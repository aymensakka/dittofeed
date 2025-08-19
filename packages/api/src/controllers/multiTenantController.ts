import { Type, TypeBoxTypeProvider } from "@fastify/type-provider-typebox";
import backendConfig from "backend-lib/src/config";
import { db } from "backend-lib/src/db";
import * as schema from "backend-lib/src/db/schema";
import logger from "backend-lib/src/logger";
import { SESSION_KEY } from "backend-lib/src/requestContext";
import { FastifyInstance } from "fastify";
import { randomBytes } from "crypto";
import { URL } from "url";
import { and, eq } from "drizzle-orm";

interface OAuthState {
  workspaceId?: string;
  returnUrl?: string;
  nonce: string;
}

// Store OAuth states temporarily (in production, use Redis)
const oauthStates = new Map<string, OAuthState>();

// Clean up old states periodically
setInterval(() => {
  const now = Date.now();
  for (const [key, value] of oauthStates.entries()) {
    // Remove states older than 10 minutes
    if (now - parseInt(key.split('-')[0]) > 10 * 60 * 1000) {
      oauthStates.delete(key);
    }
  }
}, 60 * 1000); // Clean every minute

export default async function multiTenantController(fastify: FastifyInstance) {
  const config = backendConfig();
  
  // OAuth2 initiate endpoint
  fastify.withTypeProvider<TypeBoxTypeProvider>().get(
    "/oauth2/initiate/:provider",
    {
      schema: {
        description: "Initiate OAuth2 flow for multi-tenant authentication",
        params: Type.Object({
          provider: Type.String(),
        }),
        querystring: Type.Object({
          workspaceId: Type.Optional(Type.String()),
          returnUrl: Type.Optional(Type.String()),
        }),
      },
    },
    async (request, reply) => {
      const { authMode, authProvider } = config;
      
      if (authMode !== "multi-tenant") {
        return reply.status(404).send({ 
          message: "Multi-tenant auth not enabled",
          error: "Not Found",
          statusCode: 404 
        });
      }

      const { provider } = request.params;
      const { workspaceId, returnUrl } = request.query;

      // Currently only support Google
      if (provider !== "google" || authProvider !== "google") {
        return reply.status(400).send({ 
          error: "Unsupported auth provider",
          supported: ["google"]
        });
      }

      const googleClientId = process.env.GOOGLE_CLIENT_ID;
      const googleClientSecret = process.env.GOOGLE_CLIENT_SECRET;
      
      if (!googleClientId || !googleClientSecret) {
        logger().error("Google OAuth credentials not configured");
        return reply.status(500).send({ 
          error: "OAuth provider not configured" 
        });
      }

      // Generate state for CSRF protection
      const nonce = randomBytes(16).toString('hex');
      const stateKey = `${Date.now()}-${nonce}`;
      const state: OAuthState = {
        workspaceId,
        returnUrl: returnUrl || "/dashboard/journeys",
        nonce,
      };
      
      oauthStates.set(stateKey, state);

      // Build Google OAuth URL
      const redirectUri = `${config.dashboardUrl || 'https://communication-api.caramelme.com'}/api/public/auth/oauth2/callback/google`;
      
      const googleAuthUrl = new URL('https://accounts.google.com/o/oauth2/v2/auth');
      googleAuthUrl.searchParams.append('client_id', googleClientId);
      googleAuthUrl.searchParams.append('redirect_uri', redirectUri);
      googleAuthUrl.searchParams.append('response_type', 'code');
      googleAuthUrl.searchParams.append('scope', 'openid email profile');
      googleAuthUrl.searchParams.append('state', stateKey);
      googleAuthUrl.searchParams.append('access_type', 'offline');
      googleAuthUrl.searchParams.append('prompt', 'consent');

      // Redirect to Google
      return reply.redirect(302, googleAuthUrl.toString());
    }
  );

  // OAuth2 callback endpoint
  fastify.withTypeProvider<TypeBoxTypeProvider>().get(
    "/oauth2/callback/:provider",
    {
      schema: {
        description: "Handle OAuth2 callback for multi-tenant authentication",
        params: Type.Object({
          provider: Type.String(),
        }),
        querystring: Type.Object({
          code: Type.Optional(Type.String()),
          state: Type.Optional(Type.String()),
          error: Type.Optional(Type.String()),
        }),
      },
    },
    async (request, reply) => {
      const { authMode } = config;
      
      if (authMode !== "multi-tenant") {
        return reply.status(404).send({ 
          message: "Multi-tenant auth not enabled",
          error: "Not Found",
          statusCode: 404 
        });
      }

      const { provider } = request.params;
      const { code, state, error } = request.query;

      if (error) {
        logger().error({ error }, "OAuth callback error");
        return reply.redirect(302, '/dashboard/auth/error?message=' + encodeURIComponent(error));
      }

      if (!code || !state) {
        return reply.status(400).send({ error: "Missing code or state" });
      }

      // Verify state
      const storedState = oauthStates.get(state);
      if (!storedState) {
        logger().error("Invalid OAuth state");
        return reply.status(400).send({ error: "Invalid state" });
      }
      
      oauthStates.delete(state);

      if (provider !== "google") {
        return reply.status(400).send({ error: "Unsupported provider" });
      }

      const googleClientId = process.env.GOOGLE_CLIENT_ID;
      const googleClientSecret = process.env.GOOGLE_CLIENT_SECRET;
      
      if (!googleClientId || !googleClientSecret) {
        return reply.status(500).send({ error: "OAuth provider not configured" });
      }

      try {
        // Exchange code for tokens
        const redirectUri = `${config.dashboardUrl || 'https://communication-api.caramelme.com'}/api/public/auth/oauth2/callback/google`;
        
        const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: new URLSearchParams({
            code,
            client_id: googleClientId,
            client_secret: googleClientSecret,
            redirect_uri: redirectUri,
            grant_type: 'authorization_code',
          }),
        });

        if (!tokenResponse.ok) {
          const errorText = await tokenResponse.text();
          logger().error({ status: tokenResponse.status, error: errorText }, "Failed to exchange OAuth code");
          return reply.status(500).send({ error: "Failed to authenticate with Google" });
        }

        const tokens = await tokenResponse.json();
        
        // Get user info
        const userInfoResponse = await fetch('https://www.googleapis.com/oauth2/v2/userinfo', {
          headers: {
            Authorization: `Bearer ${tokens.access_token}`,
          },
        });

        if (!userInfoResponse.ok) {
          logger().error("Failed to get user info from Google");
          return reply.status(500).send({ error: "Failed to get user information" });
        }

        const userInfo = await userInfoResponse.json();
        
        // Check if user has access to workspace
        let workspaceId = storedState.workspaceId;
        
        if (!workspaceId) {
          // Find workspace member for this user email
          const member = await db()
            .select()
            .from(schema.workspaceMember)
            .where(eq(schema.workspaceMember.email, userInfo.email))
            .limit(1);
          
          if (member.length > 0) {
            // User exists, get their last workspace
            workspaceId = member[0].lastWorkspaceId;
            
            if (!workspaceId) {
              // Find any workspace this user has access to via WorkspaceMemberRole
              const memberRole = await db()
                .select()
                .from(schema.workspaceMemberRole)
                .where(eq(schema.workspaceMemberRole.workspaceMemberId, member[0].id))
                .limit(1);
              
              if (memberRole.length > 0) {
                workspaceId = memberRole[0].workspaceId;
              }
            }
          }
          
          if (!workspaceId) {
            // Check if there's a default workspace
            const defaultWorkspace = await db()
              .select()
              .from(schema.workspace)
              .where(eq(schema.workspace.type, "Root"))
              .limit(1);
            
            if (defaultWorkspace.length > 0) {
              workspaceId = defaultWorkspace[0].id;
              
              // Create or update workspace member
              const existingMember = await db()
                .select()
                .from(schema.workspaceMember)
                .where(eq(schema.workspaceMember.email, userInfo.email))
                .limit(1);
              
              let memberId: string;
              
              if (existingMember.length === 0) {
                // Create new member
                const newMember = await db()
                  .insert(schema.workspaceMember)
                  .values({
                    email: userInfo.email,
                    name: userInfo.name || userInfo.email,
                    emailVerified: true,
                    image: userInfo.picture,
                    lastWorkspaceId: workspaceId,
                  })
                  .returning();
                
                memberId = newMember[0].id;
              } else {
                memberId = existingMember[0].id;
                
                // Update member's last workspace
                await db()
                  .update(schema.workspaceMember)
                  .set({
                    lastWorkspaceId: workspaceId,
                    name: userInfo.name || existingMember[0].name,
                    image: userInfo.picture || existingMember[0].image,
                    emailVerified: true,
                  })
                  .where(eq(schema.workspaceMember.id, memberId));
              }
              
              // Add workspace member role if not exists
              const existingRole = await db()
                .select()
                .from(schema.workspaceMemberRole)
                .where(
                  and(
                    eq(schema.workspaceMemberRole.workspaceMemberId, memberId),
                    eq(schema.workspaceMemberRole.workspaceId, workspaceId)
                  )
                )
                .limit(1);
              
              if (existingRole.length === 0) {
                await db()
                  .insert(schema.workspaceMemberRole)
                  .values({
                    workspaceMemberId: memberId,
                    workspaceId: workspaceId,
                    role: "Admin", // You might want to make this configurable
                  });
              }
            } else {
              logger().error({ email: userInfo.email }, "No workspace found for user");
              return reply.redirect(302, '/dashboard/auth/error?message=' + encodeURIComponent('No workspace access'));
            }
          }
        }

        // Set session
        request.session.set(SESSION_KEY, {
          email: userInfo.email,
          name: userInfo.name,
          picture: userInfo.picture,
          workspaceId,
          provider: 'google',
        });

        // Redirect to dashboard
        const dashboardUrl = config.dashboardUrl || 'https://communication-dashboard.caramelme.com';
        const returnUrl = storedState.returnUrl || '/dashboard/journeys';
        
        return reply.redirect(302, dashboardUrl + returnUrl);
        
      } catch (error) {
        logger().error({ error }, "OAuth callback error");
        return reply.status(500).send({ error: "Authentication failed" });
      }
    }
  );

  // Session check endpoint
  fastify.withTypeProvider<TypeBoxTypeProvider>().get(
    "/session",
    {
      schema: {
        description: "Check current session status",
      },
    },
    async (request, reply) => {
      const session = request.session.get(SESSION_KEY);
      
      if (!session) {
        return reply.status(401).send({ 
          authenticated: false 
        });
      }

      return reply.send({
        authenticated: true,
        user: {
          email: session.email,
          name: session.name,
          picture: session.picture,
          workspaceId: session.workspaceId,
        },
      });
    }
  );

  // Signout endpoint
  fastify.withTypeProvider<TypeBoxTypeProvider>().post(
    "/signout",
    {
      schema: {
        description: "Sign out in multi-tenant auth mode",
      },
    },
    async (request, reply) => {
      const { authMode } = config;
      
      if (authMode !== "multi-tenant") {
        return reply.status(404).send();
      }
      
      request.session.delete();
      
      return reply.send({ 
        success: true,
        redirectUrl: '/dashboard/auth/login',
      });
    }
  );
}
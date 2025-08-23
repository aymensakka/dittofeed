import { Type, TypeBoxTypeProvider } from "@fastify/type-provider-typebox";
import backendConfig from "backend-lib/src/config";
import { db } from "backend-lib/src/db";
import * as schema from "backend-lib/src/db/schema";
import logger from "backend-lib/src/logger";
import { SESSION_KEY } from "backend-lib/src/requestContext";
import { generateJwtToken } from "backend-lib/src/auth";
import { OpenIdProfile } from "backend-lib/src/types";
import { FastifyInstance } from "fastify";
import { randomBytes } from "crypto";
import { URL } from "url";
import { and, eq, sql } from "drizzle-orm";

// Declare global type for auth tokens
declare global {
  var authTokens: Map<string, any> | undefined;
}

interface OAuthState {
  workspaceId?: string;
  returnUrl?: string;
  nonce: string;
}

interface GoogleUserInfo {
  email: string;
  name?: string;
  picture?: string;
  id: string;
}

interface GoogleTokenResponse {
  access_token: string;
  refresh_token?: string;
  expires_in: number;
  token_type: string;
}

// Store OAuth states temporarily (in production, use Redis)
const oauthStates = new Map<string, OAuthState>();

// Clean up old states periodically
setInterval(() => {
  const now = Date.now();
  for (const [key, value] of oauthStates.entries()) {
    // Remove states older than 10 minutes
    const timestamp = key.split('-')[0];
    if (timestamp && now - parseInt(timestamp) > 10 * 60 * 1000) {
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
      
      logger().info({ 
        clientId: googleClientId,
        hasSecret: !!googleClientSecret 
      }, "Using Google OAuth credentials");
      
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
      // Use the request's host to build the redirect URI dynamically
      const protocol = request.headers['x-forwarded-proto'] || 'http';
      const host = request.headers['x-forwarded-host'] || request.headers.host || 'localhost:3001';
      const redirectUri = `${protocol}://${host}/api/public/auth/oauth2/callback/google`;
      
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

      logger().info({ 
        provider, 
        hasCode: !!code, 
        hasState: !!state,
        error 
      }, "OAuth callback received");

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
        logger().error({ state, availableStates: Array.from(oauthStates.keys()) }, "Invalid OAuth state");
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
        // Use the request's host to build the redirect URI dynamically
        const protocol = request.headers['x-forwarded-proto'] || 'http';
        const host = request.headers['x-forwarded-host'] || request.headers.host || 'localhost:3001';
        const redirectUri = `${protocol}://${host}/api/public/auth/oauth2/callback/google`;
        
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

        const tokens = await tokenResponse.json() as GoogleTokenResponse;
        
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

        const userInfo = await userInfoResponse.json() as GoogleUserInfo;
        
        logger().info({ 
          email: userInfo.email,
          name: userInfo.name,
          googleId: userInfo.id 
        }, "Got user info from Google");
        
        // Check if user has access to workspace
        let workspaceId: string | undefined = storedState.workspaceId;
        
        if (!workspaceId) {
          // Find workspace member for this user email - using raw SQL due to schema mismatch
          const memberResult = await db().execute(sql`
            SELECT * FROM "WorkspaceMember" 
            WHERE email = ${userInfo.email} 
            LIMIT 1
          `);
          const member = memberResult.rows;
          
          if (member.length > 0 && member[0]) {
            // User exists, get their last workspace
            const lastWorkspaceId = member[0].lastWorkspaceId;
            if (lastWorkspaceId && typeof lastWorkspaceId === 'string') {
              workspaceId = lastWorkspaceId;
            }
            
            if (!workspaceId) {
              // Find any workspace this user has access to via WorkspaceMemberRole
              const memberId = member[0].id as string;
              const memberRole = await db()
                .select()
                .from(schema.workspaceMemberRole)
                .where(eq(schema.workspaceMemberRole.workspaceMemberId, memberId))
                .limit(1);
              
              if (memberRole.length > 0 && memberRole[0]) {
                workspaceId = memberRole[0].workspaceId;
              }
            }
          }
          
          if (!workspaceId) {
            // No workspace access - redirect to error page
            const domain = userInfo.email.split('@')[1];
            logger().warn({ 
              email: userInfo.email, 
              domain 
            }, "User does not belong to any organization");
            
            // Redirect to an error page with a clear message
            const errorMessage = `Your email ${userInfo.email} does not belong to any registered organization. Please contact your administrator to get access.`;
            return reply.redirect(302, `/dashboard/auth/no-organization?email=${encodeURIComponent(userInfo.email)}&message=${encodeURIComponent(errorMessage)}`);
          }
        }

        // Set session
        if (!workspaceId) {
          logger().error({ email: userInfo.email }, "No workspace found for user after creation");
          return reply.redirect(302, '/dashboard/auth/error?message=' + encodeURIComponent('Failed to assign workspace'));
        }
        
        // Check if session is available
        if (!request.session || typeof request.session.set !== 'function') {
          logger().error("Session not available on request");
          return reply.status(500).send({ error: "Session configuration error" });
        }
        
        // Generate JWT token for the authenticated user
        const jwtProfile: OpenIdProfile = {
          sub: userInfo.id,
          email: userInfo.email,
          email_verified: true,
          name: userInfo.name,
          nickname: userInfo.email.split('@')[0],
          picture: userInfo.picture,
        };
        
        logger().info({ 
          email: jwtProfile.email,
          sub: jwtProfile.sub,
          workspaceId 
        }, "Generating JWT token for user");
        
        let jwtToken: string;
        try {
          jwtToken = generateJwtToken(jwtProfile);
          logger().info({ tokenLength: jwtToken.length }, "JWT token generated successfully");
        } catch (jwtError) {
          logger().error({ 
            jwtError,
            jwtErrorMessage: jwtError instanceof Error ? jwtError.message : String(jwtError),
            jwtProfile 
          }, "Failed to generate JWT token");
          throw new Error(`JWT generation failed: ${jwtError instanceof Error ? jwtError.message : String(jwtError)}`);
        }
        
        // Set session on API side (for session-based checks)
        const sessionData = {
          email: userInfo.email,
          name: userInfo.name || '',
          picture: userInfo.picture || '',
          workspaceId,
          provider: 'google',
        };
        
        if (request.session && typeof request.session.set === 'function') {
          request.session.set(SESSION_KEY, sessionData);
        }
        
        // Create a temporary auth token that includes the JWT
        const crypto = require('crypto');
        const authToken = crypto.randomBytes(32).toString('hex');
        
        // Store the auth token with JWT temporarily (in production, use Redis)
        if (!global.authTokens) {
          global.authTokens = new Map();
        }
        global.authTokens.set(authToken, {
          ...sessionData,
          jwt: jwtToken,
        });
        
        logger().info({ 
          authToken,
          tokenCount: global.authTokens.size,
          hasJwt: true 
        }, "Created auth token with JWT");
        
        // Clean up old tokens after 5 minutes
        setTimeout(() => global.authTokens?.delete(authToken), 5 * 60 * 1000);
        
        // Redirect to dashboard with auth token
        let dashboardUrl = config.dashboardUrl || 'http://localhost:3000';
        const returnUrl = storedState.returnUrl || '/dashboard/journeys';
        
        const redirectUrl = `${dashboardUrl}/dashboard/api/auth/callback?token=${authToken}&returnUrl=${encodeURIComponent(returnUrl)}`;
        logger().info({ redirectUrl }, "Redirecting to dashboard with JWT");
        
        // Don't include /dashboard in the URL since it's the basePath
        return reply.redirect(302, redirectUrl);
        
      } catch (error) {
        logger().error({ 
          error,
          errorMessage: error instanceof Error ? error.message : String(error),
          errorStack: error instanceof Error ? error.stack : undefined 
        }, "OAuth callback error");
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
      // Check if session is available
      if (!request.session || typeof request.session.get !== 'function') {
        return reply.status(401).send({ 
          authenticated: false 
        });
      }
      
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

  // Token exchange endpoint
  fastify.withTypeProvider<TypeBoxTypeProvider>().post(
    "/auth/exchange",
    {
      schema: {
        description: "Exchange auth token for session data",
        body: Type.Object({
          token: Type.String(),
        }),
      },
    },
    async (request, reply) => {
      const { token } = request.body;
      
      logger().info({ token }, "Token exchange requested");
      
      // Get the auth token data
      if (!global.authTokens) {
        logger().error("No authTokens map found");
        return reply.status(400).send({ error: "Invalid token" });
      }
      
      logger().info({ 
        tokenCount: global.authTokens.size,
        tokens: Array.from(global.authTokens.keys())
      }, "Available tokens");
      
      const sessionData = global.authTokens.get(token);
      if (!sessionData) {
        logger().error({ token }, "Token not found or expired");
        return reply.status(400).send({ error: "Invalid or expired token" });
      }
      
      logger().info({ sessionData }, "Found session data for token");
      
      // Delete the token after use
      global.authTokens.delete(token);
      
      return reply.send({
        success: true,
        session: sessionData,
        jwt: sessionData.jwt,
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
      
      // Check if session is available before deleting
      if (request.session && typeof request.session.delete === 'function') {
        request.session.delete();
      }
      
      return reply.send({ 
        success: true,
        redirectUrl: '/dashboard/auth/login',
      });
    }
  );
}
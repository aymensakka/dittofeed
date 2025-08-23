import { TypeBoxTypeProvider } from "@fastify/type-provider-typebox";
import { Type } from "@sinclair/typebox";
import { db } from "backend-lib/src/db";
import * as schema from "backend-lib/src/db/schema";
import { DittofeedFastifyInstance } from "backend-lib/src/types";
import { createSigner, createVerifier } from "fast-jwt";
import { eq, and, lt, isNull } from "drizzle-orm";
import logger from "backend-lib/src/logger";
import { v4 as uuidv4 } from "uuid";
import backendConfig from "backend-lib/src/config";
import crypto from "crypto";

// Request/Response types
const CreateSessionRequest = Type.Object({
  workspaceId: Type.String(),
});

const CreateSessionResponse = Type.Object({
  accessToken: Type.String(),
  refreshToken: Type.String(),
  expiresIn: Type.Number(),
  tokenType: Type.String(),
});

const RefreshTokenRequest = Type.Object({
  refreshToken: Type.String(),
});

const RefreshTokenResponse = Type.Object({
  accessToken: Type.String(),
  refreshToken: Type.String(),
  expiresIn: Type.Number(),
  tokenType: Type.String(),
});

const VerifySessionRequest = Type.Object({
  token: Type.String(),
});

const VerifySessionResponse = Type.Object({
  valid: Type.Boolean(),
  workspaceId: Type.Optional(Type.String()),
  sessionId: Type.Optional(Type.String()),
  expiresAt: Type.Optional(Type.String()),
});

const RevokeSessionRequest = Type.Object({
  sessionId: Type.Optional(Type.String()),
  refreshToken: Type.Optional(Type.String()),
});

// Constants
const ACCESS_TOKEN_EXPIRY_MS = 15 * 60 * 1000; // 15 minutes
const REFRESH_TOKEN_EXPIRY_MS = 7 * 24 * 60 * 60 * 1000; // 7 days
const REFRESH_TOKEN_ABSOLUTE_EXPIRY_MS = 30 * 24 * 60 * 60 * 1000; // 30 days

// JWT configuration
const getJwtSecret = () => {
  try {
    const config = backendConfig();
    return config.jwtSecret || process.env.JWT_SECRET || 'zzy3ZOlTJp3PoQjdPhxCJ9piDAFcIlYnM3nBOmXpGhA=';
  } catch (error) {
    return process.env.JWT_SECRET || 'zzy3ZOlTJp3PoQjdPhxCJ9piDAFcIlYnM3nBOmXpGhA=';
  }
};

const signAccessToken = createSigner({ 
  key: getJwtSecret(),
  expiresIn: ACCESS_TOKEN_EXPIRY_MS
});

const verifyAccessToken = createVerifier({
  key: getJwtSecret(),
  cache: true,
  cacheTTL: 100000
});

// Helper functions
function generateRefreshToken(): string {
  return crypto.randomBytes(32).toString('base64url');
}

function hashToken(token: string): string {
  return crypto.createHash('sha256').update(token).digest('hex');
}

async function createSession(
  workspaceId: string, 
  metadata?: {
    ipAddress?: string;
    userAgent?: string;
    fingerprint?: string;
  }
) {
  const sessionId = uuidv4();
  const refreshToken = generateRefreshToken();
  const refreshTokenFamily = uuidv4();
  const now = new Date();
  const expiresAt = new Date(now.getTime() + ACCESS_TOKEN_EXPIRY_MS);
  const refreshExpiresAt = new Date(now.getTime() + REFRESH_TOKEN_EXPIRY_MS);
  const absoluteExpiresAt = new Date(now.getTime() + REFRESH_TOKEN_ABSOLUTE_EXPIRY_MS);

  // Create access token
  const accessToken = signAccessToken({
    sessionId,
    workspaceId,
    type: "embedded-access",
  });

  const accessTokenHash = hashToken(accessToken);

  // Store session in database
  await db().insert(schema.embeddedSession).values({
    id: uuidv4(),
    sessionId,
    workspaceId,
    refreshToken,
    refreshTokenFamily,
    accessTokenHash,
    previousAccessTokenHash: null,
    createdAt: now,
    lastRefreshedAt: now,
    expiresAt,
    refreshExpiresAt: absoluteExpiresAt, // Absolute expiry
    revokedAt: null,
    revocationReason: null,
    metadata: metadata || {},
    refreshCount: 0,
    ipAddress: metadata?.ipAddress || null,
    userAgent: metadata?.userAgent || null,
    fingerprint: metadata?.fingerprint || null,
  });

  // Audit log
  await db().insert(schema.embeddedSessionAudit).values({
    id: uuidv4(),
    sessionId,
    workspaceId,
    action: 'created',
    timestamp: now,
    ipAddress: metadata?.ipAddress || null,
    userAgent: metadata?.userAgent || null,
    metadata: metadata || {},
    success: true,
    failureReason: null,
  });

  return {
    accessToken,
    refreshToken,
    expiresIn: ACCESS_TOKEN_EXPIRY_MS / 1000, // Convert to seconds
    sessionId,
  };
}

async function refreshSession(
  refreshToken: string,
  metadata?: {
    ipAddress?: string;
    userAgent?: string;
    fingerprint?: string;
  }
) {
  const now = new Date();
  
  // Find session by refresh token
  const session = await db().query.embeddedSession.findFirst({
    where: and(
      eq(schema.embeddedSession.refreshToken, refreshToken),
      isNull(schema.embeddedSession.revokedAt),
      lt(now, schema.embeddedSession.refreshExpiresAt)
    ),
  });

  if (!session) {
    // Check if this is a reused token
    const oldSession = await db().query.embeddedSession.findFirst({
      where: eq(schema.embeddedSession.refreshToken, refreshToken),
    });

    if (oldSession) {
      // Token reuse detected - revoke entire token family
      await db()
        .update(schema.embeddedSession)
        .set({
          revokedAt: now,
          revocationReason: 'token_reuse',
        })
        .where(eq(schema.embeddedSession.refreshTokenFamily, oldSession.refreshTokenFamily));

      // Audit log
      await db().insert(schema.embeddedSessionAudit).values({
        id: uuidv4(),
        sessionId: oldSession.sessionId,
        workspaceId: oldSession.workspaceId,
        action: 'reuse_detected',
        timestamp: now,
        ipAddress: metadata?.ipAddress || null,
        userAgent: metadata?.userAgent || null,
        metadata: { ...metadata, refreshTokenFamily: oldSession.refreshTokenFamily },
        success: false,
        failureReason: 'Token reuse detected',
      });
    }
    
    throw new Error('Invalid or expired refresh token');
  }

  // Generate new tokens
  const newRefreshToken = generateRefreshToken();
  const newAccessToken = signAccessToken({
    sessionId: session.sessionId,
    workspaceId: session.workspaceId,
    type: "embedded-access",
  });

  const newAccessTokenHash = hashToken(newAccessToken);
  const expiresAt = new Date(now.getTime() + ACCESS_TOKEN_EXPIRY_MS);

  // Update session with new tokens
  await db()
    .update(schema.embeddedSession)
    .set({
      refreshToken: newRefreshToken,
      accessTokenHash: newAccessTokenHash,
      previousAccessTokenHash: session.accessTokenHash, // Keep previous for grace period
      lastRefreshedAt: now,
      expiresAt,
      refreshCount: session.refreshCount + 1,
      ipAddress: metadata?.ipAddress || session.ipAddress,
      userAgent: metadata?.userAgent || session.userAgent,
      fingerprint: metadata?.fingerprint || session.fingerprint,
    })
    .where(eq(schema.embeddedSession.id, session.id));

  // Audit log
  await db().insert(schema.embeddedSessionAudit).values({
    id: uuidv4(),
    sessionId: session.sessionId,
    workspaceId: session.workspaceId,
    action: 'refreshed',
    timestamp: now,
    ipAddress: metadata?.ipAddress || null,
    userAgent: metadata?.userAgent || null,
    metadata: { ...metadata, refreshCount: session.refreshCount + 1 },
    success: true,
    failureReason: null,
  });

  return {
    accessToken: newAccessToken,
    refreshToken: newRefreshToken,
    expiresIn: ACCESS_TOKEN_EXPIRY_MS / 1000,
    sessionId: session.sessionId,
  };
}

export default async function embeddedSessionsController(
  fastify: DittofeedFastifyInstance,
) {
  // Create session endpoint - requires write key authentication
  fastify.withTypeProvider<TypeBoxTypeProvider>().post(
    "/create",
    {
      schema: {
        description: "Create an embedded session with refresh token",
        tags: ["Sessions", "Embedded"],
        body: CreateSessionRequest,
        response: {
          200: CreateSessionResponse,
          401: Type.Object({ error: Type.String() }),
          403: Type.Object({ error: Type.String() }),
        },
      },
    },
    async (request, reply) => {
      try {
        const { workspaceId } = request.body;
        
        // Get the authorization header
        const authHeader = request.headers.authorization;
        if (!authHeader) {
          return reply.status(401).send({ error: "Missing authorization header" });
        }

        // Parse write key
        let writeKey: string;
        if (authHeader.startsWith("Basic ")) {
          const base64Credentials = authHeader.substring(6);
          const credentials = Buffer.from(base64Credentials, 'base64').toString('utf-8');
          const [key] = credentials.split(':');
          writeKey = key || '';
        } else if (authHeader.startsWith("Bearer ")) {
          writeKey = authHeader.substring(7);
        } else {
          return reply.status(401).send({ error: "Invalid authorization format" });
        }

        // Verify the workspace exists and the write key is valid
        const workspace = await db().query.workspace.findFirst({
          where: eq(schema.workspace.id, workspaceId),
        });

        if (!workspace) {
          return reply.status(403).send({ error: "Invalid workspace" });
        }

        // For child workspaces, verify the write key matches
        if (workspace.type === "Child") {
          const secret = await db().query.secret.findFirst({
            where: eq(schema.secret.workspaceId, workspaceId),
          });

          if (!secret || secret.value !== writeKey) {
            return reply.status(403).send({ error: "Invalid write key" });
          }
        }

        // Extract metadata
        const metadata = {
          ipAddress: request.ip,
          userAgent: request.headers['user-agent'],
          fingerprint: request.headers['x-fingerprint'] as string | undefined,
        };

        // Create session with refresh token
        const session = await createSession(workspaceId, metadata);

        logger().info({
          workspaceId,
          sessionId: session.sessionId,
          message: "Created embedded session with refresh token",
        });

        return reply.status(200).send({
          accessToken: session.accessToken,
          refreshToken: session.refreshToken,
          expiresIn: session.expiresIn,
          tokenType: "Bearer",
        });
      } catch (error) {
        logger().error({
          error,
          message: "Failed to create session",
        });
        return reply.status(500).send({ error: "Internal server error" });
      }
    },
  );

  // Refresh token endpoint
  fastify.withTypeProvider<TypeBoxTypeProvider>().post(
    "/refresh",
    {
      schema: {
        description: "Refresh an access token using a refresh token",
        tags: ["Sessions", "Embedded"],
        body: RefreshTokenRequest,
        response: {
          200: RefreshTokenResponse,
          401: Type.Object({ error: Type.String() }),
        },
      },
    },
    async (request, reply) => {
      try {
        const { refreshToken } = request.body;
        
        // Extract metadata
        const metadata = {
          ipAddress: request.ip,
          userAgent: request.headers['user-agent'],
          fingerprint: request.headers['x-fingerprint'] as string | undefined,
        };

        const session = await refreshSession(refreshToken, metadata);

        logger().info({
          sessionId: session.sessionId,
          message: "Refreshed embedded session token",
        });

        return reply.status(200).send({
          accessToken: session.accessToken,
          refreshToken: session.refreshToken,
          expiresIn: session.expiresIn,
          tokenType: "Bearer",
        });
      } catch (error) {
        logger().error({
          error,
          message: "Failed to refresh session",
        });
        return reply.status(401).send({ error: "Invalid or expired refresh token" });
      }
    },
  );

  // Verify session endpoint - public, used by embedded components
  fastify.withTypeProvider<TypeBoxTypeProvider>().post(
    "/verify",
    {
      schema: {
        description: "Verify an embedded access token",
        tags: ["Sessions", "Embedded"],
        body: VerifySessionRequest,
        response: {
          200: VerifySessionResponse,
        },
      },
    },
    async (request, reply) => {
      try {
        const { token } = request.body;
        
        const decoded = verifyAccessToken(token) as {
          sessionId: string;
          workspaceId: string;
          type: string;
          exp: number;
        };

        // Check if token type is correct
        if (decoded.type !== "embedded-access") {
          return reply.status(200).send({ valid: false });
        }

        // Check if session is still valid in database
        const tokenHash = hashToken(token);
        const session = await db().query.embeddedSession.findFirst({
          where: and(
            eq(schema.embeddedSession.sessionId, decoded.sessionId),
            isNull(schema.embeddedSession.revokedAt),
            // Accept either current or previous token (grace period)
            or(
              eq(schema.embeddedSession.accessTokenHash, tokenHash),
              eq(schema.embeddedSession.previousAccessTokenHash, tokenHash)
            )
          ),
        });

        if (!session) {
          return reply.status(200).send({ valid: false });
        }

        const expiresAt = new Date(decoded.exp * 1000);
        return reply.status(200).send({
          valid: true,
          workspaceId: decoded.workspaceId,
          sessionId: decoded.sessionId,
          expiresAt: expiresAt.toISOString(),
        });
      } catch (error) {
        // Token verification failed
        return reply.status(200).send({ valid: false });
      }
    },
  );

  // Revoke session endpoint
  fastify.withTypeProvider<TypeBoxTypeProvider>().post(
    "/revoke",
    {
      schema: {
        description: "Revoke an embedded session",
        tags: ["Sessions", "Embedded"],
        body: RevokeSessionRequest,
        response: {
          200: Type.Object({ success: Type.Boolean() }),
          401: Type.Object({ error: Type.String() }),
        },
      },
    },
    async (request, reply) => {
      try {
        const { sessionId, refreshToken } = request.body;
        
        if (!sessionId && !refreshToken) {
          return reply.status(401).send({ error: "Session ID or refresh token required" });
        }

        const now = new Date();
        let session;

        if (refreshToken) {
          session = await db().query.embeddedSession.findFirst({
            where: eq(schema.embeddedSession.refreshToken, refreshToken),
          });
        } else if (sessionId) {
          session = await db().query.embeddedSession.findFirst({
            where: eq(schema.embeddedSession.sessionId, sessionId),
          });
        }

        if (!session) {
          return reply.status(401).send({ error: "Session not found" });
        }

        // Revoke the session
        await db()
          .update(schema.embeddedSession)
          .set({
            revokedAt: now,
            revocationReason: 'manual',
          })
          .where(eq(schema.embeddedSession.id, session.id));

        // Audit log
        await db().insert(schema.embeddedSessionAudit).values({
          id: uuidv4(),
          sessionId: session.sessionId,
          workspaceId: session.workspaceId,
          action: 'revoked',
          timestamp: now,
          ipAddress: request.ip,
          userAgent: request.headers['user-agent'],
          metadata: {},
          success: true,
          failureReason: null,
        });

        logger().info({
          sessionId: session.sessionId,
          message: "Revoked embedded session",
        });

        return reply.status(200).send({ success: true });
      } catch (error) {
        logger().error({
          error,
          message: "Failed to revoke session",
        });
        return reply.status(500).send({ error: "Internal server error" });
      }
    },
  );
}

// Add missing import
import { or } from "drizzle-orm";
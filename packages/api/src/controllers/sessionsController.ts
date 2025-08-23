import { TypeBoxTypeProvider } from "@fastify/type-provider-typebox";
import { Type } from "@sinclair/typebox";
import { db } from "backend-lib/src/db";
import * as schema from "backend-lib/src/db/schema";
import { DittofeedFastifyInstance } from "backend-lib/src/types";
import { createSigner, createVerifier } from "fast-jwt";
import { eq } from "drizzle-orm";
import logger from "backend-lib/src/logger";
import { v4 as uuidv4 } from "uuid";
import backendConfig from "backend-lib/src/config";

// Request/Response types
const CreateSessionRequest = Type.Object({
  workspaceId: Type.String(),
});

const CreateSessionResponse = Type.Object({
  token: Type.String(),
  expiresAt: Type.String(),
});

const VerifySessionRequest = Type.Object({
  token: Type.String(),
});

const VerifySessionResponse = Type.Object({
  valid: Type.Boolean(),
  workspaceId: Type.Optional(Type.String()),
  expiresAt: Type.Optional(Type.String()),
});

// Create JWT signer and verifier with 1 hour expiration
const getJwtSecret = () => {
  try {
    const config = backendConfig();
    return config.jwtSecret || process.env.JWT_SECRET || 'zzy3ZOlTJp3PoQjdPhxCJ9piDAFcIlYnM3nBOmXpGhA=';
  } catch (error) {
    // Fallback to environment variable if config fails
    return process.env.JWT_SECRET || 'zzy3ZOlTJp3PoQjdPhxCJ9piDAFcIlYnM3nBOmXpGhA=';
  }
};

const signToken = createSigner({ 
  key: getJwtSecret(),
  expiresIn: 3600000 // 1 hour in milliseconds
});

const verifyToken = createVerifier({
  key: getJwtSecret(),
  cache: true,
  cacheTTL: 100000
});

export default async function sessionsController(
  fastify: DittofeedFastifyInstance,
) {
  // Create session endpoint - requires write key authentication
  fastify.withTypeProvider<TypeBoxTypeProvider>().post(
    "/",
    {
      schema: {
        description: "Create an embedded session token for a workspace",
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

        // Parse write key from Basic auth
        let writeKey: string;
        if (authHeader.startsWith("Basic ")) {
          // Decode base64 and extract the write key (username part)
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

        // Create session token
        const sessionId = uuidv4();
        const expiresAt = new Date(Date.now() + 3600000); // 1 hour from now
        
        const token = signToken({
          sessionId,
          workspaceId,
          type: "embedded-session",
          expiresAt: expiresAt.toISOString(),
        });

        logger().info({
          workspaceId,
          sessionId,
          message: "Created embedded session token",
        });

        return reply.status(200).send({
          token,
          expiresAt: expiresAt.toISOString(),
        });
      } catch (error) {
        logger().error({
          error,
          message: "Failed to create session token",
        });
        return reply.status(500).send({ error: "Internal server error" });
      }
    },
  );

  // Verify session endpoint - public, used by embedded components
  fastify.withTypeProvider<TypeBoxTypeProvider>().post(
    "/verify",
    {
      schema: {
        description: "Verify an embedded session token",
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
        
        const decoded = await verifyToken(token) as {
          sessionId: string;
          workspaceId: string;
          type: string;
          expiresAt: string;
        };

        // Check if token type is correct
        if (decoded.type !== "embedded-session") {
          return reply.status(200).send({ valid: false });
        }

        // Check if token is expired
        const expiresAt = new Date(decoded.expiresAt);
        if (expiresAt < new Date()) {
          return reply.status(200).send({ valid: false });
        }

        return reply.status(200).send({
          valid: true,
          workspaceId: decoded.workspaceId,
          expiresAt: decoded.expiresAt,
        });
      } catch (error) {
        // Token verification failed
        return reply.status(200).send({ valid: false });
      }
    },
  );
}
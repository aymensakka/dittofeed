import { TypeBoxTypeProvider } from "@fastify/type-provider-typebox";
import { Type } from "@sinclair/typebox";
import { db } from "backend-lib/src/db";
import * as schema from "backend-lib/src/db/schema";
import logger from "backend-lib/src/logger";
import {
  getWorkspaceQuota,
  upsertWorkspaceQuota,
  validateWorkspaceQuota,
} from "backend-lib/src/multitenancy/resourceQuotas";
import { eq } from "drizzle-orm";
import { FastifyInstance } from "fastify";
import {
  EmptyResponse,
  GetWorkspaceQuotaRequest,
  GetWorkspaceQuotaResponse,
  QuotaValidationRequest,
  QuotaValidationResponse,
  UpsertWorkspaceQuotaRequest,
  WorkspaceQuota,
} from "isomorphic-lib/src/types";

/**
 * Quotas Controller
 * 
 * Provides CRUD operations for workspace quotas and quota validation endpoints.
 * Follows the same patterns as segmentsController.ts for consistency.
 */

// eslint-disable-next-line @typescript-eslint/require-await
export default async function quotasController(fastify: FastifyInstance) {
  // GET /quotas - Get workspace quota
  fastify.withTypeProvider<TypeBoxTypeProvider>().get(
    "/",
    {
      schema: {
        description: "Get workspace quota settings.",
        tags: ["Quotas"],
        querystring: GetWorkspaceQuotaRequest,
        response: {
          200: GetWorkspaceQuotaResponse,
        },
      },
    },
    async (request, reply) => {
      const { workspaceId } = request.query;

      try {
        const quota = await getWorkspaceQuota(workspaceId);

        logger().debug(
          { workspaceId, quotaFound: !!quota },
          "Retrieved workspace quota"
        );

        return reply.status(200).send({ quota });
      } catch (error) {
        logger().error(
          { error, workspaceId },
          "Failed to get workspace quota"
        );
        return reply.status(500).send();
      }
    },
  );

  // PUT /quotas - Create or update workspace quota
  fastify.withTypeProvider<TypeBoxTypeProvider>().put(
    "/",
    {
      schema: {
        description: "Create or update workspace quota settings.",
        tags: ["Quotas"],
        body: UpsertWorkspaceQuotaRequest,
        response: {
          200: Type.Object({ quota: WorkspaceQuota }),
          400: EmptyResponse,
          500: EmptyResponse,
        },
      },
    },
    async (request, reply) => {
      const quotaData = request.body;

      try {
        const result = await upsertWorkspaceQuota(
          quotaData.workspaceId,
          {
            maxUsers: quotaData.maxUsers,
            maxSegments: quotaData.maxSegments,
            maxJourneys: quotaData.maxJourneys,
            maxTemplates: quotaData.maxTemplates,
            maxStorageBytes: quotaData.maxStorageBytes,
            maxMessagesPerMonth: quotaData.maxMessagesPerMonth,
          }
        );

        if (result.isErr()) {
          logger().error(
            { error: result.error, quotaData },
            "Failed to upsert workspace quota"
          );
          return reply.status(400).send();
        }

        logger().info(
          { workspaceId: quotaData.workspaceId, quota: result.value },
          "Successfully upserted workspace quota"
        );

        return reply.status(200).send({ quota: result.value });
      } catch (error) {
        logger().error(
          { error, quotaData },
          "Unexpected error during quota upsert"
        );
        return reply.status(500).send();
      }
    },
  );

  // DELETE /quotas - Delete workspace quota (revert to defaults)
  fastify.withTypeProvider<TypeBoxTypeProvider>().delete(
    "/",
    {
      schema: {
        description: "Delete workspace quota settings (revert to defaults).",
        tags: ["Quotas"],
        querystring: Type.Object({
          workspaceId: Type.String({ format: "uuid" }),
        }),
        response: {
          200: EmptyResponse,
          400: EmptyResponse,
          500: EmptyResponse,
        },
      },
    },
    async (request, reply) => {
      const { workspaceId } = request.query;

      try {
        await db()
          .delete(schema.workspaceQuota)
          .where(eq(schema.workspaceQuota.workspaceId, workspaceId));

        logger().info(
          { workspaceId },
          "Deleted workspace quota (reverted to defaults)"
        );

        return reply.status(200).send();
      } catch (error) {
        logger().error(
          { error, workspaceId },
          "Failed to delete workspace quota"
        );
        return reply.status(500).send();
      }
    },
  );

  // POST /quotas/validate - Validate quota for resource creation
  fastify.withTypeProvider<TypeBoxTypeProvider>().post(
    "/validate",
    {
      schema: {
        description: "Validate if workspace can create additional resources.",
        tags: ["Quotas"],
        body: QuotaValidationRequest,
        response: {
          200: QuotaValidationResponse,
          400: EmptyResponse,
          429: Type.Object({
            error: Type.String(),
            resourceType: Type.String(),
            currentUsage: Type.Number(),
            limit: Type.Number(),
          }),
          500: EmptyResponse,
        },
      },
    },
    async (request, reply) => {
      const { workspaceId, resourceType, increment = 1 } = request.body;

      try {
        const result = await validateWorkspaceQuota(
          workspaceId,
          resourceType,
          increment
        );

        if (result.isErr()) {
          const quotaError = result.error;
          
          logger().info(
            {
              workspaceId,
              resourceType,
              increment,
              quotaError,
            },
            "Quota validation failed"
          );

          return reply.status(429).send({
            error: quotaError.message,
            resourceType: quotaError.resourceType,
            currentUsage: quotaError.currentUsage,
            limit: quotaError.limit,
          });
        }

        const validationResponse = result.value;

        logger().debug(
          {
            workspaceId,
            resourceType,
            increment,
            validationResponse,
          },
          "Quota validation successful"
        );

        return reply.status(200).send(validationResponse);
      } catch (error) {
        logger().error(
          { error, workspaceId, resourceType, increment },
          "Unexpected error during quota validation"
        );
        return reply.status(500).send();
      }
    },
  );

  // GET /quotas/usage - Get current resource usage for workspace
  fastify.withTypeProvider<TypeBoxTypeProvider>().get(
    "/usage",
    {
      schema: {
        description: "Get current resource usage for workspace.",
        tags: ["Quotas"],
        querystring: Type.Object({
          workspaceId: Type.String({ format: "uuid" }),
        }),
        response: {
          200: Type.Object({
            usage: Type.Object({
              users: Type.Number(),
              segments: Type.Number(),
              journeys: Type.Number(),
              templates: Type.Number(),
              storageBytes: Type.Number(),
              messagesThisMonth: Type.Number(),
            }),
          }),
          400: EmptyResponse,
          500: EmptyResponse,
        },
      },
    },
    async (request, reply) => {
      const { workspaceId } = request.query;

      try {
        // Get current usage counts
        const [
          segmentCount,
          journeyCount,
          messageTemplateCount,
          emailTemplateCount,
        ] = await Promise.all([
          db()
            .select({ count: schema.segment.id })
            .from(schema.segment)
            .where(eq(schema.segment.workspaceId, workspaceId)),
          
          db()
            .select({ count: schema.journey.id })
            .from(schema.journey)
            .where(eq(schema.journey.workspaceId, workspaceId)),
          
          db()
            .select({ count: schema.messageTemplate.id })
            .from(schema.messageTemplate)
            .where(eq(schema.messageTemplate.workspaceId, workspaceId)),
          
          db()
            .select({ count: schema.emailTemplate.id })
            .from(schema.emailTemplate)
            .where(eq(schema.emailTemplate.workspaceId, workspaceId)),
        ]);

        const usage = {
          users: 0, // TODO: Implement user counting
          segments: segmentCount.length,
          journeys: journeyCount.length,
          templates: messageTemplateCount.length + emailTemplateCount.length,
          storageBytes: 0, // TODO: Implement storage calculation
          messagesThisMonth: 0, // TODO: Implement message counting
        };

        logger().debug(
          { workspaceId, usage },
          "Retrieved workspace resource usage"
        );

        return reply.status(200).send({ usage });
      } catch (error) {
        logger().error(
          { error, workspaceId },
          "Failed to get workspace resource usage"
        );
        return reply.status(500).send();
      }
    },
  );
}
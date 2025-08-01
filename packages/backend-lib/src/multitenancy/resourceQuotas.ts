import { and, count, eq } from "drizzle-orm";
import { validate } from "uuid";
import { err, ok, Result } from "neverthrow";
import {
  QuotaResourceType,
  QuotaError,
  WorkspaceQuota,
  QuotaValidationResponse,
} from "isomorphic-lib/src/types";

import { db } from "../db";
import * as schema from "../db/schema";
import logger from "../logger";

/**
 * Resource quota enforcement for workspace-based multitenancy
 * 
 * This module provides functions to validate and enforce resource quotas per workspace,
 * preventing tenant abuse and ensuring fair resource allocation across workspaces.
 * Follows the same error handling patterns as backend-lib/src/auth.ts
 */

interface QuotaLimits {
  maxUsers: number;
  maxSegments: number;
  maxJourneys: number;
  maxTemplates: number;
  maxStorageBytes: number;
  maxMessagesPerMonth: number;
}

interface ResourceCounts {
  users: number;
  segments: number;
  journeys: number;
  templates: number;
  storageBytes: number;
  messagesThisMonth: number;
}

/**
 * Default quota limits for new workspaces
 * These can be overridden by creating explicit WorkspaceQuota records
 */
const DEFAULT_QUOTA_LIMITS: QuotaLimits = {
  maxUsers: 1000,
  maxSegments: 50,
  maxJourneys: 20,
  maxTemplates: 100,
  maxStorageBytes: 10 * 1024 * 1024 * 1024, // 10GB
  maxMessagesPerMonth: 100000,
};

/**
 * Get the quota limits for a workspace
 * Returns default limits if no custom quota is set
 * 
 * @param workspaceId - The UUID of the workspace
 * @returns The quota limits or null if workspace is invalid
 */
export async function getWorkspaceQuotaLimits(
  workspaceId: string
): Promise<QuotaLimits | null> {
  // Validate workspace ID format
  if (!validate(workspaceId)) {
    logger().warn({ workspaceId }, "Invalid workspace ID format");
    return null;
  }

  try {
    const quotaRecord = await db().query.workspaceQuota.findFirst({
      where: eq(schema.workspaceQuota.workspaceId, workspaceId),
    });

    if (quotaRecord) {
      return {
        maxUsers: quotaRecord.maxUsers,
        maxSegments: quotaRecord.maxSegments,
        maxJourneys: quotaRecord.maxJourneys,
        maxTemplates: quotaRecord.maxTemplates,
        maxStorageBytes: quotaRecord.maxStorageBytes,
        maxMessagesPerMonth: quotaRecord.maxMessagesPerMonth,
      };
    }

    // Return default limits if no custom quota exists
    return DEFAULT_QUOTA_LIMITS;
  } catch (error) {
    logger().error(
      { error, workspaceId },
      "Failed to get workspace quota limits"
    );
    return null;
  }
}

/**
 * Get current resource usage for a workspace
 * 
 * @param workspaceId - The UUID of the workspace
 * @returns Current resource counts or null if error
 */
export async function getCurrentResourceUsage(
  workspaceId: string
): Promise<ResourceCounts | null> {
  // Validate workspace ID format
  if (!validate(workspaceId)) {
    logger().warn({ workspaceId }, "Invalid workspace ID format");
    return null;
  }

  try {
    // Get current date for monthly message calculation
    const currentMonth = new Date();
    currentMonth.setDate(1); // First day of current month
    currentMonth.setHours(0, 0, 0, 0);

    // Execute all count queries in parallel for performance
    const [
      segmentCountResult,
      journeyCountResult,
      templateCountResult,
      // Note: User count and storage calculations would need more complex queries
      // For now, using simplified versions
    ] = await Promise.all([
      db()
        .select({ count: count() })
        .from(schema.segment)
        .where(eq(schema.segment.workspaceId, workspaceId)),
      
      db()
        .select({ count: count() })
        .from(schema.journey)
        .where(eq(schema.journey.workspaceId, workspaceId)),
      
      db()
        .select({ count: count() })
        .from(schema.messageTemplate)
        .where(eq(schema.messageTemplate.workspaceId, workspaceId)),
    ]);

    return {
      users: 0, // TODO: Implement user counting logic
      segments: segmentCountResult[0]?.count || 0,
      journeys: journeyCountResult[0]?.count || 0,
      templates: templateCountResult[0]?.count || 0,
      storageBytes: 0, // TODO: Implement storage calculation
      messagesThisMonth: 0, // TODO: Implement monthly message counting
    };
  } catch (error) {
    logger().error(
      { error, workspaceId },
      "Failed to get current resource usage"
    );
    return null;
  }
}

/**
 * Validate if a workspace can create additional resources of a given type
 * This is the main quota enforcement function used by controllers
 * 
 * @param workspaceId - The UUID of the workspace
 * @param resourceType - The type of resource being created
 * @param increment - Number of resources being added (default: 1)
 * @returns Result indicating if the operation is allowed
 */
export async function validateWorkspaceQuota(
  workspaceId: string,
  resourceType: QuotaResourceType,
  increment: number = 1
): Promise<Result<QuotaValidationResponse, QuotaError>> {
  // Validate workspace ID format
  if (!validate(workspaceId)) {
    return err({
      type: "QuotaExceeded" as const,
      message: "Invalid workspace ID format",
      resourceType,
      currentUsage: 0,
      limit: 0,
    });
  }

  // Validate increment
  if (increment < 1) {
    return err({
      type: "QuotaExceeded" as const,
      message: "Increment must be at least 1",
      resourceType,
      currentUsage: 0,
      limit: 0,
    });
  }

  try {
    // Get quota limits and current usage
    const [quotaLimits, currentUsage] = await Promise.all([
      getWorkspaceQuotaLimits(workspaceId),
      getCurrentResourceUsage(workspaceId),
    ]);

    if (!quotaLimits || !currentUsage) {
      return err({
        type: "QuotaExceeded" as const,
        message: "Failed to retrieve quota information",
        resourceType,
        currentUsage: 0,
        limit: 0,
      });
    }

    // Map resource type to current usage and limit
    const { current, limit } = getResourceValues(
      resourceType,
      currentUsage,
      quotaLimits
    );

    const newUsage = current + increment;

    // Check if the new usage would exceed the limit
    if (newUsage > limit) {
      logger().info(
        {
          workspaceId,
          resourceType,
          currentUsage: current,
          limit,
          increment,
          newUsage,
        },
        "Quota validation failed - limit exceeded"
      );

      return err({
        type: "QuotaExceeded" as const,
        message: `Quota exceeded for ${resourceType}. Current: ${current}, Limit: ${limit}, Requested: ${increment}`,
        resourceType,
        currentUsage: current,
        limit,
      });
    }

    // Quota validation passed
    logger().debug(
      {
        workspaceId,
        resourceType,
        currentUsage: current,
        limit,
        increment,
        remaining: limit - newUsage,
      },
      "Quota validation passed"
    );

    return ok({
      allowed: true,
      currentUsage: current,
      limit,
      remaining: limit - newUsage,
    });
  } catch (error) {
    logger().error(
      { error, workspaceId, resourceType, increment },
      "Error during quota validation"
    );

    return err({
      type: "QuotaExceeded" as const,
      message: "Internal error during quota validation",
      resourceType,
      currentUsage: 0,
      limit: 0,
    });
  }
}

/**
 * Get the current usage and limit values for a specific resource type
 * 
 * @param resourceType - The type of resource
 * @param usage - Current resource usage counts
 * @param limits - Workspace quota limits
 * @returns Object with current usage and limit for the resource type
 */
function getResourceValues(
  resourceType: QuotaResourceType,
  usage: ResourceCounts,
  limits: QuotaLimits
): { current: number; limit: number } {
  switch (resourceType) {
    case "Users":
      return { current: usage.users, limit: limits.maxUsers };
    case "Segments":
      return { current: usage.segments, limit: limits.maxSegments };
    case "Journeys":
      return { current: usage.journeys, limit: limits.maxJourneys };
    case "Templates":
      return { current: usage.templates, limit: limits.maxTemplates };
    case "Storage":
      return { current: usage.storageBytes, limit: limits.maxStorageBytes };
    case "Messages":
      return { current: usage.messagesThisMonth, limit: limits.maxMessagesPerMonth };
    default:
      // TypeScript should prevent this, but handle gracefully
      logger().warn({ resourceType }, "Unknown resource type in quota validation");
      return { current: 0, limit: 0 };
  }
}

/**
 * Create or update a workspace quota record
 * 
 * @param workspaceId - The UUID of the workspace
 * @param quotaLimits - The new quota limits to set
 * @returns The created/updated quota record or error
 */
export async function upsertWorkspaceQuota(
  workspaceId: string,
  quotaLimits: Partial<QuotaLimits>
): Promise<Result<WorkspaceQuota, string>> {
  // Validate workspace ID format
  if (!validate(workspaceId)) {
    return err("Invalid workspace ID format");
  }

  try {
    const now = new Date();
    
    // Check if quota already exists
    const existingQuota = await db().query.workspaceQuota.findFirst({
      where: eq(schema.workspaceQuota.workspaceId, workspaceId),
    });

    if (existingQuota) {
      // Update existing quota
      const updatedQuota = await db()
        .update(schema.workspaceQuota)
        .set({
          ...quotaLimits,
          updatedAt: now,
        })
        .where(eq(schema.workspaceQuota.workspaceId, workspaceId))
        .returning();

      logger().info(
        { workspaceId, quotaLimits },
        "Updated workspace quota"
      );

      if (updatedQuota[0]) {
        return ok({
          ...updatedQuota[0],
          createdAt: updatedQuota[0].createdAt.toISOString(),
          updatedAt: updatedQuota[0].updatedAt.toISOString(),
        } as WorkspaceQuota);
      } else {
        return err("Failed to update quota");
      }
    } else {
      // Create new quota with defaults merged with provided limits
      const newQuota = await db()
        .insert(schema.workspaceQuota)
        .values({
          workspaceId,
          ...DEFAULT_QUOTA_LIMITS,
          ...quotaLimits,
          createdAt: now,
          updatedAt: now,
        })
        .returning();

      logger().info(
        { workspaceId, quotaLimits },
        "Created new workspace quota"
      );

      if (newQuota[0]) {
        return ok({
          ...newQuota[0],
          createdAt: newQuota[0].createdAt.toISOString(),
          updatedAt: newQuota[0].updatedAt.toISOString(),
        } as WorkspaceQuota);
      } else {
        return err("Failed to create quota");
      }
    }
  } catch (error) {
    logger().error(
      { error, workspaceId, quotaLimits },
      "Failed to upsert workspace quota"
    );
    return err("Database error during quota upsert");
  }
}

/**
 * Get a workspace quota record
 * 
 * @param workspaceId - The UUID of the workspace
 * @returns The quota record or null if not found
 */
export async function getWorkspaceQuota(
  workspaceId: string
): Promise<WorkspaceQuota | null> {
  // Validate workspace ID format
  if (!validate(workspaceId)) {
    logger().warn({ workspaceId }, "Invalid workspace ID format");
    return null;
  }

  try {
    const quota = await db().query.workspaceQuota.findFirst({
      where: eq(schema.workspaceQuota.workspaceId, workspaceId),
    });

    if (!quota) return null;
    
    return {
      ...quota,
      createdAt: quota.createdAt.toISOString(),
      updatedAt: quota.updatedAt.toISOString(),
    } as WorkspaceQuota;
  } catch (error) {
    logger().error(
      { error, workspaceId },
      "Failed to get workspace quota"
    );
    return null;
  }
}
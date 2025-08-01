import { randomUUID } from "crypto";
import { and, count, eq, gte, lte, sql } from "drizzle-orm";
import { validate } from "uuid";
import { TenantMetrics } from "isomorphic-lib/src/types";

import { db } from "../db";
import * as schema from "../db/schema";
import logger from "../logger";
import { getTenantCache } from "./cache";

/**
 * Tenant metrics collection and monitoring for multi-tenant insights
 * 
 * This module tracks resource usage, performance metrics, and tenant behavior
 * to enable proactive capacity planning and usage analytics.
 */

export interface MetricsCollectionOptions {
  includeStorageMetrics?: boolean;
  includeMessageMetrics?: boolean;
  includeActiveUsers?: boolean;
}

/**
 * Collect comprehensive metrics for a specific tenant/workspace
 * 
 * @param workspaceId - The workspace to collect metrics for
 * @param options - Options for which metrics to include
 * @returns TenantMetrics object or null if workspace not found
 */
export async function collectTenantMetrics(
  workspaceId: string,
  options: MetricsCollectionOptions = {}
): Promise<TenantMetrics | null> {
  const {
    includeStorageMetrics = true,
    includeMessageMetrics = true,
    includeActiveUsers = true,
  } = options;

  // Validate workspace ID format
  if (!validate(workspaceId)) {
    logger().warn({ workspaceId }, "Invalid workspace ID format for metrics");
    return null;
  }

  try {
    // Check if workspace exists
    const workspace = await db().query.workspace.findFirst({
      where: eq(schema.workspace.id, workspaceId),
    });

    if (!workspace) {
      logger().warn({ workspaceId }, "Workspace not found for metrics collection");
      return null;
    }

    // Collect basic resource counts
    const [
      segmentCount,
      journeyCount,
      userCount,
      templateCount,
    ] = await Promise.all([
      db()
        .select({ count: count() })
        .from(schema.segment)
        .where(eq(schema.segment.workspaceId, workspaceId))
        .then(r => r[0]?.count ?? 0),
      
      db()
        .select({ count: count() })
        .from(schema.journey)
        .where(eq(schema.journey.workspaceId, workspaceId))
        .then(r => r[0]?.count ?? 0),
      
      db()
        .select({ count: count() })
        .from(schema.userProperty)
        .where(eq(schema.userProperty.workspaceId, workspaceId))
        .then(r => r[0]?.count ?? 0),
      
      db()
        .select({ count: count() })
        .from(schema.emailTemplate)
        .where(eq(schema.emailTemplate.workspaceId, workspaceId))
        .then(r => r[0]?.count ?? 0),
    ]);

    const now = new Date();
    const thirtyDaysAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);

    // Initialize metrics object
    const metrics: TenantMetrics = {
      id: randomUUID(),
      workspaceId,
      timestamp: now.toISOString(),
      userCount: userCount,
      segmentCount: segmentCount,
      journeyCount: journeyCount,
      templateCount: templateCount,
      storageUsedBytes: 0, // TODO: Implement storage calculation
      messagesThisMonth: 0, // TODO: Implement monthly message counting
      databaseQueryCount: 0, // TODO: Implement query tracking
      cacheHitRate: 0, // TODO: Implement cache hit rate calculation
    };

    // Collect message metrics if requested
    if (includeMessageMetrics) {
      // TODO: Implement when message tracking table is available
      metrics.messagesThisMonth = 0;
    }

    // Collect active users if requested
    if (includeActiveUsers) {
      // TODO: Implement when user tracking is available
      // For now, use user property count as proxy
      metrics.userCount = userCount;
    }

    // TODO: Implement storage usage calculation when file storage is implemented
    if (includeStorageMetrics) {
      metrics.storageUsedBytes = 0; // Placeholder
    }

    // Cache metrics
    const cache = getTenantCache();
    await cache.set(
      workspaceId,
      `metrics`,
      JSON.stringify(metrics),
      { ttl: 300 } // 5 minute TTL
    );

    logger().debug(
      { workspaceId, metrics },
      "Collected tenant metrics"
    );

    return metrics;
  } catch (error) {
    logger().error(
      { error, workspaceId },
      "Failed to collect tenant metrics"
    );
    return null;
  }
}

/**
 * Get cached tenant metrics if available
 */
export async function getCachedTenantMetrics(
  workspaceId: string
): Promise<TenantMetrics | null> {
  try {
    const cache = getTenantCache();
    const cached = await cache.get(workspaceId, `metrics`);
    
    if (cached) {
      return JSON.parse(cached) as TenantMetrics;
    }
    
    return null;
  } catch (error) {
    logger().error(
      { error, workspaceId },
      "Failed to get cached tenant metrics"
    );
    return null;
  }
}

/**
 * Collect metrics for all active tenants
 * This is typically run as a scheduled job
 */
export async function collectAllTenantMetrics(): Promise<void> {
  try {
    const activeWorkspaces = await db()
      .select({ workspaceId: schema.workspace.id })
      .from(schema.workspace)
      .where(eq(schema.workspace.status, "Active"));

    logger().info(
      { count: activeWorkspaces.length },
      "Starting metrics collection for all tenants"
    );

    const results = await Promise.allSettled(
      activeWorkspaces.map(({ workspaceId }) =>
        collectTenantMetrics(workspaceId)
      )
    );

    const succeeded = results.filter(r => r.status === "fulfilled").length;
    const failed = results.filter(r => r.status === "rejected").length;

    logger().info(
      { succeeded, failed, total: activeWorkspaces.length },
      "Completed metrics collection for all tenants"
    );
  } catch (error) {
    logger().error(
      { error },
      "Failed to collect metrics for all tenants"
    );
  }
}

/**
 * Track a specific metric event for a tenant
 */
export async function trackTenantEvent(
  workspaceId: string,
  eventType: string,
  metadata?: Record<string, any>
): Promise<void> {
  if (!validate(workspaceId)) {
    return;
  }

  try {
    logger().debug(
      { workspaceId, eventType, metadata },
      "Tracking tenant event"
    );

    // TODO: Implement event tracking when events table is available
  } catch (error) {
    logger().error(
      { error, workspaceId, eventType },
      "Failed to track tenant event"
    );
  }
}
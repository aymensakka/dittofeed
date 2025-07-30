import { and, count, eq, gte, lte, sql } from "drizzle-orm";
import { validate } from "uuid";
import { TenantMetrics } from "isomorphic-lib/src/types";

import { db } from "../db";
import * as schema from "../db/schema";
import logger from "../logger";
import { getTenantCache } from "./cache";
import {
  createHistogram,
  createCounter,
  getOpenTelemetryMetrics,
} from "../openTelemetry";

/**
 * Tenant metrics collection and monitoring for multi-tenant insights
 * 
 * This module tracks resource usage, performance metrics, and tenant behavior
 * to enable proactive capacity planning and usage analytics. Integrates with
 * OpenTelemetry for comprehensive observability.
 */

// OpenTelemetry metrics
const metricsPrefix = "dittofeed.tenant";

const resourceCountMetric = createCounter({
  name: `${metricsPrefix}.resource_count`,
  description: "Count of resources per workspace",
  unit: "1",
});

const queryLatencyMetric = createHistogram({
  name: `${metricsPrefix}.query_latency`,
  description: "Database query latency per workspace",
  unit: "ms",
});

const cacheHitRateMetric = createHistogram({
  name: `${metricsPrefix}.cache_hit_rate`,
  description: "Cache hit rate percentage per workspace",
  unit: "%",
});

const storageUsageMetric = createHistogram({
  name: `${metricsPrefix}.storage_usage`,
  description: "Storage usage in bytes per workspace",
  unit: "bytes",
});

const messageCountMetric = createCounter({
  name: `${metricsPrefix}.message_count`,
  description: "Messages sent per workspace",
  unit: "1",
});

export interface MetricsCollectionOptions {
  includeStorageMetrics?: boolean;
  includeMessageMetrics?: boolean;
  forceRefresh?: boolean;
}

/**
 * Collect current metrics for a workspace
 * 
 * @param workspaceId - The UUID of the workspace
 * @param options - Collection options
 * @returns Current tenant metrics
 */
export async function collectTenantMetrics(
  workspaceId: string,
  options: MetricsCollectionOptions = {}
): Promise<TenantMetrics | null> {
  // Validate workspace ID format
  if (!validate(workspaceId)) {
    logger().warn({ workspaceId }, "Invalid workspace ID format");
    return null;
  }

  const cache = getTenantCache();
  const cacheKey = `metrics:current`;
  const cacheTTL = 60; // 1 minute cache

  // Try cache first unless force refresh
  if (!options.forceRefresh) {
    const cached = await cache.get<TenantMetrics>(
      workspaceId,
      cacheKey,
      { prefix: "tenant" }
    );
    if (cached) {
      return cached;
    }
  }

  try {
    const startTime = Date.now();

    // Collect resource counts in parallel
    const [
      segmentCountResult,
      journeyCountResult,
      messageTemplateCountResult,
      emailTemplateCountResult,
      userPropertyCountResult,
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
      
      db()
        .select({ count: count() })
        .from(schema.emailTemplate)
        .where(eq(schema.emailTemplate.workspaceId, workspaceId)),
      
      db()
        .select({ count: count() })
        .from(schema.userProperty)
        .where(eq(schema.userProperty.workspaceId, workspaceId)),
    ]);

    // Calculate total templates
    const templateCount = 
      (messageTemplateCountResult[0]?.count || 0) +
      (emailTemplateCountResult[0]?.count || 0);

    // Get user count (simplified - would need proper user tracking)
    const userCount = await getUserCount(workspaceId);

    // Get storage usage if requested
    let storageUsedBytes = 0;
    if (options.includeStorageMetrics) {
      storageUsedBytes = await getStorageUsage(workspaceId);
    }

    // Get messages this month if requested
    let messagesThisMonth = 0;
    if (options.includeMessageMetrics) {
      messagesThisMonth = await getMessagesThisMonth(workspaceId);
    }

    // Get cache hit rate
    const cacheHitRate = cache.getHitRate(workspaceId) / 100; // Convert to 0-1 range

    // Record query latency
    const queryLatency = Date.now() - startTime;
    queryLatencyMetric.record(queryLatency, {
      workspace_id: workspaceId,
    });

    // Create metrics object
    const metrics: TenantMetrics = {
      id: `${workspaceId}-${Date.now()}`,
      workspaceId,
      timestamp: new Date().toISOString(),
      userCount,
      segmentCount: segmentCountResult[0]?.count || 0,
      journeyCount: journeyCountResult[0]?.count || 0,
      templateCount,
      storageUsedBytes,
      messagesThisMonth,
      databaseQueryCount: 0, // Would need query tracking
      cacheHitRate: Math.round(cacheHitRate * 100), // Store as percentage * 100
    };

    // Record OpenTelemetry metrics
    recordOpenTelemetryMetrics(metrics);

    // Cache the metrics
    await cache.set(workspaceId, cacheKey, metrics, {
      prefix: "tenant",
      ttl: cacheTTL,
    });

    // Store in database for historical tracking
    await storeTenantMetrics(metrics);

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
 * Get historical metrics for a workspace
 * 
 * @param workspaceId - The UUID of the workspace
 * @param startDate - Start date for metrics range
 * @param endDate - End date for metrics range
 * @param granularity - Time granularity for aggregation
 * @returns Array of historical metrics
 */
export async function getHistoricalMetrics(
  workspaceId: string,
  startDate?: Date,
  endDate?: Date,
  granularity: "hour" | "day" | "week" | "month" = "day"
): Promise<TenantMetrics[]> {
  // Validate workspace ID format
  if (!validate(workspaceId)) {
    logger().warn({ workspaceId }, "Invalid workspace ID format");
    return [];
  }

  try {
    const conditions = [eq(schema.tenantMetrics.workspaceId, workspaceId)];

    if (startDate) {
      conditions.push(gte(schema.tenantMetrics.timestamp, startDate));
    }

    if (endDate) {
      conditions.push(lte(schema.tenantMetrics.timestamp, endDate));
    }

    const metricsRecords = await db().query.tenantMetrics.findMany({
      where: and(...conditions),
      orderBy: (metrics, { desc }) => [desc(metrics.timestamp)],
      limit: 1000, // Reasonable limit for UI display
    });

    // Aggregate by granularity if needed
    if (granularity !== "hour") {
      return aggregateMetricsByGranularity(metricsRecords, granularity);
    }

    return metricsRecords.map(recordToTenantMetrics);
  } catch (error) {
    logger().error(
      { error, workspaceId, startDate, endDate, granularity },
      "Failed to get historical metrics"
    );
    return [];
  }
}

/**
 * Store metrics in the database
 */
async function storeTenantMetrics(metrics: TenantMetrics): Promise<void> {
  try {
    await db().insert(schema.tenantMetrics).values({
      workspaceId: metrics.workspaceId,
      timestamp: new Date(metrics.timestamp),
      userCount: metrics.userCount,
      segmentCount: metrics.segmentCount,
      journeyCount: metrics.journeyCount,
      templateCount: metrics.templateCount,
      storageUsedBytes: metrics.storageUsedBytes,
      messagesThisMonth: metrics.messagesThisMonth,
      databaseQueryCount: metrics.databaseQueryCount,
      cacheHitRate: metrics.cacheHitRate,
    });
  } catch (error) {
    logger().error(
      { error, workspaceId: metrics.workspaceId },
      "Failed to store tenant metrics"
    );
  }
}

/**
 * Get user count for a workspace
 * This is a simplified implementation - in production you'd track unique users
 */
async function getUserCount(workspaceId: string): Promise<number> {
  try {
    // This would need to be implemented based on your user tracking strategy
    // For now, return 0 as placeholder
    return 0;
  } catch (error) {
    logger().error(
      { error, workspaceId },
      "Failed to get user count"
    );
    return 0;
  }
}

/**
 * Get storage usage for a workspace
 * This is a simplified implementation - in production you'd calculate actual storage
 */
async function getStorageUsage(workspaceId: string): Promise<number> {
  try {
    // This would need to be implemented based on your storage tracking
    // For now, return estimated based on resource counts
    const estimatedBytesPerResource = 10240; // 10KB average
    
    const [segmentCount, journeyCount] = await Promise.all([
      db()
        .select({ count: count() })
        .from(schema.segment)
        .where(eq(schema.segment.workspaceId, workspaceId)),
      
      db()
        .select({ count: count() })
        .from(schema.journey)
        .where(eq(schema.journey.workspaceId, workspaceId)),
    ]);

    const totalResources = 
      (segmentCount[0]?.count || 0) +
      (journeyCount[0]?.count || 0);

    return totalResources * estimatedBytesPerResource;
  } catch (error) {
    logger().error(
      { error, workspaceId },
      "Failed to get storage usage"
    );
    return 0;
  }
}

/**
 * Get message count for current month
 */
async function getMessagesThisMonth(workspaceId: string): Promise<number> {
  try {
    const firstDayOfMonth = new Date();
    firstDayOfMonth.setDate(1);
    firstDayOfMonth.setHours(0, 0, 0, 0);

    // This would need to be implemented based on your message tracking
    // For now, return 0 as placeholder
    return 0;
  } catch (error) {
    logger().error(
      { error, workspaceId },
      "Failed to get messages this month"
    );
    return 0;
  }
}

/**
 * Record metrics to OpenTelemetry
 */
function recordOpenTelemetryMetrics(metrics: TenantMetrics): void {
  const attributes = {
    workspace_id: metrics.workspaceId,
  };

  // Record resource counts
  resourceCountMetric.add(metrics.segmentCount, {
    ...attributes,
    resource_type: "segment",
  });
  
  resourceCountMetric.add(metrics.journeyCount, {
    ...attributes,
    resource_type: "journey",
  });
  
  resourceCountMetric.add(metrics.templateCount, {
    ...attributes,
    resource_type: "template",
  });

  // Record cache hit rate
  cacheHitRateMetric.record(metrics.cacheHitRate / 100, attributes);

  // Record storage usage
  if (metrics.storageUsedBytes > 0) {
    storageUsageMetric.record(metrics.storageUsedBytes, attributes);
  }

  // Record message count
  if (metrics.messagesThisMonth > 0) {
    messageCountMetric.add(metrics.messagesThisMonth, attributes);
  }
}

/**
 * Convert database record to TenantMetrics type
 */
function recordToTenantMetrics(record: any): TenantMetrics {
  return {
    id: record.id,
    workspaceId: record.workspaceId,
    timestamp: record.timestamp.toISOString(),
    userCount: record.userCount,
    segmentCount: record.segmentCount,
    journeyCount: record.journeyCount,
    templateCount: record.templateCount,
    storageUsedBytes: record.storageUsedBytes,
    messagesThisMonth: record.messagesThisMonth,
    databaseQueryCount: record.databaseQueryCount,
    cacheHitRate: record.cacheHitRate,
  };
}

/**
 * Aggregate metrics by time granularity
 */
function aggregateMetricsByGranularity(
  metrics: any[],
  granularity: "day" | "week" | "month"
): TenantMetrics[] {
  // Group metrics by time period
  const grouped = new Map<string, any[]>();

  for (const metric of metrics) {
    const date = new Date(metric.timestamp);
    let key: string;

    switch (granularity) {
      case "day":
        key = date.toISOString().split("T")[0];
        break;
      case "week":
        const weekStart = new Date(date);
        weekStart.setDate(date.getDate() - date.getDay());
        key = weekStart.toISOString().split("T")[0];
        break;
      case "month":
        key = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
        break;
    }

    if (!grouped.has(key)) {
      grouped.set(key, []);
    }
    grouped.get(key)!.push(metric);
  }

  // Average metrics for each period
  const aggregated: TenantMetrics[] = [];

  for (const [period, periodMetrics] of grouped) {
    const avgMetrics = periodMetrics.reduce((acc, metric) => ({
      userCount: acc.userCount + metric.userCount,
      segmentCount: acc.segmentCount + metric.segmentCount,
      journeyCount: acc.journeyCount + metric.journeyCount,
      templateCount: acc.templateCount + metric.templateCount,
      storageUsedBytes: acc.storageUsedBytes + metric.storageUsedBytes,
      messagesThisMonth: acc.messagesThisMonth + metric.messagesThisMonth,
      databaseQueryCount: acc.databaseQueryCount + metric.databaseQueryCount,
      cacheHitRate: acc.cacheHitRate + metric.cacheHitRate,
    }), {
      userCount: 0,
      segmentCount: 0,
      journeyCount: 0,
      templateCount: 0,
      storageUsedBytes: 0,
      messagesThisMonth: 0,
      databaseQueryCount: 0,
      cacheHitRate: 0,
    });

    const count = periodMetrics.length;
    
    aggregated.push({
      id: `${periodMetrics[0].workspaceId}-${period}`,
      workspaceId: periodMetrics[0].workspaceId,
      timestamp: periodMetrics[0].timestamp,
      userCount: Math.round(avgMetrics.userCount / count),
      segmentCount: Math.round(avgMetrics.segmentCount / count),
      journeyCount: Math.round(avgMetrics.journeyCount / count),
      templateCount: Math.round(avgMetrics.templateCount / count),
      storageUsedBytes: Math.round(avgMetrics.storageUsedBytes / count),
      messagesThisMonth: Math.round(avgMetrics.messagesThisMonth / count),
      databaseQueryCount: Math.round(avgMetrics.databaseQueryCount / count),
      cacheHitRate: Math.round(avgMetrics.cacheHitRate / count),
    });
  }

  return aggregated;
}

/**
 * Export metrics for a workspace (for compliance/reporting)
 */
export async function exportTenantMetrics(
  workspaceId: string,
  startDate?: Date,
  endDate?: Date
): Promise<{
  workspace: string;
  exportDate: string;
  metrics: TenantMetrics[];
  summary: {
    avgUserCount: number;
    avgSegmentCount: number;
    avgJourneyCount: number;
    avgCacheHitRate: number;
    totalMessages: number;
  };
}> {
  const metrics = await getHistoricalMetrics(
    workspaceId,
    startDate,
    endDate,
    "hour"
  );

  if (metrics.length === 0) {
    return {
      workspace: workspaceId,
      exportDate: new Date().toISOString(),
      metrics: [],
      summary: {
        avgUserCount: 0,
        avgSegmentCount: 0,
        avgJourneyCount: 0,
        avgCacheHitRate: 0,
        totalMessages: 0,
      },
    };
  }

  // Calculate summary statistics
  const summary = metrics.reduce((acc, metric) => ({
    avgUserCount: acc.avgUserCount + metric.userCount,
    avgSegmentCount: acc.avgSegmentCount + metric.segmentCount,
    avgJourneyCount: acc.avgJourneyCount + metric.journeyCount,
    avgCacheHitRate: acc.avgCacheHitRate + metric.cacheHitRate,
    totalMessages: acc.totalMessages + metric.messagesThisMonth,
  }), {
    avgUserCount: 0,
    avgSegmentCount: 0,
    avgJourneyCount: 0,
    avgCacheHitRate: 0,
    totalMessages: 0,
  });

  const count = metrics.length;

  return {
    workspace: workspaceId,
    exportDate: new Date().toISOString(),
    metrics,
    summary: {
      avgUserCount: Math.round(summary.avgUserCount / count),
      avgSegmentCount: Math.round(summary.avgSegmentCount / count),
      avgJourneyCount: Math.round(summary.avgJourneyCount / count),
      avgCacheHitRate: Math.round(summary.avgCacheHitRate / count),
      totalMessages: summary.totalMessages,
    },
  };
}
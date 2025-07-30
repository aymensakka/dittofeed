import { randomUUID } from "crypto";
import { describe, expect, it, beforeEach, afterEach, jest } from "@jest/globals";
import { eq } from "drizzle-orm";

import { db } from "../../db";
import * as schema from "../../db/schema";
import {
  setWorkspaceContext,
  clearWorkspaceContext,
  withWorkspaceContext,
  validateRLSConfiguration,
} from "../../db/policies";
import {
  validateWorkspaceQuota,
  getWorkspaceQuota,
  updateWorkspaceQuota,
  getWorkspaceUsage,
} from "../resourceQuotas";
import { getTenantCache } from "../cache";
import { getTenantConnectionPool } from "../connectionPool";
import { collectTenantMetrics, getHistoricalMetrics } from "../tenantMetrics";
import {
  auditWorkspaceAccess,
  auditResourceAccess,
  auditQuotaEvent,
  AuditEventType,
} from "../../security/auditLogger";

// Mock logger to prevent console output during tests
jest.mock("../../logger", () => ({
  __esModule: true,
  default: jest.fn(() => ({
    debug: jest.fn(),
    info: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
  })),
}));

describe("Multitenancy Integration Tests", () => {
  const workspace1Id = randomUUID();
  const workspace2Id = randomUUID();
  const userId = randomUUID();
  
  let cache: ReturnType<typeof getTenantCache>;
  let connectionPool: ReturnType<typeof getTenantConnectionPool>;

  beforeEach(async () => {
    // Initialize services
    cache = getTenantCache();
    connectionPool = getTenantConnectionPool();
    
    // Create test workspaces
    await db().insert(schema.workspace).values([
      {
        id: workspace1Id,
        name: "Test Workspace 1",
        type: "Root",
        createdAt: new Date(),
        updatedAt: new Date(),
      },
      {
        id: workspace2Id,
        name: "Test Workspace 2",
        type: "Root",
        createdAt: new Date(),
        updatedAt: new Date(),
      },
    ]);

    // Create default quotas
    await db().insert(schema.workspaceQuota).values([
      {
        id: randomUUID(),
        workspaceId: workspace1Id,
        maxUsers: 100,
        maxSegments: 10,
        maxJourneys: 5,
        maxBroadcasts: 20,
        maxComputedProperties: 50,
        maxAudiences: 10,
        maxEmailTemplates: 20,
        maxSubscriptionGroups: 5,
        createdAt: new Date(),
        updatedAt: new Date(),
      },
      {
        id: randomUUID(),
        workspaceId: workspace2Id,
        maxUsers: 100,
        maxSegments: 10,
        maxJourneys: 5,
        maxBroadcasts: 20,
        maxComputedProperties: 50,
        maxAudiences: 10,
        maxEmailTemplates: 20,
        maxSubscriptionGroups: 5,
        createdAt: new Date(),
        updatedAt: new Date(),
      },
    ]);
  });

  afterEach(async () => {
    // Clean up test data
    await db().delete(schema.segment).where(
      eq(schema.segment.workspaceId, workspace1Id)
    );
    await db().delete(schema.segment).where(
      eq(schema.segment.workspaceId, workspace2Id)
    );
    
    await db().delete(schema.journey).where(
      eq(schema.journey.workspaceId, workspace1Id)
    );
    await db().delete(schema.journey).where(
      eq(schema.journey.workspaceId, workspace2Id)
    );
    
    await db().delete(schema.workspaceQuota).where(
      eq(schema.workspaceQuota.workspaceId, workspace1Id)
    );
    await db().delete(schema.workspaceQuota).where(
      eq(schema.workspaceQuota.workspaceId, workspace2Id)
    );
    
    await db().delete(schema.workspace).where(
      eq(schema.workspace.id, workspace1Id)
    );
    await db().delete(schema.workspace).where(
      eq(schema.workspace.id, workspace2Id)
    );

    // Clear workspace context
    await clearWorkspaceContext();
    
    // Clear cache
    await cache.invalidateWorkspace(workspace1Id);
    await cache.invalidateWorkspace(workspace2Id);
  });

  describe("Row-Level Security (RLS)", () => {
    it("should isolate data between workspaces", async () => {
      // Create segments in both workspaces
      await withWorkspaceContext(workspace1Id, async () => {
        await db().insert(schema.segment).values({
          id: randomUUID(),
          workspaceId: workspace1Id,
          name: "Workspace 1 Segment",
          definitionUpdatedAt: new Date(),
          createdAt: new Date(),
          updatedAt: new Date(),
        });
      });

      await withWorkspaceContext(workspace2Id, async () => {
        await db().insert(schema.segment).values({
          id: randomUUID(),
          workspaceId: workspace2Id,
          name: "Workspace 2 Segment",
          definitionUpdatedAt: new Date(),
          createdAt: new Date(),
          updatedAt: new Date(),
        });
      });

      // Verify workspace 1 can only see its own data
      await withWorkspaceContext(workspace1Id, async () => {
        const segments = await db().query.segment.findMany();
        expect(segments).toHaveLength(1);
        expect(segments[0].name).toBe("Workspace 1 Segment");
        expect(segments[0].workspaceId).toBe(workspace1Id);
      });

      // Verify workspace 2 can only see its own data
      await withWorkspaceContext(workspace2Id, async () => {
        const segments = await db().query.segment.findMany();
        expect(segments).toHaveLength(1);
        expect(segments[0].name).toBe("Workspace 2 Segment");
        expect(segments[0].workspaceId).toBe(workspace2Id);
      });
    });

    it("should prevent cross-workspace data access", async () => {
      const segmentId = randomUUID();
      
      // Create segment in workspace 1
      await withWorkspaceContext(workspace1Id, async () => {
        await db().insert(schema.segment).values({
          id: segmentId,
          workspaceId: workspace1Id,
          name: "Private Segment",
          definitionUpdatedAt: new Date(),
          createdAt: new Date(),
          updatedAt: new Date(),
        });
      });

      // Try to access from workspace 2 - should not find it
      await withWorkspaceContext(workspace2Id, async () => {
        const segment = await db().query.segment.findFirst({
          where: eq(schema.segment.id, segmentId),
        });
        expect(segment).toBeUndefined();
      });
    });

    it("should validate RLS is enabled on protected tables", async () => {
      const protectedTables = [
        "Segment",
        "Journey",
        "MessageTemplate",
        "EmailTemplate",
        "Broadcast",
      ];

      for (const table of protectedTables) {
        const isEnabled = await validateRLSConfiguration(table);
        expect(isEnabled).toBe(true);
      }
    });
  });

  describe("Resource Quotas", () => {
    it("should enforce segment quota limits", async () => {
      // Create segments up to the limit
      for (let i = 0; i < 10; i++) {
        const validation = await validateWorkspaceQuota(
          workspace1Id,
          "segments",
          1
        );
        expect(validation.isOk()).toBe(true);

        await withWorkspaceContext(workspace1Id, async () => {
          await db().insert(schema.segment).values({
            id: randomUUID(),
            workspaceId: workspace1Id,
            name: `Segment ${i + 1}`,
            definitionUpdatedAt: new Date(),
            createdAt: new Date(),
            updatedAt: new Date(),
          });
        });
      }

      // Try to exceed quota
      const validation = await validateWorkspaceQuota(
        workspace1Id,
        "segments",
        1
      );
      expect(validation.isErr()).toBe(true);
      
      if (validation.isErr()) {
        expect(validation.error.code).toBe("QUOTA_EXCEEDED");
        expect(validation.error.currentUsage).toBe(10);
        expect(validation.error.limit).toBe(10);
      }
    });

    it("should track usage across multiple resource types", async () => {
      // Create various resources
      await withWorkspaceContext(workspace1Id, async () => {
        // Create segments
        for (let i = 0; i < 5; i++) {
          await db().insert(schema.segment).values({
            id: randomUUID(),
            workspaceId: workspace1Id,
            name: `Segment ${i}`,
            definitionUpdatedAt: new Date(),
            createdAt: new Date(),
            updatedAt: new Date(),
          });
        }

        // Create journeys
        for (let i = 0; i < 3; i++) {
          await db().insert(schema.journey).values({
            id: randomUUID(),
            workspaceId: workspace1Id,
            name: `Journey ${i}`,
            status: "NotStarted",
            createdAt: new Date(),
            updatedAt: new Date(),
          });
        }
      });

      // Check usage
      const usage = await getWorkspaceUsage(workspace1Id);
      expect(usage.segments).toBe(5);
      expect(usage.journeys).toBe(3);
    });

    it("should update quotas successfully", async () => {
      const newLimits = {
        maxSegments: 20,
        maxJourneys: 10,
      };

      const result = await updateWorkspaceQuota(workspace1Id, newLimits);
      expect(result.isOk()).toBe(true);

      const quota = await getWorkspaceQuota(workspace1Id);
      expect(quota.isOk()).toBe(true);
      if (quota.isOk()) {
        expect(quota.value.maxSegments).toBe(20);
        expect(quota.value.maxJourneys).toBe(10);
      }
    });
  });

  describe("Workspace-Scoped Caching", () => {
    it("should isolate cache entries by workspace", async () => {
      // Set cache values for both workspaces
      await cache.set(workspace1Id, "test-key", { data: "workspace1" }, { ttl: 300 });
      await cache.set(workspace2Id, "test-key", { data: "workspace2" }, { ttl: 300 });

      // Verify isolation
      const value1 = await cache.get(workspace1Id, "test-key");
      expect(value1).toEqual({ data: "workspace1" });

      const value2 = await cache.get(workspace2Id, "test-key");
      expect(value2).toEqual({ data: "workspace2" });
    });

    it("should track cache hit rates per workspace", async () => {
      // Reset stats
      cache.resetStats(workspace1Id);

      // Create cache misses and hits
      await cache.get(workspace1Id, "missing-key"); // miss
      await cache.set(workspace1Id, "existing-key", { value: 123 });
      await cache.get(workspace1Id, "existing-key"); // hit
      await cache.get(workspace1Id, "existing-key"); // hit

      const hitRate = cache.getHitRate(workspace1Id);
      expect(hitRate).toBe(67); // 2 hits / 3 total * 100
    });

    it("should support cache-aside pattern", async () => {
      let factoryCalls = 0;
      const factory = async () => {
        factoryCalls++;
        return { computed: "expensive-data" };
      };

      // First call should execute factory
      const value1 = await cache.getOrSet(
        workspace1Id,
        "computed-key",
        factory,
        { ttl: 300 }
      );
      expect(value1).toEqual({ computed: "expensive-data" });
      expect(factoryCalls).toBe(1);

      // Second call should use cache
      const value2 = await cache.getOrSet(
        workspace1Id,
        "computed-key",
        factory,
        { ttl: 300 }
      );
      expect(value2).toEqual({ computed: "expensive-data" });
      expect(factoryCalls).toBe(1); // Factory not called again
    });
  });

  describe("Tenant Metrics", () => {
    it("should collect workspace metrics", async () => {
      // Create test data
      await withWorkspaceContext(workspace1Id, async () => {
        for (let i = 0; i < 5; i++) {
          await db().insert(schema.segment).values({
            id: randomUUID(),
            workspaceId: workspace1Id,
            name: `Metric Test Segment ${i}`,
            definitionUpdatedAt: new Date(),
            createdAt: new Date(),
            updatedAt: new Date(),
          });
        }
      });

      // Collect metrics
      const metrics = await collectTenantMetrics(workspace1Id, {
        includeStorageMetrics: true,
        forceRefresh: true,
      });

      expect(metrics).not.toBeNull();
      expect(metrics?.segmentCount).toBe(5);
      expect(metrics?.workspaceId).toBe(workspace1Id);
      expect(metrics?.cacheHitRate).toBeGreaterThanOrEqual(0);
    });

    it("should track historical metrics", async () => {
      // Collect metrics multiple times
      for (let i = 0; i < 3; i++) {
        await collectTenantMetrics(workspace1Id, { forceRefresh: true });
        // Small delay to ensure different timestamps
        await new Promise(resolve => setTimeout(resolve, 10));
      }

      // Retrieve historical data
      const history = await getHistoricalMetrics(
        workspace1Id,
        undefined,
        undefined,
        "hour"
      );

      expect(history.length).toBeGreaterThanOrEqual(1);
      expect(history[0].workspaceId).toBe(workspace1Id);
    });
  });

  describe("Audit Logging", () => {
    it("should log workspace access events", () => {
      auditWorkspaceAccess(workspace1Id, userId, true, {
        requestId: "test-req-1",
      });

      auditWorkspaceAccess(workspace2Id, userId, false, {
        requestId: "test-req-2",
      });

      // Verify audit logger was called (mocked)
      const logger = require("../../logger").default();
      expect(logger.info).toHaveBeenCalledWith(
        expect.objectContaining({
          eventType: "WORKSPACE_ACCESS",
          workspaceId: workspace1Id,
          success: true,
        }),
        expect.any(String)
      );
    });

    it("should log quota events", () => {
      auditQuotaEvent(
        AuditEventType.QUOTA_EXCEEDED,
        workspace1Id,
        "segments",
        10,
        10
      );

      auditQuotaEvent(
        AuditEventType.QUOTA_WARNING,
        workspace1Id,
        "journeys",
        4,
        5
      );

      const logger = require("../../logger").default();
      expect(logger.info).toHaveBeenCalledWith(
        expect.objectContaining({
          eventType: "QUOTA_EXCEEDED",
          context: expect.objectContaining({
            resourceType: "segments",
            metadata: expect.objectContaining({
              currentUsage: 10,
              limit: 10,
              usagePercentage: 100,
            }),
          }),
        }),
        expect.any(String)
      );
    });
  });

  describe("Connection Pooling", () => {
    it("should create separate pools for different workspaces", async () => {
      const pool1 = await connectionPool.getPool(workspace1Id);
      const pool2 = await connectionPool.getPool(workspace2Id);

      expect(pool1).toBeDefined();
      expect(pool2).toBeDefined();
      expect(pool1).not.toBe(pool2);

      const stats = connectionPool.getStatistics();
      expect(stats.totalPools).toBeGreaterThanOrEqual(2);
    });

    it("should track pool metrics", async () => {
      await connectionPool.getPool(workspace1Id);
      
      const metrics = connectionPool.getPoolMetrics(workspace1Id);
      expect(metrics).not.toBeNull();
      expect(metrics?.createdAt).toBeDefined();
      expect(metrics?.lastUsedAt).toBeDefined();
    });
  });

  describe("End-to-End Multitenancy Flow", () => {
    it("should handle complete resource creation flow with all features", async () => {
      const segmentId = randomUUID();
      const segmentName = "E2E Test Segment";

      // 1. Check quota before creation
      const quotaCheck = await validateWorkspaceQuota(
        workspace1Id,
        "segments",
        1
      );
      expect(quotaCheck.isOk()).toBe(true);

      // 2. Create resource with RLS context
      await withWorkspaceContext(workspace1Id, async () => {
        await db().insert(schema.segment).values({
          id: segmentId,
          workspaceId: workspace1Id,
          name: segmentName,
          definitionUpdatedAt: new Date(),
          createdAt: new Date(),
          updatedAt: new Date(),
        });
      });

      // 3. Cache the resource
      await cache.set(
        workspace1Id,
        `segment:${segmentId}`,
        { id: segmentId, name: segmentName },
        { prefix: "segment", ttl: 300 }
      );

      // 4. Log the creation
      auditResourceAccess(
        AuditEventType.RESOURCE_CREATED,
        workspace1Id,
        "segment",
        segmentId,
        userId,
        true
      );

      // 5. Verify creation and isolation
      await withWorkspaceContext(workspace1Id, async () => {
        const segment = await db().query.segment.findFirst({
          where: eq(schema.segment.id, segmentId),
        });
        expect(segment).toBeDefined();
        expect(segment?.name).toBe(segmentName);
      });

      // 6. Verify cache
      const cached = await cache.get(
        workspace1Id,
        `segment:${segmentId}`,
        { prefix: "segment" }
      );
      expect(cached).toEqual({ id: segmentId, name: segmentName });

      // 7. Verify metrics updated
      const metrics = await collectTenantMetrics(workspace1Id, {
        forceRefresh: true,
      });
      expect(metrics?.segmentCount).toBeGreaterThanOrEqual(1);

      // 8. Verify workspace isolation
      await withWorkspaceContext(workspace2Id, async () => {
        const segment = await db().query.segment.findFirst({
          where: eq(schema.segment.id, segmentId),
        });
        expect(segment).toBeUndefined();
      });

      // 9. Verify cache isolation
      const wrongCache = await cache.get(
        workspace2Id,
        `segment:${segmentId}`,
        { prefix: "segment" }
      );
      expect(wrongCache).toBeNull();
    });
  });
});
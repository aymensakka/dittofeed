import { validate } from "uuid";
import { describe, expect, it, beforeEach, afterEach, jest } from "@jest/globals";

import {
  validateWorkspaceQuota,
  getWorkspaceQuotaLimits,
  getCurrentResourceUsage,
  upsertWorkspaceQuota,
  getWorkspaceQuota,
} from "../resourceQuotas";

// Mock dependencies
jest.mock("../../db", () => ({
  db: jest.fn(() => ({
    query: {
      workspaceQuota: {
        findFirst: jest.fn(),
      },
      segment: {
        findMany: jest.fn(),
      },
      journey: {
        findMany: jest.fn(), 
      },
      messageTemplate: {
        findMany: jest.fn(),
      },
    },
    select: jest.fn(() => ({
      from: jest.fn(() => ({
        where: jest.fn(),
      })),
    })),
    insert: jest.fn(() => ({
      values: jest.fn(() => ({
        returning: jest.fn(),
      })),
    })),
    update: jest.fn(() => ({
      set: jest.fn(() => ({
        where: jest.fn(() => ({
          returning: jest.fn(),
        })),
      })),
    })),
  })),
}));

jest.mock("../../logger", () => ({
  __esModule: true,
  default: jest.fn(() => ({
    warn: jest.fn(),
    error: jest.fn(),
    info: jest.fn(),
    debug: jest.fn(),
  })),
}));

describe("ResourceQuotas", () => {
  const mockWorkspaceId = "550e8400-e29b-41d4-a716-446655440000";
  const mockInvalidWorkspaceId = "invalid-workspace-id";

  beforeEach(() => {
    jest.clearAllMocks();
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  describe("validateWorkspaceQuota", () => {
    it("should reject invalid workspace ID format", async () => {
      const result = await validateWorkspaceQuota(
        mockInvalidWorkspaceId,
        "segments",
        1
      );

      expect(result.isErr()).toBe(true);
      if (result.isErr()) {
        expect(result.error.type).toBe("QuotaExceeded");
        expect(result.error.message).toContain("Invalid workspace ID format");
        expect(result.error.resourceType).toBe("segments");
      }
    });

    it("should reject negative increment values", async () => {
      const result = await validateWorkspaceQuota(
        mockWorkspaceId,
        "segments",
        -1
      );

      expect(result.isErr()).toBe(true);
      if (result.isErr()) {
        expect(result.error.type).toBe("QuotaExceeded");
        expect(result.error.message).toContain("Increment must be at least 1");
      }
    });

    it("should allow creation within quota limits", async () => {
      // Mock getWorkspaceQuotaLimits to return default limits
      const mockGetWorkspaceQuotaLimits = getWorkspaceQuotaLimits as jest.MockedFunction<typeof getWorkspaceQuotaLimits>;
      mockGetWorkspaceQuotaLimits.mockResolvedValue({
        maxUsers: 1000,
        maxSegments: 50,
        maxJourneys: 20,
        maxTemplates: 100,
        maxStorageBytes: 10737418240,
        maxMessagesPerMonth: 100000,
      });

      // Mock getCurrentResourceUsage to return low usage
      const mockGetCurrentResourceUsage = getCurrentResourceUsage as jest.MockedFunction<typeof getCurrentResourceUsage>;
      mockGetCurrentResourceUsage.mockResolvedValue({
        users: 0,
        segments: 5, // Well under limit of 50
        journeys: 0,
        templates: 0,
        storageBytes: 0,
        messagesThisMonth: 0,
      });

      const result = await validateWorkspaceQuota(
        mockWorkspaceId,
        "segments",
        1
      );

      expect(result.isOk()).toBe(true);
      if (result.isOk()) {
        expect(result.value.allowed).toBe(true);
        expect(result.value.currentUsage).toBe(5);
        expect(result.value.limit).toBe(50);
        expect(result.value.remaining).toBe(44); // 50 - 5 - 1
      }
    });

    it("should deny creation when quota would be exceeded", async () => {
      // Mock getWorkspaceQuotaLimits to return default limits
      const mockGetWorkspaceQuotaLimits = getWorkspaceQuotaLimits as jest.MockedFunction<typeof getWorkspaceQuotaLimits>;
      mockGetWorkspaceQuotaLimits.mockResolvedValue({
        maxUsers: 1000,
        maxSegments: 50,
        maxJourneys: 20,
        maxTemplates: 100,
        maxStorageBytes: 10737418240,
        maxMessagesPerMonth: 100000,
      });

      // Mock getCurrentResourceUsage to return usage at limit
      const mockGetCurrentResourceUsage = getCurrentResourceUsage as jest.MockedFunction<typeof getCurrentResourceUsage>;
      mockGetCurrentResourceUsage.mockResolvedValue({
        users: 0,
        segments: 50, // At limit
        journeys: 0,
        templates: 0,
        storageBytes: 0,
        messagesThisMonth: 0,
      });

      const result = await validateWorkspaceQuota(
        mockWorkspaceId,
        "segments",
        1
      );

      expect(result.isErr()).toBe(true);
      if (result.isErr()) {
        expect(result.error.type).toBe("QuotaExceeded");
        expect(result.error.message).toContain("Quota exceeded for segments");
        expect(result.error.currentUsage).toBe(50);
        expect(result.error.limit).toBe(50);
      }
    });

    it("should handle multiple resource types correctly", async () => {
      const mockGetWorkspaceQuotaLimits = getWorkspaceQuotaLimits as jest.MockedFunction<typeof getWorkspaceQuotaLimits>;
      mockGetWorkspaceQuotaLimits.mockResolvedValue({
        maxUsers: 1000,
        maxSegments: 50,
        maxJourneys: 20,
        maxTemplates: 100,
        maxStorageBytes: 10737418240,
        maxMessagesPerMonth: 100000,
      });

      const mockGetCurrentResourceUsage = getCurrentResourceUsage as jest.MockedFunction<typeof getCurrentResourceUsage>;
      mockGetCurrentResourceUsage.mockResolvedValue({
        users: 500,
        segments: 25,
        journeys: 15,
        templates: 75,
        storageBytes: 5368709120, // 5GB
        messagesThisMonth: 50000,
      });

      // Test different resource types
      const resourceTypes: Array<{type: any, expectedLimit: number, expectedCurrent: number}> = [
        { type: "users", expectedLimit: 1000, expectedCurrent: 500 },
        { type: "segments", expectedLimit: 50, expectedCurrent: 25 },
        { type: "journeys", expectedLimit: 20, expectedCurrent: 15 },
        { type: "templates", expectedLimit: 100, expectedCurrent: 75 },
        { type: "storage", expectedLimit: 10737418240, expectedCurrent: 5368709120 },
        { type: "messages", expectedLimit: 100000, expectedCurrent: 50000 },
      ];

      for (const { type, expectedLimit, expectedCurrent } of resourceTypes) {
        const result = await validateWorkspaceQuota(mockWorkspaceId, type, 1);
        
        expect(result.isOk()).toBe(true);
        if (result.isOk()) {
          expect(result.value.currentUsage).toBe(expectedCurrent);
          expect(result.value.limit).toBe(expectedLimit);
        }
      }
    });
  });

  describe("getWorkspaceQuotaLimits", () => {
    it("should return null for invalid workspace ID", async () => {
      const result = await getWorkspaceQuotaLimits(mockInvalidWorkspaceId);
      expect(result).toBeNull();
    });

    it("should return custom quota when record exists", async () => {
      const mockDb = require("../../db").db();
      mockDb.query.workspaceQuota.findFirst.mockResolvedValue({
        maxUsers: 500,
        maxSegments: 25,
        maxJourneys: 10,
        maxTemplates: 50,
        maxStorageBytes: 5368709120,
        maxMessagesPerMonth: 50000,
      });

      const result = await getWorkspaceQuotaLimits(mockWorkspaceId);
      
      expect(result).toEqual({
        maxUsers: 500,
        maxSegments: 25,
        maxJourneys: 10,
        maxTemplates: 50,
        maxStorageBytes: 5368709120,
        maxMessagesPerMonth: 50000,
      });
    });

    it("should return default quota when no record exists", async () => {
      const mockDb = require("../../db").db();
      mockDb.query.workspaceQuota.findFirst.mockResolvedValue(null);

      const result = await getWorkspaceQuotaLimits(mockWorkspaceId);
      
      expect(result).toEqual({
        maxUsers: 1000,
        maxSegments: 50,
        maxJourneys: 20,
        maxTemplates: 100,
        maxStorageBytes: 10737418240, // 10GB
        maxMessagesPerMonth: 100000,
      });
    });
  });

  describe("getCurrentResourceUsage", () => {
    it("should return null for invalid workspace ID", async () => {
      const result = await getCurrentResourceUsage(mockInvalidWorkspaceId);
      expect(result).toBeNull();
    });

    it("should count resources correctly", async () => {
      const mockDb = require("../../db").db();
      
      // Mock count queries
      const mockSelect = mockDb.select.mockReturnValue({
        from: jest.fn().mockReturnValue({
          where: jest.fn().mockResolvedValue([
            { count: 5 }, // segments
            { count: 3 }, // journeys
            { count: 7 }, // message templates
            { count: 2 }, // email templates
          ])
        })
      });

      // Mock the Promise.all resolution
      jest.spyOn(Promise, 'all').mockResolvedValue([
        [{ count: 5 }], // segments
        [{ count: 3 }], // journeys  
        [{ count: 7 }], // message templates
      ]);

      const result = await getCurrentResourceUsage(mockWorkspaceId);
      
      expect(result).toEqual({
        users: 0, // TODO: Not implemented yet
        segments: 5,
        journeys: 3,
        templates: 7,
        storageBytes: 0, // TODO: Not implemented yet
        messagesThisMonth: 0, // TODO: Not implemented yet
      });
    });
  });

  describe("upsertWorkspaceQuota", () => {
    it("should reject invalid workspace ID format", async () => {
      const result = await upsertWorkspaceQuota(mockInvalidWorkspaceId, {
        maxSegments: 25,
      });

      expect(result.isErr()).toBe(true);
      if (result.isErr()) {
        expect(result.error).toContain("Invalid workspace ID format");
      }
    });

    it("should create new quota when none exists", async () => {
      const mockDb = require("../../db").db();
      mockDb.query.workspaceQuota.findFirst.mockResolvedValue(null);
      mockDb.insert.mockReturnValue({
        values: jest.fn().mockReturnValue({
          returning: jest.fn().mockResolvedValue([{
            id: "quota-id",
            workspaceId: mockWorkspaceId,
            maxUsers: 1000,
            maxSegments: 25, // Updated value
            maxJourneys: 20,
            maxTemplates: 100,
            maxStorageBytes: 10737418240,
            maxMessagesPerMonth: 100000,
            createdAt: new Date(),
            updatedAt: new Date(),
          }])
        })
      });

      const result = await upsertWorkspaceQuota(mockWorkspaceId, {
        maxSegments: 25,
      });

      expect(result.isOk()).toBe(true);
      if (result.isOk()) {
        expect(result.value.maxSegments).toBe(25);
        expect(result.value.workspaceId).toBe(mockWorkspaceId);
      }
    });

    it("should update existing quota", async () => {
      const mockDb = require("../../db").db();
      mockDb.query.workspaceQuota.findFirst.mockResolvedValue({
        id: "existing-quota-id",
        workspaceId: mockWorkspaceId,
      });
      mockDb.update.mockReturnValue({
        set: jest.fn().mockReturnValue({
          where: jest.fn().mockReturnValue({
            returning: jest.fn().mockResolvedValue([{
              id: "existing-quota-id",
              workspaceId: mockWorkspaceId,
              maxUsers: 1000,
              maxSegments: 75, // Updated value
              maxJourneys: 20,
              maxTemplates: 100,
              maxStorageBytes: 10737418240,
              maxMessagesPerMonth: 100000,
              createdAt: new Date(),
              updatedAt: new Date(),
            }])
          })
        })
      });

      const result = await upsertWorkspaceQuota(mockWorkspaceId, {
        maxSegments: 75,
      });

      expect(result.isOk()).toBe(true);
      if (result.isOk()) {
        expect(result.value.maxSegments).toBe(75);
      }
    });
  });

  describe("workspace ID validation", () => {
    it("should correctly identify valid UUID format", () => {
      expect(validate(mockWorkspaceId)).toBe(true);
      expect(validate(mockInvalidWorkspaceId)).toBe(false);
      expect(validate("")).toBe(false);
      expect(validate("123")).toBe(false);
    });
  });

  describe("error handling", () => {
    it("should handle database errors gracefully", async () => {
      const mockGetWorkspaceQuotaLimits = getWorkspaceQuotaLimits as jest.MockedFunction<typeof getWorkspaceQuotaLimits>;
      mockGetWorkspaceQuotaLimits.mockResolvedValue(null); // Simulate database error

      const result = await validateWorkspaceQuota(
        mockWorkspaceId,
        "segments",
        1
      );

      expect(result.isErr()).toBe(true);
      if (result.isErr()) {
        expect(result.error.message).toContain("Failed to retrieve quota information");
      }
    });

    it("should handle unexpected errors during validation", async () => {
      const mockGetWorkspaceQuotaLimits = getWorkspaceQuotaLimits as jest.MockedFunction<typeof getWorkspaceQuotaLimits>;
      mockGetWorkspaceQuotaLimits.mockRejectedValue(new Error("Database connection failed"));

      const result = await validateWorkspaceQuota(
        mockWorkspaceId,
        "segments",
        1
      );

      expect(result.isErr()).toBe(true);
      if (result.isErr()) {
        expect(result.error.message).toContain("Internal error during quota validation");
      }
    });
  });
});
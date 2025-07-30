import { validate } from "uuid";
import { describe, expect, it, beforeEach, afterEach, jest } from "@jest/globals";
import { sql } from "drizzle-orm";

import {
  setWorkspaceContext,
  clearWorkspaceContext,
  withWorkspaceContext,
  getCurrentWorkspaceContext,
  validateRLSConfiguration,
  RLS_POLICIES,
  RLS_PROTECTED_TABLES,
} from "../policies";

// Mock dependencies
jest.mock("../index", () => ({
  db: jest.fn(() => ({
    execute: jest.fn(),
    transaction: jest.fn(),
  })),
}));

jest.mock("../../logger", () => ({
  __esModule: true,
  default: jest.fn(() => ({
    debug: jest.fn(),
    error: jest.fn(),
    warn: jest.fn(),
  })),
}));

describe("RLS Policies", () => {
  const mockWorkspaceId = "550e8400-e29b-41d4-a716-446655440000";
  const mockInvalidWorkspaceId = "invalid-workspace-id";

  beforeEach(() => {
    jest.clearAllMocks();
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  describe("setWorkspaceContext", () => {
    it("should reject invalid workspace ID format", async () => {
      await expect(setWorkspaceContext(mockInvalidWorkspaceId)).rejects.toThrow(
        "Invalid workspace ID format"
      );
    });

    it("should execute SET LOCAL command with valid workspace ID", async () => {
      const mockDb = require("../index").db();
      mockDb.execute.mockResolvedValue(undefined);

      await setWorkspaceContext(mockWorkspaceId);

      expect(mockDb.execute).toHaveBeenCalledWith(
        expect.objectContaining({
          _: expect.objectContaining({
            type: "sql",
          }),
        })
      );
    });

    it("should handle database errors gracefully", async () => {
      const mockDb = require("../index").db();
      mockDb.execute.mockRejectedValue(new Error("Database connection failed"));

      await expect(setWorkspaceContext(mockWorkspaceId)).rejects.toThrow(
        "Database connection failed"
      );
    });
  });

  describe("clearWorkspaceContext", () => {
    it("should execute SET LOCAL command to clear context", async () => {
      const mockDb = require("../index").db();
      mockDb.execute.mockResolvedValue(undefined);

      await clearWorkspaceContext();

      expect(mockDb.execute).toHaveBeenCalledWith(
        expect.objectContaining({
          _: expect.objectContaining({
            type: "sql",
          }),
        })
      );
    });

    it("should handle database errors gracefully", async () => {
      const mockDb = require("../index").db();
      mockDb.execute.mockRejectedValue(new Error("Failed to clear context"));

      await expect(clearWorkspaceContext()).rejects.toThrow(
        "Failed to clear context"
      );
    });
  });

  describe("withWorkspaceContext", () => {
    it("should reject invalid workspace ID format", async () => {
      const mockFn = jest.fn().mockResolvedValue("test result");

      await expect(
        withWorkspaceContext(mockInvalidWorkspaceId, mockFn)
      ).rejects.toThrow("Invalid workspace ID format");

      expect(mockFn).not.toHaveBeenCalled();
    });

    it("should execute function within transaction with workspace context", async () => {
      const mockDb = require("../index").db();
      const mockTransaction = jest.fn();
      const mockExecute = jest.fn().mockResolvedValue(undefined);
      const mockFn = jest.fn().mockResolvedValue("test result");

      mockTransaction.mockImplementation(async (callback) => {
        const mockTx = { execute: mockExecute };
        return await callback(mockTx);
      });
      mockDb.transaction = mockTransaction;

      const result = await withWorkspaceContext(mockWorkspaceId, mockFn);

      expect(result).toBe("test result");
      expect(mockTransaction).toHaveBeenCalled();
      expect(mockExecute).toHaveBeenCalledWith(
        expect.objectContaining({
          _: expect.objectContaining({
            type: "sql",
          }),
        })
      );
      expect(mockFn).toHaveBeenCalled();
    });

    it("should propagate function errors", async () => {
      const mockDb = require("../index").db();
      const mockTransaction = jest.fn();
      const mockExecute = jest.fn().mockResolvedValue(undefined);
      const mockError = new Error("Function failed");
      const mockFn = jest.fn().mockRejectedValue(mockError);

      mockTransaction.mockImplementation(async (callback) => {
        const mockTx = { execute: mockExecute };
        return await callback(mockTx);
      });
      mockDb.transaction = mockTransaction;

      await expect(
        withWorkspaceContext(mockWorkspaceId, mockFn)
      ).rejects.toThrow("Function failed");
    });

    it("should handle transaction errors", async () => {
      const mockDb = require("../index").db();
      const mockTransaction = jest.fn().mockRejectedValue(
        new Error("Transaction failed")
      );
      const mockFn = jest.fn();

      mockDb.transaction = mockTransaction;

      await expect(
        withWorkspaceContext(mockWorkspaceId, mockFn)
      ).rejects.toThrow("Transaction failed");

      expect(mockFn).not.toHaveBeenCalled();
    });
  });

  describe("getCurrentWorkspaceContext", () => {
    it("should return workspace ID when context is set", async () => {
      const mockDb = require("../index").db();
      mockDb.execute.mockResolvedValue([
        { workspace_id: mockWorkspaceId }
      ]);

      const result = await getCurrentWorkspaceContext();

      expect(result).toBe(mockWorkspaceId);
      expect(mockDb.execute).toHaveBeenCalledWith(
        expect.objectContaining({
          _: expect.objectContaining({
            type: "sql",
          }),
        })
      );
    });

    it("should return null when context is empty", async () => {
      const mockDb = require("../index").db();
      mockDb.execute.mockResolvedValue([
        { workspace_id: "" }
      ]);

      const result = await getCurrentWorkspaceContext();

      expect(result).toBeNull();
    });

    it("should return null when context is not set", async () => {
      const mockDb = require("../index").db();
      mockDb.execute.mockResolvedValue([
        { workspace_id: null }
      ]);

      const result = await getCurrentWorkspaceContext();

      expect(result).toBeNull();
    });

    it("should return null for invalid workspace ID format", async () => {
      const mockDb = require("../index").db();
      mockDb.execute.mockResolvedValue([
        { workspace_id: "invalid-format" }
      ]);

      const result = await getCurrentWorkspaceContext();

      expect(result).toBeNull();
    });

    it("should handle database errors gracefully", async () => {
      const mockDb = require("../index").db();
      mockDb.execute.mockRejectedValue(new Error("Query failed"));

      const result = await getCurrentWorkspaceContext();

      expect(result).toBeNull();
    });
  });

  describe("validateRLSConfiguration", () => {
    it("should return true when RLS is enabled", async () => {
      const mockDb = require("../index").db();
      mockDb.execute.mockResolvedValue([
        { relrowsecurity: true }
      ]);

      const result = await validateRLSConfiguration("Segment");

      expect(result).toBe(true);
      expect(mockDb.execute).toHaveBeenCalledWith(
        expect.objectContaining({
          _: expect.objectContaining({
            type: "sql",
          }),
        })
      );
    });

    it("should return false when RLS is disabled", async () => {
      const mockDb = require("../index").db();
      mockDb.execute.mockResolvedValue([
        { relrowsecurity: false }
      ]);

      const result = await validateRLSConfiguration("Journey");

      expect(result).toBe(false);
    });

    it("should return false when table is not found", async () => {
      const mockDb = require("../index").db();
      mockDb.execute.mockResolvedValue([]);

      const result = await validateRLSConfiguration("NonExistentTable" as any);

      expect(result).toBe(false);
    });

    it("should handle database errors gracefully", async () => {
      const mockDb = require("../index").db();
      mockDb.execute.mockRejectedValue(new Error("Permission denied"));

      const result = await validateRLSConfiguration("MessageTemplate");

      expect(result).toBe(false);
    });
  });

  describe("RLS constants", () => {
    it("should define all required policy names", () => {
      expect(RLS_POLICIES.SEGMENT_WORKSPACE_ISOLATION).toBe("segment_workspace_isolation");
      expect(RLS_POLICIES.JOURNEY_WORKSPACE_ISOLATION).toBe("journey_workspace_isolation");
      expect(RLS_POLICIES.MESSAGE_TEMPLATE_WORKSPACE_ISOLATION).toBe("message_template_workspace_isolation");
      expect(RLS_POLICIES.EMAIL_TEMPLATE_WORKSPACE_ISOLATION).toBe("email_template_workspace_isolation");
      expect(RLS_POLICIES.BROADCAST_WORKSPACE_ISOLATION).toBe("broadcast_workspace_isolation");
      expect(RLS_POLICIES.USER_PROPERTY_WORKSPACE_ISOLATION).toBe("user_property_workspace_isolation");
      expect(RLS_POLICIES.USER_PROPERTY_ASSIGNMENT_WORKSPACE_ISOLATION).toBe("user_property_assignment_workspace_isolation");
      expect(RLS_POLICIES.EMAIL_PROVIDER_WORKSPACE_ISOLATION).toBe("email_provider_workspace_isolation");
      expect(RLS_POLICIES.SUBSCRIPTION_GROUP_WORKSPACE_ISOLATION).toBe("subscription_group_workspace_isolation");
      expect(RLS_POLICIES.INTEGRATION_WORKSPACE_ISOLATION).toBe("integration_workspace_isolation");
      expect(RLS_POLICIES.SECRET_WORKSPACE_ISOLATION).toBe("secret_workspace_isolation");
      expect(RLS_POLICIES.WRITE_KEY_WORKSPACE_ISOLATION).toBe("write_key_workspace_isolation");
    });

    it("should define all protected table names", () => {
      const expectedTables = [
        "Segment",
        "Journey", 
        "MessageTemplate",
        "EmailTemplate",
        "Broadcast",
        "UserProperty",
        "UserPropertyAssignment",
        "EmailProvider",
        "SubscriptionGroup",
        "Integration",
        "Secret",
        "WriteKey",
      ];

      expect(RLS_PROTECTED_TABLES).toEqual(expectedTables);
      expect(RLS_PROTECTED_TABLES.length).toBe(expectedTables.length);
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

  describe("integration scenarios", () => {
    it("should handle complete workflow: set context, validate, clear", async () => {
      const mockDb = require("../index").db();
      mockDb.execute.mockResolvedValue([{ workspace_id: mockWorkspaceId }]);

      // Set context
      await setWorkspaceContext(mockWorkspaceId);
      
      // Validate context is set
      const currentContext = await getCurrentWorkspaceContext();
      expect(currentContext).toBe(mockWorkspaceId);

      // Clear context  
      await clearWorkspaceContext();
      
      // Multiple execute calls should have been made
      expect(mockDb.execute).toHaveBeenCalledTimes(3);
    });

    it("should validate RLS configuration for all protected tables", async () => {
      const mockDb = require("../index").db();
      mockDb.execute.mockResolvedValue([{ relrowsecurity: true }]);

      for (const tableName of RLS_PROTECTED_TABLES) {
        const result = await validateRLSConfiguration(tableName);
        expect(result).toBe(true);
      }

      expect(mockDb.execute).toHaveBeenCalledTimes(RLS_PROTECTED_TABLES.length);
    });
  });
});
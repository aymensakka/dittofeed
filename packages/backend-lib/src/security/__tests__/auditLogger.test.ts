import { randomUUID } from "crypto";
import { validate } from "uuid";
import { describe, expect, it, beforeEach, afterEach, jest } from "@jest/globals";

import {
  auditLog,
  auditUserLogin,
  auditApiKeyAccess,
  auditWorkspaceAccess,
  auditWorkspaceContextSet,
  auditResourceAccess,
  auditQuotaEvent,
  auditSuspiciousActivity,
  auditDataOperation,
  createAuditContext,
  AuditEventType,
  AuditSeverity,
} from "../auditLogger";

// Mock dependencies
jest.mock("../../logger", () => ({
  __esModule: true,
  default: jest.fn(() => ({
    info: jest.fn(),
    error: jest.fn(),
  })),
}));

jest.mock("crypto", () => ({
  randomUUID: jest.fn(() => "mocked-uuid-1234"),
}));

describe("AuditLogger", () => {
  const mockWorkspaceId = "550e8400-e29b-41d4-a716-446655440000";
  const mockUserId = "user-123";
  const mockUserEmail = "test@example.com";
  const mockInvalidWorkspaceId = "invalid-workspace-id";

  beforeEach(() => {
    jest.clearAllMocks();
    // Mock Date.now() for consistent timestamps in tests
    jest.spyOn(Date, 'now').mockImplementation(() => 1234567890000);
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  describe("auditLog", () => {
    it("should log audit event with correct structure", () => {
      const mockLogger = require("../../logger").default();
      
      auditLog(
        AuditEventType.USER_LOGIN,
        AuditSeverity.LOW,
        "Test audit message",
        { userId: mockUserId },
        true
      );

      expect(mockLogger.info).toHaveBeenCalledWith(
        expect.objectContaining({
          audit: true,
          id: "mocked-uuid-1234",
          timestamp: expect.any(Date),
          eventType: AuditEventType.USER_LOGIN,
          severity: AuditSeverity.LOW,
          message: "Test audit message",
          context: { userId: mockUserId },
          success: true,
        }),
        "AUDIT: Test audit message"
      );
    });

    it("should log critical events at error level", () => {
      const mockLogger = require("../../logger").default();
      
      auditLog(
        AuditEventType.SUSPICIOUS_ACTIVITY,
        AuditSeverity.CRITICAL,
        "Critical security event",
        {},
        false,
        "Security breach detected"
      );

      expect(mockLogger.info).toHaveBeenCalled();
      expect(mockLogger.error).toHaveBeenCalledWith(
        expect.objectContaining({
          audit: true,
          critical: true,
          eventType: AuditEventType.SUSPICIOUS_ACTIVITY,
          severity: AuditSeverity.CRITICAL,
          message: "Critical security event",
          success: false,
          error: "Security breach detected",
        }),
        "CRITICAL AUDIT: Critical security event"
      );
    });

    it("should include error message when provided", () => {
      const mockLogger = require("../../logger").default();
      
      auditLog(
        AuditEventType.USER_LOGIN_FAILED,
        AuditSeverity.MEDIUM,
        "Login failed",
        { userEmail: mockUserEmail },
        false,
        "Invalid credentials"
      );

      expect(mockLogger.info).toHaveBeenCalledWith(
        expect.objectContaining({
          error: "Invalid credentials",
          success: false,
        }),
        "AUDIT: Login failed"
      );
    });
  });

  describe("auditUserLogin", () => {
    it("should log successful user login", () => {
      const mockLogger = require("../../logger").default();
      
      auditUserLogin(
        mockUserId,
        mockUserEmail,
        mockWorkspaceId,
        true,
        { ipAddress: "192.168.1.1" }
      );

      expect(mockLogger.info).toHaveBeenCalledWith(
        expect.objectContaining({
          eventType: AuditEventType.USER_LOGIN,
          severity: AuditSeverity.LOW,
          message: "User login successful",
          context: {
            userId: mockUserId,
            userEmail: mockUserEmail,
            workspaceId: mockWorkspaceId,
            ipAddress: "192.168.1.1",
          },
          success: true,
        }),
        "AUDIT: User login successful"
      );
    });

    it("should log failed user login", () => {
      const mockLogger = require("../../logger").default();
      
      auditUserLogin(
        mockUserId,
        mockUserEmail,
        mockWorkspaceId,
        false,
        { ipAddress: "192.168.1.1" }
      );

      expect(mockLogger.info).toHaveBeenCalledWith(
        expect.objectContaining({
          eventType: AuditEventType.USER_LOGIN_FAILED,
          severity: AuditSeverity.MEDIUM,
          message: "User login failed",
          success: false,
        }),
        "AUDIT: User login failed"
      );
    });
  });

  describe("auditApiKeyAccess", () => {
    it("should log successful API key access", () => {
      const mockLogger = require("../../logger").default();
      const mockKeyId = "key-123";
      
      auditApiKeyAccess(
        mockWorkspaceId,
        mockKeyId,
        true,
        { requestId: "req-123" }
      );

      expect(mockLogger.info).toHaveBeenCalledWith(
        expect.objectContaining({
          eventType: AuditEventType.API_KEY_ACCESS,
          severity: AuditSeverity.LOW,
          message: "API key access successful",
          context: {
            workspaceId: mockWorkspaceId,
            resourceId: mockKeyId,
            resourceType: "api_key",
            requestId: "req-123",
          },
          success: true,
        }),
        "AUDIT: API key access successful"
      );
    });

    it("should log suspicious activity for invalid workspace ID", () => {
      const mockLogger = require("../../logger").default();
      const mockKeyId = "key-123";
      
      auditApiKeyAccess(
        mockInvalidWorkspaceId,
        mockKeyId,
        true
      );

      expect(mockLogger.info).toHaveBeenCalledWith(
        expect.objectContaining({
          eventType: AuditEventType.SUSPICIOUS_ACTIVITY,
          severity: AuditSeverity.HIGH,
          message: "Invalid workspace ID format in API key access",
          context: {
            workspaceId: mockInvalidWorkspaceId,
            keyId: mockKeyId,
          },
          success: false,
          error: "Invalid UUID format",
        }),
        "AUDIT: Invalid workspace ID format in API key access"
      );
    });

    it("should log failed API key access", () => {
      const mockLogger = require("../../logger").default();
      const mockKeyId = "key-123";
      
      auditApiKeyAccess(
        mockWorkspaceId,
        mockKeyId,
        false
      );

      expect(mockLogger.info).toHaveBeenCalledWith(
        expect.objectContaining({
          eventType: AuditEventType.API_KEY_ACCESS_FAILED,
          severity: AuditSeverity.MEDIUM,
          message: "API key access failed",
          success: false,
        }),
        "AUDIT: API key access failed"
      );
    });
  });

  describe("auditWorkspaceAccess", () => {
    it("should log successful workspace access", () => {
      const mockLogger = require("../../logger").default();
      
      auditWorkspaceAccess(
        mockWorkspaceId,
        mockUserId,
        true,
        { requestId: "req-456" }
      );

      expect(mockLogger.info).toHaveBeenCalledWith(
        expect.objectContaining({
          eventType: AuditEventType.WORKSPACE_ACCESS,
          severity: AuditSeverity.LOW,
          message: "Workspace access granted",
          context: {
            workspaceId: mockWorkspaceId,
            userId: mockUserId,
            requestId: "req-456",
          },
          success: true,
        }),
        "AUDIT: Workspace access granted"
      );
    });

    it("should log denied workspace access", () => {
      const mockLogger = require("../../logger").default();
      
      auditWorkspaceAccess(
        mockWorkspaceId,
        mockUserId,
        false
      );

      expect(mockLogger.info).toHaveBeenCalledWith(
        expect.objectContaining({
          eventType: AuditEventType.WORKSPACE_ACCESS_DENIED,
          severity: AuditSeverity.HIGH,
          message: "Workspace access denied",
          success: false,
        }),
        "AUDIT: Workspace access denied"
      );
    });

    it("should log suspicious activity for invalid workspace ID", () => {
      const mockLogger = require("../../logger").default();
      
      auditWorkspaceAccess(
        mockInvalidWorkspaceId,
        mockUserId,
        true
      );

      expect(mockLogger.info).toHaveBeenCalledWith(
        expect.objectContaining({
          eventType: AuditEventType.SUSPICIOUS_ACTIVITY,
          severity: AuditSeverity.HIGH,
          message: "Invalid workspace ID format in workspace access",
          success: false,
        }),
        "AUDIT: Invalid workspace ID format in workspace access"
      );
    });
  });

  describe("auditWorkspaceContextSet", () => {
    it("should log successful RLS context setting", () => {
      const mockLogger = require("../../logger").default();
      
      auditWorkspaceContextSet(
        mockWorkspaceId,
        true,
        { requestId: "req-789" }
      );

      expect(mockLogger.info).toHaveBeenCalledWith(
        expect.objectContaining({
          eventType: AuditEventType.WORKSPACE_CONTEXT_SET,
          severity: AuditSeverity.LOW,
          message: "RLS workspace context set",
          context: {
            workspaceId: mockWorkspaceId,
            requestId: "req-789",
          },
          success: true,
        }),
        "AUDIT: RLS workspace context set"
      );
    });

    it("should log failed RLS context setting", () => {
      const mockLogger = require("../../logger").default();
      
      auditWorkspaceContextSet(
        mockWorkspaceId,
        false
      );

      expect(mockLogger.info).toHaveBeenCalledWith(
        expect.objectContaining({
          eventType: AuditEventType.WORKSPACE_CONTEXT_FAILED,
          severity: AuditSeverity.HIGH,
          message: "Failed to set RLS workspace context",
          success: false,
        }),
        "AUDIT: Failed to set RLS workspace context"
      );
    });
  });

  describe("auditResourceAccess", () => {
    it("should log successful resource creation", () => {
      const mockLogger = require("../../logger").default();
      
      auditResourceAccess(
        AuditEventType.RESOURCE_CREATED,
        mockWorkspaceId,
        "segment",
        "segment-123",
        mockUserId,
        true,
        { resourceName: "Marketing Segment" }
      );

      expect(mockLogger.info).toHaveBeenCalledWith(
        expect.objectContaining({
          eventType: AuditEventType.RESOURCE_CREATED,
          severity: AuditSeverity.LOW,
          message: "Resource created successful",
          context: {
            workspaceId: mockWorkspaceId,
            resourceType: "segment",
            resourceId: "segment-123",
            userId: mockUserId,
            resourceName: "Marketing Segment",
          },
          success: true,
        }),
        "AUDIT: Resource created successful"
      );
    });

    it("should log resource access denial", () => {
      const mockLogger = require("../../logger").default();
      
      auditResourceAccess(
        AuditEventType.RESOURCE_ACCESS_DENIED,
        mockWorkspaceId,
        "journey",
        "journey-456",
        mockUserId,
        false
      );

      expect(mockLogger.info).toHaveBeenCalledWith(
        expect.objectContaining({
          eventType: AuditEventType.RESOURCE_ACCESS_DENIED,
          severity: AuditSeverity.HIGH,
          message: "Resource access_denied failed",
          success: false,
        }),
        "AUDIT: Resource access_denied failed"
      );
    });

    it("should log suspicious activity for invalid workspace ID", () => {
      const mockLogger = require("../../logger").default();
      
      auditResourceAccess(
        AuditEventType.RESOURCE_UPDATED,
        mockInvalidWorkspaceId,
        "template",
        "template-789",
        mockUserId,
        true
      );

      expect(mockLogger.info).toHaveBeenCalledWith(
        expect.objectContaining({
          eventType: AuditEventType.SUSPICIOUS_ACTIVITY,
          severity: AuditSeverity.HIGH,
          message: "Invalid workspace ID format in resource access",
          success: false,
        }),
        "AUDIT: Invalid workspace ID format in resource access"
      );
    });
  });

  describe("auditQuotaEvent", () => {
    it("should log quota exceeded event", () => {
      const mockLogger = require("../../logger").default();
      
      auditQuotaEvent(
        AuditEventType.QUOTA_EXCEEDED,
        mockWorkspaceId,
        "segments",
        50,
        50,
        { attemptedIncrement: 1 }
      );

      expect(mockLogger.info).toHaveBeenCalledWith(
        expect.objectContaining({
          eventType: AuditEventType.QUOTA_EXCEEDED,
          severity: AuditSeverity.HIGH,
          message: "Quota exceeded for segments",
          context: {
            workspaceId: mockWorkspaceId,
            resourceType: "segments",
            metadata: {
              currentUsage: 50,
              limit: 50,
              usagePercentage: 100,
            },
            attemptedIncrement: 1,
          },
          success: false,
        }),
        "AUDIT: Quota exceeded for segments"
      );
    });

    it("should log quota warning event", () => {
      const mockLogger = require("../../logger").default();
      
      auditQuotaEvent(
        AuditEventType.QUOTA_WARNING,
        mockWorkspaceId,
        "journeys",
        18,
        20
      );

      expect(mockLogger.info).toHaveBeenCalledWith(
        expect.objectContaining({
          eventType: AuditEventType.QUOTA_WARNING,
          severity: AuditSeverity.MEDIUM,
          message: "Quota warning for journeys",
          context: {
            metadata: {
              currentUsage: 18,
              limit: 20,
              usagePercentage: 90,
            },
          },
          success: true,
        }),
        "AUDIT: Quota warning for journeys"
      );
    });

    it("should log quota updated event", () => {
      const mockLogger = require("../../logger").default();
      
      auditQuotaEvent(
        AuditEventType.QUOTA_UPDATED,
        mockWorkspaceId,
        "users",
        500,
        1000
      );

      expect(mockLogger.info).toHaveBeenCalledWith(
        expect.objectContaining({
          eventType: AuditEventType.QUOTA_UPDATED,
          severity: AuditSeverity.MEDIUM,
          message: "Quota updated for users",
          success: true,
        }),
        "AUDIT: Quota updated for users"
      );
    });
  });

  describe("auditSuspiciousActivity", () => {
    it("should log suspicious activity as critical", () => {
      const mockLogger = require("../../logger").default();
      
      auditSuspiciousActivity(
        "Multiple failed login attempts",
        mockWorkspaceId,
        mockUserId,
        { ipAddress: "192.168.1.100", attemptCount: 5 }
      );

      expect(mockLogger.info).toHaveBeenCalledWith(
        expect.objectContaining({
          eventType: AuditEventType.SUSPICIOUS_ACTIVITY,
          severity: AuditSeverity.CRITICAL,
          message: "Multiple failed login attempts",
          context: {
            workspaceId: mockWorkspaceId,
            userId: mockUserId,
            ipAddress: "192.168.1.100",
            attemptCount: 5,
          },
          success: false,
          error: "Suspicious activity detected",
        }),
        "AUDIT: Multiple failed login attempts"
      );

      expect(mockLogger.error).toHaveBeenCalledWith(
        expect.objectContaining({
          critical: true,
        }),
        "CRITICAL AUDIT: Multiple failed login attempts"
      );
    });
  });

  describe("auditDataOperation", () => {
    it("should log data export operation", () => {
      const mockLogger = require("../../logger").default();
      
      auditDataOperation(
        AuditEventType.DATA_EXPORT,
        mockWorkspaceId,
        mockUserId,
        1000,
        { exportFormat: "CSV", fileName: "users_export.csv" }
      );

      expect(mockLogger.info).toHaveBeenCalledWith(
        expect.objectContaining({
          eventType: AuditEventType.DATA_EXPORT,
          severity: AuditSeverity.MEDIUM,
          message: "Data export operation",
          context: {
            workspaceId: mockWorkspaceId,
            userId: mockUserId,
            metadata: {
              recordCount: 1000,
            },
            exportFormat: "CSV",
            fileName: "users_export.csv",
          },
        }),
        "AUDIT: Data export operation"
      );
    });

    it("should log bulk operation", () => {
      const mockLogger = require("../../logger").default();
      
      auditDataOperation(
        AuditEventType.BULK_OPERATION,
        mockWorkspaceId,
        mockUserId,
        500,
        { operation: "bulk_update", table: "segments" }
      );

      expect(mockLogger.info).toHaveBeenCalledWith(
        expect.objectContaining({
          eventType: AuditEventType.BULK_OPERATION,
          message: "Data operation operation",
          context: {
            metadata: {
              recordCount: 500,
            },
            operation: "bulk_update",
            table: "segments",
          },
        }),
        "AUDIT: Data operation operation"
      );
    });
  });

  describe("createAuditContext", () => {
    it("should create audit context with all fields", () => {
      const context = createAuditContext(
        "req-123",
        "session-456",
        "Mozilla/5.0",
        "192.168.1.1",
        {
          workspaceId: mockWorkspaceId,
          userId: mockUserId,
          resourceType: "segment",
        }
      );

      expect(context).toEqual({
        requestId: "req-123",
        sessionId: "session-456",
        userAgent: "Mozilla/5.0",
        ipAddress: "192.168.1.1",
        workspaceId: mockWorkspaceId,
        userId: mockUserId,
        resourceType: "segment",
      });
    });

    it("should create audit context with partial fields", () => {
      const context = createAuditContext(
        "req-123",
        undefined,
        undefined,
        "192.168.1.1"
      );

      expect(context).toEqual({
        requestId: "req-123",
        sessionId: undefined,
        userAgent: undefined,
        ipAddress: "192.168.1.1",
      });
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

  describe("audit event types and severities", () => {
    it("should have all required event types", () => {
      expect(AuditEventType.USER_LOGIN).toBe("USER_LOGIN");
      expect(AuditEventType.USER_LOGOUT).toBe("USER_LOGOUT");
      expect(AuditEventType.WORKSPACE_ACCESS).toBe("WORKSPACE_ACCESS");
      expect(AuditEventType.QUOTA_EXCEEDED).toBe("QUOTA_EXCEEDED");
      expect(AuditEventType.SUSPICIOUS_ACTIVITY).toBe("SUSPICIOUS_ACTIVITY");
      expect(AuditEventType.DATA_EXPORT).toBe("DATA_EXPORT");
    });

    it("should have all required severity levels", () => {
      expect(AuditSeverity.LOW).toBe("LOW");
      expect(AuditSeverity.MEDIUM).toBe("MEDIUM");
      expect(AuditSeverity.HIGH).toBe("HIGH");
      expect(AuditSeverity.CRITICAL).toBe("CRITICAL");
    });
  });
});
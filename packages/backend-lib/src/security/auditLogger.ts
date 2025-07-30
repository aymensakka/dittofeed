import { randomUUID } from "crypto";
import { validate } from "uuid";

import logger from "../logger";

/**
 * Comprehensive audit logging for multi-tenant security events
 * 
 * This module provides structured audit logging for security-critical events
 * in the multi-tenant environment, including tenant boundary crossings,
 * authentication events, and resource access patterns.
 */

export enum AuditEventType {
  // Authentication Events
  USER_LOGIN = "USER_LOGIN",
  USER_LOGOUT = "USER_LOGOUT", 
  USER_LOGIN_FAILED = "USER_LOGIN_FAILED",
  API_KEY_ACCESS = "API_KEY_ACCESS",
  API_KEY_ACCESS_FAILED = "API_KEY_ACCESS_FAILED",
  
  // Workspace/Tenant Events
  WORKSPACE_ACCESS = "WORKSPACE_ACCESS",
  WORKSPACE_ACCESS_DENIED = "WORKSPACE_ACCESS_DENIED",
  WORKSPACE_CONTEXT_SET = "WORKSPACE_CONTEXT_SET",
  WORKSPACE_CONTEXT_FAILED = "WORKSPACE_CONTEXT_FAILED",
  
  // Resource Access Events
  RESOURCE_CREATED = "RESOURCE_CREATED",
  RESOURCE_UPDATED = "RESOURCE_UPDATED",
  RESOURCE_DELETED = "RESOURCE_DELETED",
  RESOURCE_ACCESS_DENIED = "RESOURCE_ACCESS_DENIED",
  
  // Quota Events
  QUOTA_EXCEEDED = "QUOTA_EXCEEDED",
  QUOTA_WARNING = "QUOTA_WARNING",
  QUOTA_UPDATED = "QUOTA_UPDATED",
  
  // Security Events
  SUSPICIOUS_ACTIVITY = "SUSPICIOUS_ACTIVITY",
  RATE_LIMIT_EXCEEDED = "RATE_LIMIT_EXCEEDED",
  UNAUTHORIZED_ACCESS_ATTEMPT = "UNAUTHORIZED_ACCESS_ATTEMPT",
  
  // Data Events
  DATA_EXPORT = "DATA_EXPORT",
  DATA_IMPORT = "DATA_IMPORT",
  BULK_OPERATION = "BULK_OPERATION",
}

export enum AuditSeverity {
  LOW = "LOW",
  MEDIUM = "MEDIUM", 
  HIGH = "HIGH",
  CRITICAL = "CRITICAL",
}

export interface AuditContext {
  // Request Context
  requestId?: string;
  sessionId?: string;
  userAgent?: string;
  ipAddress?: string;
  
  // User Context
  userId?: string;
  userEmail?: string;
  
  // Workspace Context
  workspaceId?: string;
  workspaceName?: string;
  
  // Resource Context
  resourceType?: string;
  resourceId?: string;
  resourceName?: string;
  
  // Additional metadata
  metadata?: Record<string, unknown>;
}

export interface AuditEvent {
  id: string;
  timestamp: Date;
  eventType: AuditEventType;
  severity: AuditSeverity;
  message: string;
  context: AuditContext;
  success: boolean;
  error?: string;
}

/**
 * Core audit logging function
 * 
 * @param eventType - The type of security event
 * @param severity - The severity level of the event
 * @param message - Human-readable description of the event
 * @param context - Additional context about the event
 * @param success - Whether the operation was successful
 * @param error - Error message if the operation failed
 */
export function auditLog(
  eventType: AuditEventType,
  severity: AuditSeverity,
  message: string,
  context: AuditContext = {},
  success: boolean = true,
  error?: string
): void {
  const auditEvent: AuditEvent = {
    id: randomUUID(),
    timestamp: new Date(),
    eventType,
    severity,
    message,
    context,
    success,
    error,
  };

  // Log to structured logger with audit prefix
  logger().info(
    {
      audit: true,
      ...auditEvent,
    },
    `AUDIT: ${message}`
  );

  // For critical events, also log at error level
  if (severity === AuditSeverity.CRITICAL) {
    logger().error(
      {
        audit: true,
        critical: true,
        ...auditEvent,
      },
      `CRITICAL AUDIT: ${message}`
    );
  }
}

/**
 * Log user authentication events
 */
export function auditUserLogin(
  userId: string,
  userEmail: string,
  workspaceId?: string,
  success: boolean = true,
  context: Partial<AuditContext> = {}
): void {
  auditLog(
    success ? AuditEventType.USER_LOGIN : AuditEventType.USER_LOGIN_FAILED,
    success ? AuditSeverity.LOW : AuditSeverity.MEDIUM,
    success ? "User login successful" : "User login failed",
    {
      userId,
      userEmail,
      workspaceId,
      ...context,
    },
    success
  );
}

/**
 * Log API key access events
 */
export function auditApiKeyAccess(
  workspaceId: string,
  keyId: string,
  success: boolean = true,
  context: Partial<AuditContext> = {}
): void {
  // Validate workspace ID format for security
  if (!validate(workspaceId)) {
    auditLog(
      AuditEventType.SUSPICIOUS_ACTIVITY,
      AuditSeverity.HIGH,
      "Invalid workspace ID format in API key access",
      { workspaceId, keyId, ...context },
      false,
      "Invalid UUID format"
    );
    return;
  }

  auditLog(
    success ? AuditEventType.API_KEY_ACCESS : AuditEventType.API_KEY_ACCESS_FAILED,
    success ? AuditSeverity.LOW : AuditSeverity.MEDIUM,
    success ? "API key access successful" : "API key access failed",
    {
      workspaceId,
      resourceId: keyId,
      resourceType: "api_key",
      ...context,
    },
    success
  );
}

/**
 * Log workspace access events
 */
export function auditWorkspaceAccess(
  workspaceId: string,
  userId?: string,
  success: boolean = true,
  context: Partial<AuditContext> = {}
): void {
  // Validate workspace ID format for security
  if (!validate(workspaceId)) {
    auditLog(
      AuditEventType.SUSPICIOUS_ACTIVITY,
      AuditSeverity.HIGH,
      "Invalid workspace ID format in workspace access",
      { workspaceId, userId, ...context },
      false,
      "Invalid UUID format"
    );
    return;
  }

  auditLog(
    success ? AuditEventType.WORKSPACE_ACCESS : AuditEventType.WORKSPACE_ACCESS_DENIED,
    success ? AuditSeverity.LOW : AuditSeverity.HIGH,
    success ? "Workspace access granted" : "Workspace access denied",
    {
      workspaceId,
      userId,
      ...context,
    },
    success
  );
}

/**
 * Log RLS workspace context events
 */
export function auditWorkspaceContextSet(
  workspaceId: string,
  success: boolean = true,
  context: Partial<AuditContext> = {}
): void {
  auditLog(
    success ? AuditEventType.WORKSPACE_CONTEXT_SET : AuditEventType.WORKSPACE_CONTEXT_FAILED,
    success ? AuditSeverity.LOW : AuditSeverity.HIGH,
    success ? "RLS workspace context set" : "Failed to set RLS workspace context",
    {
      workspaceId,
      ...context,
    },
    success
  );
}

/**
 * Log resource access events
 */
export function auditResourceAccess(
  eventType: AuditEventType.RESOURCE_CREATED | AuditEventType.RESOURCE_UPDATED | AuditEventType.RESOURCE_DELETED | AuditEventType.RESOURCE_ACCESS_DENIED,
  workspaceId: string,
  resourceType: string,
  resourceId: string,
  userId?: string,
  success: boolean = true,
  context: Partial<AuditContext> = {}
): void {
  // Validate workspace ID format for security
  if (!validate(workspaceId)) {
    auditLog(
      AuditEventType.SUSPICIOUS_ACTIVITY,
      AuditSeverity.HIGH,
      "Invalid workspace ID format in resource access",
      { workspaceId, resourceType, resourceId, userId, ...context },
      false,
      "Invalid UUID format"
    );
    return;
  }

  const severity = success ? AuditSeverity.LOW : AuditSeverity.HIGH;
  const message = `Resource ${eventType.toLowerCase().replace('resource_', '')} ${success ? 'successful' : 'failed'}`;

  auditLog(
    eventType,
    severity,
    message,
    {
      workspaceId,
      resourceType,
      resourceId,
      userId,
      ...context,
    },
    success
  );
}

/**
 * Log quota-related events
 */
export function auditQuotaEvent(
  eventType: AuditEventType.QUOTA_EXCEEDED | AuditEventType.QUOTA_WARNING | AuditEventType.QUOTA_UPDATED,
  workspaceId: string,
  resourceType: string,
  currentUsage: number,
  limit: number,
  context: Partial<AuditContext> = {}
): void {
  const severity = eventType === AuditEventType.QUOTA_EXCEEDED ? AuditSeverity.HIGH : AuditSeverity.MEDIUM;
  
  auditLog(
    eventType,
    severity,
    `Quota ${eventType.toLowerCase().replace('quota_', '')} for ${resourceType}`,
    {
      workspaceId,
      resourceType,
      metadata: {
        currentUsage,
        limit,
        usagePercentage: Math.round((currentUsage / limit) * 100),
      },
      ...context,
    },
    eventType !== AuditEventType.QUOTA_EXCEEDED
  );
}

/**
 * Log suspicious activity
 */
export function auditSuspiciousActivity(
  message: string,
  workspaceId?: string,
  userId?: string,
  context: Partial<AuditContext> = {}
): void {
  auditLog(
    AuditEventType.SUSPICIOUS_ACTIVITY,
    AuditSeverity.CRITICAL,
    message,
    {
      workspaceId,
      userId,
      ...context,
    },
    false,
    "Suspicious activity detected"
  );
}

/**
 * Log data export/import events for compliance
 */
export function auditDataOperation(
  eventType: AuditEventType.DATA_EXPORT | AuditEventType.DATA_IMPORT | AuditEventType.BULK_OPERATION,
  workspaceId: string,
  userId: string,
  recordCount: number,
  context: Partial<AuditContext> = {}
): void {
  auditLog(
    eventType,
    AuditSeverity.MEDIUM,
    `Data ${eventType.toLowerCase().replace('data_', '')} operation`,
    {
      workspaceId,
      userId,
      metadata: {
        recordCount,
      },
      ...context,
    }
  );
}

/**
 * Create audit context from common request information
 */
export function createAuditContext(
  requestId?: string,
  sessionId?: string,
  userAgent?: string,
  ipAddress?: string,
  additionalContext: Partial<AuditContext> = {}
): AuditContext {
  return {
    requestId,
    sessionId,
    userAgent,
    ipAddress,
    ...additionalContext,
  };
}

/**
 * Get audit events for a workspace (for security monitoring)
 * This is a simplified implementation - in production you might want
 * to use a dedicated audit storage system
 */
export function getAuditEvents(
  workspaceId: string,
  eventTypes?: AuditEventType[],
  startDate?: Date,
  endDate?: Date,
  limit: number = 100
): AuditEvent[] {
  // This is a placeholder implementation
  // In a real system, you would query your audit log storage
  logger().debug(
    {
      workspaceId,
      eventTypes,
      startDate,
      endDate,
      limit,
    },
    "Audit events query requested"
  );
  
  return [];
}
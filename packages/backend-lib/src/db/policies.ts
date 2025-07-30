import { validate } from "uuid";
import { sql } from "drizzle-orm";
import { db } from "./index";
import logger from "../logger";

/**
 * Row-Level Security policy management for workspace-based tenant isolation
 * 
 * This module provides utilities to manage PostgreSQL RLS policies that ensure
 * workspace data isolation at the database level. All policies use the 
 * 'app.current_workspace_id' setting to enforce tenant boundaries.
 */

export interface RLSContext {
  workspaceId: string;
}

/**
 * Set the workspace context for the current database session.
 * This context is used by RLS policies to enforce workspace isolation.
 * 
 * @param workspaceId - The UUID of the workspace to set as context
 * @throws Error if workspaceId is not a valid UUID
 */
export async function setWorkspaceContext(workspaceId: string): Promise<void> {
  if (!validate(workspaceId)) {
    throw new Error(`Invalid workspace ID format: ${workspaceId}`);
  }

  try {
    await db().execute(
      sql`SET LOCAL app.current_workspace_id = ${workspaceId}`
    );
    
    logger().debug(
      { workspaceId },
      "Set RLS workspace context"
    );
  } catch (error) {
    logger().error(
      { error, workspaceId },
      "Failed to set RLS workspace context"
    );
    throw error;
  }
}

/**
 * Clear the workspace context for the current database session.
 * This removes the RLS context, effectively denying access to all RLS-protected tables.
 */
export async function clearWorkspaceContext(): Promise<void> {
  try {
    await db().execute(
      sql`SET LOCAL app.current_workspace_id = ''`
    );
    
    logger().debug("Cleared RLS workspace context");
  } catch (error) {
    logger().error(
      { error },
      "Failed to clear RLS workspace context"
    );
    throw error;
  }
}

/**
 * Execute a function within a specific workspace context.
 * This is the recommended way to perform database operations with RLS.
 * The workspace context is automatically set before execution and cleared after.
 * 
 * @param workspaceId - The UUID of the workspace context
 * @param fn - The function to execute within the workspace context
 * @returns The result of the function execution
 */
export async function withWorkspaceContext<T>(
  workspaceId: string,
  fn: () => Promise<T>
): Promise<T> {
  // Validate workspace ID format
  if (!validate(workspaceId)) {
    throw new Error(`Invalid workspace ID format: ${workspaceId}`);
  }

  return db().transaction(async (tx) => {
    // Set workspace context for this transaction
    await tx.execute(
      sql`SET LOCAL app.current_workspace_id = ${workspaceId}`
    );
    
    logger().debug(
      { workspaceId },
      "Executing function with workspace context"
    );

    try {
      return await fn();
    } catch (error) {
      logger().error(
        { error, workspaceId },
        "Error executing function with workspace context"
      );
      throw error;
    }
  });
}

/**
 * Get the current workspace context from the database session.
 * Returns null if no context is set.
 * 
 * @returns The current workspace ID or null if not set
 */
export async function getCurrentWorkspaceContext(): Promise<string | null> {
  try {
    const result = await db().execute(
      sql`SELECT current_setting('app.current_workspace_id', true) as workspace_id`
    );
    
    const workspaceId = result[0]?.workspace_id as string;
    
    // Return null if setting is empty or not set
    if (!workspaceId || workspaceId === '') {
      return null;
    }
    
    // Validate the workspace ID format
    if (!validate(workspaceId)) {
      logger().warn(
        { workspaceId },
        "Invalid workspace ID format in RLS context"
      );
      return null;
    }
    
    return workspaceId;
  } catch (error) {
    logger().error(
      { error },
      "Failed to get current workspace context"
    );
    return null;
  }
}

/**
 * RLS policy definitions for documentation and testing purposes.
 * These match the policies created in the migration files.
 */
export const RLS_POLICIES = {
  SEGMENT_WORKSPACE_ISOLATION: 'segment_workspace_isolation',
  JOURNEY_WORKSPACE_ISOLATION: 'journey_workspace_isolation',
  MESSAGE_TEMPLATE_WORKSPACE_ISOLATION: 'message_template_workspace_isolation',
  EMAIL_TEMPLATE_WORKSPACE_ISOLATION: 'email_template_workspace_isolation',
  BROADCAST_WORKSPACE_ISOLATION: 'broadcast_workspace_isolation',
  USER_PROPERTY_WORKSPACE_ISOLATION: 'user_property_workspace_isolation',
  USER_PROPERTY_ASSIGNMENT_WORKSPACE_ISOLATION: 'user_property_assignment_workspace_isolation',
  EMAIL_PROVIDER_WORKSPACE_ISOLATION: 'email_provider_workspace_isolation',
  SUBSCRIPTION_GROUP_WORKSPACE_ISOLATION: 'subscription_group_workspace_isolation',
  INTEGRATION_WORKSPACE_ISOLATION: 'integration_workspace_isolation',
  SECRET_WORKSPACE_ISOLATION: 'secret_workspace_isolation',
  WRITE_KEY_WORKSPACE_ISOLATION: 'write_key_workspace_isolation',
} as const;

/**
 * Tables protected by RLS policies.
 * This list should be kept in sync with the RLS migration files.
 */
export const RLS_PROTECTED_TABLES = [
  'Segment',
  'Journey', 
  'MessageTemplate',
  'EmailTemplate',
  'Broadcast',
  'UserProperty',
  'UserPropertyAssignment',
  'EmailProvider',
  'SubscriptionGroup',
  'Integration',
  'Secret',
  'WriteKey',
] as const;

export type RLSProtectedTable = typeof RLS_PROTECTED_TABLES[number];

/**
 * Validate that RLS is properly configured for a given table.
 * This is useful for testing and monitoring purposes.
 * 
 * @param tableName - The name of the table to check
 * @returns True if RLS is enabled, false otherwise
 */
export async function validateRLSConfiguration(tableName: RLSProtectedTable): Promise<boolean> {
  try {
    const result = await db().execute(
      sql`
        SELECT relrowsecurity 
        FROM pg_class 
        WHERE relname = ${tableName}
      `
    );
    
    const isEnabled = result[0]?.relrowsecurity as boolean;
    
    logger().debug(
      { tableName, isEnabled },
      "Checked RLS configuration for table"
    );
    
    return Boolean(isEnabled);
  } catch (error) {
    logger().error(
      { error, tableName },
      "Failed to validate RLS configuration"
    );
    return false;
  }
}
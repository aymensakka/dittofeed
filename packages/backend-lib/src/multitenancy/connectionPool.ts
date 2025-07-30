import { Pool, PoolConfig } from "pg";
import { validate } from "uuid";

import config from "../config";
import logger from "../logger";

/**
 * Tenant-aware connection pool management for enterprise multi-tenant workloads
 * 
 * This module optimizes database connections by managing separate pools per workspace,
 * improving performance and isolation for multi-tenant workloads. It automatically
 * sets workspace context for RLS and monitors connection usage per tenant.
 */

interface TenantPoolConfig extends PoolConfig {
  workspaceId: string;
  maxConnections?: number;
  idleTimeoutMillis?: number;
  connectionTimeoutMillis?: number;
}

interface PoolMetrics {
  totalCount: number;
  idleCount: number;
  waitingCount: number;
  createdAt: Date;
  lastUsedAt: Date;
}

export class TenantConnectionPool {
  private pools: Map<string, Pool>;
  private poolMetrics: Map<string, PoolMetrics>;
  private maxPoolsPerInstance: number;
  private defaultMaxConnections: number;
  private cleanupIntervalMs: number;
  private cleanupInterval?: NodeJS.Timeout;

  constructor() {
    this.pools = new Map();
    this.poolMetrics = new Map();
    
    // Configuration with sensible defaults
    this.maxPoolsPerInstance = 100; // Maximum number of workspace pools
    this.defaultMaxConnections = 5; // Max connections per workspace pool
    this.cleanupIntervalMs = 60000; // Cleanup idle pools every minute
    
    // Start cleanup interval
    this.startCleanupInterval();
  }

  /**
   * Get or create a connection pool for a specific workspace
   * 
   * @param workspaceId - The UUID of the workspace
   * @returns Promise resolving to the workspace's connection pool
   */
  async getPool(workspaceId: string): Promise<Pool> {
    // Validate workspace ID format
    if (!validate(workspaceId)) {
      throw new Error(`Invalid workspace ID format: ${workspaceId}`);
    }

    // Return existing pool if available
    if (this.pools.has(workspaceId)) {
      const pool = this.pools.get(workspaceId)!;
      this.updatePoolMetrics(workspaceId);
      return pool;
    }

    // Check if we've reached the maximum number of pools
    if (this.pools.size >= this.maxPoolsPerInstance) {
      await this.evictLeastRecentlyUsedPool();
    }

    // Create new pool for workspace
    const pool = await this.createWorkspacePool(workspaceId);
    this.pools.set(workspaceId, pool);
    this.initializePoolMetrics(workspaceId);

    logger().info(
      {
        workspaceId,
        totalPools: this.pools.size,
      },
      "Created new workspace connection pool"
    );

    return pool;
  }

  /**
   * Create a new connection pool with workspace-specific configuration
   * 
   * @param workspaceId - The UUID of the workspace
   * @returns Configured connection pool
   */
  private async createWorkspacePool(workspaceId: string): Promise<Pool> {
    const poolConfig: TenantPoolConfig = {
      workspaceId,
      connectionString: config().databaseUrl,
      max: this.defaultMaxConnections,
      idleTimeoutMillis: 30000, // 30 seconds
      connectionTimeoutMillis: 5000, // 5 seconds
      
      // Set application name for monitoring
      application_name: `dittofeed_workspace_${workspaceId.substring(0, 8)}`,
      
      // Statement timeout for safety
      statement_timeout: 30000, // 30 seconds
    };

    const pool = new Pool(poolConfig);

    // Set up event handlers for monitoring
    pool.on("connect", (client) => {
      // Set workspace context for RLS on each new connection
      client.query(
        `SET LOCAL app.current_workspace_id = '${workspaceId}'`,
        (err) => {
          if (err) {
            logger().error(
              { error: err, workspaceId },
              "Failed to set workspace context on connection"
            );
          }
        }
      );
    });

    pool.on("error", (err) => {
      logger().error(
        { error: err, workspaceId },
        "Workspace pool error"
      );
    });

    return pool;
  }

  /**
   * Execute a query using the workspace's connection pool
   * 
   * @param workspaceId - The UUID of the workspace
   * @param query - SQL query string
   * @param values - Query parameter values
   * @returns Query result
   */
  async query<T = any>(
    workspaceId: string,
    query: string,
    values?: any[]
  ): Promise<T[]> {
    const pool = await this.getPool(workspaceId);
    
    try {
      const result = await pool.query(query, values);
      return result.rows;
    } catch (error) {
      logger().error(
        {
          error,
          workspaceId,
          query: query.substring(0, 100), // Log first 100 chars of query
        },
        "Workspace pool query error"
      );
      throw error;
    }
  }

  /**
   * Get metrics for a specific workspace pool
   * 
   * @param workspaceId - The UUID of the workspace
   * @returns Pool metrics or null if pool doesn't exist
   */
  getPoolMetrics(workspaceId: string): PoolMetrics | null {
    const pool = this.pools.get(workspaceId);
    if (!pool) {
      return null;
    }

    const metrics = this.poolMetrics.get(workspaceId);
    if (!metrics) {
      return null;
    }

    return {
      ...metrics,
      totalCount: pool.totalCount,
      idleCount: pool.idleCount,
      waitingCount: pool.waitingCount,
    };
  }

  /**
   * Get metrics for all workspace pools
   * 
   * @returns Map of workspace IDs to their pool metrics
   */
  getAllPoolMetrics(): Map<string, PoolMetrics> {
    const allMetrics = new Map<string, PoolMetrics>();

    for (const [workspaceId, pool] of this.pools) {
      const metrics = this.getPoolMetrics(workspaceId);
      if (metrics) {
        allMetrics.set(workspaceId, metrics);
      }
    }

    return allMetrics;
  }

  /**
   * Close a specific workspace's connection pool
   * 
   * @param workspaceId - The UUID of the workspace
   */
  async closePool(workspaceId: string): Promise<void> {
    const pool = this.pools.get(workspaceId);
    if (!pool) {
      return;
    }

    try {
      await pool.end();
      this.pools.delete(workspaceId);
      this.poolMetrics.delete(workspaceId);
      
      logger().info(
        { workspaceId },
        "Closed workspace connection pool"
      );
    } catch (error) {
      logger().error(
        { error, workspaceId },
        "Error closing workspace pool"
      );
    }
  }

  /**
   * Close all connection pools
   */
  async closeAllPools(): Promise<void> {
    // Stop cleanup interval
    if (this.cleanupInterval) {
      clearInterval(this.cleanupInterval);
      this.cleanupInterval = undefined;
    }

    // Close all pools
    const closePromises: Promise<void>[] = [];
    for (const workspaceId of this.pools.keys()) {
      closePromises.push(this.closePool(workspaceId));
    }

    await Promise.all(closePromises);
    
    logger().info(
      { poolCount: closePromises.length },
      "Closed all workspace connection pools"
    );
  }

  /**
   * Initialize metrics for a new pool
   */
  private initializePoolMetrics(workspaceId: string): void {
    const now = new Date();
    this.poolMetrics.set(workspaceId, {
      totalCount: 0,
      idleCount: 0,
      waitingCount: 0,
      createdAt: now,
      lastUsedAt: now,
    });
  }

  /**
   * Update last used timestamp for a pool
   */
  private updatePoolMetrics(workspaceId: string): void {
    const metrics = this.poolMetrics.get(workspaceId);
    if (metrics) {
      metrics.lastUsedAt = new Date();
    }
  }

  /**
   * Start interval to cleanup idle pools
   */
  private startCleanupInterval(): void {
    this.cleanupInterval = setInterval(() => {
      this.cleanupIdlePools();
    }, this.cleanupIntervalMs);
  }

  /**
   * Clean up pools that have been idle for too long
   */
  private async cleanupIdlePools(): Promise<void> {
    const idleThresholdMs = 300000; // 5 minutes
    const now = new Date();
    const poolsToClose: string[] = [];

    for (const [workspaceId, metrics] of this.poolMetrics) {
      const idleTime = now.getTime() - metrics.lastUsedAt.getTime();
      
      // Close pools that have been idle too long
      if (idleTime > idleThresholdMs) {
        poolsToClose.push(workspaceId);
      }
    }

    // Close idle pools
    for (const workspaceId of poolsToClose) {
      await this.closePool(workspaceId);
    }

    if (poolsToClose.length > 0) {
      logger().info(
        {
          closedPools: poolsToClose.length,
          remainingPools: this.pools.size,
        },
        "Cleaned up idle workspace pools"
      );
    }
  }

  /**
   * Evict the least recently used pool when at capacity
   */
  private async evictLeastRecentlyUsedPool(): Promise<void> {
    let oldestWorkspaceId: string | null = null;
    let oldestLastUsed = new Date();

    // Find the least recently used pool
    for (const [workspaceId, metrics] of this.poolMetrics) {
      if (metrics.lastUsedAt < oldestLastUsed) {
        oldestLastUsed = metrics.lastUsedAt;
        oldestWorkspaceId = workspaceId;
      }
    }

    if (oldestWorkspaceId) {
      await this.closePool(oldestWorkspaceId);
      
      logger().info(
        {
          evictedWorkspaceId: oldestWorkspaceId,
          lastUsed: oldestLastUsed,
        },
        "Evicted least recently used workspace pool"
      );
    }
  }

  /**
   * Get connection pool statistics
   */
  getStatistics(): {
    totalPools: number;
    totalConnections: number;
    idleConnections: number;
    waitingRequests: number;
  } {
    let totalConnections = 0;
    let idleConnections = 0;
    let waitingRequests = 0;

    for (const pool of this.pools.values()) {
      totalConnections += pool.totalCount;
      idleConnections += pool.idleCount;
      waitingRequests += pool.waitingCount;
    }

    return {
      totalPools: this.pools.size,
      totalConnections,
      idleConnections,
      waitingRequests,
    };
  }
}

// Export singleton instance
let tenantPoolInstance: TenantConnectionPool | null = null;

export function getTenantConnectionPool(): TenantConnectionPool {
  if (!tenantPoolInstance) {
    tenantPoolInstance = new TenantConnectionPool();
  }
  return tenantPoolInstance;
}

export async function closeTenantConnectionPool(): Promise<void> {
  if (tenantPoolInstance) {
    await tenantPoolInstance.closeAllPools();
    tenantPoolInstance = null;
  }
}
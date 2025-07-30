# Efficient Multitenancy Enhancement PRP

name: "Dittofeed Enterprise Multitenancy Enhancement v1"
description: |
  Comprehensive PRP to transform Dittofeed's existing workspace-based multitenancy 
  into an enterprise-grade, highly efficient multi-tenant architecture addressing 
  7 identified gaps with measurable performance and security improvements.

## Goal

Transform Dittofeed's current multitenancy foundation into an enterprise-grade system with:
- 40%+ improved database performance for workspace-scoped queries
- Comprehensive resource quota enforcement per workspace  
- Advanced security with row-level security policies
- Tenant-aware caching reducing database load by 30%+
- Full tenant usage monitoring and analytics
- Optimized connection pooling for multi-tenant workloads

## Why

- **Business Value**: Enable Dittofeed to scale to enterprise customers with thousands of workspaces
- **Performance**: Current architecture will hit performance walls without tenant-optimized indexing
- **Security**: Enterprise customers require defense-in-depth tenant isolation (GAP-006)
- **Cost Control**: Resource quotas prevent tenant abuse and cost overruns (GAP-003)
- **Operational Excellence**: Tenant monitoring enables proactive capacity planning (GAP-005)

## What

Enhance the existing solid multitenancy foundation with enterprise-grade features:

### User-Visible Behavior
- Workspace admins can set resource quotas (max users, segments, journeys per workspace)
- Performance improvements: faster dashboard loading, quicker query responses
- Enhanced security: audit logs, improved tenant isolation
- Usage analytics: workspace usage dashboards for admins

### Technical Requirements  
- Row-level security on all tenant-scoped tables
- Tenant-aware database indexes for optimal query performance
- Resource quota enforcement with configurable limits
- Workspace-scoped caching with intelligent invalidation
- Comprehensive tenant metrics collection and monitoring

### Success Criteria

- [ ] Database performance improved 40%+ for workspace queries (measured via benchmarks)
- [ ] Resource quotas enforced with real-time validation
- [ ] Row-level security implemented on critical tables (Segment, Journey, MessageTemplate)
- [ ] Tenant-aware caching reduces database queries by 30%+
- [ ] Monitoring dashboard shows per-workspace usage metrics
- [ ] All existing tests pass + 95%+ coverage on new multitenancy features
- [ ] Security audit validates tenant isolation boundaries
- [ ] Load testing demonstrates 10x workspace scalability improvement

## All Needed Context

### Documentation & References (MUST READ)

```yaml
# Core Dittofeed Documentation
- url: https://docs.dittofeed.com/introduction
  why: Understanding current multitenancy model and workspace isolation

- url: https://orm.drizzle.team/docs/indexes
  why: Database indexing best practices for multi-tenant schemas

- url: https://www.postgresql.org/docs/current/ddl-rowsecurity.html  
  why: Row-level security implementation patterns

- url: https://docs.temporal.io/concepts/what-is-a-namespace
  why: Multi-tenant workflow isolation patterns (for background jobs)

# Critical Codebase Files to Study
- file: packages/backend-lib/src/db/schema.ts
  why: Current schema with 147 workspaceId references - foundation to build on

- file: packages/backend-lib/src/rbac.ts  
  why: Existing authorization patterns to extend

- file: packages/api/src/buildApp/requestContext.ts
  why: Request context patterns for workspace resolution

- file: packages/backend-lib/src/auth.ts
  why: Authentication patterns and workspace validation

- file: packages/api/src/controllers/segmentsController.ts
  why: Controller patterns with workspace scoping to replicate
```

### Current Codebase Tree (Core Structure)

```bash
dittofeed/
├── packages/
│   ├── api/                    # Fastify API server
│   │   ├── src/
│   │   │   ├── controllers/    # 23 controllers with workspace patterns
│   │   │   ├── buildApp/      # Request context, auth middleware
│   │   │   └── workspace.ts   # Workspace resolution logic
│   ├── backend-lib/           # Shared backend utilities  
│   │   ├── src/
│   │   │   ├── db/            # Database schema and connections
│   │   │   ├── auth.ts        # Authentication logic
│   │   │   ├── rbac.ts        # Role-based access control
│   │   │   └── config.ts      # Configuration management
│   ├── dashboard/             # Next.js frontend
│   ├── isomorphic-lib/        # Shared types and utilities
│   └── worker/               # Background job processing
├── PRPs/                     # Project requirement plans
├── PRDs/                     # Product requirement docs  
└── claude.md                # Global development rules
```

### Desired Codebase Tree (Files to Add)

```bash
packages/backend-lib/src/
├── multitenancy/              # NEW: Multitenancy utilities
│   ├── resourceQuotas.ts      # Resource quota enforcement
│   ├── tenantMetrics.ts       # Usage tracking and analytics
│   ├── connectionPool.ts      # Tenant-aware connection pooling
│   └── cache.ts               # Workspace-scoped caching
├── db/
│   ├── migrations/            # NEW: RLS and index migrations
│   │   ├── add_tenant_indexes.sql
│   │   └── enable_row_level_security.sql
│   └── policies.ts            # NEW: RLS policy definitions
└── security/                  # NEW: Security utilities
    ├── tenantEncryption.ts    # Per-tenant encryption keys
    └── auditLogger.ts         # Comprehensive audit logging

packages/api/src/controllers/
└── quotasController.ts        # NEW: Resource quota management API

packages/dashboard/src/components/
├── tenantAnalytics.tsx        # NEW: Usage analytics dashboard
└── quotaManagement.tsx        # NEW: Quota configuration UI

packages/isomorphic-lib/src/
└── types.ts                   # EXTEND: Add quota and metric types
```

### Known Gotchas & Library Quirks

```typescript
// CRITICAL: Drizzle ORM patterns for multitenancy
// From packages/backend-lib/src/db/schema.ts:92-117
export const workspace = pgTable("Workspace", {
  id: uuid().primaryKey().defaultRandom().notNull(),
  // All tenant tables MUST reference workspace.id with CASCADE deletion
  workspaceId: uuid().notNull(),
}, (table) => [
  foreignKey({
    columns: [table.workspaceId],
    foreignColumns: [workspace.id],
    name: "TableName_workspaceId_fkey",
  }).onUpdate("cascade").onDelete("cascade"), // CRITICAL: Always cascade
]);

// GOTCHA: PostgreSQL RLS requires setting workspace context per request
// Must set current_setting('app.current_workspace_id') for RLS policies

// PATTERN: All controllers must validate workspace access  
// From packages/api/src/buildApp/requestContext.ts:76-88
const workspaceId = requestWorkspaceIdResult.value;
if (workspaceId !== workspace.id) {
  return reply.status(403).send(); // CRITICAL: Always validate workspace match
}

// GOTCHA: Drizzle migrations are auto-generated, manual SQL needed for RLS
// Use packages/backend-lib/drizzle/ for schema changes
// Custom SQL migrations go in packages/backend-lib/src/db/migrations/

// PATTERN: Use neverthrow Result types for error handling
// From packages/backend-lib/src/auth.ts:35-70
export async function validateWriteKey({writeKey}: {writeKey: string}): Promise<string | null> {
  if (!encodedWriteKey) return null; // Early returns for validation
  return writeKeySecret.value === secretKeyValue ? writeKeySecret.workspaceId : null;
}
```

## Implementation Blueprint

### Data Models and Structure

Core data models for enterprise multitenancy features:

```typescript
// packages/isomorphic-lib/src/types.ts - EXTEND existing types

export const WorkspaceQuota = Type.Object({
  workspaceId: Type.String({format: "uuid"}),
  maxUsers: Type.Number({minimum: 0}),
  maxSegments: Type.Number({minimum: 1}),
  maxJourneys: Type.Number({minimum: 1}),
  maxTemplates: Type.Number({minimum: 1}),
  maxStorageBytes: Type.Number({minimum: 0}),
  maxMessagesPerMonth: Type.Number({minimum: 0}),
  createdAt: Type.String({format: "date-time"}),
  updatedAt: Type.String({format: "date-time"}),
});

export const TenantMetrics = Type.Object({
  workspaceId: Type.String({format: "uuid"}),
  timestamp: Type.String({format: "date-time"}),
  userCount: Type.Number(),
  segmentCount: Type.Number(),
  journeyCount: Type.Number(),
  templateCount: Type.Number(),
  storageUsedBytes: Type.Number(),
  messagesThisMonth: Type.Number(),
  databaseQueryCount: Type.Number(),
  cacheHitRate: Type.Number(),
});
```

### Task List (Implementation Order)

```yaml
Task 1: Database Performance & Security Foundation
MODIFY packages/backend-lib/src/db/schema.ts:
  - ADD tenant-aware composite indexes for major tables
  - PRESERVE existing foreign key relationships
  - PREPARE for RLS policy addition

CREATE packages/backend-lib/src/db/migrations/001_tenant_indexes.sql:
  - CREATE optimized indexes for workspace queries
  - CREATE indexes on (workspace_id, status, updated_at) patterns
  - ANALYZE query performance before/after

CREATE packages/backend-lib/src/db/migrations/002_row_level_security.sql:
  - ENABLE RLS on Segment, Journey, MessageTemplate tables
  - CREATE workspace isolation policies
  - GRANT appropriate permissions

Task 2: Resource Quota System  
CREATE packages/backend-lib/src/multitenancy/resourceQuotas.ts:
  - IMPLEMENT quota validation functions
  - MIRROR error handling pattern from packages/backend-lib/src/auth.ts
  - KEEP async/await patterns consistent with codebase

CREATE packages/api/src/controllers/quotasController.ts:
  - MIRROR pattern from packages/api/src/controllers/segmentsController.ts
  - IMPLEMENT CRUD operations for workspace quotas
  - PRESERVE TypeBox validation patterns

MODIFY packages/isomorphic-lib/src/types.ts:
  - ADD WorkspaceQuota and related schemas
  - KEEP consistent with existing type patterns

Task 3: Enhanced Connection Pooling
CREATE packages/backend-lib/src/multitenancy/connectionPool.ts:
  - IMPLEMENT tenant-aware connection pool management
  - INTEGRATE with existing packages/backend-lib/src/db.ts patterns
  - MONITOR connection usage per tenant

MODIFY packages/backend-lib/src/db.ts:
  - EXTEND existing connection logic
  - PRESERVE backward compatibility
  - ADD tenant context to connection metadata

Task 4: Workspace-Scoped Caching
CREATE packages/backend-lib/src/multitenancy/cache.ts:
  - IMPLEMENT Redis-based workspace-scoped caching
  - PATTERN: Use workspace_id as cache key prefix
  - INTEGRATE with existing computed properties caching

MODIFY relevant controllers:
  - ADD cache integration to high-traffic endpoints
  - PRESERVE existing response formats
  - IMPLEMENT cache invalidation on data changes

Task 5: Tenant Metrics & Monitoring
CREATE packages/backend-lib/src/multitenancy/tenantMetrics.ts:
  - IMPLEMENT usage tracking for all quota-relevant resources
  - INTEGRATE with existing OpenTelemetry setup
  - BATCH metrics collection for performance

CREATE packages/dashboard/src/components/tenantAnalytics.tsx:
  - MIRROR component patterns from existing dashboard components
  - IMPLEMENT charts showing workspace usage trends
  - KEEP consistent with dashboard design system

Task 6: Security Enhancements
CREATE packages/backend-lib/src/security/auditLogger.ts:
  - IMPLEMENT comprehensive audit logging
  - LOG all tenant boundary crossings
  - INTEGRATE with existing logger patterns

MODIFY packages/api/src/buildApp/requestContext.ts:
  - ADD workspace context setting for RLS
  - PRESERVE existing request flow
  - ENHANCE security validation

Task 7: Integration & Testing
CREATE test files for all new modules:
  - MIRROR testing patterns from existing codebase
  - TEST tenant isolation boundaries thoroughly  
  - BENCHMARK performance improvements

MODIFY packages/api/src/buildApp/router.ts:
  - INTEGRATE new quota controller routes
  - PRESERVE existing route patterns
  - ADD middleware for quota enforcement
```

### Per Task Pseudocode

```typescript
// Task 1: Database Indexes
// Critical tenant-aware indexing for performance
CREATE INDEX CONCURRENTLY idx_segment_workspace_perf 
ON "Segment" (workspace_id, status, definition_updated_at);

CREATE INDEX CONCURRENTLY idx_journey_workspace_perf
ON "Journey" (workspace_id, status, updated_at);

// RLS policies for defense-in-depth security
ALTER TABLE "Segment" ENABLE ROW LEVEL SECURITY;
CREATE POLICY segment_workspace_isolation ON "Segment"
  USING (workspace_id = current_setting('app.current_workspace_id', true)::uuid);

// Task 2: Resource Quotas  
// PATTERN: Follow auth.ts validation patterns
export async function validateWorkspaceQuota(
  workspaceId: string, 
  resourceType: string, 
  increment: number = 1
): Promise<Result<boolean, QuotaError>> {
  // CRITICAL: Always validate workspace access first
  const quota = await getWorkspaceQuota(workspaceId);
  if (!quota) return err(new QuotaError("No quota found"));
  
  const currentUsage = await getCurrentUsage(workspaceId, resourceType);
  const newUsage = currentUsage + increment;
  
  // PATTERN: Early return for validation failures
  if (newUsage > getQuotaLimit(quota, resourceType)) {
    return err(new QuotaError("Quota exceeded"));
  }
  
  return ok(true);
}

// Task 3: Connection Pooling
// PATTERN: Extend existing db.ts connection management
class TenantConnectionPool {
  private pools = new Map<string, Pool>();
  
  async getConnection(workspaceId: string): Promise<Pool> {
    // GOTCHA: Validate workspace ID format first
    if (!validate(workspaceId)) throw new Error("Invalid workspace ID");
    
    if (!this.pools.has(workspaceId)) {
      const pool = createPool({
        // CRITICAL: Set workspace context for RLS
        connectionString: config.databaseUrl,
        application_name: `dittofeed_workspace_${workspaceId}`,
      });
      this.pools.set(workspaceId, pool);
    }
    
    return this.pools.get(workspaceId)!;
  }
}

// Task 4: Workspace Caching
// PATTERN: Prefix all cache keys with workspace ID
export class TenantCache {
  private redis: Redis;
  
  private getCacheKey(workspaceId: string, key: string): string {
    return `workspace:${workspaceId}:${key}`;
  }
  
  async get<T>(workspaceId: string, key: string): Promise<T | null> {
    // CRITICAL: Always validate workspace access
    await validateWorkspaceAccess(workspaceId);
    
    const cacheKey = this.getCacheKey(workspaceId, key);
    const value = await this.redis.get(cacheKey);
    return value ? JSON.parse(value) : null;
  }
  
  async invalidateWorkspace(workspaceId: string): Promise<void> {
    // PATTERN: Batch operations for performance
    const pattern = `workspace:${workspaceId}:*`;
    const keys = await this.redis.keys(pattern);
    if (keys.length > 0) {
      await this.redis.del(...keys);
    }
  }
}
```

### Integration Points

```yaml
DATABASE:
  - migration: "Add tenant-aware composite indexes on major tables"
  - migration: "Enable row-level security with workspace isolation policies"
  - index: "CREATE INDEX idx_workspace_performance ON key tables"

CONFIG:
  - add to: packages/backend-lib/src/config.ts
  - pattern: "TENANT_CACHE_TTL = int(process.env.TENANT_CACHE_TTL ?? '300')"
  - pattern: "DEFAULT_WORKSPACE_QUOTAS = {...}"

ROUTES:
  - add to: packages/api/src/buildApp/router.ts
  - pattern: "app.register(quotasController, { prefix: '/api/quotas' })"
  - middleware: "Add quota validation to resource creation endpoints"

DASHBOARD:
  - add to: packages/dashboard/src/pages/settings.page.tsx
  - component: "TenantAnalytics component for usage monitoring"
  - component: "QuotaManagement component for admin configuration"

TYPES:
  - extend: packages/isomorphic-lib/src/types.ts
  - add: "WorkspaceQuota, TenantMetrics, QuotaError types"
  - pattern: "Use existing TypeBox validation patterns"
```

## Validation Loop

### Level 1: Syntax & Style

```bash
# Run these FIRST - fix any errors before proceeding
cd packages/backend-lib && yarn check  # TypeScript validation
cd packages/api && yarn check          # API type checking  
cd packages/dashboard && yarn check    # Dashboard validation

yarn lint                              # ESLint across monorepo
yarn format                           # Prettier formatting

# Expected: No errors. If errors, READ the error and fix before proceeding.
```

### Level 2: Unit Tests

```typescript
// CREATE packages/backend-lib/src/multitenancy/__tests__/resourceQuotas.test.ts
describe('ResourceQuotas', () => {
  it('should enforce segment quota limits', async () => {
    const workspaceId = 'test-workspace-id';
    await setWorkspaceQuota(workspaceId, { maxSegments: 5 });
    
    // Create 5 segments (should succeed)
    for (let i = 0; i < 5; i++) {
      const result = await validateWorkspaceQuota(workspaceId, 'segments');
      expect(result.isOk()).toBe(true);
    }
    
    // 6th segment should fail
    const result = await validateWorkspaceQuota(workspaceId, 'segments');
    expect(result.isErr()).toBe(true);
    expect(result.error.message).toContain('quota exceeded');
  });

  it('should handle workspace isolation in quotas', async () => {
    const workspace1 = 'workspace-1';
    const workspace2 = 'workspace-2';
    
    await setWorkspaceQuota(workspace1, { maxSegments: 1 });
    await setWorkspaceQuota(workspace2, { maxSegments: 10 });
    
    // Workspace 1 should hit limit
    await validateWorkspaceQuota(workspace1, 'segments');
    const result1 = await validateWorkspaceQuota(workspace1, 'segments');
    expect(result1.isErr()).toBe(true);
    
    // Workspace 2 should still have quota
    const result2 = await validateWorkspaceQuota(workspace2, 'segments');
    expect(result2.isOk()).toBe(true);
  });
});

// CREATE packages/backend-lib/src/multitenancy/__tests__/tenantCache.test.ts
describe('TenantCache', () => {
  it('should isolate cache between workspaces', async () => {
    const cache = new TenantCache();
    
    await cache.set('workspace-1', 'key', 'value1');
    await cache.set('workspace-2', 'key', 'value2');
    
    const value1 = await cache.get('workspace-1', 'key');
    const value2 = await cache.get('workspace-2', 'key');
    
    expect(value1).toBe('value1');
    expect(value2).toBe('value2');
  });
});
```

```bash
# Run and iterate until passing:
yarn test packages/backend-lib/src/multitenancy/
yarn test packages/api/src/controllers/quotasController.test.ts

# Integration tests
yarn test:integration

# If failing: Read error, understand root cause, fix code, re-run
```

### Level 3: Database & Performance Tests

```bash
# Database migration testing
cd packages/backend-lib
yarn db:generate     # Generate new migrations
yarn db:push         # Apply to test database
yarn db:reset        # Test rollback capability

# Performance benchmarking
yarn benchmark:workspace-queries  # Measure query performance improvement

# Load testing with multiple tenants
yarn test:load --tenants=100 --concurrent=10

# Security validation
yarn test:security --check-tenant-isolation
```

### Level 4: Integration Testing

```bash
# Start full stack for integration testing
yarn dev

# Test quota enforcement via API
curl -X POST http://localhost:3000/api/segments \
  -H "Content-Type: application/json" \
  -H "workspace-id: test-workspace" \
  -d '{"name": "Test Segment", "definition": {...}}'

# Expected: 201 Created for under-quota, 429 Too Many Requests for over-quota

# Test workspace isolation
curl -X GET http://localhost:3000/api/segments \
  -H "workspace-id: workspace-1"
  
curl -X GET http://localhost:3000/api/segments \
  -H "workspace-id: workspace-2"

# Expected: Different results, no cross-workspace data leakage

# Test caching performance
ab -n 1000 -c 10 http://localhost:3000/api/segments?workspace-id=test

# Expected: Improved response times after cache warmup
```

## Final Validation Checklist

- [ ] All tests pass: `yarn test` (100% pass rate required)
- [ ] No type errors: `yarn workspaces foreach run check`
- [ ] No linting errors: `yarn lint`
- [ ] Database migrations successful: `yarn db:push && yarn db:reset`
- [ ] Performance benchmarks show 40%+ improvement
- [ ] Security tests validate tenant isolation
- [ ] Load testing demonstrates 10x scalability improvement
- [ ] Resource quotas enforce limits without false positives
- [ ] Tenant analytics dashboard displays accurate usage data
- [ ] Cache hit rates achieve 30%+ database load reduction
- [ ] All existing functionality preserved (regression testing)

---

## Anti-Patterns to Avoid

- ❌ Don't bypass workspace validation in new quota enforcement
- ❌ Don't create indexes without CONCURRENTLY (causes table locks)
- ❌ Don't cache data without workspace prefixes (cross-tenant data leakage)
- ❌ Don't implement RLS without proper workspace context setting
- ❌ Don't add database columns without Drizzle schema updates
- ❌ Don't modify existing API contracts (maintain backward compatibility)
- ❌ Don't ignore connection pool limits (can exhaust database connections)
- ❌ Don't skip quota validation in any resource creation endpoint

## PRP Confidence Score: 9/10

This PRP provides comprehensive context including:
- ✅ Detailed codebase analysis with specific file references
- ✅ Concrete implementation patterns from existing code
- ✅ Step-by-step tasks with clear integration points
- ✅ Executable validation gates at multiple levels
- ✅ Performance benchmarks and success criteria
- ✅ Security considerations and tenant isolation validation
- ✅ Complete error handling and rollback procedures

**Deduction (-1)**: Some performance benchmarking tooling may need custom implementation

The implementation should succeed in a single pass with this level of context and validation.
# Claude Code Global Rules & Conventions

## Project Overview
- **Project**: Dittofeed - Open-source customer engagement platform
- **Architecture**: TypeScript monorepo with Yarn workspaces
- **Tech Stack**: Fastify, Next.js, Drizzle ORM, PostgreSQL, ClickHouse
- **Testing**: Jest with TypeScript
- **Linting**: ESLint + Prettier

## Development Rules

### File Organization
- **Packages**: All code in `packages/` directory
  - `api/` - Fastify API server
  - `dashboard/` - Next.js frontend
  - `backend-lib/` - Shared backend utilities
  - `isomorphic-lib/` - Shared types and utilities
  - `worker/` - Background job processing
  - `lite/` - Lightweight deployment

### Code Standards
- **TypeScript**: Strict mode enabled, proper typing required
- **Imports**: Use absolute imports with path mapping
- **Error Handling**: Use neverthrow Result types for error handling
- **Database**: Use Drizzle ORM with schema-first approach
- **API**: Follow Fastify patterns with TypeBox validation

### Testing Requirements
- **Unit Tests**: Jest with ts-jest configuration
- **Test Location**: Co-located with source files or in `test/` directories
- **Coverage**: Aim for >80% coverage on new code
- **Test Command**: `yarn test` or `npm test`

### Database & Migrations
- **Schema**: Defined in `packages/backend-lib/src/db/schema.ts`
- **Migrations**: Generated with Drizzle Kit in `packages/backend-lib/drizzle/`
- **Workspace Isolation**: All tables include `workspaceId` for multitenancy
- **Unique Constraints**: Critical for OAuth/Integration upsert operations

### Multitenancy Architecture
- **Current State**: Workspace-based isolation with hierarchical support
- **Auth Modes**: `anonymous`, `single-tenant`, `multi-tenant`
- **Workspace Types**: `Root`, `Child`, `Parent`
- **Request Context**: Workspace resolution from headers/body/query

### API Conventions
- **Authentication**: JWT tokens, write keys, workspace member roles
- **Workspace Context**: Required in request headers or body
- **Error Responses**: Standardized JSON error format
- **Validation**: TypeBox schemas for all endpoints

### Performance Guidelines
- **Database**: Use indexes for workspace-scoped queries
- **Caching**: Redis for session and computed property caching
- **Background Jobs**: Temporal.io for workflow orchestration
- **Monitoring**: OpenTelemetry integration

### Security Requirements
- **Workspace Isolation**: Strict tenant data separation
- **API Keys**: Scoped to specific workspaces
- **Secrets**: Encrypted storage in database
- **RBAC**: Role-based access control with workspace member roles

## Development Workflow
1. **Feature Development**: Follow TDD approach
2. **Database Changes**: Create migrations first
3. **API Changes**: Update TypeBox schemas
4. **Testing**: Unit tests before implementation
5. **Integration**: Test across workspace boundaries

### OAuth Integrations
- **Google**: User authentication and Gmail integration
- **HubSpot**: CRM integration with contacts, lists, and email tracking
- **Schema Requirements**: Unique indexes on `OauthToken(workspaceId, name)` and `Integration(workspaceId, name)`
- **Environment Variables**: Both server-side and client-side configs needed for dashboard

#### Critical Database Schema Requirements
```sql
-- Required for OAuth token upsert operations
CREATE UNIQUE INDEX "OauthToken_workspaceId_name_key" ON "OauthToken" ("workspaceId", "name");

-- Required for integration upsert operations  
CREATE UNIQUE INDEX "Integration_workspaceId_name_key" ON "Integration" ("workspaceId", "name");
```

## Deployment & Bootstrap

### Coolify Production Deployment

#### Standard Multi-Tenant
- **Bootstrap**: `deployment/bootstrap-standard-multitenant.sh`
- **Docker Compose**: `docker-compose.coolify.yaml`
- **Images**: Registry images (`multitenancy-redis-v1`)
- **Post-deploy Command**: 
  ```bash
  curl -fsSL https://raw.githubusercontent.com/aymensakka/dittofeed/multi-tenant-main/deployment/bootstrap-standard-multitenant.sh | bash
  ```

#### Embedded Dashboard
- **Bootstrap**: `deployment/bootstrap-embedded-dashboard.sh`
- **Docker Compose**: `docker-compose.coolify-embedded.yaml`
- **Images**: Embedded images (`embedded-final`)
- **Post-deploy Command**:
  ```bash
  curl -fsSL https://raw.githubusercontent.com/aymensakka/dittofeed/multi-tenant-main/deployment/bootstrap-embedded-dashboard.sh | bash
  ```

### Manual Scripts
- **`deployment/init-database.sh`**: Complete database initialization with all schema
- **`deploy-coolify-embedded.sh`**: Local embedded deployment
- **`local-multitenant-setup.sh`**: Complete local development environment setup

### Documentation
- **`deployment/BOOTSTRAP.md`**: Comprehensive bootstrap documentation
- **`deployment/COOLIFY_DEPLOYMENT_GUIDE.md`**: Coolify-specific deployment guide

### Fork Management
- **See `FORK_MANAGEMENT_GUIDE.md`**: Guidelines for managing the Dittofeed fork
  - Keeping fork synchronized with upstream
  - Managing feature branches
  - Deployment strategies

### Database Migration Commands
```bash
# Using Drizzle Kit (recommended)
npx drizzle-kit push:pg --config=drizzle.config.ts

# Manual schema application
./deployment/init-database.sh
```

### Embedded Sessions Feature
- **Tables**: EmbeddedSession, EmbeddedSessionAudit, EmbeddedSessionRateLimit
- **Security**: Refresh token families, access token rotation, rate limiting
- **Schema**: `packages/backend-lib/drizzle/0020_embedded_sessions.sql`

## Never Do
- Skip workspace validation in API endpoints
- Mix tenant data in queries
- Hardcode workspace IDs
- Bypass authentication in multi-tenant mode
- Create database queries without workspace scoping
- Use hardcoded OAuth client IDs in frontend components
- Skip importing required dependencies (e.g., axios) in OAuth handlers
- Deploy without running database migrations
- Use curl-based health checks in Docker (use Node.js instead)
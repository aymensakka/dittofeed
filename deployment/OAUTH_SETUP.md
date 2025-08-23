# Dittofeed Multi-Tenant OAuth Setup Guide

## Overview

This guide documents the OAuth authentication setup for Dittofeed in multi-tenant mode, including security considerations, database requirements, and configuration steps.

## Table of Contents
- [Architecture](#architecture)
- [Security Features](#security-features)
- [Prerequisites](#prerequisites)
- [Configuration](#configuration)
- [Database Setup](#database-setup)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)

## Architecture

### Workspace Hierarchy
```
Organization A (Parent Workspace)
├── Location 1 (Child Workspace)
├── Location 2 (Child Workspace)
└── Department X (Child Workspace)

Organization B (Parent Workspace)
├── Region 1 (Child Workspace)
└── Region 2 (Child Workspace)

Organization C (Root Workspace - standalone)
```

### Authentication Flow
1. User initiates OAuth via `/api/public/auth/oauth2/initiate/google`
2. Redirected to Google OAuth consent
3. Callback to `/api/public/auth/oauth2/callback/google`
4. System checks if user has workspace access
5. If yes → Create session and redirect to dashboard
6. If no → Redirect to "no organization" error page

## Security Features

### 🔒 What's Implemented
1. **No Auto-Creation**: New users cannot create workspaces automatically
2. **No Domain Auto-Join**: Domain-based workspace assignment is disabled
3. **Explicit Access Control**: Users must be explicitly added by workspace admins
4. **Role-Based Access**: Admin, Editor, Viewer roles with different permissions
5. **Workspace Isolation**: Complete data isolation between workspaces
6. **Parent-Child Access**: Parent workspace API keys can access child workspaces

### ⚠️ Security Considerations
- OAuth credentials must be kept secure
- Use HTTPS in production
- Regularly rotate JWT secrets
- Monitor failed authentication attempts
- Audit workspace member additions

## Prerequisites

### Required Environment Variables
```bash
# Authentication Mode
AUTH_MODE=multi-tenant
AUTH_PROVIDER=google

# Google OAuth Credentials
GOOGLE_CLIENT_ID=your-google-client-id
GOOGLE_CLIENT_SECRET=your-google-client-secret

# Security Keys
JWT_SECRET=your-jwt-secret-min-32-chars
SECRET_KEY=your-session-secret-key

# Database
DATABASE_URL=postgresql://user:password@host:port/database

# Other Services
REDIS_HOST=localhost
REDIS_PORT=6379
CLICKHOUSE_HOST=localhost
CLICKHOUSE_PORT=8123
TEMPORAL_ADDRESS=localhost:7233
```

### Google OAuth Setup
1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create or select a project
3. Enable Google+ API
4. Create OAuth 2.0 credentials
5. Add authorized redirect URIs:
   - Local: `http://localhost:3001/api/public/auth/oauth2/callback/google`
   - Production: `https://your-domain.com/api/public/auth/oauth2/callback/google`

### HubSpot Integration Setup
1. Go to [HubSpot Developer Portal](https://developers.hubspot.com/)
2. Create or select an app
3. Configure OAuth settings:
   - Scopes required: `timeline`, `sales-email-read`, `crm.objects.contacts.read`, `crm.objects.contacts.write`, `crm.objects.companies.write`, `crm.objects.companies.read`, `crm.objects.owners.read`, `crm.lists.write`, `crm.lists.read`
4. Add redirect URIs:
   - Local: `http://localhost:3000/dashboard/oauth2/callback/hubspot`
   - Production: `https://your-domain.com/dashboard/oauth2/callback/hubspot`
5. Note your Client ID and Client Secret

#### HubSpot Environment Variables
```bash
# HubSpot OAuth App Credentials
HUBSPOT_CLIENT_ID=your-hubspot-client-id
HUBSPOT_CLIENT_SECRET=your-hubspot-client-secret
NEXT_PUBLIC_HUBSPOT_CLIENT_ID=your-hubspot-client-id
```

**Important**: The `NEXT_PUBLIC_HUBSPOT_CLIENT_ID` is required for the dashboard settings page to show the correct HubSpot authorization URL.

## Configuration

### 1. Backend Configuration
```typescript
// packages/backend-lib/src/config.ts
{
  authMode: "multi-tenant",
  authProvider: "google",
  // Domain auto-join is disabled by default for security
}
```

### 2. Dashboard Configuration
```bash
# Dashboard environment variables
NEXT_PUBLIC_AUTH_MODE=multi-tenant
NEXT_PUBLIC_API_BASE=http://localhost:3001
NEXT_PUBLIC_ENABLE_MULTITENANCY=true
NEXTAUTH_URL=http://localhost:3000/dashboard
NEXTAUTH_SECRET=your-nextauth-secret
```

## Database Setup

### Initial Setup (New Installation)
```bash
# Run the OAuth migration to create required tables
psql -U dittofeed -d dittofeed -f deployment/oauth-migration.sql
```

### Migration (Existing Installation)
```bash
# Backup your database first!
pg_dump -U dittofeed dittofeed > backup.sql

# Run migration
psql -U dittofeed -d dittofeed -f deployment/oauth-migration.sql
```

### Required Tables
- `Workspace` - Organizations/tenants
- `WorkspaceMember` - User accounts
- `WorkspaceMemberRole` - User roles per workspace
- `WorkspaceMembeAccount` - OAuth provider accounts

### Creating Initial Admin User
```sql
-- 1. Create workspace
INSERT INTO "Workspace" (name, type, status, domain) 
VALUES ('My Organization', 'Root', 'Active', 'mycompany.com');

-- 2. Create workspace member
INSERT INTO "WorkspaceMember" (email, "emailVerified", "workspaceId") 
VALUES ('admin@mycompany.com', true, '<workspace-id>');

-- 3. Add admin role
INSERT INTO "WorkspaceMemberRole" ("workspaceId", "workspaceMemberId", role) 
VALUES ('<workspace-id>', '<member-id>', 'Admin');

-- 4. Add OAuth account (after first login)
INSERT INTO "WorkspaceMembeAccount" ("workspaceMemberId", provider, "providerAccountId") 
VALUES ('<member-id>', 'google', '<google-user-id>');
```

## Testing

### Local Testing
```bash
# Start services
docker-compose up -d

# Start API with OAuth
GOOGLE_CLIENT_ID="..." GOOGLE_CLIENT_SECRET="..." \
AUTH_MODE=multi-tenant AUTH_PROVIDER=google \
yarn workspace api dev

# Start Dashboard
AUTH_MODE=multi-tenant NEXT_PUBLIC_AUTH_MODE=multi-tenant \
yarn workspace dashboard dev
```

### Test Scenarios
1. **User WITH Access**
   - Add user to WorkspaceMember and WorkspaceMemberRole
   - User can log in and access dashboard

2. **User WITHOUT Access**
   - User not in database
   - Shows "no organization" error page

3. **Remove Access**
   ```sql
   DELETE FROM "WorkspaceMemberRole" 
   WHERE "workspaceMemberId" = '<member-id>';
   ```

## Troubleshooting

### Common Issues

#### 1. "null value in column providerAccountId"
**Cause**: Missing OAuth provider ID
**Solution**: Ensure WorkspaceMembeAccount has proper provider ID
```sql
INSERT INTO "WorkspaceMembeAccount" 
("workspaceMemberId", provider, "providerAccountId") 
VALUES ('<member-id>', 'google', '<google-id>');
```

#### 2. "Authentication failed" after OAuth
**Cause**: User not in WorkspaceMember table
**Solution**: Add user with proper workspace access

#### 3. Redirect loops
**Cause**: Session cookies not persisting
**Solution**: Check cookie domain settings and CORS configuration

#### 4. "Cannot read properties of undefined"
**Cause**: Request context not properly initialized
**Solution**: Ensure all required fields are present in session

#### 5. "there is no unique or exclusion constraint matching the ON CONFLICT specification"
**Cause**: Missing unique indexes on OauthToken or Integration tables
**Solution**: Create the missing unique indexes:
```sql
CREATE UNIQUE INDEX IF NOT EXISTS "OauthToken_workspaceId_name_key" 
ON "OauthToken" USING btree ("workspaceId", "name");

CREATE UNIQUE INDEX IF NOT EXISTS "Integration_workspaceId_name_key" 
ON "Integration" USING btree ("workspaceId", "name");
```

#### 6. HubSpot "missing hubspotClientSecret" error
**Cause**: HubSpot OAuth credentials not configured
**Solution**: Add HubSpot environment variables to both API and Dashboard:
```bash
HUBSPOT_CLIENT_ID=your-hubspot-client-id
HUBSPOT_CLIENT_SECRET=your-hubspot-client-secret
NEXT_PUBLIC_HUBSPOT_CLIENT_ID=your-hubspot-client-id
```

#### 7. HubSpot "Authorization failed because this account doesn't have access to the scopes"
**Cause**: Using wrong HubSpot Client ID (hardcoded instead of environment variable)
**Solution**: Ensure settings page uses the correct environment variable for HubSpot Client ID

#### 8. Missing axios import causing "ReferenceError: axios is not defined"
**Cause**: Missing import statement in OAuth handler files
**Solution**: Add `import axios from "axios";` to the top of OAuth-related files

### Debug Commands
```bash
# Check workspace members
psql -U dittofeed -d dittofeed -c "
  SELECT wm.email, wmr.role, w.name as workspace 
  FROM \"WorkspaceMember\" wm 
  JOIN \"WorkspaceMemberRole\" wmr ON wm.id = wmr.\"workspaceMemberId\"
  JOIN \"Workspace\" w ON wmr.\"workspaceId\" = w.id;
"

# Check OAuth accounts
psql -U dittofeed -d dittofeed -c "
  SELECT wm.email, wma.provider, wma.\"providerAccountId\" 
  FROM \"WorkspaceMember\" wm 
  LEFT JOIN \"WorkspaceMembeAccount\" wma ON wm.id = wma.\"workspaceMemberId\";
"

# View logs
docker logs <api-container> --tail 100
docker logs <dashboard-container> --tail 100
```

## API Endpoints

### OAuth Endpoints
- `GET /api/public/auth/oauth2/initiate/:provider` - Start OAuth flow
- `GET /api/public/auth/oauth2/callback/:provider` - OAuth callback
- `POST /api/public/auth/exchange` - Exchange token for session
- `GET /api/public/auth/session` - Check session status
- `POST /api/public/auth/signout` - Sign out

### Permission Management
- `GET /api/permissions` - List workspace members and roles
- `POST /api/permissions` - Add new member
- `PUT /api/permissions` - Update member role
- `DELETE /api/permissions` - Remove member

## Best Practices

1. **Workspace Management**
   - Create parent workspaces for organizations
   - Use child workspaces for departments/locations
   - Issue API keys at appropriate levels

2. **User Onboarding**
   - Manually add users via admin interface
   - Assign appropriate roles (start with Viewer)
   - Document access approval process

3. **Security**
   - Regular security audits
   - Monitor unusual login patterns
   - Implement rate limiting
   - Use strong JWT secrets

4. **Monitoring**
   - Track failed authentication attempts
   - Monitor workspace creation
   - Audit role changes
   - Log OAuth events

## Migration Checklist

- [ ] Backup existing database
- [ ] Run OAuth migration script
- [ ] Configure environment variables
- [ ] Set up Google OAuth credentials
- [ ] Create initial admin user
- [ ] Test authentication flow
- [ ] Document workspace hierarchy
- [ ] Train administrators on user management
- [ ] Set up monitoring and alerts
- [ ] Plan regular security reviews

## Support

For issues or questions:
1. Check logs: `docker logs <container>`
2. Verify database schema matches requirements
3. Ensure all environment variables are set
4. Test with minimal configuration first
5. Report issues with full error messages and logs
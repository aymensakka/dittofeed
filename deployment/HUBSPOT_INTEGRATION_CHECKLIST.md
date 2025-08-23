# HubSpot OAuth Integration Deployment Checklist

This checklist covers the essential steps and fixes required for successful HubSpot OAuth integration deployment.

## Prerequisites

- [ ] **HubSpot Developer Account**
  - Create app at https://developers.hubspot.com/
  - Configure required OAuth scopes
  - Note Client ID and Client Secret

- [ ] **Database Setup**
  - PostgreSQL database running
  - All migrations applied
  - Unique indexes created (see Database Fixes below)

## Environment Configuration

### API Server Environment Variables
```bash
# HubSpot OAuth credentials  
HUBSPOT_CLIENT_ID=your-hubspot-client-id
HUBSPOT_CLIENT_SECRET=your-hubspot-client-secret

# Multi-tenant authentication
AUTH_MODE=multi-tenant
AUTH_PROVIDER=google
JWT_SECRET=your-jwt-secret
SECRET_KEY=your-session-secret

# Database
DATABASE_URL=postgresql://user:password@host:port/database
```

### Dashboard Environment Variables
```bash
# Client-side HubSpot configuration (REQUIRED)
NEXT_PUBLIC_HUBSPOT_CLIENT_ID=your-hubspot-client-id

# Dashboard settings
NEXT_PUBLIC_AUTH_MODE=multi-tenant
NEXT_PUBLIC_API_BASE=http://localhost:3001
NEXT_PUBLIC_ENABLE_MULTITENANCY=true
NEXTAUTH_URL=http://localhost:3000/dashboard
NEXTAUTH_SECRET=your-nextauth-secret
```

## Database Fixes

### Required Unique Indexes
Run this SQL to ensure unique constraints exist:

```sql
-- Fix 1: OauthToken unique index (CRITICAL for HubSpot)
CREATE UNIQUE INDEX IF NOT EXISTS "OauthToken_workspaceId_name_key" 
ON "OauthToken" USING btree ("workspaceId" uuid_ops, "name" text_ops);

-- Fix 2: Integration unique index (CRITICAL for HubSpot)  
CREATE UNIQUE INDEX IF NOT EXISTS "Integration_workspaceId_name_key" 
ON "Integration" USING btree ("workspaceId" uuid_ops, "name" text_ops);

-- Update table statistics
ANALYZE "OauthToken";
ANALYZE "Integration";
```

### Automated Fix Script
```bash
# Run the schema consistency fix script
psql -U dittofeed -d dittofeed -f deployment/fix-database-schema-consistency.sql
```

## Code Fixes

### Fix 1: OAuth Handler Import
Ensure `packages/dashboard/src/lib/oauth.ts` has axios import:
```typescript
import axios from "axios";
```

### Fix 2: Settings Page Client ID
Ensure `packages/dashboard/src/pages/settings.page.tsx` uses environment variable:
```typescript
href={`https://app.hubspot.com/oauth/authorize?client_id=${process.env.NEXT_PUBLIC_HUBSPOT_CLIENT_ID}&...`}
```

### Fix 3: API Request Handler
Ensure `packages/dashboard/src/lib/apiRequestHandlerFactory.ts` uses axiosInstance:
```typescript
import axiosInstance from "./axiosInstance";
// Use: axiosInstance(requestConfig)
// Not: axios(requestConfig)
```

## HubSpot App Configuration

### OAuth Settings
- [ ] **Redirect URIs**
  - Development: `http://localhost:3000/dashboard/oauth2/callback/hubspot`
  - Production: `https://yourdomain.com/dashboard/oauth2/callback/hubspot`

- [ ] **Required Scopes**
  - `timeline` - Email event tracking
  - `sales-email-read` - Email content access
  - `crm.objects.contacts.read` - Contact information
  - `crm.objects.contacts.write` - Contact updates
  - `crm.objects.companies.read` - Company information
  - `crm.objects.companies.write` - Company updates
  - `crm.objects.owners.read` - Owner information
  - `crm.lists.read` - Contact list access
  - `crm.lists.write` - Contact list management

## Testing Checklist

### Pre-Deployment Tests
- [ ] **Database Schema**
  ```sql
  -- Verify unique indexes exist
  SELECT indexname FROM pg_indexes 
  WHERE tablename IN ('OauthToken', 'Integration') 
  AND indexname LIKE '%workspaceId_name_key';
  ```

- [ ] **Environment Variables**
  ```bash
  # API server
  echo $HUBSPOT_CLIENT_ID
  echo $HUBSPOT_CLIENT_SECRET
  
  # Dashboard  
  echo $NEXT_PUBLIC_HUBSPOT_CLIENT_ID
  ```

- [ ] **Code Imports**
  ```bash
  # Check axios import exists
  grep "import axios" packages/dashboard/src/lib/oauth.ts
  
  # Check environment variable usage
  grep "NEXT_PUBLIC_HUBSPOT_CLIENT_ID" packages/dashboard/src/pages/settings.page.tsx
  ```

### Integration Tests
- [ ] **OAuth Flow**
  - Settings page shows correct HubSpot connect URL
  - HubSpot authorization redirects properly
  - OAuth callback processes without errors
  - Integration appears as "Connected" in settings

- [ ] **Database Operations**
  - OAuth token stored successfully
  - Integration record created/updated
  - No constraint violation errors
  - Workspace isolation maintained

### Error Scenarios
- [ ] **Missing Credentials**
  - API returns "missing hubspotClientSecret" error properly
  
- [ ] **Wrong Client ID**
  - Settings page uses environment variable, not hardcoded ID
  
- [ ] **Database Constraints**
  - No "unique or exclusion constraint" errors on repeat connections

## Deployment Steps

1. **Pre-deployment**
   - [ ] Apply all database migrations
   - [ ] Run schema consistency fix script
   - [ ] Verify environment variables in deployment environment

2. **Deployment**
   - [ ] Deploy API server with HubSpot environment variables
   - [ ] Deploy dashboard with client-side HubSpot configuration
   - [ ] Restart services to load new environment variables

3. **Post-deployment**
   - [ ] Test HubSpot OAuth flow end-to-end
   - [ ] Verify database schema consistency
   - [ ] Monitor error logs for OAuth-related issues

## Troubleshooting

### Common Issues and Solutions

1. **"there is no unique or exclusion constraint matching the ON CONFLICT specification"**
   - **Cause**: Missing unique indexes
   - **Solution**: Run `deployment/fix-database-schema-consistency.sql`

2. **"missing hubspotClientSecret"**
   - **Cause**: Environment variables not loaded
   - **Solution**: Restart API server after setting environment variables

3. **"Authorization failed because this account doesn't have access to the scopes"**
   - **Cause**: Wrong Client ID or insufficient scopes
   - **Solution**: Verify `NEXT_PUBLIC_HUBSPOT_CLIENT_ID` and HubSpot app scopes

4. **"ReferenceError: axios is not defined"**
   - **Cause**: Missing import in oauth.ts
   - **Solution**: Add `import axios from "axios";`

### Debug Commands
```bash
# Check database indexes
psql -U dittofeed -d dittofeed -c "
  SELECT schemaname, tablename, indexname 
  FROM pg_indexes 
  WHERE tablename IN ('OauthToken', 'Integration')
  ORDER BY tablename, indexname;"

# Check OAuth tokens
psql -U dittofeed -d dittofeed -c "
  SELECT workspaceId, name, 
         CASE WHEN accessToken IS NOT NULL THEN 'Present' ELSE 'Missing' END as access_token
  FROM \"OauthToken\" 
  WHERE name = 'hubspot';"

# Check integrations  
psql -U dittofeed -d dittofeed -c "
  SELECT workspaceId, name, enabled 
  FROM \"Integration\" 
  WHERE name = 'hubspot';"
```

## Rollback Plan

If deployment fails:

1. **Database**: Keep existing schema (no destructive changes)
2. **Environment**: Remove HubSpot environment variables
3. **Code**: Revert to previous deployment
4. **Monitoring**: Check error logs for specific failure points

## Success Criteria

- [ ] Users can connect HubSpot from Settings page
- [ ] OAuth flow completes without errors
- [ ] Integration shows as "Connected" in dashboard
- [ ] HubSpot contacts sync properly (if applicable)
- [ ] No database constraint errors in logs
- [ ] All workspace isolation maintained

## Documentation Updates

- [ ] Update deployment documentation with HubSpot requirements
- [ ] Add troubleshooting guide for common OAuth issues
- [ ] Document environment variable requirements
- [ ] Update schema migration documentation
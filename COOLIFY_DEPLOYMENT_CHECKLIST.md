# Coolify Deployment Checklist for Embedded Dashboard Update

## Prerequisites
- SSH access to Ubuntu server
- Coolify admin access
- Database connection details

## Step 1: Update Environment Variables in Coolify

Add these to your Coolify environment configuration:

```bash
# JWT Configuration (REQUIRED - Generate secure values!)
JWT_SECRET=<generate-with: openssl rand -base64 32>
SECRET_KEY=<generate-with: openssl rand -hex 32>

# Multi-tenant settings (ensure these are set)
AUTH_MODE=multi-tenant
AUTH_PROVIDER=google

# API Configuration
NEXT_PUBLIC_API_BASE=https://api.your-domain.com

# Google OAuth (if using)
GOOGLE_CLIENT_ID=your-google-client-id
GOOGLE_CLIENT_SECRET=your-google-client-secret

# HubSpot OAuth (if using)
HUBSPOT_CLIENT_ID=your-hubspot-client-id
HUBSPOT_CLIENT_SECRET=your-hubspot-client-secret
```

## Step 2: Run Database Migrations

The embedded sessions tables have been added to the bootstrap script (`deployment/init-database.sh`).

### Option A: Use Bootstrap Script (Recommended)
```bash
# 1. Connect to your server
ssh your-server

# 2. Run the init-database script
cd /path/to/dittofeed-multitenant/deployment
./init-database.sh
```

### Option B: Run Migration Manually
```bash
# If tables don't exist, run the migration:
docker exec -it <postgres-container-id> psql -U dittofeed -d dittofeed << 'EOF'
-- Run the embedded sessions migration
\i /path/to/packages/backend-lib/drizzle/0020_embedded_sessions.sql
EOF
```

### Option C: Use Drizzle Push
```bash
# Inside the API container
docker exec -it <api-container-id> sh -c "npx drizzle-kit push"
```

The migration creates these tables:
- `EmbeddedSession` - Stores active sessions with refresh tokens
- `EmbeddedSessionAudit` - Audit trail for security monitoring
- `EmbeddedSessionRateLimit` - Rate limiting per IP/workspace

## Step 3: Rebuild Docker Images on Ubuntu Server

```bash
# 1. SSH into your Ubuntu server
ssh your-ubuntu-server

# 2. Pull latest changes
cd /path/to/dittofeed-multitenant
git pull origin feature/embedded-dashboard

# 3. Build images locally
./deployment/coolify-build-from-source.sh

# OR use the standard build script:
docker-compose build --no-cache
```

## Step 4: Update Coolify Deployment

### Option A: Via Coolify UI
1. Go to your Coolify dashboard
2. Navigate to your Dittofeed application
3. Click "Redeploy" to use the new images

### Option B: Via Docker Compose
```bash
# Update docker-compose.yml with new image tags
docker-compose down
docker-compose up -d
```

## Step 5: Verify Deployment

### 1. Check API Health
```bash
curl https://api.your-domain.com/health
```

### 2. Test Embedded Session Creation
```bash
# Get your write key from database
psql $DATABASE_URL -c "SELECT value FROM \"Secret\" WHERE \"workspaceId\" = 'your-workspace-id';"

# Create a session
curl -X POST https://api.your-domain.com/api-l/embedded-sessions/create \
  -H "Authorization: Bearer YOUR_WRITE_KEY" \
  -H "Content-Type: application/json" \
  -d '{"workspaceId": "your-workspace-id"}'
```

### 3. Verify Token Response
Should return:
```json
{
  "accessToken": "eyJ...",
  "refreshToken": "...",
  "expiresIn": 900,
  "tokenType": "Bearer"
}
```

## Step 6: Test Embedded Dashboard

1. Create a test HTML file:
```html
<!DOCTYPE html>
<html>
<head>
    <title>Embedded Dashboard Test</title>
</head>
<body>
    <iframe 
        src="https://dashboard.your-domain.com/dashboard/dashboard-l/embedded/journeys?token=YOUR_ACCESS_TOKEN&workspaceId=YOUR_WORKSPACE_ID"
        width="100%"
        height="600"
        frameborder="0">
    </iframe>
</body>
</html>
```

2. Open in browser and verify the dashboard loads

## Step 7: Monitor Logs

```bash
# Check API logs
docker logs -f <api-container-id>

# Check dashboard logs  
docker logs -f <dashboard-container-id>

# Check for any errors related to:
# - JWT verification
# - Token refresh
# - Database connections
```

## Troubleshooting

### Issue: "JWT_SECRET is not configured"
**Solution**: Ensure JWT_SECRET env var is set in Coolify and container restarted

### Issue: Embedded pages return 404
**Solution**: Verify dashboard container has latest code with .page.tsx files

### Issue: Token verification fails
**Solution**: Check that API and Dashboard use same JWT_SECRET

### Issue: Database migration fails
**Solution**: Run migration manually:
```sql
-- Connect to database
psql $DATABASE_URL

-- Run migration
\i packages/backend-lib/drizzle/0020_embedded_sessions.sql
```

## Security Checklist

- [ ] Generated strong JWT_SECRET (min 32 chars)
- [ ] Generated strong SECRET_KEY (min 32 chars)  
- [ ] HTTPS enabled for both API and Dashboard
- [ ] CORS properly configured
- [ ] Rate limiting active
- [ ] Session audit logging working

## Post-Deployment

1. **Monitor Session Creation**: Check `EmbeddedSession` table
2. **Review Audit Logs**: Check `EmbeddedSessionAudit` table
3. **Test Token Refresh**: Verify refresh tokens work
4. **Check Rate Limits**: Ensure rate limiting is active

## Rollback Plan

If issues occur:
```bash
# 1. Revert to previous images
docker-compose down
docker tag api:previous api:latest
docker tag dashboard:previous dashboard:latest
docker-compose up -d

# 2. Revert database if needed
psql $DATABASE_URL -c "DROP TABLE IF EXISTS \"EmbeddedSession\" CASCADE;"
psql $DATABASE_URL -c "DROP TABLE IF EXISTS \"EmbeddedSessionAudit\" CASCADE;"
psql $DATABASE_URL -c "DROP TABLE IF EXISTS \"EmbeddedSessionRateLimit\" CASCADE;"
```

## Support

- Check logs: `docker logs <container-id>`
- Database queries: `psql $DATABASE_URL`
- API health: `curl https://api.your-domain.com/health`
- Documentation: See EMBEDDED_DASHBOARD_GUIDE.md
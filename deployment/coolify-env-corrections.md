# Coolify Environment Variable Corrections

## CRITICAL FIX REQUIRED:

### 1. DASHBOARD_URL (Currently has DATABASE_URL value!)
- **Wrong**: `postgresql://dittofeed:AXRH+ft7pHxNF/aM2m6P0g==@postgres:5432/dittofeed`
- **Correct**: `https://dashboard.com.caramelme.com`

### 2. Missing Required Variables:
- **BOOTSTRAP_WORKSPACE_ADMIN_EMAIL**: Set to `admin@example.com` or your email
- **BOOTSTRAP_WORKSPACE_NAME**: Set to `Default`

### 3. Optional but Recommended - Simplify Passwords:
The current passwords contain special characters (+, =, /) that can cause parsing issues.

Generate new passwords without special characters:
```bash
# Generate new passwords
POSTGRES_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-20)
REDIS_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)

# Example output:
# POSTGRES_PASSWORD: LOpnL3wYIbWUBax4qXeR
# REDIS_PASSWORD: t4gJLOpnL3wYIbWU
```

Then update:
- **POSTGRES_PASSWORD**: Use the new password
- **REDIS_PASSWORD**: Use the new password
- **DATABASE_URL**: `postgresql://dittofeed:[NEW_POSTGRES_PASSWORD]@postgres:5432/dittofeed`

## After Making Changes:

1. Save the environment variables in Coolify
2. Redeploy the application
3. The services should start successfully

## Verify with:
```bash
docker ps | grep -E "api|dashboard|worker|postgres"
curl -I https://dashboard.com.caramelme.com
curl -I https://api.com.caramelme.com/health
```
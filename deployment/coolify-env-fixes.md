# Coolify Environment Variable Fixes

## Issues to Fix:

### 1. **NEXTAUTH_URL** - WRONG
```bash
# Current (WRONG):
NEXTAUTH_URL=https://api.com.caramelme.com

# Should be:
NEXTAUTH_URL=https://dashboard.com.caramelme.com
```
NextAuth URL should point to the dashboard, not the API.

### 2. **DATABASE_URL** - MISSING
```bash
# Add this:
DATABASE_URL=postgresql://dittofeed:AXRH+ft7pHxNF/aM2m6P0g==@postgres:5432/dittofeed
```

### 3. **NODE_ENV** - MISSING
```bash
# Add this:
NODE_ENV=production
```

### 4. **SECRET_KEY** - MISSING
```bash
# Add this (same as JWT_SECRET or generate new):
SECRET_KEY=G1y/p4XikQN9CKxhsoUpTca0AHHiwdzy88/lTKxSBOA=
```

### 5. **Internal Service URLs** (Optional but recommended)
For better internal communication, consider adding:
```bash
# Internal API URL for service-to-service communication
INTERNAL_API_URL=http://api:3001
```

## Complete Fixed Environment Variables:

```bash
API_BASE_URL=https://api.com.caramelme.com
NEXTAUTH_URL=https://dashboard.com.caramelme.com  # FIXED
DATABASE_URL=postgresql://dittofeed:AXRH+ft7pHxNF/aM2m6P0g==@postgres:5432/dittofeed  # ADDED
NODE_ENV=production  # ADDED
SECRET_KEY=G1y/p4XikQN9CKxhsoUpTca0AHHiwdzy88/lTKxSBOA=  # ADDED

# Keep the rest as is...
```

## Notes:
- The HTTPS URLs are fine for external access
- Coolify will handle SSL termination
- Internal container communication happens over HTTP
- Make sure your domains point to the Coolify server IP
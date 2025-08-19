# OAuth Multi-Tenant Deployment Guide

## What's New
Multi-tenant OAuth authentication has been implemented with:
- Google OAuth2 flow
- Automatic workspace assignment
- Session management
- WorkspaceMember creation

## New API Routes
- `/api/public/auth/oauth2/initiate/google` - Start OAuth flow
- `/api/public/auth/oauth2/callback/google` - OAuth callback
- `/api/public/auth/session` - Check session status
- `/api/public/auth/signout` - Sign out

## Deployment Steps

### 1. Build the Updated API
```bash
cd ~/dittofeed
git pull
./deployment/build-api.sh
```

This rebuilds the API with the same tag `multitenancy-redis-v1` that Coolify expects.

### 2. Verify Environment Variables in Coolify
Ensure these are set in your Coolify environment:
- `AUTH_MODE=multi-tenant`
- `AUTH_PROVIDER=google`
- `GOOGLE_CLIENT_ID` (from your .env.coolify)
- `GOOGLE_CLIENT_SECRET` (from your .env.coolify)

### 3. Redeploy in Coolify
Coolify will automatically pull the updated image and deploy it.

### 4. Test Authentication
1. Navigate to: `https://communication-api.caramelme.com/api/public/auth/oauth2/initiate/google`
2. Sign in with Google
3. You'll be redirected to the dashboard with a valid session

## How It Works
1. User clicks login → redirected to Google
2. Google authenticates → redirects back with code
3. API exchanges code for user info
4. API creates/finds WorkspaceMember
5. API assigns workspace and creates session
6. User redirected to dashboard

## Troubleshooting

### OAuth Route Returns 404
- Check `AUTH_MODE=multi-tenant` in API environment
- Verify API container has restarted with new code

### Google OAuth Error
- Verify `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` are set
- Check redirect URI matches your domain

### No Workspace Access
- Ensure at least one workspace exists in database
- Check WorkspaceMember table for user email

## Database Tables Used
- `Workspace` - Workspace definitions
- `WorkspaceMember` - User accounts
- `WorkspaceMemberRole` - User-workspace associations
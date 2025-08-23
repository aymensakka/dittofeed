# Google OAuth Setup for Dittofeed Multi-tenant

## Prerequisites
You need a Google Cloud Platform account and a project.

## Setup Steps

### 1. Create Google OAuth Credentials

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select or create a project
3. Navigate to **APIs & Services** > **Credentials**
4. Click **Create Credentials** > **OAuth client ID**
5. Select **Web application** as the application type
6. Configure the OAuth client:
   - **Name**: Dittofeed Local Development (or any name you prefer)
   - **Authorized JavaScript origins**:
     - `http://localhost:3000`
     - `http://localhost:3001`
   - **Authorized redirect URIs**:
     - `http://localhost:3001/api/public/auth/oauth2/callback/google`
     - `http://localhost:3000/api/auth/oauth2/callback/google`

### 2. Update Environment Variables

After creating the OAuth client, you'll receive a Client ID and Client Secret. Update your `.env` file:

```env
GOOGLE_CLIENT_ID=your-actual-client-id-here
GOOGLE_CLIENT_SECRET=your-actual-client-secret-here
```

### 3. Restart the Services

After updating the `.env` file, restart both the API and Dashboard:

```bash
# Kill existing processes
pkill -f "yarn workspace api dev"
pkill -f "yarn workspace dashboard dev"

# Restart with new credentials
cd packages/api
AUTH_MODE=multi-tenant \
AUTH_PROVIDER=google \
DATABASE_URL=postgresql://dittofeed:password@localhost:5433/dittofeed \
REDIS_HOST=localhost \
REDIS_PORT=6380 \
CLICKHOUSE_HOST=localhost \
CLICKHOUSE_PORT=8124 \
CLICKHOUSE_USER=dittofeed \
CLICKHOUSE_PASSWORD=password \
TEMPORAL_ADDRESS=localhost:7234 \
JWT_SECRET=your-jwt-secret \
SECRET_KEY=your-secret-key-for-sessions-change-in-production \
GOOGLE_CLIENT_ID=<your-actual-client-id> \
GOOGLE_CLIENT_SECRET=<your-actual-client-secret> \
yarn dev &

cd ../dashboard
yarn dev &
```

## Testing

1. Open http://localhost:3000/dashboard in your browser
2. You should be redirected to Google OAuth
3. Sign in with your Google account
4. You should be redirected back to the dashboard

## Troubleshooting

### "The OAuth client was not found" Error
- Verify your Client ID is correct in the `.env` file
- Make sure you've saved the OAuth client configuration in Google Cloud Console
- Check that the redirect URIs match exactly

### "redirect_uri_mismatch" Error
- Ensure the redirect URIs in Google Cloud Console exactly match:
  - `http://localhost:3001/api/public/auth/oauth2/callback/google`
- The URI is case-sensitive and must match exactly

### Authentication Loop
- Clear your browser cookies
- Restart both the API and Dashboard services
- Ensure SECRET_KEY is set in your environment variables

## Production Setup

For production, you'll need to:
1. Update the authorized redirect URIs to your production domains
2. Use HTTPS for all URLs
3. Store secrets securely (not in `.env` files)
4. Update CORS and cookie settings for your domain
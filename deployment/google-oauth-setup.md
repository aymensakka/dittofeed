# Google OAuth Setup for Dittofeed Dashboard

## Prerequisites

1. A Google Cloud Console account
2. A project in Google Cloud Console (create one if needed)

## Steps to Configure Google OAuth

### 1. Access Google Cloud Console

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Select your project or create a new one

### 2. Enable Google+ API

1. Navigate to **APIs & Services** > **Library**
2. Search for "Google+ API"
3. Click on it and press **Enable**

### 3. Create OAuth 2.0 Credentials

1. Go to **APIs & Services** > **Credentials**
2. Click **+ CREATE CREDENTIALS** > **OAuth client ID**
3. If prompted, configure the OAuth consent screen first:
   - Choose **External** (unless you have a Google Workspace account)
   - Fill in required fields:
     - App name: "Dittofeed"
     - User support email: Your email
     - Developer contact: Your email
   - Add scopes: `email`, `profile`, `openid`
   - Save and continue

### 4. Configure OAuth Client

1. Application type: **Web application**
2. Name: "Dittofeed Dashboard"
3. Authorized JavaScript origins:
   ```
   https://communication-dashboard.caramelme.com
   ```
4. Authorized redirect URIs:
   ```
   https://communication-dashboard.caramelme.com/api/auth/callback/google
   ```
5. Click **Create**

### 5. Copy Credentials

You'll receive:
- **Client ID**: Something like `123456789012-abcdefghijklmnopqrstuvwxyz123456.apps.googleusercontent.com`
- **Client Secret**: A string like `GOCSPX-1234567890abcdefghijklmnop`

### 6. Update Environment Variables

Add these to your Coolify environment variables:

```bash
GOOGLE_CLIENT_ID=your_client_id_here.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=your_client_secret_here
```

### 7. Verify Configuration

After deployment, the dashboard should show Google as a login option.

## Troubleshooting

### Common Issues

1. **"Error 400: redirect_uri_mismatch"**
   - Ensure the redirect URI matches exactly: `https://communication-dashboard.caramelme.com/api/auth/callback/google`
   - Check for trailing slashes or http vs https

2. **"Access blocked: This app's request is invalid"**
   - Verify the OAuth consent screen is configured
   - Make sure all required fields are filled

3. **No Google button on login page**
   - Check that both `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` are set
   - Verify the dashboard has been redeployed after adding the variables

## Security Notes

- Never commit OAuth credentials to version control
- Rotate credentials periodically
- Restrict authorized domains in production
- Consider implementing domain restrictions in Google OAuth settings for enterprise use
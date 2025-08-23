# Embedded Dashboard Guide

## Overview

The Dittofeed multi-tenant platform supports embedding dashboard components directly into third-party applications via iframes. This allows child workspaces to provide their users with direct access to Dittofeed's marketing automation features within their own applications.

## Architecture

### Authentication Flow

1. **Session Creation**: Parent applications authenticate using their workspace's write key to create embedded sessions
2. **Token Management**: Sessions use JWT access tokens (15 min) with refresh tokens (7 days) for extended access
3. **Security**: Token rotation, reuse detection, and session auditing ensure secure access

### Components Available for Embedding

The following dashboard components can be embedded:

#### Table Views (Read-only)
- `/dashboard-l/embedded/journeys` - View customer journeys
- `/dashboard-l/embedded/broadcasts` - View broadcast campaigns
- `/dashboard-l/embedded/segments` - View audience segments
- `/dashboard-l/embedded/templates` - View message templates
- `/dashboard-l/embedded/deliveries/v2` - View delivery analytics

#### Editors (Interactive)
- `/dashboard-l/embedded/journeys/v2` - Journey workflow editor
- `/dashboard-l/embedded/broadcasts/v2` - Broadcast campaign editor
- `/dashboard-l/embedded/segments/v1` - Segment builder
- `/dashboard-l/embedded/templates/email` - Email template editor
- `/dashboard-l/embedded/templates/sms` - SMS template editor

## API Endpoints

### Session Management

#### Create Session
```bash
POST /api-l/embedded-sessions/create
Authorization: Bearer <WRITE_KEY>
Content-Type: application/json

{
  "workspaceId": "workspace-uuid"
}

Response:
{
  "accessToken": "jwt-token",
  "refreshToken": "refresh-token",
  "expiresIn": 900,
  "tokenType": "Bearer"
}
```

#### Refresh Token
```bash
POST /api-l/embedded-sessions/refresh
Content-Type: application/json

{
  "refreshToken": "refresh-token"
}

Response:
{
  "accessToken": "new-jwt-token",
  "refreshToken": "new-refresh-token",
  "expiresIn": 900,
  "tokenType": "Bearer"
}
```

#### Verify Token
```bash
POST /api-l/embedded-sessions/verify
Content-Type: application/json

{
  "token": "jwt-token"
}

Response:
{
  "valid": true,
  "workspaceId": "workspace-uuid",
  "sessionId": "session-uuid",
  "expiresAt": "2025-01-01T00:00:00Z"
}
```

#### Revoke Session
```bash
POST /api-l/embedded-sessions/revoke
Content-Type: application/json

{
  "refreshToken": "refresh-token"
}

Response:
{
  "success": true
}
```

## Implementation Guide

### Backend Integration

1. **Get Write Key**: Obtain your workspace's write key from the Dittofeed admin panel

2. **Create Session**: Call the session creation endpoint with your write key:

```javascript
const response = await fetch('https://api.dittofeed.com/api-l/embedded-sessions/create', {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${WRITE_KEY}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    workspaceId: WORKSPACE_ID
  })
});

const { accessToken, refreshToken } = await response.json();
```

3. **Store Tokens**: Securely store the refresh token and use it to obtain new access tokens as needed

### Frontend Integration

1. **Embed Component**: Add an iframe to your application:

```html
<iframe
  src="https://dashboard.dittofeed.com/dashboard-l/embedded/journeys?token={accessToken}&workspaceId={workspaceId}"
  width="100%"
  height="600"
  frameborder="0"
></iframe>
```

2. **Handle Token Refresh**: Implement automatic token refresh before expiry:

```javascript
class EmbeddedDashboard {
  constructor(workspaceId, refreshToken) {
    this.workspaceId = workspaceId;
    this.refreshToken = refreshToken;
    this.accessToken = null;
    this.tokenExpiry = null;
  }

  async refreshAccessToken() {
    const response = await fetch('/api-l/embedded-sessions/refresh', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ refreshToken: this.refreshToken })
    });
    
    const data = await response.json();
    this.accessToken = data.accessToken;
    this.refreshToken = data.refreshToken;
    this.tokenExpiry = Date.now() + (data.expiresIn * 1000);
    
    // Schedule next refresh 1 minute before expiry
    setTimeout(() => this.refreshAccessToken(), (data.expiresIn - 60) * 1000);
  }

  getEmbedUrl(component) {
    return `https://dashboard.dittofeed.com/dashboard-l/embedded/${component}?token=${this.accessToken}&workspaceId=${this.workspaceId}`;
  }
}
```

3. **PostMessage Communication**: Listen for events from the embedded dashboard:

```javascript
window.addEventListener('message', (event) => {
  if (event.origin !== 'https://dashboard.dittofeed.com') return;
  
  switch(event.data.type) {
    case 'ready':
      console.log('Dashboard loaded');
      break;
    case 'height':
      // Adjust iframe height dynamically
      iframe.style.height = event.data.height + 'px';
      break;
    case 'navigation':
      // Handle navigation events
      console.log('User navigated to:', event.data.path);
      break;
  }
});
```

## Security Considerations

### Token Security
- Access tokens expire after 15 minutes
- Refresh tokens expire after 7 days (absolute: 30 days)
- Token rotation on each refresh prevents replay attacks
- Reuse detection revokes entire token family on suspicious activity

### Workspace Isolation
- All data access is strictly scoped to the authenticated workspace
- Child workspaces can only access their own data
- Parent workspaces cannot access child workspace data through embedded sessions

### Best Practices
1. **Server-side Token Management**: Never expose write keys or refresh tokens to the browser
2. **HTTPS Only**: Always use HTTPS for production deployments
3. **Origin Validation**: Validate the origin of postMessage events
4. **CSP Headers**: Configure Content Security Policy to allow specific iframe sources
5. **Rate Limiting**: Implement rate limiting on token refresh endpoints

## Database Schema

The embedded sessions feature uses three main tables:

### EmbeddedSession
Stores active sessions with tokens and metadata:
- `sessionId`: Unique session identifier
- `refreshToken`: Current refresh token
- `refreshTokenFamily`: Token family for reuse detection
- `accessTokenHash`: Hash of current access token
- `refreshCount`: Number of times token has been refreshed
- `expiresAt`: Access token expiration
- `refreshExpiresAt`: Absolute refresh token expiration

### EmbeddedSessionAudit
Tracks all session operations for security auditing:
- `action`: created, refreshed, revoked, reuse_detected
- `timestamp`: When the action occurred
- `ipAddress`: Client IP address
- `userAgent`: Client user agent
- `success`: Whether the operation succeeded

### EmbeddedSessionRateLimit
Prevents abuse through rate limiting:
- `key`: IP address or workspace ID
- `type`: Operation type (create, refresh)
- `count`: Request count in window
- `windowStart`: Start of rate limit window

## Testing

A test page is available at `/test-embedded-iframe.html` for local development:

1. Start the development servers:
```bash
./start-api-local.sh
./start-dashboard-local.sh
```

2. Create a test workspace and obtain credentials

3. Open the test page and enter your workspace ID and session token

4. Select a component to embed and test the integration

## Troubleshooting

### Common Issues

1. **404 on embedded pages**: Ensure pages use `.page.tsx` extension
2. **Token expired**: Implement automatic refresh before 15-minute expiry
3. **CORS errors**: Check that API and dashboard are on compatible domains
4. **Session not found**: Verify workspace ID matches the authenticated session

### Debug Endpoints

- Check session validity: `POST /api-l/embedded-sessions/verify`
- View session audit logs in database: `EmbeddedSessionAudit` table
- Monitor rate limits: `EmbeddedSessionRateLimit` table

## Migration from Simple Sessions

If upgrading from the simple JWT-only implementation:

1. Run migration: `0020_embedded_sessions.sql`
2. Update API endpoints to use `/embedded-sessions` instead of `/sessions`
3. Implement refresh token handling in your application
4. Update iframe URLs to include refresh token logic
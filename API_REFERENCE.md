# Dittofeed Multi-Tenant API Reference

## Overview

This document provides a comprehensive API reference for the Dittofeed multi-tenant fork, focusing on embedded dashboard and session management endpoints.

## Base URLs

- **Development**: `http://localhost:3001`
- **Production**: `https://api.your-domain.com`

## Authentication

The API uses multiple authentication methods depending on the endpoint:

1. **Write Key Authentication**: For creating sessions and workspace operations
2. **JWT Bearer Tokens**: For authenticated API calls
3. **Session Tokens**: For embedded dashboard access

---

## Embedded Sessions API

### Create Embedded Session

Creates a new embedded session with refresh token support.

**Endpoint**: `POST /api-l/embedded-sessions/create`

**Headers**:
```
Authorization: Bearer <WRITE_KEY>
Content-Type: application/json
```

**Request Body**:
```json
{
  "workspaceId": "6eed2156-606a-4666-925e-7f89adddd743"
}
```

**Response** (200 OK):
```json
{
  "accessToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refreshToken": "JVUzUqv274agy1ojfE-t9UzBB4jKPfouarLHGZA26wA",
  "expiresIn": 900,
  "tokenType": "Bearer"
}
```

**Response Codes**:
- `200`: Session created successfully
- `401`: Missing or invalid authorization header
- `403`: Invalid workspace or write key
- `500`: Internal server error

**Token Details**:
- Access tokens expire in 15 minutes (900 seconds)
- Refresh tokens expire in 7 days
- Absolute expiry for refresh tokens is 30 days

---

### Refresh Access Token

Refreshes an expired access token using a refresh token.

**Endpoint**: `POST /api-l/embedded-sessions/refresh`

**Headers**:
```
Content-Type: application/json
```

**Request Body**:
```json
{
  "refreshToken": "JVUzUqv274agy1ojfE-t9UzBB4jKPfouarLHGZA26wA"
}
```

**Response** (200 OK):
```json
{
  "accessToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refreshToken": "zqUG8UAhxkH72Umf2jNj9uwgVvt0eEIM3KZuHnrYsvE",
  "expiresIn": 900,
  "tokenType": "Bearer"
}
```

**Response Codes**:
- `200`: Token refreshed successfully
- `401`: Invalid or expired refresh token

**Security Notes**:
- Each refresh generates new access AND refresh tokens (token rotation)
- Old refresh tokens are immediately invalidated
- Token reuse triggers security alert and revokes entire token family

---

### Verify Session Token

Verifies the validity of an access token.

**Endpoint**: `POST /api-l/embedded-sessions/verify`

**Headers**:
```
Content-Type: application/json
```

**Request Body**:
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Response** (200 OK - Valid Token):
```json
{
  "valid": true,
  "workspaceId": "6eed2156-606a-4666-925e-7f89adddd743",
  "sessionId": "25117e6d-9f25-464b-b718-d6fd2c3117db",
  "expiresAt": "2025-08-23T12:02:26.000Z"
}
```

**Response** (200 OK - Invalid Token):
```json
{
  "valid": false
}
```

**Response Codes**:
- `200`: Verification completed (check `valid` field)

---

### Revoke Session

Revokes an active session.

**Endpoint**: `POST /api-l/embedded-sessions/revoke`

**Headers**:
```
Content-Type: application/json
```

**Request Body** (Option 1 - Using Refresh Token):
```json
{
  "refreshToken": "JVUzUqv274agy1ojfE-t9UzBB4jKPfouarLHGZA26wA"
}
```

**Request Body** (Option 2 - Using Session ID):
```json
{
  "sessionId": "25117e6d-9f25-464b-b718-d6fd2c3117db"
}
```

**Response** (200 OK):
```json
{
  "success": true
}
```

**Response Codes**:
- `200`: Session revoked successfully
- `401`: Session not found or invalid parameters
- `500`: Internal server error

---

## Simple Sessions API (Legacy)

### Create Simple Session

Creates a simple JWT session without refresh token support.

**Endpoint**: `POST /api-l/sessions`

**Headers**:
```
Authorization: Bearer <WRITE_KEY>
Content-Type: application/json
```

**Request Body**:
```json
{
  "workspaceId": "6eed2156-606a-4666-925e-7f89adddd743"
}
```

**Response** (200 OK):
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "expiresAt": "2025-08-23T12:46:50.275Z"
}
```

**Note**: Simple sessions expire after 1 hour and cannot be refreshed.

---

### Verify Simple Session

Verifies a simple session token.

**Endpoint**: `POST /api-l/sessions/verify`

**Headers**:
```
Content-Type: application/json
```

**Request Body**:
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Response** (200 OK):
```json
{
  "valid": true,
  "workspaceId": "6eed2156-606a-4666-925e-7f89adddd743",
  "expiresAt": "2025-08-23T12:46:50.275Z"
}
```

---

## Embedded Dashboard URLs

Once you have a valid session token, you can embed dashboard components using these URLs:

### Table Views (Read-only)

```
https://dashboard.your-domain.com/dashboard/dashboard-l/embedded/journeys?token={token}&workspaceId={workspaceId}
https://dashboard.your-domain.com/dashboard/dashboard-l/embedded/broadcasts?token={token}&workspaceId={workspaceId}
https://dashboard.your-domain.com/dashboard/dashboard-l/embedded/segments?token={token}&workspaceId={workspaceId}
https://dashboard.your-domain.com/dashboard/dashboard-l/embedded/templates?token={token}&workspaceId={workspaceId}
https://dashboard.your-domain.com/dashboard/dashboard-l/embedded/deliveries/v2?token={token}&workspaceId={workspaceId}
```

### Interactive Editors

```
https://dashboard.your-domain.com/dashboard/dashboard-l/embedded/journeys/v2?token={token}&workspaceId={workspaceId}&id={journeyId}
https://dashboard.your-domain.com/dashboard/dashboard-l/embedded/broadcasts/v2?token={token}&workspaceId={workspaceId}&id={broadcastId}
https://dashboard.your-domain.com/dashboard/dashboard-l/embedded/segments/v1?token={token}&workspaceId={workspaceId}&id={segmentId}
https://dashboard.your-domain.com/dashboard/dashboard-l/embedded/templates/email?token={token}&workspaceId={workspaceId}&id={templateId}
https://dashboard.your-domain.com/dashboard/dashboard-l/embedded/templates/sms?token={token}&workspaceId={workspaceId}&id={templateId}
```

---

## Rate Limiting

The API implements rate limiting to prevent abuse:

- **Session Creation**: 10 requests per minute per workspace
- **Token Refresh**: 30 requests per minute per workspace
- **Verification**: 100 requests per minute per IP

Rate limit information is returned in response headers:
```
X-RateLimit-Limit: 10
X-RateLimit-Remaining: 9
X-RateLimit-Reset: 1755950000
```

---

## Error Responses

All error responses follow this format:

```json
{
  "error": "Error message describing what went wrong",
  "code": "ERROR_CODE",
  "details": {
    // Additional context if available
  }
}
```

Common error codes:
- `INVALID_WRITE_KEY`: The provided write key is invalid
- `TOKEN_EXPIRED`: The access token has expired
- `REFRESH_TOKEN_REUSED`: Security violation - token reuse detected
- `RATE_LIMIT_EXCEEDED`: Too many requests
- `WORKSPACE_NOT_FOUND`: The specified workspace doesn't exist
- `INTERNAL_ERROR`: Server error occurred

---

## Security Best Practices

1. **Never expose write keys in client-side code**
   - Write keys should only be used server-side
   - Create sessions from your backend, pass tokens to frontend

2. **Implement token refresh logic**
   ```javascript
   // Example refresh implementation
   async function ensureValidToken() {
     if (tokenExpiresAt - Date.now() < 60000) { // Refresh 1 min before expiry
       await refreshToken();
     }
     return currentAccessToken;
   }
   ```

3. **Handle token rotation correctly**
   - Always store the new refresh token after refresh
   - Never reuse old refresh tokens

4. **Validate iframe origins**
   ```javascript
   window.addEventListener('message', (event) => {
     if (!trustedOrigins.includes(event.origin)) return;
     // Handle message
   });
   ```

5. **Use HTTPS in production**
   - All API calls should use HTTPS
   - Set secure cookies and headers

---

## Migration Guide

### From Simple Sessions to Embedded Sessions

1. Update your session creation calls:
   ```javascript
   // Old
   const { token } = await createSimpleSession(workspaceId);
   
   // New
   const { accessToken, refreshToken } = await createEmbeddedSession(workspaceId);
   ```

2. Implement refresh logic:
   ```javascript
   class SessionManager {
     async refreshIfNeeded() {
       if (this.isExpiringSoon()) {
         const { accessToken, refreshToken } = await this.refresh();
         this.updateTokens(accessToken, refreshToken);
       }
     }
   }
   ```

3. Update iframe URLs to use new tokens:
   ```html
   <!-- Old -->
   <iframe src="...?token={simpleToken}">
   
   <!-- New -->
   <iframe src="...?token={accessToken}">
   ```

---

## Support

For API support and questions:
- GitHub Issues: https://github.com/aymensakka/dittofeed-multitenant/issues
- Documentation: See EMBEDDED_DASHBOARD_GUIDE.md
- Email: support@your-domain.com
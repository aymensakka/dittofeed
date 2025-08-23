# OAuth Authentication Fix Summary

## Current Issues

1. **Authentication Flow Broken**: OAuth successfully logs users in but API calls fail with 401
2. **Token Mismatch**: API expects JWT tokens but OAuth only sets simple cookies
3. **Session Not Recognized**: The cookies (df-authenticated, df-workspace, etc.) are not valid sessions for the API

## Root Cause

The multi-tenant authentication implementation is incomplete:
- OAuth callback sets simple cookies but doesn't generate JWT tokens
- API's `getRequestContext` expects JWT in Authorization header
- No proper session bridge between OAuth and API authentication

## Required Fixes

### Option 1: JWT Token Generation (Recommended)
1. Modify OAuth callback to generate JWT token after successful auth
2. Send JWT to client (via redirect parameter or cookie)
3. Update dashboard to include JWT in Authorization header for all API calls
4. Store JWT in localStorage or secure cookie

### Option 2: Session-Based Auth
1. Implement proper server-side session storage (Redis)
2. Create session after OAuth callback
3. Modify `getRequestContext` to validate session cookies
4. Add session middleware to API routes

### Option 3: Hybrid Approach
1. Use secure httpOnly cookies for session
2. Generate short-lived JWT tokens from session
3. Refresh tokens automatically

## Current Workaround Attempts

1. ✅ Created WriteKey table 
2. ✅ Fixed CORS for credentials
3. ✅ Updated axios to include credentials
4. ❌ Session cookies not recognized by API
5. ❌ JWT token generation missing

## Next Steps

To properly fix this, we need to:

1. **Generate JWT after OAuth**:
   ```javascript
   const jwt = require('jsonwebtoken');
   const token = jwt.sign({
     sub: userInfo.id,
     email: userInfo.email,
     workspaceId: workspaceId,
     name: userInfo.name
   }, process.env.JWT_SECRET, { expiresIn: '7d' });
   ```

2. **Pass JWT to client**:
   - Option A: Redirect with token in URL
   - Option B: Set as httpOnly cookie
   - Option C: Exchange endpoint

3. **Update client to use JWT**:
   ```javascript
   axios.defaults.headers.common['Authorization'] = `Bearer ${token}`;
   ```

4. **Update getRequestContext to handle cookies in multi-tenant**:
   - Parse session cookies
   - Validate against database
   - Create proper context

## Database Issues

- Missing unique constraints causing ON CONFLICT errors
- Need to ensure all OAuth-related tables have proper constraints

## Testing

Once fixed, test with:
```bash
curl http://localhost:3001/api/subscription-groups \
  -H "Authorization: Bearer <jwt-token>" \
  -H "Content-Type: application/json"
```
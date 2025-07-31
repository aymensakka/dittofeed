# API Key and Iframe Embedding for Multitenant Integration

This guide explains how to integrate Dittofeed into your multitenant SaaS application using API keys and iframe embedding, without requiring OIDC/OAuth authentication.

## Overview

Dittofeed's multitenant architecture allows you to embed messaging automation features directly into your application. Each of your customers gets their own isolated workspace with full access to Dittofeed's features including journey builders, segmentation, email templates, and more.

### Key Benefits

- **No OIDC/OAuth Required**: Simple API key authentication
- **Complete Tenant Isolation**: Each customer's data is fully separated
- **Easy Integration**: Embed via iframes with session tokens
- **Parent-Child Architecture**: Manage all tenants from a single parent workspace

## Architecture

```
Your SaaS Platform (Parent Workspace)
    ├── API Key (manages all child workspaces)
    │
    ├── Customer A (Child Workspace)
    │   └── Isolated data, journeys, templates
    │
    ├── Customer B (Child Workspace)
    │   └── Isolated data, journeys, templates
    │
    └── Customer C (Child Workspace)
        └── Isolated data, journeys, templates
```

## Authentication Flow

### 1. Parent Workspace API Key

Your parent workspace API key can:
- Authenticate to any child workspace
- Create session tokens for child workspaces
- Manage child workspace resources

### 2. Authentication Logic

The API key authentication supports both direct and parent-child authentication:

```javascript
// Direct authentication - API key belongs to the target workspace
// OR
// Parent authentication - API key belongs to parent of target workspace
```

Both the parent and child workspaces must have `Active` status for authentication to succeed.

## Implementation Guide

### Step 1: Create Parent Workspace and API Key

1. Set up your main Dittofeed workspace (parent)
2. Generate an admin API key for the parent workspace
3. Store this API key securely in your backend

### Step 2: Create Child Workspaces for Each Tenant

For each of your customers, create a child workspace:

```bash
POST /api/workspaces
Authorization: Bearer YOUR_PARENT_API_KEY
Content-Type: application/json

{
  "name": "Customer A Workspace",
  "externalId": "customer-a-unique-id",
  "parentWorkspaceId": "YOUR_PARENT_WORKSPACE_ID"
}
```

### Step 3: Generate Session Tokens

When a user needs to access Dittofeed features, generate a session token:

```bash
POST /api/embedded/session
Authorization: Bearer YOUR_PARENT_API_KEY
Content-Type: application/json

{
  "workspaceId": "CHILD_WORKSPACE_ID",
  "expiresIn": 3600  // 1 hour (default)
}
```

Response:
```json
{
  "token": "eyJ0eXAiOiJKV1QiLCJhbGc...",
  "expiresAt": "2024-01-01T12:00:00Z"
}
```

### Step 4: Embed Dittofeed Components

Use the session token to embed Dittofeed components in your application:

```html
<!-- Journey Builder -->
<iframe
  src="https://app.dittofeed.com/dashboard-l/embedded/journeys/v2?token=${SESSION_TOKEN}&workspaceId=${CHILD_WORKSPACE_ID}&id=${JOURNEY_ID}"
  width="100%"
  height="800px"
></iframe>

<!-- Journey Table (List View) -->
<iframe
  src="https://app.dittofeed.com/dashboard-l/embedded/journeys?token=${SESSION_TOKEN}&workspaceId=${CHILD_WORKSPACE_ID}"
  width="100%"
  height="600px"
></iframe>

<!-- Broadcast Editor -->
<iframe
  src="https://app.dittofeed.com/dashboard-l/embedded/broadcasts/v2?token=${SESSION_TOKEN}&workspaceId=${CHILD_WORKSPACE_ID}&id=${BROADCAST_ID}"
  width="100%"
  height="800px"
></iframe>

<!-- Email Template Editor -->
<iframe
  src="https://app.dittofeed.com/dashboard-l/embedded/templates/email?token=${SESSION_TOKEN}&workspaceId=${CHILD_WORKSPACE_ID}&id=${TEMPLATE_ID}"
  width="100%"
  height="800px"
></iframe>

<!-- SMS Template Editor -->
<iframe
  src="https://app.dittofeed.com/dashboard-l/embedded/templates/sms?token=${SESSION_TOKEN}&workspaceId=${CHILD_WORKSPACE_ID}&id=${TEMPLATE_ID}"
  width="100%"
  height="600px"
></iframe>

<!-- Segment Editor -->
<iframe
  src="https://app.dittofeed.com/dashboard-l/embedded/segments/v1?token=${SESSION_TOKEN}&workspaceId=${CHILD_WORKSPACE_ID}&id=${SEGMENT_ID}"
  width="100%"
  height="800px"
></iframe>

<!-- Deliveries Table -->
<iframe
  src="https://app.dittofeed.com/dashboard-l/embedded/deliveries/v2?token=${SESSION_TOKEN}&workspaceId=${CHILD_WORKSPACE_ID}"
  width="100%"
  height="600px"
></iframe>
```

## Available Embedded Components

### 1. Journey Management
- **Journey Builder**: Visual workflow editor for creating customer journeys
- **Journey Table**: List and manage all journeys

### 2. Broadcast Management
- **Broadcast Editor**: Configure one-time campaigns
- **Broadcast Table**: View and manage broadcasts

### 3. Template Management
- **Email Editor**: Rich email template builder
- **SMS Editor**: SMS message composer
- **Templates Table**: Manage all message templates

### 4. Segmentation
- **Segment Builder**: Create customer segments with visual rules
- **Segments Table**: View and manage segments

### 5. Analytics
- **Deliveries Table**: Track message delivery status and metrics

## Best Practices

### 1. Session Token Management

```javascript
// Backend endpoint to get session token
app.post('/api/dittofeed/session', authenticate, async (req, res) => {
  const customerId = req.user.customerId;
  const childWorkspaceId = await getWorkspaceIdForCustomer(customerId);
  
  const response = await fetch('https://api.dittofeed.com/api/embedded/session', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${PARENT_API_KEY}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      workspaceId: childWorkspaceId,
      expiresIn: 3600
    })
  });
  
  const { token } = await response.json();
  res.json({ token, workspaceId: childWorkspaceId });
});
```

### 2. Frontend Integration

```javascript
// React component example
function DittofeedJourneyBuilder({ customerId }) {
  const [sessionData, setSessionData] = useState(null);
  
  useEffect(() => {
    // Fetch session token from your backend
    fetch('/api/dittofeed/session')
      .then(res => res.json())
      .then(data => setSessionData(data));
  }, []);
  
  if (!sessionData) return <div>Loading...</div>;
  
  return (
    <iframe
      src={`https://app.dittofeed.com/dashboard-l/embedded/journeys?token=${sessionData.token}&workspaceId=${sessionData.workspaceId}`}
      width="100%"
      height="800px"
      frameBorder="0"
    />
  );
}
```

### 3. Security Considerations

1. **Never expose your parent API key to the frontend**
2. **Always generate session tokens server-side**
3. **Implement proper authentication before generating tokens**
4. **Use HTTPS for all API communications**
5. **Set appropriate expiration times for session tokens**

### 4. Workspace Isolation

Each child workspace is completely isolated:
- Separate user data
- Independent journeys and campaigns
- Isolated message templates
- Separate analytics and metrics
- Independent quota limits

## API Authentication Methods

### Using Workspace ID

```bash
# Include workspace ID in header
curl -X GET https://api.dittofeed.com/api/users \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "X-Workspace-Id: CHILD_WORKSPACE_ID"

# Or in query parameter
curl -X GET https://api.dittofeed.com/api/users?workspaceId=CHILD_WORKSPACE_ID \
  -H "Authorization: Bearer YOUR_API_KEY"
```

### Using External ID

```bash
# Using external ID instead of workspace ID
curl -X GET https://api.dittofeed.com/api/users \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "X-Workspace-External-Id: customer-unique-id"
```

## Troubleshooting

### Common Issues

1. **401 Unauthorized**
   - Verify API key is correct
   - Check both parent and child workspaces are Active
   - Ensure proper Authorization header format: `Bearer YOUR_KEY`

2. **Session Token Expired**
   - Session tokens expire after the specified duration (default 1 hour)
   - Implement token refresh logic in your application

3. **Iframe Not Loading**
   - Check browser console for errors
   - Verify session token is valid
   - Ensure workspace ID is correct
   - Check for Content Security Policy (CSP) restrictions

### Debugging Authentication

```javascript
// Test API key authentication
const testAuth = async () => {
  const response = await fetch('https://api.dittofeed.com/api/workspaces', {
    headers: {
      'Authorization': `Bearer ${YOUR_API_KEY}`,
      'X-Workspace-Id': CHILD_WORKSPACE_ID
    }
  });
  
  console.log('Status:', response.status);
  console.log('Response:', await response.json());
};
```

## Example Implementation

### Complete Node.js Example

```javascript
const express = require('express');
const app = express();

// Store this securely (environment variable, secret manager, etc.)
const DITTOFEED_PARENT_API_KEY = process.env.DITTOFEED_API_KEY;

// Middleware to get Dittofeed session
app.post('/api/messaging/session', authenticateUser, async (req, res) => {
  try {
    // Get workspace ID for the authenticated customer
    const workspaceId = await getCustomerWorkspaceId(req.user.customerId);
    
    // Request session token from Dittofeed
    const response = await fetch('https://api.dittofeed.com/api/embedded/session', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${DITTOFEED_PARENT_API_KEY}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        workspaceId: workspaceId,
        expiresIn: 3600 // 1 hour
      })
    });
    
    if (!response.ok) {
      throw new Error('Failed to create session');
    }
    
    const sessionData = await response.json();
    
    res.json({
      token: sessionData.token,
      workspaceId: workspaceId,
      expiresAt: sessionData.expiresAt
    });
  } catch (error) {
    console.error('Error creating Dittofeed session:', error);
    res.status(500).json({ error: 'Failed to create messaging session' });
  }
});

// Serve the page with embedded Dittofeed
app.get('/dashboard/messaging', authenticateUser, (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html>
    <head>
      <title>Messaging Dashboard</title>
    </head>
    <body>
      <div id="messaging-container"></div>
      <script>
        // Fetch session token
        fetch('/api/messaging/session', { method: 'POST' })
          .then(res => res.json())
          .then(data => {
            // Create iframe with session token
            const iframe = document.createElement('iframe');
            iframe.src = \`https://app.dittofeed.com/dashboard-l/embedded/journeys?token=\${data.token}&workspaceId=\${data.workspaceId}\`;
            iframe.width = '100%';
            iframe.height = '800px';
            iframe.frameBorder = '0';
            
            document.getElementById('messaging-container').appendChild(iframe);
          });
      </script>
    </body>
    </html>
  `);
});
```

## Summary

Using API keys and iframe embedding provides a simple, secure way to integrate Dittofeed's messaging automation into your multitenant application without the complexity of OIDC/OAuth. The parent-child workspace architecture ensures complete tenant isolation while giving you centralized control through a single API key.

This approach is ideal for:
- SaaS platforms wanting to add messaging features
- Applications needing white-labeled marketing automation
- Platforms requiring strict tenant data isolation
- Teams wanting quick integration without complex auth flows
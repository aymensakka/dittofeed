# Dittofeed Multitenant Integration Guide

This guide helps third-party applications integrate with Dittofeed to provide messaging automation capabilities to their users.

## What is Dittofeed?

Dittofeed is an open-source customer engagement platform that provides:
- Visual journey builders for marketing automation
- Email and SMS campaign management
- Customer segmentation tools
- Message delivery analytics
- Subscription management

## Integration Overview

Integrate Dittofeed into your application to offer these features to your customers without building them from scratch. Each of your customers gets their own isolated workspace with full messaging capabilities.

### Integration Benefits

✅ **Quick Implementation** - Add messaging features in hours, not months  
✅ **No Authentication Complexity** - Simple API key-based integration  
✅ **White-Label Ready** - Embed seamlessly into your UI  
✅ **Complete Data Isolation** - Each customer's data is fully separated  
✅ **Scalable Architecture** - Grows with your customer base  

## How It Works

### 1. Architecture

```
Your Application
    │
    ├── Dittofeed Parent Account (Your main account)
    │   ├── API Key (Controls all customer workspaces)
    │   │
    │   ├── Customer A Workspace
    │   ├── Customer B Workspace
    │   └── Customer C Workspace
```

### 2. Simple 3-Step Integration

1. **Get API Access** - Obtain a parent workspace API key from Dittofeed
2. **Create Customer Workspaces** - Provision a workspace for each customer
3. **Embed UI Components** - Add Dittofeed features to your application

## Quick Start Guide

### Prerequisites

- A Dittofeed account with parent workspace access
- Basic knowledge of REST APIs
- Ability to embed iframes in your application

### Step 1: Initial Setup

Contact Dittofeed to set up your parent workspace and obtain:
- Parent Workspace ID
- Admin API Key
- API Endpoint URLs

### Step 2: Create Customer Workspaces

When onboarding a new customer, create their workspace:

```bash
POST https://api.dittofeed.com/api/workspaces
Authorization: Bearer YOUR_API_KEY
Content-Type: application/json

{
  "name": "Customer Name - Workspace",
  "externalId": "your-customer-id",
  "parentWorkspaceId": "YOUR_PARENT_WORKSPACE_ID"
}
```

### Step 3: Generate Session Tokens

Create temporary session tokens for secure frontend access:

```bash
POST https://api.dittofeed.com/api/embedded/session
Authorization: Bearer YOUR_API_KEY
Content-Type: application/json

{
  "workspaceId": "CUSTOMER_WORKSPACE_ID",
  "expiresIn": 3600
}
```

### Step 4: Embed Components

Add Dittofeed features to your application:

```html
<iframe
  src="https://app.dittofeed.com/dashboard-l/embedded/journeys?token=SESSION_TOKEN&workspaceId=WORKSPACE_ID"
  width="100%"
  height="800px"
  frameBorder="0"
></iframe>
```

## Available Features

### 📧 Email Marketing

- **Visual Email Builder** - Drag-and-drop email template creation
- **Personalization** - Dynamic content based on customer data
- **A/B Testing** - Test different versions for better results

### 🚀 Journey Automation

- **Visual Workflow Builder** - Create complex customer journeys
- **Trigger Events** - Start journeys based on user actions
- **Branching Logic** - Different paths based on user behavior

### 👥 Customer Segmentation

- **Dynamic Segments** - Auto-updating based on rules
- **Behavioral Targeting** - Target based on actions
- **Property-Based** - Segment by user attributes

### 📊 Analytics & Reporting

- **Delivery Metrics** - Open rates, click rates, conversions
- **Journey Performance** - See how users flow through journeys
- **Real-time Updates** - Live delivery status tracking

## Integration Examples

### Basic Integration (JavaScript)

```javascript
// Backend: Generate session token
async function getDittofeedSession(customerId) {
  const response = await fetch('/api/dittofeed/session', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Customer-ID': customerId
    }
  });
  
  return response.json();
}

// Frontend: Embed journey builder
async function loadMessagingDashboard() {
  const session = await getDittofeedSession(currentUser.customerId);
  
  const container = document.getElementById('messaging-dashboard');
  container.innerHTML = `
    <iframe 
      src="https://app.dittofeed.com/dashboard-l/embedded/journeys?token=${session.token}&workspaceId=${session.workspaceId}"
      style="width: 100%; height: 800px; border: none;"
    ></iframe>
  `;
}
```

### React Integration

```jsx
import { useState, useEffect } from 'react';

function MessagingDashboard({ customerId }) {
  const [session, setSession] = useState(null);
  
  useEffect(() => {
    // Fetch session from your backend
    fetchDittofeedSession(customerId)
      .then(setSession);
  }, [customerId]);
  
  if (!session) return <div>Loading...</div>;
  
  return (
    <iframe
      src={`https://app.dittofeed.com/dashboard-l/embedded/journeys?token=${session.token}&workspaceId=${session.workspaceId}`}
      style={{ width: '100%', height: '800px', border: 'none' }}
    />
  );
}
```

## API Reference

### Authentication

All API requests require authentication via Bearer token:

```
Authorization: Bearer YOUR_API_KEY
```

### Workspace Identification

Specify which workspace to access using either:

```bash
# Option 1: Workspace ID
X-Workspace-Id: workspace_id

# Option 2: External ID (your customer ID)
X-Workspace-External-Id: your_customer_id
```

### Core Endpoints

#### Create Workspace
```
POST /api/workspaces
```

#### Generate Session Token
```
POST /api/embedded/session
```

#### Send Events (for triggering journeys)
```
POST /api/track
```

#### Manage Users
```
POST /api/identify
GET /api/users
```

## Embeddable Components

### Journey Builder
Build and edit customer journeys:
```
/dashboard-l/embedded/journeys/v2?token=TOKEN&workspaceId=ID&id=JOURNEY_ID
```

### Journey List
View all journeys:
```
/dashboard-l/embedded/journeys?token=TOKEN&workspaceId=ID
```

### Email Template Editor
Create email templates:
```
/dashboard-l/embedded/templates/email?token=TOKEN&workspaceId=ID&id=TEMPLATE_ID
```

### Broadcast Manager
One-time campaigns:
```
/dashboard-l/embedded/broadcasts/v2?token=TOKEN&workspaceId=ID&id=BROADCAST_ID
```

### Segment Builder
Create customer segments:
```
/dashboard-l/embedded/segments/v1?token=TOKEN&workspaceId=ID&id=SEGMENT_ID
```

### Delivery Analytics
Track message performance:
```
/dashboard-l/embedded/deliveries/v2?token=TOKEN&workspaceId=ID
```

## Security Best Practices

### 🔒 API Key Security

- **Never expose API keys in frontend code**
- **Store keys in secure environment variables**
- **Rotate keys periodically**
- **Use different keys for different environments**

### 🛡️ Session Token Management

```javascript
// Good: Generate tokens server-side with expiration
app.post('/api/dittofeed-session', authenticate, async (req, res) => {
  const session = await createDittofeedSession({
    customerId: req.user.customerId,
    expiresIn: 3600 // 1 hour
  });
  
  res.json({ token: session.token, expiresAt: session.expiresAt });
});

// Bad: Never do this
const API_KEY = 'sk_live_...'; // Exposed in frontend!
```

### 🔐 Data Isolation

Each workspace is completely isolated:
- Customer data never mixes between workspaces
- API keys are scoped to specific workspaces
- Users in one workspace cannot access another

## Implementation Checklist

- [ ] Obtain parent workspace access from Dittofeed
- [ ] Store API credentials securely
- [ ] Implement workspace creation for new customers
- [ ] Create backend endpoint for session token generation
- [ ] Add authentication to session token endpoint
- [ ] Implement token refresh logic
- [ ] Embed Dittofeed components in your UI
- [ ] Test with a sample customer workspace
- [ ] Monitor API usage and errors
- [ ] Plan for scaling and rate limits

## Common Use Cases

### 1. SaaS Email Marketing
Add email marketing to your SaaS:
```javascript
// When customer signs up
const workspace = await createDittofeedWorkspace(customer.id);

// In your dashboard
<Tab label="Email Campaigns">
  <DittofeedEmbed type="journeys" customerId={customer.id} />
</Tab>
```

### 2. E-commerce Automation
Abandoned cart and order notifications:
```javascript
// Track purchase events
await dittofeedTrack({
  userId: customer.id,
  event: 'Order Completed',
  properties: { orderId, total, items }
});
```

### 3. Customer Success Platform
Onboarding and engagement campaigns:
```javascript
// Trigger onboarding journey
await dittofeedIdentify({
  userId: user.id,
  traits: { 
    signupDate: new Date(),
    plan: 'premium',
    onboardingStage: 'started'
  }
});
```

## Pricing & Limits

Contact Dittofeed for:
- API rate limits
- Workspace quotas
- Message sending limits
- Custom enterprise pricing

## Support Resources

### Documentation
- [API Documentation](https://docs.dittofeed.com/api-reference)
- [Embedded Components Guide](https://docs.dittofeed.com/embedded/getting-started)
- [Event Tracking Guide](https://docs.dittofeed.com/guide/submitting-user-events)

### Getting Help
- **Technical Support**: support@dittofeed.com
- **Sales Inquiries**: sales@dittofeed.com
- **Community**: [Discord](https://discord.gg/dittofeed) / [GitHub](https://github.com/dittofeed/dittofeed)

## Next Steps

1. **Contact Sales** - Get your parent workspace set up
2. **Review Documentation** - Understand all available features
3. **Build Prototype** - Start with one customer workspace
4. **Plan Rollout** - Gradually add messaging features to your app

---

Ready to add powerful messaging capabilities to your application? Contact Dittofeed to get started with your multitenant integration today!
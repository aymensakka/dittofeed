## Context

This PRP extends the existing Dittofeed marketing automation implementation to handle Apple Wallet and Google Wallet pass update notifications. By leveraging Dittofeed's notification infrastructure alongside Kafka and Redis, we can create a robust pass notification system that replaces Pass2U's enterprise webhook features.

### Business Value
- **Cost Optimization**: Eliminate need for Pass2U enterprise plan ($500+/month)
- **Unified Notifications**: Single platform for all customer communications
- **Enhanced Analytics**: Track pass engagement through marketing journeys
- **Scalability**: Leverage existing Kafka/Redis infrastructure
- **Multitenancy**: Full workspace isolation for enterprise customers

### Technical Context
- **Current State**: Pass updates via Pass2U API, no push notifications without enterprise license
- **Existing Assets**: Dittofeed workspace provisioning, event tracking, webhook handlers
- **Target State**: Dittofeed as unified notification provider for passes and marketing
- **Architecture**: TypeScript monorepo with Fastify API, Next.js dashboard, Drizzle ORM
- **Workspace Model**: Hierarchical workspace support (Root/Parent/Child)
- **Auth Modes**: Support for anonymous, single-tenant, and multi-tenant deployments

## Architecture Overview

```
┌─────────────────┐    ┌──────────────────────┐    ┌─────────────────┐
│   Pass Events   │    │   Dittofeed Core     │    │ Channel Providers│
│   (User Props)  │───▶│  ┌────────────────┐  │───▶│ ┌─────────────┐ │
│   - pass.issued │    │  │ Journey Engine │  │    │ │    Email    │ │
│   - pass.updated│    │  └───────┬────────┘  │    │ ├─────────────┤ │
│   - pass.redeemed    │  │ Message Delivery│  │    │ │     SMS     │ │
└─────────────────┘    │  │    Pipeline     │  │    │ ├─────────────┤ │
                       │  └───────┬────────┘  │    │ │   Webhook   │ │
                       │          │           │    │ ├─────────────┤ │
                       │  ┌───────▼────────┐  │    │ │Pass (New!)  │ │
                       │  │Channel Router  │  │    │ │ ├─────────┐ │ │
                       │  │& Orchestrator  │  │    │ │ │Apple    │ │ │
                       │  └────────────────┘  │    │ │ │Google   │ │ │
                       └──────────────────────┘    │ └─┴─────────┘ │
                                                   └─────────────────┘
```

### Integration Points

1. **Pass Events**: Tracked as user properties and events in Dittofeed
2. **Journey Engine**: Existing journey builder supports pass channel natively
3. **Message Delivery**: Pass messages flow through standard delivery pipeline
4. **Channel Provider**: Pass provider implements standard channel interface
5. **Analytics**: Pass engagement tracked alongside other channels
6. **UI Integration**: Pass channel appears in existing channel configuration

## Implementation Summary

### Key Architecture Changes

1. **Pass as Native Channel**: Instead of building a separate notification system, Pass notifications are implemented as a first-class channel type in Dittofeed, alongside Email, SMS, and Webhook channels.

2. **Unified Journey Builder**: Pass updates can be triggered through the same journey builder interface used for other channels, enabling sophisticated multi-channel campaigns.

3. **Existing UI Integration**: No new UI components needed - the existing channel configuration and journey builder interfaces are extended to support Pass channels.

4. **Standard Message Delivery**: Pass notifications flow through Dittofeed's existing message delivery pipeline, ensuring consistent handling, retries, and analytics.

## Implementation Guide

### Phase 1: Pass Notification as Native Dittofeed Channel

#### 1.1 Pass Channel Integration into Dittofeed Core
```typescript
// packages/backend-lib/src/channels/pass/index.ts
import { ChannelProvider } from '../types';
import { Result, ok, err } from 'neverthrow';
import * as apn from 'apn';
import { logger } from '../../telemetry';
import { Type } from '@sinclair/typebox';

// Define Pass channel configuration schema
export const PassChannelConfigSchema = Type.Object({
  provider: Type.Union([
    Type.Literal('apple_wallet'),
    Type.Literal('google_wallet')
  ]),
  appleConfig: Type.Optional(Type.Object({
    keyPath: Type.String(),
    keyId: Type.String(),
    teamId: Type.String(),
    passTypeId: Type.String()
  })),
  googleConfig: Type.Optional(Type.Object({
    serviceAccountKey: Type.String(),
    issuerId: Type.String()
  }))
});

// Define Pass channel template schema
export const PassTemplateSchema = Type.Object({
  passId: Type.String(),
  updateType: Type.Union([
    Type.Literal('balance_update'),
    Type.Literal('expiry_reminder'),
    Type.Literal('redemption_notification'),
    Type.Literal('general_update')
  ]),
  data: Type.Record(Type.String(), Type.Any())
});

export class PassChannelProvider implements ChannelProvider {
  public readonly type = 'pass' as const;
  private apnProvider?: apn.Provider;
  
  async initialize(config: any): Promise<Result<void, Error>> {
    try {
      if (config.provider === 'apple_wallet' && config.appleConfig) {
        this.apnProvider = new apn.Provider({
          token: {
            key: config.appleConfig.keyPath,
            keyId: config.appleConfig.keyId,
            teamId: config.appleConfig.teamId
          },
          production: process.env.NODE_ENV === 'production'
        });
      }
      
      logger.info('Pass channel provider initialized', { provider: config.provider });
      return ok(undefined);
    } catch (error) {
      return err(error as Error);
    }
  }

  async send(params: {
    to: string; // Pass ID
    template: any;
    workspaceId: string;
    userId?: string;
  }): Promise<Result<{ messageId: string }, Error>> {
    const { to: passId, template, workspaceId } = params;
    
    try {
      // Get devices registered for this pass
      const devices = await this.getDevicesForPass(passId, workspaceId);
      
      if (devices.length === 0) {
        logger.info('No devices registered for pass', { passId, workspaceId });
        return ok({ messageId: `no-devices-${passId}` });
      }
      
      // Send notifications based on provider
      if (template.provider === 'apple_wallet' && this.apnProvider) {
        const notification = new apn.Notification({
          topic: template.passTypeId,
          payload: {},
          pushType: 'background',
          priority: 5
        });
        
        const results = await this.apnProvider.send(notification, devices);
        
        logger.info('Apple Wallet notifications sent', {
          passId,
          sent: results.sent.length,
          failed: results.failed.length
        });
        
        return ok({ messageId: `apn-${passId}-${Date.now()}` });
      }
      
      if (template.provider === 'google_wallet') {
        // Google Wallet update logic
        await this.updateGoogleWalletPass(passId, template.data);
        return ok({ messageId: `google-${passId}-${Date.now()}` });
      }
      
      return err(new Error('Invalid provider configuration'));
    } catch (error) {
      logger.error('Failed to send pass notification', { error, passId });
      return err(error as Error);
    }
  }
  
  // Implement ChannelProvider interface methods
  async validateConfig(config: any): Promise<Result<void, Error>> {
    const validation = PassChannelConfigSchema.safeParse(config);
    if (!validation.success) {
      return err(new Error(validation.error.message));
    }
    return ok(undefined);
  }
  
  async validateTemplate(template: any): Promise<Result<void, Error>> {
    const validation = PassTemplateSchema.safeParse(template);
    if (!validation.success) {
      return err(new Error(validation.error.message));
    }
    return ok(undefined);
  }

  async handlePassNotification(
    notification: PassNotification,
    context: WorkspaceContext
  ): Promise<Result<NotificationResult, PassNotificationError>> {
    // Validate workspace access
    const accessResult = await validateWorkspaceAccess(context.workspaceId, context.userId);
    if (accessResult.isErr()) {
      return err({ code: 'UNAUTHORIZED', message: 'Invalid workspace access' });
    }

    try {
      // Get device tokens with workspace isolation
      const deviceTokensResult = await this.getDeviceTokens(notification.passId, context.workspaceId);
      if (deviceTokensResult.isErr()) {
        return err(deviceTokensResult.error);
      }
      
      const deviceTokens = deviceTokensResult.value;
      if (deviceTokens.length === 0) {
        return ok({
          success: true,
          message: 'No devices registered for pass',
          sent: 0,
          failed: 0
        });
      }

      // Create APNs notification
      const apnNotification = new apn.Notification({
        topic: process.env.PASS_TYPE_ID, // com.company.passes
        payload: {},
        pushType: 'background',
        priority: 5
      });

      // Send to all registered devices
      const results = await this.apnProvider.send(
        apnNotification,
        deviceTokens
      );

      // Track metrics with workspace context
      await this.trackNotificationMetrics(notification.passId, results, context.workspaceId);

      // Store notification log
      await this.logNotification(notification.passId, {
        workspaceId: context.workspaceId,
        type: 'pass_update',
        deviceCount: deviceTokens.length,
        successCount: results.sent.length,
        failedCount: results.failed.length,
        timestamp: new Date()
      });

      return ok({
        success: true,
        message: 'Notifications sent successfully',
        sent: results.sent.length,
        failed: results.failed.length
      });

    } catch (error) {
      logger.error('Pass notification error', { error, notification, context });
      return err({ code: 'APN_ERROR', message: 'Failed to send notifications' });
    }
  }

  private async getDeviceTokens(
    passId: string,
    workspaceId: string
  ): Promise<Result<string[], PassNotificationError>> {
    try {
      // Get from Redis cache first with workspace prefix
      const cacheKey = `workspace:${workspaceId}:pass:devices:${passId}`;
      const cached = await this.redis.smembers(cacheKey);
      if (cached.length > 0) {
        return ok(cached);
      }

      // Fallback to database with workspace isolation
      const devices = await db.select()
        .from(passDevices)
        .where(
          and(
            eq(passDevices.passId, passId),
            eq(passDevices.workspaceId, workspaceId)
          )
        );
      
      const deviceTokens = devices.map(d => d.pushToken).filter(Boolean);
      
      // Cache for future use with workspace isolation
      if (deviceTokens.length > 0) {
        await this.redis.sadd(cacheKey, ...deviceTokens);
        await this.redis.expire(cacheKey, 3600); // 1 hour
      }

      return ok(deviceTokens);
    } catch (error) {
      logger.error('Failed to get device tokens', { error, passId, workspaceId });
      return err({ code: 'DEVICE_ERROR', message: 'Failed to retrieve device tokens' });
    }
  }

  async handleGooglePassNotification(notification: PassNotification): Promise<NotificationResult> {
    // Google Wallet uses a different update mechanism
    // It requires calling their API to trigger updates
    try {
      const googleApiResponse = await fetch(
        `https://walletobjects.googleapis.com/walletobjects/v1/genericObject/${notification.passId}`,
        {
          method: 'PATCH',
          headers: {
            'Authorization': `Bearer ${await this.getGoogleAccessToken()}`,
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({
            // Update notification flag
            hasUsers: true,
            // This triggers Google to check for updates
            textModulesData: [{
              id: 'update_trigger',
              body: new Date().toISOString()
            }]
          })
        }
      );

      return {
        success: googleApiResponse.ok,
        message: await googleApiResponse.text()
      };

    } catch (error) {
      console.error('Google Wallet notification error:', error);
      throw error;
    }
  }
}
```

#### 1.2 Device Registration Service with Workspace Isolation
```typescript
// packages/backend-lib/src/pass-notifications/DeviceRegistrationService.ts
import { Result, ok, err } from 'neverthrow';
import { db } from '../db';
import { passDevices } from '../db/schema';
import { and, eq } from 'drizzle-orm';
import { validateWorkspaceAccess } from '../workspace/validation';
import { WorkspaceContext } from '../workspace/types';
import { Type } from '@sinclair/typebox';
import { validate } from '../validation';

// TypeBox validation schemas
const DeviceRegistrationSchema = Type.Object({
  passId: Type.String({ minLength: 1, maxLength: 255 }),
  deviceToken: Type.String({ minLength: 1, maxLength: 255 }),
  deviceType: Type.Union([Type.Literal('ios'), Type.Literal('android')]),
  pushToken: Type.String({ minLength: 1, maxLength: 500 }),
  workspaceId: Type.String({ format: 'uuid' })
});

type DeviceRegistration = Type.Static<typeof DeviceRegistrationSchema>;

export class DeviceRegistrationService {
  constructor(
    private redis: Redis,
    private metrics: MetricsService
  ) {}

  async registerDevice(
    registration: DeviceRegistration,
    context: WorkspaceContext
  ): Promise<Result<void, { code: string; message: string }>> {
    // Validate input
    const validationResult = validate(DeviceRegistrationSchema, registration);
    if (validationResult.isErr()) {
      return err({ code: 'VALIDATION_ERROR', message: validationResult.error });
    }

    // Validate workspace access
    const accessResult = await validateWorkspaceAccess(context.workspaceId, context.userId);
    if (accessResult.isErr()) {
      return err({ code: 'UNAUTHORIZED', message: 'Invalid workspace access' });
    }

    // Ensure pass belongs to workspace
    if (registration.workspaceId !== context.workspaceId) {
      return err({ code: 'FORBIDDEN', message: 'Pass does not belong to workspace' });
    }

    const { passId, deviceToken, deviceType, pushToken } = registration;

    try {
      // Store in database with workspace isolation
      await db.insert(passDevices)
        .values({
          passId,
          deviceToken,
          deviceType,
          pushToken,
          workspaceId: context.workspaceId,
          registeredAt: new Date(),
          lastUpdated: new Date()
        })
        .onDuplicateKeyUpdate({
          set: {
            pushToken,
            lastUpdated: new Date()
          }
        });

      // Cache in Redis with workspace namespace
      const cacheKey = `workspace:${context.workspaceId}:pass:devices:${passId}`;
      await this.redis.sadd(cacheKey, pushToken);
      
      // Update device count metric
      const deviceCount = await this.redis.scard(cacheKey);
      this.metrics.passDeviceCount.set({ 
        workspace_id: context.workspaceId,
        pass_id: passId 
      }, deviceCount);

      // Emit device registration event with workspace context
      await this.emitDeviceEvent('device.registered', {
        workspaceId: context.workspaceId,
        passId,
        deviceToken,
        deviceType,
        timestamp: new Date()
      });

      return ok(undefined);
    } catch (error) {
      logger.error('Device registration failed', { error, registration, context });
      return err({ code: 'DATABASE_ERROR', message: 'Failed to register device' });
    }
  }

  async unregisterDevice(
    passId: string,
    deviceToken: string,
    context: WorkspaceContext
  ): Promise<Result<void, { code: string; message: string }>> {
    // Validate workspace access
    const accessResult = await validateWorkspaceAccess(context.workspaceId, context.userId);
    if (accessResult.isErr()) {
      return err({ code: 'UNAUTHORIZED', message: 'Invalid workspace access' });
    }

    try {
      // Remove from database with workspace isolation
      const result = await db.delete(passDevices)
        .where(
          and(
            eq(passDevices.passId, passId),
            eq(passDevices.deviceToken, deviceToken),
            eq(passDevices.workspaceId, context.workspaceId)
          )
        );

      if (result.rowCount === 0) {
        return err({ code: 'NOT_FOUND', message: 'Device not found' });
      }

      // Remove from cache
      const cacheKey = `workspace:${context.workspaceId}:pass:devices:${passId}`;
      const pushToken = await this.getPushToken(passId, deviceToken, context.workspaceId);
      if (pushToken) {
        await this.redis.srem(cacheKey, pushToken);
      }

      // Emit device unregistration event
      await this.emitDeviceEvent('device.unregistered', {
        workspaceId: context.workspaceId,
        passId,
        deviceToken,
        timestamp: new Date()
      });

      return ok(undefined);
    } catch (error) {
      logger.error('Device unregistration failed', { error, passId, deviceToken, context });
      return err({ code: 'DATABASE_ERROR', message: 'Failed to unregister device' });
    }
  }
}
```

### Phase 2: Pass Channel Journey Integration

#### 2.1 Pass Message Templates in Journey Builder
```typescript
// packages/backend-lib/src/channels/pass/templates.ts
import { Type } from '@sinclair/typebox';
import { WorkspaceContext } from '../workspace/types';
import { validateWorkspaceHierarchy } from '../workspace/hierarchy';

// TypeBox schemas for journey validation
const JourneyNodeSchema = Type.Object({
  id: Type.String(),
  type: Type.Union([Type.Literal('condition'), Type.Literal('action'), Type.Literal('delay')]),
  condition: Type.Optional(Type.String()),
  truePath: Type.Optional(Type.String()),
  falsePath: Type.Optional(Type.String()),
  action: Type.Optional(Type.Object({
    channel: Type.String(),
    template: Type.String(),
    data: Type.Record(Type.String(), Type.Any())
  })),
  delay: Type.Optional(Type.String()),
  next: Type.Optional(Type.String())
});

const JourneyTemplateSchema = Type.Object({
  name: Type.String(),
  workspaceId: Type.String({ format: 'uuid' }),
  trigger: Type.Object({
    type: Type.Literal('event'),
    event: Type.String()
  }),
  nodes: Type.Array(JourneyNodeSchema)
});

// Pass message templates for journey builder
export const passMessageTemplates = {
  balanceUpdate: {
    id: 'pass.balance_update',
    name: 'Balance Update',
    channel: 'pass',
    description: 'Notify pass holders when their balance changes',
    schema: Type.Object({
      passId: Type.String(),
      previousBalance: Type.Number(),
      newBalance: Type.Number(),
      changeReason: Type.Optional(Type.String())
    }),
    preview: (data: any) => `Balance updated: $${data.newBalance}`
  },
  
  expiryReminder: {
    id: 'pass.expiry_reminder',
    name: 'Expiry Reminder',
    channel: 'pass',
    description: 'Remind users about expiring passes',
    schema: Type.Object({
      passId: Type.String(),
      expiryDate: Type.String({ format: 'date-time' }),
      daysUntilExpiry: Type.Number(),
      currentBalance: Type.Number()
    }),
    preview: (data: any) => `Pass expires in ${data.daysUntilExpiry} days`
  },
  
  redemptionNotification: {
    id: 'pass.redemption',
    name: 'Redemption Notification',
    channel: 'pass',
    description: 'Notify when pass is redeemed',
    schema: Type.Object({
      passId: Type.String(),
      redeemedAmount: Type.Number(),
      remainingBalance: Type.Number(),
      merchantName: Type.String(),
      location: Type.Optional(Type.String())
    }),
    preview: (data: any) => `Redeemed $${data.redeemedAmount} at ${data.merchantName}`
  }
};

// Register templates with journey builder
export function registerPassTemplates(journeyBuilder: JourneyBuilder) {
  Object.values(passMessageTemplates).forEach(template => {
    journeyBuilder.registerMessageTemplate(template);
  });
}

// Example journey using pass channel
export const examplePassJourney = {
  name: 'Gift Card Engagement',
  trigger: {
    type: 'event',
    event: 'pass.issued'
  },
  nodes: [
    {
      id: 'wait_for_activity',
      type: 'delay',
      delay: '7d',
      next: 'check_balance'
    },
    {
      id: 'check_balance',
      type: 'condition',
      condition: 'user.pass_balance > 0 && user.pass_last_used == null',
      truePath: 'send_reminder',
      falsePath: 'end'
    },
    {
      id: 'send_reminder',
      type: 'message',
      channel: 'pass',
      template: 'pass.balance_update',
      data: {
        passId: '{{user.pass_id}}',
        newBalance: '{{user.pass_balance}}',
        changeReason: 'First use reminder'
      },
      next: 'end'
    }
  ]
};
      {
        id: 'track_success',
        type: 'action',
        action: {
          type: 'track_event',
          event: 'pass.notification_sent',
          properties: {
            passId: '{{event.passId}}',
            notificationType: 'balance_update'
          }
        },
        next: 'end'
      }
    ]
  };

  static readonly REDEMPTION_JOURNEY = {
    name: 'Pass Redemption Notification',
    trigger: {
      type: 'event',
      event: 'pass.redeemed'
    },
    nodes: [
      {
        id: 'update_pass',
        type: 'action',
        action: {
          channel: 'apple_wallet_pass',
          template: 'redemption',
          data: {
            passId: '{{event.passId}}',
            remainingBalance: '{{event.remainingBalance}}',
            redeemedAmount: '{{event.redeemedAmount}}',
            location: '{{event.location}}'
          }
        },
        next: 'send_receipt'
      },
      {
        id: 'send_receipt',
        type: 'delay',
        delay: '1m', // Wait 1 minute
        next: 'email_receipt'
      },
      {
        id: 'email_receipt',
        type: 'action',
        action: {
          channel: 'email',
          template: 'redemption_receipt',
          to: '{{user.email}}',
          data: {
            redemptionDetails: '{{event}}'
          }
        },
        next: 'end'
      }
    ]
  };

  static async createJourneyForWorkspace(
    dittofeed: DittofeedClient,
    context: WorkspaceContext,
    journeyTemplate: any
  ): Promise<Result<string, { code: string; message: string }>> {
    // Validate template with TypeBox
    const validationResult = validate(JourneyTemplateSchema, {
      ...journeyTemplate,
      workspaceId: context.workspaceId
    });
    
    if (validationResult.isErr()) {
      return err({ code: 'VALIDATION_ERROR', message: validationResult.error });
    }

    // Check workspace permissions
    if (context.role !== 'owner' && context.role !== 'manager') {
      return err({ code: 'FORBIDDEN', message: 'Insufficient permissions to create journey' });
    }

    try {
      const response = await dittofeed.createJourney({
        workspaceId: context.workspaceId,
        journey: {
          ...journeyTemplate,
          name: `${journeyTemplate.name} - ${context.workspaceId}`,
          enabled: true,
          metadata: {
            createdBy: context.userId,
            workspaceType: context.workspaceType
          }
        }
      });

      logger.info('Journey created', { 
        journeyId: response.journeyId,
        workspaceId: context.workspaceId,
        template: journeyTemplate.name 
      });

      return ok(response.journeyId);
    } catch (error) {
      logger.error('Failed to create journey', { error, context, template: journeyTemplate });
      return err({ code: 'API_ERROR', message: 'Failed to create journey' });
    }
  }
}
```

#### 2.2 Event Bridge for Pass Updates with Workspace Routing
```typescript
// packages/worker/src/pass-events/EventBridge.ts
import { Kafka } from 'kafkajs';
import { DittofeedClient } from '@dittofeed/sdk';
import { Redis } from 'ioredis';
import { db } from '@backend-lib/db';
import { workspaces, giftCards } from '@backend-lib/db/schema';
import { eq } from 'drizzle-orm';
import { logger } from '@backend-lib/telemetry';
import { Result, ok, err } from 'neverthrow';

interface PassEvent {
  passId: string;
  businessId: string;
  userId?: string;
  timestamp: string;
  [key: string]: any;
}

export class PassEventBridge {
  private consumer: Kafka.Consumer;

  constructor(
    private kafka: Kafka,
    private dittofeed: DittofeedClient,
    private redis: Redis
  ) {
    this.consumer = kafka.consumer({ 
      groupId: 'dittofeed-pass-bridge',
      sessionTimeout: 30000,
      heartbeatInterval: 3000
    });
  }

  async start() {
    await this.consumer.connect();
    await this.consumer.subscribe({
      topics: [
        'pass.created',
        'pass.updated',
        'pass.balance_changed',
        'pass.redeemed'
      ]
    });

    await this.consumer.run({
      eachMessage: async ({ topic, message }) => {
        const event = JSON.parse(message.value.toString());
        await this.bridgeEventToDittofeed(topic, event);
      }
    });
  }

  private async bridgeEventToDittofeed(
    topic: string, 
    event: PassEvent
  ): Promise<Result<void, { code: string; message: string }>> {
    try {
      // Get workspace ID with caching
      const workspaceResult = await this.getWorkspaceId(event.businessId);
      if (workspaceResult.isErr()) {
        logger.warn('No Dittofeed workspace for business', { 
          businessId: event.businessId,
          error: workspaceResult.error 
        });
        return err(workspaceResult.error);
      }

      const workspaceId = workspaceResult.value;

      // Validate pass belongs to workspace
      const passValidation = await this.validatePassWorkspace(event.passId, workspaceId);
      if (passValidation.isErr()) {
        return err(passValidation.error);
      }

      // Map pass events to Dittofeed events
      const dittofeedEvent = this.mapPassEvent(topic, event);

      // Add workspace context to event properties
      dittofeedEvent.properties.workspaceId = workspaceId;
      dittofeedEvent.properties.sourceSystem = 'passkit';

      // Send to Dittofeed with workspace isolation
      await this.dittofeed.track({
        workspaceId,
        userId: event.userId || `pass_${event.passId}`,
        event: dittofeedEvent.name,
        properties: dittofeedEvent.properties,
        timestamp: event.timestamp || new Date().toISOString(),
        context: {
          ip: '0.0.0.0', // Internal event
          library: {
            name: 'pass-event-bridge',
            version: '1.0.0'
          }
        }
      });

      // Track bridged events with workspace metric
      await this.redis.hincrby(`metrics:workspace:${workspaceId}:bridged_events`, topic, 1);

      return ok(undefined);
    } catch (error) {
      logger.error('Failed to bridge event', { topic, event, error });
      return err({ code: 'BRIDGE_ERROR', message: 'Failed to bridge event to Dittofeed' });
    }
  }

  private async getWorkspaceId(businessId: string): Promise<Result<string, { code: string; message: string }>> {
    // Check cache first
    const cacheKey = `business:workspace:${businessId}`;
    const cached = await this.redis.get(cacheKey);
    if (cached) {
      return ok(cached);
    }

    // Query database
    const workspace = await db.select()
      .from(workspaces)
      .where(eq(workspaces.businessId, businessId))
      .limit(1);

    if (!workspace.length) {
      return err({ code: 'NOT_FOUND', message: 'Workspace not found for business' });
    }

    // Cache for future use
    await this.redis.set(cacheKey, workspace[0].id, 'EX', 3600);
    return ok(workspace[0].id);
  }

  private async validatePassWorkspace(
    passId: string,
    workspaceId: string
  ): Promise<Result<void, { code: string; message: string }>> {
    const pass = await db.select()
      .from(giftCards)
      .where(eq(giftCards.passId, passId))
      .limit(1);

    if (!pass.length) {
      return err({ code: 'NOT_FOUND', message: 'Pass not found' });
    }

    if (pass[0].workspaceId !== workspaceId) {
      return err({ code: 'FORBIDDEN', message: 'Pass does not belong to workspace' });
    }

    return ok(undefined);
  }

  private mapPassEvent(topic: string, event: any): DittofeedEvent {
    switch (topic) {
      case 'pass.created':
        return {
          name: 'Pass Created',
          properties: {
            passId: event.passId,
            templateId: event.templateId,
            initialBalance: event.data?.balance,
            recipientName: event.data?.recipientName
          }
        };

      case 'pass.balance_changed':
        return {
          name: 'pass.balance_updated',
          properties: {
            passId: event.passId,
            previousBalance: event.previousBalance,
            newBalance: event.newBalance,
            changeAmount: event.changeAmount,
            changeReason: event.reason
          }
        };

      case 'pass.redeemed':
        return {
          name: 'pass.redeemed',
          properties: {
            passId: event.passId,
            redeemedAmount: event.amount,
            remainingBalance: event.remainingBalance,
            location: event.location,
            merchantId: event.merchantId
          }
        };

      default:
        return {
          name: topic,
          properties: event
        };
    }
  }
}
```

### Phase 3: Pass Channel Integration in Message Delivery

#### 3.1 Pass Channel in Message Delivery Pipeline
```typescript
// packages/worker/src/message-delivery/channels/pass.ts
import { MessageDeliveryHandler } from '../types';
import { PassChannelProvider } from '@backend-lib/channels/pass';
import { db } from '@backend-lib/db';
import { passDevices, userProperties } from '@backend-lib/db/schema';
import { eq, and } from 'drizzle-orm';

export const passDeliveryHandler: MessageDeliveryHandler = {
  channel: 'pass',
  
  async deliver(message, channelConfig) {
    const provider = new PassChannelProvider();
    await provider.initialize(channelConfig);
    
    // Get pass ID from user properties
    const passIdProp = await db.select()
      .from(userProperties)
      .where(
        and(
          eq(userProperties.userId, message.userId),
          eq(userProperties.workspaceId, message.workspaceId),
          eq(userProperties.key, 'pass_id')
        )
      )
      .limit(1);
    
    if (!passIdProp.length) {
      return {
        status: 'failed',
        error: 'No pass ID found for user'
      };
    }
    
    const result = await provider.send({
      to: passIdProp[0].value,
      template: message.template,
      workspaceId: message.workspaceId,
      userId: message.userId
    });
    
    if (result.isOk()) {
      return {
        status: 'delivered',
        messageId: result.value.messageId,
        deliveredAt: new Date()
      };
    }
    
    return {
      status: 'failed',
      error: result.error.message
    };
  },
  
  async validateUserHasChannel(userId, workspaceId) {
    const devices = await db.select()
      .from(passDevices)
      .where(
        and(
          eq(passDevices.userId, userId),
          eq(passDevices.workspaceId, workspaceId),
          eq(passDevices.unregisteredAt, null)
        )
      )
      .limit(1);
    
    return devices.length > 0;
  }
};

// Register handler with message delivery system
export function registerPassChannel(deliverySystem: MessageDeliverySystem) {
  deliverySystem.registerChannel('pass', passDeliveryHandler);
}
```
    schema: {
      body: DittofeedWebhookPayloadSchema,
      response: {
        200: Type.Object({ success: Type.Boolean() }),
        401: Type.Object({ error: Type.String() }),
        500: Type.Object({ error: Type.String() })
      }
    },
    preHandler: async (request, reply) => {
      // Verify webhook signature
      const signature = request.headers['x-dittofeed-signature'];
      const isValid = await validateWebhookSignature(
        request.body,
        signature,
        process.env.DITTOFEED_WEBHOOK_SECRET!
      );
      
      if (!isValid) {
        reply.code(401).send({ error: 'Invalid signature' });
        return;
      }
    }
  }, async (request, reply) => {
    const payload = request.body;
    
    try {
      // Handle pass notification actions
      if (payload.action.channel === 'apple_wallet_pass' || 
          payload.action.channel === 'google_wallet_pass') {
        
        const result = await handlePassNotificationAction(payload, passNotificationService);
        
        if (result.isErr()) {
          logger.error('Pass notification failed', { error: result.error, payload });
          return reply.code(500).send({ error: result.error.message });
        }
        
        return reply.send({ success: true });
      }

      // Handle other actions
      return await handleStandardAction(payload);
      
    } catch (error) {
      logger.error('Webhook error', { error, payload });
      return reply.code(500).send({ error: 'Internal server error' });
    }
  });
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const payload: DittofeedWebhookPayload = await req.json();
    
    // Verify webhook signature
    const signature = req.headers.get('x-dittofeed-signature');
    if (!await verifyWebhookSignature(payload, signature)) {
      return new Response('Invalid signature', { status: 401 });
    }

    // Handle pass notification actions
    if (payload.action.channel === 'apple_wallet_pass' || 
        payload.action.channel === 'google_wallet_pass') {
      
      return await handlePassNotificationAction(payload);
    }

    // Handle other actions (existing code)
    return await handleStandardAction(payload);

  } catch (error) {
    console.error('Webhook error:', error);
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});

async function handlePassNotificationAction(
  payload: DittofeedWebhookPayload,
  passNotificationService: PassNotificationService
): Promise<Result<void, { code: string; message: string }>> {
  const { action } = payload;
  const passId = action.data.passId;

  // Log the notification attempt with workspace isolation
  await db.insert(marketingPushNotifications).values({
    workspaceId: payload.workspaceId,
    journeyId: payload.journeyId,
    userId: payload.userId,
    passId: passId,
    notificationType: action.type,
    channel: action.channel,
    payload: action.data,
    sentAt: new Date()
  });

  // Trigger pass update via PassKit Generator Service
  const updateResult = await passNotificationService.triggerPassUpdate({
    workspaceId: payload.workspaceId,
    passId: passId,
    updates: action.data,
    notifyDevices: true
  });

  if (updateResult.isErr()) {
    // Update notification status
    await db.update(marketingPushNotifications)
      .set({
        deliveryStatus: 'failed',
        errorMessage: updateResult.error.message,
        updatedAt: new Date()
      })
      .where(
        and(
          eq(marketingPushNotifications.journeyId, payload.journeyId),
          eq(marketingPushNotifications.passId, passId)
        )
      );
    
    return err(updateResult.error);
  }

  // Update notification status to delivered
  await db.update(marketingPushNotifications)
    .set({
      deliveryStatus: 'delivered',
      deliveredAt: new Date(),
      updatedAt: new Date()
    })
    .where(
      and(
        eq(marketingPushNotifications.journeyId, payload.journeyId),
        eq(marketingPushNotifications.passId, passId)
      )
    );

  // Track success event
  await trackEvent({
    workspaceId: payload.workspaceId,
    eventType: 'pass_notification_delivered',
    userId: payload.userId,
    properties: {
      passId,
      channel: action.channel,
      journeyId: payload.journeyId
    }
  });

  return ok(undefined);
}
```

### Phase 4: Integrating Pass Channel into Existing Dittofeed UI

#### 4.1 Add Pass Channel to Existing Channel List
```typescript
// packages/dashboard/src/pages/channels/index.tsx - Update existing file
import { CreditCard } from 'lucide-react';

// Add to CHANNEL_DEFINITIONS
export const CHANNEL_DEFINITIONS = {
  email: {
    id: 'email',
    name: 'Email',
    icon: Mail,
    description: 'Send emails via SMTP or email service providers',
    configComponent: EmailChannelConfig
  },
  sms: {
    id: 'sms',
    name: 'SMS',
    icon: MessageSquare,
    description: 'Send text messages via Twilio or other providers',
    configComponent: SmsChannelConfig
  },
  webhook: {
    id: 'webhook',
    name: 'Webhook',
    icon: Webhook,
    description: 'Send data to external endpoints',
    configComponent: WebhookChannelConfig
  },
  pass: {
    id: 'pass',
    name: 'Digital Pass',
    icon: CreditCard,
    description: 'Update Apple Wallet and Google Wallet passes',
    configComponent: PassChannelConfig,
    beta: true // Mark as beta feature
  }
};
```

#### 4.2 Pass Channel Configuration Component
```typescript
// packages/dashboard/src/components/channels/PassChannelConfig.tsx
import React, { useState } from 'react';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { Apple, Wallet } from 'lucide-react';
import { useWorkspace } from '@/hooks/useWorkspace';
import { usePermissions } from '@/hooks/usePermissions';

interface PassChannelConfigProps {
  channel?: any;
  onSave: (config: any) => void;
}

export function PassChannelConfig({ channel, onSave }: ChannelConfigProps) {
  const [config, setConfig] = useState({
    provider: channel?.config?.provider || 'apple_wallet',
    appleConfig: channel?.config?.appleConfig || {},
    googleConfig: channel?.config?.googleConfig || {}
  });
  
  const { workspace } = useWorkspace();
  const { can } = usePermissions();
  
  return (
    <div className="space-y-6">
      <div>
        <Label>Pass Provider</Label>
        <Select 
          value={config.provider} 
          onValueChange={(value) => setConfig({ ...config, provider: value })}
        >
          <SelectTrigger>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="apple_wallet">
              <div className="flex items-center gap-2">
                <Apple className="h-4 w-4" />
                Apple Wallet
              </div>
            </SelectItem>
            <SelectItem value="google_wallet">
              <div className="flex items-center gap-2">
                <Wallet className="h-4 w-4" />
                Google Wallet
              </div>
            </SelectItem>
          </SelectContent>
        </Select>
      </div>
      
      {config.provider === 'apple_wallet' && (
        <AppleWalletConfig 
          config={config.appleConfig}
          onChange={(appleConfig) => setConfig({ ...config, appleConfig })}
        />
      )}
      
      {config.provider === 'google_wallet' && (
        <GoogleWalletConfig
          config={config.googleConfig}
          onChange={(googleConfig) => setConfig({ ...config, googleConfig })}
        />
      )}
      
      <Button 
        onClick={() => onSave(config)}
        disabled={!can('channel:update', workspace)}
      >
        Save Channel Configuration
      </Button>
    </div>
  );
}

// Add to existing channel types in dashboard
export const CHANNEL_TYPES = [
  { id: 'email', name: 'Email', icon: Mail },
  { id: 'sms', name: 'SMS', icon: MessageSquare },
  { id: 'webhook', name: 'Webhook', icon: Webhook },
  { id: 'pass', name: 'Digital Pass', icon: CreditCard } // New channel type
] as const;
    {
      id: 'low_balance_reminder',
      name: 'Low Balance Reminders',
      description: 'Send reminders when gift card balance falls below threshold',
      icon: TrendingUp,
      triggers: ['Balance < $10', 'Balance < 20%', 'Custom threshold'],
      benefits: ['Drive redemptions', 'Prevent expiry', 'Increase usage']
    },
    {
      id: 'birthday_reload',
      name: 'Birthday Reload Campaign',
      description: 'Automatically add bonus balance on customer birthdays',
      icon: Gift,
      triggers: ['Customer birthday', 'Anniversary', 'Special dates'],
      benefits: ['Customer loyalty', 'Increased LTV', 'Personal touch']
    },
    {
      id: 'win_back',
      name: 'Win-Back Campaign',
      description: 'Re-engage customers with unused gift cards',
      icon: CreditCard,
      triggers: ['No activity 30 days', 'No activity 60 days', 'Custom period'],
      benefits: ['Reduce breakage', 'Reactivate customers', 'Clear liability']
    }
  ];

  const activateTemplate = useMutation({
    mutationFn: async (templateId: string) => {
      if (!canCreateJourneys) {
        throw new Error('Insufficient permissions to create journeys');
      }

      const response = await api.post('/api/v1/pass-journeys/activate', {
        workspaceId,
        templateId,
        config: getTemplateConfig(templateId)
      });

      return response.data;
    },
    onSuccess: (data) => {
      toast({
        title: 'Journey Activated',
        description: 'Pass notification journey is now active',
        variant: 'success'
      });
      
      // Invalidate queries to refresh journey list
      queryClient.invalidateQueries({ queryKey: ['journeys', workspaceId] });
    },
    onError: (error) => {
      toast({
        title: 'Activation Failed',
        description: error.message,
        variant: 'destructive'
      });
    }
  });

  const getTemplateConfig = (templateId: string) => {
    switch (templateId) {
      case 'balance_update':
        return {
          notifyOnRedemption: true,
          notifyOnReload: true,
          notifyOnAdjustment: true,
          minimumChangeAmount: 0
        };
      case 'low_balance_reminder':
        return {
          thresholdType: 'fixed',
          thresholdValue: 10,
          reminderFrequency: 'once',
          includeSuggestions: true
        };
      default:
        return {};
    }
  };

  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-lg font-semibold mb-1">Pass Notification Journeys</h3>
        <p className="text-sm text-muted-foreground">
          Automated campaigns for Apple and Google Wallet passes
        </p>
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        {templates.map((template) => {
          const Icon = template.icon;
          return (
            <Card 
              key={template.id}
              className="cursor-pointer hover:shadow-lg transition-shadow"
              onClick={() => setSelectedTemplate(template.id)}
            >
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <Icon className="h-5 w-5 text-primary" />
                  {template.name}
                </CardTitle>
                <CardDescription>{template.description}</CardDescription>
              </CardHeader>
              <CardContent className="space-y-4">
                <div>
                  <p className="text-sm font-medium mb-2">Triggers:</p>
                  <div className="flex flex-wrap gap-2">
                    {template.triggers.map((trigger) => (
                      <Badge key={trigger} variant="secondary">
                        {trigger}
                      </Badge>
                    ))}
                  </div>
                </div>
                <div>
                  <p className="text-sm font-medium mb-2">Benefits:</p>
                  <ul className="text-sm text-muted-foreground space-y-1">
                    {template.benefits.map((benefit) => (
                      <li key={benefit}>• {benefit}</li>
                    ))}
                  </ul>
                </div>
                <Button 
                  className="w-full"
                  onClick={(e) => {
                    e.stopPropagation();
                    activateTemplate.mutate(template.id);
                  }}
                  disabled={activateTemplate.isLoading || !canCreateJourneys}
                  title={!canCreateJourneys ? 'You need manager or owner permissions' : ''}
                >
                  {activateTemplate.isLoading ? 'Activating...' : 'Activate Journey'}
                </Button>
              </CardContent>
            </Card>
          );
        })}
      </div>
    </div>
  );
}
```

### Phase 5: Database Schema for Pass Channel

#### 5.1 Extend Existing Channel Tables
```typescript
// packages/backend-lib/src/db/schema/channels.ts - Add to existing schema
import { pgTable, text, timestamp, integer, boolean, uuid, jsonb, index, uniqueIndex } from 'drizzle-orm/pg-core';
import { relations } from 'drizzle-orm';
import { workspaces } from './workspaces';
import { giftCards } from './gift-cards';

// Add 'pass' to existing channel types enum
export const channelTypes = pgEnum('channel_type', ['email', 'sms', 'webhook', 'push', 'pass']);

// Extend existing messages table to support pass channel
// No changes needed - existing schema supports any channel type

// Pass-specific user properties stored in existing user_properties table
// Examples: pass_id, pass_balance, pass_last_used, pass_device_count

// Pass device registry - new table for pass-specific data
export const passDevices = pgTable('pass_devices', {
  id: uuid('id').defaultRandom().primaryKey(),
  workspaceId: uuid('workspace_id').references(() => workspaces.id, { onDelete: 'cascade' }).notNull(),
  userId: text('user_id').notNull(), // Dittofeed user ID
  passId: text('pass_id').notNull(),
  deviceToken: text('device_token').notNull(),
  deviceType: text('device_type', { enum: ['ios', 'android'] }).notNull(),
  pushToken: text('push_token').notNull(),
  registeredAt: timestamp('registered_at', { withTimezone: true }).defaultNow().notNull(),
  lastActiveAt: timestamp('last_active_at', { withTimezone: true }),
  unregisteredAt: timestamp('unregistered_at', { withTimezone: true })
}, (table) => {
  return {
    uniqueDevice: uniqueIndex('idx_unique_pass_device')
      .on(table.passId, table.deviceToken),
    userPassIdx: index('idx_user_pass')
      .on(table.userId, table.passId),
    workspaceIdx: index('idx_pass_devices_workspace')
      .on(table.workspaceId)
  };
});

// Pass channel configuration stored in existing channel_configs table
// Schema already supports JSON config for any channel type

// Example channel config for pass:
// {
//   "type": "pass",
//   "provider": "apple_wallet",
//   "appleConfig": {
//     "keyPath": "/path/to/key.p8",
//     "keyId": "ABC123",
//     "teamId": "TEAM123",
//     "passTypeId": "pass.com.example"
//   }
// }

// Pass events tracked in existing events table
// Event types: pass.issued, pass.updated, pass.redeemed, pass.expired

// User computed properties for pass engagement
export const passComputedProperties = {
  pass_count: {
    type: 'number',
    query: `COUNT(DISTINCT pass_id) FROM user_properties WHERE key = 'pass_id'`
  },
  total_pass_balance: {
    type: 'number', 
    query: `SUM(CAST(value AS DECIMAL)) FROM user_properties WHERE key = 'pass_balance'`
  },
  days_since_last_pass_use: {
    type: 'number',
    query: `DATEDIFF(NOW(), MAX(created_at)) FROM events WHERE type = 'pass.redeemed'`
  },
  pass_engagement_score: {
    type: 'number',
    query: `(redemption_count * 10 + update_view_count * 2) / NULLIF(pass_count, 0)`
  }
};

// Pass devices with workspace isolation
export const passDevices = pgTable('pass_devices', {
  id: uuid('id').defaultRandom().primaryKey(),
  workspaceId: uuid('workspace_id').references(() => workspaces.id, { onDelete: 'cascade' }).notNull(),
  passId: text('pass_id').notNull(),
  deviceToken: text('device_token').notNull(),
  deviceType: text('device_type', { enum: ['ios', 'android'] }).notNull(),
  pushToken: text('push_token').notNull(),
  registeredAt: timestamp('registered_at', { withTimezone: true }).defaultNow().notNull(),
  lastUpdated: timestamp('last_updated', { withTimezone: true }).defaultNow().notNull(),
  lastActiveAt: timestamp('last_active_at', { withTimezone: true })
}, (table) => {
  return {
    uniqueDevice: uniqueIndex('idx_unique_device')
      .on(table.passId, table.deviceToken),
    workspaceIdx: index('idx_devices_workspace')
      .on(table.workspaceId),
    pushTokenIdx: index('idx_devices_push_token')
      .on(table.pushToken)
  };
});

// Relations
export const marketingPushNotificationsRelations = relations(marketingPushNotifications, ({ one }) => ({
  workspace: one(workspaces, {
    fields: [marketingPushNotifications.workspaceId],
    references: [workspaces.id]
  }),
  giftCard: one(giftCards, {
    fields: [marketingPushNotifications.passId],
    references: [giftCards.passId]
  })
}));

export const passJourneyTemplatesRelations = relations(passJourneyTemplates, ({ one }) => ({
  workspace: one(workspaces, {
    fields: [passJourneyTemplates.workspaceId],
    references: [workspaces.id]
  })
}));

export const passNotificationMetricsRelations = relations(passNotificationMetrics, ({ one }) => ({
  workspace: one(workspaces, {
    fields: [passNotificationMetrics.workspaceId],
    references: [workspaces.id]
  })
}));

export const passDevicesRelations = relations(passDevices, ({ one }) => ({
  workspace: one(workspaces, {
    fields: [passDevices.workspaceId],
    references: [workspaces.id]
  })
}));
```

#### 5.2 Migration Generation
```bash
# Generate migration from schema
cd packages/backend-lib
yarn drizzle-kit generate:pg

# The generated migration will be in drizzle/0001_pass_notifications.sql
```

#### 5.3 Repository Layer with Workspace Isolation
```typescript
// packages/backend-lib/src/repositories/pass-notifications.ts
import { db } from '../db';
import { passDevices, passNotificationMetrics, passJourneyTemplates } from '../db/schema';
import { and, eq, gte, sql } from 'drizzle-orm';
import { WorkspaceContext } from '../workspace/types';
import { Result, ok, err } from 'neverthrow';

export class PassNotificationRepository {
  async getDevicesForPass(
    passId: string,
    workspaceId: string
  ): Promise<Result<typeof passDevices.$inferSelect[], Error>> {
    try {
      const devices = await db.select()
        .from(passDevices)
        .where(
          and(
            eq(passDevices.passId, passId),
            eq(passDevices.workspaceId, workspaceId)
          )
        );
      return ok(devices);
    } catch (error) {
      return err(error as Error);
    }
  }

  async updateNotificationMetrics(
    workspaceId: string,
    passId: string,
    notificationType: string,
    updates: { sent?: number; delivered?: number; failed?: number }
  ): Promise<Result<void, Error>> {
    try {
      await db.insert(passNotificationMetrics)
        .values({
          workspaceId,
          passId,
          notificationType,
          sentCount: updates.sent || 0,
          deliveredCount: updates.delivered || 0,
          failedCount: updates.failed || 0,
          lastSentAt: new Date()
        })
        .onDuplicateKeyUpdate({
          set: {
            sentCount: sql`${passNotificationMetrics.sentCount} + ${updates.sent || 0}`,
            deliveredCount: sql`${passNotificationMetrics.deliveredCount} + ${updates.delivered || 0}`,
            failedCount: sql`${passNotificationMetrics.failedCount} + ${updates.failed || 0}`,
            lastSentAt: new Date(),
            updatedAt: new Date()
          }
        });
      return ok(undefined);
    } catch (error) {
      return err(error as Error);
    }
  }

  async getActiveJourneyTemplates(
    workspaceId: string
  ): Promise<Result<typeof passJourneyTemplates.$inferSelect[], Error>> {
    try {
      const templates = await db.select()
        .from(passJourneyTemplates)
        .where(
          and(
            eq(passJourneyTemplates.workspaceId, workspaceId),
            eq(passJourneyTemplates.enabled, true)
          )
        );
      return ok(templates);
    } catch (error) {
      return err(error as Error);
    }
  }
}
```

### Phase 6: Testing and Monitoring

#### 6.1 Integration Tests with Workspace Context
```typescript
// packages/backend-lib/src/pass-notifications/__tests__/PassNotificationProvider.test.ts
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { PassNotificationProvider } from '../PassNotificationProvider';
import { DittofeedClient } from '@dittofeed/sdk';
import { WorkspaceContext } from '../../workspace/types';
import { db } from '../../db';
import { workspaces } from '../../db/schema';

describe('Pass Notification Integration', () => {
  let provider: PassNotificationProvider;
  let mockContext: WorkspaceContext;
  
  beforeEach(() => {
    provider = new PassNotificationProvider(
      mockDittofeed,
      mockRedis,
      mockKafka
    );
    
    mockContext = {
      workspaceId: 'test-workspace-id',
      userId: 'test-user-id',
      role: 'owner',
      workspaceType: 'Root'
    };
    
    // Mock workspace exists
    vi.spyOn(db.select(), 'from').mockResolvedValue([{
      id: mockContext.workspaceId,
      name: 'Test Workspace'
    }]);
  });

  it('should register pass notification channels with workspace', async () => {
    const result = await provider.registerProvider(mockContext.workspaceId);
    
    expect(result.isOk()).toBe(true);
    expect(mockDittofeed.registerNotificationChannel).toHaveBeenCalledWith(
      expect.objectContaining({
        workspaceId: mockContext.workspaceId,
        id: 'apple_wallet_pass',
        type: 'custom',
        config: expect.objectContaining({
          requiresWorkspaceContext: true
        })
      })
    );
  });

  it('should reject registration for non-existent workspace', async () => {
    vi.spyOn(db.select(), 'from').mockResolvedValue([]);
    
    const result = await provider.registerProvider('invalid-workspace');
    
    expect(result.isErr()).toBe(true);
    expect(result._unsafeUnwrapErr().code).toBe('WORKSPACE_NOT_FOUND');
  });

  it('should handle pass balance update events with workspace validation', async () => {
    const event = {
      passId: 'pass_123',
      businessId: 'business_123',
      previousBalance: 100,
      newBalance: 75,
      changeAmount: -25,
      timestamp: new Date().toISOString()
    };
    
    // Mock workspace lookup
    vi.spyOn(eventBridge, 'getWorkspaceId').mockResolvedValue(ok(mockContext.workspaceId));
    vi.spyOn(eventBridge, 'validatePassWorkspace').mockResolvedValue(ok(undefined));
    
    const result = await eventBridge.bridgeEventToDittofeed('pass.balance_changed', event);
    
    expect(result.isOk()).toBe(true);
    expect(mockDittofeed.track).toHaveBeenCalledWith({
      workspaceId: mockContext.workspaceId,
      event: 'pass.balance_updated',
      properties: expect.objectContaining({
        workspaceId: mockContext.workspaceId,
        passId: 'pass_123',
        newBalance: 75,
        sourceSystem: 'passkit'
      })
    });
  });

  it('should prevent cross-workspace pass access', async () => {
    const notification = {
      passId: 'pass_123',
      type: 'balance_update'
    };
    
    // Mock pass belongs to different workspace
    vi.spyOn(provider, 'validatePassWorkspace').mockResolvedValue(
      err({ code: 'FORBIDDEN', message: 'Pass does not belong to workspace' })
    );
    
    const result = await provider.handlePassNotification(notification, mockContext);
    
    expect(result.isErr()).toBe(true);
    expect(result._unsafeUnwrapErr().code).toBe('FORBIDDEN');
  });

  it('should send APNs notification with workspace-scoped devices', async () => {
    const notification = {
      passId: 'pass_123',
      type: 'balance_update'
    };
    
    const cacheKey = `workspace:${mockContext.workspaceId}:pass:devices:pass_123`;
    mockRedis.smembers.mockResolvedValue(['device_token_1', 'device_token_2']);
    
    const result = await provider.handlePassNotification(notification, mockContext);
    
    expect(result.isOk()).toBe(true);
    expect(mockRedis.smembers).toHaveBeenCalledWith(cacheKey);
    expect(result.value.sent).toBe(2);
  });
});
```

#### 6.2 End-to-End Test Scenarios
```typescript
// packages/backend-lib/src/pass-notifications/__tests__/e2e.test.ts
import { describe, it, expect } from 'vitest';
import { setupTestWorkspace } from '../../test-utils';
import { PassNotificationService } from '../PassNotificationService';

describe('Pass Notifications E2E', () => {
  it('should complete full notification flow with workspace isolation', async () => {
    // Setup test workspace hierarchy
    const { rootWorkspace, childWorkspace } = await setupTestWorkspace();
    
    // Create pass in child workspace
    const pass = await createTestPass(childWorkspace.id);
    
    // Register device
    const deviceResult = await deviceService.registerDevice({
      passId: pass.id,
      deviceToken: 'test-device-123',
      deviceType: 'ios',
      pushToken: 'push-token-123',
      workspaceId: childWorkspace.id
    }, {
      workspaceId: childWorkspace.id,
      userId: 'test-user',
      role: 'member'
    });
    
    expect(deviceResult.isOk()).toBe(true);
    
    // Trigger balance update event
    await kafka.producer().send({
      topic: 'pass.balance_changed',
      messages: [{
        value: JSON.stringify({
          passId: pass.id,
          businessId: childWorkspace.businessId,
          previousBalance: 100,
          newBalance: 75,
          timestamp: new Date().toISOString()
        })
      }]
    });
    
    // Verify notification sent only to child workspace devices
    const notifications = await getNotificationsForWorkspace(childWorkspace.id);
    expect(notifications).toHaveLength(1);
    expect(notifications[0].passId).toBe(pass.id);
    
    // Verify root workspace didn't receive notification
    const rootNotifications = await getNotificationsForWorkspace(rootWorkspace.id);
    expect(rootNotifications).toHaveLength(0);
  });
});
```

#### 6.3 Monitoring and Observability
```typescript
// packages/backend-lib/src/pass-notifications/metrics.ts
import { Counter, Histogram, register } from 'prom-client';
import { logger } from '../telemetry';

// Notification metrics
export const passNotificationsSent = new Counter({
  name: 'pass_notifications_sent_total',
  help: 'Total number of pass notifications sent',
  labelNames: ['workspace_id', 'channel', 'notification_type']
});

export const passNotificationDeliveryTime = new Histogram({
  name: 'pass_notification_delivery_duration_seconds',
  help: 'Time taken to deliver pass notifications',
  labelNames: ['workspace_id', 'channel'],
  buckets: [0.1, 0.5, 1, 2, 5, 10]
});

export const passDeviceRegistrations = new Counter({
  name: 'pass_device_registrations_total',
  help: 'Total number of pass device registrations',
  labelNames: ['workspace_id', 'device_type']
});

// Register all metrics
register.registerMetric(passNotificationsSent);
register.registerMetric(passNotificationDeliveryTime);
register.registerMetric(passDeviceRegistrations);

// Monitoring queries for ClickHouse
export const monitoringQueries = {
  // Pass notification performance by workspace
  notificationPerformance: `
    SELECT 
      workspace_id,
      toStartOfHour(sent_at) as hour,
      notification_type,
      channel,
      count() as total_sent,
      countIf(delivery_status = 'delivered') as delivered,
      countIf(delivery_status = 'failed') as failed,
      avg(dateDiff('second', sent_at, delivered_at)) as avg_delivery_seconds
    FROM marketing_push_notifications
    WHERE pass_id IS NOT NULL
      AND sent_at >= now() - INTERVAL 24 HOUR
      AND workspace_id = {workspace_id:UUID}
    GROUP BY workspace_id, hour, notification_type, channel
    ORDER BY hour DESC
  `,
  
  // Device registration trends
  deviceTrends: `
    SELECT 
      workspace_id,
      toStartOfDay(registered_at) as day,
      device_type,
      uniq(pass_id) as unique_passes,
      count() as total_devices
    FROM pass_devices
    WHERE registered_at >= now() - INTERVAL 30 DAY
      AND workspace_id = {workspace_id:UUID}
    GROUP BY workspace_id, day, device_type
    ORDER BY day DESC
  `,
  
  // Journey effectiveness with workspace isolation
  journeyEffectiveness: `
    SELECT 
      pjt.workspace_id,
      pjt.name as journey_name,
      uniq(mpn.pass_id) as passes_notified,
      countIf(mpn.delivery_status = 'delivered') as successful_deliveries,
      uniqIf(
        me.properties['passId'],
        me.event_type = 'pass.redeemed' 
        AND me.created_at > mpn.sent_at 
        AND me.created_at < mpn.sent_at + INTERVAL 7 DAY
      ) as redemptions_within_7_days
    FROM pass_journey_templates pjt
    JOIN marketing_push_notifications mpn ON mpn.journey_id = toString(pjt.id)
    LEFT JOIN marketing_events me ON me.properties['passId'] = mpn.pass_id
      AND me.workspace_id = pjt.workspace_id
    WHERE pjt.workspace_id = {workspace_id:UUID}
      AND mpn.sent_at >= now() - INTERVAL 30 DAY
    GROUP BY pjt.workspace_id, pjt.name
  `
};
```

### Phase 7: API Endpoints for Pass Channel

#### 7.1 Pass Device Registration API
```typescript
// packages/api/src/routes/channels/pass.ts
import { FastifyPluginAsync } from 'fastify';
import { Type } from '@sinclair/typebox';
import { requireWorkspaceAccess } from '../../middleware/workspace';
import { db } from '@backend-lib/db';
import { passDevices } from '@backend-lib/db/schema';

const passChannelRoutes: FastifyPluginAsync = async (fastify) => {
  // Register pass device - called by Apple/Google Wallet
  fastify.post<{
    Body: {
      passId: string;
      deviceToken: string;
      pushToken: string;
      deviceType: 'ios' | 'android';
    };
    Headers: {
      'x-pass-auth': string; // Pass-specific auth token
    };
  }>('/api/v1/channels/pass/devices/register', {
    schema: {
      body: Type.Object({
        passId: Type.String(),
        deviceToken: Type.String(),
        pushToken: Type.String(),
        deviceType: Type.Union([Type.Literal('ios'), Type.Literal('android')])
      }),
      response: {
        200: Type.Object({ success: Type.Boolean() }),
        400: Type.Object({ error: Type.String() }),
        403: Type.Object({ error: Type.String() })
      }
    },
    preHandler: requireWorkspaceAccess('member')
  }, async (request, reply) => {
    const { workspaceId, userId, role } = request.workspaceContext;
    
    const result = await service.registerDevice({
      ...request.body,
      workspaceId
    }, request.workspaceContext);
    
    if (result.isErr()) {
      return reply.code(result.error.code === 'FORBIDDEN' ? 403 : 400)
        .send({ error: result.error.message });
    }
    
    return { success: true };
  });

  // Get notification metrics endpoint
  fastify.get<{
    Querystring: {
      passId?: string;
      startDate?: string;
      endDate?: string;
    };
  }>('/api/v1/pass-notifications/metrics', {
    schema: {
      querystring: Type.Object({
        passId: Type.Optional(Type.String()),
        startDate: Type.Optional(Type.String({ format: 'date-time' })),
        endDate: Type.Optional(Type.String({ format: 'date-time' }))
      }),
      response: {
        200: Type.Object({
          metrics: Type.Array(Type.Object({
            date: Type.String(),
            sent: Type.Number(),
            delivered: Type.Number(),
            failed: Type.Number(),
            avgDeliveryTime: Type.Number()
          }))
        })
      }
    },
    preHandler: requireWorkspaceAccess('viewer')
  }, async (request, reply) => {
    const { workspaceId } = request.workspaceContext;
    const metrics = await service.getNotificationMetrics(
      workspaceId,
      request.query
    );
    
    return { metrics };
  });

  // Manual notification trigger (for testing)
  fastify.post<{
    Body: {
      passId: string;
      notificationType: string;
      data?: any;
    };
  }>('/api/v1/pass-notifications/send', {
    schema: {
      body: Type.Object({
        passId: Type.String(),
        notificationType: Type.String(),
        data: Type.Optional(Type.Any())
      })
    },
    preHandler: requireWorkspaceAccess('manager')
  }, async (request, reply) => {
    const result = await service.sendNotification(
      request.body,
      request.workspaceContext
    );
    
    if (result.isErr()) {
      return reply.code(500).send({ error: result.error.message });
    }
    
    return result.value;
  });
};

export default passNotificationRoutes;
```

## External Resources

### Documentation
- Dittofeed Documentation: https://docs.dittofeed.com/
- Apple Push Notification Service: https://developer.apple.com/documentation/usernotifications
- Google Wallet REST API: https://developers.google.com/wallet/generic/rest
- Kafka Integration: https://kafka.apache.org/documentation/
- Drizzle ORM: https://orm.drizzle.team/docs/overview
- TypeBox Validation: https://github.com/sinclairzx81/typebox

### SDKs and Libraries
- Dittofeed SDK: https://github.com/dittofeed/sdk-js
- Node APNs: https://github.com/parse-community/node-apn
- Redis Pub/Sub: https://redis.io/docs/manual/pubsub/
- Neverthrow: https://github.com/supermacro/neverthrow
- Temporal Workflow: https://docs.temporal.io/typescript/introduction

## Deployment

### Environment Variables
```bash
# Dittofeed Configuration
DITTOFEED_API_URL=https://api.dittofeed.com
DITTOFEED_API_KEY=your_api_key
DITTOFEED_WEBHOOK_SECRET=your_webhook_secret

# Apple Push Notifications
APN_KEY_PATH=/path/to/AuthKey_XXX.p8
APN_KEY_ID=your_key_id
APN_TEAM_ID=your_team_id
PASS_TYPE_ID=pass.com.yourcompany

# Google Wallet
GOOGLE_SERVICE_ACCOUNT_KEY=/path/to/service-account.json
GOOGLE_WALLET_ISSUER_ID=your_issuer_id

# Infrastructure
DATABASE_URL=postgresql://user:pass@localhost:5432/dittofeed
CLICKHOUSE_URL=http://localhost:8123
REDIS_URL=redis://localhost:6379
KAFKA_BROKERS=localhost:9092
TEMPORAL_ADDRESS=localhost:7233

# Security
JWT_SECRET=your_jwt_secret
ENCRYPTION_KEY=your_32_byte_encryption_key

# Monitoring
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
PROMETHEUS_PORT=9090
```

### Docker Compose Configuration
```yaml
# docker-compose.yml
version: '3.8'

services:
  # Pass notification worker service
  pass-notification-worker:
    build: 
      context: .
      dockerfile: packages/worker/Dockerfile
      target: pass-notifications
    environment:
      - NODE_ENV=production
      - DATABASE_URL=${DATABASE_URL}
      - REDIS_URL=redis://redis:6379
      - KAFKA_BROKERS=kafka:9092
      - TEMPORAL_ADDRESS=temporal:7233
    depends_on:
      - postgres
      - redis
      - kafka
      - temporal
    volumes:
      - ./certificates:/app/certificates:ro
    deploy:
      replicas: 3
      resources:
        limits:
          memory: 1G
          cpus: '0.5'
    healthcheck:
      test: ["CMD", "node", "health-check.js"]
      interval: 30s
      timeout: 10s
      retries: 3

  # API with pass notification endpoints
  api:
    extends:
      file: docker-compose.base.yml
      service: api
    environment:
      - ENABLE_PASS_NOTIFICATIONS=true
      - APN_KEY_PATH=/app/certificates/AuthKey.p8
    volumes:
      - ./certificates:/app/certificates:ro
```

### Kubernetes Deployment
```yaml
# k8s/pass-notification-worker.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pass-notification-worker
  namespace: dittofeed
spec:
  replicas: 3
  selector:
    matchLabels:
      app: pass-notification-worker
  template:
    metadata:
      labels:
        app: pass-notification-worker
    spec:
      serviceAccountName: dittofeed
      containers:
      - name: worker
        image: dittofeed/pass-notification-worker:latest
        env:
        - name: NODE_ENV
          value: production
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: dittofeed-db
              key: url
        - name: APN_KEY_ID
          valueFrom:
            secretKeyRef:
              name: apple-push-credentials
              key: key-id
        volumeMounts:
        - name: apple-certificates
          mountPath: /app/certificates
          readOnly: true
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 30
      volumes:
      - name: apple-certificates
        secret:
          secretName: apple-push-certificates
---
apiVersion: v1
kind: Service
metadata:
  name: pass-notification-worker
  namespace: dittofeed
spec:
  selector:
    app: pass-notification-worker
  ports:
  - protocol: TCP
    port: 3000
    targetPort: 3000
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: pass-notification-worker-hpa
  namespace: dittofeed
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: pass-notification-worker
  minReplicas: 3
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

## Success Criteria

1. **Integration Success**
   - Pass notification channels registered in Dittofeed with workspace isolation
   - Events bridged from Kafka to Dittofeed with workspace validation
   - Journeys created for pass updates with RBAC enforcement
   - Full multitenancy support across all components

2. **Performance**
   - < 1s notification delivery time (p99)
   - Support 10,000+ concurrent pass updates per workspace
   - 99.9% delivery success rate
   - Redis cache hit rate > 90% for device lookups

3. **Business Value**
   - Eliminate Pass2U enterprise costs ($500+/month)
   - Unified notification platform for all customer communications
   - Enhanced pass engagement metrics with workspace-level analytics
   - Support for hierarchical workspace structures

4. **Security & Compliance**
   - Strict workspace data isolation
   - RBAC enforcement on all endpoints
   - Audit trail for all pass operations
   - Encrypted storage of sensitive data

## Validation Gates

### Pre-deployment Checks
```bash
# 1. Run all tests with workspace isolation checks
cd packages/backend-lib
yarn test:pass-notifications

# 2. Integration tests with multitenancy scenarios
yarn test:integration:multitenancy

# 3. Load test with workspace isolation
yarn test:load:pass-notifications --workspaces=10 --passes-per-workspace=1000

# 4. Security audit
yarn audit:security

# 5. Type checking
yarn typecheck

# 6. Lint check
yarn lint
```

### Post-deployment Validation
```bash
# 1. Verify Dittofeed channel registration per workspace
curl -X GET "${API_URL}/api/v1/workspaces/${WORKSPACE_ID}/channels" \
  -H "Authorization: Bearer ${API_TOKEN}"

# 2. Test device registration with workspace context
curl -X POST "${API_URL}/api/v1/pass-devices/register" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H "X-Workspace-Id: ${WORKSPACE_ID}" \
  -H "Content-Type: application/json" \
  -d '{
    "passId": "test-pass-123",
    "deviceToken": "device-123",
    "pushToken": "push-123",
    "deviceType": "ios"
  }'

# 3. Monitor metrics by workspace
curl "${API_URL}/metrics" | grep -E "pass_notifications.*workspace_id=\"${WORKSPACE_ID}\""

# 4. Verify workspace isolation in logs
kubectl logs -n dittofeed -l app=pass-notification-worker --tail=100 | \
  grep "workspace_id" | jq '.workspace_id' | sort | uniq -c

# 5. Check cross-workspace access prevention
yarn test:security:cross-workspace
```

## Complete Implementation Checklist

- [ ] **Phase 0**: Pass Platform Security & Auth
  - [ ] Implement Apple Pass authentication token generation
  - [ ] Set up Google Wallet JWT verification
  - [ ] Add webhook signature validation for both platforms
  - [ ] Configure rate limiting per device/workspace

- [ ] **Phase 1**: Pass Channel Provider
  - [ ] Implement PassChannelProvider following Dittofeed channel interface
  - [ ] Add Apple Push Notification support for passes
  - [ ] Integrate Google Wallet update API
  - [ ] Add pass template validation

- [ ] **Phase 2**: Pass Template Management  
  - [ ] Create pass_templates table with Drizzle
  - [ ] Build template import from Pass2U
  - [ ] Implement Apple certificate storage (encrypted)
  - [ ] Set up Google Wallet class management
  - [ ] Add dynamic field mapping system

- [ ] **Phase 3**: Pass Generation & Distribution
  - [ ] Build PassGeneratorService for both platforms
  - [ ] Create pass download endpoints
  - [ ] Implement QR code generation
  - [ ] Add bulk pass generation API
  - [ ] Store pass metadata and track distribution

- [ ] **Phase 4**: Platform Web Services
  - [ ] Implement Apple Wallet web service endpoints
  - [ ] Add device registration/unregistration handlers  
  - [ ] Create pass update check endpoints
  - [ ] Set up Google Wallet callback handlers
  - [ ] Track all platform events

- [ ] **Phase 5**: Message Delivery Integration
  - [ ] Add pass handler to message delivery pipeline
  - [ ] Map user properties to pass IDs
  - [ ] Implement delivery status tracking
  - [ ] Configure retry logic and failover

- [ ] **Phase 6**: UI Integration (Existing Dashboard)
  - [ ] Add 'pass' to channel type definitions
  - [ ] Create PassChannelConfig component
  - [ ] Extend journey builder for pass messages
  - [ ] Add pass analytics to existing dashboards

- [ ] **Phase 7**: Testing & Migration
  - [ ] Test Apple/Google webhook integrations
  - [ ] Verify pass generation and distribution
  - [ ] Test multi-channel journeys with passes
  - [ ] Create Pass2U migration scripts
  - [ ] Document all endpoints and flows

## Critical Components We Initially Missed

### 1. **Pass Platform Authentication**
- Apple Wallet requires authentication tokens for each pass
- Google Wallet uses JWT-based authentication  
- Device registration endpoints must verify platform signatures
- Rate limiting to prevent abuse

### 2. **Pass Template Management**
- Pass templates need to be created and stored
- Apple requires certificates and provisioning
- Google requires class definitions
- Dynamic field mapping from user properties

### 3. **Pass Generation & Distribution**
- Generate passes on-demand with user data
- Create download links and QR codes
- Handle pass installation tracking
- Support bulk pass generation

### 4. **Platform Webhooks**
- Apple's web service endpoints for device registration
- Google's callback URLs for pass events
- Pass update checking endpoints
- Device unregistration handling

### 5. **Pass Lifecycle Events**
- Track pass installation/uninstallation
- Monitor pass views and updates
- Handle pass deletion
- Support pass sharing/transfer

## Additional Implementation Requirements

### Pass Authentication (Phase 0)
```typescript
// packages/backend-lib/src/channels/pass/auth.ts
import { createHmac, timingSafeEqual } from 'crypto';

// Apple Pass authentication for device registration
export function verifyApplePassAuth(
  authHeader: string,
  passSerialNumber: string
): Result<void, Error> {
  const [authType, token] = authHeader.split(' ');
  if (authType !== 'ApplePass') {
    return err(new Error('Invalid auth type'));
  }
  
  const secret = process.env.APPLE_PASS_AUTH_TOKEN;
  const expectedToken = createHmac('sha256', secret)
    .update(passSerialNumber)
    .digest('base64');
  
  if (!timingSafeEqual(Buffer.from(token), Buffer.from(expectedToken))) {
    return err(new Error('Invalid token'));
  }
  
  return ok(undefined);
}
```

### Pass Template Storage
```typescript
// packages/backend-lib/src/db/schema/pass-templates.ts
export const passTemplates = pgTable('pass_templates', {
  id: uuid('id').defaultRandom().primaryKey(),
  workspaceId: uuid('workspace_id').references(() => workspaces.id).notNull(),
  name: text('name').notNull(),
  platform: text('platform', { enum: ['apple', 'google', 'both'] }).notNull(),
  
  // Apple specific
  passTypeIdentifier: text('pass_type_identifier'),
  teamIdentifier: text('team_identifier'),
  certificate: text('certificate'), // Encrypted
  
  // Google specific
  googleClassId: text('google_class_id'),
  
  // Template structure
  structure: jsonb('structure').notNull(),
  fieldMappings: jsonb('field_mappings').notNull(),
  
  createdAt: timestamp('created_at').defaultNow().notNull()
});
```

### Platform Webhook Endpoints
```typescript
// packages/api/src/routes/webhooks/wallet-platforms.ts

// Apple Wallet endpoints
fastify.post('/v1/devices/:deviceId/registrations/:passTypeId/:serialNumber', {
  preHandler: verifyAppleAuth
}, async (request, reply) => {
  // Handle device registration
  const { deviceId, serialNumber } = request.params;
  const { pushToken } = request.body;
  
  await registerDevice({
    platform: 'apple',
    deviceId,
    passId: serialNumber,
    pushToken
  });
  
  return reply.code(201).send();
});

// Google Wallet callback
fastify.post('/webhooks/google-wallet/callback', {
  preHandler: verifyGoogleSignature
}, async (request, reply) => {
  // Handle Google Wallet events
  const { eventType, objectId } = request.body;
  
  await trackPassEvent({
    platform: 'google',
    eventType,
    passId: objectId
  });
  
  return { success: true };
});
```

## Summary: What We Added

After review, we identified several critical missing components:

1. **Authentication & Security**: Pass platforms require specific authentication mechanisms that weren't covered
2. **Template Management**: Passes need templates with certificates and provisioning
3. **Generation & Distribution**: The ability to create and distribute passes was missing
4. **Platform Webhooks**: Apple and Google have specific endpoints we must implement
5. **Lifecycle Management**: Full pass lifecycle from creation to expiry

These additions ensure a complete implementation that can fully replace Pass2U's functionality while integrating seamlessly with Dittofeed's existing architecture.

## Risk Mitigation

1. **Pass Platform Security**
   - Mitigation: Implement proper authentication for all platform endpoints
   - Monitoring: Track failed auth attempts, alert on anomalies

2. **Template Management Complexity**
   - Mitigation: Provide template builder UI, validate all templates
   - Monitoring: Track template usage and errors

3. **Rate Limiting**
   - Mitigation: Implement rate limits per device/workspace
   - Monitoring: Track rate limit hits, auto-scale if needed

4. **Certificate Management**
   - Mitigation: Automated renewal, encrypted storage
   - Monitoring: Certificate expiry alerts, validation checks

5. **Platform API Changes**
   - Mitigation: Version all integrations, maintain compatibility
   - Monitoring: API deprecation notices, test suites

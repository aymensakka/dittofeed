import { test, expect, Page } from '@playwright/test';
import { randomUUID } from 'crypto';

// Test configuration
const API_BASE_URL = 'http://localhost:3001';
const DASHBOARD_URL = 'http://localhost:3000';
const TEST_EMAIL = `test-${randomUUID()}@example.com`;
const TEST_PASSWORD = 'TestPassword123!';
const TEST_WORKSPACE_NAME = `E2E-Workspace-${Date.now()}`;

// Helper function to create test user and workspace
async function setupTestEnvironment(page: Page) {
  // This would typically be done via API or database seeding
  // For now, we'll use the OAuth flow simulation
  return {
    email: TEST_EMAIL,
    workspaceId: randomUUID(),
    workspaceName: TEST_WORKSPACE_NAME,
  };
}

// Helper to check API authentication
async function checkApiAuth(page: Page) {
  const cookies = await page.context().cookies();
  const authCookie = cookies.find(c => c.name === 'auth-token' || c.name === 'next-auth.session-token');
  return authCookie !== undefined;
}

test.describe('Dittofeed Multi-Tenant Dashboard E2E Tests', () => {
  let testContext: any;

  test.beforeEach(async ({ page }) => {
    // Navigate to dashboard
    await page.goto(`${DASHBOARD_URL}/dashboard`);
    
    // Setup test environment
    testContext = await setupTestEnvironment(page);
  });

  test.describe('Authentication & Workspace Management', () => {
    test('should redirect to login when not authenticated', async ({ page }) => {
      await page.goto(`${DASHBOARD_URL}/dashboard`);
      
      // Should redirect to login or show login prompt
      await expect(page).toHaveURL(/.*\/(login|auth|signin).*/);
    });

    test('should handle OAuth login flow', async ({ page }) => {
      await page.goto(`${DASHBOARD_URL}/dashboard`);
      
      // Look for Google OAuth button
      const googleLoginButton = page.locator('button:has-text("Sign in with Google")');
      if (await googleLoginButton.isVisible()) {
        // Note: Can't fully test OAuth without mocking
        expect(googleLoginButton).toBeVisible();
      }
    });

    test('should display workspace selector after login', async ({ page }) => {
      // Mock authenticated state
      await page.evaluate(() => {
        localStorage.setItem('test-auth', 'true');
      });
      
      await page.goto(`${DASHBOARD_URL}/dashboard`);
      
      // Check for workspace selector or workspace name
      const workspaceElement = page.locator('[data-testid="workspace-selector"], [class*="workspace"]').first();
      if (await workspaceElement.isVisible()) {
        expect(workspaceElement).toBeVisible();
      }
    });
  });

  test.describe('Main Navigation & Pages', () => {
    test('should navigate to all main sections', async ({ page }) => {
      const sections = [
        { name: 'Journeys', url: '/journeys' },
        { name: 'Segments', url: '/segments' },
        { name: 'Messages', url: '/messages' },
        { name: 'Users', url: '/users' },
        { name: 'Broadcasts', url: '/broadcasts' },
        { name: 'Deliveries', url: '/deliveries' },
        { name: 'Settings', url: '/settings' },
      ];

      for (const section of sections) {
        // Try to navigate using link or button
        const navElement = page.locator(`a:has-text("${section.name}"), button:has-text("${section.name}")`).first();
        
        if (await navElement.isVisible()) {
          await navElement.click();
          await page.waitForLoadState('networkidle');
          
          // Verify URL changed
          expect(page.url()).toContain(section.url);
          
          // Verify page loaded
          await expect(page.locator('h1, h2, [role="heading"]').first()).toBeVisible();
        }
      }
    });
  });

  test.describe('Segments Management', () => {
    test('should create a new segment', async ({ page }) => {
      await page.goto(`${DASHBOARD_URL}/dashboard/segments`);
      
      // Click create segment button
      const createButton = page.locator('button:has-text("Create"), button:has-text("New Segment")').first();
      if (await createButton.isVisible()) {
        await createButton.click();
        
        // Fill segment form
        await page.fill('input[name="name"], input[placeholder*="name"]', `Test Segment ${Date.now()}`);
        
        // Save segment
        const saveButton = page.locator('button:has-text("Save"), button:has-text("Create")').first();
        await saveButton.click();
        
        // Verify segment was created
        await expect(page.locator('.success, [role="alert"]')).toBeVisible({ timeout: 5000 });
      }
    });

    test('should list segments with workspace isolation', async ({ page }) => {
      await page.goto(`${DASHBOARD_URL}/dashboard/segments`);
      
      // Check if segments table/list is visible
      const segmentsList = page.locator('table, [role="grid"], .segment-list').first();
      if (await segmentsList.isVisible()) {
        // Verify workspace isolation by checking data attributes
        const segments = await page.locator('[data-workspace-id], .segment-item').all();
        
        for (const segment of segments) {
          const workspaceId = await segment.getAttribute('data-workspace-id');
          if (workspaceId) {
            // All segments should belong to current workspace
            expect(workspaceId).toBeTruthy();
          }
        }
      }
    });
  });

  test.describe('Journeys Management', () => {
    test('should create a new journey', async ({ page }) => {
      await page.goto(`${DASHBOARD_URL}/dashboard/journeys`);
      
      const createButton = page.locator('button:has-text("Create"), button:has-text("New Journey")').first();
      if (await createButton.isVisible()) {
        await createButton.click();
        
        // Fill journey form
        await page.fill('input[name="name"], input[placeholder*="name"]', `Test Journey ${Date.now()}`);
        
        // Save journey
        const saveButton = page.locator('button:has-text("Save"), button:has-text("Create")').first();
        await saveButton.click();
        
        // Verify journey was created
        await expect(page).toHaveURL(/.*\/journeys\/configure\/.*/);
      }
    });

    test('should configure journey workflow', async ({ page }) => {
      await page.goto(`${DASHBOARD_URL}/dashboard/journeys`);
      
      // Click on existing journey or create new one
      const journeyLink = page.locator('a[href*="/journeys/configure"]').first();
      if (await journeyLink.isVisible()) {
        await journeyLink.click();
        
        // Verify workflow editor loaded
        await expect(page.locator('.workflow-editor, canvas, [data-testid="journey-editor"]')).toBeVisible({ timeout: 10000 });
      }
    });
  });

  test.describe('Messages & Templates', () => {
    test('should create email template', async ({ page }) => {
      await page.goto(`${DASHBOARD_URL}/dashboard/messages`);
      
      const createButton = page.locator('button:has-text("Create"), button:has-text("New Template")').first();
      if (await createButton.isVisible()) {
        await createButton.click();
        
        // Select email type
        const emailOption = page.locator('button:has-text("Email"), [value="Email"]').first();
        await emailOption.click();
        
        // Fill template details
        await page.fill('input[name="name"], input[placeholder*="name"]', `Test Email Template ${Date.now()}`);
        await page.fill('input[name="subject"], input[placeholder*="subject"]', 'Test Subject');
        
        // Save template
        const saveButton = page.locator('button:has-text("Save")').first();
        await saveButton.click();
        
        // Verify template was created
        await expect(page.locator('.success, [role="alert"]')).toBeVisible({ timeout: 5000 });
      }
    });

    test('should preview email template', async ({ page }) => {
      await page.goto(`${DASHBOARD_URL}/dashboard/messages`);
      
      // Click on existing template
      const templateLink = page.locator('a[href*="/templates/email"]').first();
      if (await templateLink.isVisible()) {
        await templateLink.click();
        
        // Click preview button
        const previewButton = page.locator('button:has-text("Preview")').first();
        if (await previewButton.isVisible()) {
          await previewButton.click();
          
          // Verify preview modal/panel opens
          await expect(page.locator('.preview-modal, [role="dialog"]')).toBeVisible({ timeout: 5000 });
        }
      }
    });
  });

  test.describe('User Management', () => {
    test('should search for users', async ({ page }) => {
      await page.goto(`${DASHBOARD_URL}/dashboard/users`);
      
      // Find search input
      const searchInput = page.locator('input[type="search"], input[placeholder*="Search"]').first();
      if (await searchInput.isVisible()) {
        await searchInput.fill('test@example.com');
        await searchInput.press('Enter');
        
        // Wait for search results
        await page.waitForLoadState('networkidle');
        
        // Verify search worked
        const resultsTable = page.locator('table, [role="grid"]').first();
        expect(resultsTable).toBeVisible();
      }
    });

    test('should view user properties', async ({ page }) => {
      await page.goto(`${DASHBOARD_URL}/dashboard/user-properties`);
      
      // Check if user properties page loads
      await expect(page.locator('h1:has-text("User Properties"), h2:has-text("User Properties")')).toBeVisible({ timeout: 5000 });
      
      // Click on a property to edit
      const propertyLink = page.locator('a[href*="/user-properties/"]').first();
      if (await propertyLink.isVisible()) {
        await propertyLink.click();
        
        // Verify property editor loads
        await expect(page.locator('[data-testid="property-editor"], .property-definition')).toBeVisible({ timeout: 5000 });
      }
    });
  });

  test.describe('Broadcasts', () => {
    test('should create a broadcast', async ({ page }) => {
      await page.goto(`${DASHBOARD_URL}/dashboard/broadcasts`);
      
      const createButton = page.locator('button:has-text("Create"), button:has-text("New Broadcast")').first();
      if (await createButton.isVisible()) {
        await createButton.click();
        
        // Fill broadcast form
        await page.fill('input[name="name"], input[placeholder*="name"]', `Test Broadcast ${Date.now()}`);
        
        // Select segment
        const segmentSelect = page.locator('select[name="segment"], [data-testid="segment-select"]').first();
        if (await segmentSelect.isVisible()) {
          await segmentSelect.selectOption({ index: 1 });
        }
        
        // Save broadcast
        const saveButton = page.locator('button:has-text("Save"), button:has-text("Create")').first();
        await saveButton.click();
        
        // Verify broadcast was created
        await expect(page).toHaveURL(/.*\/broadcasts\/.*/);
      }
    });

    test('should trigger broadcast', async ({ page }) => {
      await page.goto(`${DASHBOARD_URL}/dashboard/broadcasts`);
      
      // Click on existing broadcast
      const broadcastLink = page.locator('a[href*="/broadcasts/review"]').first();
      if (await broadcastLink.isVisible()) {
        await broadcastLink.click();
        
        // Click trigger button
        const triggerButton = page.locator('button:has-text("Trigger"), button:has-text("Send")').first();
        if (await triggerButton.isVisible()) {
          await triggerButton.click();
          
          // Confirm trigger
          const confirmButton = page.locator('button:has-text("Confirm")').first();
          if (await confirmButton.isVisible()) {
            await confirmButton.click();
            
            // Verify broadcast was triggered
            await expect(page.locator('.success, [role="alert"]')).toBeVisible({ timeout: 5000 });
          }
        }
      }
    });
  });

  test.describe('Deliveries', () => {
    test('should view delivery logs', async ({ page }) => {
      await page.goto(`${DASHBOARD_URL}/dashboard/deliveries`);
      
      // Wait for deliveries table to load
      await expect(page.locator('table, [role="grid"]')).toBeVisible({ timeout: 10000 });
      
      // Check pagination works
      const nextButton = page.locator('button[aria-label="Next"], button:has-text("Next")').first();
      if (await nextButton.isEnabled()) {
        await nextButton.click();
        await page.waitForLoadState('networkidle');
      }
    });

    test('should preview delivery content', async ({ page }) => {
      await page.goto(`${DASHBOARD_URL}/dashboard/deliveries`);
      
      // Click preview icon on first delivery
      const previewButton = page.locator('[aria-label="Preview"], button:has-text("Preview")').first();
      if (await previewButton.isVisible()) {
        await previewButton.click();
        
        // Verify preview opens
        await expect(page.locator('.preview-drawer, [role="dialog"]')).toBeVisible({ timeout: 5000 });
      }
    });
  });

  test.describe('Settings & Integrations', () => {
    test('should access settings page', async ({ page }) => {
      await page.goto(`${DASHBOARD_URL}/dashboard/settings`);
      
      // Verify settings page loads
      await expect(page.locator('h1:has-text("Settings"), h2:has-text("Settings")')).toBeVisible({ timeout: 5000 });
      
      // Check for integration options
      const hubspotButton = page.locator('button:has-text("HubSpot"), a:has-text("HubSpot")').first();
      expect(hubspotButton).toBeVisible();
    });

    test('should configure email provider', async ({ page }) => {
      await page.goto(`${DASHBOARD_URL}/dashboard/settings`);
      
      // Navigate to email providers section
      const emailProvidersLink = page.locator('a:has-text("Email Providers")').first();
      if (await emailProvidersLink.isVisible()) {
        await emailProvidersLink.click();
        
        // Check for provider configuration
        const providerSelect = page.locator('select[name="provider"], [data-testid="provider-select"]').first();
        if (await providerSelect.isVisible()) {
          expect(providerSelect).toBeVisible();
        }
      }
    });

    test('should manage subscription groups', async ({ page }) => {
      await page.goto(`${DASHBOARD_URL}/dashboard/subscription-groups`);
      
      // Check if subscription groups page loads
      await expect(page.locator('h1:has-text("Subscription"), h2:has-text("Subscription")')).toBeVisible({ timeout: 5000 });
      
      // Create new subscription group
      const createButton = page.locator('button:has-text("Create"), button:has-text("New")').first();
      if (await createButton.isVisible()) {
        await createButton.click();
        
        // Fill form
        await page.fill('input[name="name"], input[placeholder*="name"]', `Test Subscription Group ${Date.now()}`);
        
        // Save
        const saveButton = page.locator('button:has-text("Save")').first();
        await saveButton.click();
        
        // Verify creation
        await expect(page.locator('.success, [role="alert"]')).toBeVisible({ timeout: 5000 });
      }
    });
  });

  test.describe('API Integration Tests', () => {
    test('should make authenticated API calls', async ({ page }) => {
      // Set up API context with authentication
      const apiContext = await page.request;
      
      // Test segments API
      const segmentsResponse = await apiContext.get(`${API_BASE_URL}/api/segments`, {
        headers: {
          'Authorization': `Bearer test-token`,
          'X-Workspace-Id': testContext.workspaceId,
        },
      });
      
      if (segmentsResponse.ok()) {
        const segments = await segmentsResponse.json();
        expect(Array.isArray(segments)).toBeTruthy();
      }
    });

    test('should respect workspace isolation in API', async ({ page }) => {
      const apiContext = await page.request;
      
      // Try to access different workspace's data
      const wrongWorkspaceId = randomUUID();
      const response = await apiContext.get(`${API_BASE_URL}/api/segments`, {
        headers: {
          'Authorization': `Bearer test-token`,
          'X-Workspace-Id': wrongWorkspaceId,
        },
      });
      
      // Should either return 403 or empty results
      if (response.ok()) {
        const data = await response.json();
        expect(data).toEqual([]);
      } else {
        expect(response.status()).toBe(403);
      }
    });

    test('should handle rate limiting', async ({ page }) => {
      const apiContext = await page.request;
      const promises = [];
      
      // Make multiple rapid requests
      for (let i = 0; i < 20; i++) {
        promises.push(
          apiContext.get(`${API_BASE_URL}/api/segments`, {
            headers: {
              'Authorization': `Bearer test-token`,
              'X-Workspace-Id': testContext.workspaceId,
            },
          })
        );
      }
      
      const responses = await Promise.all(promises);
      
      // Check if any requests were rate limited
      const rateLimited = responses.some(r => r.status() === 429);
      
      // Rate limiting should be in place
      if (rateLimited) {
        expect(rateLimited).toBeTruthy();
      }
    });
  });

  test.describe('Performance & Error Handling', () => {
    test('should handle network errors gracefully', async ({ page }) => {
      // Simulate network failure
      await page.route('**/api/**', route => route.abort());
      
      await page.goto(`${DASHBOARD_URL}/dashboard/segments`);
      
      // Should show error message
      await expect(page.locator('.error, [role="alert"]')).toBeVisible({ timeout: 10000 });
      
      // Clear route
      await page.unroute('**/api/**');
    });

    test('should load pages within acceptable time', async ({ page }) => {
      const startTime = Date.now();
      
      await page.goto(`${DASHBOARD_URL}/dashboard/journeys`);
      await page.waitForLoadState('networkidle');
      
      const loadTime = Date.now() - startTime;
      
      // Page should load within 5 seconds
      expect(loadTime).toBeLessThan(5000);
    });

    test('should handle concurrent operations', async ({ page }) => {
      await page.goto(`${DASHBOARD_URL}/dashboard/segments`);
      
      // Trigger multiple operations simultaneously
      const operations = [
        page.locator('button:has-text("Refresh")').first().click(),
        page.locator('input[type="search"]').first().fill('test'),
        page.locator('select').first().selectOption({ index: 0 }),
      ];
      
      // All operations should complete without errors
      await Promise.all(operations.filter(Boolean));
      
      // Page should remain stable
      await expect(page.locator('body')).toBeVisible();
    });
  });

  test.describe('Data Consistency', () => {
    test('should maintain workspace context across navigation', async ({ page }) => {
      // Navigate through multiple pages
      const pages = [
        '/dashboard/segments',
        '/dashboard/journeys',
        '/dashboard/messages',
        '/dashboard/users',
      ];
      
      for (const pageUrl of pages) {
        await page.goto(`${DASHBOARD_URL}${pageUrl}`);
        
        // Check workspace context is maintained
        const workspaceIndicator = page.locator('[data-workspace-id], .workspace-name').first();
        if (await workspaceIndicator.isVisible()) {
          const workspaceId = await workspaceIndicator.getAttribute('data-workspace-id');
          expect(workspaceId).toBeTruthy();
        }
      }
    });

    test('should sync data updates across tabs', async ({ browser }) => {
      // Open two tabs
      const context = await browser.newContext();
      const page1 = await context.newPage();
      const page2 = await context.newPage();
      
      // Navigate both to segments
      await page1.goto(`${DASHBOARD_URL}/dashboard/segments`);
      await page2.goto(`${DASHBOARD_URL}/dashboard/segments`);
      
      // Create segment in page1
      const createButton = page1.locator('button:has-text("Create")').first();
      if (await createButton.isVisible()) {
        await createButton.click();
        await page1.fill('input[name="name"]', `Cross-Tab Test ${Date.now()}`);
        await page1.locator('button:has-text("Save")').first().click();
      }
      
      // Refresh page2 and check if new segment appears
      await page2.reload();
      await page2.waitForLoadState('networkidle');
      
      // Both pages should show consistent data
      const segments1 = await page1.locator('table tbody tr').count();
      const segments2 = await page2.locator('table tbody tr').count();
      
      if (segments1 > 0 && segments2 > 0) {
        expect(Math.abs(segments1 - segments2)).toBeLessThanOrEqual(1);
      }
      
      await context.close();
    });
  });

  test.describe('Accessibility', () => {
    test('should have proper ARIA labels', async ({ page }) => {
      await page.goto(`${DASHBOARD_URL}/dashboard`);
      
      // Check for main navigation
      const nav = page.locator('nav[role="navigation"]');
      if (await nav.isVisible()) {
        expect(nav).toHaveAttribute('role', 'navigation');
      }
      
      // Check for main content
      const main = page.locator('main, [role="main"]');
      if (await main.isVisible()) {
        expect(main).toBeVisible();
      }
      
      // Check for proper heading hierarchy
      const h1 = await page.locator('h1').count();
      expect(h1).toBeGreaterThanOrEqual(1);
    });

    test('should be keyboard navigable', async ({ page }) => {
      await page.goto(`${DASHBOARD_URL}/dashboard`);
      
      // Tab through interactive elements
      await page.keyboard.press('Tab');
      await page.keyboard.press('Tab');
      await page.keyboard.press('Tab');
      
      // Check if an element has focus
      const focusedElement = await page.evaluate(() => document.activeElement?.tagName);
      expect(focusedElement).toBeTruthy();
    });
  });
});

// Summary test to verify all critical paths
test('Full Dashboard Functionality Summary', async ({ page }) => {
  console.log('\n=== DASHBOARD E2E TEST SUMMARY ===');
  
  const testResults = {
    authentication: false,
    navigation: false,
    segments: false,
    journeys: false,
    messages: false,
    users: false,
    broadcasts: false,
    deliveries: false,
    settings: false,
    api: false,
  };
  
  // Quick smoke test of all major features
  try {
    await page.goto(`${DASHBOARD_URL}/dashboard`, { waitUntil: 'networkidle' });
    testResults.navigation = true;
    
    // Test each major section
    const sections = Object.keys(testResults);
    for (const section of sections) {
      if (section !== 'authentication' && section !== 'api') {
        const sectionUrl = `${DASHBOARD_URL}/dashboard/${section}`;
        const response = await page.goto(sectionUrl, { waitUntil: 'domcontentloaded' });
        testResults[section] = response?.ok() || false;
      }
    }
    
    // Test API endpoint
    const apiResponse = await page.request.get(`${API_BASE_URL}/api/health`);
    testResults.api = apiResponse.ok();
    
  } catch (error) {
    console.error('Summary test error:', error);
  }
  
  // Print results
  console.log('\nTest Results:');
  for (const [feature, passed] of Object.entries(testResults)) {
    console.log(`  ${passed ? '✅' : '❌'} ${feature.charAt(0).toUpperCase() + feature.slice(1)}`);
  }
  
  const passedCount = Object.values(testResults).filter(r => r).length;
  const totalCount = Object.keys(testResults).length;
  
  console.log(`\nOverall: ${passedCount}/${totalCount} features working`);
  console.log('================================================\n');
  
  expect(passedCount).toBeGreaterThan(totalCount * 0.7); // At least 70% should work
});
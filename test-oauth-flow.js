#!/usr/bin/env node

const { chromium } = require('playwright');

async function testOAuthFlow() {
  const browser = await chromium.launch({ 
    headless: false, // Show browser for debugging
    slowMo: 500 // Slow down for visibility
  });
  
  try {
    const context = await browser.newContext();
    const page = await context.newPage();
    
    // Enable console logging
    page.on('console', msg => {
      if (msg.text().includes('cookie') || msg.text().includes('session') || msg.text().includes('auth')) {
        console.log('Browser console:', msg.text());
      }
    });
    
    console.log('1. Navigating to dashboard...');
    await page.goto('http://localhost:3000/dashboard/journeys');
    
    // Should redirect to OAuth
    await page.waitForURL(/accounts\.google\.com/, { timeout: 10000 });
    console.log('2. Redirected to Google OAuth');
    
    // Check if we need to enter credentials or just select account
    const emailField = await page.locator('input[type="email"]').count();
    
    if (emailField > 0) {
      console.log('3. Entering email...');
      await page.fill('input[type="email"]', 'aymensakka@gmail.com');
      await page.click('#identifierNext');
      
      // Wait for password or account selection
      await page.waitForTimeout(2000);
    }
    
    // Check if we're on the consent screen
    const consentButton = await page.locator('button:has-text("Continue")').count();
    if (consentButton > 0) {
      console.log('4. Clicking consent...');
      await page.click('button:has-text("Continue")');
    }
    
    // Wait for redirect back to dashboard
    console.log('5. Waiting for redirect back to dashboard...');
    await page.waitForURL(/localhost:3000\/dashboard/, { timeout: 10000 });
    
    // Check cookies
    const cookies = await context.cookies();
    console.log('6. Cookies after auth:', cookies.map(c => ({ name: c.name, value: c.value })));
    
    // Check if we're authenticated
    const url = page.url();
    console.log('7. Final URL:', url);
    
    if (url.includes('/dashboard/journeys')) {
      console.log('✅ OAuth flow successful!');
    } else {
      console.log('❌ OAuth flow failed - not on expected page');
    }
    
    // Keep browser open for inspection
    await page.waitForTimeout(5000);
    
  } finally {
    await browser.close();
  }
}

testOAuthFlow().catch(console.error);
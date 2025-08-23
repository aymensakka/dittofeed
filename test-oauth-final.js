const { chromium } = require('playwright');

(async () => {
  console.log('Testing OAuth flow with session support...');
  
  // Launch browser
  const browser = await chromium.launch({ 
    headless: false, 
    slowMo: 100 
  });
  
  const context = await browser.newContext();
  const page = await context.newPage();
  
  try {
    console.log('1. Navigating to dashboard...');
    await page.goto('http://localhost:3000/dashboard/journeys');
    
    // Wait for redirect
    await page.waitForTimeout(2000);
    
    const currentUrl = page.url();
    console.log('2. Redirected to:', currentUrl.split('?')[0]);
    
    if (currentUrl.includes('accounts.google.com')) {
      console.log('✓ Successfully redirected to Google OAuth');
      console.log('\n3. Please complete the Google sign-in in the browser...');
      console.log('   Waiting for OAuth callback (2 minutes timeout)...\n');
      
      // Set up event listeners for navigation
      page.on('framenavigated', (frame) => {
        if (frame === page.mainFrame()) {
          const url = frame.url();
          if (url.includes('localhost:3001/api/public/auth/oauth2/callback')) {
            console.log('   → OAuth callback received');
          } else if (url.includes('/dashboard')) {
            console.log('   → Redirected to dashboard!');
          }
        }
      });
      
      // Wait for successful authentication
      try {
        await page.waitForURL('**/dashboard/**', { timeout: 120000 });
        
        console.log('\n✓ OAuth authentication successful!');
        console.log('   Final URL:', page.url());
        
        // Take screenshot
        await page.screenshot({ path: 'oauth-authenticated.png' });
        console.log('   Screenshot saved as oauth-authenticated.png');
        
        // Check for user info
        const bodyText = await page.textContent('body').catch(() => '');
        if (bodyText.includes('@')) {
          console.log('   User authenticated successfully!');
        }
        
      } catch (e) {
        const errorUrl = page.url();
        console.log('\n✗ Authentication failed or timed out');
        console.log('   Current URL:', errorUrl);
        
        if (errorUrl.includes('error') || errorUrl.includes('callback')) {
          const bodyText = await page.textContent('body').catch(() => '');
          console.log('   Error:', bodyText.substring(0, 200));
        }
      }
    } else {
      console.log('✗ Failed to redirect to Google OAuth');
      console.log('   Current URL:', currentUrl);
    }
    
    console.log('\n4. Test completed. Browser will close in 5 seconds...');
    await page.waitForTimeout(5000);
    
  } catch (error) {
    console.error('Test error:', error.message);
  }
  
  await browser.close();
})();
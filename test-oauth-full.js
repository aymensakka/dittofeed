const { chromium } = require('playwright');

(async () => {
  console.log('Testing full OAuth flow with actual Google sign-in...');
  
  // Launch browser in non-headless mode so user can sign in
  const browser = await chromium.launch({ 
    headless: false, 
    slowMo: 500 
  });
  
  const context = await browser.newContext();
  const page = await context.newPage();
  
  try {
    console.log('1. Navigating to dashboard...');
    await page.goto('http://localhost:3000/dashboard/journeys');
    
    // Wait for redirect to OAuth
    await page.waitForTimeout(2000);
    
    const currentUrl = page.url();
    console.log('2. Current URL:', currentUrl);
    
    if (currentUrl.includes('accounts.google.com')) {
      console.log('✓ Successfully redirected to Google OAuth');
      console.log('\n3. Please sign in with your Google account in the browser window...');
      console.log('   The browser will stay open for you to complete the sign-in process.');
      
      // Wait for user to complete OAuth and redirect back
      console.log('\n   Waiting for OAuth callback...');
      
      // Wait up to 2 minutes for the user to complete sign-in
      try {
        await page.waitForURL('**/dashboard/**', { timeout: 120000 });
        console.log('\n✓ Successfully authenticated and redirected to dashboard!');
        console.log('   Final URL:', page.url());
        
        // Check if we're on the dashboard
        const finalUrl = page.url();
        if (finalUrl.includes('/dashboard')) {
          console.log('✓ OAuth authentication completed successfully!');
          
          // Take a screenshot of the authenticated dashboard
          await page.screenshot({ path: 'oauth-success.png' });
          console.log('   Screenshot saved as oauth-success.png');
        }
      } catch (timeoutError) {
        // Check if we got an error page
        const errorUrl = page.url();
        if (errorUrl.includes('error')) {
          console.log('\n✗ OAuth failed with error');
          console.log('   Error URL:', errorUrl);
          const bodyText = await page.textContent('body').catch(() => 'Could not get body');
          console.log('   Error message:', bodyText);
        } else {
          console.log('\n⚠ Timeout waiting for OAuth callback');
          console.log('   Current URL:', errorUrl);
        }
      }
    } else {
      console.log('✗ Did not redirect to Google OAuth');
      console.log('   URL:', currentUrl);
    }
    
    console.log('\n4. Keeping browser open for 10 seconds to inspect...');
    await page.waitForTimeout(10000);
    
  } catch (error) {
    console.error('Error during test:', error);
  }
  
  console.log('\n5. Test completed. Closing browser...');
  await browser.close();
})();
const http = require('http');
const https = require('https');
const url = require('url');

console.log('Starting OAuth debugging...\n');

// Step 1: Test the OAuth initiate endpoint
function testOAuthInitiate() {
  return new Promise((resolve) => {
    console.log('1. Testing OAuth initiate endpoint...');
    http.get('http://localhost:3001/api/public/auth/oauth2/initiate/google', (res) => {
      console.log('   Status:', res.statusCode);
      console.log('   Location:', res.headers.location);
      
      if (res.statusCode === 302 && res.headers.location) {
        const redirectUrl = res.headers.location;
        const parsedUrl = new URL(redirectUrl);
        console.log('   ✓ Redirects to:', parsedUrl.hostname);
        console.log('   Client ID:', parsedUrl.searchParams.get('client_id'));
        console.log('   Redirect URI:', decodeURIComponent(parsedUrl.searchParams.get('redirect_uri')));
        resolve(redirectUrl);
      } else {
        console.log('   ✗ Failed to redirect properly');
        resolve(null);
      }
    }).on('error', (err) => {
      console.error('   Error:', err.message);
      resolve(null);
    });
  });
}

// Step 2: Simulate OAuth callback
function simulateOAuthCallback() {
  return new Promise((resolve) => {
    console.log('\n2. Simulating OAuth callback...');
    
    // Create a fake OAuth callback with test data
    const state = Date.now() + '-test';
    const fakeCode = 'test-code-' + Date.now();
    
    const callbackUrl = `http://localhost:3001/api/public/auth/oauth2/callback/google?` +
      `state=${state}&code=${fakeCode}&scope=email+profile+openid`;
    
    console.log('   Callback URL:', callbackUrl);
    
    http.get(callbackUrl, (res) => {
      let data = '';
      
      res.on('data', (chunk) => {
        data += chunk;
      });
      
      res.on('end', () => {
        console.log('   Status:', res.statusCode);
        if (data) {
          console.log('   Response:', data.substring(0, 200));
          
          // Parse error if JSON
          try {
            const json = JSON.parse(data);
            if (json.error) {
              console.log('   ✗ Error:', json.error);
            }
          } catch (e) {
            // Not JSON, that's ok
          }
        }
        resolve(res.statusCode);
      });
    }).on('error', (err) => {
      console.error('   Error:', err.message);
      resolve(null);
    });
  });
}

// Step 3: Check API logs
function checkAPILogs() {
  console.log('\n3. Recent API activity check...');
  console.log('   Check the API logs in the terminal for detailed error messages');
}

// Step 4: Test dashboard redirect
function testDashboardRedirect() {
  return new Promise((resolve) => {
    console.log('\n4. Testing dashboard redirect...');
    http.get('http://localhost:3000/dashboard/journeys', (res) => {
      console.log('   Status:', res.statusCode);
      if (res.headers.location) {
        console.log('   Redirects to:', res.headers.location);
        if (res.headers.location.includes('/api/public/auth/oauth2/initiate')) {
          console.log('   ✓ Dashboard correctly redirects to OAuth');
        }
      }
      resolve();
    }).on('error', (err) => {
      console.error('   Error:', err.message);
      resolve();
    });
  });
}

// Run all tests
async function runTests() {
  await testOAuthInitiate();
  await simulateOAuthCallback();
  await testDashboardRedirect();
  checkAPILogs();
  
  console.log('\n5. Next steps:');
  console.log('   - Check the API terminal for detailed error logs');
  console.log('   - The OAuth callback is likely failing during token exchange or user creation');
  console.log('   - Try accessing http://localhost:3000/dashboard in a browser to see the actual error');
}

runTests();
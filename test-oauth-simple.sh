#!/bin/bash

echo "Testing OAuth flow..."
echo "1. Testing API OAuth initiate endpoint..."

# Test OAuth initiate
response=$(curl -s -I http://localhost:3001/api/public/auth/oauth2/initiate/google 2>&1)
echo "$response" | head -5

if echo "$response" | grep -q "302 Found"; then
  echo "✓ OAuth initiate returns 302 redirect"
  
  # Get the redirect URL
  redirect_url=$(echo "$response" | grep -i "location:" | cut -d' ' -f2)
  echo "  Redirect URL: $redirect_url"
  
  if echo "$redirect_url" | grep -q "accounts.google.com"; then
    echo "✓ Redirects to Google OAuth"
    
    # Extract client_id
    client_id=$(echo "$redirect_url" | grep -o 'client_id=[^&]*' | cut -d'=' -f2)
    echo "  Client ID: $client_id"
    
    # Extract redirect_uri
    redirect_uri=$(echo "$redirect_url" | grep -o 'redirect_uri=[^&]*' | cut -d'=' -f2 | sed 's/%3A/:/g' | sed 's/%2F/\//g')
    echo "  Callback URI: $redirect_uri"
  else
    echo "✗ Does not redirect to Google OAuth"
  fi
else
  echo "✗ OAuth initiate failed"
  echo "$response"
fi

echo ""
echo "2. Testing dashboard redirect..."
dashboard_response=$(curl -s -I http://localhost:3000/dashboard/journeys 2>&1)
echo "$dashboard_response" | head -5

if echo "$dashboard_response" | grep -q "307 Temporary Redirect"; then
  echo "✓ Dashboard redirects for authentication"
  
  redirect_location=$(echo "$dashboard_response" | grep -i "location:" | cut -d' ' -f2)
  echo "  Redirects to: $redirect_location"
else
  echo "✗ Dashboard does not redirect properly"
fi

echo ""
echo "3. Checking API logs for errors..."
echo "Run: curl -v http://localhost:3000/dashboard in your browser to test the full flow"
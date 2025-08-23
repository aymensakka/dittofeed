#!/bin/bash

# First, initiate OAuth to get a state
echo "1. Initiating OAuth..."
RESPONSE=$(curl -s -I "http://localhost:3001/api/public/auth/oauth2/initiate/google?returnUrl=/dashboard/journeys")
STATE=$(echo "$RESPONSE" | grep -oP 'state=\K[^&]+' | head -1)

if [ -z "$STATE" ]; then
  echo "Could not extract state from OAuth initiate"
  exit 1
fi

echo "Got state: $STATE"

# Simulate OAuth callback with a dummy code
echo "2. Simulating OAuth callback..."
curl -v "http://localhost:3001/api/public/auth/oauth2/callback/google?state=$STATE&code=dummy_code" 2>&1 | head -30
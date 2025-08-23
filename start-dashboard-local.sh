#!/bin/bash

# Load environment variables from .env file
export $(cat .env | grep -v '^#' | xargs)

cd packages/dashboard
AUTH_MODE=multi-tenant \
NEXT_PUBLIC_AUTH_MODE=multi-tenant \
NEXT_PUBLIC_API_BASE=http://localhost:3001 \
NEXT_PUBLIC_ENABLE_MULTITENANCY=true \
NEXTAUTH_URL=http://localhost:3000/dashboard \
NEXTAUTH_SECRET=${NEXTAUTH_SECRET:-your-nextauth-secret} \
GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID} \
GOOGLE_CLIENT_SECRET=${GOOGLE_CLIENT_SECRET} \
yarn dev

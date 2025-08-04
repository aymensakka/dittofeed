#!/bin/bash
# Docker login script for Coolify with file lock handling
set -e

echo "Cleaning up Docker config locks..."
# Remove any stale lock files
rm -f /root/.docker/config.json.lock 2>/dev/null || true
rm -f /root/.docker/.config.json.* 2>/dev/null || true
rm -f /root/.docker/config.json[0-9]* 2>/dev/null || true

# If config.json exists and is locked, remove it
if [ -f /root/.docker/config.json ]; then
    echo "Removing existing Docker config..."
    rm -f /root/.docker/config.json 2>/dev/null || true
fi

# Ensure .docker directory exists with proper permissions
mkdir -p /root/.docker
chmod 700 /root/.docker

# Wait for any pending Docker operations
sleep 2

# Check if environment variables are set
if [ -n "${DOCKER_REGISTRY_USERNAME}" ] && [ -n "${DOCKER_REGISTRY_PASSWORD}" ]; then
    echo "Using environment variables for Docker login..."
    echo "${DOCKER_REGISTRY_PASSWORD}" | docker login docker.reactmotion.com \
        -u "${DOCKER_REGISTRY_USERNAME}" \
        --password-stdin
else
    echo "Using hardcoded credentials for Docker login..."
    echo '9sFPGGDJUFnE4z*z4Aj9' | docker login docker.reactmotion.com \
        -u coolify-system \
        --password-stdin
fi

if [ $? -eq 0 ]; then
    echo "Docker login successful!"
else
    echo "Docker login failed!"
    exit 1
fi
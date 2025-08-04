#!/bin/bash
# Docker login script for Coolify
set -e

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
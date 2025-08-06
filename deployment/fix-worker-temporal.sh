#!/bin/bash
# Fix worker by disabling Temporal or setting correct address

echo "=== Fixing Worker Service ==="
echo ""

# Option 1: Set TEMPORAL_ADDRESS to empty to disable
echo "Option 1: Disable Temporal (if not using workflow features)"
echo "In Coolify environment variables, set:"
echo "  TEMPORAL_ADDRESS="
echo ""

# Option 2: Use a dummy/local Temporal
echo "Option 2: Point to localhost (will fail but won't crash)"
echo "In Coolify environment variables, set:"
echo "  TEMPORAL_ADDRESS=localhost:7233"
echo ""

# Check current setting
echo "Current TEMPORAL_ADDRESS in Coolify:"
echo "Check your Coolify environment variables"
echo ""

# Restart worker after changing
echo "After updating, restart the worker:"
echo "  docker restart $(docker ps -q -f name=worker-p0gcsc088cogco0cokco4404)"
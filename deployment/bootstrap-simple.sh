#!/bin/bash

# ==============================================================================
# Simple Bootstrap Script - Uses API's built-in bootstrap
# ==============================================================================

echo "===================================================="
echo "Simple Bootstrap for Dittofeed Multi-Tenant"
echo "===================================================="

PROJECT_ID="p0gcsc088cogco0cokco4404"

# Find containers
API_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "api.*${PROJECT_ID}" | head -1)
POSTGRES_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "postgres.*${PROJECT_ID}" | head -1)

if [ -z "$API_CONTAINER" ]; then
    echo "Error: API container not found"
    exit 1
fi

echo "Using containers:"
echo "  API: $API_CONTAINER"
echo "  Postgres: $POSTGRES_CONTAINER"
echo ""

# Method 1: Try using the API's startup script with BOOTSTRAP=true
echo "Method 1: Running API with BOOTSTRAP=true..."
docker exec -e BOOTSTRAP=true -e BOOTSTRAP_WORKSPACE_NAME=caramel -e BOOTSTRAP_WORKSPACE_DOMAIN=caramelme.com -e AUTH_MODE=multi-tenant $API_CONTAINER sh -c '
# Check if there is a bootstrap script
if [ -f /service/scripts/bootstrap.js ]; then
    echo "Found bootstrap.js"
    node /service/scripts/bootstrap.js
elif [ -f /service/dist/scripts/bootstrap.js ]; then
    echo "Found dist/scripts/bootstrap.js"
    node /service/dist/scripts/bootstrap.js
elif [ -f /service/dist/scripts/startServer.js ]; then
    echo "Using startServer.js with BOOTSTRAP=true"
    # Run the server with bootstrap flag, but timeout after 30 seconds
    timeout 30 node /service/dist/scripts/startServer.js || true
else
    echo "No bootstrap script found, trying direct module import"
    
    # Try to find and run bootstrap directly
    node -e "
    const path = require(\"path\");
    const fs = require(\"fs\");
    
    // Log current directory structure
    console.log(\"Current directory:\", process.cwd());
    console.log(\"Directory contents:\");
    const files = fs.readdirSync(\".\");
    files.forEach(f => console.log(\"  \", f));
    
    // Check for dist directory
    if (fs.existsSync(\"dist\")) {
        console.log(\"\\nDist directory contents:\");
        const distFiles = fs.readdirSync(\"dist\");
        distFiles.forEach(f => console.log(\"  \", f));
    }
    
    // Try to load bootstrap
    try {
        const bootstrapPath = path.join(process.cwd(), \"dist/node_modules/backend-lib/dist/bootstrap.js\");
        if (fs.existsSync(bootstrapPath)) {
            console.log(\"\\nFound bootstrap at:\", bootstrapPath);
            const { bootstrapWithDefaults } = require(bootstrapPath);
            
            console.log(\"Running bootstrap...\");
            bootstrapWithDefaults({
                workspaceName: \"caramel\",
                workspaceDomain: \"caramelme.com\",
                workspaceType: \"Root\"
            }).then(() => {
                console.log(\"✓ Bootstrap successful\");
                process.exit(0);
            }).catch(err => {
                console.error(\"Bootstrap error:\", err.message);
                process.exit(1);
            });
        } else {
            console.log(\"Bootstrap module not found at expected path\");
            
            // Try alternate path
            const altPath = \"./node_modules/backend-lib/dist/bootstrap.js\";
            if (fs.existsSync(altPath)) {
                console.log(\"Found at alternate path:\", altPath);
                const { bootstrapWithDefaults } = require(altPath);
                bootstrapWithDefaults({
                    workspaceName: \"caramel\",
                    workspaceDomain: \"caramelme.com\",
                    workspaceType: \"Root\"
                }).then(() => {
                    console.log(\"✓ Bootstrap successful\");
                    process.exit(0);
                });
            }
        }
    } catch (err) {
        console.error(\"Failed to load bootstrap:\", err.message);
        process.exit(1);
    }
    "
fi
'

echo ""
echo "Checking if workspace was created..."
if [ ! -z "$POSTGRES_CONTAINER" ]; then
    WORKSPACE_COUNT=$(docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -t -c "SELECT COUNT(*) FROM workspace;" 2>/dev/null || echo "0")
    WORKSPACE_COUNT=$(echo $WORKSPACE_COUNT | tr -d ' ')
    
    if [ "$WORKSPACE_COUNT" != "0" ]; then
        echo "✓ Found $WORKSPACE_COUNT workspace(s)"
        docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT id, name, type, domain FROM workspace;"
        echo ""
        echo "Bootstrap successful!"
    else
        echo "No workspaces found. Bootstrap may have failed."
        echo ""
        echo "Checking API logs for errors..."
        docker logs $API_CONTAINER --tail 30 2>&1 | grep -i "error\|fail\|bootstrap" || true
    fi
fi

echo ""
echo "===================================================="
echo "Done!"
echo "===================================================="
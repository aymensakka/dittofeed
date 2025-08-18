#!/bin/bash

# ==============================================================================
# Enhanced Bootstrap Script with Network Configuration for Dittofeed Multi-Tenant
# This script:
# 1. Finds all containers dynamically
# 2. Gets their internal IPs
# 3. Updates environment variables for proper internal networking
# 4. Runs bootstrap to initialize the database and workspace
# ==============================================================================

set -e

echo "===================================================="
echo "Enhanced Bootstrap with Network Configuration"
echo "===================================================="

PROJECT_ID="p0gcsc088cogco0cokco4404"

# Find all containers dynamically
echo "Step 1: Finding containers..."
API_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "api.*${PROJECT_ID}" | head -1)
POSTGRES_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "postgres.*${PROJECT_ID}" | head -1)
DASHBOARD_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "dashboard.*${PROJECT_ID}" | head -1)
WORKER_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "worker.*${PROJECT_ID}" | head -1)
TEMPORAL_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "temporal.*${PROJECT_ID}" | head -1)
CLICKHOUSE_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "clickhouse.*${PROJECT_ID}" | head -1)
REDIS_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "redis.*${PROJECT_ID}" | head -1)

echo ""
echo "Found containers:"
echo "  API: ${API_CONTAINER:-NOT FOUND}"
echo "  Postgres: ${POSTGRES_CONTAINER:-NOT FOUND}"
echo "  Dashboard: ${DASHBOARD_CONTAINER:-NOT FOUND}"
echo "  Worker: ${WORKER_CONTAINER:-NOT FOUND}"
echo "  Temporal: ${TEMPORAL_CONTAINER:-NOT FOUND}"
echo "  ClickHouse: ${CLICKHOUSE_CONTAINER:-NOT FOUND}"
echo "  Redis: ${REDIS_CONTAINER:-NOT FOUND}"
echo ""

# Check critical containers
if [ -z "$API_CONTAINER" ] || [ -z "$POSTGRES_CONTAINER" ] || [ -z "$DASHBOARD_CONTAINER" ]; then
    echo "Error: Critical containers not found"
    exit 1
fi

# Get container IPs
echo "Step 2: Getting container IPs..."
API_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $API_CONTAINER | head -c -1 | tr -d '\n')
POSTGRES_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $POSTGRES_CONTAINER | head -c -1 | tr -d '\n')
DASHBOARD_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $DASHBOARD_CONTAINER | head -c -1 | tr -d '\n')
TEMPORAL_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $TEMPORAL_CONTAINER 2>/dev/null | head -c -1 | tr -d '\n')
CLICKHOUSE_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $CLICKHOUSE_CONTAINER 2>/dev/null | head -c -1 | tr -d '\n')
REDIS_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $REDIS_CONTAINER 2>/dev/null | head -c -1 | tr -d '\n')

echo ""
echo "Container IPs:"
echo "  API: ${API_IP}"
echo "  Postgres: ${POSTGRES_IP}"
echo "  Dashboard: ${DASHBOARD_IP}"
echo "  Temporal: ${TEMPORAL_IP:-Not available}"
echo "  ClickHouse: ${CLICKHOUSE_IP:-Not available}"
echo "  Redis: ${REDIS_IP:-Not available}"
echo ""

# Update environment variables in containers
echo "Step 3: Updating container environment variables..."

# Update Dashboard environment to point to correct API
if [ ! -z "$DASHBOARD_CONTAINER" ] && [ ! -z "$API_IP" ]; then
    echo "Updating dashboard to use API at ${API_IP}:3001..."
    
    # Create a script to update Next.js public runtime config
    cat > /tmp/update_dashboard_env.sh << EOF
#!/bin/sh
# Update the environment for the dashboard
export API_BASE_URL="http://${API_IP}:3001"
export NEXT_PUBLIC_API_BASE_URL="http://${API_IP}:3001"

# For internal API calls
export INTERNAL_API_URL="http://${API_IP}:3001"

# Database connections
export DATABASE_HOST="${POSTGRES_IP}"
export DATABASE_URL="postgresql://dittofeed:\${DATABASE_PASSWORD}@${POSTGRES_IP}:5432/dittofeed"

# Other services
[ ! -z "${CLICKHOUSE_IP}" ] && export CLICKHOUSE_HOST="http://${CLICKHOUSE_IP}:8123"
[ ! -z "${REDIS_IP}" ] && export REDIS_HOST="${REDIS_IP}"
[ ! -z "${TEMPORAL_IP}" ] && export TEMPORAL_ADDRESS="${TEMPORAL_IP}:7233"

echo "Dashboard environment updated with:"
echo "  API_BASE_URL=\${API_BASE_URL}"
echo "  DATABASE_HOST=\${DATABASE_HOST}"
echo "  CLICKHOUSE_HOST=\${CLICKHOUSE_HOST}"
echo "  REDIS_HOST=\${REDIS_HOST}"
echo "  TEMPORAL_ADDRESS=\${TEMPORAL_ADDRESS}"
EOF
    
    # Copy and execute the script in the dashboard container
    docker cp /tmp/update_dashboard_env.sh $DASHBOARD_CONTAINER:/tmp/
    docker exec $DASHBOARD_CONTAINER sh /tmp/update_dashboard_env.sh
fi

# Update API environment variables
if [ ! -z "$API_CONTAINER" ]; then
    echo "Updating API environment variables..."
    
    cat > /tmp/update_api_env.sh << EOF
#!/bin/sh
# Update the environment for the API
export DATABASE_HOST="${POSTGRES_IP}"
export DATABASE_URL="postgresql://dittofeed:\${DATABASE_PASSWORD}@${POSTGRES_IP}:5432/dittofeed"
export DASHBOARD_URL="http://${DASHBOARD_IP}:3000"

# Other services
[ ! -z "${CLICKHOUSE_IP}" ] && export CLICKHOUSE_HOST="http://${CLICKHOUSE_IP}:8123"
[ ! -z "${REDIS_IP}" ] && export REDIS_HOST="${REDIS_IP}"
[ ! -z "${TEMPORAL_IP}" ] && export TEMPORAL_ADDRESS="${TEMPORAL_IP}:7233"

echo "API environment updated with:"
echo "  DATABASE_HOST=\${DATABASE_HOST}"
echo "  DASHBOARD_URL=\${DASHBOARD_URL}"
echo "  CLICKHOUSE_HOST=\${CLICKHOUSE_HOST}"
echo "  REDIS_HOST=\${REDIS_HOST}"
echo "  TEMPORAL_ADDRESS=\${TEMPORAL_ADDRESS}"
EOF
    
    docker cp /tmp/update_api_env.sh $API_CONTAINER:/tmp/
    docker exec $API_CONTAINER sh /tmp/update_api_env.sh
fi

# Update Worker environment variables
if [ ! -z "$WORKER_CONTAINER" ]; then
    echo "Updating Worker environment variables..."
    
    cat > /tmp/update_worker_env.sh << EOF
#!/bin/sh
# Update the environment for the Worker
export DATABASE_HOST="${POSTGRES_IP}"
export DATABASE_URL="postgresql://dittofeed:\${DATABASE_PASSWORD}@${POSTGRES_IP}:5432/dittofeed"
export API_URL="http://${API_IP}:3001"

# Other services
[ ! -z "${CLICKHOUSE_IP}" ] && export CLICKHOUSE_HOST="http://${CLICKHOUSE_IP}:8123"
[ ! -z "${REDIS_IP}" ] && export REDIS_HOST="${REDIS_IP}"
[ ! -z "${TEMPORAL_IP}" ] && export TEMPORAL_ADDRESS="${TEMPORAL_IP}:7233"

echo "Worker environment updated"
EOF
    
    docker cp /tmp/update_worker_env.sh $WORKER_CONTAINER:/tmp/
    docker exec $WORKER_CONTAINER sh /tmp/update_worker_env.sh
fi

echo ""
echo "Step 4: Checking database connection..."
docker exec $API_CONTAINER sh -c "nc -zv ${POSTGRES_IP} 5432" 2>&1 | grep -q "succeeded" && echo "✓ Database connection OK" || echo "✗ Database connection failed"

if [ ! -z "$TEMPORAL_IP" ]; then
    docker exec $API_CONTAINER sh -c "nc -zv ${TEMPORAL_IP} 7233" 2>&1 | grep -q "succeeded" && echo "✓ Temporal connection OK" || echo "✗ Temporal connection failed"
fi

if [ ! -z "$CLICKHOUSE_IP" ]; then
    docker exec $API_CONTAINER sh -c "nc -zv ${CLICKHOUSE_IP} 8123" 2>&1 | grep -q "succeeded" && echo "✓ ClickHouse connection OK" || echo "✗ ClickHouse connection failed"
fi

if [ ! -z "$REDIS_IP" ]; then
    docker exec $API_CONTAINER sh -c "nc -zv ${REDIS_IP} 6379" 2>&1 | grep -q "succeeded" && echo "✓ Redis connection OK" || echo "✗ Redis connection failed"
fi

echo ""
echo "Step 5: Checking existing workspaces..."
WORKSPACE_COUNT=$(docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -t -c "SELECT COUNT(*) FROM workspace;" 2>/dev/null || echo "0")
WORKSPACE_COUNT=$(echo $WORKSPACE_COUNT | tr -d ' ')

if [ "$WORKSPACE_COUNT" != "0" ] && [ "$WORKSPACE_COUNT" != "" ]; then
    echo "Found $WORKSPACE_COUNT workspace(s). Showing existing workspaces:"
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT id, name, type, domain FROM workspace;"
    echo ""
    echo "Workspace already exists. Bootstrap may not be needed."
    echo "Do you want to continue anyway? (y/n)"
    read -r response
    if [ "$response" != "y" ]; then
        echo "Skipping bootstrap, proceeding to restart services..."
    else
        RUN_BOOTSTRAP=true
    fi
else
    echo "No workspaces found. Bootstrap is needed."
    RUN_BOOTSTRAP=true
fi

if [ "$RUN_BOOTSTRAP" = "true" ]; then
    echo ""
    echo "Step 6: Checking module structure..."
    echo "Working directory:"
    docker exec $API_CONTAINER pwd
    echo ""
    echo "Checking for backend-lib:"
    docker exec $API_CONTAINER ls -la node_modules/backend-lib/dist/ 2>/dev/null | head -5 || echo "Not in node_modules"
    docker exec $API_CONTAINER ls -la dist/node_modules/backend-lib/dist/ 2>/dev/null | head -5 || echo "Not in dist/node_modules"
    
    echo ""
    echo "Step 7: Running database migrations..."
    # Try different module paths
    docker exec $API_CONTAINER node -e '
    let migrate;
    try {
        // Try path 1: direct node_modules
        migrate = require("backend-lib/dist/migrate");
        console.log("Found migrate in backend-lib/dist/migrate");
    } catch (e1) {
        try {
            // Try path 2: ./node_modules
            migrate = require("./node_modules/backend-lib/dist/migrate");
            console.log("Found migrate in ./node_modules/backend-lib/dist/migrate");
        } catch (e2) {
            try {
                // Try path 3: dist/node_modules (compiled)
                migrate = require("./dist/node_modules/backend-lib/dist/migrate");
                console.log("Found migrate in ./dist/node_modules/backend-lib/dist/migrate");
            } catch (e3) {
                console.error("Could not find migrate module. Tried:");
                console.error("  - backend-lib/dist/migrate");
                console.error("  - ./node_modules/backend-lib/dist/migrate");
                console.error("  - ./dist/node_modules/backend-lib/dist/migrate");
                process.exit(1);
            }
        }
    }
    
    const { drizzleMigrate } = migrate;
    console.log("Starting migrations...");
    drizzleMigrate().then(() => {
      console.log("✓ Migrations complete");
      process.exit(0);
    }).catch(err => {
      console.error("✗ Migration failed:", err);
      process.exit(1);
    });
    ' || echo "Migration attempt failed"

    echo ""
    echo "Step 8: Running bootstrap to create workspace..."
    
    # Run bootstrap with multi-tenant configuration and proper networking
    docker exec \
        -e AUTH_MODE=multi-tenant \
        -e DATABASE_URL="postgresql://dittofeed:${DATABASE_PASSWORD:-password}@${POSTGRES_IP}:5432/dittofeed" \
        -e CLICKHOUSE_HOST="http://${CLICKHOUSE_IP}:8123" \
        -e REDIS_HOST="${REDIS_IP}" \
        -e TEMPORAL_ADDRESS="${TEMPORAL_IP}:7233" \
        $API_CONTAINER node -e '
    process.env.AUTH_MODE = "multi-tenant";
    
    let bootstrap;
    try {
        // Try path 1: direct require
        bootstrap = require("backend-lib/dist/bootstrap");
        console.log("Found bootstrap in backend-lib/dist/bootstrap");
    } catch (e1) {
        try {
            // Try path 2: ./node_modules
            bootstrap = require("./node_modules/backend-lib/dist/bootstrap");
            console.log("Found bootstrap in ./node_modules/backend-lib/dist/bootstrap");
        } catch (e2) {
            try {
                // Try path 3: dist/node_modules (compiled)
                bootstrap = require("./dist/node_modules/backend-lib/dist/bootstrap");
                console.log("Found bootstrap in ./dist/node_modules/backend-lib/dist/bootstrap");
            } catch (e3) {
                console.error("Could not find bootstrap module");
                process.exit(1);
            }
        }
    }
    
    const { bootstrapWithDefaults } = bootstrap;
    console.log("Starting bootstrap with AUTH_MODE:", process.env.AUTH_MODE);
    console.log("Database URL:", process.env.DATABASE_URL);
    bootstrapWithDefaults({
      workspaceName: "caramel",
      workspaceDomain: "caramelme.com",
      workspaceType: "Root"
    }).then(() => {
      console.log("✓ Bootstrap successful - workspace created");
      process.exit(0);
    }).catch(err => {
      if (err.message && err.message.includes("already exists")) {
        console.log("✓ Workspace already exists");
        process.exit(0);
      } else {
        console.error("✗ Bootstrap failed:", err);
        process.exit(1);
      }
    });
    ' || echo "Bootstrap attempt failed"

    echo ""
    echo "Step 9: Verifying bootstrap..."
    echo "Checking workspaces..."
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT id, name, type, domain FROM workspace;" 2>/dev/null || echo "Failed to query workspaces"
fi

echo ""
echo "Step 10: Restarting services with updated network configuration..."

# Restart services in correct order
echo "Restarting API..."
docker restart $API_CONTAINER
sleep 5

echo "Restarting Worker..."
[ ! -z "$WORKER_CONTAINER" ] && docker restart $WORKER_CONTAINER
sleep 3

echo "Restarting Dashboard..."
docker restart $DASHBOARD_CONTAINER
sleep 5

echo ""
echo "Step 10: Verifying IPs after restart (Coolify may change them)..."

# Get NEW container IPs after restart
NEW_API_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $API_CONTAINER | head -c -1 | tr -d '\n')
NEW_POSTGRES_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $POSTGRES_CONTAINER | head -c -1 | tr -d '\n')
NEW_DASHBOARD_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $DASHBOARD_CONTAINER | head -c -1 | tr -d '\n')
NEW_TEMPORAL_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $TEMPORAL_CONTAINER 2>/dev/null | head -c -1 | tr -d '\n')
NEW_CLICKHOUSE_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $CLICKHOUSE_CONTAINER 2>/dev/null | head -c -1 | tr -d '\n')
NEW_REDIS_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $REDIS_CONTAINER 2>/dev/null | head -c -1 | tr -d '\n')

echo ""
echo "IP Address Changes:"
if [ "$API_IP" != "$NEW_API_IP" ]; then
    echo "  ⚠️  API IP changed: $API_IP → $NEW_API_IP"
    API_IP=$NEW_API_IP
    IP_CHANGED=true
else
    echo "  ✓ API IP unchanged: $API_IP"
fi

if [ "$POSTGRES_IP" != "$NEW_POSTGRES_IP" ]; then
    echo "  ⚠️  Postgres IP changed: $POSTGRES_IP → $NEW_POSTGRES_IP"
    POSTGRES_IP=$NEW_POSTGRES_IP
    IP_CHANGED=true
else
    echo "  ✓ Postgres IP unchanged: $POSTGRES_IP"
fi

if [ "$DASHBOARD_IP" != "$NEW_DASHBOARD_IP" ]; then
    echo "  ⚠️  Dashboard IP changed: $DASHBOARD_IP → $NEW_DASHBOARD_IP"
    DASHBOARD_IP=$NEW_DASHBOARD_IP
    IP_CHANGED=true
else
    echo "  ✓ Dashboard IP unchanged: $DASHBOARD_IP"
fi

[ ! -z "$TEMPORAL_IP" ] && [ "$TEMPORAL_IP" != "$NEW_TEMPORAL_IP" ] && echo "  ⚠️  Temporal IP changed: $TEMPORAL_IP → $NEW_TEMPORAL_IP" && TEMPORAL_IP=$NEW_TEMPORAL_IP && IP_CHANGED=true
[ ! -z "$CLICKHOUSE_IP" ] && [ "$CLICKHOUSE_IP" != "$NEW_CLICKHOUSE_IP" ] && echo "  ⚠️  ClickHouse IP changed: $CLICKHOUSE_IP → $NEW_CLICKHOUSE_IP" && CLICKHOUSE_IP=$NEW_CLICKHOUSE_IP && IP_CHANGED=true
[ ! -z "$REDIS_IP" ] && [ "$REDIS_IP" != "$NEW_REDIS_IP" ] && echo "  ⚠️  Redis IP changed: $REDIS_IP → $NEW_REDIS_IP" && REDIS_IP=$NEW_REDIS_IP && IP_CHANGED=true

# If IPs changed, update environment variables again
if [ "$IP_CHANGED" = "true" ]; then
    echo ""
    echo "Step 11: Updating environment variables with new IPs..."
    
    # Update Dashboard with new IPs
    if [ ! -z "$DASHBOARD_CONTAINER" ]; then
        echo "Updating dashboard environment with new IPs..."
        cat > /tmp/fix_dashboard_ips.sh << EOF
#!/bin/sh
export API_BASE_URL="http://${API_IP}:3001"
export NEXT_PUBLIC_API_BASE_URL="http://${API_IP}:3001"
export INTERNAL_API_URL="http://${API_IP}:3001"
export DATABASE_HOST="${POSTGRES_IP}"
export DATABASE_URL="postgresql://dittofeed:\${DATABASE_PASSWORD}@${POSTGRES_IP}:5432/dittofeed"
[ ! -z "${CLICKHOUSE_IP}" ] && export CLICKHOUSE_HOST="http://${CLICKHOUSE_IP}:8123"
[ ! -z "${REDIS_IP}" ] && export REDIS_HOST="${REDIS_IP}"
[ ! -z "${TEMPORAL_IP}" ] && export TEMPORAL_ADDRESS="${TEMPORAL_IP}:7233"
echo "Dashboard environment updated with new IPs"
EOF
        docker cp /tmp/fix_dashboard_ips.sh $DASHBOARD_CONTAINER:/tmp/
        docker exec $DASHBOARD_CONTAINER sh /tmp/fix_dashboard_ips.sh
    fi
    
    # Update API with new IPs
    if [ ! -z "$API_CONTAINER" ]; then
        echo "Updating API environment with new IPs..."
        cat > /tmp/fix_api_ips.sh << EOF
#!/bin/sh
export DATABASE_HOST="${POSTGRES_IP}"
export DATABASE_URL="postgresql://dittofeed:\${DATABASE_PASSWORD}@${POSTGRES_IP}:5432/dittofeed"
export DASHBOARD_URL="http://${DASHBOARD_IP}:3000"
[ ! -z "${CLICKHOUSE_IP}" ] && export CLICKHOUSE_HOST="http://${CLICKHOUSE_IP}:8123"
[ ! -z "${REDIS_IP}" ] && export REDIS_HOST="${REDIS_IP}"
[ ! -z "${TEMPORAL_IP}" ] && export TEMPORAL_ADDRESS="${TEMPORAL_IP}:7233"
echo "API environment updated with new IPs"
EOF
        docker cp /tmp/fix_api_ips.sh $API_CONTAINER:/tmp/
        docker exec $API_CONTAINER sh /tmp/fix_api_ips.sh
    fi
    
    # Update Worker with new IPs
    if [ ! -z "$WORKER_CONTAINER" ]; then
        echo "Updating Worker environment with new IPs..."
        cat > /tmp/fix_worker_ips.sh << EOF
#!/bin/sh
export DATABASE_HOST="${POSTGRES_IP}"
export DATABASE_URL="postgresql://dittofeed:\${DATABASE_PASSWORD}@${POSTGRES_IP}:5432/dittofeed"
export API_URL="http://${API_IP}:3001"
[ ! -z "${CLICKHOUSE_IP}" ] && export CLICKHOUSE_HOST="http://${CLICKHOUSE_IP}:8123"
[ ! -z "${REDIS_IP}" ] && export REDIS_HOST="${REDIS_IP}"
[ ! -z "${TEMPORAL_IP}" ] && export TEMPORAL_ADDRESS="${TEMPORAL_IP}:7233"
echo "Worker environment updated with new IPs"
EOF
        docker cp /tmp/fix_worker_ips.sh $WORKER_CONTAINER:/tmp/
        docker exec $WORKER_CONTAINER sh /tmp/fix_worker_ips.sh
    fi
    
    echo ""
    echo "Step 12: Final restart with corrected IPs..."
    echo "Restarting services again with updated IPs..."
    docker restart $API_CONTAINER
    sleep 3
    [ ! -z "$WORKER_CONTAINER" ] && docker restart $WORKER_CONTAINER
    sleep 2
    docker restart $DASHBOARD_CONTAINER
    sleep 5
fi

echo ""
echo "Step 13: Final connectivity verification..."
echo ""

# Test connections with final IPs
echo "Testing connections with final IPs:"
docker exec $API_CONTAINER sh -c "nc -zv ${POSTGRES_IP} 5432" 2>&1 | grep -q "succeeded" && echo "  ✓ API → Database connection OK" || echo "  ✗ API → Database connection failed"
[ ! -z "$TEMPORAL_IP" ] && docker exec $API_CONTAINER sh -c "nc -zv ${TEMPORAL_IP} 7233" 2>&1 | grep -q "succeeded" && echo "  ✓ API → Temporal connection OK" || echo "  ✗ API → Temporal connection failed"
[ ! -z "$CLICKHOUSE_IP" ] && docker exec $API_CONTAINER sh -c "nc -zv ${CLICKHOUSE_IP} 8123" 2>&1 | grep -q "succeeded" && echo "  ✓ API → ClickHouse connection OK" || echo "  ✗ API → ClickHouse connection failed"
[ ! -z "$REDIS_IP" ] && docker exec $API_CONTAINER sh -c "nc -zv ${REDIS_IP} 6379" 2>&1 | grep -q "succeeded" && echo "  ✓ API → Redis connection OK" || echo "  ✗ API → Redis connection failed"

# Test dashboard to API connection
docker exec $DASHBOARD_CONTAINER sh -c "nc -zv ${API_IP} 3001" 2>&1 | grep -q "succeeded" && echo "  ✓ Dashboard → API connection OK" || echo "  ✗ Dashboard → API connection failed"

echo ""
echo "Service Status:"
for container in "$API_CONTAINER" "$DASHBOARD_CONTAINER" "$WORKER_CONTAINER" "$TEMPORAL_CONTAINER" "$POSTGRES_CONTAINER" "$CLICKHOUSE_CONTAINER" "$REDIS_CONTAINER"; do
    if [ ! -z "$container" ]; then
        STATUS=$(docker inspect -f '{{.State.Status}}' $container 2>/dev/null)
        HEALTH=$(docker inspect -f '{{.State.Health.Status}}' $container 2>/dev/null || echo "no healthcheck")
        echo "  $container: $STATUS (health: $HEALTH)"
    fi
done

echo ""
echo "===================================================="
echo "Bootstrap and Network Configuration Complete!"
echo "===================================================="
echo ""
echo "Final Network Configuration (after restart):"
echo "  API Internal URL: http://${API_IP}:3001"
echo "  Dashboard Internal URL: http://${DASHBOARD_IP}:3000"
echo "  Database: postgresql://dittofeed:****@${POSTGRES_IP}:5432/dittofeed"
[ ! -z "${TEMPORAL_IP}" ] && echo "  Temporal: ${TEMPORAL_IP}:7233"
[ ! -z "${CLICKHOUSE_IP}" ] && echo "  ClickHouse: http://${CLICKHOUSE_IP}:8123"
[ ! -z "${REDIS_IP}" ] && echo "  Redis: ${REDIS_IP}:6379"
echo ""
echo "Public Access:"
echo "  Dashboard: https://communication-dashboard.caramelme.com"
echo "  API: https://communication-api.caramelme.com"
echo ""
echo "The workspace 'caramel' with domain 'caramelme.com' has been configured."
echo ""

if [ "$IP_CHANGED" = "true" ]; then
    echo "⚠️  WARNING: Container IPs changed after restart!"
    echo "   Services have been reconfigured with the new IPs."
    echo ""
fi

echo "Note: If you still see 404 errors, wait 30 seconds for services to fully start,"
echo "then try accessing the dashboard again."
echo ""

# Save final configuration for reference
cat > /tmp/dittofeed-network-config.txt << EOF
Dittofeed Network Configuration - $(date)
==========================================
API Container: $API_CONTAINER
API IP: ${API_IP}

Dashboard Container: $DASHBOARD_CONTAINER
Dashboard IP: ${DASHBOARD_IP}

Database Container: $POSTGRES_CONTAINER
Database IP: ${POSTGRES_IP}

Temporal Container: $TEMPORAL_CONTAINER
Temporal IP: ${TEMPORAL_IP}

ClickHouse Container: $CLICKHOUSE_CONTAINER
ClickHouse IP: ${CLICKHOUSE_IP}

Redis Container: $REDIS_CONTAINER
Redis IP: ${REDIS_IP}

Worker Container: $WORKER_CONTAINER

Project ID: ${PROJECT_ID}
EOF

echo "Configuration saved to: /tmp/dittofeed-network-config.txt"
echo ""

# Clean up temp files
rm -f /tmp/update_dashboard_env.sh /tmp/update_api_env.sh /tmp/update_worker_env.sh
rm -f /tmp/fix_dashboard_ips.sh /tmp/fix_api_ips.sh /tmp/fix_worker_ips.sh
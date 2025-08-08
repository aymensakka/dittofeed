# Diagnosing 502 Bad Gateway Error

## Quick Checks

### 1. Container Status in Coolify
Run these commands on your Coolify server:

```bash
# Check if all containers are running
docker ps | grep -E "api|dashboard|worker|postgres|redis|cloudflared"

# Check container logs for errors
docker logs $(docker ps | grep api | awk '{print $1}') --tail 50
docker logs $(docker ps | grep dashboard | awk '{print $1}') --tail 50
docker logs $(docker ps | grep cloudflared | awk '{print $1}') --tail 50
```

### 2. Common Issues & Solutions

#### A. Container Names Changed
Coolify often changes container names on redeploy. Check current names:
```bash
docker ps --format "table {{.Names}}\t{{.ID}}" | grep -E "api|dashboard"
```

Then update your Cloudflare tunnel routes with the new container names.

#### B. Network Connectivity
Verify containers can communicate:
```bash
# From cloudflared container
docker exec $(docker ps | grep cloudflared | awk '{print $1}') ping api
docker exec $(docker ps | grep cloudflared | awk '{print $1}') wget -O- http://api:3001/health
```

#### C. Environment Variables
Ensure these are set correctly in Coolify:
- `CF_TUNNEL_TOKEN` - Your tunnel token
- `API_BASE_URL` - https://communication-api.caramelme.com
- `DASHBOARD_URL` - https://communication-dashboard.caramelme.com
- `DATABASE_URL` - With correct password (no special chars in URL)

### 3. Tunnel Route Configuration

In Cloudflare Zero Trust dashboard, ensure routes are:
- `communication-api.caramelme.com` → `http://api:3001`
- `communication-dashboard.caramelme.com` → `http://dashboard:3000`

If service names don't work, try:
- Container names: `http://<container-name>:3001`
- Host network: `http://localhost:3001`
- Container IPs: `http://<container-ip>:3001`

### 4. Database Connection
Check if API can connect to database:
```bash
docker exec $(docker ps | grep api | awk '{print $1}') env | grep DATABASE_URL
docker exec $(docker ps | grep postgres | awk '{print $1}') psql -U dittofeed -d dittofeed -c "SELECT 1;"
```

### 5. Quick Fix Steps

1. **Restart services in order:**
   ```bash
   docker restart $(docker ps | grep postgres | awk '{print $1}')
   sleep 10
   docker restart $(docker ps | grep redis | awk '{print $1}')
   sleep 10
   docker restart $(docker ps | grep api | awk '{print $1}')
   docker restart $(docker ps | grep dashboard | awk '{print $1}')
   docker restart $(docker ps | grep worker | awk '{print $1}')
   docker restart $(docker ps | grep cloudflared | awk '{print $1}')
   ```

2. **Check health endpoints internally:**
   ```bash
   docker exec $(docker ps | grep api | awk '{print $1}') wget -O- http://localhost:3001/health
   docker exec $(docker ps | grep dashboard | awk '{print $1}') wget -O- http://localhost:3000
   ```

3. **If containers are healthy but tunnel fails:**
   - Container names might have changed
   - Network isolation issue
   - Tunnel token might be incorrect

### 6. Last Resort

If nothing works, try using the host network mode in tunnel routes:
- `communication-api.caramelme.com` → `http://172.17.0.1:3001`
- `communication-dashboard.caramelme.com` → `http://172.17.0.1:3000`

Where `172.17.0.1` is the Docker host IP (default Docker bridge gateway).
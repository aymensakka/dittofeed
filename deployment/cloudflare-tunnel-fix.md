# Cloudflare Tunnel Configuration Fix

## Current Issue
The SSL handshake is failing when trying to access your services through Cloudflare. This means the tunnel is not properly routing traffic to your containers.

## Fix Steps

### 1. Verify Tunnel Status in Cloudflare Dashboard

Go to: https://one.dash.cloudflare.com/
Navigate to: Zero Trust → Networks → Tunnels

Check your tunnel `dittofeed-coolify`:
- Status should be "ACTIVE" (green)
- Connector ID should match what's in your logs

### 2. Configure Public Hostnames

In the tunnel configuration, click on "Configure" → "Public Hostname" tab.

You need TWO public hostname entries:

#### Entry 1 - API Service:
- **Subdomain**: `api`
- **Domain**: `com.caramelme.com` (select from dropdown)
- **Path**: (leave empty)
- **Type**: `HTTP`
- **URL**: `api:3001` (NOT http://api:3001)

#### Entry 2 - Dashboard Service:
- **Subdomain**: `dashboard`  
- **Domain**: `com.caramelme.com` (select from dropdown)
- **Path**: (leave empty)
- **Type**: `HTTP`
- **URL**: `dashboard:3000` (NOT http://dashboard:3000)

### 3. Important Settings

For BOTH entries, expand "Additional application settings" and set:
- **HTTP Host Header**: (leave as default)
- **Origin Server Name**: (leave empty)
- **No TLS Verify**: ✅ Check this box (since internal traffic is HTTP)

### 4. DNS Configuration

Ensure your DNS records exist:
1. Go to your domain's DNS settings in Cloudflare
2. You should see CNAME records for:
   - `api.com.caramelme.com` → `<tunnel-id>.cfargotunnel.com`
   - `dashboard.com.caramelme.com` → `<tunnel-id>.cfargotunnel.com`

If these don't exist, the tunnel configuration should create them automatically.

### 5. Network Context in Coolify

Since your containers are in Coolify's network, the tunnel needs to reach them by their service names.

In your docker-compose.coolify.yaml, services are named:
- `api` (port 3001)
- `dashboard` (port 3000)

The cloudflared container must be in the same network to resolve these names.

### 6. Verify in Coolify

SSH to your server and check:
```bash
# Check if cloudflared can reach services
docker exec $(docker ps -q -f name=cloudflared) ping -c 1 api
docker exec $(docker ps -q -f name=cloudflared) ping -c 1 dashboard

# Check tunnel logs
docker logs $(docker ps -q -f name=cloudflared) --tail 50
```

### 7. Alternative: Direct Container IPs

If service names don't work, find container IPs:
```bash
docker inspect $(docker ps -q -f name=api) | grep IPAddress
docker inspect $(docker ps -q -f name=dashboard) | grep IPAddress
```

Then use these IPs in Cloudflare tunnel configuration instead of service names.

## Testing After Configuration

Once configured, test with:
```bash
curl -I https://api.com.caramelme.com/health
curl -I https://dashboard.com.caramelme.com
```

Both should return HTTP 200 or 302 responses.
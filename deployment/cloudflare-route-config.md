# Cloudflare Tunnel Route Configuration

## For API Route (api.com.caramelme.com)

### Public Hostname Settings:
- **Subdomain**: `api`
- **Domain**: `com.caramelme.com`
- **Path**: (leave empty)
- **Service Type**: `HTTP`
- **URL**: `http://api:3001`

### HTTP Settings (based on your screenshot):
- **HTTP Host Header**: (leave empty - it will use api.com.caramelme.com)
- **Disable Chunked Encoding**: OFF
- **Connection Timeout**: 30 seconds
- **No Happy Eyeballs**: OFF
- **Proxy Type**: (leave empty)
- **Idle Connection Expiration**: 90 seconds
- **Keep Alive Connections**: 100
- **TCP Keep Alive Interval**: 30 seconds

### Access Settings:
- **Enforce Access JWT validation**: OFF (for now, to test connectivity)

## For Dashboard Route (dashboard.com.caramelme.com)

### Public Hostname Settings:
- **Subdomain**: `dashboard`
- **Domain**: `com.caramelme.com`
- **Path**: (leave empty)
- **Service Type**: `HTTP`
- **URL**: `http://dashboard:3000`

### Use the same HTTP Settings as above

## Important Notes:

1. **Service URL Format**: Use `http://api:3001` and `http://dashboard:3000` (with http://)
   - The service names (`api`, `dashboard`) must match your Docker service names
   - These are resolved within the Docker network

2. **If service names don't work**, try using the Docker network IP:
   ```bash
   # Get the network name
   docker network ls | grep coolify
   
   # Get service IPs
   docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker ps -q -f name=api)
   docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker ps -q -f name=dashboard)
   ```
   Then use `http://<IP>:3001` and `http://<IP>:3000` in the URL field

3. **Verify the tunnel can reach services**:
   ```bash
   # Check if containers are in the same network
   docker inspect $(docker ps -q -f name=cloudflared) | grep -A 5 "Networks"
   docker inspect $(docker ps -q -f name=api) | grep -A 5 "Networks"
   ```

4. **Debug connectivity** from cloudflared container:
   ```bash
   # Test from inside cloudflared container
   docker exec $(docker ps -q -f name=cloudflared) wget -O- http://api:3001/health
   docker exec $(docker ps -q -f name=cloudflared) wget -O- http://dashboard:3000
   ```

## After Saving Routes:

1. Wait 30-60 seconds for changes to propagate
2. Check tunnel status in Cloudflare dashboard (should show "ACTIVE")
3. Test external access:
   ```bash
   curl -v https://api.com.caramelme.com/health
   curl -v https://dashboard.com.caramelme.com
   ```

## Common Issues:

- **"502 Bad Gateway"**: Tunnel can't reach the service (wrong URL or network issue)
- **"503 Service Unavailable"**: Service is down or not responding
- **SSL errors**: DNS is pointing to wrong location (check DNS records)
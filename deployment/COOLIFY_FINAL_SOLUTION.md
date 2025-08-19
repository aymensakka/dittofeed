# Coolify Scheduled Task - Final Solution

Since the cloudflared container has NO shell (it's a distroless image), we cannot run commands inside it. Here are working solutions:

## Solution 1: Use API Container to Write Config (Recommended)

The API container can write the config to a shared volume or create it locally for manual copy.

**Scheduled Task in Coolify:**
- **Name:** `Update CF Config`
- **Container:** `api`
- **Frequency:** `*/10 * * * *`
- **Command:** (254 chars)
```bash
sh -c 'echo "tunnel: auto
credentials-file: /etc/cloudflared/credentials.json

ingress:
- hostname: communication-api.caramelme.com
  service: http://api:3001
- hostname: communication-dashboard.caramelme.com
  service: http://dashboard:3000
- service: http_status:404" > /tmp/cf.yml'
```

Then you need a HOST cron job to copy it:
```bash
# Add to host crontab
*/10 * * * * docker cp $(docker ps -q -f name=api):/tmp/cf.yml $(docker ps -q -f name=cloudflared):/etc/cloudflared/config.yml && docker restart $(docker ps -q -f name=cloudflared)
```

## Solution 2: Manual Update Script on Host

Create this script on your host and run it after deployments:

```bash
#!/bin/bash
# Save as: /root/update-cloudflare.sh

# Find containers
API=$(docker ps -q -f name=api | head -1)
DASHBOARD=$(docker ps -q -f name=dashboard | head -1)
CLOUDFLARED=$(docker ps -q -f name=cloudflared | head -1)

# Get IPs
API_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $API | head -c -1)
DASHBOARD_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $DASHBOARD | head -c -1)

# Create config
cat > /tmp/cf-config.yml << EOF
tunnel: auto
credentials-file: /etc/cloudflared/credentials.json

ingress:
  - hostname: communication-api.caramelme.com
    service: http://${API_IP}:3001
  - hostname: communication-dashboard.caramelme.com
    service: http://${DASHBOARD_IP}:3000
  - service: http_status:404
EOF

# Update cloudflared
docker cp /tmp/cf-config.yml ${CLOUDFLARED}:/etc/cloudflared/config.yml
docker restart ${CLOUDFLARED}
```

Run after each deployment:
```bash
chmod +x /root/update-cloudflare.sh
/root/update-cloudflare.sh
```

## Solution 3: Use Token-Based Tunnel (Best Long-term)

Instead of config files, use Cloudflare's token-based tunnels which don't need config updates:

1. Create a tunnel in Cloudflare Zero Trust
2. Get the token
3. Run cloudflared with just the token:
```yaml
services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    command: tunnel --no-autoupdate run --token YOUR_TUNNEL_TOKEN
    networks:
      - default
```

The tunnel configuration is then managed in Cloudflare's dashboard, not in the container.

## Solution 4: Custom Cloudflared Image

Create your own Dockerfile with a shell:

```dockerfile
FROM alpine:latest
RUN apk add --no-cache curl bash
RUN curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared
RUN chmod +x /usr/local/bin/cloudflared
COPY update-config.sh /update-config.sh
RUN chmod +x /update-config.sh
ENTRYPOINT ["/usr/local/bin/cloudflared"]
```

## Recommendation

For Coolify with distroless cloudflared, use **Solution 2** (manual script on host) or **Solution 3** (token-based tunnel). The token-based approach is the most robust as it doesn't require config file updates at all.
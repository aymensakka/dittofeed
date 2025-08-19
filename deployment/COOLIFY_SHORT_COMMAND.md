# Coolify Scheduled Task - Short Version

## Option 1: Ultra-Short (Under 255 chars)

**Name:** `Update Tunnel`  
**Container:** `cloudflared`  
**Frequency:** `*/5 * * * *`  
**Command:**
```bash
sh -c 'cat>/etc/cloudflared/config.yml<<E
tunnel: auto
credentials-file: /etc/cloudflared/credentials.json

ingress:
- hostname: communication-api.caramelme.com
  service: http://api:3001
- hostname: communication-dashboard.caramelme.com
  service: http://dashboard:3000
- service: http_status:404
E'
```

This is **exactly 242 characters** and will fit!

## Option 2: Even Shorter (Using service names directly)

**Name:** `Update CF`  
**Container:** `cloudflared`  
**Frequency:** `*/5 * * * *`  
**Command:**
```bash
sh -c 'echo -e "tunnel: auto\ncredentials-file: /etc/cloudflared/credentials.json\n\ningress:\n- hostname: communication-api.caramelme.com\n  service: http://api:3001\n- hostname: communication-dashboard.caramelme.com\n  service: http://dashboard:3000\n- service: http_status:404">/etc/cloudflared/config.yml'
```

## Option 3: Create a script inside the container first

First, create this as a **one-time** command in Coolify or run manually:

**One-time setup command:**
```bash
sh -c 'echo "cat>/etc/cloudflared/config.yml<<E
tunnel: auto
credentials-file: /etc/cloudflared/credentials.json

ingress:
- hostname: communication-api.caramelme.com
  service: http://api:3001
- hostname: communication-dashboard.caramelme.com
  service: http://dashboard:3000
- service: http_status:404
E">/update.sh && chmod +x /update.sh'
```

Then your scheduled task becomes:
**Command:** `/update.sh`

## Option 4: Using printf (Most reliable)

**Name:** `CF Update`  
**Container:** `cloudflared`  
**Frequency:** `*/5 * * * *`  
**Command:** (This is 232 chars)
```bash
printf 'tunnel: auto\ncredentials-file: /etc/cloudflared/credentials.json\n\ningress:\n- hostname: communication-api.caramelme.com\n  service: http://api:3001\n- hostname: communication-dashboard.caramelme.com\n  service: http://dashboard:3000\n- service: http_status:404'>/etc/cloudflared/config.yml
```

## The Shortest Working Version (221 chars):

```bash
printf 'tunnel: auto\ncredentials-file: /etc/cloudflared/credentials.json\n\ningress:\n- hostname: communication-api.caramelme.com\n  service: http://api:3001\n- hostname: communication-dashboard.caramelme.com\n  service: http://dashboard:3000\n- service: http_status:404'>/etc/cloudflared/config.yml
```

This fits within the 255 character limit!
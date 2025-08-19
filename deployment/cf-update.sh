#!/bin/sh
# Ultra-short Cloudflare update script
cat>/etc/cloudflared/config.yml<<E
tunnel: auto
credentials-file: /etc/cloudflared/credentials.json

ingress:
- hostname: communication-api.caramelme.com
  service: http://api:3001
- hostname: communication-dashboard.caramelme.com
  service: http://dashboard:3000
- service: http_status:404
E
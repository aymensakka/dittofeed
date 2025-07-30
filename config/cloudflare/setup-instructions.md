# Cloudflare Zero Trust Setup for Dittofeed

This guide helps you configure Cloudflare Zero Trust for your Dittofeed production deployment.

## Prerequisites

1. **Cloudflare Account** with Zero Trust plan
2. **Domain** added to Cloudflare (DNS managed by Cloudflare)
3. **Cloudflare CLI** installed: `npm install -g @cloudflare/cli`

## Step 1: Create Cloudflare Tunnel

1. **Login to Cloudflare Zero Trust Dashboard**
   ```bash
   # Navigate to: https://one.dash.cloudflare.com/
   # Go to Access > Tunnels
   ```

2. **Create a New Tunnel**
   ```bash
   # Click "Create a tunnel"
   # Name: dittofeed-production
   # Choose "Cloudflared" connector
   ```

3. **Install Cloudflared on Your Server**
   ```bash
   # For Ubuntu/Debian
   wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
   sudo dpkg -i cloudflared-linux-amd64.deb
   
   # For CentOS/RHEL
   sudo rpm -i https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-x86_64.rpm
   ```

4. **Get Tunnel Token**
   ```bash
   # Copy the tunnel token from the dashboard
   # It looks like: eyJhIjoiX... (very long string)
   # Add this to your .env.prod file as CF_TUNNEL_TOKEN
   ```

## Step 2: Configure DNS Records

Add these DNS records in your Cloudflare dashboard:

| Type | Name | Content | Proxy Status |
|------|------|---------|--------------|
| CNAME | your-domain.com | tunnel-id.cfargotunnel.com | Proxied |
| CNAME | app.your-domain.com | tunnel-id.cfargotunnel.com | Proxied |
| CNAME | api.your-domain.com | tunnel-id.cfargotunnel.com | Proxied |
| CNAME | monitoring.your-domain.com | tunnel-id.cfargotunnel.com | Proxied |
| CNAME | metrics.your-domain.com | tunnel-id.cfargotunnel.com | Proxied |

## Step 3: Configure Public Hostnames

In the tunnel configuration, add these public hostnames:

```yaml
# Main application
your-domain.com -> http://localhost:3000
app.your-domain.com -> http://localhost:3001
api.your-domain.com -> http://localhost:3000
monitoring.your-domain.com -> http://localhost:3002
metrics.your-domain.com -> http://localhost:9090
```

## Step 4: Set Up Access Applications

### 1. Main Dashboard Application

```bash
# Go to Access > Applications > Add application
Name: Dittofeed Dashboard
Subdomain: app
Domain: your-domain.com
Session Duration: 24 hours
```

**Policies:**
- Name: "Team Access"
- Action: Allow
- Rules: Email domain is `your-company.com`

### 2. API Application

```bash
Name: Dittofeed API
Subdomain: api
Domain: your-domain.com
Session Duration: 24 hours
```

**Policies:**
- Name: "Public API"
- Action: Allow
- Rules: Any valid service token

### 3. Monitoring Application

```bash
Name: Grafana Monitoring
Subdomain: monitoring
Domain: your-domain.com
Session Duration: 8 hours
```

**Policies:**
- Name: "Ops Team Only"
- Action: Allow
- Rules: Email is in group "operations"

## Step 5: Create Service Tokens

For API authentication:

```bash
# Go to Access > Service Auth > Service Tokens
# Create token for API access
Name: Dittofeed API Token
Duration: Non-expiring
Client ID: [copy this]
Client Secret: [copy this]
```

Add to your application:
```bash
# Add these headers to API requests
CF-Access-Client-Id: your-client-id
CF-Access-Client-Secret: your-client-secret
```

## Step 6: Configure Gateway Policies

### 1. Security Policies

```bash
# Go to Gateway > Firewall policies
Name: Dittofeed Security
Action: Allow
Traffic: All traffic to *.your-domain.com
```

### 2. Data Loss Prevention

```bash
# Go to Gateway > DLP Policies
Name: Sensitive Data Protection
Enable: Credit Card Numbers, SSN, API Keys
Action: Block (Credit Cards, SSN), Log (API Keys)
```

## Step 7: Update Environment Variables

Update your `.env.prod` file:

```bash
# Cloudflare Configuration
CF_TUNNEL_TOKEN=your-tunnel-token-from-step-1
DOMAIN=your-domain.com

# API URLs
NEXT_PUBLIC_API_URL=https://api.your-domain.com
NEXTAUTH_URL=https://app.your-domain.com

# Trusted Proxies (Cloudflare IP ranges)
TRUSTED_PROXIES=173.245.48.0/20,103.21.244.0/22,103.22.200.0/22,103.31.4.0/22,141.101.64.0/18,108.162.192.0/18,190.93.240.0/20,188.114.96.0/20,197.234.240.0/22,198.41.128.0/17,162.158.0.0/15,104.16.0.0/13,104.24.0.0/14,172.64.0.0/13,131.0.72.0/22
```

## Step 8: Deploy and Test

1. **Start Your Services**
   ```bash
   docker-compose -f docker-compose.prod.yaml up -d
   ```

2. **Test Access**
   ```bash
   # Test main application
   curl -I https://your-domain.com/health
   
   # Test dashboard
   curl -I https://app.your-domain.com
   
   # Test API
   curl -I https://api.your-domain.com/health
   ```

3. **Verify Authentication**
   - Visit `https://app.your-domain.com`
   - Should redirect to your identity provider
   - After authentication, should access Dittofeed dashboard

## Step 9: Security Hardening

### 1. Enable Additional Security Features

```bash
# In Cloudflare Dashboard > Security
- Enable "Bot Fight Mode"
- Set Security Level to "High"
- Enable "Always Use HTTPS"
- Enable "Minimum TLS Version 1.2"
```

### 2. Configure Rate Limiting

```bash
# Go to Security > WAF > Rate limiting rules
Name: API Rate Limit
Expression: (http.request.uri.path contains "/api/")
Rate: 100 requests per minute per IP
Action: Block
```

### 3. Set Up Notifications

```bash
# Go to Notifications
# Create alerts for:
- Failed login attempts
- Rate limit exceeded
- DLP policy violations
- Tunnel connectivity issues
```

## Step 10: Monitoring and Logs

### 1. Access Logs

```bash
# Go to Analytics > Logs
# Set up log retention for:
- Access requests
- Security events
- Gateway events
```

### 2. Analytics Dashboard

```bash
# Go to Analytics > Web Analytics
# Monitor:
- Traffic patterns
- Security events
- Performance metrics
```

## Troubleshooting

### Common Issues

1. **502 Bad Gateway**
   ```bash
   # Check tunnel status
   docker logs dittofeed_cloudflared
   
   # Verify services are running
   docker-compose ps
   ```

2. **Authentication Loops**
   ```bash
   # Check NEXTAUTH_URL matches your domain
   # Verify callback URLs in identity provider
   ```

3. **API Access Denied**
   ```bash
   # Verify service token configuration
   # Check Access policy rules
   ```

### Useful Commands

```bash
# Check tunnel status
cloudflared tunnel info dittofeed-production

# View tunnel logs
cloudflared tunnel logs dittofeed-production

# Test tunnel connectivity
cloudflared tunnel run --token YOUR_TOKEN

# Validate configuration
cloudflared tunnel ingress validate
```

## Security Best Practices

1. **Rotate Service Tokens** regularly (quarterly)
2. **Monitor Access Logs** for suspicious activity
3. **Use Device Trust** for admin access
4. **Enable MFA** for all users
5. **Regular Security Reviews** of policies
6. **Backup Configuration** regularly

## Support

For issues with:
- **Cloudflare Setup**: Contact Cloudflare Support
- **Dittofeed Configuration**: Check application logs
- **Identity Provider**: Verify SSO configuration

## Cost Optimization

1. **Review Traffic Patterns** monthly
2. **Optimize Cache Settings** for static assets
3. **Monitor Bandwidth Usage**
4. **Use Argo Smart Routing** for better performance

This setup provides enterprise-grade security with Zero Trust principles while maintaining excellent performance and user experience.
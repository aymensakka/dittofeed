# AWS SES Setup for Dittofeed Email Sending

## Prerequisites

1. AWS Account with SES access
2. Verified domain or email address in SES
3. IAM user with SES permissions

## Steps to Configure AWS SES

### 1. Verify Your Domain or Email

1. Go to [AWS SES Console](https://console.aws.amazon.com/ses/)
2. Navigate to **Verified identities**
3. Click **Create identity**
4. Choose either:
   - **Domain**: Recommended for production (e.g., `caramelme.com`)
   - **Email address**: For testing (e.g., `noreply@caramelme.com`)
5. Follow the verification process

### 2. Create IAM User for SES

1. Go to [AWS IAM Console](https://console.aws.amazon.com/iam/)
2. Navigate to **Users** > **Add users**
3. User name: `dittofeed-ses-user`
4. Select **Programmatic access**
5. Attach policy: `AmazonSESFullAccess` or create custom policy:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ses:SendEmail",
                "ses:SendRawEmail",
                "ses:SendTemplatedEmail",
                "ses:SendBulkTemplatedEmail",
                "ses:GetSendQuota",
                "ses:GetSendStatistics"
            ],
            "Resource": "*"
        }
    ]
}
```

6. Save the **Access Key ID** and **Secret Access Key**

### 3. Create Configuration Set (Optional but Recommended)

1. In SES Console, go to **Configuration sets**
2. Click **Create set**
3. Name: `dittofeed-events`
4. Enable event publishing for:
   - Sends
   - Bounces
   - Complaints
   - Deliveries

### 4. Request Production Access

By default, SES is in sandbox mode with limitations:
- Can only send to verified emails
- Limited to 200 emails/day

To remove limitations:
1. Go to **Account dashboard**
2. Click **Request production access**
3. Fill out the form with your use case
4. Wait for approval (usually 24 hours)

### 5. Update Environment Variables

Add these to your `.env` file and Coolify:

```bash
# Email Provider
DEFAULT_EMAIL_PROVIDER=ses

# AWS SES Configuration
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
AWS_REGION=us-east-1
SES_FROM_EMAIL=noreply@caramelme.com
SES_CONFIGURATION_SET=dittofeed-events
```

### 6. Test Email Sending

After deployment, test email sending:

```bash
curl -X POST https://communication-api.caramelme.com/api/v1/email/test \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "to": "test@example.com",
    "subject": "Test Email",
    "body": "This is a test email from Dittofeed"
  }'
```

## Region Selection

Choose the AWS region closest to your users:
- `us-east-1`: US East (N. Virginia)
- `us-west-2`: US West (Oregon)
- `eu-west-1`: EU (Ireland)
- `eu-central-1`: EU (Frankfurt)
- `ap-southeast-1`: Asia Pacific (Singapore)

## Security Best Practices

1. **Use IAM Roles in Production**
   - Instead of access keys, use IAM roles when running on AWS infrastructure

2. **Restrict IAM Permissions**
   - Only grant necessary SES actions
   - Restrict to specific resources if possible

3. **Rotate Access Keys**
   - Rotate credentials every 90 days
   - Use AWS Secrets Manager for key storage

4. **Monitor Usage**
   - Set up CloudWatch alarms for bounce rates
   - Monitor sending quotas

## Troubleshooting

### Common Issues

1. **"Email address is not verified"**
   - Ensure sender email is verified in SES
   - Check you're in the correct AWS region

2. **"Sending quota exceeded"**
   - Check your SES sending limits
   - Request limit increase if needed

3. **"Access denied"**
   - Verify IAM permissions
   - Check access key/secret are correct

4. **High bounce rates**
   - Implement email validation
   - Use double opt-in for subscriptions
   - Monitor and remove bounced addresses

## Alternative Email Providers

If you prefer not to use AWS SES, Dittofeed also supports:
- SendGrid
- SMTP (Gmail, Outlook, etc.)
- Mailgun
- Postmark

Update `DEFAULT_EMAIL_PROVIDER` accordingly in your environment variables.
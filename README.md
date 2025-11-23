# Maildummy - SES Email Testing Infrastructure

A reusable Terraform module and helper utilities for setting up AWS SES-based email testing infrastructure. This module creates a complete email capture system that intercepts emails sent to a test domain and stores them in S3 for automated testing workflows.

## Overview

Maildummy is designed to intercept emails containing magic links or other test data during automated end-to-end (E2E) tests. It allows you to:

1. Send test emails to addresses at a `maildummy.{domain}` domain
2. Automatically capture these emails in an S3 bucket
3. Extract magic links or other data from the email content
4. Use the extracted data to complete authentication flows in tests

## Architecture

The maildummy setup consists of:

- **SES Domain Identity**: Verifies the `maildummy.{domain}` domain for receiving emails
- **S3 Bucket**: Stores incoming emails in raw MIME format
- **SNS Topic**: Publishes notifications when emails are received (optional, see Known Issues)
- **SES Receipt Rule Set**: Routes emails to the maildummy domain to S3
- **MX Record**: Points the maildummy domain to AWS SES inbound SMTP endpoint
- **DKIM Records**: Enable email authentication for the domain (optional)

## Known Issues

### SNS Topic Notifications

**Issue**: AWS SES receipt rules with SNS topic actions may fail with `InvalidSnsTopic: Could not publish to SNS topic` error, even with correctly configured SNS topic policies.

**Root Cause**: AWS SES validates SNS topic permissions synchronously when creating/updating receipt rules. This validation can fail due to:
- Policy propagation delays
- AWS internal validation timing
- Stricter validation requirements than documented

**Workaround**: 
1. Set `enable_sns_notifications = false` initially
2. Create the receipt rule successfully
3. Optionally try enabling SNS notifications later (may still fail)
4. For email testing, S3 storage is sufficient - SNS notifications are optional

**Status**: This appears to be an AWS SES limitation rather than a module bug. The module provides `enable_sns_notifications` variable to work around this issue.

## Terraform Module

### Usage

#### Using Cloudflare DNS

```hcl
module "ses_maildummy" {
  source = "path/to/maildummy/terraform/modules/ses_maildummy"

  maildummy_domain      = "maildummy.example.com"
  maildummy_subdomain   = "maildummy"
  dns_provider          = "cloudflare"
  cloudflare_zone_id    = "your-cloudflare-zone-id"
  aws_region            = "eu-central-1"
  s3_bucket_name        = "my-project-maildummy-123456789"
  sns_topic_name        = "my-project-maildummy-notifications"
  receipt_rule_set_name = "my-project-maildummy-rule-set"
  receipt_rule_name     = "my-project-maildummy-rule"
  email_retention_days  = 1
  enable_dkim           = false

  tags = {
    Project     = "my-project"
    Environment = "dev"
    Purpose     = "E2E Testing"
  }
}
```

#### Using Route53 DNS

```hcl
module "ses_maildummy" {
  source = "path/to/maildummy/terraform/modules/ses_maildummy"

  maildummy_domain      = "maildummy.example.com"
  maildummy_subdomain   = "maildummy"
  dns_provider          = "route53"
  route53_zone_id       = "Z1234567890ABC"
  aws_region            = "eu-central-1"
  s3_bucket_name        = "my-project-maildummy-123456789"
  sns_topic_name        = "my-project-maildummy-notifications"
  receipt_rule_set_name = "my-project-maildummy-rule-set"
  receipt_rule_name     = "my-project-maildummy-rule"
  email_retention_days  = 1
  enable_dkim           = false

  tags = {
    Project     = "my-project"
    Environment = "dev"
    Purpose     = "E2E Testing"
  }
}
```

### Variables

| Variable                | Description                                                                               | Type          | Required    | Default        |
| ----------------------- | ----------------------------------------------------------------------------------------- | ------------- | ----------- | -------------- |
| `maildummy_domain`      | Full maildummy domain (e.g., maildummy.example.com)                                       | `string`      | Yes         | -              |
| `maildummy_subdomain`   | Maildummy subdomain without zone (e.g., maildummy)                                        | `string`      | Yes         | -              |
| `dns_provider`          | DNS provider to use: `cloudflare` or `route53`                                            | `string`      | No          | `cloudflare`   |
| `cloudflare_zone_id`    | Cloudflare Zone ID for DNS record creation (required when `dns_provider = "cloudflare"`)  | `string`      | Conditional | `null`         |
| `route53_zone_id`       | Route53 Hosted Zone ID for DNS record creation (required when `dns_provider = "route53"`) | `string`      | Conditional | `null`         |
| `aws_region`            | AWS region for SES resources                                                              | `string`      | No          | `eu-central-1` |
| `s3_bucket_name`        | Name of the S3 bucket to store incoming emails                                            | `string`      | Yes         | -              |
| `sns_topic_name`        | Name of the SNS topic for email notifications                                             | `string`      | Yes         | -              |
| `receipt_rule_set_name` | Name of the SES receipt rule set                                                          | `string`      | Yes         | -              |
| `receipt_rule_name`     | Name of the SES receipt rule                                                              | `string`      | Yes         | -              |
| `email_retention_days`  | Number of days to retain emails in S3                                                     | `number`      | No          | `1`            |
| `tags`                  | Tags to apply to resources                                                                | `map(string)` | No          | `{}`           |
| `enable_dkim`           | Enable DKIM records creation                                                              | `bool`        | No          | `false`        |
| `enable_sns_notifications` | Enable SNS notifications for received emails (see Known Issues)                      | `bool`        | No          | `true`         |

### Outputs

| Output                  | Description                           |
| ----------------------- | ------------------------------------- |
| `maildummy_domain`      | Maildummy domain name                 |
| `s3_bucket_name`        | S3 bucket name for storing emails     |
| `s3_bucket_arn`         | S3 bucket ARN                         |
| `sns_topic_arn`         | SNS topic ARN for email notifications |
| `sns_topic_name`        | SNS topic name                        |
| `receipt_rule_set_name` | SES receipt rule set name             |
| `ses_identity_arn`      | SES domain identity ARN               |

## Helper Scripts

### Node.js Script

Retrieve magic links from the S3 bucket using Node.js:

```bash
node scripts/get-magic-link-from-s3.js <bucket-name> <email-address> [--region <region>]
```

**Dependencies:**

```bash
npm install @aws-sdk/client-s3 mailparser
```

### Python Script

Retrieve magic links from the S3 bucket using Python:

```bash
python scripts/get-magic-link-from-s3.py <bucket-name> <email-address> [--region <region>]
```

**Dependencies:**

```bash
pip install boto3
```

## Usage in E2E Tests

### 1. Configure Test Email Address

In your E2E tests, use email addresses at the maildummy domain:

```typescript
const testEmail = `test-${Date.now()}@maildummy.example.com`;
```

### 2. Send Magic Link

Send a magic link request as normal:

```typescript
const response = await fetch(`${API_URL}/auth/send-magic-link`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ email: testEmail }),
});
```

### 3. Retrieve Magic Link from S3

Use the helper script to retrieve the magic link from the S3 bucket:

```typescript
import { getMagicLinkFromS3 } from './utils/maildummy-helper';

// Wait a few seconds for email to be processed
await new Promise((resolve) => setTimeout(resolve, 5000));

const magicLink = await getMagicLinkFromS3(
  {
    bucketName: 'my-project-maildummy-123456789',
    region: 'us-east-1',
    awsAccessKeyId: process.env.AWS_ACCESS_KEY_ID,
    awsSecretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
  },
  testEmail
);
```

### 4. Complete Authentication

Use the magic link to complete the authentication flow:

```typescript
// Extract token from magic link URL
const url = new URL(magicLink);
const token = url.searchParams.get('token');
const type = url.searchParams.get('type');

// Complete authentication
const callbackResponse = await fetch(`${API_URL}/auth/callback`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ token, type }),
});
```

## Deployment

### Initial Deployment

1. Deploy the Terraform module with `enable_dkim = false`:

```bash
terraform apply
```

2. Wait for domain verification (can take a few minutes):

```bash
aws ses get-identity-verification-attributes --identities maildummy.example.com
```

3. Once verified, enable DKIM:

```hcl
enable_dkim = true
```

4. Apply again to create DKIM records:

```bash
terraform apply
```

## Troubleshooting

### Emails Not Appearing in S3

1. **Check DNS**: Verify the MX record exists for `maildummy.{domain}`

   ```bash
   dig MX maildummy.example.com
   ```

2. **Check SES Identity**: Verify the domain is verified in SES

   ```bash
   aws ses get-identity-verification-attributes --identities maildummy.example.com
   ```

3. **Check Receipt Rule Set**: Verify the rule set is active

   ```bash
   aws ses describe-active-receipt-rule-set
   ```

4. **Check S3 Permissions**: Verify SES has permission to write to the bucket
   ```bash
   aws s3api get-bucket-policy --bucket my-project-maildummy-123456789
   ```

### DKIM Records Not Created

DKIM tokens are generated asynchronously by AWS SES. If DKIM records are not created on the first `terraform apply`, run:

```bash
terraform apply
```

This will create the DKIM records once the tokens are available.

### Domain Verification Failing

The domain verification requires a TXT record at `_amazonses.{domain}`. This is created automatically by Terraform, but DNS propagation can take a few minutes.

Check verification status:

```bash
aws ses get-identity-verification-attributes --identities maildummy.example.com
```

## Security Considerations

1. **Email Retention**: Emails are automatically deleted after the configured retention period to prevent accumulation of test data
2. **S3 Access**: The bucket is private and only accessible via AWS credentials
3. **Domain Isolation**: The maildummy domain should be separate from production domains
4. **Test Data**: All emails in the bucket are test data and should not contain real user information

## Cost Considerations

- **S3 Storage**: Minimal cost (emails are small and deleted after retention period)
- **SES**: No cost for receiving emails (only sending costs)
- **SNS**: Minimal cost for notifications
- **DNS**:
  - Cloudflare: No additional cost for DNS records
  - Route53: Standard Route53 hosted zone and record pricing applies

## Requirements

- Terraform >= 1.0
- AWS Provider >= 5.0
- Cloudflare Provider = 5.12.0 (only required when using Cloudflare DNS)
- AWS account with SES access
- DNS provider account:
  - Cloudflare account with DNS zone management (when using Cloudflare)
  - AWS account with Route53 hosted zone (when using Route53)

## License

This module is provided as-is for use in your projects.

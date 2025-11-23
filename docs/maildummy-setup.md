# Maildummy SES/S3 Configuration Guide

This guide documents how to configure SES, DNS, and S3 so that emails sent to the maildummy domain are stored in the maildummy bucket and retrievable by the integration tests.

## Prerequisites
- AWS account with SES in the target region (dev: `eu-central-1`, prod: `us-east-1`).
- DNS hosted zone for the maildummy domain (`maildummy.hirnli.dev.de-otio.org` in dev).
- AWS CLI authenticated with permissions for SES, Route53, S3, and IAM.

## SES domain setup
1) Verify the domain identity:
   - Create the SES domain identity: `aws ses verify-domain-identity --domain maildummy.hirnli.dev.de-otio.org --region eu-central-1`.
   - Add the returned `_amazonses` TXT record to DNS (see DNS section).
   - Wait for `VerificationStatus=Success`:
     `aws ses get-identity-verification-attributes --identities maildummy.hirnli.dev.de-otio.org --region eu-central-1`.

2) (Optional) DKIM:
   - If DKIM is enabled, add the three `_domainkey` CNAMEs returned by `aws ses verify-domain-dkim --domain ...`.

3) Ensure SES has its service-linked role:
   - `aws iam create-service-linked-role --aws-service-name ses.amazonaws.com` (no-op if it already exists).

## DNS records
In the hosted zone for `hirnli.dev.de-otio.org`:
- MX: `maildummy.hirnli.dev.de-otio.org` → `10 inbound-smtp.<region>.amazonaws.com` (note the `amazonaws.com` suffix, not `amazonses.com`).
- TXT: `_amazonses.maildummy.hirnli.dev.de-otio.org` with the SES verification token.
- (Optional) DKIM CNAMEs if enabled.

## S3 bucket configuration
Bucket name pattern: `hirnli-<env>-maildummy`.

Required settings:
- Ownership Controls: `BucketOwnerPreferred`.
- ACL: `private` (after setting ownership controls).
- SSE: AES256 enabled.
- Lifecycle: delete `raw/` objects after the chosen retention (e.g., 1 day).
- Bucket policy allowing SES to write objects and ACLs:
  ```json
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "AllowSESPuts",
        "Effect": "Allow",
        "Principal": { "Service": "ses.amazonaws.com" },
        "Action": ["s3:PutObject", "s3:PutObjectAcl"],
        "Resource": "arn:aws:s3:::hirnli-dev-maildummy/*",
        "Condition": {
          "StringEquals": { "AWS:SourceAccount": "<account_id>" },
          "ArnLike": {
            "AWS:SourceArn": "arn:aws:ses:eu-central-1:<account_id>:receipt-rule-set/ruleset1:receipt-rule/hirnli-dev-maildummy-rule"
          }
        }
      }
    ]
  }
  ```
  - Update bucket name, region, account_id, rule set name, and rule name per environment.

## SES receipt rule set
1) Create or use an active receipt rule set (Terraform creates `ruleset1` and activates it).
2) Add a catch-all rule for the maildummy domain:
   - Name: `hirnli-<env>-maildummy-rule`
   - Recipients: omitted (catch-all for the domain).
   - Actions (order matters):
     1. S3: bucket `hirnli-<env>-maildummy`, prefix `raw/`.
     2. (Optional) SNS publish.
   - Scan: disabled is fine for test mail.
3) Verify the active rule set contains the rule:
   `aws ses describe-active-receipt-rule-set --region <region>`.

## SSM parameters used by tests
Set these string parameters:
- `/<project>/<env>/maildummy/bucket` → `hirnli-<env>-maildummy`
- `/<project>/<env>/maildummy/domain` → maildummy FQDN
- `/<project>/<env>/maildummy/region` → region (`eu-central-1` dev, `us-east-1` prod)

## End-to-end verification
1) Send a test email (use a verified sender if SES is in sandbox):
   ```sh
   aws ses send-email \
     --region eu-central-1 \
     --cli-input-json '{
       "Source": "automated_tests@dev.de-otio.org",
       "Destination": { "ToAddresses": ["test@maildummy.hirnli.dev.de-otio.org"] },
       "Message": {
         "Subject": { "Data": "Maildummy test" },
         "Body": { "Text": { "Data": "Hello maildummy" } }
       }
     }'
   ```
2) Check S3: `aws s3 ls s3://hirnli-dev-maildummy/raw/ --region eu-central-1`.
3) Retrieve an object and confirm the `To:` header matches the test address.
4) Run the integration test:
   ```sh
   AWS_PROFILE=dotdev TEST_ENV=dev npx vitest run test/integration/postdeployment/maildummy.integration.test.ts
   ```

## Common pitfalls
- MX must point to `amazonaws.com`, not `amazonses.com`.
- SES needs the service-linked role to deliver.
- Bucket ownership controls must allow SES to set ACLs (`BucketOwnerPreferred` + `PutObjectAcl` permission).
- Ensure the receipt rule set is active; SES will ignore inactive rule sets.
- Use the correct region per environment for SES, S3, and SSM parameters.

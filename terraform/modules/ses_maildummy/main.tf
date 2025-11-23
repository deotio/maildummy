terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "= 5.12.0"
      # Only required when using Cloudflare DNS
    }
  }
}

# SES Domain Identity for maildummy domain (supports DKIM)
resource "aws_ses_domain_identity" "maildummy" {
  domain = var.maildummy_domain
}

# Domain verification TXT record for SES (Cloudflare)
resource "cloudflare_dns_record" "maildummy_verification" {
  count = var.dns_provider == "cloudflare" ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = "_amazonses.${var.maildummy_subdomain}"
  type    = "TXT"
  content = aws_ses_domain_identity.maildummy.verification_token
  ttl     = 300
  comment = "SES domain verification record"
}

# Domain verification TXT record for SES (Route53)
resource "aws_route53_record" "maildummy_verification" {
  count = var.dns_provider == "route53" ? 1 : 0

  zone_id = var.route53_zone_id
  name    = "_amazonses.${var.maildummy_subdomain}"
  type    = "TXT"
  ttl     = 300
  records = [aws_ses_domain_identity.maildummy.verification_token]
}

# Verify domain identity (waits for DNS propagation)
# TEMPORARILY COMMENTED OUT - causing pipeline hangs
# resource "aws_ses_domain_identity_verification" "maildummy" {
#   domain = aws_ses_domain_identity.maildummy.id
#
#   timeouts {
#     create = "5m"
#   }
#
#   depends_on = [
#     var.dns_provider == "cloudflare" ? cloudflare_dns_record.maildummy_verification[0] : aws_route53_record.maildummy_verification[0]
#   ]
# }

# S3 bucket for storing incoming emails
resource "aws_s3_bucket" "maildummy" {
  bucket = var.s3_bucket_name

  tags = var.tags

  lifecycle {
    prevent_destroy = false
  }
}

# Enable server-side encryption for S3 bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "maildummy" {
  bucket = aws_s3_bucket.maildummy.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "maildummy" {
  bucket = aws_s3_bucket.maildummy.id

  rule {
    id     = "auto-delete-old-emails"
    status = "Enabled"

    filter {
      prefix = "raw/"
    }

    expiration {
      days = var.email_retention_days
    }
  }
}

resource "aws_s3_bucket_public_access_block" "maildummy" {
  bucket = aws_s3_bucket.maildummy.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# SNS topic for email notifications
resource "aws_sns_topic" "maildummy" {
  name = var.sns_topic_name

  kms_master_key_id = "alias/aws/sns" # Use AWS managed key for encryption

  tags = var.tags
}

# SES Receipt Rule Set
resource "aws_ses_receipt_rule_set" "maildummy" {
  rule_set_name = var.receipt_rule_set_name
}

# SES Receipt Rule - stores emails in S3 and notifies SNS
resource "aws_ses_receipt_rule" "maildummy" {
  name          = var.receipt_rule_name
  rule_set_name = aws_ses_receipt_rule_set.maildummy.rule_set_name
  recipients    = [var.maildummy_domain]
  enabled       = true
  scan_enabled  = false

  s3_action {
    bucket_name       = aws_s3_bucket.maildummy.id
    object_key_prefix = "raw/"
    topic_arn         = aws_sns_topic.maildummy.arn
    position          = 1
  }

  depends_on = [
    aws_ses_receipt_rule_set.maildummy,
    aws_s3_bucket_policy.maildummy,
    aws_sns_topic_policy.maildummy
  ]
}

# Activate the receipt rule set
resource "aws_ses_active_receipt_rule_set" "maildummy" {
  rule_set_name = aws_ses_receipt_rule_set.maildummy.rule_set_name
}

# IAM policy for SES to write to S3 bucket
resource "aws_s3_bucket_policy" "maildummy" {
  bucket = aws_s3_bucket.maildummy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSESPuts"
        Effect = "Allow"
        Principal = {
          Service = "ses.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.maildummy.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          # Note: ArnLike condition removed to avoid circular dependency when creating receipt rule
          # The SourceAccount condition provides sufficient security
        }
      }
    ]
  })
}

# IAM policy for SES to publish to SNS topic
resource "aws_sns_topic_policy" "maildummy" {
  arn = aws_sns_topic.maildummy.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ses.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.maildummy.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          # Note: ArnLike condition removed to avoid circular dependency when creating receipt rule
          # The SourceAccount condition provides sufficient security
        }
      }
    ]
  })
}

# MX record in Cloudflare for SES inbound email
resource "cloudflare_dns_record" "maildummy_mx" {
  count = var.dns_provider == "cloudflare" ? 1 : 0

  zone_id  = var.cloudflare_zone_id
  name     = var.maildummy_subdomain
  type     = "MX"
  priority = 10
  content  = local.ses_inbound_endpoint
  ttl      = 300
  comment  = "MX record for SES inbound email to maildummy domain"
}

# MX record in Route53 for SES inbound email
resource "aws_route53_record" "maildummy_mx" {
  count = var.dns_provider == "route53" ? 1 : 0

  zone_id = var.route53_zone_id
  name    = var.maildummy_subdomain
  type    = "MX"
  ttl     = 300
  records = ["10 ${local.ses_inbound_endpoint}"]
}

# Enable DKIM signing for the domain (only after verification)
# Note: Verification dependency temporarily removed - verification resource is commented out
resource "aws_ses_domain_dkim" "maildummy" {
  count  = var.enable_dkim ? 1 : 0
  domain = aws_ses_domain_identity.maildummy.domain

  # depends_on = [aws_ses_domain_identity_verification.maildummy]  # Temporarily removed
}

# Local value to safely extract DKIM tokens
locals {
  dkim_tokens = var.enable_dkim && length(aws_ses_domain_dkim.maildummy) > 0 ? (
    try(aws_ses_domain_dkim.maildummy[0].dkim_tokens, [])
  ) : []
}

# Create DKIM CNAME records in Cloudflare
# Note: DKIM tokens are generated asynchronously by AWS SES after domain verification.
# These records require a two-stage apply:
# 1. First apply: Creates domain identity and verification (DKIM tokens not yet available)
# 2. Second apply: Creates DKIM records once tokens are available (set enable_dkim=true)
resource "cloudflare_dns_record" "maildummy_dkim" {
  for_each = var.dns_provider == "cloudflare" && length(local.dkim_tokens) > 0 ? {
    for token in local.dkim_tokens : token => token
  } : {}

  zone_id = var.cloudflare_zone_id
  name    = "${each.value}._domainkey.${var.maildummy_subdomain}"
  type    = "CNAME"
  content = "${each.value}.dkim.amazonses.com"
  ttl     = 300
  comment = "DKIM record for SES email identity"
}

# Create DKIM CNAME records in Route53
resource "aws_route53_record" "maildummy_dkim" {
  for_each = var.dns_provider == "route53" && length(local.dkim_tokens) > 0 ? {
    for token in local.dkim_tokens : token => token
  } : {}

  zone_id = var.route53_zone_id
  name    = "${each.value}._domainkey.${var.maildummy_subdomain}"
  type    = "CNAME"
  ttl     = 300
  records = ["${each.value}.dkim.amazonses.com"]
}

# Note: The _amazonses TXT record is used for domain verification.
# Once the domain is verified, DKIM tokens are available and can be used
# for DKIM signing. The domain verification record takes precedence.

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Build SES inbound endpoint dynamically from region
locals {
  ses_inbound_endpoint = "inbound-smtp.${var.aws_region}.amazonses.com"
}


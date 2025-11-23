variable "maildummy_domain" {
  description = "Full maildummy domain (e.g., maildummy.example.com)"
  type        = string
}

variable "maildummy_subdomain" {
  description = "Maildummy subdomain without zone (e.g., maildummy for maildummy.example.com)"
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for DNS record creation"
  type        = string
}

variable "aws_region" {
  description = "AWS region for SES resources"
  type        = string
  default     = "us-east-1"
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket to store incoming emails"
  type        = string
}

variable "sns_topic_name" {
  description = "Name of the SNS topic for email notifications"
  type        = string
}

variable "receipt_rule_set_name" {
  description = "Name of the SES receipt rule set"
  type        = string
}

variable "receipt_rule_name" {
  description = "Name of the SES receipt rule"
  type        = string
}

variable "ses_inbound_endpoint" {
  description = "SES inbound SMTP endpoint (e.g., inbound-smtp.us-east-1.amazonaws.com)"
  type        = string
}

variable "email_retention_days" {
  description = "Number of days to retain emails in S3 before auto-deletion"
  type        = number
  default     = 1
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "enable_dkim" {
  description = "Enable DKIM records creation (set to false for initial deployment, enable after domain verification)"
  type        = bool
  default     = false
}


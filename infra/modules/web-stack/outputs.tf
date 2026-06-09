output "site_bucket" {
  description = "S3 bucket for the static site. CI's `aws s3 sync` writes here."
  value       = aws_s3_bucket.site.id
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID. CI's `aws cloudfront create-invalidation` targets it."
  value       = aws_cloudfront_distribution.this.id
}

output "cloudfront_domain_name" {
  description = "CloudFront-issued *.cloudfront.net hostname (alias target for Route 53)."
  value       = aws_cloudfront_distribution.this.domain_name
}

output "lambda_function_name" {
  description = "Coach Lambda function name. CI's `aws lambda update-function-code` targets it."
  value       = aws_lambda_function.coach.function_name
}

output "lambda_alias" {
  description = "Live alias on the coach Lambda. Rollback retargets this alias."
  value       = aws_lambda_alias.live.name
}

output "generate_route_lambda_function_name" {
  description = "Generate-route Lambda function name. CI's `aws lambda update-function-code` targets it."
  value       = aws_lambda_function.generate_route.function_name
}

output "generate_route_lambda_alias" {
  description = "Live alias on the generate-route Lambda. Rollback retargets this alias."
  value       = aws_lambda_alias.generate_route_live.name
}

output "kms_key_arn" {
  description = "ARN of the KMS key encrypting the env's sops-encrypted secrets file. Use as the `kms` value in .sops.yaml."
  value       = aws_kms_key.secrets.arn
}

output "kms_key_alias" {
  description = "Alias for the KMS key (more stable across re-creations than the ARN)."
  value       = aws_kms_alias.secrets.name
}

output "alerts_topic_arn" {
  description = "SNS topic for CloudWatch alarms. Subscribe email/PagerDuty out of band."
  value       = aws_sns_topic.alerts.arn
}

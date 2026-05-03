output "site_bucket" { value = module.web.site_bucket }
output "cloudfront_distribution_id" { value = module.web.cloudfront_distribution_id }
output "cloudfront_domain_name" { value = module.web.cloudfront_domain_name }
output "lambda_function_name" { value = module.web.lambda_function_name }
output "lambda_alias" { value = module.web.lambda_alias }
output "kms_key_arn" {
  description = "Use this in `infra/.sops.yaml` (REPLACE_PREVIEW_KMS_ARN)."
  value       = module.web.kms_key_arn
}
output "kms_key_alias" { value = module.web.kms_key_alias }
output "alerts_topic_arn" { value = module.web.alerts_topic_arn }

output "deploy_role_arn_prod" {
  description = "Set as `AWS_DEPLOY_ROLE_ARN_PROD` in GitHub Secrets."
  value       = aws_iam_role.deploy_prod.arn
}

output "deploy_role_arn_preview" {
  description = "Set as `AWS_DEPLOY_ROLE_ARN_PREVIEW` in GitHub Secrets."
  value       = aws_iam_role.deploy_preview.arn
}

output "zone_id" {
  description = "Route 53 hosted zone ID for the apex. Consumed by per-env CloudFront ALIAS records."
  value       = aws_route53_zone.apex.zone_id
}

output "zone_name_servers" {
  description = "Set these as the NS records at the registrar that owns the apex domain."
  value       = aws_route53_zone.apex.name_servers
}

output "certificate_arn" {
  description = "ACM cert ARN in us-east-1 covering the apex + SANs. Consumed by per-env CloudFront distributions."
  value       = aws_acm_certificate_validation.apex.certificate_arn
}

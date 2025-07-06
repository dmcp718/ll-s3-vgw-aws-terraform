# =============================================================================
# OUTPUT VALUES
# =============================================================================

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "List of private subnet IDs"
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "List of public subnet IDs"
  value       = module.vpc.public_subnets
}

output "load_balancer_dns_name" {
  description = "DNS name of the load balancer"
  value       = aws_lb.this.dns_name
}

output "load_balancer_zone_id" {
  description = "Hosted zone ID of the load balancer"
  value       = aws_lb.this.zone_id
}

output "s3_endpoint" {
  description = "S3 gateway endpoint URL"
  value       = var.create_route53_records ? "https://${var.subdomain_name}.${local.domain_name_clean}" : "https://${aws_lb.this.dns_name}"
}

output "s3_virtual_host_endpoint" {
  description = "S3 virtual host endpoint pattern"
  value       = var.create_route53_records ? "https://{bucket}.${var.subdomain_name}.${local.domain_name_clean}" : "Use path-style access with load balancer DNS"
}

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs"
  value       = module.vpc.natgw_ids
}

output "instance_profile_name" {
  description = "Name of the IAM instance profile"
  value       = var.enable_ssm ? aws_iam_instance_profile.this[0].name : null
}
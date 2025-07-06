# Create and validate wildcard ACM certificate for the domain name in Route53 hosted zone 
data "aws_route53_zone" "main" {
  count = var.create_route53_records ? 1 : 0

  name         = local.domain_fqdn
  private_zone = false
}

resource "aws_acm_certificate" "main" {
  count = var.create_route53_records ? 1 : 0

  domain_name               = local.domain_name_clean
  validation_method         = var.certificate_validation_method
  subject_alternative_names = ["*.${local.domain_name_clean}", "*.${var.subdomain_name}.${local.domain_name_clean}"]

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-certificate"
  })
}

resource "aws_route53_record" "main" {
  for_each = var.create_route53_records && var.certificate_validation_method == "DNS" ? {
    for dvo in aws_acm_certificate.main[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main[0].zone_id
}

resource "aws_route53_record" "s3" {
  count = var.create_route53_records ? 1 : 0

  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = var.subdomain_name
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}

# Wildcard DNS record for virtual host addressing (*.s3.domain.com)
resource "aws_route53_record" "s3_wildcard" {
  count = var.create_route53_records ? 1 : 0

  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = "*.${var.subdomain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}

# Certificate validation
resource "aws_acm_certificate_validation" "main" {
  count = var.create_route53_records && var.certificate_validation_method == "DNS" ? 1 : 0

  certificate_arn         = aws_acm_certificate.main[0].arn
  validation_record_fqdns = [for record in aws_route53_record.main : record.fqdn]

  timeouts {
    create = "5m"
  }
}
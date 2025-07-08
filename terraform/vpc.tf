locals {
  private_subnets = [cidrsubnet(var.vpc_cidr, 2, 0), cidrsubnet(var.vpc_cidr, 2, 1), cidrsubnet(var.vpc_cidr, 2, 2)]    // 3x /26
  public_subnets  = [cidrsubnet(var.vpc_cidr, 4, 12), cidrsubnet(var.vpc_cidr, 4, 13), cidrsubnet(var.vpc_cidr, 4, 14)] // 3x /28
  azs             = chunklist(data.aws_availability_zones.this.names, 3)[0]                                             // returns first three availability zones in the region as a list
}

data "aws_availability_zones" "this" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "${local.name_prefix}-vpc-${random_id.this.hex}"
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  enable_nat_gateway   = var.enable_nat_gateway
  single_nat_gateway   = var.single_nat_gateway
  enable_vpn_gateway   = var.enable_vpn_gateway
  enable_dns_hostnames = true
  enable_dns_support   = true
  enable_dhcp_options  = false

  tags = local.common_tags
}

module "vpc_endpoints" {
  source = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  count  = var.enable_ssm ? 1 : 0

  vpc_id             = module.vpc.vpc_id
  security_group_ids = [aws_security_group.vpc_endpoints[0].id]

  endpoints = {
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = concat([module.vpc.private_route_table_ids[0]], module.vpc.public_route_table_ids)
      tags            = merge(local.common_tags, { Name = "${local.name_prefix}-s3-vpc-endpoint" })
    },
    ssm = {
      service = "ssm"
      tags    = merge(local.common_tags, { Name = "${local.name_prefix}-ssm" })
    },
    ssmmessages = {
      service = "ssmmessages"
      tags    = merge(local.common_tags, { Name = "${local.name_prefix}-ssmmessages" })
    },
    ec2messages = {
      service = "ec2messages"
      tags    = merge(local.common_tags, { Name = "${local.name_prefix}-ec2messages" })
    },
  }

  tags = local.common_tags
}

resource "aws_security_group" "vpc_endpoints" {
  count = var.enable_ssm ? 1 : 0

  name        = "${local.name_prefix}-endpoints-${random_id.this.hex}"
  description = "Security group for VPC endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc-endpoints-sg"
  })
}

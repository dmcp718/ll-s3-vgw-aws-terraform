locals {
  solution_name = local.name_prefix
}

# AMI ID must be provided via variable

resource "aws_security_group" "this" {
  name        = "${local.solution_name}-sg-${random_id.this.hex}"
  description = "Security group for ${local.solution_name} instances"
  vpc_id      = module.vpc.vpc_id

  tags = merge(local.common_tags, {
    Name = "${local.solution_name}-instance-sg"
  })
}

resource "aws_security_group_rule" "egress" {
  type        = "egress"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = aws_security_group.this.id
}

resource "aws_security_group_rule" "ingress" {
  type        = "ingress"
  from_port   = var.service_port
  to_port     = var.service_port
  protocol    = "tcp"
  cidr_blocks = var.allowed_cidr_blocks

  security_group_id = aws_security_group.this.id
}

resource "aws_security_group_rule" "ssh_ingress" {
  type        = "ingress"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = var.ssh_cidr_blocks

  security_group_id = aws_security_group.this.id
}

resource "aws_lb" "this" {
  name               = "${local.solution_name}-nlb-${random_id.this.hex}"
  internal           = var.lb_internal
  load_balancer_type = "network"
  subnets            = var.lb_internal ? module.vpc.private_subnets : module.vpc.public_subnets

  enable_cross_zone_load_balancing = var.enable_cross_zone_load_balancing
  enable_deletion_protection       = var.enable_deletion_protection

  tags = merge(local.common_tags, {
    Name = "${local.solution_name}-nlb"
  })
}

resource "aws_lb_listener" "s3" {
  load_balancer_arn = aws_lb.this.arn
  port              = "443"
  protocol          = "TLS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.create_route53_records ? aws_acm_certificate.main[0].arn : null

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.s3.arn
  }

  tags = local.common_tags
}

resource "aws_lb_target_group" "s3" {
  name     = "${local.solution_name}-tg-${random_id.this.hex}"
  port     = var.service_port
  protocol = "TCP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    protocol            = "HTTP"
    path                = var.health_check_path
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
    interval            = var.health_check_interval
  }

  tags = merge(local.common_tags, {
    Name = "${local.solution_name}-target-group"
  })
}

resource "aws_launch_template" "this" {
  name_prefix                          = "${local.solution_name}-lt-${random_id.this.hex}"
  image_id                             = var.ami_id
  instance_type                        = var.instance_type
  key_name                             = var.key_name != "" ? var.key_name : null
  vpc_security_group_ids               = [aws_security_group.this.id]
  instance_initiated_shutdown_behavior = "terminate"

  user_data = base64encode(file("${path.module}/resources/bootstrap.sh"))

  dynamic "iam_instance_profile" {
    for_each = var.enable_ssm ? [1] : []
    content {
      name = aws_iam_instance_profile.this[0].name
    }
  }

  ebs_optimized = true

  # Root volume configuration
  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = var.root_volume_size
      volume_type           = var.root_volume_type
      delete_on_termination = true
      encrypted             = var.ebs_encrypted
    }
  }

  # Note: Using instance storage (NVMe) for data storage instead of EBS
  # Instance storage provides 7x faster random read IOPS and 4x faster sequential reads

  # Utilize NVMe instance storage for high-throughput caching
  block_device_mappings {
    device_name  = "/dev/sdc"
    virtual_name = "ephemeral0"
  }

  block_device_mappings {
    device_name  = "/dev/sdd"
    virtual_name = "ephemeral1"
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  monitoring {
    enabled = var.enable_detailed_monitoring
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${local.solution_name}-instance"
    })
  }

  tags = merge(local.common_tags, {
    Name = "${local.solution_name}-launch-template"
  })
}

# Placement group for enhanced networking performance
resource "aws_placement_group" "this" {
  name     = "${local.solution_name}-pg-${random_id.this.hex}"
  strategy = "cluster"

  tags = merge(local.common_tags, {
    Name = "${local.solution_name}-placement-group"
  })
}

resource "aws_autoscaling_group" "this" {
  name_prefix               = "${local.solution_name}-asg-"
  min_size                  = var.asg_min_size
  max_size                  = var.asg_max_size
  desired_capacity          = local.asg_desired_capacity
  vpc_zone_identifier       = module.vpc.private_subnets
  health_check_grace_period = var.health_check_grace_period
  health_check_type         = "ELB"
  target_group_arns         = [aws_lb_target_group.s3.arn]
  placement_group           = aws_placement_group.this.id

  # Ensure NAT Gateway and VPC endpoints are ready before launching instances
  depends_on = [
    module.vpc.natgw_ids,
    module.vpc_endpoints
  ]

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${local.solution_name}-asg"
    propagate_at_launch = false
  }

  dynamic "tag" {
    for_each = local.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = false
    }
  }
}

resource "aws_iam_instance_profile" "this" {
  count = var.enable_ssm ? 1 : 0

  name = "${local.solution_name}-instance-profile-${random_id.this.hex}"
  role = aws_iam_role.this[0].name

  tags = merge(local.common_tags, {
    Name = "${local.solution_name}-instance-profile"
  })
}

resource "aws_iam_role" "this" {
  count = var.enable_ssm ? 1 : 0

  name = "${local.solution_name}-instance-role-${random_id.this.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Effect = "Allow"
        Sid    = ""
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.solution_name}-instance-role"
  })
}

resource "aws_iam_role_policy" "this" {
  count = var.enable_ssm ? 1 : 0

  name = "${local.solution_name}-instance-policy-${random_id.this.hex}"
  role = aws_iam_role.this[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "ec2:CreateTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:GetInstanceProfile",
          "iam:GetUser",
          "iam:GetRole"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
          "ssm:UpdateInstanceInformation",
          "ssm:UpdateInstanceAssociationStatus",
          "ssm:ListInstanceAssociations",
          "ec2messages:GetMessages"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

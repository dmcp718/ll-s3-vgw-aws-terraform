# Variables Reference

This document provides a comprehensive reference for all configurable variables in the S3 Gateway infrastructure.

## Environment and Project Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `environment` | `string` | `"dev"` | Environment name. Must be one of: dev, staging, prod |
| `project_name` | `string` | `"s3-gateway"` | Name of the project/solution. Must contain only lowercase letters, numbers, and hyphens |
| `region` | `string` | `"us-west-2"` | AWS region for deployment |

## Networking Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `vpc_cidr` | `string` | `"10.10.10.0/24"` | CIDR block for VPC. Must be a valid IPv4 CIDR block |
| `enable_nat_gateway` | `bool` | `true` | Enable NAT Gateway for private subnets |
| `single_nat_gateway` | `bool` | `false` | Use single NAT gateway for all private subnets (cost optimization) |
| `enable_vpn_gateway` | `bool` | `false` | Enable VPN gateway |

## Security Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `allowed_cidr_blocks` | `list(string)` | `["0.0.0.0/0"]` | CIDR blocks allowed to access the service |
| `ssh_cidr_blocks` | `list(string)` | `["0.0.0.0/0"]` | CIDR blocks allowed for SSH access |
| `key_name` | `string` | `""` | Name of the EC2 Key Pair to use for SSH access |

## Instance Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `instance_type` | `string` | `"c5d.2xlarge"` | Primary EC2 instance type |
| `ami_id` | `string` | `""` | AMI ID to use for instances. If empty, latest Ubuntu AMI will be used |

### Instance Types for Mixed Instance Policy

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `instance_types` | `list(object)` | See below | List of instance types with weights for mixed instance policy |

**Default instance_types:**
```hcl
[
  {
    instance_type     = "c5d.2xlarge"
    weighted_capacity = "4"
  },
  {
    instance_type     = "c6id.2xlarge"
    weighted_capacity = "3"
  },
  {
    instance_type     = "c5d.xlarge"
    weighted_capacity = "2"
  },
  {
    instance_type     = "c6id.xlarge"
    weighted_capacity = "1"
  }
]
```

## Auto Scaling Configuration

| Variable | Type | Default | Description | Validation |
|----------|------|---------|-------------|------------|
| `asg_min_size` | `number` | `1` | Minimum number of instances in ASG | Must be >= 0 |
| `asg_max_size` | `number` | `3` | Maximum number of instances in ASG | Must be >= min_size |
| `asg_desired_capacity` | `number` | `1` | Desired number of instances in ASG | Will be constrained between min and max |
| `health_check_grace_period` | `number` | `1200` | Time after instance launch before checking health (seconds) |
| `on_demand_base_capacity` | `number` | `1` | Base number of On-Demand instances |
| `on_demand_percentage_above_base` | `number` | `100` | Percentage of On-Demand instances above base capacity |

## Storage Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `root_volume_size` | `number` | `40` | Size of root EBS volume in GB |
| `root_volume_type` | `string` | `"gp3"` | Type of root EBS volume |
| `ebs_encrypted` | `bool` | `true` | Enable EBS encryption |

**Note**: Data storage now uses instance NVMe storage instead of EBS volumes for superior performance:
- 7x faster random read IOPS (48.4K vs 7K)
- 4x faster sequential reads  
- 7x lower random read latency
- Excellent random write performance (68.6K IOPS)

## Load Balancer Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `lb_internal` | `bool` | `false` | Whether load balancer is internal |
| `enable_cross_zone_load_balancing` | `bool` | `true` | Enable cross-zone load balancing |
| `enable_deletion_protection` | `bool` | `false` | Enable deletion protection for load balancer |
| `ssl_policy` | `string` | `"ELBSecurityPolicy-TLS13-1-2-Res-2021-06"` | SSL policy for HTTPS listener |

## Application Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `service_port` | `number` | `8000` | Port on which the service runs |
| `health_check_path` | `string` | `"/health"` | Health check path for load balancer |
| `health_check_healthy_threshold` | `number` | `2` | Number of consecutive health check successes |
| `health_check_unhealthy_threshold` | `number` | `2` | Number of consecutive health check failures |
| `health_check_interval` | `number` | `10` | Health check interval in seconds |

## DNS and Certificate Configuration

| Variable | Type | Default | Description | Validation |
|----------|------|---------|-------------|------------|
| `domain_name` | `string` | `"example.net."` | Domain name for the service (with trailing dot) |
| `subdomain_name` | `string` | `"s3"` | Subdomain for the service |
| `create_route53_records` | `bool` | `true` | Whether to create Route53 records |
| `certificate_validation_method` | `string` | `"DNS"` | Certificate validation method | Must be DNS or EMAIL |

## Monitoring and Logging

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_detailed_monitoring` | `bool` | `true` | Enable detailed monitoring for instances |
| `enable_ssm` | `bool` | `true` | Enable Systems Manager access |

## Tagging Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `additional_tags` | `map(string)` | `{}` | Additional tags to apply to all resources |

## Environment-Specific Examples

### Development Environment

```hcl
environment                = "dev"
vpc_cidr                   = "10.10.0.0/16"
instance_type              = "c5d.large"
asg_min_size               = 1
asg_max_size               = 2
single_nat_gateway         = true
enable_detailed_monitoring = false
enable_deletion_protection = false

additional_tags = {
  Owner      = "development-team"
  CostCenter = "dev-ops"
}
```

### Staging Environment

```hcl
environment                = "staging"
vpc_cidr                   = "10.20.0.0/16"
instance_type              = "c5d.xlarge"
asg_min_size               = 1
asg_max_size               = 4
asg_desired_capacity       = 2
single_nat_gateway         = false

additional_tags = {
  Owner       = "staging-team"
  CostCenter  = "qa-ops"
  Environment = "staging"
}
```

### Production Environment

```hcl
environment                     = "prod"
vpc_cidr                        = "10.30.0.0/16"
instance_type                   = "c5d.2xlarge"
asg_min_size                    = 2
asg_max_size                    = 6
asg_desired_capacity            = 3
health_check_grace_period       = 1800
enable_deletion_protection      = true
allowed_cidr_blocks             = ["10.30.0.0/16"]
ssh_cidr_blocks                 = ["10.30.0.0/16"]

additional_tags = {
  Owner       = "platform-team"
  CostCenter  = "production"
  Compliance  = "required"
  SLA         = "99.9"
}
```

## Variable Validation Rules

### Network Validation
- `vpc_cidr`: Must be a valid IPv4 CIDR block
- Subnets are automatically calculated from VPC CIDR

### Instance Validation
- `asg_min_size`: Must be >= 0
- `asg_max_size`: Must be >= `asg_min_size`
- `asg_desired_capacity`: Automatically constrained between min and max

### Naming Validation
- `project_name`: Must contain only lowercase letters, numbers, and hyphens
- `environment`: Must be one of: dev, staging, prod

### Security Validation
- `certificate_validation_method`: Must be "DNS" or "EMAIL"

## Best Practices

1. **Environment Separation**: Use different VPC CIDRs for each environment
2. **Security**: Restrict CIDR blocks in production environments
3. **Cost Optimization**: Use single NAT gateway and smaller instances in dev
4. **High Availability**: Use multiple AZs and NAT gateways in production
5. **Monitoring**: Enable detailed monitoring in staging and production
6. **Tagging**: Use consistent tagging strategy across all environments 
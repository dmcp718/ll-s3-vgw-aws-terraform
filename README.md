# S3 Gateway Infrastructure

A generic, environment-configurable AWS infrastructure for deploying versitygw S3 Gateway services using Terraform and Packer.
https://github.com/versity/versitygw

## Overview

This repository provides a complete infrastructure-as-code solution for deploying S3 Gateway services across multiple environments (dev, staging, production) with customizable configurations.

## Features

- **Multi-environment support**: Separate configurations for dev, staging, and production
- **Configurable infrastructure**: All hardcoded values replaced with variables
- **Automated deployment**: Single script for all deployment operations
- **High availability**: Auto Scaling Groups with multiple instance types
- **Security**: Configurable security groups and IAM roles
- **Monitoring**: Optional detailed monitoring and SSM integration
- **DNS management**: Automated Route53 and SSL certificate management

## Architecture

The infrastructure includes:
- **VPC**: Configurable CIDR with public/private subnets across 3 AZs
- **Auto Scaling Group**: Mixed instance types with configurable scaling
- **Network Load Balancer**: SSL termination with health checks
- **Route53**: DNS records and SSL certificate validation
- **IAM**: Conditional roles for SSM and monitoring
- **VPC Endpoints**: Optional S3 and SSM endpoints for private connectivity

## Quick Start

### Prerequisites

1. **AWS CLI**: Configure with appropriate credentials
   ```bash
   aws configure
   ```

2. **Terraform**: Install Terraform >= 1.2.0
   ```bash
   # macOS
   brew install terraform
   
   # Linux
   wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
   unzip terraform_1.6.0_linux_amd64.zip
   sudo mv terraform /usr/local/bin/
   ```

3. **Packer** (optional, for AMI building):
   ```bash
   # macOS
   brew install packer
   
   # Linux
   wget https://releases.hashicorp.com/packer/1.9.4/packer_1.9.4_linux_amd64.zip
   unzip packer_1.9.4_linux_amd64.zip
   sudo mv packer /usr/local/bin/
   
   # Or use package manager (Ubuntu/Debian)
   curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
   sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
   sudo apt-get update && sudo apt-get install packer
   ```

### Basic Deployment

1. **Clone and navigate to the repository**
   ```bash
   git clone <repository-url>
   cd ll-s3-vgw-aws-terraform
   ```

2. **Deploy to development environment**
   ```bash
   ./deploy.sh dev plan    # Review what will be created
   ./deploy.sh dev apply   # Deploy the infrastructure
   ```

3. **Deploy to production**
   ```bash
   ./deploy.sh prod plan
   ./deploy.sh prod apply
   ```

### Advanced Usage

**Build new AMI and deploy:**
```bash
./deploy.sh staging apply --build-ami
```

**Use specific AMI:**
```bash
./deploy.sh prod apply --ami-id=ami-12345678
```

**Auto-approve deployment:**
```bash
./deploy.sh dev apply -y
```

**Destroy environment:**
```bash
./deploy.sh dev destroy
```

## Configuration

### Environment Files

Environment-specific configurations are stored in `terraform/environments/`:

- `dev.tfvars` - Development environment (cost-optimized)
- `staging.tfvars` - Staging environment (production-like)
- `prod.tfvars` - Production environment (high-performance)

### Key Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `environment` | Environment name | `dev` |
| `project_name` | Project identifier | `s3-gateway` |
| `region` | AWS region | `us-west-2` |
| `vpc_cidr` | VPC CIDR block | `10.10.10.0/24` |
| `instance_type` | Primary instance type | `c5d.2xlarge` |
| `asg_min_size` | Minimum instances | `1` |
| `asg_max_size` | Maximum instances | `3` |
| `data_volume_size` | EBS volume size (GB) | `500` |
| `domain_name` | Domain for DNS | `solution-lab.click.` |
| `allowed_cidr_blocks` | Access control | `["0.0.0.0/0"]` |

### Security Configuration

**Development Environment:**
- Restricted CIDR blocks for internal access
- Smaller instances for cost optimization
- Single NAT gateway
- Detailed monitoring disabled

**Production Environment:**
- VPC-only access for security
- High-performance instance types
- Multiple NAT gateways for redundancy
- Full monitoring enabled
- Deletion protection enabled

## Customization

### Adding New Environments

1. Create new tfvars file:
   ```bash
   cp terraform/environments/dev.tfvars terraform/environments/test.tfvars
   ```

2. Modify the environment variable:
   ```hcl
   environment = "test"
   ```

3. Update deployment script validation (optional):
   ```bash
   # Edit deploy.sh and add "test" to valid environments
   ```

### Custom Instance Types

Modify the `instance_types` variable in your environment file:

```hcl
instance_types = [
  {
    instance_type     = "c6i.2xlarge"
    weighted_capacity = "4"
  },
  {
    instance_type     = "c6i.xlarge"
    weighted_capacity = "2"
  }
]
```

### Network Configuration

Customize VPC and subnet configuration:

```hcl
vpc_cidr           = "10.50.0.0/16"
enable_nat_gateway = true
single_nat_gateway = false  # High availability
```

### Storage Configuration

Adjust EBS volumes:

```hcl
data_volume_size       = 1000
data_volume_iops       = 20000
data_volume_throughput = 1000
data_volume_type       = "gp3"
```

## AMI Management

### Building Custom AMIs

The Packer configuration builds Ubuntu-based AMIs with:
- LucidLink client pre-installed
- S3 Gateway service configured
- Optimized storage configuration

**Build AMI manually:**
```bash
cd packer/images
packer build -var-file="variables.auto.pkrvars.hcl" ll-s3-gw.pkr.hcl
```

**Environment-specific AMI builds:**
Create `packer/environments/` directory with environment-specific variables.

## Monitoring and Logging

### CloudWatch Integration

When `enable_detailed_monitoring = true`:
- EC2 detailed monitoring enabled
- Custom metrics for application performance
- Log aggregation to CloudWatch Logs

### Systems Manager Integration

When `enable_ssm = true`:
- Session Manager for secure shell access
- Systems Manager Agent for patch management
- VPC endpoints for private connectivity

## Security

### Access Control

- **SSH Access**: Configurable CIDR blocks via `ssh_cidr_blocks`
- **Application Access**: Controlled via `allowed_cidr_blocks`
- **IAM Roles**: Least privilege principle with conditional creation

### Encryption

- **EBS Volumes**: Encrypted by default
- **SSL/TLS**: Configurable SSL policies for load balancer
- **VPC Endpoints**: Private connectivity for AWS services

## Troubleshooting

### Common Issues

**1. Certificate validation timeout:**
```bash
# Check Route53 hosted zone configuration
aws route53 list-hosted-zones
```

**2. AMI not found:**
```bash
# Verify AMI exists in target region
aws ec2 describe-images --image-ids ami-12345678
```

**3. Instance launch failures:**
```bash
# Check Auto Scaling Group events
aws autoscaling describe-scaling-activities --auto-scaling-group-name <asg-name>
```

### Validation Commands

```bash
# Validate Terraform configuration
./deploy.sh dev validate

# Check AWS credentials
aws sts get-caller-identity

# Verify prerequisites
./deploy.sh --help
```

## Contributing

1. Follow the established variable naming conventions
2. Update environment files when adding new variables
3. Test changes in development environment first
4. Update documentation for new features

## License

[Your License Here]

## Support

For issues and questions:
- Check the troubleshooting section
- Review AWS CloudTrail logs
- Examine Terraform state files
- Contact the platform team 
# S3 Gateway Infrastructure

Deploy [VersityGW](https://github.com/versity/versitygw) - an S3-compatible gateway service backed by LucidLink file spaces - on AWS using Terraform and Packer.

## What is this?

This infrastructure-as-code solution deploys a highly available S3-compatible API gateway that:
- Provides S3 API compatibility for any storage backend via LucidLink
- Runs multiple VersityGW instances behind a load balancer
- Auto-scales based on demand
- Includes monitoring and security best practices
- Supports both LucidLink v2 and v3 clients

## Quick Start

### Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.2.0
- Packer (for building custom AMIs)

### ⚠️ Security Notice

**Important**: The `config_vars.txt` file contains sensitive information (passwords, access keys) and is excluded from version control. Always:
- Copy from the template: `config_vars_template.txt` → `config_vars.txt`
- Use strong, unique passwords and access keys
- Never commit the actual `config_vars.txt` file to git
- Review the template for all required configuration values

### Complete Deployment Process

```bash
# 1. Clone the repository
git clone <repository-url>
cd ll-s3-vgw-aws-terraform

# 2. Configure your environment
# Copy the template and edit with your actual values:
cp packer/script/config_vars_template.txt packer/script/config_vars.txt
# Edit packer/script/config_vars.txt with your actual values:
# - AWS_REGION: AWS deployment region (e.g. us-east-1)  
# - EC2_TYPE: EC2 instance type (recommended: c6id.2xlarge for instance storage)
# - FILESPACE1: Your LucidLink filespace name
# - FSUSER1: Your LucidLink email address
# - LLPASSWD1: Your LucidLink password
# - FSVERSION: LucidLink version - "2" or "3" (default: "3")
# - ROOT_ACCESS_KEY: S3 admin access key (change from defaults!)
# - ROOT_SECRET_KEY: S3 admin secret key (change from defaults!)
# - VGW_VIRTUAL_DOMAIN: Your S3 domain (e.g. s3.yourcompany.com)
# - FQDOMAIN: Your base domain (e.g. yourcompany.com)

# 3. Build AMI and deploy
./deploy.sh apply --build-ami

# Or do it step by step:
# 3a. Prepare AMI build files
./deploy.sh prepare

# 3b. Plan deployment with new AMI
./deploy.sh plan --build-ami

# 3c. Deploy infrastructure
./deploy.sh apply
```

**Important**: The `--build-ami` flag automatically handles all preparation steps including configuration validation, file generation, AMI building, and AMI ID extraction.

## Architecture Overview

```
┌─────────────────┐
│   Route53 DNS   │
└────────┬────────┘
         │
┌────────▼────────┐
│ NLB with SSL    │
└────────┬────────┘
         │
┌────────▼────────────────────────┐
│     Auto Scaling Group          │
│ ┌──────────┐ ┌──────────┐      │
│ │Instance 1│ │Instance 2│ ...  │
│ └──────────┘ └──────────┘      │
│                                 │
│ Each instance runs:             │
│ • LucidLink daemon (mount)      │
│ • VersityGW                     │
└─────────────────────────────────┘
         │
┌────────▼──────────┐
│LucidLink filespace│
└───────────────────┘
```

### Key Components

- **VersityGW**: S3-compatible gateway running on port 8000
- **LucidLink**: Provides the file system mount for storage backend (supports v2 and v3)
- **Auto Scaling**: Mixed instance types with spot/on-demand support
- **Load Balancer**: Network Load Balancer with SSL termination
- **Storage**: NVMe instance storage (RAID 0) for cache + EBS volumes for data

## Common Operations

### Deployment Commands

```bash
# View available options
./deploy.sh --help

# Configuration and preparation
./deploy.sh prepare              # Validate config and generate build files

# Plan changes (preview)
./deploy.sh plan                 # Plan with existing AMI
./deploy.sh plan --build-ami     # Build AMI and plan

# Apply changes
./deploy.sh apply                # Deploy with existing AMI
./deploy.sh apply --build-ami    # Build AMI and deploy

# Use specific AMI
./deploy.sh apply --ami-id=ami-12345678

# Destroy infrastructure
./deploy.sh destroy
```

## Configuration

### Essential Variables

Edit `packer/script/config_vars.txt` with your values:

```bash
# AWS Deployment Configuration
AWS_REGION="us-east-1"                    # AWS deployment region
EC2_TYPE="c6id.2xlarge"                   # EC2 instance type for AMI build

# LucidLink Configuration
FILESPACE1="your-lucidlink-filespace"     # LucidLink filespace name
FSUSER1="your-username"                   # LucidLink username
LLPASSWD1="your-password"                 # LucidLink password
ROOTPOINT1="/"                            # Root mount point
FSVERSION="2"                             # LucidLink version (2 or 3)

# S3 Gateway Configuration  
ROOT_ACCESS_KEY="your-s3-admin-key"       # S3 admin access key
ROOT_SECRET_KEY="your-s3-admin-secret"    # S3 admin secret key
VGW_IAM_DIR="/media/lucidlink/.vgw"       # IAM directory path
FQDOMAIN="your-domain.com"                # Your domain name
```

**📖 Full variable reference**: See [`VARIABLES.md`](VARIABLES.md) for all 50+ Terraform variables.

### Variable Precedence

Terraform variables can be set via (in order of precedence):
1. Command line: `./deploy.sh apply --ami-id=ami-123`
2. Environment variables: `export TF_VAR_instance_type=c5d.large`
3. Terraform variable files

## Advanced Usage

### Configuration Process

The deployment requires updating configuration files with your specific values:

```bash
# 1. Edit the main configuration file
vim packer/script/config_vars.txt

# 2. Validate configuration
./deploy.sh prepare

# 3. Build AMI manually (optional)
cd packer/script && ./ll-s3-gw_ami_build_args.sh
cd ../images && packer build -var-file="variables.auto.pkrvars.hcl" ll-s3-gw.pkr.hcl
```

### Building Custom AMIs

The AMI build process follows these steps:

1. **Configuration Validation**: Checks `config_vars.txt` for required values
2. **File Generation**: Runs `ll-s3-gw_ami_build_args.sh` to create build files
3. **Packer Build**: Creates the AMI with all software pre-installed
4. **AMI ID Extraction**: Automatically extracts AMI ID for Terraform

```bash
# Automatic (recommended)
./deploy.sh apply --build-ami

# Manual process
./deploy.sh prepare                    # Step 1 & 2
cd packer/images
packer build -var-file="variables.auto.pkrvars.hcl" ll-s3-gw.pkr.hcl  # Step 3
# Step 4 happens automatically via post-processor
```

### Monitoring & Access

- **CloudWatch**: Enabled with `enable_detailed_monitoring = true`
- **SSM Session Manager**: Secure shell access with `enable_ssm = true`
- **Health Checks**: Automatic via ALB on configurable endpoints

## Troubleshooting

### Common Issues

**Configuration not updated**
```bash
# The script will warn if template values are detected
./deploy.sh prepare
# Update packer/script/config_vars.txt with actual values
```

**AMI build fails**
```bash
# Check if configuration files were generated
ls -la packer/files/
# Re-run preparation step
./deploy.sh prepare
```

**Certificate validation timeout**
```bash
# Verify Route53 hosted zone
aws route53 list-hosted-zones
```

**Instance launch failures**
```bash
# Check Auto Scaling Group events
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name <project>-<env>-asg
```

**AMI not found**
```bash
# Verify AMI in target region
aws ec2 describe-images --image-ids ami-12345678
```

### Validation

```bash
# Validate configuration
./deploy.sh validate

# Check AWS credentials
aws sts get-caller-identity
```

## Security Features

- **Encryption**: EBS volumes encrypted by default
- **Access Control**: Configurable security groups and CIDR blocks
- **IAM**: Least-privilege roles with conditional features
- **SSL/TLS**: Configurable policies on load balancer
- **Secrets**: Systemd credential encryption for sensitive data

## Contributing

1. Test changes before deployment
2. Follow existing naming conventions
3. Update relevant documentation
4. Create pull requests for review

## Support

For issues:
1. Check the troubleshooting section above
2. Review CloudWatch logs
3. Open an issue in this repository

---

For detailed configuration options, see [`VARIABLES.md`](VARIABLES.md)  
For development guidance, see [`CLAUDE.md`](CLAUDE.md)
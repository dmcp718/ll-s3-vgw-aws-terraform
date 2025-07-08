#!/bin/bash

# S3 Gateway Deployment Script
# Usage: ./deploy.sh [action]
# Actions: plan, apply, destroy, prepare

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/terraform"
PACKER_DIR="${SCRIPT_DIR}/packer"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ACTION=""
AUTO_APPROVE=false
BUILD_AMI=false

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

usage() {
    cat << EOF
S3 Gateway Deployment Script

Usage: $0 [OPTIONS] <action>

Actions:
    plan      Show what will be created/changed
    apply     Create/update infrastructure
    destroy   Destroy infrastructure
    validate  Validate configuration
    prepare   Prepare AMI build files (config validation + file generation)
    check     Check deployment health (NAT routes, SSM connectivity, etc.)

Options:
    -h, --help          Show this help message
    -y, --auto-approve  Auto approve apply/destroy actions
    -b, --build-ami     Build new AMI before deployment
    --ami-id=ID         Use specific AMI ID
    --key-name=NAME     Override SSH key name

Examples:
    $0 prepare              # Prepare AMI build files
    $0 plan                 # Plan deployment
    $0 apply                # Deploy infrastructure
    $0 apply -y             # Deploy with auto-approve
    $0 destroy              # Destroy infrastructure
    $0 plan --build-ami     # Build AMI and plan
    $0 apply --build-ami    # Build AMI and deploy

Configuration Process:
    1. Update packer/script/config_vars.txt with your actual values
    2. Run: $0 prepare (validates config and generates build files)
    3. Run: $0 plan --build-ami (builds AMI and plans deployment)
    4. Run: $0 apply (applies infrastructure)

    The --build-ami flag will automatically:
    - Validate configuration variables
    - Generate AMI build files
    - Build the AMI with Packer
    - Extract the AMI ID for Terraform

EOF
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if terraform is installed
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed. Please install Terraform."
        exit 1
    fi
    
    # Check if packer is installed (only if building AMI)
    if [ "$BUILD_AMI" = true ] && ! command -v packer &> /dev/null; then
        log_error "Packer is not installed but --build-ami was specified. Please install Packer."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' or set AWS environment variables."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

validate_action() {
    if [[ ! "$ACTION" =~ ^(plan|apply|destroy|validate|prepare|check)$ ]]; then
        log_error "Invalid action: $ACTION"
        log_error "Valid actions: plan, apply, destroy, validate, prepare, check"
        exit 1
    fi
}

validate_config_vars() {
    log_info "Validating configuration variables..."
    
    if [ ! -f "${PACKER_DIR}/script/config_vars.txt" ]; then
        log_error "Configuration file not found: ${PACKER_DIR}/script/config_vars.txt"
        log_error "Please create this file with your specific configuration values"
        exit 1
    fi
    
    # Check if config_vars.txt has been updated from template values
    if grep -q "filespace.domain" "${PACKER_DIR}/script/config_vars.txt"; then
        log_warning "config_vars.txt contains template values. Please update with actual values:"
        log_warning "  - FILESPACE1: Your LucidLink filespace name"
        log_warning "  - FSUSER1: Your LucidLink username"
        log_warning "  - LLPASSWD1: Your LucidLink password"
        log_warning "  - ROOT_ACCESS_KEY: S3 admin access key"
        log_warning "  - ROOT_SECRET_KEY: S3 admin secret key"
        log_warning "  - AWS_REGION: AWS deployment region"
        log_warning "  - EC2_TYPE: EC2 instance type for AMI build"
        log_warning "  - VGW_IAM_DIR: IAM directory path"
        log_warning "  - FQDOMAIN: Your domain name"
        
        read -p "Continue with current values? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            log_info "Please update config_vars.txt and run again"
            exit 0
        fi
    fi
    
    log_success "Configuration validation complete"
}

prepare_ami_build() {
    log_info "Preparing AMI build files..."
    
    cd "${PACKER_DIR}/script"
    
    # Run the build preparation script
    if [ ! -f "ll-s3-gw_ami_build_args.sh" ]; then
        log_error "Build preparation script not found: ll-s3-gw_ami_build_args.sh"
        exit 1
    fi
    
    ./ll-s3-gw_ami_build_args.sh
    
    log_success "AMI build files prepared"
    cd "${SCRIPT_DIR}"
}

find_latest_ami() {
    log_info "Finding latest AMI..."
    
    # Source config to get filespace name
    if [ -f "$PACKER_DIR/script/config_vars.txt" ]; then
        source "$PACKER_DIR/script/config_vars.txt"
    fi
    
    # Find the most recent AMI with matching name pattern
    LATEST_AMI=$(aws ec2 describe-images \
        --owners self \
        --filters "Name=name,Values=ll-s3-gw-*" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text)
    
    if [ "$LATEST_AMI" != "None" ] && [ -n "$LATEST_AMI" ]; then
        log_info "Found latest AMI: $LATEST_AMI"
        export TF_VAR_ami_id="$LATEST_AMI"
        return 0
    else
        log_error "No AMI found. Please build a new AMI with --build-ami flag"
        return 1
    fi
}

build_ami() {
    log_info "Building AMI with Packer..."
    
    # Validate configuration first
    validate_config_vars
    
    # Prepare build files
    prepare_ami_build
    
    cd "${PACKER_DIR}/images"
    
    # Build AMI
    packer build \
        -var-file="variables.auto.pkrvars.hcl" \
        ll-s3-gw.pkr.hcl
    
    # Get the AMI ID
    if [ -f "ami_id.txt" ]; then
        AMI_ID=$(cat ami_id.txt | tr -d '\n')
        log_success "AMI built successfully: $AMI_ID"
        
        # Update the terraform variables
        export TF_VAR_ami_id="$AMI_ID"
        log_info "Using newly built AMI: $AMI_ID"
    else
        log_error "Failed to get AMI ID from build"
        exit 1
    fi
    
    cd "${SCRIPT_DIR}"
}

terraform_init() {
    log_info "Initializing Terraform..."
    cd "${TERRAFORM_DIR}"
    terraform init
    cd "${SCRIPT_DIR}"
}

terraform_validate() {
    log_info "Validating Terraform configuration..."
    cd "${TERRAFORM_DIR}"
    terraform validate
    cd "${SCRIPT_DIR}"
    log_success "Terraform configuration is valid"
}

terraform_plan() {
    log_info "Planning Terraform deployment..."
    cd "${TERRAFORM_DIR}"
    
    terraform plan -out="deployment.tfplan"
    
    cd "${SCRIPT_DIR}"
}

validate_deployment() {
    log_info "Validating deployment configuration..."
    cd "${TERRAFORM_DIR}"
    
    # Get VPC ID
    VPC_ID=$(terraform output -raw vpc_id 2>/dev/null)
    if [ -z "$VPC_ID" ]; then
        log_warning "Could not retrieve VPC ID for validation"
        return 0
    fi
    
    # Check that private subnet route tables have NAT Gateway routes
    log_info "Checking NAT Gateway routes for private subnets..."
    PRIVATE_ROUTE_TABLES=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=*private*" \
        --query 'RouteTables[].RouteTableId' --output text)
    
    for RT_ID in $PRIVATE_ROUTE_TABLES; do
        NAT_ROUTE=$(aws ec2 describe-route-tables \
            --route-table-ids "$RT_ID" \
            --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`].NatGatewayId' \
            --output text)
        
        if [ -z "$NAT_ROUTE" ] || [ "$NAT_ROUTE" = "None" ]; then
            log_warning "Private route table $RT_ID missing NAT Gateway route"
            
            # Get available NAT Gateway
            NAT_GW=$(aws ec2 describe-nat-gateways \
                --filter "Name=vpc-id,Values=${VPC_ID}" "Name=state,Values=available" \
                --query 'NatGateways[0].NatGatewayId' --output text)
            
            if [ -n "$NAT_GW" ] && [ "$NAT_GW" != "None" ]; then
                log_info "Adding missing NAT Gateway route to $RT_ID"
                aws ec2 create-route \
                    --route-table-id "$RT_ID" \
                    --destination-cidr-block 0.0.0.0/0 \
                    --nat-gateway-id "$NAT_GW" || true
            fi
        else
            log_info "✓ Route table $RT_ID has NAT Gateway route: $NAT_ROUTE"
        fi
    done
    
    # Note: Instance connectivity will be verified by load balancer health checks
    # ASG instances take 2-3 minutes to launch and become healthy
    
    cd "${SCRIPT_DIR}"
}

terraform_apply() {
    log_info "Applying Terraform configuration..."
    cd "${TERRAFORM_DIR}"
    
    if [ "$AUTO_APPROVE" = true ]; then
        terraform apply -auto-approve "deployment.tfplan"
    else
        terraform apply "deployment.tfplan"
    fi
    
    cd "${SCRIPT_DIR}"
    
    # Validate deployment after apply
    validate_deployment
    
    log_success "Deployment completed successfully!"
}

terraform_destroy() {
    log_warning "This will destroy all S3 Gateway infrastructure!"
    
    if [ "$AUTO_APPROVE" = false ]; then
        read -p "Are you sure you want to continue? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            log_info "Destruction cancelled"
            exit 0
        fi
    fi
    
    log_info "Destroying Terraform resources..."
    cd "${TERRAFORM_DIR}"
    
    if [ "$AUTO_APPROVE" = true ]; then
        terraform destroy -auto-approve
    else
        terraform destroy
    fi
    
    cd "${SCRIPT_DIR}"
    log_success "Resources destroyed successfully!"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -y|--auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        -b|--build-ami)
            BUILD_AMI=true
            shift
            ;;
        --ami-id=*)
            export TF_VAR_ami_id="${1#*=}"
            shift
            ;;
        --key-name=*)
            export TF_VAR_key_name="${1#*=}"
            shift
            ;;
        plan|apply|destroy|validate|prepare|check)
            if [ -z "$ACTION" ]; then
                ACTION=$1
            else
                log_error "Action already specified: $ACTION"
                exit 1
            fi
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Check required arguments
if [ -z "$ACTION" ]; then
    log_error "Action is required"
    usage
    exit 1
fi

# Main execution
log_info "Starting S3 Gateway deployment process..."
log_info "Action: $ACTION"

# Validate inputs
validate_action

# Check prerequisites
check_prerequisites

# Source config vars to get AWS_REGION for Terraform
if [ -f "$PACKER_DIR/script/config_vars.txt" ]; then
    source "$PACKER_DIR/script/config_vars.txt"
    if [ -n "$AWS_REGION" ]; then
        export AWS_REGION="$AWS_REGION"  # For AWS CLI commands
        export AWS_DEFAULT_REGION="$AWS_REGION"  # Set default region
        export TF_VAR_region="$AWS_REGION"  # For Terraform
        log_info "Using region from config: $AWS_REGION"
    fi
    if [ -n "$FQDOMAIN" ]; then
        export TF_VAR_domain_name="$FQDOMAIN"
        log_info "Using domain from config: $FQDOMAIN"
    fi
    if [ -n "$EC2_TYPE" ]; then
        export TF_VAR_instance_type="$EC2_TYPE"
        log_info "Using instance type from config: $EC2_TYPE"
    fi
    if [ -n "$VGW_VIRTUAL_DOMAIN" ]; then
        export TF_VAR_virtual_domain="$VGW_VIRTUAL_DOMAIN"
        log_info "Using virtual domain from config: $VGW_VIRTUAL_DOMAIN"
    fi
    if [ -n "$ASG_MIN_SIZE" ]; then
        export TF_VAR_asg_min_size="$ASG_MIN_SIZE"
        log_info "Using ASG min size from config: $ASG_MIN_SIZE"
    fi
    if [ -n "$ASG_MAX_SIZE" ]; then
        export TF_VAR_asg_max_size="$ASG_MAX_SIZE"
        log_info "Using ASG max size from config: $ASG_MAX_SIZE"
    fi
    if [ -n "$ASG_DESIRED_CAPACITY" ]; then
        export TF_VAR_asg_desired_capacity="$ASG_DESIRED_CAPACITY"
        log_info "Using ASG desired capacity from config: $ASG_DESIRED_CAPACITY"
    fi
fi

# Build AMI if requested
if [ "$BUILD_AMI" = true ]; then
    build_ami
fi

# If no AMI ID is set, try to find the latest one
if [ -z "$TF_VAR_ami_id" ]; then
    find_latest_ami || {
        log_error "No AMI ID provided and no existing AMI found"
        log_info "Use --build-ami to build a new AMI or --ami-id=<id> to specify one"
        exit 1
    }
fi

# Execute action
case $ACTION in
    validate)
        terraform_init
        terraform_validate
        ;;
    prepare)
        validate_config_vars
        prepare_ami_build
        ;;
    plan)
        terraform_init
        terraform_validate
        terraform_plan
        ;;
    apply)
        terraform_init
        terraform_validate
        terraform_plan
        terraform_apply
        ;;
    destroy)
        terraform_init
        terraform_destroy
        ;;
    check)
        validate_deployment
        ;;
esac

log_success "Operation completed successfully!"
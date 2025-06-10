#!/bin/bash

# S3 Gateway Deployment Script
# Usage: ./deploy.sh [environment] [action]
# Environment: dev, staging, prod
# Action: plan, apply, destroy

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
ENVIRONMENT=""
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

Usage: $0 [OPTIONS] <environment> <action>

Environments:
    dev       Development environment
    staging   Staging environment
    prod      Production environment

Actions:
    plan      Show what will be created/changed
    apply     Create/update infrastructure
    destroy   Destroy infrastructure
    validate  Validate configuration

Options:
    -h, --help          Show this help message
    -y, --auto-approve  Auto approve apply/destroy actions
    -b, --build-ami     Build new AMI before deployment
    --ami-id=ID         Use specific AMI ID
    --key-name=NAME     Override SSH key name

Examples:
    $0 dev plan                 # Plan development deployment
    $0 staging apply            # Deploy to staging
    $0 prod apply -y            # Deploy to production with auto-approve
    $0 dev destroy              # Destroy development environment
    $0 staging plan --build-ami # Build AMI and plan staging deployment

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

validate_environment() {
    if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
        log_error "Invalid environment: $ENVIRONMENT"
        log_error "Valid environments: dev, staging, prod"
        exit 1
    fi
    
    # Check if environment tfvars file exists
    if [ ! -f "${TERRAFORM_DIR}/environments/${ENVIRONMENT}.tfvars" ]; then
        log_error "Environment file not found: ${TERRAFORM_DIR}/environments/${ENVIRONMENT}.tfvars"
        exit 1
    fi
}

validate_action() {
    if [[ ! "$ACTION" =~ ^(plan|apply|destroy|validate)$ ]]; then
        log_error "Invalid action: $ACTION"
        log_error "Valid actions: plan, apply, destroy, validate"
        exit 1
    fi
}

build_ami() {
    log_info "Building AMI with Packer..."
    
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
    terraform fmt -check=true
    cd "${SCRIPT_DIR}"
    log_success "Terraform configuration is valid"
}

terraform_plan() {
    log_info "Planning Terraform deployment for $ENVIRONMENT environment..."
    cd "${TERRAFORM_DIR}"
    
    terraform plan \
        -var-file="environments/${ENVIRONMENT}.tfvars" \
        -out="${ENVIRONMENT}.tfplan"
    
    cd "${SCRIPT_DIR}"
}

terraform_apply() {
    log_info "Applying Terraform configuration for $ENVIRONMENT environment..."
    cd "${TERRAFORM_DIR}"
    
    if [ "$AUTO_APPROVE" = true ]; then
        terraform apply -auto-approve "${ENVIRONMENT}.tfplan"
    else
        terraform apply "${ENVIRONMENT}.tfplan"
    fi
    
    cd "${SCRIPT_DIR}"
    log_success "Deployment completed successfully!"
}

terraform_destroy() {
    log_warning "This will destroy all resources in the $ENVIRONMENT environment!"
    
    if [ "$AUTO_APPROVE" = false ]; then
        read -p "Are you sure you want to continue? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            log_info "Destruction cancelled"
            exit 0
        fi
    fi
    
    log_info "Destroying Terraform resources for $ENVIRONMENT environment..."
    cd "${TERRAFORM_DIR}"
    
    if [ "$AUTO_APPROVE" = true ]; then
        terraform destroy \
            -var-file="environments/${ENVIRONMENT}.tfvars" \
            -auto-approve
    else
        terraform destroy \
            -var-file="environments/${ENVIRONMENT}.tfvars"
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
        dev|staging|prod)
            if [ -z "$ENVIRONMENT" ]; then
                ENVIRONMENT=$1
            else
                log_error "Environment already specified: $ENVIRONMENT"
                exit 1
            fi
            shift
            ;;
        plan|apply|destroy|validate)
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
if [ -z "$ENVIRONMENT" ]; then
    log_error "Environment is required"
    usage
    exit 1
fi

if [ -z "$ACTION" ]; then
    log_error "Action is required"
    usage
    exit 1
fi

# Main execution
log_info "Starting deployment process..."
log_info "Environment: $ENVIRONMENT"
log_info "Action: $ACTION"

# Validate inputs
validate_environment
validate_action

# Check prerequisites
check_prerequisites

# Build AMI if requested
if [ "$BUILD_AMI" = true ]; then
    build_ami
fi

# Initialize Terraform
terraform_init

# Execute action
case $ACTION in
    validate)
        terraform_validate
        ;;
    plan)
        terraform_validate
        terraform_plan
        ;;
    apply)
        terraform_validate
        terraform_plan
        terraform_apply
        ;;
    destroy)
        terraform_destroy
        ;;
esac

log_success "Operation completed successfully!" 
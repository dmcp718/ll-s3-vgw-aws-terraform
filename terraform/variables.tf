# =============================================================================
# ENVIRONMENT AND PROJECT CONFIGURATION
# =============================================================================

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project/solution"
  type        = string
  default     = "s3-gateway"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-west-2"
}

# =============================================================================
# NETWORKING CONFIGURATION
# =============================================================================

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.10.10.0/24"
  
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use single NAT gateway for all private subnets"
  type        = bool
  default     = false
}

variable "enable_vpn_gateway" {
  description = "Enable VPN gateway"
  type        = bool
  default     = false
}

# =============================================================================
# SECURITY CONFIGURATION
# =============================================================================

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access the service"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ssh_cidr_blocks" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "key_name" {
  description = "Name of the EC2 Key Pair to use for SSH access"
  type        = string
  default     = ""
}

# =============================================================================
# INSTANCE CONFIGURATION
# =============================================================================

variable "instance_type" {
  description = "Primary EC2 instance type"
  type        = string
  default     = "c5d.2xlarge"
}

variable "instance_types" {
  description = "List of instance types for mixed instance policy with weights"
  type = list(object({
    instance_type     = string
    weighted_capacity = string
  }))
  default = [
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
}

variable "ami_id" {
  description = "AMI ID to use for instances"
  type        = string
  default     = ""
}

# =============================================================================
# AUTO SCALING CONFIGURATION
# =============================================================================

variable "asg_min_size" {
  description = "Minimum number of instances in ASG"
  type        = number
  default     = 1
  
  validation {
    condition     = var.asg_min_size >= 0
    error_message = "ASG minimum size must be non-negative."
  }
}

variable "asg_max_size" {
  description = "Maximum number of instances in ASG"
  type        = number
  default     = 3
  
  validation {
    condition     = var.asg_max_size >= var.asg_min_size
    error_message = "ASG maximum size must be greater than or equal to minimum size."
  }
}

variable "asg_desired_capacity" {
  description = "Desired number of instances in ASG"
  type        = number
  default     = 1
}

variable "health_check_grace_period" {
  description = "Time after instance launch before checking health"
  type        = number
  default     = 1200
}

variable "on_demand_base_capacity" {
  description = "Base number of On-Demand instances"
  type        = number
  default     = 1
}

variable "on_demand_percentage_above_base" {
  description = "Percentage of On-Demand instances above base capacity"
  type        = number
  default     = 100
}

# =============================================================================
# STORAGE CONFIGURATION
# =============================================================================

variable "root_volume_size" {
  description = "Size of root EBS volume in GB"
  type        = number
  default     = 40
}

variable "root_volume_type" {
  description = "Type of root EBS volume"
  type        = string
  default     = "gp3"
}

variable "data_volume_size" {
  description = "Size of data EBS volume in GB"
  type        = number
  default     = 500
}

variable "data_volume_type" {
  description = "Type of data EBS volume"
  type        = string
  default     = "gp3"
}

variable "data_volume_iops" {
  description = "IOPS for data EBS volume"
  type        = number
  default     = 16000
}

variable "data_volume_throughput" {
  description = "Throughput for data EBS volume in MB/s"
  type        = number
  default     = 1000
}

variable "ebs_encrypted" {
  description = "Enable EBS encryption"
  type        = bool
  default     = true
}

# =============================================================================
# LOAD BALANCER CONFIGURATION
# =============================================================================

variable "lb_internal" {
  description = "Whether load balancer is internal"
  type        = bool
  default     = false
}

variable "enable_cross_zone_load_balancing" {
  description = "Enable cross-zone load balancing"
  type        = bool
  default     = true
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for load balancer"
  type        = bool
  default     = false
}

variable "ssl_policy" {
  description = "SSL policy for HTTPS listener"
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-Res-2021-06"
}

# =============================================================================
# APPLICATION CONFIGURATION
# =============================================================================

variable "service_port" {
  description = "Port on which the service runs"
  type        = number
  default     = 8000
}

variable "health_check_path" {
  description = "Health check path for load balancer"
  type        = string
  default     = "/health"
}

variable "health_check_healthy_threshold" {
  description = "Number of consecutive health check successes"
  type        = number
  default     = 2
}

variable "health_check_unhealthy_threshold" {
  description = "Number of consecutive health check failures"
  type        = number
  default     = 2
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 10
}

# =============================================================================
# DNS AND CERTIFICATE CONFIGURATION
# =============================================================================

variable "domain_name" {
  description = "Domain name for the service (with trailing dot)"
  type        = string
  default     = "solution-lab.click."
}

variable "subdomain_name" {
  description = "Subdomain for the service"
  type        = string
  default     = "s3"
}

variable "create_route53_records" {
  description = "Whether to create Route53 records"
  type        = bool
  default     = true
}

variable "certificate_validation_method" {
  description = "Certificate validation method"
  type        = string
  default     = "DNS"
  
  validation {
    condition     = contains(["DNS", "EMAIL"], var.certificate_validation_method)
    error_message = "Certificate validation method must be either DNS or EMAIL."
  }
}

# =============================================================================
# MONITORING AND LOGGING
# =============================================================================

variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring for instances"
  type        = bool
  default     = true
}

variable "enable_ssm" {
  description = "Enable Systems Manager access"
  type        = bool
  default     = true
}

# =============================================================================
# TAGGING CONFIGURATION
# =============================================================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# =============================================================================
# LOCALS FOR COMPUTED VALUES
# =============================================================================

locals {
  # Naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  
  # Domain handling
  domain_fqdn       = var.domain_name
  domain_name_clean = trimsuffix(var.domain_name, ".")
  subdomain_fqdn    = "${var.subdomain_name}.${local.domain_name_clean}"
  
  # Common tags
  common_tags = merge(
    {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
    },
    var.additional_tags
  )
  
  # ASG desired capacity validation
  asg_desired_capacity = min(max(var.asg_desired_capacity, var.asg_min_size), var.asg_max_size)
}
variable "prefix" {
  type        = string
  description = "Prefix to add to all resources"
  default     = "n8n"
}

variable "certificate_arn" {
  type        = string
  description = "Certificate ARN for HTTPS support"
  default     = null
}

variable "url" {
  type        = string
  description = "URL for n8n (default is LB url), needs a trailing slash if you specify it"
  default     = null
}

variable "desired_count" {
  type        = number
  description = "Desired count of n8n tasks, be careful with this to make it more than 1 as it can cause issues with webhooks not registering properly"
  default     = 1
}

variable "container_image" {
  type        = string
  description = "Container image to use for n8n"
  default     = "n8nio/n8n:latest"
}

variable "fargate_type" {
  type        = string
  description = "Fargate type to use for n8n (either FARGATE or FARGATE_SPOT))"
  default     = "FARGATE_SPOT"
}

variable "ssl_policy" {
  type        = string
  description = "The name of the SSL policy to use for the HTTPS Listener on the ALB"
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources"
  default     = null
}

# VPC Configuration Variables (from upstream)
variable "vpc_id" {
  type        = string
  description = "VPC ID to deploy n8n into (optional, creates new VPC if not provided)"
  default     = null
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for ECS tasks (optional, uses VPC subnets if not provided)"
  default     = []
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Public subnet IDs for ALB (optional, uses VPC public subnets if not provided)"
  default     = []
}

variable "use_private_subnets" {
  type        = bool
  description = "Whether to deploy ECS tasks in private subnets (requires NAT Gateway or VPC endpoints for internet access)"
  default     = false
}

variable "alb_allowed_cidr_blocks" {
  type        = list(string)
  description = "List of CIDR blocks allowed to access the ALB (default: allows all traffic)"
  default     = ["0.0.0.0/0"]
}

# Additional Custom Variables
# Note: These are extensions to the base module and are not part of upstream

variable "aws_profile" {
  type        = string
  description = "AWS Profile name to use for authentication (Optional - used in provider configuration)"
  default     = null
}

variable "aws_access_key" {
  type        = string
  description = "AWS Access Key for authentication (Optional - used if aws_profile is not set)"
  default     = null
}

variable "aws_secret_key" {
  type        = string
  description = "AWS Secret Key for authentication (Optional - used if aws_profile is not set)"
  default     = null
}

variable "region" {
  type        = string
  description = "AWS Region to deploy resources (e.g., us-east-1, us-west-1)"
  default     = "us-west-1"
}

variable "domain" {
  type        = string
  description = "Domain name for n8n instance (used in environment variables)"
  default     = null
}

# Backend Configuration Variables
# These are used by setup-backend.sh and init.sh scripts for S3 backend setup

variable "backend_bucket" {
  type        = string
  description = "S3 bucket name for Terraform state storage"
  default     = null
}

variable "backend_key" {
  type        = string
  description = "Path to the state file within S3 bucket"
  default     = "n8n/terraform.tfstate"
}

variable "backend_dynamodb_table" {
  type        = string
  description = "DynamoDB table name for Terraform state locking"
  default     = null
}

# Backup Configuration
variable "backup_retention_days" {
  type        = number
  description = "Number of days to retain EFS backups"
  default     = 7
}

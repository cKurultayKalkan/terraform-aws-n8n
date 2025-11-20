# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Terraform module that deploys n8n (workflow automation tool) on AWS using:
- ECS Fargate Spot instances (single instance to avoid webhook deregistration issues)
- Application Load Balancer (ALB)
- EFS for persistent state storage
- Estimated cost: ~$3/month (assuming ALB is in free tier)

**Important**: n8n is not designed to run stateless behind a load balancer. This module uses a single instance to avoid webhook registration issues.

## Common Commands

### Initial Setup

```bash
# 1. Copy and configure terraform.tfvars
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars  # Edit with your values

# 2. Setup S3 backend and DynamoDB table
./setup-backend.sh

# 3. Initialize Terraform with backend configuration
./init.sh

# 4. Preview changes
terraform plan

# 5. Apply infrastructure
terraform apply
```

### Development Workflow

```bash
# Format Terraform files
terraform fmt

# Validate configuration
terraform validate

# Plan with specific var file
terraform plan -var-file=terraform.tfvars

# Apply changes
terraform apply

# Destroy infrastructure
terraform destroy

# View outputs
terraform output

# Show current state
terraform show
```

### Manual Backend Initialization

If you need to initialize without the init.sh script:

```bash
terraform init \
  -backend-config="bucket=your-bucket" \
  -backend-config="key=n8n/terraform.tfstate" \
  -backend-config="region=us-west-1" \
  -backend-config="dynamodb_table=your-table" \
  -backend-config="encrypt=true"
```

### AWS CLI Commands for Debugging

```bash
# Check ECS service status
aws ecs describe-services --cluster n8n-cluster --services n8n-service

# View task status
aws ecs list-tasks --cluster n8n-cluster

# Check ALB target health
aws elbv2 describe-target-health --target-group-arn <tg-arn>

# View CloudWatch logs
aws logs tail /aws/ecs/n8n-logs --follow

# Check EFS status
aws efs describe-file-systems
```

## Architecture

### File Structure

- **main.tf**: AWS provider configuration
- **variables.tf**: All input variables with defaults
- **backend.tf**: S3 backend configuration (commented out by default)
- **vpc.tf**: VPC setup using terraform-aws-modules/vpc/aws module
  - Creates VPC with public/private subnets across 3 AZs
  - NAT gateway disabled (ECS tasks use public IPs to reduce costs)
- **ecs.tf**: ECS cluster, task definition, and service
  - Single Fargate Spot instance
  - Container logs to CloudWatch (1 day retention)
  - Task uses EFS volume mounted at `/home/node/.n8n-fresh`
- **alb.tf**: Application Load Balancer configuration
  - HTTP listener (port 80) - redirects to HTTPS if certificate provided
  - HTTPS listener (port 443) - only created if certificate_arn is provided
  - Health check on `/healthz` endpoint
- **efs.tf**: EFS file system for n8n data persistence
  - Mount targets in private subnets
  - Access point with specific permissions (uid/gid 1000)
- **iam.tf**: IAM roles for ECS tasks
  - Task role: CloudWatch logs permissions
  - Execution role: CloudWatch logs permissions

### Key Architectural Decisions

1. **Single Instance**: `desired_count` defaults to 1 because n8n has issues with webhook deregistration when running multiple instances behind a load balancer

2. **Public IP on ECS Tasks**: Tasks are assigned public IPs to pull Docker images without requiring a NAT gateway or VPC endpoints (cost optimization)

3. **EFS for State**: All n8n state is stored on EFS at `/home/node/.n8n-fresh`. **You must backup this volume yourself.**

4. **Fargate Spot**: Uses FARGATE_SPOT by default for cost savings. Instances may be replaced occasionally.

5. **No SSL/TLS on ALB (Optional)**: SSL is optional to keep costs low. If `certificate_arn` is null, ALB only listens on HTTP. You can use Cloudflare or similar service for SSL termination.

6. **Environment Variables**: The task definition in ecs.tf:58-71 contains hardcoded environment variables (WEBHOOK_URL, N8N_EDITOR_BASE_URL, N8N_HOST). These should be updated based on the actual domain/URL being used.

### Data Flow

```
Internet → ALB (HTTP/HTTPS) → ECS Task (port 5678) → n8n container
                                        ↓
                                    EFS mount (/home/node/.n8n-fresh)
```

### Security Groups

- **ALB SG**: Allows inbound 80/443 from anywhere, outbound to VPC CIDR
- **ECS Task SG**: Allows inbound 5678 from ALB SG, outbound to anywhere
- **EFS SG**: Allows inbound 2049 (NFS) from VPC CIDR

## Important Notes

### Backend State Management

The module uses S3 for remote state storage with DynamoDB for state locking. The `setup-backend.sh` script automates the creation of these resources with proper encryption and versioning enabled.

### Authentication Options

Two authentication methods are supported:
1. **AWS Profile** (recommended): Set `aws_profile` in terraform.tfvars
2. **Access Keys**: Set `aws_access_key` and `aws_secret_key` (if no profile)

The provider in main.tf:4-7 conditionally uses profile or keys.

### Required Variables

When creating terraform.tfvars, these are essential:
- `project_name`: Project identifier
- `region`: AWS region
- `certificate_arn`: ACM certificate ARN (can be null for HTTP-only)
- `domain`: Domain name (can be null)
- `backend_bucket`: S3 bucket for state
- `backend_dynamodb_table`: DynamoDB table for locking

### Hardcoded Values to Update

In **ecs.tf**, the environment variables (lines 58-67) contain hardcoded domain values that should be replaced:
- `WEBHOOK_URL`
- `N8N_EDITOR_BASE_URL`
- `N8N_HOST`

These should ideally use `var.domain` or `var.url` instead of hardcoded values.

### VPC Configuration

The VPC module creates:
- CIDR: `10.0.0.0/16`
- Public subnets: `10.0.4.0/24`, `10.0.5.0/24`, `10.0.6.0/24`
- Private subnets: `10.0.0.0/24`, `10.0.1.0/24`, `10.0.2.0/24`
- No NAT gateway (cost optimization)
- Spans first 3 availability zones in region

### Tags Support

All resources support optional tags via the `tags` variable (map of strings). Pass tags in terraform.tfvars to apply them across all created resources.

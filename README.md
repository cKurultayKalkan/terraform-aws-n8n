# Terraform AWS N8n Module

## Description

This sets up a N8n cluster with two Fargate Spot instances and a ALB. It is backed by an EFS file system to store the state. The total costs are around 3 USD per month (provided your ALB is in the free tier).
It does not come with SSL (optionally it can listen for SSL connections), but this would raise the cost. You can also use a service like Cloudflare to run the SSL for you.

Note: This module has been setup as a cheap and easy way to run N8n. Data is stored on a EFS volume (you must back this up yourself). We use a single instance (Fargate Spot) so it might be replaced every now and then. N8n is not ment to run stateless behind a load balancer (you will get issues with webhooks).

Check out or blog post about it here: [Run n8n on AWS for less than a cup of coffee per month](https://elasticscale.com/blog/run-n8n-on-aws-for-less-than-a-cup-of-coffee-per-month/)

## About ElasticScale

Discover ES Foundation, the smart digital infrastructure for SaaS companies that want to grow and thrive.

Check out our <a href="https://elasticscale.com" target="_blank" style="color: #FFB600; text-decoration: underline">website</a> for more information.

<img src="https://static.elasticscale.io/email/banner.png" alt="ElasticScale banner" width="100%"/>

## Quick Start

### Prerequisites

1. AWS CLI configured with appropriate credentials
2. Terraform installed (>= 1.0)
3. An AWS account with permissions to create required resources

### Setup Instructions

1. **Clone the repository and prepare configuration:**
```bash
# Copy the example configuration file
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your values
vim terraform.tfvars
```

2. **Setup backend infrastructure (S3 & DynamoDB):**
```bash
# This script automatically creates S3 bucket and DynamoDB table
./setup-backend.sh
```

3. **Initialize Terraform with S3 backend:**
```bash
# The init.sh script reads backend configuration from terraform.tfvars
./init.sh
```

4. **Review and apply the configuration:**
```bash
# Review planned changes
terraform plan

# Apply the configuration
terraform apply
```

## AWS Authentication Options

### Option 1: AWS Profile (Recommended)

Use an existing AWS CLI profile:
```hcl
aws_profile = "my-aws-profile"
```

### Option 2: Access Keys

Provide AWS credentials directly:
```hcl
aws_access_key = "AKIAIOSFODNN7EXAMPLE"
aws_secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
```

## Terraform State Management (S3 & DynamoDB)

This module is configured to use S3 for state storage and DynamoDB for state locking.

### Automatic Backend Setup

The `setup-backend.sh` script automatically creates and configures:
- S3 bucket with versioning and encryption enabled
- DynamoDB table for state locking with on-demand billing

Simply run:
```bash
./setup-backend.sh
```

The script will:
1. Read configuration from `terraform.tfvars`
2. Create S3 bucket if it doesn't exist
3. Enable versioning and encryption on the bucket
4. Create DynamoDB table if it doesn't exist
5. Configure everything according to your region settings

### Migrating Existing State to S3

If you have an existing local state file:
```bash
terraform init -migrate-state \
  -backend-config="bucket=your-bucket" \
  -backend-config="key=n8n/terraform.tfstate" \
  -backend-config="region=us-west-1" \
  -backend-config="dynamodb_table=your-table" \
  -backend-config="encrypt=true"
```

### Required IAM Permissions

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketVersioning"
      ],
      "Resource": "arn:aws:s3:::your-terraform-state-bucket"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::your-terraform-state-bucket/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:DescribeTable",
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem"
      ],
      "Resource": "arn:aws:dynamodb:*:*:table/terraform-state-lock"
    }
  ]
}
```

## Security Best Practices

1. **S3 Bucket Encryption:** Always enable encryption for your state bucket
2. **IAM Permissions:** Use least privilege principle
3. **MFA:** Enable MFA for production environments
4. **Bucket Policy:** Restrict access to authorized users only
5. **Backup:** Regularly backup your EFS volume and state files

## Module Configuration

### Required Variables

| Name | Description | Type |
|------|-------------|------|
| `project_name` | Project name | `string` |
| `region` | AWS Region (e.g., us-west-1) | `string` |
| `certificate_arn` | ACM certificate ARN for SSL | `string` |
| `domain` | Domain name for N8n | `string` |
| `backend_bucket` | S3 bucket for Terraform state | `string` |
| `backend_dynamodb_table` | DynamoDB table for state lock | `string` |

### Optional Variables

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `prefix` | Prefix to add to all resources | `string` | `"n8n"` |
| `desired_count` | Desired count of n8n tasks | `number` | `1` |
| `container_image` | Container image to use for n8n | `string` | `"n8nio/n8n:latest"` |
| `fargate_type` | Fargate type (FARGATE or FARGATE_SPOT) | `string` | `"FARGATE_SPOT"` |
| `ssl_policy` | SSL policy for HTTPS listener | `string` | `"ELBSecurityPolicy-TLS13-1-2-2021-06"` |
| `url` | URL for n8n (needs trailing slash) | `string` | `null` |
| `backend_key` | S3 key for state file | `string` | `"n8n/terraform.tfstate"` |
| `aws_profile` | AWS Profile name (optional) | `string` | `null` |
| `aws_access_key` | AWS Access Key (if not using profile) | `string` | `null` |
| `aws_secret_key` | AWS Secret Key (if not using profile) | `string` | `null` |
| `tags` | Tags to apply to all resources | `map(string)` | `null` |

## Outputs

| Name | Description |
|------|-------------|
| `lb_dns_name` | Load balancer DNS name |

## Providers

| Name | Version |
|------|---------|
| aws | n/a |

## Modules

| Name | Source | Version |
|------|--------|---------|
| vpc | terraform-aws-modules/vpc/aws | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_group.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ecs_cluster.ecs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster) | resource |
| [aws_ecs_cluster_capacity_providers.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster_capacity_providers) | resource |
| [aws_ecs_service.service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_task_definition.taskdef](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_efs_access_point.access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_access_point) | resource |
| [aws_efs_file_system.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_file_system) | resource |
| [aws_efs_mount_target.mount](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_mount_target) | resource |
| [aws_iam_role.executionrole](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.taskrole](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_lb.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.http](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener.https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_target_group.ip](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_security_group.alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.efs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.n8n](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Additional Input Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_alb_allowed_cidr_blocks"></a> [alb\_allowed\_cidr\_blocks](#input\_alb\_allowed\_cidr\_blocks) | List of CIDR blocks allowed to access the ALB (default: allows all traffic) | `list(string)` | `["0.0.0.0/0"]` | no |
| <a name="input_certificate_arn"></a> [certificate\_arn](#input\_certificate\_arn) | Certificate ARN for HTTPS support | `string` | `null` | no |
| <a name="input_container_image"></a> [container\_image](#input\_container\_image) | Container image to use for n8n | `string` | `"n8nio/n8n:1.4.0"` | no |
| <a name="input_desired_count"></a> [desired\_count](#input\_desired\_count) | Desired count of n8n tasks, be careful with this to make it more than 1 as it can cause issues with webhooks not registering properly | `number` | `1` | no |
| <a name="input_fargate_type"></a> [fargate\_type](#input\_fargate\_type) | Fargate type to use for n8n (either FARGATE or FARGATE\_SPOT)) | `string` | `"FARGATE_SPOT"` | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefix to add to all resources | `string` | `"n8n"` | no |
| <a name="input_public_subnet_ids"></a> [public\_subnet\_ids](#input\_public\_subnet\_ids) | Public subnet IDs for ALB (optional, uses VPC public subnets if not provided) | `list(string)` | `[]` | no |
| <a name="input_ssl_policy"></a> [ssl\_policy](#input\_ssl\_policy) | SSL policy for HTTPS listner. | `string` | `ELBSecurityPolicy-TLS13-1-2-2021-06` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnet IDs for ECS tasks (optional, uses VPC subnets if not provided) | `list(string)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `null` | no |
| <a name="input_url"></a> [url](#input\_url) | URL for n8n (default is LB url), needs a trailing slash if you specify it | `string` | `null` | no |
| <a name="input_use_private_subnets"></a> [use\_private\_subnets](#input\_use\_private\_subnets) | Whether to deploy ECS tasks in private subnets (requires NAT Gateway or VPC endpoints for internet access) | `bool` | `false` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID to deploy n8n into (optional, creates new VPC if not provided) | `string` | `null` | no |

## Support

For issues, questions, or contributions, please open an issue in the GitHub repository.

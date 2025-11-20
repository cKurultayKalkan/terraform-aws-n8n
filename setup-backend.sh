#!/bin/bash

# Terraform Backend Setup Script
# This script automatically creates S3 bucket and DynamoDB table for Terraform state management

set -e

# Color variables for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Terraform Backend Infrastructure Setup Script        ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
    echo -e "${RED}Error: terraform.tfvars file not found!${NC}"
    echo -e "${YELLOW}Please copy and edit terraform.tfvars.example first:${NC}"
    echo "cp terraform.tfvars.example terraform.tfvars"
    exit 1
fi

# Read variables from terraform.tfvars file
get_tfvar() {
    local value=$(grep "^$1" terraform.tfvars | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^"//;s/"$//')
    echo "$value"
}

# Get configuration values
BACKEND_BUCKET=$(get_tfvar "backend_bucket")
BACKEND_DYNAMODB_TABLE=$(get_tfvar "backend_dynamodb_table")
REGION=$(get_tfvar "region")
AWS_PROFILE=$(get_tfvar "aws_profile")

# Use defaults if not specified
if [ -z "$REGION" ]; then
    REGION="us-east-1"
fi

# Check required variables
if [ -z "$BACKEND_BUCKET" ] || [ -z "$BACKEND_DYNAMODB_TABLE" ]; then
    echo -e "${RED}Error: Backend variables are missing!${NC}"
    echo "Please define the following variables in terraform.tfvars:"
    echo "  - backend_bucket"
    echo "  - backend_dynamodb_table"
    exit 1
fi

# Set AWS profile if specified
if [ ! -z "$AWS_PROFILE" ]; then
    export AWS_PROFILE=$AWS_PROFILE
    PROFILE_ARG="--profile $AWS_PROFILE"
else
    PROFILE_ARG=""
fi

echo -e "${YELLOW}Configuration:${NC}"
echo "  Region: $REGION"
echo "  S3 Bucket: $BACKEND_BUCKET"
echo "  DynamoDB Table: $BACKEND_DYNAMODB_TABLE"
if [ ! -z "$AWS_PROFILE" ]; then
    echo "  AWS Profile: $AWS_PROFILE"
fi
echo ""

# Function to check if S3 bucket exists
check_s3_bucket() {
    aws s3api head-bucket --bucket "$1" --region "$2" $PROFILE_ARG 2>/dev/null
    return $?
}

# Function to check if DynamoDB table exists
check_dynamodb_table() {
    aws dynamodb describe-table --table-name "$1" --region "$2" $PROFILE_ARG 2>/dev/null > /dev/null
    return $?
}

# Create S3 bucket
echo -e "${YELLOW}Checking S3 bucket...${NC}"
if check_s3_bucket "$BACKEND_BUCKET" "$REGION"; then
    echo -e "${GREEN}✓ S3 bucket '$BACKEND_BUCKET' already exists${NC}"
else
    echo -e "${YELLOW}Creating S3 bucket '$BACKEND_BUCKET' in region '$REGION'...${NC}"
    
    # Special handling for us-east-1 (no LocationConstraint needed)
    if [ "$REGION" = "us-east-1" ]; then
        aws s3api create-bucket \
            --bucket "$BACKEND_BUCKET" \
            --region "$REGION" \
            $PROFILE_ARG
    else
        aws s3api create-bucket \
            --bucket "$BACKEND_BUCKET" \
            --region "$REGION" \
            --create-bucket-configuration LocationConstraint="$REGION" \
            $PROFILE_ARG
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ S3 bucket created successfully${NC}"
    else
        echo -e "${RED}✗ Failed to create S3 bucket${NC}"
        echo -e "${YELLOW}Note: The bucket name might already be taken globally. Try a different name.${NC}"
        exit 1
    fi
fi

# Enable versioning on S3 bucket
echo -e "${YELLOW}Enabling versioning on S3 bucket...${NC}"
aws s3api put-bucket-versioning \
    --bucket "$BACKEND_BUCKET" \
    --versioning-configuration Status=Enabled \
    --region "$REGION" \
    $PROFILE_ARG

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Versioning enabled${NC}"
else
    echo -e "${YELLOW}⚠ Could not enable versioning (might already be enabled)${NC}"
fi

# Enable encryption on S3 bucket
echo -e "${YELLOW}Enabling default encryption on S3 bucket...${NC}"
aws s3api put-bucket-encryption \
    --bucket "$BACKEND_BUCKET" \
    --server-side-encryption-configuration '{
        "Rules": [
            {
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }
        ]
    }' \
    --region "$REGION" \
    $PROFILE_ARG

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Encryption enabled${NC}"
else
    echo -e "${YELLOW}⚠ Could not enable encryption (might already be enabled)${NC}"
fi

# Create DynamoDB table
echo -e "${YELLOW}Checking DynamoDB table...${NC}"
if check_dynamodb_table "$BACKEND_DYNAMODB_TABLE" "$REGION"; then
    echo -e "${GREEN}✓ DynamoDB table '$BACKEND_DYNAMODB_TABLE' already exists${NC}"
else
    echo -e "${YELLOW}Creating DynamoDB table '$BACKEND_DYNAMODB_TABLE'...${NC}"
    aws dynamodb create-table \
        --table-name "$BACKEND_DYNAMODB_TABLE" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "$REGION" \
        $PROFILE_ARG
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ DynamoDB table created successfully${NC}"
        
        # Wait for table to be active
        echo -e "${YELLOW}Waiting for DynamoDB table to be active...${NC}"
        aws dynamodb wait table-exists \
            --table-name "$BACKEND_DYNAMODB_TABLE" \
            --region "$REGION" \
            $PROFILE_ARG
        echo -e "${GREEN}✓ DynamoDB table is active${NC}"
    else
        echo -e "${RED}✗ Failed to create DynamoDB table${NC}"
        exit 1
    fi
fi

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Backend infrastructure setup completed successfully!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Run ${GREEN}./init.sh${NC} to initialize Terraform with the backend"
echo "2. Run ${GREEN}terraform plan${NC} to review the infrastructure changes"
echo "3. Run ${GREEN}terraform apply${NC} to create the infrastructure"
echo ""
echo -e "${BLUE}Backend Configuration Summary:${NC}"
echo "  S3 Bucket: $BACKEND_BUCKET"
echo "  DynamoDB Table: $BACKEND_DYNAMODB_TABLE"
echo "  Region: $REGION"
echo ""
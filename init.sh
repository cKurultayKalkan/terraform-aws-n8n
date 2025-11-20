#!/bin/bash

# Terraform Backend Initialization Script
# This script reads backend variables from terraform.tfvars and runs terraform init

set -e

# Color variables for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Terraform Backend Initialization${NC}"
echo "=================================="

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
    echo -e "${RED}Error: terraform.tfvars file not found!${NC}"
    echo -e "${YELLOW}Please copy and edit terraform.tfvars.example first:${NC}"
    echo "cp terraform.tfvars.example terraform.tfvars"
    exit 1
fi

# Read backend variables from terraform.tfvars file
get_tfvar() {
    local value=$(grep "^$1" terraform.tfvars | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^"//;s/"$//')
    echo "$value"
}

BACKEND_BUCKET=$(get_tfvar "backend_bucket")
BACKEND_KEY=$(get_tfvar "backend_key")
BACKEND_DYNAMODB_TABLE=$(get_tfvar "backend_dynamodb_table")
REGION=$(get_tfvar "region")
AWS_PROFILE=$(get_tfvar "aws_profile")

# Default values
if [ -z "$BACKEND_KEY" ]; then
    BACKEND_KEY="n8n/terraform.tfstate"
fi

if [ -z "$REGION" ]; then
    REGION="us-west-1"
fi

# Check if backend variables are present
if [ -z "$BACKEND_BUCKET" ] || [ -z "$BACKEND_DYNAMODB_TABLE" ]; then
    echo -e "${RED}Error: Backend variables are missing!${NC}"
    echo "Please define the following variables in terraform.tfvars:"
    echo "  - backend_bucket"
    echo "  - backend_dynamodb_table"
    exit 1
fi

echo -e "${GREEN}Backend Configuration:${NC}"
echo "  Bucket: $BACKEND_BUCKET"
echo "  Key: $BACKEND_KEY"
echo "  Region: $REGION"
echo "  DynamoDB Table: $BACKEND_DYNAMODB_TABLE"
if [ ! -z "$AWS_PROFILE" ]; then
    echo "  AWS Profile: $AWS_PROFILE"
fi
echo ""

# Create backend configuration
BACKEND_CONFIG="-backend-config=bucket=$BACKEND_BUCKET"
BACKEND_CONFIG="$BACKEND_CONFIG -backend-config=key=$BACKEND_KEY"
BACKEND_CONFIG="$BACKEND_CONFIG -backend-config=region=$REGION"
BACKEND_CONFIG="$BACKEND_CONFIG -backend-config=dynamodb_table=$BACKEND_DYNAMODB_TABLE"
BACKEND_CONFIG="$BACKEND_CONFIG -backend-config=encrypt=true"

if [ ! -z "$AWS_PROFILE" ]; then
    BACKEND_CONFIG="$BACKEND_CONFIG -backend-config=profile=$AWS_PROFILE"
fi

# Run terraform init command
echo -e "${YELLOW}Running terraform init...${NC}"
echo "Command: terraform init $BACKEND_CONFIG"
echo ""

terraform init $BACKEND_CONFIG

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ Terraform successfully initialized!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. terraform plan    - Review planned changes"
    echo "  2. terraform apply   - Apply the changes"
else
    echo -e "${RED}✗ Terraform init failed!${NC}"
    exit 1
fi
#!/bin/bash

# n8n Version Upgrade Script
# This script upgrades the n8n container to the latest version or a specific version

set -e

# Color variables for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║            n8n Version Upgrade Script                    ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
    echo -e "${RED}Error: terraform.tfvars file not found!${NC}"
    echo "This script must be run from the terraform-aws-n8n directory."
    exit 1
fi

# Read variables from terraform.tfvars file
get_tfvar() {
    local value=$(grep "^$1" terraform.tfvars | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^"//;s/"$//')
    echo "$value"
}

# Get configuration values
PREFIX=$(get_tfvar "prefix")
REGION=$(get_tfvar "region")
AWS_PROFILE=$(get_tfvar "aws_profile")

# Use defaults if not specified
if [ -z "$PREFIX" ]; then
    PREFIX="n8n"
fi

if [ -z "$REGION" ]; then
    REGION="us-west-1"
fi

# Set AWS profile if specified
PROFILE_ARG=""
if [ ! -z "$AWS_PROFILE" ]; then
    export AWS_PROFILE=$AWS_PROFILE
    PROFILE_ARG="--profile $AWS_PROFILE"
fi

# Set AWS region
export AWS_DEFAULT_REGION=$REGION

# Resource names
CLUSTER_NAME="${PREFIX}-cluster"
SERVICE_NAME="${PREFIX}-service"

echo -e "${YELLOW}Current Configuration:${NC}"
echo "  Region: $REGION"
echo "  Cluster: $CLUSTER_NAME"
echo "  Service: $SERVICE_NAME"
if [ ! -z "$AWS_PROFILE" ]; then
    echo "  AWS Profile: $AWS_PROFILE"
fi
echo ""

# Function to get current n8n version from running task
get_current_version() {
    echo -e "${YELLOW}Fetching current n8n version...${NC}"

    # Get task ARN
    TASK_ARN=$(aws ecs list-tasks \
        --cluster "$CLUSTER_NAME" \
        --service-name "$SERVICE_NAME" \
        --desired-status RUNNING \
        --region "$REGION" \
        $PROFILE_ARG \
        --query 'taskArns[0]' \
        --output text 2>/dev/null || echo "")

    if [ -z "$TASK_ARN" ] || [ "$TASK_ARN" = "None" ]; then
        echo -e "${YELLOW}⚠ No running tasks found${NC}"
        return 1
    fi

    # Get task definition
    TASK_DEF_ARN=$(aws ecs describe-tasks \
        --cluster "$CLUSTER_NAME" \
        --tasks "$TASK_ARN" \
        --region "$REGION" \
        $PROFILE_ARG \
        --query 'tasks[0].taskDefinitionArn' \
        --output text 2>/dev/null || echo "")

    if [ -z "$TASK_DEF_ARN" ]; then
        echo -e "${YELLOW}⚠ Could not fetch task definition${NC}"
        return 1
    fi

    # Get container image
    CURRENT_IMAGE=$(aws ecs describe-task-definition \
        --task-definition "$TASK_DEF_ARN" \
        --region "$REGION" \
        $PROFILE_ARG \
        --query 'taskDefinition.containerDefinitions[0].image' \
        --output text 2>/dev/null || echo "")

    if [ ! -z "$CURRENT_IMAGE" ]; then
        echo -e "${GREEN}✓ Current image: ${CYAN}$CURRENT_IMAGE${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ Could not determine current version${NC}"
        return 1
    fi
}

# Get latest n8n version from Docker Hub
get_latest_version() {
    # Print messages to stderr so they don't interfere with return value
    echo -e "${YELLOW}Checking latest n8n version from Docker Hub...${NC}" >&2

    # Get latest tag from Docker Hub API
    LATEST_VERSION=$(curl -s 'https://registry.hub.docker.com/v2/repositories/n8nio/n8n/tags?page_size=100' | \
        grep -o '"name":"[^"]*"' | \
        grep -v "latest" | \
        grep -E '"name":"[0-9]+\.[0-9]+\.[0-9]+"' | \
        head -1 | \
        cut -d'"' -f4 | tr -d '\n\r')

    if [ ! -z "$LATEST_VERSION" ]; then
        echo -e "${GREEN}✓ Latest version: ${CYAN}$LATEST_VERSION${NC}" >&2
        # Only return the image name to stdout
        echo "n8nio/n8n:$LATEST_VERSION"
    else
        echo -e "${YELLOW}⚠ Could not fetch latest version, using 'latest' tag${NC}" >&2
        echo "n8nio/n8n:latest"
    fi
}

# Main upgrade process
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo ""

# Show current version
get_current_version
echo ""

# Ask user for target version
echo -e "${YELLOW}Choose upgrade option:${NC}"
echo "  1) Upgrade to latest version (recommended)"
echo "  2) Specify a version manually"
echo "  3) Exit"
echo ""
read -p "Enter your choice (1-3): " choice

case $choice in
    1)
        TARGET_IMAGE=$(get_latest_version)
        ;;
    2)
        read -p "Enter n8n version (e.g., 1.19.4 or latest): " version
        if [ -z "$version" ]; then
            echo -e "${RED}Error: Version cannot be empty${NC}"
            exit 1
        fi
        TARGET_IMAGE="n8nio/n8n:$version"
        ;;
    3)
        echo -e "${YELLOW}Upgrade cancelled.${NC}"
        exit 0
        ;;
    *)
        echo -e "${RED}Invalid choice. Exiting.${NC}"
        exit 1
        ;;
esac

# Trim whitespace and newlines from TARGET_IMAGE
TARGET_IMAGE=$(echo "$TARGET_IMAGE" | tr -d '\n\r' | xargs)

echo ""
echo -e "${YELLOW}Target image: ${CYAN}$TARGET_IMAGE${NC}"
echo ""

# Confirm before proceeding
echo -e "${YELLOW}⚠ WARNING: This will update your n8n deployment${NC}"
echo -e "${YELLOW}The service will be temporarily unavailable during the upgrade.${NC}"
echo ""
read -p "Do you want to proceed? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo -e "${YELLOW}Upgrade cancelled.${NC}"
    exit 0
fi

echo ""
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Starting upgrade process...${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo ""

# Step 1: Update variables.tf or create terraform.tfvars override
echo -e "${YELLOW}[1/5] Updating container image configuration...${NC}"

# Backup terraform.tfvars
cp terraform.tfvars terraform.tfvars.bak

# Check if container_image is already in terraform.tfvars
if grep -q "^container_image" terraform.tfvars 2>/dev/null; then
    # Update existing value using awk (more reliable than sed on macOS)
    awk -v img="$TARGET_IMAGE" '
        /^container_image/ {
            print "container_image = \"" img "\""
            next
        }
        {print}
    ' terraform.tfvars.bak > terraform.tfvars
    echo -e "${GREEN}✓ Updated container_image in terraform.tfvars${NC}"
else
    # Add new value
    echo "" >> terraform.tfvars
    echo "# n8n Container Image Version" >> terraform.tfvars
    echo "container_image = \"$TARGET_IMAGE\"" >> terraform.tfvars
    echo -e "${GREEN}✓ Added container_image to terraform.tfvars${NC}"
fi

# Step 2: Terraform plan
echo ""
echo -e "${YELLOW}[2/5] Running terraform plan...${NC}"
terraform plan -out=upgrade.tfplan

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Terraform plan failed!${NC}"
    # Restore backup
    if [ -f terraform.tfvars.bak ]; then
        mv terraform.tfvars.bak terraform.tfvars
        echo -e "${YELLOW}Restored original terraform.tfvars${NC}"
    fi
    exit 1
fi

# Step 3: Apply changes
echo ""
echo -e "${YELLOW}[3/5] Applying terraform changes...${NC}"
terraform apply upgrade.tfplan

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Terraform apply failed!${NC}"
    exit 1
fi

# Clean up plan file
rm -f upgrade.tfplan

# Step 4: Force new deployment
echo ""
echo -e "${YELLOW}[4/5] Forcing new deployment...${NC}"
aws ecs update-service \
    --cluster "$CLUSTER_NAME" \
    --service "$SERVICE_NAME" \
    --force-new-deployment \
    --region "$REGION" \
    $PROFILE_ARG \
    > /dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Deployment triggered${NC}"
else
    echo -e "${RED}✗ Failed to trigger deployment${NC}"
    exit 1
fi

# Step 5: Wait for service to stabilize
echo ""
echo -e "${YELLOW}[5/5] Waiting for service to stabilize...${NC}"
echo -e "${CYAN}This may take a few minutes. Please wait...${NC}"
echo ""

aws ecs wait services-stable \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --region "$REGION" \
    $PROFILE_ARG

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Service is stable${NC}"
else
    echo -e "${YELLOW}⚠ Service stabilization check timed out${NC}"
    echo -e "${YELLOW}Check the ECS console for service status${NC}"
fi

# Clean up backup file
rm -f terraform.tfvars.bak

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Upgrade completed successfully!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""

# Show updated version
echo -e "${YELLOW}Verifying new version...${NC}"
sleep 5  # Wait a bit for task to fully start
get_current_version

echo ""
echo -e "${CYAN}Useful commands:${NC}"
echo "  - Check service status:"
echo "    ${GREEN}aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --region $REGION${NC}"
echo ""
echo "  - View logs:"
echo "    ${GREEN}aws logs tail /aws/ecs/${PREFIX}-logs --follow --region $REGION${NC}"
echo ""
echo "  - Rollback if needed:"
echo "    ${GREEN}terraform apply${NC} (after reverting terraform.tfvars changes)"
echo ""

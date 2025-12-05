#!/bin/bash

# n8n Backup Management Script
# This script helps you manage backups of your n8n EFS file system

set -e

# Color variables for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║            n8n Backup Management                         ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
    echo -e "${RED}Error: terraform.tfvars file not found!${NC}"
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

export AWS_DEFAULT_REGION=$REGION

BACKUP_VAULT="${PREFIX}-backup-vault"

echo -e "${YELLOW}Configuration:${NC}"
echo "  Region: $REGION"
echo "  Backup Vault: $BACKUP_VAULT"
if [ ! -z "$AWS_PROFILE" ]; then
    echo "  AWS Profile: $AWS_PROFILE"
fi
echo ""

# Function to list recent backups
list_backups() {
    echo -e "${CYAN}Recent Backups:${NC}"
    echo ""

    aws backup list-recovery-points-by-backup-vault \
        --backup-vault-name "$BACKUP_VAULT" \
        --region "$REGION" \
        $PROFILE_ARG \
        --query 'RecoveryPoints[*].[RecoveryPointArn,CreationDate,Status,ResourceType]' \
        --output table
}

# Function to trigger manual backup
create_backup() {
    echo -e "${YELLOW}Creating manual backup...${NC}"

    # Get EFS file system ID
    EFS_ID=$(aws efs describe-file-systems \
        --region "$REGION" \
        $PROFILE_ARG \
        --query "FileSystems[?Tags[?Key=='Name' && Value=='${PREFIX}-efs']].FileSystemId" \
        --output text 2>/dev/null || echo "")

    if [ -z "$EFS_ID" ]; then
        echo -e "${RED}✗ Could not find EFS file system${NC}"
        echo -e "${YELLOW}Trying alternative method...${NC}"

        EFS_ID=$(terraform output -raw efs_id 2>/dev/null || echo "")

        if [ -z "$EFS_ID" ]; then
            echo -e "${RED}✗ Could not determine EFS ID${NC}"
            return 1
        fi
    fi

    echo -e "${GREEN}✓ Found EFS: $EFS_ID${NC}"

    # Get backup role ARN
    ROLE_ARN=$(aws iam get-role \
        --role-name "${PREFIX}-backup-role" \
        --region "$REGION" \
        $PROFILE_ARG \
        --query 'Role.Arn' \
        --output text 2>/dev/null || echo "")

    if [ -z "$ROLE_ARN" ]; then
        echo -e "${RED}✗ Could not find backup role${NC}"
        echo -e "${YELLOW}Make sure you've applied the backup.tf configuration${NC}"
        return 1
    fi

    # Start backup
    BACKUP_JOB_ID=$(aws backup start-backup-job \
        --backup-vault-name "$BACKUP_VAULT" \
        --resource-arn "arn:aws:elasticfilesystem:${REGION}:$(aws sts get-caller-identity $PROFILE_ARG --query Account --output text):file-system/${EFS_ID}" \
        --iam-role-arn "$ROLE_ARN" \
        --region "$REGION" \
        $PROFILE_ARG \
        --query 'BackupJobId' \
        --output text)

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Backup started successfully${NC}"
        echo "  Backup Job ID: $BACKUP_JOB_ID"
        echo ""
        echo -e "${CYAN}Monitor progress with:${NC}"
        echo "  aws backup describe-backup-job --backup-job-id $BACKUP_JOB_ID --region $REGION"
    else
        echo -e "${RED}✗ Failed to start backup${NC}"
        return 1
    fi
}

# Function to show backup vault info
show_vault_info() {
    echo -e "${CYAN}Backup Vault Information:${NC}"
    echo ""

    aws backup describe-backup-vault \
        --backup-vault-name "$BACKUP_VAULT" \
        --region "$REGION" \
        $PROFILE_ARG \
        --output table
}

# Function to show backup plan
show_backup_plan() {
    echo -e "${CYAN}Backup Plan Configuration:${NC}"
    echo ""

    PLAN_ID=$(aws backup list-backup-plans \
        --region "$REGION" \
        $PROFILE_ARG \
        --query "BackupPlansList[?BackupPlanName=='${PREFIX}-backup-plan'].BackupPlanId" \
        --output text 2>/dev/null || echo "")

    if [ -z "$PLAN_ID" ]; then
        echo -e "${YELLOW}⚠ No backup plan found${NC}"
        echo -e "${YELLOW}Make sure you've run: terraform apply${NC}"
        return 1
    fi

    aws backup get-backup-plan \
        --backup-plan-id "$PLAN_ID" \
        --region "$REGION" \
        $PROFILE_ARG \
        --output json | jq -r '.BackupPlan'
}

# Menu
echo -e "${YELLOW}What would you like to do?${NC}"
echo "  1) List recent backups"
echo "  2) Create manual backup now"
echo "  3) Show backup vault information"
echo "  4) Show backup plan configuration"
echo "  5) Exit"
echo ""
read -p "Enter your choice (1-5): " choice

case $choice in
    1)
        list_backups
        ;;
    2)
        create_backup
        ;;
    3)
        show_vault_info
        ;;
    4)
        show_backup_plan
        ;;
    5)
        echo -e "${YELLOW}Exiting...${NC}"
        exit 0
        ;;
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}Useful AWS CLI Commands:${NC}"
echo ""
echo "  # List all backups:"
echo "  ${GREEN}aws backup list-recovery-points-by-backup-vault --backup-vault-name $BACKUP_VAULT --region $REGION${NC}"
echo ""
echo "  # Check backup job status:"
echo "  ${GREEN}aws backup list-backup-jobs --by-backup-vault-name $BACKUP_VAULT --region $REGION${NC}"
echo ""
echo "  # Restore from backup (use recovery point ARN from list):"
echo "  ${GREEN}aws backup start-restore-job --recovery-point-arn <ARN> --region $REGION${NC}"
echo ""

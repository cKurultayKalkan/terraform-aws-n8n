# AWS Backup for EFS
# This creates daily backups of the n8n EFS file system

# Backup Vault
resource "aws_backup_vault" "n8n" {
  name = "${var.prefix}-backup-vault"
  tags = var.tags
}

# Backup Plan - Daily backups with 7 day retention
resource "aws_backup_plan" "n8n" {
  name = "${var.prefix}-backup-plan"

  rule {
    rule_name         = "daily_backup"
    target_vault_name = aws_backup_vault.n8n.name
    schedule          = "cron(0 2 * * ? *)" # 2 AM UTC daily

    lifecycle {
      delete_after = var.backup_retention_days
    }

    # Optional: Copy to another region for disaster recovery
    # Uncomment and configure if needed
    # copy_action {
    #   destination_vault_arn = "arn:aws:backup:us-west-2:ACCOUNT_ID:backup-vault:vault-name"
    #   lifecycle {
    #     delete_after = 7
    #   }
    # }
  }

  tags = var.tags
}

# IAM Role for AWS Backup
resource "aws_iam_role" "backup" {
  name = "${var.prefix}-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# Attach AWS managed policy for backup
resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

# Attach AWS managed policy for restore
resource "aws_iam_role_policy_attachment" "restore" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# Backup Selection - Automatically backup EFS
resource "aws_backup_selection" "n8n" {
  name         = "${var.prefix}-backup-selection"
  plan_id      = aws_backup_plan.n8n.id
  iam_role_arn = aws_iam_role.backup.arn

  resources = [
    aws_efs_file_system.main.arn
  ]
}

# Output backup vault info
output "backup_vault_name" {
  description = "Name of the backup vault"
  value       = aws_backup_vault.n8n.name
}

output "backup_vault_arn" {
  description = "ARN of the backup vault"
  value       = aws_backup_vault.n8n.arn
}

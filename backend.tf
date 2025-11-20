terraform {
  backend "s3" {
    # S3 bucket for storing Terraform state
    # bucket = "your-terraform-state-bucket"
    # key    = "n8n/terraform.tfstate"
    # region = "us-west-1"
    
    # DynamoDB table for state locking
    # dynamodb_table = "terraform-state-lock"
    
    # Encryption
    # encrypt = true
    
    # Optional: Use AWS profile instead of access keys
    # profile = "your-aws-profile"
  }
}
provider "aws" {
  region = var.region
  
  # Use AWS Profile if provided, otherwise use access key/secret key
  profile    = var.aws_profile
  access_key = var.aws_profile != null ? null : var.aws_access_key
  secret_key = var.aws_profile != null ? null : var.aws_secret_key
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
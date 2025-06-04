variable "project_name" {
  type        = string
  description = "Proje İsmi"
}
variable "aws_access_key" {
  description = "AWS Access Key"
}
variable "aws_secret_key" {
  description = "AWS Secret Key"
}
variable "region" {
  type        = string
  default     = "us-west-1"
  description = "AWS Region. örneğin us-west-1"
}
variable "certificate_arn" {
  type        = string
  description = "SSL için kullanılacak sertifikanın ARNsi"
}
variable "domain" {
  description = "Kullanmak istediğiniz alan adı"
}

provider "aws" {
  region     = var.region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key

}

// you can also inject a SSL certificate, or just Cloudflare for free SSL
module "n8n" {
  source          = "../../"
  certificate_arn = var.certificate_arn
  prefix          = var.project_name
  url             = var.domain + "/"
}

output "lb_dns_name" {
  value = module.n8n.lb_dns_name
}

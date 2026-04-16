variable "public_subnet_ids" { type = list(string) }
variable "security_group_id" {}
variable "target_group_arn" {}
variable "ami_id" {
  default = null
}
variable "key_name" {
  default = "vockey"
}
variable "db_endpoint" {}
variable "db_name" {}
variable "db_username" {}
variable "db_password" {sensitive = true}

variable "efs_dns_name" {
  description = "EFS DNS name for WordPress uploads mount"
}
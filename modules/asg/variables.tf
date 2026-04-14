variable "subnet_ids" { type = list(string) }
variable "security_group_id" {}
variable "target_group_arn" {}
variable "ami_id" {
  default = null
}
variable "key_name" {
  default = "vockey"
}

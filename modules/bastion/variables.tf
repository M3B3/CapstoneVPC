variable "ami_id" {
  default = null
}

variable "vpc_id" {}

variable "public_subnet_ids" { type = list(string) }

variable "key_name" {
  default = "vockey"
}

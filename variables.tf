variable "region" {
  default = "us-east-1"
}

variable "azs" {
  type = list(string)
  default = [
    "us-east-1a",
    "us-east-1b"
  ]
}

variable "public_subnets" {
  type = list(string)
  default = [
    "192.168.0.0/28",   # AZ1 public
    "192.168.0.16/28"   # AZ2 public
  ]
}

variable "private_subnets" {
  type = list(string)
  default = [
    "192.168.0.32/28",  # AZ1 private
    "192.168.0.48/28"   # AZ2 private
  ]
}


variable "db_name" {
  default = "appdb"
}

variable "db_user" {
  default = "admin"
}

variable "db_password" {
  description = "⚠️ Change in production"
  default     = "ChangeMe123!"
}


resource "aws_vpc" "this" {
  cidr_block = var.cidr_block
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
}

output "vpc_id" {
  value = aws_vpc.this.id
}

output "igw_id" {
  value = aws_internet_gateway.igw.id
}

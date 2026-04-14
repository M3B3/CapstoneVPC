resource "aws_vpc" "capstone_vpc" {
  cidr_block = var.cidr_block

  tags = {
    Name = "capstone_vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.capstone_vpc.id
}

output "vpc_id" {
  value = aws_vpc.capstone_vpc.id
}

output "igw_id" {
  value = aws_internet_gateway.igw.id
}

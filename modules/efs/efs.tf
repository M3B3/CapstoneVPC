resource "aws_efs_file_system" "wordpress" {
  encrypted = true

  tags = {
    Name = "wordpress-efs"
  }
}

resource "aws_efs_mount_target" "this" {
  count           = length(var.subnet_ids)
  file_system_id  = aws_efs_file_system.wordpress.id
  subnet_id       = var.subnet_ids[count.index]
  security_groups = [var.efs_sg_id]
}

output "efs_dns_name" {
  value = aws_efs_file_system.wordpress.dns_name
}

#!/bin/bash
yum update -y

# Install Apache, PHP, MySQL client
yum install -y httpd php php-mysqli wget amazon-efs-utils

systemctl start httpd
systemctl enable httpd

cd /var/www/html

# Download WordPress
wget https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz
cp -r wordpress/* .
rm -rf wordpress latest.tar.gz

# Create mount point
mkdir -p /var/www/html/wp-content/uploads

# Mount EFS
mount -t efs -o tls ${efs_dns_name}:/ /var/www/html/wp-content/uploads

# Persist across reboots
echo "${efs_dns_name}:/ /var/www/html/wp-content/uploads efs _netdev,tls 0 0" >> /etc/fstab

# Fix permissions
chown -R apache:apache /var/www/html/wp-content/uploads

# Permissions
chown -R apache:apache /var/www/html
chmod -R 755 /var/www/html

# Configure WordPress
cp wp-config-sample.php wp-config.php

sed -i "s/database_name_here/${db_name}/" wp-config.php
sed -i "s/username_here/${db_user}/" wp-config.php
sed -i "s/password_here/${db_password}/" wp-config.php
sed -i "s/localhost/${db_endpoint}/" wp-config.php

# Restart Apache
systemctl restart httpd
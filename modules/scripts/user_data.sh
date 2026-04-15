#!/bin/bash
yum update -y

# Install Apache, PHP, MySQL client
yum install -y httpd php php-mysqli wget

systemctl start httpd
systemctl enable httpd

cd /var/www/html

# Download WordPress
wget https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz
cp -r wordpress/* .
rm -rf wordpress latest.tar.gz

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
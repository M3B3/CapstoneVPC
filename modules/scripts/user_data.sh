#!/bin/bash
yum update -y

# Install Apache, PHP, MySQL client
yum install -y httpd php php-mysqli mariadb105 wget amazon-efs-utils

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

# Enable mod_rewrite for WordPress permalinks and REST API
sed -i 's/AllowOverride None/AllowOverride All/g' /etc/httpd/conf/httpd.conf

# Create WordPress .htaccess
cat > /var/www/html/.htaccess << 'HTACCESS_EOF'
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %%{REQUEST_FILENAME} !-f
RewriteCond %%{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress
HTACCESS_EOF

# Configure WordPress
cp wp-config-sample.php wp-config.php

sed -i "s/database_name_here/${db_name}/" wp-config.php
sed -i "s/username_here/${db_user}/" wp-config.php
sed -i "s/password_here/${db_password}/" wp-config.php
sed -i "s/localhost/${db_endpoint}/" wp-config.php


# Install CRUD App plugin
mkdir -p /var/www/html/wp-content/plugins/crud-app
cat > /var/www/html/wp-content/plugins/crud-app/crud-app.php << 'PLUGIN_EOF'
<?php
/**
 * Plugin Name: CRUD App
 * Description: Simple CRUD application for managing records
 * Version: 1.0.0
 */

if ( ! defined( 'ABSPATH' ) ) exit;

register_activation_hook( __FILE__, 'crud_app_create_table' );

function crud_app_create_table() {
    global $wpdb;
    $table   = $wpdb->prefix . 'crud_records';
    $charset = $wpdb->get_charset_collate();
    $sql     = "CREATE TABLE IF NOT EXISTS $table (
        id          INT          AUTO_INCREMENT PRIMARY KEY,
        title       VARCHAR(255) NOT NULL,
        description TEXT,
        status      VARCHAR(50)  NOT NULL DEFAULT 'active',
        created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) $charset;";
    require_once ABSPATH . 'wp-admin/includes/upgrade.php';
    dbDelta( $sql );
}

add_action( 'admin_menu', 'crud_app_admin_menu' );

function crud_app_admin_menu() {
    add_menu_page(
        'CRUD App', 'CRUD App', 'manage_options',
        'crud-app', 'crud_app_admin_page', 'dashicons-list-view'
    );
}

function crud_app_admin_page() {
    global $wpdb;
    $table = $wpdb->prefix . 'crud_records';

    if ( $_SERVER['REQUEST_METHOD'] === 'POST' && check_admin_referer( 'crud_app_action' ) ) {
        $action = sanitize_text_field( $_POST['crud_action'] ?? '' );
        if ( $action === 'create' || $action === 'update' ) {
            $data = [
                'title'       => sanitize_text_field( $_POST['title'] ),
                'description' => sanitize_textarea_field( $_POST['description'] ),
                'status'      => sanitize_text_field( $_POST['status'] ),
            ];
            if ( $action === 'create' ) {
                $wpdb->insert( $table, $data );
            } else {
                $wpdb->update( $table, $data, [ 'id' => intval( $_POST['record_id'] ) ] );
            }
        } elseif ( $action === 'delete' ) {
            $wpdb->delete( $table, [ 'id' => intval( $_POST['record_id'] ) ] );
        }
        wp_redirect( admin_url( 'admin.php?page=crud-app' ) );
        exit;
    }

    $edit = null;
    if ( isset( $_GET['edit'] ) ) {
        $edit = $wpdb->get_row( $wpdb->prepare( "SELECT * FROM $table WHERE id = %d", intval( $_GET['edit'] ) ) );
    }

    $records = $wpdb->get_results( "SELECT * FROM $table ORDER BY created_at DESC" );
    ?>
    <div class="wrap">
        <h1>CRUD App</h1>
        <h2><?php echo $edit ? 'Edit Record' : 'Add New Record'; ?></h2>
        <form method="post">
            <?php wp_nonce_field( 'crud_app_action' ); ?>
            <input type="hidden" name="crud_action" value="<?php echo $edit ? 'update' : 'create'; ?>">
            <?php if ( $edit ) : ?>
                <input type="hidden" name="record_id" value="<?php echo esc_attr( $edit->id ); ?>">
            <?php endif; ?>
            <table class="form-table">
                <tr>
                    <th><label for="title">Title</label></th>
                    <td><input id="title" type="text" name="title" class="regular-text"
                               value="<?php echo esc_attr( $edit->title ?? '' ); ?>" required></td>
                </tr>
                <tr>
                    <th><label for="description">Description</label></th>
                    <td><textarea id="description" name="description" rows="4" class="large-text"><?php
                        echo esc_textarea( $edit->description ?? '' );
                    ?></textarea></td>
                </tr>
                <tr>
                    <th><label for="status">Status</label></th>
                    <td>
                        <select id="status" name="status">
                            <option value="active"   <?php selected( $edit->status ?? 'active', 'active' ); ?>>Active</option>
                            <option value="inactive" <?php selected( $edit->status ?? '', 'inactive' ); ?>>Inactive</option>
                        </select>
                    </td>
                </tr>
            </table>
            <p>
                <button type="submit" class="button button-primary">
                    <?php echo $edit ? 'Update Record' : 'Add Record'; ?>
                </button>
                <?php if ( $edit ) : ?>
                    <a href="<?php echo admin_url( 'admin.php?page=crud-app' ); ?>" class="button">Cancel</a>
                <?php endif; ?>
            </p>
        </form>
        <h2>All Records</h2>
        <table class="widefat striped">
            <thead>
                <tr><th>ID</th><th>Title</th><th>Description</th><th>Status</th><th>Created</th><th>Actions</th></tr>
            </thead>
            <tbody>
            <?php if ( empty( $records ) ) : ?>
                <tr><td colspan="6">No records yet.</td></tr>
            <?php else : ?>
                <?php foreach ( $records as $r ) : ?>
                <tr>
                    <td><?php echo esc_html( $r->id ); ?></td>
                    <td><?php echo esc_html( $r->title ); ?></td>
                    <td><?php echo esc_html( $r->description ); ?></td>
                    <td><?php echo esc_html( $r->status ); ?></td>
                    <td><?php echo esc_html( $r->created_at ); ?></td>
                    <td>
                        <a href="<?php echo admin_url( 'admin.php?page=crud-app&edit=' . $r->id ); ?>"
                           class="button button-small">Edit</a>
                        <form method="post" style="display:inline"
                              onsubmit="return confirm('Delete this record?')">
                            <?php wp_nonce_field( 'crud_app_action' ); ?>
                            <input type="hidden" name="crud_action"  value="delete">
                            <input type="hidden" name="record_id"    value="<?php echo esc_attr( $r->id ); ?>">
                            <button type="submit" class="button button-small button-link-delete">Delete</button>
                        </form>
                    </td>
                </tr>
                <?php endforeach; ?>
            <?php endif; ?>
            </tbody>
        </table>
    </div>
    <?php
}

add_shortcode( 'crud_app', 'crud_app_shortcode' );

function crud_app_shortcode() {
    global $wpdb;
    $table = $wpdb->prefix . 'crud_records';

    if ( is_user_logged_in() && $_SERVER['REQUEST_METHOD'] === 'POST'
         && check_admin_referer( 'crud_app_frontend' ) ) {
        $action = sanitize_text_field( $_POST['crud_action'] ?? '' );
        if ( $action === 'create' ) {
            $wpdb->insert( $table, [
                'title'       => sanitize_text_field( $_POST['title'] ),
                'description' => sanitize_textarea_field( $_POST['description'] ),
            ] );
        } elseif ( $action === 'delete' ) {
            $wpdb->delete( $table, [ 'id' => intval( $_POST['record_id'] ) ] );
        }
        wp_redirect( get_permalink() );
        exit;
    }

    $records = $wpdb->get_results(
        "SELECT * FROM $table WHERE status = 'active' ORDER BY created_at DESC"
    );

    ob_start();
    echo '<div class="crud-app">';

    if ( is_user_logged_in() ) :
        ?>
        <h3>Add Record</h3>
        <form method="post">
            <?php wp_nonce_field( 'crud_app_frontend' ); ?>
            <input type="hidden" name="crud_action" value="create">
            <p><input type="text" name="title" placeholder="Title" required style="width:100%;padding:6px"></p>
            <p><textarea name="description" placeholder="Description" rows="3" style="width:100%;padding:6px"></textarea></p>
            <p><button type="submit">Add Record</button></p>
        </form>
        <?php
    endif;

    echo '<h3>Records</h3>';
    if ( empty( $records ) ) {
        echo '<p>No records yet.</p>';
    } else {
        echo '<ul style="list-style:none;padding:0">';
        foreach ( $records as $r ) {
            echo '<li style="padding:8px 0;border-bottom:1px solid #eee">';
            echo '<strong>' . esc_html( $r->title ) . '</strong>';
            if ( $r->description ) {
                echo ' &mdash; ' . esc_html( $r->description );
            }
            if ( is_user_logged_in() ) {
                echo ' <form method="post" style="display:inline">';
                wp_nonce_field( 'crud_app_frontend' );
                echo '<input type="hidden" name="crud_action" value="delete">';
                echo '<input type="hidden" name="record_id" value="' . esc_attr( $r->id ) . '">';
                echo '<button type="submit" onclick="return confirm(\'Delete?\')" '
                   . 'style="background:none;border:none;color:red;cursor:pointer">&#10005;</button>';
                echo '</form>';
            }
            echo '</li>';
        }
        echo '</ul>';
    }

    echo '</div>';
    return ob_get_clean();
}
PLUGIN_EOF

# Activate the plugin via WP-CLI (install WP-CLI first)
curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp

# Wait for WordPress DB to be reachable before activating
until wp --allow-root --path=/var/www/html db check --quiet 2>/dev/null; do sleep 5; done
wp --allow-root --path=/var/www/html plugin activate crud-app

chown -R apache:apache /var/www/html/wp-content/plugins

# Restart Apache
systemctl restart httpd
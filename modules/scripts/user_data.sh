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


# Install Vinyl Vault plugin
# Usage: add shortcode [vinyl_store] to any page to display the storefront
mkdir -p /var/www/html/wp-content/plugins/vinyl-vault
cat > /var/www/html/wp-content/plugins/vinyl-vault/vinyl-vault.php << 'PLUGIN_EOF'
<?php
/**
 * Plugin Name: Vinyl Vault
 * Description: Vinyl record store — browse, filter, and order records online
 * Version:     1.0.0
 */

if (!defined('ABSPATH')) exit;

register_activation_hook(__FILE__, 'vv_install');

function vv_install() {
    global $wpdb;
    $charset = $wpdb->get_charset_collate();
    require_once ABSPATH . 'wp-admin/includes/upgrade.php';

    $rt = $wpdb->prefix . 'vinyl_records';
    dbDelta("CREATE TABLE IF NOT EXISTS $rt (
  id INT NOT NULL AUTO_INCREMENT,
  title VARCHAR(255) NOT NULL,
  artist VARCHAR(255) NOT NULL,
  genre VARCHAR(100) NOT NULL DEFAULT 'Other',
  year_released SMALLINT NULL,
  price DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  condition_grade VARCHAR(50) NOT NULL DEFAULT 'Good',
  cover_image_url VARCHAR(500) NULL,
  stock INT NOT NULL DEFAULT 0,
  description TEXT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY  (id)
) $charset;");

    $ot = $wpdb->prefix . 'vinyl_orders';
    dbDelta("CREATE TABLE IF NOT EXISTS $ot (
  id INT NOT NULL AUTO_INCREMENT,
  customer_name VARCHAR(255) NOT NULL,
  customer_email VARCHAR(255) NOT NULL,
  customer_address TEXT NOT NULL,
  items_json TEXT NOT NULL,
  total DECIMAL(10,2) NOT NULL,
  status VARCHAR(50) NOT NULL DEFAULT 'pending',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY  (id)
) $charset;");

    if ((int)$wpdb->get_var("SELECT COUNT(*) FROM $rt") === 0) {
        $seed = [
            ["Dark Side of the Moon", "Pink Floyd",      "Rock",     1973, 29.99, "Excellent", 5, "One of the best-selling albums of all time."],
            ["Rumours",               "Fleetwood Mac",   "Rock",     1977, 24.99, "Good",      3, "Classic Fleetwood Mac record."],
            ["Kind of Blue",          "Miles Davis",     "Jazz",     1959, 34.99, "New",       4, "Landmark jazz album, miles ahead of its time."],
            ["Purple Rain",           "Prince",          "Pop/Rock", 1984, 27.99, "Good",      2, "Prince and The Revolution."],
            ["Blue",                  "Joni Mitchell",   "Folk",     1971, 22.99, "Good",      6, "Considered one of the greatest albums ever made."],
            ["Nevermind",             "Nirvana",         "Rock",     1991, 19.99, "Fair",      8, "Seminal grunge album from Seattle."],
            ["What's Going On",       "Marvin Gaye",     "Soul",     1971, 26.99, "Excellent", 3, "Marvin Gaye's soul masterpiece."],
            ["Led Zeppelin IV",       "Led Zeppelin",    "Rock",     1971, 28.99, "Good",      4, "Includes Stairway to Heaven."],
            ["Thriller",              "Michael Jackson", "Pop",      1982, 23.99, "Good",      7, "Best-selling album of all time."],
            ["A Love Supreme",        "John Coltrane",   "Jazz",     1965, 31.99, "Excellent", 2, "A seminal jazz recording."],
            ["Abbey Road",            "The Beatles",     "Rock",     1969, 32.99, "Excellent", 3, "The Beatles' final studio masterpiece."],
            ["Exile on Main St.",     "Rolling Stones",  "Rock",     1972, 25.99, "Good",      4, "Double album considered their finest work."],
        ];
        foreach ($seed as $s) {
            $wpdb->insert($rt, [
                'title' => $s[0], 'artist' => $s[1], 'genre' => $s[2],
                'year_released' => $s[3], 'price' => $s[4],
                'condition_grade' => $s[5], 'stock' => $s[6], 'description' => $s[7],
            ]);
        }
    }
}

function vv_get_cart() {
    if (empty($_COOKIE['vv_cart'])) return [];
    $data = json_decode(stripslashes($_COOKIE['vv_cart']), true);
    return is_array($data) ? $data : [];
}

function vv_save_cart($cart) {
    $val     = wp_json_encode($cart);
    $expires = empty($cart) ? time() - 3600 : time() + 86400;
    setcookie('vv_cart', $val, [
        'expires'  => $expires,
        'path'     => defined('COOKIEPATH') ? COOKIEPATH : '/',
        'domain'   => defined('COOKIE_DOMAIN') ? COOKIE_DOMAIN : '',
        'httponly' => true,
        'samesite' => 'Lax',
    ]);
    $_COOKIE['vv_cart'] = $val;
}

add_action('admin_menu', 'vv_admin_menu');
function vv_admin_menu() {
    add_menu_page('Vinyl Vault', 'Vinyl Vault', 'manage_options', 'vinyl-vault',        'vv_admin_records', 'dashicons-album');
    add_submenu_page('vinyl-vault', 'Records', 'Records', 'manage_options', 'vinyl-vault',        'vv_admin_records');
    add_submenu_page('vinyl-vault', 'Orders',  'Orders',  'manage_options', 'vinyl-vault-orders', 'vv_admin_orders');
}

function vv_admin_records() {
    global $wpdb;
    $rt = $wpdb->prefix . 'vinyl_records';
    $conditions = ['New', 'Mint', 'Excellent', 'Good', 'Fair', 'Poor'];

    if ($_SERVER['REQUEST_METHOD'] === 'POST' && check_admin_referer('vv_admin')) {
        $act  = sanitize_text_field($_POST['vv_action'] ?? '');
        $data = [
            'title'           => sanitize_text_field($_POST['title'] ?? ''),
            'artist'          => sanitize_text_field($_POST['artist'] ?? ''),
            'genre'           => sanitize_text_field($_POST['genre'] ?? ''),
            'year_released'   => intval($_POST['year_released'] ?? 0) ?: null,
            'price'           => round(floatval($_POST['price'] ?? 0), 2),
            'condition_grade' => sanitize_text_field($_POST['condition_grade'] ?? 'Good'),
            'cover_image_url' => esc_url_raw($_POST['cover_image_url'] ?? ''),
            'stock'           => max(0, intval($_POST['stock'] ?? 0)),
            'description'     => sanitize_textarea_field($_POST['description'] ?? ''),
        ];
        if ($act === 'create')     $wpdb->insert($rt, $data);
        elseif ($act === 'update') $wpdb->update($rt, $data, ['id' => intval($_POST['rid'])]);
        elseif ($act === 'delete') $wpdb->delete($rt, ['id' => intval($_POST['rid'])]);
        wp_redirect(admin_url('admin.php?page=vinyl-vault'));
        exit;
    }

    $edit    = isset($_GET['edit']) ? $wpdb->get_row($wpdb->prepare("SELECT * FROM $rt WHERE id=%d", intval($_GET['edit']))) : null;
    $records = $wpdb->get_results("SELECT * FROM $rt ORDER BY artist, title");
    ?>
    <div class="wrap">
        <h1>Vinyl Vault &mdash; Records</h1>
        <h2><?php echo $edit ? 'Edit Record' : 'Add Record'; ?></h2>
        <form method="post" style="max-width:660px">
            <?php wp_nonce_field('vv_admin'); ?>
            <input type="hidden" name="vv_action" value="<?php echo $edit ? 'update' : 'create'; ?>">
            <?php if ($edit): ?><input type="hidden" name="rid" value="<?php echo esc_attr($edit->id); ?>"><?php endif; ?>
            <table class="form-table">
                <tr><th>Title</th>          <td><input name="title"  class="regular-text" value="<?php echo esc_attr($edit->title ?? ''); ?>" required></td></tr>
                <tr><th>Artist</th>         <td><input name="artist" class="regular-text" value="<?php echo esc_attr($edit->artist ?? ''); ?>" required></td></tr>
                <tr><th>Genre</th>          <td><input name="genre"  class="regular-text" value="<?php echo esc_attr($edit->genre ?? ''); ?>"></td></tr>
                <tr><th>Year</th>           <td><input name="year_released" type="number" min="1900" max="2099" value="<?php echo esc_attr($edit->year_released ?? ''); ?>"></td></tr>
                <tr><th>Price ($)</th>      <td><input name="price" type="number" step="0.01" min="0" class="small-text" value="<?php echo esc_attr($edit->price ?? ''); ?>" required></td></tr>
                <tr><th>Condition</th><td>
                    <select name="condition_grade">
                        <?php foreach ($conditions as $c): ?>
                            <option value="<?php echo $c; ?>" <?php selected($edit->condition_grade ?? 'Good', $c); ?>><?php echo $c; ?></option>
                        <?php endforeach; ?>
                    </select>
                </td></tr>
                <tr><th>Cover Image URL</th><td><input name="cover_image_url" type="url" class="large-text" value="<?php echo esc_attr($edit->cover_image_url ?? ''); ?>"></td></tr>
                <tr><th>Stock</th>          <td><input name="stock" type="number" min="0" class="small-text" value="<?php echo esc_attr($edit->stock ?? 0); ?>" required></td></tr>
                <tr><th>Description</th>    <td><textarea name="description" rows="3" class="large-text"><?php echo esc_textarea($edit->description ?? ''); ?></textarea></td></tr>
            </table>
            <p>
                <button type="submit" class="button button-primary"><?php echo $edit ? 'Update' : 'Add Record'; ?></button>
                <?php if ($edit): ?><a href="<?php echo admin_url('admin.php?page=vinyl-vault'); ?>" class="button">Cancel</a><?php endif; ?>
            </p>
        </form>
        <hr>
        <h2>Inventory (<?php echo count($records); ?> records)</h2>
        <table class="widefat striped">
            <thead><tr><th>ID</th><th>Artist</th><th>Title</th><th>Genre</th><th>Year</th><th>Price</th><th>Condition</th><th>Stock</th><th>Actions</th></tr></thead>
            <tbody>
            <?php if (empty($records)): ?>
                <tr><td colspan="9">No records in inventory.</td></tr>
            <?php else: ?>
                <?php foreach ($records as $r): ?>
                <tr>
                    <td><?php echo esc_html($r->id); ?></td>
                    <td><?php echo esc_html($r->artist); ?></td>
                    <td><?php echo esc_html($r->title); ?></td>
                    <td><?php echo esc_html($r->genre); ?></td>
                    <td><?php echo esc_html($r->year_released); ?></td>
                    <td>$<?php echo number_format($r->price, 2); ?></td>
                    <td><?php echo esc_html($r->condition_grade); ?></td>
                    <td><?php echo esc_html($r->stock); ?></td>
                    <td>
                        <a href="<?php echo admin_url('admin.php?page=vinyl-vault&edit='.$r->id); ?>" class="button button-small">Edit</a>
                        <form method="post" style="display:inline" onsubmit="return confirm('Delete this record?')">
                            <?php wp_nonce_field('vv_admin'); ?>
                            <input type="hidden" name="vv_action" value="delete">
                            <input type="hidden" name="rid" value="<?php echo esc_attr($r->id); ?>">
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

function vv_admin_orders() {
    global $wpdb;
    $ot = $wpdb->prefix . 'vinyl_orders';
    $statuses = ['pending', 'processing', 'shipped', 'completed', 'cancelled'];

    if ($_SERVER['REQUEST_METHOD'] === 'POST' && check_admin_referer('vv_orders')) {
        $wpdb->update($ot,
            ['status' => sanitize_text_field($_POST['status'])],
            ['id'     => intval($_POST['oid'])]
        );
        wp_redirect(admin_url('admin.php?page=vinyl-vault-orders'));
        exit;
    }

    $orders = $wpdb->get_results("SELECT * FROM $ot ORDER BY created_at DESC");
    ?>
    <div class="wrap">
        <h1>Vinyl Vault &mdash; Orders</h1>
        <?php if (empty($orders)): ?>
            <p>No orders yet.</p>
        <?php else: ?>
        <table class="widefat striped">
            <thead><tr><th>ID</th><th>Customer</th><th>Email</th><th>Items</th><th>Total</th><th>Status</th><th>Date</th><th>Update</th></tr></thead>
            <tbody>
            <?php foreach ($orders as $o):
                $items   = json_decode($o->items_json, true) ?: [];
                $summary = implode(', ', array_map(function($i) {
                    return $i['artist'].' - '.$i['title'].' x'.$i['qty'];
                }, $items));
            ?>
            <tr>
                <td><?php echo esc_html($o->id); ?></td>
                <td><?php echo esc_html($o->customer_name); ?></td>
                <td><?php echo esc_html($o->customer_email); ?></td>
                <td style="max-width:240px;white-space:normal;font-size:.85em"><?php echo esc_html($summary); ?></td>
                <td>$<?php echo number_format($o->total, 2); ?></td>
                <td><?php echo esc_html($o->status); ?></td>
                <td><?php echo esc_html($o->created_at); ?></td>
                <td>
                    <form method="post" style="display:flex;gap:4px">
                        <?php wp_nonce_field('vv_orders'); ?>
                        <input type="hidden" name="oid" value="<?php echo esc_attr($o->id); ?>">
                        <select name="status">
                            <?php foreach ($statuses as $s): ?>
                                <option value="<?php echo $s; ?>" <?php selected($o->status, $s); ?>><?php echo ucfirst($s); ?></option>
                            <?php endforeach; ?>
                        </select>
                        <button type="submit" class="button button-small">Save</button>
                    </form>
                </td>
            </tr>
            <?php endforeach; ?>
            </tbody>
        </table>
        <?php endif; ?>
    </div>
    <?php
}

add_shortcode('vinyl_store', 'vv_store');

function vv_store() {
    global $wpdb;
    $rt = $wpdb->prefix . 'vinyl_records';
    $ot = $wpdb->prefix . 'vinyl_orders';

    if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['vv_nonce'])) {
        if (!wp_verify_nonce($_POST['vv_nonce'], 'vv_store_action'))
            return '<p>Security error.</p>';

        $act = sanitize_text_field($_POST['vv_act'] ?? '');

        if ($act === 'add') {
            $cart = vv_get_cart();
            $id   = intval($_POST['rid']);
            if ($id > 0) $cart[$id] = ($cart[$id] ?? 0) + 1;
            vv_save_cart($cart);

        } elseif ($act === 'remove') {
            $cart = vv_get_cart();
            unset($cart[intval($_POST['rid'])]);
            vv_save_cart($cart);

        } elseif ($act === 'qty') {
            $cart = vv_get_cart();
            $id   = intval($_POST['rid']);
            $qty  = intval($_POST['qty']);
            if ($qty > 0) $cart[$id] = $qty; else unset($cart[$id]);
            vv_save_cart($cart);

        } elseif ($act === 'order') {
            $cart = vv_get_cart();
            if (!empty($cart)) {
                $items = []; $total = 0.0;
                foreach ($cart as $id => $qty) {
                    $rec = $wpdb->get_row($wpdb->prepare(
                        "SELECT * FROM $rt WHERE id=%d AND stock>=%d", $id, $qty
                    ));
                    if ($rec) {
                        $items[] = [
                            'id'     => $id,
                            'title'  => $rec->title,
                            'artist' => $rec->artist,
                            'qty'    => $qty,
                            'price'  => (float)$rec->price,
                        ];
                        $total += (float)$rec->price * $qty;
                        $wpdb->query($wpdb->prepare(
                            "UPDATE $rt SET stock=stock-%d WHERE id=%d", $qty, $id
                        ));
                    }
                }
                if (!empty($items)) {
                    $wpdb->insert($ot, [
                        'customer_name'    => sanitize_text_field($_POST['cname']),
                        'customer_email'   => sanitize_email($_POST['cemail']),
                        'customer_address' => sanitize_textarea_field($_POST['caddress']),
                        'items_json'       => wp_json_encode($items),
                        'total'            => $total,
                        'status'           => 'pending',
                    ]);
                    vv_save_cart([]);
                    setcookie('vv_flash', (string)$total, [
                        'expires'  => time() + 120,
                        'path'     => defined('COOKIEPATH') ? COOKIEPATH : '/',
                        'httponly' => true,
                        'samesite' => 'Lax',
                    ]);
                }
            }
            wp_redirect(get_permalink());
            exit;
        }
        wp_redirect(get_permalink());
        exit;
    }

    $cart   = vv_get_cart();
    $genre  = sanitize_text_field($_GET['genre']  ?? '');
    $search = sanitize_text_field($_GET['search'] ?? '');

    $wheres = ['stock > 0']; $params = [];
    if ($genre)  { $wheres[] = 'genre = %s'; $params[] = $genre; }
    if ($search) {
        $wheres[] = '(title LIKE %s OR artist LIKE %s)';
        $like = '%' . $wpdb->esc_like($search) . '%';
        $params[] = $like; $params[] = $like;
    }
    $sql     = 'SELECT * FROM ' . $rt . ' WHERE ' . implode(' AND ', $wheres) . ' ORDER BY artist, title';
    $records = empty($params) ? $wpdb->get_results($sql) : $wpdb->get_results($wpdb->prepare($sql, ...$params));
    $genres  = $wpdb->get_col("SELECT DISTINCT genre FROM $rt WHERE stock>0 ORDER BY genre");
    $url     = get_permalink();

    ob_start(); ?>
<style>
.vv{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;max-width:1100px;margin:0 auto;color:#222}
.vv-head{background:#1a1a2e;color:#fff;padding:40px 24px;text-align:center;border-radius:8px;margin-bottom:28px}
.vv-head h2{margin:0 0 6px;font-size:2.2em;letter-spacing:3px;font-weight:800}
.vv-head p{margin:0;opacity:.75;font-size:1.05em}
.vv-alert{background:#d1e7dd;color:#0a3622;border:1px solid #a3cfbb;border-radius:6px;padding:14px 18px;margin-bottom:20px}
.vv-cart-box{background:#fff;border:1px solid #dde;border-radius:8px;padding:22px;margin-bottom:28px;box-shadow:0 2px 8px rgba(0,0,0,.06)}
.vv-cart-box h3{margin:0 0 16px;font-size:1.15em;border-bottom:2px solid #1a1a2e;padding-bottom:8px}
.vv-ci{display:flex;gap:12px;align-items:center;padding:10px 0;border-bottom:1px solid #f0f0f0}
.vv-ci:last-child{border:none}
.vv-ci-info{flex:1;font-size:.95em}
.vv-ci-info strong{display:block}
.vv-total{text-align:right;font-weight:700;font-size:1.15em;margin-top:12px}
.vv-checkout{background:#f7f7f9;border-radius:6px;padding:20px;margin-top:16px}
.vv-checkout h4{margin:0 0 14px;font-size:1em}
.vv-checkout label{display:block;font-weight:600;margin:10px 0 4px;font-size:.9em}
.vv-checkout input,.vv-checkout textarea{width:100%;padding:8px 10px;border:1px solid #ccc;border-radius:4px;box-sizing:border-box;font-size:.95em}
.vv-checkout textarea{height:72px;resize:vertical}
.vv-filters{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin-bottom:22px}
.vv-tag{padding:6px 16px;background:#f0f0f0;border:1px solid #ddd;border-radius:20px;text-decoration:none;color:#333;font-size:.88em;transition:all .15s}
.vv-tag:hover,.vv-tag.on{background:#1a1a2e;color:#fff;border-color:#1a1a2e}
.vv-tag-form{display:flex;gap:6px}
.vv-tag-form input{padding:6px 12px;border:1px solid #ccc;border-radius:20px;font-size:.88em}
.vv-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(210px,1fr));gap:20px;margin-bottom:40px}
.vv-card{border:1px solid #e0e0e8;border-radius:8px;overflow:hidden;background:#fff;transition:transform .2s,box-shadow .2s}
.vv-card:hover{transform:translateY(-3px);box-shadow:0 8px 24px rgba(0,0,0,.1)}
.vv-img{width:100%;height:195px;object-fit:cover;display:block}
.vv-img-ph{width:100%;height:195px;background:linear-gradient(135deg,#1a1a2e 0%,#2d2d5e 100%);display:flex;align-items:center;justify-content:center;color:rgba(255,255,255,.15);font-size:5em}
.vv-body{padding:14px}
.vv-body-title{font-weight:700;font-size:.95em;margin:0 0 2px;line-height:1.3}
.vv-body-artist{color:#666;font-size:.88em;margin:0 0 8px}
.vv-tags{display:flex;flex-wrap:wrap;gap:5px;margin-bottom:8px}
.vv-pill{font-size:.72em;padding:2px 8px;border-radius:10px;background:#f0f0f0;color:#555}
.vv-pill-genre{background:#e8f0fe;color:#1a56db}
.vv-desc{font-size:.8em;color:#666;margin:0 0 8px;line-height:1.4}
.vv-price{font-size:1.18em;font-weight:800;color:#1a1a2e;margin-bottom:2px}
.vv-stock{font-size:.78em;color:#888;margin-bottom:8px}
.vv-btn{display:block;width:100%;padding:9px;background:#1a1a2e;color:#fff;border:none;border-radius:4px;cursor:pointer;font-size:.9em;font-weight:600;transition:background .2s}
.vv-btn:hover{background:#2d2d5e}
.vv-btn:disabled{background:#bbb;cursor:not-allowed}
.vv-btn-order{background:#c0392b}
.vv-btn-order:hover{background:#96281b}
.vv-empty{text-align:center;padding:60px;color:#aaa}
.vv-empty-icon{font-size:4em;margin-bottom:12px}
</style>
<div class="vv">
    <div class="vv-head">
        <h2>&#9679;&#9679; VINYL VAULT &#9679;&#9679;</h2>
        <p>Rare &amp; Classic Records &mdash; Curated for True Music Lovers</p>
    </div>

    <?php if (!empty($_COOKIE['vv_flash'])):
        $flash_total = (float)$_COOKIE['vv_flash'];
        setcookie('vv_flash', '', ['expires' => time() - 3600, 'path' => defined('COOKIEPATH') ? COOKIEPATH : '/']);
        unset($_COOKIE['vv_flash']); ?>
    <div class="vv-alert">
        <strong>Order placed!</strong> Thank you &mdash; your total was $<?php echo number_format($flash_total, 2); ?>. We will be in touch soon.
    </div>
    <?php endif; ?>

    <?php
    $cart_rows = []; $grand = 0.0;
    foreach ($cart as $id => $qty) {
        $rec = $wpdb->get_row($wpdb->prepare("SELECT * FROM $rt WHERE id=%d", $id));
        if ($rec) { $cart_rows[] = [$rec, $qty]; $grand += (float)$rec->price * $qty; }
    }
    if (!empty($cart_rows)): ?>
    <div class="vv-cart-box">
        <h3>Your Cart &mdash; <?php echo array_sum($cart); ?> item<?php echo array_sum($cart) != 1 ? 's' : ''; ?></h3>
        <?php foreach ($cart_rows as $ci): $rec = $ci[0]; $qty = $ci[1]; ?>
        <div class="vv-ci">
            <div class="vv-ci-info">
                <strong><?php echo esc_html($rec->title); ?></strong>
                <?php echo esc_html($rec->artist); ?>
            </div>
            <form method="post" style="display:flex;gap:5px;align-items:center">
                <?php wp_nonce_field('vv_store_action', 'vv_nonce'); ?>
                <input type="hidden" name="vv_act" value="qty">
                <input type="hidden" name="rid"    value="<?php echo esc_attr($rec->id); ?>">
                <input type="number"  name="qty"    value="<?php echo esc_attr($qty); ?>" min="0" max="<?php echo esc_attr($rec->stock + $qty); ?>" style="width:55px;padding:4px 6px;border:1px solid #ccc;border-radius:3px">
                <button type="submit" class="button button-small">Update</button>
            </form>
            <div style="font-weight:700;min-width:64px;text-align:right">$<?php echo number_format((float)$rec->price * $qty, 2); ?></div>
            <form method="post">
                <?php wp_nonce_field('vv_store_action', 'vv_nonce'); ?>
                <input type="hidden" name="vv_act" value="remove">
                <input type="hidden" name="rid"    value="<?php echo esc_attr($rec->id); ?>">
                <button type="submit" style="background:none;border:none;color:#c0392b;cursor:pointer;font-size:1.1em;padding:0 4px" title="Remove">&#10005;</button>
            </form>
        </div>
        <?php endforeach; ?>
        <div class="vv-total">Total: $<?php echo number_format($grand, 2); ?></div>
        <div class="vv-checkout">
            <h4>Shipping Details</h4>
            <form method="post">
                <?php wp_nonce_field('vv_store_action', 'vv_nonce'); ?>
                <input type="hidden" name="vv_act" value="order">
                <label>Full Name</label>
                <input name="cname"    required placeholder="Your full name">
                <label>Email Address</label>
                <input name="cemail"   type="email" required placeholder="your@email.com">
                <label>Shipping Address</label>
                <textarea name="caddress" required placeholder="Street, City, State, ZIP"></textarea>
                <button type="submit" class="vv-btn vv-btn-order" style="margin-top:14px">Place Order &mdash; $<?php echo number_format($grand, 2); ?></button>
            </form>
        </div>
    </div>
    <?php endif; ?>

    <div class="vv-filters">
        <a href="<?php echo esc_url($url); ?>" class="vv-tag <?php echo !$genre && !$search ? 'on' : ''; ?>">All</a>
        <?php foreach ($genres as $g): ?>
        <a href="<?php echo esc_url(add_query_arg('genre', urlencode($g), $url)); ?>" class="vv-tag <?php echo $genre === $g ? 'on' : ''; ?>"><?php echo esc_html($g); ?></a>
        <?php endforeach; ?>
        <form class="vv-tag-form" method="get" action="<?php echo esc_url($url); ?>">
            <input name="search" placeholder="Search artist or title..." value="<?php echo esc_attr($search); ?>">
            <button type="submit" class="vv-tag" style="border:none;cursor:pointer">Search</button>
            <?php if ($search): ?><a href="<?php echo esc_url($url); ?>" class="vv-tag">Clear</a><?php endif; ?>
        </form>
    </div>

    <?php if (empty($records)): ?>
    <div class="vv-empty">
        <div class="vv-empty-icon">&#9679;</div>
        <p>No records found<?php echo $genre || $search ? ' matching your search' : ''; ?>.</p>
    </div>
    <?php else: ?>
    <div class="vv-grid">
    <?php foreach ($records as $r): ?>
        <div class="vv-card">
            <?php if ($r->cover_image_url): ?>
                <img src="<?php echo esc_url($r->cover_image_url); ?>" alt="<?php echo esc_attr($r->title); ?>" class="vv-img">
            <?php else: ?>
                <div class="vv-img-ph">&#9679;</div>
            <?php endif; ?>
            <div class="vv-body">
                <div class="vv-body-title"><?php echo esc_html($r->title); ?></div>
                <div class="vv-body-artist"><?php echo esc_html($r->artist); ?></div>
                <div class="vv-tags">
                    <?php if ($r->genre): ?><span class="vv-pill vv-pill-genre"><?php echo esc_html($r->genre); ?></span><?php endif; ?>
                    <?php if ($r->year_released): ?><span class="vv-pill"><?php echo esc_html($r->year_released); ?></span><?php endif; ?>
                    <span class="vv-pill"><?php echo esc_html($r->condition_grade); ?></span>
                </div>
                <?php if ($r->description): ?>
                <p class="vv-desc"><?php echo esc_html(wp_trim_words($r->description, 14)); ?></p>
                <?php endif; ?>
                <div class="vv-price">$<?php echo number_format((float)$r->price, 2); ?></div>
                <div class="vv-stock"><?php echo esc_html($r->stock); ?> in stock</div>
                <?php if ($r->stock > 0): ?>
                <form method="post">
                    <?php wp_nonce_field('vv_store_action', 'vv_nonce'); ?>
                    <input type="hidden" name="vv_act" value="add">
                    <input type="hidden" name="rid"    value="<?php echo esc_attr($r->id); ?>">
                    <button type="submit" class="vv-btn">Add to Cart</button>
                </form>
                <?php else: ?>
                    <button class="vv-btn" disabled>Out of Stock</button>
                <?php endif; ?>
            </div>
        </div>
    <?php endforeach; ?>
    </div>
    <?php endif; ?>
</div>
<?php
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

# Install WP-CLI
curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp

# Wait for DB to be reachable, then activate plugin if WordPress is already installed
until wp --allow-root --path=/var/www/html db check --quiet 2>/dev/null; do sleep 5; done
wp --allow-root --path=/var/www/html core is-installed 2>/dev/null && \
    wp --allow-root --path=/var/www/html plugin activate vinyl-vault 2>/dev/null || true

chown -R apache:apache /var/www/html/wp-content/plugins

# Restart Apache
systemctl restart httpd

# CapstoneVPC — Vinyl Vault on AWS

Terraform-managed, multi-tier AWS deployment of a WordPress site running a custom **Vinyl Vault** storefront plugin (record browsing, cart, checkout, admin inventory). The infrastructure is fully modular and demonstrates a production-style web architecture: ALB → Auto Scaling web tier → Multi-AZ RDS, with EFS for shared media and a bastion for operator SSH access.

---

## Architecture

```
                  Internet
                     │
                  ┌──▼───┐
                  │ IGW  │
                  └──┬───┘
                     │
            ┌────────▼─────────┐
            │   ALB (public)   │  Listener :80 → target group
            └──┬────────────┬──┘    health check: /wp-admin/install.php
               │            │
        ┌──────▼───┐  ┌─────▼────┐
        │ EC2 (AZ1)│  │ EC2 (AZ2)│  Auto Scaling Group  (min 2, max 5)
        │ WordPress│  │ WordPress│  Target tracking @ 50% CPU
        └────┬─────┘  └────┬─────┘
             │ NFS         │ NFS
        ┌────▼─────────────▼────┐
        │   EFS (uploads only)  │  /var/www/html/wp-content/uploads
        └───────────────────────┘
             │
        ┌────▼──────────────────┐
        │  RDS MySQL (Multi-AZ) │  private subnets
        └───────────────────────┘

           ┌──────────────┐
           │   Bastion    │  public subnet, SSH from operator
           └──────────────┘
```

| Tier | What runs | Subnets |
|---|---|---|
| Edge | ALB | Public (AZ1, AZ2) |
| Web  | ASG of EC2 (Apache + PHP + WordPress + Vinyl Vault plugin) | Public (AZ1, AZ2) |
| Data | RDS MySQL (Multi-AZ) | Private (AZ1, AZ2) |
| Shared FS | EFS mount targets (uploads) | Public (reachable from web tier SG) |
| Operator | Bastion EC2 | Public (AZ1) |

Security groups follow least-privilege chaining: **ALB → Web → DB**, **Web → EFS**, **Bastion → Web (SSH)**.

---

## Prerequisites

- Terraform ≥ 1.6
- AWS credentials in the environment with permission to provision VPC / EC2 / RDS / EFS / ALB / IAM
- An HCP Terraform Cloud workspace (this repo is wired to `M3B3_org / CapstoneVPC` — change in `main.tf` if you fork)
- `aws` CLI (for testing and instance refreshes)

The SSH keypair is **generated on-the-fly** inside Terraform (`tls_private_key`) and written to `capstone.pem` next to the root module. No external `.pub` file is required.

---

## Deploy

```bash
terraform init     # downloads aws, null, tls, local providers
terraform plan
terraform apply
```

When the apply finishes:

- `terraform output -raw wordpress_url` → the ALB URL
- `capstone.pem` (mode 0400) is written into the repo directory; it's also copied to the bastion at `/home/ec2-user/capstone.pem` via a `null_resource` provisioner

WordPress installs itself via user_data on first boot of each ASG instance:
- Apache + PHP + MySQL client + EFS utils
- WordPress core download + `wp-config.php` populated with the RDS endpoint
- EFS mounted at `wp-content/uploads`
- Vinyl Vault plugin written, activated, and seeded with sample records
- Default Sample Page deleted; Twenty Twenty-Five header nav and footer credit suppressed via plugin CSS
- The Vinyl Vault store page is set as the front page

The first boot can take 3–5 minutes per instance — the ALB target group will only show `healthy` once `/wp-admin/install.php` is reachable.

---

## Test the load balancer

```bash
ALB=$(terraform output -raw wordpress_url)

# ALB health
curl -I "$ALB"

# Round-robin proof — hits a /whoami.php endpoint planted by user_data
for i in {1..10}; do curl -s "$ALB/whoami.php"; done
```

You'll see different `ip-192-168-…` hostnames as requests rotate across instances. The storefront page also shows a small *"Served by: \<hostname\>"* footer for visual confirmation.

## Test the auto-scaler

The ASG has a target-tracking policy at **50% average CPU**, with `min=2, desired=2, max=5`.

**Self-healing** — terminate one instance, watch the ASG replace it:
```bash
aws autoscaling describe-auto-scaling-groups \
  --query 'AutoScalingGroups[0].Instances[].[InstanceId,LifecycleState]' --output table
aws ec2 terminate-instances --instance-ids <one-id>
```

**Scale-out under load** — drive the ALB:
```bash
ab -n 50000 -c 200 "$ALB/"
# or: hey -z 5m -c 200 "$ALB/"
```
…or SSH to a web instance via the bastion and `stress-ng --cpu 2 --timeout 600s`.

**Where to watch / screenshot:**
- EC2 Console → Auto Scaling Groups → *capstone* → **Monitoring** tab (CPU + DesiredCapacity in one view)
- **Activity** tab for a timestamped audit log of scaling events
- CloudWatch → Alarms — the auto-created `TargetTracking-…AlarmHigh/Low`

---

## Notable variables

Defined in `variables.tf` — override via `*.tfvars`, env vars (`TF_VAR_*`), or HCP Cloud workspace variables.

| Variable | Default | Note |
|---|---|---|
| `region` | `us-east-1` | |
| `db_name` / `db_user` / `db_password` | `appdb` / `admin` / `ChangeMe123!` | **Override `db_password` for any non-throwaway deployment** |
| `wp_admin_user` / `wp_admin_email` | `admin` / `admin@example.com` | |
| `wp_admin_password` | (no default, sensitive) | Required — must be set before apply |
| `wp_site_title` | `Vinyl Vault` | |
| `key_name` | `capstone-key` | Name of the AWS key pair Terraform creates |

---

## Module layout

```
modules/
├── vpc/         VPC + Internet Gateway
├── subnets/     2 public + 2 private subnets across us-east-1a/b
├── routing/     Public route table → IGW
├── security/    All four SGs (ALB, Web, DB, EFS); chained least-privilege
├── bastion/     Operator EC2 + bastion SG
├── alb/         Application Load Balancer + target group + listener
├── rds/         Multi-AZ MySQL
├── efs/         Encrypted EFS + mount targets
├── asg/         Launch template + ASG + target-tracking CPU policy
└── scripts/
    └── user_data.sh   WordPress install + Vinyl Vault plugin + EFS mount
```

The root `main.tf` orchestrates them in dependency order. Module dependencies are detailed in `CLAUDE.md`.

---

## Cleanup

```bash
terraform destroy
```

EFS file systems and RDS instances are destroyed without final snapshots — adjust the modules if you want safer defaults.

---

## Security notes (for real-world use)

- Bastion SG allows SSH from `0.0.0.0/0` — restrict to your IP in `modules/bastion/bastion.tf`
- `db_password` is plaintext in `variables.tf` — move to a `*.tfvars` (gitignored) or AWS Secrets Manager
- The generated `capstone.pem` is sensitive; it lives in tfstate. `.gitignore` covers `*.pem`, but treat the state file with the same care you'd treat the key itself
- EFS mount targets are placed in public subnets for simplicity; in stricter designs they'd live in private subnets

# =============================================================================
# Input variables for the foundation config.
#
# Everything has a default, so a bare `terraform apply` works. Override via
# terraform.tfvars (see terraform.tfvars.example) or `-var` flags.
# =============================================================================

variable "aws_region" {
  description = "AWS region in which to create infrastructure."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = contains(["us-east-1", "us-west-2"], var.aws_region)
    error_message = "AWS Academy permits only us-east-1 and us-west-2."
  }
}

variable "project_name" {
  description = "Project identifier; used as a prefix on resource names and in tags."
  type        = string
  default     = "giftgauge"
}

# ---------- Networking -------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC. /16 gives us 65k addresses, which is overkill but standard."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "AZs to spread subnets across. Two is the EKS minimum and the cheapest configuration."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "EKS requires at least two AZs."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets, one per AZ. Hosts the ALB."
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private application subnets, one per AZ. Hosts EKS nodes."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "database_subnet_cidrs" {
  description = "CIDR blocks for database subnets, one per AZ. Hosts RDS. No NAT route — fully internal."
  type        = list(string)
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
}

# ---------- Container registry ----------------------------------------------

variable "ecr_services" {
  description = "Service names that get a dedicated ECR repository. One image per service."
  type        = list(string)
  default     = ["frontend", "profile", "sharing", "scoring"]
}

variable "ecr_untagged_image_retention_days" {
  description = "How long to keep untagged images before lifecycle policy deletes them."
  type        = number
  default     = 7
}

variable "ecr_max_tagged_images" {
  description = "Maximum number of tagged images to keep per repository. Older tagged images are deleted."
  type        = number
  default     = 30
}


// =============================================================================
// PATCH for terraform/variables.tf
//
// Append the block below to the END of your existing variables.tf.
// All other variables in the file stay as they are.
// =============================================================================

# ---------- Database ---------------------------------------------------------

variable "rds_engine_version" {
  description = "Postgres engine version. Pinned for reproducibility; bump deliberately when AWS releases a new minor."
  type        = string
  default     = "16.13"
}

variable "rds_instance_class" {
  description = "RDS instance class. db.t3.micro is the cheapest practical option (~$13/month if 24/7) and free-tier-eligible for new accounts."
  type        = string
  default     = "db.t3.micro"
}

variable "rds_allocated_storage" {
  description = "Initial storage in GB. 20 is the Postgres minimum on RDS."
  type        = number
  default     = 20

  validation {
    condition     = var.rds_allocated_storage >= 20
    error_message = "RDS Postgres requires at least 20 GB of allocated storage."
  }
}

variable "rds_max_allocated_storage" {
  description = "Storage autoscaling ceiling in GB. RDS will grow allocated_storage up to this value if disk fills, with no downtime."
  type        = number
  default     = 100
}

variable "rds_master_username" {
  description = "Master username for the RDS instance. Note RDS rejects 'admin' and treats 'postgres' as reserved-ish; pick something distinctive."
  type        = string
  default     = "giftgauge"

  validation {
    condition     = !contains(["admin", "rdsadmin", "postgres"], var.rds_master_username)
    error_message = "Master username cannot be one of: admin, rdsadmin, postgres."
  }
}

variable "rds_master_db_name" {
  description = "Initial database created at instance launch. Per-environment databases (giftgauge_dev etc.) are created by the Helm migration job at deploy time, not here."
  type        = string
  default     = "giftgauge"
}

# ---------- Bastion ----------------------------------------------------------

variable "lab_instance_profile_name" {
  description = "Pre-existing IAM instance profile to attach to the bastion. AWS Academy creates 'LabInstanceProfile' for student accounts; we reference it by name because we cannot create our own."
  type        = string
  default     = "LabInstanceProfile"
}

variable "bastion_instance_type" {
  description = "EC2 instance type for the bastion. t3.nano is the cheapest at ~$3.50/month and is more than enough to host an idle SSM agent."
  type        = string
  default     = "t3.nano"
}

variable "bastion_allowed_cidr" {
  description = "CIDR block allowed to SSH into the bastion. Almost always your single public IP as /32. Find with `curl -s https://api.ipify.org`."
  type        = string

  validation {
    condition     = can(cidrhost(var.bastion_allowed_cidr, 0))
    error_message = "bastion_allowed_cidr must be a valid CIDR block (e.g. \"203.0.113.42/32\")."
  }

  validation {
    condition     = var.bastion_allowed_cidr != "0.0.0.0/0"
    error_message = "Refusing to expose SSH to the entire internet. Use your real IP /32."
  }
}

variable "bastion_public_key_path" {
  description = "Path to the SSH public key file to install on the bastion. Generate with `ssh-keygen -t ed25519 -f ~/.ssh/giftgauge_bastion -N \"\"`."
  type        = string
  default     = "~/.ssh/giftgauge_bastion.pub"
}

# ---------- EKS --------------------------------------------------------------

variable "lab_eks_cluster_role_name" {
  description = "Override for the LabEksClusterRole's actual name. Leave empty (default) to auto-discover via iam:ListRoles. Set this to the literal role name (e.g. `c197...-LabEksClusterRole-xxxx`) if list-roles is denied in your lab."
  type        = string
  default     = ""
}

variable "lab_eks_node_role_name" {
  description = "Override for the LabEksNodeRole's actual name. Leave empty (default) to auto-discover via iam:ListRoles. Set this to the literal role name if list-roles is denied."
  type        = string
  default     = ""
}

variable "lab_user_role_name" {
  description = "Underlying role of the assumed-role session that runs `terraform apply`. Used as the principal_arn on the cluster-admin Access Entry. Default 'voclabs' is correct for AWS Academy Learner Lab."
  type        = string
  default     = "voclabs"
}

variable "eks_cluster_name" {
  description = "Name of the EKS cluster. Used in resource names; appears in kubeconfig as the context name."
  type        = string
  default     = "giftgauge-eks"
}

variable "eks_kubernetes_version" {
  description = "Kubernetes minor version. Pin a specific minor; bump deliberately when you've reviewed release notes."
  type        = string
  default     = "1.33"
}

variable "eks_node_instance_type" {
  description = "EC2 instance type for worker nodes. Lab supports nano/micro/small/medium/large only."
  type        = string
  default     = "t3.medium"
}

# ----- Primary node group sizing -----

variable "eks_primary_desired_size" {
  description = "Initial desired count for the primary node group."
  type        = number
  default     = 2
}

variable "eks_primary_min_size" {
  description = "Floor for the primary node group autoscaling."
  type        = number
  default     = 1
}

variable "eks_primary_max_size" {
  description = "Ceiling for the primary node group autoscaling."
  type        = number
  default     = 4
}

# ----- Secondary node group sizing -----

variable "eks_secondary_desired_size" {
  description = "Initial desired count for the secondary node group. Used as the drain target during Day-2 patching demos."
  type        = number
  default     = 1
}

variable "eks_secondary_min_size" {
  description = "Floor for the secondary node group autoscaling."
  type        = number
  default     = 1
}

variable "eks_secondary_max_size" {
  description = "Ceiling for the secondary node group autoscaling. Higher than the primary's max to absorb a primary drain."
  type        = number
  default     = 3
}


# ---------- Phase 5B observability -------------------------------------------

variable "public_domain" {
  description = "Apex domain used for public-facing services. The wildcard CNAME at *.<public_domain> on Cloudflare resolves to the NLB."
  type        = string
  default     = "justinpyne.xyz"
}

variable "alert_email_address" {
  description = "Email address for Let's Encrypt registration AND Alertmanager critical alerts. Same value for simplicity."
  type        = string
  default     = "jpyne.justin@gmail.com"
}

variable "github_oauth_client_id" {
  description = "GitHub OAuth App Client ID used to authenticate Grafana logins. Set in terraform.tfvars; never commit."
  type        = string
  sensitive   = true
}

variable "github_oauth_client_secret" {
  description = "GitHub OAuth App Client Secret. Set in terraform.tfvars; never commit."
  type        = string
  sensitive   = true
}

variable "gmail_app_password" {
  description = "Gmail App Password used by Alertmanager to send email via smtp.gmail.com:587. Generated at https://myaccount.google.com/apppasswords. Set in terraform.tfvars; never commit."
  type        = string
  sensitive   = true
}
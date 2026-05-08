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


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

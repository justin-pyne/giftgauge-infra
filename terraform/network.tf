# =============================================================================
# VPC and networking.
#
# Single use of the community VPC module. It produces:
#
#   - 1 VPC (10.0.0.0/16)
#   - 2 public subnets        — host the ALB
#   - 2 private subnets       — host EKS worker nodes
#   - 2 database subnets      — host RDS, no NAT route
#   - 1 Internet Gateway
#   - 1 NAT Gateway           — single AZ for cost; trade-off documented
#                               in docs/decisions.md
#   - Route tables wired correctly for all of the above
#   - 1 DB subnet group       — used by the RDS module in Phase 3
#
# We tag the public/private subnets with the Kubernetes role tags that EKS
# and the AWS Load Balancer Controller use for auto-discovery. Without these
# tags, public ALBs and internal ELBs created by Kubernetes Services
# (type=LoadBalancer) won't know which subnets to deploy into.
# =============================================================================

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${var.project_name}-vpc"
  cidr = var.vpc_cidr

  azs              = var.availability_zones
  public_subnets   = var.public_subnet_cidrs
  private_subnets  = var.private_subnet_cidrs
  database_subnets = var.database_subnet_cidrs

  # ----- Internet egress -----
  enable_nat_gateway     = true
  single_nat_gateway     = true   # cost trade-off; one NAT vs one-per-AZ
  one_nat_gateway_per_az = false

  # ----- DNS -----
  enable_dns_hostnames = true     # required by EKS
  enable_dns_support   = true

  # ----- RDS subnet group -----
  # Free side-effect of declaring database_subnets — saves us from creating
  # an aws_db_subnet_group resource by hand in Phase 3.
  create_database_subnet_group       = true
  create_database_subnet_route_table = true
  create_database_nat_gateway_route  = false   # RDS subnets stay fully internal

  # ----- EKS / ALB auto-discovery tags -----
  # The AWS Load Balancer Controller scans subnets by these tags to decide
  # where to provision ALBs / NLBs. Documented in the EKS user guide.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  # ----- Per-resource tags -----
  # default_tags from the provider already cover Project / ManagedBy /
  # Repository on every resource. Anything VPC-specific goes here.
  vpc_tags = {
    Component = "network"
  }

  tags = {
    Component = "network"
  }
}

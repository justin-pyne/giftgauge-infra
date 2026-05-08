# =============================================================================
# Outputs.
#
# These are consumed by:
#   - You, manually, when you need a quick lookup.
#   - Phase 3 (RDS) — vpc_id, database_subnet_group_name, security group inputs.
#   - Phase 4 (EKS) — vpc_id, private_subnet_ids, public_subnet_ids.
#   - Phase 7 (CI/CD) — ecr_repository_urls, so the build workflow knows
#     where to push.
# =============================================================================

# ---------- Network ----------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC."
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC."
  value       = module.vpc.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets, in AZ order."
  value       = module.vpc.public_subnets
}

output "private_subnet_ids" {
  description = "IDs of the private application subnets, in AZ order."
  value       = module.vpc.private_subnets
}

output "database_subnet_ids" {
  description = "IDs of the database subnets, in AZ order."
  value       = module.vpc.database_subnets
}

output "database_subnet_group_name" {
  description = "Name of the DB subnet group, ready for use by the RDS module in Phase 3."
  value       = module.vpc.database_subnet_group_name
}

output "nat_gateway_public_ip" {
  description = "Public IP of the (single) NAT gateway. Useful for whitelisting outbound traffic at third parties."
  value       = try(module.vpc.nat_public_ips[0], null)
}

# ---------- Container registry ----------------------------------------------

output "ecr_repository_urls" {
  description = "Map of service name to ECR repository URL. The image push target."
  value       = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}

output "ecr_repository_arns" {
  description = "Map of service name to ECR repository ARN."
  value       = { for k, v in aws_ecr_repository.this : k => v.arn }
}

# ---------- Account context --------------------------------------------------
# Convenience — saves an `aws sts get-caller-identity` round-trip for downstream
# configs that need to construct ARNs.

data "aws_caller_identity" "current" {}

output "aws_account_id" {
  description = "Account ID we are deployed into. Used by downstream configs to construct ARNs."
  value       = data.aws_caller_identity.current.account_id
}

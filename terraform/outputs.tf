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
// =============================================================================
// PATCH for terraform/outputs.tf
//
// Append the block below to the END of your existing outputs.tf.
// All other outputs in the file stay as they are.
//
// Notes on `sensitive`:
//   - rds_master_secret_arn is NOT sensitive — it's just an identifier.
//   - rds_endpoint and rds_port are NOT sensitive — knowing the host/port
//     of an RDS instance with no public access and a tight SG buys an
//     attacker nothing.
//   - We deliberately DO NOT expose the master password as a Terraform
//     output, even sensitive=true. Apps fetch it from Secrets Manager.
// =============================================================================

# ---------- Database ---------------------------------------------------------

output "rds_endpoint" {
  description = "DNS hostname of the RDS instance. Combine with rds_port to form a JDBC URL."
  value       = aws_db_instance.main.address
}

output "rds_port" {
  description = "Postgres port. Conventionally 5432."
  value       = aws_db_instance.main.port
}

output "rds_master_db_name" {
  description = "Initial database created on the instance. Per-env DBs are created from this one by the migration job."
  value       = aws_db_instance.main.db_name
}

output "rds_master_username" {
  description = "Master username. The Helm migration job uses these credentials to CREATE DATABASE for each env."
  value       = aws_db_instance.main.username
}

output "rds_security_group_id" {
  description = "ID of the RDS security group. Phase 4 will add an ingress rule to it from the EKS node SG."
  value       = aws_security_group.rds.id
}

output "rds_master_secret_arn" {
  description = "ARN of the Secrets Manager secret holding RDS master credentials. Read by External Secrets Operator in Phase 5/6."
  value       = aws_secretsmanager_secret.rds_master.arn
}

output "rds_master_secret_name" {
  description = "Name of the Secrets Manager secret. Convenient for `aws secretsmanager get-secret-value --secret-id ...`."
  value       = aws_secretsmanager_secret.rds_master.name
}

# ---------- Bastion ----------------------------------------------------------

output "bastion_instance_id" {
  description = "EC2 instance ID of the bastion."
  value       = aws_instance.bastion.id
}

output "bastion_public_ip" {
  description = "Public IP of the bastion. SSH target."
  value       = aws_instance.bastion.public_ip
}

output "bastion_security_group_id" {
  description = "ID of the bastion security group. Phase 4 adds this to the RDS ingress allowlist when the SG narrows from VPC CIDR."
  value       = aws_security_group.bastion.id
}

output "bastion_ssh_command" {
  description = "Copy-paste command to open an interactive SSH shell on the bastion."
  value       = "ssh -i ~/.ssh/giftgauge_bastion ec2-user@${aws_instance.bastion.public_ip}"
}

output "bastion_rds_tunnel_command" {
  description = "Copy-paste command that opens a local-port-forward tunnel from your laptop to RDS via the bastion. After running, in another terminal connect with `psql -h localhost -p 15432 -U <user> -d <db>` using master credentials from Secrets Manager."
  value       = "ssh -i ~/.ssh/giftgauge_bastion -N -L 15432:${aws_db_instance.main.address}:${aws_db_instance.main.port} ec2-user@${aws_instance.bastion.public_ip}"
}

# ---------- EKS --------------------------------------------------------------

output "eks_cluster_name" {
  description = "EKS cluster name. Used by `aws eks update-kubeconfig`."
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "EKS API server endpoint URL."
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_certificate_authority_data" {
  description = "Base64-encoded cluster CA. Used by Helm/Kubernetes Terraform providers in Phase 5."
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "eks_cluster_version" {
  description = "Kubernetes version actually running."
  value       = aws_eks_cluster.main.version
}

output "eks_cluster_security_group_id" {
  description = "Security group EKS auto-creates for the cluster. All managed-node-group nodes inherit it. Phase 4 references this from the RDS ingress rule."
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "kubeconfig_command" {
  description = "Copy-paste command to update your local kubeconfig."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}
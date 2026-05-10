# =============================================================================
# Amazon EKS — control plane, node groups, add-ons, and access entries.
#
# This file uses native aws_eks_* resources rather than the community module
# because the module unconditionally calls iam:GetRole, which the lab denies.
# Decision recorded in docs/decisions.md § O.
#
# Lab-specific quirks handled here:
#   1. Two pre-existing IAM roles, not one:
#        - LabEksClusterRole  (trust: eks.amazonaws.com) — for the cluster
#        - LabEksNodeRole     (trust: ec2.amazonaws.com) — for worker nodes
#      Their actual names have CloudFormation-generated prefixes/suffixes
#      that rotate per lab session, e.g.
#        c197651a5061...-LabEksClusterRole-xZIoJ9LfPDyR
#      So we DISCOVER them at apply time via iam:ListRoles + name_regex
#      rather than hardcoding. Variables `lab_eks_cluster_role_name` and
#      `lab_eks_node_role_name` provide a manual override if list-roles
#      itself is denied — the user pastes the exact name into terraform.tfvars
#      and discovery is skipped.
#
#   2. iam:GetRole is denied on the assumed-role's underlying role (`voclabs`).
#      We construct the operator role ARN as a literal string from
#      data.aws_caller_identity (which is always allowed) and use it as the
#      principal_arn on a manual cluster-admin Access Entry.
# =============================================================================

# -----------------------------------------------------------------------------
# Discover the two EKS-related lab roles by name pattern.
#
# `count = ... ? 1 : 0` lets the user bypass discovery by setting the
# corresponding variable in terraform.tfvars. If iam:ListRoles is denied in
# this lab variant, that's the fallback path.
# -----------------------------------------------------------------------------
data "aws_iam_roles" "lab_eks_cluster" {
  count      = var.lab_eks_cluster_role_name == "" ? 1 : 0
  name_regex = ".*LabEksClusterRole.*"
}

data "aws_iam_roles" "lab_eks_node" {
  count      = var.lab_eks_node_role_name == "" ? 1 : 0
  name_regex = ".*LabEksNodeRole.*"
}

# -----------------------------------------------------------------------------
# Resolved ARNs.
#
#  - When the variable is set, build the ARN literally (no IAM lookups).
#  - When the variable is empty, take the first match from the data source.
#
# `tolist()` is needed because `arns` is a set; sets aren't indexable.
# `[0]` errors clearly if the discovery returned zero matches — better than
# silently picking the wrong role.
# -----------------------------------------------------------------------------
locals {
  eks_cluster_role_arn = (
    var.lab_eks_cluster_role_name != ""
    ? "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.lab_eks_cluster_role_name}"
    : tolist(data.aws_iam_roles.lab_eks_cluster[0].arns)[0]
  )

  eks_node_role_arn = (
    var.lab_eks_node_role_name != ""
    ? "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.lab_eks_node_role_name}"
    : tolist(data.aws_iam_roles.lab_eks_node[0].arns)[0]
  )

  # Operator's underlying role (assumed-role session resolves to this role
  # for Access Entry matching). Constructed from caller identity — never
  # via iam:GetRole, which the lab denies.
  operator_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.lab_user_role_name}"
}

# -----------------------------------------------------------------------------
# CloudWatch log group for control-plane logs.
#
# EKS auto-creates one if absent, but creating it explicitly lets us set
# retention. (AWS default is "Never expire", which is bad for cost.)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.eks_cluster_name}/cluster"
  retention_in_days = 7

  tags = {
    Component = "compute"
  }
}

# -----------------------------------------------------------------------------
# The EKS cluster.
# -----------------------------------------------------------------------------
resource "aws_eks_cluster" "main" {
  name     = var.eks_cluster_name
  version  = var.eks_kubernetes_version
  role_arn = local.eks_cluster_role_arn

  vpc_config {
    subnet_ids              = module.vpc.private_subnets
    endpoint_public_access  = true
    endpoint_private_access = true
    public_access_cidrs     = ["0.0.0.0/0"]
  }

  access_config {
    authentication_mode = "API"
    # Skip the auto-bootstrap path — it triggers iam:GetRole. We grant admin
    # via the explicit Access Entry below.
    bootstrap_cluster_creator_admin_permissions = false
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  tags = {
    Component = "compute"
  }

  depends_on = [aws_cloudwatch_log_group.eks]
}

# -----------------------------------------------------------------------------
# Access Entry for the operator. EKS Access Entries match assumed-role
# sessions to entries created against the role they assumed, so granting
# `voclabs` cluster admin makes any session assumed from voclabs admin.
# -----------------------------------------------------------------------------
resource "aws_eks_access_entry" "operator" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = local.operator_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "operator_admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = local.operator_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.operator]
}

# -----------------------------------------------------------------------------
# Managed node groups.
# -----------------------------------------------------------------------------
resource "aws_eks_node_group" "primary" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.eks_cluster_name}-primary"
  node_role_arn   = local.eks_node_role_arn

  subnet_ids     = module.vpc.private_subnets
  ami_type       = "AL2023_x86_64_STANDARD"
  instance_types = [var.eks_node_instance_type]
  capacity_type  = "ON_DEMAND"
  disk_size      = 20

  scaling_config {
    desired_size = var.eks_primary_desired_size
    min_size     = var.eks_primary_min_size
    max_size     = var.eks_primary_max_size
  }

  update_config {
    max_unavailable_percentage = 33
  }

  labels = {
    nodegroup = "primary"
  }

  tags = {
    Component = "compute"
    NodeGroup = "primary"
  }

  depends_on = [
    aws_eks_access_policy_association.operator_admin,
  ]

  lifecycle {
    # Don't fight any out-of-band scaling changes from the autoscaler.
    ignore_changes = [scaling_config[0].desired_size]
  }
}

resource "aws_eks_node_group" "secondary" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.eks_cluster_name}-secondary"
  node_role_arn   = local.eks_node_role_arn

  subnet_ids     = module.vpc.private_subnets
  ami_type       = "AL2023_x86_64_STANDARD"
  instance_types = [var.eks_node_instance_type]
  capacity_type  = "ON_DEMAND"
  disk_size      = 20

  scaling_config {
    desired_size = var.eks_secondary_desired_size
    min_size     = var.eks_secondary_min_size
    max_size     = var.eks_secondary_max_size
  }

  update_config {
    max_unavailable_percentage = 33
  }

  labels = {
    nodegroup = "secondary"
  }

  tags = {
    Component = "compute"
    NodeGroup = "secondary"
  }

  depends_on = [
    aws_eks_access_policy_association.operator_admin,
  ]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# -----------------------------------------------------------------------------
# EKS managed add-ons. All four use the node IAM role (LabEksNodeRole) for
# AWS API perms, since IRSA is unavailable in this lab variant.
# -----------------------------------------------------------------------------
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Component = "compute"
  }
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Component = "compute"
  }
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # CoreDNS pods need somewhere to land.
  depends_on = [aws_eks_node_group.primary]

  tags = {
    Component = "compute"
  }
}

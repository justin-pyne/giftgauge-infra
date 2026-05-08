# =============================================================================
# Bastion host — SSM-accessed jump host for ad-hoc RDS connectivity.
#
# Architecture:
#
#   your laptop ──[aws ssm start-session]──▶ AWS SSM service
#                                                  │
#                                                  ▼ (back-channel)
#                                          ┌─ private subnet ─┐
#                                          │  bastion (EC2)   │
#                                          │  - no public IP  │
#                                          │  - no port 22    │
#                                          │  - LabInstance-  │
#                                          │    Profile with  │
#                                          │    SSM Core      │
#                                          └────────┬─────────┘
#                                                   │ port-forward 5432
#                                                   ▼
#                                          ┌─ database subnet ─┐
#                                          │  RDS Postgres     │
#                                          └───────────────────┘
#
# Cost: t3.nano is ~$3.50/month if 24/7. Tear down between work sessions.
# Run `aws ec2 stop-instances` to pause without losing the instance.
# =============================================================================

# -----------------------------------------------------------------------------
# Latest Amazon Linux 2023 AMI. AL2023 ships with SSM agent preinstalled and
# enabled. We pin this via a data source so the AMI ID is correct in any
# region the project ever runs in.
# -----------------------------------------------------------------------------
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# -----------------------------------------------------------------------------
# Bastion security group — no ingress at all (SSM uses outbound polls).
# Egress is restrictive: only HTTPS for SSM/yum mirrors and Postgres to RDS.
# -----------------------------------------------------------------------------
resource "aws_security_group" "bastion" {
  name        = "${var.project_name}-bastion"
  description = "Bastion host SG. No ingress. SSM agent uses outbound HTTPS."
  vpc_id      = module.vpc.vpc_id

  # NOTE: deliberately no ingress rules, no port 22, nothing.

  tags = {
    Component = "bastion"
  }
}

resource "aws_vpc_security_group_egress_rule" "bastion_https_anywhere" {
  security_group_id = aws_security_group.bastion.id
  description       = "HTTPS for SSM endpoints, EC2 messages, and yum mirrors."
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "bastion_to_rds" {
  security_group_id            = aws_security_group.bastion.id
  description                  = "Postgres to the RDS security group only."
  referenced_security_group_id = aws_security_group.rds.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

# -----------------------------------------------------------------------------
# The bastion EC2 instance.
# -----------------------------------------------------------------------------
resource "aws_instance" "bastion" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = var.bastion_instance_type

  # AWS Academy ships a pre-created instance profile that wraps LabRole
  # and includes AmazonSSMManagedInstanceCore — exactly what SSM agent
  # needs to register itself. We CANNOT create our own instance profile
  # in the lab, so we attach by name to the existing one.
  iam_instance_profile = var.lab_instance_profile_name

  # Private subnet. No public IP. SSM is the only way in.
  subnet_id                   = module.vpc.private_subnets[0]
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = false

  # Encrypted root volume.
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    encrypted             = true
    delete_on_termination = true
  }

  # IMDSv2 only — defense in depth.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # Install psql so we can run queries on the bastion itself if needed
  # (most of the time we'll port-forward to our laptop instead).
  user_data = <<-EOT
    #!/bin/bash
    set -eux
    dnf install -y postgresql15 || dnf install -y postgresql || true
    echo "bastion-ready" > /tmp/bastion-ready
  EOT

  tags = {
    Component = "bastion"
    Name      = "${var.project_name}-bastion"
  }

  # Don't trigger a replacement when AWS releases a new AL2023 AMI; we'll
  # cycle the bastion explicitly when we want a refreshed image.
  lifecycle {
    ignore_changes = [ami]
  }
}

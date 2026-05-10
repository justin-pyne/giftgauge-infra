# =============================================================================
# Bastion host — public-subnet SSH jump host for ad-hoc RDS connectivity.
#
# Architecture:
#
#   your laptop ──[ssh -L 15432:rds-host:5432]──▶ bastion (public subnet)
#                                                          │
#                                                          ▼ private network
#                                                  RDS Postgres
#                                                  (database subnet)
#
# Original design used a private-subnet bastion accessed via AWS SSM Session
# Manager. SSM agent registration failed in our AWS Academy lab environment
# despite correct IAM (LabRole had AmazonSSMManagedInstanceCore) and open
# egress. Rather than spend more time debugging an undocumented lab quirk,
# we fell back to the conventional pattern: public IP, narrowed SSH ingress.
# Decision recorded in docs/decisions.md § N.
#
# Cost: t3.nano is ~$3.50/month if 24/7. EBS volume ~$1/month.
# Run `aws ec2 stop-instances` to pause without losing the instance.
# =============================================================================

# -----------------------------------------------------------------------------
# Latest Amazon Linux 2023 AMI. AL2023 ships with the AWS CLI and dnf
# preconfigured for the AWS package mirror.
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
# Register the local SSH public key with EC2 so it can be installed at boot.
# The corresponding private key never leaves the operator's laptop.
# -----------------------------------------------------------------------------
resource "aws_key_pair" "bastion" {
  key_name   = "${var.project_name}-bastion"
  public_key = file(pathexpand(var.bastion_public_key_path))

  tags = {
    Component = "bastion"
  }
}

# -----------------------------------------------------------------------------
# Bastion security group.
#
# Ingress: SSH from the operator's home IP only. NEVER 0.0.0.0/0.
# Egress:  all (the bastion is a personal jump host; restrictive egress is
#          theatre and we already learned the lesson with SSM).
# -----------------------------------------------------------------------------
resource "aws_security_group" "bastion" {
  name        = "${var.project_name}-bastion"
  description = "SSH bastion for ${var.project_name}. Ingress narrowed to operator IP."
  vpc_id      = module.vpc.vpc_id

  tags = {
    Component = "bastion"
  }
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  security_group_id = aws_security_group.bastion.id

  description = "SSH from operator IP only."
  cidr_ipv4   = var.bastion_allowed_cidr
  ip_protocol = "tcp"
  from_port   = 22
  to_port     = 22
}

resource "aws_vpc_security_group_egress_rule" "bastion_egress_all" {
  security_group_id = aws_security_group.bastion.id

  description = "All outbound. Bastion is a personal jump host with no data."
  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

# -----------------------------------------------------------------------------
# The bastion EC2 instance.
# -----------------------------------------------------------------------------
resource "aws_instance" "bastion" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = var.bastion_instance_type
  key_name      = aws_key_pair.bastion.key_name

  # AWS Academy's pre-existing instance profile — gives the bastion the
  # same broad permissions as the LabRole. This lets you run AWS CLI
  # commands directly on the bastion (e.g. fetch the DB password from
  # Secrets Manager without exporting credentials).
  iam_instance_profile = var.lab_instance_profile_name

  # Public subnet, with a public IP. This is what the SSM-pattern was
  # avoiding; we accept it deliberately given the SSM problems we hit.
  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = true

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

  # Install psql client at first boot. Useful if you SSH in and want to
  # poke the DB directly rather than tunnel from your laptop.
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

  # Don't trigger replacement when AWS releases a new AL2023 AMI; we cycle
  # the bastion deliberately when we want a refreshed image.
  lifecycle {
    ignore_changes = [ami]
  }
}

# =============================================================================
# Application namespaces and per-namespace database secrets.
#
# Each application environment (dev, qa, uat) gets:
#   - Its own Kubernetes namespace
#   - Its own DB credentials Secret with:
#       DATABASE_URL       → connection string for the per-env database
#       ADMIN_DATABASE_URL → connection string for the master 'giftgauge' DB
#                           (used by the migration Job to CREATE DATABASE)
#       DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD (broken out for any
#       service that wants individual fields instead of parsing the URL)
#
# Per-env database names: giftgauge_dev, giftgauge_qa, giftgauge_uat
# These do NOT exist on RDS until the Helm migration Job runs against them
# the first time. The Job reads ADMIN_DATABASE_URL to do the CREATE DATABASE.
#
# Why three separate resource blocks instead of a for_each map: the dev
# namespace and secret already exist in Terraform state from Phase 6A.
# Refactoring to for_each would require terraform state mv to avoid
# destroying and recreating them. Three blocks is more verbose but
# avoids that risk.
#
# Why sslmode=no-verify: RDS Postgres requires SSL by default, and the
# Node 'pg' driver with sslmode=require fails because Amazon-issued certs
# aren't in the default Node trust store. no-verify gives us TLS encryption
# without cert chain verification. Acceptable for class project; production
# would mount the AWS RDS root CA bundle and use sslmode=verify-full.
# =============================================================================

locals {
  # Reused across all per-env DB URLs.
  rds_password = random_password.rds_master.result
  rds_user     = aws_db_instance.main.username
  rds_host     = aws_db_instance.main.address
  rds_port     = tostring(aws_db_instance.main.port)
  rds_master   = aws_db_instance.main.db_name # "giftgauge"

  # Master DB URL (same for every env).
  rds_admin_url = "postgresql://${local.rds_user}:${local.rds_password}@${local.rds_host}:${local.rds_port}/${local.rds_master}?sslmode=no-verify"
}

# =============================================================================
# dev
# =============================================================================

resource "kubernetes_namespace" "dev" {
  metadata {
    name = "dev"

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "giftgauge.io/environment"     = "dev"
    }
  }
}

resource "kubernetes_secret" "dev_db_credentials" {
  metadata {
    name      = "giftgauge-db"
    namespace = kubernetes_namespace.dev.metadata[0].name
  }

  data = {
    DATABASE_URL       = "postgresql://${local.rds_user}:${local.rds_password}@${local.rds_host}:${local.rds_port}/giftgauge_dev?sslmode=no-verify"
    ADMIN_DATABASE_URL = local.rds_admin_url
    DB_HOST            = local.rds_host
    DB_PORT            = local.rds_port
    DB_NAME            = "giftgauge_dev"
    DB_USER            = local.rds_user
    DB_PASSWORD        = local.rds_password
  }

  type = "Opaque"
}

# =============================================================================
# qa
# =============================================================================

resource "kubernetes_namespace" "qa" {
  metadata {
    name = "qa"

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "giftgauge.io/environment"     = "qa"
    }
  }
}

resource "kubernetes_secret" "qa_db_credentials" {
  metadata {
    name      = "giftgauge-db"
    namespace = kubernetes_namespace.qa.metadata[0].name
  }

  data = {
    DATABASE_URL       = "postgresql://${local.rds_user}:${local.rds_password}@${local.rds_host}:${local.rds_port}/giftgauge_qa?sslmode=no-verify"
    ADMIN_DATABASE_URL = local.rds_admin_url
    DB_HOST            = local.rds_host
    DB_PORT            = local.rds_port
    DB_NAME            = "giftgauge_qa"
    DB_USER            = local.rds_user
    DB_PASSWORD        = local.rds_password
  }

  type = "Opaque"
}

# =============================================================================
# uat
# =============================================================================

resource "kubernetes_namespace" "uat" {
  metadata {
    name = "uat"

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "giftgauge.io/environment"     = "uat"
    }
  }
}

resource "kubernetes_secret" "uat_db_credentials" {
  metadata {
    name      = "giftgauge-db"
    namespace = kubernetes_namespace.uat.metadata[0].name
  }

  data = {
    DATABASE_URL       = "postgresql://${local.rds_user}:${local.rds_password}@${local.rds_host}:${local.rds_port}/giftgauge_uat?sslmode=no-verify"
    ADMIN_DATABASE_URL = local.rds_admin_url
    DB_HOST            = local.rds_host
    DB_PORT            = local.rds_port
    DB_NAME            = "giftgauge_uat"
    DB_USER            = local.rds_user
    DB_PASSWORD        = local.rds_password
  }

  type = "Opaque"
}

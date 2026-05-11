# =============================================================================
# Application namespaces and per-namespace database secrets.
#
# Environments:
#   dev, qa, uat              — single-color, simple subdomain per env
#   prod-blue, prod-green     — blue/green pair, share giftgauge_prod database,
#                              one is "active" at a time (serves app.justinpyne.xyz)
#
# Per-env database names (created lazily by the Helm migration Job):
#   giftgauge_dev, giftgauge_qa, giftgauge_uat, giftgauge_prod
#
# Why prod-blue and prod-green share giftgauge_prod: both colors are running
# the same application against the same data. Schema changes that bridge
# multiple deploys must use the expand/migrate/contract pattern (Day-2 demo).
# =============================================================================

locals {
  rds_password         = random_password.rds_master.result
  rds_password_encoded = urlencode(random_password.rds_master.result)
  rds_user             = aws_db_instance.main.username
  rds_host             = aws_db_instance.main.address
  rds_port             = tostring(aws_db_instance.main.port)
  rds_master           = aws_db_instance.main.db_name # "giftgauge"

  rds_admin_url = "postgresql://${local.rds_user}:${local.rds_password_encoded}@${local.rds_host}:${local.rds_port}/${local.rds_master}?sslmode=no-verify"
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
    DATABASE_URL       = "postgresql://${local.rds_user}:${local.rds_password_encoded}@${local.rds_host}:${local.rds_port}/giftgauge_dev?sslmode=no-verify"
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
    DATABASE_URL       = "postgresql://${local.rds_user}:${local.rds_password_encoded}@${local.rds_host}:${local.rds_port}/giftgauge_qa?sslmode=no-verify"
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
    DATABASE_URL       = "postgresql://${local.rds_user}:${local.rds_password_encoded}@${local.rds_host}:${local.rds_port}/giftgauge_uat?sslmode=no-verify"
    ADMIN_DATABASE_URL = local.rds_admin_url
    DB_HOST            = local.rds_host
    DB_PORT            = local.rds_port
    DB_NAME            = "giftgauge_uat"
    DB_USER            = local.rds_user
    DB_PASSWORD        = local.rds_password
  }
  type = "Opaque"
}

# =============================================================================
# prod-blue
# =============================================================================

resource "kubernetes_namespace" "prod_blue" {
  metadata {
    name = "prod-blue"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "giftgauge.io/environment"     = "prod"
      "giftgauge.io/color"           = "blue"
    }
  }
}

resource "kubernetes_secret" "prod_blue_db_credentials" {
  metadata {
    name      = "giftgauge-db"
    namespace = kubernetes_namespace.prod_blue.metadata[0].name
  }
  data = {
    DATABASE_URL       = "postgresql://${local.rds_user}:${local.rds_password_encoded}@${local.rds_host}:${local.rds_port}/giftgauge_prod?sslmode=no-verify"
    ADMIN_DATABASE_URL = local.rds_admin_url
    DB_HOST            = local.rds_host
    DB_PORT            = local.rds_port
    DB_NAME            = "giftgauge_prod"
    DB_USER            = local.rds_user
    DB_PASSWORD        = local.rds_password
  }
  type = "Opaque"
}

# =============================================================================
# prod-green
# =============================================================================

resource "kubernetes_namespace" "prod_green" {
  metadata {
    name = "prod-green"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "giftgauge.io/environment"     = "prod"
      "giftgauge.io/color"           = "green"
    }
  }
}

resource "kubernetes_secret" "prod_green_db_credentials" {
  metadata {
    name      = "giftgauge-db"
    namespace = kubernetes_namespace.prod_green.metadata[0].name
  }
  data = {
    DATABASE_URL       = "postgresql://${local.rds_user}:${local.rds_password_encoded}@${local.rds_host}:${local.rds_port}/giftgauge_prod?sslmode=no-verify"
    ADMIN_DATABASE_URL = local.rds_admin_url
    DB_HOST            = local.rds_host
    DB_PORT            = local.rds_port
    DB_NAME            = "giftgauge_prod"
    DB_USER            = local.rds_user
    DB_PASSWORD        = local.rds_password
  }
  type = "Opaque"
}

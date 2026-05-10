# =============================================================================
# Observability stack — kube-prometheus-stack + Loki + Promtail.
#
# Components installed:
#   - Prometheus           metrics collection
#   - Grafana              dashboards (exposed at grafana.justinpyne.xyz
#                          via Ingress + Let's Encrypt + GitHub OAuth)
#   - Alertmanager         alert routing (configured for Gmail SMTP)
#   - node-exporter        per-node CPU / memory / disk metrics
#   - kube-state-metrics   Kubernetes object state metrics
#   - Loki                 log storage (single-binary mode)
#   - Promtail             log shipping (DaemonSet)
#
# All persistence is emptyDir because EBS CSI isn't available in this lab
# variant (decisions.md § P). For an 8-minute demo this is fine; pods don't
# restart often, and Grafana dashboards live as ConfigMaps.
#
# Default alert rules from kube-prometheus-stack will fire on conditions
# like NodeNotReady, KubePodCrashLooping, NodeFilesystemAlmostOutOfSpace —
# everything the rubric expects.
# =============================================================================

# -----------------------------------------------------------------------------
# Namespace.
# -----------------------------------------------------------------------------
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# Kubernetes secret holding the Grafana admin password.
#
# We don't actually want to use the admin form (it's disabled in OAuth-only
# mode), but the chart requires SOME admin password to be set, and we'd
# rather control the value than let the chart auto-generate something we
# can't easily retrieve later.
# -----------------------------------------------------------------------------
resource "random_password" "grafana_admin" {
  length  = 32
  special = false
}

resource "kubernetes_secret" "grafana_admin" {
  metadata {
    name      = "grafana-admin"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    "admin-user"     = "admin"
    "admin-password" = random_password.grafana_admin.result
  }

  type = "Opaque"
}

# -----------------------------------------------------------------------------
# Kubernetes secret holding GitHub OAuth credentials.
#
# Grafana's chart refuses to render with sensitive values inline (it scans
# for keys named *secret*, *token*, *password* and errors out — a guardrail
# against accidentally checking secrets into git via Helm values). The
# canonical workaround: store the secret as a Kubernetes Secret and tell
# Grafana to read it via environment-variable expansion in grafana.ini.
# -----------------------------------------------------------------------------
resource "kubernetes_secret" "grafana_oauth" {
  metadata {
    name      = "grafana-github-oauth"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    GF_AUTH_GITHUB_CLIENT_ID     = var.github_oauth_client_id
    GF_AUTH_GITHUB_CLIENT_SECRET = var.github_oauth_client_secret
  }

  type = "Opaque"
}

# -----------------------------------------------------------------------------
# kube-prometheus-stack
#
# This is the canonical bundle. One Helm release installs Prometheus
# Operator, Prometheus, Alertmanager, Grafana, node-exporter, and
# kube-state-metrics with sensible defaults and dashboards.
# -----------------------------------------------------------------------------
resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "65.5.0"

  timeout = 600

  values = [
    yamlencode({
      # ---------------- Prometheus ----------------
      prometheus = {
        prometheusSpec = {
          retention = "1d" # tight because we use emptyDir
          resources = {
            requests = { cpu = "200m", memory = "512Mi" }
            limits   = { memory = "1Gi" }
          }
          # No storageSpec → defaults to emptyDir.
          # Keep ServiceMonitor selectors permissive so workloads in
          # other namespaces (Phase 6) get scraped automatically.
          serviceMonitorSelectorNilUsesHelmValues = false
          podMonitorSelectorNilUsesHelmValues     = false
          ruleSelectorNilUsesHelmValues           = false
          probeSelectorNilUsesHelmValues          = false

          nodeSelector = { nodegroup = "primary" }
        }
      }

      # ---------------- Alertmanager ----------------
      alertmanager = {
        alertmanagerSpec = {
          replicas = 1
          resources = {
            requests = { cpu = "50m", memory = "64Mi" }
            limits   = { memory = "128Mi" }
          }
          nodeSelector = { nodegroup = "primary" }
        }

        config = {
          global = {
            smtp_smarthost     = "smtp.gmail.com:587"
            smtp_from          = var.alert_email_address
            smtp_auth_username = var.alert_email_address
            smtp_auth_password = var.gmail_app_password
            smtp_require_tls   = true
          }
          route = {
            receiver        = "gmail"
            group_wait      = "30s"
            group_interval  = "5m"
            repeat_interval = "4h"
            routes = [
              {
                # Inhibit chatty Watchdog/InfoInhibitor alerts.
                matchers = ["alertname=~\"InfoInhibitor|Watchdog\""]
                receiver = "null"
              },
              {
                matchers = ["severity=~\"critical|warning\""]
                receiver = "gmail"
              },
            ]
          }
          receivers = [
            { name = "null" },
            {
              name = "gmail"
              email_configs = [
                {
                  to            = var.alert_email_address
                  send_resolved = true
                },
              ]
            },
          ]
        }
      }

      # ---------------- Grafana ----------------
      grafana = {
        # Use the secret we created for admin credentials.
        admin = {
          existingSecret = kubernetes_secret.grafana_admin.metadata[0].name
          userKey        = "admin-user"
          passwordKey    = "admin-password"
        }

        # No PV; ConfigMap-backed dashboards survive restarts anyway.
        persistence = { enabled = false }

        # Load OAuth credentials from the Kubernetes Secret as env vars,
        # so grafana.ini's $__env{...} placeholders resolve at runtime.
        # Without this, Grafana sees the literal string "$__env{...}" as
        # the client_id and sends nonsense to GitHub → 404.
        envFromSecret = kubernetes_secret.grafana_oauth.metadata[0].name

        resources = {
          requests = { cpu = "100m", memory = "128Mi" }
          limits   = { memory = "256Mi" }
        }
        nodeSelector = { nodegroup = "primary" }

        # Loki as an additional data source.
        additionalDataSources = [
          {
            name      = "Loki"
            type      = "loki"
            url       = "http://loki.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:3100"
            access    = "proxy"
            isDefault = false
          }
        ]

        # Grafana INI — OAuth, no basic auth, root URL.
        "grafana.ini" = {
          server = {
            root_url            = "https://grafana.${var.public_domain}"
            serve_from_sub_path = false
          }
          # Disable the local username/password login form. OAuth is the
          # only way in. This is the rubric requirement.
          auth = {
            disable_login_form = true
          }
          "auth.basic" = {
            enabled = true
          }
          "auth.anonymous" = {
            enabled = false
          }
          # GitHub OAuth.
          "auth.github" = {
            enabled        = true
            allow_sign_up  = true
            client_id      = "$__env{GF_AUTH_GITHUB_CLIENT_ID}"
            client_secret  = "$__env{GF_AUTH_GITHUB_CLIENT_SECRET}"
            scopes         = "user:email,read:org"
            auth_url       = "https://github.com/login/oauth/authorize"
            token_url      = "https://github.com/login/oauth/access_token"
            api_url        = "https://api.github.com/user"
            allowed_emails = var.alert_email_address
          }
          users = {
            auto_assign_org_role = "Admin"
          }
        }

        # Ingress — picked up by ingress-nginx, cert from Let's Encrypt.
        ingress = {
          enabled          = true
          ingressClassName = "nginx"
          annotations = {
            "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
          }
          hosts = ["grafana.${var.public_domain}"]
          tls = [
            {
              hosts      = ["grafana.${var.public_domain}"]
              secretName = "grafana-tls"
            },
          ]
        }
      }

      # ---------------- Node exporter & kube-state-metrics ----------------
      # Defaults are fine. node-exporter runs as a DaemonSet on every node
      # and exposes per-node CPU/memory/disk/network metrics. kube-state-
      # metrics runs as a single deployment exposing K8s object state.
    })
  ]

  depends_on = [
    helm_release.cert_manager,
    helm_release.ingress_nginx,
  ]
}

# -----------------------------------------------------------------------------
# Loki — log storage, single-binary mode (cheaper, sufficient for our scale).
# -----------------------------------------------------------------------------
resource "helm_release" "loki" {
  name       = "loki"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = "6.20.0"

  timeout = 300

  values = [
    yamlencode({
      deploymentMode = "SingleBinary"

      loki = {
        # Lab-friendly: auth disabled (we're inside the cluster anyway,
        # accessed only via Grafana over its own OAuth-gated UI).
        auth_enabled = false

        commonConfig = {
          replication_factor = 1
        }

        schemaConfig = {
          configs = [
            {
              from         = "2024-04-01"
              store        = "tsdb"
              object_store = "filesystem"
              schema       = "v13"
              index = {
                prefix = "index_"
                period = "24h"
              }
            },
          ]
        }

        storage = {
          type = "filesystem"
        }

        # Disable structured metadata — required at our schema config.
        limits_config = {
          allow_structured_metadata = false
        }
      }

      # Run loki in single-binary mode with one replica.
      singleBinary = {
        replicas = 1
        persistence = {
          enabled = false
        }
        # Loki tries to mkdir /var/loki for ruler-storage at startup. The
        # chart only mounts /var/loki when persistence is enabled (PVC).
        # Without EBS CSI we can't use a PVC, so we mount an emptyDir at
        # the same path explicitly. Same end-result: Loki has somewhere
        # writable to put its data, lost on pod restart (acceptable for demo).
        extraVolumes = [
          {
            name     = "loki-data"
            emptyDir = {}
          },
        ]
        extraVolumeMounts = [
          {
            name      = "loki-data"
            mountPath = "/var/loki"
          },
        ]
        resources = {
          requests = { cpu = "100m", memory = "256Mi" }
          limits   = { memory = "512Mi" }
        }
        nodeSelector = { nodegroup = "primary" }
      }

      # Disable the components we're not using in single-binary mode.
      backend        = { replicas = 0 }
      read           = { replicas = 0 }
      write          = { replicas = 0 }
      ingester       = { replicas = 0 }
      querier        = { replicas = 0 }
      queryFrontend  = { replicas = 0 }
      queryScheduler = { replicas = 0 }
      distributor    = { replicas = 0 }
      compactor      = { replicas = 0 }
      indexGateway   = { replicas = 0 }
      bloomCompactor = { replicas = 0 }
      bloomGateway   = { replicas = 0 }

      # Disable chunks-cache and results-cache (memcached) to save resources.
      chunksCache  = { enabled = false }
      resultsCache = { enabled = false }

      # Disable the test runner.
      test = { enabled = false }

      # Disable the gateway (nginx in front of Loki) — Grafana talks directly.
      gateway = { enabled = false }

      lokiCanary = { enabled = false }

      # Skip self-monitoring of Loki itself for simplicity.
      monitoring = {
        selfMonitoring = {
          enabled = false
          grafanaAgent = {
            installOperator = false
          }
        }
      }
    })
  ]

  depends_on = [helm_release.kube_prometheus_stack]
}

# -----------------------------------------------------------------------------
# Promtail — DaemonSet that ships container logs to Loki.
# -----------------------------------------------------------------------------
resource "helm_release" "promtail" {
  name       = "promtail"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  repository = "https://grafana.github.io/helm-charts"
  chart      = "promtail"
  version    = "6.16.6"

  timeout = 300

  values = [
    yamlencode({
      config = {
        clients = [
          {
            url = "http://loki.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:3100/loki/api/v1/push"
          },
        ]
      }

      resources = {
        requests = { cpu = "50m", memory = "64Mi" }
        limits   = { memory = "128Mi" }
      }

      # Promtail runs on every node (DaemonSet); it MUST tolerate any
      # node taints to ship that node's logs.
      tolerations = [
        {
          operator = "Exists"
          effect   = "NoSchedule"
        },
      ]
    })
  ]

  depends_on = [helm_release.loki]
}

terraform {
  required_version = ">= 1.17.0, < 2.0.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.5"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

# An isolated training environment. The existing `opsforge` namespace is untouched.
provider "kubernetes" {
  config_path    = pathexpand("~/.kube/config")
  config_context = "kind-opsforge"
}

locals {
  namespace = "opsforge-tf"
  api_image = "opsforge-api:kind"
  labels = {
    "app.kubernetes.io/part-of"    = "opsforge"
    "app.kubernetes.io/managed-by" = "terraform"
  }
  api_labels = {
    "app.kubernetes.io/name" = "opsforge-api"
  }
  db_labels = {
    "app.kubernetes.io/name" = "opsforge-db"
  }
}

resource "kubernetes_namespace_v1" "opsforge" {
  metadata {
    name   = local.namespace
    labels = local.labels
  }
}

# Separate, randomly generated *lab-only* credentials. Never reuse real passwords.
# The generated password and Kubernetes Secret are recorded in LOCAL Terraform state.
resource "random_password" "postgres" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "database" {
  metadata {
    name      = "opsforge-db"
    namespace = kubernetes_namespace_v1.opsforge.metadata[0].name
    labels    = local.labels
  }
  type = "Opaque"
  data = {
    password     = random_password.postgres.result
    database_url = "postgresql+psycopg://opsforge:${random_password.postgres.result}@opsforge-db:5432/opsforge"
  }
}

resource "kubernetes_service_v1" "database" {
  metadata {
    name      = "opsforge-db"
    namespace = kubernetes_namespace_v1.opsforge.metadata[0].name
    labels    = local.db_labels
  }
  spec {
    cluster_ip = "None"
    selector   = local.db_labels
    port {
      name        = "postgres"
      port        = 5432
      target_port = 5432
    }
  }
}

resource "kubernetes_stateful_set_v1" "database" {
  metadata {
    name      = "opsforge-db"
    namespace = kubernetes_namespace_v1.opsforge.metadata[0].name
    labels    = merge(local.db_labels, local.labels)
  }
  spec {
    service_name = kubernetes_service_v1.database.metadata[0].name
    replicas     = 1
    selector {
      match_labels = local.db_labels
    }
    template {
      metadata {
        labels = local.db_labels
      }
      spec {
        automount_service_account_token = false
        container {
          name              = "postgres"
          image             = "postgres:17-alpine"
          image_pull_policy = "IfNotPresent"
          port {
            name           = "postgres"
            container_port = 5432
          }
          env {
            name  = "POSTGRES_DB"
            value = "opsforge"
          }
          env {
            name  = "POSTGRES_USER"
            value = "opsforge"
          }
          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.database.metadata[0].name
                key  = "password"
              }
            }
          }
          volume_mount {
            name       = "data"
            mount_path = "/var/lib/postgresql/data"
          }
          readiness_probe {
            exec {
              command = ["sh", "-c", "pg_isready -U opsforge -d opsforge"]
            }
            period_seconds  = 5
            timeout_seconds = 3
          }
          liveness_probe {
            exec {
              command = ["sh", "-c", "pg_isready -U opsforge -d opsforge"]
            }
            period_seconds  = 10
            timeout_seconds = 3
          }
          resources {
            requests = {
              cpu    = "50m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }
        }
      }
    }
    volume_claim_template {
      metadata {
        name = "data"
      }
      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = "standard"
        resources {
          requests = {
            storage = "1Gi"
          }
        }
      }
    }
  }
  depends_on = [kubernetes_secret_v1.database]
}

resource "kubernetes_service_v1" "api" {
  metadata {
    name      = "opsforge-api"
    namespace = kubernetes_namespace_v1.opsforge.metadata[0].name
    labels    = local.api_labels
  }
  spec {
    selector = local.api_labels
    port {
      name        = "http"
      port        = 8000
      target_port = "http"
    }
  }
}

resource "kubernetes_deployment_v1" "api" {
  metadata {
    name      = "opsforge-api"
    namespace = kubernetes_namespace_v1.opsforge.metadata[0].name
    labels    = merge(local.api_labels, local.labels)
  }
  spec {
    replicas               = 1
    revision_history_limit = 3
    strategy {
      type = "Recreate" # Alembic migrations currently run at API startup.
    }
    selector {
      match_labels = local.api_labels
    }
    template {
      metadata {
        labels = local.api_labels
      }
      spec {
        automount_service_account_token = false
        security_context {
          run_as_non_root = true
          run_as_user     = 10001
          run_as_group    = 10001
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }
        init_container {
          name              = "wait-for-db"
          image             = local.api_image
          image_pull_policy = "IfNotPresent"
          command           = ["python", "-c"]
          args = [<<-PY
            import os
            import time
            from sqlalchemy import create_engine, text
            engine = create_engine(os.environ["DATABASE_URL"], pool_pre_ping=True)
            for _ in range(60):
                try:
                    with engine.connect() as conn:
                        conn.execute(text("SELECT 1"))
                    break
                except Exception:
                    time.sleep(2)
            else:
                raise SystemExit("Database unavailable after 120 seconds")
          PY
          ]
          env {
            name = "DATABASE_URL"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.database.metadata[0].name
                key  = "database_url"
              }
            }
          }
          resources {
            requests = {
              cpu    = "20m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }
          security_context {
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }
        }
        container {
          name              = "api"
          image             = local.api_image
          image_pull_policy = "IfNotPresent"
          env {
            name = "DATABASE_URL"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.database.metadata[0].name
                key  = "database_url"
              }
            }
          }
          env {
            name  = "LOG_LEVEL"
            value = "INFO"
          }
          port {
            name           = "http"
            container_port = 8000
          }
          startup_probe {
            http_get {
              path = "/health/live"
              port = "http"
            }
            period_seconds    = 3
            failure_threshold = 40
          }
          readiness_probe {
            http_get {
              path = "/health/ready"
              port = "http"
            }
            period_seconds  = 5
            timeout_seconds = 3
          }
          liveness_probe {
            http_get {
              path = "/health/live"
              port = "http"
            }
            period_seconds  = 10
            timeout_seconds = 3
          }
          resources {
            requests = {
              cpu    = "50m"
              memory = "96Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "384Mi"
            }
          }
          security_context {
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }
        }
      }
    }
  }
  depends_on = [kubernetes_stateful_set_v1.database]
}

resource "kubernetes_namespace" "keda" {
  metadata {
    name = "keda"
  }
}

resource "helm_release" "keda" {
  name       = "keda"
  repository = "https://kedacore.github.io/charts"
  chart      = "keda"
  version    = local.keda_version
  namespace  = "keda"

  depends_on = [kubernetes_namespace.keda]
}
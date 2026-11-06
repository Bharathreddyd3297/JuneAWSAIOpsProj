# =============================================================== Read-only Kubernetes access for the tools
# IAM role telugu-pickles-aiops-kira --(EKS access entry)-->  Kubernetes group "aiops-readers"
#   --(ClusterRoleBinding)-->  ClusterRole "aiops-reader": get/list only, no secrets, no exec, no changes.

resource "aws_eks_access_entry" "aiops" {
  cluster_name      = var.cluster_name
  principal_arn     = aws_iam_role.kira.arn
  kubernetes_groups = ["aiops-readers"]
  type              = "STANDARD"
}

resource "kubernetes_cluster_role_v1" "aiops_reader" {
  metadata {
    name = "aiops-reader"
  }
  rule {
    api_groups = [""]
    resources  = ["pods", "events", "services", "endpoints", "nodes"]
    verbs      = ["get", "list"]
  }
  rule {
    api_groups = ["events.k8s.io"]
    resources  = ["events"]
    verbs      = ["get", "list"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets", "statefulsets"]
    verbs      = ["get", "list"]
  }
  rule {
    api_groups = ["argoproj.io"]
    resources  = ["rollouts", "analysisruns", "analysistemplates", "applications"]
    verbs      = ["get", "list"]
  }
  # Prometheus HTTP API through the API server proxy - this one Service only
  rule {
    api_groups     = [""]
    resources      = ["services/proxy"]
    resource_names = ["kube-prometheus-stack-prometheus", "kube-prometheus-stack-prometheus:9090"]
    verbs          = ["get"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "aiops_reader" {
  metadata {
    name = "aiops-reader"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.aiops_reader.metadata[0].name
  }
  subject {
    kind      = "Group"
    name      = "aiops-readers"
    api_group = "rbac.authorization.k8s.io"
  }
}

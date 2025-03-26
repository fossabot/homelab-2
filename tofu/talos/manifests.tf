// filepath: /root/homelab/tofu/talos/manifests.tf
locals {
  # Define safe fallbacks for kustomize rendering
  kustomize_paths = {
    cilium = "${path.root}/../k8s/infrastructure/network/cilium"
    coredns = "${path.root}/../k8s/infrastructure/network/coredns"
  }
}

# More robust implementation of kustomize rendering
# This checks if kustomize exists and provides better error handling
resource "terraform_data" "validate_kustomize" {
  provisioner "local-exec" {
    command = <<-EOT
      if ! command -v kustomize &> /dev/null; then
        echo "Error: kustomize is required but not found in PATH"
        echo "Please install kustomize: https://kubectl.docs.kubernetes.io/installation/kustomize/"
        exit 1
      fi
      
      # Validate that kustomization.yaml exists in the target directories
      for dir in "${local.kustomize_paths.cilium}" "${local.kustomize_paths.coredns}"; do
        if [ ! -f "$dir/kustomization.yaml" ]; then
          echo "Error: $dir/kustomization.yaml not found"
          exit 1
        fi
      done
    EOT
  }
}

# These data sources depend on the validation check first
data "external" "validated_cilium_kustomize" {
  depends_on = [terraform_data.validate_kustomize]
  
  program = [
    "bash", "-c", 
    <<-EOT
      set -euo pipefail
      
      # Use a temporary file for error capture
      error_file=$(mktemp)
      trap 'rm -f "$error_file"' EXIT
      
      if ! manifest=$(kustomize build --enable-helm "${local.kustomize_paths.cilium}" 2>"$error_file"); then
        error=$(cat "$error_file")
        echo "{\"status\": \"error\", \"error\": \"$error\", \"manifest\": \"\"}" 
        exit 0
      fi
      
      # Use jq to properly escape the manifest
      echo "{\"status\": \"success\", \"error\": \"\", \"manifest\": $(echo "$manifest" | jq -Rs .)}"
    EOT
  ]
}

data "external" "validated_coredns_kustomize" {
  depends_on = [terraform_data.validate_kustomize]
  
  program = [
    "bash", "-c", 
    <<-EOT
      set -euo pipefail
      
      # Use a temporary file for error capture
      error_file=$(mktemp)
      trap 'rm -f "$error_file"' EXIT
      
      if ! manifest=$(kustomize build --enable-helm "${local.kustomize_paths.coredns}" 2>"$error_file"); then
        error=$(cat "$error_file")
        echo "{\"status\": \"error\", \"error\": \"$error\", \"manifest\": \"\"}" 
        exit 0
      fi
      
      # Use jq to properly escape the manifest
      echo "{\"status\": \"success\", \"error\": \"\", \"manifest\": $(echo "$manifest" | jq -Rs .)}"
    EOT
  ]
}

# Expose the results with error checking
locals {
  cilium_manifest = data.external.validated_cilium_kustomize.result.status == "success" ? data.external.validated_cilium_kustomize.result.manifest : null
  coredns_manifest = data.external.validated_coredns_kustomize.result.status == "success" ? data.external.validated_coredns_kustomize.result.manifest : null
  
  # Error handling
  cilium_error = data.external.validated_cilium_kustomize.result.status == "error" ? data.external.validated_cilium_kustomize.result.error : null
  coredns_error = data.external.validated_coredns_kustomize.result.status == "error" ? data.external.validated_coredns_kustomize.result.error : null
  
  # Validation check - will cause Terraform to fail if manifests couldn't be rendered
  _validate_manifests = (local.cilium_error != null || local.coredns_error != null) ? file("ERROR: Failed to render manifests - Cilium: ${local.cilium_error}, CoreDNS: ${local.coredns_error}") : null
}
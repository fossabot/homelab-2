// filepath: /root/homelab/tofu/talos/manifests.tf
locals {
  # Define safe fallbacks for kustomize rendering
  kustomize_paths = {
    cilium = "${path.root}/../k8s/infrastructure/network/cilium"
    coredns = "${path.root}/../k8s/infrastructure/network/coredns"
  }
}

# More robust implementation of kustomize rendering
# This checks if kustomize exists but does NOT fail if it's missing (outputs a warning instead)
resource "terraform_data" "check_kustomize" {
  provisioner "local-exec" {
    command = <<-EOT
      if ! command -v kustomize &> /dev/null; then
        echo "Warning: kustomize is not found in PATH - falling back to static manifests"
        echo "For better results, consider installing kustomize: https://kubectl.docs.kubernetes.io/installation/kustomize/"
        exit 0
      fi

      # Check that kustomization.yaml exists in the target directories
      for dir in "${local.kustomize_paths.cilium}" "${local.kustomize_paths.coredns}"; do
        if [ ! -f "$dir/kustomization.yaml" ]; then
          echo "Warning: $dir/kustomization.yaml not found - falling back to static manifests"
          exit 0
        fi
      done

      echo "Kustomize is available and kustomization files exist."
    EOT
  }
}

# These data sources get information about kustomize availability
data "external" "kustomize_availability" {
  program = [
    "bash", "-c",
    <<-EOT
      if command -v kustomize &> /dev/null; then
        echo '{"available": "true"}'
      else
        echo '{"available": "false"}'
      fi
    EOT
  ]
}

# These data sources depend on the validation check first
data "external" "validated_cilium_kustomize" {
  # Use the non-blocking check
  depends_on = [terraform_data.check_kustomize]

  program = [
    "bash", "-c",
    <<-EOT
      set -eo pipefail

      # First check if kustomize is available
      if ! command -v kustomize &> /dev/null; then
        echo '{"status": "unavailable", "error": "kustomize not installed", "manifest": ""}'
        exit 0
      fi

      # Check if kustomization file exists
      if [ ! -f "${local.kustomize_paths.cilium}/kustomization.yaml" ]; then
        echo '{"status": "unavailable", "error": "kustomization.yaml not found", "manifest": ""}'
        exit 0
      fi

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
  # Use the non-blocking check
  depends_on = [terraform_data.check_kustomize]

  program = [
    "bash", "-c",
    <<-EOT
      set -eo pipefail

      # First check if kustomize is available
      if ! command -v kustomize &> /dev/null; then
        echo '{"status": "unavailable", "error": "kustomize not installed", "manifest": ""}'
        exit 0
      fi

      # Check if kustomization file exists
      if [ ! -f "${local.kustomize_paths.coredns}/kustomization.yaml" ]; then
        echo '{"status": "unavailable", "error": "kustomization.yaml not found", "manifest": ""}'
        exit 0
      fi

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
  # Now differentiate between "unavailable" (kustomize missing - use fallback)
  # and "error" (kustomize failed - report error)
  cilium_manifest = data.external.validated_cilium_kustomize.result.status == "success" ? data.external.validated_cilium_kustomize.result.manifest : null

  coredns_manifest = data.external.validated_coredns_kustomize.result.status == "success" ? data.external.validated_coredns_kustomize.result.manifest : null

  # Error handling - only fail on actual kustomize errors, not on "unavailable"
  cilium_error = data.external.validated_cilium_kustomize.result.status == "error" ? data.external.validated_cilium_kustomize.result.error : null

  coredns_error = data.external.validated_coredns_kustomize.result.status == "error" ? data.external.validated_coredns_kustomize.result.error : null

  # Only validate errors if kustomize is available and we expect it to work
  # Prevent hard failure when kustomize is missing
  _validate_manifests = (
    data.external.kustomize_availability.result.available == "true" &&
    (local.cilium_error != null || local.coredns_error != null)
  ) ? file("ERROR: Failed to render manifests with kustomize - Cilium: ${local.cilium_error}, CoreDNS: ${local.coredns_error}") : null
}

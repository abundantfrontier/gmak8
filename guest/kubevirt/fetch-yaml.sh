#!/bin/sh
# Download pinned KubeVirt/CDI/instancetype YAML. Cluster start must not curl GitHub.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$here/kubevirt.pin"
dest="$here/yaml"
mkdir -p "$dest"

curl -fsSL -o "$dest/kubevirt-operator.yaml" \
  "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml"
curl -fsSL -o "$dest/cdi-operator.yaml" \
  "https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-operator.yaml"
curl -fsSL -o "$dest/cdi-cr.yaml" \
  "https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-cr.yaml"
curl -fsSL -o "$dest/common-clusterinstancetypes.yaml" \
  "https://github.com/kubevirt/common-instancetypes/releases/download/${INSTANCETYPES_VERSION}/common-clusterinstancetypes-bundle-${INSTANCETYPES_VERSION}.yaml"
curl -fsSL -o "$dest/common-clusterpreferences.yaml" \
  "https://github.com/kubevirt/common-instancetypes/releases/download/${INSTANCETYPES_VERSION}/common-clusterpreferences-bundle-${INSTANCETYPES_VERSION}.yaml"

echo "fetch-yaml: wrote $dest (kept kubevirt-cr.yaml and local-path-storageprofile.yaml)"

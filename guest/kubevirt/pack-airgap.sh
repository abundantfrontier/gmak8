#!/bin/sh
# Pack linux/arm64 KubeVirt/CDI images with skopeo/crane. Not Docker. Do not vendor the tarball.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$here/airgap.pin"
images="$here/images.txt"
out=${DEST:-"$here/$AIRGAP_NAME"}
echo "pack-airgap: use skopeo copy --override-arch arm64 for each line in $images"
echo "pack-airgap: then tar.zst to $out (max $AIRGAP_MAX_BYTES bytes). Do not use docker.io."
echo "pack-airgap: pin the fedora/cirros aarch64 digest and record it in docs/eureka-local.md."
exit 1

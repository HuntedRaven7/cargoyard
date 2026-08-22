#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# Image Info Generation — edward (Arch base)
###############################################################################
# Generates /usr/share/ublue-os/image-info.json and customizes /usr/lib/os-release.
#
# Required env vars (set as ARGs in Containerfile):
#   IMAGE_NAME      - Image name (edward)
#   IMAGE_VENDOR    - Image vendor/owner (e.g. github username or org)
#   UBLUE_IMAGE_TAG - Image tag/stream (e.g. stable, testing)
#   BASE_IMAGE_NAME - Base image name (arch-bootc)
#   VERSION         - Full version string (e.g. stable-20250531)
#   SHA_HEAD_SHORT  - Short git SHA (optional, for dev builds)
###############################################################################

# Read IMAGE_NAME from /etc/environment if not set
if [[ -z "${IMAGE_NAME:-}" ]] && [[ -f /etc/environment ]]; then
    # shellcheck disable=SC1091
    . /etc/environment
fi

# Branding — customize these for your image
IMAGE_PRETTY_NAME="${IMAGE_PRETTY_NAME:-Containerino}"
IMAGE_NAME="${IMAGE_NAME:-edward}"
BASE_IMAGE_NAME="${BASE_IMAGE_NAME:-arch-bootc}"
IMAGE_LIKE="${IMAGE_LIKE:-arch}"

HOME_URL="${HOME_URL:-https://github.com/${IMAGE_VENDOR}/${IMAGE_NAME}}"
DOCUMENTATION_URL="${DOCUMENTATION_URL:-https://github.com/${IMAGE_VENDOR}/${IMAGE_NAME}/blob/main/README.md}"
SUPPORT_URL="${SUPPORT_URL:-https://github.com/${IMAGE_VENDOR}/${IMAGE_NAME}/issues}"
BUG_REPORT_URL="${BUG_REPORT_URL:-https://github.com/${IMAGE_VENDOR}/${IMAGE_NAME}/issues/new}"

# Paths
IMAGE_INFO="/usr/share/ublue-os/image-info.json"
OS_RELEASE="/usr/lib/os-release"

# Derive image flavor from name
if [[ "${IMAGE_NAME}" =~ nvidia ]]; then
	IMAGE_FLAVOR="nvidia"
else
	IMAGE_FLAVOR="main"
fi

# Image ref (used by bootc for upgrade source)
IMAGE_REF="ostree-image-signed:docker://ghcr.io/${IMAGE_VENDOR}/${IMAGE_NAME}"

###############################################################################
# Write image-info.json
###############################################################################
mkdir -p /usr/share/ublue-os
cat >"${IMAGE_INFO}" <<EOF
{
  "image-name": "${IMAGE_NAME}",
  "image-flavor": "${IMAGE_FLAVOR}",
  "image-vendor": "${IMAGE_VENDOR}",
  "image-ref": "${IMAGE_REF}",
  "image-tag": "${UBLUE_IMAGE_TAG}",
  "base-image-name": "${BASE_IMAGE_NAME}"
}
EOF

echo "Wrote ${IMAGE_INFO}"
echo "  image-name: ${IMAGE_NAME}"
echo "  image-flavor: ${IMAGE_FLAVOR}"
echo "  image-vendor: ${IMAGE_VENDOR}"

###############################################################################
# Customize /usr/lib/os-release
###############################################################################
# Only modify if the file exists and VARIANT_ID is not already set
if [[ -f "${OS_RELEASE}" ]] && ! grep -q "^VARIANT_ID=" "${OS_RELEASE}"; then
	# Read existing values
	if [[ -n "${VERSION:-}" ]]; then
		OS_VERSION="${VERSION}"
	else
		OS_VERSION="${UBLUE_IMAGE_TAG}"
	fi

	# Append our identity
	cat >>"${OS_RELEASE}" <<EOF

# ${IMAGE_NAME} image identity
VARIANT_ID="${IMAGE_FLAVOR}"
PRETTY_NAME="${IMAGE_PRETTY_NAME}"
NAME="${IMAGE_NAME}"
IMAGE_ID="${IMAGE_NAME}"
IMAGE_VERSION="${OS_VERSION}"
ID_LIKE="${IMAGE_LIKE}"
HOME_URL="${HOME_URL}"
DOCUMENTATION_URL="${DOCUMENTATION_URL}"
SUPPORT_URL="${SUPPORT_URL}"
BUG_REPORT_URL="${BUG_REPORT_URL}"
EOF

	echo "Customized ${OS_RELEASE}"
fi

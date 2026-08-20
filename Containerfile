###############################################################################
# MULTI-IMAGE CONTAINERFILE
###############################################################################
# This Containerfile builds multiple image variants using the IMAGE_VARIANT ARG.
#
# Supported variants:
#   - "edward" (default): GNOME desktop (Fedora Silverblue)
#   - "aira": KDE desktop (Bazzite)
#   - "server": Minimal server (uCore)
#   - "crmy": CRM server (Fedora bootc)
#
# Usage:
#   podman build --build-arg IMAGE_VARIANT=aira -t cargoyard-aira:stable .
#   podman build --build-arg IMAGE_VARIANT=edward -t cargoyard:stable .
#   podman build --build-arg IMAGE_VARIANT=server -t cargoyard-server:stable .
#   podman build --build-arg IMAGE_VARIANT=crmy -t cargoyard-crmy:stable .
#
# The project name is defined by IMAGE_NAME which is automatically set based
# on the IMAGE_VARIANT (cargoyard, cargoyard-aira, cargoyard-server, or cargoyard-crmy).
###############################################################################

###############################################################################
# MULTI-STAGE BUILD ARCHITECTURE
###############################################################################
# This Containerfile follows the Bluefin architecture pattern as implemented in
# @projectbluefin/distroless. The architecture layers OCI containers together:
#
# 1. Context Stage (ctx) - Combines resources from:
#    - Local build scripts and custom files
#    - @projectbluefin/common - Desktop configuration shared with Aurora
#    - @ublue-os/brew - Homebrew integration
#
# 2. Base Image varies by variant:
#    - edward: quay.io/fedora-ostree-desktops/silverblue:44 (Fedora 44, GNOME)
#    - aira: ghcr.io/ublue-os/bazzite:stable (Fedora 42, KDE)
#    - server: ghcr.io/ublue-os/ucore:stable (Minimal server)
#    - crmy: quay.io/fedora/fedora-bootc:44 (Fedora bootc)
#
# See: https://docs.projectbluefin.io/contributing/ for architecture diagram
###############################################################################

###############################################################################
# VARIANT SELECTION
###############################################################################
# Select which image variant to build. Default is "edward" (GNOME/Silverblue).
ARG IMAGE_VARIANT="edward"

# Validate variant - this ensures only supported variants are built
# hadolint ignore=DL3061,SC3010,SC3014
RUN <<VALIDATE
#!/bin/bash
set -euo pipefail
if [[ "${IMAGE_VARIANT}" != "edward" && "${IMAGE_VARIANT}" != "aira" && "${IMAGE_VARIANT}" != "server" && "${IMAGE_VARIANT}" != "crmy" ]]; then
    echo "ERROR: Invalid IMAGE_VARIANT '${IMAGE_VARIANT}'. Must be 'edward', 'aira', 'server', or 'crmy'."
    exit 1
fi
echo "Building variant: ${IMAGE_VARIANT}"
VALIDATE

###############################################################################
# BASE IMAGE SELECTION (must be outside multi-stage due to Dockerfile limitations)
###############################################################################
# The base image is selected based on IMAGE_VARIANT.
# NOTE: BuildKit/gapel multi-stage is used here - the base image varies by variant.
###############################################################################

# OCI context images - imported below and pinned directly in their FROM lines.
# The base image is pinned in the FROM line below and updated by Renovate.
FROM ghcr.io/projectbluefin/common:latest@sha256:df2fa93dac84cda91d568bd694e5051abbbdba37bf3d54a6cc15cdc80e645e2c AS common
FROM ghcr.io/ublue-os/brew:latest@sha256:5c5b6dea4b9faaab4d6fa81d7fc4f37f218c8a75a0839c72ae70b268bfdf4b0f AS brew

# Context stage - combine local and imported OCI container resources
FROM scratch AS ctx

COPY build /build
COPY custom /custom

# Copy variant-specific system files
COPY custom/system_files/edward /system_files/edward
COPY custom/system_files/aira /system_files/aira
COPY custom/system_files/server /system_files/server
COPY custom/system_files/ai /system_files/ai

# Copy from OCI containers to distinct subdirectories to avoid conflicts
COPY --from=common /system_files /oci/common
COPY --from=brew /system_files /oci/brew

###############################################################################
# BASE IMAGES
###############################################################################
# Different base images for each variant
###############################################################################

# Edward: GNOME desktop (Fedora Silverblue)
FROM quay.io/fedora-ostree-desktops/silverblue:44@sha256:1d1810dfd0e3fc41ec3bf2d6430963e9dda644e78472bae2005fca57c035201a AS base-edward

# Aira: KDE desktop (Bazzite)
FROM ghcr.io/ublue-os/bazzite:stable AS base-aira

# Server: Minimal server (uCore)
FROM ghcr.io/ublue-os/ucore:stable AS base-server

# CRMY: CRM server (Fedora bootc)
FROM quay.io/fedora/fedora-bootc:44 AS base-crmy

###############################################################################
# VARIANT IMAGES
###############################################################################
# Select the appropriate base image based on IMAGE_VARIANT
###############################################################################

# This stage selects the correct base image based on the variant
FROM base-${IMAGE_VARIANT}

# Image identity - these define how bootc, fastfetch, and the ublue ecosystem
# recognize your image. Change these to match your project name.
# IMAGE_NAME is automatically set based on IMAGE_VARIANT
ARG IMAGE_VARIANT="edward"
ARG IMAGE_VENDOR="huntedraven7"
ARG UBLUE_IMAGE_TAG="stable"
ARG VERSION=""

# Set IMAGE_NAME based on variant
ARG IMAGE_NAME_DEFAULT
# hadolint ignore=SC3010,SC3014
RUN <<SET_NAME
#!/bin/bash
set -euo pipefail
if [[ "${IMAGE_VARIANT}" == "aira" ]]; then
    IMAGE_NAME="cargoyard-aira"
elif [[ "${IMAGE_VARIANT}" == "server" ]]; then
    IMAGE_NAME="cargoyard-server"
elif [[ "${IMAGE_VARIANT}" == "crmy" ]]; then
    IMAGE_NAME="cargoyard-crmy"
else
    IMAGE_NAME="cargoyard"
fi
echo "IMAGE_NAME=${IMAGE_NAME}"
# Write to /etc/environment for build scripts
echo "IMAGE_NAME=${IMAGE_NAME}" >> /etc/environment
SET_NAME

# Set variant-specific ARGs
ARG BASE_IMAGE_NAME_DEFAULT
ARG FEDORA_MAJOR_VERSION="44"

### MODIFICATIONS
## Make modifications desired in your image and install packages by modifying the build scripts.
## The following RUN directives mount the ctx stage which includes:
##   - Local build scripts from /build
##   - Local custom files from /custom
##   - Files from @projectbluefin/common at /oci/common (includes branding/artwork content)
##   - Files from @ublue-os/brew at /oci/brew
## Scripts are run in numerical order (10-build.sh, 20-example.sh, etc.)

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/00-image-info.sh

# Set dnf options before build scripts (persists across subsequent RUN layers)
# Break the ostree hardlink first: base images ship /etc/dnf/dnf.conf as a
# hardlink into the object store. Writing to it in-place under buildah/btrfs
# corrupts the file (NUL bytes appended). Copy → mv breaks the link safely.
RUN cp /etc/dnf/dnf.conf /etc/dnf/dnf.conf.tmp && \
    mv /etc/dnf/dnf.conf.tmp /etc/dnf/dnf.conf && \
    dnf5 config-manager setopt keepcache=1 install_weak_deps=0

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/cache/rpm-ostree \
    --mount=type=secret,id=GITHUB_TOKEN \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/10-build.sh

### CLEANUP
## Use Bluefin's clean-stage.sh to remove build artifacts before linting.
## /run is deliberately not mounted as tmpfs here: clean-stage.sh must remove
## image-layer files such as /run/dnf so bootc lint's nonempty-run-tmp check
## passes. The script tolerates busy Buildah bind mounts while clearing contents.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=tmpfs,dst=/boot \
    /ctx/build/clean-stage.sh

### /opt
## Makes /opt writeable by default. Needs to be here to make the main image
## build strict (no /opt there). This is for downstream images/stuff like k0s.
## If you need /opt as an immutable real directory for build-time packages
## (e.g. google-chrome, docker-desktop), replace the next line with:
##   RUN rm /opt && mkdir /opt
RUN rm -rf /opt && ln -s /var/opt /opt

### INIT
## Required for bootc images
CMD ["/sbin/init"]

### LINTING
## Verify final image and contents are correct. --fatal-warnings catches issues.
RUN bootc container lint --fatal-warnings

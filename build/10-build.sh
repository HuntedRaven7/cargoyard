#!/usr/bin/bash

set -euo pipefail

###############################################################################
# Main Build Script
###############################################################################
# This script follows the @ublue-os/bluefin pattern for build scripts.
# It uses set -euo pipefail for strict error handling.
###############################################################################

# Read IMAGE_NAME and IMAGE_VARIANT from /etc/environment if not set
if [[ -z "${IMAGE_NAME:-}" ]]; then
    if [[ -f /etc/environment ]]; then
        # shellcheck disable=SC1091
        . /etc/environment
    fi
fi

# Default to edward variant if not set
IMAGE_VARIANT="${IMAGE_VARIANT:-edward}"

# Source helper functions
# shellcheck source=/dev/null
source /ctx/build/copr-helpers.sh

# Enable nullglob for all glob operations to prevent failures on empty matches
shopt -s nullglob

echo "::group:: Overlay Brew Integration Files"

# Brew integration files from @ublue-os/brew OCI (tarball, systemd services, shell integration)
rsync -rvK /ctx/oci/brew/ /

echo "::endgroup::"

echo "::group:: Copy Custom Files"

# Copy Brewfiles to standard location
mkdir -p /usr/share/ublue-os/homebrew/
cp /ctx/custom/brew/*.Brewfile /usr/share/ublue-os/homebrew/

# Consolidate Just Files
mkdir -p /usr/share/ublue-os/just/
find /ctx/custom/ujust -iname '*.just' -exec printf "\n\n" \; -exec cat {} \; >>/usr/share/ublue-os/just/60-custom.just

# Copy Flatpak preinstall files
mkdir -p /usr/share/flatpak/preinstall.d/
cp /ctx/custom/flatpaks/*.preinstall /usr/share/flatpak/preinstall.d/

# Copy system files (container definitions, launchers, desktop entries, etc.)
# Each variant has its own subdir under /ctx/system_files/

# Always copy Edward-specific system files (default variant)
if [ -d /ctx/system_files/edward ]; then
    cp -rf /ctx/system_files/edward/. /
fi

# Copy Aira-specific system files if this is the aira variant
if [[ "${IMAGE_VARIANT}" == "aira" ]] && [ -d /ctx/system_files/aira ]; then
    cp -rf /ctx/system_files/aira/. /
fi

# Copy Server-specific system files if this is the server variant
if [[ "${IMAGE_VARIANT}" == "server" ]] && [ -d /ctx/system_files/server ]; then
    cp -rf /ctx/system_files/server/. /
fi

echo "::endgroup::"

echo "::group:: Install Packages"

# Install the default packages and verify the DNF cache is working.
# gum is required by the default ujust recipes for interactive prompts.
dnf5 install -y tmux gum

# Variant-specific packages
if [[ "${IMAGE_VARIANT}" == "aira" ]]; then
    # Aira-specific packages
    PACKAGES=(
        git
        neovim
        kitty
        alacritty
    )
    dnf5 install -y --skip-unavailable \
        --setopt=install_weak_deps=False \
        "${PACKAGES[@]}"
elif [[ "${IMAGE_VARIANT}" == "server" ]]; then
    # Server-specific packages
    PACKAGES=(
        openssh-server
        git
        htop
    )
    dnf5 install -y --skip-unavailable \
        --setopt=install_weak_deps=False \
        "${PACKAGES[@]}"
elif [[ "${IMAGE_VARIANT}" == "crmy" ]]; then
    # CRMY-specific packages
    PACKAGES=(
        cockpit
        cockpit-podman
        openssh-server
        git
        tmux
        htop
    )
    dnf5 install -y --skip-unavailable \
        --setopt=install_weak_deps=False \
        "${PACKAGES[@]}"
fi

echo "::endgroup::"

echo "::group:: System Configuration"

# Enable/disable systemd services
systemctl enable podman.socket
systemctl enable brew-setup.service
systemctl enable brew-update.timer
systemctl enable brew-upgrade.timer
# Example: systemctl mask unwanted-service

# Aira-specific services
if [[ "${IMAGE_VARIANT}" == "aira" ]]; then
    systemctl enable setup-nix.service
    systemctl enable install-aira-configs.service
    systemctl enable setup-kwin-effects.service
elif [[ "${IMAGE_VARIANT}" == "server" ]]; then
    # Server-specific services
    systemctl enable cockpit.service
    systemctl enable sshd.service
elif [[ "${IMAGE_VARIANT}" == "crmy" ]]; then
    # CRMY-specific services
    systemctl enable cockpit.socket
    systemctl enable sshd.service
fi

echo "::endgroup::"

# Restore default glob behavior
shopt -u nullglob

echo "Custom build complete!"

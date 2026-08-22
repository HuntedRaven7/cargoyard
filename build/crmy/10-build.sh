#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# CRMY Build Script (Fedora bootc base, dnf5)
###############################################################################

# Read IMAGE_NAME from /etc/environment if not set
if [[ -z "${IMAGE_NAME:-}" ]] && [[ -f /etc/environment ]]; then
    # shellcheck disable=SC1091
    . /etc/environment
fi

echo "::group:: Overlay Brew Integration Files"

# Brew integration files from @ublue-os/brew OCI (tarball, systemd services,
# shell integration)
rsync -rvK /ctx/oci/brew/ /

echo "::endgroup::"

echo "::group:: Copy Custom Files"

shopt -s nullglob

# Copy Brewfiles to standard location
mkdir -p /usr/share/ublue-os/homebrew/
cp /ctx/custom/brew/*.Brewfile /usr/share/ublue-os/homebrew/

# Consolidate Just Files
mkdir -p /usr/share/ublue-os/just/
find /ctx/custom/ujust -iname '*.just' -exec printf "\n\n" \; -exec cat {} \; >>/usr/share/ublue-os/just/60-custom.just

# Copy Flatpak preinstall files
mkdir -p /usr/share/flatpak/preinstall.d/
cp /ctx/custom/flatpaks/*.preinstall /usr/share/flatpak/preinstall.d/

# The CRMY variant has no custom/system_files/crmy directory; it relies on the
# shared custom files above.

shopt -u nullglob

echo "::endgroup::"

echo "::group:: Install Packages"

# Install the default packages and verify the DNF cache is working.
# gum is required by the default ujust recipes for interactive prompts.
dnf5 install -y tmux gum

# CRMY-specific packages
PACKAGES=(
    cockpit
    cockpit-podman
    openssh-server
    git
    htop
)
dnf5 install -y --skip-unavailable \
    --setopt=install_weak_deps=False \
    "${PACKAGES[@]}"

echo "::endgroup::"

echo "::group:: System Configuration"

systemctl enable podman.socket
systemctl enable brew-setup.service
systemctl enable brew-update.timer
systemctl enable brew-upgrade.timer

# CRMY-specific services
systemctl enable cockpit.socket
systemctl enable sshd.service

echo "::endgroup::"

echo "CRMY build complete!"

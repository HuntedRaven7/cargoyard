#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# Edward Build Script (Arch base, pacman)
###############################################################################
# Base image: ghcr.io/huntedraven7/arch-bootc (Arch Linux — pacman, not dnf5).
# Desktop: Hyprland + Quickshell.
###############################################################################

# Read IMAGE_NAME from /etc/environment if not set
if [[ -z "${IMAGE_NAME:-}" ]] && [[ -f /etc/environment ]]; then
    # shellcheck disable=SC1091
    . /etc/environment
fi

echo "::group:: Install Packages"

# Base tooling
BASE_PACKAGES=(
    rsync      # required for the brew overlay step
    podman     # required by the container quadlets in system_files
    flatpak    # required for /usr/share/flatpak/preinstall.d at first boot
    tmux       # required by the default ujust recipes
    gum        # required by the default ujust recipes for interactive prompts
)

# Hyprland desktop stack (all verified in Arch extra)
DE_PACKAGES=(
    hyprland                    # compositor
    quickshell                  # shell/bar (Qt6 Quick)
    uwsm                        # Universal Wayland Session Manager (session launch)
    xdg-desktop-portal-hyprland # screencast/screenshots portal
    xdg-desktop-portal-gtk      # file chooser portal fallback
    xorg-xwayland               # X11 app support
    polkit-gnome                # polkit authentication agent
    greetd                      # display manager
    greetd-tuigreet             # console greeter
    fuzzel                      # app launcher
    mako                        # notifications
    grim                        # screenshots
    slurp                       # region selection for grim
    wl-clipboard                # wayland clipboard utilities
    hyprpaper                   # wallpaper daemon
    hypridle                    # idle daemon
    hyprlock                    # lock screen
    pipewire                    # audio/video server
    wireplumber                 # pipewire session manager
    pipewire-pulse              # pulseaudio compatibility
    pipewire-alsa               # alsa compatibility
    networkmanager              # network management
    noto-fonts                  # base fonts
    noto-fonts-emoji            # emoji fonts
)

pacman -Syu --noconfirm --needed "${BASE_PACKAGES[@]}" "${DE_PACKAGES[@]}"

echo "::endgroup::"

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

# Copy system files (quadlets, launchers, desktop entries)
cp -rf /ctx/system_files/. /

shopt -u nullglob

echo "::endgroup::"

echo "::group:: System Configuration"

systemctl enable podman.socket
systemctl enable brew-setup.service
systemctl enable brew-update.timer
systemctl enable brew-upgrade.timer
systemctl enable NetworkManager.service

# Display manager: greetd + tuigreet (session list comes from wayland-sessions)
mkdir -p /etc/greetd
cat >/etc/greetd/config.toml <<EOF
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --remember-session"
user = "greeter"
EOF
systemctl enable greetd.service

# Audio: pre-enable PipeWire sockets for every user session; wireplumber is
# pulled in by the drop-in below (its unit has no [Install] section)
systemctl --global enable pipewire.socket pipewire-pulse.socket
mkdir -p /etc/systemd/user/pipewire.service.d
cat >/etc/systemd/user/pipewire.service.d/override.conf <<EOF
[Unit]
Wants=wireplumber.service
EOF

echo "::endgroup::"

echo "edward build complete!"

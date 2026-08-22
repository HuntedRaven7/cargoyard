#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# Edward Build Script (Arch base, pacman)
###############################################################################
# Base image: ghcr.io/huntedraven7/arch-bootc (Arch Linux — pacman, not dnf5).
# Desktop: Hyprland + Quickshell.
###############################################################################

# Read build-time settings from /etc/environment if not already in the env
if { [[ -z "${IMAGE_NAME:-}" ]] || [[ -z "${SDDM_USER:-}" ]]; } && [[ -f /etc/environment ]]; then
    # shellcheck disable=SC1091
    . /etc/environment
fi

echo "::group:: pacman state"
grep -n 'multilib\|^Include\|^Server' /etc/pacman.conf /etc/pacman.d/mirrorlist
ls -la /etc/pacman.conf.d/ 2>/dev/null || true
echo "::endgroup::"

echo "::group:: Install Packages"

# Base tooling
BASE_PACKAGES=(
    rsync      # required for the brew overlay step
    podman     # required by the container quadlets in system_files
    flatpak    # required for /usr/share/flatpak/preinstall.d at first boot
    tmux       # required by the default ujust recipes
    gum        # required by the default ujust recipes for interactive prompts
    linux-headers
    git
)


NVIDIA_PACKAGES=(
    nvidia-open-dkms 
    lib32-nvidia-utils
)

DE_PACKAGES=(
    hyprland                    
    quickshell                  
    uwsm                        
    xdg-desktop-portal-hyprland 
    xdg-desktop-portal-gtk      
    xorg-xwayland               
    polkit-gnome                
    sddm                        
    xorg-server                 
    fuzzel                      
    mako                        
    grim                        
    slurp                       
    wl-clipboard                
    hyprpaper                   
    hypridle                    
    hyprlock                    
    pipewire                    
    wireplumber                 
    pipewire-pulse              
    pipewire-alsa               
    networkmanager              
    noto-fonts                  
    noto-fonts-emoji            
    ghostty 
    kitty
    alacritty
    foot
    nautilus
    flatpak
)

GAMING_PACKAGES=(
   steam 
)

pacman -Syu --noconfirm --needed "${BASE_PACKAGES[@]}" "${NVIDIA_PACKAGES[@]}" "${GAMING_PACKAGES[@]}" "${DE_PACKAGES[@]}"

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

# Display manager: SDDM with autologin into the uwsm-managed Hyprland session.
# SDDM_USER comes from the Containerfile ARG (persisted to /etc/environment).
# On manual logout the standard SDDM greeter takes over; xorg-server provides
# its default X11 display server.
mkdir -p /etc/sddm.conf.d
cat >/etc/sddm.conf.d/autologin.conf <<EOF
[Autologin]
User=${SDDM_USER}
Session=hyprland-uwsm.desktop
Relogin=false
EOF
systemctl enable sddm.service

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

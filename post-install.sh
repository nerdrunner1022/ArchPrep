#!/usr/bin/env bash
# =============================================================================
#  post-install.sh — AVTRHQ-UP (nerdrunner @ Lenovo ThinkPad T470)
#  Covers: Repo setup, package installation, service enablement.
# =============================================================================

set -uo pipefail

# -- Colours ------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# -- Logging ------------------------------------------------------------------
LOG_FILE="$HOME/post-install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

log_info()    { echo -e "${CYAN}${BOLD}[INFO]${RESET}  $*"; }
log_ok()      { echo -e "${GREEN}${BOLD}[ OK ]${RESET}  $*"; }
log_warn()    { echo -e "${YELLOW}${BOLD}[WARN]${RESET}  $*"; }
log_error()   { echo -e "${RED}${BOLD}[ERR ]${RESET}  $*"; }
log_section() {
    echo -e "\n${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${CYAN}${BOLD}  $*${RESET}"
    echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
}

# -- Helpers ------------------------------------------------------------------
pkg_install() {
    local label="$1"; shift
    log_info "Installing: ${label}..."
    if yay -S --needed --noconfirm "$@"; then
        log_ok "${label} done."
    else
        log_warn "${label} — one or more packages failed. Check $LOG_FILE."
    fi
}

svc_enable()      { sudo systemctl enable --now "$1" &>/dev/null \
                        && log_ok "Enabled: $1" \
                        || log_warn "Failed to enable: $1"; }
svc_enable_user() { systemctl --user enable --now "$1" &>/dev/null \
                        && log_ok "Enabled (user): $1" \
                        || log_warn "Failed to enable (user): $1"; }
svc_mask()        { sudo systemctl mask "$1" &>/dev/null \
                        && log_ok "Masked: $1" \
                        || log_warn "Failed to mask: $1"; }

# =============================================================================
#  PRE-FLIGHT
# =============================================================================
log_section "Pre-flight Checks"

[[ "$EUID" -eq 0 ]] && { log_error "Do not run as root."; exit 1; }
sudo -v || { log_error "sudo failed. Are you in the wheel group?"; exit 1; }
ping -c 1 -W 3 archlinux.org &>/dev/null \
    || { log_error "No internet. Connect first: nmcli device wifi connect \"SSID\" password \"PASS\""; exit 1; }

log_ok "All checks passed. Log: $LOG_FILE"
log_warn "This will take several hours. Keep the machine plugged in."
echo
read -rp "$(echo -e "${BOLD}Start? [y/N]: ${RESET}")" confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { log_info "Aborted."; exit 0; }

# =============================================================================
#  PART 13 — Repo Setup & yay
# =============================================================================
log_section "Part 13 — Repos & yay"

# ParallelDownloads = 3 (appropriate for ~3.84 Mbps)
sudo sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 3/' /etc/pacman.conf
log_ok "ParallelDownloads set to 3."

# multilib
if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    sudo sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' /etc/pacman.conf
    log_ok "multilib enabled."
else
    log_ok "multilib already enabled."
fi

# Chaotic AUR
if ! grep -q "^\[chaotic-aur\]" /etc/pacman.conf; then
    sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
    sudo pacman-key --lsign-key 3056513887B78AEB
    sudo pacman -U --noconfirm \
        'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'
    sudo pacman -U --noconfirm \
        'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
    printf '\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist\n' \
        | sudo tee -a /etc/pacman.conf > /dev/null
    log_ok "Chaotic AUR added."
else
    log_ok "Chaotic AUR already configured."
fi

sudo pacman -Sy
log_ok "Package databases synced."

# yay
if ! command -v yay &>/dev/null; then
    log_info "Building yay..."
    sudo pacman -S --needed --noconfirm git base-devel
    git clone https://aur.archlinux.org/yay.git /tmp/yay-build
    (cd /tmp/yay-build && makepkg -si --noconfirm)
    rm -rf /tmp/yay-build
    log_ok "yay installed."
else
    log_ok "yay already installed."
fi

# =============================================================================
#  PART 14 — Package Installation
# =============================================================================
log_section "Part 14 — Package Installation"
log_warn "Estimated time at 3.84 Mbps: 3–4 hours. Step away and check in occasionally."

pkg_install "Display Server & Intel Graphics" \
    xorg-server xorg-xinit xorg-xrandr xorg-xset xorg-xprop \
    xf86-video-intel vulkan-intel intel-media-driver libva-intel-driver

pkg_install "PipeWire Audio Stack" \
    pipewire wireplumber pipewire-pulse pipewire-alsa pavucontrol

pkg_install "Bluetooth" \
    bluez bluez-utils blueman bluetui

pkg_install "Networking & SSH" \
    openssh wget curl iputils

log_info "Installing ThinkPad packages — DKMS builds will take ~15 min after download..."
pkg_install "ThinkPad Power & Hardware" \
    tlp tlp-rdw thermald acpi_call-dkms tp_smapi-dkms

pkg_install "Display Manager, WMs & DEs" \
    sddm \
    hyprland hypridle hyprlock hyprpolkitagent hyprshot hyprsunset \
    xdg-desktop-portal-hyprland xdg-desktop-portal xdg-desktop-portal-gtk \
    i3-wm polybar picom dunst feh arandr network-manager-applet polkit-gnome \
    cinnamon \
    rofi rofimoji waypaper

pkg_install "Wayland Utilities" \
    waybar swaync wl-clipboard cliphist wlogout wf-recorder \
    brightnessctl qt5-wayland qt5ct qt6-wayland qt6ct \
    kvantum nwg-look lxappearance xdg-user-dirs emote

pkg_install "X11 Utilities" \
    xclip touchegg gnome-screenshot

pkg_install "Terminals & Editors" \
    kitty wezterm neovim gvim xed

pkg_install "File Management & Archives" \
    nemo nemo-engrampa engrampa p7zip zip unzip unrar udiskie yazi rsync

log_info "Installing fonts — ttf-ms-fonts fetches from Microsoft servers, may be slow..."
pkg_install "Fonts" \
    ttf-ms-fonts ttf-nerd-fonts-symbols ttf-nerd-fonts-symbols-common \
    ttf-nerd-fonts-symbols-mono noto-fonts noto-fonts-emoji ttf-liberation

pkg_install "Theming & Appearance" \
    archlinux-wallpaper bibata-cursor-theme awww resvg gtk-engine-murrine

pkg_install "Media & Codecs" \
    vlc vivaldi-ffmpeg-codecs mpd mpc rmpc cava obs-studio \
    imagemagick ffmpeg gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-libav

log_info "Installing browsers — ~1.2 GB combined, expect ~45 min at your speed..."
pkg_install "Browsers" \
    brave-bin vivaldi zen-browser-bin floorp-bin

log_info "Installing office tools — onlyoffice-bin is ~400 MB..."
pkg_install "Productivity & Office" \
    onlyoffice-bin okular xreader zotero inkscape gimp \
    galculator nomacs gnome-system-monitor

pkg_install "System Tools & Security" \
    btop fastfetch man-db timeshift apparmor gnome-keyring seahorse \
    reflector pacman-contrib flatpak grub-btrfs inotify-tools

pkg_install "Development Tools" \
    nodejs-lts-krypton npm composer php xampp visual-studio-code-bin

pkg_install "Shell & Prompt" \
    zsh zsh-autocomplete zsh-autosuggestions zsh-completions \
    zsh-history-substring-search zsh-syntax-highlighting starship

pkg_install "Remaining AUR Packages" \
    gazelle-tui

log_ok "All package groups done."

# =============================================================================
#  PART 15 — Service Enablement
# =============================================================================
log_section "Part 15 — Service Enablement"

log_info "Enabling PipeWire (user services)..."
svc_enable_user pipewire
svc_enable_user pipewire-pulse
svc_enable_user wireplumber
svc_enable_user mpd

svc_enable sddm
svc_enable bluetooth

log_info "Masking systemd-rfkill (conflicts with TLP)..."
svc_mask systemd-rfkill.service
svc_mask systemd-rfkill.socket
svc_enable tlp
svc_enable thermald
svc_enable NetworkManager-dispatcher

svc_enable apparmor
svc_enable grub-btrfsd
svc_enable sshd
svc_enable touchegg
svc_enable fstrim.timer

log_info "Applying ThinkPad battery thresholds (40–80%)..."
sudo sed -i 's/^#\?START_CHARGE_THRESH_BAT0=.*/START_CHARGE_THRESH_BAT0=40/' /etc/tlp.conf
sudo sed -i 's/^#\?STOP_CHARGE_THRESH_BAT0=.*/STOP_CHARGE_THRESH_BAT0=80/' /etc/tlp.conf
sudo systemctl restart tlp
log_ok "Battery thresholds applied."

# =============================================================================
#  DONE
# =============================================================================
echo
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${GREEN}${BOLD}  All done. Reboot and you'll land in SDDM.${RESET}"
echo -e "${GREEN}${BOLD}  Any failures are in: $LOG_FILE${RESET}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo

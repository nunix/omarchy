#!/usr/bin/env bash
# ==============================================================================
# Omatomic Bootstrap Installer
# Port of Omarchy (Quattro v4) for openSUSE MicroOS / Aeon (Immutable Root)
# Designed for Transactional Systems, Flatpak / Container Workflows & Rootless Run
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${BLUE}[omatomic]${NC} $*"; }
info() { echo -e "${GREEN}[info]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }
err() { echo -e "${RED}[error]${NC} $*" >&2; }

# --- 1. Pre-flight & MicroOS Detection ---
log "Starting Omatomic installer for openSUSE MicroOS / Aeon (Quattro)..."

if [[ $EUID -eq 0 ]]; then
    err "Do NOT run this script directly as root. Run as your regular user."
    exit 1
fi

IS_MICROOS=false
if grep -qE "MicroOS|Aeon" /etc/os-release 2>/dev/null || command -v transactional-update >/dev/null 2>&1; then
    IS_MICROOS=true
    info "Detected openSUSE MicroOS / Aeon transactional environment."
fi

# Ensure user directories
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.local/share"
mkdir -p "$HOME/.config"
mkdir -p "$HOME/.cache"

# Add ~/.local/bin to PATH for this script session
export PATH="$HOME/.local/bin:$PATH"

# Delta host packages needed for full desktop functionality
HOST_DELTA_PACKAGES=(
    hyprland waybar rofi-wayland foot kitty ghostty btop fastfetch
    nautilus python313-nautilus imv loupe swayimg
    playerctl pavucontrol pipewire wireplumber socat bc ripgrep fd fzf bat eza
    grim slurp wl-clipboard cliphist swappy wlogout swayidle swaylock wlsunset
    ImageMagick vips-tools libvips42 NetworkManager
    libQt6Core6 starship zoxide noctalia-qs
    sddm-qt6 sddm-config-wayland wayvnc uwsm xdg-terminal-exec
    hypridle hyprlock hyprsunset hyprshot
    inotify-tools libxkbcommon-tools udiskie wtype jq lua54
    nerdfonts-symbolsonly-fonts fontawesome-fonts fira-code-fonts google-noto-fonts
)

check_missing_host_packages() {
    local missing=()
    for pkg in "${HOST_DELTA_PACKAGES[@]}"; do
        if ! rpm -q "$pkg" &>/dev/null; then
            missing+=("$pkg")
        fi
    done
    echo "${missing[@]}"
}

MISSING_PACKAGES=($(check_missing_host_packages))

if (( ${#MISSING_PACKAGES[@]} > 0 )); then
    warn "The following host packages are not yet installed on this system:"
    echo "  ${MISSING_PACKAGES[*]}"
    echo ""
    if [[ "$IS_MICROOS" == "true" ]]; then
        info "To install them in a single transaction on MicroOS, run:"
        echo -e "${CYAN}sudo transactional-update -c pkg in --no-recommends ${MISSING_PACKAGES[*]}${NC}"
        echo -e "${CYAN}sudo reboot${NC}"
        echo ""
        if [[ "${1:-}" == "--install-host-deps" ]]; then
            log "Running transactional-update for missing delta packages..."
            sudo transactional-update -c pkg in --no-recommends "${MISSING_PACKAGES[@]}"
            info "Transactional update staged. Please reboot after this script finishes."
        fi
    else
        if sudo -v &>/dev/null 2>&1; then
            info "Attempting to install missing delta packages via zypper..."
            sudo zypper --non-interactive in --no-recommends "${MISSING_PACKAGES[@]}" || true
        fi
    fi
else
    info "All required desktop host packages are already installed."
fi

# --- 2. Install Rootless Userland Utilities (gum, dua, mise) ---
log "Installing userland binaries to ~/.local/bin..."

# gum
if ! command -v gum >/dev/null 2>&1; then
    info "Installing gum binary (v0.17.0)..."
    curl -fsSL "https://github.com/charmbracelet/gum/releases/download/v0.17.0/gum_0.17.0_Linux_x86_64.tar.gz" | tar -xz -C "$HOME/.local/bin/" --wildcards '*/gum' --strip-components=1
    chmod +x "$HOME/.local/bin/gum"
fi

# dua
if ! command -v dua >/dev/null 2>&1; then
    info "Installing dua-cli binary (v2.44.0)..."
    curl -fsSL "https://github.com/Byron/dua-cli/releases/download/v2.44.0/dua-v2.44.0-x86_64-unknown-linux-musl.tar.gz" | tar -xz -C "$HOME/.local/bin/" --wildcards '*/dua' --strip-components=1
    chmod +x "$HOME/.local/bin/dua"
fi

# mise
if ! command -v mise >/dev/null 2>&1; then
    info "Installing mise..."
    curl -fsSL https://mise.jdx.dev/mise-latest-linux-x64 -o "$HOME/.local/bin/mise"
    chmod +x "$HOME/.local/bin/mise"
fi

# tensaku stub
if ! command -v tensaku >/dev/null 2>&1; then
    cat << 'EOF' > "$HOME/.local/bin/tensaku"
#!/bin/bash
exit 0
EOF
    chmod +x "$HOME/.local/bin/tensaku"
fi

# lua symlink if host has lua5.4 but no bare lua binary
if ! command -v lua >/dev/null 2>&1; then
    if command -v lua5.4 >/dev/null 2>&1; then
        ln -sf "$(command -v lua5.4)" "$HOME/.local/bin/lua"
    elif command -v lua5.3 >/dev/null 2>&1; then
        ln -sf "$(command -v lua5.3)" "$HOME/.local/bin/lua"
    fi
fi

# --- 3. Deploy Userland Pacman & Arch Compatibility Shims ---
log "Deploying userland Arch Linux / Pacman compatibility shims to ~/.local/bin..."

cat << 'EOF' > "$HOME/.local/bin/pacman"
#!/usr/bin/env bash
# ~/.local/bin/pacman - Rootless/MicroOS compatibility shim for Omarchy

cmd="${1:-}"
shift || true

translate_pkg() {
    local p="$1"
    case "$p" in
        networkmanager) echo "NetworkManager" ;;
        dua-cli) echo "dua" ;;
        libvips) echo "libvips42" ;;
        libvips-tools) echo "vips-tools" ;;
        libfprint) echo "libfprint-2-2" ;;
        lsp-plugins-lv2) echo "lsp-plugins" ;;
        libqt6core6) echo "libQt6Core6" ;;
        rofi) echo "rofi-wayland" ;;
        imagemagick) echo "ImageMagick" ;;
        noto-fonts) echo "google-noto-fonts" ;;
        noto-fonts-cjk) echo "google-noto-sans-cjk-fonts" ;;
        noto-fonts-emoji) echo "google-noto-coloremoji-fonts" ;;
        nautilus-python) echo "python313-nautilus" ;;
        quickshell|qs) echo "noctalia-qs" ;;
        *) echo "$p" ;;
    esac
}

case "$cmd" in
    -V|--version)
        echo "Pacman v6.1.0 - openSUSE MicroOS Shim (Omatomic)"
        exit 0
        ;;
    -Slq|-Sql|-Sl)
        zypper -q se -t package 2>/dev/null | awk -F'|' 'NR>2 {gsub(/^[ \t]+|[ \t]+$/, "", $2); if (length($2)>0) print $2}' | sort -u
        ;;
    -Qq|-Qe|-Qeq|-Qqe)
        rpm -qa --qf '%{NAME}\n' | sort -u
        ;;
    -Q)
        if [ $# -eq 0 ]; then
            rpm -qa --qf '%{NAME} %{VERSION}-%{RELEASE}\n' | sort -u
        else
            for p in "$@"; do
                tp=$(translate_pkg "$p")
                rpm -q "$tp" >/dev/null 2>&1 || exit 1
            done
            exit 0
        fi
        ;;
    -Qi)
        for p in "$@"; do
            tp=$(translate_pkg "$p")
            rpm -qi "$tp" 2>/dev/null
        done
        ;;
    -Si|-Sii)
        for p in "$@"; do
            tp=$(translate_pkg "$p")
            zypper --non-interactive info "$tp" 2>/dev/null
        done
        ;;
    -S)
        pkgs=()
        for arg in "$@"; do
            [[ "$arg" == -* ]] && continue
            tp=$(translate_pkg "$arg")
            pkgs+=("$tp")
        done
        if [ ${#pkgs[@]} -gt 0 ]; then
            if command -v transactional-update >/dev/null 2>&1; then
                sudo transactional-update -c pkg in --no-recommends "${pkgs[@]}" || true
            else
                sudo zypper --non-interactive in --no-recommends "${pkgs[@]}" || true
            fi
        fi
        ;;
    -R|-Rs|-Rns)
        pkgs=()
        for arg in "$@"; do
            [[ "$arg" == -* ]] && continue
            tp=$(translate_pkg "$arg")
            pkgs+=("$tp")
        done
        if [ ${#pkgs[@]} -gt 0 ]; then
            if command -v transactional-update >/dev/null 2>&1; then
                sudo transactional-update -c pkg rm -u "${pkgs[@]}" || true
            else
                sudo zypper --non-interactive rm -u "${pkgs[@]}" || true
            fi
        fi
        ;;
    *)
        exit 0
        ;;
esac
EOF
chmod +x "$HOME/.local/bin/pacman"

cat << 'EOF' > "$HOME/.local/bin/paccache"
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$HOME/.local/bin/paccache"

cat << 'EOF' > "$HOME/.local/bin/pacman-key"
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$HOME/.local/bin/pacman-key"

cat << 'EOF' > "$HOME/.local/bin/checkupdates"
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$HOME/.local/bin/checkupdates"

cat << 'EOF' > "$HOME/.local/bin/yay"
#!/usr/bin/env bash
exec "$HOME/.local/bin/pacman" "$@"
EOF
chmod +x "$HOME/.local/bin/yay"

# --- 4. Userland Fonts Installation ---
log "Setting up fonts in ~/.local/share/fonts..."
mkdir -p "$HOME/.local/share/fonts"

if [ ! -f "$HOME/.local/share/fonts/JetBrainsMonoNerdFont-Regular.ttf" ]; then
    info "Downloading Nerd Fonts..."
    TMP_FONTS=$(mktemp -d)
    curl -sL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz | tar -xJ -C "$TMP_FONTS" 2>/dev/null || true
    curl -sL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.tar.xz | tar -xJ -C "$TMP_FONTS" 2>/dev/null || true
    cp "$TMP_FONTS"/*.ttf "$TMP_FONTS"/*.otf "$HOME/.local/share/fonts/" 2>/dev/null || true
    rm -rf "$TMP_FONTS"
fi

# --- 5. Clone or Link Omatomic Repository ---
log "Setting up Omatomic repository in ~/.local/share/omarchy..."

OMARCHY_TARGET="$HOME/.local/share/omarchy"
OMARCHY_REPO="${OMARCHY_REPO:-nunix/omarchy}"
OMARCHY_REF="${OMARCHY_REF:-omaweed}"

if [ -d /usr/share/omarchy ] && [ ! -d "$OMARCHY_TARGET" ]; then
    info "Copying existing /usr/share/omarchy tree to userland..."
    cp -R /usr/share/omarchy "$OMARCHY_TARGET"
elif [ ! -d "$OMARCHY_TARGET" ]; then
    info "Cloning $OMARCHY_REPO ($OMARCHY_REF) into $OMARCHY_TARGET..."
    git clone --branch "$OMARCHY_REF" "https://github.com/${OMARCHY_REPO}.git" "$OMARCHY_TARGET"
else
    info "$OMARCHY_TARGET already exists, pulling latest..."
    git -C "$OMARCHY_TARGET" pull --ff-only 2>/dev/null || true
fi

# Ensure user font is installed
if [ -f "$OMARCHY_TARGET/config/omarchy.ttf" ]; then
    cp "$OMARCHY_TARGET/config/omarchy.ttf" "$HOME/.local/share/fonts/"
fi
fc-cache -f 2>/dev/null || true

# Symlink all Omarchy binaries to ~/.local/bin
log "Symlinking Omarchy binaries to ~/.local/bin..."
for bin in "$OMARCHY_TARGET"/bin/*; do
    [ -f "$bin" ] || continue
    bname=$(basename "$bin")
    ln -sf "$bin" "$HOME/.local/bin/$bname"
done

ln -sf "$HOME/.local/bin/omarchy-update" "$HOME/.local/bin/omatomic-update"

# Shell environment export
mkdir -p "$HOME/.config/environment.d"
echo "OMARCHY_PATH=$OMARCHY_TARGET" > "$HOME/.config/environment.d/10-omarchy.conf"

# Append to bashrc if not present
if ! grep -q "OMARCHY_PATH" "$HOME/.bashrc" 2>/dev/null; then
    cat << EOF >> "$HOME/.bashrc"

# Omatomic / Omarchy user environment
export OMARCHY_PATH="\$HOME/.local/share/omarchy"
export PATH="\$HOME/.local/bin:\$PATH"
[ -r "\$OMARCHY_PATH/default/bash/env-bootstrap" ] && . "\$OMARCHY_PATH/default/bash/env-bootstrap"
[ -f "\$OMARCHY_PATH/default/bash/rc" ] && . "\$OMARCHY_PATH/default/bash/rc"
EOF
fi

# --- 6. Provision User Configuration & Dotfiles ---
log "Provisioning dotfiles to ~/.config..."
mkdir -p "$HOME/.config"
cp -R "$OMARCHY_TARGET"/config/* "$HOME/.config/"

# Setup default applications (Loupe for images/GIFs, Nautilus for files)
mkdir -p "$HOME/.config"
cp -f "$OMARCHY_TARGET/default/applications/mimeapps.list" "$HOME/.config/mimeapps.list" 2>/dev/null || true

# Setup Nautilus Python extensions (LocalSend, Transcode)
mkdir -p "$HOME/.local/share/nautilus-python/extensions"
cp -f "$OMARCHY_TARGET"/default/nautilus-python/extensions/*.py "$HOME/.local/share/nautilus-python/extensions/" 2>/dev/null || true

# Seed migration state
mkdir -p "$HOME/.local/state/omarchy/migrations"
for m in "$OMARCHY_TARGET"/migrations/*.sh; do
    [ -f "$m" ] || continue
    touch "$HOME/.local/state/omarchy/migrations/$(basename "$m")"
done

# Set Omatomic ASCII screensaver branding
mkdir -p "$HOME/.config/omarchy/branding"
cat << 'EOF' > "$HOME/.config/omarchy/branding/screensaver.txt"
   ____  __  ______ _____ ____  __  ___________
  / __ \/  |/  /   |_  __// __ \/  |/  /  _/ ____/
 / / / / /|_/ / /| |/ /  / / / / /|_/ // // /     
/ /_/ / /  / / ___ / /  / /_/ / /  / // // /___   
\____/_/  /_/_/  |/_/   \____/_/  /_/___/\____/   
       openSUSE MicroOS / Immutable Edition
EOF

# Set default theme
export OMARCHY_PATH="$OMARCHY_TARGET"
"$HOME/.local/bin/omarchy-theme-set" "Tokyo Night" 2>/dev/null || true

# --- 7. Polkit & Systemd Optional Host Integration ---
if sudo -v &>/dev/null 2>&1; then
    log "Configuring host Polkit power management rules..."
    sudo mkdir -p /etc/polkit-1/rules.d
    sudo tee /etc/polkit-1/rules.d/10-enable-power.rules >/dev/null << EOF
polkit.addRule(function(action, subject) {
    if ((action.id == "org.freedesktop.login1.reboot" ||
         action.id == "org.freedesktop.login1.reboot-multiple-sessions" ||
         action.id == "org.freedesktop.login1.power-off" ||
         action.id == "org.freedesktop.login1.power-off-multiple-sessions" ||
         action.id == "org.freedesktop.login1.suspend" ||
         action.id == "org.freedesktop.login1.suspend-multiple-sessions" ||
         action.id == "org.freedesktop.login1.hibernate" ||
         action.id == "org.freedesktop.login1.hibernate-multiple-sessions") &&
        (subject.isInGroup("wheel") || subject.isInGroup("sudo") || subject.isInGroup("users") || subject.user == "$USER")) {
        return polkit.Result.YES;
    }
});
EOF
fi

# --- 8. WayVNC User Service ---
mkdir -p "$HOME/.config/systemd/user"
cat << EOF > "$HOME/.config/systemd/user/wayvnc.service"
[Unit]
Description=WayVNC VNC Server for Hyprland
After=graphical-session.target

[Service]
Type=simple
ExecStart=$HOME/.local/bin/wayvnc --render-cursor 0.0.0.0 5900
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload 2>/dev/null || true

log "================================================================="
info "Omatomic bootstrap installation complete!"
info "Everything is deployed cleanly to ~/.local and ~/.config."
info "Log into Hyprland to start your session."
log "================================================================="

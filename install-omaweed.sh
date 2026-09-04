#!/usr/bin/env bash
# ==============================================================================
# Omaweed Bootstrap Installer
# Port of Omarchy (Quattro v4) to openSUSE Tumbleweed
# Designed for Bare-Metal Laptops, VMs, and WSL2 environments
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[omaweed]${NC} $*"; }
info() { echo -e "${GREEN}[info]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }
err() { echo -e "${RED}[error]${NC} $*" >&2; }

# --- 1. Pre-flight Checks ---
log "Starting Omaweed installer for openSUSE Tumbleweed (Quattro)..."

if [[ $EUID -eq 0 ]]; then
    err "Do NOT run this script directly as root. Run as your regular user with sudo privileges."
    exit 1
fi

if ! sudo -v &>/dev/null; then
    err "Current user must have sudo privileges to run the Omaweed bootstrap script."
    exit 1
fi

export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

# --- 2. Resolve Base Conflicts & Install Core Build Tools ---
log "Resolving core packaging conflicts (busybox shims)..."
sudo zypper --non-interactive in --force-resolution which gzip

log "Refreshing openSUSE repositories..."
sudo zypper --non-interactive refresh

log "Installing base development tools and runtime dependencies..."
sudo zypper --non-interactive in --no-recommends \
    git curl wget sudo tar xz jq gcc gcc-c++ make cmake cargo rust zig python3 \
    which gzip xdg-user-dirs fontconfig systemd dbus-1 polkit polkit-gnome \
    qt6-declarative-devel qt6-quickcontrols2-devel meson ninja libpulse-devel \
    gtk4-layer-shell-devel libevdev-devel libinput-devel sassc systemd-devel

log "Installing Hyprland Wayland desktop suite & QuickShell runtime..."
sudo zypper --non-interactive in --no-recommends \
    hyprland waybar rofi-wayland foot kitty ghostty btop fastfetch \
    playerctl pavucontrol pipewire wireplumber socat bc ripgrep fd fzf bat eza \
    grim slurp wl-clipboard cliphist swappy wlogout swayidle swaylock wlsunset \
    ImageMagick vips-tools libvips42 NetworkManager snapper btrfsmaintenance \
    libQt6Core6 qt6-base-devel starship zoxide noctalia-qs \
    sddm-qt6 sddm-qt6-branding-openSUSE sddm-config-wayland xorg-x11-server wayvnc \
    uwsm xdg-terminal-exec hypridle hyprlock hyprsunset hyprshot fcitx5 fcitx5-gtk3 fcitx5-gtk4 fcitx5-qt6 \
    inotify-tools libxkbcommon-tools udiskie wtype tesseract-ocr \
    nerdfonts-symbolsonly-fonts fontawesome-fonts fira-code-fonts google-noto-fonts \
    google-noto-coloremoji-fonts google-noto-sans-cjk-fonts breeze6-cursors || true

# --- 3. Install OPI (OBS Package Installer, AUR replacement for Tumbleweed) ---
log "Installing opi (openSUSE Build Service package finder, replaces AUR/yay)..."
if ! command -v opi >/dev/null 2>&1; then
    sudo zypper --non-interactive in opi 2>/dev/null || {
        warn "opi not in configured repos, building from source (cargo)..."
        BUILD_DIR=$(mktemp -d)
        git clone --depth 1 https://github.com/openSUSE/opi.git "$BUILD_DIR"
        (
            cd "$BUILD_DIR"
            cargo build --release
            sudo install -m 755 target/release/opi /usr/local/bin/opi
        )
        rm -rf "$BUILD_DIR"
    }
fi

# --- 4. Deploy Pacman & Arch Compatibility Shims ---
log "Deploying Arch Linux / Pacman compatibility shims to /usr/bin..."

sudo tee /usr/bin/pacman >/dev/null << 'EOF'
#!/usr/bin/env bash
# /usr/bin/pacman - openSUSE Tumbleweed compatibility shim for Arch Omarchy

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
        quickshell|qs) echo "noctalia-qs" ;;
        *) echo "$p" ;;
    esac
}

case "$cmd" in
    -V|--version)
        echo "Pacman v6.1.0 - openSUSE Tumbleweed Shim (Omaweed)"
        exit 0
        ;;
    -Slq|-Sql|-Sl)
        zypper -q se -t package 2>/dev/null | awk -F'|' 'NR>2 {gsub(/^[ \t]+|[ \t]+$/, "", $2); if (length($2)>0) print $2}' | sort -u
        exit 0
        ;;
    -Sii|-Si|-Ss)
        if [[ "$cmd" == "-Ss" ]]; then
            zypper search "$@"
        else
            zypper info "$@"
        fi
        ;;
    -Qo|-Qqo)
        rpm -qf "$@" 2>/dev/null || true
        ;;
    -Qm|-Qem)
        exit 1
        ;;
    -Q|-Qq|-Qe|-Qdt|-Qi)
        if [[ "$cmd" == "-Qq" || "$cmd" == "-Q" || "$cmd" == "-Qe" ]]; then
            if [[ $# -eq 0 ]]; then
                rpm -qa --qf "%{NAME}\n"
            else
                for p in "$@"; do
                    [[ "$p" == -* ]] && continue
                    tp=$(translate_pkg "$p")
                    if [[ "$p" == *"keyring"* ]]; then
                        continue
                    fi
                    if rpm -q "$p" >/dev/null 2>&1 || rpm -q "$tp" >/dev/null 2>&1; then
                        continue
                    fi
                    base="${p%-cli}"
                    base="${base%-git}"
                    if command -v "$p" >/dev/null 2>&1 || command -v "$tp" >/dev/null 2>&1 || command -v "$base" >/dev/null 2>&1; then
                        continue
                    fi
                    exit 1
                done
                exit 0
            fi
        elif [[ "$cmd" == "-Qi" ]]; then
            rpm -qi "$@"
        elif [[ "$cmd" == "-Qdt" ]]; then
            zypper packages --unneeded 2>/dev/null | awk -F'|' '/^i/ {gsub(/ /, "", $3); print $3}'
        else
            rpm -qa
        fi
        ;;
    -Syu|-Syyu)
        sudo zypper --non-interactive dup --no-allow-vendor-change -l
        ;;
    -S|-Sy)
        pkgs=()
        for arg in "$@"; do
            [[ "$arg" == --* ]] && continue
            [[ "$arg" == -* ]] && continue
            [[ "$arg" == */* ]] && continue
            tp=$(translate_pkg "$arg")
            if [[ "$arg" == *"keyring"* ]]; then
                continue
            fi
            if command -v "$arg" >/dev/null 2>&1 || command -v "$tp" >/dev/null 2>&1 || command -v "${arg%-cli}" >/dev/null 2>&1; then
                continue
            fi
            pkgs+=("$tp")
        done
        if [[ ${#pkgs[@]} -gt 0 ]]; then
            sudo zypper --non-interactive in --no-recommends "${pkgs[@]}" || true
        fi
        ;;
    -R|-Rns|-Rdd)
        pkgs=()
        for arg in "$@"; do
            [[ "$arg" == --* ]] && continue
            [[ "$arg" == -* ]] && continue
            tp=$(translate_pkg "$arg")
            pkgs+=("$tp")
        done
        if [[ ${#pkgs[@]} -gt 0 ]]; then
            sudo zypper --non-interactive rm -u "${pkgs[@]}" || true
        fi
        ;;
    *)
        exit 0
        ;;
esac
EOF
sudo chmod +x /usr/bin/pacman

sudo tee /usr/bin/paccache >/dev/null << 'EOF'
#!/usr/bin/env bash
sudo zypper --non-interactive clean -a >/dev/null 2>&1 || true
exit 0
EOF
sudo chmod +x /usr/bin/paccache

sudo tee /usr/bin/pacman-key >/dev/null << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
sudo chmod +x /usr/bin/pacman-key

sudo tee /usr/bin/yay >/dev/null << 'EOF'
#!/usr/bin/env bash
# /usr/bin/yay - openSUSE Tumbleweed OPI shim for Arch AUR calls (Omaweed)
# Real AUR has no Tumbleweed equivalent; opi searches/installs from the
# openSUSE Build Service (OBS), the closest analog for community packages.

# Known AUR -> OBS/opi search-term translations for packages Omarchy installs
# via omarchy-pkg-aur-add (browsers, editors). Unmapped names are tried as-is.
translate_aur_pkg() {
    local p="$1"
    p="${p#aur/}"
    case "$p" in
        google-chrome) echo "google-chrome-stable" ;;
        microsoft-edge-stable-bin) echo "microsoft-edge-stable" ;;
        brave-bin) echo "brave-browser" ;;
        brave-origin-bin) echo "brave-browser" ;;
        zen-browser-bin) echo "zen-browser" ;;
        omarchy-emacs) echo "emacs" ;;
        *) echo "$p" ;;
    esac
}

cmd="${1:-}"
shift || true

case "$cmd" in
    -V|--version)
        echo "yay (Omaweed OPI shim, backed by opi/OBS)"
        exit 0
        ;;
    -S|-Sy)
        for arg in "$@"; do
            [[ "$arg" == --* || "$arg" == -* ]] && continue
            pkg=$(translate_aur_pkg "$arg")
            if command -v opi >/dev/null 2>&1; then
                echo "[omaweed] Searching OBS for '$pkg' (AUR: $arg) via opi..." >&2
                sudo opi "$pkg" || echo "[omaweed] No OBS match for '$pkg'. Install manually." >&2
            else
                echo "[omaweed] opi missing, cannot resolve AUR package '$arg'." >&2
            fi
        done
        exit 0
        ;;
    -Slqa|-Slq|-Sl)
        # AUR full listing has no OBS equivalent; report empty rather than fake data.
        exit 0
        ;;
    -Sua)
        echo "[omaweed] Bulk AUR updates unsupported under the OPI shim; re-run 'yay -S <pkg>' per package." >&2
        exit 0
        ;;
    -Qqe|-Qq|-Q)
        rpm -qa --qf "%{NAME}\n"
        exit 0
        ;;
    -Qi)
        rpm -qi "$@"
        exit 0
        ;;
    -Siia|-Si)
        opi -d "$(translate_aur_pkg "${1:-}")" 2>/dev/null || zypper info "$@"
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
EOF
sudo chmod +x /usr/bin/yay

sudo tee /usr/bin/checkupdates >/dev/null << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
sudo chmod +x /usr/bin/checkupdates

# --- 5. Install Missing Native / Custom Binaries ---
log "Installing specialized tooling (gum, dua, mise, omacalc, ttfx, herdr, SwayOSD)..."

# gum
if ! command -v gum >/dev/null 2>&1; then
    info "Installing gum binary (v0.17.0)..."
    curl -fsSL "https://github.com/charmbracelet/gum/releases/download/v0.17.0/gum_0.17.0_Linux_x86_64.tar.gz" | sudo tar -xz -C /usr/local/bin/ --wildcards '*/gum' --strip-components=1
    sudo chmod +x /usr/local/bin/gum
fi

# dua
if ! command -v dua >/dev/null 2>&1; then
    info "Installing dua-cli binary (v2.44.0)..."
    curl -fsSL "https://github.com/Byron/dua-cli/releases/download/v2.44.0/dua-v2.44.0-x86_64-unknown-linux-musl.tar.gz" | sudo tar -xz -C /usr/local/bin/ --wildcards '*/dua' --strip-components=1
    sudo chmod +x /usr/local/bin/dua
fi

# mise
if ! command -v mise >/dev/null 2>&1; then
    info "Installing mise..."
    curl -fsSL https://mise.jdx.dev/mise-latest-linux-x64 -o /tmp/mise
    sudo install -m 755 /tmp/mise /usr/local/bin/mise
    rm -f /tmp/mise
fi

# tensaku stub
if ! command -v tensaku >/dev/null 2>&1; then
    sudo tee /usr/local/bin/tensaku >/dev/null << 'EOF'
#!/bin/bash
exit 0
EOF
    sudo chmod +x /usr/local/bin/tensaku
fi

# omacalc (Qt6 calculator)
if ! command -v omacalc >/dev/null 2>&1; then
    info "Compiling and installing omacalc..."
    BUILD_DIR=$(mktemp -d)
    git clone --depth 1 https://github.com/omacom/omacalc.git "$BUILD_DIR"
    (
        cd "$BUILD_DIR"
        qmake6 || qmake-qt6 || qmake
        make -j"$(nproc)"
        sudo install -m 755 omacalc /usr/local/bin/omacalc
    )
    rm -rf "$BUILD_DIR"
fi

# ttfx (terminal text effects)
if ! command -v ttfx >/dev/null 2>&1; then
    info "Compiling and installing ttfx..."
    BUILD_DIR=$(mktemp -d)
    git clone --depth 1 https://github.com/omacom/ttfx.git "$BUILD_DIR"
    (
        cd "$BUILD_DIR"
        cargo build --release
        sudo install -m 755 target/release/ttfx /usr/local/bin/ttfx
    )
    rm -rf "$BUILD_DIR"
fi

# herdr (Ghostty VT multiplexer)
if ! command -v herdr >/dev/null 2>&1; then
    info "Compiling and installing herdr..."
    BUILD_DIR=$(mktemp -d)
    git clone --depth 1 https://github.com/omacom/herdr.git "$BUILD_DIR"
    (
        cd "$BUILD_DIR"
        cargo build --release
        sudo install -m 755 target/release/herdr /usr/local/bin/herdr
    )
    rm -rf "$BUILD_DIR"
fi

# swayosd (On-Screen Display for brightness / volume)
if ! command -v swayosd-server >/dev/null 2>&1; then
    info "Compiling and installing SwayOSD..."
    BUILD_DIR=$(mktemp -d)
    git clone --depth 1 https://github.com/ErikReider/SwayOSD.git "$BUILD_DIR"
    (
        cd "$BUILD_DIR"
        meson setup build
        ninja -C build
        sudo ninja -C build install
    )
    rm -rf "$BUILD_DIR"
fi

# Nerd Fonts (JetBrainsMono, CascadiaCode, FiraCode)
if [ ! -d /usr/local/share/fonts/NerdFonts ]; then
    info "Installing Nerd Fonts..."
    sudo mkdir -p /usr/local/share/fonts/NerdFonts
    TMP_FONTS=$(mktemp -d)
    curl -sL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz | tar -xJ -C "$TMP_FONTS" 2>/dev/null || true
    curl -sL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaCode.tar.xz | tar -xJ -C "$TMP_FONTS" 2>/dev/null || true
    curl -sL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.tar.xz | tar -xJ -C "$TMP_FONTS" 2>/dev/null || true
    sudo cp "$TMP_FONTS"/*.ttf "$TMP_FONTS"/*.otf /usr/local/share/fonts/NerdFonts/ 2>/dev/null || true
    rm -rf "$TMP_FONTS"
fi

# Polkit Gnome agent compatibility symlink
sudo mkdir -p /usr/lib/polkit-gnome
if [ -f /usr/libexec/polkit-gnome-authentication-agent-1 ] && [ ! -f /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 ]; then
    sudo ln -sf /usr/libexec/polkit-gnome-authentication-agent-1 /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
fi

# Ensure /usr/bin symlinks exist for sudo secure_path without clobbering existing files
for bin in /usr/local/bin/*; do
    [ -f "$bin" ] || continue
    name=$(basename "$bin")
    if [ ! -e "/usr/bin/$name" ]; then
        sudo ln -sf "$bin" "/usr/bin/$name"
    fi
done

# --- 6. Clone Omarchy Core & Setup Environment ---
log "Setting up Omarchy core repository (/usr/share/omarchy)..."

OMARCHY_REPO="${OMARCHY_REPO:-nunix/omarchy}"
OMARCHY_REF="${OMARCHY_REF:-omaweed}"

if [ ! -d /usr/share/omarchy ]; then
    sudo git clone --branch "$OMARCHY_REF" "https://github.com/${OMARCHY_REPO}.git" /usr/share/omarchy
    sudo chown -R "$USER:$USER" /usr/share/omarchy
else
    info "/usr/share/omarchy already exists, updating..."
    sudo chown -R "$USER:$USER" /usr/share/omarchy
    git -C /usr/share/omarchy pull --ff-only || true
fi

# Export configuration
echo 'export OMARCHY_PATH="/usr/share/omarchy"' | sudo tee /etc/omarchy.conf >/dev/null

# Profile & Bash integration
sudo tee /etc/profile.d/omarchy.sh >/dev/null << 'EOF'
[ -r /usr/share/omarchy/default/bash/env-bootstrap ] && . /usr/share/omarchy/default/bash/env-bootstrap
EOF

sudo tee /etc/bash.bashrc.local >/dev/null << 'EOF'
[ -f /usr/share/omarchy/default/bash/rc ] && . /usr/share/omarchy/default/bash/rc
EOF

# Link Omarchy binaries to PATH
log "Symlinking Omarchy binaries to /usr/local/bin and /usr/bin..."
for f in /usr/share/omarchy/bin/*; do
    [ -f "$f" ] || continue
    fname=$(basename "$f")
    sudo ln -sf "$f" "/usr/local/bin/$fname"
    if [ ! -e "/usr/bin/$fname" ] || [ -L "/usr/bin/$fname" ]; then
        sudo ln -sf "$f" "/usr/bin/$fname"
    fi
done
sudo ln -sf /usr/local/bin/omarchy-update /usr/local/bin/omaweed-update
sudo ln -sf /usr/local/bin/omarchy-update /usr/bin/omaweed-update

# Setup local share symlinks for root and user
mkdir -p "$HOME/.local/share"
ln -sfn /usr/share/omarchy "$HOME/.local/share/omarchy"
sudo mkdir -p /root/.local/share
sudo ln -sfn /usr/share/omarchy /root/.local/share/omarchy

# --- 7. Polkit Rules for Power Management ---
log "Configuring Polkit power management rules..."
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

# --- 8. Apply openSUSE Compatibility Patches ---
log "Applying compatibility patches to Omarchy tree..."

# 8.1 Snapper non-Btrfs guard
if [ -f /usr/share/omarchy/install/config/snapper.sh ]; then
    sed -i 's/sudo snapper --no-dbus -c root create-config \/ 2>\/dev\/null/sudo snapper --no-dbus -c root create-config \/ 2>\/dev\/null || true/' /usr/share/omarchy/install/config/snapper.sh
fi

# 8.2 Bluetooth rfkill guard
if [ -f /usr/share/omarchy/bin/omarchy-bluetooth-power ]; then
    sed -i 's/rfkill unblock bluetooth/command -v rfkill >\/dev\/null \&\& [ -e \/dev\/rfkill ] \&\& rfkill unblock bluetooth || true/' /usr/share/omarchy/bin/omarchy-bluetooth-power
    sed -i 's/rfkill block bluetooth/command -v rfkill >\/dev\/null \&\& [ -e \/dev\/rfkill ] \&\& rfkill block bluetooth || true/' /usr/share/omarchy/bin/omarchy-bluetooth-power
fi

# 8.3 Update scripts OMARCHY_PATH guards across all scripts
python3 -c '
import glob, os
for path in glob.glob("/usr/share/omarchy/bin/*"):
    if not os.path.isfile(path): continue
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()
        if not lines or not lines[0].startswith("#!"): continue
        if any("OMARCHY_PATH:=" in line for line in lines[:5]): continue
        lines.insert(1, ": \"${OMARCHY_PATH:=/usr/share/omarchy}\"\n")
        with open("/tmp/patched_bin", "w", encoding="utf-8") as f:
            f.writelines(lines)
        os.system(f"sudo cp /tmp/patched_bin \"{path}\" && sudo chmod +x \"{path}\"")
    except Exception:
        pass
'
rm -f /tmp/patched_bin 2>/dev/null || true

# 8.4 Update restart WSL2 and non-interactive guards
if [ -f /usr/share/omarchy/bin/omarchy-update-restart ]; then
    if ! grep -q 'grep -qi microsoft /proc/version' /usr/share/omarchy/bin/omarchy-update-restart; then
        sed -i '/kernel_updated=true/a if grep -qi microsoft /proc/version 2>/dev/null; then kernel_updated=false; fi' /usr/share/omarchy/bin/omarchy-update-restart
    fi
fi

# 8.5 Migration 1785608166 systemd-resolved guard
MIGRATION_RESOLVED="/usr/share/omarchy/migrations/1785608166.sh"
if [ -f "$MIGRATION_RESOLVED" ]; then
    sed -i 's/sudo systemctl restart systemd-resolved.service/if systemctl is-active --quiet systemd-resolved.service 2>\/dev\/null; then sudo systemctl restart systemd-resolved.service; fi/' "$MIGRATION_RESOLVED"
fi

# 8.6 Rebrand omarchy-update to Omaweed
if [ -f /usr/share/omarchy/bin/omarchy-update ]; then
    sed -i 's/header "Updating Omarchy"/header "Updating Omaweed (Tumbleweed)"/' /usr/share/omarchy/bin/omarchy-update
    sed -i 's/Omarchy has been updated/Omaweed has been updated/' /usr/share/omarchy/bin/omarchy-update
fi

# 8.7 Omarchy Quattro Shell IPC & Dispatcher compatibility
if [ -f /usr/share/omarchy/bin/omarchy-shell ]; then
    sudo sed -i 's/qs ipc -n -p/qs ipc -n --any-display -p/g' /usr/share/omarchy/bin/omarchy-shell
fi

if [ -f /usr/share/omarchy/bin/omarchy-restart-shell ]; then
    sudo sed -i 's|hyprctl dispatch .hl.dsp.exec_cmd("omarchy-launch-shell"). >/dev/null|hyprctl dispatch exec omarchy-launch-shell >/dev/null 2>\&1|g' /usr/share/omarchy/bin/omarchy-restart-shell
fi

# 8.8 AUR reachability check -> OBS reachability (opi backend, not aur.archlinux.org)
if [ -f /usr/share/omarchy/bin/omarchy-pkg-aur-accessible ]; then
    sudo sed -i 's|"https://aur.archlinux.org/rpc/?v=5\&type=info\&arg=base"|"https://api.opensuse.org/public/build/openSUSE:Factory/standard/x86_64/opi"|' /usr/share/omarchy/bin/omarchy-pkg-aur-accessible
fi

# 8.9 Drop desktop AI apps with no Tumbleweed/OBS equivalent (Arch-binary-only
# packages: ChatGPT Desktop, Hermes Desktop app, Grok Bot, LM Studio, Ollama,
# T3 Code). CLI agents (claude, pi, hermes CLI, codex, etc.) are unaffected --
# those install through mise, not pacman/AUR, and stay fully supported.
log "Removing unsupported desktop AI app menu entries (no OBS/RPM equivalent)..."
MENU_FILE="/usr/share/omarchy/default/omarchy/omarchy-menu.jsonc"
if [ -f "$MENU_FILE" ]; then
    sudo sed -i -E '/"(install|remove)\.ai\.(chatgpt|grok-bot|hermes|lm-studio|ollama|t3-code)":/d' "$MENU_FILE"
fi
for f in omarchy-install-ai-chatgpt omarchy-install-ai-hermes omarchy-remove-ai-chatgpt omarchy-remove-ai-grok-bot omarchy-remove-ai-hermes omarchy-remove-ai-lm-studio omarchy-remove-ai-ollama omarchy-remove-ai-t3-code; do
    fpath="/usr/share/omarchy/bin/$f"
    if [ -f "$fpath" ]; then
        sudo tee "$fpath" >/dev/null << 'EOF'
#!/bin/bash
echo "$(basename "$0") is unsupported on Omaweed (openSUSE Tumbleweed): it packages an" >&2
echo "Arch-binary-only app with no OBS/RPM equivalent. Removed from the Install/Remove > AI menu." >&2
exit 1
EOF
        sudo chmod +x "$fpath"
    fi
done

# --- 9. Display Manager & Desktop Service Configuration ---
log "Configuring SDDM display manager and system services..."
sudo mkdir -p /etc/sddm.conf.d
cat << EOF | sudo tee /etc/sddm.conf.d/autologin.conf >/dev/null
[Autologin]
User=$USER
Session=hyprland.desktop

[Theme]
Current=breeze
EOF

if [ -f /etc/sysconfig/displaymanager ]; then
    sudo sed -i 's/DISPLAYMANAGER=".*"/DISPLAYMANAGER="sddm"/' /etc/sysconfig/displaymanager 2>/dev/null || true
fi
sudo systemctl enable -f sddm.service 2>/dev/null || true
sudo systemctl enable NetworkManager.service 2>/dev/null || true
sudo systemctl enable bluetooth.service 2>/dev/null || true
sudo systemctl enable sshd.service 2>/dev/null || true
sudo usermod -aG wheel,video,audio,input,render "$USER" 2>/dev/null || true

# --- 10. Provision User & Initialize State ---
log "Provisioning user dotfiles, fonts, and runtime services..."
mkdir -p "$HOME/.config"
cp -R /usr/share/omarchy/config/* "$HOME/.config/"

# Remove legacy v3 conf files in ~/.config/hypr to ensure hyprland.lua takes effect
rm -f "$HOME/.config/hypr/hyprland.conf" "$HOME/.config/hypr/bindings.conf" "$HOME/.config/hypr/input.conf" "$HOME/.config/hypr/looknfeel.conf" "$HOME/.config/hypr/autostart.conf" 2>/dev/null || true

# Setup fonts & cache
mkdir -p "$HOME/.local/share/fonts"
cp /usr/share/omarchy/config/omarchy.ttf "$HOME/.local/share/fonts/" 2>/dev/null || true
sudo cp /usr/share/omarchy/config/omarchy.ttf /usr/local/share/fonts/ 2>/dev/null || true
fc-cache -f 2>/dev/null || true
sudo fc-cache -f 2>/dev/null || true

# Seed initial migration state
mkdir -p "$HOME/.local/state/omarchy/migrations"
for m in /usr/share/omarchy/migrations/*.sh; do
    [ -f "$m" ] || continue
    touch "$HOME/.local/state/omarchy/migrations/$(basename "$m")"
done

# Set Omaweed ASCII branding
mkdir -p "$HOME/.config/omarchy/branding"
cat << 'EOF' > "$HOME/.config/omarchy/branding/screensaver.txt"
   ____  __  ______ _      _____________  ____ 
  / __ \/  |/  /   | | /| / / ____/ ____/ __ \
 / / / / /|_/ / /| | |/ |/ / __/ / __/ / / / /
/ /_/ / /  / / ___ | /| / / /___/ /___/ /_/ / 
\____/_/  /_/_/  |_|/_/|/_____/_____/_____/  
           openSUSE Tumbleweed Edition
EOF

# Set default theme
export OMARCHY_PATH=/usr/share/omarchy
omarchy-theme-set "Tokyo Night" 2>/dev/null || true

# --- 11. Configure WayVNC Remote Management ---
log "Configuring WayVNC remote management service..."
sudo tee /usr/local/bin/wayvnc-autostart >/dev/null << 'EOF'
#!/usr/bin/env bash
for i in {1..30}; do
    SOCKET=$(find "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" -name "wayland-*" 2>/dev/null | head -n1)
    if [ -n "$SOCKET" ]; then
        export WAYLAND_DISPLAY=$(basename "$SOCKET")
        exec /usr/bin/wayvnc --render-cursor 0.0.0.0 5900
    fi
    sleep 1
done
EOF
sudo chmod +x /usr/local/bin/wayvnc-autostart

mkdir -p "$HOME/.config/systemd/user"
cat << 'EOF' > "$HOME/.config/systemd/user/wayvnc.service"
[Unit]
Description=WayVNC VNC Server for Hyprland
After=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/local/bin/wayvnc-autostart
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable wayvnc.service 2>/dev/null || true

log "================================================================="
info "Omaweed bootstrap installation complete (Quattro v4)!"
info "System will now reboot into your Hyprland desktop."
log "================================================================="
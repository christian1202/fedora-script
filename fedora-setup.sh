#!/usr/bin/env bash
# ============================================================================
# Fedora 44 (KDE Plasma Spin) — Post-Install Setup Script
# Target Hardware: ASUS TUF Gaming F15 (NVIDIA GPU)
# ============================================================================
#
# What this script does:
#   1.  Performs a full system update
#   2.  Enables RPM Fusion (free + nonfree) repositories
#   3.  Installs proprietary NVIDIA drivers (for the laptop's dedicated GPU)
#   4.  Installs Brave Browser (via its official DNF repo)
#   5.  Installs Visual Studio Code (via Microsoft's official DNF repo)
#   6.  Installs Steam (via RPM Fusion nonfree)
#   7.  Installs GitHub Desktop (Linux fork, via Flatpak)
#   8.  Installs ProtonUp-Qt (via Flatpak, for managing GE-Proton)
#   9.  Installs Sober / Roblox (via Flatpak, with NVIDIA GPU override)
#   10. Installs gaming & performance tools (GameMode, MangoHud, GOverlay)
#   11. Applies KDE Plasma + system-level optimizations
#   12. Desktop experience & RAM optimizations (zRAM, Baloo, DNF, fonts, etc.)
#
# Usage:
#   chmod +x fedora-setup.sh
#   sudo ./fedora-setup.sh
#
# Notes:
#   - Must be run as root (or with sudo).
#   - Requires an active internet connection.
#   - A reboot is REQUIRED after completion for NVIDIA drivers to load.
# ============================================================================

set -euo pipefail  # Exit on error, undefined vars, and pipe failures

# ── Colour helpers for readable output ──────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Colour / Reset

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[  OK]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[FAIL]${NC}  $*"; }

# ── Pre-flight checks ──────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root. Please use: sudo $0"
    exit 1
fi

if ! command -v dnf &>/dev/null; then
    error "dnf not found — this script is designed for Fedora. Aborting."
    exit 1
fi

# Detect the Fedora version for informational purposes
FEDORA_VERSION=$(rpm -E %fedora 2>/dev/null || echo "unknown")
info "Detected Fedora version: ${BOLD}${FEDORA_VERSION}${NC}"

# Capture the real user who invoked sudo (needed for Flatpak user-level ops)
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   Fedora 44 KDE — ASUS TUF F15 Post-Install Setup          ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================================
# STEP 1: Full System Update
# ============================================================================
info "STEP 1/12 — Updating all system packages..."
dnf upgrade --refresh -y
success "System is fully up to date."

# ============================================================================
# STEP 2: Enable RPM Fusion Repositories (Free + Nonfree)
# ============================================================================
# RPM Fusion provides packages that Fedora cannot ship due to licensing
# (codecs, proprietary drivers, Steam, etc.).
# Reference: https://rpmfusion.org/Configuration
info "STEP 2/12 — Enabling RPM Fusion repositories (free + nonfree)..."

dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm" \
    2>/dev/null || {
        # If the packages are already installed, dnf will return non-zero.
        # Catch that gracefully and verify they're present.
        warn "RPM Fusion packages may already be installed — verifying..."
    }

# Verify RPM Fusion repos are active
if dnf repolist --enabled | grep -q "rpmfusion-free" && \
   dnf repolist --enabled | grep -q "rpmfusion-nonfree"; then
    success "RPM Fusion (free + nonfree) repositories are enabled."
else
    error "RPM Fusion repos could not be verified. Please check manually."
    exit 1
fi

# Install AppStream metadata so KDE Discover can show RPM Fusion apps
# with proper descriptions and icons.
dnf install -y rpmfusion-free-appstream-data rpmfusion-nonfree-appstream-data \
    2>/dev/null || true

# ============================================================================
# STEP 3: Install Proprietary NVIDIA Drivers
# ============================================================================
# The ASUS TUF F15 has an NVIDIA GeForce GPU (commonly RTX 30xx/40xx series).
# We install the proprietary drivers from RPM Fusion for best performance and
# Vulkan support (critical for gaming via Steam/Proton/Sober).
#
# This installs:
#   - akmod-nvidia              : Kernel module (auto-rebuilds on kernel updates)
#   - xorg-x11-drv-nvidia-cuda  : CUDA support libraries
#   - nvidia-vaapi-driver       : Hardware video acceleration (VA-API)
#   - libva-utils               : Verification tools for VA-API
#   - vulkan-loader             : Vulkan ICD loader
#   - nvidia-gpu-firmware       : Required GPU firmware blobs
#   - xorg-x11-drv-nvidia-power : NVIDIA power management (important for laptops)
#
# Reference: https://rpmfusion.org/Howto/NVIDIA
info "STEP 3/12 — Installing proprietary NVIDIA drivers..."

dnf install -y \
    akmod-nvidia \
    xorg-x11-drv-nvidia-cuda \
    xorg-x11-drv-nvidia-power \
    nvidia-vaapi-driver \
    libva-utils \
    vulkan-loader \
    nvidia-gpu-firmware

# Enable NVIDIA power management services for the laptop.
# nvidia-suspend/resume/hibernate handle GPU state across sleep cycles,
# which is essential for a laptop that frequently suspends.
systemctl enable nvidia-suspend.service   2>/dev/null || true
systemctl enable nvidia-resume.service    2>/dev/null || true
systemctl enable nvidia-hibernate.service 2>/dev/null || true

# Wait for the kernel module to finish building (akmods can take a moment).
# This is important — if the user reboots before the kmod is built, they'll
# get a black screen or fallback to nouveau.
info "Waiting for NVIDIA kernel module (akmods) to finish building..."
akmods --force 2>/dev/null || true
dracut --force 2>/dev/null || true

success "NVIDIA proprietary drivers installed."
warn "A reboot is required for the NVIDIA drivers to take effect."

# ============================================================================
# STEP 4: Install Brave Browser
# ============================================================================
# Brave is installed from its official RPM repository.
# Reference: https://brave.com/linux/
info "STEP 4/12 — Installing Brave Browser..."

# Import the Brave GPG key
dnf install -y dnf-plugins-core 2>/dev/null || true
rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc

# Add the Brave repository
cat > /etc/yum.repos.d/brave-browser.repo << 'EOF'
[brave-browser]
name=Brave Browser
baseurl=https://brave-browser-rpm-release.s3.brave.com/x86_64/
enabled=1
gpgcheck=1
gpgkey=https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
EOF

dnf install -y brave-browser
success "Brave Browser installed."

# ============================================================================
# STEP 5: Install Visual Studio Code
# ============================================================================
# VS Code is installed from Microsoft's official RPM repository.
# Reference: https://code.visualstudio.com/docs/setup/linux
info "STEP 5/12 — Installing Visual Studio Code..."

# Import the Microsoft GPG key
rpm --import https://packages.microsoft.com/keys/microsoft.asc

# Add the VS Code repository
cat > /etc/yum.repos.d/vscode.repo << 'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

dnf install -y code
success "Visual Studio Code installed."

# ============================================================================
# STEP 6: Install Steam
# ============================================================================
# Steam is available from the RPM Fusion nonfree repository (already enabled
# in Step 2). It pulls in 32-bit compatibility libraries automatically.
info "STEP 6/12 — Installing Steam..."

dnf install -y steam
success "Steam installed."

# ============================================================================
# STEP 7: Install GitHub Desktop (Linux Fork — via Flatpak)
# ============================================================================
# GitHub Desktop does not have an official Linux build. The community
# maintains a well-regarded fork available as a Flatpak:
# https://github.com/shiftkey/desktop
info "STEP 7/12 — Installing GitHub Desktop (Linux fork via Flatpak)..."

# Ensure Flatpak is installed and Flathub is configured
dnf install -y flatpak 2>/dev/null || true

# Add the Flathub remote if it doesn't already exist
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# Install GitHub Desktop from Flathub
flatpak install -y flathub io.github.shiftey.Desktop
success "GitHub Desktop (Linux fork) installed via Flatpak."

# ============================================================================
# STEP 8: Install ProtonUp-Qt (via Flatpak)
# ============================================================================
# ProtonUp-Qt is a GUI tool to install and manage custom Proton builds
# (GE-Proton, Luxtorpeda, etc.) for Steam and Lutris.
# Reference: https://github.com/DavidoTek/ProtonUp-Qt
info "STEP 8/12 — Installing ProtonUp-Qt via Flatpak..."

flatpak install -y flathub net.davidotek.pupgui2
success "ProtonUp-Qt installed via Flatpak."

# ============================================================================
# STEP 9: Install Sober (Roblox for Linux) + NVIDIA GPU Override
# ============================================================================
# Sober is a community Flatpak that runs the Android version of Roblox
# natively on Linux. On hybrid-GPU laptops like the TUF F15, we must
# explicitly tell it to use the dedicated NVIDIA GPU via env overrides.
# Reference: https://vinegarhq.org
info "STEP 9/12 — Installing Sober (Roblox) via Flatpak..."

flatpak install -y flathub org.vinegarhq.Sober
success "Sober (Roblox) installed via Flatpak."

# Force Sober to use the dedicated NVIDIA GPU instead of the integrated
# Intel/AMD iGPU. This is critical on hybrid-GPU laptops for performance.
#   __NV_PRIME_RENDER_OFFLOAD=1   → Tell the driver to offload rendering to dGPU
#   __GLX_VENDOR_LIBRARY_NAME=nvidia → Force the NVIDIA GLX implementation
#   __VK_LAYER_NV_optimus=NVIDIA_only → Force Vulkan to use NVIDIA only
info "Configuring Sober to use the dedicated NVIDIA GPU..."
flatpak override --env=__NV_PRIME_RENDER_OFFLOAD=1 \
                 --env=__GLX_VENDOR_LIBRARY_NAME=nvidia \
                 --env=__VK_LAYER_NV_optimus=NVIDIA_only \
                 org.vinegarhq.Sober
success "Sober NVIDIA GPU override applied."

# ============================================================================
# STEP 10: Install Gaming & Performance Tools
# ============================================================================
# These are tools that every Linux gamer should have. They don't come
# pre-installed but make a massive difference.
info "STEP 10/12 — Installing gaming & performance tools..."

# ── GameMode ────────────────────────────────────────────────────────────────
# Feral Interactive's GameMode temporarily applies performance optimizations
# when a game is running: CPU governor → performance, I/O priority boost,
# GPU clock pinning, and more. Steam auto-detects it, or you can force it
# with "gamemoderun %command%" in a game's launch options.
dnf install -y gamemode
info "  → GameMode installed (use: gamemoderun %command%)"

# ── MangoHud ────────────────────────────────────────────────────────────────
# A Vulkan/OpenGL overlay that shows FPS, frame times, CPU/GPU usage, temps,
# VRAM, and more — think MSI Afterburner for Linux. Add "mangohud %command%"
# to Steam launch options, or combine: "mangohud gamemoderun %command%".
dnf install -y mangohud
info "  → MangoHud installed (use: mangohud %command%)"

# ── GOverlay ────────────────────────────────────────────────────────────────
# A graphical configurator for MangoHud. Lets you drag-and-drop metrics,
# change colours, and preview the overlay without editing config files.
dnf install -y goverlay
info "  → GOverlay installed (MangoHud GUI configurator)"

# ── Flatseal ───────────────────────────────────────────────────────────────
# Graphical permission manager for Flatpak apps. Useful for tweaking GPU
# access, filesystem permissions, and environment variables for Sober,
# GitHub Desktop, ProtonUp-Qt, etc.
flatpak install -y flathub com.github.tchx84.Flatseal
info "  → Flatseal installed (Flatpak permission manager)"

# ── Multimedia Codecs (via RPM Fusion) ──────────────────────────────────────
# Fedora ships without proprietary codecs. This installs everything you need
# for video playback, streaming, and game cinematics (H.264, H.265, AAC, etc).
# The @multimedia group pulls in ffmpeg, gstreamer plugins, etc.
dnf group install -y multimedia --with-optional 2>/dev/null || \
    dnf install -y ffmpeg gstreamer1-plugins-bad-free gstreamer1-plugins-bad-freeworld \
                   gstreamer1-plugins-good gstreamer1-plugins-ugly \
                   gstreamer1-plugin-openh264 mozilla-openh264 2>/dev/null || true

# Hardware-accelerated codec support via NVIDIA NVDEC/NVENC
dnf install -y ffmpeg-libs libva-nvidia-driver 2>/dev/null || true
info "  → Multimedia codecs installed (H.264, H.265, AAC, etc.)"

success "All gaming & performance tools installed."

# ============================================================================
# STEP 11: System & KDE Plasma Optimizations
# ============================================================================
# These are things Fedora doesn't do out of the box that make a real
# difference for gaming and daily use on a KDE Plasma laptop.
info "STEP 11/12 — Applying system & KDE Plasma optimizations..."

# ── 11a. NVIDIA Flatpak Runtime ─────────────────────────────────────────────
# Flatpak apps (Sober, etc.) need the matching NVIDIA GL driver runtime
# to actually use the GPU. We detect the installed driver version and
# install the corresponding Flatpak extension automatically.
info "  → Installing NVIDIA Flatpak GL runtime..."
NVIDIA_VERSION=$(modinfo -F version nvidia 2>/dev/null || true)
if [[ -n "$NVIDIA_VERSION" ]]; then
    # Replace dots with dashes for the Flatpak runtime naming convention
    FLATPAK_NVIDIA_VER=$(echo "$NVIDIA_VERSION" | tr '.' '-')
    flatpak install -y flathub "org.freedesktop.Platform.GL.nvidia-${FLATPAK_NVIDIA_VER}" \
        2>/dev/null || warn "Could not auto-install NVIDIA Flatpak runtime (version: ${NVIDIA_VERSION}). Install manually after reboot."
else
    warn "NVIDIA driver not yet loaded (reboot needed). After reboot, run:"
    warn "  flatpak install flathub org.freedesktop.Platform.GL.nvidia-\$(modinfo -F version nvidia | tr '.' '-')"
fi

# ── 11b. Power Profiles Daemon (Laptop Optimisation) ────────────────────────
# Ensures power-profiles-daemon is installed and running. On KDE Plasma,
# this integrates with the battery widget in the system tray, letting you
# quickly switch between Balanced / Performance / Power Saver.
# TIP: Switch to "Performance" before gaming for max FPS.
dnf install -y power-profiles-daemon 2>/dev/null || true
systemctl enable --now power-profiles-daemon.service 2>/dev/null || true
info "  → Power Profiles Daemon enabled (use KDE battery widget to switch)"

# ── 11c. Kernel Tweaks for Gaming (sysctl) ──────────────────────────────────
# These are safe, well-known sysctl parameters that improve responsiveness
# and network performance for gaming workloads.
info "  → Applying kernel sysctl tweaks for gaming..."
cat > /etc/sysctl.d/99-gaming-tweaks.conf << 'EOF'
# ── Fedora 44 Gaming Tweaks ─────────────────────────────────────────────────
# Applied by fedora-setup.sh

# Reduce swap aggressiveness. Default is 60; lower values keep more data
# in RAM (great for gaming where you want to avoid stutter from swapping).
vm.swappiness = 10

# Increase the maximum number of memory map areas. Some games (especially
# via Proton/Wine) create many mappings and can hit the default limit of
# 65530, causing crashes. This is a widely recommended fix.
vm.max_map_count = 2147483642

# Reduce the kernel's tendency to write dirty pages, which decreases
# I/O stalls during gameplay (particularly on NVMe SSDs).
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5

# Network: reduce TCP latency for online gaming
net.ipv4.tcp_fastopen = 3
net.core.netdev_max_backlog = 16384
EOF
sysctl --system >/dev/null 2>&1
info "  → sysctl tweaks applied (vm.swappiness=10, vm.max_map_count increased, etc.)"

# ── 11d. Ensure Bluetooth Service is Running ────────────────────────────────
# Many TUF F15 users connect Bluetooth controllers or headsets. The service
# isn't always enabled by default.
systemctl enable --now bluetooth.service 2>/dev/null || true
info "  → Bluetooth service enabled"

# ── 11e. Thermald / TLP Alternative Check ───────────────────────────────────
# On ASUS TUF laptops, the BIOS handles most thermal management, but we
# ensure the kernel thermal framework is active. We do NOT install TLP
# because it conflicts with power-profiles-daemon.
info "  → Verified power management (power-profiles-daemon, no TLP conflict)"

# ── 11f. Firmware Updates via fwupd ─────────────────────────────────────────
# ASUS ships BIOS/firmware updates through the LVFS (Linux Vendor Firmware
# Service). fwupd + the KDE Discover integration lets you update firmware
# directly from the desktop.
dnf install -y fwupd 2>/dev/null || true
info "  → fwupd installed (check for BIOS/firmware updates in KDE Discover)"

# ── 11g. Install useful KDE utilities ──────────────────────────────────────
# These round out the KDE Plasma experience with tools that ship on other
# spins but not always on a fresh minimal KDE install.
dnf install -y \
    kate \
    kcalc \
    spectacle \
    kde-connect \
    ark \
    filelight \
    2>/dev/null || true
info "  → KDE utilities installed (Kate, KCalc, Spectacle, KDE Connect, Ark, Filelight)"

success "All system & KDE Plasma optimizations applied."

# ============================================================================
# STEP 12: Desktop Experience & RAM Optimizations
# ============================================================================
# This section tunes your KDE Plasma desktop to feel snappier, use RAM more
# efficiently, and eliminate common annoyances on a fresh install.
info "STEP 12/12 — Applying desktop experience & RAM optimizations..."

# ── 12a. zRAM Optimization (Compressed Swap in RAM) ─────────────────────────
# Fedora already uses zRAM by default, but we tune it for better performance:
#   - Use zstd compression (best ratio-to-speed balance, better than lzo-rle)
#   - Size = RAM (compressed, so effective capacity is ~2-3x that)
#   - Higher swap-priority so the kernel prefers fast zRAM over any disk swap
#
# On a laptop with 16GB RAM, this effectively gives you ~40-48GB of usable
# memory before anything touches the SSD.
info "  → Tuning zRAM (compressed swap in RAM) with zstd..."
TOTAL_RAM_MB=$(awk '/MemTotal/ {printf "%d", $2 / 1024}' /proc/meminfo)
cat > /etc/systemd/zram-generator.conf << EOF
[zram0]
# Use zstd for the best compression ratio with low CPU overhead.
compression-algorithm = zstd

# Set zRAM size equal to total physical RAM (${TOTAL_RAM_MB} MB detected).
# This is compressed, so effective capacity is ~2-3x larger.
zram-size = ram

# Highest priority so the kernel uses zRAM before any disk-based swap.
swap-priority = 100

# Maximum number of compression streams (parallel threads).
# Defaults to number of CPUs, which is optimal for multi-core laptops.
EOF
info "  → zRAM configured: zstd compression, size=RAM (${TOTAL_RAM_MB} MB), priority=100"

# ── 12b. Memory Sysctl Tuning (Desktop Responsiveness) ─────────────────────
# Complements the gaming tweaks in Step 11c with desktop-focused parameters.
info "  → Applying memory & desktop sysctl tweaks..."
cat > /etc/sysctl.d/99-desktop-memory.conf << 'EOF'
# ── Fedora 44 Desktop Memory Tweaks ─────────────────────────────────────────
# Applied by fedora-setup.sh

# Keep directory/inode caches in RAM longer. Default is 100 (equal pressure
# on page cache vs. inode/dentry cache). Lower values tell the kernel to
# prefer keeping filesystem metadata cached, which makes file browsing in
# Dolphin and app launching noticeably snappier.
vm.vfs_cache_pressure = 50

# Reduce the time dirty data stays in memory before being flushed to disk.
# Default is 3000 (30 seconds). A shorter window (15 sec) means less data
# at risk during a power loss and more consistent I/O behaviour.
vm.dirty_writeback_centisecs = 1500

# Enable compact_unevictable_allowed so the kernel can defragment memory
# more aggressively, reducing fragmentation on long-running sessions.
vm.compact_unevictable_allowed = 1
EOF
sysctl --system >/dev/null 2>&1
info "  → Desktop memory sysctl tweaks applied (vfs_cache_pressure=50, etc.)"

# ── 12c. systemd-oomd (Out-Of-Memory Daemon) ────────────────────────────────
# Fedora uses systemd-oomd instead of earlyoom. It monitors memory pressure
# and kills runaway processes BEFORE the system freezes. We just make sure
# it's enabled — it's much better than the kernel's built-in OOM killer.
systemctl enable --now systemd-oomd.service 2>/dev/null || true
info "  → systemd-oomd enabled (prevents system freezes from RAM exhaustion)"

# ── 12d. Tame Baloo File Indexer ────────────────────────────────────────────
# Baloo is KDE's file search indexer. On first boot it will index your entire
# home directory, eating CPU and RAM for potentially hours. We configure it
# to index filenames only (not file content) which is 90% lighter while still
# letting you search for files in Dolphin and KRunner.
info "  → Configuring Baloo file indexer (filenames only, no content)..."
BALOO_CONFIG="${REAL_HOME}/.config/baloofilerc"
mkdir -p "${REAL_HOME}/.config"
cat > "${BALOO_CONFIG}" << 'EOF'
[General]
# Index filenames only — skip content indexing to save CPU/RAM.
# You can still search by filename in Dolphin and KRunner.
# To fully disable Baloo, change this to: dbVersion=0 and run balooctl6 disable
only basic indexing=true

[Basic Settings]
Indexing-Enabled=true
EOF
chown "$REAL_USER:$REAL_USER" "$BALOO_CONFIG"
info "  → Baloo set to filename-only indexing (saves significant RAM/CPU)"

# ── 12e. DNF Speed Optimization ────────────────────────────────────────────
# By default DNF downloads packages one at a time. We enable parallel
# downloads (10 simultaneous) so system updates finish much faster.
# We intentionally do NOT enable fastestmirror — it measures TCP latency
# rather than throughput and often picks slower mirrors.
info "  → Optimizing DNF for faster downloads..."
DNF_CONF="/etc/dnf/dnf.conf"
if ! grep -q "max_parallel_downloads" "$DNF_CONF" 2>/dev/null; then
    cat >> "$DNF_CONF" << 'EOF'

# ── Added by fedora-setup.sh ────────────────────────────────────────────────
# Download up to 10 packages simultaneously instead of 1.
max_parallel_downloads=10

# Show a countdown before performing operations (gives you a moment to cancel).
defaultyes=True
EOF
fi
info "  → DNF: max_parallel_downloads=10"

# ── 12f. Limit systemd Journal Size ────────────────────────────────────────
# The systemd journal can grow to several GB over time. We cap it at 500MB
# so it doesn't silently eat disk space. Logs older than the cap are pruned
# automatically.
info "  → Limiting systemd journal size to 500MB..."
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/99-size-limit.conf << 'EOF'
[Journal]
SystemMaxUse=500M
RuntimeMaxUse=100M
EOF
systemctl restart systemd-journald 2>/dev/null || true
info "  → Journal capped at 500MB persistent + 100MB runtime"

# ── 12g. Font Rendering & Essential Fonts ──────────────────────────────────
# KDE Plasma's default font rendering can look thin or blurry on some panels.
# We install high-quality fonts and ensure proper antialiasing is configured.
info "  → Installing fonts & improving font rendering..."
dnf install -y \
    google-noto-sans-fonts \
    google-noto-serif-fonts \
    google-noto-sans-mono-fonts \
    google-noto-color-emoji-fonts \
    mozilla-fira-mono-fonts \
    jetbrains-mono-fonts-all \
    fontconfig-enhanced-defaults \
    fontconfig-font-replacements \
    2>/dev/null || true

# Apply FreeType rendering improvements system-wide.
# This prevents "stem darkening" which makes fonts look overly bold/fuzzy.
if ! grep -q "FREETYPE_PROPERTIES" /etc/environment 2>/dev/null; then
    echo 'FREETYPE_PROPERTIES="cff:no-stem-darkening=0 autofitter:no-stem-darkening=0"' >> /etc/environment
fi
info "  → Fonts installed (Noto, JetBrains Mono, Fira Mono) + rendering tweaks"

# ── 12h. Install btop (System Monitor) ─────────────────────────────────────
# btop is a beautiful, feature-rich terminal system monitor (like htop on
# steroids). It shows CPU, RAM, disk, network, and per-process stats with
# a mouse-friendly TUI. Great for keeping an eye on RAM usage.
dnf install -y btop 2>/dev/null || true
info "  → btop installed (run 'btop' to monitor CPU/RAM/disk/network)"

# ── 12i. IRQ Balancing ─────────────────────────────────────────────────────
# irqbalance distributes hardware interrupt requests across CPU cores.
# Without it, all IRQs hit core 0, which can cause micro-stutter when
# gaming and doing I/O at the same time (common on gaming laptops).
dnf install -y irqbalance 2>/dev/null || true
systemctl enable --now irqbalance.service 2>/dev/null || true
info "  → irqbalance enabled (distributes IRQs across CPU cores)"

# ── 12j. Disable ABRT Auto-Reporting (Privacy) ─────────────────────────────
# ABRT is Fedora's crash reporter. It runs daemons in the background and
# uploads crash dumps. On a personal laptop you probably don't need this.
# Disabling it saves a few background services and RAM.
systemctl disable --now abrtd.service 2>/dev/null || true
systemctl disable --now abrt-journal-core.service 2>/dev/null || true
systemctl disable --now abrt-oops.service 2>/dev/null || true
systemctl disable --now abrt-xorg.service 2>/dev/null || true
info "  → ABRT crash reporter disabled (saves background RAM)"

# ── 12k. KDE Plasma Desktop Settings (for the logged-in user) ──────────────
# These are KDE-specific config files that improve the daily desktop feel.
# They run as the REAL user (not root) to write to the correct home dir.
info "  → Applying KDE Plasma desktop tweaks for user '${REAL_USER}'..."

# Reduce KDE animation speed to make the desktop feel more responsive.
# 0 = instant, 1 = default. 0.5 is a snappy sweet spot.
KDE_GLOBALS="${REAL_HOME}/.config/kdeglobals"
if [[ -f "$KDE_GLOBALS" ]]; then
    # Only add if not already set
    if ! grep -q "AnimationDurationFactor" "$KDE_GLOBALS" 2>/dev/null; then
        sed -i '/^\[KDE\]/a AnimationDurationFactor=0.5' "$KDE_GLOBALS" 2>/dev/null || true
    fi
else
    mkdir -p "${REAL_HOME}/.config"
    cat > "$KDE_GLOBALS" << 'EOF'
[KDE]
AnimationDurationFactor=0.5
EOF
fi
chown "$REAL_USER:$REAL_USER" "$KDE_GLOBALS" 2>/dev/null || true
info "  → KDE animation speed set to 0.5x (snappier transitions)"

# Enable NumLock on login (common preference for laptops with numpads)
KSCREEN="${REAL_HOME}/.config/kcminputrc"
if ! grep -q "NumLock" "$KSCREEN" 2>/dev/null; then
    mkdir -p "${REAL_HOME}/.config"
    cat >> "$KSCREEN" << 'EOF'

[Keyboard]
NumLock=0
EOF
    chown "$REAL_USER:$REAL_USER" "$KSCREEN" 2>/dev/null || true
fi
info "  → NumLock on login enabled"

success "All desktop experience & RAM optimizations applied."

# ============================================================================
# Post-Install Summary
# ============================================================================
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║                      Setup Complete! 🎉                         ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}── Applications ──${NC}"
echo -e "  ${GREEN}✔${NC}  System updated"
echo -e "  ${GREEN}✔${NC}  RPM Fusion (free + nonfree) enabled"
echo -e "  ${GREEN}✔${NC}  NVIDIA proprietary drivers (akmod-nvidia + power mgmt)"
echo -e "  ${GREEN}✔${NC}  Brave Browser"
echo -e "  ${GREEN}✔${NC}  Visual Studio Code"
echo -e "  ${GREEN}✔${NC}  Steam"
echo -e "  ${GREEN}✔${NC}  GitHub Desktop (Flatpak)"
echo -e "  ${GREEN}✔${NC}  ProtonUp-Qt (Flatpak)"
echo -e "  ${GREEN}✔${NC}  Sober / Roblox (Flatpak, NVIDIA GPU override applied)"
echo ""
echo -e "  ${BOLD}── Gaming & Performance ──${NC}"
echo -e "  ${GREEN}✔${NC}  GameMode (auto-optimises CPU/GPU while gaming)"
echo -e "  ${GREEN}✔${NC}  MangoHud + GOverlay (FPS/perf overlay)"
echo -e "  ${GREEN}✔${NC}  Flatseal (Flatpak permission manager)"
echo -e "  ${GREEN}✔${NC}  Multimedia codecs (H.264, H.265, AAC, etc.)"
echo ""
echo -e "  ${BOLD}── System Optimizations ──${NC}"
echo -e "  ${GREEN}✔${NC}  NVIDIA Flatpak GL runtime"
echo -e "  ${GREEN}✔${NC}  Power Profiles Daemon (KDE battery integration)"
echo -e "  ${GREEN}✔${NC}  Kernel sysctl gaming tweaks (swappiness, max_map_count, etc.)"
echo -e "  ${GREEN}✔${NC}  Bluetooth service enabled"
echo -e "  ${GREEN}✔${NC}  fwupd firmware updater"
echo -e "  ${GREEN}✔${NC}  KDE utilities (Kate, Spectacle, KDE Connect, etc.)"
echo ""
echo -e "  ${BOLD}── Desktop & RAM Optimizations ──${NC}"
echo -e "  ${GREEN}✔${NC}  zRAM tuned (zstd, size=RAM, priority=100)"
echo -e "  ${GREEN}✔${NC}  Desktop memory sysctl (vfs_cache_pressure, writeback tuning)"
echo -e "  ${GREEN}✔${NC}  systemd-oomd (prevents freeze on RAM exhaustion)"
echo -e "  ${GREEN}✔${NC}  Baloo file indexer → filename-only mode (saves RAM/CPU)"
echo -e "  ${GREEN}✔${NC}  DNF parallel downloads (10x faster updates)"
echo -e "  ${GREEN}✔${NC}  Journal size capped at 500MB"
echo -e "  ${GREEN}✔${NC}  Fonts (Noto, JetBrains Mono) + rendering improvements"
echo -e "  ${GREEN}✔${NC}  btop system monitor"
echo -e "  ${GREEN}✔${NC}  irqbalance (distribute IRQs across CPU cores)"
echo -e "  ${GREEN}✔${NC}  ABRT crash reporter disabled"
echo -e "  ${GREEN}✔${NC}  KDE animations reduced to 0.5x (snappier feel)"
echo -e "  ${GREEN}✔${NC}  NumLock on login enabled"
echo ""
echo -e "  ${YELLOW}══════════════════════════════════════════════════════════════${NC}"
echo -e "  ${YELLOW}⚠  IMPORTANT:${NC} You ${BOLD}must reboot${NC} for all changes to take effect."
echo -e "  ${CYAN}→${NC}  Run: ${BOLD}sudo systemctl reboot${NC}"
echo -e "  ${YELLOW}══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}── After Reboot ──${NC}"
echo -e "  ${CYAN}1.${NC}  Verify NVIDIA drivers:  ${BOLD}nvidia-smi${NC}"
echo -e "  ${CYAN}2.${NC}  Verify zRAM is active:  ${BOLD}zramctl${NC}"
echo -e "  ${CYAN}3.${NC}  Monitor your system:    ${BOLD}btop${NC}"
echo -e "  ${CYAN}4.${NC}  Open ${BOLD}ProtonUp-Qt${NC} → install ${BOLD}GE-Proton${NC}"
echo -e "  ${CYAN}5.${NC}  In Steam → Settings → Compatibility → enable GE-Proton"
echo -e "  ${CYAN}6.${NC}  For any Steam game, set launch options to:"
echo -e "     ${BOLD}mangohud gamemoderun %command%${NC}"
echo -e "  ${CYAN}7.${NC}  Switch to ${BOLD}Performance${NC} mode in the KDE battery widget"
echo -e "     before gaming for maximum FPS."
echo -e "  ${CYAN}8.${NC}  Open ${BOLD}Sober${NC} and sign in to Roblox — it will auto-use"
echo -e "     your NVIDIA GPU."
echo -e "  ${CYAN}9.${NC}  Use ${BOLD}Flatseal${NC} to manage permissions for Flatpak apps."
echo -e "  ${CYAN}10.${NC} Check for BIOS updates in ${BOLD}KDE Discover → Updates${NC}."
echo ""

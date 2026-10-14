#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[ OK ]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[FAIL]${NC} $1"; }
log_step()    { echo -e "${CYAN}==>${NC} $1"; }

detect_system() {
    log_step "Detecting system type..."

    if [ -n "$TERMUX_VERSION" ] || [ -d "/data/data/com.termux" ] \
       || { [ -n "$PREFIX" ] && [[ "$PREFIX" == *"com.termux"* ]]; }; then
        SYSTEM_TYPE="termux"
        SYSTEM_NAME="Termux"
        PKG_ROOT="${PREFIX:-/data/data/com.termux/files/usr}"
    elif [ -f "/etc/os-release" ]; then
        . /etc/os-release
        SYSTEM_NAME="$NAME"
        SYSTEM_TYPE="linux"
    else
        SYSTEM_TYPE="linux"
        SYSTEM_NAME="Unknown Linux"
    fi
    log_success "System: $SYSTEM_NAME ($SYSTEM_TYPE)"
    [ -n "$PKG_ROOT" ] && log_info "PREFIX: $PKG_ROOT"
}

check_base_tools() {
    log_step "Checking base tools..."

    MISSING_TOOLS=""
    for tool in sh bash ls cat echo awk sed grep find; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            MISSING_TOOLS="$MISSING_TOOLS $tool"
        fi
    done

    if [ -n "$MISSING_TOOLS" ]; then
        log_error "Missing base tools:$MISSING_TOOLS"
    else
        log_success "Base tools OK"
    fi

    for tool in wget curl dpkg apt pkg tar gzip; do
        if command -v "$tool" >/dev/null 2>&1; then
            log_success "$tool available"
        else
            log_warn "$tool not available"
        fi
    done
}

check_linker() {
    log_step "Checking dynamic linker and libc..."
    if command -v ldd >/dev/null 2>&1; then
        if ! ldd /bin/ls >/dev/null 2>&1; then
            log_error "Dynamic linker broken, libc/ld may be corrupted"
            LINKER_BROKEN=1
        else
            log_success "Dynamic linker OK"
            LINKER_BROKEN=0
        fi
    else
        log_warn "ldd not available, skipping check"
        LINKER_BROKEN=0
    fi
}

check_dpkg_db() {
    log_step "Checking dpkg database..."

    if ! command -v dpkg >/dev/null 2>&1; then
        log_error "dpkg not available, database may be corrupted"
        DPKG_BROKEN=1
        return
    fi

    if [ -d /var/lib/dpkg ]; then
        if [ -f /var/lib/dpkg/status ]; then
            if grep -q "^Status: install ok half-configured" /var/lib/dpkg/status 2>/dev/null; then
                log_warn "Found half-configured packages"
            fi
        else
            log_error "/var/lib/dpkg/status missing"
            DPKG_BROKEN=1
            return
        fi

        if [ -d /var/lib/dpkg/updates ] && [ -n "$(ls -A /var/lib/dpkg/updates 2>/dev/null)" ]; then
            log_warn "/var/lib/dpkg/updates has leftovers, possible interrupted transaction"
        fi
    fi

    DPKG_BROKEN=0
    log_success "dpkg database looks OK"
}

check_network() {
    log_step "Checking network connectivity..."
    local ok=0
    for host in 8.8.8.8 1.1.1.1 223.5.5.5; do
        if ping -c 1 -W 2 "$host" >/dev/null 2>&1; then
            ok=1
            break
        fi
    done
    if [ "$ok" -eq 1 ]; then
        log_success "Network reachable"
    else
        log_warn "ping unreachable (ICMP may be blocked)"
    fi
}

fix_termux() {
    log_step "Starting Termux repair..."

    PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
    local TMPDIR="${TMPDIR:-$PREFIX/tmp}"
    mkdir -p "$TMPDIR" 2>/dev/null

    if ! command -v pkg >/dev/null 2>&1 && ! command -v apt >/dev/null 2>&1; then
        log_error "Both pkg and apt unavailable! Entering deep repair mode"
        fix_termux_deep
        return
    fi

    if ! dpkg --audit >/dev/null 2>&1; then
        log_warn "dpkg database abnormal, attempting rebuild"
        fix_termux_dpkg_db
    fi

    log_info "Step 1: Update index"
    pkg update -y 2>&1 | tail -n 5

    log_info "Step 2: Fix broken dependencies"
    apt --fix-broken install -y 2>&1 | tail -n 5

    log_info "Step 3: Configure pending packages"
    dpkg --configure -a 2>&1 | tail -n 5

    log_info "Step 4: Force install missing dependencies"
    apt install -f -y 2>&1 | tail -n 5

    log_info "Step 5: Upgrade"
    pkg upgrade -y 2>&1 | tail -n 5

    log_info "Step 6: Reinstall core packages"
    for p in coreutils bash apt dpkg termux-tools; do
        if ! dpkg -s "$p" >/dev/null 2>&1; then
            log_warn "$p missing, reinstalling..."
            apt install --reinstall -y "$p" 2>&1 | tail -n 3
        fi
    done

    for cmd in ls cat bash apt dpkg; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "$cmd still unavailable, trying bootstrap restore"
            fix_termux_bootstrap
            break
        fi
    done

    log_info "Step 7: Cleanup"
    apt clean 2>&1 | tail -n 2
    apt autoclean 2>&1 | tail -n 2

    log_success "Termux repair complete"
}

fix_termux_deep() {
    log_warn "Attempting to download Termux bootstrap to rebuild base environment..."

    local ARCH
    ARCH=$(uname -m)
    case "$ARCH" in
        aarch64|arm64) BOOTSTRAP_ARCH="aarch64" ;;
        armv7l|armv8l) BOOTSTRAP_ARCH="arm" ;;
        x86_64)        BOOTSTRAP_ARCH="x86_64" ;;
        i686|i386)     BOOTSTRAP_ARCH="i686" ;;
        *) log_error "Unsupported architecture: $ARCH"; return 1 ;;
    esac

    local URL="https://github.com/termux/termux-packages/releases/latest/download/bootstrap-${BOOTSTRAP_ARCH}.zip"
    local TMP="${TMPDIR:-/tmp}/bootstrap.zip"

    if command -v curl >/dev/null 2>&1; then
        curl -L -o "$TMP" "$URL" || { log_error "Download failed"; return 1; }
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$TMP" "$URL" || { log_error "Download failed"; return 1; }
    else
        log_error "Neither curl nor wget available, cannot auto-recover"
        log_info "Please reinstall Termux from F-Droid, or see:"
        log_info "https://github.com/termux/termux-packages"
        return 1
    fi

    log_warn "Bootstrap downloaded to $TMP"
    log_warn "Manual recovery steps (run outside Termux):"
    echo "  1. Backup: mv \$PREFIX \$PREFIX.bak"
    echo "  2. Extract: unzip $TMP -d \$PREFIX"
    echo "  3. Fix perms: chmod -R 755 \$PREFIX"
    echo "  4. Restart Termux"
}

fix_termux_dpkg_db() {
    log_warn "Rebuilding dpkg database..."
    local DPKG_DIR="/data/data/com.termux/files/usr/var/lib/dpkg"
    [ -d "$DPKG_DIR" ] || DPKG_DIR="/var/lib/dpkg"

    if [ -d "$DPKG_DIR" ]; then
        [ -f "$DPKG_DIR/status" ] || touch "$DPKG_DIR/status"
        [ -d "$DPKG_DIR/updates" ] || mkdir -p "$DPKG_DIR/updates"
        [ -f "$DPKG_DIR/diversions" ] || touch "$DPKG_DIR/diversions"
        [ -f "$DPKG_DIR/statoverride" ] || touch "$DPKG_DIR/statoverride"
        log_success "dpkg directory structure repaired"
    fi
}

fix_linux_apt() {
    log_step "Starting Linux (apt/dpkg) repair..."

    SUDO=""
    if [ "$(id -u)" -ne 0 ]; then
        if command -v sudo >/dev/null 2>&1; then
            SUDO="sudo"
        elif command -v su >/dev/null 2>&1; then
            log_error "sudo not found, run as root or install sudo"
            exit 1
        else
            log_error "Cannot obtain root privileges"
            exit 1
        fi
    fi

    if command -v dpkg >/dev/null 2>&1; then
        fix_linux_dpkg_db "$SUDO"
    fi

    if ! command -v apt >/dev/null 2>&1 || ! apt --version >/dev/null 2>&1; then
        log_error "apt unavailable! Attempting to reinstall apt via dpkg"
        fix_linux_reinstall_apt "$SUDO"
    fi

    if [ "${LINKER_BROKEN:-0}" -eq 1 ]; then
        log_error "Dynamic linker broken, apt may not run"
        log_info "Suggested:"
        echo "  1. Boot from Live USB, chroot into system to repair"
        echo "  2. Or: dpkg -i to reinstall libc6 (download .deb first)"
        fix_linux_libc "$SUDO"
    fi

    log_info "Step 1: Update index"
    $SUDO apt update 2>&1 | tail -n 5

    log_info "Step 2: Fix broken dependencies"
    $SUDO apt --fix-broken install -y 2>&1 | tail -n 5

    log_info "Step 3: Configure pending packages"
    $SUDO dpkg --configure -a 2>&1 | tail -n 5

    log_info "Step 4: Force install missing dependencies"
    $SUDO apt install -f -y 2>&1 | tail -n 5

    log_info "Step 5: Reinstall critical packages"
    for p in apt dpkg libc6 coreutils bash; do
        if ! dpkg -s "$p" >/dev/null 2>&1; then
            log_warn "$p missing, reinstalling..."
            $SUDO apt install --reinstall -y "$p" 2>&1 | tail -n 3
        fi
    done

    log_info "Step 6: Cleanup"
    $SUDO apt autoremove -y 2>&1 | tail -n 3
    $SUDO apt autoclean 2>&1 | tail -n 3
    $SUDO apt clean 2>&1 | tail -n 2

    log_info "Step 7: Upgrade"
    $SUDO apt upgrade -y 2>&1 | tail -n 5

    log_success "Linux repair complete"
}

fix_linux_dpkg_db() {
    local SUDO="$1"
    log_info "Checking dpkg database structure..."

    $SUDO mkdir -p /var/lib/dpkg/updates /var/lib/dpkg/info /var/lib/dpkg/triggers
    $SUDO touch /var/lib/dpkg/status /var/lib/dpkg/diversions /var/lib/dpkg/statoverride

    if [ -n "$($SUDO ls -A /var/lib/dpkg/updates 2>/dev/null)" ]; then
        log_warn "Cleaning /var/lib/dpkg/updates leftovers"
        $SUDO rm -f /var/lib/dpkg/updates/*
    fi

    log_success "dpkg database structure repaired"
}

fix_linux_reinstall_apt() {
    local SUDO="$1"
    log_warn "Attempting to download .deb and reinstall apt..."

    local ARCH
    ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)
    local CODENAME
    CODENAME=$(. /etc/os-release 2>/dev/null && echo "$VERSION_CODENAME")
    [ -z "$CODENAME" ] && CODENAME="stable"

    local MIRROR="http://deb.debian.org/debian"
    local POOL="$MIRROR/pool/main/a/apt"

    log_info "Architecture: $ARCH, distro: $CODENAME"
    log_warn "Automatic download may fail (version mismatch)"
    log_info "More reliable method:"
    echo "  1. Download matching apt_*.deb on another machine"
    echo "  2. Copy to this machine: dpkg -i apt_*.deb"
    echo "  3. Or use Live USB + chroot"

    if command -v curl >/dev/null 2>&1; then
        log_info "Listing available apt versions..."
        curl -s "$POOL/" 2>/dev/null | grep -oE 'apt_[^"]+_'"$ARCH"'\.deb' | head -n 5
    fi
}

fix_linux_libc() {
    local SUDO="$1"
    log_warn "libc repair requires caution, a mistake can make the system unbootable"

    local ARCH
    ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)

    log_info "Recommended steps:"
    echo "  1. Copy /lib/x86_64-linux-gnu/libc.so.6 from an identical machine"
    echo "  2. Or boot from Live USB, mount root partition, then:"
    echo "     sudo cp libc.so.6 /mnt/lib/x86_64-linux-gnu/"
    echo "     sudo cp ld-linux-x86-64.so.2 /mnt/lib/x86_64-linux-gnu/"
    echo "  3. After chroot: dpkg -i libc6_*.deb"
    echo ""
    log_warn "Automatic libc repair is too risky, script will not execute it"
}

fix_linux_other() {
    log_step "Non-Debian system detected, trying corresponding package manager..."
    SUDO=""
    [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && SUDO="sudo"

    if command -v dnf >/dev/null 2>&1; then
        $SUDO dnf check-update 2>&1 | tail -n 5
        $SUDO dnf upgrade -y 2>&1 | tail -n 5
        $SUDO dnf autoremove -y 2>&1 | tail -n 3
    elif command -v yum >/dev/null 2>&1; then
        $SUDO yum update -y 2>&1 | tail -n 5
        $SUDO yum clean all 2>&1 | tail -n 3
    elif command -v pacman >/dev/null 2>&1; then
        $SUDO pacman -Sy --noconfirm 2>&1 | tail -n 5
        $SUDO pacman -Su --noconfirm 2>&1 | tail -n 5
        $SUDO pacman -Sc --noconfirm 2>&1 | tail -n 3
    elif command -v zypper >/dev/null 2>&1; then
        $SUDO zypper refresh 2>&1 | tail -n 5
        $SUDO zypper update -y 2>&1 | tail -n 5
    else
        log_error "No usable package manager found"
        log_info "Manual intervention may be required"
        exit 1
    fi
    log_success "Repair complete"
}

show_info() {
    echo ""
    echo "============================================"
    echo "  System Diagnostic Report"
    echo "============================================"
    echo "System:   $SYSTEM_NAME ($SYSTEM_TYPE)"
    echo "Kernel:   $(uname -r)"
    echo "Arch:     $(uname -m)"
    echo "User:     $(whoami) (uid=$(id -u))"
    [ -n "$PKG_ROOT" ] && echo "PREFIX:   $PKG_ROOT"
    echo "--------------------------------------------"
    echo "dpkg:     $(command -v dpkg >/dev/null 2>&1 && echo available || echo unavailable)"
    echo "apt:      $(command -v apt  >/dev/null 2>&1 && echo available || echo unavailable)"
    echo "pkg:      $(command -v pkg  >/dev/null 2>&1 && echo available || echo unavailable)"
    echo "curl:     $(command -v curl >/dev/null 2>&1 && echo available || echo unavailable)"
    echo "wget:     $(command -v wget >/dev/null 2>&1 && echo available || echo unavailable)"
    echo "============================================"
    echo ""
}

confirm_run() {
    read -p "Start automatic repair? (y/N): " c
    [[ "$c" =~ ^[Yy]$ ]] || { log_warn "Cancelled"; exit 0; }
}

main() {
    echo ""
    echo "============================================"
    echo "   System Auto Repair Script v2.0 (Worst Case)"
    echo "============================================"

    detect_system
    show_info
    check_base_tools
    check_linker
    check_dpkg_db
    check_network

    confirm_run
    echo ""

    case "$SYSTEM_TYPE" in
        termux) fix_termux ;;
        linux)
            if command -v apt >/dev/null 2>&1 || command -v dpkg >/dev/null 2>&1; then
                fix_linux_apt
            else
                fix_linux_other
            fi
            ;;
        *) log_error "Unknown system"; exit 1 ;;
    esac

    echo ""
    log_success "All repair operations complete"
    echo ""
}

trap 'echo ""; log_warn "Script interrupted"; exit 130' INT
main "$@"
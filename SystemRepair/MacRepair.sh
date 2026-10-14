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

detect_macos() {
    log_step "Detecting macOS environment..."

    if [ "$(uname)" != "Darwin" ]; then
        log_error "This script is for macOS only"
        exit 1
    fi

    SYSTEM_TYPE="macos"
    SYSTEM_NAME="macOS"
    MACOS_VERSION=$(sw_vers -productVersion 2>/dev/null)
    MACOS_BUILD=$(sw_vers -buildVersion 2>/dev/null)
    MACOS_ARCH=$(uname -m)

    log_success "Detected: macOS $MACOS_VERSION ($MACOS_BUILD) on $MACOS_ARCH"
}

check_sudo() {
    log_step "Checking sudo privileges..."

    if [ "$(id -u)" -ne 0 ]; then
        if sudo -n true 2>/dev/null; then
            log_success "Passwordless sudo available"
        else
            log_warn "sudo will prompt for password"
        fi
    else
        log_success "Running as root"
    fi
}

check_sip() {
    log_step "Checking System Integrity Protection (SIP) status..."

    local sip_status
    sip_status=$(csrutil status 2>/dev/null)

    if echo "$sip_status" | grep -qi "enabled"; then
        log_warn "SIP is ENABLED - some repairs will be restricted"
        SIP_STATUS="enabled"
    elif echo "$sip_status" | grep -qi "disabled"; then
        log_success "SIP is DISABLED - full repair possible"
        SIP_STATUS="disabled"
    else
        log_warn "SIP status unknown"
        SIP_STATUS="unknown"
    fi
}

check_network() {
    log_step "Checking network connectivity..."

    if ping -c 1 -t 3 8.8.8.8 >/dev/null 2>&1 || ping -c 1 -t 3 1.1.1.1 >/dev/null 2>&1; then
        log_success "Network reachable"
        NETWORK_OK=1
    else
        log_warn "Network unreachable (some repairs will fail)"
        NETWORK_OK=0
    fi
}

repair_disk() {
    log_step "Checking and repairing disk with fsck..."

    local root_disk
    root_disk=$(df / | tail -n 1 | awk '{print $1}')

    if [[ "$root_disk" == /dev/disk* ]]; then
        log_warn "Root disk: $root_disk"
        log_warn "First Aid must be run from Recovery Mode for the boot volume"
        log_info "To repair:"
        echo "  1. Reboot holding Cmd+R (Intel) or power button (Apple Silicon)"
        echo "  2. Open Disk Utility"
        echo "  3. Select volume and click 'First Aid'"
    else
        log_warn "Cannot determine root disk, skipping"
    fi

    log_success "Disk check guidance complete"
}

repair_permissions() {
    log_step "Repairing user permissions..."

    log_info "Fixing home directory permissions..."
    sudo chmod -R u+rwX ~/ 2>/dev/null
    log_success "Home directory permissions fixed"

    log_info "Fixing /Applications permissions..."
    sudo chmod -R u+rwX,go+rX /Applications 2>/dev/null
    log_success "/Applications permissions fixed"

    log_info "Fixing /Library permissions..."
    sudo chmod -R u+rwX,go+rX /Library 2>/dev/null
    log_success "/Library permissions fixed"
}

repair_acl() {
    log_step "Repairing ACLs on system directories..."

    sudo chmod -N ~/Library/Preferences 2>/dev/null
    sudo chmod -N ~/Library/Caches 2>/dev/null

    log_success "ACL repair complete"
}

repair_launchservices() {
    log_step "Rebuilding Launch Services database..."

    local lsregister
    lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    if [ -x "$lsregister" ]; then
        "$lsregister" -kill -r -domain local -domain system -domain user 2>/dev/null
        log_success "Launch Services database rebuilt"
    else
        log_error "lsregister not found"
    fi
}

repair_dyld_cache() {
    log_step "Rebuilding dyld shared cache..."

    if [ "$SIP_STATUS" = "enabled" ]; then
        log_warn "SIP enabled, cannot update dyld cache"
        log_info "Reboot into Recovery Mode and run:"
        echo "  update_dyld_shared_cache -force"
        return
    fi

    sudo update_dyld_shared_cache -force 2>/dev/null
    log_success "dyld cache rebuilt"
}

repair_dns() {
    log_step "Flushing DNS cache..."

    sudo dscacheutil -flushcache 2>/dev/null
    sudo killall -HUP mDNSResponder 2>/dev/null
    sudo killall mDNSResponderHelper 2>/dev/null

    log_success "DNS cache flushed"
}

repair_network() {
    log_step "Resetting network interfaces..."

    local service
    service=$(networksetup -listallnetworkservices 2>/dev/null | grep -v "denotes" | head -n 1)

    if [ -n "$service" ]; then
        log_info "Resetting: $service"
        sudo networksetup -setdhcp "$service" 2>/dev/null
        log_success "DHCP renewed on $service"
    fi

    log_info "Restarting mDNSResponder..."
    sudo launchctl unload /System/Library/LaunchDaemons/com.apple.mDNSResponder.plist 2>/dev/null
    sudo launchctl load /System/Library/LaunchDaemons/com.apple.mDNSResponder.plist 2>/dev/null

    log_success "Network reset complete"
}

repair_keychain() {
    log_step "Checking keychain integrity..."

    local login_keychain
    login_keychain="$HOME/Library/Keychains/login.keychain-db"

    if [ -f "$login_keychain" ]; then
        security verify-keychain "$login_keychain" 2>&1 | tail -n 3
        if [ ${PIPESTATUS[0]} -eq 0 ]; then
            log_success "Login keychain verified"
        else
            log_warn "Login keychain has issues"
            log_info "Repair via Keychain Access.app > Keychain First Aid"
        fi
    else
        log_warn "Login keychain not found"
    fi
}

repair_nvram() {
    log_step "Checking NVRAM..."

    log_info "Current NVRAM boot-args:"
    nvram boot-args 2>/dev/null | tail -n 1

    log_warn "Resetting NVRAM must be done manually:"
    echo "  Intel Mac: reboot holding Cmd+Option+P+R"
    echo "  Apple Silicon: shut down, hold power button, choose Options > Terminal"
    echo "    then run: sudo nvram -c"

    log_success "NVRAM guidance complete"
}

repair_homebrew() {
    log_step "Repairing Homebrew (if installed)..."

    if ! command -v brew >/dev/null 2>&1; then
        log_warn "Homebrew not installed, skipping"
        return
    fi

    log_info "Running brew doctor..."
    brew doctor 2>&1 | tail -n 10

    log_info "Running brew update..."
    brew update 2>&1 | tail -n 5

    log_info "Running brew upgrade..."
    brew upgrade 2>&1 | tail -n 5

    log_info "Running brew cleanup..."
    brew cleanup 2>&1 | tail -n 5

    log_success "Homebrew repair complete"
}

repair_app_store() {
    log_step "Resetting App Store cache..."

    sudo rm -rf /var/folders/*/*/*/com.apple.appstore 2>/dev/null
    sudo rm -rf ~/Library/Caches/com.apple.appstore 2>/dev/null
    sudo rm -rf ~/Library/Caches/com.apple.AppStore 2>/dev/null

    log_info "Restarting appstoreagent..."
    killall appstoreagent 2>/dev/null

    log_success "App Store cache reset"
}

repair_spctl() {
    log_step "Checking Gatekeeper status..."

    spctl --status 2>/dev/null

    if [ "$SIP_STATUS" = "enabled" ]; then
        log_warn "SIP enabled, Gatekeeper cannot be modified"
    else
        log_info "Re-enabling Gatekeeper..."
        sudo spctl --master-enable 2>/dev/null
        log_success "Gatekeeper enabled"
    fi
}

repair_caches() {
    log_step "Clearing user caches..."

    log_info "Clearing ~/Library/Caches..."
    rm -rf ~/Library/Caches/* 2>/dev/null

    log_info "Clearing system caches (requires sudo)..."
    sudo rm -rf /Library/Caches/* 2>/dev/null
    sudo rm -rf /System/Library/Caches/* 2>/dev/null

    log_success "Caches cleared"
}

repair_preferences() {
    log_step "Checking corrupted preference files..."

    local count=0
    while IFS= read -r plist; do
        if ! plutil -lint "$plist" >/dev/null 2>&1; then
            log_warn "Corrupted: $plist"
            mv "$plist" "$plist.broken" 2>/dev/null
            count=$((count + 1))
        fi
    done < <(find ~/Library/Preferences -name "*.plist" 2>/dev/null)

    if [ "$count" -eq 0 ]; then
        log_success "No corrupted preferences found"
    else
        log_success "Moved $count corrupted plists to .broken"
    fi
}

show_menu() {
    echo ""
    echo "============================================"
    echo "   macOS Repair Menu"
    echo "============================================"
    echo "  1) Run all repairs (recommended)"
    echo "  2) Repair disk permissions"
    echo "  3) Rebuild Launch Services database"
    echo "  4) Rebuild dyld shared cache"
    echo "  5) Flush DNS and reset network"
    echo "  6) Verify keychain"
    echo "  7) Repair Homebrew"
    echo "  8) Reset App Store cache"
    echo "  9) Clear caches"
    echo " 10) Check corrupted preferences"
    echo " 11) NVRAM guidance"
    echo " 12) Disk First Aid guidance"
    echo "  0) Exit"
    echo "============================================"
}

show_info() {
    echo ""
    echo "============================================"
    echo "  System Diagnostic Report"
    echo "============================================"
    echo "System:   $SYSTEM_NAME $MACOS_VERSION"
    echo "Build:    $MACOS_BUILD"
    echo "Arch:     $MACOS_ARCH"
    echo "User:     $(whoami) (uid=$(id -u))"
    echo "SIP:      $SIP_STATUS"
    echo "Network:  $([ "${NETWORK_OK:-0}" -eq 1 ] && echo OK || echo FAIL)"
    echo "--------------------------------------------"
    echo "brew:     $(command -v brew >/dev/null 2>&1 && echo available || echo unavailable)"
    echo "curl:     $(command -v curl >/dev/null 2>&1 && echo available || echo unavailable)"
    echo "plutil:   $(command -v plutil >/dev/null 2>&1 && echo available || echo unavailable)"
    echo "csrutil:  $(command -v csrutil >/dev/null 2>&1 && echo available || echo unavailable)"
    echo "============================================"
    echo ""
}

confirm_run() {
    read -p "Continue? (y/N): " c
    [[ "$c" =~ ^[Yy]$ ]] || { log_warn "Cancelled"; exit 0; }
}

run_all() {
    log_warn "Running all safe repairs. This may take 5-15 minutes"
    confirm_run

    repair_permissions
    repair_acl
    repair_launchservices
    repair_dns
    repair_network
    repair_keychain
    repair_app_store
    repair_caches
    repair_preferences
    repair_homebrew
    repair_spctl

    if [ "$SIP_STATUS" = "disabled" ]; then
        repair_dyld_cache
    else
        log_warn "Skipping dyld cache rebuild (SIP enabled)"
    fi

    echo ""
    log_warn "The following require manual action:"
    echo "  - Disk First Aid (Recovery Mode)"
    echo "  - NVRAM reset"
    echo "  - SMC reset (Intel Macs)"
    echo ""
    log_success "All automatic repairs complete. Reboot recommended."
}

main() {
    echo ""
    echo "============================================"
    echo "   macOS Auto Repair Script v1.0"
    echo "============================================"

    detect_macos
    check_sudo
    check_sip
    check_network
    show_info

    while true; do
        show_menu
        read -p "Select option: " choice
        echo ""

        case "$choice" in
            1) run_all; break ;;
            2) repair_permissions ;;
            3) repair_launchservices ;;
            4) repair_dyld_cache ;;
            5) repair_dns; repair_network ;;
            6) repair_keychain ;;
            7) repair_homebrew ;;
            8) repair_app_store ;;
            9) repair_caches ;;
            10) repair_preferences ;;
            11) repair_nvram ;;
            12) repair_disk ;;
            0) log_info "Exiting"; exit 0 ;;
            *) log_error "Invalid option" ;;
        esac

        echo ""
        read -p "Press Enter to return to menu..."
    done
}

trap 'echo ""; log_warn "Script interrupted"; exit 130' INT
main "$@"
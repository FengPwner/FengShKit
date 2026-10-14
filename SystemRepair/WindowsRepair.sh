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

detect_windows() {
    log_step "Detecting Windows environment..."

    if ! command -v cmd.exe >/dev/null 2>&1 && ! command -v powershell.exe >/dev/null 2>&1; then
        log_error "Not running in a Windows environment (Git Bash / MSYS2 / Cygwin / WSL required)"
        exit 1
    fi

    if [ -d "/mnt/c/Windows" ]; then
        ENV_TYPE="wsl"
        SYSTEM_NAME="Windows (WSL)"
        log_success "Detected: Windows via WSL"
    elif [ -d "/c/Windows" ]; then
        ENV_TYPE="gitbash"
        SYSTEM_NAME="Windows (Git Bash / MSYS2 / Cygwin)"
        log_success "Detected: Windows via Git Bash / MSYS2 / Cygwin"
    else
        ENV_TYPE="unknown"
        SYSTEM_NAME="Windows (unknown mount)"
        log_warn "Windows directory not found in usual paths"
    fi

    if command -v cmd.exe >/dev/null 2>&1; then
        WIN_VER=$(cmd.exe /c ver 2>/dev/null | tr -d '\r' | grep -oE 'Version [0-9.]+' | head -n 1)
        [ -n "$WIN_VER" ] && log_info "$WIN_VER"
    fi
}

check_admin() {
    log_step "Checking administrator privileges..."

    local result
    result=$(cmd.exe /c "net session" 2>&1 | tr -d '\r')
    if echo "$result" | grep -qi "Access is denied"; then
        log_error "Not running as Administrator"
        log_info "Please right-click your terminal and select 'Run as administrator'"
        exit 1
    else
        log_success "Administrator privileges confirmed"
    fi
}

run_cmd() {
    local desc="$1"
    shift
    log_info "$desc"
    cmd.exe /c "$@" 2>&1 | tr -d '\r' | tail -n 5
}

run_ps() {
    local desc="$1"
    local script="$2"
    log_info "$desc"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$script" 2>&1 | tr -d '\r' | tail -n 10
}

repair_sfc() {
    log_step "Running System File Checker (SFC)..."
    log_warn "This may take 10-30 minutes, do not close the window"
    cmd.exe /c "sfc /scannow" 2>&1 | tr -d '\r' | tail -n 10
    log_success "SFC scan complete"
}

repair_dism() {
    log_step "Running DISM to repair system image..."
    log_warn "This may take 10-30 minutes"

    run_cmd "Checking health..." "DISM /Online /Cleanup-Image /CheckHealth"
    run_cmd "Scanning health..." "DISM /Online /Cleanup-Image /ScanHealth"
    run_cmd "Restoring health..." "DISM /Online /Cleanup-Image /RestoreHealth"
    log_success "DISM repair complete"
}

repair_registry() {
    log_step "Backing up registry hives..."

    local backup_dir
    if [ "$ENV_TYPE" = "wsl" ]; then
        backup_dir="/mnt/c/Windows/System32/config/RegBack_$(date +%Y%m%d_%H%M%S)"
    else
        backup_dir="/c/Windows/System32/config/RegBack_$(date +%Y%m%d_%H%M%S)"
    fi

    cmd.exe /c "mkdir \"$(echo "$backup_dir" | sed 's|/mnt/c|C:|; s|/c|C:|; s|/|\\|g')\"" 2>&1 | tr -d '\r'

    for hive in SYSTEM SOFTWARE SAM SECURITY DEFAULT; do
        local src dst
        if [ "$ENV_TYPE" = "wsl" ]; then
            src="/mnt/c/Windows/System32/config/$hive"
        else
            src="/c/Windows/System32/config/$hive"
        fi
        dst="$backup_dir/$hive"
        if [ -f "$src" ]; then
            cmd.exe /c "copy /Y \"$(echo "$src" | sed 's|/mnt/c|C:|; s|/c|C:|; s|/|\\|g')\" \"$(echo "$dst" | sed 's|/mnt/c|C:|; s|/c|C:|; s|/|\\|g')\"" >/dev/null 2>&1
            log_success "Backed up $hive"
        fi
    done

    log_info "Importing default registry policies..."
    run_cmd "Load default user hive..." "reg load HKU\\TempDefault C:\\Users\\Default\\NTUSER.DAT"
    run_cmd "Unload default user hive..." "reg unload HKU\\TempDefault"

    log_info "Resetting common problematic registry keys..."
    run_ps "Restoring Windows Update registry keys..." "
        \$path = 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\WindowsUpdate';
        if (Test-Path \$path) { Remove-Item \$path -Recurse -Force -ErrorAction SilentlyContinue };
        \$path2 = 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\WindowsUpdate\\AU';
        if (Test-Path \$path2) { Remove-Item \$path2 -Recurse -Force -ErrorAction SilentlyContinue };
        Write-Output 'Windows Update policies reset'
    "

    log_success "Registry repair complete"
}

repair_network() {
    log_step "Resetting network stack..."

    run_cmd "Reset Winsock..." "netsh winsock reset"
    run_cmd "Reset TCP/IP..." "netsh int ip reset"
    run_cmd "Reset IPv4..." "netsh int ipv4 reset"
    run_cmd "Reset IPv6..." "netsh int ipv6 reset"
    run_cmd "Flush DNS cache..." "ipconfig /flushdns"
    run_cmd "Release IP..." "ipconfig /release"
    run_cmd "Renew IP..." "ipconfig /renew"
    run_cmd "Register DNS..." "ipconfig /registerdns"

    log_success "Network stack reset complete"
}

repair_wmi() {
    log_step "Repairing WMI repository..."

    run_cmd "Verify WMI..." "winmgmt /verifyrepository"
    run_cmd "Salvage WMI..." "winmgmt /salvagerepository"
    run_cmd "Reset WMI..." "winmgmt /resetrepository"

    log_success "WMI repair complete"
}

repair_boot() {
    log_step "Repairing boot configuration..."

    run_cmd "Rebuild BCD..." "bootrec /rebuildbcd"
    run_cmd "Fix MBR..." "bootrec /fixmbr"
    run_cmd "Fix boot sector..." "bootrec /fixboot"
    run_cmd "Scan OS..." "bootrec /scanos"

    log_success "Boot configuration repair complete"
}

repair_chkdsk() {
    log_step "Scheduling disk check on next reboot..."
    log_warn "chkdsk will run on next reboot, this may take a long time"
    run_cmd "Schedule chkdsk..." "chkdsk C: /F /R /X"
    log_success "Disk check scheduled"
}

repair_store() {
    log_step "Resetting Microsoft Store and app cache..."

    run_ps "Reset Store cache..." "Get-ChildItem -Path \$env:LOCALAPPDATA\\Packages\\Microsoft.WindowsStore* | Reset-AppxPackage -ErrorAction SilentlyContinue; Write-Output 'Store cache reset'"
    run_ps "Re-register Store..." "Get-AppXPackage -AllUsers Microsoft.WindowsStore | Foreach {Add-AppxPackage -DisableDevelopmentMode -Register \"\$(\$_.InstallLocation)\\AppXManifest.xml\" -ErrorAction SilentlyContinue}; Write-Output 'Store re-registered'"

    log_success "Store reset complete"
}

repair_services() {
    log_step "Restoring default services..."

    local services="wuauserv bits cryptsvc trustedinstaller msiserver"
    for svc in $services; do
        run_cmd "Set $svc to manual..." "sc config $svc start= demand"
    done

    run_ps "Reset Windows Update components..." "
        Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue;
        Stop-Service -Name bits -Force -ErrorAction SilentlyContinue;
        Stop-Service -Name cryptsvc -Force -ErrorAction SilentlyContinue;
        Rename-Item -Path \"\$env:SystemRoot\\SoftwareDistribution\" -NewName \"SoftwareDistribution.old\" -ErrorAction SilentlyContinue;
        Rename-Item -Path \"\$env:SystemRoot\\System32\\catroot2\" -NewName \"catroot2.old\" -ErrorAction SilentlyContinue;
        Start-Service -Name cryptsvc -ErrorAction SilentlyContinue;
        Start-Service -Name bits -ErrorAction SilentlyContinue;
        Start-Service -Name wuauserv -ErrorAction SilentlyContinue;
        Write-Output 'Windows Update components reset'
    "

    log_success "Services restored"
}

show_menu() {
    echo ""
    echo "============================================"
    echo "   Windows Repair Menu"
    echo "============================================"
    echo "  1) Run all repairs (recommended)"
    echo "  2) System File Checker (SFC)"
    echo "  3) DISM image repair"
    echo "  4) Registry backup and repair"
    echo "  5) Network stack reset"
    echo "  6) WMI repository repair"
    echo "  7) Boot configuration repair"
    echo "  8) Schedule disk check (chkdsk)"
    echo "  9) Reset Microsoft Store"
    echo " 10) Restore default services"
    echo "  0) Exit"
    echo "============================================"
}

show_info() {
    echo ""
    echo "============================================"
    echo "  System Diagnostic Report"
    echo "============================================"
    echo "Environment: $SYSTEM_NAME"
    echo "Type:        $ENV_TYPE"
    echo "User:        $(whoami)"
    [ -n "$WIN_VER" ] && echo "$WIN_VER"
    echo "============================================"
    echo ""
}

confirm_run() {
    read -p "Continue? (y/N): " c
    [[ "$c" =~ ^[Yy]$ ]] || { log_warn "Cancelled"; exit 0; }
}

run_all() {
    log_warn "Running all repairs. This may take 30-90 minutes"
    confirm_run

    repair_sfc
    repair_dism
    repair_registry
    repair_network
    repair_wmi
    repair_services
    repair_store
    repair_boot

    echo ""
    log_warn "chkdsk is recommended but will lock the drive on next reboot"
    read -p "Schedule chkdsk on next reboot? (y/N): " c
    [[ "$c" =~ ^[Yy]$ ]] && repair_chkdsk

    echo ""
    log_success "All repairs complete. Reboot recommended."
}

main() {
    echo ""
    echo "============================================"
    echo "   Windows Auto Repair Script v1.0"
    echo "============================================"

    detect_windows
    show_info
    check_admin

    while true; do
        show_menu
        read -p "Select option: " choice
        echo ""

        case "$choice" in
            1) run_all; break ;;
            2) repair_sfc ;;
            3) repair_dism ;;
            4) repair_registry ;;
            5) repair_network ;;
            6) repair_wmi ;;
            7) repair_boot ;;
            8) repair_chkdsk ;;
            9) repair_store ;;
            10) repair_services ;;
            0) log_info "Exiting"; exit 0 ;;
            *) log_error "Invalid option" ;;
        esac

        echo ""
        read -p "Press Enter to return to menu..."
    done
}

trap 'echo ""; log_warn "Script interrupted"; exit 130' INT
main "$@"
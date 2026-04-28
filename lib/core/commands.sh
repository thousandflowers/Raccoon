#!/bin/bash 

VERSION="0.1.0"
TAGLINE="macOS companion toolkit"

MENU_ITEMS=(
    "upgrade:Update packages"
    "audit:Security audit (quick)"
    "audit deep:Security audit (full)"
    "network:Network info"
    "disk:Disk space"
    "memory:Memory usage"
    "---"
    "audit quiet:audit --quiet"
    "audit fix:audit --fix"
    "audit json:audit --json"
    "audit history:audit --history"
    "audit watch:audit --watch"
    "---"
    "ssh:SSH keys"
    "git:Git repos"
    "ports:Open ports"
    "battery:Battery health"
    "backup:Time Machine"
    "env:Environment"
    "startup:Launch agents"
    "trash:Trash"
    "fonts:Fonts"
    "history:Shell history"
    "certs:SSL certificates"
    "docker:Docker"
    "xcode:Xcode"
)

TOTAL_OPTIONS=25

show_version() {
    echo "Raccoon version ${VERSION}"
    echo "macOS companion toolkit"
    echo ""
    echo "Commands:"
    for item in "${MENU_ITEMS[@]}"; do
        [[ "$item" == "---" ]] && continue
        echo "  rcc $item"
    done
    echo ""
    echo "Run 'rcc' for interactive menu"
}

show_help() {
    show_version
}

show_commands() {
    echo ""
    echo -e "${PURPLE_BOLD}Available commands:${NC}"
    echo ""
    printf "%-14s %s\n" "upgrade" "Update packages (brew, pip, npm, gem)"
    printf "%-14s %s\n" "audit" "Security audit (quick scan)"
    printf "%-14s %s\n" "audit deep" "Full security audit (32 checks)"
    printf "%-14s %s\n" "audit quiet" "Audit output: pass warn fail"
    printf "%-14s %s\n" "audit fix" "Auto-fix security issues"
    printf "%-14s %s\n" "audit json" "Audit in JSON format"
    printf "%-14s %s\n" "audit history" "Audit history with diff"
    printf "%-14s %s\n" "audit watch" "Schedule weekly audit"
    printf "%-14s %s\n" "network" "Network interfaces, Wi-Fi, DNS"
    printf "%-14s %s\n" "disk" "Disk space, APFS container"
    printf "%-14s %s\n" "memory" "Processes by RAM usage"
    printf "%-14s %s\n" "ssh" "SSH key management"
    printf "%-14s %s\n" "git" "Git workflow helpers"
    printf "%-14s %s\n" "ports" "Open ports and listeners"
    printf "%-14s %s\n" "battery" "Battery health, cycles"
    printf "%-14s %s\n" "backup" "Time Machine status"
    printf "%-14s %s\n" "env" "Shell environment"
    printf "%-14s %s\n" "startup" "Launch agents, login items"
    printf "%-14s %s\n" "trash" "Trash contents"
    printf "%-14s %s\n" "fonts" "Font duplicates"
    printf "%-14s %s\n" "history" "Shell history"
    printf "%-14s %s\n" "certs" "SSL certificates"
    printf "%-14s %s\n" "docker" "Docker images, containers"
    printf "%-14s %s\n" "xcode" "Xcode simulators"
    echo ""
    echo -e "${GRAY}Run '${GREEN}rcc${NC}' for interactive menu${NC}"
    echo -e "${GRAY}Run '${GREEN}rcc help${NC}' for full help${NC}"
}

show_brand_banner() {
    echo ""
    echo -e "${GREEN}     _${NC}"
    echo -e "${GREEN}   / \_/\_   ${NC}Raccoon ${TAGLINE}"
    echo -e "${GREEN}  ( o.o )  ${NC}"
    echo -e "${GREEN}   > ^ <${NC}"
    echo ""
}

run_cmd() {
    local c="$1"
    case "$c" in
        1) exec "${SCRIPT_DIR}/bin/upgrade.sh" ;;
        2) exec "${SCRIPT_DIR}/bin/audit.sh" ;;
        3) exec "${SCRIPT_DIR}/bin/audit.sh" --deep ;;
        4) exec "${SCRIPT_DIR}/bin/network.sh" ;;
        5) exec "${SCRIPT_DIR}/bin/disk.sh" ;;
        6) exec "${SCRIPT_DIR}/bin/memory.sh" ;;
        7) exec "${SCRIPT_DIR}/bin/audit.sh" --deep --quiet ;;
        8) exec "${SCRIPT_DIR}/bin/audit.sh" --deep --fix ;;
        9) exec "${SCRIPT_DIR}/bin/audit.sh" --deep --json ;;
        10) exec "${SCRIPT_DIR}/bin/audit.sh" --history ;;
        11) exec "${SCRIPT_DIR}/bin/audit.sh" --watch ;;
        13) exec "${SCRIPT_DIR}/bin/ssh.sh" ;;
        14) exec "${SCRIPT_DIR}/bin/git.sh" ;;
        15) exec "${SCRIPT_DIR}/bin/ports.sh" ;;
        16) exec "${SCRIPT_DIR}/bin/battery.sh" ;;
        17) exec "${SCRIPT_DIR}/bin/backup.sh" ;;
        18) exec "${SCRIPT_DIR}/bin/env.sh" ;;
        19) exec "${SCRIPT_DIR}/bin/startup.sh" ;;
        20) exec "${SCRIPT_DIR}/bin/trash.sh" ;;
        21) exec "${SCRIPT_DIR}/bin/fonts.sh" ;;
        22) exec "${SCRIPT_DIR}/bin/history.sh" ;;
        23) exec "${SCRIPT_DIR}/bin/certs.sh" ;;
        24) exec "${SCRIPT_DIR}/bin/docker.sh" ;;
        25) exec "${SCRIPT_DIR}/bin/xcode.sh" ;;
    esac
}

show_menu() {
    local sel="$1"
    local n=1
    
    while [[ $n -le $TOTAL_OPTIONS ]]; do
        local item="${MENU_ITEMS[$((n-1))]}"
        
        if [[ "$item" == "---" ]]; then
            echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        else
            if [[ $n -eq $sel ]]; then
                echo -e "${GREEN}▶ $n. $item${NC}"
            else
                echo "  $n. $item"
            fi
        fi
        n=$((n+1))
    done
    
    echo ""
    echo -e "${GRAY}↑↓ Navigate | Enter | Q Quit${NC}"
}

interactive_main_menu() {
    local cur=1
    
    trap 'exit 0' INT
    
    if tput setaf 1 >/dev/null 2>&1; then
        tput clear
    else
        printf $'\033[2J\033[H]'
    fi
    show_brand_banner
    
    while true; do
        show_menu $cur
        read -r -s -n 1 key
        case "$key" in
            $'\x1b')
                read -r -s -n 1 t
                [[ "$t" == "[" ]] || continue
                read -r -s -n 1 t
                [[ "$t" == "A" ]] && ((cur > 1)) && cur=$((cur-1))
                [[ "$t" == "B" ]] && ((cur < TOTAL_OPTIONS)) && cur=$((cur+1))
                [[ $cur -eq 7 || $cur -eq 12 ]] && [[ "$t" == "A" ]] && cur=$((cur-1))
                [[ $cur -eq 7 || $cur -eq 12 ]] && [[ "$t" == "B" ]] && cur=$((cur+1))
                ;;
            "") run_cmd $cur ;;
            q|Q) exit 0 ;;
        esac
        
        if tput setaf 1 >/dev/null 2>&1; then
            tput home
        else
            printf $'\033[H]'
        fi
    done
}
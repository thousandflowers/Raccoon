#!/bin/bash

VERSION="0.5.0"
TAGLINE="macOS companion toolkit"

reset_terminal() {
    tput reset 2>/dev/null || printf '\033[?25h\033[0m\033[2J\033[H'
}

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

# Used by the bash fallback menu (when Go UI is not available)
# SCRIPT_DIR is inherited from rcc which sources this file
run_cmd() {
    # Reset completo del terminale prima di ogni comando
    printf '\r'
    printf '\033[2J\033[H'
    printf '\033[0m'
    printf '\033[?25h'
    stty sane
    
    local c="$1"
    set +e
    case "$c" in
        1) "${SCRIPT_DIR}/bin/upgrade.sh" ;;
        2) "${SCRIPT_DIR}/bin/audit.sh" ;;
        3) "${SCRIPT_DIR}/bin/audit.sh" --deep ;;
        4) "${SCRIPT_DIR}/bin/network.sh" ;;
        5) "${SCRIPT_DIR}/bin/disk.sh" ;;
        6) "${SCRIPT_DIR}/bin/memory.sh" ;;
        7) "${SCRIPT_DIR}/bin/audit.sh" --deep --quiet ;;
        8) "${SCRIPT_DIR}/bin/audit.sh" --deep --fix ;;
        9) "${SCRIPT_DIR}/bin/audit.sh" --deep --json ;;
        10) "${SCRIPT_DIR}/bin/audit.sh" --history ;;
        11) "${SCRIPT_DIR}/bin/audit.sh" --watch ;;
        13) "${SCRIPT_DIR}/bin/ssh.sh" ;;
        14) "${SCRIPT_DIR}/bin/git.sh" ;;
        15) "${SCRIPT_DIR}/bin/ports.sh" ;;
        16) "${SCRIPT_DIR}/bin/battery.sh" ;;
        17) "${SCRIPT_DIR}/bin/backup.sh" ;;
        18) "${SCRIPT_DIR}/bin/env.sh" ;;
        19) "${SCRIPT_DIR}/bin/startup.sh" ;;
        20) "${SCRIPT_DIR}/bin/trash.sh" ;;
        21) "${SCRIPT_DIR}/bin/fonts.sh" ;;
        22) "${SCRIPT_DIR}/bin/history.sh" ;;
        23) "${SCRIPT_DIR}/bin/certs.sh" ;;
        24) "${SCRIPT_DIR}/bin/docker.sh" ;;
        25) "${SCRIPT_DIR}/bin/xcode.sh" ;;
    esac
    set -e
}

show_menu() {
    local sel="$1"
    local n=1
    
    while [[ $n -le $TOTAL_OPTIONS ]]; do
        local item="${MENU_ITEMS[$((n-1))]}"
        
        if [[ "$item" == "---" ]]; then
            echo -e "${GRAY}────────────────────────────────${NC}"
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
    echo -e "${GRAY}↑↓ Navigate · Enter Run · / Search · Q Quit${NC}"
}

_filter_menu_items() {
    local query="$1"
    local lower_query
    lower_query=$(echo "$query" | tr '[:upper:]' '[:lower:]')
    
    local -a filtered=()
    local n=1
    while [[ $n -le $TOTAL_OPTIONS ]]; do
        local item="${MENU_ITEMS[$((n-1))]}"
        if [[ "$item" != "---" ]]; then
            local lower_item
            lower_item=$(echo "$item" | tr '[:upper:]' '[:lower:]')
            if [[ "$lower_item" == *"$lower_query"* ]]; then
                filtered+=("$n:$item")
            fi
        fi
        n=$((n+1))
    done
    
    echo "${filtered[@]}"
}

_show_filtered_menu() {
    local -a items=("$@")
    local sel="${items[0]}"
    items=("${items[@]:1}")
    
    local n=1
    for item in "${items[@]}"; do
        local orig_idx="${item%%:*}"
        local rest="${item#*:}"
        
        if [[ $n -eq $sel ]]; then
            echo -e "${GREEN}▶ $n. $rest${NC}"
        else
            echo "  $n. $rest"
        fi
        n=$((n+1))
    done
    
    echo ""
    echo -e "${GRAY}↑↓ Navigate | Enter | Esc Cancel${NC}"
}

_search_and_run() {
    echo ""
    echo -n "Search: "
    read -r query
    
    if [[ -z "$query" ]]; then
        return 1
    fi
    
    local result
    result=$(_filter_menu_items "$query")
    read -ra filtered <<< "$result"
    
    if [[ ${#filtered[@]} -eq 0 ]]; then
        echo ""
        echo -e "${YELLOW}No matches found${NC}"
        echo ""
        echo -n "Press any key to continue..."
        read -r -s -n 1
        return 1
    fi
    
    if [[ ${#filtered[@]} -eq 1 ]]; then
        local orig_idx="${filtered[0]%%:*}"
        run_cmd "$orig_idx"
        return 0
    fi
    
    local sel=1
    while true; do
        clear >/dev/null 2>&1 || tput clear >/dev/null 2>&1 || printf $'\033[2J\033[H]'
        show_brand_banner
        _show_filtered_menu "$sel" "${filtered[@]}"
        
        read -r -s -n 1 key
        case "$key" in
            $'\x1b')
                read -r -s -n 1 t
                [[ "$t" == "[" ]] || continue
                read -r -s -n 1 t
                [[ "$t" == "A" ]] && ((sel > 1)) && sel=$((sel-1))
                [[ "$t" == "B" ]] && ((sel < ${#filtered[@]})) && sel=$((sel+1))
                ;;
            "")
                local chosen="${filtered[$((sel-1))]}"
                local orig_idx="${chosen%%:*}"
                run_cmd "$orig_idx"
                return 0
                ;;
            $'\x03'|q|Q)
                return 1
                ;;
        esac
    done
}

_is_separator() {
    local idx="$1"
    [[ $idx -ge 1 && $idx -le $TOTAL_OPTIONS ]] || return 1
    local item="${MENU_ITEMS[$((idx-1))]}"
    [[ "$item" == "---" ]]
}

_prev_menu_item() {
    local cur="$1"
    while ((cur > 1)); do
        ((cur--))
        _is_separator "$cur" || { echo "$cur"; return 0; }
    done
    echo "$cur"
}

_next_menu_item() {
    local cur="$1"
    while ((cur < TOTAL_OPTIONS)); do
        ((cur++))
        _is_separator "$cur" || { echo "$cur"; return 0; }
    done
    echo "$cur"
}

interactive_main_menu() {
    local cur=1
    
    trap 'exit 0' INT
    
    printf '\033[2J\033[H'
    show_brand_banner
    show_menu $cur
    
    while true; do
        printf '\033[H\033[J'
        show_brand_banner
        show_menu "$cur"
        
        read -r -s -n 1 key
        case "$key" in
            $'\x1b')
                read -r -s -n 1 t
                [[ "$t" == "[" ]] || continue
                read -r -s -n 1 t
                [[ "$t" == "A" ]] && cur=$(_prev_menu_item "$cur")
                [[ "$t" == "B" ]] && cur=$(_next_menu_item "$cur")
                ;;
            "") run_cmd "$cur" ;;
            /)
                _search_and_run
                printf '\033[2J\033[H'
                show_brand_banner
                show_menu "$cur"
                ;;
            q|Q) exit 0 ;;
        esac
    done
}
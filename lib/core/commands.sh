#!/bin/bash

VERSION="0.1.0"
TAGLINE="Mac companion toolkit. Beyond Mole's scope."

declare -a RCC_COMMANDS=(
    "git:Check local git repositories"
    "upgrade:Update package managers"
    "ports:Show open ports and listeners"
    "battery:Battery health and cycle count"
    "backup:Verify Time Machine status"
    "env:Check environment and PATH"
)

show_brand_banner() {
    cat << EOF
${GREEN}     _
${GREEN}   / \\_/\\_   ${NC}Raccoon
${GREEN}  ( o.o )   ${NC}${TAGLINE}
${GREEN}   > ^ <

EOF
}

show_version() {
    echo "Raccoon version ${VERSION}"
    echo "macOS companion toolkit"
    echo ""
}

show_help() {
    show_brand_banner
    echo "Commands:"
    for entry in "${RCC_COMMANDS[@]}"; do
        local name="${entry%%:*}"
        local desc="${entry#*:}"
        printf "  %-12s %s\n" "rcc $name" "$desc"
    done
    echo ""
    printf "  %-12s %s\n" "rcc help" "Show this help"
    printf "  %-12s %s\n" "rcc --version" "Show version"
    echo ""
    echo "Use 'rcc' without arguments for interactive menu"
}

show_main_menu() {
    local selected="${1:-1}"

    printf '\033[2J\033[H'

    while IFS= read -r line || [[ -n "$line" ]]; do
        printf '\r\033[2K%s\n' "$line"
    done <<< "$(show_brand_banner)"

    printf '\r\033[2K\n'

    local idx=1
    local desc=""
printf '\r\033[2K%s\n' "$(show_menu_option 1 "git       Check local git repos" "$([[ $selected -eq 1 ]] && echo true || echo false)")"
	printf '\r\033[2K%s\n' "$(show_menu_option 2 "upgrade   Update package managers" "$([[ $selected -eq 2 ]] && echo true || echo false)")"
	printf '\r\033[2K%s\n' "$(show_menu_option 3 "ports     Show open ports/listeners" "$([[ $selected -eq 3 ]] && echo true || echo false)")"
	printf '\r\033[2K%s\n' "$(show_menu_option 4 "battery   Battery health & cycle count" "$([[ $selected -eq 4 ]] && echo true || echo false)")"
	printf '\r\033[2K%s\n' "$(show_menu_option 5 "backup    Verify Time Machine status" "$([[ $selected -eq 5 ]] && echo true || echo false)")"
	printf '\r\033[2K%s\n' "$(show_menu_option 6 "env       Check environment" "$([[ $selected -eq 6 ]] && echo true || echo false)")"
	printf '\r\033[2K%s\n' "$(show_menu_option 7 "help      Show help" "$([[ $selected -eq 7 ]] && echo true || echo false)")"
	printf '\r\033[2K%s\n' "$(show_menu_option 8 "quit      Exit" "$([[ $selected -eq 8 ]] && echo true || echo false)")"

    if [[ -t 0 ]]; then
        printf '\r\033[2K\n'
        printf '\r\033[2K%s\n' "${GRAY}↑↓  |  Enter  |  Q Quit${NC}"
        printf '\r\033[2K\n'
    fi

    printf '\033[J'
}

interactive_main_menu() {
    local current_option=1

    cleanup_and_exit() {
        show_cursor
        exit 0
    }

    trap cleanup_and_exit INT
    hide_cursor

    while true; do
        show_main_menu $current_option

        local key
        if ! key=$(read_key); then
            continue
        fi

        case "$key" in
            "UP") ((current_option > 1)) && ((current_option--)) ;;
            "DOWN") ((current_option < 8)) && ((current_option++)) ;;
            "ENTER")
                show_cursor
                case $current_option in
                    1) exec "${SCRIPT_DIR}/bin/git.sh" ;;
                    2) exec "${SCRIPT_DIR}/bin/upgrade.sh" ;;
                    3) exec "${SCRIPT_DIR}/bin/ports.sh" ;;
                    4) exec "${SCRIPT_DIR}/bin/battery.sh" ;;
                    5) exec "${SCRIPT_DIR}/bin/backup.sh" ;;
                    6) exec "${SCRIPT_DIR}/bin/env.sh" ;;
                    7) show_help; exit 0 ;;
                    8) cleanup_and_exit ;;
                esac
                ;;
            "CHAR:1") show_cursor; exec "${SCRIPT_DIR}/bin/git.sh" ;;
            "CHAR:2") show_cursor; exec "${SCRIPT_DIR}/bin/upgrade.sh" ;;
            "CHAR:3") show_cursor; exec "${SCRIPT_DIR}/bin/ports.sh" ;;
            "CHAR:4") show_cursor; exec "${SCRIPT_DIR}/bin/battery.sh" ;;
            "CHAR:5") show_cursor; exec "${SCRIPT_DIR}/bin/backup.sh" ;;
            "CHAR:6") show_cursor; exec "${SCRIPT_DIR}/bin/env.sh" ;;
            "CHAR:7") show_cursor; show_help; exit 0 ;;
            "CHAR:8") cleanup_and_exit ;;
            "QUIT") cleanup_and_exit ;;
        esac

        drain_pending_input
    done
}
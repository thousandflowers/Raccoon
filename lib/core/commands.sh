#!/bin/bash

# Version resolution, most-authoritative first:
#   1. a VERSION file stamped by the Homebrew formula (always the installed tag)
#   2. git describe in a real checkout (dev)
#   3. a generic dev fallback
# The .git guard stops git describe from walking UP into an enclosing repo
# (e.g. Homebrew's own /opt/homebrew/.git -> reported "6.0.2"). The `|| true`
# stops `set -euo pipefail` from aborting when git describe fails, e.g. a CI
# shallow checkout that has no tags.
__rcc_root="${BASH_SOURCE[0]%/*}/../.."
if [ -f "${__rcc_root}/VERSION" ]; then
	VERSION="$(cat "${__rcc_root}/VERSION" 2>/dev/null || true)"
elif [ -e "${__rcc_root}/.git" ]; then
	VERSION="$(git -C "${__rcc_root}" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
fi
VERSION="${VERSION:-dev}"
unset __rcc_root

TAGLINE="macOS companion toolkit"

reset_terminal() {
    tput reset 2>/dev/null || printf '\033[?25h\033[0m\033[2J\033[H'
}

MENU_ITEMS=(
    "upgrade:Update packages"
    "apps:Update GUI apps (App Store + casks)"
    "audit:Security audit (quick)"
    "audit deep:Security audit (full)"
    "network:Network info"
    "wifi:Wi-Fi and passwords"
    "disk:Disk space"
    "memory:Memory usage"
    "---"
    "audit quiet:audit --quiet"
    "audit fix:audit --fix"
    "audit json:audit --json"
    "audit history:audit --history"
    "audit watch:audit --watch"
    "fleet:Audit Mac fleet via SSH"
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

TOTAL_OPTIONS=${#MENU_ITEMS[@]}

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

# Mini sparkline of the last 7 audits under the banner: ● = no failures,
# ○ = had failures. Shown only with >=2 audits on record. JSON parsed with grep
# (no jq); ANSI suppressed when stdout is not a terminal (pipe-safe).
show_health_history() {
    local dir="$HOME/.raccoon/audit-history"
    [[ -d "$dir" ]] || return 0
    local files count
    files="$(ls "$dir"/audit_*.json 2>/dev/null | sort | tail -7 || true)"
    [[ -z "$files" ]] && return 0
    count="$(printf '%s\n' "$files" | grep -c . || true)"
    [[ "$count" -lt 2 ]] && return 0

    local dots="" passed=0 last_file="" f fail use_color=1
    [[ -t 1 ]] || use_color=0
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        last_file="$f"
        fail="$(grep -o '"fail": [0-9]*' "$f" | grep -o '[0-9]*' | head -1 || true)"
        [[ -z "$fail" ]] && fail=0
        if [[ "$fail" -eq 0 ]]; then
            passed=$((passed + 1))
            [[ $use_color -eq 1 ]] && dots+="${GREEN}●${NC}" || dots+="●"
        else
            [[ $use_color -eq 1 ]] && dots+="${YELLOW}○${NC}" || dots+="○"
        fi
    done <<< "$files"

    # Relative date of the most recent audit, from its filename.
    local base lastdate today yday rel
    base="$(basename "$last_file")"
    lastdate="${base#audit_}"; lastdate="${lastdate%%_*}"
    today="$(date +%Y-%m-%d)"
    yday="$(date -v-1d +%Y-%m-%d 2>/dev/null || echo "")"
    if [[ "$lastdate" == "$today" ]]; then
        rel="today"
    elif [[ -n "$yday" && "$lastdate" == "$yday" ]]; then
        rel="yesterday"
    else
        rel="$(printf '%s' "$lastdate" | awk -F- '{print $3"/"$2}')"
    fi

    echo "  Last audits: ${dots} (${passed}/${count} · last: ${rel})"
}

show_brand_banner() {
    echo ""
    echo -e "${GREEN}     _${NC}"
    echo -e "${GREEN}   / \_/\_   ${NC}Raccoon ${TAGLINE}"
    echo -e "${GREEN}  ( o.o )  ${NC}"
    echo -e "${GREEN}   > ^ <${NC}"
    show_health_history
    echo ""
}

# Used by the bash fallback menu (when Go UI is not available)
# SCRIPT_DIR is inherited from rcc which sources this file
run_cmd() {
    # Full terminal reset before each command
    printf '\r'
    printf '\033[2J\033[H'
    printf '\033[0m'
    printf '\033[?25h'
    stty sane
    
    # Data-driven: look up the command for this 1-based MENU_ITEMS position and
    # run it through the rcc dispatcher. Inserting/removing menu items needs no
    # change here, and "---" separators carry no command.
    local item="${MENU_ITEMS[$(($1 - 1))]:-}"
    [[ -z "$item" || "$item" == "---" ]] && return 0
    local cmd="${item%%:*}"
    # shellcheck disable=SC2086  # intentional word split: "audit deep" -> 2 args
    exec "${SCRIPT_DIR}/rcc" $cmd
}

show_menu() {
    local sel="$1"
    local n=1
    
    while [[ $n -le $TOTAL_OPTIONS ]]; do
        local item="${MENU_ITEMS[$((n-1))]}"
        
        if [[ "$item" == "---" ]]; then
            echo -e "${GRAY}--------------------------------${NC}"
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
    
    # One item per line: items contain spaces, so a space-joined echo would be
    # re-split word-by-word by the caller and corrupt every multi-word entry.
    if [[ ${#filtered[@]} -gt 0 ]]; then
        printf '%s\n' "${filtered[@]}"
    fi
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
    # Read newline-delimited items; read -ra would split on spaces inside items.
    local -a filtered=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && filtered+=("$line")
    done <<< "$result"
    
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
        clear >/dev/null 2>&1 || tput clear >/dev/null 2>&1 || printf $'\033[2J\033[H'
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

# Render the first-run welcome box. Split out from show_onboarding so it can be
# tested without a TTY. BOX_INNER inner width; sides are 1-cell box-drawing chars.
# ponytail: assumes a UTF-8 terminal for the one emoji line (true — onboarding
# only runs interactively); the -1 pad compensates for the glyph's double width.
_render_onboarding() {
    local BOX_INNER=45 border="" i
    for ((i = 0; i < BOX_INNER; i++)); do border+="─"; done

    _ob_row() {
        local text="$1" adj="${2:-0}" pad
        pad=$((BOX_INNER - ${#text} + adj))
        [[ $pad -lt 0 ]] && pad=0
        printf '│%s%*s│\n' "$text" "$pad" ""
    }

    echo ""
    echo "┌${border}┐"
    _ob_row "  🦝 Welcome to Raccoon" -1
    _ob_row ""
    _ob_row "  Three things you can do now:"
    _ob_row ""
    _ob_row "  rcc audit    — 30+ security checks"
    _ob_row "  rcc upgrade  — upgrade everything at once"
    _ob_row "  rcc wifi     — Wi-Fi networks and passwords"
    _ob_row ""
    _ob_row "  Navigate with arrows, Enter to run."
    _ob_row "  Press any key to continue..."
    echo "└${border}┘"
}

# First-run wizard. Shown once, guarded by the ~/.raccoon/onboarded sentinel and
# only when stdin is a TTY — piped/non-interactive use skips with zero overhead.
show_onboarding() {
    [[ -f "$HOME/.raccoon/onboarded" ]] && return 0
    [[ -t 0 ]] || return 0
    _render_onboarding
    read -r -s -n 1 -t 10 _ || true
    mkdir -p "$HOME/.raccoon"
    touch "$HOME/.raccoon/onboarded"
    clear >/dev/null 2>&1 || tput clear >/dev/null 2>&1 || printf '\033[2J\033[H'
}

interactive_main_menu() {
    show_onboarding
    local cur=1
    
    trap 'exit 0' INT
    
    clear >/dev/null 2>&1 || tput clear >/dev/null 2>&1 || printf $'\033[2J\033[H'
    show_brand_banner
    
    while true; do
        clear >/dev/null 2>&1 || tput clear >/dev/null 2>&1 || printf $'\033[2J\033[H'
        show_brand_banner
        show_menu "$cur"
        
        read -r -s -n 1 key
        case "$key" in
            $'\x1b')
                read -r -s -n 1 t
                [[ "$t" == "[" ]] || continue
                read -r -s -n 1 t
                [[ "$t" == "A" ]] && ((cur > 1)) && cur=$((cur-1))
                [[ "$t" == "B" ]] && ((cur < TOTAL_OPTIONS)) && cur=$((cur+1))
                # Skip over separators ("---") wherever they are, no hardcoded
                # positions (positions shift as menu items are added/removed).
                if _is_separator "$cur"; then
                    [[ "$t" == "A" ]] && cur=$((cur-1))
                    [[ "$t" == "B" ]] && cur=$((cur+1))
                fi
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
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

# Everything rcc can be asked to do, in one array, because three consumers read
# this list and want different things from it: the interactive menu, `rcc --help`
# via show_help, and raycast/generate.sh, which parses that help. They used to
# share a single array shaped for the menu, which is how the two menus drifted
# apart and how the generator broke. The split is a field, not a second array:
# two lists of the same commands is the problem, not the fix.
#
#   name : where : description
#
#   where = both   a command. Menu and `rcc --help`.
#           help   a way of launching a command, not a command. `rcc --help`
#                  and the man page only, because a menu lists commands, not
#                  flags. The flags themselves are documented in
#                  `rcc audit --help`.
#           menu   the category headings. They never reach `rcc --help`, so its
#                  two-column format stays exactly what generate.sh parses and
#                  the generator needs to learn nothing.
#
# The order is the menu's, and `rcc --help` follows it: it is one editorial
# decision, not two. Within a category the first entry is that category's
# principal command, so the order is deliberately not alphabetical.
RCC_ENTRIES=(
    "== Maintenance:menu:"
    "audit:both:Security audit (quick)"
    "audit deep:help:Security audit (full)"
    "audit quiet:help:audit --quiet"
    "audit fix:help:audit --fix"
    "audit json:help:audit --json"
    "audit history:help:audit --history"
    "audit watch:help:audit --watch"
    "upgrade:both:Update packages"
    "apps:both:Update GUI apps (App Store + casks)"
    "backup:both:Time Machine"
    "trash:both:Trash"
    "== System:menu:"
    "disk:both:Disk space"
    "memory:both:Memory usage"
    "battery:both:Battery health"
    "startup:both:Launch agents"
    "fonts:both:Fonts"
    "== Network:menu:"
    "network:both:Network info"
    "wifi:both:Wi-Fi and passwords"
    "ports:both:Open ports"
    "certs:both:SSL certificates"
    "ssh:both:SSH keys"
    "fleet:both:Audit Mac fleet via SSH"
    "== Development:menu:"
    "git:both:Git repos"
    "docker:both:Docker"
    "xcode:both:Xcode"
    "env:both:Environment"
    "overlap:both:PATH package-manager map"
    "history:both:Shell history"
)

# Derived, never written by hand, and both keep the "name:description" shape
# every existing consumer already parses. MENU_ITEMS additionally carries the
# "== Label" heading rows, which show_menu renders as a rule and run_cmd and
# _filter_menu_items skip, the way they already skipped "---".
#
# The menu has no second level: `fleet` is one row that runs `rcc fleet`, whose
# default prints its eight subcommands. The Go TUI expands fleet in place
# instead. The asymmetry is deliberate — the bash menu indexes MENU_ITEMS
# positionally in three functions, and a second index space there is not worth
# it for one command in the fallback interface.
MENU_ITEMS=()
RCC_HELP_ITEMS=()
_rcc_build_lists() {
    local entry name rest where desc
    for entry in "${RCC_ENTRIES[@]}"; do
        name="${entry%%:*}"
        rest="${entry#*:}"
        where="${rest%%:*}"
        desc="${rest#*:}"
        case "$where" in
            both)
                MENU_ITEMS+=("${name}:${desc}")
                RCC_HELP_ITEMS+=("${name}:${desc}")
                ;;
            help) RCC_HELP_ITEMS+=("${name}:${desc}") ;;
            menu) MENU_ITEMS+=("$name") ;;
        esac
    done
}
_rcc_build_lists

# One JSON string escape for every command that emits JSON. It lived twice, in
# audit.sh and wifi.sh, and the third copy was going to be the one that forgot
# the backslash. Backslash first: escaping quotes first would then escape the
# backslashes it just added.
rcc_json_string() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\n'/\\n}"
    printf '"%s"' "$s"
}

TOTAL_OPTIONS=${#MENU_ITEMS[@]}

show_version() {
    echo "Raccoon version ${VERSION}"
    echo "macOS companion toolkit"
}

# RCC_HELP_ITEMS entries are "name:description"; printing them raw put the colon
# in front of the user. Split on the first one and pad the names to the longest,
# computed rather than fixed so a new command can never break the column.
#
# Two columns, no headings: raycast/generate.sh parses this output, and keeping
# the category rows out of it means the generator needs to learn nothing.
show_help() {
    local item name width=0
    for item in "${RCC_HELP_ITEMS[@]}"; do
        name="${item%%:*}"
        if (( ${#name} > width )); then width=${#name}; fi
    done

    show_version
    echo ""
    echo "Commands:"
    for item in "${RCC_HELP_ITEMS[@]}"; do
        printf '  rcc %-*s  %s\n' "$width" "${item%%:*}" "${item#*:}"
    done
    echo ""
    echo "Run 'rcc' for interactive menu"
}

# Mini sparkline of the last 7 audits under the banner: ● = no failures,
# ○ = had failures. Shown only with >=2 audits on record. JSON parsed with grep
# (no jq); ANSI suppressed when stdout is not a terminal (pipe-safe).
show_health_history() {
    local dir="$HOME/.raccoon/audit-history"
    [[ -d "$dir" ]] || return 0
    local files count
    # shellcheck disable=SC2012  # our own timestamped files (audit_<ts>.json) — never contain spaces/newlines, so ls|sort is safe and simplest
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
    echo -e "${GREEN}${NC}"
    echo -e "${GREEN}   n___n   ${NC}Raccoon ${TAGLINE}"
    echo -e "${GREEN}  [ o.o ]  ${NC}"
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
    [[ -z "$item" || "$item" == "---" || "$item" == "== "* ]] && return 0
    local cmd="${item%%:*}"
    # shellcheck disable=SC2086  # intentional word split: "audit deep" -> 2 args
    exec "${SCRIPT_DIR}/rcc" $cmd
}

# A category heading: the label, then a rule of dashes out to a fixed width, so
# the four groups read as groups without costing more than one row each.
_rcc_menu_heading() {
    local label="$1" width=32 fill
    fill=$(( width - ${#label} - 4 ))
    (( fill < 0 )) && fill=0
    printf '%b-- %s %s%b\n' "${GRAY}" "$label" "$(printf '%*s' "$fill" '' | tr ' ' '-')" "${NC}"
}

show_menu() {
    local sel="$1"
    local n=1
    
    while [[ $n -le $TOTAL_OPTIONS ]]; do
        local item="${MENU_ITEMS[$((n-1))]}"
        
        if [[ "$item" == "---" ]]; then
            echo -e "${GRAY}--------------------------------${NC}"
        elif [[ "$item" == "== "* ]]; then
            _rcc_menu_heading "${item#== }"
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
        if [[ "$item" != "---" && "$item" != "== "* ]]; then
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
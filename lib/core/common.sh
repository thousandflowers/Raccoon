#!/bin/bash

# Colors
GREEN=$'\033[0;32m'
RED=$'\033[0;31m'
YELLOW=$'\033[0;33m'
GRAY=$'\033[0;90m'
PURPLE_BOLD=$'\033[1;35m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
NC=$'\033[0m'

# Icons
ICON_SUCCESS="${GREEN}✓${NC}"
ICON_ERROR="${RED}✗${NC}"
ICON_ARROW="${PURPLE_BOLD}➤${NC}"
ICON_SKIP="${GRAY}○${NC}"
ICON_DRY_RUN="${YELLOW}→${NC}"
ICON_LIST="${GRAY}▪${NC}"
ICON_REVIEW="${YELLOW}⚐${NC}"

# Spinner
SPINNER_PID=""
SPINNER_MSG=""

start_inline_spinner() {
    local msg="${1:-Loading...}"
    SPINNER_MSG="$msg"
    printf "%s " "$msg"
    (
        while true; do
            printf "%s" "${GRAY}█${NC}"
            sleep 0.1
        done
    ) &
    SPINNER_PID=$!
    disown
}

stop_inline_spinner() {
    if [[ -n "$SPINNER_PID" ]]; then
        kill "$SPINNER_PID" 2>/dev/null
        wait "$SPINNER_PID" 2>/dev/null
    fi
    SPINNER_PID=""
    printf "\r%s\n" "$(printf ' %.0s' {1..80})" | head -c 80
    printf "\r"
}

print_section_header() {
    local title="$1"
    echo ""
    echo "${PURPLE_BOLD}-- ${title}${NC}"
    echo ""
}

# Cursor control
clear_screen() { printf '\033[2J\033[H'; }
hide_cursor() { [[ -t 1 ]] && printf '\033[?25l' >&2 || true; }
show_cursor() { [[ -t 1 ]] && printf '\033[?25h' >&2 || true; }

# Read single keyboard input
read_key() {
    local key rest read_status
    IFS= read -r -s -n 1 key
    read_status=$?
    [[ $read_status -ne 0 ]] && {
        echo "QUIT"
        return 0
    }

    [[ -z "$key" ]] && {
        echo "ENTER"
        return 0
    }
    case "$key" in
        $'\n' | $'\r') echo "ENTER" ;;
        ' ') echo "SPACE" ;;
        'q' | 'Q') echo "QUIT" ;;
        'm' | 'M') echo "MORE" ;;
        'v' | 'V') echo "VERSION" ;;
        'j' | 'J') echo "DOWN" ;;
        'k' | 'K') echo "UP" ;;
        'h' | 'H') echo "LEFT" ;;
        'l' | 'L') echo "RIGHT" ;;
        $'\x03') echo "QUIT" ;;
        $'\x1b')
            if IFS= read -r -s -n 1 -t 1 rest 2> /dev/null; then
                if [[ "$rest" == "[" ]]; then
                    if IFS= read -r -s -n 1 -t 1 rest2 2> /dev/null; then
                        case "$rest2" in
                            "A") echo "UP" ;;
                            "B") echo "DOWN" ;;
                            "C") echo "RIGHT" ;;
                            "D") echo "LEFT" ;;
                            *) echo "OTHER" ;;
                        esac
                    else echo "QUIT"; fi
                else echo "QUIT"; fi
            else echo "QUIT"; fi
            ;;
        [[:print:]]) echo "CHAR:$key" ;;
        *) echo "OTHER" ;;
    esac
}

drain_pending_input() {
    local drained=0
    while IFS= read -r -s -n 1 -t 0.01 _ 2> /dev/null; do
        drained=$((drained + 1))
        [[ $drained -gt 100 ]] && break
    done
}

show_menu_option() {
    local number="$1"
    local text="$2"
    local selected="$3"

    if [[ "$selected" == "true" ]]; then
        echo -e "${CYAN}${ICON_ARROW} $number. $text${NC}"
    else
        echo "  $number. $text"
    fi
}

show_progress_bar() {
	local -a steps=("$@")
	local total=${#steps[@]}
	local current=0
	local -a failed=()
	local -a passed=()
	local is_tty=false

	[[ -t 1 ]] && is_tty=true

	if [[ $total -eq 0 ]]; then
		return 0
	fi

	local tmpfile
	tmpfile=$(mktemp)
	trap "rm -f $tmpfile" RETURN

	local bar_width=10

	render_bar() {
		local completed="$1"
		local label="$2"
		local filled=""
		local empty=""

		for ((i=0; i<bar_width; i++)); do
			if [[ $i -lt $completed ]]; then
				filled+="█"
			else
				empty+="░"
			fi
		done

		if [[ "$is_tty" == "true" ]]; then
			printf "\r[%s%s] %d/%d %s" "${GREEN}${filled}${NC}" "${GRAY}${empty}${NC}" "$completed" "$total" "$label"
		else
			printf "[%d/%d] %s" "$completed" "$total" "$label"
		fi
	}

	for step in "${steps[@]}"; do
		local label="${step%%:*}"
		local cmd="${step#*:}"

		((current++))

		if [[ "$is_tty" == "true" ]]; then
			render_bar $((current - 1)) "$label..."
		else
			echo -n "[${current}/${total}] ${label}... "
		fi

		if [[ -z "$cmd" ]] || [[ "$cmd" == "$label" ]]; then
			passed+=("$label")
			if [[ "$is_tty" != "true" ]]; then
				echo "${GREEN}done${NC}"
			else
				render_bar "$current" "done"
			fi
			continue
		fi

		local exit_code=0

		if [[ "$is_tty" == "true" ]]; then
			eval "$cmd" > "$tmpfile" 2>&1 || exit_code=$?
		else
			set +e
			eval "$cmd" 2>&1
			exit_code=$?
			set -e
		fi

		if [[ -s "$tmpfile" && "$is_tty" == "true" ]]; then
			printf "\n"
			cat "$tmpfile"
			printf "\n"
			render_bar "$current" "$label"
		fi

		if [[ $exit_code -eq 0 ]]; then
			passed+=("$label")
			if [[ "$is_tty" != "true" ]]; then
				echo "${GREEN}✓${NC}"
			else
				render_bar "$current" "$label"
			fi
		else
			failed+=("$label")
			if [[ "$is_tty" == "true" ]]; then
				printf "\r[%s%s] %d/%d %s %s\n" \
					"${GREEN}$(printf '█%.0s' $current 2>/dev/null)${NC}" \
					"$(printf '░%.0s' $((total - current)) 2>/dev/null)" \
					"$current" "$total" "$label" "${RED}✗ failed${NC}"
			else
				echo "${RED}✗ failed${NC}"
			fi
		fi
	done

	echo ""

	local passed_count=${#passed[@]}
	local failed_count=${#failed[@]}

	if [[ $failed_count -eq 0 ]]; then
		echo "${GREEN}${ICON_SUCCESS} Completed: ${passed_count}/${total} passed${NC}"
	else
		echo "${YELLOW}${ICON_ERROR} Completed: ${passed_count} passed, ${failed_count} failed${NC}"
		for f in "${failed[@]}"; do
			echo "  ${RED}✗${NC} $f"
		done
	fi

	[[ $failed_count -gt 0 ]] && return 1 || return 0
}

print_table_header() {
    local sep="|"
    local cols="$1"
    shift
    local -a widths=("$@")
    IFS='|' read -ra col_arr <<< "$cols"
    printf "%s" "$sep"
    for i in "${!col_arr[@]}"; do
        local w=${widths[$i]:-20}
        printf " %-${w}s %s" "${col_arr[$i]}" "$sep"
    done
    echo ""
    printf "%s" "$sep"
    for i in "${!col_arr[@]}"; do
        local w=${widths[$i]:-20}
        printf " %${w}s %s" "$(printf '%*s' $w '' | tr ' ' '-')" "$sep"
    done
    echo ""
}

print_table_row() {
    local sep="|"
    local values="$1"
    shift
    local -a widths=("$@")
    IFS='|' read -ra val_arr <<< "$values"
    printf "%s" "$sep"
    for i in "${!val_arr[@]}"; do
        local w=${widths[$i]:-20}
        local text="${val_arr[$i]}"
        local clean=$(echo "$text" | sed -E 's/\x1b\[[0-9;]*m//g')
        local vlen=${#clean}
        local pad=$((w - vlen))
        [[ $pad -lt 0 ]] && pad=0
        printf " %s%*s %s" "$text" "$pad" "" "$sep"
    done
    echo ""
}

# =====================================================================
# Global Progress Bar (single bar for multi-step operations)
# =====================================================================

RCC_PROGRESS_TOTAL=0
RCC_PROGRESS_CURRENT=0
RCC_PROGRESS_INFO=""
RCC_PROGRESS_BUFFER=()
RCC_PROGRESS_MAX_BUFFER=100
RCC_PROGRESS_LAST_REDRAW=0
RCC_PROGRESS_REDRAW_INTERVAL_MS=200
RCC_PROGRESS_ACTIVE=false

_rcc_get_ms() {
    perl -MTime::HiRes=time -e 'printf "%.0f\n", time*1000'
}

init_global_progress() {
    local total="$1"
    RCC_PROGRESS_TOTAL="$total"
    RCC_PROGRESS_CURRENT=0
    RCC_PROGRESS_INFO="Initializing..."
    RCC_PROGRESS_BUFFER=()
    RCC_PROGRESS_LAST_REDRAW=$(_rcc_get_ms)
    RCC_PROGRESS_ACTIVE=true

    if [[ -t 1 ]]; then
        printf '\033[2J\033[H'
        printf '\033[?25l'
        _rcc_redraw_global_progress
    fi
}

update_global_progress_info() {
    local info="$1"
    RCC_PROGRESS_INFO="$info"
    _rcc_maybe_redraw_global_progress
}

increment_global_progress() {
    RCC_PROGRESS_CURRENT=$((RCC_PROGRESS_CURRENT + 1))
    _rcc_maybe_redraw_global_progress
}

append_progress_output() {
    local line="$1"
    RCC_PROGRESS_BUFFER+=("$line")
    if [[ ${#RCC_PROGRESS_BUFFER[@]} -gt $RCC_PROGRESS_MAX_BUFFER ]]; then
        RCC_PROGRESS_BUFFER=("${RCC_PROGRESS_BUFFER[@]:1}")
    fi
    _rcc_maybe_redraw_global_progress
}

_rcc_maybe_redraw_global_progress() {
    [[ "$RCC_PROGRESS_ACTIVE" != "true" ]] && return
    [[ -t 1 ]] || return

    local now
    now=$(_rcc_get_ms)
    local elapsed=$((now - RCC_PROGRESS_LAST_REDRAW))
    if [[ $elapsed -ge $RCC_PROGRESS_REDRAW_INTERVAL_MS ]]; then
        _rcc_redraw_global_progress
        RCC_PROGRESS_LAST_REDRAW="$now"
    fi
}

_rcc_redraw_global_progress() {
    [[ -t 1 ]] || return

    local total=$RCC_PROGRESS_TOTAL
    local current=$RCC_PROGRESS_CURRENT
    local cols
    cols=$(tput cols 2>/dev/null || echo 80)
    local bar_width=20
    local filled=$((current * bar_width / total))
    local empty=$((bar_width - filled))
    local bar=""
    local i

    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done

    # Move to top-left
    printf '\033[H'

    # Line 1: progress bar
    printf "\r[%s%s] %d/%d managers\n" "$bar" "" "$current" "$total"

    # Line 2: current info
    local info_display="$RCC_PROGRESS_INFO"
    local info_clean
    info_clean=$(echo "$info_display" | sed -E 's/\x1b\[[0-9;]*m//g')
    if [[ ${#info_clean} -gt $cols ]]; then
        info_display="${info_display:0:cols}"
    fi
    printf "%s\n" "$info_display"

    # Separator line
    printf "%s\n" "$(printf '%*s' "$cols" '' | tr ' ' '-')"

    # Buffer lines
    if [[ ${#RCC_PROGRESS_BUFFER[@]} -gt 0 ]]; then
        for line in "${RCC_PROGRESS_BUFFER[@]}"; do
            local clean_line
            clean_line=$(echo "$line" | sed -E 's/\x1b\[[0-9;]*m//g')
            if [[ ${#clean_line} -gt $cols ]]; then
                printf "%s\n" "${line:0:cols}"
            else
                printf "%s\n" "$line"
            fi
        done
    fi

    # Clear from cursor to end of screen
    printf '\033[J'
}

finish_global_progress() {
    [[ "$RCC_PROGRESS_ACTIVE" != "true" ]] && return

    RCC_PROGRESS_CURRENT=$RCC_PROGRESS_TOTAL
    RCC_PROGRESS_INFO="Completed"
    _rcc_redraw_global_progress

    printf '\n'
    if [[ -t 1 ]]; then
        printf '\033[?25h'
    fi

    RCC_PROGRESS_ACTIVE=false
}

# =====================================================================
# Helper: run a command with global progress bar
# Usage: run_step "label" "info_prefix" "command"
# =====================================================================

run_step() {
    local label="$1"
    local info_prefix="$2"
    local cmd="$3"

    update_global_progress_info "$info_prefix: starting..."

    set +e
    set +o pipefail
    eval "$cmd" 2>&1 | while IFS= read -r line; do
        append_progress_output "$line"
    done
    set -e
    set -o pipefail

    increment_global_progress
}

# =====================================================================
# Helper: run a check function with global progress bar
# Usage: run_check "label" "check_function_name"
# The check function should echo lines that will be captured.
# =====================================================================

run_check() {
    local label="$1"
    local check_fn="$2"

    update_global_progress_info "audit: $label..."

    set +e
    set +o pipefail
    $check_fn 2>&1 | while IFS= read -r line; do
        append_progress_output "$line"
    done
    set -e
    set -o pipefail

    increment_global_progress
}

# =====================================================================
# Helper: flush progress buffer to terminal and restore normal output
# Usage: flush_progress_to_terminal
# Call this after finish_global_progress() to print all buffered output.
# =====================================================================

flush_progress_to_terminal() {
    # Already restored by finish_global_progress, just print buffer
    if [[ ${#RCC_PROGRESS_BUFFER[@]} -gt 0 ]]; then
        for line in "${RCC_PROGRESS_BUFFER[@]}"; do
            echo "$line"
        done
    fi
    # Clear the buffer so it doesn't get printed again
    RCC_PROGRESS_BUFFER=()
}
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
    echo "${PURPLE_BOLD}━━ ${title}${NC}"
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

print_header() {
    local -a cols=("$@")
    local width=14
    echo -n "┌"
    for i in "${!cols[@]}"; do
        printf "%${cols[$i]:s//─/$((width-2))s}┬" | sed 's/ /─/g'
    done | sed 's/.$/┐/'
    echo ""
}

print_row() {
    local -a cols=("$@")
    local width=14
    echo -n "│"
    for c in "${cols[@]}"; do
        printf " %-*s │" "$((width-3))" "$c"
    done
    echo ""
}

print_footer() {
    echo "└─────────────────────────────────┘"
}

print_key_value() {
    local key="$1"
    local value="$2"
    printf "│ %-13s │ %-14s │\n" "$key" "$value"
}
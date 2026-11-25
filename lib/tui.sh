# MacGlass installer — tiny dependency-free TUI helpers (bash). Sourced by install.sh.
# Screens: tui_screen <step-index> · boxes: tui_box · menus: tui_menu · long jobs: tui_run (spinner + log)

shopt -s extglob        # needed by tui_vlen's pattern (must be set before it is parsed)
TUI_STEPS=()            # step names, set by the caller
TUI_LOG=/dev/null       # tui_run appends command output here
TUI_TITLE=installer     # shown in the banner
TUI_ASK=1               # 0 = never wait for keys (--yes or no terminal)
[[ -t 1 && "${TERM:-dumb}" != dumb ]] && TUI_FANCY=1 || TUI_FANCY=0
[[ -t 0 ]] || TUI_ASK=0

if [[ $TUI_FANCY == 1 ]]; then
    C0=$'\e[0m' B=$'\e[1m' D=$'\e[2m' CY=$'\e[36m' GR=$'\e[32m' YE=$'\e[33m' RE=$'\e[31m' MA=$'\e[35m'
else
    C0= B= D= CY= GR= YE= RE= MA=
fi

tui_cols() { local c; c=$(tput cols 2>/dev/null || echo 80); [[ $c =~ ^[0-9]+$ ]] || c=80; echo "$c"; }
tui_width() { local c; c=$(tui_cols); (( c < 84 )) && echo $(( c > 44 ? c - 4 : 40 )) || echo 80; }
tui_vlen() { local s="${1//$'\e'\[+([0-9;])m/}"; echo "${#s}"; }
tui_short() { [[ $1 == "$HOME"/* ]] && echo "~${1#"$HOME"}" || echo "$1"; }   # ~ instead of $HOME
tui_rep() { local s="" i; for (( i = 0; i < $2; i++ )); do s+="$1"; done; printf '%s' "$s"; }

tui_cursor() { [[ $TUI_FANCY == 1 ]] && { [[ $1 == on ]] && printf '\e[?25h' || printf '\e[?25l'; }; return 0; }

# tui_box <colour> <title> [line …]   (lines may contain colours; "--" draws a separator)
tui_box() {
    local col="$1" title="$2"; shift 2
    local w; w=$(tui_width); local in=$(( w - 4 ))
    local tl=$(( $(tui_vlen "$title") ))
    if [[ -n "$title" ]]; then
        printf '  %s╭─ %s%s%s %s╮%s\n' "$col" "$B" "$title" "$C0$col" "$(tui_rep ─ $(( w - tl - 5 )))" "$C0"
    else
        printf '  %s╭%s╮%s\n' "$col" "$(tui_rep ─ $(( w - 2 )))" "$C0"
    fi
    local l pad wrapped=() word cur
    # word-wrap lines that are wider than the box
    for l in "$@"; do
        if [[ "$l" == "--" ]] || (( $(tui_vlen "$l") <= in )); then wrapped+=("$l"); continue; fi
        cur=""; local words=() lead="${l%%[! ]*}"; read -ra words <<< "$l"
        for word in "${words[@]}"; do
            if [[ -z "$cur" ]]; then cur="$lead$word"
            elif (( $(tui_vlen "$cur $word") <= in )); then cur+=" $word"
            else wrapped+=("$cur"); cur="$lead$word"; fi
        done
        [[ -n "$cur" ]] && wrapped+=("$cur")
    done
    set -- "${wrapped[@]}"
    for l in "$@"; do
        if [[ "$l" == "--" ]]; then printf '  %s├%s┤%s\n' "$col" "$(tui_rep ─ $(( w - 2 )))" "$C0"; continue; fi
        pad=$(( in - $(tui_vlen "$l") )); (( pad < 0 )) && pad=0
        printf '  %s│%s %s%*s %s│%s\n' "$col" "$C0" "$l" "$pad" "" "$col" "$C0"
    done
    printf '  %s╰%s╯%s\n' "$col" "$(tui_rep ─ $(( w - 2 )))" "$C0"
}

tui_banner() {
    local w; w=$(tui_width)
    printf '\n  %s%s%s\n' "$CY" "$(tui_rep ━ "$w")" "$C0"
    printf '  %s  ◐  MacGlass%s %s·  macOS-style KDE Plasma 6 desktop  ·  %s%s\n' "$B$CY" "$C0" "$D" "$TUI_TITLE" "$C0"
    printf '  %s%s%s\n' "$CY" "$(tui_rep ━ "$w")" "$C0"
}

# tui_screen <index>: clear, banner, progress bar, step list
tui_screen() {
    local cur=$1 n=${#TUI_STEPS[@]} w i
    w=$(tui_width)
    [[ $TUI_FANCY == 1 ]] && printf '\e[H\e[2J' || echo
    tui_banner
    local label="Step $(( cur + 1 )) of $n · ${TUI_STEPS[cur]}"
    local bw=$(( w - $(tui_vlen "$label") - 2 )); (( bw < 10 )) && bw=10
    local done_w=$(( bw * (cur + 1) / n ))
    printf '\n  %s%s%s%s%s  %s%s%s\n' "$GR" "$(tui_rep █ "$done_w")" "$D" "$(tui_rep ░ $(( bw - done_w )))" "$C0" "$B" "$label" "$C0"
    # step list, wrapped to the width
    local line="  " item il
    for i in "${!TUI_STEPS[@]}"; do
        if (( i < cur )); then item="${GR}✓ ${TUI_STEPS[i]}${C0}"
        elif (( i == cur )); then item="${B}${CY}▸ ${TUI_STEPS[i]}${C0}"
        else item="${D}○ ${TUI_STEPS[i]}${C0}"; fi
        il=$(( $(tui_vlen "$item") + 3 ))
        if (( $(tui_vlen "$line") + il > w + 2 )); then printf '%s\n' "$line"; line="  "; fi
        line+="$item   "
    done
    printf '%s\n\n' "$line"
}

# stop a running tui_run job and everything it started (Ctrl+C)
TUI_PID=
tui_killtree() { local c; for c in $(ps -o pid= --ppid "$1" 2>/dev/null); do tui_killtree "$c"; done; kill "$1" 2>/dev/null || true; }
tui_stop() { [[ -n "$TUI_PID" ]] && tui_killtree "$TUI_PID"; TUI_PID=; return 0; }

tui_info() { printf '  %s•%s %s\n' "$CY" "$C0" "$*"; }
tui_ok()   { printf '  %s✓%s %s\n' "$GR" "$C0" "$*"; }
tui_skip() { printf '  %s–  %s%s\n' "$D" "$*" "$C0"; }
tui_warn() { printf '  %s!%s %s\n' "$YE" "$C0" "$*" >&2; }

# tui_menu <result-var> <default-index> <option …>   ↑/↓ (or j/k) + Enter, or the option's number
tui_menu() {
    local __var=$1 sel=$2; shift 2
    local opts=("$@") n=$# key rest i
    if [[ $TUI_ASK == 0 ]]; then printf '  %s❯ %s%s\n' "$CY" "${opts[sel]}" "$C0"; printf -v "$__var" '%s' "$sel"; return 0; fi
    if [[ $TUI_FANCY == 0 ]]; then
        for i in "${!opts[@]}"; do printf '   %d) %s\n' $(( i + 1 )) "${opts[i]}"; done
        read -r -p "  Choose [$(( sel + 1 ))]: " key || true
        [[ $key =~ ^[0-9]+$ ]] && (( key >= 1 && key <= n )) && sel=$(( key - 1 ))
        printf -v "$__var" '%s' "$sel"; return 0
    fi
    printf '  %s↑/↓ to move · Enter to choose%s\n' "$D" "$C0"
    tui_cursor off
    while true; do
        for i in "${!opts[@]}"; do
            if (( i == sel )); then printf '  %s❯ %s%s%s\e[K\n' "$CY$B" "$(( i + 1 )). " "${opts[i]}" "$C0"
            else printf '    %s%s%s\e[K\n' "$D" "$(( i + 1 )). ${opts[i]}" "$C0"; fi
        done
        key=""; IFS= read -rsn1 key || true
        case "$key" in
            $'\e') rest=""; IFS= read -rsn2 -t 0.05 rest || true
                   case "$rest" in '[A'|'OA') sel=$(( (sel - 1 + n) % n )) ;; '[B'|'OB') sel=$(( (sel + 1) % n )) ;; esac ;;
            k) sel=$(( (sel - 1 + n) % n )) ;;
            j) sel=$(( (sel + 1) % n )) ;;
            [1-9]) if (( key <= n )); then sel=$(( key - 1 )); printf '\e[%dA' "$n"; break; fi ;;
            "") printf '\e[%dA' "$n"; break ;;
        esac
        printf '\e[%dA' "$n"
    done
    # redraw once with only the choice highlighted
    for i in "${!opts[@]}"; do
        if (( i == sel )); then printf '  %s✓ %s%s\e[K\n' "$GR$B" "${opts[i]}" "$C0"; else printf '    %s%s%s\e[K\n' "$D" "${opts[i]}" "$C0"; fi
    done
    tui_cursor on
    printf -v "$__var" '%s' "$sel"
}

tui_pause() {
    [[ $TUI_ASK == 1 ]] || return 0
    printf '\n  %s%s%s' "$D" "${1:-Press Enter to continue}" "$C0"; read -rs _k || true; echo
}

# tui_fail <message>: red box with the end of the log, then exit
tui_fail() {
    tui_cursor on; echo
    local lines=()
    if [[ -s "$TUI_LOG" ]]; then
        while IFS= read -r l; do lines+=("${D}${l:0:$(( $(tui_width) - 6 ))}${C0}"); done < <(tail -n 15 "$TUI_LOG")
        tui_box "$RE" "✗ $1" "${lines[@]}" "--" "Full log: $(tui_short "$TUI_LOG")"
    else
        tui_box "$RE" "✗ Stopped" "$1"
    fi
    exit 1
}

# Keep sudo prompts in the foreground; background jobs cannot safely read the terminal.
tui_run_interactive() {
    local label="$1"; shift
    printf '\n### %s\n' "$label" >> "$TUI_LOG"
    tui_info "$label"
    if "$@" 2>&1 | tee -a "$TUI_LOG"; then
        tui_ok "$label"
        return 0
    fi
    tui_fail "$label failed"
}

# tui_run <label> <command …>: run with a spinner; output → $TUI_LOG; stops the installer on failure
tui_run() {
    local label="$1"; shift
    printf '\n### %s\n' "$label" >> "$TUI_LOG"
    if [[ $TUI_FANCY == 0 ]]; then
        printf '  • %s … ' "$label"
        if "$@" >> "$TUI_LOG" 2>&1 < /dev/null; then echo ok; return 0; fi
        echo failed; tui_fail "$label failed"
    fi
    "$@" >> "$TUI_LOG" 2>&1 < /dev/null &
    local pid=$!; TUI_PID=$pid frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0 t0=$SECONDS rc=0
    tui_cursor off
    while kill -0 "$pid" 2>/dev/null; do
        printf '\r  %s%s%s %s %s%ss%s\e[K' "$CY" "${frames:i%10:1}" "$C0" "$label" "$D" $(( SECONDS - t0 )) "$C0"
        i=$(( i + 1 )); sleep 0.1
    done
    wait "$pid" || rc=$?
    TUI_PID=
    tui_cursor on
    if [[ $rc == 0 ]]; then printf '\r  %s✓%s %s %s%ss%s\e[K\n' "$GR" "$C0" "$label" "$D" $(( SECONDS - t0 )) "$C0"; return 0; fi
    printf '\r  %s✗%s %s\e[K\n' "$RE" "$C0" "$label"
    tui_fail "$label failed"
}

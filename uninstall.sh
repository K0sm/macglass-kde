#!/usr/bin/env bash
# MacGlass — undo ./install.sh (full-screen, step by step): restore every file it backed up,
# delete the files it created.
#   ./uninstall.sh              pick a backup (the most recent one is preselected)
#   ./uninstall.sh <backup-dir> use a specific one (~/.local/share/macglass/backups/setup-*)
#   ./uninstall.sh --yes        don't ask anything (most recent backup)
# Packages stay installed (the command to remove them is shown at the end).
set -euo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
MG="$DATA/macglass"

BK= ASSUME_YES=0
for a in "$@"; do
    case "$a" in
        --yes|-y) ASSUME_YES=1 ;;
        -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
        -*) echo "Unknown option: $a" >&2; exit 2 ;;
        *) BK="$a" ;;
    esac
done

. "$HERE/lib/tui.sh"
[[ $ASSUME_YES == 1 ]] && TUI_ASK=0
TUI_TITLE=uninstaller
TUI_STEPS=("Check" "Confirm" "Restore" "Remove" "Reload" "Done")
S_CHECK=0 S_CONFIRM=1 S_RESTORE=2 S_REMOVE=3 S_RELOAD=4 S_DONE=5
mkdir -p "$MG/logs"; TUI_LOG="$MG/logs/uninstall-$(date +%Y%m%d-%H%M%S).log"; : > "$TUI_LOG"
LIVE=1; [[ "${MACGLASS_NO_RELOAD:-0}" == 1 ]] && LIVE=0   # test mode: files only
SHELL_STOPPED=0
trap 'tui_stop; echo; [[ $SHELL_STOPPED == 1 ]] && systemctl --user start plasma-plasmashell.service 2>/dev/null; tui_box "$YE" "Uninstall cancelled" "Some files may already be restored; run ./uninstall.sh again to finish."; exit 130' INT

# ═════════════════════════════════════════════════════════════════════════════
# 1. Check
# ═════════════════════════════════════════════════════════════════════════════
tui_screen $S_CHECK
mapfile -t ALL < <(ls -1d "$MG"/backups/setup-*/ 2>/dev/null | sed 's|/$||' | sort -r)
if [[ -z "$BK" ]]; then
    BK="$(cat "$MG/LAST_SETUP_BACKUP" 2>/dev/null || true)"
    [[ -z "$BK" && ${#ALL[@]} -gt 0 ]] && BK="${ALL[0]}"
fi
BK="${BK%/}"
if [[ -z "$BK" || ! -d "$BK/config" ]]; then
    tui_box "$RE" "✗ No MacGlass install backup found" \
        "Looked for: ${BK:-$MG/backups/setup-*}" \
        "The installer saves one in ~/.local/share/macglass/backups/setup-<time>/ before it changes anything."
    rm -f "$TUI_LOG"; exit 1
fi
tui_ok "Found ${#ALL[@]} install backup(s)"

bk_info() {   # one-line description of a backup
    local b=$1 t n c
    t="$(basename "$b")"; t="${t#setup-}"
    n=$(find "$b/config" "$b/data" -type f 2>/dev/null | wc -l || true)
    c=$(grep -c . "$b/created.txt" 2>/dev/null || true)
    printf '%s-%s-%s %s:%s  ·  %s saved files, %s created' "${t:0:4}" "${t:4:2}" "${t:6:2}" "${t:9:2}" "${t:11:2}" "$n" "${c:-0}"
}

# ═════════════════════════════════════════════════════════════════════════════
# 2. Confirm
# ═════════════════════════════════════════════════════════════════════════════
while :; do
    tui_screen $S_CONFIRM
    fx="no"; [[ -f "$BK/firefox/profile" ]] && fx="yes ($(basename "$(cat "$BK/firefox/profile")"))"
    tui_box "$MA" "Remove MacGlass — what will happen" \
        "Backup:  ${B}$(bk_info "$BK")${C0}" \
        "${D}$BK${C0}" \
        "--" \
        "${GR}✓${C0} Your settings from before MacGlass are put back (theme, colours, icons," \
        "  cursor, fonts, panels, window decorations)" \
        "${GR}✓${C0} Files MacGlass created are deleted (widgets, menu bar, tools, launchers)" \
        "${GR}✓${C0} Firefox restored: $fx" \
        "${GR}✓${C0} The dock (Krema) no longer starts at login" \
        "--" \
        "${YE}!${C0} The panel and dock disappear for a few seconds while files are swapped." \
        "${D}–${C0} Packages stay installed; the command to remove them is shown at the end."
    opts=("Remove MacGlass" "Cancel")
    (( ${#ALL[@]} > 1 )) && opts=("Remove MacGlass" "Use a different backup" "Cancel")
    tui_menu go 0 "${opts[@]}"
    case "${opts[go]}" in
        "Remove MacGlass") break ;;
        "Cancel") echo; tui_ok "Cancelled. Nothing was changed."; rm -f "$TUI_LOG"; exit 0 ;;
    esac
    tui_screen $S_CONFIRM
    tui_box "$CY" "Choose a backup" "Each one is your desktop as it was right before an install." \
        "The ${B}oldest${C0} one is the setup from before MacGlass was ever installed."
    labels=(); for i in "${!ALL[@]}"; do
        l="$(bk_info "${ALL[i]}")"; (( i == 0 )) && l+="  ${GR}(latest)${C0}"
        (( i == ${#ALL[@]} - 1 )) && l+="  ${CY}(before MacGlass)${C0}"; labels+=("$l"); done
    tui_menu pick 0 "${labels[@]}"
    BK="${ALL[pick]}"
done

# ═════════════════════════════════════════════════════════════════════════════
# 3. Restore
# ═════════════════════════════════════════════════════════════════════════════
tui_screen $S_RESTORE
stop_desktop() {
    for pid in $(pgrep -x -u "$(id -u)" krema || true) $(pgrep -x -u "$(id -u)" macglass-stack || true); do
        kill "$pid" 2>/dev/null || true; done
    systemctl --user stop plasma-plasmashell.service
}
restore_config() {
    (cd "$BK/config" && find . -mindepth 1 -maxdepth 2 \( -type f -o -type l \) -print0) | while IFS= read -r -d '' f; do
        mkdir -p "$CONF/$(dirname "$f")"; rm -rf "${CONF:?}/$f"; cp -a "$BK/config/$f" "$CONF/$f"; echo "config/$f"; done
    for d in klassy gtk-3.0 gtk-4.0 vesktop/userAssets; do
        if [[ -d "$BK/config/$d" ]]; then rm -rf "${CONF:?}/$d"; cp -a "$BK/config/$d" "$CONF/$d"; echo "config/$d/"; fi; done
}
restore_data() {
    [[ -d "$BK/data" ]] || return 0
    (cd "$BK/data" && find . -mindepth 1 \( -type f -o -type l \) -print0) | while IFS= read -r -d '' f; do
        mkdir -p "$DATA/$(dirname "$f")"; cp -a "$BK/data/$f" "$DATA/$f"; echo "data/$f"; done
    for d in plasma/desktoptheme/MacGlass-Dark icons/MacGlass plasma/plasmoids/org.macglass.activeapp \
             plasma/plasmoids/org.macglass.notificationcenter plasma/plasmoids/KdeControlStation; do
        if [[ -d "$BK/data/$d" ]]; then rm -rf "${DATA:?}/$d"; cp -a "$BK/data/$d" "$DATA/$d"; echo "data/$d/"; fi
    done
}
restore_firefox() {
    local p f; p="$(cat "$BK/firefox/profile")"
    for f in user.js chrome/userChrome.css; do
        if [[ -e "$BK/firefox/$f" || -L "$BK/firefox/$f" ]]; then rm -f "$p/$f"; cp -a "$BK/firefox/$f" "$p/$f"; echo "$p/$f"; fi; done
}
if [[ $LIVE == 1 ]]; then SHELL_STOPPED=1; tui_run "Stopping the panel and dock" stop_desktop
else tui_skip "test mode: desktop keeps running"; fi
tui_run "Restoring your settings (~/.config)" restore_config
tui_run "Restoring themes and widgets (~/.local/share)" restore_data
if [[ -f "$BK/firefox/profile" ]]; then tui_run "Restoring Firefox" restore_firefox
else tui_skip "Firefox was not changed"; fi

# ═════════════════════════════════════════════════════════════════════════════
# 4. Remove
# ═════════════════════════════════════════════════════════════════════════════
tui_screen $S_REMOVE
remove_created() {
    local e p
    while IFS= read -r e; do
        case "$e" in
            config/*) rm -rf "${CONF:?}/${e#config/}" ;;
            data/*)   rm -rf "${DATA:?}/${e#data/}" ;;
            bin/*)    rm -f "$HOME/.local/bin/${e#bin/}" ;;
            firefox/*) p="$(cat "$BK/firefox/profile" 2>/dev/null || true)"; [[ -n "$p" ]] && rm -f "$p/${e#firefox/}" ;;
            *) continue ;;
        esac
        echo "removed $e"
    done < "$BK/created.txt"
}
no_krema_autostart() {   # Krema's autostart is system-wide; hide it for this user
    mkdir -p "$CONF/autostart"
    printf '[Desktop Entry]\nHidden=true\n' > "$CONF/autostart/com.bhyoo.krema.autostart.desktop"
}
if [[ -s "$BK/created.txt" ]]; then tui_run "Deleting files MacGlass created ($(grep -c . "$BK/created.txt" || true))" remove_created
else tui_skip "No created files listed"; fi
tui_run "Turning off the dock at login" no_krema_autostart

# ═════════════════════════════════════════════════════════════════════════════
# 5. Reload
# ═════════════════════════════════════════════════════════════════════════════
tui_screen $S_RELOAD
reload() {
    systemctl --user start plasma-plasmashell.service
    sleep 3
    local cs pt ic cu
    cs="$(kreadconfig6 --group General --key ColorScheme || true)"; [[ -n "$cs" ]] && plasma-apply-colorscheme "$cs" || true
    pt="$(kreadconfig6 --file plasmarc --group Theme --key name || true)"; [[ -n "$pt" ]] && plasma-apply-desktoptheme "$pt" || true
    ic="$(kreadconfig6 --group Icons --key Theme || true)"; [[ -n "$ic" ]] && /usr/lib/plasma-changeicons "$ic" || true
    cu="$(kreadconfig6 --file kcminputrc --group Mouse --key cursorTheme || true)"; plasma-apply-cursortheme "${cu:-breeze_cursors}" || true
    qdbus6 org.kde.KWin /KWin reconfigure || true
    kbuildsycoca6 || true
}
if [[ $LIVE == 1 ]]; then tui_run "Starting Plasma and applying your old look" reload; SHELL_STOPPED=0
else tui_skip "test mode: no reload"; fi

# ═════════════════════════════════════════════════════════════════════════════
# 6. Done
# ═════════════════════════════════════════════════════════════════════════════
tui_screen $S_DONE
tui_box "$GR" "✓ MacGlass is removed" \
    "${B}Log out and back in once${C0} so every app picks up the restored settings." \
    "--" \
    "MacGlass's packages are still installed. To remove them too:" \
    "  ${CY}sudo pacman -Rns krema klassy darkly whitesur-icon-theme kwin-effect-rounded-corners-git${C0}" \
    "  ${D}(add plasma6-applets-appgrid if you didn't use AppGrid before)${C0}" \
    "  ${CY}rm -f ~/.local/bin/macglass-stack${C0}" \
    "--" \
    "${D}Log: $(tui_short "$TUI_LOG")${C0}"
echo

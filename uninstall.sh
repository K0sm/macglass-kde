#!/usr/bin/env bash
# MacGlass — undo ./install.sh: restore every file it backed up, delete the files it created.
#   ./uninstall.sh              use the most recent install backup
#   ./uninstall.sh <backup-dir> use a specific one (~/.local/share/macglass/backups/setup-*)
# Packages stay installed (the command to remove them is printed at the end).
set -euo pipefail
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
MG="$DATA/macglass"
BK="${1:-$(cat "$MG/LAST_SETUP_BACKUP" 2>/dev/null || true)}"
[[ -n "$BK" && -d "$BK/config" ]] || { echo "No MacGlass install backup found (${BK:-none})." >&2; exit 1; }
echo "Restoring from $BK"

LIVE=1; [[ "${MACGLASS_NO_RELOAD:-0}" == 1 ]] && LIVE=0   # test mode: files only
if [[ $LIVE == 1 ]]; then
    pkill -x krema 2>/dev/null || true
    pkill -x macglass-stack 2>/dev/null || true
    systemctl --user stop plasma-plasmashell.service
fi

# 1. files that existed before: put the saved copies back
if [[ -d "$BK/config" ]]; then (cd "$BK/config" && find . -mindepth 1 -maxdepth 2 \( -type f -o -type l \) -print0) | while IFS= read -r -d '' f; do
    mkdir -p "$CONF/$(dirname "$f")"; rm -rf "${CONF:?}/$f"; cp -a "$BK/config/$f" "$CONF/$f"; done
    for d in klassy gtk-3.0 gtk-4.0 vesktop/userAssets; do [[ -d "$BK/config/$d" ]] && { rm -rf "${CONF:?}/$d"; cp -a "$BK/config/$d" "$CONF/$d"; }; done
fi
if [[ -d "$BK/data" ]]; then (cd "$BK/data" && find . -mindepth 1 \( -type f -o -type l \) -print0) | while IFS= read -r -d '' f; do
    mkdir -p "$DATA/$(dirname "$f")"; cp -a "$BK/data/$f" "$DATA/$f"; done
    for d in plasma/desktoptheme/MacGlass-Dark icons/MacGlass plasma/plasmoids/org.macglass.activeapp \
             plasma/plasmoids/org.macglass.notificationcenter plasma/plasmoids/KdeControlStation; do
        [[ -d "$BK/data/$d" ]] && { rm -rf "${DATA:?}/$d"; cp -a "$BK/data/$d" "$DATA/$d"; }
    done
fi

# 2. files the installer created: remove them
while IFS= read -r e; do
    case "$e" in
        config/*) rm -rf "${CONF:?}/${e#config/}" ;;
        data/*)   rm -rf "${DATA:?}/${e#data/}" ;;
        bin/*)    rm -f "$HOME/.local/bin/${e#bin/}" ;;
        firefox/*) p="$(cat "$BK/firefox/profile" 2>/dev/null || true)"; [[ -n "$p" ]] && rm -f "$p/${e#firefox/}" ;;
    esac
done < "$BK/created.txt"

# 3. Firefox files that existed before
if [[ -f "$BK/firefox/profile" ]]; then
    p="$(cat "$BK/firefox/profile")"
    for f in user.js chrome/userChrome.css; do [[ -e "$BK/firefox/$f" || -L "$BK/firefox/$f" ]] && { rm -f "$p/$f"; cp -a "$BK/firefox/$f" "$p/$f"; }; done
fi

# 4. keep Krema (system-wide autostart) from starting again for this user
mkdir -p "$CONF/autostart"
printf '[Desktop Entry]\nHidden=true\n' > "$CONF/autostart/com.bhyoo.krema.autostart.desktop"

# 5. re-apply the restored look
if [[ $LIVE == 0 ]]; then echo "(test mode: no reload)"; exit 0; fi
systemctl --user start plasma-plasmashell.service
sleep 3
cs="$(kreadconfig6 --group General --key ColorScheme || true)"; [[ -n "$cs" ]] && plasma-apply-colorscheme "$cs" >/dev/null 2>&1 || true
pt="$(kreadconfig6 --file plasmarc --group Theme --key name || true)"; [[ -n "$pt" ]] && plasma-apply-desktoptheme "$pt" >/dev/null 2>&1 || true
ic="$(kreadconfig6 --group Icons --key Theme || true)"; [[ -n "$ic" ]] && /usr/lib/plasma-changeicons "$ic" >/dev/null 2>&1 || true
cu="$(kreadconfig6 --file kcminputrc --group Mouse --key cursorTheme || true)"; plasma-apply-cursortheme "${cu:-breeze_cursors}" >/dev/null 2>&1 || true
qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true

cat <<EOF

Done. Log out and back in once so every app picks up the restored settings.
MacGlass's packages are still installed. To remove them too:
  sudo pacman -Rns krema klassy darkly whitesur-icon-theme kwin-effect-rounded-corners-git
  (plasma6-applets-appgrid too, if you didn't use AppGrid before)
  rm -f ~/.local/bin/macglass-stack
EOF

#!/usr/bin/env bash
# MacGlass — at login, warn when a locally built component needs a rebuild
# after a system update (KWin effects are tied to the exact KWin version, Krema to the Qt minor version). Runs once, takes well under a second.
set -u
PKGS="${XDG_DATA_HOME:-$HOME/.local/share}/macglass/packages"
msgs=()

# KWin refused to load the rounded-corners effect (built for another KWin) — used for Steam's own frame.
sleep 20   # give KWin time to load effects after login
if journalctl --user -b --no-pager -o cat 2>/dev/null \
     | grep -q 'kwin4_effect_shapecorners" was built for a different version of KWin'; then
    msgs+=("Rounded corners for Steam stopped working after a KWin update. Rebuild:\ncd $PKGS/kwin-effect-rounded-corners-git && makepkg -si")
fi

# Krema is pinned to the Qt minor version it was built against.
qt=$(pacman -Q qt6-base 2>/dev/null | awk '{print $2}' | sed -E 's/^[0-9]+://; s/-.*//' | cut -d. -f1,2)
need=$(pacman -Qi krema 2>/dev/null | grep -oE 'qt6-base>=[0-9:]*[0-9]+\.[0-9]+' | head -1 | sed -E 's/.*>=([0-9]+:)?//')
if [[ -n "$qt" && -n "$need" && "$qt" != "$need" ]]; then
    msgs+=("The dock (Krema) was built for Qt $need but Qt $qt is installed. Rebuild:\ncd $PKGS/krema && makepkg -si")
fi

# Control Station (KDE Store widget) — an update from the Store overwrites the MacGlass patch.
CS="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/KdeControlStation/contents/ui/CompactRepresentation.qml"
if [[ -f "$CS" ]] && ! grep -q 'MacGlass patch' "$CS"; then
    msgs+=("Control Center was updated and lost the MacGlass patch (icon size, empty tile). Re-apply:\ncd $PKGS/kde-control-station && cp CompactRepresentation.qml.macglass ${CS%/*}/CompactRepresentation.qml && cp Tahoe.qml.macglass ${CS%/*}/layouts/Tahoe.qml")
fi

for m in "${msgs[@]}"; do
    notify-send --app-name="MacGlass" --icon=system-software-update --urgency=normal \
        "MacGlass: rebuild needed" "$(printf '%b' "$m")"
done
exit 0

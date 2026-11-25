#!/usr/bin/env bash
# MacGlass — macOS-style KDE Plasma 6 desktop. Installer (full-screen, step by step).
#
#   ./install.sh                 full install (asks for your sudo password once, for packages)
#   ./install.sh --no-packages   skip pacman/makepkg (packages already installed)
#   ./install.sh --keep-panels   don't replace your panels with the MacGlass menu bar (otherwise you are asked)
#   ./install.sh --no-firefox    don't touch the Firefox profile
#   ./install.sh --no-app-tweaks don't set monochrome tray icons for ZapZap/Vesktop/Cachy-Update
#   ./install.sh --glass / --no-glass   liquid-glass app icons yes/no (otherwise you are asked)
#   ./install.sh --yes           don't ask anything (defaults: glass on, MacGlass menu bar)
#
# Everything it changes is backed up first; ./uninstall.sh puts it back.
# Needs: an Arch-based distro (pacman), Plasma 6 on Wayland, run as your normal user (not root).
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
MG="$DATA/macglass"               # runtime home: recipes, scripts, backups
BIN="$HOME/.local/bin"

DO_PACKAGES=1 DO_LAYOUT= DO_FIREFOX=1 DO_APPS=1 ASSUME_YES=0 GLASS=
for a in "$@"; do
    case "$a" in
        --no-packages) DO_PACKAGES=0 ;;
        --keep-panels) DO_LAYOUT=0 ;;
        --no-firefox) DO_FIREFOX=0 ;;
        --no-app-tweaks) DO_APPS=0 ;;
        --yes|-y) ASSUME_YES=1 ;;
        --glass) GLASS=1 ;;
        --no-glass) GLASS=0 ;;
        -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
        *) echo "Unknown option: $a" >&2; exit 2 ;;
    esac
done

. "$HERE/lib/tui.sh"
[[ $ASSUME_YES == 1 ]] && TUI_ASK=0
TUI_STEPS=("Check" "Icons" "Options" "Backup" "Packages" "Files" "Settings" "Menu bar" "Apps" "Done")
S_CHECK=0 S_ICONS=1 S_OPTIONS=2 S_BACKUP=3 S_PACKAGES=4 S_FILES=5 S_SETTINGS=6 S_MENUBAR=7 S_APPS=8 S_DONE=9

TS="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$MG/logs"; TUI_LOG="$MG/logs/install-$TS.log"; : > "$TUI_LOG"
SUDO_KEEPALIVE=
cleanup() { tui_cursor on; [[ -n "$SUDO_KEEPALIVE" ]] && kill "$SUDO_KEEPALIVE" 2>/dev/null; return 0; }
trap cleanup EXIT
trap 'tui_stop; echo; tui_box "$YE" "Installation cancelled" "Nothing after this point was changed." "If it stopped half-way, ./uninstall.sh puts everything back."; exit 130' INT

die() { tui_fail "$*"; }
kw()   { kwriteconfig6 --file "$1" --group "$2" --key "$3" "$4"; }   # file group key value
kwg()  { local f="$1"; shift; local args=(); while [[ $# -gt 2 ]]; do args+=(--group "$1"); shift; done; kwriteconfig6 --file "$f" "${args[@]}" --key "$1" "$2"; }

# ═════════════════════════════════════════════════════════════════════════════
# 1. Check the system
# ═════════════════════════════════════════════════════════════════════════════
tui_screen $S_CHECK
[[ $EUID -ne 0 ]] || die "Run as your normal user, not root (sudo is used only for packages)."
command -v pacman >/dev/null || die "pacman not found: MacGlass targets Arch-based distros (CachyOS, Arch, EndeavourOS…)."
tui_ok "Arch-based system (pacman)"
command -v plasmashell >/dev/null || die "KDE Plasma is not installed."
PV="$(plasmashell --version 2>/dev/null | awk '{print $2}')"
[[ "${PV%%.*}" -ge 6 ]] || die "Plasma 6 is required (found ${PV:-unknown})."
tui_ok "KDE Plasma $PV"
if [[ "${XDG_SESSION_TYPE:-}" == wayland ]]; then tui_ok "Wayland session"
else tui_warn "Not a Wayland session — MacGlass is built for Plasma Wayland (the dock, stack and blur need it)."; fi
for c in kwriteconfig6 kreadconfig6 qdbus6 systemctl python3; do command -v "$c" >/dev/null || die "Missing $c"; done
tui_ok "KDE tools and Python"
. /etc/os-release
LOGO=start-here-kde-symbolic; [[ "${ID:-}" == cachyos ]] && LOGO=macglass-cachyos-symbolic
tui_ok "Distribution: ${PRETTY_NAME:-${ID:-unknown}}"
echo
tui_box "$CY" "Welcome" \
    "This installer turns your Plasma desktop into MacGlass: glass windows with traffic lights, a Mac menu bar, a dock, Control Center, Quick Look and more." \
    "" \
    "${B}Nothing is changed yet.${C0} You will see everything before it is applied, and every file it touches is backed up first (undo: ${B}./uninstall.sh${C0})."
tui_pause

# ═════════════════════════════════════════════════════════════════════════════
# 2. Your current icons (shown before any theme change)
# ═════════════════════════════════════════════════════════════════════════════
scan_icons() {
    CUR_THEME="$(kreadconfig6 --file kdeglobals --group Icons --key Theme 2>/dev/null || true)"; CUR_THEME="${CUR_THEME:-breeze}"
    HAS_THEME=0; case "$CUR_THEME" in breeze|breeze-dark|MacGlass|WhiteSur*) ;; *) HAS_THEME=1 ;; esac
    N_LOCAL=0; [[ -d "$DATA/icons/hicolor" ]] && N_LOCAL=$(find "$DATA/icons/hicolor" -path '*/apps/*' -type f 2>/dev/null | wc -l || true)
    N_ABS=0; [[ -d "$DATA/applications" ]] && N_ABS=$(grep -ls '^Icon=/' "$DATA/applications"/*.desktop 2>/dev/null | wc -l || true)
    N_FOLDER=$(find "$HOME" -maxdepth 3 -name .directory -not -path '*/.*/*' 2>/dev/null | xargs -r grep -ls '^Icon=' 2>/dev/null | wc -l || true)
    N_PERS=0; [[ -d "$MG/icons/personal" ]] && N_PERS=$(find "$MG/icons/personal" -maxdepth 1 -name '*.png' 2>/dev/null | wc -l)
    return 0
}
row() {   # row <found 0/1> <how> <result>
    local m; [[ $1 == 1 ]] && m="${YE}●${C0}" || m="${D}○${C0}"
    printf '%s %-39s %s' "$m" "$2" "$3"
}
while true; do
    tui_screen $S_ICONS
    scan_icons
    tui_box "$MA" "Your custom icons — read this before the theme changes" \
        "MacGlass uses its own icon theme (built on WhiteSur). Custom icons you set yourself are affected like this:" \
        "" \
        "${B}  How the icon was set                    With MacGlass${C0}" \
        "  ${D}$(tui_rep ─ 39)  $(tui_rep ─ 30)${C0}" \
        "$(row $HAS_THEME "Icon theme in System Settings" "${RE}Replaced${C0} (uninstall restores)")" \
        "$(row $(( N_LOCAL > 0 )) "Icons in ~/.local/share/icons/hicolor" "${RE}Replaced${C0} if WhiteSur has one")" \
        "$(row $(( N_ABS > 0 )) "App launcher pointing to an image file" "${GR}Kept${C0}, but no glass tile")" \
        "$(row $(( N_FOLDER > 0 )) "Folder icon from an image file" "${GR}Kept${C0}")" \
        "$(row $(( N_FOLDER > 0 )) "Folder icon picked by name" "${YE}Shown in WhiteSur style${C0}")" \
        "--" \
        "${B}Found on this PC${C0} (${YE}●${C0} = applies to you):" \
        "  icon theme: ${B}$CUR_THEME${C0}$([[ $HAS_THEME == 1 ]] && echo "  ${YE}← will be replaced${C0}")" \
        "  $N_LOCAL own icon(s) in hicolor · $N_ABS launcher(s) with image icons" \
        "  $N_FOLDER folder(s) with custom icons · $N_PERS in the MacGlass personal folder" \
        "--" \
        "${B}Keep your own icons:${C0} save each one as ${B}<icon-name>.png${C0} in" \
        "  ~/.local/share/macglass/icons/personal/" \
        "<icon-name> is the Icon= value in the app's .desktop file. These icons win over WhiteSur, get the glass tile, and survive reinstalls."
    echo
    tui_menu ICON_CHOICE 0 \
        "Continue — I understand how my icons are affected" \
        "Pause — open the personal icons folder so I can add my icons first" \
        "Cancel the installation (nothing has been changed)"
    case $ICON_CHOICE in
        0) break ;;
        1) mkdir -p "$MG/icons/personal"
           (xdg-open "$MG/icons/personal" >/dev/null 2>&1 &) || true
           echo; tui_info "Opened ${B}$MG/icons/personal${C0}"
           tui_info "Copy your icons there as <icon-name>.png (512×512 looks best)."
           tui_pause "Press Enter when you are done — the list will refresh" ;;
        2) echo; tui_ok "Cancelled. Nothing was changed."; rm -f "$TUI_LOG"; exit 0 ;;
    esac
done
# the installer re-copies icons/ but keeps personal/ (see Files)

# ═════════════════════════════════════════════════════════════════════════════
# 3. Options
# ═════════════════════════════════════════════════════════════════════════════
tui_screen $S_OPTIONS
if [[ -z "$GLASS" ]]; then
    tui_box "$CY" "App icon style" \
        "${B}Liquid glass${C0}: every app icon on the same rounded tile with a soft glass rim and sheen (macOS Tahoe style). ${B}Plain${C0}: the WhiteSur icons as they are." \
        "${D}You can switch any time later with \"MacGlass Icon Style\" in the app launcher.${C0}"
    tui_menu g 0 "Liquid glass (recommended)" "Plain WhiteSur icons"
    [[ $g == 0 ]] && GLASS=1 || GLASS=0
    echo
fi
if [[ -z "$DO_LAYOUT" ]]; then
    tui_box "$CY" "Panels" \
        "MacGlass ${B}replaces your current panels${C0} with a Mac menu bar on top and the Krema dock at the bottom. Or keep your panels and only get the look."
    tui_menu l 0 "MacGlass menu bar + dock (recommended)" "Keep my current panels"
    [[ $l == 0 ]] && DO_LAYOUT=1 || DO_LAYOUT=0
    echo
fi

FFPROF=""
if [[ -f "$HOME/.mozilla/firefox/profiles.ini" || -f "$CONF/mozilla/firefox/profiles.ini" ]]; then
    FFROOT="$CONF/mozilla/firefox"; [[ -f "$FFROOT/profiles.ini" ]] || FFROOT="$HOME/.mozilla/firefox"
    # the profile Firefox actually starts: [Install…] Default=, else the profile marked Default=1
    rel="$(awk -F= '/^\[Install/{i=1} i&&/^Default=/{print $2; exit}' "$FFROOT/profiles.ini")"
    [[ -n "$rel" ]] || rel="$(awk -F= '/^\[Profile/{p=""} /^Path=/{p=$2} /^Default=1/{if(p!=""){print p; exit}}' "$FFROOT/profiles.ini")"
    [[ -n "$rel" && -d "$FFROOT/$rel" ]] && FFPROF="$FFROOT/$rel"
fi

yn() { [[ $1 == 1 ]] && echo "${GR}✓${C0}" || echo "${D}✗${C0}"; }
ffline="traffic lights + Safari-style address bar"
[[ $DO_FIREFOX == 1 && -z "$FFPROF" ]] && ffline="${YE}no profile found — open Firefox once, then re-run${C0}"
tui_screen $S_OPTIONS
tui_box "$GR" "Ready to install — summary" \
    "$(yn $DO_PACKAGES) Packages      $([[ $DO_PACKAGES == 1 ]] && echo "build Klassy, Darkly, Krema, WhiteSur, AppGrid + fonts" || echo "skipped (--no-packages)")" \
    "$(yn 1) Theme         colours, Plasma style, glass windows, fonts, cursor" \
    "$(yn 1) App icons     $([[ $GLASS == 1 ]] && echo "liquid glass" || echo "plain WhiteSur")" \
    "$(yn $DO_LAYOUT) Menu bar      $([[ $DO_LAYOUT == 1 ]] && echo "${YE}replaces your panels${C0} (menu bar + Krema dock)" || echo "your panels are kept")" \
    "$(yn 1) Extras        Downloads stack, Quick Look, Control/Notification Center" \
    "$(yn $DO_FIREFOX) Firefox       $([[ $DO_FIREFOX == 1 ]] && echo "$ffline" || echo "skipped")" \
    "--" \
    "Every changed file is backed up first, to" \
    "  ${B}~/.local/share/macglass/backups/setup-$TS/${C0}" \
    "Undo everything later with ${B}./uninstall.sh${C0}"
echo
tui_menu go 0 "Install MacGlass" "Cancel"
[[ $go == 0 ]] || { echo; tui_ok "Cancelled. Nothing was changed."; rm -f "$TUI_LOG"; exit 0; }

# ═════════════════════════════════════════════════════════════════════════════
# 4. Backup
# ═════════════════════════════════════════════════════════════════════════════
tui_screen $S_BACKUP
BK="$MG/backups/setup-$TS"
CONF_FILES=(kdeglobals kwinrc kwinrulesrc kcminputrc plasmarc plasmashellrc plasma-org.kde.plasma.desktop-appletsrc
            dolphinrc breezerc kglobalshortcutsrc darklyrc krunnerrc kremarc macglassstackrc macglassrc klassy gtk-3.0 gtk-4.0
            arch-update/arch-update.conf ZapZap/ZapZap.conf vesktop/userAssets autostart/macglass-check-rebuilds.desktop)
DATA_PATHS=(color-schemes/MacGlassDark.colors plasma/desktoptheme/MacGlass-Dark icons/MacGlass
            plasma/plasmoids/org.macglass.activeapp plasma/plasmoids/org.macglass.notificationcenter
            plasma/plasmoids/KdeControlStation kio/servicemenus/macglass-quicklook.desktop
            kxmlgui5/dolphin/dolphinui.rc applications/org.macglass.DownloadsStack.desktop applications/org.macglass.IconStyle.desktop)
backup() {
    mkdir -p "$BK/config" "$BK/data"; : > "$BK/created.txt"
    for f in "${CONF_FILES[@]}"; do
        if [[ -e "$CONF/$f" ]]; then mkdir -p "$BK/config/$(dirname "$f")"; cp -a "$CONF/$f" "$BK/config/$f"; else echo "config/$f" >> "$BK/created.txt"; fi
    done
    for f in "${DATA_PATHS[@]}"; do
        if [[ -e "$DATA/$f" ]]; then mkdir -p "$BK/data/$(dirname "$f")"; cp -a "$DATA/$f" "$BK/data/$f"; else echo "data/$f" >> "$BK/created.txt"; fi
    done
    for f in macglass-stack macglass-quicklook macglass-glass; do [[ -e "$BIN/$f" ]] || echo "bin/$f" >> "$BK/created.txt"; done
    if [[ $DO_FIREFOX == 1 && -n "$FFPROF" ]]; then
        mkdir -p "$BK/firefox"; echo "$FFPROF" > "$BK/firefox/profile"
        for f in user.js chrome/userChrome.css; do
            if [[ -e "$FFPROF/$f" || -L "$FFPROF/$f" ]]; then mkdir -p "$BK/firefox/$(dirname "$f")"; cp -a "$FFPROF/$f" "$BK/firefox/$f"
            else echo "firefox/$f" >> "$BK/created.txt"; fi
        done
    fi
    echo "$BK" > "$MG/LAST_SETUP_BACKUP"
}
tui_run "Saving your current settings" backup
tui_info "Backup: ${B}$BK${C0}"
sleep 1

# ═════════════════════════════════════════════════════════════════════════════
# 5. Packages
# ═════════════════════════════════════════════════════════════════════════════
tui_screen $S_PACKAGES
LOCAL_PKGS=(klassy darkly krema whitesur-icon-theme plasma6-applets-appgrid kwin-effect-rounded-corners-git)
if [[ $DO_PACKAGES == 1 ]]; then
    if ! sudo -n true 2>/dev/null; then
        tui_box "$YE" "Administrator password" \
            "Packages are installed system-wide, so sudo needs your password ${B}once${C0}." \
            "It is only used by pacman; the rest of MacGlass lives in your home folder."
        echo
        sudo -v || die "sudo was not authorised."
    fi
    # keep sudo alive while the builds run (they can take longer than sudo's 5-minute timeout)
    ( while kill -0 $$ 2>/dev/null; do sudo -n -v 2>/dev/null || exit; sleep 45; done ) & SUDO_KEEPALIVE=$!
    tui_screen $S_PACKAGES
    tui_run "Repository packages (fonts, cursors, build tools, Qt modules)" \
        sudo pacman -S --needed --noconfirm base-devel git cmake ninja extra-cmake-modules \
        inter-font capitaine-cursors ttf-jetbrains-mono-nerd appmenu-gtk-module \
        python-pillow librsvg kdialog qt6-declarative qt6-multimedia qt6-webengine layer-shell-qt kio
    mkdir -p "$MG/packages"
    for p in "${LOCAL_PKGS[@]}"; do
        dst="$MG/packages/$p"; mkdir -p "$dst"; cp -a "$HERE/packages/$p/." "$dst/"
        want="$(cd "$dst" && bash -c 'source PKGBUILD >/dev/null 2>&1; echo "${epoch:+$epoch:}$pkgver-$pkgrel"')"
        name="$(cd "$dst" && bash -c 'source PKGBUILD >/dev/null 2>&1; echo "${pkgname[0]}"')"
        have="$(pacman -Q "$name" 2>/dev/null | awk '{print $2}')"
        if [[ "$have" == "$want" ]]; then tui_ok "$name $have ${D}already installed${C0}"; continue; fi
        tui_run "Building $name $want ${D}(installed: ${have:-none})${C0}" \
            bash -c 'cd "$1" && makepkg -si --noconfirm --needed -f' _ "$dst"
    done
else
    tui_skip "Packages skipped (--no-packages)"
fi
for p in klassy darkly krema whitesur-icon-theme plasma6-applets-appgrid; do
    pacman -Q "$p" >/dev/null 2>&1 || die "Package $p is missing — run without --no-packages."
done
sleep 1

# ═════════════════════════════════════════════════════════════════════════════
# 6. Files
# ═════════════════════════════════════════════════════════════════════════════
tui_screen $S_FILES
mkdir -p "$DATA/color-schemes" "$DATA/plasma/desktoptheme" "$DATA/plasma/plasmoids" "$BIN" "$MG/bin" "$MG/firefox" "$MG/quicklook" \
         "$DATA/kio/servicemenus" "$DATA/kxmlgui5/dolphin" "$DATA/applications" "$CONF/autostart" "$CONF/klassy" "$CONF/gtk-3.0" "$CONF/gtk-4.0"

files_theme() {
    cp "$HERE/themes/color-schemes/MacGlassDark.colors" "$DATA/color-schemes/"
    rm -rf "$DATA/plasma/desktoptheme/MacGlass-Dark"; cp -a "$HERE/themes/desktoptheme/MacGlass-Dark" "$DATA/plasma/desktoptheme/"
}
files_widgets() {
    for p in org.macglass.activeapp org.macglass.notificationcenter KdeControlStation; do
        rm -rf "$DATA/plasma/plasmoids/$p"; cp -a "$HERE/plasmoids/$p" "$DATA/plasma/plasmoids/"
    done
    # keep the Control Station originals + patched copies where the rebuild check expects them
    mkdir -p "$MG/packages/kde-control-station"
    cp "$HERE/plasmoids/KdeControlStation.macglass-originals/"*.orig "$MG/packages/kde-control-station/"
    cp "$HERE/plasmoids/KdeControlStation/contents/ui/CompactRepresentation.qml" "$MG/packages/kde-control-station/CompactRepresentation.qml.macglass"
    cp "$HERE/plasmoids/KdeControlStation/contents/ui/layouts/Tahoe.qml" "$MG/packages/kde-control-station/Tahoe.qml.macglass"
}
files_icons() {
    # MacGlass overrides on top of WhiteSur-dark; your own icons in $MG/icons/personal/ survive a re-install
    [[ -d "$MG/icons/personal" ]] && mv "$MG/icons/personal" "$MG/.icons-personal.keep"
    rm -rf "$MG/icons"; cp -a "$HERE/icons" "$MG/icons"
    [[ -d "$MG/.icons-personal.keep" ]] && mv "$MG/.icons-personal.keep" "$MG/icons/personal"
    kw macglassrc Icons Glass "$([[ $GLASS == 1 ]] && echo true || echo false)"
    python3 -I "$MG/icons/build-icons.py"
    # switch the glass on/off later: `macglass-glass` (terminal) or "MacGlass Icon Style" (app launcher)
    install -m 755 "$HERE/bin/macglass-glass" "$BIN/macglass-glass"
    sed "s|@BIN@|$BIN|g" "$HERE/apps/org.macglass.IconStyle.desktop" > "$DATA/applications/org.macglass.IconStyle.desktop"
}
files_stack() {
    rm -rf "$MG/src/macglass-stack"; mkdir -p "$MG/src"; cp -a "$HERE/stack" "$MG/src/macglass-stack"
    rm -f "$MG/src/macglass-stack/org.macglass.DownloadsStack.desktop"
    (cd "$MG/src/macglass-stack" && ./build.sh)
    cp "$HERE/stack/org.macglass.DownloadsStack.desktop" "$DATA/applications/"
}
files_extras() {
    # Quick Look (Space in Dolphin)
    cp "$HERE/apps/quicklook/QuickLook.qml" "$MG/quicklook/"
    install -m 755 "$HERE/apps/quicklook/macglass-quicklook" "$BIN/macglass-quicklook"
    install -m 755 "$HERE/apps/quicklook/macglass-quicklook.desktop" "$DATA/kio/servicemenus/macglass-quicklook.desktop"
    cp "$HERE/dolphin/dolphinui.rc" "$DATA/kxmlgui5/dolphin/dolphinui.rc"   # shortcuts only (Space → Quick Look)
    # scripts + login rebuild check
    install -m 755 "$HERE/bin/check-rebuilds.sh" "$MG/bin/check-rebuilds.sh"
    install -m 755 "$HERE/lib/configure-menubar.py" "$MG/bin/configure-menubar.py"
    cp "$HERE/lib/menubar.js" "$MG/bin/menubar.js"
    printf '[Desktop Entry]\nType=Application\nName=MacGlass rebuild check\nComment=Warns when MacGlass components need a rebuild after system updates\nExec=%s\nNoDisplay=true\nX-KDE-autostart-phase=2\n' \
        "$MG/bin/check-rebuilds.sh" > "$CONF/autostart/macglass-check-rebuilds.desktop"
    cp "$HERE/README.md" "$MG/SETUP-README.md"
}
tui_run "Colour scheme and Plasma style" files_theme
tui_run "Menu-bar widgets (active app, Control Center, Notification Center)" files_widgets
tui_run "Icon theme ($([[ $GLASS == 1 ]] && echo "liquid glass" || echo "plain"))" files_icons
tui_run "Downloads stack (compiling)" files_stack
tui_run "Quick Look, Dolphin shortcut, login rebuild check" files_extras
sleep 1

# ═════════════════════════════════════════════════════════════════════════════
# 7. Settings
# ═════════════════════════════════════════════════════════════════════════════
tui_screen $S_SETTINGS
set_look() {
    cp "$HERE/config/klassyrc" "$HERE/config/windecopresetsrc" "$CONF/klassy/"
    for f in darklyrc krunnerrc macglassstackrc kremarc; do cp "$HERE/config/$f" "$CONF/$f"; done
    kw kdeglobals KDE widgetStyle Darkly
    kw kdeglobals KDE AnimationDurationFactor 0.5
    kw kdeglobals KDE frameContrast 0.12
    kw kdeglobals General font "Inter,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    kw kdeglobals General menuFont "Inter,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    kw kdeglobals General toolBarFont "Inter,9,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    kw kdeglobals General smallestReadableFont "Inter,8,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    kw kdeglobals General fixed "JetBrainsMono Nerd Font,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    kw kdeglobals WM activeFont "Inter,10,-1,5,600,0,0,0,0,0,0,0,0,0,0,1"
    kw kdeglobals General XftAntialias true
    kw kdeglobals General XftHintStyle hintslight
    kw kdeglobals General XftSubPixel rgb
    kw kcminputrc Mouse cursorTheme capitaine-cursors
    kw kcminputrc Mouse cursorSize 24
}
set_kwin() {
    # window decoration: Klassy, traffic lights on the left
    kwg kwinrc org.kde.kdecoration2 library org.kde.klassy
    kwg kwinrc org.kde.kdecoration2 theme Klassy
    kwg kwinrc org.kde.kdecoration2 ButtonsOnLeft XIA
    kwg kwinrc org.kde.kdecoration2 ButtonsOnRight ""
    kwg kwinrc org.kde.kdecoration2 BorderSize None
    kwg kwinrc org.kde.kdecoration2 BorderSizeAuto false
    # effects: native blur, scale open/close, genie minimise
    kwg kwinrc Plugins blurEnabled true
    kwg kwinrc Plugins contrastEnabled true
    kwg kwinrc Plugins scaleEnabled true
    kwg kwinrc Plugins magiclampEnabled true
    for e in fadeEnabled glideEnabled squashEnabled translucencyEnabled wobblywindowsEnabled better_blur_dxEnabled; do kwg kwinrc Plugins "$e" false; done
    kwg kwinrc Effect-blur BlurStrength 11
    kwg kwinrc Effect-blur NoiseStrength 3
    kwg kwinrc Effect-magiclamp AnimationDuration 280
    # hot corners: top-right = Mission Control (Overview, also top-left), bottom-right = Show Desktop
    kwg kwinrc Effect-overview BorderActivate "1,7"
    kwg kwinrc ElectricBorders BottomRight ShowDesktop
    # rounded corners for Steam's self-drawn frame only (never games: steam_app_* excluded first)
    if pacman -Q kwin-effect-rounded-corners-git >/dev/null 2>&1; then
        kwg kwinrc Plugins kwin4_effect_shapecornersEnabled true
        for kv in Inclusions=steam Exclusions=steam_app IncludeNormalWindows=false IncludeDialogs=false Size=12 InactiveCornerRadius=12 \
                  DisableRoundFullScreen=true DisableRoundMaximize=true DisableRoundTile=true UseNativeDecorationShadows=true UseSquircleShape=false \
                  OutlineThickness=1 SecondOutlineThickness=1 InactiveOutlineThickness=1 InactiveSecondOutlineThickness=1 \
                  ActiveOutlineAlpha=90 ActiveSecondOutlineAlpha=28 InactiveOutlineAlpha=60 InactiveSecondOutlineAlpha=18; do
            kwg kwinrc Round-Corners "${kv%%=*}" "${kv#*=}"
        done
    fi
    # window rule: games and media always fully opaque
    kwg kwinrulesrc macglass-opaque Description "MacGlass: games and media stay fully opaque"
    kwg kwinrulesrc macglass-opaque wmclass '^(steam_app_.*|gamescope|.*\.exe|steam_proton|minecraft.*|org\.prismlauncher.*|mpv|vlc|org\.kde\.haruna|org\.kde\.gwenview|org\.kde\.kdenlive|org\.kde\.krita|krita|blender|com\.obsproject\.Studio|obs|gimp.*|org\.gimp\.GIMP|org\.inkscape\.Inkscape|darktable|resolve)$'
    kwg kwinrulesrc macglass-opaque wmclassmatch 3
    kwg kwinrulesrc macglass-opaque wmclasscomplete false
    kwg kwinrulesrc macglass-opaque opacityactive 100
    kwg kwinrulesrc macglass-opaque opacityactiverule 2
    kwg kwinrulesrc macglass-opaque opacityinactive 100
    kwg kwinrulesrc macglass-opaque opacityinactiverule 2
    local order; order="$(kreadconfig6 --file kwinrulesrc --group General --key Order)"      # Plasma 6 rule list
    [[ ",$order," == *",macglass-opaque,"* ]] || kwg kwinrulesrc General Order "${order:+$order,}macglass-opaque"
}
set_dolphin_gtk() {
    kwg dolphinrc General ShowFullPathInTitlebar false
    kwg dolphinrc General ShowZoomSlider false
    kwg dolphinrc DetailsMode HighlightEntireRow true
    kwg dolphinrc DetailsMode LeftPadding 0
    kwg dolphinrc IconsMode IconSize 64
    kwg dolphinrc IconsMode PreviewSize 64
    kwg dolphinrc PlacesPanel IconSize 16
    kwg dolphinrc "KFileDialog Settings" "Places Icons Static Size" 16
    # GTK apps: rounded client-side windows, macOS button order, MacGlass icons/cursor/font
    cp "$HERE/gtk/macglass.css" "$CONF/gtk-3.0/macglass.css"
    grep -qs "macglass.css" "$CONF/gtk-3.0/gtk.css" || printf "\n@import 'macglass.css';\n" >> "$CONF/gtk-3.0/gtk.css"
    for v in gtk-3.0 gtk-4.0; do kwg "$CONF/$v/settings.ini" Settings gtk-decoration-layout "close,minimize,maximize:"; done
    kwg "$CONF/gtk-3.0/settings.ini" Settings gtk-modules "colorreload-gtk-module:window-decorations-gtk-module:appmenu-gtk-module"
    kwg "$CONF/gtk-3.0/settings.ini" Settings gtk-shell-shows-menubar 1
}
set_apply() {
    plasma-apply-colorscheme MacGlassDark || echo "warning: colour scheme not applied"
    plasma-apply-desktoptheme MacGlass-Dark || echo "warning: Plasma style not applied"
    plasma-apply-cursortheme capitaine-cursors || echo "warning: cursor not applied"
    /usr/lib/plasma-changeicons MacGlass 2>&1 || kw kdeglobals Icons Theme MacGlass
}
tui_run "Fonts, app style, cursor" set_look
tui_run "Window decoration, blur, animations, hot corners, game rule" set_kwin
tui_run "Finder-style Dolphin and GTK apps" set_dolphin_gtk
tui_run "Applying colours, Plasma style, cursor and icons" set_apply
sleep 1

# ═════════════════════════════════════════════════════════════════════════════
# 8. Menu bar
# ═════════════════════════════════════════════════════════════════════════════
tui_screen $S_MENUBAR
menubar() {
    qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$(cat "$HERE/lib/menubar.js")"
    sleep 2
    systemctl --user stop plasma-plasmashell.service
    python3 -I "$HERE/lib/configure-menubar.py" "$LOGO" || { systemctl --user start plasma-plasmashell.service; return 1; }
    systemctl --user start plasma-plasmashell.service
}
if [[ $DO_LAYOUT == 1 ]]; then
    tui_info "Your panels are replaced; the screen may flicker for a moment."
    tui_run "Building the menu bar (the Krema dock takes over the task bar)" menubar
else
    tui_skip "Your panels are kept"
fi
sleep 1

# ═════════════════════════════════════════════════════════════════════════════
# 9. Firefox and apps
# ═════════════════════════════════════════════════════════════════════════════
tui_screen $S_APPS
firefox_setup() {
    cp "$HERE/firefox/userChrome.css" "$MG/firefox/userChrome.css"
    mkdir -p "$FFPROF/chrome"; ln -sfn "$MG/firefox/userChrome.css" "$FFPROF/chrome/userChrome.css"
    touch "$FFPROF/user.js"
    while IFS= read -r line; do grep -qxF "$line" "$FFPROF/user.js" || echo "$line" >> "$FFPROF/user.js"; done <<'PREFS'
// MacGlass — traffic lights, rounded corners, Safari-style address bar (applied at every Firefox start)
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
user_pref("browser.tabs.inTitlebar", 1);
user_pref("widget.gtk.rounded-bottom-corners.enabled", true);
user_pref("browser.urlbar.trimURLs", true);
user_pref("browser.urlbar.trimHttps", true);
user_pref("browser.urlbar.trimWww", true);
user_pref("browser.urlbar.untrimOnUserInteraction.featureGate", true);
PREFS
}
if [[ $DO_FIREFOX == 0 ]]; then tui_skip "Firefox skipped (--no-firefox)"
elif [[ -n "$FFPROF" ]]; then tui_run "Firefox: traffic lights + Safari-style address bar" firefox_setup
else tui_warn "No Firefox profile found — skipped (open Firefox once, then: ./install.sh --no-packages)"; fi

# optional: monochrome tray icons for apps that support it
if [[ $DO_APPS == 1 ]]; then
    if [[ -f "$CONF/ZapZap/ZapZap.conf" ]]; then kwg "$CONF/ZapZap/ZapZap.conf" system tray_theme symbolic_light; tui_ok "ZapZap: monochrome tray icon"; fi
    if pacman -Q cachy-update >/dev/null 2>&1 || command -v arch-update >/dev/null; then
        mkdir -p "$CONF/arch-update"
        if grep -q '^TrayIconStyle=' "$CONF/arch-update/arch-update.conf" 2>/dev/null; then sed -i 's/^TrayIconStyle=.*/TrayIconStyle=light/' "$CONF/arch-update/arch-update.conf"
        else echo 'TrayIconStyle=light' >> "$CONF/arch-update/arch-update.conf"; fi
        tui_ok "Cachy-Update/Arch-Update: light tray icon"
    fi
    if [[ -d "$CONF/vesktop" ]]; then
        mkdir -p "$CONF/vesktop/userAssets"
        cp "$HERE/icons/src/vesktop-tray.png" "$CONF/vesktop/userAssets/tray"
        cp "$HERE/icons/src/vesktop-trayUnread.png" "$CONF/vesktop/userAssets/trayUnread"
        tui_ok "Vesktop: monochrome tray icon (next start)"
    fi
else
    tui_skip "App tray-icon tweaks skipped (--no-app-tweaks)"
fi
sleep 1

# ═════════════════════════════════════════════════════════════════════════════
# 10. Done
# ═════════════════════════════════════════════════════════════════════════════
tui_screen $S_DONE
reload() {
    qdbus6 org.kde.KWin /KWin reconfigure || true
    [[ $DO_LAYOUT == 1 ]] || systemctl --user restart plasma-plasmashell.service
    for pid in $(pgrep -x -u "$(id -u)" krema || true); do kill "$pid" 2>/dev/null || true; done
    sleep 1; setsid -f krema >/dev/null 2>&1
    kbuildsycoca6 || true
}
if [[ "${MACGLASS_NO_RELOAD:-0}" == 1 ]]; then tui_skip "test mode: no reload"
else tui_run "Reloading KWin, Plasma and the dock" reload; fi
echo
tui_box "$GR" "✓ MacGlass is installed" \
    "${B}Log out and back in once${C0} so every app picks up fonts, cursor and GTK settings." \
    "" \
    "${CY}•${C0} Icon style later:  \"MacGlass Icon Style\" in the app launcher" \
    "${CY}•${C0} Your own icons:    ~/.local/share/macglass/icons/personal/<name>.png" \
    "${CY}•${C0} Spotlight:         Alt+Space      ${CY}•${C0} Quick Look: Space in Dolphin" \
    "${CY}•${C0} Undo everything:   $HERE/uninstall.sh" \
    "${CY}•${C0} Notes and tweaks:  ~/.local/share/macglass/SETUP-README.md" \
    "--" \
    "${D}Log: $(tui_short "$TUI_LOG")${C0}"
echo

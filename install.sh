#!/usr/bin/env bash
# MacGlass — macOS-style KDE Plasma 6 desktop. Installer.
#
#   ./install.sh                 full install (asks for your sudo password for packages)
#   ./install.sh --no-packages   skip pacman/makepkg (packages already installed)
#   ./install.sh --keep-panels   don't replace your panels with the MacGlass menu bar
#   ./install.sh --no-firefox    don't touch the Firefox profile
#   ./install.sh --no-app-tweaks don't set monochrome tray icons for ZapZap/Vesktop/Cachy-Update
#   ./install.sh --glass / --no-glass   liquid-glass app icons yes/no (otherwise you are asked)
#   ./install.sh --yes           don't ask for confirmation
#
# Everything it changes is backed up first; ./uninstall.sh puts it back.
# Needs: an Arch-based distro (pacman), Plasma 6 on Wayland, run as your normal user (not root).
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
MG="$DATA/macglass"               # runtime home: recipes, scripts, backups
BIN="$HOME/.local/bin"

DO_PACKAGES=1 DO_LAYOUT=1 DO_FIREFOX=1 DO_APPS=1 ASSUME_YES=0 GLASS=
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

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }
kw()   { kwriteconfig6 --file "$1" --group "$2" --key "$3" "$4"; }   # file group key value
kwg()  { local f="$1"; shift; local args=(); while [[ $# -gt 2 ]]; do args+=(--group "$1"); shift; done; kwriteconfig6 --file "$f" "${args[@]}" --key "$1" "$2"; }

# ── 0. preflight ────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] || die "Run as your normal user, not root (sudo is used only for packages)."
command -v pacman >/dev/null || die "pacman not found: MacGlass targets Arch-based distros (CachyOS, Arch, EndeavourOS…)."
command -v plasmashell >/dev/null || die "KDE Plasma is not installed."
PV="$(plasmashell --version 2>/dev/null | awk '{print $2}')"
[[ "${PV%%.*}" -ge 6 ]] || die "Plasma 6 is required (found ${PV:-unknown})."
[[ "${XDG_SESSION_TYPE:-}" == wayland ]] || warn "Not a Wayland session — MacGlass is built for Plasma Wayland (the dock, stack and blur need it)."
for c in kwriteconfig6 kreadconfig6 qdbus6 systemctl python3; do command -v "$c" >/dev/null || die "Missing $c"; done

. /etc/os-release
LOGO=start-here-kde-symbolic; [[ "${ID:-}" == cachyos ]] && LOGO=macglass-cachyos-symbolic

if [[ -z "$GLASS" ]]; then
    if [[ $ASSUME_YES == 1 ]]; then GLASS=1
    else
        echo
        echo "  App icons: \"liquid glass\" gives every app icon the same rounded tile with a soft glass"
        echo "  rim and sheen (macOS Tahoe style); otherwise you get the WhiteSur icons as they are."
        read -r -p "  Use liquid-glass app icons? [Y/n] " g; [[ "$g" == [nN]* ]] && GLASS=0 || GLASS=1
    fi
fi

cat <<EOF

  MacGlass for KDE Plasma $PV
  • packages: $([[ $DO_PACKAGES == 1 ]] && echo "install repo deps + build Klassy, Darkly (patched), Krema (patched), WhiteSur icons, AppGrid, rounded-corners effect" || echo skipped)
  • menu bar: $([[ $DO_LAYOUT == 1 ]] && echo "REPLACES your current panels (Krema dock + macOS menu bar)" || echo "your panels are kept")
  • app icons: $([[ $GLASS == 1 ]] && echo "liquid glass" || echo "WhiteSur, no glass")
  • Firefox: $([[ $DO_FIREFOX == 1 ]] && echo "traffic lights + Safari-style address bar in your default profile" || echo skipped)
  • backup of every changed file → $MG/backups/setup-<time>/ (undo: ./uninstall.sh)

EOF
if [[ $ASSUME_YES == 0 ]]; then read -r -p "Continue? [y/N] " ok; [[ "$ok" == [yYsS]* ]] || exit 0; fi

# ── 1. backup ───────────────────────────────────────────────────────────────
TS="$(date +%Y%m%d-%H%M%S)"; BK="$MG/backups/setup-$TS"
mkdir -p "$BK/config" "$BK/data"
CONF_FILES=(kdeglobals kwinrc kwinrulesrc kcminputrc plasmarc plasmashellrc plasma-org.kde.plasma.desktop-appletsrc
            dolphinrc breezerc kglobalshortcutsrc darklyrc krunnerrc kremarc macglassstackrc macglassrc klassy gtk-3.0 gtk-4.0
            arch-update/arch-update.conf ZapZap/ZapZap.conf vesktop/userAssets autostart/macglass-check-rebuilds.desktop)
DATA_PATHS=(color-schemes/MacGlassDark.colors plasma/desktoptheme/MacGlass-Dark icons/MacGlass
            plasma/plasmoids/org.macglass.activeapp plasma/plasmoids/org.macglass.notificationcenter
            plasma/plasmoids/KdeControlStation kio/servicemenus/macglass-quicklook.desktop
            kxmlgui5/dolphin/dolphinui.rc applications/org.macglass.DownloadsStack.desktop)
: > "$BK/created.txt"
for f in "${CONF_FILES[@]}"; do
    if [[ -e "$CONF/$f" ]]; then mkdir -p "$BK/config/$(dirname "$f")"; cp -a "$CONF/$f" "$BK/config/$f"; else echo "config/$f" >> "$BK/created.txt"; fi
done
for f in "${DATA_PATHS[@]}"; do
    if [[ -e "$DATA/$f" ]]; then mkdir -p "$BK/data/$(dirname "$f")"; cp -a "$DATA/$f" "$BK/data/$f"; else echo "data/$f" >> "$BK/created.txt"; fi
done
for f in macglass-stack macglass-quicklook; do [[ -e "$BIN/$f" ]] || echo "bin/$f" >> "$BK/created.txt"; done
FFPROF=""
if [[ -f "$HOME/.mozilla/firefox/profiles.ini" || -f "$CONF/mozilla/firefox/profiles.ini" ]]; then
    FFROOT="$CONF/mozilla/firefox"; [[ -f "$FFROOT/profiles.ini" ]] || FFROOT="$HOME/.mozilla/firefox"
    # the profile Firefox actually starts: [Install…] Default=, else the profile marked Default=1
    rel="$(awk -F= '/^\[Install/{i=1} i&&/^Default=/{print $2; exit}' "$FFROOT/profiles.ini")"
    [[ -n "$rel" ]] || rel="$(awk -F= '/^\[Profile/{p=""} /^Path=/{p=$2} /^Default=1/{if(p!=""){print p; exit}}' "$FFROOT/profiles.ini")"
    [[ -n "$rel" && -d "$FFROOT/$rel" ]] && FFPROF="$FFROOT/$rel"
fi
if [[ $DO_FIREFOX == 1 && -n "$FFPROF" ]]; then
    mkdir -p "$BK/firefox"; echo "$FFPROF" > "$BK/firefox/profile"
    for f in user.js chrome/userChrome.css; do [[ -e "$FFPROF/$f" || -L "$FFPROF/$f" ]] && { mkdir -p "$BK/firefox/$(dirname "$f")"; cp -a "$FFPROF/$f" "$BK/firefox/$f"; } || echo "firefox/$f" >> "$BK/created.txt"; done
fi
echo "$BK" > "$MG/LAST_SETUP_BACKUP"
say "Backup: $BK"

# ── 2. packages ─────────────────────────────────────────────────────────────
if [[ $DO_PACKAGES == 1 ]]; then
    say "Repository packages"
    sudo pacman -S --needed --noconfirm base-devel git cmake ninja extra-cmake-modules \
        inter-font capitaine-cursors ttf-jetbrains-mono-nerd appmenu-gtk-module \
        python-pillow librsvg qt6-declarative qt6-multimedia qt6-webengine layer-shell-qt kio

    say "Local packages (built from the reviewed recipes in packages/)"
    mkdir -p "$MG/packages"
    for p in klassy darkly krema whitesur-icon-theme plasma6-applets-appgrid kwin-effect-rounded-corners-git; do
        dst="$MG/packages/$p"; mkdir -p "$dst"; cp -a "$HERE/packages/$p/." "$dst/"
        want="$(cd "$dst" && bash -c 'source PKGBUILD >/dev/null 2>&1; echo "${epoch:+$epoch:}$pkgver-$pkgrel"')"
        name="$(cd "$dst" && bash -c 'source PKGBUILD >/dev/null 2>&1; echo "${pkgname[0]}"')"
        have="$(pacman -Q "$name" 2>/dev/null | awk '{print $2}')"
        if [[ "$have" == "$want" ]]; then echo "   $name $have — already installed"; continue; fi
        say "   building $name $want (installed: ${have:-none})"
        (cd "$dst" && makepkg -si --noconfirm --needed -f) || die "Build of $name failed — see the output above."
    done
fi
for p in klassy darkly krema whitesur-icon-theme plasma6-applets-appgrid; do
    pacman -Q "$p" >/dev/null 2>&1 || die "Package $p is missing — run without --no-packages."
done

# ── 3. files ────────────────────────────────────────────────────────────────
say "Themes, widgets, apps"
mkdir -p "$DATA/color-schemes" "$DATA/plasma/desktoptheme" "$DATA/plasma/plasmoids" "$BIN" "$MG/bin" "$MG/firefox" "$MG/quicklook" \
         "$DATA/kio/servicemenus" "$DATA/kxmlgui5/dolphin" "$DATA/applications" "$CONF/autostart" "$CONF/klassy" "$CONF/gtk-3.0" "$CONF/gtk-4.0"
cp "$HERE/themes/color-schemes/MacGlassDark.colors" "$DATA/color-schemes/"
rm -rf "$DATA/plasma/desktoptheme/MacGlass-Dark"; cp -a "$HERE/themes/desktoptheme/MacGlass-Dark" "$DATA/plasma/desktoptheme/"
for p in org.macglass.activeapp org.macglass.notificationcenter KdeControlStation; do
    rm -rf "$DATA/plasma/plasmoids/$p"; cp -a "$HERE/plasmoids/$p" "$DATA/plasma/plasmoids/"
done
# keep the Control Station originals + patched copies where the rebuild check expects them
mkdir -p "$MG/packages/kde-control-station"
cp "$HERE/plasmoids/KdeControlStation.macglass-originals/"*.orig "$MG/packages/kde-control-station/"
cp "$HERE/plasmoids/KdeControlStation/contents/ui/CompactRepresentation.qml" "$MG/packages/kde-control-station/CompactRepresentation.qml.macglass"
cp "$HERE/plasmoids/KdeControlStation/contents/ui/layouts/Tahoe.qml" "$MG/packages/kde-control-station/Tahoe.qml.macglass"

# icon theme (MacGlass overrides on top of WhiteSur-dark)
# (your own icons in $MG/icons/personal/ survive a re-install)
[[ -d "$MG/icons/personal" ]] && mv "$MG/icons/personal" "$MG/.icons-personal.keep"
rm -rf "$MG/icons"; cp -a "$HERE/icons" "$MG/icons"
[[ -d "$MG/.icons-personal.keep" ]] && mv "$MG/.icons-personal.keep" "$MG/icons/personal"
kw macglassrc Icons Glass "$([[ $GLASS == 1 ]] && echo true || echo false)"
python3 -I "$MG/icons/build-icons.py" >/dev/null || die "Icon theme build failed."

# Downloads stack (C++/QML) → ~/.local
rm -rf "$MG/src/macglass-stack"; mkdir -p "$MG/src"; cp -a "$HERE/stack" "$MG/src/macglass-stack"
rm -f "$MG/src/macglass-stack/org.macglass.DownloadsStack.desktop"
say "   building the Downloads stack"
(cd "$MG/src/macglass-stack" && ./build.sh >/dev/null) || die "Downloads stack build failed."
cp "$HERE/stack/org.macglass.DownloadsStack.desktop" "$DATA/applications/"

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

# ── 4. settings ─────────────────────────────────────────────────────────────
say "Settings"
cp "$HERE/config/klassyrc" "$HERE/config/windecopresetsrc" "$CONF/klassy/"
for f in darklyrc krunnerrc macglassstackrc kremarc; do cp "$HERE/config/$f" "$CONF/$f"; done

# look and feel
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
order="$(kreadconfig6 --file kwinrulesrc --group General --key Order)"      # Plasma 6 rule list
[[ ",$order," == *",macglass-opaque,"* ]] || kwg kwinrulesrc General Order "${order:+$order,}macglass-opaque"

# Dolphin: Finder-like defaults
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

# apply the theme parts that need their own tools
plasma-apply-colorscheme MacGlassDark >/dev/null || warn "colour scheme not applied"
plasma-apply-desktoptheme MacGlass-Dark >/dev/null || warn "Plasma style not applied"
plasma-apply-cursortheme capitaine-cursors >/dev/null || warn "cursor not applied"
/usr/lib/plasma-changeicons MacGlass >/dev/null 2>&1 || kw kdeglobals Icons Theme MacGlass

# ── 5. menu bar ─────────────────────────────────────────────────────────────
if [[ $DO_LAYOUT == 1 ]]; then
    say "Menu bar (replacing panels; the Krema dock takes over the task bar)"
    out="$(qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$(cat "$HERE/lib/menubar.js")")" \
        || die "Plasma refused the layout script."
    sleep 2
    systemctl --user stop plasma-plasmashell.service
    python3 -I "$HERE/lib/configure-menubar.py" "$LOGO" || { systemctl --user start plasma-plasmashell.service; die "Menu bar configuration failed."; }
    systemctl --user start plasma-plasmashell.service
fi

# ── 6. Firefox ──────────────────────────────────────────────────────────────
if [[ $DO_FIREFOX == 1 ]]; then
    if [[ -n "$FFPROF" ]]; then
        say "Firefox ($FFPROF)"
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
    else
        warn "No Firefox profile found — skipped (run Firefox once, then ./install.sh --no-packages)."
    fi
fi

# ── 7. optional: monochrome tray icons for apps that support it ─────────────
if [[ $DO_APPS == 1 ]]; then
    if [[ -f "$CONF/ZapZap/ZapZap.conf" ]]; then kwg "$CONF/ZapZap/ZapZap.conf" system tray_theme symbolic_light; echo "   ZapZap: monochrome tray icon"; fi
    if pacman -Q cachy-update >/dev/null 2>&1 || command -v arch-update >/dev/null; then
        mkdir -p "$CONF/arch-update"; grep -q '^TrayIconStyle=' "$CONF/arch-update/arch-update.conf" 2>/dev/null \
            && sed -i 's/^TrayIconStyle=.*/TrayIconStyle=light/' "$CONF/arch-update/arch-update.conf" \
            || echo 'TrayIconStyle=light' >> "$CONF/arch-update/arch-update.conf"
        echo "   Cachy-Update/Arch-Update: light tray icon"
    fi
    if [[ -d "$CONF/vesktop" ]]; then
        mkdir -p "$CONF/vesktop/userAssets"
        cp "$HERE/icons/src/vesktop-tray.png" "$CONF/vesktop/userAssets/tray"
        cp "$HERE/icons/src/vesktop-trayUnread.png" "$CONF/vesktop/userAssets/trayUnread"
        echo "   Vesktop: monochrome tray icon (next start)"
    fi
fi

# ── 8. reload ───────────────────────────────────────────────────────────────
if [[ "${MACGLASS_NO_RELOAD:-0}" == 1 ]]; then echo "   (test mode: no reload)"; exit 0; fi
say "Reloading KWin, Plasma and the dock"
qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
[[ $DO_LAYOUT == 1 ]] || systemctl --user restart plasma-plasmashell.service
pkill -x krema 2>/dev/null || true; (setsid krema >/dev/null 2>&1 &)
kbuildsycoca6 >/dev/null 2>&1 || true

cat <<EOF

  MacGlass is installed.  Log out and back in once so every app picks up fonts, cursor and GTK settings.
  Undo everything:  $HERE/uninstall.sh
  Notes and tweaks: $MG/SETUP-README.md
EOF

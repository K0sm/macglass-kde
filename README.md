# MacGlass — a macOS-style KDE Plasma 6 desktop

A glassy, macOS-inspired Plasma 6 setup for Arch-based distros (built and tested on CachyOS, Plasma 6.8,
Wayland, NVIDIA). One script installs it, one script removes it.

```
git clone https://github.com/K0sm/macglass-kde.git && cd macglass-kde
./install.sh          # full-screen, step-by-step installer (sudo password once, for packages)
./uninstall.sh        # same style: shows what it restores, lets you pick a backup, puts everything back
```

Log out and back in once after installing.

## What you get

| Piece | Implementation |
|---|---|
| Window decoration | Klassy, traffic lights on the left (close · minimise · maximise), 12 px rounded corners, glass title bar |
| App style | Darkly (patched) — 12 px radius, translucent menus with blur, opaque list for games/media apps |
| Colours / Plasma style | *MacGlass Dark* colour scheme + *MacGlass-Dark* Plasma style (from MacTahoe-Dark by Vince Liuice, tuned): floating rounded popups at 55 % with native KWin blur |
| Icons / cursor / fonts | WhiteSur-dark + a small *MacGlass* override theme (Dolphin, Firefox, … tiles; symbolic menu-bar glyphs) · Capitaine cursors · Inter · JetBrains Mono Nerd Font |
| Liquid-glass icons (optional) | every app icon (dock, launcher, task switcher) on the same squircle tile with a soft glass rim and sheen; the installer asks, and **MacGlass Icon Style** switches it later |
| Menu bar | Distro logo (AppGrid launcher, **Meta**) · active app name · global menu · app status icons · input source · one chevron for system items · **Control Center** · **clock → Notification Center** |
| Control Center | KDE Control Station 2.11 (EliverLara, GPL-3), "Tahoe" layout, patched for a tray-sized icon and no empty tile |
| Notification Center | `org.macglass.notificationcenter` — macOS clock (tabular digits, moon while Do Not Disturb), click for notification history + calendar |
| Dock | Krema (patched): floating, parabolic zoom, dodges windows; **Downloads stack** as the last item |
| Downloads stack | `macglass-stack` (C++/QML): Fan / Grid / List like macOS, live thumbnails, drag & drop, Quick Look |
| Finder-style Dolphin | inset rounded glass sidebar, rounded content card(s) incl. split view, rounded path bar, borderless column header, balanced 8 px spacing |
| Quick Look | **Space** in Dolphin previews images, video, audio, PDF, text (Space/Esc close, Enter opens) |
| Spotlight | KRunner, free-floating, **Alt+Space** |
| Animations | scale open/close, genie minimise into the dock |
| Hot corners | top-right (and top-left) → Mission Control (Overview), bottom-right → Show Desktop |
| GTK apps | rounded client-side windows, macOS button order, same icons/cursor/font |
| Firefox | traffic lights, rounded corners, Safari-style centred address bar (optional) |
| Steam | rounded corners for its self-drawn window (games are never touched) |
| Games | a window rule keeps games and media players fully opaque; the blur is native KWin only |

Deliberately **not** included (they were personal to the machine this was built on): live wallpapers
(Wallpaper Engine), the login-screen background and monitor-rotation fixes, personal dock launchers.
Your wallpaper, monitors and login screen are left as they are.

## Requirements

- Arch-based distro with `pacman` (CachyOS, Arch, EndeavourOS, Garuda, …)
- KDE Plasma 6 on **Wayland**, run as your normal user (not root)
- Internet access for the package sources; ~1 GB free space for builds

## Options

```
./install.sh --no-packages    # packages already installed: only (re)apply files and settings
./install.sh --keep-panels    # keep your panels instead of the MacGlass menu bar (otherwise you are asked)
./install.sh --no-firefox     # leave the Firefox profile alone
./install.sh --no-app-tweaks  # don't switch ZapZap / Vesktop / Cachy-Update to monochrome tray icons
./install.sh --glass          # liquid-glass app icons, without asking
./install.sh --no-glass       # plain WhiteSur app icons, without asking
./install.sh --yes            # ask nothing (liquid glass on, MacGlass menu bar, unless the flags above say otherwise)
```

Re-running `install.sh` is safe: each run makes a new backup first.

## What the installer does

It runs full-screen in the terminal, one step at a time, with a progress bar and the list of steps on top.
Menus work with ↑/↓ + Enter (or the option's number); long jobs show a spinner and timer, and their output goes to
`~/.local/share/macglass/logs/install-<time>.log` (a failure shows the end of it in a red box). Ctrl+C stops safely.

1. **Check** — Arch-based system, Plasma 6, Wayland, KDE tools.
2. **Your custom icons** — *before anything changes*, a table shows how custom icons are affected, marking what
   it found on your PC (your icon theme, launchers with image icons, own hicolor icons, folder icons):

   | How the icon was set | With MacGlass |
   |---|---|
   | Icon theme in System Settings | Replaced (uninstall restores it) |
   | Icons in `~/.local/share/icons/hicolor` | Replaced if WhiteSur has one with the same name |
   | App launcher pointing to an image file | Kept, but without the glass tile |
   | Folder icon from an image file | Kept |
   | Folder icon picked by name | Shown in WhiteSur style |

   To keep your own icons (glassed, and winning over WhiteSur), choose *Pause*: it opens
   `~/.local/share/macglass/icons/personal/`; save each icon as `<icon-name>.png` (the `Icon=` value of the app's
   `.desktop` file), press Enter, and the list refreshes.
3. **Options** — icon style (liquid glass / plain) and panels (MacGlass menu bar / keep yours), then a summary to confirm.
4. **Backup** — every config file and theme folder it will touch → `~/.local/share/macglass/backups/setup-<time>/`
   (plus a list of files it creates). `uninstall.sh` preselects the newest one; if you installed more than once,
   it offers the others too (the oldest is your desktop from before MacGlass). `--yes` skips its questions.
5. **Packages** — repo: Inter, JetBrains Mono Nerd Font, Capitaine cursors, appmenu-gtk-module, build tools and Qt
   modules. Built locally from the reviewed recipes in `packages/` (pinned versions/commits):
   `klassy`, `darkly` (+2 MacGlass patches), `krema` (+1 patch), `whitesur-icon-theme`,
   `plasma6-applets-appgrid`, `kwin-effect-rounded-corners-git`. Already-installed matching versions are skipped.
6. **Files** — colour scheme, Plasma style, icon theme (built by `icons/build-icons.py`), the three widgets,
   the Downloads stack (built into `~/.local`), Quick Look, Dolphin shortcut, login rebuild check.
7. **Settings** — via `kwriteconfig6`, key by key (other settings in those files are kept); whole files only
   for MacGlass-owned configs (`klassyrc`, `darklyrc`, `kremarc`, `krunnerrc`, `macglassstackrc`).
8. **Menu bar** — `lib/menubar.js` (Plasma scripting) replaces all panels with the top bar, then
   `lib/configure-menubar.py` writes the widget settings with Plasma stopped.
9. **Firefox and apps** — `userChrome.css` link + a few `user.js` prefs (default profile); monochrome tray icons.
10. **Done** — reloads KWin, Plasma and the dock, then shows what to do next.

## Folder layout

| Path | What |
|---|---|
| `install.sh`, `uninstall.sh` | install / undo |
| `packages/<name>/` | PKGBUILDs and patches (`darkly-finder-sidebar.patch`, `darkly-header-corner.patch`, `krema-respect-startupnotify.patch`) |
| `themes/` | MacGlass Dark colours, MacGlass-Dark Plasma style |
| `plasmoids/` | active-app name, Notification Center, Control Station (patched) + its originals |
| `stack/` | Downloads stack source + `build.sh` |
| `apps/quicklook/` | Quick Look viewer, launcher, Dolphin service menu |
| `icons/` | icon theme builder + sources |
| `config/` | MacGlass-owned config files (Klassy, Darkly, Krema, KRunner, stack) |
| `gtk/`, `firefox/`, `dolphin/` | GTK CSS, Firefox userChrome, Dolphin shortcut file |
| `lib/` | menu-bar builder, `tui.sh` (the installer's full-screen interface, plain bash) |
| `bin/check-rebuilds.sh` | login check (installed to `~/.local/share/macglass/bin/`) |
| `bin/macglass-glass`, `apps/org.macglass.IconStyle.desktop` | liquid-glass icons on/off tool + its launcher |

## Maintenance

Some parts are compiled against exact KWin/Qt versions. A login notification tells you when, with the command:
- **Krema** after a Qt minor update: `cd ~/.local/share/macglass/packages/krema && makepkg -si`
- **Rounded corners for Steam** after every KWin update: `cd ~/.local/share/macglass/packages/kwin-effect-rounded-corners-git && makepkg -si`
- **Control Center** after a KDE Store update overwrote the patch (the notification shows the `cp` command)
- Darkly / Klassy if the style or decoration disappears after a big Plasma update: `makepkg -si` in their folder
- Downloads stack if it stops opening after a KDE Frameworks/Qt update: `~/.local/share/macglass/src/macglass-stack/build.sh`

## Tweaks

- Corner radius: Klassy `WindowCornerRadius` and Darkly `CornerRadius` — keep them equal
- Glass: Klassy `TitleBarOpacityActive/Inactive`; Darkly `MenuOpacity`, `DolphinSidebarOpacity`
- Popup translucency: `~/.local/share/plasma/desktoptheme/MacGlass-Dark/dialogs/background.svgz` — change **all**
  `opacity:` values of the frame pieces together, or a square appears inside popups
- Liquid-glass icons on/off later, without re-installing: open **MacGlass Icon Style** from the app launcher
  (it asks *Liquid glass* / *Plain icons*; right-click it for direct on/off), or in a terminal
  `macglass-glass on|off|toggle|status`. It rebuilds the icons and refreshes the dock.
  Run `macglass-glass on` too after installing new apps, so their icons get the glass.
- Your own app icons: put `<icon-name>.png` in `~/.local/share/macglass/icons/personal/` and rebuild as above
  (they get the glass too; list names in `personal/no-glass.txt` to keep them exactly as they are)
- How much white at the glass borders: `RIM` / `EDGE` at the top of `icons/glass.py`
- Blur strength: System Settings → Desktop Effects → Blur
- Dock: right-click the dock → Settings
- Keep another app fully opaque: add it to Darkly `OpaqueApps` and to the KWin rule *MacGlass: games and media stay fully opaque*

## Known limitations

- Global menu works for Qt/KDE apps; Firefox exports none, GTK4/libadwaita apps have no menu bar.
- The notification history follows System Settings → Notifications ("Show in history"), including *Other applications*.
- Dolphin's Selection Mode moves from Space to **Ctrl+Shift+Space** (Space is Quick Look).

## Credits

Klassy (paulmcauley), Darkly (Bali10050), Krema (bhyoo), WhiteSur & MacTahoe (Vince Liuice), KDE Control Station
(EliverLara), AppGrid (xarbit), KDE-Rounded-Corners (matinlotfali). MacGlass patches and code: GPL-3.0-or-later.

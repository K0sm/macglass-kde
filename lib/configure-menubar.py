#!/usr/bin/env python3
"""MacGlass — write the menu-bar widget settings. Run with plasmashell STOPPED.

Finds the top panel that holds org.macglass.notificationcenter (created by menubar.js) and sets:
  - tray: app icons + input source visible; system applets behind one chevron (kept loaded: they handle
    the volume/brightness/media keys and the notification popups); useless applets dropped
  - Control Center (KDE Control Station): "Tahoe" layout, MacGlass icon, no colour-scheme switcher
  - Clock/Notification Center options, AppGrid on Meta with a monochrome logo
  - panel view: flush bar, 32 px, popups float with rounded corners ("Applets only")
Usage: configure-menubar.py <applet-logo-icon-name>
"""
import os, re, sys

CONF = os.environ.get('XDG_CONFIG_HOME', os.path.expanduser('~/.config'))
APPLETS = os.path.join(CONF, 'plasma-org.kde.plasma.desktop-appletsrc')
SHELLRC = os.path.join(CONF, 'plasmashellrc')
LOGO = sys.argv[1] if len(sys.argv) > 1 else 'start-here-kde-symbolic'

s = open(APPLETS, encoding='utf-8').read()


def sections(text):
    """yield (header, body) for every [..] section"""
    for m in re.finditer(r'^(\[[^\n]*\])\n(.*?)(?=^\[|\Z)', text, re.M | re.S):
        yield m.group(1), m.group(2)


def set_section(text, header, body):
    """replace (or append) a section's body"""
    text = re.sub(r'^' + re.escape(header) + r'\n.*?(?=^\[|\Z)', '', text, flags=re.M | re.S)
    return text.rstrip('\n') + '\n\n' + header + '\n' + body.strip('\n') + '\n'


# 1. locate the panel and its applets
top_panels = set()
nc_owner = set()
for h, b in sections(s):
    m = re.fullmatch(r'\[Containments\]\[(\d+)\]', h)
    if m and re.search(r'^plugin=org\.kde\.panel$', b, re.M) and re.search(r'^location=3$', b, re.M):
        top_panels.add(m.group(1))
    m = re.fullmatch(r'\[Containments\]\[(\d+)\]\[Applets\]\[\d+\]', h)
    if m and re.search(r'^plugin=org\.macglass\.notificationcenter$', b, re.M):
        nc_owner.add(m.group(1))
found = sorted(top_panels & nc_owner, key=int)
panel = found[-1] if found else None   # newest, if several
if panel is None:
    sys.exit('configure-menubar: MacGlass top panel not found (did menubar.js run?)')

P = '[Containments][%s]' % panel
ids = {}
for h, b in sections(s):
    m = re.fullmatch(re.escape(P) + r'\[Applets\]\[(\d+)\]', h)
    if m:
        pm = re.search(r'^plugin=(.*)$', b, re.M)
        if pm:
            ids[pm.group(1)] = m.group(1)
need = ['dev.xarbit.appgrid', 'org.kde.plasma.systemtray', 'KdeControlStation', 'org.macglass.notificationcenter']
missing = [n for n in need if n not in ids]
if missing:
    sys.exit('configure-menubar: widgets missing from the panel: ' + ', '.join(missing))

A = lambda plugin: P + '[Applets][%s]' % ids[plugin]

# 2. AppGrid: monochrome logo, opens with Meta
s = set_section(s, A('dev.xarbit.appgrid') + '[Configuration][General]',
                'useCustomButtonImage=true\ncustomButtonImage=%s\nuseThemeBackground=true\nhoverAnimation=0' % LOGO)
s = set_section(s, A('dev.xarbit.appgrid') + '[Shortcuts]', 'global=Meta')

# 3. Control Center (all KDE Control Station keys live in the "Appearance" group)
s = set_section(s, A('KdeControlStation') + '[Configuration][Appearance]', '\n'.join([
    'layout=3', 'icon=macglass-control-center-symbolic', 'useCustomButtonImage=false',
    'animations=true', 'transparency=true', 'transparencyLevel=40', 'showBorders=false',
    'isDarkTheme=true', 'showColorSwitcher=false', 'lightTheme=MacGlassDark', 'darkTheme=MacGlassDark',
    'showAvatar=true', 'showKDEConnect=true', 'showNightLight=true', 'showDnd=true',
    'showVolume=true', 'showBrightness=true', 'showMediaPlayer=true', 'showBattery=true',
    'showSessionActions=true', 'showScreenshot=true', 'screenshotCommand=spectacle']))

# 4. Clock / Notification Center
s = set_section(s, A('org.macglass.notificationcenter') + '[Configuration][General]', 'dateFormat=ddd d MMM\nuse24h=true')

# 5. System tray (the tray is itself a containment: its settings are in [Applets][id][General])
keep = ['org.kde.plasma.notifications', 'org.kde.plasma.volume', 'org.kde.plasma.networkmanagement',
        'org.kde.plasma.bluetooth', 'org.kde.plasma.brightness', 'org.kde.plasma.clipboard',
        'org.kde.plasma.devicenotifier', 'org.kde.plasma.mediacontroller', 'org.kde.plasma.keyboardlayout',
        'org.kde.plasma.cameraindicator', 'org.kde.plasma.battery', 'org.kde.kdeconnect', 'org.kde.kscreen']
hidden = [k for k in keep if k not in ('org.kde.plasma.keyboardlayout', 'org.kde.plasma.cameraindicator')]
s = set_section(s, A('org.kde.plasma.systemtray') + '[General]', '\n'.join([
    'extraItems=' + ','.join(keep), 'knownItems=' + ','.join(keep),
    'hiddenItems=' + ','.join(hidden), 'shownItems=org.kde.plasma.keyboardlayout',
    'showAllItems=false', 'scaleIconsToFit=false', 'iconSpacing=2']))

s = re.sub(r'\n{3,}', '\n\n', s)
open(APPLETS, 'w', encoding='utf-8').write(s)

# 6. Panel view: flush, 32 px, translucent, popups float ("Applets only")
r = open(SHELLRC, encoding='utf-8').read() if os.path.exists(SHELLRC) else ''
r = set_section(r, '[PlasmaViews][Panel %s]' % panel, 'floating=0\nfloatingApplets=1\npanelOpacity=2\nshell=org.kde.plasma.desktop')
r = set_section(r, '[PlasmaViews][Panel %s][Defaults]' % panel, 'thickness=32')
open(SHELLRC, 'w', encoding='utf-8').write(r)
print('configure-menubar: panel %s configured' % panel)

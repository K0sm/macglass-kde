#!/usr/bin/env python3
"""MacGlass icon overrides — builds ~/.local/share/icons/MacGlass (inherits WhiteSur-dark).

Every icon uses WhiteSur's tile geometry (body 64..960 of 1024, soft drop shadow) so it sits evenly
in the dock. Re-run after editing:  python3 ~/.local/share/macglass/icons/build-icons.py
"""
import os, shutil, subprocess, tempfile
from PIL import Image, ImageChops, ImageDraw, ImageFilter

HOME = os.path.expanduser('~')
SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'src')
OUT = os.environ.get('MACGLASS_ICON_OUT') or os.path.join(os.environ.get('XDG_DATA_HOME', os.path.join(HOME, '.local/share')), 'icons/MacGlass')
# Liquid-glass icons: chosen at install time ([Icons] Glass in ~/.config/macglassrc, default on);
# MACGLASS_GLASS=0/1 overrides it for one run.
def _glass_setting():
    if os.environ.get('MACGLASS_GLASS') in ('0', '1'):
        return os.environ['MACGLASS_GLASS'] == '1'
    import configparser
    cp = configparser.ConfigParser()
    cp.read(os.path.join(os.environ.get('XDG_CONFIG_HOME', os.path.join(HOME, '.config')), 'macglassrc'))
    return cp.get('Icons', 'Glass', fallback='true').lower() != 'false'
GLASS = _glass_setting()
WS = '/usr/share/icons/WhiteSur-dark/apps/scalable'
N = 1024
BODY = (64, 64, 960, 960)

def svg(path, size):
    with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as t:
        subprocess.run(['rsvg-convert', '-w', str(size), '-h', str(size), path, '-o', t.name], check=True)
        im = Image.open(t.name).convert('RGBA'); im.load()
    os.unlink(t.name)
    return im

def squircle_mask(box, n=5.0, ss=4):
    x0, y0, x1, y1 = box; w, h = (x1 - x0) * ss, (y1 - y0) * ss
    m = Image.new('L', (w, h), 0); px = m.load(); a, b = w / 2, h / 2
    for y in range(h):
        dy = abs((y + 0.5 - b) / b) ** n
        if dy > 1: continue
        dx = (1 - dy) ** (1 / n) * a
        for x in range(int(a - dx), int(a + dx)):
            px[x, y] = 255
    full = Image.new('L', (N, N), 0)
    full.paste(m.resize((x1 - x0, y1 - y0), Image.LANCZOS), (x0, y0))
    return full

MASK = squircle_mask(BODY)

def tile(top, bottom):
    """Vertical gradient squircle tile with WhiteSur-like shadow and a faint top highlight."""
    grad = Image.new('RGBA', (N, N))
    d = ImageDraw.Draw(grad)
    for y in range(N):
        t = y / (N - 1)
        d.line([(0, y), (N, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,))
    shadow = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    sh = MASK.point(lambda v: int(v * 0.42)).filter(ImageFilter.GaussianBlur(22))
    shadow.putalpha(sh); shadow = shadow.transform((N, N), Image.AFFINE, (1, 0, 0, 0, 1, -14))
    body = Image.new('RGBA', (N, N), (0, 0, 0, 0)); body.paste(grad, (0, 0), MASK)
    hl = Image.new('RGBA', (N, N), (255, 255, 255, 0))
    if not GLASS:   # the glass pass adds its own (soft) sheen
        ImageDraw.Draw(hl).rectangle([0, 0, N, 300], fill=(255, 255, 255, 18))
    hl.putalpha(Image.composite(hl.split()[3], Image.new('L', (N, N), 0), MASK))
    return Image.alpha_composite(Image.alpha_composite(shadow, body), hl)

def place(base, art, scale):
    s = int((BODY[2] - BODY[0]) * scale)
    art = art.resize((s, s), Image.LANCZOS)
    base.alpha_composite(art, ((N - s) // 2, (N - s) // 2 - 6))
    return base

# start clean, so icons of uninstalled apps don't linger
shutil.rmtree(os.path.join(OUT, 'apps/512'), ignore_errors=True)
os.makedirs(os.path.join(OUT, 'apps/512'), exist_ok=True)

def write(im, name):
    im.resize((512, 512), Image.LANCZOS).save(os.path.join(OUT, 'apps/512', name + '.png'))

BASE = {}   # artwork made below; the glass pass (or a plain write) turns it into the final icon
def save(im, name):
    BASE[name] = im
    print('built', name)

# ZapZap: WhiteSur artwork, pre-rendered (Qt's SVG renderer drops its green "Z").
save(svg(f'{WS}/com.rtosta.zapzap.svg', N), 'com.rtosta.zapzap')
# Firefox: official logo on a dark graphite tile.
save(place(tile((58, 57, 66), (28, 27, 34)), svg('/usr/share/icons/hicolor/scalable/apps/firefox.svg', N), 0.80), 'firefox')
# MailCraft: WhiteSur Mail-style icon.
save(svg(f'{WS}/internet-mail.svg', N), 'io.github.billsecond.mailcraft')
# Cider: Apple-Music style — white tile, black double note.
def recolor_svg(path, color):
    with open(path) as f: txt = f.read().replace('#ffffff', color)
    t = tempfile.NamedTemporaryFile('w', suffix='.svg', delete=False); t.write(txt); t.close()
    im = svg(t.name, N); os.unlink(t.name); return im
save(place(tile((255, 255, 255), (232, 232, 236)), recolor_svg(os.path.join(SRC, 'music-note.svg'), '#1d1d1f'), 1.0), 'cider')
# Dolphin: KDE's own Dolphin artwork (folder + dolphin) on a light tile — not Finder.
dol = place(tile((250, 250, 252), (226, 228, 234)), svg('/usr/share/icons/hicolor/scalable/apps/org.kde.dolphin.svg', N), 0.72)
save(dol, 'org.kde.dolphin'); save(dol, 'system-file-manager')
# Stremio Enhanced: official logo on a deep purple tile.
if os.path.exists('/usr/share/icons/hicolor/512x512/apps/stremio-enhanced.png'):
    st = Image.open('/usr/share/icons/hicolor/512x512/apps/stremio-enhanced.png').convert('RGBA')
    save(place(tile((52, 34, 92), (22, 14, 44)), st, 0.74), 'stremio-enhanced')

# Personal artwork (optional): any <icon-name>.png in icons/personal/ replaces that app's icon,
# fitted to the same squircle tile + shadow (and glassed unless listed in personal/no-glass.txt).
PERS = os.path.join(os.path.dirname(SRC), 'personal')
def fill_holes(art):
    """see-through cut-outs inside the tile (e.g. a logo knocked out of it) become white,
    as they look on Apple's own light backdrop; the outside stays transparent"""
    a = art.split()[3]
    outside = a.point(lambda v: 255 if v < 128 else 0)
    seed = Image.new('L', (a.width + 2, a.height + 2), 255); seed.paste(outside, (1, 1))
    ImageDraw.floodfill(seed, (0, 0), 128)
    inside = seed.crop((1, 1, a.width + 1, a.height + 1)).point(lambda v: 0 if v == 128 else 255)
    inside = inside.filter(ImageFilter.MaxFilter(3))
    under = Image.new('RGBA', art.size, (255, 255, 255, 0)); under.putalpha(inside)
    out = Image.alpha_composite(under, art)
    out.putalpha(ImageChops.lighter(art.split()[3], inside))
    return out

def fit_tile(art):
    x0, y0, x1, y1 = BODY
    art = fill_holes(art.convert('RGBA')).resize((x1 - x0, y1 - y0), Image.LANCZOS)
    layer = Image.new('RGBA', (N, N), (0, 0, 0, 0)); layer.paste(art, (x0, y0))
    a = Image.composite(layer.split()[3], Image.new('L', (N, N), 0), MASK); layer.putalpha(a)
    shadow = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    shadow.putalpha(a.point(lambda v: int(v * 0.42)).filter(ImageFilter.GaussianBlur(22)))
    shadow = shadow.transform((N, N), Image.AFFINE, (1, 0, 0, 0, 1, -14))
    return Image.alpha_composite(shadow, layer)
personal = []
PERS_ART = {}   # personal artwork that still gets the glass layers
# names listed in personal/no-glass.txt are used exactly as supplied (e.g. art that is glass already)
noglass = set(open(os.path.join(PERS, 'no-glass.txt')).read().split()) if os.path.exists(os.path.join(PERS, 'no-glass.txt')) else set()
if os.path.isdir(PERS):
    for f in sorted(os.listdir(PERS)):
        if f.endswith('.png'):
            im = fit_tile(Image.open(os.path.join(PERS, f)))
            if f[:-4] in noglass or not GLASS: write(im, f[:-4])
            else: PERS_ART[f[:-4]] = im
            personal.append(f[:-4])
            print('personal', f[:-4])

# Liquid glass: every launcher icon (and the artwork above) on the squircle with rim + sheen.
if GLASS:
    import sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import glass
    glass.make_pass(N, BODY, MASK, tile, place)(BASE, personal, write, PERS_ART)
else:
    for n, im in BASE.items():
        if n not in personal: write(im, n)

# Symbolic glyphs (recoloured by Plasma to the menu-bar text colour).
os.makedirs(os.path.join(OUT, 'status/symbolic'), exist_ok=True)
for f in sorted(os.listdir(SRC)):
    if f.endswith('.svg') and f not in ('music-note.svg', 'tv-glyph.svg'):   # those two are artwork, not glyphs
        shutil.copy(os.path.join(SRC, f), os.path.join(OUT, 'status/symbolic', f))
        print('built', f[:-4])

with open(os.path.join(OUT, 'index.theme'), 'w') as f:
    f.write('[Icon Theme]\nName=MacGlass\nComment=MacGlass app icon overrides on top of WhiteSur-dark\n'
            'Inherits=WhiteSur-dark,breeze-dark,hicolor\nDirectories=apps/512,status/symbolic\n\n'
            '[apps/512]\nSize=512\nMinSize=8\nMaxSize=1024\nContext=Applications\nType=Scalable\n\n'
            '[status/symbolic]\nSize=16\nMinSize=8\nMaxSize=512\nContext=Status\nType=Scalable\n')
subprocess.run(['gtk-update-icon-cache', '-f', '-t', OUT], check=False, capture_output=True)
print('theme written to', OUT)

"""MacGlass "liquid glass" pass — imported by build-icons.py.

For every app icon used by a launcher (.desktop Icon=) plus the icons build-icons.py made itself:
  1. take the artwork (build-icons output, else WhiteSur-dark → WhiteSur → hicolor → breeze → pixmaps)
  2. square tile art → cropped to its body and fitted to the MacGlass squircle;
     free-form art (no tile of its own) → placed on a dark glass tile
  3. glass: slightly more vivid colour, soft bright inner rim, top sheen, fine light edge, drop shadow
Personal artwork (icons/personal/*.png) is used as-is (only fitted), never glassed.
"""
import configparser, glob, os, re, subprocess, tempfile
from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter

HOME = os.path.expanduser('~')
THEMES = ['/usr/share/icons/WhiteSur-dark', '/usr/share/icons/WhiteSur', f'{HOME}/.local/share/icons/hicolor',
          '/usr/share/icons/hicolor', '/var/lib/flatpak/exports/share/icons/hicolor',
          f'{HOME}/.local/share/flatpak/exports/share/icons/hicolor', '/usr/share/icons/breeze-dark',
          '/usr/share/icons/breeze', '/usr/share/pixmaps']
APPDIRS = [f'{HOME}/.local/share/applications', '/usr/share/applications',
           '/var/lib/flatpak/exports/share/applications', f'{HOME}/.local/share/flatpak/exports/share/applications']


def _size_of(path):
    if path.endswith('.svg') and ('scalable' in path or not re.search(r'/\d+(x\d+)?(@\d+x)?/', path)):
        return 10000
    m = re.search(r'/(\d+)x\1(?:@\d+x)?/', path) or re.search(r'/(\d+)/', path)
    return int(m.group(1)) if m else 48


def index_themes():
    """name -> best file (theme order first, then svg > largest png)"""
    best = {}
    for t in THEMES:
        found = {}
        for root, _, files in os.walk(t, followlinks=True):
            if 'symbolic' in root or '/actions' in root or '/status' in root or '/emblems' in root:
                continue
            for f in files:
                n, ext = os.path.splitext(f)
                if ext not in ('.svg', '.png') or n.endswith('-symbolic'):
                    continue
                p = os.path.join(root, f)
                rank = lambda q: ('/apps' in q, _size_of(q))   # app icons beat same-named places/devices art
                if n not in found or rank(p) > rank(found[n]):
                    found[n] = p
        for n, p in found.items():
            best.setdefault(n, p)
    return best


def launcher_icons():
    names = set()
    for d in APPDIRS:
        for f in glob.glob(os.path.join(d, '*.desktop')):
            cp = configparser.ConfigParser(interpolation=None, strict=False)
            try:
                cp.read(f, encoding='utf-8')
                e = cp['Desktop Entry']
            except Exception:
                continue
            if e.get('NoDisplay', 'false').lower() == 'true' or e.get('Hidden', 'false').lower() == 'true':
                continue
            ic = e.get('Icon', '').strip()
            if ic and not ic.startswith('/'):
                names.add(re.sub(r'\.(png|svg|xpm)$', '', ic))
    return names


def load(path, N):
    if path.endswith('.svg'):
        with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as t:
            r = subprocess.run(['rsvg-convert', '-w', str(N), '-h', str(N), '-a', path, '-o', t.name],
                               capture_output=True)
            if r.returncode:
                os.unlink(t.name); return None
            im = Image.open(t.name).convert('RGBA'); im.load()
        os.unlink(t.name)
    else:
        im = Image.open(path).convert('RGBA')
    c = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    im.thumbnail((N, N), Image.LANCZOS) if max(im.size) > N else None
    if max(im.size) < N:
        s = N / max(im.size); im = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
    c.paste(im, ((N - im.width) // 2, (N - im.height) // 2), im)
    return c


RIM, EDGE = 0.26, 0.22   # white at the borders: inner rim glow, 1-px edge


def make_pass(N, BODY, MASK, tile, place):
    x0, y0, x1, y1 = BODY
    rim_soft = ImageChops.subtract(MASK, MASK.filter(ImageFilter.GaussianBlur(30))).point(lambda v: min(255, int(v * 2.2)))
    edge = ImageChops.subtract(MASK, MASK.filter(ImageFilter.MinFilter(5)))
    sheen = Image.new('L', (N, N), 0)
    d = ImageDraw.Draw(sheen)
    for y in range(y0, y0 + int((y1 - y0) * 0.55)):
        t = (y - y0) / ((y1 - y0) * 0.55)
        d.line([(0, y), (N, y)], fill=int(70 * (1 - t) ** 1.6))
    sheen = ImageChops.multiply(sheen, MASK)
    shadow_a = MASK.point(lambda v: int(v * 0.40)).filter(ImageFilter.GaussianBlur(22))
    WHITE = Image.new('RGBA', (N, N), (255, 255, 255, 255))

    def white(alpha_l, k):
        w = WHITE.copy(); w.putalpha(alpha_l.point(lambda v: int(v * k))); return w

    def to_tile(art):
        """art (RGBA NxN) -> opaque squircle-clipped tile (no shadow)"""
        a = art.split()[3]
        body = a.point(lambda v: 255 if v > 200 else 0)
        bb = body.getbbox()
        if not bb:
            return None
        bw, bh = bb[2] - bb[0], bb[3] - bb[1]
        fill = sum(body.crop(bb).histogram()[255:]) / float(bw * bh)
        if fill > 0.80 and 0.9 < bw / bh < 1.11:   # it is a tile already: fit its body to ours
            crop = art.crop(bb).resize((x1 - x0, y1 - y0), Image.LANCZOS)
            base = Image.new('RGBA', (N, N), (0, 0, 0, 0)); base.paste(crop, (x0, y0))
            # fill the squircle corners the source shape doesn't cover with its own edge colour
            under = Image.new('RGBA', (N, N), (0, 0, 0, 0))
            under.paste(crop.resize((8, 8), Image.LANCZOS).resize((x1 - x0, y1 - y0), Image.BILINEAR), (x0, y0))
            base = Image.alpha_composite(under, base)
        else:                                          # free-form art: dark glass tile
            content = art.crop(art.getbbox())
            sq = Image.new('RGBA', (max(content.size),) * 2, (0, 0, 0, 0))
            sq.paste(content, ((sq.width - content.width) // 2, (sq.height - content.height) // 2))
            base = place(tile((62, 62, 70), (26, 26, 32)), sq, 0.70)
        base.putalpha(MASK)
        return base

    def glass_on(t):
        """glass layers on an already fitted tile that carries its own shadow"""
        body = t.split()[3].point(lambda v: 255 if v > 200 else 0)
        m = ImageChops.multiply(body, MASK)
        out = t.copy()
        for layer, k in ((ImageChops.multiply(rim_soft, m), RIM), (ImageChops.multiply(sheen, m), 1.0), (ImageChops.multiply(edge, m), EDGE)):
            out = Image.alpha_composite(out, white(layer, k))
        return out

    def glass(t):
        rgb = ImageEnhance.Color(t).enhance(1.10)
        rgb.putalpha(MASK)
        out = Image.alpha_composite(rgb, white(ImageChops.multiply(rim_soft, MASK), RIM))
        out = Image.alpha_composite(out, white(sheen, 1.0))
        out = Image.alpha_composite(out, white(edge, EDGE))
        out.putalpha(MASK)
        sh = Image.new('RGBA', (N, N), (0, 0, 0, 0)); sh.putalpha(shadow_a)
        sh = sh.transform((N, N), Image.AFFINE, (1, 0, 0, 0, 1, -14))
        return Image.alpha_composite(sh, out)

    def run(base_icons, skip, write, personal_art=None):
        for n, art in (personal_art or {}).items():   # personal artwork: glass on top, no refit
            write(glass_on(art), n)   # keeps fit_tile's drop shadow, like every other icon
        idx = index_themes()
        names = (launcher_icons() | set(base_icons)) - set(skip)
        # folders (e.g. the Downloads stack) and generic UI icons stay as they are, like on macOS
        names = {n for n in names if not re.match(r'(folder|user-|view-|document-|edit-|go-|list-|media-|window-)', n)}
        done = 0
        for n in sorted(names):
            art = base_icons.get(n)
            if art is None:
                p = idx.get(n)
                if not p:
                    continue
                try:
                    art = load(p, N)
                except Exception:
                    art = None
                if art is None:
                    continue
            t = to_tile(art)
            if t is None:
                continue
            write(glass(t), n)
            done += 1
        print('glass: %d icons' % done)

    return run

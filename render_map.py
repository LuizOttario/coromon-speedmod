# Desenha um mapa do jogo (Tiled JSON) em PNG: python3 render_map.py <pasta/mapa.json> <saida.png>
# Com NOZONE=1 não contorna as áreas de encontro (A cinza, B amarelo, C vermelho).
import json, os, sys, base64, zlib, struct
from PIL import Image, ImageDraw

M = os.path.expanduser('~/.local/share/Steam/steamapps/common/Coromon/Resources/maps/')
mf = M + sys.argv[1]; out = sys.argv[2]
m = json.load(open(mf)); W, H, T = m['width'], m['height'], 16
ts = []
for t in m['tilesets']:
    src = os.path.normpath(os.path.join(os.path.dirname(mf), t['source']))
    if not os.path.exists(src):
        continue
    d = json.load(open(src))
    if 'image' in d:
        img = Image.open(os.path.normpath(os.path.join(os.path.dirname(src), d['image']))).convert('RGBA')
        ts.append((t['firstgid'], d, img, None))
    else:
        imgs = {x['id']: Image.open(os.path.normpath(os.path.join(os.path.dirname(src), x['image']))).convert('RGBA')
                for x in d.get('tiles', []) if 'image' in x}
        ts.append((t['firstgid'], d, None, imgs))
ts.sort(key=lambda x: x[0])
cache = {}


def tile(g):
    g &= 0x1FFFFFFF
    if g in cache:
        return cache[g]
    r = None
    for fg, d, img, imgs in reversed(ts):
        if g >= fg:
            i = g - fg
            if img is not None:
                c = d['columns']; tw, th = d['tilewidth'], d['tileheight']
                r = img.crop(((i % c) * tw, (i // c) * th, (i % c) * tw + tw, (i // c) * th + th))
            else:
                r = imgs.get(i)
            break
    cache[g] = r
    return r


can = Image.new('RGBA', (W * T, H * T), (30, 30, 40, 255))


def data(l):
    d = l['data']
    if isinstance(d, str):
        b = base64.b64decode(d)
        if l.get('compression') in ('zlib', 'gzip'):
            b = zlib.decompress(b, 47)
        d = struct.unpack('<%dI' % (len(b) // 4), b)
    return d


def walk(L, objs):
    for l in L:
        if l.get('type') == 'group':
            walk(l['layers'], objs)
        elif l['type'] == 'tilelayer' and l.get('visible', True) and 'Overlay' not in l['name']:
            for k, g in enumerate(data(l)):
                if g:
                    im = tile(g)
                    if im:
                        x, y = (k % W) * T, (k // W) * T
                        can.alpha_composite(im, (x, y + T - im.height))
        elif l['type'] == 'objectgroup':
            objs += l['objects']


objs = []
walk(m['layers'], objs)
dr = ImageDraw.Draw(can)
col = {'A': (120, 120, 120, 255), 'B': (255, 220, 0, 255), 'C': (255, 40, 40, 255)}
for o in objs:
    z = [p['value'] for p in o.get('properties', []) if p['name'] == 'zoneUID']
    if not z or os.environ.get('NOZONE'):
        continue
    k = z[0][-1]
    pts = ([(o['x'] + p['x'], o['y'] + p['y']) for p in o['polygon']] if 'polygon' in o else
           [(o['x'], o['y']), (o['x'] + o['width'], o['y']), (o['x'] + o['width'], o['y'] + o['height']), (o['x'], o['y'] + o['height'])])
    if k in col:
        dr.polygon(pts, outline=col[k], width=4 if k == 'C' else 3)
can.convert('RGB').save(out)
print(can.size)

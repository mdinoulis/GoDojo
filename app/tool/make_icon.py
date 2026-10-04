"""Generates the GoDojo launcher icon sources in app/assets/icon/.

碁 (go) in brush ink on a kaya board, with a red 道場 (dojo) seal.
Needs Pillow and the OFL fonts Yuji Boku / Yuji Syuku (Google Fonts):
  python tool/make_icon.py <dir containing YujiBoku-Regular.ttf and YujiSyuku-Regular.ttf>
Then: dart run flutter_launcher_icons
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

S = 1024
FONT_DIR = sys.argv[1] if len(sys.argv) > 1 else '.'
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'icon')
INK = (24, 20, 18, 255)
SEAL = (178, 34, 34, 255)


def font(name, size):
    return ImageFont.truetype(os.path.join(FONT_DIR, name), size)


def board():
    """Kaya wood with faint grain and grid lines."""
    img = Image.new('RGBA', (S, S))
    px = img.load()
    rnd = random.Random(7)
    phases = [(rnd.uniform(0.004, 0.012), rnd.uniform(0, 6.28), rnd.uniform(2, 6))
              for _ in range(6)]
    for y in range(S):
        for x in range(S):
            g = sum(math.sin(y * f + ph + math.sin(x * 0.003) * a) for f, ph, a in phases)
            t = y / S
            r = int(232 - 18 * t + 5 * g)
            gg = int(190 - 22 * t + 4 * g)
            b = int(118 - 26 * t + 3 * g)
            px[x, y] = (r, gg, b, 255)
    d = ImageDraw.Draw(img, 'RGBA')
    step = S / 6
    for i in range(1, 6):
        p = round(i * step)
        d.line([(p, 0), (p, S)], fill=(90, 60, 25, 40), width=6)
        d.line([(0, p), (S, p)], fill=(90, 60, 25, 40), width=6)
    return img


def text_center(d, xy, s, f, fill):
    l, t, r, b = d.textbbox((0, 0), s, font=f)
    d.text((xy[0] - (l + r) / 2, xy[1] - (t + b) / 2), s, font=f, fill=fill)


def emblem():
    """碁 + seal on a transparent canvas."""
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    text_center(d, (470, 455), '碁', font('YujiBoku-Regular.ttf', 760), INK)

    # Seal: red rounded square with 道場 in reserved (white) characters.
    seal = Image.new('RGBA', (270, 270), (0, 0, 0, 0))
    sd = ImageDraw.Draw(seal)
    sd.rounded_rectangle([0, 0, 269, 269], radius=26, fill=SEAL)
    sd.rounded_rectangle([14, 14, 255, 255], radius=16, outline=(255, 240, 230, 255), width=6)
    f = font('YujiSyuku-Regular.ttf', 112)
    text_center(sd, (135, 78), '道', f, (255, 244, 236, 255))
    text_center(sd, (135, 192), '場', f, (255, 244, 236, 255))
    seal = seal.rotate(-4, resample=Image.BICUBIC, expand=True)
    img.alpha_composite(seal, (S - seal.width - 70, S - seal.height - 70))
    return img


def shadowed(e):
    sh = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    sh.putalpha(e.getchannel('A').point(lambda a: a * 0.25))
    sh = sh.filter(ImageFilter.GaussianBlur(6))
    out = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    out.alpha_composite(sh, (6, 8))
    out.alpha_composite(e)
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    bg = board()
    em = shadowed(emblem())

    full = bg.copy()
    full.alpha_composite(em)
    full.convert('RGB').save(os.path.join(OUT, 'icon.png'))

    # Android adaptive icon: foreground must sit inside the central 66% safe zone.
    k = 0.64
    small = em.resize((round(S * k), round(S * k)), Image.LANCZOS)
    fg = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    fg.alpha_composite(small, ((S - small.width) // 2, (S - small.height) // 2))
    fg.save(os.path.join(OUT, 'icon_foreground.png'))
    bg.convert('RGB').save(os.path.join(OUT, 'icon_background.png'))


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Genera l'icona di Ciak.

L'icona è disegnata a codice invece che esportata da un editor: così resta
modificabile (colori, inclinazione, numero di denti) senza ripartire da zero.

    python3 Tools/make_icon.py

Scrive Ciak/Assets.xcassets/AppIcon.appiconset/AppIcon.png (1024×1024)
e un'anteprima a dimensioni reali in Tools/preview/.
"""

import math
import os
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SS = 4                      # sovracampionamento: si disegna in grande e si riduce
S = SIZE * SS

INK_TOP = (18, 18, 24)
INK_BOTTOM = (5, 5, 7)
SLATE = (36, 36, 45)
SLATE_EDGE = (255, 255, 255, 38)
ORANGE = (255, 96, 26)
ORANGE_DEEP = (255, 126, 40)


def u(v: float) -> int:
    """Da unità di disegno (base 1024) a pixel del canvas sovracampionato."""
    return int(round(v * SS))


def vertical_gradient(top, bottom):
    strip = Image.new("RGB", (1, 512))
    for y in range(512):
        t = y / 511
        strip.putpixel((0, y), tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return strip.resize((S, S), Image.BICUBIC)


def radial_mask(cx, cy, radius, strength):
    """Maschera morbida, calcolata in piccolo e ingrandita: il risultato è già sfumato."""
    n = 160
    mask = Image.new("L", (n, n), 0)
    px = mask.load()
    for y in range(n):
        for x in range(n):
            d = math.hypot(x / n - cx, y / n - cy) / radius
            if d < 1:
                px[x, y] = int(255 * strength * (1 - d) ** 2.2)
    return mask.resize((S, S), Image.BICUBIC)


def glow(color, cx, cy, radius, strength):
    layer = Image.new("RGBA", (S, S), color + (0,))
    layer.putalpha(radial_mask(cx, cy, radius, strength))
    return layer


def clapper_bar(width, height, teeth):
    """La tavoletta: base scura e denti diagonali arancioni, con angoli arrotondati."""
    w, h = u(width), u(height)
    bar = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(bar)
    draw.rectangle([0, 0, w, h], fill=SLATE + (255,))

    # Denti larghi e di un solo arancione: a 40 px le sfumature diventano fango.
    slant = u(74)
    tooth = w / (teeth * 2 - 1)
    x = -slant
    i = 0
    while x < w + slant:
        if i % 2 == 0:
            draw.polygon([(x, h), (x + tooth, h), (x + tooth + slant, 0), (x + slant, 0)],
                         fill=ORANGE + (255,))
        x += tooth
        i += 1

    # Angoli arrotondati applicati come maschera, così i denti restano dentro.
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], radius=u(22), fill=255)
    bar.putalpha(mask)
    return bar


def build():
    canvas = vertical_gradient(INK_TOP, INK_BOTTOM).convert("RGBA")
    # Un solo alone, tenuto basso: il fondo deve restare nero, non diventare marrone.
    canvas.alpha_composite(glow(ORANGE, 0.34, 0.26, 0.80, 0.16))

    # Corpo della ciacola. Tenuto dentro i margini: iOS ritaglia l'icona
    # con una maschera arrotondata e gli angoli sporgenti verrebbero tagliati.
    rect = [u(150), u(500), u(874), u(858)]
    body = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bd = ImageDraw.Draw(body)
    bd.rounded_rectangle(rect, radius=u(58), fill=SLATE + (255,),
                         outline=SLATE_EDGE, width=u(6))

    # Luce dall'alto sul corpo: senza, resta un rettangolo piatto.
    sheen = vertical_gradient((255, 255, 255), (255, 255, 255)).convert("RGBA")
    fade = Image.new("L", (1, 512))
    for y in range(512):
        fade.putpixel((0, y), int(26 * (1 - y / 511) ** 1.6))
    sheen.putalpha(fade.resize((S, S), Image.BICUBIC))
    shape = Image.new("L", (S, S), 0)
    ImageDraw.Draw(shape).rounded_rectangle(rect, radius=u(58), fill=255)
    body.alpha_composite(Image.composite(sheen, Image.new("RGBA", (S, S), (0, 0, 0, 0)), shape))

    # Una riga sola, leggibile: la lavagnetta su cui si scrive.
    ImageDraw.Draw(body).line([(u(214), u(724)), (u(810), u(724))],
                              fill=(255, 255, 255, 34), width=u(7))

    # Tavoletta incernierata, sollevata a destra come un ciak aperto.
    bar = clapper_bar(724, 196, teeth=4)
    bar_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bar_layer.paste(bar, (u(150), u(300)))
    hinge = (u(172), u(496))
    bar_layer = bar_layer.rotate(12, resample=Image.BICUBIC, center=hinge)

    # Alone dietro la tavoletta: stacca dal fondo senza sporcarlo.
    halo = bar_layer.filter(ImageFilter.GaussianBlur(u(30)))
    halo.putalpha(halo.getchannel("A").point(lambda a: int(a * 0.45)))

    canvas.alpha_composite(halo)
    canvas.alpha_composite(body)
    canvas.alpha_composite(bar_layer)

    return canvas.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)


if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    icon = build()

    destination = os.path.join(root, "Ciak", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")
    icon.save(destination, "PNG")
    print("scritta", os.path.relpath(destination, root))

    preview_dir = os.path.join(root, "Tools", "preview")
    os.makedirs(preview_dir, exist_ok=True)
    # Anteprima: l'icona grande e le misure in cui la vedrai davvero.
    sheet = Image.new("RGB", (1024, 1320), (12, 12, 14))
    sheet.paste(icon.resize((760, 760), Image.LANCZOS), (132, 60))
    x = 132
    for px in (180, 120, 80, 60, 40):
        small = icon.resize((px, px), Image.LANCZOS)
        sheet.paste(small, (x, 900 + (180 - px) // 2))
        x += px + 40
    sheet.save(os.path.join(preview_dir, "icon-preview.png"), "PNG")
    print("anteprima in Tools/preview/icon-preview.png")

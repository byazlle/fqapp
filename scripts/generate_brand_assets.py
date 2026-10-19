#!/usr/bin/env python3
"""Generate every brand asset for 流光 (Liuguang).

Requires Pillow: python -m pip install Pillow
From the repository root: python scripts/generate_brand_assets.py

Design language: aurora glass — a squircle carrying a violet→cyan mesh
gradient with magenta bloom, crossed by three tapered light ribbons that
read as "flowing light" (流光). Everything is drawn at 4x and downsampled
so the 16 px tray icon stays crisp.
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
BRANDING = ROOT / "assets" / "branding"
IMAGES = ROOT / "assets" / "images"
WEB = ROOT / "assets" / "web"
RUNNER = ROOT / "windows" / "runner" / "resources"
INSTALLER = ROOT / "windows" / "installer"

SOURCE_SIZE = 2048
SS = 2  # supersample factor on top of SOURCE_SIZE while drawing

# Palette -------------------------------------------------------------------
DEEP = (24, 12, 62)
VIOLET = (124, 92, 255)
CYAN = (34, 211, 238)
MAGENTA = (244, 114, 182)
INK = (10, 12, 20)


def hexc(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) for i in (0, 2, 4))  # type: ignore[return-value]


def mix(a, b, t: float):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def background(size: int) -> Image.Image:
    """Diagonal aurora gradient + magenta bloom, computed small then scaled."""
    small = 320
    base = Image.new("RGB", (small, small))
    pixels = base.load()
    stops = [(0.0, DEEP), (0.42, hexc("#5B3DE8")), (0.74, VIOLET), (1.0, CYAN)]
    for y in range(small):
        for x in range(small):
            t = (x * 0.62 + y * 0.38) / (small - 1)
            for i in range(len(stops) - 1):
                t0, c0 = stops[i]
                t1, c1 = stops[i + 1]
                if t <= t1 or i == len(stops) - 2:
                    local = 0.0 if t1 == t0 else max(0.0, min(1.0, (t - t0) / (t1 - t0)))
                    pixels[x, y] = mix(c0, c1, local)
                    break
    base = base.resize((size, size), Image.Resampling.BICUBIC)

    # Magenta bloom in the upper-right, cyan bloom lower-left.
    blooms = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(blooms)
    for cx, cy, radius, color, alpha in (
        (0.80, 0.14, 0.70, MAGENTA, 150),
        (0.10, 0.92, 0.62, (56, 232, 255), 110),
        (0.30, 0.30, 0.55, (255, 255, 255), 26),
    ):
        r = radius * size
        box = (cx * size - r, cy * size - r, cx * size + r, cy * size + r)
        draw.ellipse(box, fill=(*color, alpha))
    blooms = blooms.filter(ImageFilter.GaussianBlur(radius=size * 0.10))
    base = Image.alpha_composite(base.convert("RGBA"), blooms)
    return base


def bezier(p0, p1, p2, p3, t: float):
    mt = 1 - t
    x = mt**3 * p0[0] + 3 * mt**2 * t * p1[0] + 3 * mt * t**2 * p2[0] + t**3 * p3[0]
    y = mt**3 * p0[1] + 3 * mt**2 * t * p1[1] + 3 * mt * t**2 * p2[1] + t**3 * p3[1]
    return x, y


def ribbon(size: int, points, width: float, *, samples: int = 320, taper: float = 0.55):
    """Return an L-mode mask of a tapered ribbon following a cubic bezier."""
    layer = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(layer)
    left, right = [], []
    for i in range(samples + 1):
        t = i / samples
        x, y = bezier(*points, t)
        x2, y2 = bezier(*points, min(1.0, t + 0.004))
        dx, dy = x2 - x, y2 - y
        norm = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / norm, dx / norm
        # Tapered ends read as a light streak rather than a pipe.
        profile = math.sin(math.pi * t) ** taper
        half = width * profile * 0.5
        left.append((x + nx * half, y + ny * half))
        right.append((x - nx * half, y - ny * half))
    draw.polygon(left + right[::-1], fill=255)
    for end, sign in ((points[0], 1), (points[3], 1)):
        r = width * 0.5 * 0.12
        draw.ellipse((end[0] - r, end[1] - r, end[0] + r, end[1] + r), fill=255)
    return layer


def squircle_mask(size: int, radius_ratio: float = 0.235) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    r = int(size * radius_ratio)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=r, fill=255)
    return mask


def icon_canvas(size: int, *, simple: bool = False) -> Image.Image:
    """Full-colour brand mark, opaque background, no mask applied.

    ``simple`` drops the vignette, sheen and secondary ribbons: at 16-32 px
    the full composition collapses into a purple blob, so those sizes get a
    single high-contrast streak instead.
    """
    w = size
    canvas = background(w)

    if simple:
        specs = [
            (((-0.12, 0.62), (0.28, 0.24), (0.72, 0.80), (1.12, 0.42)), 0.190, 235),
            (((-0.08, 0.30), (0.40, 0.62), (0.66, 0.46), (1.10, 0.66)), 0.070, 140),
        ]
        for points, width_ratio, alpha in specs:
            pts = tuple((x * w, y * w) for x, y in points)
            mask = ribbon(w, pts, width=width_ratio * w)
            core = Image.new("RGBA", (w, w), (255, 255, 255, 0))
            core.putalpha(mask.point(lambda v, a=alpha: int(v * a / 255)))
            canvas = Image.alpha_composite(canvas, core)
        return canvas

    # Light ribbons: wide soft base, crisp core, thin highlight.
    specs = [
        (((-0.10, 0.60), (0.30, 0.16), (0.70, 0.88), (1.10, 0.40)), 0.112, 168),
        (((-0.06, 0.34), (0.36, 0.74), (0.64, 0.10), (1.08, 0.50)), 0.070, 120),
        (((-0.04, 0.84), (0.42, 0.56), (0.60, 0.64), (1.06, 0.78)), 0.040, 92),
    ]
    for points, width_ratio, alpha in specs:
        pts = tuple((x * w, y * w) for x, y in points)
        mask = ribbon(w, pts, width=width_ratio * w)
        glow = mask.filter(ImageFilter.GaussianBlur(radius=w * 0.035))
        tint = Image.new("RGBA", (w, w), (255, 255, 255, 0))
        tint.putalpha(glow.point(lambda v, a=alpha: int(v * a / 255 * 1.35)))
        canvas = Image.alpha_composite(canvas, tint)
        core = Image.new("RGBA", (w, w), (255, 255, 255, 0))
        core.putalpha(mask.point(lambda v, a=alpha: int(v * a / 255)))
        canvas = Image.alpha_composite(canvas, core)

    # Glass sheen across the top third.
    sheen = Image.new("RGBA", (w, w), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sheen)
    sd.ellipse(
        (-w * 0.35, -w * 0.85, w * 1.15, w * 0.42),
        fill=(255, 255, 255, 30),
    )
    sheen = sheen.filter(ImageFilter.GaussianBlur(radius=w * 0.05))
    canvas = Image.alpha_composite(canvas, sheen)

    # Corner vignette adds depth without darkening the centre.
    vignette = Image.new("L", (w, w), 0)
    ImageDraw.Draw(vignette).ellipse(
        (-w * 0.18, -w * 0.18, w * 1.18, w * 1.18), fill=255
    )
    vignette = vignette.filter(ImageFilter.GaussianBlur(radius=w * 0.12))
    shade = Image.new("RGBA", (w, w), (*DEEP, 0))
    shade.putalpha(vignette.point(lambda v: int((255 - v) * 0.42)))
    canvas = Image.alpha_composite(canvas, shade)

    # Inner hairline keeps the mark alive on white backgrounds.
    hair = Image.new("RGBA", (w, w), (0, 0, 0, 0))
    hd = ImageDraw.Draw(hair)
    hd.rounded_rectangle(
        (w * 0.012, w * 0.012, w * 0.988, w * 0.988),
        radius=int(w * 0.225),
        outline=(255, 255, 255, 60),
        width=max(1, int(w * 0.004)),
    )
    return Image.alpha_composite(canvas, hair)


def rounded_icon(size: int, *, opaque_background: bool) -> Image.Image:
    big = icon_canvas(size * SS, simple=size <= 32)
    mask = squircle_mask(size * SS)
    big.putalpha(mask)
    return big.resize((size, size), Image.Resampling.LANCZOS)


def save_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, optimize=True)
    print(f"  {path.relative_to(ROOT).as_posix()}  {image.width}x{image.height}")


def load_font(bold: bool, size: int) -> ImageFont.FreeTypeFont:
    candidates = [
        "C:/Windows/Fonts/msyhbd.ttc" if bold else "C:/Windows/Fonts/msyh.ttc",
        "C:/Windows/Fonts/segoeuib.ttf" if bold else "C:/Windows/Fonts/segoeui.ttf",
    ]
    for path in candidates:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def wizard_large(width: int = 164, height: int = 314) -> Image.Image:
    """Left-hand installer panel: gradient, mark, wordmark, taglines."""
    ss = 4
    w, h = width * ss, height * ss
    panel = Image.new("RGB", (w, h), INK)
    grad = background(w)
    panel.paste(grad.resize((w, h), Image.Resampling.BICUBIC), (0, 0))

    # Darkening veil so white type always has contrast.
    veil = Image.new("RGBA", (w, h), (8, 9, 16, 150))
    panel = Image.alpha_composite(panel.convert("RGBA"), veil)

    mark = rounded_icon(int(w * 0.56), opaque_background=True)
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse(
        (
            (w - mark.width) * 0.5 - w * 0.06,
            h * 0.10 - w * 0.06,
            (w + mark.width) * 0.5 + w * 0.06,
            h * 0.10 + mark.height + w * 0.06,
        ),
        fill=(124, 92, 255, 90),
    )
    panel = Image.alpha_composite(panel, glow.filter(ImageFilter.GaussianBlur(w * 0.04)))
    panel.alpha_composite(mark, ((w - mark.width) // 2, int(h * 0.10)))

    draw = ImageDraw.Draw(panel)
    title_font = load_font(True, int(w * 0.20))
    sub_font = load_font(False, int(w * 0.062))
    tiny_font = load_font(False, int(w * 0.050))

    title = "流光"
    tw = draw.textlength(title, font=title_font)
    draw.text(
        ((w - tw) / 2, int(h * 0.42)),
        title,
        font=title_font,
        fill=(255, 255, 255, 255),
    )

    latin = "L I U G U A N G"
    lw = draw.textlength(latin, font=tiny_font)
    draw.text(
        ((w - lw) / 2, int(h * 0.55)),
        latin,
        font=tiny_font,
        fill=(198, 205, 255, 255),
    )

    for index, line in enumerate(("小说 · 短剧 · 漫剧", "漫画 · 听书")):
        lwid = draw.textlength(line, font=sub_font)
        draw.text(
            ((w - lwid) / 2, int(h * 0.62) + index * int(h * 0.055)),
            line,
            font=sub_font,
            fill=(236, 238, 255, 235),
        )

    foot = "本机解密 · 本地缓存"
    fw = draw.textlength(foot, font=tiny_font)
    draw.text(
        ((w - fw) / 2, int(h * 0.86)),
        foot,
        font=tiny_font,
        fill=(255, 255, 255, 150),
    )

    return panel.convert("RGB").resize((width, height), Image.Resampling.LANCZOS)


def wizard_small(size: int = 55) -> Image.Image:
    canvas = Image.new("RGB", (size, size), INK)
    mark = rounded_icon(size, opaque_background=True)
    canvas.paste(mark, (0, 0), mark)
    return canvas


def main() -> None:
    print("brand: 流光 / Liuguang")
    master = rounded_icon(SOURCE_SIZE, opaque_background=False)
    save_png(master, BRANDING / "app_icon_source.png")

    # Windows tray / Explorer icon: every size Explorer may ask for.
    ico_sizes = [16, 24, 32, 48, 64, 128, 256]
    icons = [rounded_icon(s, opaque_background=True) for s in ico_sizes]
    RUNNER.mkdir(parents=True, exist_ok=True)
    ico_path = RUNNER / "app_icon.ico"
    icons[-1].save(
        ico_path,
        format="ICO",
        sizes=[(s, s) for s in ico_sizes],
        append_images=icons[:-1],
    )
    print(f"  {ico_path.relative_to(ROOT).as_posix()}  {ico_sizes}")

    logo = rounded_icon(384, opaque_background=True)
    IMAGES.mkdir(parents=True, exist_ok=True)
    logo_path = IMAGES / "app_logo.webp"
    logo.convert("RGB").save(logo_path, "WEBP", quality=92, method=6)
    print(f"  {logo_path.relative_to(ROOT).as_posix()}  384x384")

    save_png(rounded_icon(64, opaque_background=True), WEB / "favicon.png")

    INSTALLER.mkdir(parents=True, exist_ok=True)
    large = wizard_large()
    large.save(INSTALLER / "wizard-large.bmp", "BMP")
    print(f"  windows/installer/wizard-large.bmp  {large.width}x{large.height}")
    small = wizard_small()
    small.save(INSTALLER / "wizard-small.bmp", "BMP")
    print(f"  windows/installer/wizard-small.bmp  {small.width}x{small.height}")


if __name__ == "__main__":
    main()

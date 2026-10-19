#!/usr/bin/env python3
"""Generate every brand asset for 番茄端碗 (FanqieDuanwan).

Requires Pillow: python -m pip install Pillow
From the repository root: python scripts/generate_brand_assets.py

Design language: a warm tomato gradient squircle carrying a cream bowl with
one tomato in it — "番茄端碗" read literally. Drawn at 4x and downsampled so
the 16 px tray icon stays crisp.
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
DEEP = (108, 8, 18)
TOMATO = (232, 52, 42)
ORANGE = (255, 159, 28)
AMBER = (255, 201, 75)
CREAM = (255, 246, 236)
LEAF = (63, 174, 90)
INK = (21, 12, 11)


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
    stops = [(0.0, DEEP), (0.40, TOMATO), (0.76, ORANGE), (1.0, AMBER)]
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
        (0.78, 0.12, 0.68, AMBER, 140),
        (0.12, 0.90, 0.60, TOMATO, 120),
        (0.34, 0.26, 0.55, (255, 255, 255), 26),
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
    """番茄端碗的标志：一只白碗端着一颗番茄。

    ``simple`` 给 16/24/32 px 用：去掉叶蒂、高光与碗身阴影，加粗碗沿和
    番茄描边。小尺寸上细节只会糊成噪点，不如把两个主体放大、边缘留白。
    """
    w = size
    canvas = background(w).convert("RGBA")
    draw = ImageDraw.Draw(canvas)

    def px(v: float) -> float:
        return v * w

    ring = 0.030 if simple else 0.021
    tomato_r = 0.168 if simple else 0.150
    tomato_y = 0.375 if simple else 0.395

    # 碗身：下半圆 + 顶部碗沿，构成一个「碗」的剪影。
    # 椭圆的圆心必须落在碗口高度（0.50），这样 start=0/end=180 画出的
    # 下半圆顶边正好接着碗沿，不会和碗沿之间漏出一条背景缝。
    draw.pieslice(
        (px(0.168), px(0.15), px(0.832), px(0.85)),
        start=0,
        end=180,
        fill=(*CREAM, 255),
    )
    # 碗身内侧的一点暗部，让白碗不是一个纯色块。
    if not simple:
        shade = Image.new("RGBA", (w, w), (0, 0, 0, 0))
        ImageDraw.Draw(shade).pieslice(
            (px(0.232), px(0.255), px(0.768), px(0.80)),
            start=10,
            end=170,
            fill=(190, 120, 96, 60),
        )
        canvas = Image.alpha_composite(
            canvas, shade.filter(ImageFilter.GaussianBlur(radius=px(0.02)))
        )
        draw = ImageDraw.Draw(canvas)

    # 碗沿：一条比碗身略宽的圆角横条。
    draw.rounded_rectangle(
        (px(0.135), px(0.452), px(0.865), px(0.528)),
        radius=px(0.038),
        fill=(*CREAM, 255),
    )
    # 碗底的小圈足。
    draw.rounded_rectangle(
        (px(0.408), px(0.822), px(0.592), px(0.862)),
        radius=px(0.018),
        fill=(*CREAM, 235),
    )

    # 番茄：奶白描边保证在红底和橙底上都分得开。
    cx, cy, r = px(0.5), px(tomato_y), px(tomato_r)
    draw.ellipse(
        (cx - r - px(ring), cy - r - px(ring), cx + r + px(ring), cy + r + px(ring)),
        fill=(*CREAM, 255),
    )
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(*TOMATO, 255))

    if not simple:
        # 高光：左上方的一小片反光。
        hi = Image.new("RGBA", (w, w), (0, 0, 0, 0))
        ImageDraw.Draw(hi).ellipse(
            (cx - r * 0.72, cy - r * 0.78, cx - r * 0.06, cy - r * 0.20),
            fill=(255, 255, 255, 90),
        )
        canvas = Image.alpha_composite(
            canvas, hi.filter(ImageFilter.GaussianBlur(radius=px(0.012)))
        )
        draw = ImageDraw.Draw(canvas)
        # 叶蒂：三片小叶子 + 一截短梗。
        leaf_w = max(1, int(px(0.016)))
        for angle in (-140, -90, -40):
            rad = math.radians(angle)
            x2 = cx + math.cos(rad) * px(0.085)
            y2 = cy - r * 0.92 + math.sin(rad) * px(0.045)
            draw.line(
                (cx, cy - r * 0.88, x2, y2),
                fill=(*LEAF, 255),
                width=int(px(0.030)),
            )
        draw.line(
            (cx, cy - r * 0.94, cx, cy - r - px(0.055)),
            fill=(46, 138, 72, 255),
            width=leaf_w * 2,
        )
    else:
        # 小尺寸只留一根粗梗，叶子在 16px 上会变成一团绿斑。
        draw.line(
            (cx, cy - r * 0.96, cx, cy - r - px(0.045)),
            fill=(*LEAF, 255),
            width=max(2, int(px(0.045))),
        )

    # 顶部玻璃高光 + 轻微暗角，和其余品牌图保持同一套光照。
    sheen = Image.new("RGBA", (w, w), (0, 0, 0, 0))
    ImageDraw.Draw(sheen).ellipse(
        (-w * 0.30, -w * 0.80, w * 1.10, w * 0.34),
        fill=(255, 255, 255, 34),
    )
    canvas = Image.alpha_composite(
        canvas, sheen.filter(ImageFilter.GaussianBlur(radius=w * 0.05))
    )

    vignette = Image.new("L", (w, w), 0)
    ImageDraw.Draw(vignette).ellipse(
        (-w * 0.18, -w * 0.18, w * 1.18, w * 1.18), fill=255
    )
    vignette = vignette.filter(ImageFilter.GaussianBlur(radius=w * 0.12))
    shade = Image.new("RGBA", (w, w), (*DEEP, 0))
    shade.putalpha(vignette.point(lambda v: int((255 - v) * 0.40)))
    canvas = Image.alpha_composite(canvas, shade)

    # 内描边：在白底上也能看出图标边界。
    hair = Image.new("RGBA", (w, w), (0, 0, 0, 0))
    ImageDraw.Draw(hair).rounded_rectangle(
        (w * 0.012, w * 0.012, w * 0.988, w * 0.988),
        radius=int(w * 0.225),
        outline=(255, 255, 255, 70),
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
    veil = Image.new("RGBA", (w, h), (26, 10, 8, 150))
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
        fill=(232, 52, 42, 120),
    )
    panel = Image.alpha_composite(panel, glow.filter(ImageFilter.GaussianBlur(w * 0.04)))
    panel.alpha_composite(mark, ((w - mark.width) // 2, int(h * 0.10)))

    draw = ImageDraw.Draw(panel)
    title_font = load_font(True, int(w * 0.20))
    sub_font = load_font(False, int(w * 0.062))
    tiny_font = load_font(False, int(w * 0.050))

    title = "番茄端碗"
    tw = draw.textlength(title, font=title_font)
    draw.text(
        ((w - tw) / 2, int(h * 0.42)),
        title,
        font=title_font,
        fill=(255, 255, 255, 255),
    )

    latin = "FANQIE DUANWAN"
    lw = draw.textlength(latin, font=tiny_font)
    draw.text(
        ((w - lw) / 2, int(h * 0.55)),
        latin,
        font=tiny_font,
        fill=(255, 219, 196, 255),
    )

    for index, line in enumerate(("小说 · 短剧 · 漫剧", "漫画 · 听书")):
        lwid = draw.textlength(line, font=sub_font)
        draw.text(
            ((w - lwid) / 2, int(h * 0.62) + index * int(h * 0.055)),
            line,
            font=sub_font,
            fill=(255, 243, 233, 235),
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
    print("brand: 番茄端碗 / FanqieDuanwan")
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

#!/usr/bin/env python3
"""Draws the app icon (a disk-usage donut on a blue squircle) and writes the AppIcon asset set.

Usage: python3 scripts/generate_icon.py   (requires Pillow: pip install pillow)
"""
import json
import math
import pathlib

from PIL import Image, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
ASSETS = ROOT / "App" / "Resources" / "Assets.xcassets"
ICONSET = ASSETS / "AppIcon.appiconset"
SIZE = 1024


def draw_master() -> Image.Image:
    scale = 4  # supersample for smooth edges
    canvas = SIZE * scale
    image = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))

    # macOS icon grid: 824 px rounded square centred in 1024, with a soft shadow.
    inset = 100 * scale
    box = (inset, inset, canvas - inset, canvas - inset)
    radius = 185 * scale

    shadow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((box[0], box[1] + 14 * scale, box[2], box[3] + 14 * scale), radius, fill=(0, 0, 0, 90))
    shadow = shadow.filter(ImageFilter.GaussianBlur(18 * scale))
    image.alpha_composite(shadow)

    # Vertical gradient background.
    gradient = Image.new("RGBA", image.size)
    top, bottom = (40, 132, 255), (8, 70, 190)
    gdraw = ImageDraw.Draw(gradient)
    for y in range(canvas):
        t = y / canvas
        color = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,)
        gdraw.line([(0, y), (canvas, y)], fill=color)
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius, fill=255)
    image.paste(gradient, (0, 0), mask)

    # Donut chart: segments in light tints, one highlighted "critical" slice.
    draw = ImageDraw.Draw(image)
    cx = cy = canvas // 2
    outer = 300 * scale
    inner = 165 * scale
    segments = [(0.38, (255, 255, 255, 255)), (0.22, (190, 220, 255, 255)), (0.17, (140, 190, 255, 255)),
                (0.13, (255, 196, 120, 255)), (0.10, (255, 120, 100, 255))]
    start = -90.0
    gap = 2.5
    for fraction, color in segments:
        sweep = fraction * 360
        draw.pieslice((cx - outer, cy - outer, cx + outer, cy + outer), start + gap / 2, start + sweep - gap / 2, fill=color)
        start += sweep
    # Punch the hole with the gradient colour at the centre.
    centre_color = tuple(int(top[i] + (bottom[i] - top[i]) * 0.5) for i in range(3)) + (255,)
    draw.ellipse((cx - inner, cy - inner, cx + inner, cy + inner), fill=centre_color)

    # Small magnifier glyph in the middle.
    ring = 70 * scale
    stroke = 22 * scale
    mx, my = cx - 18 * scale, cy - 18 * scale
    draw.ellipse((mx - ring, my - ring, mx + ring, my + ring), outline=(255, 255, 255, 255), width=stroke)
    angle = math.radians(45)
    hx0 = mx + (ring - stroke / 4) * math.cos(angle)
    hy0 = my + (ring - stroke / 4) * math.sin(angle)
    draw.line((hx0, hy0, hx0 + 70 * scale, hy0 + 70 * scale), fill=(255, 255, 255, 255), width=stroke + 6 * scale)

    return image.resize((SIZE, SIZE), Image.LANCZOS)


def main() -> None:
    ICONSET.mkdir(parents=True, exist_ok=True)
    master = draw_master()
    images = []
    for points in [16, 32, 128, 256, 512]:
        for factor in (1, 2):
            pixels = points * factor
            name = f"icon_{points}x{points}{'@2x' if factor == 2 else ''}.png"
            master.resize((pixels, pixels), Image.LANCZOS).save(ICONSET / name)
            images.append({"idiom": "mac", "scale": f"{factor}x", "size": f"{points}x{points}", "filename": name})
    (ICONSET / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")

    accent = ASSETS / "AccentColor.colorset"
    accent.mkdir(parents=True, exist_ok=True)
    (accent / "Contents.json").write_text(json.dumps({
        "colors": [{"idiom": "universal", "color": {"color-space": "srgb", "components": {
            "red": "0.040", "green": "0.360", "blue": "0.830", "alpha": "1.000"}}}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n")
    (ASSETS / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    master.save(ROOT / "docs" / "icon.png")
    print(f"Wrote {len(images)} icon sizes to {ICONSET}")


if __name__ == "__main__":
    main()

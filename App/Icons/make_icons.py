"""Builds the iPhone's app icons, each with a light, a dark and a tinted image (iOS 26 makes the clear
one from the tinted), as asset catalog icon sets in Sources/Assets.xcassets.

- `AppIcon`: the main icon (the App Store's): black tick on white.
- `AppIcon-<Background>-<Tick>`: the classic tick in every pair of the palette's colours but equal
  ones, which Cuenta → Personalización → Icono offers as if it were painting it.
- `AppIcon-<Design>`: the other designs, plus `IconPreview-<Design>-<Appearance>` imagesets for the picker.

Flat images rather than Icon Composer documents: Xcode stores three 1024 px renders of every
`.icon`, about 4 MB each, which across ~90 icons made the app hundreds of megabytes.

Run from the repo root with Pillow installed: `python3 App/Icons/make_icons.py`.
"""
import json
import math
import shutil
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent
ASSETS = ROOT.parent / "Sources" / "Assets.xcassets"
TICK = ROOT.parent / "Mac" / "AppIcon.icon" / "Assets" / "tick.png"

# Same names and order as `IconColor` in Personalization.swift.
PALETTE = {
    "White": "#FFFFFF",
    "Black": "#000000",
    "Red": "#FF3B30",
    "Orange": "#FF9500",
    "Green": "#34C759",
    "Teal": "#30B0C7",
    "Blue": "#007AFF",
    "Indigo": "#5856D6",
    "Purple": "#AF52DE",
    "Pink": "#FF2D55",
}

APPEARANCES = ("light", "dark", "tinted")
K = 4  # Shapes are drawn at 4x and scaled down, for clean edges.
S = 1024


def rgb(hex_color):
    return tuple(int(hex_color[i:i + 2], 16) for i in (1, 3, 5))


def p(v):
    return round(v * K)


def canvas():
    return Image.new("L", (S * K, S * K), 0)


def shrink(big):
    return big.resize((S, S), Image.LANCZOS)


def gradient(top, bottom, box=(0, S)):
    """A vertical gradient over the whole icon, from `top` at box[0] to `bottom` at box[1]."""
    column = Image.new("RGB", (1, S))
    y0, y1 = box
    for y in range(S):
        t = min(max((y - y0) / max(y1 - y0, 1), 0), 1)
        column.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(rgb(top), rgb(bottom))))
    return column.resize((S, S))


def paint(base, alpha, top, bottom=None, box=(0, S)):
    fill = gradient(top, bottom, box) if bottom else Image.new("RGB", (S, S), rgb(top))
    base.paste(fill, (0, 0), alpha)


def plate(appearance):
    """The background: white (a touch greyer at the bottom, as Apple's white icons), the dark
    gradient in dark mode, black for the tinted image the system colours."""
    if appearance == "light":
        return gradient("#FFFFFF", "#F1F1F4")
    if appearance == "dark":
        return gradient("#2A2A2C", "#0E0E0F")
    return Image.new("RGB", (S, S), (0, 0, 0))


def soft_shadow(base, alpha, offset=10, blur=18, strength=0.18):
    shadow = ImageChops.offset(alpha.filter(ImageFilter.GaussianBlur(blur)), 0, offset).point(lambda v: round(v * strength))
    base.paste(Image.new("RGB", (S, S), (0, 0, 0)), (0, 0), shadow)


# MARK: - Classic

def classic(background, tick, appearance):
    """Dark mode only changes a white plate (to the dark one, with a white tick unless it's coloured):
    a colour or black plate already suits it, and is what the user picked."""
    alpha = Image.open(TICK).getchannel("A")
    if appearance == "tinted":
        base = plate("tinted")
        paint(base, alpha, "#FFFFFF")
        return base
    if appearance == "dark" and background == "White":
        base = plate("dark")
        paint(base, alpha, "#FFFFFF" if tick == "Black" else PALETTE[tick])
        return base
    base = Image.new("RGB", (S, S), rgb(PALETTE[background]))
    paint(base, alpha, PALETTE[tick])
    return base


# MARK: - Designs

def bezier(a, b, c, d, steps=500):
    for i in range(steps + 1):
        t = i / steps
        yield tuple((1 - t) ** 3 * a[k] + 3 * (1 - t) ** 2 * t * b[k] + 3 * (1 - t) * t ** 2 * c[k] + t ** 3 * d[k] for k in range(2))


def disc(cx, cy, r):
    shape = canvas()
    ImageDraw.Draw(shape).ellipse([p(cx - r), p(cy - r), p(cx + r), p(cy + r)], fill=255)
    return shrink(shape)


def tree():
    """«Evaluación»: what Grade is about, a subject's parts (each as big as its weight, in its grade's
    colour) joining into the final grade."""
    root_x, root_y, root_r = 512, 292, 126
    fork_y = 456  # where the trunk from the grade splits into the branches
    leaves = [  # x, y, radius (its weight), colours top/bottom, grey in the tinted image
        (250, 752, 92, "#FF7A70", "#EE2E24", "#6A6A6A"),
        (512, 742, 122, "#6FE38A", "#22B044", "#FFFFFF"),
        (774, 752, 104, "#FFD25A", "#FFA80A", "#ABABAB"),
    ]
    width = 40
    links = canvas()
    d = ImageDraw.Draw(links)
    trunk = [(root_x, root_y + (fork_y - root_y) * i / 100) for i in range(101)]
    for x, y, *_ in leaves:
        for lx, ly in trunk + list(bezier((root_x, fork_y), (root_x, 600), (x, 560), (x, y))):
            d.ellipse([p(lx - width / 2), p(ly - width / 2), p(lx + width / 2), p(ly + width / 2)], fill=255)
    links = shrink(links)
    root = disc(root_x, root_y, root_r)
    root_box = (root_y - root_r, root_y + root_r)

    images = {}
    for appearance in APPEARANCES:
        base = plate(appearance)
        paint(base, links, {"light": "#D8D8DE", "dark": "#48484A", "tinted": "#4A4A4A"}[appearance])
        for x, y, r, top, bottom, grey in leaves:
            leaf = disc(x, y, r)
            if appearance == "tinted":
                paint(base, leaf, grey)
                continue
            soft_shadow(base, leaf, offset=8, blur=14, strength=0.16 if appearance == "light" else 0.45)
            paint(base, leaf, top, bottom, box=(y - r, y + r))
        if appearance == "light":
            soft_shadow(base, root, offset=12, blur=20, strength=0.2)
            paint(base, root, "#3A3A3C", "#0B0B0C", box=root_box)
        elif appearance == "dark":
            soft_shadow(base, root, offset=12, blur=20, strength=0.5)
            paint(base, root, "#FFFFFF", "#DCDCE0", box=root_box)
        else:
            paint(base, root, "#FFFFFF")
        images[appearance] = base
    return images


def passing():
    """«Aprobado»: three grades as rounded bars, failed, just passed and well passed, in their colours."""
    bars = [  # x centre, top, colours top/bottom, grey in the tinted image (so clear keeps them apart)
        (290, 610, "#FF7A70", "#F2362B", "#5E5E5E"),
        (512, 400, "#FFD25A", "#FFAE0A", "#A8A8A8"),
        (734, 190, "#6FE38A", "#26B548", "#FFFFFF"),
    ]
    bottom, width = 846, 196
    images = {}
    for appearance in APPEARANCES:
        base = plate(appearance)
        for x, top, color_top, color_bottom, grey in bars:
            shape = canvas()
            ImageDraw.Draw(shape).rounded_rectangle([p(x - width / 2), p(top), p(x + width / 2), p(bottom)], radius=p(width / 2), fill=255)
            shape = shrink(shape)
            if appearance == "tinted":
                paint(base, shape, grey)
                continue
            soft_shadow(base, shape, strength=0.14 if appearance == "light" else 0.4)
            paint(base, shape, color_top, color_bottom, box=(top, bottom))
            # A soft light down the left of each bar, as on Apple's.
            shine = canvas()
            ImageDraw.Draw(shine).rounded_rectangle([p(x - width / 2 + 22), p(top + 22), p(x - 8), p(bottom - 22)], radius=p(width / 2), fill=255)
            shine = shrink(shine).filter(ImageFilter.GaussianBlur(16)).point(lambda v: round(v * 0.22))
            base.paste(Image.new("RGB", (S, S), (255, 255, 255)), (0, 0), ImageChops.multiply(shine, shape))
        images[appearance] = base
    return images


def record():
    """«Expediente»: subjects in a list, each with a ring that fills with its grades, in its grade's colour."""
    rows = [  # ring centre y, fraction filled, colours top/bottom, line length
        (272, 1.0, "#5EDC7A", "#24B046", 420),
        (512, 0.68, "#FFBE3D", "#FF9500", 330),
        (752, 0.36, "#FF6A60", "#EE2E24", 380),
    ]
    rx, r, stroke = 252, 98, 40
    images = {}
    for appearance in APPEARANCES:
        base = plate(appearance)
        track_color = {"light": "#E6E6EB", "dark": "#3A3A3C", "tinted": "#3A3A3A"}[appearance]
        line_color = {"light": "#D1D1D6", "dark": "#48484A", "tinted": "#6E6E6E"}[appearance]
        for y, fraction, top, bottom, length in rows:
            track = canvas()
            ImageDraw.Draw(track).ellipse([p(rx - r), p(y - r), p(rx + r), p(y + r)], outline=255, width=p(stroke))
            paint(base, shrink(track), track_color)

            arc = canvas()
            d = ImageDraw.Draw(arc)
            start, end = -90, -90 + 360 * fraction
            d.arc([p(rx - r), p(y - r), p(rx + r), p(y + r)], start, end, fill=255, width=p(stroke))
            if fraction < 1:
                # Round ends, centred on the stroke.
                for angle in (start, end):
                    a = math.radians(angle)
                    ex, ey = rx + (r - stroke / 2) * math.cos(a), y + (r - stroke / 2) * math.sin(a)
                    d.ellipse([p(ex - stroke / 2), p(ey - stroke / 2), p(ex + stroke / 2), p(ey + stroke / 2)], fill=255)
            arc = shrink(arc)
            if appearance == "tinted":
                paint(base, arc, "#FFFFFF")
            else:
                paint(base, arc, top, bottom, box=(y - r, y + r))

            line = canvas()
            ImageDraw.Draw(line).rounded_rectangle([p(412), p(y - 23), p(412 + length), p(y + 23)], radius=p(23), fill=255)
            paint(base, shrink(line), line_color)
        images[appearance] = base
    return images


DESIGNS = {"Tree": tree, "Passing": passing, "Record": record}


# MARK: - Output

def write_iconset(name, images):
    folder = ASSETS / f"{name}.appiconset"
    folder.mkdir(parents=True)
    entries = []
    for appearance in APPEARANCES:
        image = images[appearance]
        if appearance == "tinted":
            image = image.convert("L")
        image.save(folder / f"{appearance}.png", optimize=True)
        entry = {"filename": f"{appearance}.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}
        if appearance != "light":
            entry["appearances"] = [{"appearance": "luminosity", "value": appearance}]
        entries.append(entry)
    (folder / "Contents.json").write_text(json.dumps({"images": entries, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")


def write_imageset(folder, image, properties=None):
    """One image, whatever the app's appearance: the picker chooses which of the icon's to show."""
    folder.mkdir(parents=True)
    image.resize((240, 240), Image.LANCZOS).save(folder / "preview.png", optimize=True)
    contents = {"images": [{"filename": "preview.png", "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}
    if properties:
        contents["properties"] = properties
    (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def main():
    for old in ASSETS.glob("AppIcon*.appiconset"):
        shutil.rmtree(old)
    previews = ASSETS / "IconPreviews"
    if previews.exists():
        shutil.rmtree(previews)
    previews.mkdir()
    (previews / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")

    count = 0
    for background in PALETTE:
        for tick in PALETTE:
            if background == tick:
                continue
            name = "AppIcon" if (background, tick) == ("White", "Black") else f"AppIcon-{background}-{tick}"
            write_iconset(name, {a: classic(background, tick, a) for a in APPEARANCES})
            count += 1

    # The tick alone, which the picker paints in any colour on any plate.
    write_imageset(previews / "IconTick.imageset", Image.open(TICK), {"template-rendering-intent": "template"})

    for design, build in DESIGNS.items():
        images = build()
        write_iconset(f"AppIcon-{design}", images)
        for appearance in APPEARANCES:
            write_imageset(previews / f"IconPreview-{design}-{appearance.capitalize()}.imageset", images[appearance])
        count += 1
    print(f"{count} icons")


if __name__ == "__main__":
    main()

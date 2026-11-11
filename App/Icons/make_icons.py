"""Builds the iPhone's app icons.

- `Icons/AppIcon.icon` (the main icon, the App Store's: black tick on white) and
  `Icons/AppIcon-<Design>.icon` (the other designs): Icon Composer documents whose layers are glass,
  so iOS 26 lifts each piece off the icon, as in Apple's own. Xcode stores three 1024 px renders of
  each, ~5 MB apiece, so only these four are.
- `AppIcon-<Background>-<Tick>` icon sets in Sources/Assets.xcassets: the classic tick in every pair
  of the palette's colours but equal ones, as flat light/dark/tinted images (iOS 26 makes clear from
  tinted) with the relief painted in; Cuenta → Personalización → Icono offers them as if painting it.
- `IconPreview-<Design>-<Appearance>` imagesets for the picker.

Run from the repo root with Pillow and Xcode installed: `python3 App/Icons/make_icons.py`.
"""
import json
import math
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent
ASSETS = ROOT.parent / "Sources" / "Assets.xcassets"
TICK = ROOT.parent / "Mac" / "AppIcon.icon" / "Assets" / "tick.png"
ICTOOL = "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"

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

def lighten(hex_color, amount):
    return "#" + "".join(f"{round(c + (255 - c) * amount):02X}" for c in rgb(hex_color))


def relief(base, alpha, color, appearance):
    """Paints a shape as if it stood out of the icon, the way iOS 26's glass does with layered icons:
    a soft shadow under it, a little lighter at the top, and a bright rim along its upper edge."""
    soft_shadow(base, alpha, offset=12, blur=18, strength=0.28 if appearance == "light" else 0.55)
    paint(base, alpha, lighten(color, 0.18), color, box=(180, 840))
    edge = ImageChops.subtract(alpha, ImageChops.offset(alpha, 0, 7)).filter(ImageFilter.GaussianBlur(2))
    base.paste(Image.new("RGB", (S, S), (255, 255, 255)), (0, 0), edge.point(lambda v: round(v * 0.45)))


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
        relief(base, alpha, "#FFFFFF" if tick == "Black" else PALETTE[tick], appearance)
        return base
    base = Image.new("RGB", (S, S), rgb(PALETTE[background]))
    relief(base, alpha, PALETTE[tick], appearance)
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


def ring_arc(cx, cy, r, stroke, fraction):
    shape = canvas()
    d = ImageDraw.Draw(shape)
    start, end = -90, -90 + 360 * fraction
    d.arc([p(cx - r), p(cy - r), p(cx + r), p(cy + r)], start, end, fill=255, width=p(stroke))
    if fraction < 1:
        # Round ends, centred on the stroke.
        for angle in (start, end):
            a = math.radians(angle)
            ex, ey = cx + (r - stroke / 2) * math.cos(a), cy + (r - stroke / 2) * math.sin(a)
            d.ellipse([p(ex - stroke / 2), p(ey - stroke / 2), p(ex + stroke / 2), p(ey + stroke / 2)], fill=255)
    return shrink(shape)


def piece(name, mask, light, dark=None, tinted="#FFFFFF", glass=True):
    """One layer of a design: a white shape and its colour in light, dark and the tinted image."""
    return {"name": name, "mask": mask, "light": light, "dark": dark or light, "tinted": tinted, "glass": glass}


def tree():
    """«Evaluación»: what Grade is about, a subject's parts (each as big as its weight, in its grade's
    colour) joined by a trunk and branches into the final grade."""
    root_x, root_y, root_r = 512, 292, 126
    fork_y = 456  # where the trunk from the grade splits into the branches
    leaves = [  # x, y, radius (its weight), colour, grey in the tinted image
        (250, 752, 92, "#FF453A", "#6A6A6A"),
        (512, 742, 122, "#34C759", "#FFFFFF"),
        (774, 752, 104, "#FFC20A", "#ABABAB"),
    ]
    width = 40
    links = canvas()
    d = ImageDraw.Draw(links)
    trunk = [(root_x, root_y + (fork_y - root_y) * i / 100) for i in range(101)]
    for x, y, *_ in leaves:
        for lx, ly in trunk + list(bezier((root_x, fork_y), (root_x, 600), (x, 560), (x, y))):
            d.ellipse([p(lx - width / 2), p(ly - width / 2), p(lx + width / 2), p(ly + width / 2)], fill=255)
    layers = [piece("root", disc(root_x, root_y, root_r), "#1C1C1E", "#F2F2F7")]
    layers += [piece(f"part{i}", disc(x, y, r), color, tinted=grey) for i, (x, y, r, color, grey) in enumerate(leaves)]
    layers.append(piece("branches", shrink(links), "#D8D8DE", "#48484A", "#4A4A4A", glass=False))
    return layers


def passing():
    """«Aprobado»: three grades as rounded bars, failed, just passed and well passed, in their colours."""
    bars = [  # x centre, top, colour, grey in the tinted image (so clear keeps them apart)
        (290, 610, "#FF453A", "#5E5E5E"),
        (512, 400, "#FFC20A", "#A8A8A8"),
        (734, 190, "#34C759", "#FFFFFF"),
    ]
    bottom, width = 846, 196
    layers = []
    for i, (x, top, color, grey) in enumerate(bars):
        shape = canvas()
        ImageDraw.Draw(shape).rounded_rectangle([p(x - width / 2), p(top), p(x + width / 2), p(bottom)], radius=p(width / 2), fill=255)
        layers.append(piece(f"bar{i}", shrink(shape), color, tinted=grey))
    return list(reversed(layers))


def record():
    """«Expediente»: subjects in a list, each with a ring that fills with its grades, in its grade's colour."""
    rows = [  # ring centre y, fraction filled, colour, line length
        (272, 1.0, "#34C759", 420),
        (512, 0.68, "#FF9F0A", 330),
        (752, 0.36, "#FF453A", 380),
    ]
    rx, r, stroke = 252, 98, 40
    tracks, lines = canvas(), canvas()
    layers = []
    for i, (y, fraction, color, length) in enumerate(rows):
        ImageDraw.Draw(tracks).ellipse([p(rx - r), p(y - r), p(rx + r), p(y + r)], outline=255, width=p(stroke))
        ImageDraw.Draw(lines).rounded_rectangle([p(412), p(y - 23), p(412 + length), p(y + 23)], radius=p(23), fill=255)
        layers.append(piece(f"ring{i}", ring_arc(rx, y, r, stroke, fraction), color))
    layers.append(piece("lines", shrink(lines), "#D1D1D6", "#48484A", "#6E6E6E"))
    layers.append(piece("tracks", shrink(tracks), "#E6E6EB", "#3A3A3C", "#3A3A3A", glass=False))
    return layers


def primary():
    """The main icon as layers: the tick on white."""
    return [piece("tick", Image.open(TICK).getchannel("A"), "#000000", "#FFFFFF")]


DESIGNS = {"Tree": tree, "Passing": passing, "Record": record}


# MARK: - Output

def srgb(hex_color):
    r, g, b = (c / 255 for c in rgb(hex_color))
    return f"srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"


def write_icon(name, layers):
    """An Icon Composer document: each layer is glass, so iOS 26 lifts it off the icon (light, dark,
    clear and tinted alike). The system makes the dark plate itself."""
    folder = ROOT / f"{name}.icon"
    if folder.exists():
        shutil.rmtree(folder)
    (folder / "Assets").mkdir(parents=True)
    entries = []
    for layer in layers:
        image = Image.new("RGBA", (S, S), (255, 255, 255, 0))
        image.putalpha(layer["mask"])
        image.save(folder / "Assets" / f"{layer['name']}.png", optimize=True)
        entries.append({
            "image-name": f"{layer['name']}.png",
            "name": layer["name"],
            "glass": layer["glass"],
            "fill-specializations": [
                {"value": {"automatic-gradient": srgb(layer["light"])}},
                {"appearance": "dark", "value": {"automatic-gradient": srgb(layer["dark"])}},
                {"appearance": "tinted", "value": {"solid": srgb(layer["tinted"])}},
            ],
        })
    doc = {
        "fill": {"solid": srgb("#FFFFFF")},
        "groups": [{
            "layers": entries,
            "shadow": {"kind": "neutral", "opacity": 0.5},
            "translucency": {"enabled": True, "value": 0.15},
            "specular": True,
        }],
        "supported-platforms": {"squares": ["iOS"]},
    }
    (folder / "icon.json").write_text(json.dumps(doc, indent=1) + "\n")
    return folder


def render(icon, rendition):
    """Icon Composer's own picture of the icon, for the picker."""
    with tempfile.TemporaryDirectory() as folder:
        out = Path(folder) / "icon.png"
        subprocess.run([ICTOOL, str(icon), "--export-image", "--output-file", str(out), "--platform", "iOS",
                        "--rendition", rendition, "--width", "240", "--height", "240", "--scale", "1"],
                       check=True, capture_output=True)
        return Image.open(out).copy()


def flat_tinted(layers):
    """The tinted image as flat greys on black, which the picker uses for its tinted and clear looks."""
    base = plate("tinted")
    for layer in reversed(layers):
        paint(base, layer["mask"], layer["tinted"])
    return base


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
    for old in ROOT.glob("*.icon"):
        shutil.rmtree(old)
    previews = ASSETS / "IconPreviews"
    if previews.exists():
        shutil.rmtree(previews)
    previews.mkdir()
    (previews / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")

    # The colour pairs: flat images with the relief painted in.
    flat = 0
    for background in PALETTE:
        for tick in PALETTE:
            if background == tick or (background, tick) == ("White", "Black"):
                continue
            write_iconset(f"AppIcon-{background}-{tick}", {a: classic(background, tick, a) for a in APPEARANCES})
            flat += 1

    # The tick alone, which the picker paints in any colour on any plate.
    write_imageset(previews / "IconTick.imageset", Image.open(TICK), {"template-rendering-intent": "template"})

    # The main icon and the designs: real glass, at ~5 MB each in the app.
    write_icon("AppIcon", primary())
    for design, build in DESIGNS.items():
        layers = build()
        icon = write_icon(f"AppIcon-{design}", layers)
        write_imageset(previews / f"IconPreview-{design}-Light.imageset", render(icon, "Default"))
        write_imageset(previews / f"IconPreview-{design}-Dark.imageset", render(icon, "Dark"))
        write_imageset(previews / f"IconPreview-{design}-Tinted.imageset", flat_tinted(layers))
    print(f"{flat} flat icons, {1 + len(DESIGNS)} Icon Composer icons")


if __name__ == "__main__":
    main()

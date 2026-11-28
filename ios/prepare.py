#!/usr/bin/env python3
"""Gather Derp's shared assets into ios/Generated/ for the iOS build.

    python3 ios/prepare.py [--lists easylist.txt easyprivacy.txt ...]

Writes:
- Generated/derp/: Derp's own pages, the same ones Derp for Android shows
  (android/app/src/main/assets/derp/), with what android/prepare_assets.py
  makes for them: the dork drawing code, Doodle's look, the sticker editor,
  the critters, Seasons and What's new. The WebExtension parts (manifest.json,
  background.js, page.js) stay behind: on iOS the app does their jobs.
- Generated/Assets.xcassets: the app icon, the toolbar icons (desktop Derp's
  theme/icons/ and Derp for Android's own vector icons, as templates), and
  the art (Derp's and Doodle's logos, the critters, Seasons), all as SVG.
- Generated/blocklist.json: the ad blocker's rules for WebKit, from the
  filter lists given (see blocklist.py), or a few test rules without any.
"""
import argparse
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent
IOS = ROOT / "ios"
OUT = IOS / "Generated"
PAGES = ROOT / "android/app/src/main/assets/derp"
ANDROID_ICONS = ROOT / "android/app/src/main/res/drawable"
sys.path.insert(0, str(IOS))
import blocklist  # noqa: E402

# Pages say "this phone" here and there; Derp for iOS runs on iPads too.
WORDING = {
    "devices.html": [("Point this phone’s camera", "Point this device’s camera")],
}


def pages(out):
    """Derp's pages and their shared assets, in out/derp."""
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run([sys.executable, str(ROOT / "android/prepare_assets.py"), tmp], check=True)
        shutil.copytree(pathlib.Path(tmp) / "assets/derp", out, dirs_exist_ok=True)
    for page in PAGES.iterdir():
        if page.name in ("manifest.json", "background.js", "page.js") or page.is_dir():
            continue
        shutil.copyfile(page, out / page.name)
    for name, changes in WORDING.items():
        path = out / name
        text = path.read_text(encoding="utf-8")
        for old, new in changes:
            if old not in text:
                sys.exit(f"prepare: {old!r} isn't in {name} any more")
            text = text.replace(old, new)
        path.write_text(text, encoding="utf-8")


def vector_to_svg(path):
    """An Android vector drawable (paths only) as SVG."""
    android = "{http://schemas.android.com/apk/res/android}"
    root = ET.parse(path).getroot()
    width, height = root.get(android + "viewportWidth"), root.get(android + "viewportHeight")
    shapes = []
    for p in root.iter("path"):
        attrs = {
            "d": p.get(android + "pathData"),
            "fill": "#000" if p.get(android + "fillColor", "#00000000")[1:3] not in ("00",) else "none",
            "stroke": "#000" if p.get(android + "strokeColor") else "none",
            "stroke-width": p.get(android + "strokeWidth"),
            "stroke-linecap": p.get(android + "strokeLineCap"),
            "stroke-linejoin": p.get(android + "strokeLineJoin"),
        }
        shapes.append("<path " + " ".join(f'{k}="{v}"' for k, v in attrs.items() if v) + "/>")
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">{"".join(shapes)}</svg>'


def sized(svg, size=None):
    """The SVG with its size set (icons at 20pt, as on Android), or taken from its viewBox."""
    head = svg[: svg.index(">")]
    rest = svg[len(head):]
    head = re.sub(r'\s(width|height)="[^"]*"', "", head)
    if size is None:
        box = re.search(r'viewBox="\s*[-\d.]+\s+[-\d.]+\s+([\d.]+)\s+([\d.]+)"', head)
        w, h = (box.group(1), box.group(2)) if box else ("32", "32")
    else:
        w = h = str(size)
    return head.replace("<svg", f'<svg width="{w}" height="{h}"', 1) + rest


def imageset(catalog, name, svg, template):
    svg = sized(svg, 20 if template else None)
    folder = catalog / f"{name}.imageset"
    folder.mkdir(parents=True)
    (folder / f"{name}.svg").write_text(svg, encoding="utf-8")
    properties = {"preserves-vector-representation": True}
    if template:
        properties["template-rendering-intent"] = "template"
    contents = {
        "images": [{"filename": f"{name}.svg", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": properties,
    }
    (folder / "Contents.json").write_text(json.dumps(contents, indent=2), encoding="utf-8")


def catalog(out, derp):
    """The asset catalog: app icon, icons, art."""
    info = {"info": {"author": "xcode", "version": 1}}
    out.mkdir(parents=True)
    (out / "Contents.json").write_text(json.dumps(info, indent=2), encoding="utf-8")
    icon = out / "AppIcon.appiconset"
    icon.mkdir()
    shutil.copyfile(IOS / "AppIcon-1024.png", icon / "icon-1024.png")
    (icon / "Contents.json").write_text(json.dumps({
        "images": [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        **info,
    }, indent=2), encoding="utf-8")

    # Desktop Derp's toolbar icons; context-fill is Firefox's, so black (they're templates).
    for svg in sorted((ROOT / "theme/icons").glob("*.svg")):
        if svg.stem.startswith("loading"):
            continue
        text = svg.read_text(encoding="utf-8")
        text = re.sub(r'(fill|stroke)="context-fill"', r'\1="#000"', text)
        text = re.sub(r'\s(fill|stroke)-opacity="context-fill-opacity"', "", text)
        imageset(out, "icon-" + svg.stem, text, template=True)
    # Derp for Android's own icons, drawn the same way.
    for name in ("share", "mask", "search", "globe", "up", "down"):
        imageset(out, "icon-" + name, vector_to_svg(ANDROID_ICONS / f"ic_{name}.xml"), template=True)

    # Art, in its own colors.
    imageset(out, "art-logo", (ROOT / "brand/derp.svg").read_text(encoding="utf-8"), template=False)
    imageset(out, "art-logo-private", (ROOT / "brand/derp-private.svg").read_text(encoding="utf-8"), template=False)
    imageset(out, "art-doodle", (ROOT / "brand/doodle-icon.svg").read_text(encoding="utf-8"), template=False)
    critters = json.loads(re.search(r"const CRITTERS = (\{.*\});", (derp / "critters.js").read_text(encoding="utf-8"), re.S).group(1))
    from urllib.parse import unquote
    for name, uri in critters.items():
        imageset(out, "art-" + name, unquote(uri.split(",", 1)[1]), template=False)
    fun = (ROOT / "src/features/DerpFun.sys.mjs").read_text(encoding="utf-8")
    parcel = re.search(r"const PARCEL_URL = svg\(\s*`(.*?)`\s*\);", fun, re.S).group(1)
    imageset(out, "art-parcel", f'<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">{parcel}</svg>', template=False)
    for season in sorted((derp / "seasons").glob("*.svg")):
        imageset(out, "season-" + season.stem, season.read_text(encoding="utf-8"), template=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--lists", nargs="*", default=[], help="filter lists for the ad blocker")
    args = parser.parse_args()
    if OUT.exists():
        shutil.rmtree(OUT)
    derp = OUT / "derp"
    derp.mkdir(parents=True)
    pages(derp)
    catalog(OUT / "Assets.xcassets", derp)
    texts = [pathlib.Path(p).read_text(encoding="utf-8", errors="replace") for p in args.lists]
    rules = blocklist.convert(texts) if texts else blocklist.convert([blocklist.SAMPLE])
    (OUT / "blocklist.json").write_text(json.dumps(rules, separators=(",", ":")), encoding="utf-8")
    print(f"prepare: wrote {OUT} ({len(rules)} blocking rules)")


if __name__ == "__main__":
    main()

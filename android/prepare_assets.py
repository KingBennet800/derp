#!/usr/bin/env python3
"""Copy Derp's shared assets into the Android build (run by Gradle).

    python3 prepare_assets.py <out>

Writes <out>/assets/derp/: the dork drawing code (from DerpDork.sys.mjs, the
same code the browser and the website use), the logo, the wordmark, Doodle's
icon and Doodle's look for its results (src/features/doodle-look/), the
screenshot sticker editor (stickers.js, stickers.css) with Derp's critters
(critters.js: the duck, snail and ghost), and the Seasons gag's art
(seasons/*.svg, from DerpFun.sys.mjs), what's new after an update
(whatsnew.json); and <out>/res/drawable-nodpi/
derp_logo.png for the launcher icon.
"""
import importlib.util
import json
import pathlib
import re
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("site_build", ROOT / "site/build.py")
site = importlib.util.module_from_spec(spec)
spec.loader.exec_module(site)


def critter(module, name):
    """A critter's art from its module (`export const NAME = ... encodeURIComponent(`<svg>`)`)."""
    source = (ROOT / "src/features" / module).read_text(encoding="utf-8")
    match = re.search(rf"export const {name} =.*?encodeURIComponent\(`(<svg.*?</svg>)`\)", source, re.S)
    if not match:
        sys.exit(f"prepare_assets: no {name} in {module}")
    return site.svg_data_uri(match.group(1))


def seasons():
    """Seasons' art from DerpFun.sys.mjs: {name: svg}."""
    source = (ROOT / "src/features/DerpFun.sys.mjs").read_text(encoding="utf-8")
    block = re.search(r"export const SEASON_ART = \{(.*?)\n\};", source, re.S)
    art = dict(re.findall(r"(\w+): svg\(`(.*?)`\)", block.group(1) if block else "", re.S))
    if not art:
        sys.exit("prepare_assets: no SEASON_ART in DerpFun.sys.mjs")
    return {name: f'<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 32 32">{inner}</svg>' for name, inner in art.items()}


def main(out):
    out = pathlib.Path(out)
    assets = out / "assets/derp"
    drawables = out / "res/drawable-nodpi"
    assets.mkdir(parents=True, exist_ok=True)
    drawables.mkdir(parents=True, exist_ok=True)
    (assets / "dork-art.js").write_text(
        "// Generated from src/features/DerpDork.sys.mjs by prepare_assets.py.\n" + site.dork_art() + "\n",
        encoding="utf-8",
    )
    shutil.copyfile(ROOT / "brand/derp.svg", assets / "logo.svg")
    shutil.copyfile(ROOT / "brand/doodle-icon.svg", assets / "doodle.svg")
    # Doodle's look on its results pages: desktop Derp's content script and style.
    for name in ("doodle-page.js", "doodle-page.css"):
        shutil.copyfile(ROOT / "src/features/doodle-look" / name, assets / name)
    # The wordmark in desktop Derp's new tab colors, for light and dark.
    for scheme, color in (("light", "#1f2328"), ("dark", "#e8eaed")):
        (assets / f"wordmark-{scheme}.svg").write_text(
            site.wordmark().replace('fill="currentColor"', f'fill="{color}"'), encoding="utf-8"
        )
    # Screenshot with stickers: desktop Derp's editor, and the critters for it.
    for name in ("stickers.js", "stickers.css"):
        shutil.copyfile(ROOT / "src/features" / name, assets / name)
    critters = {
        "duck": critter("DerpDuck.sys.mjs", "DUCK_URL"),
        "snail": critter("DerpFun.sys.mjs", "SNAIL_URL"),
        "ghost": critter("DerpFun.sys.mjs", "GHOST_URL"),
    }
    (assets / "critters.js").write_text(
        "// Generated from src/features/ by prepare_assets.py.\nconst CRITTERS = " + json.dumps(critters, indent=2) + ";\n",
        encoding="utf-8",
    )
    # What's new after an update: the same list as desktop Derp's.
    shutil.copyfile(ROOT / "src/features/whatsnew.json", assets / "whatsnew.json")
    # Seasons: what falls, as files the app draws.
    (assets / "seasons").mkdir(exist_ok=True)
    for name, svg in seasons().items():
        (assets / "seasons" / f"{name}.svg").write_text(svg, encoding="utf-8")
    shutil.copyfile(ROOT / "brand/build/icons/derp-512.png", drawables / "derp_logo.png")
    print(f"prepare_assets: wrote {assets} and {drawables}")


if __name__ == "__main__":
    main(sys.argv[1])

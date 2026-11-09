#!/usr/bin/env python3
"""Copy Derp's shared assets into the Android build (run by Gradle).

    python3 prepare_assets.py <out>

Writes <out>/assets/derp/: the dork drawing code (from DerpDork.sys.mjs, the
same code the browser and the website use), the logo, the wordmark, Doodle's
icon and Doodle's look for its results (src/features/doodle-look/); and
<out>/res/drawable-nodpi/derp_logo.png for the launcher icon.
"""
import importlib.util
import pathlib
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("site_build", ROOT / "site/build.py")
site = importlib.util.module_from_spec(spec)
spec.loader.exec_module(site)


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
    shutil.copyfile(ROOT / "brand/build/icons/derp-512.png", drawables / "derp_logo.png")
    print(f"prepare_assets: wrote {assets} and {drawables}")


if __name__ == "__main__":
    main(sys.argv[1])

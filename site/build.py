#!/usr/bin/env python3
"""Build Derp's website into _site/index.html: one self-contained page.

    python3 site/build.py

It fills site/page.html with Derp's logo and wordmark, the version, real
screenshots from site/screenshots/, and the dork drawing code from
src/features/DerpDork.sys.mjs, so dorks on the site
look exactly like the ones in the browser. The Pages workflow runs this and
publishes _site/.
"""
import base64
import pathlib
import re
import sys
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "_site"
REPO = "KingBennet800/derp"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def dork_art():
    source = read("src/features/DerpDork.sys.mjs")
    match = re.search(r"^// dork-art: begin.*?\n(.*?)^// dork-art: end", source, re.S | re.M)
    if not match:
        sys.exit("build.py: no dork-art section in DerpDork.sys.mjs")
    return re.sub(r"^export ", "", match.group(1), flags=re.M).strip()


def svg_data_uri(svg):
    svg = re.sub(r">\s+<", "><", svg.strip())
    return "data:image/svg+xml," + urllib.parse.quote(svg, safe="")


def wordmark():
    svg = read("brand/build/derp-wordmark.svg")
    svg = re.sub(r"<style>.*?</style>", "", svg, flags=re.S)
    svg = re.sub(r'fill="context-fill[^"]*"', 'fill="currentColor"', svg)
    return svg.replace("<svg ", '<svg role="img" aria-label="derp" ', 1)


def screenshot(name):
    """A screenshot from site/screenshots/, embedded so the page stays one file."""
    path = ROOT / "site/screenshots" / f"{name}.webp"
    if not path.exists():
        sys.exit(f"build.py: no screenshot {path.relative_to(ROOT)}")
    return "data:image/webp;base64," + base64.b64encode(path.read_bytes()).decode()


def build():
    page = read("site/page.html")
    values = {
        "{{LOGO}}": svg_data_uri(read("brand/derp.svg")),
        "{{WORDMARK}}": wordmark(),
        "{{VERSION}}": read("VERSION").strip(),
        "{{REPO_URL}}": f"https://github.com/{REPO}",
        "{{REPO}}": REPO,
        "/*{{DORK_ART}}*/": dork_art(),
    }
    for key, value in values.items():
        if key not in page:
            sys.exit(f"build.py: {key} isn't used in page.html")
        page = page.replace(key, value)
    page = re.sub(r"\{\{SHOT:([a-z0-9-]+)\}\}", lambda m: screenshot(m.group(1)), page)
    left = re.findall(r"\{\{[A-Z_]+\}\}", page)
    if left:
        sys.exit(f"build.py: unfilled placeholders {sorted(set(left))}")
    OUT.mkdir(exist_ok=True)
    (OUT / "index.html").write_text(page, encoding="utf-8")
    (OUT / ".nojekyll").write_text("")
    print(f"built {OUT / 'index.html'} ({len(page.encode()) // 1024} KB)")


if __name__ == "__main__":
    build()

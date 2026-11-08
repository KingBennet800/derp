#!/usr/bin/env python3
"""Build Derp's website into _site/index.html: one self-contained page.

    python3 site/build.py

It fills site/page.html with Derp's logo and wordmark, the version, real
screenshots from site/screenshots/, the dork drawing code from
src/features/DerpDork.sys.mjs and the duck from src/features/DerpDuck.sys.mjs,
so dorks and the duck on the site look exactly like the ones in the browser.
It also builds Doodle's home page into _site/doodle/ (site/doodle.html). The
Pages workflow runs this and publishes _site/.
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


def duck():
    match = re.search(r"encodeURIComponent\(`(<svg.*?</svg>)`\)", read("src/features/DerpDuck.sys.mjs"), re.S)
    if not match:
        sys.exit("build.py: no duck in DerpDuck.sys.mjs")
    return svg_data_uri(match.group(1))


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
        "{{DUCK}}": duck(),
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


PAGES = "https://kingbennet800.github.io/derp"


def doodle_settings():
    """Doodle's search address and DuckDuckGo settings, light (from
    config/policies.json) and dark (from DerpFeatures.sys.mjs)."""
    import json

    engine = json.loads(read("config/policies.json"))["policies"]["SearchEngines"]["Add"][0]
    template = engine["URLTemplate"]
    light = dict(urllib.parse.parse_qsl(template.split("?", 1)[1]))
    del light["q"]
    match = re.search(r'DARK: "([^"]+)"', read("src/features/DerpFeatures.sys.mjs"))
    if not match:
        sys.exit("build.py: no Doodle DARK settings in DerpFeatures.sys.mjs")
    return engine, template, light, dict(urllib.parse.parse_qsl(match.group(1)))


def build_doodle():
    """Doodle's home page, _site/doodle/: the page, its icon, and an
    OpenSearch description so other browsers can add Doodle too."""
    import html
    import json

    engine, template, light, dark = doodle_settings()
    logo = re.sub(r'\s(width|height)="\d+"', "", read("brand/doodle.svg").strip(), count=2)
    logo = logo.replace("<svg ", '<svg role="img" aria-label="Doodle" ', 1)
    fields = "\n".join(f'    <input type="hidden" name="{k}" value="{html.escape(v)}">' for k, v in light.items())
    page = read("site/doodle.html")
    values = {
        "{{LOGO}}": logo,
        "{{ICON}}": svg_data_uri(read("brand/doodle-icon.svg")),
        "{{FIELDS}}": fields,
        "{{DARK}}": json.dumps(dark),
        "{{PAGES}}": PAGES,
    }
    for key, value in values.items():
        if key not in page:
            sys.exit(f"build.py: {key} isn't used in doodle.html")
        page = page.replace(key, value)
    out = OUT / "doodle"
    out.mkdir(parents=True, exist_ok=True)
    (out / "index.html").write_text(page, encoding="utf-8")
    (out / "doodle.svg").write_text(read("brand/doodle-icon.svg"), encoding="utf-8")
    opensearch = f"""<?xml version="1.0" encoding="UTF-8"?>
<OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/" xmlns:moz="http://www.mozilla.org/2006/browser/search/">
  <ShortName>Doodle</ShortName>
  <Description>{html.escape(engine["Description"])}</Description>
  <InputEncoding>UTF-8</InputEncoding>
  <Image width="32" height="32" type="image/svg+xml">{PAGES}/doodle/doodle.svg</Image>
  <Url type="text/html" method="get" template="{html.escape(template)}"/>
  <Url type="application/x-suggestions+json" method="get" template="{html.escape(engine["SuggestURLTemplate"])}"/>
  <moz:SearchForm>{PAGES}/doodle/</moz:SearchForm>
</OpenSearchDescription>
"""
    (out / "opensearch.xml").write_text(opensearch, encoding="utf-8")
    print(f"built {out / 'index.html'} ({len(page.encode()) // 1024} KB)")


if __name__ == "__main__":
    build()
    build_doodle()

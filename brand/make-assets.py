#!/usr/bin/env python3
"""Build Derp's derived brand assets into brand/build/.

- derp-wordmark.svg / about-wordmark.svg: "derp" set in Adwaita Sans ExtraBold,
  converted to outlines so it renders identically without the font installed.
- PNG icons at every size Firefox and the desktop need, rendered with librsvg
  (via GdkPixbuf) from derp.svg / derp-private.svg.
"""
import pathlib
import shutil
import subprocess

import gi
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf  # noqa: E402

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE / "build"
FONT = "/usr/share/fonts/adwaita-sans-fonts/AdwaitaSans-Regular.ttf"
WEIGHT = 800
TEXT = "derp"
TRACKING = -0.035  # em

ICON_SIZES = (16, 22, 24, 32, 48, 64, 128, 256, 512)


def wordmark_svg(fill_attr, color_scheme_style):
    font = TTFont(FONT)
    upem = font["head"].unitsPerEm
    glyphs = font.getGlyphSet(location={"wght": WEIGHT})
    cmap = font.getBestCmap()

    path_pen = SVGPathPen(glyphs)
    bounds_pen = BoundsPen(glyphs)
    x = 0.0
    for ch in TEXT:
        glyph = glyphs[cmap[ord(ch)]]
        flip = (1, 0, 0, -1, x, 0)
        glyph.draw(TransformPen(path_pen, flip))
        glyph.draw(TransformPen(bounds_pen, flip))
        x += glyph.width + TRACKING * upem

    xmin, ymin, xmax, ymax = bounds_pen.bounds
    pad = upem * 0.02
    view_box = f"{xmin - pad:.0f} {ymin - pad:.0f} {xmax - xmin + 2 * pad:.0f} {ymax - ymin + 2 * pad:.0f}"
    style = "<style>:root { color-scheme: light dark }</style>" if color_scheme_style else ""
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" fill="{fill_attr}" viewBox="{view_box}">'
        f'{style}<path d="{path_pen.getCommands()}"/></svg>\n'
    )


def render(svg, size):
    return GdkPixbuf.Pixbuf.new_from_file_at_size(str(HERE / svg), size, size)


def save(pixbuf, name):
    pixbuf.savev(str(OUT / name), "png", [], [])


def main():
    (OUT / "icons").mkdir(parents=True, exist_ok=True)

    (OUT / "derp-wordmark.svg").write_text(
        wordmark_svg("context-fill light-dark(#0d2420, #effaf7)", color_scheme_style=True)
    )
    (OUT / "about-wordmark.svg").write_text(wordmark_svg("context-fill", color_scheme_style=False))

    for size in ICON_SIZES:
        save(render("derp.svg", size), f"icons/derp-{size}.png")

    save(render("derp.svg", 192), "about-logo.png")
    save(render("derp.svg", 384), "about-logo@2x.png")
    save(render("derp-private.svg", 192), "about-logo-private.png")
    save(render("derp-private.svg", 384), "about-logo-private@2x.png")

    # about.png is 300x236 in Firefox's branding; keep the canvas, center the logo.
    canvas = GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, True, 8, 300, 236)
    canvas.fill(0x00000000)
    logo = render("derp.svg", 236)
    logo.composite(canvas, 32, 0, 236, 236, 32, 0, 1, 1, GdkPixbuf.InterpType.BILINEAR, 255)
    save(canvas, "about.png")

    make_splash_video()
    make_ico()
    make_icns()
    print(f"assets written to {OUT}")


def png_bytes(size):
    _, data = render("derp.svg", size).save_to_bufferv("png", [], [])
    return data


def make_ico():
    """derp.ico for Windows: PNG-compressed entries, 16 to 256 px."""
    import struct

    sizes = (16, 24, 32, 48, 64, 128, 256)
    images = [png_bytes(s) for s in sizes]
    offset = 6 + 16 * len(sizes)
    header = struct.pack("<HHH", 0, 1, len(sizes))
    entries = b""
    for size, data in zip(sizes, images):
        entries += struct.pack("<BBBBHHII", size % 256, size % 256, 0, 0, 1, 32, len(data), offset)
        offset += len(data)
    (OUT / "derp.ico").write_bytes(header + entries + b"".join(images))


def make_icns():
    """derp.icns for the macOS app bundle: PNG entries, 16 to 1024 px."""
    import struct

    kinds = [("icp4", 16), ("icp5", 32), ("icp6", 64), ("ic07", 128), ("ic08", 256), ("ic09", 512),
             ("ic10", 1024), ("ic11", 32), ("ic12", 64), ("ic13", 256), ("ic14", 512)]
    body = b"".join(
        kind.encode() + struct.pack(">I", len(data) + 8) + data
        for kind, data in ((k, png_bytes(s)) for k, s in kinds)
    )
    (OUT / "derp.icns").write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)


def make_splash_video():
    """Derp's stand-in for Firefox's splash-screen.webm: the orb springs in
    (ease-out-back) on Derp's dark background, then bobs."""
    if not shutil.which("ffmpeg"):
        print("ffmpeg not found; skipping derp-splash.webm")
        return
    p = "min(t/0.7,1)"
    scale = f"1+2.70158*pow({p}-1,3)+1.70158*pow({p}-1,2)"
    graph = (
        "color=c=0x0c1416:s=1920x748:r=30:d=4.16[bg];"
        f"[1:v]format=rgba,scale=w='max(2,trunc(440*({scale})))':h=-1:eval=frame[logo];"
        "[bg][logo]overlay=x='(W-w)/2':y='(H-h)/2-12*sin(2*PI*max(t-0.7,0)/2.6)':eval=frame:shortest=1,format=yuv420p"
    )
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "nullsrc=s=16x16:d=4.16",
         "-loop", "1", "-i", str(OUT / "icons/derp-512.png"),
         "-filter_complex", graph, "-t", "4.16", "-c:v", "libvpx-vp9", "-b:v", "0", "-crf", "36",
         "-deadline", "good", "-cpu-used", "5", "-row-mt", "1", "-an", str(OUT / "derp-splash.webm")],
        check=True,
    )


if __name__ == "__main__":
    main()

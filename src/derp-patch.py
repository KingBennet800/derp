#!/usr/bin/env python3
"""Apply Derp's branding and defaults to a Firefox engine (Linux, macOS, Windows).

    derp-patch.py           brand the engine in $DERP_ENGINE (default: the
                            platform's install location) if needed
    derp-patch.py --launch  what the Linux launcher runs before starting Derp:
                            if Derp isn't already running, swap in an update
                            that derp-update staged, then brand if needed

Pure standard-library Python, so it runs anywhere Python 3.9+ does. Cheap when
nothing changed: it compares a stamp of the engine's resource archives and of
Derp's assets (sizes and mtimes) against the last run.

Exit status: 0 = nothing to do, 3 = patched, 10 = Derp is running (--launch),
anything else = error. After patching it drops Firefox's .purgecaches marker
so the next start rebuilds its caches from the new files.
"""
import json
import os
import pathlib
import re
import shutil
import struct
import sys
import zlib

PLATFORM = "macos" if sys.platform == "darwin" else "windows" if os.name == "nt" else "linux"
_DEFAULT_HOME = {
    "linux": pathlib.Path.home() / ".local/share/derp",
    "macos": pathlib.Path.home() / "Library/Application Support/Derp",
    "windows": pathlib.Path(os.environ.get("LOCALAPPDATA", pathlib.Path.home())) / "Derp",
}[PLATFORM]
HOME = pathlib.Path(os.environ.get("DERP_HOME", _DEFAULT_HOME))
# The engine directory is the one holding omni.ja: the install folder on Linux
# and Windows, Derp.app/Contents/Resources on macOS.
_DEFAULT_ENGINE = (
    pathlib.Path.home() / "Applications/Derp.app/Contents/Resources" if PLATFORM == "macos" else HOME / "firefox"
)
ENGINE = pathlib.Path(os.environ.get("DERP_ENGINE", _DEFAULT_ENGINE))
STAGED = HOME / "firefox.next"
BRAND = HOME / "brand"
CONFIG = HOME / "config"
STAMP = ENGINE / ".derp-stamp"
PROCESS_LINK = ENGINE / "derp"  # Linux: exec'ing through this names the main process "derp"
PATCHED = 3
RUNNING = 10

BRANDING = "chrome/browser/content/branding/"
SPLASH = "chrome/browser/content/activity-stream/data/content/assets/"
# Whole files swapped for Derp's, per archive.
FILE_REPLACEMENTS = {
    "browser/omni.ja": {
        "localization/en-US/branding/brand.ftl": "brand.ftl",
        "chrome/en-US/locale/branding/brand.properties": "brand.properties",
        BRANDING + "aboutDialog.css": "aboutDialog.css",
        BRANDING + "about-logo.svg": "derp.svg",
        BRANDING + "about-logo.png": "build/about-logo.png",
        BRANDING + "about-logo@2x.png": "build/about-logo@2x.png",
        BRANDING + "about-logo-private.png": "build/about-logo-private.png",
        BRANDING + "about-logo-private@2x.png": "build/about-logo-private@2x.png",
        BRANDING + "about.png": "build/about.png",
        BRANDING + "about-wordmark.svg": "build/about-wordmark.svg",
        BRANDING + "firefox-wordmark.svg": "build/derp-wordmark.svg",
        **{f"{BRANDING}icon{s}.png": f"build/icons/derp-{s}.png" for s in (16, 32, 48, 64, 128)},
        SPLASH + "splash-logo.svg": "derp-splash.svg",
        SPLASH + "splash-screen.webm": "build/derp-splash.webm",
    },
    "omni.ja": {},
}
# Window icons: PNGs on Linux; on Windows Firefox looks for <type>.ico here.
WINDOW_ICONS = {
    "linux": {f"default{s}.png": f"build/icons/derp-{s}.png" for s in (16, 32, 48, 64, 128)},
    "windows": {"main-window.ico": "build/derp.ico", "default.ico": "build/derp.ico"},
    "macos": {},
}[PLATFORM]
CONFIG_FILES = {
    "browser/defaults/preferences/derp.js": "derp-prefs.js",
    "distribution/policies.json": "policies.json",
    # Derp is a modified build, so it shouldn't identify as Mozilla's official one.
    "distribution/distribution.ini": "distribution.ini",
    # Loads Derp's browser features (web apps, Memory Saver, Settings section).
    "defaults/pref/autoconfig.js": "autoconfig.js",
    "derp.cfg": "derp.cfg",
}

# Firefox's updater is off (derp-update does the job), so say what really happens.
PHRASES = {
    "Updates disabled by your organization": "Derp updates itself in the background",
    "Your browser is being managed by your organization.": "Derp sets some of its defaults with policies.",
    # Web apps get a desktop entry and dock icon; GNOME has no taskbar.
    "Add tab to taskbar": "Install as app",
    "Remove tab from taskbar": "Uninstall app",
}

# Visible "Firefox" text becomes "Derp". Mozilla's online services and its
# mobile apps aren't Derp, so those get Mozilla's name instead.
TEXT_RULES = [
    (re.compile(r"\bMozilla Firefox\b"), "Derp"),
    (re.compile(r"\bFirefox (?=(Relay|Monitor|Send|Profiler|Color|Data|Telemetry|Nightly|Lockwise)\b)"), "Mozilla "),
    (re.compile(r"\bFirefox Alpenglow\b"), "Alpenglow"),
    (re.compile(r"\bFirefox(?= for\b| on the Android\b)"), "Mozilla’s browser"),
    (re.compile(r"\bFirefox(?= (only )?recommends\b)"), "Mozilla"),
    (re.compile(r"\bFirefox\b"), "Derp"),
]
LOCALIZED_TEXT = re.compile(r"^(localization/en-US/.+\.ftl|chrome/en-US/locale/.+\.properties)$")
# Messages, -terms and .attributes.
FTL_ENTRY = re.compile(r"^(\s*[-.]?[A-Za-z][\w-]*\s*=)(.*)$", re.S)
PROPERTIES_ENTRY = re.compile(r"^(\s*[^#!\s][^=:]*[=:])(.*)$", re.S)

# Firefox's logo and its fox mascot ("Kit") appear in dozens of illustrations;
# each is swapped for Derp art sized to the original's frame.
IMAGE_SUFFIXES = (".svg", ".png", ".gif")
FOX_IMAGE = re.compile(
    r"(^|[-_])(fox|foxy|kit|firefox|mascot|fenix)([-_.@]|$)"
    r"|^(focus-logo|desktop-to-mobile-banner|mr-rtamo-background-image|person-typing)\."
)
NOT_BRANDING = re.compile(r"(/firefox-view\.svg|/firefox-wallpaper[^/]*|/weather/[^/]*)$")
BLANK_IMAGES = {"chrome/browser/skin/classic/browser/privatebrowsing/fox-tail.svg"}
# Firefox logos under names the rules above can't spot (including the
# fox-eared private-browsing mask).
EXPLICIT_IMAGES = {
    "chrome/browser/skin/classic/browser/privatebrowsing/pbm-logo.svg": "private",
    "chrome/browser/skin/classic/browser/privatebrowsing/favicon.svg": "private",
    "chrome/toolkit/skin/classic/global/icons/indicator-private-browsing.svg": "private",
    "chrome/browser/skin/classic/browser/privateBrowsing.svg": "private-glyph",
    "chrome/toolkit/skin/classic/mozapps/extensions/line.svg": "derp",
}
CONTEXT_FILL = ' fill="context-fill" fill-opacity="context-fill-opacity"'
SVG_ROOT = re.compile(r"<svg\b[^>]*>", re.S)
SVG_BODY = re.compile(r"<svg\b[^>]*>(.*)</svg>", re.S)


def signature(path):
    st = path.stat()
    return [st.st_size, st.st_mtime_ns]


def brand_sources():
    sources = {BRAND / s for files in FILE_REPLACEMENTS.values() for s in files.values()}
    sources |= {BRAND / s for s in WINDOW_ICONS.values()}
    sources |= {BRAND / "build/icons" / f"derp-{s}.png" for s in (16, 22, 24, 32, 48, 64, 128, 256, 512)}
    sources |= {BRAND / f for f in ("derp-private.svg", "derp-glyph.svg", "derp-private-glyph.svg")}
    sources |= {CONFIG / s for s in CONFIG_FILES.values()}
    return sorted(p for p in sources if p.exists())


def assets_digest():
    """Sizes and mtimes of Derp's assets and of this script (install.sh rewrites them)."""
    import hashlib

    sources = [pathlib.Path(__file__).resolve(), *brand_sources()]
    return hashlib.sha256(json.dumps([[str(p), *signature(p)] for p in sources]).encode()).hexdigest()


def read_stamp():
    try:
        return json.loads(STAMP.read_text())
    except (OSError, ValueError):
        return {}


# ── Text ────────────────────────────────────────────────────────────────────


def rewrite_text(name, data):
    """Rebrand message values only — never the IDs, some of which contain "Firefox"."""
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return None
    def relevant(chunk):
        return "Firefox" in chunk or any(phrase in chunk for phrase in PHRASES)

    if not relevant(text):
        return None
    ftl = name.endswith(".ftl")
    out = []
    for line in text.splitlines(keepends=True):
        if not relevant(line) or line.lstrip().startswith(("#", "!")):
            out.append(line)
            continue
        m = (FTL_ENTRY if ftl else PROPERTIES_ENTRY).match(line)
        if m:
            key, value = m.groups()
        elif ftl and line[:1].isspace():  # multiline value continuation
            key, value = "", line
        else:
            out.append(line)
            continue
        for phrase, repl in PHRASES.items():
            value = value.replace(phrase, repl)
        for pattern, repl in TEXT_RULES:
            value = pattern.sub(repl, value)
        out.append(key + value)
    new = "".join(out)
    return new.encode("utf-8") if new != text else None


# ── Images ──────────────────────────────────────────────────────────────────


def number(value):
    m = re.match(r"\s*([\d.]+)", value or "")
    return float(m.group(1)) if m else None


def framed_svg(original, art, art_box, root_attrs="", fill=0.86):
    """`art` centered in the original's viewBox, keeping its width/height."""
    tag = SVG_ROOT.search(original)
    tag = tag.group(0) if tag else ""

    def attr(n):
        m = re.search(rf'\s{n}="([^"]*)"', tag)
        return m.group(1) if m else None

    width, height, view_box = attr("width"), attr("height"), attr("viewBox")
    if view_box:
        x, y, vw, vh = (float(v) for v in re.split(r"[\s,]+", view_box.strip()))
    elif number(width) and number(height):
        x, y, vw, vh = 0.0, 0.0, number(width), number(height)
    else:
        x, y, vw, vh = 0.0, 0.0, 512.0, 512.0
    size = min(vw, vh) * fill
    dims = "".join(f' {k}="{v}"' for k, v in (("width", width), ("height", height)) if v)
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg"{dims} viewBox="{x:g} {y:g} {vw:g} {vh:g}"{root_attrs}>'
        f'<svg x="{x + (vw - size) / 2:g}" y="{y + (vh - size) / 2:g}" width="{size:g}" height="{size:g}" '
        f'viewBox="0 0 {art_box} {art_box}">{art}</svg></svg>\n'
    ).encode("utf-8")


def image_size(data):
    """(width, height) of a PNG or GIF, or None."""
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return struct.unpack(">II", data[16:24])
    if data[:4] == b"GIF8":
        return struct.unpack("<HH", data[6:10])
    return None


def png_decode(data):
    """Decode an 8-bit RGBA, non-interlaced PNG (Derp's own icons) to rows."""
    pos, idat, width, height = 8, [], 0, 0
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos : pos + 8])
        chunk = data[pos + 8 : pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            width, height, depth, color, _, _, interlace = struct.unpack(">IIBBBBB", chunk)
            if (depth, color, interlace) != (8, 6, 0):
                raise ValueError("expected an 8-bit RGBA PNG")
        elif kind == b"IDAT":
            idat.append(chunk)
        elif kind == b"IEND":
            break
    raw, stride, rows, prev, i = zlib.decompress(b"".join(idat)), width * 4, [], bytearray(width * 4), 0
    for _ in range(height):
        kind, line = raw[i], bytearray(raw[i + 1 : i + 1 + stride])
        i += 1 + stride
        for x in range(stride):
            left = line[x - 4] if x >= 4 else 0
            up = prev[x]
            if kind == 1:
                line[x] = (line[x] + left) & 0xFF
            elif kind == 2:
                line[x] = (line[x] + up) & 0xFF
            elif kind == 3:
                line[x] = (line[x] + (left + up) // 2) & 0xFF
            elif kind == 4:
                corner = prev[x - 4] if x >= 4 else 0
                p = left + up - corner
                pa, pb, pc = abs(p - left), abs(p - up), abs(p - corner)
                line[x] = (line[x] + (left if pa <= pb and pa <= pc else up if pb <= pc else corner)) & 0xFF
        rows.append(line)
        prev = line
    return width, height, rows


def png_encode(width, height, rows):
    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))

    raw = b"".join(b"\x00" + bytes(row) for row in rows)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def raster(original):
    """Derp's logo centered on a transparent canvas the original's size, as a
    PNG (Firefox sniffs image types, so this also stands in for GIFs)."""
    size = image_size(original)
    if not size:
        return None
    width, height = size
    target = min(width, height) * 0.86
    sizes = [s for s in (16, 22, 24, 32, 48, 64, 128, 256, 512) if s <= target] or [16]
    lw, lh, logo = png_decode((BRAND / f"build/icons/derp-{sizes[-1]}.png").read_bytes())
    canvas = [bytearray(width * 4) for _ in range(height)]
    x0, y0 = max(0, (width - lw) // 2), max(0, (height - lh) // 2)
    for y in range(min(lh, height - y0)):
        span = min(lw, width - x0) * 4
        canvas[y0 + y][x0 * 4 : x0 * 4 + span] = logo[y][:span]
    return png_encode(width, height, canvas)


class Art:
    def __init__(self):
        body = lambda f: SVG_BODY.search((BRAND / f).read_text(encoding="utf-8")).group(1)  # noqa: E731
        self.derp = body("derp.svg")
        self.private = body("derp-private.svg")
        self.glyph = body("derp-glyph.svg")
        self.private_glyph = body("derp-private-glyph.svg")

    def image_for(self, name, data):
        if name in EXPLICIT_IMAGES:
            original = data.decode("utf-8", "replace")
            kind = EXPLICIT_IMAGES[name]
            if kind == "private-glyph":
                return framed_svg(original, self.private_glyph, 16, CONTEXT_FILL, fill=1.0)
            return framed_svg(original, self.private if kind == "private" else self.derp, 512, fill=1.0)
        base = name.rsplit("/", 1)[-1]
        if not name.endswith(IMAGE_SUFFIXES) or NOT_BRANDING.search(name) or not FOX_IMAGE.search(base):
            return None
        private = "/privatebrowsing/" in name
        if not name.endswith(".svg"):
            return raster(data)
        original = data.decode("utf-8", "replace")
        if name in BLANK_IMAGES:
            return framed_svg(original, "", 512)
        if "context-fill" in original:  # single-color icon that follows the theme
            return framed_svg(original, self.glyph, 16, CONTEXT_FILL, fill=1.0)
        return framed_svg(original, self.private if private else self.derp, 512)


# ── Archives ────────────────────────────────────────────────────────────────


def read_jar(path):
    """Yield (name, method, data) for each file in a Firefox omni.ja.

    Mozilla ships these as "optimized jars": a 4-byte read-ahead length, then
    the central directory, then the files. Python's zipfile expects the
    central directory just before the end record, so read it directly.
    """
    data = path.read_bytes()
    end = data.rfind(b"PK\x05\x06", max(0, len(data) - 65_557))
    if end < 0:
        raise ValueError(f"{path} is not a zip archive")
    count, cd_size, cd_offset = struct.unpack_from("<HII", data, end + 10)
    for start in (cd_offset, end - cd_size):
        if data[start : start + 4] == b"PK\x01\x02":
            break
    else:
        raise ValueError(f"{path}: central directory not found")
    pos = start
    for _ in range(count):
        method, = struct.unpack_from("<H", data, pos + 10)
        csize, = struct.unpack_from("<I", data, pos + 20)
        name_len, extra_len, comment_len = struct.unpack_from("<HHH", data, pos + 28)
        local, = struct.unpack_from("<I", data, pos + 42)
        name = data[pos + 46 : pos + 46 + name_len].decode("utf-8")
        pos += 46 + name_len + extra_len + comment_len
        if name.endswith("/"):
            continue
        local_name_len, local_extra_len = struct.unpack_from("<HH", data, local + 26)
        body_start = local + 30 + local_name_len + local_extra_len
        body = data[body_start : body_start + csize]
        yield name, method, body if method == 0 else zlib.decompress(body, -15)


def rebuild_jar(jar, pristine, brand_files, art):
    """Write a branded copy of `pristine` to `jar`, as a standard zip (which
    Firefox reads fine). Each entry keeps its original compression: Mozilla
    stores them uncompressed so startup can read them straight from the
    mapped file."""
    import zipfile

    counts = {"files": 0, "text": 0, "images": 0}
    tmp = jar.with_name(jar.name + ".derp-tmp")
    with zipfile.ZipFile(tmp, "w") as z:
        for name, method, data in read_jar(pristine):
            new = None
            if name in brand_files and (BRAND / brand_files[name]).exists():
                new, kind = (BRAND / brand_files[name]).read_bytes(), "files"
            elif LOCALIZED_TEXT.match(name):
                new, kind = rewrite_text(name, data), "text"
            else:
                new, kind = art.image_for(name, data), "images"
            if new is not None:
                counts[kind] += 1
            info = zipfile.ZipInfo(name, date_time=(2010, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_STORED if method == 0 else zipfile.ZIP_DEFLATED
            z.writestr(info, data if new is None else new)
    os.replace(tmp, jar)
    return counts


def rebrand_updater_strings():
    """The GTK window shown while an update installs."""
    ini = ENGINE / "updater.ini"
    if not ini.exists():
        return
    lines = []
    for line in ini.read_text(encoding="utf-8").splitlines(keepends=True):
        if "=" in line and not line.startswith(";"):
            key, value = line.split("=", 1)
            for pattern, repl in TEXT_RULES:
                value = pattern.sub(repl, value)
            line = f"{key}={value}"
        lines.append(line)
    ini.write_text("".join(lines), encoding="utf-8")


def derp_running():
    """A running engine locks its profile: a POSIX lock on .parentlock on
    Linux/macOS, an exclusively opened parent.lock on Windows."""
    profile = HOME / "profile"
    if PLATFORM == "windows":
        try:
            with open(profile / "parent.lock", "a"):
                return False
        except FileNotFoundError:
            return False
        except OSError:
            return True
    import fcntl

    try:
        lock = open(profile / ".parentlock", "rb")
    except FileNotFoundError:
        return False
    with lock:
        try:
            fcntl.lockf(lock, fcntl.LOCK_SH | fcntl.LOCK_NB)
        except OSError:
            return True
    return False


def apply_staged_update():
    """Swap in the already-branded engine derp-update left in firefox.next."""
    if not (STAGED / ".derp-ready").exists():
        return
    old = HOME / "firefox.old"
    shutil.rmtree(old, ignore_errors=True)
    os.rename(ENGINE, old)
    os.rename(STAGED, ENGINE)
    (ENGINE / ".derp-ready").unlink()
    if PLATFORM == "windows":
        shutil.rmtree(old, ignore_errors=True)
    else:
        import subprocess

        subprocess.Popen(["rm", "-rf", str(old)], start_new_session=True)


def main():
    if "--launch" in sys.argv[1:]:
        if derp_running():
            return RUNNING
        apply_staged_update()

    jars = {rel: ENGINE / rel for rel in FILE_REPLACEMENTS}
    if not all(j.exists() for j in jars.values()):
        sys.exit(f"derp-patch: no Firefox engine at {ENGINE}")

    stamp = read_stamp()
    digest = assets_digest()
    sigs = {rel: signature(j) for rel, j in jars.items()}
    # Stamps from before Derp branded both archives only recorded browser/omni.ja.
    known = stamp.get("jars") or {"browser/omni.ja": stamp.get("omni")}
    if known == sigs and stamp.get("assets") == digest:
        return 0

    art = Art()
    for rel, jar in jars.items():
        pristine = jar.with_name(jar.name + ".firefox")
        # A changed archive means a fresh Firefox (first install or an
        # update): keep it as the new pristine base before branding it.
        if known.get(rel) != sigs[rel] or not pristine.exists():
            shutil.copy2(jar, pristine)
        counts = rebuild_jar(jar, pristine, FILE_REPLACEMENTS[rel], art)
        print(f"derp-patch: {rel}: {counts['files']} files, {counts['text']} text, {counts['images']} images rebranded")

    icons = ENGINE / "browser/chrome/icons/default"
    for name, source in WINDOW_ICONS.items():
        if (BRAND / source).exists():
            icons.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(BRAND / source, icons / name)

    for target, source in CONFIG_FILES.items():
        target = ENGINE / target
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(CONFIG / source, target)

    rebrand_updater_strings()
    # Linux: "firefox" is a small stub that re-execs "firefox-bin", so link the real binary.
    if PLATFORM == "linux" and (not PROCESS_LINK.is_symlink() or os.readlink(PROCESS_LINK) != "firefox-bin"):
        PROCESS_LINK.unlink(missing_ok=True)
        PROCESS_LINK.symlink_to("firefox-bin")

    STAMP.write_text(json.dumps({"jars": {rel: signature(j) for rel, j in jars.items()}, "assets": digest}))
    # Firefox purges its startup caches when it finds this marker.
    for folder in (ENGINE, ENGINE / "browser"):
        (folder / ".purgecaches").touch()
    return PATCHED


if __name__ == "__main__":
    sys.exit(main())

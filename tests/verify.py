#!/usr/bin/env python3
"""Check an installed Derp on this machine (Linux, macOS or Windows); CI runs
this after the installer. Exits non-zero, listing every failure, if anything
is off.

    python3 tests/verify.py           check the install
    python3 tests/verify.py --launch  also start the engine headless once
"""
import importlib.util
import json
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("derp_patch", ROOT / "src/derp-patch.py")
patch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patch)

PLATFORM, HOME, ENGINE = patch.PLATFORM, patch.HOME, patch.ENGINE
APP = ENGINE.parent.parent if PLATFORM == "macos" else None
failures = []


def check(ok, what):
    print(("  ok  " if ok else "  FAIL") + f"  {what}")
    if not ok:
        failures.append(what)


def jar_file(jar, name):
    return next((data for entry, _, data in patch.read_jar(jar) if entry == name), None)


def main():
    print(f"Derp on {PLATFORM}: home {HOME}, engine {ENGINE}")
    version = (ROOT / "VERSION").read_text().strip()
    check((HOME / "VERSION").exists() and (HOME / "VERSION").read_text().strip() == version, f"Derp {version} installed")
    for folder in ("brand", "config", "features", "theme", "lib"):
        check((HOME / folder).is_dir(), f"{folder}/ copied")
    dork = ("DerpDork.sys.mjs", "dork.css", "locales/en-US/derp/dork.ftl")
    check(all((HOME / "features" / f).exists() for f in dork), "your dork installed")
    duck = ("DerpDuck.sys.mjs", "duck.css", "locales/en-US/derp/duck.ftl")
    check(all((HOME / "features" / f).exists() for f in duck), "duck mode installed")

    # Branding.
    omni = ENGINE / "browser/omni.ja"
    check(omni.exists(), "engine present")
    if omni.exists():
        brand = jar_file(omni, "localization/en-US/branding/brand.ftl") or b""
        check(b"-brand-short-name = Derp" in brand, "brand.ftl says Derp")
        menu = jar_file(omni, "localization/en-US/browser/appmenu.ftl") or b""
        values = [line.split(b"=", 1)[-1] for line in menu.splitlines() if not line.lstrip().startswith(b"#")]
        check(menu and not any(b"Firefox" in v for v in values), "menus don't say Firefox")
        check((ENGINE / "browser/omni.ja.firefox").exists(), "pristine archive kept for re-branding")
    for target in patch.CONFIG_FILES:
        check((ENGINE / target).exists(), f"{target} installed")
    try:
        policies = json.loads((ENGINE / "distribution/policies.json").read_text())["policies"]
    except (OSError, ValueError, KeyError):
        policies = {}
    check(policies.get("DisableAccounts") is True, "Mozilla accounts off")
    check(policies.get("IPProtectionAvailable") is False, "Mozilla VPN off")
    for name in patch.WINDOW_ICONS:
        check((ENGINE / "browser/chrome/icons/default" / name).exists(), f"window icon {name}")
    check((ENGINE / ".derp-stamp").exists(), "branding stamp written")

    # Platform integration.
    if PLATFORM == "linux":
        local = pathlib.Path.home() / ".local"
        check(os.access(local / "bin/derp", os.X_OK), "launcher installed")
        check((local / "share/applications/derp.desktop").exists(), "desktop entry installed")
        check((local / "share/icons/hicolor/256x256/apps/derp.png").exists(), "icons installed")
        check(os.readlink(ENGINE / "derp") == "firefox-bin", "process named derp")
    elif PLATFORM == "macos":
        plist = APP / "Contents/Info.plist"

        def plist_value(key, path=plist):
            out = subprocess.run(["plutil", "-extract", key, "raw", "-o", "-", str(path)], capture_output=True, text=True)
            return out.stdout.strip()

        check(plist_value("CFBundleName") == "Derp", "app named Derp")
        check(plist_value("CFBundleIdentifier") == "io.github.kingbennet800.derp", "own bundle id")
        check(plist_value("LSEnvironment.XRE_PROFILE_PATH") == str(HOME / "profile"), "opens Derp's own profile")
        check(plist_value("LSEnvironment.MOZ_CRASHREPORTER_DISABLE") == "1", "no crash reporter")
        check((APP / "Contents/Resources/derp.icns").exists(), "app icon")
        for strings in APP.glob("Contents/Resources/*.lproj/InfoPlist.strings"):
            check(plist_value("CFBundleName", strings) in ("", "Derp"), f"{strings.parent.name} name")
        sig = subprocess.run(["codesign", "--verify", "--deep", "--strict", str(APP)], capture_output=True, text=True)
        check(sig.returncode == 0, f"app signature valid {sig.stderr.strip()}")
    else:
        programs = pathlib.Path(os.environ["APPDATA"]) / "Microsoft/Windows/Start Menu/Programs"
        check((programs / "Derp.lnk").exists(), "Start menu shortcut")
        import winreg

        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Clients\StartMenuInternet\Derp\Capabilities") as key:
                check(winreg.QueryValueEx(key, "ApplicationName")[0] == "Derp", "registered as a browser")
        except OSError:
            check(False, "registered as a browser")

    if "--launch" in sys.argv[1:]:
        launch()

    if failures:
        print(f"\n{len(failures)} check(s) failed")
        return 1
    print("\nAll good")
    return 0


def launch():
    """Start the engine headless with a fresh profile and take a screenshot:
    proves it runs, that derp.cfg loads (it copies Derp's theme into the
    profile), and that Derp's features module starts without errors."""
    binary = {
        "linux": ENGINE / "firefox",
        "macos": APP / "Contents/MacOS/firefox" if APP else None,
        "windows": ENGINE / "firefox.exe",
    }[PLATFORM]
    with tempfile.TemporaryDirectory() as tmp:
        profile, shot = pathlib.Path(tmp) / "profile", pathlib.Path(tmp) / "shot.png"
        profile.mkdir()
        args = [str(binary), "--headless", "--no-remote", "--profile", str(profile), "--screenshot", str(shot), "about:blank"]
        if PLATFORM == "windows":
            args.insert(1, "--wait-for-browser")  # else the launcher process returns at once
        env = dict(os.environ, MOZ_HEADLESS="1")
        try:
            run = subprocess.run(args, env=env, capture_output=True, text=True, timeout=300)
            output = run.stdout + run.stderr
        except subprocess.TimeoutExpired as e:
            output = f"timed out\n{e.stdout or ''}{e.stderr or ''}"
        check(shot.exists() and shot.stat().st_size > 0, "engine starts and renders")
        check((profile / "chrome/derp-theme.css").exists(), "derp.cfg ran (theme synced into the profile)")
        check((profile / "chrome/custom.css").exists(), "custom.css created")
        check("Derp feature failed" not in output, "features started")
        if failures:
            print(output[-4000:])


if __name__ == "__main__":
    sys.exit(main())

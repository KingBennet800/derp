# Derp

A fast, fluid web browser built on Firefox, with its own name, logo, look and defaults.

Derp is the official Mozilla Firefox engine, downloaded straight from Mozilla
and verified, then rebranded and tuned on your machine. Derp never redistributes
Firefox: the installer fetches it from ftp.mozilla.org and checks it the
platform's way (Mozilla's GPG-signed checksums on Linux, Mozilla's Apple
signature on macOS, Mozilla's Authenticode signature on Windows). Everything
installs into your user account; nothing needs root or admin.

## Install

**Linux** (x86-64, ARM64) and **macOS** (Apple silicon, Intel):

```bash
curl -fsSL https://raw.githubusercontent.com/KingBennet800/derp/main/install.sh | bash
```

**Windows** 10/11 (x64, ARM64), in PowerShell:

```powershell
irm https://raw.githubusercontent.com/KingBennet800/derp/main/install.ps1 | iex
```

The one-liners download the latest [release](https://github.com/KingBennet800/derp/releases),
check it against the release's `SHA256SUMS`, and run its installer. You can also
download a release (or clone this repo) and run `install.sh` / `install.ps1` from it.
Run the installer again at any time to repair Derp.

Afterwards Derp is in your app grid (Linux), `~/Applications` (macOS) or the
Start menu (Windows). To make it your default browser, pick Derp in your system's
default-apps settings (`xdg-settings set default-web-browser derp.desktop` on Linux).

| | Linux | macOS | Windows |
| --- | --- | --- | --- |
| Derp's files | `~/.local/share/derp` | `~/Library/Application Support/Derp` | `%LOCALAPPDATA%\Derp` |
| The app | `~/.local/bin/derp` | `~/Applications/Derp.app` | Start menu → Derp |
| Your profile | `…/derp/profile` | `…/Derp/profile` | `…\Derp\profile` |
| Update log | `…/derp/update.log` | `…/Derp/update.log` | `…\Derp\update.log` |

Put your own UI tweaks in `profile/chrome/custom.css`; reinstalls keep them.

## Updates

Derp keeps itself current, both Derp and its engine:

- **Derp** (theme, features, installer): new releases from this repo are
  downloaded, checked against their `SHA256SUMS` and installed.
- **The engine**: when Mozilla ships a new Firefox, Derp downloads and verifies
  it, brands it next to the current one, and swaps it in the next time Derp
  isn't running, already branded.

Checks run at most every 6 hours: when you open Derp on Linux, from a login
agent on macOS, and from the "Derp Update" scheduled task on Windows. Firefox's
own updater is off because it would install stock, Firefox-branded files. To
check right away run `lib/derp-update` (Linux, macOS) or `lib\derp-update.ps1`
(Windows) from Derp's files folder.

## Uninstall

Linux:

```bash
bash ~/.local/share/derp/lib/uninstall.sh
```

macOS:

```bash
bash ~/Library/Application\ Support/Derp/lib/uninstall.sh
```

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File $env:LOCALAPPDATA\Derp\lib\uninstall.ps1
```

Your profile (bookmarks, history, logins) is kept; add `--purge` (`-Purge` on
Windows) to delete it too.

## What's different from stock Firefox

- **Look**: quiet and minimal. Tabs sit in the title bar; the selected tab is
  outlined by a hairline that runs on as the toolbar's top edge, with no
  separators and close buttons that appear on hover. The toolbar holds just
  sidebar, back, forward and reload, plus the extensions and ⋮ menus; the
  address bar has no pill until you hover or type, and its page buttons
  (bookmark, reader view, install) appear on hover. uBlock Origin lives in the
  extensions menu, and the bookmarks bar is off (Ctrl+Shift+B). Neutral grays, a blue accent, no translucency or blur.
  Follows GNOME light/dark; private windows are dark with a violet tint. Works
  with any theme: the selected tab takes the theme's toolbar color.
- **Derp touches**: loading tabs show a tiny bouncing Derp orb, and a
  lime-teal-blue shimmer runs under the toolbar while a page loads, and the
  highlighted address-bar suggestion gets a soft wash of the same gradient. Derp pops in on every new tab and wiggles if you hover it,
  and a bookmark star pops when you star a page. Buttons act out what they do:
  back and forward nudge, reload twists, + and × spin. Switching tabs and
  light/dark fades smoothly. All motion is off when the system asks for reduced
  motion.
- **Fluid**: spring-physics smooth scrolling with momentum, elastic overscroll and
  kinetic touchpad scrolling.
- **Fast**: GPU canvas, shader pre-caching, more parallel connections, a bigger
  DNS/TLS cache, less frequent session writes, and uBlock Origin pre-installed
  (removable).
- **Quiet**: no telemetry, studies, remote rollouts, sponsored tiles/suggestions
  or onboarding nags; no default bookmarks. The previous session is restored on start.
- **No Mozilla account or services**: no sign-in, Sync or Send Tab, and none of
  Mozilla's online services: no VPN, Relay email masks, Monitor breach alerts,
  online address-bar suggestions, weather, stories, Firefox Labs, "More from
  Mozilla", feedback or "report broken site" forms, and no crash reports sent to
  Mozilla. Settings opens on **Import and backup** (the local half of what was
  "Account and sync"). Still on, because they keep you safe or are what the
  engine is: security updates to certificate revocation lists and blocklists,
  Safe Browsing, add-on installs and updates from addons.mozilla.org, and
  downloads of on-device translation models.
- **No Firefox branding**: name, logos, the fox mascot (about 90 illustrations,
  including the private-browsing mask), the first-run splash animation, UI text,
  the updater window and the process name all say Derp. Where Mozilla's own
  services are named, they keep Mozilla's name. The engine still
  tells websites it is Firefox (user agent), so sites work normally.

## Features Firefox users keep asking for

Picked from Mozilla Connect's top-voted ideas and Reddit threads; toggles are in
**Settings → Derp**.

- **Web apps (Linux, Windows).** Open a site, click the install button in the
  address bar, and it becomes an app with its own window, app-grid or Start
  entry and taskbar/dock icon. Click the same button in the app's window to
  uninstall it. This is Firefox's own "Taskbar Tabs" feature, switched on and,
  on Linux, wired to Derp's launcher. (Not available on macOS yet.)
- **Memory Saver.** Tabs you haven't used for 30 minutes (adjustable) are
  unloaded and fade out; they reload when you click them. Pinned tabs, tabs
  playing sound, picture-in-picture, calls and pages with unsaved changes are
  left alone.
- **JPEG XL images.** Firefox's JXL decoder is built in but switched off; Derp
  turns it on.
- **AI blocked by default.** Derp starts with Firefox's AI enhancements blocked
  (chatbot, smart tab groups, link previews and so on). Translations still work
  and run on your device. Change it in Settings → AI controls.

Derp's features live in `src/features/` and load at startup through Firefox's
autoconfig (`config/derp.cfg`).

## This repo

- `install.sh`, `install.ps1`, `uninstall.sh`, `uninstall.ps1`: the installers.
- `src/`: `lib.sh` / `lib.ps1` (shared installer and updater code),
  `derp-update` / `derp-update.ps1` (the updaters), `derp-patch.py` (the
  branding patcher; its rules for which text and images get rebranded are at the
  top), the Linux launcher and desktop entry, and `features/` (web apps, Memory
  Saver, the Settings page).
- `brand/`: logo SVGs (regular, private, animated splash, single-color glyphs),
  brand strings and the About dialog style. `make-assets.py` regenerates the
  wordmark, PNGs, `.ico`, `.icns` and splash video in `brand/build/`.
- `theme/`: `derp-palette.css` (Derp's color scales), `derp-theme.css` (browser
  UI) and `derp-content.css` (built-in pages).
- `config/`: default prefs, enterprise policies, distribution identity, and
  `derp.cfg`, which loads the theme and features at startup.
- `tests/verify.py`: checks an installed Derp. CI installs, re-installs,
  verifies, launches, updates and uninstalls Derp on Linux, macOS and Windows
  (x64 and ARM) for every push.

Any setting in `config/derp-prefs.js` is only a default, so changes you make in
Settings or `about:config` persist. Derp's own "Make default" button is hidden on
purpose: the engine would register itself without Derp's profile.

### Releasing

Bump `VERSION`, commit, then tag and push it (`git tag v1.2.3 && git push --tags`).
The Release workflow publishes the archives and `SHA256SUMS`, then installs the
release with the one-liners on all three platforms to check it.

## License

Derp's own files are under the [Mozilla Public License 2.0](LICENSE). Firefox is a
trademark of the Mozilla Foundation; Derp is not affiliated with or endorsed by
Mozilla.

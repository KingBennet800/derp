# Derp

A fast, fluid web browser built on Firefox, with its own name, logo, look and defaults.

**Website: https://kingbennet800.github.io/derp/**

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

**Android** 8 or newer: download
[Derp for Android](https://github.com/KingBennet800/derp/releases/latest/download/derp-android-arm64.apk)
on your phone and open it (Android asks once to let your browser install apps).
That APK fits nearly every phone; there are also
[32-bit ARM](https://github.com/KingBennet800/derp/releases/latest/download/derp-android-arm.apk) and
[x86-64](https://github.com/KingBennet800/derp/releases/latest/download/derp-android-x86_64.apk) builds.
See [Derp for Android](#derp-for-android).

The one-liners download the latest [release](https://github.com/KingBennet800/derp/releases),
check it against the release's `SHA256SUMS`, and run its installer. When it's
done, Derp opens and has you make your dork first. You can also
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
- **Just for fun** (all off by default; Settings → Derp → Just for fun):
  - **Duck mode**: 1 in 10 times you press Enter in the address bar, a duck
    waddles along it and eats what you typed. Quack.
  - **Snail mode**: when a page takes more than 3 seconds, a snail crawls along
    the loading bar, and zooms off once the page is there.
  - **Peekaboo**: now and then (1 in 6 new tabs) your dork peeks up from the
    bottom of the window and waves.
  - **Party mode**: confetti when you bookmark a page.
  - **Sleepy tabs**: tabs Memory Saver has put to sleep snore (💤).
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
  Mozilla. Derp has its own account instead: your dork (below). Still on,
  because they keep you safe or are what the
  engine is: security updates to certificate revocation lists and blocklists,
  Safe Browsing, add-on installs and updates from addons.mozilla.org, and
  downloads of on-device translation models.
- **No Firefox branding**: name, logos, the fox mascot (about 90 illustrations,
  including the private-browsing mask), the first-run splash animation, UI text,
  the updater window and the process name all say Derp. Where Mozilla's own
  services are named, they keep Mozilla's name. The engine still
  tells websites it is Firefox (user agent), so sites work normally.

## Your dork

Derp's account is **your dork**: a cartoon you design, like a Memoji, plus a
name. It's your avatar at the top right of the tab strip. Click it to open the
editor, where you pick a face color, eyes, mouth, hair or a hat (and its color),
extras (taped nerd glasses, shades, headphones, freckles…) and a backdrop, or
hit **Shuffle**. **Save picture** saves it as a 1024px PNG. Settings' first page,
**You and your dork**, shows it too, along with importing data from other
browsers and backups.

Your dork is stored only on this device, in your profile's preferences
(`derp.dork`). There's no sign-in and no server. Every new profile starts with
a random dork of its own, and the first time Derp opens it welcomes you with
the editor so you can make it yours. It asks again each time Derp starts (and
a ring pulses around the avatar) until you press **That's me!**

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

## Derp for Android

Firefox for Android can't be rebranded on a phone the way desktop Derp
rebrands Firefox, so Derp for Android is its own small browser built on
**GeckoView**, the Firefox engine Mozilla publishes for apps.

Its engine stays current on its own: every Monday the **Engine update**
workflow checks Mozilla for a newer GeckoView. If there is one, it builds
Derp for Android with it, tests it on an emulator, and releases a patch
version of Derp (for example 1.4.0 → 1.4.1), which installed copies then
pick up. The version in use is `android/geckoview-version.txt`.

- Desktop Derp's look: its colors and icons, an address bar with no pill
  until you type, and the lime-teal-blue loading shimmer. Phones have one
  bottom toolbar (address bar, tabs, your dork, menu) and a tabs view;
  tablets have desktop's tab strip with folder tabs, and back, forward and
  reload in the toolbar. Private tabs, and light and dark mode. Just for fun is
  in the menu here too (Duck mode, Snail mode, Peekaboo and Party mode; all
  off by default).
- **Your dork** is here too, drawn by the same code as desktop Derp, and the
  first start has you make it.
- **Bookmarks, history and passwords**: ☆ in the menu bookmarks a page (your
  newest show on the new tab page); history keeps the pages you visit, except
  in private tabs; and Derp offers to save passwords when you sign in and fills
  them in next time. Passwords are encrypted with a key in Android's keystore,
  and showing or copying one asks for your screen lock. **Import data** brings
  bookmarks (.html) and passwords (.csv) exported from Chrome, Edge, Firefox,
  Safari or Derp on a computer. All of it stays on the device.
- Strict tracking protection (social trackers too), tracking parameters
  stripped from links, tracker cookies purged, no telemetry.
- Downloads, file uploads, page dialogs, and camera, microphone and location
  only when you allow them. Can be your default browser.
- **Updates itself**: whenever you open it (at most once an hour) it checks
  this repo's latest release, and if there's a newer Derp it offers it ("Later"
  waits a day), downloads the APK, checks it against the release's
  `SHA256SUMS`, and hands it to Android's installer.

Release APKs are signed with Derp's key. Android only installs an update
signed with the same key, so check a download with
`apksigner verify --print-certs derp-android-arm64.apk`; the certificate's
SHA-256 digest is
`45628fb2c0f49ea29c903db5ebe59f71a9acb59c68de0d722ba6b14ffb22759d`
(also in `android/ci/release-cert.sha256`).

The app's code is in `android/` (Kotlin, no other UI libraries). CI builds the
APKs and runs one on an emulator for every change; releases need the signing
key in the `ANDROID_KEYSTORE_B64` and `ANDROID_KEYSTORE_PASSWORD` repo
secrets.

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
- `site/`: the website. `build.py` fills `page.html` with the logo, version and
  the dork drawing code from `DerpDork.sys.mjs` into one self-contained
  `_site/index.html`; the Website workflow publishes it to GitHub Pages.
- `android/`: Derp for Android (see above). `prepare_assets.py` copies the
  logo and the dork code into the app at build time.
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

#!/usr/bin/env bash
# Install, update or repair Derp on Linux or macOS. Safe to re-run.
#
#   bash install.sh            install, or refresh Derp's files
#   bash install.sh --engine   also fetch the newest engine right now
#   bash install.sh --update   refresh Derp's files only (what the updater runs)
#   bash install.sh --ci       non-interactive install for CI (no login items)
#
# Or straight from GitHub:
#   curl -fsSL https://raw.githubusercontent.com/KingBennet800/derp/main/install.sh | bash
#
# Everything lives in your home folder; nothing needs root.
set -euo pipefail

SRC=
if [[ -f ${BASH_SOURCE[0]:-} ]]; then SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); fi

# Run from a pipe or as a lone file: fetch the latest release, check it
# against the release's checksums, and run its installer instead.
if [[ ! $SRC || ! -f $SRC/src/lib.sh ]]; then
  repo=KingBennet800/derp
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  curl -fsSL "https://api.github.com/repos/$repo/releases/latest" -o "$work/release.json"
  tarball=$(grep -o '"browser_download_url": *"[^"]*\.tar\.gz"' "$work/release.json" | head -n1 | cut -d'"' -f4)
  sums=$(grep -o '"browser_download_url": *"[^"]*/SHA256SUMS"' "$work/release.json" | head -n1 | cut -d'"' -f4)
  [[ $tarball && $sums ]] || { echo "derp: couldn't find the latest release of $repo" >&2; exit 1; }
  curl -fsSL "$tarball" -o "$work/${tarball##*/}"
  curl -fsSL "$sums" -o "$work/SHA256SUMS"
  (cd "$work" && grep " ${tarball##*/}\$" SHA256SUMS >expected &&
    if command -v sha256sum >/dev/null; then sha256sum -c --quiet expected; else shasum -a 256 -c expected >/dev/null; fi) ||
    { echo "derp: release download failed its checksum" >&2; exit 1; }
  tar -xzf "$work/${tarball##*/}" -C "$work"
  bash "$work"/derp-*/install.sh "$@"
  exit
fi

# shellcheck source=src/lib.sh
source "$SRC/src/lib.sh"

mode=install engine_now= ci=
for arg in "$@"; do
  case $arg in
    --engine) engine_now=1 ;;
    --update) mode=update ;;
    --ci) ci=1 ;;
    *) die "unknown option: $arg" ;;
  esac
done

say "Installing Derp $(cat "$SRC/VERSION") for $PLATFORM"
mkdir -p "$DERP_HOME"/{brand,config,lib,profile}
cp -Rp "$SRC"/brand/{derp.svg,derp-private.svg,derp-splash.svg,derp-glyph.svg,derp-private-glyph.svg,brand.ftl,brand.properties,aboutDialog.css,build} "$DERP_HOME/brand/"
cp -p "$SRC"/config/{derp-prefs.js,policies.json,distribution.ini,autoconfig.js,derp.cfg} "$DERP_HOME/config/"
rm -rf "$DERP_HOME/features" "$DERP_HOME/theme"
cp -Rp "$SRC/src/features" "$DERP_HOME/features"
cp -Rp "$SRC/theme" "$DERP_HOME/theme"
for f in derp-patch.py lib.sh derp-update; do
  # -p keeps mtimes, so an unchanged patcher doesn't trigger a re-brand.
  cmp -s "$SRC/src/$f" "$DERP_HOME/lib/$f" 2>/dev/null || cp -p "$SRC/src/$f" "$DERP_HOME/lib/$f"
done
install -m 755 "$SRC/uninstall.sh" "$DERP_HOME/lib/uninstall.sh"
chmod +x "$DERP_HOME/lib/derp-update"
cp "$SRC/VERSION" "$DERP_HOME/VERSION"
# This run fetches the newest engine itself, so the updater can wait its 6 hours.
[[ $mode == install ]] && touch "$DERP_HOME/.update-checked"
derp_python >/dev/null

if [[ $PLATFORM == linux ]]; then
  bin=$HOME/.local/bin apps=$HOME/.local/share/applications icons=$HOME/.local/share/icons/hicolor
  mkdir -p "$bin" "$apps"
  install -m 755 "$SRC/src/derp" "$bin/derp"
  sed "s|@BIN@|$bin|g" "$SRC/src/derp.desktop" >"$apps/derp.desktop"
  for size in 16 22 24 32 48 64 128 256 512; do
    install -Dm644 "$SRC/brand/build/icons/derp-$size.png" "$icons/${size}x$size/apps/derp.png"
  done
  install -Dm644 "$SRC/brand/derp.svg" "$icons/scalable/apps/derp.svg"
  if command -v gtk-update-icon-cache >/dev/null; then gtk-update-icon-cache -qtf "$icons" || true; fi
  if command -v update-desktop-database >/dev/null; then update-desktop-database -q "$apps" || true; fi
elif [[ ! $ci ]]; then
  # macOS: check for updates at login and every 6 hours.
  agent=$HOME/Library/LaunchAgents/$DERP_BUNDLE_ID.update.plist
  mkdir -p "$(dirname "$agent")"
  cat >"$agent" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$DERP_BUNDLE_ID.update</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$DERP_HOME/lib/derp-update</string><string>--background</string></array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>21600</integer>
  <key>ProcessType</key><string>Background</string>
</dict>
</plist>
EOF
  # The updater runs --update from this agent, so only a full install reloads it.
  if [[ $mode == install ]]; then
    launchctl bootout "gui/$(id -u)" "$agent" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$agent" 2>/dev/null || say "Couldn't load the update agent; it starts at next login"
  fi
fi

current=$(engine_version "$DERP_ENGINE")
if [[ -z $current || $engine_now ]]; then
  latest=$(latest_firefox_version || true)
  [[ $latest ]] || die "couldn't reach Mozilla to find the latest engine"
  if [[ -z $current ]] || version_newer "$latest" "$current" || [[ $engine_now ]]; then
    stage_engine "$latest"
    apply_staged
    [[ -e $DERP_STAGED ]] && say "Derp is running; the new engine is used once you quit it"
  fi
elif [[ $PLATFORM == linux ]]; then
  say "Branding the engine"
  rc=0
  "$(derp_python)" -I "$DERP_HOME/lib/derp-patch.py" --launch >/dev/null || rc=$?
  case $rc in
    0 | 3) ;;
    10) say "Derp is running — restart it to pick up the changes" ;;
    *) die "branding failed (exit $rc)" ;;
  esac
elif derp_running; then
  say "Derp is running; its new look is applied after you quit it"
else
  say "Branding Derp.app"
  brand_engine "$DERP_APP"
  register_app
fi

if [[ $mode == install ]]; then
  if [[ $PLATFORM == linux ]]; then
    say "Done. Open Derp from your app grid, or run: derp"
  else
    say "Done. Derp is in ~/Applications; open it from Launchpad or Spotlight."
  fi
fi

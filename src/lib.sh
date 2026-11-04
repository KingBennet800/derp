# Derp shell library for Linux and macOS, sourced by install.sh and derp-update.
# shellcheck shell=bash disable=SC2034 # its variables are used by the scripts sourcing it

DERP_REPO=KingBennet800/derp
FTP=https://ftp.mozilla.org/pub/firefox/releases
# Mozilla Software Releases <release@mozilla.com> (GPG) and Mozilla's Apple team.
MOZILLA_KEY_FPR=14F26682D0916CDD81E37B6D61B7B526D98F0353
MOZILLA_APPLE_TEAM=43AQ936H96
DERP_BUNDLE_ID=io.github.kingbennet800.derp

case $(uname -s) in
  Darwin) PLATFORM=macos ;;
  Linux) PLATFORM=linux ;;
  *) echo "Derp's install.sh supports Linux and macOS; on Windows use install.ps1." >&2 && exit 1 ;;
esac

if [[ $PLATFORM == macos ]]; then
  DERP_HOME=${DERP_HOME:-$HOME/Library/Application Support/Derp}
  DERP_APP=${DERP_APP:-$HOME/Applications/Derp.app}
  DERP_ENGINE=$DERP_APP/Contents/Resources
  DERP_STAGED=$DERP_HOME/Derp.app.next
else
  DERP_HOME=${DERP_HOME:-$HOME/.local/share/derp}
  DERP_ENGINE=$DERP_HOME/firefox
  DERP_STAGED=$DERP_HOME/firefox.next
fi
export DERP_HOME

say() { [[ ${DERP_QUIET:-} ]] || printf '\033[1;36m›\033[0m %s\n' "$*"; }
die() {
  echo "derp: $*" >&2
  exit 1
}

# Newer-than for dotted versions ("159.0.1" vs "159.0").
version_newer() { [[ $1 != "$2" && $(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1) == "$1" ]]; }
engine_version() {
  [[ -f $1/application.ini ]] || return 0
  sed -n 's/^Version=//p' "$1/application.ini" | head -n1
}
latest_firefox_version() {
  curl -fsS --max-time 30 https://product-details.mozilla.org/1.0/firefox_versions.json |
    sed -n 's/.*"LATEST_FIREFOX_VERSION": *"\([^"]*\)".*/\1/p'
}

derp_running() {
  if [[ $PLATFORM == macos ]]; then
    pgrep -f "$DERP_APP/Contents/MacOS/" >/dev/null 2>&1
  else
    [[ -e $DERP_HOME/profile/.parentlock ]] || return 1
    "$(derp_python)" -I -c '
import fcntl, sys
with open(sys.argv[1], "rb") as f:
    try:
        fcntl.lockf(f, fcntl.LOCK_SH | fcntl.LOCK_NB)
    except OSError:
        sys.exit(0)
sys.exit(1)' "$DERP_HOME/profile/.parentlock"
  fi
}

# A Python 3.9+ for the branding patcher. macOS only has one with Apple's
# command line tools; otherwise fetch a portable build into Derp's folder.
derp_python() {
  local py
  if [[ -x $DERP_HOME/python/bin/python3 ]]; then
    echo "$DERP_HOME/python/bin/python3"
    return
  fi
  if [[ $PLATFORM == linux || (-z ${DERP_FORCE_PORTABLE_PYTHON:-} && $(xcode-select -p 2>/dev/null) ) ]]; then
    for py in python3 /usr/bin/python3; do
      if command -v "$py" >/dev/null && "$py" -c 'import sys, zlib; sys.exit(sys.version_info < (3, 9))' 2>/dev/null; then
        command -v "$py"
        return
      fi
    done
  fi
  [[ $PLATFORM == macos ]] || die "Derp needs Python 3.9 or newer (python3)."
  install_portable_python >&2
  echo "$DERP_HOME/python/bin/python3"
}

install_portable_python() {
  # Straight from the release's files, not GitHub's API (rate-limited per IP).
  local base=https://github.com/astral-sh/python-build-standalone/releases/latest/download
  local arch work name
  arch=$(uname -m)
  [[ $arch == arm64 ]] && arch=aarch64
  say "Fetching a portable Python for Derp's patcher"
  work=$(mktemp -d)
  curl -fsSL "$base/SHA256SUMS" -o "$work/SHA256SUMS"
  name=$(grep -oE "cpython-3\.12\.[0-9]+\+[0-9]+-$arch-apple-darwin-install_only\.tar\.gz\$" "$work/SHA256SUMS" | head -n1)
  [[ $name ]] || die "couldn't find a portable Python build for $arch"
  curl -fsSL "$base/${name//+/%2B}" -o "$work/$name"
  grep " $name\$" "$work/SHA256SUMS" >"$work/expected" || die "no checksum published for $name"
  (cd "$work" && shasum -a 256 -c expected >/dev/null) || die "portable Python checksum mismatch"
  mkdir -p "$DERP_HOME"
  rm -rf "$DERP_HOME/python"
  tar -xzf "$work/$name" -C "$DERP_HOME"
  rm -rf "$work"
  [[ -x $DERP_HOME/python/bin/python3 ]] || die "portable Python didn't unpack as expected"
}

# Download Firefox $1 into $2 and verify it, leaving an unpacked engine:
# $2/engine (Linux) or $2/Derp.app (macOS, still Mozilla-signed).
fetch_firefox() {
  local version=$1 work=$2 arch file
  mkdir -p "$work"
  curl -fsS "$FTP/$version/SHA256SUMS" -o "$work/SHA256SUMS"
  if [[ $PLATFORM == linux ]]; then
    arch=$(uname -m)
    if [[ $arch == aarch64 || $arch == arm64 ]]; then arch=aarch64; else arch=x86_64; fi
    file=linux-$arch/en-US/firefox-$version.tar.xz
  else
    file="mac/en-US/Firefox $version.dmg"
  fi
  say "Downloading the Firefox $version engine from ftp.mozilla.org"
  if [[ ${DERP_QUIET:-} ]]; then
    curl -fsS "$FTP/$version/${file// /%20}" -o "$work/download"
  else
    curl -fL --progress-bar "$FTP/$version/${file// /%20}" -o "$work/download"
  fi

  say "Verifying Mozilla's checksum and signature"
  local expected
  expected=$(grep -F "  $file" "$work/SHA256SUMS" | grep -v '\.asc$' | head -n1 | cut -d' ' -f1)
  [[ $expected ]] || die "no checksum for $file in Mozilla's SHA256SUMS"
  if [[ $PLATFORM == macos ]]; then
    [[ $(shasum -a 256 "$work/download" | cut -d' ' -f1) == "$expected" ]] || die "checksum mismatch for $file"
  else
    [[ $(sha256sum "$work/download" | cut -d' ' -f1) == "$expected" ]] || die "checksum mismatch for $file"
    # Linux also checks that SHA256SUMS itself is signed by Mozilla's release key.
    curl -fsS "$FTP/$version/SHA256SUMS.asc" -o "$work/SHA256SUMS.asc"
    curl -fsS "$FTP/$version/KEY" -o "$work/KEY"
    mkdir -m 700 "$work/gnupg"
    GNUPGHOME="$work/gnupg" gpg -q --import "$work/KEY" 2>/dev/null
    GNUPGHOME="$work/gnupg" gpg --status-fd 1 --verify "$work/SHA256SUMS.asc" "$work/SHA256SUMS" 2>/dev/null |
      grep -q "^\[GNUPG:\] VALIDSIG .* $MOZILLA_KEY_FPR\$" || die "SHA256SUMS is not signed by Mozilla's release key"
  fi

  if [[ $PLATFORM == linux ]]; then
    mkdir "$work/engine"
    tar -xJf "$work/download" -C "$work/engine" --strip-components=1
  else
    local mount=$work/mount
    mkdir "$mount"
    hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$mount" "$work/download" >/dev/null
    ditto "$mount/Firefox.app" "$work/Derp.app"
    hdiutil detach "$mount" -quiet || hdiutil detach "$mount" -force -quiet
    # The app must carry Mozilla's own valid signature before Derp touches it.
    codesign --verify --deep --strict "$work/Derp.app" || die "Firefox.app's signature doesn't verify"
    [[ $(codesign -dv "$work/Derp.app" 2>&1 | sed -n 's/^TeamIdentifier=//p') == "$MOZILLA_APPLE_TEAM" ]] ||
      die "Firefox.app isn't signed by Mozilla"
  fi
  rm -f "$work/download"
}

# Brand an unpacked engine in place (Linux: a Firefox folder; macOS: an app).
brand_engine() {
  local target=$1 python
  python=$(derp_python)
  if [[ $PLATFORM == linux ]]; then
    DERP_ENGINE=$target "$python" -I "$DERP_HOME/lib/derp-patch.py" >/dev/null || [[ $? == 3 ]] || die "branding failed"
    return
  fi
  DERP_ENGINE=$target/Contents/Resources "$python" -I "$DERP_HOME/lib/derp-patch.py" >/dev/null || [[ $? == 3 ]] ||
    die "branding failed"
  local plist=$target/Contents/Info.plist strings
  plutil -replace CFBundleName -string Derp "$plist"
  plutil -replace CFBundleDisplayName -string Derp "$plist"
  plutil -replace CFBundleIdentifier -string "$DERP_BUNDLE_ID" "$plist"
  plutil -replace CFBundleIconFile -string derp.icns "$plist"
  plutil -remove CFBundleIconName "$plist" 2>/dev/null || true # else the asset catalog's fox wins
  # Derp's own profile, never Firefox's, however the app is opened.
  plutil -extract LSEnvironment xml1 -o /dev/null "$plist" 2>/dev/null || plutil -insert LSEnvironment -dictionary "$plist"
  plutil -replace LSEnvironment.XRE_PROFILE_PATH -string "$DERP_HOME/profile" "$plist"
  # No crash reporter window offering to send reports to Mozilla.
  plutil -replace LSEnvironment.MOZ_CRASHREPORTER_DISABLE -string 1 "$plist"
  # Localized names override Info.plist's (the menu bar would still say Firefox).
  for strings in "$target"/Contents/Resources/*.lproj/InfoPlist.strings; do
    [[ -f $strings ]] || continue
    plutil -convert xml1 "$strings"
    plutil -replace CFBundleName -string Derp "$strings"
    plutil -replace CFBundleDisplayName -string Derp "$strings"
  done
  cp "$DERP_HOME/brand/build/derp.icns" "$target/Contents/Resources/derp.icns"
  # Branding changes files Mozilla signed, so re-sign for this Mac (ad hoc).
  codesign --force --deep --sign - "$target" 2>/dev/null || die "couldn't sign Derp.app"
  xattr -cr "$target" 2>/dev/null || true
}

# Swap a staged engine into place, unless Derp is running (then it waits for
# the next update run, or on Linux for the launcher).
apply_staged() {
  [[ -e $DERP_STAGED/.derp-ready || -e $DERP_STAGED/Contents/.derp-ready ]] || return 0
  derp_running && return 0
  local live
  live=$([[ $PLATFORM == macos ]] && echo "$DERP_APP" || echo "$DERP_ENGINE")
  rm -rf "$live.old"
  [[ -e $live ]] && mv "$live" "$live.old"
  mkdir -p "$(dirname "$live")"
  mv "$DERP_STAGED" "$live"
  rm -f "$live/.derp-ready" "$live/Contents/.derp-ready"
  rm -rf "$live.old"
  [[ $PLATFORM == macos ]] && register_app
  return 0
}

# Tell Launch Services about Derp.app's name, icon and profile setting, and
# offer it as a default browser.
register_app() {
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$DERP_APP" 2>/dev/null || true
}

# Fetch, verify and brand Firefox $1, staging it for apply_staged.
stage_engine() {
  local version=$1 work
  work=$(mktemp -d "${TMPDIR:-/tmp}/derp-engine.XXXXXX")
  fetch_firefox "$version" "$work"
  local built
  built=$([[ $PLATFORM == macos ]] && echo "$work/Derp.app" || echo "$work/engine")
  say "Branding engine $version"
  brand_engine "$built"
  if [[ $PLATFORM == macos ]]; then
    touch "$built/Contents/.derp-ready"
  else
    touch "$built/.derp-ready"
  fi
  rm -rf "$DERP_STAGED"
  mkdir -p "$(dirname "$DERP_STAGED")"
  mv "$built" "$DERP_STAGED"
  rm -rf "$work"
}

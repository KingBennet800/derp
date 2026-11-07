#!/usr/bin/env bash
# Smoke-test Derp for Android on an emulator: install, start, check it shows
# the welcome dork editor, open a link, bookmark it, check history, save a
# password and get it offered back, switch to dark mode; screenshots and
# logcat go to $2. Fails if Derp crashes or isn't running.
set -euo pipefail
apk=$1 out=$2 pkg=io.github.kingbennet800.derp
mkdir -p "$out"

shot() { sleep "$2"; adb exec-out screencap -p >"$out/$1.png"; }
alive() { adb shell pidof "$pkg" >/dev/null || { echo "Derp isn't running after: $1"; adb logcat -d >"$out/logcat.txt"; exit 1; }; }
ui() { adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 && adb shell cat /sdcard/ui.xml; }
# Tap the view with this accessibility label (from a fresh UI dump).
tap() {
  local bounds
  bounds=$(ui | grep -o "content-desc=\"$1\"[^>]*bounds=\"\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]\"" | head -n1 | grep -o '\[[0-9,]*\]\[[0-9,]*\]')
  [[ $bounds ]] || { echo "Can't find '$1' to tap"; exit 1; }
  read -r x1 y1 x2 y2 <<<"$(tr '[],' '   ' <<<"$bounds")"
  adb shell input tap $(((x1 + x2) / 2)) $(((y1 + y2) / 2))
}
# Tap the view showing this text (a dialog's button).
tap_text() {
  local bounds
  bounds=$(ui | grep -o "text=\"$1\"[^>]*bounds=\"\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]\"" | head -n1 | grep -o '\[[0-9,]*\]\[[0-9,]*\]')
  [[ $bounds ]] || return 1
  read -r x1 y1 x2 y2 <<<"$(tr '[],' '   ' <<<"$bounds")"
  adb shell input tap $(((x1 + x2) / 2)) $(((y1 + y2) / 2))
}
# Fail unless Derp logged this (a pattern) since it started.
logged() {
  adb logcat -d >"$out/logcat.txt"
  grep -qE "$1" "$out/logcat.txt" || { echo "$2"; exit 1; }
}

adb shell settings put global window_animation_scale 0
adb shell settings put global transition_animation_scale 0
adb shell settings put global animator_duration_scale 0
adb shell cmd uimode night no
adb install -r "$apk"
adb logcat -c

# First start: Derp opens with the welcome dork editor.
adb shell am start -W -n "$pkg/.MainActivity"
shot 1-first-start 30
alive "first start"
ui >"$out/ui-first-start.xml"
for view in "Address bar" "Tabs" "Your dork" "Menu"; do
  grep -q "content-desc=\"$view\"" "$out/ui-first-start.xml" || { echo "No '$view' in the toolbar"; exit 1; }
done

# A link from another app opens in a new tab.
adb shell am start -W -a android.intent.action.VIEW -d https://example.com "$pkg"
shot 2-link 15
alive "opening a link"

# Bookmarks and history: star the page from the menu, then open both pages.
tap Menu
sleep 1
tap "Bookmark this page"
sleep 2
tap Menu
sleep 1
tap Bookmarks
shot 2b-bookmarks 6
alive "the bookmarks page"
logged "bookmarks.list -> 1" "The bookmark isn't on the Bookmarks page"
tap Menu
sleep 1
tap History
shot 2c-history 6
alive "the history page"
logged "history.list -> [1-9]" "Nothing in the history"

# Passwords: sign in on a test page by typing; Derp offers to save the
# password, and offers it back when the page comes again.
site="$out/site"
mkdir -p "$site"
cat >"$site/index.html" <<'HTML'
<!doctype html>
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Sign in</title>
<style>body{margin:0}input,button{display:block;box-sizing:border-box;width:100%;height:28vh;font-size:6vh}</style>
<form action="done.html" method="get">
  <input name="user" autocomplete="username" placeholder="Username">
  <input name="pass" type="password" autocomplete="current-password" placeholder="Password">
  <button>Sign in</button>
</form>
HTML
echo '<!doctype html><title>Signed in</title><p>Signed in.' >"$site/done.html"
python3 -m http.server 8123 --bind 127.0.0.1 --directory "$site" >/dev/null 2>&1 &
server=$!
trap 'kill $server 2>/dev/null || true' EXIT
adb reverse tcp:8123 tcp:8123
adb shell am start -W -a android.intent.action.VIEW -d http://localhost:8123/ "$pkg"
sleep 10
read -r w h < <(adb shell wm size | grep -o '[0-9]*x[0-9]*' | tail -n1 | tr x ' ')
# The username field fills the top quarter of the page.
adb shell input tap $((w / 2)) $((h * 17 / 100))
sleep 1
adb shell input text tester
# (The keyboard is up now and the page smaller, so Tab to the password field.)
adb shell input keyevent KEYCODE_TAB
adb shell input text hunter2hunter2
adb shell input keyevent KEYCODE_ENTER
shot 2d-save-password 6
tap_text Save || { ui >"$out/ui-no-save.xml"; echo "Derp didn't offer to save the password"; exit 1; }
sleep 2
alive "saving a password"
logged "Passwords: 1 saved" "The password wasn't saved"
adb shell am start -W -a android.intent.action.VIEW -d http://localhost:8123/ "$pkg"
shot 2e-password-offered 8
logged "Passwords for a site: 1" "The saved password wasn't offered to the sign-in page"

# The tabs view and the menu.
tap Tabs
shot 3-tabs 3
adb shell input keyevent KEYCODE_BACK
sleep 2
tap Menu
shot 4-menu 3
adb shell input keyevent KEYCODE_BACK
sleep 2
alive "tabs view and menu"

# Typing in the address bar searches.
tap "Address bar"
sleep 1
adb shell input text "derp%sbrowser"
adb shell input keyevent KEYCODE_ENTER
shot 5-search 12
alive "searching"

# Dark mode.
adb shell cmd uimode night yes
shot 6-dark 12
alive "switching to dark mode"
adb shell cmd uimode night no

adb logcat -d >"$out/logcat.txt"
if grep -E "FATAL EXCEPTION|E AndroidRuntime" "$out/logcat.txt" | grep -q .; then
  grep -A 20 "FATAL EXCEPTION" "$out/logcat.txt" | head -60
  exit 1
fi
echo "Derp ran: first start, a link, bookmarks, history, a saved password, dark mode."

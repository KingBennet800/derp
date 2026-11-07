#!/usr/bin/env bash
# Smoke-test Derp for Android on an emulator: install, start, check it shows
# the welcome dork editor, open a link, switch to dark mode; screenshots and
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
echo "Derp ran: first start, a link, dark mode."

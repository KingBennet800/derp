#!/usr/bin/env bash
# Screenshots of Derp for Android for the website: the welcome dork editor,
# a new tab, Derp's website, the tabs view (phones; tablets show a tab strip),
# then the same in dark mode.
# Usage: showcase.sh <apk> <out dir> <name prefix>
set -euo pipefail
apk=$1 out=$2 name=$3 pkg=io.github.kingbennet800.derp
mkdir -p "$out"

shot() {
  sleep "$2"
  calm
  adb exec-out screencap -p >"$out/$name-$1.png"
}
# Close stray system dialogs (a slow emulator's "isn't responding" ones).
calm() {
  adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS >/dev/null 2>&1 || true
  if ui | grep -q "isn't responding"; then
    tap Wait || true
    sleep 2
  fi
}
ui() { adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 && adb shell cat /sdcard/ui.xml; }
# Tap a native view by its exact accessibility label or text.
tap() {
  local x='' y=''
  ui >"$out/.ui.xml"
  read -r x y < <(python3 - "$1" "$out/.ui.xml" <<'PY'
import re, sys, xml.etree.ElementTree as ET
label, dump = sys.argv[1], sys.argv[2]
for node in ET.parse(dump).getroot().iter("node"):
    if label in (node.get("content-desc"), node.get("text")):
        x1, y1, x2, y2 = map(int, re.findall(r"\d+", node.get("bounds")))
        print((x1 + x2) // 2, (y1 + y2) // 2)
        break
PY
  ) || true
  [[ $x ]] || { echo "Can't find '$1' to tap"; return 1; }
  adb shell input tap "$x" "$y"
}
# Phones open a new tab from the tabs view; tablets from the tab strip.
new_tab() {
  if tap Tabs; then sleep 2; fi
  tap "Open a new tab"
}

adb shell settings put global window_animation_scale 0
adb shell settings put global transition_animation_scale 0
adb shell settings put global animator_duration_scale 0
adb shell cmd uimode night no
adb install -r "$apk"

# Let the emulator's own apps finish starting first.
sleep 30
calm
adb shell am start -W -n "$pkg/.MainActivity"
shot welcome 30

new_tab
shot newtab 8

adb shell am start -W -a android.intent.action.VIEW -d https://kingbennet800.github.io/derp/ "$pkg"
shot site 15

if tap Tabs; then
  shot tabs 3
  adb shell input keyevent KEYCODE_BACK
  sleep 2
fi

adb shell cmd uimode night yes
shot site-dark 10
new_tab
shot newtab-dark 6
adb shell cmd uimode night no
echo "Showcase screenshots: $(ls "$out" | tr '\n' ' ')"

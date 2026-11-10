#!/usr/bin/env bash
# Screenshots of Derp for Android for the website: the welcome dork editor,
# a new tab, Duck mode's duck, Derp's website, the tabs view (phones; tablets
# show a tab strip), then the same in dark mode, and the menu and address bar
# for a look.
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
# Tap a native view by its exact accessibility label or text; with "scroll",
# scroll (the menu) to find it if need be.
tap() {
  local x='' y='' w h tries=1
  [[ ${2:-} == scroll ]] && tries=4
  for ((try = 1; try <= tries; try++)); do
    ui >"$out/.ui.xml" || true
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
    [[ $x || $try == "$tries" ]] && break
    read -r w h < <(adb shell wm size | grep -o '[0-9]*x[0-9]*' | tail -n1 | tr x ' ')
    # (The menu sits at the right: at the bottom on phones, dropping down on tablets.)
    adb shell input swipe $((w * 85 / 100)) $((h * 70 / 100)) $((w * 85 / 100)) $((h * 30 / 100)) 300
    sleep 1
  done
  [[ $x ]] || { echo "Can't find '$1' to tap"; return 1; }
  adb shell input tap "$x" "$y"
}
# What the address bar says, as "field:<text>"; nothing if it can't be read.
address() {
  ui >"$out/.ui.xml" || return 0
  python3 - "$out/.ui.xml" <<'PY' || true
import sys, xml.etree.ElementTree as ET
for node in ET.parse(sys.argv[1]).getroot().iter("node"):
    if node.get("content-desc") == "Address bar":
        print("field:" + node.get("text", ""))
        break
PY
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

# Duck mode (off by default): turn it on in the menu, then search until the
# duck turns up (1 in 10 times) and eats the search instead. Animations back
# on, or the duck's walk is skipped.
adb shell settings put global animator_duration_scale 1
tap Menu
sleep 1
tap "Just for fun" scroll
sleep 1
tap "Duck mode"
sleep 1
tap Done
sleep 2
for try in $(seq 1 40); do
  tap "Address bar" || break
  sleep 1
  adb shell input text "rubber%sducks"
  adb shell input keyevent KEYCODE_ENTER
  sleep 0.4
  adb exec-out screencap -p >"$out/.duck-walk.png"
  sleep 0.8
  adb exec-out screencap -p >"$out/.duck-quack.png"
  # Without the duck Derp searches, and the address bar shows what you searched for.
  bar=$(address)
  if [[ $bar == field:* && $bar != *rubber* ]]; then
    echo "The duck came on try $try"
    mv "$out/.duck-walk.png" "$out/$name-duck-walk.png"
    mv "$out/.duck-quack.png" "$out/$name-duck-quack.png"
    break
  fi
  sleep 2
done
rm -f "$out"/.duck-*.png
adb shell settings put global animator_duration_scale 0

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

# Last, since leaving the address bar takes an uncertain number of BACKs.
tap Menu
shot menu-dark 2
adb shell input keyevent KEYCODE_BACK
sleep 1
tap "Address bar"
shot typing-dark 3
adb shell cmd uimode night no
echo "Showcase screenshots: $(ls "$out" | tr '\n' ' ')"

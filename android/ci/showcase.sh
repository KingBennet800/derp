#!/usr/bin/env bash
# Screenshots of Derp for Android for the website: the welcome dork editor,
# a new tab, Derp's website, the tabs view, then the same in dark mode.
# Usage: showcase.sh <apk> <out dir> <name prefix>
set -euo pipefail
apk=$1 out=$2 name=$3 pkg=io.github.kingbennet800.derp
mkdir -p "$out"

shot() { sleep "$2"; adb exec-out screencap -p >"$out/$name-$1.png"; }
ui() { adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 && adb shell cat /sdcard/ui.xml; }
# Tap a native view by its accessibility label or its text.
tap() {
  local bounds
  bounds=$(ui | grep -oE "(content-desc|text)=\"$1\"[^>]*bounds=\"\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]\"" | head -n1 | grep -oE '\[[0-9,]+\]\[[0-9,]+\]')
  [[ $bounds ]] || { echo "Can't find '$1' to tap"; exit 1; }
  read -r x1 y1 x2 y2 <<<"$(tr '[],' '   ' <<<"$bounds")"
  adb shell input tap $(((x1 + x2) / 2)) $(((y1 + y2) / 2))
}

adb shell settings put global window_animation_scale 0
adb shell settings put global transition_animation_scale 0
adb shell settings put global animator_duration_scale 0
adb shell cmd uimode night no
adb install -r "$apk"

adb shell am start -W -n "$pkg/.MainActivity"
shot welcome 30

tap Tabs
sleep 2
tap "+ New tab"
shot newtab 8

adb shell am start -W -a android.intent.action.VIEW -d https://kingbennet800.github.io/derp/ "$pkg"
shot site 15

tap Tabs
shot tabs 3
adb shell input keyevent KEYCODE_BACK
sleep 2

adb shell cmd uimode night yes
shot site-dark 10
tap Tabs
sleep 2
tap "New tab"
shot newtab-dark 6
adb shell cmd uimode night no
echo "Showcase screenshots: $(ls "$out" | tr '\n' ' ')"

#!/usr/bin/env bash
# Smoke-test Derp for Android on an emulator: install, start, check it shows
# the welcome dork editor, open a link, bookmark it, check history, save a
# password and get it offered back, the just-for-fun gags, the ad blocker,
# find in page, Reader view, Add to home screen, Memory Saver, pairing with a
# computer (tests/pairing.py standing in for it, through a test relay), dark mode;
# screenshots and logcat go to $2. Fails if Derp crashes or isn't running.
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
# Tap the view whose text contains this.
tap_has() {
  local bounds
  bounds=$(ui | grep -o "text=\"[^\"]*$1[^\"]*\"[^>]*bounds=\"\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]\"" | head -n1 | grep -o '\[[0-9,]*\]\[[0-9,]*\]')
  [[ $bounds ]] || return 1
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
echo '<!doctype html><title>Slow</title><p>That took a while.' >"$site/slow.html"
# A web server for these pages; /slow.html takes 9 seconds.
python3 - "$site" >/dev/null 2>&1 <<'PY' &
import functools, http.server, sys, time
class Pages(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/slow"):
            time.sleep(9)
        super().do_GET()
http.server.ThreadingHTTPServer(("127.0.0.1", 8123), functools.partial(Pages, directory=sys.argv[1])).serve_forever()
PY
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

# Just for fun: switch on the gags (animations on for them), bookmark this page
# (Party mode's confetti), open new tabs (Peekaboo: 1 in 6, so not checked),
# type in the address bar (Power typing), close a tab (Tab ghosts), and wait
# on a slow page (Snail mode). Hiccups (1 in 12) and Rainbow mode aren't checked.
adb shell settings put global animator_duration_scale 1
# A switch in the Just for fun panel, scrolling down to it if need be.
gag() {
  for _ in 1 2 3 4; do
    if ui | grep -q "content-desc=\"$1\""; then
      tap "$1"
      return
    fi
    adb shell input swipe $((w / 2)) $((h * 65 / 100)) $((w / 2)) $((h * 35 / 100)) 300
    sleep 1
  done
  echo "Can't find '$1' in Just for fun"
  exit 1
}
tap Menu
sleep 1
tap "Just for fun"
sleep 1
for name in "Snail mode" "Peekaboo" "Party mode" "Sleepy tabs" "Power typing" "Hiccups" "Tab ghosts" "Rainbow mode"; do
  gag "$name"
  sleep 0.5
done
shot 2f-just-for-fun 1
tap_text Done || { echo "No Done button on Just for fun"; exit 1; }
sleep 1
tap Menu
sleep 1
tap "Bookmark this page"
shot 2g-confetti 0.4
logged "Confetti!" "No confetti for a bookmark"
for i in 1 2 3; do
  tap Tabs
  sleep 1
  tap "Open a new tab"
  sleep 3
done
alive "Peekaboo"
tap "Address bar"
sleep 1
adb shell input text sparkle
sleep 1
logged "Sparks!" "No sparks while typing"
tap Tabs
sleep 2
tap "Close tab"
sleep 1
logged "Boo!" "No ghost for a closed tab"
adb shell input keyevent KEYCODE_BACK
sleep 1
alive "Power typing and Tab ghosts"
# (Animations off again: the emulator's graphics have fallen over animating
# during page loads. The snail still comes; it just doesn't crawl.)
adb shell settings put global animator_duration_scale 0
adb shell am start -W -a android.intent.action.VIEW -d http://localhost:8123/slow.html "$pkg"
shot 2h-snail 5
logged "A snail is crawling" "No snail on a slow page"
sleep 8
alive "Snail mode"

# The ad blocker: uBlock Origin, installed from addons.mozilla.org when Derp first started.
for _ in $(seq 1 30); do
  adb logcat -d | grep -q "Ad blocker ready" && break
  sleep 2
done
logged "Ad blocker ready: uBlock Origin" "uBlock Origin didn't install"

# Find in page and Reader view, on an article.
{
  echo '<!doctype html><meta name="viewport" content="width=device-width, initial-scale=1"><title>Rubber ducks</title>'
  echo '<nav class="menu"><a href="/">Home</a> <a href="/slow.html">Slow</a></nav><article><h1>Rubber ducks</h1>'
  for word in quack honk quack splash quack float; do
    echo "<p>Rubber ducks have floated in bathtubs for more than a century, and every one of them says $word now and then. They are made of vinyl these days, they come in every color you can think of, and they are very good listeners when your code won't work.</p>"
  done
  echo '</article><footer class="footer">Made for testing Derp</footer>'
} >"$site/article.html"
adb shell am start -W -a android.intent.action.VIEW -d http://localhost:8123/article.html "$pkg"
sleep 8
logged "Reader view: this page reads well" "Derp didn't notice the article"
tap Menu
sleep 1
tap "Find in page"
sleep 1
adb shell input text quack
sleep 2
logged "Find in page: 1 of 3" "Find in page didn't find the three quacks"
tap "Next match"
sleep 1
logged "Find in page: 2 of 3" "Find in page didn't go to the next quack"
shot 7-find 0.5
tap "Close find in page"
sleep 1
tap Menu
sleep 1
tap "Reader view"
shot 8-reader 6
logged "page asks: reader.get" "Reader view didn't open"
alive "find in page and Reader view"
adb shell input keyevent KEYCODE_BACK
sleep 3

# Add to home screen asks the launcher to pin the page.
tap Menu
sleep 1
tap "Add to home screen"
shot 9-home-screen 4
logged "Add to home screen: asked to pin localhost" "Add to home screen didn't ask the launcher"
adb shell input keyevent KEYCODE_BACK
sleep 1
alive "Add to home screen"

# Memory Saver: Android says it's short of memory, so tabs you're not looking
# at fall asleep (and snore, with Sleepy tabs on); one wakes up when you go back to it.
adb shell am send-trim-memory "$pkg" RUNNING_LOW
sleep 3
logged "Memory Saver: a tab fell asleep" "Memory Saver didn't put tabs to sleep"
tap Tabs
shot 3-tabs 3
ui | grep -q "💤" || { echo "Sleeping tabs don't snore"; exit 1; }
tap_has "Example Domain" || { echo "Can't find the example.com tab"; exit 1; }
sleep 5
logged "Memory Saver: a tab woke up" "The sleeping tab didn't wake up"
alive "Memory Saver"

# Your devices: a computer shows a pairing code; its link opens in Derp, which
# asks, pairs, and swaps bookmarks, passwords and tabs with it.
pairing="$(dirname "$0")/../../tests/pairing.py"
python3 "$pairing" relay --port 8124 >"$out/relay.log" 2>&1 &
relay=$!
trap 'kill $server $relay 2>/dev/null || true' EXIT
adb reverse tcp:8124 tcp:8124
sleep 1
link=$(python3 "$pairing" new --relay http://localhost:8124/)
desk=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
now=$(($(date +%s) * 1000))
cat >"$out/desk.json" <<JSON
{"tabs": [{"url": "https://example.com/on-the-computer", "title": "Open on the computer"}],
 "bookmarks": {"https://example.org/from-the-computer": {"title": "From the computer", "at": $now, "gone": false}},
 "logins": {"https://desk.example\n\ndeskuser": {"origin": "https://desk.example", "realm": "", "form": "", "username": "deskuser", "password": "deskpass1", "at": $now, "gone": false}}}
JSON
python3 "$pairing" push "$link" --device $desk --name "Derp on a CI box" --snapshot "$out/desk.json" >/dev/null
adb shell "am start -W -a android.intent.action.VIEW -d '$link' $pkg" >/dev/null
sleep 3
shot 10-pair 0
tap_text Pair || { ui >"$out/ui-no-pair.xml"; echo "Derp didn't ask to pair"; exit 1; }
for _ in $(seq 1 20); do
  adb logcat -d | grep -q "Your devices: paired" && break
  sleep 1
done
logged "Your devices: paired with Derp on a CI box" "Derp didn't pair with the computer"
shot 11-devices 3
alive "pairing"
python3 "$pairing" pull "$link" >"$out/pulled.json"
python3 - "$out/pulled.json" $desk <<'CHECK'
import json, sys
slots = json.load(open(sys.argv[1]))
phones = [s for d, s in slots.items() if d != sys.argv[2]]
assert len(phones) == 1, f"no phone on the relay: {list(slots)}"
phone = phones[0]
assert phone["kind"] == "phone", phone["kind"]
assert "https://example.com/" in phone["bookmarks"], "the phone's bookmark didn't reach the computer"
assert "https://example.org/from-the-computer" in phone["bookmarks"], "the phone didn't take the computer's bookmark"
logins = list(phone["logins"].values())
assert any(l["username"] == "tester" and l["password"] == "hunter2hunter2" for l in logins), "the phone's password didn't reach the computer"
assert any(l["username"] == "deskuser" and l["password"] == "deskpass1" for l in logins), "the phone didn't take the computer's password"
assert phone["tabs"], "the phone sent no tabs"
print(f"Paired: {phone['name']} sent {len(phone['bookmarks'])} bookmarks, {len(logins)} passwords, {len(phone['tabs'])} tabs")
CHECK

# The tabs view and the menu.
tap Tabs
shot 3b-tabs 3
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
echo "Derp ran: first start, a link, bookmarks, history, a saved password, the gags, the ad blocker, find in page, Reader view, Add to home screen, Memory Saver, pairing, dark mode."

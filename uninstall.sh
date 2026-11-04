#!/usr/bin/env bash
# Remove Derp from Linux or macOS. Your profile (bookmarks, history, logins)
# is kept unless you pass --purge.
set -euo pipefail

if [[ $(uname -s) == Darwin ]]; then
  DERP_HOME=${DERP_HOME:-$HOME/Library/Application Support/Derp}
  agent=$HOME/Library/LaunchAgents/io.github.kingbennet800.derp.update.plist
  launchctl bootout "gui/$(id -u)" "$agent" 2>/dev/null || true
  rm -f "$agent"
  rm -rf "${DERP_APP:-$HOME/Applications/Derp.app}" "${DERP_HOME:?}"/{Derp.app.next,python}
else
  DERP_HOME=${DERP_HOME:-$HOME/.local/share/derp}
  icons=$HOME/.local/share/icons/hicolor
  rm -f "$HOME/.local/bin/derp" "$HOME/.local/share/applications"/derp.desktop "$HOME/.local/share/applications"/derp.webapp-*.desktop
  rm -f "$icons"/*/apps/derp.png "$icons/scalable/apps/derp.svg"
  rm -rf "${DERP_HOME:?}"/{firefox,firefox.next,firefox.old}
fi
rm -rf "${DERP_HOME:?}"/{brand,config,features,theme,lib,.update.lock.d}
rm -f "${DERP_HOME:?}"/{VERSION,.update-checked,update.log}

if [[ ${1:-} == --purge ]]; then
  rm -rf "${DERP_HOME:?}"
  echo "Derp and its profile are gone."
else
  echo "Derp removed. Your profile is still in $DERP_HOME/profile (use --purge to delete it)."
fi

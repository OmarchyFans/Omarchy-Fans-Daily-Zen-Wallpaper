#!/bin/bash
# Reverses install.sh: removes the ~/.local/bin symlink and the keybinding, and
# puts the current theme's own background back. Keeps the still frames, the
# Aether theme and the settings unless --purge.
set -euo pipefail
MARK="fans.omarchy.daily-zen-wallpaper"
REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# Tools only from root-owned system folders (see bin/omarchy-daily-zen); tests may add the plugin's own stubs.
PATH=/usr/share/omarchy/bin:/usr/local/bin:/usr/bin:/bin
[[ -n ${DZ_TEST_STUBS:-} && $DZ_TEST_STUBS == "$REPO/tests/stubs" ]] && PATH="$DZ_TEST_STUBS:$PATH"
export PATH
"$REPO/bin/omarchy-daily-zen" mode off >/dev/null 2>&1 || true
L="$HOME/.local/bin/omarchy-daily-zen"
[[ -L $L ]] && rm -f "$L" && echo "  removed $L"
B="$HOME/.config/hypr/bindings.lua"
if [[ -f $B ]] && grep -q "$MARK" "$B"; then
  cp -a "$B" "$B.bak.$(date +%s)"
  python3 - "$B" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r'\n-- Daily Zen Wallpaper \(fans\.omarchy\.daily-zen-wallpaper\).*?\no\.bind\("SUPER \+ ALT \+ Z".*?\n', '\n', s, flags=re.S)
open(p, "w").write(s)
PY
  echo "  removed the keybinding from $B"
fi
# The still frames were set as the Omarchy background; go back to the theme's own picture.
CUR=$(readlink -f "$HOME/.local/state/omarchy/current/background" 2>/dev/null || true)
FRAMES="${XDG_DATA_HOME:-$HOME/.local/share}/omarchy-daily-zen/frames"
if [[ -n $CUR && $CUR == "$FRAMES"/* ]] && command -v omarchy-theme-bg-next >/dev/null 2>&1; then
  omarchy-theme-bg-next >/dev/null 2>&1 && echo "  background set back to the theme's own picture"
fi
if [[ ${1:-} == --purge ]]; then
  name=$(jq -r '.theme_name // "daily-zen"' "${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-daily-zen/config.json" 2>/dev/null || echo daily-zen)
  [[ $name =~ ^[a-z0-9_][a-z0-9._+-]*$ ]] && rm -rf "${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/themes/$name"
  rm -rf "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-daily-zen" "${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-daily-zen" \
         "${XDG_DATA_HOME:-$HOME/.local/share}/omarchy-daily-zen" "${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-daily-zen"
  echo "  purged frames, the Aether theme, settings and caches"
fi
echo "Done. Remove the plugin itself with: omarchy plugin remove $MARK"

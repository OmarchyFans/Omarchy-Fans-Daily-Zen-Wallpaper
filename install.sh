#!/bin/bash
#
# Optional extras for Daily Zen Wallpaper. `omarchy plugin add` already installs
# the plugin; enabling the bar chip starts the engine. This script offers what a
# plugin cannot ship itself, each behind its own confirmation and each idempotent:
#
#   1. symlink bin/omarchy-daily-zen into ~/.local/bin
#   2. SUPER + ALT + Z -> animated <-> still (appended to ~/.config/hypr/bindings.lua)
#   3. a first still frame right now, so still mode has a picture from the start
#
# Nothing is overwritten: existing entries are detected and skipped, and a
# timestamped backup is taken before a config file is appended to. No sudo.
set -euo pipefail
REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# Tools only from root-owned system folders (see bin/omarchy-daily-zen); tests may add the plugin's own stubs.
PATH=/usr/share/omarchy/bin:/usr/local/bin:/usr/bin:/bin
[[ -n ${DZ_TEST_STUBS:-} && $DZ_TEST_STUBS == "$REPO/tests/stubs" ]] && PATH="$DZ_TEST_STUBS:$PATH"
export PATH
BIN="$REPO/bin/omarchy-daily-zen"
MARK="fans.omarchy.daily-zen-wallpaper"
YES=0; [[ ${1:-} == --yes ]] && YES=1
ask() { (( YES )) && return 0; read -rp "$1 [y/N] " a; [[ $a == [yY]* ]]; }

chmod +x "$BIN" 2>/dev/null || true

missing=()
for tool in yt-dlp ffmpeg jq aether; do command -v "$tool" >/dev/null 2>&1 || missing+=("$tool"); done
if (( ${#missing[@]} )); then
  echo "  missing: ${missing[*]} (all ship with Omarchy; install with: sudo pacman -S ${missing[*]})"
fi

if ask "Symlink omarchy-daily-zen into ~/.local/bin?"; then
  mkdir -p "$HOME/.local/bin"; ln -sfn "$BIN" "$HOME/.local/bin/omarchy-daily-zen"
  echo "  linked ~/.local/bin/omarchy-daily-zen"
fi

B="$HOME/.config/hypr/bindings.lua"
if [[ -f $B ]] && grep -q "$MARK" "$B"; then
  echo "  keybinding already present in $B"
elif [[ -f $B ]] && grep -qE '^[^-]*"SUPER \+ ALT \+ Z"' "$B"; then
  echo "  SUPER + ALT + Z is already bound in $B; skipped (bind 'omarchy-daily-zen mode still' yourself)"
elif ask "Add SUPER + ALT + Z -> toggle animated / still to $B?"; then
  [[ -f $B ]] && cp -a "$B" "$B.bak.$(date +%s)"
  cat >>"$B" <<LUA

-- Daily Zen Wallpaper ($MARK): animated stream <-> still frame.
o.bind("SUPER + ALT + Z", "Zen wallpaper: animated / still", "$HOME/.config/omarchy/plugins/$MARK/bin/omarchy-daily-zen toggle-mode")
LUA
  echo "  appended; run 'hyprctl reload && hyprctl configerrors' to verify"
fi

if (( ${#missing[@]} == 0 )) && ask "Grab a first still frame now (one frame from the stream becomes your background)?"; then
  if out=$("$BIN" still 2>&1); then echo "  still saved: ${out##*$'\n'}"; else echo "  could not grab a still yet: ${out##*$'\n'}"; fi
fi
echo "Done. Enable the chip (and the engine) with: omarchy plugin enable $MARK"

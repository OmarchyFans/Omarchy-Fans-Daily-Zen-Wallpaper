#!/bin/bash
# Offline tests for Daily Zen Wallpaper. Nothing touches the network or your
# real config: HOME and the XDG dirs point at a temporary folder and yt-dlp,
# ffmpeg, aether and the omarchy-* commands are the stubs in tests/stubs.
#
#   tests/run.sh            everything
#   tests/run.sh cli        one group: cli | still | theme | daily | install | update | manifest
set -uo pipefail
R="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
B="$R/bin/omarchy-daily-zen"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME="$T/home" XDG_CONFIG_HOME="$T/config" XDG_STATE_HOME="$T/state" XDG_DATA_HOME="$T/data" XDG_CACHE_HOME="$T/cache"
mkdir -p "$HOME/.config/hypr" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
export DZ_TEST_STUBS="$R/tests/stubs" DZ_LOG="$T/log" DZ_FIXTURE="$R/tests/fixtures/video.json"
GROUPS_ALL=(manifest cli still theme daily install update)
want() { (( $# == 0 )) || true; [[ ${#ONLY[@]} -eq 0 || " ${ONLY[*]} " == *" $1 "* ]]; }
ONLY=("$@")
fails=0; pass=0
tfail() { echo "  FAIL: $*"; fails=$((fails + 1)); }
tok() { pass=$((pass + 1)); }
j() { jq -r "$1" <<<"$2"; }
reset() { : >"$DZ_LOG"; rm -rf "$XDG_STATE_HOME/omarchy-daily-zen" "$XDG_CONFIG_HOME/omarchy-daily-zen" "$XDG_DATA_HOME/omarchy-daily-zen"; unset DZ_FAIL DZ_FFMPEG_FAIL DZ_STREAMS_EMPTY; }

if want manifest; then
  echo "== manifest: schema, entry points, no symlinks, executable helper"
  m="$R/manifest.json"
  [[ $(jq -r .schemaVersion "$m") == 1 && $(jq -r .id "$m") == fans.omarchy.daily-zen-wallpaper ]] && tok || tfail "schemaVersion/id"
  [[ $(jq -r .id "$m") != omarchy.* ]] && tok || tfail "id must not start with omarchy."
  for k in service barWidget; do f=$(jq -r ".entryPoints.$k" "$m"); [[ -f $R/$f ]] && tok || tfail "entryPoints.$k -> $f missing"; done
  [[ $(jq -r .version "$m") =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && tok || tfail "version is not x.y.z"
  grep -q "^## $(jq -r .version "$m")\$" "$R/CHANGELOG.md" && tok || tfail "CHANGELOG.md has no section for $(jq -r .version "$m")"
  [[ -z $(find "$R" -path "$R/.git" -prune -o -type l -print) ]] && tok || tfail "symlinks in the tree"
  [[ -x $B && -x $R/install.sh && -x $R/uninstall.sh ]] && tok || tfail "helper or install scripts not executable"
  bash -n "$B" && bash -n "$R/lib/update.sh" && bash -n "$R/install.sh" && bash -n "$R/uninstall.sh" && tok || tfail "bash -n"
  ! grep -nE '"(sh|bash)", "-c"' "$R/Widget.qml" >/dev/null && tok || tfail "Widget.qml runs a shell string"
  [[ $(command -v omarchy-plugin-validate) ]] && { omarchy-plugin-validate "$R" >/dev/null 2>&1 && tok || tfail "omarchy plugin validate"; }
fi

if want cli; then
  echo "== cli: defaults, settings, url validation, resolve"
  reset
  out=$("$B" status --json) || tfail "status --json exited $?"
  [[ $(j .config.mode "$out") == animated && $(j .config.quality "$out") == 720 && $(j .config.url "$out") == https://www.youtube.com/watch?v=vFJuk4U-V7Q ]] && tok || tfail "defaults: $out"
  "$B" mode still >/dev/null && [[ $(jq -r .mode "$XDG_CONFIG_HOME/omarchy-daily-zen/config.json") == still ]] && tok || tfail "mode still"
  ! "$B" mode loud 2>/dev/null && tok || tfail "mode rejects nonsense"
  "$B" volume 0.5 >/dev/null && [[ $(jq -r .volume "$XDG_CONFIG_HOME/omarchy-daily-zen/config.json") == 0.5 ]] && tok || tfail "volume"
  ! "$B" volume 5 2>/dev/null && tok || tfail "volume rejects 5"
  "$B" sound off >/dev/null && [[ $(jq -r .sound "$XDG_CONFIG_HOME/omarchy-daily-zen/config.json") == false ]] && tok || tfail "sound off"
  "$B" quality 1080 >/dev/null && [[ $(jq -r .quality "$XDG_CONFIG_HOME/omarchy-daily-zen/config.json") == 1080 ]] && tok || tfail "quality"
  grep -q "omarchy-shell -q daily-zen reload" "$DZ_LOG" && tok || tfail "settings nudge the engine over IPC"
  "$B" toggle-mode >/dev/null; [[ $(jq -r .mode "$XDG_CONFIG_HOME/omarchy-daily-zen/config.json") == animated ]] && tok || tfail "toggle-mode"
  for bad in 'http://www.youtube.com/watch?v=x' 'https://evil.example/watch?v=x' 'https://www.youtube.com/watch?v=x; rm -rf ~' '-https://youtu.be/x' 'https://www.youtube.com/watch?v=x`id`'; do
    ! "$B" set-url "$bad" >/dev/null 2>&1 && tok || tfail "set-url accepted: $bad"
  done
  "$B" set-url 'https://youtu.be/vFJuk4U-V7Q' >/dev/null 2>&1 && [[ $(jq -r .url "$XDG_CONFIG_HOME/omarchy-daily-zen/config.json") == https://youtu.be/vFJuk4U-V7Q ]] && tok || tfail "set-url youtu.be"
  reset; "$B" quality 720 >/dev/null
  out=$("$B" resolve --json) || tfail "resolve exited $?"
  [[ $(j .video_format "$out") == 232 && $(j .audio_format "$out") == 234 && $(j .video_height "$out") == 720 && $(j .expires "$out") == 1900000000 ]] && tok || tfail "720p picks HLS 232 + 234: $out"
  [[ $(j .video_url "$out") == https://example.invalid/232/* ]] && tok || tfail "video url"
  grep -q -- '-j -- https://www.youtube.com/watch?v=vFJuk4U-V7Q' "$DZ_LOG" && tok || tfail "url passed after -- : $(cat "$DZ_LOG")"
  : >"$DZ_LOG"; out=$("$B" resolve --json); [[ -z $(cat "$DZ_LOG") ]] && tok || tfail "second resolve is served from the cache"
  "$B" quality 1080 >/dev/null; out=$("$B" resolve --json); [[ $(j .video_format "$out") == 270 ]] && tok || tfail "1080p picks 270: $(j .video_format "$out")"
  "$B" quality 480 >/dev/null; out=$("$B" resolve --json); [[ $(j .video_format "$out") == 231 ]] && tok || tfail "480p picks 231: $(j .video_format "$out")"
  DZ_FIXTURE="$R/tests/fixtures/nohls.json" "$B" resolve --force --json >"$T/o" && out=$(cat "$T/o")
  [[ $(j .video_protocol "$out") == https && $(j .video_format "$out") == 135 && $(j .audio_format "$out") == 140 ]] && tok || tfail "no HLS: plain https 135 + 140: $(j '[.video_format,.audio_format,.video_protocol]' "$out")"
  DZ_FIXTURE="$R/tests/fixtures/live.json" "$B" resolve --force --json >"$T/o" && out=$(cat "$T/o")
  [[ $(j .is_live "$out") == true && $(j .video_id "$out") == LIVE123 ]] && tok || tfail "live: $out"
  ! DZ_FAIL=1 "$B" resolve --force >/dev/null 2>&1 && tok || tfail "resolve fails when yt-dlp fails"
  [[ $(jq -r .video_id "$XDG_STATE_HOME/omarchy-daily-zen/stream.json") == LIVE123 ]] && tok || tfail "a failed resolve keeps the last good stream"
  : >"$DZ_LOG"; "$B" set-url 'https://www.youtube.com/@AetherJourney' >/dev/null 2>&1
  grep -q 'flat-playlist --playlist-items 1 --print id -- https://www.youtube.com/@AetherJourney/streams' "$DZ_LOG" && grep -q 'watch?v=STREAM01xyz' "$DZ_LOG" && tok || tfail "channel: streams tab first: $(cat "$DZ_LOG")"
  : >"$DZ_LOG"; DZ_STREAMS_EMPTY=1 "$B" resolve --force >/dev/null 2>&1; grep -q 'watch?v=VIDEO01abcd' "$DZ_LOG" && tok || tfail "channel: videos tab when streams is empty"
  : >"$DZ_LOG"; "$B" set-url 'https://www.youtube.com/playlist?list=PL123' >/dev/null 2>&1; grep -q 'watch?v=PLAY01abcde' "$DZ_LOG" && tok || tfail "playlist: first item"
  out=$("$B" status); [[ $out == *"Daily Zen Wallpaper"* && $out == *"playing"* ]] && tok || tfail "status text: $out"
fi

if want still; then
  echo "== still: frame grab, background set, pruning"
  reset
  out=$("$B" still) || tfail "still exited $?"
  [[ -f $out && $out == "$XDG_DATA_HOME/omarchy-daily-zen/frames/vFJuk4U-V7Q-"*"-at"*.png ]] && tok || tfail "frame path: $out"
  at=${out##*-at}; at=${at%.png}; (( at >= 20817 * 2 / 100 && at <= 20817 * 98 / 100 )) && tok || tfail "random timestamp inside 2..98%: $at"
  grep -q -- "-ss $at -i https://example.invalid/232/" "$DZ_LOG" && tok || tfail "ffmpeg seeks to the timestamp: $(grep ffmpeg "$DZ_LOG")"
  grep -q "omarchy-theme-bg-set $out" "$DZ_LOG" && tok || tfail "background set"
  [[ $(jq -r .path "$XDG_STATE_HOME/omarchy-daily-zen/frame.json") == "$out" ]] && tok || tfail "frame.json"
  : >"$DZ_LOG"; out=$("$B" still --at 100 --no-set); [[ $out == *-at100.png ]] && ! grep -q bg-set "$DZ_LOG" && tok || tfail "--at / --no-set"
  ! "$B" still --at abc >/dev/null 2>&1 && tok || tfail "--at rejects text"
  DZ_FIXTURE="$R/tests/fixtures/live.json" "$B" resolve --force >/dev/null; : >"$DZ_LOG"; out=$("$B" still --no-set)
  ! grep -q -- '-ss' "$DZ_LOG" && [[ $out == *"/LIVE123-"*.png ]] && tok || tfail "live: no seek: $(grep ffmpeg "$DZ_LOG")"
  for i in $(seq 1 14); do touch -d "-$i hours" "$XDG_DATA_HOME/omarchy-daily-zen/frames/old-$i.png"; done
  "$B" still --no-set >/dev/null; n=$(ls "$XDG_DATA_HOME/omarchy-daily-zen/frames"/*.png | wc -l); (( n == 12 )) && tok || tfail "keeps 12 frames, has $n"
  ! DZ_FFMPEG_FAIL=1 "$B" still >/dev/null 2>&1 && tok || tfail "ffmpeg failure is an error"
fi

if want theme; then
  echo "== theme: Aether palette -> Omarchy theme dir -> omarchy-theme-set"
  reset
  frame=$("$B" still --no-set)
  out=$("$B" theme --json) || tfail "theme exited $?"
  d="$XDG_CONFIG_HOME/omarchy/themes/daily-zen"
  [[ $(j .theme "$out") == daily-zen && $(j .applied "$out") == true && -f $d/colors.toml && -f $d/backgrounds/$(basename "$frame") && -f $d/preview.png ]] && tok || tfail "theme dir: $out; $(ls "$d" 2>&1)"
  [[ ! -e $d/alacritty.toml && ! -e $d/hyprland.conf ]] && tok || tfail "only colors.toml and backgrounds are copied (Aether's other files would shadow Omarchy's templates)"
  grep -q "aether --generate $frame --no-apply --output" "$DZ_LOG" && tok || tfail "aether argv: $(grep aether "$DZ_LOG")"
  grep -q "omarchy-theme-set daily-zen" "$DZ_LOG" && tok || tfail "theme applied"
  : >"$DZ_LOG"; "$B" theme --no-apply --light >/dev/null; ! grep -q theme-set "$DZ_LOG" && grep -q -- '--light-mode' "$DZ_LOG" && tok || tfail "--no-apply / --light"
  "$B" still --no-set >/dev/null; "$B" theme --no-apply >/dev/null; (( $(ls "$d/backgrounds" | wc -l) == 1 )) && tok || tfail "the theme keeps one background (the newest frame)"
  mkdir -p "$XDG_CONFIG_HOME/omarchy-daily-zen"; echo '{"theme_name": "../evil"}' >"$XDG_CONFIG_HOME/omarchy-daily-zen/config.json"
  ! "$B" theme --no-apply >/dev/null 2>&1 && tok || tfail "theme_name with a path is refused"
fi

if want daily; then
  echo "== daily: once a day, newest video, theme opt-in"
  reset
  out=$("$B" daily) || tfail "daily exited $?"
  [[ -f $out ]] && grep -q "omarchy-theme-bg-set" "$DZ_LOG" && grep -q "omarchy-shell -q daily-zen refresh" "$DZ_LOG" && tok || tfail "first daily: still + refresh: $out / $(cat "$DZ_LOG")"
  ! grep -q "omarchy-theme-set" "$DZ_LOG" && tok || tfail "no theme unless daily_theme"
  : >"$DZ_LOG"; out=$("$B" daily); [[ $out == "already refreshed today" && -z $(cat "$DZ_LOG") ]] && tok || tfail "second run does nothing: $out"
  "$B" daily-theme on >/dev/null; : >"$DZ_LOG"; "$B" daily --force >/dev/null; grep -q "omarchy-theme-set daily-zen" "$DZ_LOG" && tok || tfail "--force with daily_theme builds the theme"
  "$B" daily-refresh off >/dev/null; : >"$DZ_LOG"; out=$("$B" daily); [[ $out == "daily refresh is off" && -z $(cat "$DZ_LOG") ]] && tok || tfail "daily_refresh off: $out"
  jq -r '.last' "$XDG_STATE_HOME/omarchy-daily-zen/daily.json" | grep -qE '^[0-9]+$' && tok || tfail "daily.json stamp"
fi

if want install; then
  echo "== install: idempotent, asks, reversible"
  reset
  cp "$R/tests/fixtures/video.json" "$T/fixture.json"
  printf -- '-- bindings\n' >"$HOME/.config/hypr/bindings.lua"
  "$R/install.sh" --yes >"$T/inst" 2>&1 || tfail "install.sh --yes: $(cat "$T/inst")"
  [[ -L $HOME/.local/bin/omarchy-daily-zen ]] && tok || tfail "symlink"
  grep -q 'SUPER + ALT + Z' "$HOME/.config/hypr/bindings.lua" && tok || tfail "keybinding"
  (( $(grep -c 'toggle-mode' "$HOME/.config/hypr/bindings.lua") == 1 )) && tok || tfail "keybinding once"
  ls "$HOME/.config/hypr/"bindings.lua.bak.* >/dev/null 2>&1 && tok || tfail "backup taken"
  "$R/install.sh" --yes >/dev/null 2>&1; (( $(grep -c 'toggle-mode' "$HOME/.config/hypr/bindings.lua") == 1 )) && tok || tfail "second install does not duplicate"
  grep -q "omarchy-theme-bg-set" "$DZ_LOG" && tok || tfail "first still grabbed on install"
  "$R/uninstall.sh" >/dev/null 2>&1 || tfail "uninstall.sh"
  [[ ! -e $HOME/.local/bin/omarchy-daily-zen ]] && ! grep -q 'toggle-mode' "$HOME/.config/hypr/bindings.lua" && tok || tfail "uninstall reverses"
  [[ -d $XDG_DATA_HOME/omarchy-daily-zen ]] && tok || tfail "uninstall keeps frames"
  "$R/uninstall.sh" --purge >/dev/null 2>&1; [[ ! -d $XDG_DATA_HOME/omarchy-daily-zen && ! -d $XDG_CONFIG_HOME/omarchy-daily-zen ]] && tok || tfail "--purge"
fi

if want update; then
  echo "== update: the update check against file:// fixtures (docs/update-alerts.md)"
  reset
  export OMARCHY_PLUGIN_UPDATE_RAW="file://$R/tests/fixtures/published"
  out=$("$B" update-check 0.1.0) || tfail "update-check exited $?"
  [[ $(j .latest "$out") == 9.9.9 && $(j .update_available "$out") == true && $(j '.notes|join(",")' "$out") == "Newest thing,Older thing" ]] && tok || tfail "update-check: $out"
  out=$("$B" update-check); [[ $(j .mismatch "$out") == false && $(j .update_available "$out") == true ]] && tok || tfail "same version, no mismatch: $out"
  [[ -f $XDG_CACHE_HOME/omarchy-daily-zen/update-check.json ]] && tok || tfail "no cache written"
  out=$(OMARCHY_PLUGIN_UPDATE_RAW=file:///nonexistent "$B" update-check); [[ $(j .latest "$out") == 9.9.9 ]] && tok || tfail "offline answer from cache: $out"
  "$B" update-dismiss 9.9.9 && [[ $("$B" update-check | jq -r .dismissed) == 9.9.9 ]] && tok || tfail "dismiss"
  mkdir -p "$XDG_CONFIG_HOME/omarchy-daily-zen"; echo '{"update_check": false}' >"$XDG_CONFIG_HOME/omarchy-daily-zen/config.json"
  out=$("$B" update-check --force); [[ $(j .enabled "$out") == false && $(j .latest "$out") == null ]] && tok || tfail "opt-out: $out"
  out=$(OMARCHY_PLUGIN_UPDATE_PRINT=1 "$B" update-run all); [[ $(j '.argv[0]' "$out") == *omarchy-launch-tui && $(j '.argv[-1]' "$out") == all ]] && tok || tfail "update-run argv: $out"
  ! "$B" update-run bogus 2>/dev/null && tok || tfail "update-run rejects unknown steps"
  unset OMARCHY_PLUGIN_UPDATE_RAW
fi

echo; echo "$pass passed, $fails failed"
(( fails == 0 ))

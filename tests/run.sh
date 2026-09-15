#!/bin/bash
# Offline tests for Zen Wallpaper. Nothing touches the network or your
# real config: HOME and the XDG dirs point at a temporary folder and yt-dlp,
# ffmpeg, aether and the omarchy-* commands are the stubs in tests/stubs.
#
#   tests/run.sh            everything
#   tests/run.sh cli        one group: cli | still | theme | daily | install | update | manifest
set -uo pipefail
R="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
B="$R/bin/omarchy-zen"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME="$T/home" XDG_CONFIG_HOME="$T/config" XDG_STATE_HOME="$T/state" XDG_DATA_HOME="$T/data" XDG_CACHE_HOME="$T/cache"
mkdir -p "$HOME/.config/hypr" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
export DZ_TEST_STUBS="$R/tests/stubs" DZ_LOG="$T/log" DZ_FIXTURE="$R/tests/fixtures/video.json"
export DZ_CATALOG_FIXTURE="$R/tests/fixtures/catalog.json" DZ_RATINGS_FIXTURE="$R/tests/fixtures/ratings.json"
GROUPS_ALL=(manifest cli still theme daily install update library position api)
want() { (( $# == 0 )) || true; [[ ${#ONLY[@]} -eq 0 || " ${ONLY[*]} " == *" $1 "* ]]; }
ONLY=("$@")
fails=0; pass=0
tfail() { echo "  FAIL: $*"; fails=$((fails + 1)); }
tok() { pass=$((pass + 1)); }
j() { jq -r "$1" <<<"$2"; }
reset() { : >"$DZ_LOG"; rm -rf "$XDG_STATE_HOME/omarchy-zen" "$XDG_CONFIG_HOME/omarchy-zen" "$XDG_DATA_HOME/omarchy-zen" "$XDG_CACHE_HOME/omarchy-zen"; unset DZ_FAIL DZ_FFMPEG_FAIL DZ_STREAMS_EMPTY DZ_OFFLINE DZ_FAIL_MATCH; }

if want manifest; then
  echo "== manifest: schema, entry points, no symlinks, executable helper"
  m="$R/manifest.json"
  [[ $(jq -r .schemaVersion "$m") == 1 && $(jq -r .id "$m") == fans.omarchy.zen-wallpaper ]] && tok || tfail "schemaVersion/id"
  [[ $(jq -r .id "$m") != omarchy.* ]] && tok || tfail "id must not start with omarchy."
  for k in service barWidget; do f=$(jq -r ".entryPoints.$k" "$m"); [[ -f $R/$f ]] && tok || tfail "entryPoints.$k -> $f missing"; done
  [[ $(jq -r .version "$m") =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && tok || tfail "version is not x.y.z"
  grep -q "^## $(jq -r .version "$m")\$" "$R/CHANGELOG.md" && tok || tfail "CHANGELOG.md has no section for $(jq -r .version "$m")"
  [[ -z $(find "$R" -path "$R/.git" -prune -o -type l -print) ]] && tok || tfail "symlinks in the tree"
  [[ -x $B && -x $R/install.sh && -x $R/uninstall.sh ]] && tok || tfail "helper or install scripts not executable"
  jq -e '.schema == 1 and (.categories | length) >= 5 and all(.categories[]; (.entries | length) == 10) and (.channels[0].id == "AetherJourneyMusic")' "$R/catalog.json" >/dev/null && tok || tfail "catalog.json: 10 entries per category, Aether Journey first creator"
  [[ $(jq -r .url "$R/tests/fixtures/catalog.json") != "" ]] && node --check "$R/api/worker.js" 2>/dev/null && tok || tfail "api/worker.js does not parse"
  bash -n "$B" && bash -n "$R/lib/update.sh" && bash -n "$R/install.sh" && bash -n "$R/uninstall.sh" && tok || tfail "bash -n"
  ! grep -nE '"(sh|bash)", "-c"' "$R/Widget.qml" >/dev/null && tok || tfail "Widget.qml runs a shell string"
  [[ $(command -v omarchy-plugin-validate) ]] && { omarchy-plugin-validate "$R" >/dev/null 2>&1 && tok || tfail "omarchy plugin validate"; }
fi

if want cli; then
  echo "== cli: defaults, settings, url validation, resolve"
  reset
  out=$("$B" status --json) || tfail "status --json exited $?"
  [[ $(j .config.mode "$out") == animated && $(j .config.quality "$out") == 720 && $(j .config.url "$out") == https://www.youtube.com/watch?v=vFJuk4U-V7Q ]] && tok || tfail "defaults: $out"
  "$B" mode still >/dev/null && [[ $(jq -r .mode "$XDG_CONFIG_HOME/omarchy-zen/config.json") == still ]] && tok || tfail "mode still"
  ! "$B" mode loud 2>/dev/null && tok || tfail "mode rejects nonsense"
  "$B" volume 0.5 >/dev/null && [[ $(jq -r .volume "$XDG_CONFIG_HOME/omarchy-zen/config.json") == 0.5 ]] && tok || tfail "volume"
  ! "$B" volume 5 2>/dev/null && tok || tfail "volume rejects 5"
  "$B" sound off >/dev/null && [[ $(jq -r .sound "$XDG_CONFIG_HOME/omarchy-zen/config.json") == false ]] && tok || tfail "sound off"
  "$B" quality 1080 >/dev/null && [[ $(jq -r .quality "$XDG_CONFIG_HOME/omarchy-zen/config.json") == 1080 ]] && tok || tfail "quality"
  grep -q "omarchy-shell -q zen reload" "$DZ_LOG" && tok || tfail "settings nudge the engine over IPC"
  "$B" toggle-mode >/dev/null; [[ $(jq -r .mode "$XDG_CONFIG_HOME/omarchy-zen/config.json") == animated ]] && tok || tfail "toggle-mode"
  for bad in 'http://www.youtube.com/watch?v=x' 'https://evil.example/watch?v=x' 'https://www.youtube.com/watch?v=x; rm -rf ~' '-https://youtu.be/x' 'https://www.youtube.com/watch?v=x`id`'; do
    ! "$B" set-url "$bad" >/dev/null 2>&1 && tok || tfail "set-url accepted: $bad"
  done
  "$B" set-url 'https://youtu.be/vFJuk4U-V7Q' >/dev/null 2>&1 && [[ $(jq -r .url "$XDG_CONFIG_HOME/omarchy-zen/config.json") == https://youtu.be/vFJuk4U-V7Q ]] && tok || tfail "set-url youtu.be"
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
  [[ $(jq -r .video_id "$XDG_STATE_HOME/omarchy-zen/stream.json") == LIVE123 ]] && tok || tfail "a failed resolve keeps the last good stream"
  : >"$DZ_LOG"; "$B" set-url 'https://www.youtube.com/@AetherJourney' >/dev/null 2>&1
  grep -q 'flat-playlist --playlist-items 1 --print id -- https://www.youtube.com/@AetherJourney/streams' "$DZ_LOG" && grep -q 'watch?v=STREAM01xyz' "$DZ_LOG" && tok || tfail "channel: streams tab first: $(cat "$DZ_LOG")"
  : >"$DZ_LOG"; DZ_STREAMS_EMPTY=1 "$B" resolve --force >/dev/null 2>&1; grep -q 'watch?v=VIDEO01abcd' "$DZ_LOG" && tok || tfail "channel: videos tab when streams is empty"
  : >"$DZ_LOG"; "$B" set-url 'https://www.youtube.com/playlist?list=PL123' >/dev/null 2>&1; grep -q 'watch?v=PLAY01abcde' "$DZ_LOG" && tok || tfail "playlist: first item"
  out=$("$B" status); [[ $out == *"Zen Wallpaper"* && $out == *"playing"* ]] && tok || tfail "status text: $out"
fi

if want still; then
  echo "== still: frame grab, background set, pruning"
  reset
  out=$("$B" still) || tfail "still exited $?"
  [[ -f $out && $out == "$XDG_DATA_HOME/omarchy-zen/frames/vFJuk4U-V7Q-"*"-at"*.png ]] && tok || tfail "frame path: $out"
  at=${out##*-at}; at=${at%.png}; (( at >= 20817 * 2 / 100 && at <= 20817 * 98 / 100 )) && tok || tfail "random timestamp inside 2..98%: $at"
  grep -q -- "-ss $at -i https://example.invalid/232/" "$DZ_LOG" && tok || tfail "ffmpeg seeks to the timestamp: $(grep ffmpeg "$DZ_LOG")"
  grep -q "omarchy-theme-bg-set $out" "$DZ_LOG" && tok || tfail "background set"
  [[ $(jq -r .path "$XDG_STATE_HOME/omarchy-zen/frame.json") == "$out" ]] && tok || tfail "frame.json"
  : >"$DZ_LOG"; out=$("$B" still --at 100 --no-set); [[ $out == *-at100.png ]] && ! grep -q bg-set "$DZ_LOG" && tok || tfail "--at / --no-set"
  ! "$B" still --at abc >/dev/null 2>&1 && tok || tfail "--at rejects text"
  DZ_FIXTURE="$R/tests/fixtures/live.json" "$B" resolve --force >/dev/null; : >"$DZ_LOG"; out=$("$B" still --no-set)
  ! grep -q -- '-ss' "$DZ_LOG" && [[ $out == *"/LIVE123-"*.png ]] && tok || tfail "live: no seek: $(grep ffmpeg "$DZ_LOG")"
  for i in $(seq 1 14); do touch -d "-$i hours" "$XDG_DATA_HOME/omarchy-zen/frames/old-$i.png"; done
  "$B" still --no-set >/dev/null; n=$(ls "$XDG_DATA_HOME/omarchy-zen/frames"/*.png | wc -l); (( n == 12 )) && tok || tfail "keeps 12 frames, has $n"
  ! DZ_FFMPEG_FAIL=1 "$B" still >/dev/null 2>&1 && tok || tfail "ffmpeg failure is an error"
fi

if want theme; then
  echo "== theme: Aether palette -> Omarchy theme dir -> omarchy-theme-set"
  reset
  frame=$("$B" still --no-set)
  out=$("$B" theme --json) || tfail "theme exited $?"
  d="$XDG_CONFIG_HOME/omarchy/themes/zen"
  [[ $(j .theme "$out") == zen && $(j .applied "$out") == true && -f $d/colors.toml && -f $d/backgrounds/$(basename "$frame") && -f $d/preview.png ]] && tok || tfail "theme dir: $out; $(ls "$d" 2>&1)"
  [[ ! -e $d/alacritty.toml && ! -e $d/hyprland.conf ]] && tok || tfail "only colors.toml and backgrounds are copied (Aether's other files would shadow Omarchy's templates)"
  grep -q "aether --generate $frame --no-apply --output" "$DZ_LOG" && tok || tfail "aether argv: $(grep aether "$DZ_LOG")"
  grep -q "omarchy-theme-set zen" "$DZ_LOG" && tok || tfail "theme applied"
  : >"$DZ_LOG"; "$B" theme --no-apply --light >/dev/null; ! grep -q theme-set "$DZ_LOG" && grep -q -- '--light-mode' "$DZ_LOG" && tok || tfail "--no-apply / --light"
  "$B" still --no-set >/dev/null; "$B" theme --no-apply >/dev/null; (( $(ls "$d/backgrounds" | wc -l) == 1 )) && tok || tfail "the theme keeps one background (the newest frame)"
  mkdir -p "$XDG_CONFIG_HOME/omarchy-zen"; echo '{"theme_name": "../evil"}' >"$XDG_CONFIG_HOME/omarchy-zen/config.json"
  ! "$B" theme --no-apply >/dev/null 2>&1 && tok || tfail "theme_name with a path is refused"
fi

if want daily; then
  echo "== daily: once a day, newest video, theme opt-in"
  reset
  out=$("$B" daily) || tfail "daily exited $?"
  [[ -f $out ]] && grep -q "omarchy-theme-bg-set" "$DZ_LOG" && grep -q "omarchy-shell -q zen refresh" "$DZ_LOG" && tok || tfail "first daily: still + refresh: $out / $(cat "$DZ_LOG")"
  ! grep -q "omarchy-theme-set" "$DZ_LOG" && tok || tfail "no theme unless daily_theme"
  : >"$DZ_LOG"; out=$("$B" daily); [[ $out == "already refreshed today" && -z $(cat "$DZ_LOG") ]] && tok || tfail "second run does nothing: $out"
  "$B" daily-theme on >/dev/null; : >"$DZ_LOG"; "$B" daily --force >/dev/null; grep -q "omarchy-theme-set zen" "$DZ_LOG" && tok || tfail "--force with daily_theme builds the theme"
  "$B" daily-refresh off >/dev/null; : >"$DZ_LOG"; out=$("$B" daily); [[ $out == "daily refresh is off" && -z $(cat "$DZ_LOG") ]] && tok || tfail "daily_refresh off: $out"
  jq -r '.last' "$XDG_STATE_HOME/omarchy-zen/daily.json" | grep -qE '^[0-9]+$' && tok || tfail "daily.json stamp"
fi

if want install; then
  echo "== install: idempotent, asks, reversible"
  reset
  cp "$R/tests/fixtures/video.json" "$T/fixture.json"
  printf -- '-- bindings\n' >"$HOME/.config/hypr/bindings.lua"
  "$R/install.sh" --yes >"$T/inst" 2>&1 || tfail "install.sh --yes: $(cat "$T/inst")"
  [[ -L $HOME/.local/bin/omarchy-zen ]] && tok || tfail "symlink"
  grep -q 'SUPER + ALT + Z' "$HOME/.config/hypr/bindings.lua" && tok || tfail "keybinding"
  (( $(grep -c 'toggle-mode' "$HOME/.config/hypr/bindings.lua") == 1 )) && tok || tfail "keybinding once"
  ls "$HOME/.config/hypr/"bindings.lua.bak.* >/dev/null 2>&1 && tok || tfail "backup taken"
  "$R/install.sh" --yes >/dev/null 2>&1; (( $(grep -c 'toggle-mode' "$HOME/.config/hypr/bindings.lua") == 1 )) && tok || tfail "second install does not duplicate"
  grep -q "omarchy-theme-bg-set" "$DZ_LOG" && tok || tfail "first still grabbed on install"
  "$R/uninstall.sh" >/dev/null 2>&1 || tfail "uninstall.sh"
  [[ ! -e $HOME/.local/bin/omarchy-zen ]] && ! grep -q 'toggle-mode' "$HOME/.config/hypr/bindings.lua" && tok || tfail "uninstall reverses"
  [[ -d $XDG_DATA_HOME/omarchy-zen ]] && tok || tfail "uninstall keeps frames"
  "$R/uninstall.sh" --purge >/dev/null 2>&1; [[ ! -d $XDG_DATA_HOME/omarchy-zen && ! -d $XDG_CONFIG_HOME/omarchy-zen ]] && tok || tfail "--purge"
fi

if want update; then
  echo "== update: the update check against file:// fixtures (docs/update-alerts.md)"
  reset
  export OMARCHY_PLUGIN_UPDATE_RAW="file://$R/tests/fixtures/published"
  out=$("$B" update-check 0.1.0) || tfail "update-check exited $?"
  [[ $(j .latest "$out") == 9.9.9 && $(j .update_available "$out") == true && $(j '.notes|join(",")' "$out") == "Newest thing,Older thing" ]] && tok || tfail "update-check: $out"
  out=$("$B" update-check); [[ $(j .mismatch "$out") == false && $(j .update_available "$out") == true ]] && tok || tfail "same version, no mismatch: $out"
  [[ -f $XDG_CACHE_HOME/omarchy-zen/update-check.json ]] && tok || tfail "no cache written"
  out=$(OMARCHY_PLUGIN_UPDATE_RAW=file:///nonexistent "$B" update-check); [[ $(j .latest "$out") == 9.9.9 ]] && tok || tfail "offline answer from cache: $out"
  "$B" update-dismiss 9.9.9 && [[ $("$B" update-check | jq -r .dismissed) == 9.9.9 ]] && tok || tfail "dismiss"
  mkdir -p "$XDG_CONFIG_HOME/omarchy-zen"; echo '{"update_check": false}' >"$XDG_CONFIG_HOME/omarchy-zen/config.json"
  out=$("$B" update-check --force); [[ $(j .enabled "$out") == false && $(j .latest "$out") == null ]] && tok || tfail "opt-out: $out"
  out=$(OMARCHY_PLUGIN_UPDATE_PRINT=1 "$B" update-run all); [[ $(j '.argv[0]' "$out") == *omarchy-launch-tui && $(j '.argv[-1]' "$out") == all ]] && tok || tfail "update-run argv: $out"
  ! "$B" update-run bogus 2>/dev/null && tok || tfail "update-run rejects unknown steps"
  unset OMARCHY_PLUGIN_UPDATE_RAW
fi

if want library; then
  echo "== library: catalog cache, bookmarks, ratings, creators, play"
  reset
  out=$("$B" library --json) || tfail "library exited $?"
  [[ $(j .kind "$out") == category && $(j .category "$out") == zen && $(j '.entries|length' "$out") == 2 && $(j .ratings_api_available "$out") == true ]] && tok || tfail "library default: $(j '{kind,category,ratings_api_available}' "$out")"
  [[ $(j '.entries[0].avg' "$out") == 4.6 && $(j '.entries[0].count' "$out") == 12 && $(j '.entries[0].my_stars' "$out") == 0 && $(j '.entries[0].bookmarked' "$out") == false ]] && tok || tfail "community ratings merged: $(j '.entries[0]' "$out")"
  [[ $(j '.entries[0].plays' "$out") == 150 && $(j '.entries[0].views' "$out") == 500000 && $(j '.entries[1].plays' "$out") == 3 && $(j '.entries[1].viewers' "$out") == 300 ]] && tok || tfail "plays, views and viewers on rows: $(j '[.entries[].plays, .entries[].views]' "$out")"
  [[ $(j '.channels[0].id' "$out") == AetherJourneyMusic && $(j '.categories|length' "$out") == 2 ]] && tok || tfail "channels + categories"
  [[ -f $XDG_CACHE_HOME/omarchy-zen/catalog.json && -f $XDG_CACHE_HOME/omarchy-zen/ratings.json ]] && tok || tfail "caches written"
  : >"$DZ_LOG"; "$B" library --json >/dev/null; [[ -z $(grep curl "$DZ_LOG") ]] && tok || tfail "second library call is served from the caches: $(cat "$DZ_LOG")"
  : >"$DZ_LOG"; "$B" library --json --refresh >/dev/null; (( $(grep -c curl "$DZ_LOG") == 2 )) && tok || tfail "--refresh fetches both"
  out=$("$B" library --json --category lofi); [[ $(j '.entries[0].id' "$out") == LOFI1111111 && $(j '.entries[0].live' "$out") == true ]] && tok || tfail "category lofi"
  # a broken catalog answer keeps the cached one
  DZ_CATALOG_FIXTURE=/dev/null "$B" catalog --refresh >/dev/null 2>&1; [[ $(jq -r .generated "$XDG_CACHE_HOME/omarchy-zen/catalog.json") == 2026-09-15 ]] && tok || tfail "bad fetch keeps the cache"
  reset; rm -f "$XDG_CACHE_HOME/omarchy-zen/catalog.json"; out=$(DZ_OFFLINE=1 "$B" library --json); [[ $(j '.categories|length' "$out") -ge 5 ]] && tok || tfail "offline with no cache: the bundled catalog"
  # bookmarks
  reset; "$B" resolve >/dev/null
  "$B" bookmark add >/dev/null && [[ $(jq -r '.[0].id' "$XDG_CONFIG_HOME/omarchy-zen/bookmarks.json") == vFJuk4U-V7Q && $(jq -r '.[0].title' "$XDG_CONFIG_HOME/omarchy-zen/bookmarks.json") == KUMAMICHI* ]] && tok || tfail "bookmark the playing video"
  "$B" bookmark add LOFI1111111 >/dev/null && [[ $(jq -r '.[1].title' "$XDG_CONFIG_HOME/omarchy-zen/bookmarks.json") == "lofi radio" ]] && tok || tfail "bookmark a catalog entry by id"
  "$B" bookmark add 'https://youtu.be/NEWWWWWWWW1' >/dev/null && [[ $(jq -r '.[2].title' "$XDG_CONFIG_HOME/omarchy-zen/bookmarks.json") == "Fetched title" ]] && tok || tfail "bookmark an unknown video asks yt-dlp for its title"
  "$B" bookmark add LOFI1111111 >/dev/null; (( $(jq length "$XDG_CONFIG_HOME/omarchy-zen/bookmarks.json") == 3 )) && tok || tfail "no duplicates"
  out=$("$B" library --json --bookmarks); [[ $(j .kind "$out") == bookmarks && $(j '.entries|length' "$out") == 3 && $(j '.entries[0].playing' "$out") == true && $(j '.now.id' "$out") == vFJuk4U-V7Q ]] && tok || tfail "library --bookmarks + now: $(j '{kind, n: (.entries|length), now: .now.id}' "$out")"
  lofi=$(j '.entries[] | select(.id == "LOFI1111111")' "$out")
  [[ $(j .views "$lofi") == 0 && $(j .viewers "$lofi") == 20000 && $(j .live "$lofi") == true && $(j '.entries[0].views' "$out") == 500000 ]] && tok || tfail "bookmarks keep views/viewers/live from the catalog: $lofi"
  [[ $(j '.categories[0].bookmarked' "$out") == 1 && $(j '.categories[1].bookmarked' "$out") == 1 && $(j '.channels[0].bookmarked' "$out") == 1 ]] && tok || tfail "bookmark counts per category and creator: $(j '[.categories[].bookmarked, .channels[].bookmarked]' "$out")"
  "$B" bookmark toggle LOFI1111111 >/dev/null; (( $(jq length "$XDG_CONFIG_HOME/omarchy-zen/bookmarks.json") == 2 )) && tok || tfail "toggle removes"
  "$B" bookmark remove vFJuk4U-V7Q >/dev/null; (( $(jq length "$XDG_CONFIG_HOME/omarchy-zen/bookmarks.json") == 1 )) && tok || tfail "remove"
  ! "$B" bookmark add 'https://evil.example/x' >/dev/null 2>&1 && tok || tfail "bookmark rejects non-video"
  # ratings
  reset; : >"$DZ_LOG"
  "$B" rate vFJuk4U-V7Q 5 >/dev/null || tfail "rate"
  [[ $(jq -r '."vFJuk4U-V7Q".stars' "$XDG_CONFIG_HOME/omarchy-zen/ratings.json") == 5 && $(jq -r '."vFJuk4U-V7Q".synced' "$XDG_CONFIG_HOME/omarchy-zen/ratings.json") == true ]] && tok || tfail "local rating + synced"
  body=$(grep 'rate-body POST' "$DZ_LOG" | head -1 | sed 's/^rate-body POST //'); iid=$(jq -r .install_id <<<"$body")
  [[ $iid =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ && $(jq -r .stars <<<"$body") == 5 && $(jq -r .video_id <<<"$body") == vFJuk4U-V7Q ]] && tok || tfail "POST body: $body"
  [[ $(jq -r .install_id "$XDG_CONFIG_HOME/omarchy-zen/config.json") == "$iid" ]] && tok || tfail "install id kept in config"
  "$B" rate vFJuk4U-V7Q 3 >/dev/null; [[ $(grep -c 'rate-body POST' "$DZ_LOG") == 2 && $(jq -r .install_id "$XDG_CONFIG_HOME/omarchy-zen/config.json") == "$iid" ]] && tok || tfail "same install id on the second rating"
  [[ $(jq -r '."vFJuk4U-V7Q".avg' "$XDG_CACHE_HOME/omarchy-zen/ratings.json") == 4.5 ]] && tok || tfail "the answer updates the community cache"
  out=$("$B" library --json); [[ $(j '.entries[0].my_stars' "$out") == 3 && $(j '.entries[0].avg' "$out") == 4.5 ]] && tok || tfail "library shows my stars and the fresh average"
  ! "$B" rate vFJuk4U-V7Q 9 >/dev/null 2>&1 && tok || tfail "stars 1..5"
  : >"$DZ_LOG"; DZ_OFFLINE=1 "$B" rate LOFI1111111 4 >/dev/null; [[ $(jq -r '."LOFI1111111".synced' "$XDG_CONFIG_HOME/omarchy-zen/ratings.json") == false ]] && tok || tfail "offline rating stays unsynced"
  : >"$DZ_LOG"; "$B" ratings --refresh >/dev/null; grep -q 'LOFI1111111' <(grep 'rate-body POST' "$DZ_LOG") && [[ $(jq -r '."LOFI1111111".synced' "$XDG_CONFIG_HOME/omarchy-zen/ratings.json") == true ]] && tok || tfail "ratings --refresh re-sends pending: $(cat "$DZ_LOG")"
  : >"$DZ_LOG"; "$B" rate vFJuk4U-V7Q 0 >/dev/null; grep -q 'rate-body DELETE' "$DZ_LOG" && [[ $(jq -r '."vFJuk4U-V7Q"' "$XDG_CONFIG_HOME/omarchy-zen/ratings.json") == null ]] && tok || tfail "0 removes"
  "$B" share-ratings off >/dev/null; : >"$DZ_LOG"; "$B" rate vFJuk4U-V7Q 2 >/dev/null; ! grep -q 'rate-body' "$DZ_LOG" && [[ $(jq -r '."vFJuk4U-V7Q".stars' "$XDG_CONFIG_HOME/omarchy-zen/ratings.json") == 2 ]] && tok || tfail "share_ratings off: local only"
  # no API in the catalog
  reset; jq '.ratings_api = ""' "$R/tests/fixtures/catalog.json" >"$T/cat-noapi.json"
  out=$(DZ_CATALOG_FIXTURE="$T/cat-noapi.json" "$B" library --json); [[ $(j .ratings_api_available "$out") == false && $(j '.entries[0].count' "$out") == 0 ]] && tok || tfail "no ratings_api: not available, no fetch"
  # creators
  reset
  out=$("$B" channel list --json); [[ $(j '.[0].id' "$out") == AetherJourneyMusic ]] && tok || tfail "default creator"
  "$B" channel add 'https://www.youtube.com/@LofiGirl' >/dev/null && [[ $(jq -r '.[0].name' "$XDG_CONFIG_HOME/omarchy-zen/channels.json") == "Stub Creator" && $(jq -r '.[0].id' "$XDG_CONFIG_HOME/omarchy-zen/channels.json") == LofiGirl ]] && tok || tfail "channel add"
  ! "$B" channel add 'https://evil.example/@x' >/dev/null 2>&1 && tok || tfail "channel add rejects other hosts"
  : >"$DZ_LOG"; out=$("$B" channel videos AetherJourneyMusic --json)
  [[ $(j 'length' "$out") == 2 && $(j '.[0].id' "$out") == LIVEaaaaaaa && $(j '.[0].live' "$out") == true && $(j '.[1].id' "$out") == VIDbbbbbbbb ]] && tok || tfail "creator videos: streams then uploads, no upcoming: $out"
  grep -q -- '-- https://www.youtube.com/@AetherJourneyMusic/streams' "$DZ_LOG" && tok || tfail "streams tab argv"
  : >"$DZ_LOG"; "$B" channel videos AetherJourneyMusic --json >/dev/null; [[ -z $(grep yt-dlp "$DZ_LOG") ]] && tok || tfail "creator videos cached"
  out=$("$B" library --json --channel AetherJourneyMusic); [[ $(j .kind "$out") == channel && $(j '.entries|length' "$out") == 2 ]] && tok || tfail "library --channel"
  "$B" channel remove LofiGirl >/dev/null; (( $(jq length "$XDG_CONFIG_HOME/omarchy-zen/channels.json") == 0 )) && tok || tfail "channel remove"
  # play
  reset; : >"$DZ_LOG"
  "$B" play LOFI1111111 >/dev/null 2>&1 && [[ $(jq -r .url "$XDG_CONFIG_HOME/omarchy-zen/config.json") == https://www.youtube.com/watch?v=LOFI1111111 ]] && tok || tfail "play a catalog entry"
  (( $(grep -c 'play-body POST' "$DZ_LOG") == 1 )) && grep -q '"video_id":"vFJuk4U-V7Q"' <(grep play-body "$DZ_LOG") && tok || tfail "play reports one play for the resolved video: $(grep play-body "$DZ_LOG")"
  : >"$DZ_LOG"; "$B" resolve --force >/dev/null; ! grep -q play-body "$DZ_LOG" && tok || tfail "resolve never reports plays"
  : >"$DZ_LOG"; "$B" play LOFI1111111 >/dev/null 2>&1; ! grep -q play-body "$DZ_LOG" && tok || tfail "playing the same video again reports nothing (same id)"
  cfgurl='https://www.youtube.com/watch?v=LOFI1111111'; out=$("$B" library --json --category lofi); [[ $(j '.entries[0].playing' "$out") == true ]] && tok || tfail "playing follows the configured url right away"
  "$B" share-ratings off >/dev/null; : >"$DZ_LOG"; "$B" set-url 'https://youtu.be/vFJuk4U-V7Q' >/dev/null 2>&1; ! grep -q play-body "$DZ_LOG" && tok || tfail "share_ratings off: no play reported"
  "$B" share-ratings on >/dev/null
  "$B" play AetherJourneyMusic >/dev/null 2>&1 && [[ $(jq -r .url "$XDG_CONFIG_HOME/omarchy-zen/config.json") == https://www.youtube.com/@AetherJourneyMusic ]] && tok || tfail "play a creator = follow its newest"
  : >"$DZ_LOG"; DZ_FAIL=1 DZ_FAIL_MATCH='v=LIVEzzzzzzz' "$B" play LIVEzzzzzzz >/dev/null 2>&1 && [[ $(jq -r .url "$XDG_CONFIG_HOME/omarchy-zen/config.json") == https://www.youtube.com/@ZenFM ]] && tok || tfail "a gone live entry falls back to its channel: $(jq -r .url "$XDG_CONFIG_HOME/omarchy-zen/config.json")"
  ! "$B" play 'https://evil.example/v' >/dev/null 2>&1 && tok || tfail "play rejects other hosts"
fi

if want position; then
  echo "== position: saved by the engine, handed back by resolve, cleared by set-url"
  reset
  "$B" position save vFJuk4U-V7Q 1234 && [[ $(jq -r .position "$XDG_STATE_HOME/omarchy-zen/position.json") == 1234 ]] && tok || tfail "position save"
  out=$("$B" resolve --json); [[ $(j .resume_position "$out") == 1234 ]] && tok || tfail "resolve returns resume_position: $(j .resume_position "$out")"
  out=$("$B" resolve --json --force); [[ $(j .resume_position "$out") == 1234 ]] && tok || tfail "also after a forced resolve"
  "$B" position save OTHERvideo1 50; out=$("$B" resolve --json); [[ $(j .resume_position "$out") == 0 ]] && tok || tfail "another video: 0"
  "$B" position save vFJuk4U-V7Q 99; "$B" set-url 'https://youtu.be/vFJuk4U-V7Q' >/dev/null 2>&1; [[ ! -f $XDG_STATE_HOME/omarchy-zen/position.json ]] && tok || tfail "set-url clears the position"
  DZ_FIXTURE="$R/tests/fixtures/live.json" "$B" resolve --force >/dev/null; "$B" position save LIVE123 77; out=$("$B" resolve --json); [[ $(j .resume_position "$out") == 0 ]] && tok || tfail "live: never resumes"
  ! "$B" position save bad 1 >/dev/null 2>&1 && tok || tfail "position save validates"
fi

if want api; then
  if curl -fsS --max-time 2 http://127.0.0.1:8787/v1/health >/dev/null 2>&1; then
    echo "== api: the ratings Worker on 127.0.0.1:8787 (wrangler dev --local)"
    A=http://127.0.0.1:8787; iid=$(cat /proc/sys/kernel/random/uuid)
    out=$(/usr/bin/curl -fsS -X POST -H 'content-type: application/json' --data "{\"install_id\":\"$iid\",\"video_id\":\"vFJuk4U-V7Q\",\"stars\":4}" $A/v1/rate) || tfail "POST rate"
    [[ $(j .video_id "$out") == vFJuk4U-V7Q && $(j .count "$out") -ge 1 ]] && tok || tfail "rate answer: $out"
    out=$(/usr/bin/curl -fsS -X POST -H 'content-type: application/json' --data "{\"install_id\":\"$iid\",\"video_id\":\"vFJuk4U-V7Q\",\"stars\":2}" $A/v1/rate); n1=$(j .count "$out")
    out=$(/usr/bin/curl -fsS $A/v1/ratings); [[ $(j '."vFJuk4U-V7Q".count' "$out") == "$n1" ]] && tok || tfail "upsert: one row per install, listed: $out"
    [[ $(/usr/bin/curl -s -o /dev/null -w '%{http_code}' -X POST -H 'content-type: application/json' --data '{"install_id":"nope","video_id":"vFJuk4U-V7Q","stars":4}' $A/v1/rate) == 400 ]] && tok || tfail "bad install id -> 400"
    [[ $(/usr/bin/curl -s -o /dev/null -w '%{http_code}' -X POST -H 'content-type: application/json' --data "{\"install_id\":\"$iid\",\"video_id\":\"vFJuk4U-V7Q\",\"stars\":9}" $A/v1/rate) == 400 ]] && tok || tfail "stars 9 -> 400"
    out=$(/usr/bin/curl -fsS -X DELETE -H 'content-type: application/json' --data "{\"install_id\":\"$iid\",\"video_id\":\"vFJuk4U-V7Q\"}" $A/v1/rate); [[ $(j .count "$out") == $((n1 - 1)) ]] && tok || tfail "DELETE removes: $out"
    p0=$(/usr/bin/curl -fsS $A/v1/ratings | jq -r '."PLAYtest001".plays // 0')
    out=$(/usr/bin/curl -fsS -X POST -H 'content-type: application/json' --data "{\"install_id\":\"$iid\",\"video_id\":\"PLAYtest001\"}" $A/v1/play); [[ $(j .plays "$out") == $((p0 + 1)) ]] && tok || tfail "POST play: $out"
    out=$(/usr/bin/curl -fsS -X POST -H 'content-type: application/json' --data "{\"install_id\":\"$iid\",\"video_id\":\"PLAYtest001\"}" $A/v1/play); [[ $(j .plays "$out") == $((p0 + 1)) ]] && tok || tfail "same install, same day: not counted twice: $out"
    out=$(/usr/bin/curl -fsS $A/v1/ratings); [[ $(j '."PLAYtest001".plays' "$out") == $((p0 + 1)) && $(j '."PLAYtest001".count' "$out") == 0 ]] && tok || tfail "listing carries plays for unrated videos: $(j '."PLAYtest001"' "$out")"
    # the CLI end to end against the real worker
    reset; out=$(OMARCHY_ZEN_RATINGS_API=$A "$B" rate LOFI1111111 5); DZ_SKIP=1
    [[ $(jq -r '."LOFI1111111".synced' "$XDG_CONFIG_HOME/omarchy-zen/ratings.json") == true ]] || tfail "CLI against the worker (curl stub is on PATH, so this needs DZ_TEST_STUBS unset)"
  else
    echo "== api: skipped (start it with: cd api && npx wrangler dev --local)"
  fi
fi

echo; echo "$pass passed, $fails failed"
(( fails == 0 ))

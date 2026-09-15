#!/bin/bash
#
# update.sh — tell the user when a newer version of this plugin is published,
# and help finish the update. The same file ships in every Omarchy.Fans plugin;
# only the block under "this plugin" differs. See docs/update-alerts.md.
#
#   update.sh check [INSTALLED_VERSION] [--force]   is a newer version published? (JSON)
#   update.sh dismiss VERSION                        stop showing the alert for that version
#   update.sh run [all|install]                      open a terminal that updates the plugin
#   update.sh terminal [all|install]                 what that terminal runs (called by `run`)
#
# The check is one small HTTPS GET of the published manifest.json, plus
# CHANGELOG.md when there is something new, cached for six hours in
# ~/.cache/<slug>/update-check.json. Offline it answers from the cache. It sends
# no personal data, only a User-Agent naming this plugin and its version.
# "update_check": false in the plugin's config file turns it off.
#
# Nothing is installed without the user: `run` opens a terminal where
# `omarchy plugin update` shows the changes and asks, then install.sh asks
# again, then (only for plugins with a keepLoaded panel) a shell restart is
# offered. Nothing here pulls with git or overwrites files itself.
#
# Every tool comes from root-owned system folders, never the caller's PATH.
set -uo pipefail
export PATH="/usr/share/omarchy/bin:/usr/local/bin:/usr/bin:/bin"

UPD_SELF="$(readlink -f -- "${BASH_SOURCE[0]}")"
UPD_DIR="$(cd -- "$(dirname -- "$UPD_SELF")/.." && pwd)"

# ---- this plugin -------------------------------------------------------------
UPD_ID="fans.omarchy.zen-wallpaper"
UPD_NAME="Zen Wallpaper"
UPD_REPO="OmarchyFans/Omarchy-Fans-Zen-Wallpaper"            # GitHub owner/repo the plugin is published from
UPD_BRANCH="main"        # branch whose manifest.json is "the published version"
UPD_SLUG="omarchy-zen"            # cache lives in ~/.cache/<slug>/update-check.json
UPD_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-zen/config.json"        # JSON file; "update_check": false turns the check off
UPD_KEEP_LOADED=1   # the wallpaper engine is a service that lives inside the shell: a restart loads the new one
UPD_BUILT_STAMP=""    # file install.sh writes with the version it built for, or empty
# Runs in the update terminal after install.sh. Ask before anything that is not
# free to redo; keep it short.
post_update() {
  # Nothing to restart by hand: the engine is reloaded with the shell below.
  :
}
# ------------------------------------------------------------------------------

UPD_TTL=${OMARCHY_PLUGIN_UPDATE_TTL:-21600}
UPD_RAW="${OMARCHY_PLUGIN_UPDATE_RAW:-https://raw.githubusercontent.com/$UPD_REPO/$UPD_BRANCH}"
UPD_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/$UPD_SLUG/update-check.json"
UPD_INSTALLED="$HOME/.config/omarchy/plugins/$UPD_ID"   # where omarchy plugin add puts it
UPD_REPO_URL="https://github.com/$UPD_REPO"

# ---- versions ---------------------------------------------------------------
# A version as a fixed-width key ("0.3.10" -> 000000000300010) so plain string
# comparison orders versions numerically, in bash and in awk alike.
ver_key() {
  local a b c
  read -r a b c _ <<<"$(printf '%s' "${1:-0}" | tr -c '0-9' ' ')"
  printf '%05d%05d%05d' "$((10#${a:-0}))" "$((10#${b:-0}))" "$((10#${c:-0}))"
}
ver_gt() { [[ $(ver_key "$1") > $(ver_key "$2") ]]; }

manifest_version() { jq -r '.version // ""' "$UPD_DIR/manifest.json" 2>/dev/null || true; }

# Bullets from CHANGELOG.md sections newer than INSTALLED and up to LATEST,
# newest first, at most six. Sections start "## x.y.z"; bullets start "- ".
changelog_notes() { # changelog_notes FILE INSTALLED LATEST
  awk -v inst="$(ver_key "$2")" -v lat="$(ver_key "$3")" '
    function key(s,   n, a) { n = split(s, a, "."); return sprintf("%05d%05d%05d", a[1] + 0, a[2] + 0, a[3] + 0) }
    /^##[ \t]+v?[0-9]+\.[0-9]+/ {
      match($0, /[0-9]+(\.[0-9]+)*/); v = key(substr($0, RSTART, RLENGTH))
      keep = (v "" > inst "" && v "" <= lat ""); next
    }
    keep && /^[ \t]*[-*][ \t]+/ { sub(/^[ \t]*[-*][ \t]+/, ""); print; if (++n >= 6) exit }
  ' "$1"
}

# ---- cache -----------------------------------------------------------------
cache_get() { # cache_get JQ_FILTER
  [[ -f $UPD_CACHE ]] && jq -r "$1" "$UPD_CACHE" 2>/dev/null || true
}
cache_put() { # cache_put JQ_UPDATE [jq args...]
  local filter=$1 tmp; shift
  mkdir -p "$(dirname "$UPD_CACHE")" 2>/dev/null || return 0
  tmp=$(mktemp "$(dirname "$UPD_CACHE")/.update-check.XXXXXX") || return 0
  if { jq . "$UPD_CACHE" 2>/dev/null || echo '{}'; } | jq "$filter" "$@" >"$tmp" 2>/dev/null; then
    mv -f "$tmp" "$UPD_CACHE"
  else
    rm -f "$tmp"
  fi
}

fetch() { # fetch URL -> stdout; fails on any problem, never hangs
  curl -fsS --max-time 5 --max-filesize 200000 -A "$UPD_SLUG/$(manifest_version)" "$1" 2>/dev/null
}

enabled() {
  [[ -f $UPD_CONFIG ]] || return 0
  [[ $(jq -r '.update_check' "$UPD_CONFIG" 2>/dev/null) != false ]]
}

# ---- check -------------------------------------------------------------------
cmd_check() {
  local installed=${1:-} force=0 cli latest="" checked now fresh mismatch=false key notes='[]' stale=false
  [[ ${2:-} == --force || ${1:-} == --force ]] && force=1
  [[ $installed == --force ]] && installed=""
  cli=$(manifest_version)
  [[ -n $installed ]] || installed=$cli
  now=$(date +%s)
  # The window is newer than the files next to this script: the plugin was
  # updated but install.sh (which copies or builds things) was not re-run.
  if [[ -n $installed && -n $cli && $(ver_key "$installed") != "$(ver_key "$cli")" ]]; then mismatch=true; fi
  # The built artifact was made for another version (install.sh writes the stamp).
  if [[ -n $UPD_BUILT_STAMP && -f $UPD_DIR/$UPD_BUILT_STAMP ]] \
     && [[ $(ver_key "$(head -c 64 "$UPD_DIR/$UPD_BUILT_STAMP")") != "$(ver_key "$cli")" ]]; then stale=true; mismatch=true; fi

  local on=true
  if enabled; then
    checked=$(cache_get '.checked // 0 | tonumber? // 0'); [[ $checked =~ ^[0-9]+$ ]] || checked=0
    fresh=$(( now - checked < UPD_TTL ))
    (( fresh && ! force )) && latest=$(cache_get '.latest // ""')
    if [[ -z $latest ]]; then
      latest=$(fetch "$UPD_RAW/manifest.json" | jq -r '.version // ""' 2>/dev/null)
      if [[ -n $latest ]]; then
        cache_put '.checked = ($now|tonumber) | .latest = $latest' --arg now "$now" --arg latest "$latest"
      else
        latest=$(cache_get '.latest // ""')            # offline: the last known answer
      fi
    fi
    if [[ -n $latest ]] && ver_gt "$latest" "$installed" && ver_gt "$latest" "$cli"; then
      key="$installed>$latest"
      if [[ $(cache_get '.notes_for // ""') == "$key" ]]; then
        notes=$(cache_get '.notes // []')
      else
        local tmp; tmp=$(mktemp) || tmp=""
        if [[ -n $tmp ]] && fetch "$UPD_RAW/CHANGELOG.md" >"$tmp"; then
          notes=$(changelog_notes "$tmp" "$installed" "$latest" | jq -R . | jq -s .)
          cache_put '.notes = $notes | .notes_for = $key' --argjson notes "$notes" --arg key "$key"
        fi
        rm -f "$tmp"
      fi
    fi
  else
    on=false
  fi
  [[ -n $latest ]] && ver_gt "$latest" "$installed" && ver_gt "$latest" "$cli" && available=true || available=false
  jq -n --arg panel "$installed" --arg cli "$cli" --arg latest "$latest" --argjson available "$available" \
     --argjson notes "$notes" --argjson mismatch "$mismatch" --argjson stale "$stale" \
     --argjson git "$([[ -d $UPD_DIR/.git ]] && echo true || echo false)" \
     --arg dismissed "$(cache_get '.dismissed // ""')" --arg checked "$(cache_get '.checked // 0')" --argjson enabled "$on" \
     '{panel: $panel, cli: $cli, latest: (if $latest == "" then null else $latest end), update_available: $available,
       notes: $notes, mismatch: $mismatch, artifact_stale: $stale, git_managed: $git,
       dismissed: $dismissed, checked: ($checked | tonumber? // 0), enabled: $enabled}'
}

cmd_dismiss() {
  [[ -n ${1:-} ]] || return 2
  cache_put '.dismissed = $v' --arg v "$1"
}

# ---- run: a floating terminal that finishes the update -----------------------
cmd_run() {
  local step=${1:-all}
  [[ $step == all || $step == install ]] || return 2
  if (( ${OMARCHY_PLUGIN_UPDATE_PRINT:-0} )); then
    jq -n --arg tui "$(command -v omarchy-launch-tui || echo omarchy-launch-tui)" --arg self "$UPD_SELF" --arg step "$step" \
      '{argv: [$tui, "--app-id=TUI.float", "/usr/bin/bash", $self, "terminal", $step]}'
    return 0
  fi
  command -v omarchy-launch-tui >/dev/null || { echo "update.sh: omarchy-launch-tui not found; run by hand: omarchy plugin update $UPD_ID" >&2; return 1; }
  setsid -f omarchy-launch-tui --app-id=TUI.float /usr/bin/bash "$UPD_SELF" terminal "$step" >/dev/null 2>&1 </dev/null
}

hold() { echo; read -rp "$1 Press Enter to close " _; }

cmd_terminal() {
  local step=${1:-all} n=1 total=2
  (( UPD_KEEP_LOADED )) && total=3
  echo "$UPD_NAME update"
  echo
  if ! [[ $UPD_DIR -ef $UPD_INSTALLED ]]; then
    echo "This copy ($UPD_DIR) is not the installed plugin ($UPD_INSTALLED)."
    echo "Update it with git yourself, then run install.sh."
    hold "Nothing was changed."; return 1
  fi
  if [[ $step == all ]]; then
    if [[ -d $UPD_DIR/.git ]]; then
      echo "$n/$total  omarchy plugin update $UPD_ID   (shows the changes and asks first)"
      omarchy plugin update "$UPD_ID" || { hold "The plugin update did not finish."; return 1; }
    else
      echo "This copy was not installed with 'omarchy plugin add', so it cannot update itself."
      echo "Reinstall it from the marketplace:"
      echo "  omarchy plugin remove $UPD_ID && omarchy plugin add $UPD_REPO_URL --enable"
      hold "Nothing was changed."; return 1
    fi
    echo; n=$((n + 1))
  fi
  if [[ -x $UPD_DIR/install.sh ]]; then
    echo "$n/$total  install.sh   (the extras a plugin cannot ship itself; asks first)"
    "$UPD_DIR/install.sh" || { hold "install.sh did not finish."; return 1; }
  else
    echo "$n/$total  Nothing to install: the plugin is its files."
  fi
  echo
  post_update
  if (( UPD_KEEP_LOADED )); then
    read -rp "$total/$total  Restart the Omarchy shell now to load the new version? [Y/n] " ans
    if [[ ! $ans =~ ^[nN] ]]; then sleep 2; setsid -f omarchy restart shell >/dev/null 2>&1 </dev/null; fi
  else
    echo "The bar picks up the new files by itself."
  fi
  echo "Done."
  sleep 2
}

main() {
  case "${1:-}" in
    check)    shift; cmd_check "$@" ;;
    dismiss)  shift; cmd_dismiss "$@" ;;
    run)      shift; cmd_run "$@" ;;
    terminal) shift; cmd_terminal "$@" ;;
    *) sed -n '3,10p' "$UPD_SELF" | sed 's/^# \{0,1\}//'; return 2 ;;
  esac
}
# Everything above is parsed before this line runs, so the file can be replaced
# under us by `omarchy plugin update` without confusing the running terminal.
main "$@"

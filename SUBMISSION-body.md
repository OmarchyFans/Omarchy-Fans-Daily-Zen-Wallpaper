### Repository URL

https://github.com/OmarchyFans/Omarchy-Fans-Zen-Wallpaper

### Category

Appearance

### Tags

wallpaper, theme, youtube, ambient, lofi, aether, bar-widget, service

### Suggest a missing tag

_No response_

### Maintainer notes

Zen Wallpaper is an Omarchy.Fans product written by ModPunk, MIT licensed. What it does: • your wallpaper becomes a live YouTube mood stream (lofi, zen, ambient, jazz, 24/7 radios) playing on the layer-shell bottom layer with sound, or a fresh still frame from it becomes the Omarchy background every day; • many streams to choose from: a curated top 10 per category in catalog.json (built by tools/build-catalog.sh, fetched from main daily), creators to follow, bookmarks, star ratings and play counts shared across installs, or any YouTube link; • one click hands the frame to Aether (Omarchy's bundled theme generator) to build and apply an Omarchy theme; • update alerts in the popup (lib/update.sh, the shared Omarchy.Fans helper). Kinds: service (Service.qml, the engine: one Qt Multimedia player per monitor plus one for audio, inside omarchy-shell) and bar-widget (Widget.qml, the chip and popup). Capabilities the baseline scan will list, all by design: network (yt-dlp resolves the stream and lists a creator's videos, ffmpeg fetches one frame, the engine streams from YouTube, a daily fetch of catalog.json and a six-hourly update check from this repository on GitHub, and optional star ratings and play counts sent as {random install id, video id[, stars]} to the ratings API in api/, opt-out share_ratings=false; a Suno invite link opens the browser only on click); process-spawn (Process/Util.execArgv with fixed argv only, the QML never runs a shell string built from input, the helper pins PATH to root-owned dirs and passes URLs after --); writes-user-config (only ~/.config/omarchy-zen, ~/.local/state/omarchy-zen, ~/.local/share/omarchy-zen/frames and ~/.config/omarchy/themes/<theme_name>; the background is set through the stock omarchy-theme-bg-set); installer (install.sh: optional, asks per step, idempotent, backs up before appending, needs no root; uninstall.sh reverses it). Accepted URLs are https on youtube.com, youtu.be and music.youtube.com only. Dependencies all ship in the Omarchy base packages (yt-dlp, ffmpeg, jq, aether, qt6-multimedia-ffmpeg). tests/run.sh runs offline against stubs; CI runs bash -n, shellcheck, a manifest check and the tests. Note for the baseline: the ratings API (api/worker.js, Cloudflare Worker + D1) is in the repository but not deployed yet; until catalog.json names it, the plugin sends no ratings anywhere.

### Submission checklist

- [x] The repository is public and contains installation and removal instructions
- [x] I have documented the plugin license and any external dependencies
- [x] I own or have permission to submit this plugin and its preview assets
- [x] The plugin does not overwrite user configuration without explicit consent
- [x] I understand approval is for listing and is not a security review

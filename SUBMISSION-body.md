### Repository URL

https://github.com/OmarchyFans/Omarchy-Fans-Daily-Zen-Wallpaper

### Category

Appearance

### Tags

wallpaper, theme, youtube, ambient, aether, bar-widget, service

### Suggest a missing tag

_No response_

### Maintainer notes

Daily Zen Wallpaper plays a long-form YouTube mood stream (lofi, zen, ambient) as the Omarchy wallpaper, with sound, on the layer-shell bottom layer, or sets a fresh still frame from it as the background every day, and can hand that frame to Aether (Omarchy's bundled theme generator) to build and apply an Omarchy theme. Kinds: service (the engine, Service.qml: two Qt Multimedia players inside omarchy-shell) and bar-widget (the chip and popup). Capabilities the baseline scan will list, all by design: network (yt-dlp resolves the stream, ffmpeg fetches one frame, the engine streams from YouTube, a six-hourly update check fetches manifest.json from GitHub, opt-out in the config file), process-spawn (Process/Util.execArgv with fixed argv only; the QML never runs a shell string built from input; the helper pins PATH to root-owned dirs and passes URLs after --), writes-user-config (only ~/.config/omarchy-daily-zen, ~/.local/state/omarchy-daily-zen, ~/.local/share/omarchy-daily-zen/frames and ~/.config/omarchy/themes/<theme_name>; the background is set through the stock omarchy-theme-bg-set), installer (install.sh: optional, asks per step, idempotent, backs up before appending, no sudo; uninstall.sh reverses it). Accepted URLs are https on youtube.com, youtu.be and music.youtube.com only. Dependencies are all in the Omarchy base packages (yt-dlp, ffmpeg, jq, aether, qt6-multimedia-ffmpeg). tests/run.sh runs offline against stubs.

### Submission checklist

- [x] The repository is public and contains installation and removal instructions
- [x] I have documented the plugin license and any external dependencies
- [x] I own or have permission to submit this plugin and its preview assets
- [x] The plugin does not overwrite user configuration without explicit consent
- [x] I understand approval is for listing and is not a security review

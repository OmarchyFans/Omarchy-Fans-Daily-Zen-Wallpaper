# Daily Zen Wallpaper for Omarchy

**Turn a long YouTube mood stream into your Omarchy wallpaper: animated, with
sound, under every window; or a fresh still frame every day; and one click asks
Aether to make an Omarchy theme out of the scene.** Point it at any lofi, zen,
ambient or nature channel and the desktop follows the music.

The default stream is [KUMAMICHI — Japanese Zen Music Along the Bear's Path](https://www.youtube.com/watch?v=vFJuk4U-V7Q)
by Aether Journey. Give it any other YouTube video, live stream, playlist or
channel and it plays that instead (for a channel or playlist, the newest
upload, checked every day).

## Features

- **Animated wallpaper with sound.** The stream plays on the layer under your
  windows, above the stock Omarchy background. Video and audio come straight
  from YouTube through yt-dlp; nothing is downloaded to disk.
- **Still mode.** One frame from the stream becomes your Omarchy background
  (through the stock `omarchy-theme-bg-set`, so the lock screen and the
  picker see it too). A new frame every day, or whenever you press *Grab a still*.
- **Sound without video.** Still mode keeps the music playing if you want it.
- **Themes with Aether.** *Make a theme with Aether* hands the current still to
  [Aether](https://github.com/omacom/aether), Omarchy's bundled theme generator,
  and applies the result as the Omarchy theme `daily-zen`. Turn on *Daily theme*
  and the palette follows the picture every day.
- **Bar chip.** Left click opens the popup (mode, sound, volume, quality, the
  stream URL, daily options). Middle click flips animated and still. Scroll
  changes the volume.
- **Stays out of the way.** Video decoding pauses while a fullscreen window
  covers the wallpaper (the music keeps playing); the video is capped at 720p
  by default (480p and 1080p are a click away).
- **Update alerts.** The popup tells you when a newer version is published and
  what changed.

## How it works

Enable the plugin and the engine (a `service` plugin inside `omarchy-shell`)
reads `~/.config/omarchy-daily-zen/config.json`, asks `omarchy-daily-zen resolve`
for the stream, and plays it in a layer-shell window on the *bottom* layer.
Two Qt Multimedia players run: one for the 720p HLS video rendition (no audio
output), one for the audio rendition, so "still + sound" and "animated, muted"
are just which one runs. YouTube URLs expire after a few hours and a 6-hour
video ends: the engine re-resolves and carries on. Once an hour it runs
`omarchy-daily-zen daily`, which does nothing until a day has passed.

Everything that touches the network or the disk is in `bin/omarchy-daily-zen`:
`resolve` (yt-dlp), `still` (ffmpeg grabs one frame), `theme` (Aether), `daily`.
The chip and the engine only ever call it with fixed arguments.

## Install

```bash
omarchy plugin add https://github.com/OmarchyFans/Omarchy-Fans-Daily-Zen-Wallpaper --enable
~/.config/omarchy/plugins/fans.omarchy.daily-zen-wallpaper/install.sh
```

`install.sh` asks, step by step, whether to symlink `omarchy-daily-zen` into
`~/.local/bin`, bind `SUPER + ALT + Z` to flip animated/still, and grab a first
still. Every step is optional and idempotent; config files are backed up before
they are appended to; nothing runs with sudo.

`--enable` puts the chip in the right section of the bar (move it with
`omarchy bar move`) and starts the engine with it: the default stream begins
playing with sound at 35 % right away, and within the first minute the daily
refresh saves a still and makes it the Omarchy background. Switch to *Still*
or *Off* in the popup if you only wanted the picture. If the chip is missing,
run `omarchy plugin enable fans.omarchy.daily-zen-wallpaper` or use Setup > Plugins.

### Dependencies

All part of the Omarchy base install: `yt-dlp`, `ffmpeg`, `jq`, `aether`,
`qt6-multimedia-ffmpeg` (Quickshell's video playback). Omarchy 4 with
`omarchy-shell` is required; the plugin draws with the shell's own Quickshell.

## Remove

```bash
~/.config/omarchy/plugins/fans.omarchy.daily-zen-wallpaper/uninstall.sh   # add --purge to delete frames, the theme and settings
omarchy plugin remove fans.omarchy.daily-zen-wallpaper
```

`uninstall.sh` removes the symlink and the keybinding and, if a still frame is
the current background, goes back to the theme's own picture. Your still
frames, the `daily-zen` theme and the settings stay unless you pass `--purge`.
To stop using the generated theme, pick another one in the theme switcher.

## Commands

```
omarchy-daily-zen status [--json]          what is playing, the last still, the daily stamp
omarchy-daily-zen set-url URL              use another YouTube video, live stream, playlist or channel
omarchy-daily-zen mode animated|still|off
omarchy-daily-zen sound on|off             volume 0..1 | quality 480|720|1080
omarchy-daily-zen toggle-mode              animated <-> still (for a keybinding)
omarchy-daily-zen pause | resume
omarchy-daily-zen still [--at SEC] [--no-set]        one frame -> Omarchy background
omarchy-daily-zen theme [--frame PATH] [--light] [--no-apply]   Aether palette -> Omarchy theme
omarchy-daily-zen daily [--force]          the daily refresh
omarchy-daily-zen daily-refresh on|off | daily-theme on|off | fullscreen-pause on|off
omarchy-daily-zen open                     the current video in the browser
```

Settings live in `~/.config/omarchy-daily-zen/config.json` (the helper writes
it, the engine watches it); `screen` names the monitor to draw on (empty =
the first one; the video plays on one monitor). Still frames are kept in
`~/.local/share/omarchy-daily-zen/frames/` (the newest twelve). The Aether
theme is `~/.config/omarchy/themes/daily-zen/` (`theme_name` in the config):
only `colors.toml` and the frame are copied there, so Omarchy 4 renders every
other file from its own templates.

## What leaves your machine

- yt-dlp asks YouTube for the stream (the video page and its formats), and the
  engine streams video and audio from YouTube's servers while it plays.
- ffmpeg fetches one frame for a still.
- Once every six hours the update check fetches this plugin's `manifest.json`
  (and `CHANGELOG.md` when there is something new) from GitHub. It sends no
  personal data; `"update_check": false` in the config file turns it off.

Nothing else. Only `https://` links on `youtube.com`, `youtu.be` and
`music.youtube.com` are accepted, and they are passed to yt-dlp after `--`,
never through a shell.

## Updates

The popup shows a banner when a newer version is published, with the changelog
bullets, and *Update…* opens a terminal where `omarchy plugin update` shows the
diff and asks, `install.sh` asks, and a shell restart loads the new engine. By
hand: `omarchy plugin update fans.omarchy.daily-zen-wallpaper`, then
`omarchy restart shell`. Details in [docs/update-alerts.md](docs/update-alerts.md).

## Good to know

- The animated wallpaper plays on one monitor (the first, or `screen` in the
  config). Other monitors keep the stock background.
- Video decoding costs battery. Still mode with sound is the frugal option;
  fullscreen windows pause the video automatically.
- The window shows black for a moment while the first frames buffer after a
  (re)start of the stream.
- Applying a theme restarts terminals and retints apps, as any Omarchy theme
  change does. That is why *Make a theme* is a button and *Daily theme* is off
  by default.
- Double-click on the animated wallpaper opens the background picker, right
  double-click the theme switcher, like the stock background.

## Development

```bash
tests/run.sh                 # offline: stubs for yt-dlp, ffmpeg, aether and omarchy-*, temp HOME
omarchy plugin validate .
```

Develop in a clone, not in `~/.config/omarchy/plugins` (the shell hot-reloads
on every saved file). Layout:

```
manifest.json        kinds: service (engine) + bar-widget (chip)
Service.qml          the engine: layer window, two MediaPlayers, expiry/loop, daily timer, IPC "daily-zen"
Widget.qml           the bar chip and popup
bin/omarchy-daily-zen   resolve / still / theme / daily / settings (bash + jq)
lib/update.sh        update alerts (shared across Omarchy.Fans plugins)
install.sh uninstall.sh
tests/run.sh         offline tests; tests/stubs, tests/fixtures
docs/update-alerts.md
```

MIT.

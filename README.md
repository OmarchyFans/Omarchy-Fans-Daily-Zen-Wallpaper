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
  changes the volume. The icon is a pause sign while the stream plays and a
  play sign while it is paused, a picture in still mode.
- **Stays out of the way.** Video decoding pauses while a fullscreen window
  covers the wallpaper (the music keeps playing); the video is capped at 720p
  by default (480p and 1080p are a click away).
- **Library.** The ten most popular long streams in each category: lofi, work,
  study, focus, zen, ambient and nature, jazz, sleep, classical, synthwave and
  24/7 streams. Built from YouTube searches by `tools/build-catalog.sh` and
  refreshed from this repository's main branch once a day, so the list stays
  current without a plugin update. Aether Journey's bear path stays first in Zen.
- **Creators.** Follow YouTube channels (Aether Journey is in from the start):
  the selector lists a creator's latest streams and uploads, and *Play this
  creator* makes their newest upload the wallpaper, rechecked every day.
- **Bookmarks, ratings and play counts.** Flag any entry, give it one to five
  stars. Stars and plays (one per install and day) are shared with every
  install through a small API, so each row shows everyone's average, how many
  installs played it, and the YouTube views or live viewers as of the catalog
  build. The selector counts your bookmarks per category and per creator.
  `omarchy-daily-zen share-ratings off` keeps stars and plays on this machine.
- **Picks up where it left off.** The engine saves the playback position every
  30 seconds; after a shell restart or a reboot the same video resumes there.
- **Update alerts.** The popup tells you when a newer version is published and
  what changed.

## How it works

Enable the plugin and the engine (a `service` plugin inside `omarchy-shell`)
reads `~/.config/omarchy-daily-zen/config.json`, asks `omarchy-daily-zen resolve`
for the stream, and plays it in a layer-shell window per monitor on the
*bottom* layer, shown only once the first frame is decoded. Each window's Qt
Multimedia player decodes the 720p HLS video rendition (no audio output), and
one more player plays the audio rendition, so "still + sound" and "animated,
muted" are just which players run. YouTube URLs expire after a few hours and a 6-hour
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
omarchy-daily-zen library [--json] [--category ID | --channel ID | --bookmarks] [--refresh]
omarchy-daily-zen play ID|URL|CREATOR      play a library entry, any YouTube video, or a creator's newest
omarchy-daily-zen bookmark [list|add [ID]|remove ID|toggle [ID]]
omarchy-daily-zen rate ID 1..5             0 removes; shared unless share-ratings off
omarchy-daily-zen ratings [--refresh]      everyone's averages
omarchy-daily-zen channel [list|add URL|remove ID|videos ID]
omarchy-daily-zen catalog [--refresh]      the curated list
omarchy-daily-zen position                 where the stream is (saved every 30 s)
```

Settings live in `~/.config/omarchy-daily-zen/config.json` (the helper writes
it, the engine watches it); `screen` names one monitor to draw on (empty =
every monitor; each one decodes the video itself). Still frames are kept in
`~/.local/share/omarchy-daily-zen/frames/` (the newest twelve). The Aether
theme is `~/.config/omarchy/themes/daily-zen/` (`theme_name` in the config):
only `colors.toml` and the frame are copied there, so Omarchy 4 renders every
other file from its own templates.

## What leaves your machine

- yt-dlp asks YouTube for the stream (the video page and its formats), for a
  creator's latest videos, and for the title of a bookmarked video it does not
  know; the engine streams video and audio from YouTube's servers while it plays.
- ffmpeg fetches one frame for a still.
- Once a day the catalog (`catalog.json`) is fetched from this repository's
  main branch on GitHub.
- A rating sends three things to the ratings API named in the catalog: a
  random install id made on first use (no account, no name), the video id and
  the stars. Switching to another video sends the install id and the video id
  once (the API counts one play per install, video and day). Averages and
  play counts are fetched once an hour. `omarchy-daily-zen share-ratings off`
  keeps both local. The API (`api/`) stores only those rows and counts
  requests per IP for a minute to cap writes; no names, accounts or IPs.
- The Suno link at the top of the popup opens the author's invite page in your
  browser only when you click it.
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

## Ratings API

`api/worker.js` is a Cloudflare Worker over D1 (`api/schema.sql`: `ratings`,
`plays`, a per-IP minute counter). Deployed by
`.github/workflows/deploy-api.yml` once the repository has the secrets
`CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`; the workflow creates the
database on first run. The worker URL goes into `catalog.json` as
`ratings_api`, which every install picks up within a day. Until then the
library says community ratings are not available and stars stay local (they
are sent later, on the next `ratings --refresh` or daily refresh).

## Good to know

- Every monitor plays the video and decodes it separately; on a laptop with
  an external display, set `"screen": "eDP-1"` (or the other name from
  `hyprctl monitors`) in the config to keep it to one.
- Video decoding costs battery. Still mode with sound is the frugal option;
  fullscreen windows pause the video automatically.
- While the stream (re)starts and buffers, the stock Omarchy background shows
  for a moment; the video fades in with its first decoded frame.
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
catalog.json         the curated library (tools/build-catalog.sh rebuilds it)
api/                 the ratings Worker (Cloudflare, D1) and its deploy workflow
tests/run.sh         offline tests; tests/stubs, tests/fixtures; `tests/run.sh api` against wrangler dev
docs/update-alerts.md
```

MIT.

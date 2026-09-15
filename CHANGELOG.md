# Changelog

The bar popup reads the newest sections of this file to tell you what changed
when an update is available. Keep one short line per bullet.

## 0.2.0

- Library: the ten most popular long streams per category (lofi, work, study, focus, zen, ambient, jazz, sleep, classical, synthwave, 24/7 streams), refreshed from the main branch daily
- Creators: follow YouTube channels (Aether Journey is in from the start); play a creator to get their newest stream every day
- Bookmarks and 1–5 star ratings on every entry; ratings are shared with every install through the omarchy.fans ratings API
- The stream resumes where it left off after a shell restart or a reboot
- "Make your own music with Suno" link at the top of the popup

## 0.1.1

- The animated wallpaper plays on every monitor (set `screen` in the config to keep it to one)
- No black screen while the stream buffers: the window appears with the first decoded frame
- The music keeps playing behind fullscreen windows; only the video pauses
- The quality dropdown follows changes made from the command line

## 0.1.0

- Animated wallpaper from a YouTube mood stream, with sound, on the layer under your windows
- Still mode: a fresh frame from the stream becomes your Omarchy background every day
- "Make a theme": Aether extracts a palette from the current scene and applies it as an Omarchy theme
- Bar chip with mode, sound, volume, quality and daily options; `omarchy-daily-zen` command line
- Update alerts in the popup when a newer version is published

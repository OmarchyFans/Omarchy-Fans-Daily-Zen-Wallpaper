-- Daily Zen Wallpaper community ratings. One row per install and video.
CREATE TABLE IF NOT EXISTS ratings (
  install_id TEXT NOT NULL,
  video_id   TEXT NOT NULL,
  stars      INTEGER NOT NULL CHECK (stars BETWEEN 1 AND 5),
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (install_id, video_id)
);
CREATE INDEX IF NOT EXISTS ratings_video ON ratings (video_id);
-- Per-IP write budget (60 per minute window).
CREATE TABLE IF NOT EXISTS budget (
  ip     TEXT PRIMARY KEY,
  win    INTEGER NOT NULL,
  n      INTEGER NOT NULL
);

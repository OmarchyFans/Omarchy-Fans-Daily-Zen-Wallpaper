# Update alerts

Every Omarchy.Fans plugin tells its users when a newer version is published,
shows what changed, and walks them through the update. Omarchy has no plugin
update notifications of its own and the marketplace does not notify installers,
so without this people only learn about a new version by running
`omarchy plugin update` on a hunch. This file is the standard; new plugins get
it from day one, and every release keeps it working.

The reference implementation is Omarchy Help 0.3.1
(<https://github.com/OmarchyFans/omarchy-fans-help>, PR #4). This plugin's copy
is described at the end.

## How it works

**The version lives in three places, bumped together every release.**
`manifest.json` `version`; a `VERSION` constant in the helper if the helper has
one (helpers that read `manifest.json` at run time count); and a `## x.y.z`
section at the top of `CHANGELOG.md` with one short bullet per user-visible
change. The banner shows those bullets, so write them for users, not for git.

**The check.** When the window or panel opens (or, for a bar-only widget, when
it loads and every six hours), the widget asks the helper for
`check <its own version>`. The helper:

- fetches `https://raw.githubusercontent.com/OmarchyFans/<repo>/<branch>/manifest.json`
  (about 5 s timeout, 200 KB cap, User-Agent `<plugin>/<version>`)
- compares versions as integer tuples
- if newer, fetches `CHANGELOG.md` and keeps only the bullets from sections
  newer than the installed version (at most six)
- caches the answer in `~/.cache/<plugin>/update-check.json` for six hours, so
  repeated and offline starts are instant
- on a network failure answers from the cache
- prints JSON: `panel`, `cli`, `latest`, `update_available`, `notes`,
  `mismatch`, `artifact_stale`, `git_managed`, `dismissed`, `checked`, `enabled`

**The banner** sits above the main content (or in a small popup on a bar-only
widget, marked by a dot on the icon) and shows three things: "<Plugin> x.y.z is
available (you have a.b.c)", up to four changelog bullets, and one line saying
what *Update* will do. Two buttons:

- **Update…** opens a floating terminal (`omarchy-launch-tui --app-id=TUI.float`)
  that runs `omarchy plugin update <id>` (the stock command: it shows the diff
  and asks), then the plugin's `install.sh` if it has one (asks again), then the
  plugin's own post-update step, then offers `omarchy restart shell` when the
  plugin has a keepLoaded panel. If the plugin folder has no `.git` (a hand
  copy) it prints the reinstall steps instead.
- **Later** records the dismissed version, so that version is never offered
  again. The next version is.

**The mismatch case** matters for plugins whose install step copies or builds
something from the plugin folder: helpers copied into `~/.local/bin`, a binary
built from source. `omarchy plugin update` refreshes the plugin files but not
those, so the window can end up newer than what it runs. The helper reports
`mismatch` when the widget's version differs from the helper's, or when the
build stamp `install.sh` wrote names another version; the widget then shows
**Finish update…**, which runs `install.sh` directly. A helper too old to know
the `check` command exits non-zero; treat that as a mismatch too.

**Opt-out:** `"update_check": false` in the plugin's config file (named below)
turns the check off. Bar widgets also honour `"update_check": false` in their
`shell.json` layout entry.

## Why it is built this way

- **Updates reuse the stock path.** `omarchy plugin update` keeps the checkout
  exactly what the marketplace expects: a fast-forward of the published branch.
  Never `git pull` or overwrite files yourself.
- **Consent at every step.** Nothing installs or restarts without the user
  saying so in the terminal; the widget never runs the update itself.
- **Cheap and private.** One small request every few hours, no personal data,
  cached. The only thing sent is the User-Agent.
- **Changelog-driven notes** tell users what is new, which is the point of the
  alert, not just that a version exists.

## Adapting it per plugin kind

- **Plugins with a helper** (bash, Python) expose `update-check`,
  `update-dismiss` and `update-run` there, delegating to `lib/update.sh`. All
  network code lives in the helper, never in QML.
- **Panels** (a window): the banner is the first item above the content; the
  check runs on open.
- **Bar-only widgets** (no popup of their own): `lib/update.sh` is the helper.
  The widget reads its own `manifest.json` for the version, runs the check on
  load and every six hours, shows a dot on the icon when something is pending,
  and a click opens a small popup with the notes and the buttons (plus the
  widget's normal action, so nothing is blocked). Once dismissed the click goes
  back to normal.
- **Match the plugin's look:** `Color.*` and `Style.*` from `qs.Commons`, never
  hard-coded colours or sizes.
- **Never resolve executables on PATH from QML.** Run
  `/usr/bin/bash <pluginDir>/lib/update.sh …` with a fixed argv and a fixed
  `PATH` environment; the helper itself pins `PATH` to root-owned folders.
- **Not a shell plugin** (a browser extension, a website, a service): out of
  scope for this pattern.

## Rules for the work

- Commits in Omarchy.Fans repos are authored `modpunk
  <27315771+modpunk@users.noreply.github.com>`, with no `Co-Authored-By` or
  `Claude-Session` trailers. Merge PRs with `gh pr merge --rebase` so the
  author survives.
- Never copy into `~/.config/omarchy/plugins/<id>` on every commit: the shell
  hot-reloads on any file change and the desktop flashes. Deploy once per
  finished version, tell the user first, and restart the shell after deploying
  a keepLoaded panel (not within a second of writing the files).
- Test the banner without touching the installed plugin: load the QML in a
  throwaway `quickshell -p <dir>/shell.qml` with `Commons` and `Ui` symlinked
  from `/usr/share/omarchy/shell`, fake a newer version by writing the cache
  file with `"latest": "9.9.9"` and `"checked"` set to now, and test the
  mismatch case against an older helper or artifact. Point
  `OMARCHY_PLUGIN_UPDATE_RAW` at a `file://` folder to test the fetch offline.
- A network fetch changes the marketplace security baseline. When a listed
  plugin gains this, open a "Plugin verification" issue ("Verify and publish a
  newer upstream commit", the listed repo URL, the full SHA) and add a short
  maintainer note explaining the fetch: what URL, how often, no personal data,
  the opt-out. For a pending submission, post the same note on the submission.

## Helper interface

```
lib/update.sh check [INSTALLED_VERSION] [--force]   JSON, see above
lib/update.sh dismiss VERSION                        hide the alert for that version
lib/update.sh run [all|install]                      open the update terminal
lib/update.sh terminal [all|install]                 what that terminal runs
```

Environment for tests: `OMARCHY_PLUGIN_UPDATE_RAW` (base URL, `file://` works),
`OMARCHY_PLUGIN_UPDATE_TTL` (seconds), `OMARCHY_PLUGIN_UPDATE_PRINT=1` makes
`run` print the argv instead of opening a terminal. `XDG_CACHE_HOME` and
`XDG_CONFIG_HOME` move the cache and config.

## In this plugin

- Kind: service (`Service.qml`, the engine) plus a bar widget with a popup (`Widget.qml`); helper `bin/omarchy-daily-zen` (bash).
- Helper commands: `omarchy-daily-zen update-check [VERSION] [--force]`, `update-dismiss VERSION`, `update-run [all|install]`, all delegating to `lib/update.sh`.
- Version places: `manifest.json` (the helper reads it at run time), `CHANGELOG.md`.
- Cache: `~/.cache/omarchy-daily-zen/update-check.json`. Opt-out: `"update_check": false` in `~/.config/omarchy-daily-zen/config.json`, or the chip's `update_check` setting in shell.json.
- `UPD_KEEP_LOADED=1`: the engine is a service that lives inside the shell, so the update terminal offers `omarchy restart shell` as its last step. No other post-update step.
- No mismatch case: `install.sh` symlinks the helper, so the plugin folder is the only copy.
- Tests: `tests/run.sh update` runs the check against `file://` fixtures in `tests/fixtures/published`.

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtMultimedia

// Daily Zen Wallpaper engine (kind: service). Lives inside omarchy-shell for as
// long as the plugin is enabled.
//
// One layer-shell window per monitor on the Bottom layer: above the stock
// Omarchy background, under every window. Each window decodes the video
// itself (Qt's MediaPlayer feeds one VideoOutput), so the config's `screen`
// can restrict playback to one monitor to save battery. A window only shows
// once its first frame is decoded, so a (re)start of the stream reveals the
// stock wallpaper, never a black screen. Audio is one extra MediaPlayer on
// YouTube's audio rendition, so "still + sound" and "animated, muted" are
// just which players run.
//
// The helper writes ~/.config/omarchy-daily-zen/config.json; this file watches
// it and reacts. YouTube URLs expire after a few hours and a 6-hour video
// ends: both re-resolve and carry on (at the same position on expiry, from the
// start on end of media). Once an hour it runs the daily refresh, which does
// nothing until 24 hours have passed.
//
// IPC target "daily-zen": reload, refresh, pause, resume, status (JSON).
Item {
  id: root

  readonly property string cli: Qt.resolvedUrl("bin/omarchy-daily-zen").toString().replace(/^file:\/\//, "")
  readonly property string home: Quickshell.env("HOME")
  readonly property string configPath: (Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")) + "/omarchy-daily-zen/config.json"
  readonly property var cliEnv: ({ PATH: "/usr/share/omarchy/bin:/usr/local/bin:/usr/bin:/bin" })

  property var config: ({})
  property var stream: null
  property string mode: "off"
  property bool sound: true
  property real volume: 0.35
  property bool pauseWhenFullscreen: true
  property string screenName: ""
  property bool fullscreen: false
  property bool paused: false
  property string state: "idle"     // idle | resolving | playing | paused | paused-fullscreen | error | off
  property string error: ""
  property int retries: 0
  property double savedPosition: 0
  property double resumeAt: 0
  property string resolveReason: ""
  property bool configLoaded: false

  readonly property bool covered: pauseWhenFullscreen && fullscreen
  readonly property bool wantVideo: mode === "animated" && !paused && !covered
  // Audio keeps playing behind a fullscreen window: the music is the point, only the picture is hidden.
  readonly property bool wantAudio: mode !== "off" && sound && !paused
  readonly property bool needStream: mode === "animated" || (mode === "still" && sound)

  // ---- config -----------------------------------------------------------------
  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyConfig(text())
    onLoadFailed: function(err) { root.applyConfig("") }
  }
  // The helper replaces the file (write + rename), which a watch can miss.
  Timer { interval: 5000; running: true; repeat: true; onTriggered: configFile.reload() }

  function applyConfig(raw) {
    var c = {}
    try { c = raw ? JSON.parse(raw) : {} } catch (e) { c = {} }
    config = c
    mode = (c.mode === "still" || c.mode === "off") ? c.mode : "animated"
    sound = c.sound !== false
    volume = (typeof c.volume === "number") ? Math.max(0, Math.min(1, c.volume)) : 0.35
    pauseWhenFullscreen = c.pause_when_fullscreen !== false
    screenName = typeof c.screen === "string" ? c.screen : ""
    configLoaded = true
    var url = String(c.url || "")
    var quality = Number(c.quality || 720)
    var stale = stream && ((url && stream.source_url !== url) || (stream.quality !== quality))
    if (stale) { stream = null; audio.stop(); audio.source = "" }
    if (needStream && !stream) resolve(false, "start")
    syncSoon.restart()
  }

  // ---- resolve ----------------------------------------------------------------
  Process {
    id: resolveProc
    environment: root.cliEnv
    stdout: StdioCollector { id: resolveOut; waitForEnd: true }
    stderr: StdioCollector { id: resolveErr; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) {
        var lines = String(resolveErr.text || "").trim().split("\n")
        root.fail(lines[lines.length - 1] || ("resolve exited " + code))
        return
      }
      var s = null
      try { s = JSON.parse(resolveOut.text) } catch (e) { s = null }
      if (!s || !s.video_url) { root.fail("no playable stream"); return }
      root.retries = 0
      root.error = ""
      // The daily refresh re-resolved the same video: keep playing, the URLs in
      // use are still good and the next expiry swap picks up the new ones.
      if (root.resolveReason === "refresh" && root.stream && root.stream.video_id === s.video_id && root.anyPlaying()) {
        root.stream = Object.assign({}, s, { video_url: root.stream.video_url, audio_url: root.stream.audio_url, expires: root.stream.expires })
        syncSoon.restart()
        return
      }
      // A new source: the windows reload from the binding on stream.video_url,
      // the audio player from syncPlayers. Pending seeks apply on load.
      // At startup (a shell restart, a reboot) the helper hands back where the
      // same video was last saved, so the stream carries on from there.
      if ((root.resolveReason === "start" || root.resolveReason === "retry") && Number(s.resume_position || 0) > 5 && !s.is_live)
        root.resumeAt = Number(s.resume_position) * 1000
      root.stream = s
      resumeClear.restart()
      syncSoon.restart()
    }
  }
  function resolve(force, reason) {
    if (resolveProc.running) return
    resolveReason = reason || ""
    state = "resolving"
    var argv = ["/usr/bin/bash", root.cli, "resolve", "--json"]
    if (force) argv.push("--force")
    resolveProc.command = argv
    resolveProc.running = true
  }
  function fail(message) {
    error = message
    state = "error"
    retries += 1
    retryTimer.interval = Math.min(600000, 30000 * Math.pow(2, Math.min(retries - 1, 5)))
    retryTimer.restart()
  }
  Timer { id: retryTimer; repeat: false; onTriggered: if (root.needStream) root.resolve(true, "retry") }
  // A pending resume position is for the load right after a swap, not for a
  // later mode change.
  Timer { id: resumeClear; interval: 45000; repeat: false; onTriggered: root.resumeAt = 0 }

  // ---- playback ---------------------------------------------------------------
  function videoPlayers() {
    var out = []
    var inst = screens.instances
    for (var i = 0; i < inst.length; i++) if (inst[i] && inst[i].player) out.push(inst[i].player)
    return out
  }
  function leadVideo() {
    var inst = screens.instances
    for (var i = 0; i < inst.length; i++) if (inst[i] && inst[i].wanted) return inst[i].player
    return null
  }
  function anyPlaying() {
    if (audio.playbackState === MediaPlayer.PlayingState) return true
    var ps = videoPlayers()
    for (var i = 0; i < ps.length; i++) if (ps[i].playbackState === MediaPlayer.PlayingState) return true
    return false
  }
  Timer { id: syncSoon; interval: 60; repeat: false; onTriggered: root.syncPlayers() }
  onWantVideoChanged: syncSoon.restart()
  onWantAudioChanged: syncSoon.restart()
  onNeedStreamChanged: { if (needStream && !stream && configLoaded) resolve(false, "start"); syncSoon.restart() }

  function syncPlayers() {
    if (!stream) {
      if (!needStream) { audio.stop(); audio.source = ""; state = mode === "off" ? "off" : "idle" }
      return
    }
    // video: every window decides its source from the binding; here play/pause
    var ps = videoPlayers()
    for (var i = 0; i < ps.length; i++) {
      var p = ps[i]
      if (String(p.source) === "") continue
      if (wantVideo) { if (p.playbackState !== MediaPlayer.PlayingState && p.mediaStatus >= MediaPlayer.LoadedMedia) p.play() }
      else if (p.playbackState === MediaPlayer.PlayingState) p.pause()
    }
    // audio: whenever sound is on and the mode is not off
    if (mode !== "off" && sound && stream.audio_url) {
      if (String(audio.source) !== stream.audio_url) audio.source = stream.audio_url
      if (wantAudio) { if (audio.playbackState !== MediaPlayer.PlayingState) audio.play() }
      else if (audio.playbackState === MediaPlayer.PlayingState) audio.pause()
    } else if (String(audio.source) !== "") {
      audio.stop(); audio.source = ""
    }
    if (mode === "off") state = "off"
    else if (paused) state = "paused"
    else if (covered && mode === "animated") state = "paused-fullscreen"
    else if (!needStream) state = "idle"
    else state = "playing"
  }

  function seekIfPending(player) {
    if (resumeAt <= 0 || (stream && stream.is_live)) return
    if (player.seekable) player.position = resumeAt
  }
  function endOfMedia() {
    // Loop the stream. Re-resolve: after six hours the URLs are past their expiry.
    if (resolveProc.running) return
    savedPosition = 0
    resumeAt = 0
    resolve(true, "loop")
  }
  function playerError(which, message) {
    if (resolveProc.running) return
    resumeAt = savedPosition
    fail(which + ": " + message)
  }
  function onVideoLoaded(player) {
    seekIfPending(player)
    if (wantVideo) player.play()
    if (audio.mediaStatus >= MediaPlayer.LoadedMedia && audio.playbackState === MediaPlayer.PlayingState && player.position > 2000 && audio.seekable) audio.position = player.position
  }

  MediaPlayer {
    id: audio
    audioOutput: AudioOutput { volume: root.volume }
    onMediaStatusChanged: {
      if (mediaStatus === MediaPlayer.EndOfMedia && root.mode !== "animated") root.endOfMedia()
      else if (mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia) {
        var lead = root.leadVideo()
        if (root.mode !== "animated" || !lead) root.seekIfPending(audio)
        else if (lead.position > 2000 && audio.seekable) audio.position = lead.position
      }
    }
    onErrorOccurred: function(err, message) { root.playerError("audio", message) }
  }

  // Position bookkeeping, URL expiry and audio/video drift, once a minute.
  Timer {
    interval: 60000; repeat: true
    running: root.stream !== null && root.needStream
    onTriggered: {
      var lead = root.mode === "animated" ? root.leadVideo() : audio
      if (lead && lead.position > 0) root.savedPosition = lead.position
      var nowSec = Date.now() / 1000
      if (root.stream.expires && nowSec > root.stream.expires - 240 && !resolveProc.running) {
        root.resumeAt = root.savedPosition
        root.resolve(true, "expiry")
        return
      }
      if (root.wantVideo && root.wantAudio && !root.stream.is_live && lead && lead !== audio
          && lead.playbackState === MediaPlayer.PlayingState && audio.playbackState === MediaPlayer.PlayingState
          && Math.abs(audio.position - lead.position) > 2500 && audio.seekable) {
        audio.position = lead.position
      }
      // Other monitors follow the lead window.
      var ps = root.videoPlayers()
      for (var i = 0; i < ps.length; i++) {
        var p = ps[i]
        if (p !== lead && lead && lead !== audio && p.playbackState === MediaPlayer.PlayingState && Math.abs(p.position - lead.position) > 2500 && p.seekable) p.position = lead.position
      }
    }
  }
  Timer { interval: 10000; repeat: true; running: root.state === "playing"; onTriggered: {
    var lead = root.mode === "animated" ? root.leadVideo() : audio
    if (lead && lead.position > 0) root.savedPosition = lead.position
  } }
  // Remember where the stream is, so a shell restart or a reboot resumes there.
  Process {
    id: positionProc
    environment: root.cliEnv
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
  }
  Timer { interval: 30000; repeat: true; running: root.state === "playing" && root.stream !== null && !root.stream.is_live; onTriggered: {
    if (positionProc.running || root.savedPosition <= 0 || !root.stream) return
    positionProc.command = ["/usr/bin/bash", root.cli, "position", "save", String(root.stream.video_id), String(Math.floor(root.savedPosition / 1000))]
    positionProc.running = true
  } }

  // ---- fullscreen -------------------------------------------------------------
  // A fullscreen window covers the wallpaper completely: no point decoding.
  // Hyprland's event nudges an immediate check; the poll catches workspace switches.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var n = String(event.name || "")
      if (n === "fullscreen" || n === "workspace" || n === "focusedmon" || n === "activewindow" || n === "closewindow") fullscreenProc.check()
    }
  }
  Process {
    id: fullscreenProc
    command: ["/usr/bin/hyprctl", "activewindow", "-j"]
    environment: root.cliEnv
    stdout: StdioCollector { id: fsOut; waitForEnd: true }
    function check() { if (!running && root.pauseWhenFullscreen && root.mode === "animated") running = true }
    onExited: function(code) {
      var fs = false
      try { var w = JSON.parse(fsOut.text); fs = !!w && Number(w.fullscreen || 0) > 0 } catch (e) { fs = false }
      root.fullscreen = fs
    }
  }
  Timer { interval: 4000; repeat: true; running: root.pauseWhenFullscreen && root.mode === "animated"; triggeredOnStart: true; onTriggered: fullscreenProc.check() }
  onPauseWhenFullscreenChanged: if (!pauseWhenFullscreen) fullscreen = false

  // ---- daily ------------------------------------------------------------------
  Process {
    id: dailyProc
    command: ["/usr/bin/bash", root.cli, "daily"]
    environment: root.cliEnv
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { id: dailyErr; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) console.warn("daily-zen: daily refresh failed:", String(dailyErr.text || "").trim())
    }
  }
  Timer {
    interval: 3600000; repeat: true; running: root.configLoaded; triggeredOnStart: true
    onTriggered: if (root.config.daily_refresh !== false && !dailyProc.running) dailyProc.running = true
  }

  // ---- IPC --------------------------------------------------------------------
  IpcHandler {
    target: "daily-zen"
    function reload(): void { configFile.reload() }
    function refresh(): void { if (root.needStream) root.resolve(false, "refresh") }
    function pause(): void { root.paused = true; syncSoon.restart() }
    function resume(): void { root.paused = false; syncSoon.restart() }
    function status(): string {
      var lead = root.leadVideo()
      var shown = 0
      var inst = screens.instances
      for (var i = 0; i < inst.length; i++) if (inst[i] && inst[i].visible) shown += 1
      return JSON.stringify({
        state: root.state, error: root.error, mode: root.mode, sound: root.sound, volume: root.volume,
        paused: root.paused, fullscreen: root.fullscreen, covered: root.covered,
        video: !!lead && lead.playbackState === MediaPlayer.PlayingState, audio: audio.playbackState === MediaPlayer.PlayingState,
        position: Math.round(((root.mode === "animated" && lead) ? lead.position : audio.position) / 1000),
        title: root.stream ? root.stream.title : "", channel: root.stream ? root.stream.channel : "",
        height: root.stream ? root.stream.video_height : 0, live: root.stream ? !!root.stream.is_live : false,
        expires: root.stream ? root.stream.expires : 0, retries: root.retries, windows: shown, screens: inst.length
      })
    }
  }

  // ---- the windows, one per monitor ---------------------------------------------
  Variants {
    id: screens
    model: Quickshell.screens

    PanelWindow {
      id: win
      required property var modelData
      readonly property alias player: player
      readonly property bool wanted: root.mode === "animated" && root.stream !== null
                                     && (root.screenName === "" || (modelData && modelData.name === root.screenName))

      screen: modelData
      // Shown only with a decoded frame: a (re)start reveals the stock wallpaper, not black.
      visible: wanted && player.hasVideo
      anchors { top: true; bottom: true; left: true; right: true }
      color: "black"
      WlrLayershell.namespace: "omarchy-fans-daily-zen"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      MediaPlayer {
        id: player
        videoOutput: videoOut
        source: win.wanted ? root.stream.video_url : ""
        onMediaStatusChanged: {
          if (mediaStatus === MediaPlayer.EndOfMedia) { if (player === root.leadVideo()) root.endOfMedia() }
          else if (mediaStatus === MediaPlayer.LoadedMedia) root.onVideoLoaded(player)
        }
        onErrorOccurred: function(err, message) { if (String(source) !== "") root.playerError("video", message) }
      }

      VideoOutput {
        id: videoOut
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
      }

      // Same gestures as the stock background underneath: double-click for the
      // background picker, right double-click for the theme switcher.
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onDoubleClicked: function(mouse) {
          if (mouse.button === Qt.RightButton)
            Quickshell.execDetached(["/usr/bin/bash", "-c", "theme=$(omarchy-theme-switcher); [[ -n $theme ]] && omarchy-theme-set \"$theme\" >/dev/null 2>&1 &"])
          else
            Quickshell.execDetached(["/usr/bin/bash", "-c", "background=$(omarchy-theme-bg-switcher); [[ -n $background ]] && omarchy-theme-bg-set \"$background\""])
          mouse.accepted = true
        }
      }
    }
  }
}

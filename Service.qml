import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtMultimedia

// Daily Zen Wallpaper engine (kind: service). Lives inside omarchy-shell for as
// long as the plugin is enabled.
//
// It draws the stream on a layer-shell window on the Bottom layer: above the
// stock Omarchy background, under every window. Video and audio are two Qt
// MediaPlayers on two YouTube HLS renditions (bin/omarchy-daily-zen resolve
// picks them); the video player has no audio output, the audio player has no
// video, so "still + sound" and "animated, muted" are just which one runs.
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
  readonly property bool wantAudio: mode !== "off" && sound && !paused && !covered
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
    if (stale) { stream = null; stopAll() }
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
      if (root.resolveReason === "refresh" && root.stream && root.stream.video_id === s.video_id
          && (video.playbackState === MediaPlayer.PlayingState || audio.playbackState === MediaPlayer.PlayingState)) {
        root.stream = Object.assign({}, s, { video_url: root.stream.video_url, audio_url: root.stream.audio_url, expires: root.stream.expires })
        syncSoon.restart()
        return
      }
      root.stream = s
      root.startPlayback()
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

  // ---- playback ---------------------------------------------------------------
  function stopAll() {
    video.stop(); video.source = ""
    audio.stop(); audio.source = ""
  }
  function startPlayback() {
    if (!stream) return
    stopAll()
    syncPlayers()
  }
  Timer { id: syncSoon; interval: 60; repeat: false; onTriggered: root.syncPlayers() }
  onWantVideoChanged: syncSoon.restart()
  onWantAudioChanged: syncSoon.restart()
  onNeedStreamChanged: { if (needStream && !stream && configLoaded) resolve(false, "start"); syncSoon.restart() }

  function syncPlayers() {
    if (!stream) {
      if (!needStream) { stopAll(); state = mode === "off" ? "off" : "idle" }
      return
    }
    // video: only in animated mode; paused (not stopped) while covered or paused
    if (mode === "animated") {
      if (String(video.source) !== stream.video_url) video.source = stream.video_url
      if (wantVideo) { if (video.playbackState !== MediaPlayer.PlayingState) video.play() }
      else if (video.playbackState === MediaPlayer.PlayingState) video.pause()
    } else if (String(video.source) !== "") {
      video.stop(); video.source = ""
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
    else if (covered) state = "paused-fullscreen"
    else if (!needStream) state = "idle"
    else state = "playing"
  }

  function seekIfPending(player) {
    if (resumeAt <= 0 || (stream && stream.is_live)) { resumeAt = 0; return }
    if (player.seekable) { player.position = resumeAt }
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

  MediaPlayer {
    id: video
    videoOutput: videoOut
    onMediaStatusChanged: {
      if (mediaStatus === MediaPlayer.EndOfMedia) root.endOfMedia()
      else if (mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia) {
        root.seekIfPending(video)
        if (root.resumeAt > 0 && audio.mediaStatus >= MediaPlayer.LoadedMedia) root.seekIfPending(audio)
      }
    }
    onErrorOccurred: function(err, message) { root.playerError("video", message) }
  }
  MediaPlayer {
    id: audio
    audioOutput: AudioOutput { volume: root.volume }
    onMediaStatusChanged: {
      if (mediaStatus === MediaPlayer.EndOfMedia && root.mode !== "animated") root.endOfMedia()
      else if (mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia) {
        if (root.mode !== "animated") root.seekIfPending(audio)
        else if (video.position > 2000) audio.position = video.position
      }
    }
    onErrorOccurred: function(err, message) { root.playerError("audio", message) }
  }

  // Position bookkeeping, URL expiry and audio/video drift, once a minute.
  Timer {
    interval: 60000; repeat: true
    running: root.stream !== null && root.needStream
    onTriggered: {
      var lead = root.mode === "animated" ? video : audio
      if (lead.position > 0) root.savedPosition = lead.position
      var nowSec = Date.now() / 1000
      if (root.stream.expires && nowSec > root.stream.expires - 240 && !resolveProc.running) {
        root.resumeAt = root.savedPosition
        root.resolve(true, "expiry")
        return
      }
      if (root.wantVideo && root.wantAudio && !root.stream.is_live
          && video.playbackState === MediaPlayer.PlayingState && audio.playbackState === MediaPlayer.PlayingState
          && Math.abs(audio.position - video.position) > 2500 && audio.seekable) {
        audio.position = video.position
      }
    }
  }
  Timer { interval: 10000; repeat: true; running: root.state === "playing"; onTriggered: {
    var lead = root.mode === "animated" ? video : audio
    if (lead.position > 0) root.savedPosition = lead.position
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
    function check() { if (!running && root.pauseWhenFullscreen && root.mode !== "off") running = true }
    onExited: function(code) {
      var fs = false
      try { var w = JSON.parse(fsOut.text); fs = !!w && Number(w.fullscreen || 0) > 0 } catch (e) { fs = false }
      root.fullscreen = fs
    }
  }
  Timer { interval: 4000; repeat: true; running: root.pauseWhenFullscreen && root.mode !== "off"; triggeredOnStart: true; onTriggered: fullscreenProc.check() }
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
      return JSON.stringify({
        state: root.state, error: root.error, mode: root.mode, sound: root.sound, volume: root.volume,
        paused: root.paused, fullscreen: root.fullscreen, covered: root.covered,
        video: video.playbackState === MediaPlayer.PlayingState, audio: audio.playbackState === MediaPlayer.PlayingState,
        position: Math.round((root.mode === "animated" ? video.position : audio.position) / 1000),
        title: root.stream ? root.stream.title : "", channel: root.stream ? root.stream.channel : "",
        height: root.stream ? root.stream.video_height : 0, live: root.stream ? !!root.stream.is_live : false,
        expires: root.stream ? root.stream.expires : 0, retries: root.retries, window: win.visible
      })
    }
  }

  // ---- the window -------------------------------------------------------------
  function pickScreen() {
    var screens = Quickshell.screens
    if (!screens || screens.length === 0) return null
    if (root.screenName) {
      for (var i = 0; i < screens.length; i++) if (screens[i].name === root.screenName) return screens[i]
    }
    return screens[0]
  }

  PanelWindow {
    id: win
    screen: root.pickScreen()
    visible: root.mode === "animated" && root.stream !== null
    anchors { top: true; bottom: true; left: true; right: true }
    color: "black"
    WlrLayershell.namespace: "omarchy-fans-daily-zen"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

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

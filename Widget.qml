import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Daily Zen Wallpaper: the bar chip and its popup.
//
//   left click    open the popup (mode, sound, stills, theme, stream URL)
//   middle click  animated <-> still
//   scroll        volume
//
// Everything shown comes from `omarchy-daily-zen status --json`; every action
// is a fixed argv through Util.execArgv, so nothing typed here reaches a shell
// as code. The engine itself is Service.qml; the two talk through the config
// file and the "daily-zen" IPC target, never directly.
Panel {
  id: root
  moduleName: "fans.omarchy.daily-zen-wallpaper"
  ipcTarget: "fans.omarchy.daily-zen-wallpaper"
  manageIpc: false

  readonly property string cli: Qt.resolvedUrl("bin/omarchy-daily-zen").toString().replace(/^file:\/\//, "")
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property var status: null
  property var lib: null
  property string browse: "cat:zen"        // bookmarks | cat:<id> | ch:<id>
  property string followDraft: ""
  property bool loading: false
  property string error: ""
  property string urlDraft: ""
  property bool urlEdited: false

  readonly property var cfg: status && status.config ? status.config : ({})
  readonly property var engine: status && status.engine ? status.engine : null
  readonly property var stream: status && status.stream ? status.stream : null
  readonly property string mode: cfg.mode || "animated"
  readonly property bool sound: cfg.sound !== false
  readonly property real volume: typeof cfg.volume === "number" ? cfg.volume : 0.35
  readonly property bool engineUp: engine !== null
  readonly property var browseOptions: {
    var opts = [{ value: "bookmarks", label: "Bookmarks" + (lib && lib.bookmarks ? " (" + lib.bookmarks.length + ")" : "") }]
    var cats = lib && lib.categories ? lib.categories : [{ id: "zen", name: "Zen" }]
    for (var i = 0; i < cats.length; i++) opts.push({ value: "cat:" + cats[i].id, label: cats[i].name })
    var chans = lib && lib.channels ? lib.channels : [{ id: "AetherJourneyMusic", name: "Aether Journey" }]
    for (var k = 0; k < chans.length; k++) opts.push({ value: "ch:" + chans[k].id, label: "Creator: " + chans[k].name })
    return opts
  }
  readonly property var browseChannel: {
    if (!lib || browse.indexOf("ch:") !== 0) return null
    var id = browse.substring(3)
    for (var i = 0; i < (lib.channels || []).length; i++) if (lib.channels[i].id === id) return lib.channels[i]
    return null
  }
  readonly property var libRows: {
    if (!lib) return []
    var rows = lib.entries || []
    if (lib.now && lib.now.id && !rows.some(function(e) { return e.id === lib.now.id })) rows = [Object.assign({}, lib.now, { isNow: true })].concat(rows)
    return rows
  }
  readonly property string engineState: engine ? String(engine.state || "") : ""

  // updates: what `update-check` reported for this widget's version (docs/update-alerts.md)
  property string version: ""
  property var updateInfo: null
  readonly property bool updateAvailable: !!updateInfo && updateInfo.update_available === true
                                          && updateInfo.dismissed !== updateInfo.latest
  readonly property bool updateMismatch: !!updateInfo && updateInfo.mismatch === true
  readonly property string updateKey: updateAvailable ? String(updateInfo.latest) : (updateMismatch ? "mismatch" : "")
  property string updateHiddenKey: ""
  readonly property bool updatePending: updateKey !== "" && updateKey !== updateHiddenKey

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) { load(); loadLibrary(false); checkUpdates() }
  Component.onCompleted: load()

  // ---- updates ----------------------------------------------------------------
  FileView {
    path: Qt.resolvedUrl("manifest.json").toString().replace(/^file:\/\//, "")
    printErrors: false
    onLoaded: {
      try { root.version = String(JSON.parse(text()).version || "") } catch (e) { root.version = "" }
      root.checkUpdates()
    }
  }
  function checkUpdates() {
    if (root.setting("update_check", true) === false || updateProc.running) return
    updateProc.command = [root.cli, "update-check", root.version]
    updateProc.running = true
  }
  Process {
    id: updateProc
    stdout: StdioCollector { id: updateOut; waitForEnd: true }
    stderr: StdioCollector { id: updateErr; waitForEnd: true }
    onExited: function(code) {
      var d = null
      try { d = JSON.parse(updateOut.text) } catch (e) { d = null }
      if (d) { root.updateInfo = d; return }
      if (code !== 0 && String(updateErr.text || "").indexOf("unknown command") >= 0)
        root.updateInfo = { mismatch: true, update_available: false, latest: null, notes: [], dismissed: "", cli: "older" }
    }
  }
  Timer { interval: 6 * 3600 * 1000; running: true; repeat: true; onTriggered: root.checkUpdates() }
  function runUpdate() {
    root.updateHiddenKey = root.updateKey
    Util.execArgv([root.cli, "update-run", root.updateAvailable ? "all" : "install"])
  }
  function dismissUpdate() {
    root.updateHiddenKey = root.updateKey
    if (root.updateAvailable && root.updateInfo.latest) Util.execArgv([root.cli, "update-dismiss", String(root.updateInfo.latest)])
  }

  // ---- data -------------------------------------------------------------------
  function load() {
    if (statusProc.running) return
    loading = true
    statusProc.running = true
  }
  Process {
    id: statusProc
    command: [root.cli, "status", "--json"]
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    stderr: StdioCollector { id: statusErr; waitForEnd: true }
    onExited: function(code) {
      root.loading = false
      if (code !== 0) { root.error = String(statusErr.text || "").trim() || ("status exited " + code); return }
      try {
        root.status = JSON.parse(statusOut.text); root.error = ""
        if (!root.urlEdited) root.urlDraft = String(root.cfg.url || "")
      } catch (e) { root.error = "bad JSON from status" }
    }
  }
  Timer { interval: 3000; running: root.opened; repeat: true; onTriggered: root.load() }
  Timer { interval: 60000; running: !root.opened; repeat: true; onTriggered: root.load() }
  Timer { id: reloadSoon; interval: 900; onTriggered: { root.load(); root.loadLibrary(false) } }

  // ---- library (catalog, creators, bookmarks, ratings) ----
  function loadLibrary(refresh) {
    if (libProc.running) { libAgain.restart(); return }
    var argv = [root.cli, "library", "--json"]
    if (root.browse === "bookmarks") argv.push("--bookmarks")
    else if (root.browse.indexOf("ch:") === 0) argv.push("--channel", root.browse.substring(3))
    else argv.push("--category", root.browse.substring(4))
    if (refresh) argv.push("--refresh")
    libProc.command = argv
    libProc.running = true
  }
  Timer { id: libAgain; interval: 400; onTriggered: root.loadLibrary(false) }
  Process {
    id: libProc
    stdout: StdioCollector { id: libOut; waitForEnd: true }
    stderr: StdioCollector { id: libErr; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) { root.error = String(libErr.text || "").trim() || ("library exited " + code); return }
      try { root.lib = JSON.parse(libOut.text) } catch (e) { root.error = "bad JSON from library" }
    }
  }
  function follow() {
    var u = String(followDraft || "").trim()
    if (!u) return
    root.followDraft = ""
    act(["channel", "add", u])
  }

  function act(argv) { Util.execArgv([root.cli].concat(argv)); reloadSoon.restart() }
  function setMode(m) { act(["mode", m]) }
  function useUrl() {
    var u = String(urlDraft || "").trim()
    if (!u) return
    root.urlEdited = false
    act(["set-url", u])
  }

  function modeIcon() {
    if (!root.engineUp) return "󰋩"
    if (root.engineState === "error") return "󰋩"
    if (root.mode === "off") return "󰋩"
    if (root.mode === "still") return "󰋩"
    return root.engineState === "playing" ? "󰐊" : "󰏤"
  }
  function stateText() {
    if (!root.status) return root.error ? root.error : "Loading…"
    if (!root.engineUp) return "Engine not running. Enable the plugin (omarchy plugin enable fans.omarchy.daily-zen-wallpaper) or restart the shell."
    var s = root.engineState
    var head = s === "playing" ? (root.mode === "animated" ? "Playing" : (root.sound ? "Playing sound, still wallpaper" : "Still wallpaper"))
      : s === "paused" ? "Paused"
      : s === "paused-fullscreen" ? "Video paused behind a fullscreen window" + (root.sound ? ", sound on" : "")
      : s === "resolving" ? "Finding the stream…"
      : s === "error" ? "Problem: " + (root.engine.error || "unknown") + (root.engine.retries ? " (retrying)" : "")
      : s === "off" ? "Off" : "Idle"
    var q = root.stream && root.stream.video_height ? " · " + root.stream.video_height + "p" : ""
    var live = root.stream && root.stream.is_live ? " · live" : ""
    return head + (root.mode === "animated" ? q : "") + live
  }
  function ago(sec) {
    if (!sec) return ""
    var s = Math.max(0, Math.floor(root.status.now - sec))
    if (s < 60) return s + "s ago"
    if (s < 3600) return Math.floor(s / 60) + "m ago"
    if (s < 86400) return Math.floor(s / 3600) + "h ago"
    return Math.floor(s / 86400) + "d ago"
  }

  // ---- chip -------------------------------------------------------------------
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.modeIcon()
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: "Daily Zen Wallpaper"
      + (root.stream && root.stream.title ? " · " + root.stream.title : "")
      + " — " + root.stateText()
      + (root.updateAvailable ? " · " + root.updateInfo.latest + " is available" : (root.updateMismatch ? " · finish updating" : ""))
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.MiddleButton) root.setMode(root.mode === "animated" ? "still" : "animated")
      else root.toggle()
    }
  }
  WheelHandler {
    target: button
    onWheel: function(event) {
      var v = Math.max(0, Math.min(1, root.volume + (event.angleDelta.y > 0 ? 0.05 : -0.05)))
      root.act(["volume", v.toFixed(2)])
    }
  }
  Rectangle {
    visible: root.updatePending || (root.engineUp && root.engineState === "error")
    width: Style.space(6); height: width; radius: width / 2
    color: root.engineUp && root.engineState === "error" ? Color.urgent : Color.accent
    anchors { right: parent.right; top: parent.top; margins: Style.space(3) }
  }

  // ---- popup ------------------------------------------------------------------
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(760))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(8)

          // The author's Suno invite: make your own music (opens the browser).
          Button {
            text: "Make your own music with Suno"; iconText: "󰝚"; foreground: Color.accent; fontFamily: root.fontFamily
            fontSize: Style.font.caption; iconSize: Style.font.caption
            tooltipText: "suno.com/invite/@markusix — the author's invite link"
            onClicked: { root.close(); Util.execArgv([root.cli, "suno"]) }
          }

          PanelHero {
            width: parent.width
            title: "Daily Zen Wallpaper"
            meta: (root.stream && root.stream.title ? root.stream.title + (root.stream.channel ? " — " + root.stream.channel : "") + "\n" : "") + root.stateText()
          }

          // ---- update banner (docs/update-alerts.md) ----
          Rectangle {
            id: updateBanner
            width: parent.width
            visible: root.updatePending
            height: visible ? updateRow.implicitHeight + Style.space(14) : 0
            radius: Style.space(6)
            color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.08)
            border.width: 1
            border.color: Color.accent
            Row {
              id: updateRow
              width: parent.width - Style.space(14)
              anchors.centerIn: parent
              spacing: Style.space(8)
              Column {
                id: updateCol
                width: parent.width - updateButtons.width - parent.spacing
                spacing: Style.space(2)
                Text {
                  width: parent.width; wrapMode: Text.Wrap; textFormat: Text.PlainText
                  text: root.updateAvailable
                        ? "Daily Zen Wallpaper " + root.updateInfo.latest + " is available (you have " + root.version + ")"
                        : "Finish updating Daily Zen Wallpaper: the chip is " + root.version + ", its helper is " + (root.updateInfo ? root.updateInfo.cli : "")
                  color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true
                }
                Repeater {
                  model: root.updateAvailable ? root.updateInfo.notes.slice(0, 4) : []
                  delegate: Text {
                    required property var modelData
                    width: updateCol.width; wrapMode: Text.Wrap; textFormat: Text.PlainText
                    text: "•  " + modelData
                    color: root.foreground; opacity: 0.8; font.family: root.fontFamily; font.pixelSize: Style.font.caption
                  }
                }
                Text {
                  width: parent.width; wrapMode: Text.Wrap; textFormat: Text.PlainText
                  text: root.updateAvailable
                        ? "Update opens a terminal: omarchy plugin update shows the changes and asks, install.sh asks, then a shell restart loads the new engine."
                        : "Run install.sh once so the helper matches. It asks before changing anything."
                  color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
                }
              }
              Column {
                id: updateButtons
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)
                Button {
                  text: root.updateAvailable ? "Update…" : "Finish update…"; foreground: Color.accent; fontFamily: root.fontFamily
                  onClicked: root.runUpdate()
                }
                Button { text: "Later"; foreground: root.dim; fontFamily: root.fontFamily; onClicked: root.dismissUpdate() }
              }
            }
          }

          Text {
            width: parent.width; wrapMode: Text.WordWrap; textFormat: Text.PlainText
            visible: root.error !== ""
            color: Color.urgent; font.family: root.fontFamily; font.pixelSize: Style.font.caption
            text: root.error
          }

          // ---- mode ----
          PanelSectionHeader { width: parent.width; text: "Wallpaper" }
          Flow {
            width: parent.width
            spacing: Style.space(6)
            Button {
              text: "Animated"; iconText: "󰕧"; fontFamily: root.fontFamily; selected: root.mode === "animated"
              foreground: root.mode === "animated" ? Color.accent : root.foreground
              tooltipText: "The stream plays under your windows"
              onClicked: root.setMode("animated")
            }
            Button {
              text: "Still"; iconText: "󰋩"; fontFamily: root.fontFamily; selected: root.mode === "still"
              foreground: root.mode === "still" ? Color.accent : root.foreground
              tooltipText: "A frame from the stream is your Omarchy background (a new one every day)"
              onClicked: root.setMode("still")
            }
            Button {
              text: "Off"; iconText: "󰛊"; fontFamily: root.fontFamily; selected: root.mode === "off"
              foreground: root.mode === "off" ? Color.accent : root.foreground
              tooltipText: "Nothing plays; your Omarchy background shows"
              onClicked: root.setMode("off")
            }
            Button {
              visible: root.engineUp && root.mode !== "off"
              text: root.engine && root.engine.paused ? "Resume" : "Pause"
              iconText: root.engine && root.engine.paused ? "󰐊" : "󰏤"
              foreground: root.dim; fontFamily: root.fontFamily
              onClicked: root.act([root.engine && root.engine.paused ? "resume" : "pause"])
            }
          }

          // ---- sound ----
          Toggle {
            width: parent.width
            label: "Sound"
            description: root.mode === "still" ? "The stream's music keeps playing under the still" : "Play the stream's audio"
            checked: root.sound
            fontFamily: root.fontFamily
            onClicked: root.act(["sound", root.sound ? "off" : "on"])
          }
          Row {
            width: parent.width
            spacing: Style.space(8)
            visible: root.sound
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "Volume"; textFormat: Text.PlainText
              color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption
            }
            PanelSlider {
              id: volumeSlider
              width: parent.width - x - volumeText.width - Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              bar: root.bar
              minimum: 0; maximum: 1; step: 0.05
              value: root.volume
              onReleased: function(v) { root.act(["volume", Number(v).toFixed(2)]) }
            }
            Text {
              id: volumeText
              anchors.verticalCenter: parent.verticalCenter
              text: Math.round((volumeSlider.dragging ? volumeSlider.liveValue : root.volume) * 100) + "%"; textFormat: Text.PlainText
              color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
            }
          }

          // ---- scene actions ----
          PanelSeparator { width: parent.width }
          PanelSectionHeader { width: parent.width; text: "This scene" }
          Flow {
            width: parent.width
            spacing: Style.space(6)
            Button {
              text: "Grab a still"; iconText: "󰄀"; foreground: Color.accent; fontFamily: root.fontFamily
              tooltipText: "One frame from the stream becomes your Omarchy background now"
              onClicked: root.act(["still"])
            }
            Button {
              text: "Make a theme with Aether"; iconText: "󰏘"; foreground: Color.accent; fontFamily: root.fontFamily
              tooltipText: "Aether extracts a palette from the last still and applies it as the Omarchy theme \"" + (root.cfg.theme_name || "daily-zen") + "\" (terminals restart)"
              onClicked: root.act(["theme"])
            }
            Button {
              text: "Refresh today"; iconText: "󰑐"; foreground: root.foreground; fontFamily: root.fontFamily
              tooltipText: "Run the daily refresh now: newest video of a channel, a new still" + (root.cfg.daily_theme ? ", a new theme" : "")
              onClicked: root.act(["daily", "--force"])
            }
            Button {
              text: "Open on YouTube"; iconText: "󰗃"; foreground: root.dim; fontFamily: root.fontFamily
              onClicked: { root.close(); Util.execArgv([root.cli, "open"]) }
            }
          }
          Text {
            width: parent.width; wrapMode: Text.WordWrap; textFormat: Text.PlainText
            color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
            text: (root.status && root.status.frame ? "Last still " + root.ago(root.status.frame.taken) : "No still yet")
              + (root.status && root.status.daily ? " · daily refresh " + root.ago(root.status.daily.last) : "")
          }

          // ---- library ----
          PanelSeparator { width: parent.width }
          Row {
            width: parent.width
            spacing: Style.space(8)
            PanelSectionHeader { anchors.verticalCenter: parent.verticalCenter; text: "Library" }
            Dropdown {
              id: browseDropdown
              width: Style.space(230)
              anchors.verticalCenter: parent.verticalCenter
              showLabel: false
              options: root.browseOptions
              fontFamily: root.fontFamily
              Connections {
                target: root
                function onBrowseOptionsChanged() { if (browseDropdown.value !== root.browse) browseDropdown.value = root.browse }
              }
              Component.onCompleted: value = root.browse
              onChanged: function(v) { if (v !== root.browse) { root.browse = v; root.loadLibrary(false) } }
            }
            Button {
              anchors.verticalCenter: parent.verticalCenter
              text: ""; iconText: "󰑐"; foreground: root.dim; fontFamily: root.fontFamily
              tooltipText: "Fetch the newest catalog, creator lists and community ratings"
              onClicked: root.loadLibrary(true)
            }
          }
          Text {
            width: parent.width; wrapMode: Text.WordWrap; textFormat: Text.PlainText
            color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
            text: !root.lib ? "Loading the library…"
              : (root.browse === "bookmarks" ? "Your bookmarks. Bookmark anything with the flag on its row."
                : (root.browseChannel ? "Latest from " + root.browseChannel.name + " (live streams first). Play the creator to follow their newest upload every day."
                  : "The ten most popular long streams in this category, from YouTube searches (catalog " + (root.lib.generated || "") + ")."))
              + (root.lib && root.lib.ratings_api_available ? " Stars are shared with every install." : " Community ratings are not available yet; your stars stay on this machine until then.")
          }
          Flow {
            width: parent.width
            spacing: Style.space(6)
            visible: root.browseChannel !== null
            Button {
              text: "Play this creator"; iconText: "󰐊"; foreground: Color.accent; fontFamily: root.fontFamily
              tooltipText: "Follow: their newest stream or upload becomes the wallpaper, rechecked every day"
              onClicked: if (root.browseChannel) root.act(["play", root.browseChannel.id])
            }
            Button {
              visible: !!(root.browseChannel && root.browseChannel.added)
              text: "Unfollow"; foreground: root.dim; fontFamily: root.fontFamily
              onClicked: { var id = root.browseChannel.id; root.browse = "cat:zen"; root.act(["channel", "remove", id]) }
            }
          }
          Repeater {
            model: root.libRows
            delegate: Column {
              id: erow
              required property var modelData
              width: column.width
              spacing: Style.space(2)
              Row {
                width: parent.width
                spacing: Style.space(6)
                Text {
                  width: parent.width - playBtn.width - parent.spacing
                  anchors.verticalCenter: parent.verticalCenter
                  elide: Text.ElideRight; textFormat: Text.PlainText
                  color: erow.modelData.playing ? Color.accent : root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body
                  text: (erow.modelData.isNow ? "Now playing: " : "") + (erow.modelData.title || erow.modelData.id)
                }
                Button {
                  id: playBtn
                  text: erow.modelData.playing ? "Playing" : "Play"; iconText: "󰐊"; fontFamily: root.fontFamily
                  foreground: erow.modelData.playing ? root.dim : Color.accent
                  onClicked: if (!erow.modelData.playing) root.act(["play", String(erow.modelData.id)])
                }
              }
              Row {
                width: parent.width
                spacing: Style.space(8)
                Text {
                  width: parent.width - starRow.width - bmBtn.width - parent.spacing * 2
                  anchors.verticalCenter: parent.verticalCenter
                  elide: Text.ElideRight; textFormat: Text.PlainText
                  color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
                  text: (erow.modelData.channel || "") + (erow.modelData.live ? " · live" : "")
                    + (erow.modelData.count > 0 ? " · " + Number(erow.modelData.avg).toFixed(1) + " ★ (" + erow.modelData.count + ")" : "")
                }
                Row {
                  id: starRow
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(1)
                  Repeater {
                    model: 5
                    delegate: Text {
                      required property int index
                      textFormat: Text.PlainText
                      text: index < (erow.modelData.my_stars || 0) ? "★" : "☆"
                      color: index < (erow.modelData.my_stars || 0) ? Color.accent : root.dim
                      font.family: root.fontFamily; font.pixelSize: Style.font.body
                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.act(["rate", String(erow.modelData.id), String((erow.modelData.my_stars || 0) === index + 1 ? 0 : index + 1)])
                      }
                    }
                  }
                }
                Button {
                  id: bmBtn
                  anchors.verticalCenter: parent.verticalCenter
                  text: ""; iconText: erow.modelData.bookmarked ? "󰃀" : "󰃃"; fontFamily: root.fontFamily
                  foreground: erow.modelData.bookmarked ? Color.accent : root.dim
                  tooltipText: erow.modelData.bookmarked ? "Remove the bookmark" : "Bookmark"
                  onClicked: root.act(["bookmark", "toggle", String(erow.modelData.id)])
                }
              }
              PanelSeparator { width: parent.width; strength: 0.06 }
            }
          }
          Text {
            width: parent.width; wrapMode: Text.WordWrap; textFormat: Text.PlainText
            visible: root.lib !== null && root.libRows.length === 0
            color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
            text: root.browse === "bookmarks" ? "No bookmarks yet." : "Nothing here yet."
          }
          Row {
            width: parent.width
            spacing: Style.space(6)
            TextField {
              id: followField
              width: parent.width - followButton.width - parent.spacing
              foreground: root.foreground
              placeholderText: "Follow a creator: https://www.youtube.com/@channel"
              font.family: root.fontFamily
              text: root.followDraft
              onTextEdited: root.followDraft = text
              onAccepted: root.follow()
            }
            Button {
              id: followButton
              anchors.verticalCenter: parent.verticalCenter
              text: "Follow"; foreground: Color.accent; fontFamily: root.fontFamily
              tooltipText: "Add this creator to the Library selector"
              onClicked: root.follow()
            }
          }

          // ---- stream ----
          PanelSeparator { width: parent.width }
          PanelSectionHeader { width: parent.width; text: "Stream" }
          Row {
            width: parent.width
            spacing: Style.space(6)
            TextField {
              id: urlField
              width: parent.width - useButton.width - parent.spacing
              foreground: root.foreground
              placeholderText: "https://www.youtube.com/watch?v=…  (video, live, playlist or channel)"
              font.family: root.fontFamily
              text: root.urlDraft
              onTextEdited: { root.urlDraft = text; root.urlEdited = true }
              onAccepted: root.useUrl()
            }
            Button {
              id: useButton
              anchors.verticalCenter: parent.verticalCenter
              text: "Use"; foreground: Color.accent; fontFamily: root.fontFamily
              tooltipText: "Play this YouTube video, live stream, playlist or channel (newest upload)"
              onClicked: root.useUrl()
            }
          }
          Row {
            width: parent.width
            spacing: Style.space(8)
            Dropdown {
              id: qualityDropdown
              width: Style.space(140)
              label: "Video quality"
              options: [{ value: "480", label: "480p" }, { value: "720", label: "720p" }, { value: "1080", label: "1080p" }]
              fontFamily: root.fontFamily
              // The dropdown assigns its own value on selection, which would
              // break a binding; follow the config by hand instead.
              Connections {
                target: root
                function onStatusChanged() { var v = String(root.cfg.quality || 720); if (qualityDropdown.value !== v) qualityDropdown.value = v }
              }
              Component.onCompleted: value = String(root.cfg.quality || 720)
              onChanged: function(v) { if (v !== String(root.cfg.quality || 720)) root.act(["quality", v]) }
            }
          }

          // ---- daily ----
          PanelSeparator { width: parent.width }
          PanelSectionHeader { width: parent.width; text: "Every day" }
          Toggle {
            width: parent.width
            label: "Daily refresh"
            description: "A new still each day; for a channel or playlist, its newest video"
            checked: root.cfg.daily_refresh !== false
            fontFamily: root.fontFamily
            onClicked: root.act(["daily-refresh", root.cfg.daily_refresh !== false ? "off" : "on"])
          }
          Toggle {
            width: parent.width
            label: "Daily theme"
            description: "Also rebuild the Aether theme from the new still (terminals restart once a day)"
            checked: root.cfg.daily_theme === true
            fontFamily: root.fontFamily
            onClicked: root.act(["daily-theme", root.cfg.daily_theme === true ? "off" : "on"])
          }
          Toggle {
            width: parent.width
            label: "Pause video behind fullscreen windows"
            description: "Stop decoding the picture while a fullscreen window covers it; the sound keeps playing"
            checked: root.cfg.pause_when_fullscreen !== false
            fontFamily: root.fontFamily
            onClicked: root.act(["fullscreen-pause", root.cfg.pause_when_fullscreen !== false ? "off" : "on"])
          }
          Text {
            width: parent.width; wrapMode: Text.WordWrap; textFormat: Text.PlainText
            color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
            text: "The stream plays live from YouTube through yt-dlp; only still frames are saved (~/.local/share/omarchy-daily-zen/frames). Command line: omarchy-daily-zen."
          }
        }
      }
    }
  }
}

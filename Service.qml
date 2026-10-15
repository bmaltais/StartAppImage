// StartAppImage: install, update and remove AppImages from the Omarchy shell.
// This file owns the state, every call to bin/startappimage, the IPC entry
// points and the window. ManagerView.qml and InstallView.qml draw what is in it.
//
//   omarchy-shell io.github.bmaltais.startappimage open            toggle the manager
//   omarchy-shell io.github.bmaltais.startappimage install <file>  show the install card
//   omarchy-shell io.github.bmaltais.startappimage setup           show the setup card
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

Item {
  id: root

  // Injected by omarchy-shell (the plugin service loader).
  property var shell: null

  readonly property string cli: Qt.resolvedUrl("bin/startappimage").toString().replace("file://", "")
  readonly property int shadow: Style.space(14)
  readonly property int radius: Math.max(Style.cornerRadius, Style.space(10))

  // ---- what the window shows ----------------------------------------------
  property bool shown: false
  property string view: "manager"            // "manager" | "install" | "settings" | "setup"
  property var targetScreen: null

  // The window is only mapped once what it shows has loaded, so it never flashes
  // an empty list or a blank install card. If loading is slow it appears anyway.
  property bool listLoaded: false
  property bool slow: false
  readonly property bool ready: root.slow || (root.view === "manager" ? root.listLoaded
    : root.view === "install" ? (root.installState !== "loading" && root.locationsReady)
    : root.view === "setup" ? root.integLoaded
    : (root.settingsState !== "loading" && root.locationsReady))
  onShownChanged: {
    root.slow = false
    if (root.shown) slowTimer.restart()
  }
  Timer { id: slowTimer; interval: 700; onTriggered: root.slow = true }

  // ---- installed apps -------------------------------------------------------
  property var apps: []
  property var updates: ({})                 // id -> latest version
  readonly property int updateCount: Object.keys(updates).length
  property string busyId: ""                 // app being updated/removed, "" when idle
  property bool checking: false
  property string notice: ""
  property bool noticeIsError: false
  property var notified: ({})

  // ---- the install card -----------------------------------------------------
  property string installFile: ""
  property var meta: ({})
  property string installState: "idle"       // loading | ready | installing | done | failed
  property string installLog: ""
  property string installedId: ""
  property var locations: ({ "default": "", "options": [] })
  property string installDir: ""
  property bool locationsReady: false

  // ---- setup: launcher entry, file handler, command line ---------------------
  property var integ: ({})
  property bool integLoaded: false
  property bool setupBusy: false
  property bool offerSetup: false            // true while the one-time check runs

  // ---- per-app settings --------------------------------------------------------
  property var settingsApp: ({})
  property var cfg: ({})
  property string settingsState: "idle"      // loading | ready | saving
  property string settingsError: ""
  readonly property string home: Quickshell.env("HOME")
  // Folders to offer: where AppImages already live, plus the app's own folder if it is elsewhere.
  readonly property var locationOptions: {
    var opts = (root.locations.options || []).slice()
    var extra = [root.meta.installedDir, root.cfg.dir]
    extra.forEach(function (d) {
      if (d && !opts.some(function (o) { return o.path === d })) opts.unshift({ path: d, apps: 0 })
    })
    return opts
  }

  // ---- window control ---------------------------------------------------------
  function focusedScreen() {
    var monitor = Hyprland.focusedMonitor
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      if (monitor && screens[i].name === monitor.name) return screens[i]
    }
    return screens.length ? screens[0] : null
  }

  function toPath(url) {
    var s = String(url)
    return s.indexOf("file://") === 0 ? decodeURIComponent(s.substring(7)) : s
  }

  function showManager() {
    root.view = "manager"
    root.targetScreen = root.focusedScreen()
    root.shown = true
    root.refresh()
    root.check()
  }

  function short(path) {
    return root.home !== "" && String(path).indexOf(root.home) === 0 ? "~" + String(path).substring(root.home.length) : path
  }

  // Preselect the app's current folder when it is installed, else the remembered default.
  function chooseDir() {
    if (root.installState !== "ready" || !root.locationsReady) return
    root.installDir = root.meta.installedDir || root.locations["default"]
  }

  function showInstall(path) {
    root.installFile = root.toPath(path)
    root.meta = ({})
    root.locationsReady = false
    root.installDir = ""
    locProc.running = true
    root.installLog = ""
    root.installedId = ""
    root.installState = "loading"
    root.view = "install"
    root.targetScreen = root.focusedScreen()
    root.shown = true
    infoProc.command = [root.cli, "info", root.installFile]
    infoProc.running = true
  }

  function close() { root.shown = false }

  function showSetup() {
    root.integLoaded = false
    root.view = "setup"
    root.targetScreen = root.focusedScreen()
    root.shown = true
    integProc.running = true
  }

  function skipSetup() {
    skipProc.running = true
    root.close()
  }

  function applySetup(launcher, handler, cli, hours) {
    if (setupProc.running) return
    root.setupBusy = true
    setupProc.command = [root.cli, "setup", "--launcher", String(launcher), "--handler", String(handler), "--cli", String(cli), "--check-hours", String(hours)]
    setupProc.running = true
  }

  function showSettings(app) {
    root.settingsApp = app
    root.cfg = ({})
    root.settingsError = ""
    root.settingsState = "loading"
    root.view = "settings"
    locProc.running = true
    cfgProc.command = [root.cli, "config", app.id]
    cfgProc.running = true
  }

  function closeSettings() { root.view = "manager" }

  // ---- update source preview: what a pasted link points at ------------------------
  property var resolved: ({})                 // result of `resolve` for resolveAsked
  property string resolveAsked: ""            // the input `resolved` answers
  property string resolveWanted: ""           // the latest input the UI asked about
  readonly property bool resolving: resolveWanted !== "" && resolveWanted !== resolveAsked

  function resolveSource(input) {
    root.resolveWanted = input.trim()
    if (root.resolveWanted === "") { root.resolved = ({}); root.resolveAsked = ""; return }
    if (!resolveProc.running) resolveProc.start()
  }

  function saveSettings(args) {
    root.settingsError = ""
    root.settingsState = "saving"
    setProc.command = [root.cli, "set", root.settingsApp.id].concat(args)
    setProc.running = true
  }

  function say(text, isError) {
    root.notice = text
    root.noticeIsError = !!isError
    noticeTimer.restart()
  }

  // ---- install card actions ----------------------------------------------------
  function startInstall() {
    root.installLog = ""
    root.installState = "installing"
    installProc.command = root.installDir !== ""
      ? [root.cli, "add", root.installFile, "--dir", root.installDir]
      : [root.cli, "add", root.installFile]
    installProc.running = true
  }

  function uninstallFromCard() {
    root.installLog = ""
    root.installState = "removing"
    removeProc.command = [root.cli, "remove", root.meta.id]
    removeProc.running = true
  }

  function runOnce() {
    Quickshell.execDetached([root.cli, "run", root.installFile])
    root.close()
  }

  function openInstalled() {
    Quickshell.execDetached([root.cli, "run", root.installedId !== "" ? root.installedId : root.meta.id])
    root.close()
  }

  // ---- manager actions ------------------------------------------------------------
  function refresh() { if (!listProc.running) listProc.running = true }
  function check() {
    if (checkProc.running) return
    root.checking = true
    checkProc.running = true
  }

  function openApp(app) {
    Quickshell.execDetached([root.cli, "run", app.id])
    root.close()
  }

  function runAction(args, busy, done) {
    if (actionProc.running) return
    root.busyId = busy
    actionProc.done = done
    actionProc.last = ""
    actionProc.command = [root.cli].concat(args)
    actionProc.running = true
  }

  function updateApp(id) { root.runAction(["update", id], id, "Updated") }
  function updateAll() { root.runAction(["update"], "*", "Everything is up to date") }
  function removeApp(id) { root.runAction(["remove", id], id, "Uninstalled") }
  function addSource(source) { root.runAction(["add", source], "+", "Installed") }

  // ---- IPC -------------------------------------------------------------------------
  IpcHandler {
    target: "io.github.bmaltais.startappimage"
    function open(): void { if (root.shown && root.view === "manager") root.close(); else root.showManager() }
    function install(path: string): void { root.showInstall(path) }
    function settings(id: string): void {
      var app = root.apps.filter(function (a) { return a.id === id })[0] || { id: id }
      root.targetScreen = root.focusedScreen()
      root.shown = true
      root.showSettings(app)
    }
    function setup(): void { root.showSetup() }
    function close(): void { root.close() }
    function check(): void { root.check() }
  }

  // ---- processes ---------------------------------------------------------------------
  Process {
    id: listProc
    command: [root.cli, "list", "--json"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.apps = JSON.parse(text) } catch (e) { root.apps = [] }
        root.listLoaded = true
      }
    }
  }

  Process {
    id: integProc
    command: [root.cli, "integration"]
    stdout: StdioCollector {
      onStreamFinished: {
        var info = ({})
        try { info = JSON.parse(text) } catch (e) {}
        root.integ = info
        // The one-time offer only opens the card when setup has not been answered yet.
        if (root.offerSetup) {
          root.offerSetup = false
          if (info.cli && !info.done) { root.showSetup(); return }
        }
        root.integLoaded = true
      }
    }
  }

  Process { id: skipProc; command: [root.cli, "setup", "--done"] }

  Process {
    id: setupProc
    property string last: ""
    stderr: SplitParser { onRead: line => setupProc.last = line.replace(/^startappimage: /, "") }
    onStarted: setupProc.last = ""
    onExited: code => {
      root.setupBusy = false
      root.close()
      root.say(code === 0 ? "Setup saved" : (setupProc.last !== "" ? setupProc.last : "Setup could not be saved"), code !== 0)
    }
  }

  Process {
    id: checkProc
    command: [root.cli, "check", "--json"]
    stdout: StdioCollector {
      onStreamFinished: {
        var found = ({})
        try {
          JSON.parse(text).forEach(function (u) { found[u.id] = u.latest })
        } catch (e) {}
        root.updates = found
        root.announce()
      }
    }
    onExited: root.checking = false
  }

  Process {
    id: locProc
    command: [root.cli, "locations"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.locations = JSON.parse(text) } catch (e) { root.locations = ({ "default": "", "options": [] }) }
        root.locationsReady = true
        root.chooseDir()
      }
    }
  }

  Process {
    id: cfgProc
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          root.cfg = JSON.parse(text)
          root.settingsState = "ready"
        } catch (e) {
          root.settingsError = "Could not read this app's settings."
          root.settingsState = "ready"
        }
      }
    }
  }

  Process {
    id: resolveProc
    property string asked: ""
    function start() { asked = root.resolveWanted; command = [root.cli, "resolve", asked]; running = true }
    stdout: StdioCollector {
      onStreamFinished: {
        var r = ({})
        try { r = JSON.parse(text) } catch (e) { r = ({ ok: false, kind: "network", error: "Could not check this source" }) }
        if (resolveProc.asked === root.resolveWanted) { root.resolved = r; root.resolveAsked = resolveProc.asked }
      }
    }
    // The field changed while this ran: ask again with the newest text.
    onExited: if (root.resolveWanted !== "" && root.resolveWanted !== resolveProc.asked) resolveProc.start()
  }

  Process {
    id: setProc
    stderr: SplitParser { onRead: line => root.settingsError = line.replace(/^startappimage: /, "") }
    onExited: code => {
      root.settingsState = "ready"
      if (code === 0) {
        root.view = "manager"
        root.say("Saved", false)
        root.refresh()
        root.check()
      } else if (root.settingsError === "") {
        root.settingsError = "Could not save the settings."
      }
    }
  }

  Process {
    id: infoProc
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          root.meta = JSON.parse(text)
          root.installState = "ready"
          root.chooseDir()
        } catch (e) {
          root.installLog = "Could not read this file."
          root.installState = "failed"
        }
      }
    }
    stderr: SplitParser { onRead: line => root.installLog += line + "\n" }
    onExited: code => { if (code !== 0) root.installState = "failed" }
  }

  Process {
    id: installProc
    stdout: SplitParser {
      onRead: line => {
        root.installLog += line + "\n"
        var m = line.match(/^Installed .* \((.+)\)$/)
        if (m) root.installedId = m[1]
      }
    }
    stderr: SplitParser { onRead: line => root.installLog += line + "\n" }
    onExited: code => {
      root.installState = code === 0 ? "done" : "failed"
      root.refresh()
      root.check()
    }
  }

  Process {
    id: removeProc
    stdout: SplitParser { onRead: line => root.installLog += line + "\n" }
    stderr: SplitParser { onRead: line => root.installLog += line + "\n" }
    onExited: code => {
      root.installState = code === 0 ? "removed" : "failed"
      root.refresh()
      root.check()
    }
  }

  Process {
    id: actionProc
    property string done: ""
    property string last: ""
    stdout: SplitParser { onRead: line => actionProc.last = line }
    stderr: SplitParser { onRead: line => actionProc.last = line }
    onExited: code => {
      root.busyId = ""
      root.say(code === 0 ? done : (last !== "" ? last : "Something went wrong"), code !== 0)
      root.refresh()
      root.check()
    }
  }

  // ---- background update check --------------------------------------------------------
  function announce() {
    var fresh = []
    for (var id in root.updates) {
      if (root.notified[id] !== root.updates[id]) fresh.push(id)
    }
    if (fresh.length === 0) return
    var next = Object.assign({}, root.notified)
    fresh.forEach(function (id) { next[id] = root.updates[id] })
    root.notified = next
    if (root.shown) return
    notifyProc.command = ["notify-send", "-a", "StartAppImage", "-i", "startappimage",
      "-A", "update=Update", "-A", "open=Open manager",
      fresh.length === 1 ? "Update available" : fresh.length + " updates available",
      fresh.map(function (id) { return id + " " + root.updates[id] }).join(", ")]
    notifyProc.running = true
  }

  // notify-send -A prints the chosen action when the popup is clicked, then exits.
  Process {
    id: notifyProc
    stdout: StdioCollector {
      onStreamFinished: {
        var choice = text.trim()
        if (choice === "update") root.updateAll()
        else if (choice === "open") root.showManager()
      }
    }
  }

  Timer { interval: 20000; running: root.checkHours > 0; onTriggered: root.check() }
  // Once the shell has settled, offer setup if it has never been answered.
  Timer { interval: 4000; running: true; onTriggered: { root.offerSetup = true; integProc.running = true } }
  // Hours between background checks; 0 turns them off. Set on the setup card.
  readonly property int checkHours: root.integ.checkHours !== undefined ? root.integ.checkHours : 6
  Timer { interval: Math.max(1, root.checkHours) * 60 * 60 * 1000; running: root.checkHours > 0; repeat: true; onTriggered: root.check() }
  Timer { id: noticeTimer; interval: 6000; onTriggered: root.notice = "" }

  // ---- the window ------------------------------------------------------------------------
  PanelWindow {
    id: win
    visible: root.shown && root.ready
    screen: root.targetScreen
    color: "transparent"
    anchors.left: true
    anchors.right: true
    anchors.top: true
    anchors.bottom: true
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-startappimage"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // Click outside the card to dismiss it.
    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
      MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    RectangularShadow {
      anchors.fill: frame
      radius: frame.radius
      blur: root.shadow
      offset.y: Style.space(4)
      color: Qt.rgba(0, 0, 0, 0.6)
    }

    Rectangle {
      id: frame
      anchors.centerIn: parent
      width: root.view === "manager" ? Style.space(640) : Style.space(520)
      height: root.view === "install" ? installView.implicitHeight
        : root.view === "setup" ? setupView.implicitHeight
        : root.view === "settings" ? settingsView.implicitHeight
        : Math.max(Style.space(300), Math.min(managerView.implicitHeight, Style.space(580), (win.screen ? win.screen.height : 900) - Style.space(80)))
      radius: root.radius
      color: Color.menu.background
      border.width: Style.normalBorderWidth
      border.color: Util.alpha(Color.foreground, 0.14)
      focus: true
      Keys.onEscapePressed: { if (root.view === "settings") root.closeSettings(); else root.close() }

      // Swallow clicks so they do not reach the dismiss area behind the card.
      MouseArea { anchors.fill: parent }

      ManagerView {
        id: managerView
        anchors.fill: parent
        svc: root
        visible: root.view === "manager"
      }

      InstallView {
        id: installView
        anchors.left: parent.left
        anchors.right: parent.right
        svc: root
        visible: root.view === "install"
      }

      SettingsView {
        id: settingsView
        anchors.left: parent.left
        anchors.right: parent.right
        svc: root
        visible: root.view === "settings"
      }

      SetupView {
        id: setupView
        anchors.left: parent.left
        anchors.right: parent.right
        svc: root
        visible: root.view === "setup"
      }

      // Close button in the card's top-right corner, on every view.
      Button {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Style.spacing.lg
        anchors.rightMargin: Style.spacing.lg
        z: 10
        iconText: ""
        tooltipText: "Close"
        onClicked: root.close()
      }

      // Drop an .AppImage anywhere on the card to install it.
      DropArea {
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: drop => {
          if (!drop.hasUrls || drop.urls.length === 0) return
          var path = root.toPath(drop.urls[0])
          if (/\.appimage$/i.test(path)) root.showInstall(path)
          else root.say("Only .AppImage files can be installed", true)
        }
      }
    }
  }
}

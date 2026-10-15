// The settings window: launcher entry, file handler, command line, bar icon, update checks and
// the manager's window memory. Shown once after the plugin is enabled, and again from the
// manager's gear button. Every change applies the moment it is made, as in StartBar; a change
// that cannot be made flips back and says why. The look is SettingsWindow's.
import QtQuick
import qs.Commons
import qs.Ui

SettingsWindow {
  id: view

  property var svc
  // key -> value, what the controls show. Filled from the system by refreshVals().
  property var vals: ({})

  readonly property var integ: view.svc.integ
  readonly property bool otherHandler: !!(view.integ.handler && !view.integ.handler.ours && view.integ.handler.current)
  readonly property bool cliBlocked: !!(view.integ.cli && view.integ.cli.state === "other")

  title: "StartAppImage"
  subtitle: "SETTINGS"
  values: view.vals
  footerText: view.integ.done ? "Changes apply instantly" : "Choose what to switch on. Changes apply instantly."

  // ---- what there is to set -----------------------------------------------------
  pages: [
    { title: "General", fields: [
      { key: "launcher", type: "bool", label: "App launcher entry",
        hint: "Adds StartAppImage to the app launcher (SUPER + space) to open the manager." },
      { key: "handler", type: "choice", label: "Open .AppImage files with",
        options: [
          { value: true, label: "StartAppImage" },
          { value: false, label: view.otherHandler ? "Keep " + view.integ.handler.name : "Leave as is" }
        ],
        hint: view.otherHandler
          ? "Today these files open with " + view.integ.handler.name + ". StartAppImage takes over and remembers it; switching this off later gives it back."
          : "Double-clicking an AppImage shows the install card." },
      { key: "cli", type: "bool", label: "Command line", disabled: view.cliBlocked,
        hint: view.cliBlocked
          ? view.integ.cli.path + " already exists and is not StartAppImage, so it is left alone."
          : "Links " + (view.integ.cli ? view.integ.cli.path : "") + " so you can run startappimage in a terminal." }
    ] },
    { title: "Bar", fields: [
      { key: "barIcon", type: "bool", label: "Bar icon",
        hint: "An icon on the Omarchy bar that opens the manager and lights up when an update is waiting. You can drag it around the bar." }
    ] },
    { title: "Updates", fields: [
      { key: "hours", type: "choice", label: "Check for updates",
        options: [
          { value: 1, label: "Hourly" }, { value: 6, label: "6 hours" }, { value: 24, label: "Daily" },
          { value: 168, label: "Weekly" }, { value: 0, label: "Never" }
        ],
        hint: "Apps installed from a GitHub release are checked in the background, and a popup offers the update when a new version is out." }
    ] },
    { title: "Window", fields: [
      { key: "rsize", type: "bool", label: "Remember size",
        hint: "The manager reopens at the size you gave it. Drag its bottom-right corner to resize." },
      { key: "rpos", type: "bool", label: "Remember position",
        hint: "The manager reopens where you left it. Drag its top strip to move it. Switched off, it opens centred." }
    ] }
  ]

  // The command-line options that make each setting happen.
  readonly property var flags: ({
    launcher: "--launcher", handler: "--handler", cli: "--cli", barIcon: "--bar-icon",
    hours: "--check-hours", rsize: "--remember-size", rpos: "--remember-position"
  })

  onChanged: function (key, value) {
    var next = Object.assign({}, view.vals)
    next[key] = value
    view.vals = next
    view.svc.applySetting([view.flags[key], String(value)])
  }

  // What is switched on right now, read back from the system.
  function refreshVals() {
    var i = view.integ
    if (!i.cli) return
    view.vals = { launcher: i.launcher, handler: i.handler.ours, cli: i.cli.state === "ours",
      barIcon: i.barIcon, hours: i.checkHours, rsize: i.rememberSize, rpos: i.rememberPosition }
  }
  onVisibleChanged: if (visible) { view.reset(); view.confirmingReset = false; view.refreshVals() }
  Connections {
    target: view.svc
    // Not while changes are still being made: the read-back would undo a click.
    function onIntegChanged() { if (view.visible && !view.svc.setupBusy) view.refreshVals() }
  }

  // The recommended set, in one go: what a first run offers, and what Reset goes back to.
  property bool confirmingReset: false
  Timer { id: resetTimer; interval: 3000; onTriggered: view.confirmingReset = false }
  function applyDefaults() {
    var v = { launcher: true, handler: true, cli: !view.cliBlocked, barIcon: false, hours: 6, rsize: true, rpos: true }
    view.vals = v
    var args = []
    for (var k in v) args.push(view.flags[k], String(v[k]))
    view.svc.applySetting(args)
  }

  // ---- footer ----------------------------------------------------------------------------
  // A first run offers the recommended set in one click, or to leave it for later.
  SettingsPill {
    visible: !view.integ.done
    text: "Not now"
    onClicked: view.svc.skipSetup()
  }
  SettingsPill {
    visible: !view.integ.done
    text: "Enable recommended"
    primary: true
    onClicked: view.applyDefaults()
  }
  // Afterwards, the one quiet way back.
  SettingsPill {
    visible: !!view.integ.done
    text: view.confirmingReset ? "Click again to reset everything" : "Reset to defaults"
    danger: view.confirmingReset
    onClicked: {
      if (view.confirmingReset) { view.confirmingReset = false; resetTimer.stop(); view.applyDefaults() }
      else { view.confirmingReset = true; resetTimer.restart() }
    }
  }
}

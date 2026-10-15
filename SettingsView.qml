// One app's settings: name, launch options, whether it shows in the app launcher, where updates
// come from, and which folder it lives in. The look is SettingsWindow's, the same as the main
// settings window. Every change applies the moment it is made (text boxes on Enter or when they
// lose focus), and goes to `startappimage set`.
import QtQuick
import qs.Commons
import qs.Ui

SettingsWindow {
  id: view

  property var svc
  readonly property var cfg: view.svc.cfg
  readonly property bool ready: view.svc.settingsState === "ready"

  title: view.cfg.name || ""
  subtitle: "SETTINGS" + (view.cfg.version && view.cfg.version !== "local" ? "  \u00b7  " + view.cfg.version : "")
  // The icon comes from the list of apps, which knows it even when the window was opened by command.
  titleIcon: {
    var id = view.svc.settingsApp.id
    var found = view.svc.apps.filter(function (a) { return a.id === id })[0]
    return (found && found.icon) || view.svc.settingsApp.icon || ""
  }
  footerText: "Changes apply instantly"

  // key -> value, what the controls show: read from the app's settings, and nudged at once when
  // a switch or choice is clicked so it does not wait for the read-back.
  property var vals: ({})
  values: view.vals

  function repoOf(src) { return src && src.indexOf("github:") === 0 ? src.substring(7) : "" }

  function refreshVals() {
    var c = view.cfg
    view.vals = { name: c.name || "", show: c.hidden !== true, args: c.args || "",
      source: view.repoOf(c.source), dir: c.dir || "", folder: "" }
  }
  onVisibleChanged: if (visible) {
    view.reset()
    view.refreshVals()
    view.sourceText = view.vals.source
    view.folderText = ""
    view.svc.resolveSource(view.sourceText)
  }
  Connections {
    target: view.svc
    function onCfgChanged() { if (view.visible && !view.svc.settingsBusy) view.refreshVals() }
    function onSettingsBusyChanged() { if (view.visible && !view.svc.settingsBusy) view.refreshVals() }
  }

  // ---- update source: any link form is accepted and previewed ----------------
  property string sourceText: ""
  readonly property bool sourceFresh: view.sourceText.trim() !== "" && view.svc.resolveAsked === view.sourceText.trim()
  readonly property var res: view.sourceFresh ? view.svc.resolved : ({})
  // "empty" | "checking" | "ok" | "error" (not saved) | "warn" (GitHub unreachable, saved anyway)
  readonly property string sourceState: view.sourceText.trim() === "" ? "empty"
    : !view.sourceFresh ? "checking"
    : view.res.ok ? "ok"
    : view.res.kind === "network" ? "warn" : "error"
  Timer { id: resolveTimer; interval: 450; onTriggered: view.svc.resolveSource(view.sourceText) }

  // A committed source waits for the check of what was typed, then is saved if it passed.
  property bool sourcePending: false
  onSourceStateChanged: if (view.sourcePending && view.sourceState !== "checking") view.saveSource()
  function saveSource() {
    view.sourcePending = false
    var st = view.sourceState
    if (st === "error" || st === "checking") return
    var next = st === "ok" ? view.res.repo : st === "warn" ? view.sourceText.trim() : ""
    if (next !== view.repoOf(view.cfg.source)) view.apply(["--source", next])
  }

  // ---- folder: checked as you type, and a pasted link is spotted ---------------
  property string folderText: ""
  readonly property string folderError: {
    var t = view.folderText.trim()
    if (t === "") return ""
    if (/^(https?:\/\/|github[:.])/i.test(t)) return "That looks like a link, not a folder. Paste it under Updates instead."
    if (t === "~" || t.indexOf("~/") === 0 || t.indexOf(view.svc.home + "/") === 0) return ""
    return "The folder must be inside your home directory."
  }

  // What the last change said when it failed, next to the setting it was about.
  readonly property string saveError: view.svc.settingsError
  function errorFor(re) { return re.test(view.saveError) ? view.saveError : "" }
  readonly property string sourceSaveError: view.errorFor(/source/i)
  readonly property string folderSaveError: view.sourceSaveError === "" ? view.errorFor(/folder/i) : ""
  readonly property string otherSaveError: view.saveError !== "" && view.sourceSaveError === "" && view.folderSaveError === "" ? view.saveError : ""

  function apply(args) { view.svc.applyAppSetting(args) }

  // ---- what there is to set -----------------------------------------------------
  readonly property var folderOptions: view.svc.locationOptions.map(function (o) {
    return { value: o.path, label: view.svc.short(o.path) + (o.apps > 0 ? "  ·  " + o.apps : "") }
  })

  function sourceNote() {
    if (view.sourceSaveError !== "") return { kind: "bad", text: view.sourceSaveError }
    switch (view.sourceState) {
    case "checking": return { kind: "muted", text: "Checking..." }
    case "ok": return { kind: "ok", text: "✓ " + view.res.repo + "  ·  latest " + view.res.tag + "\n" + view.res.asset
        + (view.svc.checkHours > 0 ? "  ·  checked every " + (view.svc.checkHours === 1 ? "hour" : view.svc.checkHours + " hours") : "") }
    case "warn": return { kind: "muted", text: view.res.error + ". It will be saved as typed and checked later." }
    case "error": return { kind: "bad", text: view.res.error || "" }
    }
    return { kind: "muted", text: "" }
  }

  pages: [
    { title: "General", fields: [
      { key: "name", type: "text", label: "Name", hint: "Shown in the app launcher and the manager.",
        placeholder: "Name in the app launcher",
        note: view.otherSaveError !== "" ? { kind: "bad", text: view.otherSaveError }
          : view.cfg.external === true ? { kind: "muted", text: "Installed outside StartAppImage. Changes edit that app's own launcher entry." }
          : { kind: "muted", text: "" } },
      { key: "show", type: "bool", label: "Show in the app launcher",
        hint: "Switched off, the app stays installed and can still be opened from here." },
      { key: "args", type: "text", label: "Launch options", hint: "Added to the command the app launcher runs.",
        placeholder: "e.g. --ozone-platform=wayland --no-sandbox" }
    ] },
    { title: "Updates", fields: [
      { key: "source", type: "text", label: "Source",
        hint: "Releases of this GitHub repository are checked for updates. Paste any link to it, or leave empty for none.",
        placeholder: "Paste a GitHub link or owner/repo", note: view.sourceNote() }
    ] },
    { title: "Location", fields: [
      { key: "dir", type: "choice", stacked: true, label: "Folder",
        hint: "Changing the folder moves the file. " + view.svc.short(view.cfg.path || ""), options: view.folderOptions },
      { key: "folder", type: "text", label: "Another folder", placeholder: "~/Tools/AppImages  (inside your home folder)",
        hint: "Type a path and press Enter to move the app there.",
        note: view.folderError !== "" ? { kind: "bad", text: view.folderError }
          : view.folderSaveError !== "" ? { kind: "bad", text: view.folderSaveError } : { kind: "muted", text: "" } }
    ] }
  ]

  onEdited: function (key, text) {
    if (key === "source") { view.sourceText = text; resolveTimer.restart() }
    else if (key === "folder") view.folderText = text
  }

  onChanged: function (key, value) {
    var next = Object.assign({}, view.vals)
    next[key] = value
    switch (key) {
    case "name":
      if (value.trim() !== "") view.apply(["--name", value.trim()])
      break
    case "args":
      view.apply(["--args", value.trim()])
      break
    case "show":
      view.vals = next
      view.apply(["--hidden", value ? "false" : "true"])
      break
    case "dir":
      view.vals = next
      view.apply(["--dir", value])
      break
    case "folder":
      view.folderText = value
      if (view.folderError === "" && value.trim() !== "") view.apply(["--dir", value.trim()])
      break
    case "source":
      view.sourceText = value
      view.sourcePending = true
      view.svc.resolveSource(value)
      if (view.sourceState !== "checking") view.saveSource()
      break
    }
  }
}

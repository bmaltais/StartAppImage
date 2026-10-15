// Per-app settings: name, folder, launch options, update source, launcher visibility.
// Only what changed is sent to `startappimage set`.
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Item {
  id: view

  property var svc
  property bool custom: false
  property string dir: ""
  property bool hidden: false

  readonly property var cfg: view.svc.cfg
  readonly property bool ready: view.svc.settingsState === "ready"

  implicitHeight: col.implicitHeight + Style.spacing.panelPadding * 2

  function repoOf(src) { return src && src.indexOf("github:") === 0 ? src.substring(7) : "" }

  // ---- update source: any link form is accepted and previewed ----------------
  readonly property string sourceText: sourceField.text.trim()
  readonly property bool sourceFresh: view.sourceText !== "" && view.svc.resolveAsked === view.sourceText
  readonly property var res: view.sourceFresh ? view.svc.resolved : ({})
  // "empty" | "checking" | "ok" | "error" (stops a save) | "warn" (GitHub unreachable, saves anyway)
  readonly property string sourceState: view.sourceText === "" ? "empty"
    : !view.sourceFresh ? "checking"
    : view.res.ok ? "ok"
    : view.res.kind === "network" ? "warn" : "error"
  // What is saved: the normalised owner/repo when it resolved, else the text as typed.
  readonly property string sourceValue: view.sourceState === "ok" ? view.res.repo : view.sourceText

  // ---- folder: checked as you type, and a pasted link is spotted ---------------
  readonly property string folderText: folderField.text.trim()
  readonly property bool folderIsLink: /^(https?:\/\/|github[:.])/i.test(view.folderText)
  readonly property string folderError: {
    if (!view.custom || view.folderText === "") return ""
    if (view.folderIsLink) return "That looks like a link, not a folder."
    var t = view.folderText
    if (t === "~" || t.indexOf("~/") === 0 || t.indexOf(view.svc.home + "/") === 0) return ""
    return "The folder must be inside your home directory."
  }
  // Errors from `set` go next to the field they are about.
  readonly property string saveError: view.svc.settingsError
  readonly property string sourceSaveError: /source/i.test(view.saveError) ? view.saveError : ""
  readonly property string folderSaveError: !view.sourceSaveError && /folder/i.test(view.saveError) ? view.saveError : ""
  readonly property string otherSaveError: view.saveError !== "" && !view.sourceSaveError && !view.folderSaveError ? view.saveError : ""
  readonly property bool canSave: view.ready && view.sourceState !== "checking" && view.sourceState !== "error" && view.folderError === ""

  Timer { id: resolveTimer; interval: 450; onTriggered: view.svc.resolveSource(sourceField.text) }

  function load() {
    nameField.text = view.cfg.name || ""
    argsField.text = view.cfg.args || ""
    sourceField.text = view.repoOf(view.cfg.source)
    view.svc.resolveSource(sourceField.text)
    folderField.text = ""
    view.dir = view.cfg.dir || ""
    view.custom = false
    view.hidden = view.cfg.hidden === true
  }

  function save() {
    if (!view.canSave) return
    var out = []
    var name = nameField.text.trim()
    if (name !== "" && name !== view.cfg.name) out.push("--name", name)
    var dir = view.custom ? folderField.text.trim() : view.dir
    if (dir !== "" && dir !== view.cfg.dir) out.push("--dir", dir)
    if (argsField.text.trim() !== (view.cfg.args || "")) out.push("--args", argsField.text.trim())
    if (view.sourceValue !== view.repoOf(view.cfg.source)) out.push("--source", view.sourceValue)
    if (view.hidden !== (view.cfg.hidden === true)) out.push("--hidden", view.hidden ? "true" : "false")
    if (out.length === 0) view.svc.closeSettings()
    else view.svc.saveSettings(out)
  }

  onVisibleChanged: if (visible) { view.load(); nameField.focusInput() }
  Connections {
    target: view.svc
    function onCfgChanged() { if (view.visible) view.load() }
  }

  component Label: Text {
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1
  }
  component Note: Text {
    property bool bad: false
    Layout.fillWidth: true
    color: bad ? Color.urgent : Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    wrapMode: Text.Wrap
  }
  component Hint: Text {
    Layout.fillWidth: true
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    wrapMode: Text.Wrap
  }

  ColumnLayout {
    id: col
    anchors.fill: parent
    anchors.margins: Style.spacing.panelPadding
    spacing: Style.spacing.panelGap

    // Which app
    RowLayout {
      Layout.fillWidth: true
      Layout.rightMargin: Style.space(28)
      spacing: Style.spacing.xxl

      Item {
        Layout.preferredWidth: Style.space(40)
        Layout.preferredHeight: Style.space(40)
        Image {
          id: icon
          anchors.fill: parent
          source: view.svc.settingsApp.icon ? "file://" + view.svc.settingsApp.icon : ""
          sourceSize.width: Style.space(80)
          sourceSize.height: Style.space(80)
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          visible: status === Image.Ready
        }
        Rectangle {
          anchors.fill: parent
          visible: !icon.visible
          radius: Style.space(8)
          color: Util.alpha(Color.foreground, 0.10)
          Text {
            anchors.centerIn: parent
            text: (view.cfg.name || "?").charAt(0).toUpperCase()
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
          }
        }
      }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        Text {
          Layout.fillWidth: true
          text: view.cfg.name || ""
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
          font.bold: true
          elide: Text.ElideRight
        }
        Label { text: "SETTINGS" + (view.cfg.version && view.cfg.version !== "local" ? "  ·  " + view.cfg.version : "") }
      }
    }

    Hint {
      visible: view.cfg.external === true
      text: "Installed outside StartAppImage. Changes edit that app's own launcher entry."
    }

    // Name
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.md
      Label { text: "NAME" }
      Field {
        id: nameField
        Layout.fillWidth: true
        placeholder: "Name in the app launcher"
        onAccepted: view.save()
      }
    }

    // Source: where updates come from. One field takes any link form.
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.md
      Label { text: "SOURCE" }
      Field {
        id: sourceField
        Layout.fillWidth: true
        placeholder: "Paste a GitHub link or owner/repo"
        onTextChanged: if (view.visible) resolveTimer.restart()
        onAccepted: view.save()
      }
      Note {
        visible: view.sourceState === "empty"
        text: "Not updated automatically. Paste a link to the app's GitHub releases page to be told when a new version is out."
      }
      Note { visible: view.sourceState === "checking"; text: "Checking..." }
      Note {
        visible: view.sourceState === "ok"
        text: "\u2713 " + view.res.repo + "  \u00b7  latest " + view.res.tag + "\n" + view.res.asset
          + (view.svc.checkHours > 0 ? "  \u00b7  checked every " + (view.svc.checkHours === 1 ? "hour" : view.svc.checkHours + " hours") : "")
      }
      Note { visible: view.sourceState === "warn"; text: view.res.error + ". It will be saved as typed and checked later." }
      Note { visible: view.sourceState === "error"; bad: true; text: view.res.error }
      Note { visible: view.sourceSaveError !== ""; bad: true; text: view.sourceSaveError }
      Button {
        visible: view.sourceState !== "empty"
        text: "Remove source"
        bordered: true
        onClicked: sourceField.text = ""
      }
    }

    // Location
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.md
      Label { text: "LOCATION" }
      Flow {
        Layout.fillWidth: true
        spacing: Style.spacing.md
        Repeater {
          model: view.svc.locationOptions
          delegate: Chip {
            label: view.svc.short(modelData.path) + (modelData.apps > 0 ? "  ·  " + modelData.apps : "")
            selected: !view.custom && view.dir === modelData.path
            onClicked: { view.custom = false; view.dir = modelData.path }
          }
        }
        Chip {
          label: "Other folder..."
          selected: view.custom
          onClicked: { view.custom = true; folderField.focusInput() }
        }
      }
      Field {
        id: folderField
        Layout.fillWidth: true
        visible: view.custom
        placeholder: "~/Tools/AppImages  (inside your home folder)"
        onAccepted: view.save()
      }
      Note { visible: view.folderError !== ""; bad: true; text: view.folderError }
      Button {
        visible: view.custom && view.folderIsLink
        text: "Use it as the update source instead"
        bordered: true
        onClicked: { sourceField.text = folderField.text.trim(); folderField.text = ""; view.custom = false }
      }
      Note { visible: view.folderSaveError !== ""; bad: true; text: view.folderSaveError }
      Hint { text: "Changing the folder moves the file. " + view.svc.short(view.cfg.path || "") }
    }

    // Launch options
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.md
      Label { text: "LAUNCH OPTIONS" }
      Field {
        id: argsField
        Layout.fillWidth: true
        placeholder: "e.g. --ozone-platform=wayland --no-sandbox"
        onAccepted: view.save()
      }
      Hint { text: "Added to the command the app launcher runs." }
    }

    // Launcher visibility
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.md
      Label { text: "IN THE APP LAUNCHER" }
      Row {
        spacing: Style.spacing.md
        Chip { label: "Shown"; selected: !view.hidden; onClicked: view.hidden = false }
        Chip { label: "Hidden"; selected: view.hidden; onClicked: view.hidden = true }
      }
    }

    Text {
      Layout.fillWidth: true
      visible: view.otherSaveError !== ""
      text: view.otherSaveError
      color: Color.urgent
      wrapMode: Text.Wrap
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.lg
      Item { Layout.fillWidth: true }
      Button {
        text: "Cancel"
        bordered: true
        onClicked: view.svc.closeSettings()
      }
      Button {
        text: view.svc.settingsState === "saving" ? "Saving..." : "Save"
        selected: true
        opacity: view.canSave ? 1 : 0.4
        onClicked: view.save()
      }
    }
  }
}

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

  function load() {
    nameField.text = view.cfg.name || ""
    argsField.text = view.cfg.args || ""
    sourceField.text = view.repoOf(view.cfg.source)
    folderField.text = ""
    view.dir = view.cfg.dir || ""
    view.custom = false
    view.hidden = view.cfg.hidden === true
  }

  function save() {
    if (!view.ready) return
    var out = []
    var name = nameField.text.trim()
    if (name !== "" && name !== view.cfg.name) out.push("--name", name)
    var dir = view.custom ? folderField.text.trim() : view.dir
    if (dir !== "" && dir !== view.cfg.dir) out.push("--dir", dir)
    if (argsField.text.trim() !== (view.cfg.args || "")) out.push("--args", argsField.text.trim())
    if (sourceField.text.trim() !== view.repoOf(view.cfg.source)) out.push("--source", sourceField.text.trim())
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

    // Update source
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.md
      Label { text: "UPDATE SOURCE" }
      Field {
        id: sourceField
        Layout.fillWidth: true
        placeholder: "GitHub owner/repo"
        onAccepted: view.save()
      }
      Hint { text: "Releases of this GitHub repository are checked for updates. Leave empty for none." }
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
      visible: view.svc.settingsError !== ""
      text: view.svc.settingsError
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
        onClicked: view.save()
      }
    }
  }
}

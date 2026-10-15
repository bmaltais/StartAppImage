// Setup: the three pieces of desktop integration, each switched on or off on its own.
// Shown once after the plugin is enabled, and again from the manager's setup button.
// Nothing is changed until Apply.
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Item {
  id: view

  property var svc
  property bool launcher: true
  property bool handler: true
  property bool cli: true

  readonly property var integ: view.svc.integ
  readonly property bool otherHandler: !!(view.integ.handler && !view.integ.handler.ours && view.integ.handler.current)
  readonly property bool cliBlocked: !!(view.integ.cli && view.integ.cli.state === "other")

  implicitHeight: col.implicitHeight + Style.spacing.panelPadding * 2

  // First time: everything on. Replacing another app's role is safe because the
  // previous one is remembered and given back when this is switched off.
  // Afterwards: what is switched on right now.
  function load() {
    var i = view.integ
    if (!i.cli) return
    if (i.done) {
      view.launcher = i.launcher
      view.handler = i.handler.ours
      view.cli = i.cli.state === "ours"
    } else {
      view.launcher = true
      view.handler = true
      view.cli = !view.cliBlocked
    }
  }
  onVisibleChanged: if (visible) view.load()
  Connections {
    target: view.svc
    function onIntegChanged() { if (view.visible) view.load() }
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

    RowLayout {
      Layout.fillWidth: true
      Layout.rightMargin: Style.space(28)
      spacing: Style.spacing.xxl
      Image {
        source: Qt.resolvedUrl("assets/startappimage.svg")
        sourceSize.width: Style.space(64)
        sourceSize.height: Style.space(64)
        Layout.preferredWidth: Style.space(32)
        Layout.preferredHeight: Style.space(32)
      }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        Text {
          text: "Set up StartAppImage"
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
          font.bold: true
        }
        Label { text: "CHOOSE WHAT TO SWITCH ON" }
      }
    }

    // App launcher
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.md
      Label { text: "APP LAUNCHER ENTRY" }
      Row {
        spacing: Style.spacing.md
        Chip { label: "On"; selected: view.launcher; onClicked: view.launcher = true }
        Chip { label: "Off"; selected: !view.launcher; onClicked: view.launcher = false }
      }
      Hint { text: "Adds StartAppImage to the app launcher (SUPER + space) to open the manager." }
    }

    // File handler
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.md
      Label { text: "OPEN .APPIMAGE FILES" }
      Row {
        spacing: Style.spacing.md
        Chip { label: "With StartAppImage"; selected: view.handler; onClicked: view.handler = true }
        Chip { label: view.otherHandler ? "Keep " + view.integ.handler.name : "Leave as is"; selected: !view.handler; onClicked: view.handler = false }
      }
      Hint {
        text: view.otherHandler
          ? "Today these files open with " + view.integ.handler.name + ". StartAppImage will take over and remember it; switching this off later gives it back."
          : "Double-clicking an AppImage shows the install card."
      }
    }

    // Command line
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.md
      Label { text: "COMMAND LINE" }
      Row {
        spacing: Style.spacing.md
        Chip { label: "Add to PATH"; selected: view.cli && !view.cliBlocked; onClicked: if (!view.cliBlocked) view.cli = true }
        Chip { label: "No"; selected: !view.cli || view.cliBlocked; onClicked: view.cli = false }
      }
      Hint {
        text: view.cliBlocked
          ? (view.integ.cli.path + " already exists and is not StartAppImage, so it will be left alone.")
          : "Links " + (view.integ.cli ? view.integ.cli.path : "") + " so you can run startappimage in a terminal."
      }
    }

    Hint { text: "Only your home folder is touched, and every choice can be changed later from the setup button in the manager." }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.lg
      Item { Layout.fillWidth: true }
      Button {
        text: "Not now"
        bordered: true
        onClicked: view.svc.skipSetup()
      }
      Button {
        text: view.svc.setupBusy ? "Applying..." : "Apply"
        selected: true
        onClicked: view.svc.applySetup(view.launcher, view.handler, view.cli && !view.cliBlocked)
      }
    }
  }
}

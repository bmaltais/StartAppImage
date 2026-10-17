// The install card, shown when an .AppImage is double-clicked or dropped.
// It sizes itself to its content. Enter takes the primary action, Esc closes.
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Item {
  id: view

  property var svc
  property bool showDetails: false
  property bool confirmRemove: false
  property bool custom: false

  readonly property var meta: view.svc.meta
  readonly property string stage: view.svc.installState
  readonly property bool installed: view.meta.installed === true
  readonly property bool sameVersion: view.installed && !!view.meta.version && view.meta.version === view.meta.installedVersion
  readonly property bool failed: view.stage === "failed"
  readonly property string lastLine: {
    var lines = view.svc.installLog.trim().split("\n")
    return lines.length ? lines[lines.length - 1] : ""
  }

  implicitHeight: content.implicitHeight + Style.spacing.panelPadding * 2

  function primary() {
    if (view.confirmRemove) return
    if (view.stage === "removed") view.svc.close()
    else if (view.stage === "ready") {
      if (view.installed) view.svc.openInstalled()
      else view.svc.startInstall()
    } else if (view.stage === "done") view.svc.openInstalled()
    else if (view.failed) { if (view.svc.meta.name) view.svc.startInstall(); else view.svc.close() }
  }

  onVisibleChanged: if (visible) { view.showDetails = false; view.confirmRemove = false; view.custom = false; view.forceActiveFocus() }
  Keys.onReturnPressed: view.primary()
  Keys.onEnterPressed: view.primary()

  ColumnLayout {
    id: content
    anchors.fill: parent
    anchors.margins: Style.spacing.panelPadding
    spacing: Style.spacing.panelGap

    // App identity
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.huge

      Item {
        Layout.preferredWidth: Style.space(64)
        Layout.preferredHeight: Style.space(64)
        Image {
          id: icon
          anchors.fill: parent
          source: view.meta.icon ? "file://" + view.meta.icon : ""
          sourceSize.width: Style.space(128)
          sourceSize.height: Style.space(128)
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          visible: status === Image.Ready
        }
        Rectangle {
          anchors.fill: parent
          visible: !icon.visible
          radius: Style.space(12)
          color: Util.alpha(Color.foreground, 0.10)
          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: view.stage === "loading" ? "" : (view.meta.name || "?").charAt(0).toUpperCase()
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.display
            font.bold: true
          }
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.xs
        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: view.stage === "loading" ? "Reading AppImage..." : (view.meta.name || "Unknown app")
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          visible: !!view.meta.comment
          text: view.meta.comment || ""
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          wrapMode: Text.Wrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }
        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          visible: !!view.meta.size
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
          text: [view.meta.version ? "v" + view.meta.version.replace(/^v/, "") : "",
                 view.meta.size || "",
                 (view.meta.categories || "").split(";").filter(function (c) { return c !== "" })[0] || ""]
                .filter(function (p) { return p !== "" }).join("  ·  ")
        }
      }

      // Keeps clear of the close button in the card's corner.
      Item { Layout.preferredWidth: Style.space(12) }
    }

    // Where it comes from and where it goes
    Rectangle {
      Layout.fillWidth: true
      visible: view.stage !== "loading"
      implicitHeight: details.implicitHeight + Style.spacing.xxl * 2
      radius: Math.max(Style.cornerRadius, Style.space(6))
      color: Util.alpha(Color.foreground, 0.05)

      ColumnLayout {
        id: details
        anchors.fill: parent
        anchors.margins: Style.spacing.xxl
        spacing: Style.spacing.sm

        Text {
          textFormat: Text.PlainText
          text: "FROM"
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1
        }
        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: view.svc.short(view.meta.path || view.svc.installFile)
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideMiddle
        }
        Text {
          textFormat: Text.PlainText
          Layout.topMargin: Style.spacing.md
          text: view.stage === "ready" ? "INSTALL TO" : "INSTALLS TO"
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1
        }

        // Pick where the AppImage is kept: a folder AppImages already live in, or your own.
        Flow {
          Layout.fillWidth: true
          spacing: Style.spacing.md
          visible: view.stage === "ready"
          Repeater {
            model: view.svc.locationOptions
            delegate: Chip {
              label: view.svc.short(modelData.path) + (modelData.apps > 0 ? "  ·  " + modelData.apps : "")
              selected: !view.custom && view.svc.installDir === modelData.path
              onClicked: { view.custom = false; view.svc.installDir = modelData.path }
            }
          }
          Chip {
            label: "Other folder..."
            selected: view.custom
            onClicked: { view.custom = true; folder.forceActiveFocus(); view.svc.installDir = folder.text.trim() }
          }
        }
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(32)
          visible: view.stage === "ready" && view.custom
          radius: Math.max(Style.cornerRadius, Style.space(5))
          color: Util.alpha(Color.foreground, 0.06)
          border.width: Style.normalBorderWidth
          border.color: Util.alpha(Color.foreground, folder.activeFocus ? 0.30 : 0.12)
          TextInput {
            id: folder
            anchors.fill: parent
            anchors.leftMargin: Style.spacing.xxl
            anchors.rightMargin: Style.spacing.xxl
            verticalAlignment: TextInput.AlignVCenter
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            clip: true
            onTextChanged: if (view.custom) view.svc.installDir = text.trim()
            Keys.onReturnPressed: view.primary()
            Text {
              textFormat: Text.PlainText
              visible: folder.text === ""
              anchors.verticalCenter: parent.verticalCenter
              text: "~/Tools/AppImages  (inside your home folder)"
              color: Color.muted
              font: folder.font
            }
          }
        }
        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          visible: view.stage !== "ready"
          text: view.svc.short(view.svc.installDir || "") + "  +  an entry in the app launcher"
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideMiddle
        }
      }
    }

    // Already installed
    RowLayout {
      Layout.fillWidth: true
      visible: view.installed && view.stage === "ready"
      spacing: Style.spacing.md
      Rectangle {
        Layout.preferredWidth: Style.space(7)
        Layout.preferredHeight: Style.space(7)
        radius: width / 2
        color: Color.accent
      }
      Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        text: view.sameVersion ? "Already installed, same version."
          : (view.meta.installedVersion && view.meta.installedVersion !== "local" && view.meta.version)
            ? "Installed: " + view.meta.installedVersion + "   This file: " + view.meta.version
            : "Already installed. Replacing keeps one copy."
      }
    }

    // Progress and result
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.lg
      visible: view.stage === "installing" || view.stage === "removing" || view.stage === "done" || view.stage === "removed" || view.failed

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Style.space(4)
        radius: height / 2
        color: Util.alpha(Color.foreground, 0.10)
        visible: view.stage === "installing" || view.stage === "removing"
        clip: true
        Rectangle {
          id: slider
          width: parent.width * 0.3
          height: parent.height
          radius: height / 2
          color: Color.accent
          SequentialAnimation on x {
            running: view.stage === "installing" || view.stage === "removing"
            loops: Animation.Infinite
            NumberAnimation { from: -slider.width; to: slider.parent.width; duration: 1100; easing.type: Easing.InOutQuad }
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        color: view.failed ? Color.urgent : ((view.stage === "done" || view.stage === "removed") ? Color.accent : Color.foreground)
        text: view.failed ? "That did not work."
          : view.stage === "done" ? "Installed. It is in your app launcher now."
          : view.stage === "removed" ? "Uninstalled. The app and its launcher entry are gone."
          : view.stage === "removing" ? "Uninstalling..."
          : view.lastLine
      }

      Text {
        textFormat: Text.PlainText
        visible: view.stage !== "done" && view.stage !== "removed" && view.svc.installLog !== ""
        text: view.showDetails ? "Hide details" : "Show details"
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.underline: true
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: view.showDetails = !view.showDetails }
      }
      Rectangle {
        Layout.fillWidth: true
        visible: view.showDetails || (view.failed && view.svc.installLog !== "")
        implicitHeight: Math.min(logText.implicitHeight, Style.space(140)) + Style.spacing.xxl * 2
        radius: Math.max(Style.cornerRadius, Style.space(6))
        color: Util.alpha(Color.foreground, 0.05)
        clip: true
        Text {
          textFormat: Text.PlainText
          id: logText
          anchors.fill: parent
          anchors.margins: Style.spacing.xxl
          text: view.svc.installLog.trim()
          color: Color.muted
          wrapMode: Text.Wrap
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }
    }

    // Actions
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.lg
      visible: !view.confirmRemove

      Button {
        visible: view.stage === "ready" && view.installed
        text: "Uninstall"
        bordered: true
        foreground: Color.urgent
        onClicked: view.confirmRemove = true
      }

      Item { Layout.fillWidth: true }

      Button {
        visible: (view.stage === "ready" && !view.installed) || view.failed
        text: "Cancel"
        bordered: true
        onClicked: view.svc.close()
      }
      Button {
        visible: view.stage === "ready"
        text: "Run once"
        bordered: true
        onClicked: view.svc.runOnce()
      }
      Button {
        visible: view.stage === "ready" && view.installed
        text: view.sameVersion ? "Reinstall" : "Replace"
        bordered: true
        onClicked: view.svc.startInstall()
      }
      Button {
        visible: view.stage === "ready" || view.stage === "done" || (view.failed && !!view.meta.name)
        selected: true
        text: view.stage === "done" ? "Open"
          : view.failed ? "Retry"
          : view.installed ? "Open installed" : "Install"
        onClicked: view.primary()
      }
      Button {
        visible: view.stage === "done" || view.stage === "removed"
        text: "Done"
        bordered: true
        selected: view.stage === "removed"
        onClicked: view.svc.close()
      }
    }

    // Confirm uninstall
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.lg
      visible: view.confirmRemove

      Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: "Uninstall " + (view.meta.name || "this app") + "?"
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }
      Button {
        text: "No"
        bordered: true
        onClicked: view.confirmRemove = false
      }
      Button {
        text: "Yes, uninstall"
        bordered: true
        foreground: Color.urgent
        onClicked: { view.confirmRemove = false; view.svc.uninstallFromCard() }
      }
    }
  }
}

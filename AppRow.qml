// One installed AppImage: icon, name, a status line and its actions.
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Rectangle {
  id: row

  property var app: ({})
  property string updateTo: ""
  property bool current: false
  property bool busy: false
  property bool confirming: false

  signal openRequested()
  signal updateRequested()
  signal removeRequested()
  signal settingsRequested()
  signal selectRequested()

  function askRemove() { row.confirming = true }

  readonly property bool hasUpdate: row.updateTo !== ""
  readonly property bool hot: hover.hovered || row.current
  readonly property string source: {
    switch (row.app.sourceKind) {
    case "github": return row.app.repo
    case "url": return "from URL"
    case "external": return "added outside StartAppImage"
    }
    return "local file"
  }
  readonly property string version: (row.app.version && row.app.version !== "local") ? row.app.version : ""

  implicitHeight: Style.space(62)
  radius: Math.max(Style.cornerRadius, Style.space(6))
  color: Util.alpha(Color.foreground, row.hot ? 0.10 : 0.05)
  border.width: Style.normalBorderWidth
  border.color: row.current ? Util.alpha(Color.accent, 0.7) : Util.alpha(Color.foreground, 0.06)

  HoverHandler { id: hover }
  // A click anywhere on the row, buttons included, makes it the highlighted one.
  TapHandler { onTapped: row.selectRequested() }
  onConfirmingChanged: if (!confirming) confirmTimer.stop(); else confirmTimer.restart()
  Timer { id: confirmTimer; interval: 4000; onTriggered: row.confirming = false }

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: Style.spacing.xxl
    anchors.rightMargin: Style.spacing.lg
    spacing: Style.spacing.xxl

    // Icon, or the first letter on a tile when the app ships none.
    Item {
      Layout.preferredWidth: Style.space(36)
      Layout.preferredHeight: Style.space(36)
      Image {
        id: icon
        anchors.fill: parent
        source: row.app.icon ? "file://" + row.app.icon : ""
        sourceSize.width: Style.space(72)
        sourceSize.height: Style.space(72)
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
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: (row.app.name || "?").charAt(0).toUpperCase()
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.xxs
      RowLayout {
        id: nameRow
        Layout.fillWidth: true
        spacing: Style.spacing.lg
        Text {
          textFormat: Text.PlainText
          Layout.maximumWidth: nameRow.width - (tag.visible ? tag.width + nameRow.spacing : 0)
          text: row.app.name || row.app.id
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          font.bold: true
          elide: Text.ElideRight
        }
        // Marks apps that were installed by something other than StartAppImage.
        Rectangle {
          id: tag
          visible: row.app.external === true
          implicitWidth: tagText.implicitWidth + Style.space(10)
          implicitHeight: tagText.implicitHeight + Style.space(4)
          radius: Style.space(4)
          color: "transparent"
          border.width: Style.normalBorderWidth
          border.color: Util.alpha(Color.foreground, 0.30)
          Text {
            textFormat: Text.PlainText
            id: tagText
            anchors.centerIn: parent
            text: "EXTERNAL"
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
          }
        }
        Item { Layout.fillWidth: true }
      }
      RowLayout {
        spacing: Style.spacing.md
        Rectangle {
          Layout.preferredWidth: Style.space(7)
          Layout.preferredHeight: Style.space(7)
          radius: width / 2
          color: row.hasUpdate ? Color.accent : Util.alpha(Color.foreground, 0.35)
        }
        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          color: row.hasUpdate ? Color.accent : Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
          text: row.busy ? "Working..."
            : row.hasUpdate ? "Update available  " + (row.version || "") + " > " + row.updateTo
            : [row.version, row.source].filter(function (p) { return p !== "" }).join("  ·  ")
        }
      }
    }

    // Actions
    RowLayout {
      spacing: Style.spacing.md
      visible: !row.confirming && !row.busy

      Button {
        visible: row.hasUpdate
        text: "Update"
        selected: true
        onClicked: row.updateRequested()
      }
      Button {
        iconText: ""
        tooltipText: "Open"
        onClicked: row.openRequested()
      }
      Button {
        iconText: ""
        tooltipText: "Settings"
        onClicked: row.settingsRequested()
      }
      Button {
        iconText: ""
        tooltipText: "Uninstall"
        onClicked: row.confirming = true
      }
    }

    RowLayout {
      spacing: Style.spacing.md
      visible: row.confirming && !row.busy
      Text {
        textFormat: Text.PlainText
        text: row.app.external === true ? "Delete the app?" : "Uninstall?"
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
      Button {
        text: "Yes"
        bordered: true
        foreground: Color.urgent
        onClicked: { row.confirming = false; row.removeRequested() }
      }
      Button {
        text: "No"
        bordered: true
        onClicked: row.confirming = false
      }
    }
  }
}

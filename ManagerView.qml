// The manager: what is installed, what has an update, and a way to add more.
// Opened from the launcher. Keyboard: type to search, Up/Down to move,
// Enter opens, Ctrl+U updates, Delete uninstalls (after a confirmation).
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Item {
  id: view

  property var svc
  property string query: ""
  property int cursor: 0
  property bool adding: false

  readonly property var rows: {
    var q = view.query.trim().toLowerCase()
    return view.svc.apps.filter(function (a) {
      return q === "" || ((a.name || "") + " " + a.id).toLowerCase().indexOf(q) !== -1
    })
  }
  readonly property var currentApp: view.rows.length ? view.rows[Math.min(view.cursor, view.rows.length - 1)] : null
  readonly property string subtitle: {
    var n = view.svc.apps.length
    var parts = [n + (n === 1 ? " INSTALLED" : " INSTALLED")]
    if (view.svc.updateCount > 0) parts.push(view.svc.updateCount + (view.svc.updateCount === 1 ? " UPDATE" : " UPDATES"))
    else if (view.svc.checking) parts.push("CHECKING")
    return parts.join("  ·  ")
  }

  function move(dy) { view.cursor = Math.max(0, Math.min(view.rows.length - 1, view.cursor + dy)) }

  function currentRow() { return list.itemAtIndex(Math.min(view.cursor, Math.max(0, view.rows.length - 1))) }

  onVisibleChanged: {
    if (visible) {
      view.query = ""
      view.cursor = 0
      view.adding = false
      search.forceActiveFocus()
    }
  }
  onRowsChanged: view.cursor = Math.max(0, Math.min(view.cursor, view.rows.length - 1))

  implicitHeight: col.implicitHeight + Style.spacing.panelPadding * 2

  ColumnLayout {
    id: col
    anchors.fill: parent
    anchors.margins: Style.spacing.panelPadding
    spacing: Style.spacing.panelGap

    // Header
    RowLayout {
      Layout.fillWidth: true
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
          text: "StartAppImage"
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
          font.bold: true
        }
        Text {
          text: view.subtitle
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1
        }
      }
      Button {
        visible: view.svc.updateCount > 0
        text: "Update all"
        selected: true
        onClicked: view.svc.updateAll()
      }
      Button {
        iconText: ""
        tooltipText: "Setup: launcher, file handler, command line"
        onClicked: view.svc.showSetup()
      }
      Button {
        iconText: ""
        tooltipText: "Check for updates"
        iconSpinning: view.svc.checking
        onClicked: view.svc.check()
      }
      // Keeps clear of the close button in the card's corner.
      Item { Layout.preferredWidth: Style.space(24) }
    }

    // Search
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: Style.space(36)
      radius: height / 2
      color: Util.alpha(Color.foreground, 0.06)
      border.width: Style.normalBorderWidth
      border.color: Util.alpha(Color.foreground, search.activeFocus ? 0.30 : 0.12)

      Text {
        id: glass
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.xxxl
        anchors.verticalCenter: parent.verticalCenter
        text: ""
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
      TextInput {
        id: search
        anchors.left: glass.right
        anchors.leftMargin: Style.spacing.lg
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.xxxl
        anchors.verticalCenter: parent.verticalCenter
        color: Color.foreground
        selectionColor: Util.alpha(Color.accent, 0.4)
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        clip: true
        onTextChanged: view.query = text

        Keys.onUpPressed: view.move(-1)
        Keys.onDownPressed: view.move(1)
        Keys.onReturnPressed: if (view.currentApp) view.svc.openApp(view.currentApp)
        Keys.onEnterPressed: if (view.currentApp) view.svc.openApp(view.currentApp)
        Keys.onPressed: event => {
          if (event.key === Qt.Key_Escape && text !== "") { text = ""; event.accepted = true }
          else if (event.key === Qt.Key_Delete && text === "" && view.currentApp) { view.currentRow().askRemove(); event.accepted = true }
          else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_U && view.currentApp) {
            if (view.svc.updates[view.currentApp.id]) view.svc.updateApp(view.currentApp.id)
            event.accepted = true
          }
        }

        Text {
          visible: search.text === ""
          anchors.verticalCenter: parent.verticalCenter
          text: "Search installed apps"
          color: Color.muted
          font: search.font
        }
      }
    }

    // Section label
    Text {
      text: "APPS"
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1
      visible: view.svc.apps.length > 0
    }

    // List
    ListView {
      id: list
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.preferredHeight: contentHeight
      clip: true
      spacing: Style.spacing.lg
      model: view.rows
      visible: view.rows.length > 0
      currentIndex: view.cursor
      onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

      delegate: AppRow {
        width: ListView.view.width
        app: modelData
        current: index === view.cursor
        updateTo: view.svc.updates[modelData.id] || ""
        busy: view.svc.busyId === modelData.id || (view.svc.busyId === "*" && updateTo !== "")
        onOpenRequested: view.svc.openApp(modelData)
        onUpdateRequested: view.svc.updateApp(modelData.id)
        onRemoveRequested: view.svc.removeApp(modelData.id)
        onSettingsRequested: view.svc.showSettings(modelData)
        onSelectRequested: { view.cursor = index; search.forceActiveFocus() }
      }
    }

    // Empty state
    ColumnLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      visible: view.rows.length === 0
      Layout.preferredHeight: Style.space(130)
      spacing: Style.spacing.lg
      Item { Layout.fillHeight: true }
      Text {
        Layout.alignment: Qt.AlignHCenter
        text: view.svc.apps.length === 0 ? "No AppImages installed yet" : "No match for \"" + view.query + "\""
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        font.bold: true
      }
      Text {
        Layout.alignment: Qt.AlignHCenter
        Layout.maximumWidth: parent.width - Style.space(40)
        visible: view.svc.apps.length === 0
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: "Double-click an .AppImage in your file manager, drop one here, or add one from GitHub or a URL."
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
      Item { Layout.fillHeight: true }
    }

    // Add
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.lg
      visible: view.adding

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Style.space(34)
        radius: Math.max(Style.cornerRadius, Style.space(6))
        color: Util.alpha(Color.foreground, 0.06)
        border.width: Style.normalBorderWidth
        border.color: Util.alpha(Color.foreground, source.activeFocus ? 0.30 : 0.12)
        TextInput {
          id: source
          anchors.fill: parent
          anchors.leftMargin: Style.spacing.xxxl
          anchors.rightMargin: Style.spacing.xxxl
          verticalAlignment: TextInput.AlignVCenter
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          clip: true
          onAccepted: addButton.clicked()
          Keys.onEscapePressed: { view.adding = false; search.forceActiveFocus() }
          Text {
            visible: source.text === ""
            anchors.verticalCenter: parent.verticalCenter
            text: "GitHub link, owner/repo, download URL or /path/App.AppImage"
            color: Color.muted
            font: source.font
          }
        }
      }
      Button {
        id: addButton
        text: "Add"
        selected: true
        onClicked: {
          var s = source.text.trim()
          if (s === "") return
          view.svc.addSource(s)
          source.text = ""
          view.adding = false
          search.forceActiveFocus()
        }
      }
    }

    // Footer: add button on the left, the latest message or a hint on the right
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.xxl

      Button {
        text: "+  Add AppImage..."
        bordered: true
        onClicked: { view.adding = !view.adding; if (view.adding) source.forceActiveFocus(); else search.forceActiveFocus() }
      }
      Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
        text: view.svc.notice !== "" ? view.svc.notice : "Esc to close"
        color: view.svc.notice !== "" && view.svc.noticeIsError ? Color.urgent : Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
}

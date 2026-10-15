// Settings: pages on the left, the settings of the chosen page on the right, laid out like
// the StartBar settings window. Shown once after the plugin is enabled, and again from the
// manager's gear button. Every change applies the moment it is made, as in StartBar; a change
// that cannot be made flips back and says why.
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Item {
  id: view

  property var svc
  // The page shown (an index into pages) and what is typed in the search box.
  property int page: 0
  property string query: ""
  readonly property bool searching: view.query.trim() !== ""
  // key -> value, what the controls show. Filled from the current state by load().
  property var vals: ({})

  readonly property var integ: view.svc.integ
  readonly property bool otherHandler: !!(view.integ.handler && !view.integ.handler.ours && view.integ.handler.current)
  readonly property bool cliBlocked: !!(view.integ.cli && view.integ.cli.state === "other")

  implicitHeight: Style.space(520)

  // ---- what there is to set -----------------------------------------------------
  readonly property var pages: [
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

  function matches(field) {
    var q = view.query.trim().toLowerCase()
    return (field.label + " " + (field.hint || "")).toLowerCase().indexOf(q) !== -1
  }
  readonly property var shownGroups: {
    if (!view.searching) return [view.pages[view.page]]
    var out = []
    for (var i = 0; i < view.pages.length; i++) {
      var fields = view.pages[i].fields.filter(view.matches)
      if (fields.length) out.push({ title: view.pages[i].title, fields: fields })
    }
    return out
  }

  // The command-line options that make each setting happen.
  readonly property var flags: ({
    launcher: "--launcher", handler: "--handler", cli: "--cli", barIcon: "--bar-icon",
    hours: "--check-hours", rsize: "--remember-size", rpos: "--remember-position"
  })

  function setValue(key, value) {
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
  onVisibleChanged: if (visible) { view.page = 0; view.query = ""; view.confirmingReset = false; view.refreshVals() }
  Connections {
    target: view.svc
    // Not while changes are still being made: the read-back would undo a click.
    function onIntegChanged() { if (view.visible && !view.svc.setupBusy) view.refreshVals() }
  }
  onPageChanged: body.contentY = 0
  onQueryChanged: body.contentY = 0

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

  readonly property color hairline: Util.alpha(Color.foreground, 0.14)
  readonly property real rowRadius: Math.max(Style.cornerRadius, Style.space(5))

  // ---- header: the search box, centred, with room for the close button ---------------
  Item {
    id: header
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: Style.space(60)

    Rectangle {
      id: searchBox
      anchors.centerIn: parent
      width: Math.min(Style.space(380), parent.width - Style.space(120))
      height: Style.space(34)
      radius: height / 2
      color: Util.alpha(Color.foreground, 0.06)
      border.width: Style.normalBorderWidth
      border.color: Util.alpha(Color.foreground, search.activeFocus ? 0.30 : 0.12)

      Text {
        id: glass
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.xxxl
        anchors.verticalCenter: parent.verticalCenter
        text: "\uF002"
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
      TextInput {
        id: search
        anchors.fill: parent
        anchors.leftMargin: Style.spacing.xxxl + glass.width + Style.spacing.md
        anchors.rightMargin: Style.spacing.xxxl
        verticalAlignment: TextInput.AlignVCenter
        color: Color.foreground
        selectionColor: Util.alpha(Color.accent, 0.4)
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        maximumLength: 64
        clip: true
        text: view.query
        onTextChanged: if (view.query !== search.text) view.query = search.text
        // Escape clears a search first, then closes the window.
        Keys.onEscapePressed: function (event) {
          if (search.text !== "") { search.text = ""; event.accepted = true } else event.accepted = false
        }
        Text {
          visible: search.text === ""
          anchors.verticalCenter: parent.verticalCenter
          text: "Find a setting"
          color: Color.muted
          font: search.font
        }
      }
    }
  }

  // ---- left: the window's name and one item per page ---------------------------------
  Item {
    id: side
    anchors.top: header.bottom
    anchors.bottom: footer.top
    anchors.left: parent.left
    anchors.leftMargin: Style.spacing.lg
    width: Style.space(190)

    Text {
      id: title
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      height: Style.space(40)
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideRight
      text: "StartAppImage"
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body + 3
      font.bold: true
    }

    Column {
      anchors.top: title.bottom
      anchors.topMargin: Style.spacing.sm
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Style.space(2)

      Repeater {
        model: view.pages

        delegate: Rectangle {
          id: nav
          required property var modelData
          required property int index
          readonly property bool current: !view.searching && view.page === nav.index
          width: parent.width
          height: Style.space(38)
          radius: view.rowRadius
          color: nav.current ? Util.alpha(Color.accent, 0.22)
            : (navHover.hovered ? Style.hoverFillFor(Color.foreground, Color.accent) : "transparent")

          // The mark beside the current page.
          Rectangle {
            visible: nav.current
            anchors.left: parent.left
            anchors.leftMargin: Style.space(3)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(3)
            height: Style.space(16)
            radius: width / 2
            color: Color.accent
          }
          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            text: nav.modelData.title
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: nav.current
          }
          HoverHandler { id: navHover }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { view.query = ""; view.page = nav.index }
          }
        }
      }
    }
  }

  // ---- right: the page heading and its settings --------------------------------------
  Text {
    id: heading
    anchors.top: header.bottom
    anchors.left: side.right
    anchors.leftMargin: Style.spacing.lg * 2
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.lg
    height: Style.space(40)
    verticalAlignment: Text.AlignVCenter
    elide: Text.ElideRight
    text: view.searching ? "Search results" : view.pages[view.page].title
    color: Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.body + 8
    font.bold: true
  }

  Flickable {
    id: body
    anchors.top: heading.bottom
    anchors.bottom: footer.top
    anchors.left: side.right
    anchors.right: parent.right
    anchors.leftMargin: Style.spacing.lg * 2
    // Room for the scroll bar's gutter, always: sizing the body by whether it scrolls
    // would change its width, and with it its height.
    anchors.rightMargin: Style.spacing.lg + Style.spacing.lg + Style.spacing.xs
    contentHeight: rows.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: rows
      width: body.width

      Text {
        visible: view.searching && view.shownGroups.length === 0
        width: rows.width
        wrapMode: Text.WordWrap
        topPadding: Style.spacing.md
        text: "No setting matches “" + view.query.trim() + "”."
        color: Util.alpha(Color.foreground, 0.7)
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      Repeater {
        model: view.shownGroups

        delegate: Column {
          id: group
          required property var modelData
          width: rows.width

          // Search results come from several pages: say which.
          Text {
            visible: view.searching
            topPadding: Style.spacing.md
            bottomPadding: Style.spacing.xs
            text: group.modelData.title
            color: Util.alpha(Color.foreground, 0.7)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Repeater {
            model: group.modelData.fields

            delegate: Item {
              id: row
              required property var modelData
              readonly property var field: row.modelData
              readonly property var value: view.vals[row.field.key]
              readonly property bool live: !row.field.disabled

              width: group.width
              opacity: row.live ? 1 : 0.4
              height: Math.max(labels.implicitHeight, editor.height) + Style.spacing.md * 2

              Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: Util.alpha(view.hairline, 0.5)
              }

              Column {
                id: labels
                anchors.top: parent.top
                anchors.topMargin: Style.spacing.md
                anchors.left: parent.left
                width: parent.width - editor.width - Style.spacing.xxl
                Text {
                  width: parent.width
                  elide: Text.ElideRight
                  text: row.field.label
                  color: Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
                Text {
                  visible: !!row.field.hint
                  width: parent.width
                  wrapMode: Text.WordWrap
                  text: row.field.hint || ""
                  color: Util.alpha(Color.foreground, 0.55)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }

              Loader {
                id: editor
                enabled: row.live
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                sourceComponent: row.field.type === "bool" ? switchEditor : choiceEditor
                onLoaded: {
                  item.field = Qt.binding(function () { return row.field })
                  item.value = Qt.binding(function () { return row.value })
                }
                Connections {
                  target: editor.item
                  ignoreUnknownSignals: true
                  function onCommit(next) { view.setValue(row.field.key, next) }
                }
              }
            }
          }
        }
      }

      Item { width: 1; height: Style.spacing.md }
    }
  }

  ScrollTrack {
    target: body
    anchors.top: body.top
    anchors.bottom: body.bottom
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.lg
    width: Style.spacing.md
  }

  // ---- footer ----------------------------------------------------------------------------
  Item {
    id: footer
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    height: Style.space(52)

    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.lg
      anchors.right: footerButtons.left
      anchors.rightMargin: Style.spacing.lg
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
      text: view.integ.done ? "Changes apply instantly" : "Choose what to switch on. Changes apply instantly."
      color: Util.alpha(Color.foreground, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Row {
      id: footerButtons
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.lg
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.lg
      // A first run offers the recommended set in one click, or to leave it for later.
      Button {
        visible: !view.integ.done
        text: "Not now"
        bordered: true
        onClicked: view.svc.skipSetup()
      }
      Button {
        visible: !view.integ.done
        text: "Enable recommended"
        selected: true
        onClicked: view.applyDefaults()
      }
      Button {
        visible: !!view.integ.done
        text: view.confirmingReset ? "Click again to reset everything" : "Reset to defaults"
        bordered: true
        onClicked: {
          if (view.confirmingReset) { view.confirmingReset = false; resetTimer.stop(); view.applyDefaults() }
          else { view.confirmingReset = true; resetTimer.restart() }
        }
      }
    }
  }

  // ---- editors: each is given `field` and `value` and emits commit(next) ----------------
  Component {
    id: switchEditor
    Rectangle {
      id: sw
      property var field: null
      property var value: false
      signal commit(var next)
      implicitWidth: Style.space(42)
      implicitHeight: Style.space(24)
      width: implicitWidth
      height: implicitHeight
      radius: height / 2
      color: sw.value ? Color.accent : Util.alpha(Color.foreground, 0.25)
      // The Loader hands over the real value just after this is created; animating only
      // once that has settled keeps the knob from sliding into place when the page opens.
      property bool settled: false
      Component.onCompleted: Qt.callLater(function () { sw.settled = true })

      Rectangle {
        width: parent.height - 6
        height: width
        radius: width / 2
        y: 3
        x: sw.value ? parent.width - width - 3 : 3
        color: Color.menu.background
        Behavior on x { enabled: sw.settled; NumberAnimation { duration: 100 } }
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: sw.commit(!sw.value)
      }
    }
  }

  Component {
    id: choiceEditor
    Row {
      id: choices
      property var field: null
      property var value: null
      signal commit(var next)
      spacing: 2

      Repeater {
        model: choices.field ? choices.field.options : []

        delegate: Rectangle {
          id: choice
          required property var modelData
          readonly property bool selected: choices.value === choice.modelData.value
          width: choiceLabel.implicitWidth + Style.spacing.lg * 2
          height: Style.space(28)
          radius: view.rowRadius
          color: choice.selected ? Color.accent
            : (choiceHover.hovered ? Style.hoverFillFor(Color.foreground, Color.accent) : Util.alpha(Color.foreground, 0.08))

          Text {
            id: choiceLabel
            anchors.centerIn: parent
            text: choice.modelData.label
            color: choice.selected ? Color.menu.background : Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          HoverHandler { id: choiceHover }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: choices.commit(choice.modelData.value)
          }
        }
      }
    }
  }
}

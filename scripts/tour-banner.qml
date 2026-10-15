// The window the tour recorder (scripts/tour.sh) puts in the middle of your real screen: red with white text,
// so it cannot be missed. First it asks you to confirm, with Proceed and Cancel buttons; then, while the tour
// is recording, it says to leave the mouse and keyboard alone and which step it is on; at the end it turns
// green and says you can use them again. It redraws in place, so it does not flicker.
//
// Run by the recorder with `quickshell -n -p scripts/tour-banner.qml`, configured by environment:
//   TOUR_MODE     "confirm" (buttons, writes the answer) or "status" (shows TOUR_STATUS as it changes)
//   TOUR_TITLE    the app's name
//   TOUR_SCREEN   the name of the monitor to appear on (the real one)
//   TOUR_ANSWER   confirm: a file that gets "proceed" or "cancel" written to it, then the window closes
//                 status (nested): a file that gets "cancel" written to it when the Cancel button is pressed
//   TOUR_STATUS   status: a file whose first line is "recording" or "done" and the rest is the text to show
//   TOUR_NESTED   "1" when the tour runs in a nested session shown in a window on the real screen. Then the status
//                 window is a strip above that window instead of a box in the middle of the screen, and a transparent
//                 shield covers the window so no click reaches it.
//   TOUR_SHIELD   nested: "X,Y,W,H", where the nested window is on the real monitor
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
  id: root

  readonly property string mode: Quickshell.env("TOUR_MODE") || "status"
  readonly property string appTitle: Quickshell.env("TOUR_TITLE") || "the app"
  property string statusText: ""
  // The first line of the status file says which state we are in: starting, recording, encoding or done.
  readonly property string state: root.statusText.split("\n")[0]
  readonly property bool done: root.state === "done"
  readonly property bool encoding: root.state === "encoding"
  readonly property bool cancelled: root.state === "cancelled"
  readonly property bool over: root.done || root.encoding || root.cancelled
  property bool cancelling: false
  readonly property string statusBody: {
    var i = root.statusText.indexOf("\n")
    return i < 0 ? "" : root.statusText.substring(i + 1).replace(/\n+$/, "")
  }

  readonly property bool nested: Quickshell.env("TOUR_NESTED") === "1"
  readonly property var shield: (Quickshell.env("TOUR_SHIELD") || "0,0,0,0").split(",").map(Number)
  readonly property color red: "#c62828"
  readonly property color green: "#2e7d32"

  function answer(what) {
    Quickshell.execDetached(["sh", "-c", "printf %s \"$1\" > \"$2\"", "sh", what, Quickshell.env("TOUR_ANSWER")])
    // The confirm window is done once it has an answer; the status window stays to show what happens next.
    if (root.mode === "confirm") Qt.quit()
    else root.cancelling = true
  }

  FileView {
    path: Quickshell.env("TOUR_STATUS")
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.statusText = text()
  }

  PanelWindow {
    id: win
    screen: {
      var name = Quickshell.env("TOUR_SCREEN")
      for (var i = 0; i < Quickshell.screens.length; i++) if (Quickshell.screens[i].name === name) return Quickshell.screens[i]
      return Quickshell.screens[0]
    }
    // Not nested: no anchors, so a layer-shell window is centred on its screen. Nested: a strip along the top, above
    // the nested window.
    anchors.top: root.nested && root.mode === "status"
    margins.top: 24
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "start-tour-banner"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.mode === "confirm" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    implicitWidth: root.nested && root.mode === "status" ? Math.max(760, root.shield[2]) : 760
    implicitHeight: root.nested && root.mode === "status" ? (root.over ? 124 : 170) : col.implicitHeight + 72
    color: "transparent"

    Rectangle {
      anchors.fill: parent
      radius: 14
      color: root.mode === "status" && root.over ? (root.cancelled ? "#555555" : root.green) : root.red
      border.width: 3
      border.color: "white"
      focus: true
      Keys.onEscapePressed: if (root.mode === "confirm") root.answer("cancel")

      Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.nested && root.mode === "status" ? 18 : 36
        spacing: root.nested && root.mode === "status" ? 8 : 18

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
          color: "white"
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: root.nested && root.mode === "status" ? 20 : 28
          font.bold: true
          text: root.mode === "confirm" ? "Record the " + root.appTitle + " tour?"
            : root.done ? "The tour is done"
            : root.cancelled ? "Recording cancelled"
            : root.encoding ? "Recording finished"
            : root.state === "starting" ? "Getting ready to record the " + root.appTitle + " tour. Not recording yet."
            : root.nested ? "Recording the " + root.appTitle + " tour. You can watch below. Your mouse and keyboard cannot reach it."
            : "Recording the " + root.appTitle + " tour"
        }

        Text {
          visible: !(root.nested && root.mode === "status") || root.over
          width: parent.width
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
          color: "white"
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: 19
          lineHeight: 1.25
          text: root.mode === "confirm"
            ? "For about two minutes a script will drive the mouse pointer and the keyboard on a virtual screen.\n\nDO NOT TOUCH THE MOUSE OR THE KEYBOARD until this window says it is done. Whatever it changes is put back afterwards."
            : root.done ? "You can use the mouse and the keyboard again."
            : root.cancelled ? "Nothing was kept. The mouse and the keyboard are yours again."
            : root.encoding ? "Building the GIF now. The mouse and the keyboard are yours again."
            : "DO NOT TOUCH THE MOUSE OR THE KEYBOARD.\nThe pointer is driving a virtual screen and typing goes there."
        }

        Text {
          visible: root.mode === "status" && !root.over && root.statusBody !== ""
          width: parent.width
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
          color: "white"
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: root.nested && root.mode === "status" ? 18 : 21
          font.bold: true
          text: root.statusBody
        }

        // Status (nested): stops the recording and puts everything back. The strip is above the shielded window, so
        // it can be clicked while the recording itself cannot be touched.
        Rectangle {
          visible: root.nested && root.mode === "status" && !root.over
          anchors.horizontalCenter: parent.horizontalCenter
          width: 190
          height: 40
          radius: 10
          color: cancelHover.hovered ? "#d84343" : "transparent"
          border.width: 3
          border.color: "white"
          Text {
            anchors.centerIn: parent
            text: root.cancelling ? "Cancelling..." : "Cancel recording"
            color: "white"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 17
            font.bold: true
          }
          HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
          TapHandler { enabled: !root.cancelling; onTapped: root.answer("cancel") }
        }

        // Confirm: Proceed says you will leave the mouse and keyboard alone; Cancel stops before anything is touched.
        Row {
          visible: root.mode === "confirm"
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: 24

          component Choice: Rectangle {
            id: choice
            property string label: ""
            property bool primary: false
            signal clicked()
            width: Math.max(180, choiceLabel.implicitWidth + 48)
            height: 52
            radius: 10
            color: choice.primary ? (hover.hovered ? "#f2f2f2" : "white") : (hover.hovered ? "#d84343" : "transparent")
            border.width: 3
            border.color: "white"
            Text {
              id: choiceLabel
              anchors.centerIn: parent
              text: choice.label
              color: choice.primary ? root.red : "white"
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: 20
              font.bold: true
            }
            HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: choice.clicked() }
          }

          Choice { label: "Proceed"; primary: true; onClicked: root.answer("proceed") }
          Choice { label: "Cancel"; onClicked: root.answer("cancel") }
        }

        Text {
          visible: root.mode === "confirm"
          width: parent.width
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
          color: "white"
          opacity: 0.85
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: 15
          text: "By pressing Proceed you confirm you will not touch them. Esc cancels."
        }
      }
    }
  }

  // Nested: a transparent window exactly over the nested session's window, above it. It takes every click and hover
  // that would otherwise reach the nested session, so only the recorder can drive it.
  PanelWindow {
    visible: root.nested && root.mode === "status" && !root.over
    screen: win.screen
    anchors.top: true
    anchors.left: true
    margins.top: root.shield[1]
    margins.left: root.shield[0]
    implicitWidth: root.shield[2]
    implicitHeight: root.shield[3]
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "start-tour-shield"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; hoverEnabled: true; cursorShape: Qt.ForbiddenCursor }
  }
}

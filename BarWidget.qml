// The optional bar icon: opens the manager, and lights up when an update is waiting.
// It is on the bar only when the user chose it on the setup card. The update count
// comes from `startappimage check`, which the plugin runs in the background.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.bmaltais.startappimage"

  readonly property string countFile: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/startappimage/updates"
  property int updates: 0

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  FileView {
    path: root.countFile
    // The file does not exist until the first update check has run (a fresh install): that is "no updates", not an error.
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.updates = parseInt(text()) || 0
    onLoadFailed: root.updates = 0
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰇚"
    active: root.updates > 0
    useActiveColor: true
    activeColor: Color.accent
    onPressed: function (mouse) {
      if (!root.bar) return
      // Right click looks for updates; left click opens the manager.
      if (mouse === Qt.RightButton) root.bar.run("startappimage check")
      else root.bar.run("omarchy-shell io.github.bmaltais.startappimage open")
    }
  }
}

// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// GET, OR OPEN — the Store's one button, in the suite's own corners.
//
// Get hands the app to the window's confirm sheet (see StoreView.changeAsked),
// so what it will install, cost and pull in is shown before anything runs.
// Open launches what is installed, through the launcher's own path
// (Desktop.launchCommand). While a job is running there is no Get: Ceres runs
// one change at a time.

import QtQuick
import "../morpheus"

Rectangle {
  id: get
  property var app: null
  property bool busy: false
  property bool big: false
  signal got()
  signal launched()

  readonly property bool have: !!get.app && !!get.app.installed
  // installed, and with a desktop id to open it by
  readonly property bool canOpen: get.have && !!get.app.launch
  readonly property bool ready: get.have ? get.canOpen : !get.busy
  readonly property string word: get.have ? (get.canOpen ? "Open" : "Installed") : "Get"

  visible: !!get.app
  implicitWidth: Math.max(get.big ? 92 : 68, getText.implicitWidth + (get.big ? 36 : 28))
  implicitHeight: get.big ? 32 : 28
  width: implicitWidth
  height: implicitHeight
  radius: Zenon.windowRadius
  color: !get.ready ? Zenon.wash(0.05)
    : getMa.pressed ? Zenon.alpha(Zenon.cyan, 0.40)
    : Zenon.alpha(Zenon.cyan, get.big ? 0.22 : 0.16)
  border.width: 1
  border.color: get.ready ? Zenon.alpha(Zenon.cyan, 0.5) : Zenon.border
  Behavior on color { ColorAnimation { duration: 110 } }

  Text {
    id: getText
    anchors.centerIn: parent
    text: get.word
    color: get.ready ? Zenon.cyan : Zenon.accentMuted
    font.family: Zenon.face
    font.weight: Font.Bold
    font.pixelSize: Zenon.px(get.big ? 16 : 14)
  }

  MouseArea {
    id: getMa
    anchors.fill: parent
    enabled: get.ready
    cursorShape: get.ready ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: get.have ? get.launched() : get.got()
  }
}

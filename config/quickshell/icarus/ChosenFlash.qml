// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ── THE ROW FLASHES, THEN THE THING HAPPENS ───────────────────────────────
// Lifted whole from terminus' context menu, which is where the argument for
// it is: a menu that disappears on mouse-down leaves you unsure which row you
// hit, and for the entries that log you out that is a bad moment to be unsure
// in. The delay is long enough to see and short enough that it is not a wait.
//
// A row hands its work over rather than doing it — `fire(act)` — so the
// action runs on the far side of the flash and every row that does something
// confirms itself the same way. Rows that merely open a submenu do NOT use
// this: nothing has happened yet, and 190ms between pointing at a branch and
// seeing it is a menu that feels slow.
//
// Its own file since the Home cards moved into HomeCard.qml: an inline
// component cannot be reached from another file, and a second copy is how
// the two would drift.

import QtQuick
import "../morpheus"

Item {
  id: flash
  anchors.fill: parent
  z: 3
  property var pending: null
  property real chosen: 0
  readonly property bool running: flashAnim.running

  function fire(act) {
    flash.pending = act;
    flashAnim.restart();
  }

  SequentialAnimation {
    id: flashAnim
    NumberAnimation { target: flash; property: "chosen"; to: 1;
                      duration: 60; easing.type: Easing.OutQuad }
    NumberAnimation { target: flash; property: "chosen"; to: 0;
                      duration: 130; easing.type: Easing.InQuad }
    ScriptAction {
      script: {
        const act = flash.pending;
        flash.pending = null;
        if (act) act();
      }
    }
  }

  Rectangle {
    anchors.fill: parent
    visible: flash.chosen > 0
    color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b,
                   0.55 * flash.chosen)
  }
}

// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A MIDDLE CLICK SCROLLS (user, 2026-10-13: "hide the cursor and show a cute,
// dynamic and animated scroller where i middle clicked") — iris' own, not
// Chromium's (whose stock icon cannot be dressed):
//
//   press and drag     scrolls while held, the release ends it
//   a click            stays on: move to scroll, click (any button), Escape
//                      or the wheel puts it away
//   on a link          left to Chromium — a middle click there opens it in a
//                      tab behind, as it always has
//
// The pointer is hidden and a puck stands where the press was: a glass disc
// in the tooltip's ground, chevrons above and below — the one the page is
// going toward lit and bobbing, faster the faster it goes — and a nub that
// leans toward the pointer as a joystick's does, so the hand still sees
// where it is. It grows in and out (Zenon's menu fade), and breathes while
// it waits in the dead zone.
//
// Speed is the distance past a small dead zone, rising faster than linear,
// so a nudge reads a line and a long reach flies. It moves whatever is under
// the press — the document or a panel in it — by precise wheels at that point
// (`wheel(x, y, dy)`, the window's: Chromium scrolls on its compositor).

import QtQuick
import QtQuick.Window
import "../morpheus"
import IrisHost

Item {
  id: as
  // the page's area, and what turns a distance into a scroll there
  required property Item area
  // function(x, y, dy): a precise wheel of dy px at (x, y) in `area`
  required property var wheel
  // whether a press at (x, y) belongs to the page (a link under it: yes)
  property var leave: null

  property bool active: false
  // its own wheels on their way to the page pass through here: let them
  property bool sending: false
  property bool held: false          // press-and-drag, rather than a click
  property point home: Qt.point(0, 0)
  property point hand: Qt.point(0, 0)
  property real pressedAt: 0
  // the dead zone, and how far the nub may lean
  readonly property int dead: 10
  readonly property int reach: 6
  readonly property real dy: as.hand.y - as.home.y
  readonly property real dx: as.hand.x - as.home.x
  readonly property real speed: {
    const d = Math.abs(as.dy) - as.dead;
    if (d <= 0) return 0;
    // px a second: a nudge ~ a line a second, a long reach ~ a page
    return Math.sign(as.dy) * Math.min(6000, 2.2 * Math.pow(d, 1.55));
  }

  anchors.fill: as.area
  z: 7

  function start(p, held) {
    as.home = p;
    as.hand = p;
    as.held = held;
    as.active = true;
    Iris.hidePointer(true);
  }
  function stop() {
    if (!as.active) return;
    as.active = false;
    Iris.hidePointer(false);
  }

  // ── THE GESTURE ────────────────────────────────────────────────────
  // Only the middle button, and only off a link; hover while on, so a click
  // that left it running still steers it.
  MouseArea {
    id: catcher
    anchors.fill: parent
    acceptedButtons: as.active ? Qt.AllButtons : Qt.MiddleButton
    hoverEnabled: as.active
    // no shape of its own: the pointer's stays the page's (a link's hand…),
    // as ElasticScroll's (undefined resets a MouseArea's cursor)
    cursorShape: undefined
    onPressed: (m) => {
      if (as.active) { m.accepted = true; as.stop(); return; }
      if (as.leave && as.leave(m.x, m.y)) { m.accepted = false; return; }
      m.accepted = true;
      as.pressedAt = Date.now();
      as.start(Qt.point(m.x, m.y), true);
    }
    onPositionChanged: (m) => { if (as.active) as.hand = Qt.point(m.x, m.y); }
    onReleased: (m) => {
      if (!as.active || !as.held) return;
      // a click, not a drag: it stays on, and the next click ends it
      const still = Math.hypot(as.dx, as.dy) < 6 && Date.now() - as.pressedAt < 350;
      if (still) as.held = false; else as.stop();
    }
    onWheel: (w) => {
      w.accepted = false;
      if (as.active && !as.sending) as.stop();
    }
  }
  Keys.onEscapePressed: as.stop()
  onActiveChanged: if (as.active) as.forceActiveFocus()

  // ── THE DRIVE ──────────────────────────────────────────────────────
  FrameAnimation {
    running: as.active
    property real owed: 0
    onTriggered: {
      owed += as.speed * Math.min(0.05, frameTime);
      const step = Math.trunc(owed);
      if (step === 0) return;
      owed -= step;
      as.sending = true;
      as.wheel(as.home.x, as.home.y, step);
      as.sending = false;
    }
  }

  // ── THE PUCK ───────────────────────────────────────────────────────
  Item {
    id: puck
    readonly property int size: 52
    x: as.home.x - puck.size / 2
    y: as.home.y - puck.size / 2
    width: puck.size
    height: puck.size
    property real shade: as.active ? 1 : 0
    Behavior on shade { NumberAnimation { duration: Zenon.menuFade; easing.type: Easing.OutCubic } }
    visible: puck.shade > 0.01
    opacity: puck.shade
    scale: 0.6 + 0.4 * puck.shade
    // which way, and how hard (0..1)
    readonly property int way: as.speed > 0 ? 1 : as.speed < 0 ? -1 : 0
    readonly property real push: Math.min(1, Math.abs(as.speed) / 2500)

    // a breath while it waits, still while it scrolls
    Rectangle {
      anchors.centerIn: parent
      width: puck.size + 10
      height: width
      radius: width / 2
      color: "transparent"
      border.width: 1.5
      border.color: Zenon.alpha(Zenon.cyan, 0.5)
      SequentialAnimation on scale {
        running: puck.visible && puck.way === 0
        loops: Animation.Infinite
        NumberAnimation { from: 0.86; to: 1.04; duration: 900; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1.04; to: 0.86; duration: 900; easing.type: Easing.InOutSine }
      }
      opacity: puck.way === 0 ? 0.9 : 0
      Behavior on opacity { NumberAnimation { duration: Zenon.fast } }
    }
    // the disc: the tooltip's glass, its border and rim
    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: Zenon.tipBg
      border.width: 1
      border.color: Zenon.border
    }
    // the nub: leans toward the pointer, stretching along the way it goes
    Rectangle {
      readonly property real len: Math.hypot(as.dx, as.dy)
      readonly property real k: len > 0 ? Math.min(as.reach, len / 4) / len : 0
      x: puck.size / 2 - width / 2 + as.dx * k
      y: puck.size / 2 - height / 2 + as.dy * k
      width: 8
      height: 8 + 4 * puck.push
      radius: 4
      color: puck.way === 0 ? Zenon.keyInk : Zenon.cyan
      Behavior on color { ColorAnimation { duration: Zenon.fast } }
    }
    // the chevrons: the way it goes lit (over the nub), bobbing with the speed
    Repeater {
      model: [-1, 1]
      Text {
        required property int modelData
        readonly property bool lit: puck.way === modelData
        property real bob: 0
        anchors.horizontalCenter: parent.horizontalCenter
        y: (modelData < 0 ? 3 : puck.size - height - 3) + modelData * bob
        text: modelData < 0 ? "\u{F0143}" : "\u{F0140}"
        color: lit ? Zenon.cyan : Zenon.muted
        opacity: lit ? 1 : 0.55
        font.family: Zenon.glyphFace
        font.pixelSize: Zenon.px(16)
        Behavior on color { ColorAnimation { duration: Zenon.fast } }
        SequentialAnimation on bob {
          running: lit && puck.visible
          loops: Animation.Infinite
          NumberAnimation { from: 0; to: 3; duration: Math.max(140, 520 - 380 * puck.push); easing.type: Easing.OutQuad }
          NumberAnimation { from: 3; to: 0; duration: Math.max(140, 520 - 380 * puck.push); easing.type: Easing.InQuad }
        }
      }
    }
  }
}

// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// CROPBOX — a crop being set up, over the picture it cuts.
//
// The rest darkened, thirds, a body that moves and grips that resize, a box
// dragged out anywhere, and the size it will be saved at. The viewer's and
// the annotator's were the same box written out twice; each now says only
// where the box is kept (`r` in, `drawn` out), the rule it keeps to (a ratio,
// or Shift for a square) and what a right click or a double click means.
//
// `r` and everything drawn are in the PICTURE's pixels; `k` is how many
// screen pixels one of them is. The caller places and sizes this item over
// the picture and decides when it is shown.

import QtQuick
import "../morpheus"
import "capture.js" as Cap
import "viewer.js" as V

Item {
  id: box

  // the box, in the picture's pixels
  property var r: ({ x: 0, y: 0, w: 1, h: 1 })
  // the picture's size, and screen pixels per picture pixel
  property real tw: 1
  property real th: 1
  property real k: 1
  // width over height to keep to, 0 for none (the viewer's ratios)
  property real ratio: 0
  // Shift held keeps it square (the annotator's rule)
  property bool shiftSquare: false
  // A right click that does not travel asks for the menu, so a right drag
  // only starts once it has gone 4px (the viewer's); without it a right
  // press resizes at once and there is no menu.
  property bool clickMenu: false

  // a new box, at least 4×4
  signal drawn(var r)
  // any press on it, so the caller can take the keys back
  signal touched()
  // a right click that went nowhere (clickMenu): at, in the window
  signal menuAsked(point at, bool onBox)
  // a double click on the box's body
  signal bodyDoubleClicked()

  function fit(r, edge, mods) {
    if (box.ratio > 0) return V.fitAspect(r, edge, box.ratio, box.tw, box.th);
    if (box.shiftSquare && (mods & Qt.ShiftModifier)) return V.fitAspect(r, edge, 1, box.tw, box.th);
    return r;
  }
  function offer(r) { if (r.w >= 4 && r.h >= 4) box.drawn(r); }

  // RIGHT-DRAG RESIZES from wherever the pointer is, as the region capture
  // does (PicassoCapture): the corner nearest it follows, so the box is
  // adjusted without finding a handle. `p` is in this item's coordinates.
  property var rr0: null
  property point rp0
  property string redge: ""
  property bool rmoved: false
  function rPress(p) {
    const r = box.r, k = box.k;
    box.rr0 = r;
    box.rp0 = p;
    box.rmoved = false;
    box.redge = (p.x / k < r.x + r.w / 2 ? "l" : "r") + (p.y / k < r.y + r.h / 2 ? "t" : "b");
  }
  function rMove(p, mods) {
    if (!box.rr0) return;
    if (box.clickMenu && !box.rmoved
        && Math.abs(p.x - box.rp0.x) < 4 && Math.abs(p.y - box.rp0.y) < 4) return;
    box.rmoved = true;
    const dx = (p.x - box.rp0.x) / box.k, dy = (p.y - box.rp0.y) / box.k;
    box.offer(box.fit(Cap.resizeRect(box.rr0, box.redge, dx, dy, box.tw, box.th), box.redge, mods));
  }
  // true when it was a click (the menu's)
  function rRelease() {
    const click = box.rr0 !== null && !box.rmoved;
    box.rr0 = null;
    return click;
  }

  // what is cut away, darkened
  Rectangle { x: 0; y: 0; width: parent.width; height: box.r.y * box.k; color: "#99000000" }
  Rectangle { x: 0; y: (box.r.y + box.r.h) * box.k; width: parent.width
              height: parent.height - y; color: "#99000000" }
  Rectangle { x: 0; y: box.r.y * box.k; width: box.r.x * box.k
              height: box.r.h * box.k; color: "#99000000" }
  Rectangle { x: (box.r.x + box.r.w) * box.k; y: box.r.y * box.k
              width: parent.width - x; height: box.r.h * box.k; color: "#99000000" }

  // a fresh box, dragged out anywhere
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.CrossCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    property real ax: 0
    property real ay: 0
    onPressed: (m) => {
      box.touched();
      if (m.button === Qt.RightButton) { box.rPress(Qt.point(m.x, m.y)); return; }
      ax = m.x / box.k; ay = m.y / box.k;
    }
    onReleased: (m) => {
      const click = box.rRelease();
      if (m.button === Qt.RightButton && click && box.clickMenu)
        box.menuAsked(mapToItem(null, m.x, m.y), false);
    }
    onPositionChanged: (m) => {
      if (box.rr0) { box.rMove(Qt.point(m.x, m.y), m.modifiers); return; }
      const cx = m.x / box.k, cy = m.y / box.k;
      box.offer(box.fit(Cap.rectOf(ax, ay, cx, cy, box.tw, box.th),
                        (cx < ax ? "l" : "r") + (cy < ay ? "t" : "b"), m.modifiers));
    }
  }

  Rectangle {
    id: cropBox
    x: box.r.x * box.k
    y: box.r.y * box.k
    width: box.r.w * box.k
    height: box.r.h * box.k
    color: "transparent"
    border.width: 1
    border.color: Zenon.cyan

    // thirds, for placing things
    Repeater {
      model: 2
      Rectangle { required property int index; x: cropBox.width * (index + 1) / 3; width: 1
                  height: cropBox.height; color: Qt.rgba(1, 1, 1, 0.25) }
    }
    Repeater {
      model: 2
      Rectangle { required property int index; y: cropBox.height * (index + 1) / 3; height: 1
                  width: cropBox.width; color: Qt.rgba(1, 1, 1, 0.25) }
    }

    // the box itself moves; its corners and sides resize it
    Repeater {
      model: ["move", "tl", "t", "tr", "l", "r", "bl", "b", "br"]
      delegate: MouseArea {
        id: grip
        required property string modelData
        readonly property bool body: grip.modelData === "move"
        readonly property real gx: grip.modelData.indexOf("l") >= 0 ? 0
          : grip.modelData.indexOf("r") >= 0 ? cropBox.width : cropBox.width / 2
        readonly property real gy: grip.modelData.indexOf("t") >= 0 ? 0
          : grip.modelData.indexOf("b") >= 0 ? cropBox.height : cropBox.height / 2
        x: grip.body ? 0 : grip.gx - 9
        y: grip.body ? 0 : grip.gy - 9
        width: grip.body ? cropBox.width : 18
        height: grip.body ? cropBox.height : 18
        z: grip.body ? 0 : 1
        cursorShape: grip.body ? Qt.SizeAllCursor
          : (grip.modelData === "tl" || grip.modelData === "br") ? Qt.SizeFDiagCursor
          : (grip.modelData === "tr" || grip.modelData === "bl") ? Qt.SizeBDiagCursor
          : (grip.modelData === "l" || grip.modelData === "r") ? Qt.SizeHorCursor : Qt.SizeVerCursor
        property var r0: null
        property point p0
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: (m) => {
          box.touched();
          if (m.button === Qt.RightButton) {
            grip.r0 = null;
            box.rPress(grip.mapToItem(box, m.x, m.y));
            return;
          }
          grip.r0 = box.r;
          grip.p0 = grip.mapToItem(box, m.x, m.y);
        }
        onPositionChanged: (m) => {
          if (box.rr0) { box.rMove(grip.mapToItem(box, m.x, m.y), m.modifiers); return; }
          if (!grip.r0) return;
          const p = grip.mapToItem(box, m.x, m.y);
          const dx = (p.x - grip.p0.x) / box.k, dy = (p.y - grip.p0.y) / box.k;
          if (grip.body) { box.drawn(Cap.moveRect(grip.r0, dx, dy, box.tw, box.th)); return; }
          box.offer(box.fit(Cap.resizeRect(grip.r0, grip.modelData, dx, dy, box.tw, box.th),
                            grip.modelData, m.modifiers));
        }
        onReleased: (m) => {
          grip.r0 = null;
          const click = box.rRelease();
          if (m.button === Qt.RightButton && click && box.clickMenu)
            box.menuAsked(grip.mapToItem(null, m.x, m.y), true);
        }
        onDoubleClicked: if (grip.body) box.bodyDoubleClicked()
        Rectangle {
          visible: !grip.body
          anchors.centerIn: parent
          width: 10; height: 10; radius: Zenon.rad(2)
          color: Zenon.cyan
          border.width: 1
          border.color: "#000000"
        }
      }
    }
  }

  // the size it will be saved at
  Rectangle {
    x: cropBox.x + 6
    y: Math.max(6, cropBox.y - height - 6)
    width: cropSize.implicitWidth + 12
    height: 22
    radius: Zenon.radiusControl
    color: Zenon.hud(0.8)
    Text {
      id: cropSize
      anchors.centerIn: parent
      text: Math.round(box.r.w) + " × " + Math.round(box.r.h)
      color: Zenon.white
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(12)
    }
  }
}

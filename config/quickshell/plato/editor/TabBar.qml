// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The tabs: one per open buffer, drawn as terminus draws its own.
//
// TERMINUS' STRIP, ON PURPOSE. The same band in the same colour, divided
// evenly across the window the way a browser does it; the active tab paints
// nothing and is simply the strip showing through, the others are shaded
// back, a hairline between each. A tab fades in as it arrives, the rest
// slide aside when one is carried past them, and a middle-click closes one.
// Two tab strips in one shell that disagree about any of that would be one
// too many. See the `tabStrip` in terminus/TerminusWindow.qml, whose notes
// explain every choice here.
//
// A TAB IS A BUFFER. nvim keeps the open files, which one is showing and which
// have unsaved changes; the ORDER is plato's (EditorState.tabOrder), since
// nvim's cannot be rearranged. Closing a tab with unsaved changes is refused
// by nvim, and says so in the status line.
//
// Hidden while there is only one buffer: a single tab is just the window, and
// a strip saying so is a strip of nothing.

import QtQuick
import "../../morpheus"

Rectangle {
  id: tabStrip
  // buffer ids already drawn once (see the cell's arrival), and whether
  // arrivals animate at all (the settings' "Animate splits and tabs")
  property var seen: ({})
  property bool animate: true
  // ── A SHEET SPLICED OUT OF THIS BAR ──────────────────────────────
  // While one hangs from here, the bar goes black — the glass's own colour
  // at its seam (morpheus/Sheet, Frost.fade*) — and its hairline opens over
  // the card, so the two read as one piece. From the plato window; x in
  // this bar's own coordinates.
  property real spliceInk: 0
  property real spliceX: 0
  property real spliceW: 0

  required property var ed
  required property var client
  required property font face
  // the window's tooltip (morpheus WindowTip): a tab names its whole path
  property var tips: null

  readonly property var tabs: tabStrip.ed.tabs
  // terminus' path bar height, which its tab strip shares
  implicitHeight: tabStrip.tabs.length > 1 ? 34 : 0
  visible: implicitHeight > 0
  clip: true
  color: Zenon.headBg

  // the ink of "this is where you are", as terminus writes its active tab
  readonly property color hereInk: "#a3a9bd"

  // ── carrying one along the strip ───────────────────────────────────
  // As terminus: the order is not touched until the tab is let go. The drag
  // moves pixels, the others slide into the gap, and the order is written
  // once on release, by which time every tab already sits where it will end.
  property int dragFrom: -1
  property int dragTo: -1
  property real dragX: 0
  function endDrag() { tabStrip.dragFrom = -1; tabStrip.dragTo = -1; }
  // black under a spliced sheet, under the tabs themselves
  Rectangle {
    anchors.fill: parent
    color: "#000000"
    opacity: tabStrip.spliceInk
    visible: opacity > 0.01
  }

  Connections {
    target: tabStrip.ed
    function onTabOrderChanged() { tabStrip.endDrag(); }
  }

  // ── A TAB CLOSED SHRINKS OUT, AND THE REST CLOSE UP ───────────────
  // The strip's model is a plain list, so a change rebuilds every cell at
  // its new place. What the strip looked like before is kept here (ids in
  // order, one cell's width, each tab's name), so a cell made again can
  // start where it was and slide to where it is, and a tab that is gone
  // leaves a ghost in its slot that narrows to nothing as the others move
  // over it. Recorded a moment after each change, once the cells exist.
  property var prevIds: []
  property real prevCellW: 0
  property var prevNames: ({})
  function record() {
    tabStrip.prevIds = tabStrip.tabs.map((b) => b.id);
    tabStrip.prevCellW = tabStrip.width / Math.max(1, tabStrip.tabs.length);
    const names = {};
    for (const b of tabStrip.tabs) names[b.id] = b.name;
    tabStrip.prevNames = names;
  }
  onTabsChanged: {
    if (tabStrip.animate && tabStrip.tabs.length > 1) {
      const live = tabStrip.tabs.map((b) => b.id);
      for (let i = 0; i < tabStrip.prevIds.length; ++i) {
        const id = tabStrip.prevIds[i];
        if (live.indexOf(id) < 0)
          ghosts.append({ gx: i * tabStrip.prevCellW, gw: tabStrip.prevCellW,
                          name: tabStrip.prevNames[id] || "" });
      }
    }
    Qt.callLater(tabStrip.record);
  }
  onWidthChanged: tabStrip.prevCellW = tabStrip.width / Math.max(1, tabStrip.tabs.length)
  ListModel { id: ghosts }

  Item {
    anchors.fill: parent
    anchors.bottomMargin: 1

    Repeater {
      model: ghosts
      delegate: Item {
        id: ghost
        required property int index
        required property real gx
        required property real gw
        required property string name
        x: ghost.gx
        width: ghost.gw
        height: parent.height
        clip: true
        z: -1
        Text {
          anchors.centerIn: parent
          width: Math.min(implicitWidth, ghost.gw - 16)
          elide: Text.ElideMiddle
          textFormat: Text.PlainText
          text: ghost.name
          color: Zenon.muted
          font.family: Zenon.face
          font.pixelSize: tabStrip.face.pixelSize
        }
        ParallelAnimation {
          running: true
          onFinished: ghosts.remove(ghost.index)
          NumberAnimation { target: ghost; property: "opacity"; from: 1; to: 0; duration: Zenon.normal; easing.type: Easing.OutCubic }
          NumberAnimation { target: ghost; property: "width"; to: 0; duration: Zenon.normal; easing.type: Zenon.travelEase }
          NumberAnimation { target: ghost; property: "x"; to: ghost.gx + ghost.gw / 2; duration: Zenon.normal; easing.type: Zenon.travelEase }
        }
      }
    }

    Repeater {
      model: tabStrip.tabs

      delegate: Rectangle {
        id: tabCell
        required property var modelData
        required property int index
        readonly property bool here: tabCell.modelData.current
        readonly property bool lifted: tabStrip.dragFrom === tabCell.index
          && tabStrip.dragFrom < tabStrip.tabs.length
        readonly property int slot: {
          const f = tabStrip.dragFrom, t = tabStrip.dragTo;
          if (f < 0 || tabCell.index === f) return tabCell.index;
          if (f < t) return (tabCell.index > f && tabCell.index <= t)
            ? tabCell.index - 1 : tabCell.index;
          return (tabCell.index >= t && tabCell.index < f)
            ? tabCell.index + 1 : tabCell.index;
        }

        // from where it was before the strip was rebuilt (see prevIds)
        property real shiftX: 0
        property real shiftW: 0
        x: tabCell.lifted ? tabStrip.dragX : tabCell.slot * (tabStrip.width / Math.max(1, tabStrip.tabs.length)) + tabCell.shiftX
        z: tabCell.lifted ? 2 : 0
        Behavior on x {
          enabled: !tabCell.lifted && !closeUp.running
          NumberAnimation { duration: Zenon.normal; easing.type: Easing.OutCubic }
        }
        ParallelAnimation {
          id: closeUp
          NumberAnimation { target: tabCell; property: "shiftX"; to: 0; duration: Zenon.normal; easing.type: Zenon.travelEase }
          NumberAnimation { target: tabCell; property: "shiftW"; to: 0; duration: Zenon.normal; easing.type: Zenon.travelEase }
        }

        // ONLY A NEW TAB ARRIVES. The strip's model is a plain list, so any
        // change to the buffers rebuilds every cell, and every cell used to
        // fade in again with it — the whole strip blinked when one tab
        // opened. A tab the strip has already shown is simply there; a new
        // one grows in from its slot (and, with "Animate splits and tabs"
        // off, appears).
        opacity: 0
        transformOrigin: Item.Left
        Component.onCompleted: {
          const id = tabCell.modelData.id;
          const fresh = !tabStrip.seen[id];
          tabStrip.seen[id] = true;
          if (fresh && tabStrip.animate) { tabCell.scale = 0.6; tabIn.start(); }
          else tabCell.opacity = 1;
          // a tab already drawn, rebuilt somewhere else: slide from there
          const was = tabStrip.prevIds.indexOf(id);
          if (!fresh && was >= 0 && tabStrip.animate && tabStrip.prevCellW > 0) {
            const w = tabStrip.width / Math.max(1, tabStrip.tabs.length);
            tabCell.shiftX = was * tabStrip.prevCellW - tabCell.index * w;
            tabCell.shiftW = tabStrip.prevCellW - w;
            if (Math.abs(tabCell.shiftX) > 0.5 || Math.abs(tabCell.shiftW) > 0.5) closeUp.start();
            else { tabCell.shiftX = 0; tabCell.shiftW = 0; }
          }
        }
        ParallelAnimation {
          id: tabIn
          NumberAnimation { target: tabCell; property: "opacity"; to: 1; duration: Zenon.normal; easing.type: Easing.OutCubic }
          NumberAnimation { target: tabCell; property: "scale"; to: 1; duration: Zenon.normal; easing.type: Zenon.travelEase }
        }
        Behavior on color {
          ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
        }
        width: tabStrip.width / Math.max(1, tabStrip.tabs.length) + tabCell.shiftW
        height: parent.height
        color: tabCell.lifted ? Zenon.headBg
          : (tabCell.here ? "transparent" : Qt.rgba(0, 0, 0, 0.28))

        Rectangle {
          anchors.right: parent.right
          width: 1
          height: parent.height
          visible: !tabCell.lifted && tabCell.slot < tabStrip.tabs.length - 1
          color: Zenon.border
        }

        Row {
          anchors.centerIn: parent
          width: Math.min(implicitWidth, tabCell.width - 16)
          spacing: 6
          // pinned (pins.lua): its number, which Alt takes you back to it with
          Text {
            id: pinNo
            visible: !!tabCell.modelData.pin
            text: tabCell.modelData.pin ? String(tabCell.modelData.pin) : ""
            font.family: Zenon.face
            font.weight: Font.DemiBold
            font.pixelSize: tabStrip.face.pixelSize - 3
            color: Zenon.sand
            anchors.verticalCenter: tabLabel.verticalCenter
          }
          Text {
            id: tabLabel
            // room either side for the close button, while it shows
            width: Math.min(implicitWidth, tabCell.width - 16 - (dot.visible ? dot.width + 6 : 0)
              - (closeX.visible ? 2 * (closeX.width + 8) : 0)
              - (pinNo.visible ? pinNo.width + 6 : 0))
            elide: Text.ElideMiddle
            textFormat: Text.PlainText
            text: tabCell.modelData.name
            color: tabCell.here ? tabStrip.hereInk : Zenon.muted
            font.family: Zenon.face
            font.pixelSize: tabStrip.face.pixelSize
          }
          // unsaved: terminus' tabs have nothing to say this, an editor's must
          // (faded, not hidden, under the pointer: the close button takes
          // over its meaning, and the name does not shift)
          Text {
            id: dot
            visible: tabCell.modelData.modified
            opacity: tabMouse.containsMouse ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: Zenon.fast } }
            // unsaved: the same glyph as the status line's
            text: "\uEA73"
            font.family: Zenon.faceMono
            color: Zenon.pink
            font.pixelSize: tabStrip.face.pixelSize - 2
            anchors.verticalCenter: tabLabel.verticalCenter
          }
        }

        // ── CLOSE, UNDER THE POINTER ─────────────────────────────────
        // A × at the tab's right end while the pointer is on it (a middle
        // click still closes too). Closing a tab with unsaved changes is
        // refused by nvim, as ever.
        Text {
          id: closeX
          anchors.right: parent.right
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          opacity: tabMouse.containsMouse && !tabMouse.dragging && tabCell.width > 70 ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: Zenon.fast } }
          visible: opacity > 0
          text: "\u{F0156}"
          font.family: Zenon.faceMono
          font.pixelSize: tabStrip.face.pixelSize
          color: tabMouse.overClose ? (tabCell.modelData.modified ? Zenon.pink : Zenon.white) : Zenon.muted
          Behavior on color { ColorAnimation { duration: Zenon.fast } }
          Rectangle {
            anchors.centerIn: parent
            width: parent.height + 2
            height: width
            radius: 4
            z: -1
            color: Qt.rgba(1, 1, 1, tabMouse.overClose ? 0.08 : 0)
          }
        }

        MouseArea {
          id: tabMouse
          // the pointer is on the close button
          property bool overClose: false
          function onClose(m) {
            if (!closeX.visible) return false;
            const p = tabMouse.mapToItem(closeX, m.x, m.y);
            return p.x >= -4 && p.x <= closeX.width + 4 && p.y >= -4 && p.y <= closeX.height + 4;
          }
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.MiddleButton
          hoverEnabled: true
          onContainsMouseChanged: {
            if (!tabMouse.containsMouse) tabMouse.overClose = false;
            const t = tabStrip.tips;
            if (!t) return;
            if (tabMouse.containsMouse && !tabMouse.pressed)
              t.show(tabCell, tabCell.modelData.path || "New file — unsaved", "");
            else t.hide(tabCell);
          }
          property real grabDx: 0
          property bool dragging: false
          // held, not looked up: a press can outlive its delegate across a
          // reload — see the same note on terminus' tabMouse
          property var strip: null
          Component.onCompleted: tabMouse.strip = tabStrip

          function stripX(m) { return tabCell.mapToItem(tabStrip, m.x, 0).x; }

          onPressed: (m) => {
            if (tabStrip.tips) tabStrip.tips.hide(tabCell);
            if (m.button !== Qt.LeftButton) return;
            tabMouse.grabDx = tabMouse.stripX(m) - tabCell.x;
            tabMouse.dragging = false;
          }
          onPositionChanged: (m) => {
            tabMouse.overClose = tabMouse.onClose(m);
            if (!tabMouse.pressed || tabStrip.tabs.length < 2) return;
            const at = tabMouse.stripX(m);
            if (!tabMouse.dragging) {
              if (Math.abs(at - tabCell.x - tabMouse.grabDx) < 5) return;
              tabMouse.dragging = true;
              tabStrip.dragFrom = tabCell.index;
              tabStrip.dragTo = tabCell.index;
            }
            const w = tabCell.width;
            tabStrip.dragX = Math.max(0, Math.min(tabStrip.width - w, at - tabMouse.grabDx));
            tabStrip.dragTo = Math.max(0, Math.min(tabStrip.tabs.length - 1,
              Math.round(tabStrip.dragX / w)));
          }
          onReleased: {
            const was = tabMouse.dragging;
            tabMouse.dragging = false;
            const st = tabMouse.strip;
            if (!st) return;
            const from = st.dragFrom, to = st.dragTo;
            st.endDrag();
            if (was) st.ed.moveTab(from, to);
          }
          onCanceled: {
            tabMouse.dragging = false;
            if (tabMouse.strip) tabMouse.strip.endDrag();
          }
          onClicked: (m) => {
            if (tabMouse.dragging) return;
            const id = tabCell.modelData.id;
            // deferred: closing replaces the model this delegate belongs to
            if (m.button === Qt.MiddleButton || tabMouse.onClose(m))
              Qt.callLater(() => tabStrip.client.bufClose(id, false));
            else tabStrip.client.bufShow(id);
          }
        }
      }
    }
  }

  // the line under the strip, as the path bar has one under it — open over
  // a sheet spliced out of it (see spliceInk)
  Rectangle {
    anchors.bottom: parent.bottom
    width: tabStrip.spliceInk > 0.01 ? Math.max(0, Math.min(parent.width, tabStrip.spliceX)) : parent.width
    height: 1
    color: Zenon.border
  }
  Rectangle {
    anchors.bottom: parent.bottom
    x: Math.max(0, Math.min(parent.width, tabStrip.spliceX + tabStrip.spliceW))
    width: Math.max(0, parent.width - x)
    visible: tabStrip.spliceInk > 0.01
    height: 1
    color: Zenon.border
  }
}

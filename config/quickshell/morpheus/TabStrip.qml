// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE SUITE'S TAB STRIP — terminus' look, which plato's copied: the same band
// in the same color, divided evenly across the window the way a browser does
// it; the active tab paints nothing and is simply the strip showing through,
// the others are shaded back, a hairline between each. A tab fades in as it
// arrives, the rest slide aside when one is carried past them, a closed one
// shrinks out, and a middle-click closes one. Two tab strips in one shell
// that disagree about any of that would be one too many. See the `tabStrip`
// in terminus/Chrome.qml, whose notes explain every choice here.
//
// Lifted out of plato/editor/TabBar.qml (2026-10-18), so there is one strip,
// not two: plato's TabBar is this with its buffers fed in, terminus'
// (terminus/Chrome.qml) this with its directories. In morpheus since the same day, the suite's root,
// as every app with tabs draws from it.
//
//     TabStrip { tabs: […]; face.pixelSize: 15
//                onPicked: (id) => …; onClosed: (id) => …; onMoved: (from, to) => … }
//
// Reads: the window's tooltip (`tips`), and for a sheet spliced out of the
// bar under it, spliceInk / spliceX / spliceW (see below).

import QtQuick
import "../terminus" as Term

Rectangle {
  id: tabStrip
  // buffer ids already drawn once (see the cell's arrival), and whether
  // arrivals animate at all (the settings' "Animate splits and tabs")
  property var seen: ({})
  property bool animate: true
  // how small a new tab starts as it fades in: plato's grows from
  // 0.6, terminus' only fade (1)
  property real arriveScale: 0.6
  // a modal card is up over the window (terminus' sheets): no × and no
  // carrying, though a click still picks
  property bool locked: false
  // ── A SHEET SPLICED OUT OF THIS BAR ──────────────────────────────
  // While one hangs from here, the bar goes black — the glass's own color
  // at its seam (morpheus/Sheet, Frost.fade*) — and its hairline opens over
  // the card, so the two read as one piece. From the plato window; x in
  // this bar's own coordinates.
  property real spliceInk: 0
  property real spliceX: 0
  property real spliceW: 0

  // ── WHAT IT SHOWS, AND WHAT IT SAYS ───────────────────────────────
  // tabs: [{id, name, current, path?, modified?, pin?, loading?, tint?,
  // glyph?, glyphInk?}] in order. It never changes them itself: a click says picked,
  // a middle click or the × says closed, a carry says moved — the owner
  // does it, and the new list comes back here.
  property var tabs: []
  signal picked(var id)
  signal closed(var id)
  signal moved(int from, int to)
  // the labels' face; set piecewise (face.pixelSize: …) by the holder
  property font face: Qt.font({ family: Zenon.face, pixelSize: Zenon.px(14) })
  // the window's tooltip (morpheus WindowTip), and what a tab's says
  property var tips: null
  property var tipText: (t) => t.path || t.name
  // a single tab is just the window: hidden while there is one (plato's,
  // terminus'); off, the strip stays for one tab too
  property bool hideSingle: true
  // Zenon.tabH, the suite's tab height (plato's and terminus' alike)
  property int stripHeight: Zenon.tabH
  implicitHeight: !tabStrip.hideSingle || tabStrip.tabs.length > 1 ? tabStrip.stripHeight : 0
  visible: implicitHeight > 0
  clip: true
  // TRANSPARENT: an inactive tab is the window's own body showing through
  // (black at the panel opacity, as every other surface), and the active
  // tab paints the strip's gray itself — `hereBg`
  color: "transparent"
  // untouched by a sheet, as terminus' (user, 2026-10-11): only the bars go
  // with one, never the tabs
  readonly property color hereBg: Zenon.tabHere
  // the active tab's cell, for the glass under the strip (morpheus/TabGlass)
  property Item hereCell: null

  // the ink of "this is where you are", as terminus writes its active tab
  readonly property color hereInk: Zenon.accentKey

  // ── carrying one along the strip ───────────────────────────────────
  // As terminus: the order is not touched until the tab is let go. The drag
  // moves pixels, the others slide into the gap, and the order is written
  // once on release, by which time every tab already sits where it will end.
  property int dragFrom: -1
  property int dragTo: -1
  property real dragX: 0
  function endDrag() { tabStrip.dragFrom = -1; tabStrip.dragTo = -1; }
  // THE INACTIVE GLASS, under every tab: the window lays no ground under
  // the strip, so a cell paints only what it adds (Zenon.tabOver) and one
  // rebuilt or mid-fade never leaves a hole (as terminus, 2026-10-09)
  //
  // UNDER THE FROST, when the window lays it: painted here it sat over the
  // edges' blur (which the window puts under the whole bar) and hid it —
  // the strip lost its frost with the rework. The plato window lays this
  // same glass beneath its edgeHost instead and sets groundBelow.
  property bool groundBelow: false
  readonly property color awayGlass: Zenon.alpha(Zenon.tabAwayInk, Zenon.tabAway(Zenon.layerBg.a))
  TabGlass {
    anchors.fill: parent
    visible: !tabStrip.groundBelow
    cell: tabStrip.hereCell
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
  // ── A DROPPED TAB IS ALREADY WHERE IT LANDED (user, 2026-10-14) ───────
  // A drag's release rebuilt the strip from prevIds, the order BEFORE the
  // drag: the dropped tab jumped back to its old slot and slid over again,
  // the whole drag replayed. So a release records the order as it is on
  // screen (every other tab already in its new slot) and where the carried
  // one was let go, and only that one settles the last few pixels.
  property var dropId: null
  property real dropX: 0
  function noteDrop(from, to) {
    const ids = tabStrip.tabs.map((b) => b.id);
    const [id] = ids.splice(from, 1);
    ids.splice(to, 0, id);
    tabStrip.prevIds = ids;
    tabStrip.dropId = id;
    tabStrip.dropX = tabStrip.dragX;
  }
  function record() {
    tabStrip.dropId = null;
    tabStrip.prevIds = tabStrip.tabs.map((b) => b.id);
    tabStrip.prevCellW = tabStrip.width / Math.max(1, tabStrip.tabs.length);
    const names = {};
    for (const b of tabStrip.tabs) names[b.id] = b.name;
    tabStrip.prevNames = names;
  }
  onTabsChanged: {
    if (tabStrip.animate && (tabStrip.tabs.length > 1 || !tabStrip.hideSingle)) {
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
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
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
          if (tabCell.here) tabStrip.hereCell = tabCell;
          const id = tabCell.modelData.id;
          const fresh = !tabStrip.seen[id];
          tabStrip.seen[id] = true;
          if (fresh && tabStrip.animate) { tabCell.scale = tabStrip.arriveScale; tabIn.start(); }
          else tabCell.opacity = 1;
          // a tab already drawn, rebuilt somewhere else: slide from there
          const was = tabStrip.prevIds.indexOf(id);
          if (!fresh && was >= 0 && tabStrip.animate && tabStrip.prevCellW > 0) {
            const w = tabStrip.width / Math.max(1, tabStrip.tabs.length);
            tabCell.shiftX = (id === tabStrip.dropId ? tabStrip.dropX : was * tabStrip.prevCellW)
              - tabCell.index * w;
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
        // every tab is the body, the active one too (the user's call,
        // 2026-10-09, plato and terminus alike): the label's strength says
        // which is here. Only a carried tab takes a ground.
        //
        // EACH TAB ITS OWN GLASS (2026-10-09): the window lays no ground
        // under the strip, so the active tab wears the window's and an
        // inactive one a much thinner one — the desktop shows through it.
        // The active tab's glass is the strip's (morpheus/TabGlass, which
        // reads this cell's place): the window's ground with the thin glass
        // cut away under it, as terminus' (2026-10-11). Only a carried tab
        // paints its own.
        // carried, it looks as it did (user, 2026-10-13): the movement says
        // which one is in hand, no ground of its own
        color: Zenon.alpha(Zenon.tabAwayInk, 0)
        onHereChanged: if (here) tabStrip.hereCell = tabCell
        // a tab's own hue (plato's visual-mode magenta,
        // as their bar wears it), over its glass; plato's tabs have none
        Rectangle {
          anchors.fill: parent
          anchors.bottomMargin: -1
          visible: !!tabCell.modelData.tint
          color: tabCell.modelData.tint ? Zenon.alpha(tabCell.modelData.tint, 0.17) : "transparent"
        }

        Rectangle {
          anchors.right: parent.right
          width: 1
          height: parent.height
          visible: !tabCell.lifted && tabCell.slot < tabStrip.tabs.length - 1
          color: Zenon.border
        }
        // ── THE LINE UNDER THE STRIP, per tab ───────────────────────
        // Every tab but the active one, which runs on into the bar below
        // with no edge (user, 2026-10-09). Just under the cell, in the 1px
        // the cells leave free; cut where a sheet is spliced out of it
        // (spliceX/spliceW are strip coordinates, as the cell's x is).
        Item {
          y: tabCell.height
          width: tabCell.width
          height: 1
          readonly property bool cut: tabStrip.spliceInk > 0.01
          readonly property real cutL: Math.max(0, Math.min(width, tabStrip.spliceX - tabCell.x))
          readonly property real cutR: Math.max(0, Math.min(width, tabStrip.spliceX + tabStrip.spliceW - tabCell.x))
          // the tab's own glass under its line, or the 1px row the cells
          // leave free would be a clear seam
          Rectangle {
            anchors.fill: parent
            color: tabCell.color
          }
          Rectangle {
            width: parent.cut ? parent.cutL : parent.width
            height: 1
            visible: !tabCell.here
            color: Zenon.border
          }
          Rectangle {
            x: parent.cutR
            width: parent.width - parent.cutR
            height: 1
            visible: parent.cut && !tabCell.here
            color: Zenon.border
          }
        }

        Row {
          anchors.centerIn: parent
          width: Math.min(implicitWidth, tabCell.width - 16)
          spacing: 6
          opacity: tabCell.here || tabCell.lifted ? 1 : (tabMouse.pressed ? 0.9 : 0.7)
          Behavior on opacity { NumberAnimation { duration: Zenon.fast } }
          // what the tab holds, as a glyph before its name (terminus: the
          // directory's, as its crumbs wear it; plato: the file's kind, as a
          // listing row wears it), in that thing's own ink
          Text {
            id: tabGlyph
            visible: !!tabCell.modelData.glyph
            text: tabCell.modelData.glyph || ""
            font.family: Zenon.faceMono
            font.pixelSize: tabStrip.face.pixelSize
            color: tabCell.modelData.glyphInk || tabStrip.hereInk
            anchors.verticalCenter: parent.verticalCenter
          }
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
          // still loading (a tab's optional `loading`): the
          // shell's three dots in the label's place, until it has
          Working {
            anchors.verticalCenter: parent.verticalCenter
            running: !!tabCell.modelData.loading
            ink: tabStrip.hereInk
            dot: Math.max(4, Math.round(tabStrip.face.pixelSize / 3.5))
          }
          Text {
            id: tabLabel
            visible: !tabCell.modelData.loading
            // never more than four fifths of the tab (user, 2026-10-13: every
            // strip in the suite), the rest elided; the close chip lies over its end
            width: Math.min(implicitWidth, tabCell.width * 0.8, tabCell.width - 16 - (dot.visible ? dot.width + 6 : 0)
              - (pinNo.visible ? pinNo.width + 6 : 0) - (tabGlyph.visible ? tabGlyph.width + 6 : 0))
            elide: Text.ElideMiddle
            textFormat: Text.PlainText
            text: tabCell.modelData.name
            color: tabStrip.hereInk
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: tabStrip.face.pixelSize
          }
          // unsaved: terminus' tabs have nothing to say this, an editor's must
          // (faded, not hidden, under the pointer: the close button takes
          // over its meaning, and the name does not shift)
          Text {
            id: dot
            visible: !!tabCell.modelData.modified
            opacity: tabMouse.containsMouse ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: Zenon.fast } }
            // unsaved: the same glyph as the status line's
            text: "\uEA73"
            font.family: Zenon.faceMono
            font.weight: Zenon.weight
            color: Zenon.pink
            font.pixelSize: tabStrip.face.pixelSize - 2
            anchors.verticalCenter: tabLabel.verticalCenter
          }
        }

        // ── CLOSE, UNDER THE POINTER ─────────────────────────────────
        // A × at the tab's right end while the pointer is on it (a middle
        // click still closes too). Closing a tab with unsaved changes is
        // refused by nvim, as ever.
        // the search fields' clear chip (terminus/ClearChip), laid OVER the
        // label's end rather than making room beside it (user, 2026-10-13):
        // the name stays where it is as the pointer comes and goes
        Term.ClearChip {
          id: closeX
          anchors.right: parent.right
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          size: tabStrip.face.pixelSize
          held: tabMouse.pressed && tabMouse.overClose && !tabMouse.dragging
          // shown and hidden outright, no fade (user, 2026-10-14)
          opacity: tabMouse.containsMouse && !tabMouse.dragging && tabCell.width > 70 && !tabStrip.locked ? 1 : 0
          visible: opacity > 0
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
              t.show(tabCell, tabStrip.tipText(tabCell.modelData), "");
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
            tabMouse.overClose = tabMouse.onClose(m);
            if (m.button !== Qt.LeftButton) return;
            tabMouse.grabDx = tabMouse.stripX(m) - tabCell.x;
            tabMouse.dragging = false;
          }
          onPositionChanged: (m) => {
            tabMouse.overClose = tabMouse.onClose(m);
            if (!tabMouse.pressed || tabStrip.tabs.length < 2 || tabStrip.locked) return;
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
            if (was && from >= 0 && to >= 0 && from !== to) st.noteDrop(from, to);
            st.endDrag();
            if (was) st.moved(from, to);
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
              Qt.callLater(() => tabStrip.closed(id));
            else tabStrip.picked(id);
          }
        }
      }
    }
  }

  // the line under the strip is drawn by each tab — see tabCell
}

// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Its own file since 2026-10-08, out of TerminusWindow.qml (the split).
// `term` is the terminus window; window items it uses are read as
// term.<id>Ref (the window's aliases).

import QtQuick
import QtQuick.Shapes
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick.Effects
import QtMultimedia
import Qt.labs.folderlistmodel
import "../morpheus"
import "../picasso"
import "../oracle"
import "terminus.js" as Terminus
import "../morpheus/icons.js" as Icons
import "../morpheus/thumbs.js" as Thumbs
import "tags.js" as Tags
import "collections.js" as Coll

Column {
  id: chrome
  // the terminus window (`term`, never `root` — see terminus-split notes)
  property var term: null
  readonly property alias gridA: gridA
  readonly property alias gridB: gridB
  readonly property alias listA: listA
  readonly property alias listB: listB
  readonly property alias archiveList: archiveList
  readonly property alias band: band
  readonly property alias bodyBox: bodyBox
  readonly property alias bodyRow: bodyRow
  readonly property alias colA: colA
  readonly property alias colB: colB
  readonly property alias colC: colC
  readonly property alias colHeads: colHeads
  readonly property alias crumbBar: crumbBar
  readonly property alias dropHint: dropHint
  readonly property alias facts: facts
  readonly property alias filterField: filterField
  readonly property alias miller: miller
  readonly property alias millerBox: millerBox
  readonly property alias previewBody: previewBody
  readonly property alias portalBar: portalBar
  readonly property alias previewPane: previewPane
  readonly property alias saveField: saveField
  readonly property alias sideGrip: sideGrip
  readonly property alias splitGrip: splitGrip
  readonly property alias statusChip: statusChip
  readonly property alias statusChipMa: statusChipMa
  readonly property alias tabStrip: tabStrip
  readonly property alias textScroll: textScroll
  anchors.fill: parent
  // Beside the sidebar rather than over it — see `side`.
  anchors.leftMargin: side.width

  // ── tabs ──────────────────────────────────────────────────────
  // Hidden while there is one, because a single tab is just the window and
  // a strip saying so is a strip of nothing.
  Rectangle {
    id: tabStrip
    width: parent.width
    // the path bar's height, so the two strips stack as one band of chrome
    // rather than two of slightly different depths
    height: (term.alwaysTabs || term.tabs.length > 1) ? term.headH : 0
    visible: height > 0
    clip: true
    // The path bar's own colour. Leaving the strip transparent removed the
    // 1px separator but not the LINE: the transparent strip showed the
    // window's ground (layerBg) while the bar below was headBg, and two
    // different colours meeting across the full width is a line whether or
    // not anyone drew one. With the strip painted the same as the bar, the
    // active tab is simply the strip showing through and the boundary
    // disappears; the inactive ones darken instead.
    //
    // And it goes black with the path bar under it while a sheet is open,
    // or the band above the sheet would be grey on top of black.
    // Since the bar took the sidebar's ground, the strip is headBg instead
    // — see root.tabBg.
    // NOW the body's black instead (2026-10-08, the user's call, as in
    // plato): the strip is see-through, so an inactive tab is the window
    // itself at the panel opacity, and the active tab paints tabBg —
    // still the bar's colour, so the seam stays gone. Black behind a
    // sheet, as before.
    color: Zenon.floor(term.sheetInk)

    // ── dragging one along the strip ────────────────────────────
    // Which tab is being carried, and where it would land. -1 for neither,
    // which is nearly always.
    //
    // The ORDER IS NOT TOUCHED UNTIL YOU LET GO. It is tempting to shuffle
    // `root.tabs` as the pointer crosses each boundary, and it does not
    // work: the Repeater's model is a plain array, so replacing it destroys
    // and rebuilds every delegate — including the one under the pointer,
    // mid-gesture. So the drag moves PIXELS, the other tabs slide into the
    // gap it leaves, and the array is rewritten exactly once, on release,
    // by which time every tab is already sitting where it will end up.
    property int dragFrom: -1
    property int dragTo: -1
    // where the carried tab's left edge is, in strip coordinates
    property real dragX: 0

    function endDrag() {
      tabStrip.dragFrom = -1;
      tabStrip.dragTo = -1;
    }

    // A tab opened or closed while one is being carried leaves dragFrom
    // pointing into a list that no longer has that shape. Nothing good
    // comes of guessing which tab it used to mean.
    Connections {
      target: term
      function onTabsChanged() { tabStrip.endDrag(); }
    }

    // ── A TAB CLOSED SHRINKS OUT, AND THE REST CLOSE UP ─────────
    // As plato's strip (plato/editor/TabBar.qml). The model is a plain
    // array and a close rebuilds every cell at its new place, so
    // closeTabAt says first which tab is going (noteClose): the cells
    // made again start where they were and slide over, already there
    // rather than fading in afresh, and the closed one leaves a ghost
    // in its slot that narrows to nothing beneath them.
    property int closedAt: -1
    // How many tabs the strip had last time it settled. saveTab() replaces
    // term.tabs on every switch, which rebuilds every cell, and every cell
    // faded in from nothing: the whole strip blinked out at each switch
    // (user's capture, 2026-10-09). Only a cell the count did not have
    // before — a tab really opened — fades in now.
    property int seenCount: 0
    Connections {
      target: term
      function onTabsChanged() { Qt.callLater(() => { tabStrip.seenCount = term.tabs.length; }); }
    }
    Component.onCompleted: tabStrip.seenCount = term.tabs.length
    // THE INACTIVE GLASS, under every tab: a cell paints only what it adds
    // to it (see Zenon.tabOver), so nothing rebuilt or mid-fade can leave
    // the strip without a ground — there is no window ground under it.
    Rectangle {
      anchors.fill: parent
      color: Zenon.alpha(Zenon.tabAwayInk, term.tabAwayAlpha)
    }
    property real closedCellW: 0
    function noteClose(i) {
      if (term.tabs.length < 3 && !term.alwaysTabs) return;
      tabStrip.closedAt = i;
      tabStrip.closedCellW = tabStrip.width / Math.max(1, term.tabs.length);
      ghosts.append({ gx: i * tabStrip.closedCellW, gw: tabStrip.closedCellW,
        name: Terminus.basename(term.shownPath(i === term.tab ? term.cwd : term.tabs[i].cwd)) });
      Qt.callLater(() => { tabStrip.closedAt = -1; });
    }
    ListModel { id: ghosts }

    // ── A TAB IS A PLACE TO DROP, AND A DOOR WHILE DRAGGING ─────────
    // The crumbs and the directories in the listing already take a drop and
    // open on hold (crumbSpring, springTimer); the tabs did neither, so
    // getting a file into the directory another tab was showing meant a
    // second window or a cut and paste. Now: drop on a tab and it lands
    // in that tab's directory; hold over one and the window switches to
    // it, so the drag can carry on into that tab's listing and directories.
    DropArea {
      id: tabDrop
      anchors.fill: parent
      z: 5
      property int at: -1
      function indexAt(x) {
        const n = term.tabs.length;
        if (n === 0) return -1;
        return Math.max(0, Math.min(n - 1, Math.floor(x / (tabStrip.width / n))));
      }
      function dirOf(i) {
        if (i < 0 || i >= term.tabs.length) return "";
        return i === term.tab ? term.cwd : String(term.tabs[i].cwd || "");
      }
      onPositionChanged: (d) => {
        const i = tabDrop.indexAt(d.x);
        if (i === tabDrop.at) return;
        tabDrop.at = i;
        if (i >= 0 && i !== term.tab) tabSpring.restart(); else tabSpring.stop();
      }
      onExited: { tabDrop.at = -1; tabSpring.stop(); }
      onDropped: (d) => {
        const into = tabDrop.dirOf(tabDrop.indexAt(d.x));
        tabDrop.at = -1;
        tabSpring.stop();
        if (into === "") return;
        term.dropUris(term.urlsFrom(d), d.proposedAction, into, tabDrop, d.x, d.y);
      }
      Timer {
        id: tabSpring
        interval: Math.round(term.springMs * 0.6)
        onTriggered: {
          const i = tabDrop.at;
          if (i >= 0 && i !== term.tab && i < term.tabs.length) term.switchTab(i);
        }
      }
    }
    // The tab under the drag, outlined — the same cyan the directory rows
    // and crumbs light with under a drag.
    Rectangle {
      z: 6
      visible: tabDrop.containsDrag && tabDrop.at >= 0
      x: tabDrop.at * (tabStrip.width / Math.max(1, term.tabs.length)) + 2
      width: tabStrip.width / Math.max(1, term.tabs.length) - 4
      y: 2
      height: tabStrip.height - 4
      radius: 5
      color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.10)
      border.width: 1
      border.color: Zenon.cyan
      Behavior on x { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
    }

    // The strip spans the window and the tabs divide it, the way a browser
    // does it: a tab's position stops moving every time a directory with a
    // longer name is opened in one of them.
    //
    // An Item and not a Row, because a Row positions its children and the
    // whole point here is that one of them follows the pointer while the
    // others animate around it. The arithmetic a Row was doing is one line.
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
            width: Math.max(0, ghost.gw - 16)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideMiddle
            text: ghost.name
            color: Zenon.muted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Math.round(16 * term.zoom)
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
        model: term.tabs

        delegate: Rectangle {
          id: tabCell
          required property var modelData
          required property int index
          readonly property bool here: index === term.tab
          readonly property bool lifted: tabStrip.dragFrom === tabCell.index
            && tabStrip.dragFrom < term.tabs.length

          // WHERE THIS TAB SITS WHILE ANOTHER IS BEING CARRIED. Everything
          // between the tab's old place and the pointer's shifts one step
          // the other way, which is what opens the gap the carried tab
          // will drop into.
          readonly property int slot: {
            const f = tabStrip.dragFrom, t = tabStrip.dragTo;
            if (f < 0 || tabCell.index === f) return tabCell.index;
            if (f < t) return (tabCell.index > f && tabCell.index <= t)
              ? tabCell.index - 1 : tabCell.index;
            return (tabCell.index >= t && tabCell.index < f)
              ? tabCell.index + 1 : tabCell.index;
          }

          // from where it was before a close rebuilt the strip
          property real shiftX: 0
          property real shiftW: 0
          x: tabCell.lifted ? tabStrip.dragX
            : tabCell.slot * (tabStrip.width / Math.max(1, term.tabs.length)) + tabCell.shiftX
          // the carried one rides over the rest
          z: tabCell.lifted ? 2 : 0
          // The slide. Switched off for the tab under the pointer: that one
          // is following a finger, and an animation between the finger and
          // the tab is lag with a curve on it.
          Behavior on x {
            enabled: !tabCell.lifted && !closeUp.running
            NumberAnimation { duration: Zenon.normal; easing.type: Easing.OutCubic }
          }
          ParallelAnimation {
            id: closeUp
            NumberAnimation { target: tabCell; property: "shiftX"; to: 0; duration: Zenon.normal; easing.type: Zenon.travelEase }
            NumberAnimation { target: tabCell; property: "shiftW"; to: 0; duration: Zenon.normal; easing.type: Zenon.travelEase }
          }

          // A new tab grows into place rather than appearing, and the
          // active one lifts a little — the strip is the one part of the
          // chrome that changes while you are looking straight at it.
          opacity: 0
          Component.onCompleted: {
            const c = tabStrip.closedAt;
            if (c < 0) {
              const grew = term.tabs.length > tabStrip.seenCount;
              if (grew && (tabCell.index === term.tab || tabCell.index >= tabStrip.seenCount))
                tabIn.start();
              else tabCell.opacity = 1;
              return;
            }
            // a survivor of a close: there already, sliding from its old place
            tabCell.opacity = 1;
            const was = tabCell.index >= c ? tabCell.index + 1 : tabCell.index;
            const w = tabStrip.width / Math.max(1, term.tabs.length);
            tabCell.shiftX = was * tabStrip.closedCellW - tabCell.index * w;
            tabCell.shiftW = tabStrip.closedCellW - w;
            closeUp.start();
          }
          NumberAnimation {
            id: tabIn
            target: tabCell
            property: "opacity"
            to: 1
            duration: Zenon.normal
            easing.type: Easing.OutCubic
          }
          Behavior on color {
            ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
          }
          width: tabStrip.width / Math.max(1, term.tabs.length) + tabCell.shiftW
          height: parent.height
          // The active tab paints nothing — it is the strip, which is the
          // bar — so it runs into the path bar with no seam at all. The
          // inactive ones are shaded back, which is what separates them.
          //
          // A tab being CARRIED looks exactly like a tab. It was given a
          // ground and a cyan edge while dragging, on the theory that a
          // lifted thing should look lifted; it read as a different tab
          // rather than as the one you had hold of. The movement is the
          // feedback — nothing else is needed to say which one is moving.
          // AND A CARRIED ONE HAS TO BE OPAQUE. The active tab paints
          // nothing on purpose — being the strip is how it joins the bar
          // below without a seam — but a transparent thing cannot be
          // picked up: lifting it moved the label alone, sliding across
          // the tabs it passed over with no body of its own. In hand it
          // takes the strip's own colour, the one it has been showing
          // through all along, and is a solid object for as long as it is
          // moving.
          // Every tab is the body now, the active one too (user,
          // 2026-10-09): which is which is said by the label's strength
          // (tabLabel's opacity), not by a fill. Only a carried tab
          // takes a ground, to be a solid thing while it moves.
          //
          // NOW EACH TAB IS ITS OWN GLASS (user, 2026-10-09): the window
          // lays no ground under the strip, so the active tab wears the
          // window's and an inactive one a much thinner one — the desktop
          // shows through it, and the difference reads at a glance.
          color: here || tabCell.lifted ? term.ground(Zenon.tabOver(term.winAlpha))
            : Zenon.alpha(Zenon.tabAwayInk, 0)
          Rectangle {
            anchors.fill: parent
            visible: tabCell.lifted
            color: term.tabBg
          }

          Rectangle {
            anchors.right: parent.right
            width: 1
            height: parent.height
            // by the tab's PLACE, not its index — mid-drag those differ,
            // and a separator drawn by index lands inside the gap
            visible: !tabCell.lifted && tabCell.slot < term.tabs.length - 1
            color: Zenon.border
          }
          // ── THE LINE UNDER THE STRIP, per tab ─────────────────────
          // Every tab but the active one: there it is left out, so the
          // active tab runs straight on into the path bar (user,
          // 2026-10-09). Carried with its tab, so a drag takes it along.
          // In the 1px row the cells leave free under them, over the
          // tab's own glass — left empty, that row was a dark seam.
          Rectangle {
            y: tabCell.height
            width: parent.width
            height: 1
            color: tabCell.color
            Rectangle {
              anchors.fill: parent
              visible: !here
              color: Zenon.border
            }
          }

          Text {
            id: tabLabel
            anchors.centerIn: parent
            // room either side for the close button, while it shows
            width: parent.width - 16 - (closeX.visible ? 2 * (closeX.width + 8) : 0)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideMiddle
            text: Terminus.basename(term.shownPath(here ? term.cwd : modelData.cwd))
            // The active crumb's ink. The tab and the last path segment
            // are the same claim made twice — this is where you are — and
            // they were two different greys saying it.
            color: term.crumbInk
            // the inactive ones held back, brought up a little under the
            // pointer to say they can be taken
            opacity: here || tabCell.lifted ? 1 : (tabHov.hovered ? 0.9 : 0.7)
            Behavior on opacity { NumberAnimation { duration: Zenon.fast } }
            font.family: Zenon.face
            font.weight: Zenon.weight
            // the body's row size, written the same way rather than as a
            // number that happens to match — zoom then moves both together
            font.pixelSize: Math.round(16 * term.zoom)
          }

          // ── CLOSE, UNDER THE POINTER ───────────────────────────
          // A × at the tab's right end while the pointer is on it, as
          // plato's tabs have; a middle click still closes too.
          Text {
            id: closeX
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            opacity: tabHov.hovered && !tabMouse.dragging && tabCell.width > 70 && !term.modal ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Zenon.fast } }
            visible: opacity > 0
            text: "\u{F0156}"
            font.family: Zenon.faceMono
            font.weight: Zenon.weight
            font.pixelSize: Math.round(16 * term.zoom)
            color: tabMouse.overClose ? Zenon.white : Zenon.muted
            Behavior on color { ColorAnimation { duration: Zenon.fast } }
            Rectangle {
              anchors.centerIn: parent
              width: parent.height + 2
              height: width
              radius: 4
              z: -1
              color: Zenon.wash(tabMouse.overClose ? 0.08 : 0)
            }
          }

          HoverHandler { id: tabHov }
          MouseArea {
            id: tabMouse
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            hoverEnabled: true
            // the pointer is on the close button
            property bool overClose: false
            onContainsMouseChanged: if (!tabMouse.containsMouse) tabMouse.overClose = false
            function onClose(m) {
              if (!closeX.visible) return false;
              const p = tabMouse.mapToItem(closeX, m.x, m.y);
              return p.x >= -4 && p.x <= closeX.width + 4 && p.y >= -4 && p.y <= closeX.height + 4;
            }

            // How far into the tab you took hold of it, so the tab does not
            // jump its own width the moment the drag begins.
            property real grabDx: 0
            property bool dragging: false

            // ── THE STRIP, HELD RATHER THAN LOOKED UP ────────────────
            // A press outlives its delegate: on a config reload the tab
            // is torn down with the button still held, and the release
            // and the cancel are both delivered to what is left of it. By
            // then `tabStrip` cannot be named — a QML id resolves through
            // the component's context and not through JS scope, so once
            // that context is gone the name does not evaluate to null, it
            // fails to evaluate at all. Which is why guarding it did not
            // work: `!tabStrip` threw the error it was testing for, and
            // `typeof tabStrip` threw it too. typeof only forgives a name
            // JS itself has never heard of, and this one is not that.
            //
            // So the reference is taken ONCE, while the context is
            // certainly alive, and read as a plain property afterwards.
            // Reading a property of a half-dead object is allowed; naming
            // a dead id is not.
            property var strip: null
            Component.onCompleted: tabMouse.strip = tabStrip

            // MEASURED IN THE STRIP, never in the tab. `m.x` is relative to
            // this MouseArea, and this MouseArea moves with the tab while
            // the tab follows the pointer — reading the pointer off a thing
            // that the pointer is moving is a feedback loop, and the tab
            // shivers. mapToItem asks the strip instead, which holds still.
            function stripX(m) {
              return tabCell.mapToItem(tabStrip, m.x, 0).x;
            }

            onPressed: (m) => {
              if (m.button !== Qt.LeftButton) return;
              tabMouse.grabDx = tabMouse.stripX(m) - tabCell.x;
              tabMouse.dragging = false;
            }

            onPositionChanged: (m) => {
              tabMouse.overClose = tabMouse.onClose(m);
              if (!tabMouse.pressed || term.tabs.length < 2 || term.modal) return;
              const at = tabMouse.stripX(m);
              if (!tabMouse.dragging) {
                // a threshold, so a click that wobbles two pixels is still
                // a click and still switches tab
                if (Math.abs(at - tabCell.x - tabMouse.grabDx) < 5) return;
                tabMouse.dragging = true;
                tabStrip.dragFrom = tabCell.index;
                tabStrip.dragTo = tabCell.index;
              }
              const w = tabCell.width;
              tabStrip.dragX = Math.max(0,
                Math.min(tabStrip.width - w, at - tabMouse.grabDx));
              // WHERE IT WOULD LAND: the slot its own left edge is nearest,
              // which is what makes the gap open when the tab is more than
              // half way past its neighbour rather than the moment it
              // touches it.
              tabStrip.dragTo = Math.max(0, Math.min(term.tabs.length - 1,
                Math.round(tabStrip.dragX / w)));
            }

            // CLEARED WHETHER OR NOT THIS WAS A DRAG. An early return here
            // left `dragFrom` pointing at a tab whose gesture had ended — a
            // press that became a drag and then lost its release froze that
            // tab where it stood, and nothing afterwards put it back.
            onReleased: {
              const was = tabMouse.dragging;
              tabMouse.dragging = false;
              // Through the held reference — see `strip` above. A drag
              // that died with its component has nothing left to put back.
              const st = tabMouse.strip;
              if (!st) return;
              if (was) term.moveTab(st.dragFrom, st.dragTo);
              st.endDrag();
            }

            // A grab taken away mid-drag puts everything back rather than
            // committing a move nobody finished asking for.
            onCanceled: {
              tabMouse.dragging = false;
              // Through the held reference like the release above: a
              // cancel is exactly what a torn-down delegate delivers.
              if (tabMouse.strip) tabMouse.strip.endDrag();
            }

            onClicked: (m) => {
              // a gesture that became a drag is not also a click — the same
              // rule the listing's rows follow
              if (tabMouse.dragging) return;
              if (m.button === Qt.MiddleButton || tabMouse.onClose(m)) {
                // DEFERRED, because this handler is about to lose the
                // ground it is standing on: closing a tab replaces
                // `root.tabs`, which is this Repeater's model, so the
                // delegate running this very line is destroyed inside the
                // call and everything after it throws instead of running.
                // Handing root an index and letting it do the work in its
                // own scope — which nothing here can tear down — is the
                // whole of the fix.
                Qt.callLater(term.closeTabAt, tabCell.index);
                return;
              }
              term.switchTab(tabCell.index);
            }
          }
        }
      }
    }

    // the line under the strip is drawn by each tab — see tabCell
  }

  // ── the crumbs ────────────────────────────────────────────────
  Rectangle {
    id: crumbBar
    width: parent.width
    height: term.headH
    // BLACK WHILE THE SHEET IS UP. The send-to header is drawn on this
    // same strip, and the bar's translucent grey let the column behind it
    // read straight through a header that is answering a question — so
    // the strip goes solid for as long as the sheet is, and comes back
    // with it — see root.chromeBg, which the tab strip above wears too.
    color: term.chromeBg

    // HOW MUCH OF THE BAR'S OWN CONTENT IS SHOWING. Always all of it
    // now that sheets float (see sheetInk); it used to step aside for a
    // sheet's header written on this bar. One number, because these
    // are half a dozen siblings rather than one container — crumbInner is
    // a geometry helper with nothing inside it, which is what made the
    // first attempt at this fade nothing at all.
    //
    // AND NOW IT STANDS DOWN AGAIN: the bar is the open sheet's
    // titlebar (see root.barTitle), so everything it carries for the
    // listing fades out as the sheet arrives, at the sheet's own rate.
    readonly property real chromeInk: 1 - term.sheetInk
    // and none of it takes a click while it is not there
    readonly property bool chromeLive: crumbBar.chromeInk > 0.5

    // AND THE PATH'S OWN SHARE OF IT, which stands down for the send-to
    // header like the rest of the chrome. Searching is a sheet now (see
    // collEdit.askSearch), so nothing else takes the trail's place.
    readonly property real trailInk: crumbBar.chromeInk

    // ── THE INSIDE OF THE BAR, WHICH IS NOT THE WHOLE OF IT ──────
    // The last pixel of this strip is the hairline along its bottom edge.
    // Everything on the bar used to be centred across the whole 34,
    // hairline included, and then nudged a pixel DOWN to compensate — the
    // note on crumbStatus says "up by the separator's own pixel", which is
    // what was meant and the opposite of what +1 does. Between the two,
    // every label on this bar sat a pixel and a half low.
    //
    // So the inside is named once, here, and everything is placed against
    // it: one answer to "where is the middle", and a divider that stands
    // the full height now starts on the bar's top edge and stops exactly
    // where the hairline starts instead of running under it.
    Item {
      id: crumbInner
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 1
    }

    // the sidebar's switch, where the path begins — it is about what is to
    // the LEFT of the path, so it sits to the left of it
    Item {
      id: sideToggle
      opacity: crumbBar.chromeInk
      enabled: crumbBar.chromeLive
      anchors.left: parent.left
      anchors.leftMargin: 8
      anchors.verticalCenter: crumbInner.verticalCenter
      width: 34
      height: crumbInner.height

      Text {
        anchors.centerIn: parent
        // Written as an escape, not as the character. Every literal nerd
        // glyph in this batch arrived empty — they do not survive the trip
        // through a shell heredoc — and an empty string renders as nothing
        // at all, which is exactly what the toggle did.
        text: "\uEC02"
        color: term.sidebar ? Zenon.cyan
          : (sideHov.hovered ? Zenon.white : Zenon.muted)
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(18)
      }

      HoverHandler { id: sideHov }
      MouseArea {
        anchors.fill: parent
        onClicked: term.toggleSidebar()
      }
    }

    // ── the trail, as something that SCROLLS rather than gets cut ──
    // A path deeper than the bar is wide used to simply run off the
    // right-hand edge, and what went over the edge was the LAST step —
    // the directory you are actually standing in, and the one part of the
    // trail you cannot work out from the rest.
    Flickable {
      id: crumbFlick
      opacity: crumbBar.trailInk
      // Gone rather than merely transparent: an item at zero opacity
      // still takes the wheel and still lays out, and the search bar
      // needs both.
      visible: crumbBar.trailInk > 0.01
      enabled: crumbBar.chromeLive
      anchors.left: sideToggle.right
      // Clear of the toggle rather than touching it. The glyph is a
      // control and the trail is text; at 4px the first step read as a
      // label ON the button instead of the beginning of a path.
      anchors.leftMargin: 12
      anchors.right: filterInline.left
      anchors.rightMargin: 12
      anchors.verticalCenter: crumbInner.verticalCenter
      height: crumbInner.height
      clip: true
      contentWidth: crumbTrail.width
      contentHeight: crumbFlick.height
      flickableDirection: Flickable.HorizontalFlick
      boundsBehavior: Flickable.StopAtBounds

      // ── the trail does not END at the edge, it FADES there ────────
      // An ellipsis is a character: it has to be read, recognised as not
      // being part of any directory's name, and then discounted. A fade
      // says "there is more this way" without asking for a word.
      //
      // AN OPACITY MASK, not a wash of colour over the top. The obvious
      // trick — a rectangle ramping from the bar's own colour to
      // transparent — cannot work here, and it took a screenshot to see
      // why: headBg is #66282f36, four tenths opaque, so painting it over
      // the crumbs veils them by four tenths and stops. What is actually
      // behind this bar is the background, and there is no colour this
      // window can paint that matches that. So the pixels lose their own
      // alpha towards the edge instead, and it reads the same whatever
      // happens to be behind them.
      //
      // The layer is only enabled while there is something to fade: an
      // always-on layer would put the bar through an offscreen texture for
      // the whole session to buy an effect that only appears when the path
      // outgrows the bar.
      layer.enabled: crumbFlick.maxX > 0
      layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: crumbMask
        // The threshold is where the mask's alpha starts cutting and the
        // spread is how softly it does it. Both default to zero, which
        // means "cut nothing" — the mask was being read correctly and
        // changing precisely nothing. Half and full is the soft-edge
        // recipe: the ramp in the mask becomes a ramp in the alpha.
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
      }

      readonly property bool overLeft: crumbFlick.contentX > 1
      readonly property bool overRight: crumbFlick.contentX < crumbFlick.maxX - 1
      // 64px of ramp, as a fraction, and never more than a third of the
      // bar — on a narrow pane a fixed 36 would be most of the trail.
      readonly property real fadeAt: crumbFlick.width > 0
        ? Math.min(0.33, 64 / crumbFlick.width) : 0

      // The WHEEL drives this; a drag does not. Every crumb is a click
      // target, and a Flickable that takes drags turns a slightly unsteady
      // click into a scroll instead of a step up the tree.
      interactive: false

      readonly property real maxX: Math.max(0, contentWidth - width)
      // A CHUNK, not a step. One crumb a notch means spinning the wheel
      // six times to get back to the root of a deep path, which is not
      // scrolling, it is winding. Most of the bar per notch covers the
      // trail in a couple of strokes and still leaves enough of the old
      // view on screen to keep your bearings.
      readonly property real chunk: Math.max(120, crumbFlick.width * 0.6)

      // PINNED TO THE END, so the step that falls off is the one nearest
      // the root — the part you can most afford to lose sight of, and the
      // part the wheel is there to bring back.
      function pinEnd() {
        crumbWheel.elastic.halt(crumbFlick);
        crumbFlick.contentX = crumbFlick.maxX;
        // With a way back down on the end, the end is not where you are.
        // Where you are wins: never scrolled off the left.
        for (let i = 0; i < crumbTrail.children.length; ++i) {
          const c = crumbTrail.children[i];
          if (c.modelData && c.modelData.path === term.cwd) {
            if (c.x < crumbFlick.contentX)
              crumbFlick.contentX = Math.max(0, c.x - 8);
            break;
          }
        }
      }
      // The trail is rebuilt whenever the path changes, so this fires then
      // and not while you are reading it: scrolling back and standing
      // still does not yank you forward again.
      onContentWidthChanged: Qt.callLater(crumbFlick.pinEnd)
      onWidthChanged: Qt.callLater(crumbFlick.pinEnd)


    Row {
      id: crumbTrail
      height: crumbFlick.height
      spacing: 0

      Repeater {
        model: term.crumbList

        delegate: Row {
          id: crumbRow
          required property var modelData
          required property int index

          // FULL HEIGHT, and that is what levels the trail with the rest of
          // the bar. A Row lays its children out along x and leaves y alone,
          // so a delegate that sized itself to its label sat at the very top
          // of the strip with every other thing on the bar centred beside it
          // — measured at five pixels of air above the crumbs and eighteen
          // below. Standing the delegate the full height of the bar gives
          // the labels inside it a parent worth centring against, and it is
          // what lets the separator below be a rule rather than a character.
          height: crumbFlick.height

          // NO ENTRANCE. Each step used to fade and slide in as it was
          // created, which was written for the case of one step being
          // added to the end of the trail. The Repeater's model is the
          // whole path, so a path change destroys and rebuilds EVERY step,
          // and all of them ran it at once — the entire trail blinking on
          // each navigation. That is not movement, it is a flicker, and at
          // 140ms it is over before it reads as anything.
          //
          // What the trail actually does now is travel: the miller columns
          // slide and the trail simply is what it is when they arrive.

          // ── the separator ────────────────────────────────────────
          // A plain slash, which is what a path is written with. It was a
          // chevron, then a hairline, then a leaned rule cut to the bar's
          // exact height — and the leaned one was the wrong kind of exact:
          // a rule has ends, and ends have to be reasoned about every time
          // the bar's height or its border changes. A character has none of
          // that. It sits on the same baseline as the names either side of
          // it and moves with them.
          //
          // msgBorder, the hairline colour, so the separator stays chrome
          // and does not compete with the steps it is separating.
          Text {
            anchors.verticalCenter: parent.verticalCenter
            // NONE AFTER THE FILESYSTEM ROOT, which is already a slash —
            // "/" then "home" reads as "/home" and a separator between
            // them would double it. Everything else gets one, `~`
            // included, which is why this asks what came BEFORE rather
            // than counting from the start.
            visible: index > 0 && term.crumbList[index - 1].path !== "/"
            opacity: modelData.ghost === true ? 0.45 : 1
            text: " / "
            color: Zenon.border
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(15)
          }

          Text {
            id: crumbLabel
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.label
            // The last crumb is where you are; the rest are somewhere to
            // go. They stay muted under the pointer: a path is something
            // you READ, and lighting a segment up as the cursor crosses it
            // makes the whole bar twitch on the way to somewhere else.
            // They are still clickable — see below.
            // Where you are is the step whose path IS cwd, not the last
            // one: past it the trail goes on as the way back down.
            color: term.crumbDropPath === modelData.path ? Zenon.cyan
              : modelData.path === term.cwd
              ? term.crumbInk : Zenon.muted
            // the way back down — see crumbDeep. Lit fully while a drag
            // is over it, so the target reads as a target.
            opacity: modelData.ghost === true
              && term.crumbDropPath !== modelData.path ? 0.45 : 1
            font.family: Zenon.face
            font.weight: Font.Medium
            font.pixelSize: Zenon.px(15)

            // the step a drag is over, lit like a directory about to take
            // one — see crumbDrop. Behind the label, not beside it: in a
            // Row a sibling would take up room in the trail.
            Rectangle {
              z: -1
              anchors.fill: parent
              anchors.leftMargin: -4
              anchors.rightMargin: -4
              anchors.topMargin: -2
              anchors.bottomMargin: -2
              radius: 4
              visible: term.crumbDropPath === modelData.path
              color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.12)
            }

            MouseArea {
              anchors.fill: parent
              onClicked: term.goTo(modelData.path)
            }
          }
        }
      }

      // ── what you are looking FOR, beside where you are looking ──────
      // The bar answers "where am I". During a search that is only half
      // the answer, and the other half was written in the search strip —
      // which closes the moment you press Return. So the results were a
      // directory of files from all over the tree with nothing on screen
      // saying what they had in common.
      //
      // It sits at the end of the path because that is what it qualifies:
      // this directory, these matches. The mode word stays over on the
      // right where it already was; repeating it here would be two labels
      // for one fact.
      Item {
        width: term.searchMode !== "" ? 10 : 0
        height: 1
      }

      Rectangle {
        id: searchChip
        // not a crumb, but it sits in the trail crumbDrop.pathAt walks, which
        // asks whatever is under a drag for its modelData (as pinEnd asks
        // every child of the trail)
        readonly property var modelData: null
        anchors.verticalCenter: parent.verticalCenter
        visible: term.searchMode !== ""
        width: visible ? chipText.implicitWidth + 18 : 0
        height: 21
        radius: Zenon.windowRadius
        // ── THE COLOUR OF THE THING, NOT OF "A SEARCH" ──────────
        // Sand was right while every chip was a search. A tag has a
        // colour of its own — it is most of what a tag IS — and a
        // collection has one too, so the chip wears it and matches
        // the row in the sidebar it came from. A find or a grep has
        // no colour to borrow and keeps the sand.
        readonly property color ink: {
          if (term.searchMode === "tag") return term.tagInk(term.searchQuery);
          if (term.searchMode === "collection" && !term.scratchOpen) {
            const f = term.collById(term.collOpenId);
            if (f && f.ink) return Zenon[f.ink] || Zenon.cyan;
            return Zenon.cyan;
          }
          return Zenon.sand;
        }
        color: Qt.rgba(searchChip.ink.r, searchChip.ink.g,
                       searchChip.ink.b, 0.10)
        border.width: 1
        // tinted, not the shared rule — the ring is half of what says
        // which kind of search this is
        border.color: Qt.rgba(searchChip.ink.r, searchChip.ink.g,
                              searchChip.ink.b, 0.32)

        Text {
          id: chipText
          anchors.centerIn: parent
          // THE MARK OF THE THING IT IS SHOWING. A magnifier was right
          // while every chip was a search; a tag page and a collection
          // are not searches, and labelling them with one made the
          // sidebar and the chip disagree about what you were looking
          // at. Each wears what it is listed under.
          text: (term.searchMode === "tag" ? "\uF02B"
                 : term.searchMode === "collection" && !term.scratchOpen ? "\uEC78"
                 : "\uF002") + "  " + term.searchQuery
          color: searchChip.ink
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
      }
    }
    }

    // The ramp the trail is cut with: opaque through the middle, falling to
    // nothing at whichever end still has trail beyond it, so the fade
    // appears on the side there is more to see and only there.
    //
    // A REAL CHILD OF THE BAR, and that is the whole trick. Written inline
    // as the value of maskSource it never renders: a ShaderEffectSource
    // that is only referenced from a property is not in the scene, so its
    // texture comes back empty — and an empty mask does not mean "no mask",
    // it means every pixel has zero alpha, which took the entire trail with
    // it. hideSource keeps the gradient itself off the bar while it goes on
    // being rendered into the texture, which is exactly what it is for.
    Rectangle {
      id: crumbRamp
      width: Math.max(1, crumbFlick.width)
      height: Math.max(1, crumbFlick.height)
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0
          color: crumbFlick.overLeft ? "#00000000" : "#ff000000" }
        GradientStop { position: crumbFlick.fadeAt; color: "#ff000000" }
        GradientStop { position: 1.0 - crumbFlick.fadeAt; color: "#ff000000" }
        GradientStop { position: 1.0
          color: crumbFlick.overRight ? "#00000000" : "#ff000000" }
      }
    }

    ShaderEffectSource {
      id: crumbMask
      width: crumbRamp.width
      height: crumbRamp.height
      sourceItem: crumbRamp
      hideSource: true
      visible: false
    }

    // The shell's one scroll (morpheus Elastic) on its side: either way
    // the wheel or the fingers go moves the trail along, a chunk a notch
    // (more when spun), with the ends that give. Anchored to the trail
    // but not inside it, and off while the trail is, so it never eats the
    // wheel over a search bar that wants it.
    ElasticScroll {
      id: crumbWheel
      anchors.fill: crumbFlick
      view: crumbFlick
      horizontal: true
      enabled: crumbFlick.visible
      step: crumbFlick.chunk
    }

    // ── DROPPED ON A STEP OF THE PATH ─────────────────────────────
    // A crumb is a directory like any directory row, so a drop on one asks
    // the same Move / Copy question, and a drag held over one for
    // springMs goes there (crumbSpring).
    //
    // ONE DropArea over the whole trail, not one per crumb, for the
    // reason dropHint is one over the whole body: going somewhere
    // rebuilds the trail — every step, see crumbRow — and a DropArea
    // inside a step would be destroyed with the drag still over it.
    // This one outlives every path, and asks which step is under the
    // pointer instead.
    DropArea {
      id: crumbDrop
      anchors.fill: crumbFlick
      enabled: crumbFlick.visible
      // The step under a point in this item's space, or "" for none:
      // a crumb row and its separator both count as that step, the
      // search chip and the space past the end as nothing.
      function pathAt(x, y) {
        const p = crumbTrail.mapFromItem(crumbDrop, x, y);
        const c = crumbTrail.childAt(p.x, p.y);
        return (c && c.modelData && c.modelData.path) ? String(c.modelData.path) : "";
      }
      // ── THE TRAIL MOVES UNDER A STILL POINTER TOO ──────────────
      // A window resize, the trail re-pinning to its end, the wheel, or
      // the trail being rebuilt after a hold went somewhere: the step
      // under the pointer changes and no drag event says so. So the
      // last point is kept and asked again — to put the light on the
      // right step, not to start a hold: only a pointer that actually
      // moves arms one, or a hold would go up the path a step a second
      // on its own.
      property real atX: 0
      property real atY: 0
      function rehover() {
        if (crumbDrop.containsDrag)
          term.crumbHover(crumbDrop.pathAt(crumbDrop.atX, crumbDrop.atY), false);
      }
      Connections {
        target: crumbFlick
        function onWidthChanged() { Qt.callLater(crumbDrop.rehover); }
        function onContentXChanged() { crumbDrop.rehover(); }
        function onContentWidthChanged() { Qt.callLater(crumbDrop.rehover); }
      }
      onPositionChanged: (d) => {
        crumbDrop.atX = d.x;
        crumbDrop.atY = d.y;
        term.crumbHover(crumbDrop.pathAt(d.x, d.y), true);
      }
      onExited: term.crumbHover("", false)
      onDropped: (d) => {
        const into = crumbDrop.pathAt(d.x, d.y);
        term.crumbHover("", false);
        if (into === "") return;
        term.dropUris(term.urlsFrom(d), d.proposedAction, into,
                      crumbDrop, d.x, d.y);
      }
    }



    // ── the filter, inline ──────────────────────────────────────
    // No card, no overlay. `/` or f puts the keyboard here and the list
    // narrows as you type; the query lives in the path bar beside the
    // counts, because that is where everything else about the current view
    // is already written. The field is only as wide as what is in it, so
    // an empty filter takes no room at all.
    Row {
      id: filterInline
      anchors.right: crumbStatus.left
      anchors.rightMargin: term.query !== "" || filterField.activeFocus ? 14 : 0
      anchors.verticalCenter: crumbInner.verticalCenter
      spacing: 6
      visible: term.query !== "" || filterField.activeFocus
      opacity: crumbBar.chromeInk

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "\uF002"
        color: Zenon.cyan
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(15)
      }

      TextInput {
        id: filterField
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(8, Math.min(260, contentWidth + 2))
        color: Zenon.cyan
        selectionColor: Zenon.cyan
        selectedTextColor: Zenon.onAccent
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(17)
        clip: true
        // Only a CHANGED query moves the cursor to the top. Switching panes
        // writes the arriving pane's own query into this field, and that
        // reset its cursor to row 0 every time you crossed over.
        onTextChanged: {
          if (term.act.query === text) return;
          term.act.query = text;
          term.act.sel = 0;
        }
        Keys.onEscapePressed: (e) => {
          e.accepted = true;
          filterField.text = "";
          term.act.query = "";
          term.contentRef.forceActiveFocus();
        }
        Keys.onReturnPressed: (e) => {
          e.accepted = true;
          term.contentRef.forceActiveFocus();
        }
        Keys.onUpPressed: (e) => { e.accepted = true; term.moveSel(-1); }
        Keys.onDownPressed: (e) => { e.accepted = true; term.moveSel(1); }

        // The caret, since a bare TextInput on a bar has no frame to say
        // where the keyboard is — and the field's OWN, for the reason the
        // search bar's carries: a second one drawn at contentWidth is in
        // the wrong place as soon as the caret is not at the end.
        cursorDelegate: Caret { field: filterField }
      }
    }

    // ── the settings hatch ────────────────────────────────────────
    // The switches you flip WHILE you are working — hidden files, which
    // view, how much of the desktop shows through — at the far end of the
    // bar that already reports what the window is doing. Almost every one
    // of them has a key as well, and the panel is less a second way of
    // working than the place those keys are finally written down.
    Item {
      id: prefsToggle
      opacity: crumbBar.chromeInk
      enabled: crumbBar.chromeLive
      anchors.right: parent.right
      anchors.rightMargin: 8
      anchors.verticalCenter: crumbInner.verticalCenter
      width: 30
      height: crumbInner.height

      Text {
        anchors.centerIn: parent
        // nf-fa-bars, as an escape — a literal nerd glyph does not survive
        // the trip through a shell heredoc, and arrives as nothing at all.
        text: "\uF0C9"
        color: (term.prefsRef.open || term.burgerOn) ? Zenon.cyan
          : (prefsHov.hovered ? Zenon.white : Zenon.muted)
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(16)
      }

      HoverHandler { id: prefsHov }
      MouseArea {
        anchors.fill: parent
        // ── THE WINDOW'S MENU, NOT A SECOND KEY FOR ONE SHEET ─────
        // This opened the settings panel outright. A hamburger in the
        // corner of a window is the place everything without a home
        // goes, and spending it on one sheet — which the palette also
        // opens, and which is mostly a written-down copy of keys that
        // already work — left the most reachable control in the window
        // doing the least. Settings is in the menu now, as a row.
        //
        // From the button's bottom edge, the way the row menu drops out
        // of its row. It is at the right edge of the window, so the
        // card has nowhere to go but left: the popup surface slides to
        // fit, which is what Slide is for.
        onClicked: {
          if (term.menuPopRef.menu.open) { term.menuPopRef.menu.close(); return; }
          term.burgerOn = true;
          term.menuPopRef.menu.openCustom(prefsToggle,
                          { x: prefsToggle.width, y: prefsToggle.height },
                          term.menuPopRef.menu.windowItems, false, true);
        }
      }
    }

    // ── one pane or two ───────────────────────────────────────────
    // Split mode had only a key and a menu row; this is the switch for
    // it, beside the hamburger. Lit in the accent while the window is
    // split, the way the hamburger is lit while its menu is open.
    Item {
      id: splitToggle
      opacity: crumbBar.chromeInk
      enabled: crumbBar.chromeLive
      anchors.right: prefsToggle.left
      anchors.verticalCenter: crumbInner.verticalCenter
      // not in a file picker, which has one pane (see toggleDual)
      width: term.picking ? 0 : 30
      visible: !term.picking
      height: crumbInner.height

      Text {
        anchors.centerIn: parent
        // nf-fa-columns, as an escape (see the hamburger's note)
        text: "\uF0DB"
        color: term.dual ? Zenon.cyan
          : (splitHov.hovered ? Zenon.white : Zenon.muted)
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(15)
        Behavior on color { ColorAnimation { duration: Zenon.fast } }
      }

      HoverHandler { id: splitHov }
      MouseArea {
        anchors.fill: parent
        onClicked: term.toggleDual()
      }
    }

    // ── what is running, in a drawer ──────────────────────────────
    // A browser's downloads button, and for the same reason: work that
    // takes time is not the thing you are doing, it is a thing that is
    // happening, and it belongs at the edge of the window rather than in
    // a card floating over the corner of it.
    //
    // The panel that used to sit in the bottom right could only ever show
    // ONE transfer, which was fine while transfers took turns. They no
    // longer do — see the note on `jobs` — so what is needed is a list,
    // and a list wants somewhere to hang from.
    //
    // IT IS NOT THERE WHEN THERE IS NOTHING TO SAY. An idle button that
    // reports nothing is a permanent invitation to check on nothing, and
    // the whole point of putting this in the bar is that the bar is
    // already where you look to find out what the window is doing.
    Item {
      id: jobsToggle
      opacity: crumbBar.chromeInk
      enabled: crumbBar.chromeLive
      anchors.right: splitToggle.left
      anchors.rightMargin: 2
      anchors.verticalCenter: crumbInner.verticalCenter
      readonly property bool live: Jobs.model.count > 0
      // ONE COLOUR, READ BY EVERYTHING. The glyph, the count, the glow and
      // the burst all wear it, so "something went wrong" is a single fact
      // about the drawer rather than four things that have to be kept in
      // step. Red is reserved for exactly this — the same rule the confirm
      // card's verbInk follows.
      // Bad news first — a failure alongside a success is still a
      // failure to go and look at. Then green, but only once nothing is
      // RUNNING: green while a second job is still going would be
      // reporting the batch finished when half of it has not.
      readonly property color tone: Jobs.faults > 0 ? Zenon.red
        : (Jobs.live === 0 && Jobs.done > 0 ? Zenon.green
                                                   : Zenon.cyan)
      width: jobsToggle.live ? 32 : 0
      visible: width > 0.5
      height: crumbInner.height
      // Grows and collapses rather than appearing: it sits between the
      // status chip and the hamburger, and a button that pops into
      // existence shoves everything to its left across in one frame.
      Behavior on width {
        NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease }
      }

      // How lit the glow is, 0 to 1. Driven by the two animations below
      // rather than bound to anything: it has to BURST when a job starts
      // and then settle into a breath, and a binding can only ever say
      // one of those.
      property real glow: 0

      // ── the glow ────────────────────────────────────────────────
      // A blurred COPY of the glyph underneath the real one, not the
      // glyph itself blurred — blurring the thing you are meant to read
      // is how an icon becomes a smudge. The copy is what spreads; the
      // glyph on top of it stays sharp.
      Item {
        anchors.centerIn: parent
        width: parent.height
        height: parent.height
        opacity: jobsToggle.glow
        visible: opacity > 0.01
        // it swells with the burst, which is most of what makes a glow
        // read as an event rather than as a colour
        scale: 1.0 + 0.55 * jobsToggle.glow
        layer.enabled: true
        layer.effect: MultiEffect {
          blurEnabled: true
          // blurMax is the kernel, which is the actual softness knob —
          // `blur` alone is only the fraction of it that gets used. The
          // menu's shadow note spells this out at length.
          blurMax: 48
          blur: 1.0
          brightness: 0.5
          saturation: 0.4
          autoPaddingEnabled: true
        }

        Text {
          anchors.centerIn: parent
          text: jobsGlyph.text
          color: jobsToggle.tone
          font: jobsGlyph.font
        }
      }

      Text {
        id: jobsGlyph
        anchors.centerIn: parent
        // nf-fa-download, as an escape — a literal nerd glyph does not
        // survive the trip through a shell heredoc and arrives as
        // nothing at all. The browser's own sign for "things are coming
        // in", which is what this is.
        text: "\uF019"
        color: jobsHov.hovered && Jobs.faults === 0
          ? Zenon.white : jobsToggle.tone
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(15)
      }

      // How many, when there is more than one — the same thing a browser
      // does, and the reason the glyph alone is not enough now that jobs
      // run together.
      Text {
        anchors.right: parent.right
        anchors.rightMargin: -1
        anchors.top: parent.top
        anchors.topMargin: 5
        visible: Jobs.model.count > 1
        text: Jobs.model.count
        color: Zenon.black
        style: Text.Outline
        styleColor: jobsToggle.tone
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(10)
      }

      // ON HOVER, not on click. Checking what is running is a glance, and
      // a glance should not cost a click and then a second click to put
      // it away again.
      HoverHandler {
        id: jobsHov
        onHoveredChanged: {
          term.jobsOverGlyph = hovered;
          if (hovered) term.jobsDrawerRef.openFrom(jobsToggle);
          term.jobsDrawerRef.settle();
        }
      }

      // A BURST when a job starts, then a breath for as long as any is
      // running. Two animations rather than one, because they answer two
      // different questions — "something just began" and "something is
      // still going" — and one curve cannot say both.
      SequentialAnimation {
        id: jobsGlowBurst
        NumberAnimation { target: jobsToggle; property: "glow"; to: 1.0;
                          duration: 140; easing.type: Easing.OutQuad }
        NumberAnimation { target: jobsToggle; property: "glow"; to: 0.5;
                          duration: 460; easing.type: Easing.InQuad }
      }

      SequentialAnimation {
        id: jobsFaultBurst
        NumberAnimation { target: jobsToggle; property: "glow"; to: 1.0;
                          duration: 110; easing.type: Easing.OutQuad }
        NumberAnimation { target: jobsToggle; property: "glow"; to: 0.62;
                          duration: 320; easing.type: Easing.InQuad }
      }

      // FINISHING IS NEWS TOO. It bursts like a start and a fault do,
      // and then it STAYS — settling to a floor instead of fading out,
      // because the green is the receipt and a receipt that dims itself
      // after half a second is one you had to be watching for.
      SequentialAnimation {
        id: jobsDoneBurst
        NumberAnimation { target: jobsToggle; property: "glow"; to: 1.0;
                          duration: 130; easing.type: Easing.OutQuad }
        NumberAnimation { target: jobsToggle; property: "glow"; to: 0.55;
                          duration: 420; easing.type: Easing.InQuad }
      }

      SequentialAnimation {
        id: jobsGlowPulse
        // jobsLive, not live: rows outlive the work now, and a drawer
        // sitting there green is finished — breathing at you is what
        // something still running does.
        running: Jobs.live > 0 && !jobsGlowBurst.running
                 && !jobsFaultBurst.running && !jobsDoneBurst.running
        loops: Animation.Infinite
        NumberAnimation { target: jobsToggle; property: "glow"
                          to: Jobs.faults > 0 ? 0.95 : 0.78
                          duration: 880; easing.type: Easing.InOutQuad }
        NumberAnimation { target: jobsToggle; property: "glow"
                          to: Jobs.faults > 0 ? 0.45 : 0.28
                          duration: 880; easing.type: Easing.InOutQuad }
      }

      // and out when the last one finishes, rather than freezing at
      // whatever the pulse was on
      NumberAnimation {
        id: jobsGlowOut
        target: jobsToggle
        property: "glow"
        to: 0
        duration: Zenon.normal
        easing.type: Zenon.ease
      }

      Connections {
        target: Jobs
        function onStartedChanged() {
          jobsGlowOut.stop();
          jobsGlowBurst.restart();
        }
        // A failure bursts too, and harder: it settles to a brighter floor
        // than a start does, so a drawer with bad news in it is lit even
        // when nothing is running behind it.
        function onFaultedChanged() {
          jobsGlowOut.stop();
          jobsFaultBurst.restart();
        }
        // Only when the LAST one lands. Each job in a batch finishing
        // would otherwise re-burst the glyph while the rest are still
        // going, which reads as "done" three times before it is.
        function onFinishedChanged() {
          if (Jobs.live > 0) return;
          jobsGlowOut.stop();
          jobsDoneBurst.restart();
        }
      }

      // The model's own count, rather than a second counter kept in step
      // with it by hand: the last job leaving IS the count reaching zero.
      Connections {
        target: Jobs.model
        function onCountChanged() {
          if (Jobs.model.count > 0) return;
          jobsGlowBurst.stop();
          jobsGlowOut.restart();
          term.jobsDrawerRef.open = false;
        }
      }
    }

    // What used to be a bar of its own along the bottom. Two full-width
    // strips to carry one line of text each was a strip too many, and the
    // right-hand end of the path bar was empty — so the count, the view
    // and whatever the last action had to say live here now.
    Row {
      id: crumbStatus
      opacity: crumbBar.chromeInk
      enabled: crumbBar.chromeLive
      anchors.right: jobsToggle.left
      anchors.rightMargin: 10
      // up by the separator's own pixel: it is the bar's bottom EDGE, not
      // part of the inside, and centring across it sat everything low
      anchors.verticalCenter: crumbInner.verticalCenter
      spacing: 14

      // ── the status, as a chip ──────────────────────────────────
      // It was a bare line of red in a bar of greys: every note wore the
      // colour of an alarm, and none of them looked like they belonged to
      // the bar they sat in. Same rounded shape as the search chip and the
      // key caps, and the colour says which KIND of news it is rather than
      // only that there is some — red for refused or failed, sand for an
      // ordinary note.
      Rectangle {
        id: statusChip
        anchors.verticalCenter: parent.verticalCenter
        // THE COLOUR IS HELD THE SAME WAY THE WORDS ARE. Reading
        // root.statusBad live meant a failure turned sand the instant the
        // status cleared — because clearing resets the flag — and then
        // faded out yellow. It has to keep the tone it was shown in for as
        // long as it is still on screen.
        property bool shownBad: false
        readonly property color tone: statusChip.shownBad ? Zenon.red : Zenon.sand
        // It ARRIVES and it LEAVES, rather than blinking in and out. The
        // timeout above means the disappearance is something that happens
        // on its own while you are looking elsewhere, and a thing that
        // vanishes between frames reads as a glitch; a thing that fades
        // reads as finished. The width goes with it so the bar beside it
        // is not shoved sideways in one step.
        // IT KEEPS THE WORDS WHILE IT GOES. Binding the text straight to
        // root.status meant that clearing the status emptied the label in
        // the same frame, the width collapsed with it, and the opacity
        // animation then played out on something nought pixels wide — the
        // fade was running the whole time and there was nothing left to
        // see it on. `shown` holds the last message until the fade is
        // over, so there is something to fade.
        property string shown: ""
        onOpacityChanged: if (statusChip.opacity === 0) statusChip.shown = "";

        opacity: term.status !== "" ? 1 : 0
        visible: opacity > 0.01
        // ── NEVER WIDER THAN THE BAR CAN GIVE ────────────────────
        // A message is as long as whatever failed made it, and an
        // uncapped chip pushed the crumbs off and then ran out of the
        // window. Capped at about two fifths of the bar, elided, and the
        // whole of it is one hover away — see statusNote.
        readonly property real cap: Math.max(160, crumbBar.width * 0.42)
        readonly property bool cut: statusInk.implicitWidth + 18 > statusChip.cap
        width: statusChip.shown !== "" ? Math.min(statusInk.implicitWidth + 18, statusChip.cap) : 0
        height: 21
        radius: Zenon.windowRadius
        // Twice the slowest of the motion tokens, and deliberately outside
        // them: every other transition in this window answers something
        // you just did, so it should be over before you look for it. This
        // one happens on its own three seconds later, while you are
        // reading something else — the going IS the notice, and at 170ms
        // it is finished before it has been seen.
        Behavior on opacity {
          NumberAnimation { duration: Zenon.slow * 2; easing.type: Zenon.ease }
        }
        Behavior on width {
          NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
        }
        color: Qt.rgba(statusChip.tone.r, statusChip.tone.g,
                       statusChip.tone.b, 0.10)
        border.width: 1
        // the tone is the message: a warning ringed like everything else
        // reads as ordinary
        border.color: Qt.rgba(statusChip.tone.r, statusChip.tone.g,
                              statusChip.tone.b, 0.32)

        Text {
          id: statusInk
          anchors.centerIn: parent
          // ONLY the status. There used to be a fallback here that read
          // "1 copied · p to paste" for as long as something was on the
          // clipboard — which never emptied, so the chip could never fade
          // out and every message after it was a silent text swap. It was
          // also teaching a key on a permanent basis, which is what the
          // hint bar and F1 are for.
          text: statusChip.shown
          color: statusChip.tone
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
          width: Math.min(implicitWidth, statusChip.width - 18)
          elide: Text.ElideRight
        }
        MouseArea {
          id: statusChipMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: statusChip.cut ? Qt.PointingHandCursor : Qt.ArrowCursor
          // Held while you read; let go and it counts down afresh.
          onContainsMouseChanged: {
            if (statusChipMa.containsMouse) term.statusClearRef.stop();
            else term.armStatusClear();
          }
          onClicked: term.copyText(statusChip.shown, "message copied")
        }
      }

      // ── the undo, offered ──────────────────────────────────────
      // The status chip's shape in cyan: a thing to press rather than a
      // thing to read. See undoOffer.
      Rectangle {
        id: undoChip
        anchors.verticalCenter: parent.verticalCenter
        readonly property bool on: term.undoOffer && term.undoLabel !== ""
        opacity: undoChip.on ? 1 : 0
        visible: opacity > 0.01
        width: undoChip.on ? undoInk.implicitWidth + 20 : 0
        height: 21
        radius: Zenon.windowRadius
        Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
        Behavior on width { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
        color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b,
                       undoMa.pressed ? 0.28 : (undoMa.containsMouse ? 0.18 : 0.10))
        border.width: 1
        border.color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.40)
        clip: true

        Text {
          id: undoInk
          anchors.centerIn: parent
          textFormat: Text.StyledText
          text: "\uF0E2&#160;&#160;" + term.undoLabel
            + "&#160;&#160;<font color=\"" + Zenon.hex(Zenon.muted) + "\">u</font>"
          color: Zenon.cyan
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
        MouseArea {
          id: undoMa
          anchors.fill: parent
          hoverEnabled: true
          enabled: undoChip.on
          onClicked: term.undo()
        }
      }

      // ── A MODE HAS TO BE VISIBLE ──────────────────────────────
      // Everything else in this window is one keystroke that does one
      // thing; visual mode changes what the arrow keys mean until it is
      // turned off, so it says so — a mark of its own in magenta, the
      // colour no other state in this bar wears, rather than a word in
      // the same ink as the count beside it.
      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: term.visualOn
        text: "\uEA70"
        color: Zenon.magenta
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(15)
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: {
          const n = term.markedCount;
          // see the mark before this one
          // WHAT IT ADDS UP TO, not just how many. terminus.js has had
          // selectionSize since the status strip was written and nothing
          // ever called it — so "12 selected" told you nothing about
          // whether those twelve would fit on the stick you were copying
          // them to. Directories are left out of the total rather than
          // counted at their record size; the function's own note says why.
          if (n > 0) {
            const sz = Terminus.selectionSize(term.markedRows(), term.dirSizes);
            const tail = sz.pending > 0
              ? (sz.bytes > 0 ? "  \u00b7  " + Terminus.formatSize(sz.bytes) + " + measuring\u2026"
                              : "  \u00b7  measuring\u2026")
              : (sz.bytes > 0 ? "  \u00b7  " + Terminus.formatSize(sz.bytes) : "");
            return n + " selected" + tail;
          }
          if (term.visualOn) return "0 selected";
          const items = term.view.length
            + (term.view.length === 1 ? " item" : " items");
          // in the trash, how much it holds is what you are there to see
          return term.inTrash && term.trashSize !== ""
            ? items + " \u00b7 " + term.trashSize : items;
        }
        color: (term.markedCount > 0 || term.visualOn) ? Zenon.cyan : Zenon.muted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(14)
      }

      // What the zoom is at, and a control for it — the shared meter
      // (ZoomMeter.qml, picasso's bar has it too). Thumbs and the two list
      // layouts scale independently, so it follows whichever view you are
      // in. Its steps are the same 0.1 notch the keys and ctrl+wheel use.
      ZoomMeter {
        anchors.verticalCenter: parent.verticalCenter
        // across the whole travel, not out of some absolute maximum
        value: (term.activeZoom - term.zoomMin)
               / Math.max(0.0001, term.zoomMax - term.zoomMin)
        onSeek: (f) => term.setZoom(term.zoomMin + f * (term.zoomMax - term.zoomMin))
        onStep: (d) => term.zoomBy(d * 0.1)
        onReset: term.zoomReset()
      }

      // WHAT IT IS SEARCHING, and nothing else. The view mode used to
      // share this slot as its fallback — a word that named what you were
      // already looking at, beside a menu that is one click away and says
      // the same thing. Nothing was read off it that the window was not
      // already showing.
      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: term.searchMode !== ""
        text: term.searchMode === "grep" ? "grep"
          : (term.searchMode === "tag" ? "tag"
             : (term.searchMode === "collection" ? "collection" : "find"))
        color: Zenon.sand
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(14)
      }

      // Which branch, while the mode is on and there is one to name. The
      // gutter says what changed; this says what it changed against, which
      // is the other half of the question and the only part a per-row mark
      // cannot carry. Silent outside a repository — the mode being on is
      // not a promise that there is a repository to report on.
      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: term.git && term.gitBranch !== ""
        text: "\uE725  " + term.gitBranch   // nf-dev-git_branch
        color: Zenon.muted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(14)
      }
    }

    // ── WHAT THE SHEET IS DOING, SAID ON THE BAR ─────────────────
    // The send-to header lives HERE rather than inside the sheet, and
    // that is the whole of why it looks right: inside the sheet, anything
    // see-through reveals the file list, because the file list is what is
    // behind it. On the bar it sits over the window's own background with
    // the compositor's blur behind that, so its translucency shows what
    // the bar's translucency shows.
    //
    // The breadcrumb steps aside while it is up — you are choosing a
    // destination, not reading where you already are — and the two cross
    // fade on the sheet's own opacity, so the bar changes its mind at
    // exactly the speed the sheet arrives.
    //
    // Read as a sentence: this thing → that place. The verb and the arrow
    // are punctuation and stay muted; the nouns carry the colour.
    // THE DIALOG SHEETS' HEADER, in the same place and for the same
    // reason as the send picker's. A glyph and a name: these cards are
    // about one thing and its name is the whole of what there is to say.
    //
    // CENTRED OVER THE CARD, not over the bar — the card is the thing
    // it titles — and kept inside the bar's ends. The card hangs centred
    // under the bar, so the two agree; read off the splice rather than
    // assumed, so a card that is not centred is still titled over it.
    Item {
      id: barHead
      anchors.top: parent.top
      anchors.bottom: crumbInner.bottom
      readonly property real mid: term.spliceX + term.spliceW / 2 - term.sideRef.width
      readonly property real want: term.barSend ? sendToBarHead.implicitWidth
        : barHeadRow.implicitWidth
      width: Math.min(want, parent.width - 32)
      x: Math.round(Math.max(16, Math.min(parent.width - width - 16,
                                          mid - width / 2)))
      opacity: term.sheetInk
      visible: opacity > 0.01

      Row {
        id: barHeadRow
        visible: !term.barSend
        anchors.centerIn: parent
        spacing: 8
        Text {
          id: barHeadGlyph
          anchors.verticalCenter: parent.verticalCenter
          visible: term.barGlyph !== ""
          text: term.barGlyph
          color: term.barGlyphInk
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(16)
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, barHead.parent.width - 32
            - (barHeadGlyph.visible ? barHeadGlyph.implicitWidth + 8 : 0))
          elide: Text.ElideMiddle
          text: term.barTitle
          color: term.barTitleInk
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: Zenon.px(15)
        }
      }

      Item {
        id: barSendHead
        visible: term.barSend
        anchors.fill: parent
        clip: true
        Row {
          id: sendToBarHead
          anchors.centerIn: parent
          spacing: 6

          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: term.sendToRef.sending
            text: term.sendToRef.op === "move" ? "\uDB80\uDD90" : "\uDB80\uDD8F"
            // crumbInk, the ink the step you are standing on uses. The header
            // takes the bar's place while it is up, so its punctuation is the
            // bar's punctuation — muted put it a shade below the chrome it had
            // replaced.
            color: term.crumbInk
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(15)
          }

          // Air after the verb, so the glyph reads as a label on the line
          // rather than as the first character of the filename.
          // A Row skips an invisible child entirely, so the spacers go with
          // the nouns they were spacing and `go` reads as arrow, air, place.
          Item { width: 6; height: 1; visible: term.sendToRef.sending }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: term.sendToRef.icon || ""
            // The Row's own 6 is the gap between PHRASES; a glyph and the
            // name it labels are one phrase and were reading as two things
            // jammed together.
            rightPadding: 3
            color: term.sendToRef.iconInk
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(15)
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            // COUNTED OFF `names`, not off `paths`. They are the same length
            // for a copy and a move, and for `go` the subject is a name with
            // no path behind it — read from the path list it said "0 items".
            width: Math.min(implicitWidth, 300)
            elide: Text.ElideMiddle
            text: (term.sendToRef.names.length === 1 ? term.sendToRef.names[0]
                : term.sendToRef.names.length + " items") || ""
            color: term.sendToRef.iconInk
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(15)
          }

          Item { width: 6; height: 1 }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: !!term.sendToRef.current
            // A DIFFERENT ARROW FOR A DIFFERENT SENTENCE. Copy and move are
            // putting a thing somewhere, and the heavy arrow reads as
            // delivery; `go` is you travelling, so it gets the plain one.
            text: term.sendToRef.op === "go" ? "\uF061" : "\uDB85\uDFB7"
            color: term.crumbInk
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(15)
          }

          Item { width: 6; height: 1 }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: !!term.sendToRef.current
            text: term.sendToRef.glyphOf(term.sendToRef.current) || ""
            rightPadding: 3
            color: term.sendToRef.blocked ? Zenon.muted : Zenon.cyan
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(15)
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: !!term.sendToRef.current
            width: Math.min(implicitWidth, 260)
            elide: Text.ElideMiddle
            text: (term.sendToRef.current ? term.sendToRef.current.name : "") || ""
            color: term.sendToRef.blocked ? Zenon.muted : Zenon.cyan
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(15)
          }
        }
      }
    }

    // the bar's bottom edge — open over a sheet spliced out of it (see
    // root.noteSheet), the two halves either side of the card
    Rectangle {
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      readonly property real gapL: Math.max(0, term.spliceX - term.sideRef.width)
      width: term.sheetInk > 0.01 ? Math.min(parent.width, gapL) : parent.width
      height: 1
      color: Zenon.border
    }
    Rectangle {
      anchors.bottom: parent.bottom
      readonly property real gapR: Math.max(0, term.spliceX + term.spliceW - term.sideRef.width)
      x: Math.min(parent.width, gapR)
      width: Math.max(0, parent.width - x)
      visible: term.sheetInk > 0.01
      height: 1
      color: Zenon.border
    }
  }


  // ── column headers ────────────────────────────────────────────
  // Only the list view has columns to name. The miller layout's panes are
  // one column each and the grid has none, so the strip collapses rather
  // than standing there labelling nothing.
  Rectangle {
    id: colHeads
    width: parent.width
    // ONE PANE ONLY. With two, each carries its own heading bar inside its
    // own half — because each has its own view, and a strip up here can be
    // only one height for both. A grid beside a list would have had a
    // 22px band of nothing over the grid, which is what it looked like:
    // a sort bar placeholder.
    height: term.colHeadsOn && term.viewMode === "list" && !term.dual
      ? 22 : 0
    visible: height > 0
    clip: true
    // Transparent: the sidebar is beside this strip now rather than
    // under it, so there is only the listing to head. See headArea.
    color: "transparent"

    // Inset by the sidebar, because the columns name what is in the
    // LISTING and the sidebar is not the listing. Spanning the full width
    // put "NAME" above the bookmarks, labelling a column that is not
    // there — and the label moved out from over the rows it belongs to.
    //
    // Over the ACTIVE pane, wherever that is; only when that pane is a
    // list; and the SAME ColHeadBar the two-pane case draws inside each
    // half, so there is one definition of what a heading row is.
    ColHeadBar { term: chrome.term
      x: term.activePaneX
      width: term.activePaneW
      height: parent.height
      visible: term.viewMode === "list"
    }

    // ── AND IT GOES DARK WITH THE SHEET ────────────────────────────
    // This strip sits between the path bar and the top of an open sheet,
    // and it is the one piece of chrome that was not following them: two
    // grounds, one of them transparent, so the blurred listing read
    // straight through a 22px band directly under a header that had gone
    // solid black. Which is exactly what "the header is not opaque" looks
    // like from the outside.
    //
    // OVER the heading bar, not behind it: headPlate covers the split
    // panes' headings for the same reason, and one layout showing NAME ·
    // SIZE · MODIFIED under an open sheet while the other shows a black
    // band is the same window disagreeing with itself.
    Rectangle {
      anchors.fill: parent
      color: Zenon.black
      opacity: term.sheetInk
      visible: opacity > 0.01
    }

    // No bottom rule here: ColHeadBar draws its own. This one lay exactly
    // over it — two translucent borders stacked read as one visibly darker
    // line than every other border — and it sat above the sheet's dimmer,
    // so it also stayed lit when everything else went dark.
  }

  // ── the body, with the sidebar beside it ──────────────────────
  // The row owns the leftover height; the sidebar and the body divide the
  // width of it. Reading it off bodyBox instead was a loop: bodyBox sizes
  // itself from its parent, and its parent is this.
  Row {
    id: bodyRow
    width: parent.width
    height: parent.height - tabStrip.height - crumbBar.height
      - colHeads.height - portalBar.height

    // NOT BLURRED behind a card any more: the window is darkened
    // instead — see root.cardScrim, which every card's overlay wears.


    Item {
      id: bodyBox
      width: parent.width
      height: parent.height

      // The ACTIVE half's heading strip height, which is what the miller
      // frame and the hit tests mean by "the top of the listing". Each
      // half's own is asked for by side — see root.paneHeadH.
      readonly property real headH: term.paneHeadH(term.paneSide)
      readonly property real topH: bodyBox.headH

      // One strip per half, each following its own view and neither
      // moving. `live` marks the one the keyboard is in, the same way the
      // rows below it do.
      ColHeadBar { term: chrome.term
        x: term.paneX(0)
        width: term.paneW(0)
        visible: term.paneHeadH(0) > 0
        live: term.paneLRef.active
        pane: term.paneLRef
        z: 3
      }

      ColHeadBar { term: chrome.term
        x: term.paneX(1)
        width: term.paneW(1)
        visible: term.dual && term.paneHeadH(1) > 0
        live: term.paneRRef.active
        pane: term.paneRRef
        z: 3
      }

      // ── THE ACTIVE HALF STANDS IN FRONT ───────────────────────────
      // Two halves of the same black with a 1px seam between them: which
      // one has the keyboard was said only by the cursor's fill and a
      // brighter heading, and both are small. Now the active half casts
      // a vertical shadow across the seam onto the other — the way a
      // sheet stands over the window. The other half is not darkened.
      // Over the views and under the headings, and it takes no input.
      // Two strips, one either side of the seam, each the shadow the
      // half beside it casts when it is the active one. They stay put
      // and crossfade: a single strip moved to the other half, eased,
      // and swept across the whole window every time the keyboard
      // crossed over. Tied to the divider directly, so a dragged
      // split carries them with no lag.
      Repeater {
        model: 2
        delegate: Rectangle {
          required property int index
          // index 0 falls on the right half (cast by an active left),
          // index 1 on the left half (cast by an active right)
          readonly property bool on: term.dual && term.paneSide === (index === 0 ? 0 : 1)
          z: 2.5
          // two curated shadows: dark glass takes the long dense one;
          // on paper that is a black slab, so a light theme gets a short,
          // faint one — the depth of a page lifted, not a hole
          width: Zenon.light ? 48 : 100
          height: parent.height
          x: index === 0 ? term.paneSplit + 1 : term.paneSplit - width
          visible: opacity > 0.01
          opacity: on ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
          gradient: Gradient {
            orientation: Gradient.Horizontal
            // BLACK IN EVERY THEME: a shadow, not a fade into the pane —
            // in the theme's ground a light theme's seam lost its depth
            // and read as a pale smear (Buck, 2026-10-08).
            // dark: 0.6 at the seam, a soft core, a long tail (the solid
            // 1.0 → 0.85 core was too heavy — user, 2026-10-08).
            // light: a soft even falloff from 16%, no core at all.
            GradientStop { position: index === 0 ? 0.0 : 1.0; color: Qt.rgba(0, 0, 0, Zenon.light ? 0.16 : 0.6) }
            GradientStop { position: index === 0 ? 0.08 : 0.92; color: Qt.rgba(0, 0, 0, Zenon.light ? 0.12 : 0.46) }
            GradientStop { position: index === 0 ? 0.25 : 0.75; color: Qt.rgba(0, 0, 0, Zenon.light ? 0.07 : 0.28) }
            GradientStop { position: index === 0 ? 0.5 : 0.5; color: Qt.rgba(0, 0, 0, Zenon.light ? 0.03 : 0.12) }
            GradientStop { position: index === 0 ? 0.75 : 0.25; color: Qt.rgba(0, 0, 0, Zenon.light ? 0.008 : 0.035) }
            GradientStop { position: index === 0 ? 1.0 : 0.0; color: "transparent" }
          }
        }
      }

      // ── the divider, as something you can grab ────────────────
      // Not a child of the sidebar: `side` clips, so a handle inside it
      // could only ever be as wide as the 1px line it sits on. So it
      // overlays the seam from INSIDE the body instead.
      //
      // It used to sit in the Row between the sidebar and the body, which is
      // the one place it must not be: a Row lays out every visible child, so
      // the 9px handle was 9px of layout. The body was pushed 9px right of
      // the sidebar and, being sized as `parent.width - side.width`, ran 9px
      // off the right-hand edge of the window — which is why the preview
      // pane had 12px of padding down its left side and 3px down its right.
      // A child of bodyBox costs the Row nothing.
      MouseArea {
        id: sideGrip
        width: 9
        height: parent.height
        // z above the body so the cursor changes over the seam even where a
        // row is drawn right up to it
        z: 9
        visible: term.sidebar
        hoverEnabled: true
        cursorShape: Qt.SizeHorCursor
        preventStealing: true
        // Straddling the divider, half either side — and measured from
        // bodyBox's own left edge, which IS the divider, so this no longer
        // has to follow side.width at all.
        x: -4

        // Where in the grip it was taken hold of, so the seam stays under
        // the same part of the pointer for the whole drag.
        property real grab: 0

        // Measured in the window's coordinates, never in the grip's own.
        //
        // The grip travels with the divider, so while you drag it slides
        // along underneath the pointer — and a delta taken from `m.x` is
        // measured against an origin that is itself moving. Each frame
        // overshot and the next corrected, which is what made the divider
        // jitter. The window does not move, so a position mapped into it is
        // stable.
        onPressed: (m) => {
          sideGrip.grab = m.x;
        }
        onPositionChanged: (m) => {
          if (!sideGrip.pressed) return;
          const px = sideGrip.mapToItem(term.contentRef, m.x, 0).x;
          term.sidebarWidth = Math.max(term.sidebarMin,
            Math.min(term.sidebarMax, px - sideGrip.grab + 4));
        }
        // Double click springs it back, so a width dragged somewhere silly is
        // one gesture to undo rather than a careful drag back.
        onDoubleClicked: term.sidebarWidth = 200
      }

    // Ctrl+wheel zooms — see the overlay at the bottom of this Item.
    // It cannot live here: a pointer handler on a parent is only offered
    // an event after every child has declined it, and all three views are
    // Flickables that handle the wheel themselves. So this container's own
    // handler was never reached and the gesture did nothing.

    // ── the two lists, one per half ─────────────────────────────
    // Neither ever moves. See PaneList, which is where the argument for
    // that lives; with one pane the right-hand one simply is not drawn.
    PaneList { term: chrome.term; id: listA; pane: term.paneLRef }
    PaneList { term: chrome.term; id: listB; pane: term.paneRRef }

    // ── AND THE CURSOR TRAVELS, HERE TOO ────────────────────────
    // The same bar the sheets wear. It was a fill on each row, which
    // cannot move between two of them — the mark blinked off one and on to
    // the next — and this is the list it matters most on, because it is
    // the one the cursor spends all day in.
    //
    // NOT WHILE THE ROW IS cursorOnly. With things ticked, or on the pane
    // the keyboard is not in, the cursor is drawn as an OUTLINE rather
    // than a fill so it cannot be mistaken for a selection; the bar stands
    // down for that and the row draws its own border, as before.
    // SelectBar and EntryRow are files of their own beside this one
    // (terminus/SelectBar.qml, terminus/EntryRow.qml), shared with plato:
    // each is handed this window as its `host`.
    SelectBar {
      host: term
      view: listA
      index: term.paneLRef.sel
      rowH: term.rowH
      rowY: term.paneLRef.rowTop(term.paneLRef.sel)
      on: listA.on && !term.cursorOutline(term.paneLRef)
      // NOT WHILE EXTENDING A SELECTION. Holding a direction in visual
      // mode steps the cursor a row at a time as fast as the key repeats,
      // and an eased bar spends every one of those steps still catching
      // up with the last — it trails the block it is supposed to be
      // drawing the end of. It snaps while the selection grows.
      animate: !term.visualOn
    }
    SelectBar {
      host: term
      view: listB
      index: term.paneRRef.sel
      rowH: term.rowH
      rowY: term.paneRRef.rowTop(term.paneRRef.sel)
      on: listB.on && !term.cursorOutline(term.paneRRef)
      animate: !term.visualOn
    }

    // ── columns ─────────────────────────────────────────────────
    // Yazi's miller layout: where you came from, where you are, and what
    // you are about to open. The point is that moving the cursor changes
    // the right-hand pane rather than the whole window, so you can look
    // into a directory without entering it.
    // ── STEPPING THROUGH THE TREE, AS MOVEMENT ──────────────────
    // Miller's columns are a window onto the tree, and walking into a
    // directory slides that window one column along. Drawn as a cut — the
    // three columns simply becoming three different columns — there is
    // nothing for the eye to follow and no sense of which way you went;
    // out and back looked identical to going two levels down.
    //
    // A CLIPPING FRAME the columns move inside. The Row used to be placed
    // here directly, so shifting it would have shifted its own clip with
    // it and the columns would have drawn over the chrome either side.
    // The frame holds the pane's place; the Row travels within it.
    Item {
      id: millerBox
      x: term.activePaneX
      y: bodyBox.topH
      width: term.activePaneW
      height: parent.height - bodyBox.topH
      visible: term.viewMode === "columns"
      clip: true

      // AN ITEM, NOT A ROW. A Row lays its children out in declaration
      // order, and these three swap places — so they are placed by the
      // SLOT they are standing in instead. See millerOrder.
      Item {
        id: miller
        width: parent.width
        height: parent.height

        // ── TWO COLUMNS WHILE A FIND IS UP ────────────────────────
        // Results are not a directory — they come from all over the tree
        // — so the parent column has nothing true to say about them. It
        // was drawing the parent of the directory the search STARTED in,
        // which is a quarter of the pane spent on an answer to a question
        // nobody asked. With it gone the results and the preview split
        // the pane, which is what miller columns are for: the list, and
        // what the cursor is on.
        //
        // A find only. A grep already puts its own second column to work
        // — see showMeta — and its results are lines inside files rather
        // than places, so that layout is the one it wants.
        //
        // AND NOT A TAG OR A COLLECTION, which this briefly did on the
        // reasoning that they are results too. They are not: a find is
        // typed, looked at and left, so borrowing the pane's shape for
        // the duration costs nothing. A collection is a PLACE you keep
        // and come back to — it has a view of its own now — and forcing
        // the two-column shape on top of that meant the view it
        // remembered never showed. Two columns is for the thing you are
        // passing through, not the thing you live in.
        readonly property bool flat: term.searchMode === "find"

        readonly property real w0: miller.flat
          ? 0 : Math.round(miller.width * 0.24)
        // THE FREED QUARTER GOES TO THE RESULTS, all of it. The preview
        // keeps the 0.42 it has in the three-column layout — it is
        // showing one file and never wanted more — so the list takes the
        // parent column's room on top of its own and ends up the wider of
        // the two. Which is the right way round: a result is a PATH, and
        // a path is long.
        readonly property real w1: Math.round(
          miller.width * (miller.flat ? 0.58 : 0.34))
        // One seam instead of two when the parent is gone.
        readonly property int seams: miller.flat ? 1 : 2
        readonly property real w2:
          miller.width - miller.w0 - miller.w1 - miller.seams

        function slotX(sl) { return sl === 0 ? 0
          : (sl === 1 ? (miller.flat ? 0 : miller.w0 + 1)
                      : miller.w0 + miller.w1 + miller.seams); }
        function slotW(sl) { return sl === 0 ? miller.w0
          : (sl === 1 ? miller.w1 : miller.w2); }
        // Where the columns ARE, which is home except for the moment
        // after a step: millerStep drops them a third of a pane to one
        // side and the animator carries them back, so the motion reads as
        // the tree moving under a window that is standing still.
        //
        // A plain value, not a binding — see millerAnim, which writes it
        // from the render thread. Same for opacity and millerFade.
        x: 0
        opacity: 1

        MillerColumn { term: chrome.term
          id: colA
          slot: term.millerOrder[0] === 0 ? 0
              : (term.millerOrder[1] === 0 ? 1 : 2)
          x: miller.slotX(colA.drawnSlot)
          width: miller.slotW(colA.drawnSlot)
          height: parent.height
          // By SLOT, never by instance: rotating changes what this column
          // is about, and the binding follows it there.
          rows: colA.slot === 0 ? term.millerRowsParent
              : (colA.slot === 1 ? term.millerRowsCurrent
                               : term.millerRowsPreview)
        }

        MillerColumn { term: chrome.term
          id: colB
          slot: term.millerOrder[0] === 1 ? 0
              : (term.millerOrder[1] === 1 ? 1 : 2)
          x: miller.slotX(colB.drawnSlot)
          width: miller.slotW(colB.drawnSlot)
          height: parent.height
          // By SLOT, never by instance: rotating changes what this column
          // is about, and the binding follows it there.
          rows: colB.slot === 0 ? term.millerRowsParent
              : (colB.slot === 1 ? term.millerRowsCurrent
                               : term.millerRowsPreview)
        }

        MillerColumn { term: chrome.term
          id: colC
          slot: term.millerOrder[0] === 2 ? 0
              : (term.millerOrder[1] === 2 ? 1 : 2)
          x: miller.slotX(colC.drawnSlot)
          width: miller.slotW(colC.drawnSlot)
          height: parent.height
          // By SLOT, never by instance: rotating changes what this column
          // is about, and the binding follows it there.
          rows: colC.slot === 0 ? term.millerRowsParent
              : (colC.slot === 1 ? term.millerRowsCurrent
                               : term.millerRowsPreview)
        }

        // The two seams. They do not rotate — a divider is where one
        // column stops, not something a column owns.
        Rectangle {
          x: miller.w0; width: 1; height: parent.height
          visible: !miller.flat
          color: Zenon.border
        }
        Rectangle {
          x: miller.w0 + miller.w1 + miller.seams - 1
          width: 1; height: parent.height
          color: Zenon.border
        }

        // The media half of the third column — a picture, a film, a PDF,
        // an archive's tree. The DIRECTORY half is a rotating column like
        // the other two and sits above this; they are the same slot seen
        // two ways, which is why this takes slot 2's geometry.
        Item {
          id: previewPane
          x: miller.slotX(2)
          width: miller.slotW(2)
          height: parent.height
          clip: true

          // ── IT EASES IN, IT DOES NOT APPEAR ──────────────────────
          // The pane is filled once the columns have stopped, which is
          // deliberate: building a column of delegates syncs the scene
          // graph, and doing that mid-slide is the bump the transition
          // used to have. The cost is that the content then arrives on a
          // frame where nothing else is moving, and anything appearing at
          // full strength on a still frame POPS.
          //
          // So the pane carries its own short fade, reset by settlePreview
          // whenever the thing being shown actually changes. A plain
          // value, not a binding — previewFade writes it from the render
          // thread, like the slide and the columns' own fade.
          opacity: 1

          // ── THE WHOLE PANE IS THE DIRECTORY IT IS SHOWING ────────
          // Clicking a row in here already steps into the previewed directory.
          // The empty space below the rows did nothing, which made the pane
          // read as a picture OF a directory rather than as the directory —
          // and the gap below a short listing is most of the column.
          //
          // Declared FIRST, so it sits underneath: a row, a scrolling text
          // preview and an archive tree all take their own clicks before
          // this ever sees one. Only while a directory is what is being
          // shown; over a file this pane is a preview and not a door.
          MouseArea {
            anchors.fill: parent
            enabled: term.previewKind === "dir"
            acceptedButtons: Qt.LeftButton
            onClicked: {
              const r = term.currentRow();
              if (r && r.isDir) term.goTo(r.path);
            }
          }


          // ── a picture or a film, and what it IS ────────────────────
          // Anchored to the TOP of the pane rather than centred in it,
          // because the facts underneath are part of the preview now. A
          // frame floating in the middle with a block of text below it reads
          // as two unrelated things, and worse, both of them move: every
          // change of aspect ratio slid the metadata up or down the pane.
          //
          // Rounded the same 5px as the grid tiles, and for the same reason
          // the note over thumbClip gives — the corners belong on the frame,
          // never on the pane it is letterboxed inside.
          Column {
            id: media
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 16
            // A touch tighter at the top than at the sides: the bar above is a hard
            // edge and the pane's own left divider is not, so an equal 16 read as
            // more air above than beside.
            anchors.topMargin: 12
            spacing: 10
            // NOT text. A picture's name belongs above it, because the
            // picture is the thing and the name labels it. A document is
            // read from its first line down, so anything above that line
            // is in the way — text carries its name at the FOOT instead,
            // with the counts, where the two read as one footer. See the
            // facts column.
            visible: term.previewKind === "image" || term.previewKind === "video"
              || term.previewKind === "audio"

            // The frame gets at most this much of the pane and the rest
            // belongs to the facts. Uncapped, a tall photograph filled the
            // pane on its own and pushed every row of metadata off the
            // bottom of it.
            readonly property real boxW: media.width
            readonly property real boxH: Math.max(80, previewPane.height * 0.56)

            ClippingRectangle {
              id: mediaClip
              anchors.horizontalCenter: parent.horizontalCenter
              visible: shot.status === Image.Ready
              color: "transparent"
              radius: Zenon.windowRadius

              // The aspect ratio comes from the Image's IMPLICIT size, the
              // decoded source, and never from paintedWidth/paintedHeight —
              // the painted size follows the item's own, which is this
              // rectangle's, and reading it here would be a binding loop.
              // LATCHED WHEN THE PICTURE LANDS, not bound to it.
              //
              // The value never circled — sourceSize is fixed, so the
              // implicit size is the decoded size and nothing to do with
              // this item. The DEPENDENCY did: height reads
              // shot.implicitHeight, and shot fills this item, so Qt saw
              // height depending on a child that depends on height and
              // called it a loop. It is right to: a graph that circles
              // is re-evaluated until it happens to settle, which is
              // work done on every layout pass for an answer that only
              // changes when a new file is shown.
              property real ar: 1
              function takeAspect() {
                if (shot.implicitWidth > 0 && shot.implicitHeight > 0)
                  mediaClip.ar = shot.implicitWidth / shot.implicitHeight;
              }
              Connections {
                target: shot
                function onStatusChanged() {
                  if (shot.status === Image.Ready) mediaClip.takeAspect();
                }
              }
              width: Math.max(1, Math.min(media.boxW, media.boxH * mediaClip.ar))
              height: Math.max(1, Math.min(media.boxH, media.boxW / mediaClip.ar))

              Image {
                id: shot
                anchors.fill: parent
                // One Image for both kinds, because they differ only in
                // where the pixels come from: a picture is shown as itself,
                // a video as the frame ffmpeg pulled out of it for the grid.
                //
                // The row is re-checked here, not just previewKind. Moving
                // the cursor changes the row a frame before loadPreview has
                // decided what the new one is, so for that frame this
                // binding asked for a DIRECTORY as an image and Qt logged
                // "Cannot open: file:///home/buck/Desktop" every time the
                // cursor passed one.
                source: {
                  const r = term.currentRow();
                  if (!r || r.isDir) return "";
                  // a video's frame and an audio file's cover both live in
                  // the thumbnail cache; a picture is shown as itself
                  if (term.previewKind === "video"
                      || term.previewKind === "audio") {
                    return term.thumbFile[r.path]
                      ? "file://" + term.thumbFile[r.path] : "";
                  }
                  if (term.previewKind !== "image") return "";
                  if (!Terminus.isImage(r.name)) return "";
                  // A raw or a HEIC is not something Qt can open, so the
                  // pane shows the rendered copy — the same cache a
                  // film's frame comes from, for the same reason.
                  if (term.needsRender(r)) {
                    return term.thumbFile[r.path]
                      ? "file://" + term.thumbFile[r.path] : "";
                  }
                  return Strings.fileUrl(r.path);
                }
                // ── AND IF QT STILL CANNOT READ IT ──────────
                // The blind list is a seed; this is what makes it
                // complete. One failure per format, then every file of
                // that kind takes the rendered path from the start.
                onStatusChanged: {
                  if (status !== Image.Error) return;
                  const rr = term.currentRow();
                  if (rr && !rr.isDir && Terminus.isImage(rr.name))
                    term.noteBlind(rr.name);
                }
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                // capped rather than full-size: a 6000px background decoded
                // at native resolution to fill a 300px pane is most of a
                // second and a lot of memory for a picture nobody is
                // looking at yet
                sourceSize.width: 900
                sourceSize.height: 900
              }
            }

            // NO NAME, AND NO RULE. The column beside this one has the
            // row selected and named already, so every preview repeating
            // it was the pane telling you the one thing you could already
            // see — and with the name gone the rule under it was dividing
            // a picture from its own caption, which needs no dividing.
            //
            // Text keeps a rule: there it separates a document you are
            // reading from the footer under it. See the facts column.



          }

          // ── THE FACTS, WHICH ARE NOT ALWAYS AT THE TOP ────────────
          // For a picture or a film they belong under the frame, where
          // they read as its caption. For TEXT there is no frame — the
          // document itself fills the pane — and a block of counts above
          // it pushes the first line of the file down out of the way of
          // the thing you opened the preview to read. So they sit at the
          // foot of the pane there, the way a status line does.
          //
          // One Repeater either way: only the anchoring differs, and an
          // anchor set to undefined is how QML is told to forget one.
          Column {
            id: facts
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 20
            anchors.rightMargin: 16

            // Measured rather than guessed, so a label added later
            // cannot quietly overflow the way "longest line" did.
            readonly property real labelW: factsMetric.width + 6
            TextMetrics {
              id: factsMetric
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(16)
              text: "longest line"
            }

            // PLACED, NOT ANCHORED EITHER WAY ROUND.
            //
            // This was a pair of ternaries handing `undefined` to whichever
            // anchor was not wanted. QML does not reliably drop an anchor
            // that way — both stayed live, top won, and the footer rendered
            // at the TOP of the pane with the document crushed into the one
            // line above it. One `y` cannot contradict itself.
            // A FOOTER NEEDS SOMETHING TO BE THE FOOT OF. An empty
            // file is still previewKind "text", so the counts were
            // pinned to the bottom of the pane behind a rule with
            // nothing above it — a separator separating the metadata
            // from a blank. With no document the counts ARE the
            // content, so they sit where it would have been.
            readonly property bool atFoot:
              (term.previewKind === "text" && term.previewText !== "")
              || term.previewKind === "pdf"
            y: facts.atFoot
              ? Math.max(0, parent.height - facts.height - 12)
              : media.y + media.height + 10
            visible: media.visible || term.previewKind === "text"
              || term.previewKind === "pdf"
            spacing: 3

            // Only for text, where this column is a footer under the
            // document rather than a caption under a picture — a picture
            // already has the rule that media draws above these rows.
            // Edge to edge of the pane, not of the rows: the rows are inset
            // to read as text, but a rule inset with them read as a stray
            // underline rather than the seam between document and footer.
            // A Column places only y, so x is free to step out of it.
            Rectangle {
              x: -facts.anchors.leftMargin
              width: parent.width + facts.anchors.leftMargin
                + facts.anchors.rightMargin
              height: 1
              color: Zenon.border
              visible: facts.atFoot
            }

            Item {
              width: 1
              height: 7
              visible: facts.atFoot
            }

            // NO NAME HERE. The column beside this one already has the
            // row selected and named; repeating it over its own preview
            // was the pane telling you something you were looking at.


            Repeater {
              // Every property this reads is named here on purpose: a
              // binding re-evaluates when a PROPERTY it touched changes,
              // and currentRow() is a function call, which is not one.
              // Without `sel` and `view` in the expression the panel kept
              // the first file's size and date for the whole directory.
              model: {
                const kind = term.previewKind;
                const info = term.previewInfo;
                const at = term.sel;
                const all = term.view;
                if (kind !== "image" && kind !== "video"
                    && kind !== "audio" && kind !== "text"
                    && kind !== "pdf")
                  return [];
                const r = term.currentRow();
                if (!r) return [];
                const out = [];
                const dot = "  \u00b7  ";
                const add = (k, v) => { if (v) out.push([k, v]); };
                if (info && info.dims) out.push(["dimensions", info.dims]);
                if (kind === "video" && info) {
                  add("duration", info.duration);
                  add("codec", info.codec
                    + (info.container ? dot + info.container : ""));
                  add("frame rate", info.fps);
                  add("bitrate", info.bitrate);
                } else if (kind === "audio" && info) {
                  // the tags first: on a track they are the answer, and
                  // the codec is the footnote
                  add("title", info.title);
                  add("artist", info.artist);
                  add("album", info.album
                    + (info.date ? dot + info.date : ""));
                  add("track", info.track);
                  add("duration", info.duration);
                  add("codec", info.codec
                    + (info.container ? dot + info.container : ""));
                  add("audio", [info.rate, info.channels]
                    .filter((x) => !!x).join(dot));
                  add("bitrate", info.bitrate);
                } else if (kind === "pdf" && info) {
                  // What the document says about itself first, where it
                  // says anything — a great many PDFs carry neither a
                  // title nor an author.
                  add("title", info.title);
                  add("author", info.author);
                  add("pages", info.pages);
                  add("page size", info.pageSize);
                  add("pdf", info.version
                    + (info.encrypted ? dot + "encrypted" : ""));
                } else if (kind === "text" && info) {
                  // Length, then shape, then the one that explains a
                  // page of mojibake when you meet one.
                  add("lines", info.lines);
                  add("words", info.words + dot
                      + info.chars + " characters");
                  add("longest line", info.longest);
                  add("encoding", info.encoding);
                } else if (info) {
                  add("format", info.format);
                  add("colour", [info.depth, info.colorspace]
                    .filter((x) => !!x).join(dot));
                }
                out.push(["size", Terminus.formatSize(r.size)]);
                out.push(["modified", Terminus.formatTime(r.mtime)]);
                return out;
              }

              delegate: Row {
                required property var modelData
                width: media.width
                height: 24
                spacing: 10

                Text {
                  // WIDE ENOUGH FOR THE LONGEST LABEL THERE ACTUALLY IS,
                  // which is "longest line" and not "frame rate" — the
                  // text rows were added after this number was chosen.
                  // Right-aligned text that does not fit its box spills
                  // out of the LEFT of it, so the label was not merely
                  // cramped, it was hanging off the edge of the pane.
                  width: facts.labelW
                  height: parent.height
                  horizontalAlignment: Text.AlignRight
                  verticalAlignment: Text.AlignVCenter
                  text: modelData[0]
                  color: Zenon.muted
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(16)
                }

                Text {
                  width: media.width - facts.labelW - 10
                  height: parent.height
                  verticalAlignment: Text.AlignVCenter
                  text: modelData[1]
                  elide: Text.ElideRight
                  color: Zenon.white
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(16)
                }
              }
            }
          }

          // ── a typeface, in its own hand ────────────────────────────
          // Every other preview describes the file. This one IS it: Qt loads
          // the face and draws the specimen with it, which answers "what
          // does this look like" in a way no list of facts about a font ever
          // could.
          //
          // FontLoader reads the file on the fly and leaves nothing behind —
          // the family it registers lives only as long as the loader does,
          // so browsing a directory of fonts does not install any of them.
          // the shared specimen (FontSpecimen), as quick look and oracle
          // show a face
          FontSpecimen {
            id: fontPane
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 16
            // A touch tighter at the top than at the sides: the bar above is a hard
            // edge and the pane's own left divider is not, so an equal 16 read as
            // more air above than beside.
            anchors.topMargin: 12
            visible: term.previewKind === "font"
            // BOTH questions, not just previewKind. That one is settled a
            // frame behind the cursor, so stepping from a typeface onto
            // anything else asked Qt to load the new row as a font —
            // "Cannot load font: …/probe.tar.gz" in the log, once per step.
            // The name settles immediately.
            path: {
              const r = term.currentRow();
              if (!r || r.isDir || term.previewKind !== "font") return "";
              if (!Terminus.isFont(r.name)) return "";
              return r.path;
            }
          }

          // ── what is inside an archive ─────────────────────────────
          // A column of full paths was what the tool prints, not what the
          // question is: forty lines that all begin with the same three
          // directories say nothing about the SHAPE of the archive. Folded
          // back into the hierarchy it came out of, it reads the way yazi
          // draws a directory — which is what the pane beside it is already
          // showing you.
          //
          // Inert. There is nothing in here to open until it is extracted,
          // so unlike the directory preview above it takes no clicks.
          ListView {
            id: archiveList
            anchors.fill: parent
            anchors.margins: 16
            // level with the text preview beside it — see the note there
            anchors.topMargin: 0
            anchors.bottomMargin: 0
            visible: term.previewKind === "archive"
            model: term.previewKind === "archive" ? term.previewTree : []
            clip: true
            interactive: true
            // drained with the model — see the note on the list, above
            reuseItems: term.previewKind === "archive"
            boundsBehavior: Flickable.StopAtBounds
            onVisibleChanged: if (!visible) contentY = 0;

            delegate: Item {
              required property var modelData
              width: archiveList.width
              height: Math.round(21 * term.zoom)

              // The guides are BOX-DRAWING characters and they have to stack
              // exactly under the ones on the row above, which only a
              // fixed-pitch face guarantees — the names beside them are set
              // in the proportional one every other listing here uses.
              Text {
                id: treeGuide
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                // `|| ""` on every field this delegate reads, and it is not
                // defensive noise: reuseItems recycles a delegate by
                // rebinding modelData, and on the frame the model swaps —
                // one archive to the next, or an archive to nothing — the
                // recycled row is briefly bound to a row of a different
                // shape. Qt logged one "Unable to assign [undefined] to
                // QString" per delegate per swap.
                text: modelData.prefix || ""
                // muted, not msgBorder: that is a hairline colour carrying
                // 30% alpha and the guides came out as a suggestion of a
                // tree. They are structure — meant to be seen at a glance
                // and never read — which is exactly what muted is for.
                color: Zenon.muted
                font.family: Zenon.faceMono
                font.weight: Zenon.weight
                font.pixelSize: Math.round(15 * term.zoom)
              }

              Text {
                id: treeGlyph
                anchors.left: treeGuide.right
                anchors.verticalCenter: parent.verticalCenter
                visible: !!modelData.glyph
                width: visible ? Math.round(20 * term.zoom) : 0
                text: modelData.glyph || ""
                color: modelData.inkKey ? Zenon[modelData.inkKey] : (modelData.ink || Zenon.white)
                font.family: Zenon.faceMono
                font.weight: Zenon.weight
                font.pixelSize: Math.round(15 * term.zoom)
              }

              Text {
                anchors.left: treeGlyph.right
                anchors.leftMargin: 4
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.name || ""
                elide: Text.ElideRight
                color: modelData.nameKey ? Zenon[modelData.nameKey] : (modelData.nameInk || Zenon.white)
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Math.round(15 * term.zoom)
              }
            }
          }

          ScrollRail {
            owner: term
            target: archiveList
            on: archiveList.visible
            // Its RIGHT EDGE is against the PANE rather than the view, for
            // the reason the text pane's rail gives below: the view is
            // inset 16px and a rail hung off that sits nowhere near where
            // every other rail in this window sits.
            //
            // Its top and bottom are the VIEW's, which is the half that
            // was wrong here too — hung off the pane, the rail was taller
            // than the list it reports on, so the thumb was scaled against
            // a height that is not the viewport's.
            anchors.top: archiveList.top
            anchors.topMargin: 2
            anchors.bottom: archiveList.bottom
            anchors.bottomMargin: 2
            anchors.right: previewPane.right
            anchors.rightMargin: 2
          }

          // SCROLLABLE, because a preview that only ever shows the first
          // screenful is a preview of the top of a file. bat is asked for a
          // capped number of lines either way, but forty lines in a pane
          // twenty deep is half an answer.
          //
          // Wheel and drag both work because it is a Flickable; the rail
          // beside it is the same one every other view here uses.
          Flickable {
            id: textScroll
            // BELOW THE HEADER RATHER THAN BEHIND IT. This used to fill
            // the pane, which was right while text was the one kind with
            // no facts above it — see media.visible.
            anchors.top: media.visible ? media.bottom : parent.top
            // NONE when there is no header above it: the bar over the
            // pane is already a hard edge, and the three columns beside
            // this one start their first row flush with it.
            anchors.topMargin: media.visible ? 10 : 0

            anchors.left: parent.left
            anchors.right: parent.right
            // Stops above the facts when they are at the foot of the
            // pane, which is where text puts them — see the note on the
            // facts column.
            anchors.bottom: term.previewKind === "text" && facts.visible
              ? facts.top : parent.bottom
            anchors.bottomMargin: term.previewKind === "text" && facts.visible
              ? 10 : 0
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            // NO PADDING AT THE BOTTOM, and none at the top either when
            // there is no header above — the sides need it, because the
            // pane's divider is a hairline and text run up against it
            // reads as spilling out of the column, but the bar above is a
            // hard edge that already separates them and the three columns
            // beside this one start their first row flush with it. Inset,
            // the preview began a line and a half lower than the listing
            // it is a preview OF, which reads as the pane sagging. The top
            // margin is set above, since it now depends on the header
            // and on where the facts sit.
            visible: term.previewKind === "text"
            clip: true
            interactive: true
            boundsBehavior: Flickable.StopAtBounds
            // WRAPPED, so the width is the pane's and there is nothing
            // to scroll sideways to. A preview is for reading what is in
            // a file, and a line that runs off the right edge of a narrow
            // pane cannot be read without dragging it back and forth.
            contentWidth: width
            contentHeight: previewBody.implicitHeight
            // back to the top whenever the pane is showing something else
            onVisibleChanged: if (!visible) contentY = 0;

            Text {
              id: previewBody
              width: textScroll.width
              text: term.previewText
              // RichText, because bat's colours arrive as ANSI and are
              // translated rather than thrown away — that is the syntax
              // highlighting, and markdown comes through the same path
              textFormat: Text.RichText
              color: Zenon.white
              // AnywhereIfNeeded rather than plain Wrap: source lines and
              // long paths have no spaces to break at, and a word wider
              // than the pane would otherwise still overhang it.
              wrapMode: Text.WrapAtWordBoundaryOrAnywhere
              // plato's face (term.codeFamily): text as the editor sets it
              font.family: term.codeFamily
              font.weight: term.codeWeight
              font.pixelSize: Math.round(17 * term.zoom)
            }
          }

          // A new file starts at the top of itself, not wherever the last
          // one was left. previewText changes for every row the cursor
          // lands on, so this is the moment to reset.
          Connections {
            target: term
            function onPreviewTextChanged() { textScroll.contentY = 0; }
            // and the same for the tree, which stays visible from one
            // archive to the next and would otherwise open the second one
            // partway down
            // — keyed on previewTree, where an archive's tree lives now;
            // previewRows is a directory's, and never changed between two
            // archives
            function onPreviewTreeChanged() { archiveList.contentY = 0; }
          }

          ScrollRail {
            owner: term
            target: textScroll
            on: textScroll.visible
            // Its RIGHT edge is placed against the pane, not against
            // textScroll — the flickable is inset 16px so that its text
            // does not run into the edges, and hanging the rail off that
            // put it 18px in from the pane while every other rail here
            // sits 2px from its view. Its top follows the text, which no
            // longer starts at the top of the pane.
            //
            // Its TOP AND BOTTOM are the view's, though, and the bottom
            // used to be the pane's — so on a file with facts under it the
            // rail ran on past the text and down over them, and on every
            // file it claimed a height the thing it scrolls does not have.
            // A scrollbar is as tall as what it scrolls.
            anchors.top: textScroll.top
            anchors.topMargin: 0
            anchors.bottom: textScroll.bottom
            anchors.bottomMargin: 2
            anchors.right: previewPane.right
            anchors.rightMargin: 2
          }

          Image {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            // A touch tighter at the top than at the sides: the bar above is a hard
            // edge and the pane's own left divider is not, so an equal 16 read as
            // more air above than beside.
            anchors.topMargin: 12
            // Stops above the facts, which sit at the foot for a document
            // the same way they do for text — it used to fill the pane and
            // draw straight over them.
            anchors.bottom: facts.visible ? facts.top : parent.bottom
            anchors.bottomMargin: facts.visible ? 10 : 16
            visible: term.previewKind === "pdf"
            source: term.previewKind === "pdf" && term.previewStamp > 0
              ? "file://" + term.pdfStem + ".png?v=" + term.previewStamp : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: false
            sourceSize.width: 900
            sourceSize.height: 1200
          }

          Text {
            anchors.centerIn: parent
            visible: term.previewKind === "binary" || term.previewKind === "none"
            text: term.previewKind === "binary" ? "binary" : ""
            color: Zenon.muted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(13)
          }
        }
      }
    }

    // ── grid ────────────────────────────────────────────────────
    // Qt decodes the picture itself. There is no thumbnail cache and no
    // thumbnailer process behind this: sourceSize makes the loader scale
    // while decoding, so what lands in memory is already tile-sized, and
    // asynchronous keeps that off the render thread.
    // ── the two grids, one per half ─────────────────────────────
    PaneGrid { term: chrome.term; id: gridA; pane: term.paneLRef }
    PaneGrid { term: chrome.term; id: gridB; pane: term.paneRRef }

    // a soft shade from the bar onto whichever grid is scrolled
    // (TopShade.qml). Not on the lists or the columns (user, 2026-10-09):
    // over the frosted bar it read as a drop shadow under a row strip.
    Repeater {
      model: [gridA, gridB]
      delegate: TopShade {
        required property var modelData
        view: modelData
        on: modelData.on
        x: modelData.x
        y: modelData.y
        width: modelData.width
      }
    }

    // The listing's cursor, on the grid's two axes. Stands down for the
    // same case the lists do: with things ticked, or on the half the
    // keyboard is not in, the cursor is an outline rather than a fill.
    SelectCell {
      host: term
      view: gridA
      index: term.paneLRef.sel
      on: gridA.on && !term.cursorOutline(term.paneLRef)
      // As the lists do — see the note on listA's bar.
      animate: !term.visualOn
    }
    SelectCell {
      host: term
      view: gridB
      index: term.paneRRef.sel
      on: gridB.on && !term.cursorOutline(term.paneRRef)
      animate: !term.visualOn
    }

    // One rail per view that scrolls, each riding its own flickable —
    // four of them now, because there are four views and each belongs to
    // a half rather than to a role. Declared here, after the views, so
    // they draw over the tiles rather than under them.
    ScrollRail {
      owner: term
      target: gridA
      on: gridA.on
      anchors.right: gridA.right
      anchors.rightMargin: 2
      anchors.top: gridA.top
      anchors.topMargin: 2
      anchors.bottom: gridA.bottom
      anchors.bottomMargin: 2
    }

    ScrollRail {
      owner: term
      target: gridB
      on: gridB.on
      anchors.right: gridB.right
      anchors.rightMargin: 2
      anchors.top: gridB.top
      anchors.topMargin: 2
      anchors.bottom: gridB.bottom
      anchors.bottomMargin: 2
    }

    ScrollRail {
      owner: term
      target: listA
      on: listA.on
      anchors.right: listA.right
      anchors.rightMargin: 2
      anchors.top: listA.top
      anchors.topMargin: 2
      anchors.bottom: listA.bottom
      anchors.bottomMargin: 2
    }

    ScrollRail {
      owner: term
      target: listB
      on: listB.on
      anchors.right: listB.right
      anchors.rightMargin: 2
      anchors.top: listB.top
      anchors.topMargin: 2
      anchors.bottom: listB.bottom
      anchors.bottomMargin: 2
    }

    // In miller columns only the FOCUSED column gets one. The parent
    // column is context you glance at, and a second bar beside it would
    // be two scrollbars for one cursor.
    //
    // Positioned rather than anchored to its target: root.midCol is a child of
    // the `miller` Row, so a rail anchored to it would have to live in that
    // Row too — and a Row lays its children out side by side, so the bar
    // would take a slice of width from the columns instead of floating over
    // the one it belongs to. `miller` fills this parent, so root.midCol's own x
    // is already the offset needed here.

    ScrollRail {
      owner: term
      target: term.midCol.view
      on: term.viewMode === "columns"
      anchors.top: millerBox.top
      anchors.topMargin: 2
      anchors.bottom: millerBox.bottom
      anchors.bottomMargin: 2
      // The frame's coordinates, not the travelling Row's: a scrollbar
      // belongs to the pane, so it holds still while the columns move.
      x: millerBox.x + term.midCol.x + term.midCol.width - width - 2
    }

    // ── the second pane ─────────────────────────────────────────
    // Deliberately plain. It shows a directory, a cursor and its columns,
    // and nothing else: no filter, no marks, no preview, no view modes.
    // Everything a pane can DO belongs to the active one, and Tab, `o` or
    // a click in here is how this side becomes that.
    // The same neutral border every other seam in this window uses. A cyan
    // one was tried and read as decoration rather than structure — cyan
    // here means "chosen", and a line that is always there is not making a
    // choice. The CHEVRON on it is cyan, which is the one thing that is.
    //
    // UNDER THE POINTER IT IS CYAN, which is the sidebar's grip exactly:
    // the seam is neutral while it is only a seam, and says so the moment
    // it is a thing you can take hold of. That is not decoration — it is
    // the line answering the cursor that has just changed shape over it.
    Rectangle {
      width: 1
      height: parent.height
      x: term.paneSplit
      visible: term.dual
      color: splitGrip.pressed || splitGrip.containsMouse
        ? Zenon.cyan : Zenon.border
    }

    // The divider, as something you can take hold of. The sidebar's grip in
    // every respect — 9px straddling a 1px line, z above the body so the
    // cursor changes over the seam, and measured in a frame that does NOT
    // move: bodyBox's own width is fixed while the split is dragged, and
    // reading the delta off the grip would be reading it against an origin
    // sliding under the pointer.
    MouseArea {
      id: splitGrip
      width: 9
      height: parent.height
      x: term.paneSplit - 4
      z: 9
      visible: term.dual
      hoverEnabled: true
      cursorShape: Qt.SizeHorCursor
      preventStealing: true

      property real grab: 0
      onPressed: (m) => { splitGrip.grab = m.x; }
      onPositionChanged: (m) => {
        if (!splitGrip.pressed || bodyBox.width <= 0) return;
        const px = splitGrip.mapToItem(bodyBox, m.x, 0).x - splitGrip.grab + 4;
        term.paneFrac = Math.max(term.paneMinFrac,
          Math.min(term.paneMaxFrac, px / bodyBox.width));
        term.viewSaveRef.restart();
      }
      // back to even, the way the sidebar's grip springs back to 200
      onDoubleClicked: { term.paneFrac = 0.5; term.viewSaveRef.restart(); }
    }

    // Which side the keyboard is in, ON the divider — as a GRIP.
    //
    // It was a hairline around the whole active half, then a chevron on
    // the divider (`❮|`, `|❯`). Now two short bars, one either side of
    // the line: the shape every draggable seam wears, so the divider says
    // it can be taken hold of — and the bar on the side the keyboard is
    // in is lit, so it doubles as the split's indicator. The line between
    // them is what answers the pointer, turning cyan under it.
    //
    // Both panes still say it a second way — the inactive one's cursor is
    // an outline rather than a fill — so the grip is the confirmation, not
    // the only clue.
    Repeater {
      model: term.dual ? [0, 1] : []
      delegate: Rectangle {
        required property int modelData
        // the active side only — hover is the line's to answer, and
        // lighting both would hide the one thing this says
        readonly property bool lit: term.paneSide === modelData
        width: 2
        height: 14
        radius: 1
        x: modelData === 0 ? term.paneSplit - 4 : term.paneSplit + 3
        y: (parent.height - height) / 2
        z: 4
        color: lit ? Zenon.cyan : Zenon.muted
        Behavior on color { ColorAnimation { duration: Zenon.fast } }
      }
    }

    // ── the second half's chrome ────────────────────────────────
    // Its listing and its grid are PaneList/PaneGrid now, declared
    // alongside the first half's and never moved. What is left here is
    // the part that is about the half rather than about the listing: a
    // click on its empty space is still "I want to be over here", and a
    // half with nothing in it still has to say so.
    Item {
      id: otherPane
      // THE PASSIVE HALF, WHICHEVER THAT IS. This was pinned to side 1,
      // so with the right half active it lay over the ACTIVE rows and
      // turned every press that missed a row of the OTHER listing into a
      // step across: triangles, the rows below the left half's last one,
      // the space between. That was the fight.
      x: term.paneX(term.pas.side)
      width: term.paneW(term.pas.side)
      height: parent.height
      visible: term.dual
      // Clicks only. The views underneath draw the rows; this is the
      // space between and below them.
      //
      // Above the views rather than under them, because a Flickable takes
      // the left button for its own flick and never gives it back. Gated
      // on the hover hit test so a press that IS on a row reaches the row
      // and steps across once, not twice.
      property bool overRow: false

      HoverHandler {
        id: otherWatch
        onPointChanged: {
          const v = term.otherViewMode === "grid"
            ? term.gridOf(term.pas.side) : term.listOf(term.pas.side);
          otherPane.overRow = v.indexAt(
            otherWatch.point.position.x + v.contentX,
            otherWatch.point.position.y - v.y + v.contentY) >= 0;
        }
      }

      MouseArea {
        anchors.fill: parent
        enabled: term.dual && !otherPane.overRow
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: term.activatePane(term.pas.side)
      }

      // The same word at the same size as the active pane's — see the
      // note there. Two panes saying the same thing two different ways
      // reads as two different states.
      EmptyMark {
        anchors.centerIn: parent
        visible: term.dual && term.otherRows.length === 0
      }
    }

    // ── dropping onto this directory ────────────────────────────
    // ONE DropArea, and that is the fix.
    //
    // There were two, stacked on the same rectangle with the same keys: the
    // real one, and a second declared later that existed only to light up
    // the border. Later means on top, and the top DropArea is the one Qt
    // delivers to — so every drop landed on the decorative one, which had
    // no onDropped and quietly dropped it on the floor. Dragging a file
    // from artemis into terminus did nothing for exactly this reason.
    //
    // No `keys` filter either. Keys are matched against the SOURCE's
    // Drag.keys, which an application outside quickshell has no reason to
    // set — the honest test is whether what arrived carries file URLs, and
    // dropUris already checks that and ignores anything else.
    //
    // The high z keeps it above the click and wheel overlays.
    DropArea {
      id: dropHint
      anchors.fill: parent
      z: 7
      // WHERE it was dropped decides where it goes. With one pane that is
      // always here; with two, dropping on the right-hand side means the
      // right-hand side, which is most of what a second pane is for.
      // Tracked as the pointer moves so the row under it can light up:
      // a drop that is about to go INTO something has to say which thing,
      // or the only honest reading is "somewhere in this pane".
      onPositionChanged: (d) => {
        term.dropDir = term.dropDirAt(d.x, d.y);
        term.dropSide = !term.dual ? 0
          : (d.x >= term.paneX(1) ? 1 : 0);
        term.dragAssistMove(d.x, d.y);
      }
      onExited: { term.dropDir = ""; term.dragAssistStop(); }
      // A RESIZE MOVES THE ROWS under a pointer that has not moved — a
      // grid reflows its tiles, a split's halves change width — and no
      // drag event follows to say what is under it now. Asked again from
      // the last point the drag reported, a turn later so the views have
      // laid themselves out. The same re-reading assistTick does when an
      // edge scroll moves the rows.
      function reaim() {
        if (!dropHint.containsDrag) return;
        const x = term.assistAt.x, y = term.assistAt.y;
        term.dropDir = term.dropDirAt(x, y);
        term.dropSide = !term.dual ? 0 : (x >= term.paneX(1) ? 1 : 0);
        term.springCheck();
      }
      onWidthChanged: Qt.callLater(dropHint.reaim)
      onHeightChanged: Qt.callLater(dropHint.reaim)

      onDropped: (d) => {
        // The branches the drag opened are NOT shut here: the drop
        // question is about to ask about a row in one of them, and
        // folding it away under the menu loses the very thing you are
        // answering about. Held until the menu is answered — see
        // springHeld.
        term.dragAssistStop(true);
        const side = !term.dual ? term.paneSide
          : (d.x >= term.paneX(1) ? 1 : 0);
        const pane = side === term.paneSide ? term.cwd : term.otherCwd;
        const into = term.dropDir !== "" ? term.dropDir : pane;
        term.dropDir = "";
        if (!term.dropUris(term.urlsFrom(d), d.proposedAction, into,
                           dropHint, d.x, d.y))
          term.springShut(term.springHeld);
      }
    }

    // THE HALF IT WILL LAND IN, not the body. With a split open the body
    // is both panes, and lighting all of it said the drop was going
    // everywhere — the one thing a drop target exists to rule out.
    Rectangle {
      x: term.paneX(term.dropSide)
      width: term.paneW(term.dropSide)
      height: parent.height
      // Not while a directory is the target: two things lit at once says
      // the drop is going to both.
      visible: dropHint.containsDrag && term.dropDir === ""
      color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.07)
      border.width: 1
      border.color: Zenon.border
      z: 8
    }

    // ── the drag box ────────────────────────────────────────────
    // A DragHandler, not a MouseArea. Every row already has a MouseArea
    // for its click, and a MouseArea laid over them would either swallow
    // those clicks or never see the press; a pointer handler can sit above
    // the lot and only TAKE the grab once the pointer has actually moved,
    // which is exactly the difference between a click and a drag.
    DragHandler {
      id: band
      target: null
      acceptedButtons: Qt.LeftButton
      // Off while the pointer is on an item, because then a drag is that
      // item being dragged. Anywhere else — the gap under the last row, the
      // empty half of a grid — the band is what a drag means, and it has to
      // outrank the ListView's own flick to get the gesture.
      //
      // `band.active ||` is what makes it survive the drag. hoverRow is a
      // live property, so the moment the pointer crossed onto a tile this
      // went false and the handler was disabled mid-gesture — in the grid
      // that is the very first row, which is why the box could not be
      // dragged past it. Once the band has the grab it keeps it.
      //
      // `overBandZone` is the third condition, and it is about COLUMNS
      // view: of its three panes only the middle one holds rows this
      // window can select. A press in the preview started a band that
      // could never select anything and drew a box over a picture to say
      // so; the left-hand pane is the parent directory and is no better.
      // railHOVER, not only railDragging. The rail disarms the band by
      // saying it has the pointer, and the row and tile handlers both read
      // that — this one only read the drag half. railDragging is set on
      // PRESS, and a DragHandler declaring CanTakeOverFromAnything has
      // already taken the gesture by then, so the guard arrived too late
      // to stop anything. Below the last tile in a grid there is no row
      // under the pointer, so the band was armed right where the scrollbar
      // lives — and grabbing the bar at the bottom drew a selection box
      // instead of scrolling.
      enabled: band.active
        || (!term.hoverRow && term.overBandZone
            && !term.railHover && !term.railDragging
            && !term.modal)
      grabPermissions: PointerHandler.CanTakeOverFromAnything

      // Where a band is allowed to be drawn: the whole body in list and
      // grid view, the middle column alone in columns view.
      readonly property real zoneL: term.activePaneX
        + (term.viewMode === "columns" ? term.midCol.x : 0)
      readonly property real zoneR: term.activePaneX
        + (term.viewMode === "columns"
          ? term.midCol.x + term.midCol.width : term.activePaneW)

      // Clamped to that zone. bodyBox does not clip, so a drag carried
      // past its left edge drew the selection box out over the sidebar —
      // the rectangle was honest about the pointer and wrong about what it
      // was selecting from, since there is nothing selectable over there.
      readonly property real x1: Math.max(band.zoneL,
        Math.min(centroid.pressPosition.x, centroid.position.x))
      readonly property real y1: Math.max(0,
        Math.min(centroid.pressPosition.y, centroid.position.y))
      readonly property real x2: Math.min(band.zoneR,
        Math.max(centroid.pressPosition.x, centroid.position.x))
      readonly property real y2: Math.min(bodyBox.height,
        Math.max(centroid.pressPosition.y, centroid.position.y))

      // What was already ticked when the drag began, so dragging ADDS to a
      // selection instead of replacing it — and so releasing without
      // having moved cannot wipe what you had.
      property var base: ({})

      // The rectangle as last drawn. Kept because the centroid collapses
      // the instant the button comes up, and the box has to still have a
      // shape to fade out from.
      property rect held: Qt.rect(0, 0, 0, 0)

      onActiveChanged: {
        if (active) {
          band.base = Object.assign({}, term.marked);
          band.lastLo = -1;
          band.lastHi = -1;
          // COLLAPSE THE OLD RECTANGLE FIRST.
          //
          // `held` survives a release on purpose, so the box has a shape
          // to fade out from — but it also survived into the NEXT gesture,
          // and opacity goes to 1 the instant the band activates. So a
          // band that activated and had not yet been dragged anywhere drew
          // the PREVIOUS box, at the previous place, for a frame.
          //
          // That is the ghost: press on a selected row and move fast, and
          // hoverRow has not caught up, so this handler — which may take
          // the grab from anything — wins the gesture for a moment before
          // the row drag claims it, just long enough to flash the last
          // rectangle back onto the screen.
          band.held = Qt.rect(band.x1, band.y1, 0, 0);
        }
        // nothing to apply on release: the last centroid already did, and
        // the collapsed one would select a single row
      }
      // The last row range applied, so a move that stays inside the same
      // rows does not rebuild the selection. Dragging across a tall list
                // fires a centroid change per pixel and only a fraction of
      // them cross a row boundary.
      property int lastLo: -1
      property int lastHi: -1

      onCentroidChanged: {
        if (!band.active) return;
        // (see the TapHandler below for the click, as opposed to the drag)
        const w = band.x2 - band.x1, h = band.y2 - band.y1;
        // Only remember a rectangle with a shape. On release the centroid
        // collapses to a point while `active` is still true for one more
        // event, and letting that through overwrote the held rect with a
        // 0x0 one — so the fade ran on something invisible, which looked
        // exactly like no fade at all.
        if (w > 2 && h > 2)
          band.held = Qt.rect(band.x1, band.y1, w, h);
        term.applyBand(band.x1, band.y1, band.x2, band.y2, band.base);
      }
    }

    Rectangle {
      // Drawn from the HELD rectangle, not the live centroid, so releasing
      // leaves it where it was and it fades from there rather than
      // collapsing to a point on the way out.
      // A rectangle with no shape is not drawn at all, so a stale one can
      // never appear and the fade only ever runs on something real.
      visible: opacity > 0.01 && band.held.width > 2 && band.held.height > 2
      opacity: band.active ? 1 : 0
      // Slower on the way out than a normal transition: the box is being
      // dismissed rather than moved, and a 140ms disappearance reads as a
      // cut rather than a fade.
      Behavior on opacity {
        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
      }
      x: band.held.x
      y: band.held.y
      width: band.held.width
      height: band.held.height
      radius: Zenon.windowRadius
      color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.12)
      border.width: 1
      border.color: Zenon.border
      z: 5
    }

    // Ctrl+wheel zooms.
    //
    // A MouseArea, not a WheelHandler, and that is not a preference: a
    // WheelHandler receives NOTHING here. Verified with a logging handler
    // placed inside the very ListView those same wheel events were visibly
    // scrolling, and again on an overlay above all three views — zero
    // events in both, while a console.log elsewhere in this file logged
    // fine. MouseArea.onWheel does get them.
    //
    // NoButton is what makes it safe to lay over everything: it never takes
    // a press, so clicks, drags and the rubber band are untouched. A wheel
    // without ctrl is declined and falls through to the view underneath,
    // which goes on scrolling exactly as before.
    ElasticScroll {
      anchors.fill: parent
      // whichever of the three views the pointer is over
      pick: (x, y) => term.wheelTarget(x, y)
      intercept: (w) => {
        if (!(w.modifiers & Qt.ControlModifier)) return false;
        term.zoomBy(w.angleDelta.y > 0 ? 0.1 : -0.1);
        return true;
      }
      step: term.wheelStep
    }

    // Whether the pointer is over empty space, tracked by something that
    // can never steal a press.
    //
    // A HoverHandler only ever handles hover, so unlike a MouseArea it
    // cannot take the press that a row's DragHandler needs — and taking
    // that press is exactly what the overlay below was doing, which is why
    // dragging a file out of terminus produced no drag at all. Declining the
    // press with `accepted = false` was not enough: by then the overlay had
    // already won the gesture.
    //
    // It asks the view's own indexAt rather than reading hoverRow, for the
    // reason rowUnder exists.
    //
    // AND IT ASKS ONLY WHEN THE ANSWER COULD HAVE CHANGED. This fires on
    // every motion event — on a 180Hz panel that is a hit test against a
    // view, per frame, for a boolean that changes when you cross a row
    // boundary and at no other time. The last point is remembered and a
    // move of less than a pixel in both axes is not worth asking about.
    HoverHandler {
      id: emptyWatch
      property real lastX: -1
      property real lastY: -1
      //
      // The throttle remembers an answer, so anything else that could
      // change it has to say so. A pane switch is the one: the pointer has
      // not moved, but which half is active has, and in column view that
      // decides whether it is over anything at all.
      //
      // READ BY NOTHING, ON PURPOSE. It exists so that the handler
      // below has something to fire on — a property whose only job is
      // its own change signal. It reads as dead to anything counting
      // references, because the handler's name does not contain it.
      readonly property int activeSide: term.act.side
      onActiveSideChanged: {
        emptyWatch.lastX = -1;
        emptyWatch.lastY = -1;
        if (emptyWatch.hovered) emptyWatch.settle();
      }

      function settle() {
        const px = emptyWatch.point.position.x;
        const py = emptyWatch.point.position.y;
        if (Math.abs(px - emptyWatch.lastX) < 1
         && Math.abs(py - emptyWatch.lastY) < 1) return;
        emptyWatch.lastX = px;
        emptyWatch.lastY = py;
        term.overEmpty = term.rowUnder(px, py) < 0;
        // The rubber band cannot ask where the pointer is — a DragHandler
        // has a position only once it is already dragging — so the hover
        // that is watching anyway answers for it.
        term.overBandZone = px >= band.zoneL && px <= band.zoneR;
      }
      onPointChanged: emptyWatch.settle()
    }

    // A click on nothing: right opens the menu, left means "none of them".
    //
    // ABOVE the views, not below them, and that one word was the whole bug.
    // At z:-1 this sat underneath three Flickables, and a Flickable takes
    // the left button for its own flick and never gives it back — so the
    // deselect could not fire. RIGHT clicks did arrive, because a Flickable
    // ignores those, which is why the paste-here menu worked all along and
    // hid the fact that its other half never did.
    //
    // Two things stop it swallowing what it should not: `enabled` turns it
    // off whenever the pointer is on a row, so rows get their own clicks;
    // and the rubber band is a DragHandler declaring CanTakeOverFromAnything,
    // so it still steals the press the moment a click becomes a drag.
    MouseArea {
      anchors.fill: parent
      z: 5
      // Not present at all over a row, so a row keeps every press it is
      // entitled to — including the one that becomes a drag out of terminus.
      enabled: term.overEmpty
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      // ── ASKED AGAIN AT THE PRESS ──────────────────────────────────
      // overEmpty is worked out when the POINTER moves, and rows move
      // under a still pointer — a listing landing, a scroll, a file
      // arriving. Then it is stale, this sits over a row, and the click
      // meant for the row lands here: a ctrl-click that marked nothing,
      // and a second click (after the hand had moved a pixel) that did.
      // A row under the press now hands the press on to it.
      onPressed: (m) => {
        term.overEmpty = term.rowUnder(m.x, m.y) < 0;
        if (!term.overEmpty) m.accepted = false;
      }
      onClicked: (m) => {
        // FIRST, so both of the lines below are about the half that was
        // clicked rather than the half that had the keyboard.
        term.comeOverAt(m.x);
        if (m.button === Qt.RightButton) { term.menuPopRef.menu.openHere(bodyBox, m); return; }
        if (Object.keys(term.marked).length > 0) term.act.marked = {};
        term.contentRef.forceActiveFocus();
      }
    }

    // Centred in the ACTIVE PANE, not in the body. With two panes open the
    // body is both of them, so an empty directory on one side put its
    // label in the middle of the window — half of it hanging over the
    // other pane's rows, saying "Empty" about a listing that was not.
    // CENTRED ON THE LISTING, WHICH IS NOT ALWAYS THE PANE.
    //
    // In list and grid the listing IS the pane, so the middle of one is
    // the middle of the other. Miller is three columns and only the middle
    // one holds these rows — so "Empty" sat in the centre of all three,
    // which puts it over the preview of a directory that is not the empty
    // one and a third of a pane away from the column it is about.
    //
    // It travels with the columns too: miller.x is the step animation, so
    // the label slides in with the column it belongs to rather than
    // sitting still while that column moves out from under it.
    EmptyMark {
      id: emptyLabel
      x: term.viewMode === "columns"
        // NOT miller.x. That is written by an XAnimator on the render
        // thread, which does not notify QML bindings as it goes — so this
        // read it frozen at the step's STARTING offset, a quarter of a
        // pane to one side, and then snapped when the animation ended.
        // The label appeared over the third column and jumped to the
        // second. Measured from the column's resting place instead, and
        // the fade below carries the change.
        ? millerBox.x + term.midCol.x + (term.midCol.width - width) / 2
        : term.activePaneX + (term.activePaneW - width) / 2
      y: (parent.height - height) / 2
      // IT WAITS FOR THE COLUMNS, THEN ARRIVES ON ITS OWN.
      //
      // Riding miller's fade was close but not it: the label came in
      // WITH the tree, while the tree was still travelling, and its x is
      // measured off the middle column's resting place — so it sat still
      // in the middle of a pane that had not stopped moving yet.
      //
      // Held at nothing for the whole step and eased in once the columns
      // are down. "Empty" is an answer about where you have arrived, and
      // it can wait until you have.
      //
      // Not a child of miller either, because miller SLIDES: this belongs
      // at the column's resting place rather than wherever it is mid-step.
      //
      // AND NOT WHILE A DIRECTORY IS ARRIVING. `view.length === 0` is a
      // complete answer to "is this empty" and a wrong one for the window
      // between asking for a directory and its rows landing: enter() holds
      // `arriving` across exactly that gap, for exactly this reason, and
      // the label was not asking. Caught on a step BACK out of a directory —
      // the columns had already rotated and stopped, the new listing had
      // not arrived, and "Empty" flashed over a column that was about to
      // be full. Frame-accurate from a 60fps capture: two rows drawn in
      // the middle column with the label underneath them.
      readonly property bool wanted: term.view.length === 0
        && !term.millerAnimRef.running && !term.arriving
      // ── IT FADES IN, IT DOES NOT FADE OUT ──────────────────────
      // The rows of the directory you step back into land in a single
      // frame; a fade spent the next seven dissolving this ON TOP of them.
      // Measured with the label temporarily drawn in red: still visible
      // over a populated column a frame after the step, which is the
      // flicker — an animation playing inside a directory it is not about.
      //
      // A STATE AND A ONE-WAY TRANSITION, not a Behavior that switches
      // itself off. `enabled: wanted` on a Behavior is a race: the opacity
      // binding and the enabled binding both fall off `wanted`, and
      // nothing says which is re-evaluated first. A transition with `to`
      // simply has no rule for the other direction, so leaving is instant
      // by construction rather than by winning an ordering.
      opacity: 0
      visible: emptyLabel.opacity > 0.01

      states: State {
        name: "shown"
        when: emptyLabel.wanted
        PropertyChanges { emptyLabel.opacity: 1 }
      }
      transitions: Transition {
        to: "shown"
        NumberAnimation {
          property: "opacity"
          duration: Zenon.fast
          easing.type: Zenon.travelEase
        }
      }
      filtered: term.query !== ""
    }
    }

  }


  // ── the picker's own footer ───────────────────────────────────
  // Only while a portal request is open. It is deliberately the widest
  // thing on screen and sits directly above the hints: an application is
  // blocked waiting on this, so what terminus is being asked for has to be
  // impossible to miss.
  Rectangle {
    id: portalBar
    width: parent.width
    // 46, down from 60 (user, 2026-10-09): a strip, not a panel
    height: term.picking ? 46 : 0
    visible: height > 0
    clip: true
    // FROSTED AND DARKER, no gradient (the user's call — the cyan washed up
    // from the bottom edge is gone): a shade over the window's own glass,
    // which Hyprland blurs, so the strip reads as the same frosted pane set
    // a step deeper. darken() halves in light themes.
    // NOW THE SIDEBAR'S GROUND, as every bar is (user, 2026-10-09): the
    // body itself, with rows not yet reached frosted through it.
    color: term.chromeBg

    // What is being asked for, as a mark: save, a directory, one file or several.
    readonly property string mark: !term.portal ? ""
      : term.portal.save ? "\uF0C7"
      : term.portal.directory ? "\uF07C"
      : term.portal.multiple ? "\uF0C5" : "\uF15B"

    // The neutral seam every other strip in this window uses. A cyan rule
    // here was the loudest line on the surface, for a bar that is already
    // tinted and already says what it is.
    Rectangle {
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      height: 1
      color: Zenon.border
    }

    Row {
      id: portalLabel
      anchors.left: parent.left
      anchors.leftMargin: 14
      anchors.verticalCenter: parent.verticalCenter
      spacing: 12

      // the bare mark: the tinted, ringed square it sat in was a halo the
      // strip did not need (user, 2026-10-09)
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: portalBar.mark
        color: Zenon.cyan
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(16)
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Text {
          text: term.portalTitle
          color: Zenon.white
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: Zenon.px(15)
        }
      }
    }

    // save requests need a name, and it is the only thing being chosen
    Rectangle {
      id: saveBox
      anchors.left: portalLabel.right
      anchors.leftMargin: 14
      anchors.right: portalButtons.left
      anchors.rightMargin: 14
      anchors.verticalCenter: parent.verticalCenter
      height: 30
      radius: 8
      visible: !!term.portal && term.portal.save
      // A CLASH LIGHTS THE FIELD — its ring and a wash of the same yellow
      // the button turns — so "this name is taken" is said where the name is.
      color: term.saveClash ? Zenon.alpha(Zenon.yellow, 0.10) : Zenon.selBg
      Behavior on color { ColorAnimation { duration: Zenon.fast } }
      border.width: 1
      border.color: Terminus.nameError(saveField.text) === ""
        ? (term.saveClash ? Zenon.yellow : Zenon.border) : Zenon.red

      // WHERE, beside WHAT. The cursor now decides the directory, and a
      // save into a directory you cannot see named is a save you have to
      // go looking for afterwards.
      // The file's own mark, from the name as typed, so "notes.md"
      // wears the glyph it will have in the listing once it exists.
      Text {
        id: saveGlyph
        anchors.left: parent.left
        anchors.leftMargin: 11
        anchors.verticalCenter: parent.verticalCenter
        text: Icons.glyphFor({ name: saveField.text || "x", isDir: false })
        color: Zenon.keyInk
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(14)
      }

      // Where it goes, as a pill: the directory is the other half of the
      // answer, and "in Downloads" in the field's own grey read as part
      // of the name.
      Rectangle {
        id: saveWhere
        anchors.right: parent.right
        anchors.rightMargin: 5
        anchors.verticalCenter: parent.verticalCenter
        height: 24
        radius: 6
        width: Math.min(saveWhereRow.implicitWidth + 16, saveBox.width * 0.42)
        color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.10)
        clip: true
        Row {
          id: saveWhereRow
          anchors.left: parent.left
          anchors.leftMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          spacing: 6
          Text {
            text: "\uF07B"
            color: Zenon.cyan
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(12)
          }
          Text {
            width: Math.min(implicitWidth, saveBox.width * 0.42 - 40)
            elide: Text.ElideLeft
            text: term.saveDir === "/" ? "/" : Terminus.basename(term.saveDir)
            color: Zenon.cyan
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(13)
          }
        }
      }

      // ── AND A WAY OUT OF IT ─────────────────────────────────────
      // A small chip inside the field while the name is taken: the first
      // free " (n)" before the extension (term.saveNumbered). Replacing
      // stays the button's; keeping both is this.
      Rectangle {
        id: saveNumber
        anchors.right: saveWhere.left
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        height: 22
        width: term.saveClash ? saveNumberText.implicitWidth + 14 : 0
        visible: width > 0.5
        radius: 5
        clip: true
        color: Zenon.alpha(Zenon.yellow, saveNumberMa.pressed ? 0.34
          : saveNumberMa.containsMouse ? 0.24 : 0.14)
        Behavior on width { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
        Text {
          id: saveNumberText
          anchors.centerIn: parent
          // the number it would add, read off the name it would make
          text: {
            if (!term.saveClash) return "";
            const m = /\((\d+)\)(\.[^.]*)?$/.exec(
              Terminus.freeNameKeeping(term.saveRows(), saveField.text));
            return "+ (" + (m ? m[1] : "1") + ")";
          }
          color: Zenon.yellow
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: Zenon.px(12)
        }
        MouseArea {
          id: saveNumberMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: term.saveNumbered()
        }
      }

      TextInput {
        id: saveField

        cursorDelegate: Caret { field: saveField }
        anchors.fill: parent
        anchors.leftMargin: saveGlyph.implicitWidth + 20
        anchors.rightMargin: saveWhere.width + 14
          + (saveNumber.visible ? saveNumber.width + 6 : 0)
        verticalAlignment: TextInput.AlignVCenter
        color: Zenon.white
        selectionColor: Zenon.cyan
        // dark on the cyan selection — white on it was barely there
        selectedTextColor: Zenon.onAccent
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(14)
        clip: true
        Keys.onReturnPressed: (e) => { e.accepted = true; term.portalConfirm(); }
        Keys.onEscapePressed: (e) => { e.accepted = true; term.portalCancel(); }
        // Tab goes back to the listing, so the two halves of the dialog
        // are one ring rather than a field you can get into and not out of.
        Keys.onPressed: (e) => {
          if (e.key !== Qt.Key_Tab && e.key !== Qt.Key_Backtab) return;
          e.accepted = true;
          term.contentRef.forceActiveFocus();
        }
      }
    }

    // what a confirm would actually hand over, spelled out, because the
    // difference between "this directory" and "the directory under the cursor"
    // is invisible otherwise
    // ── WHAT CONFIRMING WOULD HAND BACK, AS CHIPS ─────────────────
    // Each chosen thing with its own glyph and name, as the listing draws
    // it, three at most and then a count — a path in grey said the same
    // thing in a way nobody reads.
    Item {
      id: portalPicks
      anchors.left: portalLabel.right
      anchors.leftMargin: 18
      anchors.right: portalButtons.left
      anchors.rightMargin: 14
      anchors.verticalCenter: parent.verticalCenter
      height: 28
      visible: !!term.portal && !term.portal.save
      clip: true
      readonly property var picks: term.portalChoice
      readonly property int fit: Math.max(1, Math.floor(portalPicks.width / 170))
      readonly property int shown: Math.min(portalPicks.picks.length, 3, portalPicks.fit)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: portalPicks.picks.length === 0
        text: "nothing selected"
        color: Zenon.muted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
      }

      Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        Repeater {
          model: portalPicks.picks.slice(0, portalPicks.shown)
          delegate: Rectangle {
            id: pick
            required property var modelData
            readonly property string name: Terminus.basename(String(modelData)) || String(modelData)
            height: 26
            radius: 6
            // sized by its contents, which are capped below — never the
            // other way round, or the Row and the chip polish each other
            readonly property real most: (portalPicks.width - 70) / Math.max(1, portalPicks.shown)
            width: pickRow.implicitWidth + 18
            color: Zenon.wash(0.05)
            border.width: 1
            border.color: Zenon.border
            clip: true
            Row {
              id: pickRow
              anchors.left: parent.left
              anchors.leftMargin: 9
              anchors.verticalCenter: parent.verticalCenter
              spacing: 6
              Text {
                text: Icons.glyphFor({ name: pick.name, isDir: !!term.portal && term.portal.directory })
                color: Zenon.cyan
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(13)
              }
              Text {
                width: Math.max(20, Math.min(implicitWidth, pick.most - 40))
                elide: Text.ElideMiddle
                text: pick.name
                color: Zenon.white
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(13)
              }
            }
          }
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: portalPicks.picks.length > portalPicks.shown
          text: "+" + (portalPicks.picks.length - portalPicks.shown) + " more"
          color: Zenon.soft
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
      }
    }

    Row {
      id: portalButtons
      anchors.right: parent.right
      anchors.rightMargin: 14
      anchors.verticalCenter: parent.verticalCenter
      spacing: 8

      DialogButton {
        label: "Cancel"
        ink: Zenon.muted
        onClicked: term.portalCancel()
      }

      DialogButton {
        label: (!!term.portal && term.portal.save)
          ? (term.saveClash ? "Replace" : "Save") : "Choose"
        ink: term.saveClash ? Zenon.yellow : Zenon.cyan
        ready: term.portalChoice.length > 0
        primary: term.portalChoice.length > 0
        onClicked: term.portalConfirm()
      }
    }
  }

}

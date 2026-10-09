// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ── THE SURFACE QUICK LOOK LIVES ON ──────────────────────────────────
// Not a child of the window. terminus is an xdg-toplevel, so anything
// inside it is clipped to whatever height the compositor gave the window —
// and a preview that has to fit inside a short window is not a preview.
//
// So the overlay gets its own layer-shell surface, the size of the monitor
// the window happens to be on. Two properties make that safe:
//
//   keyboardFocus None  — the layer never asks for the keyboard, so focus
//     stays on the toplevel underneath and Escape / h / l / j / k go on
//     being handled by the window's own Keys handler, unmoved.
//   exclusionMode Ignore — it is a modal overlay for a few seconds, not
//     furniture. Reserving space would shove every tiled window aside.
//
// It is mapped only while the overlay is on screen, opacity included, so
// the closing fade finishes before the surface goes away.
// ── THE DROP QUESTION, ON A SURFACE NOTHING CAN COVER ─────────────────
// See dropUris for why this is a layer and not a popup. Everything else
// about it follows the context menu: same ground, same radius, same row
// height, and it grows out of the pointer the way that card does.
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

PanelWindow {
  id: dropAsk
  // the terminus window (`term`, never `root` — see terminus-split notes)
  property var term: null
  property var rows: []
  property bool open: false
  property real cx: 0
  property real cy: 0
  property int at: 0

  // ── AS EVERY MENU ARRIVES, CHOOSES AND LEAVES ─────────────────────
  // The card is drawn here, on this surface, and not by CardMenu: a card
  // on a surface of its own has to stack above this one to be clicked,
  // and when it did not, the click fell to the catcher below and the drop
  // was abandoned without a word. What CardMenu does is copied instead —
  // the shade that fades and grows the card in and out, and the cyan
  // flash on the row you chose, with the action at the end of it.
  property real shade: 0
  onOpenChanged: dropAsk.shade = dropAsk.open ? 1 : 0
  Behavior on shade {
    NumberAnimation { duration: Zenon.menuFade; easing.type: Easing.OutCubic }
  }
  property int flashAt: -1
  property real flash: 0
  property var pendingAct: null
  SequentialAnimation {
    id: dropFlash
    NumberAnimation { target: dropAsk; property: "flash"; to: 1;
                      duration: 60; easing.type: Easing.OutQuad }
    NumberAnimation { target: dropAsk; property: "flash"; to: 0;
                      duration: 130; easing.type: Easing.InQuad }
    ScriptAction {
      script: {
        const act = dropAsk.pendingAct;
        dropAsk.pendingAct = null;
        dropAsk.flashAt = -1;
        dropAsk.dismiss();
        if (act) act();
      }
    }
  }

  // Keyboard of its OWN, unlike quick look's layer which leaves the keys
  // to the window behind it. The window behind this one may be buried —
  // that is the whole reason this surface exists — so it cannot be the
  // thing listening.
  WlrLayershell.keyboardFocus: dropAsk.open
    ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "terminus-dropmenu"
  exclusionMode: ExclusionMode.Ignore
  // kept up through the fade out, so the card is seen to go — and taking
  // no input while it does, or a click just after answering would land on
  // a menu that is already leaving
  visible: dropAsk.open || dropAsk.shade > 0.01
  mask: dropAsk.open ? null : dropNoInput
  Region { id: dropNoInput }
  screen: term.screen
  color: "transparent"
  anchors { top: true; bottom: true; left: true; right: true }

  // ── WHERE THE POINTER IS, ASKED OF THE COMPOSITOR ─────────────────
  // A Wayland client is not told where its own toplevel sits, so there is
  // no arithmetic here that can turn a point inside the window into a
  // point on the screen — Item.mapToGlobal answers as though the window
  // were at the origin, which is how the card ended up over whichever
  // window happened to be at that offset instead of over the drop.
  //
  // Zenon.winOrigin solves this for a LAYER, by reading the anchors and
  // margins it was placed with. A toplevel has neither.
  //
  // hyprctl does know, and costs 5ms measured — which is nothing against
  // a menu that opens after a drop, and is paid once per drop rather than
  // per frame.
  function show(list) {
    dropAsk.rows = list || [];
    dropAsk.at = 0;
    cursorProc.running = false;
    cursorProc.running = true;
  }

  // Fallback: the middle of the screen. Better than a card at a
  // meaningless offset if hyprctl ever fails to answer.
  function place(gx, gy) {
    const sx = term.screen ? term.screen.x : 0;
    const sy = term.screen ? term.screen.y : 0;
    const okX = !isNaN(gx), okY = !isNaN(gy);
    dropAsk.cx = okX ? gx - sx : dropAsk.width / 2;
    dropAsk.cy = okY ? gy - sy : dropAsk.height / 2;
    dropAsk.open = true;
    // ASK FOR THE KEYBOARD AND KEEP ASKING. A bare forceActiveFocus on
    // the frame a surface is made visible is dropped — it has not been
    // mapped yet — which is the same trap the window itself documents
    // beside focusClaim. One shot here for the common case, and a few
    // more behind it for the frame the compositor is still catching up.
    dropKeys.forceActiveFocus();
    dropClaim.restart();
  }

  Process {
    id: cursorProc
    command: ["hyprctl", "cursorpos"]
    stdout: StdioCollector {
      id: cursorOut
      waitForEnd: true
      onStreamFinished: {
        // "739, 1429"
        const p = String(cursorOut.text || "").trim().split(",");
        dropAsk.place(Number(p[0]), Number(p[1]));
      }
    }
  }

  Timer {
    id: dropClaim
    interval: 16
    repeat: true
    property int tries: 0
    onTriggered: {
      if (!dropAsk.open || dropKeys.activeFocus || dropClaim.tries++ > 12) {
        dropClaim.stop();
        dropClaim.tries = 0;
        return;
      }
      dropKeys.forceActiveFocus();
    }
  }

  function dismiss() {
    dropAsk.open = false;
    // Abort, Escape or a click away: nothing landed, so the branches the
    // drag opened go now. A turn later, because a chosen row's act runs
    // just AFTER this — see dropFlash — and Copy or Move starts
    // springGrace instead.
    Qt.callLater(() => { if (!term.springGraceRef.running) term.springShut(term.springHeld); });
    // The rows stay until the next show: the card fades out, and emptying
    // them under it would collapse it mid-fade.
    // The listing gets the keyboard back, the way every sheet here ends.
    term.takeFocus();
  }

  // The row flashes, then it acts — see dropFlash.
  function choose(i) {
    if (dropFlash.running || !dropAsk.open) return;
    const r = dropAsk.rows[i];
    if (!r || r.sep) return;
    dropAsk.at = i;
    dropAsk.flashAt = i;
    dropAsk.pendingAct = r.act || null;
    dropFlash.restart();
  }

  // Skips the rule when walking, so the ring is the three verbs.
  function step(n) {
    const list = dropAsk.rows;
    if (list.length === 0) return;
    let i = dropAsk.at;
    for (let guard = 0; guard < list.length; ++guard) {
      i = (i + n + list.length) % list.length;
      if (!list[i].sep) { dropAsk.at = i; return; }
    }
  }

  // Click away to abort, the way the menu it replaced did.
  MouseArea {
    anchors.fill: parent
    onClicked: dropAsk.dismiss()
  }

  FocusScope {
    id: dropKeys
    anchors.fill: parent
    focus: true
    Keys.onPressed: (event) => {
      event.accepted = true;
      if (event.key === Qt.Key_Escape) { dropAsk.dismiss(); return; }
      if (event.key === Qt.Key_Down || event.text === "j") { dropAsk.step(1); return; }
      if (event.key === Qt.Key_Up || event.text === "k") { dropAsk.step(-1); return; }
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        dropAsk.choose(dropAsk.at); return;
      }
    }

    MenuShadow {
      panel: dropCard
      cornerRadius: Zenon.menuRadius
      opacity: dropAsk.shade
      transformOrigin: Item.TopLeft
      scale: dropCard.scale
    }

    ClippingRectangle {
      id: dropCard
      // Clamped to the screen, because a card that opened near the right
      // or bottom edge would otherwise hang off it — the compositor does
      // this for a popup and does not for a layer's contents.
      x: Math.round(Math.min(Math.max(8, dropAsk.cx),
                             dropAsk.width - dropCard.width - 8))
      y: Math.round(Math.min(Math.max(8, dropAsk.cy),
                             dropAsk.height - dropCard.height - 8))
      width: Zenon.menuWidth
      height: dropCol.implicitHeight + 2 * Zenon.menuCardPad
      color: Zenon.menuBg   // its own layer surface (dropAsk), so frosted like every menu
      radius: Zenon.menuRadius
      border.color: Zenon.border
      border.width: 1
      // Out of the pointer's corner, faded and grown by the shade, as
      // CardMenu arrives.
      transformOrigin: Item.TopLeft
      scale: Zenon.menuScale(dropAsk.shade)
      opacity: dropAsk.shade

      Column {
        id: dropCol
        x: Zenon.menuCardPad
        y: Zenon.menuCardPad
        width: parent.width - 2 * Zenon.menuCardPad

        Repeater {
          model: dropAsk.rows

          delegate: Item {
            required property var modelData
            required property int index
            width: dropCol.width
            height: modelData.sep ? Zenon.menuSepHeight : Zenon.menuRowHeight

            Rectangle {
              visible: modelData.sep === true
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.right: parent.right
              // edge to edge, as every menu's separator: the rows sit
              // inside the card's padding, so it reaches back out by that
              anchors.leftMargin: -Zenon.menuCardPad
              anchors.rightMargin: -Zenon.menuCardPad
              height: 1
              color: Zenon.border
            }

            // the lit row, the full width of the row as CardMenu's is
            Rectangle {
              visible: !modelData.sep && dropAsk.at === index
              anchors.fill: parent
              color: Zenon.border
            }

            // and the flash on the one chosen
            Rectangle {
              visible: dropAsk.flashAt === index && dropAsk.flash > 0
              anchors.fill: parent
              color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b,
                             0.55 * dropAsk.flash)
            }

            // FROM THE LEFT, as every shared menu's labels are. It was
            // centred, after menu.openCustom's custom lists — but this is
            // a menu, and the shared ones set its type, size and edge.
            Text {
              visible: !modelData.sep
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: 12
              anchors.rightMargin: 10
              horizontalAlignment: Text.AlignLeft
              elide: Text.ElideRight
              text: modelData.label || ""
              color: Zenon.white
              font.family: Zenon.face
              font.weight: Font.Medium
              font.pixelSize: Zenon.px(16)
            }

            MouseArea {
              anchors.fill: parent
              enabled: !modelData.sep && !dropFlash.running
              hoverEnabled: true
              onEntered: dropAsk.at = index
              onClicked: dropAsk.choose(index)
            }
          }
        }
      }
    }
  }
}

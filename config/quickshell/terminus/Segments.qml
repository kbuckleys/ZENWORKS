// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A FEW CHOICES, ONE OF THEM ON — one bordered pill split into its options,
// a hairline between them, the chosen one lit by ONE highlight that slides
// to whichever is chosen (user, 2026-10-11) rather than each part lighting
// itself. For a view's handful of ways to look (open or closed, whose,
// which history, which forge) and a window's few pages (alexandria's,
// ceres' switch — this was theirs first, written in each). Sized by its
// words; no hover, no hand cursor (the suite's controls answer neither).
//
//     Segments { options: [["open", "Open"], ["closed", "Closed"]]
//                current: pg.showing; onChose: (v) => pg.showing = v
//                onPointed: (v, item, inside) => …   // a tooltip, say }
//
// ── A TRAIL OF PLACES (terminus' breadcrumbs, 2026-10-13) ──────────────
// What a path needs that a switch does not, all off by default:
//   faint      values drawn at half strength (the way back down a path)
//   hot        the value a drag is over, washed in the accent
//   heldAt     a part item (from `pressed`) a menu is open on — HeldRing
//   buttons    which buttons a part answers; every press is `pressed`
//              (value, the part, button, x, y), and a left one `chose` too
//   valueAt    the value under a point in this item, "" for none — for a
//              DropArea laid over the whole trail
//   partAt     the part item showing a value, null for none
//   weight, pad  the words' weight and the room either side of them
//
// ── AND FROM THE KEYBOARD (`keys`, 2026-10-13) ─────────────────────────
// For a card walked with Tab (the batch rename's): `claim()` gives it the
// keyboard, ←/→ choose the next part that can be chosen, Tab and Shift-Tab
// leave (`tabbed`, `backTabbed`) for the holder's ring to place, and it
// wears the HeldRing every focused field wears while it has the keys.
//
// ── A PICTURE OVER EACH WORD (`art`, 2026-10-14) ───────────────────────
// For a switch whose choices are shapes (picasso's Fit): `art` is a
// Component made once per part, above its word, `artH` tall. It reads
// `parent.value` (the part's value) and `parent.ink` (its word's colour).
//
// terminus' PrefSeg is the settings panel's own (enrolled with its window
// for the keyboard); this is the one for anywhere else.

import QtQuick
import "../morpheus"

Item {
  id: segs
  // [[value, label], …]
  property var options: []
  property string current: ""
  property real textSize: Zenon.px(14)
  // the unlit words' ink; the lit one's is the accent
  property color ink: Zenon.muted
  // values that can be picked; null for all. One left out is shown faint
  // and does not answer (terminus' settings: columns while split)
  property var allowed: null
  // Parts of one width, sharing whatever width the holder gives it (set
  // `width`), rather than each as wide as its words — for a switch that
  // spans a card (picasso's tabs, fits, intervals).
  property bool even: false
  // values that wear a small dot — something set under that choice
  // (picasso's card: a look staged, a slideshow on)
  property var dotted: []
  property var faint: []
  property string hot: ""
  property var heldAt: null
  property int buttons: Qt.LeftButton
  property int weight: Font.Bold
  property real pad: 28
  property bool keys: false
  readonly property bool focused: segs.activeFocus
  function claim() { if (segs.keys) segs.forceActiveFocus(); }
  signal chose(string value)
  signal pressed(string value, Item at, int button, real x, real y)
  signal tabbed()
  signal backTabbed()
  // the next part along that can be chosen, from the current one
  function step(d) {
    const n = segs.options.length;
    for (let k = 1; k <= n; ++k) {
      const i = segs.index + d * k;
      if (i < 0 || i >= n) return;
      const v = String(segs.options[i][0]);
      if (segs.allowed === null || segs.allowed.indexOf(v) >= 0) { segs.chose(v); return; }
    }
  }
  Keys.onPressed: (e) => {
    if (!segs.keys) return;
    if (e.key === Qt.Key_Left) { e.accepted = true; segs.step(-1); }
    else if (e.key === Qt.Key_Right) { e.accepted = true; segs.step(1); }
    else if (e.key === Qt.Key_Backtab || (e.key === Qt.Key_Tab && (e.modifiers & Qt.ShiftModifier))) {
      e.accepted = true; segs.backTabbed();
    } else if (e.key === Qt.Key_Tab) { e.accepted = true; segs.tabbed(); }
  }
  // the pointer on an option, or off it — for the holder's tooltip
  signal pointed(string value, Item at, bool inside)

  readonly property int index: segs.options.findIndex((o) => o[0] === segs.current)
  function partAt(v) {
    const i = segs.options.findIndex((o) => o[0] === v);
    return i >= 0 && i < rep.count ? rep.itemAt(i) : null;
  }
  function valueAt(x, y) {
    const p = row.mapFromItem(segs, x, y);
    if (p.y < 0 || p.y > row.height) return "";
    for (let i = 0; i < rep.count; ++i) {
      const it = rep.itemAt(i);
      if (it && p.x >= it.x && p.x < it.x + it.width) return String(segs.options[i][0]);
    }
    return "";
  }
  implicitWidth: row.implicitWidth + 2
  property Component art: null
  property real artH: 16
  readonly property real artRoom: segs.art ? segs.artH + 8 : 0
  implicitHeight: Math.round(segs.textSize * 2.1) + segs.artRoom
  width: implicitWidth
  height: implicitHeight

  Rectangle {
    anchors.fill: parent
    radius: Zenon.windowRadius
    color: Zenon.wash(0.04)
  }

  // the one highlight, under the words, sliding to the chosen option
  readonly property Item litItem: segs.index >= 0 && rep.count > segs.index ? rep.itemAt(segs.index) : null
  Rectangle {
    id: lit
    visible: !!segs.litItem
    x: segs.litItem ? row.x + segs.litItem.x + 2 : 0
    y: 3
    width: segs.litItem ? segs.litItem.width - 4 : 0
    height: segs.height - 6
    radius: Math.max(0, Zenon.windowRadius - 2)
    color: Zenon.alpha(Zenon.cyan, 0.16)
    Behavior on x { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.travelEase } }
    Behavior on width { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.travelEase } }
  }

  Row {
    id: row
    x: 1
    y: 1
    height: segs.height - 2
    Repeater {
      id: rep
      model: segs.options
      delegate: Item {
        id: one
        required property var modelData
        required property int index
        readonly property bool on: segs.current === one.modelData[0]
        readonly property bool ok: segs.allowed === null || segs.allowed.indexOf(one.modelData[0]) >= 0
        width: segs.even ? (segs.width - 2) / Math.max(1, segs.options.length)
          : label.implicitWidth + segs.pad
        height: row.height
        // between two options, a hairline
        Rectangle {
          visible: one.index > 0
          width: 1
          height: parent.height - 10
          anchors.verticalCenter: parent.verticalCenter
          color: Zenon.border
        }
        // pressed, darker — the repository chip's press in delphi
        // (Zenon.wash 0.12), in the highlight's own shape (user, 2026-10-11)
        Rectangle {
          x: 2
          y: 2
          width: parent.width - 4
          height: parent.height - 4
          radius: Math.max(0, Zenon.windowRadius - 2)
          color: Zenon.wash(0.12)
          visible: press.pressed && one.ok
        }
        // a drag over it: lit as a directory about to take one
        Rectangle {
          x: 2
          y: 2
          width: parent.width - 4
          height: parent.height - 4
          radius: Math.max(0, Zenon.windowRadius - 2)
          color: Zenon.alpha(Zenon.cyan, 0.12)
          visible: segs.hot !== "" && segs.hot === one.modelData[0]
        }
        // the part a menu is open on (terminus' HeldRing)
        HeldRing {
          x: 1
          y: 1
          width: parent.width - 2
          height: parent.height - 2
          radius: Math.max(0, Zenon.windowRadius - 1)
          on: segs.heldAt !== null && segs.heldAt === one
        }
        Rectangle {
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: 6
          width: 6
          height: 6
          radius: 3
          color: Zenon.cyan
          visible: segs.dotted.indexOf(one.modelData[0]) >= 0
        }
        Loader {
          active: !!segs.art
          sourceComponent: segs.art
          readonly property string value: String(one.modelData[0])
          readonly property color ink: label.color
          opacity: label.opacity
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: label.top
          anchors.bottomMargin: 6
        }
        Text {
          id: label
          anchors.centerIn: parent
          anchors.verticalCenterOffset: segs.artRoom / 2
          text: one.modelData[1]
          color: one.on || segs.hot === one.modelData[0] ? Zenon.cyan : segs.ink
          opacity: !one.ok ? 0.35
            : segs.faint.indexOf(one.modelData[0]) >= 0 && segs.hot !== one.modelData[0] ? 0.45 : 1
          Behavior on color { ColorAnimation { duration: Zenon.fast } }
          font.family: Zenon.face
          font.weight: segs.weight
          font.features: { "tnum": 1 }
          font.pixelSize: segs.textSize
        }
        HoverHandler { onHoveredChanged: segs.pointed(one.modelData[0], one, hovered) }
        TapHandler {
          id: press
          acceptedButtons: segs.buttons
          onTapped: (ev, button) => {
            if (!one.ok) return;
            segs.pressed(one.modelData[0], one, button, ev.position.x, ev.position.y);
            if (button === Qt.LeftButton) segs.chose(one.modelData[0]);
          }
        }
      }
    }
  }

  // the border over everything, so no fill ever sits on it (ceres' rule)
  Rectangle {
    anchors.fill: parent
    radius: Zenon.windowRadius
    color: "transparent"
    border.width: 1
    border.color: Zenon.border
  }
  // the keyboard is here — the ring every focused field wears
  HeldRing {
    anchors.fill: parent
    radius: Zenon.windowRadius
    z: 10
    on: segs.keys && segs.activeFocus
  }
}

// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A column label that sorts, which is the only header behavior this window
// has. The caret marks the active column, the same way zeus' does.
// ── the row of column headings ──────────────────────────────────────────
// Both panes need one and neither can borrow the other's, because each is
// its own view at its own width. The single-pane case still uses the strip
// above the body; this is what goes inside a half.
// ── a button ────────────────────────────────────────────────────────────
// The picker's shape, used by every dialog as well. There were four sets of
// them — the picker's bordered pills, the confirm card's tinted half-widths,
// the permissions card's two flat words, the properties card's one — and
// they agreed on nothing: not the height, not the corner, not what "this is
// the one Return takes" looks like.
//
// `ink` is the color it answers in and `primary` says it is the default.
// The primary one BREATHES, because a card whose default action is the
// dangerous one should say which is which without being read twice.
// ── a row of exclusive choices in the settings panel ────────────────────
// The view and the sort key are the same control twice — a strip of buttons
// where exactly one is lit — so they are one component rather than two
// Repeaters that would drift apart the first time either was touched.
//
// Its own file since 2026-10-08, out of TerminusWindow.qml, where it was an
// inline component. `term` is the terminus window; every place that makes
// one passes it (`term: root`).

import QtQuick
import Quickshell
import "../morpheus"

Item {
  // the terminus window — passed in by whoever makes one. NOT `root`:
  // inside a delegate a property of that name shadowed the window's id
  // and bound to itself (2026-10-08)
  property var term: null
  id: seg
  property var options: []
  property string current: ""
  // Values that can actually be picked. null means all of them; anything
  // left out is shown REFUSING rather than hidden, because a button that
  // vanishes teaches nothing about why.
  property var allowed: null
  // ── OR AS THE SUITE'S SEGMENTS (user, 2026-10-11) ────────────────────
  // The one pill split into its options (terminus/Segments), sized by its
  // words, instead of a strip of separate buttons. Still this control for
  // the keyboard — enrolled, walked with the arrows — only drawn the other
  // way. `labels` names each option for it; a value without one is shown
  // as it is.
  property bool segmented: false
  property var labels: ({})
  signal chose(string value)

  // ── WALKED ALONG RATHER THAN FLIPPED ────────────────────────────────
  // A segment is a row of buttons, so ctrl ←/→ step between them and
  // return takes the next one — skipping any the panel is currently
  // refusing, because landing on a button that will not be pressed is the
  // same dead end the action row avoids.
  readonly property bool reachable: true
  function activate() { seg.nudge(1); }
  function nudge(d) {
    const o = seg.options;
    const n = o.length;
    if (n === 0) return;
    let i = o.indexOf(seg.current);
    if (i < 0) i = 0;
    for (let t = 0; t < n; t++) {
      i = (i + d + n) % n;
      if (seg.allowed === null || seg.allowed.indexOf(o[i]) >= 0) {
        seg.chose(o[i]);
        return;
      }
    }
  }
  Component.onCompleted: term.prefEnrol(seg)

  width: parent ? parent.width : 0
  height: 34

  Segments {
    visible: seg.segmented
    anchors.left: parent.left
    anchors.leftMargin: 14
    anchors.right: parent.right
    anchors.rightMargin: 14
    anchors.verticalCenter: parent.verticalCenter
    // the column's width, in equal parts (user, 2026-10-11)
    even: true
    options: seg.options.map((o) => [o, seg.labels[o] || o])
    current: seg.current
    allowed: seg.allowed
    onChose: (v) => seg.chose(v)
  }

  Row {
    id: segRow
    visible: !seg.segmented
    anchors.left: parent.left
    anchors.leftMargin: 14
    anchors.right: parent.right
    anchors.rightMargin: 14
    anchors.verticalCenter: parent.verticalCenter
    height: 28
    spacing: 6

    Repeater {
      model: seg.options

      delegate: Rectangle {
        id: segBtn
        required property var modelData
        width: (segRow.width - 6 * Math.max(0, seg.options.length - 1))
          / Math.max(1, seg.options.length)
        height: 28
        radius: Zenon.windowRadius
        readonly property bool ok: seg.allowed === null
          || seg.allowed.indexOf(segBtn.modelData) >= 0
        readonly property bool on: seg.current === segBtn.modelData
        // PRESSED, DARKENED as ClearChip and Segments are (user, 2026-10-15)
        color: segPress.pressed && segBtn.ok ? Zenon.pressFill
          : segBtn.on
          ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.18)
          : "transparent"
        border.width: 1
        border.color: segBtn.on ? Zenon.cyan : Zenon.border
        opacity: segBtn.ok ? 1 : 0.35
        Behavior on color { ColorAnimation { duration: Zenon.fast } }

        Text {
          anchors.fill: parent
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          text: segBtn.modelData
          elide: Text.ElideRight
          color: segBtn.on ? Zenon.cyan : Zenon.accentKey
          opacity: segPress.pressed ? Zenon.pressDim : 1
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(14)
        }

        MouseArea {
          id: segPress
          anchors.fill: parent
          enabled: segBtn.ok
          onClicked: seg.chose(segBtn.modelData)
        }
      }
    }
  }
}

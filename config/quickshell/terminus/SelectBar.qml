// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// SELECTBAR — the cursor over a list of rows: one bar, sliding between them.
//
//     SelectBar { view: list; index: list.currentIndex; rowH: 26 }
//
// Terminus' cursor, lifted out of it. A fill drawn by each row can only blink
// from one row to the next; this is one rectangle behind the rows that
// travels, on Zenon.travelEase, so the eye follows the cursor rather than
// finding it again. Terminus draws every list with it; plato's file tree and
// its editor's current line are the same bar.
//
// OVER A VIEW, OR NOT. Given a Flickable (`view`) it sits behind that view's
// rows and scrolls with them. Given an item instead (`within`) it fills that,
// for rows that are not a Flickable's — plato's editor lines.
//
// THE HOST, when there is one, is the window it belongs to: terminus hands
// itself, and the bar reads two things off it — whether the cursor is to
// slide at all (a setting), and a pulse that says "land where you are now,
// without the slide" (after a view was frozen and thawed).

import QtQuick
import "../morpheus"

Item {
  id: bar

  property Flickable view: null
  property var host: null
  property int index: 0
  property real rowH: 30
  // an exact position, for rows of different heights; -1 means index × rowH
  property real rowY: -1
  property bool on: true
  property bool animate: true
  // the bar's color: terminus' own, unless a caller says otherwise
  property color color: Zenon.border
  // a rounded bar inset from the row's ends, for lists whose other
  // highlights are cards (alexandria); 0 and 0 is terminus' full-width bar
  property real radius: 0
  property real inset: 0

  readonly property bool slides: bar.animate && (!bar.host || bar.host.cursorSlide !== false)
  readonly property bool filled: !bar.view || bar.view.count === undefined || bar.view.count > 0

  // A BAR COMING BACK LANDS, IT DOES NOT FLY IN. While it has no row (index
  // -1: plato's tree between closing one file's directory and reading the
  // next one's) or is off, it waits where it is, hidden; on its way back it
  // seats on the row without the slide. It used to sweep down from above the
  // first row on every tab switch (user capture, 2026-10-14). `settled` is
  // set a turn after it shows, so `on` and `index` may change in either
  // order in the same turn.
  readonly property bool shown: bar.on && bar.filled && (bar.rowY >= 0 || bar.index >= 0)
  property bool settled: false
  onShownChanged: { if (!bar.shown) bar.settled = false; else settle.restart(); }
  Component.onCompleted: settle.restart()
  Timer { id: settle; interval: 0; onTriggered: bar.settled = bar.shown }
  property real _lastY: 0
  readonly property real wantY: bar.rowY >= 0 ? bar.rowY
    : bar.index >= 0 ? bar.index * bar.rowH : bar._lastY
  onWantYChanged: if (bar.rowY >= 0 || bar.index >= 0) bar._lastY = bar.wantY

  // without a view, the item whose rows these are (plato's editor window)
  property Item within: null

  parent: bar.view ? bar.view : bar.within
  anchors.fill: parent
  clip: true
  z: -1

  Item {
    width: parent.width
    height: parent.height
    y: bar.view ? -(bar.view.contentY - bar.view.originY) : 0

    Rectangle {
      id: slot
      x: bar.inset
      width: parent.width - 2 * bar.inset
      radius: bar.radius
      height: bar.rowH
      y: bar.wantY
      Behavior on y {
        id: slide
        enabled: bar.slides && bar.settled
        YAnimator { duration: Zenon.fast; easing.type: Zenon.travelEase }
      }
      color: bar.color
      visible: bar.shown

      Connections {
        target: bar.host
        ignoreUnknownSignals: true
        function onThawPulseChanged() { slot.reseat(); }
      }
      function reseat() {
        if (Math.abs(slot.y - bar.wantY) < 0.5) return;
        slide.enabled = false;
        slot.y = Qt.binding(function() { return bar.wantY; });
        slide.enabled = Qt.binding(function() { return bar.slides && bar.settled; });
      }
    }
  }
}

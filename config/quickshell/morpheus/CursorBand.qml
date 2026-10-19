// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE CURSOR THAT SLIDES — one band under a list's chosen row, gliding from
// row to row rather than each row lighting and unlighting on its own. It was
// artemis' alone (its selMark); folio, ideo, lexi, zeus, metis, picasso,
// ceres and delphi each lit the row itself, so the cursor jumped there and
// glided here (user, 2026-10-19: "not all panels use sliding cursor"). One
// file now, so every list's cursor moves the same way.
//
//     ListView { id: list; … }                  // or a GridView
//     CursorBand { follows: list; index: popup.sel }
//
//     Column { id: rows; Repeater { id: rep; … } }
//     CursorBand { parent: rows.parent; repeater: rep; index: win.sel }
//
// With a view it parents itself into the view's contentItem, so it scrolls
// with the rows (a child declared inside a ListView lands on the view, not
// its contentItem — see artemis' note). With a Repeater, give it a parent
// beside the Column (a positioner would lay the band out as a row) and it
// follows the chosen item there.
//
// It takes the chosen item's own box, so rows of any height and grid cells
// both work. While the item is not built (scrolled far off, or the model
// just replaced) it holds where it was rather than dropping to the top.
// menuHi, flush, no edge mark: the suite's menu cursor (menu-band rules).
// The row's own fill must not ALSO light for the cursor, or the two show.

import QtQuick
import "."

Rectangle {
  id: band
  // the ListView or GridView it slides in (not `view`: lists name their
  // own view that, and `view: view` would read the band's property)
  property var follows: null
  property var repeater: null
  property int index: -1
  property bool shown: true
  // drawn this far inside the row on each side (a list whose rows have air
  // between them, or a rounded card's band)
  property real insetX: 0
  property real insetY: 0

  // into the view's contentItem by hand: a `parent:` binding that falls back
  // to the parent it was given would read itself
  function adopt() { if (band.follows && band.follows.contentItem) band.parent = band.follows.contentItem; }
  onFollowsChanged: band.adopt()
  // and asked once more after load: a Repeater may have built its items
  // before the Connections below were listening
  Component.onCompleted: { band.adopt(); Qt.callLater(() => band.tick++); }
  z: -1
  color: Zenon.menuHi

  // re-asked whenever the view builds or moves its delegates: itemAtIndex()
  // is a call, not a property, and says nothing when the item it could not
  // find a moment ago now exists
  property int tick: 0
  Connections {
    target: band.follows
    ignoreUnknownSignals: true
    function onCountChanged() { band.tick++; }
    function onContentHeightChanged() { band.tick++; }
    function onContentWidthChanged() { band.tick++; }
    function onWidthChanged() { band.tick++; }
  }
  Connections {
    target: band.repeater
    ignoreUnknownSignals: true
    function onItemAdded() { band.tick++; }
    function onItemRemoved() { band.tick++; }
  }

  readonly property Item target: {
    band.tick;
    if (band.index < 0) return null;
    if (band.repeater) return band.repeater.itemAt(band.index);
    if (band.follows && typeof band.follows.itemAtIndex === "function") return band.follows.itemAtIndex(band.index);
    return null;
  }
  // the chosen item's box in this band's parent; read through its x and y
  // so a move re-places it
  readonly property point at: {
    const t = band.target;
    if (!t || !band.parent) return band.held;
    t.x; t.y; t.width; t.height;
    if (t.parent) { t.parent.x; t.parent.y; }
    return t.parent === band.parent ? Qt.point(t.x, t.y) : t.mapToItem(band.parent, 0, 0);
  }
  property point held: Qt.point(0, 0)
  property size heldSize: Qt.size(0, 0)
  onAtChanged: if (band.target) band.held = band.at
  onTargetChanged: {
    if (!band.target) return;
    band.heldSize = Qt.size(band.target.width, band.target.height);
    // the first time it has somewhere to be it is put there, not slid in
    // from the corner
    if (!band.placed) Qt.callLater(() => band.placed = true);
  }
  property bool placed: false

  x: band.at.x + band.insetX
  y: band.at.y + band.insetY
  width: Math.max(0, (band.target ? band.target.width : band.heldSize.width) - 2 * band.insetX)
  height: Math.max(0, (band.target ? band.target.height : band.heldSize.height) - 2 * band.insetY)
  // nothing past the end: a list emptied under it (every update installed,
  // the last match filtered out) left the band holding the last row's box
  readonly property int rows: {
    band.tick;
    if (band.repeater) return band.repeater.count;
    if (band.follows && band.follows.count !== undefined) return band.follows.count;
    return -1;
  }
  visible: band.shown && band.index >= 0 && (band.rows < 0 || band.index < band.rows) && (band.target !== null || band.placed)

  Behavior on x { enabled: band.placed && Zenon.cursorSlide; NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
  Behavior on y { enabled: band.placed && Zenon.cursorSlide; NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
  Behavior on width { enabled: band.placed && Zenon.cursorSlide; NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
  Behavior on height { enabled: band.placed && Zenon.cursorSlide; NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
}

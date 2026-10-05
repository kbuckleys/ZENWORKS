// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ── one switch in the settings panel ────────────────────────────────────
// A name, the key that does the same thing, and the state as something you
// can click. Its own component because four of these written out by hand is
// four chances for one to drift from the other three.
// ── a preference you DO rather than one you set ─────────────────────────
// PrefRow's shape — the same height, the same hover, the same label — so the
// panel stays one list. What differs is the right-hand end: a switch says
// "this is how things are" and would be a lie here, because nothing stays
// on afterwards. A verb says what will happen, and a count beside it says
// how much there is to happen to, which is also how you know whether the row
// is worth pressing at all.
// A CHOICE on the batch-rename card, shown as the answer with the rest put
// away. A dropdown and not another row of chips: these options are
// EXCLUSIVE and each one hides the others' controls, so a shape that shows
// one answer is telling the truth where six lit-or-unlit chips would be
// claiming they could all be on at once.
//
// Shared: terminus' batch-rename card and collection editor, and picasso's
// rename of several pictures. `host` is the window, or the card, holding
// the one open dropdown (bulkOpenDrop) and the wheel's step (wheelStep).

import QtQuick
import "../morpheus"

Item {
  id: drop
  // whoever keeps the one open dropdown — see the header
  property var host: null
  // [[value, label], ...] rather than two parallel lists, so a row cannot
  // go out of step with its own label.
  property var options: []
  property string value: ""
  property bool expanded: false
  signal picked(string v)

  // WHERE THE LIST ACTUALLY LIVES. A list hanging under a 28px chip is
  // entirely outside its own parent's bounds, and Qt Quick will RENDER a
  // child out there while refusing to hit-test it — so the menu drew
  // perfectly and not one row in it could be clicked. Reparented into a
  // layer that spans the card, where every row sits inside its parent and
  // the mouse can find it.
  property Item overlay: null
  property real listX: 0
  property real listY: 0
  property real listH: 0

  // THE SAME CONTRACT A FIELD OFFERS. The card owns the tab ring and hands
  // focus round it by calling claim() and asking focused — a control that
  // cannot answer those is one the keyboard has to skip, and the mode
  // picker is the first thing in the row.
  readonly property bool focused: drop.activeFocus
  signal tabbed()
  signal backTabbed()
  function claim() { drop.forceActiveFocus(); }

  // Which row the KEYBOARD is on, as opposed to which one is chosen.
  // Only meaningful while open, and reset to the chosen row each time it
  // opens so arrowing starts from where you already are.
  property int cursor: 0
  function indexOfValue() {
    for (let i = 0; i < drop.options.length; ++i)
      if (drop.options[i][0] === drop.value) return i;
    return 0;
  }
  function choose(i) {
    if (i < 0 || i >= drop.options.length) return;
    drop.expanded = false;
    drop.picked(drop.options[i][0]);
  }

  Keys.onPressed: (e) => {
    // Tab LEAVES, and closes on the way out: a list left hanging over the
    // card while the caret is three controls away is a menu nobody owns.
    if (e.key === Qt.Key_Tab) {
      e.accepted = true; drop.expanded = false; drop.tabbed(); return;
    }
    if (e.key === Qt.Key_Backtab) {
      e.accepted = true; drop.expanded = false; drop.backTabbed(); return;
    }
    // Escape closes the LIST if one is open, and is left alone otherwise
    // so it still reaches the card and shuts that.
    if (e.key === Qt.Key_Escape) {
      if (!drop.expanded) return;
      e.accepted = true; drop.expanded = false; return;
    }
    if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter
        || e.key === Qt.Key_Space) {
      e.accepted = true;
      if (drop.expanded) drop.choose(drop.cursor);
      else { drop.cursor = drop.indexOfValue(); drop.expanded = true; }
      return;
    }
    if (e.key === Qt.Key_Down || e.key === Qt.Key_Up) {
      e.accepted = true;
      const step = e.key === Qt.Key_Down ? 1 : -1;
      if (!drop.expanded) {
        // Closed, an arrow OPENS it rather than silently changing the
        // value underneath you — the same thing every other list in this
        // window does with a first keypress.
        drop.cursor = drop.indexOfValue();
        drop.expanded = true;
        return;
      }
      drop.cursor = Math.max(0, Math.min(drop.options.length - 1,
                                         drop.cursor + step));
      return;
    }
  }

  // Recomputed when it opens, not bound: mapToItem is a function call and
  // a binding around one does not re-run when the geometry under it moves.
  // A dropdown does not move while it is open, so once is enough.
  // ── WHERE IT FITS, NOT JUST WHERE IT BELONGS ───────────────────────
  // A card sized by its own content is often shorter than a list of nine
  // options, and a list that simply hung downwards from the last rule ran
  // off the bottom of the card and was cut in half by the clip. So the
  // space is measured and the list goes wherever there is more of it —
  // and when neither side has enough, it takes what there is and scrolls.
  function reposition() {
    const rowH = Zenon.menuRowHeight;
    const want = drop.options.length * rowH + 8;
    if (!drop.overlay) {
      drop.listX = 0;
      drop.listY = drop.height + 4;
      drop.listH = want;
      return;
    }
    const pt = drop.mapToItem(drop.overlay, 0, 0);
    const below = drop.overlay.height - (pt.y + drop.height) - 6;
    const above = pt.y - 6;
    drop.listX = pt.x;
    // Downwards by preference — that is where a menu is looked for — and
    // upwards only when down genuinely has less room.
    if (want <= below || below >= above) {
      drop.listH = Math.min(want, Math.max(rowH + 8, below));
      drop.listY = pt.y + drop.height + 4;
    } else {
      drop.listH = Math.min(want, Math.max(rowH + 8, above));
      drop.listY = pt.y - drop.listH - 4;
    }
  }

  onExpandedChanged: {
      if (!drop.host) return;
    if (drop.expanded) { drop.reposition(); drop.host.bulkOpenDrop = drop; }
    else if (drop.host.bulkOpenDrop === drop) drop.host.bulkOpenDrop = null;
  }

  Connections {
    target: drop.host
    ignoreUnknownSignals: true
    function onBulkOpenDropChanged() {
      if (drop.host.bulkOpenDrop !== drop) drop.expanded = false;
    }
  }

  readonly property string label: {
    for (let i = 0; i < drop.options.length; ++i)
      if (drop.options[i][0] === drop.value) return drop.options[i][1];
    return "";
  }
  // Sized to the WIDEST option, not to the current one: a control that
  // changes width when you change its value shoves the field beside it.
  //
  // Measured in a FUNCTION and stored, not computed in the binding —
  // measuring means writing to the TextMetrics, and writing to something
  // a binding is reading is how a binding loop starts.
  property real widest: 0
  function remeasure() {
    let w = 0;
    for (let i = 0; i < drop.options.length; ++i) {
      dropMetric.text = drop.options[i][1];
      w = Math.max(w, dropMetric.width);
    }
    drop.widest = w;
  }
  onOptionsChanged: drop.remeasure()
  Component.onCompleted: drop.remeasure()

  implicitWidth: drop.widest + 34
  // Grows with the text it carries, so a card that wants larger type
  // does not end up with larger words in a chip sized for smaller ones.
  property int textSize: 13
  implicitHeight: Math.max(28, drop.textSize + 15)

  TextMetrics {
    id: dropMetric
    font.family: Zenon.face
    font.pixelSize: drop.textSize
  }

  Rectangle {
    id: dropChip
    anchors.fill: parent
    radius: Zenon.windowRadius
    color: drop.expanded || dropHov.hovered ? Zenon.headBg
      : Qt.rgba(Zenon.white.r, Zenon.white.g, Zenon.white.b, 0.05)
    border.width: 1
    border.color: drop.expanded || drop.activeFocus ? Zenon.cyan
                                                    : Zenon.border
    Behavior on color { ColorAnimation { duration: Zenon.fast } }
    Behavior on border.color { ColorAnimation { duration: Zenon.fast } }

    Text {
      anchors.left: parent.left
      anchors.leftMargin: 9
      anchors.verticalCenter: parent.verticalCenter
      text: drop.label
      color: Zenon.white
      font.family: Zenon.face
      font.pixelSize: drop.textSize
    }
    Text {
      anchors.right: parent.right
      anchors.rightMargin: 9
      anchors.verticalCenter: parent.verticalCenter
      // Down, not right: it opens downwards, and the arrow on a menu row
      // that opens sideways is the one glyph this must not borrow.
      text: "\uF078"
      color: Zenon.white
      font.family: Zenon.faceMono
      font.pixelSize: drop.textSize - 2
    }
  }
  HoverHandler { id: dropHov }
  MouseArea {
    anchors.fill: parent
    onClicked: {
      drop.claim();
      if (!drop.expanded) drop.cursor = drop.indexOfValue();
      drop.expanded = !drop.expanded;
    }
  }

  // The list. Parented to the drop and drawn with a z of its own, which
  // is why patRow lifts its whole self while one is open — see there.
  Rectangle {
    id: dropList
    visible: drop.expanded
    parent: drop.overlay ? drop.overlay : drop
    x: drop.listX
    y: drop.listY
    // FROM THE MEASUREMENT, not from the Column inside it. dropCol is
    // anchored to this rectangle, and its rows size to dropCol — so asking
    // dropCol how wide it wants to be is asking a child how wide its own
    // parent should be. That is a polish loop, and a polish loop does not
    // warn and carry on: layout never settles and the whole window comes
    // up blank.
    width: Math.max(drop.width, drop.widest + 24)
    height: drop.listH
    // THE SAME SURFACE THIS WINDOW'S OTHER MENUS ARE. panelBg is
    // rgba(0,0,0,panelOpacity) — a colour built for a layer surface with
    // the compositor's blur behind it. There is no blur behind anything
    // inside a window, so it was simply see-through, and the verb chips
    // underneath read straight through the list.
    radius: Zenon.menuRadius
    color: Zenon.menuBgSolid
    border.width: 1
    border.color: Zenon.border
    z: 100

    ListView {
      id: dropView
      anchors.fill: parent
      anchors.topMargin: 4
      anchors.bottomMargin: 4
      clip: true
      model: drop.options
      // Follows the keyboard, so arrowing past the bottom of a clamped
      // list scrolls rather than moving a cursor nobody can see.
      currentIndex: drop.cursor
      onCurrentIndexChanged: dropView.positionViewAtIndex(
        dropView.currentIndex, ListView.Contain)
      boundsBehavior: Flickable.DragAndOvershootBounds
      boundsMovement: Flickable.FollowBoundsBehavior
      ElasticScroll { view: dropView; step: drop.host && drop.host.wheelStep ? drop.host.wheelStep : 120 }

      delegate: Rectangle {
        id: dropRow
        required property var modelData
        required property int index
        width: dropView.width
        height: Zenon.menuRowHeight
        // Either pointer: the keyboard's row and the mouse's row light
        // the same way, because they are the same thing said twice.
        color: rowHov.hovered || drop.cursor === dropRow.index
          ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.16)
          : "transparent"

        Text {
          anchors.left: parent.left
          anchors.leftMargin: 12
          anchors.right: parent.right
          anchors.rightMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideRight
          text: dropRow.modelData[1]
          // The chosen one keeps the cyan a state is owed; the rest are
          // plain white, the same as every other pickable label here.
          color: dropRow.modelData[0] === drop.value ? Zenon.cyan
                                                     : Zenon.white
          font.family: Zenon.face
          font.pixelSize: drop.textSize
        }

        HoverHandler { id: rowHov }
        MouseArea {
          anchors.fill: parent
          onClicked: drop.choose(dropRow.index)
        }
      }
    }
  }
}

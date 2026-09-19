// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import "../morpheus"
import "folio.js" as Folio

PanelWindow {
  id: popup

  WlrLayershell.layer: WlrLayer.Overlay

  // Explicitly the whole surface when idle and explicitly nothing while
  // dragging, rather than leaning on what an unset mask means — getting that
  // backwards leaves the popup permanently click-through. closeArea already
  // fills the window, so it IS the full-surface region.
  mask: Region { item: popup.dragging ? null : closeArea }

  property bool shown: false
  // ── DRAGGING ONE OF THESE SOMEWHERE ELSE ──────────────────────────────
  // Artemis' arrangement, wholesale, because the problem is identical: a
  // layer-shell popup that must let go of the pointer and of its own focus
  // grab for as long as a drag is in flight, without cancelling the drag.
  //
  // Wayland's drag grab is separate from the surface input region, so
  // dropping the region mid-drag does not cancel anything — it only decides
  // who the drop resolves to, which has to be the application underneath.
  property bool dragging: false
  property bool morphMode: false
  // 0..1, driven by shell.qml, which owns the crossfade schedule: 0 until the
  // pill's own row has finished clearing, then rising to 1 as the pill
  // finishes taking this layer's shape
  property real morphFade: 1

  property real showFactor: 0

  property bool collapsing: false
  // ── NO SCALE WHEN MORPHED, AND THAT IS THE POINT ────────────────────
  // This briefly followed contentFade so the panel would grow as it faded,
  // the way a detached one does. It looked wrong, and the capture showed
  // why: detached, the panel is arriving out of nothing and 0.94 -> 1.0
  // reads as arrival. Morphed, the container is ALREADY THERE — it is the
  // pill — so the same scale is not an entrance, it is the text being
  // stretched horizontally in place. Measured across the morph: the
  // content spread outward over seven frames.
  //
  // So a morph is a straight crossfade inside a shape that is already
  // right, and the scale belongs to the case that has something to scale
  // from.
  readonly property real growth: popup.showFactor
  readonly property real panelX: (popup.collapsing ? 0.985 + 0.015 * popup.growth
                        : 0.94 + 0.06 * popup.growth)
  readonly property real panelY: (popup.collapsing ? 0.82 + 0.18 * popup.growth
                        : 0.90 + 0.10 * popup.growth)
  // Morphed, the handover is timed off the PILL's progress, not this popup's
  // own showFactor: showFactor is OutCubic and front-loaded, so it crossed the
  // threshold ~25ms in and this layer's content faded up on top of a morpheus
  // row that was still 80% opaque.
  // Math.min, not morphFade alone. Handing the pill straight to another
  // layer leaves morphFade pinned at 1 — the pill never un-morphs, so there
  // is nothing to ease it down — and this layer stayed fully opaque until its
  // window simply blinked out. Its own closeAnim is already easing
  // showFactor to 0, so taking the lower of the two fades it out on the way
  // between layers while leaving the normal open schedule untouched.
  readonly property real contentFade: popup.morphMode
    ? Math.min(popup.morphFade, popup.showFactor) : popup.showFactor
  property string mode: "text"
  property string query: ""
  property var entries: []
  property var imageIds: []
  property var rows: []
  property var imgRows: []
  property var thumbsReady: ({})
  property int thumbStamp: 0
  property int sel: 0
  property bool hasText: false
  property bool hasImg: false
  property string lastAction: ""

  property var statusbar: null

  readonly property color bgColor: Zenon.layerBg
  readonly property color borderColor: Zenon.surfaceBorder
  readonly property color selColor: Zenon.selBg
  readonly property color msgColor: Zenon.headBg
  readonly property color msgBorder: Zenon.msgBorder
  readonly property color fgColor: Zenon.white
  readonly property color hintColor: Zenon.muted

  // ── THE KEYS, DRAWN AS KEYS ──────────────────────────────────────────
  // The hints were rich text with the key in bold and its word after it in
  // grey, and the colours were hex literals inside folio.js — the palette
  // said twice. A chip says "this is a key you press" the way the rest of
  // this desktop says it, and takes its ink from Zenon like everything else.
  //
  // The recipe is terminus' KeyChip, which is an inline component of that
  // file and so cannot be imported.
  component KeyCap: Rectangle {
    id: cap
    property string label: ""
    implicitWidth: capText.implicitWidth + 13
    implicitHeight: 19
    radius: 5
    color: Qt.rgba(Zenon.keyInk.r, Zenon.keyInk.g, Zenon.keyInk.b, 0.10)
    border.width: 1
    border.color: Qt.rgba(Zenon.keyInk.r, Zenon.keyInk.g, Zenon.keyInk.b, 0.30)
    visible: cap.label !== ""

    Text {
      id: capText
      anchors.centerIn: parent
      text: cap.label
      color: Zenon.keyInk
      font.family: Zenon.face
      font.pixelSize: 11
    }
  }

  readonly property int textCellH: 32
  readonly property int textRows: 12
  readonly property int imgCell: 200
  readonly property int imgRowsVisible: 3
  readonly property int msgH: 28

  readonly property int imgPerRow: Math.max(1, Math.floor(1000 / popup.imgCell))

  readonly property int textColsUsed: popup.query.length > 0 ? 1 : 2
  readonly property int textRowsNeeded: Math.min(Math.max(1, Math.ceil(popup.rows.length / popup.textColsUsed)), popup.textRows)
  readonly property int imgRowsNeeded: Math.min(Math.ceil(popup.imgRows.length / popup.imgPerRow), popup.imgRowsVisible)

  function cellText(preview) {
    const cellW = popup.textColsUsed === 1 ? panel.width : textGrid.cellWidth;
    const avail = Math.max(1, Math.floor((cellW - 32) / textMetrics.advanceWidth));
    const p = preview.length > avail ? preview.slice(0, Math.max(0, avail - 1)) + "…" : preview;
    return Folio.highlightedPreview(p, popup.query);
  }
  readonly property real textCellHeight: popup.textCellH

  readonly property real bodyH: popup.mode === "image"
    ? popup.imgRowsNeeded * popup.imgCell + popup.msgH
    : popup.textRowsNeeded * popup.textCellHeight + popup.msgH

  TextMetrics {
    id: textMetrics
    font.family: Zenon.face
    font.pixelSize: 16
    font.weight: 600
    text: "M"
  }

  visible: popup.showFactor > 0.01
  color: "transparent"

  anchors { left: true; right: true; top: true; bottom: true }
  focusable: true
  exclusionMode: ExclusionMode.Ignore

  NumberAnimation {
    id: openAnim
    target: popup; property: "showFactor"
    to: 1; duration: Zenon.slow; easing.type: Zenon.ease
  }

  NumberAnimation {
    id: closeAnim
    target: popup; property: "showFactor"
    to: 0; duration: Zenon.slow; easing.type: Zenon.ease
    onFinished: popup.shown = false
  }

  HyprlandFocusGrab {
    id: grab
    windows: [ popup ]
    // Not while dragging: the pointer is over another application by design
    // at that point, and closing here would destroy the row the drag is
    // sourced from, mid-gesture.
    active: popup.shown && !popup.dragging
    onCleared: {
      popup.log("grab cleared");
      popup.closePopup();
    }
  }

  IpcHandler {
    target: "Folio"
    function toggle() {
      popup.toggle();
    }
  }

  Process {
    id: listProc
    stdout: StdioCollector {
      id: out
      waitForEnd: true
      onStreamFinished: popup.onList(out.text)
    }
  }

  Process {
    id: thumbProc
    onExited: popup.onThumbsDone()
  }

  Process {
    id: actionProc
    onExited: popup.onActionDone()
  }

  Process {
    id: logProc
  }

  function log(msg) {
    logProc.command = ["sh", "-c",
      "printf '%s\\n' " + Strings.shellQuote(Qt.formatTime(new Date(), "hh:mm:ss") + " " + msg) +
      " >> /tmp/folio_state.txt"];
    logProc.running = true;
  }

  function openPopup() {
    popup.shown = true;
    popup.collapsing = false;
    popup.mode = "text";
    popup.query = "";
    filter.text = "";
    popup.sel = 0;
    popup.reload();
    focusRetry.counter = 0;
    focusRetry.restart();
    closeAnim.stop();
    popup.showFactor = 0;
    openAnim.restart();
    popup.log("open");
  }

  function closePopup() {
    popup.collapsing = true;
    openAnim.stop();
    closeAnim.restart();
    popup.log("close");
  }

  function toggle() {
    if (popup.shown) popup.closePopup();
    else popup.openPopup();
  }

  function reload() {
    listProc.command = ["cliphist", "-preview-width", "10000", "list"];
    listProc.running = true;
  }

  function onList(text) {
    const parsed = Folio.parseList(text);
    popup.entries = parsed.entries;
    popup.imageIds = parsed.imageIds;
    popup.hasText = parsed.entries.length > 0;
    popup.hasImg = parsed.imageIds.length > 0;

    if (popup.mode === "text" && !popup.hasText && popup.hasImg) popup.mode = "image";
    else if (popup.mode === "image" && !popup.hasImg && popup.hasText) popup.mode = "text";

    popup.rebuildImageRows();
    popup.applyFilter();
    popup.generateThumbs();
    popup.clampSel();
  }

  function rebuildImageRows() {
    const tdir = Folio.thumbDir();
    const arr = [];
    for (let i = 0; i < popup.imageIds.length; ++i) {
      arr.push({ id: popup.imageIds[i], path: tdir + "/" + popup.imageIds[i] + ".png" });
    }
    popup.imgRows = arr;
  }

  function applyFilter() {
    popup.rows = Folio.filterEntries(popup.entries, popup.query);
    popup.clampSel();
  }

  function generateThumbs() {
    if (thumbProc.running) return;
    const cmd = Folio.thumbCommand(popup.imageIds, Folio.thumbDir());
    if (!cmd) return;
    thumbProc.command = ["sh", "-c", cmd];
    thumbProc.running = true;
  }

function onThumbsDone() {

  const ready = {};
  for (const r of popup.imgRows) ready[r.id] = true;
  popup.thumbsReady = ready;
  popup.thumbStamp++;
  popup.followSelection();
}

  function runAction(cmd, kind) {
    popup.lastAction = kind;
    actionProc.command = ["sh", "-c", cmd];
    actionProc.running = true;
  }

  function onActionDone() {
    popup.log("action=" + popup.lastAction);
    if (popup.lastAction === "delete") popup.reload();
    else popup.closePopup();
    popup.lastAction = "";
  }

  function confirm() {
    const len = popup.mode === "image" ? popup.imgRows.length : popup.rows.length;
    if (len === 0) return;
    const id = popup.mode === "image"
      ? popup.imgRows[popup.sel].id
      : popup.rows[popup.sel].id;
    popup.runAction(Folio.copyCommand(id), "copy");
  }

  function openSelected() {
    if (popup.mode !== "image" || popup.imgRows.length === 0) return;
    popup.runAction(Folio.openCommand(popup.imgRows[popup.sel].id, Folio.openDir()), "open");
  }

  function deleteSelected() {
    const len = popup.mode === "image" ? popup.imgRows.length : popup.rows.length;
    if (len === 0) return;
    const id = popup.mode === "image"
      ? popup.imgRows[popup.sel].id
      : popup.rows[popup.sel].id;
    popup.runAction(Folio.deleteCommand(id, Folio.thumbDir()), "delete");
  }

  function toggleMode() {
    const target = popup.mode === "image" ? "text" : "image";
    const avail = target === "text" ? popup.hasText : popup.hasImg;
    popup.log("toggle target=" + target + " avail=" + avail);
    if (!avail || popup.mode === target) return;
    popup.mode = target;
    popup.query = "";
    filter.text = "";
    popup.sel = 0;
    popup.applyFilter();
    popup.followSelection();
    focusRetry.restart();
  }

  function rowCount() {
    return popup.mode === "image" ? popup.imgRows.length : popup.rows.length;
  }

  function stepSel(delta) {
    const len = popup.rowCount();
    if (len === 0) return;
    popup.sel = ((popup.sel + delta) % len + len) % len;
    popup.followSelection();
  }

  function moveVert(delta) {
    const len = popup.rowCount();
    if (len === 0) return;
    const cols = popup.mode === "image" ? popup.imgPerRow : popup.textColsUsed;
    const rows = Math.ceil(len / cols);
    const row = Math.floor(popup.sel / cols);
    const col = popup.sel % cols;
    let newRow = (row + delta) % rows;
    if (newRow < 0) newRow += rows;
    const rowValid = (newRow === rows - 1) ? (len - newRow * cols) : cols;
    const newCol = Math.min(col, rowValid - 1);
    popup.sel = newRow * cols + newCol;
    popup.followSelection();
  }

  function moveHoriz(delta) {
    const len = popup.rowCount();
    if (len === 0) return;
    const cols = popup.mode === "image" ? popup.imgPerRow : popup.textColsUsed;
    const row = Math.floor(popup.sel / cols);
    const col = popup.sel % cols;
    const rowStart = row * cols;
    const rowLen = Math.min(cols, len - rowStart);
    const newCol = (col + delta) % rowLen;
    const adjCol = newCol < 0 ? newCol + rowLen : newCol;
    popup.sel = rowStart + adjCol;
    popup.followSelection();
  }

  function pageMove(delta) {
    const len = popup.rowCount();
    if (len === 0) return;

    const page = popup.mode === "image"
      ? popup.imgPerRow * popup.imgRowsVisible
      : popup.textRowsNeeded * popup.textColsUsed;
    popup.sel = Math.max(0, Math.min(len - 1, popup.sel + delta * page));
    popup.followSelection();
  }

  function goHome() {
    if (popup.rowCount() > 0) popup.sel = 0;
    popup.followSelection();
  }

  function goEnd() {
    const len = popup.rowCount();
    if (len > 0) popup.sel = len - 1;
    popup.followSelection();
  }

  function clampSel() {
    const len = popup.rowCount();
    if (len === 0) popup.sel = 0;
    else if (popup.sel >= len) popup.sel = len - 1;
    else if (popup.sel < 0) popup.sel = 0;
    popup.followSelection();
  }

  function followSelection() {
    Qt.callLater(() => {
      textGrid.positionViewAtIndex(popup.sel, ListView.Contain);
      imgGrid.positionViewAtIndex(popup.sel, ListView.Contain);
    });
  }

  // ── WHAT YOU ARE CARRYING, DRAWN BESIDE THE CURSOR ────────────────────
  // Without it a drag out of here is an invisible one: the popup gets out of
  // the way the moment the gesture starts, so between picking an entry up and
  // dropping it there is nothing on screen saying which entry it was.
  //
  // Sized from the text and anchored rather than laid out, because
  // grabToImage reads the width in the same tick the labels are filled in — a
  // Row would not have set its own width yet and the first drag of a session
  // would carry a card a few pixels wide.
  property string dragLabel: ""
  property string dragGlyph: ""
  property color dragInk: Zenon.cyan
  property var dragGrab: null

  Item {
    id: dragCard
    opacity: 0
    z: -100
    x: -4000
    height: 38

    readonly property real pad: 12
    width: dragCard.pad * 2 + dragCardGlyph.implicitWidth
      + (popup.dragGlyph !== "" ? 8 : 0) + dragCardLabel.implicitWidth

    Rectangle {
      anchors.fill: parent
      radius: 6
      color: Zenon.layerBg
      border.width: 1
      border.color: Zenon.cyan
    }

    Text {
      id: dragCardGlyph
      anchors.left: parent.left
      anchors.leftMargin: dragCard.pad
      anchors.verticalCenter: parent.verticalCenter
      text: popup.dragGlyph
      color: popup.dragInk
      font.family: Zenon.faceFixed
      font.pixelSize: 16
    }

    Text {
      id: dragCardLabel
      anchors.left: dragCardGlyph.right
      anchors.leftMargin: popup.dragGlyph !== "" ? 8 : 0
      anchors.verticalCenter: parent.verticalCenter
      text: popup.dragLabel
      color: Zenon.white
      font.family: Zenon.face
      font.pixelSize: 15
    }
  }

  // The picture is made BEFORE the drag is offered: Drag.imageSource is read
  // when Drag.active turns true and grabToImage answers a frame later, so
  // setting them the other way round makes every drag carry the previous
  // one's picture.
  function dragPicture(label, glyph, ink, then) {
    popup.dragLabel = label;
    popup.dragGlyph = glyph;
    popup.dragInk = ink;
    // A failed grab is not a reason to refuse the drag; it simply goes
    // without a picture.
    if (!dragCard.grabToImage(function(res) {
          popup.dragGrab = res; then(res.url);
        }))
      then("");
  }

  // The original behind a thumbnail, written out so it can be handed over —
  // see Folio.dragFileCommand. Asynchronous, like the grab above, so the
  // drag is offered from the callback rather than before it.
  property var dragThen: null
  Process {
    id: dragProc
    stdout: StdioCollector {
      id: dragOut
      waitForEnd: true
      onStreamFinished: {
        const f = String(dragOut.text || "").trim();
        const then = popup.dragThen;
        popup.dragThen = null;
        if (then) then(f);
      }
    }
  }

  function dragDecode(id, then) {
    popup.dragThen = then;
    dragProc.command = ["sh", "-c", Folio.dragFileCommand(id, Folio.openDir())];
    dragProc.running = true;
  }

  MouseArea {
    id: closeArea
    anchors.fill: parent
    z: 0
    onClicked: popup.closePopup()
  }

  // shell.qml sizes the morphed pill from this; without it the pill fell back
  // to a hardcoded 320px and the panel floated free of its own background
  function calcHeight() {
    return popup.bodyH;
  }

  Item {
    id: panel
    width: Zenon.layerWidth(1000)
    height: popup.bodyH
    // Zenon.slow is the pill's own height easing in shell.qml; if these drift
    // apart the panel visibly detaches from its background mid-resize
    Behavior on height { NumberAnimation { duration: Zenon.slow; easing.type: Zenon.ease } }
    // Either edge. A layer opens out of the pill, so it has to be on the
    // same one — anchored to whichever it is and given the same lift, with
    // the unused anchor left undefined so the two can never both apply.
    anchors {
      horizontalCenter: parent.horizontalCenter
      top: Zenon.barTop ? parent.top : undefined
      bottom: Zenon.barTop ? undefined : parent.bottom
      topMargin: Zenon.edgeLift(popup.morphMode, popup.screen, popup.statusbar)
      bottomMargin: Zenon.edgeLift(popup.morphMode, popup.screen, popup.statusbar)
    }
    z: 1
    opacity: popup.contentFade
    transform: Scale {
      origin.x: panel.width / 2
      // grows out of the edge the bar is on, which is the edge it came from
      origin.y: Zenon.barTop ? 0 : panel.height
      xScale: popup.panelX
      yScale: popup.panelY
    }

    MouseArea { anchors.fill: parent }

    LayerShadow {
      panel: bg
      cornerRadius: Zenon.pillRadius
      morphed: popup.morphMode
    }

    // ClippingRectangle, not Rectangle + clip: true. Qt's own clip is
    // RECTANGULAR — it clips to the bounding box and knows nothing about the
    // radius — so every square child painted to the panel's edge (the bottom
    // strip most visibly) filled in the rounded corners behind it. This one
    // clips to the rounded shape itself.
    ClippingRectangle {
      id: bg
      anchors.fill: parent
      // Grown by its own border: a ClippingRectangle insets its children by
      // border.width on every side, so the content box came out 2px smaller
      // than the panel and any layout measured against the panel's size fell
      // one row or one column short. This hands the content its full box back.
      anchors.margins: -bg.border.width
      color: popup.bgColor
      radius: Zenon.pillRadius
      topLeftRadius: Zenon.pillRadius
      topRightRadius: Zenon.pillRadius
      bottomLeftRadius: Zenon.pillRadius
      bottomRightRadius: Zenon.pillRadius
      border.color: popup.borderColor
      border.width: 1

      Column {
      anchors.fill: parent

      Item {
        id: body
        width: parent.width
        height: parent.height - msgBar.height

          Text {
            id: emptyLabel
            anchors.centerIn: parent
            text: "No clipboard entries"
            color: popup.hintColor
            font.family: Zenon.face
            font.weight: 600
            font.pixelSize: 13
            visible: popup.shown && !popup.hasText && !popup.hasImg
          }

          Text {
            anchors.centerIn: parent
            text: "No matches found"
            color: popup.hintColor
            font.family: Zenon.face
            font.weight: 600
            font.pixelSize: 15
            visible: popup.shown && popup.mode === "text" && popup.rows.length === 0 && popup.hasText
          }

        Item {
          id: textPane
          anchors.fill: parent
          visible: opacity > 0.01
          opacity: popup.mode === "text" ? 1 : 0
          x: popup.mode === "text" ? 0 : -24
          Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
          Behavior on x { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }

          GridView {
            id: textGrid
            anchors.fill: parent
            clip: true
            flow: GridView.FlowLeftToRight
            cellWidth: textGrid.width / popup.textColsUsed
            cellHeight: popup.textCellHeight
            model: popup.rows
            highlightMoveDuration: 120

            delegate: Item {
              id: textRow
              required property var modelData
              required property int index
              width: textGrid.cellWidth
              height: textGrid.cellHeight

              // The WHOLE entry, not the preview the cell shows — the preview
              // is trimmed and marked up for reading in a narrow cell, and
              // what the other application wants is what was copied.
              //
              // Drag.active is never bound: a binding starts the drag the
              // instant the handler activates, which is a frame before
              // grabToImage can answer, so the card would always be empty.
              Drag.active: false
              Drag.source: textRow
              Drag.keys: ["text/plain"]
              Drag.mimeData: ({ "text/plain": String(textRow.modelData.content || "") })
              Drag.supportedActions: Qt.CopyAction
              Drag.dragType: Drag.Automatic
              Drag.hotSpot.x: 0
              Drag.hotSpot.y: 0
              Drag.onDragFinished: function(dropAction) {
                textRow.Drag.active = false;
                popup.dragging = false;
                if (dropAction === Qt.CopyAction) popup.closePopup();
              }

              DragHandler {
                target: null
                onActiveChanged: {
                  if (!active) return;
                  // region first, so the surface is already transparent by
                  // the time the drag is offered
                  popup.dragging = true;
                  popup.dragPicture(Folio.plain(textRow.modelData.preview),
                                    "\uF0F6", Zenon.cyan, function(url) {
                    textRow.Drag.imageSource = url;
                    textRow.Drag.active = true;
                  });
                }
              }

              Rectangle {
                anchors.fill: parent
                color: index === popup.sel ? popup.selColor : "transparent"
              }

              Text {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                text: popup.cellText(modelData.preview)
                color: popup.fgColor
                textFormat: Text.RichText
                font.family: Zenon.face
                font.weight: 600
                font.pixelSize: 16
                clip: true
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                horizontalAlignment: Text.AlignLeft
                verticalAlignment: Text.AlignVCenter
              }

              MouseArea {
                anchors.fill: parent
                // ONE CLICK PICKS, TWO COMMIT. A single click used to paste
                // and close, which cannot coexist with dragging an entry out
                // — every drag begins with a press on the thing being
                // dragged, and the release that ends it read as a click. It
                // also made the most destructive gesture here the cheapest
                // one: a mis-click pasted into whatever had focus.
                onClicked: popup.sel = index
                onDoubleClicked: {
                  popup.sel = index;
                  popup.confirm();
                }
              }
            }
          }

          // A SIBLING OF THE VIEW, never a child of it — inside, it becomes
          // part of the scrolling content: it travels with the cells and its
          // anchors resolve against the content item, which is as tall as the
          // whole list. It hides itself when everything fits.
          Scrollbar {
            flick: textGrid
            anchors.right: textGrid.right
            anchors.top: textGrid.top
            anchors.bottom: textGrid.bottom
          }
        }

        Item {
          id: imgPane
          anchors.fill: parent
          visible: opacity > 0.01
          opacity: popup.mode === "image" ? 1 : 0
          x: popup.mode === "image" ? 0 : 24
          Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
          Behavior on x { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }

          GridView {
            id: imgGrid
            anchors.fill: parent
            clip: true
            flow: GridView.FlowLeftToRight
            cellWidth: popup.imgCell
            cellHeight: popup.imgCell
            model: popup.imgRows
            highlightMoveDuration: 120

            delegate: Item {
              id: imgRow
              required property var modelData
              required property int index
              width: imgGrid.cellWidth
              height: imgGrid.cellHeight

              // A FILE, and the real one rather than the thumbnail this cell
              // is drawing — see Folio.dragFileCommand. The mime data cannot
              // be written until that file exists, so unlike the text rows
              // above it is filled in from the decode's callback.
              Drag.active: false
              Drag.source: imgRow
              Drag.keys: ["text/uri-list"]
              Drag.supportedActions: Qt.CopyAction
              Drag.dragType: Drag.Automatic
              Drag.hotSpot.x: width / 2
              Drag.hotSpot.y: height / 2
              Drag.onDragFinished: function(dropAction) {
                imgRow.Drag.active = false;
                popup.dragging = false;
                if (dropAction === Qt.CopyAction) popup.closePopup();
              }

              DragHandler {
                target: null
                onActiveChanged: {
                  if (!active) return;
                  popup.dragging = true;
                  popup.dragDecode(imgRow.modelData.id, function(file) {
                    // Nothing decoded means nothing to carry: let go of the
                    // surface again rather than offering an empty drag.
                    if (file === "") { popup.dragging = false; return; }
                    imgRow.Drag.mimeData = {
                      "text/uri-list": "file://" + encodeURI(file) + "\r\n"
                    };
                    popup.dragPicture(Folio.baseName(file), "\uF03E",
                                      Zenon.cyan, function(url) {
                      imgRow.Drag.imageSource = url;
                      imgRow.Drag.active = true;
                    });
                  });
                }
              }

              Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: 10
                color: "transparent"
                border.color: index === popup.sel ? Zenon.muted : "transparent"
                border.width: index === popup.sel ? 2 : 0

                Image {
                  anchors.fill: parent
                  anchors.margins: 4
                  source: popup.thumbsReady[modelData.id]
                    ? "file://" + modelData.path + "?v=" + popup.thumbStamp
                    : ""
                  asynchronous: true
                  fillMode: Image.PreserveAspectFit
                  sourceSize.width: popup.imgCell
                  sourceSize.height: popup.imgCell
                }
              }

              MouseArea {
                anchors.fill: parent
                // ONE CLICK PICKS, TWO COMMIT. A single click used to paste
                // and close, which cannot coexist with dragging an entry out
                // — every drag begins with a press on the thing being
                // dragged, and the release that ends it read as a click. It
                // also made the most destructive gesture here the cheapest
                // one: a mis-click pasted into whatever had focus.
                onClicked: popup.sel = index
                onDoubleClicked: {
                  popup.sel = index;
                  popup.confirm();
                }
              }
            }
          }

          // A SIBLING OF THE VIEW, never a child of it — inside, it becomes
          // part of the scrolling content: it travels with the cells and its
          // anchors resolve against the content item, which is as tall as the
          // whole list. It hides itself when everything fits.
          Scrollbar {
            flick: imgGrid
            anchors.right: imgGrid.right
            anchors.top: imgGrid.top
            anchors.bottom: imgGrid.bottom
          }
        }
      }

      Rectangle {
        id: msgBar
        width: parent.width
        height: popup.msgH
        color: Zenon.hintBg

        Rectangle {
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: 1
          color: popup.msgBorder
        }

        Row {
          anchors.centerIn: parent
          // Tighter than the old 32, because a chip already draws its own
          // boundary — the space was doing that job.
          spacing: 14

          Repeater {
            model: Folio.hintText(popup.mode)

            delegate: Row {
              id: hintPair
              required property var modelData
              spacing: 5

              KeyCap {
                anchors.verticalCenter: parent.verticalCenter
                label: hintPair.modelData[0]
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: hintPair.modelData[1]
                color: popup.hintColor
                font.family: Zenon.face
                font.pixelSize: 13
              }
            }
          }
        }
      }
    }

    TextInput {
      id: filter

      // A cursorDelegate REPLACES the built-in one, so there is exactly
      // one caret and this decides how it behaves. It breathes, the way
      // every other field on this desktop does — a hard on/off blink
      // was the last thing here still wearing Qt's default.
      cursorDelegate: Rectangle {
        width: 2
        color: Zenon.cyan
        SequentialAnimation on opacity {
          running: filter.activeFocus
          loops: Animation.Infinite
          NumberAnimation { to: 0.2; duration: 620; easing.type: Easing.InOutQuad }
          NumberAnimation { to: 1.0; duration: 620; easing.type: Easing.InOutQuad }
        }
      }
      width: 1
      height: 1
      x: -1
      y: -1
      opacity: 0
      focus: true
      color: "transparent"
      Keys.forwardTo: bg
      onTextChanged: {
        if (popup.mode === "text") {
          popup.query = filter.text;
          popup.sel = 0;
          popup.applyFilter();
        }
      }
    }

    Keys.onEscapePressed: (event) => {
      event.accepted = true;
      if (filter.text !== "") {
        filter.text = "";
        popup.query = "";
      } else {
        popup.closePopup();
      }
    }

    Keys.onReturnPressed: (event) => {
      event.accepted = true;
      if (event.modifiers & Qt.ShiftModifier) popup.openSelected();
      else popup.confirm();
    }

    Keys.onTabPressed: (event) => {
      event.accepted = true;
      popup.toggleMode();
    }

    Keys.onBacktabPressed: (event) => {
      event.accepted = true;
      popup.toggleMode();
    }

    Keys.onLeftPressed: (event) => { event.accepted = true; popup.moveHoriz(-1); }
    Keys.onRightPressed: (event) => { event.accepted = true; popup.moveHoriz(1); }
    Keys.onUpPressed: (event) => { event.accepted = true; popup.moveVert(-1); }
    Keys.onDownPressed: (event) => { event.accepted = true; popup.moveVert(1); }

    Keys.onPressed: (event) => {
      if (event.key === Qt.Key_Delete) {
        event.accepted = true;
        popup.deleteSelected();
      } else if (event.key === Qt.Key_Backspace) {
        event.accepted = true;
        if (filter.text.length > 0) {
          const chars = Array.from(filter.text);
          chars.pop();
          filter.text = chars.join("");
        }
      } else if (event.key === Qt.Key_Home) {
        event.accepted = true;
        popup.goHome();
      } else if (event.key === Qt.Key_End) {
        event.accepted = true;
        popup.goEnd();
      } else if (event.key === Qt.Key_PageUp) {
        event.accepted = true;
        popup.pageMove(-1);
      } else if (event.key === Qt.Key_PageDown) {
        event.accepted = true;
        popup.pageMove(1);
      }
    }
    }
    }

  Timer {
    id: focusRetry
    interval: 60
    repeat: true
    onTriggered: {
      if (!popup.shown) {
        stop();
        return;
      }
      filter.forceActiveFocus();
      if (filter.activeFocus) stop();
      if (focusRetry.counter++ > 12) stop();
    }
    property int counter: 0
  }
}

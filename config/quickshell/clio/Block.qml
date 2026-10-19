// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ONE BLOCK OF A NOTE — a paragraph of some kind, drawn: its marker (a
// bullet, a number, a checkbox, a quote's bar, a heading's fold), then its
// words in a rich-text TextEdit; or a picture, a sketch, a file, a table, a
// divider. BlockEditor lays these out and owns every gesture: the pointer
// lands on its overlay, which asks the block under it what is there
// (press(), cursorAt()), so a drag can run from one block into the next.
//
// The block's data is the editor's, found by key on every `rev`; the
// TextEdit is written to only when what it shows is not what the data says
// (an undo, a merge) — never as an echo of its own typing, which would put
// the caret back at the start.

import QtQuick
import Quickshell
import Quickshell.Widgets
import "../morpheus"
import "notes.js" as N
import "../morpheus/icons.js" as Icons

Item {
  id: blk
  required property string key
  required property int index
  property var editor: null

  // a fresh copy on every change, so whatever reads it hears the change —
  // the editor edits its blocks in place
  readonly property var b: { void (blk.editor ? blk.editor.rev : 0); const o = blk.editor ? blk.editor.blockOf(blk.key) : null; return o ? Object.assign({}, o) : null; }
  readonly property string kind: blk.b ? blk.b.k : "body"
  readonly property bool isText: !!N.KINDS[blk.kind] && !!N.KINDS[blk.kind].text
  readonly property bool isList: !!N.KINDS[blk.kind] && !!N.KINDS[blk.kind].list
  readonly property int level: blk.b && blk.b.l ? blk.b.l : 0
  readonly property bool folded: !!blk.editor && blk.editor.isHidden(blk.key)
  readonly property bool mediaHeld: !!blk.editor && blk.editor.mediaSel === blk.key
  property alias te: text
  readonly property real indentW: blk.level * 26
  readonly property real markW: blk.isList || blk.kind === "quote" ? 28 : 0
  readonly property real ts: blk.editor ? blk.editor.textSize : 16

  // its place in a row of pictures and files (BlockEditor ROWS): its share
  // of the column, and where in the row; its y is the editor's to set
  readonly property var share: { void (blk.editor ? blk.editor.rev : 0); void (blk.editor ? blk.editor.blocks : null);
                                 return blk.editor ? blk.editor.shareOf(blk.key) : { slot: 0, n: 1 }; }
  // its even share of the column; a picture's size is worked out from it
  readonly property real slotW: blk.editor ? Math.floor((blk.editor.columnW - blk.editor.rowGap * (blk.share.n - 1)) / blk.share.n) : 600
  // ALIGNED (the row's first block says how — BlockEditor.rowAlign): the
  // row's pictures packed together, each as wide as it is drawn, and the
  // editor places the group; along the left, the even slots as before
  readonly property bool isMedia: blk.kind === "image" || blk.kind === "sketch" || blk.kind === "file"
  readonly property string rowAlign: blk.isMedia && blk.editor ? blk.editor.rowAlign(blk.key) : ""
  readonly property real contentW: blk.kind === "file" ? fileChip.width : media.width
  width: blk.isMedia && blk.rowAlign !== "" ? blk.contentW + blk.indentW : blk.slotW
  x: blk.isMedia && blk.rowAlign !== "" && blk.editor ? blk.editor.rowX(blk.key)
     : blk.share.slot * (blk.slotW + (blk.editor ? blk.editor.rowGap : 0))
  onHeightChanged: if (blk.editor) blk.editor.relayout()
  onVisibleChanged: if (blk.editor) Qt.callLater(blk.editor.relayout)
  // the one being carried somewhere else in the note
  opacity: !!blk.editor && blk.editor.dragKey === blk.key ? 0.4 : 1
  height: blk.folded ? 0 : body.height + blk.padTop + blk.padBottom
  visible: !blk.folded
  readonly property real padTop: blk.kind === "title" ? 4 : blk.kind === "heading" ? 14 : blk.kind === "subheading" ? 10
    : blk.kind === "image" || blk.kind === "sketch" || blk.kind === "table" || blk.kind === "mono" ? 8 : 2
  readonly property real padBottom: blk.kind === "image" || blk.kind === "sketch" || blk.kind === "table" || blk.kind === "mono" || blk.kind === "title" ? 8 : 2

  // ── WHAT THE OVERLAY ASKS ──────────────────────────────────────────────
  // A press at (x, y) in the block: a control under it answers ({ act }), or
  // null for the words (the editor places the caret).
  function control(x, y) {
    if (blk.kind === "check" && x >= blk.indentW && x < blk.indentW + blk.markW && y < blk.padTop + text.firstLineH + 4)
      return { act: "check" };
    if (N.isHeading(blk.b) && x < 0 && x > -30 && blk.editor.canFold(blk.key)) return { act: "fold" };
    if (blk.kind === "image" || blk.kind === "sketch") {
      const r = media.mapToItem(blk, 0, 0);
      if (x >= r.x + media.width - 22 && x <= r.x + media.width + 4 && y >= r.y + media.height - 22 && y <= r.y + media.height + 4)
        return { act: "resize" };
      if (x >= r.x && x <= r.x + media.width && y >= r.y && y <= r.y + media.height) return { act: "media" };
      return { act: "beside" };
    }
    if (blk.kind === "file") return { act: x >= fileChip.x && x <= fileChip.x + fileChip.width ? "file" : "beside" };
    if (blk.kind === "rule") return { act: "media" };
    // a table is carried by the grip in the margin beside it
    if (blk.kind === "table" && x < -4 && x > -30 && y < 36) return { act: "grip" };
    if (blk.kind === "table") return tableLoader.item ? tableLoader.item.control(x - tableLoader.x, y - tableLoader.y) : null;
    if (blk.isText) {
      const p = blk.textPoint(x, y);
      const link = text.linkAt(p.x, p.y);
      if (link !== "" && p.x <= text.contentWidth + 2) return { act: "link", href: link };
    }
    return null;
  }
  function cursorAt(x, y) {
    const c = blk.control(x, y);
    if (!c) return blk.isText ? Qt.IBeamCursor : Qt.ArrowCursor;
    if (c.act === "resize") return Qt.SizeFDiagCursor;
    if (c.act === "cell") return Qt.IBeamCursor;
    if (c.act === "grip") return Qt.OpenHandCursor;
    // a hand for a web link only (user, 2026-10-19); a link to a note, a
    // tick, a fold or a picture is a control, under the plain arrow
    if (c.act === "link" && /^https?:\/\//i.test(String(c.href || ""))) return Qt.PointingHandCursor;
    return Qt.ArrowCursor;
  }
  // where (x, y) in the block is, in the TextEdit
  // ── SPELLING ── its marks (SpellMarks, a child of the text)
  function spellAt(pos) { return spell.at(pos); }
  function textPoint(x, y) { return Qt.point(x - text.x, y - body.y - text.y); }
  function posAt(x, y) {
    const p = blk.textPoint(x, y);
    if (p.y < 0) return 0;
    if (p.y > text.height) return text.length;
    return text.positionAt(p.x, p.y);
  }

  // ── THE TEXT, KEPT IN STEP ─────────────────────────────────────────────
  // `shown`: the stored run this TextEdit was last given or last wrote.
  property string shown: ""
  property bool syncing: false
  function load() {
    if (!blk.b || !blk.isText) return;
    // THE LIVE BLOCK, NOT `b`: `b` is a copy taken at the last structural
    // change (editor.rev), and typing since only reaches the editor's own
    // block — so a repaint read from it put the text back as it was
    // (user, 2026-10-15: applying a background undid the last edit)
    const live = blk.editor ? blk.editor.blockOf(blk.key) : null;
    const want = (live ? live.h : blk.b.h) || "";
    if (want === blk.shown && text.length >= 0 && blk._loaded) return;
    blk.syncing = true;
    text.text = blk.kind === "mono" ? want : blk.editor.display(want);
    blk.syncing = false;
    blk.shown = want;
    blk._loaded = true;
  }
  property bool _loaded: false
  onBChanged: Qt.callLater(blk.load)
  Component.onCompleted: blk.load()
  // the theme changed: colors by name are painted again
  Connections {
    target: Zenon
    function onThemeEpochChanged() {
      if (!blk.isText || blk.kind === "mono") return;
      // typing not yet read back is read first, so it is not painted over
      if (blk.editor) blk.editor.flushTyping();
      blk._loaded = false;
      blk.load();
    }
  }

  readonly property real textX: blk.indentW + blk.markW + (blk.kind === "mono" ? 14 : 0)

  // ── THE MARKER ─────────────────────────────────────────────────────────
  Item {
    id: marker
    x: blk.indentW
    y: blk.padTop
    width: blk.markW
    height: text.firstLineH
    visible: blk.isList
    // a checkbox: a ring, filled and ticked when done (Apple's)
    Rectangle {
      visible: blk.kind === "check"
      anchors.verticalCenter: parent.verticalCenter
      x: 3
      // the ring a little under the line's cap height (user, 2026-10-14:
      // at 1.1 × the text it stood taller than the words beside it)
      width: Math.round(blk.ts * 0.86)
      height: width
      radius: width / 2
      color: blk.b && blk.b.c ? Zenon.yellow : "transparent"
      border.width: blk.b && blk.b.c ? 0 : 1.5
      border.color: Zenon.muted
      Behavior on color { ColorAnimation { duration: Zenon.fast } }
      Text {
        anchors.centerIn: parent
        visible: !!blk.b && !!blk.b.c
        text: ""
        color: Zenon.onAccent
        font.family: Zenon.glyphFace
        font.pixelSize: Math.round(blk.ts * 0.5)
      }
    }
    Text {
      visible: blk.kind === "bullet" || blk.kind === "dash" || blk.kind === "number"
      anchors.verticalCenter: parent.verticalCenter
      anchors.right: parent.right
      anchors.rightMargin: 8
      text: blk.kind === "bullet" ? (blk.level % 2 === 0 ? "•" : "◦")
        : blk.kind === "dash" ? "–"
        : (blk.editor ? blk.editor.numberOf(blk.index) : 1) + "."
      color: blk.kind === "number" ? Zenon.ink : Zenon.muted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: blk.ts
      font.features: { "tnum": 1 }
    }
  }
  // a quote's bar
  Rectangle {
    visible: blk.kind === "quote"
    x: blk.indentW + 6
    y: blk.padTop + 2
    width: 3
    radius: 1.5
    height: Math.max(4, text.height - 4)
    color: Zenon.alpha(Zenon.muted, 0.7)
  }
  // a heading's fold, in the margin — shown on hover, or while folded
  Text {
    visible: N.isHeading(blk.b) && !!blk.editor && blk.editor.canFold(blk.key)
             && (blk.b.fold || blk.editor.hoverKey === blk.key)
    x: -24
    y: blk.padTop + (text.firstLineH - height) / 2
    text: blk.b && blk.b.fold ? "" : ""
    color: blk.b && blk.b.fold ? Zenon.cyan : Zenon.muted
    font.family: Zenon.glyphFace
    font.pixelSize: Zenon.px(11)
  }

  // ── THE BODY ───────────────────────────────────────────────────────────
  Item {
    id: body
    y: blk.padTop
    width: parent.width
    height: blk.isText ? text.height + (dueLine.visible ? dueLine.height : 0)
      : blk.kind === "rule" ? 18
      : blk.kind === "file" ? fileChip.height
      : blk.kind === "table" ? (tableLoader.item ? tableLoader.item.height : 40)
      : media.height + (caption.visible ? caption.height + 4 : 0)

    // a checklist item's reminder, under its words: red once it is past
    Text {
      id: dueLine
      visible: blk.kind === "check" && !!blk.b && !!blk.b.due
      x: blk.textX
      y: text.height
      height: visible ? implicitHeight + 2 : 0
      readonly property bool late: visible && !blk.b.c && blk.b.due <= Date.now()
      text: visible ? "\u{F009F}  " + N.dueText(blk.b.due, Date.now()) : ""
      color: dueLine.late ? Zenon.red : blk.b && blk.b.c ? Zenon.muted : Zenon.yellow
      font.family: Zenon.face
      font.weight: Font.DemiBold
      font.pixelSize: Math.round(blk.ts * 0.78)
    }

    // a code block's panel
    Rectangle {
      visible: blk.kind === "mono"
      x: blk.indentW
      width: parent.width - blk.indentW
      height: text.height
      radius: Zenon.windowRadius
      color: Zenon.wash(0.05)
      border.width: 1
      border.color: Zenon.border
    }

    TextEdit {
      palette.link: Zenon.link   // the theme's, not the system's blue
      id: text
      visible: blk.isText
      x: blk.textX
      y: blk.kind === "mono" ? 0 : 0
      width: Math.max(10, parent.width - x - (blk.kind === "mono" ? 14 : 0))
      topPadding: blk.kind === "mono" ? 10 : 0
      bottomPadding: blk.kind === "mono" ? 10 : 0
      textFormat: blk.kind === "mono" ? TextEdit.PlainText : TextEdit.RichText
      wrapMode: TextEdit.Wrap
      // a block's alignment; left alone, Qt sets a right-to-left script
      // along the right by itself
      horizontalAlignment: !blk.b || !blk.b.align ? TextEdit.AlignLeft
        : blk.b.align === "center" ? TextEdit.AlignHCenter : blk.b.align === "right" ? TextEdit.AlignRight : TextEdit.AlignJustify
      readOnly: !blk.editor || blk.editor.readOnly
      selectByMouse: false
      activeFocusOnPress: false
      persistentSelection: true
      color: blk.b && blk.b.k === "check" && blk.b.c ? Zenon.muted : blk.kind === "quote" ? Zenon.soft : Zenon.ink
      // while finding, the match is marked yellow, as Apple's find marks it
      selectionColor: blk.editor && blk.editor.findQuery !== "" ? Zenon.alpha(Zenon.yellow, 0.5) : Zenon.alpha(Zenon.cyan, 0.32)
      selectedTextColor: color
      font.family: blk.kind === "mono" ? Zenon.faceMono : (blk.editor ? blk.editor.face : Zenon.face)
      font.weight: blk.kind === "title" || blk.kind === "heading" ? Font.Bold
        : blk.kind === "subheading" ? Font.DemiBold : Zenon.weight
      font.pixelSize: Math.round(blk.ts * (blk.kind === "title" ? 1.75 : blk.kind === "heading" ? 1.4
        : blk.kind === "subheading" ? 1.15 : blk.kind === "mono" ? 0.88 : 1))
      font.italic: false
      cursorDelegate: Caret { field: text; thick: 3; low: 0.45; steady: true }
      readonly property real firstLineH: {
        void [text.font.pixelSize, text.length];
        const r = text.positionToRectangle(0);
        return Math.max(r.height, text.font.pixelSize * 1.3);
      }

      onTextChanged: {
        if (blk.syncing || !blk.editor || !blk.isText) return;
        blk.editor.typed(blk.key, blk);
      }
      // a squiggle under each wrong word
      SpellMarks {
        id: spell
        field: text
        mgr: blk.editor ? blk.editor.mgr : null
        active: blk.isText && blk.kind !== "mono" && !!blk.editor && !blk.editor.readOnly
      }
      onActiveFocusChanged: {
        if (activeFocus && blk.editor) blk.editor.focused(blk.key);
      }
      onCursorPositionChanged: {
        if (activeFocus && blk.editor) blk.editor.caretMoved(blk.key, blk);
      }
      Keys.onPressed: (e) => { if (blk.editor && blk.editor.key(blk.key, blk, e)) e.accepted = true; }
    }
    // Math Notes' answer, ghosted after the "=" until taken (tab)
    Text {
      visible: !!blk.editor && blk.editor.ghostKey === blk.key && blk.editor.ghost !== ""
      x: text.x + text.positionToRectangle(text.length).x + 4
      y: text.y + text.positionToRectangle(text.length).y
      text: blk.editor ? blk.editor.ghost : ""
      color: Zenon.alpha(Zenon.yellow, 0.75)
      font: text.font
    }

    // a picture or a sketch
    ClippingRectangle {
      id: media
      visible: blk.kind === "image" || blk.kind === "sketch"
      x: blk.indentW
      readonly property real room: Math.max(80, blk.slotW - blk.indentW)
      // a sketch with its strokes is drawn from them (so in this theme's
      // colors); its saved picture is only for exports and thumbnails
      readonly property bool drawn: blk.kind === "sketch" && !!blk.b && !!blk.b.strokes
      readonly property real natural: media.drawn ? room : pic.implicitWidth > 0 ? pic.implicitWidth : room
      width: visible ? Math.round(Math.min(room * (blk.b && blk.b.w ? blk.b.w : 1), Math.max(60, natural))) : 0
      height: !visible ? 0 : media.drawn ? Math.round(width * (blk.b.aspect || 0.6))
        : pic.implicitWidth > 0 ? Math.round(width * pic.implicitHeight / pic.implicitWidth) : 140
      // a picture that USES transparency is not rounded (user, 2026-10-15):
      // its shape is its own, and a corner cut off a cut-out reads as damage.
      // Asked of the picture itself (ClioManager.askClear), not its type; a
      // photograph and a sketch's card keep theirs.
      readonly property string file: blk.kind === "image" && blk.b && blk.b.src && blk.editor
        ? blk.editor.base + "/" + blk.b.src + (blk.b.v ? "?v=" + blk.b.v : "") : ""
      readonly property var mgr: blk.editor ? blk.editor.mgr : null
      // read here, asked for below: a binding that queued the question
      // looped on its own answer
      readonly property bool seeThrough: !!media.mgr && media.file !== "" && media.mgr.clear[media.file] === true
      function askClear() { if (media.mgr && media.file !== "") media.mgr.askClear(media.file); }
      onFileChanged: media.askClear()
      onMgrChanged: media.askClear()
      Component.onCompleted: media.askClear()
      radius: media.seeThrough ? 0 : 8
      color: blk.kind === "sketch" ? Zenon.wash(0.04) : "transparent"
      Image {
        id: pic
        anchors.fill: parent
        visible: !media.drawn
        source: media.drawn ? "" : (blk.kind === "image" || blk.kind === "sketch") && blk.b && blk.b.src && blk.editor
          ? "file://" + blk.editor.base + "/" + blk.b.src + (blk.b.v ? "?v=" + blk.b.v : "") : ""
        sourceSize.width: 1600
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: false
        smooth: true
        mipmap: true
      }
      Canvas {
        id: strokes
        anchors.fill: parent
        visible: media.drawn
        onWidthChanged: requestPaint()
        onPaint: {
          const c = getContext("2d");
          c.reset();
          if (media.drawn) N.paintStrokes(c, blk.b.strokes, width, (n) => String(Zenon[n] || Zenon.ink));
        }
        Connections { target: blk; function onBChanged() { if (media.drawn) strokes.requestPaint(); } }
        Connections { target: Zenon; function onThemeEpochChanged() { strokes.requestPaint(); } }
      }
      Working { anchors.centerIn: parent; running: pic.status === Image.Loading && !media.drawn; visible: running }
      Text {
        anchors.centerIn: parent
        visible: pic.status === Image.Error && !media.drawn
        text: "  missing picture"
        color: Zenon.muted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
      }
      // held: chosen, for delete / copy / open
      Rectangle {
        anchors.fill: parent
        color: "transparent"
        radius: media.radius
        border.width: blk.mediaHeld ? 3 : 0
        border.color: Zenon.alpha(Zenon.cyan, 0.8)
      }
      // the corner to pull
      Rectangle {
        visible: blk.mediaHeld || (!!blk.editor && blk.editor.hoverKey === blk.key)
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 5
        width: 14
        height: 14
        radius: Zenon.radiusControl
        color: Zenon.hud(0.8)
        border.width: 1
        border.color: Zenon.border
      }
    }
    Text {
      id: caption
      visible: blk.kind === "sketch"
      anchors.top: media.bottom
      anchors.topMargin: 4
      x: media.x
      text: "\u{F03EB}  Sketch · double-click to draw"
      color: Zenon.muted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(12)
    }

    // a file: its glyph, its name, its size — opened on a click
    Rectangle {
      id: fileChip
      visible: blk.kind === "file"
      x: blk.indentW
      width: visible ? Math.min(blk.slotW - blk.indentW, fileRow.implicitWidth + 28) : 0
      height: 54
      radius: Zenon.windowRadius
      color: Zenon.wash(0.05)
      border.width: blk.mediaHeld ? 2 : 1
      border.color: blk.mediaHeld ? Zenon.alpha(Zenon.cyan, 0.8) : Zenon.border
      Row {
        id: fileRow
        x: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: blk.b ? (Icons.glyphFor({ name: blk.b.name || "" }) || "") : ""
          color: Zenon.cyan
          font.family: Zenon.glyphFace
          font.pixelSize: Zenon.px(22)
        }
        Column {
          anchors.verticalCenter: parent.verticalCenter
          Text {
            text: blk.b ? blk.b.name || "file" : ""
            color: Zenon.ink
            elide: Text.ElideMiddle
            width: Math.min(implicitWidth, Math.max(120, blk.width - 160))
            font.family: Zenon.face
            font.weight: Font.DemiBold
            font.pixelSize: Zenon.px(14)
          }
          Text {
            text: blk.b ? N.sizeText(blk.b.size) : ""
            color: Zenon.muted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(12)
          }
        }
      }
    }

    // a divider
    Rectangle {
      visible: blk.kind === "rule"
      x: blk.indentW
      y: 8
      width: parent.width - blk.indentW
      height: blk.mediaHeld ? 3 : 1
      color: blk.mediaHeld ? Zenon.cyan : Zenon.border
    }

    // a table: the grip it is carried by, in the margin
    Text {
      visible: blk.kind === "table" && !!blk.editor && !blk.editor.readOnly
        && (blk.editor.hoverKey === blk.key || blk.mediaHeld || blk.editor.dragKey === blk.key)
      x: -26
      y: 8
      text: "\u{F01DD}"
      color: blk.mediaHeld ? Zenon.cyan : Zenon.muted
      font.family: Zenon.glyphFace
      font.pixelSize: Zenon.px(16)
    }
    Loader {
      id: tableLoader
      x: blk.indentW
      active: blk.kind === "table"
      sourceComponent: Component {
        TableBlock {
          editor: blk.editor
          block: blk
          width: Math.max(120, body.width - blk.indentW)
        }
      }
    }
  }

  // ── THE TEXT'S OWN WORK, ASKED BY THE EDITOR ───────────────────────────
  function range(a, b) {
    if (blk.kind === "mono") return N.escape(text.getText(a, b));
    return N.inline(text.getFormattedText(a, b));
  }
  // (a paragraph separator by its code: written into a regex literal,
  // QML lexes it as a line break)
  function plainRange(a, b) { return text.getText(a, b).split(String.fromCharCode(0x2029)).join("\n"); }
  // set the shown text from the data at once (a merge, a split)
  function reload() { blk._loaded = false; blk.load(); }
  function table() { return tableLoader.item; }
}

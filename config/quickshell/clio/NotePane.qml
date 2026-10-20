// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE NOTE, OPEN — its toolbar (Apple's: Aa for formats, a checklist, a
// table, things to put in, colors, the lock, sharing), then the editor;
// a journal entry with its date, mood and bookmark over its words; a
// locked note as its lock until the password is given; find (ctrl+f) as a
// bar under the toolbar.
//
// What is typed is the editor's until it is committed: a beat after the
// last change, and at once when another note is chosen or the window goes.

import QtQuick
import Quickshell
import Quickshell.Io
import "../morpheus"
import "../terminus"
import "notes.js" as N

Item {
  id: pane
  property var win: null
  readonly property var mgr: pane.win ? pane.win.mgr : null
  readonly property alias editor: ed

  // the note shown: its id, and the note as the notebook has it now
  property string noteId: ""
  readonly property var note: {
    if (!pane.mgr || pane.noteId === "") return null;
    void pane.mgr.notes;
    void pane.mgr.stickies;
    return pane.noteId.startsWith("s:") ? pane.mgr.stickyOf(pane.noteId) : pane.mgr.noteOf(pane.noteId);
  }
  readonly property bool isEntry: !!pane.note && pane.note.kind === "entry"
  readonly property bool isSticky: !!pane.note && pane.note.kind === "sticky"
  // its words are not here yet: locked, or its journal is
  readonly property bool locked: !!pane.note && (pane.note.sealed && !pane.mgr.opened[pane.note.id]
    || pane.isEntry && pane.win.journalLocked(pane.note.journal))
  readonly property bool editing: ed.activeFocusInside
  property bool loadedOne: false

  function show(n) {
    pane.commit();
    pane.closeFind(true);
    pane.noteId = n ? n.id : "";
    pane.loadedOne = false;
    if (!n) { ed.load([]); return; }
    if (n.sealed && !pane.mgr.opened[n.id]) return;
    if (pane.isEntry && pane.win.journalLocked(n.journal)) return;
    const bs = pane.mgr.blocksOf(n);
    if (n.sealed && !bs) return;
    ed.load(bs || []);
    pane.loadedOne = true;
  }
  // the note opened once the password has been given
  function unlockHere() {
    const n = pane.note;
    if (!n) return;
    pane.win.withPassword(() => {
      if (!n.sealed) { pane.show(n); return; }
      pane.mgr.unseal(n.id, (ok, bs, err) => {
        if (!ok) { pane.win.say(err ? err.error : "Could not open it", true); return; }
        pane.show(pane.mgr.noteOf(n.id));
      });
    });
  }
  Connections {
    target: pane.mgr
    // locked again from elsewhere (Lock Now, the timer): put away
    function onUnlockedChanged() { if (!pane.mgr.unlocked && pane.note && (pane.note.sealed || pane.isEntry)) pane.show(pane.note); }
  }

  property bool dirty: false
  Connections {
    target: ed
    function onEdited() { pane.dirty = true; saveTimer.restart(); pane.mgr.touchLock(); }
  }
  Timer { id: saveTimer; interval: 700; onTriggered: pane.commit() }
  function commit() {
    saveTimer.stop();
    if (!pane.dirty || !pane.note || !pane.loadedOne) { pane.dirty = false; return; }
    pane.dirty = false;
    const bs = ed.stored();
    if (pane.isSticky) pane.mgr.setStickyBlocks(pane.noteId, bs);
    else pane.mgr.setBlocks(pane.noteId, bs);
  }
  function focusEditor(start) {
    if (!pane.note || pane.locked || !pane.loadedOne) { pane.win.refocus(); return; }
    ed.focusEnd(start);
  }
  function copyAll() { ed.copyAll(); }

  // ── THE TOOLBAR ────────────────────────────────────────────────────────
  Item {
    id: head
    width: parent.width
    height: pane.win ? pane.win.headH : 50
    z: 5
    Rectangle { anchors.fill: parent; color: Zenon.headBg }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Zenon.border }

    // a note in the Trash says so, or the sticky's colors (where a note
    // lives is not said here: its row in the list says it — user, 2026-10-14)
    Text {
      x: 18
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(0, tools.x - 30)
      elide: Text.ElideRight
      visible: !pane.isSticky && !!pane.note && pane.note.deleted
      text: "In the Trash · restore it to edit"
      color: pane.note && pane.note.deleted ? Zenon.red : Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
    }
    Row {
      id: swatches
      x: 16
      anchors.verticalCenter: parent.verticalCenter
      spacing: 6
      visible: pane.isSticky
      Repeater {
        model: ["sand", "yellow", "green", "cyan", "blue", "magenta", "pink"]
        delegate: Rectangle {
          required property string modelData
          width: 18
          height: 18
          radius: height / 2
          color: Clio.ink(modelData)
          border.width: pane.note && pane.note.hue === modelData ? 2 : 0
          border.color: Zenon.ink
          MouseArea { anchors.fill: parent; onClicked: Clio.set(pane.note.sticky, "hue", modelData) }
        }
      }
    }

    // centered on the note (user, 2026-10-14), the format bar under it too
    Row {
      id: tools
      // (never over a sticky's colors, nor off the pane's left edge)
      x: Math.max(swatches.visible ? swatches.x + swatches.width + 14 : 12, Math.round((parent.width - width) / 2))
      anchors.verticalCenter: parent.verticalCenter
      spacing: 4
      visible: !!pane.note && !pane.locked
      readonly property bool writable: !!pane.note && !pane.note.deleted
      ClioTool {
        id: aaTool
        pane: pane
        word: "Aa"
        tip: pane.formatPinned ? "Formats — click to put away" : "Formats — click to keep them up"
        lit: pane.formatPinned
        litInk: Zenon.cyan
        enabled: tools.writable
        onHoveredChanged: pane.formatHover()
        onPressed: {
          pane.formatPinned = !pane.formatPinned;
          // put away by the click: gone now, though the pointer is still on Aa
          if (!pane.formatPinned) { pane.formatHush = true; formatLeave.stop(); pane.formatShown = false; }
        }
      }
      ClioTool { pane: pane; glyph: "\uF0CA"; tip: "Outline — the note's headings"; menu: true; onPressed: (x, y) => pane.outlineMenu(x, y) }
      ClioTool { pane: pane; glyph: "\u{F0C52}"; tip: "Checklist"; keys: "ctrl shift l"; enabled: tools.writable; onPressed: ed.setKind("check") }
      ClioTool { pane: pane; glyph: ""; tip: "Table"; keys: "ctrl alt t"; enabled: tools.writable; onPressed: ed.insertTable() }
      ClioTool { pane: pane; glyph: ""; tip: "Put in…"; menu: true; enabled: tools.writable; onPressed: (x, y) => pane.attachMenu(x, y) }
      ClioTool {
        id: trayTool
        pane: pane
        glyph: "\u{F02F9}"
        tip: pane.trayOpen ? "" : "Pictures and files to use again"
        lit: pane.trayOpen
        enabled: tools.writable && !pane.isSticky
        onPressed: pane.trayOpen = !pane.trayOpen
      }
      ClioTool { pane: pane; glyph: "\u{F03EB}"; tip: "Sketch"; enabled: tools.writable && !pane.isSticky; onPressed: pane.win.sketch(null) }
      ClioTool { pane: pane; glyph: ""; tip: "Link"; keys: "ctrl k"; enabled: tools.writable; onPressed: pane.askLink() }
      // spelling, on or off for every note (on by default; user, 2026-10-17)
      ClioTool {
        pane: pane
        glyph: "\u{F04C6}"
        tip: pane.mgr && pane.mgr.spellOn ? "Spelling is checked — click to stop" : "Check spelling"
        lit: !!pane.mgr && pane.mgr.spellOn
        litInk: Zenon.cyan
        onPressed: pane.mgr.setSpellOn(!pane.mgr.spellOn)
      }
      ClioTool { pane: pane; glyph: "\u{F03D8}"; tip: "Color and highlight"; menu: true; enabled: tools.writable; onPressed: (x, y) => pane.inkMenu(x, y) }
      Item { width: 8; height: 1 }
      ClioTool {
        pane: pane
        visible: !pane.isSticky
        glyph: pane.note && pane.note.sealed ? "" : ""
        tip: pane.note && pane.note.sealed ? "Locked — opened until Lock Now" : "Lock this note"
        lit: !!pane.note && !!pane.note.sealed
        menu: true
        onPressed: (x, y) => pane.lockMenu(x, y)
      }
      ClioTool { pane: pane; glyph: ""; tip: "Share and export"; menu: true; visible: !pane.isSticky; onPressed: (x, y) => pane.shareMenu(x, y) }
      ClioTool { pane: pane; glyph: ""; tip: "More"; menu: true; onPressed: (x, y) => pane.win.noteMenu(pane.note, x, y) }
    }
  }

  // ── FIND ───────────────────────────────────────────────────────────────
  property bool finding: false
  readonly property real findH: findBar.height
  function openFind() {
    if (!pane.note || pane.locked) return;
    ed.flashing = false;
    pane.finding = true;
    const sel = ed.selectedText();
    if (sel !== "" && sel.indexOf("\n") < 0) findField.text = sel;
    findField.forceActiveFocus();
    findField.selectAll();
    ed.find(findField.text);
  }
  // `quiet`: another note is coming in — nothing focused, only put away
  function closeFind(quiet) {
    if (!pane.finding) return;
    pane.finding = false;
    if (quiet) { ed.find(""); return; }
    if (!ed.endFind()) pane.focusEditor(false);
  }
  // ── THE FORMAT BAR ─────────────────────────────────────────────────────
  // Every format at once, in a second bar under the toolbar: shown while
  // the pointer is on Aa (or on the bar), kept up by a click on Aa. The
  // note slides down to make room and goes under it frosted, as under the
  // head (user, 2026-10-14). Its buttons never take the keyboard: the
  // caret and the selection stay where they were.
  property bool formatPinned: false
  property bool formatShown: false
  readonly property bool formatUp: (pane.formatShown || pane.formatPinned) && !!pane.note && !pane.locked && !pane.note.deleted
  // a click put it away: the hover does not bring it back until the
  // pointer has left Aa (and the bar) once
  property bool formatHush: false
  // the pointer on the bar (see fmtRoom: why there is no Flickable)
  // (the handler itself, not formatBar.hovered: its own hoveredChanged
  // ran before that binding caught up, read "still on the bar", and the
  // bar never went — user, 2026-10-14)
  function barHovered() { return formatBar.handler.hovered; }
  // decided once every hover that changed with this move has changed
  function formatHover() { Qt.callLater(pane.formatSettle); }
  function formatSettle() {
    if (aaTool.hovered || pane.barHovered()) {
      if (pane.formatHush) return;
      formatLeave.stop();
      pane.formatShown = true;
    } else {
      pane.formatHush = false;
      formatLeave.restart();
    }
  }
  Timer { id: formatLeave; interval: 380; onTriggered: if (!aaTool.hovered && !pane.barHovered()) pane.formatShown = false }
  // the kind of block the caret is in, lit on the bar
  readonly property string alignHere: ed.alignHere()
  // the marks on the words in hand (the caret's, or the selection's), lit
  // on the bar; a heading's own weight is not "bold" (TextEdit's
  // cursorSelection, Qt 6.7)
  readonly property var marksHere: {
    void ed.cursorKey; void ed.rev;
    const it = ed.current();
    if (!it || !it.isText || !it.te || !it.te.cursorSelection) return ({});
    void it.te.cursorPosition; void it.te.selectionStart; void it.te.selectionEnd; void it.te.length;
    const f = it.te.cursorSelection.font;
    return { b: f.weight >= Font.Bold && it.te.font.weight < Font.DemiBold, i: f.italic, u: f.underline, s: f.strikeout };
  }
  // the face the words in hand wear, when it is one chosen for them ("" for
  // the note's own)
  readonly property string faceHere: {
    void ed.cursorKey; void ed.rev;
    const it = ed.current();
    if (!it || !it.isText || !it.te || !it.te.cursorSelection) return "";
    void it.te.cursorPosition; void it.te.selectionStart; void it.te.selectionEnd; void it.te.length;
    const f = it.te.cursorSelection.font.family;
    return f && f !== it.te.font.family ? f : "";
  }
  // Alexandria opened for the words in hand (user, 2026-10-17: "change the
  // font of one word while retaining a different font for the rest")
  function chooseRunFace() {
    if (!pane.mgr.fontBook || pane.inMono) return;
    pane.mgr.fontBook.pick({ title: "Font for these words", family: pane.faceHere || pane.mgr.faceFor(pane.isEntry), weight: 400 },
                           (family) => { ed.runFace(family === pane.mgr.faceFor(pane.isEntry) ? "" : family); pane.focusEditor(false); });
  }
  readonly property string kindHere: { void ed.cursorKey; void ed.rev; const it = ed.current(); return it ? it.kind : ""; }
  // the caret (or every line chosen) in a Monostyled block: plain text,
  // so marks, alignment and clearing do nothing there — dimmed on the bar
  readonly property bool inMono: {
    void ed.cursorKey; void ed.rev; void ed.cross;
    const ts = ed.targets();
    return ts.length > 0 && ts.every((x) => ed.blocks[x] && ed.blocks[x].k === "mono");
  }
  Rectangle {
    id: formatBar
    readonly property var handler: barHover
    // the pane, as its buttons are handed it: `pane: pane` in a delegate
    // binds ClioTool's own `pane` to itself (null) — the side: side trap
    readonly property Item host: pane
    anchors.top: head.bottom
    width: parent.width
    height: pane.formatUp ? 46 : 0
    clip: true
    // over the note below it
    z: 4.5
    // the head's own ground: the note frosted under it, as under the head
    color: Zenon.headBg
    Behavior on height { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Zenon.border }
    HoverHandler { id: barHover; onHoveredChanged: pane.formatHover() }
    // (no Flickable: it filtered the pointer, and the hover over the
    // buttons went stale — the bar jumped, then would not go. A pane too
    // narrow for every format gets the row a little smaller instead.)
    Item {
      id: fmtRoom
      anchors.fill: parent
      anchors.leftMargin: 4
      anchors.rightMargin: 4
      Row {
        id: fmtRow
        // centered, under the toolbar it opens from
        readonly property real fit: Math.min(1, fmtRoom.width / Math.max(1, width))
        scale: fit
        transformOrigin: Item.Center
        x: Math.round((fmtRoom.width - width) / 2)
        height: parent.height
        spacing: 0
        // the paragraph styles, each named in its own weight
        Repeater {
          model: [["title", "Title", "ctrl shift t", Font.Bold], ["heading", "Heading", "ctrl shift h", Font.Bold],
                  ["subheading", "Subheading", "ctrl shift j", Font.DemiBold], ["body", "Body", "ctrl shift b", Font.Normal],
                  ["mono", "Mono", "ctrl shift m", Font.Normal]]
          delegate: ClioTool {
            required property var modelData
            anchors.verticalCenter: parent.verticalCenter
            pane: formatBar.host
            onHoveredChanged: formatBar.host.formatHover()
            size: 26
            word: modelData[1]
            wordPx: Zenon.px(12)
            pad: 10
            wordWeight: modelData[3]
            litInk: Zenon.cyan
            lit: pane.kindHere === modelData[0]
            tip: N.KINDS[modelData[0]].label
            keys: modelData[2]
            onPressed: ed.setKind(modelData[0])
          }
        }
        Item { width: 21; height: parent.height; Rectangle { anchors.centerIn: parent; width: 1; height: 18; color: Zenon.border } }
        // lists and the quote
        Repeater {
          model: [["bullet", "ctrl shift 7"], ["dash", "ctrl shift 8"], ["number", "ctrl shift 9"], ["check", "ctrl shift l"], ["quote", ""]]
          delegate: ClioTool {
            required property var modelData
            anchors.verticalCenter: parent.verticalCenter
            pane: formatBar.host
            onHoveredChanged: formatBar.host.formatHover()
            size: 26
            glyph: N.KINDS[modelData[0]].glyph
            litInk: Zenon.cyan
            lit: pane.kindHere === modelData[0]
            tip: N.KINDS[modelData[0]].label
            keys: modelData[1]
            onPressed: ed.setKind(modelData[0])
          }
        }
        Item { width: 21; height: parent.height; Rectangle { anchors.centerIn: parent; width: 1; height: 18; color: Zenon.border } }
        // how the lines sit
        Repeater {
          model: [["", "\uF036", "Along the left"], ["center", "\uF037", "Centered"], ["right", "\uF038", "Along the right"], ["justify", "\uF039", "Justified"]]
          delegate: ClioTool {
            required property var modelData
            anchors.verticalCenter: parent.verticalCenter
            pane: formatBar.host
            onHoveredChanged: formatBar.host.formatHover()
            size: 26
            glyph: modelData[1]
            litInk: Zenon.cyan
            enabled: !pane.inMono
            lit: enabled && (pane.kindHere !== "" || ed.mediaSel !== "") && pane.alignHere === modelData[0]
            tip: modelData[2]
            onPressed: ed.setAlign(modelData[0])
          }
        }
        Item { width: 21; height: parent.height; Rectangle { anchors.centerIn: parent; width: 1; height: 18; color: Zenon.border } }
        // the marks on the words chosen
        Repeater {
          model: [["b", "", "Bold", "ctrl b"], ["i", "", "Italic", "ctrl i"], ["u", "", "Underline", "ctrl u"], ["s", "", "Strikethrough", "ctrl shift x"]]
          delegate: ClioTool {
            required property var modelData
            anchors.verticalCenter: parent.verticalCenter
            pane: formatBar.host
            onHoveredChanged: formatBar.host.formatHover()
            size: 26
            glyph: modelData[1]
            litInk: Zenon.cyan
            enabled: !pane.inMono
            lit: enabled && !!pane.marksHere[modelData[0]]
            tip: modelData[2]
            keys: modelData[3]
            onPressed: ed.mark(modelData[0])
          }
        }
        Item { width: 21; height: parent.height; Rectangle { anchors.centerIn: parent; width: 1; height: 18; color: Zenon.border } }
        ClioTool { anchors.verticalCenter: parent.verticalCenter; pane: formatBar.host; onHoveredChanged: formatBar.host.formatHover(); size: 26; glyph: ""; tip: "Outdent"; keys: "shift tab"; onPressed: ed.indent(-1) }
        ClioTool { anchors.verticalCenter: parent.verticalCenter; pane: formatBar.host; onHoveredChanged: formatBar.host.formatHover(); size: 26; glyph: ""; tip: "Indent"; keys: "tab"; onPressed: ed.indent(1) }
        Item { width: 21; height: parent.height; Rectangle { anchors.centerIn: parent; width: 1; height: 18; color: Zenon.border } }
        // the words' own typeface: its name on the bar when one is chosen
        ClioTool {
          anchors.verticalCenter: parent.verticalCenter
          visible: !!pane.mgr.fontBook && !pane.isSticky
          pane: formatBar.host
          onHoveredChanged: formatBar.host.formatHover()
          size: 26
          pad: 14
          word: pane.faceHere !== "" ? pane.faceHere : "Font"
          wordPx: Zenon.px(13)
          wordWeight: Font.DemiBold
          lit: pane.faceHere !== ""
          litInk: Zenon.cyan
          tip: pane.faceHere !== "" ? "Font for these words — right click for the note's own" : "Font for these words"
          enabled: !pane.inMono
          onPressed: pane.chooseRunFace()
          MouseArea { anchors.fill: parent; acceptedButtons: Qt.RightButton; onClicked: ed.runFace("") }
        }
        ClioTool { anchors.verticalCenter: parent.verticalCenter; pane: formatBar.host; onHoveredChanged: formatBar.host.formatHover(); size: 26; glyph: "\u{F0265}"; tip: "Clear formatting"; enabled: !pane.inMono; onPressed: ed.plainText() }
      }
    }
  }

  // ── FIND IN NOTE ── at the foot of the note, over the hint strip and
  // dressed as it is (user, 2026-10-14): the note goes on under it frosted
  // (the window's bottom edge, see ClioWindow), the fields centered
  Item {
    id: findBar
    anchors.bottom: parent.bottom
    width: parent.width
    height: pane.finding && pane.win ? pane.win.footH + 8 : 0
    clip: true
    z: 4
    Behavior on height { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
    Rectangle { anchors.fill: parent; color: Zenon.hintFrostBg }
    Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Zenon.border }
    Row {
      id: findRow
      readonly property real fit: Math.min(1, (findBar.width - 24) / Math.max(1, width))
      scale: fit
      x: Math.round((findBar.width - width) / 2)
      anchors.verticalCenter: parent.verticalCenter
      spacing: 8
      Rectangle {
        width: 260
        height: 30
        radius: Zenon.windowRadius
        color: Zenon.wash(0.06)
        border.width: 1
        border.color: Zenon.border
        TextInput {
          id: findField
          anchors.fill: parent
          anchors.leftMargin: 10
          anchors.rightMargin: 10
          verticalAlignment: TextInput.AlignVCenter
          clip: true
          cursorDelegate: Caret { field: findField }
          color: Zenon.ink
          selectionColor: Zenon.alpha(Zenon.cyan, 0.4)
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(14)
          onTextChanged: if (pane.finding) ed.find(text)
          Keys.onPressed: (e) => {
            if (e.key === Qt.Key_Escape) { pane.closeFind(); e.accepted = true; }
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { ed.findStep(e.modifiers & Qt.ShiftModifier ? -1 : 1); e.accepted = true; }
            else if (e.key === Qt.Key_Tab) { replaceField.forceActiveFocus(); e.accepted = true; }
          }
          Text { visible: findField.text === ""; anchors.verticalCenter: parent.verticalCenter; text: "Find in note"; color: Zenon.accentMuted; font: findField.font }
        }
        HeldRing { anchors.fill: parent; radius: parent.radius; z: 10; on: findField.activeFocus }
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: findField.text === "" ? "" : ed.findHits.length === 0 ? "None" : (ed.findAt + 1) + " of " + ed.findHits.length
        color: ed.findHits.length === 0 && findField.text !== "" ? Zenon.red : Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
        font.features: { "tnum": 1 }
      }
      DialogButton { anchors.verticalCenter: parent.verticalCenter; glyph: true; label: ""; onClicked: ed.findStep(-1) }
      DialogButton { anchors.verticalCenter: parent.verticalCenter; glyph: true; label: ""; onClicked: ed.findStep(1) }
      Rectangle {
        visible: !ed.readOnly
        width: 180
        height: 30
        radius: Zenon.windowRadius
        color: Zenon.wash(0.06)
        border.width: 1
        border.color: Zenon.border
        TextInput {
          id: replaceField
          anchors.fill: parent
          anchors.leftMargin: 10
          anchors.rightMargin: 10
          verticalAlignment: TextInput.AlignVCenter
          clip: true
          cursorDelegate: Caret { field: replaceField }
          color: Zenon.ink
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(14)
          Keys.onPressed: (e) => {
            if (e.key === Qt.Key_Escape) { pane.closeFind(); e.accepted = true; }
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { ed.replaceHit(replaceField.text); e.accepted = true; }
            else if (e.key === Qt.Key_Backtab) { findField.forceActiveFocus(); e.accepted = true; }
          }
          Text { visible: replaceField.text === ""; anchors.verticalCenter: parent.verticalCenter; text: "Replace with"; color: Zenon.accentMuted; font: replaceField.font }
        }
        HeldRing { anchors.fill: parent; radius: parent.radius; z: 10; on: replaceField.activeFocus }
      }
      DialogButton { visible: !ed.readOnly; anchors.verticalCenter: parent.verticalCenter; label: "Replace all"; ready: ed.findHits.length > 0; onClicked: ed.replaceAll(replaceField.text) }
    }
  }

  // ── THE TRAY: what is already in Clio, to use again ────────────────────
  property bool trayOpen: false
  onNoteChanged: if (!pane.note || pane.isSticky) pane.trayOpen = false
  // the picker asked for once the tray is wholly gone (its collapse ended,
  // the popup unmapped); the timer only in case that never comes
  property bool pickPending: false
  function pickNow() { if (!pane.pickPending) return; pane.pickPending = false; pickLater.stop(); Qt.callLater(() => pane.win.attachFile()); }
  Timer { id: pickLater; interval: 400; onTriggered: pane.pickNow() }
  AttachTray {
    window: pane.win
    target: trayTool
    win: pane.win
    shown: pane.trayOpen && pane.visible
    dismissable: true
    onDismissed: pane.trayOpen = false
    onUsed: (it) => pane.win.dropFiles([it.path], ed.caretGap())
    // the tray put away first: building the picker holds the shell a few
    // hundred ms, and a fade caught in that hold hung over the note
    onChoose: { pane.pickPending = true; pane.trayOpen = false; pickLater.restart(); }
    onVisibleChanged: if (!visible) pane.pickNow()
  }

  // ── THE EDITOR ─────────────────────────────────────────────────────────
  BlockEditor {
    id: ed
    anchors.top: formatBar.bottom
    anchors.bottom: findBar.top
    anchors.left: parent.left
    anchors.right: parent.right
    visible: !!pane.note && !pane.locked && pane.loadedOne
    base: pane.mgr ? pane.mgr.base : ""
    mgr: pane.mgr
    readOnly: !pane.note || !!pane.note.deleted
    sinkOnTick: !!pane.mgr && pane.mgr.sinkChecked
    textSize: Math.round(Zenon.px(16) * (pane.mgr ? pane.mgr.textScale : 1))
    face: pane.isSticky ? Clio.faceOf(pane.note) : pane.mgr ? pane.mgr.faceFor(pane.isEntry) : Zenon.face
    readonly property bool activeFocusInside: {
      void ed.cursorKey;
      const it = ed.current();
      return !!it && (it.kind === "table" ? !!it.table() && it.table().hasFocus : it.te && it.te.activeFocus)
        || ed.mediaSel !== "" || ed.cross !== null;
    }
    header: NoteHead { width: parent ? parent.width : 400; pane: pane }
    footer: Backlinks { width: parent ? parent.width : 400; pane: pane }

    Keys.onPressed: (e) => {
      const ctrl = e.modifiers & Qt.ControlModifier;
      if (ctrl && e.key === Qt.Key_F && !(e.modifiers & Qt.ShiftModifier)) { pane.openFind(); e.accepted = true; return; }
      if (ctrl && e.key === Qt.Key_K) { pane.askLink(); e.accepted = true; return; }
      if (ctrl && e.key === Qt.Key_G) { ed.findStep(e.modifiers & Qt.ShiftModifier ? -1 : 1); e.accepted = true; return; }
    }
    onEscaped: { pane.commit(); pane.win.toList(); }
    onLinkClicked: (href) => {
      const id = N.noteLink(href);
      if (id) { pane.win.openNote(id); return; }
      Quickshell.execDetached(["xdg-open", href]);
    }
    onNoteLinkAsked: { if (!pane.isSticky) pane.win.linkOpen = true; }
    onMathAsked: (seq, expr) => pane.mgr.math(expr, (r) => ed.mathAnswer(seq, r))
    onMediaOpened: (b) => b.k === "sketch" ? pane.win.sketch(b) : pane.win.openFile(b)
    onFileOpened: (b) => pane.win.openFile(b)
    onFilesDropped: (paths, at) => pane.win.dropFiles(paths, at)
    // a picture put in is read, so its words are found by a search
    onPicturesAdded: (srcs) => { for (const s of srcs) pane.mgr.ocr(s, (t) => { if (t !== "") ed.setOcr(s, t); }); }
    onPasteAsked: {
      if (pane.isSticky || !pane.note) { ed.pasteText(); return; }
      pane.mgr.pasteImage(pane.note.id, (b) => { if (b) ed.attachBlock(b); else ed.pasteText(); });
    }
    onPastePlainAsked: pane.pastePlain()
    onMenuAsked: (x, y, info) => {
      const p = ed.mapToItem(pane.win.stageItem, x, y);
      pane.editMenu(p.x, p.y, info);
    }
  }

  // ── A LINK TO A NOTE, PEEKED AT ── a moment after the pointer stops on it
  readonly property var linkNote: { const id = N.noteLink(ed.hoverLink); return id && pane.mgr ? pane.mgr.noteOf(id) : null; }
  property bool linkPeek: false
  onLinkNoteChanged: { pane.linkPeek = false; if (pane.linkNote) linkWait.restart(); else linkWait.stop(); }
  Timer { id: linkWait; interval: 450; onTriggered: pane.linkPeek = !!pane.linkNote }
  NotePeek {
    win: pane.win
    target: ed.linkSpotItem
    note: pane.linkNote
    shown: pane.linkPeek && !!pane.linkNote && pane.visible && !pane.win.menuRef.isOpen && !pane.win.sheetOpen
  }

  // ── NOTHING CHOSEN ─────────────────────────────────────────────────────
  EmptyMark {
    anchors.centerIn: parent
    visible: !pane.note && !!pane.mgr && pane.mgr.loaded
    word: pane.win && pane.win.inJournal ? "No entry chosen" : "No note chosen"
  }

  // ── LOCKED ─────────────────────────────────────────────────────────────
  Column {
    anchors.centerIn: parent
    visible: !!pane.note && pane.locked
    spacing: 14
    width: 360
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: ""
      color: Zenon.yellow
      font.family: Zenon.glyphFace
      font.pixelSize: Zenon.px(46)
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: pane.isEntry ? "This journal is locked" : "This note is locked"
      color: Zenon.ink
      font.family: Zenon.face
      font.weight: Font.Bold
      font.pixelSize: Zenon.px(20)
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      text: pane.isEntry ? "Enter the Clio password to read and write in it." : "Enter the Clio password to view it. Every locked note opens with it, until you Lock Now or close Clio."
      color: Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(14)
    }
    DialogButton {
      anchors.horizontalCenter: parent.horizontalCenter
      label: pane.isEntry ? "Unlock journal" : "View note"
      ink: Zenon.yellow
      primary: true
      onClicked: pane.unlockHere()
    }
  }

  // (the format bar kept up moves the editor down, and away again: its
  // frost re-measured each time, or a band of it stayed where the bar was)
  // (head and format bar frosted as one strip, from the pane's
  // top down to the note — no bar named, see morpheus/ScrollEdge; and
  // re-measured as the bars come and go, or a band of frost stayed where
  // one had been)
  ScrollEdge { view: ed.flick; follow: true; bar: null; chromeTop: 0; visible: ed.visible; track: [ed.y, formatBar.height] }

  // ── MENUS ──────────────────────────────────────────────────────────────
  function formatMenu(x, y) {
    const k = (kind, label, keys) => ({ text: label, icon: N.KINDS[kind].glyph, mark: keys || "", run: () => ed.setKind(kind) });
    pane.win.menuRef.open(x, y, [
      k("title", "Title", "ctrl shift t"), k("heading", "Heading", "ctrl shift h"), k("subheading", "Subheading", "ctrl shift j"),
      k("body", "Body", "ctrl shift b"), k("mono", "Monostyled", "ctrl shift m"),
      { isSeparator: true },
      k("bullet", "Bulleted list", "ctrl shift 7"), k("dash", "Dashed list", "ctrl shift 8"), k("number", "Numbered list", "ctrl shift 9"),
      k("check", "Checklist", "ctrl shift l"), k("quote", "Block quote"),
      { isSeparator: true },
      { text: "Bold", enabled: !pane.inMono, icon: "", mark: "ctrl b", run: () => ed.mark("b") },
      { text: "Italic", enabled: !pane.inMono, icon: "", mark: "ctrl i", run: () => ed.mark("i") },
      { text: "Underline", enabled: !pane.inMono, icon: "", mark: "ctrl u", run: () => ed.mark("u") },
      { text: "Strikethrough", enabled: !pane.inMono, icon: "", mark: "ctrl shift x", run: () => ed.mark("s") },
      { isSeparator: true },
      { text: "Indent", icon: "", mark: "tab", run: () => ed.indent(1) },
      { text: "Outdent", icon: "", mark: "shift tab", run: () => ed.indent(-1) },
      { text: "Clear formatting", enabled: !pane.inMono, icon: "\u{F0265}", run: () => ed.plainText() }]
      .concat(!pane.mgr.fontBook ? [] : [{ isSeparator: true }]
      .concat(pane.isSticky ? [] : [
        { text: "Font for these words…", enabled: !pane.inMono, icon: "\uF031", run: () => pane.chooseRunFace() },
        { text: "The note's own font for these words", enabled: !pane.inMono && pane.faceHere !== "", icon: "\uF031", run: () => ed.runFace("") }]).concat(!pane.isSticky ? [] : [
        { text: "Font for this sticky…", icon: "\uF031",
          run: () => pane.mgr.chooseFace(false, pane.note) }])));
  }
  // ── THE OUTLINE ── the note's title, headings and subheadings, each a
  // way to it (a folded heading over it is opened: ed.showHit's unfolding)
  function outlineMenu(x, y) {
    ed.flushTyping();
    const lvl = { title: 0, heading: 1, subheading: 2 };
    const items = [];
    ed.blocks.forEach((b, i) => {
      if (!(b.k in lvl)) return;
      const t = N.plain(b.h).trim();
      if (t === "") return;
      items.push({ text: "\u2003".repeat(lvl[b.k]) + t, icon: N.KINDS[b.k].glyph,
                   run: () => {
                     if (ed._hidden[i]) for (let x = i - 1; x >= 0; x--) if (ed.blocks[x].fold) { ed.blocks[x].fold = false; ed.rev++; }
                     Qt.callLater(() => ed.place(i, "start"));
                   } });
    });
    if (items.length === 0) items.push({ text: "No headings yet", icon: "", enabled: false, run: () => {} });
    pane.win.menuRef.open(x, y, items);
  }
  function inkMenu(x, y) {
    const names = { magenta: "Purple", pink: "Pink", yellow: "Orange", green: "Mint", blue: "Blue", cyan: "Cyan", red: "Red" };
    const marks = { sand: "Yellow", pink: "Pink", green: "Green", blue: "Blue", magenta: "Purple" };
    const items = N.INKS.map((n) => ({ text: names[n] + " text", icon: "", iconInk: Zenon[n], run: () => ed.ink(n) }));
    items.push({ text: "Plain text color", icon: "", run: () => ed.ink("") }, { isSeparator: true });
    for (const m of N.MARKERS) items.push({ text: marks[m] + " highlight", icon: "\u{F0652}", iconInk: Zenon[m], run: () => ed.highlight(m) });
    items.push({ text: "No highlight", icon: "\u{F0652}", run: () => ed.highlight("") });
    pane.win.menuRef.open(x, y, items);
  }
  // a picture's words under it, as paragraphs (read now if not yet)
  function textUnder(k) {
    const b = ed.blockOf(k);
    if (!b) return;
    const put = (t) => {
      if (t === "") { pane.win.say("No words found in it", true); return; }
      ed.setOcr(b.src, t);
      ed.insertAt(ed.indexOf(k) + 1, t.split("\n").map((l) => N.block("body", N.escape(l))));
    };
    if (b.ocr) put(b.ocr); else { pane.win.say("Reading the picture…"); pane.mgr.ocr(b.src, put); }
  }
  function copyTextOf(k) {
    const b = ed.blockOf(k);
    if (!b) return;
    const go = (t) => { if (t === "") { pane.win.say("No words found in it", true); return; } ed.setOcr(b.src, t); pane.mgr.copyText(t); pane.win.say("Copied the words in the picture"); };
    if (b.ocr) go(b.ocr); else { pane.win.say("Reading the picture…"); pane.mgr.ocr(b.src, go); }
  }
  function attachMenu(x, y) {
    const items = [];
    if (!pane.isSticky) items.push(
      { text: "A picture or a file…", icon: "", run: () => pane.win.attachFile() },
      { text: "The picture on the clipboard", icon: "\u{F0192}", run: () => pane.mgr.pasteImage(pane.note.id, (b) => b ? ed.attachBlock(b) : pane.win.say("No picture on the clipboard", true)) },
      { text: "A scanned document…", icon: "\u{F06AB}", run: () => pane.win.scanDocument() },
      { text: "A sketch", icon: "\u{F03EB}", run: () => pane.win.sketch(null) },
      { text: "A link to a note", icon: "\u{F0339}", mark: ">>", run: () => pane.win.linkOpen = true });
    items.push({ text: "A table", icon: "", mark: "ctrl alt t", run: () => ed.insertTable() },
               { text: "A divider", icon: "\u{F06D7}", mark: "---", run: () => ed.insertRule() },
               { text: "Today's date", icon: "", run: () => pane.typeHere(N.dateLong(Date.now())) },
               { text: "The time", icon: "", run: () => pane.typeHere(N.clock(Date.now())) });
    pane.win.menuRef.open(x, y, items);
  }
  // the clipboard as words only (BlockEditor.pastePlain)
  function pastePlain() {
    plainProc.running = false;
    plainProc.running = true;
  }
  Process {
    id: plainProc
    command: ["sh", "-c", "wl-paste -n -t text 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text === "") { pane.win.say("No words on the clipboard", true); return; }
        ed.pastePlain(text);
      }
    }
  }
  function typeHere(t) {
    const it = ed.current();
    if (!it || !it.isText) { ed.focusEnd(false); Qt.callLater(() => pane.typeHere(t)); return; }
    it.te.insert(it.te.cursorPosition, N.escape(t));
  }
  function lockMenu(x, y) {
    const n = pane.note;
    if (!n) return;
    const items = [];
    if (n.sealed) items.push({ text: "Remove lock", icon: "", run: () => pane.win.removeLock(n) });
    else items.push({ text: "Lock this " + (pane.isEntry ? "entry" : "note"), icon: "", run: () => pane.win.lockNote(n) });
    if (pane.mgr.unlocked) items.push({ text: "Lock Now", icon: "", mark: "ctrl alt l", run: () => pane.win.lockNow() });
    items.push({ isSeparator: true }, { text: pane.mgr.hasPassword ? "Change the password…" : "Set a password…", icon: "", run: () => pane.win.changePassword() });
    pane.win.menuRef.open(x, y, items);
  }
  function shareMenu(x, y) {
    const n = pane.note;
    pane.win.menuRef.open(x, y, [
      { text: "Copy note", icon: "\u{F018F}", run: () => pane.win.copyNote(n) },
      { text: "Copy as Markdown", icon: "", run: () => { pane.commit(); pane.mgr.copyText(N.markdownOf(ed.stored(), "")); pane.win.say("Copied as Markdown"); } },
      { text: "Copy as plain text", icon: "", run: () => { pane.commit(); pane.mgr.copyText(N.textOf(ed.stored())); pane.win.say("Copied as text"); } },
      { isSeparator: true },
      { text: "Export as Markdown…", icon: "", mark: "ctrl e", run: () => pane.win.exportNote(n, "markdown") },
      { text: "Export as HTML…", icon: "", run: () => pane.win.exportNote(n, "html") },
      { text: "Export as text…", icon: "", run: () => pane.win.exportNote(n, "text") },
      { isSeparator: true },
      { text: "Every picture and file…", icon: "", run: () => pane.win.picsOpen = true }]);
  }
  function askLink() {
    const href = ed.linkHere();
    const sel = ed.selectedText();
    pane.win.cardsRef.ask({ title: href ? "Edit link" : "Add a link", glyph: "", ink: Zenon.cyan,
      fields: [{ key: "url", label: "Address", value: href || (/^\S+\.\S+$/.test(sel) ? sel : ""), hint: "https://…" }]
        .concat(sel === "" ? [{ key: "label", label: "Words", value: "", optional: true }] : []),
      verb: href ? "Save" : "Add", then: (v) => { if (v.url.trim()) Qt.callLater(() => ed.link(v.url.trim(), v.label || "")); } });
  }
  // the right click in the editor: the edits, then what it was on
  // a reminder at a time typed: "tomorrow 9", "20/10 14:00", "in 2 hours"
  function askDue(k) {
    const b = ed.blockOf(k);
    pane.win.cardsRef.ask({ title: "Remind me", glyph: "\u{F009F}", ink: Zenon.yellow,
      detail: "When: “tomorrow 9”, “in 2 hours”, “18:30”, “20/10 14:00” or “2026-10-20 14:00”.",
      fields: [{ key: "when", label: "When", value: b && b.due ? N.clock(b.due) : "", hint: "tomorrow 9" }], verb: "Remind me",
      then: (v) => {
        const due = N.parseWhen(v.when, Date.now());
        if (!due) { pane.win.say("That is not a time I can read", true); return; }
        ed.setAttr(k, "due", due);
        pane.win.say("Reminder " + N.dueText(due, Date.now()));
      } });
  }
  function editMenu(x, y, info) {
    if (!pane.note) return;
    const ro = ed.readOnly;
    const it = ed.current();
    const hasSel = ed.cross !== null || !!it && it.isText && it.te.selectionStart !== it.te.selectionEnd;
    // the spelling's own items first, as every Mac menu has them
    const sp = info.spell;
    const spellItems = !sp ? [] : sp.sugs.slice(0, 6).map((w) => ({ text: w, icon: "\uF00C", enabled: !ro,
                                                                     run: () => ed.respellWord(info.key, sp, w) }))
      .concat(sp.sugs.length === 0 ? [{ text: "No guesses", icon: "", enabled: false, run: () => {} }] : [])
      .concat(pane.mgr.spellTail(sp.w));
    const items = spellItems.concat([
      { text: "Cut", icon: "\u{F0190}", mark: "ctrl x", enabled: hasSel && !ro, run: () => { if (ed.cross) { ed.copyCross(); ed.deleteCross(); } else it.te.cut(); } },
      { text: "Copy", icon: "\u{F018F}", mark: "ctrl c", enabled: hasSel, run: () => { if (ed.cross) ed.copyCross(); else it.te.copy(); } },
      { text: "Paste", icon: "\u{F0192}", mark: "ctrl v", enabled: !ro, run: () => ed.pasteAsked() },
      { text: "Paste as plain text", icon: "\u{F0192}", mark: "ctrl shift v", enabled: !ro, run: () => pane.pastePlain() },
      { text: "Select all", icon: "\u{F0486}", mark: "ctrl a", run: () => ed.selectAll() }]);
    const c = info.control;
    if (info.link) items.push({ isSeparator: true },
      { text: N.noteLink(info.link) ? "Open the note" : "Open the link", icon: "", run: () => ed.linkClicked(info.link) },
      { text: "Copy the address", icon: "\u{F018F}", run: () => pane.mgr.copyText(info.link) },
      { text: "Edit link…", icon: "", enabled: !ro, run: () => pane.askLink() });
    if (info.kind === "image" || info.kind === "sketch" || info.kind === "file") {
      const b = ed.blockOf(info.key);
      items.push({ isSeparator: true },
        { text: info.kind === "sketch" ? "Edit sketch" : "Open", icon: info.kind === "sketch" ? "\u{F03EB}" : "",
          run: () => info.kind === "sketch" ? pane.win.sketch(b) : pane.win.openFile(b) });
      if (info.kind !== "file") items.push(
        { text: "Full width", icon: "\u{F084E}", enabled: !ro, run: () => { ed.resizeMedia(info.key, 1); ed.edited(); } },
        { text: "Half width", icon: "\u{F084C}", enabled: !ro, run: () => { ed.resizeMedia(info.key, 0.5); ed.edited(); } });
      if (info.kind === "image") items.push(
        { text: "Copy the words in it", icon: "\u{F113D}", run: () => pane.copyTextOf(info.key) },
        { text: "Its words under it", icon: "\u{F09ED}", enabled: !ro, run: () => pane.textUnder(info.key) });
      // a row of pictures and files (BlockEditor ROWS)
      const at = ed.indexOf(info.key);
      if (ed.joins(at)) items.push({ text: "On a line of its own", icon: "\u{F0729}", enabled: !ro, run: () => ed.setBeside(info.key, false) });
      else if (at > 0 && ed.sideKind(ed.blocks[at - 1])) items.push({ text: "Beside the one before", icon: "\u{F056D}", enabled: !ro, run: () => ed.setBeside(info.key, true) });
      items.push({ text: "Show in terminus", icon: "", run: () => Quickshell.execDetached(["qs", "ipc", "call", "Terminus", "reveal", pane.mgr.base + "/" + b.src]) },
                 { text: "Remove", icon: "", danger: true, enabled: !ro, run: () => { ed.mediaSel = info.key; ed.deleteMedia(); } });
    }
    // a checklist item: a reminder
    if (info.kind === "check" && !ro) {
      const k = info.key, b = ed.blockOf(k);
      const presets = N.duePresets(Date.now()).map((p) => ({ text: p.label, icon: "\u{F009C}", mark: N.dueText(p.due, Date.now()), run: () => ed.setAttr(k, "due", p.due) }));
      items.push({ isSeparator: true },
        { text: b && b.due ? "Reminder: " + N.dueText(b.due, Date.now()) : "Remind me…", icon: "\u{F009F}", run: () => {
          const p = Qt.point(x, y);
          pane.win.menuRef.open(p.x, p.y, presets.concat([
            { text: "At a time…", icon: "\u{F0020}", run: () => pane.askDue(k) }])
            .concat(b && b.due ? [{ isSeparator: true }, { text: "No reminder", icon: "", danger: true, run: () => ed.setAttr(k, "due", null) }] : []));
        } });
    }
    if (info.kind === "table" && info.cell && !ro) {
      const r = info.cell.r, cc = info.cell.c, k = info.key;
      items.push({ isSeparator: true },
        { text: "Add a row above", icon: "\u{F04F4}", run: () => ed.tableRow(k, r) },
        { text: "Add a row below", icon: "\u{F04F3}", run: () => ed.tableRow(k, r + 1) },
        { text: "Add a column before", icon: "\u{F04ED}", run: () => ed.tableCol(k, cc) },
        { text: "Add a column after", icon: "\u{F04EC}", run: () => ed.tableCol(k, cc + 1) },
        { text: "Delete row", icon: "\u{F04F5}", run: () => ed.tableRow(k, r, true) },
        { text: "Delete column", icon: "\u{F04EE}", run: () => ed.tableCol(k, cc, true) },
        { text: "Delete table", icon: "", danger: true, run: () => { ed.mediaSel = k; ed.deleteMedia(); } });
    }
    if (!ro && N.isText({ k: info.kind })) {
      items.push({ isSeparator: true },
        { text: "Formats…", icon: "\u{F0B34}", run: () => pane.formatMenu(x, y) },
        { text: "Color and highlight…", icon: "\u{F03D8}", run: () => pane.inkMenu(x, y) },
        { text: "Link…", icon: "", mark: "ctrl k", run: () => pane.askLink() });
      if (pane.note.d && pane.note.d.checks > 0) items.push(
        { text: "Tick every box", icon: "\u{F0C52}", run: () => ed.checkAll(true) },
        { text: "Untick every box", icon: "\u{F0130}", run: () => ed.checkAll(false) },
        { text: "Move ticked items to the bottom", icon: "\u{F04BC}", run: () => ed.sinkChecked() },
        { text: "Delete ticked items", icon: "\uF1F8", danger: true, run: () => { const k = ed.deleteTicked(); if (k) pane.win.say(k + (k === 1 ? " ticked item deleted — ctrl z brings it back" : " ticked items deleted — ctrl z brings them back")); } });
    }
    items.push({ isSeparator: true }, { text: "Find in note", icon: "", mark: "ctrl f", run: () => pane.openFind() });
    pane.win.menuRef.open(x, y, items);
  }
}

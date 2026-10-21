// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// MINERVA'S WINDOW — the library, or a book being read.
//
//   the library   every book opened, last read first (MinervaLibrary)
//   reading       the book (MinervaPdf or MinervaBook — the same face to
//                 this window), a sidebar of its contents, your bookmarks,
//                 your highlights and a find's hits (MinervaSide), and a
//                 head that says where you are
//
// A highlight is the words selected, kept with the book and filed into
// Clio, one note per book ("Highlights · <title>"). The place you were is
// kept as you read, and a book opens where you left it.
//
//   ← → / page keys / space   turn       ctrl f   find (return: the next)
//   ctrl d   bookmark here               ctrl h   highlight the selection
//   ctrl + − 0   size (an EPUB's type)   ctrl b   the sidebar
//   ctrl l   the library                 ctrl o   open a file
//   esc      the find, then the library, then closes

import QtQuick
import Quickshell
import "../morpheus"
import "../morpheus/controls" as Ctl
import "../terminus"
import "minerva.js" as M

FloatingWindow {
  id: mw
  title: "minerva"
  color: Zenon.alpha(Zenon.layerBg, 0)
  implicitWidth: 1280
  implicitHeight: 880
  minimumSize: Qt.size(820, 560)

  property var mgr: null

  onVisibleChanged: if (!mw.visible) Qt.callLater(() => { mw.keep(); if (mw.mgr) mw.mgr.retire(mw); mw.destroy(); })
  onClosed: mw.visible = false

  // lower (user, 2026-10-21): the tools sit in it now, not under it
  readonly property int headH: 48
  readonly property int sideW: 300
  readonly property var settings: mw.mgr ? mw.mgr.settings : M.defaults()

  // ── WHAT IS OPEN ───────────────────────────────────────────────────────
  property string mode: "library"     // library · reading
  property string path: ""
  readonly property string kind: M.kindOf(mw.path)
  readonly property var book: mw.mgr && mw.path !== "" ? mw.mgr.bookOf(mw.path) : null
  readonly property var page: viewLoader.item
  property var epub: null             // epub.py's book.json, for an EPUB
  property string failure: ""
  readonly property bool needsPdf: mw.kind === "pdf" && !!mw.mgr && mw.mgr.pdfKnown && !mw.mgr.pdfReady

  function read(p) {
    mw.keep();
    mw.failure = "";
    mw.epub = null;
    mw.findText = "";
    mw.path = p;
    mw.mode = "reading";
    mw.mgr.touch(p, { opened: Date.now() });
    viewLoader.sourceComponent = undefined;
    if (mw.kind === "epub") {
      mw.mgr.openEpub(p, (b, why) => {
        if (mw.path !== p) return;
        if (!b) { mw.failure = why || "This book could not be read"; return; }
        mw.epub = b;
        mw.mgr.change(p, { title: b.title || M.nameOf(p), author: b.author, cover: b.cover });
        viewLoader.sourceComponent = bookComp;
      });
    } else if (mw.mgr.pdfReady) {
      viewLoader.setSource("MinervaPdf.qml", { path: p, startAt: mw.book ? mw.book.pos : null, zoomMode: mw.settings.zoom });
    }
    keys.forceActiveFocus();
  }
  // Qt PDF arriving (installed from here) opens the PDF that asked for it
  Connections {
    target: mw.mgr
    function onPdfReadyChanged() { if (mw.mgr.pdfReady && mw.mode === "reading" && mw.kind === "pdf" && !mw.page) mw.read(mw.path); }
  }
  function toLibrary() {
    mw.keep();
    mw.mode = "library";
    mw.path = "";
    viewLoader.sourceComponent = undefined;
    keys.forceActiveFocus();
  }
  // where you are, kept (also on the way out)
  function keep() {
    if (!mw.page || !mw.page.ready || mw.path === "") return;
    mw.placeChanged(mw.page.where);
  }
  function placeChanged(where) {
    if (!mw.mgr || mw.path === "") return;
    const progress = mw.kind === "pdf" ? M.pdfProgress(where.page || 0, mw.page ? mw.page.pageCount : 1)
      : M.epubProgress(mw.epub ? mw.epub.chapters : [], where.chapter || 0, where.frac || 0);
    mw.mgr.change(mw.path, { pos: where, progress: progress });
  }

  Component {
    id: bookComp
    MinervaBook {
      book: mw.epub
      mgr: mw.mgr
      startAt: mw.book ? mw.book.pos : null
      settings: mw.settings
    }
  }
  Connections {
    target: mw.page
    ignoreUnknownSignals: true
    function onMoved(where) { mw.placeChanged(where); mw.syncMeta(); }
    function onFailed(why) { mw.failure = why; }
    function onZoomChosen(z) { if (mw.mgr) mw.mgr.setSetting("zoom", z); }
    function onReadyChanged() { mw.syncMeta(); }
  }
  // a PDF's own title and author, when it has them — asked when it is
  // ready AND as it moves, since ready can come before this is listening
  function syncMeta() {
    if (mw.kind !== "pdf" || !mw.page || !mw.page.ready || !mw.page.title || !mw.book) return;
    if (mw.book.title !== mw.page.title || mw.book.author !== mw.page.author)
      mw.mgr.change(mw.path, { title: mw.page.title, author: mw.page.author });
  }

  // ── MARKS ──────────────────────────────────────────────────────────────
  readonly property var hereMark: mw.book && mw.page && mw.page.ready ? M.markHere(mw.book.bookmarks, mw.page.where) : null
  function toggleBookmark() {
    if (!mw.book || !mw.page || !mw.page.ready) return;
    if (mw.hereMark) { mw.mgr.change(mw.path, { bookmarks: M.dropMark(mw.book.bookmarks, mw.hereMark.id) }); mw.say("Bookmark removed"); return; }
    mw.mgr.change(mw.path, { bookmarks: M.addMark(mw.book.bookmarks, mw.page.where, "", Date.now()) });
    mw.say("Bookmarked " + M.whereWords(mw.kind, mw.page.where, mw.epub ? mw.epub.chapters : []));
  }
  function highlight() {
    if (!mw.book || !mw.page) return;
    const text = String(mw.page.selected || "").replace(/\s+/g, " ").trim();
    if (text === "") { mw.say("Select some words first", true); return; }
    const where = mw.page.where;
    const list = M.addMark(mw.book.highlights, where, text, Date.now());
    const id = list[list.length - 1].id;
    mw.mgr.change(mw.path, { highlights: list });
    const place = M.whereWords(mw.kind, where, mw.epub ? mw.epub.chapters : []);
    const filed = mw.mgr.toClio(mw.book.title, text, mw.book.title + " · " + place, (noteId) => {
      const b = mw.mgr.bookOf(mw.path);
      if (b) mw.mgr.change(mw.path, { highlights: M.setMark(b.highlights, id, { note: noteId }) });
    });
    mw.say(filed ? "Highlighted — and filed in Clio" : "Highlighted");
  }
  function dropMark(id, list) {
    if (!mw.book) return;
    if (list === "marks") mw.mgr.change(mw.path, { bookmarks: M.dropMark(mw.book.bookmarks, id) });
    else mw.mgr.change(mw.path, { highlights: M.dropMark(mw.book.highlights, id) });
  }

  // ── FIND ───────────────────────────────────────────────────────────────
  property string findText: ""
  function find(words) {
    mw.findText = words;
    if (mw.page) mw.page.find(words);
    if (words !== "") { mw.setSidebar(true); side.tab = "find"; }
  }

  // ── WHAT WAS JUST DONE, SAID ONCE ─────────────────────────────────────
  property string said: ""
  property bool saidBad: false
  function say(t, bad) { mw.said = t; mw.saidBad = !!bad; sayTimer.restart(); }
  Timer { id: sayTimer; interval: 2800; onTriggered: mw.said = "" }

  function setSidebar(on) { if (mw.mgr) mw.mgr.setSetting("sidebar", on); }
  function openFile() {
    if (!mw.mgr || !mw.mgr.fileManager) return;
    mw.mgr.fileManager.choose(false, mw.path !== "" ? mw.path.replace(/\/[^/]*$/, "") : Quickshell.env("HOME"), (paths) => {
      if (paths && paths.length > 0) mw.mgr.open(paths.join("\n"));
    }, "", true);
  }

  // ── KEYS ───────────────────────────────────────────────────────────────
  Item {
    id: keys
    focus: true
    Keys.onPressed: (e) => {
      const ctrl = e.modifiers & Qt.ControlModifier;
      e.accepted = true;
      if (ctrl && e.key === Qt.Key_O) { mw.openFile(); return; }
      if (mw.mode === "library") {
        if (e.key === Qt.Key_Escape) { if (lib.query !== "") lib.query = ""; else mw.visible = false; return; }
        if (e.key === Qt.Key_Left) { lib.move(-1, 0); return; }
        if (e.key === Qt.Key_Right) { lib.move(1, 0); return; }
        if (e.key === Qt.Key_Up) { lib.move(0, -1); return; }
        if (e.key === Qt.Key_Down) { lib.move(0, 1); return; }
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { const b = lib.current(); if (b) mw.read(b.path); return; }
        if (e.key === Qt.Key_Delete) { const b = lib.current(); if (b) { mw.mgr.forget(b.path); mw.say("Removed from the library — the file is untouched"); } return; }
        if (e.key === Qt.Key_Backspace) { lib.query = lib.query.slice(0, -1); return; }
        if (e.text && e.text.length > 0 && !ctrl && e.text.charCodeAt(0) >= 32) { lib.query += e.text; lib.sel = 0; return; }
        e.accepted = false;
        return;
      }
      if (e.key === Qt.Key_Escape) {
        if (mw.findText !== "") { findField.text = ""; mw.find(""); return; }
        mw.toLibrary();
        return;
      }
      if (ctrl && e.key === Qt.Key_L) { mw.toLibrary(); return; }
      if (ctrl && e.key === Qt.Key_F) { findField.forceActiveFocus(); findField.selectAll(); return; }
      if (ctrl && e.key === Qt.Key_B) { mw.setSidebar(!mw.settings.sidebar); return; }
      if (ctrl && e.key === Qt.Key_D) { mw.toggleBookmark(); return; }
      if (ctrl && e.key === Qt.Key_H) { mw.highlight(); return; }
      if (ctrl && e.key === Qt.Key_C) { if (mw.page) mw.page.copy(); return; }
      if (ctrl && (e.key === Qt.Key_Plus || e.key === Qt.Key_Equal)) { if (mw.page) mw.page.zoomBy(1.15); return; }
      if (ctrl && e.key === Qt.Key_Minus) { if (mw.page) mw.page.zoomBy(1 / 1.15); return; }
      if (ctrl && e.key === Qt.Key_0) { if (mw.page) mw.page.fit("width"); return; }
      if (!mw.page) { e.accepted = false; return; }
      if (e.key === Qt.Key_Right || e.key === Qt.Key_PageDown || e.key === Qt.Key_Space) { mw.page.step(1); return; }
      if (e.key === Qt.Key_Left || e.key === Qt.Key_PageUp) { mw.page.step(-1); return; }
      if (e.key === Qt.Key_Home) { mw.page.goTo(mw.kind === "pdf" ? { page: 0 } : { chapter: 0, frac: 0 }); return; }
      if (e.key === Qt.Key_End) { mw.page.goTo(mw.kind === "pdf" ? { page: mw.page.pageCount - 1 } : { chapter: mw.page.pageCount - 1, frac: 1 }); return; }
      if (e.key === Qt.Key_Delete && side.sel >= 0 && (side.tab === "marks" || side.tab === "highlights")) {
        const r = side.rows[side.sel]; if (r) mw.dropMark(r.id, side.tab); return;
      }
      e.accepted = false;
    }
  }

  // ── THE STAGE ──────────────────────────────────────────────────────────
  Item {
    id: stage
    anchors.fill: parent
    Rectangle { anchors.fill: parent; color: Zenon.layerBg }

    // ── the head ─────────────────────────────────────────────────────────
    Item {
      id: head
      width: parent.width
      height: mw.headH
      z: 3
      Rectangle { anchors.fill: parent; color: Zenon.headBg }
      Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Zenon.border }
      Text {
        id: owl
        x: 20
        anchors.verticalCenter: parent.verticalCenter
        text: mw.mode === "reading" ? "" : "\u{F03D2}"
        color: mw.mode === "reading" ? (owlPress.pressed ? Zenon.ink : Zenon.accentMuted) : Zenon.cyan
        font.family: Zenon.glyphFace
        font.pixelSize: Zenon.px(mw.mode === "reading" ? 15 : 20)
        MouseArea { id: owlPress; anchors.fill: parent; anchors.margins: -10; enabled: mw.mode === "reading"; onClicked: mw.toLibrary() }
      }
      Text {
        id: headTitle
        anchors.left: owl.right
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, head.width * (mw.mode === "reading" ? 0.24 : 0.4))
        elide: Text.ElideRight
        text: mw.mode === "library" ? "Library" : mw.book ? mw.book.title : M.nameOf(mw.path)
        color: Zenon.ink
        font.family: Zenon.face
        font.weight: Zenon.titleWeight
        font.pixelSize: Zenon.px(18)
      }
      Text {
        anchors.left: headTitle.right
        anchors.leftMargin: 12
        anchors.baseline: headTitle.baseline
        anchors.right: headTools.left
        anchors.rightMargin: 16
        visible: mw.mode === "library" || !mw.page || !mw.page.ready
        elide: Text.ElideRight
        text: mw.mode === "library"
          ? (mw.mgr ? (mw.mgr.books.length === 1 ? "1 book" : mw.mgr.books.length + " books") : "")
            + (lib.query !== "" ? "  ·  “" + lib.query + "”" : "")
          : (mw.book && mw.book.author ? mw.book.author : "")
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(14)
      }
      // ── THE READING TOOLS (user, 2026-10-21) ───────────────────────────
      // where you are and the way to anywhere else, then the size: a page
      // you can type, the turn either way, and for a PDF − zoom +, its
      // width or its whole page
      // by its file, not its type name: a type new to minerva's qmldir is
      // not seen until the shell restarts
      Loader {
        id: navTools
        anchors.left: headTitle.right
        anchors.leftMargin: 18
        anchors.verticalCenter: parent.verticalCenter
        active: mw.mode === "reading"
        visible: !!mw.page && mw.page.ready && x + width < headTools.x - 12
        source: "MinervaTools.qml"
        onLoaded: { navTools.item.win = mw; navTools.item.done.connect(() => keys.forceActiveFocus()); }
      }
      Row {
        id: headTools
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        // find, a field that is always there while reading; the buttons
        // beside it stand as tall (32)
        Rectangle {
          visible: mw.mode === "reading"
          width: 200
          height: 30
          radius: Zenon.windowRadius
          color: Zenon.wash(0.06)
          border.width: 1
          border.color: Zenon.border
          HeldRing { anchors.fill: parent; on: findField.activeFocus }
          Text {
            id: findGlyph
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "\u{F0349}"
            color: Zenon.accentMuted
            font.family: Zenon.glyphFace
            font.pixelSize: Zenon.px(14)
          }
          TextInput {
            id: findField
            anchors.left: findGlyph.right
            anchors.leftMargin: 8
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            clip: true
            color: Zenon.ink
            selectionColor: Zenon.cyan
            selectedTextColor: Zenon.onAccent
            font.family: Zenon.face
            font.pixelSize: Zenon.px(14)
            cursorDelegate: Caret { field: findField }
            Text {
              anchors.fill: parent
              verticalAlignment: Text.AlignVCenter
              visible: findField.text === "" && !findField.activeFocus
              text: "Find in the book"
              color: Zenon.accentMuted
              font: findField.font
            }
            Keys.onPressed: (e) => {
              if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                if (findField.text !== mw.findText) mw.find(findField.text);
                else if (mw.page) (e.modifiers & Qt.ShiftModifier) ? mw.page.findPrev() : mw.page.findNext();
                e.accepted = true;
              } else if (e.key === Qt.Key_Escape) {
                findField.text = "";
                mw.find("");
                keys.forceActiveFocus();
                e.accepted = true;
              }
            }
          }
        }
        DialogButton {
          implicitHeight: 30
          visible: mw.mode === "reading" && mw.kind === "epub"
          label: "Aa"
          onClicked: mw.typeOpen = !mw.typeOpen
        }
        DialogButton {
          implicitHeight: 30
          visible: mw.mode === "reading" && !!mw.page
          glyph: true
          label: mw.hereMark ? "\u{F00C0}" : "\u{F00C3}"
          ink: mw.hereMark ? Zenon.cyan : Zenon.muted
          onClicked: mw.toggleBookmark()
        }
        DialogButton {
          implicitHeight: 30
          visible: mw.mode === "reading" && !!mw.page && mw.page.selected !== ""
          label: "Highlight"
          ink: Zenon.yellow
          onClicked: mw.highlight()
        }
        DialogButton {
          implicitHeight: 30
          visible: mw.mode === "reading"
          glyph: true
          label: "\u{F0279}"
          ink: mw.settings.sidebar ? Zenon.cyan : Zenon.muted
          onClicked: mw.setSidebar(!mw.settings.sidebar)
        }
        DialogButton {
          implicitHeight: 30
          visible: mw.mode === "library"
          label: "Open…"
          ink: Zenon.cyan
          ready: !!mw.mgr && !!mw.mgr.fileManager
          onClicked: mw.openFile()
        }
      }
    }

    // ── the library ──────────────────────────────────────────────────────
    MinervaLibrary {
      id: lib
      anchors.top: head.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: foot.top
      visible: mw.mode === "library"
      mgr: mw.mgr
      onChosen: (p) => mw.read(p)
      onForgot: (p) => { mw.mgr.forget(p); mw.say("Removed from the library — the file is untouched"); }
    }

    // ── reading ──────────────────────────────────────────────────────────
    Item {
      id: sideBox
      // on the right (user, 2026-10-21): the page's left edge is where
      // reading starts, and nothing should stand in front of it
      anchors.top: head.bottom
      anchors.right: parent.right
      anchors.bottom: foot.top
      width: mw.mode === "reading" && mw.settings.sidebar ? mw.sideW : 0
      visible: width > 0
      Behavior on width { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
      clip: true
      Rectangle { anchors.fill: parent; color: Zenon.alpha(Zenon.tabAwayInk, Zenon.tabAway(Zenon.layerBg.a)) }
      Rectangle { anchors.fill: parent; color: Zenon.ground; opacity: 0.6 }
      Rectangle { anchors.left: parent.left; width: 1; height: parent.height; color: Zenon.border }
      MinervaSide {
        id: side
        x: sideBox.width - mw.sideW
        width: mw.sideW
        height: parent.height
        kind: mw.kind
        outline: mw.page ? mw.page.outline : []
        bookmarks: mw.book ? mw.book.bookmarks : []
        highlights: mw.book ? mw.book.highlights : []
        hits: mw.page ? mw.page.hits : []
        chapters: mw.epub ? mw.epub.chapters : []
        findWords: mw.findText
        serif: mw.mgr ? mw.mgr.serifFace : Zenon.face
        onGo: (where, row) => {
          if (!mw.page) return;
          if (side.tab === "find") mw.page.showHit(row);
          else mw.page.goTo(row && row.anchor ? Object.assign({}, where, { anchor: row.anchor }) : where);
          keys.forceActiveFocus();
        }
        onDropMark: (id, list) => mw.dropMark(id, list)
        onShowNote: (m) => mw.mgr.showInClio(m.note, m.text)
      }
    }
    Item {
      id: readBox
      // Qt's PDF view draws past its own bounds (its pages are a TableView
      // that does not clip): without this the page ran under the foot
      clip: true
      anchors.top: head.bottom
      anchors.left: parent.left
      anchors.right: sideBox.left
      anchors.bottom: foot.top
      visible: mw.mode === "reading"
      Loader {
        id: viewLoader
        anchors.fill: parent
        onLoaded: metaSoon.restart()
        onStatusChanged: if (viewLoader.status === Loader.Error) mw.failure = "This PDF could not be shown"
      }
      // Qt PDF missing: what it takes, and the button that does it
      Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 520)
        spacing: 10
        visible: mw.needsPdf
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "\u{F0226}"
          color: Zenon.cyan
          font.family: Zenon.glyphFace
          font.pixelSize: Zenon.px(40)
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "PDFs need Qt PDF"
          color: Zenon.ink
          font.family: Zenon.face
          font.weight: Zenon.titleWeight
          font.pixelSize: Zenon.px(18)
        }
        EmptyState {
          width: parent.width
          text: "Qt's PDF module comes inside qt6-webengine on Arch (about 120 MB). EPUBs need nothing; Ceres installs it once, and this PDF opens."
        }
        Item { width: 1; height: 4 }
        BusyButton {
          anchors.horizontalCenter: parent.horizontalCenter
          label: "Install Qt PDF"
          ink: Zenon.cyan
          primary: true
          busy: !!mw.mgr && mw.mgr.settingUp
          busyText: "Installing…"
          onClicked: if (!mw.mgr.setupPdf((ok) => mw.say(ok ? "Qt PDF is installed" : "Qt PDF was not installed", !ok))) mw.say("Ceres is busy — try again in a moment", true)
        }
      }
      // the book could not be read, or is still being unpacked
      EmptyState {
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 520)
        visible: mw.failure !== "" || (!mw.needsPdf && !mw.page && mw.mode === "reading")
        text: mw.failure !== "" ? mw.failure : "Opening…"
      }
      // ── the type, for an EPUB ──────────────────────────────────────────
      Rectangle {
        visible: mw.typeOpen && mw.kind === "epub"
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 12
        width: 300
        height: typeCol.implicitHeight + 28
        radius: Zenon.radiusCard
        color: Zenon.hud(0.92)
        border.width: 1
        border.color: Zenon.border
        z: 5
        Column {
          id: typeCol
          x: 6
          y: 14
          width: parent.width - 12
          spacing: 4
          PrefSlider {
            width: parent.width
            label: "Size"
            labelW: 96
            value: mw.settings.fontSize
            from: 12
            to: 40
            wheelStep: 1
            readout: String(mw.settings.fontSize)
            neutral: M.defaults().fontSize
            onMoved: (v) => mw.mgr.setSetting("fontSize", Math.round(v))
          }
          PrefSlider {
            width: parent.width
            label: "Spacing"
            labelW: 96
            value: mw.settings.lineHeight
            from: 1.1
            to: 2.4
            wheelStep: 0.1
            readout: mw.settings.lineHeight.toFixed(1)
            neutral: M.defaults().lineHeight
            onMoved: (v) => mw.mgr.setSetting("lineHeight", v)
          }
          PrefSlider {
            width: parent.width
            label: "Measure"
            labelW: 96
            value: mw.settings.width
            from: 420
            to: 1400
            wheelStep: 40
            readout: String(mw.settings.width)
            neutral: M.defaults().width
            onMoved: (v) => mw.mgr.setSetting("width", v)
          }
          Item {
            width: parent.width
            height: 36
            Ctl.Check {
              x: 14
              anchors.verticalCenter: parent.verticalCenter
              label: "Serif type"
              lit: mw.settings.serif
              onToggled: mw.mgr.setSetting("serif", !mw.settings.serif)
            }
          }
        }
      }
    }

    // ── what was just done, said once ────────────────────────────────────
    Rectangle {
      anchors.horizontalCenter: readBox.visible ? readBox.horizontalCenter : parent.horizontalCenter
      anchors.bottom: foot.top
      anchors.bottomMargin: 18
      width: Math.min(saidText.implicitWidth + 32, 560)
      height: 34
      radius: Zenon.windowRadius
      color: Zenon.hud(0.85)
      border.width: 1
      border.color: mw.saidBad ? Zenon.alpha(Zenon.red, 0.6) : Zenon.border
      opacity: mw.said !== "" ? 1 : 0
      visible: opacity > 0
      z: 4
      Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Easing.OutCubic } }
      Text {
        id: saidText
        anchors.centerIn: parent
        width: Math.min(implicitWidth, parent.width - 32)
        elide: Text.ElideRight
        text: mw.said
        color: mw.saidBad ? Zenon.red : Zenon.ink
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(15)
      }
    }

    HintBar {
      id: foot
      anchors.bottom: parent.bottom
      width: parent.width
      rows: mw.mode === "library"
        ? [["arrows", "choose"], ["return", "read"], ["type", "filter"], ["delete", "remove"], ["ctrl o", "open"], ["esc", "close"]]
        : [["← →", "turn"], ["ctrl f", "find"], ["ctrl d", "bookmark"], ["ctrl h", "highlight"], ["ctrl + −", "size"],
           ["ctrl b", "sidebar"], ["esc", "library"]]
    }
  }
  property bool typeOpen: false
  Timer { id: metaSoon; interval: 500; repeat: true; property int tries: 0
    onTriggered: { mw.syncMeta(); if (++metaSoon.tries > 8 || (mw.page && mw.page.ready)) { metaSoon.stop(); metaSoon.tries = 0; } } }
}

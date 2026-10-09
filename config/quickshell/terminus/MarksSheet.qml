// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
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

Rectangle {
  id: marks
  // the terminus window (`term`, never `root` — see terminus-split notes)
  property var term: null
  anchors.fill: parent
  z: 13
  visible: opacity > 0.01
  opacity: marks.open ? 1 : 0
  // THE SCRIM STOPS AT THE BAR: the bar is this sheet's titlebar,
  // and a scrim laid over it dimmed the title — as the send picker's is.
  color: "transparent"
  Rectangle {
    anchors.fill: parent
    anchors.topMargin: term.tabStripRef.height + term.crumbBarRef.height
    color: term.cardScrim
  }
  // and the sidebar beside the bar, which is not the titlebar: the
  // scrim stops at the bar, not at the sidebar's first heading
  Rectangle {
    width: term.sideRef.width
    height: term.tabStripRef.height + term.crumbBarRef.height
    color: term.cardScrim
  }
  Behavior on opacity {
    NumberAnimation {
      duration: marks.open ? marksSheet.slideIn : marksSheet.slideOut
      easing.type: Zenon.ease
    }
  }

  property bool open: false
  property int sel: 0
  property string query: ""

  // THE SIDEBAR'S OWN LIST, read straight off root.bookmarks so the two
  // can never disagree about what is bookmarked. Home wears its own name
  // rather than the user's — the basename of ~ is "buck", which no rule
  // claims — the same substitution the sidebar and the go sheet make.
  readonly property var all: {
    const out = [];
    const bs = term.bookmarks;
    for (let i = 0; i < bs.length; i++) {
      const p = bs[i];
      out.push({
        path: p,
        name: p === Paths.home() ? "Home" : Terminus.basename(p),
        glyph: Icons.glyphFor({
          name: p === Paths.home() ? "home" : Terminus.basename(p),
          isDir: true })
      });
    }
    return out;
  }

  // RANKED, not merely filtered — the same scorer the file filter and the
  // palette use. Matched against the PATH as well as the name, because a
  // bookmark two levels inside Steam is found by "steam" more often than
  // by what its own directory happens to be called.
  readonly property var rows: {
    const q = marks.query.trim().toLowerCase();
    const all = marks.all;
    if (q === "") return all;
    const hit = [];
    for (let i = 0; i < all.length; i++) {
      const sc = Terminus.fuzzyScore(
        all[i].name.toLowerCase() + " " + all[i].path.toLowerCase(), q);
      if (sc >= 0) hit.push({ c: all[i], sc: sc, i: i });
    }
    hit.sort((a, b) => (b.sc - a.sc) || (a.i - b.i));
    const out = [];
    for (let i = 0; i < hit.length; i++) out.push(hit[i].c);
    return out;
  }

  onQueryChanged: marks.sel = 0

  function ask() {
    marks.query = "";
    marks.sel = 0;
    marks.open = true;
  }

  // Held rather than read back at the end: the flash is long enough for a
  // second keystroke to move the cursor, and where you go is where it lit.
  property string pendingPath: ""
  property bool pendingTab: false

  RowFlash { id: marksFlash; onDone: () => marks.travel() }

  function dismiss() {
    marksFlash.cancel();
    marks.pendingPath = "";
    marks.open = false;
    term.contentRef.forceActiveFocus();
  }

  function step(d) {
    const n = marks.rows.length;
    if (n === 0) return;
    marks.sel = (marks.sel + d + n) % n;
    marksList.positionViewAtIndex(marks.sel, ListView.Contain);
  }

  // ── AND IT MANAGES THEM, not just lists them ──────────────────
  // The sheet STAYS OPEN. Removing one is housekeeping and housekeeping
  // comes in runs — a card that closed after each would make tidying four
  // of them four trips through g b.
  //
  // The cursor holds its place rather than its index: with the last row
  // gone there is no row there any more, so it steps back onto the one
  // above instead of off the end of the list.
  // ── REORDER ───────────────────────────────────────────────────
  // The order is the file's order and the sidebar reads the same file, so
  // moving one here moves it there. Alt, because the bare arrows walk the
  // list and a manager that reordered on them could not be scrolled.
  //
  // ONLY WITH NOTHING TYPED. Under a filter the rows on screen are a
  // ranked subset and the one "above" a row is not the one above it in the
  // file — swapping by what you can see would shuffle what you cannot.
  function shift(d) {
    if (marks.query !== "") {
      term.warn("clear the filter to reorder");
      return;
    }
    const from = marks.sel;
    const to = from + d;
    if (from < 0 || to < 0 || to >= marks.rows.length) return;
    term.moveBookmark(from, to);
    marks.sel = to;
  }

  // The other half of a manager: b a is still the way in from the listing,
  // but a panel about bookmarks that cannot make one is a viewer.
  function addHere() {
    const at = term.cwd;
    if (term.bookmarks.indexOf(at) >= 0) {
      term.warn("already bookmarked");
      return;
    }
    term.editBookmarks((list) => list.push(at));
    term.status = "bookmarked " + Terminus.basename(at);
    marks.query = "";
    marks.sel = Math.max(0, marks.rows.length - 1);
  }

  function drop() {
    const r = marks.rows[marks.sel];
    if (!r) return;
    const n = marks.rows.length;
    term.removeBookmark(r.path);
    if (marks.sel >= n - 1) marks.sel = Math.max(0, n - 2);
  }

  function go(inTab) {
    const r = marks.rows[marks.sel];
    if (!r) return;
    if (!marksFlash.fire(marks.sel)) return;
    marks.pendingPath = r.path;
    marks.pendingTab = inTab === true;
  }

  // Closed before it travels, for the reason the palette gives: the sheet
  // is answering a question and the answer is somewhere else.
  function travel() {
    const path = marks.pendingPath;
    const inTab = marks.pendingTab;
    marks.dismiss();
    if (path === "") return;
    if (inTab) term.openInNewTab(path);
    else term.goTo(path);
  }

  InputShield { keepTop: term.tabStripRef.height + term.crumbBarRef.height; onClicked: marks.dismiss() }

  Sheet {
    backdrop: term.chromeRef   // frosted over it — see morpheus/Sheet
    splice: true
    onCardInkChanged: term.noteSheet("s9", cardInk, drawnX, drawnW)
    onDrawnXChanged: term.noteSheet("s9", cardInk, drawnX, drawnW)
    onDrawnWChanged: term.noteSheet("s9", cardInk, drawnX, drawnW)
    id: marksSheet
    leftInset: term.sideRef.width
    floating: false   // hangs from the bar, which carries its title — see barTitle
    title: term.sheetTitle
    glyph: term.sheetGlyph
    titleInk: term.sheetTitleInk
    glyphInk: term.sheetGlyphInk
    shown: marks.open
    fromTop: term.tabStripRef.height + term.crumbBarRef.height
    // SIZED BY THE FOOTER, not by the rows. A bookmark's name and path are
    // short and would sit happily in 520; the hint row is SEVEN pairs long
    // — move, go, tab, order, add, remove, close, with the filter echoed
    // ahead of them — and it is the footer that decides how wide a sheet
    // full of short names has to be.
    cardW: 880
    // A point taller than the palette's, because the rows are: a 17px name
    // in a 30px row leaves four pixels above and below it.
    readonly property int rowH: 32
    readonly property int pageRows: 14
    cardH: 12 + Math.max(1, Math.min(marksSheet.pageRows,
                                     marks.rows.length))
                * marksSheet.rowH + marksFoot.height

    SelectBar {

      host: term
      view: marksList
      index: marks.sel
      rowH: marksSheet.rowH
      on: marks.rows.length > 0
    }

    ListView {
      id: marksList
      anchors.top: parent.top
      anchors.topMargin: 6
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: marksFoot.top
      anchors.bottomMargin: 6
      clip: true
      model: marks.rows
      currentIndex: marks.sel
      boundsBehavior: Flickable.DragAndOvershootBounds
      boundsMovement: Flickable.FollowBoundsBehavior
      ElasticScroll { view: marksList; step: term.wheelStep }

      delegate: Item {
        id: markRow
        required property var modelData
        required property int index
        width: marksList.width
        height: marksSheet.rowH

        FlashOver { flash: marksFlash; index: markRow.index }

        MouseArea {
          anchors.fill: parent
          enabled: !marksFlash.running
          acceptedButtons: Qt.LeftButton | Qt.MiddleButton
          onClicked: (m) => {
            marks.sel = markRow.index;
            // Middle click removes it, the gesture the sidebar's rows and
            // the tab strip already use for "take this away".
            if (m.button === Qt.MiddleButton)
              term.removeBookmark(markRow.modelData.path);
            else marks.go(false);
          }
        }

        // A FIXED COLUMN for the glyph, not its own width: the nerd font
        // is proportional, so a wide icon ended further right than a
        // narrow one and ran into a name pinned at a constant x. The
        // listing and the go sheet both do this, for the same reason.
        Text {
          id: markGlyph
          x: 16
          width: 22
          horizontalAlignment: Text.AlignHCenter
          anchors.verticalCenter: parent.verticalCenter
          text: markRow.modelData.glyph
          color: Zenon.cyan
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(16)
        }

        Text {
          anchors.left: markGlyph.right
          anchors.leftMargin: 8
          anchors.right: markPath.left
          anchors.rightMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          text: markRow.modelData.name
          elide: Text.ElideRight
          color: Zenon.white
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(17)
        }

        // ── THE WAY OUT, ON THE ROW THE CURSOR IS ON ──────────────
        // Shown for the cursor's row only, so the list is a list until you
        // are standing on something — twelve little crosses down the side
        // is a panel about deleting rather than a panel of places.
        //
        // It sits where the path ends rather than beside it: the path is
        // the quiet half of the row and the cross would have read as part
        // of it.
        Text {
          id: markDrop
          anchors.right: parent.right
          anchors.rightMargin: 16
          anchors.verticalCenter: parent.verticalCenter
          visible: markRow.index === marks.sel
          text: "\uEA76"
          color: dropHov.hovered ? Zenon.red : Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(14)

          HoverHandler { id: dropHov }
          MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            onClicked: {
              marks.sel = markRow.index;
              marks.drop();
            }
          }
        }

        // Where it actually is, quietly. Two bookmarks can share a
        // basename and the name alone would be the sheet refusing to say
        // which is which.
        Text {
          id: markPath
          anchors.right: markDrop.left
          anchors.rightMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, marksList.width * 0.45)
          horizontalAlignment: Text.AlignRight
          elide: Text.ElideLeft
          // ~ for home, the way the breadcrumb writes it: the full path
          // of a bookmark under home is mostly the same eleven characters
          // on every row, and elide would have eaten the useful end of it
          // to keep them.
          text: {
            const h = Paths.home();
            const p = markRow.modelData.path;
            return p === h ? "~"
              : (p.indexOf(h + "/") === 0 ? "~" + p.slice(h.length) : p);
          }
          color: Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
      }
    }

    // Nothing bookmarked yet, said where the rows would be rather than as
    // an empty card that looks like something failed to load.
    Text {
      anchors.centerIn: marksList
      visible: marks.all.length === 0
      text: "nothing bookmarked yet \u2014 b a adds this directory"
      color: Zenon.muted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(14)
    }

    Rectangle {
      anchors.bottom: marksFoot.top
      anchors.left: parent.left
      anchors.right: parent.right
      height: 1
      color: Zenon.border
    }

    Item {
      id: marksFoot
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      height: 34

      Row {
        anchors.centerIn: parent
        spacing: 12

        Text {
          anchors.verticalCenter: parent.verticalCenter
          rightPadding: 2
          text: marks.query !== "" ? marks.query
            : (marks.rows.length === 0 ? "nothing matches"
                                       : "type to filter")
          color: marks.query !== "" ? Zenon.sand : Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(14)
        }

        Repeater {
          // SHORT WORDS, because there are seven of them now. The chip
          // carries the key and the word only has to disambiguate it —
          // "tab" after a return glyph cannot mean anything but a new one,
          // and "order" after alt-arrows cannot mean sorting.
          model: [["\u2191\u2193", "move"], ["\u21b5", "go"],
                  ["\u21e7\u21b5", "tab"], ["alt \u2191\u2193", "order"],
                  ["ctrl a", "add"], ["del", "remove"],
                  ["esc", "close"]]

          delegate: Row {
            id: mfPair
            required property var modelData
            spacing: 5

            KeyCap {
              anchors.verticalCenter: parent.verticalCenter
              label: mfPair.modelData[0]
              fontSize: 12
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: mfPair.modelData[1]
              color: Zenon.muted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(14)
            }
          }
        }
      }
    }
  }
}

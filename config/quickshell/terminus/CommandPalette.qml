// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ── THE PALETTE ───────────────────────────────────────────────────────
// NOT `palette`, and that is not a style choice. Every Item in Qt 6 has a
// `palette` property of its own, and an item's own property is found
// before an id declared outside it — so inside the delegate `palette.sel`
// read a QQuickPalette and came back undefined, which made `on` false on
// every row forever. The rows were the right size and the colours were
// right; the comparison was against nothing. Measured: sel=undefined,
// size=558x30, selBg=#4d45505c.
// A sheet over root.commands. It borrows the send picker's shape wholesale
// — type to filter with no field, arrows to move, Return to commit — for
// the reason that picker states in its own note: the sheet has the
// keyboard and there is nothing else in it a letter could mean.
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
  id: cmdPalette
  // the terminus window (`term`, never `root` — see terminus-split notes)
  property var term: null
  anchors.fill: parent
  z: 13
  visible: opacity > 0.01
  opacity: cmdPalette.open ? 1 : 0
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
      duration: cmdPalette.open ? paletteSheet.slideIn : paletteSheet.slideOut
      easing.type: Zenon.ease
    }
  }

  property bool open: false
  property string query: ""
  property int sel: 0

  // Ranked, not merely filtered — the same scorer the file filter uses, so
  // "dup" puts duplicate first rather than somewhere among everything
  // containing those letters in that order.
  // THE SECTION IS MATCHED AGAINST BUT NEVER DRAWN. The groups decide the
  // order, so related rows still sit together, and the name of the group
  // is a word the query can find — "new" and "all" and "top" are each a
  // single word that only means something in company, and typing "tab"
  // has to reach the one that means a tab. It is not a heading, though:
  // headings were a row you had to step past to get anywhere, for a label
  // nobody reads twice.
  readonly property var shown: {
    // nothing while closed: term.commands changes with the row under the
    // cursor (its labels are about that row), and the hidden list was
    // refiltered and its rows rebuilt on every step (see RowMenu's target)
    if (!cmdPalette.open && cmdPalette.opacity <= 0.01) return [];
    const q = cmdPalette.query.trim().toLowerCase();
    const all = term.commands;
    if (q === "") return all;
    const hit = [];
    for (let i = 0; i < all.length; i++) {
      const sc = Terminus.fuzzyScore(
        String(all[i].section) + " " + String(all[i].label).toLowerCase()
          + " " + String(all[i].alias).toLowerCase()
          + " " + String(all[i].key), q);
      if (sc >= 0) hit.push({ c: all[i], sc: sc, i: i });
    }
    // ── THE ONES THAT DO SOMETHING FIRST, HERE TOO ──────────────
    // The unfiltered list is partitioned that way and a query used to
    // throw it out: a reference key that scored a shade better than a verb
    // sat above it, so "co" led with `copy path` on some queries and with
    // the copy GROUP HEADING's keys on others. Which half a row is in is
    // not a matter of degree, so it is not left to a score.
    //
    // The score still decides everything inside each half, and the
    // original index still breaks ties inside that.
    hit.sort((a, b) => {
      const ar = a.c.act ? 0 : 1;
      const br = b.c.act ? 0 : 1;
      if (ar !== br) return ar - br;
      return (b.sc - a.sc) || (a.i - b.i);
    });
    const out = [];
    for (let i = 0; i < hit.length; i++) out.push(hit[i].c);
    return out;
  }

  onQueryChanged: cmdPalette.sel = 0

  function ask() {
    cmdPalette.query = "";
    cmdPalette.sel = 0;
    cmdPalette.open = true;
  }

  // Held rather than read back at the end: the flash is long enough for a
  // second keystroke to move the cursor, and what runs is what was lit up.
  property var pending: null

  RowFlash { id: cmdFlash; onDone: () => cmdPalette.fire() }

  function dismiss() {
    cmdFlash.cancel();
    cmdPalette.pending = null;
    cmdPalette.open = false;
    term.contentRef.forceActiveFocus();
  }

  function step(d) {
    const n = cmdPalette.shown.length;
    if (n === 0) return;
    cmdPalette.sel = (cmdPalette.sel + d + n) % n;
    paletteList.positionViewAtIndex(cmdPalette.sel, ListView.Contain);
  }

  // CLOSED BEFORE THE VERB RUNS, never after. Half of these open another
  // sheet, and a palette still on screen underneath one would be a card
  // over a card — and the two would fight for the keyboard.
  // WHAT THE CURSOR IS ON, and whether it is a thing that can be done.
  // Most of the keymap is not: j is the cursor, escape means four
  // different things, and the mouse gestures are not keys.
  readonly property var atSel: cmdPalette.shown[cmdPalette.sel]
  readonly property bool runnable:
    !!cmdPalette.atSel && !!cmdPalette.atSel.act

  // NOTHING HAPPENS ON A ROW THAT ONLY TELLS YOU SOMETHING, and the sheet
  // stays up — you are reading it. Closing on return would have made the
  // keymap half of this dismiss itself every time a hand finished a
  // thought. The footer says which kind of row you are on.
  function run() {
    if (!cmdPalette.runnable) return;
    if (!cmdFlash.fire(cmdPalette.sel)) return;
    cmdPalette.pending = cmdPalette.atSel;
  }

  // CLOSED BEFORE THE VERB RUNS, never after. Half of these open another
  // sheet, and a palette still on screen underneath one would be a card
  // over a card — and the two would fight for the keyboard.
  function fire() {
    const c = cmdPalette.pending;
    cmdPalette.pending = null;
    cmdPalette.dismiss();
    if (c && c.act) c.act();
  }

  InputShield { keepTop: term.tabStripRef.height + term.crumbBarRef.height; onClicked: cmdPalette.dismiss() }

  Sheet {
    backdrop: term.chromeRef   // frosted over it — see morpheus/Sheet
    splice: true
    onCardInkChanged: term.noteSheet("s3", cardInk, drawnX, drawnW)
    onDrawnXChanged: term.noteSheet("s3", cardInk, drawnX, drawnW)
    onDrawnWChanged: term.noteSheet("s3", cardInk, drawnX, drawnW)
    id: paletteSheet
    leftInset: term.sideRef.width
    floating: false   // hangs from the bar, which carries its title — see barTitle
    title: term.sheetTitle
    glyph: term.sheetGlyph
    titleInk: term.sheetTitleInk
    glyphInk: term.sheetGlyphInk
    shown: cmdPalette.open
    fromTop: term.tabStripRef.height + term.crumbBarRef.height
    // Wider and taller than it was, because it is the keymap now as well
    // as the verbs — ninety-odd rows rather than fifty, read as a page.
    cardW: 620
    readonly property int rowH: 30
    // FOURTEEN, the go and send sheets' page. They are the same shape
    // hanging off the same bar and a page that is one row deeper on this
    // one is a sheet that does not quite match the others.
    readonly property int pageRows: 14
    // THE ROWS AND WHAT HOLDS THEM, AND NOTHING ELSE. The list runs from
    // 6 below the top of the card to 6 above the footer, so those twelve
    // and the footer's own height are the whole of what is not rows. A
    // spare 14 on the end here was 14 pixels the list had and the rows did
    // not — which is exactly one sliver of a fifteenth row, showing under
    // a page that says it holds fourteen.
    cardH: 12 + Math.max(1, Math.min(paletteSheet.pageRows,
                                     cmdPalette.shown.length))
                * paletteSheet.rowH + paletteFoot.height

    SelectBar {

      host: term
      view: paletteList
      index: cmdPalette.sel
      rowH: paletteSheet.rowH
    }

    ListView {
      id: paletteList
      anchors.top: parent.top
      anchors.topMargin: 6
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: paletteFoot.top
      anchors.bottomMargin: 6
      clip: true
      model: cmdPalette.shown
      currentIndex: cmdPalette.sel
      boundsBehavior: Flickable.DragAndOvershootBounds
      boundsMovement: Flickable.FollowBoundsBehavior
      onCurrentIndexChanged:
        paletteList.positionViewAtIndex(paletteList.currentIndex,
                                        ListView.Contain)
      ElasticScroll { view: paletteList; step: term.wheelStep }

      delegate: Item {
        id: cmdRow
        required property var modelData
        required property int index
        width: paletteList.width
        height: paletteSheet.rowH

        readonly property bool on: cmdRow.index === cmdPalette.sel

        // NO HOVER, and no fill of its own — see the bar above the view.
        // Sweeping the pointer across the list used to drag the cursor
        // with it, which is a second thing moving the selection while the
        // arrow keys are moving it too: reach for the mouse on the way to
        // something else and the row you had picked was gone. A click
        // still picks, because a click is a decision.
        MouseArea {
          anchors.fill: parent
          enabled: !cmdFlash.running
          onClicked: { cmdPalette.sel = cmdRow.index; cmdPalette.run(); }
        }

        FlashOver { flash: cmdFlash; index: cmdRow.index }

        Text {
          anchors.left: parent.left
          anchors.leftMargin: 16
          anchors.right: cmdKey.left
          anchors.rightMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          text: cmdRow.modelData.label
          elide: Text.ElideRight
          // ── TWO KINDS OF ROW, TWO INKS ──────────────────────────
          // A row that RUNS and a row that only tells you something are
          // different in kind, not in degree: one is a verb you can press
          // return on, the other is a key the window already answers to.
          // Full white for the verbs and the same white stepped back for
          // the rest, so the half of this list you can act on reads first
          // and the keymap around it stays legible without competing.
          //
          // The cursor is not in this: the bar under the row says where it
          // is, and inking the cursor's row as well said the same fact
          // twice and hid which kind of row it was.
          color: cmdRow.modelData.act ? Zenon.white
            : Qt.rgba(Zenon.white.r, Zenon.white.g, Zenon.white.b, 0.6)
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(16)
        }

        // The key it already had, so the palette teaches as well as does.
        KeyCap {
          id: cmdKey
          visible: cmdRow.modelData.key !== ""
          anchors.right: parent.right
          anchors.rightMargin: 16
          anchors.verticalCenter: parent.verticalCenter
          label: cmdRow.modelData.key
          fontSize: 12
        }
      }
    }

    // ── A LIST THIS LONG NEEDS TO SAY HOW LONG ───────────────────
    // Ninety-odd rows through a fourteen-row window, and the only thing
    // saying so was that the rows kept coming. The shared rail, placed the
    // way every other rail in this window is placed — 2px in from the
    // view it reports on, hidden outright when everything already fits,
    // which is what it does the moment a filter cuts the list to a page.
    //
    // It clears the key chips: they stop 16px from the card's edge and the
    // rail is 10 wide from 2, so the two never meet.
    ScrollRail {
      owner: term
      target: paletteList
      anchors.right: paletteList.right
      anchors.rightMargin: 2
      anchors.top: paletteList.top
      anchors.topMargin: 2
      anchors.bottom: paletteList.bottom
      anchors.bottomMargin: 2
    }

    Rectangle {
      anchors.bottom: paletteFoot.top
      anchors.left: parent.left
      anchors.right: parent.right
      height: 1
      color: Zenon.border
    }

    Item {
      id: paletteFoot
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
          text: cmdPalette.query !== "" ? cmdPalette.query
            : (cmdPalette.shown.length === 0 ? "nothing matches"
                                          : "type to filter")
          color: cmdPalette.query !== "" ? Zenon.sand : Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }

        // THE RUN CHIP ONLY WHEN THERE IS SOMETHING TO RUN. This list is
        // half keymap now, and a return chip standing over a row that is
        // the cursor key would have been an offer the palette cannot keep.
        Repeater {
          model: cmdPalette.runnable
            ? [["\u2191\u2193", "move"], ["\u21b5", "run"],
               ["esc", "close"]]
            : [["\u2191\u2193", "move"], ["esc", "close"]]

          delegate: Row {
            id: pfPair
            required property var modelData
            spacing: 5

            KeyCap {
              anchors.verticalCenter: parent.verticalCenter
              label: pfPair.modelData[0]
              fontSize: 11
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: pfPair.modelData[1]
              color: Zenon.muted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(13)
            }
          }
        }
      }
    }
  }
}

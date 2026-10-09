// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ── the settings panel ────────────────────────────────────────────
// What the hamburger at the end of the breadcrumb bar opens. Built like
// the right-click menu — one `shade` driving the whole arrival, a full-
// window catcher behind it so anywhere else dismisses it — because they
// are the same object with different contents, and a second set of
// animation numbers to keep in step would drift from the first.
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

Item {
  id: prefs
  // the terminus window (`term`, never `root` — see terminus-split notes)
  property var term: null
  readonly property alias prefsCol: prefsCol
  anchors.fill: parent
  z: 14
  // THE SHEET'S OWN ARRIVAL DECIDES THIS. It used to carry a `shade` that
  // faded the whole overlay on the menu's timing — which would now cut
  // the sheet off partway out, because a sheet leaves more slowly than a
  // menu card ever did. The sheet fades and slides itself; this only has
  // to still be there while it does.
  visible: prefsSheet.cardInk > 0.01

  property bool open: false

  // openFrom/toggleFrom stood here. They existed so the hamburger
  // could open this sheet without knowing what shape it was, and the
  // hamburger opens the window menu now — Settings is a row in it,
  // which sets `open` directly, the same way the palette always has.
  // Nothing was left calling either one.

  // ── ON THE PROPERTY, NOT IN THE OPENER ──────────────────────────
  // openFrom is the hamburger's way in and it is not the only one: the
  // palette's `settings` verb sets prefs.open outright, so anything hung
  // off the function is skipped for the door most people use. Whatever
  // sets the property gets this.
  //
  // Sorted here rather than once at startup because the two columns are as
  // wide as the sheet lets them be: a row's x is not settled until there
  // is a sheet to measure it against.
  onOpenChanged: {
    if (prefs.open) {
      term.prefOrder();
      // AT THE TOP, not wherever it was left. The panel is short enough to
      // read in one glance, so there is no place in it you were.
      term.prefCursor = 0;
    } else {
      term.prefCursor = -1;
    }
  }

  InputShield {
    keepTop: term.tabStripRef.height + term.crumbBarRef.height
    onClicked: { prefs.open = false; term.contentRef.forceActiveFocus(); }
  }

  // ── A SHEET, LIKE EVERY OTHER CARD IN THIS WINDOW ────────────────
  // It hung off the hamburger as a menu card, 292 pixels of settings in
  // one tall strip, positioned by arithmetic against the corner it came
  // out of and clamped to the window so it did not fall off the bottom.
  // It is a panel of settings, not a menu of verbs — and the sheet gives
  // it the width to be laid out rather than listed.
  //
  // The arrival, the title on the bar, the gap it opens in the bar's own
  // edge and the blur behind it all come with the shape.
  Sheet {
    backdrop: term.chromeRef   // frosted over it — see morpheus/Sheet
    splice: true
    onCardInkChanged: term.noteSheet("s1", cardInk, drawnX, drawnW)
    onDrawnXChanged: term.noteSheet("s1", cardInk, drawnX, drawnW)
    onDrawnWChanged: term.noteSheet("s1", cardInk, drawnX, drawnW)
    id: prefsSheet
    leftInset: term.sideRef.width
    floating: false   // hangs from the bar, which carries its title — see barTitle
    title: term.sheetTitle
    glyph: term.sheetGlyph
    titleInk: term.sheetTitleInk
    glyphInk: term.sheetGlyphInk
    shown: prefs.open
    fromTop: term.tabStripRef.height + term.crumbBarRef.height
    // 700, not 620: the two columns each hold a slider with a label and a
    // readout, and a PrefText whose field is whatever is left after its
    // label — the narrower the sheet, the less of a terminal command you
    // can see at once. The well caps it against the window either way, so
    // this is a ceiling rather than a width.
    cardW: 700
    cardH: prefsCol.implicitHeight

    // The card eats its own clicks. Without this, the gaps between rows
    // fall through to the catcher behind and dismiss the panel you were
    // reaching into.
    InputShield {}

    // ── IT SCROLLS WHEN THE WINDOW IS TOO SHORT FOR IT ──────────────
    // Every other sheet already caps itself and scrolls what will not fit:
    // the palette and the pickers count rows against a page, the previews
    // flick. This one asked for its full height and got whatever the well
    // would give it, so in a short window the bottom of the panel — the
    // terminal command, the session switches — was simply cut off with no
    // way to reach it.
    //
    // The card still ASKS for its natural height; the Sheet still caps that
    // against the window. What changed is what happens when the cap bites.
    Flickable {
      id: prefsScroll
      // the shell's wheel and touchpad feel, as every other sheet here
      ElasticScroll { view: prefsScroll; step: term.wheelStep }
      anchors.fill: parent
      clip: true
      contentWidth: width
      contentHeight: prefsCol.implicitHeight
      boundsBehavior: Flickable.StopAtBounds
      // Nothing to flick when it all fits, so a short panel does not drift
      // under the hand on a stray wheel notch.
      interactive: prefsScroll.contentHeight > prefsScroll.height

    // INSIDE THE SCROLLER, so it travels with the rows it is marking.
    // Left outside it the bar mapped its position through the content
    // item while sitting in the body, which agrees only while the panel
    // is scrolled to the top.
    // ── THE SELECTION, AS ONE BAR THAT MOVES ──────────────────────
    // The list sheets get theirs beside a view; this panel is two Columns
    // and has no view, so it carries its own. DECLARED BEFORE THE ROWS so
    // it draws beneath them, and a sibling of the Column rather than a
    // child, because a Column lays out what it holds and this is not a row.
    Rectangle {
      id: prefBar
      readonly property var cur: term.prefAt()
      visible: !!prefBar.cur
      color: Zenon.border

      // mapToItem rather than the row's own x and y: the rows live in two
      // different Columns inside a Row, so their coordinates are each
      // relative to a different parent and mean nothing here until they
      // are brought into this one.
      //
      // AND IT IS NOT A BINDING ON ITS OWN. mapToItem is a function call
      // over geometry, not a property read, so nothing tells it to run
      // again when the geometry moves — and the panel is still sliding in
      // when the cursor is first set. The bar came up one slot high and
      // snapped into place on the first Tab, because THAT changed `cur`.
      // So it is given the two things that do move to watch: the sheet's
      // arrival, which ramps 0 to 1 while the card travels, and the
      // column's height, which settles when the rows are laid out.
      readonly property var spot: (prefBar.cur
          && prefsSheet.cardInk >= 0 && prefsCol.height >= 0)
        ? prefBar.cur.mapToItem(prefsCol.parent, 0, 0) : null
      x: prefBar.spot ? prefBar.spot.x : 0
      y: prefBar.spot ? prefBar.spot.y : 0
      width: prefBar.cur ? prefBar.cur.width : 0
      height: prefBar.cur ? prefBar.cur.height : 0

      // Only the travel is animated. The size changes when the cursor
      // crosses between a 32px switch and a 34px slider, and easing two
      // pixels of height is a wobble rather than a movement.
      //
      // AND IT ANSWERS THE SAME SWITCH. This panel's cursor is not a
      // SelectBar — it is placed by mapToItem rather than by an index, so
      // it cannot be one — which meant the setting reached every sliding
      // cursor in the window except the one on the panel the setting is
      // ON. Gated here by hand for the same reason it exists there.
      Behavior on x {
        enabled: term.cursorSlide
        NumberAnimation { duration: Zenon.fast; easing.type: Zenon.travelEase }
      }
      Behavior on y {
        enabled: term.cursorSlide
        NumberAnimation { duration: Zenon.fast; easing.type: Zenon.travelEase }
      }
    }

    Column {
      id: prefsCol
      width: parent.width
      topPadding: 4
      bottomPadding: 10

      // ── TWO COLUMNS, BECAUSE THERE IS ROOM FOR TWO ──────────────
      // As a menu card hanging off the hamburger this was 292 pixels
      // wide and thirteen rows tall — a strip you scrolled your eye
      // down. A sheet is as wide as the window lets it be, so the
      // sections sit beside each other and the whole of it is one
      // glance. Split by SECTION rather than by row count: a heading
      // and the switches under it are one thing and do not get to be
      // in two places.
      Row {
        width: parent.width
        spacing: 26

        Column {
          width: (parent.width - parent.spacing) / 2

        SideHead { term: prefs.term; label: "VIEW"; first: true }

        // The three views as three buttons rather than as `v` pressed until
        // the right one comes round. While the window is split, columns is
        // not in the ring — six columns of listing in half a window each —
        // so it is shown refusing rather than quietly doing nothing.
        PrefSeg { term: prefs.term
          options: ["columns", "list", "grid"]
          current: term.viewMode
          allowed: term.viewRing
          onChose: (v) => term.setView(v)
        }

        // The two zooms are deliberately independent — the grid scales its
        // pictures and everything else scales its text — so the row says
        // which one it is holding rather than reading "zoom" and meaning
        // something different in each view.
        // The grid's own switch, named for what it turns off rather than for
        // the view it belongs to — there is nowhere else thumbnails are drawn.
        PrefRow { term: prefs.term
          label: "Thumbnails"
          on: term.thumbsOn
          onToggled: term.thumbsOn = !term.thumbsOn
        }

        PrefRow { term: prefs.term
          label: "Preview pane"
          on: term.previewOn
          onToggled: term.previewOn = !term.previewOn
        }

        PrefSlider { term: prefs.term
          label: term.viewMode === "grid" ? "Thumbnails" : "Text size"
          value: term.activeZoom
          from: term.zoomMin
          to: term.zoomMax
          neutral: term.viewMode === "grid" ? term.thumbZoomDefault : 1.0
          // the same notch ctrl+wheel over the listing uses, and the same
          // one ctrl+plus steps by
          wheelStep: 0.1
          readout: Math.round(term.activeZoom * 100) + "%"
          onMoved: (v) => term.setZoom(v)
        }

        SideHead { term: prefs.term; label: "LISTING" }

        PrefRow { term: prefs.term
          label: "Hidden files"
          hint: "."
          on: term.showHidden
          onToggled: term.showHidden = !term.showHidden
        }

        PrefRow { term: prefs.term
          label: "Disk usage"
          hint: ", u"
          on: term.usage
          onToggled: term.toggleUsage()
        }

        PrefRow { term: prefs.term
          label: "Confirm trash"
          on: term.confirmTrash
          onToggled: term.confirmTrash = !term.confirmTrash
        }

        PrefRow { term: prefs.term
          label: "Git status"
          hint: ", g"
          on: term.git
          onToggled: term.toggleGit()
        }

        // ACTION, not a switch. PrefRow draws a toggle because every other
        // row in this panel is one; this is a thing you DO once, so it wears
        // its verb where the switch would be and nothing is left lit
        // afterwards to suggest a state.
        PrefAction { term: prefs.term
          label: "Reset remembered views"
          verb: term.dirViewOrder.length > 0
            ? term.dirViewOrder.length + " kept" : "none"
          enabled: term.dirViewOrder.length > 0
          onTriggered: term.forgetDirViews()
        }

        // Beside the button that forgets them, because it is the same
        // fact said as a number: how many are kept at all.
        PrefSlider { term: prefs.term
          label: "Remember"
          value: term.dirViewCap
          from: 50
          to: 1000
          readout: term.dirViewCap + " dirs"
          onMoved: (v) => {
            term.dirViewCap = Math.round(v);
            term.trimDirViews();
          }
        }

        PrefRow { term: prefs.term
          label: "Remember per directory"
          on: term.perDirView
          onToggled: {
            term.perDirView = !term.perDirView;
            // Recorded on the way ON, so the directory you are standing in is
            // remembered from here rather than from the next one you walk
            // into — and applied at once, so turning it back on returns the
            // view this directory had rather than waiting for you to leave.
            if (term.perDirView) { term.rememberView(); term.applyDirView(); }
            term.viewSaveRef.restart();
          }
        }

        }

        Column {
          width: (parent.width - parent.spacing) / 2

        SideHead { term: prefs.term; label: "SORT"; first: true }

        // The column headings do this too, by clicking them — but only in
        // list view, and the grid and columns had no way to reach the order
        // at all except by learning `,` sequences.
        //
        // USAGE joins the ring only while the disk-usage mode is on, which
        // is the only time it means anything. Without it, turning the mode
        // on left all four buttons unlit and the panel looking broken.
        PrefSeg { term: prefs.term
          // TAG joins the ring only once something is tagged, on the
          // same reasoning as USAGE above: an order that cannot
          // distinguish any two rows is a button that does nothing.
          options: {
            const o = ["name", "kind", "size", "time"];
            if (term.usage) o.push("usage");
            if (term.anyTagged) o.push("tag");
            return o;
          }
          current: term.sortKey
          onChose: (v) => {
            // a second press on the key already in force turns it round,
            // exactly as clicking the heading twice does
            if (term.sortKey === v) term.sortDesc = !term.sortDesc;
            else { term.sortKey = v; term.sortDesc = false; }
          }
        }

        PrefRow { term: prefs.term
          label: "Natural order"
          on: term.naturalSort
          onToggled: term.naturalSort = !term.naturalSort
        }

        // Named for what you see rather than for the sort it rides on:
        // "Arrange by kind" would be a second control saying what the
        // ring above already says.
        PrefRow { term: prefs.term
          label: "Group headings"
          on: term.grouped
          // List view only — see root.grouped — so muted in the others
          enabled: term.viewMode === "list"
          onToggled: term.grouped = !term.grouped
        }

        PrefRow { term: prefs.term
          label: "Directories first"
          on: term.dirsFirst
          // No re-sort to ask for: the pane's `view` reads this, so
          // both halves rearrange themselves — see the note on Pane.raw.
          onToggled: term.dirsFirst = !term.dirsFirst
        }

        PrefRow { term: prefs.term
          label: "Descending"
          on: term.sortDesc
          onToggled: term.sortDesc = !term.sortDesc
        }

        SideHead { term: prefs.term; label: "WINDOW" }

        PrefRow { term: prefs.term
          label: "Sidebar"
          on: term.sidebar
          onToggled: term.toggleSidebar()
        }

        PrefRow { term: prefs.term
          label: "Recents in sidebar"
          on: term.recentsShown
          onToggled: { term.recentsShown = !term.recentsShown; term.viewSaveRef.restart(); }
        }

        PrefRow { term: prefs.term
          label: "Always show tabs"
          on: term.alwaysTabs
          onToggled: term.alwaysTabs = !term.alwaysTabs
        }

        PrefRow { term: prefs.term
          label: "Column headers"
          on: term.colHeadsOn
          onToggled: term.colHeadsOn = !term.colHeadsOn
        }

        PrefRow { term: prefs.term
          label: "Sliding cursor"
          on: term.cursorSlide
          onToggled: term.cursorSlide = !term.cursorSlide
        }

        PrefRow { term: prefs.term
          label: "Restore session"
          on: term.sessionReplay
          onToggled: {
            term.sessionReplay = !term.sessionReplay;
            term.viewSaveRef.restart();
          }
        }

        PrefRow { term: prefs.term
          label: "Split view"
          hint: "\\"
          on: term.dual
          onToggled: term.toggleDual()
        }

        // Empty is the default and says so: xdg-terminal-exec is what
        // runs when nothing is typed here, and oracle's Default Apps
        // keeps its list on the terminal chosen there — so the ghost
        // names that one rather than the mechanism.
        PrefText { term: prefs.term
          label: "Terminal"
          value: term.termCmd
          ghost: Oracle.terminal + " (Default Apps)"
          onCommitted: (v) => {
            term.termCmd = v.trim();
            term.viewSaveRef.restart();
          }
        }

        }
      }
    }
    }
  }
}

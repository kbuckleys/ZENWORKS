// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Its own file since 2026-10-08, out of TerminusWindow.qml, where it was an
// inline component. `term` is the terminus window; every place that makes
// one passes it (`term: root`).

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
  // the terminus window — passed in by whoever makes one. NOT `root`:
  // inside a delegate a property of that name shadowed the window's id
  // and bound to itself (2026-10-08)
  property var term: null
  id: headBar
  y: 0
  height: 22
  // the sidebar's ground, like the path bar above it — see root.chromeBg
  color: term.chromeBg
  // Below this the size and date columns are dropped and the name gets the
  // whole width — a half-width pane cannot carry three columns, and trying
  // ran "5.2 KiB" straight through the end of the filename. Matched by
  // EntryRow.showMeta, so the headings and the rows always agree.
  readonly property bool meta: headBar.width >= term.metaMinWidth
  // False on the pane the keyboard is NOT in. Search results only ever
  // replace the ACTIVE listing, so only the active half grows a WHERE column
  // — the other pane is still showing a directory and would have headed an
  // empty column with it.
  property bool live: true
  // The half this strip heads. Its arrows are that half's order, and a click
  // on it sorts that half — stepping into it first, because the window's
  // sort is the active half's.
  property var pane: term.act
  readonly property var frac:
    (term.searchMode !== "" && headBar.live) ? term.colFound : term.colPlain

  // The same pixel widths the rows use — see root.colWidths. Both read
  // it from one function so a heading cannot drift off the column it
  // names.
  readonly property var cols: term.colWidths(headBar.width - 24, headBar.frac)

  Row {
    anchors.fill: parent
    leftPadding: 12
    rightPadding: 12

    // THE FRACTIONS ARE OF THE INNER WIDTH, not of the whole row, and they
    // come from root.colPlain / root.colFound so the rows underneath cannot
    // disagree with the headings.
    //
    // A Row's padding comes out of the space its children have, and these
    // used to sum to 0.96 of the full width — which happened to leave about
    // enough for the 24px of padding and no more. Adding the KIND column
    // took them to a round 1.00 and the last one, MODIFIED, was pushed 24px
    // past the right edge: the "sunken" column. Subtracting the padding
    // first makes the arithmetic exact at any width, and makes the headings
    // line up with the cells under them by construction.
    ColHead { term: headBar.term
      pane: headBar.pane
      width: headBar.meta ? headBar.cols.name : (parent.width - 24)
      label: "NAME"
      sortKey: "name"
    }
    // Only while there are results to place. No sort key: the order of a
    // search is the order the search returned, and a heading that changed it
    // would be offering to re-rank the answer by the one field the ranking
    // was never about.
    ColHead { term: headBar.term
      pane: headBar.pane
      width: headBar.meta ? headBar.cols.where : 0
      visible: headBar.meta && headBar.frac.where > 0
      label: "WHERE"
    }
    // Sorting by kind arrived without a column to click, so it was the one
    // arrangement you could only reach through a menu or a two-key sequence.
    ColHead { term: headBar.term
      pane: headBar.pane
      width: headBar.meta ? headBar.cols.kind : 0
      visible: headBar.meta
      label: "KIND"
      sortKey: "kind"
      rightAlign: true
    }
    ColHead { term: headBar.term
      pane: headBar.pane
      width: headBar.meta ? headBar.cols.size : 0
      visible: headBar.meta
      // The heading says which question the column is answering: in the
      // usage mode it is no longer "how big is this file" but "how much of
      // this directory is this", and the bars under it are not sizes.
      label: term.usage ? "USAGE" : "SIZE"
      sortKey: term.usage ? "usage" : "size"
      rightAlign: true
    }
    ColHead { term: headBar.term
      pane: headBar.pane
      width: headBar.meta ? headBar.cols.time : 0
      visible: headBar.meta
      label: "MODIFIED"
      sortKey: "time"
      // Left, like the times below it.
    }
  }

  Rectangle {
    anchors.bottom: parent.bottom
    width: parent.width
    height: 1
    color: Zenon.border
  }
}

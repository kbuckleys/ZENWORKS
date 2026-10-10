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

Item {
  // the terminus window — passed in by whoever makes one. NOT `root`:
  // inside a delegate a property of that name shadowed the window's id
  // and bound to itself (2026-10-08)
  property var term: null
  id: sideHead
  property string label: ""
  // ── A RULE EACH SIDE, EXCEPT OVER THE FIRST ONE ───────────────────
  // The heading is fenced: one rule closing the group above it, one
  // opening its own. The topmost heading takes only the lower rule,
  // because the bar it hangs under already draws the line above it and
  // two of them a few pixels apart is a seam that looks like a mistake.
  //
  // WHICH ONE IS TOPMOST IS NOT FIXED. A group with nothing in it is not
  // drawn — no bookmarks, no BOOKMARKS — so `first` is passed down the
  // four of them as a cascade of emptiness tests at the call sites: Tags
  // is first when there are no bookmarks, Collections when there are
  // neither, and Collections is always drawn, which is why Disks never
  // has to ask.
  property bool first: false

  readonly property int rule: 1
  // Over the top rule, and it belongs to the group that just ended.
  readonly property int airAbove: 13
  // Between a rule and the word, on both sides, so the heading sits in
  // the middle of its own fence rather than against one side of it.
  readonly property int airIn: 7

  // ── THE ROW MEETS THE RULE, NOT THE GLYPH ────────────────────────
  // An earlier turn at this pushed the lower rule down into the first
  // row's top air so it sat hard against the glyph. It did close that
  // gap and it put the rule THROUGH the cursor: the fill starts at the
  // top of the row, eight pixels above where the line had been moved
  // to, so selecting the first bookmark drew a line across it.
  //
  // The rule is the head's last pixel and the row begins on the next
  // one, which is what makes the cursor's top edge and the rule a
  // single seam. The air between that seam and the glyph belongs to the
  // row — it is what centres a 15px glyph in 32px — and is not the
  // heading's to take.

  width: parent ? parent.width : 0
  // Measured off the parts rather than given as a number, so changing
  // the type size or either gap cannot leave the rules in the wrong
  // place — which is what a hand-tuned height got wrong twice before.
  // ROUNDED, because the text's implicit height is fractional and a
  // fractional height puts the lower rule across two pixel rows — half
  // of it under the cursor, which is exactly the seam this is for.
  // THE LEADING HEADING IS THE TOP BAR'S HEIGHT, so its rule is the same
  // line as the one under the tab strip (or the path bar, with one tab)
  // beside it — measured from the text it was a few pixels short, and the
  // two hairlines stepped at the seam (user, 2026-10-09).
  height: !visible ? 0
    : sideHead.first && term ? term.headH
    : Math.round((sideHead.first ? 0 : sideHead.airAbove + sideHead.rule)
      + sideHead.airIn + sideHeadText.height + sideHead.airIn + sideHead.rule)

  // Above the rows, because the lower rule is drawn over the first one's
  // top air — and that row draws a fill when it is the active one, which
  // is declared after this and would otherwise paint straight over the
  // line. BOOKMARKS lost its rule exactly that way whenever the bookmark
  // under it was the place you were standing.
  z: 1

  // Closing the group above. Absent on the first, which has none.
  // Edge to edge: inset, they read as underlines belonging to the word
  // rather than as the panel's own divisions.
  Rectangle {
    visible: !sideHead.first
    width: sideHead.width
    y: sideHead.airAbove
    height: sideHead.rule
    color: Zenon.border
  }

  // And opening this one, on the item's last pixel — so the first row,
  // and the cursor that fills it, begin on the very next one.
  Rectangle {
    width: sideHead.width
    y: sideHead.height - sideHead.rule
    height: sideHead.rule
    color: Zenon.border
  }

  Text {
    id: sideHeadText
    // 12, the panel's own left edge — where the GLYPH column starts, not
    // where the names do. A heading that is a title belongs at the edge
    // of the thing it is titling, with the rows indented under it by
    // their icons; indenting the title as well leaves the column with
    // nothing at its margin and the whole panel drifting right.
    // ── ON THE ICONS, NOT ON THE COLUMN THEY SIT IN ───────────────
    // 15 rather than 12. The glyph column starts at 12 and is 20 wide
    // with the glyph CENTRED in it, so no icon's ink actually begins at
    // 12 — measured off the rendered rows, the home, directory and disk
    // glyphs all start at 15 or 16. Aligning to the column is the tidy
    // answer on paper and visibly wrong on screen: the heading hangs a
    // few pixels left of everything it names.
    //
    // The cost of the optical answer is that it is tied to this type
    // size; a much larger glyph would start further in and want a
    // different number.
    //
    // The rules stay at 12. A separator that begins where the text does
    // leaves a notch at the panel's edge and stops being a separator.
    x: 15
    y: sideHead.first && term
       ? Math.round((sideHead.height - sideHead.rule - sideHeadText.height) / 2)
       : sideHead.airAbove + sideHead.rule + sideHead.airIn
    text: sideHead.label
    // ── A TITLE, NOT A FILING LABEL ─────────────────────────────────
    // It was 11px grey caps with 1.8 of letter-spacing, which is the
    // shape of a label on a drawer — small, shouted, and needing an
    // ornament beside it to be worth looking at at all. Two ornaments
    // were tried and both read as arbitrary, which was the wrong
    // problem: the text itself was the quiet part.
    //
    // 13px sentence case in the accent ink instead. Letter-spacing goes
    // with it — it exists to open up capitals and does nothing but
    // loosen a word that is already legible.
    // ── A MARK BEFORE IT, NOT A RULE AFTER IT ──────────────────────────
    // The heading was a word with a hairline running off it to the right
    // edge — "BOOKMARKS ————", the group's own underscore. That is a divider
    // doing a heading's job: it carries the eye ACROSS the column, away from
    // the rows the heading is announcing, and it is the loudest thing in a
    // panel whose whole point is the list under it. Taking it away left the
    // label correct and unfurnished.
    //
    // So the weight moved to the FRONT, where a heading's weight belongs: a
    // short cyan tick in the glyph column, the same column every row's icon
    // stands in, so the headings and the rows share one left edge and the
    // label starts where a row's label starts. It marks the group in the one
    // place the eye is already travelling down.
    // The ink the breadcrumb gives the step you are standing on. Cyan
    // is this window's "chosen" colour — it marks the active pane, the
    // cursor and the current row — and spending it on four headings
    // that are never chosen and never change made the sidebar compete
    // with the one thing in it that IS selected.
    // guarded: a window built in the background (TerminusManager.prebuild)
    // evaluates this once before `term` arrives
    color: term ? term.crumbInk : Zenon.muted
    font.family: Zenon.face
    font.weight: Font.Bold
    font.pixelSize: Zenon.px(13)
    // Back with the capitals, and for them: tracking is what stops a run
    // of caps reading as one shape. It went when the headings stopped
    // being capitals and returns with them.
    font.letterSpacing: 1.2
  }

}

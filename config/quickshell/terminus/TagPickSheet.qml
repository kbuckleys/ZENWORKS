// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ── tags ──────────────────────────────────────────────────────────
// A PICKER THAT HAPPENS TO MANAGE, which is the other way round from the
// bookmarks sheet beside it. The common act is "put a tag on these
// files", so that is what a bare Return does and that is why the card
// stays open afterwards: tagging comes in runs, and a card that closed
// on each would make three tags three trips.
//
// The list is the UNION of three things — the seven that come with a
// colour, whatever has been made by hand, and whatever is actually on a
// file. The third is not redundant: a tag written by another program, or
// one whose definition was lost, is on the disk and has to be reachable.
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
  id: tagPick
  // the terminus window (`term`, never `root` — see terminus-split notes)
  property var term: null
  anchors.fill: parent
  z: 13
  visible: opacity > 0.01
  opacity: tagPick.open ? 1 : 0
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
      duration: tagPick.open ? tagSheet.slideIn : tagSheet.slideOut
      easing.type: Zenon.ease
    }
  }

  property bool open: false
  property int sel: 0
  property string query: ""

  // WHAT IT WILL TAG, captured on the way in rather than read live.
  // acting() answers about the cursor, and the footer has to be able to
  // say "3 items" for the whole time the card is up — including after a
  // toggle has refreshed the listing underneath it.
  property var targets: []

  readonly property var counts: Tags.tally(term.tagMarks)

  readonly property var all: {
    const seen = ({});
    const out = [];
    const add = (name) => {
      if (name === "" || seen[name]) return;
      seen[name] = true;
      let on = tagPick.targets.length > 0;
      let some = false;
      for (let i = 0; i < tagPick.targets.length; ++i) {
        if (Tags.hasTag(term.tagMarks[tagPick.targets[i]], name)) some = true;
        else on = false;
      }
      out.push({
        name: name,
        ink: term.tagInk(name),
        count: tagPick.counts[name] || 0,
        // Three states, not two. A selection where SOME of the files
        // carry the tag is the case a checkbox cannot say, and it is
        // exactly the case where Return does something non-obvious —
        // see Tags.toggleAcross.
        on: on,
        partly: some && !on
      });
    };
    // Each of the seven in its place, under whatever it is called
    // now. Always seven rows: a default can be renamed but not
    // removed, so a slot never empties. Typing one of the original
    // names onto a file brings that name home — see the tag write.
    for (let i = 0; i < Tags.PRESETS.length; ++i) {
      const n = Tags.PRESETS[i].name;
      const now = term.tagGone[n];
      add(now === undefined ? n : now);
    }
    for (let j = 0; j < term.tagDefs.length; ++j) add(term.tagDefs[j].name);
    const tallied = Object.keys(tagPick.counts).sort();
    for (let k = 0; k < tallied.length; ++k) add(tallied[k]);
    return out;
  }

  // Ranked by the same scorer the file filter and the palette use.
  readonly property var rows: {
    const q = tagPick.query.trim().toLowerCase();
    const all = tagPick.all;
    if (q === "") return all;
    const hit = [];
    for (let i = 0; i < all.length; i++) {
      const sc = Terminus.fuzzyScore(all[i].name.toLowerCase(), q);
      if (sc >= 0) hit.push({ c: all[i], sc: sc, i: i });
    }
    hit.sort((a, b) => (b.sc - a.sc) || (a.i - b.i));
    const out = [];
    for (let i = 0; i < hit.length; i++) out.push(hit[i].c);
    return out;
  }

  // A NAME THAT DOES NOT EXIST YET IS AN OFFER, not an error. Typing a
  // new word and pressing Return should make that tag and put it on the
  // selection in one gesture — anything else means a separate "new tag"
  // verb for something the filter field has already been told.
  readonly property string fresh: {
    const q = Tags.normalise([tagPick.query])[0] || "";
    if (q === "") return "";
    for (let i = 0; i < tagPick.all.length; ++i)
      if (tagPick.all[i].name === q) return "";
    return q;
  }

  onQueryChanged: tagPick.sel = 0

  function ask() {
    tagPick.query = "";
    tagPick.sel = 0;
    tagPick.targets = term.acting().map((r) => r.path);
    tagPick.open = true;
  }

  function dismiss() {
    tagPick.open = false;
    term.contentRef.forceActiveFocus();
  }

  function step(d) {
    const n = tagPick.rows.length + (tagPick.fresh !== "" ? 1 : 0);
    if (n === 0) return;
    tagPick.sel = (tagPick.sel + d + n) % n;
    tagList.positionViewAtIndex(
      Math.max(0, tagPick.sel - (tagPick.fresh !== "" ? 1 : 0)),
      ListView.Contain);
  }

  // Index 0 is the offer when there is one, so everything below shifts.
  readonly property int offset: tagPick.fresh !== "" ? 1 : 0

  function chosen() {
    if (tagPick.offset === 1 && tagPick.sel === 0) return tagPick.fresh;
    const r = tagPick.rows[tagPick.sel - tagPick.offset];
    return r ? r.name : "";
  }

  function apply() {
    const name = tagPick.chosen();
    if (name === "") return;
    if (tagPick.targets.length === 0) { term.warn("nothing to tag"); return; }
    // A brand new name is DEFINED as well as applied, so it keeps its
    // place in the list after the filter is cleared.
    if (name === tagPick.fresh) {
      term.defineTag(name, "cyan");
      tagPick.query = "";
    }
    term.toggleTagFor(tagPick.targets, name);
  }

  // ── RENAMING IS ITS OWN MODE, ON THE ROW ──────────────────────
  // The filter field used to double as the name field: highlight a
  // tag, type the new name, ctrl+Return. It could not work, and the
  // reason is structural rather than a slip — typing the new name
  // RE-FILTERS the list by fuzzy-matching it, so the tag being renamed
  // drops out of `rows` and the "make a new tag" offer takes index 0.
  // chosen() then answers with that offer and rename() refuses. It
  // only ever went through if the new name happened to fuzzy-match the
  // old one and you arrowed back onto it.
  //
  // One field cannot be both "which tag" and "what to call it". The
  // filter stays a filter; renaming borrows the ROW, the way the
  // listing renames a file in place, and keys go to the name while it
  // is up. Nothing is dictated into two places at once.
  property string renaming: ""
  property string renameText: ""

  // ── A REFUSAL HAS TO LAND WHERE THE EYE IS ────────────────────
  // root.warn writes the status chip at the foot of the WINDOW, which
  // during a sheet is behind the scrim and a long way from the row
  // being argued about. Said in the footer instead, in place of the
  // hints, and gone again shortly after.
  property string gripe: ""

  function gripeAbout(t) { tagPick.gripe = t; gripeGo.restart(); }

  Timer { id: gripeGo; interval: 2400; onTriggered: tagPick.gripe = ""; }

  onOpenChanged: if (!tagPick.open) tagPick.gripe = "";

  function beginRename() {
    let name = tagPick.chosen();
    // ── THE OFFER IS NOT A TAG, BUT IT IS WHERE THE CURSOR SITS ──
    // Typing to FIND a tag puts the "make a new one" offer at the top
    // of the list, and the highlight defaults to it. Refusing there
    // and saying nothing is what made renaming look like it CREATED
    // tags: the keystrokes went to the filter instead, and the Return
    // that was meant to commit the new name made a tag out of it.
    //
    // So it falls to the first real row and MOVES the highlight onto
    // it, rather than renaming something the cursor was not on: what
    // is about to change is the row you can see turn into a field.
    if (name === "" || name === tagPick.fresh) {
      if (tagPick.rows.length === 0) {
        tagPick.gripeAbout("no tag to rename");
        return;
      }
      tagPick.sel = tagPick.offset;
      name = tagPick.rows[0].name;
    }

    tagPick.renaming = name;
    tagPick.renameText = name;
  }

  function commitRename() {
    const from = tagPick.renaming;
    const to = tagPick.renameText.trim();
    tagPick.renaming = "";
    tagPick.renameText = "";
    if (from === "" || to === "" || to === from) return;
    term.renameTag(from, to);
    // The filter was very likely how the tag was found, and the new
    // name has no reason to match it — leaving it on would hide the
    // thing that was just renamed.
    tagPick.query = "";
  }

  function cancelRename() {
    tagPick.renaming = "";
    tagPick.renameText = "";
  }

  // Takes it off everywhere — see root.dropTag for why a definition
  // cannot be dropped on its own, and why one of the seven cannot be
  // dropped at all.
  function drop() {
    const name = tagPick.chosen();
    if (name === "" || name === tagPick.fresh) return;
    if (term.presetSlot(name) !== "") {
      tagPick.gripeAbout(name + " is a default tag");
      return;
    }
    term.dropTag(name);
    tagPick.sel = Math.max(0, tagPick.sel - 1);
  }

  InputShield { keepTop: term.tabStripRef.height + term.crumbBarRef.height; onClicked: tagPick.dismiss() }

  Sheet {
    backdrop: term.chromeRef   // frosted over it — see morpheus/Sheet
    splice: true
    onCardInkChanged: term.noteSheet("s8", cardInk, drawnX, drawnW)
    onDrawnXChanged: term.noteSheet("s8", cardInk, drawnX, drawnW)
    onDrawnWChanged: term.noteSheet("s8", cardInk, drawnX, drawnW)
    id: tagSheet
    leftInset: term.sideRef.width
    floating: false   // hangs from the bar, which carries its title — see barTitle
    title: term.sheetTitle
    glyph: term.sheetGlyph
    titleInk: term.sheetTitleInk
    glyphInk: term.sheetGlyphInk
    shown: tagPick.open
    fromTop: term.tabStripRef.height + term.crumbBarRef.height
    // As wide as the key hints along its foot need, which is the widest
    // thing in it — a fixed 720 left seven short names in a wide card.
    cardW: Math.max(460, tagHints.implicitWidth + 48)
    readonly property int rowH: 32
    readonly property int pageRows: 12
    cardH: 12 + Math.max(1, Math.min(tagSheet.pageRows,
                                     tagPick.rows.length + tagPick.offset))
                * tagSheet.rowH + tagFoot.height

    SelectBar {

      host: term
      view: tagList
      index: Math.max(0, tagPick.sel - tagPick.offset)
      rowH: tagSheet.rowH
      on: tagPick.rows.length > 0 && tagPick.sel >= tagPick.offset
    }

    // The offer, above the list rather than in it: it is not one of the
    // tags, it is the thing that would make one.
    Item {
      id: tagNew
      anchors.top: parent.top
      anchors.topMargin: 6
      anchors.left: parent.left
      anchors.right: parent.right
      height: tagPick.fresh !== "" ? tagSheet.rowH : 0
      visible: tagPick.fresh !== ""

      Rectangle {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        radius: Zenon.windowRadius
        color: tagPick.sel === 0
          ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.16)
          : "transparent"
      }

      Text {
        x: 16
        width: 22
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
        text: "\uF067"
        color: Zenon.cyan
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(14)
      }

      Text {
        anchors.left: parent.left
        anchors.leftMargin: 46
        anchors.verticalCenter: parent.verticalCenter
        text: "make \u201c" + tagPick.fresh + "\u201d"
        color: Zenon.white
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(17)
      }

      MouseArea {
        anchors.fill: parent
        onClicked: { tagPick.sel = 0; tagPick.apply(); }
      }
    }

    ListView {
      id: tagList
      anchors.top: tagNew.bottom
      anchors.topMargin: 6
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: tagFoot.top
      anchors.bottomMargin: 6
      clip: true
      model: tagPick.rows
      currentIndex: Math.max(0, tagPick.sel - tagPick.offset)
      boundsBehavior: Flickable.DragAndOvershootBounds
      boundsMovement: Flickable.FollowBoundsBehavior
      ElasticScroll { view: tagList; step: term.wheelStep }

      delegate: Item {
        id: tagRow
        required property var modelData
        required property int index
        width: tagList.width
        height: tagSheet.rowH

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.MiddleButton
          onClicked: (m) => {
            tagPick.sel = tagRow.index + tagPick.offset;
            if (m.button === Qt.MiddleButton) tagPick.drop();
            else tagPick.apply();
          }
        }

        // The colour IS the glyph. A tag has no icon of its own and a
        // generic one on every row would be a column of identical
        // shapes where the one distinguishing mark already lives.
        Text {
          id: tagDot
          x: 16
          width: 22
          horizontalAlignment: Text.AlignHCenter
          anchors.verticalCenter: parent.verticalCenter
          text: "\uF02B"
          color: tagRow.modelData.ink
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(15)
        }

        // The row IS the name field while this one is being renamed —
        // see tagPick.renaming. Cyan and a caret, so which row is
        // taking the typing is never in question.
        readonly property bool editing: tagPick.renaming !== ""
          && tagPick.renaming === tagRow.modelData.name

        Text {
          id: tagName
          anchors.left: tagDot.right
          anchors.leftMargin: 14
          anchors.right: tagState.left
          // room for the count that follows the name
          anchors.rightMargin: 12 + tagCount.implicitWidth + 10
          anchors.verticalCenter: parent.verticalCenter
          text: tagRow.editing ? tagPick.renameText : tagRow.modelData.name
          elide: Text.ElideRight
          color: tagRow.editing ? Zenon.cyan : Zenon.white
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(17)
        }

        Rectangle {
          visible: tagRow.editing
          x: tagName.x + Math.min(tagName.contentWidth + 2, tagName.width)
          anchors.verticalCenter: parent.verticalCenter
          width: 1
          height: 19
          color: Zenon.cyan
        }

        // Whether the SELECTION carries it, then how many files do.
        // Two different questions and the first one is why the card is
        // open, so it is the one that gets a mark rather than a number.
        Text {
          id: tagState
          anchors.right: parent.right
          anchors.rightMargin: 16
          anchors.verticalCenter: parent.verticalCenter
          text: tagRow.modelData.on ? "\uF00C"
            : (tagRow.modelData.partly ? "\uF068" : "")
          color: tagRow.modelData.on ? Zenon.cyan : Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }

        // BESIDE THE NAME, not at the card's far edge. Out there a lone
        // "1" sat half a card away from the tag it counted, and read as
        // belonging to nothing. Hidden while the row is being renamed,
        // when the name under it is moving.
        Text {
          id: tagCount
          x: tagName.x + Math.min(tagName.contentWidth, tagName.width) + 10
          anchors.verticalCenter: parent.verticalCenter
          visible: !tagRow.editing
          text: tagRow.modelData.count > 0
            ? String(tagRow.modelData.count) : ""
          color: Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
      }
    }

    Rectangle {
      anchors.bottom: tagFoot.top
      anchors.left: parent.left
      anchors.right: parent.right
      height: 1
      color: Zenon.border
    }

    Item {
      id: tagFoot
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      height: 34

      Text {
        anchors.centerIn: parent
        visible: tagPick.gripe !== ""
        text: tagPick.gripe
        color: Zenon.red
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(14)
      }

      Row {
        id: tagHints
        anchors.centerIn: parent
        spacing: 12
        visible: tagPick.gripe === ""

        Text {
          anchors.verticalCenter: parent.verticalCenter
          rightPadding: 2
          text: tagPick.query !== "" ? tagPick.query
            : (tagPick.targets.length === 1 ? "1 item"
               : tagPick.targets.length + " items")
          color: tagPick.query !== "" ? Zenon.sand : Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(14)
        }

        Repeater {
          // The keys that are actually bound. `x` was advertised here
          // while Delete was what the router listened for — a hint bar
          // is documentation and documentation that lies is worse than
          // none.
          model: [["\u21b5", "tag"], ["\u21e7\u21b5", "tag & close"],
                  ["alt r", "rename"], ["\u2191\u2193", "move"],
                  ["del", "remove"], ["esc", "close"]]
          delegate: Row {
            required property var modelData
            spacing: 5
            KeyCap { label: modelData[0] }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: modelData[1]
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

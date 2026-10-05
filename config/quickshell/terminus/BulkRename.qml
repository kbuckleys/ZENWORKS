// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE BATCH RENAME — terminus' card, shared. Terminus opens it on the rows
// you are acting on; picasso's viewer on the marked pictures. It edits
// names and nothing else: what it hands back is the list of moves, and the
// holder runs them (terminus.js bulkRenameApply, which cannot destroy a file).
//
//     BulkRename {
//       host: root; topInset: …; leftInset: …
//       onRenamed: (moves) => …     // [[from, to], …]
//       onClosed: …                 // the keyboard back where it was
//     }
//     bulk.begin(names, paths)
//
// ── bulk rename ───────────────────────────────────────────────────
// Forty names, edited where the forty files are.
//
// Two columns and nothing else: what a thing is called now, and what it
// would be called. The pattern field above them is the reason this exists
// at all — "replace .JPEG with .jpg across all of them" is one gesture,
// and the per-row fields are there for the handful the pattern got wrong.
//
// NOTHING IS APPLIED UNTIL THE BUTTON. The rules are checked live and
// written on the offending row, so an empty name or two files that would
// end up with the same name is something you see before you commit rather
// than a refusal afterwards.

import QtQuick
import "../morpheus"
import "terminus.js" as Terminus

Rectangle {
  id: bulk
  // what the card frosts over (see morpheus/Sheet), from the host
  property Item backdrop: null

  // ── WHAT THE HOLDER SAYS ──────────────────────────────────────────────
  // The window it is in: SelectBar's and the rail's host. Where the card
  // hangs from (the top bars' height) and how far in it starts (a sidebar),
  // the scrim, the wheel's step, and what the bar above it says.
  property var host: null
  property real topInset: 0
  property real leftInset: 0
  property color scrim: Qt.rgba(0, 0, 0, 0.55)
  property real wheelStep: 120
  // what a thing being renamed is called — "item", "picture"
  property string noun: "item"
  property string title: bulk.names.length === 1 ? "Rename 1 " + bulk.noun
    : "Rename " + bulk.names.length + " " + bulk.noun + "s"
  property string glyph: "\uEC61"
  property color titleInk: Zenon.white
  property color glyphInk: Zenon.cyan
  // HUNG FROM THE HOLDER'S BAR rather than floating with a title of its
  // own — for a holder whose bar carries the sheet's name (terminus). The
  // card's arrival and where it is drawn, so that bar can go dark with it
  // and open its hairline over it.
  property bool hangs: false
  readonly property real cardInk: bulkSheet.cardInk
  readonly property real drawnX: bulkSheet.drawnX
  readonly property real drawnW: bulkSheet.drawnW
  // The renames, as [[from path, to path], …] — or [] when no name changed.
  // The holder runs them (terminus.js bulkRenameApply), as a job of its own.
  signal renamed(var moves)
  // The card has gone; the keyboard is the holder's again.
  signal closed()

  // ── bulk rename ─────────────────────────────────────────────────────────
  // It used to open $EDITOR in a terminal with one name per line. That is a
  // good way to rename forty files and a poor way to find out you cannot:
  // the window was somewhere else, the rules were only checked after you had
  // closed it, and the whole feature depended on having an editor configured.
  // The editing happens in the card below now — see `bulk`.
  property var names: []
  // What they WOULD be called. Replaced whole rather than written into: a QML
  // property only reports a change when the reference changes, so mutating the
  // array in place left every row showing what it showed before.
  property var edits: []
  // Where each of them IS, row for row — see bulkRenameApply for why the
  // names alone, taken in cwd, renamed the wrong files.
  property var paths: []

  // Opened on these: their names now, and where each of them is.
  function begin(names, paths) {
    if (!names || names.length === 0) return;
    bulk.names = names.slice();
    bulk.paths = paths.slice();
    bulk.edits = bulk.names.slice();
    bulk.history = [];
    bulk.open = true;
  }


  function setEdit(i, text) {
    if (i < 0 || i >= bulk.edits.length) return;
    if (bulk.edits[i] === text) return;
    const next = bulk.edits.slice();
    next[i] = text;
    bulk.edits = next;
  }

  // Find-and-replace across the whole set, from the ORIGINAL names.
  //
  // From the originals rather than from what is on screen, so running it twice
  // is the same as running it once — a replace that fed on its own output
  // turned "a-a" into "b-b" and then into "c-c" as you typed. The cost is that
  // it discards hand edits, which is why it is a button and not a live
  // binding: an edit you made by hand should not evaporate because the caret
  // moved through the pattern field.
  // How the two pattern fields are read, and how much of the name they touch.
  // Both live on root rather than on the card so the transforms below can read
  // them without knowing anything about where the buttons are.
  property bool regex: false
  property bool stemOnly: true

  // ── the three modes ─────────────────────────────────────────────────────
  // Finder's split, and it is the right one: replace EDITS a name, add
  // DECORATES it, format REPLACES it outright. Those are three different
  // intentions about the old name — keep most of it, keep all of it, keep
  // none of it — and they were previously spread across one field pair and
  // six chips, where "add a prefix" was a find/replace with an empty find
  // that did nothing, and numbering was a verb you could not aim.
  //
  // One at a time, chosen from the dropdown left of the first field, so the
  // row below only ever shows the controls the chosen mode actually has.
  property string mode: "replace"     // replace | add | format
  // The one open dropdown, held as a REFERENCE rather than a name: opening a
  // second while the first is up would leave two lists over each other, and
  // a null here is also how a click anywhere else puts the open one away.
  property var bulkOpenDrop: null
  property string addWhere: "after"   // before | after
  property string fmtKind: "index"    // index | counter | date
  property string fmtWhere: "after"   // before | after
  property string fmtStart: "1"

  function applyAdd(text, where) {
    if (text === "") return;
    bulk.pushHistory();
    // From the ORIGINAL names, like replace and unlike the verbs: adding the
    // same prefix twice should mean the same as adding it once.
    bulk.edits = Terminus.bulkAddText(bulk.names, text, where,
                                          bulk.stemOnly);
  }

  function applyFormat(fmt) {
    if (fmt === "" && bulk.fmtKind !== "date") return;
    bulk.pushHistory();
    bulk.edits = Terminus.bulkFormat(bulk.names, fmt,
                                         bulk.fmtKind, bulk.fmtWhere,
                                         bulk.fmtStart, " ",
                                         bulk.stemOnly);
  }

  function applyReplace(find, repl) {
    if (find === "") return;
    bulk.pushHistory();
    bulk.edits = Terminus.bulkReplaceIn(bulk.names, find, repl,
                                            bulk.regex, bulk.stemOnly);
  }

  // ── the transforms ──────────────────────────────────────────────────────
  // These read what is ON SCREEN and write it back, unlike the replace above,
  // which always works from the original names. The difference is deliberate
  // and it is the difference between a pattern and a verb: a replace run twice
  // should mean the same as run once, and "lowercase" run after "number" has
  // to see the numbers or the two cannot be combined at all.
  function applyCase(mode) {
    bulk.pushHistory();
    bulk.edits = Terminus.bulkCase(bulk.edits, mode, bulk.stemOnly);
  }
  function applyTidy() {
    bulk.pushHistory();
    bulk.edits = Terminus.bulkTidy(bulk.edits, bulk.stemOnly);
  }
  function applyNumber(where) {
    bulk.pushHistory();
    bulk.edits = Terminus.bulkNumber(bulk.edits, 1, 0, where, " ",
                                         bulk.stemOnly);
  }
  // ── stepping back ───────────────────────────────────────────────────────
  // Every verb above is destructive of the one before it, and the useful way
  // to work is to try one, look at the rows, and try another. Without a way
  // back, "try" means "commit to", and the only escape was all the way to the
  // original names — which throws away the four presses that were right along
  // with the fifth that was not.
  //
  // A STACK rather than a single previous state, because the verbs are meant
  // to be stacked: number, then tidy, then lowercase is three presses and
  // stepping back through them one at a time is the same three in reverse.
  property var history: []

  function pushHistory() {
    const h = bulk.history.slice();
    h.push(bulk.edits.slice());
    // Twenty is far past what anyone stacks by hand, and it keeps a card that
    // is open on four thousand rows from quietly holding forty copies of them.
    while (h.length > 20) h.shift();
    bulk.history = h;
  }

  function undoEdit() {
    if (bulk.history.length === 0) return;
    const h = bulk.history.slice();
    bulk.edits = h.pop();
    bulk.history = h;
  }

  // Back to where the card opened, in one press, from however deep.
  function resetEdits() {
    if (bulk.edits.join("\u0000") !== bulk.names.join("\u0000"))
      bulk.pushHistory();
    bulk.edits = bulk.names.slice();
  }

  function commit() {
    const pairs = Terminus.bulkPairs(bulk.names, bulk.edits);
    // Refused rather than half-applied — see bulkIssues for the rules. The
    // card disables its own button on the same test, so getting here with a
    // null means something changed underneath it.
    if (pairs === null) return;
    bulk.open = false;
    bulk.closed();
    if (pairs.length === 0) { bulk.renamed([]); return; }
    const moves = [];
    for (let i = 0; i < bulk.paths.length; ++i) {
      const to = String(bulk.edits[i]).trim();
      if (to === bulk.names[i]) continue;
      const from = bulk.paths[i];
      moves.push([from, Terminus.joinPath(Terminus.dirname(from), to)]);
    }
    bulk.renamed(moves);
  }

  anchors.fill: parent
  z: 15
  visible: opacity > 0.01
  opacity: bulk.open ? 1 : 0
  // hung from a bar, the bar stays lit — it is the sheet's titlebar
  color: bulk.hangs ? "transparent" : bulk.scrim
  Rectangle {
    visible: bulk.hangs
    anchors.fill: parent
    anchors.topMargin: bulk.topInset
    color: bulk.scrim
  }
  // the sidebar beside the bar is not the titlebar, so it dims too
  Rectangle {
    visible: bulk.hangs
    width: bulk.leftInset
    height: bulk.topInset
    color: bulk.scrim
  }
  Behavior on opacity { NumberAnimation { duration: bulk.open ? bulkSheet.slideIn : bulkSheet.slideOut; easing.type: Zenon.ease } }

  property bool open: false
  // Which row has the keyboard. A delegate cannot be told to take focus
  // from outside, so it watches this and claims it for itself.
  property int at: 0
  // Bumped to ask row `at` to take the keyboard AGAIN even when `at` did
  // not change — tabbing out of the pattern fields and back into the row
  // it was already on has nothing to change but still has to move the
  // caret. A counter, for the reason openPulse is one.
  property int atPulse: 0

  function focusRow(i) {
    const n = bulk.names.length;
    if (n === 0) return;
    bulk.at = Math.max(0, Math.min(n - 1, i));
    bulk.atPulse++;
  }

  // Tab walks the whole card and wraps: find, replace, every row, back to
  // find. One ring rather than two halves that cannot reach each other,
  // which is what the pattern fields and the rows were before.
  function tabFromRow(i) {
    // Wraps to the PICKER, which is the top of the ring now that the
    // card opens on it.
    if (i < bulk.names.length - 1) bulk.focusRow(i + 1);
    else modeDrop.claim();
  }
  function backTabFromRow(i) {
    // replField, before this: the second of the two REPLACE fields, and
    // the only mode that has it. Backing out of row one in add or format
    // reached for a control that was not on screen.
    if (i > 0) bulk.focusRow(i - 1);
    else bulk.tailField().claim();
  }

  // ── THE WHOLE ROW OF CONTROLS, IN ORDER ───────────────────────
  // Every control the showing mode has, not just its text fields. The
  // secondary pickers — before/after, Index/Counter/Date, the start
  // number — were reachable by pointer only, which made the card half
  // keyboard-driven: Tab walked straight past the thing you were about
  // to set.
  //
  // Per mode, because only one mode's controls are on screen at a time
  // and a hidden control cannot take focus — tabbing into one reads as
  // Tab doing nothing at all.
  function ring() {
    if (bulk.mode === "add")
      return [modeDrop, addField, addWhere];
    if (bulk.mode === "format")
      return bulk.fmtKind === "date"
        ? [modeDrop, fmtKind, fmtField, fmtWhere]
        : [modeDrop, fmtKind, fmtField, fmtWhere, fmtStart];
    return [modeDrop, findField, replField];
  }

  function focusFrom(cur, dir) {
    const r = bulk.ring();
    let i = -1;
    for (let k = 0; k < r.length; ++k) if (r[k] === cur) { i = k; break; }
    if (i < 0) { r[0].claim(); return; }
    const next = i + dir;
    // Off either end is into the ROWS, which are the other half of this
    // card's ring — tabFromRow brings it back round.
    if (next >= r.length) { bulk.focusRow(0); return; }
    if (next < 0) { bulk.focusRow(bulk.names.length - 1); return; }
    r[next].claim();
  }

  // The last control before the rows — read off the ring rather than
  // named, so adding a control to a mode does not need saying twice.
  function tailField() {
    const r = bulk.ring();
    return r[r.length - 1];
  }

  // What is wrong with each proposed name, from the same function the
  // commit gate reads — see Terminus.bulkIssues.
  readonly property var issues:
    Terminus.bulkIssues(bulk.names, bulk.edits)
  readonly property bool sound: {
    for (let i = 0; i < bulk.issues.length; ++i)
      if (bulk.issues[i] !== "") return false;
    return true;
  }
  readonly property int changes: {
    let n = 0;
    for (let i = 0; i < bulk.names.length; ++i)
      if (bulk.edits[i] !== bulk.names[i]) n++;
    return n;
  }

  function dismiss() {
    bulk.open = false;
    bulk.closed();
  }

  onOpenChanged: {
    // Whatever was hanging open when the card went away does not come
    // back with it.
    bulk.bulkOpenDrop = null;
    if (!bulk.open) return;
    bulk.at = 0;
    findField.text = "";
    replField.text = "";
    addField.text = "";
    fmtField.text = "";
    bulkClaim.tries = 0;
    bulkClaim.restart();
  }

  // Switching mode moves the caret with it. The field you are looking at
  // having the keyboard is the whole reason the card claims focus at all.
  Connections {
    target: bulk
    function onModeChanged() {
      if (!bulk.open) return;
      bulkClaim.tries = 0;
      bulkClaim.restart();
    }
  }

  // ASK UNTIL IT HAS IT. The card is animating in from opacity 0 when the
  // first request goes out, and forceActiveFocus() on an item the scene
  // has not placed yet is silently dropped — the same trap the rename
  // field and the create prompt both carry a retry for.
  Timer {
    id: bulkClaim
    interval: 40
    repeat: true
    property int tries: 0
    onTriggered: {
      if (!bulk.open || modeDrop.focused
          || bulkClaim.tries++ > 12) {
        bulkClaim.stop();
        return;
      }
      bulkKeys.forceActiveFocus();
      // AND THE FIND FIELD WITHIN IT. It used to be the first name row,
      // on the reasoning that a row is where you would start typing —
      // but the card's own verb is the pattern at the top, and landing in
      // row one meant reaching for the mouse or tabbing backwards to use
      // it. Editing a single name by hand is what the in-place rename is
      // for; this card is open because the pattern is what you wanted.
      modeDrop.claim();
    }
  }

  InputShield { keepTop: bulk.topInset; onClicked: bulk.dismiss() }

  // Escape from anywhere in the card, including from inside a field that
  // has not handled it — so there is always one key that gets you out.
  FocusScope {
    id: bulkKeys
    anchors.fill: parent
    // Escape from anywhere in the card, and nothing else out of it.
    //
    // The fields are deeper than this, so they see their own keys first
    // and this only ever gets what they did not want — which must not
    // travel on to the listing's key handler. Before this, a key the
    // pattern fields ignored acted on the rows behind the card.
    Keys.onPressed: (e) => {
      e.accepted = true;
      if (e.key === Qt.Key_Escape) bulk.dismiss();
    }

    Sheet {
      backdrop: bulk.backdrop   // frosted over it — see morpheus/Sheet
      id: bulkSheet
      leftInset: bulk.leftInset
      floating: !bulk.hangs
      title: bulk.title
      glyph: bulk.glyph
      titleInk: bulk.titleInk
      glyphInk: bulk.glyphInk
      shown: bulk.open
      fromTop: bulk.topInset
      cardW: 760
      cardH: bulkCol.implicitHeight

      Column {
        id: bulkCol
        width: parent.width

        // The caption band stood here. It is the floating card's own
        // header now — see Sheet.floating, which draws the title and glyph.

        // ── the pattern ───────────────────────────────────────
        // Return in either field applies it. A BUTTON rather than a live
        // binding: the replace runs from the original names, so making it
        // live would wipe a hand edit every time the caret moved through
        // the pattern.
        Item {
          id: patRow
          width: parent.width
          height: 46
          // Lifted as a WHOLE while any of its dropdowns is open. Giving
          // the list its own z is not enough: z only orders an item among
          // its siblings, and the list's siblings are inside patRow while
          // the things it has to cover are the rows below patRow.
          z: (modeDrop.expanded || addWhere.expanded || fmtKind.expanded
              || fmtWhere.expanded) ? 60 : 0

          // Every mode's controls live between the dropdown and the
          // button, so the row keeps one shape whichever mode is showing
          // and the button never moves when you switch.
          readonly property real innerL: 16 + modeDrop.width + 8
          readonly property real innerR: patRow.width - 16 - applyBtn.width - 8
          readonly property real innerW: Math.max(80, patRow.innerR - patRow.innerL)

          BulkDrop {

            host: bulk
            id: modeDrop
            overlay: dropLayer
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            options: [["replace", "Replace Text"],
                      ["add",     "Add Text"],
                      ["format",  "Format"]]
            value: bulk.mode
            onPicked: (v) => bulk.mode = v
            // Forward into whichever mode is now showing, back to the
            // last row — the picker is the top of the ring.
            onTabbed: bulk.focusFrom(modeDrop, 1)
            onBackTabbed: bulk.focusFrom(modeDrop, -1)
          }

          // ── replace text ─────────────────────────────────────
          // Return in either field applies it. A BUTTON rather than a
          // live binding: the replace runs from the original names, so
          // making it live would wipe a hand edit every time the caret
          // moved through the pattern.
          Item {
            visible: bulk.mode === "replace"
            x: patRow.innerL
            width: patRow.innerW
            height: parent.height
            readonly property real cell: Math.max(50, (width - 22) / 2)

            BulkField {
              id: findField
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: parent.cell
              ghost: "find"
              onAccepted: bulk.applyReplace(findField.text, replField.text)
              onTabbed: bulk.focusFrom(findField, 1)
              onBackTabbed: bulk.focusFrom(findField, -1)
            }

            Text {
              id: patArrow
              anchors.left: findField.right
              anchors.leftMargin: 8
              anchors.verticalCenter: parent.verticalCenter
              width: 14
              horizontalAlignment: Text.AlignHCenter
              text: "\u2192"
              color: Zenon.muted
              font.family: Zenon.face
              font.pixelSize: 15
            }

            BulkField {
              id: replField
              anchors.left: patArrow.right
              anchors.leftMargin: 8
              anchors.verticalCenter: parent.verticalCenter
              width: parent.cell
              ghost: "replace with"
              onAccepted: bulk.applyReplace(findField.text, replField.text)
              onTabbed: bulk.focusFrom(replField, 1)
              onBackTabbed: bulk.focusFrom(replField, -1)
            }
          }

          // ── add text ─────────────────────────────────────────
          Item {
            visible: bulk.mode === "add"
            x: patRow.innerL
            width: patRow.innerW
            height: parent.height

            BulkField {
              id: addField
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Math.max(60, parent.width - addWhere.width - 8)
              ghost: "text to add"
              onAccepted: bulk.applyAdd(addField.text, bulk.addWhere)
              onTabbed: bulk.focusFrom(addField, 1)
              onBackTabbed: bulk.focusFrom(addField, -1)
            }

            BulkDrop {

              host: bulk
              id: addWhere
            overlay: dropLayer
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              options: [["before", "before name"], ["after", "after name"]]
              value: bulk.addWhere
              onPicked: (v) => bulk.addWhere = v
              onTabbed: bulk.focusFrom(addWhere, 1)
              onBackTabbed: bulk.focusFrom(addWhere, -1)
            }
          }

          // ── format ───────────────────────────────────────────
          // The one mode that DISCARDS the old name, which is why it
          // asks for the most: what the new name is, what distinguishes
          // the rows, which end that goes on, and where counting starts.
          Item {
            visible: bulk.mode === "format"
            x: patRow.innerL
            width: patRow.innerW
            height: parent.height

            BulkDrop {

              host: bulk
              id: fmtKind
            overlay: dropLayer
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              options: [["index",   "Name and Index"],
                        ["counter", "Name and Counter"],
                        ["date",    "Name and Date"]]
              value: bulk.fmtKind
              onPicked: (v) => bulk.fmtKind = v
              onTabbed: bulk.focusFrom(fmtKind, 1)
              onBackTabbed: bulk.focusFrom(fmtKind, -1)
            }

            BulkField {
              id: fmtField
              anchors.left: fmtKind.right
              anchors.leftMargin: 8
              anchors.verticalCenter: parent.verticalCenter
              width: Math.max(50, parent.width - fmtKind.width
                      - fmtWhere.width - (fmtStart.visible ? fmtStart.width + 8 : 0)
                      - 24)
              ghost: "custom format"
              onAccepted: bulk.applyFormat(fmtField.text)
              onTabbed: bulk.focusFrom(fmtField, 1)
              onBackTabbed: bulk.focusFrom(fmtField, -1)
            }

            BulkDrop {

              host: bulk
              id: fmtWhere
            overlay: dropLayer
              anchors.right: fmtStart.visible ? fmtStart.left : parent.right
              anchors.rightMargin: fmtStart.visible ? 8 : 0
              anchors.verticalCenter: parent.verticalCenter
              options: [["before", "before name"], ["after", "after name"]]
              value: bulk.fmtWhere
              onPicked: (v) => bulk.fmtWhere = v
              onTabbed: bulk.focusFrom(fmtWhere, 1)
              onBackTabbed: bulk.focusFrom(fmtWhere, -1)
            }

            BulkField {
              id: fmtStart
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: 58
              // A date has nothing to count from.
              visible: bulk.fmtKind !== "date"
              ghost: "start"
              // NOT bound to bulkFmtStart, written to it: a two-way
              // binding on a field you are typing in fights the caret.
              onTextChanged: bulk.fmtStart = fmtStart.text
              onAccepted: bulk.applyFormat(fmtField.text)
              onTabbed: bulk.focusFrom(fmtStart, 1)
              onBackTabbed: bulk.focusFrom(fmtStart, -1)
            }
          }

          DialogButton {
            id: applyBtn
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            label: bulk.mode === "replace" ? "Replace"
              : bulk.mode === "add" ? "Add" : "Format"
            ink: Zenon.cyan
            ready: bulk.mode === "replace" ? findField.text !== ""
              : bulk.mode === "add" ? addField.text !== ""
              : (fmtField.text !== "" || bulk.fmtKind === "date")
            onClicked: {
              if (bulk.mode === "replace")
                bulk.applyReplace(findField.text, replField.text);
              else if (bulk.mode === "add")
                bulk.applyAdd(addField.text, bulk.addWhere);
              else
                bulk.applyFormat(fmtField.text);
            }
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: Zenon.border
        }

        // ── the verbs ─────────────────────────────────────────
        // A find and a replace answer "change this into that", which is
        // one of the things batch renaming is for and not the common one.
        // The rest — put these in order, make the case consistent, get the
        // underscores out — are not patterns at all, they are the same
        // edit applied to every row, and doing them through find/replace
        // means writing a regular expression to say "lowercase".
        //
        // They stack: each reads the rows as they stand, so numbering and
        // then tidying is two presses. Reset goes back to the names the
        // card opened with, because a stack of verbs needs a bottom.
        Item {
          width: parent.width
          height: 42

          Row {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            BulkVerb { label: "abc";  onClicked: bulk.applyCase("lower") }
            BulkVerb { label: "ABC";  onClicked: bulk.applyCase("upper") }
            BulkVerb { label: "Abc";  onClicked: bulk.applyCase("title") }
            BulkVerb { label: "tidy"; onClicked: bulk.applyTidy() }
            BulkVerb { label: "1 ·";  onClicked: bulk.applyNumber("prefix") }
            BulkVerb { label: "· 1";  onClicked: bulk.applyNumber("suffix") }
          }

          Row {
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            // Two switches rather than two more verbs: they change what
            // every button above MEANS rather than doing anything
            // themselves, and a thing that stays on has to look like it.
            // Written out rather than symbolised. There is room, and
            // ".*" meaning "regular expression" is a thing you either
            // already know or cannot guess.
            BulkVerb {
              label: "keep .ext"
              on: bulk.stemOnly
              onClicked: bulk.stemOnly = !bulk.stemOnly
            }
            BulkVerb {
              label: "regex"
              on: bulk.regex
              onClicked: bulk.regex = !bulk.regex
            }
            BulkVerb {
              label: "undo"
              // Dimmed rather than hidden when there is nothing to undo:
              // a button that comes and goes moves the two beside it.
              dim: bulk.history.length === 0
              onClicked: bulk.undoEdit()
            }
            BulkVerb {
              label: "reset"
              dim: bulk.edits.join("\u0000") === bulk.names.join("\u0000")
              onClicked: bulk.resetEdits()
            }
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: Zenon.border
        }

        // ── the two columns ───────────────────────────────────
        Rectangle {
          width: parent.width
          height: 22
          color: Zenon.headBg

          Text {
            x: 46
            width: (parent.width - 60) * 0.42
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            text: "NOW"
            color: Zenon.muted
            font.family: Zenon.faceFixed
            font.pixelSize: 12
          }

          Text {
            x: 46 + (parent.width - 60) * 0.42 + 12
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            text: "TO"
            color: Zenon.muted
            font.family: Zenon.faceFixed
            font.pixelSize: 12
          }

          Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Zenon.border
          }
        }

        Item {
          width: parent.width
          // Sized to what it holds, up to the room the card has left. A
          // fixed height left a band of empty card under three names and
          // could not show thirty.
          height: Math.max(34, Math.min(bulkList.contentHeight,
            bulk.height - 100 - 26 - 46 - 1 - 22 - 52))

          SelectBar {

            host: bulk.host
            view: bulkList
            index: bulk.at
            rowH: 30
            on: bulk.names.length > 0
          }

          ListView {
            id: bulkList
            anchors.fill: parent
            clip: true
            model: bulk.names.length
            // The fields are live TextInputs holding unsaved text, and a
            // recycled delegate would carry one row's caret into another.
            reuseItems: false
            boundsBehavior: Flickable.DragAndOvershootBounds
            boundsMovement: Flickable.FollowBoundsBehavior

            // THE SHEETS WEAR THE LISTING'S BAND, and it is also what keeps the
            // wheel theirs. A Flickable at its end DECLINES the wheel, and a
            // declined wheel is offered to whatever is under the pointer next —
            // the listing behind the sheet, which scrolled along with it. The
            // overlay takes every notch, stretched or not. Every sheet list below
            // has one for the same reason.
            ElasticScroll { view: bulkList; step: bulk.wheelStep }

            delegate: Item {
              id: bulkRow
              required property int index
              width: bulkList.width
              height: 30

              readonly property string issue:
                bulk.issues[bulkRow.index] === undefined
                  ? "" : bulk.issues[bulkRow.index]
              readonly property bool moved:
                bulk.edits[bulkRow.index] !== bulk.names[bulkRow.index]

              // No cursor fill: that is the SelectBar beside the view.
              // The issue tint stays — it is about the ROW's text being
              // wrong, not about where the cursor is, and it has to be
              // visible on rows the cursor is nowhere near.
              Rectangle {
                anchors.fill: parent
                color: bulkRow.issue !== ""
                  ? Qt.rgba(Zenon.red.r, Zenon.red.g, Zenon.red.b, 0.10)
                  : "transparent"
              }

              // The row number, because the duplicate warning names one.
              Text {
                x: 0
                width: 40
                height: parent.height
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
                text: bulkRow.index + 1
                color: Zenon.muted
                font.family: Zenon.face
                font.pixelSize: 12
              }

              Text {
                id: wasName
                x: 46
                width: (parent.width - 60) * 0.42
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                text: bulk.names[bulkRow.index] || ""
                elide: Text.ElideMiddle
                // Dimmed once the row is going to change: the old name is
                // then history, and the eye should be on the new one.
                color: bulkRow.moved ? Zenon.muted : Zenon.keyInk
                font.family: Zenon.face
                font.pixelSize: 14
              }

              TextInput {
                id: toName

                cursorDelegate: Caret { field: toName }
                x: wasName.x + wasName.width + 12
                width: parent.width - x - 14 - (issueText.visible ? issueText.width + 10 : 0)
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                text: bulk.edits[bulkRow.index] || ""
                color: bulkRow.issue !== "" ? Zenon.red
                  : (bulkRow.moved ? Zenon.cyan : Zenon.white)
                selectionColor: Zenon.selBg
                selectedTextColor: Zenon.white
                font.family: Zenon.face
                font.weight: bulkRow.moved ? Font.Bold : Font.Medium
                font.pixelSize: 14
                clip: true

                onTextEdited: bulk.setEdit(bulkRow.index, toName.text)
                onActiveFocusChanged: if (activeFocus) bulk.at = bulkRow.index

                // Down and up walk the list, which is what a column of
                // fields is for; Tab walks the whole card, pattern fields
                // included. Return commits the batch from any of them, so
                // the common case never needs the pointer.
                Keys.onPressed: (e) => {
                  if (e.key === Qt.Key_Tab) {
                    e.accepted = true; bulk.tabFromRow(bulkRow.index); return;
                  }
                  if (e.key === Qt.Key_Backtab) {
                    e.accepted = true; bulk.backTabFromRow(bulkRow.index); return;
                  }
                }
                Keys.onDownPressed: (e) => {
                  e.accepted = true;
                  bulk.focusRow(bulkRow.index + 1);
                }
                Keys.onUpPressed: (e) => {
                  e.accepted = true;
                  bulk.focusRow(bulkRow.index - 1);
                }
                Keys.onReturnPressed: (e) => {
                  e.accepted = true;
                  if (bulk.sound) bulk.commit();
                }
                Keys.onEnterPressed: (e) => {
                  e.accepted = true;
                  if (bulk.sound) bulk.commit();
                }

                // A delegate cannot be handed focus from outside, so it
                // takes it when the card says this row is the one. The
                // STEM is selected and the extension is not, for the same
                // reason the in-place rename does it: a bulk rename is
                // almost never about the type.
                Connections {
                  target: bulk
                  function onAtPulseChanged() {
                    if (bulk.at !== bulkRow.index) return;
                    toName.forceActiveFocus();
                    const st = Terminus.stem(toName.text);
                    toName.select(0, st.length > 0 ? st.length : toName.text.length);
                  }
                }
                Component.onCompleted: {
                  if (bulk.at !== bulkRow.index) return;
                  toName.forceActiveFocus();
                  const st = Terminus.stem(toName.text);
                  toName.select(0, st.length > 0 ? st.length : toName.text.length);
                }
              }

              // WHY the row is red, on the row. A card that only greyed
              // out its own button left you comparing thirty names by eye
              // to find the two that collided.
              Text {
                id: issueText
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                visible: bulkRow.issue !== ""
                text: bulkRow.issue
                color: Zenon.red
                font.family: Zenon.face
                font.pixelSize: 12
              }
            }
          }

          ScrollRail {
            owner: bulk.host
            target: bulkList
            anchors.top: bulkList.top
            anchors.bottom: bulkList.bottom
            x: bulkList.x + bulkList.width - width - 2
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: Zenon.border
        }

        // ── what it will do, and the two answers ──────────────
        Item {
          width: parent.width
          height: 52

          Text {
            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            text: !bulk.sound ? "fix the marked names"
              : (bulk.changes === 0 ? "nothing changed"
                : bulk.changes + (bulk.changes === 1
                    ? " name will change" : " names will change"))
            color: !bulk.sound ? Zenon.red
              : (bulk.changes === 0 ? Zenon.muted : Zenon.cyan)
            font.family: Zenon.face
            font.pixelSize: 14
          }

          Row {
            anchors.right: parent.right
            anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            DialogButton {
              label: "Cancel"
              ink: Zenon.muted
              onClicked: bulk.dismiss()
            }

            DialogButton {
              label: "Rename"
              ink: Zenon.cyan
              primary: true
              ready: bulk.sound && bulk.changes > 0
              onClicked: bulk.commit()
            }
          }
        }
      }
    }
  }

  // ── where the dropdowns' lists go ─────────────────────────────────────
  // Over the card; a click anywhere off an open list puts it away. Declared
  // last, so it is above the rows it hangs over.
  Item {
    id: dropLayer
    anchors.fill: parent
    z: 30
    MouseArea {
      anchors.fill: parent
      enabled: bulk.bulkOpenDrop !== null
      onClicked: bulk.bulkOpenDrop = null
    }
  }
}

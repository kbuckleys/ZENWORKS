// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// you filter with the keyboard and commit with return.
// ── the collection editor ───────────────────────────────────────
// Edits a DEEP COPY and writes it only on save. A card that mutated the
// stored directory as you typed would have no cancel — and the rules are
// the sort of thing you take apart to see what happens.
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
  id: collEdit
  // the terminus window (`term`, never `root` — see terminus-split notes)
  property var term: null
  anchors.fill: parent
  z: 13
  visible: opacity > 0.01
  opacity: collEdit.open ? 1 : 0
  // Every sheet hangs from the bar now, so the bar it hangs from stays
  // lit (it is the titlebar) and only what is under it is darkened.
  color: "transparent"

  Rectangle {
    id: searchScrim
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
      duration: collEdit.open ? collSheet.slideIn : collSheet.slideOut
      easing.type: Zenon.ease
    }
  }

  property bool open: false
  property var draft: null
  property bool making: false

  // ── AND A SEARCH IS THE SAME CARD ─────────────────────────────
  // A collection is a saved search, so asking one and saving one were
  // two sheets for one question. `s` opens this card with a query on
  // top: Return runs it, the rule rows refine it, and "save as
  // collection" names it and keeps it — no retyping, no second sheet.
  // `searching` is that mode; `naming` is the name row it grows when
  // you decide to keep the search. A new collection is this card,
  // already naming.
  property bool searching: false
  property bool naming: false
  // "find" searches names, "grep" what is inside — the two searches
  // `s` and `S` have always been.
  property string searchKind: "find"
  // Opened by `s`/`S` — a search, which hangs from the bar. A new
  // collection opens the same card already naming, and floats; saving a
  // search as a collection keeps the sheet where it already is.
  property bool hangs: false

  // ── SLIGHTLY LARGER TYPE THAN THE RENAME CARD ─────────────────
  // That card is a table: forty rows of filenames, where small type is
  // what lets you see them all at once. This one is four controls you
  // read and type into, and it was borrowing the table's size. One
  // number, so the fields, the pickers and the sentence cannot drift
  // apart from each other.
  readonly property int textSize: 16

  // ── WHY A ListModel AND NOT THE DRAFT'S OWN ARRAY ─────────────
  // The same reason jobsModel is one, and it bit in the same way. A
  // `property var` holding an array has to be REPLACED to be seen
  // changing, so a Repeater over it rebuilds every delegate on every
  // edit — and these delegates seed themselves from their row on
  // creation and write back on every keystroke. Rebuild, seed, write,
  // rebuild: a binding loop, and Qt said so.
  //
  // A ListModel is edited in PLACE. setProperty touches one role and
  // the delegate already on screen keeps its cursor, its focus and its
  // text.
  ListModel { id: ruleModel }

  // Bumped on every edit, because a binding cannot watch a ListModel's
  // CONTENTS — only its count. The sentence below and the Save button
  // both have to re-read when a value changes, and this is what tells
  // them to. Same trick jobFaults uses.
  property int ruleRev: 0

  // The draft as it stands, rebuilt from the model on demand rather
  // than kept in step with it. Called by the sentence, by `ready`, and
  // by commit — never stored, so there is only ever one truth.
  function draftNow() {
    if (!collEdit.draft) return null;
    // FROM the draft, with the edited fields written over it — not a
    // fresh object holding only them. A collection also carries what the
    // card does not edit (its view, tidy, anyKind), and building it from
    // scratch dropped those on every save.
    const d = JSON.parse(JSON.stringify(collEdit.draft));
    d.name = collEdit.searching ? saveName.text : collName.text;
    d.ink = collEdit.draft.ink || "cyan";
    d.root = collRoot.text;
    d.rules = [];
    // The query is the first rule, written the way a collection would
    // have spelt it — so what is run and what is saved are one thing.
    if (collEdit.searching) {
      if (String(d.root).trim() === "") d.root = term.cwd;
      const q = searchQ.text.trim();
      if (q !== "") d.rules.push(collEdit.searchKind === "grep"
        ? { kind: "content", op: "text", value: q }
        : { kind: "name", op: "contains", value: q });
    }
    for (let i = 0; i < ruleModel.count; ++i) {
      const r = ruleModel.get(i);
      d.rules.push({ kind: r.kind, op: r.op, value: r.value });
    }
    return d;
  }

  function ask(id) {
    // A NEW one is a search you are about to name — see askSearch.
    if (!(id >= 0) || !term.collById(id)) { collEdit.askSearch("", true); return; }
    collEdit.searching = false;
    collEdit.naming = false;
    collEdit.hangs = false;
    const existing = id >= 0 ? term.collById(id) : null;
    collEdit.making = existing === null;
    // JSON round trip rather than a shallow copy: the rules are objects
    // inside an array, and a shallow copy would hand the card the very
    // objects it is supposed to be editing a copy of.
    collEdit.draft = existing
      ? JSON.parse(JSON.stringify(existing))
      : Coll.blank(Date.now());
    if (collEdit.making && collEdit.draft.root === "")
      collEdit.draft.root = term.cwd;
    // PUSHED IN, not bound. These two write BACK to the draft on every
    // keystroke, so binding their text to the draft as well would be a
    // loop — the field sets the draft, the draft sets the field. The
    // draft is the record and the fields are seeded from it once, which
    // is the same shape the rule rows use.
    collName.text = String(collEdit.draft.name || "");
    collRoot.text = String(collEdit.draft.root || "");
    ruleModel.clear();
    const rs = collEdit.draft.rules || [];
    for (let i = 0; i < rs.length; ++i)
      ruleModel.append({ kind: rs[i].kind, op: rs[i].op,
                         value: String(rs[i].value || "") });
    if (ruleModel.count === 0) {
      const n = Coll.newRule("name");
      ruleModel.append({ kind: n.kind, op: n.op, value: n.value });
    }
    collEdit.ruleRev = collEdit.ruleRev + 1;
    collEdit.open = true;
    collClaim.tries = 0;
    collClaim.restart();
  }

  // ── OPENED AS A SEARCH ────────────────────────────────────────
  // `kind` is "find" or "grep", or "" for whichever the last search
  // was. Pressed again over the results of a search it reopens on that
  // same search — query, place and refinements — which is what makes
  // the results something you refine rather than retype.
  function askSearch(kind, name) {
    const keep = term.lastSearch;
    // A NEW collection starts blank; only a search reopens on the last one.
    const plain = name !== true
      && (term.searchMode === "find" || term.searchMode === "grep");
    const refining = name !== true && !!keep && (term.scratchOpen
      || (plain && keep.query === term.searchQuery && keep.kind === term.searchMode));
    collEdit.searching = true;
    collEdit.naming = name === true;
    collEdit.hangs = name !== true;
    collEdit.making = true;
    collEdit.searchKind = kind !== "" ? kind
      : (refining ? keep.kind : (plain ? term.searchMode : "find"));
    collEdit.draft = Coll.blank(Date.now());
    collEdit.draft.rules = [];
    searchQ.text = refining ? keep.query : (plain ? term.searchQuery : "");
    collRoot.text = refining ? keep.root : term.cwd;
    saveName.text = "";
    collName.text = "";
    ruleModel.clear();
    if (refining)
      for (const r of keep.rules)
        ruleModel.append({ kind: r.kind, op: r.op, value: String(r.value || "") });
    collEdit.ruleRev = collEdit.ruleRev + 1;
    collEdit.open = true;
    collClaim.tries = 0;
    collClaim.restart();
  }

  // The rows that actually ask something, for remembering a search.
  function liveRules() {
    const out = [];
    for (let i = 0; i < ruleModel.count; ++i) {
      const r = ruleModel.get(i);
      if (String(r.value || "").trim() !== "")
        out.push({ kind: r.kind, op: r.op, value: r.value });
    }
    return out;
  }

  // Return in search mode. A bare query in the directory you are in
  // is the search `s` always ran — find or rg, ignore files honoured —
  // and anything refined runs through the collection pipeline as a
  // collection nobody has saved yet. See root.searchScratch.
  function runSearch() {
    if (!collEdit.asks) return;
    const q = searchQ.text.trim();
    const extra = collEdit.liveRules();
    const where = Coll.expandHome(collRoot.text.trim(), Paths.home());
    term.lastSearch = { kind: collEdit.searchKind, query: q,
                        root: collRoot.text, rules: extra };
    const d = collEdit.draftNow();
    collEdit.dismiss();
    if (extra.length === 0 && q !== "" && (where === "" || where === term.cwd)) {
      term.search(collEdit.searchKind, q);
      return;
    }
    term.searchScratch(d, q);
  }

  // "save as collection": the name row opens and takes the keyboard.
  function beginNaming() {
    collEdit.naming = true;
    Qt.callLater(() => saveName.claim());
  }

  // ASK UNTIL IT HAS IT, the same retry every other card here carries:
  // the sheet is animating in from opacity 0 when the first request goes
  // out, and forceActiveFocus() on an item the scene has not placed yet
  // is silently dropped.
  Timer {
    id: collClaim
    interval: 40
    repeat: true
    property int tries: 0
    onTriggered: {
      const first = !collEdit.searching ? collName
        : (collEdit.naming && searchQ.text !== "" ? saveName : searchQ);
      if (!collEdit.open || first.focused || collClaim.tries++ > 12) {
        collClaim.stop();
        return;
      }
      collKeys.forceActiveFocus();
      first.claim();
    }
  }

  function dismiss() {
    collEdit.open = false;
    collEdit.draft = null;
    term.contentRef.forceActiveFocus();
  }

  function setRule(i, field, value) {
    if (i < 0 || i >= ruleModel.count) return;
    if (ruleModel.get(i)[field] === value) return;
    ruleModel.setProperty(i, field, String(value));
    // The op belongs to the kind, so changing the kind has to pick a
    // legal op — "larger" survives a switch to Name otherwise and
    // compiles to nothing.
    if (field === "kind") {
      const ops = Coll.opsFor(value);
      ruleModel.setProperty(i, "op", ops.length > 0 ? ops[0] : "");
      ruleModel.setProperty(i, "value", "");
    }
    collEdit.ruleRev = collEdit.ruleRev + 1;
  }

  function addRule() {
    const n = Coll.newRule("name");
    ruleModel.append({ kind: n.kind, op: n.op, value: n.value });
    collEdit.ruleRev = collEdit.ruleRev + 1;
  }

  function dropRule(i) {
    if (i < 0 || i >= ruleModel.count) return;
    ruleModel.remove(i);
    // Never none: an empty card gives you nothing to type into and no
    // way to get a row back. A search has its query to type into, and
    // its refinements are optional — "+ refine" brings one back.
    if (ruleModel.count === 0 && !collEdit.searching) {
      const n = Coll.newRule("name");
      ruleModel.append({ kind: n.kind, op: n.op, value: n.value });
    }
    collEdit.ruleRev = collEdit.ruleRev + 1;
  }

  // ruleRev and nameRev are READ here so the binding re-runs when they
  // change — a ListModel's contents are invisible to the dependency
  // tracker, and without touching them this would evaluate once.
  // Whether the draft asks anything at all — a search can run on this.
  readonly property bool asks: {
    collEdit.ruleRev;
    collEdit.nameRev;
    const d = collEdit.draftNow();
    if (!d) return false;
    return Coll.command(d, Paths.home()) !== "" || Coll.tagsOnly(d);
  }
  // And whether it can be KEPT, which also needs a name.
  readonly property bool ready: {
    collEdit.nameRev;
    if (!collEdit.asks) return false;
    const d = collEdit.draftNow();
    return !!d && String(d.name).trim() !== "";
  }

  readonly property string sentence: {
    collEdit.ruleRev;
    const d = collEdit.draftNow();
    return d ? Coll.describe(d) : "";
  }

  // The two text fields are not in the model, so they need their own.
  property int nameRev: 0

  // ── THE TAB RING ──────────────────────────────────────────────
  // Built by ASKING the Repeater what it made, not by keeping a list in
  // step with it by hand: rules are added and removed while the card is
  // open, and a hand-kept list is one `addRule` away from pointing at a
  // control that no longer exists.
  //
  // Each rule contributes three stops — what it asks about, how, and
  // what for — and the value stop is whichever of the two controls that
  // rule actually shows.
  function ring() {
    const out = collEdit.searching
      ? (collEdit.naming ? [searchQ, collRoot, saveName] : [searchQ, collRoot])
      : [collName, collRoot];
    for (let i = 0; i < ruleRepeater.count; ++i) {
      const row = ruleRepeater.itemAt(i);
      if (!row) continue;
      if (row.kindCtl) out.push(row.kindCtl);
      if (row.opCtl) out.push(row.opCtl);
      if (row.valCtl) out.push(row.valCtl);
    }
    return out;
  }

  function focusFrom(cur, dir) {
    const r = collEdit.ring();
    if (r.length === 0) return;
    let i = -1;
    for (let k = 0; k < r.length; ++k) if (r[k] === cur) { i = k; break; }
    // Not found means the caller is gone — its row was just removed —
    // and the top of the ring is the honest place to land.
    if (i < 0) { r[0].claim(); return; }
    const next = r[(i + dir + r.length) % r.length];
    if (next && next.claim) next.claim();
  }

  function commit() {
    if (collEdit.searching && !collEdit.naming) { collEdit.runSearch(); return; }
    if (!collEdit.ready) return;
    const d = collEdit.draftNow();
    d.name = String(d.name).trim();
    term.saveCollection(d);
    const id = d.id;
    collEdit.dismiss();
    term.goToCollection(id);
  }

  InputShield {
    keepTop: term.tabStripRef.height + term.crumbBarRef.height
    onClicked: collEdit.dismiss()
  }

  FocusScope {
    id: collKeys
    anchors.fill: parent
    Keys.onPressed: (e) => {
      if (e.key !== Qt.Key_Escape) return;
      e.accepted = true;
      // ONE STEP AT A TIME, the rule every card with something open
      // inside it follows. An open dropdown is the innermost thing, so
      // it goes first — Escape used to take the whole card away from
      // under a menu the pointer was still in.
      if (term.bulkOpenDrop !== null) { term.bulkOpenDrop = null; return; }
      collEdit.dismiss();
    }

    Sheet {
      backdrop: term.chromeRef   // frosted over it — see morpheus/Sheet
      splice: true
      onCardInkChanged: term.noteSheet("s7", cardInk, drawnX, drawnW)
      onDrawnXChanged: term.noteSheet("s7", cardInk, drawnX, drawnW)
      onDrawnWChanged: term.noteSheet("s7", cardInk, drawnX, drawnW)
      id: collSheet
      leftInset: term.sideRef.width
      // Every sheet comes down out of the bar now, a search and a
      // collection dialog alike: the bar is the card's titlebar.
      floating: false
      title: term.sheetTitle
      glyph: term.sheetGlyph
      titleInk: term.sheetTitleInk
      glyphInk: term.sheetGlyphInk
      shown: collEdit.open
      fromTop: term.tabStripRef.height + term.crumbBarRef.height
      cardW: 820
      cardH: collCol.implicitHeight

      Column {
        id: collCol
        width: parent.width

        // ── what it is called, and where it looks ──────────────
        Item {
          width: parent.width
          height: 46

          BulkField {

            textSize: collEdit.textSize
            id: collName
            visible: !collEdit.searching
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            width: (parent.width - 44) * 0.38
            ghost: "name"
            onTextChanged: collEdit.nameRev = collEdit.nameRev + 1
            onTabbed: collEdit.focusFrom(collName, 1)
            onBackTabbed: collEdit.focusFrom(collName, -1)
            onAccepted: collEdit.commit()
          }

          // ── THE QUERY, in place of the name ────────────────
          // Which of the two it searches is said beside it, and is
          // one click to change — the same pair `s` and `S` open on.
          Row {
            id: searchKinds
            visible: collEdit.searching
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            BulkVerb {
              label: "names"
              on: collEdit.searchKind === "find"
              onClicked: { collEdit.searchKind = "find"; collEdit.nameRev++; }
            }
            BulkVerb {
              label: "contents"
              on: collEdit.searchKind === "grep"
              onClicked: { collEdit.searchKind = "grep"; collEdit.nameRev++; }
            }
          }

          BulkField {
            textSize: collEdit.textSize
            id: searchQ
            visible: collEdit.searching
            anchors.left: searchKinds.right
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: (parent.width - 44) * 0.62 - searchKinds.width - 12
            ghost: collEdit.searchKind === "grep" ? "text inside files" : "part of a name"
            onTextChanged: collEdit.nameRev = collEdit.nameRev + 1
            onTabbed: collEdit.focusFrom(searchQ, 1)
            onBackTabbed: collEdit.focusFrom(searchQ, -1)
            onAccepted: collEdit.commit()
          }

          BulkField {

            textSize: collEdit.textSize
            id: collRoot
            anchors.left: collEdit.searching ? searchQ.right : collName.right
            anchors.leftMargin: 12
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            ghost: "where to look"
            elide: Text.ElideLeft
            onTextChanged: collEdit.nameRev = collEdit.nameRev + 1
            onTabbed: collEdit.focusFrom(collRoot, 1)
            onBackTabbed: collEdit.focusFrom(collRoot, -1)
            onAccepted: collEdit.commit()
          }
        }

        // ── KEPT AS A COLLECTION ──────────────────────────────
        // Only once you have asked to keep it: a search you are just
        // running has no use for a name.
        Item {
          width: parent.width
          height: collEdit.searching && collEdit.naming ? 40 : 0
          visible: height > 0
          clip: true

          Text {
            id: saveNameLabel
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: saveName.verticalCenter
            text: "save as"
            color: Zenon.muted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: collEdit.textSize - 2
          }

          BulkField {
            textSize: collEdit.textSize
            id: saveName
            anchors.left: saveNameLabel.right
            anchors.leftMargin: 12
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.top: parent.top
            ghost: "collection name"
            onTextChanged: collEdit.nameRev = collEdit.nameRev + 1
            onTabbed: collEdit.focusFrom(saveName, 1)
            onBackTabbed: collEdit.focusFrom(saveName, -1)
            onAccepted: collEdit.commit()
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: Zenon.border
        }

        // ── the rules ─────────────────────────────────────────
        Repeater {
          id: ruleRepeater
          model: ruleModel

          delegate: Item {
            id: ruleRow
            required property string kind
            required property string op
            required property string value
            required property int index

            // What this row offers the ring. The value stop is whichever
            // control the row is actually showing — a hidden one cannot
            // take focus, and tabbing into it would look like Tab being
            // swallowed.
            readonly property var kindCtl: kindDrop
            readonly property var opCtl: opDrop
            readonly property var valCtl:
              ruleRow.kind === "kind" ? valueDrop : valueField
            width: collCol.width
            height: 44
            // Lifted while one of its own dropdowns is open, for the
            // reason patRow is — z orders an item among its SIBLINGS,
            // and the rows below are this row's siblings.
            z: (kindDrop.expanded || opDrop.expanded) ? 60 : 0

            BulkDrop {

              host: term

              textSize: collEdit.textSize
              id: kindDrop
              overlay: term.dropLayerRef
              anchors.left: parent.left
              anchors.leftMargin: 16
              anchors.verticalCenter: parent.verticalCenter
              options: {
                const out = [];
                for (let i = 0; i < Coll.KINDS.length; ++i)
                  out.push([Coll.KINDS[i].kind, Coll.KINDS[i].label]);
                return out;
              }
              value: ruleRow.kind
              onPicked: (v) => collEdit.setRule(ruleRow.index, "kind", v)
              onTabbed: collEdit.focusFrom(kindDrop, 1)
              onBackTabbed: collEdit.focusFrom(kindDrop, -1)
            }

            BulkDrop {

              host: term

              textSize: collEdit.textSize
              id: opDrop
              overlay: term.dropLayerRef
              anchors.left: kindDrop.right
              anchors.leftMargin: 8
              anchors.verticalCenter: parent.verticalCenter
              options: {
                const ops = Coll.opsFor(ruleRow.kind);
                const out = [];
                for (let i = 0; i < ops.length; ++i) out.push([ops[i], ops[i]]);
                return out;
              }
              value: ruleRow.op
              onPicked: (v) => collEdit.setRule(ruleRow.index, "op", v)
              onTabbed: collEdit.focusFrom(opDrop, 1)
              onBackTabbed: collEdit.focusFrom(opDrop, -1)
            }

            // The Kind row picks from a list; everything else is typed.
            // Two controls in one slot rather than a third column that
            // is empty five rows out of six.
            BulkDrop {
              host: term
              textSize: collEdit.textSize
              id: valueDrop
              overlay: term.dropLayerRef
              visible: ruleRow.kind === "kind"
              anchors.left: opDrop.right
              anchors.leftMargin: 8
              anchors.verticalCenter: parent.verticalCenter
              options: {
                const out = [["", "\u2014"]];
                for (let i = 0; i < Coll.FILE_KINDS.length; ++i)
                  out.push([Coll.FILE_KINDS[i].name,
                            Coll.FILE_KINDS[i].label || Coll.FILE_KINDS[i].name]);
                return out;
              }
              value: ruleRow.value
              onPicked: (v) => collEdit.setRule(ruleRow.index, "value", v)
              onTabbed: collEdit.focusFrom(valueDrop, 1)
              onBackTabbed: collEdit.focusFrom(valueDrop, -1)
            }

            BulkField {

              textSize: collEdit.textSize
              id: valueField
              visible: ruleRow.kind !== "kind"
              anchors.left: opDrop.right
              anchors.leftMargin: 8
              anchors.right: ruleDrop.left
              anchors.rightMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              ghost: {
                const k = ruleRow.kind;
                if (k === "size") return "10m";
                if (k === "date") return "7d";
                if (k === "tag") return "a tag name";
                if (k === "content") return "text to find inside";
                return "text";
              }
              // Written back on every keystroke rather than on accept:
              // the Save button is bound to whether the draft asks
              // anything, and it would stay dead until you pressed
              // Return in a field you had already filled in.
              onTextChanged: collEdit.setRule(ruleRow.index, "value",
                                               valueField.text)
              onTabbed: collEdit.focusFrom(valueField, 1)
              onBackTabbed: collEdit.focusFrom(valueField, -1)
              onAccepted: collEdit.commit()
              // Seeded once. The row is edited in place now, so this
              // runs when the row is CREATED and never again — which is
              // what stops the seed and the write-back chasing each
              // other.
              Component.onCompleted: valueField.text = ruleRow.value
            }

            Text {
              id: ruleDrop
              anchors.right: parent.right
              anchors.rightMargin: 16
              anchors.verticalCenter: parent.verticalCenter
              text: "\uEA76"
              color: ruleDropHov.hovered ? Zenon.red : Zenon.muted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(14)

              HoverHandler { id: ruleDropHov }
              MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                onClicked: collEdit.dropRule(ruleRow.index)
              }
            }
          }
        }

        Rectangle {
          width: parent.width
          // one rule, not two stacked, when a search has no refinements
          height: ruleModel.count > 0 ? 1 : 0
          color: Zenon.border
        }

        // ── what it would ask, in words ───────────────────────
        // The compiled sentence, shown back. A rule that compiles to
        // nothing — a size of "abc", a date of "soon" — is otherwise
        // invisible until the directory returns the wrong thing.
        Item {
          width: parent.width
          height: 40

          Text {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.right: collActions.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: collEdit.sentence === ""
              ? (collEdit.searching ? "type something to look for" : "no rules yet")
              : collEdit.sentence
            // An empty search is not a mistake, just not a question yet.
            color: collEdit.searching && !collEdit.naming ? Zenon.muted
              : (collEdit.ready ? Zenon.muted : Zenon.red)
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: collEdit.textSize - 2
          }

          Row {
            id: collActions
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            BulkVerb {
              label: collEdit.searching ? "+ refine" : "+ rule"
              onClicked: collEdit.addRule()
            }
            BulkVerb {
              label: "delete"
              visible: !collEdit.searching
              dim: collEdit.making
              onClicked: {
                if (collEdit.making) return;
                term.dropCollection(collEdit.draft.id);
                collEdit.dismiss();
              }
            }
            // The search's way out to a collection, and back again.
            BulkVerb {
              visible: collEdit.searching
              label: collEdit.naming ? "just search" : "save as collection"
              onClicked: {
                if (collEdit.naming) { collEdit.naming = false; searchQ.claim(); }
                else collEdit.beginNaming();
              }
            }
            DialogButton {
              label: collEdit.searching && !collEdit.naming ? "Search"
                : (collEdit.making ? "Create" : "Save")
              ink: collEdit.searching && !collEdit.naming ? Zenon.sand : Zenon.cyan
              ready: collEdit.searching && !collEdit.naming ? collEdit.asks
                : collEdit.ready
              onClicked: collEdit.commit()
            }
          }
        }
      }
    }
  }
}

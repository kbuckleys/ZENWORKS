// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A WINDOW'S CARDS — one sheet, one card at a time, in the order asked:
// the suite's confirmation (terminus/ConfirmBody) or a question with fields
// (FormBody) on morpheus' Sheet, behind an InputShield. Delphi's and
// calypso's windows ask everything through it.
//
//   card_({ question, glyph, ink, detail, items, rows,
//           choices: [{ label, ink, run, keep, primary }] }) → id
//                                any answers; the LAST is the way out (Esc,
//                                a click off the card). `keep` leaves the
//                                card up after its run (a sign-in's Open and
//                                Copy are not answers)
//   confirm({ question, glyph, ink, detail, items, verb, then, cancel }) → id
//   ask(form) → id               a FormBody card — fields, a password
//   dropCard(id)                 take one down (the sign-in that finished)
//
// `lead` is a card that goes before the queue, owned by whoever set it
// (delphi's git questions): its answers come back as leadChose(i) and
// leadSettled(ok, values), not through the queue. Children placed in it go
// into the confirmation's slot, under its items (delphi's file tree).
//
// Lifted out of delphi/DelphiWindow.qml (2026-10-11) when calypso's window
// wanted the same cards.

import QtQuick
import "../morpheus"
import "../terminus"

Item {
  id: deck
  anchors.fill: parent

  property var lead: null
  property real fromTop: 0
  property real leftInset: 0
  property real cardW: 540
  // a FormBody directory field's Choose…
  property var chooseDir: null
  // … and a file field's (FormBody `file`)
  property var chooseFile: null
  default property alias extra: confirmBody.extra

  signal leadChose(int i)
  signal leadSettled(bool ok, var values)
  // the last card went down: the window takes its keys back
  signal cleared()

  property var sheetQueue: []
  property int cardN: 0
  readonly property var card: deck.lead ? deck.lead
    : deck.sheetQueue.length > 0 ? deck.sheetQueue[0] : null
  readonly property bool carding: deck.card !== null
  property int cardPick: 0
  onCardChanged: {
    deck.cardPick = 0;
    if (!deck.card) Qt.callLater(deck.cleared);
    else if (deck.card.kind === "confirm") Qt.callLater(() => cardKeys.forceActiveFocus());
  }

  function card_(c) {
    const id = ++deck.cardN;
    // every answer speaks in a colour: one left without drew in Qt's default
    // black, heavier than the rest (the sign-in card's Copy, 2026-10-10)
    const choices = (c.choices || []).map((ch) => Object.assign({ ink: Zenon.muted }, ch));
    deck.sheetQueue = deck.sheetQueue.concat([Object.assign({ kind: "confirm", id: id }, c, { choices: choices })]);
    return id;
  }
  function dropCard(id) { deck.sheetQueue = deck.sheetQueue.filter((c) => c.id !== id); }
  function confirm(c) {
    return deck.card_({ question: c.question, glyph: c.glyph || "", ink: c.ink || Zenon.cyan,
      detail: c.detail || "", items: c.items || [],
      choices: [{ label: c.verb || "OK", ink: c.ink || Zenon.cyan, run: c.then || null },
                { label: "Cancel", ink: Zenon.muted, run: c.cancel || null }] });
  }
  function ask(form) {
    const id = ++deck.cardN;
    deck.sheetQueue = deck.sheetQueue.concat([Object.assign({ kind: "form", id: id }, form)]);
    return id;
  }
  // a confirmation's answer i
  function choose(i) {
    const c = deck.card;
    if (!c || c.kind !== "confirm") return;
    if (c === deck.lead) { deck.leadChose(i); return; }
    const ch = c.choices[i];
    if (!ch) return;
    if (!ch.keep) deck.dropCard(c.id);
    if (ch.run) ch.run();
  }
  // a form's answer
  function settleForm(ok, values) {
    const c = deck.card;
    if (!c || c.kind !== "form") return;
    if (c === deck.lead) { deck.leadSettled(ok, values); return; }
    deck.dropCard(c.id);
    if (ok && c.then) c.then(values || {});
    else if (!ok && c.cancel) c.cancel();
  }
  // Esc, or a click off the card
  function dismiss() {
    const c = deck.card;
    if (!c) return;
    if (c.kind === "form") deck.settleForm(false, null);
    else deck.choose(c.choices.length - 1);
  }

  InputShield { visible: deck.carding; onClicked: deck.dismiss() }
  Sheet {
    id: sheet
    shown: deck.carding
    fromTop: deck.fromTop
    leftInset: deck.leftInset
    cardW: deck.cardW
    cardH: deck.card && deck.card.kind === "form" ? formBody.implicitHeight : confirmBody.implicitHeight
    ConfirmBody {
      id: confirmBody
      visible: !!deck.card && deck.card.kind === "confirm"
      width: parent.width
      question: deck.card && deck.card.question ? deck.card.question : ""
      glyph: deck.card && deck.card.glyph ? deck.card.glyph : ""
      glyphInk: deck.card && deck.card.ink ? deck.card.ink : Zenon.white
      detail: deck.card && deck.card.detail ? deck.card.detail : ""
      items: deck.card && deck.card.items ? deck.card.items : []
      choices: deck.card && deck.card.choices ? deck.card.choices : []
      pick: deck.cardPick
      onPicked: (i) => deck.cardPick = i
      onChose: (i) => deck.choose(i)
    }
    FormBody {
      id: formBody
      visible: !!deck.card && deck.card.kind === "form"
      width: parent.width
      form: deck.card && deck.card.kind === "form" ? deck.card : null
      chooseDir: deck.chooseDir
      chooseFile: deck.chooseFile
      onDone: (ok, values) => deck.settleForm(ok, values)
    }
  }
  // a confirmation has no field to hold the keyboard: it is held here
  Item {
    id: cardKeys
    Keys.onPressed: (e) => {
      const c = deck.card;
      e.accepted = true;
      if (!c || c.kind !== "confirm") return;
      const n = c.choices.length;
      if (e.key === Qt.Key_Escape) deck.dismiss();
      else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) deck.choose(deck.cardPick);
      // the answers are drawn right to left (ConfirmBody): left is the next one
      else if (e.key === Qt.Key_Left || e.key === Qt.Key_Tab) deck.cardPick = (deck.cardPick + 1) % n;
      else if (e.key === Qt.Key_Right || e.key === Qt.Key_Backtab) deck.cardPick = (deck.cardPick + n - 1) % n;
    }
  }
}

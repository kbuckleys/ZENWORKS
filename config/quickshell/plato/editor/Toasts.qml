// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// What nvim says, as cards in the lower right corner of the editor: a write,
// an error, a plugin's vim.notify, :ls's listing. They used to take the
// status line's place, which hid the file — and with it the ● that says it
// is unsaved — for as long as the message was up.
//
// A card per message, newest at the bottom, sliding in from the right and
// out again. Its ink says how loud it is: red for an error, yellow for a
// warning, cyan for progress (a write), muted for anything else. The pointer
// over a card holds it; a click puts it away.
//
// HOW LONG: the settings sheet's timeout for an ordinary one, half as long
// again for a warning, twice for an error. Output of several lines (:ls,
// :reg, :!cmd) and a question (confirm) wait for the next key — what nvim's
// own "Press ENTER" did.
//
// MESSAGES THAT BELONG TOGETHER ARE ONE CARD. nvim names a message that
// updates another (a write's "writing…" then its "written") by the same id,
// says when one replaces or carries on the last, and sends :!cmd's output in
// parts a moment apart; each of those lands in the card it belongs to.
//
// A QUESTION IS A CARD TOO (bridge.lua's ask): its choices are buttons
// along its foot, each with the key that answers it — Alt and a letter, so
// it never takes a key the editor was waiting for. It stays until it is
// answered; "dismiss" answers it with nothing.

import QtQuick
import "../../morpheus"

Item {
  id: root

  property font face
  property int timeout: 4000
  readonly property int maxCards: 4

  // what the status bar and the search count already say
  readonly property var quiet: ({
    search_cmd: true, search_count: true, empty: true, return_prompt: true,
    completion: true, wildlist: true,
  })
  function tone(kind) {
    if (/^(emsg|echoerr|lua_error|rpc_error|shell_err)$/.test(kind)) return "error";
    if (kind === "wmsg") return "warn";
    if (kind === "progress") return "progress";
    return "info";
  }

  ListModel { id: cards }
  // the answer goes back through this (PlatoWindow's NvimClient)
  property var client: null
  property int _uid: 0
  property double _lastAt: 0

  function take(ev) {
    const kind = String(ev.kind || "");
    if (root.quiet[kind]) return;
    const text = String(ev.text || "").replace(/\n+$/, "");
    if (text === "") return;
    const now = Date.now();
    const together = now - root._lastAt < 120;
    root._lastAt = now;
    const t = root.tone(kind);
    const msgId = ev.msgId === undefined || ev.msgId === null ? "" : String(ev.msgId);

    // the same message again, updated
    if (msgId !== "") {
      for (let i = 0; i < cards.count; ++i) {
        if (cards.get(i).msgId === msgId) {
          root.update(i, text, t, kind);
          return;
        }
      }
    }
    const last = cards.count - 1;
    if (last >= 0 && ev.append) { root.update(last, cards.get(last).text + text, t, kind); return; }
    if (last >= 0 && ev.replace) { root.update(last, text, t, kind); return; }
    // parts of one burst: a line each, the loudest ink
    if (last >= 0 && together && msgId === "") {
      const c = cards.get(last);
      const worse = c.tone === "error" || t === "error" ? "error"
        : c.tone === "warn" || t === "warn" ? "warn" : t;
      root.update(last, c.text + "\n" + text, worse, kind);
      return;
    }
    cards.append({ uid: ++root._uid, msgId: msgId, text: text, tone: t,
                   sticky: root.waits(text, kind), serial: 0, ask: 0, choices: "[]" });
    root.trim();
  }
  // never more than maxCards; a question is the last to be pushed out
  function trim() {
    while (cards.count > root.maxCards) {
      let i = 0;
      while (i < cards.count - 1 && cards.get(i).ask > 0) i++;
      cards.remove(i);
    }
  }

  // ── questions ──────────────────────────────────────────────────────
  function takeAsk(ev) {
    const choices = ev.choices ? Array.from(ev.choices) : [];
    root.unask(ev.ask);
    cards.append({ uid: ++root._uid, msgId: "", text: String(ev.text || ""),
                   tone: ev.tone === "error" ? "error" : ev.tone === "info" ? "info" : "warn",
                   sticky: true, serial: 0, ask: ev.ask, choices: JSON.stringify(choices) });
    root.trim();
  }
  function unask(n) {
    for (let i = cards.count - 1; i >= 0; --i) if (cards.get(i).ask === n) cards.remove(i);
  }
  function answer(n, choice) {
    root.unask(n);
    if (root.client) root.client.answer(n, choice);
  }
  // Alt and a letter, from the editor: the newest question with that
  // choice takes it. True when one did.
  function tryKey(letter) {
    for (let i = cards.count - 1; i >= 0; --i) {
      const c = cards.get(i);
      if (c.ask <= 0) continue;
      const ch = JSON.parse(c.choices);
      for (const x of ch) if (x.key === letter) { root.answer(c.ask, letter); return true; }
    }
    return false;
  }
  function waits(text, kind) { return text.indexOf("\n") >= 0 || kind === "confirm"; }
  function update(i, text, tone, kind) {
    const c = cards.get(i);
    cards.set(i, { text: text, tone: tone, sticky: root.waits(text, kind), serial: c.serial + 1 });
  }
  function dismiss(uid) {
    for (let i = 0; i < cards.count; ++i) if (cards.get(i).uid === uid) { cards.remove(i); return; }
  }
  // a key went to the editor: what was waiting for one has had it
  function keyTyped() {
    for (let i = cards.count - 1; i >= 0; --i) if (cards.get(i).sticky && cards.get(i).ask <= 0) cards.remove(i);
  }
  function clear() { cards.clear(); }

  function ink(tone) {
    return tone === "error" ? Zenon.red : tone === "warn" ? Zenon.yellow
      : tone === "progress" ? Zenon.cyan : Zenon.muted;
  }
  function glyph(tone) {
    return tone === "error" ? "\u{F0159}" : tone === "warn" ? "\u{F0026}"
      : tone === "progress" ? "\u{F012C}" : "\u{F02FC}";
  }

  ListView {
    id: list
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    width: parent.width
    // THE WHOLE AREA, NOT ITS CONTENT. Sized to its content it started at
    // nothing — and a list with no height makes no delegates, so the first
    // card never arrived to give it one. Laid out bottom to top, the cards
    // still sit in the corner; the rest is empty and takes no input.
    height: parent.height
    interactive: false
    verticalLayoutDirection: ListView.BottomToTop
    spacing: 8
    model: cards

    add: Transition {
      ParallelAnimation {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Zenon.normal; easing.type: Zenon.ease }
        NumberAnimation { property: "slide"; from: 40; to: 0; duration: Zenon.normal; easing.type: Zenon.travelEase }
      }
    }
    remove: Transition {
      ParallelAnimation {
        NumberAnimation { property: "opacity"; to: 0; duration: Zenon.fast; easing.type: Zenon.ease }
        NumberAnimation { property: "slide"; to: 40; duration: Zenon.fast; easing.type: Zenon.ease }
      }
    }
    displaced: Transition {
      NumberAnimation { property: "y"; duration: Zenon.normal; easing.type: Zenon.travelEase }
    }

    delegate: Item {
      id: card
      required property int index
      required property int uid
      required property string text
      required property string tone
      required property bool sticky
      required property int serial
      required property int ask
      required property string choices
      readonly property var choiceList: { try { return JSON.parse(card.choices); } catch (e) { return []; } }

      property real slide: 0
      readonly property bool many: card.text.indexOf("\n") >= 0
      readonly property color inkC: root.ink(card.tone)
      readonly property real maxW: Math.min(list.width, 560)

      width: list.width
      height: body.height

      // its own clock: restarted by an update, held by the pointer
      Timer {
        id: life
        running: !card.sticky && !hover.hovered
        interval: card.tone === "error" ? root.timeout * 2
          : card.tone === "warn" ? root.timeout * 1.5 : root.timeout
        onTriggered: root.dismiss(card.uid)
      }
      onSerialChanged: life.restart()

      Rectangle {
        id: body
        x: list.width - width + card.slide
        width: Math.min(card.maxW, Math.max(180, words.implicitWidth + 30 + 28 + 18,
          card.ask > 0 ? buttons.implicitWidth + 42 + 18 : 0))
        height: Math.max(40, words.height + 22) + (card.ask > 0 ? buttons.height + 8 : 0)
        radius: Zenon.windowRadius
        color: Zenon.alpha(Zenon.card, 0.96)
        border.width: 1
        border.color: card.tone === "error" || card.tone === "warn"
          ? Qt.rgba(card.inkC.r, card.inkC.g, card.inkC.b, 0.45) : Zenon.border
        Behavior on width { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
        Behavior on height { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }

        // the kind's ink, down the leading edge
        Rectangle {
          x: 1
          y: 8
          width: 3
          height: parent.height - 16
          radius: 1.5
          color: card.inkC
          opacity: card.tone === "info" ? 0.5 : 0.9
        }
        Text {
          id: mark
          x: 16
          y: 11
          font.family: Zenon.faceMono
          font.weight: Zenon.weight
          font.pixelSize: root.face.pixelSize + 1
          color: card.inkC
          text: root.glyph(card.tone)
        }
        Text {
          id: words
          x: 16 + 26
          y: 11
          width: Math.min(implicitWidth, card.maxW - 42 - 18)
          wrapMode: Text.Wrap
          maximumLineCount: 20
          elide: Text.ElideRight
          textFormat: Text.PlainText
          // a listing is columns, and reads as columns
          font.family: card.many ? Zenon.faceFixed : Zenon.face
          font.pixelSize: card.many ? root.face.pixelSize - 2 : root.face.pixelSize - 1
          color: card.tone === "error" ? Zenon.red : Zenon.white
          lineHeight: 1.1
          text: card.text
        }
        // a question's choices: a button each, with its key
        Row {
          id: buttons
          visible: card.ask > 0
          x: 16 + 26
          y: words.y + words.height + 10
          height: visible ? 28 : 0
          spacing: 8
          Repeater {
            model: card.choiceList
            Rectangle {
              id: choice
              required property var modelData
              width: choiceRow.implicitWidth + 20
              height: 28
              radius: 5
              color: choiceHover.hovered ? Zenon.wash(0.1) : Zenon.wash(0.05)
              border.width: 1
              border.color: Zenon.border
              Row {
                id: choiceRow
                anchors.centerIn: parent
                spacing: 8
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: root.face.pixelSize - 2
                  color: Zenon.white
                  text: choice.modelData.label
                }
                KeyCap {
                  anchors.verticalCenter: parent.verticalCenter
                  label: "alt " + choice.modelData.key
                  fontSize: 11
                }
              }
              HoverHandler { id: choiceHover; cursorShape: Qt.PointingHandCursor }
              TapHandler { onTapped: root.answer(card.ask, choice.modelData.key) }
            }
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: 4
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: 12
            color: dismissHover.hovered ? Zenon.white : Zenon.muted
            text: "dismiss"
            HoverHandler { id: dismissHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.answer(card.ask, "") }
          }
        }
        // waiting for a key says so
        Text {
          visible: card.sticky && card.ask <= 0
          anchors.right: parent.right
          anchors.rightMargin: 10
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 6
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: 11
          color: Zenon.muted
          text: "any key"
        }
        HoverHandler { id: hover }
        // a question is put away by answering it, not by a stray click
        TapHandler { enabled: card.ask <= 0; onTapped: root.dismiss(card.uid) }
      }
    }
  }
}

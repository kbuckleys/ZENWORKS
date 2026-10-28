// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE LOOK-UP CARD (user, 2026-10-21: "word lookup can use lexi. you could
// also add translate, lexi covers that too"): the words selected, defined
// from Wiktionary or translated — both asked of lexi/lexi.js through the
// manager — in a card over the page's corner. "Open in Lexi" carries them
// over to Lexi itself, for its history, its pronunciation and the rest.
//
// A single word opens on its definition, more than three on the
// translation; the language is the one chosen last, Lexi's most used first.

import QtQuick
import "../morpheus"
import "../terminus"

Rectangle {
  id: card
  property var win: null
  readonly property var mgr: card.win ? card.win.mgr : null
  property string words: ""
  property string mode: "define"       // define · translate
  property bool shown: false
  // what the card is laid over, frosted under it (the window's reading box)
  property Item glass: null
  signal closed()

  // asked afresh when the words or the mode change
  property var result: null
  property string why: ""
  property bool busy: false
  property int seq: 0
  function ask(words, mode) {
    card.words = String(words || "").replace(/\s+/g, " ").trim();
    card.mode = mode || (card.words.split(" ").length > 3 ? "translate" : "define");
    card.shown = card.words !== "";
    card.fetch();
  }
  function fetch() {
    if (!card.mgr || card.words === "") return;
    const n = ++card.seq;
    card.result = null;
    card.why = "";
    card.busy = true;
    const done = (r, why) => { if (n !== card.seq) return; card.busy = false; card.result = r; card.why = why || ""; };
    if (card.mode === "define") card.mgr.define(card.words.split(" ").slice(0, 3).join(" "), done);
    else { card.askedIn = card.win.settings.translateTo; card.mgr.translate(card.words, card.askedIn, done); }
  }
  property string askedIn: ""
  Connections {
    target: card.win
    ignoreUnknownSignals: true
    function onSettingsChanged() { if (card.shown && card.mode === "translate" && card.askedIn !== card.win.settings.translateTo) card.fetch(); }
  }

  visible: opacity > 0
  opacity: card.shown ? 1 : 0
  Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Easing.OutCubic } }
  width: 400
  height: Math.min(col.implicitHeight + 32, 520)
  radius: Zenon.radiusCard
  color: Zenon.headBg
  border.width: 1
  border.color: Zenon.border
  clip: true
  // a sheet's card over live content (morpheus/Sheet's cardFrost), tracked
  Frost { anchors.fill: parent; z: -1; source: card.glass; active: card.visible; visible: active; radius: card.radius
    base: Zenon.black; brightness: -0.12; saturation: -0.3; blurMax: 32; scrim: 0; track: [card.x, card.y, card.width] }

  Column {
    id: col
    x: 18
    y: 16
    width: parent.width - 36
    spacing: 12

    Item {
      width: parent.width
      height: 30
      Segments {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        options: [["define", "Define"], ["translate", "Translate"]]
        current: card.mode
        onChose: (v) => { card.mode = v; card.fetch(); }
      }
      ClearChip {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        size: Zenon.px(15)
        shown: true
        onClicked: { card.shown = false; card.closed(); }
      }
    }

    // the word, and how it sounds
    Text {
      textFormat: Text.PlainText
      width: parent.width
      visible: card.mode === "define"
      elide: Text.ElideRight
      text: card.result && card.result.title ? card.result.title : card.words
      color: Zenon.ink
      font.family: card.mgr ? card.mgr.serifFace : Zenon.face
      font.pixelSize: Zenon.px(24)
      font.weight: Font.DemiBold
    }
    Text {
      visible: card.mode === "define" && !!card.result && !!card.result.ipa
      text: card.result && card.result.ipa ? card.result.ipa : ""
      color: Zenon.accentMuted
      font.family: Zenon.face
      font.pixelSize: Zenon.px(14)
    }

    EmptyState {
      width: parent.width
      visible: card.busy || card.why !== ""
      text: card.busy ? (card.mode === "define" ? "Looking it up…" : "Translating…") : card.why
    }

    // its senses, a few of each part of speech
    Flickable {
      id: defs
      width: parent.width
      visible: card.mode === "define" && !!card.result && !card.busy
      height: Math.min(defCol.implicitHeight, 300)
      contentHeight: defCol.implicitHeight
      clip: true
      interactive: false
      ElasticScroll { view: defs }
      Column {
        id: defCol
        width: defs.width
        spacing: 10
        Repeater {
          model: card.mode === "define" && card.result ? card.result.pos.slice(0, 4) : []
          delegate: Column {
            required property var modelData
            width: defCol.width
            spacing: 4
            SectionLabel { text: modelData.name }
            Repeater {
              model: modelData.defs.slice(0, 3)
              delegate: Text {
                required property var modelData
                required property int index
                width: defCol.width
                wrapMode: Text.WordWrap
                text: (index + 1) + ".  " + modelData.def + (modelData.example ? "\n     “" + modelData.example + "”" : "")
                color: Zenon.white
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(14)
                lineHeight: 1.15
              }
            }
          }
        }
      }
    }

    // the translation, and the language it is in
    Text {
      textFormat: Text.PlainText
      width: parent.width
      visible: card.mode === "translate"
      maximumLineCount: 4
      elide: Text.ElideRight
      wrapMode: Text.WordWrap
      text: "“" + card.words + "”"
      color: Zenon.accentMuted
      font.family: card.mgr ? card.mgr.serifFace : Zenon.face
      font.pixelSize: Zenon.px(14)
    }
    Text {
      width: parent.width
      visible: card.mode === "translate" && !!card.result && !card.busy
      wrapMode: Text.WordWrap
      text: card.result && card.result.translation ? card.result.translation : ""
      color: Zenon.ink
      font.family: card.mgr ? card.mgr.serifFace : Zenon.face
      font.pixelSize: Zenon.px(17)
      textFormat: Text.PlainText
    }

    Row {
      spacing: 8
      DialogButton {
        id: langBtn
        visible: card.mode === "translate"
        implicitHeight: 30
        held: card.win.heldBy(langBtn)
        label: (card.result && card.result.source ? card.mgr.languageName(card.result.source) + "  →  " : "")
          + (card.mgr ? card.mgr.languageName(card.win.settings.translateTo) : "")
        onClicked: card.win.openMenu(langBtn, card.mgr.languages().map((l) => ({
          text: l.name, mark: l.code === card.win.settings.translateTo ? "✓" : "",
          run: () => card.mgr.setSetting("translateTo", l.code)
        })))
      }
      DialogButton {
        implicitHeight: 30
        label: "Open in Lexi"
        ink: Zenon.cyan
        onClicked: { card.mgr.openInLexi(card.words, card.mode === "translate"); card.shown = false; card.closed(); }
      }
    }
  }
}

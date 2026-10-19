// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ONE ITEM, IN FULL — the window's right side. Its face and name large at
// the top; then its fields in rounded cards, one card a section (the
// login's own, its websites, the rest), each field its label over its
// value; then its notes, its tags and when it changed.
//
// A secret is dots until Reveal (the daemon sends it only then — see
// calypso/core/server.py); Copy never brings it here at all. The one-time
// password is the code itself, in two halves, beside the ring of how long
// it has left; it turns over on its own.
//
// Everything it does goes through the window (win.copyField, win.revealField,
// win.openUrl, win.fieldMenu), so a key in the window and a click here are
// the same act.

import QtQuick
import "../morpheus"
import "../ceres"
import "calypso.js" as C

Item {
  id: pane
  property var win: null
  readonly property var it: pane.holding ? pane.heldIt : (win ? win.item : null)
  readonly property var d: pane.holding ? pane.heldD : (win ? win.detail : null)
  // ── THE LAST ITEM STAYS UNTIL THE NEXT ONE IS IN (2026-10-14) ─────────
  // Every new choice blanked the fields for a frame — the new name over the
  // asking dots — before the daemon's answer came, a flicker on every click
  // (user's flicker capture). The pane now keeps drawing the item it had,
  // name and fields together, until the next one's detail is in (or
  // holdCap: a slow vault shows the dots as before). The window's own
  // item/detail move at once, so a key acts on the chosen item; the pane
  // takes no clicks while it holds.
  property var heldIt: null
  property var heldD: null
  property bool holding: false
  property var lastIt: null
  property var lastD: null
  // the window forgot (an account locked, it hid): nothing to hold on to
  function drop() { pane.lastIt = null; pane.lastD = null; pane.release(); }
  function release() { holdCap.stop(); pane.holding = false; pane.heldIt = null; pane.heldD = null; }
  Timer { id: holdCap; interval: 200; onTriggered: pane.release() }
  Connections {
    target: pane.win
    function onDetailChanged() {
      if (!pane.win.detail) return;
      pane.lastIt = pane.win.item;
      pane.lastD = pane.win.detail;
      pane.release();
    }
    function onItemChanged() {
      const it = pane.win.item;
      if (!it || !pane.lastD || C.keyOf(it) === C.keyOf(pane.lastIt) || pane.win.inTrash) { pane.release(); return; }
      if (pane.win.detail && C.keyOf(pane.lastIt) === C.keyOf(pane.win.item)) return;
      if (!pane.holding) { pane.heldIt = pane.lastIt; pane.heldD = pane.lastD; pane.holding = true; }
      holdCap.restart();
    }
    function onDetailErrChanged() { if (pane.win.detailErr !== "") pane.release(); }
  }
  enabled: !pane.holding
  // BEHIND THE RE-PROMPT, the keys are its field's. A PasswordField draws
  // and never listens, and nothing handed it a key: every one went to the
  // search, so a card that asks again could never be opened (user,
  // 2026-10-14). The window hands them here (win.key) while this is up.
  readonly property bool asking: !!pane.d && !!pane.d.reprompt
  function key(e) { return pane.asking && rePw.key(e); }
  function keyUp(e) { return pane.asking && rePw.keyUp(e); }
  readonly property alias flick: flick

  Flickable {
    id: flick
    anchors.fill: parent
    contentWidth: width
    contentHeight: body.implicitHeight + 120
    boundsBehavior: Flickable.StopAtBounds
    clip: true
    topMargin: 0
    bottomMargin: 40
    interactive: contentHeight > height

    Column {
      id: body
      x: Math.max(28, (flick.width - width) / 2)
      width: Math.min(flick.width - 56, 720)
      spacing: 18
      opacity: pane.it ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Zenon.fast } }

      Item { width: 1; height: 8 }

      // ── its face and name ─────────────────────────────────────────────
      Item {
        width: parent.width
        height: 72
        ItemTile {
          id: face
          item: pane.it
          size: 64
          lit: true
          ringed: false
          anchors.verticalCenter: parent.verticalCenter
        }
        Column {
          anchors.left: face.right
          anchors.leftMargin: 18
          anchors.right: headActs.left
          anchors.rightMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          spacing: 4
          Text {
            width: parent.width
            elide: Text.ElideRight
            text: pane.it ? pane.it.title : ""
            color: Zenon.ink
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: Zenon.px(24)
          }
          Row {
            spacing: 8
            width: parent.width
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: pane.win ? C.platform(pane.win.acctOf(pane.it).kind).glyph : ""
              color: pane.win ? (Zenon[C.platform(pane.win.acctOf(pane.it).kind).ink] || Zenon.accentMuted) : Zenon.accentMuted
              font.family: Zenon.glyphFace
              font.pixelSize: Zenon.px(13)
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, parent.width - 30)
              elide: Text.ElideMiddle
              text: !pane.it || !pane.win ? "" : [C.kindOf(pane.it.kind).one, pane.it.folder,
                     (pane.win.acctOf(pane.it) || {}).name].filter((s) => !!s).join("  ·  ")
              color: Zenon.accentMuted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(14)
            }
          }
        }
        Row {
          id: headActs
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: 4
          FieldAct {
            visible: !!pane.win && pane.win.canEdit(pane.it) && !pane.win.inTrash
            glyph: "\uF044"
            tip: "Edit"
            tips: pane.win ? pane.win.tipsItem : null
            onClicked: pane.win.editItem()
          }
          FieldAct {
            glyph: pane.win && pane.it && pane.win.isFav(pane.it) ? "" : ""
            ink: pane.win && pane.it && pane.win.isFav(pane.it) ? Zenon.sand : Zenon.accentMuted
            tip: pane.win && pane.it && pane.win.isFav(pane.it) ? "Leave favorites" : "Add to favorites"
            tips: pane.win ? pane.win.tipsItem : null
            onClicked: pane.win.toggleFav(pane.it)
          }
          FieldAct {
            id: moreAct
            glyph: "\u{F01D8}"
            tip: "More"
            tips: pane.win ? pane.win.tipsItem : null
            on: pane.win && pane.win.menuHeld === "detail"
            onClicked: { const p = moreAct.mapToItem(pane.win.stageItem, 0, moreAct.height + 4); pane.win.itemMenu(pane.it, p.x - 200, p.y, "detail"); }
          }
        }
      }

      // ── what Watchtower found ────────────────────────────────────────
      Repeater {
        model: pane.win && pane.it ? (pane.win.mgr.flags[C.keyOf(pane.it)] || []) : []
        delegate: Rectangle {
          required property var modelData
          readonly property var pr: C.problem(modelData)
          width: body.width
          height: 44
          radius: Zenon.windowRadius + 2
          color: Zenon.alpha(Zenon[pr.ink] || Zenon.accentMuted, 0.1)
          border.width: 1
          border.color: Zenon.alpha(Zenon[pr.ink] || Zenon.accentMuted, 0.4)
          Row {
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "\u{F0ECC}"
              color: Zenon[parent.parent.pr.ink] || Zenon.accentMuted
              font.family: Zenon.glyphFace
              font.pixelSize: Zenon.px(15)
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "<b>" + parent.parent.pr.label + "</b>  \u00b7  " + parent.parent.pr.say
              textFormat: Text.StyledText
              color: Zenon.ink
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(13)
            }
          }
        }
      }

      // ── in the trash ─────────────────────────────────────────────────
      Rectangle {
        visible: !!pane.win && pane.win.inTrash && !!pane.it
        width: parent.width
        height: visible ? trashCol.implicitHeight + 32 : 0
        radius: Zenon.windowRadius + 4
        color: Zenon.wash(0.04)
        border.width: 1
        border.color: Zenon.border
        Column {
          id: trashCol
          anchors.centerIn: parent
          width: parent.width - 32
          spacing: 12
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "In the trash" + (pane.it && pane.it.sub ? "  \u00b7  " + pane.it.sub : "")
            color: Zenon.ink
            font.family: Zenon.face
            font.weight: Font.DemiBold
            font.pixelSize: Zenon.px(15)
          }
          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            DialogButton { label: "Delete forever"; ink: Zenon.red; onClicked: pane.win.deleteItem(pane.it, true) }
            DialogButton { label: "Restore"; ink: Zenon.cyan; primary: true; onClicked: pane.win.restoreItem(pane.it) }
          }
        }
      }

      // ── behind Bitwarden's re-prompt ─────────────────────────────────
      Rectangle {
        visible: !!pane.d && !!pane.d.reprompt
        width: parent.width
        height: visible ? reCol.implicitHeight + 32 : 0
        radius: Zenon.windowRadius + 4
        color: Zenon.wash(0.04)
        border.width: 1
        border.color: Zenon.border
        // a click on it takes the keys back from the search
        MouseArea { anchors.fill: parent; onClicked: pane.win.takeKeys() }
        Column {
          id: reCol
          anchors.centerIn: parent
          width: parent.width - 32
          spacing: 6
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "This item asks for your master password again"
            color: Zenon.ink
            font.family: Zenon.face
            font.weight: Font.DemiBold
            font.pixelSize: Zenon.px(15)
          }
          PasswordField {
            id: rePw
            width: parent.width
            prompt: "input your master password"
            purpose: "shows this item, once"
            busy: !!pane.win && pane.win.detailBusy
            onSubmitted: (p) => pane.win.reprompt(p)
          }
        }
      }

      // ── its fields, a card each section ──────────────────────────────
      Repeater {
        model: pane.d && pane.d.sections ? pane.d.sections : []
        delegate: Column {
          id: sec
          required property var modelData
          width: body.width
          spacing: 6
          Text {
            visible: sec.modelData.title !== ""
            leftPadding: 4
            text: sec.modelData.title.toUpperCase()
            color: Zenon.accentMuted
            font.family: Zenon.face
            font.weight: Font.DemiBold
            font.pixelSize: Zenon.px(11)
            font.letterSpacing: 1.2
          }
          Rectangle {
            width: sec.width
            height: rows.implicitHeight
            radius: Zenon.windowRadius + 4
            color: Zenon.wash(0.04)
            border.width: 1
            border.color: Zenon.border
            Column {
              id: rows
              width: parent.width
              Repeater {
                model: sec.modelData.fields
                delegate: FieldRow {
                  required property var modelData
                  required property int index
                  width: rows.width
                  win: pane.win
                  field: modelData
                  ruled: index > 0
                }
              }
            }
          }
        }
      }

      // ── files kept with it ───────────────────────────────────────────
      Column {
        readonly property var atts: pane.d && pane.d.attachments ? pane.d.attachments : []
        visible: !!pane.d && !pane.d.reprompt && (atts.length > 0 || (!!pane.win && pane.win.canAttach(pane.it)))
        width: parent.width
        spacing: 6
        Text {
          leftPadding: 4
          text: "ATTACHMENTS"
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Font.DemiBold
          font.pixelSize: Zenon.px(11)
          font.letterSpacing: 1.2
        }
        Rectangle {
          visible: parent.atts.length > 0
          width: parent.width
          height: attCol.implicitHeight
          radius: Zenon.windowRadius + 4
          color: Zenon.wash(0.04)
          border.width: 1
          border.color: Zenon.border
          Column {
            id: attCol
            width: parent.width
            Repeater {
              model: parent.parent.parent.atts
              delegate: Item {
                required property var modelData
                required property int index
                width: attCol.width
                height: 48
                Rectangle { visible: index > 0; x: 16; width: parent.width - 32; height: 1; color: Zenon.border }
                Text {
                  id: attGlyph
                  x: 18
                  anchors.verticalCenter: parent.verticalCenter
                  text: "\u{F03E2}"
                  color: Zenon.accentMuted
                  font.family: Zenon.glyphFace
                  font.pixelSize: Zenon.px(15)
                }
                Text {
                  anchors.left: attGlyph.right
                  anchors.leftMargin: 10
                  anchors.right: attActs.left
                  anchors.rightMargin: 8
                  anchors.verticalCenter: parent.verticalCenter
                  elide: Text.ElideMiddle
                  text: modelData.name + (modelData.size ? "  <font color='" + Zenon.accentMuted + "'>" + modelData.size + "</font>" : "")
                  textFormat: Text.StyledText
                  color: Zenon.ink
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(14)
                }
                Row {
                  id: attActs
                  anchors.right: parent.right
                  anchors.rightMargin: 12
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 2
                  FieldAct { glyph: "\uF019"; tip: "Save it somewhere"; tips: pane.win ? pane.win.tipsItem : null; onClicked: pane.win.saveAttachment(modelData) }
                  FieldAct { glyph: "\u{F0A7A}"; ink: Zenon.red; tip: "Remove it"; tips: pane.win ? pane.win.tipsItem : null; onClicked: pane.win.removeAttachment(modelData) }
                }
              }
            }
          }
        }
        Text {
          visible: !!pane.win && pane.win.canAttach(pane.it)
          leftPadding: 4
          text: "\u{F03E2}  Attach a file"
          color: Zenon.cyan
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
          MouseArea { anchors.fill: parent; onClicked: pane.win.addAttachment() }
        }
      }

      // ── its notes ────────────────────────────────────────────────────
      Column {
        visible: !!pane.d && pane.d.notes !== ""
        width: parent.width
        spacing: 6
        Text {
          leftPadding: 4
          text: "NOTES"
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Font.DemiBold
          font.pixelSize: Zenon.px(11)
          font.letterSpacing: 1.2
        }
        Rectangle {
          width: parent.width
          height: notes.implicitHeight + 28
          radius: Zenon.windowRadius + 4
          color: Zenon.wash(0.04)
          border.width: 1
          border.color: Zenon.border
          TextEdit {
            id: notes
            x: 16
            y: 14
            width: parent.width - 32
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.Wrap
            text: pane.d ? pane.d.notes : ""
            color: Zenon.accentSoft
            selectionColor: Zenon.alpha(Zenon.cyan, 0.4)
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(14)
          }
        }
      }

      // ── its tags: each a way to the others wearing it ────────────────
      Flow {
        visible: !!pane.it && pane.it.tags.length > 0
        width: parent.width
        spacing: 6
        Repeater {
          model: pane.it ? pane.it.tags : []
          delegate: Rectangle {
            required property var modelData
            height: 26
            width: tagText.implicitWidth + 22
            radius: height / 2
            color: tagPress.pressed ? Zenon.pressWash(0.14) : Zenon.alpha(Zenon.magenta, 0.1)
            border.width: 1
            border.color: Zenon.alpha(Zenon.magenta, 0.35)
            Text {
              id: tagText
              anchors.centerIn: parent
              text: "  " + modelData
              color: Zenon.magenta
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(12)
            }
            MouseArea { id: tagPress; anchors.fill: parent; onClicked: pane.win.setScope({ shelf: "all", tag: modelData }) }
          }
        }
      }

      // ── when ─────────────────────────────────────────────────────────
      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        visible: text !== ""
        topPadding: 6
        text: {
          if (!pane.d) return "";
          const bits = [];
          if (pane.d.updated) bits.push("Changed " + C.dateWords(pane.d.updated));
          if (pane.d.created) bits.push("made " + C.dateWords(pane.d.created));
          return bits.join("  ·  ");
        }
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(12)
      }
    }
  }
  ElasticScroll { anchors.fill: flick; view: flick }
  Scrollbar { flick: flick; anchors.right: flick.right; anchors.top: flick.top; anchors.bottom: flick.bottom }

  // asking the vault: the shell's dots, where the fields will be
  Working {
    anchors.horizontalCenter: parent.horizontalCenter
    y: 140
    running: !!pane.win && pane.win.detailBusy && !pane.d
    visible: running
  }
  // nothing chosen, or an item that would not open
  Column {
    anchors.centerIn: parent
    visible: !pane.it || (!!pane.win && pane.win.detailErr !== "" && !pane.d)
    spacing: 10
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: ""
      color: Zenon.alpha(Zenon.accentMuted, 0.35)
      font.family: Zenon.glyphFace
      font.pixelSize: 72
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: pane.win && pane.win.detailErr !== "" && pane.it ? pane.win.detailErr : "Nothing chosen"
      color: pane.win && pane.win.detailErr !== "" && pane.it ? Zenon.red : Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(15)
    }
  }
}

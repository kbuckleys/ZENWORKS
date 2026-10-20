// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// AN ITEM, BEING MADE OR CHANGED — the window's right side while editing,
// laid out as the item itself is (ItemDetail), every value now a field:
//
//   its name, the account it goes in (a new one, several to choose from:
//   terminus' Segments) and its folder (typed, or one of those there are)
//   its kind's fields (C.FIELDS): a secret masked, a password with the
//   generator's dice and its strength, a one-time password scanned off the
//   screen or pasted
//   its websites; fields of your own, hidden or plain; its notes (delphi's
//   MessageWell); its tags; a favorite
//
// What the platform's tool cannot do (C.can — the daemon's `can`) is not
// offered: a field of your own on a platform without them, a one-time
// password where it cannot be set.
//
// The state is C.editState's; the window sends C.draftOf it (win.saveEdit).

import QtQuick
import "../morpheus"
import "../morpheus/controls" as Controls
import "../terminus"
import "../picasso"
import "../delphi"
import "calypso.js" as C

Item {
  id: ed
  property var win: null
  // C.editState; held, mutated in place as fields are typed (a field's text
  // is never bound back, so typing keeps its caret)
  property var st: null
  readonly property var acct: ed.win && ed.st ? ed.win.mgr.accountOf(ed.st.acct) || {} : {}
  readonly property var info: ed.win ? ed.win.mgr.platformInfo(ed.acct.kind) : null
  readonly property alias flick: flick
  property bool dirty: false
  // a list of the editor's rows rebuilt (a website or a field added or
  // taken away): its own counter, so the Repeaters build from the state anew
  property int shape: 0

  function touch() { ed.dirty = true; }
  // the fields that are not a Repeater's, filled when the state arrives
  // (the window hands it in after the editor is made)
  onStChanged: if (ed.st) {
    titleBox.text = ed.st.title;
    folderBox.text = ed.st.folder;
    notesWell.text = ed.st.notes;
    tagsBox.text = ed.st.tags;
    ed.dirty = false;
  }
  function rebuild() { ed.shape++; ed.touch(); }
  function focusFirst() { Qt.callLater(() => titleBox.claim()); }

  Flickable {
    id: flick
    anchors.fill: parent
    contentWidth: width
    contentHeight: body.implicitHeight + 120
    boundsBehavior: Flickable.StopAtBounds
    clip: true
    bottomMargin: 40

    Column {
      id: body
      x: Math.max(28, (flick.width - width) / 2)
      width: Math.min(flick.width - 56, 720)
      spacing: 18

      Item { width: 1; height: 8 }

      // ── its name, its account, its folder ─────────────────────────────
      Row {
        width: parent.width
        spacing: 18
        ItemTile {
          id: face
          anchors.verticalCenter: parent.verticalCenter
          size: 64
          lit: true
          glyph: ed.st ? C.kindOf(ed.st.kind).glyph : ""
          ink: ed.st ? C.kindOf(ed.st.kind).ink : "cyan"
        }
        Column {
          width: parent.width - face.width - 18
          spacing: 8
          BulkField {
            id: titleBox
            width: parent.width
            textSize: Zenon.px(20)
            ghost: ed.st ? C.kindOf(ed.st.kind).one + " name" : ""
            onTextChanged: if (ed.st && ed.st.title !== text) { ed.st.title = text; ed.touch(); }
          }
          Row {
            spacing: 10
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: ed.st ? C.kindOf(ed.st.kind).one : ""
              color: Zenon.accentMuted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(13)
            }
            // a new item, several accounts it could go in
            Segments {
              anchors.verticalCenter: parent.verticalCenter
              visible: !!ed.st && ed.st.id === "" && ed.win.writable(ed.st.kind).length > 1
              options: ed.st ? ed.win.writable(ed.st.kind).map((a) => [a.id, a.name]) : []
              current: ed.st ? ed.st.acct : ""
              textSize: Zenon.px(12)
              onChose: (v) => { ed.st.acct = v; ed.st.folder = ""; folderBox.text = ""; ed.rebuild(); }
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: !!ed.st && (ed.st.id !== "" || ed.win.writable(ed.st.kind).length <= 1)
              text: (C.platform(ed.acct.kind).glyph || "") + "  " + (ed.acct.name || "")
              color: Zenon.accentMuted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(13)
            }
          }
          // the folder: typed (a new one is made), or chosen from the menu
          Row {
            visible: C.can(ed.info, "folders")
            spacing: 4
            BulkField {
              id: folderBox
              width: 260
              textSize: Zenon.px(13)
              ghost: ed.acct.kind === "onepassword" || ed.acct.kind === "proton" ? "Vault" : "No folder"
              onTextChanged: if (ed.st && ed.st.folder !== text) { ed.st.folder = text; ed.touch(); }
            }
            FieldAct {
              id: folderPick
              anchors.verticalCenter: parent.verticalCenter
              glyph: ""
              tip: "Folders there are"
              tips: ed.win ? ed.win.tipsItem : null
              onClicked: ed.win.mgr.call("folders", ed.acct, {}, (ok, list) => {
                if (!ok) return;
                const p = folderPick.mapToItem(ed.win.stageItem, 0, folderPick.height + 4);
                ed.win.menuAt(p.x, p.y, (list.length ? list : [""]).map((f) => ({
                  text: f || "(none)", icon: f === folderBox.text ? "" : "", enabled: f !== "" || list.length === 0,
                  run: () => { folderBox.text = f; } })));
              })
            }
          }
        }
      }

      // ── its kind's fields ─────────────────────────────────────────────
      Rectangle {
        visible: !!ed.st && C.fieldsOf(ed.st.kind).length > 0
        width: parent.width
        height: stdCol.implicitHeight
        radius: Zenon.windowRadius + 4
        color: Zenon.wash(0.04)
        border.width: 1
        border.color: Zenon.border
        Column {
          id: stdCol
          width: parent.width
          Repeater {
            model: ed.st ? C.fieldsOf(ed.st.kind).filter((f) => !f.totp || C.can(ed.info, "totpEdit")) : []
            delegate: EditRow {
              id: er
              required property var modelData
              required property int index
              readonly property var slot: ed.st.std[modelData.key]
              width: stdCol.width
              win: ed.win
              ruled: index > 0
              label: modelData.label
              hint: modelData.hint || ""
              secret: !!modelData.secret
              known: !!slot && slot.known
              gen: !!modelData.gen
              totp: !!modelData.totp
              Component.onCompleted: text = slot ? slot.value : ""
              onEdited: (t) => { if (!slot || slot.value === t) return; slot.value = t; if (!slot.known && t !== "") { slot.known = true; er.known = true; } ed.touch(); }
              onRevealWanted: ed.win.revealForEdit(modelData.key, (v) => { er.text = v; slot.value = v; slot.known = true; er.known = true; er.showing = true; })
              onGenerateWanted: ed.win.openGenerator((v) => { er.text = v; er.showing = true; })
              onScanWanted: ed.win.scanQr((uri) => { er.text = uri; er.showing = true; })
            }
          }
        }
      }

      // ── its websites ──────────────────────────────────────────────────
      Column {
        visible: !!ed.st && (ed.st.kind === "login" || ed.st.urls.length > 0)
        width: parent.width
        spacing: 6
        SectionLabel {
          leftPadding: 4
          text: "WEBSITES"
        }
        Rectangle {
          width: parent.width
          height: urlCol.implicitHeight
          radius: Zenon.windowRadius + 4
          color: Zenon.wash(0.04)
          border.width: 1
          border.color: Zenon.border
          Column {
            id: urlCol
            width: parent.width
            Repeater {
              model: ed.st ? (void ed.shape, ed.st.urls.length) : 0
              delegate: EditRow {
                required property int index
                width: urlCol.width
                win: ed.win
                ruled: index > 0
                label: "Website"
                hint: "https://example.com"
                removable: true
                Component.onCompleted: text = ed.st.urls[index] || ""
                onEdited: (t) => { if (ed.st.urls[index] !== t) { ed.st.urls[index] = t; ed.touch(); } }
                onRemoved: { ed.st.urls.splice(index, 1); ed.rebuild(); }
              }
            }
          }
        }
        Text {
          leftPadding: 4
          text: "  Add a website"
          color: Zenon.cyan
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
          MouseArea { anchors.fill: parent; onClicked: { ed.st.urls.push(""); ed.rebuild(); } }
        }
      }

      // ── fields of your own ────────────────────────────────────────────
      Column {
        visible: C.can(ed.info, "custom")
        width: parent.width
        spacing: 6
        SectionLabel {
          leftPadding: 4
          text: "MORE"
        }
        Rectangle {
          visible: !!ed.st && (void ed.shape, ed.st.custom.length > 0)
          width: parent.width
          height: customCol.implicitHeight
          radius: Zenon.windowRadius + 4
          color: Zenon.wash(0.04)
          border.width: 1
          border.color: Zenon.border
          Column {
            id: customCol
            width: parent.width
            Repeater {
              model: ed.st ? (void ed.shape, ed.st.custom.length) : 0
              delegate: EditRow {
                id: cr
                required property int index
                readonly property var c: ed.st.custom[index]
                width: customCol.width
                win: ed.win
                ruled: index > 0
                labelEditable: true
                secret: !!c && c.hidden
                known: !!c && c.known
                hideToggle: true
                removable: true
                Component.onCompleted: { labelText = c ? c.label : ""; text = c ? c.value : ""; }
                onLabelEdited: (t) => { if (c.label !== t) { c.label = t; ed.touch(); } }
                onEdited: (t) => { if (c.value === t) return; c.value = t; if (!c.known && t !== "") { c.known = true; cr.known = true; } ed.touch(); }
                onHiddenToggled: { c.hidden = !c.hidden; cr.secret = c.hidden; ed.touch(); }
                onRevealWanted: ed.win.revealForEdit(c.ref, (v) => { cr.text = v; c.value = v; c.known = true; cr.known = true; cr.showing = true; })
                onRemoved: { ed.st.custom.splice(index, 1); ed.rebuild(); }
              }
            }
          }
        }
        Row {
          spacing: 18
          Text {
            leftPadding: 4
            text: "  Add a field"
            color: Zenon.cyan
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(13)
            MouseArea { anchors.fill: parent
              onClicked: { ed.st.custom.push({ ref: "", label: "", value: "", known: true, hidden: false }); ed.rebuild(); } }
          }
          Text {
            text: "  Add a hidden field"
            color: Zenon.cyan
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(13)
            MouseArea { anchors.fill: parent
              onClicked: { ed.st.custom.push({ ref: "", label: "", value: "", known: true, hidden: true }); ed.rebuild(); } }
          }
        }
      }

      // ── its notes ─────────────────────────────────────────────────────
      Column {
        width: parent.width
        spacing: 6
        SectionLabel {
          leftPadding: 4
          text: "NOTES"
        }
        MessageWell {
          id: notesWell
          width: parent.width
          height: Math.max(110, edit.contentHeight + 30)
          ghost: "Notes — kept with the item, as it is"
          onTextChanged: if (ed.st && ed.st.notes !== text) { ed.st.notes = text; ed.touch(); }
          onSubmitted: ed.win.saveEdit()
          onEscaped: ed.win.cancelEdit()
        }
      }

      // ── its tags, and a favorite ─────────────────────────────────────
      Column {
        visible: C.can(ed.info, "tags")
        width: parent.width
        spacing: 6
        SectionLabel {
          leftPadding: 4
          text: "TAGS"
        }
        BulkField {
          id: tagsBox
          width: parent.width
          textSize: Zenon.px(14)
          ghost: "Work, banking — separated by commas"
          onTextChanged: if (ed.st && ed.st.tags !== text) { ed.st.tags = text; ed.touch(); }
        }
      }
      Controls.Check {
        height: 28
        visible: C.can(ed.info, "fav")
        width: parent.width
        label: "A favorite, in " + C.platform(ed.acct.kind).name + " too"
        lit: !!ed.st && ed.st.fav
        onToggled: { ed.st.fav = !ed.st.fav; lit = ed.st.fav; ed.touch(); }
      }
    }
  }
  ElasticScroll { anchors.fill: flick; view: flick }
  Scrollbar { flick: flick; anchors.right: flick.right; anchors.top: flick.top; anchors.bottom: flick.bottom }
}

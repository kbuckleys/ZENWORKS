// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A RELEASE BEING WRITTEN — the Releases page, given over to one release, new
// or one there is (user, 2026-10-11: a sheet was too tight for its notes).
// Across the top its tag, the branch it is made from (a new one only) and
// its title; draft and pre-release where the forge has them; then the notes,
// the rest of the page — written, or previewed as the forge will show them,
// and "Write them for me" for GitHub's own or the commits since the last
// tag. Saving and cancelling are the page's buttons; ctrl return saves.
//
// The fields write into page.edit as they are typed; reset() puts
// page.edit back into them (opening one, notes written for you).

import QtQuick
import Quickshell
import "../morpheus"
import "../terminus"
import "../picasso"
import "delphi.js" as D

Item {
  id: ed
  property var page: null
  readonly property var e: ed.page ? ed.page.edit : null
  readonly property bool typing: tagField.focused || titleField.focused || notes.focused
  property string showing: "write"   // write | preview

  function claim() { if (ed.e && ed.e.mode === "new") tagField.claim(); else notes.claim(); }
  function reset() {
    if (!ed.e) return;
    tagField.text = ed.e.tag;
    titleField.text = ed.e.name;
    notes.text = ed.e.body;
  }
  // a different release opened: its own values in the fields
  property string _for: ""
  onEChanged: {
    const k = ed.e ? ed.e.mode + ":" + (ed.e.id || "") : "";
    if (k !== ed._for) { ed._for = k; ed.showing = "write"; ed.reset(); if (ed.e) Qt.callLater(ed.claim); }
  }

  Column {
    id: top
    x: 24
    y: 18
    width: parent.width - 48
    spacing: 12

    Row {
      width: parent.width
      spacing: 12
      Column {
        spacing: 5
        width: 170
        Text { text: "Tag"; color: Zenon.accentMuted; font.family: Zenon.face; font.weight: Zenon.weight; font.pixelSize: Zenon.px(13) }
        BulkField {
          id: tagField
          width: parent.width
          height: Math.round(Zenon.px(15) * 2.2)
          textSize: Zenon.px(15)
          ghost: "v1.0.0"
          // a release there is keeps its tag on GitLab, which knows it by it
          enabled: !!ed.e && (ed.e.mode === "new" || !/^gitlab/.test(ed.page.hub ? ed.page.hub.forge : ""))
          opacity: enabled ? 1 : 0.6
          onTextChanged: if (ed.e && text !== ed.e.tag) ed.page.setEdit("tag", text)
          onTabbed: titleField.claim()
          onAccepted: titleField.claim()
        }
      }
      Column {
        visible: !!ed.e && ed.e.mode === "new"
        spacing: 5
        Text { text: "From"; color: Zenon.accentMuted; font.family: Zenon.face; font.weight: Zenon.weight; font.pixelSize: Zenon.px(13) }
        DialogButton {
          id: fromBtn
          height: Math.round(Zenon.px(15) * 2.2)
          label: (ed.e ? ed.e.target || "HEAD" : "") + "   "
          onClicked: {
            const items = ed.page.win.refs.local.map((l) => ({
              text: l.name, icon: ed.e && l.name === ed.e.target ? "" : "",
              run: () => ed.page.setEdit("target", l.name) }));
            const p = fromBtn.mapToItem(ed, 0, fromBtn.height + 4);
            fromPop.open(p.x, p.y, items);
          }
        }
      }
      Column {
        spacing: 5
        width: parent.width - x
        Text { text: "Title"; color: Zenon.accentMuted; font.family: Zenon.face; font.weight: Zenon.weight; font.pixelSize: Zenon.px(13) }
        BulkField {
          id: titleField
          width: parent.width
          height: Math.round(Zenon.px(15) * 2.2)
          textSize: Zenon.px(15)
          ghost: ed.e ? ed.e.tag || "the tag, unless you name it" : ""
          onTextChanged: if (ed.e && text !== ed.e.name) ed.page.setEdit("name", text)
          onTabbed: notes.claim()
          onBackTabbed: tagField.claim()
          onAccepted: notes.claim()
        }
      }
    }

    // what it will be made from, said where it matters
    Text {
      width: parent.width
      visible: text !== ""
      wrapMode: Text.Wrap
      text: !ed.e ? ""
        : ed.e.mode === "new" ? (ed.e.prev !== "" ? "The last tag is " + ed.e.prev + ". " : "No tags yet. ")
          + ed.page.site.name + " makes the tag on " + (ed.e.target || "the branch") + " as it has it"
          + (ed.e.unpushed > 0 ? " — " + ed.e.unpushed + (ed.e.unpushed === 1 ? " commit" : " commits") + " here are not pushed yet, and would not be in it." : ".")
        : ed.e.wasDraft ? "A draft: only you see it until it is published." : ""
      color: ed.e && ed.e.unpushed > 0 ? Zenon.yellow : Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
    }

    Row {
      visible: ed.page && ed.page.drafts
      spacing: 28
      Switch {
        width: 300
        height: 26
        label: "A draft — only you see it, until published"
        on: !!ed.e && ed.e.draft
        onToggled: ed.page.setEdit("draft", !ed.e.draft)
      }
      Switch {
        width: 200
        height: 26
        label: "A pre-release"
        on: !!ed.e && ed.e.prerelease
        onToggled: ed.page.setEdit("prerelease", !ed.e.prerelease)
      }
    }

    Item {
      width: parent.width
      height: notesSeg.height
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "Notes"
        color: Zenon.ink
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(15)
      }
      Segments {
        id: notesSeg
        anchors.horizontalCenter: parent.horizontalCenter
        textSize: Zenon.px(13)
        options: [["write", "Write"], ["preview", "Preview"]]
        current: ed.showing
        onChose: (v) => ed.showing = v
      }
      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10
        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: !!ed.e && ed.e.by !== ""
          text: ed.e && ed.e.by === "github" ? "written by GitHub, from what was merged" : ed.e && ed.e.by === "commits" ? "written from the commits since " + (ed.e.prev || "the start") : ""
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
        DialogButton {
          label: ed.page && ed.page.writing ? "Writing…" : "Write them for me"
          ready: !!ed.page && !ed.page.writing && !!ed.e && ed.e.tag.trim() !== ""
          onClicked: ed.page.writeNotes()
        }
      }
    }
  }

  // ── the notes: the rest of the page ──
  MessageWell {
    id: notes
    visible: ed.showing === "write"
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: top.bottom
    anchors.bottom: parent.bottom
    anchors.leftMargin: 24
    anchors.rightMargin: 24
    anchors.topMargin: 10
    anchors.bottomMargin: 18
    textSize: Zenon.px(15)
    ghost: "What is in it — markdown: ## headings, - lists, **bold**, `code`, [links](https://…)"
    note: ed.e ? (ed.e.body.length > 0 ? ed.e.body.split("\n").length + " lines" : "") : ""
    onTextChanged: if (ed.e && text !== ed.e.body) ed.page.setEdit("body", text)
    passKeys: (k) => ed.page.win.key(k)
    onSubmitted: ed.page.save()
    onEscaped: ed.page.cancelEdit()
    onBackTabbed: titleField.claim()
  }
  Rectangle {
    visible: ed.showing === "preview"
    anchors.fill: notes
    radius: Zenon.windowRadius
    color: Zenon.wash(0.03)
    border.width: 1
    border.color: Zenon.border
    Flickable {
      id: prev
      anchors.fill: parent
      anchors.margins: 14
      clip: true
      contentWidth: width
      contentHeight: prevText.implicitHeight
      boundsBehavior: Flickable.StopAtBounds
      TextEdit {
        id: prevText
        width: prev.width
        readOnly: true
        selectByMouse: true
        wrapMode: TextEdit.Wrap
        textFormat: ed.e && ed.e.body.trim() !== "" ? TextEdit.MarkdownText : TextEdit.PlainText
        text: !ed.e || ed.e.body.trim() === "" ? "Nothing written yet" : D.mdLinesOf(ed.e.body)
        color: ed.e && ed.e.body.trim() !== "" ? Zenon.ink : Zenon.accentMuted
        selectionColor: Zenon.alpha(Zenon.cyan, 0.4)
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(15)
        onLinkActivated: (link) => Quickshell.execDetached(["xdg-open", link])
      }
    }
    ElasticScroll { anchors.fill: prev; view: prev }
    Scrollbar { flick: prev; anchors.right: parent.right; anchors.rightMargin: 2; anchors.top: prev.top; anchors.bottom: prev.bottom }
  }

  PopMenu {
    id: fromPop
    anchors.fill: parent
    window: ed.page ? ed.page.win : null
    cardWidth: 260
  }
}

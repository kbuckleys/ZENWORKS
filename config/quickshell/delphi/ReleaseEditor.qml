// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A RELEASE BEING WRITTEN — the Releases page, given over to one release, new
// or one there is (user, 2026-10-11: a sheet was too tight for its notes).
// Across the top its tag, the branch it is made from (a new one only) and
// its title; draft and pre-release where the forge has them; then the notes,
// the rest of the page, and "Write them for me" for GitHub's own or the
// commits since the last tag. Saving and canceling are the page's buttons;
// ctrl return saves.
//
// The notes are MARKDOWN, written as Markdown under a bar made for it
// (delphi/MarkdownBar, writing the syntax through clio/MarkdownTarget), with
// Write and Preview as GitHub's release editor has them (user, 2026-10-25:
// Clio's rich-text editor here was the wrong tool). Preview is NotesView,
// the release page's own reading — code chips, heading lines and all.
// Spelling is checked by Clio's dictionary and its one switch.
//
// The fields write into page.edit as they are typed; reset() puts
// page.edit back into them (opening one, notes written for you).

import QtQuick
import "../morpheus"
import "../morpheus/controls" as Controls
import "../terminus"
import "../clio"
import "../clio/notes.js" as N
import "delphi.js" as D

Item {
  id: ed
  property var page: null
  readonly property var e: ed.page ? ed.page.edit : null
  readonly property bool typing: tagField.focused || titleField.focused || notes.focused
  // "write" or "preview", as GitHub's tabs
  property string tab: "write"
  readonly property var spellMgr: Clio.app
  // the notes' words, a size up from the fields' (user, 2026-10-25: a bit
  // small to write in); the release preview (ReleasesPage) reads it too
  readonly property int notesPx: Zenon.px(17)

  function claim() {
    if (ed.e && ed.e.mode === "new") tagField.claim();
    else { ed.tab = "write"; notes.claim(); }
  }
  // putting a release's values in is not an edit: a body with Windows line
  // ends comes back out of the field with plain ones, and writing that back
  // from inside the change that opened it was a binding loop
  property bool loading: false
  function reset() {
    if (!ed.e) return;
    ed.loading = true;
    tagField.text = ed.e.tag;
    titleField.text = ed.e.name;
    notes.text = ed.e.body;
    ed.loading = false;
  }
  function showTab(v) {
    ed.tab = v;
    if (v === "write") Qt.callLater(() => notes.claim());
  }
  // ── THE NOTES' RIGHT-CLICK MENU ── everything the notes take, in one
  // place (user, 2026-10-25: "a full and useful context menu — zenworks is
  // all about convenience"): a wrong word's guesses (`fix(word)` puts one
  // in), undo, the clipboard, formats and paragraph styles, a link, what to
  // put in, how they are written, and the spelling's switch
  function editMenu(x, y, hit, fix) {
    const t = mdTarget;
    const sm = ed.spellMgr;
    const spell = !hit || !sm ? []
      : hit.sugs.slice(0, 6).map((w) => ({ text: w, icon: "\uF00C", run: () => fix(w) }))
        .concat(hit.sugs.length === 0 ? [{ text: "No guesses", icon: "", enabled: false, run: () => {} }] : [])
        .concat(sm.spellTail(hit.w));
    const undo = [
      { text: "Undo", icon: "\u{F054C}", mark: "ctrl z", enabled: notes.edit.canUndo, run: () => notes.edit.undo() },
      { text: "Redo", icon: "\u{F044E}", mark: "ctrl shift z", enabled: notes.edit.canRedo, run: () => notes.edit.redo() },
      { isSeparator: true }];
    const edits = notes.editItems();
    const kind = (k, label) => ({ text: label || N.KINDS[k].label, icon: N.KINDS[k].glyph, run: () => t.setKind(k) });
    const shape = [
      { isSeparator: true },
      { text: "Format", icon: "\uF032", enabled: !t.inMono, children: [
        { text: "Bold", icon: "\uF032", mark: "ctrl b", run: () => t.mark("b") },
        { text: "Italic", icon: "\uF033", mark: "ctrl i", run: () => t.mark("i") },
        { text: "Strikethrough", icon: "\uF0CC", run: () => t.mark("s") },
        { text: "Code", icon: "\uF121", mark: "ctrl e", run: () => t.code() },
        { isSeparator: true },
        { text: "Clear formatting", icon: "\u{F0265}", run: () => t.plainText() }] },
      { text: "Paragraph", icon: N.KINDS.heading.glyph, children: [
        kind("heading"), kind("subheading"), kind("body"), { isSeparator: true },
        kind("bullet"), kind("number"), kind("check"), { isSeparator: true },
        kind("quote"), kind("mono", "Code")] },
      { text: "Link…", icon: "\uF0C1", mark: "ctrl k", run: () => ed.askLink() },
      { text: "Put in", icon: "\u{F1298}", children: ed.insertItems() },
      { isSeparator: true },
      { text: "Preview", icon: "\uF06E", run: () => ed.showTab("preview") },
      { text: sm && sm.spellOn ? "Stop checking spelling" : "Check spelling", icon: "\u{F04C6}", enabled: !!sm,
        run: () => sm.setSpellOn(!sm.spellOn) }];
    fromPop.open(x, y, spell.concat(undo, edits, shape));
  }
  // what the menu's Put in offers: a divider, today's date, and the line
  // every forge's release ends on — every change since the last tag
  function insertItems() {
    const hub = ed.page ? ed.page.hub : null;
    const site = ed.page ? ed.page.site : null;
    const tag = ed.e ? ed.e.tag.trim() : "";
    const url = hub && ed.e ? D.compareUrl(hub.web, !!site && (site.id === "gitlab" || site.kind === "gitlab"), ed.e.prev, tag) : "";
    const today = Qt.formatDate(new Date(), "MMMM d, yyyy");
    return [
      { text: "Divider", icon: N.KINDS.rule.glyph, run: () => mdTarget.rule() },
      { text: "Today's date", icon: "\uF073", run: () => ed.putWords(today) },
      { text: url ? "Full changelog link" : "Full changelog link — needs an earlier tag", icon: "\u{F08AA}", enabled: url !== "",
        run: () => ed.putChangelog(url) }];
  }
  // words at the caret
  function putWords(w) { mdTarget.insert(w); }
  // "**Full changelog**: <compare url>", a paragraph of its own at the end
  function putChangelog(url) {
    const f = notes.edit;
    const tail = f.text.replace(/\s+$/, "");
    f.cursorPosition = f.length;
    mdTarget.insert((tail === "" ? "" : f.text.endsWith("\n\n") ? "" : f.text.endsWith("\n") ? "\n" : "\n\n")
                    + "**Full changelog**: " + url + "\n");
  }
  // the address asked for, round the words chosen or as its own words
  function askLink() {
    const sel = notes.edit.selectedText;
    const href = "";
    ed.page.win.ask({ title: href ? "Edit link" : "Add a link", glyph: "\uF0C1", ink: Zenon.cyan,
      fields: [{ key: "url", label: "Address", value: href || (/^\S+\.\S+$/.test(sel) ? sel : ""), hint: "https://…" }]
        .concat(sel === "" ? [{ key: "label", label: "Words", value: "", optional: true }] : []),
      verb: href ? "Save" : "Add",
      then: (v) => {
        const u = (v.url || "").trim();
        if (!u) return;
        Qt.callLater(() => mdTarget.link(u, v.label || ""));
      } });
  }
  // a different release opened: its own values in the fields, on Write
  property string _for: ""
  onEChanged: {
    const k = ed.e ? ed.e.mode + ":" + (ed.e.id || "") : "";
    if (k !== ed._for) { ed._for = k; ed.tab = "write"; ed.reset(); if (ed.e) Qt.callLater(ed.claim); }
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
          opacity: enabled ? 1 : Zenon.disabledDim
          onTextChanged: if (ed.e && !ed.loading && text !== ed.e.tag) ed.page.setEdit("tag", text)
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
          onTextChanged: if (ed.e && !ed.loading && text !== ed.e.name) ed.page.setEdit("name", text)
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
      Controls.Check {
        width: 300
        height: 26
        label: "A draft — only you see it, until published"
        lit: !!ed.e && ed.e.draft
        onToggled: ed.page.setEdit("draft", !ed.e.draft)
      }
      Controls.Check {
        width: 200
        height: 26
        label: "A pre-release"
        lit: !!ed.e && ed.e.prerelease
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
        current: ed.tab
        onChose: (v) => ed.showTab(v)
      }
      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10
        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: !!ed.e && ed.e.by !== ""
          text: ed.e && ed.e.by === "github" ? "Written by GitHub, from what was merged" : ed.e && ed.e.by === "commits" ? "Written from the commits since " + (ed.e.prev || "the start") : ""
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

    // ── the toolbar: the Markdown bar, and the spelling's switch; there,
    // and quiet, on Preview, so nothing below it moves ──
    Rectangle {
      width: parent.width
      height: 40
      radius: Zenon.windowRadius
      color: Zenon.wash(0.03)
      border.width: 1
      border.color: Zenon.border
      // in the middle of the bar (user, 2026-10-25), the spelling's switch
      // at its right end
      MarkdownBar {
        id: mdBar
        anchors.centerIn: parent
        target: mdTarget
        host: toolHost
        enabled: ed.tab === "write"
        opacity: enabled ? 1 : Zenon.disabledDim
        onLinkAsked: ed.askLink()
      }
      Rectangle { anchors.right: spellTool.left; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter; width: 1; height: 18; color: Zenon.border }
      // spelling, on or off — Clio's switch, so one answer everywhere (on
      // by default)
      ClioTool {
        id: spellTool
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        pane: toolHost
        glyph: "\u{F04C6}"
        tip: ed.spellMgr && ed.spellMgr.spellOn ? "Spelling is checked — click to stop" : "Check spelling"
        lit: !!ed.spellMgr && ed.spellMgr.spellOn
        litInk: Zenon.cyan
        enabled: !!ed.spellMgr
        onPressed: ed.spellMgr.setSpellOn(!ed.spellMgr.spellOn)
      }
    }
  }

  // the ClioTools' pane (their tips, in this window)
  Item {
    id: toolHost
    readonly property var win: ({ tipsItem: tips })
  }
  WindowTip { id: tips; window: ed.page ? ed.page.win : null }
  MarkdownTarget { id: mdTarget; field: notes.edit }

  // ── the notes: the rest of the page ──
  MessageWell {
    id: notes
    visible: ed.tab === "write"
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: top.bottom
    anchors.bottom: parent.bottom
    anchors.leftMargin: 24
    anchors.rightMargin: 24
    anchors.topMargin: 10
    anchors.bottomMargin: 18
    textSize: ed.notesPx
    ghost: "What is in it — ## headings, - lists, **bold**, `code`, [links](https://…)"
    note: ed.e ? (ed.e.body.length > 0 ? ed.e.body.split("\n").length + " lines" : "") : ""
    spellMgr: ed.spellMgr
    onTextChanged: if (ed.e && !ed.loading && text !== ed.e.body) ed.page.setEdit("body", text)
    // the bar's keys first (ctrl b, i, e, k …), then the window's
    passKeys: (k) => mdBar.key(k) || ed.page.win.key(k)
    onSubmitted: ed.page.save()
    onEscaped: ed.page.cancelEdit()
    onBackTabbed: titleField.claim()
    onMenuAsked: (x, y, hit) => { const p = notes.mapToItem(ed, x, y); ed.editMenu(p.x, p.y, hit, (w) => notes.respell(hit, w)); }
  }
  // Preview: the notes as the release page will show them, in the well's frame
  Rectangle {
    id: previewWell
    visible: ed.tab === "preview"
    anchors.fill: notes
    radius: Zenon.windowRadius
    color: Zenon.wash(0.05)
    border.width: 1
    border.color: Zenon.border
    Flickable {
      id: previewFlick
      anchors.fill: parent
      anchors.margins: 1
      clip: true
      contentWidth: width
      contentHeight: previewText.height + 30
      boundsBehavior: Flickable.StopAtBounds
      NotesView {
        id: previewText
        x: 16
        y: 12
        width: previewFlick.width - 32
        body: ed.e ? ed.e.body : ""
        empty: "Nothing to preview yet"
        textSize: ed.notesPx
      }
    }
    ElasticScroll { anchors.fill: previewFlick; view: previewFlick }
    Scrollbar { flick: previewFlick; anchors.right: previewFlick.right; anchors.top: previewFlick.top; anchors.bottom: previewFlick.bottom }
  }

  PopMenu {
    id: fromPop
    anchors.fill: parent
    window: ed.page ? ed.page.win : null
    cardWidth: 260
  }
}

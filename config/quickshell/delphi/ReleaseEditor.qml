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
// The notes are written in RICH TEXT or as MARKDOWN (user, 2026-10-25),
// under Clio's format bar (clio/FormatBar) either way: rich text is Clio's
// own editor, its blocks read from the Markdown and written back to it as
// they change (notes.js blocksOfMarkdown / markdownOf); Markdown is the plain
// well, the bar writing the syntax (clio/MarkdownTarget). Notes rich text
// cannot hold (pictures, HTML — notes.js markdownLoses) stay in Markdown.
// Spelling is checked in both, by Clio's dictionary and its one switch.
//
// The fields write into page.edit as they are typed; reset() puts
// page.edit back into them (opening one, notes written for you).

import QtQuick
import Quickshell
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
  readonly property bool typing: tagField.focused || titleField.focused || notes.focused || ed.richFocused
  // how the notes are written: "rich" (Clio's editor) or "markdown"
  property string form: "rich"
  // what rich text would drop of the notes, in words ("" — nothing)
  readonly property string loses: ed.e ? N.markdownLoses(ed.e.body) : ""
  readonly property bool richFocused: {
    for (let p = ed.Window.activeFocusItem; p; p = p.parent) if (p === rich) return true;
    return false;
  }
  readonly property var spellMgr: Clio.app
  // the notes' words, a size up from the fields' (user, 2026-10-25: a bit
  // small to write in); the release preview (ReleasesPage) reads it too
  readonly property int notesPx: Zenon.px(17)

  function claim() {
    if (ed.e && ed.e.mode === "new") tagField.claim();
    else if (ed.form === "rich") rich.focusEnd(false);
    else notes.claim();
  }
  function reset() {
    if (!ed.e) return;
    tagField.text = ed.e.tag;
    titleField.text = ed.e.name;
    notes.text = ed.e.body;
    if (ed.form === "rich" && ed.loses !== "") ed.form = "markdown";
    if (ed.form === "rich") ed.loadRich();
  }
  // the notes into Clio's editor, from their Markdown
  function loadRich() {
    const bs = ed.e && ed.e.body.trim() !== "" ? N.blocksOfMarkdown(ed.e.body) : [];
    rich.load(bs.length ? bs : [N.block("body", "")]);
  }
  // what the editor holds, back into the notes as Markdown — a beat after
  // typing, and at once before a save or a switch
  function settle() {
    richSync.stop();
    if (!ed.e || ed.form !== "rich") return;
    const md = N.markdownOf(rich.stored(), "");
    const body = md.trim() === "" ? "" : md;
    if (body !== ed.e.body) ed.page.setEdit("body", body);
  }
  Timer { id: richSync; interval: 250; onTriggered: ed.settle() }
  function writeAs(v) {
    if (v === ed.form) return;
    if (v === "rich" && ed.loses !== "") {
      ed.page.win.say("These notes have " + ed.loses + ", which only Markdown keeps", true);
      return;
    }
    if (v === "markdown") { ed.settle(); notes.text = ed.e ? ed.e.body : ""; }
    ed.form = v;
    if (v === "rich") ed.loadRich();
    Qt.callLater(ed.claim);
  }
  // ── THE NOTES' RIGHT-CLICK MENU ── everything the notes take, in one
  // place (user, 2026-10-25: "a full and useful context menu — zenworks is
  // all about convenience"): a wrong word's guesses (`fix(word)` puts one
  // in), undo, the clipboard, formats and paragraph styles, a link, what to
  // put in, how they are written, and the spelling's switch
  function editMenu(x, y, hit, fix) {
    const inRich = ed.form === "rich";
    const t = toolHost.target;
    const sm = ed.spellMgr;
    const spell = !hit || !sm ? []
      : hit.sugs.slice(0, 6).map((w) => ({ text: w, icon: "\uF00C", run: () => fix(w) }))
        .concat(hit.sugs.length === 0 ? [{ text: "No guesses", icon: "", enabled: false, run: () => {} }] : [])
        .concat(sm.spellTail(hit.w));
    const undo = [
      { text: "Undo", icon: "\u{F054C}", mark: "ctrl z", enabled: inRich ? rich.canUndo : notes.edit.canUndo,
        run: () => { if (inRich) rich.undo(); else notes.edit.undo(); } },
      { text: "Redo", icon: "\u{F044E}", mark: "ctrl shift z", enabled: inRich ? rich.canRedo : notes.edit.canRedo,
        run: () => { if (inRich) rich.redo(); else notes.edit.redo(); } },
      { isSeparator: true }];
    const edits = inRich ? rich.editItems(() => rich.pastePlainNow(() => ed.page.win.say("No words on the clipboard", true)))
                       : notes.editItems();
    const kind = (k, label) => ({ text: label || N.KINDS[k].label, icon: N.KINDS[k].glyph, run: () => t.setKind(k) });
    const shape = [
      { isSeparator: true },
      { text: "Format", icon: "\uF032", enabled: !t.inMono, children: [
        { text: "Bold", icon: "\uF032", mark: "ctrl b", run: () => t.mark("b") },
        { text: "Italic", icon: "\uF033", mark: "ctrl i", run: () => t.mark("i") },
        { text: "Strikethrough", icon: "\uF0CC", mark: "ctrl shift x", run: () => t.mark("s") },
        { isSeparator: true },
        { text: "Clear formatting", icon: "\u{F0265}", run: () => t.plainText() }] },
      { text: "Paragraph", icon: N.KINDS.heading.glyph, children: [
        kind("heading"), kind("subheading"), kind("body"), { isSeparator: true },
        kind("bullet"), kind("number"), kind("check"), { isSeparator: true },
        kind("quote"), kind("mono", "Code")] },
      { text: "Link…", icon: "\uF0C1", run: () => ed.askLink() },
      { text: "Put in", icon: "\u{F1298}", children: ed.insertItems() },
      { isSeparator: true },
      { text: inRich ? "Write in Markdown" : "Write in rich text", icon: inRich ? "\u{F0354}" : "\u{F09A8}",
        enabled: inRich || ed.loses === "", run: () => ed.writeAs(inRich ? "markdown" : "rich") },
      { text: sm && sm.spellOn ? "Stop checking spelling" : "Check spelling", icon: "\u{F04C6}", enabled: !!sm,
        run: () => sm.setSpellOn(!sm.spellOn) }];
    fromPop.open(x, y, spell.concat(undo, edits, shape));
  }
  // what the menu's Put in offers: a divider, today's date, and the line
  // every forge's release ends on — every change since the last tag
  function insertItems() {
    const inRich = ed.form === "rich";
    const hub = ed.page ? ed.page.hub : null;
    const site = ed.page ? ed.page.site : null;
    const tag = ed.e ? ed.e.tag.trim() : "";
    const url = hub && ed.e ? D.compareUrl(hub.web, !!site && (site.id === "gitlab" || site.kind === "gitlab"), ed.e.prev, tag) : "";
    const today = Qt.formatDate(new Date(), "MMMM d, yyyy");
    return [
      { text: "Divider", icon: N.KINDS.rule.glyph, run: () => { if (inRich) rich.insertRule(); else mdTarget.rule(); } },
      { text: "Today's date", icon: "\uF073", run: () => ed.putWords(today) },
      { text: url ? "Full changelog link" : "Full changelog link — needs an earlier tag", icon: "\u{F08AA}", enabled: url !== "",
        run: () => ed.putChangelog(url) }];
  }
  // words at the caret, in either way of writing
  function putWords(w) {
    if (ed.form !== "rich") { mdTarget.insert(w); return; }
    const it = rich.current();
    if (!it || !it.isText) return;
    const te = it.te;
    if (te.selectionStart !== te.selectionEnd) te.remove(te.selectionStart, te.selectionEnd);
    te.insert(te.cursorPosition, N.escape(w));
  }
  // "**Full changelog**: <compare url>", a paragraph of its own at the end
  function putChangelog(url) {
    if (ed.form === "rich") {
      rich.insertBlocks([N.block("body", "<b>Full changelog</b>: <a href=\"" + N.escape(url) + "\">" + N.escape(url) + "</a>")], true);
      return;
    }
    const f = notes.edit;
    const tail = f.text.replace(/\s+$/, "");
    f.cursorPosition = f.length;
    mdTarget.insert((tail === "" ? "" : f.text.endsWith("\n\n") ? "" : f.text.endsWith("\n") ? "\n" : "\n\n")
                    + "**Full changelog**: " + url + "\n");
  }
  // the address asked for, round the words chosen or as its own words
  function askLink() {
    const inRich = ed.form === "rich";
    const sel = inRich ? rich.selectedText() : notes.edit.selectedText;
    const href = inRich ? rich.linkHere() : "";
    ed.page.win.ask({ title: href ? "Edit link" : "Add a link", glyph: "\uF0C1", ink: Zenon.cyan,
      fields: [{ key: "url", label: "Address", value: href || (/^\S+\.\S+$/.test(sel) ? sel : ""), hint: "https://…" }]
        .concat(sel === "" ? [{ key: "label", label: "Words", value: "", optional: true }] : []),
      verb: href ? "Save" : "Add",
      then: (v) => {
        const u = (v.url || "").trim();
        if (!u) return;
        Qt.callLater(() => { if (inRich) rich.link(u, v.label || ""); else mdTarget.link(u, v.label || ""); });
      } });
  }
  // a different release opened: its own values in the fields, written in
  // rich text unless it has what only Markdown keeps
  property string _for: ""
  onEChanged: {
    const k = ed.e ? ed.e.mode + ":" + (ed.e.id || "") : "";
    if (k !== ed._for) { ed._for = k; ed.form = "rich"; ed.reset(); if (ed.e) Qt.callLater(ed.claim); }
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
        options: [["rich", "Rich text"], ["markdown", "Markdown"]]
        current: ed.form
        onChose: (v) => ed.writeAs(v)
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

    // ── the toolbar: Clio's format bar, and the spelling's switch ──
    Rectangle {
      width: parent.width
      height: 40
      radius: Zenon.windowRadius
      color: Zenon.wash(0.03)
      border.width: 1
      border.color: Zenon.border
      Item {
        anchors.fill: parent
        anchors.rightMargin: spellTool.width + 14
        FormatBar {
          host: toolHost
          // (through toolHost: `ed` in here is the bar's own)
          ed: toolHost.target
          // what Markdown has: no alignment, underline, faces or dashes
          lists: ["bullet", "number", "check", "quote"]
          marks: ["b", "i", "s"]
          aligns: false
        }
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
    // why these notes stay in Markdown
    Text {
      width: parent.width
      visible: ed.form === "markdown" && ed.loses !== ""
      wrapMode: Text.Wrap
      text: "These notes have " + ed.loses + ", which rich text would drop — written in Markdown."
      color: Zenon.yellow
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
    }
  }

  // the ClioTools' pane (their tips, in this window), and what the format
  // bar acts on: Clio's editor, or the Markdown in the well
  Item {
    id: toolHost
    readonly property var win: ({ tipsItem: tips })
    readonly property var target: ed.form === "rich" ? rich : mdTarget
  }
  WindowTip { id: tips; window: ed.page ? ed.page.win : null }
  MarkdownTarget { id: mdTarget; field: notes.edit }

  // ── the notes: the rest of the page ──
  MessageWell {
    id: notes
    visible: ed.form === "markdown"
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: top.bottom
    anchors.bottom: parent.bottom
    anchors.leftMargin: 24
    anchors.rightMargin: 24
    anchors.topMargin: 10
    anchors.bottomMargin: 18
    textSize: ed.notesPx
    ghost: "What is in it — markdown: ## headings, - lists, **bold**, `code`, [links](https://…)"
    note: ed.e ? (ed.e.body.length > 0 ? ed.e.body.split("\n").length + " lines" : "") : ""
    spellMgr: ed.spellMgr
    spelling: ed.form === "markdown"
    onTextChanged: if (ed.e && ed.form === "markdown" && text !== ed.e.body) ed.page.setEdit("body", text)
    passKeys: (k) => ed.page.win.key(k)
    onSubmitted: ed.page.save()
    onEscaped: ed.page.cancelEdit()
    onBackTabbed: titleField.claim()
    onMenuAsked: (x, y, hit) => { const p = notes.mapToItem(ed, x, y); ed.editMenu(p.x, p.y, hit, (w) => notes.respell(hit, w)); }
  }
  // rich text: Clio's editor, in the well's frame
  Rectangle {
    id: richWell
    visible: ed.form === "rich"
    anchors.fill: notes
    radius: Zenon.windowRadius
    color: Zenon.wash(0.05)
    border.width: 1
    border.color: Zenon.border
    BlockEditor {
      id: rich
      anchors.fill: parent
      anchors.margins: 1
      clip: true
      mgr: ed.spellMgr
      textSize: ed.notesPx
      sidePad: 14
      topPad: 10
      bottomPad: 40
      maxColumn: 100000
      submits: true
      // its own paste: words, as the blocks take them (no pictures here)
      ownsPaste: true
      onEdited: richSync.restart()
      onSubmitted: { ed.settle(); ed.page.save(); }
      onEscaped: { ed.settle(); ed.page.cancelEdit(); }
      onLinkClicked: (href) => Quickshell.execDetached(["xdg-open", href])
      onMenuAsked: (x, y, info) => {
        const p = rich.mapToItem(ed, x, y);
        const sp = info ? info.spell : null;
        ed.editMenu(p.x, p.y, sp, (w) => rich.respellWord(info.key, sp, w));
      }
    }
    Text {
      x: 14
      y: 12
      visible: !!ed.e && ed.e.body === "" && !ed.richFocused
      text: "What is in it — headings, lists, bold, links: as the forge will show them"
      color: Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: ed.notesPx
    }
    HeldRing { anchors.fill: parent; radius: parent.radius; z: 10; on: ed.richFocused }
  }

  PopMenu {
    id: fromPop
    anchors.fill: parent
    window: ed.page ? ed.page.win : null
    cardWidth: 260
  }
}

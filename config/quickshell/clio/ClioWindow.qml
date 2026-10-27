// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// CLIO'S WINDOW — three columns, as Apple's Notes lays its own out:
//
//   the sidebar   All notes, Stickies (the desktop's), the containers and
//                 smart containers, the Trash, the tags; the journals
//   the list      a search, then the notes under their date headings —
//                 pinned first — as rows or a gallery; in a journal, the
//                 timeline of entries with its insights and calendar
//   the note      the editor (BlockEditor) under its toolbar: formats,
//                 checklists, tables, pictures, sketches, links, the lock
//
// Every question is the suite's card (delphi/CardSheet), every right click
// a PopMenu, every hover a WindowTip; the sheets (mood, sketch, settings,
// pictures, moments) hang from the head as calypso's do.
//
//   ctrl+n  a new note        ctrl+j  a new journal entry     ctrl+shift+n  a container
//   ctrl+f  find in the note (search, from the list)          ctrl+shift+f  search
//   ctrl+p  pin    ctrl+d  duplicate    ctrl+e  export    ctrl+,  settings
//   ctrl+1 ctrl+2  list, gallery   ctrl+= ctrl+- ctrl+0  text size
//   ctrl+alt+l  lock now          delete  to the Trash (from the list)
//   esc     unwinds: the find, the search, then closes

import QtQuick
import Quickshell
import Quickshell.Io
import "../morpheus"
import "../morpheus/controls" as Ctl
import "../terminus"
import "../delphi"
import "notes.js" as N
import "clio.js" as Scribe
import "../terminus/terminus.js" as Terminus

FloatingWindow {
  id: win
  title: "clio"
  color: Zenon.alpha(Zenon.layerBg, 0)
  implicitWidth: 1320
  implicitHeight: 840
  minimumSize: Qt.size(900, 560)

  property var mgr: null

  // CLOSED, IT GOES (plato's rule): the notebook written, the lock shut
  onVisibleChanged: {
    if (!win.mgr) return;
    if (win.visible) { win.mgr.hold(); return; }
    win.commit();
    win.mgr.retire(win);
    Qt.callLater(() => win.destroy());
  }
  onClosed: win.visible = false
  Component.onCompleted: if (win.mgr) win.mgr.hold()

  readonly property color hiFill: Zenon.menuHi
  readonly property int headH: 50
  readonly property int footH: Zenon.hintBarH   // morpheus/HintBar's strip
  readonly property var tipsItem: tips
  readonly property Item stageItem: stage

  // ── WHERE YOU ARE ──────────────────────────────────────────────────────
  readonly property var scope: win.mgr ? win.mgr.scope : ({ shelf: "all" })
  readonly property bool inJournal: win.scope.shelf === "journal"
  readonly property bool onDesktop: win.scope.shelf === "desktop"
  readonly property bool inTrash: win.scope.shelf === "trash"
  function setScope(s) {
    win.commit();
    win.mgr.set("scope", s);
    win.query = "";
    win.day = "";
    win.wantTop = true;
    Qt.callLater(win.reseat);
  }
  property string query: ""
  // the journal: a day chosen on the calendar ("" none)
  property string day: ""
  readonly property string jfilter: win.mgr ? win.mgr.journalFilter : ""

  // what the list shows
  readonly property var shown: {
    if (!win.mgr) return [];
    void win.mgr.notes;
    if (win.onDesktop) {
      const t = N.terms(win.query);
      return win.mgr.stickies.filter((s) => N.score(s, t) > 0);
    }
    if (win.inJournal) return N.entries(win.mgr.notes, win.scope.id || "", { query: win.query, filter: win.jfilter, day: win.day });
    return N.shelve(win.mgr.notes, win.scope, win.query, win.mgr.sort, win.mgr.folders);
  }
  // the rows: each note, and the heading over it if one goes there
  readonly property var rows: {
    const out = [];
    let last = null;
    const now = Date.now();
    const searching = N.terms(win.query).words.length > 0;
    for (const n of win.shown) {
      let sec = "";
      if (win.inJournal) sec = N.entrySection(n, now);
      else if (win.onDesktop || win.inTrash || searching) sec = "";
      else if (n.pinned) sec = "Pinned";
      else if (win.mgr.groupByDate) sec = N.sectionOf(n, win.mgr.sort, now);
      out.push({ n: n, head: sec !== last && sec !== "" ? sec : "" });
      last = sec;
    }
    return out;
  }

  // ── WHICH NOTE ─────────────────────────────────────────────────────────
  property string selId: ""
  readonly property var current: {
    if (!win.mgr || win.selId === "") return null;
    void win.mgr.notes;
    void win.mgr.stickies;
    return win.selId.startsWith("s:") ? win.mgr.stickyOf(win.selId) : win.mgr.noteOf(win.selId);
  }
  readonly property int selIndex: win.shown.findIndex((n) => n.id === win.selId)
  property bool wantTop: false
  property string wantId: ""
  onShownChanged: Qt.callLater(win.reseat)
  // the cursor stays on its note across a new list; a new scope or search
  // lands on the top; a note asked for by id (just made) is chosen once
  // the list has it
  function reseat() {
    if (win.wantId !== "") {
      if (win.shown.some((n) => n.id === win.wantId)) { win.choose(win.wantId); win.wantId = ""; }
      return;
    }
    if (win.wantTop) {
      win.wantTop = false;
      win.choose(win.shown.length > 0 ? win.shown[0].id : "");
      return;
    }
    if (win.selId !== "" && win.selIndex >= 0) return;
    // its note went (deleted, moved out of view): the one after it
    const at = Math.max(0, Math.min(win.lastIndex, win.shown.length - 1));
    win.choose(win.shown.length > 0 ? win.shown[at].id : "");
  }
  property int lastIndex: 0
  onSelIndexChanged: if (win.selIndex >= 0) win.lastIndex = win.selIndex
  function choose(id) {
    if (id === win.selId) return;
    win.commit();
    win.selId = id;
    pane.show(win.current);
    win.mgr.markSeen(id);
    // opened from a search: its first word lit where it is, as Apple's
    // search does (the title does not count — it is already in sight)
    const words = N.terms(win.query).words;
    if (words.length > 0 && id !== "") { flashWait.text = words[0]; flashWait.restart(); }
  }
  function move(d) {
    if (win.shown.length === 0) return;
    const i = Math.max(0, Math.min(win.shown.length - 1, (win.selIndex < 0 ? 0 : win.selIndex) + d));
    win.choose(win.shown[i].id);
    (win.inJournal ? journalList : list).seat(i);
  }

  // ── WRITING IT DOWN ────────────────────────────────────────────────────
  // the editor's blocks into the notebook, now (a switch, a close)
  function commit() { pane.commit(); }

  // ── MAKING ─────────────────────────────────────────────────────────────
  function showUp() {
    if (win.selId === "" || !win.current) win.wantTop = true;
    Qt.callLater(win.reseat);
    // opened to the list, the note shown but not being written in — a
    // click or Return goes into it (user, 2026-10-17)
    Qt.callLater(win.toList);
  }
  function newNote(blocks) {
    if (!win.mgr) return;
    win.commit();
    if (win.onDesktop) { win.pick(win.mgr.newSticky(), "start"); return; }
    let folder = win.scope.shelf === "folder" ? win.scope.id : "";
    if (win.inJournal || win.inTrash || win.scope.shelf === "smart" || win.scope.shelf === "tag") {
      if (win.inJournal || win.inTrash) win.mgr.set("scope", { shelf: "all" });
    }
    const id = win.mgr.newNote(folder, blocks ? blocks : win.scope.shelf === "tag"
      ? [N.block(win.mgr.startWith, ""), N.block("body", "#" + N.escape(win.scope.id) + "&nbsp;")] : null);
    win.query = "";
    win.pick(id, "start");
  }
  function newEntry(date, prompt, blocks) {
    if (!win.mgr) return;
    win.commit();
    const j = win.inJournal && win.scope.id ? win.scope.id : (win.mgr.journals[0] || {}).id;
    if (!win.inJournal) win.mgr.set("scope", { shelf: "journal", id: j });
    win.query = "";
    win.day = "";
    win.mgr.set("journalFilter", "");
    const id = win.mgr.newEntry(j, date, prompt, blocks);
    win.pick(id, prompt ? "end" : "start");
    return id;
  }
  // ── TODAY ──
  // today's entry in the journal (the one shown, else the first): opened
  // if it is written, begun if not — from the daily template when one is set
  function today() {
    if (!win.mgr) return;
    win.commit();
    const j = win.inJournal && win.scope.id ? win.scope.id : (win.mgr.journals[0] || {}).id;
    const k = N.dayKey(Date.now());
    const e = win.mgr.notes.filter((n) => n.kind === "entry" && !n.deleted && n.journal === j && N.dayKey(n.date) === k)
      .sort((a, b) => a.date - b.date)[0];
    if (e) { win.query = ""; win.day = ""; win.openNote(e.id); pane.focusEditor(false); return; }
    win.newEntry(0, "", win.mgr.meta.daily ? win.mgr.templateBlocks(win.mgr.meta.daily) : null);
  }

  // ── TEMPLATES ──
  // a new note (or entry) from one; the compose button's right click
  function fromTemplate(t) {
    const bs = win.mgr.templateBlocks(t.id);
    if (!bs) return;
    if (win.inJournal) win.newEntry(0, "", bs); else win.newNote(bs);
  }
  function templateMenu(x, y) {
    const ts = win.mgr.templates;
    const items = ts.map((t) => ({ text: t.name, icon: "\u{F0DC9}", run: () => win.fromTemplate(t) }));
    if (ts.length === 0) items.push({ text: "No templates yet — save or import one", icon: "", enabled: false });
    items.push({ isSeparator: true },
               { text: "Save this note as a template…", icon: "\u{F0193}", enabled: !!win.current && !win.current.sealed && win.current.kind !== "sticky",
                 run: () => win.saveTemplate(win.current) },
               { text: "Import a template…", icon: "", enabled: !!win.mgr.fileManager, run: () => win.importTemplate() });
    if (ts.length > 0) items.push({ text: "Delete a template…", icon: "", danger: true,
      run: () => menu.open(x, y, ts.map((t) => ({ text: t.name, icon: "", danger: true, run: () => win.mgr.deleteTemplate(t.id) }))) });
    menu.open(x, y, items);
  }
  // a Markdown, text or HTML file chosen, named, kept
  function importTemplate() {
    if (!win.mgr.fileManager) return;
    win.mgr.fileManager.choose(false, Quickshell.env("HOME") + "/Documents", (paths) => {
      if (!paths || !paths.length) return;
      const path = paths[0];
      const stem = path.replace(/^.*\//, "").replace(/\.[^.]*$/, "");
      cards.ask({ title: "Import a template", glyph: "\u{F0DC9}", ink: Zenon.cyan,
        detail: "Its words, lists and tables, to start new notes and entries from. {date}, {weekday}, {time}, {day}, {month} and {year} are filled in when it is used.",
        fields: [{ key: "name", label: "Name", value: stem || "Template" }], verb: "Import",
        then: (v) => {
          const t = win.mgr.importTemplate(path, v.name.trim());
          win.say(t ? "Imported as a template" : "Nothing in it to make a template from", !t);
        } });
    });
  }
  function saveTemplate(n) {
    if (!n) return;
    win.commit();
    const bs = win.mgr.blocksOf(n);
    if (!bs) return;
    cards.ask({ title: "Save as a template", glyph: "\u{F0DC9}", ink: Zenon.cyan,
      detail: "Its words, lists and tables, to start new notes and entries from. {date}, {weekday}, {time}, {day}, {month} and {year} are filled in when it is used.",
      fields: [{ key: "name", label: "Name", value: N.titleOf(n, "Template") }], verb: "Save",
      then: (v) => { win.mgr.addTemplate(v.name.trim(), bs); win.say("Saved as a template"); } });
  }

  // Moments: an entry about a day, its pictures in it
  function entryWithPictures(ms, paths) {
    const id = win.newEntry(ms);
    const blocks = [N.block("title", ""), N.block("body", "")];
    let left = paths.length;
    for (const p of paths) win.mgr.attach(id, p, (b) => {
      if (b) blocks.splice(blocks.length - 1, 0, N.block(b.k, "", { src: b.src, name: b.name, size: b.size }));
      if (--left > 0) return;
      win.mgr.setBlocks(id, blocks);
      pane.show(win.mgr.noteOf(id));
      Qt.callLater(() => pane.focusEditor(true));
    });
  }
  // a note just made, chosen as soon as the list has it, the caret in it
  function pick(id, at) {
    win.wantId = id;
    win.reseat();
    Qt.callLater(() => { win.reseat(); pane.focusEditor(at === "start"); });
  }
  function openSticky(id) {
    win.setScope({ shelf: "desktop" });
    win.pick(id, "end");
  }
  // a note opened at words in it (a highlight): lit for a moment
  function openAt(id, text) {
    win.openNote(id);
    flashWait.text = text;
    flashWait.restart();
  }
  Timer { id: flashWait; property string text: ""; interval: 180; onTriggered: pane.editor.flashText(flashWait.text) }
  function openNote(id) {
    const n = win.mgr.noteOf(id);
    if (!n) { win.say("That note is gone", true); return; }
    if (n.kind === "entry") win.setScope({ shelf: "journal", id: n.journal });
    else if (n.deleted) win.setScope({ shelf: "trash" });
    else if (!win.shown.some((x) => x.id === id)) win.setScope({ shelf: "all" });
    win.pick(id, "end");
  }

  // ── VERBS ON A NOTE ────────────────────────────────────────────────────
  function togglePin(n) {
    if (!n || n.kind !== "note") return;
    win.mgr.setField(n.id, "pinned", !n.pinned, false);
    win.say(n.pinned ? "Unpinned" : "Pinned");
  }
  function trashNote(n) {
    if (!n) return;
    if (n.kind === "sticky") {
      Clio.discard(n.sticky);
      win.say("Moved to the Trash");
      return;
    }
    if (n.deleted) { win.destroyNote(n); return; }
    win.commit();
    win.mgr.trash(n.id);
    win.say("Moved to the Trash");
  }
  function destroyNote(n) {
    cards.confirm({ question: "Delete “" + N.titleOf(n, "this entry") + "” forever?", glyph: "", ink: Zenon.red,
      detail: "It cannot be brought back, and its pictures and files go with it.", verb: "Delete forever",
      then: () => win.mgr.forget(n.id) });
  }
  function restoreNote(n) {
    if (!n) return;
    // its container may have gone with it: then into Notes
    if (n.kind === "note" && n.folder && !win.mgr.folders.some((f) => f.id === n.folder)) win.mgr.setField(n.id, "folder", "", false);
    win.mgr.restore(n.id);
    win.say("Restored");
  }
  function duplicateNote(n) {
    if (!n || n.kind === "sticky") return;
    win.commit();
    const id = win.mgr.duplicate(n.id);
    if (id) { win.pick(id, "end"); win.say("Duplicated"); }
    else win.say("Unlock it to duplicate it", true);
  }
  function moveNote(n, folder) {
    if (!n) return;
    win.commit();
    if (n.kind === "sticky") { const id = win.mgr.fromDesktop(n.id, folder); win.say("Taken off the desktop"); if (id) win.openNote(id); return; }
    win.mgr.setField(n.id, "folder", folder, false);
    if (n.deleted) win.mgr.restore(n.id);
    win.say("Moved to " + win.folderName(folder));
  }
  function toDesktop(n) {
    if (!n || n.kind !== "note") return;
    win.commit();
    if (!win.mgr.blocksOf(n)) { win.say("Unlock it first", true); return; }
    win.mgr.toDesktop(n.id);
    win.say("Put on the desktop — it is a sticky now");
  }
  // a name of its own, kept over the first line; emptied, the first line
  // names it again
  function renameNote(n) {
    if (!n || n.kind === "sticky") return;
    win.commit();
    cards.ask({ title: n.kind === "entry" ? "Name this entry" : "Rename note", glyph: "\u{F0455}", ink: Zenon.cyan,
      detail: "Shown in the list in place of its first line. Leave it empty to go back to the first line.",
      fields: [{ key: "name", label: "Name", value: n.name || N.titleOf(n, ""), optional: true }], verb: "Rename",
      then: (v) => { win.mgr.setField(n.id, "name", v.name.trim(), false); win.say(v.name.trim() ? "Renamed" : "Named by its first line again"); } });
  }
  function folderName(id) {
    if (!id) return "Notes";
    const f = win.mgr.folders.find((x) => x.id === id);
    return f ? f.name : "Notes";
  }
  // where a note can go: every container, nested, for a menu
  function moveMenu(n, x, y) {
    const items = [{ text: "Notes", icon: "\u{F11D7}", enabled: n.kind === "sticky" || n.folder !== "", run: () => win.moveNote(n, "") }];
    for (const f of N.folderRows(win.mgr.folders, win.mgr.notes, {}))
      items.push({ text: " ".repeat(f.depth) + f.name, icon: "", enabled: n.kind === "sticky" || n.folder !== f.id, run: () => win.moveNote(n, f.id) });
    items.push({ isSeparator: true }, { text: "New container…", icon: "\u{F0257}", run: () => win.askFolder("", (id) => win.moveNote(n, id)) });
    menu.open(x, y, items);
  }
  function infoOf(n) {
    const d = n.d || N.derive(n);
    const lines = [];
    if (n.kind === "entry") lines.push("Dated " + N.dateTime(n.date));
    if (n.created) lines.push("Created " + N.dateTime(n.created));
    if (n.modified) lines.push("Edited " + N.dateTime(n.modified));
    lines.push(d.words + (d.words === 1 ? " word, " : " words, ") + d.chars + " characters");
    if (d.checks) lines.push(d.done + " of " + d.checks + " ticked");
    if (d.images.length || d.files) lines.push(d.images.length + " pictures, " + d.files + " files");
    if (d.tags.length) lines.push("Tags: " + d.tags.map((t) => "#" + t).join(" "));
    const back = win.mgr.notes.filter((o) => o.d && o.d.links.indexOf(n.id) >= 0 && !o.deleted);
    if (back.length) lines.push("Linked from: " + back.map((o) => N.titleOf(o)).join(", "));
    cards.card_({ question: N.titleOf(n, "Entry"), glyph: "\u{F064E}", ink: Zenon.cyan, detail: lines.join("\n"),
                  choices: [{ label: "Close", ink: Zenon.accentMuted }] });
  }
  function exportNote(n, format) {
    if (!n) return;
    win.commit();
    if (format === "pdf") {
      const go = (dir) => win.makePdf(n, dir, (ok, said) => win.say(ok ? "Exported to " + said.replace(Quickshell.env("HOME"), "~") : "Not exported: " + said, !ok));
      if (win.mgr.fileManager) win.mgr.fileManager.choose(true, Quickshell.env("HOME") + "/Documents", (paths) => { if (paths && paths.length) go(paths[0]); });
      else go(Quickshell.env("HOME") + "/Documents");
      return;
    }
    const ask = (dir) => win.mgr.exportNote(n, format, dir, (ok, said) => win.say(ok ? "Exported to " + said.replace(Quickshell.env("HOME"), "~") : "Not exported: " + said, !ok));
    if (win.mgr.fileManager) win.mgr.fileManager.choose(true, Quickshell.env("HOME") + "/Documents", (paths) => { if (paths && paths.length) ask(paths[0]); });
    else ask(Quickshell.env("HOME") + "/Documents");
  }
  // ── ON PAPER ──
  // a note as a PDF in `dir` (Paper lays it out, the backend binds it)
  function makePdf(n, dir, done) {
    const bs = win.mgr.blocksOf(n);
    if (!bs) { done(false, "Unlock it first"); return; }
    if (paper.busy) { done(false, "Still making the last one"); return; }
    paper.face = win.mgr.faceFor(n.kind === "entry");
    const html = N.htmlOf(bs, "file://" + win.mgr.base, { flat: true, imgWidth: paper.pageW - 2 * paper.margin });
    win.say("Making the PDF…");
    paper.make(html, dir, (pages) => {
      if (!pages || !pages.length) { done(false, "Nothing to put on paper"); return; }
      win.mgr.call("pdf", { pages: pages, out: dir + "/" + N.fileName(N.titleOf(n), "pdf"), dpi: paper.dpi },
                   (ok, r, err) => done(ok, ok ? r.path : (err ? err.error : "")));
    });
  }
  // printed: on paper as a PDF, handed to the printing system (lp)
  property bool canPrint: false
  Process {
    running: true
    command: ["sh", "-c", "command -v lp"]
    onExited: (code) => win.canPrint = code === 0
  }
  function printNote(n) {
    if (!n) return;
    win.commit();
    win.makePdf(n, Quickshell.env("XDG_RUNTIME_DIR") || "/tmp", (ok, said) => {
      if (!ok) { win.say("Not printed: " + said, true); return; }
      win.mgr.call("print", { path: said }, (ok2, r, err) => win.say(ok2 ? "Sent to the printer" : "Not printed: " + (err ? err.error : ""), !ok2));
    });
  }
  Paper { id: paper; parent: stage }

  function copyNote(n) {
    if (!n) return;
    pane.copyAll();
    win.say("Copied the note");
  }

  // ── FOLDERS, JOURNALS ──────────────────────────────────────────────────
  function askFolder(parent, then) {
    cards.ask({ title: parent ? "New container in " + win.folderName(parent) : "New container", glyph: "\u{F0257}", ink: Zenon.cyan,
      fields: [{ key: "name", label: "Name", value: N.freeName("New Container", win.mgr.folders.map((f) => f.name)) }], verb: "Make it",
      then: (v) => {
        const id = win.mgr.addFolder(v.name.trim() || "New Container", parent || "");
        if (then) then(id); else win.setScope({ shelf: "folder", id: id });
      } });
  }
  // a smart container: words and tokens typed, and two rules picked — when it
  // was edited, and what it holds (notes.js passes); the rules are tokens in
  // its query, read back out of it when it is edited
  readonly property var smartWhen: [["", "Any time"], ["edited:today", "Edited today"], ["edited:week", "Edited this week"],
    ["edited:month", "Edited this month"], ["edited:year", "Edited this year"], ["created:week", "Made this week"], ["created:month", "Made this month"]]
  readonly property var smartHolds: [["", "Anything"], ["has:checklist", "A checklist"], ["is:todo", "Boxes still to tick"],
    ["has:attachment", "Pictures or files"], ["has:picture", "Pictures"], ["has:table", "A table"], ["has:sketch", "A sketch"],
    ["has:link", "A link"], ["has:highlight", "Highlighted words"], ["is:locked", "A lock"]]
  function askSmart(f) {
    const q = f ? String(f.query || "").split(/\s+/) : [];
    const pick = (opts) => { const hit = opts.find((o) => o[0] !== "" && q.indexOf(o[0]) >= 0); return hit ? hit[0] : ""; };
    const when0 = pick(win.smartWhen), holds0 = pick(win.smartHolds);
    const rest = q.filter((w) => w !== "" && w !== when0 && w !== holds0).join(" ");
    cards.ask({ title: f ? "Edit " + f.name : "New smart container", glyph: "\u{F0968}", ink: Zenon.magenta,
      detail: "Every note that matches gathers here. Words and #tags are typed; is:pinned, is:todo, has:link and the like work too.",
      fields: [{ key: "name", label: "Name", value: f ? f.name : "Smart Container" },
               { key: "query", label: "Matching", value: rest, hint: "#work, or words", optional: true },
               { key: "when", label: "When", options: win.smartWhen, value: when0, optional: true },
               { key: "holds", label: "Holding", options: win.smartHolds, value: holds0, optional: true }],
      verb: f ? "Save" : "Make it",
      then: (v) => {
        const query = [v.query.trim(), v.when, v.holds].filter((x) => x !== "").join(" ");
        if (query === "") { win.say("A smart container needs something to match", true); return; }
        if (f) { win.mgr.renameFolder(f.id, v.name.trim() || f.name); win.mgr.setFolderQuery(f.id, query); }
        else win.setScope({ shelf: "smart", id: win.mgr.addFolder(v.name.trim() || "Smart Container", "", query) });
      } });
  }
  function renameFolder(f) {
    cards.ask({ title: "Rename " + f.name, glyph: "", ink: Zenon.cyan, fields: [{ key: "name", label: "Name", value: f.name }], verb: "Rename",
      then: (v) => { if (v.name.trim()) win.mgr.renameFolder(f.id, v.name.trim()); } });
  }
  function deleteFolder(f) {
    const n = win.mgr.notes.filter((x) => x.kind === "note" && !x.deleted && N.subfolders(win.mgr.folders, f.id).indexOf(x.folder) >= 0).length;
    cards.confirm({ question: "Delete " + f.name + "?", glyph: "", ink: Zenon.red,
      detail: f.query ? "Only the smart container goes; its notes stay where they are."
        : n === 0 ? "It is empty." : "Its " + n + (n === 1 ? " note goes" : " notes go") + " to the Trash, with its containers.",
      verb: "Delete", then: () => { win.mgr.deleteFolder(f.id); if (win.scope.id === f.id) win.setScope({ shelf: "all" }); } });
  }
  function askJournal(j) {
    cards.ask({ title: j ? "Rename " + j.name : "New journal", glyph: "\u{F0B64}", ink: Zenon.cyan,
      fields: [{ key: "name", label: "Name", value: j ? j.name : N.freeName("New Journal", win.mgr.journals.map((x) => x.name)) },
               { key: "hue", label: "Color", options: [["cyan", "Cyan"], ["magenta", "Magenta"], ["yellow", "Orange"], ["green", "Green"], ["blue", "Blue"], ["pink", "Pink"], ["sand", "Sand"]], value: j ? j.hue : "cyan" }],
      verb: j ? "Save" : "Make it",
      then: (v) => {
        if (j) win.mgr.setJournal(j.id, { name: v.name.trim() || j.name, hue: v.hue });
        else win.setScope({ shelf: "journal", id: win.mgr.addJournal(v.name.trim(), v.hue) });
      } });
  }
  function deleteJournal(j) {
    if (win.mgr.journals.length <= 1) { win.say("The last journal stays", true); return; }
    const n = win.mgr.notes.filter((x) => x.kind === "entry" && x.journal === j.id && !x.deleted).length;
    cards.confirm({ question: "Delete " + j.name + "?", glyph: "", ink: Zenon.red,
      detail: n === 0 ? "It has no entries." : "Its " + n + (n === 1 ? " entry goes" : " entries go") + " to the Trash.",
      verb: "Delete", then: () => { win.mgr.deleteJournal(j.id); win.setScope({ shelf: "journal", id: win.mgr.journals[0].id }); } });
  }
  function journalLocked(id) {
    const j = win.mgr ? win.mgr.journals.find((x) => x.id === id) : null;
    return !!j && j.locked && !win.mgr.unlocked;
  }

  // ── THE LOCK ───────────────────────────────────────────────────────────
  // Unlock asked on a card; with no password yet, one is made first (and
  // its hint), as Apple asks the first time a note is locked.
  function withPassword(then) {
    if (win.mgr.unlocked) { then(); return; }
    if (!win.mgr.hasPassword) { win.makePassword(then); return; }
    cards.ask({ title: "Enter the Clio password", glyph: "", ink: Zenon.yellow,
      detail: win.mgr.hint ? "Hint: " + win.mgr.hint : "",
      secret: { key: "pw", prompt: "input the clio password", purpose: "unlocks locked notes and journals" },
      verb: "Unlock", hold: true, busyText: "Unlocking…",
      then: (v, finish) => win.mgr.unlock(v.pw, (ok, err) => {
        if (!ok) { finish(err && err.kind === "auth" ? "not the clio password" : (err ? err.error : "failed")); return; }
        finish(true);
        then();
      }) });
  }
  function makePassword(then, old) {
    cards.ask({ title: old !== undefined ? "A new Clio password" : "Set a Clio password", glyph: "", ink: Zenon.yellow,
      detail: "One password locks every locked note and journal. It cannot be recovered: forgotten, what it locks stays locked.",
      secret: { key: "pw", prompt: "input a new password", purpose: "locks notes and journals" },
      verb: "Next",
      then: (a) => cards.ask({ title: "Once more", glyph: "", ink: Zenon.yellow,
        secret: { key: "pw", prompt: "input it again", purpose: "to be sure of it" },
        verb: "Next",
        then: (b) => {
          if (a.pw !== b.pw) { win.say("The two did not match — try again", true); return; }
          cards.ask({ title: "A hint", glyph: "\u{F0335}", ink: Zenon.yellow, detail: "Said when the password is asked for. Leave it empty for none.",
            fields: [{ key: "hint", label: "Hint", value: "", optional: true }], verb: "Set password", hold: true, busyText: "Setting…",
            then: (h, finish) => win.mgr.setPassword(a.pw, h.hint, old, (ok, err) => {
              if (!ok) { finish(err ? err.error : "failed"); return; }
              finish(true);
              win.say(old !== undefined ? "Password changed" : "Password set");
              if (then) then();
            }) });
        } }) });
  }
  function changePassword() {
    if (!win.mgr.hasPassword) { win.makePassword(null); return; }
    cards.ask({ title: "Change the Clio password", glyph: "", ink: Zenon.yellow,
      secret: { key: "pw", prompt: "input the current password", purpose: "every locked note is locked again under the new one" },
      verb: "Next", then: (v) => win.makePassword(null, v.pw) });
  }
  function lockNote(n) {
    if (!n || n.kind === "sticky") return;
    win.withPassword(() => {
      win.commit();
      win.mgr.lockNote(n.id);
      win.say("Locked — closed when you Lock now, or close the window");
    });
  }
  function removeLock(n) {
    win.withPassword(() => win.mgr.unseal(n.id, (ok) => { if (ok) { win.mgr.unlockNote(n.id); win.say("The lock is off"); } }));
  }
  function lockNow() {
    win.commit();
    win.mgr.lockNow();
    pane.show(win.current);
    win.say("Locked");
  }

  // ── PICTURES, FILES, SKETCHES ──────────────────────────────────────────
  function attachFile() {
    const n = win.current;
    if (!n || n.kind === "sticky" || !win.mgr.fileManager) return;
    win.mgr.fileManager.choose(false, Quickshell.env("HOME"), (paths) => {
      if (!paths || !paths.length) return;
      for (const p of paths) win.mgr.attach(n.id, p, (b) => { if (b) pane.editor.attachBlock(b); });
    }, "", true);
  }
  // files dropped on the note, in at gap `at`, all at once and in the
  // order dropped, once every copy is made
  function dropFiles(paths, at) {
    const n = win.current;
    if (!n) return;
    if (n.kind === "sticky") {
      // a sticky keeps no files: their paths, as words
      pane.editor.insertAt(at, paths.map((p) => N.block("body", N.escape(p))));
      return;
    }
    const got = new Array(paths.length);
    let left = paths.length;
    paths.forEach((p, x) => win.mgr.attach(n.id, p, (b) => {
      got[x] = b ? N.block(b.k, "", { src: b.src, name: b.name, size: b.size }) : null;
      if (--left > 0) return;
      const list = got.filter((g) => !!g);
      if (win.current && win.current.id === n.id) pane.editor.insertAt(at, list);
    }));
  }
  // a picture of a document: put in, read, and its words set under it
  function scanDocument() {
    const n = win.current;
    if (!n || n.kind === "sticky" || !win.mgr.fileManager) return;
    win.mgr.fileManager.choose(false, Quickshell.env("HOME") + "/Pictures", (paths) => {
      if (!paths || !paths.length) return;
      win.mgr.attach(n.id, paths[0], (b) => {
        if (!b) return;
        if (b.k !== "image") { pane.editor.attachBlock(b); win.say("That is not a picture", true); return; }
        const at = pane.editor.caretGap();
        pane.editor.insertAt(at, [N.block("image", "", { src: b.src, name: b.name, size: b.size })]);
        win.say("Reading the document…");
        win.mgr.ocr(b.src, (t) => {
          if (t === "") { win.say("No words found in it", true); return; }
          pane.editor.setOcr(b.src, t);
          const i = pane.editor.blocks.findIndex((x) => x.src === b.src);
          pane.editor.insertAt(i + 1, t.split("\n").map((l) => N.block("body", N.escape(l))));
        });
      });
    }, "", false);
  }
  function openFile(b) {
    if (!b || !b.src) return;
    const p = win.mgr.base + "/" + b.src;
    Quickshell.execDetached(["sh", "-c", Terminus.openOrAskCommand(p)]);
  }
  // the sketch pad, for a new sketch (key "") or one already there
  property string sketchKey: ""
  property bool sketching: false
  function sketch(b) {
    const n = win.current;
    if (!n || n.kind === "sticky") return;
    win.sketchKey = b ? b._key || "" : "";
    sketchPad.begin(b ? b.strokes || [] : [], b && b._key ? b.src : "");
    win.sketching = true;
  }
  function sketchDone(strokes, ok) {
    win.sketching = false;
    if (!ok) { pane.focusEditor(false); return; }
    const n = win.current;
    if (!n) return;
    const key = win.sketchKey;
    const b = key ? pane.editor.blockOf(key) : null;
    const save = (dir, name, src) => sketchPad.save(dir + "/" + name, () => {
      if (b) pane.editor.touchMedia(key, { strokes: strokes, aspect: sketchPad.aspect });
      else pane.editor.insertBlocks([N.block("sketch", "", { src: src, name: name, strokes: strokes, aspect: sketchPad.aspect })], false);
    });
    if (b && b.src) save(win.mgr.base, b.src, b.src);
    else win.mgr.attachDir(n.id, "Sketch.png", (r) => { if (r) save(r.dir, r.name, r.src); });
  }

  // ── SAID ONCE ──────────────────────────────────────────────────────────
  function say(t, bad) { saidBox.say(t, bad); }
  Connections { target: win.mgr; function onFailure(text) { win.say(text, true); } }
  // the sync guard: the note changed on another machine as well — the one
  // from there is shown, what was written here kept beside it
  Connections {
    target: win.mgr
    function onChangedHere(id) { if (win.current && win.current.id === id) pane.show(win.mgr.noteOf(id)); }
    // pages changed outside Clio, read again: the note open shown afresh
    function onDiskChanged() {
      pane.show(win.current);
      win.say("Updated from the disk");
    }
    function onConflicted(id, copy) {
      if (win.current && win.current.id === id) pane.show(win.mgr.noteOf(id));
      win.say("Changed on another machine too — both kept, this one as “(this machine)”", true);
    }
  }

  // ── MENUS ──────────────────────────────────────────────────────────────
  property string menuHeld: ""
  function noteMenu(n, x, y) {
    if (!n) return;
    win.menuHeld = n.id;
    if (n.kind === "sticky") {
      menu.open(x, y, [
        { text: "Move to a container…", icon: "", run: () => win.moveMenu(n, x, y) },
        { text: "Color", icon: "\u{F03D8}", run: () => win.hueMenu(n, x, y) },
        { text: Clio.notes.some((s) => s.id === n.sticky && s.above) ? "Back under windows" : "Keep above windows", icon: "\u{F0931}",
          run: () => Clio.set(n.sticky, "above", !Clio.notes.some((s) => s.id === n.sticky && s.above)) },
        { text: Clio.shown ? "Hide stickies" : "Show stickies", icon: Clio.shown ? "" : "", run: () => Clio.toggle() },
        { isSeparator: true },
        { text: "Delete sticky…", icon: "", danger: true, run: () => win.trashNote(n) }]);
      return;
    }
    if (n.deleted) {
      menu.open(x, y, [{ text: "Restore", icon: "\u{F099B}", run: () => win.restoreNote(n) },
                       { text: "Move to…", icon: "", enabled: n.kind === "note", run: () => win.moveMenu(n, x, y) },
                       { isSeparator: true },
                       { text: "Delete forever…", icon: "", danger: true, run: () => win.destroyNote(n) }]);
      return;
    }
    const locked = !!n.sealed;
    const items = [];
    if (n.kind === "note") items.push({ text: n.pinned ? "Unpin" : "Pin", icon: "\u{F0403}", mark: "ctrl p", run: () => win.togglePin(n) });
    if (n.kind === "entry") items.push({ text: n.bookmark ? "Remove bookmark" : "Bookmark", icon: n.bookmark ? "\uF47A" : "\uF461", run: () => win.mgr.setField(n.id, "bookmark", !n.bookmark, false) });
    items.push({ text: "Rename…", icon: "\u{F0455}", run: () => win.renameNote(n) });
    items.push({ text: locked ? "Remove lock" : "Lock", icon: locked ? "" : "", run: () => locked ? win.removeLock(n) : win.lockNote(n) });
    if (n.kind === "note") {
      items.push({ text: "Move to…", icon: "", run: () => win.moveMenu(n, x, y) },
                 { text: "Put on the desktop", icon: "\u{F178F}", enabled: !locked || !!win.mgr.opened[n.id], run: () => win.toDesktop(n) });
    }
    items.push({ text: "Duplicate", icon: "\u{F0191}", mark: "ctrl d", enabled: !locked, run: () => win.duplicateNote(n) },
               { isSeparator: true },
               { text: "Export as Markdown…", icon: "", mark: "ctrl e", run: () => win.exportNote(n, "markdown") },
               { text: "Export as HTML…", icon: "", run: () => win.exportNote(n, "html") },
               { text: "Export as text…", icon: "", run: () => win.exportNote(n, "text") },
               { text: "Export as PDF…", icon: "\u{F0226}", run: () => win.exportNote(n, "pdf") },
               { text: "Print…", icon: "\u{F042A}", enabled: win.canPrint, run: () => win.printNote(n) },
               { text: "Save as a template…", icon: "\u{F0DC9}", enabled: !locked, run: () => win.saveTemplate(n) },
               { text: "Info", icon: "\u{F064E}", run: () => win.infoOf(n) },
               { text: "Show page in Terminus", icon: "\uF07C", run: () => { win.commit(); win.mgr.revealPage(n.id); } },
               { isSeparator: true },
               { text: n.kind === "entry" ? "Delete entry" : "Delete", icon: "", mark: "delete", danger: true, run: () => win.trashNote(n) });
    menu.open(x, y, items);
  }
  function hueMenu(n, x, y) {
    menu.open(x, y, Scribe.HUES.map((h) => ({ text: h[0].toUpperCase() + h.slice(1), icon: n.hue === h ? "" : "",
                                                iconInk: Clio.ink(h), run: () => Clio.set(n.sticky, "hue", h) })));
  }
  function folderMenu(f, x, y) {
    win.menuHeld = "f:" + f.id;
    if (f.query) {
      menu.open(x, y, [{ text: "Edit smart container…", icon: "", run: () => win.askSmart(f) },
                       { isSeparator: true }, { text: "Delete smart container…", icon: "", danger: true, run: () => win.deleteFolder(f) }]);
      return;
    }
    const kids = [{ text: "Top level", icon: "", enabled: f.parent !== "", run: () => win.mgr.moveFolder(f.id, "") }];
    for (const o of N.folderRows(win.mgr.folders, win.mgr.notes, {}))
      if (!N.wouldLoop(win.mgr.folders, f.id, o.id) && o.id !== f.parent) kids.push({ text: " ".repeat(o.depth) + o.name, icon: "", run: () => win.mgr.moveFolder(f.id, o.id) });
    menu.open(x, y, [
      { text: "New note here", icon: "", run: () => { win.setScope({ shelf: "folder", id: f.id }); win.newNote(); } },
      { text: "New container inside…", icon: "\u{F0257}", run: () => win.askFolder(f.id) },
      { text: "Rename…", icon: "\u{F0455}", run: () => win.renameFolder(f) },
      { text: "Move container…", icon: "", run: () => menu.open(x, y, kids) },
      { isSeparator: true },
      { text: "Delete container…", icon: "", danger: true, run: () => win.deleteFolder(f) }]);
  }
  function journalMenu(j, x, y) {
    win.menuHeld = "j:" + j.id;
    menu.open(x, y, [
      { text: "New entry", icon: "", run: () => { win.setScope({ shelf: "journal", id: j.id }); win.newEntry(); } },
      { text: "Rename and color…", icon: "\u{F0455}", run: () => win.askJournal(j) },
      { text: j.locked ? "Unlock journal" : "Lock journal", icon: j.locked ? "" : "",
        run: () => win.withPassword(() => { win.mgr.setJournal(j.id, { locked: !j.locked }); win.say(j.locked ? "The journal is open to all" : "The journal asks for the password"); }) },
      { text: "Export entries as Markdown…", icon: "", run: () => win.exportJournal(j) },
      { isSeparator: true },
      { text: "Delete journal…", icon: "", danger: true, enabled: win.mgr.journals.length > 1, run: () => win.deleteJournal(j) }]);
  }
  function exportJournal(j) {
    const list = N.entries(win.mgr.notes, j.id, {});
    const parts = [];
    for (const e of list.slice().reverse()) {
      const bs = win.mgr.blocksOf(e);
      if (!bs) continue;
      parts.push("## " + N.dateLong(e.date) + (e.mood ? " · " + N.moodOf(e.mood.v).label : "") + "\n\n" + N.markdownOf(bs, "attachments"));
    }
    const go = (dir) => {
      const path = dir + "/" + N.fileName(j.name, "md");
      win.mgr.call("export", { path: path, text: "# " + j.name + "\n\n" + parts.join("\n"),
                               files: list.flatMap((e) => (win.mgr.blocksOf(e) || []).filter((b) => b.src).map((b) => [b.src, dir + "/attachments/" + b.src])) },
                   (ok, r, err) => win.say(ok ? "Exported " + list.length + " entries" : "Not exported: " + (err ? err.error : ""), !ok));
    };
    if (win.mgr.fileManager) win.mgr.fileManager.choose(true, Quickshell.env("HOME") + "/Documents", (p) => { if (p && p.length) go(p[0]); });
  }

  // ── CARRYING ───────────────────────────────────────────────────────────
  // A note, an entry or a sticky pressed and moved: a card under the
  // pointer, the sidebar row it would land on lit (only one it can land
  // on), and on release: the Trash trashes it, a container takes a note or
  // a sticky, Stickies puts a note on the desktop, a journal takes an entry.
  property var carried: null
  function canLand(d, n) {
    if (!d || !n) return false;
    if (d.shelf === "trash") return !n.deleted;
    if (d.shelf === "folder") return n.kind === "note" || n.kind === "sticky";
    if (d.shelf === "desktop") return n.kind === "note";
    if (d.shelf === "journal") return n.kind === "entry" && n.journal !== d.id;
    return false;
  }
  function carry(n, from, m) {
    const p = from.mapToItem(stage, m.x, m.y);
    win.carried = n;
    carryCard.x = p.x + 12;
    carryCard.y = p.y + 6;
    const s = stage.mapToItem(side, p.x, p.y);
    const d = side.dropAt(s.x, s.y);
    side.dropHot = win.canLand(d, n) ? JSON.stringify(d) : "";
  }
  function land(from, m) {
    const n = win.carried;
    win.carried = null;
    side.dropHot = "";
    if (!n) return;
    const p = from.mapToItem(side, m.x, m.y);
    const d = side.dropAt(p.x, p.y);
    if (!win.canLand(d, n)) return;
    if (d.shelf === "trash") win.trashNote(n);
    else if (d.shelf === "desktop") win.toDesktop(n);
    else if (d.shelf === "folder") win.moveNote(n, d.id);
    else if (d.shelf === "journal") {
      win.commit();
      win.mgr.setField(n.id, "journal", d.id, false);
      win.say("Moved to " + (win.mgr.journalOf(d.id) || {}).name);
    }
  }

  // ── KEYS ───────────────────────────────────────────────────────────────
  function refocus() {
    if (cards.carding || win.sheetOpen) return;
    if (pane.editing || win.noteHad) pane.focusEditor(false); else listKeys.forceActiveFocus();
  }
  // the keys to the list, the note let go (Esc out of it)
  function toList() { win.noteHad = false; listKeys.forceActiveFocus(); }
  // whether the note had the keyboard before a menu, a card or a sheet took
  // it: by the time one closes the note no longer has it, and the keys went
  // to the list (and the next word typed into the search)
  property bool noteHad: false
  Connections {
    target: pane
    function onEditingChanged() {
      if (pane.editing) win.noteHad = true;
      else if (!menu.isOpen && !cards.carding && !win.sheetOpen) win.noteHad = false;
    }
  }
  readonly property bool sheetOpen: win.sketching || win.moodOpen || win.setOpen || win.picsOpen || win.momentsOpen || win.linkOpen || win.dateOpen || win.highlightsOpen || win.tasksOpen
  function unwind() {
    if (pane.trayOpen) { pane.trayOpen = false; return; }
    if (pane.finding) { pane.closeFind(); return; }
    if (win.query !== "") { win.query = ""; search.clear(); return; }
    if (win.day !== "") { win.day = ""; return; }
    // and nothing more: Esc never closes Clio (user, 2026-10-17)
  }
  // keys that are the window's whatever has the focus
  Shortcut { sequences: ["Ctrl+N"]; enabled: !win.sheetOpen && !cards.carding; onActivated: win.newNote() }
  Shortcut { sequences: ["Ctrl+J"]; enabled: !win.sheetOpen && !cards.carding; onActivated: win.newEntry() }
  Shortcut { sequences: ["Ctrl+T"]; enabled: !win.sheetOpen && !cards.carding; onActivated: win.today() }
  Shortcut { sequences: ["Ctrl+Shift+N"]; enabled: !win.sheetOpen && !cards.carding; onActivated: win.askFolder("") }
  Shortcut { sequences: ["Ctrl+Shift+F"]; enabled: !win.sheetOpen && !cards.carding; onActivated: search.grab() }
  Shortcut { sequences: ["Ctrl+P"]; enabled: !win.sheetOpen && !cards.carding; onActivated: win.togglePin(win.current) }
  Shortcut { sequences: ["Ctrl+D"]; enabled: !win.sheetOpen && !cards.carding; onActivated: win.duplicateNote(win.current) }
  Shortcut { sequences: ["Ctrl+E"]; enabled: !win.sheetOpen && !cards.carding; onActivated: win.exportNote(win.current, "markdown") }
  Shortcut { sequences: ["Ctrl+,"]; enabled: !cards.carding; onActivated: win.setOpen = true }
  Shortcut { sequences: ["Ctrl+1"]; onActivated: win.mgr.set("view", "list") }
  Shortcut { sequences: ["Ctrl+2"]; onActivated: win.mgr.set("view", "gallery") }
  Shortcut { sequences: ["Ctrl+=", "Ctrl++"]; onActivated: win.mgr.set("textScale", Math.min(1.6, Math.round((win.mgr.textScale + 0.1) * 10) / 10)) }
  Shortcut { sequences: ["Ctrl+-"]; onActivated: win.mgr.set("textScale", Math.max(0.8, Math.round((win.mgr.textScale - 0.1) * 10) / 10)) }
  Shortcut { sequences: ["Ctrl+0"]; onActivated: win.mgr.set("textScale", 1) }
  Shortcut { sequences: ["Ctrl+Alt+L"]; enabled: !!win.mgr && win.mgr.unlocked; onActivated: win.lockNow() }

  // the list's own keys: up and down, delete, return into the note, and
  // typing goes to the search
  Item {
    id: listKeys
    focus: true
    Keys.onPressed: (e) => {
      const ctrl = e.modifiers & Qt.ControlModifier;
      if (e.key === Qt.Key_Down || ctrl && e.key === Qt.Key_J) { win.move(1); e.accepted = true; return; }
      if (e.key === Qt.Key_Up || ctrl && e.key === Qt.Key_K) { win.move(-1); e.accepted = true; return; }
      if (e.key === Qt.Key_PageDown) { win.move(8); e.accepted = true; return; }
      if (e.key === Qt.Key_PageUp) { win.move(-8); e.accepted = true; return; }
      if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Right) { pane.focusEditor(false); e.accepted = true; return; }
      if (e.key === Qt.Key_Delete) { win.trashNote(win.current); e.accepted = true; return; }
      if (ctrl && e.key === Qt.Key_F) { search.grab(); e.accepted = true; return; }
      if (e.key === Qt.Key_Escape) { win.unwind(); e.accepted = true; return; }
      if (e.text && e.text.length > 0 && !ctrl && e.text.charCodeAt(0) >= 32) { search.grab(); search.type(e.text); e.accepted = true; }
    }
  }

  // ── THE STAGE ──────────────────────────────────────────────────────────
  Item {
    id: stage
    anchors.fill: parent

    Rectangle { z: -1; x: side.width; width: parent.width - x; height: parent.height; color: Zenon.layerBg }

    ClioSide {
      id: side
      win: win
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: 250
    }

    // ── the list, or the journal ──
    Item {
      id: listCol
      anchors.left: side.right
      anchors.top: parent.top
      anchors.bottom: foot.top
      width: win.inJournal ? Math.round(Math.min(560, Math.max(380, (win.width - side.width) * 0.42)))
                           : Math.round(Math.min(420, Math.max(300, (win.width - side.width) * 0.34)))
      Behavior on width { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.travelEase } }
      Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Zenon.border }

      NoteSearch {
        id: search
        win: win
        z: 5
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: win.headH
      }
      NoteList {
        id: list
        win: win
        anchors.top: search.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        visible: !win.inJournal
      }
      JournalList {
        id: journalList
        win: win
        anchors.top: search.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        visible: win.inJournal
      }
    }

    // ── the note ──
    NotePane {
      id: pane
      win: win
      anchors.left: listCol.right
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: foot.top
    }

    // ── what was just done, said once ──
    Ctl.Said {
      anchors.horizontalCenter: pane.horizontalCenter
      anchors.bottom: foot.top
      anchors.bottomMargin: 18 + pane.findH
      id: saidBox
      lasts: 2600
    }

    // ── and up out of the foot ──
    // the list, the journal and the note carry on under the hint strip,
    // frosted, rising out of it as they come — see morpheus/ScrollEdge
    Repeater {
      model: [list.listView, list.gridView, journalList.view, pane.editor.flick]
      delegate: ScrollEdge {
        required property var modelData
        view: modelData
        below: true
        follow: true
        // the note's find bar sits over the hint strip: both are chrome,
        // frosted as one from the note's foot down (no bar named, or the
        // find bar is the unfrosted gap) — and under the pane, so its
        // fields draw over the frost
        readonly property bool note: modelData === pane.editor.flick
        bar: note && pane.finding ? null : foot
        z: note ? -0.5 : 0
        visible: modelData.visible
      }
    }

    // ── the foot ──
    // morpheus/HintBar, as every strip (ceres' height, ground and rule)
    HintBar {
      id: foot
      anchors.bottom: parent.bottom
      anchors.left: side.right
      anchors.right: parent.right
      rows: win.hintRows
    }
  }

  readonly property var hintRows: pane.finding ? [["return", "next"], ["shift return", "back"], ["esc", "close find"]]
    : pane.editing ? [["ctrl b i u", "bold, italic, underline"], ["ctrl shift l", "checklist"], ["- * 1. []", "lists as you type"],
                      [">>", "link a note"], ["… =", "work it out"], ["ctrl f", "find"], ["esc", "to the list"]]
    : win.inJournal ? [["↑↓", "entry"], ["return", "write"], ["ctrl j", "new entry"], ["delete", "delete"], ["esc", win.query !== "" ? "clear" : "close"]]
    : [["↑↓", "note"], ["return", "write"], ["ctrl n", "new note"], ["ctrl p", "pin"], ["delete", "delete"], ["typing", "search"], ["esc", win.query !== "" ? "clear" : "close"]]

  // ── SHEETS ─────────────────────────────────────────────────────────────
  // each behind a shield, hung from the head over the note's side
  property bool moodOpen: false
  property bool setOpen: false
  property bool picsOpen: false
  property bool momentsOpen: false
  property bool linkOpen: false
  property bool dateOpen: false
  property bool highlightsOpen: false
  property bool tasksOpen: false
  onSheetOpenChanged: if (win.sheetOpen) sheetKeys.forceActiveFocus(); else Qt.callLater(win.refocus)
  Item {
    id: sheetKeys
    Keys.onPressed: (e) => {
      if (win.linkOpen && linkPick.key(e)) { e.accepted = true; return; }
      if (win.sketching && sketchPad.key(e)) { e.accepted = true; return; }
      if (e.key === Qt.Key_Escape) {
        if (win.sketching) win.sketchDone(null, false);
        win.moodOpen = win.setOpen = win.picsOpen = win.momentsOpen = win.linkOpen = win.dateOpen = win.highlightsOpen = win.tasksOpen = false;
        e.accepted = true;
      }
    }
  }

  InputShield { visible: win.moodOpen; onClicked: win.moodOpen = false }
  Sheet {
    shown: win.moodOpen
    fromTop: win.headH
    leftInset: listCol.x + listCol.width
    cardW: Math.min(pane.width - 60, 640)
    cardH: moodBody.implicitHeight
    MoodBody { id: moodBody; width: parent.width; win: win; onClosed: win.moodOpen = false }
  }
  InputShield { visible: win.dateOpen; onClicked: win.dateOpen = false }
  Sheet {
    shown: win.dateOpen
    fromTop: win.headH
    leftInset: listCol.x + listCol.width
    cardW: 420
    cardH: dateBody.implicitHeight
    DateBody { id: dateBody; width: parent.width; win: win; onClosed: win.dateOpen = false }
  }
  InputShield { visible: win.sketching; onClicked: {} }
  Sheet {
    shown: win.sketching
    fromTop: win.headH
    leftInset: side.width
    cardW: Math.min(win.width - side.width - 60, 980)
    cardH: Math.min(win.height - win.headH - 40, 720)
    SketchPad { id: sketchPad; anchors.fill: parent; win: win; onFinished: (strokes, ok) => win.sketchDone(strokes, ok) }
  }
  InputShield { visible: win.setOpen; onClicked: win.setOpen = false }
  Sheet {
    shown: win.setOpen
    fromTop: win.headH
    // centered on the window, not on what is right of the sidebar
    leftInset: 0
    // frosted over the window (user, 2026-10-17) — see morpheus/Sheet
    backdrop: stage
    cardW: Math.min(1040, win.width - 80)
    cardH: setBody.implicitHeight
    SettingsBody { id: setBody; width: parent.width; win: win; onClosed: win.setOpen = false }
  }
  InputShield { visible: win.picsOpen; onClicked: win.picsOpen = false }
  Sheet {
    shown: win.picsOpen
    fromTop: win.headH
    leftInset: side.width
    cardW: Math.min(win.width - side.width - 60, 980)
    cardH: Math.min(win.height - win.headH - 40, 680)
    AttachmentsBody { anchors.fill: parent; win: win; shown: win.picsOpen; onClosed: win.picsOpen = false }
  }
  InputShield { visible: win.momentsOpen; onClicked: win.momentsOpen = false }
  Sheet {
    shown: win.momentsOpen
    fromTop: win.headH
    leftInset: side.width
    cardW: Math.min(win.width - side.width - 60, 900)
    cardH: Math.min(win.height - win.headH - 40, 660)
    // frosted over the window (user, 2026-10-17) — see morpheus/Sheet
    backdrop: stage
    MomentsBody { anchors.fill: parent; win: win; shown: win.momentsOpen; onClosed: win.momentsOpen = false }
  }
  InputShield { visible: win.highlightsOpen; onClicked: win.highlightsOpen = false }
  Sheet {
    shown: win.highlightsOpen
    fromTop: win.headH
    leftInset: side.width
    cardW: Math.min(win.width - side.width - 60, 760)
    cardH: Math.min(win.height - win.headH - 40, 640)
    backdrop: stage
    HighlightsBody { anchors.fill: parent; win: win; shown: win.highlightsOpen; onClosed: win.highlightsOpen = false }
  }
  InputShield { visible: win.tasksOpen; onClicked: win.tasksOpen = false }
  Sheet {
    shown: win.tasksOpen
    fromTop: win.headH
    leftInset: side.width
    cardW: Math.min(win.width - side.width - 60, 760)
    cardH: Math.min(win.height - win.headH - 40, 640)
    backdrop: stage
    // by file, so it needs no shell restart (a new qmldir type does)
    Loader {
      id: tasksLoader
      anchors.fill: parent
      active: win.tasksOpen || !!item
      source: "TasksBody.qml"
      onLoaded: { item.win = win; item.closed.connect(() => win.tasksOpen = false); }
    }
  }
  Binding { target: tasksLoader.item; property: "shown"; value: win.tasksOpen; when: !!tasksLoader.item }
  InputShield { visible: win.linkOpen; onClicked: win.linkOpen = false }
  Sheet {
    shown: win.linkOpen
    fromTop: win.headH
    leftInset: listCol.x + listCol.width
    cardW: Math.min(pane.width - 60, 560)
    cardH: 420
    NotePicker {
      id: linkPick
      anchors.fill: parent
      win: win
      shown: win.linkOpen
      onPicked: (n) => { win.linkOpen = false; Qt.callLater(() => pane.editor.insertNoteLink(n.id, N.titleOf(n))); }
      onClosed: win.linkOpen = false
    }
  }

  // the card a carried note rides on
  Rectangle {
    id: carryCard
    parent: stage
    z: 1000
    visible: win.carried !== null
    width: Math.min(260, carryText.implicitWidth + 44)
    height: 34
    radius: Zenon.windowRadius
    color: Zenon.hud(0.9)
    border.width: 1
    border.color: Zenon.alpha(side.dropHot.indexOf("trash") >= 0 ? Zenon.yellow : Zenon.cyan, 0.6)
    Row {
      x: 12
      anchors.verticalCenter: parent.verticalCenter
      spacing: 8
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: !win.carried ? "" : win.carried.kind === "entry" ? "\u{F0B64}" : win.carried.kind === "sticky" ? "\u{F178F}" : "\u{F11D7}"
        color: Zenon.sand
        font.family: Zenon.glyphFace
        font.pixelSize: Zenon.px(14)
      }
      Text {
        id: carryText
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, 200)
        elide: Text.ElideRight
        text: win.carried ? N.titleOf(win.carried, win.carried.kind === "entry" ? N.dateLong(win.carried.date) : "") : ""
        color: Zenon.ink
        font.family: Zenon.face
        font.weight: Font.DemiBold
        font.pixelSize: Zenon.px(13)
      }
    }
  }

  // ── THE CARDS, THE MENU, THE TOOLTIP ───────────────────────────────────
  CardSheet {
    id: cards
    fromTop: win.headH
    leftInset: side.width
    cardW: 540
    onCleared: win.refocus()
  }
  PopMenu {
    id: menu
    parent: stage
    anchors.fill: parent
    window: win
    cardWidth: 280
    onClosed: { win.menuHeld = ""; win.refocus(); }
  }
  readonly property var menuRef: menu
  readonly property var sideRef: side
  readonly property var cardsRef: cards
  readonly property var paneRef: pane
  WindowTip { id: tips; window: win }
}

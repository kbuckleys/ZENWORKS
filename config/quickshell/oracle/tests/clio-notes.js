// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// CLIO'S NOTEBOOK, the pure half: blocks in and out of Qt's rich text,
// stickies, Markdown, search, the list's headings, folders, the journal's
// streaks and calendar, Math Notes' sums.
//
// The rich text is the shape a QML TextEdit really writes (read off one,
// 2026-10-14) — that is what the parser has to survive.

"use strict";

const QT = "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.0//EN\" \"http://www.w3.org/TR/REC-html40/strict.dtd\">\n<html><head><meta name=\"qrichtext\" content=\"1\" /><style type=\"text/css\">\np, li { white-space: pre-wrap; }\n</style></head><body style=\" font-family:'SF Pro Display'; font-size:16px; font-weight:600; font-style:normal;\">"
  + "\n<p style=\" margin-top:12px; margin-bottom:12px; margin-left:0px; margin-right:0px; -qt-block-indent:0; text-indent:0px;\">Hello <span style=\" font-weight:700;\">bold</span> and <a href=\"clio:note/x\"><span style=\" text-decoration: underline; color:#0000ff;\">link</span></a></p>"
  + "\n<ul style=\"margin-top: 0px; margin-bottom: 0px; margin-left: 0px; margin-right: 0px; -qt-list-indent: 1;\">"
  + "\n<li class=\"checked\" style=\" margin-top:12px; margin-bottom:0px; margin-left:0px; margin-right:0px; -qt-block-indent:0; text-indent:0px;\">done</li>"
  + "\n<li class=\"unchecked\" style=\" margin-top:0px; margin-bottom:12px; margin-left:0px; margin-right:0px; -qt-block-indent:0; text-indent:0px;\">todo</li></ul>"
  + "\n<ol style=\"margin-top: 0px; -qt-list-indent: 1;\">\n<li style=\" margin-top:12px;\">one</li></ol>"
  + "\n<h1 style=\" margin-top:18px;\"><span style=\" font-size:xx-large; font-weight:700;\">Head</span></h1>"
  + "\n<pre style=\" margin-top:12px;\"><span style=\" font-family:'monospace';\">code &lt;x&gt;</span></pre>"
  + "\n<pre style=\" margin-top:0px;\"><span style=\" font-family:'monospace';\">line</span></pre>"
  + "\n<p style=\" margin-top:12px; margin-bottom:12px; margin-left:40px; margin-right:40px; -qt-block-indent:0; text-indent:0px;\">quote</p>"
  + "\n<table border=\"0\" cellspacing=\"2\" cellpadding=\"0\">\n<tr>\n<td>\n<p style=\" margin-top:0px;\">a</p></td>\n<td>\n<p style=\" margin-top:0px;\">b</p></td></tr></table>"
  + "\n<hr />"
  + "\n<p style=\" margin-top:12px;\">x<br />y</p></body></html>";

module.exports = {
  module: "clio/notes.js",
  cases: (N, t) => {
    // ── Qt's rich text into blocks ──
    const bs = N.blocksOf(QT);
    t.eq("every paragraph is a block", bs.map((b) => b.k),
      ["body", "check", "check", "number", "title", "mono", "quote", "table", "rule", "body"]);
    t.eq("the link keeps its target, loses Qt's blue", bs[0].h, "Hello <span style=\" font-weight:700;\">bold</span> and <a href=\"clio:note/x\">link</a>");
    t.eq("checked and not", [bs[1].c, bs[2].c], [true, false]);
    t.eq("a heading's own size is not kept", bs[4].h, "<span style=\" font-weight:700;\">Head</span>");
    t.eq("code lines in a row are one block, as text", bs[5].h, "code <x>\nline");
    t.eq("a table's cells", bs[7].rows, [["a", "b"]]);
    t.eq("a line break stays inside its block", bs[9].h, "x<br />y");
    t.eq("an empty paragraph is an empty block", N.blocksOf("<p style=\"x\"><br /></p>").map((b) => b.h), [""]);
    t.eq("plain text is a block", N.blocksOf("just words")[0].h, "just words");
    const nested = N.blocksOf("<ul><li>a</li><ul><li>b</li></ul><li>c</li></ul>");
    t.eq("a list inside a list is indented", nested.map((b) => (b.l || 0)), [0, 1, 0]);

    // ── one TextEdit's text into a block's run ──
    t.eq("inline: the paragraph's inside", N.inline(QT.replace(/<ul[\s\S]*<\/html>/, "")), bs[0].h);
    t.eq("inline: empty is empty", N.inline("<p style=\"-qt-paragraph-type:empty;\"><br /></p>"), "");
    t.eq("plain words", N.plain("a&amp;b <b>c</b>&nbsp;d<br />e"), "a&b c d\ne");

    // ── marks ──
    const bold = "<span style=\" font-weight:700;\">x</span>";
    t.eq("bold is seen as Qt writes it", N.marked(bold, "b"), true);
    t.eq("toggled off, nothing left", N.toggleMark(bold, "b"), "x");
    t.eq("toggled on", N.toggleMark("x", "i"), "<i>x</i>");
    t.eq("strike", N.marked("<span style=\" text-decoration: line-through;\">s</span>", "s"), true);
    t.eq("a colour, and off again", N.colour(N.colour("x", "color", "#01c100"), "color", ""), "x");

    // ── colours by name ──
    const ink = (n) => ({ magenta: "#aa00aa", pink: "#ff88aa", yellow: "#ffaa00", green: "#00ff00", blue: "#0000ff", cyan: "#00ffff", red: "#ff0000" })[n];
    const mark = (n) => ({ sand: "#eedd99", pink: "#552233", green: "#225533", blue: "#223355", magenta: "#442244" })[n];
    const coloured = "<span style=\" color:" + N.sentinel("ink", 3) + ";\">g</span>";
    t.eq("painted with the theme's colour", N.paint(coloured, ink, mark), "<span style=\" color:#00ff00;\">g</span>");
    t.eq("and kept by name", N.unpaint(N.paint(coloured, ink, mark), ink, mark), coloured);

    // ── back out ──
    const note = [N.block("title", "Shop"), N.block("check", "milk", { c: true }), N.block("check", "eggs"),
                  N.block("number", "a"), N.block("number", "b", { l: 1 }), N.block("number", "c"),
                  N.block("image", "", { src: "n1/p.png", name: "p.png" }), N.block("body", "<b>x</b> &amp; y")];
    t.eq("numbers count along their level", N.numbering(note).slice(3, 6), [1, 1, 2]);
    t.eq("markdown", N.markdownOf(note, "att"),
      "# Shop\n\n- [x] milk\n- [ ] eggs\n1. a\n  1. b\n2. c\n\n![p.png](att/n1/p.png)\n\n**x** & y\n");
    t.eq("plain text", N.textOf(note.slice(0, 3)), "Shop\n☑ milk\n☐ eggs");
    const html = N.htmlOf(note, "");
    t.eq("html lists open and close", (html.match(/<ol>/g) || []).length, 2);
    t.eq("html: blocks back", N.blocksOf(html).map((b) => b.k), ["title", "check", "check", "number", "number", "number", "image", "body"]);

    // ── stickies ──
    const sticky = N.stickyOf(note.slice(0, 3));
    t.eq("a sticky draws boxes as characters", N.plain(sticky).replace(/\s+/g, " "), "Shop☑ milk☐ eggs");
    t.eq("and they come back as a checklist", N.blocksOfSticky(sticky).map((b) => b.k + (b.c ? "+" : "")), ["title", "check+", "check"]);
    t.eq("a plain sticky is its paragraphs", N.blocksOfSticky("<p>one</p><p>two</p>").map((b) => b.h), ["one", "two"]);
    t.eq("dropChars keeps the markup", N.dropChars("<b>☐ </b>milk", 2), "<b></b>milk");

    // ── typed shortcuts ──
    t.eq("shortcuts", ["- ", "* ", "1. ", "[] ", "# ", "> ", "x "].map((s) => (N.shortcut(s) || {}).k || ""),
      ["dash", "bullet", "number", "check", "title", "quote", ""]);

    // ── folds ──
    const doc = [N.block("title", "T"), N.block("heading", "A", { fold: true }), N.block("body", "a"),
                 N.block("subheading", "s"), N.block("heading", "B"), N.block("body", "b")];
    t.eq("a folded heading puts away what is under it", N.hidden(doc), [false, false, true, true, false, false]);
    t.eq("foldable only with something under", [N.foldable(doc, 1), N.foldable(doc, 3)], [true, false]);

    // ── what a note is ──
    const n1 = { id: "a", kind: "note", folder: "", created: 1, modified: 5, deleted: 0, pinned: false,
      blocks: [N.block("title", "Groceries"), N.block("check", "milk #shop", { c: true }), N.block("check", "bread")] };
    n1.d = N.derive(n1);
    t.eq("title, preview, tags", [n1.d.title, n1.d.preview, n1.d.tags], ["Groceries", "milk #shop  bread", ["shop"]]);
    t.eq("checks counted", [n1.d.checks, n1.d.done], [2, 1]);
    t.eq("words", n1.d.words, 4);
    t.eq("a #1 is not a tag", N.tagsOf("issue #1 and #todo-list/"), ["todo-list"]);

    // ── search and the list ──
    const n2 = { id: "b", kind: "note", folder: "f2", created: 3, modified: 9, deleted: 0, pinned: true,
      blocks: [N.block("title", "Ideas"), N.block("body", "grocery app idea")] };
    const n3 = { id: "c", kind: "note", folder: "f1", created: 2, modified: 7, deleted: 4, pinned: false,
      blocks: [N.block("title", "Old")] };
    const e1 = { id: "e", kind: "entry", journal: "journal", created: 1, modified: 1, deleted: 0, date: 1, blocks: [N.block("body", "grocery")] };
    for (const n of [n2, n3, e1]) n.d = N.derive(n);
    const all = [n1, n2, n3, e1];
    const ids = (l) => l.map((n) => n.id);
    t.eq("pinned first, then edited", ids(N.shelve(all, { shelf: "all" }, "", "modified")), ["b", "a"]);
    t.eq("the trash", ids(N.shelve(all, { shelf: "trash" }, "", "modified")), ["c"]);
    t.eq("search: title start beats body", ids(N.shelve(all, { shelf: "all" }, "groc", "modified")), ["a", "b"]);
    t.eq("search tokens", ids(N.shelve(all, { shelf: "all" }, "has:checklist", "modified")), ["a"]);
    t.eq("#tag token", ids(N.shelve(all, { shelf: "all" }, "#shop", "modified")), ["a"]);
    t.eq("is:todo", ids(N.shelve(all, { shelf: "all" }, "is:todo", "modified")), ["a"]);
    const folders = [{ id: "f1", name: "Work", parent: "" }, { id: "f2", name: "Ideas", parent: "f1" },
                     { id: "s1", name: "Lists", parent: "", query: "has:checklist" }];
    t.eq("a folder holds its subfolders' notes", ids(N.shelve(all, { shelf: "folder", id: "f1" }, "", "modified", folders)), ["b"]);
    t.eq("a smart folder", ids(N.shelve(all, { shelf: "smart", id: "s1" }, "", "modified", folders)), ["a"]);
    t.eq("folder rows", N.folderRows(folders, all).map((f) => f.name + f.depth + ":" + f.count), ["Work0:1", "Ideas1:1"]);
    t.eq("a shut folder hides its children", N.folderRows(folders, all, { f1: true }).length, 1);
    t.eq("a folder under itself loops", N.wouldLoop(folders, "f1", "f2"), true);
    t.eq("free names", N.freeName("New Folder", ["new folder", "New Folder 2"]), "New Folder 3");

    // ── dates ──
    const now = new Date(2026, 9, 14, 15, 30).getTime();
    t.eq("headings", [new Date(2026, 9, 14, 1), new Date(2026, 9, 13, 23), new Date(2026, 9, 9), new Date(2026, 8, 20),
                      new Date(2026, 2, 3), new Date(2024, 1, 1)].map((d) => N.sectionOf({ modified: d.getTime() }, "modified", now)),
      ["Today", "Yesterday", "Previous 7 Days", "Previous 30 Days", "March", "2024"]);
    t.eq("short dates", [new Date(2026, 9, 14, 9, 5), new Date(2026, 9, 13), new Date(2026, 9, 10), new Date(2026, 2, 3), new Date(2025, 0, 2)]
      .map((d) => N.dateShort(d.getTime(), now)), ["09:05", "Yesterday", "Saturday", "3 Mar", "2 Jan 2025"]);

    // ── the journal ──
    const day = (d, h) => new Date(2026, 9, d, h || 12).getTime();
    const ents = [14, 13, 12, 10, 9, 8, 7].map((d, i) => ({ id: "e" + i, kind: "entry", journal: "j", deleted: 0, created: day(d), date: day(d),
      bookmark: d === 12, mood: d === 13 ? { v: 2, words: [] } : null, prompt: "", d: { words: 10, images: d === 8 ? ["x"] : [], tags: [], text: "", title: "" } }));
    const ins = N.insights(ents, now);
    t.eq("the streak runs back from today", ins.streak, 3);
    t.eq("the longest", ins.longest, 4);
    t.eq("words and entries", [ins.words, ins.year], [70, 7]);
    t.eq("a streak survives until a day is missed", N.insights(ents.slice(1), now).streak, 2);
    t.eq("filters", ["bookmarked", "mood", "photos"].map((f) => N.entries(ents, "j", { filter: f }).length), [1, 1, 1]);
    t.eq("a day", N.entries(ents, "j", { day: N.dayKey(day(9)) }).map((e) => e.id), ["e4"]);
    const grid = N.monthGrid(2026, 9);
    t.eq("October 2026 starts on a Thursday", grid.slice(0, 4).map((c) => c.out), [true, true, true, false]);
    t.eq("whole weeks", grid.length % 7, 0);
    t.eq("prompts hold still for a day", N.promptOfDay(now) === N.promptOfDay(now + 3600000), true);

    // ── math ──
    t.eq("a sum", N.mathAsk("12 * 4 =", null), "12 * 4");
    t.eq("after a label", N.mathAsk("Total: 3 + 4=", null), "3 + 4");
    t.eq("not a sum", N.mathAsk("hello", null), null);
    const vars = N.mathVars(["rent = 1200", "months = 12"]);
    t.eq("names stand for values", N.mathAsk("rent * months =", vars), "(1200) * (12)");

    // ── keeping ──
    t.eq("a note read back keeps its kinds", N.clean({ id: "x", blocks: [{ k: "check", h: "a", c: 1 }, { k: "nope", h: "b" }] }).blocks.map((b) => b.k + b.c),
      ["checktrue", "bodyundefined"]);
    t.eq("a sealed note keeps its head only", N.clean({ id: "x", sealed: "abc", title: "Secret" }).blocks, null);
    t.eq("meta: a journal always", N.cleanMeta({}).journals.length, 1);
    t.eq("file names", [N.fileName("a/b: c", "md"), N.fileName("", "md")], ["a b c.md", "Note.md"]);
    t.eq("new fields survive a read", (() => { const c = N.clean({ id: "x", fromDesktop: { x: 1 }, uses: ["a.png"], blocks: [
        { k: "image", src: "p.png", beside: true, ocr: "hi" }, { k: "check", h: "a", due: 5 }, { k: "body", beside: true }] });
      return [c.fromDesktop.x, c.uses[0], c.blocks[0].beside, c.blocks[0].ocr, c.blocks[1].due, c.blocks[2].beside]; })(), [1, "a.png", true, "hi", 5, undefined]);
    t.eq("an entry read back from disk keeps its journal", (() => { const c = N.clean({ id: "x", kind: "entry", journal: "j1", date: 7, bookmark: true, _disk: 9, blocks: [] });
      return [c.journal, c.date, c.bookmark, c._disk, c.folder]; })(), ["j1", 7, true, 9, undefined]);
    t.eq("a name given is the title, over the first line", N.titleOf({ name: "Groceries", blocks: [{ k: "title", h: "Monday" }] }), "Groceries");
    t.eq("a name survives a read, sealed too", [N.clean({ id: "x", name: " A ", blocks: [] }).name, N.clean({ id: "x", name: "B", sealed: "s", title: "B" }).name], ["A", "B"]);
    t.eq("recent: written or opened, newest first, no Trash, no empty", N.recent([
        { id: "a", kind: "note", modified: 10, created: 2, blocks: [{ k: "title", h: "A" }] },
        { id: "b", kind: "entry", modified: 5, created: 1, blocks: [{ k: "body", h: "B" }] },
        { id: "c", kind: "note", modified: 30, deleted: 31, blocks: [{ k: "title", h: "C" }] },
        { id: "d", kind: "note", modified: 40, blocks: [{ k: "title", h: "" }] }], { b: 20 }, 5).map((r) => r.n.id), ["a", "b"]);
    t.eq("recent: a day apart, the later day first", N.recent([
        { id: "a", kind: "note", modified: 1000, created: 9, blocks: [{ k: "title", h: "A" }] },
        { id: "b", kind: "note", modified: 1000 + 86400000 * 2, created: 1, blocks: [{ k: "title", h: "B" }] }], {}, 5).map((r) => r.n.id), ["b", "a"]);
    t.eq("alignment kept on words, dropped elsewhere", [N.clean({ id: "x", blocks: [{ k: "body", h: "a", align: "center" }] }).blocks[0].align,
      N.clean({ id: "x", blocks: [{ k: "mono", h: "a", align: "right" }] }).blocks[0].align, N.clean({ id: "x", blocks: [{ k: "body", h: "a", align: "sideways" }] }).blocks[0].align],
      ["center", undefined, undefined]);
    t.eq("alignment exported", N.htmlOf([{ k: "body", h: "a", align: "right" }], "").indexOf("text-align: right") >= 0, true);
    t.eq("window fields never written", Object.keys(N.stored({ id: "x", _disk: 3, d: {} })), ["id"]);
    t.eq("words read off a picture are searchable", N.derive({ blocks: [{ k: "title", h: "T" }, { k: "image", src: "p", ocr: "invoice 42" }] }).text.indexOf("invoice") >= 0, true);

    // ── templates ──
    const tpl = N.templateOf([{ k: "title", h: "{weekday}" }, { k: "image", src: "p.png" }, { k: "check", h: "x", c: true, due: 9 }]);
    t.eq("a template keeps no pictures, ticks or reminders", tpl.map((b) => b.k + (b.c ? "+" : "") + (b.due ? "!" : "")), ["title", "check"]);
    const wed = new Date(2026, 9, 14, 8, 5).getTime();
    t.eq("filled in when used", N.fillTemplate(tpl, wed)[0].h, "Wednesday");
    t.eq("meta keeps templates and the daily one", (() => { const m = N.cleanMeta({ templates: [{ id: "t1", name: "Day", blocks: tpl }], daily: "t1" }); return [m.templates.length, m.daily]; })(), [1, "t1"]);
    t.eq("a daily template that is gone is none", N.cleanMeta({ daily: "t9" }).daily, "");

    // ── on this day ──
    const e = (y, m, d) => ({ id: "e" + y, kind: "entry", date: new Date(y, m, d, 12).getTime(), deleted: 0 });
    t.eq("on this day, nearest year first", N.onThisDay([e(2024, 9, 14), e(2025, 9, 14), e(2025, 9, 15), e(2026, 9, 14)], wed).map((x) => x.years), [1, 2]);

    // ── reminders ──
    t.eq("due today", N.dueText(new Date(2026, 9, 14, 14, 0).getTime(), wed), "14:00");
    t.eq("due tomorrow", N.dueText(new Date(2026, 9, 15, 9, 0).getTime(), wed), "Tomorrow 09:00");
    t.eq("due this week", N.dueText(new Date(2026, 9, 17, 18, 0).getTime(), wed), "Sat 18:00");
    t.eq("times typed", ["in 2 hours", "tomorrow 9", "2026-10-20 14:30", "20/10 9", "07:00", "soon"].map((s) => N.parseWhen(s, wed)),
      [wed + 7200000, new Date(2026, 9, 15, 9).getTime(), new Date(2026, 9, 20, 14, 30).getTime(), new Date(2026, 9, 20, 9).getTime(),
       new Date(2026, 9, 15, 7).getTime(), 0]);
    t.eq("presets", N.duePresets(wed).map((p) => p.label), ["In an hour", "This evening", "Tomorrow morning", "Next week"]);
    const due = [{ id: "n", blocks: [{ k: "check", h: "pay", due: wed - 1 }, { k: "check", h: "done", c: true, due: 1 }, { k: "check", h: "later", due: wed + 9 }] }];
    t.eq("what is due", N.dueChecks(due, wed, {}).map((x) => x.h), ["pay"]);
    t.eq("told once", N.dueChecks(due, wed, { ["n|" + (wed - 1) + "|pay"]: true }).length, 0);

    // ── backlinks ──
    const ln = [{ id: "a", modified: 1, d: { links: ["c"] } }, { id: "b", modified: 2, d: { links: ["c"] } }, { id: "c", modified: 3, d: { links: [] } }];
    t.eq("linked from", N.linksTo(ln, "c").map((n) => n.id), ["b", "a"]);
  }
};

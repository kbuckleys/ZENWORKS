// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// minerva's pure half: the library, places, progress, marks, settings,
// search snippets and EPUB links.

"use strict";

module.exports = {
  module: "minerva/minerva.js",
  cases: (M, t) => {
    t.eq("a pdf", M.kindOf("/a/B.PDF"), "pdf");
    t.eq("an epub", M.kindOf("/a/b.epub"), "epub");
    t.eq("a comic", M.kindOf("/a/b.CBR"), "comic");
    t.eq("a text", M.kindOf("/a/b.md"), "text");
    t.eq("anything else", M.kindOf("/a/b.doc"), "");
    t.ok("a comic is pages", M.paged("comic") && !M.paged("text"));
    t.eq("name without its extension", M.nameOf("/a/Owl Book.epub"), "Owl Book");

    // settings
    t.eq("defaults", M.cleanSettings(null), M.defaults());
    t.eq("font size clamped", M.cleanSettings({ fontSize: 99 }).fontSize, 40);
    t.eq("width on a 20px step", M.cleanSettings({ width: 731 }).width, 740);
    t.eq("a zoom number kept", M.cleanSettings({ zoom: 1.5 }).zoom, 1.5);
    t.eq("an unknown zoom is width", M.cleanSettings({ zoom: "huge" }).zoom, "width");
    // the window's own size (MinervaWindow keepSize): none until it closes once
    t.eq("no size kept by default", M.cleanSettings({}).winSize, undefined);
    t.eq("a size kept, rounded", M.cleanSettings({ winSize: [1300.4, 900.6] }).winSize, [1300, 901]);
    t.eq("never under the window's minimum", M.cleanSettings({ winSize: [100, 100] }).winSize, [820, 560]);
    t.eq("a broken size is dropped", M.cleanSettings({ winSize: [1300, "x"] }).winSize, undefined);

    // library
    const lib = M.parseLibrary(JSON.stringify({ books: [
      { path: "/b/one.pdf", pos: { page: 4 }, progress: 0.5, bookmarks: [{ id: "x", where: { page: 2 } }, { nope: 1 }] },
      { path: "/b/two.epub", title: "Two", pos: { chapter: 3, frac: 2 } },
      { path: "/b/one.pdf" },
      { path: "/b/three.doc" }
    ] }));
    t.eq("unreadable and repeated books dropped", lib.books.map((b) => b.path), ["/b/one.pdf", "/b/two.epub"]);
    t.eq("a title from the file name", lib.books[0].title, "one");
    t.eq("a bad mark dropped", lib.books[0].bookmarks.length, 1);
    t.eq("frac clamped", lib.books[1].pos.frac, 1);
    t.eq("garbage is an empty library", M.parseLibrary("{").books.length, 0);
    let books = M.upsert(lib.books, "/b/two.epub", { opened: 5 });
    t.eq("opened goes first", books[0].path, "/b/two.epub");
    books = M.upsert(books, "/b/new.epub", {});
    t.eq("a new book is added in front", books.map((b) => b.path), ["/b/new.epub", "/b/two.epub", "/b/one.pdf"]);
    books = M.update(books, "/b/one.pdf", { progress: 0.9 });
    t.eq("update keeps the order", books[2].progress, 0.9);
    t.eq("remove", M.remove(books, "/b/new.epub").length, 2);
    t.eq("round trip", M.parseLibrary(M.serializeLibrary({ books: books, settings: { fontSize: 22 } })).settings.fontSize, 22);

    // marks
    let marks = M.addMark([], { page: 7 }, "a line", 10);
    marks = M.addMark(marks, { page: 2 }, "", 20);
    t.eq("in reading order", M.sortMarks(marks).map((m) => m.where.page), [2, 7]);
    t.ok("found here", !!M.markHere(marks, { page: 7 }));
    t.eq("not here", M.markHere(marks, { page: 8 }), null);
    t.ok("an epub mark near enough", !!M.markHere(M.addMark([], { chapter: 1, frac: 0.5 }), { chapter: 1, frac: 0.51 }));
    t.eq("dropped", M.dropMark(marks, marks[0].id).length, 1);

    // progress
    const ch = [{ words: 100 }, { words: 300 }];
    t.eq("the start", M.epubProgress(ch, 0, 0), 0);
    t.eq("weighed by words", M.epubProgress(ch, 1, 0), 0.25);
    t.eq("the end", M.epubProgress(ch, 1, 1), 1);
    t.eq("pdf last page", M.pdfProgress(9, 10), 1);
    t.eq("pdf of one page", M.pdfProgress(0, 1), 1);
    t.eq("percent", M.percentWords(0.426), "43%");

    // places
    t.eq("a pdf place", M.whereWords("pdf", { page: 11 }), "Page 12");
    t.eq("an epub place", M.whereWords("epub", { chapter: 1, frac: 0.4 }, [{}, { title: "The Lamp" }]), "The Lamp · 40%");
    t.eq("an unnamed chapter", M.whereWords("epub", { chapter: 0, frac: 0 }, []), "Chapter 1 · 0%");
    const now = Date.parse("2026-10-20T12:00:00Z");
    t.eq("today", M.openedWords(now - 3600000, now), "Today");
    t.eq("yesterday", M.openedWords(now - 86400000 * 1.2, now), "Yesterday");
    t.eq("a week", M.openedWords(now - 86400000 * 8, now), "1 week ago");

    // search
    t.eq("lit, case kept", M.litSnippet("The Owl & owl", "owl", "#fff"),
      'The <b><font color="#fff">Owl</font></b> &amp; <b><font color="#fff">owl</font></b>');
    t.eq("nothing to light", M.litSnippet("a<b", "", "#fff"), "a&lt;b");

    // links
    t.eq("a chapter link", M.internalLink("ch:3#end"), { chapter: 3, anchor: "end" });
    t.eq("no anchor", M.internalLink("ch:0"), { chapter: 0, anchor: "" });
    t.eq("the web", M.internalLink("https://x"), null);
    t.has("a chapter set in its ink", M.chapterHtml("<p>x</p>", "#abc", "#def"), "color: #abc");
    t.has("…and its line spacing", M.chapterHtml("<p>x</p>", "#abc", "#def", 1.8), "line-height: 180%");
    const hm = M.setMark(M.addMark([], { page: 1 }, "x"), M.addMark([], { page: 1 }, "x")[0].id, { note: "n1" });
    t.eq("a mark's colour defaults to yellow", M.parseLibrary(JSON.stringify({ books: [{ path: "/a.pdf", highlights: [{ where: { page: 0 }, color: "plaid" }] }] })).books[0].highlights[0].color, "yellow");
    const q = M.parseLibrary(JSON.stringify({ books: [{ path: "/a.pdf", highlights: [{ where: { page: 0 }, quads: [[[0, 0], [10, 0], [10, 5]], [[1, 1]], "x"] }] }] })).books[0].highlights[0];
    t.eq("a highlight's outline kept, broken polygons dropped", q.quads, [[[0, 0], [10, 0], [10, 5]]]);
    t.eq("an epub highlight keeps its span", M.cleanPos("epub", { chapter: 1, frac: 0.2, start: 4, end: 9 }), { chapter: 1, frac: 0.2, start: 4, end: 9 });
    t.eq("…but not a backwards one", M.cleanPos("epub", { chapter: 1, frac: 0.2, start: 9, end: 4 }), { chapter: 1, frac: 0.2 });

    // new settings
    const st = M.cleanSettings({ theme: "night", spread: "cover", sort: "nope", shelves: ["Work", "work", " ", "Fun"], shelf: "Gone", watch: ["/home/b", "rel"] });
    t.eq("a theme", st.theme, "night");
    t.eq("a spread", st.spread, "cover");
    t.eq("an unknown sort", st.sort, "recent");
    t.eq("shelves deduped by case", st.shelves, ["Work", "Fun"]);
    t.eq("a shelf that is gone is none", st.shelf, "");
    t.eq("only absolute watched paths", st.watch, ["/home/b"]);

    // the library shown
    const shown = [
      { path: "/l/a.pdf", title: "Beta", author: "Ann Zed", opened: 5, added: 1, progress: 0.2, shelves: ["Work"], finished: 0 },
      { path: "/l/b.epub", title: "alpha 10", author: "Bo Young", opened: 0, added: 3, progress: 0, shelves: [], finished: 0 },
      { path: "/l/c.epub", title: "Alpha 9", author: "", opened: 9, added: 2, progress: 1, shelves: ["Work"], finished: 7 }
    ];
    t.eq("states", shown.map(M.stateOf), ["reading", "unread", "finished"]);
    t.eq("by state", M.filterBooks(shown, "unread", "", "").map((b) => b.path), ["/l/b.epub"]);
    t.eq("by shelf", M.filterBooks(shown, "all", "Work", "").length, 2);
    t.eq("by words", M.filterBooks(shown, "all", "", "zed").length, 1);
    t.eq("recent", M.sortBooks(shown, "recent").map((b) => b.title), ["Alpha 9", "Beta", "alpha 10"]);
    t.eq("title, numbers in order", M.sortBooks(shown, "title").map((b) => b.title), ["Alpha 9", "alpha 10", "Beta"]);
    t.eq("author by surname, none last", M.sortBooks(shown, "author").map((b) => b.title), ["alpha 10", "Beta", "Alpha 9"]);
    t.eq("progress", M.sortBooks(shown, "progress")[0].title, "Alpha 9");
    t.eq("added", M.sortBooks(shown, "added")[0].title, "alpha 10");
    t.eq("a shelf ticked", M.toggleShelf(["A"], "B"), ["A", "B"]);
    t.eq("a shelf unticked", M.toggleShelf(["A", "B"], "A"), ["B"]);
    const found = M.addFound([{ path: "/l/a.pdf", title: "x", kind: "pdf" }], ["/l/a.pdf", "/l/n.cbz", "/l/n.doc", "/l/n.cbz"], 50);
    t.eq("found books join once, at the end", found.map((b) => b.path), ["/l/a.pdf", "/l/n.cbz"]);
    t.eq("…unread", M.stateOf(found[1]), "unread");

    // time
    const day = new Date(2026, 9, 21, 12).getTime();
    let stats = M.addTime(null, 90000, day);
    stats = M.addTime(stats, 70000, day - 86400000);
    stats = M.addTime(stats, 30000, day - 2 * 86400000);
    t.eq("a day's time", stats.days[M.dayKey(day)], 90000);
    t.eq("a streak stops at a day under a minute", M.streak(stats, day), 2);
    t.eq("a streak survives a day not yet read", M.streak(stats, day + 86400000), 2);
    t.eq("the last days", M.lastDays(stats, 3, day), [30000, 70000, 90000]);
    t.eq("time left at the pace so far", M.timeLeft({ progress: 0.25, readMs: 600000, finished: 0 }), 1800000);
    t.eq("not known yet", M.timeLeft({ progress: 0.01, readMs: 600000, finished: 0 }), -1);
    t.eq("minutes", M.spanWords(25 * 60000), "25 min");
    t.eq("hours", M.spanWords(130 * 60000), "2 h 10 min");
    t.eq("stats round trip", M.parseLibrary(M.serializeLibrary({ books: [], stats: stats })).stats.days[M.dayKey(day)], 90000);

    // themes
    const sh = { bg: "#000", ink: "#fff", link: "#0ff" };
    t.eq("auto: a chapter in the shell's colours", M.themeOf("auto", "epub", sh).bg, "#000");
    t.eq("auto: a pdf as printed", M.themeOf("auto", "pdf", sh).tone, false);
    t.eq("sepia toned for a pdf", M.themeOf("sepia", "pdf", sh).tone, true);
    t.eq("a comic is never toned", M.themeOf("night", "comic", sh).tone, false);
    // night follows the shell theme when it is given one (MinervaWindow nightTone)
    const nt = Object.assign({}, sh, { night: { bg: "#1a120c", ink: "#e8dccb", link: "#d08a4a" } });
    t.eq("night in the theme's tone", M.themeOf("night", "epub", nt).bg, "#1a120c");
    t.eq("its ink too", M.themeOf("night", "pdf", nt).ink, "#e8dccb");
    t.eq("still toned for a pdf", M.themeOf("night", "pdf", nt).tone, true);
    t.eq("no theme given: the fixed night", M.themeOf("night", "epub", sh).bg, "#151517");
    t.eq("sepia stays sepia", M.themeOf("sepia", "epub", nt).bg, "#f4ecd8");

    // layout
    const sizes = [{ width: 100, height: 200 }, { width: 100, height: 200 }, { width: 200, height: 100 }];
    const one = M.layoutPages(sizes, 1, "off", 10, 4, 0);
    t.eq("one to a row", one.rows, [[0], [1], [2]]);
    t.eq("tops", one.tops, [10, 214, 418, 522]);
    t.eq("the widest row sets the width", one.contentW, 220);
    t.eq("centered", one.rects[0].x, 60);
    t.eq("height", one.contentH, 528);
    const two = M.layoutPages(sizes, 1, "on", 10, 4, 0);
    t.eq("two to a row", two.rows, [[0, 1], [2]]);
    t.eq("side by side", [two.rects[0].x, two.rects[1].x], [10, 114]);
    t.eq("cover alone", M.layoutPages(sizes, 1, "cover", 10, 4, 0).rows, [[0], [1, 2]]);
    t.eq("a short page centered in its row", M.layoutPages(sizes, 1, "cover", 10, 4, 0).rects[2].y, 214 + 50);
    t.eq("room over the first row", M.layoutPages(sizes, 1, "off", 10, 4, 0, 48).tops[0], 58);
    t.eq("…and under the last", M.layoutPages(sizes, 1, "off", 10, 4, 0, 48).contentH, 576);
    t.eq("row at y", M.rowAt(one.tops, 300), 1);
    t.eq("row at the top", M.rowAt(one.tops, 0), 0);
    t.eq("row past the foot", M.rowAt(one.tops, 9999), 2);
    t.eq("fit width", M.fitZoom(sizes, "off", "width", 0, 10, 4, 420, 1000), 2);
    t.eq("fit page", M.fitZoom(sizes, "off", "page", 0, 10, 4, 420, 420), 2);
    t.eq("fit a spread's width", M.fitZoom(sizes, "on", "width", 0, 10, 4, 424, 1000), 2);

    // highlights out
    const md = M.highlightsMarkdown({ title: "Owl", author: "M", kind: "pdf", highlights: [
      { where: { page: 4 }, text: "late\nlight", at: 2, color: "blue", comment: "nice" },
      { where: { page: 1 }, text: "first", at: 1, color: "yellow", comment: "" }] });
    t.has("a title", md, "# Owl");
    t.ok("in reading order", md.indexOf("> first") < md.indexOf("> late light"));
    t.has("its place and colour", md, "— Page 5 · blue");
    t.has("its comment", md, "nice");

    // read aloud
    const text = "Hello there. \"Is it?\" she said! Fin";
    t.eq("sentences", M.sentences(text).map((r) => text.slice(r.start, r.end)), ["Hello there.", "\"Is it?\"", "she said!", "Fin"]);
    t.eq("a decimal is not a stop", M.sentences("Pi is 3.14 ok.").length, 1);
    t.eq("blank lines are nothing", M.sentences("\n\n  \n").length, 0);
    t.ok("a long run is cut", M.sentences(Array(200).join("word ")).length > 1);

    t.eq("a mark's note survives a round trip", M.parseLibrary(M.serializeLibrary({ books: [{ path: "/a.pdf", highlights: [{ id: "h", where: { page: 1 }, note: "n9" }] }] })).books[0].highlights[0].note, "n9");
  }
};

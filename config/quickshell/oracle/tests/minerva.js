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
    t.eq("anything else", M.kindOf("/a/b.txt"), "");
    t.eq("name without its extension", M.nameOf("/a/Owl Book.epub"), "Owl Book");

    // settings
    t.eq("defaults", M.cleanSettings(null), M.defaults());
    t.eq("font size clamped", M.cleanSettings({ fontSize: 99 }).fontSize, 40);
    t.eq("width on a 20px step", M.cleanSettings({ width: 731 }).width, 740);
    t.eq("a zoom number kept", M.cleanSettings({ zoom: 1.5 }).zoom, 1.5);
    t.eq("an unknown zoom is width", M.cleanSettings({ zoom: "huge" }).zoom, "width");

    // library
    const lib = M.parseLibrary(JSON.stringify({ books: [
      { path: "/b/one.pdf", pos: { page: 4 }, progress: 0.5, bookmarks: [{ id: "x", where: { page: 2 } }, { nope: 1 }] },
      { path: "/b/two.epub", title: "Two", pos: { chapter: 3, frac: 2 } },
      { path: "/b/one.pdf" },
      { path: "/b/three.txt" }
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
    t.eq("a mark's note survives a round trip", M.parseLibrary(M.serializeLibrary({ books: [{ path: "/a.pdf", highlights: [{ id: "h", where: { page: 1 }, note: "n9" }] }] })).books[0].highlights[0].note, "n9");
  }
};

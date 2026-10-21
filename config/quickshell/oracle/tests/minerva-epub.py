#!/usr/bin/env python3
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# minerva's EPUB unpacker (minerva/core/epub.py), against books made here:
# an EPUB 3 with a nav, an EPUB 2 with only an NCX, and a broken zip.

import json
import os
import shutil
import sys
import tempfile
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "minerva", "core"))
import epub  # noqa: E402
import books  # noqa: E402

TMP = tempfile.mkdtemp(prefix="minerva-test-")
fails, count = [], 0


def eq(name, got, want):
    global count
    count += 1
    if got != want:
        fails.append("%s\n      want %r\n      got  %r" % (name, want, got))


def has(name, hay, needle):
    global count
    count += 1
    if needle not in hay:
        fails.append("%s\n      %r missing" % (name, needle))


def hasnt(name, hay, needle):
    global count
    count += 1
    if needle in hay:
        fails.append("%s\n      %r should be gone" % (name, needle))


def book(path, opf, files, nav=None, ncx=None):
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("mimetype", "application/epub+zip")
        z.writestr("META-INF/container.xml", '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>')
        z.writestr("OPS/book.opf", opf)
        for name, data in files.items():
            z.writestr("OPS/" + name, data)
        if nav:
            z.writestr("OPS/nav.xhtml", nav)
        if ncx:
            z.writestr("OPS/toc.ncx", ncx)


try:
    # ── EPUB 3 ────────────────────────────────────────────────────────────
    p3 = os.path.join(TMP, "three.epub")
    book(p3, '''<package xmlns="http://www.idpf.org/2007/opf" version="3.0"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Three</dc:title><dc:creator>Ann</dc:creator></metadata>
<manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="a" href="a.xhtml" media-type="application/xhtml+xml"/><item id="b" href="sub/b.xhtml" media-type="application/xhtml+xml"/><item id="p" href="pic.png" media-type="image/png"/></manifest>
<spine><itemref idref="a"/><itemref idref="b"/></spine></package>''',
         {"a.xhtml": '<html xmlns="http://www.w3.org/1999/xhtml"><head><script>x()</script><style>p{}</style></head><body><p>Alpha <i>owl</i> &amp; <b>lamp</b>.</p><img src="pic.png"/><p><a href="sub/b.xhtml#end">to the end</a></p></body></html>',
          "sub/b.xhtml": '<html xmlns="http://www.w3.org/1999/xhtml"><body><h2>Beta</h2><p id="end">Owl again, owl.</p><svg><text>gone</text></svg></body></html>',
          "pic.png": b"\x89PNG\r\n\x1a\n"},
         nav='<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body><nav epub:type="toc"><ol><li><a href="a.xhtml">First</a></li><li><a href="sub/b.xhtml">Second</a><ol><li><a href="sub/b.xhtml#end">The end</a></li></ol></li></ol></nav></body></html>')
    d3 = os.path.join(TMP, "c3")
    b3 = epub.open_book(p3, d3)
    eq("title", b3["title"], "Three")
    eq("author", b3["author"], "Ann")
    eq("two chapters, in spine order", [c["file"] for c in b3["chapters"]], ["0000.html", "0001.html"])
    eq("chapters named by the contents", [c["title"] for c in b3["chapters"]], ["First", "Second"])
    eq("the contents, nested", [(t["label"], t["chapter"], t["anchor"], t["depth"]) for t in b3["toc"]],
       [("First", 0, "", 0), ("Second", 1, "", 0), ("The end", 1, "end", 1)])
    a = open(os.path.join(d3, "ch", "0000.html")).read()
    hasnt("scripts dropped", a, "x()")
    hasnt("styles dropped", a, "p{}")
    has("italic kept as em", a, "<em>owl</em>")
    has("bold kept as strong", a, "<strong>lamp</strong>")
    has("an entity kept escaped", a, "&amp;")
    has("a picture by absolute file url", a, 'src="file://' + d3)
    has("a link between chapters", a, 'href="ch:1#end"')
    b = open(os.path.join(d3, "ch", "0001.html")).read()
    has("an id becomes an anchor", b, '<a name="end"></a>')
    hasnt("svg dropped", b, "gone")
    # unchanged book: read back, not unpacked again
    mtime = os.path.getmtime(os.path.join(d3, "book.json"))
    eq("a second open reads book.json back", epub.open_book(p3, d3)["stamp"], b3["stamp"])
    eq("…without writing it", os.path.getmtime(os.path.join(d3, "book.json")), mtime)
    # a cache missing a chapter is unpacked again, not trusted
    os.remove(os.path.join(d3, "ch", "0000.html"))
    epub.open_book(p3, d3)
    eq("a chapter missing from the cache is made again", os.path.exists(os.path.join(d3, "ch", "0000.html")), True)
    os.remove(os.path.join(d3, "ch", "0000.html"))
    eq("find skips a chapter it cannot read", [h["chapter"] for h in epub.find(d3, "owl")], [1, 1])
    epub.open_book(p3, d3)
    hits = epub.find(d3, "OWL")
    eq("find ignores case", [h["chapter"] for h in hits], [0, 1, 1])
    has("a snippet around the hit", hits[1]["snippet"], "Owl again")
    eq("nothing to find", epub.find(d3, "  "), [])

    # ── EPUB 2 (NCX only) ─────────────────────────────────────────────────
    p2 = os.path.join(TMP, "two.epub")
    book(p2, '''<package xmlns="http://www.idpf.org/2007/opf" version="2.0"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Two</dc:title></metadata>
<manifest><item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/><item id="c" href="c.html" media-type="application/xhtml+xml"/></manifest>
<spine toc="ncx"><itemref idref="c"/></spine></package>''',
         {"c.html": "<html><body><p>Gamma</p></body></html>"},
         ncx='<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/"><navMap><navPoint><navLabel><text>Only</text></navLabel><content src="c.html"/></navPoint></navMap></ncx>')
    b2 = epub.open_book(p2, os.path.join(TMP, "c2"))
    eq("an NCX's contents", [t["label"] for t in b2["toc"]], ["Only"])
    eq("no cover", b2["cover"], "")

    # ── broken ────────────────────────────────────────────────────────────
    bad = os.path.join(TMP, "bad.epub")
    open(bad, "wb").write(b"not a zip")
    try:
        epub.open_book(bad, os.path.join(TMP, "cb"))
        eq("a broken book raises", "no error", "BadZipFile")
    except zipfile.BadZipFile:
        eq("a broken book raises", "BadZipFile", "BadZipFile")

    # ── markdown and text ─────────────────────────────────────────────────
    md = os.path.join(TMP, "notes.md")
    open(md, "w").write("# The Owl\n\nIntro *soft* and **loud**, `code` [web](https://x.y).\n\n"
                        "## One\n\n- a\n- b\n\n> quoted\n\n## Two\n\n```\n<raw>\n```\n")
    bm = epub.text_book(md, os.path.join(TMP, "md"))
    eq("one h1 is the title", bm["title"], "The Owl")
    eq("chapters at the headings", [c["title"] for c in bm["chapters"]], ["The Owl", "One", "Two"])
    c0 = open(os.path.join(TMP, "md", "ch", bm["chapters"][0]["file"])).read()
    has("emphasis", c0, "<em>soft</em>")
    has("strong", c0, "<strong>loud</strong>")
    has("a web link", c0, '<a href="https://x.y">web</a>')
    c1 = open(os.path.join(TMP, "md", "ch", bm["chapters"][1]["file"])).read()
    has("a list", c1, "<ul><li>a</li><li>b</li></ul>")
    has("a quote", c1, "<blockquote>quoted</blockquote>")
    c2 = open(os.path.join(TMP, "md", "ch", bm["chapters"][2]["file"])).read()
    has("code kept escaped", c2, "<pre>&lt;raw&gt;</pre>")
    eq("contents", [t["label"] for t in bm["toc"]], ["The Owl", "One", "Two"])
    tx = os.path.join(TMP, "story.txt")
    open(tx, "w").write("Front matter.\n\nChapter 1\n\nIt began\nhere.\n\nChapter 2\n\nThe end.\n")
    bt = epub.text_book(tx, os.path.join(TMP, "tx"))
    eq("a text's chapter lines", [c["title"] for c in bt["chapters"]], ["", "Chapter 1", "Chapter 2"])
    has("lines joined in a paragraph", open(os.path.join(TMP, "tx", "ch", bt["chapters"][1]["file"])).read(), "<p>It began here.</p>")
    long = os.path.join(TMP, "long.txt")
    open(long, "w").write("\n\n".join(["word " * 500] * 20))
    eq("a long text without chapters is cut in parts", len(epub.text_book(long, os.path.join(TMP, "lg"))["chapters"]), 3)

    # ── comics ────────────────────────────────────────────────────────────
    import struct as _st
    import zlib as _z

    def png(w, h):
        raw = b"".join(b"\x00" + b"\x00" * (w * 3) for _ in range(h))
        chunk = lambda t, d: _st.pack(">I", len(d)) + t + d + _st.pack(">I", _z.crc32(t + d) & 0xFFFFFFFF)
        return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", _st.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", _z.compress(raw)) + chunk(b"IEND", b"")
    cbz = os.path.join(TMP, "c.cbz")
    with zipfile.ZipFile(cbz, "w") as z:
        z.writestr("p10.png", png(4, 6))
        z.writestr("p2.png", png(3, 5))
        z.writestr("notes.txt", "x")
    cb = books.comic(cbz, os.path.join(TMP, "cbz"))
    eq("pages in natural order", [os.path.basename(p["file"]) for p in cb["pages"]], ["p2.png", "p10.png"])
    eq("sizes from the headers", [(p["width"], p["height"]) for p in cb["pages"]], [(3, 5), (4, 6)])
    eq("read back unchanged", books.comic(cbz, os.path.join(TMP, "cbz"))["stamp"], cb["stamp"])
    lib = os.path.join(TMP, "lib")
    os.makedirs(os.path.join(lib, "a", ".hidden"))
    for f in ["a/x.pdf", "a/.hidden/y.pdf", "z.epub", "n.txt", "q.CBZ"]:
        open(os.path.join(lib, f), "w").write("")
    eq("a scan finds books, not hidden ones or texts", sorted(os.path.relpath(p, lib) for p in books.scan([lib])), ["a/x.pdf", "q.CBZ", "z.epub"])
finally:
    shutil.rmtree(TMP, ignore_errors=True)

for f in fails:
    print("  FAIL  " + f)
print("  %d of %d minerva epub checks %s" % (len(fails) if fails else count, count, "FAILED" if fails else "pass"))
sys.exit(1 if fails else 0)

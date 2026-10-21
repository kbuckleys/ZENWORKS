#!/usr/bin/env python3
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# minerva's EPUB unpacker: an .epub into something Qt's rich text can set.
#
#   epub.py open <book.epub> <cache dir>     → book.json on stdout
#   epub.py find <cache dir> <words>         → [{ chapter, at, snippet }]
#   epub.py text <book.txt|.md> <cache dir>  → book.json, the same shape
#
# A plain text or a Markdown file is read as a book too (user, 2026-10-21):
# Markdown's headings make its chapters (# and ##, when there are two or
# more), a text's "Chapter …" lines make its, and a text with none is cut
# into parts of about 4000 words at a blank line, so no chapter is a
# scroll the length of the book.
#
# An EPUB is a zip of XHTML chapters, a manifest and a reading order (the
# OPF), a table of contents (nav.xhtml or toc.ncx) and pictures. Qt's
# RichText is HTML 4's plain subset — no CSS layout, no SVG, no scripts —
# so each chapter is rewritten to what it can set: paragraphs, headings,
# emphasis, lists, quotes, preformatted text, pictures (by absolute file
# URL) and links between chapters (as "ch:N#anchor"). Everything lands in
# the cache dir, keyed by the caller; a second open with the same dir and
# an unchanged book reads book.json back without unpacking again.
#
#   book.json: { title, author, cover, chapters: [{ file, title, words }],
#                toc: [{ label, chapter, anchor, depth }] }
#
# Standard library only.

import html
import json
import os
import posixpath
import re
import sys
import zipfile
from html.parser import HTMLParser
from urllib.parse import unquote, urldefrag
import xml.etree.ElementTree as ET

NS = {
    "c": "urn:oasis:names:tc:opendocument:xmlns:container",
    "opf": "http://www.idpf.org/2007/opf",
    "dc": "http://purl.org/dc/elements/1.1/",
    "ncx": "http://www.daisy.org/z3986/2005/ncx/",
    "xhtml": "http://www.w3.org/1999/xhtml",
    "epub": "http://www.idpf.org/2007/ops",
}
VERSION = 3  # bumped when the rewrite changes, so old caches are redone

# what a chapter keeps; everything else is unwrapped (its text kept)
KEEP = {"p", "h1", "h2", "h3", "h4", "h5", "h6", "em", "i", "strong", "b", "u", "s",
        "sub", "sup", "blockquote", "ul", "ol", "li", "pre", "code", "br", "hr",
        "a", "img", "dl", "dt", "dd", "small", "big", "table", "tr", "td", "th"}
BLOCK = {"div", "section", "article", "aside", "figure", "figcaption", "header", "footer",
         "main", "nav", "body", "center"}
DROP = {"script", "style", "head", "title", "svg", "math", "iframe", "object", "noscript"}
VOID = {"br", "hr", "img"}


def text(el):
    return "".join(el.itertext()).strip() if el is not None else ""


class Rewriter(HTMLParser):
    """A chapter's XHTML → Qt rich text. Ids become <a name> anchors."""

    def __init__(self, base, resolve_img, resolve_link):
        super().__init__(convert_charrefs=True)
        self.out = []
        self.drop = 0
        self.base = base
        self.img = resolve_img
        self.link = resolve_link
        self.words = 0
        self.open_blocks = []

    def handle_starttag(self, tag, attrs):
        tag = tag.lower().split(":")[-1]
        a = dict(attrs)
        if self.drop or tag in DROP:
            if tag not in VOID:
                self.drop += 1
            return
        anchor = a.get("id")
        if anchor:
            self.out.append('<a name="%s"></a>' % html.escape(anchor, quote=True))
        if tag in BLOCK:
            # a div is a paragraph's worth of break, no more
            self.open_blocks.append(tag)
            return
        if tag not in KEEP:
            return
        if tag == "img" or (tag == "image"):
            src = self.img(a.get("src") or a.get("xlink:href") or a.get("href") or "")
            if src:
                alt = html.escape(a.get("alt") or "", quote=True)
                self.out.append('<p align="center"><img src="%s" alt="%s"></p>' % (html.escape(src, quote=True), alt))
            return
        if tag == "a":
            href = a.get("href") or ""
            target = self.link(href) if href else ""
            self.out.append('<a href="%s">' % html.escape(target, quote=True) if target else "<a>")
            return
        if tag == "i":
            tag = "em"
        if tag == "b":
            tag = "strong"
        self.out.append("<%s>" % tag)

    def handle_endtag(self, tag):
        tag = tag.lower().split(":")[-1]
        if self.drop:
            if tag in DROP or tag not in VOID:
                self.drop -= 1
            return
        if tag in BLOCK:
            if self.open_blocks:
                self.open_blocks.pop()
            self.out.append("<br>") if self.out and not self.out[-1].endswith(("</p>", "<br>", "</h1>", "</h2>",
                                                                                "</h3>", "</h4>", "</li>", "</blockquote>",
                                                                                "</pre>", "</ul>", "</ol>")) else None
            return
        if tag not in KEEP or tag in VOID:
            return
        if tag == "i":
            tag = "em"
        if tag == "b":
            tag = "strong"
        self.out.append("</%s>" % tag)

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        t = tag.lower().split(":")[-1]
        if t not in VOID and t not in BLOCK:
            self.handle_endtag(tag)

    def handle_data(self, data):
        if self.drop:
            return
        self.words += len(data.split())
        self.out.append(html.escape(data, quote=False))

    def result(self):
        s = "".join(self.out)
        s = re.sub(r"(<br>\s*){3,}", "<br><br>", s)
        return s.strip()


def opf_path(z):
    root = ET.fromstring(z.read("META-INF/container.xml"))
    rf = root.find(".//c:rootfile", NS)
    if rf is None:
        raise ValueError("no rootfile in container.xml")
    return rf.get("full-path")


def open_book(src, dest):
    src, dest = os.path.abspath(src), os.path.abspath(dest)
    os.makedirs(dest, exist_ok=True)
    stamp = "%d:%d:%d" % (VERSION, os.path.getmtime(src), os.path.getsize(src))
    meta_path = os.path.join(dest, "book.json")
    try:
        with open(meta_path) as f:
            old = json.load(f)
        # trusted only whole: a cache missing a chapter (cleaned in part)
        # is unpacked again rather than read back with holes in it
        if old.get("stamp") == stamp and all(
                os.path.exists(os.path.join(dest, "ch", c["file"])) for c in old.get("chapters", [])):
            return old
    except (OSError, ValueError):
        pass

    with zipfile.ZipFile(src) as z:
        names = set(z.namelist())
        opf = opf_path(z)
        opf_dir = posixpath.dirname(opf)
        root = ET.fromstring(z.read(opf))
        md = root.find("opf:metadata", NS)
        title = text(md.find("dc:title", NS)) if md is not None else ""
        author = text(md.find("dc:creator", NS)) if md is not None else ""

        manifest = {}
        cover_id = ""
        for it in root.findall("opf:manifest/opf:item", NS):
            href = posixpath.normpath(posixpath.join(opf_dir, unquote(it.get("href") or "")))
            manifest[it.get("id")] = {"href": href, "type": it.get("media-type") or "",
                                      "props": it.get("properties") or ""}
            if "cover-image" in (it.get("properties") or ""):
                cover_id = it.get("id")
        if not cover_id and md is not None:
            for m in md.findall("opf:meta", NS):
                if m.get("name") == "cover":
                    cover_id = m.get("content") or ""

        spine = [manifest[i.get("idref")]["href"] for i in root.findall("opf:spine/opf:itemref", NS)
                 if i.get("idref") in manifest and i.get("linear") != "no"]
        index = {h: n for n, h in enumerate(spine)}

        # pictures: extracted once, by their path in the book
        img_dir = os.path.join(dest, "img")

        def extract(path):
            if path not in names:
                return ""
            out = os.path.join(img_dir, path.replace("/", "_"))
            if not os.path.exists(out):
                os.makedirs(img_dir, exist_ok=True)
                with open(out, "wb") as f:
                    f.write(z.read(path))
            return "file://" + out

        cover = ""
        if cover_id in manifest:
            cover = extract(manifest[cover_id]["href"])

        chapters = []
        chap_dir = os.path.join(dest, "ch")
        os.makedirs(chap_dir, exist_ok=True)
        for n, href in enumerate(spine):
            if href not in names:
                continue
            base = posixpath.dirname(href)

            def resolve_img(s, base=base):
                if not s or s.startswith(("http:", "https:", "data:")):
                    return ""
                return extract(posixpath.normpath(posixpath.join(base, unquote(urldefrag(s)[0]))))

            def resolve_link(s, base=base):
                if s.startswith(("http:", "https:", "mailto:")):
                    return s
                path, frag = urldefrag(s)
                target = posixpath.normpath(posixpath.join(base, unquote(path))) if path else href
                if target not in index:
                    return ""
                return "ch:%d%s" % (index[target], "#" + frag if frag else "")

            raw = z.read(href).decode("utf-8", "replace")
            rw = Rewriter(base, resolve_img, resolve_link)
            rw.feed(raw)
            body = rw.result()
            m = re.search(r"<title>(.*?)</title>", raw, re.S | re.I)
            ctitle = html.unescape(re.sub(r"<[^>]+>", "", m.group(1))).strip() if m else ""
            name = "%04d.html" % n
            with open(os.path.join(chap_dir, name), "w") as f:
                f.write(body)
            chapters.append({"file": name, "title": ctitle, "words": rw.words, "spine": n})

        # the contents: EPUB 3's nav, else EPUB 2's NCX
        toc = []
        nav = next((v for v in manifest.values() if "nav" in v["props"].split()), None)
        if nav and nav["href"] in names:
            nroot = ET.fromstring(z.read(nav["href"]))
            nbase = posixpath.dirname(nav["href"])
            tocnav = None
            for el in nroot.iter("{%s}nav" % NS["xhtml"]):
                if el.get("{%s}type" % NS["epub"]) == "toc":
                    tocnav = el
                    break
            if tocnav is not None:
                def walk(ol, depth):
                    for li in ol.findall("xhtml:li", NS):
                        a = li.find("xhtml:a", NS)
                        if a is not None:
                            path, frag = urldefrag(a.get("href") or "")
                            target = posixpath.normpath(posixpath.join(nbase, unquote(path)))
                            if target in index:
                                toc.append({"label": text(a), "chapter": index[target], "anchor": frag, "depth": depth})
                        sub = li.find("xhtml:ol", NS)
                        if sub is not None:
                            walk(sub, depth + 1)
                ol = tocnav.find("xhtml:ol", NS)
                if ol is not None:
                    walk(ol, 0)
        if not toc:
            ncx = next((v for v in manifest.values() if v["type"] == "application/x-dtbncx+xml"), None)
            if ncx and ncx["href"] in names:
                nroot = ET.fromstring(z.read(ncx["href"]))
                nbase = posixpath.dirname(ncx["href"])

                def walkp(parent, depth):
                    for np in parent.findall("ncx:navPoint", NS):
                        label = text(np.find("ncx:navLabel/ncx:text", NS))
                        content = np.find("ncx:content", NS)
                        if content is not None:
                            path, frag = urldefrag(content.get("src") or "")
                            target = posixpath.normpath(posixpath.join(nbase, unquote(path)))
                            if target in index:
                                toc.append({"label": label, "chapter": index[target], "anchor": frag, "depth": depth})
                        walkp(np, depth + 1)
                nm = nroot.find("ncx:navMap", NS)
                if nm is not None:
                    walkp(nm, 0)
        # chapters named as the contents name them (what the reader sees in
        # the sidebar); their own <title> only where the contents say nothing
        # and it is not just the book's name again
        for c in chapters:
            hit = next((t for t in toc if t["chapter"] == c["spine"] and not t["anchor"]), None) \
                or next((t for t in toc if t["chapter"] == c["spine"]), None)
            if hit and hit["label"]:
                c["title"] = hit["label"]
            elif c["title"].lower() == (title or "").lower():
                c["title"] = ""

    book = {"stamp": stamp, "title": title, "author": author, "cover": cover,
            "dir": dest, "chapters": chapters, "toc": toc}
    with open(meta_path + ".part", "w") as f:
        json.dump(book, f)
    os.replace(meta_path + ".part", meta_path)
    return book


# ── A TEXT, OR MARKDOWN ─────────────────────────────────────────────────

def inline_md(t):
    """Markdown's inline marks, on text already escaped."""
    t = re.sub(r"`([^`]+)`", r"<code>\1</code>", t)
    t = re.sub(r"!\[([^\]]*)\]\(([^)\s]+)[^)]*\)", r"\1", t)
    t = re.sub(r"\[([^\]]+)\]\(((?:https?|mailto):[^)\s]+)[^)]*\)", r'<a href="\2">\1</a>', t)
    t = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", t)
    t = re.sub(r"(\*\*|__)(?=\S)(.+?)(?<=\S)\1", r"<strong>\2</strong>", t)
    t = re.sub(r"(?<![\w*])\*(?=\S)(.+?)(?<=\S)\*(?!\*)", r"<em>\1</em>", t)
    t = re.sub(r"(?<![\w_])_(?=\S)(.+?)(?<=\S)_(?![\w_])", r"<em>\1</em>", t)
    t = re.sub(r"~~(.+?)~~", r"<s>\1</s>", t)
    return t


def md_blocks(src):
    """Markdown → [(level, heading) | (0, html)]: the blocks Qt can set."""
    out = []
    lines = src.split("\n")
    para, i = [], 0

    def flush():
        if para:
            out.append((0, "<p>%s</p>" % inline_md(html.escape(" ".join(para), quote=False))))
            para.clear()
    while i < len(lines):
        ln = lines[i]
        fence = re.match(r"^\s*(```|~~~)", ln)
        if fence:
            flush()
            code = []
            i += 1
            while i < len(lines) and not lines[i].strip().startswith(fence.group(1)):
                code.append(lines[i])
                i += 1
            out.append((0, "<pre>%s</pre>" % html.escape("\n".join(code), quote=False)))
            i += 1
            continue
        h = re.match(r"^(#{1,6})\s+(.*?)\s*#*\s*$", ln)
        if h:
            flush()
            out.append((len(h.group(1)), h.group(2)))
            i += 1
            continue
        if re.match(r"^\s*([-*_])(\s*\1){2,}\s*$", ln):
            flush()
            out.append((0, "<hr>"))
            i += 1
            continue
        if ln.startswith(">"):
            flush()
            q = []
            while i < len(lines) and lines[i].startswith(">"):
                q.append(lines[i].lstrip(">").strip())
                i += 1
            out.append((0, "<blockquote>%s</blockquote>" % inline_md(html.escape(" ".join(q), quote=False))))
            continue
        li = re.match(r"^\s*([-*+]|\d+[.)])\s+(.*)", ln)
        if li:
            flush()
            tag = "ol" if li.group(1)[0].isdigit() else "ul"
            items = []
            while i < len(lines):
                m = re.match(r"^\s*([-*+]|\d+[.)])\s+(.*)", lines[i])
                if m:
                    items.append(m.group(2))
                elif lines[i].strip() and items and lines[i].startswith(("  ", "\t")):
                    items[-1] += " " + lines[i].strip()
                else:
                    break
                i += 1
            out.append((0, "<%s>%s</%s>" % (tag, "".join("<li>%s</li>" % inline_md(html.escape(t, quote=False))
                                                          for t in items), tag)))
            continue
        if not ln.strip():
            flush()
        else:
            para.append(ln.strip())
        i += 1
    flush()
    return out


CHAPTER_LINE = re.compile(r"^\s*(chapter|part|book|act|prologue|epilogue)\b[\w .:'-]{0,60}$", re.I)


def text_book(src, dest):
    src, dest = os.path.abspath(src), os.path.abspath(dest)
    os.makedirs(os.path.join(dest, "ch"), exist_ok=True)
    stamp = "t%d:%d:%d" % (VERSION, os.path.getmtime(src), os.path.getsize(src))
    meta_path = os.path.join(dest, "book.json")
    try:
        with open(meta_path) as f:
            old = json.load(f)
        if old.get("stamp") == stamp and all(
                os.path.exists(os.path.join(dest, "ch", c["file"])) for c in old.get("chapters", [])):
            return old
    except (OSError, ValueError):
        pass
    with open(src, "rb") as f:
        raw = f.read()
    try:
        body = raw.decode("utf-8")
    except UnicodeDecodeError:
        body = raw.decode("latin-1")
    body = body.replace("\r\n", "\n").replace("\r", "\n")
    name = os.path.splitext(os.path.basename(src))[0]
    title = name
    parts = []  # [(title, [html])]
    if src.lower().endswith((".md", ".markdown")):
        blocks = md_blocks(body)
        heads = [b for b in blocks if b[0] in (1, 2)]
        if heads and heads[0][0] == 1 and sum(1 for b in blocks if b[0] == 1) == 1:
            title = re.sub(r"<[^>]+>", "", inline_md(html.escape(heads[0][1], quote=False)))
        split = len(heads) >= 2
        cur = ("", [])
        for lv, h in blocks:
            if lv:
                head = inline_md(html.escape(h, quote=False))
                if split and lv <= 2 and cur[1]:
                    parts.append(cur)
                    cur = ("", [])
                if split and lv <= 2 and not cur[0]:
                    cur = (html.unescape(re.sub(r"<[^>]+>", "", head)), cur[1])
                cur[1].append("<h%d>%s</h%d>" % (min(lv, 3), head, min(lv, 3)))
            else:
                cur[1].append(h)
        if cur[1]:
            parts.append(cur)
    else:
        paras = [p.strip() for p in re.split(r"\n\s*\n", body) if p.strip()]
        marked = any(CHAPTER_LINE.match(p) for p in paras)
        cur, words = ("", []), 0
        for p in paras:
            if marked and CHAPTER_LINE.match(p):
                if cur[1]:
                    parts.append(cur)
                cur, words = (p, ["<h2>%s</h2>" % html.escape(p, quote=False)]), 0
                continue
            if not marked and words > 4000:
                parts.append(cur)
                cur, words = ("", []), 0
            words += len(p.split())
            cur[1].append("<p>%s</p>" % html.escape(re.sub(r"\s*\n\s*", " ", p), quote=False))
        if cur[1]:
            parts.append(cur)
    if not parts:
        parts = [("", ["<p></p>"])]
    chapters, toc = [], []
    for n, (ct, hs) in enumerate(parts):
        fname = "%04d.html" % n
        html_text = "".join(hs)
        with open(os.path.join(dest, "ch", fname), "w") as f:
            f.write(html_text)
        words = len(re.sub(r"<[^>]+>", " ", html_text).split())
        chapters.append({"file": fname, "title": ct, "words": words, "spine": n})
        if ct:
            toc.append({"label": ct, "chapter": n, "anchor": "", "depth": 0})
    book = {"stamp": stamp, "title": title, "author": "", "cover": "", "dir": dest,
            "chapters": chapters, "toc": toc}
    with open(meta_path + ".part", "w") as f:
        json.dump(book, f)
    os.replace(meta_path + ".part", meta_path)
    return book


def find(dest, words):
    """Every chapter's hits for the words, a snippet around each."""
    with open(os.path.join(dest, "book.json")) as f:
        book = json.load(f)
    q = words.strip().lower()
    out = []
    if not q:
        return out
    for n, c in enumerate(book["chapters"]):
        try:
            with open(os.path.join(dest, "ch", c["file"])) as f:
                plain = html.unescape(re.sub(r"<[^>]+>", " ", f.read()))
        except OSError:
            continue
        plain = re.sub(r"\s+", " ", plain)
        low = plain.lower()
        at = low.find(q)
        while at >= 0 and len(out) < 500:
            a, b = max(0, at - 50), min(len(plain), at + len(q) + 70)
            out.append({"chapter": n, "at": at, "snippet": ("…" if a > 0 else "") + plain[a:b].strip() + ("…" if b < len(plain) else ""),
                        "match": plain[at:at + len(q)]})
            at = low.find(q, at + len(q))
    return out


def main():
    try:
        if len(sys.argv) >= 4 and sys.argv[1] == "open":
            print(json.dumps(open_book(sys.argv[2], sys.argv[3])))
        elif len(sys.argv) >= 4 and sys.argv[1] == "text":
            print(json.dumps(text_book(sys.argv[2], sys.argv[3])))
        elif len(sys.argv) >= 4 and sys.argv[1] == "find":
            print(json.dumps(find(sys.argv[2], " ".join(sys.argv[3:]))))
        else:
            print(json.dumps({"error": "usage: epub.py open|text <book> <dir> | find <dir> <words>"}))
            sys.exit(2)
    except (zipfile.BadZipFile, KeyError, ValueError, ET.ParseError, OSError, UnicodeError) as e:
        print(json.dumps({"error": "%s: %s" % (type(e).__name__, e)}))
        sys.exit(1)


if __name__ == "__main__":
    main()

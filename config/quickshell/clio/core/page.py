# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# A NOTE AS A PAGE — every note and journal entry is kept as one HTML file
# (user, 2026-10-14: "more freedom, especially with portability"). Opened in
# a browser it reads as the note: headings, lists, ticked boxes, pictures
# from ../Attachments, tables. Read back by Clio it is the same note,
# exactly:
#
#   <head>   <meta name="clio-<field>" content="<json>"> — every field of
#            the note but its blocks (id, kind, dates, pinned, the container,
#            the mood, a locked note's sealed text …)
#   <body>   one element per block, `data-k` its kind and `data-clio` (json)
#            whatever else it has (level, tick, src, width, alignment …);
#            a block's words are its inner HTML, as the editor keeps them
#
# A page made elsewhere (no clio-id) is read as well as it can be: its
# headings, paragraphs, list items and preformatted text become blocks, and
# its name and file times the rest. It is written as Clio's own page on its
# first save.

import hashlib
import html
import json
import os
import re
import time

TEXT = {"title": "h1", "heading": "h2", "subheading": "h3", "body": "p", "quote": "blockquote", "mono": "pre"}
LISTS = {"bullet": "ul", "dash": "ul", "number": "ol", "check": "ul"}
MEDIA = {"image", "sketch", "file"}

STYLE = """
body { font: 16px/1.5 system-ui, sans-serif; max-width: 46rem; margin: 2.5rem auto; padding: 0 1.25rem; color: #222; background: #fdfcfa; }
@media (prefers-color-scheme: dark) { body { color: #e6e6e6; background: #1c1c1e; } a { color: #6cc4d8; } }
h1 { font-size: 1.75em; margin: .4em 0; } h2 { font-size: 1.4em; margin: .5em 0 .3em; } h3 { font-size: 1.15em; margin: .5em 0 .2em; }
p { margin: .15em 0; min-height: 1.5em; }
pre { padding: .6em .8em; border-radius: 6px; background: rgba(127,127,127,.12); white-space: pre-wrap; }
blockquote { margin: .3em 0; padding-left: .9em; border-left: 3px solid rgba(127,127,127,.5); opacity: .85; }
ul, ol { margin: .15em 0; padding-left: 1.6em; }
ul.dash { list-style-type: "\\2013  "; }
ul.check { list-style: none; padding-left: .2em; }
li.check::before { content: "\\25CB"; display: inline-block; width: 1.4em; }
li.check.done::before { content: "\\25C9"; }
li.check.done { opacity: .6; }
figure { margin: .5em 0; display: inline-block; vertical-align: top; }
figure img { max-width: 100%; border-radius: 8px; }
table { border-collapse: collapse; margin: .5em 0; } td { border: 1px solid rgba(127,127,127,.4); padding: .3em .6em; vertical-align: top; }
hr { border: 0; border-top: 1px solid rgba(127,127,127,.4); margin: 1em 0; }
.clio-locked { opacity: .6; font-style: italic; }
""".strip()


def esc(s):
    return html.escape(str(s), quote=True)


def plain(h):
    # a block's words without their markup
    s = re.sub(r"<br\s*/?>", "\n", str(h or ""), flags=re.I)
    return html.unescape(re.sub(r"<[^>]+>", "", s))


def title_of(note):
    # what the note is called: its own name, the first line of its first
    # words, or (locked) the title kept in the clear
    if note.get("name"):
        return str(note["name"]).strip()
    for b in note.get("blocks") or []:
        if not isinstance(b, dict) or b.get("k") not in TEXT and b.get("k") not in LISTS:
            continue
        t = (b.get("h") or "") if b.get("k") == "mono" else plain(b.get("h"))
        t = t.strip().split("\n")[0].strip()
        if t:
            return t
    return str(note.get("title") or "").strip()


def file_title(note):
    # the file's name, without its extension: the title made safe for any
    # file system; an entry starts with its day, so a journal lists in order
    t = re.sub(r'[\\/:*?"<>|\x00-\x1f]+', " ", title_of(note))
    t = re.sub(r"\s+", " ", t).strip().lstrip(".")[:80].strip()
    if note.get("kind") == "entry":
        ms = note.get("date") or note.get("created") or 0
        if not ms:
            return "Entry " + t if t else "Entry"
        # untitled, its time as well: two on one day apart, and in order
        return time.strftime("%Y-%m-%d" if t else "%Y-%m-%d %H.%M", time.localtime(ms / 1000)) + (" " + t if t else "")
    return t or "New Note"


def _attrs(b, skip):
    extra = {k: v for k, v in b.items() if k not in skip}
    return ' data-clio="%s"' % esc(json.dumps(extra, ensure_ascii=False, separators=(",", ":"))) if extra else ""


def _style(b):
    out = []
    if b.get("align"):
        out.append("text-align: " + str(b["align"]))
    if b.get("l"):
        out.append("margin-left: %.1fem" % (1.6 * int(b["l"])))
    return ' style="%s"' % "; ".join(out) if out else ""


def body_of(blocks):
    out, open_list = [], None
    for b in blocks or []:
        if not isinstance(b, dict):
            continue
        k = str(b.get("k") or "body")
        if k in LISTS:
            want = (LISTS[k], k)
            if open_list != want:
                if open_list:
                    out.append("</%s>" % open_list[0])
                out.append('<%s class="%s">' % want)
                open_list = want
            cls = ' class="check%s"' % (" done" if b.get("c") else "") if k == "check" else ""
            out.append('<li data-k="%s"%s%s%s>%s</li>' % (k, cls, _attrs(b, ("k", "h")), _style(b), b.get("h") or ""))
            continue
        if open_list:
            out.append("</%s>" % open_list[0])
            open_list = None
        if k == "mono":
            out.append('<pre data-k="mono"%s>%s</pre>' % (_attrs(b, ("k", "h")), html.escape(str(b.get("h") or ""), quote=False)))
        elif k in TEXT:
            tag = TEXT[k]
            out.append('<%s data-k="%s"%s%s>%s</%s>' % (tag, k, _attrs(b, ("k", "h")), _style(b), b.get("h") or "", tag))
        elif k in ("image", "sketch"):
            src = "../Attachments/" + str(b.get("src") or "")
            w = b.get("w")
            size = ' style="width: %d%%"' % round(100 * float(w)) if w else ""
            out.append('<figure data-k="%s"%s%s><img src="%s" alt="%s"></figure>'
                       % (k, _attrs(b, ("k",)), size, esc(src), esc(b.get("name") or "")))
        elif k == "file":
            out.append('<p data-k="file"%s%s><a href="%s">%s</a></p>'
                       % (_attrs(b, ("k",)), _style(b), esc("../Attachments/" + str(b.get("src") or "")), esc(b.get("name") or "file")))
        elif k == "table":
            rows = "".join("<tr>" + "".join("<td>%s</td>" % c for c in row) + "</tr>" for row in b.get("rows") or [])
            out.append('<table data-k="table"%s>%s</table>' % (_attrs(b, ("k", "h", "rows")), rows))
        elif k == "rule":
            out.append('<hr data-k="rule"%s>' % _attrs(b, ("k", "h")))
    if open_list:
        out.append("</%s>" % open_list[0])
    return "\n".join(out)


def page_of(note):
    # the note as its page
    head = ['<meta name="clio-%s" content="%s">' % (k, esc(json.dumps(v, ensure_ascii=False, separators=(",", ":"))))
            for k, v in note.items() if k != "blocks" and not k.startswith("_")]
    if note.get("sealed"):
        body = '<p class="clio-locked">Locked in Clio — opened there with the Clio password.</p>'
    else:
        body = body_of(note.get("blocks"))
    return ("<!DOCTYPE html>\n<html>\n<head>\n<meta charset=\"utf-8\">\n"
            '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
            "<title>%s</title>\n<meta name=\"generator\" content=\"Clio\">\n%s\n<style>\n%s\n</style>\n</head>\n"
            "<body>\n<article>\n%s\n</article>\n</body>\n</html>\n") % (esc(title_of(note) or file_title(note)), "\n".join(head), STYLE, body)


# ── READING ──────────────────────────────────────────────────────────────
META_RE = re.compile(r'<meta\s+name="clio-([\w-]+)"\s+content="([^"]*)"\s*/?>', re.I)
BLOCK_RE = re.compile(r'<(h1|h2|h3|p|blockquote|pre|li|figure|table|hr)\b([^>]*?)\sdata-k="(\w+)"([^>]*)>(?:(.*?)</\1>)?', re.S | re.I)
CLIO_RE = re.compile(r'data-clio="([^"]*)"')
ROW_RE = re.compile(r"<tr\b[^>]*>(.*?)</tr>", re.S | re.I)
CELL_RE = re.compile(r"<t[dh]\b[^>]*>(.*?)</t[dh]>", re.S | re.I)


def blocks_of(body):
    out = []
    for m in BLOCK_RE.finditer(body):
        tag, before, k, after, inner = m.group(1).lower(), m.group(2), m.group(3), m.group(4), m.group(5) or ""
        c = CLIO_RE.search(before + after)
        b = {"k": k}
        if c:
            try:
                extra = json.loads(html.unescape(c.group(1)))
                if isinstance(extra, dict):
                    b.update(extra)
            except ValueError:
                pass
        if k == "mono":
            b["h"] = html.unescape(inner)
        elif k == "table":
            b["rows"] = [[cell for cell in CELL_RE.findall(r)] for r in ROW_RE.findall(inner)] or [[""]]
            b.setdefault("h", "")
        elif k in MEDIA or k == "rule":
            b.setdefault("h", "")
        else:
            b["h"] = inner
        out.append(b)
    return out


# a page from somewhere else: its plain structure, as blocks
FOREIGN_RE = re.compile(r"<(h1|h2|h3|h4|h5|h6|p|li|pre|blockquote)\b[^>]*>(.*?)</\1>", re.S | re.I)
FOREIGN_KIND = {"h1": "title", "h2": "heading", "h3": "subheading", "h4": "subheading", "h5": "subheading", "h6": "subheading",
                "p": "body", "li": "bullet", "pre": "mono", "blockquote": "quote"}
KEEP_INLINE = re.compile(r"</?(?!(?:b|i|u|s|em|strong|a|br|span)\b)[a-z][^>]*>", re.I)


def foreign_blocks(text):
    body = re.search(r"<body\b[^>]*>(.*)</body>", text, re.S | re.I)
    body = body.group(1) if body else text
    body = re.sub(r"<(script|style)\b.*?</\1>", "", body, flags=re.S | re.I)
    out = []
    for m in FOREIGN_RE.finditer(body):
        k = FOREIGN_KIND[m.group(1).lower()]
        inner = m.group(2)
        if k == "mono":
            out.append({"k": k, "h": plain(inner)})
        else:
            h = KEEP_INLINE.sub("", inner).strip()
            if h:
                out.append({"k": k, "h": h})
    if not out:
        for line in plain(body).split("\n"):
            if line.strip():
                out.append({"k": "body", "h": html.escape(line.strip(), quote=False)})
    return out


def note_of(text, path, kind="note"):
    # a page read back: Clio's own exactly, anything else as well as can be
    head = text.split("</head>", 1)[0] if "</head>" in text else ""
    note = {}
    for m in META_RE.finditer(head):
        try:
            note[m.group(1)] = json.loads(html.unescape(m.group(2)))
        except ValueError:
            pass
    body = text.split("<body", 1)[1] if "<body" in text else text
    if note.get("id"):
        if not note.get("sealed"):
            note["blocks"] = blocks_of(body)
        return note
    # made elsewhere: named by its path (the same file, the same note)
    st = os.stat(path)
    title = re.search(r"<title>(.*?)</title>", head or text, re.S | re.I)
    blocks = foreign_blocks(text)
    if title and plain(title.group(1)).strip() and not (blocks and blocks[0]["k"] == "title"):
        blocks.insert(0, {"k": "title", "h": html.escape(plain(title.group(1)).strip(), quote=False)})
    ms = int(st.st_mtime * 1000)
    out = {"v": 1, "id": "h" + hashlib.sha1(os.path.realpath(path).encode()).hexdigest()[:11], "kind": kind,
           "created": ms, "modified": ms, "blocks": blocks}
    if kind == "entry":
        out["date"] = ms
    return out

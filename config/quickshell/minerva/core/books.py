#!/usr/bin/env python3
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# minerva's other helpers: comics, and the directories it watches.
#
#   books.py comic <book.cbz|.cbr> <cache dir>  → { title, pages: [{ file, width, height }] }
#   books.py scan <dir>…                        → [path…], every book under them
#
# A comic is an archive of pictures, read in their names' natural order
# (page 2 before page 10). A CBZ is a zip; a CBR a RAR, which bsdtar
# (libarchive, in Arch's base) reads, unrar where it is not. The pictures
# land in the cache dir with their sizes measured from their own headers,
# so the reader lays every page out before one is drawn. A second open of
# an unchanged book reads comic.json back.
#
# scan walks each directory (four deep, hidden ones skipped) for what the
# reader opens: PDFs, EPUBs and comics — not plain texts, which a directory
# of notes would bury the library in.
#
# Standard library only.

import json
import os
import re
import shutil
import struct
import subprocess
import sys
import zipfile

VERSION = 1
PICTURES = (".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp")
BOOKS = (".pdf", ".epub", ".cbz", ".cbr")


def natural(s):
    return [int(t) if t.isdigit() else t.lower() for t in re.split(r"(\d+)", s)]


def size_of(path):
    """A picture's (width, height) from its header; (0, 0) when unknown."""
    try:
        with open(path, "rb") as f:
            head = f.read(64 * 1024)
    except OSError:
        return 0, 0
    if head[:8] == b"\x89PNG\r\n\x1a\n" and len(head) >= 24:
        return struct.unpack(">II", head[16:24])
    if head[:6] in (b"GIF87a", b"GIF89a"):
        return struct.unpack("<HH", head[6:10])
    if head[:2] == b"BM" and len(head) >= 26:
        w, h = struct.unpack("<ii", head[18:26])
        return abs(w), abs(h)
    if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
        kind = head[12:16]
        if kind == b"VP8 " and len(head) >= 30:
            w, h = struct.unpack("<HH", head[26:30])
            return w & 0x3FFF, h & 0x3FFF
        if kind == b"VP8L" and len(head) >= 25:
            b = head[21:25]
            return 1 + (((b[1] & 0x3F) << 8) | b[0]), 1 + (((b[3] & 0xF) << 10) | (b[2] << 2) | ((b[1] & 0xC0) >> 6))
        if kind == b"VP8X" and len(head) >= 30:
            return 1 + int.from_bytes(head[24:27], "little"), 1 + int.from_bytes(head[27:30], "little")
    if head[:2] == b"\xff\xd8":
        i = 2
        while i + 9 < len(head):
            if head[i] != 0xFF:
                i += 1
                continue
            marker = head[i + 1]
            if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                h, w = struct.unpack(">HH", head[i + 5:i + 9])
                return w, h
            if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7:
                i += 2
                continue
            seg = struct.unpack(">H", head[i + 2:i + 4])[0]
            i += 2 + seg
    return 0, 0


def free_name(d, name):
    """`name` in directory `d`, or "name-2.ext", "name-3.ext"… when a page
    is already there: flattening folders into names can make two pages one
    ("a/1.jpg" and "a_1.jpg"), and the second used to replace the first."""
    stem, ext = os.path.splitext(name)
    out, n = name, 2
    while os.path.exists(os.path.join(d, out)):
        out, n = "%s-%d%s" % (stem, n, ext), n + 1
    return os.path.join(d, out)


def comic(src, dest):
    src, dest = os.path.abspath(src), os.path.abspath(dest)
    stamp = "%d:%d:%d" % (VERSION, os.path.getmtime(src), os.path.getsize(src))
    meta = os.path.join(dest, "comic.json")
    try:
        with open(meta) as f:
            old = json.load(f)
        if old.get("stamp") == stamp and all(os.path.exists(p["file"]) for p in old.get("pages", [])):
            return old
    except (OSError, ValueError):
        pass
    pages_dir = os.path.join(dest, "pages")
    shutil.rmtree(pages_dir, ignore_errors=True)
    os.makedirs(pages_dir, exist_ok=True)
    if zipfile.is_zipfile(src):
        with zipfile.ZipFile(src) as z:
            for n in z.namelist():
                if n.lower().endswith(PICTURES) and not os.path.basename(n).startswith("."):
                    out = free_name(pages_dir, n.replace("/", "_").lstrip("._"))
                    with open(out, "wb") as f:
                        f.write(z.read(n))
    else:
        tool = shutil.which("bsdtar")
        cmd = [tool, "-xf", src, "-C", pages_dir] if tool else None
        if not cmd and shutil.which("unrar"):
            cmd = ["unrar", "x", "-inul", "-o+", src, pages_dir + "/"]
        if not cmd:
            raise ValueError("a CBR needs bsdtar (libarchive) or unrar")
        r = subprocess.run(cmd, capture_output=True, timeout=300)
        if r.returncode != 0:
            raise ValueError("the archive could not be opened")
        # flattened, as a zip's are: the pages' names in one directory
        for root, dirs, files in os.walk(pages_dir):
            if root == pages_dir:
                continue
            rel = os.path.relpath(root, pages_dir).replace(os.sep, "_")
            for fn in files:
                os.replace(os.path.join(root, fn), free_name(pages_dir, rel + "_" + fn))
        for root, dirs, files in os.walk(pages_dir, topdown=False):
            if root != pages_dir:
                shutil.rmtree(root, ignore_errors=True)
    pages = []
    for fn in sorted(os.listdir(pages_dir), key=natural):
        p = os.path.join(pages_dir, fn)
        if not fn.lower().endswith(PICTURES):
            continue
        w, h = size_of(p)
        pages.append({"file": p, "width": w or 1000, "height": h or 1500})
    if not pages:
        raise ValueError("there are no pictures in this comic")
    title = os.path.splitext(os.path.basename(src))[0]
    book = {"stamp": stamp, "title": title, "pages": pages}
    with open(meta + ".part", "w") as f:
        json.dump(book, f)
    os.replace(meta + ".part", meta)
    return book


def scan(dirs):
    out, seen = [], set()
    for d in dirs:
        d = os.path.abspath(os.path.expanduser(d))
        base = d.rstrip(os.sep).count(os.sep)
        for root, sub, files in os.walk(d):
            sub[:] = [s for s in sub if not s.startswith(".")] if root.count(os.sep) - base < 4 else []
            for fn in files:
                if fn.lower().endswith(BOOKS) and not fn.startswith("."):
                    p = os.path.join(root, fn)
                    if p not in seen:
                        seen.add(p)
                        out.append(p)
            if len(out) >= 2000:
                return out
    return out


def main():
    try:
        if len(sys.argv) >= 4 and sys.argv[1] == "comic":
            print(json.dumps(comic(sys.argv[2], sys.argv[3])))
        elif len(sys.argv) >= 2 and sys.argv[1] == "scan":
            print(json.dumps(scan(sys.argv[2:])))
        else:
            print(json.dumps({"error": "usage: books.py comic <book> <dir> | scan <dir>…"}))
            sys.exit(2)
    except (zipfile.BadZipFile, ValueError, OSError, subprocess.SubprocessError) as e:
        print(json.dumps({"error": "%s" % e}))
        sys.exit(1)


if __name__ == "__main__":
    main()

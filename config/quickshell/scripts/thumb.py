#!/usr/bin/env python3
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# THE THUMBNAILS THAT ARE NOT ONE magick CALL. morpheus/thumbs.js makes the
# ordinary ones inline; this is what it hands the two kinds that need more:
#
#   f  a picture Qt cannot open (psd, xcf, kra, raw...). Transparency is laid
#      over a checkerboard rather than refused: generate() skips an image with
#      alpha because Qt can show the original instead, and for these it
#      cannot — skipping one meant it never showed at all.
#   d  a document or a container: the first page of a pdf, ai, ps or djvu,
#      the first page of a comic, the cover of an epub.
#
#   thumb.py <kind> <source> <out.jpg> <px>
#
# Writes a JPEG at <out> or nothing. Prints nothing either way — the caller
# reports what exists.

import os
import re
import subprocess
import sys
import zipfile
from urllib.parse import unquote
import posixpath

PICS = (".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".avif", ".jxl")


def ext(path):
    return os.path.splitext(path)[1].lower().lstrip(".")


def natural(name):
    return [int(t) if t.isdigit() else t.lower() for t in re.split(r"(\d+)", name)]


# Everything ends here: whatever came in, as an image file or as bytes on
# stdin, scaled into the box and written as the pool's JPEG. The checkerboard
# goes under anything with alpha — JPEG has none, and flattening onto a flat
# colour would be wrong against one theme or the other.
def finish(src, out, px, data=None):
    cmd = ["magick", src, "-auto-orient", "-thumbnail", f"{px}x{px}",
           "(", "+clone", "-tile", "pattern:checkerboard",
           "-draw", "color 0,0 reset", ")",
           "+swap", "-compose", "over", "-composite",
           "-strip", "-quality", "85", out]
    subprocess.run(cmd, input=data, stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, timeout=60)


def run(cmd):
    r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                       timeout=60)
    return r.stdout if r.returncode == 0 else b""


# ── pages ───────────────────────────────────────────────────────────────
def pdf(src, out, px):
    # An .ai saved by anything since CS is a PDF with extra parts; one that is
    # not simply yields nothing here.
    png = run(["pdftoppm", "-f", "1", "-l", "1", "-singlefile",
               "-scale-to", str(px), "-png", src])
    if png:
        finish("png:-", out, px, png)


def djvu(src, out, px):
    ppm = run(["ddjvu", "-format=ppm", "-page=1", f"-size={px}x{px}",
               "-aspect=yes", src])
    if ppm:
        finish("ppm:-", out, px, ppm)


def postscript(src, out, px):
    # ImageMagick hands this to ghostscript.
    finish(src + "[0]", out, px)


# ── containers ──────────────────────────────────────────────────────────
# Krita and OpenRaster both keep a flattened copy of the canvas at the root
# of the zip, which is the picture — no layers to composite.
def layered(src, out, px):
    try:
        with zipfile.ZipFile(src) as z:
            names = set(z.namelist())
            for want in ("mergedimage.png", "preview.png", "Thumbnails/thumbnail.png"):
                if want in names:
                    finish("png:-", out, px, z.read(want))
                    return
    except (zipfile.BadZipFile, OSError):
        pass


# A comic is pages in an archive, and the first by NATURAL order is the cover:
# page10 does not come before page2.
def comic(src, out, px):
    e = ext(src)
    data = b""
    if e in ("cbz",) and zipfile.is_zipfile(src):
        with zipfile.ZipFile(src) as z:
            pics = sorted((n for n in z.namelist()
                           if n.lower().endswith(PICS) and not n.startswith("__MACOSX")),
                          key=natural)
            if pics:
                data = z.read(pics[0])
    elif e == "cbr":
        names = run(["unrar", "lb", "-inul", src]).decode("utf-8", "replace").splitlines()
        pics = sorted((n for n in names if n.lower().endswith(PICS)), key=natural)
        if pics:
            # -n restricts to the one member; unrar takes the name literally
            data = run(["unrar", "p", "-inul", "-n" + pics[0], src])
    else:  # cb7, cbt — and a .cbz that is secretly a rar
        names = run(["bsdtar", "-tf", src]).decode("utf-8", "replace").splitlines()
        pics = sorted((n for n in names if n.lower().endswith(PICS)), key=natural)
        if pics:
            data = run(["7z", "e", "-so", "-spd", src, pics[0]])
    if data:
        finish("-", out, px, data)


# The cover is whatever the package names as one: an EPUB3 item marked
# cover-image, or the EPUB2 <meta name="cover"> pointing at an item id. Books
# that name neither usually still have an image called cover, and failing that
# the first picture in the book is very nearly always it.
def epub(src, out, px):
    try:
        z = zipfile.ZipFile(src)
    except (zipfile.BadZipFile, OSError):
        return
    with z:
        names = z.namelist()
        href = None
        try:
            container = z.read("META-INF/container.xml").decode("utf-8", "replace")
            m = re.search(r'full-path\s*=\s*"([^"]+)"', container)
            opf_path = m.group(1) if m else None
            opf = z.read(opf_path).decode("utf-8", "replace") if opf_path else ""
        except KeyError:
            opf_path, opf = None, ""

        items = []
        for tag in re.findall(r"<(?:\w+:)?item\b[^>]*>", opf):
            attrs = dict(re.findall(r'([\w:-]+)\s*=\s*"([^"]*)"', tag))
            items.append(attrs)
        for it in items:
            if "cover-image" in it.get("properties", "").split():
                href = it.get("href")
                break
        if not href:
            m = re.search(r'<(?:\w+:)?meta\b[^>]*name\s*=\s*"cover"[^>]*>', opf)
            if m:
                c = re.search(r'content\s*=\s*"([^"]+)"', m.group(0))
                if c:
                    for it in items:
                        if it.get("id") == c.group(1):
                            href = it.get("href")
                            break
        member = None
        if href:
            base = posixpath.dirname(opf_path or "")
            member = posixpath.normpath(posixpath.join(base, unquote(href)))
            if member not in names:
                member = None
        if not member:
            pics = [n for n in names if n.lower().endswith(PICS)]
            covers = [n for n in pics if "cover" in n.lower()]
            member = (covers or pics or [None])[0]
        if member:
            finish("-", out, px, z.read(member))


def main():
    if len(sys.argv) != 5:
        return 2
    kind, src, out, px = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
    e = ext(src)
    try:
        if kind == "f":
            if e in ("kra", "krz", "ora"):
                layered(src, out, px)
            else:
                finish(src + "[0]", out, px)
        elif kind == "d":
            if e in ("pdf", "ai"):
                pdf(src, out, px)
            elif e in ("djvu", "djv"):
                djvu(src, out, px)
            elif e in ("ps", "eps", "epsf", "epsi"):
                postscript(src, out, px)
            elif e in ("cbz", "cbr", "cb7", "cbt"):
                comic(src, out, px)
            elif e == "epub":
                epub(src, out, px)
    except Exception:
        pass
    # never leave half a file for the pool to trust
    if os.path.exists(out) and os.path.getsize(out) == 0:
        os.remove(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())

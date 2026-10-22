#!/usr/bin/env python3
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# tidy.py — what is taking room that could be given back, as JSON on stdout.
#
#   overview          { trash, caches, pkgcache, orphans, journal, downloads }
#     trash           { bytes, items, dir }
#     caches          { bytes, dirs: [{ name, path, bytes }] }   ~/.cache, biggest first
#     pkgcache        { bytes, tool, old: { count, bytes }, gone: { count, bytes } }
#                     old = all but the newest version of each package
#                     (paccache -k1), gone = every version of packages no
#                     longer installed (paccache -uk0); tool false without
#                     pacman-contrib
#     orphans         [{ name, bytes }]   installed as a dependency, needed by nothing
#     journal         { bytes }
#     downloads       { dir, files: [{ path, bytes, mtime }] }  big, or old and not small
#   dupes [DIR…]      [{ bytes, paths: [{ path, mtime }] }]   most room wasted first;
#                     no DIR is the home's own: Downloads, Documents, Pictures,
#                     Videos, Music, Desktop (XDG's names for them)
#   trash PATH…       { moved: [path], failed: [{ path, why }] }   through gio trash
#   delete PATH…      the same, gone for good — only inside the home, never it
#   empty             the trash emptied (gio trash --empty)
#
# Files go to the trash (gio, the freedesktop trash every file manager
# reads) unless `delete` is asked for by name: when the disk is too full for
# the trash to help (2026-10-22, user: "sometimes a user may not have enough
# space in their root drive"), the window asks twice first. The package cache, the
# orphans and the journal are root's — the window hands those to Ceres'
# password card. Standard library only, every command on a timeout.

import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import time

HOME = os.path.expanduser("~")


def run(argv, timeout=30):
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout, p.stderr
    except (OSError, subprocess.TimeoutExpired) as e:
        return -1, "", str(e)


def tree_bytes(path):
    """Room a tree takes on disk (blocks, not apparent size), never following links."""
    total = 0
    stack = [path]
    while stack:
        d = stack.pop()
        try:
            with os.scandir(d) as it:
                for e in it:
                    try:
                        st = e.stat(follow_symlinks=False)
                    except OSError:
                        continue
                    total += st.st_blocks * 512
                    if stat.S_ISDIR(st.st_mode):
                        stack.append(e.path)
        except OSError:
            pass
    return total


def xdg_dir(name, fallback):
    code, out, _ = run(["xdg-user-dir", name], timeout=5)
    p = out.strip() if code == 0 else ""
    return p if p and p != HOME else os.path.join(HOME, fallback)


# "1.20 GiB", "512.00 KiB", "3 B" -> bytes
UNITS = {"B": 1, "KiB": 1024, "MiB": 1024 ** 2, "GiB": 1024 ** 3, "TiB": 1024 ** 4,
         "K": 1024, "M": 1024 ** 2, "G": 1024 ** 3, "T": 1024 ** 4}


def size_words(s):
    m = re.search(r"([\d.]+)\s*([KMGT]?i?B|[KMGT])\b", s)
    if not m:
        return 0
    return int(float(m.group(1)) * UNITS.get(m.group(2), 1))


def trash_info():
    d = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local/share"), "Trash")
    files = os.path.join(d, "files")
    try:
        items = len(os.listdir(files))
    except OSError:
        items = 0
    return {"bytes": tree_bytes(files), "items": items, "dir": files}


def caches():
    root = os.environ.get("XDG_CACHE_HOME") or os.path.join(HOME, ".cache")
    out = []
    try:
        with os.scandir(root) as it:
            for e in it:
                if e.is_symlink():
                    continue
                b = tree_bytes(e.path) if e.is_dir(follow_symlinks=False) else e.stat(follow_symlinks=False).st_blocks * 512
                out.append({"name": e.name, "path": e.path, "bytes": b})
    except OSError:
        pass
    out.sort(key=lambda x: -x["bytes"])
    return {"bytes": sum(x["bytes"] for x in out), "dirs": out[:40]}


# "==> finished dry run: 12 candidates (disk space saved: 1.20 GiB)"
def paccache_dry(args):
    code, out, err = run(["paccache", "-d"] + args, timeout=60)
    text = out + err
    m = re.search(r"(\d+)\s+candidates?.*?saved:\s*([^)]*)\)", text)
    if m:
        return {"count": int(m.group(1)), "bytes": size_words(m.group(2))}
    return {"count": 0, "bytes": 0}


def pkgcache():
    have = shutil.which("paccache") is not None
    res = {"bytes": tree_bytes("/var/cache/pacman/pkg"), "tool": have,
           "old": {"count": 0, "bytes": 0}, "gone": {"count": 0, "bytes": 0}}
    if have:
        res["old"] = paccache_dry(["-k1"])
        res["gone"] = paccache_dry(["-uk0"])
    return res


def orphans():
    code, out, _ = run(["pacman", "-Qdtq"])
    names = [n for n in out.split() if n]
    if not names:
        return []
    code, info, _ = run(["pacman", "-Qi"] + names)
    sizes = {}
    cur = None
    for line in info.splitlines():
        if line.startswith("Name"):
            cur = line.split(":", 1)[1].strip()
        elif line.startswith("Installed Size") and cur:
            sizes[cur] = size_words(line.split(":", 1)[1])
    out = [{"name": n, "bytes": sizes.get(n, 0)} for n in names]
    out.sort(key=lambda x: -x["bytes"])
    return out


def journal():
    code, out, err = run(["journalctl", "--disk-usage"], timeout=15)
    return {"bytes": size_words(out + err)}


BIG = 100 * 1024 ** 2          # big: this or more, any age
OLD_DAYS = 180                 # old: untouched this long …
OLD_MIN = 10 * 1024 ** 2       # … and at least this


def downloads():
    d = xdg_dir("DOWNLOAD", "Downloads")
    now = time.time()
    out = []
    for root, dirs, files in os.walk(d):
        dirs[:] = [x for x in dirs if not x.startswith(".")]
        for f in files:
            p = os.path.join(root, f)
            try:
                st = os.stat(p, follow_symlinks=False)
            except OSError:
                continue
            if not stat.S_ISREG(st.st_mode):
                continue
            old = now - st.st_mtime > OLD_DAYS * 86400
            if st.st_size >= BIG or (old and st.st_size >= OLD_MIN):
                out.append({"path": p, "bytes": st.st_size, "mtime": int(st.st_mtime)})
    out.sort(key=lambda x: -x["bytes"])
    return {"dir": d, "files": out[:200]}


DUPE_MIN = 1024 * 1024         # smaller files are not worth the time


def digest(path, head=None):
    h = hashlib.blake2b(digest_size=20)
    try:
        with open(path, "rb") as f:
            if head:
                h.update(f.read(head))
            else:
                for chunk in iter(lambda: f.read(1 << 20), b""):
                    h.update(chunk)
    except OSError:
        return None
    return h.hexdigest()


def dupes(dirs):
    by_size = {}
    seen = set()
    for d in dirs:
        for root, sub, files in os.walk(d):
            sub[:] = [x for x in sub if not x.startswith(".")]
            for f in files:
                p = os.path.join(root, f)
                try:
                    st = os.stat(p, follow_symlinks=False)
                except OSError:
                    continue
                if not stat.S_ISREG(st.st_mode) or st.st_size < DUPE_MIN:
                    continue
                # one file reached twice (a directory inside another named)
                # or hard links are the same bytes on disk, not a copy
                key = (st.st_dev, st.st_ino)
                if key in seen:
                    continue
                seen.add(key)
                by_size.setdefault(st.st_size, []).append((p, int(st.st_mtime)))
    groups = []
    for size, items in by_size.items():
        if len(items) < 2:
            continue
        # the first 64 KiB, then all of it, only where the first agrees
        heads = {}
        for p, m in items:
            k = digest(p, 65536)
            if k:
                heads.setdefault(k, []).append((p, m))
        for same in heads.values():
            if len(same) < 2:
                continue
            fulls = {}
            for p, m in same:
                k = digest(p)
                if k:
                    fulls.setdefault(k, []).append((p, m))
            for g in fulls.values():
                if len(g) > 1:
                    g.sort(key=lambda x: x[1])
                    groups.append({"bytes": size, "paths": [{"path": p, "mtime": m} for p, m in g]})
    groups.sort(key=lambda g: -g["bytes"] * (len(g["paths"]) - 1))
    return groups


def trash(paths):
    moved, failed = [], []
    for p in paths:
        code, _, err = run(["gio", "trash", "--", p], timeout=60)
        if code == 0:
            moved.append(p)
        else:
            failed.append({"path": p, "why": (err.strip().splitlines() or ["gio could not"])[-1]})
    return {"moved": moved, "failed": failed}


def delete(paths):
    done, failed = [], []
    home = os.path.realpath(HOME)
    for p in paths:
        # the link itself, never what it points at; and only inside the home
        parent = os.path.realpath(os.path.dirname(os.path.abspath(p)))
        full = os.path.join(parent, os.path.basename(p))
        if not (parent == home or parent.startswith(home + os.sep)) or full == home:
            failed.append({"path": p, "why": "only files inside the home are deleted"})
            continue
        try:
            if os.path.isdir(full) and not os.path.islink(full):
                shutil.rmtree(full)
            else:
                os.remove(full)
            done.append(p)
        except OSError as e:
            failed.append({"path": p, "why": e.strerror or str(e)})
    return {"moved": done, "failed": failed}


def empty():
    code, _, err = run(["gio", "trash", "--empty"], timeout=600)
    return {"moved": [] if code else ["trash"], "failed": [] if code == 0 else [{"path": "trash", "why": err.strip() or "gio could not"}]}


def main(argv):
    if not argv:
        print(json.dumps({"error": "what to do"}))
        return 2
    cmd, rest = argv[0], argv[1:]
    if cmd == "overview":
        out = {"trash": trash_info(), "caches": caches(), "pkgcache": pkgcache(),
               "orphans": orphans(), "journal": journal(), "downloads": downloads()}
    elif cmd == "dupes":
        dirs = rest or [xdg_dir(n, f) for n, f in (("DOWNLOAD", "Downloads"), ("DOCUMENTS", "Documents"),
                        ("PICTURES", "Pictures"), ("VIDEOS", "Videos"), ("MUSIC", "Music"), ("DESKTOP", "Desktop"))]
        out = dupes(sorted(set(d for d in dirs if os.path.isdir(d))))
    elif cmd == "trash":
        out = trash(rest)
    elif cmd == "delete":
        out = delete(rest)
    elif cmd == "empty":
        out = empty()
    else:
        out = {"error": "unknown command " + cmd}
    print(json.dumps(out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

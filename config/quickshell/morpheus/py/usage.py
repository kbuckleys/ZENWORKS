#!/usr/bin/env python3
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# usage.py — what is taking up a volume's room, by kind: Disk Utility's
# colored bar. Terminus' disk Info sheet and stylus' volume pane both ask
# (through terminus/UsageScan), and share the one cache.
#
#   usage.py MOUNT --cache FILE [--fresh] [--max-age SECONDS]
#
# One JSON object a line:
#   { ev: "df", total, used, free }          at once, from statvfs
#   { ev: "cats", cats: { id: bytes }, at, cached: true }
#                                            the last scan, when there is one
#   { ev: "scan", files, bytes }             a long walk, as it goes
#   { ev: "cats", cats, at, cached: false }  the walk's answer (then cached)
#
# CHEAP ON PURPOSE. The free room is statvfs, never a walk. The kinds are a
# walk at idle CPU and disk priority, only when the cached one is older than
# --max-age (12 h) or --fresh asks; what it cannot read (other users'
# homes, root's directories) is simply not counted, and the difference
# between what the walk found and what statvfs says is used is the
# caller's "Other". Sizes are what is allocated (st_blocks), hard links
# counted once, and a walk never leaves the filesystem it started on.
#
# Kinds: by place first — off the user's home on the system volume is
# "system"; ~/.cache "caches", the trash "trash", flatpak and Steam "apps"
# — then, anywhere else, by extension. Standard library only.

import json
import os
import stat
import subprocess
import sys
import time

CATS = ("system", "apps", "documents", "pictures", "videos", "music", "archives", "caches", "trash", "other")

EXTS = {
    "documents": "pdf doc docx odt ods odp xls xlsx ppt pptx rtf txt md epub mobi csv tex pages key numbers djvu cbz cbr",
    "pictures": "jpg jpeg png gif webp heic heif avif jxl tif tiff bmp svg raw cr2 cr3 nef arw dng orf rw2 psd kra xcf ico",
    "videos": "mp4 mkv webm mov avi m4v mpg mpeg wmv flv 3gp ts mts",
    "music": "mp3 flac ogg oga opus m4a wav aac wma aiff alac mid midi",
    "archives": "zip tar gz tgz xz txz zst bz2 7z rar iso img dmg deb rpm appimage cab lz4 lzma",
}
BY_EXT = {e: c for c, words in EXTS.items() for e in words.split()}


def emit(**ev):
    sys.stdout.write(json.dumps(ev) + "\n")
    sys.stdout.flush()


def df(mount):
    v = os.statvfs(mount)
    total = v.f_blocks * v.f_frsize
    return total, (v.f_blocks - v.f_bfree) * v.f_frsize, v.f_bavail * v.f_frsize


def fs_key(mount):
    # the cache's key: the mount and its filesystem, so another disk
    # mounted at the same place is not given this one's answer
    try:
        return "%s@%x" % (mount, os.statvfs(mount).f_fsid)
    except OSError:
        return mount


def places(mount, home):
    # path → kind, for directories whose whole contents are one kind
    p = {}
    sysvol = mount == "/"
    if home and (home == mount or home.startswith(mount.rstrip("/") + "/")):
        p[os.path.join(home, ".cache")] = "caches"
        p[os.path.join(home, ".local/share/Trash")] = "trash"
        for a in (".local/share/flatpak", ".var/app", ".local/share/Steam", ".steam"):
            p[os.path.join(home, a)] = "apps"
    if sysvol:
        p["/opt"] = "apps"
        p["/var/lib/flatpak"] = "apps"
    return p


def other_mounts(mount):
    # mount points under this one that are other filesystems: not walked
    out = set()
    try:
        with open("/proc/self/mountinfo") as f:
            rows = [l.split(" - ", 1) for l in f]
    except OSError:
        return out
    src_of = {}
    for a, b in rows:
        a, b = a.split(), b.split()
        mp = a[4].encode().decode("unicode_escape")
        src_of[mp] = (b[1] if len(b) > 1 else "") + ":" + a[2]
    mine = src_of.get(mount)
    for mp, src in src_of.items():
        if mp != mount and mp.startswith(mount.rstrip("/") + "/") and src != mine:
            out.add(mp)
    return out


def scan(mount, home, tick=None):
    totals = dict.fromkeys(CATS, 0)
    seen = set()
    skip = other_mounts(mount)
    fixed = places(mount, home)
    under_home = home + "/" if home else None
    sysvol = mount == "/"
    files = 0
    last = time.monotonic()
    stack = [(mount, None)]
    while stack:
        d, kind = stack.pop()
        try:
            it = os.scandir(d)
        except OSError:
            continue
        with it:
            for e in it:
                try:
                    st = e.stat(follow_symlinks=False)
                except OSError:
                    continue
                if stat.S_ISDIR(st.st_mode):
                    p = e.path
                    if p in skip:
                        continue
                    k = kind or fixed.get(p)
                    if k is None and sysvol and not (under_home and (p + "/").startswith(under_home)) \
                            and not (under_home and under_home.startswith(p + "/")):
                        # the system volume, off the user's home: the
                        # system, whatever its files are called
                        k = "system"
                    stack.append((p, k))
                    continue
                if st.st_nlink > 1:
                    if (st.st_dev, st.st_ino) in seen:
                        continue
                    seen.add((st.st_dev, st.st_ino))
                size = st.st_blocks * 512
                k = kind
                if k is None:
                    name = e.name
                    dot = name.rfind(".")
                    k = BY_EXT.get(name[dot + 1:].lower(), "other") if dot > 0 else "other"
                totals[k] += size
                files += 1
                if tick and files % 4096 == 0:
                    now = time.monotonic()
                    if now - last > 0.5:
                        last = now
                        tick(files, sum(totals.values()))
    return totals


def read_cache(path):
    try:
        with open(path) as f:
            j = json.load(f)
        return j if isinstance(j, dict) else {}
    except (OSError, ValueError):
        return {}


def write_cache(path, cache):
    tmp = path + ".tmp"
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(tmp, "w") as f:
            json.dump(cache, f)
        os.replace(tmp, path)
    except OSError:
        pass


def idle():
    # a walk is background work: last in line for the CPU and the disk
    try:
        os.nice(19)
    except OSError:
        pass
    try:
        subprocess.run(["ionice", "-c", "3", "-p", str(os.getpid())], capture_output=True, timeout=3)
    except (OSError, subprocess.SubprocessError):
        pass


def main():
    a = sys.argv[1:]
    if not a or a[0].startswith("-"):
        sys.stderr.write("usage: usage.py MOUNT --cache FILE [--fresh] [--max-age SECONDS]\n")
        return 2
    mount = os.path.realpath(a[0])
    cache_path = a[a.index("--cache") + 1] if "--cache" in a[:-1] else ""
    max_age = int(a[a.index("--max-age") + 1]) if "--max-age" in a[:-1] else 12 * 3600
    try:
        total, used, free = df(mount)
    except OSError as e:
        emit(ev="done", ok=False, why="It is not there any more" if e.errno == 2
             else "It is not yours to read" if e.errno == 13 else (e.strerror or "It could not be read"))
        return 1
    emit(ev="df", total=total, used=used, free=free)
    key = fs_key(mount)
    cache = read_cache(cache_path) if cache_path else {}
    had = cache.get(key)
    if had:
        emit(ev="cats", cats=had.get("cats", {}), at=had.get("at", 0), cached=True)
    if had and "--fresh" not in a and time.time() - had.get("at", 0) < max_age:
        return 0
    idle()
    cats = scan(mount, os.path.expanduser("~"), lambda n, b: emit(ev="scan", files=n, bytes=b))
    at = int(time.time())
    emit(ev="cats", cats=cats, at=at, cached=False)
    if cache_path:
        # read again: another scan may have finished meanwhile
        cache = read_cache(cache_path)
        cache[key] = {"cats": cats, "at": at}
        write_cache(cache_path, cache)
    return 0


if __name__ == "__main__":
    sys.exit(main())

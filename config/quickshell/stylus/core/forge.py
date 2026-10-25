#!/usr/bin/env python3
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# forge.py — stylus' backend: the drives, what an image is, and writing one.
#
#   drives                [{ id, block, dev, model, vendor, serial, size, bus,
#                            kind: usb|sd|disk|loop, removable, readOnly,
#                            system, table: gpt|dos|"",
#                            parts: [{ dev, label, fstype, version, partLabel,
#                                      uuid, size, offset, number, mounts,
#                                      used, encrypted, inner }] }]
#                         `used` is a mounted one's used bytes, else -1
#                         `inner` is an unlocked LUKS volume's filesystem:
#                         { dev, fstype, label, version } (null while locked)
#                         every drive, Disk Utility's way, and this user's
#                         loop devices. The system's own disk is listed with
#                         `system` set, and nothing here writes to it.
#   watch                 a line "changed" whenever a drive comes or goes
#                         (run it tethered: Paths.tether)
#   probe FILE            { path, size, compressed, rawSize, kind, label,
#                           table, windows, sums }
#   sums FILE [--expect HEX]     the checksum, streamed (see EVENTS)
#   write SOURCE TARGET... [--no-verify]   the image onto each target, streamed
#   unlock DEV            a LUKS volume opened, the passphrase on stdin (one
#                         line) — never an argument; { ev: "done", ok,
#                         cleartext, why }
#   lock DEV              its filesystem unmounted and the container shut
#   scan DEV              every sector read, streamed like a write: phase
#                         "scan", progress, then done { ok, bad: [LBA…],
#                         badCount, read }. Read-only; the system's disk too
#   resizable             { fstype: { shrink, grow, onlineShrink, onlineGrow,
#                           offlineOnly } } — udisks' CanResize for each
#   create DRIVE OFFSET SIZE [--fs FS] [--label L] [--name N] [--type T]
#                         [--encrypt]   a partition in free space, made and
#                         formatted by udisks (CreatePartitionAndFormat);
#                         --encrypt reads the passphrase from stdin. A blank
#                         drive is given a GPT table first.
#   delete DEV            a partition unmounted (or locked) and removed
#   resize DEV SIZE       a partition and its filesystem to SIZE bytes, in
#                         the order that keeps the data: the filesystem
#                         first when shrinking, the partition first when
#                         growing; unmounted or mounted as its filesystem
#                         needs, and put back as it was
#                         All three refuse the system's own disk.
#   sig FILE              { state: good|bad|nokey|expired|revoked|none,
#                           signer, key, of: "image"|"sums", from } — the
#                           image's own signature, else its sums file's
#   fetchkey KEY          the signer's public key into your keyring, from
#                           a keyserver; { ok, why }
#   catalog               [{ id, name, version, file, url, size, sums: { url,
#                           name } | null, sig: { url, name } | null,
#                           sha256 }] — each distribution's current release,
#                           worked out from its own release files now
#   download URL DIR FILE [--sums URL NAME] [--sig URL NAME] [--sha256 HEX]
#                         the image into DIR, resumed from FILE.part when
#                         one is there, its sums and signature beside it;
#                         streamed like a write, done { ok, path }
#   bench DEV             read speed across the drive and random access
#                           time, read-only; streamed, done { ok, rates:
#                           [{ at, rate }], avg, min, max, accessMs }
#   newimage PATH SIZE [--fs FS] [--label L]
#                         a blank disk image (sparse), attached, and with
#                           --fs given a GPT table and one partition of it
#   attach PATH [--ro]    a disk image (or ISO) attached as a loop device
#   detach DEV            its volumes unmounted and the loop let go of
#   windows ISO DRIVE     a Windows installer ISO onto a drive the way it
#                         boots: GPT, one FAT32 partition, the ISO's files
#                         copied across, an install.wim over 4 GiB split
#                         into .swm parts (wimlib); streamed like a write
#   backup DEV OUT [--raw]  a drive or volume to OUT, zstd (or raw and
#                         sparse), streamed like a write; OUT.sha256 beside
#                         it. A /dev SOURCE to `write` is a clone.
#   rename DEV [--label TEXT] [--name TEXT]
#                         { ev: "done", ok, why } — a volume's filesystem
#                         label and its GPT partition name, set in place
#                         (udisks Filesystem.SetLabel, Partition.SetName)
#
# A TARGET is a udisks block object, a /dev path, or a regular file (an
# image unpacked to disk, and how the tests write without a drive).
#
# ── NO ROOT HERE ─────────────────────────────────────────────────────────
# A drive is opened by udisks (Block.OpenDevice, the way GNOME Disks
# restores): polkit asks once, through the session's agent, and this process
# gets a file descriptor back. Unmounting and the partition rescan are
# udisks' too. Nothing here runs dd, pkexec or sudo.
#
# ── EVENTS ───────────────────────────────────────────────────────────────
# sums and write print one JSON object per line:
#   { ev: "phase", phase: unmount|open|write|sync|verify|hash }
#   { ev: "progress", phase, done, total, frac, rate }      at most 4 a second
#   { ev: "done", ok, ... }     the last line, whatever happened
# A failure is { ev: "done", ok: false, code, why }; code is one of toolarge,
# busy, auth, removed, readonly, system, source, io, cancelled. SIGTERM
# cancels; the drive is left part-written, which `why` says.
#
# Standard library, plus PyGObject (Gio) for udisks: only the drive commands
# import it, so probe and sums run anywhere.

import bz2
import errno
import gzip
import hashlib
import json
import lzma
import os
import re
import signal
import stat
import struct
import subprocess
import sys
import time
import zipfile

try:
    from compression import zstd
except ImportError:  # python < 3.14
    zstd = None

UD = "org.freedesktop.UDisks2"
CHUNK = 4 << 20
# written past this without a sync, progress is the page cache filling, not
# the drive: every SYNC_EVERY bytes the drive is made to catch up
SYNC_EVERY = 64 << 20
# mount points that make a drive the system's: never listed, never written
SYSTEM_MOUNTS = ("/", "/boot", "/boot/efi", "/efi", "/usr", "/var", "/home")


def emit(**ev):
    sys.stdout.write(json.dumps(ev) + "\n")
    sys.stdout.flush()


class Fail(Exception):
    def __init__(self, code, why):
        super().__init__(why)
        self.code = code
        self.why = why


# ── WHAT AN IMAGE IS ─────────────────────────────────────────────────────

MAGIC = (
    (b"\xfd7zXZ\x00", "xz"),
    (b"\x28\xb5\x2f\xfd", "zst"),
    (b"\x1f\x8b", "gz"),
    (b"BZh", "bz2"),
    (b"PK\x03\x04", "zip"),
)
IMAGE_EXT = (".iso", ".img", ".raw", ".bin", ".dd")


def compression_of(path):
    with open(path, "rb") as f:
        head = f.read(8)
    for magic, name in MAGIC:
        if head.startswith(magic):
            return name
    return ""


def zip_member(z):
    # the one image in the archive: an image by name, else the largest file
    files = [i for i in z.infolist() if not i.is_dir()]
    named = [i for i in files if i.filename.lower().endswith(IMAGE_EXT)]
    pick = named or files
    if not pick:
        raise Fail("source", "The archive holds no image")
    return max(pick, key=lambda i: i.file_size)


class Source:
    # the image as a stream of its uncompressed bytes. `raw` is the file as
    # it sits on disk, so progress through a compressed one is its position.
    # `fd`: a drive opened for reading (a clone's source, or a backup's),
    # read as it is.
    def __init__(self, path, fd=None):
        self.path = path
        self.zip = None
        if fd is not None:
            self.raw = os.fdopen(fd, "rb", buffering=0)
            self.size = self.rawSize = os.lseek(fd, 0, os.SEEK_END)
            os.lseek(fd, 0, os.SEEK_SET)
            self.compressed = ""
            self.stream = self.raw
            return
        self.size = os.path.getsize(path)
        self.compressed = compression_of(path)
        self.raw = open(path, "rb")
        self.rawSize = 0
        c = self.compressed
        if c == "xz":
            self.stream = lzma.open(self.raw)
            self.rawSize = xz_size(path)
        elif c == "zst":
            if zstd is None:
                raise Fail("source", "zstd images need Python 3.14")
            self.stream = zstd.open(self.raw)
            self.rawSize = zst_size(path)
        elif c == "gz":
            self.stream = gzip.GzipFile(fileobj=self.raw)
        elif c == "bz2":
            self.stream = bz2.open(self.raw)
        elif c == "zip":
            self.zip = zipfile.ZipFile(self.raw)
            m = zip_member(self.zip)
            self.member = m.filename
            self.rawSize = m.file_size
            self.stream = self.zip.open(m)
        else:
            self.stream = self.raw
            self.rawSize = self.size

    def position(self):
        # how far through, 0..1, by the measure that is known
        return self.raw.tell() / self.size if self.size else 0.0

    def fill(self, buf):
        # buf filled from the stream; a decompressor hands back what it has,
        # so read until the buffer is full or the image ends
        view = memoryview(buf)
        got = 0
        while got < len(buf):
            n = self.stream.readinto(view[got:])
            if not n:
                break
            got += n
        return got

    def close(self):
        for f in (self.stream, self.zip, self.raw):
            try:
                if f:
                    f.close()
            except (OSError, ValueError):
                pass


def xz_size(path):
    # xz keeps the uncompressed size in its index; `xz -l` reads it
    try:
        out = subprocess.run(["xz", "--robot", "--list", path], capture_output=True,
                             text=True, timeout=20).stdout
    except (OSError, subprocess.SubprocessError):
        return 0
    for line in out.splitlines():
        f = line.split("\t")
        if f[0] == "totals" and len(f) > 4 and f[4].isdigit():
            return int(f[4])
    return 0


def zst_size(path):
    # the frame header's content size, when the compressor wrote one and
    # the file is one frame (zstd's own default for a file)
    try:
        with open(path, "rb") as f:
            info = zstd.get_frame_info(f.read(18))
        return info.decompressed_size or 0
    except (OSError, zstd.ZstdError, ValueError, AttributeError):
        return 0


def head_bytes(path, n=64 << 10):
    s = Source(path)
    try:
        buf = bytearray(n)
        got = s.fill(buf)
        return bytes(buf[:got])
    finally:
        s.close()


def table_of(head):
    if head[512:520] == b"EFI PART" or head[4096:4104] == b"EFI PART":
        return "gpt"
    if len(head) >= 512 and head[510:512] == b"\x55\xaa":
        return "mbr"
    return ""


def iso_label(head):
    # the primary volume descriptor, sector 16 of 2048
    pvd = head[0x8000:0x8800]
    if pvd[1:6] != b"CD001":
        return None
    return pvd[40:72].decode("ascii", "replace").strip()


def iso_dir(f, extent, length):
    # one ISO 9660 directory's records: { NAME: (extent, size, isdir) };
    # a file over 4 GiB is several records under one name, and adds up
    out = {}
    f.seek(extent * 2048)
    data = f.read(length)
    i = 0
    while i < len(data):
        n = data[i]
        if n == 0:
            i = (i // 2048 + 1) * 2048
            continue
        rec = data[i:i + n]
        ext, size, flags, nl = struct.unpack_from("<I", rec, 2)[0], struct.unpack_from("<I", rec, 10)[0], rec[25], rec[32]
        name = rec[33:33 + nl].decode("ascii", "replace").split(";")[0].rstrip(".").upper()
        if name not in ("\x00", "\x01"):
            prev = out.get(name)
            out[name] = (prev[0] if prev else ext, size + (prev[1] if prev else 0), bool(flags & 2))
        i += n
    return out


def windows_of(path):
    # a Windows installer ISO: sources/install.wim (or .esd) under the root.
    # The size decides whether it fits FAT32 whole (phase 4 splits it).
    try:
        with open(path, "rb") as f:
            f.seek(0x8000)
            pvd = f.read(2048)
            root = pvd[156:190]
            top = iso_dir(f, struct.unpack_from("<I", root, 2)[0], struct.unpack_from("<I", root, 10)[0])
            src = top.get("SOURCES")
            if not src or not src[2]:
                return None
            inner = iso_dir(f, src[0], src[1])
    except (OSError, struct.error, IndexError):
        return None
    for name in ("INSTALL.WIM", "INSTALL.ESD", "INSTALL.SWM"):
        if name in inner:
            size = inner[name][1]
            return {"wim": "sources/" + name.lower(), "wimSize": size,
                    "split": size > 0xFFFFFFFF, "uefi": "EFI" in top}
    return None


def probe(path):
    path = os.path.abspath(path)
    s = Source(path)
    out = {"path": path, "size": s.size, "compressed": s.compressed, "rawSize": s.rawSize,
           "member": getattr(s, "member", "")}
    s.close()
    head = head_bytes(path)
    table = table_of(head)
    label = iso_label(head)
    windows = windows_of(path) if label is not None and not s.compressed and not table else None
    if windows:
        kind = "windows"
    elif label is not None:
        # hybrid: an ISO that is also a disk, written as it is
        kind = "hybrid" if table else "iso"
    else:
        kind = "disk" if table else "raw"
    out.update(kind=kind, label=label or "", table=table, windows=windows, sums=sidecar(path))
    return out


# ── CHECKSUMS ────────────────────────────────────────────────────────────
# A download's sums sit beside it: name.sha256, SHA256SUMS, Fedora's
# *-CHECKSUM. Both line styles are read, GNU ("hex  name") and BSD
# ("SHA256 (name) = hex"); a file holding nothing but the hex counts when it
# is named after the image.

ALGOS = {32: "md5", 40: "sha1", 64: "sha256", 128: "sha512"}
GNU = re.compile(r"^([0-9a-fA-F]{32,128})\s+[ *]?(?:\./)?(.+?)\s*$")
BSD = re.compile(r"^(MD5|SHA1|SHA256|SHA512)\s*\((?:\./)?(.+?)\)\s*=\s*([0-9a-fA-F]+)\s*$", re.I)
SUMS_NAME = re.compile(r"(sums?|checksums?|\.sha\d+|\.md5)(\.txt)?$", re.I)


def sums_in(text, name, alone=False):
    lines = [l.strip() for l in text.splitlines() if l.strip() and not l.startswith("#")]
    for l in lines:
        m = BSD.match(l)
        if m and os.path.basename(m.group(2)) == name:
            return m.group(1).lower(), m.group(3).lower()
        m = GNU.match(l)
        if m and os.path.basename(m.group(2)) == name and len(m.group(1)) in ALGOS:
            return ALGOS[len(m.group(1))], m.group(1).lower()
    if alone and len(lines) == 1 and len(lines[0].split()[0]) in ALGOS:
        h = lines[0].split()[0]
        if re.fullmatch(r"[0-9a-fA-F]+", h):
            return ALGOS[len(h)], h.lower()
    return None


def sidecar(path):
    d, name = os.path.split(path)
    try:
        entries = sorted(os.listdir(d))
    except OSError:
        return None
    for e in entries:
        p = os.path.join(d, e)
        if e == name or not SUMS_NAME.search(e) or not os.path.isfile(p):
            continue
        try:
            if os.path.getsize(p) > 1 << 20:
                continue
            with open(p, encoding="utf-8", errors="replace") as f:
                text = f.read()
        except OSError:
            continue
        got = sums_in(text, name, alone=e.startswith(name))
        if got:
            return {"algo": got[0], "expected": got[1], "from": p}
    return None


def sums(path, expect=""):
    path = os.path.abspath(path)
    found = sidecar(path)
    if expect:
        expect = expect.strip().lower()
        found = {"algo": ALGOS.get(len(expect), "sha256"), "expected": expect, "from": ""}
    algo = found["algo"] if found else "sha256"
    h = hashlib.new(algo)
    total = os.path.getsize(path)
    emit(ev="phase", phase="hash")
    meter = Meter("hash", total)
    with open(path, "rb") as f:
        buf = bytearray(CHUNK)
        while not Stop.asked:
            n = f.readinto(buf)
            if not n:
                break
            h.update(memoryview(buf)[:n])
            meter.add(n)
    if Stop.asked:
        raise Fail("cancelled", "Stopped")
    got = h.hexdigest()
    emit(ev="done", ok=(not found or got == found["expected"]), algo=algo, got=got,
         expected=found["expected"] if found else "", **{"from": found["from"] if found else ""},
         checked=bool(found))


# ── DOWNLOADS ────────────────────────────────────────────────────────────
# A handful of distributions, each found where it says its current release
# is — never a version written in here, which would be stale by the next
# release. One that cannot be reached is left out of the list, not guessed.

UA = {"User-Agent": "stylus (Zenworks)"}


def fetch(url, timeout=20):
    import urllib.request
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout) as r:
        return r.read().decode("utf-8", "replace")


def head_size(url):
    import urllib.request
    try:
        req = urllib.request.Request(url, headers=UA, method="HEAD")
        with urllib.request.urlopen(req, timeout=20) as r:
            return int(r.headers.get("Content-Length") or 0)
    except Exception:
        return 0


def line_for(text, pattern):
    for l in text.splitlines():
        m = re.match(r"^([0-9a-fA-F]{64})\s+\*?(\S+)$", l.strip())
        if m and re.fullmatch(pattern, m.group(2)):
            return m.group(2), m.group(1)
    return None, None


def entry_arch():
    base = "https://geo.mirror.pkgbuild.com/iso/latest/"
    name, h = line_for(fetch(base + "sha256sums.txt"), r"archlinux-\d{4}\.\d{2}\.\d{2}-x86_64\.iso")
    if not name:
        return None
    return {"id": "arch", "name": "Arch Linux", "version": name.split("-")[1], "file": name, "url": base + name,
            "sums": {"url": base + "sha256sums.txt", "name": "sha256sums.txt"},
            "sig": {"url": base + name + ".sig", "name": name + ".sig"}, "sha256": h}


def entry_debian():
    base = "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/"
    name, h = line_for(fetch(base + "SHA256SUMS"), r"debian-[\d.]+-amd64-netinst\.iso")
    if not name:
        return None
    return {"id": "debian", "name": "Debian (netinst)", "version": name.split("-")[1], "file": name, "url": base + name,
            "sums": {"url": base + "SHA256SUMS", "name": "SHA256SUMS"},
            "sig": {"url": base + "SHA256SUMS.sign", "name": "SHA256SUMS.sign"}, "sha256": h}


def entry_ubuntu():
    ver = ""
    for block in fetch("https://changelogs.ubuntu.com/meta-release-lts").split("\n\n"):
        f = dict(l.split(": ", 1) for l in block.splitlines() if ": " in l)
        if f.get("Supported") == "1" and f.get("Version"):
            ver = f["Version"].replace(" LTS", "").strip()
    if not ver:
        return None
    base = "https://releases.ubuntu.com/" + ver + "/"
    name, h = line_for(fetch(base + "SHA256SUMS"), r"ubuntu-[\d.]+-desktop-amd64\.iso")
    if not name:
        return None
    return {"id": "ubuntu", "name": "Ubuntu (LTS)", "version": ver, "file": name, "url": base + name,
            "sums": {"url": base + "SHA256SUMS", "name": "SHA256SUMS"},
            "sig": {"url": base + "SHA256SUMS.gpg", "name": "SHA256SUMS.gpg"}, "sha256": h}


def entry_fedora():
    best = None
    for e in json.loads(fetch("https://fedoraproject.org/releases.json")):
        if e.get("variant") == "Workstation" and e.get("arch") == "x86_64" and str(e.get("link", "")).endswith(".iso"):
            v = str(e.get("version", ""))
            if v.isdigit() and (not best or int(v) > int(best["version"])):
                best = e
    if not best:
        return None
    link = best["link"]
    return {"id": "fedora", "name": "Fedora Workstation", "version": best["version"], "file": link.rsplit("/", 1)[1],
            "url": link, "size": int(best.get("size") or 0), "sums": None, "sig": None, "sha256": best.get("sha256", "")}


def entry_opensuse():
    base = "https://download.opensuse.org/tumbleweed/iso/"
    current = "openSUSE-Tumbleweed-DVD-x86_64-Current.iso"
    name, h = line_for(fetch(base + current + ".sha256"), r"openSUSE-Tumbleweed-DVD-x86_64-Snapshot\d+-Media\.iso")
    if not name:
        return None
    return {"id": "opensuse", "name": "openSUSE Tumbleweed", "version": name.split("Snapshot")[1].split("-")[0],
            "file": name, "url": base + name, "sums": {"url": base + name + ".sha256", "name": name + ".sha256"},
            "sig": {"url": base + name + ".sha256.asc", "name": name + ".sha256.asc"}, "sha256": h}


def catalog():
    from concurrent.futures import ThreadPoolExecutor

    def one(fn):
        try:
            e = fn()
        except Exception:
            return None
        if e and not e.get("size"):
            e["size"] = head_size(e["url"])
        return e

    with ThreadPoolExecutor(5) as ex:
        out = [e for e in ex.map(one, (entry_arch, entry_fedora, entry_ubuntu, entry_debian, entry_opensuse)) if e]
    print(json.dumps(out))


def download(url, dest_dir, name, sums=None, sig=None, sha=""):
    import urllib.request
    import urllib.error
    name = os.path.basename(name)
    path = os.path.join(dest_dir, name)
    part = path + ".part"
    os.makedirs(dest_dir, exist_ok=True)
    have = os.path.getsize(part) if os.path.exists(part) else 0
    hdrs = dict(UA)
    if have:
        hdrs["Range"] = "bytes=%d-" % have
    emit(ev="phase", phase="download")
    try:
        r = urllib.request.urlopen(urllib.request.Request(url, headers=hdrs), timeout=30)
    except urllib.error.HTTPError as e:
        if e.code == 416 and have:
            r = None
        else:
            raise Fail("io", "The download could not start (%d)" % e.code)
    except (urllib.error.URLError, OSError) as e:
        raise Fail("io", "No connection: " + str(getattr(e, "reason", e)))
    if r is not None:
        # a server that ignored the range sends it all from the start
        if have and r.status != 206:
            have = 0
        total = have + int(r.headers.get("Content-Length") or 0)
        meter = Meter("download", total)
        meter.done = have
        with open(part, "ab" if have else "wb") as f:
            while not Stop.asked:
                try:
                    chunk = r.read(1 << 20)
                except OSError as e:
                    raise Fail("io", "The download broke off — it resumes from here next time (" + str(e) + ")")
                if not chunk:
                    break
                f.write(chunk)
                meter.add(len(chunk))
        r.close()
        meter.add(0, force=True)
        if Stop.asked:
            raise Fail("cancelled", "Stopped — it resumes from here next time")
    os.replace(part, path)
    # the sums and the signature beside it, as the distribution has them
    for extra in (sums, sig):
        if extra:
            try:
                with urllib.request.urlopen(urllib.request.Request(extra[0], headers=UA), timeout=30) as x, \
                        open(os.path.join(dest_dir, os.path.basename(extra[1])), "wb") as f:
                    f.write(x.read())
            except Exception:
                pass
    if sha and not sums:
        with open(path + ".sha256", "w") as f:
            f.write("%s  %s\n" % (sha, name))
    emit(ev="done", ok=True, path=path, why="")


# ── SIGNATURES ───────────────────────────────────────────────────────────
# A download signed by whoever made it: the image's own .sig/.asc/.gpg, or
# — what most distributions sign — the sums file beside it (Arch's .sig on
# the ISO, Ubuntu's SHA256SUMS.gpg, Debian's SHA256SUMS.sign, Fedora's
# CHECKSUM clearsigned). A good signature on the sums file plus a matching
# sum is the image vouched for. gpg checks against your own keyring; a key
# not in it is said with its id, and fetched only when asked (fetchkey).

SIG_EXTS = (".sig", ".asc", ".gpg", ".sign")


def gpg_verify(sig, data):
    import shutil
    if not shutil.which("gpg"):
        return {"state": "none", "why": "gpg is not installed"}
    argv = ["gpg", "--batch", "--status-fd", "1", "--verify"] + ([sig, data] if sig else [data])
    try:
        r = subprocess.run(argv, capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.SubprocessError):
        return {"state": "none", "why": "gpg did not answer"}
    out = {"state": "bad", "signer": "", "key": ""}
    for line in r.stdout.splitlines():
        f = line.split(" ", 3)
        if len(f) < 2 or f[0] != "[GNUPG:]":
            continue
        tag = f[1]
        if tag in ("GOODSIG", "EXPKEYSIG", "REVKEYSIG", "BADSIG"):
            out["key"] = f[2] if len(f) > 2 else ""
            out["signer"] = f[3] if len(f) > 3 else ""
            out["state"] = {"GOODSIG": "good", "EXPKEYSIG": "expired", "REVKEYSIG": "revoked", "BADSIG": "bad"}[tag]
        elif tag == "NO_PUBKEY":
            out["state"] = "nokey"
            out["key"] = f[2] if len(f) > 2 else ""
        elif tag == "ERRSIG" and out["state"] == "bad" and len(f) > 2:
            out["key"] = out["key"] or f[2]
    return out


def find_sig(path):
    for e in SIG_EXTS:
        if os.path.isfile(path + e):
            return path + e
    return ""


def sig(path):
    path = os.path.abspath(path)
    own = find_sig(path)
    if own:
        out = gpg_verify(own, path)
        out.update({"of": "image", "from": own})
        print(json.dumps(out))
        return
    s_ = sidecar(path)
    if s_ and s_.get("from"):
        sums_file = s_["from"]
        detached = find_sig(sums_file)
        if detached:
            out = gpg_verify(detached, sums_file)
            out.update({"of": "sums", "from": detached})
            print(json.dumps(out))
            return
        with open(sums_file, errors="replace") as f:
            if "-----BEGIN PGP SIGNED MESSAGE-----" in f.read(4096):
                out = gpg_verify("", sums_file)
                out.update({"of": "sums", "from": sums_file})
                print(json.dumps(out))
                return
    print(json.dumps({"state": "none", "signer": "", "key": "", "of": "", "from": ""}))


def fetchkey(key):
    key = re.sub(r"[^0-9A-Fa-fx]", "", key)
    if not key:
        raise Fail("source", "No key id")
    last = ""
    for server in ("hkps://keyserver.ubuntu.com", "hkps://keys.openpgp.org"):
        try:
            r = subprocess.run(["gpg", "--batch", "--keyserver", server, "--recv-keys", key],
                               capture_output=True, text=True, timeout=60)
        except (OSError, subprocess.SubprocessError):
            continue
        if r.returncode == 0:
            emit(ev="done", ok=True, why="")
            return
        last = (r.stderr.strip().splitlines() or [""])[-1]
    raise Fail("io", "The key could not be fetched" + (": " + last if last else ""))


# ── PROGRESS AND STOPPING ────────────────────────────────────────────────

class Stop:
    asked = False


def on_term(*_):
    Stop.asked = True


class Meter:
    def __init__(self, phase, total, frac=None):
        self.phase, self.total, self.done = phase, total, 0
        self.frac = frac
        self.t0 = self.last = time.monotonic()

    def add(self, n, force=False):
        self.done += n
        now = time.monotonic()
        if not force and now - self.last < 0.25:
            return
        self.last = now
        took = now - self.t0
        f = self.frac() if self.frac else (self.done / self.total if self.total else 0.0)
        emit(ev="progress", phase=self.phase, done=self.done, total=self.total,
             frac=round(min(f, 1.0), 4), rate=int(self.done / took) if took > 0 else 0)


# ── THE DRIVES (udisks) ──────────────────────────────────────────────────

def gio():
    from gi.repository import Gio, GLib
    return Gio, GLib


def bus():
    Gio, _ = gio()
    return Gio.bus_get_sync(Gio.BusType.SYSTEM, None)


def text(ay):
    # an "ay": a NUL-terminated byte string
    if isinstance(ay, (bytes, bytearray)):
        b = bytes(ay)
    else:
        b = bytes(ay or [])
    return b.split(b"\x00", 1)[0].decode("utf-8", "replace")


def objects(conn):
    r = conn.call_sync(UD, "/org/freedesktop/UDisks2", "org.freedesktop.DBus.ObjectManager",
                       "GetManagedObjects", None, None, 0, -1, None)
    return r.unpack()[0]


def disk_of(majmin):
    # the whole disks under a block device, through partitions and the
    # device-mapper layers (LUKS, LVM) down to their slaves
    out = set()
    p = os.path.realpath("/sys/dev/block/" + majmin)
    if not os.path.isdir(p):
        return out
    if os.path.exists(os.path.join(p, "partition")):
        p = os.path.dirname(p)
    slaves = os.path.join(p, "slaves")
    under = os.listdir(slaves) if os.path.isdir(slaves) else []
    if not under:
        out.add(os.path.basename(p))
    for s in under:
        try:
            with open(os.path.join(slaves, s, "dev")) as f:
                out |= disk_of(f.read().strip())
        except OSError:
            pass
    return out


def system_disks():
    # every whole disk behind the mounts the system stands on, and swap
    found = set()

    def dev_of(src, majmin):
        if src.startswith("/dev/"):
            try:
                r = os.stat(src).st_rdev
                return "%d:%d" % (os.major(r), os.minor(r))
            except OSError:
                pass
        return majmin

    try:
        with open("/proc/self/mountinfo") as f:
            for line in f:
                a, b = line.split(" - ", 1)
                a, b = a.split(), b.split()
                if a[4] in SYSTEM_MOUNTS:
                    found |= disk_of(dev_of(b[1] if len(b) > 1 else "", a[2]))
    except OSError:
        pass
    try:
        with open("/proc/swaps") as f:
            for line in f.readlines()[1:]:
                p = line.split()[0]
                st = os.stat(p)
                r = st.st_rdev if stat.S_ISBLK(st.st_mode) else st.st_dev
                found |= disk_of("%d:%d" % (os.major(r), os.minor(r)))
    except (OSError, IndexError):
        pass
    return found


def drive_list():
    conn = bus()
    objs = objects(conn)
    sysd = system_disks()
    blocks = {p: i for p, i in objs.items() if UD + ".Block" in i}
    out = []
    for path, ifaces in sorted(blocks.items()):
        b = ifaces[UD + ".Block"]
        if UD + ".Partition" in ifaces or b.get("CryptoBackingDevice", "/") != "/":
            continue
        dev = text(b.get("Device"))
        name = os.path.basename(dev)
        loop = ifaces.get(UD + ".Loop")
        d = objs.get(b.get("Drive", "/"), {}).get(UD + ".Drive")
        if loop is not None:
            if loop.get("SetupByUID") != os.getuid() or not text(loop.get("BackingFile")):
                continue
            kind, removable = "loop", False
            model, vendor, serial, bus_ = os.path.basename(text(loop.get("BackingFile"))), "", "", ""
        elif d is not None:
            bus_ = d.get("ConnectionBus", "")
            removable = bool(d.get("Removable") or d.get("MediaRemovable") or bus_ in ("usb", "sdio"))
            media = d.get("Media", "")
            kind = "usb" if bus_ == "usb" else "sd" if (bus_ == "sdio" or media.startswith("flash_sd")) else "disk"
            if removable and not d.get("MediaAvailable", True):
                continue
            model, vendor, serial = d.get("Model", ""), d.get("Vendor", ""), d.get("Serial", "")
        else:
            continue
        if b.get("Size", 0) == 0:
            continue
        out.append({"id": b.get("Drive", "/") if d is not None else path, "block": path, "dev": dev,
                    "model": model.strip(), "vendor": vendor.strip(), "serial": serial, "size": b.get("Size", 0),
                    "bus": bus_, "kind": kind, "removable": removable, "readOnly": bool(b.get("ReadOnly")),
                    "system": name in sysd, "table": ifaces.get(UD + ".PartitionTable", {}).get("Type", ""),
                    "parts": parts_of(objs, path)})
    return out


def parts_of(objs, whole):
    out = []
    for p, i in objs.items():
        part = i.get(UD + ".Partition")
        if not part or part.get("Table") != whole:
            continue
        b = i[UD + ".Block"]
        mounts = [text(m) for m in i.get(UD + ".Filesystem", {}).get("MountPoints", [])]
        # an unlocked LUKS partition: what is mounted is its cleartext child
        for q, j in objs.items():
            if j.get(UD + ".Block", {}).get("CryptoBackingDevice") == p:
                mounts += [text(m) for m in j.get(UD + ".Filesystem", {}).get("MountPoints", [])]
        inner = None
        for q, j in objs.items():
            cb = j.get(UD + ".Block", {})
            if cb.get("CryptoBackingDevice") == p:
                inner = {"dev": text(cb.get("Device")), "fstype": cb.get("IdType", ""), "label": cb.get("IdLabel", ""),
                         "version": cb.get("IdVersion", "")}
        # what a mounted one holds: the floor for shrinking it (statvfs, cheap)
        used = -1
        if mounts:
            try:
                v = os.statvfs(mounts[0])
                used = (v.f_blocks - v.f_bfree) * v.f_frsize
            except OSError:
                pass
        out.append({"dev": text(b.get("Device")), "label": b.get("IdLabel", ""), "fstype": b.get("IdType", ""),
                    "encrypted": UD + ".Encrypted" in i, "inner": inner, "used": used,
                    "version": b.get("IdVersion", ""), "partLabel": part.get("Name", ""), "uuid": b.get("IdUUID", ""),
                    "size": b.get("Size", 0), "offset": part.get("Offset", 0), "number": part.get("Number", 0),
                    "mounts": mounts})
    return sorted(out, key=lambda x: x["number"])


def watch():
    Gio, GLib = gio()
    conn = bus()
    loop = GLib.MainLoop()
    pending = [0]

    def tell():
        pending[0] = 0
        emit(ev="changed")
        return False

    def on_signal(*_):
        if pending[0]:
            GLib.source_remove(pending[0])
        pending[0] = GLib.timeout_add(300, tell)

    for sig in ("InterfacesAdded", "InterfacesRemoved"):
        conn.signal_subscribe(UD, "org.freedesktop.DBus.ObjectManager", sig, "/org/freedesktop/UDisks2",
                              None, 0, on_signal)
    # media in a card reader: the block changes, nothing is added
    conn.signal_subscribe(UD, "org.freedesktop.DBus.Properties", "PropertiesChanged", None,
                          UD + ".Drive", 0, on_signal)
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, loop.quit)
    loop.run()


# ── WRITING ──────────────────────────────────────────────────────────────

class Target:
    # one place the image goes: a drive (through udisks) or a regular file
    def __init__(self, arg, conn_objs):
        self.arg = arg
        self.fd = -1
        self.block = ""
        self.size = 0
        self.failed = ""
        self.code = ""
        path = "" if arg.startswith("/org/") else os.path.realpath(arg)
        if path and not path.startswith("/dev/") and (not os.path.exists(path) or os.path.isfile(path)):
            self.dev = path
            self.file = True
            return
        self.file = False
        conn, objs = conn_objs()
        for p, i in objs.items():
            b = i.get(UD + ".Block")
            if b and (p == arg or text(b.get("Device")) == path):
                self.block, self.dev, self.size = p, text(b.get("Device")), b.get("Size", 0)
                self.ro = bool(b.get("ReadOnly"))
                if UD + ".Partition" in i:
                    raise Fail("source", "Write to the whole drive, not one partition")
                break
        if not self.block:
            raise Fail("removed", "The drive is not there any more")
        if os.path.basename(self.dev) in system_disks():
            raise Fail("system", "That is the drive the system runs from")
        if self.ro:
            raise Fail("readonly", "The drive is read-only (a lock switch?)")

    def gone(self):
        return not self.file and not os.path.exists("/sys/class/block/" + os.path.basename(self.dev))


def call(conn, path, iface, method, args, fds=False):
    Gio, GLib = gio()
    flags = Gio.DBusCallFlags.ALLOW_INTERACTIVE_AUTHORIZATION
    try:
        if fds:
            return conn.call_with_unix_fd_list_sync(UD, path, iface, method, args, GLib.VariantType("(h)"),
                                                    flags, GLib.MAXINT, None, None)
        return conn.call_sync(UD, path, iface, method, args, None, flags, GLib.MAXINT, None)
    except GLib.Error as e:
        msg = e.message or ""
        if "NotAuthorized" in msg or "not authorized" in msg.lower() or "Dismissed" in msg:
            raise Fail("auth", "Permission was not given")
        if "busy" in msg.lower():
            raise Fail("busy", "Something is still using the drive")
        raise Fail("io", msg.split(": ", 1)[-1])


def unmount(conn, objs, t):
    # every mounted filesystem on the drive, and any unlocked LUKS under it
    _, GLib = gio()
    none = GLib.Variant("(a{sv})", ({},))
    for p, i in objs.items():
        part = i.get(UD + ".Partition")
        if not part or part.get("Table") != t.block:
            continue
        for q, j in objs.items():
            if j.get(UD + ".Block", {}).get("CryptoBackingDevice") == p:
                if j.get(UD + ".Filesystem", {}).get("MountPoints"):
                    call(conn, q, UD + ".Filesystem", "Unmount", none)
                call(conn, p, UD + ".Encrypted", "Lock", none)
        if i.get(UD + ".Filesystem", {}).get("MountPoints"):
            call(conn, p, UD + ".Filesystem", "Unmount", none)


def open_target(conn, t):
    if t.file:
        t.fd = os.open(t.dev, os.O_RDWR | os.O_CREAT | os.O_TRUNC | os.O_CLOEXEC, 0o644)
        return
    _, GLib = gio()
    opts = {"flags": GLib.Variant("i", os.O_EXCL | os.O_CLOEXEC)}
    r, fdl = call(conn, t.block, UD + ".Block", "OpenDevice", GLib.Variant("(sa{sv})", ("rw", opts)), fds=True)
    t.fd = fdl.get(r.unpack()[0])
    # the size the kernel sees, which udisks' cached property can lag
    t.size = os.lseek(t.fd, 0, os.SEEK_END)
    os.lseek(t.fd, 0, os.SEEK_SET)


def inhibit(conn_objs):
    # logind holds off sleep while the fd stays open; nothing to undo
    try:
        Gio, GLib = gio()
        sysbus = conn_objs()[0]
        r, fdl = sysbus.call_with_unix_fd_list_sync(
            "org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager", "Inhibit",
            GLib.Variant("(ssss)", ("sleep:idle:handle-lid-switch", "Stylus", "Writing a drive", "block")),
            GLib.VariantType("(h)"), 0, -1, None, None)
        return fdl.get(r.unpack()[0])
    except Exception:
        return -1


def write_all(fd, view):
    while view:
        n = os.write(fd, view)
        view = view[n:]


def why_of(e, t):
    if t.gone():
        return "removed", "The drive was taken out"
    if e.errno == errno.ENOSPC:
        return "toolarge", "The image is bigger than the drive"
    if e.errno in (errno.EROFS, errno.EACCES, errno.EPERM):
        return "readonly", "The drive refused to be written"
    return "io", os.strerror(e.errno) if e.errno else str(e)


def write(src_path, targets, verify=True):
    cache = {}

    def conn_objs():
        if "c" not in cache:
            cache["c"] = bus()
        cache["o"] = objects(cache["c"])
        return cache["c"], cache["o"]

    ts = [Target(a, conn_objs) for a in targets]
    if src_path.startswith("/dev/") and any(t.dev == os.path.realpath(src_path) for t in ts):
        raise Fail("source", "A drive cannot be copied onto itself")
    try:
        src = read_source(src_path)
    except (OSError, zipfile.BadZipFile, lzma.LZMAError) as e:
        raise Fail("source", "The image could not be read: " + str(e))
    drives = [t for t in ts if not t.file]
    hold = inhibit(conn_objs) if drives else -1
    if drives:
        emit(ev="phase", phase="unmount")
        for t in drives:
            if src.rawSize and t.size and src.rawSize > t.size:
                raise Fail("toolarge", "The image is bigger than the drive")
            unmount(*conn_objs(), t)
    emit(ev="phase", phase="open")
    for t in ts:
        open_target(cache.get("c"), t)
    emit(ev="phase", phase="write")
    total = src.rawSize
    meter = Meter("write", total, (lambda: meter.done / total) if total else src.position)
    h = hashlib.sha256()
    buf = bytearray(CHUNK)
    unsynced = 0
    live = list(ts)
    try:
        while not Stop.asked and live:
            n = src.fill(buf)
            if not n:
                break
            view = memoryview(buf)[:n]
            for t in list(live):
                if t.size and meter.done + n > t.size:
                    t.code, t.failed = "toolarge", "The image is bigger than the drive"
                    live.remove(t)
                    continue
                try:
                    write_all(t.fd, view)
                except OSError as e:
                    t.code, t.failed = why_of(e, t)
                    live.remove(t)
            h.update(view)
            unsynced += n
            if unsynced >= SYNC_EVERY:
                unsynced = 0
                for t in live:
                    settle(t, meter.done + n)
            meter.add(n)
    except (OSError, EOFError, lzma.LZMAError, zipfile.BadZipFile, ValueError) as e:
        src.close()
        raise Fail("source", "The image is damaged: " + str(e))
    written = meter.done
    meter.add(0, force=True)
    src.close()
    if Stop.asked:
        for t in ts:
            safe_close(t)
        raise Fail("cancelled", "Stopped — the drive is half written; write it again or reset it")
    emit(ev="phase", phase="sync")
    for t in live:
        try:
            os.fsync(t.fd)
        except OSError as e:
            t.code, t.failed = why_of(e, t)
    live = [t for t in live if not t.failed]
    if verify and live:
        check(live, written, h.hexdigest())
    for t in ts:
        safe_close(t)
        if t.block and not t.gone():
            # the new partitions, seen now instead of whenever udev looks
            try:
                _, GLib = gio()
                call(cache["c"], t.block, UD + ".Block", "Rescan", GLib.Variant("(a{sv})", ({},)))
            except Fail:
                pass
    if hold >= 0:
        os.close(hold)
    out = [{"target": t.arg, "dev": t.dev, "ok": not t.failed, "code": t.code, "why": t.failed} for t in ts]
    ok = all(o["ok"] for o in out)
    first = next((o for o in out if not o["ok"]), None)
    emit(ev="done", ok=ok, written=written, sha256=h.hexdigest(), verified=bool(verify), targets=out,
         code=first["code"] if first else "", why=first["why"] if first else "")


def settle(t, upto):
    # the drive made to catch up, and what it now holds let go of: the page
    # cache would otherwise fill with the image and progress race ahead
    try:
        os.fdatasync(t.fd)
        os.posix_fadvise(t.fd, 0, upto, os.POSIX_FADV_DONTNEED)
    except OSError as e:
        t.code, t.failed = why_of(e, t)


def check(live, written, want):
    # the written bytes read back off each drive, past the page cache
    emit(ev="phase", phase="verify")
    meter = Meter("verify", written * len(live))
    buf = bytearray(CHUNK)
    for t in live:
        try:
            os.posix_fadvise(t.fd, 0, 0, os.POSIX_FADV_DONTNEED)
        except OSError:
            pass
        h = hashlib.sha256()
        off = 0
        try:
            while off < written and not Stop.asked:
                n = os.preadv(t.fd, [memoryview(buf)[:min(CHUNK, written - off)]], off)
                if not n:
                    break
                h.update(memoryview(buf)[:n])
                off += n
                meter.add(n)
        except OSError as e:
            t.code, t.failed = why_of(e, t)
            continue
        if Stop.asked:
            raise Fail("cancelled", "Stopped while checking — the drive is written but unchecked")
        if h.hexdigest() != want:
            t.code, t.failed = "io", "What was read back does not match the image — the drive may be failing"
    meter.add(0, force=True)


def safe_close(t):
    if t.fd >= 0:
        try:
            os.close(t.fd)
        except OSError:
            pass
        t.fd = -1


# ── A WINDOWS INSTALLER ──────────────────────────────────────────────────
# A Windows ISO is not a hybrid image: written byte for byte it does not
# start. What does is what Rufus makes for UEFI: a GPT drive, one FAT32
# partition, the ISO's files copied onto it — and FAT32 holds no file over
# 4 GiB, so an install.wim past that is split into install.swm parts,
# which Windows Setup reads as they are. Everything through udisks: the
# ISO set up as a read-only loop and mounted, the stick formatted and
# mounted, both put away after, whatever happens in between.

SPLIT_MB = 3800


class Shim:
    # what unmount() needs of a Target
    def __init__(self, block):
        self.block = block


def wait_for(conn, path, iface, tries=40):
    # udisks adds a new block's interfaces a moment after it answers
    for _ in range(tries):
        objs = objects(conn)
        if iface in objs.get(path, {}):
            return objs
        time.sleep(0.25)
    raise Fail("io", "udisks did not finish setting it up")


def copy_tree(src, dst, skip, meter):
    for root, dirs, files in os.walk(src):
        rel = os.path.relpath(root, src)
        out = os.path.join(dst, rel) if rel != "." else dst
        os.makedirs(out, exist_ok=True)
        for name in files:
            if Stop.asked:
                return
            sp = os.path.join(root, name)
            if os.path.normcase(os.path.relpath(sp, src)).lower() in skip:
                continue
            with open(sp, "rb") as a, open(os.path.join(out, name), "wb") as b:
                while True:
                    chunk = a.read(CHUNK)
                    if not chunk:
                        break
                    b.write(chunk)
                    meter.add(len(chunk))


def tree_size(src, skip):
    total = 0
    for root, _, files in os.walk(src):
        for name in files:
            sp = os.path.join(root, name)
            if os.path.relpath(sp, src).lower() not in skip:
                total += os.path.getsize(sp)
    return total


def split_wim(wim, dest, meter):
    # wimlib's own words for how far, on stdout: "… (42%) written"
    import shutil
    tool = shutil.which("wimlib-imagex")
    if not tool:
        raise Fail("tool", "wimlib is needed to split install.wim")
    pr = subprocess.Popen([tool, "split", wim, dest, str(SPLIT_MB)], stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, text=True, bufsize=1)
    last = ""
    buf = ""
    while True:
        ch = pr.stdout.read(1)
        if not ch:
            break
        if ch in "\r\n":
            m = re.search(r"\((\d+)%\)", buf)
            if m:
                meter.frac = (lambda f: lambda: f)(int(m.group(1)) / 100)
                meter.add(0)
            if buf.strip():
                last = buf.strip()
            buf = ""
        else:
            buf += ch
        if Stop.asked:
            pr.terminate()
    if pr.wait() != 0 and not Stop.asked:
        raise Fail("io", "Splitting install.wim failed: " + last)


def windows(iso, drive):
    p = probe(iso)
    if p["kind"] != "windows":
        raise Fail("source", "This is not a Windows installer")
    win = p["windows"]
    split = bool(win and win["split"])
    import shutil
    if split and not shutil.which("wimlib-imagex"):
        raise Fail("tool", "wimlib is needed to split install.wim")
    _, GLib = gio()
    conn = bus()
    objs = objects(conn)
    whole = block_of(objs, os.path.realpath(drive))
    not_system(objs, whole)
    if objs[whole][UD + ".Block"].get("ReadOnly"):
        raise Fail("readonly", "The drive is read-only (a lock switch?)")
    size = objs[whole][UD + ".Block"].get("Size", 0)
    if size and p["size"] > size:
        raise Fail("toolarge", "The installer is bigger than the drive")
    hold = inhibit(lambda: (conn, objs))
    none = GLib.Variant("(a{sv})", ({},))
    part = loop = None
    stick = iso_mnt = ""
    try:
        emit(ev="phase", phase="unmount")
        unmount(conn, objs, Shim(whole))
        emit(ev="phase", phase="prepare")
        call(conn, whole, UD + ".Block", "Format", GLib.Variant("(sa{sv})", ("gpt", {})))
        objs = wait_for(conn, whole, UD + ".PartitionTable")
        r_ = call(conn, whole, UD + ".PartitionTable", "CreatePartitionAndFormat",
                  GLib.Variant("(ttssa{sv}sa{sv})", (MiB, 0, "EBD0A0A2-B9E5-4433-87C0-68B6B72699C7", "Windows", {},
                                                     "vfat", {"label": GLib.Variant("s", "WINDOWS")})))
        part = r_.unpack()[0]
        wait_for(conn, part, UD + ".Filesystem")
        stick = call(conn, part, UD + ".Filesystem", "Mount", none).unpack()[0]
        # the ISO, read-only, as udisks' own loop
        loop = loop_setup(conn, iso, read_only=True)
        wait_for(conn, loop, UD + ".Filesystem")
        iso_mnt = call(conn, loop, UD + ".Filesystem", "Mount", GLib.Variant("(a{sv})", ({"options": GLib.Variant("s", "ro")},))).unpack()[0]
        skip = {"sources/install.wim"} if split else set()
        total = tree_size(iso_mnt, skip)
        emit(ev="phase", phase="copy")
        meter = Meter("copy", total)
        copy_tree(iso_mnt, stick, skip, meter)
        meter.add(0, force=True)
        if split and not Stop.asked:
            emit(ev="phase", phase="split")
            sm = Meter("split", win["wimSize"])
            split_wim(os.path.join(iso_mnt, "sources", "install.wim"), os.path.join(stick, "sources", "install.swm"), sm)
        if Stop.asked:
            raise Fail("cancelled", "Stopped — the drive is half made; make it again or reset it")
        emit(ev="phase", phase="sync")
        os.sync()
    except OSError as e:
        why = "The drive is full" if e.errno == errno.ENOSPC else (e.strerror or str(e))
        raise Fail("io", why)
    finally:
        for path, mnt in ((part, stick), (loop, iso_mnt)):
            if path and mnt:
                try:
                    call(conn, path, UD + ".Filesystem", "Unmount", none)
                except Fail:
                    pass
        if loop:
            try:
                call(conn, loop, UD + ".Loop", "Delete", none)
            except Fail:
                pass
        if hold >= 0:
            os.close(hold)
    dev = text(objects(conn).get(whole, {}).get(UD + ".Block", {}).get("Device"))
    emit(ev="done", ok=True, verified=False, split=split, targets=[{"target": whole, "dev": dev, "ok": True, "code": "", "why": ""}],
         code="", why="")


# ── BENCHMARK ────────────────────────────────────────────────────────────
# Read-only on purpose: a write test has to overwrite the drive, and putting
# the data back after (as GNOME Disks does) does not survive a power cut.
# Read speed at BENCH_POINTS places from start to end — a spinning disk is
# slower at its end, a full flash drive sometimes too — and the time a
# random 4 KiB read takes. udisks' OpenForBenchmark is O_DIRECT, past the
# page cache, so what is measured is the drive; buffers are page-aligned
# (mmap), as O_DIRECT wants.

BENCH_POINTS = 24
BENCH_READ = 32 << 20
BENCH_ACCESS = 200


def bench(dev):
    import mmap
    import random
    if os.path.isfile(dev):
        fd = os.open(dev, os.O_RDONLY | os.O_CLOEXEC)
    else:
        _, GLib = gio()
        conn = bus()
        path = block_of(objects(conn), os.path.realpath(dev))
        emit(ev="phase", phase="open")
        r_, fdl = call(conn, path, UD + ".Block", "OpenForBenchmark", GLib.Variant("(a{sv})", ({},)), fds=True)
        fd = fdl.get(r_.unpack()[0])
    size = os.lseek(fd, 0, os.SEEK_END)
    if size < BENCH_READ * 2:
        os.close(fd)
        raise Fail("io", "It is too small to measure")
    buf = mmap.mmap(-1, CHUNK)
    small = mmap.mmap(-1, 4096)
    emit(ev="phase", phase="bench")
    meter = Meter("bench", BENCH_POINTS * BENCH_READ + BENCH_ACCESS * 4096)
    rates = []
    try:
        for i in range(BENCH_POINTS):
            if Stop.asked:
                break
            at = (size - BENCH_READ) * i // (BENCH_POINTS - 1) // MiB * MiB
            t0 = time.monotonic()
            got = 0
            while got < BENCH_READ:
                n = os.preadv(fd, [buf], at + got)
                if not n:
                    break
                got += n
            took = time.monotonic() - t0
            rates.append({"at": round(at / size, 4), "rate": int(got / took) if took > 0 else 0})
            meter.add(got)
        times = []
        for _ in range(BENCH_ACCESS):
            if Stop.asked:
                break
            at = random.randrange(0, size - 4096) // 4096 * 4096
            t0 = time.monotonic()
            os.preadv(fd, [small], at)
            times.append(time.monotonic() - t0)
            meter.add(4096)
    except OSError as e:
        raise Fail("io", "It could not be read: " + (e.strerror or str(e)))
    finally:
        os.close(fd)
    meter.add(0, force=True)
    if Stop.asked:
        raise Fail("cancelled", "Stopped")
    rs = [x["rate"] for x in rates]
    emit(ev="done", ok=True, rates=rates, avg=int(sum(rs) / len(rs)), min=min(rs), max=max(rs),
         accessMs=round(1000 * sum(times) / len(times), 2) if times else 0, why="")


# ── DISK IMAGES ──────────────────────────────────────────────────────────
# A file standing in for a drive: attached through udisks as a loop device
# (no password: it is yours), it is in the sidebar's Disk images and every
# tool here works on it — partition it, format it, write onto it.

def loop_setup(conn, path, read_only=False):
    Gio, GLib = gio()
    fd = os.open(path, (os.O_RDONLY if read_only else os.O_RDWR) | os.O_CLOEXEC)
    try:
        fdl = Gio.UnixFDList.new()
        idx = fdl.append(fd)
        opts = {"read-only": GLib.Variant("b", True)} if read_only else {}
        try:
            r_, _ = conn.call_with_unix_fd_list_sync(UD, "/org/freedesktop/UDisks2/Manager", UD + ".Manager", "LoopSetup",
                                                     GLib.Variant("(ha{sv})", (idx, opts)), GLib.VariantType("(o)"),
                                                     Gio.DBusCallFlags.ALLOW_INTERACTIVE_AUTHORIZATION, -1, fdl, None)
        except GLib.Error as e:
            raise Fail("io", (e.message or "").split(": ", 1)[-1] or "It could not be attached")
        return r_.unpack()[0]
    finally:
        os.close(fd)


def attach(path, read_only=False):
    path = os.path.abspath(path)
    if not os.path.isfile(path):
        raise Fail("source", "Not found: " + path)
    conn = bus()
    loop = loop_setup(conn, path, read_only)
    dev = text(wait_for(conn, loop, UD + ".Loop")[loop][UD + ".Block"].get("Device"))
    emit(ev="done", ok=True, dev=dev, why="")


def detach(dev):
    _, GLib = gio()
    conn = bus()
    objs = objects(conn)
    path = block_of(objs, dev)
    if UD + ".Loop" not in objs[path]:
        raise Fail("io", "It is not a disk image")
    # its partitions, and a filesystem on the whole of it (an ISO)
    unmount(conn, objs, Shim(path))
    if mounts_of(objs, path):
        call(conn, path, UD + ".Filesystem", "Unmount", GLib.Variant("(a{sv})", ({},)))
    call(conn, path, UD + ".Loop", "Delete", GLib.Variant("(a{sv})", ({},)))
    emit(ev="done", ok=True, why="")


def newimage(path, size, fs="", label=""):
    _, GLib = gio()
    path = os.path.abspath(path)
    if os.path.exists(path):
        raise Fail("source", "Something is already called that")
    size = int(size) // MiB * MiB
    if size < 4 * MiB:
        raise Fail("source", "Too small — at least 4 MiB")
    try:
        with open(path, "wb") as f:
            f.truncate(size)
    except OSError as e:
        raise Fail("io", "It cannot be made there: " + (e.strerror or str(e)))
    conn = bus()
    loop = loop_setup(conn, path)
    objs = wait_for(conn, loop, UD + ".Block")
    dev = text(objs[loop][UD + ".Block"].get("Device"))
    if fs:
        call(conn, loop, UD + ".Block", "Format", GLib.Variant("(sa{sv})", ("gpt", {})))
        wait_for(conn, loop, UD + ".PartitionTable")
        fopts = {"label": GLib.Variant("s", label)} if label else {}
        if fs in ("ext4", "btrfs", "xfs", "f2fs"):
            fopts["take-ownership"] = GLib.Variant("b", True)
        win = fs in ("vfat", "exfat", "ntfs")
        call(conn, loop, UD + ".PartitionTable", "CreatePartitionAndFormat",
             GLib.Variant("(ttssa{sv}sa{sv})", (MiB, 0, "EBD0A0A2-B9E5-4433-87C0-68B6B72699C7" if win
                                                else "0FC63DAF-8483-4772-8E79-3D69D8477DE4", label, {}, fs, fopts)))
    emit(ev="done", ok=True, dev=dev, path=path, why="")


# ── READING A WHOLE DRIVE ────────────────────────────────────────────────
# A clone's source and a backup's: udisks opens it read-only (polkit asks
# once, the system's own disk included — reading changes nothing).

def read_source(dev):
    if not dev.startswith("/dev/"):
        return Source(dev)
    _, GLib = gio()
    conn = bus()
    path = block_of(objects(conn), os.path.realpath(dev))
    emit(ev="phase", phase="open")
    r, fdl = call(conn, path, UD + ".Block", "OpenDevice", GLib.Variant("(sa{sv})", ("r", {"flags": GLib.Variant("i", os.O_CLOEXEC)})), fds=True)
    return Source(dev, fdl.get(r.unpack()[0]))


# ── BACKING UP ───────────────────────────────────────────────────────────
# A drive (or one volume) to a file: zstd on every core (.img.zst), or raw
# and sparse (.img: a run of zeros is a hole, not written). Written to
# OUT.part and renamed only when whole, so a stopped backup leaves nothing
# under the real name; a .sha256 beside it, of the file as written, which
# is what the write sheet checks a restore against.

HOLE = 64 << 10


def backup(dev, out, compress):
    src = read_source(dev)
    tmp = out + ".part"
    total = src.rawSize
    h = hashlib.sha256()
    try:
        f = open(tmp, "wb")
    except OSError as e:
        src.close()
        raise Fail("io", "It cannot be saved there: " + (e.strerror or str(e)))
    comp = zstd.ZstdCompressor(options={zstd.CompressionParameter.compression_level: 3,
                                        zstd.CompressionParameter.nb_workers: os.cpu_count() or 1}) if compress else None
    emit(ev="phase", phase="backup")
    meter = Meter("backup", total)
    buf = bytearray(CHUNK)
    zero = bytes(CHUNK)
    written = 0
    try:
        while not Stop.asked:
            n = src.fill(buf)
            if not n:
                break
            view = memoryview(buf)[:n]
            if comp:
                out_b = comp.compress(view, zstd.ZstdCompressor.CONTINUE)
                if out_b:
                    f.write(out_b)
                    h.update(out_b)
                    written += len(out_b)
            else:
                h.update(view)
                # holes at 64 KiB: a filesystem's empty room is rarely a
                # whole 4 MiB of nothing
                for i in range(0, n, HOLE):
                    piece = view[i:i + HOLE]
                    if piece == zero[:len(piece)]:
                        f.seek(len(piece), os.SEEK_CUR)
                    else:
                        f.write(piece)
                written += n
            meter.add(n)
        if comp and not Stop.asked:
            tail = comp.flush()
            f.write(tail)
            h.update(tail)
            written += len(tail)
        if not comp:
            f.truncate()
        f.close()
    except OSError as e:
        f.close()
        os.unlink(tmp)
        src.close()
        why = "The disk it was saving to is full" if e.errno == errno.ENOSPC else "It could not be read: " + (e.strerror or str(e))
        raise Fail("io", why)
    meter.add(0, force=True)
    src.close()
    if Stop.asked:
        os.unlink(tmp)
        raise Fail("cancelled", "Stopped — nothing was kept")
    os.replace(tmp, out)
    digest = h.hexdigest()
    try:
        with open(out + ".sha256", "w") as s_:
            s_.write("%s  %s\n" % (digest, os.path.basename(out)))
    except OSError:
        pass
    emit(ev="done", ok=True, out=out, read=meter.done, written=os.path.getsize(out), sha256=digest, why="")


# ── RENAMING ─────────────────────────────────────────────────────────────

def rename(dev, label=None, name=None):
    _, GLib = gio()
    conn = bus()
    objs = objects(conn)
    path = next((p for p, i in objs.items() if text(i.get(UD + ".Block", {}).get("Device")) == dev), None)
    if not path:
        raise Fail("removed", "The volume is not there any more")
    # the system's own volumes stay as they are, as everywhere in stylus
    mounts = [text(x) for x in objs[path].get(UD + ".Filesystem", {}).get("MountPoints", [])]
    if any(m in SYSTEM_MOUNTS for m in mounts):
        raise Fail("system", "The system stands on " + mounts[0])
    none = {}
    if label is not None:
        if UD + ".Filesystem" not in objs[path]:
            raise Fail("io", "There is no filesystem to label")
        call(conn, path, UD + ".Filesystem", "SetLabel", GLib.Variant("(sa{sv})", (label, none)))
    if name is not None:
        if UD + ".Partition" not in objs[path]:
            raise Fail("io", "It is not a partition")
        call(conn, path, UD + ".Partition", "SetName", GLib.Variant("(sa{sv})", (name, none)))
    emit(ev="done", ok=True, why="")


# ── LUKS ─────────────────────────────────────────────────────────────────

def block_of(objs, dev):
    path = next((p for p, i in objs.items() if text(i.get(UD + ".Block", {}).get("Device")) == dev), None)
    if not path:
        raise Fail("removed", "It is not there any more")
    return path


def unlock(dev, passphrase):
    _, GLib = gio()
    conn = bus()
    objs = objects(conn)
    path = block_of(objs, dev)
    if UD + ".Encrypted" not in objs[path]:
        raise Fail("io", "It is not encrypted")
    if not passphrase:
        raise Fail("auth", "No passphrase was given")
    try:
        r = call(conn, path, UD + ".Encrypted", "Unlock", GLib.Variant("(sa{sv})", (passphrase, {})))
    except Fail as e:
        # udisks' own words for a wrong one
        if "passphrase" in e.why.lower() or "key" in e.why.lower() or "Failed to activate" in e.why:
            raise Fail("auth", "That passphrase does not open it")
        raise
    emit(ev="done", ok=True, cleartext=r.unpack()[0], why="")


def lock(dev):
    _, GLib = gio()
    conn = bus()
    objs = objects(conn)
    path = block_of(objs, dev)
    none = GLib.Variant("(a{sv})", ({},))
    for q, j in objs.items():
        if j.get(UD + ".Block", {}).get("CryptoBackingDevice") == path:
            mounts = [text(m) for m in j.get(UD + ".Filesystem", {}).get("MountPoints", [])]
            if any(m in SYSTEM_MOUNTS for m in mounts):
                raise Fail("system", "The system stands on " + mounts[0])
            if mounts:
                call(conn, q, UD + ".Filesystem", "Unmount", none)
    call(conn, path, UD + ".Encrypted", "Lock", none)
    emit(ev="done", ok=True, why="")


# ── SURFACE SCAN ─────────────────────────────────────────────────────────
# Every sector read once, nothing written: a 4 MiB read that fails is read
# again 4 KiB at a time to say where, and the page cache let go of as it
# goes (fadvise) so a scan does not push everything else out of memory.

SCAN_UNIT = 4096
MAX_BAD = 2000


def scan(dev):
    if os.path.isfile(dev):
        fd = os.open(dev, os.O_RDONLY | os.O_CLOEXEC)
        gone = lambda: not os.path.exists(dev)
    else:
        _, GLib = gio()
        conn = bus()
        path = block_of(objects(conn), dev)
        emit(ev="phase", phase="open")
        r, fdl = call(conn, path, UD + ".Block", "OpenDevice", GLib.Variant("(sa{sv})", ("r", {})), fds=True)
        fd = fdl.get(r.unpack()[0])
        gone = lambda: not os.path.exists("/sys/class/block/" + os.path.basename(dev))
    size = os.lseek(fd, 0, os.SEEK_END)
    emit(ev="phase", phase="scan")
    meter = Meter("scan", size)
    buf = bytearray(CHUNK)
    bad = []
    off = 0
    since = 0
    try:
        while off < size and not Stop.asked:
            n = min(CHUNK, size - off)
            try:
                os.preadv(fd, [memoryview(buf)[:n]], off)
            except OSError:
                if gone():
                    raise Fail("removed", "The drive was taken out")
                for u in range(off, off + n, SCAN_UNIT):
                    try:
                        os.preadv(fd, [memoryview(buf)[:SCAN_UNIT]], u)
                    except OSError:
                        bad.append(u // 512)
                if len(bad) > MAX_BAD:
                    break
            off += n
            since += n
            if since >= SYNC_EVERY:
                since = 0
                try:
                    os.posix_fadvise(fd, 0, off, os.POSIX_FADV_DONTNEED)
                except OSError:
                    pass
            meter.add(n)
    finally:
        os.close(fd)
    meter.add(0, force=True)
    if Stop.asked:
        raise Fail("cancelled", "Stopped at " + str(round(100 * off / size)) + "%")
    emit(ev="done", ok=not bad, bad=bad[:200], badCount=len(bad), read=off, why=("" if not bad else
         (str(len(bad)) + (" unreadable sectors" if len(bad) != 1 else " unreadable sector")
          + (" (stopped counting)" if len(bad) > MAX_BAD else ""))))


# ── PARTITIONS ───────────────────────────────────────────────────────────
# Everything through udisks, polkit asking once; the system's own disk is
# refused whole — even its free space — as everywhere in stylus.

MiB = 1 << 20
RESIZE_FS = ("ext4", "vfat", "exfat", "ntfs", "btrfs", "xfs", "f2fs")
# libblockdev's BDFSResizeFlags, as udisks' CanResize hands them on
OFFLINE_SHRINK, OFFLINE_GROW, ONLINE_SHRINK, ONLINE_GROW = 2, 4, 8, 16


def resizable():
    conn = bus()
    _, GLib = gio()
    out = {}
    for fs in RESIZE_FS:
        try:
            r = conn.call_sync(UD, "/org/freedesktop/UDisks2/Manager", UD + ".Manager", "CanResize",
                               GLib.Variant("(s)", (fs,)), None, 0, -1, None)
            ok, mode, _ = r.unpack()[0]
        except GLib.Error:
            ok, mode = False, 0
        out[fs] = {"shrink": bool(ok and mode & (OFFLINE_SHRINK | ONLINE_SHRINK)),
                   "grow": bool(ok and mode & (OFFLINE_GROW | ONLINE_GROW)),
                   "onlineShrink": bool(ok and mode & ONLINE_SHRINK), "onlineGrow": bool(ok and mode & ONLINE_GROW),
                   "offlineShrink": bool(ok and mode & OFFLINE_SHRINK), "offlineGrow": bool(ok and mode & OFFLINE_GROW)}
    print(json.dumps(out))


def not_system(objs, whole_path):
    dev = text(objs[whole_path].get(UD + ".Block", {}).get("Device"))
    if os.path.basename(dev) in system_disks():
        raise Fail("system", "The system runs from this drive")


def table_of_part(objs, path):
    t = objs[path].get(UD + ".Partition", {}).get("Table", "/")
    if t == "/" or t not in objs:
        raise Fail("io", "It is not a partition")
    return t


def mounts_of(objs, path):
    return [text(m) for m in objs[path].get(UD + ".Filesystem", {}).get("MountPoints", [])]


def create(drive, offset, size, fs="", label="", name="", ptype="", passphrase=None):
    _, GLib = gio()
    conn = bus()
    objs = objects(conn)
    path = block_of(objs, drive)
    not_system(objs, path)
    if UD + ".PartitionTable" not in objs[path]:
        # a blank drive gets a table; one holding a filesystem bare is not blank
        if objs[path].get(UD + ".Block", {}).get("IdUsage"):
            raise Fail("io", "It holds a filesystem with no partition table — erase it first")
        emit(ev="phase", phase="table")
        call(conn, path, UD + ".Block", "Format", GLib.Variant("(sa{sv})", ("gpt", {})))
        objs = objects(conn)
    kind = objs[path][UD + ".PartitionTable"].get("Type", "")
    popts = {}
    if kind == "dos":
        popts["partition-type"] = GLib.Variant("s", "primary")
        if ptype and not ptype.startswith("0x"):
            ptype = "0x" + ptype
    offset = (int(offset) + MiB - 1) // MiB * MiB
    size = int(size) // MiB * MiB
    emit(ev="phase", phase="create")
    if fs:
        fopts = {}
        if label:
            fopts["label"] = GLib.Variant("s", label)
        if fs in ("ext4", "btrfs", "xfs", "f2fs"):
            # the new filesystem's top directory yours, not root's
            fopts["take-ownership"] = GLib.Variant("b", True)
        if passphrase is not None:
            if not passphrase:
                raise Fail("auth", "No passphrase was given")
            fopts["encrypt.passphrase"] = GLib.Variant("s", passphrase)
            fopts["encrypt.type"] = GLib.Variant("s", "luks2")
        r = call(conn, path, UD + ".PartitionTable", "CreatePartitionAndFormat",
                 GLib.Variant("(ttssa{sv}sa{sv})", (offset, size, ptype, name, popts, fs, fopts)))
    else:
        r = call(conn, path, UD + ".PartitionTable", "CreatePartition",
                 GLib.Variant("(ttssa{sv})", (offset, size, ptype, name, popts)))
    emit(ev="done", ok=True, created=r.unpack()[0], why="")


def delete(dev):
    _, GLib = gio()
    conn = bus()
    objs = objects(conn)
    path = block_of(objs, dev)
    not_system(objs, table_of_part(objs, path))
    none = GLib.Variant("(a{sv})", ({},))
    for q, j in objs.items():
        if j.get(UD + ".Block", {}).get("CryptoBackingDevice") == path:
            if mounts_of(objs, q):
                call(conn, q, UD + ".Filesystem", "Unmount", none)
            call(conn, path, UD + ".Encrypted", "Lock", none)
    if mounts_of(objs, path):
        call(conn, path, UD + ".Filesystem", "Unmount", none)
    call(conn, path, UD + ".Partition", "Delete", GLib.Variant("(a{sv})", ({"tear-down": GLib.Variant("b", True)},)))
    emit(ev="done", ok=True, why="")


def resize(dev, size):
    _, GLib = gio()
    conn = bus()
    objs = objects(conn)
    path = block_of(objs, dev)
    not_system(objs, table_of_part(objs, path))
    if UD + ".Encrypted" in objs[path]:
        raise Fail("io", "An encrypted volume is not resized from here yet")
    size = int(size) // MiB * MiB
    now = objs[path][UD + ".Partition"].get("Size", 0)
    grow = size > now
    fstype = objs[path][UD + ".Block"].get("IdType", "")
    has_fs = UD + ".Filesystem" in objs[path]
    none = GLib.Variant("(a{sv})", ({},))
    was = mounts_of(objs, path)
    if has_fs:
        r = conn.call_sync(UD, "/org/freedesktop/UDisks2/Manager", UD + ".Manager", "CanResize",
                           GLib.Variant("(s)", (fstype,)), None, 0, -1, None)
        ok, mode, _ = r.unpack()[0]
        online = mode & (ONLINE_GROW if grow else ONLINE_SHRINK)
        offline = mode & (OFFLINE_GROW if grow else OFFLINE_SHRINK)
        if not ok or not (online or offline):
            raise Fail("io", "%s cannot be %s" % (fstype or "This filesystem", "grown" if grow else "shrunk"))
        # mounted or not, as the filesystem's tool needs it
        if was and not online:
            emit(ev="phase", phase="unmount")
            call(conn, path, UD + ".Filesystem", "Unmount", none)
        elif not was and not offline:
            emit(ev="phase", phase="mount")
            call(conn, path, UD + ".Filesystem", "Mount", none)
    try:
        if grow:
            emit(ev="phase", phase="partition")
            call(conn, path, UD + ".Partition", "Resize", GLib.Variant("(ta{sv})", (size, {})))
            if has_fs:
                emit(ev="phase", phase="filesystem")
                # 0: to fill the partition
                call(conn, path, UD + ".Filesystem", "Resize", GLib.Variant("(ta{sv})", (0, {})))
        else:
            if has_fs:
                emit(ev="phase", phase="filesystem")
                call(conn, path, UD + ".Filesystem", "Resize", GLib.Variant("(ta{sv})", (size, {})))
            emit(ev="phase", phase="partition")
            call(conn, path, UD + ".Partition", "Resize", GLib.Variant("(ta{sv})", (size, {})))
    finally:
        # back the way it was found
        objs = objects(conn)
        now_mounted = mounts_of(objs, path) if path in objs else []
        try:
            if was and not now_mounted:
                call(conn, path, UD + ".Filesystem", "Mount", none)
            elif not was and now_mounted:
                call(conn, path, UD + ".Filesystem", "Unmount", none)
        except Fail:
            pass
    emit(ev="done", ok=True, why="")


def main():
    a = sys.argv[1:]
    signal.signal(signal.SIGTERM, on_term)
    signal.signal(signal.SIGINT, on_term)
    cmd = a[0] if a else ""
    try:
        if cmd == "drives":
            print(json.dumps(drive_list()))
        elif cmd == "watch":
            watch()
        elif cmd == "probe" and len(a) > 1:
            print(json.dumps(probe(a[1])))
        elif cmd == "sums" and len(a) > 1:
            sums(a[1], a[a.index("--expect") + 1] if "--expect" in a[:-1] else "")
        elif cmd == "unlock" and len(a) > 1:
            unlock(a[1], sys.stdin.readline().rstrip("\n"))
        elif cmd == "lock" and len(a) > 1:
            lock(a[1])
        elif cmd == "scan" and len(a) > 1:
            scan(a[1])
        elif cmd == "resizable":
            resizable()
        elif cmd == "create" and len(a) > 3:
            opt = lambda k: a[a.index(k) + 1] if k in a[:-1] else ""
            create(a[1], a[2], a[3], opt("--fs"), opt("--label"), opt("--name"), opt("--type"),
                   sys.stdin.readline().rstrip("\n") if "--encrypt" in a else None)
        elif cmd == "delete" and len(a) > 1:
            delete(a[1])
        elif cmd == "resize" and len(a) > 2:
            resize(a[1], a[2])
        elif cmd == "catalog":
            catalog()
        elif cmd == "download" and len(a) > 3:
            pair = lambda k: (a[a.index(k) + 1], a[a.index(k) + 2]) if k in a[:-2] else None
            download(a[1], a[2], a[3], pair("--sums"), pair("--sig"), a[a.index("--sha256") + 1] if "--sha256" in a[:-1] else "")
        elif cmd == "sig" and len(a) > 1:
            sig(a[1])
        elif cmd == "fetchkey" and len(a) > 1:
            fetchkey(a[1])
        elif cmd == "bench" and len(a) > 1:
            bench(a[1])
        elif cmd == "newimage" and len(a) > 2:
            opt = lambda k: a[a.index(k) + 1] if k in a[:-1] else ""
            newimage(a[1], a[2], opt("--fs"), opt("--label"))
        elif cmd == "attach" and len(a) > 1:
            attach(a[1], "--ro" in a)
        elif cmd == "detach" and len(a) > 1:
            detach(a[1])
        elif cmd == "windows" and len(a) > 2:
            windows(a[1], a[2])
        elif cmd == "backup" and len(a) > 2:
            backup(a[1], a[2], "--raw" not in a)
        elif cmd == "rename" and len(a) > 1:
            label = a[a.index("--label") + 1] if "--label" in a[:-1] else None
            name = a[a.index("--name") + 1] if "--name" in a[:-1] else None
            rename(a[1], label, name)
        elif cmd == "write" and len(a) > 2:
            rest = [x for x in a[1:] if x != "--no-verify"]
            write(rest[0], rest[1:], verify="--no-verify" not in a)
        else:
            sys.stderr.write("usage: forge.py drives | watch | probe FILE | sums FILE [--expect HEX]"
                             " | write SOURCE TARGET... [--no-verify] | rename DEV [--label T] [--name T]"
                             " | unlock DEV (passphrase on stdin) | lock DEV | scan DEV"
                             " | resizable | create DRIVE OFFSET SIZE [--fs F --label L --name N --type T --encrypt]"
                             " | delete DEV | resize DEV SIZE | backup DEV OUT [--raw] | windows ISO DRIVE\n")
            return 2
    except Fail as e:
        emit(ev="done", ok=False, code=e.code, why=e.why)
        return 1
    except FileNotFoundError as e:
        emit(ev="done", ok=False, code="source", why="Not found: " + (e.filename or ""))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

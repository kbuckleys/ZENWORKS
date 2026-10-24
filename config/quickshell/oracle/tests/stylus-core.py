#!/usr/bin/env python3
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# stylus' backend (stylus/core/forge.py), against images made here: ISOs
# built by bsdtar (a Linux-like one, a Windows-like one, a hybrid), each
# compression it unpacks, the sums files downloads come with, and writes to
# regular files standing in for drives. No drive is touched.

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
FORGE = os.path.join(HERE, "..", "..", "stylus", "core", "forge.py")
sys.path.insert(0, os.path.dirname(FORGE))
import forge  # noqa: E402

TMP = tempfile.mkdtemp(prefix="stylus-test-")
fails, count = [], 0


def eq(name, got, want):
    global count
    count += 1
    if got != want:
        fails.append("%s\n      want %r\n      got  %r" % (name, want, got))


def run(*args):
    r = subprocess.run([sys.executable, FORGE] + list(args), capture_output=True, text=True, timeout=60)
    lines = [json.loads(l) for l in r.stdout.splitlines() if l.strip()]
    return r.returncode, lines


def iso(name, files):
    d = os.path.join(TMP, name + ".d")
    for rel, data in files.items():
        p = os.path.join(d, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "wb") as f:
            f.write(data)
    out = os.path.join(TMP, name + ".iso")
    subprocess.run(["bsdtar", "--format", "iso9660", "--options", "volume-id=" + name.upper(),
                    "-cf", out, "-C", d, "."], check=True)
    return out


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


try:
    noise = os.urandom(3 << 20) + bytes(2 << 20)
    linux = iso("linux", {"boot/vmlinuz": noise, "arch/x86_64/airootfs.sfs": b"x" * 9000})
    win = iso("windows", {"sources/install.wim": b"w" * 70000, "efi/boot/bootx64.efi": b"e", "bootmgr": b"b"})
    hybrid = os.path.join(TMP, "hybrid.iso")
    with open(linux, "rb") as f:
        data = bytearray(f.read())
    data[510:512] = b"\x55\xaa"
    with open(hybrid, "wb") as f:
        f.write(data)
    disk = os.path.join(TMP, "pi.img")
    with open(disk, "wb") as f:
        f.write(bytes(512) + b"EFI PART" + os.urandom(1 << 20))

    # ── probe ────────────────────────────────────────────────────────────
    p = forge.probe(linux)
    eq("plain iso kind", p["kind"], "iso")
    eq("iso label", p["label"], "LINUX")
    eq("plain iso size known", p["rawSize"], os.path.getsize(linux))
    p = forge.probe(hybrid)
    eq("hybrid kind", p["kind"], "hybrid")
    eq("hybrid table", p["table"], "mbr")
    p = forge.probe(win)
    eq("windows kind", p["kind"], "windows")
    eq("windows wim", (p["windows"] or {}).get("wim"), "sources/install.wim")
    eq("windows wim size", (p["windows"] or {}).get("wimSize"), 70000)
    eq("windows fits fat32", (p["windows"] or {}).get("split"), False)
    eq("windows uefi", (p["windows"] or {}).get("uefi"), True)
    p = forge.probe(disk)
    eq("disk image kind", p["kind"], "disk")
    eq("disk image table", p["table"], "gpt")

    # ── each compression, unpacked on the way ────────────────────────────
    want = sha(hybrid)
    packed = {}
    for tool, ext in (("xz", "xz"), ("zstd", "zst"), ("gzip", "gz"), ("bzip2", "bz2")):
        out = hybrid + "." + ext
        with open(out, "wb") as f:
            subprocess.run([tool, "-c", hybrid], stdout=f, check=True)
        packed[ext] = out
    zp = os.path.join(TMP, "hybrid.zip")
    with zipfile.ZipFile(zp, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("README.txt", "readme")
        z.write(hybrid, "hybrid.iso")
    packed["zip"] = zp
    for ext, path in packed.items():
        p = forge.probe(path)
        eq(ext + " seen", p["compressed"], ext)
        eq(ext + " still hybrid inside", p["kind"], "hybrid")
        if ext in ("xz", "zst", "zip"):
            eq(ext + " size known", p["rawSize"], len(data))
        out = os.path.join(TMP, "out-" + ext + ".img")
        code, lines = run("write", path, out)
        last = lines[-1] if lines else {}
        eq(ext + " write ok", (code, last.get("ok")), (0, True))
        eq(ext + " written bytes", last.get("written"), len(data))
        eq(ext + " target matches", sha(out), want)
        eq(ext + " verified", last.get("verified"), True)
        phases = [l["phase"] for l in lines if l.get("ev") == "phase"]
        eq(ext + " phases (no drive: no unmount)", phases, ["open", "write", "sync", "verify"])

    # two targets at once, and --no-verify
    a, b = os.path.join(TMP, "a.img"), os.path.join(TMP, "b.img")
    code, lines = run("write", linux, a, b, "--no-verify")
    eq("two targets", [t["ok"] for t in lines[-1]["targets"]], [True, True])
    eq("both match", (sha(a), sha(b)), (sha(linux), sha(linux)))
    eq("no verify phase", "verify" in [l.get("phase") for l in lines if l.get("ev") == "phase"], False)

    # a damaged download
    bad = os.path.join(TMP, "bad.img.xz")
    with open(packed["xz"], "rb") as f:
        raw = bytearray(f.read())
    raw[len(raw) // 2] ^= 0xFF
    with open(bad, "wb") as f:
        f.write(raw)
    code, lines = run("write", bad, os.path.join(TMP, "bad.img"))
    eq("damaged xz refused", (lines[-1].get("ok"), lines[-1].get("code")), (False, "source"))
    code, lines = run("write", os.path.join(TMP, "missing.iso"), os.path.join(TMP, "x.img"))
    eq("missing source", lines[-1].get("code"), "source")
    zjunk = os.path.join(TMP, "empty.zip")
    with zipfile.ZipFile(zjunk, "w") as z:
        z.writestr("dir/", "")
    code, lines = run("write", zjunk, os.path.join(TMP, "x.img"))
    eq("zip without an image", lines[-1].get("code"), "source")

    # ── sums beside the download ─────────────────────────────────────────
    h = sha(linux)
    eq("gnu line", forge.sums_in(h + "  linux.iso\n", "linux.iso"), ("sha256", h))
    eq("gnu binary mark", forge.sums_in(h + " *./linux.iso\n", "linux.iso"), ("sha256", h))
    eq("bsd line", forge.sums_in("# Fedora\nSHA256 (linux.iso) = " + h + "\n", "linux.iso"), ("sha256", h))
    eq("other file's line", forge.sums_in(h + "  other.iso\n", "linux.iso"), None)
    eq("bare hex only when named after it", forge.sums_in(h + "\n", "linux.iso"), None)
    eq("bare hex", forge.sums_in(h + "\n", "linux.iso", alone=True), ("sha256", h))
    md5 = hashlib.md5(open(linux, "rb").read()).hexdigest()
    eq("md5 by length", forge.sums_in(md5 + "  linux.iso", "linux.iso"), ("md5", md5))
    with open(os.path.join(TMP, "SHA256SUMS"), "w") as f:
        f.write("%s  windows.iso\n%s  linux.iso\n" % ("0" * 64, h))
    s = forge.sidecar(linux)
    eq("SHA256SUMS found", (s or {}).get("expected"), h)
    code, lines = run("sums", linux)
    eq("sums match", (lines[-1].get("ok"), lines[-1].get("checked")), (True, True))
    code, lines = run("sums", win)
    eq("sums mismatch", (lines[-1].get("ok"), lines[-1].get("checked")), (False, True))
    code, lines = run("sums", disk)
    eq("no sums: hash only", (lines[-1].get("ok"), lines[-1].get("checked"), lines[-1].get("got")),
       (True, False, sha(disk)))
    code, lines = run("sums", disk, "--expect", sha(disk).upper())
    eq("pasted hash", (lines[-1].get("ok"), lines[-1].get("checked")), (True, True))

    # ── backing up, and restoring the backup ─────────────────────────────
    for flag, ext in (([], ".img.zst"), (["--raw"], ".img")):
        out = os.path.join(TMP, "backup" + ext)
        code, lines = run("backup", hybrid, out, *flag)
        last = lines[-1] if lines else {}
        eq("backup " + ext, (code, last.get("ok"), last.get("read")), (0, True, len(data)))
        eq("no .part left " + ext, os.path.exists(out + ".part"), False)
        code, lines = run("sums", out)
        eq("its sidecar matches " + ext, (lines[-1].get("ok"), lines[-1].get("checked")), (True, True))
        back = os.path.join(TMP, "restored" + ext + ".bin")
        code, lines = run("write", out, back)
        eq("restored " + ext, (lines[-1].get("ok"), sha(back)), (True, want))
    code, lines = run("backup", hybrid, "/nonexistent-dir/x.img.zst")
    eq("an unwritable place said", (lines[-1].get("ok"), lines[-1].get("code")), (False, "io"))

    # ── the system's own disk ────────────────────────────────────────────
    root = forge.system_disks()
    eq("system disk found", bool(root), True)
finally:
    shutil.rmtree(TMP, ignore_errors=True)

for f in fails:
    print("  FAIL " + f)
print("stylus core: %d passed, %d failed" % (count - len(fails), len(fails)))
sys.exit(1 if fails else 0)

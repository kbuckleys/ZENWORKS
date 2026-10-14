# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# CLIO'S BACKEND — the notebook on disk, JSON lines on stdin/stdout (the
# suite's loop: morpheus/py/lines.py). Started while clio's window is open,
# gone a minute after.
#
#   load                     every note and entry, the containers and journals,
#                            and whether a password is set
#   save {note, seal}        one note, written whole (atomically); `seal`:
#                            its blocks encrypted, only its head readable
#   remove {id}              a note gone for good, its attachments with it
#                            (save those another note still uses)
#   meta {meta}              the containers and journals
#   attach {id, path}        a file copied in beside a note → its block (one
#                            already in Clio: the same file, not a copy)
#   attachDir {id}           where a note's files live (a sketch is saved
#                            there by the window itself)
#   pasteImage {id}          a picture on the clipboard, kept → its block;
#                            {none: true} when the clipboard holds words
#   ocr {src}                the words in a picture (tesseract)
#   pdf {pages, out, dpi}    pages the window drew, into one PDF
#   print {path}             a PDF to the printer (lp), where there is one
#   copyText {text}          words onto the clipboard
#   export {path, text, files}   a note written out, its files beside it
#   password {password, hint, old}   the Clio password set or changed —
#                            every sealed note sealed again under the new one
#   unlock {password} · lockNow · unseal {id}
#
# THE LOCK. One Clio password, as Apple's Notes has: PBKDF2-SHA256 (600 000
# rounds, a random salt) makes 64 bytes of key from it — half encrypts (as
# the passphrase handed to `openssl enc -aes-256-cbc -pbkdf2` through a
# pipe, never argv, where any user can read it), half signs what was
# encrypted (HMAC-SHA256, checked before anything is decrypted). The key
# lives here only while unlocked; the password itself never stays.
#
# Layout: ~/Documents/Clio/{Notes/<id>.json, Journals/<id>.json (the
# entries), Attachments/<file>, and,
# hidden, .meta.json, .lock.json, .stickies.json, .moved.json}. Attachments
# are SHARED: one directory, a block's `src` a name in it, and a file put in
# twice (the tray) one file used twice — it goes when nothing uses it. — one directory, read from where
# it is written, so copied to another machine it is the same notebook
# there. CLIO_DIR overrides it (the tests). What was kept in the old place
# ($XDG_DATA_HOME/clio) is moved over the first time (migrate).

import base64
import hashlib
import hmac
import json
import os
import secrets
import shutil
import subprocess
import sys
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), "morpheus", "py"))

import lines  # noqa: E402

PROTOCOL = 1
ROUNDS = 600000
IMAGES = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".svg", ".avif", ".heic", ".tif", ".tiff"}


class ClioError(Exception):
    def __init__(self, text, kind="failed"):
        super().__init__(text)
        self.kind = kind


# the notebook's own bookkeeping, hidden: what a person browsing the
# directory wants is their notes and files
META, LOCK, MOVED = ".meta.json", ".lock.json", ".moved.json"
ATT = "Attachments"
SHOWN = {"meta.json": META, "lock.json": LOCK, "stickies.json": ".stickies.json"}


def root():
    return os.environ.get("CLIO_DIR") or os.path.expanduser("~/Documents/Clio")


def old_root():
    return os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"), "clio")


def migrate():
    # Each thing the old place holds, moved in unless the new place has one
    # already (the stickies' file can be there first: the board writes it
    # before this ever starts). The old directory goes once it is empty.
    if os.environ.get("CLIO_DIR"):
        return
    old, new = old_root(), root()
    if not os.path.isdir(old) or os.path.realpath(old) == os.path.realpath(new):
        return
    os.makedirs(new, exist_ok=True)
    for name in os.listdir(old):
        src, dst = os.path.join(old, name), os.path.join(new, name)
        if os.path.isdir(src) and os.path.isdir(dst):
            for sub in os.listdir(src):
                if not os.path.exists(os.path.join(dst, sub)):
                    shutil.move(os.path.join(src, sub), os.path.join(dst, sub))
            continue
        if not os.path.exists(dst):
            shutil.move(src, dst)
    # only empty directories left behind: everything made it over
    if not any(files for _, _, files in os.walk(old)):
        shutil.rmtree(old, ignore_errors=True)


def path_of(*parts):
    return os.path.join(root(), *parts)


def att(*parts):
    return path_of(ATT, *parts)


def in_att(src):
    # a block's src as a path in Attachments, never out of it
    home = os.path.realpath(att())
    p = os.path.realpath(att(str(src)))
    return p if p.startswith(home + os.sep) else None


# notes and journal entries, each kind in its own directory
KINDS = {"note": "Notes", "entry": "Journals"}


def note_path(i, kind=None):
    # where note `i` is written: by its kind when it is known, otherwise
    # wherever it already is (a journal entry, or else a note)
    if kind is not None:
        return path_of(KINDS.get(kind, "Notes"), i + ".json")
    for d in ("Journals", "Notes"):
        p = path_of(d, i + ".json")
        if os.path.exists(p):
            return p
    return path_of("Notes", i + ".json")


def note_files():
    # every note's and entry's file
    out = []
    for d in KINDS.values():
        dd = path_of(d)
        for n in sorted(os.listdir(dd)) if os.path.isdir(dd) else []:
            if n.endswith(".json"):
                out.append(os.path.join(dd, n))
    return out


def safe_id(i):
    i = str(i or "")
    if not i or "/" in i or i.startswith(".") or len(i) > 80:
        raise ClioError("Not a note: " + i)
    return i


def write_atomic(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".part"
    with open(tmp, "wb") as f:
        f.write(data if isinstance(data, bytes) else data.encode("utf-8"))
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def read_json(path, fallback):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return fallback


# ── THE KEY ───────────────────────────────────────────────────────────────
def derive(password, salt):
    return hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, ROUNDS, 64)


def check_of(key):
    return base64.b64encode(hmac.new(key[32:], b"clio-check", hashlib.sha256).digest()).decode()


def _openssl(args, data, passphrase):
    r, w = os.pipe()
    try:
        os.write(w, passphrase.encode() + b"\n")
    finally:
        os.close(w)
    try:
        p = subprocess.run(["openssl", "enc", "-aes-256-cbc", "-pbkdf2", "-iter", "1000",
                            "-pass", "fd:%d" % r] + args,
                           input=data, capture_output=True, pass_fds=(r,), timeout=30)
    finally:
        os.close(r)
    if p.returncode != 0:
        raise ClioError("openssl: " + p.stderr.decode(errors="replace").strip()[:200])
    return p.stdout


def seal(key, obj):
    data = json.dumps(obj, ensure_ascii=False).encode("utf-8")
    cipher = _openssl(["-salt"], data, key[:32].hex())
    mac = hmac.new(key[32:], cipher, hashlib.sha256).digest()
    return "v1:" + base64.b64encode(mac).decode() + ":" + base64.b64encode(cipher).decode()


def unseal(key, text):
    try:
        v, mac, cipher = str(text).split(":", 2)
        mac = base64.b64decode(mac)
        cipher = base64.b64decode(cipher)
    except ValueError:
        raise ClioError("A locked note that cannot be read")
    if v != "v1" or not hmac.compare_digest(mac, hmac.new(key[32:], cipher, hashlib.sha256).digest()):
        raise ClioError("A locked note sealed with another password", "auth")
    return json.loads(_openssl(["-d"], cipher, key[:32].hex()).decode("utf-8"))


class Server(lines.Service):
    def __init__(self):
        super().__init__()
        self.key = None
        self.lock = threading.Lock()

    def failure(self, e):
        if isinstance(e, ClioError):
            return {"kind": e.kind, "error": str(e)}
        if isinstance(e, OSError):
            return {"kind": "failed", "error": e.strerror or str(e)}
        return None

    # ── reading ──
    def load(self):
        notes = []
        for p in note_files():
            j = read_json(p, None)
            if isinstance(j, dict) and j.get("id"):
                # when it was written, as read: a save sends it back, and a
                # file changed since (another machine, synced) is not
                # written over (save)
                j["_disk"] = os.path.getmtime(p)
                notes.append(j)
        lk = read_json(path_of(LOCK), {})
        return {"notes": notes, "meta": read_json(path_of(META), {}),
                "password": bool(lk.get("check")), "hint": lk.get("hint", ""),
                "unlocked": self.key is not None, "root": root()}

    # ── writing ──
    def save(self, args):
        note = dict(args.get("note") or {})
        i = safe_id(note.get("id"))
        if args.get("seal"):
            if self.key is None:
                raise ClioError("Unlock first", "locked")
            blocks = note.pop("blocks", None)
            if blocks is not None:
                note["sealed"] = seal(self.key, blocks)
                # the files it uses, said in the clear, so another note's
                # deletion leaves them and its own takes them (the names
                # are on disk in the clear anyway: attachments are not sealed)
                note["uses"] = sorted({str(b["src"]) for b in blocks if isinstance(b, dict) and b.get("src")})
        note.pop("_disk", None)
        p = note_path(i, "entry" if note.get("kind") == "entry" else "note")
        with self.lock:
            # THE SYNC GUARD. The file changed since it was read (another
            # machine wrote it, and it came over): neither is lost. What is
            # here goes in as a copy beside it, and the window is handed the
            # other one to show.
            expect = args.get("expect")
            if expect and os.path.exists(p) and abs(os.path.getmtime(p) - float(expect)) > 0.001:
                disk = read_json(p, None)
                if isinstance(disk, dict) and disk.get("id"):
                    copy = dict(note, id=i[0] + secrets.token_hex(6), conflictOf=i)
                    bs = copy.get("blocks")
                    if isinstance(bs, list) and bs and isinstance(bs[0], dict):
                        bs = [dict(b) for b in bs]
                        bs[0]["h"] = str(bs[0].get("h") or "") + " (this machine)"
                        copy["blocks"] = bs
                    cp = os.path.join(os.path.dirname(p), copy["id"] + ".json")
                    write_atomic(cp, json.dumps(copy, ensure_ascii=False, indent=1))
                    disk["_disk"] = os.path.getmtime(p)
                    copy["_disk"] = os.path.getmtime(cp)
                    return {"conflict": True, "disk": disk, "copy": copy}
            write_atomic(p, json.dumps(note, ensure_ascii=False, indent=1))
        return {"sealed": "sealed" in note and note["sealed"] or "", "mtime": os.path.getmtime(p)}

    def remove(self, args):
        i = safe_id(args.get("id"))
        gone = self.srcs_of(read_json(note_path(i), {}))
        try:
            os.remove(note_path(i))
        except FileNotFoundError:
            pass
        # its files go with it, save those another note uses as well
        keep = self.used(skip=i)
        for src in gone - keep:
            p = in_att(src)
            if p and os.path.isfile(p):
                os.remove(p)
        return {}

    @staticmethod
    def srcs_of(j):
        out = set()
        if not isinstance(j, dict):
            return out
        for b in j.get("blocks") or []:
            if isinstance(b, dict) and b.get("src"):
                out.add(str(b["src"]))
        for u in j.get("uses") or []:
            out.add(str(u))
        return out

    def used(self, skip=""):
        # every attachment a note points at: its blocks' sources, and for a
        # locked note (blocks sealed) the list it keeps in the clear (`uses`)
        out = set()
        for p in note_files():
            if os.path.basename(p) != skip + ".json":
                out |= self.srcs_of(read_json(p, None))
        return out

    def meta(self, args):
        write_atomic(path_of(META), json.dumps(args.get("meta") or {}, ensure_ascii=False, indent=1))
        return {}

    # ── files ──
    @staticmethod
    def free(d, name):
        base, ext = os.path.splitext(name or "file")
        base = base.replace("/", "_")[:80] or "file"
        cand, n = base + ext, 2
        while os.path.exists(os.path.join(d, cand)):
            cand = "%s %d%s" % (base, n, ext)
            n += 1
        return cand

    def block_for(self, name):
        ext = os.path.splitext(name)[1].lower()
        return {"k": "image" if ext in IMAGES else "file", "src": name, "name": name,
                "size": os.path.getsize(att(name))}

    def attach(self, args):
        i = safe_id(args.get("id"))
        src = os.path.expanduser(str(args.get("path") or ""))
        if not os.path.isfile(src):
            raise ClioError("Not a file: " + src)
        # one already in Clio (the tray, a drag from another note): the same
        # file, not a copy — `remove` keeps it while anything still uses it
        home = os.path.realpath(att())
        real = os.path.realpath(src)
        if real.startswith(home + os.sep):
            return self.block_for(os.path.relpath(real, home))
        os.makedirs(att(), exist_ok=True)
        name = self.free(att(), os.path.basename(src))
        shutil.copy2(src, att(name))
        return self.block_for(name)

    def attach_dir(self, args):
        safe_id(args.get("id"))
        os.makedirs(att(), exist_ok=True)
        name = self.free(att(), str(args.get("name") or "Sketch.png"))
        return {"dir": att(), "name": name, "src": name}

    def paste_image(self, args):
        i = safe_id(args.get("id"))
        try:
            types = subprocess.run(["wl-paste", "--list-types"], capture_output=True, timeout=5).stdout.decode().split()
        except (OSError, subprocess.TimeoutExpired):
            return {"none": True}
        words = any(t.startswith("text/") for t in types)
        pic = next((t for t in ("image/png", "image/jpeg", "image/webp", "image/gif") if t in types), None)
        # a copied picture from a browser comes with its html too: words win
        # unless there is nothing but the picture and a file name
        if pic is None or (words and "text/html" in types):
            return {"none": True}
        data = subprocess.run(["wl-paste", "--type", pic], capture_output=True, timeout=20).stdout
        if not data:
            return {"none": True}
        os.makedirs(att(), exist_ok=True)
        name = self.free(att(), "Pasted." + pic.split("/")[1].replace("jpeg", "jpg"))
        with open(att(name), "wb") as f:
            f.write(data)
        return self.block_for(name)

    def ocr(self, args):
        # the words in a picture (tesseract), for search and for copying
        p = in_att(args.get("src"))
        if not p or not os.path.isfile(p):
            raise ClioError("No such picture")
        try:
            r = subprocess.run(["tesseract", p, "-", "--psm", "3"], capture_output=True, timeout=120)
        except FileNotFoundError:
            raise ClioError("tesseract is not installed", "missing")
        except subprocess.TimeoutExpired:
            raise ClioError("Reading the picture took too long")
        text = r.stdout.decode("utf-8", "replace")
        # its lines as they were, the page breaks and runs of blank lines gone
        lines = [l.rstrip() for l in text.replace("\f", "\n").split("\n")]
        out, blank = [], False
        for l in lines:
            if l.strip() == "":
                blank = bool(out)
                continue
            if blank:
                out.append("")
            out.append(l)
            blank = False
        return {"text": "\n".join(out).strip()}

    def pdf(self, args):
        # pages drawn by the window (PNGs, `dpi` to the inch) into one PDF:
        # tesseract's, so its words can be found and copied; magick's, plain
        # pictures, when tesseract cannot
        pages = [str(p) for p in args.get("pages") or []]
        out = os.path.expanduser(str(args.get("out") or ""))
        dpi = str(int(args.get("dpi") or 192))
        if not pages or not out.endswith(".pdf"):
            raise ClioError("Nothing to make a PDF of")
        os.makedirs(os.path.dirname(out), exist_ok=True)
        lst = out[:-4] + ".pages.txt"
        try:
            with open(lst, "w") as f:
                f.write("\n".join(pages) + "\n")
            r = subprocess.run(["tesseract", lst, out[:-4], "--dpi", dpi, "pdf"], capture_output=True, timeout=600)
            ok = r.returncode == 0 and os.path.exists(out)
        except (FileNotFoundError, subprocess.TimeoutExpired):
            ok = False
        finally:
            try:
                os.remove(lst)
            except OSError:
                pass
        if not ok:
            r = subprocess.run(["magick"] + pages + ["-units", "PixelsPerInch", "-density", dpi, out], capture_output=True, timeout=600)
            if r.returncode != 0:
                raise ClioError("Could not make the PDF: " + r.stderr.decode("utf-8", "replace")[-200:])
        for p in pages:
            try:
                os.remove(p)
            except OSError:
                pass
        return {"path": out}

    def print_file(self, args):
        p = os.path.expanduser(str(args.get("path") or ""))
        try:
            r = subprocess.run(["lp", p], capture_output=True, timeout=60)
        except FileNotFoundError:
            raise ClioError("There is no printing system here (CUPS)", "missing")
        if r.returncode != 0:
            raise ClioError(r.stderr.decode("utf-8", "replace").strip() or "The printer said no")
        return {}

    def copy_text(self, args):
        subprocess.run(["wl-copy"], input=str(args.get("text") or "").encode(), timeout=5)
        return {}

    def export(self, args):
        out = os.path.expanduser(str(args.get("path") or ""))
        if not out:
            raise ClioError("Nowhere to write")
        write_atomic(out, str(args.get("text") or ""))
        # attachments beside it: [[src (relative to attachments), dest]]
        for pair in args.get("files") or []:
            try:
                s = in_att(pair[0])
                if not s:
                    continue
                dest = os.path.expanduser(pair[1])
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                shutil.copy2(s, dest)
            except (OSError, IndexError, TypeError):
                pass
        return {"path": out}

    # ── the lock ──
    def password(self, args):
        new = str(args.get("password") or "")
        if len(new) < 1:
            raise ClioError("It needs a password")
        lk = read_json(path_of(LOCK), {})
        old_key = None
        if lk.get("check"):
            old_key = derive(str(args.get("old") or ""), base64.b64decode(lk["salt"]))
            if not hmac.compare_digest(check_of(old_key), lk["check"]):
                raise ClioError("The old password is not right", "auth")
        salt = secrets.token_bytes(16)
        key = derive(new, salt)
        # every sealed note sealed again under the new key, before the new
        # key is written: a failure half way leaves the old password working
        resealed = []
        if old_key is not None:
            for p in note_files():
                j = read_json(p, None)
                if isinstance(j, dict) and j.get("sealed"):
                    j["sealed"] = seal(key, unseal(old_key, j["sealed"]))
                    resealed.append((p, j))
        for p, j in resealed:
            write_atomic(p, json.dumps(j, ensure_ascii=False, indent=1))
        write_atomic(path_of(LOCK), json.dumps({
            "salt": base64.b64encode(salt).decode(), "check": check_of(key),
            "hint": str(args.get("hint") or ""), "rounds": ROUNDS}))
        os.chmod(path_of(LOCK), 0o600)
        self.key = key
        return {"resealed": len(resealed)}

    def unlock(self, args):
        lk = read_json(path_of(LOCK), {})
        if not lk.get("check"):
            raise ClioError("No password is set", "nopassword")
        key = derive(str(args.get("password") or ""), base64.b64decode(lk["salt"]))
        if not hmac.compare_digest(check_of(key), lk["check"]):
            raise ClioError("That is not the Clio password", "auth")
        self.key = key
        return {}

    def unseal_note(self, args):
        if self.key is None:
            raise ClioError("Locked", "locked")
        i = safe_id(args.get("id"))
        j = read_json(note_path(i), None)
        if not isinstance(j, dict) or not j.get("sealed"):
            raise ClioError("Not a locked note")
        blocks = unseal(self.key, j["sealed"])
        # sealed before the attachments were gathered: their new names
        moved = read_json(path_of(MOVED), {})
        for b in blocks:
            if isinstance(b, dict) and b.get("src") in moved:
                b["src"] = moved[b["src"]]
        return {"blocks": blocks}

    def dispatch(self, op, req, args, cancel, emit):
        if op == "load":
            return self.load()
        if op == "save":
            return self.save(args)
        if op == "remove":
            return self.remove(args)
        if op == "meta":
            return self.meta(args)
        if op == "attach":
            return self.attach(args)
        if op == "attachDir":
            return self.attach_dir(args)
        if op == "pasteImage":
            return self.paste_image(args)
        if op == "pdf":
            return self.pdf(args)
        if op == "print":
            return self.print_file(args)
        if op == "ocr":
            return self.ocr(args)
        if op == "copyText":
            return self.copy_text(args)
        if op == "export":
            return self.export(args)
        if op == "password":
            return self.password(args)
        if op == "unlock":
            return self.unlock(args)
        if op == "lockNow":
            self.key = None
            return {}
        if op == "unseal":
            return self.unseal_note(args)
        raise ClioError("No such request: " + op)


def gather():
    # Attachments kept a directory per note before (attachments/<id>/<f>):
    # every file moved into the one shared directory, and every note's
    # blocks pointed at its new name. A locked note's blocks cannot be read
    # here: the old→new names are kept (.moved.json) and put right when it
    # is opened (unseal_note), and written for good on its next save.
    old = path_of("attachments")
    if not os.path.isdir(old):
        return
    os.makedirs(att(), exist_ok=True)
    moved = read_json(path_of(MOVED), {})
    for i in sorted(os.listdir(old)):
        d = os.path.join(old, i)
        if not os.path.isdir(d):
            continue
        for name in sorted(os.listdir(d)):
            src = os.path.join(d, name)
            if not os.path.isfile(src):
                continue
            new = Server.free(att(), name)
            shutil.move(src, att(new))
            moved[i + "/" + name] = new
    write_atomic(path_of(MOVED), json.dumps(moved, ensure_ascii=False, indent=1))
    for p in note_files():
        j = read_json(p, None)
        if not isinstance(j, dict):
            continue
        changed = False
        for b in j.get("blocks") or []:
            if isinstance(b, dict) and b.get("src") in moved:
                b["src"] = moved[b["src"]]
                changed = True
        if j.get("uses"):
            j["uses"] = [moved.get(u, u) for u in j["uses"]]
            changed = True
        if changed:
            write_atomic(p, json.dumps(j, ensure_ascii=False, indent=1))
    if not any(files for _, _, files in os.walk(old)):
        shutil.rmtree(old, ignore_errors=True)


def split():
    # Notes and journal entries were one directory (notes/): each now in its
    # kind's own, Notes/ and Journals/
    old = path_of("notes")
    if not os.path.isdir(old):
        return
    for n in os.listdir(old):
        src = os.path.join(old, n)
        if not n.endswith(".json") or not os.path.isfile(src):
            continue
        j = read_json(src, None)
        dst = note_path(n[:-5], "entry" if isinstance(j, dict) and j.get("kind") == "entry" else "note")
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if not os.path.exists(dst):
            shutil.move(src, dst)
    if not os.listdir(old):
        os.rmdir(old)


def hide():
    # the bookkeeping kept under its old, shown names before: hidden now
    for old, new in SHOWN.items():
        src, dst = path_of(old), path_of(new)
        if not os.path.exists(src):
            continue
        if not os.path.exists(dst):
            os.replace(src, dst)
        elif os.path.getmtime(src) <= os.path.getmtime(dst):
            # already carried over (the board reads the shown stickies file
            # once and writes the hidden one): the shown copy is stale
            os.remove(src)


def main():
    try:
        migrate()
        hide()
        split()
        gather()
    except OSError as e:
        print("clio: could not move the notebook over:", e, file=sys.stderr)
    lines.serve(Server(), PROTOCOL)

# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# THE UNIX PASSWORD STORE — pass, and gopass, which keeps the same kind of
# store: a directory of files, each one secret encrypted with gpg, its path
# the entry's name ("web/github.com.gpg" → web / github.com).
#
# Read here directly rather than through `pass show`: listing is the
# directory, so it needs nothing unlocked; an entry is `gpg --decrypt`. The
# unlocking is gpg-agent's: the passphrase typed here is handed to gpg once
# (--pinentry-mode loopback, over stdin) to decrypt one file, and the agent
# keeps the key open for its own cache time. Locking asks the agent to forget
# that key's passphrase (and only that key's).
#
# An entry, as pass has it: the first line is the password; then "key: value"
# lines (login, user, username, email, url…); an otpauth:// line is the
# one-time password (pass-otp's convention); anything else is notes.
#
# gopass's store on age instead of gpg is not read (it says so).

import concurrent.futures
import os
import re
import threading
import time

from base import (Locked, Provider, VaultError, detail, field, first_line, host_of,
                  item, run, section)

USER_KEYS = ("login", "username", "user", "email", "e-mail")
URL_KEYS = ("url", "website", "site", "uri", "link")

_cache = {}           # (account, path) → (mtime, parsed)
_lock = threading.Lock()


def parse_entry(text):
    lines = text.split("\n")
    password = lines[0] if lines else ""
    pairs, notes, otp = [], [], ""
    for line in lines[1:]:
        s = line.strip()
        if s.lower().startswith("otpauth://"):
            otp = otp or s
            continue
        m = re.match(r"^([A-Za-z][\w .-]{0,40}):\s?(.*)$", line)
        if m and not s.lower().startswith(("http:", "https:")):
            pairs.append((m.group(1).strip(), m.group(2)))
        else:
            notes.append(line)
    while notes and not notes[-1].strip():
        notes.pop()
    return {"password": password, "pairs": pairs, "notes": "\n".join(notes).strip("\n"), "otp": otp}


def pair(pairs, keys):
    for k, v in pairs:
        if k.lower() in keys and v.strip():
            return v.strip()
    return ""


# ── writing ─────────────────────────────────────────────────────────────
# An entry is written the way pass writes one: the password on the first
# line, then "key: value" lines, the otpauth:// line, then the notes —
# encrypted with gpg to the recipients of the nearest .gpg-id, straight from
# memory (stdin) to the file, through a temporary name. A store that is a
# git repository gets the commit pass would have made.

def compose(password, pairs, otp, notes):
    lines = [password or ""]
    lines += [f"{k}: {v}" for k, v in pairs if k and v is not None and str(v) != ""]
    if otp:
        lines.append(otp)
    if notes:
        lines += ["", notes.rstrip("\n")]
    return "\n".join(lines) + "\n"


def safe_name(s):
    s = re.sub(r"[\x00/]+", "-", str(s or "").strip()).strip(".")
    return s or "untitled"


class PassWriter:
    def gpg_id_for(self, path):
        d = os.path.dirname(path)
        root = os.path.realpath(self.store())
        while True:
            f = os.path.join(d, ".gpg-id")
            if os.path.isfile(f):
                with open(f) as h:
                    return [l.strip() for l in h if l.strip() and not l.startswith("#")]
            if os.path.realpath(d) == root or d in ("/", ""):
                return self.recipients()
            d = os.path.dirname(d)

    def commit(self, message, cancel):
        root = self.store()
        if os.path.isdir(os.path.join(root, ".git")):
            run(["git", "-C", root, "add", "-A"], cancel, timeout=30)
            run(["git", "-C", root, "commit", "-q", "-m", message], cancel, timeout=30)

    def write_entry(self, name, text, cancel):
        path = os.path.join(self.store(), name + ".gpg")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        rcpt = self.gpg_id_for(path)
        if not rcpt:
            raise VaultError("This store names no gpg key (.gpg-id)")
        tmp = path + ".calypso-tmp"
        args = ["--encrypt", "-o", tmp]
        for r in rcpt:
            args += ["-r", r]
        code, _, err = self.gpg(args, cancel, stdin=text)
        if code != 0:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            raise VaultError(first_line(err) or "gpg could not encrypt the entry")
        os.replace(tmp, path)
        return path

    def save(self, id, draft, cancel):
        f = draft.get("fields") or {}
        old = None
        if id:
            old = self.decrypt(id, os.path.join(self.store(), id + ".gpg"), cancel)
        title = safe_name(draft.get("title") or (id.rpartition("/")[2] if id else ""))
        folder = "/".join(safe_name(p) for p in str(draft.get("folder") or "").split(" / ") if p.strip()) \
            if "folder" in draft else (id.rpartition("/")[0] if id else "")
        name = (folder + "/" if folder else "") + title
        password = f.get("password") if f.get("password") is not None else (old or {}).get("password", "")
        pairs = list((old or {}).get("pairs", []))
        if f.get("username") is not None:
            pairs = [(k, v) for k, v in pairs if k.lower() not in USER_KEYS]
            if f["username"]:
                pairs.insert(0, ("login", f["username"]))
        if "urls" in draft:
            pairs = [(k, v) for k, v in pairs if k.lower() not in URL_KEYS]
            pairs[1 if pairs and pairs[0][0].lower() in USER_KEYS else 0:0] = [("url", u) for u in draft["urls"] if u]
        if "custom" in draft:
            std = [(k, v) for k, v in pairs if k.lower() in USER_KEYS or k.lower() in URL_KEYS]
            oldp = (old or {}).get("pairs", [])
            extra = []
            for c in draft["custom"]:
                ref = str(c.get("ref") or "")
                v = c.get("value")
                if v is None and ref.startswith("p"):
                    try:
                        v = oldp[int(ref[1:])][1]
                    except (ValueError, IndexError):
                        v = ""
                extra.append((str(c.get("label") or "field").replace(":", " ").strip(), v or ""))
            pairs = std + extra
        otp = f.get("totp") if f.get("totp") is not None else (old or {}).get("otp", "")
        notes = draft["notes"] if "notes" in draft else (old or {}).get("notes", "")
        text = compose(password, pairs, otp, notes)
        # a NEW entry under a name already taken, as much as a rename onto
        # one: write_entry's os.replace would put this over that password
        if name != id and os.path.exists(os.path.join(self.store(), name + ".gpg")):
            raise VaultError("Something by that name is already there")
        self.write_entry(name, text, cancel)
        if id and name != id:
            try:
                os.unlink(os.path.join(self.store(), id + ".gpg"))
            except OSError:
                pass
        with _lock:
            for k in [k for k in _cache if k[0] == self.cfg.get("id") and k[1] in (id, name)]:
                del _cache[k]
        self.commit(("Edit " if id else "Add ") + name + " (calypso)", cancel)
        return {"id": name}

    def delete(self, id, permanent, cancel):
        path = os.path.join(self.store(), id + ".gpg")
        if not os.path.exists(path):
            raise VaultError("That entry is not in the store any more")
        if permanent:
            os.unlink(path)
        else:
            code, _, err = run(["gio", "trash", path], cancel, timeout=30)
            if code != 0:
                raise VaultError(first_line(err) or "could not move it to the trash")
        self.commit("Remove " + id + " (calypso)", cancel)
        return {}


class PassStore(PassWriter, Provider):
    KIND = "pass"
    NAME = "pass"
    CLI = "pass"
    PKG = "pass"
    ASKS = "passphrase"
    CAN = {"create": ["login", "password", "note"], "edit": True, "delete": "trash",
           "restore": False, "custom": True, "totpEdit": True, "folders": True,
           "attachments": False, "fav": False, "tags": False, "history": False}
    BLURB = "gpg-agent keeps your key open for its own cache time, or until you lock it here"

    def store(self):
        d = self.cfg.get("store") or os.environ.get("PASSWORD_STORE_DIR") or "~/.password-store"
        return os.path.expanduser(str(d))

    def installed(self):
        # the store is read with gpg itself; `pass` is only what makes and
        # edits one (installed when chosen, for that)
        from base import have
        return have("gpg") and (self.KIND == "pass" or have(self.CLI))

    def files(self):
        root = self.store()
        out = []
        for dp, dns, fns in os.walk(root, followlinks=True):
            dns[:] = sorted(d for d in dns if not d.startswith("."))
            for f in sorted(fns):
                if f.endswith(".gpg"):
                    full = os.path.join(dp, f)
                    out.append((os.path.relpath(full, root)[:-4], full))
        return out

    def recipients(self):
        """the gpg ids the store is encrypted to (.gpg-id, nearest the root)"""
        try:
            with open(os.path.join(self.store(), ".gpg-id")) as f:
                return [l.strip() for l in f if l.strip() and not l.startswith("#")]
        except OSError:
            return []

    def probe(self):
        fs = self.files()
        return min(fs, key=lambda p: os.path.getsize(p[1]))[1] if fs else None

    def gpg(self, args, cancel, stdin=None, timeout=60):
        return run(["gpg", "--batch", "--quiet", "--yes", "--no-tty"] + args, cancel,
                   stdin=stdin, timeout=timeout)

    def unlocked(self, cancel):
        f = self.probe()
        if not f:
            return True            # nothing to decrypt: nothing locked
        code, _, _ = self.gpg(["--pinentry-mode", "error", "--decrypt", "-o", "/dev/null", f],
                              cancel, timeout=20)
        return code == 0

    def status(self, cancel):
        root = self.store()
        if os.path.isfile(os.path.join(root, ".age-recipients")):
            return {"configured": False, "unlocked": False, "user": root,
                    "note": "this store is encrypted with age, which calypso does not read"}
        ok = os.path.isfile(os.path.join(root, ".gpg-id"))
        return {"configured": ok, "unlocked": ok and self.unlocked(cancel),
                "user": ", ".join(self.recipients()) or root,
                "note": "" if ok else "no password store at " + root}

    def setup(self, params, secret, cancel, emit):
        if params.get("store"):
            self.cfg["store"] = str(params["store"]).strip()
        st = self.status(cancel)
        if not st["configured"]:
            raise VaultError(st.get("note") or "No password store there (no .gpg-id) — make one with `pass init <your gpg id>`")
        if secret:
            self.unlock(secret, cancel)
        return dict(self.status(cancel), store=self.store())

    def unlock(self, secret, cancel):
        f = self.probe()
        if not f:
            return {}
        code, _, err = self.gpg(["--pinentry-mode", "loopback", "--passphrase-fd", "0",
                                 "--decrypt", "-o", "/dev/null", f], cancel,
                                stdin=(secret or "") + "\n", timeout=60)
        if code != 0:
            low = err.lower()
            if "bad passphrase" in low or "no secret key" not in low:
                raise VaultError("Wrong passphrase" if "bad passphrase" in low or "passphrase" in low
                                 else first_line(err) or "gpg could not decrypt", "auth")
            raise VaultError("Your gpg key for this store is not on this machine")
        return {}

    def keygrips(self, cancel):
        grips = []
        for rid in self.recipients():
            code, out, _ = run(["gpg", "--batch", "--with-colons", "--with-keygrip",
                                "--list-secret-keys", rid], cancel, timeout=20)
            if code == 0:
                grips += [l.split(":")[9] for l in out.splitlines() if l.startswith("grp:")]
        return grips

    def lock(self, cancel):
        grips = self.keygrips(cancel)
        if not grips:
            return {}
        cmds = [f"clear_passphrase --mode=normal {g}" for g in grips] + ["/bye"]
        run(["gpg-connect-agent"] + cmds, cancel, timeout=20)
        with _lock:
            for k in [k for k in _cache if k[0] == self.cfg.get("id")]:
                del _cache[k]
        return {}

    def decrypt(self, name, path, cancel):
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            raise VaultError("That entry is not in the store any more")
        key = (self.cfg.get("id"), name)
        with _lock:
            hit = _cache.get(key)
        if hit and hit[0] == mtime:
            return hit[1]
        code, out, err = self.gpg(["--pinentry-mode", "error", "--decrypt", path], cancel)
        if code != 0:
            if "pinentry" in err.lower() or "passphrase" in err.lower() or "no secret" not in err.lower():
                raise Locked()
            raise VaultError(first_line(err))
        parsed = parse_entry(out)
        with _lock:
            _cache[key] = (mtime, parsed)
        return parsed

    def row(self, name, parsed):
        folder, _, title = name.rpartition("/")
        user = parsed and pair(parsed["pairs"], USER_KEYS)
        url = parsed and pair(parsed["pairs"], URL_KEYS)
        # pass' own habit: the entry named after the site, the file after the login
        host = host_of(url) if url else host_of(title) or host_of(folder.rpartition("/")[2])
        if not user and folder and "." in folder.rpartition("/")[2] and "." not in title:
            user = title
        mtime = 0
        kind = "login" if (user or host or (parsed and parsed["otp"])) else "password"
        return item(name, title, user or "", kind, host, folder, False, [], mtime,
                    bool(parsed["otp"]) if parsed else None)

    def cached(self, name, path):
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            return None
        with _lock:
            hit = _cache.get((self.cfg.get("id"), name))
        return hit[1] if hit and hit[0] == mtime else None

    def listed(self, name, path, parsed):
        r = self.row(name, parsed)
        try:
            r["updated"] = int(os.path.getmtime(path))
        except OSError:
            pass
        return r

    # AT ONCE, FROM THE NAMES. Each entry is a gpg process (~120 ms, and the
    # agent takes them one at a time however many are asked together), so a
    # store of a few hundred read before listing kept the list away for half
    # a minute. The list comes straight from the directory and what was read
    # before; enrich() reads the rest after, and says each batch as it lands.
    def items(self, cancel):
        files = self.files()
        if not self.unlocked(cancel):
            raise Locked()
        return [self.listed(n, p, self.cached(n, p)) for n, p in files]

    def enrich(self, cancel, emit):
        todo = [(n, p) for n, p in self.files() if self.cached(n, p) is None]
        batch, last = [], time.time()
        with concurrent.futures.ThreadPoolExecutor(2) as ex:
            futs = {ex.submit(self.decrypt, n, p, cancel): (n, p) for n, p in todo}
            for fu in concurrent.futures.as_completed(futs):
                n, p = futs[fu]
                try:
                    batch.append(self.listed(n, p, fu.result()))
                except VaultError:
                    continue
                if len(batch) >= 40 or time.time() - last > 0.4:
                    emit({"rows": batch})
                    batch, last = [], time.time()
        if batch:
            emit({"rows": batch})
        return {"read": len(todo)}

    def detail(self, id, cancel, secret=None):
        path = os.path.join(self.store(), id + ".gpg")
        parsed = self.decrypt(id, path, cancel)
        row = self.row(id, parsed)
        try:
            row["updated"] = int(os.path.getmtime(path))
        except OSError:
            pass
        pairs = parsed["pairs"]
        used_user = next((k for k, v in pairs if k.lower() in USER_KEYS and v.strip()), None)
        main = [field("username", "username", row["sub"], role="username"),
                field("password", "password", parsed["password"], "secret", True, "password"),
                field("totp", "one-time password", parsed["otp"], "totp", True, "totp")
                if parsed["otp"] else None]
        urls, extra = [], []
        for i, (k, v) in enumerate(pairs):
            if k == used_user:
                continue
            if k.lower() in URL_KEYS:
                urls.append(field(f"p{i}", "website", v.strip(), "url"))
            else:
                sens = any(w in k.lower() for w in ("pin", "secret", "key", "token", "cvv", "pass"))
                extra.append(field(f"p{i}", k, v, "secret" if sens else "text", sens))
        if not urls and row["host"]:
            urls.append(field("site", "website", "https://" + row["host"], "url"))
        sections = [section("", main), section("websites", urls), section("more", extra)]
        return detail(row, sections, parsed["notes"])


class GoPass(PassStore):
    KIND = "gopass"
    NAME = "gopass"
    CLI = "gopass"
    PKG = "gopass"

    def store(self):
        if self.cfg.get("store"):
            return os.path.expanduser(str(self.cfg["store"]))
        code, out, _ = run(["gopass", "config", "mounts.path"], None, timeout=15)
        p = out.strip().splitlines()[-1].strip() if code == 0 and out.strip() else ""
        if p.startswith("mounts.path"):
            p = p.split("=", 1)[-1].strip()
        return os.path.expanduser(p or "~/.local/share/gopass/stores/root")

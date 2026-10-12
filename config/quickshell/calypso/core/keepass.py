# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# KEEPASS — a .kdbx file of your own (KeePassXC's, KeePass', KeeWeb's), read
# and written through pykeepass (python-pykeepass), chosen over
# keepassxc-cli (2026-10-12, user) because the CLI cannot set a custom field
# or a one-time password.
#
# Unlocked, the database is open in this daemon's memory, as KeePassXC
# holds it, with what opened it (the password, the key file) so a write can
# open it afresh first: when the file changed on disk since (KeePassXC saved
# it), the change is read before anything is written over it. A save goes
# to a temporary file beside it and is moved into place — the database is
# never half-written. Locking forgets all of it.
#
# An entry's folder is its group's path ("Work / Servers"); the recycle bin
# is its trash. One-time passwords are KeePassXC's `otp` attribute; the
# older KeePass forms (TimeOtp-*, "TOTP Seed") are read too.

import base64
import os
import tempfile
import threading

from base import (Locked, Provider, VaultError, detail, field, host_of, item,
                  section)

_open = {}            # account id → { kp, mtime, secret, keyfile }
_lock = threading.Lock()

STANDARD = {"Title", "UserName", "Password", "URL", "Notes", "otp"}
OTP_KEYS = ("otp", "TimeOtp-Secret-Base32", "TimeOtp-Secret", "TOTP Seed")


def pykeepass():
    try:
        import pykeepass as p
        return p
    except ImportError:
        raise VaultError("pykeepass is not installed (python-pykeepass)", "missing")


def otp_value(strings):
    """the entry's one-time password as something totp.parse reads"""
    g = lambda k: strings.get(k) or ""
    if g("otp"):
        return g("otp")
    if g("TimeOtp-Secret-Base32"):
        algo = (g("TimeOtp-Algorithm") or "HMAC-SHA-1").replace("HMAC-", "").replace("-", "")
        return ("otpauth://totp/?secret=" + g("TimeOtp-Secret-Base32")
                + "&period=" + (g("TimeOtp-Period") or "30") + "&digits=" + (g("TimeOtp-Length") or "6")
                + "&algorithm=" + algo)
    if g("TimeOtp-Secret"):
        return base64.b32encode(g("TimeOtp-Secret").encode()).decode()
    if g("TOTP Seed"):
        return g("TOTP Seed") + ("\u0001" + g("TOTP Settings") if g("TOTP Settings") else "")
    return ""


def epoch(dt):
    try:
        return int(dt.timestamp()) if dt else 0
    except (AttributeError, ValueError, OSError):
        return 0


def protected(entry, key):
    try:
        v = entry._element.find("String[Key='%s']/Value" % key.replace("'", ""))
        return v is not None and v.get("Protected") == "True"
    except Exception:
        return False


class KeePass(Provider):
    KIND = "keepass"
    NAME = "KeePass"
    CLI = "pykeepass"
    PKG = "python-pykeepass"
    BLURB = "the database is open in calypso's memory while unlocked, and forgotten when locked"
    CAN = {"create": ["login", "password", "note"], "edit": True, "delete": "trash",
           "restore": True, "custom": True, "totpEdit": True, "folders": True,
           "attachments": True, "fav": False, "tags": True, "history": True}

    def installed(self):
        try:
            pykeepass()
            return True
        except VaultError:
            return False

    @property
    def aid(self):
        return self.cfg.get("id")

    @property
    def path(self):
        return os.path.expanduser(str(self.cfg.get("path") or ""))

    @property
    def keyfile(self):
        k = str(self.cfg.get("keyfile") or "")
        return os.path.expanduser(k) if k else None

    def status(self, cancel):
        with _lock:
            here = self.aid in _open
        ok = bool(self.path) and os.path.isfile(self.path)
        return {"configured": ok, "unlocked": ok and here, "user": os.path.basename(self.path),
                "note": "" if ok else "the database file is not there"}

    def setup(self, params, secret, cancel, emit):
        path = os.path.expanduser(str(params.get("path") or "").strip())
        keyfile = str(params.get("keyfile") or "").strip()
        if keyfile and not os.path.isfile(os.path.expanduser(keyfile)):
            raise VaultError("The key file is not there")
        if params.get("create"):
            if os.path.exists(path):
                raise VaultError("Something is already there — choose a new file name")
            if not secret and not keyfile:
                raise VaultError("A new database needs a password, a key file, or both")
            os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
            try:
                pykeepass().create_database(path, password=secret or None,
                                            keyfile=os.path.expanduser(keyfile) if keyfile else None)
            except Exception as e:
                raise VaultError("The database could not be made: " + str(e))
        elif not os.path.isfile(path):
            raise VaultError("There is no file there")
        self.cfg["path"] = path
        self.cfg["keyfile"] = keyfile
        if secret is not None or keyfile:
            self.unlock(secret, cancel)
        return dict(self.status(cancel), path=path, keyfile=keyfile)

    def openkp(self, secret, keyfile):
        try:
            return pykeepass().PyKeePass(self.path, password=secret or None, keyfile=keyfile)
        except Exception as e:
            name = type(e).__name__
            if "Credentials" in name or "HeaderChecksum" in name or "PayloadChecksum" in name:
                raise VaultError("Wrong password" + (" or key file" if keyfile else ""), "auth")
            raise VaultError("The database could not be opened: " + str(e))

    def unlock(self, secret, cancel):
        if not os.path.isfile(self.path):
            raise VaultError("The database file is not there: " + self.path)
        kp = self.openkp(secret, self.keyfile)
        with _lock:
            _open[self.aid] = {"kp": kp, "mtime": os.path.getmtime(self.path),
                               "secret": secret, "keyfile": self.keyfile}
        return {}

    def lock(self, cancel):
        with _lock:
            _open.pop(self.aid, None)
        return {}

    def kp(self):
        """the open database — read afresh if the file changed under it"""
        with _lock:
            o = _open.get(self.aid)
        if o is None:
            raise Locked()
        try:
            m = os.path.getmtime(self.path)
        except OSError:
            raise VaultError("The database file is not there any more")
        if m != o["mtime"]:
            kp = self.openkp(o["secret"], o["keyfile"])
            with _lock:
                o.update(kp=kp, mtime=m)
        return o["kp"]

    def write(self, kp):
        """saved beside, then moved into place"""
        d = os.path.dirname(self.path) or "."
        fd, tmp = tempfile.mkstemp(prefix=".calypso-", suffix=".kdbx", dir=d)
        os.close(fd)
        try:
            kp.save(filename=tmp)
            try:
                os.chmod(tmp, os.stat(self.path).st_mode & 0o777)
            except OSError:
                pass
            os.replace(tmp, self.path)
        except Exception as e:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            raise VaultError("The database could not be saved: " + str(e))
        with _lock:
            if self.aid in _open:
                _open[self.aid]["mtime"] = os.path.getmtime(self.path)

    def sync(self, cancel):
        self.kp()
        return {}

    # ── reading ────────────────────────────────────────────────────────
    def binned(self, kp, e):
        rb = getattr(kp, "recyclebin_group", None)
        if rb is None:
            return False
        g = e.group
        while g is not None:
            if g.uuid == rb.uuid:
                return True
            g = g.parentgroup
        return False

    def folder_of(self, e):
        try:
            path = e.group.path or []
        except AttributeError:
            path = []
        return " / ".join(p for p in path if p)

    def strings(self, e):
        s = {"Title": e.title or "", "UserName": e.username or "", "Password": e.password or "",
             "URL": e.url or "", "Notes": e.notes or "", "otp": e.otp or ""}
        for k, v in (e.custom_properties or {}).items():
            s[k] = v or ""
        return s

    def row(self, e):
        s = self.strings(e)
        otp = otp_value(s)
        kind = ("login" if s["UserName"] or s["URL"] or otp else
                "password" if s["Password"] else "note")
        return item(str(e.uuid), s["Title"], s["UserName"], kind, host_of(s["URL"]),
                    self.folder_of(e), False, list(e.tags or []), epoch(e.mtime),
                    bool(otp) if kind == "login" else False)

    def items(self, cancel):
        kp = self.kp()
        return [self.row(e) for e in kp.entries if not self.binned(kp, e)]

    def trash(self, cancel):
        kp = self.kp()
        return [self.row(e) for e in kp.entries if self.binned(kp, e)]

    def entry(self, kp, id):
        import uuid
        try:
            e = kp.find_entries(uuid=uuid.UUID(id), first=True)
        except ValueError:
            e = None
        if e is None:
            raise VaultError("That entry is not in the database any more")
        return e

    def urls(self, s):
        out = [s["URL"]] if s["URL"] else []
        out += [v for k, v in sorted(s.items()) if k.startswith("KP2A_URL") and v]
        return out

    def detail(self, id, cancel, secret=None):
        kp = self.kp()
        e = self.entry(kp, id)
        s = self.strings(e)
        otp = otp_value(s)
        main = [field("username", "username", s["UserName"], role="username"),
                field("password", "password", s["Password"], "secret", True, "password"),
                field("totp", "one-time password", otp, "totp", True, "totp") if otp else None]
        urls = [field(f"url{i}", "website", u, "url") for i, u in enumerate(self.urls(s))]
        extra = []
        for k in sorted(e.custom_properties or {}):
            if k in OTP_KEYS or k.startswith("TimeOtp-") or k == "TOTP Settings" \
                    or k.startswith("KP2A_URL") or k.startswith("KPH:") or k.startswith("_"):
                continue
            hidden = protected(e, k)
            extra.append(field("c:" + k, k, s[k], "secret" if hidden else "text", hidden))
        hist = []
        for n, h in enumerate(reversed(e.history or [])):
            if h.password and h.password != s["Password"] and \
                    not any(x["value"] == h.password for x in hist):
                hist.append(field(f"h:{n}", "until " + (h.mtime.strftime("%-d %b %Y") if h.mtime else "before"),
                                  h.password, "secret", True))
        sections = [section("", main), section("websites", urls), section("more", extra),
                    section("password history", hist)]
        d = detail(self.row(e), sections, s["Notes"], created=epoch(e.ctime))
        d["attachments"] = [{"id": str(a.id), "name": a.filename,
                             "size": "%.1f KB" % (len(a.data or b"") / 1024)} for a in e.attachments or []]
        return d

    def folders(self, cancel):
        kp = self.kp()
        rb = getattr(kp, "recyclebin_group", None)
        out = []
        for g in kp.groups:
            if g is kp.root_group or (rb is not None and g.uuid == rb.uuid):
                continue
            p = " / ".join(x for x in (g.path or []) if x)
            if p:
                out.append(p)
        return sorted(set(out), key=str.lower)

    def audit_secrets(self, cancel):
        kp = self.kp()
        out = {}
        for e in kp.entries:
            if self.binned(kp, e):
                continue
            s = self.strings(e)
            out[str(e.uuid)] = {"password": s["Password"], "urls": self.urls(s), "totp": bool(otp_value(s))}
        return out

    # ── writing ────────────────────────────────────────────────────────
    def group(self, kp, folder):
        g = kp.root_group
        for name in [p.strip() for p in str(folder or "").split(" / ") if p.strip()]:
            nxt = next((x for x in g.subgroups if x.name == name), None)
            g = nxt if nxt is not None else kp.add_group(g, name)
        return g

    def save(self, id, draft, cancel):
        kp = self.kp()
        f = draft.get("fields") or {}
        val = lambda k, old: old if f.get(k) is None else f[k]
        title = draft.get("title") or "(untitled)"
        if id:
            e = self.entry(kp, id)
            e.save_history()
            e.title = title
        else:
            e = kp.add_entry(self.group(kp, draft.get("folder")), title, "", "", force_creation=True)
        e.username = val("username", e.username or "")
        e.password = val("password", e.password or "")
        if "totp" in f and f["totp"] is not None:
            e.otp = f["totp"] or None
        if "notes" in draft:
            e.notes = draft["notes"] or None
        if "tags" in draft:
            e.tags = [t for t in draft["tags"] if t] or None
        if "urls" in draft:
            urls = [u for u in draft["urls"] if u]
            e.url = urls[0] if urls else None
            for k in list((e.custom_properties or {}).keys()):
                if k.startswith("KP2A_URL"):
                    e.delete_custom_property(k)
            for i, u in enumerate(urls[1:], 1):
                e.set_custom_property("KP2A_URL_%d" % i, u)
        if "custom" in draft:
            old = dict(e.custom_properties or {})
            keep = set()
            for c in draft["custom"]:
                label = str(c.get("label") or "field").strip() or "field"
                ref = str(c.get("ref") or "")
                v = c.get("value")
                if v is None and ref.startswith("c:"):
                    v = old.get(ref[2:], "")
                if ref.startswith("c:") and ref[2:] != label and ref[2:] in old:
                    e.delete_custom_property(ref[2:])
                try:
                    e.set_custom_property(label, v or "", protect=bool(c.get("hidden")))
                except TypeError:
                    e.set_custom_property(label, v or "")
                keep.add(label)
            for k in old:
                if k not in keep and not (k in OTP_KEYS or k.startswith(("TimeOtp-", "KP2A_URL", "KPH:", "_"))
                                          or k == "TOTP Settings"):
                    e.delete_custom_property(k)
        if id and "folder" in draft and draft["folder"] != self.folder_of(e):
            kp.move_entry(e, self.group(kp, draft.get("folder")))
        e.touch(modify=True)
        self.write(kp)
        return {"id": str(e.uuid)}

    def delete(self, id, permanent, cancel):
        kp = self.kp()
        e = self.entry(kp, id)
        if permanent or self.binned(kp, e) or not hasattr(kp, "trash_entry"):
            kp.delete_entry(e)
        else:
            kp.trash_entry(e)
        self.write(kp)
        return {}

    def restore(self, id, cancel):
        kp = self.kp()
        e = self.entry(kp, id)
        kp.move_entry(e, kp.root_group)
        self.write(kp)
        return {}

    # ── attachments ────────────────────────────────────────────────────
    def attachment(self, e, att):
        a = next((a for a in e.attachments or [] if str(a.id) == str(att)), None)
        if a is None:
            raise VaultError("That attachment is not there any more")
        return a

    def attachment_save(self, id, att, path, cancel):
        a = self.attachment(self.entry(self.kp(), id), att)
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "wb") as out:
            out.write(a.data or b"")
        return {"path": path}

    def attachment_add(self, id, path, cancel):
        kp = self.kp()
        e = self.entry(kp, id)
        with open(path, "rb") as f:
            data = f.read()
        bid = kp.add_binary(data)
        e.add_attachment(bid, os.path.basename(path))
        self.write(kp)
        return {}

    def attachment_remove(self, id, att, cancel):
        kp = self.kp()
        e = self.entry(kp, id)
        e.delete_attachment(self.attachment(e, att))
        self.write(kp)
        return {}

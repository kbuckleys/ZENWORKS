# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# BITWARDEN, through bw — the official CLI (bitwarden-cli), and Vaultwarden
# the same way with a server address. Chosen over rbw (2026-10-12, user) for
# writing: bw creates, edits, trashes and restores every kind of item, its
# custom fields, one-time passwords and attachments; rbw only adds logins.
#
# bw keeps the account signed in on disk (its data.json) and hands out a
# SESSION KEY on unlock; this daemon keeps that key in memory only and
# passes it in each bw call's environment (BW_SESSION). The master password
# reaches bw through a fifo (--passwordfile), never argv, env or disk.
# Locking is `bw lock` and forgetting the key.
#
# The whole vault comes from one `bw list items` (secrets and all, as
# Bitwarden's own clients hold it) and is kept here while unlocked; the
# window still gets every secret blanked (server.py).
#
# Several accounts: bw keeps one per data directory (BITWARDENCLI_APPDATA_DIR);
# a calypso account other than the first names its own (`profile`).

import base64
import copy
import json
import os
import threading
import time

from base import (Fifo, Locked, Provider, VaultError, detail, field, first_line,
                  host_of, item, iso_time, run, section)

TYPES = {1: "login", 2: "note", 3: "card", 4: "identity", 5: "ssh"}
TYPE_OF = {v: k for k, v in TYPES.items()}

IDENTITY = [("title", "title"), ("first", "firstName"), ("middle", "middleName"),
            ("last", "lastName"), ("username", "username"), ("company", "company"),
            ("email", "email"), ("phone", "phone"), ("address1", "address1"),
            ("address2", "address2"), ("address3", "address3"), ("city", "city"),
            ("state", "state"), ("postal", "postalCode"), ("country", "country"),
            ("ssn", "ssn"), ("passport", "passportNumber"), ("license", "licenseNumber")]
IDENTITY_SECRET = {"ssn", "passport", "license"}
LABELS = {"first": "first name", "middle": "middle name", "last": "last name",
          "address1": "address", "address2": "address line 2", "address3": "address line 3",
          "postal": "postal code", "ssn": "social security number",
          "passport": "passport number", "license": "license number"}

_sessions = {}        # account id → BW_SESSION
_vaults = {}          # account id → { items: {id: raw}, folders: {id: name}, at }
_lock = threading.Lock()


def b64(obj):
    return base64.b64encode(json.dumps(obj).encode()).decode()


class Bitwarden(Provider):
    KIND = "bitwarden"
    NAME = "Bitwarden"
    CLI = "bw"
    PKG = "bitwarden-cli"

    # [extra]'s bitwarden-cli runs on nodejs-lts-jod, which conflicts with a
    # current `nodejs` (and taking that away takes npm with it): with nodejs
    # installed, Bitwarden's own standalone build from the AUR instead
    # (bitwarden-cli-bin — no Node at all). User's install failed on exactly
    # this, 2026-10-12.
    @classmethod
    def package(cls):
        import subprocess
        try:
            r = subprocess.run(["pacman", "-Qq", "nodejs"], stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, timeout=10)
            if r.returncode == 0:
                return "bitwarden-cli-bin", True
        except (OSError, subprocess.TimeoutExpired):
            pass
        return "bitwarden-cli", False
    BLURB = "bw stays signed in on this machine; its session is in calypso's memory until locked"
    CAN = {"create": ["login", "note", "card", "identity", "ssh"], "edit": True,
           "delete": "trash", "restore": True, "custom": True, "totpEdit": True,
           "folders": True, "attachments": True, "fav": True, "tags": False, "history": True}

    @property
    def aid(self):
        return self.cfg.get("id")

    def env(self, session=True):
        e = {"BW_NOINTERACTION": "true", "NODE_NO_WARNINGS": "1"}
        prof = str(self.cfg.get("profile") or "")
        if prof:
            base = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"),
                                "Bitwarden CLI", "calypso-" + prof)
            os.makedirs(base, mode=0o700, exist_ok=True)
            e["BITWARDENCLI_APPDATA_DIR"] = base
        if session:
            with _lock:
                s = _sessions.get(self.aid)
            if s:
                e["BW_SESSION"] = s
        return e

    def bw(self, args, cancel, session=True, **kw):
        kw.setdefault("timeout", 120)
        return run(["bw"] + args, cancel, env=self.env(session), **kw)

    def why(self, err, out=""):
        t = (err or out or "").strip()
        low = t.lower()
        if "two-step" in low or "two step" in low or "2fa" in low:
            return "two-step"
        if "invalid master password" in low or "username or password is incorrect" in low:
            return "Wrong master password"
        if "new device" in low or "verification" in low and "email" in low:
            return "Bitwarden sent a verification code to your email — enter it as the 2FA code"
        if "connect" in low or "enotfound" in low or "network" in low or "etimedout" in low:
            return "Could not reach the server"
        return first_line(t) or "bw failed"

    # ── the account ────────────────────────────────────────────────────
    def status_raw(self, cancel):
        code, out, _ = self.bw(["status"], cancel, timeout=30)
        try:
            return json.loads(out) if code == 0 else {}
        except ValueError:
            return {}

    def status(self, cancel):
        st = self.status_raw(cancel)
        state = st.get("status") or "unauthenticated"
        unlocked = state == "unlocked"
        if not unlocked:
            with _lock:
                _sessions.pop(self.aid, None)
                _vaults.pop(self.aid, None)
        return {"configured": state != "unauthenticated", "unlocked": unlocked,
                "user": st.get("userEmail") or self.cfg.get("email") or "",
                "server": (st.get("serverUrl") or "bitwarden.com").replace("https://", "")}

    def setup(self, params, secret, cancel, emit):
        email = str(params.get("email") or "").strip()
        server = str(params.get("server") or "").strip().rstrip("/")
        if "@" not in email:
            raise VaultError("That does not look like an email address")
        if not secret:
            raise VaultError("Your master password is needed to sign in")
        st = self.status_raw(cancel)
        if st.get("status") not in (None, "unauthenticated") and st.get("userEmail") != email:
            self.bw(["logout"], cancel, session=False, timeout=30)
            st = {}
        if st.get("status") in (None, "unauthenticated"):
            url = server if not server or "://" in server else "https://" + server
            self.bw(["config", "server", url or "https://vault.bitwarden.com"], cancel,
                    session=False, timeout=30)
            argv = ["login", email, "--raw"]
            method, code2 = params.get("method"), str(params.get("code") or "").strip()
            if code2:
                argv += ["--method", str({"app": 0, "email": 1, "key": 3}.get(method, 0)), "--code", code2]
            with Fifo("calypso-bw-" + self.aid, secret) as f:
                argv += ["--passwordfile", f.path]
                code, out, err = self.bw(argv, cancel, session=False, timeout=180)
            if code != 0 or not out.strip():
                why = self.why(err, out)
                if why == "two-step":
                    if method == "email" and not code2:
                        raise VaultError("Bitwarden emailed you a code: enter it below", "2fa")
                    raise VaultError("This account uses two-step login: its code is needed", "2fa")
                raise VaultError(why, "auth")
            with _lock:
                _sessions[self.aid] = out.strip().splitlines()[-1]
        else:
            self.unlock(secret, cancel)
        self.cfg["email"] = email
        return dict(self.status(cancel), email=email)

    def unlock(self, secret, cancel):
        with Fifo("calypso-bw-" + self.aid, secret or "") as f:
            code, out, err = self.bw(["unlock", "--passwordfile", f.path, "--raw"], cancel,
                                     session=False, timeout=120)
        if code != 0 or not out.strip():
            low = (err + out).lower()
            if "not logged in" in low or "you are not logged in" in low:
                raise VaultError("Bitwarden is signed out on this machine — add the account again", "auth")
            raise VaultError(self.why(err, out), "auth")
        with _lock:
            _sessions[self.aid] = out.strip().splitlines()[-1]
            _vaults.pop(self.aid, None)
        return {}

    def lock(self, cancel):
        self.bw(["lock"], cancel, timeout=30)
        with _lock:
            _sessions.pop(self.aid, None)
            _vaults.pop(self.aid, None)
        return {}

    def forget(self, cancel):
        self.bw(["logout"], cancel, timeout=30)
        with _lock:
            _sessions.pop(self.aid, None)
            _vaults.pop(self.aid, None)
        return {}

    def sync(self, cancel):
        self.need()
        code, _, err = self.bw(["sync"], cancel, timeout=180)
        if code != 0:
            raise VaultError(self.why(err))
        with _lock:
            _vaults.pop(self.aid, None)
        return {}

    def need(self):
        with _lock:
            if not _sessions.get(self.aid):
                raise Locked()

    def json(self, args, cancel, timeout=180):
        self.need()
        code, out, err = self.bw(args, cancel, timeout=timeout)
        if code != 0:
            low = err.lower()
            if "locked" in low or "not logged in" in low or "session" in low:
                with _lock:
                    _sessions.pop(self.aid, None)
                raise Locked()
            raise VaultError(self.why(err, out))
        try:
            return json.loads(out or "null")
        except ValueError:
            raise VaultError("bw said something that is not JSON")

    # ── the vault ──────────────────────────────────────────────────────
    def vault(self, cancel, fresh=False):
        with _lock:
            v = _vaults.get(self.aid)
        if v and not fresh:
            return v
        items = {i["id"]: i for i in self.json(["list", "items"], cancel) or [] if i.get("id")}
        folders = {f["id"]: f["name"] for f in self.json(["list", "folders"], cancel) or []
                   if f.get("id")}
        v = {"items": items, "folders": folders, "at": time.time()}
        with _lock:
            _vaults[self.aid] = v
        return v

    def row(self, e, folders):
        kind = TYPES.get(e.get("type"), "other")
        login = e.get("login") or {}
        uris = [u.get("uri") for u in login.get("uris") or [] if u.get("uri")]
        sub = login.get("username") or ""
        if kind == "card":
            c = e.get("card") or {}
            sub = (c.get("brand") or "") + (" •••• " + c["number"][-4:] if c.get("number") else "")
        elif kind == "identity":
            i = e.get("identity") or {}
            sub = " ".join(x for x in (i.get("firstName"), i.get("lastName")) if x) or i.get("email") or ""
        return item(e["id"], e.get("name"), sub.strip(), kind, host_of(uris[0]) if uris else "",
                    folders.get(e.get("folderId"), ""), e.get("favorite"), [],
                    iso_time(e.get("revisionDate")), bool(login.get("totp")) if kind == "login" else False)

    def items(self, cancel):
        v = self.vault(cancel, fresh=True)
        return [self.row(e, v["folders"]) for e in v["items"].values()]

    def raw(self, id, cancel):
        v = self.vault(cancel)
        e = v["items"].get(id)
        if e is None:
            v = self.vault(cancel, fresh=True)
            e = v["items"].get(id)
        if e is None:
            raise VaultError("That item is not in the vault any more")
        return e, v

    def detail(self, id, cancel, secret=None):
        e, v = self.raw(id, cancel)
        if e.get("reprompt") == 1:
            if secret is None:
                return {"id": id, "reprompt": True, "sections": [], "notes": ""}
            # the master password, checked the way the vault is opened
            self.unlock(secret, cancel)
            e, v = self.raw(id, cancel)
        kind = TYPES.get(e.get("type"), "other")
        main = []
        if kind == "login":
            l = e.get("login") or {}
            main = [field("username", "username", l.get("username"), role="username"),
                    field("password", "password", l.get("password"), "secret", True, "password"),
                    field("totp", "one-time password", l.get("totp"), "totp", True, "totp")
                    if l.get("totp") else None]
        elif kind == "card":
            c = e.get("card") or {}
            exp = "/".join(x for x in (str(c.get("expMonth") or ""), str(c.get("expYear") or "")) if x)
            main = [field("cardholder", "cardholder name", c.get("cardholderName")),
                    field("brand", "type", c.get("brand")),
                    field("number", "number", c.get("number"), "secret", True, "password"),
                    field("expiry", "expiry date", exp, "date"),
                    field("code", "verification number", c.get("code"), "secret", True)]
        elif kind == "identity":
            i = e.get("identity") or {}
            main = [field(k, LABELS.get(k, k), i.get(n), "email" if k == "email" else "phone" if k == "phone" else
                          "secret" if k in IDENTITY_SECRET else "text", k in IDENTITY_SECRET,
                          "username" if k == "username" else "") for k, n in IDENTITY]
        elif kind == "ssh":
            s = e.get("sshKey") or {}
            main = [field("public", "public key", s.get("publicKey")),
                    field("fingerprint", "fingerprint", s.get("keyFingerprint")),
                    field("private", "private key", s.get("privateKey"), "secret", True)]
        uris = [u.get("uri") for u in (e.get("login") or {}).get("uris") or [] if u.get("uri")]
        sections = [section("", main)]
        if uris:
            sections.append(section("websites", [field(f"url{i}", "website", u, "url")
                                                 for i, u in enumerate(uris)]))
        extra = []
        for n, f in enumerate(e.get("fields") or []):
            t = f.get("type")
            if t == 3:
                continue          # a linked field: its value is another field's
            val = f.get("value")
            if t == 2:
                val = "yes" if str(val).lower() == "true" else "no"
            extra.append(field(f"c:{n}", f.get("name") or "field", val,
                               "secret" if t == 1 else "text", t == 1))
        sections.append(section("more", extra))
        hist = [field(f"h:{n}", "used until " + time.strftime("%-d %b %Y", time.localtime(iso_time(h.get("lastUsedDate")))),
                      h.get("password"), "secret", True)
                for n, h in enumerate(reversed(e.get("passwordHistory") or [])) if h.get("password")]
        sections.append(section("password history", hist))
        d = detail(self.row(e, v["folders"]), sections, e.get("notes") or "",
                   created=iso_time(e.get("creationDate")))
        d["attachments"] = [{"id": a.get("id"), "name": a.get("fileName"), "size": a.get("sizeName") or ""}
                            for a in e.get("attachments") or []]
        return d

    def totp(self, id, fieldref, cancel):
        code, out, err = self.bw(["get", "totp", id], cancel, timeout=60)
        if code != 0:
            raise VaultError(self.why(err))
        return out.strip()

    # ── writing ────────────────────────────────────────────────────────
    def folder_id(self, name, v, cancel):
        if not name:
            return None
        for fid, n in v["folders"].items():
            if n == name:
                return fid
        code, out, err = self.bw(["create", "folder"], cancel, stdin=b64({"name": name}), timeout=60)
        if code != 0:
            raise VaultError(self.why(err))
        made = json.loads(out)
        v["folders"][made["id"]] = name
        return made["id"]

    def folders(self, cancel):
        return sorted(self.vault(cancel)["folders"].values(), key=str.lower)

    def save(self, id, draft, cancel):
        v = self.vault(cancel)
        kind = draft.get("kind") or "login"
        if id:
            e = copy.deepcopy(self.raw(id, cancel)[0])
        else:
            e = {"type": TYPE_OF.get(kind, 1), "name": "", "notes": None, "favorite": False,
                 "folderId": None, "fields": [], "reprompt": 0, "organizationId": None,
                 "collectionIds": None}
            if kind == "login":
                e["login"] = {"uris": [], "username": None, "password": None, "totp": None}
            elif kind == "note":
                e["secureNote"] = {"type": 0}
            elif kind == "card":
                e["card"] = {}
            elif kind == "identity":
                e["identity"] = {}
            elif kind == "ssh":
                e["sshKey"] = {}
        f = draft.get("fields") or {}
        put = lambda obj, key, k: obj.__setitem__(key, f[k] or None) if k in f and f[k] is not None else None
        e["name"] = draft.get("title") or e.get("name") or "(untitled)"
        if "notes" in draft:
            e["notes"] = draft["notes"] or None
        if "fav" in draft:
            e["favorite"] = bool(draft["fav"])
        if "folder" in draft:
            e["folderId"] = self.folder_id(draft["folder"], v, cancel)
        if kind == "login":
            l = e.setdefault("login", {})
            put(l, "username", "username")
            put(l, "password", "password")
            put(l, "totp", "totp")
            if "urls" in draft:
                old = {u.get("uri"): u for u in l.get("uris") or []}
                l["uris"] = [old.get(u) or {"match": None, "uri": u} for u in draft["urls"] if u]
        elif kind == "card":
            c = e.setdefault("card", {})
            put(c, "cardholderName", "cardholder")
            put(c, "brand", "brand")
            put(c, "number", "number")
            put(c, "code", "code")
            if f.get("expiry") is not None:
                mm, _, yy = str(f["expiry"]).partition("/")
                c["expMonth"] = mm.strip().lstrip("0") or None
                c["expYear"] = yy.strip() or None
        elif kind == "identity":
            i = e.setdefault("identity", {})
            for k, n in IDENTITY:
                put(i, n, k)
        elif kind == "ssh":
            s = e.setdefault("sshKey", {})
            put(s, "privateKey", "private")
            put(s, "publicKey", "public")
            put(s, "keyFingerprint", "fingerprint")
        if "custom" in draft:
            old = e.get("fields") or []
            new = [x for x in old if x.get("type") == 3]      # linked ones stay
            for c in draft["custom"]:
                ref = str(c.get("ref") or "")
                val = c.get("value")
                if val is None and ref.startswith("c:"):
                    n = int(ref[2:])
                    val = old[n].get("value") if n < len(old) else ""
                new.append({"name": c.get("label") or "field", "value": val or "",
                            "type": 1 if c.get("hidden") else 0, "linkedId": None})
            e["fields"] = new
        for k in ("object", "revisionDate", "creationDate", "deletedDate", "passwordHistory",
                  "attachments") if not id else ():
            e.pop(k, None)
        args = ["edit", "item", id] if id else ["create", "item"]
        code, out, err = self.bw(args, cancel, stdin=b64(e), timeout=120)
        if code != 0:
            raise VaultError(self.why(err, out))
        try:
            saved = json.loads(out)
        except ValueError:
            saved = None
        if saved and saved.get("id"):
            with _lock:
                if self.aid in _vaults:
                    _vaults[self.aid]["items"][saved["id"]] = saved
            return {"id": saved["id"]}
        with _lock:
            _vaults.pop(self.aid, None)
        return {"id": id}

    def delete(self, id, permanent, cancel):
        args = ["delete", "item", id] + (["--permanent"] if permanent else [])
        code, _, err = self.bw(args, cancel, timeout=60)
        if code != 0:
            raise VaultError(self.why(err))
        with _lock:
            if self.aid in _vaults:
                _vaults[self.aid]["items"].pop(id, None)
        return {}

    def trash(self, cancel):
        v = self.vault(cancel)
        return [self.row(e, v["folders"]) for e in self.json(["list", "items", "--trash"], cancel) or []]

    def restore(self, id, cancel):
        code, _, err = self.bw(["restore", "item", id], cancel, timeout=60)
        if code != 0:
            raise VaultError(self.why(err))
        with _lock:
            _vaults.pop(self.aid, None)
        return {}

    def audit_secrets(self, cancel):
        out = {}
        for iid, e in self.vault(cancel)["items"].items():
            l = e.get("login") or {}
            out[iid] = {"password": l.get("password") or "",
                        "urls": [u.get("uri") for u in l.get("uris") or [] if u.get("uri")],
                        "totp": bool(l.get("totp"))}
        return out

    # ── attachments ────────────────────────────────────────────────────
    def attachment_save(self, id, att, path, cancel):
        code, _, err = self.bw(["get", "attachment", att, "--itemid", id, "--output", path],
                               cancel, timeout=300)
        if code != 0:
            raise VaultError(self.why(err))
        return {"path": path}

    def attachment_add(self, id, path, cancel):
        code, out, err = self.bw(["create", "attachment", "--file", path, "--itemid", id],
                                 cancel, timeout=600)
        if code != 0:
            raise VaultError(self.why(err, out))
        with _lock:
            _vaults.pop(self.aid, None)
        return {}

    def attachment_remove(self, id, att, cancel):
        code, _, err = self.bw(["delete", "attachment", att, "--itemid", id], cancel, timeout=60)
        if code != 0:
            raise VaultError(self.why(err))
        with _lock:
            _vaults.pop(self.aid, None)
        return {}

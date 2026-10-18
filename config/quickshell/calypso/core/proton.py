# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# PROTON PASS, through pass-cli (proton-pass-cli, from the AUR).
#
# pass-cli keeps ONE signed-in session on the machine, in a place of its
# own, until `pass-cli logout`. There is no separate lock: so here, locking
# only shuts calypso's view of it (nothing listed, nothing handed over)
# until it is opened again; signing out is Remove's business.
#
# Signing in, two ways (pass-cli login):
#   in the browser   pass-cli prints an address; it is shown to be opened,
#                    and pass-cli waits until the sign-in there is done
#   here             --interactive: the password goes through a fifo named
#                    in PROTON_PASS_PASSWORD_FILE (never this process' own
#                    environment), the 2FA code in PROTON_PASS_TOTP
#
# Proton documents the commands, not the JSON they print, so what comes back
# is read loosely (pick/kind_of): the names below are the ones its docs and
# templates use (title, username, email, password, urls, totp…), looked for
# at any depth of an item.

import json
import re
import threading

from base import (Fifo, Locked, Provider, VaultError, detail, field, first_line, host_of,
                  item, iso_time, run, section)

_shut = set()          # accounts shut here (calypso's lock), by id
_lock = threading.Lock()

ITEM_KINDS = {"login": "login", "note": "note", "creditcard": "card", "credit_card": "card",
              "card": "card", "identity": "identity", "alias": "login", "sshkey": "ssh",
              "ssh_key": "ssh", "wifi": "password", "custom": "other"}


def walk(o, depth=0):
    """every (key, value) pair in a JSON value, outermost first"""
    if depth > 6:
        return
    if isinstance(o, dict):
        for k, v in o.items():
            yield k, v
        for v in o.values():
            if isinstance(v, (dict, list)):
                yield from walk(v, depth + 1)
    elif isinstance(o, list):
        for v in o:
            yield from walk(v, depth + 1)


def pick(o, *names):
    """the first non-empty value under any of `names`, at any depth"""
    want = {n.lower().replace("_", "") for n in names}
    for k, v in walk(o):
        if str(k).lower().replace("_", "") in want and v not in (None, "", [], {}):
            return v
    return None


def kind_of(o):
    t = pick(o, "item_type", "itemType", "type", "kind")
    if isinstance(t, str):
        return ITEM_KINDS.get(t.lower().replace(" ", ""), "other")
    if isinstance(t, dict) and t:
        return ITEM_KINDS.get(next(iter(t)).lower(), "other")
    content = pick(o, "content")
    if isinstance(content, dict) and len(content) == 1:
        return ITEM_KINDS.get(next(iter(content)).lower(), "other")
    if pick(o, "password", "username", "email", "urls"):
        return "login"
    return "note"


def when(v):
    """a time as pass-cli may give it: epoch seconds or ms, or ISO 8601"""
    if isinstance(v, (int, float)):
        return int(v / 1000 if v > 1e11 else v)
    return iso_time(v)


def as_list(data, *keys):
    if isinstance(data, list):
        return data
    if isinstance(data, dict):
        for k in keys:
            if isinstance(data.get(k), list):
                return data[k]
        for v in data.values():
            if isinstance(v, list):
                return v
    return []


class Proton(Provider):
    KIND = "proton"
    NAME = "Proton Pass"
    CLI = "pass-cli"
    PKG = "proton-pass-cli-bin"
    AUR = True
    ASKS = ""
    BLURB = "pass-cli stays signed in on this machine; locking here only hides the vault"
    # pass-cli makes logins only, and cannot set a one-time password or
    # move an item (its docs, 2026-10-12); deleting is for good
    CAN = {"create": ["login"], "edit": True, "delete": "delete", "restore": False,
           "custom": True, "totpEdit": False, "folders": True, "attachments": False,
           "fav": False, "tags": False, "history": False}

    def pc(self, args, cancel, **kw):
        return run(["pass-cli"] + args, cancel, **kw)

    def signed_in(self, cancel):
        code, out, _ = self.pc(["info"], cancel, timeout=30)
        if code != 0:
            return None
        m = re.search(r"[\w.+-]+@[\w-]+(\.[\w-]+)+", out)
        return m.group(0) if m else "signed in"

    def status(self, cancel):
        who = self.signed_in(cancel)
        with _lock:
            shut = self.cfg.get("id") in _shut
        return {"configured": who is not None, "unlocked": who is not None and not shut,
                "user": who or ""}

    def setup(self, params, secret, cancel, emit):
        how = params.get("how") or "browser"
        if how == "browser":
            return self.browser(cancel, emit)
        email = str(params.get("email") or "").strip()
        if not email or not secret:
            raise VaultError("Your Proton email and password are needed")
        env = {}
        code2fa = str(params.get("totp") or "").strip()
        if code2fa:
            env["PROTON_PASS_TOTP"] = code2fa
        extra = params.get("extra") or None
        with Fifo("calypso-proton", secret) as f, Fifo("calypso-proton-extra", extra) as x:
            env["PROTON_PASS_PASSWORD_FILE"] = f.path
            if extra:
                env["PROTON_PASS_EXTRA_PASSWORD_FILE"] = x.path
            code, out, err = self.pc(["login", "--interactive", email], cancel, env=env,
                                     timeout=180)
        if code != 0:
            low = (err + out).lower()
            if "totp" in low or "2fa" in low or "two-factor" in low:
                raise VaultError("Proton wants your 2FA code too", "auth")
            if "password" in low or "credentials" in low:
                raise VaultError("Wrong email or password", "auth")
            raise VaultError(first_line(err) or first_line(out) or "pass-cli could not sign in")
        with _lock:
            _shut.discard(self.cfg.get("id"))
        return self.status(cancel)

    def browser(self, cancel, emit):
        """pass-cli login, its address handed on as an event the moment it is
        printed; done when pass-cli says the browser's sign-in landed."""
        import os
        import subprocess
        p = subprocess.Popen(["pass-cli", "login"], stdin=subprocess.DEVNULL,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             start_new_session=True,
                             env=dict(os.environ, NO_COLOR="1", TERM="dumb"))
        cancel.attach(p)
        said = False
        lines = []
        try:
            for raw in p.stdout:
                line = raw.decode(errors="replace").strip()
                lines.append(line)
                m = re.search(r"https://\S+", line)
                if m and not said:
                    said = True
                    emit({"url": m.group(0).rstrip(".,)")})
            p.wait(timeout=900)
        finally:
            cancel.detach(p)
        cancel.check()
        if p.returncode != 0:
            raise VaultError(next((l for l in reversed(lines) if l), "") or "pass-cli could not sign in")
        with _lock:
            _shut.discard(self.cfg.get("id"))
        return self.status(cancel)

    def unlock(self, secret, cancel):
        if self.signed_in(cancel) is None:
            raise VaultError("Proton Pass is signed out — add it again to sign in", "auth")
        with _lock:
            _shut.discard(self.cfg.get("id"))
        return {}

    def lock(self, cancel):
        with _lock:
            _shut.add(self.cfg.get("id"))
        return {}

    def forget(self, cancel):
        self.pc(["logout"], cancel, timeout=30)
        with _lock:
            _shut.discard(self.cfg.get("id"))
        return {}

    def need(self, cancel):
        with _lock:
            if self.cfg.get("id") in _shut:
                raise Locked()

    def json(self, args, cancel, timeout=120):
        self.need(cancel)
        code, out, err = self.pc(args + ["--output", "json"], cancel, timeout=timeout)
        if code != 0:
            low = (err + out).lower()
            if "login" in low or "session" in low or "not logged" in low:
                raise Locked("Proton Pass is signed out")
            raise VaultError(first_line(err) or "pass-cli failed")
        try:
            return json.loads(out or "null")
        except ValueError:
            raise VaultError("pass-cli said something that is not JSON")

    def vaults(self, cancel):
        out = []
        for v in as_list(self.json(["vault", "list"], cancel), "vaults", "shares"):
            sid = pick(v, "share_id", "shareId", "id")
            if sid:
                out.append((str(sid), str(pick(v, "name", "title") or "")))
        return out

    def items(self, cancel):
        rows = []
        for sid, vname in self.vaults(cancel):
            cancel.check()
            for e in as_list(self.json(["item", "list", "--share-id", sid], cancel, 300), "items"):
                iid = pick(e, "item_id", "itemId", "id")
                if not iid:
                    continue
                kind = kind_of(e)
                urls = pick(e, "urls", "url") or []
                url = urls[0] if isinstance(urls, list) and urls else urls if isinstance(urls, str) else ""
                rows.append(item(f"{sid}/{iid}", pick(e, "title", "name"),
                                 pick(e, "username", "email", "itemEmail") or "", kind,
                                 host_of(url), vname, bool(pick(e, "pinned", "favorite")), [],
                                 when(pick(e, "modify_time", "modifyTime", "update_time")),
                                 bool(pick(e, "totp_uri", "totpUri", "totp")) if kind == "login" else False))
        return rows

    def split(self, id):
        sid, _, iid = str(id).partition("/")
        return sid, iid

    def detail(self, id, cancel, secret=None):
        sid, iid = self.split(id)
        e = self.json(["item", "view", "--share-id", sid, "--item-id", iid], cancel)
        kind = kind_of(e)
        urls = pick(e, "urls") or []
        urls = urls if isinstance(urls, list) else [urls]
        totp = pick(e, "totp_uri", "totpUri", "totp")
        main = []
        if kind == "login":
            main = [field("username", "username", pick(e, "username"), role="username"),
                    field("email", "email", pick(e, "email", "itemEmail"), "email",
                          role="" if pick(e, "username") else "username"),
                    field("password", "password", pick(e, "password"), "secret", True, "password"),
                    field("totp", "one-time password", totp, "totp", True, "totp") if totp else None]
        elif kind == "card":
            main = [field("holder", "cardholder name", pick(e, "cardholder_name", "cardholderName")),
                    field("number", "number", pick(e, "number"), "secret", True, "password"),
                    field("expiry", "expiry date", pick(e, "expiration_date", "expirationDate"), "date"),
                    field("cvv", "verification number", pick(e, "verification_number", "cvv"), "secret", True),
                    field("pin", "PIN", pick(e, "pin"), "secret", True)]
        elif kind == "ssh":
            main = [field("public", "public key", pick(e, "public_key", "publicKey")),
                    field("private", "private key", pick(e, "private_key", "privateKey"), "secret", True)]
        elif kind == "password":
            main = [field("ssid", "network", pick(e, "ssid")),
                    field("password", "password", pick(e, "password"), "secret", True, "password")]
        extra = []
        for i, f in enumerate(pick(e, "extra_fields", "extraFields", "custom_fields") or []):
            if not isinstance(f, dict):
                continue
            name = pick(f, "name", "field_name", "label") or "field"
            val = pick(f, "value", "content", "text", "hidden")
            hidden = bool(pick(f, "hidden")) or "hidden" in str(pick(f, "type") or "").lower()
            if "totp" in str(pick(f, "type") or "").lower():
                extra.append(field(f"extra{i}", name, val, "totp", True))
            else:
                extra.append(field(f"extra{i}", name, val, "secret" if hidden else "text", hidden))
        sections = [section("", main)]
        if urls:
            sections.append(section("websites", [field(f"url{i}", "website", u, "url")
                                                 for i, u in enumerate(urls) if u]))
        sections.append(section("more", extra))
        it = item(id, pick(e, "title", "name"), pick(e, "username", "email") or "", kind,
                  host_of(urls[0]) if urls else "", "", bool(pick(e, "pinned")), [],
                  when(pick(e, "modify_time", "modifyTime")), bool(totp))
        return detail(it, sections, pick(e, "note", "notes") or "",
                      created=when(pick(e, "create_time", "createTime")))

    def folders(self, cancel):
        return sorted((n for _, n in self.vaults(cancel) if n), key=str.lower)

    def save(self, id, draft, cancel):
        f = draft.get("fields") or {}
        vault = draft.get("folder") or ""
        if not id:
            if (draft.get("kind") or "login") != "login":
                raise VaultError("pass-cli makes logins only — other kinds are made in Proton Pass itself")
            t = {"title": draft.get("title") or "(untitled)", "username": f.get("username") or "",
                 "password": f.get("password") or "", "urls": [u for u in draft.get("urls") or [] if u]}
            if "@" in t["username"] and not f.get("email"):
                t["email"], t["username"] = t["username"], ""
            argv = ["item", "create", "login", "--from-template", "-"] + (["--vault-name", vault] if vault else [])
            self.need(cancel)
            code, out, err = self.pc(argv, cancel, stdin=json.dumps(t), timeout=120)
            if code != 0:
                raise VaultError(first_line(err) or "pass-cli could not make the item")
            m = re.search(r'"?(?:item_?id|id)"?\s*[:=]\s*"?([A-Za-z0-9_=-]{8,})', out)
            return {"id": None}
        sid, iid = self.split(id)
        # Only --field: pass-cli takes no other way in, so a changed secret
        # is in pass-cli's argv for the moment it runs.
        sets = [("title", draft.get("title"))]
        for key in ("username", "password", "email"):
            if f.get(key) is not None:
                sets.append((key, f[key]))
        if "notes" in draft:
            sets.append(("note", draft["notes"]))
        if "urls" in draft and draft["urls"]:
            sets.append(("url", draft["urls"][0]))
        for c in draft.get("custom") or []:
            if c.get("value") is not None:
                sets.append((str(c.get("label") or "field"), c["value"]))
        argv = ["item", "update", "--share-id", sid, "--item-id", iid]
        for k, v in sets:
            if v is not None:
                argv += ["--field", f"{k}={v}"]
        self.need(cancel)
        code, _, err = self.pc(argv, cancel, timeout=120)
        if code != 0:
            raise VaultError(first_line(err) or "pass-cli could not save the item")
        return {"id": id}

    def delete(self, id, permanent, cancel):
        sid, iid = self.split(id)
        self.need(cancel)
        code, _, err = self.pc(["item", "delete", "--share-id", sid, "--item-id", iid], cancel, timeout=60)
        if code != 0:
            raise VaultError(first_line(err) or "pass-cli could not delete it")
        return {}

    def totp(self, id, fieldref, cancel):
        """Made here (server.py) from the item's otpauth value when there is
        one; pass-cli is asked only for a field that came without it."""
        sid, iid = self.split(id)
        codes = self.json(["item", "totp", "--share-id", sid, "--item-id", iid], cancel)
        if isinstance(codes, dict) and codes:
            return str(codes.get("totp") or next(iter(codes.values())))
        raise VaultError("Proton Pass has no code for this item")

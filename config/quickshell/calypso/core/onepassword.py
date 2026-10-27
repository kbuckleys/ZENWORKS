# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# 1PASSWORD, through op (1password-cli, from the AUR).
#
# op signs in per account and hands back a SESSION TOKEN (op signin --raw),
# good for 30 minutes of use. This daemon keeps it in memory and nowhere else
# — never a file, never this process' environment — and passes it to each op
# call; "unlocked" is having one op still accepts. Locking signs out
# (op signout), which ends the session on 1Password's side too.
#
# The account's password goes over op's stdin: with no terminal, op reads it
# from there. Adding an account wants the sign-in address, the email and the
# Secret Key as well (op account add); after that, only the password.
#
# With the 1Password desktop app's CLI integration turned on, op asks the app
# instead and the password typed here is not needed — the app's own prompt
# comes up (system authentication).

import json
import re
import threading

from base import (Locked, Provider, VaultError, detail, field, first_line, host_of,
                  item, iso_time, run, section)

KINDS = {"LOGIN": "login", "PASSWORD": "password", "SECURE_NOTE": "note",
         "CREDIT_CARD": "card", "IDENTITY": "identity", "SSH_KEY": "ssh",
         "API_CREDENTIAL": "password", "DATABASE": "password", "SERVER": "password",
         "WIRELESS_ROUTER": "password", "EMAIL_ACCOUNT": "login", "BANK_ACCOUNT": "card",
         "PASSPORT": "identity", "DRIVER_LICENSE": "identity",
         "SOCIAL_SECURITY_NUMBER": "identity", "MEMBERSHIP": "card",
         "REWARD_PROGRAM": "card", "SOFTWARE_LICENSE": "other", "DOCUMENT": "other",
         "OUTDOOR_LICENSE": "identity", "MEDICAL_RECORD": "other", "CRYPTO_WALLET": "other"}

# 1Password's own field ids, and the shared keys the window edits by
# (base.Provider.save), each way
OP2STD = {"username": "username", "password": "password", "cardholder": "cardholder",
          "type": "brand", "ccnum": "number", "cvv": "code", "expiry": "expiry",
          "firstname": "first", "lastname": "last", "initial": "middle", "company": "company",
          "email": "email", "defphone": "phone", "address": "address1",
          "private_key": "private", "public_key": "public", "fingerprint": "fingerprint"}
STD2OP = {v: k for k, v in OP2STD.items()}
CATEGORY = {"login": "LOGIN", "password": "PASSWORD", "note": "SECURE_NOTE",
            "card": "CREDIT_CARD", "identity": "IDENTITY"}

# the tokens, by account id — this daemon's memory only
_tokens = {}
_lock = threading.Lock()
# HOW EACH ACCOUNT'S SESSION IS HANDED TO op (audit, 2026-10-27): "env" —
# in op's environment, where only this user can read it — or "argv", the
# old --session flag, which any user on the machine can read off the
# process list while op runs. Settled at each unlock by trying the
# environment first (_settle); anything not yet proven goes by argv, so a
# version of op that reads the environment differently still unlocks.
_via = {}
# the account's user ID, from `op account list`, for OP_SESSION_<id>
_uuids = {}


class OnePassword(Provider):
    KIND = "onepassword"
    NAME = "1Password"
    CLI = "op"
    PKG = "1password-cli"
    AUR = True
    BLURB = "op's session lasts 30 minutes of use; locking here signs it out"
    CAN = {"create": ["login", "password", "note", "card", "identity"], "edit": True,
           "delete": "archive", "restore": False, "custom": True, "totpEdit": True,
           "folders": True, "attachments": False, "fav": True, "tags": True, "history": False}

    @property
    def account(self):
        # what op calls the account: the shorthand calypso gave it, else its
        # sign-in address
        return str(self.cfg.get("shorthand") or self.cfg.get("address") or "")

    def token(self):
        with _lock:
            return _tokens.get(self.cfg.get("id"))

    def session_env(self, t):
        """The token under every name op is known to read: OP_SESSION (the
        documented one), and OP_SESSION_<shorthand> / OP_SESSION_<user ID>
        (what op signin has printed, by version) where the name is a valid
        variable name — a shorthand like my.1password.com is not."""
        env = {"OP_SESSION": t}
        with _lock:
            uuid = _uuids.get(self.cfg.get("id"))
        for n in (str(self.cfg.get("shorthand") or ""), str(uuid or "")):
            if re.fullmatch(r"[A-Za-z0-9_]+", n):
                env["OP_SESSION_" + n] = t
        return env

    def op(self, args, cancel, token=True, **kw):
        argv = ["op"] + args
        if self.account:
            argv += ["--account", self.account]
        t = self.token() if token else None
        if t:
            with _lock:
                via = _via.get(self.cfg.get("id"), "argv")
            if via == "env":
                kw["env"] = dict(kw.get("env") or {}, **self.session_env(t))
            else:
                argv += ["--session", t]
        return run(argv, cancel, **kw)

    def _settle(self, cancel):
        """A fresh token: does op take it from the environment? Asked once,
        with `whoami` and no --session; the answer is how every call of this
        account passes it until the next unlock."""
        aid = self.cfg.get("id")
        for a in self.known(cancel):
            if self.account in (a.get("shorthand"), a.get("url"), a.get("account_uuid"), a.get("user_uuid")):
                with _lock:
                    _uuids[aid] = a.get("user_uuid") or ""
                break
        with _lock:
            _via[aid] = "env"
        code, _, _ = self.op(["whoami", "--format", "json"], cancel, timeout=20)
        if code != 0:
            with _lock:
                _via[aid] = "argv"

    def known(self, cancel):
        code, out, _ = run(["op", "account", "list", "--format", "json"], cancel, timeout=20)
        try:
            return json.loads(out) if code == 0 else []
        except ValueError:
            return []

    def status(self, cancel):
        acc = None
        for a in self.known(cancel):
            if self.account in (a.get("shorthand"), a.get("url"), a.get("account_uuid"),
                                a.get("user_uuid")):
                acc = a
                break
        unlocked = False
        if acc and self.token():
            code, _, _ = self.op(["whoami", "--format", "json"], cancel, timeout=20)
            unlocked = code == 0
            if not unlocked:
                with _lock:
                    _tokens.pop(self.cfg.get("id"), None)
        return {"configured": bool(acc), "unlocked": unlocked,
                "user": (acc or {}).get("email") or self.cfg.get("email") or "",
                "server": (acc or {}).get("url") or self.cfg.get("address") or ""}

    def setup(self, params, secret, cancel, emit):
        address = str(params.get("address") or "my.1password.com").strip()
        address = re.sub(r"^https?://", "", address).rstrip("/")
        email = str(params.get("email") or "").strip()
        key = str(params.get("secretKey") or "").strip().upper()
        short = str(params.get("shorthand") or self.cfg.get("shorthand") or "").strip()
        if "@" not in email:
            raise VaultError("That does not look like an email address")
        if not re.match(r"^A3-[A-Z0-9]{6}(-[A-Z0-9]{5,6}){4}$", key.replace(" ", "")):
            raise VaultError("A Secret Key looks like A3-XXXXXX-XXXXXX-XXXXX-XXXXX-XXXXX — it is in your Emergency Kit")
        if not secret:
            raise VaultError("Your 1Password account password is needed to add it")
        argv = ["op", "account", "add", "--address", address, "--email", email,
                "--secret-key", key.replace(" ", ""), "--signin", "--raw"]
        if short:
            argv += ["--shorthand", short]
        code, out, err = run(argv, cancel, stdin=secret + "\n", timeout=120)
        if code != 0:
            raise VaultError(self.why(err), "auth")
        t = out.strip().splitlines()[-1].strip() if out.strip() else ""
        if t:
            with _lock:
                _tokens[self.cfg.get("id")] = t
        self.cfg.update({"address": address, "email": email, "shorthand": short or address})
        if t:
            self._settle(cancel)
        return dict(self.status(cancel), shorthand=short or address, address=address)

    def why(self, err):
        low = err.lower()
        if "secret key" in low:
            return "1Password did not accept that Secret Key"
        if "password" in low or "unauthorized" in low or "401" in low:
            return "Wrong password"
        if "connect" in low or "network" in low or "dial" in low or "timeout" in low:
            return "Could not reach 1Password"
        return first_line(err).replace("[ERROR] ", "") or "op could not sign in"

    def unlock(self, secret, cancel):
        code, out, err = run(["op", "signin", "--account", self.account, "--raw"], cancel,
                             stdin=(secret or "") + "\n", timeout=120)
        t = out.strip()
        if code != 0 or not t:
            raise VaultError(self.why(err), "auth")
        with _lock:
            _tokens[self.cfg.get("id")] = t.splitlines()[-1].strip()
        self._settle(cancel)
        return {}

    def lock(self, cancel):
        if self.token():
            self.op(["signout"], cancel, timeout=20)
        with _lock:
            _tokens.pop(self.cfg.get("id"), None)
            _via.pop(self.cfg.get("id"), None)
        return {}

    def forget(self, cancel):
        self.lock(cancel)
        run(["op", "account", "forget", self.account], cancel, timeout=20)
        return {}

    def need(self, cancel):
        if not self.token():
            raise Locked()

    def json(self, args, cancel, timeout=120):
        self.need(cancel)
        code, out, err = self.op(args + ["--format", "json"], cancel, timeout=timeout)
        if code != 0:
            low = err.lower()
            if "session" in low or "signin" in low or "sign in" in low or "not currently signed" in low:
                with _lock:
                    _tokens.pop(self.cfg.get("id"), None)
                raise Locked()
            raise VaultError(first_line(err).replace("[ERROR] ", "") or "op failed")
        try:
            return json.loads(out or "null")
        except ValueError:
            raise VaultError("op said something that is not JSON")

    def items(self, cancel):
        rows = []
        for e in self.json(["item", "list"], cancel) or []:
            urls = e.get("urls") or []
            primary = next((u.get("href") for u in urls if u.get("primary")), None) \
                or (urls[0].get("href") if urls else "")
            kind = KINDS.get(e.get("category") or "", "other")
            rows.append(item(e.get("id"), e.get("title"), e.get("additional_information") or "",
                             kind, host_of(primary), (e.get("vault") or {}).get("name", ""),
                             e.get("favorite"), e.get("tags") or [], iso_time(e.get("updated_at")),
                             None if kind == "login" else False))
        return rows

    def detail(self, id, cancel, secret=None):
        e = self.json(["item", "get", id, "--reveal"], cancel)
        kind = KINDS.get(e.get("category") or "", "other")
        by_section = {}
        order = []
        notes = ""
        has_totp = False
        sub = ""
        for i, f in enumerate(e.get("fields") or []):
            purpose = f.get("purpose") or ""
            typ = (f.get("type") or "STRING").upper()
            label = f.get("label") or purpose.lower() or "field"
            value = f.get("value")
            if purpose == "NOTES":
                notes = value or ""
                continue
            fid = f.get("id") or f"f{i}"
            std = OP2STD.get(fid) if not (f.get("section") or {}).get("label") else None
            ref = "totp" if typ == "OTP" and not has_totp else std or "c:" + fid
            if isinstance(value, dict):
                value = ", ".join(str(v) for v in value.values() if v)
            if typ == "MONTH_YEAR" and value and len(str(value)) == 6:
                value = str(value)[4:] + "/" + str(value)[:4]
            if typ == "OTP":
                has_totp = True
                fl = field(ref, "one-time password", value or "x", "totp", True, "totp")
            elif typ == "CONCEALED" or purpose == "PASSWORD":
                fl = field(ref, label, value, "secret", True,
                           "password" if purpose == "PASSWORD" else "")
            else:
                k = {"URL": "url", "EMAIL": "email", "PHONE": "phone", "DATE": "date",
                     "MONTH_YEAR": "date"}.get(typ, "text")
                fl = field(ref, label, value, k, False,
                           "username" if purpose == "USERNAME" else "")
                if purpose == "USERNAME":
                    sub = value or ""
            sec = (f.get("section") or {}).get("label") or ""
            if sec not in by_section:
                by_section[sec] = []
                order.append(sec)
            by_section[sec].append(fl)
        sections = [section(s, by_section[s]) for s in order]
        urls = [u.get("href") for u in e.get("urls") or [] if u.get("href")]
        if urls:
            sections.insert(1 if sections else 0,
                            section("websites", [field(f"url{i}", u_label(e, i), u, "url")
                                                 for i, u in enumerate(urls)]))
        it = item(e.get("id"), e.get("title"), sub, kind, host_of(urls[0]) if urls else "",
                  (e.get("vault") or {}).get("name", ""), e.get("favorite"), e.get("tags") or [],
                  iso_time(e.get("updated_at")), has_totp)
        return detail(it, sections, notes, created=iso_time(e.get("created_at")))

    # ── writing: 1Password's own JSON, over stdin ──────────────────────────
    def vaults(self, cancel):
        return self.json(["vault", "list"], cancel) or []

    def folders(self, cancel):
        return sorted((v.get("name") or "" for v in self.vaults(cancel)), key=str.lower)

    def save(self, id, draft, cancel):
        import copy
        kind = draft.get("kind") or "login"
        f = draft.get("fields") or {}
        if id:
            e = copy.deepcopy(self.json(["item", "get", id, "--reveal"], cancel))
        else:
            e = {"title": "", "category": CATEGORY.get(kind, "LOGIN"), "fields": [], "urls": []}
            if kind in ("login", "password"):
                if kind == "login":
                    e["fields"].append({"id": "username", "type": "STRING", "purpose": "USERNAME", "label": "username", "value": ""})
                e["fields"].append({"id": "password", "type": "CONCEALED", "purpose": "PASSWORD", "label": "password", "value": ""})
            e["fields"].append({"id": "notesPlain", "type": "STRING", "purpose": "NOTES", "label": "notesPlain", "value": ""})
        fields = e.setdefault("fields", [])
        byid = {x.get("id"): x for x in fields}
        e["title"] = draft.get("title") or e.get("title") or "(untitled)"
        for key, value in f.items():
            if value is None or key == "totp":
                continue
            oid = STD2OP.get(key, key)
            if key == "expiry" and value:
                mm, _, yy = str(value).partition("/")
                value = yy.strip() + mm.strip().zfill(2)
            if oid in byid:
                byid[oid]["value"] = value
            else:
                secret = key in ("password", "number", "code", "private")
                x = {"id": oid, "type": "CONCEALED" if secret else ("MONTH_YEAR" if key == "expiry" else "STRING"),
                     "label": oid, "value": value}
                if key == "username":
                    x["purpose"] = "USERNAME"
                if key == "password":
                    x["purpose"] = "PASSWORD"
                fields.append(x)
                byid[oid] = x
        if f.get("totp") is not None:
            otp = next((x for x in fields if (x.get("type") or "").upper() == "OTP"), None)
            if otp is None and f["totp"]:
                fields.append({"id": "totp", "type": "OTP", "label": "one-time password", "value": f["totp"]})
            elif otp is not None:
                if f["totp"]:
                    otp["value"] = f["totp"]
                else:
                    fields.remove(otp)
        if "notes" in draft:
            n = next((x for x in fields if x.get("purpose") == "NOTES"), None)
            if n is None:
                fields.append({"id": "notesPlain", "type": "STRING", "purpose": "NOTES",
                               "label": "notesPlain", "value": draft["notes"]})
            else:
                n["value"] = draft["notes"]
        if "custom" in draft:
            std_ids = set(OP2STD) | {"notesPlain"}
            keep = []
            for x in fields:
                if (x.get("id") in std_ids and not (x.get("section") or {}).get("label")) \
                        or (x.get("type") or "").upper() == "OTP" or x.get("purpose"):
                    keep.append(x)
            sec = {"id": "calypso", "label": "more"}
            for c in draft["custom"]:
                ref = str(c.get("ref") or "")
                old = byid.get(ref[2:]) if ref.startswith("c:") else None
                val = c.get("value")
                if val is None and old is not None:
                    val = old.get("value")
                x = dict(old) if old else {"id": "", "section": sec}
                x.update({"label": c.get("label") or "field", "value": val or "",
                          "type": "CONCEALED" if c.get("hidden") else "STRING"})
                keep.append(x)
            if any((x.get("section") or {}).get("id") == "calypso" for x in keep):
                secs = e.setdefault("sections", [])
                if not any(s.get("id") == "calypso" for s in secs):
                    secs.append(sec)
            e["fields"] = keep
        if "urls" in draft:
            e["urls"] = [{"href": u, "primary": i == 0} for i, u in enumerate(u for u in draft["urls"] if u)]
        if "tags" in draft:
            e["tags"] = [t for t in draft["tags"] if t]
        for k in ("created_at", "updated_at", "last_edited_by", "version"):
            e.pop(k, None)
        vault = draft.get("folder") or (e.get("vault") or {}).get("name") or ""
        if id:
            self.need(cancel)
            code, out, err = self.op(["item", "edit", id, "--format", "json"], cancel,
                                     stdin=json.dumps(e), timeout=120)
            if code != 0:
                raise VaultError(first_line(err).replace("[ERROR] ", "") or "op could not save the item")
            if "fav" in draft:
                self.op(["item", "edit", id, "--favorite", "true" if draft["fav"] else "false"], cancel, timeout=60)
            now = (e.get("vault") or {}).get("name")
            if vault and now and vault != now:
                code, out, err = self.op(["item", "move", id, "--current-vault", now,
                                          "--destination-vault", vault], cancel, timeout=120)
                if code != 0:
                    raise VaultError(first_line(err).replace("[ERROR] ", "") or "op could not move the item")
                try:
                    id = json.loads(out).get("id") or id
                except ValueError:
                    pass
            return {"id": id}
        e.pop("vault", None)
        argv = ["item", "create", "--format", "json"] + (["--vault", vault] if vault else []) \
            + (["--favorite"] if draft.get("fav") else []) + ["-"]
        self.need(cancel)
        code, out, err = self.op(argv, cancel, stdin=json.dumps(e), timeout=120)
        if code != 0:
            raise VaultError(first_line(err).replace("[ERROR] ", "") or "op could not make the item")
        try:
            return {"id": json.loads(out).get("id")}
        except ValueError:
            return {"id": None}

    def delete(self, id, permanent, cancel):
        self.need(cancel)
        code, _, err = self.op(["item", "delete", id] + ([] if permanent else ["--archive"]),
                               cancel, timeout=60)
        if code != 0:
            raise VaultError(first_line(err).replace("[ERROR] ", "") or "op could not delete it")
        return {}

    def audit_secrets(self, cancel):
        # every item in one go: the list piped back into op item get
        self.need(cancel)
        code, listing, _ = self.op(["item", "list", "--categories", "Login,Password", "--format", "json"],
                                   cancel, timeout=120)
        if code != 0:
            return {}
        code, out, _ = self.op(["item", "get", "-", "--reveal", "--format", "json"], cancel,
                               stdin=listing, timeout=600)
        res = {}
        dec = json.JSONDecoder()
        text, pos = out.strip(), 0
        while pos < len(text):
            try:
                e, pos = dec.raw_decode(text, pos)
            except ValueError:
                break
            while pos < len(text) and text[pos] in " \n\r\t,":
                pos += 1
            for x in (e if isinstance(e, list) else [e]):
                fs = x.get("fields") or []
                res[x.get("id")] = {
                    "password": next((f.get("value") or "" for f in fs if f.get("purpose") == "PASSWORD"), ""),
                    "urls": [u.get("href") for u in x.get("urls") or [] if u.get("href")],
                    "totp": any((f.get("type") or "").upper() == "OTP" for f in fs)}
        return res

    def totp(self, id, fieldref, cancel):
        self.need(cancel)
        code, out, err = self.op(["item", "get", id, "--otp"], cancel, timeout=60)
        if code != 0:
            raise VaultError(first_line(err).replace("[ERROR] ", "") or "op could not make a code")
        return out.strip()


def u_label(e, i):
    u = (e.get("urls") or [])[i]
    return (u.get("label") or "website").lower()

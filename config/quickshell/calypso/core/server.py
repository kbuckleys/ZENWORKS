# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# THE DAEMON — calypso's backend, JSON lines on stdin/stdout (the suite's
# loop: morpheus/py/lines.py). Every request names the account it is for,
# whole, as the window keeps it:
#
#   {"id": 7, "op": "items", "account": {"id": "a1", "kind": "keepass",
#                                         "path": "~/vault.kdbx"}, "args": {}}
#
#   platforms                     every platform, its CLI there or not
#   status                        { configured, unlocked, user, note }
#   setup  {params, secret}       the first sign-in (adds the account)
#   unlock {secret} · lock · forget · sync
#   items                         the list (base.py's ITEM)
#   enrich                        what that left out, as events {rows}
#   detail {item, secret?}        an item, its secrets KEPT BACK (below)
#   reveal {item, ref}            one secret, to be shown
#   copy   {item, ref}            one secret onto the clipboard (hand.copy)
#   type   {item, parts}          typed where the cursor is (hand.type_):
#                                 parts are roles ("username", "password",
#                                 "totp"), refs, or "\t" / "\n"
#   totp   {item, ref?}           { code, period, left }
#   copyText {text} · typeText {text}   plain text (a username, a host)
#   save {item?, draft} · delete {item, permanent} · restore {item}
#   trash · folders                writing (base.Provider.save's draft)
#   generate {opts} · strength {text} · words · copySecret {text}
#   audit {pwned}                  Watchtower (audit.py)
#   scanQr                         an otpauth QR code, off the screen
#   attachmentSave/Add/Remove      files kept with an item
#
# SECRETS STAY HERE. A detail's secret fields reach the window with their
# value blanked; the values are kept in `held`, by account and item, for
# reveal/copy/type, and dropped on lock, on forget and when the daemon goes.
# A copy or a type never sends the secret back at all.

import os
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), "morpheus", "py"))

import lines  # noqa: E402
import audit  # noqa: E402
import generate  # noqa: E402
import hand  # noqa: E402
import totp as T  # noqa: E402
from base import Locked, VaultError  # noqa: E402
from bitwarden import Bitwarden  # noqa: E402
from keepass import KeePass  # noqa: E402
from onepassword import OnePassword  # noqa: E402
from passstore import GoPass, PassStore  # noqa: E402
from proton import Proton  # noqa: E402

PROTOCOL = 1

PLATFORMS = [Bitwarden, OnePassword, Proton, KeePass, PassStore, GoPass]
BY_KIND = {p.KIND: p for p in PLATFORMS}


def provider(account):
    if not isinstance(account, dict) or account.get("kind") not in BY_KIND:
        raise VaultError("No such platform: " + str((account or {}).get("kind")))
    return BY_KIND[account["kind"]](account)


def scan_qr(cancel):
    """A QR code on the screen (a site's "set up your authenticator" page):
    a region chosen with slurp, captured by grim into memory, read by
    zbarimg from stdin. Nothing is written to disk."""
    from base import needs, run as brun
    needs({"slurp": "slurp", "grim": "grim", "zbarimg": "zbar"}, "Scanning a QR code")
    code, region, _ = brun(["slurp"], cancel, timeout=120)
    if code != 0 or not region.strip():
        raise VaultError("No region chosen", "cancelled")
    import subprocess
    g = subprocess.run(["grim", "-g", region.strip(), "-t", "png", "-"], stdout=subprocess.PIPE,
                       stderr=subprocess.DEVNULL, timeout=30)
    if g.returncode != 0:
        raise VaultError("grim could not capture the screen")
    z = subprocess.run(["zbarimg", "--quiet", "--raw", "-"], input=g.stdout, stdout=subprocess.PIPE,
                       stderr=subprocess.DEVNULL, timeout=30)
    text = z.stdout.decode(errors="replace").strip().splitlines()
    codes = [t for t in text if t.lower().startswith("otpauth://")]
    if not codes:
        raise VaultError("No one-time password QR code there" if text else "No QR code there")
    return {"uri": codes[0]}


STD_KEYS = {"username", "password", "totp", "cardholder", "brand", "number", "expiry", "code",
            "title", "first", "middle", "last", "company", "email", "phone", "address1", "address2",
            "address3", "city", "state", "postal", "country", "ssn", "passport", "license",
            "private", "public", "fingerprint"}


def clear_of(args):
    """seconds before a copied secret leaves the clipboard (the window's
    setting); 0 keeps it"""
    try:
        return max(0, int(args.get("clear", hand.CLEAR_AFTER)))
    except (TypeError, ValueError):
        return hand.CLEAR_AFTER


def otp_of(value):
    """a totp field's value → totp.parse's spec (KeePass' seed + settings
    come joined by \\u0001)"""
    seed, _, settings = str(value or "").partition("\u0001")
    return T.parse(seed, settings)


class Server(lines.Service):
    def __init__(self):
        super().__init__()
        self.held = {}             # (account, item) → { ref: value, role:ref… }
        self.lock = threading.Lock()

    def failure(self, e):
        if isinstance(e, Locked):
            return {"kind": "locked", "error": str(e) if str(e) != "locked" else "The vault is locked"}
        if isinstance(e, VaultError):
            return {"kind": e.kind, "error": str(e), "pkgs": e.pkgs}
        if isinstance(e, RuntimeError):
            return {"kind": "hand", "error": str(e)}
        return None

    def forget_held(self, aid):
        with self.lock:
            for k in [k for k in self.held if k[0] == aid]:
                del self.held[k]

    def keep(self, aid, d):
        """the detail with its secrets taken out, and held"""
        vals = {}
        for s in d.get("sections", []):
            for f in s["fields"]:
                if f["secret"]:
                    vals[f["ref"]] = f["value"]
                    f["length"] = len(f["value"])
                    f["value"] = ""
                else:
                    vals[f["ref"]] = f["value"]
                if f["role"]:
                    vals["role:" + f["role"]] = f["ref"]
        with self.lock:
            self.held[(aid, d.get("id"))] = vals
        return d

    def value(self, p, aid, iid, ref, cancel):
        with self.lock:
            vals = self.held.get((aid, iid))
        if vals is None or (ref not in vals and "role:" + ref not in vals):
            d = p.detail(iid, cancel)
            if d.get("reprompt"):
                raise VaultError("This item asks for your master password first — open it in calypso's window", "reprompt")
            self.keep(aid, d)
            with self.lock:
                vals = self.held.get((aid, iid)) or {}
        if ref not in vals and "role:" + ref in vals:
            ref = vals["role:" + ref]
        if ref not in vals:
            raise VaultError("This item has no " + ref)
        return ref, vals[ref]

    def code(self, p, aid, iid, ref, cancel):
        ref, v = self.value(p, aid, iid, ref or "totp", cancel)
        spec = otp_of(v)
        if spec:
            return T.code(spec)
        made = p.totp(iid, ref, cancel)
        if not made:
            raise VaultError("No one-time password on this item")
        return {"code": str(made), "period": 30, "left": 30 - time.time() % 30}

    def dispatch(self, op, req, args, cancel, emit):
        if op == "ping":
            return {"protocol": PROTOCOL}
        if op == "platforms":
            out = []
            for p in PLATFORMS:
                pkg, aur = p.package()
                out.append({"kind": p.KIND, "name": p.NAME, "cli": p.CLI, "pkg": pkg, "aur": aur,
                            "asks": p.ASKS, "blurb": p.BLURB, "installed": p({}).installed(),
                            "can": p.CAN})
            return out
        if op == "generate":
            try:
                return generate.make(args.get("opts") or {})
            except ValueError as e:
                raise VaultError(str(e), "words" if "word" in str(e) else "vault")
        if op == "strength":
            return generate.strength(args.get("text") or "")
        if op == "words":
            return {"have": generate.have_words()}
        if op == "copySecret":
            return hand.copy(str(args.get("text") or ""), clear_of(args))
        if op == "scanQr":
            return scan_qr(cancel)
        if op == "copyText":
            return hand.copy(str(args.get("text") or ""), 0)
        if op == "typeText":
            return hand.type_([str(args.get("text") or "")])
        account = req.get("account")
        p = provider(account)
        aid = account.get("id")
        if not p.installed():
            raise VaultError(f"{p.CLI} is not installed ({p.package()[0]})", "missing")
        item = args.get("item")
        if op == "status":
            return dict(p.status(cancel), installed=True)
        if op == "setup":
            res = p.setup(args.get("params") or {}, args.get("secret"), cancel, emit)
            # what the platform settled on (a shorthand, a path) goes back to
            # be kept with the account
            return dict(res, account=p.cfg)
        if op == "unlock":
            self.forget_held(aid)
            return p.unlock(args.get("secret"), cancel)
        if op == "lock":
            self.forget_held(aid)
            return p.lock(cancel)
        if op == "forget":
            self.forget_held(aid)
            return p.forget(cancel)
        if op == "sync":
            self.forget_held(aid)
            return p.sync(cancel)
        if op == "items":
            return p.items(cancel)
        if op == "enrich":
            # what a quick listing left out, a batch of rows at a time
            # (passstore); the rest have nothing more to say
            return p.enrich(cancel, emit) if hasattr(p, "enrich") else {"read": 0}
        if op == "save":
            res = p.save(item or None, args.get("draft") or {}, cancel)
            self.forget_held(aid)
            return res
        if op == "duplicate":
            # a copy, secrets and all, made here: they never go by the window
            d = p.detail(item, cancel)
            self.keep(aid, d)
            with self.lock:
                vals = dict(self.held.get((aid, item)) or {})
            std, custom, urls = {}, [], []
            for sec in d.get("sections", []):
                for f in sec["fields"]:
                    ref = f["ref"]
                    if ref.startswith("h:"):
                        continue
                    if f["kind"] == "url":
                        urls.append(vals.get(ref, ""))
                    elif ref.startswith(("c:", "p", "s:")) and ref not in STD_KEYS:
                        custom.append({"label": f["label"], "value": vals.get(ref, ""), "hidden": f["secret"]})
                    else:
                        std[ref] = vals.get(ref, "")
            draft = {"kind": d.get("kind"), "title": (d.get("title") or "") + " copy", "folder": d.get("folder", ""),
                     "notes": d.get("notes", ""), "fields": std, "urls": urls, "custom": custom,
                     "tags": d.get("tags", [])}
            return p.save(None, draft, cancel)
        if op == "delete":
            self.forget_held(aid)
            return p.delete(item, bool(args.get("permanent")), cancel)
        if op == "restore":
            return p.restore(item, cancel)
        if op == "trash":
            return p.trash(cancel)
        if op == "folders":
            return p.folders(cancel)
        if op == "audit":
            rows = p.items(cancel)
            sec = p.audit_secrets(cancel)
            res = audit.check(rows, sec)
            if args.get("pwned"):
                seen = audit.pwned({k: v.get("password") for k, v in sec.items()}, cancel)
                for iid, n in seen.items():
                    res["items"].setdefault(iid, []).append("pwned")
                res["counts"]["pwned"] = len(seen)
                res["pwnedAt"] = int(time.time())
            return res
        if op == "attachmentSave":
            return p.attachment_save(item, args["att"], args["path"], cancel)
        if op == "attachmentAdd":
            res = p.attachment_add(item, args["path"], cancel)
            self.forget_held(aid)
            return res
        if op == "attachmentRemove":
            res = p.attachment_remove(item, args["att"], cancel)
            self.forget_held(aid)
            return res
        if op == "detail":
            return self.keep(aid, p.detail(item, cancel, args.get("secret")))
        if op == "reveal":
            return {"value": self.value(p, aid, item, args["ref"], cancel)[1]}
        if op == "copy":
            ref = args.get("ref") or "password"
            if ref == "totp" or args.get("totp"):
                return dict(hand.copy(self.code(p, aid, item, ref, cancel)["code"], 0), what="code")
            return hand.copy(self.value(p, aid, item, ref, cancel)[1], clear_of(args))
        if op == "totp":
            return self.code(p, aid, item, args.get("ref"), cancel)
        if op == "type":
            out = []
            for part in args.get("parts") or []:
                if part in ("\t", "\n"):
                    out.append(part)
                elif part == "totp":
                    out.append(self.code(p, aid, item, "totp", cancel)["code"])
                else:
                    out.append(self.value(p, aid, item, part, cancel)[1])
            return hand.type_(out, float(args.get("delay", 0.3)))
        raise VaultError("unknown request: " + op, "protocol")

    def close(self):
        super().close()
        with self.lock:
            self.held.clear()


def main():
    lines.serve(Server(), PROTOCOL)

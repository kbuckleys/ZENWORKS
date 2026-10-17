# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# WHAT EVERY VAULT ANSWERS TO. One class per platform (bitwarden.py,
# onepassword.py, proton.py, keepass.py, passstore.py), each wrapping that
# platform's own CLI, every one speaking the same shapes back:
#
#   an ITEM, as listed:
#     { id, title, sub, kind, host, folder, fav, tags, updated, totp }
#       kind     login · card · note · identity · ssh · password · other
#       sub      what tells two of the same title apart (the username)
#       folder   the vault, folder or group it is in ("" for none)
#       totp     true / false, or None while it is not known
#
#   an item's DETAIL:
#     { id, title, kind, host, folder, tags, updated, notes,
#       sections: [{ title, fields: [{ ref, label, kind, value, secret, role }] }],
#       reprompt }
#       kind     text · secret · url · email · phone · totp · date · note
#       role     username · password · totp — what Quick Access types
#       secret   the value is kept back from the window (server.py) and given
#                only to reveal, copy and type
#
# A platform raises VaultError for anything the user should read — a wrong
# password, a missing tool, a server out of reach — in words, not a trace.

import os
import shutil
import subprocess
import tempfile
import threading
import time
import urllib.parse


class VaultError(Exception):
    def __init__(self, msg, kind="vault", pkgs=None):
        super().__init__(msg)
        self.kind = kind
        # what to install for it to work, when that is the trouble: the
        # window offers it (Ceres) — kind "needs"
        self.pkgs = pkgs or []


def needs(tools, why):
    """tools: { command: package } — raises "needs" with the packages of
    the missing ones, or returns"""
    missing = sorted({pkg for cmd, pkg in tools.items() if not shutil.which(cmd)})
    if missing:
        raise VaultError(why + " needs " + ", ".join(missing) + ", which is not installed", "needs", missing)


class Locked(VaultError):
    def __init__(self, msg="locked"):
        super().__init__(msg, "locked")


def run(argv, cancel=None, stdin=None, env=None, timeout=60, check=False):
    """A CLI, its own session (so a cancel takes whatever it started too),
    output captured as text. → (code, out, err)"""
    e = dict(os.environ)
    # never a terminal, never a pager, never color: answers are parsed
    e.update({"NO_COLOR": "1", "TERM": "dumb", "PAGER": "cat", "LC_ALL": "C.UTF-8"})
    if env:
        e.update(env)
    try:
        p = subprocess.Popen(argv, stdin=subprocess.PIPE if stdin is not None else subprocess.DEVNULL,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=e,
                             start_new_session=True)
    except FileNotFoundError:
        raise VaultError(f"{argv[0]} is not installed", "missing")
    if cancel:
        cancel.attach(p)
    try:
        out, err = p.communicate(stdin.encode() if isinstance(stdin, str) else stdin,
                                 timeout=timeout)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(p.pid, 15)
        except OSError:
            pass
        p.communicate()
        raise VaultError(f"{os.path.basename(argv[0])} did not answer in {timeout}s", "timeout")
    finally:
        if cancel:
            cancel.detach(p)
            cancel.check()
    out, err = out.decode(errors="replace"), err.decode(errors="replace")
    if check and p.returncode != 0:
        raise VaultError(first_line(err) or f"{os.path.basename(argv[0])} failed ({p.returncode})")
    return p.returncode, out, err


def first_line(text):
    for line in str(text or "").splitlines():
        line = line.strip()
        if line:
            return line[:300]
    return ""


def have(cli):
    return shutil.which(cli) is not None


def runtime_dir():
    return os.environ.get("XDG_RUNTIME_DIR") or tempfile.gettempdir()


class Fifo:
    """A secret handed to a program that reads it from a PATH (a pinentry
    helper, PROTON_PASS_PASSWORD_FILE): a fifo, private to this user, so the
    secret is never on disk. Written once, on a thread, when the reader opens
    it; gone when the `with` ends, a writer still waiting released."""

    def __init__(self, name, secret):
        self.path = os.path.join(runtime_dir(), name)
        self.secret = secret
        self.thread = None

    def __enter__(self):
        for p in (self.path, self.path + ".spent"):
            try:
                os.unlink(p)
            except OSError:
                pass
        os.mkfifo(self.path, 0o600)
        if self.secret is not None:
            def write():
                try:
                    with open(self.path, "w") as f:
                        f.write(self.secret + "\n")
                except OSError:
                    pass
            self.thread = threading.Thread(target=write, daemon=True)
            self.thread.start()
        return self

    def spend(self):
        """Marks it answered already (calypso-pinentry.sh declines at once)."""
        open(self.path + ".spent", "w").close()

    def __exit__(self, *a):
        if self.thread and self.thread.is_alive():
            # nobody read it: open the other end so the writer lets go
            try:
                fd = os.open(self.path, os.O_RDONLY | os.O_NONBLOCK)
                time.sleep(0.05)
                os.close(fd)
            except OSError:
                pass
        for p in (self.path, self.path + ".spent"):
            try:
                os.unlink(p)
            except OSError:
                pass
        self.secret = None


def host_of(uri):
    """ "https://www.amazon.eg/foo" → "amazon.eg"; a bare "github.com" too."""
    s = str(uri or "").strip()
    if not s:
        return ""
    if "://" not in s:
        if "." not in s or " " in s:
            return ""
        s = "https://" + s
    try:
        h = urllib.parse.urlsplit(s).hostname or ""
    except ValueError:
        return ""
    h = h.lower()
    return h[4:] if h.startswith("www.") else h


def item(id, title, sub="", kind="login", host="", folder="", fav=False, tags=None,
         updated=0, totp=None):
    return {"id": str(id), "title": str(title or "(untitled)"), "sub": str(sub or ""),
            "kind": kind, "host": host, "folder": str(folder or ""), "fav": bool(fav),
            "tags": list(tags or []), "updated": int(updated or 0), "totp": totp}


def field(ref, label, value, kind="text", secret=False, role=""):
    return {"ref": str(ref), "label": str(label), "kind": kind,
            "value": "" if value is None else str(value), "secret": bool(secret),
            "role": role}


def detail(it, sections, notes="", reprompt=False, created=0):
    out = dict(it)
    out.update({"sections": [s for s in sections if s["fields"]], "notes": notes or "",
                "reprompt": reprompt, "created": int(created or 0)})
    return out


def section(title, fields):
    return {"title": title, "fields": [f for f in fields if f and (f["value"] != "" or f["kind"] == "totp")]}


def iso_time(s):
    """2026-10-11T09:00:00Z (and fractions, offsets) → epoch seconds, or 0."""
    import datetime
    s = str(s or "").strip()
    if not s:
        return 0
    try:
        s = s.replace("Z", "+00:00")
        if "." in s:
            head, tail = s.split(".", 1)
            frac = ""
            while tail and tail[0].isdigit():
                frac, tail = frac + tail[0], tail[1:]
            s = head + ("." + frac[:6] if frac else "") + tail
        d = datetime.datetime.fromisoformat(s)
        if d.tzinfo is None:
            d = d.replace(tzinfo=datetime.timezone.utc)
        return int(d.timestamp())
    except ValueError:
        return 0


class Provider:
    """One account on one platform. `cfg` is what the window keeps for it
    (calypso.json): { id, kind, name, ... the platform's own settings }."""

    KIND = ""
    NAME = ""
    CLI = ""
    PKG = ""
    AUR = False
    # what "unlock" asks for: "password" (a master password), "passphrase"
    # (gpg's), or "" (the platform's own session; nothing to type)
    ASKS = "password"
    # where the CLI's session lives, to say on the lock card
    BLURB = ""
    # what the platform's tool can do, so the window offers only that:
    #   create     the kinds a new item may be
    #   edit       an item's fields may change
    #   delete     "trash" (comes back), "archive", "delete" (for good), None
    #   restore    out of the trash again
    #   custom     fields of your own; totpEdit  a one-time password set
    #   folders    filed in a folder; attachments  files kept with an item
    #   fav, tags  kept by the platform itself; history  password history
    CAN = {"create": [], "edit": False, "delete": None, "restore": False, "custom": False,
           "totpEdit": False, "folders": False, "attachments": False, "fav": False,
           "tags": False, "history": False}

    def __init__(self, cfg):
        self.cfg = cfg

    # the package that brings the CLI, and whether it is from the AUR — a
    # platform may choose by what is on the machine (bitwarden.py)
    @classmethod
    def package(cls):
        return cls.PKG, cls.AUR

    def installed(self):
        return have(self.CLI)

    # → { configured, unlocked, user, note }
    def status(self, cancel):
        raise NotImplementedError

    def setup(self, params, secret, cancel, emit):
        """First sign-in (adds the account); may unlock it as it goes."""
        raise NotImplementedError

    def unlock(self, secret, cancel):
        raise NotImplementedError

    def lock(self, cancel):
        raise NotImplementedError

    def items(self, cancel):
        raise NotImplementedError

    def detail(self, id, cancel, secret=None):
        raise NotImplementedError

    def totp(self, id, field, cancel):
        """The current code of a totp field, when the platform makes it (the
        server makes the rest from the field's otpauth value)."""
        return None

    def sync(self, cancel):
        return {}

    # ── writing, where the platform can (CAN says which) ──────────────────
    # draft: { kind, title, folder, fav, tags, notes, urls: [..],
    #          fields: { std key: value, or None for "as it was" },
    #          custom: [{ ref, label, value (None: as it was), hidden }] }
    # The std keys are calypso.js' KINDS' fields: username, password, totp;
    # cardholder, brand, number, expiry, code; title, first, middle, last…;
    # private, public, fingerprint. → { id }
    def save(self, id, draft, cancel):
        raise VaultError(self.NAME + " cannot change items from here")

    def delete(self, id, permanent, cancel):
        raise VaultError(self.NAME + " cannot delete items from here")

    def trash(self, cancel):
        return []

    def restore(self, id, cancel):
        raise VaultError(self.NAME + " keeps no trash")

    def folders(self, cancel):
        return sorted({r["folder"] for r in self.items(cancel) if r["folder"]}, key=str.lower)

    # every login's password, sites and whether it has a code: Watchtower's
    # reading (audit.py) — never sent to the window
    def audit_secrets(self, cancel):
        out = {}
        for r in self.items(cancel):
            if r["kind"] not in ("login", "password"):
                continue
            try:
                d = self.detail(r["id"], cancel)
            except VaultError:
                continue
            fs = [f for s in d.get("sections", []) for f in s["fields"]]
            out[r["id"]] = {"password": next((f["value"] for f in fs if f["role"] == "password"), ""),
                            "urls": [f["value"] for f in fs if f["kind"] == "url"],
                            "totp": any(f["kind"] == "totp" for f in fs)}
        return out

    def attachment_save(self, id, att, path, cancel):
        raise VaultError(self.NAME + " keeps no attachments")

    def attachment_add(self, id, path, cancel):
        raise VaultError(self.NAME + " keeps no attachments")

    def attachment_remove(self, id, att, cancel):
        raise VaultError(self.NAME + " keeps no attachments")

    def forget(self, cancel):
        """The account is being removed from calypso: sign out, if that
        means anything."""
        try:
            self.lock(cancel)
        except VaultError:
            pass
        return {}

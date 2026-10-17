# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# TOKENSTORE — where a token pasted into delphi is kept, for every forge.
#
# The keyring first (the Secret Service, through git's libsecret helper —
# where git's own HTTPS finds it too). When there is no keyring to keep it
# in — no Secret Service running, as on this machine on 2026-10-11 (KWallet
# installed, its Secret Service interface off), where every store "worked"
# and kept nothing — a file of delphi's own instead:
#
#     $XDG_CONFIG_HOME/delphi/tokens.json      { host: { username, password } }
#
# readable and writable by its owner only, in a directory only its owner can
# open: the same fallback gh and glab make (gh's hosts.yml). git finds a
# token there through bin/delphi-credential, which gitrun.Creds hands it.
#
# put() says where it went; it refuses, loudly, when it could keep it
# nowhere — a sign-in that would be gone on the next start is not one.
#
# SEVERAL ACCOUNTS ON ONE FORGE (user, 2026-10-17): the one in use is the
# host's own entry, as above — what git and every request find. The others
# are kept the same way under a host of their own (shelf_host: never a real
# one, so git never meets them), their names listed in the file's "_shelf"
# (names only, no secrets). Switching swaps the two. "_use" says, per host,
# that the token kept here wins over gh's or glab's sign-in (github.py,
# gitlab.py token()): set by a token added or switched to, cleared by the
# tool's own sign-in.

import json
import os
import tempfile

import rest
from rest import ForgeError

DIR = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "delphi")
FILE = os.path.join(DIR, "tokens.json")


def _read():
    try:
        with open(FILE) as fh:
            d = json.load(fh)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def _write(d):
    os.makedirs(DIR, mode=0o700, exist_ok=True)
    os.chmod(DIR, 0o700)
    fd, tmp = tempfile.mkstemp(dir=DIR, prefix=".tokens-")
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w") as fh:
            json.dump(d, fh, indent=1)
        os.replace(tmp, FILE)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def get(host):
    """{username, password, where} of the token kept for host, or {}."""
    c = rest.keyring("fill", {"protocol": "https", "host": host})
    if c.get("password"):
        return {"username": c.get("username", ""), "password": c["password"], "where": "keyring"}
    e = _read().get(host)
    if isinstance(e, dict) and e.get("password"):
        return {"username": e.get("username", ""), "password": e["password"], "where": "file"}
    return {}


def put(host, username, password):
    """Kept in the keyring when there is one, else in the file — and read
    back from where it went, so a store that kept nothing is never
    believed. Answers where."""
    rest.keyring("approve", {"protocol": "https", "host": host,
                             "username": username, "password": password})
    if not rest.KEYRING["down"]:
        c = rest.keyring("fill", {"protocol": "https", "host": host})
        if c.get("password") == password:
            return "keyring"
    d = _read()
    d[host] = {"username": username, "password": password}
    _write(d)
    if _read().get(host, {}).get("password") != password:
        raise ForgeError(f"could not keep the token for {host} anywhere — no keyring, and {FILE} could not be written")
    return "file"


def _drop(host):
    c = rest.keyring("fill", {"protocol": "https", "host": host})
    if c:
        rest.keyring("reject", {"protocol": "https", "host": host, "username": c.get("username", "")})
    d = _read()
    if host in d:
        del d[host]
        _write(d)


# ── the accounts not in use ─────────────────────────────────────────────
def shelf_host(host, login):
    return f"delphi-shelf.{login.lower()}.{host}"


def _meta(key, host, value=None, set_=False):
    d = _read()
    m = d.get(key) if isinstance(d.get(key), dict) else {}
    if not set_:
        return m.get(host)
    if value in (None, "", []):
        m.pop(host, None)
    else:
        m[host] = value
    d[key] = m
    _write(d)


def shelved(host):
    """The names of the accounts kept for host and not in use."""
    return list(_meta("_shelf", host) or [])


def prefer(host):
    """"store" when the token kept here is the one in use for host, over
    the forge's command-line tool's own sign-in."""
    return _meta("_use", host) or ""


def set_prefer(host, how):
    if prefer(host) != (how or ""):
        _meta("_use", host, how or "", True)


def shelve(host, login, password):
    put(shelf_host(host, login), login, password)
    names = [n for n in shelved(host) if n.lower() != login.lower()]
    _meta("_shelf", host, names + [login], True)


def _unshelve(host, login):
    c = get(shelf_host(host, login))
    _drop(shelf_host(host, login))
    _meta("_shelf", host, [n for n in shelved(host) if n.lower() != login.lower()], True)
    return c


def add(host, login, password):
    """An account's token kept and put in use; the one in use before (if
    another) kept beside it. Answers where it went."""
    cur = get(host)
    if cur.get("username") and cur["username"].lower() != login.lower():
        shelve(host, cur["username"], cur["password"])
    if login.lower() in (n.lower() for n in shelved(host)):
        _unshelve(host, login)
    where = put(host, login, password)
    set_prefer(host, "store")
    return where


def switch(host, login):
    """The kept account named put in use, the one in use before kept."""
    cur = get(host)
    if cur.get("username", "").lower() == login.lower():
        set_prefer(host, "store")
        return
    c = _unshelve(host, login) if login.lower() in (n.lower() for n in shelved(host)) else {}
    if not c.get("password"):
        raise ForgeError(f"no account {login} kept for {host}")
    put(host, c.get("username") or login, c["password"])
    if cur.get("username"):
        shelve(host, cur["username"], cur["password"])
    set_prefer(host, "store")


def accounts(host, in_use):
    """[{login, source, active}] of the accounts kept for host — `in_use`:
    whether the kept one is the one in use."""
    cur = get(host)
    out = [{"login": cur["username"], "source": cur["where"], "active": in_use}] if cur.get("username") else []
    return out + [{"login": n, "source": "kept", "active": False} for n in shelved(host)]


def drop(host, login=None):
    """The account in use forgotten (or the kept one named); another kept
    takes its place, if there is one."""
    cur = get(host)
    if login and cur.get("username", "").lower() != login.lower():
        if login.lower() in (n.lower() for n in shelved(host)):
            _unshelve(host, login)
        return
    _drop(host)
    left = shelved(host)
    if left:
        c = _unshelve(host, left[0])
        if c.get("password"):
            put(host, c.get("username") or left[0], c["password"])
            return
    set_prefer(host, "")

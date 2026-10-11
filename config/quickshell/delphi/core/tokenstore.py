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


def drop(host):
    c = rest.keyring("fill", {"protocol": "https", "host": host})
    if c:
        rest.keyring("reject", {"protocol": "https", "host": host, "username": c.get("username", "")})
    d = _read()
    if host in d:
        del d[host]
        _write(d)

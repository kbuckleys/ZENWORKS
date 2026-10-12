# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# ONE-TIME CODES — RFC 6238, here, for the vaults that only keep the secret
# (KeePassXC, pass, gopass, and Bitwarden's seed). 1Password and Proton Pass
# hand over a code of their own; their CLIs are asked instead.
#
#   parse(text)     an otpauth:// URI, a bare base32 secret, or KeePass'
#                   "TOTP Settings" pair → { secret, digits, period, algo,
#                   issuer, account } or None
#   code(spec, at)  the code for that moment, and how long it has left

import base64
import hashlib
import hmac
import struct
import time
import urllib.parse

ALGOS = {"SHA1": hashlib.sha1, "SHA256": hashlib.sha256, "SHA512": hashlib.sha512}


def _b32(secret):
    s = "".join(str(secret).split()).replace("-", "").upper().rstrip("=")
    if not s:
        return None
    try:
        return base64.b32decode(s + "=" * (-len(s) % 8))
    except (ValueError, TypeError):
        return None


def parse(text, settings=""):
    """`settings` is KeePass' legacy "TOTP Settings" ("30;6", or "30;S" for
    Steam, which is not supported) beside a bare seed."""
    t = str(text or "").strip()
    if not t:
        return None
    spec = {"digits": 6, "period": 30, "algo": "SHA1", "issuer": "", "account": ""}
    if t.lower().startswith("otpauth://"):
        u = urllib.parse.urlsplit(t)
        if u.netloc.lower() != "totp":
            return None
        q = {k.lower(): v[0] for k, v in urllib.parse.parse_qs(u.query).items()}
        label = urllib.parse.unquote(u.path.lstrip("/"))
        if ":" in label:
            spec["issuer"], spec["account"] = [x.strip() for x in label.split(":", 1)]
        else:
            spec["account"] = label
        spec["issuer"] = q.get("issuer", spec["issuer"])
        secret = q.get("secret", "")
        try:
            spec["digits"] = int(q.get("digits", 6))
            spec["period"] = int(q.get("period", 30))
        except ValueError:
            return None
        spec["algo"] = q.get("algorithm", "SHA1").upper()
    else:
        secret = t
        if settings:
            bits = str(settings).split(";")
            try:
                spec["period"] = int(bits[0])
                if len(bits) > 1:
                    spec["digits"] = int(bits[1])
            except ValueError:
                return None
    key = _b32(secret)
    if key is None or spec["algo"] not in ALGOS or not 6 <= spec["digits"] <= 10 \
            or spec["period"] <= 0:
        return None
    spec["key"] = key
    return spec


def code(spec, at=None):
    at = time.time() if at is None else at
    counter = int(at // spec["period"])
    mac = hmac.new(spec["key"], struct.pack(">Q", counter), ALGOS[spec["algo"]]).digest()
    off = mac[-1] & 0x0F
    n = struct.unpack(">I", mac[off:off + 4])[0] & 0x7FFFFFFF
    digits = spec["digits"]
    return {"code": str(n % (10 ** digits)).zfill(digits),
            "period": spec["period"],
            "left": spec["period"] - (at % spec["period"])}

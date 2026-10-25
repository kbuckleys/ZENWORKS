# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# WATCHTOWER — what is wrong with the passwords you keep, as 1Password's
# Watchtower says it: weak ones, the same one in several places, old ones,
# logins on sites that only speak http, logins with no one-time password
# saved, and (asked for, never on its own) passwords that have leaked.
#
# The passwords are read here, in the daemon, and never leave it: what goes
# back is which items have which problem. The breach check is Have I Been
# Pwned's range API: only the first five characters of each password's
# SHA-1 go out, the rest is compared here (k-anonymity), so neither the
# password nor its hash is ever sent.

import hashlib
import time
import urllib.request

import generate

OLD_DAYS = 365 * 2


def check(rows, secrets, now=None):
    """rows: the account's items; secrets: { item id: { password, urls,
    totp } } for the ones that have them → { item id: [problems] } and
    counts per problem."""
    now = now or time.time()
    by_pw = {}
    for iid, s in secrets.items():
        pw = s.get("password") or ""
        if pw:
            by_pw.setdefault(hashlib.sha256(pw.encode()).hexdigest(), []).append(iid)
    out = {}
    for r in rows:
        iid = r["id"]
        s = secrets.get(iid) or {}
        pw = s.get("password") or ""
        probs = []
        if pw:
            st = generate.strength(pw)
            if st["score"] <= 1:
                probs.append("weak")
            if len(by_pw.get(hashlib.sha256(pw.encode()).hexdigest(), [])) > 1:
                probs.append("reused")
            if r.get("updated") and now - r["updated"] > OLD_DAYS * 86400:
                probs.append("old")
        urls = s.get("urls") or []
        if any(str(u).lower().startswith("http://") for u in urls):
            probs.append("insecure")
        if r.get("kind") == "login" and pw and not s.get("totp"):
            probs.append("no2fa")
        if probs:
            out[iid] = probs
    counts = {}
    for probs in out.values():
        for p in probs:
            counts[p] = counts.get(p, 0) + 1
    return {"items": out, "counts": counts}


def pwned(passwords, cancel=None):
    """{ id: password } → { id: times seen in breaches } for those seen.
    One request per distinct five-character prefix."""
    by_prefix = {}
    for iid, pw in passwords.items():
        if not pw:
            continue
        h = hashlib.sha1(pw.encode()).hexdigest().upper()
        by_prefix.setdefault(h[:5], []).append((iid, h[5:]))
    seen = {}
    for prefix, members in by_prefix.items():
        if cancel:
            cancel.check()
        req = urllib.request.Request("https://api.pwnedpasswords.com/range/" + prefix,
                                     headers={"User-Agent": "calypso (Zenworks)", "Add-Padding": "true"})
        with urllib.request.urlopen(req, timeout=20) as r:
            body = r.read().decode()
        counts = {}
        for line in body.splitlines():
            suffix, _, n = line.partition(":")
            counts[suffix.strip()] = int(n or 0)
        for iid, suffix in members:
            if counts.get(suffix, 0) > 0:
                seen[iid] = counts[suffix]
    return seen

#!/usr/bin/env python3
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# CALYPSO CORE TESTS — calypso/core, with a throwaway HOME and GNUPGHOME so
# the user's own vaults, keys and agents are never touched. The pass store is
# real: a gpg key made for the occasion, entries encrypted to it, unlocked
# through the same loopback calypso uses.
#
#   python3 oracle/tests/calypso-core.py           every test
#   python3 oracle/tests/calypso-core.py pass      tests whose name has "pass"

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORE = os.path.join(ROOT, "calypso", "core")
sys.path.insert(0, CORE)
sys.path.insert(0, os.path.join(ROOT, "morpheus", "py"))

TMP = tempfile.mkdtemp(prefix="calypso-test-")
GNUPG = os.path.join(TMP, "g")
os.makedirs(GNUPG, mode=0o700)
os.environ.update({"HOME": TMP, "XDG_CONFIG_HOME": os.path.join(TMP, ".config"),
                   "XDG_RUNTIME_DIR": TMP, "GNUPGHOME": GNUPG,
                   "PASSWORD_STORE_DIR": os.path.join(TMP, "store")})

import base  # noqa: E402
import keepass  # noqa: E402
import proton  # noqa: E402
import server  # noqa: E402
import totp as T  # noqa: E402
import lines  # noqa: E402
import audit  # noqa: E402
import bitwarden  # noqa: E402
import generate  # noqa: E402
import onepassword  # noqa: E402
from passstore import PassStore, parse_entry  # noqa: E402

passed = failed = 0


def eq(a, b, what=""):
    if a != b:
        raise AssertionError(f"{what}: {a!r} != {b!r}")


TESTS = []


def test(fn):
    TESTS.append(fn)
    return fn


@test
def totp_rfc6238():
    # RFC 6238 appendix B, SHA1, 8 digits
    key = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"   # "12345678901234567890"
    spec = T.parse(f"otpauth://totp/x?secret={key}&digits=8")
    eq(T.code(spec, 59)["code"], "94287082", "t=59")
    eq(T.code(spec, 1111111109)["code"], "07081804", "t=1111111109")
    eq(T.code(spec, 20000000000)["code"], "65353130", "t=20000000000")
    k256 = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA"
    s256 = T.parse(f"otpauth://totp/x?secret={k256}&digits=8&algorithm=SHA256")
    eq(T.code(s256, 59)["code"], "46119246", "sha256")
    eq(T.parse("not base32 !!"), None, "junk")
    eq(T.parse("otpauth://hotp/x?secret=" + key), None, "hotp refused")
    bare = T.parse("gezd gnbv gy3t qojq gezd gnbv gy3t qojq", "30;8")
    eq(T.code(bare, 59)["code"], "94287082", "KeePass seed + settings")
    left = T.code(spec, 61)["left"]
    eq(round(left), 29, "time left")


@test
def entry_shapes():
    e = parse_entry("hunter2\nlogin: ada\nurl: https://github.com/x\notpauth://totp/a?secret=JBSWY3DP\n\nsome notes\nmore\n")
    eq(e["password"], "hunter2")
    eq(e["pairs"], [("login", "ada"), ("url", "https://github.com/x")])
    eq(e["otp"].startswith("otpauth://"), True)
    eq(e["notes"], "some notes\nmore")
    eq(base.host_of("https://www.Amazon.eg/foo"), "amazon.eg")
    eq(base.host_of("github.com"), "github.com")
    eq(base.host_of("just words"), "")
    eq(base.iso_time("1970-01-01T00:01:00Z"), 60)
    eq(base.iso_time("1970-01-01T00:01:00.123456789+00:00"), 60)


@test
def proton_loose_json():
    e = {"item": {"id": "i1", "content": {"title": "GitHub", "content": {"Login": {
        "username": "ada", "password": "pw", "urls": ["https://github.com"], "totp_uri": "otpauth://totp/x?secret=JBSWY3DP"}}}}}
    eq(proton.pick(e, "title"), "GitHub")
    eq(proton.pick(e, "totpUri"), "otpauth://totp/x?secret=JBSWY3DP", "snake and camel alike")
    eq(proton.kind_of({"item_type": "creditCard"}), "card")
    eq(proton.kind_of({"content": {"Note": {}}}), "note")
    eq(proton.when(1700000000000), 1700000000)
    eq(proton.as_list({"items": [1, 2]}, "items"), [1, 2])


@test
def keepass_otp_forms():
    eq(keepass.otp_value({"otp": "otpauth://totp/x?secret=JBSWY3DP"}).startswith("otpauth"), True)
    v = keepass.otp_value({"TOTP Seed": "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", "TOTP Settings": "30;8"})
    eq(len(T.code(server.otp_of(v), 59)["code"]), 8, "legacy seed + settings")
    v = keepass.otp_value({"TimeOtp-Secret-Base32": "JBSWY3DPEHPK3PXP", "TimeOtp-Length": "8"})
    eq(T.parse(v)["digits"], 8, "KeePass 2's own")


@test
def generator():
    g = generate.make({"mode": "chars", "length": 24})
    v = g["value"]
    eq(len(v), 24)
    eq(all(any(c in s for c in v) for s in ("abcdefghijkmnpqrstuvwxyz", "ABCDEFGHJKLMNPQRSTUVWXYZ", "23456789")), True, "every kind there")
    eq(any(c in generate.AMBIGUOUS for c in v), False, "no look-alikes")
    eq(generate.make({"mode": "pin", "length": 6})["value"].isdigit(), True)
    eq(len(generate.make({"mode": "chars", "length": 10, "symbols": False, "upper": False, "digits": False})["value"]), 10)
    generate._words = ["word%04d" % i for i in range(4096)]
    w = generate.make({"mode": "words", "words": 5, "separator": ".", "capitalize": True, "number": True})
    eq(len(w["value"].split(".")), 5)
    eq(w["bits"] > 60, True, "five words of 4096")
    generate._words = []
    try:
        generate.make({"mode": "words"})
        raise AssertionError("words with no list")
    except ValueError:
        pass
    generate._words = None
    eq(generate.strength("password1")["score"], 0, "a common one")
    eq(generate.strength("Summer2024!")["score"] <= 1, True, "a word and a year")
    eq(generate.strength(generate.make({"length": 24})["value"])["score"], 4)
    eq(generate.strength("correct-horse-battery-staple")["score"] >= 2, True, "words")


@test
def watchtower():
    now = 2_000_000_000
    rows = [{"id": "a", "kind": "login", "updated": now - 10}, {"id": "b", "kind": "login", "updated": now - 10},
            {"id": "c", "kind": "login", "updated": now - 3 * 365 * 86400}, {"id": "d", "kind": "note", "updated": 0}]
    sec = {"a": {"password": "Same-pass-9!xQ", "urls": ["http://a.example"], "totp": True},
           "b": {"password": "Same-pass-9!xQ", "urls": [], "totp": False},
           "c": {"password": "abc", "urls": [], "totp": True}}
    r = audit.check(rows, sec, now)
    eq(sorted(r["items"]["a"]), ["insecure", "reused"])
    eq(sorted(r["items"]["b"]), ["no2fa", "reused"])
    eq(sorted(r["items"]["c"]), ["old", "weak"])
    eq("d" in r["items"], False)
    eq(r["counts"]["reused"], 2)
    # the breach check: only five characters of the hash go out
    import hashlib
    import io
    h = hashlib.sha1(b"abc").hexdigest().upper()
    asked = []

    class Resp(io.BytesIO):
        def __enter__(self):
            return self

        def __exit__(self, *a):
            pass
    real = audit.urllib.request.urlopen
    audit.urllib.request.urlopen = lambda req, timeout=0: (asked.append(req.full_url), Resp((h[5:] + ":42\r\nFFFF:1").encode()))[1]
    try:
        seen = audit.pwned({"c": "abc", "a": "Same-pass-9!xQ"})
    finally:
        audit.urllib.request.urlopen = real
    eq(seen, {"c": 42})
    eq(all(u.rsplit("/", 1)[1] in (h[:5], hashlib.sha1(b"Same-pass-9!xQ").hexdigest().upper()[:5]) for u in asked), True,
       "the prefix, never the password")


def fake_cli(provider, answers):
    """a provider whose CLI calls are answered here; what was sent is kept"""
    sent = []

    def call(args, cancel, **kw):
        sent.append((args, kw.get("stdin")))
        for prefix, ans in answers:
            if args[:len(prefix)] == prefix:
                return ans(args, kw.get("stdin")) if callable(ans) else ans
        return (0, "{}", "")
    return sent, call


BW_ITEM = {"id": "i1", "type": 1, "name": "GitHub", "folderId": "f1", "favorite": True, "reprompt": 0,
           "notes": "n", "revisionDate": "2026-10-01T00:00:00.000Z",
           "login": {"username": "ada", "password": "pw1", "totp": "JBSWY3DPEHPK3PXP",
                     "uris": [{"match": None, "uri": "https://github.com/login"}]},
           "fields": [{"name": "pin", "value": "1234", "type": 1}, {"name": "x", "value": "y", "type": 0}],
           "passwordHistory": [{"lastUsedDate": "2026-01-01T00:00:00.000Z", "password": "old"}],
           "attachments": [{"id": "at1", "fileName": "key.txt", "sizeName": "1 KB"}]}


@test
def bitwarden_through_bw():
    b = bitwarden.Bitwarden({"id": "bwt", "kind": "bitwarden"})
    bitwarden._sessions["bwt"] = "SESSION"
    sent, call = fake_cli(b, [
        (["list", "items", "--trash"], (0, "[]", "")),
        (["list", "items"], (0, json.dumps([BW_ITEM]), "")),
        (["list", "folders"], (0, json.dumps([{"id": "f1", "name": "Work"}]), "")),
        (["edit", "item"], lambda a, i: (0, json.dumps(json.loads(__import__("base64").b64decode(i))), "")),
        (["create", "item"], lambda a, i: (0, json.dumps(dict(json.loads(__import__("base64").b64decode(i)), id="new")), "")),
        (["create", "folder"], (0, json.dumps({"id": "f2", "name": "Home"}), "")),
    ])
    b.bw = call
    c = lines.Cancel()
    rows = b.items(c)
    eq((rows[0]["title"], rows[0]["sub"], rows[0]["folder"], rows[0]["fav"], rows[0]["totp"], rows[0]["host"]),
       ("GitHub", "ada", "Work", True, True, "github.com"))
    d = b.detail("i1", c)
    flat = {f["ref"]: f for s in d["sections"] for f in s["fields"]}
    eq(sorted(flat), ["c:0", "c:1", "h:0", "password", "totp", "url0", "username"])
    eq((flat["c:0"]["secret"], flat["h:0"]["value"]), (True, "old"), "hidden field, history")
    eq(d["attachments"][0]["name"], "key.txt")
    # an edit: the secret left as it was, a field changed, one added, a folder made
    b.save("i1", {"kind": "login", "title": "GitHub!", "folder": "Home", "fields": {"username": "lovelace", "password": None},
                  "urls": ["https://github.com"], "custom": [{"ref": "c:0", "label": "pin", "value": None, "hidden": True},
                                                           {"ref": "", "label": "new", "value": "v", "hidden": False}]}, c)
    import base64
    edited = json.loads(base64.b64decode([x for x in sent if x[0][:2] == ["edit", "item"]][-1][1]))
    eq((edited["name"], edited["login"]["username"], edited["login"]["password"], edited["folderId"]),
       ("GitHub!", "lovelace", "pw1", "f2"))
    eq([(f["name"], f["value"], f["type"]) for f in edited["fields"]], [("pin", "1234", 1), ("new", "v", 0)])
    eq(edited["login"]["uris"], [{"match": None, "uri": "https://github.com"}])
    eq(all("pw1" not in " ".join(a) for a, _ in sent), True, "no secret in argv")
    res = b.save(None, {"kind": "card", "title": "Visa", "fields": {"number": "4111", "expiry": "03/2029", "code": "123"}}, c)
    made = json.loads(base64.b64decode([x for x in sent if x[0][:2] == ["create", "item"]][-1][1]))
    eq((res["id"], made["type"], made["card"]["number"], made["card"]["expMonth"], made["card"]["expYear"]),
       ("new", 3, "4111", "3", "2029"))
    bitwarden._sessions.clear()
    bitwarden._vaults.clear()


@test
def onepassword_through_op():
    o = onepassword.OnePassword({"id": "opt", "kind": "onepassword", "shorthand": "me"})
    onepassword._tokens["opt"] = "TOKEN"
    item = {"id": "x1", "title": "Bank", "category": "LOGIN", "vault": {"id": "v1", "name": "Private"},
            "fields": [{"id": "username", "type": "STRING", "purpose": "USERNAME", "label": "username", "value": "ada"},
                       {"id": "password", "type": "CONCEALED", "purpose": "PASSWORD", "label": "password", "value": "pw"},
                       {"id": "notesPlain", "type": "STRING", "purpose": "NOTES", "label": "notesPlain", "value": ""},
                       {"id": "TOTP_1", "type": "OTP", "label": "one-time password", "value": "otpauth://totp/x?secret=JBSWY3DP"},
                       {"id": "pin", "type": "CONCEALED", "label": "pin", "value": "9", "section": {"id": "s", "label": "more"}}],
            "urls": [{"href": "https://bank.example", "primary": True}]}
    sent, call = fake_cli(o, [(["item", "get"], (0, json.dumps(item), "")),
                              (["item", "edit"], (0, "{}", "")), (["item", "create"], (0, json.dumps({"id": "n1"}), ""))])
    o.op = call
    c = lines.Cancel()
    d = o.detail("x1", c)
    flat = {f["ref"]: f for s in d["sections"] for f in s["fields"]}
    eq(sorted(flat), ["c:pin", "password", "totp", "url0", "username"], "shared keys, customs by id")
    o.save("x1", {"kind": "login", "title": "Bank", "fields": {"password": "new"}, "custom": [
        {"ref": "c:pin", "label": "pin", "value": None, "hidden": True}]}, c)
    body = json.loads([i for a, i in sent if a[:2] == ["item", "edit"]][-1])
    by = {f["id"]: f for f in body["fields"]}
    eq((by["password"]["value"], by["pin"]["value"], by["username"]["value"]), ("new", "9", "ada"))
    eq(any("new" in x for a, _ in sent for x in a), False, "the secret over stdin only")
    eq(o.save(None, {"kind": "login", "title": "T", "folder": "Work", "fields": {"username": "u", "password": "p"}}, c)["id"], "n1")
    onepassword._tokens.clear()


@test
def onepassword_session_off_argv():
    # the session token kept off the process list: in op's environment when
    # op reads it from there (proven at unlock by whoami), --session only
    # when it does not — both kinds of op played here
    keep = onepassword.run
    for reads_env in (True, False):
        calls = []

        def fake(argv, cancel=None, stdin=None, env=None, timeout=60, check=False):
            env = env or {}
            calls.append((list(argv), dict(env)))
            if argv[1:2] == ["signin"]:
                return (0, "TOK123\n", "")
            if argv[1:3] == ["account", "list"]:
                return (0, json.dumps([{"shorthand": "me", "url": "my.1password.com", "user_uuid": "UUIDABC"}]), "")
            has = ("--session" in argv and argv[argv.index("--session") + 1] == "TOK123") or \
                  (reads_env and env.get("OP_SESSION") == "TOK123")
            return (0, "[]", "") if has else (1, "", "[ERROR] not signed in")
        onepassword.run = fake
        try:
            o = onepassword.OnePassword({"id": "ops", "kind": "onepassword", "shorthand": "me"})
            o.unlock("master", lines.Cancel())
            calls.clear()
            code, _, _ = o.op(["item", "list", "--format", "json"], lines.Cancel())
            argv, env = calls[-1]
            eq(code, 0, f"reads_env={reads_env}: the call is signed in")
            if reads_env:
                eq("TOK123" in " ".join(argv), False, "no token on argv")
                eq((env.get("OP_SESSION"), env.get("OP_SESSION_me"), env.get("OP_SESSION_UUIDABC")),
                   ("TOK123", "TOK123", "TOK123"), "every name op is known to read")
            else:
                eq(argv[-2:], ["--session", "TOK123"], "an op that does not read it: the flag, as before")
            o.lock(lines.Cancel())
            eq(onepassword._via.get("ops"), None, "settled again at the next unlock")
        finally:
            onepassword.run = keep
            onepassword._tokens.clear()
            onepassword._via.clear()
            onepassword._uuids.clear()
    # a shorthand that is no variable name gets no OP_SESSION_<it>
    o = onepassword.OnePassword({"id": "opd", "kind": "onepassword", "shorthand": "my.1password.com"})
    eq(sorted(o.session_env("T")), ["OP_SESSION"])


# ── pass, for real ────────────────────────────────────────────────────────
PASSPHRASE = "correct horse"


def gpg(*args, stdin=None):
    return subprocess.run(["gpg", "--batch", "--yes"] + list(args), input=stdin,
                          capture_output=True, text=True)


def make_store():
    r = gpg("--pinentry-mode", "loopback", "--passphrase", PASSPHRASE,
            "--quick-gen-key", "Calypso Test <calypso@test>", "default", "default", "never")
    assert r.returncode == 0, r.stderr
    store = os.environ["PASSWORD_STORE_DIR"]
    os.makedirs(os.path.join(store, "web"), exist_ok=True)
    with open(os.path.join(store, ".gpg-id"), "w") as f:
        f.write("calypso@test\n")
    for name, body in [("web/github.com", "pw-gh\nlogin: ada\notpauth://totp/x?secret=JBSWY3DPEHPK3PXP\n"),
                       ("email/ada@example.com", "pw-mail\nurl: mail.example.com\npin: 0000\n"),
                       ("wifi", "pw-wifi\n")]:
        os.makedirs(os.path.dirname(os.path.join(store, name)), exist_ok=True)
        r = gpg("-e", "-r", "calypso@test", "-o", os.path.join(store, name + ".gpg"), stdin=body)
        assert r.returncode == 0, r.stderr
    # forget the passphrase the key was made with
    subprocess.run(["gpgconf", "--reload", "gpg-agent"])


@test
def pass_store_for_real():
    if not shutil.which("gpg"):
        print("    (no gpg: skipped)")
        return
    make_store()
    c = lines.Cancel()
    p = PassStore({"id": "p"})
    st = p.status(c)
    eq((st["configured"], st["unlocked"]), (True, False), "locked to start")
    try:
        p.items(c)
        raise AssertionError("listed while locked")
    except base.Locked:
        pass
    try:
        p.unlock("wrong", c)
        raise AssertionError("a wrong passphrase unlocked")
    except base.VaultError as e:
        eq(e.kind, "auth")
    p.unlock(PASSPHRASE, c)
    eq(p.status(c)["unlocked"], True, "unlocked")
    quick = {r["id"]: r for r in p.items(c)}
    eq(sorted(quick), ["email/ada@example.com", "web/github.com", "wifi"], "listed from the names at once")
    eq(quick["web/github.com"]["totp"], None, "not read yet: not known")
    got = []
    eq(p.enrich(c, lambda ev: got.extend(ev["rows"]))["read"], 3, "the rest read after")
    eq(sorted(r["id"] for r in got), sorted(quick), "every row said, read")
    eq(p.enrich(c, lambda ev: None)["read"], 0, "read once")
    rows = {r["id"]: r for r in p.items(c)}
    gh = rows["web/github.com"]
    eq((gh["title"], gh["sub"], gh["host"], gh["folder"], gh["totp"]),
       ("github.com", "ada", "github.com", "web", True))
    eq(rows["email/ada@example.com"]["host"], "mail.example.com", "url line")
    eq(rows["wifi"]["kind"], "password")
    s = server.Server()
    d = s.keep("p", p.detail("email/ada@example.com", c))
    flat = {f["label"]: f for sec in d["sections"] for f in sec["fields"]}
    eq(flat["pin"]["secret"], True, "a pin line is kept back")
    eq(flat["password"]["value"], "")
    eq(s.value(p, "p", "email/ada@example.com", "password", c)[1], "pw-mail")
    eq(len(s.code(p, "p", "web/github.com", "totp", c)["code"]), 6)
    # writing: a new one, an edit that keeps the secret, a rename, a delete
    r = p.save(None, {"kind": "login", "title": "new.example", "folder": "web", "fields": {"username": "ada", "password": "n3w", "totp": None},
                      "urls": ["https://new.example"], "notes": "hi", "custom": [{"label": "pin", "value": "7", "hidden": True}]}, c)
    eq(r["id"], "web/new.example")
    # a second NEW one under that name is refused, never written over it
    try:
        p.save(None, {"kind": "login", "title": "new.example", "folder": "web", "fields": {"password": "other"}}, c)
        eq("written", "refused", "a new entry over a taken name")
    except Exception as e:
        eq("already there" in str(e), True, "a new entry over a taken name")
    d = p.detail("web/new.example", c)
    flat = {f["label"]: f for sec in d["sections"] for f in sec["fields"]}
    eq((flat["username"]["value"], flat["password"]["value"], flat["pin"]["value"], d["notes"]), ("ada", "n3w", "7", "hi"))
    r = p.save("web/new.example", {"kind": "login", "title": "renamed.example", "folder": "web",
                                   "fields": {"username": "lovelace", "password": None}}, c)
    eq(r["id"], "web/renamed.example")
    eq(os.path.exists(os.path.join(os.environ["PASSWORD_STORE_DIR"], "web", "new.example.gpg")), False, "the old name gone")
    d = p.detail("web/renamed.example", c)
    flat = {f["label"]: f for sec in d["sections"] for f in sec["fields"]}
    eq((flat["username"]["value"], flat["password"]["value"], flat["pin"]["value"]), ("lovelace", "n3w", "7"), "kept what was not touched")
    p.delete("web/renamed.example", True, c)
    eq(os.path.exists(os.path.join(os.environ["PASSWORD_STORE_DIR"], "web", "renamed.example.gpg")), False)
    p.lock(c)
    eq(p.status(c)["unlocked"], False, "locked again (that key only)")


@test
def daemon_end_to_end():
    d = subprocess.Popen([sys.executable, os.path.join(ROOT, "calypso", "bin", "calypsod")],
                         stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    try:
        ready = json.loads(d.stdout.readline())
        eq(ready["event"]["protocol"], server.PROTOCOL)

        def ask(msg):
            d.stdin.write(json.dumps(msg) + "\n")
            d.stdin.flush()
            while True:
                m = json.loads(d.stdout.readline())
                if m.get("id") == msg["id"] and "event" not in m:
                    return m
        r = ask({"id": 1, "op": "platforms"})
        eq([p["kind"] for p in r["result"]],
           ["bitwarden", "onepassword", "proton", "keepass", "pass", "gopass"])
        r = ask({"id": 2, "op": "items", "account": {"id": "x", "kind": "nope"}})
        eq((r["ok"], r["kind"]), (False, "vault"))
        if shutil.which("gpg") and os.path.exists(os.path.join(os.environ["PASSWORD_STORE_DIR"], ".gpg-id")):
            acct = {"id": "p2", "kind": "pass"}
            r = ask({"id": 3, "op": "items", "account": acct})
            eq(r.get("kind"), "locked", "locked over the wire")
            ask({"id": 4, "op": "unlock", "account": acct, "args": {"secret": PASSPHRASE}})
            r = ask({"id": 5, "op": "detail", "account": acct, "args": {"item": "wifi"}})
            pw = [f for s in r["result"]["sections"] for f in s["fields"] if f["role"] == "password"][0]
            eq(pw["value"], "", "no secret over the wire")
            r = ask({"id": 6, "op": "reveal", "account": acct, "args": {"item": "wifi", "ref": pw["ref"]}})
            eq(r["result"]["value"], "pw-wifi", "until revealed")
            ask({"id": 7, "op": "lock", "account": acct})
    finally:
        d.stdin.close()
        d.wait(10)


def main():
    global passed, failed
    want = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        for t in TESTS:
            if want and want not in t.__name__:
                continue
            try:
                t()
                print(f"  ok   {t.__name__}")
                passed += 1
            except Exception as e:
                import traceback
                print(f"  FAIL {t.__name__}: {e}")
                traceback.print_exc()
                failed += 1
    finally:
        subprocess.run(["gpgconf", "--kill", "gpg-agent"], env=os.environ)
        shutil.rmtree(TMP, ignore_errors=True)
    print(f"calypso core: {passed} passed, {failed} failed")
    sys.exit(1 if failed else 0)


main()

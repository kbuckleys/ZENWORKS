# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# SSH KEYS FOR SIGNING IN — the keys in ~/.ssh, what each one is for, a new
# one made, ~/.ssh/config told which key goes to which host, and a test that
# the host lets it in. (Keys for SIGNING commits are core/signing.py's; this
# file only reads that one to say "signs your commits" beside it.)
#
#   status()        openssh there or not, the agent, every key: its type,
#                   fingerprint, passphrase or none, the hosts ~/.ssh/config
#                   gives it to
#   create(...)     a new ed25519 key. The passphrase crosses one private
#                   socket to ssh-keygen's askpass, never argv or disk, and is
#                   checked afterwards: a key that came out without one when one
#                   was asked for is deleted again, not handed back
#   use(...)        ~/.ssh/config: a block for a host, naming the key — added,
#                   never the file rewritten (see plan_host)
#   remember(...)   the agent keeping a key's passphrase after its first use
#                   (AddKeysToAgent in the key's blocks), or no longer
#   test(...)       ssh -T user@host: in, refused, or why not
#   remove(...)     the key pair to the trash, its config lines taken out
#
# THE CONFIG FILE STAYS YOURS, the same rule as ceres' pacman.conf editor: a
# change is lines added or one line's value replaced; comments, order and
# spacing survive. Every function on it takes a list of lines and returns a
# new one, so the tests can run it on text.

import json
import os
import re
import shutil
import socket
import subprocess
import tempfile
import threading

from gitrun import ASKPASS, GitError

HOME = os.path.expanduser("~")
SSH = os.path.join(HOME, ".ssh")
CONFIG = os.path.join(SSH, "config")
RUNTIME = os.environ.get("XDG_RUNTIME_DIR") or tempfile.gettempdir()
# where the session's agent listens (hypr/lua/base.lua sets SSH_AUTH_SOCK to
# it; autostart.lua starts it) — openssh's own user unit uses the same path
AGENT = os.path.join(RUNTIME, "ssh-agent.socket")
MARK = "# added by Delphi"

# the hosts whose login name is known: a forge's is always git, the AUR's aur
USERS = {"github.com": "git", "gitlab.com": "git", "codeberg.org": "git", "aur.archlinux.org": "aur"}


# A host or login name as ssh and ~/.ssh/config take one. Hosts can come
# from a cloned repository's remote (delphi.js sshTarget), so one starting
# with "-" would reach ssh as an option ("-oProxyCommand=…") and one with a
# space or newline would write lines of its own into the config.
NAME = re.compile(r"^[A-Za-z0-9_.][A-Za-z0-9_.@:%+-]*$")


def _checked(host, user):
    if not NAME.match(host or "") or (user and not NAME.match(user)):
        raise GitError(["ssh"], 1, f"{user + '@' if user else ''}{host} is not a host ssh can be pointed at")


def _tilde(p):
    return "~" + p[len(HOME):] if p == HOME or p.startswith(HOME + "/") else p


def _full(p):
    return os.path.abspath(os.path.expanduser(p))


# ── the agent ───────────────────────────────────────────────────────────
def agent_sock():
    """The agent ssh should talk to: the session's, else the usual socket
    when something listens there."""
    s = os.environ.get("SSH_AUTH_SOCK", "")
    if s and os.path.exists(s):
        return s
    return AGENT if os.path.exists(AGENT) else ""


def agent_start():
    """The agent at the usual socket, started when there is none (openssh
    installed after the session began: the session's own starts next time)."""
    if agent_sock():
        return agent_sock()
    if not shutil.which("ssh-agent"):
        return ""
    subprocess.run(["ssh-agent", "-a", AGENT], capture_output=True, stdin=subprocess.DEVNULL, timeout=10)
    return agent_sock()


def _loaded(sock):
    """The fingerprints the agent holds."""
    if not sock or not shutil.which("ssh-add"):
        return []
    r = subprocess.run(["ssh-add", "-l"], capture_output=True, text=True, stdin=subprocess.DEVNULL,
                       env=dict(os.environ, SSH_AUTH_SOCK=sock), timeout=5)
    return [l.split()[1] for l in r.stdout.splitlines() if len(l.split()) > 1] if r.returncode == 0 else []


# ── ~/.ssh/config, as lines ─────────────────────────────────────────────
def _split(line):
    """(keyword lowercased, value) of a config line; None for blank/comment."""
    s = line.strip()
    if not s or s.startswith("#"):
        return None
    m = re.match(r"([A-Za-z]+)\s*(?:=\s*|\s+)(.*)$", s)
    return (m.group(1).lower(), m.group(2).strip()) if m else (s.lower(), "")


def blocks(lines):
    """Every Host/Match block: {at, end, kind, patterns, ids (line indexes
    of IdentityFile), mark (the Delphi line above it, or -1)}. end is the
    index the next block starts at (its own marker included)."""
    out = []
    for i, l in enumerate(lines):
        kv = _split(l)
        if kv and kv[0] in ("host", "match"):
            mark = i - 1 if i > 0 and lines[i - 1].strip() == MARK else -1
            if out:
                out[-1]["end"] = mark if mark >= 0 else i
            out.append({"at": i, "end": len(lines), "kind": kv[0], "patterns": kv[1].split(), "ids": [], "mark": mark})
        elif kv and kv[0] == "identityfile" and out:
            out[-1]["ids"].append(i)
    return out


def _value(line):
    kv = _split(line)
    return kv[1].strip('"') if kv else ""


def hosts_of(lines, key):
    """The hosts whose block gives ssh this key (a private key's path)."""
    want = _full(key)
    out = []
    for b in blocks(lines):
        if b["kind"] == "host" and any(_full(_value(lines[i])) == want for i in b["ids"]):
            out += [p for p in b["patterns"] if not p.startswith("!")]
    return out


def plan_host(lines, host, user, key, agent=True, replace=False):
    """The config with `host` sending `key`. Returns {lines, state}:

      added    a new block, before the first `Host *` or Match (ssh takes the
               FIRST value it meets, so after them ours would lose)
      same     the host's block names this key already — nothing changed
      differs  the host has a block of its own with other keys: unchanged
               unless `replace`, its text in `block` for the card to show
      updated  (replace) that block's first IdentityFile now this key,
               IdentitiesOnly added when missing
    """
    key_t = _tilde(_full(key))
    host_l = host.lower()
    for b in blocks(lines):
        if b["kind"] != "host" or host_l not in [p.lower() for p in b["patterns"]]:
            continue
        if any(_full(_value(lines[i])) == _full(key) for i in b["ids"]):
            return {"lines": list(lines), "state": "same"}
        if not replace:
            return {"lines": list(lines), "state": "differs", "block": "\n".join(lines[b["at"]:b["end"]]).rstrip()}
        new = list(lines)
        body = [_split(l) for l in lines[b["at"] + 1:b["end"]]]
        indent = "  "
        for l in lines[b["at"] + 1:b["end"]]:
            if _split(l):
                indent = l[:len(l) - len(l.lstrip())] or "  "
                break
        add = []
        if b["ids"]:
            i = b["ids"][0]
            new[i] = new[i][:len(new[i]) - len(new[i].lstrip())] + "IdentityFile " + key_t
        else:
            add.append(indent + "IdentityFile " + key_t)
        if not any(kv and kv[0] == "identitiesonly" for kv in body):
            add.append(indent + "IdentitiesOnly yes")
        new[b["at"] + 1:b["at"] + 1] = add
        return {"lines": new, "state": "updated"}
    block = [MARK, "Host " + host]
    if user:
        block.append("  User " + user)
    block += ["  IdentityFile " + key_t, "  IdentitiesOnly yes"]
    if agent:
        block.append("  AddKeysToAgent yes")
    at = len(lines)
    for b in blocks(lines):
        if b["kind"] == "match" or "*" in b["patterns"]:
            at = b["mark"] if b["mark"] >= 0 else b["at"]
            break
    before, after = list(lines[:at]), list(lines[at:])
    while before and not before[-1].strip():
        before.pop()
    new = before + ([""] if before else []) + block + ([""] + after if after else [])
    return {"lines": new, "state": "added"}


def remembered(lines, key):
    """Whether every block that gives ssh this key says AddKeysToAgent yes
    (False when no block gives it)."""
    want = _full(key)
    mine = [b for b in blocks(lines) if b["kind"] == "host"
            and any(_full(_value(lines[i])) == want for i in b["ids"])]
    if not mine:
        return False
    for b in mine:
        vals = [kv[1].lower() for kv in (_split(l) for l in lines[b["at"] + 1:b["end"]]) if kv and kv[0] == "addkeystoagent"]
        if not vals or vals[0] != "yes":
            return False
    return True


def plan_remember(lines, key, on):
    """The config with the key's passphrase kept by the agent (on) or not:
    in each block that gives ssh this key, its AddKeysToAgent line set to
    yes in place or added at the block's end — or, off, taken out."""
    want = _full(key)
    new = list(lines)
    # last block first: the lines added or taken out shift only what follows
    for b in reversed(blocks(lines)):
        if b["kind"] != "host" or not any(_full(_value(lines[i])) == want for i in b["ids"]):
            continue
        at = [i for i in range(b["at"] + 1, b["end"]) if (_split(lines[i]) or ("",))[0] == "addkeystoagent"]
        if not on:
            for i in reversed(at):
                del new[i]
            continue
        if at:
            l = new[at[0]]
            new[at[0]] = l[:len(l) - len(l.lstrip())] + "AddKeysToAgent yes"
            continue
        body = [i for i in range(b["at"] + 1, b["end"]) if lines[i].strip()]
        last = body[-1] if body else b["at"]
        indent = "  "
        for i in body:
            if _split(lines[i]):
                indent = lines[i][:len(lines[i]) - len(lines[i].lstrip())] or "  "
                break
        new.insert(last + 1, indent + "AddKeysToAgent yes")
    return new


def plan_unlink(lines, key):
    """The config with `key` taken out: its IdentityFile lines gone, and a
    block Delphi added that is left with none removed whole."""
    want = _full(key)
    drop = set()
    for b in blocks(lines):
        mine = [i for i in b["ids"] if _full(_value(lines[i])) == want]
        if not mine:
            continue
        if b["mark"] >= 0 and len(mine) == len(b["ids"]):
            drop.update(range(b["mark"], b["end"]))
        else:
            drop.update(mine)
    new = [l for i, l in enumerate(lines) if i not in drop]
    out = []
    for l in new:   # no run of blank lines left where a block was
        if not l.strip() and out and not out[-1].strip():
            continue
        out.append(l)
    while out and not out[-1].strip():
        out.pop()
    return out


def _read_config():
    try:
        with open(CONFIG) as f:
            return f.read().splitlines()
    except FileNotFoundError:
        return []


def _write_config(lines):
    os.makedirs(SSH, mode=0o700, exist_ok=True)
    tmp = CONFIG + ".delphi-new"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write("\n".join(lines) + "\n" if lines else "")
    os.replace(tmp, CONFIG)


# ── the keys ────────────────────────────────────────────────────────────
def _keygen(*args, timeout=10):
    return subprocess.run(["ssh-keygen", *args], capture_output=True, text=True,
                          stdin=subprocess.DEVNULL, timeout=timeout)


def _has_passphrase(priv):
    """True, False, or None when it cannot be told (no ssh-keygen, no file)."""
    if not shutil.which("ssh-keygen") or not os.path.exists(priv):
        return None
    r = _keygen("-y", "-P", "", "-f", priv, timeout=5)
    if r.returncode == 0:
        return False
    return True if "passphrase" in (r.stderr or "").lower() else None


def _fingerprint(pub):
    if not shutil.which("ssh-keygen"):
        return ""
    r = _keygen("-l", "-f", pub, timeout=5)
    parts = r.stdout.split()
    return parts[1] if r.returncode == 0 and len(parts) > 1 else ""


def status():
    import signing
    from gitrun import Git
    lines = _read_config()
    sign = os.path.expanduser(signing._get(Git(None), "user.signingkey"))
    sock = agent_sock()
    loaded = _loaded(sock)
    keys = []
    if os.path.isdir(SSH):
        for n in sorted(os.listdir(SSH)):
            if not n.endswith(".pub"):
                continue
            pub = os.path.join(SSH, n)
            try:
                with open(pub) as f:
                    parts = f.read().split()
            except OSError:
                continue
            if len(parts) < 2 or not parts[0].startswith(("ssh-", "ecdsa-", "sk-")):
                continue
            priv = pub[:-4]
            fp = _fingerprint(pub)
            keys.append({"name": n[:-4], "path": priv, "pub": pub, "public": " ".join(parts[:2]),
                         "type": parts[0].replace("ssh-", ""), "comment": " ".join(parts[2:]),
                         "fingerprint": fp, "private": os.path.exists(priv),
                         "passphrase": _has_passphrase(priv),
                         "hosts": hosts_of(lines, priv), "signing": sign in (pub, priv),
                         "remember": remembered(lines, priv),
                         "loaded": bool(fp) and fp in loaded})
    return {"ssh": bool(shutil.which("ssh")), "keygen": bool(shutil.which("ssh-keygen")),
            "agent": sock, "agentBin": bool(shutil.which("ssh-agent")), "dir": SSH,
            "users": USERS, "keys": keys}


class _Answers:
    """A private socket that answers delphi-askpass with one text — the
    passphrase ssh-keygen asks for (twice: new, then again)."""

    def __init__(self, text):
        self.text = text
        self.path = os.path.join(RUNTIME, f"delphi-key-{os.getpid()}-{threading.get_ident()}.sock")
        try:
            os.unlink(self.path)
        except OSError:
            pass
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        old = os.umask(0o177)
        try:
            self.sock.bind(self.path)
        finally:
            os.umask(old)
        self.sock.listen(4)
        threading.Thread(target=self._serve, daemon=True).start()

    def _serve(self):
        for _ in range(4):
            try:
                c, _ = self.sock.accept()
            except OSError:
                return
            with c:
                try:
                    buf = b""
                    while not buf.endswith(b"\n"):
                        chunk = c.recv(4096)
                        if not chunk:
                            break
                        buf += chunk
                    c.sendall((json.dumps({"answer": self.text}) + "\n").encode())
                except OSError:
                    pass

    def close(self):
        try:
            self.sock.close()
            os.unlink(self.path)
        except OSError:
            pass


def create(name, comment="", passphrase="", cancel=None):
    if not shutil.which("ssh-keygen"):
        raise GitError(["ssh-keygen"], 127, "ssh-keygen is not installed (openssh)")
    if not re.match(r"^[A-Za-z0-9][A-Za-z0-9._-]*$", name or "") or name.endswith(".pub"):
        raise GitError(["ssh-keygen"], 1, "a key's name is letters, digits, dots, dashes and underscores")
    priv = os.path.join(SSH, name)
    if os.path.exists(priv) or os.path.exists(priv + ".pub"):
        raise GitError(["ssh-keygen"], 1, f"there is a key called {name} already")
    os.makedirs(SSH, mode=0o700, exist_ok=True)
    args = ["ssh-keygen", "-q", "-t", "ed25519", "-C", comment or name, "-f", priv]
    ans = None
    e = dict(os.environ)
    if passphrase:
        ans = _Answers(passphrase)
        e.update({"SSH_ASKPASS": ASKPASS, "SSH_ASKPASS_REQUIRE": "force", "DELPHI_SOCK": ans.path})
    else:
        args[2:2] = ["-N", ""]
    try:
        r = subprocess.run(args, capture_output=True, text=True, stdin=subprocess.DEVNULL,
                           env=e, start_new_session=True, timeout=60)
    finally:
        if ans:
            ans.close()
    if r.returncode != 0:
        raise GitError(["ssh-keygen"], r.returncode, r.stderr.strip() or "ssh-keygen failed")
    # asked for a passphrase and got none: never hand that key out
    if passphrase and _has_passphrase(priv) is not True:
        for p in (priv, priv + ".pub"):
            try:
                os.unlink(p)
            except OSError:
                pass
        raise GitError(["ssh-keygen"], 1, "ssh-keygen made the key without its passphrase, so it was deleted again")
    with open(priv + ".pub") as f:
        pub = " ".join(f.read().split()[:2])
    return {"path": priv, "public": pub, "fingerprint": _fingerprint(priv + ".pub")}


def use(host, key, user=None, replace=False, agent=True):
    """~/.ssh/config sends `key` to `host` (see plan_host); `agent`: its
    passphrase kept by the agent once given."""
    user = USERS.get(host.lower(), "") if user is None else user
    _checked(host, user)
    p = plan_host(_read_config(), host, user, key, agent=agent, replace=replace)
    if p["state"] in ("added", "updated"):
        _write_config(p["lines"])
    return {"state": p["state"], "block": p.get("block", "")}


def remember(key, on):
    """The key's passphrase kept by the agent from its next use (on), or no
    longer — and, off, the agent told to forget it now as well."""
    priv = _full(key)
    lines = _read_config()
    if not hosts_of(lines, priv):
        raise GitError(["ssh"], 1, "no host is given this key yet — use it for one first")
    new = plan_remember(lines, priv, on)
    if new != lines:
        _write_config(new)
    sock = agent_start() if on else agent_sock()
    if not on and sock and shutil.which("ssh-add") and os.path.exists(priv + ".pub"):
        subprocess.run(["ssh-add", "-d", priv + ".pub"], capture_output=True, stdin=subprocess.DEVNULL,
                       env=dict(os.environ, SSH_AUTH_SOCK=sock), timeout=5)
    return {"remember": remembered(_read_config(), priv), "agent": sock}


# ssh's own failures (exit 255), worded by what they mean
WHY = [("permission denied", "refused"), ("host key verification failed", "hostkey"),
       ("could not resolve", "network"), ("timed out", "network"), ("unreachable", "network"),
       ("connection refused", "network"), ("no route", "network"), ("closed by remote", "network")]
LOGIN = [r"Hi ([^!,\s]+)!", r"Welcome to GitLab, @([^!\s]+)!", r"Hi there, ([^!\s]+)!"]


def read_test(code, text):
    """What `ssh -T` said: {ok, why, login, line}."""
    lines = [l.strip() for l in (text or "").splitlines() if l.strip() and not l.startswith("Warning: Permanently")]
    last = lines[-1] if lines else ""
    # killed (Esc, the 120 s timeout): it never got in — read as "got in",
    # the remote was switched to ssh on it (audit 2026-10-28d)
    if code is None or code < 0:
        return {"ok": False, "why": "network", "login": "", "line": last}
    if code == 255:
        low = (text or "").lower()
        why = next((w for k, w in WHY if k in low), "error")
        return {"ok": False, "why": why, "login": "", "line": last}
    login = ""
    for pat in LOGIN:
        m = re.search(pat, text or "")
        if m:
            login = m.group(1)
            break
    return {"ok": True, "why": "", "login": login, "line": last}


def test(host, user=None, sock=None, cancel=None):
    """Whether `host` lets you in by key. Its questions (a new host's key,
    the key's passphrase) come up in the window through delphi-askpass."""
    import gitrun
    if not shutil.which("ssh"):
        raise GitError(["ssh"], 127, "ssh is not installed (openssh)")
    user = USERS.get(host.lower(), "git") if user is None else user
    _checked(host, user)
    e = gitrun.env(sock=sock)
    p = subprocess.Popen(["ssh", "-T", "-o", "ConnectTimeout=10", "--", f"{user}@{host}"],
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                         text=True, env=e, start_new_session=True)
    if cancel:
        cancel.attach(p)   # Esc in the window kills ssh, and its askpass
    try:
        out, _ = p.communicate(timeout=120)
    except subprocess.TimeoutExpired:
        p.kill()
        out, _ = p.communicate()
    finally:
        if cancel:
            cancel.detach(p)
    if cancel:
        cancel.check()   # stopped: the request ends as cancelled, not as an answer
    return dict(read_test(p.returncode, out), host=host, user=user)


def remove(key):
    """The pair to the trash (gio), and its lines out of ~/.ssh/config."""
    priv = _full(key)
    # a pair: ~/.ssh/config or known_hosts sit in the same directory
    if os.path.dirname(priv) != SSH or priv.endswith(".pub") or not os.path.exists(priv + ".pub"):
        raise GitError(["rm"], 1, "only key pairs in ~/.ssh are removed here")
    gone = []
    for p in (priv, priv + ".pub"):
        if os.path.exists(p):
            r = subprocess.run(["gio", "trash", p], capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=15)
            if r.returncode != 0:
                raise GitError(["gio", "trash"], r.returncode, r.stderr.strip() or "could not move it to the trash")
            gone.append(p)
    lines = _read_config()
    new = plan_unlink(lines, priv)
    if new != lines:
        _write_config(new)
    return {"trashed": gone}

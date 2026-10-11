# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# SIGNED COMMITS, WITH AN SSH KEY — no GPG. git signs with ssh-keygen -Y
# sign when gpg.format is ssh; GitHub, GitLab and Codeberg show a commit
# signed by a key registered with them as Verified.
#
#   status()        how git is set up here: signing on or off, the key, the
#                   public keys there are to choose from, ssh-keygen there
#   setup(...)      sign every commit (and tag) with a key: one there is, or
#                   a new ed25519 key made for it. The key is also written to
#                   an allowed-signers file, so git can check your own
#                   commits' signatures too (History's "Signed").
#   off()           commits unsigned again; the key and the file stay
#
# Everything is git's GLOBAL config — the same "for all your repositories"
# as who commits. Only ever run when asked, from the window.

import os
import shutil
import subprocess

from gitrun import Git, GitError

HOME = os.path.expanduser("~")
SSH = os.path.join(HOME, ".ssh")
SIGNERS = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config"),
                       "git", "allowed_signers")


def _get(g, k):
    try:
        return g.run(["config", "--global", "--get", k], lock=False).strip()
    except GitError:
        return ""


def status():
    g = Git(None)
    keys = []
    if os.path.isdir(SSH):
        for n in sorted(os.listdir(SSH)):
            if n.endswith(".pub"):
                p = os.path.join(SSH, n)
                try:
                    with open(p) as f:
                        parts = f.read().split()
                except OSError:
                    continue
                if len(parts) >= 2 and parts[0].startswith(("ssh-", "ecdsa-", "sk-")):
                    keys.append({"path": p, "type": parts[0], "comment": " ".join(parts[2:])})
    key = _get(g, "user.signingkey")
    return {"on": _get(g, "commit.gpgsign") == "true", "format": _get(g, "gpg.format") or "openpgp",
            "key": os.path.expanduser(key), "keyThere": bool(key) and os.path.exists(os.path.expanduser(key)),
            "keys": keys, "keygen": shutil.which("ssh-keygen") is not None,
            "email": _get(g, "user.email")}


def setup(key="", create=False, email="", cancel=None):
    """Sign with `key` (a .pub path), or with a new key made for it. The new
    one has no passphrase: git signs without asking, the way it commits —
    the key file is yours alone (0600), as any ssh key is."""
    if not shutil.which("ssh-keygen"):
        raise GitError(["ssh-keygen"], 127, "ssh-keygen is not installed (openssh)")
    g = Git(None)
    email = email or _get(g, "user.email")
    if create:
        os.makedirs(SSH, mode=0o700, exist_ok=True)
        priv = os.path.join(SSH, "id_ed25519_signing")
        n = 1
        while os.path.exists(priv) or os.path.exists(priv + ".pub"):
            n += 1
            priv = os.path.join(SSH, f"id_ed25519_signing_{n}")
        r = subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", email or "delphi signing key",
                            "-f", priv], capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=30)
        if r.returncode != 0:
            raise GitError(["ssh-keygen"], r.returncode, r.stderr or "ssh-keygen failed")
        key = priv + ".pub"
    key = os.path.expanduser(key)
    if not key.endswith(".pub") or not os.path.exists(key):
        raise GitError(["config"], 1, "choose a public key (.pub)")
    with open(key) as f:
        pub = " ".join(f.read().split()[:2])
    for k, v in (("gpg.format", "ssh"), ("user.signingkey", key), ("commit.gpgsign", "true"),
                 ("tag.gpgsign", "true"), ("gpg.ssh.allowedSignersFile", SIGNERS)):
        g.run(["config", "--global", k, v])
    # your own key, trusted for your own address: git can say "Good" of
    # your signatures (it checks against this file, nothing else)
    os.makedirs(os.path.dirname(SIGNERS), exist_ok=True)
    line = f"{email or '*'} namespaces=\"git\" {pub}"
    have = ""
    if os.path.exists(SIGNERS):
        with open(SIGNERS) as f:
            have = f.read()
    if pub not in have:
        with open(SIGNERS, "a") as f:
            if have and not have.endswith("\n"):
                f.write("\n")
            f.write(line + "\n")
    return {"key": key, "public": pub, "created": bool(create)}


def off():
    Git(None).run(["config", "--global", "commit.gpgsign", "false"])
    Git(None).run(["config", "--global", "tag.gpgsign", "false"])
    return status()

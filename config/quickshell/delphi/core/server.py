# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# THE DAEMON — delphi's backend, spoken to as JSON lines on stdin/stdout.
#
# Whoever draws delphi (the quickshell windows today; a test, or anything
# else, tomorrow) starts bin/delphid and writes one request per line:
#
#   {"id": 7, "op": "status", "repo": "/path", "args": {...}}
#
# and reads one line per message:
#
#   {"id": 7, "ok": true, "result": ...}            the answer, exactly once
#   {"id": 7, "ok": false, "error": "...", "kind": "git"|"cancelled"|...}
#   {"id": 7, "event": {...}}                       progress, before the answer
#   {"event": {"ask": 3, "prompt": "...", ...}}     not tied to a request
#
# Requests run on threads of their own, so a slow fetch never holds up a
# status. Writes to ONE repository run one at a time, in the order they came
# (a lock per repository); reads never wait for them. {"op": "cancel",
# "args": {"id": 7}} stops request 7 and everything git started for it.
#
# The protocol is versioned (PROTOCOL, sent in the ready event). A change
# that breaks the window bumps it, and the window refuses a daemon it does
# not speak — which keeps a quickshell update and a backend change from
# failing silently into each other.

import inspect
import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time

import forgejo
import github
import gitlab
import gitrun
import repo as R
import signing
from graph import Lanes
from gitrun import Cancel, Cancelled, GitError
from rest import ForgeError
from stow import StowError
from lines import send
import lines

PROTOCOL = 1

def snake(name):
    return re.sub(r"(?<!^)(?=[A-Z])", "_", name).lower()


# ── the askpass broker ──────────────────────────────────────────────────
class Asker:
    """A unix socket, private to this user, where bin/delphi-askpass brings
    git's and ssh's questions. Each becomes an `ask` event; the window's
    {"op": "answer"} goes back down the same connection."""

    def __init__(self):
        d = os.environ.get("XDG_RUNTIME_DIR") or tempfile.gettempdir()
        self.path = os.path.join(d, f"delphi-{os.getpid()}.sock")
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
        self.sock.listen(8)
        self.waiting = {}
        self.n = 0
        self.lock = threading.Lock()
        threading.Thread(target=self._accept, daemon=True).start()

    def _accept(self):
        while True:
            try:
                c, _ = self.sock.accept()
            except OSError:
                return
            threading.Thread(target=self._one, args=(c,), daemon=True).start()

    def _one(self, c):
        try:
            buf = b""
            while not buf.endswith(b"\n"):
                chunk = c.recv(4096)
                if not chunk:
                    return
                buf += chunk
            q = json.loads(buf.decode())
            with self.lock:
                self.n += 1
                n = self.n
                ev = threading.Event()
                self.waiting[n] = [ev, None]
            prompt = q.get("prompt", "")
            send({"event": dict({"ask": n, "prompt": prompt.strip()},
                                **classify(prompt, q.get("kind", "")))})
            ev.wait(300)
            with self.lock:
                ans = self.waiting.pop(n, [None, None])[1]
            c.sendall((json.dumps({"answer": ans}) + "\n").encode())
        except (OSError, ValueError):
            pass
        finally:
            c.close()

    def answer(self, ask, text):
        with self.lock:
            w = self.waiting.get(ask)
            if w:
                w[1] = text
                w[0].set()
        return {}

    def close(self):
        try:
            self.sock.close()
            os.unlink(self.path)
        except OSError:
            pass


def classify(prompt, kind):
    """What sort of question this is, so the card can ask it properly: a
    username is shown as typed, a password or passphrase is hidden, and an
    ssh host key is a yes/no with the fingerprint to read."""
    p = prompt.lower()
    if kind == "confirm" or "(yes/no" in p:
        return {"kind": "confirm", "secret": False}
    if p.startswith("username"):
        return {"kind": "username", "secret": False}
    if "passphrase" in p:
        return {"kind": "passphrase", "secret": True}
    return {"kind": "password", "secret": True}


# ── history, a page at a time ───────────────────────────────────────────
class LogSession:
    """One `git log` kept running, read as the window scrolls. The graph's
    lanes continue from page to page, so the window never re-lays rows it
    already has."""

    def __init__(self, repo, args):
        self.repo = repo
        self.lanes = Lanes()
        self.proc = subprocess.Popen(repo.git.argv(repo.log_args(**args)),
                                     stdout=subprocess.PIPE,
                                     stderr=subprocess.DEVNULL,
                                     stdin=subprocess.DEVNULL,
                                     env=gitrun.env(lock=False),
                                     start_new_session=True)
        self.rest = ""
        self.held = []
        self.ended = False
        self.lock = threading.Lock()
        self.row = 0

    def page(self, count=200):
        with self.lock:
            # git hands back more than a page in one read; what is over waits
            # in self.held for the next page
            while len(self.held) < count and not self.ended:
                chunk = self.proc.stdout.read1(65536)
                if not chunk:
                    self.ended = True
                    cs, self.rest = R.parse_log(self.rest + R.RS)
                else:
                    cs, self.rest = R.parse_log(self.rest + chunk.decode("utf-8", "replace"))
                self.held += cs
            got, self.held = self.held[:count], self.held[count:]
            for c in got:
                c["graph"] = self.lanes.row(c["sha"], c["parents"])
                c["row"] = self.row
                self.row += 1
            return {"commits": got, "end": self.ended and not self.held}

    def close(self):
        try:
            os.killpg(self.proc.pid, 15)
        except (ProcessLookupError, PermissionError):
            pass


# ── watching a repository ───────────────────────────────────────────────
class Watch:
    """inotifywait on the git directory (index, HEAD, refs — what every git
    command, from here or a terminal, touches when it changes something) and,
    when it is small enough, the working tree. Changes are gathered for
    150 ms and sent as one `changed` event. A tree too big to watch is left
    out and the event says so: the window then refreshes on focus instead."""

    MAX_DIRS = 20000
    HEAVY = r"(^|/)(\.git|node_modules|target|build|dist|\.venv|__pycache__)(/|$)"

    def __init__(self, repo):
        self.repo = repo
        self.procs = []
        self.pending = set()
        self.timer = None
        self.lock = threading.Lock()
        common = repo.info["common"]
        self._spawn(["inotifywait", "-m", "-q", "--format", "%w%f",
                     "-e", "modify,create,delete,move,attrib",
                     repo.gitdir], "git")
        refs = os.path.join(common, "refs")
        if os.path.isdir(refs):
            self._spawn(["inotifywait", "-m", "-r", "-q", "--format", "%w%f",
                         "-e", "modify,create,delete,move", refs,
                         common if common != repo.gitdir else refs], "refs")
        self.tree = self._small(repo.root)
        if self.tree:
            self._spawn(["inotifywait", "-m", "-r", "-q", "--format", "%w%f",
                         "-e", "modify,create,delete,move,attrib",
                         "--exclude", self.HEAVY, repo.root], "tree")

    def _small(self, root):
        n = 0
        for d, dirs, _ in os.walk(root):
            dirs[:] = [x for x in dirs if not re.search(self.HEAVY, "/" + x)]
            n += 1
            if n > self.MAX_DIRS:
                return False
        return True

    def _spawn(self, argv, what):
        try:
            p = subprocess.Popen(argv, stdout=subprocess.PIPE,
                                 stderr=subprocess.DEVNULL, text=True,
                                 start_new_session=True)
        except FileNotFoundError:
            return
        self.procs.append(p)
        threading.Thread(target=self._read, args=(p, what), daemon=True).start()

    def _read(self, p, what):
        for line in p.stdout:
            path = line.rstrip("\n")
            if what == "git":
                base = os.path.basename(path)
                # git's own lock files come and go around every write; the
                # write itself is what matters, and lands as the real name.
                if base.endswith(".lock"):
                    continue
                kind = "index" if base == "index" else "state"
            elif what == "refs":
                if path.endswith(".lock"):
                    continue
                kind = "refs"
            else:
                kind = "tree"
            with self.lock:
                self.pending.add(kind)
                if self.timer is None:
                    self.timer = threading.Timer(0.15, self._flush)
                    self.timer.daemon = True
                    self.timer.start()

    def _flush(self):
        with self.lock:
            what, self.pending, self.timer = sorted(self.pending), set(), None
        send({"event": {"changed": self.repo.root, "what": what,
                        "tree": self.tree}})

    def close(self):
        for p in self.procs:
            try:
                os.killpg(p.pid, 15)
            except (ProcessLookupError, PermissionError):
                pass


# ── the tools around git ────────────────────────────────────────────────
# What delphi leans on that git does not bring: gh and glab (each forge's
# sign-in), ssh (a remote at git@… or ssh://…), inotifywait (changes made
# outside delphi, seen as they happen). Which are here, and — for the forge
# tools — whom they had signed in, from their own config files: a sign-in
# that outlived its tool is one a reinstall brings back (user, 2026-10-11:
# missing tools noticed for accounts already signed in, not only at first).

def _user_in(path, host):
    """The `user:` under `host:` in a gh or glab config (YAML, read by its
    indentation — no YAML library in the standard one)."""
    try:
        lines = open(os.path.expanduser(path)).read().splitlines()
    except OSError:
        return ""
    inside, depth = False, 0
    for l in lines:
        if not l.strip() or l.lstrip().startswith("#"):
            continue
        ind = len(l) - len(l.lstrip())
        key = l.strip()
        if key.rstrip(":") == host and key.endswith(":"):
            inside, depth = True, ind
            continue
        if inside and ind <= depth:
            inside = False
        if inside:
            m = re.match(r"user:\s*(\S+)", key)
            if m and m.group(1) not in ("''", '""'):
                return m.group(1)
    return ""


def tools():
    w = shutil.which
    return {"gh": bool(w("gh")), "glab": bool(w("glab")), "ssh": bool(w("ssh")),
            "inotifywait": bool(w("inotifywait")),
            "ghUser": _user_in("~/.config/gh/hosts.yml", "github.com"),
            "glabUser": _user_in("~/.config/glab-cli/config.yml", "gitlab.com")}


# ── the ops ─────────────────────────────────────────────────────────────
# The forges, by the prefix of their requests ("githubRepos", "gitlabRepos",
# "codebergRepos") — every module answers to the same names (see forge).
FORGES = {"github": github, "gitlab": gitlab, "codeberg": forgejo}

# ── A SERVER OF YOUR OWN ───────────────────────────────────────────────────
# A self-hosted GitLab, or a Forgejo or Gitea, is "gitlab@<host>" or
# "forgejo@<host>": its requests are named so ("gitlab@git.example.orgStatus"),
# and answered by a copy of that forge's module loaded for that host alone —
# its own HOST and API, so two servers' requests running at once can never
# cross, and not a line of the module had to learn about hosts.
KINDS = {"gitlab": gitlab, "forgejo": forgejo}
_HOSTED = {}
_HOSTED_LOCK = threading.Lock()
_ROUTE = re.compile(r"(github|gitlab|codeberg|forgejo)(?:@([a-z0-9][a-z0-9.\-]*(?::\d+)?))?(?=[A-Z])")


def hosted(kind, host):
    import importlib.util
    key = f"{kind}@{host}"
    with _HOSTED_LOCK:
        mod = _HOSTED.get(key)
        if mod is None:
            base = KINDS[kind]
            spec = importlib.util.spec_from_file_location(key, base.__file__)
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            mod.API = base.API.replace(base.HOST, host, 1)
            mod.HOST = host
            mod.FORGE_ID = key
            _HOSTED[key] = mod
        return mod


def route(op):
    """(module, the request's own name) for a forge's request, else None."""
    m = _ROUTE.match(op)
    if not m:
        return None
    name, host = m.group(1), m.group(2)
    rest = op[m.end():]
    if host:
        return (hosted(name, host), rest) if name in KINDS else None
    return (FORGES[name], rest) if name in FORGES else None

# Requests named here change the repository; they queue behind each other.
WRITES = {"stowCopyIn", "resolveBlocks", "ignore", "untrack", "stage", "stageAll", "unstage", "unstageAll", "discard", "clean",
          "stageLines", "unstageLines", "discardLines", "commit", "undoCommit",
          "branchCreate", "branchTrack", "switch", "branchDelete",
          "branchRename", "setUpstream", "tagCreate", "tagDelete",
          "remoteAdd", "remoteRemove", "remoteSetUrl", "fetch", "pull", "push",
          "stashPush", "stashApply", "stashDrop", "stashBranch",
          "worktreeAdd", "worktreeRemove", "worktreePrune", "merge",
          "cherryPick", "revert", "rebase", "rebaseInteractive", "sequence",
          "reset", "take", "markResolved", "pullCheckout", "connect", "bringBack", "applyPatch"}

# Request op → Repo method, where the names differ.
ALIAS = {"files": "files_in", "refs": "refs", "lastMessage": "last_message"}


class Server(lines.Service):
    def __init__(self):
        super().__init__()
        self.asker = Asker()
        self.repos = {}
        self.locks = {}
        self.logs = {}
        self.watches = {}
        self.n = 0
        self.lock = threading.Lock()

    # repositories are opened once and shared by every request for them
    def repo(self, path):
        info = R.discover(path)
        if not info:
            raise GitError(["rev-parse"], 128, f"not a git repository: {path}")
        root = info["root"]
        with self.lock:
            if root not in self.repos:
                self.repos[root] = R.Repo(root, self.asker.path)
                self.locks[root] = threading.Lock()
            return self.repos[root], self.locks[root]

    # the loop is morpheus/py/lines.Service's; an answer to git's question
    # is given here, at once, never queued behind a thread's start
    def special(self, req):
        if req.get("op") != "answer":
            return False
        args = req.get("args") or {}
        send({"id": req.get("id"), "ok": True,
              "result": self.asker.answer(args.get("ask"), args.get("text"))})
        return True

    def failure(self, e):
        if isinstance(e, GitError):
            return {"kind": "git", "error": e.err or str(e), "code": e.code}
        if isinstance(e, ForgeError):
            return {"kind": "forge", "error": str(e), "status": e.status}
        if isinstance(e, StowError):
            return {"kind": "stow", "error": str(e)}
        return None

    def dispatch(self, op, req, args, cancel, emit):
        return self.serve_op(op, req.get("repo"), args, cancel, emit)

    def serve_op(self, op, path, args, cancel, emit):
        kw = {snake(k): v for k, v in args.items()}
        # ── not tied to one repository ──
        if op == "ping":
            return {"protocol": PROTOCOL}
        if op == "discover":
            return R.discover(kw["path"])
        if op == "scan":
            return R.scan(kw.get("roots", ["~"]), kw.get("depth", 4), cancel, emit)
        if op == "init":
            return R.init(kw["path"], kw.get("branch"))
        if op == "clone":
            return R.clone(kw["url"], kw["dest"], self.asker.path, cancel, emit,
                           kw.get("depth"), kw.get("blobless", False),
                           kw.get("branch"))
        if op == "across":
            # the latest commits of each repository named, newest first in
            # each — History's "All repositories" (a repository with none
            # yet, or gone, is left out)
            out = []
            fmt = "%H%x1f%an%x1f%ct%x1f%s%x1e"
            for root in kw.get("roots", []):
                try:
                    txt = gitrun.Git(root).run(["log", "-n", str(kw.get("count", 12)),
                                                f"--format={fmt}", "HEAD"], lock=False)
                except (GitError, OSError):
                    continue
                cs = []
                for rec in txt.split("\x1e"):
                    f = rec.strip("\n").split("\x1f")
                    if len(f) == 4:
                        cs.append({"sha": f[0], "author": f[1], "when": int(f[2] or 0), "subject": f[3]})
                if cs:
                    out.append({"root": root, "commits": cs})
            return out
        if op == "tools":
            return tools()
        if op == "summaries":
            return R.summaries(kw.get("roots", []), cancel)
        if op == "missing":
            # which of these repositories lost their files: "gone" (the
            # directory is not there) or "plain" (there, but no .git any more)
            # — the Repositories page's "Missing" rows
            out = {}
            for root in kw.get("roots", []):
                if not os.path.isdir(root):
                    out[root] = "gone"
                elif not os.path.exists(os.path.join(root, ".git")):
                    out[root] = "plain"
            return out
        if op == "whereCloned":
            # which of these repositories is a clone of host/full — the one a
            # forge's repository opens as, when it is here already
            want = (kw["host"].lower(), kw["full"].lower().removesuffix(".git"))
            for root in kw.get("roots", []):
                try:
                    out = gitrun.Git(root).run(["remote", "-v"], lock=False)
                except (GitError, OSError):
                    continue
                for l in out.splitlines():
                    parts = l.split()
                    if len(parts) >= 2 and R.remote_key(parts[1]) == want:
                        return {"root": root}
            return {"root": None}
        if op == "signingStatus":
            return signing.status()
        if op == "signingSetup":
            return signing.setup(kw.get("key", ""), kw.get("create", False), kw.get("email", ""), cancel)
        if op == "signingOff":
            return signing.off()
        if op == "identitySet":
            # global unless a repository is named — the first-run question
            # "who are you" is asked once, for every repository
            where = ["--global"] if not path else []
            g = gitrun.Git(self.repo(path)[0].root if path else None)
            for k in ("name", "email"):
                if kw.get(k):
                    g.run(["config"] + where + [f"user.{k}", kw[k]])
            return {}
        fr = route(op)
        if fr:
            return self.forge(fr[0], fr[1], kw, cancel, emit)
        # ── one repository ──
        r, lock = self.repo(path)
        if op == "logOpen":
            with self.lock:
                self.n += 1
                sid = self.n
                self.logs[sid] = LogSession(r, kw)
            return {"session": sid}
        if op == "logPage":
            s = self.logs.get(kw["session"])
            if not s:
                raise GitError(["log"], 1, "history closed")
            return s.page(kw.get("count", 200))
        if op == "logClose":
            s = self.logs.pop(kw["session"], None)
            if s:
                s.close()
            return {}
        if op == "watch":
            with self.lock:
                if r.root not in self.watches:
                    self.watches[r.root] = Watch(r)
                return {"tree": self.watches[r.root].tree}
        if op == "unwatch":
            w = self.watches.pop(r.root, None)
            if w:
                w.close()
            return {}
        if op == "info":
            return dict(r.info, identity=r.identity())
        name = ALIAS.get(op, snake(op))
        fn = getattr(r, name, None)
        if fn is None or name.startswith("_"):
            raise GitError([op], 1, f"unknown request: {op}")
        params = inspect.signature(fn).parameters
        if "cancel" in params:
            kw["cancel"] = cancel
        if "emit" in params:
            kw["emit"] = emit
        if op in WRITES:
            with lock:
                cancel.check()
                return fn(**kw)
        return fn(**kw)

    def forge(self, f, op, kw, cancel, emit):
        """A forge's request — `f` its module (github, gitlab, forgejo),
        every one answering to the same names."""
        cli = {"github": "gh", "gitlab": "glab"}.get(f.__name__.split("@")[0])
        if op == "Status":
            st = f.status()
            if cli:
                gitrun.CREDS.refresh(**{cli + "_ok": st.get("source") == cli})
            return st
        if op == "Login":
            st = f.login(emit, cancel)
            if cli:
                gitrun.CREDS.refresh(**{cli + "_ok": True})
            return st
        if op == "Logout":
            if cli:
                gitrun.CREDS.refresh(**{cli + "_ok": False})
            return f.logout(kw.get("login"))
        if op == "Accounts":
            return f.accounts()
        if op == "Switch":
            st = f.switch_account(kw["login"])
            if cli:
                gitrun.CREDS.refresh(**{cli + "_ok": st.get("source") == cli})
            return st
        if op == "SetToken":
            return f.set_token(kw["token"])
        if op == "ForgetToken":
            return f.forget_token()
        if op == "Repos":
            return f.repos(cancel)
        if op == "Create":
            return f.create(kw["name"], kw.get("private", True),
                            kw.get("description", ""), kw.get("org"))
        if op == "Plan":
            return f.plan(kw["full"], kw["files"], kw.get("branch"))
        if op == "Branches":
            return f.branches(kw["full"])
        if op == "Upload":
            return f.upload(kw["full"], kw["files"], kw["message"],
                            kw.get("branch"), emit, cancel)
        if op == "Pulls":
            return f.pulls(kw["full"], kw.get("state", "open"))
        if op == "Issues":
            return f.issues(kw["full"], kw.get("state", "open"))
        if op == "Thread":
            return f.thread(kw["full"], kw["number"], kw.get("pull", False))
        if op == "Comment":
            return f.comment(kw["full"], kw["number"], kw["body"], kw.get("pull", False))
        if op == "SetState":
            return f.set_state(kw["full"], kw["number"], kw["open"], kw.get("pull", False))
        if op == "OpenIssue":
            return f.open_issue(kw["full"], kw["title"], kw.get("body", ""))
        if op == "OpenPull":
            return f.open_pull(kw["full"], kw["head"], kw["base"], kw["title"],
                               kw.get("body", ""), kw.get("draft", False))
        if op == "Merge":
            return f.merge(kw["full"], kw["number"], kw.get("method", "merge"))
        if op == "Checks":
            return f.checks(kw["full"], kw["sha"])
        if op == "ChecksMany":
            return f.checks_many(kw["full"], kw["shas"])
        if op == "AddSigningKey":
            return f.add_signing_key(kw["key"], kw.get("title", "delphi"))
        if op == "UpdateRelease":
            return f.update_release(kw["full"], kw["id"], kw["tag"], kw.get("name", ""), kw.get("body", ""),
                                    kw.get("draft", False), kw.get("prerelease", False))
        if op == "DeleteRelease":
            return f.delete_release(kw["full"], kw["id"], kw.get("tag", ""))
        if op == "Archive":
            return f.archive(kw["full"], kw.get("on", True))
        if op == "Releases":
            return f.releases(kw["full"])
        if op == "ReleaseNotes":
            return f.release_notes(kw["full"], kw["tag"], kw["target"], kw.get("previous"))
        if op == "CreateRelease":
            return f.create_release(kw["full"], kw["tag"], kw["target"], kw.get("name", ""),
                                    kw.get("body", ""), kw.get("draft", False), kw.get("prerelease", False))
        raise ForgeError(f"unknown request: {f.__name__}{op}")

    def close(self):
        for s in self.logs.values():
            s.close()
        for w in self.watches.values():
            w.close()
        super().close()
        self.asker.close()


def main():
    srv = Server()
    # Whether gh can answer for github.com, and glab for gitlab.com, decides
    # the credential helpers every network call gets; asked once at start,
    # then by each forge's Status.
    threading.Thread(target=lambda: gitrun.CREDS.refresh(
        gh_ok=github.token()[1] == "gh", glab_ok=gitlab.token()[1] == "glab"), daemon=True).start()
    lines.serve(srv, PROTOCOL)

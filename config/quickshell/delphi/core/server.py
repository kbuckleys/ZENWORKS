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
import socket
import subprocess
import sys
import tempfile
import threading
import time

import github
import gitrun
import repo as R
from graph import Lanes
from gitrun import Cancel, Cancelled, GitError

PROTOCOL = 1

_out_lock = threading.Lock()


def send(msg):
    line = json.dumps(msg, ensure_ascii=False, separators=(",", ":"))
    with _out_lock:
        sys.stdout.write(line + "\n")
        sys.stdout.flush()


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


# ── the ops ─────────────────────────────────────────────────────────────
# Requests named here change the repository; they queue behind each other.
WRITES = {"stage", "stageAll", "unstage", "unstageAll", "discard", "clean",
          "stageLines", "unstageLines", "discardLines", "commit",
          "branchCreate", "branchTrack", "switch", "branchDelete",
          "branchRename", "setUpstream", "tagCreate", "tagDelete",
          "remoteAdd", "remoteRemove", "remoteSetUrl", "fetch", "pull", "push",
          "stashPush", "stashApply", "stashDrop", "stashBranch",
          "worktreeAdd", "worktreeRemove", "worktreePrune", "merge",
          "cherryPick", "revert", "rebase", "rebaseInteractive", "sequence",
          "reset", "take", "markResolved", "pullCheckout"}

# Request op → Repo method, where the names differ.
ALIAS = {"files": "files_in", "refs": "refs", "lastMessage": "last_message"}


class Server:
    def __init__(self):
        self.asker = Asker()
        self.repos = {}
        self.locks = {}
        self.cancels = {}
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

    def handle(self, req):
        rid, op = req.get("id"), req.get("op", "")
        args = req.get("args") or {}
        if op == "cancel":
            c = self.cancels.get(args.get("id"))
            if c:
                c.cancel()
            return send({"id": rid, "ok": True, "result": {}})
        if op == "answer":
            return send({"id": rid, "ok": True,
                         "result": self.asker.answer(args.get("ask"), args.get("text"))})
        cancel = Cancel()
        self.cancels[rid] = cancel
        threading.Thread(target=self._run, args=(rid, op, req, args, cancel),
                         daemon=True).start()

    def _run(self, rid, op, req, args, cancel):
        emit = lambda ev: send({"id": rid, "event": ev})
        try:
            res = self.dispatch(op, req.get("repo"), args, cancel, emit)
            send({"id": rid, "ok": True, "result": res})
        except Cancelled:
            send({"id": rid, "ok": False, "kind": "cancelled", "error": "cancelled"})
        except GitError as e:
            send({"id": rid, "ok": False, "kind": "git", "error": e.err or str(e),
                  "code": e.code})
        except github.ForgeError as e:
            send({"id": rid, "ok": False, "kind": "forge", "error": str(e),
                  "status": e.status})
        except Exception as e:   # a bug here must not take the daemon down
            send({"id": rid, "ok": False, "kind": "internal",
                  "error": f"{type(e).__name__}: {e}"})
        finally:
            self.cancels.pop(rid, None)

    def dispatch(self, op, path, args, cancel, emit):
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
        if op == "identitySet":
            # global unless a repository is named — the first-run question
            # "who are you" is asked once, for every repository
            where = ["--global"] if not path else []
            g = gitrun.Git(self.repo(path)[0].root if path else None)
            for k in ("name", "email"):
                if kw.get(k):
                    g.run(["config"] + where + [f"user.{k}", kw[k]])
            return {}
        if op.startswith("github"):
            return self.forge(op[6:], kw, cancel, emit)
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

    def forge(self, op, kw, cancel, emit):
        if op == "Status":
            st = github.status()
            gitrun.CREDS.refresh(gh_ok=st.get("source") == "gh")
            return st
        if op == "Login":
            st = github.login(emit, cancel)
            gitrun.CREDS.refresh(gh_ok=True)
            return st
        if op == "Logout":
            gitrun.CREDS.refresh(gh_ok=False)
            return github.logout()
        if op == "SetToken":
            return github.set_token(kw["token"])
        if op == "ForgetToken":
            return github.forget_token()
        if op == "Repos":
            return github.repos(cancel)
        if op == "Create":
            return github.create(kw["name"], kw.get("private", True),
                                 kw.get("description", ""), kw.get("org"))
        if op == "Plan":
            return github.plan(kw["full"], kw["files"], kw.get("branch"))
        if op == "Branches":
            return github.branches(kw["full"])
        if op == "Upload":
            return github.upload(kw["full"], kw["files"], kw["message"],
                                 kw.get("branch"), emit, cancel)
        if op == "Pulls":
            return github.pulls(kw["full"], kw.get("state", "open"))
        if op == "Issues":
            return github.issues(kw["full"], kw.get("state", "open"))
        if op == "Thread":
            return github.thread(kw["full"], kw["number"])
        if op == "Comment":
            return github.comment(kw["full"], kw["number"], kw["body"])
        if op == "SetState":
            return github.set_state(kw["full"], kw["number"], kw["open"])
        if op == "OpenIssue":
            return github.open_issue(kw["full"], kw["title"], kw.get("body", ""))
        if op == "OpenPull":
            return github.open_pull(kw["full"], kw["head"], kw["base"], kw["title"],
                                    kw.get("body", ""), kw.get("draft", False))
        if op == "Merge":
            return github.merge(kw["full"], kw["number"], kw.get("method", "merge"))
        raise github.ForgeError(f"unknown request: github{op}")

    def close(self):
        for s in self.logs.values():
            s.close()
        for w in self.watches.values():
            w.close()
        for c in list(self.cancels.values()):
            c.cancel()
        self.asker.close()


def main():
    srv = Server()
    # Whether gh can answer for github.com decides the credential helpers
    # every network call gets; asked once at start, then by githubStatus.
    threading.Thread(target=lambda: gitrun.CREDS.refresh(
        gh_ok=github.token()[1] == "gh"), daemon=True).start()
    send({"event": {"ready": True, "protocol": PROTOCOL, "pid": os.getpid()}})
    try:
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                req = json.loads(line)
            except ValueError:
                send({"ok": False, "kind": "protocol", "error": "not JSON"})
                continue
            srv.handle(req)
    finally:
        srv.close()

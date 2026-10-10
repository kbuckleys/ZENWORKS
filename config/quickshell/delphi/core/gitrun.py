# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# RUNNING GIT — the one place delphi starts a git process.
#
# Everything else in delphi/core asks this file, so the rules below hold for
# every call without anyone remembering them:
#
#   · git never waits on a terminal. GIT_TERMINAL_PROMPT=0, and every question
#     git or ssh wants answered goes through bin/delphi-askpass, which asks the
#     daemon, which asks whoever is drawing delphi.
#   · git never opens an editor on its own. GIT_EDITOR is `:` unless a caller
#     hands one in (rebase plans, plato --wait).
#   · reads do not take locks. GIT_OPTIONAL_LOCKS=0 on anything that only
#     looks, so a refresh in the background never fights the user's own git in
#     a terminal over index.lock.
#   · output is the machine's, not the user's: no colour, no pager, no quoted
#     paths, C locale for the few messages parsed by text.
#   · every process is its own session, so cancelling kills git AND whatever
#     git started (ssh, a hook, a credential helper), not just git.

import os
import signal
import subprocess
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.path.join(os.path.dirname(HERE), "bin")
ASKPASS = os.path.join(BIN, "delphi-askpass")


class GitError(Exception):
    def __init__(self, args, code, err):
        self.args_ = args
        self.code = code
        self.err = err.strip()
        super().__init__(self.err or f"git {' '.join(args[:2])} exited {code}")


class Cancelled(Exception):
    pass


class Cancel:
    """A request's off switch. The worker running a request hands it to every
    git call it makes; cancel() kills whichever one is running and makes every
    later call raise Cancelled instead of starting."""

    def __init__(self):
        self.done = False
        self._procs = set()
        self._lock = threading.Lock()

    def attach(self, proc):
        with self._lock:
            if self.done:
                _kill(proc)
                raise Cancelled()
            self._procs.add(proc)

    def detach(self, proc):
        with self._lock:
            self._procs.discard(proc)

    def cancel(self):
        with self._lock:
            self.done = True
            procs = list(self._procs)
        for p in procs:
            _kill(p)

    def check(self):
        if self.done:
            raise Cancelled()


def _kill(proc):
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        pass


# Delphi's own answer to "who keeps the password": the keyring, through
# git-credential-libsecret — but only when the user has not chosen a helper of
# their own, which always wins. For github.com, gh's helper goes first when gh
# is signed in, so a `gh auth login` is all a user ever has to do. Both are
# passed per call with -c, never written into anyone's gitconfig.
class Creds:
    def __init__(self):
        self.user_helper = None   # None = not looked up yet
        self.gh_ok = False

    def refresh(self, gh_ok=None):
        r = subprocess.run(["git", "config", "--get-all", "credential.helper"],
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                           text=True)
        self.user_helper = r.stdout.strip()
        if gh_ok is not None:
            self.gh_ok = gh_ok

    def args(self):
        if self.user_helper is None:
            self.refresh()
        a = []
        if not self.user_helper and os.path.exists(
                "/usr/lib/git-core/git-credential-libsecret"):
            a += ["-c", "credential.helper=libsecret"]
        if self.gh_ok:
            # The empty value clears the helpers collected so far for this
            # host, so a stale keyring entry cannot answer before gh does.
            a += ["-c", "credential.https://github.com.helper=",
                  "-c", "credential.https://github.com.helper=!gh auth git-credential"]
        return a


CREDS = Creds()

BASE_ARGS = ["-c", "color.ui=false", "-c", "core.quotepath=false",
             "-c", "advice.statusHints=false", "-c", "pager.branch=false"]


def env(sock=None, lock=True, editor=None, seq_editor=None, extra=None):
    e = dict(os.environ)
    e.update({
        "LC_ALL": "C",
        "GIT_TERMINAL_PROMPT": "0",
        "GIT_PAGER": "cat",
        "PAGER": "cat",
        "GIT_EDITOR": editor or ":",
        "GCM_INTERACTIVE": "never",
    })
    if seq_editor:
        e["GIT_SEQUENCE_EDITOR"] = seq_editor
    if not lock:
        e["GIT_OPTIONAL_LOCKS"] = "0"
    if sock:
        e["DELPHI_SOCK"] = sock
        e["GIT_ASKPASS"] = ASKPASS
        e["SSH_ASKPASS"] = ASKPASS
        e["SSH_ASKPASS_REQUIRE"] = "force"
    else:
        # No one to ask: fail fast rather than hang on a prompt.
        e["GIT_ASKPASS"] = "/bin/false"
        e["SSH_ASKPASS"] = "/bin/false"
        e["SSH_ASKPASS_REQUIRE"] = "force"
    # ssh cannot fall back to a terminal either: every process starts in a
    # session of its own, which has no controlling tty to open.
    if extra:
        e.update(extra)
    return e


class Git:
    """git, pointed at one repository (or at none, for clone/init)."""

    def __init__(self, root=None, sock=None):
        self.root = root
        self.sock = sock

    def argv(self, args, creds=False):
        a = ["git"]
        if self.root:
            a += ["-C", self.root]
        a += BASE_ARGS
        if creds:
            a += CREDS.args()
        return a + list(args)

    def run(self, args, input=None, cancel=None, ok=(0,), lock=True,
            creds=False, text=True, **envkw):
        """Run to completion; return stdout. Raises GitError on a code not in
        ok, Cancelled if cancel fired."""
        cancel = cancel or Cancel()
        cancel.check()
        argv = self.argv(args, creds)
        p = subprocess.Popen(argv, stdin=subprocess.PIPE if input is not None
                             else subprocess.DEVNULL,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             env=env(self.sock, lock, **envkw),
                             start_new_session=True)
        cancel.attach(p)
        try:
            data = input.encode() if isinstance(input, str) else input
            out, err = p.communicate(data)
        finally:
            cancel.detach(p)
        if cancel.done:
            raise Cancelled()
        err = err.decode("utf-8", "replace")
        if p.returncode not in ok:
            raise GitError(list(args), p.returncode, err)
        return out.decode("utf-8", "replace") if text else out

    def code(self, args, cancel=None, lock=False):
        """Exit status only — for questions git answers with one."""
        (cancel or Cancel()).check()
        p = subprocess.run(self.argv(args), stdin=subprocess.DEVNULL,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           env=env(lock=lock))
        return p.returncode

    def stream(self, args, on_text, cancel=None, input=None, lock=True,
               creds=False, **envkw):
        """Run, handing each line of stderr AND stdout to on_text(stream,
        line) as it arrives — git's progress counters redraw with \\r, which
        is treated as a line end, so 45%, 46%... each arrive. Returns
        (code, stdout, stderr) with the full text kept for the error."""
        cancel = cancel or Cancel()
        cancel.check()
        p = subprocess.Popen(self.argv(args, creds),
                             stdin=subprocess.PIPE if input is not None
                             else subprocess.DEVNULL,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             env=env(self.sock, lock, **envkw),
                             start_new_session=True)
        cancel.attach(p)
        kept = {"out": [], "err": []}

        def pump(f, name):
            buf = b""
            while True:
                chunk = f.read1(4096) if hasattr(f, "read1") else f.read(4096)
                if not chunk:
                    break
                buf += chunk
                while True:
                    i = min([k for k in (buf.find(b"\n"), buf.find(b"\r"))
                             if k >= 0], default=-1)
                    if i < 0:
                        break
                    line, buf = buf[:i], buf[i + 1:]
                    s = line.decode("utf-8", "replace")
                    kept[name].append(s)
                    if s.strip():
                        on_text(name, s)
            if buf:
                s = buf.decode("utf-8", "replace")
                kept[name].append(s)
                on_text(name, s)

        ts = [threading.Thread(target=pump, args=(p.stdout, "out"), daemon=True),
              threading.Thread(target=pump, args=(p.stderr, "err"), daemon=True)]
        for t in ts:
            t.start()
        try:
            if input is not None:
                p.stdin.write(input.encode() if isinstance(input, str) else input)
                p.stdin.close()
            p.wait()
            for t in ts:
                t.join()
        finally:
            cancel.detach(p)
        if cancel.done:
            raise Cancelled()
        out, err = "\n".join(kept["out"]), "\n".join(kept["err"])
        return p.returncode, out, err

    def stream_ok(self, args, on_text, cancel=None, **kw):
        code, out, err = self.stream(args, on_text, cancel, **kw)
        if code != 0:
            raise GitError(list(args), code, _last_lines(err or out))
        return out


def _last_lines(text, n=12):
    # Progress counters leave hundreds of lines behind; the reason a push
    # failed is in the last few.
    lines = [l for l in text.splitlines() if l.strip()]
    return "\n".join(lines[-n:])


def progress_of(line):
    """git's progress line → (phase, percent) or None.
    'Receiving objects:  45% (450/1000), 1.2 MiB | 3 MiB/s' → ('Receiving
    objects', 45). The 'remote: ' prefix the server's half carries is kept off
    the phase."""
    s = line.strip()
    if s.startswith("remote:"):
        s = s[7:].strip()
    head, sep, rest = s.partition(":")
    if not sep:
        return None
    rest = rest.strip()
    pct = rest.split("%", 1)[0]
    if "%" in rest and pct.strip().isdigit():
        return head.strip(), int(pct.strip())
    return None

# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# ONE REPOSITORY — every question and every change delphi has for it.
#
# Methods take plain values and return plain dicts and lists: the daemon sends
# them as JSON unchanged, and the tests call them directly. Nothing here knows
# a window exists. Two arguments are common to almost all:
#
#   cancel  the request's gitrun.Cancel
#   emit    emit(dict) — progress and interim results, sent as events tagged
#           with the request they belong to
#
# Reads are lock-free (lock=False → GIT_OPTIONAL_LOCKS=0). Writes are not
# serialised here; the daemon runs a repository's writes one at a time.

import os
import re
import tempfile

import diff as D
import stow as ST
import status as S
from gitrun import Git, GitError, progress_of

US = "\x1f"   # unit separator between fields of one record
RS = "\x1e"   # record separator — commit subjects may hold anything else


def discover(path):
    """The repository a path is in, or None. Works from any subdirectory, a
    linked worktree, or the git directory of a bare repository."""
    g = Git(path if os.path.isdir(path) else os.path.dirname(path))
    try:
        out = g.run(["rev-parse", "--path-format=absolute", "--show-toplevel",
                     "--git-dir", "--git-common-dir", "--is-bare-repository"],
                    lock=False)
    except (GitError, FileNotFoundError, NotADirectoryError):
        try:
            out = g.run(["rev-parse", "--path-format=absolute", "--git-dir",
                         "--git-common-dir", "--is-bare-repository"], lock=False)
            gd, common, bare = out.splitlines()[:3]
            return {"root": gd, "gitdir": gd, "common": common, "bare": True}
        except (GitError, FileNotFoundError, NotADirectoryError, ValueError):
            return None
    top, gd, common, bare = out.splitlines()[:4]
    return {"root": top, "gitdir": gd, "common": common, "bare": bare == "true",
            "worktree": os.path.realpath(gd) != os.path.realpath(common)}


SKIP = {"node_modules", ".cache", ".npm", ".cargo", ".rustup", ".local",
        "target", "build", "dist", ".venv", "venv", "__pycache__", ".git",
        "Trash", ".Trash", ".mozilla", ".steam", "go", ".gradle", ".m2"}


def scan(roots, depth=4, cancel=None, emit=None):
    """Repositories under the given directories, `depth` levels down. A found
    repository is not descended into — its subdirectories are its own, and
    submodules are listed by the repository itself. Hidden directories other
    than .config are skipped: that is where caches and app data live."""
    found = []
    stack = [(os.path.expanduser(r), 0) for r in roots]
    seen = set()
    while stack:
        if cancel:
            cancel.check()
        d, lv = stack.pop()
        try:
            real = os.path.realpath(d)
            if real in seen:
                continue
            seen.add(real)
            with os.scandir(d) as it:
                ents = list(it)
        except OSError:
            continue
        if any(e.name == ".git" for e in ents):
            r = {"root": d, "name": os.path.basename(d.rstrip("/")) or d}
            found.append(r)
            if emit:
                emit({"found": r})
            continue
        if lv >= depth:
            continue
        for e in ents:
            if not e.is_dir(follow_symlinks=False) or e.name in SKIP:
                continue
            if e.name.startswith(".") and e.name != ".config":
                continue
            stack.append((e.path, lv + 1))
    found.sort(key=lambda r: r["root"])
    return found


def init(path, branch=None):
    os.makedirs(path, exist_ok=True)
    a = ["init"]
    if branch:
        a += ["-b", branch]
    Git(path).run(a + [path])
    return discover(path)


def clone(url, dest, sock=None, cancel=None, emit=None, depth=None,
          blobless=False, branch=None):
    a = ["clone", "--progress"]
    if depth:
        a += ["--depth", str(depth)]
    if blobless:
        # Every commit and tree, no file contents until a checkout needs them:
        # the cheap way into a huge repository with all its history.
        a += ["--filter=blob:none"]
    if branch:
        a += ["--branch", branch]
    a += ["--", url, dest]
    Git(None, sock).stream_ok(a, _progress(emit), cancel, creds=True)
    return discover(dest)


def _progress(emit):
    def on(stream, line):
        if not emit:
            return
        p = progress_of(line)
        if p:
            emit({"progress": {"phase": p[0], "percent": p[1]}})
        else:
            emit({"log": line})
    return on


def remote_key(url):
    """A remote's address as (host, owner/name) — https, ssh and scp-like
    alike — or None: what tells two addresses of one repository apart from
    two repositories."""
    u = str(url or "").strip()
    m = (re.match(r"^(?:https?|ssh|git)://(?:[^@/]+@)?([^/:]+)(?::\d+)?/(.+?)(?:\.git)?/?$", u)
         or re.match(r"^(?:[^@]+@)?([^:/]+):(.+?)(?:\.git)?/?$", u))
    return (m.group(1).lower(), m.group(2).lower()) if m else None


class Repo:
    def __init__(self, path, sock=None):
        info = discover(path)
        if not info:
            raise GitError(["rev-parse"], 128, f"not a git repository: {path}")
        self.info = info
        self.root = info["root"]
        self.gitdir = info["gitdir"]
        self.git = Git(self.root, sock)

    # ── kept out of the repository, kept on disk ───────────────────────────
    # A file you make inside a repository and do not want in it (a build's
    # binary, user 2026-10-11: spoot's bin/): ignored — in .gitignore, for
    # everyone who clones it, or in the git directory's info/exclude, for
    # this machine only. One already committed is first untracked (git rm
    # --cached): the next commit takes it out of the repository, and the
    # file stays where it is.
    def ignore(self, patterns, where="gitignore", cancel=None):
        path = (os.path.join(self.root, ".gitignore") if where == "gitignore"
                else os.path.join(self.info["common"], "info", "exclude"))
        try:
            with open(path) as f:
                have = f.read()
        except OSError:
            have = ""
        lines = {l.strip() for l in have.splitlines()}
        new = [p for p in patterns if p.strip() and p.strip() not in lines]
        if new:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "a") as f:
                if have and not have.endswith("\n"):
                    f.write("\n")
                f.write("\n".join(new) + "\n")
        return {"added": new, "file": path}

    def untrack(self, paths, ignore=True, where="gitignore", cancel=None):
        self.git.run(["rm", "--cached", "-r", "-q", "--"] + list(paths), cancel=cancel)
        if ignore:
            self.ignore(["/" + p.strip("/") + ("/" if os.path.isdir(os.path.join(self.root, p)) else "")
                         for p in paths], where, cancel)
        return {"untracked": list(paths)}

    # ── releases: what changed since the last one ─────────────────────────
    def last_tag(self, rev="HEAD", cancel=None):
        """The newest tag reachable from rev, or "" when there is none."""
        try:
            return self.git.run(["describe", "--tags", "--abbrev=0", rev],
                                cancel=cancel, lock=False).strip()
        except GitError:
            return ""

    def changelog(self, since="", until="HEAD", cancel=None):
        """The commits since a tag (or all of them), oldest last, merges left
        out — a release's notes where the forge writes none."""
        rng = f"{since}..{until}" if since else until
        out = self.git.run(["log", "--no-merges", "-z", f"--format=%s{US}%h{US}%an", rng],
                           cancel=cancel, lock=False)
        res = []
        for rec in out.split("\0"):
            f = rec.strip("\n").split(US)
            if len(f) == 3 and f[0]:
                res.append({"subject": f[0], "sha": f[1], "author": f[2]})
        return res

    # ── dotfiles: its stow packages (core/stow.py; never stowed here) ────
    def stow_packages(self, target=None, cancel=None):
        return ST.packages(self.root, target, cancel)

    def stow_plan(self, name, target=None, cancel=None):
        return ST.plan(self.root, name, target, cancel)

    def stow_copy_in(self, src, package, target=None, cancel=None):
        return ST.copy_in(self.root, src, package, target, cancel)

    # ── status ──────────────────────────────────────────────────────────
    def status(self, cancel=None, ignored=False):
        a = ["status", "--porcelain=v2", "-z", "--branch", "--show-stash",
             "--untracked-files=all"]
        if ignored:
            a.append("--ignored=matching")
        st = S.parse(self.git.run(a, cancel=cancel, lock=False))
        st["state"] = S.repo_state(self.gitdir)
        st["root"] = self.root
        return st

    # ── diffs ───────────────────────────────────────────────────────────
    def diff(self, path=None, staged=False, context=3, cancel=None,
             start=0, budget=4000, untracked=False):
        """One file's diff (or every file's, path=None). staged → index vs
        HEAD, else working tree vs index. An untracked file is shown against
        nothing, without touching the index."""
        if untracked and path:
            out = self.git.run(["diff", "--no-index", "--no-ext-diff",
                                f"-U{context}", "--", "/dev/null", path],
                               cancel=cancel, ok=(0, 1), lock=False)
        else:
            a = ["diff", "--no-ext-diff", f"-U{context}", "--find-renames"]
            if staged:
                a.append("--cached")
            if path:
                a += ["--", path]
            out = self.git.run(a, cancel=cancel, lock=False)
        files = D.parse(out)
        files, more = D.page(files, start, budget)
        return {"files": files, "more": more}

    def show(self, rev, path=None, context=3, cancel=None, start=0, budget=4000):
        """What a commit changed — against its first parent, so a merge shows
        what it brought into the branch, the question people usually ask."""
        a = ["show", "--format=", "--no-ext-diff", f"-U{context}",
             "--find-renames", "--diff-merges=first-parent", rev]
        if path:
            a += ["--", path]
        files = D.parse(self.git.run(a, cancel=cancel, lock=False))
        files, more = D.page(files, start, budget)
        return {"files": files, "more": more}

    def compare(self, a, b, path=None, context=3, cancel=None, start=0,
                budget=4000):
        args = ["diff", "--no-ext-diff", f"-U{context}", "--find-renames",
                f"{a}...{b}"]
        if path:
            args += ["--", path]
        files = D.parse(self.git.run(args, cancel=cancel, lock=False))
        files, more = D.page(files, start, budget)
        return {"files": files, "more": more}

    # ── staging ─────────────────────────────────────────────────────────
    def stage(self, paths, cancel=None):
        # -A so a deleted file is staged as a deletion, not refused.
        self.git.run(["add", "-A", "--"] + list(paths), cancel=cancel)

    def stage_all(self, cancel=None):
        self.git.run(["add", "-A"], cancel=cancel)

    def unstage(self, paths, cancel=None):
        if self._unborn():
            self.git.run(["rm", "--cached", "-r", "-q", "--"] + list(paths),
                         cancel=cancel)
        else:
            self.git.run(["restore", "--staged", "--"] + list(paths),
                         cancel=cancel)

    def unstage_all(self, cancel=None):
        if self._unborn():
            self.git.run(["rm", "--cached", "-r", "-q", "."], cancel=cancel)
        else:
            self.git.run(["reset", "-q"], cancel=cancel)

    def discard(self, paths, cancel=None):
        """Throw away working-tree changes to tracked files. The caller has
        asked the user; this does not."""
        self.git.run(["restore", "--worktree", "--"] + list(paths), cancel=cancel)

    def clean(self, paths, cancel=None):
        """Delete untracked files — again, asked about before this runs."""
        self.git.run(["clean", "-f", "-d", "-q", "--"] + list(paths), cancel=cancel)

    def stage_lines(self, path, chosen, cancel=None, untracked=False):
        """Stage part of a file's working-tree diff. chosen = {hunk: None |
        [line indexes]} against the diff this same path gives right now."""
        if untracked:
            # Partial staging of a new file: git add -N gives it an empty
            # index entry, and the chosen lines go onto that.
            self.git.run(["add", "-N", "--", path], cancel=cancel)
        files = D.parse(self.git.run(["diff", "--no-ext-diff", "-U3", "--", path],
                                     cancel=cancel, lock=False))
        f = self._one(files, path)
        if f["status"] == "added":
            f = D.as_modification(f)
        self._apply(D.build(f, _keys(chosen)), ["--cached"], cancel)

    def unstage_lines(self, path, chosen, cancel=None):
        files = D.parse(self.git.run(["diff", "--cached", "--no-ext-diff", "-U3",
                                      "--", path], cancel=cancel, lock=False))
        f = self._one(files, path)
        if f["status"] == "added":
            f = D.as_modification(f)
            p = D.build(f, _keys(chosen), reverse=True)
            self._apply(p, ["--cached", "-R"], cancel)
            return
        self._apply(D.build(f, _keys(chosen), reverse=True), ["--cached", "-R"], cancel)

    def discard_lines(self, path, chosen, cancel=None):
        files = D.parse(self.git.run(["diff", "--no-ext-diff", "-U3", "--", path],
                                     cancel=cancel, lock=False))
        f = self._one(files, path)
        self._apply(D.build(f, _keys(chosen), reverse=True), ["-R"], cancel)

    def _one(self, files, path):
        for f in files:
            if path in (f["new"], f["old"]):
                return f
        raise GitError(["diff"], 1, f"no changes in {path} any more")

    def _apply(self, patch, flags, cancel):
        if not patch:
            return
        self.git.run(["apply", "--recount", "--whitespace=nowarn"] + flags + ["-"],
                     input=patch, cancel=cancel)

    def _unborn(self):
        return self.git.code(["rev-parse", "-q", "--verify", "HEAD"]) != 0

    # ── committing ──────────────────────────────────────────────────────
    def identity(self):
        def get(k):
            try:
                return self.git.run(["config", "--get", k], lock=False).strip()
            except GitError:
                return ""
        return {"name": get("user.name"), "email": get("user.email"),
                "sign": get("commit.gpgsign") == "true"}

    def commit(self, message, amend=False, no_verify=False, allow_empty=False,
               signoff=False, cancel=None, emit=None):
        a = ["commit", "-F", "-", "--cleanup=strip"]
        if amend:
            a.append("--amend")
        if no_verify:
            a.append("--no-verify")
        if allow_empty:
            a.append("--allow-empty")
        if signoff:
            a.append("--signoff")
        # A hook's output (pre-commit, commit-msg) is the user's to read: it
        # streams as log lines, and its last lines are the error if it fails.
        self.git.stream_ok(a, _progress(emit), cancel, input=message)
        return self.head()

    def undo_commit(self, cancel=None):
        """The last commit taken back: its changes staged again, its message
        handed back for the box (Changes' Undo, user 2026-10-14). The first
        commit of a branch has no parent to go back to: the branch is made
        unborn again, everything still staged."""
        msg = self.last_message()
        try:
            self.git.run(["rev-parse", "--verify", "--quiet", "HEAD~1"], cancel=cancel, lock=False)
            first = False
        except GitError:
            first = True
        if first:
            self.git.run(["update-ref", "-d", "HEAD"], cancel=cancel)
        else:
            self.git.run(["reset", "--soft", "HEAD~1"], cancel=cancel)
        return {"message": msg, "first": first}

    def last_message(self):
        return self.git.run(["log", "-1", "--format=%B"], lock=False).rstrip("\n")

    def head(self):
        try:
            sha = self.git.run(["rev-parse", "HEAD"], lock=False).strip()
        except GitError:
            sha = None
        return {"sha": sha}

    # ── history ─────────────────────────────────────────────────────────
    LOG_FORMAT = US.join(["%H", "%P", "%an", "%ae", "%at", "%cn", "%ct",
                          "%D", "%s"]) + RS

    def log_args(self, revs=None, path=None, all_refs=True, first_parent=False,
                 grep=None, author=None):
        a = ["log", "--topo-order", "-z", f"--format={self.LOG_FORMAT}",
             "--decorate=full"]
        if first_parent:
            a.append("--first-parent")
        if grep:
            a += ["--regexp-ignore-case", f"--grep={grep}"]
        if author:
            a += [f"--author={author}"]
        if revs:
            a += list(revs)
        elif all_refs:
            a += ["--branches", "--remotes", "--tags", "HEAD"]
        if path:
            # one file's history: --parents rewrites each commit's parents to
            # the nearest ones that touched it, or the graph's lines would run
            # off to commits that are not in the list
            a.insert(1, "--parents")
            a += ["--", path]
        return a

    def message(self, sha, cancel=None):
        out = self.git.run(["show", "-s", "--format=%B%x00%GG%x00%G?", sha],
                           cancel=cancel, lock=False)
        body, _, rest = out.partition("\0")
        gg, _, code = rest.partition("\0")
        return {"body": body.rstrip("\n"), "signature": code.strip() or "N",
                "signer": gg.strip()}

    def files_in(self, sha, cancel=None):
        """The files a commit touched, with counts — the list beside a
        commit's diff, cheap before any diff is read."""
        out = self.git.run(["show", "--format=", "-z", "--numstat",
                            "--find-renames", "--diff-merges=first-parent", sha],
                           cancel=cancel, lock=False)
        res, parts, i = [], out.split("\0"), 0
        while i < len(parts):
            rec = parts[i]; i += 1
            if not rec.strip():
                continue
            add, dele, path = (rec.lstrip("\n").split("\t", 2) + ["", ""])[:3]
            e = {"added": None if add == "-" else int(add or 0),
                 "deleted": None if dele == "-" else int(dele or 0)}
            if path == "":
                # rename: the two paths follow as their own NUL records
                e["from"], e["path"] = parts[i], parts[i + 1]; i += 2
            else:
                e["path"] = path
            res.append(e)
        # what happened to each: A added, M modified, D deleted, R renamed —
        # a file a commit removed is one that can be brought back from it
        st = self.git.run(["show", "--format=", "-z", "--name-status",
                           "--find-renames", "--diff-merges=first-parent", sha],
                          cancel=cancel, lock=False).split("\0")
        how, i = {}, 0
        while i < len(st):
            code = st[i].strip(); i += 1
            if not code:
                continue
            if code[0] in "RC":
                how[st[i + 1]] = code[0]; i += 2
            else:
                how[st[i]] = code[0]; i += 1
        for e in res:
            e["status"] = how.get(e["path"], "M")
        return res

    def bring_back(self, sha, paths, cancel=None):
        """Files a commit removed (or changed), back as they were just before
        it — in the working tree and staged, to commit. From the commit's
        first parent; a first commit has none, so nothing to bring back."""
        if self.git.code(["rev-parse", "-q", "--verify", f"{sha}^"]) != 0:
            raise GitError(["checkout"], 1, "the first commit removed nothing — there is nothing before it")
        self.git.run(["checkout", f"{sha}^", "--"] + list(paths), cancel=cancel)
        return {"paths": list(paths)}

    def blame(self, path, rev=None, cancel=None):
        a = ["blame", "--porcelain", "-w"]
        if rev:
            a.append(rev)
        out = self.git.run(a + ["--", path], cancel=cancel, lock=False)
        commits, lines, cur = {}, [], None
        for l in out.split("\n"):
            if not l:
                continue
            if l[0] == "\t":
                lines.append({"sha": cur, "text": l[1:]})
                continue
            f = l.split(" ")
            if len(f[0]) == 40 and all(c in "0123456789abcdef" for c in f[0]):
                cur = f[0]
                commits.setdefault(cur, {})
            elif cur:
                k, _, v = l.partition(" ")
                if k in ("author", "author-time", "summary"):
                    commits[cur][k.replace("-", "")] = v
        return {"commits": commits, "lines": lines}

    # ── branches and other refs ─────────────────────────────────────────
    def refs(self, cancel=None):
        fmt = US.join(["%(refname)", "%(objectname)", "%(upstream)",
                       "%(upstream:track,nobracket)", "%(HEAD)",
                       "%(committerdate:unix)", "%(subject)",
                       "%(worktreepath)", "%(symref)"])
        out = self.git.run(["for-each-ref", f"--format={fmt}",
                            "refs/heads", "refs/remotes", "refs/tags"],
                           cancel=cancel, lock=False)
        res = {"local": [], "remote": [], "tags": []}
        for line in out.splitlines():
            f = line.split(US)
            if len(f) < 9:
                continue
            ref, sha, up, track, head, when, subj, wt, sym = f[:9]
            ahead = behind = 0
            gone = "gone" in track
            for m in re.finditer(r"(ahead|behind) (\d+)", track):
                if m.group(1) == "ahead":
                    ahead = int(m.group(2))
                else:
                    behind = int(m.group(2))
            e = {"ref": ref, "sha": sha, "when": int(when or 0), "subject": subj}
            if ref.startswith("refs/heads/"):
                e.update(name=ref[11:], current=head == "*",
                         upstream=up[13:] if up.startswith("refs/remotes/") else up or None,
                         ahead=ahead, behind=behind, gone=gone,
                         worktree=wt or None)
                res["local"].append(e)
            elif ref.startswith("refs/remotes/"):
                if sym:
                    continue   # origin/HEAD → origin/main: not a branch
                e["name"] = ref[13:]
                e["remote"] = e["name"].split("/", 1)[0]
                res["remote"].append(e)
            else:
                e["name"] = ref[10:]
                res["tags"].append(e)
        return res

    def branch_create(self, name, start=None, switch=True, cancel=None):
        if switch:
            a = ["switch", "-c", name] + ([start] if start else [])
        else:
            a = ["branch", name] + ([start] if start else [])
        self.git.run(a, cancel=cancel)

    def branch_track(self, remote_branch, name=None, cancel=None):
        """A local branch following a remote one, switched to."""
        name = name or remote_branch.split("/", 1)[1]
        self.git.run(["switch", "-c", name, "--track", remote_branch], cancel=cancel)

    def switch(self, name, cancel=None, detach=False):
        a = ["switch"] + (["--detach"] if detach else []) + [name]
        self.git.run(a, cancel=cancel)

    def branch_delete(self, name, force=False, cancel=None):
        self.git.run(["branch", "-D" if force else "-d", name], cancel=cancel)

    def branch_rename(self, old, new, cancel=None):
        self.git.run(["branch", "-m", old, new], cancel=cancel)

    def set_upstream(self, branch, upstream, cancel=None):
        if upstream:
            self.git.run(["branch", f"--set-upstream-to={upstream}", branch],
                         cancel=cancel)
        else:
            self.git.run(["branch", "--unset-upstream", branch], cancel=cancel)

    def tag_create(self, name, rev="HEAD", message=None, cancel=None):
        a = ["tag"]
        if message:
            a += ["-a", "-m", message]
        self.git.run(a + [name, rev], cancel=cancel)

    def tag_delete(self, name, cancel=None):
        self.git.run(["tag", "-d", name], cancel=cancel)

    # ── remotes and the network ─────────────────────────────────────────
    def remotes(self, cancel=None):
        out = self.git.run(["remote", "-v"], cancel=cancel, lock=False)
        res = {}
        for l in out.splitlines():
            name, url, kind = (l.split() + ["", "", ""])[:3]
            r = res.setdefault(name, {"name": name})
            r["push" if "push" in kind else "fetch"] = url
        return list(res.values())

    def remote_add(self, name, url, cancel=None):
        self.git.run(["remote", "add", name, url], cancel=cancel)

    def remote_remove(self, name, cancel=None):
        self.git.run(["remote", "remove", name], cancel=cancel)

    def remote_set_url(self, name, url, cancel=None):
        self.git.run(["remote", "set-url", name, url], cancel=cancel)

    def connect(self, url, branch=None, remote="origin", onto=False, cancel=None, emit=None):
        """This repository joined to one that already exists elsewhere (a
        GitHub repository made before, by hand uploads or anyone else): the
        remote added (or pointed there), its history fetched, and

          - a branch with NO commits yet put on that history — the files on
            disk left exactly as they are (a mixed reset), so what is shown
            as changed afterwards is only what really differs, and a push
            lands on top of what is there instead of beside it;
          - a branch WITH commits left alone if its history and the remote's
            share nothing (adopted: false, unrelated: true) — joining those
            is a merge of unrelated histories, a choice too big to make here;
            if they are related, it simply tracks the remote branch;
          - with `onto`, a branch whose history is unrelated is put on the
            remote's all the same: its commits kept on a branch of their own
            (backup, named in the answer) so nothing is lost, the branch
            moved onto the remote's history with every file left as it is
            (mixed reset) — what it had that the remote has not shows as
            changes, to commit on top. For the repository made here and
            committed before it was connected (user, 2026-10-11).

        branch: the remote's branch to take (its default, from the forge);
        guessed from the remote's HEAD when not given."""
        names = [r["name"] for r in self.remotes(cancel)]
        if remote in names:
            self.git.run(["remote", "set-url", remote, url], cancel=cancel)
        else:
            self.git.run(["remote", "add", remote, url], cancel=cancel)
        self.git.stream_ok(["fetch", "--progress", remote], _progress(emit), cancel, creds=True)
        if not branch:
            self.git.code(["remote", "set-head", remote, "--auto"])
            out = self.git.run(["symbolic-ref", "-q", "--short", f"refs/remotes/{remote}/HEAD"],
                               ok=(0, 1), lock=False).strip()
            branch = out.split("/", 1)[1] if "/" in out else "main"
        theirs = f"refs/remotes/{remote}/{branch}"
        if self.git.code(["rev-parse", "-q", "--verify", theirs]) != 0:
            # an empty repository there: nothing to adopt, only somewhere to push
            return {"remote": remote, "branch": branch, "adopted": False, "empty": True}
        if self._unborn():
            # the branch takes the remote's name and history; the index is
            # made to match it, the working tree is not touched
            self.git.run(["symbolic-ref", "HEAD", f"refs/heads/{branch}"], cancel=cancel)
            self.git.run(["reset", "-q", "--mixed", theirs], cancel=cancel)
            self.git.run(["branch", f"--set-upstream-to={remote}/{branch}", branch], cancel=cancel)
            return {"remote": remote, "branch": branch, "adopted": True}
        head = self.git.run(["symbolic-ref", "-q", "--short", "HEAD"], ok=(0, 1), lock=False).strip()
        if self.git.code(["merge-base", "HEAD", theirs]) != 0:
            if not onto or not head:
                return {"remote": remote, "branch": branch, "adopted": False, "unrelated": True}
            # the commits here, kept under a name of their own
            backup, n = f"{head}-before-{remote}", 1
            while self.git.code(["rev-parse", "-q", "--verify", f"refs/heads/{backup}"]) == 0:
                n += 1
                backup = f"{head}-before-{remote}-{n}"
            self.git.run(["branch", backup, "HEAD"], cancel=cancel)
            self.git.run(["reset", "-q", "--mixed", theirs], cancel=cancel)
            name = head
            if head != branch and self.git.code(["rev-parse", "-q", "--verify", f"refs/heads/{branch}"]) != 0:
                self.git.run(["branch", "-m", head, branch], cancel=cancel)
                name = branch
            self.git.run(["branch", f"--set-upstream-to={remote}/{branch}", name], cancel=cancel)
            return {"remote": remote, "branch": branch, "adopted": True, "backup": backup}
        if head:
            self.git.run(["branch", f"--set-upstream-to={remote}/{branch}", head], cancel=cancel)
        return {"remote": remote, "branch": branch, "adopted": False, "tracking": bool(head)}

    def fetch(self, remote=None, prune=True, cancel=None, emit=None):
        a = ["fetch", "--progress"]
        if prune:
            a.append("--prune")
        a += [remote] if remote else ["--all"]
        self.git.stream_ok(a, _progress(emit), cancel, creds=True)

    def pull(self, mode="ff-only", cancel=None, emit=None):
        """mode: ff-only (never makes a commit the user did not ask for),
        rebase, or merge."""
        a = ["pull", "--progress", {"ff-only": "--ff-only", "rebase": "--rebase",
                                    "merge": "--no-rebase"}[mode]]
        self.git.stream_ok(a, _progress(emit), cancel, creds=True)

    def push(self, remote=None, branch=None, force=False, set_upstream=False,
             tags=False, cancel=None, emit=None):
        a = ["push", "--progress", "--porcelain"]
        if force:
            # --force-with-lease, never --force: it refuses when the remote
            # moved since the last fetch, the case where force loses work.
            a.append("--force-with-lease")
        if set_upstream:
            a.append("--set-upstream")
        if tags:
            a.append("--follow-tags")
        if remote:
            a.append(remote)
            if branch:
                a.append(branch)
        self.git.stream_ok(a, _progress(emit), cancel, creds=True)

    def pull_checkout(self, remote, number, branch=None, same=False,
                      refs="pull", cancel=None, emit=None):
        """A pull request's commits, on a branch here, switched to. One made
        from a branch of this same repository is that branch, tracking it —
        so a push goes back into the pull request. One from a fork is
        fetched from the pull request's own ref into pr-N."""
        if same and branch:
            track = f"refs/remotes/{remote}/{branch}"
            self.git.stream_ok(["fetch", "--progress", remote,
                                f"+refs/heads/{branch}:{track}"],
                               _progress(emit), cancel, creds=True)
            name, start = branch, track
        else:
            track = f"refs/remotes/{remote}/pr/{number}"
            # GitHub and Forgejo keep a pull request at refs/pull/N/head,
            # GitLab a merge request at refs/merge-requests/N/head
            self.git.stream_ok(["fetch", "--progress", remote,
                                f"+refs/{refs}/{number}/head:{track}"],
                               _progress(emit), cancel, creds=True)
            name, start = f"pr-{number}", track
        if self.git.code(["rev-parse", "-q", "--verify", f"refs/heads/{name}"]) == 0:
            self.git.run(["switch", name], cancel=cancel)
            # brought up to the pull request, when that is only forward
            moved = self.git.code(["merge", "--ff-only", "-q", start]) == 0
            return {"branch": name, "behind": not moved}
        a = ["switch", "-c", name] + (["--track"] if same and branch else []) + [start]
        self.git.run(a, cancel=cancel)
        return {"branch": name, "behind": False}

    # ── stash ───────────────────────────────────────────────────────────
    def stashes(self, cancel=None):
        out = self.git.run(["stash", "list", "-z",
                            f"--format=%gd{US}%H{US}%ct{US}%gs"],
                           cancel=cancel, lock=False)
        res = []
        for rec in out.split("\0"):
            f = rec.split(US)
            if len(f) == 4:
                res.append({"ref": f[0], "sha": f[1], "when": int(f[2] or 0),
                            "message": f[3]})
        return res

    def stash_push(self, message=None, untracked=True, staged_only=False,
                   paths=None, cancel=None):
        a = ["stash", "push"]
        if message:
            a += ["-m", message]
        if staged_only:
            a.append("--staged")
        elif untracked:
            a.append("--include-untracked")
        if paths:
            a += ["--"] + list(paths)
        self.git.run(a, cancel=cancel)

    def stash_apply(self, ref, pop=False, index=True, cancel=None):
        a = ["stash", "pop" if pop else "apply"]
        if index:
            a.append("--index")
        self.git.run(a + [ref], cancel=cancel)

    def stash_drop(self, ref, cancel=None):
        self.git.run(["stash", "drop", ref], cancel=cancel)

    def stash_branch(self, name, ref, cancel=None):
        self.git.run(["stash", "branch", name, ref], cancel=cancel)

    # ── worktrees ───────────────────────────────────────────────────────
    def worktrees(self, cancel=None):
        out = self.git.run(["worktree", "list", "--porcelain", "-z"],
                           cancel=cancel, lock=False)
        res, cur = [], None
        for f in out.split("\0"):
            if not f:
                if cur:
                    res.append(cur); cur = None
                continue
            k, _, v = f.partition(" ")
            if k == "worktree":
                cur = {"path": v, "branch": None, "sha": None}
            elif cur is None:
                continue
            elif k == "HEAD":
                cur["sha"] = v
            elif k == "branch":
                cur["branch"] = v[11:] if v.startswith("refs/heads/") else v
            elif k in ("bare", "detached"):
                cur[k] = True
            elif k in ("locked", "prunable"):
                cur[k] = v or True
        if cur:
            res.append(cur)
        main = os.path.realpath(self.root)
        for w in res:
            w["current"] = os.path.realpath(w["path"]) == main
        if res:
            res[0]["main"] = True
        return res

    def worktree_add(self, path, branch=None, new_branch=None, start=None,
                     cancel=None):
        a = ["worktree", "add"]
        if new_branch:
            a += ["-b", new_branch, path] + ([start] if start else [])
        else:
            a += [path] + ([branch] if branch else [])
        self.git.run(a, cancel=cancel)
        return discover(path)

    def worktree_remove(self, path, force=False, cancel=None):
        self.git.run(["worktree", "remove"] + (["--force"] if force else [])
                     + [path], cancel=cancel)

    def worktree_prune(self, cancel=None):
        self.git.run(["worktree", "prune"], cancel=cancel)

    # ── merge, rebase, cherry-pick, revert, reset ───────────────────────
    def merge(self, rev, ff="ff", squash=False, cancel=None, emit=None):
        a = ["merge", "--no-edit"]
        a.append({"ff": "--ff", "no-ff": "--no-ff", "ff-only": "--ff-only"}[ff])
        if squash:
            a.append("--squash")
        return self._may_conflict(a + [rev], cancel, emit)

    def cherry_pick(self, shas, cancel=None, emit=None):
        return self._may_conflict(["cherry-pick"] + list(shas), cancel, emit)

    def revert(self, sha, cancel=None, emit=None):
        return self._may_conflict(["revert", "--no-edit", sha], cancel, emit)

    def rebase(self, onto, cancel=None, emit=None):
        return self._may_conflict(["rebase", onto], cancel, emit)

    def rebase_plan(self, base, cancel=None):
        """The commits an interactive rebase onto `base` would list, oldest
        first — what the plan editor starts from."""
        out = self.git.run(["log", "--reverse", "--topo-order", "--no-merges",
                            f"--format=%H{US}%s", f"{base}..HEAD"],
                           cancel=cancel, lock=False)
        return [dict(zip(("sha", "subject"), l.split(US, 1)))
                for l in out.splitlines() if l]

    def rebase_interactive(self, base, plan, cancel=None, emit=None):
        """Run an interactive rebase with a plan made in delphi rather than in
        an editor. plan: [{action, sha, message?}] oldest first; action is
        pick, reword, edit, squash, fixup or drop.

        git still wants to open an editor for the todo list; the sequence
        editor delphi hands it copies the finished plan over git's file and
        exits. A reword becomes a pick plus an exec that amends the message
        from a file, so no second editor ever opens; a squash keeps git's
        combined message (GIT_EDITOR is `:`), and fixup -C or a reword after
        it is how a different one is chosen."""
        tmp = tempfile.mkdtemp(prefix="delphi-rebase-")
        lines = []
        for n, step in enumerate(plan):
            act, sha = step["action"], step["sha"]
            if act == "reword":
                mf = os.path.join(tmp, f"msg{n}")
                with open(mf, "w") as f:
                    f.write(step.get("message", ""))
                lines.append(f"pick {sha}")
                lines.append("exec git commit --amend --no-verify --cleanup=strip -F "
                             + _sh(mf))
            elif act in ("pick", "edit", "squash", "fixup", "drop"):
                lines.append(f"{act} {sha}")
            else:
                raise GitError(["rebase"], 1, f"unknown plan step: {act}")
        todo = os.path.join(tmp, "todo")
        with open(todo, "w") as f:
            f.write("\n".join(lines) + "\n")
        return self._may_conflict(["rebase", "-i", base], cancel, emit,
                                  seq_editor="cp " + _sh(todo))

    def sequence(self, op, action, cancel=None, emit=None):
        """continue / abort / skip / quit for whatever is in progress — op is
        rebase, merge, cherry-pick, revert or am."""
        return self._may_conflict([op, f"--{action}"], cancel, emit)

    def _may_conflict(self, args, cancel, emit, **envkw):
        # Stopping for conflicts is not a failure of the request: git did what
        # it was asked and is waiting. The answer says so, and the status that
        # follows lists the conflicts.
        code, out, err = self.git.stream(args, _progress(emit), cancel, **envkw)
        st = S.repo_state(self.gitdir)
        if code == 0:
            return {"done": st is None, "state": st}
        if st is not None or "CONFLICT" in out + err:
            return {"done": False, "state": st, "conflicts": True,
                    "message": (err or out).strip()[-2000:]}
        raise GitError(args, code, (err or out).strip()[-2000:])

    def reset(self, rev, mode="mixed", cancel=None):
        self.git.run(["reset", f"--{mode}", rev], cancel=cancel)

    # ── conflicts ───────────────────────────────────────────────────────
    def take(self, path, side, cancel=None):
        """Resolve a conflicted file whole: our side or theirs, then mark it
        resolved. A side that deleted the file has none to take: taking it
        deletes the file (git rm), which is what that side did."""
        n = 2 if side == "ours" else 3
        try:
            self.git.run(["cat-file", "-e", f":{n}:{path}"], cancel=cancel, lock=False)
        except GitError:
            self.git.run(["rm", "-q", "--", path], cancel=cancel)
            return {"removed": True}
        self.git.run(["checkout", f"--{side}", "--", path], cancel=cancel)
        self.git.run(["add", "--", path], cancel=cancel)
        return {"removed": False}

    # ── one conflict at a time ──────────────────────────────────────────
    # A conflicted file as git left it on disk, read into blocks: the
    # stretches both sides agree on, and each conflict between its markers —
    # our lines, the base's (when the conflict style shows them), theirs.
    # The page chooses per conflict; resolve_blocks writes the file back
    # with those chosen and the rest left marked, refusing if the file
    # changed since it was read (the token is its content's hash).
    def conflict_blocks(self, path, cancel=None):
        import hashlib
        full = os.path.join(self.root, path)
        with open(full, "rb") as f:
            raw = f.read()
        token = hashlib.sha1(raw).hexdigest()
        if b"\0" in raw[:8000]:
            return {"binary": True, "token": token, "blocks": []}
        text = raw.decode("utf-8", errors="replace")
        return {"binary": False, "token": token, "blocks": _blocks(text)}

    def resolve_blocks(self, path, choices, token, mark=False, cancel=None):
        import hashlib
        full = os.path.join(self.root, path)
        with open(full, "rb") as f:
            raw = f.read()
        if hashlib.sha1(raw).hexdigest() != token:
            raise GitError(["merge"], 1, f"{path} changed since it was shown — look again before choosing")
        blocks = _blocks(raw.decode("utf-8", errors="replace"))
        out, left, i = [], 0, 0
        for b in blocks:
            if "same" in b:
                out += b["same"]
                continue
            how = choices.get(str(i))
            i += 1
            if how == "ours":
                out += b["ours"]
            elif how == "theirs":
                out += b["theirs"]
            elif how == "both":
                out += b["ours"] + b["theirs"]
            elif how == "theirsFirst":
                out += b["theirs"] + b["ours"]
            elif how == "neither":
                pass
            else:
                out += b["raw"]
                left += 1
        with open(full, "w", encoding="utf-8", newline="") as f:
            f.write("".join(out))
        if left == 0 and mark:
            self.git.run(["add", "--", path], cancel=cancel)
        return {"left": left, "marked": left == 0 and mark}

    def mark_resolved(self, paths, cancel=None):
        self.git.run(["add", "--"] + list(paths), cancel=cancel)

    def conflict_versions(self, path, cancel=None):
        """The three sides of a conflicted file — base, ours, theirs — written
        to files beside nothing, for the merge view to open. A missing side
        (added by one, deleted by other) is absent from the answer."""
        tmp = tempfile.mkdtemp(prefix="delphi-merge-")
        res = {"merged": os.path.join(self.root, path)}
        for n, side in ((1, "base"), (2, "ours"), (3, "theirs")):
            try:
                data = self.git.run(["show", f":{n}:{path}"], cancel=cancel,
                                    lock=False, text=False)
            except GitError:
                continue
            p = os.path.join(tmp, f"{side}.{os.path.basename(path)}")
            with open(p, "wb") as f:
                f.write(data)
            res[side] = p
        return res


def _blocks(text):
    """A file's text → [{"same": [lines]} | {"ours", "base", "theirs":
    [lines], "oursLabel", "theirsLabel", "raw": [lines]}], every line with
    its own ending, so writing them back changes nothing not chosen. A
    marker is seven of its character at a line's start, then a space or
    the line's end; an opening without its close is left as text."""
    lines = text.splitlines(keepends=True)
    out, same, i = [], [], 0

    def mark(line, ch):
        body = line.rstrip("\r\n")
        return body.startswith(ch * 7) and (len(body) == 7 or body[7] == " ")

    while i < len(lines):
        if mark(lines[i], "<"):
            j, part, ours, base, theirs = i + 1, "ours", [], None, []
            while j < len(lines) and not mark(lines[j], ">"):
                if part == "ours" and mark(lines[j], "|"):
                    part, base = "base", []
                elif part in ("ours", "base") and lines[j].rstrip("\r\n") == "=" * 7:
                    part = "theirs"
                else:
                    (ours if part == "ours" else base if part == "base" else theirs).append(lines[j])
                j += 1
            if j < len(lines) and part == "theirs":
                if same:
                    out.append({"same": same})
                    same = []
                out.append({"ours": ours, "base": base, "theirs": theirs,
                            "oursLabel": lines[i].rstrip("\r\n")[8:].strip(),
                            "theirsLabel": lines[j].rstrip("\r\n")[8:].strip(),
                            "raw": lines[i:j + 1]})
                i = j + 1
                continue
        same.append(lines[i])
        i += 1
    if same:
        out.append({"same": same})
    return out


def _keys(chosen):
    # JSON objects have string keys; hunk indexes are ints here.
    return {int(k): v for k, v in chosen.items()}


def _sh(s):
    return "'" + s.replace("'", "'\\''") + "'"


def parse_log(chunk):
    """Records of LOG_FORMAT (RS-terminated, -z adds a NUL after each) →
    commit dicts. Returns (commits, leftover) — a partial record at the end
    of a read waits for the next."""
    recs = chunk.split(RS)
    rest = recs.pop()
    res = []
    for r in recs:
        r = r.lstrip("\0\n")
        f = r.split(US)
        if len(f) < 9:
            continue
        refs = [x.strip() for x in f[7].split(",") if x.strip()]
        res.append({"sha": f[0], "parents": f[1].split() if f[1] else [],
                    "author": f[2], "email": f[3], "when": int(f[4] or 0),
                    "committer": f[5], "committed": int(f[6] or 0),
                    "refs": _refs(refs), "subject": f[8]})
    return res, rest


def _refs(decor):
    out = []
    for d in decor:
        head = False
        if d.startswith("HEAD -> "):
            head = True; d = d[8:]
        elif d == "HEAD":
            out.append({"kind": "head", "name": "HEAD"}); continue
        if d.startswith("tag: "):
            out.append({"kind": "tag", "name": d[5:].replace("refs/tags/", "", 1)})
        elif d.startswith("refs/heads/"):
            out.append({"kind": "local", "name": d[11:], "head": head})
        elif d.startswith("refs/remotes/"):
            if d.endswith("/HEAD"):
                continue
            out.append({"kind": "remote", "name": d[13:]})
        elif d.startswith("refs/stash"):
            out.append({"kind": "stash", "name": "stash"})
        else:
            out.append({"kind": "other", "name": d})
    return out

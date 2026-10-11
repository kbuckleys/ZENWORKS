#!/usr/bin/env python3
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# DELPHI CORE TESTS — delphi/core against real repositories made for the
# occasion in a throwaway directory, with a throwaway HOME so the user's own
# gitconfig (helpers, hooks, signing) can neither help nor hurt.
#
#   python3 oracle/tests/delphi-core.py           every test
#   python3 oracle/tests/delphi-core.py stage     tests whose name has "stage"

import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORE = os.path.join(ROOT, "delphi", "core")
sys.path.insert(0, CORE)

TMP = tempfile.mkdtemp(prefix="delphi-test-")
os.environ.update({
    "HOME": TMP, "XDG_CONFIG_HOME": os.path.join(TMP, ".config"),
    "XDG_RUNTIME_DIR": TMP,
    "GIT_CONFIG_NOSYSTEM": "1", "GIT_AUTHOR_NAME": "Test",
    "GIT_AUTHOR_EMAIL": "t@example.com", "GIT_COMMITTER_NAME": "Test",
    "GIT_COMMITTER_EMAIL": "t@example.com",
})
subprocess.run(["git", "config", "--global", "init.defaultBranch", "main"], check=True)

import diff as D        # noqa: E402
import gitrun           # noqa: E402
import repo as R        # noqa: E402
import status as S      # noqa: E402
from graph import Lanes  # noqa: E402
import server           # noqa: E402

gitrun.CREDS.user_helper = ""   # never look for the keyring helper in tests

TESTS = []


def test(fn):
    TESTS.append(fn)
    return fn


def eq(a, b, what=""):
    if a != b:
        raise AssertionError(f"{what}\n  got:  {a!r}\n  want: {b!r}")


def sh(cwd, *args, input=None):
    r = subprocess.run(["git", "-C", cwd] + list(args), input=input, text=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if r.returncode:
        raise AssertionError(f"git {' '.join(args)}: {r.stderr}")
    return r.stdout


n = [0]


def fresh(files=None):
    n[0] += 1
    d = os.path.join(TMP, f"r{n[0]}")
    os.makedirs(d)
    sh(d, "init", "-q")
    for k, v in (files or {}).items():
        write(d, k, v)
    if files:
        sh(d, "add", "-A")
        sh(d, "commit", "-q", "-m", "init")
    return d


def write(d, name, text):
    p = os.path.join(d, name)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        f.write(text)


def read(d, name):
    with open(os.path.join(d, name)) as f:
        return f.read()


def index_of(d, name):
    return sh(d, "show", f":{name}")


LINES = "".join(f"line {i}\n" for i in range(1, 31))


# ── status ──────────────────────────────────────────────────────────────
@test
def status_lists():
    d = fresh({"a": "1\n", "b": "2\n", "c": "3\n"})
    write(d, "a", "1x\n"); sh(d, "add", "a"); write(d, "a", "1xy\n")
    sh(d, "mv", "b", "b2")
    write(d, "new file", "n\n")
    os.remove(os.path.join(d, "c"))
    r = R.Repo(d)
    st = r.status()
    eq(st["branch"]["head"], "main", "branch")
    eq(sorted((e["path"], e["kind"]) for e in st["staged"]),
       [("a", "modified"), ("b2", "renamed")], "staged")
    eq([e.get("from") for e in st["staged"] if e["path"] == "b2"], ["b"], "rename from")
    eq(sorted((e["path"], e["kind"]) for e in st["unstaged"]),
       [("a", "modified"), ("c", "deleted")], "unstaged")
    eq([e["path"] for e in st["untracked"]], ["new file"], "untracked, with a space")
    eq(st["state"], None, "idle")


@test
def status_upstream_and_stash():
    remote = os.path.join(TMP, "remote1.git")
    subprocess.run(["git", "init", "-q", "--bare", remote], check=True)
    d = fresh({"a": "1\n"})
    sh(d, "remote", "add", "origin", remote)
    sh(d, "push", "-q", "-u", "origin", "main")
    write(d, "a", "2\n"); sh(d, "commit", "-q", "-am", "two")
    write(d, "a", "3\n"); sh(d, "stash", "-q")
    st = R.Repo(d).status()
    eq(st["branch"]["upstream"], "origin/main")
    eq((st["branch"]["ahead"], st["branch"]["behind"]), (1, 0))
    eq(st["stash"], 1)


@test
def status_conflict_and_state():
    d = fresh({"f": "base\n"})
    sh(d, "switch", "-q", "-c", "other")
    write(d, "f", "theirs\n"); sh(d, "commit", "-q", "-am", "t")
    sh(d, "switch", "-q", "main")
    write(d, "f", "ours\n"); sh(d, "commit", "-q", "-am", "o")
    r = R.Repo(d)
    res = r.merge("other")
    eq(res["conflicts"], True, "merge stops")
    st = r.status()
    eq([(c["path"], c["how"]) for c in st["conflicts"]], [("f", "both modified")])
    eq(st["state"]["op"], "merge")
    v = r.conflict_versions("f")
    eq((open(v["base"]).read(), open(v["ours"]).read(), open(v["theirs"]).read()),
       ("base\n", "ours\n", "theirs\n"), "three sides")
    r.take("f", "theirs")
    res = r.sequence("merge", "continue")
    eq(res["done"], True, "merge finished")
    eq(read(d, "f"), "theirs\n")
    eq(r.status()["state"], None)


# ── diffs ───────────────────────────────────────────────────────────────
@test
def diff_parse_and_words():
    d = fresh({"f": "alpha beta gamma\nkeep\n"})
    write(d, "f", "alpha BETA gamma\nkeep\nadded\n")
    out = R.Repo(d).diff("f")
    f = out["files"][0]
    eq((f["old"], f["new"], f["status"]), ("f", "f", "modified"))
    ls = f["hunks"][0]["lines"]
    eq([l["t"] for l in ls], ["-", "+", " ", "+"])
    eq(ls[0]["spans"], [[6, 10]], "beta lit")
    eq(ls[1]["spans"], [[6, 10]], "BETA lit")
    eq((ls[2]["old"], ls[2]["new"]), (2, 2), "line numbers")


@test
def diff_quoted_path_and_binary():
    d = fresh({"t\tab": "x\n", "bin": ""})
    write(d, "t\tab", "y\n")
    with open(os.path.join(d, "bin"), "wb") as f:
        f.write(b"\0\1\2")
    fs = R.Repo(d).diff()["files"]
    eq(sorted(f["new"] for f in fs), ["bin", "t\tab"])
    eq([f["binary"] for f in fs if f["new"] == "bin"], [True])


@test
def diff_paging():
    d = fresh({"f": LINES * 20})
    write(d, "f", "".join(("X" + l if i % 30 == 0 else l)
                          for i, l in enumerate((LINES * 20).splitlines(True))))
    r = R.Repo(d)
    whole = r.diff("f", budget=10**9)["files"][0]["hunks"]
    got, start = [], 0
    while start is not None:
        page = r.diff("f", start=start, budget=20)
        for f in page["files"]:
            got += f["hunks"]
        start = page["more"]
    eq(len(got), len(whole), "every hunk once")
    eq(got, whole)


# ── partial staging ─────────────────────────────────────────────────────
@test
def stage_one_hunk():
    d = fresh({"f": LINES})
    write(d, "f", LINES.replace("line 2\n", "line two\n").replace("line 25\n", "line 25!\n"))
    r = R.Repo(d)
    r.stage_lines("f", {"1": None})
    eq(index_of(d, "f"), LINES.replace("line 25\n", "line 25!\n"), "only the second hunk")
    eq(len(r.diff("f")["files"][0]["hunks"]), 1, "first still unstaged")


@test
def stage_some_lines():
    d = fresh({"f": LINES})
    new = LINES.replace("line 10\nline 11\nline 12\n", "TEN\nELEVEN\nTWELVE\n")
    write(d, "f", new)
    r = R.Repo(d)
    h = r.diff("f")["files"][0]["hunks"][0]
    # stage only "-line 11" and "+ELEVEN"
    pick = [i for i, l in enumerate(h["lines"])
            if l["text"] in ("line 11", "ELEVEN") and l["t"] != " "]
    r.stage_lines("f", {"0": pick})
    eq(index_of(d, "f"), LINES.replace("line 11\n", "ELEVEN\n"))
    eq(read(d, "f"), new, "working tree untouched")


@test
def stage_only_an_addition_or_deletion():
    d = fresh({"f": LINES})
    write(d, "f", LINES.replace("line 5\n", "").replace("line 6\n", "line 6\nNEW\n"))
    r = R.Repo(d)
    h = r.diff("f")["files"][0]["hunks"][0]
    plus = [i for i, l in enumerate(h["lines"]) if l["t"] == "+"]
    r.stage_lines("f", {"0": plus})
    eq(index_of(d, "f"), LINES.replace("line 6\n", "line 6\nNEW\n"), "addition alone")
    h = r.diff("f")["files"][0]["hunks"][0]
    minus = [i for i, l in enumerate(h["lines"]) if l["t"] == "-"]
    r.stage_lines("f", {"0": minus})
    eq(index_of(d, "f"), read(d, "f"), "then the deletion")


@test
def stage_second_hunk_after_partial_first():
    # the new-side start of a later hunk moves when an earlier one is taken
    # only in part; git apply must still find it
    d = fresh({"f": LINES})
    new = LINES.replace("line 3\n", "A\nB\nC\nline 3\n").replace("line 27\n", "Z\n")
    write(d, "f", new)
    r = R.Repo(d)
    hs = r.diff("f")["files"][0]["hunks"]
    first_plus = [i for i, l in enumerate(hs[0]["lines"]) if l["text"] == "B"]
    r.stage_lines("f", {"0": first_plus, "1": None})
    eq(index_of(d, "f"),
       LINES.replace("line 3\n", "B\nline 3\n").replace("line 27\n", "Z\n"))


@test
def unstage_some_lines():
    d = fresh({"f": LINES})
    new = LINES.replace("line 10\nline 11\n", "TEN\nELEVEN\n")
    write(d, "f", new)
    sh(d, "add", "f")
    r = R.Repo(d)
    h = r.diff("f", staged=True)["files"][0]["hunks"][0]
    pick = [i for i, l in enumerate(h["lines"])
            if l["text"] in ("line 10", "TEN") and l["t"] != " "]
    r.unstage_lines("f", {"0": pick})
    eq(index_of(d, "f"), LINES.replace("line 11\n", "ELEVEN\n"))
    eq(read(d, "f"), new)


@test
def discard_some_lines():
    d = fresh({"f": LINES})
    write(d, "f", LINES.replace("line 4\n", "FOUR\n").replace("line 20\n", "TWENTY\n"))
    r = R.Repo(d)
    r.discard_lines("f", {"0": None})
    eq(read(d, "f"), LINES.replace("line 20\n", "TWENTY\n"))


@test
def stage_part_of_untracked_file():
    d = fresh({"keep": "k\n"})
    write(d, "new", "one\ntwo\nthree\n")
    r = R.Repo(d)
    h = r.diff("new", untracked=True)["files"][0]["hunks"][0]
    pick = [i for i, l in enumerate(h["lines"]) if l["text"] in ("one", "three")]
    r.stage_lines("new", {"0": pick}, untracked=True)
    eq(index_of(d, "new"), "one\nthree\n")
    r.unstage_lines("new", {"0": [0]})
    eq(index_of(d, "new"), "three\n", "and back out, line by line")


@test
def stage_with_no_newline_at_end():
    d = fresh({"f": "a\nb"})
    write(d, "f", "a\nb\nc")
    r = R.Repo(d)
    r.stage_lines("f", {"0": None})
    eq(index_of(d, "f"), "a\nb\nc")


@test
def stage_nothing_is_a_no_op():
    d = fresh({"f": LINES})
    write(d, "f", LINES.replace("line 2\n", "two\n"))
    r = R.Repo(d)
    r.stage_lines("f", {"0": []})
    eq(index_of(d, "f"), LINES)


@test
def unstage_in_unborn_repo():
    d = fresh()
    write(d, "a", "1\n"); sh(d, "add", "a")
    r = R.Repo(d)
    r.unstage(["a"])
    eq([e["path"] for e in r.status()["untracked"]], ["a"])


# ── commits, refs, stash, worktrees ─────────────────────────────────────
@test
def commit_and_amend():
    d = fresh({"a": "1\n"})
    r = R.Repo(d)
    write(d, "a", "2\n"); r.stage(["a"])
    sha = r.commit("second\n\nbody text\n")["sha"]
    eq(r.message(sha)["body"], "second\n\nbody text")
    r.commit("second, reworded", amend=True)
    eq(r.last_message(), "second, reworded")
    eq(sh(d, "rev-list", "--count", "HEAD").strip(), "2", "amend, not a new commit")


@test
def commit_hook_output_streams():
    d = fresh({"a": "1\n"})
    hook = os.path.join(d, ".git", "hooks", "pre-commit")
    write(d, ".git/hooks/pre-commit", "#!/bin/sh\necho checking >&2\necho nope >&2\nexit 1\n")
    os.chmod(hook, 0o755)
    r = R.Repo(d)
    write(d, "a", "2\n"); r.stage(["a"])
    seen = []
    try:
        r.commit("x", emit=seen.append)
        raise AssertionError("hook should have failed the commit")
    except gitrun.GitError as e:
        eq("nope" in e.err, True, "the hook's words are the error")
    eq({"log": "checking"} in seen, True, "streamed as it ran")
    r.commit("x", no_verify=True)


@test
def refs_branches_tags():
    d = fresh({"a": "1\n"})
    r = R.Repo(d)
    r.branch_create("feature", switch=False)
    r.tag_create("v1", message="first")
    r.switch("feature")
    refs = r.refs()
    eq(sorted(b["name"] for b in refs["local"]), ["feature", "main"])
    eq([b["name"] for b in refs["local"] if b["current"]], ["feature"])
    eq([t["name"] for t in refs["tags"]], ["v1"])
    r.switch("main")
    r.branch_rename("feature", "feat")
    r.branch_delete("feat")
    eq([b["name"] for b in r.refs()["local"]], ["main"])


@test
def stash_round_trip():
    d = fresh({"a": "1\n"})
    r = R.Repo(d)
    write(d, "a", "2\n"); write(d, "u", "untracked\n")
    r.stash_push("wip")
    eq(r.status()["untracked"], [], "untracked went too")
    s = r.stashes()
    eq((len(s), s[0]["ref"], s[0]["message"].endswith("wip")), (1, "stash@{0}", True))
    r.stash_apply("stash@{0}", pop=True)
    eq((read(d, "a"), read(d, "u")), ("2\n", "untracked\n"))
    eq(r.stashes(), [])


@test
def worktrees_add_list_remove():
    d = fresh({"a": "1\n"})
    r = R.Repo(d)
    wt = os.path.join(TMP, f"wt{n[0]}")
    info = r.worktree_add(wt, new_branch="side")
    eq(info["worktree"], True)
    ws = r.worktrees()
    eq([(os.path.realpath(w["path"]), w["branch"]) for w in ws],
       [(os.path.realpath(d), "main"), (os.path.realpath(wt), "side")])
    eq([w.get("current") for w in ws], [True, False])
    eq([b["worktree"] for b in r.refs()["local"] if b["name"] == "side"],
       [wt], "branch knows where it is checked out")
    r.worktree_remove(wt)
    eq(len(r.worktrees()), 1)


@test
def rebase_with_a_plan():
    d = fresh({"f": "0\n"})
    for i in range(1, 5):
        write(d, f"f{i}", f"{i}\n"); sh(d, "add", "-A"); sh(d, "commit", "-q", "-m", f"c{i}")
    r = R.Repo(d)
    plan = r.rebase_plan("HEAD~4")
    eq([p["subject"] for p in plan], ["c1", "c2", "c3", "c4"])
    shas = {p["subject"]: p["sha"] for p in plan}
    res = r.rebase_interactive("HEAD~4", [
        {"action": "pick", "sha": shas["c3"]},
        {"action": "reword", "sha": shas["c1"], "message": "first, renamed\n"},
        {"action": "fixup", "sha": shas["c2"]},
        {"action": "drop", "sha": shas["c4"]},
    ])
    eq(res["done"], True, "rebase finished")
    eq(sh(d, "log", "--format=%s", "HEAD~2..HEAD").split("\n")[:2],
       ["first, renamed", "c3"])
    eq(os.path.exists(os.path.join(d, "f4")), False, "c4 dropped")
    eq(os.path.exists(os.path.join(d, "f2")), True, "c2 folded in")


@test
def fetch_pull_push_with_progress():
    remote = os.path.join(TMP, "remote2.git")
    subprocess.run(["git", "init", "-q", "--bare", remote], check=True)
    a = fresh({"a": "1\n"})
    ra = R.Repo(a)
    ra.remote_add("origin", remote)
    ra.push("origin", "main", set_upstream=True)
    b = os.path.join(TMP, "clone2")
    seen = []
    R.clone(remote, b, emit=seen.append)
    eq(read(b, "a"), "1\n", "cloned")
    write(a, "a", "2\n"); ra.stage(["a"]); ra.commit("two"); ra.push()
    rb = R.Repo(b)
    rb.fetch()
    eq(rb.status()["branch"]["behind"], 1)
    rb.pull()
    eq(read(b, "a"), "2\n", "pulled")
    eq([r["name"] for r in ra.remotes()], ["origin"])


# ── history and the graph ───────────────────────────────────────────────
@test
def pull_checkout_fork_and_same():
    # a remote with a branch of its own and a pull request's ref, as GitHub
    # keeps them (refs/pull/N/head)
    remote = os.path.join(TMP, "prs.git")
    subprocess.run(["git", "init", "-q", "--bare", remote], check=True)
    d = fresh({"a": "1\n"})
    sh(d, "remote", "add", "origin", remote)
    sh(d, "push", "-q", "origin", "main")
    sh(d, "switch", "-q", "-c", "feature")
    write(d, "a", "feature\n"); sh(d, "commit", "-q", "-am", "feature")
    sh(d, "push", "-q", "origin", "feature")
    sh(d, "switch", "-q", "-c", "forked", "main")
    write(d, "b", "fork\n"); sh(d, "add", "b"); sh(d, "commit", "-q", "-m", "fork")
    sh(d, "push", "-q", "origin", "forked:refs/pull/7/head")
    sh(d, "switch", "-q", "main")
    sh(d, "branch", "-q", "-D", "feature", "forked")
    r = R.Repo(d)
    # from a fork: pr-7, made from the pull request's ref
    eq(r.pull_checkout("origin", 7), {"branch": "pr-7", "behind": False}, "fork")
    eq(read(d, "b"), "fork\n", "the fork's file")
    # again, after it moved on: brought forward
    sh(d, "switch", "-q", "-c", "more", "pr-7")
    write(d, "b", "fork 2\n"); sh(d, "commit", "-q", "-am", "more")
    sh(d, "push", "-q", "-f", "origin", "more:refs/pull/7/head")
    sh(d, "switch", "-q", "main")
    eq(r.pull_checkout("origin", 7)["branch"], "pr-7", "again")
    eq(read(d, "b"), "fork 2\n", "moved forward")
    # from this repository: the branch itself, tracking it
    sh(d, "switch", "-q", "main")
    eq(r.pull_checkout("origin", 8, branch="feature", same=True)["branch"], "feature", "same")
    eq(sh(d, "rev-parse", "--abbrev-ref", "@{u}").strip(), "origin/feature", "tracks")
    eq(read(d, "a"), "feature\n", "the branch's file")


@test
def upload_expands_directories():
    import github
    d = os.path.join(TMP, "up")
    for f in ["proj/a", "proj/sub/b", "proj/.git/HEAD", "solo"]:
        write(d, f, "x")
    os.symlink(os.path.join(d, "proj"), os.path.join(d, "proj", "sub", "loop"))
    os.symlink(os.path.join(d, "nowhere"), os.path.join(d, "proj", "broken"))
    got = github.expand([{"local": os.path.join(d, "proj"), "path": "into/proj"},
                         {"local": os.path.join(d, "solo"), "path": "/solo"},
                         {"local": os.path.join(d, "proj", "a"), "path": "into/proj/a"}])
    eq([g["path"] for g in got], ["into/proj/a", "into/proj/sub/b", "solo"],
       "files under it, no .git, no links followed, no twice")
    # caches left out; inside a repository, what it ignores too — but a
    # file chosen by name goes regardless
    r = fresh({".gitignore": "*.log\nbuild/\n", "keep.txt": "k"})
    for f in ["build/out.bin", "x.log", "__pycache__/m.pyc", "src/m.py", "src/m.pyc"]:
        write(r, f, "x")
    got, skipped = github.expand([{"local": r, "path": "r"},
                                  {"local": os.path.join(r, "x.log"), "path": "named.log"}], count=True)
    eq([g["path"] for g in got], ["r/.gitignore", "r/keep.txt", "r/src/m.py", "named.log"], "kept")
    # x.log, build/out.bin, src/m.pyc; a skipped directory (__pycache__) is
    # passed by, not walked to be counted
    eq(skipped, 3, "left out")


@test
def upload_batches_and_rides_out_github():
    # against a fake API: 230 text files and a picture go as one blob and
    # four trees, a "slow down" is waited out, a stalled commit sent again
    import io
    import json as J
    import urllib.error
    import github
    d = os.path.join(TMP, "batch")
    for i in range(230):
        write(d, f"dir/f{i:03}.txt", "x" * i)
    with open(os.path.join(d, "dir", "p.png"), "wb") as fh:
        fh.write(b"\x89PNG\0\1")
    calls, once = [], {"slow": True, "stall": True}

    class Answer:
        def __init__(self, v): self.v, self.headers = v, {}
        def read(self): return J.dumps(self.v).encode()
        def __enter__(self): return self
        def __exit__(self, *a): pass

    def fake(req, timeout):
        path, m = req.full_url.replace(github.API, ""), req.get_method()
        calls.append((m, path.rsplit("/", 1)[-1] if "/git/" in path else path))
        if path.endswith("/git/trees") and once["slow"]:
            once["slow"] = False
            raise urllib.error.HTTPError(req.full_url, 403, "", {"Retry-After": "3"},
                                         io.BytesIO(b'{"message": "secondary rate limit"}'))
        if path.endswith("/git/commits") and once["stall"]:
            once["stall"] = False
            raise TimeoutError("timed out")
        if path == "/repos/me/r": return Answer({"default_branch": "main"})
        if "/git/ref/heads/" in path: return Answer({"object": {"sha": "base"}})
        if path.endswith("/commits/base"): return Answer({"tree": {"sha": "t0"}})
        return Answer({"sha": "s"})

    keep = (github.urllib.request.urlopen, github.token, github.time.sleep)
    github.urllib.request.urlopen, github.token = fake, (lambda: ("t", "gh"))
    github.time.sleep = lambda s: None
    try:
        ev = []
        github.upload("me/r", [{"local": os.path.join(d, "dir"), "path": "dir"}], "m", None, ev.append)
    finally:
        github.urllib.request.urlopen, github.token, github.time.sleep = keep
    writes = [c for c in calls if c[0] != "GET"]
    # three batches (100, 100, 31 — the picture last, a blob of its own);
    # the first tree asked twice (slowed down), the commit twice (stalled)
    eq([c[1] for c in writes], ["trees", "trees", "trees", "blobs", "trees", "commits", "commits", "main"], "requests")
    eq(sum(1 for e in ev if e.get("state") == "sent"), 231, "every file said sent")
    eq([e for e in ev if "phase" in e], [{"phase": "waiting", "seconds": 3}, {"phase": "committing"}], "phases")


@test
def connect_adopts_existing_history():
    # "GitHub": a repository with history made elsewhere (hand uploads)
    hub = os.path.join(TMP, "hub.git")
    subprocess.run(["git", "init", "-q", "--bare", hub], check=True)
    up = fresh({"a.txt": "1\n", "b.txt": "2\n", "c.txt": "3\n"})
    write(up, "a.txt", "1 more\n"); sh(up, "commit", "-qam", "second")
    sh(up, "remote", "add", "origin", hub)
    sh(up, "push", "-q", "origin", "main")
    # here: the same files, one changed, one new — a fresh repository, no commits
    d = fresh()
    write(d, "a.txt", "1 more\n"); write(d, "b.txt", "2 changed\n")
    write(d, "c.txt", "3\n"); write(d, "new.txt", "n\n")
    r = R.Repo(d)
    eq(r.connect(hub)["adopted"], True, "adopted")
    eq(sh(d, "log", "--format=%s").split(), ["second", "init"], "its history is ours now")
    eq(sh(d, "rev-parse", "--abbrev-ref", "@{u}").strip(), "origin/main", "tracks it")
    st = r.status()
    eq([e["path"] for e in st["unstaged"]], ["b.txt"], "only what differs")
    eq([e["path"] for e in st["untracked"]], ["new.txt"], "and what is new")
    eq(read(d, "b.txt"), "2 changed\n", "files untouched")
    # a branch with commits of its own, unrelated: left alone
    e = fresh({"x.txt": "x\n"})
    got = R.Repo(e).connect(hub)
    eq((got["adopted"], got.get("unrelated")), (False, True), "unrelated refused")
    eq(sh(e, "log", "--format=%s").split(), ["init"], "its own history kept")
    # …unless asked to go on top: kept on a backup branch, files untouched
    write(e, "a.txt", "1 more\n")
    got = R.Repo(e).connect(hub, onto=True)
    eq((got["adopted"], got["backup"]), (True, "main-before-origin"), "onto")
    eq(sh(e, "log", "--format=%s").split(), ["second", "init"], "on theirs now")
    eq(sh(e, "log", "--format=%s", "main-before-origin").split(), ["init"], "ours kept")
    eq(read(e, "x.txt"), "x\n", "files untouched")
    eq(sorted(x["path"] for x in R.Repo(e).status()["untracked"]), ["x.txt"], "ours shows as new")
    # an empty repository there: only somewhere to push
    empty = os.path.join(TMP, "empty.git")
    subprocess.run(["git", "init", "-q", "--bare", empty], check=True)
    eq(R.Repo(fresh()).connect(empty, branch="main").get("empty"), True, "empty remote")


@test
def bring_back_what_a_commit_removed():
    d = fresh({"LICENSE": "mit\n", "README.md": "hi\n", "keep": "k\n"})
    sh(d, "rm", "-q", "LICENSE", "README.md")
    write(d, "keep", "k2\n")
    sh(d, "commit", "-qam", "tidy")
    r = R.Repo(d)
    sha = sh(d, "rev-parse", "HEAD").strip()
    eq({f["path"]: f["status"] for f in r.files_in(sha)}, {"LICENSE": "D", "README.md": "D", "keep": "M"}, "status")
    r.bring_back(sha, ["LICENSE", "README.md"])
    eq(read(d, "LICENSE"), "mit\n", "back on disk")
    eq(sorted(e["path"] for e in r.status()["staged"]), ["LICENSE", "README.md"], "and staged")


@test
def forges_upload_as_one_commit():
    # GitLab and Codeberg against fakes: a directory's files go as ONE
    # request, created or updated as the branch has them; each is routed
    # by its prefix in the daemon
    import json as J
    import gitlab
    import forgejo
    d = os.path.join(TMP, "fup")
    write(d, "dir/new.txt", "n\n"); write(d, "dir/old.txt", "o\n")
    sent = []

    class Answer:
        def __init__(self, v): self.v, self.headers = v, {}
        def read(self): return J.dumps(self.v).encode()
        def __enter__(self): return self
        def __exit__(self, *a): pass

    def fake(req, timeout):
        u, m = req.full_url, req.get_method()
        body = J.loads(req.data) if req.data else None
        if m != "GET":
            sent.append((m, u, body))
        if u.endswith("/projects/me%2Fr") or u.endswith("/repos/me/r"):
            return Answer({"default_branch": "main"})
        if "/repository/tree" in u:
            return Answer([{"path": "dir/old.txt", "type": "blob"}])
        if "/branches/main" in u:
            return Answer({"commit": {"id": "c0"}})
        if "/git/trees/c0" in u:
            return Answer({"tree": [{"path": "dir/old.txt", "type": "blob", "sha": "s0"}]})
        return Answer({"id": "c1", "commit": {"sha": "c1"}})

    keep = (gitlab.urllib.parse, gitlab.rest.urllib.request.urlopen, gitlab.token, forgejo.token)
    gitlab.rest.urllib.request.urlopen = fake
    gitlab.token = lambda: ("t", "keyring")
    forgejo.token = lambda: ("t", "keyring")
    try:
        gitlab.upload("me/r", [{"local": os.path.join(d, "dir"), "path": "dir"}], "m")
        forgejo.upload("me/r", [{"local": os.path.join(d, "dir"), "path": "dir"}], "m")
    finally:
        gitlab.rest.urllib.request.urlopen, gitlab.token, forgejo.token = keep[1], keep[2], keep[3]
    eq(len(sent), 2, "one request each")
    gl, fj = sent[0][2], sent[1][2]
    eq(sorted((a["action"], a["file_path"]) for a in gl["actions"]),
       [("create", "dir/new.txt"), ("update", "dir/old.txt")], "gitlab actions")
    eq(sorted((f["operation"], f["path"], f.get("sha")) for f in fj["files"]),
       [("create", "dir/new.txt", None), ("update", "dir/old.txt", "s0")], "codeberg files")
    eq(sorted(server.FORGES), ["codeberg", "github", "gitlab"], "routed by prefix")


def continuous(rows):
    """Every line leaving a row's bottom arrives at the next row's top, in
    the same column and colour — and nothing else arrives."""
    for i in range(len(rows) - 1):
        # two lines may meet at one point on the boundary (a branch bending
        # into a line that runs on) — they arrive below as the one line
        out = sorted({(b, c) for _, b, c in rows[i]["bottom"]})
        inn = sorted({(a, c) for a, _, c in rows[i + 1]["top"]})
        if out != inn:
            raise AssertionError(f"row {i}→{i+1}: bottom {out} ≠ top {inn}")


@test
def graph_shapes():
    d = fresh({"f": "0\n"})
    sh(d, "switch", "-q", "-c", "b1")
    write(d, "x", "1\n"); sh(d, "add", "-A"); sh(d, "commit", "-q", "-m", "b1a")
    sh(d, "switch", "-q", "main")
    write(d, "y", "1\n"); sh(d, "add", "-A"); sh(d, "commit", "-q", "-m", "m1")
    sh(d, "switch", "-q", "-c", "b2")
    write(d, "z", "1\n"); sh(d, "add", "-A"); sh(d, "commit", "-q", "-m", "b2a")
    sh(d, "switch", "-q", "main")
    sh(d, "merge", "-q", "--no-ff", "-m", "merge b1", "b1")
    sh(d, "merge", "-q", "--no-ff", "-m", "merge b2", "b2")
    write(d, "w", "1\n"); sh(d, "add", "-A"); sh(d, "commit", "-q", "-m", "after")
    r = R.Repo(d)
    s = server.LogSession(r, {})
    rows = []
    while True:
        p = s.page(2)
        rows += p["commits"]
        if p["end"]:
            break
    s.close()
    eq(len(rows), 7, "every commit, across pages of 2")
    eq([c["row"] for c in rows], list(range(7)))
    continuous([c["graph"] for c in rows])
    eq(rows[0]["graph"]["col"], 0, "tip in the first column")
    eq(len(rows[1]["graph"]["bottom"]), 2, "a merge has two lines out")
    eq(rows[-1]["graph"]["bottom"], [], "root ends every line")
    eq(any(x["kind"] == "local" and x["name"] == "main" and x["head"]
           for x in rows[0]["refs"]), True, "HEAD -> main decoration")


@test
def graph_octopus_and_criss_cross():
    L = Lanes()
    # A merges B C D (octopus); B and C share parent E; D's parent F; E, F → G
    hist = [("A", ["B", "C", "D"]), ("B", ["E"]), ("C", ["E"]), ("D", ["F"]),
            ("E", ["G"]), ("F", ["G"]), ("G", [])]
    rows = [L.row(s, p) for s, p in hist]
    continuous(rows)
    eq(rows[0]["width"], 3)
    eq(rows[-1]["bottom"], [], "every line ends at the root")
    eq(L.lanes, [], "and nothing is left open")
    eq([r["col"] for r in rows[:2]], [0, 0], "first parents keep the column straight")


@test
def graph_on_real_histories():
    # Any repositories already on this machine (plato's plugin clones) make a
    # far less tidy history than the fixtures; the invariant must hold there.
    base = os.path.expanduser("~buck/.local/share/quickshell/plato/nvim/site/pack")
    seen = 0
    for dirpath, dirs, _ in os.walk(base):
        if ".git" in dirs or os.path.isfile(os.path.join(dirpath, ".git")):
            dirs[:] = []
            try:
                r = R.Repo(dirpath)
            except gitrun.GitError:
                continue
            s = server.LogSession(r, {})
            rows = []
            while len(rows) < 3000:
                p = s.page(500)
                rows += [c["graph"] for c in p["commits"]]
                if p["end"]:
                    break
            s.close()
            continuous(rows)
            seen += 1
        if seen >= 4:
            break
    print(f"    ({seen} real histories)")


@test
def blame_and_files():
    d = fresh({"f": "a\nb\n"})
    write(d, "f", "a\nB\n"); write(d, "g", "g\n")
    sh(d, "add", "-A"); sh(d, "commit", "-q", "-m", "two")
    r = R.Repo(d)
    b = r.blame("f")
    eq([l["text"] for l in b["lines"]], ["a", "B"])
    eq(len({l["sha"] for l in b["lines"]}), 2)
    fs = r.files_in("HEAD")
    eq(sorted((f["path"], f["added"], f["deleted"]) for f in fs),
       [("f", 1, 1), ("g", 1, 0)])


@test
def discovery():
    d = fresh({"sub/x": "1\n"})
    info = R.discover(os.path.join(d, "sub"))
    eq(info["root"], d)
    eq(R.discover(TMP + "/nowhere"), None)
    found = R.scan([TMP], depth=1)
    eq(any(f["root"] == d for f in found), True)


@test
def progress_lines():
    eq(gitrun.progress_of("Receiving objects:  45% (450/1000), 1.2 MiB"),
       ("Receiving objects", 45))
    eq(gitrun.progress_of("remote: Counting objects: 100% (3/3), done."),
       ("Counting objects", 100))
    eq(gitrun.progress_of("To github.com:x/y.git"), None)


# ── the daemon, end to end ──────────────────────────────────────────────
class Daemon:
    def __init__(self):
        self.p = subprocess.Popen([sys.executable, os.path.join(ROOT, "delphi", "bin", "delphid")],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  text=True)
        self.msgs = []
        self.cv = threading.Condition()
        threading.Thread(target=self._read, daemon=True).start()
        self.ready = self.wait(lambda m: m.get("event", {}).get("ready"))
        self.n = 0

    def _read(self):
        for line in self.p.stdout:
            with self.cv:
                self.msgs.append(json.loads(line))
                self.cv.notify_all()

    def wait(self, pred, timeout=20):
        end = time.time() + timeout
        with self.cv:
            while True:
                for m in self.msgs:
                    if pred(m):
                        self.msgs.remove(m)
                        return m
                left = end - time.time()
                if left <= 0:
                    raise AssertionError("daemon never answered")
                self.cv.wait(left)

    def send(self, op, repo=None, **args):
        self.n += 1
        self.p.stdin.write(json.dumps({"id": self.n, "op": op, "repo": repo,
                                       "args": args}) + "\n")
        self.p.stdin.flush()
        return self.n

    def call(self, op, repo=None, **args):
        i = self.send(op, repo, **args)
        return self.wait(lambda m: m.get("id") == i and "ok" in m)

    def close(self):
        self.p.stdin.close()
        self.p.wait(10)


@test
def daemon_end_to_end():
    d = fresh({"a": "1\n"})
    dm = Daemon()
    try:
        eq(dm.ready["event"]["protocol"], server.PROTOCOL)
        eq(dm.call("ping")["result"], {"protocol": server.PROTOCOL})
        write(d, "a", "2\n")
        st = dm.call("status", d)["result"]
        eq([e["path"] for e in st["unstaged"]], ["a"])
        eq(dm.call("stage", d, paths=["a"])["ok"], True)
        r = dm.call("commit", d, message="via daemon")
        eq(r["ok"], True, r.get("error"))
        eq(dm.call("lastMessage", d)["result"], "via daemon")
        bad = dm.call("switch", d, name="no-such-branch")
        eq((bad["ok"], bad["kind"]), (False, "git"))
        eq(dm.call("nonsense", d)["ok"], False)
        sid = dm.call("logOpen", d)["result"]["session"]
        page = dm.call("logPage", d, session=sid, count=10)["result"]
        eq([c["subject"] for c in page["commits"]], ["via daemon", "init"])
    finally:
        dm.close()


@test
def daemon_askpass_round_trip():
    dm = Daemon()
    try:
        sock = os.path.join(TMP, f"delphi-{dm.ready['event']['pid']}.sock")
        out = {}

        def ask():
            out["r"] = subprocess.run(
                [os.path.join(ROOT, "delphi", "bin", "delphi-askpass"),
                 "Password for 'https://me@example.com': "],
                env=dict(os.environ, DELPHI_SOCK=sock), text=True,
                stdout=subprocess.PIPE)
        t = threading.Thread(target=ask); t.start()
        q = dm.wait(lambda m: "ask" in m.get("event", {}))["event"]
        eq((q["kind"], q["secret"]), ("password", True))
        dm.call("answer", ask=q["ask"], text="s3cret")
        t.join(10)
        eq((out["r"].returncode, out["r"].stdout), (0, "s3cret\n"))
        # a dismissed question is a cancelled one
        t = threading.Thread(target=ask); t.start()
        q = dm.wait(lambda m: "ask" in m.get("event", {}))["event"]
        dm.call("answer", ask=q["ask"], text=None)
        t.join(10)
        eq(out["r"].returncode, 1)
    finally:
        dm.close()


@test
def daemon_cancel():
    dm = Daemon()
    try:
        d = fresh({"a": "1\n"})
        # a hook that never ends stands in for a hung push
        write(d, ".git/hooks/pre-commit", "#!/bin/sh\nsleep 60\n")
        os.chmod(os.path.join(d, ".git/hooks/pre-commit"), 0o755)
        write(d, "a", "2\n")
        dm.call("stage", d, paths=["a"])
        i = dm.send("commit", d, message="slow")
        time.sleep(0.5)
        t0 = time.time()
        dm.call("cancel", id=i)
        r = dm.wait(lambda m: m.get("id") == i and "ok" in m)
        eq((r["ok"], r["kind"]), (False, "cancelled"))
        eq(time.time() - t0 < 5, True, "cancelled promptly")
        # and the write lock was released: the next write runs
        os.remove(os.path.join(d, ".git/hooks/pre-commit"))
        lock = os.path.join(d, ".git", "index.lock")
        if os.path.exists(lock):
            os.remove(lock)   # git killed mid-commit leaves this; git's own rule
        eq(dm.call("commit", d, message="fast")["ok"], True)
    finally:
        dm.close()


@test
def daemon_watch():
    d = fresh({"a": "1\n"})
    dm = Daemon()
    try:
        eq(dm.call("watch", d)["result"]["tree"], True)
        time.sleep(0.3)
        write(d, "a", "2\n")
        ev = dm.wait(lambda m: m.get("event", {}).get("changed") == d)["event"]
        eq("tree" in ev["what"], True)
        sh(d, "add", "a")
        ev = dm.wait(lambda m: m.get("event", {}).get("changed") == d
                     and "index" in m["event"]["what"])
    finally:
        dm.close()


def main():
    want = sys.argv[1] if len(sys.argv) > 1 else ""
    ok = bad = 0
    for t in TESTS:
        if want not in t.__name__:
            continue
        try:
            t()
            print(f"  ok   {t.__name__}")
            ok += 1
        except Exception as e:
            print(f"  FAIL {t.__name__}: {type(e).__name__}: {e}")
            bad += 1
    print(f"delphi core: {ok} passed, {bad} failed")
    shutil.rmtree(TMP, ignore_errors=True)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()

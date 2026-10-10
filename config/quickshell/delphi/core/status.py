# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# WORKING TREE STATUS — `git status --porcelain=v2 -z`, read into lists.
#
# v2 rather than the v1 terminus reads: delphi needs what v1 leaves out — the
# branch header (oid, upstream, ahead/behind), the stash count, submodule
# state, and both halves of a rename. -z because a path may hold a newline;
# under -z git stops quoting and NUL separates everything.
#
# One file can be in two lists: changed in the index AND changed again in the
# working tree since. That is the honest picture — "staged" and "unstaged" are
# the two halves of its XY code, not a property of the file.

import os

KIND = {"M": "modified", "T": "typechange", "A": "added", "D": "deleted",
        "R": "renamed", "C": "copied"}


def parse(raw):
    """raw = the bytes-as-text of `git status --porcelain=v2 -z --branch
    --show-stash`. Returns a dict the protocol sends as is."""
    out = {"branch": {"oid": None, "head": None, "upstream": None,
                      "ahead": 0, "behind": 0},
           "stash": 0, "staged": [], "unstaged": [], "untracked": [],
           "conflicts": [], "ignored": []}
    recs = raw.split("\0")
    i = 0
    while i < len(recs):
        r = recs[i]
        i += 1
        if not r:
            continue
        t = r[0]
        if t == "#":
            _header(out, r)
        elif t == "1":
            # 1 XY sub mH mI mW hH hI path
            f = r.split(" ", 8)
            _entry(out, f[1], f[8], None, f[2], f[3:6])
        elif t == "2":
            # 2 XY sub mH mI mW hH hI Xscore path\0origPath
            f = r.split(" ", 9)
            orig = recs[i] if i < len(recs) else None
            i += 1
            _entry(out, f[1], f[9], orig, f[2], f[3:6])
        elif t == "u":
            # u XY sub m1 m2 m3 mW h1 h2 h3 path
            f = r.split(" ", 10)
            out["conflicts"].append({"path": f[10], "code": f[1],
                                     "how": _conflict(f[1])})
        elif t == "?":
            out["untracked"].append({"path": r[2:]})
        elif t == "!":
            out["ignored"].append({"path": r[2:]})
    return out


def _header(out, r):
    b = out["branch"]
    parts = r.split(" ")
    key = parts[1] if len(parts) > 1 else ""
    val = " ".join(parts[2:])
    if key == "branch.oid":
        b["oid"] = None if val == "(initial)" else val
    elif key == "branch.head":
        b["head"] = None if val == "(detached)" else val
        b["detached"] = val == "(detached)"
    elif key == "branch.upstream":
        b["upstream"] = val
    elif key == "branch.ab":
        a, _, bh = val.partition(" ")
        b["ahead"] = int(a.lstrip("+") or 0)
        b["behind"] = int(bh.lstrip("-") or 0)
    elif key == "stash":
        out["stash"] = int(val or 0)


def _entry(out, xy, path, orig, sub, modes):
    x, y = xy[0], xy[1]
    common = {"path": path}
    if orig:
        common["from"] = orig
    if sub != "N...":
        # S<c><m><u>: commit changed, tracked changes, untracked changes.
        common["submodule"] = {"commit": sub[1] == "C", "modified": sub[2] == "M",
                               "untracked": sub[3] == "U"}
    if x != ".":
        out["staged"].append(dict(common, kind=KIND.get(x, x)))
    if y != ".":
        e = dict(common, kind=KIND.get(y, y))
        # The working-tree half of a staged rename is about the new path only.
        e.pop("from", None)
        out["unstaged"].append(e)


# The seven unmerged codes, in words a person resolving them needs: what each
# side did. "both modified" is the everyday one; the others decide whether
# there even is a file to merge.
CONFLICT = {"DD": "both deleted", "AU": "added by us", "UD": "deleted by them",
            "UA": "added by them", "DU": "deleted by us", "AA": "both added",
            "UU": "both modified"}


def _conflict(xy):
    return CONFLICT.get(xy, xy)


def repo_state(gitdir):
    """What git is in the middle of, read from the files it leaves in the git
    directory — the same test git's own prompt script uses. None when idle."""
    p = lambda *n: os.path.join(gitdir, *n)
    if os.path.isdir(p("rebase-merge")):
        st = {"op": "rebase", "interactive": os.path.exists(p("rebase-merge", "interactive"))}
        st.update(_steps(p("rebase-merge"), "msgnum", "end"))
        st["onto"] = _read(p("rebase-merge", "onto"))
        st["head"] = _read(p("rebase-merge", "head-name"))
        return st
    if os.path.isdir(p("rebase-apply")):
        if os.path.exists(p("rebase-apply", "applying")):
            st = {"op": "am"}
        else:
            st = {"op": "rebase", "interactive": False}
        st.update(_steps(p("rebase-apply"), "next", "last"))
        return st
    if os.path.exists(p("MERGE_HEAD")):
        return {"op": "merge", "theirs": _read(p("MERGE_HEAD"))}
    if os.path.exists(p("CHERRY_PICK_HEAD")):
        return {"op": "cherry-pick", "theirs": _read(p("CHERRY_PICK_HEAD"))}
    if os.path.exists(p("REVERT_HEAD")):
        return {"op": "revert", "theirs": _read(p("REVERT_HEAD"))}
    if os.path.exists(p("BISECT_LOG")):
        return {"op": "bisect"}
    return None


def _steps(d, cur, last):
    try:
        return {"step": int(_read(os.path.join(d, cur)) or 0),
                "steps": int(_read(os.path.join(d, last)) or 0)}
    except ValueError:
        return {}


def _read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read().strip()
    except OSError:
        return None

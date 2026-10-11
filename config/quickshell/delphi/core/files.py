# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# FILES FOR AN UPLOAD — what local paths become, whichever forge they go to
# (github, gitlab, forgejo): a directory opened into its files under its own
# name, caches and what git ignores left out (delphi/core/github.py made it;
# shared since GitLab and Codeberg upload too).

import os
import subprocess


# What a chosen directory never sends: git's own (a .git directory is a
# repository's history, not its files) and the caches tools leave beside
# code. Inside a git work tree its ignore rules are kept as well (_ignored).
SKIP_DIRS = {".git", "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache"}
SKIP_FILES = {".DS_Store", "Thumbs.db"}
SKIP_ENDS = (".pyc", ".pyo")


def _ignored(paths):
    """Which of these files git would ignore, asked of the work tree each one
    is in (none, when they are in none). Never raises: a question git cannot
    answer leaves the file in."""
    out, by_top = set(), {}
    for p in paths:
        by_top.setdefault(os.path.dirname(p), []).append(p)
    tops = {}
    for d in by_top:
        try:
            r = subprocess.run(["git", "-C", d, "rev-parse", "--show-toplevel"],
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                               text=True, timeout=10)
        except (OSError, subprocess.TimeoutExpired):
            continue
        if r.returncode == 0 and r.stdout.strip():
            tops.setdefault(r.stdout.strip(), []).extend(by_top[d])
    for top, ps in tops.items():
        try:
            r = subprocess.run(["git", "-C", top, "check-ignore", "-z", "--stdin"],
                               input="\0".join(ps) + "\0", stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, text=True, timeout=30)
        except (OSError, subprocess.TimeoutExpired):
            continue
        out.update(x for x in r.stdout.split("\0") if x)
    return out


def expand(files, count=False):
    """files: [{local, path}] where a local may be a DIRECTORY — it stands
    for every file under it, each landing at path + its place inside (the
    directory keeps its own name: path is where the directory itself goes).
    Symbolic links to directories are not followed (a loop, or half the
    disk); a link to a file uploads the file's contents. Sockets, devices
    and broken links are left out, as are caches and what git ignores there
    (see SKIP_DIRS). Sorted, so a plan and its upload agree. With `count`, a
    pair: the files, and how many files were left out (a skipped directory
    is passed by, not counted)."""
    out, seen, walked, skipped = [], set(), [], [0]
    for f in files:
        local, path = f["local"], f["path"].strip("/")
        if os.path.isdir(local) and not os.path.islink(local):
            for top, dirs, names in os.walk(local):
                dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
                for n in sorted(names):
                    full = os.path.join(top, n)
                    if not os.path.isfile(full):
                        continue
                    if n in SKIP_FILES or n.endswith(SKIP_ENDS):
                        skipped[0] += 1
                        continue
                    rel = os.path.relpath(full, local).replace(os.sep, "/")
                    dest = path + "/" + rel if path else rel
                    if dest not in seen:
                        seen.add(dest)
                        e = {"local": full, "path": dest}
                        out.append(e)
                        walked.append(e)
        elif os.path.isfile(local):
            if path not in seen:
                seen.add(path)
                out.append({"local": local, "path": path})
    # a file chosen by name goes whatever git thinks; one found in a
    # directory goes only if git would keep it
    if walked:
        drop = _ignored([e["local"] for e in walked])
        if drop:
            found = {id(e) for e in walked}
            kept = [f for f in out if id(f) not in found or f["local"] not in drop]
            skipped[0] += len(out) - len(kept)
            out = kept
    return (out, skipped[0]) if count else out

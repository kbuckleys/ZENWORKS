# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# DOTFILES — a repository of GNU Stow packages, looked at and prepared, never
# stowed. A package is a top-level directory laid out like the target (your
# home): kitty/.config/kitty/kitty.conf links to ~/.config/kitty/kitty.conf.
#
# What this does, and the one thing it never does (user, 2026-10-10, twice:
# stowing is theirs, by hand, as a series of tests):
#
#   packages   each package, and what `stow -n` (stow's own dry run, which
#              touches nothing) says it would do: link, nothing (linked), or
#              refuse over files in the way
#   plan       one package file by file: linked already, to link, in the way
#   copy_in    a file or directory from the target COPIED into a package, at
#              the same place under it — the source is not moved, deleted or
#              linked; that, and stow itself, are the user's to run
#
# Nothing here writes outside the repository.

import os
import re
import shutil
import subprocess

# what a package's copy never takes from a config directory
SKIP = {".git", "__pycache__", ".DS_Store"}

# stow 2.4: "cannot stow X over existing target Y since …"; older stows:
# "existing target is neither a link nor a directory: Y"
_CONFLICT = (re.compile(r"over existing target (.+?) since "),
             re.compile(r"existing target is [^:]*: (.+)$"))


class StowError(Exception):
    pass


def have_stow():
    return shutil.which("stow") is not None


def _rc(root):
    """A .stowrc's --target and --dir (the repository's own; stow reads it
    from the directory it runs in), ~ and $HOME expanded."""
    out = {}
    try:
        with open(os.path.join(root, ".stowrc")) as f:
            words = f.read().split()
    except OSError:
        return out
    for i, w in enumerate(words):
        for key, short in (("target", "-t"), ("dir", "-d")):
            val = None
            if w.startswith(f"--{key}="):
                val = w.split("=", 1)[1]
            elif w in (f"--{key}", short) and i + 1 < len(words):
                val = words[i + 1]
            if val:
                out[key] = os.path.expandvars(os.path.expanduser(val))
    return out


def target_of(root, target=None):
    """Where the packages go: as asked, else the .stowrc's, else home."""
    if target:
        return os.path.abspath(os.path.expanduser(target))
    t = _rc(root).get("target")
    if t:
        return os.path.abspath(os.path.join(root, t))
    return os.path.expanduser("~")


def _files(pkg_dir):
    """A package's files, relative to it (directories walked, SKIP left)."""
    out = []
    for dp, dns, fns in os.walk(pkg_dir):
        dns[:] = sorted(d for d in dns if d not in SKIP)
        for f in sorted(fns):
            if f in SKIP:
                continue
            out.append(os.path.relpath(os.path.join(dp, f), pkg_dir))
    return out


def _dry(root, target, name, cancel=None):
    """stow -n -v for one package: (links, conflicts), each a list of
    target-relative paths. Never stows: -n is stow's simulation."""
    try:
        p = subprocess.run(["stow", "-n", "-v", "-d", root, "-t", target, name],
                           capture_output=True, text=True, timeout=30,
                           stdin=subprocess.DEVNULL)
    except FileNotFoundError:
        raise StowError("stow is not installed")
    except subprocess.TimeoutExpired:
        raise StowError("stow took too long to answer")
    links, conflicts, other = [], [], []
    for line in (p.stdout + "\n" + p.stderr).splitlines():
        s = line.strip()
        if s.startswith("LINK: "):
            links.append(s[6:].split(" => ", 1)[0])
            continue
        for rx in _CONFLICT:
            m = rx.search(s)
            if m:
                conflicts.append(m.group(1))
                break
        else:
            if s and not s.startswith(("WARNING", "MKDIR", "UNLINK", "All operations", "* ")):
                other.append(s)
    if p.returncode != 0 and not conflicts:
        raise StowError("\n".join(other) or f"stow exited {p.returncode}")
    return links, conflicts


def packages(root, target=None, cancel=None):
    target = target_of(root, target)
    rc = _rc(root)
    out = {"target": target, "stowrc": bool(rc), "stow": have_stow(),
           "packages": []}
    if not os.path.isdir(target):
        out["noTarget"] = True
        return out
    for name in sorted(os.listdir(root)):
        d = os.path.join(root, name)
        if name.startswith(".") or name in SKIP or not os.path.isdir(d) or os.path.islink(d):
            continue
        if cancel:
            cancel.check()
        files = _files(d)
        top = os.listdir(d)
        # laid out like a home: something at its top starts with a dot
        dotted = any(e.startswith(".") and e not in SKIP for e in top)
        pk = {"name": name, "files": len(files), "dotted": dotted,
              "links": [], "conflicts": []}
        if not files:
            pk["state"] = "empty"
        elif not out["stow"]:
            pk["state"] = "unknown"
        else:
            try:
                pk["links"], pk["conflicts"] = _dry(root, target, name, cancel)
                pk["state"] = ("conflicts" if pk["conflicts"]
                               else "tolink" if pk["links"] else "linked")
            except StowError as e:
                pk["state"] = "error"
                pk["error"] = str(e)
        out["packages"].append(pk)
    return out


def _linked(src, dst):
    """Whether dst (in the target) is, or resolves through a linked
    directory to, src (in the package)."""
    try:
        return os.path.realpath(dst) == os.path.realpath(src) and os.path.lexists(dst)
    except OSError:
        return False


def plan(root, name, target=None, cancel=None):
    """One package, file by file: each file's path in the target and
    whether it is linked already, to link, or in the way (a file of your
    own where the link would go)."""
    target = target_of(root, target)
    d = os.path.join(root, name)
    if not os.path.isdir(d):
        raise StowError(f"no package {name}")
    conflicts = set()
    if have_stow() and os.path.isdir(target):
        try:
            conflicts = set(_dry(root, target, name, cancel)[1])
        except StowError:
            pass
    rows = []
    for rel in _files(d):
        dst = os.path.join(target, rel)
        if _linked(os.path.join(d, rel), dst):
            st = "linked"
        elif rel in conflicts or any(rel.startswith(c + "/") for c in conflicts) \
                or (os.path.lexists(dst) and not os.path.islink(dst)):
            st = "inTheWay"
        else:
            st = "toLink"
        rows.append({"path": rel, "target": dst, "state": st})
    return {"target": target, "files": rows}


def copy_in(root, src, package, target=None, cancel=None):
    """src (a file or directory in the target) copied into the package at
    the same place under it: ~/.config/kitty → <root>/<package>/.config/kitty.
    Refuses rather than overwrite a package file that differs. The source
    is only read."""
    target = target_of(root, target)
    src = os.path.abspath(os.path.expanduser(src))
    package = package.strip().strip("/")
    if not package or "/" in package or package.startswith(".") or package in SKIP:
        raise StowError("a package is a plain name, like kitty")
    rel = os.path.relpath(src, target)
    if rel.startswith("..") or rel == ".":
        raise StowError(f"{src} is not inside {target}, where the packages go")
    if not os.path.lexists(src):
        raise StowError(f"{src} is not there")
    real_root = os.path.realpath(root)
    if os.path.realpath(src) == real_root or os.path.realpath(src).startswith(real_root + "/"):
        raise StowError("that is in this repository already (stowed, perhaps)")
    if os.path.islink(src):
        raise StowError(f"{src} is a link; copy what it points to instead")
    dest = os.path.join(root, package, rel)
    # every file first, so a refusal leaves nothing half copied
    pairs = []
    if os.path.isdir(src):
        for dp, dns, fns in os.walk(src):
            dns[:] = [x for x in dns if x not in SKIP]
            for f in fns:
                if f in SKIP:
                    continue
                s = os.path.join(dp, f)
                pairs.append((s, os.path.join(dest, os.path.relpath(s, src))))
    else:
        pairs.append((src, dest))
    clash = []
    for s, t in pairs:
        if os.path.lexists(t):
            if os.path.isfile(t) and not os.path.islink(s) and _same(s, t):
                continue
            clash.append(os.path.relpath(t, root))
    if clash:
        raise StowError("the package already has different copies of: "
                        + ", ".join(clash[:6]) + (f" and {len(clash) - 6} more" if len(clash) > 6 else ""))
    n = 0
    for s, t in pairs:
        if cancel:
            cancel.check()
        if os.path.lexists(t):
            continue
        os.makedirs(os.path.dirname(t), exist_ok=True)
        if os.path.islink(s):
            os.symlink(os.readlink(s), t)
        else:
            shutil.copy2(s, t)
        n += 1
    return {"copied": n, "package": package, "into": os.path.join(package, rel)}


def _same(a, b):
    try:
        if os.path.getsize(a) != os.path.getsize(b):
            return False
        with open(a, "rb") as fa, open(b, "rb") as fb:
            return fa.read() == fb.read()
    except OSError:
        return False

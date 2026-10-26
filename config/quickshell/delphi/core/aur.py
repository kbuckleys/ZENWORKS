# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
"""THE AUR — a package's recipe repository (a remote at aur.archlinux.org)
and the package as the AUR shows it.

Not a forge like the others: no pull requests, issues or releases, no
sign-in (a push goes over SSH, as any remote's). What it has is the
package: its version, votes and popularity, and whether it was flagged out
of date — the AUR's RPC, read without an account — beside the recipe in
the checkout, and the steps a release of it takes, one request each:

  aurInfo     the recipe (pkgname, pkgver, pkgrel, .SRCINFO in step) and
              the AUR's word on it
  aurVersion  a new version (pkgrel 1), or the same again (pkgrel + 1)
  aurSums     the source's checksums, fetched (updpkgsums)
  aurSrcinfo  .SRCINFO written from the PKGBUILD
  aurBuild    built from the real source (makepkg, no dependencies
              installed) and checked (namcap)
  aurTag      the source's tags (the PKGBUILD's url=), and whether the
              version is among them: a release of a tag not pushed yet
              fetches the wrong tarball, or none (checked: False when
              url= is not a repository — a home page, often)
  aurFor      the AUR packages among Delphi's repositories made from a
              given repository: what a release of it can be followed by
  aurCommit   the recipe committed (PKGBUILD, .SRCINFO, its local files
              and what is tracked), refused while .SRCINFO is behind;
              committed: false when there was nothing new

The push is delphi's own, as for any repository: it publishes at once.
"""

import json
import os
import re
import shutil
import subprocess
import urllib.parse
import urllib.request

RPC = "https://aur.archlinux.org/rpc/v5/info"
WEB = "https://aur.archlinux.org/packages/"
_VERSION = re.compile(r"^[A-Za-z0-9._+]+$")


class AurError(Exception):
    pass


def _var(text, name):
    m = re.search(r"^" + name + r"=(['\"]?)([^'\"\n]*)\1\s*$", text, re.M)
    return m.group(2) if m else ""


def recipe(root):
    """What the checkout's PKGBUILD says, and whether .SRCINFO says the
    same. Read as text, never run: makepkg --printsrcinfo sources the
    PKGBUILD, and this page opens on any clone of an AUR package — one you
    are reading before you trust it, too. So .SRCINFO is behind when its
    name, version or release differ, or the PKGBUILD changed after it
    (updpkgsums, a hand edit); "Write it" is still makepkg's own."""
    path = os.path.join(root, "PKGBUILD")
    try:
        text = open(path).read()
    except OSError:
        raise AurError("This repository has no PKGBUILD")
    out = {"pkgname": _var(text, "pkgname"), "pkgver": _var(text, "pkgver"),
           "pkgrel": _var(text, "pkgrel"), "srcinfo": "missing"}
    info = os.path.join(root, ".SRCINFO")
    try:
        have = open(info).read()
    except OSError:
        return out
    # a split package's pkgname is a list; its .SRCINFO is under pkgbase
    base = _var(text, "pkgbase") or out["pkgname"]
    said = dict(re.findall(r"^\s*(pkgbase|pkgver|pkgrel)\s*=\s*(.*?)\s*$", have, re.M))
    same = (said.get("pkgver") == out["pkgver"] and said.get("pkgrel") == out["pkgrel"]
            and (not base or base.startswith("(") or said.get("pkgbase") == base))
    try:
        newer = os.path.getmtime(path) > os.path.getmtime(info) + 1
    except OSError:
        newer = False
    out["srcinfo"] = "ok" if same and not newer else "stale"
    return out


def published(pkg):
    """The AUR's word on a package, or None when it has none (not pushed
    yet). Times are seconds since 1970; outOfDate is when it was flagged."""
    q = urllib.parse.urlencode({"arg[]": pkg})
    try:
        with urllib.request.urlopen(RPC + "?" + q, timeout=12) as r:
            data = json.load(r)
    except (OSError, ValueError) as e:
        raise AurError(f"The AUR did not answer: {e}")
    res = data.get("results") or []
    if not res:
        return None
    p = res[0]
    return {"version": p.get("Version", ""), "votes": p.get("NumVotes", 0),
            "popularity": p.get("Popularity", 0), "outOfDate": p.get("OutOfDate"),
            "modified": p.get("LastModified"), "maintainer": p.get("Maintainer") or "",
            "web": WEB + pkg}


def info(root, pkg):
    r = recipe(root)
    name = pkg or r["pkgname"]
    out = {"recipe": r, "pkg": name, "web": WEB + name, "aur": None, "error": "",
           "tools": {t: bool(shutil.which(t)) for t in ("makepkg", "updpkgsums", "namcap")}}
    try:
        out["aur"] = published(name)
    except AurError as e:
        out["error"] = str(e)
    return out


def set_version(root, version):
    """pkgver to `version` with pkgrel 1, or — the same version again —
    pkgrel one up: a change to the recipe alone."""
    v = str(version or "").strip()
    if not _VERSION.match(v):
        raise AurError(f"'{v}' is not a version makepkg takes")
    path = os.path.join(root, "PKGBUILD")
    text = open(path).read()
    old, rel = _var(text, "pkgver"), _var(text, "pkgrel")
    rel = str(int(rel or "0") + 1) if v == old else "1"
    text = re.sub(r"^pkgver=.*$", "pkgver=" + v, text, count=1, flags=re.M)
    text = re.sub(r"^pkgrel=.*$", "pkgrel=" + rel, text, count=1, flags=re.M)
    with open(path, "w") as f:
        f.write(text)
    return {"pkgver": v, "pkgrel": rel}


def _run(argv, root, cancel, tail=40):
    """A tool run in the checkout, stoppable; its last lines kept."""
    p = subprocess.Popen(argv, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                         text=True, start_new_session=True)
    cancel.attach(p)
    lines = []
    try:
        for line in p.stdout:
            lines.append(line.rstrip("\n"))
        p.wait()
    finally:
        cancel.detach(p)
    cancel.check()
    return p.returncode, lines[-tail:]


def sums(root, cancel):
    if not shutil.which("updpkgsums"):
        raise AurError("updpkgsums is missing (pacman-contrib)")
    # always fetched fresh: makepkg reuses a tarball already here, and a
    # forge can serve different bytes for the same tag (a renamed repository
    # renames the directory inside it — zenworks 0.0.7-1 failed its checksum
    # for everyone; release.sh does the same)
    ver = recipe(root).get("pkgver") or ""
    if _VERSION.match(ver):
        for name in os.listdir(root):
            if name.endswith("-" + ver + ".tar.gz") and os.path.isfile(os.path.join(root, name)):
                os.remove(os.path.join(root, name))
    code, said = _run(["updpkgsums"], root, cancel)
    if code != 0:
        raise AurError("The checksums were not updated:\n" + "\n".join(said[-8:]))
    return {}


def srcinfo(root):
    p = subprocess.run(["makepkg", "--printsrcinfo"], cwd=root, capture_output=True, text=True, timeout=60)
    if p.returncode != 0 or not p.stdout.strip():
        raise AurError("makepkg could not read the PKGBUILD:\n" + p.stderr.strip()[-600:])
    with open(os.path.join(root, ".SRCINFO"), "w") as f:
        f.write(p.stdout)
    return {}


def _vkey(tag):
    """A tag's place among versions: 0.10.0 after 0.9.1, "v" ignored."""
    t = tag[1:] if tag[:1] in "vV" else tag
    return [(0, int(x)) if x.isdigit() else (1, x) for x in re.split(r"[._+-]", t)]


def tags(root, version, cancel):
    """The source's tags, newest version first, from the PKGBUILD's url=
    (git ls-remote, no account), and the one `version` is — itself or
    v-prefixed — or "" when it is not there yet. Many a package's url= is
    a home page, not a repository: then checked is False and why says so,
    and the release goes on without the check."""
    url = _var(open(os.path.join(root, "PKGBUILD")).read(), "url")
    out = {"url": url, "tags": [], "tag": "", "checked": False, "why": ""}
    if not re.match(r"^(https?|git|ssh|file)://", url):
        out["why"] = "The PKGBUILD has no url= to check" if not url else url + " is not a repository"
        return out
    p = subprocess.Popen(["git", "ls-remote", "--tags", "--refs", url], cwd=root,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                         start_new_session=True,
                         env=dict(os.environ, GIT_TERMINAL_PROMPT="0", GIT_ASKPASS="", SSH_ASKPASS=""))
    cancel.attach(p)
    try:
        stdout, err = p.communicate(timeout=40)
    except subprocess.TimeoutExpired:
        p.kill()
        stdout, err = "", "it did not answer"
    finally:
        cancel.detach(p)
    cancel.check()
    if p.returncode != 0:
        out["why"] = url + " could not be read as a repository" + (": " + err.strip().splitlines()[-1] if err.strip() else "")
        return out
    names = [l.split("refs/tags/", 1)[1] for l in stdout.splitlines() if "\trefs/tags/" in l]
    names.sort(key=_vkey, reverse=True)
    v = str(version or "").strip()
    out.update(tags=names, checked=True,
               tag=next((t for t in names if v and t in (v, "v" + v)), ""))
    return out


def _norm(url):
    """A repository's address as host/owner/name (repo.remote_key), the
    same however it is written; "" when it is not one."""
    import repo as R
    k = R.remote_key(re.sub(r"^git\+", "", str(url or "")))
    return k[0] + "/" + k[1] if k else ""


def packages_for(roots, urls):
    """The AUR packages, among the checkouts in `roots`, whose recipe is of
    the repository at any of `urls` (its url= or a source= points there):
    [{ root, pkg }] — what a release of that repository can be followed by."""
    want = {_norm(u) for u in urls} - {""}
    out = []
    for root in roots:
        try:
            text = open(os.path.join(root, "PKGBUILD")).read()
        except OSError:
            continue
        try:
            remotes = subprocess.run(["git", "-C", root, "remote", "-v"], capture_output=True,
                                     text=True, timeout=10).stdout
        except (OSError, subprocess.SubprocessError):
            continue
        if "aur.archlinux.org" not in remotes:
            continue
        found = [_norm(f) for f in [_var(text, "url")] + re.findall(r"https?://[^\s'\")]+", text)]
        if any(f and (f in want or any(f.startswith(w + "/") for w in want)) for f in found):
            out.append({"root": root, "pkg": _var(text, "pkgbase") or _var(text, "pkgname")})
    return out


def _local_files(root):
    """What .SRCINFO names that lives in the checkout: source files that
    are not fetched, the install script, the changelog."""
    try:
        text = open(os.path.join(root, ".SRCINFO")).read()
    except OSError:
        return []
    out = []
    for key, val in re.findall(r"^\s*(source(?:_\w+)?|install|changelog)\s*=\s*(.+?)\s*$", text, re.M):
        if "::" in val or "://" in val:
            continue
        if os.path.isfile(os.path.join(root, val)) and val not in out:
            out.append(val)
    return out


def commit(repo, message, cancel):
    """The recipe committed: PKGBUILD, .SRCINFO and the local files it
    names, plus every tracked change. Nothing else new — a clone's
    makepkg leftovers (the tarball, pkg/, src/) stay out. Refused while
    .SRCINFO is behind: the AUR takes no push without one in step."""
    root = repo.root
    state = recipe(root)["srcinfo"]
    if state != "ok":
        raise AurError(".SRCINFO is " + ("missing" if state == "missing" else "behind the PKGBUILD") + " — write it first")
    msg = str(message or "").strip()
    if not msg:
        raise AurError("The commit needs a message")
    repo.git.run(["add", "-u"], cancel=cancel)
    repo.git.run(["add", "--", "PKGBUILD", ".SRCINFO"] + _local_files(root), cancel=cancel)
    # nothing new (committed on Changes already): not an error, the push
    # may still be to come
    if repo.git.code(["diff", "--cached", "--quiet"]) == 0:
        return dict(repo.head(), committed=False)
    return dict(repo.commit(msg, cancel=cancel), committed=True)


# namcap on a package of QML and shell: what it cannot see into it calls
# unneeded, the suite's own python modules uninstalled, and every link
# inside the package it lists; none of it is news
_NOISE = re.compile(r"may not be needed|implicitly satisfied|symlink .* points to|Referenced python module")


def build(root, cancel):
    """Built from the real source, nothing installed for it (-d), then
    namcap on the recipe and the package: { package, notes }."""
    code, said = _run(["makepkg", "-fd", "--noconfirm"], root, cancel)
    if code != 0:
        raise AurError("The build failed:\n" + "\n".join(said[-12:]))
    pkgs = subprocess.run(["makepkg", "--packagelist"], cwd=root, capture_output=True,
                          text=True, timeout=30).stdout.split()
    pkg = pkgs[0] if pkgs else ""
    notes = []
    if shutil.which("namcap"):
        for what in ["PKGBUILD"] + ([pkg] if pkg else []):
            _, out = _run(["namcap", what], root, cancel, tail=400)
            notes += [l for l in out if l.strip() and not _NOISE.search(l)]
    return {"package": os.path.basename(pkg), "notes": notes, "namcap": bool(shutil.which("namcap"))}

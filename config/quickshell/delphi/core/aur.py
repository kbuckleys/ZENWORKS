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

The commit and the push are delphi's own, as for any repository.
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
_REMOTE = re.compile(r"^(?:ssh://)?aur@aur\.archlinux\.org[:/](.+?)(?:\.git)?/?$|"
                     r"^https://aur\.archlinux\.org/(.+?)(?:\.git)?/?$")
_VERSION = re.compile(r"^[A-Za-z0-9._+]+$")


class AurError(Exception):
    pass


def package_of(url):
    """The package a remote URL names, or "" when it is not the AUR's."""
    m = _REMOTE.match(str(url or "").strip())
    return (m.group(1) or m.group(2)) if m else ""


def _var(text, name):
    m = re.search(r"^" + name + r"=(['\"]?)([^'\"\n]*)\1\s*$", text, re.M)
    return m.group(2) if m else ""


def recipe(root):
    """What the checkout's PKGBUILD says, and whether .SRCINFO says the
    same (makepkg reads the PKGBUILD for it, as the AUR will)."""
    path = os.path.join(root, "PKGBUILD")
    try:
        text = open(path).read()
    except OSError:
        raise AurError("This repository has no PKGBUILD")
    out = {"pkgname": _var(text, "pkgname"), "pkgver": _var(text, "pkgver"),
           "pkgrel": _var(text, "pkgrel"), "srcinfo": "missing"}
    try:
        have = open(os.path.join(root, ".SRCINFO")).read()
    except OSError:
        return out
    try:
        want = subprocess.run(["makepkg", "--printsrcinfo"], cwd=root, capture_output=True,
                              text=True, timeout=30).stdout
        out["srcinfo"] = "ok" if want.strip() == have.strip() else "stale"
    except (OSError, subprocess.SubprocessError):
        out["srcinfo"] = "unknown"
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

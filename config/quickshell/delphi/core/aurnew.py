# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
"""A NEW AUR PACKAGE, FROM A REPOSITORY (user, 2026-10-28: "a one-stop
git/aur powerhouse"). Delphi reads a source checkout and says what its
package would be; you correct it; Delphi writes the recipe in a new
repository with its remote on the AUR, and the AUR page (aur.py) takes it
from there: checksums, .SRCINFO, a build, namcap, the first push.

  scan(root)              what the checkout says: { name, version, tags,
                          description, url, license, systems, kinds,
                          depends, makedepends, optdepends, missing, notes }
  resolve(names)          each name a package in the repos, on the AUR, or
                          neither (the AUR's RPC, `pacman -Si` / `-Ssq`)
  available(name)         whether a package name is free on the AUR and
                          in the repos
  write(spec)             the PKGBUILD text for a spec (the scan, corrected)
  create(spec, dest)      a new repository at dest: the PKGBUILD, its
                          remote on the AUR — nothing pushed

Read as files, never run: a build file is only parsed (Cargo.toml,
pyproject.toml, package.json, go.mod, meson.build, CMakeLists.txt,
configure.ac, Makefile), so scanning a repository you do not trust yet
runs none of it. What a manifest cannot say — the libraries a binary
ends up linked to — the first build's namcap says on the AUR page.
"""

import json
import os
import re
import shutil
import subprocess
import urllib.parse
import urllib.request

try:
    import tomllib
except ImportError:     # python < 3.11
    tomllib = None

import aur

RPC_INFO = "https://aur.archlinux.org/rpc/v5/info"
AUR_GIT = "ssh://aur@aur.archlinux.org/{}.git"
# what makepkg takes as a package name
NAME = re.compile(r"^[a-z0-9@_+][a-z0-9@._+-]*$")


class NewError(aur.AurError):
    pass


def _read(root, name, limit=400000):
    try:
        with open(os.path.join(root, name), errors="replace") as f:
            return f.read(limit)
    except OSError:
        return None


def _toml(text):
    if text is None or tomllib is None:
        return {}
    try:
        return tomllib.loads(text)
    except (ValueError, TypeError):
        return {}


# ── THE LICENSE ─────────────────────────────────────────────────────────
# SPDX ids, by words every copy of the license has (the first that fits)
LICENSES = [
    ("AGPL-3.0-or-later", ["GNU AFFERO GENERAL PUBLIC LICENSE", "Version 3"]),
    ("LGPL-3.0-or-later", ["GNU LESSER GENERAL PUBLIC LICENSE", "Version 3"]),
    ("LGPL-2.1-or-later", ["GNU LESSER GENERAL PUBLIC LICENSE", "Version 2.1"]),
    ("GPL-3.0-or-later", ["GNU GENERAL PUBLIC LICENSE", "Version 3"]),
    ("GPL-2.0-or-later", ["GNU GENERAL PUBLIC LICENSE", "Version 2"]),
    ("MPL-2.0", ["Mozilla Public License", "2.0"]),
    ("Apache-2.0", ["Apache License", "Version 2.0"]),
    ("MIT", ["Permission is hereby granted, free of charge"]),
    ("BSD-3-Clause", ["Redistribution and use in source and binary forms", "Neither the name"]),
    ("BSD-2-Clause", ["Redistribution and use in source and binary forms"]),
    ("ISC", ["Permission to use, copy, modify, and/or distribute this software for any purpose"]),
    ("Unlicense", ["This is free and unencumbered software released into the public domain"]),
    ("Zlib", ["This software is provided 'as-is', without any express or implied"]),
]
LICENSE_FILES = ["LICENSE", "LICENSE.md", "LICENSE.txt", "LICENCE", "COPYING", "COPYING.md", "UNLICENSE"]


def license_of(text):
    """the SPDX id a license text is, or "" """
    t = re.sub(r"\s+", " ", text or "")
    for spdx, words in LICENSES:
        if all(w.lower() in t.lower() for w in words):
            return spdx
    return ""


def _spdx_from_manifest(v):
    """a manifest's license field, as written (already SPDX, mostly)"""
    if isinstance(v, dict):
        v = v.get("text") or v.get("file") or ""
    v = str(v or "").strip()
    return v if re.match(r"^[A-Za-z0-9.+-]+( (OR|AND|WITH) [A-Za-z0-9.+-]+)*$", v) else ""


# ── THE NAME OF A DEPENDENCY, AS ARCH NAMES IT ──────────────────────────
# a requirement's name out of "requests>=2; python_version<'3.9'"
def _req_name(r):
    m = re.match(r"^\s*([A-Za-z0-9][A-Za-z0-9._-]*)", str(r))
    return m.group(1) if m else ""


def python_pkg(req):
    """python-<name>, as Arch names a PyPI project: lower case, _ and . as -"""
    n = _req_name(req).lower().replace("_", "-").replace(".", "-")
    return "python-" + n if n else ""


# a build backend → what makepkg needs to run it
BACKENDS = {"setuptools": "python-setuptools", "hatchling": "python-hatchling", "poetry": "python-poetry-core",
            "flit": "python-flit-core", "pdm": "python-pdm-backend", "maturin": "python-maturin",
            "mesonpy": "meson-python", "scikit_build": "python-scikit-build-core", "setuptools_scm": "python-setuptools-scm"}


# ── WHAT THE CHECKOUT IS BUILT WITH ─────────────────────────────────────
def _git(root, args):
    try:
        p = subprocess.run(["git", "-C", root] + args, capture_output=True, text=True, timeout=20,
                           stdin=subprocess.DEVNULL)
        return p.stdout if p.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def _https(url):
    """a remote's address as the page it is on: git@host:o/n.git → https://host/o/n"""
    u = str(url or "").strip()
    m = re.match(r"^(?:ssh://)?git@([^:/]+)[:/](.+?)(?:\.git)?/?$", u)
    if m:
        return "https://" + m.group(1) + "/" + m.group(2)
    m = re.match(r"^(https?://[^\s]+?)(?:\.git)?/?$", u)
    return m.group(1) if m else ""


def _tags(root):
    from aur import _vkey
    names = [t.strip() for t in _git(root, ["tag", "--list"]).splitlines() if t.strip()]
    names = [t for t in names if re.match(r"^[vV]?\d", t)]
    names.sort(key=_vkey, reverse=True)
    return names


def _deps_meson(text):
    return re.findall(r"dependency\(\s*'([^']+)'", text or "")


def _deps_cmake(text):
    t = text or ""
    out = []
    for args in re.findall(r"pkg_(?:check|search)_modules\s*\(([^)]*)\)", t, re.I):
        out += [w for w in args.split()[1:] if not w.isupper() and not w.startswith("$")]
    pkgs = [p for p in re.findall(r"find_package\s*\(\s*([A-Za-z0-9_]+)", t, re.I)
            if p not in ("PkgConfig", "Threads")]
    return [re.sub(r"[<>=].*$", "", d) for d in out], pkgs


def _deps_autotools(text):
    out = []
    for args in re.findall(r"PKG_CHECK_MODULES\s*\(\s*\[?\w+\]?\s*,\s*\[?([^\],)]+)", text or ""):
        out += [w for w in args.split() if re.match(r"^[A-Za-z]", w)]
    return out


# CMake's package names → Arch packages, for the commonest
CMAKE = {"Qt6": "qt6-base", "Qt5": "qt5-base", "KF6": "extra-cmake-modules", "ECM": "extra-cmake-modules",
         "Boost": "boost", "OpenSSL": "openssl", "ZLIB": "zlib", "CURL": "curl", "SDL2": "sdl2",
         "PNG": "libpng", "JPEG": "libjpeg-turbo", "Freetype": "freetype2", "fmt": "fmt", "spdlog": "spdlog",
         "nlohmann_json": "nlohmann-json", "GTest": "gtest", "Vulkan": "vulkan-icd-loader", "OpenGL": "libglvnd",
         "X11": "libx11", "Wayland": "wayland", "PipeWire": "pipewire", "LibArchive": "libarchive",
         "SQLite3": "sqlite", "PkgConfig": "pkgconf", "Python3": "python", "glm": "glm", "Lua": "lua"}


def scan(root):
    """What the checkout at `root` says its package would be. Nothing in it
    is run: build files are read as text."""
    if not os.path.isdir(root):
        raise NewError("That directory is not there")
    out = {"root": root, "name": "", "version": "", "tags": [], "description": "", "url": "", "license": "",
           "systems": [], "arch": "x86_64", "depends": [], "makedepends": [], "optdepends": [],
           "pkgconfig": [], "notes": [], "binary": "", "kinds": ["release", "git"]}
    base = os.path.basename(os.path.abspath(root)).lower()
    deps, make = [], []

    def note(s):
        # shown in a card that reads markup: a name from the repository
        # (a license file's) is text, never a tag
        out["notes"].append(s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))

    cargo = _toml(_read(root, "Cargo.toml"))
    pyproject = _toml(_read(root, "pyproject.toml"))
    pkgjson = None
    try:
        pkgjson = json.loads(_read(root, "package.json") or "null")
    except ValueError:
        pkgjson = None
    gomod = _read(root, "go.mod")
    meson = _read(root, "meson.build")
    cmake = _read(root, "CMakeLists.txt")
    configure = _read(root, "configure.ac") or _read(root, "configure.in")
    makefile = _read(root, "Makefile") or _read(root, "makefile")
    setup_py = _read(root, "setup.py")

    if cargo.get("package") or cargo.get("workspace"):
        p = cargo.get("package") or {}
        out["systems"].append("cargo")
        out["name"] = out["name"] or str(p.get("name") or "")
        out["version"] = out["version"] or (p.get("version") if isinstance(p.get("version"), str) else "")
        out["description"] = out["description"] or str(p.get("description") or "")
        out["url"] = out["url"] or str(p.get("repository") or p.get("homepage") or "")
        out["license"] = out["license"] or _spdx_from_manifest(p.get("license"))
        make.append("cargo")
        deps.append("gcc-libs")
        out["binary"] = str(p.get("name") or "")
        if (cargo.get("workspace") and not cargo.get("package")):
            note("A Cargo workspace: the binary to install is guessed — check package() in the PKGBUILD")
        bins = cargo.get("bin") or []
        if bins and isinstance(bins, list) and isinstance(bins[0], dict) and bins[0].get("name"):
            out["binary"] = str(bins[0]["name"])
    if pyproject.get("project") or pyproject.get("tool", {}).get("poetry") or setup_py is not None:
        p = pyproject.get("project") or pyproject.get("tool", {}).get("poetry") or {}
        out["systems"].append("python")
        out["arch"] = "any" if "cargo" not in out["systems"] else out["arch"]
        out["name"] = out["name"] or str(p.get("name") or "")
        if isinstance(p.get("version"), str):
            out["version"] = out["version"] or p["version"]
        out["description"] = out["description"] or str(p.get("description") or "")
        urls = p.get("urls") or {}
        if isinstance(urls, dict):
            out["url"] = out["url"] or str(urls.get("Repository") or urls.get("Source") or urls.get("Homepage") or "")
        out["url"] = out["url"] or str(p.get("repository") or p.get("homepage") or "")
        out["license"] = out["license"] or _spdx_from_manifest(p.get("license"))
        deps.append("python")
        reqs = p.get("dependencies") or []
        if isinstance(reqs, dict):    # poetry: { name: version }
            reqs = [k for k in reqs if k.lower() != "python"]
        deps += [python_pkg(r) for r in reqs if python_pkg(r)]
        for extra, rs in (p.get("optional-dependencies") or {}).items():
            for r in rs if isinstance(rs, list) else []:
                if python_pkg(r):
                    out["optdepends"].append(python_pkg(r) + ": for " + str(extra))
        make += ["python-build", "python-installer", "python-wheel"]
        backend = str((pyproject.get("build-system") or {}).get("build-backend") or "setuptools")
        for key, pkg in BACKENDS.items():
            if backend.startswith(key) or any(str(r).startswith(key) for r in (pyproject.get("build-system") or {}).get("requires", [])):
                if pkg not in make:
                    make.append(pkg)
        if setup_py is not None and not pyproject:
            make.append("python-setuptools")
            note("Built with setup.py alone: its dependencies are not read — add them by hand")
    if isinstance(pkgjson, dict) and "electron" not in json.dumps(pkgjson.get("devDependencies") or {}):
        out["systems"].append("npm")
        out["arch"] = "any" if len(out["systems"]) == 1 else out["arch"]
        out["name"] = out["name"] or re.sub(r"^@[^/]+/", "", str(pkgjson.get("name") or ""))
        out["version"] = out["version"] or str(pkgjson.get("version") or "")
        out["description"] = out["description"] or str(pkgjson.get("description") or "")
        repo = pkgjson.get("repository")
        out["url"] = out["url"] or _https(repo.get("url") if isinstance(repo, dict) else repo) or str(pkgjson.get("homepage") or "")
        out["license"] = out["license"] or _spdx_from_manifest(pkgjson.get("license"))
        deps.append("nodejs")
        make.append("npm")
        if not pkgjson.get("bin"):
            note("package.json names no bin: it may be a library, not a program")
    elif isinstance(pkgjson, dict):
        note("An Electron app: packaging one is its own work (electron, asar) — the PKGBUILD is a start only")
        out["systems"].append("npm")
        deps.append("electron")
        make.append("npm")
    if gomod is not None:
        out["systems"].append("go")
        m = re.search(r"^module\s+(\S+)", gomod, re.M)
        if m:
            out["name"] = out["name"] or m.group(1).rstrip("/").rsplit("/", 1)[-1]
            if "." in m.group(1).split("/")[0]:
                out["url"] = out["url"] or "https://" + m.group(1)
        make.append("go")
        deps.append("glibc")
    if meson is not None:
        out["systems"].append("meson")
        m = re.search(r"project\(\s*'([^']+)'", meson)
        if m:
            out["name"] = out["name"] or m.group(1)
        m = re.search(r"version\s*:\s*'([^']+)'", meson)
        if m:
            out["version"] = out["version"] or m.group(1)
        m = re.search(r"license\s*:\s*'([^']+)'", meson)
        if m:
            out["license"] = out["license"] or _spdx_from_manifest(m.group(1))
        make.append("meson")
        out["pkgconfig"] += _deps_meson(meson)
    if cmake is not None and "meson" not in out["systems"]:
        out["systems"].append("cmake")
        m = re.search(r"project\s*\(\s*([A-Za-z0-9_.+-]+)", cmake, re.I)
        if m:
            out["name"] = out["name"] or m.group(1)
        m = re.search(r"project\s*\([^)]*VERSION\s+([0-9][0-9.]*)", cmake, re.I)
        if m:
            out["version"] = out["version"] or m.group(1)
        make.append("cmake")
        pcs, pkgs = _deps_cmake(cmake)
        out["pkgconfig"] += pcs
        found = resolve_cmake([p for p in pkgs if p not in CMAKE])
        for p in pkgs:
            if p in CMAKE:
                deps.append(CMAKE[p])
            elif found.get(p):
                deps.append(found[p])
            else:
                note("CMake looks for " + p + " — find its package by hand")
    if configure is not None and not set(out["systems"]) & {"meson", "cmake"}:
        out["systems"].append("autotools")
        m = re.search(r"AC_INIT\(\s*\[?([^\],]+)\]?\s*,\s*\[?([^\],]+)", configure)
        if m:
            out["name"] = out["name"] or m.group(1).strip()
            out["version"] = out["version"] or m.group(2).strip()
        out["pkgconfig"] += _deps_autotools(configure)
        if not os.path.exists(os.path.join(root, "configure")):
            make += ["autoconf", "automake"]
    if makefile is not None and not out["systems"]:
        out["systems"].append("make")
        if "install:" not in makefile:
            note("The Makefile has no install target: package() is a guess — check it")
    if not out["systems"]:
        out["systems"].append("copy")
        out["arch"] = "any"
        note("No build system found: the PKGBUILD copies files — say where they go in package()")

    # what the manifests do not say
    # Arch spells a name with - where a project may have _ (tidy_up → tidy-up)
    out["name"] = re.sub(r"[^a-z0-9@.+-]", "-", (out["name"] or base).lower()).strip("-")
    origin = _https(_git(root, ["remote", "get-url", "origin"]).strip())
    out["url"] = out["url"] or origin
    out["source"] = origin
    out["tags"] = _tags(root)[:12]
    # how the tags are written: v1.2.3 or 1.2.3
    out["tag"] = "v$pkgver" if out["tags"] and out["tags"][0][:1] in "vV" else "$pkgver"
    if not out["version"] and out["tags"]:
        out["version"] = re.sub(r"^[vV]", "", out["tags"][0])
    out["version"] = re.sub(r"[^A-Za-z0-9._+]", ".", out["version"] or "")
    if not out["license"]:
        for f in LICENSE_FILES:
            t = _read(root, f, 20000)
            if t:
                out["license"] = license_of(t)
                if not out["license"]:
                    note(f + " is a license Delphi does not know: give its SPDX id")
                break
        else:
            note("No license file: say what it is under, or LicenseRef-unknown")
    if not out["description"]:
        readme = next((_read(root, n, 4000) for n in ("README.md", "README", "README.rst", "README.txt") if _read(root, n, 1)), "")
        for line in (readme or "").splitlines():
            if line.lstrip().startswith(("#", "!", "[", "<", "=", "-", "|", ">", "```")):
                continue
            s = line.strip().strip("*_ ").strip()
            if s and len(s) > 12 and s.lower() != out["name"]:
                # its first sentence
                out["description"] = re.split(r"(?<=[.!?])\s", s)[0][:120]
                break
    out["description"] = out["description"].rstrip(".")
    if not out["tags"]:
        out["kinds"] = ["git"]
        note("No version tags: a -git package (it builds the latest commit) is the one that works")
    if not origin:
        note("No origin remote: the source address has to be typed")
    # pkg-config names → the packages that ship them
    pc = resolve_pkgconfig(out["pkgconfig"])
    for name, pkg in pc.items():
        if pkg:
            deps.append(pkg)
        else:
            note("Nothing here ships " + name + ".pc — find its package by hand")
    out["depends"] = _uniq(deps)
    out["makedepends"] = [m for m in _uniq(make) if m not in out["depends"]]
    out["optdepends"] = _uniq(out["optdepends"])
    return out


def _uniq(xs):
    seen, out = set(), []
    for x in xs:
        if x and x not in seen:
            seen.add(x)
            out.append(x)
    return out


def _owner(paths):
    """the package that owns the first of `paths` there is: installed
    (pacman -Qo), else in the files database (pacman -F, when synced)"""
    for p in paths:
        if os.path.exists(p):
            r = subprocess.run(["pacman", "-Qqo", p], capture_output=True, text=True, timeout=15)
            if r.returncode == 0 and r.stdout.strip():
                return r.stdout.split()[0]
    if shutil.which("pacman"):
        for p in paths:
            r = subprocess.run(["pacman", "-Fq", p.lstrip("/")], capture_output=True, text=True, timeout=30)
            if r.returncode == 0 and r.stdout.strip():
                return r.stdout.split()[0].split("/")[-1]
    return ""


def resolve_cmake(names):
    """find_package(Name) → the package shipping NameConfig.cmake"""
    out = {}
    for n in _uniq(names):
        if not re.match(r"^[A-Za-z0-9_.+-]+$", n):
            continue
        out[n] = _owner([f"/usr/lib/cmake/{n}/{n}Config.cmake", f"/usr/lib/cmake/{n}/{n.lower()}-config.cmake",
                         f"/usr/lib64/cmake/{n}/{n}Config.cmake", f"/usr/share/cmake/{n}/{n}Config.cmake"])
    return out


def resolve_pkgconfig(names):
    """pkg-config module → the package that ships its .pc: installed first
    (pacman -Qo), then the files database (pacman -F, when synced)"""
    out = {}
    for n in _uniq(names):
        if not re.match(r"^[A-Za-z0-9._+-]+$", n):
            continue
        pkg = ""
        for d in ("/usr/lib/pkgconfig", "/usr/share/pkgconfig"):
            p = os.path.join(d, n + ".pc")
            if os.path.exists(p):
                r = subprocess.run(["pacman", "-Qqo", p], capture_output=True, text=True, timeout=15)
                if r.returncode == 0 and r.stdout.strip():
                    pkg = r.stdout.split()[0]
                    break
        if not pkg and shutil.which("pacman"):
            r = subprocess.run(["pacman", "-Fq", "usr/lib/pkgconfig/" + n + ".pc"], capture_output=True, text=True, timeout=30)
            if r.returncode == 0 and r.stdout.strip():
                pkg = r.stdout.split()[0].split("/")[-1]
        out[n] = pkg
    return out


# ── WHERE EACH NAME IS ──────────────────────────────────────────────────
def _in_repos(names):
    """the names pacman's sync databases have (or provide)"""
    if not names or not shutil.which("pacman"):
        return set()
    have = set()
    r = subprocess.run(["pacman", "-Sql"], capture_output=True, text=True, timeout=30)
    pkgs = set(r.stdout.split()) if r.returncode == 0 else set()
    for n in names:
        if n in pkgs:
            have.add(n)
    # a provide (python-yaml is python-pyyaml's): asked one by one, for the rest
    for n in [n for n in names if n not in have]:
        r = subprocess.run(["pacman", "-Ssq", "^" + re.escape(n) + "$"], capture_output=True, text=True, timeout=15)
        if r.returncode == 0 and r.stdout.strip():
            have.add(n)
    return have


def _on_aur(names):
    if not names:
        return {}
    q = urllib.parse.urlencode([("arg[]", n) for n in names])
    try:
        with urllib.request.urlopen(RPC_INFO + "?" + q, timeout=15) as r:
            data = json.load(r)
    except (OSError, ValueError) as e:
        raise NewError("The AUR did not answer: " + str(e))
    return {p.get("Name"): p for p in data.get("results") or []}


def resolve(names):
    """[{ name, where: "repo" | "aur" | "none" }] — a dependency that is
    nowhere is a name to correct (python-<x> is not always x's package)"""
    names = _uniq([str(n).split(":")[0].split(">")[0].split("<")[0].split("=")[0].strip() for n in names])
    repo = _in_repos(names)
    rest = [n for n in names if n not in repo]
    aurs = _on_aur(rest) if rest else {}
    return [{"name": n, "where": "repo" if n in repo else "aur" if n in aurs else "none"} for n in names]


def available(name):
    """{ free, why }: a name the AUR has is someone's (or yours, to clone);
    one in the repos is refused by the AUR outright"""
    n = str(name or "").strip()
    if not NAME.match(n):
        return {"free": False, "why": "A package name is lower case letters, digits and @ . _ + -"}
    if n in _in_repos([n]):
        return {"free": False, "why": n + " is in the official repositories: the AUR takes no package of that name"}
    found = _on_aur([n])
    if n in found:
        p = found[n]
        who = p.get("Maintainer") or "nobody (orphaned — it can be adopted)"
        return {"free": False, "why": n + " is on the AUR already, kept by " + who, "maintainer": p.get("Maintainer") or ""}
    return {"free": True, "why": ""}


# ── THE PKGBUILD ────────────────────────────────────────────────────────
def _arr(xs):
    return "(" + " ".join("'" + str(x).replace("'", "'\\''") + "'" for x in xs) + ")"


def _darr(xs):
    """an array whose entries name variables ($pkgname, $pkgver): double
    quoted, so makepkg expands them; nothing else of the shell's is let in"""
    return "(" + " ".join('"' + re.sub(r'(["`\\])', r"\\\1", str(x)) + '"' for x in xs) + ")"


def _q(s):
    return "'" + str(s).replace("'", "'\\''") + "'"


def _build_steps(system, binary):
    """prepare/build/check/package for a build system: (functions text)"""
    b = binary or "${pkgname%-git}"
    if system == "cargo":
        return '''prepare() {
  cd "$_src"
  export RUSTUP_TOOLCHAIN=stable
  cargo fetch --locked --target "$(rustc -vV | sed -n 's/host: //p')"
}

build() {
  cd "$_src"
  export RUSTUP_TOOLCHAIN=stable
  export CARGO_TARGET_DIR=target
  cargo build --frozen --release --all-features
}

check() {
  cd "$_src"
  export RUSTUP_TOOLCHAIN=stable
  cargo test --frozen --all-features
}

package() {
  cd "$_src"
  install -Dm0755 -t "$pkgdir/usr/bin/" "target/release/''' + b + '''"
  install -Dm0644 -t "$pkgdir/usr/share/licenses/$pkgname/" LICENSE* 2>/dev/null || true
}
'''
    if system == "python":
        return '''build() {
  cd "$_src"
  python -m build --wheel --no-isolation
}

package() {
  cd "$_src"
  python -m installer --destdir="$pkgdir" dist/*.whl
  install -Dm0644 -t "$pkgdir/usr/share/licenses/$pkgname/" LICENSE* 2>/dev/null || true
}
'''
    if system == "npm":
        return '''package() {
  cd "$_src"
  npm install -g --prefix "$pkgdir/usr" --cache "$srcdir/npm-cache" .
  # npm leaves the build directory's owner and its own references behind
  chown -R root:root "$pkgdir"
  find "$pkgdir/usr/lib/node_modules" -name package.json -exec sed -i '/"_where"/d' {} +
  install -Dm0644 -t "$pkgdir/usr/share/licenses/$pkgname/" LICENSE* 2>/dev/null || true
}
'''
    if system == "go":
        return '''prepare() {
  cd "$_src"
  mkdir -p build
}

build() {
  cd "$_src"
  export CGO_CPPFLAGS="${CPPFLAGS}"
  export CGO_CFLAGS="${CFLAGS}"
  export CGO_CXXFLAGS="${CXXFLAGS}"
  export CGO_LDFLAGS="${LDFLAGS}"
  export GOFLAGS="-buildmode=pie -trimpath -ldflags=-linkmode=external -mod=readonly -modcacherw"
  go build -o build .
}

package() {
  cd "$_src"
  install -Dm0755 -t "$pkgdir/usr/bin/" build/*
  install -Dm0644 -t "$pkgdir/usr/share/licenses/$pkgname/" LICENSE* 2>/dev/null || true
}
'''
    if system == "meson":
        return '''build() {
  arch-meson "$_src" build
  meson compile -C build
}

check() {
  meson test -C build --print-errorlogs
}

package() {
  meson install -C build --destdir "$pkgdir"
}
'''
    if system == "cmake":
        return '''build() {
  cmake -B build -S "$_src" \\
    -DCMAKE_BUILD_TYPE=None \\
    -DCMAKE_INSTALL_PREFIX=/usr \\
    -Wno-dev
  cmake --build build
}

package() {
  DESTDIR="$pkgdir" cmake --install build
}
'''
    if system == "autotools":
        return '''prepare() {
  cd "$_src"
  [ -x configure ] || autoreconf -fi
}

build() {
  cd "$_src"
  ./configure --prefix=/usr
  make
}

package() {
  cd "$_src"
  make DESTDIR="$pkgdir" install
}
'''
    if system == "make":
        return '''build() {
  cd "$_src"
  make
}

package() {
  cd "$_src"
  make DESTDIR="$pkgdir" PREFIX=/usr install
}
'''
    return '''package() {
  cd "$_src"
  # what goes where: the files this package installs
  install -Dm0644 -t "$pkgdir/usr/share/$pkgname/" *
}
'''


def write(spec):
    """The PKGBUILD for a spec: { name, kind ("release" | "git"), version,
    description, url, source, license, arch, depends, makedepends,
    optdepends, system, binary, maintainer }"""
    kind = spec.get("kind") or "release"
    name = str(spec.get("name") or "").strip()
    if kind == "git" and not name.endswith("-git"):
        name += "-git"
    if not NAME.match(name):
        raise NewError("A package name is lower case letters, digits and @ . _ + -")
    src = str(spec.get("source") or spec.get("url") or "").strip()
    if not re.match(r"^(https?|git|ssh)://", src):
        raise NewError("The source needs an address (https://…)")
    # THE ADDRESS GOES INTO A DOUBLE-QUOTED source=, which makepkg runs as
    # shell: a scanned manifest's `https://x/$(…)` would be a command run by
    # anyone who builds it (or makepkg --printsrcinfo). No $ ` " \ or space.
    if re.search(r'[\s"`$\\]', src):
        raise NewError("The source address has characters a recipe cannot hold ($ ` \" \\ or a space)")
    base = name[:-4] if name.endswith("-git") else name
    system = spec.get("system") or "copy"
    make = list(spec.get("makedepends") or [])
    if kind == "git" and "git" not in make:
        make.append("git")
    lines = []
    if spec.get("maintainer"):
        lines.append("# Maintainer: " + str(spec["maintainer"]).replace("\n", " "))
    lines.append("pkgname=" + name)
    if kind == "git":
        lines += ["_pkgname=" + base, "pkgver=0", "pkgrel=1"]
    else:
        ver = str(spec.get("version") or "").strip()
        if not aur._VERSION.match(ver):
            raise NewError("A release needs a version makepkg takes (1.2.3)")
        lines += ["pkgver=" + ver, "pkgrel=1"]
    lines.append('PACKAGER="' + aur.PACKAGER + '"')
    lines += ["pkgdesc=" + _q(spec.get("description") or ""),
              "arch=" + _arr([spec.get("arch") or "x86_64"]),
              "url=" + _q(spec.get("url") or src),
              "license=" + _arr([spec.get("license") or "LicenseRef-unknown"])]
    deps = [d for d in spec.get("depends") or [] if d]
    if deps:
        lines.append("depends=" + _arr(deps))
    if make:
        lines.append("makedepends=" + _arr(make))
    opts = [o for o in spec.get("optdepends") or [] if o]
    if opts:
        lines.append("optdepends=" + _arr(opts))
    if kind == "git":
        lines += ["provides=" + _arr([base]), "conflicts=" + _arr([base])]
        git = re.sub(r"^https?://", "git+https://", src)
        lines += ["source=" + _darr(["$_pkgname::" + git]), "sha256sums=('SKIP')", "_src=\"$_pkgname\"", "",
                  "pkgver() {",
                  "  cd \"$_src\"",
                  "  ( set -o pipefail",
                  "    git describe --long --tags --abbrev=7 2>/dev/null | sed 's/^v//;s/\\([^-]*-g\\)/r\\1/;s/-/./g' ||",
                  "    printf 'r%s.%s' \"$(git rev-list --count HEAD)\" \"$(git rev-parse --short=7 HEAD)\" )",
                  "}"]
    else:
        tag = str(spec.get("tag") or "v$pkgver")
        # the version's own variable, or a plain tag name: nothing else of
        # the shell's in a double-quoted address
        if tag not in ("v$pkgver", "$pkgver") and not re.match(r"^[A-Za-z0-9._+-]+$", tag):
            raise NewError("A tag is letters, digits and . _ + - (or v$pkgver)")
        tarball, inside = _tarball(src, tag)
        lines += ["source=" + _darr(["$pkgname-$pkgver.tar.gz::" + tarball]), "sha256sums=('SKIP')",
                  "# the directory the tarball unpacks to (the first build says if not)",
                  "_src=" + inside]
    lines.append("")
    return "\n".join(lines) + "\n" + _build_steps(system, spec.get("binary") or "")


def _tarball(src, tag):
    """a forge's tarball of a tag (GitHub, GitLab, Codeberg/Forgejo/Gitea),
    and the directory it unpacks to: GitHub drops a tag's leading v,
    GitLab keeps the tag, Gitea's is the repository's name alone"""
    u = src.rstrip("/")
    if u.endswith(".git"):
        u = u[:-4]
    repo = u.rsplit("/", 1)[-1]
    host = urllib.parse.urlparse(u).netloc
    bare = tag[1:] if tag.startswith("v") else tag
    if host == "github.com":
        return u + "/archive/refs/tags/" + tag + ".tar.gz", '"' + repo + "-" + bare + '"'
    if "gitlab" in host:
        return u + "/-/archive/" + tag + "/" + repo + "-" + tag + ".tar.gz", '"' + repo + "-" + tag + '"'
    return u + "/archive/" + tag + ".tar.gz", '"' + repo + '"'


def create(spec, dest):
    """A new repository at dest (made; refused when it holds anything) with
    the PKGBUILD and a remote `aur` at the package's AUR address. Nothing
    is pushed: the AUR page does that, after the checksums and a build."""
    if not spec.get("maintainer"):
        # git's own name for you, as a recipe's first line says it
        who = _git(os.getcwd(), ["config", "--global", "user.name"]).strip()
        mail = _git(os.getcwd(), ["config", "--global", "user.email"]).strip()
        if who:
            spec = dict(spec, maintainer=who + (" <" + mail.replace("@", " at ").replace(".", " dot ") + ">" if mail else ""))
    text = write(spec)
    name = re.search(r"^pkgname=(.+)$", text, re.M).group(1)
    dest = os.path.abspath(os.path.expanduser(str(dest or "")))
    if os.path.exists(dest) and os.listdir(dest):
        raise NewError(dest + " is not empty")
    os.makedirs(dest, exist_ok=True)
    with open(os.path.join(dest, "PKGBUILD"), "w") as f:
        f.write(text)
    for argv in (["init", "-q", "-b", "master"], ["remote", "add", "aur", AUR_GIT.format(name)]):
        p = subprocess.run(["git", "-C", dest] + argv, capture_output=True, text=True, timeout=20)
        if p.returncode != 0:
            raise NewError("git " + argv[0] + " failed: " + p.stderr.strip())
    return {"root": dest, "pkg": name}

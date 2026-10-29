# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# GITHUB — the account, its repositories, and uploading files without a
# clone. Plain HTTPS to api.github.com; nothing beyond the standard library.
#
# WHERE THE TOKEN COMES FROM, in order:
#   1. gh, when it is signed in (`gh auth token`). Signing in is gh's own web
#      flow — login() drives it and hands the one-time code to the window.
#   2. the keyring, through git-credential-libsecret — where a personal
#      access token pasted into delphi is kept (set_token), and where git's
#      own HTTPS pushes find it too.
# The token is held in memory only for as long as a request needs it. It is
# never logged, never put in argv, and never written anywhere but the keyring.
#
# Other forges (GitLab through glab, Forgejo/Codeberg) get a file of their own
# with the same functions; the daemon picks by host.

import base64
import os
import re
import urllib.parse
import subprocess
from concurrent.futures import ThreadPoolExecutor

import rest
import tokenstore
from files import expand   # noqa: F401  (github.expand, the tests')
from rest import ForgeError

API = "https://api.github.com"
HOST = "github.com"


def _gh(*args, input=None, timeout=20):
    try:
        return subprocess.run(["gh"] + list(args), input=input, text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              stdin=None if input is not None else subprocess.DEVNULL,
                              timeout=timeout)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None


def have_gh():
    return _gh("--version") is not None




def token():
    """(token, source) or (None, None)."""
    # a token pasted into delphi wins over gh's sign-in once chosen
    # (tokenstore "_use", set by set_token/switch, cleared by gh's own sign-in
    # or switch) — before, it was kept and never used while gh was signed in
    if tokenstore.prefer(HOST) == "store":
        c = tokenstore.get(HOST)
        if c:
            return c["password"], c["where"]
    r = _gh("auth", "token", "-h", HOST)
    if r is not None and r.returncode == 0 and r.stdout.strip():
        return r.stdout.strip(), "gh"
    # the keyring, or delphi's own file where there is no keyring (tokenstore)
    c = tokenstore.get(HOST)
    if c:
        return c["password"], c["where"]
    return None, None


def status():
    tok, src = token()
    res = {"signedIn": False, "source": src, "gh": have_gh(), "cli": have_gh(), "forge": "github", "host": HOST}
    if not tok:
        return res
    try:
        me = call("GET", "/user", tok=tok)
    except ForgeError as e:
        res["error"] = str(e)
        return res
    res.update(signedIn=True, login=me.get("login"), name=me.get("name"),
               avatar=me.get("avatar_url"), id=me.get("id"),
               # GitHub's private address for commits: theirs, linked to the
               # account, without putting a real one in public history
               noreply=f"{me.get('id')}+{me.get('login')}@users.noreply.github.com")
    return res


def set_token(tok):
    """Check a personal access token against the API, then keep it in the
    keyring under the account it belongs to."""
    me = call("GET", "/user", tok=tok)
    # kept where it will be found again — and said where (tokenstore.add); an
    # account kept before stays, to switch back to, and this one is in use
    where = tokenstore.add(HOST, me["login"], tok)
    return {"login": me["login"], "where": where}


def forget_token():
    tokenstore.drop(HOST)


CODE = re.compile(r"one-time code[^A-Z0-9]*([A-Z0-9]{4}-[A-Z0-9]{4})", re.I)
URL = re.compile(r"https://\S+/login/device\S*")


def login(emit, cancel):
    """gh's web sign-in, without a terminal. gh prints a one-time code and a
    URL and then waits for the browser half; the code and URL go to the
    window, which shows them and opens the page when the user asks. gh also
    sets itself up as git's credential helper for github.com."""
    p = subprocess.Popen(["gh", "auth", "login", "--hostname", HOST, "--web",
                          "--git-protocol", "https", "--skip-ssh-key"],
                         stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, text=True,
                         env=dict(os.environ, BROWSER="true", GH_PROMPT_DISABLED=""),
                         start_new_session=True)
    rest.device_flow(p, cancel, emit, CODE, URL)
    if p.returncode != 0:
        raise ForgeError("sign-in did not finish")
    tokenstore.set_prefer(HOST, "")   # gh's own sign-in is the one in use
    return status()


# ── SEVERAL ACCOUNTS ────────────────────────────────────────────────────
# gh keeps any number of accounts per host, one of them active; delphi lists
# them, switches between them (gh auth switch), and adds one by signing in
# again (gh auth login adds; it does not replace). A token in the keyring is
# one more, shown as such.

ACCOUNT = re.compile(r"account\s+(\S+)")
ACTIVE = re.compile(r"Active account:\s*(true|false)")


def _gh_accounts():
    out, cur = [], None
    r = _gh("auth", "status", "-h", HOST)
    for line in (r.stdout + r.stderr if r is not None else "").splitlines():
        m = ACCOUNT.search(line)
        if m and HOST in line:
            cur = {"login": m.group(1), "source": "gh", "active": False}
            out.append(cur)
            continue
        a = ACTIVE.search(line)
        if a and cur is not None:
            cur["active"] = a.group(1) == "true"
    return out


def _kept(login):
    """Whether `login` is a token kept here (in use or shelved), not gh's."""
    names = [tokenstore.get(HOST).get("username", "")] + tokenstore.shelved(HOST)
    return bool(login) and login.lower() in (n.lower() for n in names if n)


def accounts():
    # gh's and the kept tokens side by side; the one token() uses is active
    store = token()[1] not in (None, "gh")
    out = _gh_accounts()
    if store:
        for a in out:
            a["active"] = False
    # one row per login: the same account in gh and kept here is gh's row,
    # marked in use (and from where) when the kept token is the one used
    rows = {a["login"].lower(): a for a in out}
    for k in tokenstore.accounts(HOST, store):
        same = rows.get(k["login"].lower())
        if same is None:
            out.append(k)
        elif k["active"]:
            same.update(active=True, source=k["source"])
    return {"accounts": out, "many": True}


def switch_account(login):
    if _kept(login) and login.lower() not in (a["login"].lower() for a in _gh_accounts()):
        tokenstore.switch(HOST, login)
        return status()
    r = _gh("auth", "switch", "-h", HOST, "-u", login)
    if r is None or r.returncode != 0:
        raise ForgeError((r.stderr or r.stdout).strip() if r is not None else "gh is not there")
    tokenstore.set_prefer(HOST, "")   # gh's account is the one in use now
    return status()


def logout(login=None):
    # the account named, or the one in use — a kept token is forgotten,
    # a gh account signed out of gh
    if (login and _kept(login) and login.lower() not in (a["login"].lower() for a in _gh_accounts())) \
            or (not login and token()[1] not in (None, "gh")):
        tokenstore.drop(HOST, login)
        return {"ok": True}
    r = _gh("auth", "logout", "-h", HOST, *(["-u", login] if login else []))
    return {"ok": r is not None and r.returncode == 0}




def call(method, path, body=None, tok=None, raw=False, again=False, waited=None):
    if tok is None:
        tok, _ = token()
    if not tok:
        raise ForgeError("not signed in to GitHub", 401)
    url = path if path.startswith("http") else API + path
    return rest.request(method, url, {
        "Authorization": "Bearer " + tok,
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "delphi",
    }, body, raw, again, waited, who="GitHub")


def _paged(path, tok, limit=1000):
    out = []
    url = path + ("&" if "?" in path else "?") + "per_page=100"
    while url and len(out) < limit:
        page, link = call("GET", url, tok=tok, raw=True)
        out += page
        m = re.search(r'<([^>]+)>;\s*rel="next"', link or "")
        url = m.group(1) if m else None
    return out


def repos(cancel=None):
    tok, _ = token()
    rs = _paged("/user/repos?sort=pushed&affiliation=owner,collaborator,organization_member", tok)
    return [{"name": r["name"], "full": r["full_name"], "private": r["private"],
             "fork": r["fork"], "description": r.get("description") or "",
             "https": r["clone_url"], "ssh": r["ssh_url"],
             "branch": r.get("default_branch"), "pushed": r.get("pushed_at"),
             "archived": r.get("archived", False), "empty": r.get("size", 0) == 0}
            for r in rs]


def create(name, private=True, description="", org=None):
    body = {"name": name, "private": private, "description": description,
            "auto_init": False}
    r = call("POST", f"/orgs/{org}/repos" if org else "/user/repos", body)
    return {"full": r["full_name"], "https": r["clone_url"], "ssh": r["ssh_url"],
            "branch": r.get("default_branch") or "main"}


# ── archived: read-only on the forge, kept, and undoable ──────────────
# For a repository no longer kept up but not to be deleted (user,
# 2026-10-14): nothing can be pushed to it, and it says so to visitors.
def archive(full, on=True):
    """Archived (on) or back to normal: GitHub's own flag, both ways."""
    r = call("PATCH", f"/repos/{full}", {"archived": bool(on)})
    return {"archived": r.get("archived", bool(on))}


def branches(full):
    """A repository's branches, the default one first."""
    tok, _ = token()
    info = call("GET", f"/repos/{full}", tok=tok)
    names = [b["name"] for b in _paged(f"/repos/{full}/branches", tok)]
    d = info.get("default_branch")
    if d in names:
        names.remove(d)
        names.insert(0, d)
    return {"default": d, "branches": names}


# An upload's batches (see upload): files a tree request carries at most,
# and their bytes; a text file larger than INLINE_BYTES goes as a blob.
BATCH_FILES = 100
BATCH_BYTES = 2_000_000
INLINE_BYTES = 400_000

def plan(full, files, branch=None):
    """What an upload would do, before it does it: each file's size, where
    it lands, and whether a file is already there (it would be replaced).
    Read from the branch's tree — or, for a branch not made yet, from the
    default branch's, which is what the new one starts as."""
    files, skipped = expand(files, count=True)
    tok, _ = token()
    default = call("GET", f"/repos/{full}", tok=tok).get("default_branch") or "main"
    branch = branch or default
    head = _head_of(full, branch, tok)
    fresh = head is None
    start = head if head is not None else _head_of(full, default, tok)
    there, partial = set(), False
    if start is not None:
        t = call("GET", f"/repos/{full}/git/trees/{start}?recursive=1", tok=tok)
        there = {e["path"] for e in t.get("tree", []) if e.get("type") == "blob"}
        partial = bool(t.get("truncated"))
    out = []
    for f in files:
        path = f["path"].lstrip("/")
        try:
            size = os.path.getsize(f["local"])
        except OSError:
            size = -1
        exists = path in there
        if partial and not exists and len(files) <= 30:
            # a tree too big to list whole: asked one path at a time
            try:
                # quoted: a space was http.client's InvalidURL, which is no
                # ForgeError, and the whole plan failed (audit 2026-10-28d)
                ref = urllib.parse.quote(branch if not fresh else default, safe="")
                call("GET", f"/repos/{full}/contents/{urllib.parse.quote(path, safe='/')}?ref={ref}", tok=tok)
                exists = True
            except ForgeError:
                pass
        out.append({"local": f["local"], "path": path, "size": size, "exists": exists})
    return {"branch": branch, "fresh": fresh, "from": default if fresh else None,
            "empty": start is None, "files": out, "skipped": skipped}


def upload(full, files, message, branch=None, emit=None, cancel=None):
    """Commit files straight to a repository on GitHub — no clone, no git.
    files: [{local, path}] — path is where it lands in the repository.

    Everything goes in ONE commit through the git data API (trees in
    batches on top of the branch's, text inside them and anything else as a
    blob first → a commit → move the branch). A branch that does
    not exist yet is made, starting from the default branch. An empty
    repository has no branch to build on and the data API refuses it, so
    there the first file goes in through the contents API, which can create
    a branch, and the rest follow on top of it."""
    tok, _ = token()
    default = call("GET", f"/repos/{full}", tok=tok).get("default_branch") or "main"
    if branch is None:
        branch = default
    files = expand(files)
    if not files:
        raise ForgeError("nothing to upload — the directories hold no files")
    new_ref = False
    base = _head_of(full, branch, tok)
    if base is None and branch != default:
        base = _head_of(full, default, tok)
        new_ref = base is not None
    if base is None:
        first = files.pop(0)
        with open(first["local"], "rb") as fh:
            first["data"] = fh.read()
        if emit:
            emit({"file": first["path"], "state": "sending"})
        r = call("PUT", f"/repos/{full}/contents/{urllib.parse.quote(first['path'].lstrip('/'), safe='/')}", {
            "message": message, "branch": branch,
            "content": base64.b64encode(first["data"]).decode()}, tok=tok)
        if emit:
            emit({"file": first["path"], "state": "sent"})
        if not files:
            return {"sha": r["commit"]["sha"], "branch": branch}
        base = r["commit"]["sha"]
    tree_base = call("GET", f"/repos/{full}/git/commits/{base}", tok=tok)["tree"]["sha"]
    # THE FILES GO IN BATCHES, each one tree built on the last. A text file
    # rides inside its tree request (GitHub makes the blob from the text
    # itself), so a batch of a hundred is one request, not a hundred: one
    # request a file was 468 chances for a stall to end it all, and ran
    # into GitHub's limit on how fast content may be made. A file that is
    # not text (or is large) is sent as a blob of its own first. Read a
    # batch at a time, not all held at once. Every request here may be
    # sent twice (see call: again).
    waited = (lambda sec: emit({"phase": "waiting", "seconds": sec})) if emit else None
    batches, cur, size = [], [], 0
    for f in files:
        try:
            n = os.path.getsize(f["local"])
        except OSError:
            n = 0
        if cur and (len(cur) >= BATCH_FILES or size + n > BATCH_BYTES):
            batches.append(cur)
            cur, size = [], 0
        cur.append(f)
        size += n
    if cur:
        batches.append(cur)
    tree_sha = tree_base
    for batch in batches:
        if cancel:
            cancel.check()
        entries = []
        for f in batch:
            if emit:
                emit({"file": f["path"], "state": "sending"})
            with open(f["local"], "rb") as fh:
                data = fh.read()
            mode = "100755" if os.access(f["local"], os.X_OK) else "100644"
            text = None
            if len(data) <= INLINE_BYTES and b"\0" not in data:
                try:
                    text = data.decode("utf-8")
                except UnicodeDecodeError:
                    text = None
            if text is not None:
                entries.append({"path": f["path"], "mode": mode, "type": "blob", "content": text})
            else:
                b = call("POST", f"/repos/{full}/git/blobs", {
                    "content": base64.b64encode(data).decode(), "encoding": "base64"},
                    tok=tok, again=True, waited=waited)
                entries.append({"path": f["path"], "mode": mode, "type": "blob", "sha": b["sha"]})
        if cancel:
            cancel.check()
        tree_sha = call("POST", f"/repos/{full}/git/trees",
                        {"base_tree": tree_sha, "tree": entries},
                        tok=tok, again=True, waited=waited)["sha"]
        if emit:
            for f in batch:
                emit({"file": f["path"], "state": "sent"})
    if emit:
        emit({"phase": "committing"})
    # a commit sent twice is two commit objects, the second unused; moving
    # the branch to one place twice is moving it once — both may go again
    c = call("POST", f"/repos/{full}/git/commits",
             {"message": message, "tree": tree_sha, "parents": [base]}, tok=tok, again=True)
    if new_ref:
        call("POST", f"/repos/{full}/git/refs",
             {"ref": f"refs/heads/{branch}", "sha": c["sha"]}, tok=tok)
    else:
        call("PATCH", f"/repos/{full}/git/refs/heads/{branch}", {"sha": c["sha"]}, tok=tok, again=True)
    return {"sha": c["sha"], "branch": branch, "url": c.get("html_url"), "created": new_ref}


def _head_of(full, branch, tok):
    # the commit a branch is on, or None when there is no such branch (or no
    # branch at all: an empty repository answers 409)
    try:
        return call("GET", f"/repos/{full}/git/ref/heads/{branch}", tok=tok)["object"]["sha"]
    except ForgeError as e:
        if e.status in (404, 409):
            return None
        raise


# ── PULL REQUESTS AND ISSUES ────────────────────────────────────────────
# Of one repository (`full`, "owner/name"): listed newest-moved first, one
# opened whole (its words, then everything said on it, in order), and the
# few things done to one — say something, close or reopen, merge. A full
# review (comments on lines of the diff) is not here: that is GitHub's page.

def _who(u):
    return (u or {}).get("login") or ""


def _labels(r):
    return [{"name": l.get("name", ""), "color": "#" + (l.get("color") or "888888")}
            for l in r.get("labels") or []]


def _row(r, pull):
    e = {"number": r["number"], "title": r.get("title") or "",
         "author": _who(r.get("user")), "state": r.get("state"),
         "updated": r.get("updated_at"), "created": r.get("created_at"),
         "comments": r.get("comments", 0), "labels": _labels(r),
         "url": r.get("html_url"), "pull": pull,
         # the description's start, for the list's hover bubble
         "excerpt": re.sub(r"<!--.*?-->", "", r.get("body") or "", flags=re.S).strip()[:600]}
    if pull:
        head, base = r.get("head") or {}, r.get("base") or {}
        e.update(draft=bool(r.get("draft")), merged=bool(r.get("merged_at")),
                 branch=head.get("ref"), base=base.get("ref"),
                 headRepo=(head.get("repo") or {}).get("full_name"),
                 # its newest commit: what its checks are of (CI)
                 sha=head.get("sha") or "")
        if e["merged"]:
            e["state"] = "merged"
    return e


def pulls(full, state="open"):
    tok, _ = token()
    rs = _paged(f"/repos/{full}/pulls?state={state}&sort=updated&direction=desc",
                tok, limit=200 if state == "open" else 100)
    return [_row(r, True) for r in rs]


def issues(full, state="open"):
    # the issues listing carries pull requests too (GitHub's issues are a
    # superset); those are the other page's
    tok, _ = token()
    rs = _paged(f"/repos/{full}/issues?state={state}&sort=updated&direction=desc",
                tok, limit=200 if state == "open" else 100)
    return [_row(r, False) for r in rs if "pull_request" not in r]


def thread(full, number, pull=False):
    """One issue or pull request, whole: its text, then what was said on it,
    oldest first — comments, and for a pull request its reviews (approved,
    changes asked for) among them."""
    tok, _ = token()
    # asked side by side: the four answers are independent, and one after
    # another they take two seconds. A pull request's own two are asked on
    # the chance it is one; for an issue they answer 404, and are dropped.
    def maybe(path, paged=False):
        try:
            return _paged(path, tok) if paged else call("GET", path, tok=tok)
        except ForgeError as e:
            if e.status == 404:
                return None
            raise
    with ThreadPoolExecutor(4) as ex:
        fi = ex.submit(call, "GET", f"/repos/{full}/issues/{number}", None, tok)
        fc = ex.submit(_paged, f"/repos/{full}/issues/{number}/comments", tok)
        fp = ex.submit(maybe, f"/repos/{full}/pulls/{number}")
        fr = ex.submit(maybe, f"/repos/{full}/pulls/{number}/reviews", True)
        i, comments, p, reviews = fi.result(), fc.result(), fp.result(), fr.result()
    pull = "pull_request" in i
    out = _row(i, pull)
    out["body"] = i.get("body") or ""
    said = [{"author": _who(c.get("user")), "body": c.get("body") or "",
             "when": c.get("created_at"), "kind": "comment"}
            for c in comments]
    if pull and p:
        out.update(_row(p, True))
        out["body"] = p.get("body") or out["body"]
        out.update(mergeable=p.get("mergeable"), mergeState=p.get("mergeable_state"),
                   commits=p.get("commits", 0), additions=p.get("additions", 0),
                   deletions=p.get("deletions", 0), files=p.get("changed_files", 0),
                   sameRepo=out.get("headRepo") == full)
        for v in reviews or []:
            if v.get("state") in ("APPROVED", "CHANGES_REQUESTED") or v.get("body"):
                said.append({"author": _who(v.get("user")), "body": v.get("body") or "",
                             "when": v.get("submitted_at"),
                             "kind": {"APPROVED": "approved",
                                      "CHANGES_REQUESTED": "changes"}.get(v.get("state"), "review")})
    said.sort(key=lambda c: c["when"] or "")
    out["said"] = said
    return out


def comment(full, number, body, pull=False):
    c = call("POST", f"/repos/{full}/issues/{number}/comments", {"body": body})
    return {"author": _who(c.get("user")), "body": c.get("body") or "",
            "when": c.get("created_at"), "kind": "comment"}


def set_state(full, number, open, pull=False):
    r = call("PATCH", f"/repos/{full}/issues/{number}",
             {"state": "open" if open else "closed"})
    return {"state": r.get("state")}


def open_issue(full, title, body=""):
    r = call("POST", f"/repos/{full}/issues", {"title": title, "body": body})
    return _row(r, False)


def open_pull(full, head, base, title, body="", draft=False):
    """head: a branch of this repository, or "owner:branch" for one on a
    fork."""
    r = call("POST", f"/repos/{full}/pulls", {"title": title, "body": body,
                                             "head": head, "base": base,
                                             "draft": bool(draft)})
    return _row(r, True)


def merge(full, number, method="merge"):
    r = call("PUT", f"/repos/{full}/pulls/{number}/merge", {"merge_method": method})
    return {"merged": bool(r.get("merged")), "sha": r.get("sha")}


# ── RELEASES ──────────────────────────────────────────────────────────────
# A tag with a title, notes and files attached — what a repository's
# "Releases" lists, newest first. Made here from a tag that may not exist
# yet: GitHub makes it at `target` (a branch or a commit already pushed).
# The notes can be written by GitHub itself from the pull requests merged
# since the previous release (release_notes) — its "Generate release notes".
def _rel(r):
    return {"id": r.get("id"), "tag": r.get("tag_name") or "",
            "name": r.get("name") or r.get("tag_name") or "",
            "body": r.get("body") or "", "draft": bool(r.get("draft")),
            "prerelease": bool(r.get("prerelease")), "author": _who(r.get("author")),
            "when": r.get("published_at") or r.get("created_at"),
            "url": r.get("html_url"), "target": r.get("target_commitish") or "",
            "assets": [{"name": a.get("name"), "size": a.get("size", 0),
                        "downloads": a.get("download_count", 0),
                        "url": a.get("browser_download_url")} for a in r.get("assets") or []],
            "sources": _sources(r)}


# The files GitHub makes of the tag itself — its "Source code (zip)" and
# "(tar.gz)", listed apart from the uploaded ones and in no API's assets.
# The web's archive links, not the API's zipball_url: that one wants a
# token on a private repository, the browser's session opens these. None
# for a draft, whose tag may not be there yet.
def _sources(r):
    page, tag = r.get("html_url") or "", r.get("tag_name") or ""
    if r.get("draft") or not tag or "/releases/" not in page:
        return []
    base = page.split("/releases/")[0] + "/archive/refs/tags/" + urllib.parse.quote(tag, safe="")
    return [rest.source_row(kind, base + "." + kind) for kind in ("zip", "tar.gz")]


def releases(full):
    tok, _ = token()
    return [_rel(r) for r in _paged(f"/repos/{full}/releases", tok, limit=100)]


def release_notes(full, tag, target, previous=None):
    body = {"tag_name": tag, "target_commitish": target}
    if previous:
        body["previous_tag_name"] = previous
    r = call("POST", f"/repos/{full}/releases/generate-notes", body)
    return {"name": r.get("name") or tag, "body": r.get("body") or "", "by": "github"}


def create_release(full, tag, target, name, body="", draft=False, prerelease=False):
    return _rel(call("POST", f"/repos/{full}/releases",
                     {"tag_name": tag, "target_commitish": target, "name": name or tag,
                      "body": body, "draft": bool(draft), "prerelease": bool(prerelease)}))


# ── CI ────────────────────────────────────────────────────────────────────
# A commit's checks: the check runs (GitHub Actions and every app that
# reports that way) and the older commit statuses, as one list (rest.ci_*).
def checks(full, sha):
    tok, _ = token()
    runs = []
    cr = call("GET", f"/repos/{full}/commits/{sha}/check-runs?per_page=100", tok=tok)
    for r in cr.get("check_runs") or []:
        st = r.get("conclusion") if r.get("status") == "completed" else r.get("status")
        # an Actions check run is its job: its log and its re-run are here
        actions = (r.get("app") or {}).get("slug") == "github-actions"
        runs.append({"name": r.get("name") or "", "state": rest.ci_word(st),
                     "url": r.get("html_url") or r.get("details_url") or "",
                     "started": r.get("started_at"), "finished": r.get("completed_at"),
                     "job": r.get("id") if actions else None})
    cs = call("GET", f"/repos/{full}/commits/{sha}/status", tok=tok)
    for s in cs.get("statuses") or []:
        runs.append({"name": s.get("context") or "", "state": rest.ci_word(s.get("state")),
                     "url": s.get("target_url") or "", "started": s.get("created_at"),
                     "finished": s.get("updated_at")})
    return {"sha": sha, "state": rest.ci_sum(runs), "runs": runs}


def checks_many(full, shas):
    return rest.ci_many(checks, full, shas)


def job_log(full, job):
    """an Actions job's log, readable: { lines }"""
    tok, _ = token()
    t = rest.text(f"{API}/repos/{full}/actions/jobs/{int(job)}/logs",
                  {"Authorization": "Bearer " + tok, "Accept": "application/vnd.github+json",
                   "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "delphi"}, who="GitHub")
    return {"lines": rest.log_lines(t)}


def rerun(full, job):
    """the job run again (and what depends on it)"""
    call("POST", f"/repos/{full}/actions/jobs/{int(job)}/rerun", {})
    return {}


# ── THE INBOX: what GitHub has for you (2026-10-28) ────────────────────
def _web_of(subject, full):
    """a notification's subject → its page (the API names its API address)"""
    u = (subject or {}).get("url") or ""
    m = re.search(r"/repos/([^/]+/[^/]+)/(pulls|issues|commits|releases)/([^/]+)$", u)
    if not m:
        return f"https://github.com/{full}", 0
    kind = {"pulls": "pull", "issues": "issues", "commits": "commit", "releases": "releases"}[m.group(2)]
    n = int(m.group(3)) if m.group(3).isdigit() else 0
    if kind == "releases":
        return f"https://github.com/{m.group(1)}/releases", 0
    return f"https://github.com/{m.group(1)}/{kind}/{m.group(3)}", n


def inbox():
    out = []
    for t in call("GET", "/notifications?all=false&per_page=50") or []:
        full = (t.get("repository") or {}).get("full_name") or ""
        sub = t.get("subject") or {}
        web, n = _web_of(sub, full)
        out.append({"id": str(t.get("id")), "title": sub.get("title") or "", "repo": full, "number": n,
                    "kind": {"PullRequest": "pull", "Issue": "issue", "Release": "release", "Commit": "commit",
                             "Discussion": "discussion", "CheckSuite": "ci"}.get(sub.get("type"), "other"),
                    "reason": (t.get("reason") or "").replace("_", " "), "when": t.get("updated_at") or "", "web": web})
    return out


def inbox_done(nid):
    call("PATCH", f"/notifications/threads/{int(nid)}", {})
    return {}


# ── REVIEWS ───────────────────────────────────────────────────────────────
def review(full, number, verdict, body=""):
    """approve, changes (requested) or comment — a pull request's review"""
    event = {"approve": "APPROVE", "changes": "REQUEST_CHANGES", "comment": "COMMENT"}[verdict]
    call("POST", f"/repos/{full}/pulls/{int(number)}/reviews", {"event": event, "body": body or ""})
    return {}


# ── THE REPOSITORY ON GITHUB: ITS SETTINGS, A FORK ───────────────────────
def repo_info(full):
    r = call("GET", f"/repos/{full}")
    return {"full": r["full_name"], "name": r["name"], "description": r.get("description") or "",
            "homepage": r.get("homepage") or "", "private": bool(r.get("private")),
            "default": r.get("default_branch") or "", "topics": r.get("topics") or [],
            "archived": bool(r.get("archived")), "fork": bool(r.get("fork")),
            "parent": (r.get("parent") or {}).get("full_name") or "",
            "web": r.get("html_url") or "", "https": r.get("clone_url") or "", "ssh": r.get("ssh_url") or ""}


def repo_edit(full, changes):
    """what changed of name, description, homepage, private, default, topics"""
    body = {}
    for k, api in (("name", "name"), ("description", "description"), ("homepage", "homepage"),
                   ("private", "private"), ("default", "default_branch")):
        if k in changes:
            body[api] = changes[k]
    if body:
        r = call("PATCH", f"/repos/{full}", body)
        full = r.get("full_name") or full
    if "topics" in changes:
        call("PUT", f"/repos/{full}/topics", {"names": [t.lower() for t in changes["topics"]]})
    return repo_info(full)


def fork(full, org=None):
    r = call("POST", f"/repos/{full}/forks", {"organization": org} if org else {})
    return {"full": r["full_name"], "https": r.get("clone_url") or "", "ssh": r.get("ssh_url") or ""}


# ── A KEY THAT SIGNS ──────────────────────────────────────────────────────
# Registered as a SIGNING key (not one to log in with): commits signed with
# it show as Verified. The token needs the admin:ssh_signing_key scope —
# gh's default sign-in does not ask for it, and GitHub's refusal says so.
def add_signing_key(key, title="delphi"):
    try:
        r = call("POST", "/user/ssh_signing_keys", {"title": title, "key": key})
    except ForgeError as e:
        if e.status == 422 and "already" in str(e).lower():
            return {"added": False, "already": True}
        if e.status in (403, 404):
            raise ForgeError("GitHub refused: the sign-in needs the admin:ssh_signing_key permission — run "
                             "`gh auth refresh -s admin:ssh_signing_key`, or add the key at github.com → Settings → "
                             "SSH and GPG keys → New SSH key (type: Signing Key)", e.status)
        raise
    return {"added": True, "id": r.get("id")}


def update_release(full, id, tag, name, body="", draft=False, prerelease=False):
    return _rel(call("PATCH", f"/repos/{full}/releases/{id}",
                     {"tag_name": tag, "name": name or tag, "body": body,
                      "draft": bool(draft), "prerelease": bool(prerelease)}))


def delete_release(full, id, tag=""):
    call("DELETE", f"/repos/{full}/releases/{id}")
    return {}


# a picture or video for the notes, attached to the release; its address is
# the tag's download, which works once the release is published
def media_upload(full, rel, path):
    tok, _ = token()
    if not tok:
        raise ForgeError("not signed in to GitHub", 401)
    data = rest.read_media(path)
    name = rest.media_name(path, data)
    url = (f"https://uploads.github.com/repos/{full}/releases/{rel['id']}/assets?name="
           + urllib.parse.quote(name, safe=""))
    try:
        rest.request("POST", url, {"Authorization": "Bearer " + tok, "Accept": "application/vnd.github+json",
                                   "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "delphi"},
                     payload=data, ctype=rest.media_type(path), who="GitHub")
    except ForgeError as e:
        # 422: one of that name is attached already — the same content
        if e.status != 422:
            raise
    return (f"https://github.com/{full}/releases/download/"
            f"{urllib.parse.quote(rel['tag'], safe='')}/{urllib.parse.quote(name, safe='')}")


# ── SSH keys for signing in (core/sshkeys.py makes them) ──────────────
# gh's sign-in does not carry the permission by default: asked for once,
# with the exact command (as signing keys are).
def _key_scope(e, verb):
    if e.status in (403, 404):
        raise ForgeError(f"GitHub refused to {verb} your SSH keys: the sign-in needs the admin:public_key permission — "
                         "run `gh auth refresh -s admin:public_key`, or use github.com → Settings → SSH and GPG keys", e.status)
    raise e


def ssh_keys():
    try:
        return [{"id": k["id"], "title": k.get("title") or "", "key": " ".join((k.get("key") or "").split()[:2])}
                for k in _paged("/user/keys", token()[0])]
    except ForgeError as e:
        _key_scope(e, "list")


def add_ssh_key(key, title="delphi"):
    try:
        r = call("POST", "/user/keys", {"title": title, "key": key})
    except ForgeError as e:
        if e.status == 422 and "already" in str(e).lower():
            return {"added": False, "already": True}
        _key_scope(e, "add to")
    return {"added": True, "id": r.get("id")}


def delete_ssh_key(id):
    try:
        call("DELETE", f"/user/keys/{id}")
    except ForgeError as e:
        _key_scope(e, "remove")
    return {}

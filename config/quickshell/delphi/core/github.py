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
import json
import os
import re
import subprocess
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

import rest
from files import SKIP_DIRS, SKIP_FILES, SKIP_ENDS, expand   # noqa: F401  (github.expand, the tests')
from rest import ForgeError

API = "https://api.github.com"
HOST = "github.com"




def _keyring(action, fields):
    return rest.keyring(action, fields)


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
    r = _gh("auth", "token", "-h", HOST)
    if r is not None and r.returncode == 0 and r.stdout.strip():
        return r.stdout.strip(), "gh"
    c = _keyring("fill", {"protocol": "https", "host": HOST})
    if c.get("password"):
        return c["password"], "keyring"
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
    _keyring("approve", {"protocol": "https", "host": HOST,
                         "username": me["login"], "password": tok})
    return {"login": me["login"]}


def forget_token():
    c = _keyring("fill", {"protocol": "https", "host": HOST})
    if c:
        _keyring("reject", {"protocol": "https", "host": HOST,
                            "username": c.get("username", "")})


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
    cancel.attach(p)
    sent = {}
    try:
        for line in p.stdout:
            m, u = CODE.search(line), URL.search(line)
            if m:
                sent["code"] = m.group(1)
            if u:
                sent["url"] = u.group(0)
            if "code" in sent and "url" in sent and not sent.get("done"):
                sent["done"] = True
                emit({"device": {"code": sent["code"], "url": sent["url"]}})
        p.wait()
    finally:
        cancel.detach(p)
    cancel.check()
    if p.returncode != 0:
        raise ForgeError("sign-in did not finish")
    return status()


# ── SEVERAL ACCOUNTS ────────────────────────────────────────────────────
# gh keeps any number of accounts per host, one of them active; delphi lists
# them, switches between them (gh auth switch), and adds one by signing in
# again (gh auth login adds; it does not replace). A token in the keyring is
# one more, shown as such.

ACCOUNT = re.compile(r"account\s+(\S+)")
ACTIVE = re.compile(r"Active account:\s*(true|false)")


def accounts():
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
    if not out:
        c = _keyring("fill", {"protocol": "https", "host": HOST})
        if c.get("username"):
            out.append({"login": c["username"], "source": "keyring", "active": True})
    return {"accounts": out, "many": True}


def switch_account(login):
    r = _gh("auth", "switch", "-h", HOST, "-u", login)
    if r is None or r.returncode != 0:
        raise ForgeError((r.stderr or r.stdout).strip() if r is not None else "gh is not there")
    return status()


def logout(login=None):
    # the account named, or the active one
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
                call("GET", f"/repos/{full}/contents/{path}?ref={branch if not fresh else default}", tok=tok)
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
        r = call("PUT", f"/repos/{full}/contents/{first['path']}", {
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
                 headRepo=(head.get("repo") or {}).get("full_name"))
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

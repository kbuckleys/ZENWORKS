# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# FORGEJO — Codeberg (and any Forgejo or Gitea): github.py's twin, function
# for function, against its API (v1). The account, its repositories,
# uploading files without a clone (one commit: the multi-file contents
# endpoint), pull requests and issues.
#
# THE TOKEN: there is no command-line sign-in to borrow, so it is a token
# made at codeberg.org → Settings → Applications (repository and issue
# access), pasted into delphi and kept in the keyring — where git's HTTPS
# finds it too.

import base64
import os
import re

import rest
import tokenstore
from files import expand
from rest import ForgeError

HOST = "codeberg.org"
API = f"https://{HOST}/api/v1"
# the id the window knows this forge by: "codeberg", or "forgejo@<host>" for
# a server of your own (server.hosted loads a copy of this module per host)
FORGE_ID = "codeberg"
NAME = "Codeberg"


def have_cli():
    return False


def token():
    # the keyring, or delphi's own file where there is no keyring (tokenstore)
    c = tokenstore.get(HOST)
    if c:
        return c["password"], c["where"]
    return None, None


def call(method, path, body=None, tok=None, raw=False, again=False, waited=None, anon=False):
    if tok is None:
        tok, _ = token()
    if not tok and not anon:
        raise ForgeError(f"not signed in to {HOST}", 401)
    url = path if path.startswith("http") else API + path
    h = {"User-Agent": "delphi", "Accept": "application/json"}
    if tok:
        h["Authorization"] = "token " + tok
    return rest.request(method, url, h, body, raw, again, waited, who=NAME)


def _paged(path, tok, limit=1000, anon=False):
    out = []
    url = path + ("&" if "?" in path else "?") + "limit=50"
    while url and len(out) < limit:
        page, link = call("GET", url, tok=tok, raw=True, anon=anon)
        if not page:
            break
        out += page
        m = re.search(r'<([^>]+)>;\s*rel="next"', link or "")
        url = m.group(1) if m else None
    return out


def status():
    tok, src = token()
    res = {"signedIn": False, "source": src, "cli": False, "forge": FORGE_ID, "host": HOST}
    if not tok:
        return res
    try:
        me = call("GET", "/user", tok=tok)
    except ForgeError as e:
        res["error"] = str(e)
        return res
    res.update(signedIn=True, login=me.get("login"), name=me.get("full_name") or me.get("login"),
               avatar=me.get("avatar_url"), id=me.get("id"),
               noreply=f"{me.get('login')}@noreply.{HOST}")
    return res


def set_token(tok):
    me = call("GET", "/user", tok=tok)
    # kept where it will be found again — and said where (tokenstore.add);
    # an account in use before stays, to switch back to
    where = tokenstore.add(HOST, me["login"], tok)
    return {"login": me["login"], "where": where}


def forget_token():
    tokenstore.drop(HOST)


def login(emit, cancel):
    raise ForgeError(f"{NAME} signs in with a token — paste one")


# SEVERAL ACCOUNTS: every token pasted is kept, one in use
# (tokenstore: the others on its shelf, a switch away)
def accounts():
    return {"accounts": tokenstore.accounts(HOST, True), "many": True}


def switch_account(login):
    tokenstore.switch(HOST, login)
    return status()


def logout(login=None):
    tokenstore.drop(HOST, login)
    return {"ok": True}


def repos(cancel=None):
    tok, _ = token()
    rs = _paged("/user/repos", tok, limit=400)
    rs.sort(key=lambda r: r.get("updated_at") or "", reverse=True)
    return [{"name": r["name"], "full": r["full_name"], "private": r.get("private", False),
             "fork": r.get("fork", False), "description": r.get("description") or "",
             "https": r["clone_url"], "ssh": r["ssh_url"], "branch": r.get("default_branch"),
             "pushed": r.get("updated_at"), "archived": r.get("archived", False),
             "empty": bool(r.get("empty"))}
            for r in rs]


def archive(full, on=True):
    """Forgejo's (Codeberg's) archived flag, set by editing the repository."""
    r = call("PATCH", f"/repos/{full}", {"archived": bool(on)})
    return {"archived": r.get("archived", bool(on)) if isinstance(r, dict) else bool(on)}


def create(name, private=True, description="", org=None):
    body = {"name": name, "private": private, "description": description, "auto_init": False}
    r = call("POST", f"/orgs/{org}/repos" if org else "/user/repos", body)
    return {"full": r["full_name"], "https": r["clone_url"], "ssh": r["ssh_url"],
            "branch": r.get("default_branch") or "main"}


def _default(full, tok):
    return call("GET", f"/repos/{full}", tok=tok).get("default_branch") or "main"


def branches(full):
    tok, _ = token()
    d = _default(full, tok)
    names = [b["name"] for b in _paged(f"/repos/{full}/branches", tok)]
    if d in names:
        names.remove(d)
        names.insert(0, d)
    return {"default": d, "branches": names}


def _tree(full, ref, tok):
    """{path: blob sha} of every file on a branch, or None when there is no
    such branch (an empty repository has none)."""
    try:
        head = call("GET", f"/repos/{full}/branches/{ref}", tok=tok)["commit"]["id"]
    except ForgeError as e:
        if e.status in (404, 409):
            return None
        raise
    out, page = {}, 1
    while True:
        t = call("GET", f"/repos/{full}/git/trees/{head}?recursive=true&per_page=10000&page={page}", tok=tok)
        for e in t.get("tree") or []:
            if e.get("type") == "blob":
                out[e["path"]] = e.get("sha")
        if not t.get("truncated"):
            break
        page += 1
    return out


def plan(full, files, branch=None):
    files, skipped = expand(files, count=True)
    tok, _ = token()
    default = _default(full, tok)
    branch = branch or default
    there = _tree(full, branch, tok)
    fresh = there is None
    if fresh:
        there = _tree(full, default, tok)
    empty = there is None
    there = there or {}
    out = []
    for f in files:
        try:
            size = os.path.getsize(f["local"])
        except OSError:
            size = -1
        out.append({"local": f["local"], "path": f["path"], "size": size, "exists": f["path"] in there})
    return {"branch": branch, "fresh": fresh and not empty, "from": default if fresh else None,
            "empty": empty, "files": out, "skipped": skipped}


def upload(full, files, message, branch=None, emit=None, cancel=None):
    """Commit files to a repository on Codeberg — no clone, no git: ONE
    request (the contents endpoint takes every file as one commit). A file
    already there is replaced, which it asks the blob's sha for; a branch
    not made yet starts from the default one."""
    tok, _ = token()
    default = _default(full, tok)
    branch = branch or default
    files = expand(files)
    if not files:
        raise ForgeError("nothing to upload — the directories hold no files")
    there = _tree(full, branch, tok)
    new_branch = None
    if there is None:
        base = _tree(full, default, tok)
        if base is not None:
            new_branch, there = branch, base
    there = there or {}
    ops = []
    for f in files:
        if cancel:
            cancel.check()
        if emit:
            emit({"file": f["path"], "state": "sending"})
        with open(f["local"], "rb") as fh:
            data = fh.read()
        op = {"operation": "update" if f["path"] in there else "create", "path": f["path"],
              "content": base64.b64encode(data).decode()}
        if f["path"] in there:
            op["sha"] = there[f["path"]]
        ops.append(op)
    if emit:
        emit({"phase": "committing"})
    body = {"message": message, "files": ops}
    if new_branch:
        body.update(branch=default, new_branch=new_branch)
    else:
        body["branch"] = branch
    waited = (lambda sec: emit({"phase": "waiting", "seconds": sec})) if emit else None
    r = call("POST", f"/repos/{full}/contents", body, tok=tok, waited=waited)
    if emit:
        for f in files:
            emit({"file": f["path"], "state": "sent"})
    c = (r or {}).get("commit") or {}
    return {"sha": c.get("sha"), "branch": branch, "url": c.get("html_url"), "created": bool(new_branch)}


# ── PULL REQUESTS AND ISSUES ────────────────────────────────────────────

def _who(u):
    return (u or {}).get("login") or ""


def _labels(r):
    return [{"name": l.get("name", ""), "color": "#" + (l.get("color") or "888888").lstrip("#")}
            for l in r.get("labels") or []]


def _row(r, pull):
    e = {"number": r["number"], "title": r.get("title") or "", "author": _who(r.get("user")),
         "state": r.get("state"), "updated": r.get("updated_at"), "created": r.get("created_at"),
         "comments": r.get("comments", 0), "labels": _labels(r), "url": r.get("html_url"),
         "pull": pull,
         "excerpt": re.sub(r"<!--.*?-->", "", r.get("body") or "", flags=re.S).strip()[:600]}
    if pull:
        head, base = r.get("head") or {}, r.get("base") or {}
        e.update(draft=bool(r.get("draft")) or (e["title"].lower().startswith(("wip:", "draft:"))),
                 merged=bool(r.get("merged")), branch=head.get("ref"), base=base.get("ref"),
                 headRepo=(head.get("repo") or {}).get("full_name"))
        if e["merged"]:
            e["state"] = "merged"
    return e


def pulls(full, state="open"):
    # listed through the ISSUES endpoint (type=pulls): the pulls endpoint
    # works out every request's diff stats and took 32 s for forgejo's own
    # list (2026-10-11); this one is a couple of seconds. It knows merged or
    # not, not the branches — those come with the one opened (thread).
    tok, _ = token()
    rs = _paged(f"/repos/{full}/issues?state={state}&type=pulls", tok, limit=100, anon=not tok)
    out = []
    for r in rs:
        e = _row(r, True)
        pr = r.get("pull_request") or {}
        e["merged"] = bool(pr.get("merged"))
        e["draft"] = bool(pr.get("draft")) or e["title"].lower().startswith(("wip:", "draft:"))
        if e["merged"]:
            e["state"] = "merged"
        out.append(e)
    return out


def issues(full, state="open"):
    tok, _ = token()
    rs = _paged(f"/repos/{full}/issues?state={state}&type=issues", tok, limit=100, anon=not tok)
    return [_row(r, False) for r in rs]


def thread(full, number, pull=False):
    tok, _ = token()
    i = call("GET", f"/repos/{full}/issues/{number}", tok=tok, anon=not tok)
    pull = pull or bool(i.get("pull_request"))
    out = _row(i, pull)
    out["body"] = i.get("body") or ""
    said = [{"author": _who(c.get("user")), "body": c.get("body") or "", "when": c.get("created_at"),
             "kind": "comment"}
            for c in _paged(f"/repos/{full}/issues/{number}/comments", tok, anon=not tok)]
    if pull:
        p = call("GET", f"/repos/{full}/pulls/{number}", tok=tok, anon=not tok)
        out.update(_row(p, True))
        out["body"] = p.get("body") or out["body"]
        out.update(mergeable=p.get("mergeable"), mergeState="", commits=0,
                   additions=p.get("additions") or 0, deletions=p.get("deletions") or 0,
                   files=p.get("changed_files") or 0, sameRepo=out.get("headRepo") == full)
        try:
            for v in _paged(f"/repos/{full}/pulls/{number}/reviews", tok, anon=not tok):
                if v.get("state") in ("APPROVED", "REQUEST_CHANGES") or v.get("body"):
                    said.append({"author": _who(v.get("user")), "body": v.get("body") or "",
                                 "when": v.get("submitted_at"),
                                 "kind": {"APPROVED": "approved", "REQUEST_CHANGES": "changes"}.get(v.get("state"), "review")})
        except ForgeError:
            pass
    said.sort(key=lambda c: c["when"] or "")
    out["said"] = said
    return out


def comment(full, number, body, pull=False):
    c = call("POST", f"/repos/{full}/issues/{number}/comments", {"body": body})
    return {"author": _who(c.get("user")), "body": c.get("body") or "", "when": c.get("created_at"),
            "kind": "comment"}


def set_state(full, number, open, pull=False):
    r = call("PATCH", f"/repos/{full}/issues/{number}", {"state": "open" if open else "closed"})
    return {"state": r.get("state")}


def open_issue(full, title, body=""):
    return _row(call("POST", f"/repos/{full}/issues", {"title": title, "body": body}), False)


def open_pull(full, head, base, title, body="", draft=False):
    r = call("POST", f"/repos/{full}/pulls", {"head": head, "base": base,
                                             "title": ("WIP: " + title) if draft else title,
                                             "body": body})
    return _row(r, True)


def merge(full, number, method="merge"):
    call("POST", f"/repos/{full}/pulls/{number}/merge",
         {"Do": {"merge": "merge", "squash": "squash", "rebase": "rebase"}.get(method, "merge")})
    return {"merged": True, "sha": None}


# ── RELEASES ──────────────────────────────────────────────────────────────
# github.py's, on Forgejo's API (the same shape, drafts and pre-releases
# too). It writes no notes itself: release_notes says so, and the window
# writes them from the commits instead.
def _rel(r):
    return {"id": r.get("id"), "tag": r.get("tag_name") or "",
            "name": r.get("name") or r.get("tag_name") or "",
            "body": r.get("body") or "", "draft": bool(r.get("draft")),
            "prerelease": bool(r.get("prerelease")),
            "author": (r.get("author") or {}).get("login") or "",
            "when": r.get("published_at") or r.get("created_at"),
            "url": r.get("html_url"), "target": r.get("target_commitish") or "",
            "assets": [{"name": a.get("name"), "size": a.get("size", 0),
                        "downloads": a.get("download_count", 0),
                        "url": a.get("browser_download_url")} for a in r.get("assets") or []]}


def releases(full):
    tok, _ = token()
    return [_rel(r) for r in _paged(f"/repos/{full}/releases", tok, limit=100, anon=not tok)]


def release_notes(full, tag, target, previous=None):
    return {"name": tag, "body": "", "by": ""}


def create_release(full, tag, target, name, body="", draft=False, prerelease=False):
    return _rel(call("POST", f"/repos/{full}/releases",
                     {"tag_name": tag, "target_commitish": target, "name": name or tag,
                      "body": body, "draft": bool(draft), "prerelease": bool(prerelease)}))


# ── CI ────────────────────────────────────────────────────────────────────
# Forgejo Actions (and Woodpecker, and anything else) report as commit
# statuses: the combined status lists each.
def checks(full, sha):
    tok, _ = token()
    cs = call("GET", f"/repos/{full}/commits/{sha}/status", tok=tok, anon=not tok)
    runs = [{"name": s.get("context") or "", "state": rest.ci_word(s.get("status") or s.get("state")),
             "url": s.get("target_url") or "", "started": s.get("created_at"),
             "finished": s.get("updated_at")} for s in (cs or {}).get("statuses") or []]
    return {"sha": sha, "state": rest.ci_sum(runs), "runs": runs}


def checks_many(full, shas):
    return rest.ci_many(checks, full, shas)


# ── A KEY THAT SIGNS ──────────────────────────────────────────────────────
# Forgejo checks an SSH signature against the keys on the account (and asks
# for the key to be verified once, on the web — said back if so).
def add_signing_key(key, title="delphi"):
    try:
        r = call("POST", "/user/keys", {"title": title, "key": key})
    except ForgeError as e:
        if e.status == 422 and ("exist" in str(e).lower() or "used" in str(e).lower()):
            return {"added": False, "already": True}
        raise
    return {"added": True, "id": r.get("id"), "verify": f"https://{HOST}/user/settings/keys"}


def update_release(full, id, tag, name, body="", draft=False, prerelease=False):
    return _rel(call("PATCH", f"/repos/{full}/releases/{id}",
                     {"tag_name": tag, "name": name or tag, "body": body,
                      "draft": bool(draft), "prerelease": bool(prerelease)}))


def delete_release(full, id, tag=""):
    call("DELETE", f"/repos/{full}/releases/{id}")
    return {}


# ── SSH keys for signing in (core/sshkeys.py makes them) ──────────────
# Forgejo's keys are one kind: a key added for signing signs in as well
def ssh_keys():
    return [{"id": k["id"], "title": k.get("title") or "", "key": " ".join((k.get("key") or "").split()[:2])}
            for k in _paged("/user/keys", token()[0])]


def add_ssh_key(key, title="delphi"):
    try:
        r = call("POST", "/user/keys", {"title": title, "key": key})
    except ForgeError as e:
        if e.status == 422 and ("exist" in str(e).lower() or "used" in str(e).lower()):
            return {"added": False, "already": True}
        raise
    return {"added": True, "id": r.get("id"), "verify": f"https://{HOST}/user/settings/keys"}


def delete_ssh_key(id):
    call("DELETE", f"/user/keys/{id}")
    return {}

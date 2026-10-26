# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# GITLAB — github.py's twin, function for function, against GitLab's API
# (v4): the account, its projects, uploading files without a clone, merge
# requests and issues. The window speaks to every forge the same way; what
# differs is here.
#
# WHERE THE TOKEN COMES FROM, in order:
#   1. glab, when it is signed in (`glab config get token`, else what
#      `glab auth status --show-token` says).
#   2. the keyring — a personal access token pasted into delphi (scope
#      `api`), kept there by set_token; git's HTTPS finds it there too.
#
# GitLab's words, said as github.py's: a project is a repository ("full" is
# its path, group/name); a merge request is a pull request (its iid is the
# number); "opened" is open. An issue and a merge request can share a
# number, so a thread is asked for with `pull`.

import base64
import os
import re
import subprocess
import urllib.parse

import rest
import tokenstore
from files import expand
from rest import ForgeError

HOST = "gitlab.com"
API = f"https://{HOST}/api/v4"
# "gitlab", or "gitlab@<host>" for a server of your own (server.hosted)
FORGE_ID = "gitlab"
NAME = "GitLab"


def _glab(*args, timeout=20, err=subprocess.STDOUT):
    try:
        return subprocess.run(["glab"] + list(args), text=True,
                              stdout=subprocess.PIPE, stderr=err,
                              stdin=subprocess.DEVNULL, timeout=timeout)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None


def have_cli():
    return _glab("--version") is not None


def token():
    """(token, source) or (None, None)."""
    # a token pasted into delphi wins over glab's sign-in once chosen
    # (tokenstore "_use", set by set_token, cleared by login) — before, it was
    # kept and never used while glab was signed in (2026-10-21)
    if tokenstore.prefer(HOST) == "store":
        c = tokenstore.get(HOST)
        if c:
            return c["password"], c["where"]
    # stdout alone: glab's notices (a new version, the keyring) go to stderr,
    # and one merged in read as "no token" — so git was never handed glab's
    # helper and a push to gitlab.com asked for a password (2026-10-21)
    r = _glab("config", "get", "token", "--host", HOST, err=subprocess.DEVNULL)
    if r is not None and r.returncode == 0 and r.stdout.strip() and "\n" not in r.stdout.strip():
        return r.stdout.strip(), "glab"
    r = _glab("auth", "status", "--hostname", HOST, "--show-token")
    if r is not None:
        # "Token: …" or "Token found in configuration file (plaintext): …"
        m = re.search(r"Token(?: found[^:\n]*)?:\s*(\S{12,})", r.stdout)
        if m and "*" not in m.group(1):
            return m.group(1), "glab"
    # the keyring, or delphi's own file where there is no keyring (tokenstore)
    c = tokenstore.get(HOST)
    if c:
        return c["password"], c["where"]
    return None, None


def call(method, path, body=None, tok=None, raw=False, again=False, waited=None, anon=False):
    given = tok is not None
    src = None
    if tok is None:
        tok, src = token()
    if not tok and not anon:
        raise ForgeError("not signed in to GitLab", 401)
    url = path if path.startswith("http") else API + path
    def ask(t):
        h = {"User-Agent": "delphi", "Accept": "application/json"}
        if t:
            # Bearer, which GitLab takes from a personal access token and an
            # OAuth one alike — glab's browser/device sign-in gives the latter,
            # and PRIVATE-TOKEN was answered 401 (2026-10-11)
            h["Authorization"] = "Bearer " + t
        return rest.request(method, url, h, body, raw, again, waited, who=NAME)
    try:
        return ask(tok)
    except ForgeError as e:
        # glab's OAuth token lasts two hours and glab renews it as it runs:
        # once refused, glab is run once (so it renews), and asked again
        if e.status != 401 or given or src != "glab":
            raise
        _glab("api", "user", timeout=30)
        fresh, _ = token()
        if not fresh or fresh == tok:
            raise
        return ask(fresh)


def _paged(path, tok, limit=1000, anon=False):
    out = []
    url = path + ("&" if "?" in path else "?") + "per_page=100"
    while url and len(out) < limit:
        page, link = call("GET", url, tok=tok, raw=True, anon=anon)
        out += page
        m = re.search(r'<([^>]+)>;\s*rel="next"', link or "")
        url = m.group(1) if m else None
    return out


def _pid(full):
    # a project by its path: group/sub/name, encoded as one segment
    return urllib.parse.quote(full, safe="")


def status():
    tok, src = token()
    res = {"signedIn": False, "source": src, "cli": have_cli(), "forge": FORGE_ID, "host": HOST}
    if not tok:
        return res
    try:
        me = call("GET", "/user", tok=tok)
    except ForgeError as e:
        res["error"] = str(e)
        return res
    res.update(signedIn=True, login=me.get("username"), name=me.get("name"),
               avatar=me.get("avatar_url"), id=me.get("id"),
               # GitLab's private address for commits
               noreply=f"{me.get('id')}-{me.get('username')}@users.noreply.{HOST}")
    return res


def set_token(tok):
    me = call("GET", "/user", tok=tok)
    # kept where it will be found again — and said where (tokenstore.put)
    where = tokenstore.put(HOST, me["username"], tok)
    tokenstore.set_prefer(HOST, "store")
    return {"login": me["username"], "where": where}


def forget_token():
    tokenstore.drop(HOST)


CODE = re.compile(r"one-time code:\s*([A-Z0-9-]{6,})", re.I)
URL = re.compile(r"https://\S+/oauth/device\S*")


def login(emit, cancel):
    """glab's sign-in, without a terminal: its DEVICE flow — a one-time code
    and a page to type it at (gitlab.com/oauth/device), handed to the window
    as gh's are, and glab waits until GitLab says yes. Every question glab
    would put to a terminal is answered by a flag here; its first try (the
    browser flow, --web) ended "sign-in did not finish" (2026-10-11).

    Where there is no keyring (tokenstore: no Secret Service) glab would
    fail at the very end, saving the token into one: --insecure-storage
    keeps it in glab's own config file instead, as gh does in its hosts.yml."""
    rest.keyring("fill", {"protocol": "https", "host": HOST})
    a = ["glab", "auth", "login", "--hostname", HOST, "--device",
         "--git-protocol", "https", "--api-protocol", "https",
         "--container-registry-domains", f"{HOST},{HOST}:443,registry.{HOST}"]
    if rest.KEYRING["down"]:
        a.append("--insecure-storage")
    p = subprocess.Popen(a, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, text=True, start_new_session=True,
                         env=dict(os.environ, BROWSER="true", NO_PROMPT="1"))
    said = rest.device_flow(p, cancel, emit, CODE, URL)
    if p.returncode != 0:
        # glab's own last words, not a bare "did not finish"
        why = [l for l in said if l and l not in ("ERROR",)][-2:]
        raise ForgeError("sign-in did not finish" + (": " + " ".join(why) if why else ""))
    tokenstore.set_prefer(HOST, "")   # glab's own sign-in is the one in use
    return status()


# ONE ACCOUNT here: glab keeps one per host, and a token in the keyring is
# one per host too — so there is no second to switch to (accounts says so:
# many is false, and the window does not offer it).
def accounts():
    st = status()
    return {"accounts": [{"login": st["login"], "source": st.get("source"), "active": True}]
            if st.get("signedIn") else [], "many": False}


def switch_account(login):
    raise ForgeError("one account at a time here — sign out, then in as the other")


def logout(login=None):
    # whichever is in use: a pasted token is forgotten, glab signed out — a
    # pasted one used to outlive "sign out" and keep the forge signed in
    if token()[1] not in (None, "glab"):
        tokenstore.drop(HOST)
        return {"ok": True}
    r = _glab("auth", "logout", "--hostname", HOST)
    return {"ok": r is not None and r.returncode == 0}


def repos(cancel=None):
    tok, _ = token()
    ps = _paged("/projects?membership=true&order_by=last_activity_at&sort=desc&simple=false", tok, limit=400)
    return [{"name": p["path"], "full": p["path_with_namespace"],
             "private": p.get("visibility") != "public",
             "fork": bool(p.get("forked_from_project")), "description": p.get("description") or "",
             "https": p["http_url_to_repo"], "ssh": p["ssh_url_to_repo"],
             "branch": p.get("default_branch"), "pushed": p.get("last_activity_at"),
             "archived": p.get("archived", False), "empty": bool(p.get("empty_repo"))}
            for p in ps]


def create(name, private=True, description="", org=None):
    body = {"name": name, "path": name, "visibility": "private" if private else "public",
            "description": description, "initialize_with_readme": False}
    if org:
        body["namespace_path"] = org
    p = call("POST", "/projects", body)
    return {"full": p["path_with_namespace"], "https": p["http_url_to_repo"],
            "ssh": p["ssh_url_to_repo"], "branch": p.get("default_branch") or "main"}


def archive(full, on=True):
    """GitLab's archive / unarchive (the project goes read-only)."""
    p = call("POST", f"/projects/{_pid(full)}/{'archive' if on else 'unarchive'}")
    return {"archived": p.get("archived", bool(on)) if isinstance(p, dict) else bool(on)}


def _default(full, tok):
    return call("GET", f"/projects/{_pid(full)}", tok=tok).get("default_branch") or "main"


def branches(full):
    tok, _ = token()
    d = _default(full, tok)
    try:
        names = [b["name"] for b in _paged(f"/projects/{_pid(full)}/repository/branches", tok)]
    except ForgeError as e:
        if e.status != 404:
            raise
        names = []
    if d in names:
        names.remove(d)
        names.insert(0, d)
    return {"default": d, "branches": names}


def _tree(full, ref, tok):
    """Every file on a branch, or None when there is no such branch (or no
    branch at all: an empty project)."""
    try:
        t = _paged(f"/projects/{_pid(full)}/repository/tree?recursive=true&ref={urllib.parse.quote(ref, safe='')}",
                   tok, limit=100000)
    except ForgeError as e:
        if e.status == 404:
            return None
        raise
    return {e["path"] for e in t if e.get("type") == "blob"}


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
    there = there or set()
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
    """Commit files to a GitLab project — no clone, no git: ONE request
    (GitLab's commits API takes every file as an action of one commit). A
    branch not made yet is started from the default branch; an empty
    project takes its first commit the same way. Each file is said sent as
    it is read; the commit is the request."""
    tok, _ = token()
    default = _default(full, tok)
    branch = branch or default
    files = expand(files)
    if not files:
        raise ForgeError("nothing to upload — the directories hold no files")
    there = _tree(full, branch, tok)
    start = None
    if there is None:
        there = _tree(full, default, tok)
        if there is not None:
            start = default
    there = there or set()
    actions = []
    for f in files:
        if cancel:
            cancel.check()
        if emit:
            emit({"file": f["path"], "state": "sending"})
        with open(f["local"], "rb") as fh:
            data = fh.read()
        actions.append({"action": "update" if f["path"] in there else "create",
                        "file_path": f["path"], "encoding": "base64",
                        "content": base64.b64encode(data).decode(),
                        "execute_filemode": os.access(f["local"], os.X_OK)})
    if emit:
        emit({"phase": "committing"})
    body = {"branch": branch, "commit_message": message, "actions": actions}
    if start:
        body["start_branch"] = start
    waited = (lambda sec: emit({"phase": "waiting", "seconds": sec})) if emit else None
    c = call("POST", f"/projects/{_pid(full)}/repository/commits", body, tok=tok, waited=waited)
    if emit:
        for f in files:
            emit({"file": f["path"], "state": "sent"})
    return {"sha": c.get("id"), "branch": branch, "url": c.get("web_url"), "created": bool(start)}


# ── MERGE REQUESTS AND ISSUES ───────────────────────────────────────────
# Said as github.py says pull requests and issues, so the window draws
# either: number is the iid, state open | closed | merged, and so on.

def _labels(r):
    return [{"name": l if isinstance(l, str) else l.get("name", ""), "color": "#888888"}
            for l in r.get("labels") or []]


def _row(r, pull):
    st = {"opened": "open", "locked": "closed"}.get(r.get("state"), r.get("state"))
    e = {"number": r["iid"], "title": r.get("title") or "",
         "author": (r.get("author") or {}).get("username", ""), "state": st,
         "updated": r.get("updated_at"), "created": r.get("created_at"),
         "comments": r.get("user_notes_count", 0), "labels": _labels(r),
         "url": r.get("web_url"), "pull": pull,
         "excerpt": re.sub(r"<!--.*?-->", "", r.get("description") or "", flags=re.S).strip()[:600]}
    if pull:
        e.update(draft=bool(r.get("draft") or r.get("work_in_progress")), merged=st == "merged",
                 branch=r.get("source_branch"), base=r.get("target_branch"),
                 sha=r.get("sha") or "",
                 sameProject=r.get("source_project_id") == r.get("target_project_id"))
    return e


def _list(full, what, state, pull):
    tok, _ = token()
    q = {"open": "opened", "closed": "all"}.get(state, state)
    rs = _paged(f"/projects/{_pid(full)}/{what}?state={q}&order_by=updated_at&sort=desc",
                tok, limit=100, anon=not tok)
    rows = [_row(r, pull) for r in rs]
    return rows if state == "open" else [r for r in rows if r["state"] != "open"]


def pulls(full, state="open"):
    return _list(full, "merge_requests", state, True)


def issues(full, state="open"):
    return _list(full, "issues", state, False)


def _kind(pull):
    return "merge_requests" if pull else "issues"


def thread(full, number, pull=False):
    tok, _ = token()
    base = f"/projects/{_pid(full)}/{_kind(pull)}/{number}"
    r = call("GET", base, tok=tok, anon=not tok)
    out = _row(r, pull)
    out["body"] = r.get("description") or ""
    # the discussion is for those signed in, even on a public project
    try:
        notes = _paged(base + "/notes?sort=asc&order_by=created_at", tok) if tok else []
    except ForgeError as e:
        if e.status not in (401, 403):
            raise
        notes = []
    out["signInToRead"] = not tok
    out["said"] = [{"author": (n.get("author") or {}).get("username", ""), "body": n.get("body") or "",
                    "when": n.get("created_at"), "kind": "comment"}
                   for n in notes if not n.get("system")]
    if pull:
        ms = r.get("detailed_merge_status") or r.get("merge_status") or ""
        out.update(mergeable=None if ms in ("checking", "unchecked", "") else ms in ("mergeable", "can_be_merged"),
                   mergeState="blocked" if ms in ("not_approved", "ci_must_pass", "discussions_not_resolved", "blocked_status") else ms,
                   commits=0, additions=0, deletions=0,
                   files=int(str(r.get("changes_count") or "0").rstrip("+") or 0),
                   sameRepo=out.get("sameProject", True), headRepo=full if out.get("sameProject", True) else "")
    return out


def comment(full, number, body, pull=False):
    n = call("POST", f"/projects/{_pid(full)}/{_kind(pull)}/{number}/notes", {"body": body})
    return {"author": (n.get("author") or {}).get("username", ""), "body": n.get("body") or "",
            "when": n.get("created_at"), "kind": "comment"}


def set_state(full, number, open, pull=False):
    r = call("PUT", f"/projects/{_pid(full)}/{_kind(pull)}/{number}",
             {"state_event": "reopen" if open else "close"})
    return {"state": "open" if r.get("state") == "opened" else r.get("state")}


def open_issue(full, title, body=""):
    return _row(call("POST", f"/projects/{_pid(full)}/issues", {"title": title, "description": body}), False)


def open_pull(full, head, base, title, body="", draft=False):
    if ":" in head:
        raise ForgeError("a merge request from a fork is opened on GitLab itself")
    r = call("POST", f"/projects/{_pid(full)}/merge_requests",
             {"source_branch": head, "target_branch": base,
              "title": ("Draft: " + title) if draft else title, "description": body})
    return _row(r, True)


def merge(full, number, method="merge"):
    if method == "rebase":
        raise ForgeError("GitLab rebases in its own merge settings — merge or squash here")
    r = call("PUT", f"/projects/{_pid(full)}/merge_requests/{number}/merge",
             {"squash": method == "squash"})
    return {"merged": r.get("state") == "merged", "sha": r.get("merge_commit_sha")}


# ── RELEASES ──────────────────────────────────────────────────────────────
# github.py's, on GitLab's API. GitLab has no drafts or pre-releases (an
# "upcoming" release is one dated ahead), and its own notes need a
# changelog set up in the project: release_notes says none, and the window
# writes them from the commits instead.
def _rel(r):
    links = (r.get("assets") or {}).get("links") or []
    return {"id": r.get("tag_name"), "tag": r.get("tag_name") or "",
            "name": r.get("name") or r.get("tag_name") or "",
            "body": r.get("description") or "", "draft": False,
            "prerelease": bool(r.get("upcoming_release")),
            "author": (r.get("author") or {}).get("username") or "",
            "when": r.get("released_at") or r.get("created_at"),
            "url": ((r.get("_links") or {}).get("self")) or "",
            "target": (r.get("commit") or {}).get("id") or "",
            "assets": [{"name": a.get("name"), "size": 0, "downloads": -1, "url": a.get("url")} for a in links]}


def releases(full):
    tok, _ = token()
    return [_rel(r) for r in _paged(f"/projects/{_pid(full)}/releases", tok, limit=100, anon=not tok)]


def release_notes(full, tag, target, previous=None):
    return {"name": tag, "body": "", "by": ""}


def create_release(full, tag, target, name, body="", draft=False, prerelease=False):
    if draft:
        raise ForgeError("GitLab has no draft releases — publish it, or keep the notes for later")
    return _rel(call("POST", f"/projects/{_pid(full)}/releases",
                     {"tag_name": tag, "ref": target, "name": name or tag, "description": body}))


# ── CI ────────────────────────────────────────────────────────────────────
# A commit's pipeline jobs, as GitLab reports them on the commit (its
# statuses: one per job, external ones too).
def checks(full, sha):
    tok, _ = token()
    rs = call("GET", f"/projects/{_pid(full)}/repository/commits/{sha}/statuses?per_page=100", tok=tok, anon=not tok)
    # a job retried reports again: the newest of each name is what stands
    seen, runs = set(), []
    for s in sorted(rs or [], key=lambda x: x.get("id") or 0, reverse=True):
        key = (s.get("name"), s.get("stage"))
        if key in seen:
            continue
        seen.add(key)
        runs.append({"name": (s.get("stage") + ": " if s.get("stage") else "") + (s.get("name") or ""),
                     "state": "neutral" if s.get("allow_failure") and s.get("status") == "failed" else rest.ci_word(s.get("status")),
                     "url": s.get("target_url") or "", "started": s.get("started_at"),
                     "finished": s.get("finished_at")})
    return {"sha": sha, "state": rest.ci_sum(runs), "runs": list(reversed(runs))}


def checks_many(full, shas):
    return rest.ci_many(checks, full, shas)


# ── A KEY THAT SIGNS ──────────────────────────────────────────────────────
# GitLab keeps one list of SSH keys, each for logging in, signing or both:
# this one is for signing only.
def add_signing_key(key, title="delphi"):
    try:
        r = call("POST", "/user/keys", {"title": title, "key": key, "usage_type": "signing"})
    except ForgeError as e:
        if e.status in (400, 422) and "taken" in str(e).lower():
            return {"added": False, "already": True}
        raise
    return {"added": True, "id": r.get("id")}


def update_release(full, id, tag, name, body="", draft=False, prerelease=False):
    # GitLab knows a release by its tag; the tag itself cannot be changed
    t = urllib.parse.quote(tag or id, safe="")
    return _rel(call("PUT", f"/projects/{_pid(full)}/releases/{t}", {"name": name or tag, "description": body}))


def delete_release(full, id, tag=""):
    call("DELETE", f"/projects/{_pid(full)}/releases/{urllib.parse.quote(tag or id, safe='')}")
    return {}


# a picture or video for the notes: a project upload, GitLab's own way (a
# release's files are links to elsewhere)
def media_upload(full, rel, path):
    tok, _ = token()
    if not tok:
        raise ForgeError("not signed in to GitLab", 401)
    data = rest.read_media(path)
    form, ctype = rest.multipart("file", rest.media_name(path, data), data, rest.media_type(path))
    r = rest.request("POST", f"{API}/projects/{_pid(full)}/uploads",
                     {"User-Agent": "delphi", "Accept": "application/json", "Authorization": "Bearer " + tok},
                     payload=form, ctype=ctype, who=NAME) or {}
    where = r.get("full_path") or f"/{full}{r.get('url') or ''}"
    return f"https://{HOST}{where}"


# ── SSH keys for signing in (core/sshkeys.py makes them) ──────────────
def ssh_keys():
    return [{"id": k["id"], "title": k.get("title") or "", "key": " ".join((k.get("key") or "").split()[:2]),
             "usage": k.get("usage_type") or "auth_and_signing"}
            for k in _paged("/user/keys", token()[0])]


def add_ssh_key(key, title="delphi"):
    try:
        r = call("POST", "/user/keys", {"title": title, "key": key, "usage_type": "auth"})
    except ForgeError as e:
        if e.status in (400, 422) and "taken" in str(e).lower():
            return {"added": False, "already": True}
        raise
    return {"added": True, "id": r.get("id")}


def delete_ssh_key(id):
    call("DELETE", f"/user/keys/{id}")
    return {}

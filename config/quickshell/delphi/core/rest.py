# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# REST — what every forge module asks the network and the keyring with:
# one request with its patience and its retries, a forge's error, and the
# keyring entry a pasted token is kept in. Lifted out of github.py when
# GitLab and Codeberg came (2026-10-11); each forge passes its own address,
# headers and name.

import json
import os
import re
import subprocess
import time
import urllib.error
import urllib.request


class ForgeError(Exception):
    def __init__(self, msg, status=None):
        super().__init__(msg)
        self.status = status


def device_flow(p, cancel, emit, code, url):
    """A forge CLI's device sign-in, read as it prints (gh, glab): the
    one-time code and the page it is typed into go to the window once both
    have been seen. Returns every line said, for an error that needs one."""
    sent, said = {}, []
    cancel.attach(p)
    try:
        for line in p.stdout:
            said.append(line.strip())
            m, u = code.search(line), url.search(line)
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
    return said


def keyring(action, fields):
    # Only the keyring helper, whatever else the user has configured: this is
    # delphi's own store, asked directly. Prompts are switched off, so a miss
    # is an empty answer, never a question. A keyring that is not there (no
    # Secret Service running — the helper says "not activatable") is noted in
    # KEYRING["down"], so tokenstore.py stores elsewhere instead of believing
    # a store that did nothing (2026-10-11).
    body = "".join(f"{k}={v}\n" for k, v in fields.items()) + "\n"
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0", GIT_ASKPASS="/bin/false",
               SSH_ASKPASS="/bin/false")
    try:
        r = subprocess.run(["git", "-c", "credential.helper=",
                            "-c", "credential.helper=libsecret",
                            "credential", action], input=body, text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           env=env, timeout=20)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        KEYRING["down"] = True
        return {}
    KEYRING["down"] = bool(re.search(r"(store|lookup|erase) failed|not activatable|ServiceUnknown", r.stderr or ""))
    if r.returncode != 0:
        return {}
    return dict(l.split("=", 1) for l in r.stdout.splitlines() if "=" in l)


KEYRING = {"down": False}


def _hidden(text, headers):
    """A forge's message with the request's own secret blanked out — Codeberg
    answers a wrong token by quoting it ("task with token \"…\""), and the
    message goes on a card (2026-10-11). Whatever the token is called, it is
    a header's value, or the part after "Bearer " / "token "."""
    t = str(text or "")
    for v in (headers or {}).values():
        sv = str(v)
        for secret in (sv, sv.split(" ", 1)[-1]):
            if len(secret) >= 8 and secret in t:
                t = t.replace(secret, "…")
    return t


def request(method, url, headers, body=None, raw=False, again=False, waited=None, who="the forge"):
    """One request. `again`: a write that may be sent twice —
    one whose second sending makes nothing new (a blob or a tree is named by
    its content: the same one twice is the same one). `waited(seconds)` is
    told when GitHub asks for a pause and it is kept."""
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers=dict(headers))
    if data is not None:
        req.add_header("Content-Type", "application/json")
    # A READ IS TRIED AGAIN when the network failed it — a connection that
    # hung (seen right after signing in, 2026-10-10: "timed out", and the
    # same call took 0.7 s a minute later) or one refused — and so is a write
    # marked `again`. Any other write is not: it may have landed, and doing
    # it twice could make two of something. A stall is given up on early
    # and tried again — answers come in half a second, and a stalled one
    # (2026-10-11: one in a dozen) only ever stalls; the patience grows with
    # each try.
    #
    # GITHUB'S "SLOW DOWN" (403 or 429 with Retry-After, or its secondary
    # rate limit: content made too fast) is waited out as long as it says,
    # a few times, for any request that may be sent again — a 468-file upload
    # stopped on a timeout at file 341 (2026-10-11).
    safe = method == "GET" or again
    waits = (6, 10, 20, 30) if safe else (20,)
    tries, pauses = len(waits), 0
    n = 0
    while True:
        try:
            with urllib.request.urlopen(req, timeout=waits[min(n, tries - 1)]) as r:
                txt = r.read().decode()
                link = r.headers.get("Link", "")
            break
        except urllib.error.HTTPError as e:
            try:
                j = json.loads(e.read().decode())
                msg = j.get("message", "") if isinstance(j, dict) else ""
                # GitLab says it in "message" or "error", sometimes as a list
                if isinstance(j, dict) and not msg:
                    msg = j.get("error", "") or ""
                if isinstance(msg, (list, dict)):
                    msg = json.dumps(msg)
            except Exception:
                msg = ""
            after = e.headers.get("Retry-After") if e.headers else None
            slow = e.code == 429 or (e.code == 403 and (after or "rate limit" in msg.lower()))
            if slow and safe and pauses < 4:
                pauses += 1
                pause = min(120, int(after) if after and after.isdigit() else 60)
                if waited:
                    waited(pause)
                time.sleep(pause)
                continue
            raise ForgeError(_hidden(msg, headers) or f"{who} answered {e.code}", e.code)
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            n += 1
            if n < tries:
                time.sleep(0.5 * n)
                continue
            why = getattr(e, "reason", None) or e
            raise ForgeError(f"cannot reach {who}: {why}")
    val = json.loads(txt) if txt else None
    return (val, link) if raw else val


# ── CI: WHAT A FORGE'S CHECKS SAY OF A COMMIT ─────────────────────────────
# GitHub's check runs and statuses, GitLab's job statuses, Forgejo's commit
# statuses — each forge's words for how a check went, said one way here:
# pending, success, failure, or neutral (skipped, canceled by a newer run's
# rule, nothing to say). A commit's state is its worst check's: any failure
# fails it, else any still running keeps it pending; none at all is "none".
_CI = {"success": "success", "passed": "success", "completed": "success",
       "failure": "failure", "failed": "failure", "error": "failure",
       "timed_out": "failure", "action_required": "failure", "startup_failure": "failure",
       "pending": "pending", "queued": "pending", "in_progress": "pending",
       "running": "pending", "created": "pending", "waiting": "pending",
       "preparing": "pending", "scheduled": "pending", "requested": "pending",
       "waiting_for_resource": "pending", "manual": "neutral",
       "skipped": "neutral", "neutral": "neutral", "cancelled": "neutral",
       "canceled": "neutral", "stale": "neutral", "warning": "success"}


def ci_word(s):
    return _CI.get(str(s or "").lower(), "neutral")


def ci_sum(runs):
    st = [r["state"] for r in runs]
    if not st:
        return "none"
    if "failure" in st:
        return "failure"
    if "pending" in st:
        return "pending"
    return "success" if "success" in st else "neutral"


def ci_many(fn, full, shas, limit=40):
    """fn(full, sha) for each of the first `limit` commits, a few at once:
    {sha: answer}; one that fails says nothing rather than failing the rest."""
    from concurrent.futures import ThreadPoolExecutor
    out = {}
    def one(sha):
        try:
            out[sha] = fn(full, sha)
        except Exception:
            pass
    with ThreadPoolExecutor(max_workers=6) as ex:
        list(ex.map(one, list(shas)[:limit]))
    return out

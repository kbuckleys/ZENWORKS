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
import subprocess
import time
import urllib.error
import urllib.request


class ForgeError(Exception):
    def __init__(self, msg, status=None):
        super().__init__(msg)
        self.status = status


def keyring(action, fields):
    # Only the keyring helper, whatever else the user has configured: this is
    # delphi's own store, asked directly. Prompts are switched off, so a miss
    # is an empty answer, never a question.
    body = "".join(f"{k}={v}\n" for k, v in fields.items()) + "\n"
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0", GIT_ASKPASS="/bin/false",
               SSH_ASKPASS="/bin/false")
    try:
        r = subprocess.run(["git", "-c", "credential.helper=",
                            "-c", "credential.helper=libsecret",
                            "credential", action], input=body, text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                           env=env, timeout=20)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return {}
    if r.returncode != 0:
        return {}
    return dict(l.split("=", 1) for l in r.stdout.splitlines() if "=" in l)


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
            raise ForgeError(msg or f"{who} answered {e.code}", e.code)
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            n += 1
            if n < tries:
                time.sleep(0.5 * n)
                continue
            why = getattr(e, "reason", None) or e
            raise ForgeError(f"cannot reach {who}: {why}")
    val = json.loads(txt) if txt else None
    return (val, link) if raw else val

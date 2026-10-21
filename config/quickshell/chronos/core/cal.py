#!/usr/bin/env python3
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# chronos' calendar, through khal (user, 2026-10-21): your .ics calendars,
# read and written by khal so recurring events, time zones and alarms are
# its business, and synced with an online calendar by vdirsyncer when one
# is set up. JSON for the panel.
#
#   cal.py status                    { khal, config, calendars, vdirsyncer, synced }
#   cal.py setup                     a khal config with one local calendar, when
#                                    there is none (never touches one that exists)
#   cal.py list FROM TO              events between two ISO dates (TO exclusive)
#   cal.py new CAL START END TITLE [LOCATION]
#                                    START/END "YYYY-MM-DD HH:MM", or both a bare
#                                    date for an all-day event
#   cal.py delete UID                the event's file, to the trash
#   cal.py sync                      vdirsyncer sync, when it is configured
#
# Standard library only (khal brings its own python dependencies).

import glob
import json
import os
import shutil
import subprocess
import sys

HOME = os.path.expanduser("~")
CONF_HOME = os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config")
DATA_HOME = os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local", "share")
KHAL_CONF = os.path.join(CONF_HOME, "khal", "config")
VDIR_CONF = os.path.join(CONF_HOME, "vdirsyncer", "config")
LOCAL_CAL = os.path.join(DATA_HOME, "khal", "calendars", "personal")

# the one khal config chronos writes: ISO dates and 24-hour times, because
# those are what it hands khal and reads back
CONFIG = """# written by chronos (ZENWORKS) — yours to edit; chronos only ever writes
# this file when there is none
[calendars]
[[personal]]
path = {path}
type = calendar
color = dark cyan

[locale]
timeformat = %H:%M
dateformat = %Y-%m-%d
longdateformat = %Y-%m-%d
datetimeformat = %Y-%m-%d %H:%M
longdatetimeformat = %Y-%m-%d %H:%M

[default]
default_calendar = personal
"""

FIELDS = ["uid", "title", "start-date", "start-time", "end-date", "end-time",
          "all-day", "location", "calendar", "description", "repeat-symbol"]


def run(argv, timeout=20):
    try:
        r = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout, r.stderr
    except (OSError, subprocess.SubprocessError) as e:
        return 1, "", str(e)


def calendars():
    """[{ name, path }] from khal's config: the [[name]] sections' paths
    (a glob, `type = discover`, is expanded)"""
    out = []
    try:
        text = open(KHAL_CONF).read()
    except OSError:
        return out
    name = None
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("[[") and s.endswith("]]"):
            name = s[2:-2].strip()
        elif s.startswith("[") and not s.startswith("[["):
            name = None
        elif name and s.startswith("path") and "=" in s:
            p = os.path.expanduser(s.split("=", 1)[1].strip())
            for q in (glob.glob(p) if any(c in p for c in "*?[") else [p]):
                out.append({"name": name if q == p else os.path.basename(q.rstrip("/")), "path": q})
    return out


def status():
    return {"khal": shutil.which("khal") is not None,
            "config": os.path.exists(KHAL_CONF),
            "calendars": [c["name"] for c in calendars()],
            "vdirsyncer": shutil.which("vdirsyncer") is not None,
            "synced": os.path.exists(VDIR_CONF)}


def setup():
    if os.path.exists(KHAL_CONF):
        return {"ok": True, "made": False}
    os.makedirs(os.path.dirname(KHAL_CONF), exist_ok=True)
    os.makedirs(LOCAL_CAL, exist_ok=True)
    with open(KHAL_CONF, "w") as f:
        f.write(CONFIG.format(path=LOCAL_CAL))
    return {"ok": True, "made": True}


def truthy(v):
    return str(v).strip().lower() in ("true", "1", "yes")


def parse_list(text):
    """khal list --json: one JSON array per day it lists (and, with the day
    headings off, nothing else) — every array line is taken, flattened"""
    out = []
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith("["):
            continue
        try:
            rows = json.loads(line)
        except ValueError:
            continue
        for r in rows if isinstance(rows, list) else []:
            if isinstance(r, dict):
                out.append(r)
    return out


def event(r):
    allday = truthy(r.get("all-day", ""))
    return {"uid": r.get("uid", ""), "title": r.get("title", "") or "(untitled)",
            "date": r.get("start-date", ""), "start": "" if allday else r.get("start-time", ""),
            "endDate": r.get("end-date", ""), "end": "" if allday else r.get("end-time", ""),
            "allDay": allday, "location": r.get("location", ""), "calendar": r.get("calendar", ""),
            "description": r.get("description", ""), "repeats": bool(r.get("repeat-symbol", "").strip())}


def list_events(start, end):
    args = ["khal", "list", "--day-format", ""]
    for f in FIELDS:
        args += ["--json", f]
    code, out, err = run(args + [start, end])
    if code != 0:
        return {"error": (err.strip().splitlines() or ["khal could not list"])[-1]}
    seen = set()
    events = []
    for r in parse_list(out):
        e = event(r)
        # an event spanning days is listed under each; the day it is listed
        # under is the one it shows on, so the key is the pair
        key = (e["uid"], e["date"], e["start"])
        if key in seen:
            continue
        seen.add(key)
        events.append(e)
    return {"events": events}


def new(cal, start, end, title, location=""):
    args = ["khal", "new"]
    if cal:
        args += ["-a", cal]
    if location:
        args += ["-l", location]
    args += [start] + ([end] if end else []) + [title]
    code, out, err = run(args)
    if code != 0:
        return {"error": (err.strip().splitlines() or ["khal could not add it"])[-1]}
    return {"ok": True}


def delete(uid):
    for c in calendars():
        for p in glob.glob(os.path.join(c["path"], "*.ics")):
            try:
                with open(p, errors="replace") as f:
                    if ("UID:" + uid) in f.read():
                        code, _, err = run(["gio", "trash", p])
                        if code != 0:
                            os.remove(p)
                        return {"ok": True}
            except OSError:
                continue
    return {"error": "That event was not found in any calendar"}


def sync():
    if not (shutil.which("vdirsyncer") and os.path.exists(VDIR_CONF)):
        return {"ok": False, "skipped": True}
    code, out, err = run(["vdirsyncer", "sync"], timeout=120)
    return {"ok": code == 0, "error": "" if code == 0 else (err.strip().splitlines() or ["vdirsyncer failed"])[-1]}


def main():
    a = sys.argv[1:]
    cmd = a[0] if a else ""
    if cmd == "status":
        r = status()
    elif cmd == "setup":
        r = setup()
    elif cmd == "list" and len(a) >= 3:
        r = list_events(a[1], a[2])
    elif cmd == "new" and len(a) >= 5:
        r = new(a[1], a[2], a[3], a[4], a[5] if len(a) > 5 else "")
    elif cmd == "delete" and len(a) >= 2:
        r = delete(a[1])
    elif cmd == "sync":
        r = sync()
    else:
        r = {"error": "usage: cal.py status|setup|list FROM TO|new CAL START END TITLE [LOC]|delete UID|sync"}
    print(json.dumps(r))


if __name__ == "__main__":
    main()

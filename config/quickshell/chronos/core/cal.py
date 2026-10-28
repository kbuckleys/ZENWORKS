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
# THE CALENDAR WINDOW (2026-10-28) reads and writes events whole, as .ics
# files in the calendar's directory, which khal and vdirsyncer then see:
#
#   cal.py calendars                 [ { name, title, path, color } ]
#   cal.py get UID                   the event, every field the window edits
#   cal.py save JSON                 a new event, or one changed: { uid?, calendar,
#                                    title, allDay, start, end, location,
#                                    description, repeat, alert }
#   cal.py accounts                  [ { name, url, user } ] chronos set up
#   cal.py account NAME URL USER     a CalDAV account (password on stdin):
#                                    vdirsyncer's pair, its calendars found and
#                                    synced, and khal told where they are
#   cal.py unaccount NAME            that account gone again
#   cal.py shift UID START END       moved or resized: its start and end moved by
#                                    START and END minutes (days, all day) — the
#                                    whole series for a repeat
#   cal.py copy UID [DAYS]           a copy, DAYS later (0: the same day)
#   cal.py search TEXT               events whose title, place or notes say TEXT,
#                                    a year back and two on
#   cal.py newcal TITLE [COLOR]      a calendar of its own on this computer
#   cal.py setcal NAME TITLE COLOR   a calendar renamed or recolored (its vdir
#                                    displayname and color files; synced back for
#                                    an online one)
#   cal.py delcal NAME               a calendar on this computer, to the trash
#
# Standard library only (khal brings its own python dependencies).

import datetime
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import uuid

HOME = os.path.expanduser("~")
CONF_HOME = os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config")
DATA_HOME = os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local", "share")
KHAL_CONF = os.path.join(CONF_HOME, "khal", "config")
VDIR_CONF = os.path.join(CONF_HOME, "vdirsyncer", "config")


def documents():
    """XDG's Documents directory (user-dirs.dirs), else ~/Documents"""
    try:
        with open(os.path.join(CONF_HOME, "user-dirs.dirs")) as f:
            for line in f:
                m = re.match(r'^XDG_DOCUMENTS_DIR="(.*)"\s*$', line.strip())
                if m:
                    return m.group(1).replace("$HOME", HOME)
    except OSError:
        pass
    return os.path.join(HOME, "Documents")


# THE CALENDAR ON THIS COMPUTER, where you can see it (user, 2026-10-28):
# ~/Documents/Calendar, one .ics file an event, as Clio's notes are kept
# under ~/Documents too. A config made before keeps the place it names.
LOCAL_ROOT = os.path.join(documents(), "Calendar")
# each calendar on this computer a directory in it (khal's `discover`): one
# more is one more directory, named and colored by vdir's displayname and
# color files, as a synced one is
LOCAL_CAL = os.path.join(LOCAL_ROOT, "Personal")

# the one khal config chronos writes: ISO dates and 24-hour times, because
# those are what it hands khal and reads back
CONFIG = """# written by chronos (Zenworks) — yours to edit; chronos writes this file
# when there is none, and adds or takes away the online accounts you set up
# in its calendar window, between their "chronos account" marks
[calendars]
{local}
[locale]
timeformat = %H:%M
dateformat = %Y-%m-%d
longdateformat = %Y-%m-%d
datetimeformat = %Y-%m-%d %H:%M
longdatetimeformat = %Y-%m-%d %H:%M
{default}"""
LOCAL = """[[local]]
path = {path}/*
type = discover
"""
DEFAULT = """
[default]
default_calendar = Personal
"""

FIELDS = ["uid", "title", "start-date", "start-time", "end-date", "end-time",
          "all-day", "location", "calendar", "description", "repeat-symbol"]


def run(argv, timeout=20, input=None):
    try:
        r = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, input=input)
        return r.returncode, r.stdout, r.stderr
    except (OSError, subprocess.SubprocessError) as e:
        return 1, "", str(e)


def calendars():
    """[{ name, title, path, color }] from khal's config: the [[name]]
    sections' paths (a glob, `type = discover`, is expanded). A synced
    calendar's own name and color are vdirsyncer's metasync files beside it."""
    out = []
    try:
        text = open(KHAL_CONF).read()
    except OSError:
        return out
    name, color = None, ""
    found = []
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("[[") and s.endswith("]]"):
            name, color = s[2:-2].strip(), ""
        elif s.startswith("[") and not s.startswith("[["):
            name = None
        elif name and s.startswith("color") and "=" in s:
            color = s.split("=", 1)[1].strip()
            for c in found:
                if c[0] == name:
                    c[2] = color
        elif name and s.startswith("path") and "=" in s:
            found.append([name, os.path.expanduser(s.split("=", 1)[1].strip()), color])
    for name, p, color in found:
        for q in (sorted(glob.glob(p)) if any(c in p for c in "*?[") else [p]):
            if not os.path.isdir(q) and q != p:
                continue
            own = os.path.basename(q.rstrip("/"))
            title = read_small(os.path.join(q, "displayname")) or (name if q == p else own)
            out.append({"name": name if q == p else own, "title": title, "path": q,
                        "color": read_small(os.path.join(q, "color")) or color})
    return out


def read_small(p):
    try:
        with open(p, errors="replace") as f:
            return f.read(200).strip()
    except OSError:
        return ""


def status():
    return {"khal": shutil.which("khal") is not None,
            "config": os.path.exists(KHAL_CONF),
            "calendars": [c["name"] for c in calendars()],
            "vdirsyncer": shutil.which("vdirsyncer") is not None,
            "synced": os.path.exists(VDIR_CONF)}


def setup(local=True):
    """khal's config, when there is none: with one calendar on this
    computer, or (local False, an online account's first) none of its own
    — asked first, never made unwanted (user, 2026-10-28)"""
    if os.path.exists(KHAL_CONF):
        return {"ok": True, "made": False}
    os.makedirs(os.path.dirname(KHAL_CONF), exist_ok=True)
    if local:
        os.makedirs(LOCAL_CAL, exist_ok=True)
        _meta(LOCAL_CAL, "Personal", CAL_COLORS["blue"])
    with open(KHAL_CONF, "w") as f:
        f.write(CONFIG.format(local=LOCAL.format(path=LOCAL_ROOT) if local else "",
                              default=DEFAULT if local else ""))
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
    colors = event_colors()
    for r in parse_list(out):
        e = event(r)
        e["color"] = colors.get(e["uid"], "")
        # an event spanning days is listed under each; the day it is listed
        # under is the one it shows on, so the key is the pair
        key = (e["uid"], e["date"], e["start"])
        if key in seen:
            continue
        seen.add(key)
        events.append(e)
    return {"events": events}


# ── COLORS (2026-10-28) ─────────────────────────────────────────────────
# Clio's stickies' seven hues (the window draws them in the theme's inks).
# A calendar's is written as vdir's hex, these; an event's as RFC 7986's
# COLOR, a CSS name other calendar apps know (sand is "tan").
CAL_COLORS = {"sand": "#c8b48c", "yellow": "#e8c547", "green": "#7fb069", "cyan": "#5fb3b3",
              "blue": "#5b8fd9", "magenta": "#b07cc6", "pink": "#e48aa5"}
CSS_OF = {"sand": "tan"}
HUE_OF = {"tan": "sand"}


def event_colors():
    """uid → its COLOR, from every calendar's files (khal does not list it)"""
    out = {}
    for c in calendars():
        for p in glob.glob(os.path.join(c["path"], "*.ics")):
            try:
                with open(p, errors="replace") as f:
                    text = f.read(200000)
            except OSError:
                continue
            if "\nCOLOR" not in text and "\rCOLOR" not in text:
                continue
            uid = color = ""
            for l in unfold(text):
                u = l.upper()
                if u.startswith("UID") and not uid:
                    uid = prop(l)[2].strip()
                elif u.startswith("COLOR") and not color:
                    color = prop(l)[2].strip().lower()
            if uid and color:
                out[uid] = HUE_OF.get(color, color)
    return out


def new(cal, start, end, title, location=""):
    args = ["khal", "new"]
    if cal:
        args += ["-a", cal]
    if location:
        args += ["-l", location]
    # -- first: a title like "-5 kg" is the event's, not an option
    args += ["--", start] + ([end] if end else []) + [title]
    code, out, err = run(args)
    if code != 0:
        return {"error": (err.strip().splitlines() or ["khal could not add it"])[-1]}
    return {"ok": True}


def uids_of(text):
    """Every UID an .ics holds, by its own line (RFC 5545 folds a long line
    onto ones that start with a space; unfolded first). Not a substring:
    "UID:abc" is in "UID:abcdef" too."""
    out = set()
    for line in re.sub(r"\r?\n[ \t]", "", text).splitlines():
        m = re.match(r"UID(?:;[^:]*)?:(.*)$", line.strip(), re.I)
        if m:
            out.add(m.group(1).strip())
    return out


def delete(uid):
    for c in calendars():
        for p in glob.glob(os.path.join(c["path"], "*.ics")):
            try:
                with open(p, errors="replace") as f:
                    uids = uids_of(f.read())
            except OSError:
                continue
            if uid not in uids:
                continue
            # the file goes whole: one holding other events too would take
            # them with it (an imported calendar is often one file)
            if len(uids) > 1:
                return {"error": "That event shares its file with others — remove it in your calendar app"}
            code, _, err = run(["gio", "trash", "--", p])
            if code != 0:
                # never for good without asking: said, and left where it is
                return {"error": (err.strip().splitlines() or ["It could not be moved to the trash"])[-1]}
            return {"ok": True}
    return {"error": "That event was not found in any calendar"}


def sync():
    if not (shutil.which("vdirsyncer") and os.path.exists(VDIR_CONF)):
        return {"ok": False, "skipped": True}
    code, out, err = run(["vdirsyncer", "sync"], timeout=120)
    return {"ok": code == 0, "error": "" if code == 0 else (err.strip().splitlines() or ["vdirsyncer failed"])[-1]}


# ── EVENTS WHOLE (the window, 2026-10-28) ───────────────────────────────

def unfold(text):
    return re.sub(r"\r?\n[ \t]", "", text).replace("\r\n", "\n").split("\n")


def fold(line):
    """RFC 5545: lines of 75 octets at most, the rest on lines that start
    with a space; never through a UTF-8 character"""
    b = line.encode("utf-8")
    if len(b) <= 75:
        return line
    out, cur = [], b""
    for ch in line:
        e = ch.encode("utf-8")
        if len(cur) + len(e) > (75 if not out else 74):
            out.append(cur.decode("utf-8"))
            cur = b""
        cur += e
    out.append(cur.decode("utf-8"))
    return "\r\n ".join(out)


def esc(t):
    return str(t).replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace("\r\n", "\\n").replace("\n", "\\n")


def unesc(t):
    return re.sub(r"\\(.)", lambda m: "\n" if m.group(1) in "nN" else m.group(1), t)


def prop(line):
    """'DTSTART;TZID=Europe/Berlin:20261028T140000' → (NAME, {params}, value)"""
    head, _, value = line.partition(":")
    # a colon inside a quoted parameter is the parameter's
    while head.count('"') % 2:
        more, _, value = value.partition(":")
        head += ":" + more
    parts = head.split(";")
    params = {}
    for p in parts[1:]:
        k, _, v = p.partition("=")
        params[k.upper()] = v.strip('"')
    return parts[0].upper(), params, value


def local_zone():
    """the machine's zone, by name ("Europe/Berlin"), or "" """
    tz = os.environ.get("TZ", "").lstrip(":")
    if tz and "/" in tz and not tz.startswith("/"):
        return tz
    real = os.path.realpath("/etc/localtime")
    i = real.find("zoneinfo/")
    return real[i + 9:] if i >= 0 else ""


def zone(name):
    try:
        from zoneinfo import ZoneInfo
        return ZoneInfo(name)
    except Exception:
        return None


def to_local(value, params):
    """an ICS date or date-time → (local datetime or date, all_day)"""
    v = value.strip()
    if params.get("VALUE", "").upper() == "DATE" or re.fullmatch(r"\d{8}", v):
        return datetime.date(int(v[:4]), int(v[4:6]), int(v[6:8])), True
    m = re.fullmatch(r"(\d{8})T(\d{2})(\d{2})(\d{2})?(Z?)", v)
    if not m:
        raise ValueError("unreadable time " + v)
    d = datetime.datetime(int(m.group(1)[:4]), int(m.group(1)[4:6]), int(m.group(1)[6:8]),
                          int(m.group(2)), int(m.group(3)), int(m.group(4) or 0))
    if m.group(5):
        return d.replace(tzinfo=datetime.timezone.utc).astimezone().replace(tzinfo=None), False
    z = zone(params.get("TZID", "")) if params.get("TZID") else None
    if z:
        return d.replace(tzinfo=z).astimezone().replace(tzinfo=None), False
    return d, False


def stamp(d):
    return d.strftime("%Y-%m-%d") if not isinstance(d, datetime.datetime) else d.strftime("%Y-%m-%d %H:%M")


REPEATS = ("daily", "weekly", "monthly", "yearly")


def repeat_of(rrule):
    if not rrule:
        return ""
    parts = dict(p.partition("=")[::2] for p in rrule.upper().split(";") if p)
    f = parts.pop("FREQ", "").lower()
    if parts.get("INTERVAL") == "1":
        parts.pop("INTERVAL")
    # a weekly one on its own weekday says BYDAY too, as many clients write it
    if f == "weekly" and "BYDAY" in parts and "," not in parts["BYDAY"]:
        parts.pop("BYDAY")
    return f if f in REPEATS and not parts else "custom"


def alert_of(trigger, params):
    """minutes before the start, or None"""
    if params.get("RELATED", "START").upper() != "START" or params.get("VALUE", "").upper() == "DATE-TIME":
        return None
    m = re.fullmatch(r"(-?)P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?", trigger.strip())
    if not m:
        return None
    mins = int(m.group(2) or 0) * 10080 + int(m.group(3) or 0) * 1440 + int(m.group(4) or 0) * 60 + int(m.group(5) or 0)
    return mins if m.group(1) == "-" or mins == 0 else None


def blocks(lines):
    """the master VEVENT's span in `lines` (first and last index), and
    whether other components share the UID (exceptions to a repeat)"""
    spans, start = [], None
    for i, l in enumerate(lines):
        u = l.strip().upper()
        if u == "BEGIN:VEVENT":
            start = i
        elif u == "END:VEVENT" and start is not None:
            spans.append((start, i))
            start = None
    master = None
    for a, b in spans:
        if not any(lines[k].upper().startswith("RECURRENCE-ID") for k in range(a, b)):
            master = (a, b)
            break
    return master or (spans[0] if spans else None)


def file_of(uid):
    """(calendar, path, text) of the file holding UID alone; or an error"""
    for c in calendars():
        for p in glob.glob(os.path.join(c["path"], "*.ics")):
            try:
                with open(p, errors="replace") as f:
                    text = f.read()
            except OSError:
                continue
            uids = uids_of(text)
            if uid not in uids:
                continue
            if len(uids) > 1:
                return None, None, "That event shares its file with others — change it in your calendar app"
            return c, p, text
    return None, None, "That event was not found in any calendar"


def get(uid):
    c, p, text = file_of(uid)
    if not c:
        return {"error": text}
    lines = unfold(text)
    span = blocks(lines)
    if not span:
        return {"error": "That event's file holds no event"}
    ev = {"uid": uid, "calendar": c["name"], "title": "", "location": "", "description": "",
          "repeat": "", "alert": None, "allDay": False, "start": "", "end": "", "color": "", "url": "", "note": ""}
    start = end = None
    duration = None
    depth = 0
    for l in lines[span[0] + 1:span[1]]:
        u = l.upper()
        if u.startswith("BEGIN:"):
            depth += 1
            continue
        if u.startswith("END:"):
            depth -= 1
            continue
        name, params, value = prop(l)
        if depth > 0:
            if name == "TRIGGER" and ev["alert"] is None:
                ev["alert"] = alert_of(value, params)
            continue
        try:
            if name == "SUMMARY":
                ev["title"] = unesc(value)
            elif name == "LOCATION":
                ev["location"] = unesc(value)
            elif name == "COLOR":
                c = value.strip().lower()
                ev["color"] = HUE_OF.get(c, c)
            elif name == "URL":
                ev["url"] = value.strip()
            elif name == "X-CLIO-NOTE":
                # its notes in Clio (2026-10-28): the note's id
                ev["note"] = value.strip()
            elif name == "DESCRIPTION":
                ev["description"] = unesc(value)
            elif name == "RRULE":
                ev["repeat"] = repeat_of(value)
            elif name == "DTSTART":
                start, ev["allDay"] = to_local(value, params)
            elif name == "DTEND":
                end, _ = to_local(value, params)
            elif name == "DURATION":
                duration = value
        except ValueError as e:
            return {"error": str(e)}
    if start is None:
        return {"error": "That event has no start"}
    if end is None and duration:
        m = alert_of("-" + duration.lstrip("+"), {})
        end = start + datetime.timedelta(minutes=m or 0) if m is not None else None
    if end is None:
        end = start + (datetime.timedelta(days=1) if ev["allDay"] else datetime.timedelta(hours=1))
    if ev["allDay"]:
        # DTEND is the day after the last one
        end = max(start, end - datetime.timedelta(days=1))
    ev["start"], ev["end"] = stamp(start), stamp(end)
    return ev


def parse_when(t, all_day):
    t = str(t or "").strip()
    if all_day:
        return datetime.datetime.strptime(t[:10], "%Y-%m-%d").date()
    return datetime.datetime.strptime(t, "%Y-%m-%d %H:%M")


def nth_weekday(d):
    """BYDAY for the transition's day: -1SU in a month's last week"""
    day = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"][d.weekday()]
    last = (d + datetime.timedelta(days=7)).month != d.month
    return ("-1" if last else str((d.day - 1) // 7 + 1)) + day


def offset(td):
    s = int(td.total_seconds())
    sign = "-" if s < 0 else "+"
    s = abs(s)
    return "%s%02d%02d" % (sign, s // 3600, (s % 3600) // 60)


def vtimezone(name, year):
    """a VTIMEZONE for `name` as it runs in `year`: its changes as yearly
    rules, which every client reads (the TZID alone is not enough for some
    servers)"""
    z = zone(name)
    if not z:
        return []
    def off(d):
        return d.replace(tzinfo=z).utcoffset()
    start = datetime.datetime(year, 1, 1, 12)
    changes = []
    prev = off(start)
    for i in range(1, 366):
        d = start + datetime.timedelta(days=i)
        o = off(d)
        if o != prev:
            # to the hour it changed, in the old local time
            h = d - datetime.timedelta(days=1)
            while off(h + datetime.timedelta(hours=1)) == prev:
                h += datetime.timedelta(hours=1)
            changes.append((h.replace(minute=0, second=0) + datetime.timedelta(hours=1), prev, o))
            prev = o
    out = ["BEGIN:VTIMEZONE", "TZID:" + name]
    if not changes:
        out += ["BEGIN:STANDARD", "DTSTART:19700101T000000", "TZOFFSETFROM:" + offset(prev),
                "TZOFFSETTO:" + offset(prev), "END:STANDARD"]
    for at, frm, to in changes:
        kind = "DAYLIGHT" if to > frm else "STANDARD"
        out += ["BEGIN:" + kind, "DTSTART:" + at.strftime("%Y%m%dT%H%M%S"),
                "RRULE:FREQ=YEARLY;BYMONTH=%d;BYDAY=%s" % (at.month, nth_weekday(at.date())),
                "TZOFFSETFROM:" + offset(frm), "TZOFFSETTO:" + offset(to), "END:" + kind]
    return out + ["END:VTIMEZONE"]


MANAGED = ("SUMMARY", "DTSTART", "DTEND", "DURATION", "LOCATION", "DESCRIPTION", "DTSTAMP", "COLOR", "URL", "X-CLIO-NOTE",
           "LAST-MODIFIED", "SEQUENCE")


def event_lines(e, start, end, tzname, keep_rrule):
    """the managed half of a VEVENT, and whether it needs a VTIMEZONE"""
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out = ["DTSTAMP:" + now, "LAST-MODIFIED:" + now]
    needs_tz = False
    if e["allDay"]:
        out += ["DTSTART;VALUE=DATE:" + start.strftime("%Y%m%d"),
                "DTEND;VALUE=DATE:" + (end + datetime.timedelta(days=1)).strftime("%Y%m%d")]
    elif (e.get("repeat") or keep_rrule) and tzname:
        # a repeat keeps its wall-clock time across summer time: the zone's
        out += ["DTSTART;TZID=%s:%s" % (tzname, start.strftime("%Y%m%dT%H%M%S")),
                "DTEND;TZID=%s:%s" % (tzname, end.strftime("%Y%m%dT%H%M%S"))]
        needs_tz = True
    else:
        u = lambda d: d.astimezone(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        out += ["DTSTART:" + u(start), "DTEND:" + u(end)]
    out.append("SUMMARY:" + esc(e["title"]))
    col = str(e.get("color") or "").strip().lower()
    if re.fullmatch(r"[a-z]{3,20}", col):
        out.append("COLOR:" + CSS_OF.get(col, col))
    url = str(e.get("url") or "").strip()
    if re.match(r"^(https?|mailto|tel):", url):
        out.append("URL:" + url)
    note = str(e.get("note") or "").strip()
    if re.fullmatch(r"[A-Za-z0-9._-]{1,80}", note):
        out.append("X-CLIO-NOTE:" + note)
    if e.get("location"):
        out.append("LOCATION:" + esc(e["location"]))
    if e.get("description"):
        out.append("DESCRIPTION:" + esc(e["description"]))
    if e.get("repeat") in REPEATS:
        out.append("RRULE:FREQ=" + e["repeat"].upper())
    a = e.get("alert")
    if isinstance(a, (int, float)) and a >= 0:
        out += ["BEGIN:VALARM", "ACTION:DISPLAY", "DESCRIPTION:" + esc(e["title"]),
                "TRIGGER:-PT%dM" % int(a) if a else "TRIGGER:PT0S", "END:VALARM"]
    return out, needs_tz


def write_atomic(path, text):
    tmp = path + ".part"
    with open(tmp, "w", newline="") as f:
        f.write(text)
    os.replace(tmp, path)


def save(raw):
    try:
        e = json.loads(raw)
    except ValueError:
        return {"error": "The event did not come through"}
    if not isinstance(e, dict):
        return {"error": "The event did not come through"}
    e["title"] = str(e.get("title", "")).strip()
    e["allDay"] = bool(e.get("allDay"))
    if not e["title"]:
        return {"error": "Give it a title"}
    try:
        start = parse_when(e.get("start"), e["allDay"])
        end = parse_when(e.get("end") or e.get("start"), e["allDay"])
    except ValueError:
        return {"error": "That is not a date and time (YYYY-MM-DD HH:MM)"}
    if end < start:
        return {"error": "It ends before it starts"}
    cals = calendars()
    cal = next((c for c in cals if c["name"] == e.get("calendar")), cals[0] if cals else None)
    if not cal:
        return {"error": "There is no calendar to put it in"}
    tzname = local_zone() if zone(local_zone() or "-") else ""
    # one line of the file (UID:…): no line breaks in it
    uid = re.sub(r"[\r\n]", "", str(e.get("uid") or ""))
    old_path, keep_rrule, text = None, False, None
    if uid:
        c, old_path, text = file_of(uid)
        if not c:
            # gone (an undone delete puts it back): made again, under its uid
            if text != "That event was not found in any calendar":
                return {"error": text}
            old_path, text = None, None
    else:
        uid = str(uuid.uuid4()).upper() + "@zenworks"
    if not e["allDay"]:
        start, end = start.astimezone(), end.astimezone()
    if text is not None:
        lines = [l for l in unfold(text) if l != ""]
        span = blocks(lines)
        if not span:
            return {"error": "That event's file holds no event"}
        a, b = span
        body, depth, seq, kept = [], 0, 0, []
        for l in lines[a + 1:b]:
            u = l.upper()
            name = prop(l)[0] if depth == 0 and not u.startswith(("BEGIN:", "END:")) else ""
            if u.startswith("BEGIN:"):
                depth += 1
            if depth > 0:
                # an alarm is the form's to say; anything else nested stays
                kept.append(l)
                if u.startswith("END:"):
                    depth -= 1
                    if depth == 0:
                        if not any(k.upper() == "BEGIN:VALARM" for k in kept):
                            body += kept
                        kept = []
                continue
            if name == "SEQUENCE":
                try:
                    seq = int(prop(l)[2]) + 1
                except ValueError:
                    seq = 1
                continue
            if name == "RRULE":
                if e.get("repeat") == "custom":
                    body.append(l)
                    keep_rrule = True
                continue
            if name in MANAGED or name == "UID":
                continue
            body.append(l)
        mine, needs_tz = event_lines(e, start, end, tzname, keep_rrule)
        vevent = ["BEGIN:VEVENT", "UID:" + uid, "SEQUENCE:%d" % seq] + mine + body + ["END:VEVENT"]
        rest = lines[:a] + vevent + lines[b + 1:]
        if needs_tz and not any(l.upper() == "TZID:" + tzname.upper() for l in rest):
            i = next((k for k, l in enumerate(rest) if l.upper() == "BEGIN:VEVENT"), len(rest) - 1)
            rest = rest[:i] + vtimezone(tzname, start.year) + rest[i:]
    else:
        mine, needs_tz = event_lines(e, start, end, tzname, False)
        rest = (["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Zenworks//Chronos//EN"]
                + (vtimezone(tzname, start.year) if needs_tz else [])
                + ["BEGIN:VEVENT", "UID:" + uid, "SEQUENCE:0"] + mine + ["END:VEVENT", "END:VCALENDAR"])
    out = "\r\n".join(fold(l) for l in rest) + "\r\n"
    moved = old_path and os.path.dirname(old_path) != cal["path"].rstrip("/")
    path = old_path if old_path and not moved else os.path.join(
        cal["path"], re.sub(r"[^A-Za-z0-9@._-]", "_", uid) + ".ics")
    try:
        os.makedirs(cal["path"], exist_ok=True)
        write_atomic(path, out)
    except OSError as err:
        return {"error": "It could not be written: " + (err.strerror or str(err))}
    if moved:
        code, _, err = run(["gio", "trash", "--", old_path])
        if code != 0:
            return {"ok": True, "uid": uid, "warning": "It is in both calendars now: the old copy could not go to the trash"}
    return {"ok": True, "uid": uid}


def shift(uid, ds, de):
    """start and end moved by ds and de minutes (days for an all-day one)"""
    ev = get(uid)
    if ev.get("error"):
        return ev
    try:
        ds, de = int(ds), int(de)
    except ValueError:
        return {"error": "Minutes are whole numbers"}
    if ev["allDay"]:
        a = parse_when(ev["start"], True) + datetime.timedelta(days=ds)
        b = parse_when(ev["end"], True) + datetime.timedelta(days=de)
        ev["start"], ev["end"] = stamp(a), stamp(max(a, b))
    else:
        a = parse_when(ev["start"], False) + datetime.timedelta(minutes=ds)
        b = parse_when(ev["end"], False) + datetime.timedelta(minutes=de)
        if b <= a:
            b = a + datetime.timedelta(minutes=15)
        ev["start"], ev["end"] = stamp(a), stamp(b)
    r = save(json.dumps(ev))
    return dict(r, start=ev["start"], end=ev["end"]) if r.get("ok") else r


def copy(uid, days=0):
    ev = get(uid)
    if ev.get("error"):
        return ev
    ev["uid"] = ""
    d = int(days or 0)
    if d:
        ad = ev["allDay"]
        ev["start"] = stamp(parse_when(ev["start"], ad) + datetime.timedelta(days=d))
        ev["end"] = stamp(parse_when(ev["end"], ad) + datetime.timedelta(days=d))
    return save(json.dumps(ev))


def search(text):
    t = str(text or "").strip().lower()
    if len(t) < 2:
        return {"events": []}
    today = datetime.date.today()
    r = list_events((today - datetime.timedelta(days=365)).isoformat(), (today + datetime.timedelta(days=730)).isoformat())
    if r.get("error"):
        return r
    found, seen = [], set()
    for e in r["events"]:
        if t in (e["title"] + " " + e["location"] + " " + e["description"]).lower():
            # a repeat is one result: its next time from today, else its last
            k = e["uid"]
            if k in seen and e["date"] < today.isoformat():
                continue
            if k in seen:
                found = [x for x in found if x["uid"] != k or x["date"] >= today.isoformat()]
                if any(x["uid"] == k for x in found):
                    continue
            seen.add(k)
            found.append(e)
    found.sort(key=lambda e: (e["date"] < today.isoformat(), e["date"] if e["date"] >= today.isoformat() else "~" + str(9999 - int(e["date"][:4])) + e["date"]))
    return {"events": found[:200]}


# ── CALENDARS OF YOUR OWN, ON THIS COMPUTER ─────────────────────────────
def _meta(path, title, color):
    os.makedirs(path, exist_ok=True)
    with open(os.path.join(path, "displayname"), "w") as f:
        f.write(title)
    if color:
        with open(os.path.join(path, "color"), "w") as f:
            f.write(color)


def _color_hex(c):
    c = str(c or "").strip().lower()
    if c in CAL_COLORS:
        return CAL_COLORS[c]
    return c if re.fullmatch(r"#[0-9a-f]{6}", c) else ""


def newcal(title, color=""):
    t = str(title or "").strip()
    if not t:
        return {"error": "Give the calendar a name"}
    if not os.path.exists(KHAL_CONF):
        setup(local=True)
    # the directory local calendars live in, in khal's config (an older one
    # names a single calendar: this root is added beside it)
    conf = open(KHAL_CONF).read()
    if os.path.join(LOCAL_ROOT, "*") not in conf:
        m = re.search(r"(?m)^\[calendars\]\s*$", conf)
        at = m.end() if m else 0
        conf = conf[:at] + "\n" + LOCAL.format(path=LOCAL_ROOT) + conf[at:]
        write_atomic(KHAL_CONF, conf)
    name = re.sub(r"[^A-Za-z0-9 _-]", "", t).strip().replace(" ", "-")[:40] or "Calendar"
    path, n = os.path.join(LOCAL_ROOT, name), 2
    while os.path.exists(path):
        path, n = os.path.join(LOCAL_ROOT, name + "-" + str(n)), n + 1
    _meta(path, t, _color_hex(color) or CAL_COLORS["blue"])
    return {"ok": True, "name": os.path.basename(path)}


def setcal(name, title, color):
    c = next((c for c in calendars() if c["name"] == name), None)
    if not c:
        return {"error": "There is no calendar " + str(name)}
    t = str(title or "").strip() or c["title"]
    _meta(c["path"], t, _color_hex(color) or c.get("color", ""))
    return {"ok": True}


def delcal(name):
    c = next((c for c in calendars() if c["name"] == name), None)
    if not c:
        return {"error": "There is no calendar " + str(name)}
    real = os.path.realpath(c["path"])
    if not real.startswith(os.path.realpath(LOCAL_ROOT) + os.sep):
        return {"error": "Only a calendar on this computer is deleted here — an online one, on its account"}
    code, _, err = run(["gio", "trash", "--", real])
    if code != 0:
        return {"error": (err.strip().splitlines() or ["It could not be moved to the trash"])[-1]}
    return {"ok": True}


# ── ACCOUNTS (CalDAV, through vdirsyncer) ───────────────────────────────
VDIR_DATA = os.path.join(DATA_HOME, "vdirsyncer")
SECRET = ["secret-tool"]


def account_name(n):
    return re.sub(r"[^a-z0-9_-]", "", str(n).strip().lower().replace(" ", "-"))[:32]


def marked(text, name):
    """the span chronos wrote for `name`: from its start mark to its end mark"""
    m = re.search(r"(?ms)^# chronos account: %s\n.*?^# end chronos account: %s\n?" % (re.escape(name), re.escape(name)), text)
    return m


def accounts():
    try:
        text = open(VDIR_CONF).read()
    except OSError:
        return []
    out = []
    for name in re.findall(r"(?m)^# chronos account: (\S+)$", text):
        m = marked(text, name)
        body = m.group(0) if m else ""
        url = re.search(r'(?m)^url = "(.*)"$', body)
        user = re.search(r'(?m)^username = "(.*)"$', body)
        out.append({"name": name, "url": url.group(1) if url else "", "user": user.group(1) if user else ""})
    return out


def quote(v):
    # one line of vdirsyncer's config: a newline would start another
    v = re.sub(r"[\r\n]+", " ", str(v))
    return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'


def account(name, url, user, password):
    name = account_name(name)
    if not name:
        return {"error": "Give the account a name"}
    if not re.match(r"^https?://", url or ""):
        return {"error": "The server's address starts with https://"}
    if not shutil.which("vdirsyncer"):
        return {"error": "vdirsyncer is not installed"}
    if any(a["name"] == name for a in accounts()):
        return {"error": "There is an account called " + name + " already"}
    if not os.path.exists(KHAL_CONF):
        setup(local=False)
    code, _, err = run(SECRET + ["store", "--label", "Calendar " + name + " (Zenworks)",
                                 "service", "zenworks-calendar", "account", name], input=password)
    if code != 0:
        return {"error": "The password could not be kept in the keyring: " + ((err.strip().splitlines() or ["secret-tool failed"])[-1])}
    local = os.path.join(VDIR_DATA, "calendars", name)
    block = "\n".join([
        "# chronos account: " + name,
        "[pair %s]" % name,
        'a = "%s_local"' % name,
        'b = "%s_remote"' % name,
        'collections = ["from b"]',
        'metadata = ["color", "displayname"]',
        "",
        "[storage %s_local]" % name,
        'type = "filesystem"',
        "path = " + quote(local + "/"),
        'fileext = ".ics"',
        "",
        "[storage %s_remote]" % name,
        'type = "caldav"',
        "url = " + quote(url),
        "username = " + quote(user),
        'password.fetch = ["command", "secret-tool", "lookup", "service", "zenworks-calendar", "account", %s]' % quote(name),
        "# end chronos account: " + name, ""])
    try:
        text = open(VDIR_CONF).read() if os.path.exists(VDIR_CONF) else ""
    except OSError:
        text = ""
    if "[general]" not in text:
        text = ('[general]\nstatus_path = "%s/"\n\n' % os.path.join(VDIR_DATA, "status")) + text
    os.makedirs(os.path.dirname(VDIR_CONF), exist_ok=True)
    os.makedirs(local, exist_ok=True)
    write_atomic(VDIR_CONF, text.rstrip("\n") + "\n\n" + block)
    # discover asks before making each local calendar: yes to every one
    code, out, err = run(["vdirsyncer", "discover", name], timeout=120, input="y\n" * 50)
    if code != 0:
        unaccount(name)
        last = (err.strip().splitlines() or out.strip().splitlines() or ["the server did not answer"])[-1]
        return {"error": "The server said no: " + last}
    run(["vdirsyncer", "metasync", name], timeout=120)
    code, _, err = run(["vdirsyncer", "sync", name], timeout=300)
    # khal reads them where vdirsyncer keeps them, each calendar a directory
    try:
        conf = open(KHAL_CONF).read()
    except OSError:
        conf = ""
    entry = "# chronos account: %s\n[[%s]]\npath = %s/*\ntype = discover\n# end chronos account: %s\n" % (name, name, local, name)
    m = re.search(r"(?m)^\[calendars\]\s*$", conf)
    if m:
        nxt = re.search(r"(?m)^\[(?!\[)", conf[m.end():])
        at = m.end() + nxt.start() if nxt else len(conf)
        conf = conf[:at].rstrip("\n") + "\n" + entry + "\n" + conf[at:]
    else:
        conf = "[calendars]\n" + entry + "\n" + conf
    write_atomic(KHAL_CONF, conf)
    return {"ok": True, "name": name, "synced": code == 0,
            "warning": "" if code == 0 else (err.strip().splitlines() or ["the first sync failed"])[-1]}


def unaccount(name):
    # a name that cleans down to nothing is no account — and its directory
    # would be calendars/ itself, every account's
    if not name:
        return {"error": "There is no such account"}
    for path in (VDIR_CONF, KHAL_CONF):
        try:
            text = open(path).read()
        except OSError:
            continue
        m = marked(text, name)
        if m:
            write_atomic(path, text[:m.start()] + text[m.end():])
    run(SECRET + ["clear", "service", "zenworks-calendar", "account", name])
    local = os.path.join(VDIR_DATA, "calendars", name)
    if os.path.isdir(local):
        run(["gio", "trash", "--", local])
    return {"ok": True}


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
    elif cmd == "calendars":
        r = calendars()
    elif cmd == "get" and len(a) >= 2:
        r = get(a[1])
    elif cmd == "save" and len(a) >= 2:
        r = save(a[1])
    elif cmd == "accounts":
        r = accounts()
    elif cmd == "account" and len(a) >= 4:
        r = account(a[1], a[2], a[3], sys.stdin.readline().rstrip("\n"))
    elif cmd == "unaccount" and len(a) >= 2:
        r = unaccount(account_name(a[1]))
    elif cmd == "shift" and len(a) >= 4:
        r = shift(a[1], a[2], a[3])
    elif cmd == "copy" and len(a) >= 2:
        r = copy(a[1], a[2] if len(a) > 2 else 0)
    elif cmd == "search" and len(a) >= 2:
        r = search(a[1])
    elif cmd == "newcal" and len(a) >= 2:
        r = newcal(a[1], a[2] if len(a) > 2 else "")
    elif cmd == "setcal" and len(a) >= 4:
        r = setcal(a[1], a[2], a[3])
    elif cmd == "delcal" and len(a) >= 2:
        r = delcal(a[1])
    else:
        r = {"error": "usage: cal.py status|setup|list FROM TO|new CAL START END TITLE [LOC]|delete UID|sync"
                      "|calendars|get UID|save JSON|accounts|account NAME URL USER|unaccount NAME"}
    print(json.dumps(r))


if __name__ == "__main__":
    main()

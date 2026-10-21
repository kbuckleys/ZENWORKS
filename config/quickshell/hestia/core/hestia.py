#!/usr/bin/env python3
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# hestia's reader: systemd and the journal, as JSON for the window.
#
#   hestia.py units  system|user        every service: what it is, whether it
#                                       runs, whether it starts at boot, how
#                                       often it has restarted
#   hestia.py show   system|user UNIT   one unit's facts
#   hestia.py timers system|user        the timers, when they ran and run next
#   hestia.py logs   [--user] [--unit U] [--prio N] [--boot B] [--grep Q] [-n N]
#                                       journal lines, newest last
#   hestia.py boot                      how long the last boot took, and what
#                                       took it
#
# Read only: starting, stopping and enabling are systemctl's own, run by the
# window (polkit asks for the password, hyprpolkitagent shows it). Every
# command on a timeout; standard library only.

import json
import re
import subprocess
import sys

SHOW_PROPS = ["Id", "Description", "LoadState", "ActiveState", "SubState", "UnitFileState",
              "UnitFilePreset", "FragmentPath", "ActiveEnterTimestamp", "InactiveEnterTimestamp",
              "MainPID", "MemoryCurrent", "CPUUsageNSec", "NRestarts", "Restart", "ExecStart",
              "TriggeredBy", "Documentation", "Result", "Type", "User", "WantedBy"]


def run(argv, timeout=8):
    try:
        r = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        return r.stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def sysctl(scope):
    return ["systemctl", "--user"] if scope == "user" else ["systemctl"]


def as_json(text, default):
    try:
        return json.loads(text)
    except ValueError:
        return default


def show_many(scope, units, props):
    """`systemctl show` for many units in one call: blocks split by a blank line"""
    out = {}
    if not units:
        return out
    text = run(sysctl(scope) + ["show", "--no-pager", "-p", ",".join(props), "--"] + units, timeout=15)
    for block in text.split("\n\n"):
        d = {}
        for line in block.splitlines():
            k, _, v = line.partition("=")
            if k:
                d[k] = v
        if d.get("Id"):
            out[d["Id"]] = d
    return out


def num(v):
    try:
        n = int(v)
        # systemd's "infinity"/unset is 2^64-1
        return -1 if n >= 18446744073709551615 else n
    except (TypeError, ValueError):
        return -1


def units(scope):
    loaded = as_json(run(sysctl(scope) + ["list-units", "--type=service", "--all", "-o", "json", "--no-pager"]), [])
    files = as_json(run(sysctl(scope) + ["list-unit-files", "--type=service", "-o", "json", "--no-pager"]), [])
    by = {}
    for f in files:
        name = f.get("unit_file", "")
        # templates (foo@.service) are not units anyone runs as such
        if not name or name.endswith("@.service"):
            continue
        by[name] = {"unit": name, "desc": "", "load": "", "active": "inactive", "sub": "dead",
                    "file": f.get("state") or "", "preset": f.get("preset") or "", "loaded": False}
    for u in loaded:
        name = u.get("unit", "")
        if not name:
            continue
        e = by.setdefault(name, {"unit": name, "file": "", "preset": ""})
        e.update({"desc": u.get("description") or "", "load": u.get("load") or "",
                  "active": u.get("active") or "", "sub": u.get("sub") or "", "loaded": True})
    # what only `show` knows, for the ones systemd has loaded
    live = [n for n, e in by.items() if e.get("loaded")]
    shown = show_many(scope, live, ["Id", "NRestarts", "MainPID", "MemoryCurrent", "ActiveEnterTimestamp",
                                    "UnitFileState", "Description"])
    for n, e in by.items():
        s = shown.get(n, {})
        e["restarts"] = max(0, num(s.get("NRestarts")))
        e["pid"] = max(0, num(s.get("MainPID")))
        e["mem"] = num(s.get("MemoryCurrent"))
        e["since"] = s.get("ActiveEnterTimestamp", "")
        if not e.get("file") and s.get("UnitFileState"):
            e["file"] = s["UnitFileState"]
        if not e.get("desc") and s.get("Description"):
            e["desc"] = s["Description"]
        e["scope"] = scope
    return sorted(by.values(), key=lambda e: e["unit"])


def show(scope, unit):
    d = show_many(scope, [unit], SHOW_PROPS).get(unit, {})
    for k in ("MainPID", "MemoryCurrent", "CPUUsageNSec", "NRestarts"):
        if k in d:
            d[k] = num(d[k])
    # ExecStart is systemd's struct dump: the command line is its argv
    ex = d.get("ExecStart", "")
    if "argv[]=" in ex:
        d["ExecStart"] = ex.split("argv[]=", 1)[1].split(" ;", 1)[0].strip()
    d["scope"] = scope
    return d


def timers(scope):
    rows = as_json(run(sysctl(scope) + ["list-timers", "--all", "-o", "json", "--no-pager"]), [])
    names = [r.get("activates") for r in rows if r.get("activates")]
    descs = show_many(scope, [r.get("unit") for r in rows if r.get("unit")] + names, ["Id", "Description"])
    out = []
    for r in rows:
        unit = r.get("unit", "")
        out.append({"unit": unit, "activates": r.get("activates") or "",
                    "desc": (descs.get(r.get("activates") or "", {}) or {}).get("Description")
                            or (descs.get(unit, {}) or {}).get("Description", ""),
                    # microseconds since the epoch; 0 for never / not scheduled
                    "next": r.get("next") or 0, "last": r.get("last") or 0, "scope": scope})
    return out


# a terminal's colour codes, which some services write into the journal
# (nusgmon's "\x1b[1mSkipping…"): meaningless outside a terminal
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b\][^\x07]*\x07")


def message(m):
    # MESSAGE is a string, or a byte array when it is not valid UTF-8 (or
    # carries those escape codes)
    if isinstance(m, list):
        try:
            m = bytes(m).decode("utf-8", "replace")
        except (TypeError, ValueError):
            return ""
    return ANSI.sub("", str(m or ""))


def logs(args):
    argv = ["journalctl", "-o", "json", "--no-pager"]
    n = "400"
    i = 0
    while i < len(args):
        a = args[i]
        v = args[i + 1] if i + 1 < len(args) else ""
        if a == "--user":
            argv.append("--user")
            i += 1
            continue
        if a == "--unit" and v:
            argv += ["--user-unit" if "--user" in args else "--unit", v]
        elif a == "--prio" and v:
            argv += ["-p", v]
        elif a == "--boot" and v:
            argv += ["-b", v]
        elif a == "--grep" and v:
            argv += ["--grep", v, "--case-sensitive=false"]
        elif a == "-n" and v:
            n = v
        i += 2
    argv += ["-n", n]
    out = []
    for line in run(argv, timeout=15).splitlines():
        j = as_json(line, None)
        if not isinstance(j, dict):
            continue
        out.append(row(j))
    return out


def row(j):
    try:
        t = int(j.get("__REALTIME_TIMESTAMP", "0")) // 1000
    except ValueError:
        t = 0
    try:
        prio = int(j.get("PRIORITY", "6"))
    except ValueError:
        prio = 6
    return {"t": t, "prio": prio,
            "ident": j.get("SYSLOG_IDENTIFIER") or j.get("_COMM") or "",
            "unit": j.get("_SYSTEMD_UNIT") or j.get("_SYSTEMD_USER_UNIT") or j.get("UNIT") or "",
            "pid": j.get("_PID") or "", "msg": message(j.get("MESSAGE")).rstrip()}


def boot():
    t = run(["systemd-analyze", "time"], timeout=10)
    blame = []
    for line in run(["systemd-analyze", "blame", "--no-pager"], timeout=10).splitlines()[:12]:
        parts = line.split()
        if len(parts) >= 2:
            blame.append({"took": " ".join(parts[:-1]), "unit": parts[-1]})
    return {"summary": t.splitlines()[0].strip() if t else "", "blame": blame}


def main():
    a = sys.argv[1:]
    cmd = a[0] if a else ""
    if cmd == "units" and len(a) >= 2:
        print(json.dumps(units(a[1])))
    elif cmd == "show" and len(a) >= 3:
        print(json.dumps(show(a[1], a[2])))
    elif cmd == "timers" and len(a) >= 2:
        print(json.dumps(timers(a[1])))
    elif cmd == "logs":
        print(json.dumps(logs(a[1:])))
    elif cmd == "boot":
        print(json.dumps(boot()))
    else:
        print(json.dumps({"error": "usage: hestia.py units|show|timers|logs|boot …"}))
        sys.exit(2)


if __name__ == "__main__":
    main()

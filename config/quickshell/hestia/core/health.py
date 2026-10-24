#!/usr/bin/env python3
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# health.py — the machine's drives and firmware, as JSON on stdout.
#
#   disks       [{ id, model, serial, size, dev, devs, kind: nvme|ata|"",
#                  smart, failing, warnings: [], tempK, hours, usedPct,
#                  spareLeft, spareThresh, written, read, mediaErrors,
#                  unsafe, powerCycles, badSectors, attrsFailing,
#                  wcTempK, selftest, selftestLeft }]
#   selftest ID short|extended|abort
#               { ok, why } — a drive's own self-test started or stopped
#               (udisks; polkit asks once, as for opening a drive)
#   firmware    { installed, devices: [{ id, name, version, update, summary,
#                 reboot }] }
#
# The drives come from udisks, which reads SMART as root on everyone's
# behalf: no smartctl, no password. The numbers are passed on as they are;
# what they MEAN (good, worn, failing) is hestia.js' diskVerdict, where the
# tests can reach it. Standard library only, every command on a timeout.

import json
import shutil
import subprocess
import sys

UD = "org.freedesktop.UDisks2"


def run(argv, timeout=8):
    try:
        r = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout
    except (OSError, subprocess.SubprocessError):
        return 1, ""


def busctl_json(*args, timeout=8):
    code, out = run(["busctl", "--system", "--json=short"] + list(args), timeout)
    if code != 0 or not out.strip():
        return None
    try:
        return json.loads(out)
    except ValueError:
        return None


def val(v):
    # busctl's JSON wraps every value as { type, data }
    return v.get("data") if isinstance(v, dict) and "data" in v else v


def bytestr(v):
    # an "ay" — a NUL-terminated byte string, as a list of numbers
    v = val(v) or []
    return bytes(b for b in v if b).decode("utf-8", "replace") if isinstance(v, list) else ""


def disks():
    objs = busctl_json("call", UD, "/org/freedesktop/UDisks2", "org.freedesktop.DBus.ObjectManager", "GetManagedObjects")
    if not objs:
        return []
    objs = (objs.get("data") or [{}])[0]
    drives, blocks = {}, {}
    for path, ifaces in objs.items():
        if UD + ".Drive" in ifaces:
            drives[path] = ifaces
        b = ifaces.get(UD + ".Block")
        if b:
            blocks[path] = b
    out = []
    for path, ifaces in sorted(drives.items()):
        d = ifaces[UD + ".Drive"]
        devs = []
        whole = ""
        for bp, b in blocks.items():
            if val(b.get("Drive")) != path:
                continue
            dev = bytestr(b.get("Device"))
            if not dev:
                continue
            devs.append(dev)
            # the whole disk is the block that is not a partition
            if UD + ".Partition" not in objs.get(bp, {}) and (not whole or len(dev) < len(whole)):
                whole = dev
        r = {"id": path, "model": " ".join(x for x in [val(d.get("Vendor")) or "", val(d.get("Model")) or ""] if x).strip(),
             "serial": val(d.get("Serial")) or "", "size": val(d.get("Size")) or 0,
             "dev": whole, "devs": sorted(devs), "kind": "", "smart": False, "failing": False,
             "warnings": [], "tempK": 0, "hours": -1, "usedPct": -1, "spareLeft": -1, "spareThresh": -1,
             "written": -1, "read": -1, "mediaErrors": -1, "unsafe": -1, "powerCycles": -1,
             "badSectors": -1, "attrsFailing": -1, "wcTempK": 0, "selftest": "", "selftestLeft": -1}
        nv = ifaces.get(UD + ".NVMe.Controller")
        ata = ifaces.get(UD + ".Drive.Ata")
        if nv:
            r["kind"] = "nvme"
            r["smart"] = True
            r["warnings"] = [w for w in (val(nv.get("SmartCriticalWarning")) or []) if w]
            r["tempK"] = val(nv.get("SmartTemperature")) or 0
            r["hours"] = val(nv.get("SmartPowerOnHours"))
            r["selftest"] = val(nv.get("SmartSelftestStatus")) or ""
            r["selftestLeft"] = val(nv.get("SmartSelftestPercentRemaining"))
            a = busctl_json("call", UD, path, UD + ".NVMe.Controller", "SmartGetAttributes", "a{sv}", "0")
            if a:
                at = (a.get("data") or [{}])[0]
                r["usedPct"] = val(at.get("percent_used", {"data": -1}))
                r["spareLeft"] = val(at.get("avail_spare", {"data": -1}))
                r["spareThresh"] = val(at.get("spare_thresh", {"data": -1}))
                # NVMe counts data units of 512,000 bytes; udisks hands on bytes
                r["written"] = val(at.get("total_data_written", {"data": -1}))
                r["read"] = val(at.get("total_data_read", {"data": -1}))
                r["mediaErrors"] = val(at.get("media_errors", {"data": -1}))
                r["unsafe"] = val(at.get("unsafe_shutdowns", {"data": -1}))
                r["powerCycles"] = val(at.get("power_cycles", {"data": -1}))
                r["wcTempK"] = val(at.get("wctemp", {"data": 0}))
        elif ata and val(ata.get("SmartSupported")):
            r["kind"] = "ata"
            r["smart"] = bool(val(ata.get("SmartEnabled")))
            r["failing"] = bool(val(ata.get("SmartFailing")))
            r["tempK"] = round(val(ata.get("SmartTemperature")) or 0)
            secs = val(ata.get("SmartPowerOnSeconds")) or 0
            r["hours"] = secs // 3600 if secs else -1
            r["badSectors"] = val(ata.get("SmartNumBadSectors"))
            r["attrsFailing"] = val(ata.get("SmartNumAttributesFailing"))
            r["selftest"] = val(ata.get("SmartSelftestStatus")) or ""
            r["selftestLeft"] = val(ata.get("SmartSelftestPercentRemaining"))
        out.append(r)
    return out


def firmware():
    if not shutil.which("fwupdmgr"):
        return {"installed": False, "devices": []}
    # exit 2 is "no updates", with nothing on stdout
    code, outp = run(["fwupdmgr", "get-updates", "--json", "--no-unreported-check", "--no-metadata-check"], 30)
    devs = []
    try:
        j = json.loads(outp) if outp.strip() else {}
    except ValueError:
        j = {}
    for d in j.get("Devices", []):
        rel = (d.get("Releases") or [{}])[0]
        flags = rel.get("Flags") or []
        devs.append({"id": d.get("DeviceId", ""), "name": d.get("Name", ""), "version": d.get("Version", ""),
                     "update": rel.get("Version", ""), "summary": rel.get("Summary", ""),
                     "reboot": "needs-reboot" in flags or "needs-reboot" in (d.get("Flags") or [])})
    return {"installed": True, "devices": [x for x in devs if x["id"]]}


def selftest(drive, what):
    # the drive's own test, on the controller it has: NVMe or ATA
    iface = None
    objs = busctl_json("call", UD, "/org/freedesktop/UDisks2", "org.freedesktop.DBus.ObjectManager", "GetManagedObjects")
    ifaces = ((objs or {}).get("data") or [{}])[0].get(drive, {})
    for i in (UD + ".NVMe.Controller", UD + ".Drive.Ata"):
        if i in ifaces:
            iface = i
    if not iface:
        return {"ok": False, "why": "This drive has no self-test"}
    if what == "abort":
        argv = [iface, "SmartSelftestAbort", "a{sv}", "0"]
    elif what in ("short", "extended"):
        argv = [iface, "SmartSelftestStart", "sa{sv}", what, "0"]
    else:
        return {"ok": False, "why": "short, extended or abort"}
    try:
        r = subprocess.run(["busctl", "--system", "--allow-interactive-authorization=yes", "call", UD, drive] + argv,
                           capture_output=True, text=True, timeout=120)
    except (OSError, subprocess.SubprocessError):
        return {"ok": False, "why": "udisks did not answer"}
    if r.returncode == 0:
        return {"ok": True, "why": ""}
    err = (r.stderr.strip().splitlines() or [""])[-1]
    if "not authorized" in err.lower() or "dismissed" in err.lower():
        return {"ok": False, "why": "Permission was not given"}
    return {"ok": False, "why": err.split(": ", 1)[-1] or "The drive refused"}


def main():
    a = sys.argv[1:]
    cmd = a[0] if a else "disks"
    if cmd == "disks":
        print(json.dumps(disks()))
    elif cmd == "firmware":
        print(json.dumps(firmware()))
    elif cmd == "selftest" and len(a) > 2:
        print(json.dumps(selftest(a[1], a[2])))
    else:
        print(json.dumps({"error": "usage: health.py disks|firmware|selftest ID short|extended|abort"}))


if __name__ == "__main__":
    main()

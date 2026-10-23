#!/usr/bin/env python3
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# chronos' calendar backend (chronos/core/cal.py), against a calendar made
# here: delete finds an event by its exact UID, never takes a file that
# holds others, and never deletes for good when the trash says no (2026-10-23).
# Nothing reaches khal or gio: `run` is stood in for, and what it was asked
# is checked.

import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TMP = tempfile.mkdtemp(prefix="chronos-test-")
os.environ["XDG_CONFIG_HOME"] = os.path.join(TMP, "config")
os.environ["XDG_DATA_HOME"] = os.path.join(TMP, "data")
sys.path.insert(0, os.path.join(HERE, "..", "..", "chronos", "core"))
import cal  # noqa: E402

fails, count = [], 0


def eq(name, got, want):
    global count
    count += 1
    if got != want:
        fails.append("%s\n      want %r\n      got  %r" % (name, want, got))


def ics(*uids):
    ev = "".join("BEGIN:VEVENT\r\nUID:%s\r\nSUMMARY:x\r\nEND:VEVENT\r\n" % u for u in uids)
    return "BEGIN:VCALENDAR\r\n" + ev + "END:VCALENDAR\r\n"


asked = []
trash_ok = [True]


def fake_run(argv, timeout=20):
    asked.append(argv)
    if argv[:2] == ["gio", "trash"]:
        if not trash_ok[0]:
            return 1, "", "gio: Trashing on system internal mounts is not supported\n"
        os.remove(argv[-1])
    return 0, "", ""


cal.run = fake_run

try:
    cal.setup()
    d = cal.LOCAL_CAL
    files = {"a.ics": ics("abcdef"), "b.ics": ics("abc"), "many.ics": ics("one", "two"),
             "fold.ics": "BEGIN:VEVENT\r\nUID:long-\r\n uid\r\nEND:VEVENT\r\n"}
    for n, t in files.items():
        with open(os.path.join(d, n), "w") as f:
            f.write(t)
    left = lambda: sorted(os.listdir(d))

    eq("the exact UID, not one it starts", cal.delete("abc"), {"ok": True})
    eq("so b.ics went, a.ics stayed", left(), ["a.ics", "fold.ics", "many.ics"])
    eq("a folded UID line is read whole", cal.delete("long-uid"), {"ok": True})
    eq("a file with others is refused", "error" in cal.delete("one"), True)
    eq("and kept", "many.ics" in left(), True)
    trash_ok[0] = False
    r = cal.delete("abcdef")
    eq("a trash that says no is said", "Trashing" in r.get("error", ""), True)
    eq("and the file is left, not deleted", "a.ics" in left(), True)
    eq("nothing found", "error" in cal.delete("nope"), True)

    asked.clear()
    cal.new("personal", "2026-10-23", "2026-10-23", "-5 kg")
    eq("the title after --, never an option", asked[-1][-4:], ["--", "2026-10-23", "2026-10-23", "-5 kg"])
finally:
    shutil.rmtree(TMP, ignore_errors=True)

for f in fails:
    print("  FAIL  " + f)
print("  %d of %d chronos core checks %s" % (len(fails) if fails else count, count, "FAILED" if fails else "pass"))
sys.exit(1 if fails else 0)

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

import json
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TMP = tempfile.mkdtemp(prefix="chronos-test-")
# a home of its own: the local calendar lives in ~/Documents/Calendar,
# and a test must never write there (2026-10-28: it did, once)
os.environ["HOME"] = os.path.join(TMP, "home")
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


def fake_run(argv, timeout=20, input=None):
    asked.append(argv)
    if argv[:2] == ["gio", "trash"]:
        if not trash_ok[0]:
            return 1, "", "gio: Trashing on system internal mounts is not supported\n"
        (shutil.rmtree if os.path.isdir(argv[-1]) else os.remove)(argv[-1])
    return 0, "", ""


cal.run = fake_run

try:
    eq("the local calendar is in Documents", cal.LOCAL_CAL.endswith("/Documents/Calendar/Personal"), True)
    cal.setup()
    d = cal.LOCAL_CAL
    files = {"a.ics": ics("abcdef"), "b.ics": ics("abc"), "many.ics": ics("one", "two"),
             "fold.ics": "BEGIN:VEVENT\r\nUID:long-\r\n uid\r\nEND:VEVENT\r\n"}
    for n, t in files.items():
        with open(os.path.join(d, n), "w") as f:
            f.write(t)
    left = lambda: sorted(n for n in os.listdir(d) if n.endswith(".ics"))

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

    # ── events whole: the calendar window (2026-10-28) ──
    os.environ["TZ"] = "Europe/Berlin"
    import time
    time.tzset()
    eq("calendars named and colored", [(c["name"], c["title"], c["color"]) for c in cal.calendars()],
       [("Personal", "Personal", "#5b8fd9")])
    r = cal.save(json.dumps({"title": "Dentist, again; \\ x", "start": "2026-11-02 14:00", "end": "2026-11-02 15:30",
                             "location": "Clinic", "description": "line one\nline two", "alert": 15, "calendar": "personal"}))
    eq("saved", r.get("ok"), True)
    uid = r.get("uid", "")
    got = cal.get(uid)
    eq("read back", [got.get(k) for k in ("title", "start", "end", "allDay", "location", "description", "alert", "repeat")],
       ["Dentist, again; \\ x", "2026-11-02 14:00", "2026-11-02 15:30", False, "Clinic", "line one\nline two", 15, ""])
    text = open(os.path.join(d, os.listdir(d)[[n.startswith(uid[:8]) for n in os.listdir(d)].index(True)])).read()
    eq("a single event in UTC", "DTSTART:20261102T130000Z" in text, True)
    eq("escaped", "SUMMARY:Dentist\\, again\\; \\\\ x" in text, True)
    # weekly, all day: a date, the day after as DTEND
    r2 = cal.save('{"title": "Bins", "allDay": true, "start": "2026-11-03", "end": "2026-11-03", "repeat": "weekly"}')
    g2 = cal.get(r2["uid"])
    eq("all day, weekly", [g2["allDay"], g2["start"], g2["end"], g2["repeat"], g2["alert"]], [True, "2026-11-03", "2026-11-03", "weekly", None])
    # timed and repeating: the zone's wall clock, with its VTIMEZONE
    r3 = cal.save('{"title": "Standup", "start": "2026-11-02 09:30", "end": "2026-11-02 09:45", "repeat": "daily", "alert": 0}')
    p3 = [os.path.join(d, n) for n in os.listdir(d) if n.startswith(r3["uid"][:8])][0]
    t3 = open(p3).read()
    eq("a repeat keeps its zone", ["DTSTART;TZID=Europe/Berlin:20261102T093000" in t3, "BEGIN:VTIMEZONE" in t3,
                                   "RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU" in t3, "TRIGGER:PT0S" in t3], [True, True, True, True])
    eq("read back at its time", [cal.get(r3["uid"])["start"], cal.get(r3["uid"])["alert"]], ["2026-11-02 09:30", 0])
    # someone else's event: what the window does not edit stays
    other = ("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:theirs\r\nSEQUENCE:4\r\nDTSTART:20261105T100000Z\r\n"
             "DURATION:PT2H\r\nSUMMARY:Theirs\r\nRRULE:FREQ=WEEKLY;BYDAY=MO,WE\r\nATTENDEE;CN=Ann:mailto:ann@example.org\r\n"
             "BEGIN:VALARM\r\nTRIGGER:-PT1H\r\nACTION:AUDIO\r\nEND:VALARM\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n")
    with open(os.path.join(d, "theirs.ics"), "w") as f:
        f.write(other)
    g4 = cal.get("theirs")
    eq("their event read", [g4["start"], g4["end"], g4["repeat"], g4["alert"]], ["2026-11-05 11:00", "2026-11-05 13:00", "custom", 60])
    g4["title"] = "Ours now"
    g4["alert"] = None
    eq("changed", cal.save(json.dumps(g4)).get("ok"), True)
    t4 = open(os.path.join(d, "theirs.ics")).read()
    eq("kept what it does not edit", ["ATTENDEE;CN=Ann" in t4, "RRULE:FREQ=WEEKLY;BYDAY=MO,WE" in t4, "SEQUENCE:5" in t4,
                                      "VALARM" in t4, "DURATION" in t4, "SUMMARY:Ours now" in t4], [True, True, True, False, False, True])
    eq("a weekly on its own day is weekly", cal.repeat_of("FREQ=WEEKLY;BYDAY=TU;INTERVAL=1"), "weekly")
    eq("refused: ends first", "error" in cal.save('{"title": "x", "start": "2026-11-02 14:00", "end": "2026-11-02 13:00"}'), True)
    eq("refused: no title", "error" in cal.save('{"title": " ", "start": "2026-11-02 14:00"}'), True)
    long = "x" * 200 + "é" * 50
    eq("folded at 75 octets, whole characters", all(len(l.encode()) <= 75 for l in cal.fold("DESCRIPTION:" + long).split("\r\n")), True)
    eq("unfolded back", cal.unfold(cal.fold("DESCRIPTION:" + long))[0], "DESCRIPTION:" + long)

    # an account: vdirsyncer's pair and khal's calendar, marked, and gone again
    cal.shutil.which = lambda n: "/usr/bin/" + n
    asked.clear()
    r5 = cal.account("Work Cloud", "https://dav.example.org/", "me", "secret")
    eq("account made", [r5.get("ok"), r5.get("name")], [True, "work-cloud"])
    eq("password to the keyring, on stdin", [a[:2] for a in asked][0], ["secret-tool", "store"])
    eq("listed", cal.accounts(), [{"name": "work-cloud", "url": "https://dav.example.org/", "user": "me"}])
    khal = open(cal.KHAL_CONF).read()
    eq("khal's calendar inside [calendars]", khal.index("[[work-cloud]]") < khal.index("[locale]"), True)
    eq("unaccount", cal.unaccount("work-cloud"), {"ok": True})
    eq("no name is no account (not calendars/ itself)", "error" in cal.unaccount(""), True)
    eq("a line break stays inside the value", cal.quote("a\nb"), '"a b"')
    eq("gone from both", ["work-cloud" in open(cal.VDIR_CONF).read(), "work-cloud" in open(cal.KHAL_CONF).read()], [False, False])
    # colors, moving, copying, calendars of your own (2026-10-28)
    rc = cal.save(json.dumps({"title": "Lunch", "start": "2026-11-04 12:00", "end": "2026-11-04 13:00", "color": "Sand",
                              "url": "https://example.org/menu", "calendar": "Personal", "note": "n-123"}))
    eq("its Clio note kept", cal.get(rc["uid"])["note"], "n-123")
    eq("sand is tan to other apps", "COLOR:tan" in open([os.path.join(d, n) for n in os.listdir(d) if n.startswith(rc["uid"][:8])][0]).read(), True)
    eq("a color and a link kept", [cal.get(rc["uid"])["color"], cal.get(rc["uid"])["url"]], ["sand", "https://example.org/menu"])
    eq("its color found for the list", cal.event_colors().get(rc["uid"]), "sand")
    eq("moved an hour on, half an hour longer", [cal.shift(rc["uid"], 60, 90)["start"], cal.get(rc["uid"])["end"]],
       ["2026-11-04 13:00", "2026-11-04 14:30"])
    eq("all day moves by days", cal.shift(r2["uid"], 1, 1)["start"], "2026-11-04")
    cp = cal.copy(rc["uid"], 7)
    eq("a copy a week on, its own uid", [cal.get(cp["uid"])["start"], cp["uid"] != rc["uid"], cal.get(cp["uid"])["color"]],
       ["2026-11-11 13:00", True, "sand"])
    gone = cal.get(cp["uid"])
    os.remove([os.path.join(d, n) for n in os.listdir(d) if n.startswith(cp["uid"][:8])][0])
    eq("an undone delete puts it back", [cal.save(json.dumps(gone)).get("ok"), cal.get(cp["uid"])["title"]], [True, "Lunch"])
    nc = cal.newcal("Work things", "green")
    eq("a calendar of its own", [nc["name"], [c["title"] for c in cal.calendars()] ], ["Work-things", ["Personal", "Work things"]])
    eq("renamed and recolored", [cal.setcal("Work-things", "Work", "magenta")["ok"],
                                 next(c for c in cal.calendars() if c["name"] == "Work-things")["color"]], [True, "#b07cc6"])
    asked.clear()
    trash_ok[0] = True
    eq("deleted to the trash", cal.delcal("Work-things"), {"ok": True})
    eq("by gio", asked[-1][:2], ["gio", "trash"])
    # an online account first, on a machine with no calendar: none made of its own
    os.remove(cal.KHAL_CONF)
    cal.setup(local=False)
    eq("online first: no local calendar", ["[[personal]]" in open(cal.KHAL_CONF).read(), "default_calendar" in open(cal.KHAL_CONF).read(),
                                          "[calendars]" in open(cal.KHAL_CONF).read()], [False, False, True])
finally:
    shutil.rmtree(TMP, ignore_errors=True)

for f in fails:
    print("  FAIL  " + f)
print("  %d of %d chronos core checks %s" % (len(fails) if fails else count, count, "FAILED" if fails else "pass"))
sys.exit(1 if fails else 0)

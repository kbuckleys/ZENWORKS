#!/usr/bin/env python3
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# CLIO CORE TESTS — clio/core against a throwaway CLIO_DIR: notes kept and
# read back, attachments, and the lock (sealed on disk, unsealed only with
# the password, every sealed note carried across a password change).
#
#   python3 oracle/tests/clio-core.py

import json
import os
import shutil
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "clio", "core"))
sys.path.insert(0, os.path.join(ROOT, "morpheus", "py"))

TMP = tempfile.mkdtemp(prefix="clio-test-")
os.environ["CLIO_DIR"] = os.path.join(TMP, "clio")

import server  # noqa: E402

server.ROUNDS = 1000   # the real count takes a second a time
fails = []
count = 0


def eq(name, got, want):
    global count
    count += 1
    if got != want:
        fails.append("%s\n      want %r\n      got  %r" % (name, want, got))


def raises(name, fn, kind):
    global count
    count += 1
    try:
        fn()
    except server.ClioError as e:
        if e.kind != kind:
            fails.append("%s\n      want kind %s, got %s (%s)" % (name, kind, e.kind, e))
        return
    fails.append(name + "\n      expected a refusal")


try:
    s = server.Server()
    eq("nothing yet", s.load()["notes"], [])
    note = {"id": "n1", "kind": "note", "blocks": [{"k": "title", "h": "Hi"}], "created": 1, "modified": 2}
    s.save({"note": note})
    eq("kept and read back", [{k: v for k, v in n.items() if k != "_disk"} for n in s.load()["notes"]], [note])
    eq("with the time it was written", s.load()["notes"][0]["_disk"] > 0, True)
    raises("an id is a name, not a path", lambda: s.save({"note": {"id": "../x"}}), "failed")

    # attachments
    pic = os.path.join(TMP, "p.png")
    with open(pic, "wb") as f:
        f.write(b"\x89PNG....")
    b = s.attach({"id": "n1", "path": pic})
    eq("a picture is an image block", (b["k"], b["src"], b["size"]), ("image", "p.png", 8))
    eq("in the shared directory", os.path.exists(os.path.join(TMP, "clio", "Attachments", "p.png")), True)
    eq("a second is named apart", s.attach({"id": "n1", "path": pic})["src"], "p 2.png")
    eq("a sketch's place", s.attach_dir({"id": "n1", "name": "Sketch.png"})["src"], "Sketch.png")

    # the lock
    raises("no password, no unlock", lambda: s.unlock({"password": "x"}), "nopassword")
    raises("no key, no sealing", lambda: s.save({"note": dict(note, id="n2"), "seal": True}), "locked")
    s.password({"password": "pw1", "hint": "one"})
    res = s.save({"note": dict(note, id="n2"), "seal": True})
    on_disk = json.load(open(os.path.join(TMP, "clio", "Notes", "n2.json")))
    eq("sealed on disk: no blocks", "blocks" in on_disk, False)
    eq("and not readable", "Hi" in on_disk["sealed"], False)
    eq("the save says so", res["sealed"] == on_disk["sealed"], True)
    eq("unsealed with the key", s.unseal_note({"id": "n2"})["blocks"], note["blocks"])
    s.key = None
    raises("locked again", lambda: s.unseal_note({"id": "n2"}), "locked")
    raises("a wrong password", lambda: s.unlock({"password": "nope"}), "auth")
    s.unlock({"password": "pw1"})
    eq("the right one", s.unseal_note({"id": "n2"})["blocks"], note["blocks"])
    eq("the hint is said", s.load()["hint"], "one")
    raises("changing it needs the old one", lambda: s.password({"password": "pw2", "old": "bad"}), "auth")
    eq("changed: every sealed note carried over", s.password({"password": "pw2", "old": "pw1"})["resealed"], 1)
    s.key = None
    raises("the old password is gone", lambda: s.unlock({"password": "pw1"}), "auth")
    s.unlock({"password": "pw2"})
    eq("and the note still opens", s.unseal_note({"id": "n2"})["blocks"], note["blocks"])
    # a sealed text tampered with is refused before decrypting
    j = json.load(open(os.path.join(TMP, "clio", "Notes", "n2.json")))
    v, mac, c = j["sealed"].split(":")
    raises("tampered", lambda: server.unseal(s.key, v + ":" + mac + ":" + c[:-8] + "AAAAAAA="), "auth")

    # export and removal
    out = os.path.join(TMP, "out", "Hi.md")
    s.export({"path": out, "text": "# Hi\n", "files": [["p.png", os.path.join(TMP, "out", "Hi", "p.png")]]})
    eq("exported", open(out).read(), "# Hi\n")
    eq("with its pictures", os.path.exists(os.path.join(TMP, "out", "Hi", "p.png")), True)
    # a file used again is the same file, and goes only with the last note
    # that uses it
    keep = s.attach({"id": "n1", "path": pic})
    again = s.attach({"id": "n3", "path": os.path.join(TMP, "clio", "Attachments", keep["src"])})
    eq("reused, not copied", again["src"], keep["src"])
    s.save({"note": {"id": "n1", "blocks": [keep]}})
    s.save({"note": {"id": "n4", "blocks": [{"k": "body", "h": "x"}, again]}, "seal": True})
    eq("a locked note says what it uses", json.load(open(os.path.join(TMP, "clio", "Notes", "n4.json")))["uses"], [keep["src"]])
    att = lambda f: os.path.exists(os.path.join(TMP, "clio", "Attachments", f))
    s.remove({"id": "n1"})
    eq("what another note uses stays", (os.path.exists(os.path.join(TMP, "clio", "Notes", "n1.json")), att(keep["src"])), (False, True))
    s.remove({"id": "n4"})
    eq("and goes with the last", att(keep["src"]), False)

    # the sync guard: a file changed since it was read is not written over
    s.save({"note": {"id": "n5", "blocks": [{"k": "title", "h": "A"}]}})
    seen = [n for n in s.load()["notes"] if n["id"] == "n5"][0]["_disk"]
    first = s.save({"note": {"id": "n5", "blocks": [{"k": "title", "h": "B"}]}, "expect": seen})
    eq("saved over what it read", ("conflict" in first, first["mtime"] > 0), (False, True))
    p5 = os.path.join(TMP, "clio", "Notes", "n5.json")
    json.dump({"id": "n5", "blocks": [{"k": "title", "h": "There"}]}, open(p5, "w"))
    os.utime(p5, (first["mtime"] + 5, first["mtime"] + 5))
    clash = s.save({"note": {"id": "n5", "blocks": [{"k": "title", "h": "Here"}]}, "expect": first["mtime"]})
    eq("changed elsewhere: both kept", (clash.get("conflict"), clash["disk"]["blocks"][0]["h"], clash["copy"]["blocks"][0]["h"],
                                        json.load(open(p5))["blocks"][0]["h"]), (True, "There", "Here (this machine)", "There"))

    # notes and entries apart: Notes/ and Journals/, and the old one directory split
    s.save({"note": {"id": "e1", "kind": "entry", "blocks": []}})
    eq("an entry in Journals", os.path.exists(os.path.join(TMP, "clio", "Journals", "e1.json")), True)
    os.makedirs(os.path.join(TMP, "clio", "notes"))
    json.dump({"id": "e2", "kind": "entry"}, open(os.path.join(TMP, "clio", "notes", "e2.json"), "w"))
    json.dump({"id": "n7", "kind": "note"}, open(os.path.join(TMP, "clio", "notes", "n7.json"), "w"))
    server.split()
    eq("split by kind", (os.path.exists(os.path.join(TMP, "clio", "Journals", "e2.json")), os.path.exists(os.path.join(TMP, "clio", "Notes", "n7.json")),
                         os.path.exists(os.path.join(TMP, "clio", "notes"))), (True, True, False))
    s.remove({"id": "e2"})
    eq("removed from where it is", os.path.exists(os.path.join(TMP, "clio", "Journals", "e2.json")), False)

    # the old layout, a directory per note, gathered into the shared one
    old = os.path.join(TMP, "clio", "attachments", "n9")
    os.makedirs(old)
    open(os.path.join(old, "p.png"), "w").write("old")
    s.save({"note": {"id": "n9", "blocks": [{"k": "image", "src": "n9/p.png"}]}})
    s.save({"note": {"id": "n8", "blocks": [{"k": "image", "src": "n9/p.png"}]}, "seal": True})
    server.gather()
    moved = json.load(open(os.path.join(TMP, "clio", "Notes", "n9.json")))["blocks"][0]["src"]
    eq("moved and pointed at", (att(moved), moved.startswith("n9/"), os.path.exists(os.path.join(TMP, "clio", "attachments"))), (True, False, False))
    eq("a locked note put right when opened", s.unseal_note({"id": "n8"})["blocks"][0]["src"], moved)
finally:
    shutil.rmtree(TMP, ignore_errors=True)

for f in fails:
    print("  FAIL  " + f)
print("  %d of %d clio core checks %s" % (len(fails) if fails else count, count, "FAILED" if fails else "pass"))
sys.exit(1 if fails else 0)

#!/usr/bin/env python3
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# QMLLINT, AGAINST WHAT WAS ALREADY THERE (2026-10-18).
#
#   scripts/lintgate.py           lint every .qml, list what is NEW
#   scripts/lintgate.py --accept  take today's warnings as the baseline
#
# qmllint says ~500 things about this suite, nearly all of them the price of
# dynamic QML (a property typed `Item` holding something richer). Read once,
# they are noise; what matters is a warning that was not there yesterday —
# above all after an update. A Qt or quickshell release that adds a property
# turns one of ours into a silent override (ViewerWindow's own `fullscreen`
# now hides FloatingWindow's), and nothing else would say so.
#
# The baseline (scripts/lint-baseline.txt) is file + kind + message with the
# line numbers taken out, counted, so moving code is not news and a second
# copy of a known warning is. New warnings of the kinds that mean something
# changed underneath (BREAKING below) fail preflight; the rest are listed.

import collections, json, os, re, subprocess, sys, tempfile

# LINTGATE_ROOT: a scratch copy of the config, to test the gate itself
ROOT = os.environ.get("LINTGATE_ROOT") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASELINE = os.path.join(ROOT, "scripts", "lint-baseline.txt")
QMLLINT = "/usr/lib/qt6/bin/qmllint"

# idioms this suite uses on purpose: `root.revision;` to depend on a counter,
# comma expressions in tight loops
IGNORED = {"comma", "confusing-expression-statement"}
# what an update underneath (Qt, quickshell) or a broken edit looks like
BREAKING = {"property-override", "unresolved-type", "incompatible-type",
            "uncreatable-type", "required", "syntax.duplicate-ids", "syntax"}


def lint():
    files = []
    for d, _, fs in os.walk(ROOT):
        if "/oracle/qmltests" in d or "/.git" in d:
            continue
        files += [os.path.join(d, f) for f in fs if f.endswith(".qml")]
    files.sort()
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as t:
        out = t.name
    subprocess.run([QMLLINT, "-I", "/usr/lib/qt6/qml", "--unqualified", "disable",
                    "--import", "disable", "--compiler", "disable", "--json", out] + files,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    with open(out) as fh:
        data = json.load(fh)
    os.unlink(out)
    seen = collections.Counter()
    for f in data.get("files", []):
        rel = os.path.relpath(f["filename"], ROOT)
        for w in f.get("warnings", []):
            kind = w.get("id") or "?"
            if kind in IGNORED:
                continue
            msg = re.sub(r"\d+:\d+", "N:N", w.get("message", "").split("\n")[0]).strip()
            seen[(rel, kind, msg)] += 1
    return seen


def read_baseline():
    base = collections.Counter()
    if os.path.exists(BASELINE):
        for line in open(BASELINE, encoding="utf-8"):
            p = line.rstrip("\n").split("\t")
            if len(p) == 4 and p[0].isdigit():
                base[(p[1], p[2], p[3])] = int(p[0])
    return base


def main():
    if not os.path.exists(QMLLINT):
        print("   qmllint not found — skipped")
        return 0
    seen = lint()
    if "--accept" in sys.argv:
        with open(BASELINE, "w", encoding="utf-8") as fh:
            fh.write("# scripts/lintgate.py --accept — count, file, kind, message\n")
            for (rel, kind, msg), n in sorted(seen.items()):
                fh.write(f"{n}\t{rel}\t{kind}\t{msg}\n")
        print(f"   baseline: {sum(seen.values())} warnings in {len({k[0] for k in seen})} files")
        return 0
    base = read_baseline()
    if not base:
        print("   no baseline yet — run scripts/lintgate.py --accept")
        return 0
    new = [(k, n - base.get(k, 0)) for k, n in seen.items() if n > base.get(k, 0)]
    fixed = sum(max(0, n - seen.get(k, 0)) for k, n in base.items())
    bad = [x for x in new if x[0][1] in BREAKING]
    for (rel, kind, msg), n in sorted(new, key=lambda x: (x[0][1] not in BREAKING, x[0])):
        mark = "!!" if kind in BREAKING else "  "
        print(f" {mark} {rel}  [{kind}]{' x' + str(n) if n > 1 else ''}  {msg[:140]}")
    print(f"   {len(new)} new ({len(bad)} breaking), {fixed} gone since the baseline")
    if new and not bad:
        print("   (listed only; once read, scripts/lintgate.py --accept)")
    return 1 if bad else 0


sys.exit(main())

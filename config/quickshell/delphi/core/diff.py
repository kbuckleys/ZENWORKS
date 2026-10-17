# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# DIFFS — git's unified diff read into files, hunks and lines; and the other
# way, a chosen subset of those lines written back out as a patch git apply
# will take. The second half is what hunk and line staging are.
#
# THE ONE RULE OF A PARTIAL PATCH. A patch is checked against one side of the
# diff: the side it is applied TO. That side must come out of the edit
# exactly as it is on disk, line for line, or git apply refuses. So:
#
#   forward  (stage a part of the unstaged diff; applied to the index, the
#            diff's OLD side): an unchosen + is dropped (it never happened),
#            an unchosen - becomes context (the line stays).
#   reverse  (unstage a part of the staged diff; discard a part of the
#            working tree — both git apply -R, matched against the NEW side):
#            an unchosen - is dropped, an unchosen + becomes context.
#
# Counts in each @@ header are rewritten to match, and git apply also gets
# --recount, so a miscount can never be the reason a patch fails.
#
# "\ No newline at end of file" belongs to the line before it. It travels with
# that line, whatever the line becomes.

import difflib
import re

HUNK = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@ ?(.*)$")


def unquote(s):
    """git's C-style quoting ("a\\tb", "\\303\\251") back to the path. Paths
    are only quoted when they hold a byte core.quotepath=false still
    escapes: a control character, a quote or a backslash."""
    if len(s) < 2 or s[0] != '"' or s[-1] != '"':
        return s
    out = bytearray()
    i, body = 0, s[1:-1]
    esc = {"a": 7, "b": 8, "t": 9, "n": 10, "v": 11, "f": 12, "r": 13,
           '"': 34, "\\": 92}
    while i < len(body):
        c = body[i]
        if c == "\\" and i + 1 < len(body):
            n = body[i + 1]
            if n in esc:
                out.append(esc[n]); i += 2; continue
            if n.isdigit():
                out.append(int(body[i + 1:i + 4], 8)); i += 4; continue
        out += c.encode("utf-8")
        i += 1
    return out.decode("utf-8", "replace")


def _strip_ab(p):
    p = unquote(p)
    return p[2:] if p[:2] in ("a/", "b/") else p


def _git_line_paths(rest):
    # "a/x b/x" — or quoted. With no rename the two halves are the same path,
    # so an unquoted line is split down its middle; a rename is settled by
    # its own "rename from/to" lines, which overwrite this guess.
    rest = rest.strip()
    if rest.startswith('"'):
        m = re.match(r'("(?:[^"\\]|\\.)*")\s+(.*)$', rest)
        if m:
            return _strip_ab(m.group(1)), _strip_ab(m.group(2))
    n = (len(rest) - 1) // 2
    return _strip_ab(rest[:n]), _strip_ab(rest[n + 1:])


def parse(text):
    """A whole `git diff` (any number of files) → list of file dicts:
       {old, new, status, binary, header:[raw lines], hunks:[...]}
    Each hunk: {oldStart, oldCount, newStart, newCount, section, lines}.
    Each line: {t: ' '|'+'|'-', text, old, new, noeol?}."""
    files = []
    f = h = None
    oldn = newn = 0
    for raw in text.split("\n"):
        if raw.startswith("diff --git ") or raw.startswith("diff --cc ") \
                or raw.startswith("diff --combined "):
            a, b = _git_line_paths(raw.split(" ", 2)[2]) \
                if raw.startswith("diff --git ") else (None, raw.split(" ", 2)[2])
            f = {"old": a, "new": b, "status": "modified", "binary": False,
                 "header": [raw], "hunks": []}
            if raw.startswith("diff --c"):
                f["combined"] = True
            files.append(f)
            h = None
            continue
        if f is None:
            continue
        if h is None or not (raw[:1] in (" ", "+", "-", "\\") or raw == ""):
            m = HUNK.match(raw)
            if m:
                h = {"oldStart": int(m.group(1)),
                     "oldCount": int(m.group(2)) if m.group(2) is not None else 1,
                     "newStart": int(m.group(3)),
                     "newCount": int(m.group(4)) if m.group(4) is not None else 1,
                     "section": m.group(5), "lines": []}
                oldn, newn = h["oldStart"], h["newStart"]
                f["hunks"].append(h)
                continue
            if h is None:
                _file_header(f, raw)
                continue
        # inside a hunk
        if raw == "":
            continue   # the split's own trailing empty string
        t = raw[0]
        if t == "\\":
            if h["lines"]:
                h["lines"][-1]["noeol"] = True
            continue
        line = {"t": t, "text": raw[1:]}
        if t == " ":
            line["old"], line["new"] = oldn, newn
            oldn += 1; newn += 1
        elif t == "-":
            line["old"] = oldn; oldn += 1
        elif t == "+":
            line["new"] = newn; newn += 1
        h["lines"].append(line)
    for f in files:
        _words(f)
    return files


def _file_header(f, raw):
    f["header"].append(raw)
    if raw.startswith("new file mode"):
        f["status"] = "added"
    elif raw.startswith("deleted file mode"):
        f["status"] = "deleted"
    elif raw.startswith("rename from "):
        f["status"] = "renamed"; f["old"] = unquote(raw[12:])
    elif raw.startswith("rename to "):
        f["new"] = unquote(raw[10:])
    elif raw.startswith("copy from "):
        f["status"] = "copied"; f["old"] = unquote(raw[10:])
    elif raw.startswith("copy to "):
        f["new"] = unquote(raw[8:])
    elif raw.startswith("Binary files ") or raw == "GIT binary patch":
        f["binary"] = True
    elif raw.startswith("old mode ") or raw.startswith("new mode "):
        if f["status"] == "modified":
            f["status"] = "mode"
    elif raw.startswith("Submodule ") or raw.startswith("+Subproject"):
        f["submodule"] = True


# ── the words that changed inside a changed line ────────────────────────
# A run of - lines followed by a run of + lines is one edit; its lines are
# paired in order and diffed by word, so a renamed variable lights one word
# and not a whole line. Long lines and lopsided runs are left whole: the
# highlighting is a reading aid, and past these sizes it stops being one.
WORD = re.compile(r"\w+|\s+|[^\w\s]")


def _words(f):
    for h in f["hunks"]:
        ls = h["lines"]
        i = 0
        while i < len(ls):
            if ls[i]["t"] != "-":
                i += 1; continue
            j = i
            while j < len(ls) and ls[j]["t"] == "-":
                j += 1
            k = j
            while k < len(ls) and ls[k]["t"] == "+":
                k += 1
            dels, adds = ls[i:j], ls[j:k]
            if adds and len(dels) <= 40 and len(adds) <= 40:
                for a, b in zip(dels, adds):
                    if len(a["text"]) <= 400 and len(b["text"]) <= 400:
                        sa, sb = _spans(a["text"], b["text"])
                        if sa is not None:
                            a["spans"], b["spans"] = sa, sb
            i = k


def _spans(a, b):
    ta, tb = WORD.findall(a), WORD.findall(b)
    sm = difflib.SequenceMatcher(None, ta, tb, autojunk=False)
    if sm.ratio() < 0.3:
        return None, None   # mostly different: whole-line color says it
    pa, pb = _offsets(ta), _offsets(tb)
    sa, sb = [], []
    for op, i1, i2, j1, j2 in sm.get_opcodes():
        if op == "equal":
            continue
        if i2 > i1:
            sa.append([pa[i1], pa[i2]])
        if j2 > j1:
            sb.append([pb[j1], pb[j2]])
    return sa, sb


def _offsets(toks):
    o, n = [0], 0
    for t in toks:
        n += len(t); o.append(n)
    return o


# ── writing a patch back ────────────────────────────────────────────────
def build(f, chosen, reverse=False):
    """The patch that applies only the chosen lines of file f.
    chosen: {hunkIndex: None | iterable of line indexes} — None takes the
    whole hunk. Returns patch text, or "" when nothing chosen changes
    anything."""
    out = []
    shift = 0   # how far earlier partial hunks moved the new side
    for hi, h in enumerate(f["hunks"]):
        if hi not in chosen:
            continue
        pick = chosen[hi]
        pick = None if pick is None else set(pick)
        lines, changes = [], 0

        def put(l, as_change):
            nonlocal changes
            if as_change:
                lines.append(l["t"] + l["text"]); changes += 1
            else:
                lines.append(" " + l["text"])
            if l.get("noeol"):
                lines.append("\\ No newline at end of file")

        for block in _blocks(h["lines"]):
            if isinstance(block, dict):
                put(block, False)
                continue
            dels = [(i, l) for i, l in block if l["t"] == "-"]
            adds = [(i, l) for i, l in block if l["t"] == "+"]
            if pick is None:
                for _, l in dels + adds:
                    put(l, True)
                continue
            # The side being applied to keeps its unchosen lines as context;
            # the other side's unchosen lines never happened. A chosen line
            # of the other side goes right after its partner — the k-th
            # deletion pairs with the k-th addition — so replacing line 11
            # alone lands where line 11 was, not after the whole block.
            keep, other = (adds, dels) if reverse else (dels, adds)
            for k, (i, l) in enumerate(keep):
                put(l, i in pick)
                if k < len(other) and other[k][0] in pick:
                    put(other[k][1], True)
            for i, l in other[len(keep):]:
                if i in pick:
                    put(l, True)
        if not changes:
            continue
        oc = sum(1 for s in lines if s[:1] in (" ", "-"))
        nc = sum(1 for s in lines if s[:1] in (" ", "+"))
        os_ = h["oldStart"]
        ns = h["newStart"] if reverse else max(os_ + shift, 0)
        if oc == 0 and not reverse:
            ns = os_ + shift + 1 if os_ else 1
        out.append(f"@@ -{os_},{oc} +{ns},{nc} @@")
        out += lines
        shift += nc - oc
    if not out:
        return ""
    return "\n".join(_head(f) + out) + "\n"


def _blocks(lines):
    """A hunk's lines as context lines (dicts) and change blocks (lists of
    (index, line) — a run of - and + with no context between)."""
    out, run = [], []
    for i, l in enumerate(lines):
        if l["t"] == " ":
            if run:
                out.append(run); run = []
            out.append(l)
        else:
            run.append((i, l))
    if run:
        out.append(run)
    return out


def _head(f):
    # Only the lines git apply reads: the diff --git line, modes, and ---/+++.
    # index lines carry blob ids that a partial patch no longer matches.
    keep = []
    for l in f["header"]:
        if l.startswith(("diff --git", "new file mode", "deleted file mode",
                         "old mode", "new mode", "--- ", "+++ ")):
            keep.append(l)
    return keep


def whole(f, reverse=False):
    return build(f, {i: None for i in range(len(f["hunks"]))}, reverse)


def as_modification(f):
    """A new file's diff, reworded as an edit of an empty file. An
    intent-to-add entry (git add -N) is an EMPTY file in the index, and only
    a modification patch applies to it — "new file" says the path must not
    exist yet, which for an i-t-a path it already does."""
    g = dict(f)
    p = f["new"]
    hdr = []
    for l in f["header"]:
        if l.startswith("new file mode"):
            continue
        if l.startswith("--- "):
            l = "--- a/" + p
        hdr.append(l)
    g["header"] = hdr
    g["status"] = "modified"
    return g


def page(files, start_line=0, budget=4000):
    """A diff too long to send at once, cut into pages by line count. Returns
    (files_slice, next_start or None); hunks are never split, so a page can
    run over its budget by at most one hunk."""
    out, n, seen = [], 0, 0
    for f in files:
        g = dict(f); g["hunks"] = []
        g["firstLine"] = seen
        for h in f["hunks"]:
            size = len(h["lines"]) + 1
            if seen >= start_line:
                if n and n + size > budget:
                    if g["hunks"]:
                        out.append(g)
                    return out, seen
                g["hunks"].append(h)
                n += size
            seen += size
        if g["hunks"] or (not f["hunks"] and seen >= start_line):
            out.append(g)
    return out, None

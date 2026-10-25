.pragma library
// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// DELPHI'S PURE HALF — what the windows do with the daemon's answers before
// drawing them: a status into the rows of the Changes list, a diff into the
// rows of a diff view, a dragged range of rows into the lines to stage, a
// commit's age into words. No git here (that is delphi/core), no QML state;
// tested by oracle/tests/delphi.js.

// ── THE CHANGES LIST ────────────────────────────────────────────────────
// What each kind of change is called, and the git state terminus draws it
// as (terminus.js gitMark / gitInk: its letter and its ink) — so a file
// reads the same in delphi's list as beside its name in terminus and in
// plato's tree. A staged file is "staged" whatever was done to it, as
// terminus has it; the word says what.
var WORDS = {
  modified: "modified", typechange: "type changed", added: "added", deleted: "deleted",
  renamed: "renamed", copied: "copied", untracked: "new", conflict: "conflict"
};

function stateOf(area, kind) {
  if (area === "conflict") return "conflict";
  if (area === "staged") return "staged";
  if (kind === "untracked") return "untracked";
  if (kind === "deleted") return "deleted";
  return "modified";
}

// The sections of the Changes list, in the order they are worked through:
// conflicts first (nothing else can be committed while they stand), then
// what is not staged, then what is. Each row: {area, sec, path, from, kind,
// state, word, how, dir, name}. Untracked files join the unstaged section — "new"
// is one more kind of change waiting to be staged, not a separate chore.
function sections(st) {
  if (!st) return [];
  var out = [];
  function row(area, e, kind) {
    var p = String(e.path);
    var cut = p.lastIndexOf("/", p.length - 2);
    return { area: area, sec: area === "untracked" ? "unstaged" : area, path: p, from: e.from || "",
             kind: kind, state: stateOf(area, kind), word: WORDS[kind] || String(kind || ""), how: e.how || "",
             dir: cut >= 0 ? p.slice(0, cut + 1) : "", name: cut >= 0 ? p.slice(cut + 1) : p };
  }
  var conf = (st.conflicts || []).map(function (e) { return row("conflict", e, "conflict"); });
  var uns = (st.unstaged || []).map(function (e) { return row("unstaged", e, e.kind); })
    .concat((st.untracked || []).map(function (e) { return row("untracked", e, "untracked"); }));
  uns.sort(byPath);
  var stg = (st.staged || []).map(function (e) { return row("staged", e, e.kind); });
  stg.sort(byPath);
  if (conf.length) out.push({ id: "conflict", title: "Conflicts", rows: conf });
  out.push({ id: "unstaged", title: "Changes", rows: uns });
  out.push({ id: "staged", title: "Staged", rows: stg });
  return out;
}

function byPath(a, b) { return a.path < b.path ? -1 : a.path > b.path ? 1 : 0; }

// One flat list for the ListView: a head row per section, then its files.
// The flat index is what the cursor moves over; heads are skipped by it.
function flatten(secs) {
  var out = [];
  for (var i = 0; i < secs.length; i++) {
    var s = secs[i];
    out.push({ head: true, id: s.id, title: s.title, count: s.rows.length });
    for (var j = 0; j < s.rows.length; j++) out.push(s.rows[j]);
  }
  return out;
}

// Where the cursor should be after the list changed under it: the same file
// in the same section if it is still there; else — it was just staged, or
// discarded — the row now at the same place in that section, because that
// is where the work is (following the file into Staged would make staging
// a list one by one a chase); else the nearest file row.
function reseat(rows, want, at) {
  if (want) {
    for (var i = 0; i < rows.length; i++)
      if (!rows[i].head && rows[i].path === want.path && rows[i].sec === want.sec) return i;
  }
  var n = rows.length;
  if (n === 0) return -1;
  var k = Math.max(0, Math.min(n - 1, at));
  for (var d = 0; d < n; d++) {
    if (k + d < n && !rows[k + d].head && (!want || rows[k + d].sec === want.sec)) return k + d;
    if (k - d >= 0 && !rows[k - d].head && (!want || rows[k - d].sec === want.sec)) return k - d;
  }
  for (var e = 0; e < n; e++) if (!rows[e].head) return e;
  return -1;
}

// The same sections as a TREE: each section's files under their
// directories, as terminus and plato draw a tree (terminus/EntryRow — its
// guides read `guide`, the mask of ancestor columns whose branch carries on
// below, worked out as morpheus/FileTree works it out). A directory holding
// one directory and nothing else is folded into it ("config/quickshell"),
// as an editor's file tree folds them. Directories first, then files, each
// by name. A directory row: { isDir: true, sec, area, path (its own, no
// slash), name, depth, guide, expanded, key, count, paths (every file under
// it), states (theirs) }. A file row is the section's row with depth and
// guide. `closed`: { key: true } for directories put away; key = sec +
// ":" + path.
function treeRows(secs, closed) {
  closed = closed || {};
  var out = [];
  function lower(x) { return String(x).toLowerCase(); }
  function byName(a, b) { return lower(a.name) < lower(b.name) ? -1 : lower(a.name) > lower(b.name) ? 1 : 0; }
  for (var i = 0; i < secs.length; i++) {
    var s = secs[i];
    out.push({ head: true, id: s.id, title: s.title, count: s.rows.length });
    var top = { dirs: {}, files: [] };
    for (var j = 0; j < s.rows.length; j++) {
      var r = s.rows[j], parts = String(r.path).replace(/\/$/, "").split("/"), node = top;
      for (var k = 0; k < parts.length - 1; k++) {
        if (!node.dirs[parts[k]]) node.dirs[parts[k]] = { name: parts[k], dirs: {}, files: [] };
        node = node.dirs[parts[k]];
      }
      node.files.push(r);
    }
    walk(s, top, "", 0, 0);
  }
  function under(node, acc) {
    for (var f = 0; f < node.files.length; f++) acc.push(node.files[f]);
    for (var d in node.dirs) under(node.dirs[d], acc);
    return acc;
  }
  function walk(s, node, prefix, depth, anc) {
    var dirs = [];
    for (var d in node.dirs) {
      var n = node.dirs[d], name = n.name;
      // fold a chain of lone directories into one row
      while (n.files.length === 0 && Object.keys(n.dirs).length === 1) {
        n = n.dirs[Object.keys(n.dirs)[0]];
        name += "/" + n.name;
      }
      dirs.push({ name: name, node: n });
    }
    dirs.sort(byName);
    var files = node.files.slice().sort(byName);
    var all = dirs.length + files.length;
    for (var x = 0; x < all; x++) {
      var mine = x === all - 1 ? anc : (anc | (1 << depth));
      var guide = depth > 0 ? mine : -1;
      if (x < dirs.length) {
        var e = dirs[x], path = prefix + e.name, key = s.id + ":" + path;
        var inside = under(e.node, []);
        out.push({ isDir: true, sec: s.id, area: s.id, path: path, name: e.name, depth: depth, guide: guide,
                   expanded: !closed[key], key: key, count: inside.length,
                   paths: inside.map(function (q) { return q.path; }),
                   states: inside.map(function (q) { return q.state; }),
                   untracked: inside.filter(function (q) { return q.area === "untracked"; }).map(function (q) { return q.path; }) });
        if (!closed[key]) walk(s, e.node, path + "/", depth + 1, mine);
      } else {
        out.push(Object.assign({}, files[x - dirs.length], { depth: depth, guide: guide }));
      }
    }
  }
  return out;
}

function nextFile(rows, at, d) {
  for (var i = at + d; i >= 0 && i < rows.length; i += d)
    if (!rows[i].head) return i;
  return at;
}

// ── THE DIFF VIEW ───────────────────────────────────────────────────────
// A diff (files → hunks → lines) as the rows a ListView draws: one per file
// head (only when there is more than one file), one per hunk head, one per
// line. Every line row knows its file, hunk and line index — the address
// staging sends back — and its two line numbers.
function diffRows(files) {
  var out = [];
  var many = files.length > 1;
  for (var fi = 0; fi < files.length; fi++) {
    var f = files[fi];
    if (many || f.binary || f.hunks.length === 0)
      out.push({ kind: "file", fi: fi, path: f.new || f.old, from: f.old !== f.new ? f.old : "",
                 status: f.status, binary: !!f.binary });
    for (var hi = 0; hi < f.hunks.length; hi++) {
      var h = f.hunks[hi];
      out.push({ kind: "hunk", fi: fi, hi: hi, text: hunkLabel(h), section: h.section || "" });
      for (var li = 0; li < h.lines.length; li++) {
        var l = h.lines[li];
        out.push({ kind: "line", fi: fi, hi: hi, li: li, t: l.t, text: l.text,
                   old: l.old === undefined ? 0 : l.old, nu: l["new"] === undefined ? 0 : l["new"],
                   spans: l.spans || null, noeol: !!l.noeol });
      }
    }
  }
  return out;
}

function hunkLabel(h) {
  var a = h.oldCount === 1 ? "line " + h.oldStart : "lines " + h.oldStart + "–" + (h.oldStart + Math.max(0, h.oldCount - 1));
  if (h.oldCount === 0) a = "after line " + h.oldStart;
  return a;
}

// The rows from..to (either order) as the daemon's `chosen`: {hunk: [line
// indexes]} of the CHANGED lines in the range — context is never chosen, it
// is never a change. A range that covers a whole hunk's changes still names
// them one by one; the patch is the same.
function chosenIn(rows, from, to) {
  var a = Math.min(from, to), b = Math.max(from, to);
  var out = {};
  var any = false;
  for (var i = Math.max(0, a); i <= b && i < rows.length; i++) {
    var r = rows[i];
    if (r.kind === "line" && r.t !== " ") {
      (out[r.hi] = out[r.hi] || []).push(r.li);
      any = true;
    } else if (r.kind === "hunk" && a === b) {
      // a hunk head alone: the whole hunk
      out[r.hi] = null;
      any = true;
    }
  }
  return any ? out : null;
}

// The hunk a row belongs to — what `s` stages when no lines are picked.
function hunkAt(rows, i) {
  if (i < 0 || i >= rows.length) return -1;
  var r = rows[i];
  return r.kind === "file" ? -1 : r.hi;
}

// Which rows are changes, for the cursor's j/k over changes only.
function nextChange(rows, at, d) {
  var i = at + d;
  while (i >= 0 && i < rows.length && rows[i].kind === "line" && rows[i].t === " ") i += d;
  // and past the run it lands in, to its start (going down) — one press per
  // change, not per changed line
  if (i < 0 || i >= rows.length) return at;
  while (rows[i].kind !== "line" || rows[i].t === " ") {
    i += d;
    if (i < 0 || i >= rows.length) return at;
  }
  return i;
}

function diffStats(files) {
  var add = 0, del = 0;
  for (var fi = 0; fi < (files || []).length; fi++)
    for (var hi = 0; hi < files[fi].hunks.length; hi++) {
      var ls = files[fi].hunks[hi].lines;
      for (var li = 0; li < ls.length; li++) {
        if (ls[li].t === "+") add++;
        else if (ls[li].t === "-") del++;
      }
    }
  return { added: add, deleted: del };
}

// ── HISTORY ─────────────────────────────────────────────────────────────
// The graph's colors, by the daemon's color number. Slot names, again.
var LANES = ["cyan", "magenta", "green", "yellow", "blue", "red", "sand", "pink"];
function laneInk(n) { return LANES[((n % LANES.length) + LANES.length) % LANES.length]; }

function short(sha) { return String(sha || "").slice(0, 7); }

// Ages as a person says them: "now", "4 min", "3 h", "yesterday", "5 d",
// then the date. `now` in ms (Date.now()), `t` in seconds (git's).
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
function ago(t, now) {
  var s = Math.max(0, Math.floor(now / 1000) - t);
  if (s < 60) return "now";
  if (s < 3600) return Math.floor(s / 60) + " min";
  if (s < 86400) return Math.floor(s / 3600) + " h";
  if (s < 172800) return "yesterday";
  if (s < 30 * 86400) return Math.floor(s / 86400) + " d";
  var d = new Date(t * 1000), n = new Date(now);
  var md = d.getDate() + " " + MONTHS[d.getMonth()];
  return d.getFullYear() === n.getFullYear() ? md : md + " " + d.getFullYear();
}

function stamp(t) {
  var d = new Date(t * 1000);
  function two(x) { return x < 10 ? "0" + x : "" + x; }
  return d.getFullYear() + "-" + two(d.getMonth() + 1) + "-" + two(d.getDate())
    + " " + two(d.getHours()) + ":" + two(d.getMinutes());
}

// A commit's ref chips: the checked-out branch first, then local branches,
// tags, remotes. Each {label, ink, glyph}.
function chips(refs) {
  var order = { head: 0, local: 1, tag: 2, remote: 3, stash: 4, other: 5 };
  var rs = (refs || []).slice().sort(function (a, b) {
    var x = (a.head ? -1 : order[a.kind]), y = (b.head ? -1 : order[b.kind]);
    return x - y;
  });
  return rs.map(function (r) {
    if (r.kind === "tag") return { label: r.name, ink: "sand", glyph: "" };
    if (r.kind === "remote") return { label: r.name, ink: "blue", glyph: "" };
    if (r.kind === "stash") return { label: "Stash", ink: "magenta", glyph: "" };
    if (r.kind === "head") return { label: "HEAD", ink: "red", glyph: "" };
    return { label: r.name, ink: r.head ? "cyan" : "green", glyph: "", here: !!r.head };
  });
}

// ── COMMIT MESSAGES ─────────────────────────────────────────────────────
// What the box under the staged files says about the message as it is
// typed: the subject's length (50 is the convention, 72 the hard wrap), and
// whether there is anything to commit with it at all.
function subjectOf(msg) {
  var s = String(msg || "").replace(/^\s+/, "");
  var i = s.indexOf("\n");
  return (i < 0 ? s : s.slice(0, i)).replace(/\s+$/, "");
}

function messageNote(msg) {
  var sub = subjectOf(msg);
  if (sub === "") return { ok: false, text: "", ink: "muted" };
  var n = sub.length;
  if (n > 72) return { ok: true, text: n + " — long for a subject", ink: "red" };
  if (n > 50) return { ok: true, text: String(n), ink: "yellow" };
  return { ok: true, text: String(n), ink: "muted" };
}

// A message for a commit left without one, from what is staged: what was
// done to which files — "Add README.md and LICENSE", "Update install,
// remove LICENSE", "Update a.qml, b.js and 12 more". A verb per kind of
// change, the most files first; the whole kept under 72 characters.
// staged: [{ path, kind }].
function autoMessage(staged) {
  var verbs = { added: "add", modified: "update", typechange: "update", deleted: "remove",
                renamed: "rename", copied: "copy" };
  var order = ["update", "add", "remove", "rename", "copy"];
  var by = {};
  for (var i = 0; i < (staged || []).length; i++) {
    var v = verbs[staged[i].kind] || "update";
    (by[v] = by[v] || []).push(baseName(staged[i].path));
  }
  var groups = order.filter(function (v) { return by[v]; })
    .sort(function (a, b) { return by[b].length - by[a].length; });
  if (groups.length === 0) return "";
  function names(list, room) {
    var shown = list.slice(0, room);
    var more = list.length - shown.length;
    if (more > 0) return shown.join(", ") + " and " + more + " more";
    if (shown.length === 1) return shown[0];
    return shown.slice(0, -1).join(", ") + " and " + shown[shown.length - 1];
  }
  // as many names as fit: three for one kind of change, fewer for more
  for (var room = groups.length === 1 ? 3 : 2; room >= 0; room--) {
    var parts = groups.map(function (v) {
      return room === 0 ? v + " " + by[v].length + (by[v].length === 1 ? " file" : " files") : v + " " + names(by[v], room);
    });
    var msg = parts.join(", ");
    msg = msg.charAt(0).toUpperCase() + msg.slice(1);
    if (msg.length <= 72 || room === 0) return msg;
  }
  return "";
}

// ── REMOTES ─────────────────────────────────────────────────────────────
// A remote's URL → {host, full, web}: github.com/owner/name from any of
// https://github.com/o/n(.git), git@github.com:o/n(.git), ssh://git@…/o/n.
function remoteOf(url) {
  var u = String(url || "").trim();
  var m = u.match(/^(?:https?|ssh|git):\/\/(?:[^@/]+@)?([^/:]+)(?::\d+)?\/(.+?)(?:\.git)?\/?$/)
       || u.match(/^(?:[^@]+@)?([^:/]+):(.+?)(?:\.git)?\/?$/);
  if (!m) return null;
  return { host: m[1].toLowerCase(), full: m[2], web: "https://" + m[1].toLowerCase() + "/" + m[2] };
}

// HOW A REMOTE IS REACHED: "HTTPS", "SSH", or "" (a path, git://). The
// Remotes page's badge, and which way `s` switches it.
function protocolOf(url) {
  var u = String(url || "").trim();
  if (/^https?:\/\//.test(u)) return "HTTPS";
  if (/^ssh:\/\//.test(u) || /^[^@\/:\s]+@[^:\/\s]+:/.test(u)) return "SSH";
  return "";
}
// The same repository the other way: https ↔ ssh. A forge's ssh address
// is git@host:owner/name.git; the AUR's is ssh://aur@aur.archlinux.org/
// name.git (aur.archlinux.org/<pkg>.git over https only clones). "" when
// it cannot be said (a path, git://).
function otherUrl(url) {
  var p = protocolOf(url), r = remoteOf(url);
  if (!p || !r) return "";
  var full = r.full.replace(/\.git$/, "");
  if (p === "SSH") return "https://" + r.host + "/" + full + ".git";
  if (r.host === "aur.archlinux.org") return "ssh://aur@aur.archlinux.org/" + full + ".git";
  return "git@" + r.host + ":" + full + ".git";
}
// who ssh logs in as, and where — what sshTest is asked about an ssh
// remote ("git@github.com:o/n" → { user: "git", host: "github.com" })
function sshTarget(url) {
  var u = String(url || "").trim();
  var m = u.match(/^ssh:\/\/(?:([^@\/]+)@)?([^\/:]+)/) || u.match(/^([^@\/:\s]+)@([^:\/\s]+):/);
  return m ? { user: m[1] || "git", host: m[2].toLowerCase() } : null;
}

// What an ssh test that did not get in means (core/sshkeys.read_test's why)
var SSH_WHY = {
  refused: "The host does not know any key offered to it — add the public key there.",
  hostkey: "The host's key was not trusted, so ssh stopped before signing in.",
  network: "The host could not be reached — the network, or the address.",
  error: "ssh stopped with an error."
};
// The hosts a new key can be for: the three forges, the AUR, and servers of
// your own — each with whether Delphi can hand it the key itself (`api`:
// a forge id) or it is pasted on the host's own page (`page`)
function keyHosts() {
  var out = [];
  for (var i = 0; i < FORGE_ORDER.length; i++) {
    var f = FORGES[FORGE_ORDER[i]];
    out.push({ host: f.host, name: f.name, glyph: f.glyph, api: f.id, page: "" });
  }
  out.push({ host: "aur.archlinux.org", name: "AUR", glyph: "", api: "",
             page: "https://aur.archlinux.org/login", where: "My Account → SSH Public Key" });
  return out;
}

// A repository's name for a clone directory, from its URL.
function cloneName(url) {
  var r = remoteOf(url);
  var p = r ? r.full : String(url || "");
  p = p.replace(/\.git\/?$/, "").replace(/\/+$/, "");
  var i = p.lastIndexOf("/");
  return i >= 0 ? p.slice(i + 1) : p;
}

// ── QUESTIONS ───────────────────────────────────────────────────────────
// git's and ssh's prompts, said for a card: "Password for
// 'https://me@github.com': " → title "Password", for "me@github.com". An ssh
// host key question keeps its whole text — the fingerprint IS the question.
function askCard(q) {
  var p = String(q.prompt || "").trim();
  if (q.kind === "confirm") return { title: "Trust this host?", detail: p, secret: false, confirm: true };
  var m = p.match(/^(Username|Password) for '([^']*)'/i);
  if (m) {
    var who = m[2].replace(/^https?:\/\//, "");
    return { title: m[1].charAt(0).toUpperCase() + m[1].slice(1).toLowerCase(), detail: who, secret: !!q.secret };
  }
  m = p.match(/^Enter passphrase for (?:key )?'?([^':]+)'?/i);
  if (m) return { title: "Key passphrase", detail: m[1], secret: true };
  return { title: q.secret ? "Password" : "Answer", detail: p.replace(/:\s*$/, ""), secret: !!q.secret };
}

// The error a failed request shows: git's last meaningful line or two, with
// git's "hint:" chatter and "error: " prefixes trimmed.
function errorText(err) {
  var ls = String(err || "").split("\n").map(function (l) { return l.trim(); })
    .filter(function (l) { return l !== "" && !/^hint:/.test(l); })
    .map(function (l) { return l.replace(/^(error|fatal):\s*/, ""); });
  if (ls.length === 0) return "It did not work";
  return ls.slice(-3).join("\n");
}

// Recently opened repositories: the newest first, one per root, at most n.
function remember(list, root, name, now, n) {
  var out = [{ root: root, name: name, at: now }];
  for (var i = 0; i < (list || []).length; i++)
    if (list[i].root !== root) out.push(list[i]);
  return out.slice(0, n || 20);
}

function baseName(p) {
  var s = String(p || "").replace(/\/+$/, "");
  var i = s.lastIndexOf("/");
  return i >= 0 ? s.slice(i + 1) : s;
}

function tilde(p, home) {
  var s = String(p || "");
  return home && s.indexOf(home) === 0 ? "~" + s.slice(home.length) : s;
}

// ── THE FORGE ───────────────────────────────────────────────────────────
// The sites a repository can live on, and what each calls things. `refs`
// is where a pull request's commits are kept on it (a checkout fetches
// them from there); `pull`/`pulls` its own words for one.
var FORGES = {
  github:   { id: "github", name: "GitHub", host: "github.com", glyph: "\uF09B",
              pull: "pull request", pulls: "Pull requests", refs: "pull", cli: "gh", pkg: "github-cli",
              tokens: "github.com → Settings → Developer settings → Tokens" },
  gitlab:   { id: "gitlab", name: "GitLab", host: "gitlab.com", glyph: "\uF296",
              pull: "merge request", pulls: "Merge requests", refs: "merge-requests", cli: "glab", pkg: "glab",
              tokens: "gitlab.com → Preferences → Access tokens (scope: api)" },
  codeberg: { id: "codeberg", name: "Codeberg", host: "codeberg.org", glyph: "\uF330",
              pull: "pull request", pulls: "Pull requests", refs: "pull", cli: "", pkg: "",
              tokens: "codeberg.org → Settings → Applications (repository and issue access)" }
};
var FORGE_ORDER = ["github", "gitlab", "codeberg"];

// Every change between two tags, on the forge's own page: GitLab puts its
// pages under /-/, GitHub and Forgejo do not (release notes' "Full
// changelog" line, 2026-10-25). "" without both tags.
function compareUrl(web, gitlab, from, to) {
  if (!web || !from || !to) return "";
  return web + (gitlab ? "/-/compare/" : "/compare/") + encodeURIComponent(from) + "..." + encodeURIComponent(to);
}

// ── SERVERS OF YOUR OWN ──────────────────────────────────────────────────
// A self-hosted GitLab, or a Forgejo or Gitea: { kind: "gitlab"|"forgejo",
// host, name? }, kept by the manager and laid into FORGES (after the three)
// as "<kind>@<host>" — the name the daemon routes by (server.route). Signed
// in to with a token: a server's own sign-in page is its own business.
var SERVER_KINDS = {
  gitlab:  { name: "GitLab", glyph: "\uF296", pull: "merge request", pulls: "Merge requests", refs: "merge-requests",
             tokens: " → Preferences → Access tokens (scope: api)" },
  forgejo: { name: "Forgejo or Gitea", glyph: "\uF233", pull: "pull request", pulls: "Pull requests", refs: "pull",
             tokens: " → Settings → Applications (repository and issue access)" }
};
function serverId(kind, host) { return kind + "@" + String(host || "").toLowerCase(); }
// a host as typed — https://git.example.org/, with a path even — to its name
function hostOf(text) {
  var t = String(text || "").trim().toLowerCase().replace(/^[a-z]+:\/\//, "");
  t = t.replace(/^[^@\/]*@/, "").split("/")[0];
  return /^[a-z0-9][a-z0-9.\-]*(:\d+)?$/.test(t) ? t : "";
}
function setServers(list) {
  for (var k in FORGES) if (FORGES[k].server) delete FORGES[k];
  FORGE_ORDER.length = 0;
  FORGE_ORDER.push("github", "gitlab", "codeberg");
  (list || []).forEach(function (s) {
    var kind = SERVER_KINDS[s.kind];
    if (!kind || !hostOf(s.host)) return;
    var id = serverId(s.kind, s.host);
    FORGES[id] = { id: id, kind: s.kind, server: true, name: s.name || s.host, host: s.host, glyph: kind.glyph,
                   pull: kind.pull, pulls: kind.pulls, refs: kind.refs, cli: "", pkg: "", tokens: s.host + kind.tokens };
    FORGE_ORDER.push(id);
  });
}

function forgeOfHost(host) {
  var h = String(host || "").toLowerCase();
  for (var i = 0; i < FORGE_ORDER.length; i++)
    if (FORGES[FORGE_ORDER[i]].host === h) return FORGES[FORGE_ORDER[i]];
  return null;
}

// The repository on a forge a checkout's pull requests and issues live on:
// the one behind `upstream` when there is one (a fork's are its parent's),
// else `origin`, else any remote on a forge delphi knows. { remote, host,
// full, web, forge } or null — forge the FORGES id.
function hubOf(remotes, own) {
  var rs = remotes || [];
  function on(r) {
    var o = r ? remoteOf(r.fetch || r.push) : null;
    var f = o ? forgeOfHost(o.host) : null;
    return f ? { remote: r.name, host: o.host, full: o.full, web: o.web, forge: f.id } : null;
  }
  // own: the one that is yours (origin first) — what Archive acts on,
  // never the project a fork came from
  var named = own ? ["origin", "upstream"] : ["upstream", "origin"];
  for (var i = 0; i < named.length; i++) {
    for (var j = 0; j < rs.length; j++)
      if (rs[j].name === named[i] && on(rs[j])) return on(rs[j]);
  }
  for (var k = 0; k < rs.length; k++) if (on(rs[k])) return on(rs[k]);
  return null;
}

// Every remote on a forge, the hub (hubOf) first, each forge repository
// once — for what one of them may have turned off (Releases, 2026-10-21:
// spoot's origin on Codeberg has releases off; its releases are on GitHub)
function hubsOf(remotes) {
  var rs = remotes || [], out = [], seen = {};
  var first = hubOf(rs);
  if (first) { out.push(first); seen[first.forge + " " + first.full] = true; }
  for (var i = 0; i < rs.length; i++) {
    var h = hubOf([rs[i]]);
    if (h && !seen[h.forge + " " + h.full]) { out.push(h); seen[h.forge + " " + h.full] = true; }
  }
  return out;
}

// ── AT A GLANCE ─────────────────────────────────────────────────────────
// What a repository's summary (delphi/core summaries) says needs doing, as
// words for Repositories' rows, each with a Zenon color's name; empty when
// there is nothing. ci: what its forge's checks said of its head, or null.
function attentionOf(s, ci) {
  var out = [];
  if (!s) return out;
  if (s.state && s.state.op) out.push({ word: s.state.op + " under way", ink: "yellow" });
  if (s.conflicts > 0) out.push({ word: s.conflicts + (s.conflicts === 1 ? " conflict" : " conflicts"), ink: "red" });
  if (s.changed > 0) out.push({ word: s.changed + " changed", ink: "yellow" });
  if (s.ahead > 0) out.push({ word: "↑" + s.ahead + " to push", ink: "cyan" });
  if (s.behind > 0) out.push({ word: "↓" + s.behind + " to pull", ink: "cyan" });
  if (s.branch && s.remotes && s.remotes.length > 0 && !s.upstream && s.oid) out.push({ word: "not published", ink: "muted" });
  if (ci && ci.state === "failure") out.push({ word: "checks failing", ink: "red" });
  return out;
}

// GitHub's "2026-10-09T20:04:39Z" → unix seconds (what ago() reads)
function secondsOf(iso) {
  var t = Date.parse(String(iso || ""));
  return isNaN(t) ? 0 : Math.floor(t / 1000);
}

// What a pull request or an issue is, by its mark: { glyph, ink, word } —
// ink a Zenon color's name
function forgeMark(r) {
  if (!r) return { glyph: "", ink: "muted", word: "" };
  if (r.pull) {
    if (r.state === "merged") return { glyph: "", ink: "magenta", word: "Merged" };
    if (r.state === "closed") return { glyph: "", ink: "red", word: "Closed" };
    if (r.draft) return { glyph: "", ink: "muted", word: "Draft" };
    return { glyph: "", ink: "green", word: "Open" };
  }
  return r.state === "closed" ? { glyph: "", ink: "magenta", word: "Closed" }
                              : { glyph: "", ink: "green", word: "Open" };
}

// Markdown as written on GitHub, made fit for a Text's MarkdownText: the
// template's <!-- comments --> gone, a picture said as a link to it (a
// Text would fetch it, unasked), html tags dropped but their words kept,
// and a bare #123 left alone.
function mdOf(text) {
  return String(text || "").replace(/\r\n/g, "\n")
    .replace(/<!--[\s\S]*?-->/g, "")
    .replace(/<img\b[^>]*\bsrc="([^"]*)"[^>]*>/gi, "[picture]($1)")
    .replace(/!\[([^\]]*)\]\(([^)\s]+)[^)]*\)/g, function (m, alt, url) { return "[" + (alt || "picture") + "](" + url + ")"; })
    .replace(/<\/?(details|summary|p|div|span|br|sub|sup|kbd|picture|source)\b[^>]*>/gi, "")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

// A release's markdown for MarkdownText with every line kept as written
// (user, 2026-10-12: the preview did not honor blank lines). GitHub keeps
// a release's single newlines; Qt joined them, and spaced a paragraph no
// more than a line. A text line before another becomes a hard break; a run
// of blank lines between text, that many no-break-space lines (a line of
// nbsp is text, not blank); next to a heading, list, quote, table or rule,
// the first blank still ends the block and the rest are nbsp paragraphs.
// Code fences pass untouched.
function mdLinesOf(text) {
  var src = String(text || "").replace(/\r\n/g, "\n").replace(/<!--[\s\S]*?-->/g, "");
  var lines = mdOf(src.replace(/\n/g, "\u0001")).split("\u0001");
  var block = /^\s{0,3}(#{1,6}(\s|$)|[-*+]\s|\d+[.)]\s|>|\||(-{3,}|\*{3,}|_{3,})\s*$)/;
  var fence = /^\s{0,3}(```|~~~)/;
  var out = [], prev = "", blanks = 0, inFence = false;
  for (var i = 0; i < lines.length; i++) {
    var l = lines[i];
    if (inFence) { out.push(l); if (fence.test(l)) { inFence = false; prev = "block"; } continue; }
    if (/^\s*$/.test(l)) { if (out.length) blanks++; continue; }
    var kind = fence.test(l) || block.test(l) ? "block" : "text";
    if (out.length) {
      if (prev === "text" && kind === "text") {
        out[out.length - 1] += "  ";
        for (var b = 0; b < blanks; b++) out.push("\u00a0  ");
      } else if (blanks > 0) {
        out.push("");
        for (var c = 1; c < blanks; c++) out.push("\u00a0", "");
      }
    }
    out.push(l);
    if (fence.test(l)) inFence = true;
    prev = kind;
    blanks = 0;
  }
  return out.join("\n");
}

// Markdown said plainly, for a few lines of preview: headings' #s, emphasis,
// code fences and quote marks gone, a link or a picture its words, html
// tags dropped, blank runs closed up.
function plainOf(text) {
  return mdOf(text)
    .replace(/^```.*$/gm, "")
    .replace(/^\s{0,3}#{1,6}\s+/gm, "")
    .replace(/^\s{0,3}>\s?/gm, "")
    .replace(/\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/<[^>]+>/g, "")
    .replace(/(\*\*|__|\*|_|`)(\S(?:.*?\S)?)\1/g, "$2")
    .replace(/\n{2,}/g, "\n")
    .trim();
}

// ── A CONFLICT'S TWO SIDES, BY WHAT THEY ARE ────────────────────────────
// git's "ours" and "theirs" are positions, not people: in a rebase "ours" is
// the branch being rebased ONTO and "theirs" is your own commit. Named here
// for what each side is, from what git is in the middle of (status.
// repo_state); a stash brought back leaves no state, and says so in its
// markers ("Updated upstream" / "Stashed changes").
function sideNames(state, oursLabel, theirsLabel) {
  var op = state && state.op ? state.op : "";
  if (op === "rebase") return { ours: "Upstream", theirs: "Your commit" };
  if (op === "merge") return { ours: "Yours", theirs: "Merged in" };
  if (op === "cherry-pick") return { ours: "Yours", theirs: "Picked commit" };
  if (op === "revert") return { ours: "Yours", theirs: "The revert" };
  if (/stash/i.test(String(theirsLabel || ""))) return { ours: "Your files", theirs: "The stash" };
  return { ours: "Yours", theirs: "Theirs" };
}

// text into StyledText: its own < > & left as written
function esc(s) {
  return String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

// ── THE NEXT RELEASE'S NAME ─────────────────────────────────────────────
// The last tag with its last number one up — v1.4.2 → v1.4.3, 2.0 → 2.1,
// release-7 → release-8 — and v0.1.0 when there is none, or no number to
// count up. Only a suggestion: the field is there to change it.
function nextVersion(tag) {
  var t = String(tag || "");
  var m = /^(.*?)(\d+)(\D*)$/.exec(t);
  if (!m) return "v0.1.0";
  return m[1] + (parseInt(m[2], 10) + 1) + m[3];
}

// Notes from commits ({ subject, sha }), as a changelog: one line each,
// newest first, under what they came after.
function notesFrom(commits, since) {
  var cs = commits || [];
  if (cs.length === 0) return "";
  var head = since ? "## Changes since " + since + "\n\n" : "## Changes\n\n";
  return head + cs.map(function (c) { return "- " + c.subject + " (" + c.sha + ")"; }).join("\n") + "\n";
}

// A commit's checks in words: "3 passed", "1 failed · 2 passed", "running —
// 1 of 4 done"
function ciWords(c) {
  if (!c || !c.runs || c.runs.length === 0) return "";
  var n = { success: 0, failure: 0, pending: 0, neutral: 0 };
  c.runs.forEach(function (r) { n[r.state] = (n[r.state] || 0) + 1; });
  var total = c.runs.length;
  if (n.pending > 0) return "Checks running — " + (total - n.pending) + " of " + total + " done" + (n.failure ? ", " + n.failure + " failed" : "");
  var parts = [];
  if (n.failure) parts.push(n.failure + " failed");
  if (n.success) parts.push(n.success + " passed");
  if (n.neutral) parts.push(n.neutral + " skipped");
  return "Checks: " + parts.join(" · ");
}

// A commit's signature, from git's %G? and %GG: null when unsigned.
// { glyph, words, ink } — ink a Zenon color's name. "Can't check" is a
// signature git has no key to check against here (not a bad one).
function signatureOf(code, signer) {
  var c = String(code || "N");
  var who = String(signer || "").split("\n").map(function (l) {
    var m = /(?:Good|Bad) "git" signature for (.+?) with/.exec(l) || /(?:Good|Bad) signature from "?([^"]+)"?/.exec(l);
    return m ? m[1] : "";
  }).filter(function (x) { return x; })[0] || "";
  if (c === "N") return null;
  if (c === "G" || c === "U") return { glyph: "", words: "Signed" + (who ? " by " + who : ""), ink: "green" };
  if (c === "B") return { glyph: "", words: "Bad signature — the commit is not what was signed", ink: "red" };
  if (c === "X" || c === "Y") return { glyph: "", words: "Signed with a key that has expired", ink: "yellow" };
  if (c === "R") return { glyph: "", words: "Signed with a revoked key", ink: "yellow" };
  return { glyph: "", words: "Signed — no key here to check it with", ink: "muted" };
}

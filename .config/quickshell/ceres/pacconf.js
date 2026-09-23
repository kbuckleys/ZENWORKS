// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// PACMAN.CONF, EDITED BY HAND — the pure half of ceres' Settings tab.
//
// THE FILE STAYS YOURS. Nothing here regenerates pacman.conf from a model: a
// change is an edit to the line that holds the setting — its value replaced
// in place, the line commented out or uncommented — and a setting the file
// has never mentioned is added at the end of its section. So the banner, the
// comments, the tab alignment and the order all survive, and `diff` against
// the original shows exactly the lines that were asked for and no others.
//
// Every function takes the file as an array of lines and returns a NEW array;
// nothing is mutated, which is what makes "discard" and "what changed" free.
//
// The settings and their descriptions are pacman.conf(5)'s, for pacman 7.1.

// ── what can be set ───────────────────────────────────────────────────────
// type: flag · int · text · list (space-separated words) · clean · sig
// `def` is what pacman does when the line is absent, in words.
const GROUPS = [
  { id: "general", title: "Output", blurb: "How pacman talks to you." },
  { id: "downloads", title: "Downloads", blurb: "How packages and databases are fetched." },
  { id: "packages", title: "Upgrades", blurb: "What an upgrade touches, holds back, and cleans up." },
  { id: "signatures", title: "Signatures", blurb: "What a package or database must be signed by before pacman accepts it." },
  { id: "paths", title: "Paths", blurb: "Where pacman keeps things. Most systems never change these." },
  { id: "repos", title: "Repositories", blurb: "Where packages come from, in order: when two repositories have a package of the same name, the one listed first wins, whatever its version." }
];

const SCHEMA = [
  { key: "Color", group: "general", type: "flag", label: "Colour",
    help: "Colour in pacman's output, when it is going to a terminal.", def: "off" },
  { key: "ILoveCandy", group: "general", type: "flag", label: "Pac-Man progress bar",
    help: "Draws progress bars as Pac-Man eating pellets. Undocumented, and harmless.", def: "off" },
  { key: "VerbosePkgLists", group: "general", type: "flag", label: "Package tables",
    help: "Lists the packages of an upgrade, sync or removal as a table: name, old and new version, size.", def: "off" },
  { key: "NoProgressBar", group: "general", type: "flag", label: "No progress bars",
    help: "Turns progress bars off, for terminals that cannot draw them.", def: "off" },
  { key: "CheckSpace", group: "general", type: "flag", label: "Check disk space",
    help: "Checks, roughly, that there is room for a transaction before installing anything.", def: "off" },
  { key: "UseSyslog", group: "general", type: "flag", label: "Log to syslog",
    help: "Also logs pacman's actions through syslog — the journal, on most systems.", def: "off" },

  { key: "ParallelDownloads", group: "downloads", type: "int", label: "Parallel downloads", min: 1, max: 50,
    help: "How many files download at once. Unset, it is one at a time.", def: "1" },
  { key: "DownloadUser", group: "downloads", type: "text", label: "Download as",
    help: "The user downloads run as, so that they do not run as root. Unset, they run as whoever ran pacman.", def: "the user running pacman" },
  { key: "DisableDownloadTimeout", group: "downloads", type: "flag", label: "No download timeout",
    help: "Drops the low-speed limit and timeout on downloads — for proxies and security gateways that stall them.", def: "off" },
  { key: "XferCommand", group: "downloads", type: "text", label: "Download command",
    help: "An external program to download with instead of pacman's own: %u is the URL, %o the file to write.", def: "pacman's built-in downloader" },
  { key: "DisableSandbox", group: "downloads", type: "flag", label: "No download sandbox",
    help: "Turns off the whole sandbox around the download process. The same as both of the two below together.", def: "off" },
  { key: "DisableSandboxFilesystem", group: "downloads", type: "flag", label: "No filesystem sandbox",
    help: "Turns off only the Landlock filesystem restrictions, for kernels without Landlock.", def: "off" },
  { key: "DisableSandboxSyscalls", group: "downloads", type: "flag", label: "No syscall sandbox",
    help: "Turns off only the seccomp syscall filter, for kernels without it.", def: "off" },

  { key: "IgnorePkg", group: "packages", type: "list", label: "Never upgrade",
    help: "Packages a full upgrade leaves alone. Shell globs are allowed.", def: "none" },
  { key: "IgnoreGroup", group: "packages", type: "list", label: "Never upgrade groups",
    help: "Every package in these groups is left alone by a full upgrade.", def: "none" },
  { key: "HoldPkg", group: "packages", type: "list", label: "Ask before removing",
    help: "Removing one of these asks for confirmation first. Shell globs are allowed.", def: "none" },
  { key: "NoUpgrade", group: "packages", type: "list", label: "Never overwrite",
    help: "Files an upgrade never touches: the new version is installed beside yours as .pacnew. Paths inside the package, without the leading slash.", def: "none" },
  { key: "NoExtract", group: "packages", type: "list", label: "Never install",
    help: "Files never extracted from any package. Paths inside the package, without the leading slash; a leading ! puts one back.", def: "none" },
  { key: "Architecture", group: "packages", type: "text", label: "Architecture",
    help: "Only packages for these architectures install. auto is this machine's; packages for any install everywhere.", def: "no check" },
  { key: "CleanMethod", group: "packages", type: "clean", label: "What -Sc removes",
    help: "KeepInstalled drops cached files of packages no longer installed; KeepCurrent drops files no repository offers any more. Both together: only files that are neither.", def: "KeepInstalled" },

  { key: "SigLevel", group: "signatures", type: "sig", label: "Everything",
    help: "The default for every repository that does not set its own.", def: "Required TrustedOnly" },
  { key: "LocalFileSigLevel", group: "signatures", type: "sig", label: "Local files",
    help: "For pacman -U on a file on disk.", def: "as Everything" },
  { key: "RemoteFileSigLevel", group: "signatures", type: "sig", label: "Remote files",
    help: "For pacman -U on a URL.", def: "as Everything" },

  { key: "RootDir", group: "paths", type: "text", label: "Root",
    help: "Where pacman installs to — for a chroot, or a system mounted from elsewhere.", def: "/" },
  { key: "DBPath", group: "paths", type: "text", label: "Database",
    help: "The package databases.", def: "/var/lib/pacman/" },
  { key: "CacheDir", group: "paths", type: "list", label: "Package cache",
    help: "Where downloaded packages are kept. Several are tried in order; new downloads go to the first one writable.", def: "/var/cache/pacman/pkg/" },
  { key: "HookDir", group: "paths", type: "list", label: "Hooks",
    help: "Extra directories of alpm hooks, besides /usr/share/libalpm/hooks/. Later ones take precedence.", def: "/etc/pacman.d/hooks/" },
  { key: "GPGDir", group: "paths", type: "text", label: "Keyring",
    help: "The GnuPG directory with the packagers' keys.", def: "/etc/pacman.d/gnupg/" },
  { key: "LogFile", group: "paths", type: "text", label: "Log",
    help: "pacman's log — what History reads.", def: "/var/log/pacman.log" }
];

// Arch's own repositories: switched on and off, never removed.
const OFFICIAL = ["core", "extra", "multilib", "core-testing", "extra-testing", "multilib-testing",
                  "gnome-unstable", "kde-unstable"];
const REPO_KEYS = ["Include", "Server", "CacheServer", "SigLevel", "Usage"];
const USAGE = ["Sync", "Search", "Install", "Upgrade"];

function spec(key) {
  for (const s of SCHEMA) if (s.key === key) return s;
  return null;
}

function lines(text) {
  const out = String(text ?? "").split("\n");
  if (out.length && out[out.length - 1] === "") out.pop();
  return out;
}
function text(ls) { return ls.join("\n") + "\n"; }

// ── sections ──────────────────────────────────────────────────────────────
// Every header, live or commented out: "[core]" or "#[multilib]". A section
// runs to the next header of either kind.
const HEAD_RE = /^(\s*)(#\s*)?\[([^\]]+)\]\s*$/;

function sections(ls) {
  const out = [];
  for (let i = 0; i < ls.length; i++) {
    const m = HEAD_RE.exec(ls[i]);
    if (!m) continue;
    if (out.length) out[out.length - 1].end = i;
    out.push({ name: m[3].trim(), start: i, end: ls.length, commented: !!m[2] });
  }
  return out;
}
function optionsSection(ls) {
  return sections(ls).find(s => s.name === "options" && !s.commented) || null;
}

function esc(s) { return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"); }
function lineRe(key) { return new RegExp("^(\\s*)(#\\s*)?(" + esc(key) + ")\\b\\s*(=\\s*(.*?))?\\s*$"); }

// A key's lines inside [start, end): live ones, and the first commented one.
function find(ls, start, end, key) {
  const re = lineRe(key);
  const out = { live: [], commented: -1 };
  for (let i = start + 1; i < end; i++) {
    const m = re.exec(ls[i]);
    if (!m) continue;
    if (m[2]) { if (out.commented < 0) out.commented = i; }
    else out.live.push({ at: i, value: m[5] ?? "" });
  }
  return out;
}

// ── options ───────────────────────────────────────────────────────────────
// → { set, value } — a flag's value is true; a list's values are the live
// lines' words together (pacman adds repeated lines up).
function getOption(ls, key) {
  const sec = optionsSection(ls);
  if (!sec) return { set: false, value: "" };
  const f = find(ls, sec.start, sec.end, key);
  if (f.live.length === 0) return { set: false, value: "" };
  const s = spec(key);
  if (s && s.type === "flag") return { set: true, value: true };
  return { set: true, value: f.live.map(l => l.value).join(" ").trim() };
}

// The value replaced on the line itself, keeping its key and its spacing.
function withValue(line, key, value) {
  const m = lineRe(key).exec(line);
  if (!m) return line;
  const body = line.replace(/^(\s*)#\s*/, "$1");
  if (value === true) return body.replace(/\s*=.*$/, "");
  const mm = /^(\s*\S+?)(\s*=\s*)(.*)$/.exec(body);
  // "#IgnorePkg     =" has no space after its = to keep
  return mm ? mm[1] + mm[2] + (/\s$/.test(mm[2]) ? "" : " ") + value : body + " = " + value;
}
function commentOut(line) { return "#" + line; }

// The last SETTING of a section, live or commented: where a new one goes,
// with the others — not after the blank lines that close the section, nor
// after a note like "# An example of a custom package repository" that
// belongs to the section below. A commented setting is "#Key" or "#Key = …";
// a note is prose, and never reads as a single CamelCase word before an =.
const SETTING_RE = /^\s*#?\s*[A-Z][A-Za-z]+\b\s*(=.*)?$/;
function tailOf(ls, sec) {
  for (let i = sec.end - 1; i > sec.start; i--) if (SETTING_RE.test(ls[i])) return i;
  return sec.start;
}

function setIn(ls, sec, key, value, isFlag) {
  const out = ls.slice();
  const f = find(out, sec.start, sec.end, key);
  const unset = value === null || value === false || value === "";
  if (unset) {
    for (const l of f.live) out[l.at] = commentOut(out[l.at]);
    return out;
  }
  const v = isFlag ? true : String(value);
  if (f.live.length) {
    out[f.live[0].at] = withValue(out[f.live[0].at], key, v);
    // the rest folded into the first: one line says the whole value
    for (const l of f.live.slice(1)) out[l.at] = commentOut(out[l.at]);
    return out;
  }
  if (f.commented >= 0) {
    out[f.commented] = withValue(out[f.commented], key, v);
    return out;
  }
  out.splice(tailOf(out, sec) + 1, 0, v === true ? key : key + " = " + v);
  return out;
}

// null, false or "" unsets: the line is commented out, not deleted, so the
// value is still there to see — and to switch back on.
function setOption(ls, key, value) {
  const sec = optionsSection(ls);
  if (!sec) return ls;
  const s = spec(key);
  return setIn(ls, sec, key, value, !!s && s.type === "flag");
}

// ── signature levels ──────────────────────────────────────────────────────
// Read left to right, later words overriding earlier ones, a Package or
// Database prefix narrowing a word to that one kind — pacman's own rules.
const CHECKS = ["Never", "Optional", "Required"];
const TRUSTS = ["TrustedOnly", "TrustAll"];

function parseSig(str, base) {
  const b = base || { pkg: { check: "Required", trust: "TrustedOnly" }, db: { check: "Required", trust: "TrustedOnly" } };
  const out = { pkg: Object.assign({}, b.pkg), db: Object.assign({}, b.db) };
  for (const w of String(str ?? "").split(/\s+/).filter(x => x)) {
    const m = /^(Package|Database)?(.+)$/.exec(w);
    const which = m[1] === "Package" ? ["pkg"] : m[1] === "Database" ? ["db"] : ["pkg", "db"];
    for (const k of which) {
      if (CHECKS.indexOf(m[2]) >= 0) out[k].check = m[2];
      else if (TRUSTS.indexOf(m[2]) >= 0) out[k].trust = m[2];
    }
  }
  return out;
}

// The shortest string that says it: what both share, unprefixed; where the
// database differs, a Database word after it. TrustedOnly is the default and
// is not written unless the database needs it spelled out.
function formatSig(sig) {
  const out = [sig.pkg.check];
  if (sig.db.check !== sig.pkg.check) out.push("Database" + sig.db.check);
  if (sig.pkg.trust !== "TrustedOnly") out.push(sig.pkg.trust);
  if (sig.db.trust !== sig.pkg.trust) out.push("Database" + sig.db.trust);
  return out.join(" ");
}

function sameSig(a, b) {
  return a.pkg.check === b.pkg.check && a.pkg.trust === b.pkg.trust
    && a.db.check === b.db.check && a.db.trust === b.db.trust;
}

// ── repositories ──────────────────────────────────────────────────────────
// A repository's BLOCK is its header down to its last directive, live or
// commented — not the blank lines or the comment that introduces the next
// one, which stay where they are when blocks move.
function blockOf(ls, sec) {
  let last = sec.start;
  for (let i = sec.start + 1; i < sec.end; i++) {
    const body = ls[i].replace(/^\s*#\s*/, "");
    if (/^\s*(Include|Server|CacheServer|SigLevel|Usage)\b\s*=/.test(body)) last = i;
  }
  return { start: sec.start, end: last + 1 };
}

function repos(ls) {
  const out = [];
  for (const s of sections(ls)) {
    if (s.name === "options") continue;
    const b = blockOf(ls, s);
    const r = { name: s.name, enabled: !s.commented, official: OFFICIAL.indexOf(s.name) >= 0,
                start: b.start, end: b.end, Include: [], Server: [], CacheServer: [], SigLevel: "", Usage: "" };
    for (let i = b.start + 1; i < b.end; i++) {
      const live = !/^\s*#/.test(ls[i]);
      // a switched-off repository's directives are all commented; a live one's
      // commented lines are notes, not settings
      if (live !== r.enabled) continue;
      const m = /^\s*(?:#\s*)?(Include|Server|CacheServer|SigLevel|Usage)\s*=\s*(.*?)\s*$/.exec(ls[i]);
      if (!m) continue;
      if (m[1] === "SigLevel" || m[1] === "Usage") r[m[1]] = m[2];
      else r[m[1]].push(m[2]);
    }
    out.push(r);
  }
  return out;
}

function repoNamed(ls, name) { return repos(ls).find(r => r.name === name) || null; }

// Switched off: header and directives commented. Switched on: the same
// lines uncommented — only those, never a note that happens to sit inside.
function setRepoEnabled(ls, name, on) {
  const r = repoNamed(ls, name);
  if (!r || r.enabled === on) return ls;
  const out = ls.slice();
  for (let i = r.start; i < r.end; i++) {
    const body = out[i].replace(/^(\s*)#\s*/, "$1");
    const isHead = HEAD_RE.test(out[i]);
    const isDirective = /^\s*(Include|Server|CacheServer|SigLevel|Usage)\s*=/.test(body);
    if (!isHead && !isDirective) continue;
    if (on && /^\s*#/.test(out[i])) out[i] = body;
    else if (!on && !/^\s*#/.test(out[i])) out[i] = commentOut(out[i]);
  }
  return out;
}

// One up or down: the two blocks trade places, and what lies between them
// stays put.
function moveRepo(ls, name, d) {
  const rs = repos(ls);
  const i = rs.findIndex(r => r.name === name);
  const j = i + d;
  if (i < 0 || j < 0 || j >= rs.length) return ls;
  const [a, b] = i < j ? [rs[i], rs[j]] : [rs[j], rs[i]];
  return ls.slice(0, a.start)
    .concat(ls.slice(b.start, b.end), ls.slice(a.end, b.start), ls.slice(a.start, a.end), ls.slice(b.end));
}

// SigLevel and Usage: one line. Include, Server and CacheServer: a line per
// value, the old lines replaced where the first of them was.
function setRepoKey(ls, name, key, value) {
  const r = repoNamed(ls, name);
  if (!r || !r.enabled) return ls;
  const sec = { start: r.start, end: r.end };
  if (key === "SigLevel" || key === "Usage") {
    if (value === "" || value === null) return setIn(ls, sec, key, null, false);
    const out = setIn(ls, sec, key, value, false);
    // new: straight under the header, where these conventionally go
    if (find(ls, sec.start, sec.end, key).live.length === 0 && find(ls, sec.start, sec.end, key).commented < 0) {
      const at = out.findIndex((l, k) => k > r.start && lineRe(key).test(l) && !/^\s*#/.test(l));
      const [ln] = out.splice(at, 1);
      out.splice(r.start + 1, 0, ln);
    }
    return out;
  }
  const values = (Array.isArray(value) ? value : String(value ?? "").split(/\s+/)).filter(v => v);
  const f = find(ls, sec.start, sec.end, key);
  const out = ls.slice();
  const at = f.live.length ? f.live[0].at : tailOf(ls, { start: r.start, end: r.end }) + 1;
  for (let k = f.live.length - 1; k >= 0; k--) out.splice(f.live[k].at, 1);
  out.splice(at, 0, ...values.map(v => key + " = " + v));
  return out;
}

function validRepoName(name, ls) {
  const n = String(name ?? "").trim();
  if (!/^[A-Za-z0-9._+-]+$/.test(n)) return "letters, digits and . _ + - only";
  if (n === "local" || n === "options") return "“" + n + "” is reserved";
  if (repoNamed(ls, n)) return "there is already a [" + n + "]";
  return "";
}

// At the end, where a third-party repository conventionally goes: after
// Arch's own, so theirs win when the two share a name.
function addRepo(ls, name, servers, sig) {
  const out = ls.slice();
  while (out.length && out[out.length - 1].trim() === "") out.pop();
  out.push("", "[" + name + "]");
  if (sig) out.push("SigLevel = " + sig);
  for (const s of (Array.isArray(servers) ? servers : String(servers ?? "").split(/\s+/)).filter(x => x))
    out.push("Server = " + s);
  return out;
}

function removeRepo(ls, name) {
  const r = repoNamed(ls, name);
  if (!r || r.official) return ls;
  const out = ls.slice();
  let start = r.start, end = r.end;
  // one blank line goes with it — the one after, or else the one before —
  // so the file closes up as if the block had never been added
  if (end < out.length && out[end].trim() === "") end++;
  else if (start > 0 && out[start - 1].trim() === "") start--;
  out.splice(start, end - start);
  return out;
}

// ── what changed ──────────────────────────────────────────────────────────
// Lines that differ between two versions, counted the cheap way: the edits
// here keep the lines aligned except where a line is added or removed, and
// the count is only for the "N changes" on the button — the review shows
// diff's own output.
function changedCount(a, b) {
  if (a.length === b.length) {
    let n = 0;
    for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) n++;
    return n;
  }
  const seen = {};
  for (const l of a) seen[l] = (seen[l] || 0) + 1;
  let n = 0;
  for (const l of b) { if (seen[l]) seen[l]--; else n++; }
  for (const k in seen) n += seen[k];
  return n;
}

// The review: the draft written as you, diffed against the file, and read
// by pacman-conf — the file as it is too, because pacman-conf exits 0 and
// only WARNS about a directive it does not know, and a warning the file
// already had must not stop a save that has nothing to do with it. Only
// what the draft adds counts.
function reviewCommand(draft) {
  const d = "'" + String(draft).replace(/'/g, "'\\''") + "'";
  return "diff -u /etc/pacman.conf " + d + "; "
    + "echo '@@was'; pacman-conf --config /etc/pacman.conf 2>&1 >/dev/null; "
    + "echo '@@now'; pacman-conf --config " + d + " 2>&1 >/dev/null; echo \"@@exit $?\"";
}

// A warning without the parts that move: which file, and which line.
function problemKey(l) {
  return String(l).replace(/config file [^,]*, /, "").replace(/line \d+: /, "");
}

// → { diff, ok, problems: [what pacman-conf says of the draft and not of the file] }
function readReviewOut(out) {
  const s = String(out ?? "");
  const a = s.indexOf("@@was\n"), b = s.indexOf("@@now\n");
  const diff = a >= 0 ? s.slice(0, a) : s;
  if (a < 0 || b < 0) return { diff: diff, ok: false, problems: ["pacman-conf did not run"] };
  const was = s.slice(a + 6, b).split("\n").filter(l => l.trim() !== "").map(problemKey);
  const m = /^([\s\S]*?)@@exit (\d+)\s*$/.exec(s.slice(b + 6));
  if (!m) return { diff: diff, ok: false, problems: ["pacman-conf did not run"] };
  const problems = m[1].split("\n").filter(l => l.trim() !== "" && was.indexOf(problemKey(l)) < 0);
  return { diff: diff, ok: m[2] === "0" && problems.length === 0, problems: problems };
}

// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// CERES — the pure half. Commands built, output read, nothing run.
//
// Every command here ends by printing its own exit status as a last line,
// "@@exit N". A Process reports its exit and its stream separately and in
// EITHER order, and an update checker has to know both at once: the same
// empty output is "nothing to do" with one status and "could not ask" with
// another. Reading the status out of the stream makes them one event.

const EXIT_MARK = "@@exit ";

function q(s) {
  return "'" + String(s ?? "").replace(/'/g, "'\\''") + "'";
}

// ── the commands ──────────────────────────────────────────────────────────

// The official repos. Against Ceres' OWN temporary database rather than
// checkupdates' default, which lives in /tmp (gone at every boot, so every
// first check re-downloaded every database) and is shared with anything else
// running checkupdates — two syncs into one dbpath and the second fails on
// the lock. `online` false re-reads the local packages against the database
// as last synced: no network, a quarter of a second.
function repoCommand(db, online) {
  return "CHECKUPDATES_DB=" + q(db) + " checkupdates --nocolor"
    + (online ? "" : " --nosync")
    + " 2>&1; echo \"" + EXIT_MARK + "$?\"";
}

// The AUR, through paru, so the count honours IgnorePkg, IgnoreGroup and
// devel tracking exactly as `paru -Syu` will. stderr is folded in because it
// is the only thing that tells "no AUR updates" from "no network": paru exits
// 1 for both.
function aurCommand() {
  return "paru -Qua --color=never 2>&1; echo \"" + EXIT_MARK + "$?\"";
}

// The AUR again, without the network. After a transaction the question is
// only "which of the updates we already know about are now installed", and
// the local database answers it: each known update is kept while the
// installed version is still older than the one it would move to. vercmp
// is pacman's own comparison, so epochs and pkgrels mean what they mean to
// pacman.
function aurRecheckCommand(list) {
  const pairs = (list || []).map(u => q(u.name) + " " + q(u.to)).join(" ");
  return "set -- " + pairs + "\n"
    + "while [ $# -ge 2 ]; do\n"
    + "  v=$(pacman -Q -- \"$1\" 2>/dev/null | cut -d' ' -f2)\n"
    + "  if [ -n \"$v\" ] && [ \"$(vercmp \"$v\" \"$2\")\" -lt 0 ]; then\n"
    + "    printf '%s %s -> %s\\n' \"$1\" \"$v\" \"$2\"\n"
    + "  fi\n"
    + "  shift 2\n"
    + "done\n"
    + "echo \"" + EXIT_MARK + "0\"";
}

// The running kernel's modules are gone once its package has been upgraded:
// new USB devices, filesystems, anything loaded on demand stops working
// until a reboot. That, not "a newer kernel exists upstream", is the fact
// worth putting on the bar.
function restartCommand() {
  return "if [ -d \"/usr/lib/modules/$(uname -r)\" ]; then echo ok; "
    + "else echo restart; fi";
}

// ── reading them back ─────────────────────────────────────────────────────

// Splits a command's output into its lines and the status it printed last.
// A missing mark means the command never finished — killed, or cut short —
// and that is reported as its own status rather than guessed at.
function splitExit(text) {
  const lines = String(text ?? "").split("\n");
  let code = -1;
  for (let i = lines.length - 1; i >= 0; --i) {
    const l = lines[i].trim();
    if (l === "") continue;
    // At the END of the line, not only as the whole of it: output that does
    // not finish with a newline (the news feed's XML) puts the mark on the
    // same line as its last bytes.
    const at = l.lastIndexOf(EXIT_MARK);
    if (at >= 0 && /^-?\d+$/.test(l.slice(at + EXIT_MARK.length))) {
      code = parseInt(l.slice(at + EXIT_MARK.length), 10);
      if (at === 0) lines.splice(i, 1);
      else lines[i] = lines[i].slice(0, lines[i].lastIndexOf(EXIT_MARK));
    }
    break;
  }
  return { lines: lines, code: code };
}

// "name old -> new", the one format checkupdates, `paru -Qua` and the
// recheck above all print. Anything else in the stream — paru's
// ":: ignoring package upgrade" notes, warnings — is not an update and is
// not counted as one.
const UPDATE_RE = /^(\S+)\s+(\S+)\s+->\s+(\S+)(?:\s.*)?$/;

function parseUpdates(lines) {
  const out = [];
  const seen = {};
  for (const raw of lines || []) {
    const m = UPDATE_RE.exec(String(raw).trim());
    if (!m || seen[m[1]]) continue;
    seen[m[1]] = true;
    out.push({ name: m[1], from: m[2], to: m[3] });
  }
  out.sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0);
  return out;
}

// checkupdates: 0 updates, 2 none, anything else a failure.
function readRepo(text) {
  const r = splitExit(text);
  if (r.code === 0) return { ok: true, list: parseUpdates(r.lines) };
  if (r.code === 2) return { ok: true, list: [] };
  // The shell's "command not found". checkupdates is pacman-contrib's, and
  // pacman-contrib arrives as somebody else's dependency — it went with
  // waybar-updates the day that was removed. Say what to install, not
  // "sh: checkupdates: not found".
  if (r.code === 127) return { ok: false, list: [], error: "pacman-contrib is not installed" };
  return { ok: false, list: [], error: errorLine(r.lines, "repo check failed") };
}

// paru: 0 updates, 1 none OR a failure — told apart by what it said.
function readAur(text) {
  const r = splitExit(text);
  const list = parseUpdates(r.lines);
  if (r.code === 127) return { ok: false, list: [], error: "paru is not installed" };
  if (r.code === 0) return { ok: true, list: list };
  if (r.code === 1) {
    const err = r.lines.find(l => /^\s*error\b/i.test(l));
    if (!err && list.length === 0) return { ok: true, list: [] };
    if (!err) return { ok: true, list: list };
    return { ok: false, list: [], error: shortError(err) };
  }
  return { ok: false, list: [], error: errorLine(r.lines, "AUR check failed") };
}

function errorLine(lines, fallback) {
  const l = (lines || []).map(s => String(s).trim()).filter(s => s !== "");
  const hit = l.find(s => /error/i.test(s)) || l[l.length - 1];
  return hit ? shortError(hit) : fallback;
}

// paru's network errors repeat the same cause four times over. The first
// clause says it; the rest is noise on a tooltip.
function shortError(s) {
  let t = String(s).trim().replace(/^==>\s*/, "").replace(/^error:\s*/i, "");
  const unreachable = /network is unreachable|could not resolve|timed out|connect error/i;
  if (unreachable.test(t)) return "offline";
  const cut = t.indexOf(": ");
  if (cut > 0 && t.length > 60) t = t.slice(0, cut);
  return t.length > 80 ? t.slice(0, 77) + "…" : t;
}

// ── what is worth saying ──────────────────────────────────────────────────

// An update is the package AND where it is going. The same package moving
// to a newer version tomorrow is a new update, and should be said again.
function keyOf(u) { return u.name + " " + u.to; }

// The ones in `list` nobody has been told about. Announcing on "the list
// changed" re-announced the leftovers every time part of it was installed;
// only arrivals are news.
function arrivals(list, told) {
  const known = {};
  for (const k of told || []) known[k] = true;
  return (list || []).filter(u => !known[keyOf(u)]);
}

// What is still worth remembering as told: the told ones still pending.
// Anything installed since drops out, so it can be told again when it
// comes back at a newer version.
function stillTold(list, told) {
  const pending = {};
  for (const u of list || []) pending[keyOf(u)] = true;
  return (told || []).filter(k => pending[k]);
}

// ── scheduling ────────────────────────────────────────────────────────────

// Minutes until the next attempt after `failures` failures in a row: 5, 10,
// 20, 40… never longer than the ordinary interval. A failed check waiting a
// full hour to try again is an hour of a stale bar for a blip.
function retryMins(failures, intervalMins) {
  const n = Math.max(1, failures);
  return Math.min(Math.max(1, intervalMins), 5 * Math.pow(2, n - 1));
}

// Is an online check due, on the wall clock? A Timer counts only time the
// machine was awake, so a laptop that slept through its hour would wait
// another one after waking.
function due(now, lastTry, lastOk, failures, intervalMins) {
  if (!lastOk) return !lastTry || now - lastTry >= retryMins(failures, intervalMins) * 60000;
  if (failures > 0) return now - lastTry >= retryMins(failures, intervalMins) * 60000;
  return now - lastOk >= intervalMins * 60000;
}

// "12m", "3h", "2d" — how old the last good answer is.
function age(ms) {
  const m = Math.max(0, Math.floor(ms / 60000));
  if (m < 1) return "just now";
  if (m < 60) return m + "m ago";
  const h = Math.floor(m / 60);
  if (h < 48) return h + "h ago";
  return Math.floor(h / 24) + "d ago";
}

// ── the tooltip, which is also the toast ──────────────────────────────────

function esc(s) {
  return String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

// `ink` is { muted, arrow, repo, aur, warn } as hex strings; `limit` rows per
// group before the rest fold into an ellipsis. `notes` are lines set above
// the lists — stale, restart — in the warning ink.
function describe(repo, aur, ink, limit, notes) {
  const lines = [];
  for (const n of notes || []) lines.push("<font color='" + ink.warn + "'>" + esc(n) + "</font>");
  if ((notes || []).length && ((repo || []).length || (aur || []).length)) lines.push("");

  function group(list, glyph, color, one, many) {
    if (!list || list.length === 0) return;
    if (lines.length && lines[lines.length - 1] !== "") lines.push("");
    lines.push("<font color='" + color + "'>" + glyph + "</font>  "
      + list.length + " " + (list.length === 1 ? one : many));
    for (const u of list.slice(0, limit)) {
      lines.push("    " + esc(u.name) + " <font color='" + ink.muted + "'>"
        + esc(u.from) + "</font> <font color='" + ink.arrow + "'>→</font> "
        + esc(u.to));
    }
    if (list.length > limit)
      lines.push("    <font color='" + ink.muted + "'>+ " + (list.length - limit)
        + " more</font>");
  }
  group(repo, "", ink.repo, "Update", "Updates");
  group(aur, "", ink.aur, "AUR Update", "AUR Updates");
  return lines.join("\n");
}

// ── a transaction ─────────────────────────────────────────────────────────
//
// A transaction is one or more paru STEPS run under one password: an upgrade
// is one, installing some packages while removing others is two.
//
// THE PASSWORD IS CHECKED ONCE, THEN HELD. The wrapper reads it off its own
// stdin (never argv, never the environment), and:
//
//   1. offers it ONCE to `sudo -A -v`. The askpass answers a single call in
//      this phase (see ceres-askpass.sh), so a wrong password costs exactly
//      one failed attempt against faillock, and stops everything: 91.
//   2. once sudo has taken it, serves it to every later askpass call for as
//      long as the steps run — each step's sudo, paru's --sudoloop, a build
//      that outlives sudo's five-minute cache. A backgrounded loop writes it
//      into the fifo whenever something opens the fifo to read, and is
//      killed the moment the last step ends.
//
// Every step gets /dev/null for stdin: a prompt nobody can answer must fail,
// not hang. The first step to fail stops the rest.
const AUTH_FAILED = 91;

function stepCommand(args) {
  if ((args || [])[0] === "@sudo") return ["sudo", "-A"].concat(args.slice(1)).map(q).join(" ");
  // a script run as you — the paru build — which may itself ask sudo -A
  if ((args || [])[0] === "@user") return "sh -c " + q(args[1]);
  const sync = /^-S/.test(args[0] || "");
  const flags = ["--noconfirm", "--sudoloop", "--sudoflags=-A"]
    .concat(sync ? ["--skipreview"] : []);
  return ["paru"].concat(args, flags).map(q).join(" ");
}

function runCommand(fifo, askpass, steps) {
  const run = (steps || []).map(a =>
    "[ \"$s\" -eq 0 ] && { " + stepCommand(a) + " </dev/null 2>&1 || s=$?; }\n").join("");
  return "f=" + q(fifo) + "\n"
    + "clean() { rm -f \"$f\" \"$f.spent\" \"$f.once\"; }\n"
    + "clean; mkfifo -m 600 \"$f\" || { echo '" + EXIT_MARK + "9'; exit 9; }\n"
    + "IFS= read -r pw\n"
    + "export SUDO_ASKPASS=" + q(askpass) + " CERES_FIFO=\"$f\"\n"
    + ": > \"$f.once\"\n"
    + "( printf '%s\\n' \"$pw\" > \"$f\" ) 2>/dev/null & w=$!\n"
    + "if ! sudo -A -v </dev/null 2>&1; then\n"
    + "  kill \"$w\" 2>/dev/null; clean; echo '" + EXIT_MARK + AUTH_FAILED + "'; exit " + AUTH_FAILED + "\n"
    + "fi\n"
    + "kill \"$w\" 2>/dev/null; rm -f \"$f.once\" \"$f.spent\"\n"
    + "echo '@@authed'\n"
    // SIGPIPE ignored, or the first reader to close early kills the server
    // and the next sudo waits on a fifo nobody will ever write to again.
    + "( trap '' PIPE; while :; do printf '%s\\n' \"$pw\" > \"$f\"; done ) 2>/dev/null & w=$!\n"
    + "pw=\n"
    + "s=0\n"
    + run
    + "kill \"$w\" 2>/dev/null; clean\n"
    + "echo \"" + EXIT_MARK + "$s\"";
}

// What a transaction is, as steps. The whole list is a full upgrade —
// anything less is a partial one, which Arch does not support.
function upgradeSteps() { return [["-Syu"]]; }

// Installing and removing in one go: install first, so a removal that the
// install made unnecessary is still asked for, and a failed install does not
// leave you having removed something on its way.
function changeSteps(install, remove) {
  const out = [];
  if ((install || []).length) out.push(["-S", "--needed"].concat(install));
  if ((remove || []).length) out.push(["-Rs"].concat(remove));
  return out;
}

// The command a terminal gets when something needs a human: the same steps,
// prompts and all.
function terminalCommand(steps) {
  return (steps || []).map(a => a[0] === "@user" ? "sh -c " + q(a[1])
    : (a[0] === "@sudo" ? ["sudo"].concat(a.slice(1)) : ["paru"].concat(a)).map(q).join(" ")).join(" && ");
}

// ── reading pacman.log as it is written ───────────────────────────────────
// "[2026-09-23T06:23:30+0300] [ALPM] upgraded npm (12.0.2-1 -> 12.1.0-1)"
const ALPM_RE = /\[ALPM\]\s+(upgraded|installed|reinstalled|downgraded|removed)\s+(\S+)\s+\((.*)\)\s*$/;

function readEvent(line) {
  const m = ALPM_RE.exec(String(line ?? ""));
  if (!m) return null;
  const v = /^(\S+)\s*->\s*(\S+)$/.exec(m[3].trim());
  return v ? { verb: m[1], name: m[2], from: v[1], to: v[2] }
           : { verb: m[1], name: m[2], from: "", to: m[3].trim() };
}

const VERBS = ["upgraded", "installed", "reinstalled", "downgraded", "removed"];

function tally(events) {
  const out = {};
  for (const v of VERBS) out[v] = [];
  for (const e of events || []) if (out[e.verb]) out[e.verb].push(e);
  return out;
}

// What paru is doing, from its own ":: " lines — the only progress it prints
// without a terminal. Anything else is detail for the log.
function phaseOf(line) {
  const s = String(line ?? "").trim();
  const m = /^(?:::|==>)\s+(.+?)\.*$/.exec(s);
  if (!m) return "";
  const t = m[1];
  if (/^Synchroni[sz]ing package databases/i.test(t)) return "Syncing databases";
  if (/^Starting full system upgrade/i.test(t)) return "Resolving";
  if (/^Retrieving packages/i.test(t)) return "Downloading";
  if (/^Checking keys|^Checking package integrity|^Loading package files|^Checking for file conflicts|^Checking available disk space/i.test(t)) return "Checking";
  if (/^Processing package changes/i.test(t)) return "Installing";
  if (/^Running post-transaction hooks/i.test(t)) return "Running hooks";
  if (/^Making package|^Starting build|^Building/i.test(t)) return "Building";
  if (/^Downloading PKGBUILDs|^Cloning|^Fetching/i.test(t)) return "Fetching AUR sources";
  return "";
}

// The line worth showing when it went wrong: pacman's and paru's own
// "error:" lines, last first, since the last one is usually the cause.
function failureOf(lines) {
  const errs = (lines || []).map(s => String(s).trim())
    .filter(s => /^error:/i.test(s) || /^==> ERROR:/.test(s));
  if (errs.length === 0) return "";
  return errs[errs.length - 1].replace(/^(?:==>\s*)?error:\s*/i, "");
}

// ── what it cost ──────────────────────────────────────────────────────────
// `expac -Q '%n %m'` → { name: bytes }. Per package, as ZENU does: a single
// before/after total hides a big install cancelling a big removal.
function parseSizes(text) {
  const out = {};
  for (const l of String(text ?? "").split("\n")) {
    const m = /^(\S+)\s+(\d+)$/.exec(l.trim());
    if (m) out[m[1]] = Number(m[2]);
  }
  return out;
}

function diskDelta(before, after) {
  let added = 0, removed = 0;
  for (const n in after) {
    const d = after[n] - (before[n] || 0);
    if (d > 0) added += d;
  }
  for (const n in before) {
    const d = (after[n] || 0) - before[n];
    if (d < 0) removed -= d;
  }
  return { added: added, removed: removed };
}

function bytes(n) {
  n = Math.max(0, Number(n) || 0);
  const u = ["B", "K", "M", "G", "T"];
  let i = 0;
  while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
  return i === 0 ? n + "B" : n.toFixed(1) + u[i];
}

// "+212.4M  −3.1M", or one side when only one side moved, or "" for nothing.
function diskLine(delta) {
  if (!delta) return "";
  const a = delta.added, r = delta.removed;
  if (a > 0 && r > 0) return "+" + bytes(a) + "  −" + bytes(r);
  if (a > 0) return "+" + bytes(a);
  if (r > 0) return "−" + bytes(r);
  return "";
}

// ── the package list ──────────────────────────────────────────────────────
// scripts/ceres.sh builds and searches it; these read what it prints.

function searchCommand(script, installedOnly, query) {
  return q(script) + " search " + (installedOnly ? "installed" : "all") + " " + q(query);
}

// "state\tname\tsize\trepo\tversion" → rows. `size` is bytes; 0 means
// nothing knows yet (an AUR package before it is built).
function parseRows(text) {
  const out = [];
  for (const l of String(text ?? "").split("\n")) {
    const f = l.split("\t");
    if (f.length < 4 || f[1] === "") continue;
    out.push({ state: f[0], name: f[1], size: Number(f[2]) || 0,
               repo: f[3], version: f[4] || "",
               installed: f[0] !== "avail", aur: f[3] === "aur" });
  }
  return out;
}

function infoCommand(script, name, repo) {
  return q(script) + " info " + q(name) + " " + q(repo || "");
}

// pacman -Qi / -Si / paru -Si: "Key   : value", continuation lines indented.
// Order is kept — it is pacman's, and it is the order people know.
function parseInfo(text) {
  const fields = [];
  for (const raw of String(text ?? "").split("\n")) {
    const m = /^([A-Z][A-Za-z ]*?)\s*:\s?(.*)$/.exec(raw);
    if (m && !/^\s/.test(raw)) { fields.push([m[1].trim(), m[2].trim()]); continue; }
    if (fields.length && /^\s+\S/.test(raw))
      fields[fields.length - 1][1] += " " + raw.trim();
  }
  const map = {};
  for (const [k, v] of fields) if (!(k in map)) map[k] = v;
  return { fields: fields, map: map };
}

// A list-valued field ("Depends On", "Required By"): "None" is empty.
function listField(v) {
  const s = String(v ?? "").trim();
  if (s === "" || s === "None") return [];
  return s.split(/\s{2,}|\s(?=\S)/).filter(x => x !== "");
}

// ── what a change will do, before it is done ──────────────────────────────
// Repo targets are asked of pacman directly — it resolves their dependencies
// without the network and without root. AUR targets cannot be: nothing knows
// their dependencies or size until paru has the PKGBUILD, so they are listed
// as such rather than priced at zero.
// `dbpath`, when given, prices the change against THAT database instead of
// the system's — Ceres' own, synced by every update check, so an update is
// shown at the version it will actually land at rather than whatever the
// system databases held when they were last synced. expac has no --dbpath,
// so there the sizes come from `pacman -Si`, converted back to bytes.
function planCommand(repoInstall, remove, dbpath) {
  const ins = (repoInstall || []).map(q).join(" ");
  const rem = (remove || []).map(q).join(" ");
  const db = dbpath ? " --dbpath " + q(dbpath) : "";
  let s = "echo '@@install'\n";
  if (ins !== "") {
    s += "out=$(pacman" + db + " -S --needed --print --print-format '%n\t%v\t%r' -- " + ins + " 2>&1); st=$?\n"
      + "printf '%s\\n' \"$out\"; echo \"@@status $st\"\n"
      + "names=$(printf '%s\\n' \"$out\" | awk -F'\\t' 'NF==3{print $1}')\n"
      + (dbpath
        ? "echo '@@sync'; [ -n \"$names\" ] && LC_ALL=C pacman" + db + " -Si $names 2>/dev/null | awk '\n"
          + "  function b(v, u) { return v * (u == \"KiB\" ? 1024 : u == \"MiB\" ? 1048576 : u == \"GiB\" ? 1073741824 : 1) }\n"
          + "  /^Name / { n = $3 } /^Download Size/ { d = b($4, $5) }\n"
          + "  /^Installed Size/ { printf \"%s\\t%d\\t%d\\n\", n, d, b($4, $5) }'\n"
        : "echo '@@sync'; [ -n \"$names\" ] && expac -S '%n\t%k\t%m' $names 2>/dev/null\n")
      + "echo '@@local'; [ -n \"$names\" ] && expac -Q '%n\t%m' $names 2>/dev/null\n";
  }
  s += "echo '@@remove'\n";
  if (rem !== "") {
    s += "out=$(pacman -Rs --print --print-format '%n\t%v' -- " + rem + " 2>&1); st=$?\n"
      + "printf '%s\\n' \"$out\"; echo \"@@status $st\"\n"
      + "names=$(printf '%s\\n' \"$out\" | awk -F'\\t' 'NF==2{print $1}')\n"
      + "echo '@@freed'; [ -n \"$names\" ] && expac -Q '%n\t%m' $names 2>/dev/null\n";
  }
  s += "echo '@@end'";
  return s;
}

function readPlan(text) {
  const plan = { install: [], remove: [], installError: "", removeError: "",
                 blocked: [], download: 0, add: 0, replace: 0, free: 0 };
  let sec = "", sub = "";
  const sync = {}, local = {}, freed = {};
  for (const raw of String(text ?? "").split("\n")) {
    const l = raw.replace(/\s+$/, "");
    if (l === "@@install") { sec = "install"; sub = "list"; continue; }
    if (l === "@@remove") { sec = "remove"; sub = "list"; continue; }
    if (l === "@@sync") { sub = "sync"; continue; }
    if (l === "@@local") { sub = "local"; continue; }
    if (l === "@@freed") { sub = "freed"; continue; }
    if (l === "@@end") break;
    if (/^@@status /.test(l)) continue;
    if (l === "") continue;
    const f = l.split("\t");
    if (sub === "sync") { if (!(f[0] in sync)) sync[f[0]] = { dl: Number(f[1]) || 0, size: Number(f[2]) || 0 }; continue; }
    if (sub === "local") { local[f[0]] = Number(f[1]) || 0; continue; }
    if (sub === "freed") { freed[f[0]] = Number(f[1]) || 0; continue; }
    if (sec === "install") {
      if (f.length === 3) plan.install.push({ name: f[0], version: f[1], repo: f[2] });
      else if (/^error:/.test(l) && plan.installError === "") plan.installError = l.replace(/^error:\s*/, "");
    } else if (sec === "remove") {
      if (f.length === 2) plan.remove.push({ name: f[0], version: f[1] });
      else if (/^error:/.test(l)) plan.removeError = l.replace(/^error:\s*/, "");
      else if (/^:: /.test(l)) plan.blocked.push(l.replace(/^::\s*/, ""));
    }
  }
  for (const p of plan.install) {
    const s = sync[p.name] || { dl: 0, size: 0 };
    p.download = s.dl; p.size = s.size; p.old = local[p.name] || 0;
    plan.download += s.dl; plan.add += s.size; plan.replace += p.old;
  }
  for (const p of plan.remove) { p.size = freed[p.name] || 0; plan.free += p.size; }
  return plan;
}

// "+212.4M" / "−3.1M": a signed disk change.
function signed(n) {
  return (n >= 0 ? "+" : "−") + bytes(Math.abs(n));
}

// ── reviewing an AUR package before it is built ───────────────────────────
// The PKGBUILD as the AUR has it now, against the one last built from (paru
// keeps its clones). A diff when there is something to diff against — the
// change is what needs reading, not the whole file again — and the whole file
// when this package has never been built here.
function reviewCommand(name) {
  const p = q(name);
  return "c=\"${XDG_CACHE_HOME:-$HOME/.cache}/paru/clone\"/" + p + "\n"
    + "new=$(paru -Gp -- " + p + " 2>/dev/null)\n"
    + "if [ -z \"$new\" ]; then echo '@@none'; exit 0; fi\n"
    + "if [ -f \"$c/PKGBUILD\" ]; then\n"
    + "  printf '%s\\n' \"$new\" | diff -u --label built --label aur \"$c/PKGBUILD\" - && echo '@@same'\n"
    + "else echo '@@new'; printf '%s\\n' \"$new\"; fi";
}

// → { kind: "diff"|"new"|"same"|"none", lines: [{ text, ink }] } where ink is
// "add", "del", "hunk" or "".
function readReview(text) {
  const lines = String(text ?? "").replace(/\n$/, "").split("\n");
  let kind = "diff";
  if (lines[lines.length - 1] === "@@same") { kind = "same"; lines.pop(); }
  if (lines[0] === "@@none") return { kind: "none", lines: [] };
  if (lines[0] === "@@new") { kind = "new"; lines.shift(); }
  return {
    kind: kind,
    lines: lines.map(l => ({
      text: l,
      ink: kind !== "diff" ? ""
        : /^\+\+\+|^---/.test(l) ? "hunk"
        : /^@@/.test(l) ? "hunk"
        : /^\+/.test(l) ? "add" : /^-/.test(l) ? "del" : ""
    }))
  };
}

// The words the password field says under itself for a change.
function changeLabel(install, remove) {
  const parts = [];
  if ((install || []).length) parts.push("install " + install.length);
  if ((remove || []).length) parts.push("remove " + remove.length);
  return parts.join(" · ");
}

// ── root commands that are not paru ───────────────────────────────────────
// A step is paru's arguments, or a root command marked by a leading "@sudo":
// ["@sudo", "paccache", "-rk2"]. Both run under the same password and the
// same wrapper, so cache maintenance reads exactly like an install — the
// same field, the same progress view, the same result.
function isSudoStep(args) { return (args || [])[0] === "@sudo"; }

// ── history ───────────────────────────────────────────────────────────────
// pacman.log, newest first, as far back as `limit` package events go. The
// "Running" lines come along because they are what turns a list of events
// into TRANSACTIONS: each one is the command that the events after it (in
// the file) belong to.
function historyCommand(limit) {
  return "tac /var/log/pacman.log 2>/dev/null | grep -m " + Math.max(1, limit | 0)
    + " -E '\\[ALPM\\] (installed|upgraded|removed|downgraded|reinstalled) |\\[PACMAN\\] Running '";
}

const STAMP_RE = /^\[(\d{4}-\d\d-\d\d)T(\d\d:\d\d)(?::\d\d)?([+-]\d{4})?\]/;

// → [{ date, time, command, events: [{verb,name,from,to}] }], newest first.
// Read in the order tac gives it: a transaction's events arrive BEFORE the
// line that started it, so they are collected until that line closes them.
function readHistory(text) {
  const out = [];
  let pending = [];
  for (const line of String(text ?? "").split("\n")) {
    const st = STAMP_RE.exec(line);
    if (!st) continue;
    const e = readEvent(line);
    if (e) { e.date = st[1]; e.time = st[2]; pending.push(e); continue; }
    const run = /\[PACMAN\] Running '(.*)'\s*$/.exec(line);
    if (!run) continue;
    if (pending.length) {
      out.push({ date: st[1], time: st[2], command: run[1], events: pending });
      pending = [];
    }
  }
  // events older than the first Running line in the window: still worth
  // showing, as a transaction whose command fell off the end
  if (pending.length)
    out.push({ date: pending[0].date, time: pending[0].time, command: "", events: pending });
  return out;
}

// "pacman --sync -y -u --noconfirm --" → "full upgrade", and so on: what a
// transaction WAS, in words, from the command that ran it.
function describeCommand(cmd) {
  const c = String(cmd ?? "");
  if (c === "") return "";
  if (/--sync\b.*-y\b.*-u\b|--sync\b.*-u\b.*-y\b|-Syu/.test(c)) return "full upgrade";
  if (/--sync\b|^pacman -S/.test(c)) return "install";
  if (/--remove\b|^pacman -R/.test(c)) return "remove";
  if (/--upgrade\b|^pacman -U/.test(c)) return "install from file";
  return c.replace(/^pacman\s+/, "");
}

// ── the package cache, for going back ─────────────────────────────────────
function cachedCommand(name) {
  return "ls -1 /var/cache/pacman/pkg/ 2>/dev/null | grep -F -- " + q(name + "-")
    + " | grep -v '\\.sig$' | sort -V";
}

// File names → [{ version, file }] for exactly this package, newest last as
// ls sorts them. A name is only this package's when the part after "name-"
// is a version-release-arch triple: "gst-plugins-bad-libs-…" is not
// gst-plugins-bad's.
function readCached(name, text) {
  const out = [];
  const pre = name + "-";
  for (const f of String(text ?? "").split("\n")) {
    if (f.indexOf(pre) !== 0) continue;
    const m = /^([^-]+-[^-]+)-(x86_64|any|i686|aarch64|armv7h)\.pkg\.tar\.[a-z0-9]+$/.exec(f.slice(pre.length));
    if (m) out.push({ version: m[1], file: "/var/cache/pacman/pkg/" + f });
  }
  return out;
}

// ── maintenance ───────────────────────────────────────────────────────────
// One command, sectioned, for everything the Maintenance tab reports. All of
// it without root: pacman's own queries, pacdiff's listing, and find over the
// cache (du cannot see into the root-only download-* directories; counting
// them is exact, measuring them is not).
function maintCommand(cloneDir) {
  return "echo '@@orphans'; pacman -Qtdq 2>/dev/null | while read -r n; do "
    + "expac -Q '%n\t%v\t%m' \"$n\" 2>/dev/null; done\n"
    + "echo '@@pacnew'; pacdiff -o 2>/dev/null\n"
    + "echo '@@cache'; find /var/cache/pacman/pkg -maxdepth 1 -name '*.pkg.tar.*' ! -name '*.sig' -printf '%s\\n' 2>/dev/null"
    + " | awk '{n++; t+=$1} END {print n+0 \"\\t\" t+0}'\n"
    + "echo '@@stale'; find /var/cache/pacman/pkg -maxdepth 1 -type d -name 'download-*' 2>/dev/null | wc -l\n"
    + "echo '@@clones'; for d in " + q(cloneDir) + "/*/; do [ -d \"$d\" ] || continue; "
    + "n=$(basename \"$d\"); s=$(du -sb \"$d\" 2>/dev/null | cut -f1); "
    + "if pacman -Qq \"$n\" >/dev/null 2>&1; then i=1; else i=0; fi; printf '%s\\t%s\\t%s\\n' \"$n\" \"$s\" \"$i\"; done\n"
    + "echo '@@synced'; stat -c %Y /var/lib/pacman/sync 2>/dev/null\n"
    + "echo '@@aurlist'; stat -c %Y \"${XDG_CACHE_HOME:-$HOME/.cache}/ceres/aur-names\" 2>/dev/null\n"
    // What the two cache buttons WOULD do, before either is pressed —
    // paccache's dry run, which needs no root. A button that would remove
    // nothing says so instead of taking a password to do it.
    + "echo '@@keep'; paccache -dk2 2>&1 | tail -n1\n"
    + "echo '@@uninst'; paccache -duk0 2>&1 | tail -n1\n"
    + "echo '@@end'";
}

function readMaint(text) {
  const m = { orphans: [], pacnew: [], cacheCount: 0, cacheBytes: 0, stale: 0,
              clones: [], synced: 0, aurList: 0, keep: { n: 0, size: "" }, uninst: { n: 0, size: "" } };
  let sec = "";
  for (const raw of String(text ?? "").split("\n")) {
    const l = raw.replace(/\s+$/, "");
    const sm = /^@@(\w+)$/.exec(l);
    if (sm) { sec = sm[1]; if (sec === "end") break; continue; }
    if (l === "") continue;
    const f = l.split("\t");
    if (sec === "orphans" && f.length >= 3)
      m.orphans.push({ name: f[0], version: f[1], size: Number(f[2]) || 0,
                       installed: true, state: "dep", repo: "" });
    else if (sec === "pacnew") m.pacnew.push(l);
    else if (sec === "cache") { m.cacheCount = Number(f[0]) || 0; m.cacheBytes = Number(f[1]) || 0; }
    else if (sec === "stale") m.stale = Number(l) || 0;
    else if (sec === "clones" && f.length >= 3)
      m.clones.push({ name: f[0], size: Number(f[1]) || 0, installed: f[2] === "1" });
    else if (sec === "synced") m.synced = (Number(l) || 0) * 1000;
    else if (sec === "aurlist") m.aurList = (Number(l) || 0) * 1000;
    else if (sec === "keep") m.keep = readPrune(l);
    else if (sec === "uninst") m.uninst = readPrune(l);
  }
  m.clones.sort((a, b) => b.size - a.size);
  return m;
}

// paccache's last line → { n, size }:
//   "==> finished dry run: 90 candidates (disk space saved: 431.55 MiB)"
//   "==> finished: 90 packages removed (disk space saved: 431.55 MiB)"
//   "==> no candidate packages found for pruning"
function readPrune(line) {
  const m = /(\d+) (?:candidates?|packages? removed) \(disk space saved: ([\d.]+ \w+)\)/.exec(String(line ?? ""));
  return m ? { n: Number(m[1]), size: m[2] } : { n: 0, size: "" };
}

// What a finished transaction SAID, for the ones that change no package —
// paccache, the stale-download sweep. The last "==>" line is the tool's
// own summary; without one, nothing was said worth repeating.
function summaryLine(lines) {
  for (let i = (lines || []).length - 1; i >= 0; --i) {
    const l = String(lines[i]).trim();
    if (/^==> /.test(l)) return l.replace(/^==>\s*/, "");
  }
  return "";
}

// The diff a .pacnew or .pacsave is ABOUT: the live file against the one
// pacman set down beside it. Both are readable without root for nearly all
// of /etc; one that is not says so instead of showing nothing.
function pacnewDiffCommand(path) {
  const live = String(path).replace(/\.pac(new|save)$/, "");
  return "diff -u --label " + q(live) + " --label " + q(path) + " -- " + q(live) + " " + q(path)
    + " 2>&1; true";
}

// ── Arch news ─────────────────────────────────────────────────────────────
// What archlinux.org posts when an update needs a human: a config to merge
// by hand, an initramfs to rebuild, a package that moved. paru shows it
// before an upgrade; so does ceres — see unreadNews.
const NEWS_URL = "https://archlinux.org/feeds/news/";

function newsCommand() {
  return "curl -fsS --max-time 20 " + q(NEWS_URL) + " 2>&1; s=$?; echo; echo \"" + EXIT_MARK + "$s\"";
}

// The last full system upgrade, which is what news is measured against: an
// item older than it describes an upgrade already done.
function lastUpgradeCommand() {
  return "tac /var/log/pacman.log 2>/dev/null | grep -m1 'starting full system upgrade'";
}

const MONTHS = { Jan: 0, Feb: 1, Mar: 2, Apr: 3, May: 4, Jun: 5,
                 Jul: 6, Aug: 7, Sep: 8, Oct: 9, Nov: 10, Dec: 11 };

// "Tue, 22 Sep 2026 09:09:27 +0000" → ms. Parsed by hand: RFC 2822 is not a
// format every JavaScript engine's Date.parse promises to read.
function rfc822(s) {
  const m = /(\d{1,2}) (\w{3}) (\d{4}) (\d\d):(\d\d):(\d\d) ([+-]\d{4}|GMT|UTC)?/.exec(String(s ?? ""));
  if (!m || !(m[2] in MONTHS)) return 0;
  let t = Date.UTC(+m[3], MONTHS[m[2]], +m[1], +m[4], +m[5], +m[6]);
  if (m[7] && /^[+-]/.test(m[7])) {
    const sign = m[7][0] === "-" ? -1 : 1;
    t -= sign * (Number(m[7].slice(1, 3)) * 60 + Number(m[7].slice(3, 5))) * 60000;
  }
  return t;
}

// "[2026-09-23T13:12:18+0300] ..." → ms
function logStamp(line) {
  const m = /^\[(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d)(?::(\d\d))?([+-]\d{4})?\]/.exec(String(line ?? ""));
  if (!m) return 0;
  let t = Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +(m[6] || 0));
  if (m[7]) {
    const sign = m[7][0] === "-" ? -1 : 1;
    t -= sign * (Number(m[7].slice(1, 3)) * 60 + Number(m[7].slice(3, 5))) * 60000;
  }
  return t;
}

function unescapeXml(s) {
  return String(s ?? "").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"")
    .replace(/&#39;|&apos;/g, "'").replace(/&amp;/g, "&");
}

// → { ok, items: [{ title, link, date, text }] }, newest first as published.
// `text` is the description without its markup — the first thing to read,
// not the whole post, which the link is for.
function readNews(out) {
  const r = splitExit(out);
  if (r.code !== 0) return { ok: false, items: [] };
  const xml = r.lines.join("\n");
  const items = [];
  const re = /<item>([\s\S]*?)<\/item>/g;
  let m;
  while ((m = re.exec(xml)) !== null) {
    const it = m[1];
    const get = (tag) => { const x = new RegExp("<" + tag + ">([\\s\\S]*?)</" + tag + ">").exec(it); return x ? x[1] : ""; };
    const text = unescapeXml(get("description")).replace(/<[^>]+>/g, "").replace(/\s+/g, " ").trim();
    items.push({ title: unescapeXml(get("title")).trim(), link: get("link").trim(),
                 date: rfc822(get("pubDate")), text: text });
  }
  return { ok: true, items: items };
}

// Published since the last full upgrade, and not put aside.
function unreadNews(items, lastUpgrade, dismissed) {
  const seen = {};
  for (const l of dismissed || []) seen[l] = true;
  return (items || []).filter(n => n.date > (lastUpgrade || 0) && !seen[n.link]);
}

// Does this transaction move the system forward — the thing news is about?
function isUpgrade(steps) {
  return (steps || []).some(a => /^-S\w*y/.test(a[0] || "") || (a[0] === "-S" && a.indexOf("-y") >= 0));
}

// ── what ceres stands on ──────────────────────────────────────────────────
// Every program ceres runs, the package that provides it, and what ceres
// wants it for — so a missing one is reported as something to install and a
// reason, not as a command that failed. paru is the one not in the repos: it
// is built from its AUR recipe (see setupSteps).
const DEPS = [
  { bin: "paru",              pkg: "paru",              aur: true, why: "installs and updates packages, the AUR included" },
  { bin: "checkupdates",      pkg: "pacman-contrib",    why: "checks for updates without root" },
  { bin: "paccache",          pkg: "pacman-contrib",    why: "trims the package cache" },
  { bin: "pacdiff",           pkg: "pacman-contrib",    why: "merges .pacnew files" },
  { bin: "expac",             pkg: "expac",             why: "package sizes" },
  { bin: "fzf",               pkg: "fzf",               why: "searching packages" },
  { bin: "gawk",              pkg: "gawk",              why: "building the package list" },
  { bin: "inotifywait",       pkg: "inotify-tools",     why: "noticing when pacman finishes" },
  { bin: "curl",              pkg: "curl",              why: "Arch news" },
  { bin: "git",               pkg: "git",               why: "AUR builds" },
  { bin: "xdg-open",          pkg: "xdg-utils",         why: "opening links" },
  { bin: "xdg-terminal-exec", pkg: "xdg-terminal-exec", why: "anything that needs a terminal" },
  { bin: "notify-send",       pkg: "libnotify",         why: "update toasts" }
];

// Prints each missing program's name, one per line — and "cargo" when that
// is missing too, since building paru needs it (rust provides it; someone on
// rustup already has it, and must not be handed rust on top).
function depsCommand() {
  return DEPS.map(d => "command -v " + q(d.bin) + " >/dev/null 2>&1 || echo " + q(d.bin)).join("; ")
    + "; command -v cargo >/dev/null 2>&1 || echo cargo; true";
}

// → { missing: [{ pkg, aur, why: [..] }], paru: bool, cargo: bool } — one row
// per PACKAGE, however many of its programs are missing.
function readDeps(text) {
  const gone = {};
  for (const l of String(text ?? "").split("\n")) if (l.trim()) gone[l.trim()] = true;
  const byPkg = {}, order = [];
  for (const d of DEPS) {
    if (!gone[d.bin]) continue;
    if (!byPkg[d.pkg]) { byPkg[d.pkg] = { pkg: d.pkg, aur: !!d.aur, why: [] }; order.push(d.pkg); }
    byPkg[d.pkg].why.push(d.why);
  }
  return { missing: order.map(p => byPkg[p]), paru: !!gone["paru"], cargo: !!gone["cargo"] };
}

// The steps that install what is missing. `paru` is "paru", "paru-git" or ""
// (paru present). Repo packages first, in one pacman call — with base-devel
// and git whenever paru is to be built, and rust only when there is no cargo.
// Then paru: its AUR recipe cloned and built AS YOU (makepkg refuses root,
// and should), and the result installed by pacman, so paru is a package pacman
// knows and can upgrade. The build happens under the cache, not /tmp — a Rust
// build tree is large and /tmp is RAM — and is removed afterwards.
//
// AND THE SYSTEM IS BROUGHT CURRENT ON THE WAY. The pacman step is -Syu: the
// databases synced, everything upgraded, and the missing packages installed,
// in one transaction — installing onto freshly synced databases WITHOUT
// upgrading is the partial upgrade Arch warns against. Last, with paru in
// place, ceres' own AUR list is fetched (`script aur`), so onboarding ends
// with nothing left to sync by hand.
function setupSteps(deps, paru, buildDir, script) {
  const repo = (deps.missing || []).filter(m => !m.aur).map(m => m.pkg);
  const steps = [];
  if (paru) {
    for (const p of ["base-devel", "git"]) if (repo.indexOf(p) < 0) repo.push(p);
    if (deps.cargo) repo.push("rust");
  }
  if (repo.length === 0 && !paru) return steps;
  steps.push(["@sudo", "pacman", "-Syu", "--needed", "--noconfirm"].concat(repo));
  if (paru) {
    const d = q(buildDir);
    steps.push(["@user",
      "set -e; rm -rf " + d + "; mkdir -p " + d + "; cd " + d + "; "
      + "echo ':: Fetching the " + paru + " recipe from the AUR'; "
      + "git clone --depth 1 " + q("https://aur.archlinux.org/" + paru + ".git") + " recipe; cd recipe; "
      + "echo ':: Building " + paru + "'; "
      + "makepkg --noconfirm --needed -f; "
      + "pkgs=$(ls *.pkg.tar.* | grep -v -- '-debug-' | grep -v '\\.sig$'); "
      + "echo ':: Installing ' $pkgs; "
      + "sudo -A pacman -U --noconfirm $pkgs; "
      + "cd /; rm -rf " + d]);
  }
  if (script) steps.push(["@user", q(script) + " aur"]);
  return steps;
}

// ── sorting the package list ──────────────────────────────────────────────
// "" keeps the order the search gave — fzf's, best match first — which is the
// right order for a query and the only one that knows anything about it.
// Repos sort in pacman's own order, testing after the stable ones, the AUR
// and local after all of them; ties fall back to the name.
const REPO_ORDER = ["core", "extra", "multilib", "core-testing", "extra-testing", "multilib-testing", "aur", "local"];

function repoRank(r) {
  const i = REPO_ORDER.indexOf(r);
  return i >= 0 ? i : REPO_ORDER.length - 2;   // an unknown repo: before the AUR
}

function sortRows(rows, key, desc) {
  if (!key) return rows;
  const byName = (a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0;
  const cmp = key === "size" ? (a, b) => (a.size - b.size) || byName(a, b)
    : key === "repo" ? (a, b) => (repoRank(a.repo) - repoRank(b.repo)) || byName(a, b)
    : byName;
  const out = rows.slice().sort(cmp);
  return desc ? out.reverse() : out;
}

// Every word of the filter somewhere in the name: "gst bad" finds
// gst-plugins-bad. The same rule fzf applies to the package search.
function matchesAll(name, query) {
  const n = String(name).toLowerCase();
  return String(query ?? "").toLowerCase().split(/\s+/).filter(t => t !== "")
    .every(t => n.indexOf(t) >= 0);
}

// ── programs still running replaced code ──────────────────────────────────
// An upgrade replaces a library on disk, but a program already running keeps
// the old copy mapped until it restarts — the kernel marks that copy
// "(deleted)" in /proc/<pid>/maps. Only your own processes can be read
// without root, which covers every app and session service you run.
//
// One line per affected process: pid, name, the systemd unit it runs in if it
// is a user service (its cgroup's last component, when that is a .service),
// and up to three replaced files, comma-joined.
function staleCommand() {
  return "for p in /proc/[0-9]*; do [ -O \"$p\" ] || continue; "
    + "m=$(grep -oE '/usr/(lib|bin)[^ ]* \\(deleted\\)$' \"$p/maps\" 2>/dev/null | sed 's/ (deleted)//' | sort -u | head -3 | tr '\\n' ','); "
    + "e=$(readlink \"$p/exe\" 2>/dev/null); case \"$e\" in *' (deleted)') m=\"$m${e% (deleted)},\";; esac; "
    + "[ -n \"$m\" ] || continue; "
    + "u=$(tail -n1 \"$p/cgroup\" 2>/dev/null | sed 's|.*/||'); case \"$u\" in *.service) ;; *) u=;; esac; "
    + "printf '%s\\t%s\\t%s\\t%s\\n' \"${p#/proc/}\" \"$(cat \"$p/comm\" 2>/dev/null)\" \"$u\" \"$m\"; done";
}

// → [{ name, unit, service, pids: [..], files: [..] }], services and apps each
// grouped by name, the most processes first. A service is anything running as
// a systemd user unit; the rest are apps.
function readStale(text) {
  const by = {};
  for (const l of String(text ?? "").split("\n")) {
    const f = l.split("\t");
    if (f.length < 4 || !f[1]) continue;
    const key = f[1] + "|" + f[2];
    if (!by[key]) by[key] = { name: f[1], unit: f[2], service: f[2] !== "", pids: [], files: [] };
    const g = by[key];
    g.pids.push(Number(f[0]));
    for (const x of f[3].split(",")) if (x && g.files.indexOf(x) < 0) g.files.push(x);
  }
  return Object.keys(by).map(k => by[k])
    .sort((a, b) => (a.service - b.service) || (b.pids.length - a.pids.length) || (a.name < b.name ? -1 : 1));
}

// "firefox, discord" / "firefox, discord and 3 more" — for a one-line note
function nameList(names, most) {
  const n = names.length;
  if (n <= most) return names.join(", ");
  return names.slice(0, most).join(", ") + " and " + (n - most) + " more";
}

// ── the Arch Linux Archive ────────────────────────────────────────────────
// Every version of every official package ever built, at
// archive.archlinux.org/packages/<first letter>/<name>/. Where History's way
// back goes when the local cache no longer has the version: pacman installs
// straight from the URL and still checks the signature. AUR packages are not
// there; their listing is simply empty.
const ARCHIVE = "https://archive.archlinux.org/packages/";

function archiveDir(name) {
  const n = String(name);
  return ARCHIVE + encodeURIComponent(n.charAt(0)) + "/" + encodeURIComponent(n) + "/";
}

function archiveCommand(name) {
  return "curl -fsS --max-time 20 " + q(archiveDir(name)) + " 2>/dev/null"
    + " | grep -oE 'href=\"[^\"]+\\.pkg\\.tar\\.[a-z0-9]+\"' | sed 's/^href=\"//; s/\"$//; s/%3A/:/g' | sort -V";
}

// Listing → [{ version, url }], exactly this package's, oldest first. The
// names come URL-encoded (an epoch's colon is %3A); readCached does the
// matching once they are plain file names.
function readArchive(name, text) {
  const files = String(text ?? "").split("\n").filter(l => l.trim() !== "");
  const plain = files.map(f => { try { return decodeURIComponent(f.trim()); } catch (e) { return f.trim(); } });
  return byVersion(readCached(name, plain.join("\n"))).map((c, i) => ({
    version: c.version,
    url: archiveDir(name) + encodeURIComponent(c.file.replace(/^.*\//, ""))
  }));
}

// ── pacman's version order ────────────────────────────────────────────────
// alpm's vercmp, in JavaScript: epoch first, then the version by rpmvercmp's
// segment rules, then the release. `sort -V` does not know epochs — it put
// less 1:710 below less 580 — and a list of versions to go back to has to be
// in the order pacman itself would call newer.
function rpmvercmp(a, b) {
  if (a === b) return 0;
  let i = 0, j = 0;
  const alnum = (c) => /[A-Za-z0-9]/.test(c);
  while (i < a.length || j < b.length) {
    while (i < a.length && !alnum(a[i])) i++;
    while (j < b.length && !alnum(b[j])) j++;
    if (i >= a.length || j >= b.length) break;
    const numeric = /[0-9]/.test(a[i]);
    const seg = (s, k) => { let e = k; while (e < s.length && (numeric ? /[0-9]/.test(s[e]) : /[A-Za-z]/.test(s[e]))) e++; return e; };
    const ei = seg(a, i), ej = seg(b, j);
    const sa = a.slice(i, ei), sb = b.slice(j, ej);
    if (sb === "") return numeric ? 1 : -1;     // a number beats letters
    if (numeric) {
      const na = sa.replace(/^0+/, ""), nb = sb.replace(/^0+/, "");
      if (na.length !== nb.length) return na.length > nb.length ? 1 : -1;
      if (na !== nb) return na > nb ? 1 : -1;
    } else if (sa !== sb) return sa > sb ? 1 : -1;
    i = ei; j = ej;
  }
  const ra = a.slice(i), rb = b.slice(j);
  if (ra === "" && rb === "") return 0;
  // what is left over: a letter suffix is OLDER (1.0a < 1.0), anything else newer
  if (ra === "") return /^[A-Za-z]/.test(rb) ? 1 : -1;
  return /^[A-Za-z]/.test(ra) ? -1 : 1;
}

function vercmp(a, b) {
  const split = (v) => {
    const m = /^(?:(\d+):)?(.*?)(?:-([^-]*))?$/.exec(String(v));
    return { e: m[1] || "0", v: m[2], r: m[3] };
  };
  const x = split(a), y = split(b);
  const ec = rpmvercmp(x.e, y.e);
  if (ec !== 0) return ec;
  const vc = rpmvercmp(x.v, y.v);
  if (vc !== 0 || x.r === undefined || y.r === undefined) return vc;
  return rpmvercmp(x.r, y.r);
}

function byVersion(list) {
  return list.slice().sort((p, q) => vercmp(p.version, q.version));
}

// ── AUR health ────────────────────────────────────────────────────────────
// What the AUR itself says about the AUR packages you have: flagged out of
// date (someone reported upstream is ahead), orphaned (no maintainer — no one
// will update it), or gone from the AUR altogether. One POST for all of them
// (no URL-length ceiling); `-debug` packages are makepkg's split debug symbols
// and were never on the AUR, so they are left out rather than called gone.
function aurHealthCommand() {
  return "names=$(pacman -Qmq 2>/dev/null | grep -v -- '-debug$')\n"
    + "echo '@@names'; printf '%s\\n' $names\n"
    + "echo '@@json'\n"
    + "[ -n \"$names\" ] && curl -fsS --max-time 20 https://aur.archlinux.org/rpc/v5/info "
    + "$(for n in $names; do printf -- \"--data-urlencode arg[]=%s \" \"$n\"; done) 2>/dev/null\n"
    + "s=$?; echo; echo \"" + EXIT_MARK + "$s\"";
}

// → { ok, checked, problems: [{ name, flagged (ms, 0 if not), orphaned, gone }] }
function readAurHealth(text) {
  const r = splitExit(text);
  if (r.code !== 0) return { ok: false, checked: 0, problems: [] };
  const all = r.lines.join("\n");
  const names = [];
  const ni = all.indexOf("@@names"), ji = all.indexOf("@@json");
  if (ni < 0 || ji < 0) return { ok: false, checked: 0, problems: [] };
  for (const l of all.slice(ni + 7, ji).split("\n")) if (l.trim()) names.push(l.trim());
  if (names.length === 0) return { ok: true, checked: 0, problems: [] };
  let data = null;
  try { data = JSON.parse(all.slice(ji + 6).trim()); } catch (e) { return { ok: false, checked: 0, problems: [] }; }
  if (!data || !Array.isArray(data.results)) return { ok: false, checked: 0, problems: [] };
  const by = {};
  for (const x of data.results) by[x.Name] = x;
  const problems = [];
  for (const n of names) {
    const x = by[n];
    if (!x) { problems.push({ name: n, flagged: 0, orphaned: false, gone: true }); continue; }
    const flagged = x.OutOfDate ? Number(x.OutOfDate) * 1000 : 0;
    const orphaned = !x.Maintainer;
    if (flagged || orphaned) problems.push({ name: n, flagged: flagged, orphaned: orphaned, gone: false });
  }
  return { ok: true, checked: names.length, problems: problems };
}

// ── what needs a package, and what it put on disk ─────────────────────────
// For an installed package only. `pactree -ru` is every package that would
// lose it, directly or through something else — pacman's own "Required By"
// is only the first step of that chain, and the whole chain is what matters
// before a removal. `pacman -Ql` is its files, directories left out.
function extrasCommand(name) {
  const n = q(name);
  return "echo '@@rdeps'; pactree -ru -- " + n + " 2>/dev/null | tail -n +2\n"
    + "echo '@@files'; pacman -Ql -- " + n + " 2>/dev/null | cut -d' ' -f2- | grep -v '/$'\n"
    + "echo '@@end'";
}

function readExtras(text) {
  const out = { rdeps: [], files: [] };
  let sec = "";
  for (const raw of String(text ?? "").split("\n")) {
    const l = raw.trim();
    if (l === "@@rdeps") { sec = "rdeps"; continue; }
    if (l === "@@files") { sec = "files"; continue; }
    if (l === "@@end") break;
    if (l === "" || !sec) continue;
    out[sec].push(l);
  }
  out.rdeps.sort();
  return out;
}

// ── undoing a transaction ─────────────────────────────────────────────────
// A whole transaction taken back, from History: what it upgraded goes back to
// the version it replaced, what it installed is removed, what it removed
// comes back. Each package only if it is STILL as that transaction left it —
// a later upgrade of the same package means going back would jump over it,
// so that one is skipped and says why rather than being quietly clobbered.
//
// The copies come from pacman's cache, then paru's build folders (which keep
// the AUR builds pacman never cached), then the Arch archive — which only
// ever has the official packages.

// Everything installed, then every package file on disk that could be a way
// back. One path per line; readUndo matches them by name.
function undoCommand(cloneDir) {
  return "pacman -Q 2>/dev/null; echo '@@files'; "
    + "find /var/cache/pacman/pkg " + q(cloneDir)
    + " -maxdepth 2 -name '*.pkg.tar.*' ! -name '*.sig' 2>/dev/null; true";
}

// The packages a command NAMED: what was asked for, as opposed to what came
// along. "pacman --remove -s --noconfirm -- gimp" → ["gimp"]. After a `--`
// everything is a name; without one, every word that is not a flag.
function commandTargets(cmd) {
  const w = String(cmd ?? "").trim().split(/\s+/).slice(1);
  const dd = w.indexOf("--");
  const names = dd >= 0 ? w.slice(dd + 1) : w.filter(x => x !== "" && x[0] !== "-");
  return names.map(n => n.replace(/^.*\//, ""));
}

// → { back: [{ name, now, version, file }], remove: [{ name, version }],
//     skipped: [{ name, why }], missing: [{ name, version }] }
// `missing` is going back with no local copy — the archive is asked next.
function readUndo(tx, text) {
  const parts = String(text ?? "").split("@@files\n");
  const installed = {};
  for (const l of (parts[0] || "").split("\n")) {
    const m = /^(\S+)\s+(\S+)$/.exec(l.trim());
    if (m) installed[m[1]] = m[2];
  }
  const files = (parts[1] || "").split("\n").filter(l => l.trim() !== "");
  const copyOf = (name, version) => {
    const base = files.map(f => f.replace(/^.*\//, ""));
    for (const c of readCached(name, base.join("\n")))
      if (c.version === version) {
        const want = c.file.replace(/^.*\//, "");
        return files.find(f => f.replace(/^.*\//, "") === want) || null;
      }
    return null;
  };
  const out = { back: [], remove: [], skipped: [], missing: [] };
  // A package brought back by pacman -U is marked as installed on purpose.
  // One the transaction removed only because something else went (-Rs took
  // it along) was a dependency, and has to be one again — or it is never an
  // orphan afterwards. Upgrades and downgrades keep their reason on their own.
  const named = commandTargets(tx && tx.command);
  const goBack = (name, now, version) => {
    // With no command on record nothing is known to have come along, and
    // guessing "dependency" is the dangerous way round: a package you wanted,
    // marked as a dependency, is swept up as an orphan later.
    const asdeps = now === "" && named.length > 0 && named.indexOf(name) < 0;
    const file = copyOf(name, version);
    if (file) out.back.push({ name: name, now: now, version: version, file: file, asdeps: asdeps });
    else out.missing.push({ name: name, now: now, version: version, asdeps: asdeps });
  };
  for (const e of (tx && tx.events) || []) {
    const now = installed[e.name];
    if (e.verb === "upgraded" || e.verb === "downgraded") {
      if (now === undefined) out.skipped.push({ name: e.name, why: "removed since" });
      else if (now !== e.to) out.skipped.push({ name: e.name, why: "changed since, now " + now });
      else goBack(e.name, now, e.from);
    } else if (e.verb === "installed") {
      if (now === undefined) continue;                 // already gone: nothing to undo
      if (now !== e.to) out.skipped.push({ name: e.name, why: "changed since, now " + now });
      else out.remove.push({ name: e.name, version: now });
    } else if (e.verb === "removed") {
      if (now !== undefined) out.skipped.push({ name: e.name, why: "installed again since" });
      else goBack(e.name, "", e.to);
    }
    // reinstalled: the same version before and after — nothing to take back
  }
  return out;
}

// The archive, asked only about what had no local copy.
function undoArchiveCommand(missing) {
  return (missing || []).map(m => "echo " + q("@@pkg " + m.name) + "; " + archiveCommand(m.name))
    .join("; ");
}

// The archive's answers folded into the plan: found → going back from the
// archive; not found → skipped, which is every AUR package without a build.
function withArchive(plan, text) {
  const lists = {};
  let cur = null;
  for (const l of String(text ?? "").split("\n")) {
    const m = /^@@pkg (\S+)$/.exec(l);
    if (m) { cur = m[1]; lists[cur] = []; continue; }
    if (cur && l.trim() !== "") lists[cur].push(l.trim());
  }
  const out = { back: plan.back.slice(), remove: plan.remove.slice(), skipped: plan.skipped.slice(), missing: [] };
  for (const m of plan.missing) {
    const hit = readArchive(m.name, (lists[m.name] || []).join("\n")).find(a => a.version === m.version);
    if (hit) out.back.push({ name: m.name, now: m.now, version: m.version, url: hit.url, asdeps: m.asdeps });
    else out.skipped.push({ name: m.name, why: "no copy of " + m.version + " left" });
  }
  return out;
}

// One pacman -U for everything going back — together, so a library and the
// programs built against it move as one — then one -R for what the
// transaction brought in.
function undoSteps(plan) {
  const steps = [];
  const sources = plan.back.map(b => b.file || b.url);
  if (sources.length) steps.push(["@sudo", "pacman", "-U", "--noconfirm"].concat(sources));
  const deps = plan.back.filter(b => b.asdeps).map(b => b.name);
  if (deps.length) steps.push(["@sudo", "pacman", "-D", "--asdeps"].concat(deps));
  if (plan.remove.length) steps.push(["@sudo", "pacman", "-R", "--noconfirm"].concat(plan.remove.map(r => r.name)));
  return steps;
}

// ── the mirrors ───────────────────────────────────────────────────────────
// How good the mirrorlist is, from two sources: Arch's own status feed (is
// each mirror synced, and how far behind) and a timing taken from HERE —
// the only place that knows where here is. A fresh list is ranked the same
// way reflector's --sort rate does it, without reflector: every mirror the
// feed calls healthy is timed on a tiny file, the quickest twelve then
// download a real file one at a time, and the fastest ten are kept.
const MIRRORLIST = "/etc/pacman.d/mirrorlist";
const MIRROR_STATUS = "https://archlinux.org/mirrors/status/json/";

// A Server line's mirror, as the status feed names it: the URL up to
// $repo. "https://x/archlinux/$repo/os/$arch" → "https://x/archlinux/".
function mirrorBase(server) {
  return String(server ?? "").replace(/^\s*Server\s*=\s*/, "").trim().replace(/\$repo.*$/, "");
}

function mirrorHost(base) {
  return String(base ?? "").replace(/^[a-z]+:\/\//, "").replace(/\/.*$/, "");
}

function mirrorHealthCommand() {
  const first = "$(grep -m1 -E '^\\s*Server\\s*=' " + MIRRORLIST
    + " | sed -E 's/^\\s*Server\\s*=\\s*//; s/\\$repo.*$//')";
  return "stat -c %Y " + MIRRORLIST + " 2>/dev/null; echo '@@list'; "
    + "grep -E '^\\s*Server\\s*=' " + MIRRORLIST + " 2>/dev/null; echo '@@status'; "
    + "curl -fsS --max-time 20 " + q(MIRROR_STATUS) + " 2>/dev/null; echo; echo '@@probe'; "
    + "f=" + first + "; [ -n \"$f\" ] && curl -o /dev/null -s -w '%{time_total} %{http_code}' "
    + "--connect-timeout 3 --max-time 6 \"${f}lastupdate\"; true";
}

// A mirror is out of sync when the feed has not seen it sync, it is
// missing packages, or it is more than a day behind.
function mirrorBehind(s) {
  return !s || !s.last_sync || s.completion_pct < 1 || s.delay === null || s.delay > 86400;
}

// → { modified, servers: [{ base, host, country, status }], status: {base → entry},
//     behind, unknown, firstMs, statusOk }
function readMirrorHealth(text) {
  const sec = { head: "", list: "", status: "", probe: "" };
  let cur = "head";
  for (const line of String(text ?? "").split("\n")) {
    const m = /^@@(list|status|probe)$/.exec(line);
    if (m) { cur = m[1]; continue; }
    sec[cur] += line + "\n";
  }
  const out = { modified: (parseInt(sec.head, 10) || 0) * 1000, servers: [], status: {},
                behind: 0, unknown: 0, firstMs: -1, statusOk: false };
  try {
    for (const u of JSON.parse(sec.status).urls || []) out.status[u.url] = u;
    out.statusOk = true;
  } catch (e) {}
  for (const l of sec.list.split("\n")) {
    if (!/^\s*Server\s*=/.test(l)) continue;
    const base = mirrorBase(l), s = out.status[base] || null;
    out.servers.push({ base: base, host: mirrorHost(base), country: s ? s.country_code : "", status: s });
    if (!out.statusOk) continue;
    if (!s) out.unknown++;
    else if (mirrorBehind(s)) out.behind++;
  }
  const p = /^(\S+)\s+(\d+)/.exec(sec.probe.trim());
  if (p && p[2] === "200") out.firstMs = Math.round(parseFloat(p[1]) * 1000);
  return out;
}

// Everything the feed calls healthy over https: active, complete, and less
// than three hours behind. ~280 mirrors; timing them all takes seconds.
function mirrorCandidates(status) {
  return Object.keys(status || {}).map(k => status[k]).filter(s =>
    s.active && s.protocol === "https" && s.completion_pct === 1
    && s.delay !== null && s.delay < 3 * 3600).map(s => s.url);
}

// Stage one: every candidate, in parallel, on the one-line lastupdate file —
// mostly the connection's round trip. One line per mirror as it answers, so
// progress can be counted. Stage two: the quickest `keep` of those download
// core.files one at a time — in turn, so they do not share the line — for
// the bytes per second pacman will actually see. core.files, not core.db:
// at 130 KB the db is over before a connection reaches its speed, and every
// mirror read the same; 1.5 MB tells them apart (measured 2026-09-24).
// (No '@' at the start of a -w format: curl reads that as a file to load it from.)
function rankCommand(candidates, keep) {
  return "printf '%s\\n' " + (candidates || []).map(q).join(" ")
    + " | xargs -P 48 -I{} curl -o /dev/null -s -w 'ping %{time_total} %{http_code} {}\\n'"
    + " --connect-timeout 2 --max-time 4 '{}lastupdate' > \"${TMPDIR:-/tmp}/ceres-ping.$$\"; "
    + "cat \"${TMPDIR:-/tmp}/ceres-ping.$$\"; "
    + "awk '$3 == 200 { print $2, $4 }' \"${TMPDIR:-/tmp}/ceres-ping.$$\" | sort -n | head -" + (keep | 0)
    + " | while read -r t u; do curl -o /dev/null -s -w \"rate %{speed_download} %{http_code} $u\\n\""
    + " --connect-timeout 3 --max-time 8 \"${u}core/os/x86_64/core.files\"; done; "
    + "rm -f \"${TMPDIR:-/tmp}/ceres-ping.$$\"";
}

// → { pinged, answered, ranked: [{ base, host, ms, rate }] } — the fastest
// by download rate, the round trip kept to show beside it.
function readRank(text, n) {
  const ping = {};
  let pinged = 0, answered = 0;
  const rates = [];
  for (const l of String(text ?? "").split("\n")) {
    let m = /^ping (\S+) (\d+) (\S+)$/.exec(l);
    if (m) {
      pinged++;
      if (m[2] === "200") { answered++; ping[m[3]] = Math.round(parseFloat(m[1]) * 1000); }
      continue;
    }
    m = /^rate (\S+) (\d+) (\S+)$/.exec(l);
    if (m && m[2] === "200") rates.push({ base: m[3], host: mirrorHost(m[3]), ms: ping[m[3]] ?? -1, rate: parseFloat(m[1]) });
  }
  rates.sort((a, b) => b.rate - a.rate);
  return { pinged: pinged, answered: answered, ranked: rates.slice(0, n) };
}

// The new mirrorlist, saying where it came from.
function mirrorlistText(ranked, when) {
  return "# Ranked by ceres on " + when + ": the fastest from this machine among the\n"
    + "# mirrors archlinux.org reports as fully synced. The list before it is\n"
    + "# kept as " + MIRRORLIST + ".ceres-bak.\n\n"
    + (ranked || []).map(r => "Server = " + r.base + "$repo/os/$arch").join("\n") + "\n";
}

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

.pragma library
// ONE COPY FOR THE WHOLE SHELL. Without the pragma every component instance
// that imports this file evaluated all of it again (qmlprofiler, 2026-10-09;
// see morpheus/icons.js and terminus/terminus.js for what that cost).

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

// The AUR, through paru, so the count honors IgnorePkg, IgnoreGroup and
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
function describe(repo, aur, ink, limit, notes, flat) {
  const lines = [];
  for (const n of notes || []) lines.push("<font color='" + ink.warn + "'>" + esc(n) + "</font>");
  if ((notes || []).length && ((repo || []).length || (aur || []).length || (flat || []).length)) lines.push("");

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
  // Flathub's, beside the system's (user, 2026-10-14) — the bar's tooltip
  // and the toast both
  group(flat, "\uF324", ink.flat || ink.repo, "Flatpak Update", "Flatpak Updates");
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

// Each step under `script`, on a pseudo-terminal of a fixed width, so pacman
// draws its bars — see cleanLine. `-e` hands back the step's own exit code;
// stdin is still /dev/null behind it, so a prompt --noconfirm did not cover
// reads end-of-file and fails, exactly as it did without the terminal.
function ptyCommand(cmd) {
  return "script -qefc " + q("stty cols 110 2>/dev/null; " + cmd) + " /dev/null";
}

// `tag` is a token fresh for each run, worn by its marks: the steps' own
// output passes through the same stream, and an AUR build or an install
// script that printed "@@exit 0" ended the job on the spot — the window
// unlocked for a second transaction while pacman still held its lock.
function runCommand(fifo, askpass, steps, tag, noAuth) {
  const t = String(tag ?? "");
  const mark = EXIT_MARK.replace(/ $/, "") + t + " ";
  const run = (steps || []).map(a =>
    "[ \"$s\" -eq 0 ] && { " + ptyCommand(stepCommand(a)) + " </dev/null 2>&1 || s=$?; }\n").join("");
  // NOTHING OF ROOT'S, NO PASSWORD (a Flatpak installed just for you): no
  // sudo to warm, no fifo to serve — marked authed at once, so the job is
  // read exactly as one that was asked for a password. See needsRoot.
  if (noAuth)
    return "IFS= read -r pw; pw=\n"
      + "printf '\\n@@authed" + t + "\\n'\n"
      + "s=0\n" + run
      + "printf '\\n" + mark + "%s\\n' \"$s\"";
  return "f=" + q(fifo) + "\n"
    + "clean() { rm -f \"$f\" \"$f.spent\" \"$f.once\"; }\n"
    + "clean; mkfifo -m 600 \"$f\" || { echo '" + mark + "9'; exit 9; }\n"
    + "IFS= read -r pw\n"
    + "export SUDO_ASKPASS=" + q(askpass) + " CERES_FIFO=\"$f\"\n"
    + ": > \"$f.once\"\n"
    + "( printf '%s\\n' \"$pw\" > \"$f\" ) 2>/dev/null & w=$!\n"
    + "if ! sudo -A -v </dev/null 2>&1; then\n"
    + "  kill \"$w\" 2>/dev/null; clean; echo '" + mark + AUTH_FAILED + "'; exit " + AUTH_FAILED + "\n"
    + "fi\n"
    + "kill \"$w\" 2>/dev/null; rm -f \"$f.once\" \"$f.spent\"\n"
    + "printf '\\n@@authed" + t + "\\n'\n"
    // SIGPIPE ignored, or the first reader to close early kills the server
    // and the next sudo waits on a fifo nobody will ever write to again.
    + "( trap '' PIPE; while :; do printf '%s\\n' \"$pw\" > \"$f\"; done ) 2>/dev/null & w=$!\n"
    + "pw=\n"
    + "s=0\n"
    + run
    + "kill \"$w\" 2>/dev/null; clean\n"
    // On a line of its own. The last step ran on a pty, and pacman's final
    // output need not end in a line break — the mark printed straight after
    // it landed on the end of that text and went unread, and a removal that
    // had worked was reported as "paru stopped (exit -1)".
    + "printf '\\n" + mark + "%s\\n' \"$s\"";
}

// ── STOPPING A JOB, FOR REAL (user, 2026-10-18) ──────────────────────────
// Shift+Esc used to send SIGINT and wait. pacman decides for itself what an
// interrupt means, paru carries on to its next package after a build is
// interrupted, and a user's kill cannot reach what runs as root at all — so
// a long AUR build "cancelled" ran on to its end. This escalates:
//
//   1. SIGINT to the whole tree (pacman's own ctrl+c) — 3 s to go
//   2. SIGTERM, 2 s;  3. SIGKILL
//   root's processes the same way through `sudo -S`, with the password the
//   job was started with (read from stdin; none for a job that needed none)
//
// EXCEPT WHILE PACMAN WRITES TO THE DISK (`committing`: the Installing and
// hooks phases). Killed there, a package is left half on the disk; it stays
// at step 1, and pacman stops cleanly after the package in hand.
//
// Once nothing of the job is left: pacman's lock if no pacman holds it, the
// partial downloads, and paru's build directories this job touched (newer
// than `since`, epoch seconds) — an interrupted build leaves gigabytes.
// Prints "@@stopped 1" when the job is gone, "@@stopped 0" when it was left
// to finish the package in hand.
function stopCommand(pid, committing, since, cloneDir) {
  return "IFS= read -r pw\n"
    + "root=" + Number(pid) + "; committing=" + (committing ? 1 : 0) + "; since=" + Number(since || 0) + "\n"
    + "clone=" + q(cloneDir) + "\n"
    + "tree() { for c in $(pgrep -P \"$1\"); do tree \"$c\"; echo \"$c\"; done; }\n"
    // a zombie is gone: dead, only not yet reaped by whoever started it
    + "alive() { kill -0 \"$root\" 2>/dev/null && ! grep -q ') Z ' /proc/$root/stat 2>/dev/null; }\n"
    + "asroot() { [ -n \"$pw\" ] && printf '%s\\n' \"$pw\" | sudo -S -p '' \"$@\" >/dev/null 2>&1; }\n"
    + "sig() { p=\"$(tree \"$root\") $root\"; kill -\"$1\" $p 2>/dev/null; asroot kill -\"$1\" $p; }\n"
    + "gone() { n=0; while alive && [ $n -lt \"$1\" ]; do sleep 0.1; n=$((n+1)); done; ! alive; }\n"
    + "sig INT\n"
    + "if [ $committing = 0 ]; then\n"
    + "  gone 30 || { sig TERM; gone 20; } || { sig KILL; gone 20; }\n"
    + "fi\n"
    + "if alive; then echo '@@stopped 0'; exit 0; fi\n"
    + "echo '@@stopped 1'\n"
    + "pgrep -x pacman >/dev/null || asroot sh -c 'rm -f /var/lib/pacman/db.lck; "
    + "find /var/cache/pacman/pkg -maxdepth 1 -name \"*.part\" -delete'\n"
    + "[ \"$since\" -gt 0 ] && [ -d \"$clone\" ] && "
    + "find \"$clone\" -mindepth 1 -maxdepth 1 -type d -newermt \"@$since\" -exec rm -rf {} + 2>/dev/null\n"
    + "exit 0";
}

// Whether any step needs root: a pacman/paru step, an @sudo, or an @user
// shell line that calls sudo itself. One that does not runs with no password.
function needsRoot(steps) {
  return (steps || []).some(a => a[0] !== "@user" || /\bsudo\b/.test(a[1] || ""));
}

// A transaction's own marks, found at the END of a line as well as being the
// whole of it — the same rule splitExit keeps, for the same reason. `before`
// is whatever the line carried ahead of the mark, which is still log.
function txMark(line, tag) {
  const l = String(line ?? ""), t = String(tag ?? "");
  if (l.endsWith("@@authed" + t)) return { kind: "authed", before: l.slice(0, l.length - 8 - t.length) };
  const e = /^(.*?)@@exit(\S*) (-?\d+)$/.exec(l);
  if (e && e[2] === t) return { kind: "exit", code: parseInt(e[3], 10), before: e[1] };
  return null;
}

// How much of `to` is the same as `from`, cut back to just after the last
// separator (. - : + _ ~) before they part, so a change is lit as a whole
// component: 3.130-1 → 3.131-1 gives "3." and lights "131-1", never "31-1".
function versionSplit(from, to) {
  const a = String(from ?? ""), b = String(to ?? "");
  let i = 0;
  while (i < a.length && i < b.length && a[i] === b[i]) i++;
  if (i === b.length && i === a.length) return b.length;
  while (i > 0 && !/[.\-:+_~]/.test(b[i - 1])) i--;
  return i;
}

// What a transaction is, as steps. The whole list is a full upgrade —
// anything less is a partial one, which Arch does not support.
function upgradeSteps() { return [["-Syu"]]; }

// ── HELD BACK: PARU'S MINIMUM RELEASE AGE ─────────────────────────────────
// paru 2.2.0's MinimumReleaseAge refuses an AUR package changed more
// recently than the age — and refuses the WHOLE -Syu with it, not that one
// package: one fresh update would stop every AUR update until it aged. paru
// -Qua still lists it. So Ceres asks the AUR when each update last changed,
// marks the ones still too new, and a full upgrade leaves them out with
// --ignore (paru honors it for the AUR too); they come in on the first
// upgrade after they clear. Devel packages (DevelSuffixes) and
// MinimumReleaseAgeExclude's globs are spared, exactly as paru spares them.

// When each update last changed on the AUR: one POST for all of them.
function aurAgesCommand(names) {
  return "curl -fsS --max-time 20 https://aur.archlinux.org/rpc/v5/info "
    + (names || []).map(n => "--data-urlencode " + q("arg[]=" + n)).join(" ")
    + " 2>/dev/null; s=$?; echo; echo \"" + EXIT_MARK + "$s\"";
}
// → { name: LastModified in ms }, or null when the AUR did not answer
function readAurAges(text) {
  const r = splitExit(text);
  if (r.code !== 0) return null;
  let data = null;
  try { data = JSON.parse(r.lines.join("\n").trim()); } catch (e) { return null; }
  if (!data || !Array.isArray(data.results)) return null;
  const out = {};
  for (const x of data.results) if (x && x.Name && x.LastModified) out[x.Name] = Number(x.LastModified) * 1000;
  return out;
}

// A shell glob (globset's *, ? and [..]) as a whole-name match.
function globRe(g) {
  let re = "";
  for (let i = 0; i < g.length; i++) {
    const c = g[i];
    if (c === "*") re += ".*";
    else if (c === "?") re += ".";
    else if (c === "[") {
      const j = g.indexOf("]", i + 2);
      if (j < 0) { re += "\\["; continue; }
      re += "[" + g.slice(i + 1, j).replace(/^!/, "^").replace(/\\/g, "\\\\") + "]";
      i = j;
    } else re += c.replace(/[.+^${}()|\\\]]/g, "\\$&");
  }
  return new RegExp("^" + re + "$");
}
function ageExempt(name, rule) {
  const n = String(name);
  return (rule.devel || []).some(s => n.endsWith(s)) || (rule.exclude || []).some(g => globRe(g).test(n));
}
// The AUR updates still too new, each with when it clears.
// `rule` is Pac.paruAgeOf's; `ages` readAurAges'. → [{ name, until (ms) }]
function heldOf(aur, rule, ages, now) {
  if (!rule || !(rule.secs > 0) || !ages) return [];
  const out = [];
  for (const u of aur || []) {
    const at = ages[u.name];
    if (!at || ageExempt(u.name, rule)) continue;
    const until = at + rule.secs * 1000;
    if (until > now) out.push({ name: u.name, until: until });
  }
  return out;
}
// A full upgrade without them. Only paru's own -Syu is touched: setup's
// pacman -Syu is the repos', where the age means nothing.
// The very same list back when there is nothing to leave out of it.
function withHeld(steps, names) {
  const hit = a => a[0] === "-Syu" && a.indexOf("--ignore") < 0;
  if (!(names || []).length || !(steps || []).some(hit)) return steps;
  return steps.map(a => hit(a) ? a.concat(["--ignore", names.join(",")]) : a);
}

// 259200 → "3 days": the age as Settings and the job's label say it
function ageWords(secs) {
  const units = [[604800, "week"], [86400, "day"], [3600, "hour"], [60, "minute"], [1, "second"]];
  for (const [n, w] of units)
    if (secs >= n && secs % n === 0) { const k = secs / n; return k + " " + w + (k === 1 ? "" : "s"); }
  return "0 seconds";
}

// paru.conf, the one paru reads: $PARU_CONF, then yours, then the system's.
// The first line says which.
function paruConfCommand() {
  return "p=\"${PARU_CONF:-${XDG_CONFIG_HOME:-$HOME/.config}/paru/paru.conf}\"; "
    + "[ -e \"$p\" ] || p=/etc/paru.conf; echo \"@@path $p\"; cat -- \"$p\" 2>/dev/null";
}
// → { path, lines }
function readParuConf(text) {
  const s = String(text ?? "");
  const nl = s.indexOf("\n");
  const head = nl < 0 ? s : s.slice(0, nl);
  const m = /^@@path (.+)$/.exec(head);
  if (!m) return { path: "", lines: [] };
  const ls = (nl < 0 ? "" : s.slice(nl + 1)).split("\n");
  if (ls.length && ls[ls.length - 1] === "") ls.pop();
  return { path: m[1], lines: ls };
}
// Written beside it and renamed over it, the old one kept as .ceres-bak —
// the system's as root, yours as you (no password for your own file).
function paruConfSteps(path, text) {
  const p = q(path), tmp = q(path + ".ceres-new"), bak = q(path + ".ceres-bak");
  const write = "{ [ ! -e " + p + " ] || cp -p " + p + " " + bak + "; } && printf '%s' " + q(text) + " > " + tmp
    + " && chmod 644 " + tmp + " && mv -f " + tmp + " " + p;
  if (/^\/etc\//.test(path)) return [["@sudo", "sh", "-c", write]];
  return [["@user", "mkdir -p " + q(path.replace(/\/[^/]*$/, "")) + " && " + write]];
}

// paru's refusal, when an install named something still too new — the age
// is in paru.conf, and Ceres only leaves such updates out of a full one:
//   error: the following AUR packages are newer than the minimum release age
//   of 3 days: foo (updated 5 hours ago), bar (updated 1 day ago)
// → { age: "3 days", packages: [{ name, ago }] } or null
function ageRefusalOf(lines) {
  for (const raw of lines || []) {
    const m = /newer than the minimum release age of (.+?): (.+)$/.exec(String(raw).trim());
    if (!m) continue;
    const pkgs = [...m[2].matchAll(/(\S+) \(updated (.+?) ago\)/g)].map(x => ({ name: x[1], ago: x[2] }));
    return { age: m[1], packages: pkgs };
  }
  return null;
}
// The failure, as a sentence: "foo changed on the AUR 5 hours ago, under
// paru's 3 days" — what is new, and the rule it is held by.
function ageRefusalLine(r) {
  const ps = (r && r.packages) || [];
  if (ps.length === 0) return "Held back by paru's minimum release age of " + ((r && r.age) || "?");
  const one = p => p.name + " " + p.ago + " ago";
  return (ps.length === 1 ? ps[0].name + " changed on the AUR " + ps[0].ago + " ago"
    : "Changed on the AUR too recently: " + ps.map(one).join(", "))
    + " \u2014 paru holds back AUR changes newer than " + r.age;
}
// The same steps, once past the age: --nominimumreleaseage on paru's own
// -S steps, for this run only.
function unheldSteps(steps) {
  return (steps || []).map(a => /^-S/.test(a[0] || "") && a.indexOf("--nominimumreleaseage") < 0
    ? [a[0], "--nominimumreleaseage"].concat(a.slice(1)) : a);
}

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

// ── WHAT PARU WANTED A HUMAN FOR ──────────────────────────────────────────
// Steps run with --noconfirm and no stdin, so two of paru's questions can't
// be answered: which of several providers to take (it takes the first), and
// whether an installed package may be replaced by one it conflicts with — it
// refuses outright ("can not install conflicting packages with --noconfirm").
// Both are read off the failed log here, so the window can ask them itself
// rather than sending you to a terminal:
//
//   :: There are 2 providers available for artcraft:
//   :: Repository AUR:
//       1) artcraft  2) artcraft-git
//   :: Conflicts found:
//       nodejs-lts-krypton: nodejs          ← coming in: what it replaces
//
// Or pacman's own form of the same refusal, when paru hands the targets
// straight on (2026-10-14: bitwarden-cli wanted nodejs-lts-jod):
//
//   :: nodejs-lts-jod-22.23.3-2 and nodejs-26.11.1-1 are in conflict. Remove nodejs? [y/N]
//   error: unresolvable package conflicts detected
//
// read as the same "nodejs-lts-jod replaces nodejs" (--useask answers it).
//
// null when the log holds no refused conflict — a provider menu alone was
// answered (with the first) and is not why anything failed.
// "nodejs-lts-jod-22.23.3-2" → "nodejs-lts-jod": pacman names a package
// there with its version and release
function stripVersion(s) {
  const m = /^(.+)-[^-]+-\d+(?:\.\d+)?$/.exec(String(s));
  return m ? m[1] : String(s);
}
function settleOf(lines) {
  const ls = (lines || []).map(l => String(l));
  const refused = ls.some(l => /can not install conflicting packages with --noconfirm/i.test(l))
    || (ls.some(l => /unresolvable package conflicts detected/i.test(l))
        && ls.some(l => /^::\s*\S+ and \S+ are in conflict/.test(l.trim())));
  if (!refused) return null;
  const providers = [], conflicts = [];
  let prov = null, section = "";
  for (const raw of ls) {
    const l = raw.replace(/^Enter a number \(default=\d+\):\s*/, "");
    // pacman's question (with "Remove X?" naming the installed one bare) or
    // its echo in the error, once per pair
    let m = /^::\s*(\S+) and (\S+) are in conflict(?:\s*\(([^)]*)\))?\.?(?:\s*Remove (\S+)\?)?/.exec(l.trim());
    if (m) {
      const pkg = stripVersion(m[1]);
      const gone = m[4] || stripVersion(m[2]);
      if (!conflicts.some(c => c.pkg === pkg && c.replaces.indexOf(gone) >= 0))
        conflicts.push({ pkg: pkg, replaces: [gone], inner: false });
      section = "";
      continue;
    }
    m = /^::\s*There are \d+ providers available for (\S+?):?$/.exec(l.trim());
    if (m) { prov = { name: m[1], options: [] }; providers.push(prov); section = "prov"; continue; }
    if (/^::\s*Repository /.test(l.trim()) && section === "prov") continue;
    m = /^::\s*(Inner conflicts|Conflicts) found:?$/i.exec(l.trim());
    if (m) { section = /^inner/i.test(m[1]) ? "inner" : "conflicts"; continue; }
    if (/^::/.test(l.trim()) || /^error:/i.test(l.trim())) { section = ""; continue; }
    if (section === "prov") {
      const opts = [...l.matchAll(/(\d+)\)\s+(\S+)/g)];
      if (opts.length) { for (const o of opts) prov.options.push(o[2]); continue; }
      section = "";
    } else if (section === "conflicts" || section === "inner") {
      m = /^\s+(\S+):\s+(.+)$/.exec(l);
      if (m) {
        conflicts.push({ pkg: m[1], replaces: m[2].trim().split(/\s+/), inner: section === "inner" });
        continue;
      }
      section = "";
    }
  }
  return { providers: providers.filter(p => p.options.length > 1), conflicts: conflicts };
}

// What still needs each package a settle would remove: `pacman -Qi a b`
// prints one block per package; its "Required By" is who breaks (or must be
// satisfied by what replaces it). { name: [requirers] }
function requiredByOf(text) {
  const out = {};
  for (const block of String(text ?? "").split(/\n\s*\n/)) {
    const info = parseInfo(block);
    const n = info.map["Name"];
    if (n) out[n] = listField(info.map["Required By"]);
  }
  return out;
}
function requiredByCommand(names) {
  return "LC_ALL=C pacman -Qi -- " + (names || []).map(q).join(" ") + " 2>/dev/null";
}

// What a transaction is, for its title: an update (-Syu), an install of
// named packages (-S), a removal (-R), or something else (a cache sweep).
function txKindOf(steps) {
  const ss = (steps || []).filter(a => a && a[0] !== "@sudo" && a[0] !== "@user");
  if (ss.some(a => /^-S\w*u/.test(a[0] || "") || /^-S\w*y/.test(a[0] || ""))) return "update";
  if (ss.length && ss.every(a => /^-S/.test(a[0] || ""))) return "install";
  if (ss.length && ss.every(a => /^-R/.test(a[0] || ""))) return "remove";
  if (ss.length) return "update";
  // nothing of paru's: a Flatpak update is still an update, the rest
  // (services restarted, a cache swept) only "other"
  return (steps || []).some(a => a && /\bflatpak\b.*\bupdate\b/.test(a.join(" "))) ? "update" : "other";
}

// A finished job that pacman.log heard nothing of, in its own label's
// words, past tense: "restart a and b" → "Restarted a and b". The label is
// what request() was given; "" when it said nothing (a full upgrade).
const DONE_VERBS = { restart: "Restarted", update: "Updated", install: "Installed",
  remove: "Removed", repair: "Repaired", drop: "Dropped", reinstall: "Reinstalled" };
function doneLine(label) {
  const l = String(label ?? "").trim();
  const m = /^(\w+)\b\s*(.*)$/.exec(l);
  if (!m) return "";
  const v = DONE_VERBS[m[1].toLowerCase()];
  return v ? (v + (m[2] ? " " + m[2] : "")) : "";
}

// The same steps, now answered. `choices` maps a provider menu's name to
// the option taken. Conflicts go through paru's --useask: pacman's --ask
// says yes to replacing a conflicting package — and to nothing else — so
// it is added only once you have agreed to exactly the replacements
// settleOf listed. A provider for one of your own targets takes its place;
// one for a dependency rides along as a target and is marked a dependency
// after (taking the first option needs nothing: paru already does).
function settledSteps(steps, settle, choices) {
  const ch = choices || {};
  const out = [];
  for (const a of steps || []) {
    if (a[0] === "@sudo" || a[0] === "@user" || !/^-S/.test(a[0] || "")) {
      out.push(a);
      continue;
    }
    let args = a.slice();
    const extra = [];
    for (const p of (settle && settle.providers) || []) {
      const pick = ch[p.name];
      if (!pick || p.options.indexOf(pick) < 0) continue;
      const at = args.indexOf(p.name, 1);
      if (at > 0) args[at] = pick;
      else if (pick !== p.options[0]) { args.push(pick); extra.push(pick); }
    }
    if (settle && settle.conflicts.length && args.indexOf("--useask") < 0)
      args = [args[0], "--useask"].concat(args.slice(1));
    out.push(args);
    if (extra.length) out.push(["@sudo", "pacman", "-D", "--asdeps"].concat(extra));
  }
  return out;
}

// ── THE LOG, AS A TERMINAL WOULD HAVE SHOWN IT ────────────────────────────
// A transaction runs under `script`, so pacman believes it has a terminal and
// draws its bars — the download readings a piped pacman never prints. What
// comes back is terminal output: color and cursor escapes, and a bar
// redrawn in place with carriage returns (turned into line breaks before
// they reach here, so a redraw arrives as a new line).

// The escapes and stray control characters out, and the pty's trailing space.
function cleanLine(raw) {
  return String(raw ?? "")
    // a terminal's OSC — Flatpak's progress (9;4) among them — whole: the
    // control characters alone came off and left "]9;4;1;45" in the log
    .replace(/\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)/g, "")
    .replace(/\x1b\[[0-9;?]*[ -\/]*[@-~]/g, "")
    .replace(/\x1b[()][A-Za-z0-9]/g, "")
    .replace(/\x1b[=>78]/g, "")
    // line breaks too: one that slips through arrives glued to the front of
    // the next line (see runProc in Ceres), and a mark behind it goes unread
    .replace(/[\x00-\x1f\x7f]/g, "")
    .replace(/\s+$/, "");
}

// ── FLATPAK'S PROGRESS (user, 2026-10-15: a first install sat behind a sheet
// that seemed to do nothing while its runtimes came down). On a terminal it
// reports the whole job's percentage as the terminal progress sequence,
// OSC 9;4 — read from the RAW line, before cleanLine takes it off — and
// draws "Installing 2/5… ▌ 45%  4.1 MB/s  00:12" lines. → { pct, of, rate,
// eta, phase } (any may be missing), or null for a line that says nothing.
function flatpakProgressOf(raw) {
  const r = String(raw ?? "");
  let pct = -1;
  const osc = r.match(/\x1b\]9;4;[12];(\d{1,3})/g);
  if (osc) pct = parseInt(/(\d{1,3})$/.exec(osc[osc.length - 1])[1], 10);
  const line = cleanLine(r);
  const job = /(Installing|Updating|Uninstalling)(?: (\d+)\/(\d+))?\u2026?/.exec(line);
  if (pct < 0 && job) {
    const p = /(\d{1,3})%/.exec(line);
    if (p) pct = parseInt(p[1], 10);
  }
  if (pct < 0 && !job) return null;
  const rate = /([\d.]+\s?[kKMGT]?i?B)\/s/.exec(line);
  const eta = /\b(\d\d:\d\d(?::\d\d)?)\s*$/.exec(line);
  return {
    pct: pct >= 0 ? Math.min(100, pct) : -1,
    of: job && job[2] ? job[2] + " of " + job[3] : "",
    phase: job ? job[1] + (job[2] ? " " + job[2] + " of " + job[3] : "") : "",
    rate: rate ? rate[1] + "/s" : "", eta: eta ? eta[1] : ""
  };
}

// A pacman bar line, read: what it is about, how far, and — for a download —
// how big, how fast and how long. null for anything that is not a bar.
//
//    linux-6.9-1-x86_64   135.0 MiB  20.5 MiB/s 00:05 [#####-----]  45%
//    Total ( 2/10)        300.0 MiB  25.0 MiB/s 00:10 [##--------]  20%
//   (1/5) upgrading linux                             [##########] 100%
function progressOf(line) {
  const m = /^(.*?)\s*\[[#\-Cco ]*\]\s+(\d{1,3})%$/.exec(String(line ?? "").trim());
  if (!m) return null;
  const pre = m[1].trim();
  const pct = Math.min(100, parseInt(m[2], 10));
  const d = /^(.+?)\s+([\d.]+\s+[KMGT]?i?B)\s+([\d.]+\s+[KMGT]?i?B\/s)\s+(\d+:\d+(?::\d+)?|--:--)$/.exec(pre);
  const label = (d ? d[1] : pre).trim();
  return {
    // the same bar redrawn, whatever its counter says by now
    key: label.replace(/\(\s*\d+\/\d+\)/, "(n)"),
    label: label, pct: pct,
    size: d ? d[2] : "", rate: d ? d[3] : "", eta: d ? d[4] : "",
    download: !!d
  };
}

// HOW FAR THE WHOLE JOB IS, from one bar — 0..1, or null when the bar says
// nothing about the whole. pacman gives it two ways: while downloading, a
// "Total (x/y)" bar measured in bytes across every file; while installing,
// each package's bar carries "(x/y)", so package x at p% is x-1 packages done
// and p% of the next.
function overallOf(p) {
  if (!p) return null;
  const c = /\(\s*(\d+)\/(\d+)\)/.exec(p.label);
  if (/^Total\b/.test(p.label)) return p.pct / 100;
  if (!c) return null;
  const x = parseInt(c[1], 10), y = parseInt(c[2], 10);
  if (!(y > 0)) return null;
  return Math.min(1, Math.max(0, (x - 1 + p.pct / 100) / y));
}

// A new line onto the log. A bar that is already in the last few lines is
// updated where it stands rather than added again — pacman redraws one bar
// per parallel download, so the one to replace is not always the last.
// `redraw` says the line was drawn over the one before it (it followed a
// bare carriage return), and it replaces that line whatever it looks like.
function foldLine(log, line, cap, redraw) {
  const out = (log || []).slice();
  if (redraw && out.length > 0) { out[out.length - 1] = line; return out; }
  const p = progressOf(line);
  if (p) {
    for (let i = out.length - 1; i >= Math.max(0, out.length - 12); --i) {
      const q = progressOf(out[i]);
      if (q && q.key === p.key) { out[i] = line; return out; }
    }
  }
  out.push(line);
  while (out.length > (cap || 400)) out.shift();
  return out;
}

// ── WHY A REMOVAL CANNOT HAPPEN ───────────────────────────────────────────
// pacman's refusals, one per dependency:
//   removing hyprcursor breaks dependency 'libhyprcursor.so=0-64' required by hyprland
// grouped by the package that is in the way, which is the thing you would
// have to act on — "hyprland needs hyprcursor, libhyprcursor.so".
function blockers(reasons) {
  const by = {}, order = [], other = [];
  for (const r of reasons || []) {
    const m = /breaks dependency '([^']+)' required by (\S+)/.exec(String(r));
    if (!m) { if (String(r).trim() !== "") other.push(String(r).trim()); continue; }
    if (!by[m[2]]) { by[m[2]] = []; order.push(m[2]); }
    if (by[m[2]].indexOf(m[1]) < 0) by[m[2]].push(m[1]);
  }
  return { needs: order.map(n => ({ by: n, deps: by[n] })), other: other };
}

// pacman's headline, in words that say what to do about it.
function removeHeadline(err) {
  const e = String(err ?? "");
  if (/could not satisfy dependencies/.test(e)) return "Other packages still need this";
  return e;
}

// ── what it cost ──────────────────────────────────────────────────────────
// `expac -Q '%n %m'` → { name: bytes }. Per package, as ZENU does: a single
// before/after total hides a big install canceling a big removal.
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
  // Flathub's record, its keys unindented so parseInfo reads it as pacman's
  if (repo === "flatpak")
    return "flatpak remote-info --system flathub " + q(name) + " 2>/dev/null | sed 's/^ *//'";
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

// ── history ───────────────────────────────────────────────────────────────
// pacman.log, newest first, as far back as `limit` package events go. The
// "Running" lines come along because they are what turns a list of events
// into TRANSACTIONS: each one is the command that the events after it (in
// the file) belong to.
function historyCommand(limit) {
  return "tac /var/log/pacman.log 2>/dev/null | grep -m " + Math.max(1, limit | 0)
    + " -E '\\[ALPM\\] (installed|upgraded|removed|downgraded|reinstalled) |\\[PACMAN\\] Running '"
    // and Flatpak's, after a mark (user, 2026-10-14): its own journal, and the
    // names of what is installed, so an event says Spotify, not its id
    + "; echo '@@flatpak'; command -v flatpak >/dev/null 2>&1 && "
    + "{ flatpak history --columns=time,change,application,branch,installation 2>/dev/null | tail -n " + Math.max(1, limit | 0) + "; "
    + "echo '@@fpnames'; flatpak list --app --columns=application,name 2>/dev/null; }; true";
}

const STAMP_RE = /^\[(\d{4}-\d\d-\d\d)T(\d\d:\d\d)(?::\d\d)?([+-]\d{4})?\]/;

// → [{ date, time, command, events: [{verb,name,from,to}] }], newest first.
// Read in the order tac gives it: a transaction's events arrive BEFORE the
// line that started it, so they are collected until that line closes them.
function readHistory(text, now) {
  const all = String(text ?? "");
  const cut = all.indexOf("@@flatpak");
  const out = [];
  let pending = [];
  for (const line of (cut < 0 ? all : all.slice(0, cut)).split("\n")) {
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
  if (cut < 0) return out;
  // Flatpak's, among them by time — newest first, as pacman's are
  return out.concat(readFlatpakHistory(all.slice(cut), now))
    .sort((a, b) => (b.date + b.time).localeCompare(a.date + a.time));
}

// ── FLATPAK'S HISTORY ─────────────────────────────────────────────────────
// `flatpak history`: "Oct 14 21:52:25 \t deploy install \t com.spotify.Client
// \t stable \t user". Installs, updates and removals; pulls and remotes are
// not news. Its time has no year — this one, unless that would be ahead of
// today. Events closer than five minutes, in one installation, are one job:
// an app's runtimes come down over minutes before the app itself. Those
// RUNTIMES (a version for a branch: 25.08, 1.4 — an app's is stable, beta or
// master) fold into one line, so the job reads as the app it was for.
const FP_MONTHS = { Jan: 1, Feb: 2, Mar: 3, Apr: 4, May: 5, Jun: 6, Jul: 7, Aug: 8, Sep: 9, Oct: 10, Nov: 11, Dec: 12 };
const FP_VERBS = { "deploy install": "installed", "deploy update": "upgraded", "uninstall": "removed" };
function readFlatpakHistory(text, now) {
  const today = now ? new Date(now) : new Date();
  const names = {};
  const lines = String(text ?? "").split("\n");
  const at = lines.indexOf("@@fpnames");
  if (at >= 0) for (const l of lines.slice(at + 1)) {
    const f = l.split("\t");
    if (f.length >= 2 && f[0]) names[f[0]] = f[1] || f[0];
  }
  const ev = [];
  for (const l of at >= 0 ? lines.slice(0, at) : lines) {
    const f = l.split("\t");
    const verb = FP_VERBS[(f[1] || "").trim()];
    const m = /^(\w{3})\s+(\d+)\s+(\d\d):(\d\d)/.exec(f[0] || "");
    if (!verb || !m || !f[2] || !FP_MONTHS[m[1]]) continue;
    let y = today.getFullYear();
    const mo = FP_MONTHS[m[1]], d = Number(m[2]);
    if (mo > today.getMonth() + 1 || (mo === today.getMonth() + 1 && d > today.getDate())) y--;
    const pad = n => (n < 10 ? "0" : "") + n;
    ev.push({ date: y + "-" + pad(mo) + "-" + pad(d), time: m[3] + ":" + m[4], verb: verb, id: f[2],
              runtime: !/^(stable|beta|master)$/.test((f[3] || "").trim()), scope: (f[4] || "").trim(),
              t: Date.UTC(y, mo - 1, d, Number(m[3]), Number(m[4])) });
  }
  // one job: same installation, under five minutes from the event before
  // — and of one kind: an app removed minutes after another was installed is
  // a job of its own, not part of the install (runtimes go with the job
  // they came in, whatever their verb)
  const jobs = [];
  for (const e of ev) {
    const last = jobs.length ? jobs[jobs.length - 1] : null;
    const kind = e.runtime ? "" : (e.verb === "removed" ? "out" : "in");
    if (last && last.scope === e.scope && e.t - last.end <= 5 * 60000 && (!kind || !last.kind || last.kind === kind)) {
      last.events.push(e);
      last.end = e.t;
      if (kind) last.kind = kind;
    } else jobs.push({ scope: e.scope, end: e.t, kind: kind, events: [e] });
  }
  return jobs.map(j => {
    const apps = j.events.filter(e => !e.runtime);
    const rts = j.events.filter(e => e.runtime);
    const events = apps.map(e => ({ verb: e.verb, name: names[e.id] || e.id, from: "", to: "", flatpak: true, id: e.id }));
    if (rts.length) {
      const v = rts[0].verb;
      const n = new Set(rts.map(e => e.id)).size;
      events.push({ verb: v, name: n + (n === 1 ? " runtime" : " runtimes"), from: "", to: "", flatpak: true, runtime: true });
    }
    const lead = (apps[0] || j.events[0]).verb;
    const first = j.events[0];
    return { date: first.date, time: first.time, flatpak: true, scope: j.scope,
             command: "flatpak " + (lead === "installed" ? "install" : lead === "removed" ? "uninstall" : "update"),
             events: events };
  });
}

// "pacman --sync -y -u --noconfirm --" → "full upgrade", and so on: what a
// transaction WAS, in words, from the command that ran it.
function describeCommand(cmd) {
  const c = String(cmd ?? "");
  if (c === "") return "";
  // Flatpak's jobs: what they did, and that they were Flatpak's
  const fp = /^flatpak (install|uninstall|update)$/.exec(c);
  if (fp) return "Flatpak " + ({ install: "install", uninstall: "removal", update: "update" })[fp[1]];
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
    // Flatpak's, when it is here: its apps and the runtimes they share, both
    // installations, with flatpak's own sizes (user, 2026-10-14)
    + "echo '@@fpapps'; command -v flatpak >/dev/null 2>&1 && flatpak list --app --columns=name,application,size,installation 2>/dev/null\n"
    + "echo '@@fprt'; command -v flatpak >/dev/null 2>&1 && flatpak list --runtime --columns=name,application,size,installation 2>/dev/null\n"
    + "echo '@@fpunused'; " + flatpakUnusedCommand() + "\n"
    + "echo '@@end'";
}

function readMaint(text) {
  const m = { orphans: [], pacnew: [], cacheCount: 0, cacheBytes: 0, stale: 0,
              clones: [], synced: 0, aurList: 0, keep: { n: 0, size: "" }, uninst: { n: 0, size: "" },
              fpApps: [], fpRuntimes: [], fpUnused: [] };
  const unusedLines = [];
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
    else if (sec === "fpunused") unusedLines.push(l);
    else if ((sec === "fpapps" || sec === "fprt") && f.length >= 2)
      (sec === "fpapps" ? m.fpApps : m.fpRuntimes).push({ name: f[0] || f[1], version: f[1],
        right: (f[2] || "").trim() + (f[3] && f[3].trim() === "user" ? " \u00b7 just you" : "") });
  }
  m.clones.sort((a, b) => b.size - a.size);
  m.fpUnused = readFlatpakUnused(unusedLines.join("\n"));
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
//
// A `file` in place of a `bin` is data rather than a program, there or not:
// the Store's app catalog is a directory archlinux-appstream-data fills.
// `store`: only the Store wants it — said in the Store's own tab when it is
// missing, not as Setup in Updates (user, 2026-10-25).
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
  { bin: "notify-send",       pkg: "libnotify",         why: "update toasts" },
  { file: "/usr/share/swcatalog/xml", pkg: "archlinux-appstream-data", store: true,
    why: "the Store: icons, descriptions and screenshots of Arch's apps" },
  { file: "/usr/lib/qt6/plugins/imageformats/kimg_jxl.so", pkg: "kimageformats", store: true,
    why: "the Store's app icons, which Arch ships as JPEG XL" }
];
function depKey(d) { return d.bin || d.file; }

// ONE AUR HELPER: PARU (user, 2026-10-26: "yay is old anyway"). Ceres runs
// the AUR through paru alone; another helper beside it keeps its own cache,
// its own idea of what is out of date and its own -Syu. Found, setup is not
// done until it is gone and paru is in — no discard, and every other job
// waits (Ceres.request). Each with its -bin / -git builds and the -debug
// package makepkg leaves beside them.
const OTHER_HELPERS = ["yay", "pikaur", "trizen", "aura", "pakku", "pacaur", "aurman", "rua"];
const OTHER_HELPERS_RE = "(" + OTHER_HELPERS.join("|") + ")(-bin|-git)?(-debug)?";

// Prints each missing program's name, one per line — and "cargo" when that
// is missing too, since building paru needs it (rust provides it; someone on
// rustup already has it, and must not be handed rust on top).
// And, as "=<package>", whichever package owns the paru on the PATH — paru,
// paru-git, paru-bin — for Settings, which offers to swap it for the other.
// And "flatpak" when there is no flatpak: not a dependency — the Store asks
// whether you want it (see setupSteps' `flatpak`).
// And, as "~<package>", every other AUR helper installed (OTHER_HELPERS).
function depsCommand() {
  return DEPS.map(d => (d.file ? "[ -e " + q(d.file) + " ]" : "command -v " + q(d.bin) + " >/dev/null 2>&1")
    + " || echo " + q(depKey(d))).join("; ")
    + "; command -v cargo >/dev/null 2>&1 || echo cargo"
    + "; command -v flatpak >/dev/null 2>&1 || echo flatpak"
    + "; p=$(command -v paru) && pacman -Qqo \"$p\" 2>/dev/null | sed 's/^/=/'"
    + "; pacman -Qq 2>/dev/null | grep -xE " + q(OTHER_HELPERS_RE) + " | sed 's/^/~/'; true";
}


// → { missing: [{ pkg, aur, store, why: [..] }], paru: bool, cargo: bool, paruPkg,
//     flatpak, others } — flatpak is whether it is HERE, unlike paru and cargo;
// others the other AUR helpers' packages installed (OTHER_HELPERS);
// one row per PACKAGE, however many of its programs are missing; paruPkg is
// the package paru came from, "" when there is none or pacman does not own it.
function readDeps(text) {
  const gone = {}, others = [];
  let paruPkg = "";
  for (const l of String(text ?? "").split("\n")) {
    const t = l.trim();
    if (t.startsWith("=")) paruPkg = t.slice(1);
    else if (t.startsWith("~")) { if (others.indexOf(t.slice(1)) < 0) others.push(t.slice(1)); }
    else if (t) gone[t] = true;
  }
  const byPkg = {}, order = [];
  for (const d of DEPS) {
    if (!gone[depKey(d)]) continue;
    if (!byPkg[d.pkg]) { byPkg[d.pkg] = { pkg: d.pkg, aur: !!d.aur, store: !!d.store, why: [] }; order.push(d.pkg); }
    // a package anything else wants too is not the Store's alone
    if (!d.store) byPkg[d.pkg].store = false;
    byPkg[d.pkg].why.push(d.why);
  }
  return { missing: order.map(p => byPkg[p]), paru: !!gone["paru"], cargo: !!gone["cargo"],
           paruPkg: gone["paru"] ? "" : paruPkg, flatpak: !gone["flatpak"], others: others };
}

// The helpers' own names, for what setup says: "yay", not "yay-bin-debug"
function helperNames(others) {
  const out = [];
  for (const p of others || []) {
    const n = String(p).replace(/(-bin|-git)?(-debug)?$/, "");
    if (out.indexOf(n) < 0) out.push(n);
  }
  return out;
}

// Flathub, as a remote for the whole system — see setupSteps
const FLATHUB_STEP = ["@sudo", "flatpak", "remote-add", "--if-not-exists", "--system",
                      "flathub", "https://dl.flathub.org/repo/flathub.flatpakrepo"];

// ── FLATPAK UPDATES (user, 2026-10-14) ───────────────────────────────────
// Asked of both installations — the system's and yours — with what is
// installed now, so a row reads "name  from → to" as the system's do. The
// mark is the system's answer: yours failing (no remote of your own) is not
// a failed check. No flatpak at all is an empty answer, not an error.
function flatpakUpdatesCommand() {
  return "command -v flatpak >/dev/null 2>&1 || { echo '" + EXIT_MARK + "0'; exit 0; }\n"
    + "s=0\n"
    + "for sc in system user; do\n"
    + "  flatpak list --$sc --app --columns=application,name,version 2>/dev/null | sed \"s/^/I\t$sc\t/\"\n"
    + "  out=$(flatpak remote-ls --$sc --updates --app --columns=application,version 2>/dev/null) "
    + "|| { [ \"$sc\" = system ] && s=1; }\n"
    + "  [ -n \"$out\" ] && printf '%s\\n' \"$out\" | sed \"s/^/U\t$sc\t/\"\n"
    // and the runtimes the apps share, which update on their own and were
    // never counted — a runtime-only update went unseen and unapplied
    + "  rt=$(flatpak remote-ls --$sc --updates --runtime --columns=application 2>/dev/null)\n"
    + "  [ -n \"$rt\" ] && printf '%s\\n' \"$rt\" | sed \"s/^/R\t$sc\t/\"\n"
    + "done\n"
    + "echo '" + EXIT_MARK + "'\"$s\"";
}
// → { ok, list: [{ name, id, from, to, scope, flatpak: true }] }. A new build
// of the same version says so rather than "1.2 → 1.2".
function readFlatpakUpdates(text) {
  const r = splitExit(text);
  const have = {}, list = [];
  for (const l of r.lines) {
    const f = l.split("\t");
    if (f[0] === "I" && f.length >= 4) have[f[1] + " " + f[2]] = { name: f[3] || f[2], version: f[4] || "" };
  }
  for (const l of r.lines) {
    const f = l.split("\t");
    if (f[0] !== "U" || f.length < 3 || !f[2]) continue;
    const h = have[f[1] + " " + f[2]] || { name: f[2], version: "" };
    const to = (f[3] || "").trim();
    list.push({ name: h.name, id: f[2], from: h.version, to: to && to !== h.version ? to : "new build",
                scope: f[1], flatpak: true });
  }
  // the runtimes: one row for each installation's, "3 runtimes"
  const rts = {};
  for (const l of r.lines) {
    const f = l.split("\t");
    if (f[0] === "R" && f.length >= 3 && f[2]) (rts[f[1]] = rts[f[1]] || new Set()).add(f[2]);
  }
  for (const sc of Object.keys(rts)) {
    const n = rts[sc].size;
    list.push({ name: n + (n === 1 ? " runtime" : " runtimes"), id: "", from: "", to: "shared libraries",
                scope: sc, flatpak: true, runtime: true });
  }
  return { ok: r.code === 0, list: list, error: r.code === 0 ? "" : "flatpak check failed" };
}
// Every one: the system's as root, yours without
function flatpakUpdateSteps(list) {
  const steps = [];
  if ((list || []).some(u => u.scope !== "user"))
    steps.push(["@sudo", "flatpak", "update", "--system", "-y"]);
  if ((list || []).some(u => u.scope === "user"))
    steps.push(["@user", "flatpak update --user -y"]);
  return steps;
}
// Just this one — or, for the runtimes row, that installation's all
function flatpakUpdateOne(u) {
  if (u.runtime) return flatpakUpdateSteps([u]);
  if (u.scope === "user") return [["@user", "flatpak update --user -y " + q(u.id)]];
  return [["@sudo", "flatpak", "update", "--system", "-y", u.id]];
}

// ── FLATPAK, LATER OR NOT AT ALL (Settings › Channels; user, 2026-10-14) ──
// Added: flatpak from the repos (no -y: nothing else moves), then Flathub
// for the whole system, as setup would have.
function flatpakAddSteps() {
  return [["@sudo", "pacman", "-S", "--needed", "--noconfirm", "flatpak"], FLATHUB_STEP];
}

// Removed: every Flatpak app and runtime first — the user's own, then the
// system's, each only when there is any (uninstall --all with nothing there
// is an error) — then Flathub's remote, then flatpak itself. What apps kept
// in ~/.var/app is the user's and stays; the sheet says so.
//
// AND NOTHING LEFT BEHIND (user, 2026-10-15: Ceres keeps the system clean).
// After the package: Flatpak's own stores — the system's (/var/lib/flatpak:
// its repository, the catalog, the exports), yours (~/.local/share/flatpak)
// and its cache — and Ceres' own Flathub figures. `deleteData` takes what
// the apps kept too (~/.var/app, Flatpak's alone): asked, ticked by default.
function flatpakRemoveSteps(deleteData) {
  const dd = deleteData ? " --delete-data" : "";
  return [
    ["@user", "if flatpak list --user --columns=ref 2>/dev/null | grep -q .; then "
      + "flatpak uninstall --user --all --noninteractive -y" + dd + "; fi; "
      + "if flatpak list --system --columns=ref 2>/dev/null | grep -q .; then "
      + "sudo -A flatpak uninstall --system --all --noninteractive -y" + dd + "; fi; "
      + "sudo -A flatpak remote-delete --system --force flathub 2>/dev/null; true"],
    ["@sudo", "pacman", "-Rns", "--noconfirm", "flatpak"],
    ["@sudo", "rm", "-rf", "--", "/var/lib/flatpak"],
    ["@user", "rm -rf -- \"${XDG_DATA_HOME:-$HOME/.local/share}/flatpak\" \"${XDG_CACHE_HOME:-$HOME/.cache}/flatpak\" "
      + "\"${XDG_CACHE_HOME:-$HOME/.cache}/ceres/store/flathub-stats.json\""
      + (deleteData ? " \"$HOME/.var/app\"" : "")]
  ];
}

// ── WHAT FLATPAK LEAVES ABOUT, for Maintenance ───────────────────────────
// Runtimes nothing installed needs any more — removed apps leave theirs
// (Spotify's six were found so). `flatpak uninstall --unused` with no
// keyboard lists them and stops at its question.
function flatpakUnusedCommand() {
  return "command -v flatpak >/dev/null 2>&1 || exit 0; for sc in user system; do "
    + "flatpak uninstall --unused --$sc </dev/null 2>/dev/null | sed \"s/^/$sc\t/\"; done; true";
}
// → [{ scope, id, branch }]
function readFlatpakUnused(text) {
  const out = [];
  for (const l of String(text ?? "").split("\n")) {
    const f = l.split("\t").map(x => x.trim());
    if (f.length >= 5 && /^\d+\.$/.test(f[1]) && f[3]) out.push({ scope: f[0], id: f[3], branch: f[4] || "" });
  }
  return out;
}
// Take them out — only from the installations that have any
function flatpakUnusedSteps(unused) {
  const steps = [];
  if ((unused || []).some(u => u.scope === "system"))
    steps.push(["@sudo", "flatpak", "uninstall", "--unused", "--system", "--noninteractive", "-y"]);
  if ((unused || []).some(u => u.scope === "user"))
    steps.push(["@user", "flatpak uninstall --unused --user --noninteractive -y"]);
  return steps;
}
// Repair's dry run, both installations: what it would fix. A clean one
// says only that it verified and checked; anything else is a problem.
function flatpakRepairCommand() {
  return "command -v flatpak >/dev/null 2>&1 || exit 0; for sc in user system; do "
    + "flatpak repair --$sc --dry-run 2>&1 | sed \"s/^/$sc\t/\"; done; true";
}
function readFlatpakRepair(text) {
  const problems = [];
  for (const l of String(text ?? "").split("\n")) {
    const i = l.indexOf("\t");
    if (i < 0) continue;
    const m = cleanLine(l.slice(i + 1)).trim();
    if (m === "" || /^\[\d+\/\d+\] Verifying|^Checking remotes|^Working on the|^Pruning|^Nothing/i.test(m)) continue;
    problems.push({ scope: l.slice(0, i), text: m });
  }
  return { problems: problems };
}

// WITH ITS PROGRESS: installs and updates run without --noninteractive,
// which prints nothing but the ref (watched on a real install, 2026-10-15);
// -y answers what there is to answer, the steps name the remote and the ref
// so there is nothing to choose, and stdin is /dev/null in any case. Its
// terminal progress then reaches flatpakProgressOf. Removals keep it: they
// have no download to show.
//
// ONE FLATPAK APP, in or out. "system" is for everyone and goes through
// sudo; "user" is yours alone and needs no password — Flathub is added for
// you first, since setup added it for the system only.
const FLATHUB_URL = "https://dl.flathub.org/repo/flathub.flatpakrepo";
function flatpakInstallSteps(id, scope) {
  if (scope === "user")
    return [["@user", "flatpak remote-add --user --if-not-exists flathub " + q(FLATHUB_URL)
      + " && flatpak install --user -y flathub " + q(id)]];
  return [["@sudo", "flatpak", "install", "--system", "-y", "flathub", id]];
}
// ...AND WHAT IT LEAVES (user, 2026-10-15): its data in ~/.var/app when
// asked (ticked by default), then any runtime nothing needs any more —
// removing Spotify had left six behind.
function flatpakUninstallSteps(id, scope, deleteData) {
  const dd = deleteData ? " --delete-data" : "";
  if (scope === "user")
    return [["@user", "flatpak uninstall --user --noninteractive -y" + dd + " " + q(id)
      + " && flatpak uninstall --unused --user --noninteractive -y"]];
  return [["@sudo", "flatpak", "uninstall", "--system", "--noninteractive", "-y"].concat(deleteData ? ["--delete-data"] : []).concat([id]),
          ["@sudo", "flatpak", "uninstall", "--unused", "--system", "--noninteractive", "-y"]];
}

// `flatpak list --app --columns=name,application,installation` → rows
function parseFlatpaks(text) {
  const out = [];
  for (const l of String(text ?? "").split("\n")) {
    const f = l.split("\t");
    if (f.length < 2 || !f[1]) continue;
    out.push({ name: f[0] || f[1], id: f[1], scope: (f[2] || "system").trim() });
  }
  return out;
}

// The steps that install what is missing, and take out any other AUR helper
// (deps.others). `paru` is "paru", "paru-git" or ""
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
//
// `flatpak` true: Flatpak comes in the same pacman call, and Flathub is added
// as a system remote — the one place the Store's Flatpak apps come from. The
// remote is added even when flatpak was already here; --if-not-exists makes
// that a no-op for someone who added it themselves.
function setupSteps(deps, paru, buildDir, script, flatpak) {
  const repo = (deps.missing || []).filter(m => !m.aur).map(m => m.pkg);
  if (flatpak && !deps.flatpak) repo.push("flatpak");
  const steps = [];
  if (paru) {
    for (const p of ["base-devel", "git"]) if (repo.indexOf(p) < 0) repo.push(p);
    if (deps.cargo) repo.push("rust");
  }
  const others = deps.others || [];
  if (repo.length === 0 && !paru && !flatpak && others.length === 0) return steps;
  if (repo.length || paru) steps.push(["@sudo", "pacman", "-Syu", "--needed", "--noconfirm"].concat(repo));
  if (flatpak) steps.push(FLATHUB_STEP);
  // the other helper out, then paru in (user, 2026-10-26: "remove yay then
  // install" paru). -Rs takes what it alone pulled in; a package that needs
  // the helper stops the removal, and the job, with pacman's own words. A
  // paru build that then fails leaves setup to do again, paru still missing.
  if (others.length) steps.push(["@sudo", "pacman", "-Rs", "--noconfirm"].concat(others));
  if (paru) steps.push(paruBuildStep(paru, buildDir));
  if (script) steps.push(["@user", q(script) + " aur"]);
  return steps;
}

// Building `paru` ("paru" or "paru-git") from its AUR recipe, as you, and
// installing the result with pacman. `--ask 4` answers pacman's one question
// here, "remove the conflicting package?", with yes: swapping paru for
// paru-git (or back, or for paru-bin) is exactly that conflict, and is
// done in the same transaction rather than removing paru first and hoping
// the install goes through. The build comes first under `set -e`, so a
// failed build leaves the paru you had.
function paruBuildStep(paru, buildDir) {
  const d = q(buildDir);
  return ["@user",
    "set -e; rm -rf " + d + "; mkdir -p " + d + "; cd " + d + "; "
    + "echo ':: Fetching the " + paru + " recipe from the AUR'; "
    + "git clone --depth 1 " + q("https://aur.archlinux.org/" + paru + ".git") + " recipe; cd recipe; "
    + "echo ':: Building " + paru + "'; "
    + "makepkg --noconfirm --needed -f; "
    + "pkgs=$(ls *.pkg.tar.* | grep -v -- '-debug-' | grep -v '\\.sig$'); "
    + "echo ':: Installing ' $pkgs; "
    + "sudo -A pacman -U --noconfirm --ask 4 $pkgs; "
    + "cd /; rm -rf " + d];
}

// SWAPPING THE PARU THAT IS THERE (Settings). Its build needs what setup put
// in for it — base-devel, git, a Rust toolchain — which may have been
// removed since; asked for with --needed and no -y, so nothing is synced or
// upgraded on the way, and what is already in is skipped.
function paruSwitchSteps(paru, deps, buildDir) {
  const need = ["base-devel", "git"].concat(deps && deps.cargo ? ["rust"] : []);
  return [["@sudo", "pacman", "-S", "--needed", "--noconfirm"].concat(need),
          paruBuildStep(paru, buildDir)];
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
// THIS SESSION, NOT EVERY ONE OF YOURS (user, 2026-10-26: "I keep seeing
// this message even after a re-login"). Logging in again on another TTY left
// the first desktop running on its own, and its Hyprland, Xwayland and the
// rest held the old LLVM — named as if this desktop had to restart them,
// which no restart here would clear. Left out: processes of your OTHER login
// sessions (logind's, class user*, another TTY or an ssh login). Everything
// else still counts — this session, user services and the user manager (its
// own "manager" session), scopes it started. Asked from no session logind
// knows of, nothing is left out.
//
// One line per affected process: pid, name, the systemd unit it runs in if it
// is a user service (its cgroup's last component, when that is a .service),
// and up to three replaced files, comma-joined.
function staleCommand() {
  return "s=$(cat /proc/self/sessionid 2>/dev/null); "
    + "o=$(loginctl list-sessions --no-legend 2>/dev/null | awk -v s=\"$s\" -v u=\"$(id -u)\" "
    + "'$2 == u && $6 ~ /^user/ { if ($1 == s) me = 1; else o = o \" \" $1 } END { if (me) print o }'); "
    + "for p in /proc/[0-9]*; do [ -O \"$p\" ] || continue; "
    + "if [ -n \"$o\" ]; then read -r q 2>/dev/null < \"$p/sessionid\" || q=; case \"$o \" in *\" $q \"*) continue;; esac; fi; "
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

// A STALE SERVICE IS RESTARTED, NOT LOGGED OUT OF (user, 2026-10-15: "I
// re-logged and still see it"). User services belong to systemd's user
// manager, which lives as long as ANY session of yours does — leaving the
// desktop for the tty it was started from, and back, never ends it, and the
// service runs on with its old code. Restarting the unit is what renews it:
// yours, so no password.
//
// A unit whose file went with its package (removing Flatpak takes
// flatpak-session-helper.service with it) still runs, but systemd can no
// longer start it: restart says "Unit … not found". Its LoadState is then
// not-found, and stopping it is all that is left to do — judged by whether
// it still runs: systemd drops a fileless unit the moment it stops, and its
// stop then reports "not loaded" for a stop that worked.
function restartServicesSteps(units) {
  const u = (units || []).filter(x => /\.service$/.test(x));
  if (!u.length) return [];
  return [["@user", "r=0; for u in " + u.map(q).join(" ") + "; do "
    + "if [ \"$(systemctl --user show -p LoadState --value \"$u\")\" = not-found ]; "
    + "then systemctl --user stop \"$u\" 2>/dev/null; ! systemctl --user is-active -q \"$u\" || r=1; else systemctl --user restart \"$u\" || r=1; fi; done; exit $r"]];
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
// The copies come from pacman's cache, then paru's build directories (which keep
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
// The pings are held in a mktemp file, not a name built from the pid in a
// shared /tmp that anything could have made first.
function rankCommand(candidates, keep) {
  return "t=$(mktemp) || exit 1; "
    + "printf '%s\\n' " + (candidates || []).map(q).join(" ")
    + " | xargs -P 48 -I{} curl -o /dev/null -s -w 'ping %{time_total} %{http_code} {}\\n'"
    + " --connect-timeout 2 --max-time 4 '{}lastupdate' > \"$t\"; "
    + "cat \"$t\"; "
    + "awk '$3 == 200 { print $2, $4 }' \"$t\" | sort -n | head -" + (keep | 0)
    + " | while read -r t2 u; do curl -o /dev/null -s -w \"rate %{speed_download} %{http_code} $u\\n\""
    + " --connect-timeout 3 --max-time 8 \"${u}core/os/x86_64/core.files\"; done; "
    + "rm -f \"$t\"";
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

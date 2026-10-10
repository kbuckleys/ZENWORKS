// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

// The multi-select mark: a bolt, U+F140B. Past the BMP, so it is written as
// the surrogate pair a JS string literal needs rather than as the codepoint.
const BALLOT = "\uDB85\uDC0B";

function formatMemKb(kb) {
  const v = parseInt(kb, 10);
  if (isNaN(v)) return kb;
  if (v >= 1048576) return (v / 1048576).toFixed(1) + "G";
  return Math.round(v / 1024) + "M";
}

// ── ONE SAMPLE OF EVERY PROCESS ─────────────────────────────────────────
// ps for the columns, and the kernel's own tick counters beside it for the
// CPU. ps's %cpu is NOT what this list is for: it is the process's whole
// lifetime averaged — cpu time over time since it started — so a daemon that
// burned an hour at boot sits at the top of the list all day, and a process
// that has been idle for a week and just started spinning barely registers.
// What the question "what is using my CPU" means is NOW, and now is the
// difference between two samples of utime+stime. So every sample carries the
// ticks, and the uptime they were read at, and the next sample subtracts.
//
// awk reads /proc/<pid>/stat whole: the command name is in parentheses and
// may itself contain spaces or parentheses, so the fields are counted from
// after the LAST ") " — utime and stime are the 12th and 13th after it. A
// process that exits between the glob and the read is a warning on stderr
// and nothing else.
const PROC_CMD =
  "read up _ < /proc/uptime; echo \"@ $up $(getconf CLK_TCK)\"\n"
  + "awk '{ i = length($0); while (i > 0 && substr($0, i, 1) != \")\") i--;"
  + " split(substr($0, i + 2), f, \" \"); print \"t\", $1, f[12] + f[13] }'"
  + " /proc/[0-9]*/stat 2>/dev/null\n"
  + "ps -eo pid=,ppid=,user=,stat=,nlwp=,ni=,rss=,vsz=,etimes=,pcpu=,args=";

// The sample PROC_CMD prints: the uptime and tick rate it was read at, every
// pid's ticks, and the rows. memKb keeps the raw rss the formatted `mem`
// throws away — sorting by memory on "512M" vs "1.4G" would order them as
// strings and lie. `cpu` starts as ps's lifetime figure and is replaced by
// liveCpu() as soon as there is a previous sample to subtract.
function parseProcSample(text) {
  const out = { up: 0, hz: 100, ticks: ({}), rows: [] };
  for (const line of String(text).split("\n")) {
    if (line.charAt(0) === "@") {
      const f = line.split(/\s+/);
      out.up = parseFloat(f[1]) || 0;
      out.hz = parseInt(f[2], 10) || 100;
      continue;
    }
    if (line.charAt(0) === "t" && line.charAt(1) === " ") {
      const f = line.split(" ");
      out.ticks[f[1]] = parseInt(f[2], 10) || 0;
      continue;
    }
    const m = line.match(
      /^\s*(\d+)\s+(\d+)\s+(\S+)\s+(\S+)\s+(\d+)\s+(\S+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\S+)\s+(.*)$/);
    if (!m || m[11] === "") continue;
    out.rows.push({ pid: m[1], ppid: m[2], user: m[3], stat: m[4],
                    threads: parseInt(m[5], 10) || 0, nice: m[6],
                    memKb: parseInt(m[7], 10) || 0, mem: formatMemKb(m[7]),
                    vszKb: parseInt(m[8], 10) || 0,
                    etimes: parseInt(m[9], 10) || 0,
                    cpu: m[10], args: m[11] });
  }
  return out;
}

// The CPU each process used between `prev` and `cur`, as a percentage of one
// core the way top and ps both count it — a busy four-thread process reads
// 400. A pid `prev` has not seen (it is new, or its number was reused) keeps
// ps's figure, which for something that just started IS recent.
// Returns whether the numbers are live, so the view can say when they are not.
function liveCpu(cur, prev) {
  if (!prev || !(cur.up > prev.up)) return false;
  const span = (cur.up - prev.up) * cur.hz;
  for (const r of cur.rows) {
    const now = cur.ticks[r.pid], was = prev.ticks[r.pid];
    if (now === undefined || was === undefined || now < was) continue;
    r.cpu = (100 * (now - was) / span).toFixed(1);
  }
  return true;
}

// Backwards-compatible: the old single-command shape, which the tests and
// anything else reading `ps -eo pid=,user=,pcpu=,rss=,args=` still use.
function parseProcesses(text) {
  const rows = [];
  for (const line of String(text).split("\n")) {
    const m = line.match(/^\s*(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(.*)$/);
    if (m && m[1] && m[5] !== "") {
      rows.push({ pid: m[1], user: m[2], cpu: m[3], mem: formatMemKb(m[4]),
                  memKb: parseInt(m[4], 10) || 0, args: m[5] });
    }
  }
  return rows;
}

// The command's own name, for sorting by it. `args` is the whole command
// line, so this is the basename of argv[0] — and kernel threads arrive
// already bracketed, which is a name too, just not a path.
function procName(args) {
  const head = String(args).trim().split(/\s+/)[0] || "";
  if (head.charAt(0) === "[") return head.replace(/^\[|\]$/g, "");
  const cut = head.lastIndexOf("/");
  return cut >= 0 ? head.slice(cut + 1) : head;
}

// Filter first, then order: the sort only has to touch what survived, and the
// two are separate questions you change independently. (Same reasoning, and
// the same shape, as picasso.js sortRows.)
//
// Every comparison falls back to pid, so rows that tie hold still across the
// 2.5s refresh instead of swapping places under the cursor.
function sortRows(rows, key, desc) {
  const dir = desc ? -1 : 1;
  const byPid = (a, b) => (parseInt(a.pid, 10) || 0) - (parseInt(b.pid, 10) || 0);
  const num = (pick) => (a, b) => {
    const d = pick(a) - pick(b);
    return d !== 0 ? d * dir : byPid(a, b);
  };
  const str = (pick) => (a, b) => {
    const x = pick(a).toLowerCase(), y = pick(b).toLowerCase();
    if (x === y) return byPid(a, b);
    return (x < y ? -1 : 1) * dir;
  };
  const cmp = {
    cpu:  num((r) => parseFloat(r.cpu) || 0),
    mem:  num((r) => r.memKb || 0),
    threads: num((r) => r.threads || 0),
    pid:  num((r) => parseInt(r.pid, 10) || 0),
    user: str((r) => String(r.user)),
    name: str((r) => procName(r.args))
  }[key];
  // slice(): sort is in place, and `rows` is the unfiltered list the caller
  // still owns
  return cmp ? rows.slice().sort(cmp) : rows;
}

// ── THE TREE ────────────────────────────────────────────────────────────
// The rows again, each parent followed by its children, siblings in the order
// the list is sorted by. A row whose parent is not in `rows` — pid 1, kthreadd,
// or anything whose parent the filter hid — is a root of its own, so a
// filtered tree still shows every match rather than only the ones whose whole
// ancestry happened to match too.
//
// Each row comes back as a copy carrying `depth`, `tree` (the guide lines to
// draw in front of the command) and `kids` (how many descendants it has).
// `folded` is a set of pids whose descendants are left out; a folded row says
// how many with `hidden`.
function buildTree(rows, key, desc, folded) {
  const byPid = ({});
  for (const r of rows) byPid[r.pid] = r;
  const kids = ({});
  const roots = [];
  for (const r of rows) {
    if (r.ppid !== undefined && r.ppid !== r.pid && byPid[r.ppid]) {
      (kids[r.ppid] = kids[r.ppid] || []).push(r);
    } else {
      roots.push(r);
    }
  }
  const count = ({});
  const descendants = (pid) => {
    if (count[pid] !== undefined) return count[pid];
    let n = 0;
    for (const k of kids[pid] || []) n += 1 + descendants(k.pid);
    return (count[pid] = n);
  };
  const out = [];
  const walk = (list, depth, guides) => {
    const sorted = sortRows(list, key, desc);
    for (let i = 0; i < sorted.length; ++i) {
      const r = sorted[i];
      const last = i === sorted.length - 1;
      const n = descendants(r.pid);
      const isFolded = !!(folded && folded[r.pid]) && n > 0;
      out.push(Object.assign({}, r, {
        depth: depth,
        tree: depth === 0 ? "" : guides + (last ? "\u2514\u2500 " : "\u251C\u2500 "),
        kids: n,
        folded: isFolded,
        hidden: isFolded ? n : 0
      }));
      if (!isFolded && kids[r.pid])
        walk(kids[r.pid], depth + 1,
          depth === 0 ? "" : guides + (last ? "   " : "\u2502  "));
    }
  };
  walk(roots, 0, "");
  return out;
}

// The row that is this one's parent in `list`, by index, or -1.
function parentIndex(list, i) {
  const r = list[i];
  if (!r) return -1;
  for (let j = i - 1; j >= 0; --j) if (list[j].pid === r.ppid) return j;
  return -1;
}

// ── WHAT A PROCESS IS DOING ──────────────────────────────────────────────
// ps's STAT is a letter and some flags; the letter is the state.
function stateName(stat) {
  return ({ R: "running", S: "sleeping", D: "disk wait", Z: "zombie",
            T: "stopped", t: "traced", I: "idle", X: "dead", W: "paging" })
    [String(stat).charAt(0)] ?? String(stat);
}

// "3d 4h", "2h 05m", "12m 30s", "45s" — two units, the two that matter.
function formatDuration(secs) {
  let s = Math.max(0, Math.floor(Number(secs) || 0));
  const d = Math.floor(s / 86400); s -= d * 86400;
  const h = Math.floor(s / 3600); s -= h * 3600;
  const m = Math.floor(s / 60); s -= m * 60;
  const two = (n) => (n < 10 ? "0" : "") + n;
  if (d > 0) return d + "d " + h + "h";
  if (h > 0) return h + "h " + two(m) + "m";
  if (m > 0) return m + "m " + two(s) + "s";
  return s + "s";
}

// A byte count at the width the list's own RAM column uses.
function formatBytes(n) {
  const v = Math.max(0, Number(n) || 0);
  if (v >= 1073741824) return (v / 1073741824).toFixed(1) + "G";
  if (v >= 1048576) return (v / 1048576).toFixed(1) + "M";
  if (v >= 1024) return (v / 1024).toFixed(1) + "K";
  return v + "B";
}

// One process, read closer than ps reads it. /proc/<pid>/io is only readable
// for your own processes (and not even all of those, under some ptrace
// policies), so its absence is ordinary and comes back as null.
function detailCmd(pid) {
  const p = "/proc/" + String(parseInt(pid, 10) || 0);
  return "cat " + p + "/status 2>/dev/null; echo '##'; "
    + "cat " + p + "/io 2>/dev/null; echo '##'; "
    + "readlink " + p + "/cwd 2>/dev/null; echo '##'; "
    + "tr '\\0' ' ' < " + p + "/cmdline 2>/dev/null; echo; echo '##'; "
    + "ps -o lstart= -p " + String(parseInt(pid, 10) || 0) + " 2>/dev/null";
}

function parseDetail(text) {
  const parts = String(text).split(/^##$/m);
  const kv = (block) => {
    const o = ({});
    for (const l of String(block ?? "").split("\n")) {
      const m = l.match(/^([\w()]+):\s*(.*)$/);
      if (m) o[m[1]] = m[2].trim();
    }
    return o;
  };
  const status = kv(parts[0]);
  const ioRaw = kv(parts[1]);
  const kbOf = (v) => parseInt(String(v ?? ""), 10);
  const io = ioRaw.read_bytes !== undefined
    ? { read: Number(ioRaw.read_bytes) || 0, write: Number(ioRaw.write_bytes) || 0 }
    : null;
  return {
    found: status.Pid !== undefined,
    name: status.Name ?? "",
    swapKb: kbOf(status.VmSwap),
    peakKb: kbOf(status.VmHWM),
    ctx: (parseInt(status.voluntary_ctxt_switches, 10) || 0)
       + (parseInt(status.nonvoluntary_ctxt_switches, 10) || 0),
    io: io,
    cwd: String(parts[2] ?? "").trim(),
    cmdline: String(parts[3] ?? "").trim(),
    started: String(parts[4] ?? "").trim().replace(/\s+/g, " ")
  };
}

// ── SIGNALS AND PRIORITY ────────────────────────────────────────────────
// The signals worth a key, in the order the card offers them: the polite one
// first because it is the one you almost always mean.
const SIGNALS = [
  { sig: "TERM", say: "ask to quit" },
  { sig: "KILL", say: "force quit" },
  { sig: "INT",  say: "interrupt" },
  { sig: "HUP",  say: "hang up · reload" },
  { sig: "STOP", say: "pause" },
  { sig: "CONT", say: "resume" },
  { sig: "USR1", say: "user 1" },
  { sig: "USR2", say: "user 2" }
];

// One line per pid that could not be reached, as "FAIL <pid>", and nothing
// for the ones that could — the same contract the plain kill always had, so
// one reader handles all of them.
function signalScript(pids, sig) {
  const s = SIGNALS.some((x) => x.sig === sig) ? sig : "TERM";
  return "for p in " + pids.map((p) => String(parseInt(p, 10) || 0)).join(" ")
    + "; do kill -s " + s + " \"$p\" 2>/dev/null || echo \"FAIL $p\"; done";
}

function clampNice(n) {
  return Math.max(-20, Math.min(19, Math.round(Number(n) || 0)));
}

function niceScript(pids, n) {
  return "for p in " + pids.map((p) => String(parseInt(p, 10) || 0)).join(" ")
    + "; do renice -n " + clampNice(n) + " -p \"$p\" >/dev/null 2>&1 || echo \"FAIL $p\"; done";
}

// fixed-width data columns; monospace font keeps them aligned
function display(r) {
  return r.pid.padStart(6) + " " + r.user.padEnd(9) +
    (r.cpu + "%").padStart(6) + " " +
    r.mem.padStart(5) + "  " + r.args;
}

function filterRows(rows, query) {
  const q = String(query).toLowerCase();
  if (!q) return rows;
  return rows.filter((r) => display(r).toLowerCase().indexOf(q) >= 0);
}

// Matches render bold #eebebe (rasi: highlight bold #eebebe)
function highlight(text, query) {
  text = String(text);
  if (!query) return Strings.escapeHtml(text);
  const lower = text.toLowerCase();
  const ql = String(query).toLowerCase();
  let out = "", pos = 0, i;
  while ((i = lower.indexOf(ql, pos)) >= 0) {
    out += Strings.escapeHtml(text.slice(pos, i));
    out += "<b><span style=\"color:#eebebe;\">" +
      Strings.escapeHtml(text.substr(i, ql.length)) + "</span></b>";
    pos = i + ql.length;
  }
  return out + Strings.escapeHtml(text.slice(pos));
}

// uptime -p → strip the leading "up "
function uptimeClean(text) {
  return String(text).replace(/^up\s+/, "").replace(/\s+$/, "");
}

// ── bandwhich ─────────────────────────────────────────────────────────────
// `bandwhich --raw` prints the same three tables its TUI draws, one row per
// line, a block a second, forever. All three are read: the view is meant to be
// what bandwhich shows, not a chosen slice of it.
//
//   Refreshing:
//   process: <1788161614> "claude" up/down Bps: 16/16 connections: 1
//   connection: <1788161614> <enp7s0>:39504 => 160.79.104.10:443 (tcp) up/down Bps: 16/16 process: "claude"
//   remote_address: <1788161614> 160.79.104.10 up/down Bps: 16/16 connections: 1
//
// These came off a real capture. An earlier pass reconstructed them from the
// binary's format strings and got the field ORDER wrong in all three — the
// <angle brackets> hold a unix timestamp, not the pid, the address or the
// connection, and every row carries one. Worth stating, because the strings
// are still in the binary in the misleading order and the next reader will
// find them too.
//
// `Bps` is bytes per second as a plain integer — raw mode does not humanise,
// which is exactly what a sort wants.
//
// The three are normalised on the way in, because they are the same four
// columns wearing different names: a thing, what it is bound to, and its two
// rates. One row shape means one delegate and one sort.
const NET_RE = {
  // process: <ts> "name" up/down Bps: u/d connections: n
  process: /^process: <\d+> "(.*)" up\/down Bps: (\d+)\/(\d+) connections: (\d+)\s*$/,
  // remote_address: <ts> addr up/down Bps: u/d connections: n
  remote: /^remote_address: <\d+> (.+?) up\/down Bps: (\d+)\/(\d+) connections: (\d+)\s*$/,
  // connection: <ts> <iface>:port => remote:port (proto) up/down Bps: u/d process: "name"
  connection: /^connection: <\d+> <(.+?)>:(\d+) => (.+) \((\w+)\) up\/down Bps: (\d+)\/(\d+)(?: process: "(.*)")?\s*$/
};

// bandwhich's own frame marker — it prints this before every block, so there
// is no need to guess where one ends from the timing of the lines.
function isNetFrame(line) {
  return /^Refreshing:/.test(String(line).trim());
}

function parseNetLine(line) {
  const t = String(line).trim();
  if (t === "") return null;
  let m;

  if ((m = NET_RE.process.exec(t))) {
    return { table: "process", name: m[1] || "?", detail: m[4] + " conn",
             up: parseInt(m[2], 10) || 0, down: parseInt(m[3], 10) || 0 };
  }
  if ((m = NET_RE.remote.exec(t))) {
    return { table: "remote", name: m[1], detail: m[4] + " conn",
             up: parseInt(m[2], 10) || 0, down: parseInt(m[3], 10) || 0 };
  }
  if ((m = NET_RE.connection.exec(t))) {
    return { table: "connection", name: m[3],
             detail: (m[7] || "?") + " · " + m[4] + " · " + m[1],
             up: parseInt(m[5], 10) || 0, down: parseInt(m[6], 10) || 0 };
  }
  return null;
}

// A line bandwhich clearly meant as a row that no pattern above matched — the
// one thing worth saying out loud, because it means a format changed under us
// and the table would otherwise just look short for no stated reason.
function isNetRow(line) {
  return /^(process|remote_address|connection): /.test(String(line).trim());
}

// Bytes per second, at the width the meters' own tooltips use.
function formatBps(n) {
  const v = Number(n) || 0;
  if (v >= 1048576) return (v / 1048576).toFixed(1) + "M";
  if (v >= 1024) return (v / 1024).toFixed(1) + "K";
  return v + "B";
}

// What a row reads as, for the filter to match against. The same job display()
// does for a process row, over the columns this table has.
function displayNet(r) {
  return r.name + " " + r.detail;
}

function filterNet(rows, query) {
  const q = String(query).toLowerCase();
  if (!q) return rows;
  return rows.filter((r) => displayNet(r).toLowerCase().indexOf(q) >= 0);
}

// Sorted like the kill list, over this table's columns. The tiebreak is the
// name rather than a pid: these rows have no pid to fall back on, and two of
// the three tables are not about processes at all.
function sortNet(rows, key, desc) {
  const dir = desc ? -1 : 1;
  const tie = (a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0);
  const num = (pick) => (a, b) => {
    const d = pick(a) - pick(b);
    return d !== 0 ? d * dir : tie(a, b);
  };
  const str = (pick) => (a, b) => {
    const x = pick(a).toLowerCase(), y = pick(b).toLowerCase();
    if (x === y) return tie(a, b);
    return (x < y ? -1 : 1) * dir;
  };
  const cmp = {
    name:   str((r) => String(r.name)),
    detail: str((r) => String(r.detail)),
    up:     num((r) => r.up),
    down:   num((r) => r.down)
  }[key];
  return cmp ? rows.slice().sort(cmp) : rows;
}

// The one line worth showing out of a multi-line complaint. bandwhich's is a
// bare "Error:", a blank, the interface names, then the sentence that actually
// says what went wrong, then a bulleted workaround — and a strip one line tall
// can show exactly one of those.
function firstProblem(text) {
  const lines = String(text).split("\n")
    .map((l) => l.trim())
    .filter((l) => l !== "" && l !== "Error:" && l[0] !== "*" && !/:$/.test(l));
  const joined = lines.join(" ");
  const stop = joined.indexOf(". ");
  const one = stop > 0 ? joined.slice(0, stop + 1) : joined;
  return one.length > 140 ? one.slice(0, 137) + "…" : one;
}

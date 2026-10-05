// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ZEUS' PROCESS LIST: the sample it takes, the CPU it works out from two of
// them, the tree it builds, what it reads about one process, and the scripts
// it hands to sh to signal or renice.

"use strict";

// Two samples a second apart, in PROC_CMD's own shape. pid 30 is new in the
// second; pid 20's command line has spaces and a parenthesis in it.
const A = [
  "@ 1000.00 100",
  "t 1 500", "t 2 10", "t 10 2000", "t 20 100",
  "    1     0 root     Ss     1   0 15504 21148  1000  0.5 /sbin/init",
  "    2     0 root     S      1   0     0     0  1000  0.0 [kthreadd]",
  "   10     1 buck     Sl    12   0 204800 900000  900  2.2 /usr/bin/app --flag",
  "   20    10 buck     R      1   5  1024  4096   10 10.0 sh -c echo (hi) there"
].join("\n");
const B = [
  "@ 1001.00 100",
  "t 1 500", "t 2 10", "t 10 2150", "t 20 200", "t 30 5",
  "    1     0 root     Ss     1   0 15504 21148  1001  0.5 /sbin/init",
  "    2     0 root     S      1   0     0     0  1001  0.0 [kthreadd]",
  "   10     1 buck     Sl    12   0 204800 900000  901  2.2 /usr/bin/app --flag",
  "   20    10 buck     R      1   5  1024  4096   11 10.0 sh -c echo (hi) there",
  "   30     2 root     I      1 -20     0     0    0  3.0 [kworker/0:1]"
].join("\n");

module.exports = {
  module: "zeus/zeus.js",
  cases: (Z, t) => {
    // ── the sample
    const a = Z.parseProcSample(A);
    t.eq("the uptime is read", a.up, 1000);
    t.eq("and the tick rate", a.hz, 100);
    t.eq("every row is read", a.rows.length, 4);
    t.eq("ticks by pid", a.ticks["10"], 2000);
    const r20 = a.rows.find((r) => r.pid === "20");
    t.eq("a command with spaces survives whole", r20.args, "sh -c echo (hi) there");
    t.eq("the parent", r20.ppid, "10");
    t.eq("threads are a number", a.rows.find((r) => r.pid === "10").threads, 12);
    t.eq("rss is kept raw for sorting", a.rows.find((r) => r.pid === "10").memKb, 204800);
    t.eq("and formatted for reading", a.rows.find((r) => r.pid === "10").mem, "200M");
    t.eq("before a second sample the cpu is ps's", r20.cpu, "10.0");

    // ── live cpu
    t.eq("no previous sample is not live", Z.liveCpu(Z.parseProcSample(B), null), false);
    const b = Z.parseProcSample(B);
    t.eq("two samples are", Z.liveCpu(b, a), true);
    t.eq("150 ticks in a second is 150% of a core",
      b.rows.find((r) => r.pid === "10").cpu, "150.0");
    t.eq("100 ticks in a second is one core", b.rows.find((r) => r.pid === "20").cpu, "100.0");
    t.eq("an idle process reads zero, whatever its lifetime says",
      b.rows.find((r) => r.pid === "1").cpu, "0.0");
    t.eq("a new process keeps ps's figure", b.rows.find((r) => r.pid === "30").cpu, "3.0");
    const back = Z.parseProcSample(A);
    t.eq("a sample older than the last is not subtracted", Z.liveCpu(back, b), false);

    // ── the tree
    const tree = Z.buildTree(b.rows, "pid", false, {});
    t.eq("parents come before children",
      tree.map((r) => r.pid), ["1", "10", "20", "2", "30"]);
    t.eq("roots have no guides", tree[0].tree, "");
    t.eq("a last child gets a corner", tree[1].tree, "└─ ");
    t.eq("its child is indented past it", tree[2].tree, "   └─ ");
    t.eq("depth", tree[2].depth, 2);
    t.eq("descendants are counted", tree[0].kids, 2);
    const two = Z.buildTree(b.rows.concat([Object.assign({}, b.rows[3], { pid: "21" })]),
      "pid", false, {});
    t.eq("a child with a sibling below it gets a tee",
      two.find((r) => r.pid === "20").tree, "   ├─ ");
    const folded = Z.buildTree(b.rows, "pid", false, { "2": true });
    t.eq("a folded parent hides its children", folded.some((r) => r.pid === "30"), false);
    t.eq("and says how many", folded.find((r) => r.pid === "2").hidden, 1);
    t.eq("folding a leaf does nothing",
      Z.buildTree(b.rows, "pid", false, { "20": true }).find((r) => r.pid === "20").folded, false);
    const orphan = Z.buildTree(b.rows.filter((r) => r.pid !== "10"), "pid", false, {});
    t.eq("a row whose parent was filtered out is a root of its own",
      orphan.find((r) => r.pid === "20").depth, 0);
    const bycpu = Z.buildTree(b.rows, "cpu", true, {});
    t.eq("siblings follow the sort", bycpu[0].pid, "1");
    t.eq("the parent of a row, by index", Z.parentIndex(tree, 2), 1);
    t.eq("a root has none", Z.parentIndex(tree, 0), -1);

    // ── sorting by threads
    t.eq("threads sort", Z.sortRows(b.rows, "threads", true)[0].pid, "10");

    // ── one process
    t.eq("state letters", Z.stateName("Sl"), "sleeping");
    t.eq("zombies", Z.stateName("Z+"), "zombie");
    t.eq("seconds", Z.formatDuration(45), "45s");
    t.eq("minutes", Z.formatDuration(750), "12m 30s");
    t.eq("hours", Z.formatDuration(7500), "2h 05m");
    t.eq("days", Z.formatDuration(3 * 86400 + 4 * 3600), "3d 4h");
    t.eq("bytes", Z.formatBytes(1536), "1.5K");
    t.eq("gigabytes", Z.formatBytes(3 * 1073741824), "3.0G");
    t.has("the detail reads status", Z.detailCmd("42"), "/proc/42/status");
    t.has("a pid is a number and nothing else", Z.detailCmd("42; rm -rf ~"), "/proc/42/");
    const d = Z.parseDetail([
      "Name:\tapp", "Pid:\t10", "VmHWM:\t  300000 kB", "VmSwap:\t     512 kB",
      "voluntary_ctxt_switches:\t10", "nonvoluntary_ctxt_switches:\t5",
      "##", "rchar: 1", "read_bytes: 4096", "write_bytes: 8192",
      "##", "/home/buck", "##", "/usr/bin/app --flag ", "##", "Sat Oct  3 09:12:44 2026"
    ].join("\n"));
    t.eq("found", d.found, true);
    t.eq("peak rss", d.peakKb, 300000);
    t.eq("swap", d.swapKb, 512);
    t.eq("context switches add up", d.ctx, 15);
    t.eq("io", d.io, { read: 4096, write: 8192 });
    t.eq("cwd", d.cwd, "/home/buck");
    t.eq("the command line", d.cmdline, "/usr/bin/app --flag");
    t.eq("the start, with its padding folded", d.started, "Sat Oct 3 09:12:44 2026");
    const noio = Z.parseDetail("Name:\tx\nPid:\t1\n##\n##\n##\n##\n");
    t.eq("an unreadable io file is null, not zeros", noio.io, null);
    t.eq("a process that is gone is not found", Z.parseDetail("##\n##\n##\n##\n").found, false);

    // ── signals and priority
    t.eq("TERM comes first", Z.SIGNALS[0].sig, "TERM");
    t.has("the chosen signal is sent", Z.signalScript(["10", "20"], "KILL"), "kill -s KILL");
    t.has("to every pid", Z.signalScript(["10", "20"], "KILL"), "for p in 10 20;");
    t.has("an unknown signal falls back to TERM", Z.signalScript(["10"], "RM -RF"), "kill -s TERM");
    t.has("pids are numbers and nothing else", Z.signalScript(["10; reboot"], "TERM"), "for p in 10;");
    t.has("failures are reported per pid", Z.signalScript(["10"], "TERM"), 'echo "FAIL $p"');
    t.has("renice", Z.niceScript(["10"], 5), "renice -n 5 -p");
    t.eq("nice is clamped low", Z.clampNice(-99), -20);
    t.eq("and high", Z.clampNice(40), 19);
    t.has("a clamped value is what is run", Z.niceScript(["10"], 99), "renice -n 19");
  }
};

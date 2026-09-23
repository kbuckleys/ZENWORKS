// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The pure half of ceres: reading what checkupdates and paru said, and
// deciding when to ask again.
//
// The failure cases are the point. waybar-updates read a failed check as an
// empty one and put "System is up to date" on the bar while offline; every
// way a check can fail is pinned here as a failure, and every way it can
// succeed with nothing to say is pinned as a success.

"use strict";

const { execFileSync } = require("child_process");

module.exports = {
  module: "ceres/ceres.js",
  cases: (C, t) => {
    // ── the exit mark ─────────────────────────────────────────────────────
    t.eq("mark read and removed", C.splitExit("a\nb\n@@exit 2\n"),
      { lines: ["a", "b", ""], code: 2 });
    t.eq("no mark is no status", C.splitExit("a\nb\n").code, -1);
    t.eq("a mark mid-stream is not the status", C.splitExit("@@exit 0\nlater\n").code, -1);
    t.eq("a mark glued to unterminated output", C.splitExit("</rss>@@exit 0"), { lines: ["</rss>"], code: 0 });

    // ── official repos ────────────────────────────────────────────────────
    const cu = "npm 12.0.2-1 -> 12.1.0-1\nffmpeg 2:9.0.1-4 -> 2:9.0.2-1\n@@exit 0\n";
    const r = C.readRepo(cu);
    t.ok("updates are a success", r.ok);
    t.eq("sorted by name, epoch kept", r.list.map(u => u.name + "=" + u.to),
      ["ffmpeg=2:9.0.2-1", "npm=12.1.0-1"]);
    t.eq("exit 2 is up to date", C.readRepo("@@exit 2\n"), { ok: true, list: [] });
    const off = C.readRepo("==> ERROR: Cannot fetch updates\n@@exit 1\n");
    t.ok("exit 1 is a FAILURE, not an empty list", !off.ok);
    t.eq("and says why", off.error, "Cannot fetch updates");
    t.ok("a killed check is a failure", !C.readRepo("npm 1-1 -> 2-1\n").ok);
    t.eq("a missing checkupdates names the package",
      C.readRepo("sh: line 1: checkupdates: command not found\n@@exit 127\n").error,
      "pacman-contrib is not installed");

    // ── AUR ───────────────────────────────────────────────────────────────
    t.eq("paru: 1 with silence is up to date", C.readAur("@@exit 1\n"), { ok: true, list: [] });
    const net = "error: error sending request for url (https://aur.archlinux.org/rpc): "
      + "error trying to connect: tcp connect error: Network is unreachable (os error 101)\n@@exit 1\n";
    const a = C.readAur(net);
    t.ok("paru: 1 with an error is a failure", !a.ok);
    t.eq("network errors read as offline", a.error, "offline");
    const au = C.readAur(":: spotify: ignoring package upgrade (1-1 => 2-1)\n"
      + "quickshell-git 0.3.1-1 -> 0.3.2-1\n@@exit 0\n");
    t.eq("notes are not updates", au.list.map(u => u.name), ["quickshell-git"]);
    t.eq("a trailing tag is tolerated",
      C.parseUpdates(["foo 1-1 -> 2-1 [ignored]"]).map(u => u.to), ["2-1"]);
    t.eq("duplicates count once", C.parseUpdates(["a 1 -> 2", "a 1 -> 2"]).length, 1);

    // ── the offline AUR recheck, run by a real shell ──────────────────────
    // Against pacman's own database, with a package that is certainly
    // installed and a target version certainly newer, plus one that is not
    // installed at all and so is not an update to anything.
    const cmd = C.aurRecheckCommand([
      { name: "pacman", to: "99:1-1" },
      { name: "no such package here", to: "2-1" }
    ]);
    let out = "";
    try { out = execFileSync("/bin/sh", ["-c", cmd], { encoding: "utf8" }); }
    catch (e) { out = "threw " + e.message; }
    const rr = C.readAur(out);
    t.eq("recheck keeps what is still older", rr.list.map(u => u.name), ["pacman"]);
    t.eq("and reads a clean exit", C.splitExit(out).code, 0);
    t.has("names are quoted", cmd, "'no such package here'");

    // ── telling ───────────────────────────────────────────────────────────
    const list = [{ name: "a", from: "1", to: "2" }, { name: "b", from: "1", to: "2" }];
    t.eq("all new at first", C.arrivals(list, []).length, 2);
    t.eq("told once is told", C.arrivals(list, ["a 2", "b 2"]).length, 0);
    t.eq("a newer version is news again",
      C.arrivals([{ name: "a", from: "2", to: "3" }], ["a 2"]).length, 1);
    t.eq("installing some forgets only those",
      C.stillTold([list[1]], ["a 2", "b 2"]), ["b 2"]);

    // ── when ──────────────────────────────────────────────────────────────
    t.eq("backoff 5", C.retryMins(1, 60), 5);
    t.eq("backoff 10", C.retryMins(2, 60), 10);
    t.eq("backoff 40", C.retryMins(4, 60), 40);
    t.eq("never past the interval", C.retryMins(9, 60), 60);
    const H = 3600000, M = 60000;
    t.ok("never checked is due", C.due(1000, 0, 0, 0, 60));
    t.ok("fresh is not due", !C.due(10 * M, 10 * M, 10 * M, 0, 60));
    t.ok("an hour on is due", C.due(10 * M + H, 10 * M, 10 * M, 0, 60));
    t.ok("slept through it is due", C.due(10 * H, 10 * M, 10 * M, 0, 60));
    t.ok("a failure retries in 5, not 60", C.due(6 * M, 0, 1, 1, 60) && !C.due(4 * M, 0, 1, 1, 60));
    t.eq("age", C.age(3 * H + 5 * M), "3h ago");

    // ── the transaction wrapper, end to end ───────────────────────────────
    // Real sh, real fifo, real askpass — only sudo and paru are stand-ins,
    // so nothing here can touch the real sudo or count against faillock.
    // The stand-in sudo does what sudo does with -A: runs the askpass, and on
    // a wrong answer runs it once more before giving up. The stand-in paru
    // proves it was exec'd (its pid is the one sudo validated under) and
    // echoes its arguments.
    const fs = require("fs"), os = require("os"), path = require("path");
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "ceres test "));
    const bin = path.join(dir, "bin");
    fs.mkdirSync(bin);
    // The stand-in sudo: `-A -v` validates through the askpass exactly as
    // sudo does, asking once more on a wrong answer; any other `-A cmd` needs
    // the askpass to answer "right" again — which is what proves the password
    // is served after validation. Every askpass call is counted.
    fs.writeFileSync(path.join(bin, "sudo"),
      "#!/bin/sh\n"
      + "echo x >> \"$CERES_FIFO.calls\"\n"
      + "[ \"$1\" = -A ] || exit 3\n"
      + "p=$(\"$SUDO_ASKPASS\")\n"
      + "if [ \"$p\" != right ]; then\n"
      + "  echo x >> \"$CERES_FIFO.calls\"; p=$(\"$SUDO_ASKPASS\") || exit 1\n"
      + "  [ \"$p\" = right ] || exit 1\n"
      + "fi\n"
      + "[ \"$2\" = -v ] && exit 0\n"
      + "shift; \"$@\"\n", { mode: 0o755 });
    fs.writeFileSync(path.join(bin, "paru"),
      "#!/bin/sh\n"
      + "echo ':: Synchronizing package databases...'\n"
      + "sudo -A true && sudo -A true && echo served-twice\n"
      + "echo \"args: $*\"\n"
      + "read x && echo \"stdin was not closed\"\n"
      + "exit 0\n", { mode: 0o755 });
    const fifo = path.join(dir, "ask fifo");
    const askpass = path.join(__dirname, "..", "ceres-askpass.sh");
    const run = (pw, steps) => {
      try { fs.rmSync(fifo + ".calls", { force: true }); } catch (e) {}
      try {
        return execFileSync("/bin/sh", ["-c", C.runCommand(fifo, askpass, steps)],
          { encoding: "utf8", input: pw + "\n", timeout: 20000,
            env: Object.assign({}, process.env, { PATH: bin + ":" + process.env.PATH }) });
      } catch (e) { return e.stdout ? String(e.stdout) : "threw " + e.message; }
    };
    const calls = () => { try { return fs.readFileSync(fifo + ".calls", "utf8").length / 2; } catch (e) { return 0; } };
    const good = run("right", C.upgradeSteps());
    t.eq("right password: exit 0", C.splitExit(good).code, 0);
    t.has("authed before paru", good, "@@authed");
    t.has("sudo inside paru is answered, again and again", good, "served-twice");
    t.has("full upgrade, no prompts", good, "args: -Syu --noconfirm --sudoloop --sudoflags=-A --skipreview");
    t.ok("paru's stdin is closed", good.indexOf("stdin was not closed") === -1);
    t.ok("fifo removed after", !fs.existsSync(fifo) && !fs.existsSync(fifo + ".spent") && !fs.existsSync(fifo + ".once"));
    const bad = run("wrong", C.upgradeSteps());
    t.eq("wrong password: auth failure code", C.splitExit(bad).code, C.AUTH_FAILED);
    t.ok("and paru never ran", bad.indexOf("args:") === -1);
    // sudo asked twice (the second is its retry); the second must be
    // refused by the askpass, not answered with the same wrong password
    t.eq("a wrong password is offered once, never retried", calls(), 2);
    const two = run("right", C.changeSteps(["a b"], ["c"]));
    t.has("install step", two, "args: -S --needed a b --noconfirm");
    t.has("then remove step", two, "args: -Rs c --noconfirm --sudoloop --sudoflags=-A");
    t.ok("no review flag on a removal", two.indexOf("-Rs c --noconfirm --sudoloop --sudoflags=-A --skipreview") === -1);
    t.before("install before remove", two, "args: -S", "args: -Rs");
    const rootStep = run("right", [["@sudo", "echo", "root step ran"], ["-S", "x"]]);
    t.has("a root step runs under the served password", rootStep, "root step ran");
    t.before("steps in order", rootStep, "root step ran", "args: -S x");
    t.eq("terminal command", C.terminalCommand(C.changeSteps(["a"], ["b"])),
      "'paru' '-S' '--needed' 'a' && 'paru' '-Rs' 'b'");
    fs.rmSync(dir, { recursive: true, force: true });

    // ── reading it ────────────────────────────────────────────────────────
    t.eq("upgrade event", C.readEvent("[2026-09-23T06:23:30+0300] [ALPM] upgraded npm (12.0.2-1 -> 12.1.0-1)"),
      { verb: "upgraded", name: "npm", from: "12.0.2-1", to: "12.1.0-1" });
    t.eq("install event", C.readEvent("[x] [ALPM] installed unrar (1:7.3.1-1)"),
      { verb: "installed", name: "unrar", from: "", to: "1:7.3.1-1" });
    t.eq("not an event", C.readEvent("[x] [ALPM] transaction completed"), null);
    t.eq("hooks are not events", C.readEvent("[x] [ALPM] running '35-systemd-update.hook'..."), null);
    t.eq("tally", C.tally([C.readEvent("[x] [ALPM] removed a (1-1)")]).removed.length, 1);
    t.eq("phase: sync", C.phaseOf(":: Synchronizing package databases..."), "Syncing databases");
    t.eq("phase: hooks", C.phaseOf(":: Running post-transaction hooks..."), "Running hooks");
    t.eq("phase: nothing", C.phaseOf("(1/3) upgrading npm"), "");
    t.eq("failure: the last error",
      C.failureOf(["error: failed to commit transaction (conflicting files)",
                   "error: unresolvable package conflicts detected"]),
      "unresolvable package conflicts detected");
    const before = C.parseSizes("a 100\nb 50\n"), after = C.parseSizes("a 150\nc 10\n");
    t.eq("disk both sides", C.diskDelta(before, after), { added: 60, removed: 50 });
    t.eq("disk line", C.diskLine({ added: 1572864, removed: 0 }), "+1.5M");
    t.eq("nothing moved", C.diskLine({ added: 0, removed: 0 }), "");

    // ── the package list ──────────────────────────────────────────────────
    const rows = C.parseRows("explicit\tfirefox\t250000000\textra\t140.0-1\n"
      + "avail\tqs\t0\taur\t\nbroken line\n");
    t.eq("rows parsed, junk skipped", rows.map(r => r.name), ["firefox", "qs"]);
    t.ok("installed and aur flags", rows[0].installed && !rows[0].aur && rows[1].aur && !rows[1].installed);
    t.has("search command quotes the query", C.searchCommand("/s/ceres.sh", false, "a'b"), "'a'\\''b'");
    t.has("installed-only mode", C.searchCommand("/s", true, ""), " search installed ");
    const info = C.parseInfo("Name            : less\nDepends On      : glibc  ncurses\n"
      + "Description     : A terminal pager\n    that wraps\nRequired By     : None\n");
    t.eq("info fields kept in order", info.fields.map(f => f[0]), ["Name", "Depends On", "Description", "Required By"]);
    t.eq("continuation joined", info.map["Description"], "A terminal pager that wraps");
    t.eq("list field", C.listField(info.map["Depends On"]), ["glibc", "ncurses"]);
    t.eq("None is empty", C.listField(info.map["Required By"]), []);

    // ── plans ─────────────────────────────────────────────────────────────
    const plan = C.readPlan("@@install\ngimp\t3.0.4-1\textra\nbabl\t0.1.1-1\textra\n@@status 0\n"
      + "@@sync\ngimp\t20000000\t100000000\nbabl\t1000\t5000\nbabl\t999\t999\n"
      + "@@local\nbabl\t4000\n"
      + "@@remove\n7zip\t26.03-1\n@@status 0\n@@freed\n7zip\t6783359\n@@end\n");
    t.eq("install list", plan.install.map(p => p.name), ["gimp", "babl"]);
    t.eq("download summed, first repo wins", plan.download, 20001000);
    t.eq("installed size summed", plan.add, 100005000);
    t.eq("what it replaces", plan.replace, 4000);
    t.eq("remove list and freed", [plan.remove[0].name, plan.free], ["7zip", 6783359]);
    const blocked = C.readPlan("@@install\n@@remove\nerror: failed to prepare transaction (could not satisfy dependencies)\n"
      + ":: removing glibc breaks dependency 'glibc' required by 7zip\n@@status 1\n@@freed\n@@end\n");
    t.eq("blocked removal says why", blocked.blocked, ["removing glibc breaks dependency 'glibc' required by 7zip"]);
    t.has("and the error", blocked.removeError, "could not satisfy dependencies");
    t.eq("unknown target", C.readPlan("@@install\nerror: target not found: nope\n@@status 1\n@@sync\n@@local\n@@remove\n@@end\n").installError,
      "target not found: nope");
    t.eq("signed", [C.signed(1572864), C.signed(-1024)], ["+1.5M", "−1.0K"]);

    // ── review ────────────────────────────────────────────────────────────
    const rv = C.readReview("--- built\n+++ aur\n@@ -1,2 +1,2 @@\n-pkgver=1\n+pkgver=2\n arch=(x86_64)\n");
    t.eq("diff kinds", rv.lines.map(l => l.ink), ["hunk", "hunk", "hunk", "del", "add", ""]);
    t.eq("unchanged", C.readReview("@@same\n").kind, "same");
    t.eq("never built", C.readReview("@@new\npkgname=x\n").lines.map(l => l.text), ["pkgname=x"]);
    t.eq("not in the AUR", C.readReview("@@none\n").kind, "none");
    t.has("name quoted", C.reviewCommand("a b"), "'a b'");
    t.eq("label", C.changeLabel(["a", "b"], ["c"]), "install 2 · remove 1");

    // ── history ───────────────────────────────────────────────────────────
    const hist = C.readHistory([
      "[2026-09-23T12:51:50+0300] [ALPM] upgraded aom (3.15.0-1 -> 3.15.1-1)",
      "[2026-09-23T12:51:50+0300] [ALPM] upgraded firefox (156.0-1 -> 156.0.1-1)",
      "[2026-09-23T12:51:49+0300] [PACMAN] Running 'pacman --sync -y -u --noconfirm --'",
      "[2026-09-23T07:12:51+0300] [ALPM] removed sl (5.05-6)",
      "[2026-09-23T07:12:51+0300] [PACMAN] Running 'pacman --remove -s --noconfirm -- sl'",
      "[2026-09-23T07:00:00+0300] [PACMAN] Running 'pacman --sync -y --'",
      "[2026-09-22T01:00:00+0300] [ALPM] installed orphan (1-1)"
    ].join("\n"));
    t.eq("grouped by transaction, newest first", hist.map(h => h.events.length), [2, 1, 1]);
    t.eq("a transaction's command", C.describeCommand(hist[0].command), "full upgrade");
    t.eq("removal", C.describeCommand(hist[1].command), "remove");
    t.eq("a sync with no events is not a transaction", hist.length, 3);
    t.eq("events past the window keep their date", hist[2].date, "2026-09-22");
    t.eq("time kept", hist[0].time, "12:51");
    const cached = C.readCached("gst-plugins-bad", "gst-plugins-bad-1.28.7-1-x86_64.pkg.tar.zst\n"
      + "gst-plugins-bad-libs-1.28.7-1-x86_64.pkg.tar.zst\nless-1:710-1-x86_64.pkg.tar.zst\n");
    t.eq("cache: exactly this package", cached.map(c => c.version), ["1.28.7-1"]);
    t.eq("cache: epochs kept", C.readCached("less", "less-1:710-1-x86_64.pkg.tar.zst").map(c => c.version), ["1:710-1"]);
    t.has("cache listing sorts by version", C.cachedCommand("x"), "sort -V");

    // ── maintenance ───────────────────────────────────────────────────────
    const mt = C.readMaint("@@orphans\npython-build\t1.2-1\t1000\n@@pacnew\n/etc/pacman.conf.pacnew\n"
      + "@@cache\n502\t2000000000\n@@stale\n24\n@@clones\nsmall\t10\t1\nbig\t999\t0\n@@synced\n1790000000\n@@end\n");
    t.eq("orphans read as installed rows", [mt.orphans[0].name, mt.orphans[0].installed], ["python-build", true]);
    t.eq("pacnew listed", mt.pacnew, ["/etc/pacman.conf.pacnew"]);
    t.eq("cache counted", [mt.cacheCount, mt.cacheBytes, mt.stale], [502, 2000000000, 24]);
    t.eq("clones biggest first, installed flag", mt.clones.map(c => c.name + ":" + c.installed), ["big:false", "small:true"]);
    t.eq("synced in ms", mt.synced, 1790000000000);
    t.eq("dry run read", C.readPrune("==> finished dry run: 90 candidates (disk space saved: 431.55 MiB)"),
      { n: 90, size: "431.55 MiB" });
    t.eq("a real run read the same way", C.readPrune("==> finished: 1 packages removed (disk space saved: 2.00 MiB)").n, 1);
    t.eq("nothing to prune", C.readPrune("==> no candidate packages found for pruning"), { n: 0, size: "" });
    t.eq("maint carries both", C.readMaint("@@keep\n==> finished dry run: 3 candidates (disk space saved: 1.00 MiB)\n@@uninst\n==> no candidate packages found for pruning\n@@end\n").keep.n, 3);
    t.eq("summary: the tool's own last word",
      C.summaryLine(["@@authed", "==> Privilege escalation required", "==> finished: 5 packages removed (disk space saved: 9 MiB)"]),
      "finished: 5 packages removed (disk space saved: 9 MiB)");
    t.eq("summary: nothing said", C.summaryLine(["x"]), "");
    t.has("pacnew diff is live file vs pacnew", C.pacnewDiffCommand("/etc/a b.conf.pacnew"), "'/etc/a b.conf' '/etc/a b.conf.pacnew'");

    // ── root steps ────────────────────────────────────────────────────────
    t.eq("a root step runs under sudo -A", C.stepCommand(["@sudo", "paccache", "-rk2"]), "'sudo' '-A' 'paccache' '-rk2'");
    t.eq("and in a terminal under sudo", C.terminalCommand([["@sudo", "paccache", "-rk2"]]), "'sudo' 'paccache' '-rk2'");

    // ── news ──────────────────────────────────────────────────────────────
    t.eq("rfc822 with offset", C.rfc822("Tue, 22 Sep 2026 09:09:27 +0000"), Date.UTC(2026, 8, 22, 9, 9, 27));
    t.eq("rfc822 east of utc", C.rfc822("Tue, 22 Sep 2026 12:09:27 +0300"), Date.UTC(2026, 8, 22, 9, 9, 27));
    t.eq("log stamp", C.logStamp("[2026-09-23T13:12:18+0300] [PACMAN] starting full system upgrade"),
      Date.UTC(2026, 8, 23, 10, 12, 18));
    const feed = C.readNews("<rss><channel><item><title>Mkinitcpio &gt;=42 needs you</title>"
      + "<link>https://archlinux.org/news/a/</link><description>&lt;p&gt;Re-enroll &lt;code&gt;TPM2&lt;/code&gt; &amp;amp; go.&lt;/p&gt;</description>"
      + "<pubDate>Tue, 22 Sep 2026 09:09:27 +0000</pubDate></item>"
      + "<item><title>Old</title><link>https://archlinux.org/news/b/</link><description></description>"
      + "<pubDate>Mon, 01 Jan 2024 00:00:00 +0000</pubDate></item></channel></rss>\n@@exit 0\n");
    t.eq("items read", feed.items.map(i => i.title), ["Mkinitcpio >=42 needs you", "Old"]);
    t.eq("markup stripped, entities once", feed.items[0].text, "Re-enroll TPM2 &amp; go.");
    t.eq("unread: newer than the last upgrade", C.unreadNews(feed.items, Date.UTC(2026, 0, 1), []).map(i => i.title),
      ["Mkinitcpio >=42 needs you"]);
    t.eq("unread: not once dismissed", C.unreadNews(feed.items, 0, ["https://archlinux.org/news/a/"]).map(i => i.title), ["Old"]);
    t.ok("offline feed is a failure", !C.readNews("curl: (6) Could not resolve host\n@@exit 6\n").ok);
    t.ok("-Syu is an upgrade", C.isUpgrade(C.upgradeSteps()));
    t.ok("-Sy with names is an upgrade", C.isUpgrade([["-Sy", "--needed", "a"]]));
    t.ok("an install is not", !C.isUpgrade(C.changeSteps(["a"], ["b"])));

    // ── what ceres stands on ──────────────────────────────────────────────
    const deps = C.readDeps("paru\ncheckupdates\npaccache\nfzf\ncargo\n");
    t.eq("one row per package", deps.missing.map(m => m.pkg), ["paru", "pacman-contrib", "fzf"]);
    t.eq("with every reason", deps.missing[1].why.length, 2);
    t.ok("paru and cargo flagged", deps.paru && deps.cargo);
    t.eq("nothing missing", C.readDeps("").missing.length, 0);
    t.has("deps command asks for each", C.depsCommand(), "command -v 'inotifywait'");
    const st = C.setupSteps(deps, "paru-git", "/home/test/.cache/ceres/build");
    t.eq("repo packages first, with the build tools and rust",
      st[0], ["@sudo", "pacman", "-Syu", "--needed", "--noconfirm", "pacman-contrib", "fzf", "base-devel", "git", "rust"]);
    t.eq("then the build, as you", st[1][0], "@user");
    t.has("from the chosen AUR recipe", st[1][1], "https://aur.archlinux.org/paru-git.git");
    t.ok("no rust for a rustup user", C.setupSteps(C.readDeps("paru\n"), "paru", "/b")[0].indexOf("rust") < 0);
    t.eq("paru present: repo packages only", C.setupSteps(C.readDeps("fzf\n"), "", "/b").length, 1);
    const withList = C.setupSteps(C.readDeps("fzf\n"), "", "/b", "/s/ceres.sh");
    t.eq("and the AUR list refreshed last", withList[withList.length - 1], ["@user", "'/s/ceres.sh' aur"]);
    t.eq("nothing missing, nothing to do", C.setupSteps(C.readDeps(""), "", "/b").length, 0);
    t.eq("a missing paru is said as such", C.readAur("sh: paru: command not found\n@@exit 127\n").error, "paru is not installed");

    // the bootstrap, end to end through the real wrapper: stand-in git,
    // makepkg, pacman and sudo record what they were asked
    {
      const d2 = fs.mkdtempSync(path.join(os.tmpdir(), "ceres boot "));
      const b2 = path.join(d2, "bin");
      fs.mkdirSync(b2);
      const w = (n, body) => fs.writeFileSync(path.join(b2, n), "#!/bin/sh\n" + body, { mode: 0o755 });
      w("sudo", "[ \"$1\" = -A ] || exit 3\np=$(\"$SUDO_ASKPASS\")\n[ \"$p\" = right ] || exit 1\n"
        + "[ \"$2\" = -v ] && exit 0\nshift; exec \"$@\"\n");
      w("pacman", "echo \"pacman: $*\"\n");
      w("git", "mkdir -p \"$5\"\n");
      w("makepkg", "touch paru-2.1.0-2-x86_64.pkg.tar.zst paru-debug-2.1.0-2-x86_64.pkg.tar.zst "
        + "paru-2.1.0-2-x86_64.pkg.tar.zst.sig\necho '==> Making package: paru'\n");
      const build = path.join(d2, "build dir");
      const out2 = (() => {
        try {
          return execFileSync("/bin/sh", ["-c", C.runCommand(path.join(d2, "fifo"), askpass,
            C.setupSteps(C.readDeps("paru\nfzf\n"), "paru", build))],
            { encoding: "utf8", input: "right\n", timeout: 20000,
              env: Object.assign({}, process.env, { PATH: b2 + ":" + process.env.PATH }) });
        } catch (e) { return e.stdout ? String(e.stdout) : "threw " + e.message; }
      })();
      t.eq("bootstrap: exit 0", C.splitExit(out2).code, 0);
      t.has("bootstrap: a full upgrade with the deps", out2, "pacman: -Syu --needed --noconfirm fzf base-devel git");
      t.has("bootstrap: built", out2, "==> Making package: paru");
      t.has("bootstrap: installs only the package, as root",
        out2, "pacman: -U --noconfirm paru-2.1.0-2-x86_64.pkg.tar.zst\n");
      t.ok("bootstrap: build tree removed", !fs.existsSync(build));
      fs.rmSync(d2, { recursive: true, force: true });
    }

    // ── sorting and filtering ─────────────────────────────────────────────
    const srt = [{ name: "zsh", repo: "extra", size: 3 }, { name: "yay", repo: "aur", size: 0 },
                 { name: "base", repo: "core", size: 9 }, { name: "gimp", repo: "extra", size: 5 }];
    t.eq("no key keeps search order", C.sortRows(srt, "", false).map(r => r.name), ["zsh", "yay", "base", "gimp"]);
    t.eq("by name", C.sortRows(srt, "name", false).map(r => r.name), ["base", "gimp", "yay", "zsh"]);
    t.eq("by repo, pacman's order, then name", C.sortRows(srt, "repo", false).map(r => r.name), ["base", "gimp", "zsh", "yay"]);
    t.eq("by size, descending", C.sortRows(srt, "size", true).map(r => r.name), ["base", "gimp", "zsh", "yay"]);
    t.eq("the input is not reordered", srt[0].name, "zsh");
    t.ok("every word matches", C.matchesAll("gst-plugins-bad", "gst bad"));
    t.ok("in any order", C.matchesAll("gst-plugins-bad", "bad gst"));
    t.ok("a missing word does not", !C.matchesAll("gst-plugins-good", "gst bad"));
    t.ok("an empty filter matches all", C.matchesAll("x", "  "));

    // ── programs running replaced code ────────────────────────────────────
    const stl = C.readStale("589\twireplumber\twireplumber.service\t/usr/lib/libaom.so.3,/usr/lib/libexpat.so.1,\n"
      + "101\tfirefox\t\t/usr/lib/libnss3.so,\n102\tfirefox\t\t/usr/lib/libnss3.so,/usr/lib/libxul.so,\n"
      + "garbage\n");
    t.eq("apps first, grouped by name", stl.map(g => g.name), ["firefox", "wireplumber"]);
    t.eq("every process of an app", stl[0].pids, [101, 102]);
    t.eq("files merged, once each", stl[0].files, ["/usr/lib/libnss3.so", "/usr/lib/libxul.so"]);
    t.ok("a user unit is a service", stl[1].service && stl[1].unit === "wireplumber.service");
    t.eq("names in a line", C.nameList(["a", "b", "c", "d"], 2), "a, b and 2 more");
    t.eq("few names in full", C.nameList(["a", "b"], 3), "a, b");
    {
      const live = require("child_process").execFileSync("/bin/sh", ["-c", C.staleCommand()], { encoding: "utf8" });
      t.ok("the scan runs and every line reads", C.readStale(live).every(g => g.name && g.pids.length > 0));
    }

    // ── the archive ───────────────────────────────────────────────────────
    t.eq("archive folder", C.archiveDir("less"), "https://archive.archlinux.org/packages/l/less/");
    const arc = C.readArchive("less", "less-1%3A563-1-x86_64.pkg.tar.zst\nless-1%3A563-1-x86_64.pkg.tar.zst.sig\n"
      + "lesspipe-2.0-1-any.pkg.tar.zst\n");
    t.eq("archive: versions decoded, sigs and neighbours out", arc.map(a => a.version), ["1:563-1"]);
    t.eq("archive: the url re-encoded", arc[0].url,
      "https://archive.archlinux.org/packages/l/less/less-1%3A563-1-x86_64.pkg.tar.zst");
    t.has("archive listing sorts by version", C.archiveCommand("x"), "sort -V");

    // ── vercmp, against pacman's own ──────────────────────────────────────
    {
      const pairs = [["1:710-1", "580-1"], ["156.0.1-1", "99.0.1-1"], ["1.0a-1", "1.0-1"], ["1.0-2", "1.0-10"],
                     ["2.0.0-1", "2.0-1"], ["1.0rc1-1", "1.0-1"], ["20240903-1", "20240903-2"], ["0.12.0-1", "0.13.0-1"],
                     ["1:1.0-1", "2:0.1-1"], ["1.2.3", "1.2.3"], ["6.30.0-1", "6.30.0-2"], ["3.15.0-1", "3.15.1-1"]];
      for (const [a, b] of pairs) {
        const real = Number(require("child_process").execFileSync("vercmp", [a, b], { encoding: "utf8" }).trim());
        t.eq("vercmp " + a + " vs " + b, Math.sign(C.vercmp(a, b)), Math.sign(real));
      }
      t.eq("byVersion orders epochs last", C.byVersion([{ version: "1:710-1" }, { version: "580-1" }, { version: "590-1" }]).map(x => x.version),
        ["580-1", "590-1", "1:710-1"]);
    }

    // ── AUR health ────────────────────────────────────────────────────────
    const ah = C.readAurHealth("@@names\nfine\nstale\nlonely\nvanished\n@@json\n"
      + JSON.stringify({ resultcount: 3, results: [
          { Name: "fine", Maintainer: "a", OutOfDate: null },
          { Name: "stale", Maintainer: "b", OutOfDate: 1790000000 },
          { Name: "lonely", Maintainer: null, OutOfDate: null }] }) + "\n@@exit 0\n");
    t.eq("health: all checked", ah.checked, 4);
    t.eq("health: only the problems", ah.problems.map(p => p.name), ["stale", "lonely", "vanished"]);
    t.eq("health: flagged when", ah.problems[0].flagged, 1790000000000);
    t.ok("health: orphaned", ah.problems[1].orphaned);
    t.ok("health: gone", ah.problems[2].gone);
    t.ok("health: offline is not 'all fine'", !C.readAurHealth("@@names\nx\n@@json\n\n@@exit 6\n").ok);
    t.has("debug splits are not asked about", C.aurHealthCommand(), "-debug$");

    // ── needed by, and files ──────────────────────────────────────────────
    const ex = C.readExtras("@@rdeps\nman-db\nbase\n@@files\n/usr/bin/less\n/usr/share/man/man1/less.1.gz\n@@end\n");
    t.eq("needed by, sorted", ex.rdeps, ["base", "man-db"]);
    t.eq("files", ex.files.length, 2);
    {
      const live = C.readExtras(require("child_process").execFileSync("/bin/sh", ["-c", C.extrasCommand("less")], { encoding: "utf8" }));
      t.ok("live: less is needed by something, and has its binary", live.rdeps.length > 0 && live.files.indexOf("/usr/bin/less") >= 0);
      t.ok("live: the package is not its own dependent", live.rdeps.indexOf("less") < 0);
    }

    // ── the tooltip ───────────────────────────────────────────────────────
    const ink = { muted: "#m", arrow: "#a", repo: "#r", aur: "#u", warn: "#w" };
    const d = C.describe(list, [], ink, 1, ["checked 3h ago — offline"]);
    t.has("note first", d.split("\n")[0], "offline");
    t.has("count line", d, "2 Updates");
    t.has("folded rest", d, "+ 1 more");
    t.ok("no AUR group when none", d.indexOf("AUR") === -1);
    t.has("markup escaped", C.describe([{ name: "a<b", from: "1", to: "2" }], [], ink, 5, []),
      "a&lt;b");

    // ── undoing a transaction ─────────────────────────────────────────────
    const tx = { events: [
      { verb: "upgraded", name: "nss", from: "3.129-1", to: "3.130-1" },
      { verb: "upgraded", name: "my-lib", from: "1.0-1", to: "1.1-1" },
      { verb: "upgraded", name: "later", from: "2.0-1", to: "2.1-1" },
      { verb: "upgraded", name: "aurpkg", from: "0.9-1", to: "1.0-1" },
      { verb: "installed", name: "newdep", from: "", to: "4.0-1" },
      { verb: "installed", name: "gonedep", from: "", to: "4.0-1" },
      { verb: "removed", name: "oldpkg", from: "", to: "7.0-2" },
      { verb: "reinstalled", name: "same", from: "", to: "1-1" },
    ] };
    const disk = "nss 3.130-1\nmy-lib 1.1-1\nlater 2.2-1\naurpkg 1.0-1\nnewdep 4.0-1\nsame 1-1\n@@files\n"
      + "/var/cache/pacman/pkg/nss-3.129-1-x86_64.pkg.tar.zst\n"
      + "/var/cache/pacman/pkg/nss-3.130-1-x86_64.pkg.tar.zst\n"
      + "/home/b/.cache/paru/my clone/aurpkg/aurpkg-0.9-1-x86_64.pkg.tar.zst\n"
      + "/var/cache/pacman/pkg/oldpkg-7.0-2-any.pkg.tar.zst\n";
    const U = C.readUndo(tx, disk);
    t.eq("an upgrade goes back to what it replaced, from the cache",
      U.back.find(b => b.name === "nss").file, "/var/cache/pacman/pkg/nss-3.129-1-x86_64.pkg.tar.zst");
    t.eq("an AUR build is found in paru's clone",
      U.back.find(b => b.name === "aurpkg").file, "/home/b/.cache/paru/my clone/aurpkg/aurpkg-0.9-1-x86_64.pkg.tar.zst");
    t.eq("a removal comes back", U.back.find(b => b.name === "oldpkg").version, "7.0-2");
    t.eq("an install is removed", U.remove.map(r => r.name).join(), "newdep");
    t.eq("a later upgrade is not jumped over", U.skipped.find(s => s.name === "later").why, "changed since, now 2.2-1");
    t.eq("no copy on disk is asked of the archive", U.missing.map(m => m.name).join(), "my-lib");
    t.ok("a reinstall has nothing to undo", !U.back.concat(U.remove, U.skipped).some(x => x.name === "same"));
    t.ok("an install already gone is left alone", !U.remove.concat(U.skipped).some(x => x.name === "gonedep"));
    const A = C.withArchive(U, "@@pkg my-lib\nmy-lib-1.0-1-x86_64.pkg.tar.zst\n");
    t.has("the archive fills the gap", (A.back.find(b => b.name === "my-lib") || {}).url || "", "archive.archlinux.org");
    t.eq("and nothing is left missing", A.missing.length, 0);
    const N = C.withArchive(U, "@@pkg my-lib\n");
    t.eq("no archive copy is a skip that says so", N.skipped.find(s => s.name === "my-lib").why, "no copy of 1.0-1 left");
    const S = C.undoSteps(A);
    t.eq("everything going back is one pacman -U", S[0].slice(0, 4).join(" "), "@sudo pacman -U --noconfirm");
    t.eq("with every source in it", S[0].length - 4, A.back.length);
    t.eq("then one removal", S[1].join(" "), "@sudo pacman -R --noconfirm newdep");
    t.eq("nothing to do is no steps", C.undoSteps({ back: [], remove: [] }).length, 0);
    t.eq("what a command named", C.commandTargets("pacman --remove -s --noconfirm -- gimp").join(), "gimp");
    t.eq("without a --, every non-flag word",
      C.commandTargets("pacman -U /var/cache/pacman/pkg/less-1:710-1-x86_64.pkg.tar.zst").join(),
      "less-1:710-1-x86_64.pkg.tar.zst");
    const rm = { command: "pacman --remove -s --noconfirm -- gimp", events: [
      { verb: "removed", name: "gimp", from: "", to: "3.2.6-2" },
      { verb: "removed", name: "gegl", from: "", to: "0.4.72-3" } ] };
    const R = C.readUndo(rm, "@@files\n/var/cache/pacman/pkg/gimp-3.2.6-2-x86_64.pkg.tar.zst\n"
      + "/var/cache/pacman/pkg/gegl-0.4.72-3-x86_64.pkg.tar.zst\n");
    t.eq("what was asked for comes back as asked for", R.back.find(b => b.name === "gimp").asdeps, false);
    t.eq("what came along comes back as a dependency", R.back.find(b => b.name === "gegl").asdeps, true);
    t.eq("and pacman is told so after the install",
      C.undoSteps(R).map(x => x.slice(1, 4).join(" ")).join(" | "), "pacman -U --noconfirm | pacman -D --asdeps");
    t.eq("an upgrade going back keeps its own reason", U.back.find(b => b.name === "nss").asdeps, false);
    t.eq("with no command on record, nothing is guessed a dependency",
      U.back.find(b => b.name === "oldpkg").asdeps, false);
    t.has("the command reads the clone folders too",
      C.undoCommand("/home/b/.cache/paru/my clone"), "'/home/b/.cache/paru/my clone'");

    // ── the mirrors ───────────────────────────────────────────────────────
    t.eq("a Server line's mirror", C.mirrorBase("Server = https://x.org/arch linux/$repo/os/$arch"), "https://x.org/arch linux/");
    t.eq("its host", C.mirrorHost("https://x.org:8443/arch/"), "x.org:8443");
    const mfeed = JSON.stringify({ urls: [
      { url: "https://good.org/arch/", protocol: "https", active: true, completion_pct: 1, delay: 60, last_sync: "x", country_code: "DE" },
      { url: "https://slow.org/arch/", protocol: "https", active: true, completion_pct: 1, delay: 200000, last_sync: "x", country_code: "US" },
      { url: "https://dead.org/arch/", protocol: "https", active: true, completion_pct: 0, delay: null, last_sync: null, country_code: "US" },
      { url: "http://plain.org/arch/", protocol: "http", active: true, completion_pct: 1, delay: 60, last_sync: "x", country_code: "FR" } ] });
    const MH = C.readMirrorHealth("1700000000\n@@list\nServer = https://good.org/arch/$repo/os/$arch\n"
      + "Server = https://slow.org/arch/$repo/os/$arch\nServer = https://dead.org/arch/$repo/os/$arch\n"
      + "Server = https://nowhere.org/$repo/os/$arch\n@@status\n" + mfeed + "\n@@probe\n0.240 200");
    t.eq("the list's age", MH.modified, 1700000000000);
    t.eq("every server read", MH.servers.length, 4);
    t.eq("behind: a day late, or incomplete", MH.behind, 2);
    t.eq("unknown to Arch's feed", MH.unknown, 1);
    t.eq("the first server's answer, from here", MH.firstMs, 240);
    t.eq("a server knows its country", MH.servers[0].country, "DE");
    t.eq("no feed, no verdicts", C.readMirrorHealth("1\n@@list\nServer = https://a/$repo\n@@status\n\n@@probe\n").behind, 0);
    t.eq("candidates: healthy and https only", C.mirrorCandidates(MH.status).join(), "https://good.org/arch/");
    const rc = C.rankCommand(["https://a b/arch/"], 12);
    t.has("candidates are quoted", rc, "'https://a b/arch/'");
    t.has("the quickest twelve are rated", rc, "head -12");
    const RK = C.readRank("ping 0.300 200 https://a/\nping 0.200 200 https://b/\nping 4.000 000 https://c/\n"
      + "rate 900000 200 https://a/\nrate 2500000 200 https://b/\n", 10);
    t.eq("everything timed is counted", RK.pinged, 3);
    t.eq("and what answered", RK.answered, 2);
    t.eq("ranked by download rate", RK.ranked.map(r => r.host).join(), "b,a");
    t.eq("with its round trip beside it", RK.ranked[0].ms, 200);
    const ML = C.mirrorlistText(RK.ranked, "2026-09-24");
    t.has("the list says where it came from", ML, "# Ranked by ceres on 2026-09-24");
    t.has("and is pacman's format", ML, "Server = https://b/$repo/os/$arch");
  }
};

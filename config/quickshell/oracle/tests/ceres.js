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

    // ── the log, read off a pty ───────────────────────────────────────────
    t.eq("a mark glued to pacman's last text", C.txMark("\u2026cache...@@exit 0"),
      { kind: "exit", code: 0, before: "\u2026cache..." });
    t.eq("a mark alone", C.txMark("@@authed"), { kind: "authed", before: "" });
    t.eq("prose is no mark", C.txMark("removing @@exit things"), null);
    t.eq("a stray break does not hide the exit mark", C.cleanLine("\n@@exit 0"), "@@exit 0");
    t.eq("escapes and the pty's space cleaned", C.cleanLine("\x1b[1;34m::\x1b[0m Retrieving\x1b[K  "), ":: Retrieving");
    const dl = C.progressOf(" linux-6.9-1-x86_64   135.0 MiB  20.5 MiB/s 00:05 [#####-----]  45%");
    t.eq("a download bar read", [dl.label, dl.size, dl.rate, dl.eta, dl.pct, dl.download],
      ["linux-6.9-1-x86_64", "135.0 MiB", "20.5 MiB/s", "00:05", 45, true]);
    const inst = C.progressOf("(1/5) upgrading linux                 [##########] 100%");
    t.eq("an install bar read", [inst.label, inst.pct, inst.download], ["(1/5) upgrading linux", 100, false]);
    t.eq("candy bars too", C.progressOf("foo 1.0 MiB 2.0 MiB/s 00:01 [--C o o o]  30%").pct, 30);
    t.eq("prose is not a bar", C.progressOf(":: Retrieving packages..."), null);
    t.eq("the Total bar is the whole download",
      C.overallOf(C.progressOf(" Total ( 2/10)  300.0 MiB  25.0 MiB/s 00:10 [##--------]  20%")), 0.2);
    t.eq("package 3 of 4 half done is 62.5% of the job",
      C.overallOf(C.progressOf("(3/4) upgrading linux          [#####-----]  50%")), 0.625);
    t.eq("a lone file's bar says nothing of the whole",
      C.overallOf(C.progressOf(" foo 1.0 MiB 2.0 MiB/s 00:01 [#-]  30%")), null);
    const f1 = C.foldLine(["a", " Total ( 1/3)  9 MiB  1 MiB/s 00:09 [#---]  10%"],
      " Total ( 2/3)  9 MiB  1 MiB/s 00:05 [##--]  50%");
    t.eq("a redrawn bar replaces itself", f1.length, 2);
    t.has("with its new reading", f1[1], "50%");
    const f2 = C.foldLine([" a 1 MiB 1 MiB/s 00:01 [#-]  10%", " b 1 MiB 1 MiB/s 00:01 [#-]  10%"],
      " a 1 MiB 1 MiB/s 00:01 [##]  90%");
    t.eq("parallel bars each keep their row", [f2.length, f2[0].indexOf("90%") > 0], [2, true]);
    t.eq("other lines are added", C.foldLine(["a"], "b"), ["a", "b"]);
    t.eq("a redraw replaces the line before it",
      C.foldLine(["x", "  1 230.3M  1 3.20M"], "  2 230.3M  2 6.90M", 400, true),
      ["x", "  2 230.3M  2 6.90M"]);
    t.eq("and capped", C.foldLine(["a", "b"], "c", 2), ["b", "c"]);

    // ── why a removal cannot happen ───────────────────────────────────────
    const bl = C.blockers([
      "removing hyprcursor breaks dependency 'hyprcursor' required by hyprland",
      "removing hyprcursor breaks dependency 'libhyprcursor.so=0-64' required by hyprland",
      "removing foo breaks dependency 'foo' required by bar"]);
    t.eq("grouped by what is in the way", bl.needs,
      [{ by: "hyprland", deps: ["hyprcursor", "libhyprcursor.so=0-64"] }, { by: "bar", deps: ["foo"] }]);
    t.eq("pacman's headline in plain words",
      C.removeHeadline("failed to prepare transaction (could not satisfy dependencies)"),
      "Other packages still need this");
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
    const askpass = path.join(__dirname, "..", "..", "scripts", "ceres-askpass.sh");
    const run = (pw, steps) => {
      try { fs.rmSync(fifo + ".calls", { force: true }); } catch (e) {}
      try {
        return execFileSync("/bin/sh", ["-c", C.runCommand(fifo, askpass, steps)],
          { encoding: "utf8", input: pw + "\n", timeout: 20000,
            env: Object.assign({}, process.env, { PATH: bin + ":" + process.env.PATH }) })
          .replace(/\r/g, "");
      } catch (e) { return e.stdout ? String(e.stdout).replace(/\r/g, "") : "threw " + e.message; }
    };
    const calls = () => { try { return fs.readFileSync(fifo + ".calls", "utf8").length / 2; } catch (e) { return 0; } };
    // no password at all: the steps run, the marks are the same, sudo never
    const free = execFileSync("/bin/sh", ["-c", C.runCommand(fifo, askpass, [["@user", "echo just-me"]], "", true)],
      { encoding: "utf8", input: "\n", timeout: 20000,
        env: Object.assign({}, process.env, { PATH: bin + ":" + process.env.PATH }) }).replace(/\r/g, "");
    t.has("a user's job runs", free, "just-me");
    t.has("marked authed", free, "@@authed");
    t.eq("and ends 0", C.splitExit(free).code, 0);
    t.eq("without asking sudo", calls(), 0);
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
    // paru's unasked questions, from the log of a real refused install
    const refused = [
      ":: Resolving dependencies...",
      ":: There are 2 providers available for artcraft:",
      ":: Repository AUR:",
      "    1) artcraft  2) artcraft-git",
      "Enter a number (default=1): :: Calculating conflicts...",
      ":: Calculating inner conflicts...",
      ":: Conflicts found:",
      "    nodejs-lts-krypton: nodejs",
      ":: Conflicting packages will have to be confirmed manually",
      "error: can not install conflicting packages with --noconfirm"];
    const settle = C.settleOf(refused);
    t.eq("settle: the provider menu", settle.providers, [{ name: "artcraft", options: ["artcraft", "artcraft-git"] }]);
    t.eq("settle: what comes in and what it replaces", settle.conflicts,
      [{ pkg: "nodejs-lts-krypton", replaces: ["nodejs"], inner: false }]);
    t.eq("settle: any other failure is not a question", C.settleOf(["error: target not found: x"]), null);
    // pacman's own form of the refusal (bitwarden-cli, 2026-10-14)
    const pacForm = C.settleOf([
      "looking for conflicting packages...",
      ":: nodejs-lts-jod-22.23.3-2 and nodejs-26.11.1-1 are in conflict. Remove nodejs? [y/N]",
      "error: unresolvable package conflicts detected",
      "error: failed to prepare transaction (conflicting dependencies)",
      ":: nodejs-lts-jod-22.23.3-2 and nodejs-26.11.1-1 are in conflict"]);
    t.eq("settle: pacman's 'are in conflict', once", pacForm.conflicts,
      [{ pkg: "nodejs-lts-jod", replaces: ["nodejs"], inner: false }]);
    t.eq("settle: pacman's form is answered through --useask",
      C.settledSteps([["-S", "--needed", "bitwarden-cli"]], pacForm, {}),
      [["-S", "--useask", "--needed", "bitwarden-cli"]]);
    t.eq("required by, per package", C.requiredByOf(
      "Name            : nodejs\nVersion         : 26.11.1-1\nRequired By     : node-gyp  nodejs-nopt  npm\n                  semver\n\n"
      + "Name            : foo\nRequired By     : None\n"), { nodejs: ["node-gyp", "nodejs-nopt", "npm", "semver"], foo: [] });
    t.eq("tx kind: an install", C.txKindOf([["-S", "--needed", "bitwarden-cli"]]), "install");
    t.eq("tx kind: an update", C.txKindOf([["-Syu"]]), "update");
    t.eq("tx kind: a removal", C.txKindOf([["-Rs", "x"]]), "remove");
    t.eq("tx kind: a Flatpak update is an update", C.txKindOf([["@user", "flatpak update --user -y"]]), "update");
    t.eq("tx kind: services restarted are other", C.txKindOf([["@user", "systemctl --user restart a"]]), "other");
    t.eq("done line: restart", C.doneLine("restart spotify and 2 more"), "Restarted spotify and 2 more");
    t.eq("done line: nothing said", C.doneLine(""), "");
    t.eq("done line: an unknown verb", C.doneLine("rehearsal: reinstall x"), "");
    t.eq("tx kind: settled install is still one", C.txKindOf([["-S", "--useask", "x"], ["@sudo", "pacman", "-D", "--asdeps", "b"]]), "install");
    t.eq("settle: a conflict line without the refusal is not a question",
      C.settleOf([":: a-1-1 and b-2-1 are in conflict"]), null);
    t.eq("settle: menus across repos keep counting",
      C.settleOf([":: There are 3 providers available for java-runtime:", ":: Repository extra:",
                  "    1) jre-openjdk  2) jre11-openjdk", ":: Repository AUR:", "    3) zulu",
                  "error: can not install conflicting packages with --noconfirm"]).providers[0].options,
      ["jre-openjdk", "jre11-openjdk", "zulu"]);
    t.eq("settled: own target swapped, conflicts agreed through --useask",
      C.settledSteps([["-S", "--needed", "artcraft"]], settle, { artcraft: "artcraft-git" }),
      [["-S", "--useask", "--needed", "artcraft-git"]]);
    t.eq("settled: a dependency's provider rides along, then is a dependency",
      C.settledSteps([["-S", "--needed", "app"]], { providers: [{ name: "java-runtime", options: ["a", "b"] }], conflicts: [] },
        { "java-runtime": "b" }),
      [["-S", "--needed", "app", "b"], ["@sudo", "pacman", "-D", "--asdeps", "b"]]);
    t.eq("settled: removals and sudo steps untouched",
      C.settledSteps([["-S", "x"], ["-Rs", "y"], ["@sudo", "pacman", "-Sc"]], settle, {}),
      [["-S", "--useask", "x"], ["-Rs", "y"], ["@sudo", "pacman", "-Sc"]]);
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
    t.eq("the Store's own needs are marked as the Store's",
      C.readDeps("/usr/share/swcatalog/xml\ncheckupdates\n").missing.map((m) => m.pkg + ":" + m.store),
      ["pacman-contrib:false", "archlinux-appstream-data:true"]);
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
    t.eq("the paru package is read", C.readDeps("fzf\n=paru-bin\n").paruPkg, "paru-bin");
    t.eq("and is no missing program", C.readDeps("=paru-git\n").missing.length, 0);
    t.eq("no paru, no package", C.readDeps("paru\n").paruPkg, "");
    // the Store's catalog is a directory, not a program
    t.has("a data dependency is tested as a path", C.depsCommand(), "[ -e '/usr/share/swcatalog/xml' ]");
    t.eq("and named by its package", C.readDeps("/usr/share/swcatalog/xml\n").missing.map(m => m.pkg),
      ["archlinux-appstream-data"]);
    // Flatpak: asked, never required
    t.ok("flatpak here when not reported", C.readDeps("").flatpak);
    t.ok("and not when reported", !C.readDeps("flatpak\n").flatpak);
    t.eq("and it is no missing dependency", C.readDeps("flatpak\n").missing.length, 0);
    const fp = C.setupSteps(C.readDeps("flatpak\nfzf\n"), "", "/b", "", true);
    t.eq("flatpak in the same pacman call", fp[0], ["@sudo", "pacman", "-Syu", "--needed", "--noconfirm", "fzf", "flatpak"]);
    t.eq("then Flathub, system-wide", fp[1].slice(0, 5), ["@sudo", "flatpak", "remote-add", "--if-not-exists", "--system"]);
    const fpOnly = C.setupSteps(C.readDeps(""), "", "/b", "", true);
    t.eq("flatpak already here: only the remote", fpOnly.length, 1);
    t.eq("which is Flathub", fpOnly[0][5], "flathub");
    t.eq("asked no: nothing", C.setupSteps(C.readDeps("flatpak\n"), "", "/b", "", false).length, 0);
    // a job with nothing of root's in it
    t.ok("a user's flatpak needs no root", !C.needsRoot([["@user", "flatpak install --user -y flathub x"]]));
    t.ok("a system one does", C.needsRoot([["@sudo", "flatpak", "install", "--system", "x"]]));
    t.ok("an @user line that sudos does", C.needsRoot([["@user", "sudo -A flatpak uninstall --system --all"]]));
    t.ok("a paru step does", C.needsRoot([["-S", "x"]]));
    const na = C.runCommand("/f", "/a", [["@user", "echo hi"]], "T", true);
    t.ok("no sudo when nothing needs it", na.indexOf("sudo") < 0 && na.indexOf("@@authedT") >= 0);
    // Flatpak updates
    const fu = C.readFlatpakUpdates("I\tsystem\tcom.spotify.Client\tSpotify\t1.2.9\n"
      + "I\tuser\torg.a.B\tB\t2.0\n"
      + "U\tsystem\tcom.spotify.Client\t1.3.0\nU\tuser\torg.a.B\t2.0\n@@exit 0\n");
    t.ok("read", fu.ok);
    t.eq("named, from → to", [fu.list[0].name, fu.list[0].from, fu.list[0].to, fu.list[0].scope], ["Spotify", "1.2.9", "1.3.0", "system"]);
    t.eq("a rebuild says so", fu.list[1].to, "new build");
    t.ok("a failed system check is a failure", !C.readFlatpakUpdates("@@exit 1\n").ok);
    const rto = C.readFlatpakUpdates("R\tsystem\torg.freedesktop.Platform\nR\tsystem\torg.freedesktop.Platform.GL.default\n"
      + "R\tuser\torg.gnome.Platform\n@@exit 0\n");
    t.eq("runtime-only updates are seen, one row each installation", rto.list.map(u => u.scope + " " + u.name), ["system 2 runtimes", "user 1 runtime"]);
    t.eq("and updated, the system's as root", C.flatpakUpdateOne(rto.list[0])[0].slice(0, 4), ["@sudo", "flatpak", "update", "--system"]);
    t.ok("yours without", !C.needsRoot(C.flatpakUpdateOne(rto.list[1])));
    t.eq("Update all takes them", C.flatpakUpdateSteps(rto.list).length, 2);
    t.eq("all: system as root, yours without", C.flatpakUpdateSteps(fu.list).map(st => st[0]), ["@sudo", "@user"]);
    t.ok("yours alone needs no root", !C.needsRoot(C.flatpakUpdateSteps([fu.list[1]])));
    t.eq("just one", C.flatpakUpdateOne(fu.list[0])[0].slice(-1), ["com.spotify.Client"]);
    t.has("in the tooltip", C.describe([], [], { muted: "#1", arrow: "#2", repo: "#3", aur: "#4", warn: "#5", flat: "#6" }, 5, [], fu.list),
      "2 Flatpak Updates");
    // Flatpak in History
    const fh = "@@flatpak\n"
      + "Oct 14 21:46:06\tadd remote\t\t\tuser\n"
      + "Oct 14 21:47:08\tpull\torg.freedesktop.Platform.GL.default\t25.08\tuser\n"
      + "Oct 14 21:47:08\tdeploy install\torg.freedesktop.Platform.GL.default\t25.08\tuser\n"
      + "Oct 14 21:49:56\tdeploy install\torg.freedesktop.Platform.Locale\t25.08\tuser\n"
      + "Oct 14 21:52:25\tdeploy install\tcom.spotify.Client\tstable\tuser\n"
      + "Oct 14 23:10:00\tuninstall\tcom.spotify.Client\tstable\tuser\n"
      + "@@fpnames\ncom.spotify.Client\tSpotify\n";
    const now = Date.UTC(2026, 9, 15, 9, 0);
    const fpTx = C.readFlatpakHistory(fh, now);
    t.eq("two jobs: an install and, later, a removal", fpTx.length, 2);
    t.eq("the install, by the app's name, its runtimes in one line",
      fpTx[0].events.map(e => e.verb + " " + e.name), ["installed Spotify", "installed 2 runtimes"]);
    t.eq("dated this year, at its first event", [fpTx[0].date, fpTx[0].time], ["2026-10-14", "21:47"]);
    t.eq("said as Flatpak's", C.describeCommand(fpTx[0].command), "Flatpak install");
    t.eq("a removal", C.describeCommand(fpTx[1].command), "Flatpak removal");
    const mixed = C.readFlatpakHistory("Oct 14 22:31:00\tdeploy install\ta.Notes\tstable\tuser\n"
      + "Oct 14 22:32:00\tuninstall\tcom.spotify.Client\tstable\tuser\n"
      + "Oct 14 22:32:30\tuninstall\torg.x.Platform\t25.08\tuser\n", now);
    t.eq("an install and a removal minutes apart are two jobs", mixed.map(x => C.describeCommand(x.command)), ["Flatpak install", "Flatpak removal"]);
    t.eq("the runtime goes with the removal", mixed[1].events.map(e => e.name), ["com.spotify.Client", "1 runtime"]);
    t.eq("a date ahead of today is last year's", C.readFlatpakHistory("Dec 31 10:00:00\tdeploy install\ta.b\tstable\tsystem\n", now)[0].date, "2025-12-31");
    const merged = C.readHistory("[2026-10-14T22:00:00+0300] [ALPM] installed gimp (3.0-1)\n"
      + "[2026-10-14T22:00:00+0300] [PACMAN] Running 'pacman -S gimp'\n" + fh, now);
    t.eq("among pacman's, newest first", merged.map(x => x.command.split(" ")[0] + " " + x.time), ["flatpak 23:10", "pacman 22:00", "flatpak 21:47"]);
    // Flatpak's progress
    const fpp = C.flatpakProgressOf("\x1b]9;4;1;45\x07Installing 2/5\u2026 \u2588\u2588\u258c   45%  4.1 MB/s  00:12");
    t.eq("read from its terminal progress, with what and how fast",
      [fpp.pct, fpp.of, fpp.phase, fpp.rate, fpp.eta], [45, "2 of 5", "Installing 2 of 5", "4.1 MB/s", "00:12"]);
    t.eq("the percentage on the line, with no sequence", C.flatpakProgressOf("Updating 1/1\u2026 80%").pct, 80);
    t.eq("a phase alone", C.flatpakProgressOf("Uninstalling 1/2\u2026").phase, "Uninstalling 1 of 2");
    t.eq("anything else is nothing", C.flatpakProgressOf("Looking for matches\u2026"), null);
    t.eq("and the sequence never reaches the log", C.cleanLine("\x1b]9;4;1;45\x07Installing 2/5"), "Installing 2/5");
    // stale services, restarted
    t.eq("a stale service is restarted, as you", C.restartServicesSteps(["flatpak-session-helper.service"]),
      [["@user", "r=0; for u in 'flatpak-session-helper.service'; do "
        + "if [ \"$(systemctl --user show -p LoadState --value \"$u\")\" = not-found ]; "
        + "then systemctl --user stop \"$u\" 2>/dev/null; ! systemctl --user is-active -q \"$u\" || r=1; else systemctl --user restart \"$u\" || r=1; fi; done; exit $r"]]);
    t.ok("which needs no password", !C.needsRoot(C.restartServicesSteps(["a.service"])));
    t.eq("only services", C.restartServicesSteps(["session-2.scope"]), []);
    // Flatpak's leftovers
    const un = C.readFlatpakUnused("user\t\nuser\t 1.\t   \torg.freedesktop.Platform.GL.default\t25.08\tr\n"
      + "user\t 2.\t   \torg.freedesktop.Platform\t25.08\tr\nsystem\tNothing unused to uninstall\n");
    t.eq("unused runtimes read, whose", un.map(u => u.scope + " " + u.id), ["user org.freedesktop.Platform.GL.default", "user org.freedesktop.Platform"]);
    t.eq("taken out only where there are any", C.flatpakUnusedSteps(un).map(st => st[0]), ["@user"]);
    t.eq("none, nothing to do", C.flatpakUnusedSteps([]).length, 0);
    t.eq("a clean repair finds nothing", C.readFlatpakRepair("user\t[1/2] Verifying flathub:app/x\u2026\nuser\tChecking remotes...\nsystem\tWorking on the system installation at /var/lib/flatpak\n").problems.length, 0);
    t.eq("anything else is a problem", C.readFlatpakRepair("user\tObject missing: abc.file\n").problems.map(p => p.text), ["Object missing: abc.file"]);
    t.has("removing one: its data when asked", C.flatpakUninstallSteps("a.b", "user", true)[0][1], "--delete-data 'a.b'");
    t.has("and the runtimes it leaves", C.flatpakUninstallSteps("a.b", "user", false)[0][1], "uninstall --unused --user");
    t.eq("the system's too", C.flatpakUninstallSteps("a.b", "system", true).map(st => st.slice(0, 3).join(" ")), ["@sudo flatpak uninstall", "@sudo flatpak uninstall"]);
    const gone = C.flatpakRemoveSteps(true);
    t.ok("removing Flatpak clears its stores", gone.some(st => st.join(" ") === "@sudo rm -rf -- /var/lib/flatpak"));
    t.has("yours and its cache", gone[gone.length - 1][1], "/flatpak\" \"${XDG_CACHE_HOME:-$HOME/.cache}/flatpak\"");
    t.has("and the apps' data when asked", gone[gone.length - 1][1], ".var/app");
    t.ok("not when not", C.flatpakRemoveSteps(false)[3][1].indexOf(".var/app") < 0);
    t.ok("installs show their progress", C.flatpakInstallSteps("a.b", "system")[0].indexOf("--noninteractive") < 0);
    // Flatpak in Maintenance
    const mfp = C.readMaint("@@fpapps\nSpotify\tcom.spotify.Client\t14.1 MB\tuser\n@@fprt\nFreedesktop Platform\torg.freedesktop.Platform\t600 MB\tsystem\n@@end\n");
    t.eq("apps and runtimes read", [mfp.fpApps.length, mfp.fpRuntimes.length], [1, 1]);
    t.eq("with size, and whose", mfp.fpApps[0].right, "14.1 MB \u00b7 just you");
    t.eq("the system's says nothing more", mfp.fpRuntimes[0].right, "600 MB");
    // one Flatpak app
    t.eq("for everyone, as root", C.flatpakInstallSteps("a.b", "system")[0].slice(0, 3), ["@sudo", "flatpak", "install"]);
    t.ok("just you, no root", !C.needsRoot(C.flatpakInstallSteps("a.b", "user")));
    t.has("with Flathub added for you first", C.flatpakInstallSteps("a.b", "user")[0][1], "remote-add --user --if-not-exists flathub");
    t.ok("taken out of yours, no root", !C.needsRoot(C.flatpakUninstallSteps("a.b", "user")));
    t.eq("out of the system's, as root", C.flatpakUninstallSteps("a.b", "system")[0][1], "flatpak");
    // Settings › Channels
    t.eq("added later: flatpak alone, no upgrade", C.flatpakAddSteps()[0], ["@sudo", "pacman", "-S", "--needed", "--noconfirm", "flatpak"]);
    t.eq("then Flathub", C.flatpakAddSteps()[1][5], "flathub");
    const fpRm = C.flatpakRemoveSteps();
    t.has("removed: the user's apps first", fpRm[0][1], "flatpak uninstall --user --all");
    t.has("and the system's, as root", fpRm[0][1], "sudo -A flatpak uninstall --system --all");
    t.eq("then flatpak itself", fpRm[1], ["@sudo", "pacman", "-Rns", "--noconfirm", "flatpak"]);
    t.eq("installed apps read", C.parseFlatpaks("Inkscape\torg.inkscape.Inkscape\tsystem\nLutris\tnet.lutris.Lutris\tuser\n"),
      [{ name: "Inkscape", id: "org.inkscape.Inkscape", scope: "system" }, { name: "Lutris", id: "net.lutris.Lutris", scope: "user" }]);
    const sw = C.paruSwitchSteps("paru-git", C.readDeps(""), "/b");
    t.eq("a switch syncs nothing", sw[0], ["@sudo", "pacman", "-S", "--needed", "--noconfirm", "base-devel", "git"]);
    t.has("and builds the other recipe", sw[1][1], "https://aur.archlinux.org/paru-git.git");
    t.has("taking the conflict's removal", sw[1][1], "pacman -U --noconfirm --ask 4");
    t.ok("rust when there is no cargo", C.paruSwitchSteps("paru", C.readDeps("cargo\n"), "/b")[0].indexOf("rust") > 0);
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
              env: Object.assign({}, process.env, { PATH: b2 + ":" + process.env.PATH }) })
            // each step runs on a pty, which ends its lines \r\n; Ceres
            // strips the returns on the way in, and so does this
            .replace(/\r/g, "");
        } catch (e) { return e.stdout ? String(e.stdout).replace(/\r/g, "") : "threw " + e.message; }
      })();
      t.eq("bootstrap: exit 0", C.splitExit(out2).code, 0);
      t.has("bootstrap: a full upgrade with the deps", out2, "pacman: -Syu --needed --noconfirm fzf base-devel git");
      t.has("bootstrap: built", out2, "==> Making package: paru");
      t.has("bootstrap: installs only the package, as root",
        out2, "pacman: -U --noconfirm --ask 4 paru-2.1.0-2-x86_64.pkg.tar.zst\n");
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
    t.eq("archive: versions decoded, sigs and neighbors out", arc.map(a => a.version), ["1:563-1"]);
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
      // Against pacman itself, the one package every Arch machine is
      // guaranteed to have with something depending on it — this used to ask
      // after less, which is not installed everywhere, and failed there.
      const live = C.readExtras(require("child_process").execFileSync("/bin/sh", ["-c", C.extrasCommand("pacman")], { encoding: "utf8" }));
      t.ok("live: pacman is needed by something, and has its binary", live.rdeps.length > 0 && live.files.indexOf("/usr/bin/pacman") >= 0);
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

    // ── stopping a job, through a real shell and real processes ──────────
    // No password (""): nothing goes through sudo here, and a job that
    // needed none is stopped exactly this way.
    {
      const cp = require("child_process"), fs = require("fs"), os = require("os"), path = require("path");
      const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "ceres-stop-"));
      const clone = path.join(tmp, "clone");
      fs.mkdirSync(path.join(clone, "old"), { recursive: true });
      fs.utimesSync(path.join(clone, "old"), 1000, 1000);
      // a "job": a shell with a child, both deaf to what `deaf` lists
      // started in the background of a shell that exits at once, so it is
      // init's to reap, not this test's (which cannot while it waits)
      const job = (deaf) => {
        const trap = deaf ? "trap \"\" " + deaf + "; " : "";
        const pid = Number(cp.execFileSync("sh", ["-c",
          "sh -c '" + trap + "sleep 30 & wait' >/dev/null 2>&1 & echo $!"], { encoding: "utf8" }).trim());
        cp.execSync("sleep 0.3");
        return pid;
      };
      // as ceres runs it: the script as `sh -c`, the password on stdin
      const stop = (pid, committing, since) => cp.execFileSync("sh", ["-c", C.stopCommand(pid, committing, since, clone)], {
        input: "\n", encoding: "utf8", timeout: 20000 }).trim();
      const alive = (pid) => { try { process.kill(pid, 0); return true; } catch (e) { return false; } };

      const a = job("");
      t.eq("an interrupt that is heard stops it", stop(a, false, 0), "@@stopped 1");
      t.ok("and it is gone", !alive(a));

      const b = job("INT TERM");
      const since = Math.floor(Date.now() / 1000) - 1;
      fs.mkdirSync(path.join(clone, "built", "src"), { recursive: true });
      const t0 = Date.now();
      t.eq("deaf to INT and TERM, it is killed", stop(b, false, since), "@@stopped 1");
      t.ok("after the INT and TERM waits", Date.now() - t0 >= 4500);
      t.ok("and it is gone", !alive(b));
      t.ok("the build this job touched is cleared", !fs.existsSync(path.join(clone, "built")));
      t.ok("an older one is kept", fs.existsSync(path.join(clone, "old")));

      const c = job("INT");
      t.eq("while pacman writes, it is only asked", stop(c, true, 0), "@@stopped 0");
      t.ok("and left to finish", alive(c));
      cp.execSync("pkill -KILL -P " + c + "; kill -KILL " + c + " 2>/dev/null; true");
      fs.rmSync(tmp, { recursive: true, force: true });
    }
  }
};

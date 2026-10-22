// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// hestia's pure half: unit states, filters, actions and their systemctl
// lines, the journal's rows and filters, and the words for numbers.

"use strict";

module.exports = {
  module: "hestia/hestia.js",
  cases: (H, t) => {
    const run = { unit: "a.service", active: "active", sub: "running", file: "enabled", restarts: 0 };
    const oneshot = { unit: "b.service", active: "active", sub: "exited", file: "static" };
    const dead = { unit: "c.service", active: "inactive", sub: "dead", file: "disabled" };
    const bad = { unit: "d.service", active: "failed", sub: "failed", file: "enabled" };
    const loop = { unit: "e.service", active: "active", sub: "running", file: "enabled", restarts: 3773 };

    // state
    t.eq("running", [H.stateRole(run), H.stateWords(run)], ["ok", "Running"]);
    t.eq("a oneshot that ran", [H.stateRole(oneshot), H.stateWords(oneshot)], ["done", "Done"]);
    t.eq("stopped", [H.stateRole(dead), H.stateWords(dead)], ["off", "Stopped"]);
    t.eq("failed", [H.stateRole(bad), H.stateWords(bad)], ["bad", "Failed"]);
    t.eq("starting", H.stateWords({ active: "activating" }), "Activating…");
    t.eq("boot words", H.bootWords("static"), "Started by others");
    t.eq("an unknown boot state", H.bootWords("weird"), "Weird");
    t.eq("crash-looping", H.looping(loop), true);
    t.eq("not looping", H.looping(run), false);

    // filters
    const all = [dead, bad, run, oneshot, loop];
    t.eq("running", H.filterUnits(all, "", "running").map((u) => u.unit), ["a.service", "b.service", "e.service"]);
    t.eq("failed", H.filterUnits(all, "", "failed").map((u) => u.unit), ["d.service"]);
    t.eq("at boot", H.filterUnits(all, "", "enabled").length, 3);
    t.eq("typed", H.filterUnits(all, "C.SERV", "all").map((u) => u.unit), ["c.service"]);
    t.eq("failed first", H.sortUnits(all)[0].unit, "d.service");
    t.eq("counts", H.counts(all), { running: 3, failed: 1, enabled: 3, all: 5, looping: 1 });
    t.eq("short name", H.shortName("nusgmon.service"), "nusgmon");

    // actions
    t.eq("a running unit stops and restarts", H.actions(run).map((a) => a.verb), ["stop", "restart", "disable"]);
    t.eq("a stopped one starts", H.actions(dead).map((a) => a.verb), ["start", "enable"]);
    t.eq("a failed one clears", H.actions(bad).map((a) => a.verb), ["start", "disable", "reset-failed"]);
    t.eq("static has no boot switch", H.actions(oneshot).map((a) => a.verb), ["stop", "restart"]);
    t.eq("masked only unmasks", H.actions({ file: "masked", active: "inactive" }).map((a) => a.verb), ["unmask"]);
    t.eq("system line", H.actionArgs("system", "restart", "x.service"), ["systemctl", "restart", "x.service"]);
    t.eq("user line", H.actionArgs("user", "stop", "x.service"), ["systemctl", "--user", "stop", "x.service"]);
    t.eq("enable starts it too", H.actionArgs("system", "enable", "x.service"), ["systemctl", "enable", "--now", "x.service"]);
    t.eq("said", H.verbWords("disable", "x.service"), "x no longer starts at boot");

    // the journal
    const r = H.parseJournalLine(JSON.stringify({ __REALTIME_TIMESTAMP: "1792540987218000", PRIORITY: "3", SYSLOG_IDENTIFIER: "systemd", _SYSTEMD_UNIT: "init.scope", _PID: "1", MESSAGE: "boom\n" }));
    t.eq("a row", [r.t, r.prio, r.ident, r.unit, r.msg], [1792540987218, 3, "systemd", "init.scope", "boom"]);
    t.eq("a byte-array message", H.journalRow({ MESSAGE: [104, 105] }).msg, "hi");
    t.eq("garbage is no row", H.parseJournalLine("{"), null);
    t.eq("a terminal's colour codes stripped", H.journalRow({ MESSAGE: "\u001b[1mSkipping\u001b[0m x" }).msg, "Skipping x");
    t.eq("…in a byte array too", H.journalRow({ MESSAGE: [27, 91, 49, 109, 104, 105] }).msg, "hi");
    t.eq("no priority is info", H.journalRow({}).prio, 6);
    t.eq("roles", [0, 3, 4, 5, 6, 7].map(H.prioRole), ["bad", "bad", "warn", "note", "plain", "plain"]);
    t.eq("filters for the reader", H.logArgs({ unit: "x.service", prio: "4", boot: "-1", grep: "oops", n: 50 }),
      ["--unit", "x.service", "--prio", "4", "--boot", "-1", "--grep", "oops", "-n", "50"]);
    t.eq("a user unit", H.logArgs({ user: true, unit: "y.service" }), ["--user", "--unit", "y.service", "-n", "400"]);
    const f = H.logArgs({ user: true, unit: "y.service", prio: "3" }, true);
    t.eq("following", f.slice(0, 7), ["journalctl", "-f", "-o", "json", "-n", "0", "--no-pager"]);
    t.has("following a user unit", f.join(" "), "--user --user-unit y.service -p 3");
    t.eq("capped to the newest", H.capRows([1, 2, 3, 4], 2), [3, 4]);

    // words
    t.eq("bytes", H.bytes(12173312), "11.6 MB");
    t.eq("no bytes", H.bytes(-1), "");
    t.eq("cpu ms", H.cpuTime(82427000), "82 ms");
    t.eq("cpu minutes", H.cpuTime(250e9), "4 min 10 s");
    const now = Date.parse("2026-10-21T00:00:00Z");
    t.eq("in 4 h", H.relUs((now + 4 * 3600e3) * 1000, now), "in 4 h");
    t.eq("a day ago", H.relUs((now - 86400e3) * 1000, now), "1 day ago");
    t.eq("never", H.relUs(0, now), "");
    t.eq("today's clock has no date", H.clock(now - 1000, now).length, 8);
    t.eq("another day's has one", H.clock(now - 3 * 86400e3, now).length, 19);

    // ── drives ────────────────────────────────────────────────────────────
    const nv = { kind: "nvme", smart: true, warnings: [], tempK: 310, hours: 28060, usedPct: 5, spareLeft: 100, spareThresh: 5,
                 written: 53274297856000, read: 1, mediaErrors: 0, unsafe: 114, badSectors: -1, attrsFailing: -1, wcTempK: 343,
                 devs: ["/dev/nvme0n1", "/dev/nvme0n1p2"] };
    t.eq("a healthy drive", H.diskVerdict(nv).level, "good");
    t.eq("…in a line", H.diskLine(nv), "Good · 37 °C · 5% worn");
    t.eq("a critical warning is bad", H.diskVerdict(Object.assign({}, nv, { warnings: ["spare"] })).words, "Spare blocks nearly used up");
    t.eq("spare at its threshold is bad", H.diskVerdict(Object.assign({}, nv, { spareLeft: 5 })).level, "bad");
    t.eq("nearly worn is a warning", H.diskVerdict(Object.assign({}, nv, { usedPct: 93 })).words, "Nearly worn out (93%)");
    t.eq("media errors warn", H.diskVerdict(Object.assign({}, nv, { mediaErrors: 2 })).words, "2 media errors");
    t.eq("hot warns", H.diskVerdict(Object.assign({}, nv, { tempK: 350 })).words, "Running hot");
    t.eq("an ATA drive failing", H.diskVerdict({ kind: "ata", smart: true, failing: true, badSectors: 3 }).why.length, 2);
    t.eq("SMART off says so", H.diskVerdict({ kind: "ata", smart: false }).level, "unknown");
    t.eq("no data", H.diskVerdict({ kind: "" }).level, "unknown");
    t.eq("hours in words", H.hoursWords(28060), "3 years 74 days (28,060 h)");
    t.eq("a few hours", H.hoursWords(5), "5 h (5 h)");
    t.eq("bytes as drives are sold", H.driveBytes(53274297856000), "53.3 TB");
    t.eq("small bytes", H.driveBytes(512), "512 B");
    t.eq("facts start with health", H.diskHealthFacts(nv)[0], ["Health", "Good", ""]);
    t.eq("a partition finds its drive", H.driveOf([nv], "/dev/nvme0n1p2") === nv, true);
    t.eq("an unknown device has none", H.driveOf([nv], "/dev/sdz"), null);
    t.eq("firmware without fwupd", H.parseFirmware('{"installed":false,"devices":[]}').installed, false);
    t.eq("a broken firmware answer", H.parseFirmware("x").known, false);
  }
};

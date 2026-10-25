// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// kairos' pure half: what a window counts as, time split across hours and
// midnight, a week, the most used, durations, a timer's summary.

"use strict";

module.exports = {
  module: "kairos/kairos.js",
  cases: (K, t) => {
    const own = ["terminus", "hestia", "kairos"];
    t.eq("a class", K.appKey("Kitty", "zsh", own), "kitty");
    t.eq("one of ours", K.appKey("org.quickshell", "hestia", own), "hestia");
    t.eq("Tidy is ours", [K.appKey("org.quickshell", "hygieia"), K.isOwn("hygieia"), K.prettyKey("hygieia")], ["hygieia", true, "Tidy"]);
    t.eq("ours, unknown title", K.appKey("org.quickshell", "something", own), "zenworks");
    t.eq("no window", K.appKey("", "x", own), "");
    t.eq("a picker title", K.appKey("org.quickshell", "terminus-picker"), "terminus");
    t.eq("UI names", [K.prettyKey("hestia"), K.prettyKey("terminus")], ["System Journal", "Terminus"]);

    const months = {};
    // 10 minutes ending 14:05 → 5 in 13h, 5 in 14h
    let touched = K.addTime(months, "kitty", 600, new Date(2026, 9, 21, 14, 5));
    let day = K.dayOf(months, "2026-10-21");
    t.eq("split across hours", [day.hours[13], day.hours[14], day.apps.kitty], [300, 300, 600]);
    t.eq("month touched", Object.keys(touched), ["2026-10"]);
    // ending exactly on the hour: all in the hour before
    K.addTime(months, "kitty", 60, new Date(2026, 9, 21, 16, 0));
    t.eq("on the hour", [day.hours[15], day.hours[16]], [60, 0]);
    // across midnight into a new month
    touched = K.addTime(months, "plato", 120, new Date(2026, 10, 1, 0, 1));
    t.eq("across midnight", [K.dayOf(months, "2026-10-31").hours[23], K.dayOf(months, "2026-11-01").hours[0]], [60, 60]);
    t.eq("both months", Object.keys(touched).sort(), ["2026-10", "2026-11"]);
    t.eq("nothing for no key", Object.keys(K.addTime(months, "", 60, new Date())), []);

    t.eq("total", K.total(day), 660);
    t.eq("week", K.week(months, new Date(2026, 9, 27)).map((d) => d.total), [660, 0, 0, 0, 0, 0, 0]);
    const sum = K.sumDays(months, new Date(2026, 9, 21), new Date(2026, 10, 1));
    t.eq("summed", sum.apps, { kitty: 660, plato: 120 });
    const top = K.topApps(sum, 0);
    t.eq("top apps", top.map((r) => [r.key, Math.round(r.share * 100)]), [["kitty", 100], ["plato", 18]]);

    t.eq("durations", [K.fmt(0), K.fmt(45), K.fmt(840), K.fmt(7500)], ["0m", "45s", "14m", "2h 05m"]);

    let ticks = [];
    ticks = K.pushTick(ticks, 1000, "a", 5, 60000);
    ticks = K.pushTick(ticks, 50000, "b", 70, 60000);
    ticks = K.pushTick(ticks, 70000, "a", 60, 60000);
    t.eq("old ticks dropped", ticks.map((x) => x.at), [50000, 70000]);
    t.eq("since", K.since(ticks, 0), [{ key: "b", secs: 70 }, { key: "a", secs: 60 }]);
    t.eq("summary", K.summaryLine(K.since(ticks, 0), (k) => k.toUpperCase()), "B 1m, A 1m");

    t.eq("pretty keys", [K.prettyKey("org.gnome.Nautilus"), K.prettyKey("brave-browser"), K.prettyKey("zenworks")],
      ["Nautilus", "Brave browser", "Zenworks"]);
    t.eq("broken file", K.parseMonth("{nope").days, {});

    // ── limits and breaks ──
    t.eq("no file, no limits", K.parseLimits(""), K.emptyLimits());
    const L = K.parseLimits(JSON.stringify({ limits: { firefox: 60, bad: "x", zero: 0 }, told: { day: "2026-10-22", keys: { firefox: true } } }));
    t.eq("only real limits are kept", L.limits, { firefox: 60 });
    t.eq("round trip", K.parseLimits(K.serializeLimits(L)), L);
    t.eq("a limit set", K.withLimit({}, "kitty", 30), { kitty: 30 });
    t.eq("…and taken off", K.withLimit({ kitty: 30 }, "kitty", 0), {});
    t.eq("under the limit", K.limitDue(L.limits, K.emptyLimits().told, "2026-10-23", "firefox", 59 * 60), false);
    t.eq("reached", K.limitDue(L.limits, K.emptyLimits().told, "2026-10-23", "firefox", 3600), true);
    t.eq("already said today", K.limitDue(L.limits, L.told, "2026-10-22", "firefox", 4000), false);
    t.eq("said yesterday, due again", K.limitDue(L.limits, L.told, "2026-10-23", "firefox", 4000), true);
    t.eq("no limit, never due", K.limitDue(L.limits, L.told, "2026-10-23", "kitty", 99999), false);
    t.eq("a new day clears what was said", K.markTold(L.told, "2026-10-23", "kitty"), { day: "2026-10-23", keys: { kitty: true } });
    t.eq("the same day adds to it", Object.keys(K.markTold(L.told, "2026-10-22", "kitty").keys).length, 2);
    t.eq("limit words", [K.limitWords(0), K.limitWords(30), K.limitWords(60), K.limitWords(90)], ["No limit", "30 min", "1 h", "1 h 30 min"]);
    t.eq("time against a limit", K.againstLimit(3900, 60), "1h 05m of 1 h");
    t.eq("a break due", [K.breakDue(1199, 20), K.breakDue(1200, 20), K.breakDue(99999, 0)], [false, true, false]);
  }
};

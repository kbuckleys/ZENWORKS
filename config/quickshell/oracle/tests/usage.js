// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// the colored usage bar's pure half (terminus/usage.js): stretches, the
// legend, the scan's words.

"use strict";

module.exports = {
  module: "terminus/usage.js",
  cases: (U, t) => {
    const GiB = 1073741824;
    const df = { total: 100 * GiB, used: 40 * GiB, free: 60 * GiB };

    t.eq("nothing known", U.stretches(null, null), []);
    t.eq("before a walk: one used stretch", U.stretches(df, null).map((s) => [s.id, s.frac]), [["used", 0.4]]);
    const cats = { system: 20 * GiB, pictures: 10 * GiB, other: 2 * GiB, music: 0 };
    t.eq("kinds in order, the unfound is Other", U.stretches(df, cats).map((s) => [s.id, s.bytes / GiB]),
      [["system", 20], ["pictures", 10], ["other", 10]]);
    const over = { system: 60 * GiB, videos: 20 * GiB };
    t.eq("a walk past the used room is scaled down", U.stretches(df, over).map((s) => [s.id, s.bytes / GiB]),
      [["system", 30], ["videos", 10]]);
    t.eq("slivers left out", U.stretches(df, { system: 40 * GiB, music: 1024 }).map((s) => s.id), ["system"]);
    t.eq("legend ends with free", U.legend(df, cats).map((l) => [l.name, l.line]),
      [["System", "20.0 GiB"], ["Pictures", "10.0 GiB"], ["Other", "10.0 GiB"], ["Free", "60.0 GiB"]]);
    t.eq("free words", U.freeWords(df), "60.0 GiB free of 100.0 GiB");

    const now = 1000000 * 1000;
    t.eq("scanning", U.scanWords({ scanning: true, files: 1234 }, now), "Sorting what is where… " + (1234).toLocaleString() + " files");
    t.eq("just now", U.scanWords({ at: 1000000 - 20 }, now), "Sorted just now");
    t.eq("minutes", U.scanWords({ at: 1000000 - 600 }, now), "Sorted 10 min ago");
    t.eq("hours", U.scanWords({ at: 1000000 - 3 * 3600 }, now), "Sorted 3 h ago");
    t.eq("days", U.scanWords({ at: 1000000 - 5 * 86400 }, now), "Sorted 5 days ago");
    t.eq("never", U.scanWords({}, now), "");
    t.eq("line", U.parseLine('{"ev":"df","total":1}'), { ev: "df", total: 1 });
    t.eq("not a line", U.parseLine("Traceback"), null);
  }
};

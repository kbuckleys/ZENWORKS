// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// chronos' pure half: the month grid, the timers' file, and the calendar —
// events by day, the quick-add line, and when a reminder is due.

"use strict";

module.exports = {
  module: "chronos/chronos.js",
  cases: (C, t) => {
    // the grid
    const g = C.monthGrid(2026, 9);
    t.eq("six weeks", g.length, 42);
    t.eq("iso", C.isoDay(2026, 9, 21), "2026-10-21");

    // events by day
    const ev = [
      { uid: "b", title: "Standup", date: "2026-10-21", start: "09:30", end: "09:45", endDate: "2026-10-21" },
      { uid: "a", title: "Holiday", date: "2026-10-21", allDay: true },
      { uid: "c", title: "Dentist", date: "2026-10-22", start: "14:00", end: "15:00", endDate: "2026-10-22" },
      { title: "no date" }
    ];
    const by = C.eventsByDay(ev);
    t.eq("all-day first, then by time", by["2026-10-21"].map((e) => e.title), ["Holiday", "Standup"]);
    t.eq("dateless dropped", Object.keys(by).length, 2);
    t.eq("a span", C.eventTime(ev[0]), "09:30 – 09:45");
    t.eq("all day", C.eventTime(ev[1]), "All day");

    // quick add
    t.eq("time and title", C.parseQuick("14:00 Dentist", "2026-10-22"),
      { allDay: false, start: "2026-10-22 14:00", end: "2026-10-22 15:00", title: "Dentist", location: "" });
    t.eq("a span and a place", C.parseQuick("14:00-15:30 Dentist @ Clinic", "2026-10-22"),
      { allDay: false, start: "2026-10-22 14:00", end: "2026-10-22 15:30", title: "Dentist", location: "Clinic" });
    t.eq("an hour alone", C.parseQuick("9 Standup", "2026-10-22").start, "2026-10-22 09:00");
    t.eq("no time is all day", C.parseQuick("Holiday", "2026-10-22"), { allDay: true, start: "2026-10-22", end: "", title: "Holiday", location: "" });
    t.eq("late, ends at midnight's edge", C.parseQuick("23:30 Late", "2026-10-22").end, "2026-10-22 23:59");
    t.has("not a time", C.parseQuick("25:00 x", "2026-10-22").error, "time of day");
    t.has("backwards", C.parseQuick("15-14 x", "2026-10-22").error, "ends before");
    t.has("nothing", C.parseQuick("  ", "2026-10-22").error, "Type");
    t.eq("cal.py's arguments", C.newArgs(C.parseQuick("Holiday", "2026-10-22"), "personal"), ["personal", "2026-10-22", "", "Holiday", ""]);

    // reminders
    const dentist = ev[2];
    const at = C.eventMs(dentist);
    t.eq("ten minutes before", C.remindersDue([dentist], at - 11 * 60000, at - 10 * 60000, 10, {}).length, 1);
    t.eq("not yet", C.remindersDue([dentist], at - 12 * 60000, at - 11 * 60000, 10, {}).length, 0);
    t.eq("not twice", C.remindersDue([dentist], at - 11 * 60000, at - 10 * 60000, 10, { [C.remindKey(dentist)]: true }).length, 0);
    t.eq("off", C.remindersDue([dentist], 0, at, -1, {}).length, 0);
    t.eq("all day at nine", new Date(C.eventMs(ev[1])).getHours(), 9);
    t.has("says when", C.remindWords(dentist, at - 10 * 60000), "In 10 min, at 14:00");
  }
};

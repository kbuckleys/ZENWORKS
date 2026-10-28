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
    t.eq("the clock's tooltip names the day", C.oneLine(new Date(2026, 9, 26)), "Monday, October 26, 2026");

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
    t.eq("cal.py's arguments", C.newArgs(C.parseQuick("Holiday", "2026-10-22"), "personal"), ["personal", "2026-10-22", "2026-10-22", "Holiday", ""]);
    t.eq("all day ends the day it starts, so a weekday is title", C.newArgs(C.parseQuick("Friday drinks", "2026-10-23"), ""),
      ["", "2026-10-23", "2026-10-23", "Friday drinks", ""]);

    // reminders
    const dentist = ev[2];
    const at = C.eventMs(dentist);
    t.eq("ten minutes before", C.remindersDue([dentist], at - 11 * 60000, at - 10 * 60000, 10, {}).length, 1);
    t.eq("not yet", C.remindersDue([dentist], at - 12 * 60000, at - 11 * 60000, 10, {}).length, 0);
    t.eq("not twice", C.remindersDue([dentist], at - 11 * 60000, at - 10 * 60000, 10, { [C.remindKey(dentist)]: true }).length, 0);
    t.eq("off", C.remindersDue([dentist], 0, at, -1, {}).length, 0);
    t.eq("all day at nine", new Date(C.eventMs(ev[1])).getHours(), 9);
    t.has("says when", C.remindWords(dentist, at - 10 * 60000), "In 10 min, at 14:00");

    // the calendar window (2026-10-28)
    t.eq("times typed", ["9", "930", "9:30", "21.30", "9pm", "12am", "9:30 am", "25", "13pm"].map(C.normTime),
         ["09:00", "09:30", "09:30", "21:30", "21:00", "00:00", "09:30", "", ""]);
    t.eq("dates typed", ["2026-11-2", "2026-02-30", "11/2"].map(C.normDate), ["2026-11-02", "", ""]);
    t.eq("week starts monday", C.isoOf(C.weekStart(new Date(2026, 10, 1))), "2026-10-26");
    const ev2 = (s, e, extra) => Object.assign({ date: "2026-11-02", endDate: "2026-11-02", start: s, end: e, allDay: false }, extra || {});
    const lay = C.layoutDay([ev2("09:00", "10:00"), ev2("09:30", "11:00"), ev2("10:00", "10:30"), ev2("12:00", "13:00"),
                             ev2("", "", { allDay: true })], "2026-11-02");
    t.eq("overlaps side by side", lay.map((l) => [l.s, l.col, l.cols]), [[540, 0, 2], [570, 1, 2], [600, 0, 2], [720, 0, 1]]);
    t.eq("runs past midnight", C.spanOn(ev2("23:00", "01:00", { endDate: "2026-11-03" }), "2026-11-02"), { s: 1380, e: 1440 });
    t.eq("and from it the next day", C.spanOn(ev2("23:00", "01:00", { endDate: "2026-11-03" }), "2026-11-03"), { s: 0, e: 60 });
    t.eq("ranges", [C.rangeOf("day", new Date(2026, 10, 2)), C.rangeOf("week", new Date(2026, 10, 4)), C.rangeOf("month", new Date(2026, 10, 15))],
         [["2026-11-02", "2026-11-03"], ["2026-11-02", "2026-11-09"], ["2026-10-26", "2026-12-07"]]);
    t.eq("steps", [C.isoOf(C.stepDate("month", new Date(2026, 0, 31), 1)), C.isoOf(C.stepDate("week", new Date(2026, 10, 2), -1))],
         ["2026-02-01", "2026-10-26"]);
    t.eq("titles", [C.rangeTitle("month", new Date(2026, 10, 2)), C.rangeTitle("week", new Date(2026, 10, 30))],
         ["November 2026", "Nov 30 – Dec 6, 2026"]);
    t.eq("colors", [C.calColor("dark cyan", 0), C.calColor("#AA00ff", 0), C.calColor("", 1), C.calColor("light purple", 0), C.calColor("#007aff")],
         ["cyan", "#aa00ff", "green", "magenta", "#007aff"]);
    t.eq("other apps' words", [C.calColor("tan"), C.calColor("#5B8FD9"), C.calColor("Gold")], ["sand", "blue", "yellow"]);
    t.eq("snapped to the quarter hour", [C.snapMinutes(30, 48), C.snapMinutes(-50, 48), C.snapMinutes(5, 48)], [45, -60, 0]);
    const tev = { allDay: false }, aev = { allDay: true };
    t.eq("a drag", [C.dragShift(tev, 1, 30, false), C.dragShift(tev, 0, -90, true, 60), C.dragShift(aev, 2, 0, false)],
         [{ ds: 1470, de: 1470 }, { ds: 0, de: -45 }, { ds: 2, de: 2 }]);
    t.eq("days between", [C.daysBetween("2026-10-30", "2026-11-02"), C.daysBetween("2026-11-02", "2026-11-01")], [3, -1]);
    t.eq("undo of a new event deletes it", C.inverse({ kind: "save", before: null, after: { uid: "x" } }), { kind: "delete", before: { uid: "x" } });
    t.eq("undo of a delete saves it", C.inverse({ kind: "delete", before: { uid: "x" } }).kind, "save");
    t.eq("undo of a shift", C.inverse({ kind: "shift", uid: "x", ds: 30, de: 60 }), { kind: "shift", uid: "x", ds: -30, de: -60 });
    t.eq("a year", [C.rangeOf("year", new Date(2026, 4, 3)), C.isoOf(C.stepDate("year", new Date(2026, 4, 3), 1)), C.rangeTitle("year", new Date(2026, 4, 3))],
         [["2026-01-01", "2027-01-01"], "2027-05-01", "2026"]);
    t.eq("title parts", [C.titleParts("month", new Date(2026, 9, 2)), C.titleParts("week", new Date(2026, 9, 28)), C.titleParts("day", new Date(2026, 9, 28))],
         [["October", "2026"], ["Oct – Nov", "2026"], ["Wednesday, October 28", "2026"]]);
    t.eq("groups", [C.groupOf({ path: "/h/.local/share/vdirsyncer/calendars/icloud/home" }, [{ name: "icloud" }]), C.groupOf({ path: "/h/khal/personal" }, [{ name: "icloud" }])],
         ["icloud", ""]);
    // plain words: Wednesday 2026-10-28 is "now"
    const now = new Date(2026, 9, 28, 12, 0);
    const pn = (x) => { const r = C.parseNatural(x, "2026-10-28", now); return r.error ? r.error : [r.title, r.start, r.end, r.location]; };
    t.eq("plain: tomorrow at 1pm @ place", pn("Lunch with Sam tomorrow at 1pm @ Luigi's"), ["Lunch with Sam", "2026-10-29 13:00", "2026-10-29 14:00", "Luigi's"]);
    t.eq("plain: a weekday and a span", pn("Dentist fri 14:30-15:15"), ["Dentist", "2026-10-30 14:30", "2026-10-30 15:15", ""]);
    t.eq("plain: next monday at 9", pn("Review next monday at 9"), ["Review", "2026-11-09 09:00", "2026-11-09 10:00", ""]);
    t.eq("plain: a month day, all day", pn("Holiday nov 3"), ["Holiday", "2026-11-03", "2026-11-03", ""]);
    t.eq("plain: day month, past is next year", pn("Birthday 2 jan"), ["Birthday", "2027-01-02", "2027-01-02", ""]);
    t.eq("plain: in days, a length", pn("Call mum in 2 days at 6pm for 30 min"), ["Call mum", "2026-10-30 18:00", "2026-10-30 18:30", ""]);
    t.eq("plain: 2-4pm", pn("Workshop thu 2-4pm"), ["Workshop", "2026-10-29 14:00", "2026-10-29 16:00", ""]);
    t.eq("plain: the day in view", pn("Gym 18:00"), ["Gym", "2026-10-28 18:00", "2026-10-28 19:00", ""]);
    t.eq("plain: today is today", pn("Read today"), ["Read", "2026-10-28", "2026-10-28", ""]);
    t.eq("plain: only when", pn("tomorrow 9am"), "Say what it is, not only when");
    t.eq("plain: an ISO date", pn("Launch 2026-12-01 10:00"), ["Launch", "2026-12-01 10:00", "2026-12-01 11:00", ""]);
    t.eq("a draft at a slot", [C.draft("2026-11-02", 545, "x").start, C.draft("2026-11-02", 545, "x").end, C.draft("2026-11-02", -1).allDay],
         ["2026-11-02 09:00", "2026-11-02 10:00", true]);
  }
};

// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// CHRONOS' CALENDAR WINDOW (user, 2026-10-28) — a month, a week or a day
// of the same khal calendars the panel's agenda shows, events opened and
// written whole (repeats, alerts, notes), and online accounts (CalDAV,
// through vdirsyncer) set up in it. The panel stays the quick look; this
// is the calendar app.
//
// THIS IS THE PART THAT IS ALWAYS IN THE SHELL: the ipc handler, the
// .desktop entry, and what the window keeps between openings (its view,
// the calendars hidden). The window is compiled the first time it is
// opened and thrown away when it shuts. Events, reminders and syncing are
// Chronos' (the singleton), so they go on with it shut.
//
//   `qs ipc call Calendar open ""`         the window, on today
//   `qs ipc call Calendar day 2026-11-02`  on that day
//   `qs ipc call Calendar add ""`          a new event, today
//
// An Item loaded by shell.qml's Loader, as SunClock is, not a chronos/qmldir
// type: a type added to a qmldir is not seen by a live reload.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../morpheus"
import "../morpheus/lagnotes.js" as LagNotes
import "../morpheus/hypr.js" as Hypr
import "chronos.js" as Chr

Item {
  id: mgr
  visible: false

  // ── KEPT BETWEEN OPENINGS ──────────────────────────────────────────
  // { view: "month" | "week" | "day", hidden: [calendar names], side }
  property var settings: ({ view: "month", hidden: [], side: true })
  function set(key, value) {
    const s = Object.assign({}, mgr.settings);
    s[key] = value;
    mgr.settings = s;
    saveTimer.restart();
  }
  function parse(text) {
    let v = {};
    try { v = JSON.parse(text || "{}") || {}; } catch (e) { v = {}; }
    return {
      view: ["month", "week", "day"].indexOf(v.view) >= 0 ? v.view : "month",
      hidden: Array.isArray(v.hidden) ? v.hidden.filter((h) => typeof h === "string") : [],
      side: v.side !== false
    };
  }
  FileView {
    id: settingsFile
    path: Quickshell.statePath("chronos-calendar.json")
    blockLoading: true
    printErrors: false
    onLoaded: mgr.settings = mgr.parse(settingsFile.text())
  }
  Timer { id: saveTimer; interval: 400; onTriggered: settingsFile.setText(JSON.stringify(mgr.settings, null, 2) + "\n") }

  // ── ITS .desktop ENTRY ─────────────────────────────────────────────
  // The launcher's "Calendar"; it claims no file types.
  readonly property var launcher: Desktop.launcher("chronos", {
    Type: "Application",
    Name: "Calendar",
    GenericName: "Calendar",
    Comment: "Your calendars and events, in Zenworks",
    Icon: "x-office-calendar",
    Categories: ["Office", "Calendar"],
    Keywords: ["calendar", "events", "schedule", "agenda", "appointment", "meeting", "caldav", "khal", "chronos"],
    Exec: Desktop.execLine(Quickshell.shellDir + "/chronos/bin/chronos", ""),
    Terminal: "false",
    StartupNotify: "false"
  })

  // ── THE WINDOW ─────────────────────────────────────────────────────
  // Floating by its title (hypr/lua/windowdefaults.lua: "chronos").
  property var win: null
  LazyComponent {
    id: lazy
    source: Qt.resolvedUrl("CalendarWindow.qml")
    tag: "calendar"
  }
  function withWindow(fn) {
    lazy.withReady(() => {
      let fresh = false;
      if (!mgr.win) {
        const t0 = Date.now();
        mgr.win = lazy.comp.createObject(mgr, { mgr: mgr });
        LagNotes.mark("calendar window", t0);
        if (!mgr.win) return;
        fresh = true;
      }
      const was = !fresh && mgr.win.visible;
      fn(mgr.win);
      mgr.win.visible = true;
      mgr.win.refocus();
      if (was) Hyprland.dispatch(Hypr.focusTitle("chronos"));
    });
  }
  function retire(w) {
    if (mgr.win === w) mgr.win = null;
    if (!mgr.win && lazy.waiting.length === 0) lazy.comp = null;
  }

  function open() { mgr.withWindow(() => {}); }
  function day(iso) {
    const d = Chr.dateOf(iso);
    mgr.withWindow((w) => { if (d) w.goDay(d); });
  }
  // an event, opened in the window on its day (the panel's agenda)
  function event(e) { mgr.withWindow((w) => { w.goTo(e); w.open(e); }); }
  // the online accounts sheet (the panel's "Online account…")
  function accounts() { mgr.withWindow((w) => w.accounts()); }
  function add(iso) {
    const d = Chr.dateOf(iso) || new Date();
    mgr.withWindow((w) => w.create(Chr.isoOf(d), -1));
  }

  IpcHandler {
    target: "Calendar"
    function open(section: string): string { mgr.open(); return "ok"; }
    function day(iso: string): string { mgr.day(iso); return "ok"; }
    function add(iso: string): string { mgr.add(iso); return "ok"; }
  }
}

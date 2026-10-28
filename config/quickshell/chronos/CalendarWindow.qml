// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// CHRONOS' CALENDAR WINDOW (user, 2026-10-28): Apple Calendar's shape, to
// be refined — the toolbar (sidebar, +, Day · Week · Month · Year), the
// month in bold and its year beside it with ‹ Today › across from them,
// the calendars down the sidebar under the account they are from with a
// small month at its foot. A timed event in a month is a dot, its title
// and its time; an all-day one a filled bar. Events open with a click and
// are written whole in a sheet (when, repeats, an alert, where, notes);
// online accounts in another. The sidebar makes room for itself as
// stylus' does (terminus/SideRoom).
//
// Events are khal's, read for what is on screen (Chronos.listRange) and
// written by chronos/core/cal.py as .ics files, so khal, vdirsyncer and the
// panel's agenda all see them.
//
//   d w m y   day · week · month · year   t   today
//   ← →       back · on                    n   a new event
//   return    open the chosen event        delete  it, to the trash
//   ctrl z    undo (ctrl shift z: redo)    ctrl c / v / d  copy, paste, duplicate
//   ctrl f    search                       g   go to a date
//   r         sync the accounts            ctrl b  the sidebar
//   esc       the sheet, the search, the chosen event — never the window
//
// THE EVENTS IN HAND (user, 2026-10-28: "let me resize events, give them
// a context menu, let me change their colors … see what apple calendar can
// do"): dragged to another time or day (cal/EventBlock, cal/EventChip),
// resized by their foot, a right click's menu (open, duplicate, copy, its
// color, another calendar, delete), every change undone with ctrl z. A drag
// on empty hours makes an event that long; a double click, an hour's.
// Colors are the stickies' (Clio.ink, theme-adherent); an event's own over
// its calendar's. Clio's tasks due on a day are on it, and an event's
// notes are a Clio note (Notes in Clio). Calendars of your own are made,
// renamed, recolored and deleted from the sidebar.

import QtQuick
import Quickshell
import "../morpheus"
import "../morpheus/controls" as Ctl
import "../terminus"
import "../morpheus/undo"
import "../clio"
import "../clio/notes.js" as N
import "cal"
import "chronos.js" as Chr

FloatingWindow {
  id: cw
  title: "chronos"
  color: Zenon.alpha(Zenon.layerBg, 0)
  implicitWidth: 1200
  implicitHeight: 800
  minimumSize: Qt.size(820, 560)

  property var mgr: null

  onVisibleChanged: if (!cw.visible) Qt.callLater(() => { if (cw.mgr) cw.mgr.retire(cw); cw.destroy(); })
  onClosed: cw.visible = false
  function refocus() { Qt.callLater(() => keys.forceActiveFocus()); }
  Component.onCompleted: { Chronos.loadCalendars(); cw.reload(); }

  // terminus' bar height (user, 2026-10-28: "the top bar is too high")
  readonly property int headH: Zenon.toolbarH
  readonly property int sideW: 236
  readonly property var settings: cw.mgr ? cw.mgr.settings : ({ view: "month", hidden: [], side: true })
  readonly property bool sideOpen: cw.settings.side
  function setSidebar(on) { if (cw.mgr) cw.mgr.set("side", on); }
  readonly property string view: cw.settings.view
  function setView(v) { if (cw.mgr) cw.mgr.set("view", v); }

  function say(t, bad) { saidBox.say(t, bad); }

  // ── WHERE IT IS ────────────────────────────────────────────────────
  property var at: new Date()
  readonly property string todayIso: { cw.tick; return Chr.isoOf(new Date()); }
  // the minute, for the now line and today
  property int tick: 0
  Timer { interval: 60000; repeat: true; running: cw.visible; onTriggered: cw.tick++ }
  // today is on screen (the Today button rests)
  readonly property bool showsToday: { const r = Chr.rangeOf(cw.view, cw.at); return cw.todayIso >= r[0] && cw.todayIso < r[1]; }
  function step(n) { cw.at = Chr.stepDate(cw.view, cw.at, n); }
  function today() { cw.at = new Date(); }
  function goDay(d) { cw.at = d; cw.setView("day"); }
  onAtChanged: reloadTimer.restart()
  onViewChanged: reloadTimer.restart()

  // ── THE EVENTS ON SCREEN ───────────────────────────────────────────
  property var events: []
  property string error: ""
  Timer { id: reloadTimer; interval: 60; onTriggered: cw.reload() }
  function reload() {
    if (!Chronos.calReady) return;
    const r = Chr.rangeOf(cw.view, cw.at);
    Chronos.listRange(r[0], r[1], (j) => {
      if (j.error) { cw.error = j.error; return; }
      cw.error = "";
      cw.events = j.events || [];
    });
  }
  // Chronos re-reads after a sync, a save or an add in the panel: so does this
  Connections { target: Chronos; function onEventsChanged() { reloadTimer.restart(); } function onCalReadyChanged() { reloadTimer.restart(); } }
  readonly property var shown: cw.events.filter((e) => cw.settings.hidden.indexOf(e.calendar) < 0)
  // Clio's open checklist items with a due date, on their day beside the
  // events (as the panel's agenda has them): a click opens the note there
  readonly property var tasks: Clio.app ? N.tasks(Clio.app.notes, Date.now()).filter((t) => t.due > 0)
    .map((t) => ({ uid: "", title: t.h, date: Chr.isoOf(new Date(t.due)), start: "", allDay: true, task: t })) : []
  readonly property var byDay: Chr.eventsByDay(cw.shown.concat(cw.tasks))

  // ── THE CALENDARS ──────────────────────────────────────────────────
  function calIndex(name) { return Chronos.calendars.findIndex((c) => c.name === name); }
  // a hue (Clio's, the stickies') in the theme's ink, or a hex as it is
  function colorOf(hue) { return String(hue).charAt(0) === "#" ? hue : Clio.ink(hue); }
  function hueOf(name) {
    const i = cw.calIndex(name);
    return Chr.calColor(i >= 0 ? Chronos.calendars[i].color : "", Math.max(0, i));
  }
  function inkOf(name) { return cw.colorOf(cw.hueOf(name)); }
  // an event's own color, else its calendar's
  function evInk(ev) {
    if (!ev) return Zenon.cyan;
    return ev.color && Chr.isColor(ev.color) ? cw.colorOf(ev.color) : cw.inkOf(ev.calendar);
  }
  function titleOf(name) {
    const c = Chronos.calendars.find((x) => x.name === name);
    return c ? c.title : name;
  }
  function toggleCal(name) {
    const h = cw.settings.hidden.slice();
    const i = h.indexOf(name);
    if (i >= 0) h.splice(i, 1); else h.push(name);
    cw.mgr.set("hidden", h);
  }
  readonly property string firstShownCal: {
    const c = Chronos.calendars.find((x) => cw.settings.hidden.indexOf(x.name) < 0);
    return c ? c.name : (Chronos.calendars.length ? Chronos.calendars[0].name : "");
  }

  // ── AN EVENT, OPENED ───────────────────────────────────────────────
  function create(iso, mins) {
    if (!Chronos.calReady) { cw.say("Set up the calendar first", true); return; }
    sheet.edit(Chr.draft(iso, mins, cw.firstShownCal));
  }
  function open(e) {
    if (!e.uid) return;
    Chronos.getEvent(e.uid, (j) => {
      if (j.error) { cw.say(j.error, true); return; }
      sheet.edit(j);
    });
  }
  function openTask(item) { if (Clio.app && item && item.task) Clio.app.openTask(item.task.id, item.task.h); }
  // a span dragged out on empty hours: an event exactly that long
  function createSpan(iso, s, e) {
    if (!Chronos.calReady) return;
    const d = Chr.draft(iso, s, cw.firstShownCal);
    d.start = iso + " " + Chr.hhmm(s);
    d.end = iso + " " + Chr.hhmm(Math.min(e, 24 * 60 - 1));
    sheet.edit(d);
  }

  // ── THE CHOSEN EVENT ───────────────────────────────────────────────
  // one at a time, by its uid and the day it shows on (a repeat shows on
  // many): the keys act on it
  property var selected: null
  // what a right click's menu is about while it is open, for its ring
  // (terminus' HeldRing): "uid|date" of an event, or a calendar's name
  readonly property var heldKey: menu.isOpen ? menu.held : null
  function select(ev) { cw.selected = ev && ev.uid ? { uid: ev.uid, date: ev.date, ev: ev } : null; }
  function isSelected(ev) { return !!ev && !!cw.selected && cw.selected.uid === ev.uid && cw.selected.date === ev.date; }

  // ── CHANGES, UNDONE (morpheus UndoStack, as Clio's and Picasso's) ──
  // A step is what was done (Chr.inverse says what undoes it); undo applies
  // the inverse, redo the step again
  UndoStack { id: history; limit: 60 }
  property bool undoing: false
  function record(step) { if (!cw.undoing) history.record(step); }
  function apply(step, done) {
    const fin = (ok, words) => { cw.undoing = false; if (done) done(ok, words); };
    cw.undoing = true;
    if (step.kind === "shift") Chronos.shiftEvent(step.uid, step.ds, step.de, (j) => fin(!j.error, j.error));
    else if (step.kind === "save") Chronos.saveEvent(step.after, (j) => fin(!j.error, j.error));
    else if (step.kind === "delete")
      // kept whole first, so the redo that follows has all of it
      Chronos.getEvent(step.before.uid, (g) => {
        if (!g.error) Object.assign(step.before, g);
        Chronos.removeEvent(step.before.uid, (ok, words) => fin(ok, words));
      });
  }
  function undo() {
    if (!history.canUndo) { cw.say("Nothing to undo", true); return; }
    const step = history.past[history.past.length - 1];
    history.undo(step);
    cw.apply(Chr.inverse(step), (ok, words) => cw.say(ok ? "Undone" : words || "It could not be undone", !ok));
  }
  function redo() {
    if (!history.canRedo) { cw.say("Nothing to redo", true); return; }
    const step = history.future[history.future.length - 1];
    history.redo(step);
    cw.apply(step, (ok, words) => cw.say(ok ? "Done again" : words || "It could not be done again", !ok));
  }

  // ── MOVING, CHANGING, COPYING ──────────────────────────────────────
  // ds, de: minutes (days for an all-day event). A repeat moves whole —
  // said first. done(ok) puts a dragged block back when it did not move.
  function moveEvent(ev, ds, de, done) {
    const go = () => Chronos.shiftEvent(ev.uid, ds, de, (j) => {
      if (j.error) { cw.say(j.error, true); if (done) done(false); return; }
      cw.record({ kind: "shift", uid: ev.uid, ds: ds, de: de });
      if (done) done(true);
    });
    if (!ev.repeats) { go(); return; }
    cw.ask_({ question: "Move every time it repeats?", glyph: "\u{F0456}", ink: Zenon.cyan,
      detail: "“" + ev.title + "” repeats: moving it moves the whole series by the same amount.",
      choices: [{ label: "Move them all", ink: Zenon.cyan, run: go }, { label: "Cancel", run: () => { if (done) done(false); } }] });
  }
  // what changes a whole event (its color, its calendar): read, changed, saved
  function change(ev, fields, words) {
    Chronos.getEvent(ev.uid, (before) => {
      if (before.error) { cw.say(before.error, true); return; }
      const after = Object.assign({}, before, fields);
      Chronos.saveEvent(after, (j) => {
        if (j.error) { cw.say(j.error, true); return; }
        cw.record({ kind: "save", before: before, after: after });
        if (words) cw.say(words);
      });
    });
  }
  function setColor(ev, hue) { cw.change(ev, { color: hue }, hue === "" ? "Its calendar's color" : ""); }
  function moveToCalendar(ev, cal) { cw.change(ev, { calendar: cal }, "Moved to " + cw.titleOf(cal)); }
  function deleteEvent(ev) {
    if (!ev || !ev.uid) return;
    Chronos.getEvent(ev.uid, (before) => {
      Chronos.removeEvent(ev.uid, (ok, words) => {
        if (!ok) { cw.say(words, true); return; }
        if (!before.error) cw.record({ kind: "delete", before: before });
        if (cw.selected && cw.selected.uid === ev.uid) cw.selected = null;
        cw.say("“" + ev.title + "” deleted — ctrl z brings it back");
      });
    });
  }
  function duplicate(ev, days) {
    Chronos.copyEvent(ev.uid, days || 0, (j) => {
      if (j.error) { cw.say(j.error, true); return; }
      cw.record({ kind: "save", before: null, after: { uid: j.uid } });
      cw.say(days ? "Pasted" : "Duplicated");
    });
  }
  // copy and paste: onto the day the window is on
  property var clip: null
  function copyEv(ev) { if (ev && ev.uid) { cw.clip = ev; cw.say("Copied “" + ev.title + "”"); } }
  function paste(iso) {
    if (!cw.clip) { cw.say("Nothing copied", true); return; }
    cw.duplicate(cw.clip, Chr.daysBetween(cw.clip.date, iso || Chr.isoOf(cw.at)));
  }
  // its notes in Clio: the note it has, or a new one made from it
  function notesFor(ev) {
    if (!Clio.app) { cw.say("Clio is not running", true); return; }
    if (ev.note) { Clio.app.openTask(ev.note, ""); return; }
    const lines = [Chr.eventTime(Object.assign({ date: String(ev.start).slice(0, 10), endDate: String(ev.end).slice(0, 10),
                                                start: String(ev.start).slice(11, 16), end: String(ev.end).slice(11, 16) }, { allDay: ev.allDay }))
                   + "  ·  " + String(ev.start).slice(0, 10)]
      .concat(ev.location ? [ev.location] : []).concat(ev.description ? [ev.description] : []).concat([""]);
    Clio.app.noteFromText(ev.title, lines, "Calendar", false, (id) => {
      if (!ev.uid || !id) return;
      Chronos.getEvent(ev.uid, (g) => { if (!g.error) Chronos.saveEvent(Object.assign({}, g, { note: id }), () => {}); });
    });
  }

  // ── MENUS ──────────────────────────────────────────────────────────
  function ask_(c) {
    menuCard.c = c;
    menuCard.pick = 0;
    menuCard.shown = true;
  }
  function eventMenu(ev, item, x, y) {
    const p = item.mapToItem(stage, x, y);
    const hues = [{ text: cw.titleOf(ev.calendar) + "'s color", icon: "\u{F012F}", iconInk: cw.inkOf(ev.calendar), run: () => cw.setColor(ev, "") },
                  { isSeparator: true }]
      .concat(Chr.COLORS.map((c) => ({ text: c[1], icon: "\u{F012F}", iconInk: cw.colorOf(c[0]), run: () => cw.setColor(ev, c[0]) })));
    const cals = Chronos.calendars.filter((c) => c.name !== ev.calendar)
      .map((c) => ({ text: c.title, icon: "\u{F012F}", iconInk: cw.inkOf(c.name), run: () => cw.moveToCalendar(ev, c.name) }));
    menu.open(p.x, p.y, [
      { text: "Open", icon: "\u{EAB0}", mark: "return", run: () => cw.open(ev) },
      { text: "Notes in Clio", icon: "\u{F0219}", run: () => Chronos.getEvent(ev.uid, (g) => { if (!g.error) cw.notesFor(g); }) },
      { isSeparator: true },
      { text: "Duplicate", icon: "\u{F018F}", mark: "ctrl d", run: () => cw.duplicate(ev, 0) },
      { text: "Copy", icon: "\u{F018F}", mark: "ctrl c", run: () => cw.copyEv(ev) },
      { isSeparator: true },
      { text: "Color", icon: "\u{F03D8}", children: hues },
    ].concat(cals.length ? [{ text: "Move to", icon: "\u{EAB0}", children: cals }] : []).concat([
      { isSeparator: true },
      { text: "Delete", icon: "\u{F09E7}", danger: true, mark: "delete", run: () => cw.deleteEvent(ev) },
    ]), ev.uid + "|" + ev.date);
  }
  // the hours or a day with nothing under the pointer: a new event there
  function emptyMenu(iso, mins, item, x, y) {
    const p = item.mapToItem(stage, x, y);
    menu.open(p.x, p.y, [
      { text: mins >= 0 ? "New event at " + Chr.hhmm(mins) : "New event", icon: "\u{F0415}", mark: "n", run: () => cw.create(iso, mins) },
      { text: "New all-day event", icon: "\u{F00F3}", run: () => cw.create(iso, -1) },
    ].concat(cw.clip ? [{ isSeparator: true }, { text: "Paste “" + cw.clip.title + "”", icon: "\u{F0192}", mark: "ctrl v", run: () => cw.paste(iso) }] : []));
  }
  // a month's cell under a point of the window (a chip dragged over it)
  property string dropIso: ""
  function monthIsoAt(sx, sy) {
    const p = monthView.mapFromItem(null, sx, sy);
    const c = Math.floor(p.x / monthView.cellW), r = Math.floor((p.y - monthView.dayHeadH) / monthView.cellH);
    if (c < 0 || c > 6 || r < 0 || r > 5) return "";
    const cell = monthView.cells[r * 7 + c];
    return cell ? Chr.isoDay(cell.y, cell.m, cell.d) : "";
  }

  // ── CALENDARS OF YOUR OWN ──────────────────────────────────────────
  function isLocal(cal) { return Chr.groupOf(cal, Chronos.accounts) === ""; }
  function calMenu(cal, item, x, y) {
    const p = item.mapToItem(stage, x, y);
    menu.open(p.x, p.y, [
      { text: "Rename…", icon: "\u{F03EB}", run: () => cw.calForm(cal) },
      { text: "Color", icon: "\u{F03D8}", children: Chr.COLORS.map((c) => ({ text: c[1], icon: "\u{F012F}", iconInk: cw.colorOf(c[0]),
          run: () => Chronos.setCalendar(cal.name, cal.title, c[0], (j) => { if (j.error) cw.say(j.error, true); }) })) },
      { text: cw.settings.hidden.indexOf(cal.name) >= 0 ? "Show" : "Hide", icon: "\u{F0208}", run: () => cw.toggleCal(cal.name) },
      { isSeparator: true },
      { text: "New calendar…", icon: "\u{F0415}", run: () => cw.calForm(null) },
    ].concat(cw.isLocal(cal) ? [{ text: "Delete…", icon: "\u{F09E7}", danger: true, run: () => cw.ask_({
        question: "Delete “" + cal.title + "”?", glyph: "\u{F09E7}", ink: Zenon.red,
        detail: "It goes to the trash with every event in it — restore it from there if you change your mind.",
        choices: [{ label: "Delete", ink: Zenon.red, run: () => Chronos.deleteCalendar(cal.name, (j) => cw.say(j.error ? j.error : "Moved to the trash", !!j.error)) },
                  { label: "Cancel" }] }) }] : []), cal.name);
  }
  // a new calendar (cal null) or one renamed
  function calForm(cal) {
    calSheet.cal = cal;
    calName.text = cal ? cal.title : "";
    calSheet.hue = cal ? cw.hueOf(cal.name) : "blue";
    calSheet.shown = true;
    Qt.callLater(() => calName.claim());
  }

  // ── SEARCH ─────────────────────────────────────────────────────────
  property var results: null       // null: not searching
  property string searched: ""
  function search(text) {
    const t = String(text || "").trim();
    if (t.length < 2) { cw.results = null; return; }
    Chronos.searchEvents(t, (j) => {
      if (j.error) { cw.say(j.error, true); return; }
      cw.searched = t;
      cw.results = (j.events || []).filter((e) => cw.settings.hidden.indexOf(e.calendar) < 0);
    });
  }
  function endSearch() { cw.results = null; searchField.text = ""; cw.refocus(); }
  function goTo(e) {
    const d = Chr.dateOf(e.date);
    if (d) { cw.at = d; if (cw.view === "year") cw.setView("day"); }
    cw.results = null;
    Qt.callLater(() => { cw.select(e); cw.refocus(); });
  }

  function accounts() { accSheet.open(); }
  function sync() {
    if (Chronos.accounts.length === 0) { accSheet.open(); return; }
    cw.say("Syncing…", false);
    Chronos.syncNow((j) => cw.say(j && j.ok ? "Synced" : j && j.error ? j.error : "Not synced", !(j && j.ok)));
  }

  // ── KEYS ───────────────────────────────────────────────────────────
  Item {
    id: keys
    focus: true
    Keys.onPressed: (e) => {
      e.accepted = true;
      if (sheet.shown) { if (e.key === Qt.Key_Escape) sheet.close(); else e.accepted = false; return; }
      if (accSheet.shown) { if (e.key === Qt.Key_Escape) accSheet.shown = false; else e.accepted = false; return; }
      if (calSheet.shown) { if (e.key === Qt.Key_Escape) calSheet.shown = false; else e.accepted = false; return; }
      if (goSheet.shown) { if (e.key === Qt.Key_Escape) goSheet.shown = false; else e.accepted = false; return; }
      if (menuCard.shown) {
        if (e.key === Qt.Key_Escape) menuCard.answer(menuCard.c.choices.length - 1);
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) menuCard.answer(menuCard.pick);
        else if (e.key === Qt.Key_Left || e.key === Qt.Key_Right || e.key === Qt.Key_Tab)
          menuCard.pick = (menuCard.pick + 1) % menuCard.c.choices.length;
        return;
      }
      const ctrl = (e.modifiers & Qt.ControlModifier) !== 0, shift = (e.modifiers & Qt.ShiftModifier) !== 0;
      const sel = cw.selected ? cw.selected.ev : null;
      // esc lets go of what is in hand, never the window (user, 2026-10-28)
      if (e.key === Qt.Key_Escape) { if (cw.results !== null) cw.endSearch(); else if (cw.selected) cw.selected = null; return; }
      if (ctrl && e.key === Qt.Key_B) { cw.setSidebar(!cw.sideOpen); return; }
      if (ctrl && e.key === Qt.Key_Z) { if (shift) cw.redo(); else cw.undo(); return; }
      if (ctrl && e.key === Qt.Key_Y) { cw.redo(); return; }
      if (ctrl && e.key === Qt.Key_F) { searchField.claim(); return; }
      if (ctrl && e.key === Qt.Key_C) { if (sel) cw.copyEv(sel); return; }
      if (ctrl && e.key === Qt.Key_V) { cw.paste(Chr.isoOf(cw.at)); return; }
      if (ctrl && e.key === Qt.Key_D) { if (sel) cw.duplicate(sel, 0); return; }
      if (ctrl) { e.accepted = false; return; }
      if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && sel) { cw.open(sel); return; }
      if ((e.key === Qt.Key_Delete || e.key === Qt.Key_Backspace) && sel) { cw.deleteEvent(sel); return; }
      if (e.text === "g") { goField.text = Chr.isoOf(cw.at); goSheet.shown = true; Qt.callLater(() => goField.claim()); return; }
      if (e.key === Qt.Key_Left) { cw.step(-1); return; }
      if (e.key === Qt.Key_Right) { cw.step(1); return; }
      if (e.text === "t") cw.today();
      else if (e.text === "m") cw.setView("month");
      else if (e.text === "w") cw.setView("week");
      else if (e.text === "d") cw.setView("day");
      else if (e.text === "y") cw.setView("year");
      else if (e.text === "n") cw.create(Chr.isoOf(cw.at), cw.view === "month" ? -1 : 9 * 60);
      else if (e.text === "r") cw.sync();
      else e.accepted = false;
    }
  }

  // ── THE SIDEBAR MAKES ROOM FOR ITSELF ──────────────────────────────
  SideRoom {
    id: room
    window: cw
    anchor: keys
    shown: cw.sideOpen
    want: cw.sideW
    box: sideBox
    edge: "left"
  }

  Item {
    id: stage
    anchors.fill: parent
    // the window's ground, beside the sidebar
    Rectangle { z: -1; x: sideBox.width; width: parent.width - x; height: parent.height; color: Zenon.layerBg }

    // ── the sidebar, the window's whole height ──
    Item {
      id: sideBox
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      // while Hyprland resizes the window for it, the sidebar is whatever
      // the window has gained (SideRoom); otherwise it slides on its own
      width: room.keepW >= 0 ? Math.max(0, Math.min(cw.sideW, cw.width - room.keepW)) : cw.sideOpen ? cw.sideW : 0
      visible: width > 0
      Behavior on width {
        enabled: !room.following
        NumberAnimation { duration: Math.round(Zenon.normal * 1.4); easing.type: Zenon.travelEase }
      }
      clip: true
      z: 2
      SideGlass { edge: "right" }

      Flickable {
        id: sideList
        x: sideBox.width - cw.sideW
        y: 8
        width: cw.sideW
        height: miniBox.y - 8
        clip: true
        contentWidth: width
        contentHeight: calCol.implicitHeight + 16
        boundsBehavior: Flickable.StopAtBounds
        Column {
          id: calCol
          x: 12
          width: parent.width - 24
          // the calendars, under the account each is from: this computer's first
          Repeater {
            model: {
              const groups = [""].concat(Chronos.accounts.map((a) => a.name));
              return groups.map((g) => ({ name: g, cals: Chronos.calendars.filter((c) => Chr.groupOf(c, Chronos.accounts) === g) }))
                .filter((g) => g.cals.length > 0);
            }
            delegate: Column {
              id: grp
              required property var modelData
              required property int index
              width: calCol.width
              SideHead {
                first: grp.index === 0
                ruled: false
                width: parent.width
                label: grp.modelData.name === "" ? "On this computer" : grp.modelData.name
                // a calendar of your own, made here
                action: grp.modelData.name === ""
                onActed: cw.calForm(null)
              }
              Repeater {
                model: grp.modelData.cals
                delegate: Item {
                  id: crow
                  required property var modelData
                  width: grp.width
                  height: 28
                  Ctl.Check {
                    x: 4
                    anchors.verticalCenter: parent.verticalCenter
                    lit: cw.settings.hidden.indexOf(crow.modelData.name) < 0
                    ink: cw.inkOf(crow.modelData.name)
                    label: crow.modelData.title
                    textSize: Zenon.px(14)
                    onToggled: cw.toggleCal(crow.modelData.name)
                  }
                  // ringed while its menu is up (terminus' HeldRing)
                  HeldRing {
                    anchors.fill: parent
                    anchors.leftMargin: -2
                    anchors.rightMargin: 2
                    radius: Zenon.radiusControl
                    on: cw.heldKey === crow.modelData.name
                  }
                  // its menu: rename, color, show or hide, delete
                  TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: (pt) => cw.calMenu(crow.modelData, crow, pt.position.x, pt.position.y)
                  }
                }
              }
            }
          }
          Item { width: 1; height: 10 }
          DialogButton {
            x: 4
            label: Chronos.accounts.length ? "Accounts…" : "Add an account…"
            implicitHeight: 28
            ready: Chronos.calReady
            onClicked: accSheet.open()
          }
        }
      }
      ElasticScroll { anchors.fill: sideList; view: sideList }

      // a small month at the sidebar's foot, a day a click
      Item {
        id: miniBox
        x: sideBox.width - cw.sideW + 14
        width: cw.sideW - 28
        height: mini.implicitHeight + 20
        anchors.bottom: parent.bottom
        Rectangle { width: parent.width; height: 1; color: Zenon.border }
        // the panel's month, as the panel draws it (cal/MonthGrid)
        MonthGrid {
          id: mini
          y: 10
          width: parent.width
          win: cw
          // months on from the one the window is in, by its own arrows
          property int shift: 0
          month: new Date(cw.at.getFullYear(), cw.at.getMonth() + mini.shift, 1)
          selIso: Chr.isoOf(cw.at)
          marked: { const m = {}; for (const k in Chronos.byDay) m[k] = true; for (const k in cw.byDay) m[k] = true; return m; }
          onPicked: (d) => { cw.at = d; cw.refocus(); }
          onOpened: (d) => cw.goDay(d)
          onStepped: (n) => mini.shift = mini.shift + n
          Connections { target: cw; function onAtChanged() { mini.shift = 0; } }
        }
      }
    }

    // ── the toolbar ──
    Item {
      id: head
      z: 3
      anchors.left: sideBox.right
      anchors.right: parent.right
      height: cw.headH
      Rectangle { anchors.fill: parent; color: Zenon.headBg }
      Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Zenon.border }
      Row {
        x: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        DialogButton {
          implicitHeight: 30
          glyph: true
          // the sidebar shown or not, minerva's glyphs for the left side
          label: cw.sideOpen ? "\u{EC02}" : "\u{EBF3}"
          ink: cw.sideOpen ? Zenon.cyan : Zenon.muted
          onClicked: cw.setSidebar(!cw.sideOpen)
        }
        DialogButton {
          implicitHeight: 30
          glyph: true
          label: "\u{F0415}"
          ready: Chronos.calReady
          onClicked: cw.create(Chr.isoOf(cw.at), cw.view === "month" || cw.view === "year" ? -1 : 9 * 60)
        }
      }
      Segments {
        anchors.centerIn: parent
        options: [["day", "Day"], ["week", "Week"], ["month", "Month"], ["year", "Year"]]
        current: cw.view
        onChose: (v) => { cw.setView(v); cw.refocus(); }
      }
      Row {
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: !Chronos.calReady ? "" : Chronos.calBusy ? "Working…" : cw.error
          color: cw.error !== "" ? Zenon.yellow : Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(12)
        }
        DialogButton { glyph: true; label: "\u{F0E8E}"; implicitHeight: 30; visible: Chronos.accounts.length > 0; ready: !Chronos.calBusy; onClicked: cw.sync() }
        BulkField {
          id: searchField
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(240, Math.max(140, head.width * 0.22))
          visible: Chronos.calReady
          ghost: "Search"
          clearable: true
          onAccepted: cw.search(searchField.text)
          onCleared: cw.endSearch()
        }
      }
    }

    // ── the page ──
    // FROM THE WINDOW'S TOP, under the bar (user, 2026-10-28: "frost the
    // top bar, and the secondary top bar in day and week views"): what
    // scrolls — the hours, a year — rises under the day's bar, the title
    // and the top bar, frosted (morpheus/ScrollEdge, the whole stretch,
    // as hestia's: no bar, chromeTop 0)
    Item {
      id: page
      anchors.left: sideBox.right
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: foot.top
      clip: true

      ScrollEdge { z: 0; view: hours; follow: true; chromeTop: 0; visible: timeView.visible }
      ScrollEdge { z: 0; view: yearView; follow: true; chromeTop: 0; visible: yearView.visible }
      // the day's bar in a week or a day: the title, the days across, the
      // all-day row — one translucent ground, ruled at its foot
      Rectangle {
        id: subBar
        z: 1
        visible: timeView.visible
        y: cw.headH
        width: parent.width
        height: titleRow.height + timeView.headH + timeView.allDayH + 1
        color: Zenon.headBg
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Zenon.border }
      }

      // the month in bold, its year plain; back, today, on across from it
      Item {
        id: titleRow
        z: 2
        y: cw.headH
        visible: Chronos.calReady
        width: parent.width
        height: Chronos.calReady ? Zenon.px(26) + 24 : 0
        Text {
          x: 20
          anchors.verticalCenter: parent.verticalCenter
          readonly property var parts: Chr.titleParts(cw.view, cw.at)
          textFormat: Text.StyledText
          text: "<b>" + parts[0] + "</b>" + (parts[1] !== "" ? " " + parts[1] : "")
          color: Zenon.ink
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(26)
        }
        Row {
          anchors.right: parent.right
          anchors.rightMargin: 16
          anchors.verticalCenter: parent.verticalCenter
          spacing: 4
          DialogButton { glyph: true; label: "\u{F0141}"; implicitHeight: 28; onClicked: cw.step(-1) }
          // already there: nothing to go back to
          DialogButton { label: "Today"; implicitHeight: 28; ready: !cw.showsToday; onClicked: cw.today() }
          DialogButton { glyph: true; label: "\u{F0142}"; implicitHeight: 28; onClicked: cw.step(1) }
        }
      }

      // nothing set up: asked where the calendar lives first, and only
      // what that needs installed, then (user, 2026-10-28)
      Column {
        anchors.centerIn: parent
        width: 520
        spacing: 16
        visible: !Chronos.calReady
        EmptyState {
          width: parent.width
          text: "Where should your calendar live?"
        }
        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
          text: "On this computer, its events stay here" + (Chronos.calStatus.khal ? "." : " — khal is installed to keep them.")
            + " An online account (iCloud, Fastmail, Nextcloud or any CalDAV) is synced with your other devices"
            + (Chronos.calStatus.khal && Chronos.calStatus.vdirsyncer ? "." : " — what it needs is installed once you have given it.")
            + " Either can be added later."
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: 10
          DialogButton {
            label: "On this computer"
            ink: Zenon.cyan
            ready: !Chronos.calBusy
            onClicked: if (!Chronos.setupCalendar((ok) => cw.say(ok ? "Ready" : "Not set up", !ok))) cw.say("Ceres is busy — try again in a moment", true)
          }
          DialogButton {
            label: "Online account…"
            ink: Zenon.cyan
            ready: !Chronos.calBusy
            onClicked: accSheet.open()
          }
        }
      }

      // ── a month ──
      Item {
        id: monthView
        anchors.fill: parent
        anchors.topMargin: cw.headH + titleRow.height
        visible: Chronos.calReady && cw.view === "month"
        readonly property var cells: Chr.monthGrid(cw.at.getFullYear(), cw.at.getMonth())
        readonly property real dayHeadH: Zenon.px(12) + 14
        readonly property real cellW: width / 7
        readonly property real cellH: (height - dayHeadH) / 6
        readonly property real chipH: Zenon.px(12) + 7
        Row {
          Repeater {
            model: 7
            delegate: Text {
              required property int index
              width: monthView.cellW
              rightPadding: 10
              height: monthView.dayHeadH
              horizontalAlignment: Text.AlignRight
              verticalAlignment: Text.AlignVCenter
              text: Qt.locale().dayName((index + 1) % 7, Locale.ShortFormat)
              color: Zenon.accentMuted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(12)
            }
          }
        }
        Repeater {
          model: monthView.cells
          delegate: Item {
            id: cell
            required property var modelData
            required property int index
            readonly property string iso: Chr.isoDay(cell.modelData.y, cell.modelData.m, cell.modelData.d)
            readonly property var evs: cw.byDay[cell.iso] || []
            readonly property int fits: Math.max(0, Math.floor((cell.height - Zenon.px(13) - 14) / (monthView.chipH + 2)))
            readonly property bool more: cell.evs.length > cell.fits
            x: (cell.index % 7) * monthView.cellW
            y: monthView.dayHeadH + Math.floor(cell.index / 7) * monthView.cellH
            width: monthView.cellW
            height: monthView.cellH
            readonly property bool weekend: cell.index % 7 >= 5
            Rectangle { anchors.fill: parent; color: cw.dropIso === cell.iso ? Zenon.alpha(Zenon.cyan, 0.14)
              : !cell.modelData.cur ? Zenon.wash(0.03) : cell.weekend ? Zenon.wash(0.015) : "transparent" }
            Rectangle { width: parent.width; height: 1; color: Zenon.border; opacity: 0.6 }
            Rectangle { width: 1; height: parent.height; color: Zenon.border; opacity: 0.6; visible: cell.index % 7 !== 0 }
            MouseArea {
              anchors.fill: parent
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              onClicked: (m) => {
                cw.at = new Date(cell.modelData.y, cell.modelData.m, cell.modelData.d);
                cw.selected = null;
                if (m.button === Qt.RightButton) cw.emptyMenu(cell.iso, -1, cell, m.x, m.y);
                cw.refocus();
              }
              onDoubleClicked: (m) => { if (m.button === Qt.LeftButton) cw.create(cell.iso, -1); }
            }
            // the day's number; today's in the accent; a click opens the day
            Rectangle {
              x: parent.width - width - 6
              y: 5
              // a disc round today's number, as Apple's; a month's first
              // day says its month, and is never a disc
              readonly property bool disc: cell.iso === cw.todayIso && cell.modelData.d !== 1
              width: disc ? height : dayNum.implicitWidth + 10
              height: Zenon.px(13) + 10
              radius: disc ? width / 2 : Zenon.radiusControl
              color: cell.iso === cw.todayIso ? Zenon.cyan : "transparent"
              Text {
                id: dayNum
                anchors.centerIn: parent
                text: cell.modelData.d === 1 ? Chr.monthName(cell.modelData.m).slice(0, 3) + " 1" : cell.modelData.d
                color: cell.iso === cw.todayIso ? Zenon.onAccent : cell.modelData.cur ? Zenon.ink : Zenon.accentMuted
                font.family: Zenon.face
                font.weight: cell.iso === cw.todayIso ? Font.Bold : Zenon.weight
                font.pixelSize: Zenon.px(13)
              }
              MouseArea { anchors.fill: parent; onClicked: cw.goDay(new Date(cell.modelData.y, cell.modelData.m, cell.modelData.d)) }
            }
            Column {
              x: 4
              y: Zenon.px(13) + 14
              width: parent.width - 8
              spacing: 2
              Repeater {
                model: cell.evs.slice(0, cell.more ? Math.max(0, cell.fits - 1) : cell.fits)
                delegate: EventChip { required property var modelData; win: cw; ev: modelData; dot: !modelData.allDay; mode: "month"
                                      width: parent.width; height: monthView.chipH }
              }
              Text {
                visible: cell.more
                text: "+" + (cell.evs.length - Math.max(0, cell.fits - 1)) + " more"
                color: Zenon.accentMuted
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(12)
                MouseArea { anchors.fill: parent; onClicked: cw.goDay(new Date(cell.modelData.y, cell.modelData.m, cell.modelData.d)) }
              }
            }
          }
        }
      }

      // ── a year: twelve small months; a month's name opens it, a day its day ──
      Flickable {
        id: yearView
        anchors.fill: parent
        anchors.topMargin: cw.headH + titleRow.height
        visible: Chronos.calReady && cw.view === "year"
        contentWidth: width
        contentHeight: yearGrid.implicitHeight + 24
        boundsBehavior: Flickable.StopAtBounds
        interactive: false
        clip: true
        Grid {
          id: yearGrid
          x: 20
          columns: Math.max(2, Math.min(4, Math.floor((yearView.width - 40) / 230)))
          columnSpacing: 28
          rowSpacing: 22
          readonly property real cellW: (yearView.width - 40 - columnSpacing * (columns - 1)) / columns
          Repeater {
            model: 12
            delegate: Column {
              id: ym
              required property int index
              width: yearGrid.cellW
              spacing: 4
              Text {
                text: Chr.monthName(ym.index)
                color: cw.at.getFullYear() === new Date().getFullYear() && ym.index === new Date().getMonth() ? Zenon.cyan : Zenon.ink
                font.family: Zenon.face
                font.weight: Font.Bold
                font.pixelSize: Zenon.px(15)
                MouseArea { anchors.fill: parent; onClicked: { cw.at = new Date(cw.at.getFullYear(), ym.index, 1); cw.setView("month"); } }
              }
              // the sidebar's month, as the panel draws it (cal/MonthGrid)
              MonthGrid {
                width: parent.width
                win: cw
                header: false
                fixed: true
                month: new Date(cw.at.getFullYear(), ym.index, 1)
                selIso: ""
                marked: { const m = {}; for (const k in cw.byDay) m[k] = true; return m; }
                onPicked: (d) => cw.goDay(d)
                onOpened: (d) => cw.goDay(d)
              }
            }
          }
        }
      }
      ElasticScroll { anchors.fill: yearView; view: yearView; visible: yearView.visible }

      // ── a week, a day: the hours ──
      Item {
        id: timeView
        anchors.fill: parent
        anchors.topMargin: cw.headH + titleRow.height
        z: 2
        visible: Chronos.calReady && (cw.view === "week" || cw.view === "day")
        readonly property var days: {
          if (cw.view === "day") return [new Date(cw.at.getFullYear(), cw.at.getMonth(), cw.at.getDate())];
          const a = Chr.weekStart(cw.at);
          return [0, 1, 2, 3, 4, 5, 6].map((i) => Chr.addDays(a, i));
        }
        readonly property real gutter: 58
        readonly property real colW: (width - gutter - 10) / days.length
        readonly property real hourH: 48
        readonly property real headH: Zenon.px(15) + 22
        // the all-day row: as tall as the busiest day needs
        readonly property int allDayMost: Math.max(0, ...timeView.days.map((d) => (cw.byDay[Chr.isoOf(d)] || []).filter((e) => e.allDay).length))
        readonly property real allDayH: Math.max(1, timeView.allDayMost) * (Zenon.px(12) + 9) + 8

        // the days across the top
        Repeater {
          model: timeView.days
          delegate: Item {
            id: dh
            required property var modelData
            required property int index
            readonly property string iso: Chr.isoOf(dh.modelData)
            x: timeView.gutter + dh.index * timeView.colW
            width: timeView.colW
            height: timeView.headH
            Row {
              anchors.centerIn: parent
              spacing: 6
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Chr.dayShort(Chr.weekIndex(dh.modelData))
                color: Zenon.accentMuted
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(13)
              }
              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: height
                height: Zenon.px(15) + 12
                radius: width / 2
                color: dh.iso === cw.todayIso ? Zenon.cyan : "transparent"
                Text {
                  id: dnum
                  anchors.centerIn: parent
                  text: dh.modelData.getDate()
                  color: dh.iso === cw.todayIso ? Zenon.onAccent : Zenon.ink
                  font.family: Zenon.face
                  font.weight: Font.Bold
                  font.pixelSize: Zenon.px(15)
                }
              }
            }
            MouseArea { anchors.fill: parent; enabled: cw.view === "week"; onClicked: cw.goDay(dh.modelData) }
          }
        }
        // all day
        Item {
          id: allDay
          y: timeView.headH
          width: parent.width
          height: timeView.allDayH
          Text {
            x: timeView.gutter - implicitWidth - 10
            y: 6
            text: "all-day"
            color: Zenon.accentMuted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(11)
          }
          Repeater {
            model: timeView.days
            delegate: Column {
              id: ad
              required property var modelData
              required property int index
              x: timeView.gutter + ad.index * timeView.colW + 2
              y: 4
              width: timeView.colW - 4
              spacing: 2
              Repeater {
                model: (cw.byDay[Chr.isoOf(ad.modelData)] || []).filter((e) => e.allDay)
                delegate: EventChip { required property var modelData; win: cw; ev: modelData; mode: "row"
                                      colW: timeView.colW; days: timeView.days.length; dayIndex: ad.index
                                      width: ad.width; height: Zenon.px(12) + 7 }
              }
            }
          }
        }

        Flickable {
          id: hours
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: allDay.bottom
          anchors.topMargin: 1
          anchors.bottom: parent.bottom
          contentWidth: width
          contentHeight: timeView.hourH * 24 + 16
          boundsBehavior: Flickable.StopAtBounds
          interactive: false
          clip: true
          // where it is now (today in view), else the working day, to begin with
          function settle() {
            const n = new Date(), today = timeView.days.some((d) => Chr.isoOf(d) === cw.todayIso);
            const h = today ? Math.max(0, n.getHours() + n.getMinutes() / 60 - 2) : 7;
            hours.contentY = Math.max(0, Math.min(hours.contentHeight - hours.height, h * timeView.hourH));
          }
          Component.onCompleted: Qt.callLater(hours.settle)
          Connections { target: cw; function onViewChanged() { Qt.callLater(hours.settle); } }
          Item {
            width: hours.width
            height: hours.contentHeight
            Repeater {
              model: 24
              delegate: Item {
                required property int index
                y: 8 + index * timeView.hourH
                width: parent.width
                height: timeView.hourH
                Text {
                  x: timeView.gutter - implicitWidth - 10
                  y: -implicitHeight / 2
                  visible: index > 0
                  text: Chr.hhmm(index * 60)
                  color: Zenon.accentMuted
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(11)
                }
                Rectangle { x: timeView.gutter; width: parent.width - timeView.gutter; height: 1; color: Zenon.border; opacity: 0.6 }
              }
            }
            // the time now, in the gutter beside its line
            Rectangle {
              readonly property real mins: { cw.tick; const n = new Date(); return n.getHours() * 60 + n.getMinutes(); }
              visible: timeView.days.some((d) => Chr.isoOf(d) === cw.todayIso)
              x: timeView.gutter - width - 4
              y: 8 + mins / 60 * timeView.hourH - height / 2
              width: nowText.implicitWidth + 10
              height: nowText.implicitHeight + 4
              radius: Zenon.radiusControl
              color: Zenon.red
              z: 61
              Text {
                id: nowText
                anchors.centerIn: parent
                text: { cw.tick; return Chr.hhmm(new Date().getHours() * 60 + new Date().getMinutes()); }
                color: Zenon.onAccent
                font.family: Zenon.face
                font.weight: Font.Bold
                font.pixelSize: Zenon.px(11)
              }
            }
            Repeater {
              model: timeView.days
              delegate: Item {
                id: col
                required property var modelData
                required property int index
                readonly property string iso: Chr.isoOf(col.modelData)
                x: timeView.gutter + col.index * timeView.colW
                y: 8
                width: timeView.colW
                height: timeView.hourH * 24
                Rectangle { width: 1; height: parent.height; color: Zenon.border; opacity: 0.6 }
                Rectangle { anchors.fill: parent; z: -1; visible: Chr.weekIndex(col.modelData) >= 5 && col.iso !== cw.todayIso; color: Zenon.wash(0.015) }
                // today's column, faintly in the accent (Apple's)
                Rectangle { anchors.fill: parent; z: -1; visible: col.iso === cw.todayIso && cw.view === "week"; color: Zenon.alpha(Zenon.cyan, 0.05) }
                // empty hours: a drag makes an event that long, a double
                // click an hour's at the half hour, a right click the menu
                MouseArea {
                  id: drawMa
                  anchors.fill: parent
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  property int from: -1
                  property int to: -1
                  readonly property int at0: Math.min(drawMa.from, drawMa.to)
                  readonly property int at1: Math.max(drawMa.from, drawMa.to)
                  function snap(y) { return Math.max(0, Math.min(24 * 60, Chr.snapMinutes(y, timeView.hourH))); }
                  onPressed: (m) => {
                    cw.selected = null;
                    if (m.button === Qt.RightButton) { cw.emptyMenu(col.iso, Chr.snapMinutes(m.y, timeView.hourH, 30), col, m.x, m.y); return; }
                    drawMa.from = Math.floor(m.y / timeView.hourH * 4) * 15;
                    drawMa.to = drawMa.from;
                  }
                  onPositionChanged: (m) => { if (drawMa.from >= 0) drawMa.to = drawMa.snap(m.y); }
                  onReleased: (m) => {
                    if (drawMa.from >= 0 && drawMa.at1 - drawMa.at0 >= 15) cw.createSpan(col.iso, drawMa.at0, drawMa.at1);
                    drawMa.from = -1;
                    cw.refocus();
                  }
                  onCanceled: drawMa.from = -1
                  onDoubleClicked: (m) => { if (m.button === Qt.LeftButton) cw.create(col.iso, m.y / timeView.hourH * 60 - 15); }
                }
                // the span being drawn
                Rectangle {
                  visible: drawMa.from >= 0 && drawMa.at1 - drawMa.at0 >= 15
                  x: 2
                  y: drawMa.at0 / 60 * timeView.hourH
                  width: col.width - 4
                  height: (drawMa.at1 - drawMa.at0) / 60 * timeView.hourH
                  radius: Zenon.rad(1)
                  color: Zenon.alpha(cw.inkOf(cw.firstShownCal), 0.3)
                  border.width: 1
                  border.color: cw.inkOf(cw.firstShownCal)
                  Text {
                    x: 8; y: 3
                    text: "New event  " + Chr.hhmm(drawMa.at0) + " – " + Chr.hhmm(Math.min(drawMa.at1, 1439))
                    color: Zenon.ink
                    font.family: Zenon.face
                    font.weight: Font.DemiBold
                    font.pixelSize: Zenon.px(12)
                  }
                }
                Repeater {
                  model: Chr.layoutDay((cw.byDay[col.iso] || []).filter((e) => !e.task), col.iso)
                  delegate: EventBlock {
                    required property var modelData
                    win: cw
                    ev: modelData.ev
                    s: modelData.s
                    e: modelData.e
                    hourH: timeView.hourH
                    colW: timeView.colW
                    days: timeView.days.length
                    dayIndex: col.index
                    x: 2 + modelData.col * (col.width - 4) / modelData.cols
                    y: modelData.s / 60 * timeView.hourH + 1
                    width: (col.width - 4) / modelData.cols - 2
                    baseH: (modelData.e - modelData.s) / 60 * timeView.hourH - 2
                  }
                }
                // now
                Rectangle {
                  visible: col.iso === cw.todayIso
                  readonly property real mins: { cw.tick; const n = new Date(); return n.getHours() * 60 + n.getMinutes(); }
                  y: mins / 60 * timeView.hourH
                  width: parent.width
                  height: 2
                  color: Zenon.red
                  z: 60
                  Rectangle { x: -4; y: -3; width: 8; height: 8; radius: 4; color: Zenon.red }
                }
              }
            }
          }
        }
        ElasticScroll { anchors.fill: hours; view: hours }
        Scrollbar { z: 4; flick: hours; anchors.right: hours.right; anchors.top: hours.top; anchors.bottom: hours.bottom }
      }
    }

    // ── what a search found: a year back, two on; a click goes there ──
    Rectangle {
      id: found
      visible: cw.results !== null
      anchors.fill: page
      anchors.topMargin: cw.headH
      z: 5
      color: Zenon.layerBg
      Item {
        id: foundHead
        width: parent.width
        height: Zenon.px(18) + 28
        Text {
          x: 20
          anchors.verticalCenter: parent.verticalCenter
          text: !cw.results ? "" : cw.results.length === 0 ? "Nothing found for “" + cw.searched + "”"
            : cw.results.length + (cw.results.length === 1 ? " event" : " events") + " for “" + cw.searched + "”"
          color: Zenon.ink
          font.family: Zenon.face
          font.weight: Zenon.titleWeight
          font.pixelSize: Zenon.px(18)
        }
        DialogButton { anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                       label: "Done"; implicitHeight: 28; onClicked: cw.endSearch() }
      }
      ListView {
        id: foundList
        anchors.top: foundHead.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        model: cw.results || []
        boundsBehavior: Flickable.StopAtBounds
        section.property: "date"
        section.delegate: Text {
          required property string section
          x: 20
          topPadding: 12
          bottomPadding: 4
          text: { const d = Chr.dateOf(section); return d ? Chr.longDay(d) + " " + d.getFullYear() : section; }
          color: section === cw.todayIso ? Zenon.cyan : Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: Zenon.px(12)
        }
        delegate: Item {
          id: frow
          required property var modelData
          width: foundList.width
          height: Zenon.px(14) + 20
          Rectangle { anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; radius: Zenon.windowRadius
                      color: fma.containsMouse ? Zenon.wash(0.04) : "transparent" }
          Rectangle { x: 22; anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4; color: cw.evInk(frow.modelData) }
          Text {
            x: 40
            width: 110
            anchors.verticalCenter: parent.verticalCenter
            text: Chr.eventTime(frow.modelData)
            color: Zenon.accentMuted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(13)
          }
          Text {
            textFormat: Text.PlainText
            x: 156
            width: parent.width - 176
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: frow.modelData.title + (frow.modelData.location ? "  ·  " + frow.modelData.location : "")
            color: Zenon.ink
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(14)
          }
          MouseArea { id: fma; anchors.fill: parent; hoverEnabled: true; onClicked: cw.goTo(frow.modelData) }
        }
      }
      ElasticScroll { anchors.fill: foundList; view: foundList }
      Scrollbar { flick: foundList; anchors.right: foundList.right; anchors.top: foundList.top; anchors.bottom: foundList.bottom }
    }

    HintBar {
      id: foot
      z: 3
      anchors.bottom: parent.bottom
      anchors.left: sideBox.right
      anchors.right: parent.right
      rows: cw.selected ? [["return", "open"], ["delete", "delete"], ["ctrl d", "duplicate"], ["ctrl c", "copy"], ["ctrl z", "undo"], ["esc", "let go"]]
        : [["d w m y", "day · week · month · year"], ["← →", "back · on"], ["t", "today"], ["n", "new event"],
           ["drag", "move · make"], ["ctrl f", "search"], ["ctrl z", "undo"], ["ctrl b", "sidebar"]]
    }

    Ctl.Said {
      id: saidBox
      anchors.horizontalCenter: page.horizontalCenter
      anchors.bottom: foot.top
      anchors.bottomMargin: 18
      lasts: 2600
    }

    // ── an event ──
    InputShield { visible: sheet.shown; onClicked: sheet.close() }
    Sheet {
      id: sheet
      fromTop: cw.headH
      cardW: 620
      cardH: evCol.implicitHeight + 48
      // the form: { uid, calendar, title, allDay, start, end, location,
      // description, repeat, alert } — start and end "YYYY-MM-DD[ HH:MM]"
      property var e: null
      property bool busy: false
      property string why: ""
      property string colorTip: ""
      readonly property bool isNew: !sheet.e || !sheet.e.uid
      // the event as it was opened, for undo
      property var orig: null
      function edit(ev) {
        sheet.e = ev;
        sheet.orig = ev && ev.uid ? Object.assign({}, ev) : null;
        sheet.why = "";
        titleField.text = ev.title || "";
        startDate.text = String(ev.start).slice(0, 10);
        endDate.text = String(ev.end || ev.start).slice(0, 10);
        startTime.text = ev.allDay ? "" : String(ev.start).slice(11, 16);
        endTime.text = ev.allDay ? "" : String(ev.end).slice(11, 16);
        place.text = ev.location || "";
        link.text = ev.url || "";
        notes.text = ev.description || "";
        sheet.shown = true;
        Qt.callLater(() => titleField.claim());
      }
      function close() { sheet.shown = false; cw.refocus(); }
      function set(k, v) { const n = Object.assign({}, sheet.e); n[k] = v; sheet.e = n; }
      // the form as cal.py save takes it, or a reason it cannot be
      function gathered() {
        const sd = Chr.normDate(startDate.text), ed = Chr.normDate(endDate.text || startDate.text);
        if (!sd || !ed) return { why: "A date is YYYY-MM-DD" };
        const n = Object.assign({}, sheet.e, { title: titleField.text.trim(), location: place.text.trim(), description: notes.text.trim(),
                                               url: link.text.trim() });
        if (n.url !== "" && !/^(https?|mailto|tel):/.test(n.url)) n.url = "https://" + n.url;
        if (n.allDay) { n.start = sd; n.end = ed; }
        else {
          const st = Chr.normTime(startTime.text), et = Chr.normTime(endTime.text);
          if (!st || !et) return { why: "A time is like 9:30 or 21:00" };
          n.start = sd + " " + st;
          n.end = ed + " " + et;
        }
        if (n.end < n.start) return { why: "It ends before it starts" };
        if (n.title === "") return { why: "Give it a title" };
        return { e: n };
      }
      function save() {
        const g = sheet.gathered();
        if (g.why) { sheet.why = g.why; return; }
        sheet.busy = true;
        const was = sheet.orig;
        Chronos.saveEvent(g.e, (j) => {
          sheet.busy = false;
          if (!j || j.error) { sheet.why = j && j.error ? j.error : "Not saved"; return; }
          cw.record({ kind: "save", before: was, after: Object.assign({}, g.e, { uid: j.uid || g.e.uid }) });
          sheet.close();
          cw.say(j.warning ? j.warning : sheet.isNew ? "Added “" + g.e.title + "”" : "Saved", !!j.warning);
        });
      }
      function remove() {
        if (sheet.isNew) return;
        const ev = Object.assign({}, sheet.e);
        sheet.close();
        cw.deleteEvent(ev);
      }

      Column {
        id: evCol
        x: 24
        y: 24
        width: parent.width - 48
        spacing: 14

        BulkField {
          id: titleField
          width: parent.width
          textSize: 17
          ghost: sheet.isNew ? "Title — or “Lunch fri 1pm @ Luigi's”" : "Title"
          // a new event's title in plain words fills in its day, time and
          // place (Chr.parseNatural) on the first return; the next saves
          onAccepted: {
            if (sheet.isNew) {
              const q = Chr.parseNatural(titleField.text, startDate.text || Chr.isoOf(cw.at));
              if (!q.error && q.title !== titleField.text.trim()) {
                titleField.text = q.title;
                startDate.text = q.start.slice(0, 10);
                endDate.text = q.end.slice(0, 10);
                if (!q.allDay) { startTime.text = q.start.slice(11, 16); endTime.text = q.end.slice(11, 16); }
                if (q.location) place.text = q.location;
                sheet.set("allDay", q.allDay);
                return;
              }
            }
            sheet.save();
          }
        }
        Segments {
          width: parent.width
          visible: Chronos.calendars.length > 1
          options: Chronos.calendars.map((c) => [c.name, c.title])
          inks: { const o = {}; for (const c of Chronos.calendars) o[c.name] = cw.inkOf(c.name); return o; }
          current: sheet.e ? sheet.e.calendar : ""
          onChose: (v) => sheet.set("calendar", v)
        }
        Ctl.Check {
          label: "All day"
          lit: !!sheet.e && sheet.e.allDay
          onToggled: {
            const on = !sheet.e.allDay;
            sheet.set("allDay", on);
            if (!on && startTime.text === "") { startTime.text = "09:00"; endTime.text = "10:00"; }
          }
        }
        Grid {
          columns: 3
          columnSpacing: 12
          rowSpacing: 10
          verticalItemAlignment: Grid.AlignVCenter
          Text { text: "Starts"; width: 64; color: Zenon.ink; font.family: Zenon.face; font.weight: Zenon.weight; font.pixelSize: Zenon.px(14) }
          BulkField { id: startDate; width: 150; ghost: "YYYY-MM-DD"; onAccepted: sheet.save()
            onFocusedChanged: if (!focused && Chr.normDate(text) && (!Chr.normDate(endDate.text) || endDate.text < Chr.normDate(text))) endDate.text = Chr.normDate(text) }
          BulkField { id: startTime; width: 100; visible: !!sheet.e && !sheet.e.allDay; ghost: "9:30"; onAccepted: sheet.save()
            onFocusedChanged: {
              // the end keeps the length it had
              if (focused || !Chr.normTime(text)) return;
              const was = Chr.minutesOf(String(sheet.e.start).slice(11, 16)), len = Chr.minutesOf(Chr.normTime(endTime.text)) - was;
              const s = Chr.minutesOf(Chr.normTime(text));
              text = Chr.normTime(text);
              if (len > 0 && s + len < 24 * 60) endTime.text = Chr.hhmm(s + len);
              sheet.set("start", String(sheet.e.start).slice(0, 10) + " " + text);
            } }
          Text { text: "Ends"; width: 64; color: Zenon.ink; font.family: Zenon.face; font.weight: Zenon.weight; font.pixelSize: Zenon.px(14) }
          BulkField { id: endDate; width: 150; ghost: "YYYY-MM-DD"; onAccepted: sheet.save() }
          BulkField { id: endTime; width: 100; visible: !!sheet.e && !sheet.e.allDay; ghost: "10:30"; onAccepted: sheet.save()
            onFocusedChanged: if (!focused && Chr.normTime(text)) text = Chr.normTime(text) }
        }
        SectionLabel { text: "Repeat" }
        Segments {
          width: parent.width
          even: true
          options: [["", "Never"], ["daily", "Daily"], ["weekly", "Weekly"], ["monthly", "Monthly"], ["yearly", "Yearly"]]
            .concat(sheet.e && sheet.e.repeat === "custom" ? [["custom", "As it was"]] : [])
          current: sheet.e ? sheet.e.repeat : ""
          onChose: (v) => sheet.set("repeat", v)
        }
        SectionLabel { text: "Alert" }
        Segments {
          width: parent.width
          even: true
          options: [["none", "None"], ["0", "At the start"], ["5", "5 min"], ["15", "15 min"], ["60", "1 hour"], ["1440", "1 day"]]
          current: !sheet.e || sheet.e.alert === null || sheet.e.alert === undefined ? "none" : String(sheet.e.alert)
          onChose: (v) => sheet.set("alert", v === "none" ? null : Number(v))
        }
        // its color: its calendar's, or one of the stickies' own
        Row {
          spacing: 8
          Text { anchors.verticalCenter: parent.verticalCenter; width: 64; text: "Color"; color: Zenon.ink
                 font.family: Zenon.face; font.weight: Zenon.weight; font.pixelSize: Zenon.px(14) }
          Repeater {
            model: [["", "Its calendar's"]].concat(Chr.COLORS)
            delegate: Rectangle {
              id: sw
              required property var modelData
              readonly property bool on: !!sheet.e && (sheet.e.color || "") === sw.modelData[0]
              readonly property color ink: sw.modelData[0] === "" ? cw.inkOf(sheet.e ? sheet.e.calendar : "") : cw.colorOf(sw.modelData[0])
              width: 24
              height: 24
              radius: 12
              color: sw.ink
              border.width: sw.on ? 2 : 0
              border.color: Zenon.ink
              // its calendar's: a ring, not a disc
              Rectangle { visible: sw.modelData[0] === ""; anchors.centerIn: parent; width: 12; height: 12; radius: 6; color: Zenon.layerBg }
              MouseArea {
                anchors.fill: parent
                anchors.margins: -2
                hoverEnabled: true
                onClicked: sheet.set("color", sw.modelData[0])
                onContainsMouseChanged: if (containsMouse) sheet.colorTip = sw.modelData[1]; else if (sheet.colorTip === sw.modelData[1]) sheet.colorTip = ""
              }
            }
          }
          Text { anchors.verticalCenter: parent.verticalCenter; text: sheet.colorTip; color: Zenon.accentMuted
                 font.family: Zenon.face; font.weight: Zenon.weight; font.pixelSize: Zenon.px(12) }
        }
        BulkField { id: place; width: parent.width; ghost: "Where"; onAccepted: sheet.save() }
        BulkField { id: link; width: parent.width; ghost: "A link (a call, a page)"; onAccepted: sheet.save() }
        BulkField { id: notes; width: parent.width; ghost: "Notes"; onAccepted: sheet.save() }
        Text {
          width: parent.width
          visible: !!sheet.e && sheet.e.repeat !== "" && !sheet.isNew
          wrapMode: Text.WordWrap
          text: "A change is made to every time it repeats."
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
        Text {
          width: parent.width
          visible: sheet.why !== ""
          wrapMode: Text.WordWrap
          text: sheet.why
          color: Zenon.red
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
        Rectangle { width: parent.width; height: 1; color: Zenon.border }
        Item {
          width: parent.width
          height: 32
          Row {
            spacing: 8
            DialogButton {
              visible: !sheet.isNew
              label: "Delete"
              ink: Zenon.red
              ready: !sheet.busy
              onClicked: sheet.remove()
            }
            DialogButton {
              visible: !sheet.isNew
              label: "Duplicate"
              ready: !sheet.busy
              onClicked: { const ev = sheet.e; sheet.close(); cw.duplicate(ev, 0); }
            }
            // its notes, a Clio note: made from the event the first time
            DialogButton {
              visible: !!Clio.app
              label: sheet.e && sheet.e.note ? "Open its notes" : "Notes in Clio"
              ready: !sheet.busy
              onClicked: {
                const g = sheet.gathered();
                const ev = g.e || sheet.e;
                if (sheet.isNew) { sheet.why = "Add it first, then its notes"; return; }
                sheet.close();
                cw.notesFor(ev);
              }
            }
            DialogButton {
              visible: !!sheet.e && !!sheet.e.url
              label: "Open the link"
              onClicked: Strings.openLink(sheet.e.url)
            }
          }
          Row {
            anchors.right: parent.right
            spacing: 10
            DialogButton { label: "Cancel"; ink: Zenon.accentMuted; onClicked: sheet.close() }
            BusyButton { label: sheet.isNew ? "Add" : "Save"; primary: true; ink: Zenon.cyan; busy: sheet.busy; busyText: "Saving…"; onClicked: sheet.save() }
          }
        }
      }
    }

    // ── a question with several answers (a repeat moved, a calendar deleted) ──
    InputShield { visible: menuCard.shown; onClicked: menuCard.answer(menuCard.c.choices.length - 1) }
    Sheet {
      id: menuCard
      fromTop: cw.headH
      cardW: 480
      cardH: menuBody.implicitHeight
      property var c: ({ question: "", choices: [{ label: "OK" }] })
      property int pick: 0
      function answer(i) {
        menuCard.shown = false;
        const ch = menuCard.c.choices[i];
        if (ch && ch.run) ch.run();
        cw.refocus();
      }
      ConfirmBody {
        id: menuBody
        width: parent.width
        question: menuCard.c.question || ""
        glyph: menuCard.c.glyph || ""
        glyphInk: menuCard.c.ink || Zenon.cyan
        detail: menuCard.c.detail || ""
        choices: (menuCard.c.choices || []).map((x) => ({ label: x.label, ink: x.ink || Zenon.accentMuted }))
        pick: menuCard.pick
        onPicked: (i) => menuCard.pick = i
        onChose: (i) => menuCard.answer(i)
      }
    }

    // ── a calendar of your own: made, or renamed and recolored ──
    InputShield { visible: calSheet.shown; onClicked: calSheet.shown = false }
    Sheet {
      id: calSheet
      fromTop: cw.headH
      cardW: 520
      cardH: calCol2.implicitHeight + 48
      property var cal: null
      property string hue: "blue"
      function done() {
        const t = calName.text.trim();
        if (t === "") return;
        calSheet.shown = false;
        if (calSheet.cal) Chronos.setCalendar(calSheet.cal.name, t, calSheet.hue, (j) => cw.say(j.error ? j.error : "Saved", !!j.error));
        else Chronos.newCalendar(t, calSheet.hue, (j) => cw.say(j.error ? j.error : "“" + t + "” made, on this computer", !!j.error));
        cw.refocus();
      }
      Column {
        id: calCol2
        x: 24
        y: 24
        width: parent.width - 48
        spacing: 16
        Text {
          textFormat: Text.PlainText
          text: calSheet.cal ? "The calendar “" + calSheet.cal.title + "”" : "A new calendar"
          color: Zenon.ink
          font.family: Zenon.face
          font.weight: Zenon.titleWeight
          font.pixelSize: Zenon.px(18)
        }
        BulkField { id: calName; width: parent.width; textSize: 16; ghost: "Its name"; onAccepted: calSheet.done() }
        Row {
          spacing: 10
          Repeater {
            model: Chr.COLORS
            delegate: Rectangle {
              id: cs
              required property var modelData
              width: 28
              height: 28
              radius: 14
              color: cw.colorOf(cs.modelData[0])
              border.width: calSheet.hue === cs.modelData[0] ? 2 : 0
              border.color: Zenon.ink
              MouseArea { anchors.fill: parent; onClicked: calSheet.hue = cs.modelData[0] }
            }
          }
        }
        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          visible: !calSheet.cal
          text: "Kept on this computer, in Documents → Calendar → its name, one file an event."
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
        Rectangle { width: parent.width; height: 1; color: Zenon.border }
        Row {
          anchors.right: parent.right
          spacing: 10
          DialogButton { label: "Cancel"; ink: Zenon.accentMuted; onClicked: { calSheet.shown = false; cw.refocus(); } }
          DialogButton { label: calSheet.cal ? "Save" : "Make it"; primary: true; ink: Zenon.cyan; onClicked: calSheet.done() }
        }
      }
    }

    // ── go to a date (g) ──
    InputShield { visible: goSheet.shown; onClicked: goSheet.shown = false }
    Sheet {
      id: goSheet
      fromTop: cw.headH
      cardW: 420
      cardH: goCol.implicitHeight + 48
      function go() {
        const iso = Chr.normDate(goField.text);
        if (!iso) { goField.claim(); return; }
        goSheet.shown = false;
        cw.at = Chr.dateOf(iso);
        cw.refocus();
      }
      Column {
        id: goCol
        x: 24
        y: 24
        width: parent.width - 48
        spacing: 14
        Text { text: "Go to a date"; color: Zenon.ink; font.family: Zenon.face; font.weight: Zenon.titleWeight; font.pixelSize: Zenon.px(18) }
        BulkField { id: goField; width: parent.width; textSize: 16; ghost: "YYYY-MM-DD"; onAccepted: goSheet.go() }
      }
    }

    // ── online accounts ──
    InputShield { visible: accSheet.shown; onClicked: accSheet.shown = false }
    Sheet {
      id: accSheet
      fromTop: cw.headH
      cardW: 600
      cardH: accCol.implicitHeight + 48
      property bool busy: false
      property string why: ""
      property string kind: "icloud"
      // the account a first Remove asked about: the second click removes it
      // (its synced copies to the trash, its password out of the keyring)
      property string removing: ""
      // [id, name, server, where the password comes from]
      readonly property var kinds: [
        ["icloud", "iCloud", "https://caldav.icloud.com/", "An app-specific password, made at account.apple.com."],
        ["fastmail", "Fastmail", "https://caldav.fastmail.com/", "An app password, made in Fastmail's settings."],
        ["nextcloud", "Nextcloud", "https://", "The server's address ends /remote.php/dav — an app password works best."],
        ["other", "Other CalDAV", "https://", "The address your provider gives for CalDAV."]
      ]
      readonly property var row: accSheet.kinds.find((k) => k[0] === accSheet.kind) || accSheet.kinds[0]
      function open() {
        accSheet.why = "";
        accSheet.removing = "";
        accName.text = "";
        accUser.text = "";
        accPass.text = "";
        accSheet.pickKind("icloud");
        accSheet.shown = true;
      }
      function pickKind(k) {
        accSheet.kind = k;
        accUrl.text = accSheet.row[2];
        if (accName.text === "" || accSheet.kinds.some((r) => r[1] === accName.text)) accName.text = accSheet.row[1];
      }
      function add() {
        if (accUser.text.trim() === "" || accPass.text === "") { accSheet.why = "The user name and password are both needed"; return; }
        accSheet.busy = true;
        accSheet.why = "";
        const started = Chronos.addAccount(accName.text.trim(), accUrl.text.trim(), accUser.text.trim(), accPass.text, (j) => {
          accSheet.busy = false;
          if (!j || j.error) { accSheet.why = j && j.error ? j.error : "It was not added"; return; }
          accPass.text = "";
          accSheet.shown = false;
          cw.refocus();
          cw.say(j.warning ? "Added, but the first sync said: " + j.warning : "Added and synced", !!j.warning);
        });
        if (started === false) { accSheet.busy = false; accSheet.why = "Ceres is busy — try again in a moment"; }
      }
      Column {
        id: accCol
        x: 24
        y: 24
        width: parent.width - 48
        spacing: 14
        Text {
          text: "Online calendars"
          color: Zenon.ink
          font.family: Zenon.face
          font.weight: Zenon.titleWeight
          font.pixelSize: Zenon.px(18)
        }
        // the ones there
        Repeater {
          model: Chronos.accounts
          delegate: Item {
            id: arow
            required property var modelData
            width: accCol.width
            height: 34
            Column {
              anchors.verticalCenter: parent.verticalCenter
              Text { text: arow.modelData.name; color: Zenon.ink; font.family: Zenon.face; font.weight: Font.Bold; font.pixelSize: Zenon.px(14) }
              Text { text: arow.modelData.user + " · " + arow.modelData.url; color: Zenon.accentMuted; font.family: Zenon.face; font.weight: Zenon.weight; font.pixelSize: Zenon.px(12) }
            }
            DialogButton {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              label: accSheet.removing === arow.modelData.name ? "Remove it?" : "Remove"
              ink: Zenon.red
              primary: accSheet.removing === arow.modelData.name
              implicitHeight: 28
              ready: !accSheet.busy
              onClicked: {
                if (accSheet.removing !== arow.modelData.name) { accSheet.removing = arow.modelData.name; return; }
                accSheet.removing = "";
                Chronos.removeAccount(arow.modelData.name, () => cw.say("Removed — its copies are in the trash", false));
              }
            }
          }
        }
        Rectangle { width: parent.width; height: 1; color: Zenon.border; visible: Chronos.accounts.length > 0 }
        SectionLabel { text: "Add an account" }
        Segments {
          width: parent.width
          even: true
          options: accSheet.kinds.map((k) => [k[0], k[1]])
          current: accSheet.kind
          onChose: (v) => accSheet.pickKind(v)
        }
        BulkField { id: accName; width: parent.width; ghost: "Its name here" }
        BulkField { id: accUrl; width: parent.width; ghost: "https://"; mono: true }
        BulkField { id: accUser; width: parent.width; ghost: "User name or email" }
        BulkField { id: accPass; width: parent.width; ghost: "Password"; masked: true; onAccepted: accSheet.add() }
        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: accSheet.row[3] + " The password is kept in the keyring, never in a file."
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
        Text {
          width: parent.width
          visible: accSheet.why !== ""
          wrapMode: Text.WordWrap
          text: accSheet.why
          color: Zenon.red
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
        Rectangle { width: parent.width; height: 1; color: Zenon.border }
        Row {
          anchors.right: parent.right
          spacing: 10
          DialogButton { label: "Close"; ink: Zenon.accentMuted; onClicked: { accSheet.shown = false; cw.refocus(); } }
          BusyButton { label: "Add"; primary: true; ink: Zenon.cyan; busy: accSheet.busy; busyText: "Finding its calendars…"; onClicked: accSheet.add() }
        }
      }
    }
  }

  // a right click's menu: an event's, a calendar's, empty hours'
  PopMenu {
    id: menu
    anchors.fill: parent
    window: cw
    cardWidth: 260
    onClosed: cw.refocus()
  }
}

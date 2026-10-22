// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┘┴└─┘
// https://github.com/kbuckleys/
//
// CHRONOS — the pomodoro timers. A singleton because they have to keep
// counting whether or not the layer that shows them is open, and because the
// bar wants to know if anything is running without opening anything.
//
// One Timer drives all of them. N QML Timers would each fire on their own
// phase and drift apart from each other; one tick means every countdown is
// always reading from the same second.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../oracle"
import "../ceres"
import "../kairos"
import "chronos.js" as Chr

Singleton {
  id: root

  // [{ label, minutes, remaining, running }]
  property var timers: []

  readonly property int defaultMinutes: 25
  readonly property int maxTimers: 8

  readonly property bool anyRunning: {
    for (let i = 0; i < root.timers.length; ++i)
      if (root.timers[i].running) return true;
    return false;
  }

  // ── editing ──────────────────────────────────────────────────────────
  // Every mutation replaces the array rather than editing in place: QML does
  // not see a property change when the contents of a var array are poked, so
  // the grid would keep showing the old numbers.
  // What is on disk, as text. The countdown mutates this array once a second
  // and only label and minutes are persisted, so an unconditional save here
  // rewrote the state file every second a timer was running to store bytes
  // that had not changed. Compared instead, and written only when the
  // persisted shape actually moves.
  property string saved: ""

  function mutate(fn) {
    const next = root.timers.map((t) => ({
      label: t.label, minutes: t.minutes,
      remaining: t.remaining, running: t.running, endsAt: t.endsAt || 0
    }));
    fn(next);
    root.timers = next;
    const text = Chr.serialize(next);
    if (text !== root.saved) {
      root.saved = text;
      saveTimer.restart();
    }
  }

  // Whether a timer was added: at the cap nothing is, and a caller about to
  // act on "the one just added" must not act on the last existing one.
  function add(label, minutes) {
    if (root.timers.length >= root.maxTimers) return false;
    root.mutate((ts) => ts.push({
      label: label || ("Pomodoro " + (ts.length + 1)),
      minutes: minutes || root.defaultMinutes,
      remaining: 0,
      running: false
    }));
    return true;
  }

  function remove(i) {
    root.mutate((ts) => { if (i >= 0 && i < ts.length) ts.splice(i, 1); });
  }

  function bump(i, delta) {
    root.mutate((ts) => {
      const t = ts[i];
      if (!t) return;
      t.minutes = Math.max(1, Math.min(600, t.minutes + delta));
      // an idle timer follows its own length; a running one keeps counting
      // from where it is, so nudging the dial mid-session cannot rewind it
      if (!t.running) t.remaining = 0;
    });
  }

  function toggle(i) {
    root.mutate((ts) => {
      const t = ts[i];
      if (!t) return;
      if (t.running) {
        t.remaining = Math.max(0, Math.ceil((t.endsAt - Date.now()) / 1000));
        t.running = false;
        t.endsAt = 0;
        return;
      }
      if (t.remaining <= 0) t.remaining = t.minutes * 60;
      // when it will be done, by the WALL CLOCK — see the tick
      t.endsAt = Date.now() + t.remaining * 1000;
      t.running = true;
    });
  }

  function reset(i) {
    root.mutate((ts) => {
      const t = ts[i];
      if (!t) return;
      t.running = false;
      t.remaining = 0;
      t.endsAt = 0;
    });
  }

  function relabel(i, label) {
    root.mutate((ts) => { if (ts[i]) ts[i].label = label; });
  }

  // ── the tick ─────────────────────────────────────────────────────────
  Timer {
    interval: 1000
    repeat: true
    // only while something is actually counting; an idle shell should not be
    // rebuilding this array once a second forever
    running: root.anyRunning
    onTriggered: {
      const done = [];
      root.mutate((ts) => {
        for (let i = 0; i < ts.length; ++i) {
          const t = ts[i];
          if (!t.running) continue;
          // Read off the clock, not counted down by one. A Timer's second
          // is never quite a second, and it does not count at all while the
          // machine is asleep — a 25-minute timer across a suspend used to
          // resume where it left off rather than having run out.
          t.remaining = Math.max(0, Math.ceil((t.endsAt - Date.now()) / 1000));
          if (t.remaining <= 0) {
            t.remaining = 0;
            t.running = false;
            done.push({ label: t.label, minutes: t.minutes });
          }
        }
      });
      for (const t of done) root.fire(t);
    }
  }

  // Announced through notify-send rather than by reaching into howler
  // directly. It goes out over DBus and comes back in through the same server
  // every other application uses, so a finished timer is a notification in
  // the ordinary sense — it lands in the history and the bell counts it.
  //
  // Critical urgency, which howler's ported mako config gives a timeout of 0:
  // it stays on screen until dismissed, which is the whole point of a timer.
  // With screen time on, a timer of ten minutes or more also says what its
  // time went to (Kairos, from the last few hours it keeps tick by tick).
  function fire(t) {
    const went = Oracle.screenTime && t.minutes >= 10
      ? Kairos.summarySince(Date.now() - t.minutes * 60000) : "";
    Quickshell.execDetached([
      "notify-send", "-u", "critical", "-a", "chronos",
      t.label, t.minutes + " minute timer finished" + (went !== "" ? "\n" + went : "")
    ]);
  }

  // ── persistence ──────────────────────────────────────────────────────
  FileView {
    id: stateFile
    path: Quickshell.statePath("chronos.json")
    blockLoading: true
    printErrors: false
  }

  Timer {
    id: saveTimer
    interval: 400
    onTriggered: stateFile.setText(root.saved)
  }

  // No default timer. An empty list stays empty — the panel says "no timers,
  // n to add one", which is a better first impression than a pomodoro someone
  // else decided you wanted.

  // ── THE CALENDAR (khal; 2026-10-21) ────────────────────────────────────
  // Events are khal's (core/cal.py asks it), read for the month the panel
  // shows and for the next two days, which is what reminders need — so
  // reminders keep coming with the panel shut. An online calendar set up in
  // vdirsyncer is synced every Oracle.calSyncMins.
  readonly property string calCore: Quickshell.shellDir + "/chronos/core/cal.py"
  property var calStatus: ({ khal: false, config: false, calendars: [], vdirsyncer: false, synced: false })
  readonly property bool calReady: root.calStatus.khal && root.calStatus.config
  property var events: []           // the month in view, give or take a week
  property var soon: []             // today and the next two days, for reminders
  property string calError: ""
  property bool calBusy: false

  Component { id: calProcComp; Process {} }
  Component { id: calCollComp; StdioCollector { waitForEnd: true } }
  function calAsk(args, fn) {
    const p = calProcComp.createObject(root);
    const out = calCollComp.createObject(p);
    p.stdout = out;
    out.streamFinished.connect(() => {
      let j = null;
      try { j = JSON.parse(out.text); } catch (e) {}
      if (fn) fn(j || { error: "The calendar could not be read" });
      p.destroy();
    });
    p.command = ["python3", "-I", root.calCore].concat(args);
    p.running = true;
  }
  function calCheck(then) {
    root.calAsk(["status"], (j) => { if (!j.error) root.calStatus = j; if (then) then(); });
  }
  // the month in view: from a week before its first day to six weeks on
  property string rangeFrom: ""
  property string rangeTo: ""
  function loadMonth(y, m) {
    const from = new Date(y, m, 1 - 7), to = new Date(y, m, 1 + 49);
    root.rangeFrom = Chr.isoOf(from);
    root.rangeTo = Chr.isoOf(to);
    root.reloadEvents();
  }
  function reloadEvents() {
    if (!root.calReady) return;
    if (root.rangeFrom !== "")
      root.calAsk(["list", root.rangeFrom, root.rangeTo], (j) => {
        if (j.error) { root.calError = j.error; return; }
        root.calError = "";
        root.events = j.events || [];
      });
    const t = new Date();
    root.calAsk(["list", Chr.isoOf(t), Chr.isoOf(new Date(t.getFullYear(), t.getMonth(), t.getDate() + 3))], (j) => {
      if (!j.error) root.soon = j.events || [];
    });
  }
  readonly property var byDay: Chr.eventsByDay(root.events)

  // the panel's line → a new event on that day; done(ok, words)
  function addQuick(text, iso, done) {
    const q = Chr.parseQuick(text, iso);
    if (q.error) { if (done) done(false, q.error); return; }
    root.calBusy = true;
    root.calAsk(["new"].concat(Chr.newArgs(q, "")), (j) => {
      root.calBusy = false;
      if (done) done(!j.error, j.error ? j.error : "Added “" + q.title + "”");
      root.reloadEvents();
    });
  }
  function removeEvent(uid, done) {
    if (!uid) return;
    root.calAsk(["delete", uid], (j) => {
      if (done) done(!j.error, j.error ? j.error : "Removed");
      root.reloadEvents();
    });
  }
  // khal through Ceres, then a config with one local calendar; done(ok)
  function setupCalendar(done) {
    const finish = () => root.calAsk(["setup"], () => root.calCheck(() => { root.reloadEvents(); if (done) done(root.calReady); }));
    if (root.calStatus.khal) { finish(); return true; }
    return Ceres.install(["khal"], "for the calendar in Chronos", (ok) => { if (ok) finish(); else if (done) done(false); });
  }
  Timer {
    interval: Math.max(5, Oracle.calSyncMins) * 60000
    repeat: true
    running: root.calReady && root.calStatus.synced
    onTriggered: root.calAsk(["sync"], () => root.reloadEvents())
  }
  // the next days re-read every five minutes (an event added elsewhere)
  Timer { interval: 300000; repeat: true; running: root.calReady; onTriggered: root.reloadEvents() }

  // ── REMINDERS ──────────────────────────────────────────────────────────
  // Every half minute, what falls due since the last look: a critical
  // notification (it comes through Do not disturb and Focus), with Snooze
  // (ten minutes) and Done. Said once each — the keys live in the state
  // file beside the timers, so a restart does not say them again.
  property double remindLast: Date.now()
  property var fired: ({})
  property var snoozed: []          // [{ e, at }]
  Timer {
    interval: 30000
    repeat: true
    running: root.calReady && Oracle.calRemindLead >= 0
    onTriggered: {
      const now = Date.now();
      const due = Chr.remindersDue(root.soon, root.remindLast, now, Oracle.calRemindLead, root.fired);
      root.remindLast = now;
      const keep = [];
      for (const s of root.snoozed) { if (s.at <= now) due.push(s.e); else keep.push(s); }
      root.snoozed = keep;
      if (due.length === 0) return;
      const f = Object.assign({}, root.fired);
      for (const e of due) { f[Chr.remindKey(e)] = now; root.remind(e); }
      // a week of keys is plenty; older ones go
      for (const k in f) if (now - f[k] > 7 * 86400000) delete f[k];
      root.fired = f;
      remindSave.restart();
    }
  }
  function remind(e) {
    const p = remindProcComp.createObject(root, { ev: e });
    p.command = ["notify-send", "-u", "critical", "-a", "chronos", "-i", "x-office-calendar",
                 "-A", "snooze=Snooze 10 min", "-A", "done=Done",
                 "\u{F00F0}  " + e.title, Chr.remindWords(e, Date.now())];
    p.running = true;
  }
  Component {
    id: remindProcComp
    Process {
      id: rp
      property var ev: null
      stdout: StdioCollector {
        id: rpOut
        waitForEnd: true
        onStreamFinished: {
          if (rpOut.text.trim() === "snooze" && rp.ev)
            root.snoozed = root.snoozed.concat([{ e: rp.ev, at: Date.now() + 10 * 60000 }]);
          rp.destroy();
        }
      }
    }
  }
  FileView {
    id: remindFile
    path: Quickshell.statePath("chronos-reminded.json")
    blockLoading: true
    printErrors: false
  }
  Timer { id: remindSave; interval: 500; onTriggered: remindFile.setText(JSON.stringify(root.fired)) }

  Component.onCompleted: {
    root.timers = Chr.parse(stateFile.text());
    // seeded from what was just loaded, not from the file's own bytes: parse
    // normalizes, so the two can differ by whitespace and a first mutation
    // would otherwise always look like a change
    root.saved = Chr.serialize(root.timers);
    try { root.fired = JSON.parse(remindFile.text() || "{}") || {}; } catch (e) { root.fired = {}; }
    root.calCheck(() => { const t = new Date(); root.loadMonth(t.getFullYear(), t.getMonth()); });
  }
}

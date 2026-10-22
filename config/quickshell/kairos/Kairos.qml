// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// KAIROS — screen time. The time that counts, rather than the time that
// passes: how long each app had you, from Hyprland's focused window.
//
// Counted every few seconds into the focused window's app, and only while
// someone is there: not while the lock is up, not once idle for Oracle's
// screenTimeIdleMins (an idle inhibitor — a video playing — holds idle off,
// so watching counts), not with no window focused. Kept on this machine and
// nowhere else, a month a file in $XDG_DATA_HOME/kairos, written once a
// minute. Oracle's Time section turns it off.
//
// A Chronos timer that finishes says what its time went to
// (summarySince), the one place this reaches into another app's words.
//
// LIMITS AND BREAKS (2026-10-22). A daily limit per app, set in the
// window, said once a day by a notification when it is reached; and, with
// Oracle's screenBreaks, a reminder to look away after screenBreakMins at
// the screen without a break. Both through notify-send, so Howler's Focus
// holds them back like any other notification.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import "../morpheus"
import "../morpheus/icons.js" as Icons
import "../oracle"
import "kairos.js" as K

Singleton {
  id: root

  readonly property bool enabled: Oracle.screenTime
  // the lock, handed in by KairosManager (Cerberus belongs to shell.qml)
  property bool locked: false
  readonly property bool idle: idler.isIdle
  readonly property string dir: Paths.dataDir() + "/kairos"

  // { "2026-10": MONTH } — what has been read or counted this session
  property var months: ({})
  // bumped on every change, for bindings reading months
  property int revision: 0
  property var dirty: ({})
  // the last three hours, a tick at a time, for a timer's summary
  property var ticks: []

  // the app focused now ("" none). Hyprland's activewindow event carries
  // CLASS,TITLE (as LagWatch reads it); before the first one, and after a
  // reload, one `hyprctl activewindow -j` says what is focused.
  property string focusClass: ""
  property string focusTitle: ""
  readonly property string current: K.appKey(root.focusClass, root.focusTitle)
  Connections {
    target: Hyprland
    function onRawEvent(ev) {
      if (ev.name !== "activewindow") return;
      const d = String(ev.data);
      const cut = d.indexOf(",");
      root.focusClass = cut < 0 ? d : d.slice(0, cut);
      root.focusTitle = cut < 0 ? "" : d.slice(cut + 1);
    }
  }
  Process {
    running: true
    command: ["hyprctl", "activewindow", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.firstFocus(text)
    }
  }
  function firstFocus(text) {
    try {
      const j = JSON.parse(text);
      if (j && j.class !== undefined && root.focusClass === "") { root.focusClass = j.class || ""; root.focusTitle = j.title || ""; }
    } catch (e) {}
  }
  readonly property bool counting: root.enabled && !root.locked && !root.idle && root.current !== ""

  // ── COUNTING ──
  // Whatever happened since the last look goes to what was focused THEN:
  // looked at on every change of window (onCurrentChanged runs before the
  // new value is used) and every five seconds. A gap longer than a tick
  // and a half is a suspend or a stall, and only a tick of it counts.
  property real lastAt: Date.now()
  property string lastKey: ""
  property bool lastCounting: false
  function tick() {
    const now = Date.now();
    const secs = Math.min((now - root.lastAt) / 1000, 7.5);
    if (root.lastCounting && root.lastKey !== "" && secs > 0.2) {
      root.ensureMonth(K.monthKey(new Date(now)));
      const touched = K.addTime(root.months, root.lastKey, secs, new Date(now));
      for (const mk in touched) root.dirty[mk] = true;
      root.ticks = K.pushTick(root.ticks, now, root.lastKey, secs, 3 * 3600000);
      root.revision++;
    }
    // the stretch since the last break: idle and the lock end it
    if (root.counting) root.stretch += Math.max(0, secs);
    else if (root.locked || root.idle) root.stretch = 0;
    if (root.lastCounting && root.lastKey !== "") root.checkLimit(root.lastKey, new Date(now));
    if (Oracle.screenBreaks && K.breakDue(root.stretch, Oracle.screenBreakMins)) {
      root.stretch = 0;
      root.say("Time for a break", "You've been at the screen for " + K.limitWords(Oracle.screenBreakMins)
        + ". Look at something far away for 20 seconds.", "normal");
    }
    root.lastAt = now;
    root.lastKey = root.current;
    root.lastCounting = root.counting;
  }

  // ── LIMITS AND BREAKS ──
  property real stretch: 0
  property var limits: ({})
  property var told: ({ day: "", keys: {} })
  FileView { id: limitsFile; path: Quickshell.statePath("kairos.json"); blockLoading: true; printErrors: false }
  function saveLimits() {
    // FileView never re-reads its own setText: the state above is the truth
    limitsFile.setText(K.serializeLimits({ limits: root.limits, told: root.told }));
  }
  function setLimit(key, mins) {
    root.limits = K.withLimit(root.limits, key, mins);
    root.saveLimits();
    root.revision++;
  }
  function limitOf(key) { return root.limits[key] || 0; }
  function checkLimit(key, at) {
    const dk = K.dayKey(at);
    const d = K.dayOf(root.months, dk);
    const secs = d && d.apps[key] ? d.apps[key] : 0;
    if (!K.limitDue(root.limits, root.told, dk, key, secs)) return;
    root.told = K.markTold(root.told, dk, key);
    root.saveLimits();
    root.say("Your limit for " + root.nameOf(key), K.limitWords(root.limitOf(key))
      + " today, the limit you set in Screen Time.", "normal");
  }
  function say(title, body, urgency) {
    Quickshell.execDetached(["notify-send", "-u", urgency, "-a", "Screen Time", "-i", "preferences-system-time", title, body]);
  }
  onCurrentChanged: root.tick()
  onCountingChanged: root.tick()

  Timer { interval: 5000; repeat: true; running: root.enabled; onTriggered: root.tick() }
  Timer { interval: 60000; repeat: true; running: true; onTriggered: root.flush() }

  IdleMonitor {
    id: idler
    enabled: root.enabled
    timeout: Math.max(1, Oracle.screenTimeIdleMins) * 60
    respectInhibitors: true
  }

  // ── THE FILES ──
  function pathOf(mk) { return root.dir + "/" + mk + ".json"; }
  // blocking: text() right after the path is set answers that file (a
  // month is a few kilobytes)
  FileView { id: reader; blockLoading: true; printErrors: false }
  // a month into `months`, read once a session; a missing file is empty
  function ensureMonth(mk) {
    if (root.months[mk]) return root.months[mk];
    reader.path = root.pathOf(mk);
    const m = K.parseMonth(reader.text());
    root.months[mk] = m;
    return m;
  }
  // every month a span of days falls in, read, so the views can ask. Read
  // inside the asking binding, so the answer is already there: no revision
  // bump (one here, inside a binding on revision, was a binding loop).
  function ensureDays(from, to) {
    for (let d = from; d.getTime() <= to.getTime(); d = K.addDays(d, 1)) {
      const mk = K.monthKey(d);
      if (!root.months[mk]) root.ensureMonth(mk);
    }
  }

  AtomicWriter { id: writer; tag: "kairos-write" }
  Process { id: mkdir; running: true; command: ["mkdir", "-p", root.dir] }
  function flush() {
    for (const mk in root.dirty)
      if (root.months[mk]) writer.write(root.pathOf(mk), JSON.stringify(root.months[mk]));
    root.dirty = ({});
  }

  // every file gone, and what is in memory with it
  function forget() {
    root.months = ({});
    root.dirty = ({});
    root.ticks = [];
    root.revision++;
    Quickshell.execDetached(["sh", "-c", "rm -f \"$1\"/*.json", "kairos", root.dir]);
  }

  // ── ASKING ── (the views read `revision` in their own bindings)
  function day(key) { root.ensureDays(K.dateOf(key), K.dateOf(key)); return K.dayOf(root.months, key); }
  function week(end) { root.ensureDays(K.addDays(end, -6), end); return K.week(root.months, end); }
  function weekSum(end) { root.ensureDays(K.addDays(end, -6), end); return K.sumDays(root.months, K.addDays(end, -6), end); }
  // "Plato 14m, kitty 8m" for the time since `ms`; "" when nothing counted
  function summarySince(ms) {
    root.tick();
    return K.summaryLine(K.since(root.ticks, ms), root.nameOf);
  }

  // what a key is called: its .desktop Name, else its own words
  property var names: ({})
  function entryOf(key) {
    if (typeof DesktopEntries.heuristicLookup === "function") return DesktopEntries.heuristicLookup(key);
    return DesktopEntries.byId(key);
  }
  function nameOf(key) {
    if (key in root.names) return root.names[key];
    let n = K.isOwn(key) ? "" : ((root.entryOf(key) || {}).name || "");
    if (n === "") n = K.prettyKey(key);
    root.names[key] = n;
    return n;
  }
  function glyphOf(key) {
    return Icons.appGlyph([key, root.nameOf(key)]) || "󰗄";
  }

  Component.onCompleted: {
    const l = K.parseLimits(limitsFile.text());
    root.limits = l.limits;
    root.told = l.told;
  }
  Component.onDestruction: { root.tick(); root.flush(); }
}

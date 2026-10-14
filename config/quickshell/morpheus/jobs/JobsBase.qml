// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// JOBS, WITHOUT THE PROCESSES — the rows, their counts and how each one ends,
// in plain Qt Quick: what the drawer (JobsCard) and its glyph (terminus/
// JobsGlyph) read. Split out of the shell's Jobs singleton (2026-10-13), as
// ZenonBase was out of Zenon.
//
//   morpheus/Jobs.qml   = this + the processes it runs (rsync, archivers),
//                          their progress lines and the toast when one lands
//
// The rows are a ListModel, edited in place — see the note in Jobs.qml.

import QtQuick
import "../../terminus/terminus.js" as Terminus

QtObject {
  id: jobs

  property ListModel model: ListModel {}

  // Rows that ended badly / well and are still in the drawer, and how many
  // are actually running. Counts rather than searches, because a binding
  // cannot walk a ListModel and notice when it changes.
  property int faults: 0
  property int done: 0
  property int live: 0
  // Bumped once per event, read by the glow animations — a counter rather
  // than a signal so a Connections can watch each one.
  property int started: 0
  property int faulted: 0
  property int finished: 0

  // The live jobs' overall progress, 0..100, for the bar: the mean of what is
  // running, so three copies read as one number.
  readonly property int pct: {
    jobs.model.count;
    jobs.rev;
    let sum = 0, n = 0;
    for (let i = 0; i < jobs.model.count; ++i) {
      const j = jobs.model.get(i);
      if (j.state !== "running") continue;
      sum += j.pct;
      ++n;
    }
    return n === 0 ? 100 : Math.round(sum / n);
  }
  // Bumped on every progress line, because a binding cannot see a ListModel's
  // contents change — only its count.
  property int rev: 0

  // A job has ended. Every terminus window listens and re-reads whatever it
  // is showing; `dest` is where the job wrote.
  signal ended(int id, string op, int code, bool cancelled, string dest)
  // and with what the holder needs for its receipt: the names it made, and
  // when it started (ms) — the shell's Jobs toasts the long ones
  signal landed(int id, string op, var names, real startedAt, int code)
  // The first line of a job's stderr, for whichever window wants to say it.
  signal said(string text)

  // How one of the holder's own jobs is stopped — function(meta), the meta
  // its start wrote (the shell's: kill the process group).
  property var stopHook: null

  // What the drawer never draws, kept out of the model: a QObject does not
  // belong in a ListModel row. Written at start, read at exit, bound by
  // nothing — so a plain map.
  property var meta: ({})
  property int seq: 0

  // By id, never by position: a row can be removed while another job is
  // mid-flight, and an index held across that is pointing at the wrong job.
  function rowAt(id) {
    for (let i = 0; i < jobs.model.count; ++i)
      if (jobs.model.get(i).id === id) return i;
    return -1;
  }

  function update(id, patch) {
    const i = jobs.rowAt(id);
    if (i < 0) return;
    jobs.model.set(i, patch);
    jobs.rev++;
  }

  // A row, running: `names` are what it makes (one name: "<name> → <dir>");
  // `extra` lands in its meta (the shell's: its process). Its id.
  function begin(op, names, dest, extra) {
    const id = ++jobs.seq;
    jobs.live++;
    jobs.meta[id] = Object.assign({ names: names, dest: dest, started: Date.now() }, extra || {});
    jobs.model.append({
      id: id, op: op,
      what: names.length === 1 ? names[0] : names.length + " items",
      // where it is going, as its directory's name — the drawer says
      // "<thing> → <directory>", the way the Copy to / Move to header does
      to: dest ? (Terminus.basename(String(dest).replace(/\/+$/, "")) || "/") : "",
      pct: 0, index: 0, total: names.length,
      // entries counted rather than bytes measured, for the two ops whose
      // tools report no percentage of their own
      entries: 0, seen: 0, cancelled: false,
      rate: "", eta: "",
      // "running" until it ends; then "done", "failed" or "stopped"
      state: "running" });
    jobs.started++;
    return id;
  }

  function exited(id, code) {
    const i = jobs.rowAt(id);
    if (i < 0) return;
    const row = jobs.model.get(i);
    const op = row.op;
    const cancelled = row.cancelled;
    const m = jobs.meta[id] || { names: [], started: 0, dest: "" };
    // EVERY ENDED ROW STAYS until it has been read — a failure because it is
    // the news, a success because the drawer closing on it is the receipt
    // arriving and leaving in the same frame. See clearEnded.
    if (code !== 0) {
      jobs.model.set(i, { state: cancelled ? "stopped" : "failed", pct: 100 });
      jobs.faults++;
      jobs.faulted++;
    } else {
      jobs.model.set(i, { state: "done", pct: 100 });
      jobs.done++;
      jobs.finished++;
    }
    jobs.rev++;
    jobs.linger.restart();
    jobs.live = Math.max(0, jobs.live - 1);
    delete jobs.meta[id];
    jobs.landed(id, op, m.names || [], m.started || 0, code);
    jobs.ended(id, op, code, cancelled, m.dest || "");
  }

  function cancel(id) {
    const i = jobs.rowAt(id);
    if (i < 0) return;
    jobs.model.set(i, { cancelled: true });
    jobs.rev++;
    const m = jobs.meta[id];
    if (m && jobs.stopHook) jobs.stopHook(m);
  }

  function cancelAll() {
    // ids first: each cancel writes the model, and walking a model that is
    // being written is how you skip every second row
    const ids = [];
    for (let i = 0; i < jobs.model.count; ++i)
      if (jobs.model.get(i).state === "running") ids.push(jobs.model.get(i).id);
    for (const id of ids) jobs.cancel(id);
  }

  // One row put away by hand: stopped if it is running, dismissed if not.
  function dismiss(id) {
    const i = jobs.rowAt(id);
    if (i < 0) return;
    const st = jobs.model.get(i).state;
    if (st === "running") { jobs.cancel(id); return; }
    jobs.model.remove(i);
    if (st === "done") jobs.done = Math.max(0, jobs.done - 1);
    else jobs.faults = Math.max(0, jobs.faults - 1);
  }

  // Every row that has stopped, dropped — once the drawer has been read, or
  // by the timer for the case where nobody looked.
  function clearEnded() {
    if (jobs.faults === 0 && jobs.done === 0) return;
    for (let i = jobs.model.count - 1; i >= 0; --i)
      if (jobs.model.get(i).state !== "running") jobs.model.remove(i);
    jobs.faults = 0;
    jobs.done = 0;
    jobs.linger.stop();
  }

  // Long enough to notice from across the room, short enough that a failure
  // half an hour ago is not still shouting at you.
  readonly property Timer linger: Timer {
    interval: 12000
    onTriggered: jobs.clearEnded()
  }
}

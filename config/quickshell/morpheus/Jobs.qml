// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE JOBS — copies, moves, archives and extracts in flight — for the whole
// shell rather than for one window.
//
// They lived on the terminus window that started them, and the Processes were
// that window's children: retire a spare window with a copy running and the
// copy died with it, and close every window and there was nothing left to
// show what was still going on. Here they outlive every window. Any terminus
// window draws the drawer from this (JobsCard), and the bar carries a module
// for when no window is open at all (JobsModule).
//
// Terminus still BUILDS the commands — what rsync is told is a file manager's
// business — and hands the argv over. What happens after that is this file's:
// the process, the progress, cancelling, the receipt, the notification.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../terminus/terminus.js" as Terminus

Singleton {
  id: jobs

  // ── why a ListModel and not a list ────────────────────────────────────
  // A `property var` holding an array has to be REPLACED to be seen changing,
  // and a Repeater over a replaced array rebuilds every delegate. rsync
  // reports progress several times a second, so the drawer would have thrown
  // its rows away and built new ones at that rate. A ListModel is edited in
  // PLACE: set() touches the roles it is given and the delegate that is
  // already on screen simply re-reads them.
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
  // The first line of a job's stderr, for whichever window wants to say it.
  signal said(string text)

  // What the drawer never draws, kept out of the model: a QObject does not
  // belong in a ListModel row. Written at start, read at exit, bound by
  // nothing — so a plain map.
  property var meta: ({})
  property int seq: 0

  Component {
    id: runner

    Process {
      id: proc
      property int jobId: -1
      // A failed START never emits exited, and would leave a row running
      // forever — the same guard terminus' command runner carries.
      property bool sawExit: false
      onRunningChanged: {
        if (!proc.running && !proc.sawExit) jobs.exited(proc.jobId, -1);
      }

      // rsync rewrites its progress line with \r, so this is a stream of one
      // growing line rather than a sequence of them.
      stdout: SplitParser {
        splitMarker: "\r"
        onRead: (line) => jobs.line(proc.jobId, line)
      }
      stderr: StdioCollector {
        id: procErr
        waitForEnd: true
        onStreamFinished: {
          const e = String(procErr.text || "").trim();
          if (e !== "") jobs.said(e.split("\n")[0]);
        }
      }
      onExited: (code) => {
        proc.sawExit = true;
        jobs.exited(proc.jobId, code);
      }
    }
  }

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

  // `argv` is the whole command, setsid included — see terminus' startJob.
  function start(op, paths, dest, argv) {
    const id = ++jobs.seq;
    const proc = runner.createObject(jobs, { jobId: id });
    if (!proc) return -1;
    jobs.live++;
    proc.command = argv;
    const names = paths.map((p) => Terminus.basename(p));
    jobs.meta[id] = { proc: proc, names: names, dest: dest, started: Date.now() };
    jobs.model.append({
      id: id, op: op,
      what: names.length === 1 ? names[0] : names.length + " items",
      pct: 0, index: 0, total: paths.length,
      // entries counted rather than bytes measured, for the two ops whose
      // tools report no percentage of their own
      entries: 0, seen: 0, cancelled: false,
      rate: "", eta: "",
      // "running" until it ends; then "done", "failed" or "stopped"
      state: "running" });
    jobs.started++;
    proc.running = true;
    return id;
  }

  function line(id, text) {
    const i = jobs.rowAt(id);
    if (i < 0) return;
    const j = jobs.model.get(i);
    // an archive job counts entries; the percentage comes from the total it
    // announced before it started
    if (j.op === "archive" || j.op === "extract") {
      const rec = Terminus.parseArchiveProgress(text);
      if (!rec) return;
      const entries = rec.total !== undefined ? rec.total : j.entries;
      const seen = rec.at !== undefined ? rec.at : j.seen;
      const pct = entries > 0
        ? Math.max(0, Math.min(100, Math.round(seen * 100 / entries)))
        : (seen > 0 ? 100 : 0);
      // No speed to read off an archiver, so the time left is a guess from
      // the pace so far — the card shows it the way it shows rsync's.
      const m = jobs.meta[id];
      const eta = m ? Terminus.etaFrom(Date.now() - m.started, seen, entries) : "";
      jobs.update(id, { entries: entries, seen: seen, pct: pct, eta: eta });
      return;
    }
    // "Keep both" copies one item at a time and announces each one
    const item = Terminus.parseItem(text);
    if (item > 0) { jobs.update(id, { index: item, pct: 0 }); return; }
    const pct = Terminus.parseProgress(text);
    if (pct < 0) return;
    const r = Terminus.parseRate(text);
    jobs.update(id, r ? { pct: pct, rate: r.rate, eta: r.eta } : { pct: pct });
  }

  function exited(id, code) {
    const i = jobs.rowAt(id);
    if (i < 0) return;
    const row = jobs.model.get(i);
    const op = row.op;
    const cancelled = row.cancelled;
    const m = jobs.meta[id] || { names: [], started: 0, proc: null, dest: "" };
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
    linger.restart();
    jobs.live = Math.max(0, jobs.live - 1);
    delete jobs.meta[id];
    // Later: the stderr collector may still be closing, and destroying the
    // Process under it loses the one line that says what went wrong.
    if (m.proc) Qt.callLater(() => { if (m.proc) m.proc.destroy(); });
    // A toast only for a job long enough to have stopped watching — through
    // notify-send, so it lands in howler's history like any application's.
    if (code === 0 && Date.now() - (m.started || 0) > 3000)
      Quickshell.execDetached(["notify-send", "-a", "terminus",
        Terminus.jobSummary(op, m.names)]);
    jobs.ended(id, op, code, cancelled, m.dest || "");
  }

  // Kill the job's whole process group — the reason it runs under setsid.
  // execDetached, so two cancels in one breath cannot share a killer.
  function cancel(id) {
    const i = jobs.rowAt(id);
    if (i < 0) return;
    jobs.model.set(i, { cancelled: true });
    jobs.rev++;
    const m = jobs.meta[id];
    const pid = (m && m.proc) ? m.proc.processId : 0;
    if (pid > 0)
      Quickshell.execDetached(["sh", "-c", "kill -TERM -" + pid + " 2>/dev/null"]);
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
    linger.stop();
  }

  // Long enough to notice from across the room, short enough that a failure
  // half an hour ago is not still shouting at you.
  Timer {
    id: linger
    interval: 12000
    onTriggered: jobs.clearEnded()
  }
}

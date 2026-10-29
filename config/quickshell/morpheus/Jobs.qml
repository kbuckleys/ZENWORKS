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
// the process, the progress, canceling, the receipt, the notification.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../terminus/terminus.js" as Terminus
import "jobs"

// THE ROWS AND HOW THEY END are JobsBase's (morpheus/jobs, 2026-10-13) —
// plain Qt Quick. This adds what only the shell has: the processes, their
// progress lines, killing them, and the toast when a long one lands.
JobsBase {
  id: jobs

  // ── why a ListModel and not a list ────────────────────────────────────
  // A `property var` holding an array has to be REPLACED to be seen changing,
  // and a Repeater over a replaced array rebuilds every delegate. rsync
  // reports progress several times a second, so the drawer would have thrown
  // its rows away and built new ones at that rate. A ListModel is edited in
  // PLACE: set() touches the roles it is given and the delegate that is
  // already on screen simply re-reads them. (The model is JobsBase's.)

  // each job's Process, by id — destroyed once it has landed
  property var procs: ({})

  readonly property Component runner: Component {
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

  // `argv` is the whole command, setsid included — see terminus' startJob.
  function start(op, paths, dest, argv) {
    const proc = jobs.runner.createObject(jobs);
    if (!proc) return -1;
    const id = jobs.begin(op, paths.map((p) => Terminus.basename(p)), dest, { pid: () => proc.processId });
    proc.jobId = id;
    jobs.procs[id] = proc;
    proc.command = argv;
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
    if (r && jobs.meta[id]) { jobs.meta[id].bps = r.bps; jobs.meta[id].at = Date.now(); }
    jobs.update(id, r ? { pct: pct, rate: r.rate, eta: r.eta } : { pct: pct });
  }

  // ── HOW FAST, AS A GRAPH ──────────────────────────────────────────────
  // Each job's speed over time, by id, for the row's Sparkline in JobsCard —
  // the bar's performance tooltips' graph, in the same panel look, kept with
  // the same backend (Sysmon.pushRaw: Sysmon.span samples, trimmed from the
  // front). Raw figures, not levels: the card draws each against its own
  // peak, so the top of the well is "as fast as this job has gone" and the
  // peak in its corner is a real speed — a USB stick and an NVMe both use
  // the whole height.
  //
  // What moves bytes (copy, move, download) is graphed in bytes a second,
  // from rsync's own figure; an archive or an extract, which says no speed,
  // in entries a second, counted from its progress. Every job has a graph,
  // so the card needs no meter beside it.
  //
  // Sampled on a 1Hz clock rather than per progress line: the tools print
  // when they like, and a Sparkline spaces its points evenly. A job whose
  // rsync has gone quiet reads 0, not its last speed. Rows that have gone
  // keep no history: the map is rebuilt from the model.
  property var speeds: ({})
  readonly property Timer speedClock: Timer {
    interval: 1000
    repeat: true
    running: jobs.live > 0
    onTriggered: jobs.sampleSpeeds()
  }
  function sampleSpeeds() {
    const out = {};
    const now = Date.now();
    for (let i = 0; i < jobs.model.count; ++i) {
      const row = jobs.model.get(i);
      const had = jobs.speeds[row.id];
      const m = jobs.meta[row.id];
      if (row.state === "running" && !row.cancelled && m) {
        let v = 0;
        if (row.op === "archive" || row.op === "extract") {
          const dt = (now - (m.seenAt || m.started)) / 1000;
          v = dt > 0 ? Math.max(0, row.seen - (m.lastSeen || 0)) / dt : 0;
          m.lastSeen = row.seen;
          m.seenAt = now;
        } else if (m.bps !== undefined && now - m.at <= 2000) {
          v = m.bps;
        }
        out[row.id] = Sysmon.pushRaw(had || [], v);
      } else if (had) {
        out[row.id] = had;
      }
    }
    jobs.speeds = out;
  }

  // Kill the job's whole process group — the reason it runs under setsid.
  // execDetached, so two cancels in one breath cannot share a killer.
  stopHook: (m) => {
    const pid = m.pid ? m.pid() : 0;
    if (pid > 0)
      Quickshell.execDetached(["sh", "-c", "kill -TERM -" + pid + " 2>/dev/null"]);
  }

  onLanded: (id, op, names, startedAt, code) => {
    // Later: the stderr collector may still be closing, and destroying the
    // Process under it loses the one line that says what went wrong.
    const proc = jobs.procs[id];
    delete jobs.procs[id];
    if (proc) Qt.callLater(() => proc.destroy());
    // A toast only for a job long enough to have stopped watching — through
    // notify-send, so it lands in howler's history like any application's.
    if (code === 0 && Date.now() - (startedAt || 0) > 3000)
      Quickshell.execDetached(["notify-send", "-a", "terminus", Terminus.jobSummary(op, names)]);
  }
}

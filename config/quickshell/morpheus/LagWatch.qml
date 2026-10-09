// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE LAG, WRITTEN DOWN WHEN IT HAPPENS. Animation that stutters and then
// recovers on its own is gone by the time anyone looks, so this keeps a log
// of every hitch with what was true at that moment — ~/.cache/quickshell/
// lag.log, the last 400 lines:
//
//   11:42:07  stall 640ms x1 · bar 20fps · rss 1290MB · after open artemis
//
//   stall   the main thread was busy that long: a heavy binding pass, JS,
//           a garbage collection. Seen as a 100 ms timer firing late.
//   frames  gaps between the bar's frames inside a burst of animation —
//           frames dropped, wherever the time went (render thread, GPU,
//           compositor). Seen on frameSwapped, which only fires when the
//           bar draws anyway: nothing here asks for a single extra frame,
//           so watching cannot itself be the lag.
//   rss     the shell's memory, which grows with live reloads.
//   after   what happened in the seconds before a stall: a layer opening
//           or closing ("open artemis"), a window mapping ("window kitty"),
//           and how long any window built on demand took to construct
//           ("terminus window 640ms", from lagnotes.js). Most stalls turned
//           out to land on a window opening, and nothing said which.
//   in      the focused window at the time ("in alexandria"): a run of
//           stalls with nothing opening is work inside that window.
//
// NOT THE GPU. Asking nvidia-smi after a hitch was tried, and the asking
// stalled the driver for ~150 ms — a hitch that caused the next question.
// When the log shows frames lost and no stall, look at the GPU by hand
// (`nvidia-smi -q -d PERFORMANCE`) while it is happening.
//
// WHEN THE LOG IS NOT ENOUGH, profile: `scripts/restart.sh --debug <port>`
// and qmlprofiler, which names every binding, script and creation a stall is
// made of. It found the closed menus rebuilding on every cursor step and the
// big .js files evaluated once per importing instance (2026-10-09).
//
// Loaded by shell.qml through a Loader, with the bar's pill as `watch`.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "lagnotes.js" as LagNotes

Item {
  id: lag

  property Item watch: null
  // shell.qml's activeLayer, bound in from the Loader
  property string openLayer: ""
  readonly property var win: lag.watch ? lag.watch.Window.window : null

  // what was seen since the last line
  property int stalls: 0
  property real stallMax: 0
  property int gaps: 0
  property real gapMax: 0
  property var lines: []

  // ── the main thread ──────────────────────────────────────────────────
  property real tickAt: 0
  Timer {
    interval: 100
    repeat: true
    running: true
    onTriggered: {
      const now = Date.now();
      const late = lag.tickAt > 0 ? now - lag.tickAt - 100 : 0;
      lag.tickAt = now;
      if (late > 80) {
        if (lag.stalls === 0) lag.stallFrom = now - late;
        lag.stalls++;
        lag.stallMax = Math.max(lag.stallMax, late);
        flush.start();
      }
    }
  }

  // ── what came before ─────────────────────────────────────────────────
  // The last few seconds of things that open, so a stall line can say what
  // it followed. Only written out on a line with a stall in it.
  property real stallFrom: 0
  // the focused window, so a run of stalls with nothing opening says where
  // you were: most of them turned out to be work INSIDE a window
  property string focusedIn: ""
  // a reload starts this over, and activewindow only fires on the next
  // change: the title is all a toplevel is sure to carry until then
  Component.onCompleted: {
    const t = Hyprland.activeToplevel;
    if (t && t.title) lag.focusedIn = t.title;
  }
  property var recent: []
  function saw(text) {
    const now = Date.now();
    lag.recent = lag.recent.filter((e) => now - e.at < 5000).concat([{ at: now, text: text }]);
  }
  onOpenLayerChanged: lag.saw(lag.openLayer !== "" ? "open " + lag.openLayer : "close")
  Connections {
    target: Hyprland
    function onRawEvent(ev) {
      if (ev.name === "openwindow") {
        // ADDRESS,WORKSPACE,CLASS,TITLE — the class is enough to know it
        const parts = String(ev.data).split(",");
        lag.saw("window " + (parts[2] || "?"));
      } else if (ev.name === "activewindow") {
        // CLASS,TITLE — the shell's own windows are all org.quickshell, and
        // their titles (terminus, alexandria, plato, ceres…) say which
        const d = String(ev.data);
        const cut = d.indexOf(",");
        const cls = cut < 0 ? d : d.slice(0, cut);
        const title = cut < 0 ? "" : d.slice(cut + 1);
        lag.focusedIn = cls === "org.quickshell" ? (title || "shell") : cls;
      } else if (ev.name === "openlayer" && String(ev.data) !== "quickshell") {
        // the popups all share the default namespace; activeLayer names them
        lag.saw("layer " + ev.data);
      }
    }
  }

  // ── the frames ───────────────────────────────────────────────────────
  // A drop is a long gap INSIDE continuous drawing: fast frames before it
  // AND after it — the animation was running on both sides and frames went
  // missing in between. Fast-then-gap alone is an animation ending and the
  // bar's next unrelated redraw (a timer, a hover) coming a while later; the
  // bar's own quarter-second redraws are gap-then-gap. Both were logged as
  // drops by the first version. 25 ms is two frames lost at 100 Hz.
  //
  // AND UNDER 75 ms. A dropped frame is late by a frame or a few; the bar's
  // meters animate on every quarter-second sample and then sit idle, fast
  // frames either side — idle, not lost (the third false positive,
  // 2026-10-08). The cap was 100 against a ~150 ms idle, but a net sample
  // animating for Zenon.slow (170 ms) leaves 250 − 170 = 80 ms of idle, and
  // half of everything logged as dropped on 2026-10-09 sat at 80–99 ms. A real
  // hang that long is the main thread's, and the stall timer above has it.
  property real swapAt: 0
  property real lastDt: 1000
  property real held: 0      // a gap after fast frames, waiting on the next
  // frames the bar drew since the last line, for its rate — a bar that is
  // always drawing is a cost of its own, and says an animation never ends
  property int swaps: 0
  property real since: Date.now()
  Connections {
    target: lag.win
    ignoreUnknownSignals: true
    function onFrameSwapped() {
      const now = Date.now();
      const dt = now - lag.swapAt;
      lag.swapAt = now;
      lag.swaps++;
      if (lag.held > 0 && dt <= 25) {
        lag.gaps++;
        lag.gapMax = Math.max(lag.gapMax, lag.held);
        flush.start();
      }
      lag.held = lag.lastDt <= 25 && dt > 25 && dt < 75 ? dt : 0;
      lag.lastDt = dt;
    }
  }

  // ── reports that want a line of their own (lagnotes.js report) ──────
  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: if (LagNotes.lines && LagNotes.lines.length > 0 && !flush.running) flush.start()
  }

  // ── one line per burst ───────────────────────────────────────────────
  Timer {
    id: flush
    interval: 2000
    onTriggered: { statusFile.reload(); lag.write(); }
  }

  FileView {
    id: statusFile
    path: "/proc/self/status"
    blockLoading: true
    printErrors: false
  }

  function write() {
    const m = /VmRSS:\s+(\d+)/.exec(String(statusFile.text()));
    const parts = [];
    if (lag.stalls) parts.push("stall " + Math.round(lag.stallMax) + "ms x" + lag.stalls);
    if (lag.gaps) parts.push("frames " + Math.round(lag.gapMax) + "ms x" + lag.gaps);
    const secs = Math.max(0.001, (Date.now() - lag.since) / 1000);
    parts.push("bar " + Math.round(lag.swaps / secs) + "fps");
    lag.swaps = 0;
    lag.since = Date.now();
    if (m) parts.push("rss " + Math.round(Number(m[1]) / 1024) + "MB");
    // context only for a stall, from a little before it began
    const from = lag.stallFrom - 3000;
    const built = LagNotes.take(lag.stalls ? from : Date.now());
    if (lag.stalls) {
      const before = lag.recent.filter((e) => e.at >= from).map((e) => e.text);
      const all = before.concat(built);
      if (lag.focusedIn !== "") parts.push("in " + lag.focusedIn.slice(0, 40));
      if (all.length) parts.push("after " + all.join(", "));
    }
    const reports = typeof LagNotes.takeLines === "function" ? LagNotes.takeLines() : [];
    if (reports.length) parts.push(reports.join(" · "));
    lag.stalls = 0; lag.stallMax = 0; lag.gaps = 0; lag.gapMax = 0;
    const now = new Date();
    const stamp = Qt.formatDateTime(now, "yyyy-MM-dd hh:mm:ss");
    const next = lag.lines.concat([stamp + "  " + parts.join(" · ")]);
    lag.lines = next.length > 400 ? next.slice(next.length - 400) : next;
    logFile.setText(lag.lines.join("\n") + "\n");
  }

  FileView {
    id: logFile
    path: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/quickshell/lag.log"
    blockLoading: true
    printErrors: false
    // carry on from the last session's lines rather than starting over
    onLoaded: lag.lines = String(logFile.text()).split("\n").filter((l) => l !== "").slice(-400)
  }
}

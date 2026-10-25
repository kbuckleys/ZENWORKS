// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// HESTIA — keeper of the hearth: what keeps the house running in the
// background. The machine's services and your own, its timers, and the
// journal they all write to; a service started, stopped, restarted or set
// to start at boot from here.
//
// THIS IS THE PART THAT IS ALWAYS IN THE SHELL: the ipc handler and the
// .desktop entry. Everything Hestia knows it asks core/hestia.py for when
// the window wants it, and nothing runs while the window is shut.
//
// Doing something to a SYSTEM service is systemctl's own: polkit asks for
// the password (hyprpolkitagent shows it), so nothing here holds one. Your
// own (--user) services need none.
//
//   `qs ipc call Hestia open <section>`   overview · system · user ·
//                                         timers · journal
//   `qs ipc call Hestia unit <name>`      that service, in its section
//   `qs ipc call Hestia journal <unit>`   the journal, of that unit or all

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../morpheus"
import "../morpheus/lagnotes.js" as LagNotes
import "../morpheus/hypr.js" as Hypr
import "../ceres"
import "hestia.js" as H

Scope {
  id: mgr

  readonly property string core: Quickshell.shellDir + "/hestia/core/hestia.py"

  // ── ASKING core/hestia.py ──────────────────────────────────────────
  // one-off processes, made per ask and destroyed when answered;
  // fn(json | null)
  Component { id: procComp; Process {} }
  Component { id: collComp; StdioCollector { waitForEnd: true } }
  function ask(args, fn) {
    const p = procComp.createObject(mgr);
    const out = collComp.createObject(p);
    p.stdout = out;
    out.streamFinished.connect(() => {
      let j = null;
      try { j = JSON.parse(out.text); } catch (e) {}
      if (j && j.error) j = null;
      fn(j);
      p.destroy();
    });
    p.command = ["python3", "-I", mgr.core].concat(args);
    p.running = true;
  }

  // ── WHAT IS KNOWN ──────────────────────────────────────────────────
  property var system: []
  property var user: []
  property var timers: []
  property var bootInfo: null
  property bool loadingUnits: false
  function refresh() {
    mgr.loadingUnits = true;
    let left = 2;
    const done = () => { if (--left === 0) mgr.loadingUnits = false; };
    mgr.ask(["units", "system"], (j) => { if (j) mgr.system = j; done(); });
    mgr.ask(["units", "user"], (j) => { if (j) mgr.user = j; done(); });
  }
  function refreshTimers() {
    mgr.ask(["timers", "system"], (a) => mgr.ask(["timers", "user"], (b) => {
      mgr.timers = (a || []).concat(b || []).sort((x, y) => (x.next || 9e18) - (y.next || 9e18));
    }));
  }
  function refreshBoot() { mgr.ask(["boot"], (j) => { if (j) mgr.bootInfo = j; }); }
  function unitOf(scope, name) {
    return (scope === "user" ? mgr.user : mgr.system).find((u) => u.unit === name) || null;
  }

  // ── DOING ──────────────────────────────────────────────────────────
  // one at a time; done(ok, why)
  property string busy: ""           // "verb unit" while one runs
  signal acted(bool ok, string words)
  function act(scope, verb, unit) {
    if (actProc.running) return false;
    mgr.busy = verb + " " + unit;
    actProc.words = H.verbWords(verb, unit);
    actProc.scope = scope;
    actProc.command = H.actionArgs(scope, verb, unit);
    actProc.running = true;
    return true;
  }
  // ── NO ONE TO ASK FOR THE PASSWORD ──────────────────────────────────
  // polkit needs an agent to ask (hyprpolkitagent); with none running it
  // refuses at once, "Interactive authentication required". Then the
  // suite's own root path does it instead: Ceres' password card, one job.
  function viaCeres(argv, words) {
    mgr.busy = "ceres";
    const ok = Ceres.install([], words.charAt(0).toLowerCase() + words.slice(1) + " (as root)", (done) => {
      mgr.busy = "";
      mgr.acted(done, done ? actProc.words : "Not done");
      mgr.refresh();
    }, [["@sudo"].concat(argv)]);
    if (!ok) { mgr.busy = ""; mgr.acted(false, "Ceres is busy — try again once it is done"); }
  }
  Process {
    id: actProc
    property string words: ""
    property string scope: "system"
    stderr: StdioCollector { id: actErr; waitForEnd: true }
    onExited: (code) => {
      mgr.busy = "";
      const why = actErr.text.trim().split("\n").filter((l) => l !== "").pop() || "";
      if (code !== 0 && actProc.scope === "system" && /interactive authentication required/i.test(actErr.text)) {
        mgr.viaCeres(actProc.command, actProc.words);
        return;
      }
      // polkit's own "not authorized" is the password dialog dismissed
      if (code === 0) mgr.acted(true, actProc.words);
      else mgr.acted(false, /not authorized|authentication/i.test(why) ? "Not done — the password was not given"
        : (why !== "" ? why : "systemctl could not do that"));
      mgr.refresh();
    }
  }

  // ── ITS .desktop ENTRY ─────────────────────────────────────────────
  readonly property var launcher: Desktop.launcher("hestia", {
    Type: "Application",
    Name: "Hestia",
    GenericName: "Services and Logs",
    Comment: "Services, timers and the system journal, in Zenworks",
    Icon: "utilities-system-monitor",
    Categories: ["System", "Monitor"],
    Keywords: ["systemd", "service", "services", "daemon", "journal", "log", "logs", "timer", "boot", "systemctl", "journalctl"],
    Exec: Desktop.execLine(Quickshell.shellDir + "/hestia/bin/hestia", ""),
    Terminal: "false",
    StartupNotify: "false",
  })

  // ── THE WINDOW ─────────────────────────────────────────────────────
  // Floating by its title (hypr/lua/rules.lua: "hestia").
  property var win: null
  LazyComponent {
    id: lazy
    source: Qt.resolvedUrl("HestiaWindow.qml")
    tag: "hestia"
  }
  function withWindow(fn) {
    lazy.withReady(() => {
      let fresh = false;
      if (!mgr.win) {
        const t0 = Date.now();
        mgr.win = lazy.comp.createObject(mgr, { mgr: mgr });
        LagNotes.mark("hestia window", t0);
        if (!mgr.win) return;
        fresh = true;
      }
      const was = !fresh && mgr.win.visible;
      fn(mgr.win);
      mgr.win.visible = true;
      if (was) Hyprland.dispatch(Hypr.focusTitle("hestia"));
    });
  }
  function retire(w) {
    if (mgr.win === w) mgr.win = null;
    if (!mgr.win && lazy.waiting.length === 0) lazy.comp = null;
  }

  function open(section) { mgr.withWindow((w) => w.go(section || "")); }
  function showUnit(name) {
    const n = String(name || "").trim();
    const unit = n === "" ? "" : /\.\w+$/.test(n) ? n : n + ".service";
    mgr.withWindow((w) => w.showUnit(unit));
  }
  function journal(unit) { mgr.withWindow((w) => w.journalOf(String(unit || "").trim(), "")); }

  IpcHandler {
    target: "Hestia"
    function open(section: string): string { mgr.open(section); return "ok"; }
    function unit(name: string): string { mgr.showUnit(name); return "ok"; }
    function journal(unit: string): string { mgr.journal(unit); return "ok"; }
  }
}

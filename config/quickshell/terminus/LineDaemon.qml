// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE LINE TO A BACKEND — one process, JSON lines both ways (the other end
// is morpheus/py/lines.py). Delphi's git daemon and calypso's vault daemon
// are both reached through this.
//
//     LineDaemon {
//       id: line
//       name: "delphi"                        for the log
//       command: ["python3", ".../bin/delphid"]
//       protocol: 1                           refused if the daemon says another
//       goneText: "The git backend stopped"   what a request still out is told
//       onHeard: (ev) => …                    events tied to no request
//     }
//     line.request(op, { repo, args, … }, done(ok, result, err), event(ev)) → id
//     line.cancel(id)
//     line.hold(who) / line.release(who)    keep it up (an open window); with
//                                           nobody holding it, it goes after
//                                           `idle` ms with nothing in flight
//
// Started on the first request; requests made before it says "ready" wait
// and go the moment it does. A crash with someone still holding it brings it
// back, once a second at most.
//
// Lifted out of delphi/DelphiManager.qml (2026-10-11) when calypso wanted
// the same line.

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
  id: line

  property string name: "daemon"
  property var command: []
  property int protocol: 1
  property string goneText: "The backend stopped"
  property int idle: 60000

  property bool up: false
  property string broken: ""
  property var _out: []
  property var _pending: ({})
  property int _n: 0
  property var _users: ({})
  readonly property bool wanted: Object.keys(line._users).length > 0
  readonly property int inFlight: Object.keys(line._pending).length

  // an event tied to no request (not "ready", which is the line's own)
  signal heard(var ev)
  // it stopped — every request still out has already been told
  signal stopped(int code)

  Process {
    id: proc
    command: line.command
    stdinEnabled: true
    stdout: SplitParser {
      onRead: (l) => line.hear_(l)
    }
    stderr: SplitParser {
      onRead: (l) => console.warn(line.name + "d:", l)
    }
    onExited: (code) => {
      line.up = false;
      // every request still out fails now, not never
      const p = line._pending;
      line._pending = ({});
      // and what waited for "ready" goes with them: sent at the next start,
      // an op its caller was told had failed ran anyway (audit 2026-10-28d)
      line._out = [];
      for (const k in p) {
        try { if (p[k].done) p[k].done(false, null, { kind: "gone", error: line.goneText }); } catch (e) {}
      }
      line.stopped(code);
      if (code !== 0 && code !== 15 && line.wanted) {
        console.warn(line.name + ": backend exited", code);
        restartTimer.start();
      }
    }
  }
  Timer { id: restartTimer; interval: 1000; onTriggered: if (line.wanted) line.start_() }
  function start_() {
    if (proc.running) return;
    line.broken = "";
    proc.running = true;
  }
  function send_(msg) {
    if (!line.up) {
      line._out.push(msg);
      line.start_();
      return;
    }
    proc.write(JSON.stringify(msg) + "\n");
  }
  function hear_(l) {
    let m;
    try { m = JSON.parse(l); } catch (e) { console.warn(line.name + ": not JSON:", l); return; }
    if (m.id === undefined || m.id === null) {
      const ev = m.event || {};
      if (ev.ready) { line.ready_(ev); return; }
      line.heard(ev);
      return;
    }
    const p = line._pending[m.id];
    if (!p) return;
    if (m.event) {
      if (p.event) { try { p.event(m.event); } catch (e) { console.warn(line.name + ":", e); } }
      return;
    }
    delete line._pending[m.id];
    line._pendingChanged();
    if (p.done) {
      try { p.done(!!m.ok, m.ok ? m.result : null, m.ok ? null : m); }
      catch (e) { console.warn(line.name + ":", p.op, e); }
    }
  }
  function ready_(ev) {
    if (ev.protocol !== line.protocol) {
      line.broken = "The backend speaks protocol " + ev.protocol + ", this window " + line.protocol;
      console.warn(line.name + ":", line.broken);
      proc.running = false;
      return;
    }
    line.up = true;
    const q = line._out;
    line._out = [];
    for (const msg of q) proc.write(JSON.stringify(msg) + "\n");
  }

  function request(op, fields, done, event) {
    const id = ++line._n;
    line._pending[id] = { op: op, done: done || null, event: event || null };
    line._pendingChanged();
    line.send_(Object.assign({ id: id, op: op, args: {} }, fields || {}));
    if (!line.wanted) idleTimer.restart();
    return id;
  }
  function cancel(id) {
    if (!line._pending[id]) return;
    line.send_({ id: ++line._n, op: "cancel", args: { id: id } });
  }

  // ── WHO NEEDS IT ───────────────────────────────────────────────────
  function hold(who) {
    const u = Object.assign({}, line._users);
    u[who] = true;
    line._users = u;
    idleTimer.stop();
    line.start_();
  }
  function release(who) {
    const u = Object.assign({}, line._users);
    delete u[who];
    line._users = u;
    if (!line.wanted) idleTimer.restart();
  }
  // stopped now, whoever holds it (calypso's lock: what the daemon kept in
  // memory goes with it)
  function stop() {
    idleTimer.stop();
    line.up = false;
    proc.running = false;
  }
  Timer {
    id: idleTimer
    interval: line.idle
    onTriggered: {
      if (line.wanted || line.inFlight > 0) { idleTimer.restart(); return; }
      line.up = false;
      proc.running = false;
    }
  }
}

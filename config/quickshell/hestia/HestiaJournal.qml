// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Hestia's journal: everything the machine (or your session) has written,
// newest at the foot — by how serious (everything, notices, warnings,
// errors), by boot (this one, the one before, all), by unit, by words —
// and followed live while you watch.

import QtQuick
import Quickshell.Io
import "../morpheus"
import "../terminus"
import "hestia.js" as H

Item {
  id: jp

  property var mgr: null
  property var win: null

  property bool user: false
  property string prio: "4"
  property string boot: "0"
  property string unit: ""
  property string words: ""
  property bool following: true

  readonly property var filters: ({ user: jp.user, unit: jp.unit, prio: jp.prio, boot: jp.boot, grep: jp.words, n: 600 })

  // read again a beat after any filter moves (typing settles first)
  onFiltersChanged: reload.restart()
  Timer { id: reload; interval: 250; onTriggered: jp.load() }
  property int gen: 0
  function load() {
    if (!jp.mgr || !jp.visible) return;
    const g = ++jp.gen;
    log.loading = true;
    log.clear();
    jp.mgr.ask(["logs"].concat(H.logArgs(jp.filters)), (rows) => {
      if (g !== jp.gen) return;
      log.loading = false;
      log.setRows(rows || []);
      jp.follow(jp.following);
    });
  }
  // following only makes sense for this boot
  function follow(on) {
    jp.following = on;
    followProc.running = false;
    if (!on || !jp.visible || (jp.boot !== "0" && jp.boot !== "")) return;
    followProc.command = Paths.tether(H.logArgs(jp.filters, true));
    followProc.running = true;
  }
  Process {
    id: followProc
    stdout: SplitParser { splitMarker: "\n"; onRead: (line) => log.append(H.parseJournalLine(line)) }
  }
  Component.onDestruction: followProc.running = false
  onVisibleChanged: if (jp.visible) jp.load(); else followProc.running = false

  // a unit's journal, asked for from elsewhere
  function show(unitName, scope) {
    jp.user = scope === "user";
    jp.unit = unitName || "";
    unitField.text = jp.unit;
    jp.prio = "";
    jp.load();
  }

  // ── THE FILTERS ────────────────────────────────────────────────────────
  Column {
    id: bar
    z: 3
    x: 20
    y: 14
    width: parent.width - 40
    spacing: 10
    Row {
      spacing: 10
      Segments {
        options: [["system", "The machine"], ["user", "Your session"]]
        current: jp.user ? "user" : "system"
        onChose: (v) => jp.user = v === "user"
      }
      Segments {
        options: H.PRIOS.map((p) => [p.id === "" ? "all" : p.id, p.label])
        current: jp.prio === "" ? "all" : jp.prio
        inks: ({ "3": Zenon.red, "4": Zenon.yellow })
        onChose: (v) => jp.prio = v === "all" ? "" : v
      }
      Segments {
        options: H.BOOTS.map((b) => [b.id === "" ? "any" : b.id, b.label])
        current: jp.boot === "" ? "any" : jp.boot
        onChose: (v) => jp.boot = v === "any" ? "" : v
      }
    }
    Row {
      spacing: 10
      width: parent.width
      // the unit, and the words: terminus' shared field
      BulkField {
        id: unitField
        width: 260
        height: 32
        ghost: "Any service"
        clearable: true
        // the name settles before it is asked for: a service half typed is none
        onTextChanged: unitSettle.restart()
        onAccepted: if (jp.win) jp.win.refocus()
      }
      BulkField {
        id: wordsField
        width: Math.max(200, bar.width - 260 - 10 - followBtn.width - 20)
        height: 32
        ghost: "Words in the message"
        clearable: true
        onTextChanged: wordsSettle.restart()
        onAccepted: if (jp.win) jp.win.refocus()
      }
      DialogButton {
        id: followBtn
        implicitHeight: 32
        label: jp.following ? "Following" : "Follow"
        ink: jp.following ? Zenon.cyan : Zenon.muted
        ready: jp.boot === "0" || jp.boot === ""
        onClicked: jp.follow(!jp.following)
      }
    }
  }
  Timer { id: unitSettle; interval: 500; onTriggered: { const t = unitField.text.trim(); jp.unit = t === "" ? "" : /\.\w+$/.test(t) ? t : t + ".service"; } }
  Timer { id: wordsSettle; interval: 500; onTriggered: jp.words = wordsField.text.trim() }

  // ── THE BAR OVER THE LOG ───────────────────────────────────────────────
  // The lines run up under the filters and the window's head, frosted, and
  // down under the hints (morpheus/ScrollEdge); the filters' ground is the
  // head's, translucent, so it is one bar with the head.
  //
  // NOT `bar: head` (user's frost bug, 2026-10-21): ScrollEdge paints SHARP
  // rows into the gap between its bar and the view, and that gap was these
  // filters — the lines ran over them. From the head's top with no bar, the
  // whole stretch is frost (the scroll-edge rule ceres' colBar taught).
  ScrollEdge { view: log.view; follow: true; chromeTop: jp.win ? -jp.win.headH : 0; z: 1 }
  ScrollEdge { view: log.view; below: true; follow: true; bar: jp.win ? jp.win.footItem : null; z: 1 }
  Rectangle { id: chrome; z: 2; width: parent.width; height: log.y; color: Zenon.headBg }
  HestiaLog {
    id: log
    anchors.top: bar.bottom
    anchors.topMargin: 14
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    emptyText: "Nothing matches these filters"
  }
  readonly property int count: log.count
}

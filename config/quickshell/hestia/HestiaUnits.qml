// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Hestia's services — the machine's, or your own: the list on the left
// (running, failed, starting at boot, or all; typing filters it), and the
// one chosen on the right — what it is, what it is doing, the buttons that
// start, stop, restart or set it to start at boot, and its own journal,
// followed live.

import QtQuick
import Quickshell.Io
import "../morpheus"
import "../terminus"
import "../hermes"
import "hestia.js" as H

Item {
  id: pg

  property var mgr: null
  property var win: null
  property string scope: "system"

  property string query: ""
  property string chip: "running"
  property string current: ""
  property int sel: 0
  property bool listFocus: false

  readonly property var all: pg.mgr ? (pg.scope === "user" ? pg.mgr.user : pg.mgr.system) : []
  readonly property var shown: H.sortUnits(H.filterUnits(pg.all, pg.query, pg.chip))
  readonly property var counts: H.counts(pg.all)
  readonly property var unit: pg.all.find((u) => u.unit === pg.current) || null
  property var facts: null

  function choose(name) {
    if (name === pg.current) return;
    pg.current = name;
    pg.facts = null;
    log.clear();
    if (name === "") return;
    pg.mgr.ask(["show", pg.scope, name], (j) => { if (pg.current === name) pg.facts = j; });
    log.loading = true;
    pg.mgr.ask(["logs"].concat(H.logArgs({ user: pg.scope === "user", unit: name, n: 300 })), (rows) => {
      if (pg.current !== name) return;
      log.loading = false;
      log.setRows(rows || []);
    });
    pg.follow(pg.following);
  }
  // a unit asked for by name: shown whatever the chip, and chosen
  function reveal(name) {
    if (!pg.all.some((u) => u.unit === name)) pg.chip = "all";
    else if (!H.shows(pg.all.find((u) => u.unit === name), pg.chip)) pg.chip = "all";
    filterBox.text = "";
    pg.choose(name);
    Qt.callLater(() => { const i = pg.shown.findIndex((u) => u.unit === name); if (i >= 0) { pg.sel = i; list.positionViewAtIndex(i, ListView.Center); } });
  }
  function move(d) {
    if (pg.shown.length === 0) return;
    pg.listFocus = true;
    pg.sel = Math.max(0, Math.min(pg.shown.length - 1, pg.sel + d));
    list.positionViewAtIndex(pg.sel, ListView.Contain);
    pg.choose(pg.shown[pg.sel].unit);
  }
  onShownChanged: if (pg.sel >= pg.shown.length) pg.sel = Math.max(0, pg.shown.length - 1)
  function focusFilter() { filterBox.claim(); }

  // ── FOLLOWING ITS LOG ──────────────────────────────────────────────────
  property bool following: true
  function follow(on) {
    pg.following = on;
    followProc.running = false;
    if (!on || pg.current === "") return;
    followProc.command = Paths.tether(H.logArgs({ user: pg.scope === "user", unit: pg.current }, true));
    followProc.running = true;
  }
  Process {
    id: followProc
    stdout: SplitParser { splitMarker: "\n"; onRead: (line) => log.append(H.parseJournalLine(line)) }
  }
  Component.onDestruction: followProc.running = false
  onVisibleChanged: if (!pg.visible) followProc.running = false; else if (pg.current !== "") pg.follow(pg.following)

  function act(verb) {
    if (!pg.unit) return;
    if (!pg.mgr.act(pg.scope, verb, pg.unit.unit) && pg.win) pg.win.say("Still doing the last one", true);
  }
  // facts again after anything is done to it
  Connections {
    target: pg.mgr
    function onActed(ok, words) {
      if (pg.current !== "") pg.mgr.ask(["show", pg.scope, pg.current], (j) => { if (j && pg.current === j.Id) pg.facts = j; });
    }
  }

  // ── THE LIST ───────────────────────────────────────────────────────────
  Item {
    id: listSide
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Math.max(320, Math.min(460, parent.width * 0.4))
    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Zenon.border; z: 4 }

    // ── THE BAR OVER THE LIST ──────────────────────────────────────────
    // The rows scroll on up under the filter and the chips and the
    // window's head, frosted (morpheus/ScrollEdge), and down under the
    // hints; the filter's ground is the head's, translucent, so the frost
    // shows through it as it does through the head.
    ScrollEdge { view: list; follow: true; chromeTop: pg.win ? -pg.win.headH : 0; z: 1 }
    ScrollEdge { view: list; below: true; follow: true; bar: pg.win ? pg.win.footItem : null; z: 1 }
    Rectangle { id: listChrome; z: 2; width: parent.width - 1; height: list.y; color: Zenon.headBg }

    BulkField {
      id: filterBox
      z: 3
      x: 14
      y: 14
      width: parent.width - 28
      height: 32
      ghost: "Filter " + (pg.scope === "user" ? "your services" : "services")
      clearable: true
      onTextChanged: { pg.query = filterBox.text; pg.sel = 0; }
      onAccepted: if (pg.win) pg.win.refocus()
    }
    Segments {
      id: chips
      z: 3
      x: 14
      anchors.top: filterBox.bottom
      anchors.topMargin: 10
      even: true
      width: parent.width - 28
      options: H.SHOWS.map((s) => [s.id, s.label + (s.id === "all" ? "" : " " + (pg.counts[s.id] || 0))])
      current: pg.chip
      inks: ({ failed: pg.counts.failed > 0 ? Zenon.red : Zenon.accentMuted })
      onChose: (v) => { pg.chip = v; pg.sel = 0; }
    }

    EmptyState {
      anchors.top: chips.bottom
      anchors.topMargin: 40
      x: 20
      width: parent.width - 40
      visible: pg.shown.length === 0
      text: pg.mgr && pg.mgr.loadingUnits && pg.all.length === 0 ? "Asking systemd…"
        : pg.query !== "" ? "Nothing matches “" + pg.query + "”"
        : pg.chip === "failed" ? "Nothing has failed" : "Nothing here"
    }
    ListView {
      id: list
      anchors.top: chips.bottom
      anchors.topMargin: 10
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.rightMargin: 1
      anchors.bottom: parent.bottom
      clip: true
      // by count: the units are a new array on every refresh
      model: pg.shown.length
      ElasticScroll { view: list }
      CursorBand { follows: list; index: pg.sel; shown: pg.listFocus || (!!pg.shown[pg.sel] && pg.shown[pg.sel].unit === pg.current) }
      delegate: Item {
        id: urow
        required property int index
        readonly property var u: pg.shown[index] || null
        readonly property string role: H.stateRole(u)
        width: list.width
        height: 52
        Rectangle {
          id: dot
          x: 18
          anchors.verticalCenter: parent.verticalCenter
          width: 8
          height: 8
          radius: 4
          color: urow.role === "ok" ? Zenon.green : urow.role === "bad" ? Zenon.red
            : urow.role === "busy" ? Zenon.yellow : urow.role === "done" ? Zenon.accentSoft : Zenon.wash(0.25)
        }
        Column {
          anchors.left: dot.right
          anchors.leftMargin: 12
          anchors.right: badge.left
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          spacing: 2
          Text {
            width: parent.width
            elide: Text.ElideRight
            text: urow.u ? H.shortName(urow.u.unit) : ""
            color: urow.u && urow.u.unit === pg.current ? Zenon.ink : Zenon.white
            font.family: Zenon.face
            font.weight: 600
            font.pixelSize: Zenon.px(14)
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width
            elide: Text.ElideRight
            text: urow.u ? (urow.u.desc || H.bootWords(urow.u.file)) : ""
            color: Zenon.accentMuted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(12)
          }
        }
        // restarting over and over says so, in red
        Text {
          id: badge
          anchors.right: parent.right
          anchors.rightMargin: 16
          anchors.verticalCenter: parent.verticalCenter
          text: !urow.u ? "" : H.looping(urow.u) ? "\u{F0709} " + urow.u.restarts : urow.role === "bad" ? "Failed" : ""
          color: Zenon.red
          font.family: Zenon.face
          font.weight: 600
          font.pixelSize: Zenon.px(12)
        }
        MouseArea { anchors.fill: parent; onClicked: { pg.sel = urow.index; pg.listFocus = true; if (urow.u) pg.choose(urow.u.unit); if (pg.win) pg.win.refocus(); } }
      }
    }
    Scrollbar { flick: list; anchors.right: parent.right; anchors.top: list.top; anchors.bottom: list.bottom }
  }

  // ── THE ONE CHOSEN ─────────────────────────────────────────────────────
  Item {
    id: detail
    anchors.left: listSide.right
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom

    EmptyState {
      anchors.centerIn: parent
      visible: !pg.unit
      text: "Choose a service to see what it is doing"
    }

    Column {
      id: detailTop
      visible: !!pg.unit
      x: 24
      y: 18
      width: parent.width - 48
      spacing: 12

      Item {
        width: parent.width
        height: 40
        Column {
          anchors.left: parent.left
          anchors.right: actRow.left
          anchors.rightMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          spacing: 2
          Text {
            width: parent.width
            elide: Text.ElideRight
            text: pg.unit ? H.shortName(pg.unit.unit) : ""
            color: Zenon.ink
            font.family: Zenon.face
            font.weight: Zenon.titleWeight
            font.pixelSize: Zenon.px(18)
          }
          Text {
            width: parent.width
            elide: Text.ElideRight
            text: pg.unit ? H.stateWords(pg.unit) + "  ·  " + H.bootWords(pg.unit.file) : ""
            color: !pg.unit ? Zenon.accentMuted : H.stateRole(pg.unit) === "bad" ? Zenon.red
              : H.stateRole(pg.unit) === "ok" ? Zenon.green : Zenon.accentMuted
            font.family: Zenon.face
            font.weight: 600
            font.pixelSize: Zenon.px(13)
          }
        }
        Row {
          id: actRow
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: 8
          Repeater {
            model: H.actions(pg.unit)
            delegate: BusyButton {
              required property var modelData
              implicitHeight: 32
              label: modelData.label
              ink: ({ red: Zenon.red, green: Zenon.green, cyan: Zenon.cyan, yellow: Zenon.yellow })[modelData.ink] || Zenon.accentMuted
              busy: !!pg.mgr && pg.mgr.busy === modelData.verb + " " + (pg.unit ? pg.unit.unit : "")
              busyText: "…"
              ready: !!pg.mgr && pg.mgr.busy === ""
              onClicked: pg.act(modelData.verb)
            }
          }
        }
      }

      HermesCard {
        title: "About"
        glyph: "\u{F02FD}"
        note: pg.unit ? pg.unit.desc : ""
        HermesFact { label: "Running since"; value: pg.facts && pg.unit && pg.unit.active === "active" ? pg.facts.ActiveEnterTimestamp : "" }
        HermesFact { label: "Stopped since"; value: pg.facts && pg.unit && pg.unit.active !== "active" ? pg.facts.InactiveEnterTimestamp : "" }
        HermesFact { label: "Process"; value: pg.facts && pg.facts.MainPID > 0 ? String(pg.facts.MainPID) : "" }
        HermesFact { label: "Memory"; value: pg.facts ? H.bytes(pg.facts.MemoryCurrent) : "" }
        HermesFact { label: "CPU time"; value: pg.facts && pg.facts.CPUUsageNSec > 0 ? H.cpuTime(pg.facts.CPUUsageNSec) : "" }
        HermesFact { label: "Restarts"; value: pg.facts && pg.facts.NRestarts > 0 ? pg.facts.NRestarts + (pg.facts.Restart ? "  (restart " + pg.facts.Restart + ")" : "") : "" }
        HermesFact { label: "Last result"; value: pg.facts && pg.facts.Result && pg.facts.Result !== "success" ? pg.facts.Result : "" }
        HermesFact { label: "Runs"; value: pg.facts ? pg.facts.ExecStart || "" : "" }
        HermesFact { label: "Started by"; value: pg.facts ? pg.facts.TriggeredBy || pg.facts.WantedBy || "" : "" }
        HermesFact { label: "Unit file"; value: pg.facts ? pg.facts.FragmentPath || "" : "" }
      }

      Item {
        width: parent.width
        height: 30
        SectionLabel { anchors.verticalCenter: parent.verticalCenter; text: "Its journal" }
        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: 8
          DialogButton {
            implicitHeight: 28
            label: "In the journal"
            onClicked: if (pg.win) pg.win.journalOf(pg.current, pg.scope)
          }
          DialogButton {
            implicitHeight: 28
            label: pg.following ? "Following" : "Follow"
            ink: pg.following ? Zenon.cyan : Zenon.muted
            onClicked: pg.follow(!pg.following)
          }
        }
      }
    }
    Rectangle {
      visible: !!pg.unit
      anchors.top: detailTop.bottom
      anchors.topMargin: 6
      anchors.left: parent.left
      anchors.leftMargin: 24
      anchors.right: parent.right
      anchors.rightMargin: 24
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 16
      radius: Zenon.radiusCard
      color: Zenon.wash(0.03)
      border.width: 1
      border.color: Zenon.border
      clip: true
      HestiaLog {
        id: log
        anchors.fill: parent
        anchors.margins: 1
        showUnit: false
        emptyText: "Nothing in its journal"
      }
    }
  }
}

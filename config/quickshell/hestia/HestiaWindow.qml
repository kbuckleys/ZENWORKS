// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// HESTIA'S WINDOW — five pages, chosen in the head (a sidebar for five was
// a column of empty glass; user, 2026-10-21), the page under it full width
// and running up under the head and its own bar, frosted (ScrollEdge):
//
//   Overview      what wants looking at: failed, restarting over and over,
//                 this boot's errors, the boot itself
//   Services      the machine's; My services, your session's
//   Timers        what runs on a schedule, and when next
//   Journal       everything written, filtered and followed
//
//   ctrl 1…5   page          ↑ ↓   a service        ctrl f   filter
//   ctrl r     ask again     esc   closes

import QtQuick
import Quickshell
import "../morpheus"
import "../terminus"
import "hestia.js" as H

FloatingWindow {
  id: hw
  title: "hestia"
  color: Zenon.alpha(Zenon.layerBg, 0)
  implicitWidth: 1240
  implicitHeight: 800
  minimumSize: Qt.size(900, 560)

  property var mgr: null

  onVisibleChanged: if (!hw.visible) Qt.callLater(() => { if (hw.mgr) hw.mgr.retire(hw); hw.destroy(); })
  onClosed: hw.visible = false
  Component.onCompleted: if (hw.mgr) { hw.mgr.refresh(); hw.mgr.refreshTimers(); }

  readonly property int headH: 60
  property string section: "overview"
  readonly property var counts: H.counts(hw.mgr ? hw.mgr.system.concat(hw.mgr.user) : [])

  function go(id) {
    if (id && H.SECTIONS.some((s) => s.id === id)) hw.section = id;
    hw.refocus();
  }
  function showUnit(unit, scope) {
    const s = scope === "user" ? "user" : scope === "system" ? "system"
      : hw.mgr && hw.mgr.unitOf("user", unit) && !hw.mgr.unitOf("system", unit) ? "user" : "system";
    hw.section = s;
    (s === "user" ? userPage : systemPage).reveal(unit);
    hw.refocus();
  }
  function journalOf(unit, scope, prio) {
    hw.section = "journal";
    journalPage.show(unit || "", scope || "system");
    if (prio) journalPage.prio = prio;
    hw.refocus();
  }
  function refocus() { Qt.callLater(() => keys.forceActiveFocus()); }

  // ── WHAT WAS JUST DONE, SAID ONCE ─────────────────────────────────────
  property string said: ""
  property bool saidBad: false
  function say(t, bad) { hw.said = t; hw.saidBad = !!bad; sayTimer.restart(); }
  Timer { id: sayTimer; interval: 3200; onTriggered: hw.said = "" }
  Connections {
    target: hw.mgr
    function onActed(ok, words) { hw.say(words, !ok); }
  }

  readonly property var page: ({ system: systemPage, user: userPage })[hw.section] || null
  // the bars the pages' content runs up and down under (their ScrollEdges)
  readonly property Item headItem: head
  readonly property Item footItem: foot
  // what a section says beside its name in the head
  function sectionCount(id) {
    if (!hw.mgr) return "";
    if (id === "overview") return hw.counts.failed + hw.counts.looping > 0 ? "  " + (hw.counts.failed + hw.counts.looping) : "";
    if (id === "system") return "  " + H.counts(hw.mgr.system).running;
    if (id === "user") return "  " + H.counts(hw.mgr.user).running;
    if (id === "timers") return hw.mgr.timers.length ? "  " + hw.mgr.timers.length : "";
    return "";
  }
  function lookAgain() {
    hw.mgr.refresh();
    if (hw.section === "timers") hw.mgr.refreshTimers();
    if (hw.section === "overview") overviewPage.load();
    if (hw.section === "journal") journalPage.load();
  }

  // ── KEYS ───────────────────────────────────────────────────────────────
  Item {
    id: keys
    focus: true
    Keys.onPressed: (e) => {
      const ctrl = e.modifiers & Qt.ControlModifier;
      e.accepted = true;
      if (e.key === Qt.Key_Escape) { hw.visible = false; return; }
      if (ctrl && e.key >= Qt.Key_1 && e.key <= Qt.Key_5) { hw.go(H.SECTIONS[e.key - Qt.Key_1].id); return; }
      if (ctrl && e.key === Qt.Key_R) { hw.lookAgain(); return; }
      if (hw.page) {
        if (e.key === Qt.Key_Down) { hw.page.move(1); return; }
        if (e.key === Qt.Key_Up) { hw.page.move(-1); return; }
        if (e.key === Qt.Key_PageDown) { hw.page.move(10); return; }
        if (e.key === Qt.Key_PageUp) { hw.page.move(-10); return; }
        if (ctrl && e.key === Qt.Key_F) { hw.page.focusFilter(); return; }
      }
      e.accepted = false;
    }
  }

  // ── THE STAGE ──────────────────────────────────────────────────────────
  Item {
    id: stage
    anchors.fill: parent
    Rectangle { z: -1; anchors.fill: parent; color: Zenon.layerBg }

    // ── the head ─────────────────────────────────────────────────────────
    // over the pages (z), its ground translucent: what scrolls up under it
    // shows through, frosted, from each page's ScrollEdge
    Item {
      id: head
      z: 3
      anchors.left: parent.left
      anchors.right: parent.right
      height: hw.headH
      Rectangle { anchors.fill: parent; color: Zenon.headBg }
      Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Zenon.border }
      Text {
        id: brandGlyph
        x: 20
        anchors.verticalCenter: parent.verticalCenter
        text: "\u{F0E2E}"
        color: Zenon.yellow
        font.family: Zenon.glyphFace
        font.pixelSize: Zenon.px(20)
      }
      Column {
        id: brandWords
        anchors.left: brandGlyph.right
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1
        Text {
          // the UI name (user, 2026-10-21); code, IPC and directory stay "hestia"
          text: "System Log"
          color: Zenon.ink
          font.family: Zenon.face
          font.weight: Zenon.titleWeight
          font.pixelSize: Zenon.px(17)
        }
        Text {
          text: hw.counts.failed + hw.counts.looping === 0 ? "All running well"
            : [hw.counts.failed ? hw.counts.failed + " failed" : "", hw.counts.looping ? hw.counts.looping + " restarting" : ""].filter((x) => x).join(", ")
          color: hw.counts.failed + hw.counts.looping === 0 ? Zenon.accentMuted : Zenon.red
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(12)
        }
      }
      // the five pages, with what each has to say beside its name
      Segments {
        anchors.centerIn: parent
        options: H.SECTIONS.map((s) => [s.id, s.label + hw.sectionCount(s.id)])
        current: hw.section
        inks: ({ overview: hw.counts.failed + hw.counts.looping > 0 ? Zenon.red : Zenon.accentMuted })
        onChose: (v) => hw.go(v)
      }
      BusyButton {
        id: refreshBtn
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        implicitHeight: 32
        label: "Look again"
        busy: !!hw.mgr && hw.mgr.loadingUnits
        busyText: "Asking\u2026"
        onClicked: hw.lookAgain()
      }
    }

    // ── the pages ────────────────────────────────────────────────────────
    Item {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: head.bottom
      anchors.bottom: foot.top
      HestiaOverview { id: overviewPage; anchors.fill: parent; mgr: hw.mgr; win: hw; visible: hw.section === "overview" }
      HestiaUnits { id: systemPage; anchors.fill: parent; mgr: hw.mgr; win: hw; scope: "system"; visible: hw.section === "system" }
      HestiaUnits { id: userPage; anchors.fill: parent; mgr: hw.mgr; win: hw; scope: "user"; visible: hw.section === "user" }
      HestiaTimers { id: timersPage; anchors.fill: parent; mgr: hw.mgr; win: hw; visible: hw.section === "timers" }
      HestiaJournal { id: journalPage; anchors.fill: parent; mgr: hw.mgr; win: hw; visible: hw.section === "journal" }
    }

    Rectangle {
      anchors.horizontalCenter: body.horizontalCenter
      anchors.bottom: foot.top
      anchors.bottomMargin: 18
      width: Math.min(saidText.implicitWidth + 32, 620)
      height: 34
      radius: Zenon.windowRadius
      color: Zenon.hud(0.85)
      border.width: 1
      border.color: hw.saidBad ? Zenon.alpha(Zenon.red, 0.6) : Zenon.border
      opacity: hw.said !== "" ? 1 : 0
      visible: opacity > 0
      z: 5
      Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Easing.OutCubic } }
      Text {
        id: saidText
        anchors.centerIn: parent
        width: Math.min(implicitWidth, parent.width - 32)
        elide: Text.ElideRight
        text: hw.said
        color: hw.saidBad ? Zenon.red : Zenon.ink
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(15)
      }
    }

    HintBar {
      id: foot
      z: 3
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      rows: hw.page ? [["↑↓", "service"], ["ctrl f", "filter"], ["ctrl 1-5", "page"], ["ctrl r", "look again"], ["esc", "close"]]
        : [["ctrl 1-5", "page"], ["ctrl r", "look again"], ["esc", "close"]]
    }
  }
}

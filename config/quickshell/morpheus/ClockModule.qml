// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import Quickshell
import "helpers.js" as Helpers
import "../chronos/chronos.js" as Chr
import "../chronos/weather.js" as Wx
import "../chronos"
import "../oracle"
import "."

Item {
  id: root
  implicitWidth: row.implicitWidth
  implicitHeight: Zenon.slot

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    leftPadding: Zenon.padModule
    rightPadding: Zenon.padModule

    // The live digits sit on top of every segment lit and dimmed. DSEG has no
    // ghosting of its own — you get it by drawing "88:88" behind, which is
    // literally what the panel of a real clock is doing: the unlit segments
    // are still there, you can just about see them.
    //
    // The ghost is built from the SAME shape as the reading — one more group
    // of eights when the seconds are showing — so the two cannot come out
    // different widths and leave the live digits sitting off-centre on their
    // own unlit panel.
    Item {
      width: Math.max(ghost.implicitWidth, label.implicitWidth)
      height: Zenon.slot
      anchors.verticalCenter: parent.verticalCenter

      BarText {
        id: ghost
        anchors.centerIn: parent
        text: Oracle.clockSeconds ? "88:88:88" : "88:88"
        numeric: true
        // the same ink an unlit meter notch uses: it is the same idea, an
        // element of the accent that is present but not lit
        color: Zenon.trough(Zenon.cyan)
      }

      BarText {
        id: label
        anchors.centerIn: parent
        // Padded in both modes, and on purpose: an unpadded 12-hour clock is
        // one digit narrower for eleven hours of the day, and a bar module
        // that changes width every time it strikes ten would push everything
        // beside it sideways. The leading zero is what keeps the pill still.
        text: Helpers.pad(root.shownHour) + ":" + Helpers.pad(clock.minutes)
          + (Oracle.clockSeconds ? ":" + Helpers.pad(clock.seconds) : "")
        numeric: true
        color: Zenon.cyan
      }
    }

    // ── THE TIMER THAT ENDS FIRST ────────────────────────────────────
    // While a chronos timer runs, its time left rides beside the clock in
    // the clock's own digits, green as chronos draws a running one. Only the
    // soonest: the rest are in the tooltip, and a row of countdowns would
    // push the meters about. Ghosted to its own width, so the digits ticking
    // down never shuffle the bar.
    Collapsible {
      anchors.verticalCenter: parent.verticalCenter
      active: root.nextTimer !== null
      // a digit's width plus two bar gaps between the clock and the countdown:
      // enough that they read as two numbers, not one long time
      openWidth: timerBox.width + Zenon.gap * 2 + digitMetrics.advanceWidth
      TextMetrics { id: digitMetrics; font: timerLabel.font; text: "8" }
      Item {
        id: timerBox
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(timerGhost.implicitWidth, timerLabel.implicitWidth)
        height: Zenon.slot
        BarText {
          id: timerGhost
          anchors.centerIn: parent
          text: root.timerText.replace(/[0-9]/g, "8")
          numeric: true
          color: Zenon.trough(Zenon.green)
        }
        BarText {
          id: timerLabel
          anchors.centerIn: parent
          text: root.timerText
          numeric: true
          color: Zenon.green
        }
      }
    }
  }

  readonly property var nextTimer: {
    const ts = Chronos.timers;
    let best = null;
    for (let i = 0; ts && i < ts.length; ++i)
      if (ts[i].running && (best === null || ts[i].remaining < best.remaining)) best = ts[i];
    return best;
  }
  // kept through the collapse, so the digits do not blank as it eases shut
  property string timerText: "00:00"
  onNextTimerChanged: if (root.nextTimer) root.timerText = Chr.clock(root.nextTimer.remaining)

  // 13 is 01 on a 12-hour face, and midnight is 12 rather than 00.
  readonly property int shownHour: {
    if (Oracle.clock24h) return clock.hours;
    return ((clock.hours + 11) % 12) + 1;
  }

  SystemClock {
    id: clock
    // Seconds means a repaint a second rather than a repaint a minute, which
    // is sixty times the work for a digit most bars do not carry — so it is
    // only asked for when it is actually being shown.
    precision: Oracle.clockSeconds ? SystemClock.Seconds : SystemClock.Minutes
    enabled: true
  }

  // What today is, in one line. The month grid that used to hang off this
  // hover is a layer now — a calendar you can page through does not belong in
  // something that vanishes when the pointer moves.
  signal activated()

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    onClicked: root.activated()
  }

  // ── WHAT IS RUNNING, under the date ───────────────────────────────────
  // A timer you set is a thing you are waiting on, and the clock is what you
  // look at while waiting — but the only place saying how long was left was
  // the panel behind a click. The hover already answers "what day is it"; it
  // may as well answer the other question you came to the clock with.
  //
  // Running ones first and counting down; idle ones after, showing the length
  // they are set to. An idle timer is still something you made on purpose and
  // worth being reminded of, and the two are told apart by the arrow rather
  // than by being in separate lists.
  // ── THE WEATHER, UNDER THE DATE ──────────────────────────────────────
  // chronos' own reading, not a second fetch: whatever its panel last got.
  // Nothing at all when weather is switched off or has never answered.
  readonly property string weatherLine: {
    const c = Weather.current;
    if (Weather.disabled || !c) return "";
    return "\n" + Wx.glyph(c.code, c.isDay) + "  " + Weather.fmt(c.temp) + Weather.unit
      + "  " + Wx.label(c.code).toLowerCase();
  }
  // Hovering is asking, so an old reading is refreshed then — the same
  // stale rule the panel uses, so this is never more traffic than opening it.
  Connections {
    target: mouse
    function onContainsMouseChanged() { if (mouse.containsMouse && !Weather.disabled) Weather.refreshIfStale(); }
  }

  readonly property string timerLines: {
    const ts = Chronos.timers;
    if (!ts || ts.length === 0) return "";
    const run = [];
    const idle = [];
    for (let i = 0; i < ts.length; ++i) {
      const t = ts[i];
      const name = String(t.label || "timer");
      if (t.running) run.push("\u25b8 " + name + "   " + Chr.clock(t.remaining));
      else idle.push("\u00b7 " + name + "   " + t.minutes + "m");
    }
    const all = run.concat(idle);
    return all.length === 0 ? "" : "\n" + all.join("\n");
  }

  Tooltip {
    anchorItem: root
    cursorArea: mouse
    text: Chr.oneLine(clock.date) + root.weatherLine + root.timerLines
    align: Text.AlignHCenter
    show: mouse.containsMouse
  }
}

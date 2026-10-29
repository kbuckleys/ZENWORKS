// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// WALLCLOCK — the time of day, ticking on the minute (or the second).
//
//   WallClock { id: clock; withSeconds: Oracle.clockSeconds }
//   … clock.date, clock.hours, clock.minutes, clock.seconds
//
// Quickshell's SystemClock in its place: that one aims its next tick at a
// local time, and in the hour a DST fall-back repeats it takes the first
// pass of that time — already gone, so it re-arms at 1 ms the whole hour.
// Cairo, 2026-10-29: ~1900 "QTimer::start: negative intervals" a second
// and a third of a core. This aims at epoch boundaries instead, which every
// zone's minutes share, so the local clock never comes into it.
import QtQuick

QtObject {
  id: wc

  property bool withSeconds: false
  property bool enabled: true

  property date date: new Date()
  readonly property int hours: wc.date.getHours()
  readonly property int minutes: wc.date.getMinutes()
  readonly property int seconds: wc.date.getSeconds()

  // a hair past the boundary, so the new minute has surely begun
  function wait() {
    const step = wc.withSeconds ? 1000 : 60000;
    return step - Date.now() % step + 20;
  }
  function now() {
    wc.date = new Date();
    tick.interval = wc.wait();
  }

  onWithSecondsChanged: { wc.now(); tick.restart(); }
  onEnabledChanged: if (wc.enabled) wc.now()

  readonly property Timer tick: Timer {
    interval: wc.wait()
    running: wc.enabled
    repeat: true
    onTriggered: wc.now()
  }
}

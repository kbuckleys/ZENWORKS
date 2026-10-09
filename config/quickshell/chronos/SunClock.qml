// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// IS THE SUN UP? Zenon.daylight, for Follow Daytime (the Day theme by
// daylight, the Night theme after dark) and Follow Background's Sun tone.
//
// Today's sunrise and sunset are the forecast's (Weather.today — open-meteo
// gives them as local wall-clock times, "2026-10-08T06:05"). With no
// forecast — the weather switched off, no location yet, a day the forecast
// has not reached — it is day from 07:00 to 19:00. Asked once a minute and
// whenever a forecast lands; the theme only changes when the answer does.
//
// Loaded by shell.qml through a Loader: chronos/qmldir does not list it, and
// a new qmldir entry is not seen by a live reload.

import QtQuick
import "../morpheus"

Item {
  id: sun

  function minutes(d) { return d.getHours() * 60 + d.getMinutes(); }

  function update() {
    const now = new Date();
    const iso = Qt.formatDate(now, "yyyy-MM-dd");
    const day = Weather.dayFor(iso);
    let up = 7 * 60, down = 19 * 60;
    if (day && day.sunrise && day.sunset) {
      const r = new Date(day.sunrise), s = new Date(day.sunset);
      if (!isNaN(r.getTime()) && !isNaN(s.getTime())) { up = sun.minutes(r); down = sun.minutes(s); }
    }
    const m = sun.minutes(now);
    const light = m >= up && m < down;
    if (Zenon.daylight !== light) Zenon.daylight = light;
  }

  Timer { interval: 60000; repeat: true; running: true; onTriggered: sun.update() }
  Connections { target: Weather; function onDaysChanged() { sun.update(); } }
  Component.onCompleted: sun.update()
}

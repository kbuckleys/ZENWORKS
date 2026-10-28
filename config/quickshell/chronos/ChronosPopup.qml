// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┘┴└─┘
// https://github.com/kbuckleys/
//
// CHRONOS — what the clock opens into. The calendar on the left, the forecast
// on the right, the chosen day's agenda under both, and the pomodoro band
// across the foot.
//
// POINTER-ONLY, deliberately. It spawns from a pill you clicked, so it is
// answering a mouse, and every affordance in here is a hit target: months step
// on a click or a scroll, a timer's length steps on a scroll or its own
// stepper, and nothing hides behind a chord. The single exception is naming a
// timer, which is typing by definition — and even that commits and cancels
// from two buttons as well as from the keyboard.
//
// The two panes are wired together: picking a day in the calendar focuses the
// forecast on it, and picking a day in the forecast strip moves the calendar's
// selection to match. One selected date, two views of it.

import QtQuick
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Widgets
import "../morpheus"
import "../terminus"
import "../morpheus/helpers.js" as Helpers
import "../clio"
import "../clio/notes.js" as N
import "chronos.js" as Chr
import "weather.js" as Wx

LayerPopup {
  id: popup

  readonly property string face: Zenon.face
  // the calendar window's manager (shell.qml's Loader): a day
  // double-clicked opens it there
  property var calendar: null

  // While the pill is still growing into this layer, the panel is scaled down
  // to the pill's live size — and a radius scales with it. Halfway through, an
  // 8px corner paints as ~5px on screen while the pill's own corner is a true
  // 8px, so the dark header strip inside this clip pokes out past the pill's
  // arc. Dividing by the scale keeps the ON-SCREEN radius at pillRadius. The
  // two axes scale by different amounts, so mid-morph the corner is cut a
  // shade wide — which shows the pill's own background rather than this
  // layer's, and is gone by the time the scale reaches 1.
  readonly property real clipRadius: Zenon.pillRadius
    / Math.max(0.2, Math.min(popup.panelX, popup.panelY))

  // the glyphs this panel is built out of, named once. Every codepoint was
  // read off the installed font rather than taken from a cheat sheet.
  readonly property string glyphRename:  ""
  readonly property string glyphReset:   ""
  readonly property string glyphRemove:  ""
  readonly property string glyphTimer:   ""
  readonly property string glyphAdd:     "\u{F0415}"
  readonly property string glyphPlay:    "\u{F040A}"
  readonly property string glyphPause:   "\u{F03E4}"

  // ── the date the whole panel is pointed at ───────────────────────────
  // A month cursor rather than a Date for the view: paging by month on a Date
  // lands on the 31st of a 30-day month and silently skips one.
  property int viewYear: 0
  property int viewMonth: 0
  // The selection carries its own y/m/d rather than an offset into the view:
  // the grid's dim cells belong to the neighboring months, so what is
  // selected is not always inside the month on screen.
  property int selYear: 0
  property int selMonth: 0
  property int selDay: 1
  property var today: new Date()

  readonly property string todayIso: Chr.isoOf(popup.today)
  readonly property string selIso:
    Chr.isoDay(popup.selYear, popup.selMonth, popup.selDay)
  readonly property var selDate: new Date(popup.selYear, popup.selMonth, popup.selDay)
  readonly property bool selIsToday: popup.selIso === popup.todayIso

  readonly property var cells: Chr.monthGrid(popup.viewYear, popup.viewMonth)

  function goToday() {
    popup.today = new Date();
    popup.viewYear = popup.today.getFullYear();
    popup.viewMonth = popup.today.getMonth();
    popup.selYear = popup.viewYear;
    popup.selMonth = popup.viewMonth;
    popup.selDay = popup.today.getDate();
  }

  function stepMonth(d) {
    let m = popup.viewMonth + d;
    let y = popup.viewYear;
    while (m < 0) { m += 12; y -= 1; }
    while (m > 11) { m -= 12; y += 1; }
    popup.viewMonth = m;
    popup.viewYear = y;
  }

  function stepYear(d) { popup.viewYear += d; }

  // Picking a day in a dim leading or trailing cell pages the view to that
  // day's own month, which is what clicking one of them plainly means.
  function pick(y, m, d) {
    popup.selYear = y;
    popup.selMonth = m;
    popup.selDay = d;
    popup.viewYear = y;
    popup.viewMonth = m;
  }

  // ── naming, the one place typing belongs ─────────────────────────────
  // -1 while naming something that does not exist yet, otherwise the index of
  // the timer being renamed.
  property bool naming: false
  property int nameTarget: -1

  function startNaming(index) {
    popup.nameTarget = index;
    popup.naming = true;
    nameInput.text = (index >= 0 && Chronos.timers[index])
      ? Chronos.timers[index].label : "";
    nameInput.selectAll();
    Qt.callLater(() => { if (popup.naming) nameInput.forceActiveFocus(); });
  }

  function commitName() {
    const label = nameInput.text.trim();
    const target = popup.nameTarget;
    popup.naming = false;
    popup.nameTarget = -1;
    // an empty name still makes a timer; it just gets the generic one
    if (target < 0) Chronos.add(label, 0);
    else if (label !== "") Chronos.relabel(target, label);
    bgRoot.forceActiveFocus();
  }

  function cancelName() {
    popup.naming = false;
    popup.nameTarget = -1;
    bgRoot.forceActiveFocus();
  }

  // ── geometry ─────────────────────────────────────────────────────────
  readonly property int cellW: 52
  readonly property int cellH: 34
  readonly property int gridW: popup.cellW * 7
  // both panes are the calendar grid plus breathing room, and the panel is as
  // wide as the two of them rather than stretched to the usual 1000
  readonly property int paneW: popup.gridW + 24
  readonly property int sideMargin: 20
  readonly property int splitGap: 20
  readonly property int panelWidth:
    popup.sideMargin * 2 + popup.paneW * 2 + popup.splitGap * 2 + 1

  // ── the pomodoro band ────────────────────────────────────────────────
  // Cells divide the band's width between them: one timer takes all of it, two
  // take a half each, three a third each. Past three they wrap, and the rows
  // are balanced rather than filled — four comes out 2+2, not 3+1, because a
  // lone cell stretched across a whole row does not read as one of a set.
  readonly property int perRow: 3
  readonly property int cellGap: 10
  // A cell is the same height as the empty invitation, so the band never
  // changes shape when the first timer appears.
  readonly property int timerH: popup.emptyH
  // the ＋ strip runs the full height of the band down its right edge
  readonly property bool bandEmpty: Chronos.timers.length === 0
  readonly property int bandPadTop: 8
  readonly property int bandPadBottom: 8

  readonly property var bandLayout: {
    const counts = Chr.bandRows(Chronos.timers.length, popup.perRow);
    const out = [];
    let i = 0;
    for (const n of counts) {
      const row = [];
      for (let k = 0; k < n; ++k) row.push(i++);
      out.push(row);
    }
    return out;
  }

  // Two lines (2026-10-24): a cell's name over its countdown. On one line the
  // name was what gave way, and three across it gave way entirely — the
  // hover tools held their room even while hidden. The empty invitation is
  // two lines as well (what to do, and the gestures), so the band keeps its
  // shape when the first timer appears.
  readonly property int emptyH: 58

  readonly property int bandInner: {
    if (popup.bandEmpty) return popup.emptyH;
    const rows = Math.max(1, popup.bandLayout.length);
    return rows * popup.timerH + (rows - 1) * popup.cellGap;
  }
  readonly property int bandHeight:
    popup.bandPadTop + popup.bandInner + popup.bandPadBottom
  readonly property int bandWidth: popup.panelWidth - popup.sideMargin * 2
  readonly property bool hasTimers: Chronos.timers.length > 0
  // The cells own the whole band. Adding a timer is one of the buttons on a
  // cell now, so nothing is reserved beside them — which is also what makes
  // "one timer takes the whole width" literally true.
  readonly property int cellsWidth: popup.bandWidth

  function cellWidthFor(count) {
    if (count <= 0) return popup.cellsWidth;
    return (popup.cellsWidth - (count - 1) * popup.cellGap) / count;
  }

  // ── the body ─────────────────────────────────────────────────────────
  // Fixed, and sized by the calendar: six rows of a month is the tallest thing
  // in here and the one that must not move as you page through months.
  readonly property int panePad: 18
  // header + weekday row + six weeks + footer + the gaps between them, and a
  // little over so the forecast's week strip is not fighting the calendar for
  // the last dozen pixels
  readonly property int paneInner: 34 + 22 + popup.cellH * 6 + 26 + 24 + 14
  readonly property int bodyHeight: popup.panePad * 2 + popup.paneInner

  // "2 events · 1 task"
  function agendaCount() {
    const t = popup.dayTasks.length, e = popup.dayEvents.length - t;
    return [e > 0 ? e + (e === 1 ? " event" : " events") : "", t > 0 ? t + (t === 1 ? " task" : " tasks") : ""]
      .filter((x) => x).join(" \u00B7 ");
  }
  function calcHeight() { return popup.bandHeight + 1 + popup.bodyHeight + 1 + popup.agendaH; }

  // ── the day's events (khal; 2026-10-21) ──────────────────────────────
  // A strip under the calendar: the chosen day's events, one line each, and
  // a line to type a new one into. Before khal is set up, the one button
  // that sets it up.
  // Clio's open checklist items with a due date (2026-10-22): on their day
  // beside the events, khal or not — a click opens the note at the item
  readonly property var openTasks: Clio.app ? N.tasks(Clio.app.notes, Date.now()).filter((t) => t.due > 0) : []
  readonly property var taskDays: {
    const out = {};
    for (const t of popup.openTasks) out[Chr.isoOf(new Date(t.due))] = true;
    return out;
  }
  readonly property var dayTasks: popup.openTasks.filter((t) => Chr.isoOf(new Date(t.due)) === popup.selIso)
    .map((t) => ({ title: t.h, start: N.clock(t.due), allDay: false, task: t }))
  readonly property var dayEvents: (Chronos.calReady ? (Chronos.byDay[popup.selIso] || []) : []).concat(popup.dayTasks)
  readonly property int agendaRowH: 32
  readonly property int agendaRows: Math.min(5, popup.dayEvents.length)
  // a day with nothing on it is the one line that says so, and the field
  // (user, 2026-10-21: the empty row under it was padding for nothing)
  readonly property int agendaH: !Chronos.calReady && popup.dayTasks.length === 0 ? 52
    : popup.agendaRows === 0 ? 46 : 46 + popup.agendaRows * popup.agendaRowH + 10
  property string agendaNote: ""
  property bool agendaNoteBad: false
  function agendaSay(t, bad) { popup.agendaNote = t; popup.agendaNoteBad = !!bad; agendaNoteTimer.restart(); }
  Timer { id: agendaNoteTimer; interval: 2600; onTriggered: popup.agendaNote = "" }
  // the month in view, read as it changes (a beat after, so paging through
  // months asks for the one landed on)
  Timer { id: monthLoad; interval: 200; onTriggered: Chronos.loadMonth(popup.viewYear, popup.viewMonth) }
  onViewMonthChanged: monthLoad.restart()
  onViewYearChanged: monthLoad.restart()

  // ── the forecast the right pane is showing ───────────────────────────
  // The selected day if there is one in range, otherwise nothing — and with
  // nothing, the pane shows the live reading instead.
  readonly property var selForecast: Weather.dayFor(popup.selIso)
  readonly property bool showingNow: popup.selIsToday || popup.selForecast === null

  // Everything the forecast block binds to, resolved here rather than in the
  // tree. Weather.current is null until the first reply lands and the panes
  // keep their bindings live behind `visible`, so every read of it needs a
  // guard — one place for them, not fifteen.
  readonly property var wxNow: Weather.current
  readonly property var wxRow: popup.showingNow ? Weather.today : popup.selForecast
  readonly property int wxCode: popup.showingNow
    ? (popup.wxNow ? popup.wxNow.code : 0)
    : (popup.selForecast ? popup.selForecast.code : 0)
  readonly property bool wxIsDay: popup.showingNow
    ? (popup.wxNow ? popup.wxNow.isDay : true) : true
  readonly property string wxTemp: popup.showingNow
    ? (popup.wxNow ? Weather.fmt(popup.wxNow.temp) : "--")
    : Weather.fmt(popup.selForecast.hi)
  readonly property string wxLow: popup.showingNow
    ? "" : Weather.fmt(popup.selForecast.lo)
  readonly property string wxFeels:
    popup.wxNow ? Weather.fmt(popup.wxNow.feels) + Weather.unit : "--"
  readonly property string wxHumid:
    popup.wxNow ? popup.wxNow.humidity + "%" : "--"
  // A forecast day's own small print. Its low already sits beside the high,
  // so the row under it carries what the day adds: the chance of rain and how
  // long it is light (it used to repeat the low and print the rain twice).
  readonly property string wxPop:
    popup.selForecast ? (popup.selForecast.pop ?? 0) + "%" : "--"
  readonly property string wxDaylight: {
    const r = popup.wxRow ? new Date(popup.wxRow.sunrise) : null;
    const s = popup.wxRow ? new Date(popup.wxRow.sunset) : null;
    if (!r || !s || isNaN(r.getTime()) || isNaN(s.getTime())) return "--";
    const m = Math.max(0, Math.round((s - r) / 60000));
    return Math.floor(m / 60) + "h " + String(m % 60).padStart(2, "0") + "m";
  }
  readonly property string wxWind: popup.wxNow
    ? Math.round(popup.wxNow.wind) + " km/h " + Wx.windDir(popup.wxNow.windDeg)
    : "--"
  readonly property string wxSunrise:
    popup.wxRow ? Wx.hhmm(popup.wxRow.sunrise) : "--:--"
  readonly property string wxSunset:
    popup.wxRow ? Wx.hhmm(popup.wxRow.sunset) : "--:--"

  // an end of the twelve-hour curve: its hour and what it reads then — the
  // curve is scaled to its own extremes, so without the degrees a flat
  // evening and a 10° drop drew the same line
  function hourEnd(i) {
    const h = Weather.nextHours[i];
    if (!h) return "";
    return Wx.hhmm(h.time) + "  " + Weather.fmt(h.temp) + "°";
  }

  function roleColor(code) {
    const r = Wx.role(code);
    if (r === "sun") return Zenon.sand;
    if (r === "cloud") return Zenon.cyan;
    if (r === "rain") return Zenon.blue;
    if (r === "snow") return Zenon.white;
    if (r === "sleet") return Zenon.pink;
    if (r === "storm") return Zenon.magenta;
    return Zenon.muted;
  }

  // How long ago the forecast came in. Zero means it was restored from disk and
  // has not been refreshed this session, which is worth saying out loud rather
  // than dressing up as fresh.
  property double ageNow: Date.now()
  readonly property string age: {
    if (!Weather.ready) return "";
    if (Weather.fetched === 0) return "cached";
    const s = Math.max(0, Math.floor((popup.ageNow - Weather.fetched) / 1000));
    if (s < 60) return "just now";
    const m = Math.floor(s / 60);
    if (m < 60) return m + "m ago";
    return Math.floor(m / 60) + "h ago";
  }

  focusable: true

  Component.onCompleted: popup.goToday()

  HyprlandFocusGrab {
    id: grab
    windows: [ popup ]
    active: popup.shown
    onCleared: popup.closePopup()
  }

  // Keeps "today" and the forecast's age honest while the panel sits open —
  // only while it is open, since neither matters to anything else.
  Timer {
    interval: 30000
    repeat: true
    running: popup.shown
    onTriggered: {
      popup.ageNow = Date.now();
      const now = new Date();
      // a panel left open across midnight should move its own highlight
      if (Chr.isoOf(now) !== popup.todayIso) popup.today = now;
    }
  }

  IpcHandler {
    id: ipc
    target: "Chronos"

    function toggle() { popup.toggle(); }

    // Start a fresh timer of N minutes without opening anything — the form a
    // keybind wants. 0 means the default length.
    function pomodoro(minutes: int): string {
      const m = minutes > 0 ? minutes : Chronos.defaultMinutes;
      if (!Chronos.add("Pomodoro", m))
        return "not started: already " + Chronos.maxTimers + " timers";
      Chronos.toggle(Chronos.timers.length - 1);
      return "started " + m + "m";
    }

    // Open straight into naming a new timer, so it gets set up by hand here
    // rather than arriving as a default someone else picked.
    function create(): string {
      if (!popup.shown) popup.openPopup();
      // after openPopup's own callLater has handed the focus to bgRoot, so the
      // name field is what ends up holding it
      Qt.callLater(() => { if (popup.shown) popup.startNaming(-1); });
      return "naming";
    }

    // "Start timer" from a keybind or cynosure. No timers means make one;
    // exactly one idle timer means start it; any more than that is a choice,
    // and outside cynosure the place to make it is this panel. Cynosure asks
    // the question itself and calls startAt with the answer.
    function start(): string {
      if (Chronos.timers.length === 0) return ipc.create();
      const idle = [];
      for (let i = 0; i < Chronos.timers.length; ++i)
        if (!Chronos.timers[i].running) idle.push(i);
      if (idle.length === 1) return ipc.startAt(idle[0]);
      if (!popup.shown) popup.openPopup();
      return idle.length === 0 ? "all running" : "choose";
    }

    function startAt(index: int): string {
      const t = Chronos.timers[index];
      if (!t) return "no timer " + index;
      if (!t.running) Chronos.toggle(index);
      return "started " + t.label;
    }

    // stop everything that is counting, without deleting anything
    function halt(): string {
      for (let i = 0; i < Chronos.timers.length; ++i)
        if (Chronos.timers[i].running) Chronos.toggle(i);
      return "halted";
    }

    function weather(): string {
      Weather.refresh();
      return "refreshing " + (Weather.place !== "" ? Weather.place : "unknown place");
    }

    function status(): string {
      let s = "shown=" + popup.shown + " naming=" + popup.naming
        + " view=" + popup.viewYear + "-" + (popup.viewMonth + 1)
        + " sel=" + popup.selIso
        + " timers=" + Chronos.timers.length
        + " weather=" + (Weather.ready ? "ready"
            : (Weather.error !== "" ? Weather.error : "pending"));
      for (let i = 0; i < Chronos.timers.length; ++i) {
        const t = Chronos.timers[i];
        s += " [" + t.label + " " + t.minutes + "m run=" + t.running
          + " left=" + t.remaining + "]";
      }
      return s;
    }
  }

  function openPopup() {
    popup.shown = true;
    popup.collapsing = false;
    popup.naming = false;
    popup.nameTarget = -1;
    popup.goToday();
    popup.ageNow = Date.now();
    // opening is the moment someone actually wants to know, so this is where a
    // stale forecast gets replaced — the fifteen-minute poll is the background
    Weather.refreshIfStale();
    Chronos.calCheck(() => Chronos.loadMonth(popup.viewYear, popup.viewMonth));
    popup.playOpen();
    Qt.callLater(() => { if (popup.shown) bgRoot.forceActiveFocus(); });
  }

  function closePopup() {
    popup.collapsing = true;
    popup.naming = false;
    popup.playClose();
  }

  function toggle() {
    if (popup.shown) popup.closePopup();
    else popup.openPopup();
  }

  MouseArea {
    anchors.fill: parent
    z: 0
    onClicked: popup.closePopup()
  }

  LayerPanel {
    id: panel
    host: popup
    ground: bgRoot
    shadowRadius: popup.clipRadius
    width: Zenon.layerWidth(popup.panelWidth)
    height: popup.calcHeight()

    PanelGround {
      id: bgRoot
      radius: popup.clipRadius

      // Escape closes, because a layer that took the focus grab has to give it
      // back somehow. It is the only key this panel answers.
      Keys.onEscapePressed: (event) => {
        event.accepted = true;
        popup.closePopup();
      }

      Column {
        anchors.fill: parent

        // ── calendar | forecast ─────────────────────────────────────
        Item {
          id: body
          width: parent.width
          height: popup.bodyHeight

          // ── the calendar ─────────────────────────────────────────
          Item {
            id: calPane
            width: popup.paneW
            height: parent.height
            anchors.left: parent.left
            anchors.leftMargin: popup.sideMargin

            // Scrolling anywhere over the pane pages the month, and with shift
            // held, the year. The chevrons in the header do the same for anyone
            // who would rather click.
            WheelHandler {
              acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
              onWheel: (event) => {
                const d = event.angleDelta.y > 0 ? -1 : 1;
                if (event.modifiers & Qt.ShiftModifier) popup.stepYear(d);
                else popup.stepMonth(d);
              }
            }

            Column {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: 8

              // «  ‹  August 2026  ›  »  — month on the inner pair, year on the
              // outer, so paging a year is a click and not a chord
              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                height: 34
                spacing: 2

                Chevron { glyph: "«"; onActivated: popup.stepYear(-1) }
                Chevron { glyph: "‹"; onActivated: popup.stepMonth(-1) }

                Item {
                  width: 196
                  height: 34

                  Row {
                    anchors.centerIn: parent
                    height: 24
                    spacing: 8

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: Chr.monthName(popup.viewMonth)
                      color: headMa.pressed ? Zenon.white : Zenon.cyan
                      Behavior on color { ColorAnimation { duration: Zenon.fast } }
                      font.family: popup.face
                      font.weight: Font.Bold
                      font.pixelSize: Zenon.px(19)
                    }
                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: String(popup.viewYear)
                      color: Zenon.muted
                      font.family: popup.face
                      font.weight: Zenon.weight
                      font.pixelSize: Zenon.px(15)
                    }
                  }

                  MouseArea {
                    id: headMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: popup.goToday()
                  }
                }

                Chevron { glyph: "›"; onActivated: popup.stepMonth(1) }
                Chevron { glyph: "»"; onActivated: popup.stepYear(1) }
              }

              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                height: 22

                Repeater {
                  model: 7
                  delegate: Text {
                    required property int index
                    width: popup.cellW
                    height: 22
                    text: Chr.dayShort(index)
                    color: index >= 5 ? Zenon.muted : Zenon.keyInk
                    font.family: popup.face
                    font.weight: Font.Bold
                    font.pixelSize: Zenon.px(13)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                  }
                }
              }

              Grid {
                anchors.horizontalCenter: parent.horizontalCenter
                columns: 7
                columnSpacing: 0
                rowSpacing: 0

                Repeater {
                  model: popup.cells

                  delegate: Item {
                    id: dayCell
                    required property var modelData
                    required property int index
                    width: popup.cellW
                    height: popup.cellH

                    readonly property string iso: Chr.isoDay(
                      dayCell.modelData.y, dayCell.modelData.m, dayCell.modelData.d)
                    readonly property bool isToday: dayCell.iso === popup.todayIso
                    readonly property bool isSel: dayCell.iso === popup.selIso
                    readonly property bool weekend: dayCell.index % 7 >= 5
                    readonly property var forecast: Weather.dayFor(dayCell.iso)

                    Rectangle {
                      anchors.centerIn: parent
                      width: popup.cellW - 6
                      height: popup.cellH - 4
                      radius: Zenon.windowRadius
                      color: dayCell.isToday ? Zenon.cyan
                        : (dayCell.isSel ? Zenon.menuHi
                            : (dayMa.pressed ? Zenon.pressTile(false) : Zenon.alpha(Zenon.border, 0)))
                      border.color: (dayCell.isSel && !dayCell.isToday) ? Zenon.cyan : "transparent"
                      border.width: 1
                      Behavior on color { ColorAnimation { duration: Zenon.fast } }
                    }

                    Text {
                      anchors.centerIn: parent
                      anchors.verticalCenterOffset: dayCell.forecast ? -3 : 0
                      text: String(dayCell.modelData.d)
                      color: dayCell.isToday ? Zenon.black
                        : (!dayCell.modelData.cur ? Zenon.dimInk
                        : (dayCell.weekend ? Zenon.muted : Zenon.white))
                      font.family: popup.face
                      font.weight: dayCell.isToday ? Font.Black : Font.Bold
                      font.pixelSize: Zenon.px(15)
                    }

                    // A day the forecast reaches wears a dot in its condition's
                    // color, so the week ahead is readable off the grid itself
                    // without clicking through it day by day.
                    Rectangle {
                      anchors.horizontalCenter: parent.horizontalCenter
                      anchors.bottom: parent.bottom
                      anchors.bottomMargin: 5
                      width: 4
                      height: 4
                      radius: height / 2
                      visible: dayCell.forecast !== null
                      color: dayCell.isToday ? Zenon.black
                        : popup.roleColor(dayCell.forecast ? dayCell.forecast.code : 0)
                    }

                    // a day with something on it: a dot in the corner
                    Rectangle {
                      anchors.top: parent.top
                      anchors.right: parent.right
                      anchors.topMargin: 6
                      anchors.rightMargin: 8
                      width: 5
                      height: 5
                      radius: height / 2
                      visible: !!Chronos.byDay[dayCell.iso] || !!popup.taskDays[dayCell.iso]
                      color: dayCell.isToday ? Zenon.black : Zenon.yellow
                    }

                    MouseArea {
                      id: dayMa
                      anchors.fill: parent
                      hoverEnabled: true
                      onClicked: popup.pick(dayCell.modelData.y,
                        dayCell.modelData.m, dayCell.modelData.d)
                      // the calendar window, on that day (2026-10-28)
                      onDoubleClicked: if (popup.calendar) popup.calendar.day(Chr.isoDay(dayCell.modelData.y, dayCell.modelData.m, dayCell.modelData.d))
                    }
                  }
                }
              }

              // What is selected, spelled out, and the way back to today
              Item {
                width: parent.width
                height: 26

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: 12
                  anchors.verticalCenter: parent.verticalCenter
                  text: Chr.longDay(popup.selDate)
                  color: popup.selIsToday ? Zenon.cyan : Zenon.keyInk
                  Behavior on color { ColorAnimation { duration: Zenon.normal } }
                  font.family: popup.face
                  font.weight: Font.Bold
                  font.pixelSize: Zenon.px(13)
                }

                // spelled out: a calendar glyph alone did not say where it went
                DialogButton {
                  anchors.right: parent.right
                  anchors.rightMargin: 12
                  anchors.verticalCenter: parent.verticalCenter
                  label: "Today"
                  ink: Zenon.cyan
                  ready: !(popup.selIsToday && popup.viewMonth === popup.today.getMonth()
                    && popup.viewYear === popup.today.getFullYear())
                  onClicked: popup.goToday()
                }
              }
            }
          }

          Rectangle {
            anchors.left: calPane.right
            anchors.leftMargin: popup.splitGap
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: parent.height - popup.panePad * 2
            color: Zenon.border
          }

          // ── the forecast ─────────────────────────────────────────
          Item {
            id: wxPane
            anchors.left: calPane.right
            anchors.leftMargin: popup.splitGap * 2 + 1
            width: popup.paneW
            height: parent.height

            // ── nothing to show yet ─────────────────────────────
            Column {
              anchors.centerIn: parent
              spacing: 10
              visible: !Weather.ready

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Wx.icon("unknown")
                color: Zenon.muted
                font.family: popup.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(34)
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                // Switched off says so. An empty pane that only ever offers
                // "try again" would be blaming the network for a choice made
                // in the settings panel, and the button below would go on
                // failing silently for as long as it was pressed.
                text: Weather.disabled ? "The forecast is switched off"
                  : (Weather.loading ? "fetching the forecast…"
                  : (Weather.error !== "" ? Weather.error : "no forecast yet"))
                color: Zenon.muted
                font.family: popup.face
                font.weight: Font.Bold
                font.pixelSize: Zenon.px(15)
              }
              DialogButton {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !Weather.disabled
                label: Weather.located ? "Try again" : "Find me"
                ink: Zenon.cyan
                ready: !Weather.loading
                onClicked: Weather.refresh()
              }
            }

            // ── the reading, and the numbers around it ──────────
            // Anchored from the top, with the week pinned to the bottom
            // separately: the slack between them lands where nothing is, so
            // neither block can be pushed off the pane by a font metric.
            Column {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.topMargin: popup.panePad
              spacing: 10
              visible: Weather.ready

              // place, age, units, refresh
              Item {
                width: parent.width
                height: 26

                Row {
                  anchors.left: parent.left
                  anchors.leftMargin: 12
                  anchors.verticalCenter: parent.verticalCenter
                  height: 20
                  spacing: 8

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Weather.place !== "" ? Weather.place : "Here"
                    color: Zenon.cyan
                    font.family: popup.face
                    font.weight: Font.Bold
                    font.pixelSize: Zenon.px(16)
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: popup.age
                    color: Zenon.muted
                    font.family: popup.face
                    font.weight: Zenon.weight
                    font.pixelSize: Zenon.px(12)
                  }
                }

                // The units as the suite's switch, both on show: a glyph that
                // named the OTHER unit, and only spelled it out under the
                // pointer, read as a label for the one in use.
                Row {
                  anchors.right: parent.right
                  anchors.rightMargin: 12
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 6

                  Segments {
                    anchors.verticalCenter: parent.verticalCenter
                    textSize: Zenon.px(12)
                    options: [["c", "°C"], ["f", "°F"]]
                    current: Weather.fahrenheit ? "f" : "c"
                    onChose: (v) => { if ((v === "f") !== Weather.fahrenheit) Weather.toggleUnits(); }
                  }
                  DialogButton {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: true
                    label: Wx.icon("refresh")
                    ink: Weather.error !== "" ? Zenon.red : Zenon.accentMuted
                    ready: !Weather.loading
                    onClicked: Weather.refresh()
                  }
                }
              }

              // Now, or the selected day if one is picked. The same block
              // either way, so switching between them changes numbers rather
              // than layout.
              Item {
                width: parent.width
                height: 94

                Text {
                  id: bigGlyph
                  anchors.left: parent.left
                  anchors.leftMargin: 8
                  anchors.verticalCenter: parent.verticalCenter
                  width: 74
                  horizontalAlignment: Text.AlignHCenter
                  text: Wx.glyph(popup.wxCode, popup.wxIsDay)
                  color: popup.roleColor(popup.wxCode)
                  Behavior on color { ColorAnimation { duration: Zenon.normal } }
                  font.family: popup.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(52)
                }

                Column {
                  anchors.left: bigGlyph.right
                  anchors.leftMargin: 4
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 2

                  Row {
                    height: 38
                    spacing: 4

                    // The reading on its own unlit face, the way the bar's
                    // clock and the countdowns are drawn: every segment lit
                    // behind the live digits, which is literally what the panel
                    // of a real thermometer display is doing.
                    Item {
                      anchors.bottom: parent.bottom
                      anchors.bottomMargin: 2
                      width: bigTemp.implicitWidth
                      height: bigTemp.implicitHeight

                      Text {
                        anchors.centerIn: parent
                        text: Helpers.ghostText(popup.wxTemp)
                        color: Zenon.trough(Zenon.white)
                        font.family: Zenon.clockFamily
                        font.weight: Font.Bold
                        font.pixelSize: Zenon.px(32)
                      }
                      Text {
                        id: bigTemp
                        anchors.centerIn: parent
                        text: popup.wxTemp
                        color: Zenon.white
                        font.family: Zenon.clockFamily
                        font.weight: Font.Bold
                        font.pixelSize: Zenon.px(32)
                      }
                    }
                    Text {
                      anchors.bottom: parent.bottom
                      anchors.bottomMargin: 9
                      text: Weather.unit
                      color: Zenon.keyInk
                      font.family: popup.face
                      font.weight: Font.Bold
                      font.pixelSize: Zenon.px(15)
                    }
                    Text {
                      anchors.bottom: parent.bottom
                      anchors.bottomMargin: 9
                      visible: !popup.showingNow
                      text: "  ↓ " + popup.wxLow
                      color: Zenon.blue
                      font.family: popup.face
                      font.weight: Font.Bold
                      font.pixelSize: Zenon.px(15)
                    }
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: Wx.label(popup.wxCode)
                    color: Zenon.keyInk
                    font.family: popup.face
                    font.weight: Font.Bold
                    font.pixelSize: Zenon.px(15)
                  }

                  Text {
                    text: popup.showingNow
                      ? Chr.longDay(popup.today) : Chr.longDay(popup.selDate)
                    color: Zenon.muted
                    font.family: popup.face
                    font.weight: Zenon.weight
                    font.pixelSize: Zenon.px(12)
                  }
                }

                Column {
                  anchors.right: parent.right
                  anchors.rightMargin: 12
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 8

                  Reading {
                    glyph: Wx.icon("sunrise")
                    text: popup.wxSunrise
                  }
                  Reading {
                    glyph: Wx.icon("sunset")
                    text: popup.wxSunset
                  }
                }
              }

              // the three numbers under it
              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 20

                Reading {
                  glyph: Wx.icon("thermo")
                  visible: popup.showingNow
                  text: popup.wxFeels
                  hint: "feels like"
                }
                Reading {
                  glyph: Wx.icon("humidity")
                  visible: popup.showingNow
                  text: popup.wxHumid
                  hint: "humidity"
                }
                Reading {
                  glyph: Wx.icon("wind")
                  visible: popup.showingNow
                  text: popup.wxWind
                  hint: "wind"
                }
                Reading {
                  glyph: Wx.icon("umbrella")
                  visible: !popup.showingNow
                  text: popup.wxPop
                  hint: "chance of rain"
                }
                Reading {
                  glyph: Wx.icon("sunrise")
                  visible: !popup.showingNow
                  text: popup.wxDaylight
                  hint: "daylight"
                }
              }

              // ── the next twelve hours ─────────────────────────
              Item {
                width: parent.width
                height: 42
                visible: Weather.hourlyCurve.length >= 2

                Sparkline {
                  anchors.left: parent.left
                  anchors.leftMargin: 80
                  anchors.right: parent.right
                  anchors.rightMargin: 80
                  anchors.top: parent.top
                  height: 28
                  values: Weather.hourlyCurve
                  lineColor: Zenon.sand
                  fillColor: Zenon.sand
                  fillOpacity: 0.16
                  maxPoints: 12
                }

                // The curve is normalized to its own extremes, so the hours
                // that make it readable have to sit beside it.
                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: 12
                  anchors.top: parent.top
                  text: popup.hourEnd(0)
                  color: Zenon.muted
                  font.family: popup.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(11)
                }
                Text {
                  anchors.right: parent.right
                  anchors.rightMargin: 12
                  anchors.top: parent.top
                  text: popup.hourEnd(Weather.nextHours.length - 1)
                  color: Zenon.muted
                  font.family: popup.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(11)
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.bottom: parent.bottom
                  text: "Next 12 hours"
                  color: Zenon.muted
                  font.family: popup.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(11)
                }
              }
            }

            // ── the week ────────────────────────────────────────
            // Clicking one moves the calendar's selection to it, which is the
            // same act as clicking that day in the grid — one selected date,
            // reachable from either pane.
            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: popup.panePad
              spacing: 0
              visible: Weather.ready

              Repeater {
                model: Weather.days

                delegate: Item {
                  id: dayStrip
                  required property var modelData
                  required property int index
                  width: Math.floor(popup.gridW / 7)
                  // Sized by its own content, not by a number that has to be
                  // kept in step with four font sizes by hand — at a fixed 66
                  // the column overflowed the cell and the selected day's
                  // border cut its low temperature in half.
                  height: stripCol.implicitHeight + 14

                  readonly property bool isSel: dayStrip.modelData.date === popup.selIso
                  readonly property bool isToday: dayStrip.modelData.date === popup.todayIso
                  // noon, so a DST shift cannot land the parse on the previous day
                  readonly property var when: new Date(dayStrip.modelData.date + "T12:00:00")

                  Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: Zenon.windowRadius
                    color: dayStrip.isSel ? Zenon.menuHi
                      : (stripMa.pressed ? Zenon.pressTile(false) : Zenon.alpha(Zenon.border, 0))
                    border.color: dayStrip.isSel ? Zenon.cyan : "transparent"
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: Zenon.fast } }
                  }

                  Column {
                    id: stripCol
                    anchors.centerIn: parent
                    spacing: 1

                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: dayStrip.isToday ? "Today"
                        : Chr.dayShort(Chr.weekIndex(dayStrip.when))
                      color: dayStrip.isToday ? Zenon.cyan : Zenon.muted
                      font.family: popup.face
                      font.weight: Font.Bold
                      font.pixelSize: Zenon.px(11)
                    }
                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: Wx.glyph(dayStrip.modelData.code, true)
                      color: popup.roleColor(dayStrip.modelData.code)
                      font.family: popup.face
                      font.weight: Zenon.weight
                      font.pixelSize: Zenon.px(20)
                    }
                    // degrees marked: bare, a column of 31 / 29 / 28 under
                    // weekday names read as the dates
                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: Weather.fmt(dayStrip.modelData.hi) + "°"
                      color: Zenon.white
                      font.family: popup.face
                      font.weight: Font.Bold
                      font.pixelSize: Zenon.px(13)
                    }
                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: Weather.fmt(dayStrip.modelData.lo) + "°"
                      color: Zenon.muted
                      font.family: popup.face
                      font.weight: Zenon.weight
                      font.pixelSize: Zenon.px(11)
                    }
                  }

                  MouseArea {
                    id: stripMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: popup.pick(dayStrip.when.getFullYear(),
                      dayStrip.when.getMonth(), dayStrip.when.getDate())
                  }
                }
              }
            }
          }
        }
        Rectangle {
          width: parent.width
          height: 1
          color: Zenon.border
        }

        // ── the day's events ────────────────────────────────────────
        Item {
          id: agenda
          width: parent.width
          height: popup.agendaH

          // not set up: what it takes, and the button
          Row {
            visible: !Chronos.calReady && popup.dayTasks.length === 0
            // centered in the strip (user, 2026-10-21)
            anchors.centerIn: parent
            spacing: 12
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "\u{F00F0}"
              color: Zenon.muted
              font.family: popup.face
              font.pixelSize: Zenon.px(16)
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "Where should your calendar live?"
              color: Zenon.muted
              font.family: popup.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(13)
            }
            // asked first, installed after (user, 2026-10-28): here
            // installs khal; online opens the window's accounts sheet,
            // which installs what the account needs once it is given
            DialogButton {
              anchors.verticalCenter: parent.verticalCenter
              label: "On this computer"
              ink: Zenon.cyan
              onClicked: if (!Chronos.setupCalendar((ok) => popup.agendaSay(ok ? "Your calendar is ready" : "Not set up", !ok)))
                popup.agendaSay("Ceres is busy \u2014 try again in a moment", true)
            }
            DialogButton {
              anchors.verticalCenter: parent.verticalCenter
              visible: !!popup.calendar
              label: "Online account\u2026"
              ink: Zenon.cyan
              onClicked: popup.calendar.accounts()
            }
          }

          // set up: the day's events, and a line for a new one (and, set
          // up or not, the day's tasks from Clio)
          Item {
            visible: Chronos.calReady || popup.dayTasks.length > 0
            anchors.fill: parent
            anchors.leftMargin: popup.sideMargin
            anchors.rightMargin: popup.sideMargin

            Text {
              id: agendaHead
              x: 4
              y: 14
              text: popup.agendaNote !== "" ? popup.agendaNote
                : popup.dayEvents.length === 0 ? "Nothing on " + Chr.longDay(popup.selDate)
                : popup.agendaCount() + " on " + Chr.longDay(popup.selDate)
              color: popup.agendaNote !== "" ? (popup.agendaNoteBad ? Zenon.red : Zenon.cyan) : Zenon.keyInk
              font.family: popup.face
              font.weight: Font.Bold
              font.pixelSize: Zenon.px(13)
            }
            // the Calendar window, on the day chosen here
            DialogButton {
              id: openCal
              visible: Chronos.calReady && !!popup.calendar
              glyph: true
              label: "\u{EAB0}"
              implicitHeight: 28
              anchors.right: addBox.left
              anchors.rightMargin: 8
              anchors.verticalCenter: agendaHead.verticalCenter
              onClicked: popup.calendar.day(popup.selIso)
            }
            // the line a new event is typed into
            Rectangle {
              id: addBox
              visible: Chronos.calReady
              anchors.right: parent.right
              anchors.verticalCenter: agendaHead.verticalCenter
              width: Math.min(440, parent.width * 0.55)
              height: 28
              radius: Zenon.windowRadius
              color: Zenon.wash(0.05)
              border.width: 1
              border.color: Zenon.border
              TextInput {
                id: addField
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 28
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                color: Zenon.white
                selectionColor: Zenon.cyan
                selectedTextColor: Zenon.onAccent
                font.family: popup.face
                font.pixelSize: Zenon.px(13)
                cursorDelegate: Caret { field: addField }
                enabled: !Chronos.calBusy
                Text {
                  anchors.fill: parent
                  verticalAlignment: Text.AlignVCenter
                  visible: addField.text === ""
                  text: "Add \u2014 Lunch with Sam fri 1pm @ Luigi's"
                  color: Zenon.muted
                  font: addField.font
                  elide: Text.ElideRight
                }
                function add() {
                  Chronos.addQuick(addField.text, popup.selIso, (ok, w) => { popup.agendaSay(w, !ok); if (ok) addField.text = ""; });
                }
                Keys.onReturnPressed: (e) => { e.accepted = true; addField.add(); }
                Keys.onEnterPressed: (e) => { e.accepted = true; addField.add(); }
                Keys.onEscapePressed: (e) => {
                  e.accepted = true;
                  if (addField.text !== "") addField.text = "";
                  else bgRoot.forceActiveFocus();
                }
              }
              ClearChip {
                size: Zenon.px(15)
                shown: addField.text !== ""
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                onClicked: addField.text = ""
              }
              HeldRing { anchors.fill: parent; radius: parent.radius; z: 10; on: addField.activeFocus }
            }

            ListView {
              id: eventList
              anchors.top: agendaHead.bottom
              anchors.topMargin: 12
              width: parent.width
              height: popup.agendaRows * popup.agendaRowH
              clip: true
              model: popup.dayEvents.length
              ElasticScroll { view: eventList }
              delegate: Item {
                id: evRow
                required property int index
                readonly property var e: popup.dayEvents[index] || null
                width: eventList.width
                height: popup.agendaRowH
                // its color, the Calendar's (2026-10-28): a task a hollow box
                Rectangle {
                  id: evDot
                  x: 6
                  anchors.verticalCenter: parent.verticalCenter
                  width: 8
                  height: 8
                  radius: evRow.e && evRow.e.task ? 1.5 : 4
                  readonly property color ink: evRow.e && !evRow.e.task ? Clio.ink(Chronos.hueOf(evRow.e)) : Zenon.accentMuted
                  color: evRow.e && evRow.e.task ? "transparent" : evDot.ink
                  border.width: evRow.e && evRow.e.task ? 1.2 : 0
                  border.color: evDot.ink
                }
                Text {
                  id: evTime
                  x: 22
                  width: 110
                  anchors.verticalCenter: parent.verticalCenter
                  text: Chr.eventTime(evRow.e)
                  color: evDot.ink
                  font.family: popup.face
                  font.weight: Font.Bold
                  font.pixelSize: Zenon.px(13)
                }
                Text {
                  anchors.left: evTime.right
                  anchors.right: evRemove.left
                  anchors.rightMargin: 12
                  anchors.verticalCenter: parent.verticalCenter
                  elide: Text.ElideRight
                  textFormat: Text.StyledText
                  text: !evRow.e ? "" : Strings.escapeHtml(evRow.e.title)
                    + (evRow.e.location ? '  <font color="' + Zenon.hex(Zenon.muted) + '">' + Strings.escapeHtml(evRow.e.location) + "</font>" : "")
                    + (evRow.e.repeats ? '  <font color="' + Zenon.hex(Zenon.muted) + '">\u{F0456}</font>' : "")
                  color: Zenon.white
                  font.family: popup.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(14)
                }
                // removing a repeating event would take every one of them:
                // that is khal's own editor's job, not a stray click's
                ClearChip {
                  id: evRemove
                  size: Zenon.px(15)
                  anchors.right: parent.right
                  // clear of the scrollbar's strip, when there is one
                  anchors.rightMargin: 18
                  anchors.verticalCenter: parent.verticalCenter
                  shown: !!evRow.e && !evRow.e.repeats && !evRow.e.task
                  onClicked: Chronos.removeEvent(evRow.e.uid, (ok, w) => popup.agendaSay(ok ? "Removed \u201C" + evRow.e.title + "\u201D" : w, !ok))
                }
                // a task: its note, opened at it — and pressed like a row,
                // since nothing else says this line goes anywhere
                Rectangle {
                  anchors.fill: parent
                  z: -1
                  radius: Zenon.windowRadius
                  color: taskMa.pressed ? Zenon.pressTile(false) : Zenon.alpha(Zenon.border, 0)
                }
                // a task opens its note at it; an event, in the Calendar
                MouseArea {
                  id: taskMa
                  anchors.fill: parent
                  anchors.rightMargin: evRemove.shown ? evRemove.width + 12 : 0
                  visible: !!evRow.e && (!!evRow.e.task || !!popup.calendar)
                  onClicked: {
                    if (evRow.e.task) { if (Clio.app) Clio.app.openTask(evRow.e.task.id, evRow.e.task.h); return; }
                    popup.calendar.event(evRow.e);
                  }
                }
              }
            }
            // only with more than fits: along the right edge it lay over
            // each row's ×, and took its clicks (user, 2026-10-28: "the
            // remove event in quick access doesn't do anything")
            Scrollbar { flick: eventList; visible: eventList.visible && eventList.contentHeight > eventList.height + 1
                        anchors.right: eventList.right; anchors.top: eventList.top; anchors.bottom: eventList.bottom }
          }
        }
        Rectangle {
          width: parent.width
          height: 1
          color: Zenon.border
        }

        // ── pomodoro, across both halves ────────────────────────────
        Item {
          id: band
          width: parent.width
          height: popup.bandHeight

          Rectangle {
            anchors.fill: parent
            color: Zenon.headBg
          }

          Row {
            x: popup.sideMargin
            y: popup.bandPadTop
            width: popup.bandWidth
            height: popup.bandInner
            spacing: popup.cellGap
            // out of the way while a name is typed over them: the layer is
            // glass, so no ground laid on top hides them completely
            opacity: popup.naming ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }

            // the cells, in balanced rows
            Column {
              width: popup.cellsWidth
              spacing: popup.cellGap

              // an empty band is one full-width invitation, which is the only
              // thing worth putting there
              Rectangle {
                visible: !popup.hasTimers
                width: parent.width
                height: popup.emptyH
                radius: Zenon.radiusCard
                color: emptyMa.pressed ? Zenon.pressTile(false) : "transparent"
                border.color: Zenon.border
                border.width: 1
                Behavior on color { ColorAnimation { duration: Zenon.fast } }
                Behavior on border.color { ColorAnimation { duration: Zenon.fast } }

                Row {
                  anchors.centerIn: parent
                  spacing: 14

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: popup.glyphTimer
                    color: emptyMa.pressed ? Zenon.cyan : Zenon.accentMuted
                    Behavior on color { ColorAnimation { duration: Zenon.fast } }
                    font.family: popup.face
                    font.weight: Zenon.weight
                    font.pixelSize: Zenon.px(20)
                  }
                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    EmptyState { text: "No timers — click to start one" }
                    // the gestures, said once where they cannot be found by
                    // looking: nothing on a cell shows that it scrolls
                    Text {
                      text: "Click a timer to start or pause it \u00B7 scroll it to change its length"
                      color: Zenon.muted
                      font.family: popup.face
                      font.weight: Zenon.weight
                      font.pixelSize: Zenon.px(11)
                    }
                  }
                }

                MouseArea {
                  id: emptyMa
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: popup.startNaming(-1)
                }
              }

              Repeater {
                model: popup.bandLayout

                delegate: Row {
                  id: cellRow
                  required property var modelData
                  readonly property int count: cellRow.modelData.length
                  width: popup.cellsWidth
                  height: popup.timerH
                  spacing: popup.cellGap

                  Repeater {
                    model: cellRow.modelData

                    delegate: TimerCell {
                      required property int modelData
                      slot: modelData
                      width: popup.cellWidthFor(cellRow.count)
                      height: popup.timerH
                    }
                  }
                }
              }
            }

          }

          // ── naming ────────────────────────────────────────────────
          // Across the band rather than inside one cell: half the time the
          // timer being named does not exist yet, and a field where a cell is
          // about to appear is clearer than one squeezed into a corner.
          Rectangle {
            id: nameStrip
            anchors.fill: parent
            // the band's own head strip; the cells fade out beneath it
            color: Zenon.headBg
            visible: opacity > 0.01
            opacity: popup.naming ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }

            // swallows clicks, so the band underneath cannot be poked at while
            // a name is half typed
            MouseArea { anchors.fill: parent }

            Row {
              anchors.centerIn: parent
              width: popup.bandWidth - 40
              height: 40
              spacing: 10

              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 22
                horizontalAlignment: Text.AlignHCenter
                text: popup.nameTarget < 0 ? popup.glyphTimer : popup.glyphRename
                color: Zenon.cyan
                font.family: popup.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(17)
              }

              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 264
                height: 34
                radius: Zenon.windowRadius
                color: Zenon.selBg
                border.color: Zenon.border
                border.width: 1

                TextInput {
                  id: nameInput

                  cursorDelegate: Caret { field: nameInput }
                  anchors.fill: parent
                  anchors.leftMargin: 12
                  anchors.rightMargin: 12
                  verticalAlignment: TextInput.AlignVCenter
                  color: Zenon.white
                  selectionColor: Zenon.cyan
                  selectedTextColor: Zenon.onAccent
                  selectByMouse: true
                  font.family: popup.face
                  font.weight: Font.Bold
                  font.pixelSize: Zenon.px(15)
                  // Handled as key events, not through onAccepted: that signal
                  // does not consume the keypress, so Return reached the panel
                  // behind and was read as "start the timer" — every timer
                  // created this way started counting the moment it was named.
                  Keys.onReturnPressed: (event) => {
                    event.accepted = true;
                    popup.commitName();
                  }
                  Keys.onEnterPressed: (event) => {
                    event.accepted = true;
                    popup.commitName();
                  }
                  Keys.onEscapePressed: (event) => {
                    event.accepted = true;
                    popup.cancelName();
                  }

                  Text {
                    anchors.fill: parent
                    visible: nameInput.text === ""
                    text: popup.nameTarget < 0
                      ? "Name it, or just take the default" : "new name"
                    color: Zenon.muted
                    font: nameInput.font
                    verticalAlignment: Text.AlignVCenter
                  }
                }
                // focused for typing: terminus' held ring (user, 2026-10-11 — every
                // text field wears it, its own border staying neutral)
                HeldRing { anchors.fill: parent; radius: parent.radius; z: 10; on: nameInput.activeFocus }
              }

              // Naming is the one place a key is unavoidable; finishing it
              // still is not, so both ways out are buttons too.
              // Cancel left of the verb, the verb the default answer — the
              // confirmation sheets' order
              DialogButton {
                anchors.verticalCenter: parent.verticalCenter
                label: "Cancel"
                onClicked: popup.cancelName()
              }
              DialogButton {
                anchors.verticalCenter: parent.verticalCenter
                label: popup.nameTarget < 0 ? "Create" : "Rename"
                ink: Zenon.green
                primary: true
                onClicked: popup.commitName()
              }
            }
          }
        }

      }
    }
  }

  // ── the pieces ─────────────────────────────────────────────────────────
  // Inline components are only legal at the document root, which is why these
  // live down here rather than beside the things that use them.

  // One pomodoro. Click it to start or stop, scroll it to change its length,
  // and the buttons on hover add one, rename, reset and remove it.
  //
  // Two lines: the play state and name on top with the tools at its right
  // end, the countdown under it with the length stepper at its right end.
  // The tools only ever compete with the name, which elides — the countdown
  // and the stepper always have their room.
  //
  // A ClippingRectangle rather than a Rectangle with clip: true — Qt's own clip
  // is RECTANGULAR and knows nothing about the radius, so the drain wash and
  // the progress rule, both square and both painted to the edge, filled in the
  // cell's rounded corners behind them.
  component TimerCell: ClippingRectangle {
    id: cell
    required property int slot
    readonly property var t: Chronos.timers[cell.slot] ?? null
    readonly property bool running: cell.t !== null && cell.t.running
    readonly property bool armed: cell.t !== null && cell.t.remaining > 0
    readonly property int total: cell.t !== null ? Math.max(1, cell.t.minutes * 60) : 1
    readonly property int remain: cell.t !== null
      ? (cell.t.remaining > 0 ? cell.t.remaining : cell.total) : 0
    // idle reads as a full dial rather than an empty one: the length is set and
    // the whole of it is still ahead of you
    readonly property real frac: Math.max(0, Math.min(1, cell.remain / cell.total))
    readonly property color accent: cell.running ? Zenon.green
      : (cell.armed ? Zenon.sand : Zenon.cyan)
    readonly property bool showTools: cellHover.hovered || toolsHover.hovered

    radius: Zenon.radiusCard
    color: cellMa.pressed ? Zenon.pressTile(cell.running) : Zenon.panelBg
    border.color: cell.running
      ? Qt.rgba(cell.accent.r, cell.accent.g, cell.accent.b, 0.55) : Zenon.surface
    border.width: 1
    Behavior on color { ColorAnimation { duration: Zenon.fast } }
    Behavior on border.color { ColorAnimation { duration: Zenon.normal } }

    // Hover through a HANDLER, not a MouseArea. A hoverEnabled MouseArea over
    // the whole cell is the topmost thing in it and takes the pointer for
    // itself, so the buttons inside never lit and never got their clicks. A
    // HoverHandler reports the pointer without consuming it.
    HoverHandler { id: cellHover }

    // And the cell's own click target is declared FIRST, which in QML means
    // BOTTOM: every button below is a later sibling, so it sits above this and
    // takes its own clicks. Only the bare parts of the cell reach here.
    MouseArea {
      id: cellMa
      anchors.fill: parent
      onClicked: Chronos.toggle(cell.slot)
    }

    // the drain: a wash across the cell that shrinks with the countdown
    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: parent.width * cell.frac
      color: Qt.rgba(cell.accent.r, cell.accent.g, cell.accent.b,
        cell.running ? 0.13 : 0.06)
      Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.Linear } }
    }

    // ── top line: state, name, tools ──────────────────────────────────
    // A hover reveal on purpose (user, 2026-10-24: kept over always shown).
    // The tools are always LAID OUT, only their opacity moves, so nothing
    // shifts as the pointer enters; `enabled` follows the hover, so a faded
    // button cannot be clicked.
    Row {
      id: cellTools
      anchors.right: parent.right
      anchors.rightMargin: 8
      anchors.verticalCenter: cellName.verticalCenter
      spacing: 4
      opacity: cell.showTools ? 1 : 0
      enabled: cell.showTools
      Behavior on opacity { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }

      HoverHandler { id: toolsHover }

      // Adding sits FIRST so the destructive one stays at the far end. A
      // TinyButton like its neighbours rather than an AddChip: the row is one
      // set of controls and reads as one (user, 2026-10-24: "keep them
      // uniform")
      TinyButton {
        glyph: popup.glyphAdd
        visible: Chronos.timers.length < Chronos.maxTimers
        onActivated: popup.startNaming(-1)
      }
      TinyButton {
        glyph: popup.glyphRename
        onActivated: popup.startNaming(cell.slot)
      }
      TinyButton {
        glyph: popup.glyphReset
        dimmed: !cell.running && !cell.armed
        onActivated: Chronos.reset(cell.slot)
      }
      TinyButton {
        glyph: popup.glyphRemove
        onActivated: Chronos.remove(cell.slot)
      }
    }

    // what a click on the cell will do, drawn as what it is doing: paused or
    // idle shows play, counting shows pause
    Text {
      id: cellState
      anchors.left: parent.left
      anchors.leftMargin: 10
      anchors.verticalCenter: cellName.verticalCenter
      text: cell.running ? popup.glyphPause : popup.glyphPlay
      color: cell.accent
      Behavior on color { ColorAnimation { duration: Zenon.normal } }
      font.family: popup.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
    }

    Text {
      textFormat: Text.PlainText
      id: cellName
      anchors.left: cellState.right
      anchors.leftMargin: 6
      anchors.right: cellTools.left
      anchors.rightMargin: 6
      y: 7
      elide: Text.ElideRight
      text: cell.t !== null ? cell.t.label : ""
      color: cell.running ? cell.accent : Zenon.white
      Behavior on color { ColorAnimation { duration: Zenon.normal } }
      font.family: popup.face
      font.weight: Font.Bold
      font.pixelSize: Zenon.px(13)
    }

    // ── bottom line: countdown, stepper ───────────────────────────────
    // the countdown, over its own unlit face
    Item {
      id: cellClock
      anchors.left: parent.left
      anchors.leftMargin: 10
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 7
      width: liveTime.implicitWidth
      height: liveTime.implicitHeight

      Text {
        anchors.centerIn: parent
        text: Helpers.ghostText(Chr.clock(cell.remain))
        color: Zenon.trough(cell.accent)
        font.family: Zenon.clockFamily
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(20)
      }
      Text {
        id: liveTime
        anchors.centerIn: parent
        text: Chr.clock(cell.remain)
        color: cell.accent
        Behavior on color { ColorAnimation { duration: Zenon.normal } }
        font.family: Zenon.clockFamily
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(20)
      }
    }

    // The length, as a stepper. It is also what the scroll wheel over the cell
    // is driving, so the number the wheel moves is always on screen.
    Row {
      anchors.right: parent.right
      anchors.rightMargin: 8
      anchors.verticalCenter: cellClock.verticalCenter
      spacing: 2

      TinyButton {
        glyph: "‹"
        onActivated: Chronos.bump(cell.slot, -1)
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: 34
        horizontalAlignment: Text.AlignHCenter
        text: (cell.t !== null ? cell.t.minutes : 0) + "m"
        color: Zenon.keyInk
        font.family: popup.face
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(13)
      }
      TinyButton {
        glyph: "›"
        onActivated: Chronos.bump(cell.slot, 1)
      }
    }

    // the same countdown as a rule along the bottom edge, for the glance that
    // does not stop to read digits
    Rectangle {
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      width: parent.width * cell.frac
      height: 3
      color: cell.accent
      opacity: (cell.running || cell.armed) ? 1 : 0.35
      Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.Linear } }
    }

    // Scroll to lengthen or shorten, five minutes at a time with shift. On the
    // cell rather than on the number, so it works wherever the pointer is.
    WheelHandler {
      acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
      onWheel: (event) => {
        const step = (event.modifiers & Qt.ShiftModifier) ? 5 : 1;
        Chronos.bump(cell.slot, event.angleDelta.y > 0 ? step : -step);
      }
    }
  }

  // A small square button. `dimmed` is for one that is currently pointless.
  //
  // No outline: four boxed buttons in a row read as a strip of chrome. Lit
  // while PRESSED, not under the pointer — the suite's buttons answer no
  // hover (2026-10-11). One ink for all of them, rename and remove alike
  // (user, 2026-10-24): the press is the suite's button press, not a color
  // per verb.
  component TinyButton: Rectangle {
    id: tiny
    property string glyph: ""
    property bool dimmed: false
    signal activated()

    readonly property bool lit: tinyMa.pressed && !tiny.dimmed

    width: 20
    height: 20
    radius: Zenon.windowRadius
    color: tiny.lit ? Zenon.pressFill : Zenon.alpha(Zenon.pressFill, 0)
    opacity: tiny.dimmed ? Zenon.disabledDim : 1
    Behavior on color { ColorAnimation { duration: Zenon.fast } }
    Behavior on opacity { NumberAnimation { duration: Zenon.fast } }

    Text {
      anchors.centerIn: parent
      text: tiny.glyph
      color: Zenon.keyInk
      Behavior on color { ColorAnimation { duration: Zenon.fast } }
      font.family: popup.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(12)
    }

    MouseArea {
      id: tinyMa
      anchors.fill: parent
      onClicked: if (!tiny.dimmed) tiny.activated()
    }
  }

  // glyph, value, and a word under it — the forecast's small print
  component Reading: Row {
    id: reading
    property string glyph: ""
    property string text: ""
    property string hint: ""

    // A glyph and the number it labels are two things, not one word — at 5 the
    // pair read as a single smudge
    spacing: 13

    // Uncolored. The glyph is a label for the number beside it, not a reading
    // of its own, and five different inks along one row turned the small print
    // into a paintbox. The condition glyph and the week strip still carry the
    // palette, because there the color IS the information.
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: reading.glyph
      color: Zenon.keyInk
      font.family: popup.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(17)
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0

      Text {
        textFormat: Text.PlainText
        text: reading.text
        color: Zenon.white
        font.family: popup.face
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(13)
      }
      Text {
        visible: reading.hint !== ""
        text: reading.hint
        color: Zenon.muted
        font.family: popup.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(10)
      }
    }
  }

  // A month or year chevron. Big enough to hit without aiming.
  component Chevron: Item {
    id: chev
    property string glyph: ""
    signal activated()

    width: 26
    height: 34

    Text {
      anchors.centerIn: parent
      text: chev.glyph
      color: chevMa.pressed ? Zenon.cyan : Zenon.muted
      Behavior on color { ColorAnimation { duration: Zenon.fast } }
      font.family: popup.face
      font.weight: Font.Bold
      font.pixelSize: Zenon.px(18)
    }

    MouseArea {
      id: chevMa
      anchors.fill: parent
      hoverEnabled: true
      onClicked: chev.activated()
    }
  }
}

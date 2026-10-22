// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// SCREEN TIME — Kairos' window. A day or a week, chosen in the head; the
// time across it as bars (the day's hours, the week's days); under that,
// every app it went to, most first.
//
//   ← →      a day (a week) back or on      t   today
//   d  w     day · week                     esc closes
//
// A week's bar is a way into that day. "Forget" (the foot) empties every
// file, asked first.

import QtQuick
import Quickshell
import "../morpheus"
import "../terminus"
import "kairos.js" as K

FloatingWindow {
  id: kw
  title: "kairos"
  color: Zenon.alpha(Zenon.layerBg, 0)
  implicitWidth: 960
  implicitHeight: 720
  minimumSize: Qt.size(720, 520)

  property var mgr: null

  onVisibleChanged: if (!kw.visible) Qt.callLater(() => { if (kw.mgr) kw.mgr.retire(kw); kw.destroy(); })
  onClosed: kw.visible = false

  readonly property int headH: 60
  property string view: "day"
  // the day the window is on: the day itself, or the last of its week
  property var at: new Date()
  readonly property string atKey: K.dayKey(kw.at)
  readonly property bool atToday: kw.atKey === K.dayKey(new Date())

  function go(v) {
    if (v === "day" || v === "week") kw.view = v;
    Qt.callLater(() => keys.forceActiveFocus());
  }
  function step(n) {
    const d = K.addDays(kw.at, n * (kw.view === "week" ? 7 : 1));
    if (d.getTime() > Date.now()) return;
    kw.at = d;
  }
  function today() { kw.at = new Date(); }

  // what is on screen, re-asked as Kairos counts (it bumps revision)
  readonly property var span: {
    Kairos.revision;
    return kw.view === "week" ? Kairos.weekSum(kw.at) : (Kairos.day(kw.atKey) || null);
  }
  readonly property var weekDays: { Kairos.revision; return Kairos.week(kw.at); }
  readonly property real totalSecs: K.total(kw.span)
  readonly property var apps: K.topApps(kw.span, 0)
  // the bars: 24 hours, or 7 days
  readonly property var bars: kw.view === "week"
    ? kw.weekDays.map((d) => ({ v: d.total, label: Qt.locale().dayName(d.date.getDay(), Locale.ShortFormat), key: d.key }))
    : (kw.span ? kw.span.hours : K.emptyDay().hours).map((v, h) => ({ v: v, label: h % 6 === 0 ? String(h) : "", key: "" }))
  readonly property real barMax: Math.max(kw.view === "week" ? 3600 : 600, ...kw.bars.map((b) => b.v))

  function headWords() {
    if (kw.view === "week") {
      const from = K.addDays(kw.at, -6);
      return Qt.locale().toString(from, "d MMM") + " – " + Qt.locale().toString(kw.at, "d MMM");
    }
    if (kw.atToday) return "Today";
    if (K.dayKey(K.addDays(new Date(), -1)) === kw.atKey) return "Yesterday";
    return Qt.locale().toString(kw.at, "dddd, d MMMM");
  }

  // ── KEYS ──
  Item {
    id: keys
    focus: true
    Keys.onPressed: (e) => {
      e.accepted = true;
      if (forget.shown) {
        if (e.key === Qt.Key_Escape) forget.shown = false;
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) forget.answer(forget.pick);
        else if (e.key === Qt.Key_Left || e.key === Qt.Key_Right || e.key === Qt.Key_Tab) forget.pick = 1 - forget.pick;
        return;
      }
      if (e.key === Qt.Key_Escape) { kw.visible = false; return; }
      if (e.key === Qt.Key_Left) { kw.step(-1); return; }
      if (e.key === Qt.Key_Right) { kw.step(1); return; }
      if (e.key === Qt.Key_T) { kw.today(); return; }
      if (e.key === Qt.Key_D) { kw.go("day"); return; }
      if (e.key === Qt.Key_W) { kw.go("week"); return; }
      e.accepted = false;
    }
  }

  Item {
    id: stage
    anchors.fill: parent
    Rectangle { z: -1; anchors.fill: parent; color: Zenon.layerBg }

    // ── the head ──
    Item {
      id: head
      z: 3
      anchors.left: parent.left
      anchors.right: parent.right
      height: kw.headH
      Rectangle { anchors.fill: parent; color: Zenon.headBg }
      Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Zenon.border }
      Column {
        x: 20
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1
        Text {
          text: "Screen Time"
          color: Zenon.ink
          font.family: Zenon.face
          font.weight: Zenon.titleWeight
          font.pixelSize: Zenon.px(17)
        }
        Text {
          text: !Kairos.enabled ? "Not counting — turned off in Settings"
            : Kairos.locked || Kairos.idle ? "Paused while you are away" : "Counting on this machine only"
          color: Kairos.enabled ? Zenon.accentMuted : Zenon.yellow
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(12)
        }
      }
      Segments {
        anchors.centerIn: parent
        options: [["day", "Day"], ["week", "Week"]]
        current: kw.view
        onChose: (v) => kw.go(v)
      }
      Row {
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        DialogButton { label: "‹"; implicitHeight: 32; onClicked: kw.step(-1) }
        DialogButton { label: "Today"; implicitHeight: 32; ready: !kw.atToday; onClicked: kw.today() }
        DialogButton { label: "›"; implicitHeight: 32; ready: !kw.atToday; onClicked: kw.step(1) }
      }
    }

    // ── the page ──
    Flickable {
      id: page
      anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: foot.top }
      contentWidth: width
      contentHeight: col.implicitHeight + 40
      boundsBehavior: Flickable.StopAtBounds
      clip: true

      Column {
        id: col
        x: 32
        y: 24
        width: page.width - 64
        spacing: 22

        // the total, and what it is the total of
        Row {
          spacing: 14
          Text {
            text: K.fmt(kw.totalSecs)
            color: Zenon.ink
            font.family: Zenon.face
            font.weight: Zenon.titleWeight
            font.pixelSize: Zenon.px(34)
          }
          Column {
            anchors.verticalCenter: parent.verticalCenter
            Text {
              text: kw.headWords()
              color: Zenon.ink
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(15)
            }
            Text {
              text: kw.view === "week" ? "A day, on average: " + K.fmt(kw.totalSecs / 7)
                : kw.apps.length ? kw.apps.length + (kw.apps.length === 1 ? " app" : " apps") : "Nothing counted"
              color: Zenon.accentMuted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(13)
            }
          }
        }

        // the bars
        Item {
          id: chart
          width: col.width
          height: 200
          readonly property real labelH: Zenon.px(12) + 10
          readonly property real gap: kw.view === "week" ? 18 : 4
          readonly property real barW: (chart.width - chart.gap * (kw.bars.length - 1)) / Math.max(1, kw.bars.length)

          // a faint rule at the top and at the floor
          Rectangle { width: parent.width; height: 1; color: Zenon.border; opacity: 0.6 }
          Rectangle { y: chart.height - chart.labelH; width: parent.width; height: 1; color: Zenon.border }
          Text {
            anchors.right: parent.right
            y: 4
            text: K.fmt(kw.barMax)
            color: Zenon.accentMuted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(11)
          }

          Repeater {
            model: kw.bars
            delegate: Item {
              id: bar
              required property var modelData
              required property int index
              x: bar.index * (chart.barW + chart.gap)
              width: chart.barW
              height: chart.height
              readonly property bool chosen: kw.view === "week" && bar.modelData.key === kw.atKey
              Rectangle {
                width: parent.width
                height: Math.max(bar.modelData.v > 0 ? 3 : 0, (chart.height - chart.labelH - 22) * bar.modelData.v / kw.barMax)
                anchors.bottom: parent.bottom
                anchors.bottomMargin: chart.labelH
                radius: Math.min(Zenon.rad(1), width / 2)
                color: Zenon.alpha(Zenon.cyan, bar.chosen || kw.view === "day" ? 0.85 : 0.45)
                Behavior on height { NumberAnimation { duration: Zenon.slow; easing.type: Zenon.ease } }
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                text: bar.modelData.label
                color: bar.chosen ? Zenon.ink : Zenon.accentMuted
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(12)
              }
              // a week's day opens that day
              MouseArea {
                anchors.fill: parent
                enabled: kw.view === "week" && bar.modelData.key !== ""
                onClicked: { kw.at = K.dateOf(bar.modelData.key); kw.go("day"); }
              }
              // the time, over the bar the pointer is on
              HoverHandler { id: barHover }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: chart.height - chart.labelH - 22 - (chart.height - chart.labelH - 22) * bar.modelData.v / kw.barMax
                visible: barHover.hovered && bar.modelData.v > 0
                text: K.fmt(bar.modelData.v)
                color: Zenon.ink
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(12)
              }
            }
          }
        }

        SectionLabel { text: "Apps" }

        // every app, most first
        Column {
          width: col.width
          spacing: 2
          Repeater {
            model: kw.apps
            delegate: Item {
              id: row
              required property var modelData
              width: col.width
              height: Zenon.px(15) + 26
              Text {
                id: glyph
                anchors.verticalCenter: parent.verticalCenter
                width: Zenon.px(22)
                text: Kairos.glyphOf(row.modelData.key)
                color: Zenon.cyan
                font.family: Zenon.face
                font.pixelSize: Zenon.px(18)
              }
              Text {
                id: name
                anchors.left: glyph.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, row.width * 0.3)
                elide: Text.ElideRight
                text: Kairos.nameOf(row.modelData.key)
                color: Zenon.ink
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(15)
              }
              // its share, against the most used
              Rectangle {
                id: track
                x: row.width * 0.34
                anchors.verticalCenter: parent.verticalCenter
                width: row.width * 0.5
                height: 6
                radius: 3
                color: Zenon.wash(0.06)
                Rectangle {
                  width: Math.max(6, track.width * row.modelData.share)
                  height: parent.height
                  radius: 3
                  color: Zenon.alpha(Zenon.cyan, 0.7)
                }
              }
              Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: K.fmt(row.modelData.secs)
                color: Zenon.ink
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(15)
              }
            }
          }
        }
      }
    }

    EmptyState {
      anchors.horizontalCenter: page.horizontalCenter
      y: page.y + 24 + 60 + 22 + 200 + 70
      width: 420
      visible: kw.apps.length === 0
      text: !Kairos.enabled ? "Screen time is off. Turn it on in Settings, Time & weather."
        : kw.atToday && kw.view === "day" ? "Nothing yet today. Time counts while an app is in front of you."
        : "Nothing was counted then."
    }

    HintBar {
      id: foot
      z: 3
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      rows: [["← →", kw.view === "week" ? "week" : "day"], ["d w", "day · week"], ["t", "today"], ["esc", "close"]]
      DialogButton {
        anchors.verticalCenter: parent.verticalCenter
        label: "Forget"
        implicitHeight: 28
        onClicked: { forget.pick = 1; forget.shown = true; }
      }
    }

    // ── forgetting, asked first ──
    InputShield { visible: forget.shown; onClicked: forget.shown = false }
    Sheet {
      id: forget
      fromTop: kw.headH
      cardW: 460
      cardH: forgetBody.implicitHeight
      property int pick: 1
      function answer(i) {
        forget.shown = false;
        if (i === 0) Kairos.forget();
      }
      ConfirmBody {
        id: forgetBody
        width: parent.width
        question: "Forget all screen time?"
        glyph: ""
        glyphInk: Zenon.red
        detail: "Every day counted so far is deleted from this machine."
        choices: [{ label: "Forget", ink: Zenon.red }, { label: "Cancel", ink: Zenon.accentMuted }]
        pick: forget.pick
        onPicked: (i) => forget.pick = i
        onChose: (i) => forget.answer(i)
      }
    }
  }
}

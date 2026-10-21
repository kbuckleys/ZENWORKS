// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A JOURNAL, AS APPLE'S — the insights over it (the streak, this year's
// entries, the words written), a reflection to write about, the calendar
// of days written on; then the entries as cards under their months, each
// its day, its title and first lines, its pictures, how it felt. Filters
// as Apple's: bookmarked, with photos, with a mood, reflections.

import QtQuick
import "../morpheus"
import "../terminus"
import "notes.js" as N

Item {
  id: jl
  property var win: null
  readonly property alias view: list
  readonly property var mgr: jl.win ? jl.win.mgr : null
  readonly property string journal: jl.win && jl.win.inJournal ? jl.win.scope.id || "" : ""
  readonly property bool shut: !!jl.win && jl.win.journalLocked(jl.journal)
  readonly property var all: jl.mgr ? (void jl.mgr.notes, N.entries(jl.mgr.notes, jl.journal, {})) : []
  readonly property var stats: N.insights(jl.all, Date.now())
  property bool calendar: false
  property int promptShift: 0

  // ── THE TOP: INSIGHTS, FILTERS ─────────────────────────────────────────
  Column {
    id: top
    width: parent.width
    topPadding: 10
    spacing: 10
    visible: !jl.shut

    Row {
      x: 14
      spacing: 8
      Repeater {
        model: [
          { glyph: "", ink: "yellow", value: jl.stats.streak, word: jl.stats.streak === 1 ? "day streak" : "day streak",
            tip: "Days in a row with an entry. Longest: " + jl.stats.longest },
          { glyph: "\u{F0B64}", ink: "cyan", value: jl.stats.year, word: "this year", tip: jl.stats.total + " entries in all, on " + jl.stats.daysWritten + " days" },
          { glyph: "\u{F09AA}", ink: "magenta", value: jl.stats.words, word: "words", tip: "Words written in this journal" }]
        delegate: Rectangle {
          id: stat
          required property var modelData
          width: Math.floor((jl.width - 28 - 16) / 3)
          height: 58
          radius: Zenon.rad(7)
          color: Zenon.alpha(Zenon[modelData.ink], 0.08)
          border.width: 1
          border.color: Zenon.alpha(Zenon[modelData.ink], 0.3)
          Column {
            anchors.centerIn: parent
            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: 6
              Text { text: stat.modelData.glyph; color: Zenon[stat.modelData.ink]; font.family: Zenon.glyphFace; font.pixelSize: Zenon.px(15); anchors.verticalCenter: parent.verticalCenter }
              Text {
                text: stat.modelData.value >= 10000 ? (stat.modelData.value / 1000).toFixed(1) + "k" : String(stat.modelData.value)
                color: Zenon.ink
                font.family: Zenon.face
                font.weight: Font.Bold
                font.pixelSize: Zenon.px(18)
                font.features: { "tnum": 1 }
              }
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: stat.modelData.word
              color: Zenon.accentMuted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(11)
            }
          }
          HoverHandler { onHoveredChanged: hovered ? jl.win.tipsItem.show(stat, stat.modelData.tip) : jl.win.tipsItem.hide(stat) }
        }
      }
    }

    // ── THE LAST FOUR WEEKS, BY MOOD ── a dot a day: its mood's color, a
    // plain dot for a day written with none, a ring for a day not written;
    // a click shows that day
    Item {
      id: moods
      readonly property var days: N.moodDays(jl.all, Date.now(), 28)
      visible: jl.all.length > 0 && jl.win && jl.win.query === ""
      x: 14
      width: jl.width - 28
      height: 30
      readonly property real step: (moods.width - 10) / 28
      Repeater {
        model: moods.days
        delegate: Item {
          id: dot
          required property var modelData
          required property int index
          readonly property var mood: dot.modelData.mood === null ? null : N.moodOf(dot.modelData.mood)
          readonly property bool chosen: !!jl.win && jl.win.day === dot.modelData.key
          x: 5 + dot.index * moods.step
          width: moods.step
          height: moods.height
          Rectangle {
            anchors.centerIn: parent
            width: Math.min(14, moods.step - 3) * (dotMa.pressed || dot.chosen ? 1.2 : 1)
            height: width
            radius: width / 2
            color: dot.mood ? (Zenon[dot.mood.ink] || Zenon.accentMuted) : dot.modelData.wrote ? Zenon.accentMuted : "transparent"
            border.width: dot.modelData.wrote ? (dot.chosen ? 2 : 0) : 1
            border.color: dot.chosen ? Zenon.ink : Zenon.border
            opacity: dot.modelData.wrote ? 1 : 0.7
            Behavior on width { NumberAnimation { duration: Zenon.ms(120) } }
          }
          MouseArea {
            id: dotMa
            anchors.fill: parent
            hoverEnabled: true
            onClicked: if (dot.modelData.wrote) jl.win.day = dot.chosen ? "" : dot.modelData.key
            onContainsMouseChanged: containsMouse
              ? jl.win.tipsItem.show(dot, N.dateLong(dot.modelData.ms) + (dot.mood ? " · " + dot.mood.label : dot.modelData.wrote ? "" : " · nothing written"))
              : jl.win.tipsItem.hide(dot)
          }
        }
      }
    }

    // today's reflection: write about it, or another
    Rectangle {
      x: 14
      width: jl.width - 28
      height: refl.implicitHeight + 24
      radius: Zenon.rad(7)
      color: Zenon.alpha(Zenon.magenta, 0.07)
      border.width: 1
      border.color: Zenon.alpha(Zenon.magenta, 0.28)
      visible: jl.win && jl.win.query === "" && jl.win.day === ""
      Column {
        id: refl
        x: 14
        y: 12
        width: parent.width - 28
        spacing: 8
        Text {
          text: "\u{F0336}  REFLECTION"
          color: Zenon.magenta
          font.family: Zenon.face
          font.weight: Zenon.titleWeight
          font.pixelSize: Zenon.px(11)
          font.letterSpacing: Zenon.labelSpacing
        }
        Text {
          width: parent.width
          wrapMode: Text.Wrap
          text: N.promptOfDay(Date.now(), jl.promptShift)
          color: Zenon.ink
          font.family: Zenon.face
          font.weight: Font.DemiBold
          font.pixelSize: Zenon.px(15)
        }
        Row {
          spacing: 8
          DialogButton { label: "Write"; ink: Zenon.magenta; onClicked: jl.win.newEntry(Date.now(), N.promptOfDay(Date.now(), jl.promptShift)) }
          DialogButton { label: "Another"; onClicked: jl.promptShift++ }
          DialogButton { label: "\u{F02EF}  Moments"; onClicked: jl.win.momentsOpen = true }
        }
      }
    }

    // on this day, in years before: the nearest one, and how many more
    Rectangle {
      id: past
      readonly property var hits: jl.win && jl.win.query === "" && jl.win.day === "" ? N.onThisDay(jl.all, Date.now()) : []
      x: 14
      width: jl.width - 28
      height: pastCol.implicitHeight + 20
      visible: past.hits.length > 0
      radius: Zenon.rad(9)
      color: pastMa.pressed ? Zenon.alpha(Zenon.yellow, 0.14) : Zenon.alpha(Zenon.yellow, 0.08)
      border.width: 1
      border.color: Zenon.alpha(Zenon.yellow, 0.3)
      Column {
        id: pastCol
        x: 14
        y: 10
        width: parent.width - 28
        spacing: 4
        Text {
          text: "\u{F02DA}  ON THIS DAY · " + (past.hits.length ? (past.hits[0].years === 1 ? "A YEAR AGO" : past.hits[0].years + " YEARS AGO") : "")
            + (past.hits.length > 1 ? "  +" + (past.hits.length - 1) : "")
          color: Zenon.yellow
          font.family: Zenon.face
          font.weight: Zenon.titleWeight
          font.pixelSize: Zenon.px(11)
          font.letterSpacing: Zenon.labelSpacing
        }
        Text {
          width: parent.width
          elide: Text.ElideRight
          text: past.hits.length ? N.titleOf(past.hits[0].n, N.dateLong(past.hits[0].n.date)) : ""
          color: Zenon.ink
          font.family: Zenon.face
          font.weight: Font.DemiBold
          font.pixelSize: Zenon.px(14)
        }
      }
      MouseArea {
        id: pastMa
        anchors.fill: parent
        hoverEnabled: true
        // one: open it; more: the day shown, every year of it
        onClicked: past.hits.length === 1 ? jl.win.openNote(past.hits[0].n.id) : jl.win.choose(past.hits[0].n.id)
      }
    }

    // ── FROM YOUR JOURNAL ── an older entry brought back (the same all day),
    // when no year has one on this day
    Rectangle {
      id: back
      readonly property var e: !past.visible && jl.win && jl.win.query === "" && jl.win.day === "" ? N.resurface(jl.all, Date.now()) : null
      x: 14
      width: jl.width - 28
      height: backCol.implicitHeight + 20
      visible: !!back.e
      radius: Zenon.rad(9)
      color: backMa.pressed ? Zenon.alpha(Zenon.cyan, 0.18) : Zenon.alpha(Zenon.cyan, 0.06)
      border.width: 1
      border.color: Zenon.alpha(Zenon.cyan, 0.28)
      Column {
        id: backCol
        x: 14
        y: 10
        width: parent.width - 28
        spacing: 4
        Text {
          text: "\u{F0B64}  FROM YOUR JOURNAL · " + (back.e ? N.dateLong(back.e.date).toUpperCase() : "")
          color: Zenon.cyan
          font.family: Zenon.face
          font.weight: Zenon.titleWeight
          font.pixelSize: Zenon.px(11)
          font.letterSpacing: Zenon.labelSpacing
        }
        Text {
          width: parent.width
          elide: Text.ElideRight
          maximumLineCount: 2
          wrapMode: Text.Wrap
          text: back.e ? N.titleOf(back.e, N.dateLong(back.e.date)) + (back.e.d && back.e.d.preview ? " — " + back.e.d.preview : "") : ""
          color: Zenon.ink
          font.family: Zenon.face
          font.weight: Font.DemiBold
          font.pixelSize: Zenon.px(14)
        }
      }
      MouseArea {
        id: backMa
        anchors.fill: parent
        hoverEnabled: true
        onClicked: jl.win.openNote(back.e.id)
      }
    }

    // the filters, and the calendar
    Item {
      x: 14
      width: jl.width - 28
      height: 30
      Segments {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        options: [["", "All"], ["bookmarked", ""], ["photos", ""], ["mood", "\u{F01F5}"], ["reflection", "\u{F0336}"]]
        current: jl.mgr ? jl.mgr.journalFilter : ""
        textSize: Zenon.px(12)
        onChose: (v) => { jl.mgr.set("journalFilter", v); jl.win.wantTop = true; }
        onPointed: (v, item, inside) => inside
          ? jl.win.tipsItem.show(item, { "": "Every entry", bookmarked: "Bookmarked", photos: "With photos", mood: "With a mood", reflection: "Reflections" }[v])
          : jl.win.tipsItem.hide(item)
      }
      DialogButton {
        id: calBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        glyph: true
        label: ""
        ink: jl.calendar || jl.win.day !== "" ? Zenon.cyan : Zenon.accentMuted
        onClicked: jl.calendar = !jl.calendar
        HoverHandler { onHoveredChanged: hovered ? jl.win.tipsItem.show(calBtn, "Calendar of entries") : jl.win.tipsItem.hide(calBtn) }
      }
    }

    // the month, the days written on dotted
    JournalCalendar {
      x: 14
      width: jl.width - 28
      visible: jl.calendar
      win: jl.win
      entries: jl.all
      stats: jl.stats
    }
    // a day chosen: said, and let go of
    Rectangle {
      x: 14
      visible: !!jl.win && jl.win.day !== ""
      width: dayText.implicitWidth + 40
      height: 28
      radius: Zenon.windowRadius
      color: jl.win ? jl.win.hiFill : "transparent"
      Text {
        id: dayText
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        text: jl.win && jl.win.day !== "" ? (() => { const p = jl.win.day.split("-"); return N.dateLong(new Date(+p[0], +p[1] - 1, +p[2]).getTime()); })() : ""
        color: Zenon.cyan
        font.family: Zenon.face
        font.weight: Font.DemiBold
        font.pixelSize: Zenon.px(13)
      }
      ClearChip { anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter; size: Zenon.px(13); onClicked: jl.win.day = "" }
    }
    Rectangle { width: jl.width; height: 1; color: Zenon.border }
  }

  // ── THE ENTRIES ────────────────────────────────────────────────────────
  ListModel { id: rowModel }
  readonly property var rows: jl.win && jl.win.inJournal ? jl.win.rows : []
  onRowsChanged: {
    const r = jl.rows;
    let same = rowModel.count === r.length;
    for (let i = 0; same && i < r.length; i++) same = rowModel.get(i).key === r[i].n.id;
    if (same) { for (let i = 0; i < r.length; i++) if (rowModel.get(i).head !== r[i].head) rowModel.setProperty(i, "head", r[i].head); return; }
    rowModel.clear();
    for (const x of r) rowModel.append({ key: x.n.id, head: x.head });
  }

  ListView {
    id: list
    anchors.top: top.bottom
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    visible: !jl.shut
    clip: true
    bottomMargin: 12
    spacing: 0
    boundsBehavior: Flickable.StopAtBounds
    model: rowModel
    cacheBuffer: 4000
    delegate: Item {
      id: row
      required property string key
      required property string head
      required property int index
      readonly property var n: jl.rows[index] ? jl.rows[index].n : null
      readonly property bool here: !!row.n && jl.win.selId === row.n.id
      width: list.width
      height: card.height + 12 + (row.head !== "" ? 36 : 0)
      Text {
        visible: row.head !== ""
        x: 18
        height: 36
        verticalAlignment: Text.AlignBottom
        bottomPadding: 6
        text: row.head
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(15)
      }
      EntryCard {
        id: card
        x: 12
        y: (row.head !== "" ? 36 : 0) + 6
        width: parent.width - 24
        win: jl.win
        note: row.n
        here: row.here
      }
    }
    EmptyMark {
      anchors.centerIn: parent
      visible: list.count === 0 && !!jl.mgr && jl.mgr.loaded
      filtered: !!jl.win && (jl.win.query !== "" || jl.win.day !== "" || jl.mgr.journalFilter !== "")
      word: "No entries yet"
    }
  }
  ElasticScroll { id: wheel; anchors.fill: list; view: list }
  Scrollbar { flick: list; anchors.right: list.right; anchors.top: list.top; anchors.bottom: list.bottom }

  // ── A LOCKED JOURNAL ───────────────────────────────────────────────────
  Column {
    anchors.centerIn: parent
    visible: jl.shut
    spacing: 12
    Text { anchors.horizontalCenter: parent.horizontalCenter; text: ""; color: Zenon.yellow; font.family: Zenon.glyphFace; font.pixelSize: Zenon.px(40) }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "This journal is locked"
      color: Zenon.ink
      font.family: Zenon.face
      font.weight: Font.Bold
      font.pixelSize: Zenon.px(18)
    }
    DialogButton {
      anchors.horizontalCenter: parent.horizontalCenter
      label: "Unlock"
      ink: Zenon.yellow
      primary: true
      onClicked: jl.win.withPassword(() => jl.win.paneRef.show(jl.win.current))
    }
  }

  function seat(i) { list.positionViewAtIndex(i, ListView.Contain); }
}

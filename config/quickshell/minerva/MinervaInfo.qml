// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// INFO, on a sheet (ctrl i — user, 2026-10-21: "reading stats"): a book's
// facts — where it is, how far, its marks, its shelves, the time spent in
// it and the time it will take at that pace — and under it, or alone from
// the library's head, your reading: today, this week, the days in a row,
// and the last fortnight as bars. The facts are Hermes' rows (HermesFact).

import QtQuick
import "../morpheus"
import "../hermes" as Her
import "minerva.js" as M

Column {
  id: info
  property var mgr: null
  property var book: null
  property var chapters: []
  property int pages: 0
  spacing: 8

  readonly property var days: info.mgr ? M.lastDays(info.mgr.stats, 14, Date.now()) : []
  readonly property real most: Math.max(60000, ...info.days)
  readonly property real week: info.days.slice(-7).reduce((a, b) => a + b, 0)

  // ── THE BOOK ───────────────────────────────────────────────────────────
  Text {
    width: parent.width
    visible: !!info.book
    wrapMode: Text.WordWrap
    maximumLineCount: 2
    elide: Text.ElideRight
    text: info.book ? info.book.title : ""
    color: Zenon.ink
    font.family: info.mgr ? info.mgr.serifFace : Zenon.face
    font.pixelSize: Zenon.px(22)
    font.weight: Font.DemiBold
  }
  Text {
    visible: !!info.book && info.book.author !== ""
    text: info.book ? info.book.author : ""
    color: Zenon.accentMuted
    font.family: Zenon.face
    font.pixelSize: Zenon.px(15)
  }
  Item { width: 1; height: 4; visible: !!info.book }
  Column {
    width: parent.width
    visible: !!info.book
    spacing: 0
    Her.HermesFact { width: parent.width; label: "Kind"; value: info.book ? M.KINDS[info.book.kind] + (info.pages > 0 ? ", " + info.pages + " pages" : info.chapters.length > 0 ? ", " + info.chapters.length + " chapters" : "") : "" }
    Her.HermesFact { width: parent.width; label: "File"; value: info.book ? info.book.path : "" }
    Her.HermesFact {
      width: parent.width
      label: "Read"
      value: !info.book ? "" : info.book.finished > 0 ? "Finished " + M.openedWords(info.book.finished).toLowerCase()
        : info.book.opened > 0 ? M.percentWords(info.book.progress) + ", at " + M.whereWords(info.book.kind, info.book.pos, info.chapters) : "Not yet"
    }
    Her.HermesFact { width: parent.width; label: "Time spent"; value: info.book && info.book.readMs > 0 ? M.spanWords(info.book.readMs) : "" }
    Her.HermesFact { width: parent.width; label: "Time left"; value: info.book && M.timeLeft(info.book) > 0 ? "About " + M.spanWords(M.timeLeft(info.book)) + ", at your pace" : "" }
    Her.HermesFact { width: parent.width; label: "Last read"; value: info.book && info.book.opened > 0 ? M.openedWords(info.book.opened) : "" }
    Her.HermesFact { width: parent.width; label: "Added"; value: info.book && info.book.added > 0 ? M.openedWords(info.book.added) : "" }
    Her.HermesFact {
      width: parent.width
      label: "Marks"
      value: !info.book ? "" : [info.book.bookmarks.length === 1 ? "1 bookmark" : info.book.bookmarks.length + " bookmarks",
        info.book.highlights.length === 1 ? "1 highlight" : info.book.highlights.length + " highlights",
        info.book.highlights.filter((h) => h.comment).length + " with notes"].join(", ")
    }
    Her.HermesFact { width: parent.width; label: "Shelves"; value: info.book && info.book.shelves.length ? info.book.shelves.join(", ") : "" }
  }
  Item { width: 1; height: 10; visible: !!info.book }

  // ── YOUR READING ───────────────────────────────────────────────────────
  SectionLabel { text: "Your reading" }
  Row {
    spacing: 28
    Repeater {
      model: [
        ["Today", M.spanWords(info.days[info.days.length - 1] || 0)],
        ["This week", M.spanWords(info.week)],
        ["In a row", info.mgr ? (M.streak(info.mgr.stats, Date.now()) === 1 ? "1 day" : M.streak(info.mgr.stats, Date.now()) + " days") : ""]
      ]
      delegate: Column {
        required property var modelData
        spacing: 2
        Text {
          text: modelData[1]
          color: Zenon.ink
          font.family: Zenon.face
          font.weight: Font.DemiBold
          font.pixelSize: Zenon.px(20)
        }
        Text {
          text: modelData[0]
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.pixelSize: Zenon.px(12)
        }
      }
    }
  }
  // the last fortnight, a bar a day, today on the right
  Item {
    width: parent.width
    height: 96
    Row {
      anchors.bottom: dayNames.top
      anchors.bottomMargin: 6
      width: parent.width
      height: 70
      spacing: 6
      Repeater {
        model: info.days
        delegate: Item {
          required property real modelData
          required property int index
          width: (parent.width - 6 * 13) / 14
          height: parent.height
          Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: Math.max(3, parent.height * modelData / info.most)
            radius: Zenon.rad(3)
            color: index === 13 ? Zenon.cyan : modelData >= 60000 ? Zenon.alpha(Zenon.cyan, 0.55) : Zenon.wash(0.12)
          }
        }
      }
    }
    Text {
      id: dayNames
      anchors.bottom: parent.bottom
      text: "two weeks ago"
      color: Zenon.accentMuted
      font.family: Zenon.face
      font.pixelSize: Zenon.px(11)
    }
    Text {
      anchors.bottom: parent.bottom
      anchors.right: parent.right
      text: "today"
      color: Zenon.accentMuted
      font.family: Zenon.face
      font.pixelSize: Zenon.px(11)
    }
  }
}

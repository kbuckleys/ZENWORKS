// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// READ THIS FIRST — the Arch news published since your last upgrade, shown
// before the next one goes ahead. What paru -Pw prints, as a page: each item's
// title, when, the first of what it says, and the post itself a click on its title away.
// Continuing puts these aside and carries on with the upgrade that was held;
// backing out leaves both the news and the upgrade where they were.
//
// One view for the panel and the window, like TxView. With `all` it is the
// window's News tab instead: the whole feed on demand, newest first, the
// items since your last upgrade marked new.

import QtQuick
import "../morpheus"
import "."

Item {
  id: view
  // Text size over the panel's: the window reads 2px larger.
  property int grow: 0
  // the News tab: every item the feed carries, not only the unread
  property bool all: false
  // the tab, offline: the feed last read is kept, and the lead says so
  readonly property bool stale: view.all && Ceres.newsFailed && Ceres.news.length > 0
  readonly property bool leadShown: !view.all || view.stale
  // ↑ ↓ from the window's keys: the list moves by a line
  function scroll(d) {
    const top = items.originY, bottom = items.originY + Math.max(0, items.contentHeight - items.height);
    items.contentY = Math.max(top, Math.min(bottom, items.contentY + d * 60));
  }

  Text {
    id: lead
    visible: view.leadShown
    height: view.leadShown ? implicitHeight : 0
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    wrapMode: Text.Wrap
    text: view.all ? "Offline — showing the news last read"
      : Ceres.unreadNews.length === 1
      ? "Arch posted news since your last upgrade. Worth reading before this one."
      : "Arch posted " + Ceres.unreadNews.length + " news items since your last upgrade. Worth reading before this one."
    color: Zenon.yellow
    font.family: Zenon.face
    font.weight: Font.Bold
    font.pixelSize: Zenon.px(15) + view.grow
  }

  ListView {
    id: items
    // the shell's wheel and touchpad feel (morpheus Elastic)
    ElasticScroll { view: items }
    anchors.top: lead.bottom
    anchors.topMargin: view.leadShown ? 14 : 0
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    clip: true
    spacing: 10
    boundsBehavior: Flickable.StopAtBounds
    model: view.all ? Ceres.news : Ceres.unreadNews
    ScrollRail {
      target: items
      // Against the edge the view is inset from (its host's margin), not the list's.
      parent: view
      anchors.right: parent.right
      anchors.rightMargin: -view.anchors.rightMargin
      anchors.top: items.top
      anchors.bottom: items.bottom
    }
    delegate: Rectangle {
      id: card
      required property var modelData
      // since your last upgrade and not put aside: what the upgrade stops for
      readonly property bool fresh: view.all && Ceres.unreadNews.some((n) => n.link === card.modelData.link)
      width: items.width - 14
      height: body.implicitHeight + 24
      radius: Zenon.windowRadius
      color: Zenon.headBg
      border.width: 1
      border.color: Zenon.border

      Column {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 6
        // the post's glyph rides after the title's last word, in the link's
        // ink, where a "Read the post" row used to be (user, 2026-10-22)
        Text {
          id: title
          // clear of the date in the corner
          width: parent.width - stamp.width - 16
          wrapMode: Text.Wrap
          textFormat: Text.StyledText
          text: card.modelData.title.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
            + "&nbsp;&nbsp;<font face=\"" + Zenon.glyphFace + "\" color=\"" + Zenon.link + "\">\u{F17B7}</font>"
          color: Zenon.white
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: Zenon.px(15) + view.grow
        }
        Text {
          textFormat: Text.PlainText
          width: parent.width
          wrapMode: Text.Wrap
          maximumLineCount: 4
          elide: Text.ElideRight
          text: card.modelData.text
          color: Zenon.accentKey
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13) + view.grow
        }
      }
      // WHEN, IN THE CORNER (user, 2026-10-22): top right, on the title's
      // first line — "new" before the date when it is
      Row {
        id: stamp
        anchors.right: parent.right
        anchors.rightMargin: 12
        y: body.y + title.baselineOffset - stampDate.baselineOffset
        spacing: 8
        Text {
          visible: card.fresh
          text: "New since your last upgrade"
          color: Zenon.yellow
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: Zenon.px(12) + view.grow
        }
        Text {
          id: stampDate
          text: Qt.formatDate(new Date(card.modelData.date), "ddd d MMM yyyy")
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(12) + view.grow
        }
      }
      // THE CARD IS THE LINK (user, 2026-10-22): anywhere on it opens the
      // post. Pressed, it darkens as a Store card does; no hand (user,
      // 2026-10-22: a card, not a link in text)
      Rectangle {
        anchors.fill: parent
        radius: card.radius
        visible: open.pressed
        color: Zenon.pressTile(false)
      }
      TapHandler {
        id: open
        onTapped: Strings.openLink(card.modelData.link)
      }
    }
  }

  // the tab with nothing to show: being read, unreachable, or empty
  EmptyState {
    anchors.centerIn: parent
    width: Math.min(parent.width, 520)
    visible: view.all && Ceres.news.length === 0
    text: Ceres.newsLoading ? "Reading archlinux.org…"
      : Ceres.newsFailed ? "Couldn't reach archlinux.org — ctrl r tries again"
      : "No news yet — ctrl r reads archlinux.org"
  }
}

// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// READ THIS FIRST — the Arch news published since your last upgrade, shown
// before the next one goes ahead. What paru -Pw prints, as a page: each item's
// title, when, the first of what it says, and the post itself a click away.
// Continuing puts these aside and carries on with the upgrade that was held;
// backing out leaves both the news and the upgrade where they were.
//
// One view for the panel and the window, like TxView.

import QtQuick
import Quickshell
import "../morpheus"
import "."
import "ceres.js" as Cer

Item {
  id: view
  // Text size over the panel's: the window reads 2px larger.
  property int grow: 0

  Text {
    id: lead
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    wrapMode: Text.Wrap
    text: Ceres.unreadNews.length === 1
      ? "Arch posted news since your last upgrade. Worth reading before this one."
      : "Arch posted " + Ceres.unreadNews.length + " news items since your last upgrade. Worth reading before this one."
    color: Zenon.yellow
    font.family: Zenon.face
    font.weight: Font.Bold
    font.pixelSize: 15 + view.grow
  }

  ListView {
    id: items
    anchors.top: lead.bottom
    anchors.topMargin: 14
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    clip: true
    spacing: 10
    boundsBehavior: Flickable.StopAtBounds
    model: Ceres.unreadNews
    ScrollRail {
      target: items
      parent: items
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
    }
    delegate: Rectangle {
      id: card
      required property var modelData
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
        Text {
          width: parent.width
          wrapMode: Text.Wrap
          text: card.modelData.title
          color: Zenon.white
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: 15 + view.grow
        }
        Text {
          text: Qt.formatDate(new Date(card.modelData.date), "ddd d MMM yyyy")
          color: Zenon.muted
          font.family: Zenon.face
          font.pixelSize: 12 + view.grow
        }
        Text {
          width: parent.width
          wrapMode: Text.Wrap
          maximumLineCount: 4
          elide: Text.ElideRight
          text: card.modelData.text
          color: Zenon.keyInk
          font.family: Zenon.face
          font.pixelSize: 13 + view.grow
        }
        Text {
          text: "Read the post →"
          color: readHov.hovered ? Zenon.white : Zenon.cyan
          font.family: Zenon.face
          font.pixelSize: 13 + view.grow
          HoverHandler { id: readHov; cursorShape: Qt.PointingHandCursor }
          TapHandler { onTapped: Quickshell.execDetached(["xdg-open", card.modelData.link]) }
        }
      }
    }
  }
}

// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// WHAT THE KEYS DO, as a row of caps: `rows` is a list of [key, what it does].
// The strip it stands on (its ground, its rule, its height) belongs to each
// panel; the row is the same everywhere, which is the point of it being here.

import QtQuick
import "."

//
// ── WHEN THE STRIP IS SHORT ─────────────────────────────────────────────
// Give it `maxWidth` and the hints that do not fit go, from the END: a
// holder lists its keys most important first, so what is left is the
// head of the list, whole, rather than a caption run under whatever stands
// beside the row (ceres' "Review 1" button had "updates" written through
// it). The keys still work; only their reminder steps aside, and comes
// back as soon as there is room. Unset (-1), every hint is shown.
//
// AND NOTHING IS LOST: when any have gone, a `?` cap ends the row, and
// hovering it (or clicking, for a touchpad that does not hover) opens a
// small card above it with every key the strip would have listed.

Row {
  id: hints
  property var rows: []
  spacing: 14
  property real maxWidth: -1
  // how many of `rows` are showing
  property int shown: 0

  function refit() {
    const ws = [];
    for (let i = 0; i < pairs.count; i++) {
      const it = pairs.itemAt(i);
      if (!it) break;
      ws.push(it.implicitWidth + (i > 0 ? hints.spacing : 0));
    }
    const all = ws.reduce((t, w) => t + w, 0);
    if (hints.maxWidth < 0 || all <= hints.maxWidth) { hints.shown = ws.length; return; }
    // short: room is kept for the `?` that stands in for the rest
    const room = hints.maxWidth - more.implicitWidth - hints.spacing;
    let used = 0, n = 0;
    for (const w of ws) {
      if (used + w > room) break;
      used += w;
      n++;
    }
    hints.shown = n;
  }
  onMaxWidthChanged: hints.refit()
  Component.onCompleted: hints.refit()

  Repeater {
    id: pairs
    model: hints.rows
    onItemAdded: hints.refit()
    onItemRemoved: hints.refit()
    delegate: Row {
      id: pair
      required property var modelData
      required property int index
      spacing: 5
      visible: pair.index < hints.shown
      onImplicitWidthChanged: hints.refit()

      KeyCap {
        anchors.verticalCenter: parent.verticalCenter
        label: pair.modelData[0]
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: pair.modelData[1]
        color: Zenon.muted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
      }
    }
  }

  // the rest, behind a `?` — see the note at the head of the file
  KeyCap {
    id: more
    anchors.verticalCenter: parent.verticalCenter
    visible: hints.shown < hints.rows.length
    label: "?"
    border.color: moreHov.hovered || hints.cardOpen ? Zenon.keyInk : Zenon.border
    HoverHandler { id: moreHov; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: hints.pinned = !hints.pinned }

    Rectangle {
      id: card
      visible: hints.cardOpen
      anchors.bottom: parent.top
      anchors.bottomMargin: 12
      anchors.right: parent.right
      anchors.rightMargin: -8
      width: cardCol.implicitWidth + 24
      height: cardCol.implicitHeight + 20
      radius: Zenon.windowRadius
      color: Zenon.menuBgSolid
      border.width: 1
      border.color: Zenon.border
      z: 50

      Column {
        id: cardCol
        x: 12
        y: 10
        spacing: 6
        Repeater {
          model: hints.rows
          delegate: Row {
            required property var modelData
            spacing: 8
            KeyCap {
              anchors.verticalCenter: parent.verticalCenter
              label: parent.modelData[0]
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: parent.modelData[1]
              color: Zenon.keyInk
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(13)
            }
          }
        }
      }
    }
  }
  property bool pinned: false
  readonly property bool cardOpen: more.visible && (moreHov.hovered || hints.pinned)
  onRowsChanged: hints.pinned = false
}

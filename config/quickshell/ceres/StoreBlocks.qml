// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// AppStream prose — an app's description, a release's notes — as ceres-store
// hands it over: {p: text} paragraphs and {ul|ol: [items]} lists, drawn as a
// page's text with its bullets and numbers.

import QtQuick
import "../morpheus"

Column {
  id: bl
  property var blocks: []
  spacing: 10

  Repeater {
    model: bl.blocks
    delegate: Column {
      id: blk
      required property var modelData
      readonly property var items: blk.modelData.ul || blk.modelData.ol || []
      readonly property bool numbered: !!blk.modelData.ol
      width: bl.width
      spacing: 5
      Text {
        visible: blk.modelData.p !== undefined
        width: parent.width
        wrapMode: Text.Wrap
        text: blk.modelData.p || ""
        color: Zenon.white
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(16)
        lineHeight: 1.12
      }
      Repeater {
        model: blk.items
        delegate: Row {
          required property var modelData
          required property int index
          width: blk.width
          spacing: 10
          Text {
            width: 18
            horizontalAlignment: Text.AlignRight
            text: blk.numbered ? (index + 1) + "." : "•"
            color: Zenon.cyan
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(16)
          }
          Text {
            width: parent.width - 28
            wrapMode: Text.Wrap
            text: modelData
            color: Zenon.white
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(16)
            lineHeight: 1.08
          }
        }
      }
    }
  }
}

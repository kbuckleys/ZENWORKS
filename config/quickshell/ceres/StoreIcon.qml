// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// An app's icon, with its source's mark in the lower corner.
//
// Arch's catalogue ships its icons cut to size, as JPEG XL (kimageformats
// reads them — it is a dependency). Where it has none, the icon theme's
// stock icon by the same name; where that has none either, the name's first
// letter on a tile, never an empty square.

import QtQuick
import Quickshell
import "../morpheus"
import "store.js" as St

Item {
  id: ic
  property var app: null
  property int size: 52
  property bool mark: true
  implicitWidth: ic.size
  implicitHeight: ic.size
  width: ic.size
  height: ic.size

  readonly property string src: !ic.app ? ""
    : ic.app.icon ? "file://" + ic.app.icon
    : ic.app.stock ? Quickshell.iconPath(ic.app.stock, true) : ""

  Image {
    id: img
    anchors.fill: parent
    source: ic.src
    sourceSize: Qt.size(ic.size * 2, ic.size * 2)
    fillMode: Image.PreserveAspectFit
    smooth: true
    mipmap: true
    asynchronous: true
    cache: true
  }

  Rectangle {
    anchors.fill: parent
    visible: ic.src === "" || img.status === Image.Error
    radius: Zenon.windowRadius
    color: Zenon.alpha(Zenon.cyan, 0.16)
    border.width: 1
    border.color: Zenon.alpha(Zenon.cyan, 0.4)
    Text {
      anchors.centerIn: parent
      text: ic.app ? ic.app.name.charAt(0).toUpperCase() : ""
      color: Zenon.cyan
      font.family: Zenon.face
      font.weight: Font.Bold
      font.pixelSize: Math.round(ic.size * 0.46)
    }
  }

  // the source's mark, on a disc of the window's ground so it reads over
  // any icon
  Rectangle {
    visible: ic.mark && !!ic.app
    width: Math.round(ic.size * 0.36)
    height: width
    radius: width / 2
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.rightMargin: -Math.round(width * 0.25)
    anchors.bottomMargin: -Math.round(width * 0.2)
    color: Zenon.layerBg
    border.width: 1
    border.color: Zenon.border
    Text {
      anchors.centerIn: parent
      text: St.cardGlyph(ic.app)
      // the AUR in its magenta, as Updates and Packages mark it; an app from
      // more than one source in the accent, under the layers mark
      color: !ic.app ? Zenon.blue
        : (ic.app.others || []).length ? Zenon.cyan
        : ic.app.source === "aur" ? Zenon.magenta : Zenon.blue
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Math.round(parent.width * 0.62)
    }
  }
}

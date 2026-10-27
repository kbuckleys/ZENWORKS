// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A THEME, SMALL: its ground with a line of its ink and a dot of its
// accent, 22 by 14 — beside a theme's name in Oracle's Theme menu and on
// its chip (user, 2026-10-27: dark from light at a glance). `colors` is
// [ground, ink, accent].
//
//   Swatch { colors: ["#000000", "#dfdfdd", "#9bbfbf"] }
//   a CardMenu row: { text: "Zenon", swatch: [ground, ink, accent] }

import QtQuick

Rectangle {
  id: sw
  property var colors: null
  implicitWidth: 22
  implicitHeight: 14
  width: implicitWidth
  height: implicitHeight
  radius: Zenon.rad(3)
  color: sw.colors ? sw.colors[0] : "transparent"
  border.width: 1
  border.color: Zenon.border
  // the ink, as a line of text would sit
  Rectangle {
    x: 4
    anchors.verticalCenter: parent.verticalCenter
    width: 8
    height: 2
    radius: 1
    color: sw.colors ? sw.colors[1] : "transparent"
  }
  // the accent
  Rectangle {
    anchors.right: parent.right
    anchors.rightMargin: 4
    anchors.verticalCenter: parent.verticalCenter
    width: 5
    height: 5
    radius: 2.5
    color: sw.colors ? sw.colors[2] : "transparent"
  }
}

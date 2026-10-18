// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE FEATURES — the front page's carousel, after the App Store's (user,
// 2026-10-14): each app's own screenshot full-bleed, its words over the
// lower left on a fade of the window's ground, the dots underneath, and a
// turn every nine seconds unless the pointer is resting on it.
//
// `shots` is StoreView's url → file map; a feature whose picture has not
// landed wears its color instead, so the card is never an empty frame.

import QtQuick
import Quickshell.Widgets
import "../morpheus"
import "store.js" as St

ClippingRectangle {
  id: hero
  property var apps: []
  property var shots: ({})
  property bool busy: false
  property int at: 0
  signal opened(var app)
  signal got(var app)
  signal launched(var app)
  signal removed(var app)

  readonly property var app: hero.apps.length ? hero.apps[Math.min(hero.at, hero.apps.length - 1)] : null
  function turn(d) {
    if (hero.apps.length < 2) return;
    hero.at = (hero.at + d + hero.apps.length) % hero.apps.length;
    turner.restart();
  }
  onAppsChanged: if (hero.at >= hero.apps.length) hero.at = 0

  radius: Zenon.windowRadius
  color: Zenon.wash(0.04)
  border.width: 1
  border.color: Zenon.border

  Timer {
    id: turner
    interval: 9000
    repeat: true
    running: hero.visible && hero.apps.length > 1 && !heroMa.containsMouse
    onTriggered: hero.turn(1)
  }

  // ── the pictures, one per feature, crossfading ───────────────────────
  Repeater {
    model: hero.apps
    delegate: Item {
      id: slide
      required property var modelData
      required property int index
      readonly property string file: hero.shots[slide.modelData.shot] || ""
      readonly property color brand: slide.modelData.color ? slide.modelData.color : Zenon.cyan
      anchors.fill: parent
      opacity: slide.index === hero.at ? 1 : 0
      visible: opacity > 0
      Behavior on opacity { NumberAnimation { duration: Zenon.ms(520); easing.type: Easing.InOutQuad } }
      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: Zenon.alpha(slide.brand, 0.38) }
          GradientStop { position: 1.0; color: Zenon.alpha(slide.brand, 0.08) }
        }
      }
      Image {
        anchors.fill: parent
        source: slide.file !== "" ? "file://" + slide.file : ""
        fillMode: Image.PreserveAspectCrop
        verticalAlignment: Image.AlignTop
        asynchronous: true
        sourceSize.width: 1600
        smooth: true
        mipmap: true
        opacity: status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Zenon.ms(300) } }
      }
    }
  }

  // ── the fade the words stand on: the window's own ground, rising from
  // the lower left, so the text reads in a light theme as in a dark one ──
  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      GradientStop { position: 0.35; color: Zenon.alpha(Zenon.layerBg, 0.0) }
      GradientStop { position: 1.0; color: Zenon.alpha(Zenon.layerBg, 0.92) }
    }
  }
  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: Zenon.alpha(Zenon.layerBg, 0.55) }
      GradientStop { position: 0.6; color: Zenon.alpha(Zenon.layerBg, 0.0) }
    }
  }

  MouseArea {
    id: heroMa
    anchors.fill: parent
    hoverEnabled: true
    onClicked: if (hero.app) hero.opened(hero.app)
  }

  // ── its words ───────────────────────────────────────────────────────
  Row {
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.leftMargin: 34
    anchors.bottomMargin: 30
    spacing: 18
    StoreIcon {
      anchors.bottom: parent.bottom
      app: hero.app
      size: 76
    }
    Column {
      anchors.bottom: parent.bottom
      width: Math.min(560, hero.width * 0.55)
      spacing: 5
      Text {
        readonly property var sec: St.sectionOf(hero.app)
        text: "FEATURED" + (sec ? "  ·  " + sec[1].toUpperCase() : "")
        color: Zenon.white
        opacity: 0.8
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(12)
        font.letterSpacing: 1.2
      }
      Text {
        width: parent.width
        elide: Text.ElideRight
        text: hero.app ? hero.app.name : ""
        color: Zenon.white
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(32)
      }
      Text {
        width: parent.width
        elide: Text.ElideRight
        text: hero.app ? hero.app.summary : ""
        color: Zenon.white
        opacity: 0.85
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(16)
      }
      Item { width: 1; height: 6 }
      // Open, then the trash after it, as on the app's page and the cards
      Row {
        spacing: 12
        StoreGet {
          big: true
          app: hero.app
          busy: hero.busy
          onGot: hero.got(hero.app)
          onLaunched: hero.launched(hero.app)
        }
        StoreRemove {
          visible: !!hero.app && !!hero.app.installed
          anchors.verticalCenter: parent.verticalCenter
          big: true
          busy: hero.busy
          onRemoved: hero.removed(hero.app)
        }
      }
    }
  }

  // ── where in the turn: a pill for this one, dots for the rest ───────
  Rectangle {
    visible: hero.apps.length > 1
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.rightMargin: 30
    anchors.bottomMargin: 34
    width: dotRow.implicitWidth + 18
    height: 20
    radius: Zenon.windowRadius
    color: Zenon.alpha(Zenon.layerBg, 0.6)
    Row {
      id: dotRow
      anchors.centerIn: parent
      spacing: 6
      Repeater {
        model: hero.apps.length
        delegate: Rectangle {
          required property int index
          width: index === hero.at ? 18 : 6
          height: 6
          radius: 3
          color: Zenon.white
          opacity: index === hero.at ? 0.95 : 0.4
          Behavior on width { NumberAnimation { duration: Zenon.ms(260); easing.type: Easing.OutCubic } }
          MouseArea {
            anchors.fill: parent
            anchors.margins: -5
            onClicked: { hero.at = index; turner.restart(); }
          }
        }
      }
    }
  }

  // ── turn by hand ────────────────────────────────────────────────────
  // picasso's edge tabs (morpheus/EdgeTab), out of the carousel's sides
  // (user, 2026-10-17: the bare ‹ › were hardly visible)
  Repeater {
    model: hero.apps.length > 1 ? [-1, 1] : []
    delegate: EdgeTab {
      required property var modelData
      edge: modelData < 0 ? "left" : "right"
      anchors.verticalCenter: parent.verticalCenter
      x: modelData < 0 ? 0 : hero.width - width
      onClicked: hero.turn(modelData)
    }
  }
}

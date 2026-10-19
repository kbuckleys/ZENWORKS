// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// HOW IT FELT — Apple's State of Mind, on a journal entry: a place on the
// scale from very unpleasant to very pleasant, the words that describe it,
// and what it was about. Kept on the entry (notes.js MOODS, FEELINGS).

import QtQuick
import "../morpheus"
import "notes.js" as N

Column {
  id: mb
  property var win: null
  signal closed()
  readonly property var n: mb.win ? mb.win.current : null
  property int v: 0
  property bool chosen: false
  property var words: []
  property var about: []
  readonly property var mood: N.moodOf(mb.v)
  readonly property color ink: Zenon[mb.mood.ink] || Zenon.accentMuted

  // what the entry already says, each time the sheet comes up
  onNChanged: mb.reset()
  Connections { target: mb.win; function onMoodOpenChanged() { if (mb.win.moodOpen) mb.reset(); } }
  function reset() {
    const m = mb.n && mb.n.mood;
    mb.chosen = !!m;
    mb.v = m ? m.v : 0;
    mb.words = m ? m.words.slice() : [];
    mb.about = m ? (m.about || []).slice() : [];
  }
  function toggle(list, w) { return list.indexOf(w) >= 0 ? list.filter((x) => x !== w) : list.concat([w]); }
  function save(clear) {
    if (mb.n) mb.win.mgr.setField(mb.n.id, "mood", clear ? null : { v: mb.v, words: mb.words, about: mb.about }, false);
    mb.closed();
  }

  padding: 22
  spacing: 16

  Text {
    text: "How did it feel?"
    color: Zenon.ink
    font.family: Zenon.face
    font.weight: Font.Bold
    font.pixelSize: Zenon.px(19)
  }
  // the scale: seven places, the chosen one large and lit
  Item {
    width: mb.width - 44
    height: 74
    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: -10
      x: 20
      width: parent.width - 40
      height: 4
      radius: height / 2
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: Zenon.magenta }
        GradientStop { position: 0.5; color: Zenon.accentMuted }
        GradientStop { position: 1; color: Zenon.yellow }
      }
    }
    Repeater {
      model: N.MOODS
      delegate: Item {
        required property var modelData
        required property int index
        readonly property bool on: mb.chosen && mb.v === modelData.v
        x: 20 + index * (parent.width - 40) / 6 - width / 2
        width: 44
        height: parent.height
        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          y: 27 - height / 2
          width: parent.on ? 34 : 18
          height: width
          radius: width / 2
          color: Zenon[modelData.ink] || Zenon.accentMuted
          border.width: parent.on ? 3 : 0
          border.color: Zenon.ink
          Behavior on width { NumberAnimation { duration: Zenon.fast; easing.type: Easing.OutBack } }
        }
        MouseArea { anchors.fill: parent; onClicked: { if (mb.v !== modelData.v) mb.words = []; mb.v = modelData.v; mb.chosen = true; } }
      }
    }
    Text {
      anchors.bottom: parent.bottom
      anchors.horizontalCenter: parent.horizontalCenter
      text: mb.chosen ? mb.mood.label : "Choose a place on the scale"
      color: mb.chosen ? mb.ink : Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Font.Bold
      font.pixelSize: Zenon.px(15)
    }
  }
  Text {
    visible: mb.chosen
    text: "What best describes it?"
    color: Zenon.accentMuted
    font.family: Zenon.face
    font.weight: Font.DemiBold
    font.pixelSize: Zenon.px(13)
  }
  Flow {
    visible: mb.chosen
    width: mb.width - 44
    spacing: 6
    Repeater {
      model: N.FEELINGS[String(mb.v)] || []
      delegate: MoodChip { required property string modelData; word: modelData; on: mb.words.indexOf(modelData) >= 0; ink: mb.ink; onClicked: mb.words = mb.toggle(mb.words, modelData) }
    }
  }
  Text {
    visible: mb.chosen
    text: "What is having the biggest impact?"
    color: Zenon.accentMuted
    font.family: Zenon.face
    font.weight: Font.DemiBold
    font.pixelSize: Zenon.px(13)
  }
  Flow {
    visible: mb.chosen
    width: mb.width - 44
    spacing: 6
    Repeater {
      model: N.ABOUT
      delegate: MoodChip { required property string modelData; word: modelData; on: mb.about.indexOf(modelData) >= 0; ink: Zenon.cyan; onClicked: mb.about = mb.toggle(mb.about, modelData) }
    }
  }
  Item {
    width: mb.width - 44
    height: 32
    Row {
      anchors.right: parent.right
      spacing: 8
      DialogButton { visible: !!mb.n && !!mb.n.mood; label: "Clear"; ink: Zenon.red; onClicked: mb.save(true) }
      DialogButton { label: "Cancel"; onClicked: mb.closed() }
      DialogButton { label: "Save"; ink: Zenon.cyan; primary: true; ready: mb.chosen; onClicked: mb.save(false) }
    }
  }
}

// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// MOMENTS — Apple's journaling suggestions, from what this machine has:
// the pictures taken or saved on each of the last thirty days (the
// Pictures directory), to write about with them in the entry; and a few
// reflections to start from. Nothing leaves the machine.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../morpheus"
import "../terminus"
import "notes.js" as N

Item {
  id: mo
  property var win: null
  property bool shown: false
  signal closed()
  // [{ day, ms, paths: [] }], newest first
  property var days: []
  property var chosen: ({})
  property bool scanning: false
  onShownChanged: if (mo.shown) { mo.chosen = ({}); mo.scan(); }

  function scan() {
    mo.scanning = true;
    finder.running = false;
    finder.running = true;
  }
  Process {
    id: finder
    command: ["sh", "-c", "d=$(xdg-user-dir PICTURES 2>/dev/null); [ -d \"$d\" ] || d=\"$HOME/Pictures\"; "
      + "find \"$d\" -maxdepth 4 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.heic' -o -iname '*.gif' \\) "
      + "-newermt '-30 days' -not -path '*/.*' -printf '%T@\\t%p\\n' 2>/dev/null | sort -rn | head -n 400"]
    stdout: StdioCollector {
      id: found
      waitForEnd: true
      onStreamFinished: {
        const by = {};
        const order = [];
        for (const line of found.text.split("\n")) {
          const t = line.indexOf("\t");
          if (t < 0) continue;
          const ms = parseFloat(line.slice(0, t)) * 1000;
          const k = N.dayKey(ms);
          if (!by[k]) { by[k] = { day: k, ms: N.dayStart(ms) + 12 * 3600000, paths: [] }; order.push(k); }
          if (by[k].paths.length < 12) by[k].paths.push(line.slice(t + 1));
        }
        mo.days = order.map((k) => by[k]);
        mo.scanning = false;
      }
    }
  }
  function toggle(p) {
    const c = Object.assign({}, mo.chosen);
    if (c[p]) delete c[p]; else c[p] = true;
    mo.chosen = c;
  }

  Row {
    x: 20
    y: 16
    spacing: 12
    Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{F02EF}"; color: Zenon.magenta; font.family: Zenon.glyphFace; font.pixelSize: Zenon.px(18) }
    Text { anchors.verticalCenter: parent.verticalCenter; text: "Moments"; color: Zenon.ink; font.family: Zenon.face; font.weight: Font.Bold; font.pixelSize: Zenon.px(19) }
    Text { anchors.verticalCenter: parent.verticalCenter; text: "pictures from the last 30 days, and things to write about"; color: Zenon.accentMuted; font.family: Zenon.face; font.weight: Zenon.weight; font.pixelSize: Zenon.px(13) }
  }
  DialogButton { anchors.right: parent.right; anchors.rightMargin: 20; y: 16; label: "Close"; onClicked: mo.closed() }

  Flickable {
    id: flick
    anchors.fill: parent
    anchors.topMargin: 60
    anchors.margins: 18
    contentHeight: col.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    Column {
      id: col
      width: flick.width
      spacing: 14

      // reflections
      Text { text: "REFLECTIONS"; color: Zenon.accentMuted; font.family: Zenon.face; font.weight: Font.DemiBold; font.pixelSize: Zenon.px(11); font.letterSpacing: 0.8 }
      Flow {
        width: parent.width
        spacing: 8
        Repeater {
          model: [0, 1, 2, 3, 4, 5].map((i) => N.promptOfDay(Date.now(), i * 7 + 1))
          delegate: Rectangle {
            required property string modelData
            width: Math.min(col.width, pt.implicitWidth + 28)
            height: pt.implicitHeight + 18
            radius: Zenon.windowRadius + 2
            color: Zenon.alpha(Zenon.magenta, 0.08)
            border.width: 1
            border.color: Zenon.alpha(Zenon.magenta, 0.28)
            Text {
              id: pt
              x: 14
              y: 9
              width: Math.min(implicitWidth, col.width - 28)
              wrapMode: Text.Wrap
              text: modelData
              color: Zenon.ink
              font.family: Zenon.face
              font.weight: Font.DemiBold
              font.pixelSize: Zenon.px(14)
            }
            MouseArea { anchors.fill: parent; onClicked: { mo.closed(); mo.win.newEntry(Date.now(), modelData); } }
          }
        }
      }

      // the days, and their pictures
      Text { text: "PICTURES"; color: Zenon.accentMuted; font.family: Zenon.face; font.weight: Font.DemiBold; font.pixelSize: Zenon.px(11); font.letterSpacing: 0.8 }
      Working { running: mo.scanning; visible: running }
      Text {
        visible: !mo.scanning && mo.days.length === 0
        text: "No pictures in the last 30 days"
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(14)
      }
      Repeater {
        model: mo.days
        delegate: Column {
          id: dayCol
          required property var modelData
          readonly property var picked: modelData.paths.filter((p) => !!mo.chosen[p])
          width: col.width
          spacing: 8
          Item {
            width: parent.width
            height: 28
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: N.dateLong(dayCol.modelData.ms)
              color: Zenon.ink
              font.family: Zenon.face
              font.weight: Font.Bold
              font.pixelSize: Zenon.px(15)
            }
            DialogButton {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              label: dayCol.picked.length > 0 ? "Write with " + dayCol.picked.length : "Write about this day"
              ink: Zenon.magenta
              onClicked: { mo.closed(); mo.win.entryWithPictures(dayCol.modelData.ms, dayCol.picked.length > 0 ? dayCol.picked : dayCol.modelData.paths.slice(0, 4)); }
            }
          }
          Flow {
            width: parent.width
            spacing: 6
            Repeater {
              model: dayCol.modelData.paths
              delegate: ClippingRectangle {
                required property string modelData
                width: 104
                height: 104
                radius: Zenon.windowRadius
                color: Zenon.wash(0.05)
                Image {
                  anchors.fill: parent
                  source: "file://" + modelData
                  sourceSize.width: 220
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                }
                Rectangle {
                  anchors.fill: parent
                  color: "transparent"
                  radius: Zenon.windowRadius
                  border.width: mo.chosen[modelData] ? 3 : 0
                  border.color: Zenon.magenta
                }
                Rectangle {
                  visible: !!mo.chosen[modelData]
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: 6
                  width: 20
                  height: 20
                  radius: 10
                  color: Zenon.magenta
                  Text { anchors.centerIn: parent; text: ""; color: Zenon.onAccent; font.family: Zenon.glyphFace; font.pixelSize: Zenon.px(11) }
                }
                MouseArea { anchors.fill: parent; onClicked: mo.toggle(modelData) }
              }
            }
          }
        }
      }
    }
  }
  ElasticScroll { anchors.fill: flick; view: flick }
}

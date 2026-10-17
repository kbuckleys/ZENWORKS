// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// MOMENTS — Apple's journaling suggestions, from what this machine has:
// the pictures taken or saved on each of the last thirty days (the
// Pictures directory), to write about with them in the entry; and a few
// reflections to start from. Nothing leaves the machine.
//
// The tiles are drawn from the shell's one thumbnail pool (morpheus/thumbs.js),
// as terminus' and picasso's are: the pool's index answers for a picture already
// cached on the frame its tile is made, and the rest are made in one batch in the
// background — never the 12MB original decoded for a 104px tile (user, 2026-10-17).

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../morpheus"
import "../terminus"
import "notes.js" as N
import "../morpheus/thumbs.js" as Thumbs

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

  // ── THE POOL ──
  // path → its thumbnail, or "" for "use the original" (one with
  // transparency, which the pool will not hold as JPEG; or one nothing came
  // of). A path not in it yet is waiting.
  property var thumbs: ({})
  property var thumbIndex: ({})
  FileView {
    id: indexFile
    path: Thumbs.indexPath()
    blockLoading: true
    printErrors: false
    onTextChanged: {
      let o = null;
      try { o = JSON.parse(String(indexFile.text() || "{}")); } catch (e) { o = null; }
      mo.thumbIndex = (o && typeof o === "object" && !Array.isArray(o)) ? o : ({});
    }
  }
  function thumbOf(p) {
    const t = mo.thumbs[p];
    return t === undefined ? "" : "file://" + (t !== "" ? t : p);
  }
  // what the index already knows, at once; the rest asked of the pool
  function pool(rows) {
    const t = {}, miss = [];
    for (const r of rows) {
      const hit = Thumbs.indexHit(mo.thumbIndex, r.path, r.size, r.mtime);
      if (hit === "") miss.push(r.path);
      else t[r.path] = Thumbs.isNone(hit) ? "" : hit;
    }
    mo.thumbs = t;
    maker.running = false;
    maker.batch = miss;
    if (miss.length === 0) return;
    maker.command = ["sh", "-c", Thumbs.generate(miss.map((p) => ({ kind: "i", src: p })), false)];
    maker.running = true;
  }
  property var landed: ({})
  Process {
    id: maker
    property var batch: []
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: (line) => {
        const cut = line.indexOf("\t");
        if (cut <= 0) return;
        mo.landed[line.slice(0, cut)] = line.slice(cut + 1);
        if (!flush.running) flush.start();
      }
    }
    onRunningChanged: {
      if (running) return;
      // not reported is not made: the original, then
      for (const p of maker.batch) if (!(p in mo.landed) && !(p in mo.thumbs)) mo.landed[p] = "";
      mo.take();
    }
  }
  // handed over every few frames, not per line
  Timer { id: flush; interval: 120; onTriggered: mo.take() }
  function take() {
    const keys = Object.keys(mo.landed);
    if (keys.length === 0) return;
    const t = Object.assign({}, mo.thumbs);
    for (const k of keys) t[k] = Thumbs.isNone(mo.landed[k]) ? "" : mo.landed[k];
    mo.landed = ({});
    mo.thumbs = t;
  }

  function scan() {
    mo.scanning = true;
    indexFile.reload();
    finder.running = false;
    finder.running = true;
  }
  Process {
    id: finder
    command: ["sh", "-c", "d=$(xdg-user-dir PICTURES 2>/dev/null); [ -d \"$d\" ] || d=\"$HOME/Pictures\"; "
      + "find \"$d\" -maxdepth 4 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.heic' -o -iname '*.gif' \\) "
      + "-newermt '-30 days' -not -path '*/.*' -printf '%T@\\t%s\\t%p\\n' 2>/dev/null | sort -rn | head -n 400"]
    stdout: StdioCollector {
      id: found
      waitForEnd: true
      onStreamFinished: {
        const by = {};
        const order = [];
        const rows = [];
        for (const line of found.text.split("\n")) {
          const f = line.split("\t");
          if (f.length < 3) continue;
          const mtime = parseFloat(f[0]);
          const path = f.slice(2).join("\t");
          const ms = mtime * 1000;
          const k = N.dayKey(ms);
          if (!by[k]) { by[k] = { day: k, ms: N.dayStart(ms) + 12 * 3600000, paths: [] }; order.push(k); }
          if (by[k].paths.length < 12) {
            by[k].paths.push(path);
            rows.push({ path: path, size: Number(f[1]), mtime: mtime });
          }
        }
        mo.pool(rows);
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
            // pressed darkens, as every button's press does (user, 2026-10-17)
            color: chipPress.pressed ? Zenon.alpha(Zenon.magenta, 0.24) : chipPress.containsMouse ? Zenon.alpha(Zenon.magenta, 0.14) : Zenon.alpha(Zenon.magenta, 0.08)
            border.width: 1
            border.color: Zenon.alpha(Zenon.magenta, chipPress.pressed ? 0.5 : 0.28)
            scale: chipPress.pressed ? 0.97 : 1
            Behavior on scale { NumberAnimation { duration: 90 } }
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
            MouseArea { id: chipPress; anchors.fill: parent; hoverEnabled: true; onClicked: { mo.closed(); mo.win.newEntry(Date.now(), modelData); } }
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
                  source: mo.thumbOf(modelData)
                  sourceSize.width: Thumbs.size()
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  // faded in as it arrives, not popped in (2026-10-17)
                  opacity: status === Image.Ready ? 1 : 0
                  Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
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
                // pressed darkens
                Rectangle { anchors.fill: parent; color: "black"; opacity: tilePress.pressed ? 0.22 : 0 }
                MouseArea { id: tilePress; anchors.fill: parent; onClicked: mo.toggle(modelData) }
              }
            }
          }
        }
      }
    }
  }
  ElasticScroll { anchors.fill: flick; view: flick }
}

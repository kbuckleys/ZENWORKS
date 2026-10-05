// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE VIEWER'S MAP — where the pictures shown were taken, as pins on
// OpenStreetMap. Loaded by ViewerWindow by its url (a Loader's source), only
// while the window is in its map mode.
//
// THE TILES ARE FETCHED ONCE AND KEPT, under the cache's picasso/tiles, by
// curl with a name of its own (viewer.js tileCommand) — OpenStreetMap's tile
// policy asks for both. Nothing is fetched until the map is opened, and then
// only the tiles on screen: the map is the one place the viewer goes online.
//
// Pins near each other on screen are one, with a count (viewer.js
// clusterPins). A pin of one opens its picture; of several, the map zooms in
// on them — or, as far in as it goes, opens the first.
//
//   drag  pan        wheel  zoom, about the pointer      + - 0  zoom, fit

import QtQuick
import Quickshell
import Quickshell.Io
import "../morpheus"
import "viewer.js" as V

Item {
  id: map
  clip: true

  // [{ lat, lon, path }]
  property var points: []
  // path -> its thumbnail, the window's
  property var thumbs: ({})
  signal opened(string path)
  signal wantThumb(string path)

  property real zoom: 2
  property real clat: 20
  property real clon: 0
  readonly property int iz: Math.max(1, Math.min(19, Math.round(map.zoom)))
  // the middle, in world pixels at the zoom shown
  readonly property real cx: V.lonToX(map.clon, map.iz) * V.TILE
  readonly property real cy: V.latToY(map.clat, map.iz) * V.TILE

  // On the pictures — or, handed a place, on that, close in.
  // nothing is fetched before start() has said where to look
  property bool started: false
  function start(at) {
    map.started = true;
    if (at && isFinite(at.lat) && isFinite(at.lon)) { map.zoom = 15; map.clat = at.lat; map.clon = at.lon; return; }
    map.fit();
  }
  function fit() {
    const f = V.fitMap(map.points, Math.max(200, map.width), Math.max(200, map.height));
    map.zoom = f.z; map.clat = f.lat; map.clon = f.lon;
  }
  // The world pixel at the zoom shown, made the middle.
  function centreOnWorld(wx, wy) {
    map.clon = V.xToLon(wx / V.TILE, map.iz);
    map.clat = V.yToLat(wy / V.TILE, map.iz);
  }
  function panBy(dx, dy) { map.centreOnWorld(map.cx - dx, map.cy - dy); }
  // A step in or out, keeping what is under (px, py) there.
  function zoomBy(d, px, py) {
    const nz = Math.max(1, Math.min(19, map.iz + d));
    if (nz === map.iz) return;
    const x = px === undefined ? map.width / 2 : px, y = py === undefined ? map.height / 2 : py;
    const lon = V.xToLon((map.cx + x - map.width / 2) / V.TILE, map.iz);
    const lat = V.yToLat((map.cy + y - map.height / 2) / V.TILE, map.iz);
    map.zoom = nz;
    const wx = V.lonToX(lon, nz) * V.TILE, wy = V.latToY(lat, nz) * V.TILE;
    map.centreOnWorld(wx - (x - map.width / 2), wy - (y - map.height / 2));
  }

  Rectangle { anchors.fill: parent; color: "#1b1d22" }

  // ── the tiles ─────────────────────────────────────────────────────────
  // The range on screen as a string: the Repeater is rebuilt when a tile
  // comes into view, not on every pixel of a drag.
  readonly property string range: {
    const n = Math.pow(2, map.iz);
    const x0 = Math.floor((map.cx - map.width / 2) / V.TILE), x1 = Math.floor((map.cx + map.width / 2) / V.TILE);
    const y0 = Math.max(0, Math.floor((map.cy - map.height / 2) / V.TILE));
    const y1 = Math.min(n - 1, Math.floor((map.cy + map.height / 2) / V.TILE));
    return [map.iz, x0, x1, y0, y1].join(",");
  }
  property var tiles: []
  onRangeChanged: map.retile()
  onStartedChanged: map.retile()
  function retile() {
    if (!map.started) return;
    const r = map.range.split(",").map(Number), out = [];
    for (let y = r[3]; y <= r[4]; ++y) for (let x = r[1]; x <= r[2]; ++x) out.push({ z: r[0], x: x, y: y });
    map.tiles = out;
  }

  readonly property string tileDir: Paths.cacheDir() + "/picasso/tiles"
  property var files: ({})
  property var asked: ({})
  property var queue: []
  property int inflight: 0
  function need(z, x, y) {
    const n = Math.pow(2, z), wx = ((x % n) + n) % n, key = z + "/" + wx + "/" + y;
    if (map.files[key] !== undefined || map.asked[key]) return;
    map.asked[key] = true;
    map.queue.push({ key: key, file: V.tileFile(map.tileDir, z, wx, y), url: V.tileUrl(z, wx, y) });
    map.pump();
  }
  function pump() {
    while (map.inflight < 4 && map.queue.length > 0) {
      const t = map.queue.pop();
      // a zoom gone past is not worth the fetch — asked again if it comes back
      if (Number(t.key.split("/")[0]) !== map.iz) { delete map.asked[t.key]; continue; }
      map.inflight++;
      const p = fetchComp.createObject(map, { key: t.key, command: ["sh", "-c", V.tileCommand(), "sh", t.file, t.url] });
      if (p) p.running = true; else map.inflight--;
    }
  }
  Component {
    id: fetchComp
    Process {
      id: fp
      property string key: ""
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: {
          const f = String(text || "").trim();
          const next = Object.assign({}, map.files);
          next[fp.key] = f;
          map.files = next;
          map.inflight--;
          map.pump();
          fp.destroy();
        }
      }
    }
  }
  function keyOf(t) {
    const n = Math.pow(2, t.z);
    return t.z + "/" + (((t.x % n) + n) % n) + "/" + t.y;
  }

  Repeater {
    model: map.tiles
    delegate: Image {
      required property var modelData
      x: modelData.x * V.TILE - map.cx + map.width / 2
      y: modelData.y * V.TILE - map.cy + map.height / 2
      width: V.TILE
      height: V.TILE
      readonly property string file: map.files[map.keyOf(modelData)] || ""
      source: file !== "" ? "file://" + file : ""
      asynchronous: true
      opacity: status === Image.Ready ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Zenon.fast } }
      Component.onCompleted: map.need(modelData.z, modelData.x, modelData.y)
    }
  }

  // ── pan and zoom ──────────────────────────────────────────────────────
  MouseArea {
    anchors.fill: parent
    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    property real lx: 0
    property real ly: 0
    onPressed: (m) => { lx = m.x; ly = m.y; }
    onPositionChanged: (m) => { map.panBy(m.x - lx, m.y - ly); lx = m.x; ly = m.y; }
    onDoubleClicked: (m) => map.zoomBy(1, m.x, m.y)
    property real wheelAcc: 0
    onWheel: (w) => {
      wheelAcc += w.angleDelta.y !== 0 ? w.angleDelta.y : w.angleDelta.x;
      if (Math.abs(wheelAcc) < 120) return;
      map.zoomBy(wheelAcc > 0 ? 1 : -1, w.x, w.y);
      wheelAcc = 0;
    }
  }

  // ── the pins ──────────────────────────────────────────────────────────
  Repeater {
    model: V.clusterPins(map.points, map.iz, 60)
    delegate: Item {
      id: pin
      required property var modelData
      readonly property string first: pin.modelData.items[0].path
      x: pin.modelData.x - map.cx + map.width / 2 - width / 2
      y: pin.modelData.y - map.cy + map.height / 2 - height
      width: 52
      height: 60
      visible: x > -width && y > -height && x < map.width && y < map.height + height
      Component.onCompleted: if (!(pin.first in map.thumbs)) map.wantThumb(pin.first)

      // the point it stands on
      Rectangle { x: pin.width / 2 - 1; y: 46; width: 2; height: 12; color: Zenon.cyan }
      Rectangle { x: pin.width / 2 - 3; y: 55; width: 6; height: 6; radius: 3; color: Zenon.cyan }
      Rectangle {
        width: 50; height: 50; radius: 25
        color: Zenon.cyan
        Thumb {
          anchors.fill: parent
          anchors.margins: 3
          radius: width / 2
          path: pin.first
          thumb: map.thumbs[pin.first] ?? ""
          wait: !(pin.first in map.thumbs)
          spinner: false
          fade: false
        }
      }
      Rectangle {
        visible: pin.modelData.n > 1
        x: 34; y: -4
        width: Math.max(22, countText.implicitWidth + 10)
        height: 22
        radius: 11
        color: Zenon.sand
        Text { id: countText; anchors.centerIn: parent; text: pin.modelData.n; color: Zenon.black
               font.family: Zenon.face; font.weight: 600; font.pixelSize: 12 }
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          if (pin.modelData.n === 1 || map.iz >= 18) { map.opened(pin.first); return; }
          map.centreOnWorld(pin.modelData.x, pin.modelData.y);
          map.zoomBy(Math.min(3, 18 - map.iz));
        }
      }
    }
  }

  // ── the credit the tiles ask for ──────────────────────────────────────
  Rectangle {
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    width: credit.implicitWidth + 14
    height: 22
    color: "#cc000000"
    Text {
      id: credit
      anchors.centerIn: parent
      text: "© OpenStreetMap contributors"
      color: creditMa.containsMouse ? Zenon.cyan : Zenon.muted
      font.family: Zenon.face
      font.pixelSize: 11
      MouseArea { id: creditMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                  onClicked: Qt.openUrlExternally("https://www.openstreetmap.org/copyright") }
    }
  }
  // the zoom, for the eye
  Rectangle {
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.margins: 12
    width: zoomCol.implicitWidth + 8
    height: zoomCol.implicitHeight + 8
    radius: 6
    color: "#cc000000"
    border.width: 1
    border.color: Zenon.border
    Column {
      id: zoomCol
      anchors.centerIn: parent
      Repeater {
        model: [{ t: "+", d: 1 }, { t: "−", d: -1 }, { t: "", d: 0 }]
        delegate: Text {
          required property var modelData
          width: 28; height: 28
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          text: modelData.t
          color: zma.containsMouse ? Zenon.cyan : Zenon.white
          font.family: Zenon.face
          font.pixelSize: 16
          MouseArea { id: zma; anchors.fill: parent; hoverEnabled: true
                      onClicked: modelData.d === 0 ? map.fit() : map.zoomBy(modelData.d) }
        }
      }
    }
  }
}

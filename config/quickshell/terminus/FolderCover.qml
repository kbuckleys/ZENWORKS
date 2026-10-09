// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// DIRECTORY COVER — a directory in a grid of pictures, drawn as its pictures.
//
// Beside a row of photographs a flat directory glyph reads as a placeholder for
// a thumbnail that never came. This draws the directory's first pictures
// instead: one picture whole, two side by side, three as one large and two
// small, four two by two — ringed in magenta, with the directory's own glyph on
// a small badge in the corner, so it still reads as somewhere to go and not as
// a picture.
//
// A directory with no pictures in it draws nothing and says so through `shown`,
// and the caller keeps its glyph. Shared by terminus' grid and picasso's
// gallery; the pictures come out of the shared thumbnail pool (thumbs.js), and
// the answer per directory is remembered shell-wide in covers.js.

import QtQuick
import Quickshell.Io
import Quickshell.Widgets
import "../morpheus"
import "../morpheus/thumbs.js" as Thumbs
import "covers.js" as Covers

Item {
  id: cover

  // The directory, and anything that changes when its contents do — its mtime.
  property string path: ""
  property real stamp: 0
  // false holds off the scan: thumbnails turned off, or the tile not a directory.
  property bool live: true
  // The badge: the glyph and ink the directory would have been drawn with.
  property string glyph: ""
  property color ink: Zenon.cyan
  property real dim: 1

  property var pics: []
  readonly property bool shown: cover.live && cover.pics.length > 0
  // "2|": the generation of the answers. The first cached an empty answer
  // from a scan a reload had killed, and the library kept it — see finish.
  readonly property string key: cover.path === "" ? "" : "2|" + cover.path + "|" + cover.stamp

  // THREE BY TWO, as large as the tile allows. Square, it took the box's
  // shorter side and came out a small block beside the photographs it shares
  // a grid with, which are landscape and fill the box's width — at the
  // Backgrounds zoom, 50px against 90. Three by two is the shape most
  // photographs are, so a row of covers and pictures reads as one row.
  readonly property real aspect: 1.5
  readonly property real coverW: Math.min(cover.width, cover.height * cover.aspect)
  readonly property real coverH: cover.coverW / cover.aspect
  // The badge and its inset scale off the short side.
  readonly property real side: cover.coverH

  // The key a running scan was started for. A delegate is recycled under a
  // new directory while its process is still out, and the answer that comes back
  // is the OLD directory's — cached under its own key, and not drawn here.
  property string asked: ""

  function begin() {
    if (!cover.live || cover.key === "") { cover.pics = []; return; }
    const hit = Covers.cache[cover.key];
    if (hit !== undefined) { cover.pics = hit; return; }
    cover.pics = [];
    if (scan.running || gen.running) { wait.restart(); return; }
    const token = Covers.take();
    if (token === 0) { wait.restart(); return; }
    cover.lease = token;
    cover.asked = cover.key;
    scan.dir = cover.path;
    scan.command = ["sh", "-c", Covers.scanCommand(cover.path, Strings.shellQuote)];
    scan.running = true;
  }

  function finish(key, urls) {
    if (cover.dying) return;
    // NOTHING IS NOT REMEMBERED. A scan killed half way — by a reload, which
    // this library survives — reports exactly what a directory with no pictures
    // does, and remembered, that directory showed its glyph until its mtime
    // changed. Asking an empty directory again costs one find.
    if (urls.length > 0) Covers.cache[key] = urls;
    Covers.give(cover.lease);
    cover.lease = 0;
    if (key === cover.key) cover.pics = urls;
    else Qt.callLater(cover.begin);
  }

  onKeyChanged: Qt.callLater(cover.begin)
  onLiveChanged: Qt.callLater(cover.begin)
  Component.onCompleted: cover.begin()
  // Handed back when the tile goes; a reload that skips this only costs
  // the lease's own timeout — see covers.js.
  property int lease: 0
  property bool dying: false
  Component.onDestruction: { cover.dying = true; Covers.give(cover.lease); }

  Timer { id: wait; interval: 120; onTriggered: cover.begin() }

  Process {
    id: scan
    property string dir: ""
    stdout: StdioCollector {
      id: scanOut
      onStreamFinished: {
        const files = String(scanOut.text || "").split("\n").filter((f) => f !== "");
        if (files.length === 0) { cover.finish(cover.asked, []); return; }
        gen.files = files;
        gen.command = ["sh", "-c",
          Thumbs.generate(files.map((f) => ({ kind: "i", src: f })), false)];
        gen.running = true;
      }
    }
  }

  Process {
    id: gen
    property var files: []
    stdout: StdioCollector {
      id: genOut
      onStreamFinished: {
        // the tile may have been recycled while the thumbnails were being
        // made — its cover is gone, and so is anything to draw them on
        if (typeof cover === "undefined" || !cover || !gen.files) return;
        const made = Thumbs.parseMade(genOut.text);
        // A picture the pool would not take — transparency, which JPEG
        // cannot hold — is drawn from itself, at a size small enough that
        // reading the original is no great cost.
        cover.finish(cover.asked, gen.files.map((f) => {
          const t = made[f];
          return (t && !Thumbs.isNone(t)) ? "file://" + t : Strings.fileUrl(f);
        }));
      }
    }
  }

  // ── THE DRAWING ───────────────────────────────────────────────────
  // Cell i of n, as a rectangle in a unit square: one whole, two halves,
  // one large and two small, or a two-by-two.
  function cell(i, n) {
    if (n <= 1) return { x: 0, y: 0, w: 1, h: 1 };
    if (n === 2) return { x: i * 0.5, y: 0, w: 0.5, h: 1 };
    if (n === 3) return i === 0 ? { x: 0, y: 0, w: 0.5, h: 1 }
                                : { x: 0.5, y: (i - 1) * 0.5, w: 0.5, h: 0.5 };
    return { x: (i % 2) * 0.5, y: Math.floor(i / 2) * 0.5, w: 0.5, h: 0.5 };
  }

  ClippingRectangle {
    id: frame
    anchors.centerIn: parent
    width: Math.round(cover.coverW)
    height: Math.round(cover.coverH)
    radius: Zenon.windowRadius
    color: Zenon.surface
    visible: cover.shown
    opacity: cover.dim

    Repeater {
      model: cover.shown ? cover.pics : []
      delegate: Image {
        id: piece
        required property string modelData
        required property int index
        // A hairline of the frame's own colour between the pieces, so a
        // mosaic reads as four pictures rather than one confused one.
        readonly property var r: cover.cell(piece.index, cover.pics.length)
        readonly property real gap: cover.pics.length > 1 ? 1 : 0
        x: Math.round(piece.r.x * frame.width) + (piece.r.x > 0 ? piece.gap : 0)
        y: Math.round(piece.r.y * frame.height) + (piece.r.y > 0 ? piece.gap : 0)
        width: Math.round(piece.r.w * frame.width) - (piece.r.x > 0 ? piece.gap : 0)
        height: Math.round(piece.r.h * frame.height) - (piece.r.y > 0 ? piece.gap : 0)
        source: piece.modelData
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: Math.ceil(frame.width)
        sourceSize.height: Math.ceil(frame.height)
        opacity: piece.status === Image.Ready ? 1 : 0
        Behavior on opacity {
          NumberAnimation { duration: Zenon.normal; easing.type: Easing.OutCubic }
        }
      }
    }
  }

  // THE CONTAINER'S EDGE. A magenta ring round the whole cover, drawn over
  // the pictures rather than clipped by them: in a grid that is mostly
  // photographs, a mosaic could otherwise pass for one more photograph, and
  // the ring says "this holds things" at a glance, before the badge is read.
  // Magenta because nothing else in either grid wears it.
  Rectangle {
    visible: cover.shown
    opacity: cover.dim
    anchors.fill: frame
    radius: frame.radius
    color: "transparent"
    border.width: 2
    border.color: Zenon.magenta
  }

  // The badge: the directory's glyph on a dark disc in the corner, so a cover
  // is still plainly a directory and still the directory it was — Pictures keeps
  // its picture glyph, Videos its camera.
  Rectangle {
    visible: cover.shown
    opacity: cover.dim
    // A quarter of the cover at most, so a small cover in a dense grid is
    // still mostly picture; the floor is where the glyph stops being legible.
    x: frame.x + inset
    y: frame.y + frame.height - height - inset
    readonly property int inset: Math.max(3, Math.round(cover.side * 0.06))
    width: Math.max(16, Math.round(cover.side * 0.22))
    height: width
    radius: width / 2
    color: Zenon.hud(0.72)
    border.width: 1
    border.color: Qt.rgba(cover.ink.r, cover.ink.g, cover.ink.b, 0.35)

    Text {
      anchors.centerIn: parent
      text: cover.glyph
      color: cover.ink
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Math.round(parent.width * 0.52)
    }
  }
}

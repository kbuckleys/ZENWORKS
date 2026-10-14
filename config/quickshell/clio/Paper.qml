// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A NOTE ON PAPER — for a PDF (and so for printing). There is no browser or
// PDF maker on the machine to hand HTML to, so the window lays the note out
// itself: its HTML (notes.js htmlOf) in a rich-text field on white A4 at
// twice the screen's 96 dpi, cut into pages where a line ends (never through
// one), each page grabbed as a picture. The backend then binds them with
// tesseract, which lays the words under the pictures, so the PDF can be
// searched and its text copied (clio/core/server.py pdf).
//
// Kept off the window's edge, out of sight; only ever drawn while making.
// The paper is white and the ink near-black in every theme: it is paper.

import QtQuick
import "../morpheus"

Item {
  id: paper
  property string face: Zenon.face
  readonly property real k: 2                       // twice 96 dpi
  readonly property int dpi: Math.round(96 * paper.k)
  readonly property int pageW: Math.round(794 * paper.k)
  readonly property int pageH: Math.round(1123 * paper.k)
  readonly property int margin: Math.round(72 * paper.k)
  readonly property int roomH: paper.pageH - 2 * paper.margin
  x: -paper.pageW - 4000
  width: paper.pageW
  height: paper.pageH
  visible: paper.busy
  property bool busy: false

  // html → page PNGs in `dir` (hidden, .clio-page-N.png: the backend takes
  // them away once bound), then done(paths)
  property var _job: null
  function make(html, dir, done) {
    if (paper.busy) { done(null); return; }
    paper._job = { dir: dir, done: done, pages: [], top: 0 };
    words.text = "<div>" + html + "</div>";
    paper.busy = true;
    // the pictures in it load as it is shown: a moment for them
    settle.restart();
  }
  Timer { id: settle; interval: 600; onTriggered: paper.nextPage() }

  // where the page that starts at `top` (in the words' own y) ends: the top
  // of the line that would cross the bottom — or the bottom itself, for a
  // picture taller than a page
  function breakAfter(top) {
    const y = top + paper.roomH;
    if (y >= words.contentHeight) return words.contentHeight;
    const r = words.positionToRectangle(words.positionAt(10, y));
    return r.y > top + 4 ? r.y : y;
  }
  function nextPage() {
    const j = paper._job;
    if (!j) return;
    if (j.top >= words.contentHeight - 1 && j.pages.length > 0) { paper.finish(); return; }
    const end = paper.breakAfter(j.top);
    words.y = paper.margin - j.top;
    hide.y = paper.margin + (end - j.top);
    const path = j.dir + "/.clio-page-" + (j.pages.length + 1) + ".png";
    Qt.callLater(() => sheet.grabToImage((res) => {
      res.saveToFile(path);
      j.pages.push(path);
      j.top = Math.max(end, j.top + 1);
      paper.nextPage();
    }, Qt.size(paper.pageW, paper.pageH)));
  }
  function finish() {
    const j = paper._job;
    paper._job = null;
    paper.busy = false;
    words.text = "";
    if (j) j.done(j.pages);
  }

  Rectangle {
    id: sheet
    width: paper.pageW
    height: paper.pageH
    color: "#ffffff"
    clip: true
    TextEdit {
      id: words
      x: paper.margin
      width: paper.pageW - 2 * paper.margin
      textFormat: TextEdit.RichText
      wrapMode: TextEdit.Wrap
      readOnly: true
      color: "#1a1a1a"
      font.family: paper.face
      font.pixelSize: Math.round(14.5 * paper.k)
    }
    // what is past this page's last line, covered (it is the next page's)
    Rectangle { id: hide; width: parent.width; height: parent.height; color: sheet.color }
  }
}

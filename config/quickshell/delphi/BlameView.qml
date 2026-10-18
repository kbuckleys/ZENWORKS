// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// WHO WROTE THIS — one file, every line with the commit that last changed it
// (repo.blame, git blame -w). A run of lines from one commit is said once,
// at its first line: who, how long ago, and what the commit was about; the
// newer the change, the brighter the bar beside it, so what moved lately
// stands out. A line's author clicked: that commit, in History.
// History's right side, in place of a file's diff.
//
//     BlameView { win: pg.win; path: "src/main.c"; rev: sha
//                 onPicked: (sha) => …; line: 40 }   // scrolled to line 40

import QtQuick
import "../morpheus"
import "delphi.js" as D

Item {
  id: bv
  property var win: null
  property string path: ""
  property string rev: ""
  property int line: 0
  signal picked(string sha)
  signal closed()

  property var got: null
  property bool loading: false
  property string failed: ""
  readonly property string codeFace: Zenon.faceCode
  // the oldest and newest change in the file: the bar's brightness between
  readonly property var span: {
    if (!bv.got) return [0, 1];
    let lo = Infinity, hi = 0;
    for (const k in bv.got.commits) {
      const t = parseInt(bv.got.commits[k].authortime || "0", 10);
      if (t > 0) { lo = Math.min(lo, t); hi = Math.max(hi, t); }
    }
    return lo === Infinity ? [0, 1] : [lo, Math.max(hi, lo + 1)];
  }
  function load() {
    bv.got = null;
    if (!bv.win || bv.path === "") return;
    const path = bv.path, rev = bv.rev;
    bv.loading = true;
    bv.win.mgr.call("blame", bv.win.root, { path: path, rev: rev || null }, (ok, res, err) => { if (!bv) return;
      if (path !== bv.path || rev !== bv.rev) return;
      bv.loading = false;
      bv.failed = ok ? "" : D.errorText(err ? err.error : "");
      bv.got = ok ? res : null;
      if (ok && bv.line > 0) Qt.callLater(() => view.positionViewAtIndex(bv.line - 1, ListView.Center));
    });
  }
  onPathChanged: bv.load()
  onRevChanged: bv.load()
  Component.onCompleted: bv.load()

  Rectangle {
    id: bar
    width: parent.width
    height: Math.round(Zenon.px(14) * 2.4)
    color: "transparent"
    Text {
      x: 16
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - 32 - closeBtn.width
      elide: Text.ElideMiddle
      textFormat: Text.StyledText
      text: "<b>Who wrote " + D.esc(D.baseName(bv.path)) + "</b>  <font color='" + Zenon.hex(Zenon.accentMuted) + "'>"
        + (bv.got ? Object.keys(bv.got.commits).length + " commits · " + bv.got.lines.length + " lines" : "") + "</font>"
      color: Zenon.ink
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(14)
    }
    DialogButton {
      id: closeBtn
      anchors.right: parent.right
      anchors.rightMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      label: "The diff"
      onClicked: bv.closed()
    }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Zenon.border }
  }

  ListView {
    id: view
    // the chosen one slides (morpheus/CursorBand), rather than each row lighting
    CursorBand { follows: view; index: bv.line - 1 }
    anchors.top: bar.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    cacheBuffer: 1200
    model: bv.got ? bv.got.lines : []
    readonly property int rowH: Math.round(Zenon.px(14) * 1.55)
    readonly property int gutter: Math.min(300, Math.round(bv.width * 0.34))
    delegate: Item {
      id: ln
      required property var modelData
      required property int index
      readonly property var c: bv.got ? bv.got.commits[ln.modelData.sha] || {} : {}
      // the first line of a run from one commit carries its words
      readonly property bool first: ln.index === 0 || bv.got.lines[ln.index - 1].sha !== ln.modelData.sha
      readonly property bool mine: /^0+$/.test(ln.modelData.sha || "")
      readonly property real age: {
        const t = parseInt(ln.c.authortime || "0", 10);
        return t > 0 ? (t - bv.span[0]) / (bv.span[1] - bv.span[0]) : 0;
      }
      width: view.width
      height: view.rowH
      Rectangle {
        anchors.fill: parent
        color: "transparent"
      }
      // the bar: brighter the newer
      Rectangle {
        x: 0
        width: 3
        height: parent.height
        color: ln.mine ? Zenon.yellow : Zenon.alpha(Zenon.cyan, 0.15 + 0.75 * ln.age)
      }
      Text {
        id: who
        x: 12
        width: view.gutter - 20
        anchors.verticalCenter: parent.verticalCenter
        visible: ln.first
        elide: Text.ElideRight
        textFormat: Text.StyledText
        text: ln.mine ? "<font color='" + Zenon.hex(Zenon.yellow) + "'>not committed yet</font>"
          : D.esc(ln.c.author || "") + "  <font color='" + Zenon.hex(Zenon.accentMuted) + "'>"
            + D.ago(parseInt(ln.c.authortime || "0", 10), Date.now()) + "  ·  " + D.esc(ln.c.summary || "") + "</font>"
        color: Zenon.accentSoft
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
        MouseArea {
          anchors.fill: parent
          enabled: !ln.mine
          onClicked: bv.picked(ln.modelData.sha)
        }
      }
      Text {
        id: num
        x: view.gutter
        width: Zenon.px(14) * 3
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        text: String(ln.index + 1)
        color: Zenon.accentMuted
        font.family: bv.codeFace
        font.pixelSize: Zenon.px(13)
      }
      Text {
        anchors.left: num.right
        anchors.leftMargin: 14
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: String(ln.modelData.text).replace(/\t/g, "    ")
        color: Zenon.ink
        font.family: bv.codeFace
        font.pixelSize: Zenon.px(14)
      }
    }
  }
  ElasticScroll { anchors.fill: view; view: view }
  Scrollbar { flick: view; anchors.right: view.right; anchors.top: view.top; anchors.bottom: view.bottom }
  Working { anchors.centerIn: view; running: bv.loading; visible: running }
  Text {
    anchors.centerIn: view
    width: view.width - 60
    visible: bv.failed !== "" && !bv.loading
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.Wrap
    text: bv.failed
    color: Zenon.red
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(14)
  }
}

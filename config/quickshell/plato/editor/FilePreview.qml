// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A FILE, SHOWN. What plato's picker previews under its list, the completion
// menu beside a path it offers, and the pointer resting on a path in the
// text (PathCard.qml): a text file through terminus' preview (plato's own
// highlighter, render.lua, or bat), a picture as itself, a directory as
// what is in it, in terminus' glyphs and inks.
//
//     FilePreview { file: "/abs/path"; codeFamily: …; pixelSize: … }
//
// `from` starts the text further down, and `hit` lights one row of it (a
// grep match). A host with something else to show — the picker's undo
// diffs — hands it in with show(). `kind` says what is on show:
// "" (nothing yet), text, image, dir, binary, empty, or missing.

import QtQuick
import Quickshell
import Quickshell.Io
import "../../morpheus"
import "../../terminus/terminus.js" as Terminus
import "../../morpheus/icons.js" as Icons

Item {
  id: fp

  property string file: ""
  property int from: 1
  property int hit: -1
  property string codeFamily: Zenon.faceFixed
  property int pixelSize: 16
  // drawn centred when not empty: the host's word for what is (not) here
  property string message: ""
  // a moment's wait before looking, so walking a list does not run a
  // preview for every row passed
  property int delay: 60
  // the image's longest side is drawn at no more than this, this far in
  property int imageSource: 900
  property int imageMargin: 0
  // the host shows its own things with show(), and no file is looked for
  property bool manual: false
  // long lines wrapped at the width rather than cut off by it
  property bool wrap: false

  // (markdown comes out rendered, as the editor draws it)
  readonly property string platoRender: Quickshell.shellDir + "/plato/nvim/render.lua"
  readonly property string kind: fp._kind
  // what the text or picture takes, for a card that sizes itself to it
  readonly property real contentW: fp._kind === "image" ? pic.implicitWidth
    : fp._kind === "" ? 0 : Math.min(textBox.implicitWidth, textBox.width) + 36
  readonly property real contentH: fp._kind === "image" ? pic.implicitHeight
    : fp._kind === "" ? 0 : textBox.contentHeight + 20
  readonly property bool imageReady: pic.status === Image.Ready

  property string _key: ""
  property string _kind: ""
  property string _rich: ""
  // the picture on show: the file it was shown FOR, not `file`, which moves
  // on a moment before the next load decides what that one is (a picture's
  // kind left in place, the next file — a .md — went to the image decoder)
  property string _pic: ""
  property var _cache: ({})

  // the file and where in it: the key for the cache, too
  readonly property string want: fp.file === "" ? "" : fp.file + (fp.from > 1 ? "#" + fp.from : "")
  onWantChanged: wait.restart()
  Component.onCompleted: if (fp.want !== "") wait.restart()
  Timer { id: wait; interval: fp.delay; onTriggered: fp.load() }

  // something of the host's own, in place of a file
  function show(key, kind, rich) {
    proc.running = false;
    fp._key = key;
    fp._kind = kind;
    fp._rich = rich;
    fp._pic = kind === "image" ? fp.file : "";
    fade.restart();
  }
  function forget() { fp._cache = ({}); fp._key = ""; fp._kind = ""; fp._rich = ""; fp._pic = ""; }
  // a text preview carries the colours of the theme it was rendered in
  Connections { target: Zenon; function onThemeEpochChanged() { fp.forget(); fp.load(); } }

  function load() {
    if (fp.manual) return;
    const key = fp.want;
    if (key === fp._key) return;
    if (key === "") { fp.show("", "", ""); return; }
    const hit = fp._cache[key];
    if (hit) { fp.show(key, hit.kind, hit.rich); return; }
    if (Terminus.isImage(fp.file.slice(fp.file.lastIndexOf("/") + 1))) {
      fp.show(key, "image", "");
      return;
    }
    // what it is first — a directory, a file, nothing — on a line of its own
    const p = "\"$1\"";
    proc.running = false;
    proc.forKey = key;
    proc.command = ["sh", "-c",
      "if [ -d " + p + " ]; then echo D; exec ls -1Ap --group-directories-first -- " + p + " 2>/dev/null | head -n 200; "
      + "elif [ -e " + p + " ]; then echo F; " + Terminus.previewCommand(fp.file, fp.platoRender, fp.from, Zenon.nvimTheme()) + "; "
      + "else echo M; fi", "sh", fp.file];
    proc.running = true;
  }

  // a directory's entries, as terminus' tree shows them
  function listing(text) {
    const names = String(text).split("\n").filter((n) => n !== "");
    if (names.length === 0) return "";
    const esc = (t) => t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    const rows = Terminus.enrich(names.map((n) => {
      const dir = n.endsWith("/");
      const name = dir ? n.slice(0, -1) : n;
      return { name: name, path: fp.file + "/" + name, isDir: dir, size: 1 };
    }), Icons);
    return "<pre style=\"white-space: pre-wrap; font-family: '" + fp.codeFamily + "';\">"
      + rows.map((e) => "<span style=\"color:" + Zenon.hex(Terminus.rowInk(e)) + "\">" + esc(e.glyph) + "  "
        + esc(e.name) + (e.isDir ? "/" : "") + "</span>").join("\n") + "</pre>";
  }

  Process {
    id: proc
    property string forKey: ""
    stdout: StdioCollector {
      id: out
      onStreamFinished: {
        const key = proc.forKey;
        if (key !== fp.want) return;
        const t = String(out.text);
        const cut = t.indexOf("\n");
        const what = cut < 0 ? t : t.slice(0, cut);
        const body = cut < 0 ? "" : t.slice(cut + 1);
        let kind, rich = "";
        if (what === "D") { rich = fp.listing(body); kind = rich === "" ? "empty" : "dir"; }
        else if (what === "F") {
          kind = Terminus.looksBinary(body) ? "binary" : body.trim() === "" ? "empty" : "text";
          if (kind === "text") rich = Terminus.ansiToRich(body, fp.codeFamily);
        } else kind = "missing";
        const c = Object.assign({}, fp._cache);
        // a handful kept: the files you go back and forth between
        const keys = Object.keys(c);
        if (keys.length > 40) delete c[keys[0]];
        c[key] = { kind: kind, rich: rich };
        fp._cache = c;
        fp.show(key, kind, rich);
      }
    }
  }

  NumberAnimation {
    id: fade
    target: fp
    property: "opacity"
    from: 0.35
    to: 1
    duration: Zenon.fast
    easing.type: Zenon.ease
  }

  // the hit: its line, lit behind the text. Its place is ASKED of the laid
  // out text, never counted as hit × a font's line spacing: the rich text's
  // own pitch is not FontMetrics', and the <pre> wraps (pre-wrap), so a long
  // line above the hit took two rows — the band drifted off its line.
  readonly property rect hitRect: fp.lineRect(fp.hit, textBox.length, textBox.width, textBox.contentHeight)
  function lineRect(n, len, w, h) {
    if (n < 0 || len === 0) return Qt.rect(0, 0, 0, 0);
    // the start of source line n: past n line ends, whichever way the
    // document keeps them (\n, a line separator, or a new block)
    // (char codes, not a regex: the QML lexer reads a \u2028 escape in a
    // regex literal as a line break, and the function failed to compile)
    const t = textBox.getText(0, len);
    let at = 0;
    for (let k = 0; k < n; k++) {
      while (at < t.length) {
        const c = t.charCodeAt(at++);
        if (c === 10 || c === 0x2028 || c === 0x2029) break;
      }
      if (at >= t.length) return Qt.rect(0, 0, 0, 0);
    }
    return textBox.positionToRectangle(at);
  }
  Rectangle {
    visible: fp._kind === "text" && fp.hit >= 0 && fp.hitRect.height > 0
    x: 8
    width: parent.width - 16
    y: textBox.y + fp.hitRect.y
    height: fp.hitRect.height
    radius: 3
    color: Qt.rgba(Zenon.sand.r, Zenon.sand.g, Zenon.sand.b, 0.14)
    Behavior on y { NumberAnimation { duration: Zenon.brisk; easing.type: Zenon.travelEase } }
  }
  // a TextEdit only for positionToRectangle (the band above); nothing in it
  // is picked, typed or focused
  TextEdit {
    id: textBox
    visible: fp._kind === "text" || fp._kind === "dir"
    enabled: false
    readOnly: true
    selectByMouse: false
    activeFocusOnPress: false
    cursorVisible: false
    x: 18
    y: 10
    width: parent.width - 36
    textFormat: TextEdit.RichText
    wrapMode: fp.wrap ? TextEdit.Wrap : TextEdit.NoWrap
    font.family: fp.codeFamily
    font.pixelSize: fp.pixelSize
    color: Zenon.white
    text: visible ? fp._rich : ""
  }
  Image {
    id: pic
    visible: fp._kind === "image"
    anchors.fill: parent
    anchors.margins: fp.imageMargin
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    sourceSize.width: fp.imageSource
    sourceSize.height: fp.imageSource
    source: fp._pic !== "" ? "file://" + fp._pic : ""
  }
  Text {
    visible: fp.message !== ""
    anchors.centerIn: parent
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: 14
    color: Zenon.muted
    text: fp.message
  }
}

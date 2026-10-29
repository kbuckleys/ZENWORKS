// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A CONFLICTED FILE, ONE CONFLICT AT A TIME — Changes' right side for a file
// git could not merge. The file as git left it, read into blocks
// (repo.conflict_blocks): what both sides agree on, folded, and each
// conflict as its two sides one above the other, named for what they are
// (D.sideNames — git's "ours" is upstream in a rebase). Each conflict takes
// one side, both (either order), or neither; Save writes those in and
// leaves the rest marked; when every one is chosen, Save and mark resolved
// stages it. The whole file one side's, and plato for anything finer, are
// still there.
//
// A file it cannot read this way — binary, or one side deleted it — is
// left to the holder's whole-file choices (`readable` false).

import QtQuick
import "../morpheus"
import "../terminus"
import "delphi.js" as D

Item {
  id: cv
  property var win: null
  property var file: null          // the Changes row: path, name, how
  signal wholeFile(string side)    // Take yours / theirs whole
  signal editIt()

  readonly property string path: cv.file ? cv.file.path : ""
  property var blocks: []
  property string token: ""
  property bool binary: false
  property bool loading: false
  property string failed: ""
  // conflict index → ours | theirs | both | theirsFirst | neither
  property var choices: ({})
  readonly property bool readable: !cv.binary && cv.failed === "" && cv.count > 0
  readonly property int count: cv.blocks.filter((b) => !!b.raw).length
  readonly property int chosen: Object.keys(cv.choices).length
  readonly property var names: cv.blocks.length > 0
    ? D.sideNames(cv.win ? cv.win.state : null, (cv.blocks.find((b) => !!b.raw) || {}).oursLabel,
                  (cv.blocks.find((b) => !!b.raw) || {}).theirsLabel)
    : D.sideNames(cv.win ? cv.win.state : null)
  readonly property string codeFace: Zenon.faceCode

  function load() {
    cv.choices = ({});
    if (!cv.win || cv.path === "") { cv.blocks = []; return; }
    const path = cv.path;
    cv.loading = true;
    cv.win.mgr.call("conflictBlocks", cv.win.root, { path: path }, (ok, res, err) => { if (!cv) return;
      if (path !== cv.path) return;
      cv.loading = false;
      cv.failed = ok ? "" : String(err && err.error || "could not read it");
      cv.blocks = ok ? res.blocks : [];
      cv.binary = ok && res.binary;
      cv.token = ok ? res.token : "";
    });
  }
  onPathChanged: cv.load()
  Component.onCompleted: cv.load()

  function choose(i, how) {
    const c = Object.assign({}, cv.choices);
    if (c[i] === how || how === "") delete c[i]; else c[i] = how;
    cv.choices = c;
  }
  function save(mark) {
    if (cv.chosen === 0 && !mark) return;
    const name = cv.file.name;
    cv.win.act("resolveBlocks", { path: cv.path, choices: cv.choices, token: cv.token, mark: mark }, {
      label: mark ? "Resolving " + name : "Saving " + name,
      then: (r) => { cv.win.say(r.marked ? name + " resolved" : r.left === 0 ? name + " saved — mark it resolved when it is right"
                                : r.left + (r.left === 1 ? " conflict" : " conflicts") + " left in " + name); if (cv) cv.load(); },
      failed: (err) => { cv.win.fail("Could not save " + name, null, err); if (cv) cv.load(); } });
  }

  // ── the blocks ─────────────────────────────────────────────────────────
  ListView {
    id: view
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: bar.top
    visible: cv.readable
    clip: true
    topMargin: 12
    bottomMargin: 12
    spacing: 10
    boundsBehavior: Flickable.StopAtBounds
    model: cv.blocks
    delegate: Item {
      id: blk
      required property var modelData
      required property int index
      readonly property var b: blk.modelData
      readonly property bool conflict: !!blk.b.raw
      // which conflict this is, counted among conflicts only
      readonly property int n: cv.blocks.slice(0, blk.index).filter((x) => !!x.raw).length
      readonly property string how: blk.conflict ? cv.choices[blk.n] || "" : ""
      property bool open: false
      width: view.width
      height: blk.conflict ? card.height : sameCol.height

      // what both sides agree on: folded to its ends when long
      Column {
        id: sameCol
        visible: !blk.conflict
        x: 18
        width: parent.width - 36
        readonly property var lines: blk.conflict ? [] : blk.b.same
        readonly property bool folds: sameCol.lines.length > 6 && !blk.open
        Repeater {
          model: sameCol.folds ? sameCol.lines.slice(0, 2) : sameCol.lines
          delegate: Text {
            required property var modelData
            width: sameCol.width
            elide: Text.ElideRight
            text: String(modelData).replace(/\r?\n$/, "") || " "
            color: Zenon.accentMuted
            font.family: cv.codeFace
            font.pixelSize: Zenon.px(14)
          }
        }
        Text {
          visible: sameCol.folds
          text: "···  " + (sameCol.lines.length - 4) + " lines the same  ···"
          color: Zenon.dimInk !== undefined ? Zenon.dimInk : Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
          MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: blk.open = true }
        }
        Repeater {
          model: sameCol.folds ? sameCol.lines.slice(-2) : []
          delegate: Text {
            required property var modelData
            width: sameCol.width
            elide: Text.ElideRight
            text: String(modelData).replace(/\r?\n$/, "") || " "
            color: Zenon.accentMuted
            font.family: cv.codeFace
            font.pixelSize: Zenon.px(14)
          }
        }
      }

      // a conflict: its two sides and the ways to settle it
      Rectangle {
        id: card
        visible: blk.conflict
        x: 12
        width: parent.width - 24
        height: cardCol.implicitHeight + 24
        radius: Zenon.windowRadius
        color: Zenon.wash(0.04)
        border.width: 1
        border.color: blk.how !== "" ? Zenon.alpha(Zenon.green, 0.5) : Zenon.alpha(Zenon.red, 0.45)
        Column {
          id: cardCol
          x: 12
          y: 12
          width: parent.width - 24
          spacing: 8
          Item {
            width: parent.width
            height: choiceRow.height
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: (blk.how !== "" ? "  " : "") + "Conflict " + (blk.n + 1) + " of " + cv.count
              color: blk.how !== "" ? Zenon.green : Zenon.red
              font.family: Zenon.face
              font.weight: Font.Bold
              font.pixelSize: Zenon.px(14)
            }
            Row {
              id: choiceRow
              anchors.right: parent.right
              spacing: 6
              Segments {
                textSize: Zenon.px(13)
                options: [["ours", cv.names.ours], ["theirs", cv.names.theirs], ["both", "Both"], ["neither", "Neither"]]
                current: blk.how === "theirsFirst" ? "both" : blk.how
                onChose: (v) => cv.choose(blk.n, v)
              }
            }
          }
          // both, in which order: theirs above when asked
          Text {
            visible: blk.how === "both" || blk.how === "theirsFirst"
            text: blk.how === "both" ? cv.names.ours + " first  ·  <u>" + cv.names.theirs + " first instead</u>"
                                     : cv.names.theirs + " first  ·  <u>" + cv.names.ours + " first instead</u>"
            textFormat: Text.StyledText
            color: Zenon.accentMuted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(13)
            MouseArea { anchors.fill: parent; onClicked: cv.choose(blk.n, blk.how === "both" ? "theirsFirst" : "both") }
          }
          Repeater {
            model: blk.conflict ? [["ours", cv.names.ours, blk.b.oursLabel, blk.b.ours],
                                   ["theirs", cv.names.theirs, blk.b.theirsLabel, blk.b.theirs]] : []
            delegate: Column {
              id: side
              required property var modelData
              readonly property bool kept: blk.how === "" || blk.how === side.modelData[0] || blk.how === "both" || blk.how === "theirsFirst"
              width: cardCol.width
              spacing: 2
              opacity: side.kept ? 1 : 0.4
              Text {
                width: parent.width
                elide: Text.ElideRight
                textFormat: Text.StyledText
                text: "<b>" + side.modelData[1] + "</b>" + (side.modelData[2] ? "  <font color='" + Zenon.hex(Zenon.accentMuted) + "'>" + D.esc(side.modelData[2]) + "</font>" : "")
                  + (side.modelData[3].length === 0 ? "  <font color='" + Zenon.hex(Zenon.accentMuted) + "'>— nothing here</font>" : "")
                color: side.modelData[0] === "ours" ? Zenon.cyan : Zenon.magenta
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(13)
              }
              Rectangle {
                width: parent.width
                height: sideText.implicitHeight + 10
                visible: side.modelData[3].length > 0
                radius: Zenon.radiusControl
                color: Zenon.alpha(side.modelData[0] === "ours" ? Zenon.cyan : Zenon.magenta, 0.08)
                Text {
                  textFormat: Text.PlainText
                  id: sideText
                  x: 8
                  y: 5
                  width: parent.width - 16
                  wrapMode: Text.WrapAnywhere
                  text: side.modelData[3].map((l) => String(l).replace(/\r?\n$/, "")).join("\n")
                  color: Zenon.ink
                  font.family: cv.codeFace
                  font.pixelSize: Zenon.px(14)
                }
              }
            }
          }
        }
      }
    }
  }
  ElasticScroll { anchors.fill: view; view: view; visible: view.visible }
  Scrollbar { flick: view; visible: view.visible; anchors.right: view.right; anchors.top: view.top; anchors.bottom: view.bottom }
  Working { anchors.centerIn: view; running: cv.loading && cv.blocks.length === 0; visible: running }

  // ── what to do with it ─────────────────────────────────────────────────
  Rectangle {
    id: bar
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: cv.readable ? 56 : 0
    visible: cv.readable
    color: "transparent"
    Rectangle { width: parent.width; height: 1; color: Zenon.border }
    Text {
      x: 16
      anchors.verticalCenter: parent.verticalCenter
      text: cv.chosen + " of " + cv.count + " chosen"
      color: cv.chosen === cv.count ? Zenon.green : Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.features: { "tnum": 1 }
      font.pixelSize: Zenon.px(14)
    }
    Row {
      anchors.right: parent.right
      anchors.rightMargin: 12
      anchors.verticalCenter: parent.verticalCenter
      spacing: 8
      DialogButton { label: "All " + cv.names.ours.toLowerCase(); onClicked: cv.wholeFile("ours") }
      DialogButton { label: "All " + cv.names.theirs.toLowerCase(); onClicked: cv.wholeFile("theirs") }
      DialogButton { label: "Edit in plato"; onClicked: cv.editIt() }
      DialogButton { label: "Save"; ready: cv.chosen > 0 && cv.chosen < cv.count; onClicked: cv.save(false) }
      DialogButton { label: "Save and mark resolved"; ink: Zenon.green; primary: true; ready: cv.chosen === cv.count; onClicked: cv.save(true) }
    }
  }
}

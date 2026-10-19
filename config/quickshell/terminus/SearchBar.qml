// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A SEARCH'S OWN BAR — Finder's, under the path bar of a results tab (user,
// 2026-10-13: "open the results in a new tab with the smart directory/
// collection options, just like finder"). It says what was asked and lets
// it be asked differently without retyping it:
//
//   where    the directory it was asked from, home, or everywhere
//   what     names, or what is inside the files
//   +        more rules — the search sheet, refining this search
//   Save     keep it as a collection (the sheet's naming row)
//
// Reads the tab's spec (term.searchSpec) and changes it through
// term.respec, which runs it again in this tab. Only there on a results
// page (term.searchPage); zero high otherwise.

import QtQuick
import "../morpheus"
import "terminus.js" as Terminus

Rectangle {
  id: bar
  property var term: null

  readonly property bool on: !!term && term.searchPage
  height: bar.on ? term.headH - 2 : 0
  visible: height > 0
  clip: true
  color: term ? term.chromeBg : "transparent"

  readonly property var spec: bar.on ? term.searchSpec : null
  readonly property string home: Paths.home()
  // where it looks, as one of the switch's three, or "" for a root of the
  // sheet's own (then shown as its own option)
  readonly property string scope: {
    if (!bar.spec) return "";
    const r = String(bar.spec.root || "");
    if (r === "" || r === term.cwd) return "here";
    if (r === bar.home) return "home";
    if (r === "/") return "all";
    return "other";
  }
  readonly property var scopes: {
    if (!bar.on) return [];
    const out = [["here", "“" + (term.cwd === "/" ? "/" : Terminus.basename(term.cwd)) + "”"]];
    if (term.cwd !== bar.home) out.push(["home", "Home"]);
    if (term.cwd !== "/") out.push(["all", "Everywhere"]);
    if (bar.scope === "other")
      out.push(["other", "“" + Terminus.basename(String(bar.spec.root)) + "”"]);
    return out;
  }

  // the bar's ink fades with the rest of the chrome while a sheet is up
  readonly property real ink: term ? 1 - term.sheetInk : 1

  Row {
    anchors.left: parent.left
    anchors.leftMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    spacing: 10
    opacity: bar.ink
    enabled: bar.ink > 0.5

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "Search"
      color: Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
    }
    Segments {
      anchors.verticalCenter: parent.verticalCenter
      textSize: Zenon.px(13)
      pad: 22
      options: bar.scopes
      current: bar.scope
      onChose: (v) => {
        if (v === bar.scope || v === "other") return;
        term.respec({ root: v === "here" ? term.cwd : v === "home" ? bar.home : "/" });
      }
    }
    Segments {
      anchors.verticalCenter: parent.verticalCenter
      textSize: Zenon.px(13)
      pad: 22
      options: [["find", "Names"], ["grep", "Contents"]]
      current: bar.spec ? bar.spec.kind : ""
      onChose: (v) => { if (bar.spec && v !== bar.spec.kind) term.respec({ kind: v }); }
    }
    // the rules past the query, said rather than shown: the sheet is where
    // they are read and changed
    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: !!bar.spec && (bar.spec.rules || []).length > 0
      text: bar.spec ? "+ " + (bar.spec.rules || []).length
        + ((bar.spec.rules || []).length === 1 ? " rule" : " rules") : ""
      color: Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
    }
  }

  Row {
    anchors.right: parent.right
    anchors.rightMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    spacing: 8
    opacity: bar.ink
    enabled: bar.ink > 0.5

    // more rules: the search sheet, opened on this search. A drawn plus and
    // the word, as compact as the chip it is (user, 2026-10-14: a 96px
    // button holding a lone "+" read as unfinished)
    Rectangle {
      id: addRule
      anchors.verticalCenter: parent.verticalCenter
      width: addRow.implicitWidth + 22
      height: 28
      radius: Zenon.radiusControl
      // no hover tint, as DialogButton (user, 2026-10-11)
      color: addMa.pressed ? Zenon.pressWash(0.24) : Zenon.wash(0.12)
      border.width: 1
      border.color: Zenon.border
      Behavior on color { ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
      Row {
        id: addRow
        anchors.centerIn: parent
        spacing: 7
        Item {
          anchors.verticalCenter: parent.verticalCenter
          width: 11
          height: 11
          Repeater {
            model: [0, 90]
            Rectangle {
              required property var modelData
              anchors.centerIn: parent
              width: 11
              height: 2
              radius: height / 2
              rotation: modelData
              color: Zenon.cyan
            }
          }
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Rules"
          color: Zenon.white
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: Zenon.px(14)
        }
      }
      MouseArea {
        id: addMa
        anchors.fill: parent
        onClicked: bar.refine()
      }
    }
    DialogButton {
      anchors.verticalCenter: parent.verticalCenter
      label: "Save"
      ink: Zenon.cyan
      // the default answer, lit and breathing (user, 2026-10-14)
      primary: true
      onClicked: { bar.refine(); term.collEditRef.beginNaming(); }
    }
  }
  function refine() {
    const s = bar.spec;
    if (!s) return;
    term.lastSearch = { kind: s.kind, query: s.query, root: s.root, rules: s.rules || [] };
    term.collEditRef.askSearch("");
  }

  // the bar's edge, as the path bar's
  Rectangle {
    anchors.bottom: parent.bottom
    width: parent.width
    height: 1
    color: Zenon.border
  }
}

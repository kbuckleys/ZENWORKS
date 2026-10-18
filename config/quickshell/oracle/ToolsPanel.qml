// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// TOOLS, unfolded — Health's Tools row opened (user, 2026-10-18: "give me
// the ability to view the missing packages, be they optional or required").
//
// One row a PACKAGE (Ora.toolPackages: wl-copy and wl-paste are one
// wl-clipboard), in the box ceres' mirror list stands in
// (morpheus/controls/ListFrame) and in its rows' shape: what is missing
// first, needed then optional, each with a box to tick (morpheus/controls/
// Check — the needed ones come ticked); then what is installed, folded
// under its heading. One Install for everything ticked, through ceres;
// the checkup runs again once it lands. Without paru ceres cannot install,
// and the commands are given instead. The list itself is oracle.js TOOLS.
//
// Loaded by URL from OracleWindow, not named as a type (see ComputerPanel).

import QtQuick
import "oracle.js" as Ora
import "../morpheus"
import "../morpheus/controls" as Controls
import "../ceres"

Item {
  id: tp
  // the panel's palette, handed in rather than reached for
  property string face: Zenon.face
  property color fgColor: Zenon.white
  property color dimColor: Zenon.accentMuted
  property color highlight: Zenon.cyan

  readonly property var row: (Oracle.revision, Oracle.checkup ? Oracle.checkup.tools : null)
  readonly property var tools: tp.row && tp.row.list ? tp.row.list : []
  readonly property var pkgs: Ora.toolPackages(tp.tools)
  readonly property var needed: tp.pkgs.filter((p) => !p.have && p.core)
  readonly property var optional: tp.pkgs.filter((p) => !p.have && !p.core)
  readonly property var installed: tp.pkgs.filter((p) => p.have)
  readonly property bool busy: (Oracle.revision, !!Ceres.installing || Ceres.txBusy)
  // ceres installs through paru; without it, the commands are the way in
  readonly property bool paruGone: tp.needed.concat(tp.optional).some((p) => p.names.indexOf("paru") >= 0)
  property bool showInstalled: false

  // ── WHAT IS TICKED, by package ─────────────────────────────────────────
  // The needed ones start ticked. Picked again only when what is missing
  // changes — a checkup run again over the same answer keeps your ticks.
  property var picked: ({})
  property string pickedFor: ""
  readonly property string missingKey: tp.needed.concat(tp.optional).map((p) => p.pkg).join(" ")
  onMissingKeyChanged: {
    if (tp.missingKey === tp.pickedFor) return;
    tp.pickedFor = tp.missingKey;
    const next = {};
    for (const p of tp.needed) next[p.pkg] = true;
    tp.picked = next;
  }
  Component.onCompleted: tp.missingKeyChanged()
  function toggle(pkg) {
    const next = Object.assign({}, tp.picked);
    if (next[pkg]) delete next[pkg]; else next[pkg] = true;
    tp.picked = next;
  }
  readonly property var chosen: tp.needed.concat(tp.optional).filter((p) => !!tp.picked[p.pkg])

  function install() {
    if (!tp.chosen.length) return;
    Ceres.install(tp.chosen.map((p) => p.pkg), "for the shell's tools (Oracle › Health)",
      (ok) => { if (ok) Oracle.runCheckup(); });
  }

  // the rows, in the mirror list's shape: { head } or a package
  readonly property var rows: {
    const out = [];
    if (tp.needed.length) out.push({ head: true, name: "Not installed · needed" });
    for (const p of tp.needed) out.push({ p: p, pick: true });
    if (tp.optional.length) out.push({ head: true, name: "Not installed · optional" });
    for (const p of tp.optional) out.push({ p: p, pick: true });
    if (tp.installed.length) out.push({ head: true, fold: true, name: "Installed · " + tp.installed.length });
    if (tp.showInstalled) for (const p of tp.installed) out.push({ p: p, pick: false });
    return out;
  }

  implicitHeight: body.implicitHeight + 24

  Column {
    id: body
    x: 24
    y: 6
    width: tp.width - 48
    spacing: 10

    Working {
      running: tp.tools.length === 0 && Oracle.checking
      height: Zenon.px(20)
    }
    Text {
      visible: tp.tools.length === 0 && !Oracle.checking
      text: "Not checked yet."
      color: tp.dimColor
      font.family: tp.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(14)
    }

    // ── THE BOX ───────────────────────────────────────────────────────
    Item {
      visible: tp.tools.length > 0
      width: body.width
      height: list.implicitHeight + 12
      Controls.ListFrame { anchors.fill: parent }
      Column {
        id: list
        x: 6
        y: 6
        width: parent.width - 12
        Repeater {
          model: tp.rows
          delegate: Rectangle {
            id: r
            required property var modelData
            readonly property var p: r.modelData.p || null
            width: list.width
            height: 28
            radius: Zenon.windowRadius
            color: "transparent"

            // a missing package: its box; an installed one: the mirror rows'
            // health dot, green
            Controls.Check {
              id: box
              visible: !!r.modelData.pick
              anchors.left: parent.left
              anchors.leftMargin: 6
              anchors.verticalCenter: parent.verticalCenter
              lit: !!r.p && !!tp.picked[r.p.pkg]
              ink: r.p && r.p.core ? Zenon.red : tp.highlight
              enabled2: !tp.busy
            }
            Rectangle {
              visible: !!r.p && !r.modelData.pick
              anchors.left: parent.left
              anchors.leftMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              width: 6; height: 6; radius: 3
              color: Zenon.green
              opacity: 0.7
            }
            // a heading folds the installed ones away, as a chevron says
            Text {
              id: chev
              visible: !!r.modelData.fold
              // beside its heading, as the Tools row's own chevron is
              anchors.left: nameT.right
              anchors.leftMargin: 8
              anchors.verticalCenter: parent.verticalCenter
              text: ""
              rotation: tp.showInstalled ? 90 : 0
              Behavior on rotation { NumberAnimation { duration: Zenon.menuFade; easing.type: Easing.OutCubic } }
              color: tp.dimColor
              font.family: Zenon.glyphFace
              font.pixelSize: Zenon.px(11)
            }
            Text {
              id: nameT
              anchors.left: parent.left
              anchors.leftMargin: r.modelData.head ? 10 : r.modelData.pick ? 34 : 24
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, r.width * 0.5)
              elide: Text.ElideRight
              textFormat: Text.StyledText
              font.weight: r.modelData.head ? Font.Bold : Font.Normal
              text: {
                const m = r.modelData;
                if (m.head) return "<font color='" + tp.dimColor + "'>" + Strings.escapeHtml(m.name) + "</font>";
                const p = r.p;
                // the tools when they are not just the package's name
                const also = p.names.length > 1 || p.names[0] !== p.pkg ? p.names.join(", ") : "";
                return Strings.escapeHtml(p.pkg)
                  + (also ? "  <font color='" + tp.dimColor + "'>" + Strings.escapeHtml(also) + "</font>" : "")
                  + (p.builds ? "  <font color='" + Zenon.red + "'>AUR \u00b7 builds from source</font>"
                     : p.aur ? "  <font color='" + Zenon.yellow + "'>AUR</font>" : "");
              }
              color: r.p && r.p.core && !r.p.have ? Zenon.red : tp.fgColor
              font.family: tp.face
              font.pixelSize: Zenon.px(16)
            }
            Text {
              visible: !!r.p
              anchors.left: nameT.right
              anchors.leftMargin: 16
              anchors.right: parent.right
              anchors.rightMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              horizontalAlignment: Text.AlignRight
              elide: Text.ElideLeft
              text: r.p ? (r.p.builds && !r.p.have ? r.p.builds : r.p.why) : ""
              color: tp.dimColor
              font.family: tp.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(15)
            }
            // the whole row ticks (the box's own tap is left unanswered, so
            // a tap on it is not counted twice); the Installed heading folds
            TapHandler {
              enabled: (!!r.modelData.pick && !tp.busy) || !!r.modelData.fold
              onTapped: {
                if (r.modelData.fold) tp.showInstalled = !tp.showInstalled;
                else tp.toggle(r.p.pkg);
              }
            }
          }
        }
      }
    }

    // without paru ceres cannot install; these are the way in by hand
    Column {
      visible: tp.paruGone && !!tp.row && !!tp.row.install
      spacing: 2
      Text {
        text: "paru is missing, so ceres cannot install these yet. In a terminal:"
        color: tp.dimColor
        font.family: tp.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
      }
      Repeater {
        model: tp.paruGone && tp.row && tp.row.install ? tp.row.install : []
        delegate: TextEdit {
          required property string modelData
          readOnly: true
          selectByMouse: true
          text: modelData
          color: tp.fgColor
          selectionColor: Zenon.alpha(tp.highlight, 0.35)
          font.family: Zenon.faceMono
          font.pixelSize: Zenon.px(13)
        }
      }
    }

    Row {
      visible: tp.needed.length + tp.optional.length > 0 && !tp.paruGone
      spacing: 8
      DialogButton {
        label: tp.busy ? "Installing…"
          : tp.chosen.length ? "Install " + tp.chosen.length + (tp.chosen.length === 1 ? " package" : " packages")
          : "Install"
        ink: tp.highlight
        primary: true
        ready: !tp.busy && tp.chosen.length > 0
        onClicked: tp.install()
      }
      // anything ticked: a way to untick it all; nothing ticked: tick it all
      DialogButton {
        visible: tp.needed.length + tp.optional.length > 1 || tp.chosen.length > 0
        label: tp.chosen.length > 0 ? "Deselect all" : "Select all"
        ink: tp.fgColor
        ready: !tp.busy
        onClicked: {
          const next = {};
          if (tp.chosen.length === 0) for (const p of tp.needed.concat(tp.optional)) next[p.pkg] = true;
          tp.picked = next;
        }
      }
    }
  }
}

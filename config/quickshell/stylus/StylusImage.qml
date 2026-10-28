// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A NEW DISK IMAGE, IN A SHEET — a file that is a drive: sparse (it takes
// room only as it fills), attached as soon as it is made, and, with a
// filesystem chosen, given a GPT table and one partition of it — so it is
// in the sidebar's Disk images, ready to mount, to partition, to write
// onto. forge.py newimage; no password, it is yours.
//
//     Sheet { cardH: body.implicitHeight
//       StylusImage { id: body; width: parent.width; win: sw } }

import QtQuick
import "../morpheus"
import "../terminus"
import "../terminus/terminus.js" as Terminus
import "stylus.js" as S

FocusScope {
  id: body

  property var win: null
  readonly property var mgr: body.win ? body.win.mgr : null

  property string out: ""
  property real size: 8 * 1073741824
  property string fs: "exfat"
  property bool working: false
  property string why: ""

  function reset() {
    body.out = "";
    body.size = 8 * 1073741824;
    body.fs = "exfat";
    body.working = false;
    body.why = "";
    label.text = "";
    typed.text = "";
  }
  function choose() {
    const fm = body.mgr ? body.mgr.fileManager : null;
    if (!fm) return;
    fm.choose(false, body.out !== "" ? body.out.replace(/\/[^/]*$/, "") : UserDirs.documents, (paths) => {
      if (paths && paths.length > 0) body.out = paths[0].replace(/(\.img)?$/i, ".img");
    }, "Disk image.img");
  }
  function go() {
    if (body.out === "" || body.working) return;
    body.working = true;
    body.why = "";
    const args = ["newimage", body.out, String(S.mibDown(body.size))]
      .concat(body.fs !== "" ? ["--fs", body.fs] : [])
      .concat(body.fs !== "" && label.text.trim() !== "" ? ["--label", Terminus.cleanLabel(body.fs, label.text)] : []);
    body.mgr.ask(args, (j) => {
      body.working = false;
      if (j && j.ok) body.win.imageMade(j.dev);
      else body.why = j && j.why ? j.why : "It could not be made";
    });
  }

  implicitHeight: col.implicitHeight + 2 * 24

  Column {
    id: col
    x: 24
    y: 24
    width: parent.width - 48
    spacing: 14

    Column {
      width: parent.width
      spacing: 3
      Text {
        text: "New disk image"
        color: Zenon.ink
        font.family: Zenon.face
        font.weight: Zenon.titleWeight
        font.pixelSize: Zenon.px(17)
      }
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: "A file that is a drive — it takes room only as it fills, and is attached as soon as it is made"
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
      }
    }

    // where it goes
    Rectangle {
      width: parent.width
      height: 52
      radius: Zenon.radiusCard
      color: Zenon.wash(0.04)
      border.width: 1
      border.color: Zenon.border
      Text {
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.right: pick.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideMiddle
        text: body.out !== "" ? body.out : "Choose where to make it"
        color: body.out !== "" ? Zenon.ink : Zenon.muted
        font.family: body.out !== "" ? Zenon.faceMono : Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
      }
      DialogButton {
        id: pick
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        label: body.out !== "" ? "Change…" : "Choose…"
        primary: body.out === ""
        ink: body.out === "" ? Zenon.cyan : Zenon.accentMuted
        onClicked: body.choose()
      }
    }

    // how big: a common size, or typed
    Row {
      spacing: 10
      Segments {
        anchors.verticalCenter: parent.verticalCenter
        options: S.IMAGE_SIZES.map((g) => [String(g), g + " GiB"])
        current: String(body.size / 1073741824)
        onChose: (v) => body.size = Number(v) * 1073741824
      }
      BulkField {
        id: typed
        anchors.verticalCenter: parent.verticalCenter
        width: 110
        ghost: "or type"
        onAccepted: {
          const n = Terminus.parseSizeStr(typed.text.replace(/i?B$/i, ""));
          if (n >= 4 * S.MIB) body.size = S.mibDown(n);
        }
      }
      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        text: Terminus.formatSize(body.size)
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(12)
      }
    }

    Segments {
      options: [["exfat", "exFAT"], ["vfat", "FAT32"], ["ext4", "ext4"], ["ntfs", "NTFS"], ["btrfs", "Btrfs"], ["", "None"]]
      current: body.fs
      onChose: (v) => body.fs = v
    }
    BulkField { id: label; visible: body.fs !== ""; width: 260; ghost: "Label"; onAccepted: body.go() }

    Text {
      textFormat: Text.PlainText
      visible: body.why !== ""
      width: parent.width
      wrapMode: Text.Wrap
      text: body.why
      color: Zenon.red
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
    }

    Row {
      anchors.right: parent.right
      spacing: 10
      DialogButton { label: "Cancel"; ink: Zenon.accentMuted; onClicked: body.win.closeImage() }
      BusyButton {
        label: "Make it"
        primary: true
        ink: Zenon.cyan
        ready: body.out !== ""
        busy: body.working
        busyText: "Making it…"
        onClicked: body.go()
      }
    }
  }

  Keys.onEscapePressed: body.win.closeImage()
}

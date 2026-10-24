// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// BACKING UP A DRIVE (OR ONE VOLUME), IN A SHEET — to an image file:
// compressed (.img.zst, zstd on every core) or raw (.img, sparse), saved
// where terminus' picker says, a .sha256 beside it so a restore checks
// itself. The backup is the manager's (forge.py backup): Hide puts the
// sheet away and it goes on; Stop keeps nothing.
//
// Restoring is the write sheet with the backup as its image.
//
//     Sheet { cardH: body.implicitHeight
//       StylusBackup { id: body; width: parent.width; win: sw } }

import QtQuick
import "../morpheus"
import "../terminus"
import "../terminus/terminus.js" as Terminus
import "stylus.js" as S

FocusScope {
  id: body

  property var win: null
  readonly property var mgr: body.win ? body.win.mgr : null
  readonly property var job: body.mgr ? body.mgr.backupJob : null
  // what the sheet shows: the running or finished backup, else the one
  // picked in the sidebar
  readonly property var drive: body.job ? body.job.drive : (body.win ? body.win.drive : null)
  readonly property var part: body.job ? body.job.part : (body.win ? body.win.vol : null)
  readonly property string face: !body.job ? "choosing" : body.job.result ? "done" : "running"
  readonly property bool mounted: !!body.part ? body.part.mounts.length > 0
    : !!body.drive && (body.drive.parts || []).some((p) => p.mounts.length > 0)

  property bool compress: true
  property string out: ""

  function reset() {
    body.compress = true;
    body.out = "";
  }
  function choose() {
    const fm = body.mgr ? body.mgr.fileManager : null;
    if (!fm) return;
    const dir = body.out !== "" ? body.out.replace(/\/[^/]*$/, "") : UserDirs.documents;
    fm.choose(false, dir, (paths) => {
      if (!paths || paths.length === 0) return;
      // the extension follows the kind chosen, whatever was typed
      body.out = paths[0].replace(/(\.img)?(\.zst)?$/i, "") + (body.compress ? ".img.zst" : ".img");
    }, S.backupName(body.drive, body.part, body.compress));
  }
  function go() {
    if (body.face === "done") { body.mgr.clearBackup(); body.win.closeBackup(); return; }
    if (body.face !== "choosing" || body.out === "") return;
    body.mgr.backup(body.drive, body.part, body.out, body.compress);
  }
  onCompressChanged: if (body.out !== "") body.out = body.out.replace(/(\.img)?(\.zst)?$/i, "") + (body.compress ? ".img.zst" : ".img")

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
        width: parent.width
        elide: Text.ElideRight
        text: "Back up " + (body.part ? S.partName(body.part) : S.driveTitle(body.drive))
        color: Zenon.ink
        font.family: Zenon.face
        font.weight: Zenon.titleWeight
        font.pixelSize: Zenon.px(17)
      }
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: "Every byte of it, " + Terminus.formatSize(body.part ? body.part.size : body.drive ? body.drive.size : 0)
          + ", into one file — restore it with Write, onto this drive or another as big"
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
      }
    }

    Segments {
      visible: body.face === "choosing"
      options: [["zst", "Compressed (.img.zst)"], ["raw", "Raw (.img)"]]
      current: body.compress ? "zst" : "raw"
      onChose: (v) => body.compress = v === "zst"
    }

    // where it goes
    Rectangle {
      visible: body.face === "choosing"
      width: parent.width
      height: 52
      radius: Zenon.radiusCard
      color: Zenon.wash(0.04)
      border.width: 1
      border.color: Zenon.border
      Text {
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.right: pick.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideMiddle
        text: body.out !== "" ? body.out : "Choose where to save it"
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

    Text {
      visible: body.face === "choosing" && body.mounted
      width: parent.width
      wrapMode: Text.Wrap
      text: "Some of it is mounted: what changes while it is read may be caught half-way. Unmount it first for a clean copy."
      color: Zenon.yellow
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
    }

    // the run, and how it went
    Column {
      visible: body.face !== "choosing"
      width: parent.width
      spacing: 8
      Text {
        width: parent.width
        elide: Text.ElideMiddle
        text: body.job ? body.job.out : ""
        color: Zenon.accentMuted
        font.family: Zenon.faceMono
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(12)
      }
      Rectangle {
        id: band
        width: parent.width
        height: 8
        radius: Zenon.rad(4)
        color: Zenon.wash(0.06)
        ProgressFill {
          anchors.fill: parent
          radius: band.radius
          frac: S.phaseFrac(body.job)
          ink: body.job && body.job.result && !body.job.result.ok ? Zenon.red : Zenon.cyan
        }
      }
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: S.backupWords(body.job)
        color: body.job && body.job.result ? (body.job.result.ok ? Zenon.green : Zenon.red) : Zenon.ink
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
      }
    }

    Row {
      anchors.right: parent.right
      spacing: 10
      DialogButton {
        visible: body.face !== "done"
        label: body.face === "running" ? "Hide" : "Cancel"
        ink: Zenon.accentMuted
        onClicked: body.win.closeBackup()
      }
      DialogButton {
        visible: body.face === "running"
        label: "Stop"
        ink: Zenon.red
        onClicked: body.mgr.stopBackup()
      }
      DialogButton {
        visible: body.face !== "running"
        label: body.face === "done" ? "Done" : "Back up"
        primary: true
        ink: Zenon.cyan
        ready: body.face === "done" || body.out !== ""
        onClicked: body.go()
      }
    }
  }

  Keys.onEscapePressed: body.win.closeBackup()
  Keys.onReturnPressed: body.go()
}

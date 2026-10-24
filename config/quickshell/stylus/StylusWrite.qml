// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// WRITING AN IMAGE, IN A SHEET — what drops from stylus' toolbar over the
// drive it was opened on. Three faces, one after the other:
//
//   choosing   the image (Open… / Change…, or dropped), the other drives to
//              write at the same time, and what will be erased — in red,
//              on the button too: the sheet IS the question
//   writing    each drive with its own fill and how far; Hide puts the
//              sheet away and the write goes on (the sidebar keeps count)
//   done       how each went
//
// The face is the manager's job: none (or one for other drives) is
// choosing, so a write started here can be watched from a reopened window.
//
//     Sheet { cardH: body.implicitHeight
//       StylusWrite { id: body; width: parent.width; win: sw } }

import QtQuick
import "../morpheus"
import "../terminus"
import "stylus.js" as S

Item {
  id: body

  property var win: null

  readonly property var mgr: body.win ? body.win.mgr : null
  readonly property var job: body.mgr ? body.mgr.job : null
  readonly property string face: !body.job ? "choosing" : body.job.result ? "done" : "writing"
  readonly property var drive: body.win ? body.win.drive : null
  // the drives that may be written as well: never the system's, never a
  // write-protected one (the same rule as the toolbar's Write)
  // (none for a Windows installer: it is made onto one drive)
  readonly property var others: !body.win || (body.win.probe && body.win.probe.kind === "windows") ? []
    : body.win.drives.filter((d) => body.drive && d.block !== body.drive.block
      && d.block !== body.win.srcBlock && S.offWhy("write", d, null) === "")
  // A CLONE: another drive as the source — any but the one written,
  // the system's own included (it is only read)
  readonly property bool cloning: !!body.win && body.win.srcMode === "drive"
  readonly property var sources: body.win ? body.win.drives.filter((d) => body.drive && d.block !== body.drive.block) : []
  readonly property bool srcMounted: !!body.win && !!body.win.srcDrive
    && (body.win.srcDrive.parts || []).some((p) => p.mounts.length > 0)
  readonly property var targets: body.job ? body.job.drives : (body.win ? body.win.targets : [])
  readonly property string blocked: body.win ? body.win.blocked : ""
  // what is in the way (yellow), else what to know about the image
  readonly property string warning: body.blocked !== "" && body.blocked !== "busy" && body.blocked !== "Choose an image"
    ? body.blocked
    : body.srcMounted ? "Some of " + S.driveTitle(body.win.srcDrive) + " is mounted: what changes while it is read may be caught half-way"
    : S.writeWarning(body.win ? body.win.probe : null, !!body.win && body.win.sums.state === "bad", !!body.win && body.win.sig.level === "bad")

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
        text: body.face === "done" ? (body.job.result.ok ? "Done" : S.headWords(body.job, []))
          : body.face === "writing" ? (body.job.probe && body.job.probe.kind === "drive" ? "Copying " + body.job.probe.label
                                       : "Writing " + String(body.job.source).replace(/.*\//, ""))
          : body.cloning ? "Copy a drive onto " + S.driveTitle(body.drive)
          : "Write an image to " + S.driveTitle(body.drive)
        color: body.face === "done" && !body.job.result.ok ? Zenon.red : Zenon.ink
        font.family: Zenon.face
        font.weight: Zenon.titleWeight
        font.pixelSize: Zenon.px(17)
      }
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: body.face === "writing" ? "You can hide this — the write goes on, and the sidebar keeps count"
          : body.face === "done" ? (body.job.verify ? "Each drive was read back and compared with the image" : "")
          : body.cloning ? "The drive is erased and the other copied onto it, byte for byte"
          : body.win && body.win.probe && body.win.probe.kind === "windows"
            ? "Made the way Windows starts from it — one FAT32 partition, its files copied across — for UEFI PCs, Secure Boot on or off"
          : "The drive is erased and the image written onto it, byte for byte"
        visible: text !== ""
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
      }
    }

    // where it comes from: a file (a download, a backup), or a drive
    Segments {
      visible: body.face === "choosing" && body.sources.length > 0
      options: [["image", "An image"], ["drive", "Another drive"]]
      current: body.win ? body.win.srcMode : "image"
      onChose: (v) => body.win.setSourceMode(v)
    }
    Repeater {
      model: body.face === "choosing" && body.cloning ? body.sources : []
      StylusDrive {
        required property var modelData
        drive: modelData
        pickable: true
        picked: !!body.win && body.win.srcBlock === modelData.block
        onToggled: body.win.pickSource(modelData)
      }
    }
    StylusSource {
      visible: body.face === "choosing" && !body.cloning
      path: body.win ? body.win.path : ""
      probe: body.win ? body.win.probe : null
      sums: body.win ? body.win.sums : ({ state: "none", words: "" })
      sig: body.win ? body.win.sig : ({ words: "", level: "", key: "" })
      fetching: !!body.win && body.win.fetching
      hot: !!body.win && body.win.dropOver
      onOpen: body.win.openAsk()
      onDownload: body.win.downloadAsk()
      onFetchKey: body.win.fetchKey()
    }

    // the drive the sheet is for, then the others it may write as well
    Text {
      visible: body.face === "choosing" && body.others.length > 0
      text: "Also write to"
      color: Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Zenon.titleWeight
      font.pixelSize: Zenon.px(12)
    }
    Repeater {
      model: body.face === "choosing" ? body.others : body.targets
      StylusDrive {
        required property var modelData
        drive: modelData
        pickable: body.face === "choosing"
        picked: !!body.win && !!body.win.picked[modelData.block]
        job: body.face === "choosing" ? null : body.job
        why: body.face === "choosing" && picked && body.win.probe ? S.fits(body.win.probe, modelData).why : ""
        onToggled: body.win.toggle(modelData)
      }
    }

    Text {
      width: parent.width
      wrapMode: Text.Wrap
      visible: body.face === "choosing" && body.warning !== ""
      text: body.warning
      color: Zenon.yellow
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
    }

    // the sheet's question, one sentence in a red ring: the red button
    // under it is the answer
    Rectangle {
      visible: body.face === "choosing"
      width: parent.width
      height: notice.implicitHeight + 24
      radius: Zenon.radiusControl
      color: Zenon.alpha(Zenon.red, 0.06)
      border.width: 1
      border.color: Zenon.alpha(Zenon.red, 0.55)
      Text {
        id: notice
        anchors.centerIn: parent
        width: parent.width - 32
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: S.eraseNotice(body.targets.length)
        color: Zenon.red
        font.family: Zenon.face
        font.weight: Zenon.titleWeight
        font.pixelSize: Zenon.px(13)
      }
    }

    Row {
      anchors.right: parent.right
      spacing: 10
      DialogButton {
        visible: body.face !== "done"
        label: body.face === "writing" ? "Hide" : "Cancel"
        ink: Zenon.accentMuted
        onClicked: body.win.closeSheet()
      }
      DialogButton {
        visible: body.face === "writing"
        label: "Stop"
        ink: Zenon.red
        onClicked: body.mgr.stop()
      }
      DialogButton {
        visible: body.face === "choosing"
        label: body.targets.length > 1 ? "Erase " + body.targets.length + " drives and write" : "Erase and write"
        primary: true
        ink: Zenon.red
        ready: body.blocked === ""
        onClicked: body.win.startWrite()
      }
      DialogButton {
        visible: body.face === "done"
        label: "Done"
        primary: true
        ink: Zenon.cyan
        onClicked: body.win.closeSheet()
      }
    }
  }
}

// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// DOWNLOADING A LINUX, IN A SHEET — each distribution's current release,
// found where it says it is as the sheet opens (forge.py catalog: never a
// version written into the shell), downloaded into Downloads with its
// checksums and signature beside it, and chosen in the write sheet when it
// is in. The download is the manager's: Hide puts the sheet away and it
// goes on; Stop keeps what came, and the next try picks up from there.
//
//     Sheet { cardH: body.implicitHeight
//       StylusDownload { id: body; width: parent.width; win: sw } }

import QtQuick
import "../morpheus"
import "../terminus"
import "../terminus/terminus.js" as Terminus
import "stylus.js" as S

FocusScope {
  id: body

  property var win: null
  readonly property var mgr: body.win ? body.win.mgr : null
  readonly property var job: body.mgr ? body.mgr.downloadJob : null
  readonly property string face: !body.job ? "choosing" : body.job.result ? "done" : "running"

  property var list: []
  property bool loading: false
  property int sel: 0
  readonly property var entry: body.list[body.sel] || null

  function reset() {
    body.loading = true;
    body.mgr.ask(["catalog"], (j) => {
      body.loading = false;
      body.list = Array.isArray(j) ? j : [];
      body.sel = Math.min(body.sel, Math.max(0, body.list.length - 1));
    });
  }
  function go() {
    if (body.face === "done") { body.mgr.clearDownload(); body.win.closeDownload(); return; }
    if (body.face === "choosing" && body.entry) body.mgr.download(body.entry);
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
        textFormat: Text.PlainText
        text: body.face === "choosing" ? "Download a Linux" : body.job.entry.name + " " + body.job.entry.version
        color: Zenon.ink
        font.family: Zenon.face
        font.weight: Zenon.titleWeight
        font.pixelSize: Zenon.px(17)
      }
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: "Into Downloads, its checksums and signature beside it — then it is the image to write"
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
      }
    }

    // ── what there is ──────────────────────────────────────────────────
    Item {
      visible: body.face === "choosing"
      width: parent.width
      height: Math.max(rows.implicitHeight, 34)
      Column {
        id: rows
        width: parent.width
        Repeater {
          id: rep
          model: body.list
          Item {
            required property var modelData
            required property int index
            width: rows.width
            height: 34
            Text {
              textFormat: Text.PlainText
              x: 10
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.name
              color: Zenon.ink
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(14)
            }
            Text {
              textFormat: Text.PlainText
              anchors.right: parent.right
              anchors.rightMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              text: [modelData.version, modelData.size ? Terminus.formatSize(modelData.size) : "",
                     modelData.sig ? "signed" : ""].filter((x) => x).join("  ·  ")
              color: Zenon.accentMuted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(12)
            }
            TapHandler { onTapped: body.sel = index }
          }
        }
      }
      CursorBand { repeater: rep; index: body.sel; shown: body.list.length > 0 }
      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        visible: body.list.length === 0
        text: body.loading ? "Finding the current releases…" : "None of them could be reached — is the network up?"
        color: Zenon.muted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
      }
    }

    // ── the download, and how it went ──────────────────────────────────
    Column {
      visible: body.face !== "choosing"
      width: parent.width
      spacing: 8
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
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.Wrap
        text: !body.job ? "" : !body.job.result ? S.progressLine(body.job)
          : body.job.result.ok ? "Downloaded" : body.job.result.why
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
        onClicked: body.win.closeDownload()
      }
      DialogButton {
        visible: body.face === "running"
        label: "Stop"
        ink: Zenon.red
        onClicked: body.mgr.stopDownload()
      }
      DialogButton {
        visible: body.face !== "running"
        label: body.face === "done" ? "Done" : "Download"
        primary: true
        ink: Zenon.cyan
        ready: body.face === "done" || !!body.entry
        onClicked: body.go()
      }
    }
  }

  Keys.onEscapePressed: body.win.closeDownload()
  Keys.onReturnPressed: body.go()
  Keys.onUpPressed: body.sel = Math.max(0, body.sel - 1)
  Keys.onDownPressed: body.sel = Math.min(body.list.length - 1, body.sel + 1)
}

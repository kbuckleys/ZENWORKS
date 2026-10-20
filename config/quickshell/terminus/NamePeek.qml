// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A NAME CUT SHORT, SHOWN WHOLE — the pointer resting on a row whose name
// its column elided: after a moment, a Bubble hanging from the row with the
// whole name and what the row would say if it had room (size, kind, when).
// Terminus' window and morpheus' FileTree (plato's narrow tree, where names
// are cut most) each place one; EntryRow tells its host when it is rested
// on with its name cut (host.peekName(row, entry), null when it is left).
//
//     NamePeek { id: namePeek; window: win }
//     function peekName(row, entry) { namePeek.show(row, entry); }

import QtQuick
import "../morpheus"
import "terminus.js" as Terminus

Item {
  id: np
  property var window: null
  property Item row: null
  property var entry: null
  property bool ready: false

  function show(row, entry) {
    np.ready = false;
    np.row = row;
    np.entry = entry;
    if (row) wait.restart(); else wait.stop();
  }
  Timer { id: wait; interval: Zenon.hoverWait; onTriggered: np.ready = !!np.row }

  Bubble {
    window: np.window
    target: np.row
    shown: np.ready && !!np.entry
    cardWidth: 400
    Text {
      width: 372
      wrapMode: Text.WrapAnywhere
      text: np.entry ? np.entry.name : ""
      color: Zenon.ink
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(15)
    }
    Text {
      width: 372
      elide: Text.ElideRight
      text: !np.entry ? ""
        : (np.entry.isDir ? "directory" : Terminus.formatSize(np.entry.size) + "  ·  " + Terminus.kindOf(np.entry.name))
          + (np.entry.mtime ? "  ·  " + Terminus.formatTime(np.entry.mtime) : "")
          + (np.entry.isLink ? "  ·  a link" : "")
      color: Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
    }
  }
}

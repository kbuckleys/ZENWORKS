// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A NOTE'S TABLE — a grid of cells, each a little rich-text field of its
// own. Tab walks the cells (and adds a row past the last), shift+tab walks
// back, ↑ ↓ at a cell's edge move between rows, Esc leaves the table. Rows
// and columns are added and taken away from the right-click menu.

import QtQuick
import "../morpheus"
import "notes.js" as N

Item {
  id: tbl
  property var editor: null
  property var block: null

  readonly property var rows: { void (tbl.editor ? tbl.editor.rev : 0); return tbl.block && tbl.block.b ? tbl.block.b.rows || [[""]] : [[""]]; }
  readonly property int nRows: tbl.rows.length
  readonly property int nCols: tbl.rows.length > 0 ? tbl.rows[0].length : 1
  readonly property real cellW: Math.floor(tbl.width / Math.max(1, tbl.nCols))

  height: grid.height

  // the cell the caret was last in, so a menu or a sheet that took the
  // focus away hands it back there rather than to the note list
  property int lastR: 0
  property int lastC: 0
  readonly property bool hasFocus: {
    for (let f = tbl.Window.activeFocusItem; f; f = f.parent) if (f === tbl) return true;
    return false;
  }
  function refocus() { tbl.focusCell(Math.min(tbl.lastR, tbl.nRows - 1), Math.min(tbl.lastC, tbl.nCols - 1)); }

  // where a press lands: a cell, and the place in it
  function control(x, y) {
    for (let r = 0; r < rowRep.count; r++) {
      const row = rowRep.itemAt(r);
      if (!row || y < row.y || y > row.y + row.height) continue;
      const c = Math.max(0, Math.min(tbl.nCols - 1, Math.floor(x / tbl.cellW)));
      const cell = row.cellAt(c);
      if (!cell) return null;
      const p = cell.mapFromItem(tbl, x, y);
      return { act: "cell", r: r, c: c, pos: cell.te.positionAt(p.x - cell.te.x, p.y - cell.te.y) };
    }
    return null;
  }
  function cell(r, c) {
    const row = rowRep.itemAt(r);
    return row ? row.cellAt(c) : null;
  }
  function focusCell(r, c, pos) {
    const cl = tbl.cell(r, c);
    if (!cl) return;
    cl.te.forceActiveFocus();
    cl.te.cursorPosition = pos === undefined ? cl.te.length : Math.max(0, Math.min(cl.te.length, pos));
  }

  Rectangle {
    anchors.fill: grid
    color: "transparent"
    radius: Zenon.windowRadius
    border.width: 1
    border.color: Zenon.border
  }
  Column {
    id: grid
    width: tbl.width
    Repeater {
      id: rowRep
      model: tbl.nRows
      delegate: Item {
        id: rowItem
        required property int index
        readonly property int r: index
        width: grid.width
        height: Math.max(36, cellRow.childrenRect.height)
        function cellAt(c) { return cellRep.itemAt(c); }
        // the head row, shaded as Apple's
        Rectangle {
          anchors.fill: parent
          visible: rowItem.r === 0
          color: Zenon.wash(0.05)
          radius: Zenon.windowRadius
        }
        Rectangle { visible: rowItem.r > 0; width: parent.width; height: 1; color: Zenon.border }
        Row {
          id: cellRow
          Repeater {
            id: cellRep
            model: tbl.nCols
            delegate: Item {
              id: cellItem
              required property int index
              readonly property int c: index
              property alias te: cellText
              width: tbl.cellW
              height: Math.max(36, cellText.height + 16)
              Rectangle { visible: cellItem.c > 0; width: 1; height: rowItem.height; color: Zenon.border }
              property string shown: ""
              property bool syncing: false
              function load() {
                const want = (tbl.rows[rowItem.r] || [])[cellItem.c] || "";
                if (want === cellItem.shown && cellItem.loaded) return;
                cellItem.syncing = true;
                cellText.text = tbl.editor ? tbl.editor.display(want) : want;
                cellItem.syncing = false;
                cellItem.shown = want;
                cellItem.loaded = true;
              }
              property bool loaded: false
              Connections { target: tbl; function onRowsChanged() { Qt.callLater(cellItem.load); } }
              Component.onCompleted: cellItem.load()
              TextEdit {
                id: cellText
                x: 10
                y: 8
                width: parent.width - 20
                textFormat: TextEdit.RichText
                wrapMode: TextEdit.Wrap
                readOnly: !tbl.editor || tbl.editor.readOnly
                selectByMouse: false
                activeFocusOnPress: false
                persistentSelection: false
                color: Zenon.ink
                selectionColor: Zenon.alpha(Zenon.cyan, 0.32)
                selectedTextColor: color
                font.family: tbl.editor ? tbl.editor.face : Zenon.face
                font.weight: rowItem.r === 0 ? Font.DemiBold : Zenon.weight
                font.pixelSize: tbl.editor ? Math.round(tbl.editor.textSize * 0.94) : 15
                cursorDelegate: Caret { field: cellText; thick: 3; low: 0.45; steady: true }
                onTextChanged: {
                  if (cellItem.syncing || !tbl.editor) return;
                  const h = tbl.editor.keep(N.inline(cellText.text));
                  cellItem.shown = h;
                  tbl.editor.cellTyped(tbl.block.key, rowItem.r, cellItem.c, h);
                }
                onActiveFocusChanged: {
                  if (!activeFocus) return;
                  tbl.lastR = rowItem.r;
                  tbl.lastC = cellItem.c;
                  if (tbl.editor) tbl.editor.focused(tbl.block.key);
                }
                Keys.onPressed: (e) => {
                  if (!tbl.editor) return;
                  if (tbl.editor.cellKey(tbl.block.key, tbl, rowItem.r, cellItem.c, cellText, e)) e.accepted = true;
                }
              }
            }
          }
        }
      }
    }
  }
}

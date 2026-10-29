// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// CALYPSO'S QUICK ACCESS — the bar's popup, out of the pill: find a login
// among every open account and type it where the cursor was, or put it on
// the clipboard. 1Password's Quick Access, in the shell's own layer.
//
//   list      everything open, what you used last first; typing filters
//   actions   one item: type username ⇥ password, or one of them, or the
//             code; or copy one (cleared in 30 s, kept out of cliphist)
//   unlock    nothing open yet: the suite's password field, for the account
//             chosen on its switch
//   empty     no account at all: the window is where one is added
//
// The vaults are the manager's (CalypsoManager): an account opened here is
// open in the window and the other way round. Secrets never come here — the
// daemon types and copies them itself.

import QtQuick
import Quickshell.Hyprland
import "../morpheus"
import "../terminus"
import "../ceres"
import "calypso.js" as C

LayerPopup {
  id: popup

  // handed in by shell.qml
  property var mgr: null

  readonly property color bgColor: Zenon.layerBg
  readonly property color keyColor: Zenon.accentKey
  readonly property color dimColor: Zenon.accentMuted
  readonly property color entryColor: Zenon.pink

  // list · actions · unlock · empty · error
  property string mode: "list"
  property string query: ""
  property int sel: 0
  property var activeEntry: null
  property int actionSel: 0
  property string errorMsg: ""
  property string lockTarget: ""
  property bool unlocking: false
  property string failMsg: ""

  // col 0 is typed where the cursor is, col 1 goes on the clipboard. Index
  // 0 is where the choice starts — "both" is what you want nine times in ten.
  //
  // A CARD IS NOT A LOGIN (user, 2026-10-14): its own four, typed or
  // copied — number, expiry, security code, cardholder. Kinds "t:<ref>" and
  // "c:<ref>" name the card's field (base.field refs, the same on every
  // platform).
  readonly property bool cardShown: !!popup.activeEntry && popup.activeEntry.kind === "card"
  readonly property var cardActions: [
    { kind: "t:number",     col: 0, glyph: "\u{F0FEF}", label: "number" },
    { kind: "t:expiry",     col: 0, glyph: "\u{F00ED}", label: "expiry date" },
    { kind: "t:code",       col: 0, glyph: "\u{F0306}", label: "security code" },
    { kind: "t:cardholder", col: 0, glyph: "\u{F0004}", label: "cardholder" },
    { kind: "c:number",     col: 1, glyph: "\u{F0FEF}", label: "number" },
    { kind: "c:expiry",     col: 1, glyph: "\u{F00ED}", label: "expiry date" },
    { kind: "c:code",       col: 1, glyph: "\u{F0306}", label: "security code" },
    { kind: "c:cardholder", col: 1, glyph: "\u{F0004}", label: "cardholder" },
  ]
  readonly property var actionTypes: popup.cardShown ? popup.cardActions : popup.loginActions
  readonly property var loginActions: [
    { kind: "both",     col: 0, glyph: "", label: "user ⇥ pass" },
    { kind: "user",     col: 0, glyph: "", label: "username" },
    { kind: "pass",     col: 0, glyph: "", label: "password" },
    { kind: "totp",     col: 0, glyph: "\u{F097F}", label: "one-time code" },
    { kind: "copypass", col: 1, glyph: "", label: "password" },
    { kind: "copyuser", col: 1, glyph: "", label: "username" },
    { kind: "copytotp", col: 1, glyph: "\u{F097F}", label: "one-time code" },
  ]

  readonly property int msgH: Zenon.hintBarH   // morpheus/HintBar's strip
  readonly property int searchH: 36
  readonly property int emptyH: 64
  readonly property int lockH: 132
  readonly property int actHeadH: 64
  readonly property int actSectH: 28
  readonly property int cellH: 34
  readonly property int actBodyH: 6 + popup.actSectH + 4 * popup.cellH + 8
  readonly property int cols: 2
  readonly property int visibleRows: 8

  focusable: true

  HyprlandFocusGrab {
    windows: [ popup ]
    active: popup.shown
    onCleared: popup.closePopup()
  }

  // ── what is listed ─────────────────────────────────────────────────────
  // everything open; with nothing typed, what you used last comes first
  readonly property var filtered: {
    if (!popup.mgr) return [];
    const rows = C.shelve(popup.mgr.items, null, popup.query, popup.mgr.favs, "name");
    if (popup.query !== "") return rows;
    const rank = {};
    popup.mgr.recent.forEach((k, i) => rank[k] = i);
    return rows.slice().sort((a, b) => {
      const ra = rank[C.keyOf(a)], rb = rank[C.keyOf(b)];
      if (ra !== undefined || rb !== undefined) return (ra === undefined ? 1e9 : ra) - (rb === undefined ? 1e9 : rb);
      return 0;
    });
  }
  readonly property var lockedAccts: popup.mgr ? popup.mgr.accounts.filter((a) => popup.mgr.isLocked(a)) : []
  readonly property var lockAcct: popup.lockedAccts.find((a) => a.id === popup.lockTarget) || popup.lockedAccts[0] || null
  readonly property bool lockAsks: {
    const info = popup.mgr && popup.lockAcct ? popup.mgr.platformInfo(popup.lockAcct.kind) : null;
    return !info || info.asks !== "";
  }

  // the list as the grid lays it: down each column first (1 3 / 2 4)
  readonly property int effCols: popup.filtered.length >= 1 && popup.filtered.length <= popup.visibleRows ? 1 : popup.cols
  readonly property int gridRows: Math.max(1, Math.ceil(popup.filtered.length / popup.effCols))
  readonly property var displayOrder: {
    const len = popup.filtered.length, c = popup.effCols, r = popup.gridRows, order = [];
    for (let row = 0; row < r; ++row)
      for (let col = 0; col < c; ++col) {
        const i = col * r + row;
        order.push(i < len ? i : -1);
      }
    return order;
  }
  // The grid's model, kept in place: a view handed a new array starts again
  // from its top, and the array was new on every refresh of an account
  // (the window's list jumped mid-scroll for it, 2026-10-12).
  ListModel { id: cellModel }
  onDisplayOrderChanged: {
    const d = popup.displayOrder;
    let same = cellModel.count === d.length;
    for (let i = 0; same && i < d.length; i++) same = cellModel.get(i).at === d[i];
    if (same) return;
    cellModel.clear();
    for (const i of d) cellModel.append({ at: i });
  }
  function cellOf(i) { return (i % popup.gridRows) * popup.effCols + Math.floor(i / popup.gridRows); }
  onFilteredChanged: {
    if (popup.sel >= popup.filtered.length) popup.sel = Math.max(0, popup.filtered.length - 1);
    Qt.callLater(() => list.positionViewAtIndex(popup.cellOf(popup.sel), GridView.Contain));
  }

  // ── open, close ────────────────────────────────────────────────────────
  function openPopup() {
    popup.shown = true;
    popup.collapsing = false;
    popup.query = "";
    filterInput.text = "";
    popup.sel = 0;
    popup.failMsg = "";
    popup.activeEntry = null;
    // never back on the actions card it closed from (a copy closes it
    // there): with the entry gone it came up as bare placeholders
    // (user, 2026-10-12); settleMode picks unlock or empty over this
    popup.mode = "list";
    if (popup.mgr) {
      popup.mgr.hold("quick");
      popup.mgr.loadPlatforms();
      popup.mgr.refreshAll();
    }
    popup.settleMode();
    focusRetry.begin();
    popup.playOpen();
    popup.syncFocus();
  }
  function closePopup() {
    actFlash.cancel();
    popup.collapsing = true;
    popup.playClose();
    if (popup.mgr) popup.mgr.release("quick");
  }
  function toggle() { if (popup.shown) popup.closePopup(); else popup.openPopup(); }
  function settleMode() {
    if (!popup.mgr || popup.mgr.accounts.length === 0) popup.mode = "empty";
    // not answered for yet: the list's "reading the vaults…", not the lock
    else if (!popup.mgr.anyOpen && !popup.mgr.checking) popup.mode = "unlock";
    else if (popup.mode !== "actions" && popup.mode !== "error") popup.mode = "list";
    popup.syncFocus();
  }
  Connections {
    target: popup.mgr
    function onAnyOpenChanged() { if (popup.shown && popup.mode !== "actions") popup.settleMode(); }
    function onCheckingChanged() { if (popup.shown && popup.mode !== "actions") popup.settleMode(); }
  }
  // the shell's screen lock: every account, and the daemon stopped
  function lockVault() {
    if (popup.shown) popup.closePopup();
    if (popup.mgr) popup.mgr.lockAll();
  }
  function syncFocus() {
    Qt.callLater(() => {
      if (!popup.shown) return;
      if (popup.mode === "list") filterInput.forceActiveFocus();
      else bgRoot.forceActiveFocus();
    });
  }

  // ── doing it ───────────────────────────────────────────────────────────
  function currentEntry() { return popup.filtered[popup.sel] || null; }
  function openActions() {
    const e = popup.currentEntry();
    if (!e) return;
    popup.activeEntry = e;
    popup.actionSel = popup.firstAction();
    popup.mode = "actions";
    popup.syncFocus();
  }
  function actionOk(i) {
    const a = popup.actionTypes[i];
    return !!a && C.actionEnabled(a.kind, popup.activeEntry);
  }
  function firstAction() {
    for (let i = 0; i < popup.actionTypes.length; ++i) if (popup.actionOk(i)) return i;
    return -1;
  }
  function actionsIn(col) {
    const out = [];
    for (let i = 0; i < popup.actionTypes.length; ++i) if (popup.actionTypes[i].col === col) out.push(i);
    return out;
  }
  function moveAction(dCol, dRow) {
    const cur = popup.actionTypes[popup.actionSel];
    if (!cur) return;
    const list = popup.actionsIn(cur.col);
    const row = list.indexOf(popup.actionSel);
    if (dCol !== 0) {
      const other = popup.actionsIn((cur.col + dCol + 2) % 2).filter((i) => popup.actionOk(i));
      if (other.length === 0) return;
      let best = other[0], dist = 1e9;
      for (const i of other) {
        const d = Math.abs(popup.actionsIn(popup.actionTypes[i].col).indexOf(i) - row);
        if (d < dist) { dist = d; best = i; }
      }
      popup.actionSel = best;
      return;
    }
    for (let step = 1; step <= list.length; ++step) {
      const i = list[((row + dRow * step) % list.length + list.length) % list.length];
      if (popup.actionOk(i)) { popup.actionSel = i; return; }
    }
  }
  // Typed: the popup goes first, so the keyboard is back with the window the
  // text is for before the daemon types (it waits a moment itself).
  // the action's row flashes, then it types or copies (morpheus/RowFlash,
  // user 2026-10-21); the row is keyed by its action's number
  property Item pickedAct: null
  RowFlash { id: actFlash }
  function executeSel() {
    const i = popup.actionSel, kind = popup.actionTypes[i].kind;
    actFlash.flashThen(i, () => popup.execute(kind), () => popup.actionSel);
  }
  function execute(kind) {
    const e = popup.activeEntry;
    if (!e || !popup.mgr) return;
    const acct = popup.mgr.accountOf(e.acct);
    const field = kind.slice(0, 2) === "t:" || kind.slice(0, 2) === "c:" ? kind.slice(2) : "";
    const parts = kind.slice(0, 2) === "t:" ? [field]
      : { both: ["username", "\t", "password"], user: ["username"], pass: ["password"], totp: ["totp"] }[kind];
    popup.mgr.used(e);
    if (parts) {
      popup.closePopup();
      popup.mgr.call("type", acct, { item: e.id, parts: parts, delay: 0.35 }, (ok, r, err) => {
        if (ok) return;
        // only a package missing (wtype): the window, on its install card
        if (err && err.kind === "needs") popup.mgr.withWindow((w) => { w.wake(); w.failed(err, null); });
        else popup.mgr.tell(C.failWords(err), true);
      });
      return;
    }
    const ref = field || { copypass: "password", copyuser: "username", copytotp: "totp" }[kind];
    popup.mgr.call("copy", acct, { item: e.id, ref: ref, totp: ref === "totp", clear: popup.mgr.clearAfter }, (ok, r, err) => {
      if (!ok && err && err.kind === "needs") { popup.closePopup(); popup.mgr.withWindow((w) => { w.wake(); w.failed(err, null); }); return; }
      if (!ok) { popup.errorMsg = C.failWords(err); popup.mode = "error"; popup.syncFocus(); return; }
      popup.closePopup();
    });
  }
  function submitUnlock(secret) {
    if (!popup.lockAcct || popup.unlocking) return;
    popup.unlocking = true;
    popup.failMsg = "";
    popup.mgr.unlock(popup.lockAcct, secret, (ok, err) => {
      popup.unlocking = false;
      if (ok) { popup.mode = "list"; popup.syncFocus(); return; }
      if (err && err.kind === "auth") { field.failed = true; popup.failMsg = C.authNote(err); }
      else popup.failMsg = C.failWords(err);
    });
  }
  function openWindow(it) {
    popup.closePopup();
    if (!popup.mgr) return;
    if (it) popup.mgr.show(it); else popup.mgr.open();
  }

  // ── the hints ──────────────────────────────────────────────────────────
  function hints() {
    if (popup.mode === "actions") return [["arrows", "choose"], ["return", "run"], ["alt o", "in calypso"], ["backspace", "back"]];
    if (popup.mode === "unlock")
      return (popup.lockAsks ? [["return", "unlock"]] : [["return", "open"]])
        .concat(popup.lockedAccts.length > 1 ? [["tab", "account"]] : []).concat([["esc", "close"]]);
    if (popup.mode === "empty") return [["return", "open calypso"], ["esc", "close"]];
    if (popup.mode === "error") return [["return", "back"]];
    return [["type", "filter"], ["return", "actions"], ["alt o", "calypso"], ["alt g", "generator"], ["alt l", "lock"]]
      .concat(popup.lockedAccts.length > 0 ? [["alt u", "unlock more"]] : []);
  }

  // ── AS WIDE AS ITS WIDEST ENTRY ────────────────────────────────────────
  // the widest row as drawn, times the columns showing, the hint strip as
  // the floor and the 1000 every layer shares as the ceiling
  FontMetrics { id: rowFm; font.family: Zenon.face; font.weight: 600; font.pixelSize: Zenon.px(16) }
  FontMetrics { id: userFm; font.family: Zenon.face; font.pixelSize: Zenon.px(14) }
  FontMetrics { id: headFm; font.family: Zenon.face; font.weight: 700; font.pixelSize: Zenon.px(17) }
  FontMetrics { id: noteFm; font.family: Zenon.face; font.pixelSize: Zenon.px(12) }
  function rowTextW(e) {
    if (!e) return 0;
    return 16 + 26 + 10 + 16 + rowFm.advanceWidth(String(e.title || ""))
      + (e.totp === true ? 22 : 0) + (e.sub ? 24 + userFm.advanceWidth(e.sub) : 0);
  }
  HintRow { id: hintMeasure; opacity: 0; rows: popup.hints() }
  readonly property int noteW: popup.mode === "list" ? Math.ceil(noteFm.advanceWidth("000 items")) + 16 : 0
  readonly property int minW: Math.max(380, Math.ceil(hintMeasure.implicitWidth + 48 + 2 * popup.noteW))
  readonly property int panelWidth: {
    if (popup.mode === "actions" && popup.activeEntry)
      return Math.max(popup.minW, 480, Math.min(1000, Math.ceil(headFm.advanceWidth(popup.activeEntry.title) + 140)));
    if (popup.mode !== "list") return Math.max(popup.minW, 460);
    let most = 0;
    for (const e of popup.filtered.slice(0, 400)) most = Math.max(most, popup.rowTextW(e));
    return Math.max(popup.minW, Math.min(1000, (Math.ceil(most) + 8) * popup.effCols));
  }
  readonly property int panelTarget: Zenon.layerWidth(popup.panelWidth)
  property real liveWidth: (popup.morphMode && popup.statusbar && popup.statusbar.pillWidth > 0)
    ? popup.statusbar.pillWidth : popup.panelTarget
  Behavior on liveWidth {
    enabled: !popup.morphMode
    NumberAnimation { duration: Zenon.slow; easing.type: Zenon.ease }
  }
  function listHeight() {
    if (popup.filtered.length === 0) return 0;
    return Math.max(1, Math.min(popup.gridRows, popup.visibleRows)) * popup.cellH;
  }
  function calcHeight() {
    if (popup.mode === "list")
      return (popup.query.length > 0 ? popup.searchH : 0)
        + (popup.filtered.length === 0 ? popup.emptyH : popup.listHeight()) + popup.msgH;
    if (popup.mode === "actions") return popup.actHeadH + popup.actBodyH + popup.msgH;
    if (popup.mode === "unlock") return popup.lockH + (popup.lockedAccts.length > 1 ? 40 : 0) + popup.msgH;
    return popup.emptyH + popup.msgH;
  }

  // The strip every view ends on: artemis' and folio's, with the keys as caps.


  // ── the panel ──────────────────────────────────────────────────────────
  MouseArea { anchors.fill: parent; z: 0; onClicked: popup.closePopup() }

  LayerPanel {
    id: panel
    host: popup
    ground: bgRoot
    width: Math.round(popup.liveWidth)
    height: popup.calcHeight()

    // a rounded clip (Qt's own clip is the bounding box): the strips painted
    // to the panel's edge would fill the corners in

    PanelGround {
      id: bgRoot
      color: popup.bgColor

      // ── list ──────────────────────────────────────────────────────────
      Item {
        id: listView
        anchors.fill: parent
        visible: opacity > 0.01
        opacity: popup.mode === "list" ? 1 : 0
        x: popup.mode === "list" ? 0 : -24
        Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
        Behavior on x { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }

        ScrollEdge { view: list; x: list.x; width: list.width; height: list.y }
        ScrollEdge { view: list; below: true; x: list.x; y: list.y + list.height; width: list.width; height: listHints.height }
        // the suite's one scrollbar, as folio's grids wear it; placed by
        // the grid's own place in the column (the column fills this item)
        Scrollbar {
          flick: list
          z: 2
          x: list.x + list.width - width
          y: list.y
          height: list.height
        }

        Column {
          anchors.fill: parent

          // the filter: a line that only exists once something is typed
          Item {
            id: inputBar
            width: parent.width
            height: popup.query.length > 0 ? popup.searchH : 0
            Behavior on height { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
            clip: true
            Row {
              anchors.left: parent.left
              anchors.leftMargin: 16
              anchors.right: queryClear.left
              anchors.rightMargin: 8
              height: parent.height
              visible: inputBar.height > 2
              Text {
                width: 36
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                text: ""
                color: popup.entryColor
                font.family: Zenon.glyphFace
                font.pixelSize: Zenon.px(15)
              }
              TextInput {
                id: filterInput
                width: parent.width - 36
                height: parent.height
                verticalAlignment: TextInput.AlignVCenter
                color: popup.entryColor
                selectionColor: popup.entryColor
                selectedTextColor: Zenon.onAccent
                font.family: Zenon.face
                font.weight: Font.Bold
                font.pixelSize: Zenon.px(18)
                cursorDelegate: Caret { field: filterInput }
                clip: true
                Keys.forwardTo: bgRoot
                onTextChanged: { popup.query = filterInput.text; popup.sel = 0; }
              }
            }
            // a click on the × empties the filter, as esc does (Picasso's)
            ClearChip {
              id: queryClear
              anchors.right: parent.right
              anchors.rightMargin: 14
              anchors.verticalCenter: parent.verticalCenter
              size: Zenon.px(15)
              visible: inputBar.height > 2
              onClicked: filterInput.text = ""
            }
          }

          Item {
            width: parent.width
            height: popup.filtered.length === 0 ? popup.emptyH : 0
            Text {
              anchors.centerIn: parent
              visible: popup.filtered.length === 0
              text: popup.query === "" ? (popup.mgr && popup.mgr.loading ? "Reading the vaults…" : "Nothing in the open vaults") : "Nothing matches \u201C" + popup.query + "\u201D"
              color: popup.dimColor
              font.family: Zenon.face
              font.weight: 600
              font.pixelSize: Zenon.px(15)
            }
          }

          GridView {
            id: list
            ElasticScroll { view: list }
            width: parent.width
            height: popup.listHeight()
            clip: true
            flow: GridView.FlowLeftToRight
            cellWidth: width / popup.effCols
            cellHeight: popup.cellH
            model: cellModel
            // the chosen one slides (morpheus/CursorBand), rather than each
            // cell lighting itself (user, 2026-10-21); cellOf: the grid runs
            // down its columns
            CursorBand { follows: list; index: popup.filtered.length > 0 ? popup.cellOf(popup.sel) : -1 }
            delegate: Item {
              id: cell
              required property int at
              readonly property var entry: at >= 0 ? popup.filtered[at] || null : null
              readonly property bool picked: at >= 0 && at === popup.sel
              width: list.cellWidth
              height: list.cellHeight
              ItemTile {
                id: rowTile
                x: 16
                anchors.verticalCenter: parent.verticalCenter
                visible: !!cell.entry
                item: cell.entry
                size: 24
                lit: cell.picked
              }
              Text {
                id: rowName
                anchors.left: rowTile.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, cell.width - x - 16 - (rowUser.visible ? 60 : 0))
                text: !cell.entry ? "" : C.highlight(cell.entry.title, popup.query, Zenon.pink)
                  + (cell.entry.totp === true ? "&nbsp;&nbsp;<span style=\"color:" + Zenon.cyan + ";font-size:12px;\">\u{F097F}</span>" : "")
                color: cell.picked ? popup.entryColor : Zenon.ink
                textFormat: Text.RichText
                clip: true
                font.family: Zenon.face
                font.weight: 600
                font.pixelSize: Zenon.px(16)
              }
              Text {
                id: rowUser
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.left: rowName.right
                anchors.leftMargin: 24
                anchors.verticalCenter: parent.verticalCenter
                visible: !!cell.entry && cell.entry.sub !== ""
                horizontalAlignment: Text.AlignRight
                text: cell.entry ? cell.entry.sub : ""
                color: popup.dimColor
                elide: Text.ElideLeft
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(14)
              }
              MouseArea {
                anchors.fill: parent
                enabled: !!cell.entry
                onClicked: { popup.sel = cell.at; popup.openActions(); }
              }
            }
          }

          HintBar {
            id: listHints
            width: parent.width
            rows: popup.hints()
            // how many, at the right end, where ceres stands its buttons
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: popup.filtered.length + (popup.filtered.length === 1 ? " item" : " items")
              color: popup.dimColor
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(13)
            }
          }
        }
      }

      // ── actions ───────────────────────────────────────────────────────
      Item {
        id: actionsView
        anchors.fill: parent
        visible: opacity > 0.01
        opacity: popup.mode === "actions" ? 1 : 0
        x: popup.mode === "actions" ? 0 : 24
        Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
        Behavior on x { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }

        // the sliding cursor over both columns of actions (morpheus/
        // CursorBand following the chosen row itself: two Repeaters)
        CursorBand { item: popup.mode === "actions" ? popup.pickedAct : null }
        Column {
          anchors.fill: parent
          // the item, as its row was, larger
          Item {
            width: parent.width
            height: popup.actHeadH
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Zenon.border }
            ItemTile {
              id: actTile
              x: 16
              anchors.verticalCenter: parent.verticalCenter
              item: popup.activeEntry
              size: 40
              lit: true
            }
            Column {
              anchors.left: actTile.right
              anchors.leftMargin: 12
              anchors.right: parent.right
              anchors.rightMargin: 16
              anchors.verticalCenter: parent.verticalCenter
              spacing: 1
              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: popup.activeEntry ? popup.activeEntry.title : ""
                color: Zenon.ink
                elide: Text.ElideMiddle
                font.family: Zenon.face
                font.weight: 700
                font.pixelSize: Zenon.px(17)
              }
              Text {
                width: parent.width
                text: !popup.activeEntry || !popup.mgr ? "" : [popup.activeEntry.sub,
                  (popup.mgr.accountOf(popup.activeEntry.acct) || {}).name].filter((s) => !!s).join("  ·  ")
                color: popup.dimColor
                elide: Text.ElideMiddle
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(13)
              }
            }
          }
          // what is typed, and what is copied
          Row {
            id: actionGrid
            width: parent.width
            height: popup.actBodyH
            Repeater {
              model: [{ title: "type", glyph: "" }, { title: "copy", glyph: "\u{F018F}" }]
              delegate: Item {
                id: group
                required property var modelData
                required property int index
                width: actionGrid.width / 2
                height: actionGrid.height
                Rectangle {
                  visible: group.index === 1
                  anchors.top: parent.top
                  anchors.topMargin: 10
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: 10
                  width: 1
                  color: Zenon.border
                }
                Column {
                  anchors.fill: parent
                  topPadding: 6
                  Item {
                    width: parent.width
                    height: popup.actSectH
                    Row {
                      x: 16
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: 8
                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: group.modelData.glyph
                        color: Zenon.cyan
                        font.family: Zenon.glyphFace
                        font.pixelSize: Zenon.px(13)
                      }
                      Text {
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        text: group.modelData.title
                        color: Zenon.cyan
                        font.family: Zenon.face
                        font.weight: Zenon.titleWeight
                        font.pixelSize: Zenon.px(13)
                        font.letterSpacing: Zenon.labelSpacing
                      }
                    }
                  }
                  Repeater {
                    model: popup.actionsIn(group.index)
                    delegate: Item {
                      id: act
                      required property var modelData
                      readonly property var action: popup.actionTypes[modelData]
                      readonly property bool ok: popup.actionOk(modelData)
                      readonly property bool picked: ok && popup.actionSel === modelData
                      readonly property bool isTotp: action.kind === "totp" || action.kind === "copytotp"
                      width: group.width
                      height: popup.cellH
                      opacity: ok ? 1 : Zenon.disabledDim
                      // the cursor is actionsView's CursorBand, told which row
                      onPickedChanged: if (act.picked) popup.pickedAct = act
                      Component.onCompleted: if (act.picked) popup.pickedAct = act
                      Component.onDestruction: if (popup.pickedAct === act) popup.pickedAct = null
                      FlashOver { flash: actFlash; index: act.modelData }
                      Text {
                        id: actIcon
                        x: 16
                        anchors.verticalCenter: parent.verticalCenter
                        width: 26
                        horizontalAlignment: Text.AlignHCenter
                        text: act.action.glyph
                        color: act.picked ? popup.entryColor : popup.dimColor
                        font.family: Zenon.glyphFace
                        font.pixelSize: Zenon.px(18)
                      }
                      // a code with seconds to live expires on its way:
                      // the ring goes red for the last five
                      TotpRing {
                        id: ring
                        visible: act.isTotp && act.ok && !!popup.activeEntry && popup.activeEntry.totp === true
                        running: visible && popup.shown
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                      }
                      Text {
                        textFormat: Text.PlainText
                        anchors.left: actIcon.right
                        anchors.leftMargin: 10
                        anchors.right: ring.visible ? ring.left : parent.right
                        anchors.rightMargin: ring.visible ? 8 : 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: act.action.label
                        color: act.picked ? popup.entryColor : Zenon.ink
                        elide: Text.ElideRight
                        font.family: Zenon.face
                        font.weight: act.picked ? 600 : 400
                        font.pixelSize: Zenon.px(15)
                      }
                      MouseArea {
                        anchors.fill: parent
                        enabled: act.ok
                        onClicked: { popup.actionSel = act.modelData; popup.executeSel(); }
                      }
                    }
                  }
                }
              }
            }
          }
          HintBar { width: parent.width; rows: popup.hints() }
        }
      }

      // ── unlock ────────────────────────────────────────────────────────
      Item {
        id: unlockView
        anchors.fill: parent
        visible: opacity > 0.01
        opacity: popup.mode === "unlock" ? 1 : 0
        x: popup.mode === "unlock" ? 0 : 24
        Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
        Behavior on x { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }

        Column {
          anchors.fill: parent
          Item {
            width: parent.width
            height: popup.lockH + (popup.lockedAccts.length > 1 ? 40 : 0)
            Column {
              anchors.centerIn: parent
              width: parent.width - 32
              spacing: 8
              // which account the field is for
              Segments {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: popup.lockedAccts.length > 1
                options: popup.lockedAccts.map((a) => [a.id, a.name])
                current: popup.lockAcct ? popup.lockAcct.id : ""
                textSize: Zenon.px(12)
                onChose: (v) => popup.lockTarget = v
              }
              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10
                ItemTile {
                  anchors.verticalCenter: parent.verticalCenter
                  size: 28
                  glyph: popup.lockAcct ? C.platform(popup.lockAcct.kind).glyph : ""
                  ink: popup.lockAcct ? C.platform(popup.lockAcct.kind).ink : "cyan"
                }
                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  text: popup.lockAcct ? popup.lockAcct.name : ""
                  color: Zenon.ink
                  font.family: Zenon.face
                  font.weight: Font.Bold
                  font.pixelSize: Zenon.px(15)
                }
              }
              PasswordField {
                id: field
                width: parent.width
                visible: popup.lockAsks
                washRadius: Zenon.windowRadius
                busy: popup.unlocking
                prompt: C.unlockPrompt(popup.lockAcct && popup.mgr && popup.mgr.platformInfo(popup.lockAcct.kind)
                  ? popup.mgr.platformInfo(popup.lockAcct.kind).asks : "password")
                purpose: popup.failMsg !== "" ? popup.failMsg : popup.unlocking ? "unlocking…" : "unlocks " + (popup.lockAcct ? popup.lockAcct.name : "the vault")
                onSubmitted: (pw) => popup.submitUnlock(pw)
                onCancelled: popup.closePopup()
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !popup.lockAsks
                text: popup.unlocking ? "Opening…" : "return opens it"
                color: popup.dimColor
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(13)
              }
            }
          }
          HintBar { width: parent.width; rows: popup.hints() }
        }
      }

      // ── no account, or a failure ─────────────────────────────────────
      Item {
        anchors.fill: parent
        visible: opacity > 0.01
        opacity: popup.mode === "empty" || popup.mode === "error" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
        Column {
          anchors.fill: parent
          Item {
            width: parent.width
            height: popup.emptyH
            Row {
              anchors.centerIn: parent
              spacing: 10
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: popup.mode === "error" ? "" : ""
                color: popup.mode === "error" ? Zenon.red : Zenon.cyan
                font.family: Zenon.glyphFace
                font.pixelSize: Zenon.px(16)
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: popup.mode === "error" ? popup.errorMsg : "No accounts yet — add one in calypso"
                color: popup.mode === "error" ? Zenon.red : popup.dimColor
                font.family: Zenon.face
                font.weight: 600
                font.pixelSize: Zenon.px(15)
              }
            }
          }
          HintBar { width: parent.width; rows: popup.hints() }
        }
      }

      Keys.onReleased: (event) => { if (popup.mode === "unlock") field.keyUp(event); }
      Keys.onPressed: (event) => {
        const alt = event.modifiers & Qt.AltModifier;
        if (popup.mode === "empty") {
          event.accepted = true;
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) popup.openWindow(null);
          else if (event.key === Qt.Key_Escape) popup.closePopup();
          return;
        }
        if (popup.mode === "error") {
          event.accepted = true;
          if ([Qt.Key_Return, Qt.Key_Enter, Qt.Key_Escape, Qt.Key_Backspace].indexOf(event.key) >= 0) {
            popup.mode = popup.activeEntry ? "actions" : "list";
            popup.syncFocus();
          }
          return;
        }
        if (popup.mode === "unlock") {
          event.accepted = true;
          if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) && popup.lockedAccts.length > 1) {
            const ids = popup.lockedAccts.map((a) => a.id);
            const i = ids.indexOf(popup.lockAcct.id);
            popup.lockTarget = ids[(i + (event.key === Qt.Key_Tab ? 1 : ids.length - 1)) % ids.length];
            return;
          }
          if (event.key === Qt.Key_Escape && popup.mgr && popup.mgr.anyOpen && field.pw === "") { popup.mode = "list"; popup.syncFocus(); return; }
          if (!popup.lockAsks) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) popup.submitUnlock("");
            else if (event.key === Qt.Key_Escape) popup.closePopup();
            return;
          }
          field.key(event);
          return;
        }
        if (popup.mode === "actions") {
          event.accepted = true;
          if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) { popup.mode = "list"; popup.syncFocus(); return; }
          if (alt && event.key === Qt.Key_O) { popup.openWindow(popup.activeEntry); return; }
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (popup.actionOk(popup.actionSel)) popup.executeSel();
            return;
          }
          if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) { popup.moveAction(0, event.key === Qt.Key_Up ? -1 : 1); return; }
          if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) { popup.moveAction(event.key === Qt.Key_Left ? -1 : 1, 0); return; }
          if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            const n = popup.actionTypes.length;
            let i = popup.actionSel;
            for (let step = 0; step < n; ++step) {
              i = (i + (event.key === Qt.Key_Backtab ? n - 1 : 1)) % n;
              if (popup.actionOk(i)) { popup.actionSel = i; break; }
            }
          }
          return;
        }
        // the list
        if (event.key === Qt.Key_Escape) {
          event.accepted = true;
          if (filterInput.text !== "") filterInput.text = ""; else popup.closePopup();
          return;
        }
        if (alt && event.key === Qt.Key_L) { event.accepted = true; popup.closePopup(); popup.mgr.lockAll(); return; }
        if (alt && event.key === Qt.Key_O) { event.accepted = true; popup.openWindow(popup.currentEntry()); return; }
        if (alt && event.key === Qt.Key_G) {
          event.accepted = true;
          popup.closePopup();
          popup.mgr.withWindow((w) => { w.wake(); w.openGenerator(null); });
          return;
        }
        if (alt && event.key === Qt.Key_U && popup.lockedAccts.length > 0) { event.accepted = true; popup.mode = "unlock"; popup.syncFocus(); return; }
        if (alt && event.key === Qt.Key_S) {
          event.accepted = true;
          for (const a of popup.mgr.accounts) if ((popup.mgr.states[a.id] || {}).unlocked && a.kind !== "keepass") popup.mgr.sync(a);
          return;
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { event.accepted = true; popup.openActions(); return; }
        const len = popup.filtered.length;
        if (len === 0) return;
        const step = (d) => { popup.sel = ((popup.sel + d) % len + len) % len; Qt.callLater(() => list.positionViewAtIndex(popup.cellOf(popup.sel), GridView.Contain)); };
        if (event.key === Qt.Key_Down) { event.accepted = true; step(1); }
        else if (event.key === Qt.Key_Up) { event.accepted = true; step(-1); }
        else if (event.key === Qt.Key_PageDown) { event.accepted = true; step(popup.visibleRows); }
        else if (event.key === Qt.Key_PageUp) { event.accepted = true; step(-popup.visibleRows); }
        else if ((event.key === Qt.Key_Left || event.key === Qt.Key_Right) && popup.effCols > 1) {
          event.accepted = true;
          const r = popup.gridRows, row = popup.sel % r;
          const col = (Math.floor(popup.sel / r) + (event.key === Qt.Key_Left ? -1 : 1) + popup.effCols) % popup.effCols;
          popup.sel = Math.min(col * r + row, len - 1);
          Qt.callLater(() => list.positionViewAtIndex(popup.cellOf(popup.sel), GridView.Contain));
        }
      }
    }
  }

  FocusRetry {
    id: focusRetry
    live: popup.shown
    took: (popup.mode === "list" && filterInput.activeFocus) || (popup.mode !== "list" && bgRoot.activeFocus)
    onPlace: popup.syncFocus()
  }
}

// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ARTEMIS — the finder. Goddess of the hunt, who is said never to have missed
// what she aimed at: type a few letters and the thing you meant is the thing
// at the top. An index of the tree, an fzf over it, and a frecency count so
// what you actually open climbs.

import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import "artemis.js" as Artemis
import "../morpheus/icons.js" as Icons
import "../morpheus"
import "../terminus"
import "../terminus/terminus.js" as Terminus

LayerPopup {
  id: popup

  property string query: ""
  property var entries: []
  property var rows: []
  property int sel: 0
  property string searchRoot: Quickshell.env("HOME")

  // ── the index ────────────────────────────────────────────────────────
  // Where the walk gets written, and when it last happened. The file itself
  // is never read into QML — only fzf opens it — so its size costs the
  // engine nothing.
  readonly property string indexPath: Quickshell.cachePath("artemis-index")
  // kept for artemis.json and status(), not for deciding whether to rebuild
  property double indexedAt: 0
  property bool indexing: false
  property bool searching: false

  // Directories are in the index too; this narrows to them.
  property bool dirsOnly: false

  // Results can arrive out of order — a search is a process, killing one is
  // asynchronous, and a slow reply could otherwise land on top of a newer
  // one. Only the newest generation is allowed to write rows.
  property int searchGen: 0

  // The query the DELEGATES highlight against, updated on the debounce
  // rather than on the keystroke. `query` still moves immediately (the field
  // has to feel live), but every visible row re-runs highlightedPreview and
  // a full RichText reparse whenever this changes, and doing that against
  // results that have not arrived yet was pure waste.
  property string highlightQuery: ""

  property var freq: ({})

  // What runs on the tail of the row flash — see rowFlash.
  property var flashAct: null

  // ── RESULTS ARRIVE, THEY DO NOT FLICKER ──────────────────────────────
  // Every answer bumps arriveSeq, and a row near the top whose path CHANGED
  // with it rises in (see the delegate's arrive()). A row that is the same
  // file it was a keystroke ago stays perfectly still, so typing one more
  // letter that keeps the top of the list does not shimmer the whole panel.
  // arriveAt fences it to the moment of arrival: rows that come into view
  // later, by scrolling, are not arriving.
  property int arriveSeq: 0
  property double arriveAt: 0

  // The busiest row in the frecency map, so a row's heat pip can say how
  // hot it is relative to the rest rather than in raw opens.
  readonly property int freqMax: {
    let m = 0;
    for (const k in popup.freq) if (popup.freq[k] > m) m = popup.freq[k];
    return m;
  }

  // ── BUSY, BUT ONLY WHEN IT IS WORTH SAYING ───────────────────────────
  // A search is ~7ms and a walk ~19ms; dots that came up for that long on
  // every keystroke would be a flicker, not a message. They are shown once
  // the wait has outlasted busyDelay, which in practice means a cold cache.
  readonly property bool working: popup.searching || popup.indexing
  property bool busy: false
  onWorkingChanged: {
    if (popup.working) busyDelay.restart()
    else { busyDelay.stop(); popup.busy = false }
  }
  Timer { id: busyDelay; interval: 150; onTriggered: popup.busy = popup.working }

  // NOTHING MATCHED — asked of the query the rows ANSWER (highlightQuery),
  // not the one being typed, so the mark does not blink on between a
  // keystroke and its results.
  readonly property bool showNoMatch:
    popup.rows.length === 0 && popup.highlightQuery.trim() !== ""
  readonly property int emptyH: 128

  readonly property color bgColor: Zenon.layerBg
  readonly property color msgColor: Zenon.headBg
  readonly property color fgColor: Zenon.white
  readonly property color hintColor: Zenon.muted

  // ── THE KEYS, DRAWN AS KEYS ──────────────────────────────────────────
  // The hints were rich text with the key in bold and its word after it in
  // grey, and the colours were hex literals inside artemis.js — the palette
  // said twice. A chip says "this is a key you press" the way the rest of
  // this desktop says it, and takes its ink from Zenon like everything else.
  //
  // The recipe is terminus' KeyChip, which is an inline component of that
  // file and so cannot be imported.
  readonly property color dirColor: Zenon.blue

  // ── AS WIDE AS THE LONGEST RESULT ─────────────────────────────────────
  // A thousand pixels was the answer to every search: three short paths got
  // the same panel as a screen full of deep ones, most of it empty. The row
  // face is monospaced for measuring purposes — the delegate already fits
  // its path by counting characters against textMetrics — so the width a
  // result wants is arithmetic, not a layout pass. 68 is the chrome the
  // delegate spends either side of the text: 16 margin, a 26 glyph, 10 of
  // gap, 16 margin.
  //
  // The RAW preview is what is measured, never the fitted one: fitPath
  // shortens to whatever the width allows, so measuring the result of that
  // would be the width deciding itself.
  readonly property int rowChars: {
    let n = 0;
    for (let i = 0; i < popup.rows.length; ++i) {
      const p = popup.rows[i].preview;
      if (p && p.length > n) n = p.length;
    }
    return n;
  }
  readonly property int rowCellW:
    Math.ceil(popup.rowChars * textMetrics.advanceWidth) + 68

  // NO NARROWER THAN ITS OWN FOOTER. The hint strip is a row of chips
  // centred in the panel and its contents change with the mode (dirsOnly
  // reworks them), so the floor is measured off the row itself rather than
  // guessed at with a literal that would be wrong the day a hint is
  // reworded. No circle: what the row is wide is decided by the chips and
  // their labels, and not one of them looks at the panel.
  readonly property int hintPad: 24
  readonly property int minW:
    Math.ceil(hintRow.implicitWidth) + popup.hintPad * 2

  // shell.qml reads this for the morphed pill's width; it used to be the
  // literal 1000 in both files, with nothing keeping them equal. 1000 is
  // still the ceiling, under whatever Zenon.layerMax currently is.
  readonly property int panelWidth: popup.rowChars === 0
    ? popup.minW : Math.max(popup.minW, Math.min(1000, popup.rowCellW))
  readonly property int panelTarget: Zenon.layerWidth(popup.panelWidth)

  // WHAT IS ON SCREEN, which is not the target while the pill is moving.
  // Morphed, the pill's own animated width IS the value — following it makes
  // the two locked frame-for-frame, and a Behavior on top of an easing
  // source is a second easing chasing the first. Standalone there is no pill
  // to follow, so the ease lives here. Cynosure and folio do exactly this.
  property real liveWidth: (popup.morphMode && popup.statusbar
      && popup.statusbar.pillWidth > 0)
    ? popup.statusbar.pillWidth : popup.panelTarget
  Behavior on liveWidth {
    enabled: !popup.morphMode
    NumberAnimation { duration: Zenon.slow; easing.type: Zenon.ease }
  }

  readonly property int textCellH: 32
  readonly property int textRows: 12
  readonly property int msgH: 28
  readonly property int textColsUsed: 1
  readonly property int textRowsNeeded: Math.min(Math.max(1, Math.ceil(popup.rows.length / popup.textColsUsed)), popup.textRows)
  readonly property real textCellHeight: popup.textCellH
  readonly property int inputH: popup.query.length > 0 ? 36 : 0
  readonly property real bodyH: (popup.showNoMatch ? popup.emptyH
      : popup.textRowsNeeded * popup.textCellHeight)
    + popup.msgH + popup.inputH

  TextMetrics {
    id: textMetrics
    font.family: Zenon.face
    font.pixelSize: Zenon.px(16)
    font.weight: 600
    text: "M"
  }

  focusable: true

  // ── why a row could not be dragged out ───────────────────────────────
  // This surface covers the WHOLE screen (all four anchors, plus closeArea
  // filling it), so the pointer never leaves artemis during a drag and the
  // compositor resolved every drop back to artemis itself. The file had
  // nowhere to land.
  //
  // Icarus drags fine from inside a Flickable, so the Flickable was never
  // the problem — its menus just mask down to their own background
  // (Region { item: fileBg }) and are click-through everywhere else.
  //
  // Rather than mask permanently, which would let clicks outside the panel
  // fall through to whatever is underneath, the input region is dropped only
  // while a drag is actually in flight. Wayland's drag grab is separate from
  // the surface input region, so letting go of the region mid-drag does not
  // cancel the drag — it only changes who the drop resolves to.
  property bool dragging: false
  // Explicitly the whole surface when idle, explicitly nothing while dragging,
  // rather than leaning on what an unset mask means — getting that backwards
  // would leave artemis permanently click-through. closeArea already fills the
  // window, so it is the full-screen region.
  mask: Region { item: popup.dragging ? null : closeArea }

  HyprlandFocusGrab {
    id: grab
    windows: [ popup ]
    // Not while dragging: the pointer is over another application by design
    // at that point, and closing here would destroy the row the drag is
    // sourced from, mid-drag.
    active: popup.shown && !popup.dragging
    onCleared: popup.closePopup()
  }

  IpcHandler {
    target: "Artemis"
    function toggle() {
      popup.toggle();
    }
    // Same shape as Picasso's rescan(): the index is a cache, and there has to
    // be a way to rebuild it without waiting for it to go stale.
    function reindex(): string {
      popup.reindex();
      return "indexing";
    }
    function status(): string {
      return "index=" + popup.indexPath
        + " age=" + (popup.indexedAt > 0
            ? Math.round((Date.now() - popup.indexedAt) / 1000) + "s" : "never")
        + " indexing=" + popup.indexing
        + " known=" + Object.keys(popup.freq).length;
    }
  }

  Process {
    id: searchProc
    property int generation: 0
    property string nextCmd: ""
    property int nextGen: 0
    onExited: if (searchProc.nextCmd !== "") Qt.callLater(popup.startSearch)
    stdout: StdioCollector {
      id: out
      waitForEnd: true
      onStreamFinished: popup.onSearch(out.text, searchProc.generation)
    }
  }

  Process {
    id: actionProc
    onExited: (code) => popup.onActionDone(code)
  }

  // The walk. Runs detached from anything the user is waiting on: an open
  // shows whatever index is already on disk and lets this refresh it
  // underneath, which is picasso's "scan once and keep it warm" rather than
  // artemis's old "scan again on every keystroke".
  Process {
    id: indexProc
    onExited: {
      popup.indexing = false
      popup.indexedAt = Date.now()
      popup.saveState()
      // The first index of all: nothing could be shown until it existed.
      if (popup.shown) popup.refresh()
      popup.pruneFreq()
    }
  }

  // The frequency map outlives the files in it. Nothing pruned it, so a
  // download opened twice and then deleted kept its seat at the top of the
  // opening view for as long as the map survived — which is forever, because
  // the map is saved to disk.
  //
  // Checked after an index walk rather than on every open: that is the moment
  // the answer can have changed, and it costs one process over a few hundred
  // keys.
  Process {
    id: aliveProc
    stdout: StdioCollector {
      id: aliveOut
      waitForEnd: true
      onStreamFinished: {
        const alive = String(aliveOut.text || "").split("\u001e").filter((x) => x !== "")
        const before = Object.keys(popup.freq).length
        popup.freq = Artemis.pruneFreq(popup.freq, alive)
        if (Object.keys(popup.freq).length !== before) popup.saveState()
      }
    }
  }

  function pruneFreq() {
    const keys = Object.keys(popup.freq)
    if (keys.length === 0 || aliveProc.running) return
    aliveProc.command = ["sh", "-c", Artemis.aliveCommand(keys)]
    aliveProc.running = true
  }

  function reindex() {
    if (popup.indexing) return
    popup.indexing = true
    indexProc.command = ["sh", "-c",
      Artemis.indexCommand(popup.searchRoot || Quickshell.env("HOME"), popup.indexPath)]
    indexProc.running = true
  }


  function openPopup() {
    popup.shown = true
    popup.collapsing = false
    popup.query = ""
    searchInput.text = ""
    popup.sel = 0
    popup.highlightQuery = ""
    popup.dragging = false
    // Show something immediately off the existing index, and only then go and
    // freshen it. The old open() blocked on a 518k-file traversal to produce a
    // list of 200 arbitrary files.
    //
    // Unconditional, not "only if stale". The walk is 19ms for ~4k entries, so
    // there is nothing to buy by tolerating a stale index — and a staleness
    // window is exactly what made a manual reindex key necessary. indexProc
    // refreshes the view when it lands, ~19ms later.
    popup.refresh()
    popup.reindex()
    focusRetry.counter = 0
    focusRetry.restart()
    popup.playOpen();
  }

  function closePopup() {
    // the card goes with the finder; dismiss() is not used, because it hands
    // the keyboard back to a field that is on its way out
    openWith.close()
    // A drag that ends without onDragFinished would otherwise leave this
    // surface permanently input-transparent, i.e. unusable.
    popup.dragging = false
    rowFlash.cancel()
    popup.flashAct = null
    popup.collapsing = true
    popup.playClose();
  }

  function toggle() {
    if (popup.shown) popup.closePopup()
    else popup.openPopup()
  }

  // ── what to show ─────────────────────────────────────────────────────
  //
  // One entry point, because "no query" and "a query" are the same question
  // asked of the same index — they only differ in whether fzf is involved.
  function refresh() {
    const q = popup.query.trim()
    if (q === "") {
      popup.searching = false
      searchProc.running = false
      // What you actually open, most-used first. The old opening view was
      // `fd --max-results 200 | sort`, which bails after the first 200 hits
      // in nondeterministic traversal order — so it opened on 200 essentially
      // random files. cynosure.js already ranks its own list this way.
      const ranked = Artemis.freqRanked(popup.freq, 200)
      if (ranked.length > 0 && !popup.dirsOnly) {
        popup.setRows(ranked)
      } else {
        popup.run(Artemis.browseCommand(popup.indexPath, popup.dirsOnly))
      }
      return
    }
    popup.run(Artemis.filterCommand(popup.indexPath, q, popup.dirsOnly))
  }

  // Every result-producing command goes through here so the generation
  // bookkeeping cannot be forgotten at one of the call sites.
  function run(cmd) {
    popup.searchGen++
    popup.searching = true
    searchProc.nextCmd = cmd
    searchProc.nextGen = popup.searchGen
    // Killing a process is asynchronous, so the old run is stopped and the
    // new one started from its exit. Setting `generation` and `running` on
    // the spot relabelled the OLD run as the new one — its reply then passed
    // the generation check — and the start itself was a no-op, so the new
    // search never ran and `searching` stayed up.
    if (searchProc.running) { searchProc.running = false; return }
    popup.startSearch()
  }

  function startSearch() {
    if (searchProc.running || searchProc.nextCmd === "") return
    searchProc.generation = searchProc.nextGen
    searchProc.command = ["sh", "-c", searchProc.nextCmd]
    searchProc.nextCmd = ""
    searchProc.running = true
  }

  function onSearch(text, gen) {
    // A slower earlier search landing after a newer one used to clobber it.
    if (gen !== popup.searchGen) return
    popup.searching = false
    popup.setRows(Artemis.parseResults(text))
  }

  function setRows(rows) {
    popup.rows = rows
    popup.highlightQuery = popup.query
    popup.arriveAt = Date.now()
    popup.arriveSeq++
    popup.clampSel()
  }

  // fzf --filter has ALREADY fuzzy-matched and ranked by the time we see it.
  // What used to sit here was a second pass that re-filtered that output with
  // a contiguous-substring test — which threw away every non-contiguous match
  // fzf had just found. Artemis was paying for a fuzzy finder and shipping
  // substring search. There is nothing to do here but show what came back.

  function runAction(cmd, kind) {
    actionProc.command = ["sh", "-c", cmd]
    actionProc.running = true
  }

  // The file an open is out for, while it is — so its exit can be read as
  // "nothing opens this" and not as any other action ending.
  property string opening: ""

  function onActionDone(code) {
    const path = popup.opening
    popup.opening = ""
    // ── NOTHING OPENS IT: ASK ────────────────────────────────────────
    // The same card terminus raises for the same file, raised here over the
    // finder instead of closing it on a file that silently did not open.
    // What is chosen on it is registered against the type, so terminus and
    // artemis both open this kind of file with it from then on.
    if (path !== "" && code === Terminus.NO_HANDLER && popup.shown) {
      openWith.ask(path)
      return
    }
    popup.closePopup()
  }

  // ── FOR PLATO ────────────────────────────────────────────────────────
  // Plato's Ctrl-P is this finder, scoped to a project: it reads this index
  // (see `scope` in artemis.js), asks for it to be walked again through
  // reindex() when it opens, and says what it opened through here — so a file
  // opened from either one ranks in both. Nothing else of the popup is
  // plato's to touch.
  function noteOpened(path) {
    popup.freq = Artemis.bumpFreq(popup.freq, String(path))
    popup.saveState()
  }

  // ── A ROW LIGHTS UP BEFORE IT ACTS ───────────────────────────────────
  // terminus' RowFlash, as every sheet in the suite wears it: return used to
  // collapse the finder on the keystroke, so you never saw which row it took.
  // The row is captured NOW, not read at the tail — the flash is long enough
  // for an arrow key to land in, and what was opened is what was chosen.
  function flashThen(index, act) {
    // an open already on its way out is not interrupted by another
    if (rowFlash.running && popup.flashAct) return
    rowFlash.cancel()
    popup.flashAct = act
    rowFlash.fire(index)
  }

  RowFlash {
    id: rowFlash
    onDone: () => {
      const f = popup.flashAct
      popup.flashAct = null
      if (f) f()
    }
  }

  // The ROW is held, not its index: a search can land inside the flash and
  // put a different file at that index.
  function choose(index) {
    if (index < 0 || index >= popup.rows.length) return
    const row = popup.rows[index]
    popup.flashThen(index, () => popup.confirm(row))
  }

  function confirm(row) {
    if (!row) return
    popup.freq = Artemis.bumpFreq(popup.freq, row.path)
    popup.saveState()
    if (row.isDir) {
      popup.runAction(Artemis.openDirCommand(row.path), "cd")
      return
    }
    popup.opening = row.path
    popup.runAction(Terminus.openOrAskCommand(row.path), "open")
  }

  // ── what survives a restart ──────────────────────────────────────────
  // Artemis was the only interactive layer in the shell persisting nothing.
  // Same FileView + debounced setText shape as chronos and picasso.
  FileView {
    id: stateFile
    path: Quickshell.statePath("artemis.json")
    blockLoading: true
    printErrors: false
  }

  Timer {
    id: stateSave
    interval: 400
    onTriggered: stateFile.setText(JSON.stringify({
      freq: popup.freq, indexedAt: popup.indexedAt
    }))
  }

  function saveState() { stateSave.restart() }

  Component.onCompleted: {
    try {
      const j = JSON.parse(stateFile.text() || "{}")
      popup.freq = j.freq ?? ({})
      popup.indexedAt = j.indexedAt ?? 0
    } catch (e) {}
  }

  function rowCount() {
    return popup.rows.length
  }

  function stepSel(delta) {
    const len = popup.rowCount()
    if (len === 0) return
    popup.sel = ((popup.sel + delta) % len + len) % len
    popup.followSelection()
  }

  function moveVert(delta) {
    const len = popup.rowCount()
    if (len === 0) return
    const cols = popup.textColsUsed
    const rows = Math.ceil(len / cols)
    const row = Math.floor(popup.sel / cols)
    const col = popup.sel % cols
    let newRow = (row + delta) % rows
    if (newRow < 0) newRow += rows
    const rowValid = (newRow === rows - 1) ? (len - newRow * cols) : cols
    const newCol = Math.min(col, rowValid - 1)
    popup.sel = newRow * cols + newCol
    popup.followSelection()
  }

  function moveHoriz(delta) {
    const len = popup.rowCount()
    if (len === 0) return
    const cols = popup.textColsUsed
    if (cols <= 1) {
      popup.stepSel(delta)
      return
    }
    const row = Math.floor(popup.sel / cols)
    const col = popup.sel % cols
    const rowStart = row * cols
    const rowLen = Math.min(cols, len - rowStart)
    const newCol = (col + delta) % rowLen
    const adjCol = newCol < 0 ? newCol + rowLen : newCol
    popup.sel = rowStart + adjCol
    popup.followSelection()
  }

  function pageMove(delta) {
    const len = popup.rowCount()
    if (len === 0) return
    const page = popup.textRowsNeeded * popup.textColsUsed
    popup.sel = Math.max(0, Math.min(len - 1, popup.sel + delta * page))
    popup.followSelection()
  }

  function goHome() {
    if (popup.rowCount() > 0) popup.sel = 0
    popup.followSelection()
  }

  function goEnd() {
    const len = popup.rowCount()
    if (len > 0) popup.sel = len - 1
    popup.followSelection()
  }

  function clampSel() {
    const len = popup.rowCount()
    if (len === 0) popup.sel = 0
    else if (popup.sel >= len) popup.sel = len - 1
    else if (popup.sel < 0) popup.sel = 0
    popup.followSelection()
  }

  function followSelection() {
    Qt.callLater(() => {
      fileGrid.positionViewAtIndex(popup.sel, GridView.Contain)
    })
  }

  MouseArea {
    id: closeArea
    anchors.fill: parent
    z: 0
    onClicked: popup.closePopup()
  }

  // shell.qml sizes the morphed pill from this; without it the pill fell back
  // to a hardcoded 320px and the panel floated free of its own background
  function calcHeight() {
    return popup.bodyH;
  }

  Item {
    id: panel
    width: Math.round(popup.liveWidth)
    height: popup.bodyH
    // Zenon.slow is the pill's own height easing in shell.qml; if these drift
    // apart the panel visibly detaches from its background mid-resize
    Behavior on height { NumberAnimation { duration: Zenon.slow; easing.type: Zenon.ease } }
    // Either edge. A layer opens out of the pill, so it has to be on the
    // same one, off whichever it is by the same lift. Placed by y, NOT by a
    // top/bottom anchor pair: flipping two anchors at runtime updates one
    // before the other, for that instant both apply and stretch the panel to
    // the screen, and that stretch overwrites — and so unbinds — `height`.
    // The panel then stayed screen-tall until the shell was restarted.
    anchors.horizontalCenter: parent.horizontalCenter
    y: Zenon.barTop ? Zenon.edgeLift(popup.morphMode, popup.screen, popup.statusbar)
      : parent.height - height - Zenon.edgeLift(popup.morphMode, popup.screen, popup.statusbar)
    z: 1
    opacity: popup.contentFade
    transform: Scale {
      origin.x: panel.width / 2
      // grows out of the edge the bar is on, which is the edge it came from
      origin.y: Zenon.barTop ? 0 : panel.height
      xScale: popup.panelX
      yScale: popup.panelY
    }

    MouseArea { anchors.fill: parent }

    LayerShadow {
      panel: bg
      cornerRadius: Zenon.pillRadius
      morphed: popup.morphMode
    }

    // ClippingRectangle, not Rectangle + clip: true. Qt's own clip is
    // RECTANGULAR — it clips to the bounding box and knows nothing about the
    // radius — so every square child painted to the panel's edge (the bottom
    // strip most visibly) filled in the rounded corners behind it. This one
    // clips to the rounded shape itself.
    ClippingRectangle {
      id: bg
      anchors.fill: parent
      // Grown by its own border. A ClippingRectangle insets its children by
      // border.width on every side, so the content box came out 2px smaller
      // than the panel and every layout measured against the panel's size was
      // short by one row or one column. Expanding the clipper by the border
      // hands the content its full box back; the outline simply sits a pixel
      // further out, which is invisible.
      anchors.margins: -bg.border.width
      color: popup.bgColor
      radius: Zenon.pillRadius
      border.color: Zenon.border
      border.width: 1

      // results scrolled off the top carry on under the search line,
      // frosted — see morpheus/ScrollEdge. Before the column, so the line
      // draws over it; nothing to go under while the line is folded away.
      ScrollEdge {
        view: fileGrid
        x: fileGrid.parent.x + fileGrid.x
        width: fileGrid.width
        height: fileGrid.parent.y + fileGrid.y
      }
      // and the ones still below rise out of the hint strip
      ScrollEdge {
        view: fileGrid
        below: true
        x: fileGrid.parent.x + fileGrid.x
        y: msgBar.y
        width: fileGrid.width
        height: msgBar.height
      }

      Column {
        anchors.fill: parent

        Rectangle {
          id: inputBar
          width: parent.width
          // Off the same property as bodyH, and on the panel's own clock
          // (Zenon.slow): the line and the panel grow together, so the list
          // under them rides down with the edge instead of being shoved a row
          // and then caught up with.
          height: popup.inputH
          visible: height > 0.5
          clip: true
          color: "transparent"
          Behavior on height { NumberAnimation { duration: Zenon.slow; easing.type: Zenon.ease } }

          Row {
            anchors.fill: parent
            anchors.leftMargin: 10
            spacing: 0
            // fades in as it unfolds, rather than being uncovered by the clip
            opacity: inputBar.height / 36
            Behavior on opacity { NumberAnimation { duration: Zenon.fast } }

            Text {
              id: promptText
              width: 30
              height: parent.height
              // The lens, or — while alt d narrows to directories — the
              // directory, in the directories' own blue: the mode is said where you
              // are looking, not only in the hint strip.
              text: popup.dirsOnly ? Icons.glyphFor({ name: "", isDir: true }) : "\uf002"
              color: popup.dirsOnly ? popup.dirColor : Zenon.magenta
              Behavior on color { ColorAnimation { duration: Zenon.fast } }
              font.family: popup.dirsOnly ? Zenon.faceMono : Zenon.face
              font.weight: Font.Bold
              font.pixelSize: Zenon.px(18)
              verticalAlignment: Text.AlignVCenter
            }

            TextInput {
              id: searchInput
              width: parent.width - promptText.width - busyDots.width - 16
              height: parent.height
              // the words in the ink; the lens beside them keeps the magenta
              // (the user's call, 2026-10-08)
              color: Zenon.ink
              selectionColor: Zenon.magenta
              selectedTextColor: Zenon.onAccent
              font.family: Zenon.face
              font.weight: Font.Bold
              font.pixelSize: Zenon.px(18)
              verticalAlignment: Text.AlignVCenter
              focus: true
              // the shell's one caret, in the field's own ink — it follows
              // the arrow keys, where the old pulse was pinned to the end
              cursorDelegate: Caret { field: searchInput; color: Zenon.magenta }
              clip: true
              Keys.forwardTo: bg
              onTextChanged: {
                popup.query = searchInput.text
                popup.sel = 0
                // Clearing the field is instant — there is no process to
                // debounce, the frecency list is already in hand.
                if (popup.query.trim() === "") popup.refresh()
                else searchDebounce.restart()
              }
            }
          }

          // out and not back yet — see popup.busy for why it waits first
          Working {
            id: busyDots
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            running: popup.busy && popup.rows.length > 0
            ink: Zenon.magenta
          }
        }

        Item {
          id: body
          width: parent.width
          height: parent.height - inputBar.height - msgBar.height

          // ── WHEN THERE ARE NO ROWS ─────────────────────────────────────
          // Three different answers, and a line of grey text was all three.
          // Nothing matched is terminus' mark — the same lens over the same
          // word — and the body grows to hold it (see emptyH). Still out is
          // the shell's dots. Nothing typed and nothing yet opened is the
          // one place a word is still the right thing.
          EmptyMark {
            anchors.centerIn: parent
            filtered: true
            visible: popup.shown && popup.showNoMatch
          }

          Working {
            anchors.centerIn: parent
            running: popup.shown && popup.rows.length === 0 && !popup.showNoMatch
              && popup.working
            dot: 6
          }

          Text {
            anchors.centerIn: parent
            text: "type to search"
            color: popup.hintColor
            font.family: Zenon.face
            font.weight: 600
            font.pixelSize: Zenon.px(15)
            visible: popup.shown && popup.rows.length === 0 && !popup.showNoMatch
              && !popup.working
          }

          GridView {
            id: fileGrid
            // Finder's rubber band and the smooth wheel notch, one rule for
            // the whole shell — see morpheus/Elastic.qml. Inside the view
            // rather than over it: it pins itself to the viewport.
            ElasticScroll { view: fileGrid; step: popup.textCellHeight * 4 }
            // the shell's one scrollbar, as every other list has
            ScrollRail {
              target: fileGrid
              parent: fileGrid
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.bottom: parent.bottom
            }
            anchors.fill: parent
            clip: true
            // DOWN THE PAGE, NOT ACROSS. Top-to-bottom flow with one column the
            // view's width wide lays its columns out SIDEWAYS: a twelfth row went
            // to a second column off to the right, so the grid could only ever
            // scroll horizontally — and the wheel, which scrolls down, found
            // nothing to move. Left-to-right with one column is a plain list.
            flow: GridView.FlowLeftToRight
            cellWidth: fileGrid.width
            cellHeight: popup.textCellHeight
            model: popup.rows
            // ── THE CARET, AND NOTHING ELSE ────────────────────────────────
            // One selection for the whole list, sliding between rows rather
            // than jumping — a fill per delegate could only ever blink from
            // one to the next. selBg is the suite's selection ground; the
            // magenta edge ties it to the field you are typing into.
            //
            // A row used to tint under the pointer as well, which said "this
            // is the one" about a row that was not — the selection is moved
            // with the keys here and a single click only moves the caret, so a
            // second highlight following the mouse was a second answer to the
            // only question this list asks.
            //
            // PARENTED BY HAND. A child declared inside a GridView lands on
            // the view itself, NOT its contentItem (measured — see the note in
            // morpheus/ElasticScroll), so the mark sat still in viewport
            // coordinates while the rows scrolled: once the caret passed the
            // last visible row it sank out of the bottom and every row after
            // it went unmarked. In the contentItem it scrolls with the rows;
            // z 0 is under the delegates' 1.
            Rectangle {
              id: selMark
              parent: fileGrid.contentItem
              z: 0
              width: fileGrid.cellWidth
              height: fileGrid.cellHeight
              y: Math.floor(popup.sel / popup.textColsUsed) * fileGrid.cellHeight
              visible: popup.rows.length > 0
              color: Zenon.selBg
              Behavior on y { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
              Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 2
                height: parent.height - 12
                radius: 1
                color: popup.dirsOnly ? popup.dirColor : Zenon.magenta
              }
            }
            // Each row carries a RichText, a glyph, a flash, an animation, a
            // Connections and a MouseArea. Handing the view a fresh array used to destroy and
            // rebuild every one of them on every search — the same trap
            // Tooltip.qml and ZeusPopup.qml both already carry a scar from.
            reuseItems: true
            cacheBuffer: 4000

            delegate: Item {
              id: row
              required property var modelData
              required property int index
              width: fileGrid.cellWidth
              height: fileGrid.cellHeight

              // ── ARRIVING ONE AFTER ANOTHER ─────────────────────────────
              // When the panel opens, each of the first eight rows fades in
              // and rises a few pixels, Zenon.stagger after the one before.
              property real enter: 1
              opacity: row.enter
              transform: Translate { y: (1 - row.enter) * 6 }
              Connections {
                target: popup
                function onOpenedChanged() {
                  if (row.index > 7 || Zenon.stagger === 0) return;
                  row.enter = 0;
                  rowArrive.restart();
                }
              }
              SequentialAnimation {
                id: rowArrive
                PauseAnimation { duration: row.index * Zenon.stagger }
                NumberAnimation {
                  target: row; property: "enter"; to: 1
                  duration: Zenon.normal; easing.type: Zenon.ease
                }
              }

              // Drag a result straight into another application, the same way
              // icarus drags a file out of its browser. encodeURI rather than
              // raw concatenation: half the paths in this index have spaces in
              // them, and text/uri-list wants them percent-encoded.
              // NOT BOUND TO THE HANDLER, and that is the whole reason the
              // drag card never appeared. A binding starts the drag the
              // instant the handler activates — which is a frame before
              // grabToImage can answer — so Drag.imageSource was still empty
              // when the compositor asked for the icon, and assigning it
              // afterwards only broke the binding. Set imperatively in the
              // grab's callback instead, so the picture exists before the
              // drag does.
              Drag.active: false
              Drag.source: row
              Drag.keys: ["text/uri-list"]
              Drag.mimeData: ({ "text/uri-list": Strings.fileUrl(row.modelData.path) + "\r\n" })
              Drag.supportedActions: Qt.CopyAction
              Drag.dragType: Drag.Automatic
              Drag.hotSpot.x: width / 2
              Drag.hotSpot.y: height / 2
              Drag.onDragFinished: function(dropAction) {
                // Cleared by hand now that nothing binds it — see Drag.active.
                row.Drag.active = false
                popup.dragging = false
                if (dropAction === Qt.CopyAction) popup.closePopup()
              }

              // The same glyph terminus draws for the same file, from the
              // same table — see morpheus/icons.js. A result list over the
              // tree and a listing of the tree are two views of one thing,
              // and a .rs that is a Rust mark in one and a blank page in the
              // other is two answers to one question.
              //
              // Worked out ONCE per delegate rather than in the Text's own
              // binding: reuseItems re-binds modelData on every recycled row,
              // and glyphFor walks three tables — cheap, but not cheap enough
              // to pay for on every rebind of every row of five hundred.
              readonly property string glyph: {
                const p = String(row.modelData.path || "")
                // the index marks a directory with a trailing slash, which is
                // not part of its name
                const bare = row.modelData.isDir ? p.replace(/\/+$/, "") : p
                const cut = bare.lastIndexOf("/")
                return Icons.glyphFor({ name: cut < 0 ? bare : bare.slice(cut + 1),
                                        isDir: row.modelData.isDir })
              }

              // ── HOW OFTEN YOU OPEN IT ──────────────────────────────────
              // Before anything is typed the list IS the frecency ranking,
              // and nothing on it said so — it read as an arbitrary handful.
              // A pip in the gutter, as bright as the file is hot relative to
              // the hottest; gone the moment you type, when the order is
              // fzf's and the count is beside the point.
              Rectangle {
                readonly property int hits: popup.freq[row.modelData.path] || 0
                visible: popup.highlightQuery === "" && hits > 0 && popup.freqMax > 0
                x: 7
                anchors.verticalCenter: parent.verticalCenter
                width: 4
                height: 4
                radius: 2
                color: Zenon.magenta
                opacity: 0.2 + 0.8 * hits / Math.max(1, popup.freqMax)
              }

              // The row's face — glyph and path — as one piece, so it can
              // rise in on arrival without the selection or the flash moving.
              Item {
                id: face
                anchors.fill: parent
                transform: Translate { id: lift }

                Text {
                  id: rowGlyph
                  anchors.left: parent.left
                  anchors.leftMargin: 16
                  anchors.verticalCenter: parent.verticalCenter
                  width: 26
                  horizontalAlignment: Text.AlignHCenter
                  text: row.glyph
                  color: modelData.isDir ? popup.dirColor : popup.fgColor
                  // MONO for the glyph and proportional for the path beside it:
                  // the icons are drawn on a fixed advance, and in the
                  // proportional face they come out at different widths, so the
                  // paths would not line up down the column.
                  font.family: Zenon.faceMono
                  font.weight: Zenon.weight
                  // A touch larger than the path beside it. These are pictures,
                  // not letters: at the text's own size they read as smudges in
                  // the margin rather than as marks you can tell apart at a
                  // glance, which is the whole job.
                  font.pixelSize: Zenon.px(22)
                }

                Text {
                  anchors.fill: parent
                  anchors.leftMargin: 16 + 26 + 10
                  anchors.rightMargin: 16
                  text: {
                    // THE TARGET WIDTH, not the live one. The panel follows the
                    // pill while it morphs, so measuring against the view would
                    // re-fit and re-mark-up every row on every frame of the
                    // animation for an answer only correct at the end of it.
                    const avail = Math.max(1, Math.floor(
                      (popup.panelTarget - 32 - 36) / textMetrics.advanceWidth))
                    // the parent path recedes, so the NAME is what reads down
                  // the column; matched letters are lit in either part
                  return Artemis.highlightedPreview(
                      Artemis.fitPath(modelData.preview, avail), popup.highlightQuery,
                      { match: String(Zenon.magenta), dim: String(popup.hintColor) })
                  }
                  color: modelData.isDir ? popup.dirColor : popup.fgColor
                  textFormat: Text.RichText
                  font.family: Zenon.face
                  font.weight: 600
                  font.pixelSize: Zenon.px(16)
                  clip: true
                  // No `elide` here: RichText is measured after the markup is
                  // parsed, so eliding fights the manual fit above and the
                  // manual one always won anyway.
                  wrapMode: Text.NoWrap
                  horizontalAlignment: Text.AlignLeft
                  verticalAlignment: Text.AlignVCenter
                }
              }

              // ── ARRIVING ───────────────────────────────────────────────
              // A row near the top that is showing a DIFFERENT file than it
              // was rises in, staggered down the list. The same file stays
              // still. Called from the answer (arriveSeq) and from the view
              // handing this delegate out (created or reused), because which
              // of those happens first depends on whether the row existed.
              property string lastPath: ""
              property int seenSeq: -1
              function arrive() {
                const p = String(row.modelData.path || "")
                const fresh = row.seenSeq !== popup.arriveSeq
                  && Date.now() - popup.arriveAt < 200
                  && row.index < 10 && p !== row.lastPath
                row.seenSeq = popup.arriveSeq
                row.lastPath = p
                if (fresh) arriveAnim.restart()
                else if (!arriveAnim.running) { face.opacity = 1; lift.y = 0 }
              }
              Component.onCompleted: row.arrive()
              GridView.onReused: row.arrive()
              Connections {
                target: popup
                function onArriveSeqChanged() { row.arrive() }
              }
              SequentialAnimation {
                id: arriveAnim
                PropertyAction { target: face; property: "opacity"; value: 0 }
                PropertyAction { target: lift; property: "y"; value: 5 }
                PauseAnimation { duration: row.index * 14 }
                ParallelAnimation {
                  NumberAnimation { target: face; property: "opacity"; to: 1
                                    duration: Zenon.fast; easing.type: Zenon.ease }
                  NumberAnimation { target: lift; property: "y"; to: 0
                                    duration: Zenon.fast; easing.type: Zenon.ease }
                }
              }

              // lit before it acts — see popup.flashThen
              FlashOver { flash: rowFlash; index: row.index }

              DragHandler {
                id: rowDrag
                target: null
                onActiveChanged: {
                  if (!active) return
                  // region first, so the surface is already transparent by
                  // the time the drag is offered
                  popup.dragging = true
                  // WHAT YOU ARE CARRYING, drawn beside the cursor. Without it
                  // a drag out of here was an invisible one: the popup gets out
                  // of the way the moment the gesture starts, so between
                  // picking a result up and dropping it there was nothing on
                  // screen saying which result it was. terminus has said so
                  // since it learned to drag, and this is the same card.
                  //
                  // The picture is made BEFORE the drag is offered, because
                  // Drag.imageSource is read when Drag.active turns true and
                  // grabToImage answers a frame later — set them the other way
                  // round and every drag carries the previous one's picture.
                  popup.dragPicture(row, function(url) {
                    row.Drag.imageSource = url
                    row.Drag.active = true
                  })
                }
              }

              MouseArea {
                id: rowMa
                anchors.fill: parent
                // A single click only moves the caret — opening on one click
                // meant there was no way to point at a row without launching
                // it, and no way to start a drag from one either.
                onClicked: popup.sel = row.index
                onDoubleClicked: {
                  popup.sel = row.index
                  popup.choose(row.index)
                }
              }
            }
          }
        }

        Rectangle {
          id: msgBar
          width: parent.width
          height: popup.msgH
          color: Zenon.hintFrostBg   // the results rise out of it — see the ScrollEdges
          Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Zenon.border
          }
          // the suite's hint strip — morpheus/HintRow, as every layer has it
          HintRow {
            id: hintRow
            anchors.centerIn: parent
            rows: Artemis.hintText(popup.dirsOnly)
          }
        }
      }

      Keys.onEscapePressed: (event) => {
        event.accepted = true;
        if (searchInput.text !== "") {
          searchInput.text = "";
        } else {
          popup.closePopup();
        }
      }
      Keys.onReturnPressed: (event) => {
        event.accepted = true
        popup.choose(popup.sel)
      }
      Keys.onLeftPressed: (event) => { event.accepted = true; popup.moveHoriz(-1) }
      Keys.onRightPressed: (event) => { event.accepted = true; popup.moveHoriz(1) }
      Keys.onUpPressed: (event) => { event.accepted = true; popup.moveVert(-1) }
      Keys.onDownPressed: (event) => { event.accepted = true; popup.moveVert(1) }
      Keys.onPressed: (event) => {
        if (event.key === Qt.Key_PageUp) {
          event.accepted = true
          popup.pageMove(-1)
        } else if (event.key === Qt.Key_PageDown) {
          event.accepted = true
          popup.pageMove(1)
        } else if (event.key === Qt.Key_Home) {
          event.accepted = true
          popup.goHome()
        } else if (event.key === Qt.Key_End) {
          event.accepted = true
          popup.goEnd()
        } else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_D) {
          event.accepted = true
          popup.dirsOnly = !popup.dirsOnly
          popup.sel = 0
          popup.refresh()
        } else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_C) {
          // copy only. Clearing the search box is esc's job in every layer,
          // and overloading alt c meant the hint bar could only ever describe
          // half of what the key did.
          event.accepted = true
          if (popup.rows.length > 0) {
            const path = popup.rows[popup.sel].path
            Quickshell.execDetached(["sh", "-c", "printf '%s' " + Strings.shellQuote(path) + " | wl-copy 2>/dev/null"])
            // the suite's flash, with nothing on its tail — the copy is done
            popup.flashThen(popup.sel, null)
          }
        }
      }
    }
  }

  // ── what a drag is carrying ───────────────────────────────────────────
  // The suite's drag card (terminus/DragCard.qml): the labels are filled in,
  // the picture is taken, and the drag carries the photograph.
  function dragPicture(row, then) {
    const p = String(row.modelData.path || "")
    const bare = row.modelData.isDir ? p.replace(/\/+$/, "") : p
    const cut = bare.lastIndexOf("/")
    // The NAME, not the path. A drag card is read at a glance beside a moving
    // cursor, and the rest of the path is what the row behind it is already
    // showing.
    dragCard.label = cut < 0 ? bare : bare.slice(cut + 1)
    dragCard.glyph = row.glyph
    dragCard.ink = row.modelData.isDir ? popup.dirColor : popup.fgColor
    dragCard.picture(then)
  }

  DragCard { id: dragCard }

  // ── OPEN WITH, RAISED OVER THE FINDER ────────────────────────────────
  // Terminus' open-with card, for a file nothing opens — see
  // terminus/OpenWithLayer.qml. Over everything else on this surface: the
  // panel underneath dims rather than going, so you can see what you were in
  // the middle of, and a click off the card puts it away and leaves the
  // finder as it was.
  OpenWithLayer {
    id: openWith
    z: 50
    dim: panel
    // registered and opened — the finder is done, as after any other open
    onOpened: popup.closePopup()
    // back to the field, not closed: escape on the card is "not this", and
    // the finder still has what you were looking at
    onCancelled: if (popup.shown) searchInput.forceActiveFocus()
  }

  Timer {
    id: focusRetry
    interval: 60
    repeat: true
    onTriggered: {
      if (!popup.shown) {
        stop()
        return
      }
      searchInput.forceActiveFocus()
      if (searchInput.activeFocus) stop()
      if (focusRetry.counter++ > 12) stop()
    }
    property int counter: 0
  }

  Timer {
    id: searchDebounce
    interval: 200
    repeat: false
    onTriggered: popup.refresh()
  }
}

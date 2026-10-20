// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Io
import Quickshell.Hyprland
import "ideo.js" as Ideo
import "../morpheus"
import "../morpheus/gridnav.js" as Nav

LayerPopup {
  id: popup

  readonly property color bgColor: Zenon.layerBg
  readonly property color fgColor: Zenon.white
  readonly property color headColor: Zenon.cyan
  readonly property color dimColor: Zenon.muted
  readonly property color entryColor: Zenon.pink
  readonly property color errColor: Zenon.red

  // mode: emoji · nerd
  property var memo: ({})             // per-mode { entries, filtered, query, sel }
  property string appMode: "emoji"
  property string query: ""
  property var entries: []
  property var filtered: []
  property int sel: 0
  property bool nerdLoading: false
  property bool nerdFailed: false
  // nothing to show yet and nothing has gone wrong: from the open, through
  // the deferred load and the fetch, until the set lands. nerdLoading alone
  // left the gap before the fetch starts, which read as "No matches found"
  readonly property bool nerdPending: popup.appMode === "nerd"
    && popup.nerdCache.length === 0 && !popup.nerdFailed
  // what the last copy put on the clipboard; nerd mode stays open after a
  // copy, so the count line says it for a moment instead of the close
  property string copiedNote: ""

  // nerd format strip state
  property bool formatMode: false
  property int formatSel: 0
  readonly property var formats: ["icon", "class", "utf"]

  // Parsed once per shell session, not once per open. Neither set changes
  // underneath us, and re-reading 670KB of emoji-test.txt — then running a
  // regex over every one of its lines — stalled the UI thread in the middle
  // of the morph. That stall was the jerk in this layer's entrance.
  property var emojiCache: []
  property var nerdCache: []

  focusable: true

  HyprlandFocusGrab {
    id: grab
    windows: [ popup ]
    active: popup.shown
    onCleared: popup.closePopup()
  }

  IpcHandler {
    target: "Ideo"

    function toggle() {
      if (popup.shown) popup.closePopup();
      else popup.openPopup("emoji");
    }

    function emoji() { popup.openPopup("emoji"); }

    function nerd() { popup.openPopup("nerd"); }
  }

  // ------------------------------------------------------------- procs --

  Process {
    id: emojiProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: popup.onEmojiFile(text)
    }
  }

  function onEmojiFile(text) {
    popup.emojiCache = Ideo.parseEmojiTest(text);
    // the user can tab to the other mode while this is in flight; the result
    // still belongs in the cache, but it must not overwrite what is on screen
    if (popup.appMode !== "emoji") return;
    popup.entries = popup.emojiCache;
    popup.applyFilter();
  }

  Timer {
    id: loadDeferred
    // just past the morph. A first parse still has to happen somewhere, but
    // not while the pill is mid-animation into this layer's shape.
    interval: Zenon.slow + 40
    onTriggered: {
      if (popup.appMode === "emoji") {
        emojiProc.command = ["cat", "/usr/share/unicode/emoji/emoji-test.txt"];
        emojiProc.running = true;
      } else {
        popup.fetchNerds();
      }
    }
  }

  function fetchNerds() {
    popup.nerdLoading = true;
    popup.nerdFailed = false;
    const xhr = new XMLHttpRequest();
    xhr.open("GET", "https://www.nerdfonts.com/assets/css/webfont.css");
    xhr.onreadystatechange = () => {
      if (xhr.readyState !== XMLHttpRequest.DONE) return;
      popup.nerdLoading = false;
      if (xhr.status !== 200 || !xhr.responseText) {
        popup.nerdFailed = true;
        return;
      }
      popup.nerdCache = Ideo.parseNerdCss(xhr.responseText);
      if (popup.appMode !== "nerd") return;
      popup.entries = popup.nerdCache;
      popup.applyFilter();
    };
    xhr.send();
  }

  // ---------------------------------------------------------- actions --

  // emoji copies close the picker, as they always have; nerd copies keep
  // it open — picking icons tends to come in runs — and say so in the
  // count line instead
  function copyText(t, what) {
    if (popup.appMode === "emoji") {
      popup.closePopup();
      popup.detach("sleep 0.25 && printf '%s' " + Strings.shellQuote(t) +
        " | wl-copy >/dev/null 2>&1");
      return;
    }
    popup.detach("printf '%s' " + Strings.shellQuote(t) +
      " | wl-copy >/dev/null 2>&1");
    // a short word, not the copied text: the count line sets the floor of
    // the panel width, and a long class name would jolt it wider
    popup.copiedNote = "Copied " + (what || "icon");
    copiedTimer.restart();
    if (popup.formatMode) {
      popup.formatMode = false;
      popup.syncFocus();
    }
  }

  Timer {
    id: copiedTimer
    interval: 1400
    onTriggered: popup.copiedNote = ""
  }

  function copyFormat() {
    const e = currentRow();
    if (!e) return;
    const f = popup.formats[popup.formatSel];
    if (f === "icon") popup.copyText(e.char, "icon");
    else if (f === "class") popup.copyText(e.cls, "class");
    else popup.copyText("U+" + e.code.toUpperCase(), "codepoint");
  }

  function detach(script) {
    if (script) Quickshell.execDetached(["bash", "-c", script]);
  }

  // ------------------------------------------------------------- open --

  function openPopup(mode) {
    // when already shown (tab-switch) we must NOT touch showFactor — a
    // single invisible frame drops the layer surface, clears the focus
    // grab, and the grab's onCleared closes us. no open animation either:
    // the swap should be invisible, just content changing under the cursor
    const cold = !popup.shown;

    if (cold) {
      popup.shown = true;
      popup.collapsing = false;
      popup.playOpen();
      popup.memo = {};               // a fresh open retains nothing
    } else {
      // park the outgoing mode exactly where the user left it
      popup.memo[popup.appMode] = {
        entries: popup.entries,
        filtered: popup.filtered,
        query: popup.query,
        sel: popup.sel,
      };
    }

    popup.appMode = mode || "emoji";
    popup.formatMode = false;
    popup.formatSel = 0;

    const memo = popup.memo[popup.appMode];
    if (!cold && memo && memo.entries.length > 0) {
      // seen before: restore instantly, no reload flicker
      popup.entries = memo.entries;
      popup.filtered = memo.filtered;
      popup.sel = Math.min(memo.sel, Math.max(0, memo.filtered.length - 1));
      popup.query = memo.query;
    } else {
      const cache = popup.appMode === "emoji" ? popup.emojiCache : popup.nerdCache;
      popup.entries = cache;
      popup.filtered = [];
      popup.sel = 0;
      popup.query = "";
      if (cache.length === 0) {
        // a fresh try: the last failure is not this one
        if (popup.appMode === "nerd") popup.nerdFailed = false;
        loadDeferred.restart();
      }
    }

    filterInput.text = popup.query;
    popup.applyFilter();

    if (cold) {
      focusRetry.begin();
    }
    popup.syncFocus();
  }

  function closePopup() {
    popup.collapsing = true;
    popup.playClose();
  }

  property real lastTab: 0

  function toggleMode() {
    const now = Date.now();
    if (now - popup.lastTab < 80) return;   // same chord delivered twice
    popup.lastTab = now;
    popup.openPopup(popup.appMode === "emoji" ? "nerd" : "emoji");
  }

  function syncFocus() {
    Qt.callLater(() => {
      if (!popup.shown) return;
      filterInput.forceActiveFocus();
    });
  }

  // ------------------------------------------------------ list logic --

  function applyFilter() {
    popup.filtered = Ideo.filterEntries(popup.entries, popup.query);
    const len = popup.filtered.length;
    if (popup.sel >= len) popup.sel = len > 0 ? len - 1 : 0;
    Qt.callLater(() => grid.positionViewAtIndex(popup.sel, ListView.Contain));
  }

  // ── AS WIDE AS THERE ARE PICTURES ─────────────────────────────────────
  // Nineteen columns was the answer whether the filter left four emoji or
  // four hundred, so a narrow search sat in the left corner of a panel that
  // was nine tenths empty. The cells are a fixed size, so the only width
  // this grid can honestly be is a whole number of them.
  readonly property int cellW: popup.appMode === "emoji" ? 52 : 62
  // ── THE NERD GLYPH, LOOKED AT (user, 2026-10-14) ─────────────────────
  // A pane right of the grid with the selected icon large, its name, its
  // set, the class and the codepoint. Nerd mode only; it takes its width
  // out of the grid's ceiling, so the panel does not grow for it.
  readonly property int previewW: popup.appMode === "nerd" ? 250 : 0
  readonly property int colsMax: Math.max(1, Math.floor((1000 - popup.previewW) / popup.cellW))
  // Nothing loaded yet is not the same as nothing to show — the same rule
  // gridHeight() already follows. Measured as one column, the pill morphed
  // to a sliver and snapped wide the instant the set landed.
  readonly property int colsUsed: popup.entries.length === 0 ? popup.colsMax
    : Math.max(1, Math.min(popup.filtered.length, popup.colsMax))

  // The literal 1000 above and not panelWidth: the ceiling is what limits
  // the columns, and reading the width back would be the width deciding
  // itself.
  function cols() {
    return popup.colsUsed;
  }

  // NO NARROWER THAN ITS OWN FOOTER. The hint strip's chips change with the
  // mode, so the floor is measured off the strip rather than guessed at with
  // a literal that would be wrong the day a hint is reworded.
  readonly property int hintPad: 24
  // the count and the hints share the one line now, so both are owed room
  readonly property int minW: Math.ceil(msgStrip.needW) + popup.hintPad * 2

  readonly property int panelWidth:
    Math.max(popup.minW, popup.colsUsed * popup.cellW + popup.previewW)
  readonly property int panelTarget: Zenon.layerWidth(popup.panelWidth)

  // WHAT IS ON SCREEN, which is not the target while the pill is moving.
  // Morphed, the pill's own animated width IS the value — following it makes
  // the two locked frame-for-frame, and a Behavior on top of an easing
  // source is a second easing chasing the first. Standalone there is no pill
  // to follow, so the ease lives here. Cynosure, folio and artemis do the
  // same.
  property real liveWidth: (popup.morphMode && popup.statusbar
      && popup.statusbar.pillWidth > 0)
    ? popup.statusbar.pillWidth : popup.panelTarget
  Behavior on liveWidth {
    enabled: !popup.morphMode
    NumberAnimation { duration: Zenon.slow; easing.type: Zenon.ease }
  }

  // ── THE KEYS THAT MOVE THE GRID, IN ONE PLACE ─────────────────────────
  // Because there are two items that have to answer them. The filter field
  // is a real TextInput sitting in front of the grid, and a TextInput eats
  // Left and Right to walk its own caret — so the moment anything was typed
  // the grid stopped answering the arrows, and the caret crawled instead
  // through text nobody was editing. Forwarding to the panel did not save
  // it: the panel's handlers are attached to the panel, and the field
  // forwards to bgRoot, which has none.
  //
  // So the field asks this FIRST, before the TextInput itself sees the key.
  // Returns whether the key was one of ours.
  function gridKey(event) {
    if (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) {
      event.accepted = true;
      const page = cols() * (popup.appMode === "emoji" ? 7 : 6);
      popup.moveSel(event.key === Qt.Key_PageUp ? -page : page);
      return true;
    }
    if (event.key === Qt.Key_Up) {
      event.accepted = true; popup.moveVert(-1); return true;
    }
    if (event.key === Qt.Key_Down) {
      event.accepted = true; popup.moveVert(1); return true;
    }
    if (event.key === Qt.Key_Left) {
      event.accepted = true;
      if (popup.formatMode) popup.formatSel = (popup.formatSel + 2) % 3;
      else popup.moveHoriz(-1);
      return true;
    }
    if (event.key === Qt.Key_Right) {
      event.accepted = true;
      if (popup.formatMode) popup.formatSel = (popup.formatSel + 1) % 3;
      else popup.moveHoriz(1);
      return true;
    }
    // Home and End walk the caret to the ends of the field for the same
    // reason, and the grid has ends of its own worth going to.
    // Set outright: moveSel wraps modulo the length, so a step of the whole
    // length landed exactly where it started.
    if (event.key === Qt.Key_Home) {
      event.accepted = true; popup.jumpSel(0); return true;
    }
    if (event.key === Qt.Key_End) {
      event.accepted = true; popup.jumpSel(popup.filtered.length - 1); return true;
    }
    return false;
  }

  function currentRow() {
    return popup.filtered[popup.sel] || null;
  }

  function activateCurrent(copyOnly) {
    const e = currentRow();
    if (!e) return;
    if (popup.appMode === "emoji") {
      if (copyOnly) popup.copyText(e.char);
      else popup.copyPaste(e.char);
    } else {
      if (copyOnly) { popup.copyText(e.char, "icon"); return; }
      popup.formatMode = true;
      popup.formatSel = 0;
    }
  }

  // clipboard always; keystrokes land in whatever held focus before us
  function copyPaste(ch) {
    popup.closePopup();
    popup.detach("sleep 0.25 && printf '%s' " + Strings.shellQuote(ch) +
      " | wl-copy >/dev/null 2>&1 && sleep 0.15 && wtype " + Strings.shellQuote(ch));
  }

  // grid clicks copy only — typing is a keyboard decision

  function moveSel(delta) {
    const len = popup.filtered.length;
    if (len === 0) return;
    popup.sel = Nav.wrap(popup.sel, delta, len);
    Qt.callLater(() => grid.positionViewAtIndex(popup.sel, ListView.Contain));
  }

  function jumpSel(i) {
    const len = popup.filtered.length;
    if (len === 0) return;
    popup.sel = Math.max(0, Math.min(len - 1, i));
    Qt.callLater(() => grid.positionViewAtIndex(popup.sel, ListView.Contain));
  }

  function moveVert(delta) {
    const c = cols();
    moveSel(delta * c);
  }

  function moveHoriz(delta) {
    moveSel(delta);
  }

  // ---------------------------------------------------------- hints --

  function hints() {
    if (popup.formatMode)
      return [["left/right", "choose"], ["return", "copy"], ["esc", "back"]];
    if (popup.appMode === "emoji")
      return [["return", "copy · paste"], ["esc", "clear · close"],
              ["tab", "nerd"]];
    return [["return", "pick format"], ["esc", "clear · close"],
            ["tab", "emoji"]];
  }

  // ── THE KEYS, DRAWN AS KEYS ──────────────────────────────────────────
  // They were a run of rich text with the key in bold and the word after it
  // in gray — which asks the reader to find where one hint ends and the next
  // begins from weight alone. A chip says "this is a key you press" the way
  // the rest of this desktop says it, and a chip with its word beside it is
  // one object rather than two runs that happen to be adjacent.
  //
  // The recipe is terminus' KeyChip, which is an inline component of that
  // file and so cannot be imported.



  // ----------------------------------------------------------- keys --

  // ---------------------------------------------------------- panel --

  MouseArea {
    anchors.fill: parent
    z: 0
    onClicked: popup.closePopup()
  }

  LayerPanel {
    id: panel
    host: popup
    ground: bgRoot
    width: Math.round(popup.liveWidth)
    height: popup.calcHeight()

    // ClippingRectangle, not Rectangle + clip: true. Qt's own clip is
    // RECTANGULAR — it clips to the bounding box and knows nothing about the
    // radius — so every square child painted to the panel's edge (the bottom
    // strip most visibly) filled in the rounded corners behind it. This one
    // clips to the rounded shape itself.

    ClippingRectangle {
      id: bgRoot
      anchors.fill: parent
      // Grown by its own border: a ClippingRectangle insets its children by
      // border.width on every side, so the content box came out 2px smaller
      // than the panel and any layout measured against the panel's size fell
      // one row or one column short. This hands the content its full box back.
      anchors.margins: -bgRoot.border.width
      color: popup.bgColor
      radius: Zenon.pillRadius
      topLeftRadius: Zenon.pillRadius
      topRightRadius: Zenon.pillRadius
      bottomLeftRadius: Zenon.pillRadius
      bottomRightRadius: Zenon.pillRadius
      border.color: Zenon.border
      border.width: 1
      focus: true

      // matches scrolled off the top carry on under the search line,
      // frosted — see morpheus/ScrollEdge. Before the column, so the line
      // draws over it; nothing to go under while the line is folded away.
      ScrollEdge {
        view: grid
        x: grid.parent.x + grid.x
        width: grid.width
        height: grid.parent.y + grid.y
      }

      // and the ones still to come show through the strip at the bottom
      ScrollEdge {
        id: msgEdge
        view: grid
        below: true
        x: grid.parent.x + grid.x
        y: grid.parent.y + grid.y + grid.height
        width: grid.width
        height: msgStrip.height
      }

      Column {
        anchors.fill: parent

        // ----------------------------------------------- input bar --
        Item {
          id: inputBar
          width: parent.width
          height: popup.query.length > 0 ? 50 : 0
          Behavior on height { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
          clip: true

          Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Zenon.border
          }

          Row {
            anchors.fill: parent
            visible: inputBar.height > 2
            leftPadding: 16
            spacing: 12

            Rectangle {
              width: modeLabel.width + 16
              height: parent.height
              color: "transparent"

              Text {
                id: modeLabel
                anchors.centerIn: parent
                text: popup.appMode === "emoji" ? "EMOJI" : "NERD"
                color: popup.headColor
                font.family: Zenon.face
                font.weight: 700
                font.pixelSize: Zenon.px(13)
              }
            }

            Item {
              width: parent.width - modeLabel.width - 60
              height: parent.height

              TextInput {
                id: filterInput
                anchors.fill: parent
                verticalAlignment: TextInput.AlignVCenter
                color: popup.entryColor
                selectionColor: popup.errColor
                selectedTextColor: Zenon.onAccent
                font.family: Zenon.face
                font.weight: 500
                font.pixelSize: Zenon.px(17)
                cursorVisible: activeFocus
                cursorDelegate: Item {}
                clip: true
                Keys.forwardTo: bgRoot

                Keys.priority: Keys.BeforeItem
                Keys.onPressed: (event) => {
                  // the grid's keys first, or the caret takes the arrows
                  if (popup.gridKey(event)) return;
                  if (event.key === Qt.Key_Backspace && popup.formatMode) {
                    event.accepted = true;
                    popup.formatMode = false;
                    popup.syncFocus();
                  } else if (event.key === Qt.Key_Tab) {
                    event.accepted = true;
                    popup.toggleMode();
                  }
                }

                Rectangle {
                  id: pulseCursor
                  anchors.left: parent.left
                  anchors.leftMargin: Math.min(filterInput.contentWidth + 2,
                                               filterInput.width - 5)
                  anchors.verticalCenter: parent.verticalCenter
                  width: 3
                  height: 22
                  radius: 1
                  color: popup.entryColor
                  opacity: 0.25
                  visible: filterInput.activeFocus
                  SequentialAnimation on opacity {
                    running: filterInput.activeFocus
                    loops: Animation.Infinite
                    NumberAnimation { to: 1; duration: Zenon.breath; easing.type: Zenon.breathEase }
                    NumberAnimation { to: 0.25; duration: Zenon.breath; easing.type: Zenon.breathEase }
                  }
                }

                onTextChanged: {
                  popup.query = filterInput.text;
                  popup.sel = 0;
                  popup.applyFilter();
                }
              }
            }
          }
        }

        // ---------------------------------------------------- grid --
        Item {
          width: parent.width
          height: popup.gridHeight()

          Text {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: -popup.previewW / 2
            visible: popup.shown && popup.filtered.length === 0 &&
                     !popup.nerdPending
            text: popup.nerdFailed && popup.appMode === "nerd"
              ? "Failed to fetch icons from nerdfonts.com"
              : popup.query !== "" ? "Nothing matches \u201C" + popup.query + "\u201D" : "Nothing here"
            color: popup.nerdFailed && popup.appMode === "nerd"
              ? popup.errColor : popup.dimColor
            font.family: Zenon.face
            font.weight: 600
            font.pixelSize: Zenon.px(15)
          }

          // the nerd set is fetched from nerdfonts.com, which is sometimes
          // slow: dots, not an empty grid, until it lands
          Working {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: -popup.previewW / 2
            running: popup.shown && popup.nerdPending
            dot: 6
            gap: 6
          }

          // How far down the set goes, and something to drag: the picasso
          // picker's bar, over the right edge, for emoji and nerd icons
          // alike (one grid shows both). z over the grid, which is declared
          // after it; it takes presses only while the grid overflows.
          Scrollbar {
            flick: grid
            on: grid.visible
            z: 1
            anchors.right: parent.right
            anchors.rightMargin: popup.previewW
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: 4
            anchors.bottomMargin: 4
            // one row per notch over the bar
            wheelStep: popup.appMode === "emoji" ? 46 : 50
          }

          GridView {
            id: grid
            // Finder's rubber band and the smooth wheel notch, one rule for
            // the whole shell — see morpheus/Elastic.qml. Inside the view
            // rather than over it: it pins itself to the viewport.
            ElasticScroll { view: grid }
            // the chosen one slides (morpheus/CursorBand), rather than each row lighting
            CursorBand { follows: grid; index: popup.sel; insetX: 2; insetY: 2; radius: 6 }
            // CENTERED AT ITS OWN WIDTH, not filling the pane. The panel is a
            // whole number of cells wide except when the footer's floor is
            // holding it open, and then the leftover belongs on both sides
            // of the pictures rather than all of it on the right.
            width: popup.colsUsed * popup.cellW
            x: Math.round((parent.width - popup.previewW - grid.width) / 2)
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            clip: true
            flow: GridView.FlowLeftToRight
            cellWidth: popup.cellW
            cellHeight: popup.appMode === "emoji" ? 46 : 50
            model: popup.filtered
            highlightMoveDuration: 120

            delegate: Item {
              required property var modelData
              required property int index
              width: grid.cellWidth
              height: grid.cellHeight

              Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: Zenon.windowRadius
                color: "transparent"
              }

              Text {
                anchors.centerIn: parent
                text: modelData.char
                color: popup.fgColor
                font.family: popup.appMode === "emoji"
                  ? "Noto Color Emoji" : "Symbols Nerd Font"
                font.pixelSize: Zenon.px(popup.appMode === "emoji" ? 28 : 30)
              }

              MouseArea {
                anchors.fill: parent
                onClicked: {
                  popup.sel = index;
                  popup.activateCurrent(true);
                }
              }
            }
          }

          NerdPreview {
            id: nerdPreview
            visible: popup.previewW > 0
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: popup.previewW
            // read off sel and filtered, which a call to currentRow() would hide
            entry: popup.appMode === "nerd" ? (popup.filtered[popup.sel] || null) : null
            ink: popup.entryColor
          }
        }

        // -------------------------------------------- message strip --
        // morpheus/HintBar, as every strip: the count before the keys, and
        // while a format is being chosen the chooser over the whole strip
        HintBar {
          id: msgStrip
          width: parent.width
          rows: popup.formatMode ? [] : popup.hints()
          leading: Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: !popup.formatMode && !(popup.nerdPending && popup.copiedNote === "")
            text: {
              if (popup.copiedNote !== "") return popup.copiedNote;
              if (popup.appMode === "nerd")
                return popup.filtered.length + " Icons";
              return popup.filtered.length + " Emojis";
            }
            // muted, as the picasso picker's count is: a fact about the
            // grid you are already looking at
            color: Zenon.muted
            font.bold: true
            font.family: Zenon.face
            font.weight: 600
            font.pixelSize: Zenon.px(15)
          }
          overlay: Row {
            id: formatRow
            width: parent.width
            height: parent.height
            visible: popup.formatMode

            Repeater {
              model: ["Icon", "Class", "UTF"]

              delegate: Item {
                required property var modelData
                required property int index
                width: formatRow.width / 3
                height: formatRow.height

                Rectangle {
                  anchors.fill: parent
                  color: popup.formatSel === index
                    ? Zenon.menuHi : "transparent"
                }

                Text {
                  anchors.centerIn: parent
                  text: modelData
                  color: popup.formatSel === index
                    ? popup.entryColor : popup.dimColor
                  font.bold: popup.formatSel === index
                  font.family: Zenon.face
                  font.pixelSize: Zenon.px(14)
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    popup.formatSel = index;
                    popup.copyFormat();
                  }
                }
              }
            }
          }
        }
      }
    }

      Keys.onEscapePressed: (event) => {
      event.accepted = true;
      if (popup.formatMode) {
        popup.formatMode = false;
        popup.syncFocus();
      } else if (filterInput.text !== "") {
        filterInput.text = "";
      } else {
        popup.closePopup();
      }
    }

    Keys.onPressed: (event) => {
      if (event.key === Qt.Key_Tab) {
        event.accepted = true;
        popup.toggleMode();
        return;
      }

      if (popup.gridKey(event)) return;

      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        event.accepted = true;
        if (popup.formatMode) {
          popup.copyFormat();
          return;
        }
        if (event.modifiers & Qt.ShiftModifier) return;   // reserved
        popup.activateCurrent(false);
        return;
      }
      if (event.key === Qt.Key_Backspace && popup.formatMode) {
        event.accepted = true;
        popup.formatMode = false;
        return;
      }

    }
  }

  // -------------------------------------------------------- helpers --

  function gridHeight() {
    const maxRows = popup.appMode === "emoji" ? 7 : 6;
    const rowH = popup.appMode === "emoji" ? 46 : 50;
    // Nothing loaded yet is not the same as nothing to show. Measured as one
    // row, the pill morphed to a 100px sliver and then snapped to full height
    // the instant the set landed; reserving the full grid means it opens once,
    // at the size it is going to keep.
    if (popup.entries.length === 0) return maxRows * rowH;
    const rows = Math.ceil(popup.filtered.length / cols());
    const h = Math.max(1, Math.min(rows, maxRows)) * rowH;
    // A filter down to a row or two would squash the nerd preview beside
    // it; the grid is held open to what the pane needs while it has a glyph.
    return popup.previewW > 0 && popup.filtered.length > 0
      ? Math.max(h, nerdPreview.needH) : h;
  }

  function calcHeight() {
    return (popup.query.length > 0 ? 50 : 0) +
      popup.gridHeight() + Zenon.hintBarH;
  }

  FocusRetry {
    id: focusRetry
    live: popup.shown
    took: filterInput.activeFocus
    onPlace: popup.syncFocus()
  }
}

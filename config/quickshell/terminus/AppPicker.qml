// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// APPPICKER — "open with": the applications that already claim a file's
// type, above everything installed, one cursor over both, type to narrow.
//
//     Sheet { cardH: picker.implicitHeight
//       AppPicker { id: picker; width: parent.width
//                   handlers: …; defaultId: …; mime: …
//                   onChosen: (app, mime, paths, openFiles) => … } }
//
// The card body of terminus' open-with sheet, lifted out of TerminusWindow so
// artemis can raise the very same card over itself when it is asked to open a
// file nothing handles. The CARD is the host's (a Sheet, wherever it hangs);
// this is what goes in it, and the keys.
//
// WHAT IT DOES NOT DO is act. Choosing an application emits `chosen`, and
// striking one out emits `removeRequested`: what running something means is
// the host's — terminus queues it as an action and rescans, artemis runs it
// and closes. The scan that fills `handlers`, `defaultId` and `mime` is the
// host's too (Terminus.appsCommand), because terminus' right-click menu reads
// the same answer and must not ask for it twice.

import QtQuick
import Quickshell
import "../morpheus"
import "terminus.js" as Terminus
import "../morpheus/icons.js" as Icons

Item {
  id: picker
  implicitHeight: appCol.implicitHeight

  // the window the cursor bar belongs to — see SelectBar.host. May be null.
  property var host: null
  // ElasticScroll's step; 0 is its own default
  property real wheelStep: 0

  // ── WHAT THE HOST'S SCAN SAID ─────────────────────────────────────────
  // The handlers already registered for the type ({id, name, file} rows, as
  // Terminus.parseApps gives them), which of them is the default, and the
  // type itself — read live, because the card is usually up before the scan
  // has answered.
  property var handlers: []
  property string defaultId: ""
  property string mime: ""

  property bool open: false
  // EVERYTHING IT WILL OPEN. `path` is the first of them, because the type
  // being adopted has to be one type and that is the one the scan asked about.
  property var paths: []
  property string path: ""
  // whether choosing opens the files as well as adopting the type — terminus'
  // properties card only registers
  property bool openFiles: true
  property int pick: 0

  // app, the type it is adopted for ("" when nothing could name the type),
  // the files, and whether to open them
  signal chosen(var app, string mime, var paths, bool openFiles)
  signal removeRequested(string id)
  // something worth a status line
  signal notice(string text)
  // closed without choosing, or after choosing — either way the keyboard
  // goes back to the host
  signal dismissed()

  // Snapshotted when the card opens rather than read live. It is a few
  // hundred entries, the filter runs over it on every keystroke, and
  // DesktopEntries.applications is a model rather than an array — walking
  // it per keystroke is work that answers the same thing every time.
  property var installed: []

  // THE APP'S OWN GLYPH leads every row, as in icarus' list. The column is
  // kept for one the map does not know, so the names stay in one line.
  readonly property int glyphW: 18
  readonly property int glyphGap: 10

  // ── TYPE AND IT NARROWS ─────────────────────────────────────────────
  // No field, the way the send picker has none: the card has the keyboard
  // and there is nothing else in it a letter could mean, so a letter
  // filters. A box drawn around that only said "this takes typing", which
  // the caret and the footer say without spending a row on it.
  property string query: ""

  readonly property var hits:
    Terminus.filterApps(picker.installed, picker.query)

  // ── ONE CURSOR OVER TWO LISTS ───────────────────────────────────────
  // The card shows the handlers this type already has above the several
  // hundred applications it could have, and `pick` walks both as though
  // they were one column: 0 .. handlerCount-1 is the summary at the top,
  // everything after it indexes `hits`. Otherwise the arrows could only
  // ever reach the lower half and the rows at the top were pointer-only.
  //
  // handlerCount follows the section's own visibility — it collapses to 0
  // the moment a filter is typed, which is also when the section is hidden,
  // so the cursor never points at a row that is not on screen.
  readonly property int handlerCount:
    picker.query === "" ? picker.handlers.length : 0
  readonly property bool onHandler: picker.pick < picker.handlerCount
  readonly property int hitIndex: picker.pick - picker.handlerCount

  // Back to the top on every keystroke: the ranking has changed underneath
  // the cursor, so where it was means nothing.
  onQueryChanged: {
    picker.pick = 0;
    appList.positionViewAtBeginning();
  }

  Keys.onPressed: (event) => {
    event.accepted = true;
    if (event.key === Qt.Key_Escape) {
      // Escape clears the filter before it closes the card: a narrowed
      // list is a state you can be in by accident.
      if (picker.query !== "") { picker.query = ""; return; }
      picker.dismiss(); return;
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      picker.accept(); return;
    }
    if (event.key === Qt.Key_Down) { picker.step(1); return; }
    if (event.key === Qt.Key_Up) { picker.step(-1); return; }
    // Delete takes a handler away, which is the key terminus already means
    // "remove" by everywhere else. It acts on the row under the cursor in
    // the list below rather than on the summary at the top: every handler
    // appears in the list anyway — so "firefox", Delete, done, without
    // reaching for the pointer.
    if (event.key === Qt.Key_Delete) { picker.strike(); return; }
    if (event.key === Qt.Key_Backspace) {
      picker.query = picker.query.slice(0, -1); return;
    }
    if (event.key !== Qt.Key_Tab && event.text
        && event.text.length === 1 && event.text >= " ") {
      picker.query += event.text;
    }
  }

  // Only a registered handler can be removed; anything else in this list
  // is simply an application that has never claimed the type, and saying
  // so is better than a key that silently does nothing.
  function strike() {
    if (picker.onHandler) {
      const h = picker.handlers[picker.pick];
      if (h) picker.removeRequested(h.id);
      return;
    }
    const a = picker.hits[picker.hitIndex];
    if (!a) return;
    let handled = false;
    for (const h of picker.handlers) if (h.id === a.id) handled = true;
    if (!handled) {
      picker.notice((a.name || a.id) + " does not handle this type");
      return;
    }
    picker.removeRequested(a.id);
  }

  function snapshot() {
    const vals = DesktopEntries.applications.values;
    const out = [];
    for (let i = 0; i < vals.length; ++i) {
      const e = vals[i];
      if (!e) continue;
      const nm = String(e.name || "").trim();
      const id = String(e.id || "").trim();
      // An entry with no name is a row you cannot read and one with no id
      // is a row that cannot be launched OR registered — neither belongs
      // in a list whose only job is to be chosen from.
      if (nm === "" || id === "") continue;
      // the app's own glyph, from the map icarus and the launcher read
      out.push({ name: nm, id: id,
                 glyph: Icons.appGlyph([id, String(e.execString || ""), nm]) });
    }
    // By name, once, here — filterApps breaks every tie by the order it
    // was handed, so this is the order the unfiltered list appears in and
    // the order equally good matches keep.
    out.sort((a, b) => {
      const x = a.name.toLowerCase(), y = b.name.toLowerCase();
      return x < y ? -1 : (x > y ? 1 : 0);
    });
    return out;
  }

  function ask(paths, openFiles) {
    const list = (paths && paths.length !== undefined)
      ? paths : [String(paths || "")];
    picker.paths = list;
    picker.path = list.length > 0 ? list[0] : "";
    picker.openFiles = openFiles !== false;
    picker.installed = picker.snapshot();
    picker.pick = 0;
    picker.query = "";
    picker.open = true;
    // the card is still invisible on the frame that opens it, and an
    // invisible item refuses active focus without saying so
    appClaim.tries = 0;
    appClaim.restart();
  }

  Timer {
    id: appClaim
    interval: 30
    repeat: true
    property int tries: 0
    onTriggered: {
      if (!picker.open || appClaim.tries++ > 20) { appClaim.stop(); return; }
      if (picker.activeFocus) { appClaim.stop(); return; }
      picker.forceActiveFocus();
    }
  }

  function step(d) {
    const n = picker.handlerCount + picker.hits.length;
    if (n === 0) return;
    picker.pick = (picker.pick + d + n) % n;
    if (!picker.onHandler)
      appList.positionViewAtIndex(picker.hitIndex, ListView.Contain);
  }

  function accept() {
    // A handler is already registered, so choosing one is simply opening
    // with it — the same thing the row below would do, minus the adopting.
    if (picker.onHandler) {
      const h = picker.handlers[picker.pick];
      if (h) picker.choose(h);
      return;
    }
    const a = picker.hits[picker.hitIndex];
    if (!a) return;
    picker.choose(a);
  }

  property var pendingApp: null

  RowFlash { id: appFlash; onDone: () => picker.launch() }

  function choose(app) {
    // The flash lives on the lower list's rows; from the summary above it
    // there is nothing to flash, so the launch goes straight through.
    if (picker.onHandler) { picker.pendingApp = app; picker.launch(); return; }
    if (!appFlash.fire(picker.hitIndex)) return;
    picker.pendingApp = app;
  }

  function launch() {
    const app = picker.pendingApp;
    picker.pendingApp = null;
    if (!app) return;
    // read before the card goes: dismissing hands the keyboard back, and the
    // host may start a rescan that empties the type
    const mime = picker.mime, paths = picker.paths.slice();
    const openFiles = picker.openFiles;
    // true across the dismiss, so a host can tell this one — which a choice
    // follows — from escape or a click away
    picker.launching = true;
    picker.dismiss();
    picker.launching = false;
    picker.chosen(app, mime, paths, openFiles);
  }
  property bool launching: false

  function dismiss() {
    // Harmless when dismiss is called BY the flash: the animation has
    // already finished by the time its own script action runs.
    appFlash.cancel();
    picker.pendingApp = null;
    picker.open = false;
    picker.dismissed();
  }

  // The snapshot is NOT dropped on the way out, and that is deliberate:
  // the card is kept alive through its fade, so emptying the list here
  // would collapse the rows out from under it and the last thing you saw
  // of it would be an empty box. It is replaced wholesale by the next
  // ask(), which is the only place its contents can be stale.

  Column {
    id: appCol
    width: parent.width

    // ── WHAT ALREADY OPENS IT ─────────────────────────────────────────
    // This card asks "choose a program" and used to ask it without ever
    // saying which programs already claim the type — so the one thing
    // you might want to do about a wrong handler, take it away, could
    // only be reached from the properties card.
    //
    // Hidden the moment you start typing: past that point the card is a
    // search result and a second list above it is in the way.
    Column {
      width: parent.width
      visible: picker.handlers.length > 0 && picker.query === ""

      Item { width: 1; height: 10 }

      Text {
        x: 14
        text: "opens with"
        color: Zenon.muted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(12)
      }

      Item { width: 1; height: 4 }

      Repeater {
        model: picker.handlers
        delegate: Item {
          id: handlerRow
          required property var modelData
          required property int index
          width: appCol.width
          height: 30

          readonly property bool isDefault:
            modelData.id === picker.defaultId

          readonly property bool target:
            picker.onHandler && picker.pick === handlerRow.index

          Rectangle {
            anchors.fill: parent
            color: handlerRow.target ? Zenon.border
                 : (handlerHov.hovered ? Zenon.border : "transparent")
          }
          HoverHandler { id: handlerHov }

          Text {
            id: handlerGlyph
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            width: picker.glyphW
            horizontalAlignment: Text.AlignHCenter
            text: Icons.appGlyph([handlerRow.modelData.id, handlerRow.modelData.name || ""])
            color: Zenon.white
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(14)
          }

          Text {
            anchors.left: handlerGlyph.right
            anchors.leftMargin: picker.glyphGap
            anchors.right: handlerDef.visible ? handlerDef.left
                                              : handlerX.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: handlerRow.modelData.name || handlerRow.modelData.id
            color: Zenon.white
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(14)
          }

          KeyCap {
            id: handlerDef
            anchors.right: handlerX.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            visible: handlerRow.isDefault
            label: "default"
          }

          Text {
            id: handlerX
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: ""   // nf-fa-times, as the row menu uses
            color: handlerXHov.hovered ? Zenon.red : Zenon.muted
            font.family: Zenon.faceMono
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(14)

            HoverHandler { id: handlerXHov }
            MouseArea {
              anchors.fill: parent
              anchors.margins: -7
              onClicked: picker.removeRequested(handlerRow.modelData.id)
            }
          }
        }
      }

      // NO RULE OF ITS OWN. The list below already draws one above
      // itself, and two lines with a gap between them read as an empty
      // row rather than as a division.
    }

    // NO FIELD. Typing filters — see the key handler — the way it does in
    // the send picker, so the card opens straight onto the list it is
    // asking you to choose from instead of onto a box.
    //
    // THE RULE ABOVE THE LIST divides it from the handlers, so it is drawn
    // only while they are showing. With none, the list sits straight under
    // the sheet's header, whose own rule is already the division — the
    // second rule here, with the old 12px of padding between the two, read
    // as a double line across the top of every file nothing opens. Same as
    // the bottom: the list ends straight on the footer's rule.
    Rectangle {
      width: parent.width
      height: picker.handlerCount > 0 && picker.hits.length > 0 ? 1 : 0
      color: Zenon.border
    }

    SelectBar {
      host: picker.host
      view: appList
      index: picker.hitIndex
      rowH: 30
      // dark while the cursor is up in the summary — see handlerCount
      on: !picker.onHandler && picker.hits.length > 0
    }

    ListView {
      id: appList
      width: parent.width
      // Ten rows of room, and fewer when there are fewer — the card
      // shrinks around a filter that has narrowed to two.
      height: Math.min(picker.hits.length, 10) * 30
      model: picker.hits
      clip: true
      reuseItems: true
      boundsBehavior: Flickable.DragAndOvershootBounds
      boundsMovement: Flickable.FollowBoundsBehavior
      ElasticScroll { view: appList; step: picker.wheelStep }

      delegate: Item {
        id: appRow
        required property var modelData
        required property int index
        width: appList.width
        height: 30

        readonly property bool target:
          !picker.onHandler && index === picker.hitIndex

        // Which of these several hundred already claim the type. The
        // name carries it rather than a chip: the right-hand column is
        // the id, and a badge between the two would crowd a row that is
        // mostly name already.
        readonly property bool handler: {
          for (const h of picker.handlers)
            if (h.id === appRow.modelData.id) return true;
          return false;
        }

        // NO HOVER, AND NO TINT — the rule every other sheet follows. The
        // pointer moving the cursor is a second thing driving the selection
        // while the arrows are driving it too. A click still picks, because
        // a click is a decision.
        FlashOver { flash: appFlash; index: appRow.index }

        Text {
          id: appGlyph
          anchors.left: parent.left
          anchors.leftMargin: 14
          anchors.verticalCenter: parent.verticalCenter
          width: picker.glyphW
          horizontalAlignment: Text.AlignHCenter
          text: appRow.modelData.glyph || ""
          color: appRow.handler ? Zenon.cyan
               : (appRow.target ? Zenon.white : Zenon.keyInk)
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(16)
        }

        Text {
          id: appName
          anchors.left: appGlyph.right
          anchors.leftMargin: picker.glyphGap
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, appRow.width - 14 - picker.glyphW - picker.glyphGap - 14)
          text: modelData.name
          elide: Text.ElideRight
          color: appRow.handler ? Zenon.cyan
               : (appRow.target ? Zenon.white : Zenon.keyInk)
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(16)
        }

        // The id, dimmed, because two entries can call themselves the
        // same thing and the id is what tells them apart — and it is
        // what you typed if you typed "evince".
        Text {
          anchors.left: appName.right
          anchors.leftMargin: 10
          anchors.right: parent.right
          anchors.rightMargin: 14
          anchors.verticalCenter: parent.verticalCenter
          text: modelData.id
          elide: Text.ElideMiddle
          horizontalAlignment: Text.AlignRight
          color: Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }

        MouseArea {
          anchors.fill: parent
          onClicked: picker.choose(modelData)
        }
      }
    }

    // "nothing matches" is not a hint — it is the answer to what you just
    // typed, and without it a filter that matches nothing is
    // indistinguishable from a card that has stopped working.
    Item {
      width: parent.width
      height: picker.hits.length === 0 ? 30 : 0
      visible: height > 0

      Text {
        anchors.left: parent.left
        anchors.leftMargin: 43
        anchors.verticalCenter: parent.verticalCenter
        text: "nothing matches"
        color: Zenon.muted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(16)
      }
    }

    Rectangle {
      width: parent.width
      height: 1
      color: Zenon.border
    }

    // ── THE HINT IS THE FIELD ──────────────────────────────────────────
    // The send picker's footer, verbatim in shape: what you typed on the
    // left where the instruction was, and the keys as chips on the right.
    Item {
      width: parent.width
      height: 34

      Row {
        anchors.centerIn: parent
        spacing: 12

        Text {
          anchors.verticalCenter: parent.verticalCenter
          rightPadding: 2
          text: picker.query !== "" ? picker.query : "type to filter"
          color: picker.query !== "" ? Zenon.sand : Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }

        Repeater {
          model: [["↑↓", "move"], ["↵", "open"],
                  ["del", "remove"], ["esc", "close"]]

          delegate: Row {
            id: appHintPair
            required property var modelData
            spacing: 5

            KeyCap {
              anchors.verticalCenter: parent.verticalCenter
              label: appHintPair.modelData[0]
              fontSize: 11
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: appHintPair.modelData[1]
              color: Zenon.muted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(13)
            }
          }
        }
      }
    }
  }
}

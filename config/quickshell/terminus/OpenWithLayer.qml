// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// OPENWITHLAYER — terminus' open-with card, floating, for a surface that is
// not terminus: the scan, the card, and what choosing runs, in one piece.
//
//     OpenWithLayer { anchors.fill: parent; z: 50; dim: panel
//                     onOpened: …close the finder…; onCancelled: …refocus… }
//     …
//     if (code === Terminus.NO_HANDLER) layer.ask(path)
//
// For a file nothing opens (Terminus.openOrAskCommand's exit 3). Artemis
// raises it over itself, on its own surface; icarus, whose menus are gone by
// the time the open has failed, puts it in a window of its own. Terminus
// itself does not use this: its card hangs in its own Sheet and shares the
// scan with its right-click menu — but the card is the same AppPicker.
//
// Choosing registers the application against the file's type and opens the
// file (Terminus.adoptAppCommand), so every one of them opens that kind of
// file with it from then on.
//
// THE TYPE is terminus' (Terminus.typeScript): an empty file is typed by its
// name, never as application/x-zerosize — choosing plato for an empty `todo`
// registers text/plain, not "every empty file", and an empty .psd stays a
// Photoshop image.

import QtQuick
import Quickshell
import Quickshell.Io
import "../morpheus"
import "../morpheus/icons.js" as Icons
import "terminus.js" as Terminus

Item {
  id: layer
  anchors.fill: parent
  visible: layer.active

  // An item to darken, in its own shape, while the card is up — the thing the
  // card was raised over. Null darkens nothing.
  property Item dim: null
  property real dimRadius: Zenon.pillRadius

  readonly property bool open: picker.open
  // up, or still fading out
  readonly property bool active: picker.open || sheet.cardInk > 0.01

  // an application was chosen and the file handed to it
  signal opened()
  // put away without choosing
  signal cancelled()

  function ask(path) {
    const name = Terminus.basename(path);
    sheet.title = name;
    sheet.glyph = Icons.glyphFor({ name: name, isDir: false });
    layer.scan(path);
    picker.ask([path], true);
  }

  // Gone at once and without a word — for a host that is closing anyway, and
  // has nowhere to hand the keyboard back to.
  function close() {
    layer.quiet = true;
    picker.dismiss();
    layer.quiet = false;
  }
  property bool quiet: false

  // ── WHAT CLAIMS THE TYPE ──────────────────────────────────────────────
  // terminus' own scan, for the card's "opens with" list and for the type a
  // choice is registered against.
  property var apps: []
  property string mime: ""
  property string defaultId: ""

  Process {
    id: appsProc
    stdout: StdioCollector {
      id: appsOut
      waitForEnd: true
      onStreamFinished: {
        layer.apps = Terminus.parseApps(appsOut.text);
        layer.mime = Terminus.parseAppsMime(appsOut.text);
        layer.defaultId = Terminus.parseAppsDefault(appsOut.text);
      }
    }
  }

  function scan(path) {
    layer.apps = [];
    layer.mime = "";
    layer.defaultId = "";
    appsProc.running = false;
    appsProc.command = ["sh", "-c", Terminus.appsCommand(path)];
    appsProc.running = true;
  }

  // Only a handler the scan listed can be struck, and a type with one did not
  // get here (gio opens with it) — but the card offers the key, so it works:
  // the association goes, and the list is asked again.
  Process {
    id: assocProc
    onExited: if (picker.open) layer.scan(picker.path)
  }

  Rectangle {
    visible: !!layer.dim
    x: layer.dim ? layer.dim.x : 0
    y: layer.dim ? layer.dim.y : 0
    width: layer.dim ? layer.dim.width : 0
    height: layer.dim ? layer.dim.height : 0
    radius: layer.dimRadius
    color: Qt.rgba(0, 0, 0, 0.55)
    opacity: sheet.cardInk
  }

  InputShield { onClicked: picker.dismiss() }

  Sheet {
    id: sheet
    floating: true
    shown: picker.open
    cardW: 560
    cardH: picker.implicitHeight

    AppPicker {
      id: picker
      width: parent.width
      handlers: layer.apps
      defaultId: layer.defaultId
      mime: layer.mime
      onChosen: (app, mime, paths, openFiles) => {
        Quickshell.execDetached(["sh", "-c",
          Terminus.adoptAppCommand(app.id, mime, paths[0])]);
        layer.opened();
      }
      onRemoveRequested: (id) => {
        if (!id || layer.mime === "") return;
        assocProc.command = ["sh", "-c", Terminus.removeAppCommand(id, layer.mime)];
        assocProc.running = true;
      }
      // chosen() follows a dismiss too, so only a dismiss with nothing
      // pending is a cancel — see AppPicker.launch
      onDismissed: if (!layer.quiet && !picker.launching) layer.cancelled()
    }
  }
}

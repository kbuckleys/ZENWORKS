// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Terminus' taking the keyboard … logic, out of TerminusWindow.qml
// (2026-10-08). The state stays on the window (term); the window keeps a
// one-line forwarder for each function here, so callers are unchanged.

import QtQuick
import QtQuick.Shapes
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick.Effects
import QtMultimedia
import Qt.labs.folderlistmodel
import "../morpheus"
import "../picasso"
import "../oracle"
import "terminus.js" as Terminus
import "../morpheus/icons.js" as Icons
import "../morpheus/thumbs.js" as Thumbs
import "tags.js" as Tags
import "collections.js" as Coll

Item {
  id: portal
  property var term: null
  readonly property alias focusClaim: focusClaim

  // forceActiveFocus() on the frame `visible` is set does nothing: the surface
  // has not been mapped yet, so there is no window for the focus to be active
  // IN, and the call is silently dropped. Every caller here used to make it
  // anyway, which is why the window opened and then ignored every key — the
  // compositor had focused it and Qt had no focus item inside it.
  //
  // So it asks until it has it, the same way cerberus does, and stops the
  // moment it does. Twelve tries at 60ms is well past the point a surface that
  // is going to map has mapped.
  Timer {
    id: focusClaim
    interval: 60
    repeat: true
    property int tries: 0
    // A save dialog wants the NAME FIELD, not the listing — you are there to
    // type a filename. Asked each tick rather than latched at restart, because
    // `portal` is assigned in the same breath as `shown`.
    // THE LISTING, even for a save.
    //
    // It used to be the name field, on the reasoning that you are here to type
    // a filename — but the name is already filled in, and WHERE it goes is the
    // question you actually have to answer. With the keyboard in the field,
    // Return wrote the file wherever the dialog happened to open. With it in
    // the listing, the arrows and the letters do what they do everywhere else
    // in this window and the field is one Tab away when you want it.
    readonly property Item want: term.contentRef
    onRunningChanged: if (running) tries = 0
    onTriggered: {
      if (!term.shown || focusClaim.want.activeFocus || focusClaim.tries++ > 12) {
        focusClaim.stop();
        return;
      }
      focusClaim.want.forceActiveFocus();
    }
  }
  // WHERE YOU LAST SAVED SOMETHING.
  //
  // A save request arrives with a directory the ASKING PROGRAM chose, which is
  // its own download directory or whatever it had open — almost never where you
  // keep things. Landing there and putting the keyboard in the name field
  // meant the obvious gesture, type a name and press Return, wrote the file
  // into the application's idea of a good place; sorting it out afterwards was
  // a cut and a paste in a file manager, which is the thing this dialog was
  // supposed to save you.
  //
  // Where YOU last saved is a far better guess than where the program suggests,
  // and it survives a restart because the habit does. The VALUE lives on the
  // manager — see lastSaveDir there — because a dialog does not outlive its
  // own answer. This is only the door to the preferences file.
  function persistPrefs() { term.viewSaveRef.restart(); }
  function portalAnswer(paths) {
    if (!term.portal) return;
    const saving = term.portal.save;
    // Recorded on the way out rather than on every step, so cancelling a
    // dialog does not teach it anything.
    if (term.portal.save && paths.length > 0 && term.mgr)
      term.mgr.noteSaveDir(Terminus.dirname(paths[0]));
    const out = term.portal.out;
    // an in-shell caller's answer — see TerminusManager.choose
    const reply = term.portal.reply;
    term.portal = null;
    if (reply) reply(paths);
    if (term.mgr) {
      // `saving` captured before portal was cleared — see answerPortal for
      // why a save has to bring its file into existence.
      term.mgr.answerPortal(out, paths, saving);
      // a dedicated dialog is done existing, not merely hidden
      if (term.mgr.pickerWin === term) { term.mgr.retirePicker(); return; }
    }
    term.shown = false;
  }
  function portalConfirm() {
    const c = term.portalChoice;
    if (c.length === 0) return;
    term.portalAnswer(c);
  }
  function portalCancel() { term.portalAnswer([]); }
}

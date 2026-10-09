// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Its own file since 2026-10-08, out of TerminusWindow.qml (the split).
// `term` is the terminus window; window items it uses are read as
// term.<id>Ref (the window's aliases).

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
  id: dialogKeys
  // the terminus window (`term`, never `root` — see terminus-split notes)
  property var term: null
  anchors.fill: parent
  z: 20
  readonly property bool anyOpen:
    term.confirmRef.open || term.propsRef.open || prefs.open || sendTo.open
    || cmdPalette.open || marks.open || disks.open || tagPick.open
    || term.plugRef.open || diskInfo.open
    || term.looking
  enabled: dialogKeys.anyOpen

  onAnyOpenChanged: {
    if (dialogKeys.anyOpen) { dialogClaim.tries = 0; dialogClaim.restart(); }
    else term.contentRef.forceActiveFocus();
  }

  Timer {
    id: dialogClaim
    interval: 30
    repeat: true
    property int tries: 0
    onTriggered: {
      if (!dialogKeys.anyOpen || dialogKeys.activeFocus
          || dialogClaim.tries++ > 20) {
        dialogClaim.stop();
        return;
      }
      dialogKeys.forceActiveFocus();
    }
  }

  Keys.onPressed: (event) => {
    event.accepted = true;

    // Before confirm, because choosing a destination can raise the
    // overwrite question on top of this one and the answer belongs to
    // whichever card is in front.
    // Before confirm for the same reason the palette is: a sheet that can
    // raise another question belongs to whichever card is in front.
    // No filter here, so every letter is free — and `m` is the verb the
    // rows are about, which is why it can be a bare letter when the
    // bookmarks sheet beside it has to spend ctrl and delete.
    // The card on top first: a disk's properties opened from the new-disk
    // question answer before it does.
    if (term.diskInfoRef.open && !term.confirmRef.open) {
      if (event.key === Qt.Key_Escape) { term.diskInfoRef.dismiss(); return; }
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        term.diskInfoRef.enter(); return;
      }
      if (event.text === "m" || event.text === "M") { term.diskInfoRef.toggle(); return; }
      return;
    }
    if (term.plugRef.open && !term.confirmRef.open) {
      if (event.key === Qt.Key_Escape) { term.plugRef.dismiss(); return; }
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        term.plugRef.primary(); return;
      }
      if (event.key === Qt.Key_Down || event.text === "j") { term.plugRef.step(1); return; }
      if (event.key === Qt.Key_Up || event.text === "k") { term.plugRef.step(-1); return; }
      if (event.text === "m" || event.text === "M") { term.plugRef.mountOne(term.plugRef.sel); return; }
      if (event.text === "i") { term.plugRef.inspect(term.plugRef.sel); return; }
      return;
    }
    if (term.disks.open && !term.confirmRef.open) {
      if (event.key === Qt.Key_Escape) { term.disks.dismiss(); return; }
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        term.disks.enter(); return;
      }
      if (event.key === Qt.Key_Down || event.text === "j") {
        term.disks.step(1); return;
      }
      if (event.key === Qt.Key_Up || event.text === "k") {
        term.disks.step(-1); return;
      }
      if (event.text === "m" || event.text === "M") {
        term.disks.toggle(); return;
      }
      return;
    }

    if (term.marksRef.open && !term.confirmRef.open) {
      // Escape backs out one step at a time, the palette's rule: the
      // filter first, then the sheet.
      if (event.key === Qt.Key_Escape) {
        if (term.marksRef.query !== "") { term.marksRef.query = ""; return; }
        term.marksRef.dismiss(); return;
      }
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        // SHIFT OPENS IT IN A TAB, the same modifier the listing uses on
        // a directory and the go sheet uses on a destination.
        term.marksRef.go((event.modifiers & Qt.ShiftModifier) !== 0);
        return;
      }
      // Alt first: the bare arrows walk, the held ones carry.
      if (event.modifiers & Qt.AltModifier) {
        if (event.key === Qt.Key_Down) { term.marksRef.shift(1); return; }
        if (event.key === Qt.Key_Up) { term.marksRef.shift(-1); return; }
      }
      if (event.key === Qt.Key_Down) { term.marksRef.step(1); return; }
      if (event.key === Qt.Key_Up) { term.marksRef.step(-1); return; }
      // ctrl a, not a letter — every letter belongs to the filter.
      if ((event.modifiers & Qt.ControlModifier)
          && event.key === Qt.Key_A) {
        term.marksRef.addHere(); return;
      }
      // DELETE, and not a letter. Every letter belongs to the filter now —
      // `d` would have taken a bookmark away in the middle of typing
      // "downloads", which is the one mistake this sheet must not make
      // easy. There is no confirmation and there does not need to be: a
      // bookmark is a pointer, not a file, and b a puts it back.
      if (event.key === Qt.Key_Delete) { term.marksRef.drop(); return; }
      if (event.key === Qt.Key_Backspace) {
        term.marksRef.query = term.marksRef.query.slice(0, -1); return;
      }
      if (event.key !== Qt.Key_Tab && event.text
          && event.text.length === 1 && event.text >= " ") {
        term.marksRef.query += event.text;
      }
      return;
    }

    if (term.tagPickRef.open && !term.confirmRef.open) {
      // The filter first, then the sheet — the palette's rule, which
      // every sheet with a filter in it follows.
      // ── WHILE A NAME IS BEING TYPED, IT TAKES EVERYTHING ──────
      // Before the filter, before Escape-clears-the-query, before the
      // letter keys: the row is an editor and an editor owns its keys.
      if (term.tagPickRef.renaming !== "") {
        if (event.key === Qt.Key_Escape) { term.tagPickRef.cancelRename(); return; }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          term.tagPickRef.commitRename(); return;
        }
        if (event.key === Qt.Key_Backspace) {
          term.tagPickRef.renameText = term.tagPickRef.renameText.slice(0, -1); return;
        }
        if (event.text && event.text.length === 1 && event.text >= " ")
          term.tagPickRef.renameText += event.text;
        return;
      }

      // ── ALT R, AND BEFORE THE LETTER KEYS ─────────────────────
      // Every bare letter belongs to the filter, so the modifier has
      // to be tested first: `event.text` is still "r" with Alt held,
      // and the printable branch below would otherwise swallow it and
      // type an r into the filter instead.
      if ((event.modifiers & Qt.AltModifier) !== 0
          && event.key === Qt.Key_R) {
        term.tagPickRef.beginRename(); return;
      }

      if (event.key === Qt.Key_Escape) {
        if (term.tagPickRef.query !== "") { term.tagPickRef.query = ""; return; }
        term.tagPickRef.dismiss(); return;
      }
      // Return TAGS and leaves the card up. Shift-Return is the one that
      // is finished — tagging comes in runs, but a single tag should not
      // cost an Escape as well.
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        term.tagPickRef.apply();
        if ((event.modifiers & Qt.ShiftModifier) !== 0) term.tagPickRef.dismiss();
        return;
      }
      if (event.key === Qt.Key_Down) { term.tagPickRef.step(1); return; }
      if (event.key === Qt.Key_Up) { term.tagPickRef.step(-1); return; }
      // DELETE, not a letter, for the reason the marks sheet gives: every
      // letter belongs to the filter, and `x` in the middle of typing a
      // tag name must not take a tag off forty files.
      if (event.key === Qt.Key_Delete) { term.tagPickRef.drop(); return; }
      if (event.key === Qt.Key_Backspace) {
        term.tagPickRef.query = term.tagPickRef.query.slice(0, -1); return;
      }
      if (event.key !== Qt.Key_Tab && event.text
          && event.text.length === 1 && event.text >= " ") {
        term.tagPickRef.query += event.text;
      }
      return;
    }

    if (term.cmdPaletteRef.open && !term.confirmRef.open) {
      if (event.key === Qt.Key_Escape) {
        if (term.cmdPaletteRef.query !== "") { term.cmdPaletteRef.query = ""; return; }
        term.cmdPaletteRef.dismiss(); return;
      }
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        term.cmdPaletteRef.run(); return;
      }
      if (event.key === Qt.Key_Down) { term.cmdPaletteRef.step(1); return; }
      if (event.key === Qt.Key_Up) { term.cmdPaletteRef.step(-1); return; }
      if (event.key === Qt.Key_Backspace) {
        term.cmdPaletteRef.query = term.cmdPaletteRef.query.slice(0, -1); return;
      }
      if (event.key !== Qt.Key_Tab && event.text
          && event.text.length === 1 && event.text >= " ") {
        term.cmdPaletteRef.query += event.text;
      }
      return;
    }

    // ── LOOKING ──────────────────────────────────────────────────
    // One key in and one key out, and the arrows walk the listing
    // underneath so a directory of photographs can be flicked through
    // without closing and reopening on each one.
    if (term.looking && !term.confirmRef.open) {
      // THE SECOND KEY OF A CHORD. `y` below starts one, but this item
      // has the keyboard while looking, so the key that finishes it never
      // reached content's handler and `y y` / `y t` did nothing at all.
      // Resolved here the same way content resolves it.
      if (term.contentRef.pending !== "") {
        if (event.key === Qt.Key_Escape) { term.contentRef.done(); return; }
        if (event.text === "") return;
        const list = term.contentRef.sequences[term.contentRef.pending] || [];
        for (const entry of list) {
          if (entry[0] === event.text) { term.contentRef.done(); entry[2](); return; }
        }
        return;
      }
      // ESCAPE AND SPACE LEAVE. The key that opens it closes it, which
      // is now space rather than `i`. Return does NOT: it is the key that
      // means "do the thing", and over a file being looked at the thing is
      // to open it — which is the one verb this overlay existed to save
      // you from needing, and then could not do.
      if (event.key === Qt.Key_Escape
          || (event.key === Qt.Key_Space
              && !(event.modifiers & Qt.ShiftModifier))) {
        term.looking = false;
        return;
      }
      // ── ACTING ON IT WITHOUT CLOSING IT FIRST ───────────────────
      // Looking at a directory of photographs is exactly when you know which
      // ones you want gone, and every one of these used to need the
      // overlay shut and reopened. The cursor stays where it is, so the
      // next picture is already up by the time the status line answers.
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        term.looking = false;
        term.activate();
        return;
      }
      // PLAY / PAUSE. Not space — that closes the overlay now — and not
      // Return, which opens the file in whatever owns it. `p` is free
      // here: paste means nothing over a single file being looked at.
      if (event.text === "p" && term.lookLayerRef.look.playable) {
        if (term.lookLayerRef.lookPlayer.playbackState === MediaPlayer.PlayingState)
          term.lookLayerRef.lookPlayer.pause();
        else term.lookLayerRef.lookPlayer.play();
        return;
      }
      if (event.text === "d") { term.trash(); return; }
      if (event.text === "y") { term.contentRef.seq("y"); return; }
      // ── QUICK ACTIONS, WHERE YOU NOTICE YOU NEED THEM ──────────
      // A sideways photograph is a thing you discover by looking at
      // one, and the brackets are the keys every image viewer uses
      // for it. `e` pulls the soundtrack out of whatever is playing.
      if (event.text === "[") { term.rotateLook(-90); return; }
      if (event.text === "]") { term.rotateLook(90); return; }
      if (event.text === "e" && term.lookLayerRef.look.vid) { term.extractAudio(); return; }
      if (event.text === "r") {
        term.looking = false; term.beginRename(); return;
      }
      // the shifted one still marks, as it does in the listing behind
      if (event.key === Qt.Key_Space
          && (event.modifiers & Qt.ShiftModifier)) {
        term.toggleMark(); term.moveSel(1); return;
      }
      // ── TWO AXES, TWO JOBS ──────────────────────────────────────
      // ACROSS is the directory: h/l and the horizontal arrows step to the
      // previous and next file, because this is a picture viewer and
      // left-right is what a hand reaches for in one. They do NOT walk the
      // trail here, which they do everywhere else — the trail is about
      // directories and there is no directory on screen.
      //
      // DOWN is the document: j/k and the vertical arrows scroll the text
      // pane. Four keys all meaning "next file" was three of them wasted,
      // and it left the one thing a long README actually needs — reading
      // past the first screenful — with no key at all.
      if (event.key === Qt.Key_Right || event.text === "l") {
        term.moveSel(1); return;
      }
      if (event.key === Qt.Key_Left || event.text === "h") {
        term.moveSel(-1); return;
      }
      if (event.key === Qt.Key_Down || event.text === "j") {
        term.lookLayerRef.look.scrollBy(1); return;
      }
      if (event.key === Qt.Key_Up || event.text === "k") {
        term.lookLayerRef.look.scrollBy(-1); return;
      }
      // ── A DOCUMENT'S PAGES ARE WHAT PAGE KEYS TURN ─────────────
      // Over a PDF with more than one page the four page keys walk
      // the pages; everywhere else they keep scrolling text.
      if (term.lookLayerRef.look.docPages > 1) {
        if (event.key === Qt.Key_PageDown) { term.lookLayerRef.look.docGo(term.lookLayerRef.look.docPage + 1); return; }
        if (event.key === Qt.Key_PageUp) { term.lookLayerRef.look.docGo(term.lookLayerRef.look.docPage - 1); return; }
        if (event.key === Qt.Key_Home) { term.lookLayerRef.look.docGo(1); return; }
        if (event.key === Qt.Key_End) { term.lookLayerRef.look.docGo(term.lookLayerRef.look.docPages); return; }
      }
      if (event.key === Qt.Key_PageDown) { term.lookLayerRef.look.scrollBy(8); return; }
      if (event.key === Qt.Key_PageUp) { term.lookLayerRef.look.scrollBy(-8); return; }
      if (event.key === Qt.Key_Home) { term.lookLayerRef.lookScroll.contentY = 0; return; }
      if (event.key === Qt.Key_End) {
        term.lookLayerRef.lookScroll.contentY = Math.max(0,
          term.lookLayerRef.lookScroll.contentHeight - term.lookLayerRef.lookScroll.height);
        return;
      }
      return;
    }

    if (term.sendToRef.open && !term.confirmRef.open) {
      // Escape backs out of the filter before it backs out of the sheet:
      // a narrowed tree is a state you can be in by accident, and losing
      // the whole picker for it would be losing the branches you opened
      // to get there.
      if (event.key === Qt.Key_Escape) {
        if (term.sendToRef.query !== "") { term.sendToRef.query = ""; return; }
        term.sendToRef.dismiss(); return;
      }
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        // SHIFT GOES THERE WITHOUT LEAVING HERE — the same shift the
        // listing's own open honours, and only for `go`: a copy has
        // nowhere to arrive that a tab could show.
        term.sendToRef.choose((event.modifiers & Qt.ShiftModifier) !== 0);
        return;
      }
      if (event.key === Qt.Key_Down) { term.sendToRef.step(1); return; }
      if (event.key === Qt.Key_Up) { term.sendToRef.step(-1); return; }
      if (event.key === Qt.Key_Right) { term.sendToRef.expandCurrent(); return; }
      if (event.key === Qt.Key_Left) { term.sendToRef.outward(); return; }
      if (event.key === Qt.Key_Backspace) {
        term.sendToRef.query = term.sendToRef.query.slice(0, -1); return;
      }
      // EVERYTHING ELSE PRINTABLE NARROWS THE TREE. Arrows and the four
      // keys above are the whole of the navigation, deliberately — see
      // the note on `query`.
      if (event.key !== Qt.Key_Tab && event.text
          && event.text.length === 1 && event.text >= " ") {
        term.sendToRef.query += event.text;
        return;
      }
      return;
    }

    if (term.confirmRef.open) {
      if (event.key === Qt.Key_Escape) { term.confirmRef.dismiss(); return; }
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        term.confirmRef.choose(term.confirmRef.pick);
        return;
      }
      const n = Math.max(1, term.confirmRef.choices.length);
      // The answers are drawn right to left (ConfirmBody): the first is
      // at the far right, so left goes on through the list.
      if (event.key === Qt.Key_Left || event.key === Qt.Key_H
          || event.key === Qt.Key_Tab) {
        term.confirmRef.pick = (term.confirmRef.pick + 1) % n;
        return;
      }
      if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
        term.confirmRef.pick = (term.confirmRef.pick + n - 1) % n;
        return;
      }
      // A number picks one outright: "2" on a three-way overwrite prompt
      // is faster than two arrows and a Return.
      if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
        const i = event.key - Qt.Key_1;
        if (i < term.confirmRef.choices.length) term.confirmRef.choose(i);
        return;
      }
      return;
    }

    if (event.key === Qt.Key_Escape) {
      term.propsRef.open = false;
      term.prefsRef.open = false;
      term.contentRef.forceActiveFocus();
      return;
    }

    // ── THE SETTINGS PANEL, FROM THE KEYBOARD ──────────────────
    // Tab and the arrows walk the rows; space or return works the one
    // under the cursor; left and right move a slider or a segment along.
    // Everything else is swallowed, which is why this branch was here in
    // the first place: `d` behind an open panel was a file in the trash
    // you never asked to send there.
    if (term.prefsRef.open) {
      const cur = term.prefAt();
      switch (event.key) {
      // Shift+Tab does not arrive as Tab with a modifier — it is its own
      // key, and testing Tab with ShiftModifier finds nothing.
      case Qt.Key_Tab:
      case Qt.Key_Down:     term.prefStep(1); return;
      case Qt.Key_Backtab:
      case Qt.Key_Up:       term.prefStep(-1); return;
      case Qt.Key_Right:    if (cur) cur.nudge(1); return;
      case Qt.Key_Left:     if (cur) cur.nudge(-1); return;
      case Qt.Key_Space:
      case Qt.Key_Return:
      case Qt.Key_Enter:    if (cur) cur.activate(); return;
      }
      return;
    }

    // the card's own keys — the permissions grid, Tab, Return, s; see
    // PropsCard.handleKey
    term.propsRef.handleKey(event.key);
  }
}

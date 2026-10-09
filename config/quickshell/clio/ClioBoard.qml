// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┘┴└─┘
// https://github.com/kbuckleys/
//
// THE WALL THE NOTES ARE ON — one surface per screen, every note drawn on
// every screen it reaches.
//
// A LAYER SURFACE BELONGS TO AN OUTPUT. The protocol fixes it at creation and
// has no request to change it, so a note cannot be carried across a seam the
// way a window is: moving one means destroying its surface and building
// another, and a surface that goes takes the pointer grab with it — which is
// why a drag across a monitor boundary had to be started again on the far
// side. So nothing is ever moved between outputs. Each screen's surface draws
// the whole wall and shows the part of it that lands on that screen. A note
// crossing a seam is already drawn on the far side before it gets there.
//
// THE INPUT REGION IS BUILT FROM THE MODEL. That is the part that looked
// impossible: a mask is a declared Region and the notes are a list. Masked to
// the item holding them the surface claimed the whole screen and swallowed
// every click on the desktop; masked to nothing it heard none at all. A
// Region's `regions` takes a list, and an Instantiator can build one Region
// per note — so the region really is the notes, and only the notes.
//
// Which also brings back what one surface per note could not have: a note you
// click comes to the FRONT, because they are items in one scene again rather
// than separate surfaces whose stacking is fixed at creation.
//
// ON THE BOTTOM LAYER, and declared after icarus' desktop catcher in
// shell.qml — that catcher masks the whole screen, and within one layer the
// later surface is the one on top.

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Wayland
import "../morpheus"
import "../terminus"
import "clio.js" as Scribe

Variants {
  model: Quickshell.screens

  PanelWindow {
    id: board
    required property var modelData

    screen: board.modelData
    readonly property real originX: board.screen ? board.screen.x : 0
    readonly property real originY: board.screen ? board.screen.y : 0

    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "clio"
    // A note is typed into, so the surface has to be able to hold the
    // keyboard — but only while one is being edited.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors { left: true; right: true; top: true; bottom: true }
    // ROWS, not notes: the last note deleted still has a row while it plays
    // its exit, and a board put away under it would cut that short. And kept
    // up while the notes pop out on a hide, for the same reason: `drawn`
    // counts the notes still on screen at all (popK > 0). NOT a timer
    // started on the hide — the binding saw `shown` go false before the
    // handler started it, the board was put away for an instant, and the
    // layer remapping (Hyprland's map animation) flashed every note before
    // its pop out (user, twice).
    property int drawn: 0
    visible: (Clio.shown || board.drawn > 0) && Clio.rows.count > 0

    // The head's height, and where it meets its note: a pixel INTO it, so
    // the head's edge and the note's lie on one line, the seam between them.
    readonly property int headH: 30
    readonly property int headGap: -1

    // Which note has the keyboard, "" for none. Board-local: the notes are
    // shared between screens, the keyboard is not.
    property string editing: ""

    // ── THE REGION, ONE RECTANGLE PER NOTE ─────────────────────────────
    // Built rather than declared — see the note above. Positioned exactly as
    // the cards are, so what takes a click is what draws.
    //
    // ALWAYS THE NOTES, even while one is being edited. It used to drop the
    // mask entirely so that clicking OFF a note was a click this surface
    // received — and that is a trap: clio then swallows the click, so
    // whatever would have taken the focus away never gets it, the state
    // never clears, and the surface keeps the whole screen for good. One
    // note touched and icarus could not be opened on that monitor again.
    //
    // Leaving insert is therefore not something this surface watches for. It
    // is told — see onActiveChanged, which fires when the click it did NOT
    // take lands on something else.
    Instantiator {
      id: shapes
      model: Clio.rows

      delegate: Region {
        required property string key
        readonly property var n: Clio.noteFor(key)
        // Nothing for a note on its way out, or for a wall fading away: what
        // is leaving is drawn, not touched, and the desktop under it is the
        // desktop again from the moment it was asked for.
        readonly property bool live: !!n && Clio.shown && !Clio.isLeaving(key)
        // And the head, which floats off the note while it is edited — over
        // its top edge, or under its bottom one when the top has no room.
        readonly property bool headed: live && board.editing === key
        readonly property real reach: board.headH + board.headGap
        readonly property bool below: !!n && n.y - board.originY < reach
        x: n ? Math.round(n.x - board.originX) : 0
        y: n ? Math.round(n.y - board.originY - (headed && !below ? reach : 0)) : 0
        width: live ? n.w : 0
        height: live ? n.h + (headed ? reach : 0) : 0
      }
    }

    mask: noteMask



    Region {
      id: noteMask
      // ZERO-SIZED ON ITS OWN. A Region combines its own rectangle with its
      // children's, and one with no geometry of its own does not mean "no
      // rectangle" — so the union came out as the whole surface and clio
      // swallowed every click on any screen that had a note on it. Which is
      // why making a note stopped icarus opening on that monitor.
      x: 0
      y: 0
      width: 0
      height: 0
      regions: {
        const out = [];
        for (let i = 0; i < shapes.count; i++) out.push(shapes.objectAt(i));
        return out;
      }
    }

    // ── THE CLICK THAT WENT SOMEWHERE ELSE ─────────────────────────────
    // The mechanism this shell already has for exactly this, and which zeus
    // and icarus both use: a grab reports the clicks that land outside its
    // windows WITHOUT taking them. That distinction is the whole problem —
    // widening the mask to catch the click swallowed it, so nothing else
    // could take the focus, so the state never cleared and the monitor was
    // lost to icarus for good. Asking the window whether it was still
    // active was the other way round: nothing ever told it.
    //
    // Held only while a note is being edited, so the desktop is untouched
    // the rest of the time.
    HyprlandFocusGrab {
      // The menu only while it is up, as zeus and icarus list theirs: its
      // surface does not exist until it opens, and a grab handed a window
      // with no surface never covers it — so a click on a menu row counted
      // as a click outside, the grab cleared, and the note lost the
      // keyboard under whatever the row had just done.
      windows: noteMenu.visible ? [ board, noteMenu ] : [ board ]
      active: board.editing !== "" || board.menuSlot !== null
      onCleared: {
        board.closeMenu();
        wall.forceActiveFocus();
      }
    }

    // ── THE RIGHT-CLICK MENU ───────────────────────────────────────────
    // Morpheus' card, the one icarus and zeus open on a layer surface, laid
    // out the way plato's editor menu is: each row carries what it does,
    // and the keys that do the same thing beside it. One per board, for
    // whichever note was right-clicked on this screen.
    //
    // The rows are taken when it opens, not bound: what can be cut is what
    // was selected when you asked, and a menu that rewrote itself under the
    // pointer would be a different menu from the one you aimed at.
    //
    // PUT AWAY by a choice, by a click anywhere else on the wall (the
    // shield below), by a click off the wall (the grab), or by any key —
    // the card never has the keyboard, so the note's own keys close it.
    property Item menuSlot: null
    property var menuItems: []

    function openMenu(s, p) {
      board.menuItems = s.menuItems();
      noteMenu.at = Qt.point(p.x, p.y);
      board.menuSlot = s;
    }
    function closeMenu() { board.menuSlot = null; }

    CardMenu {
      id: noteMenu
      screen: board.screen
      open: board.menuSlot !== null
      fit: true
      cardWidth: 240
      model: board.menuItems.map((it) => it.isSeparator ? { isSeparator: true }
        : { text: it.text, icon: it.icon, hint: it.hint || "", enabled: it.enabled !== false })
      onChosen: (i) => {
        const it = board.menuItems[i];
        board.closeMenu();
        if (it && it.run && it.enabled !== false) it.run();
      }
    }

    // ── SNAPPING ───────────────────────────────────────────────────────
    // A wall dragged together by hand is a wall a few pixels out everywhere.
    // So an edge that comes within SNAP of another note's edge — level with
    // it, or a GAP's width beside it — or of a screen's edge less a gutter,
    // goes the rest of the way, and a guide is drawn along what it met.
    //
    // FROM THE RAW POSITION EVERY TIME. The drags compute where the pointer
    // alone would put the note, and that is what is snapped, so pulling
    // past the threshold lets go: nothing is remembered between frames.
    //
    // Everything in the layout's global space, as a note's position is; the
    // guides are drawn only on the board doing the dragging.
    readonly property int snapReach: 8
    readonly property int snapGap: 12
    readonly property int snapGutter: 16
    property var guides: []

    // A move snaps whichever edge is nearer; a resize only the far ones,
    // right and bottom, which are the edges the corner moves.
    function snap(id, x, y, w, h, resizing) {
      const xs = [], ys = [];          // [target, from, to] along the other axis
      for (let i = 0; i < Clio.notes.length; i++) {
        const o = Clio.notes[i];
        if (o.id === id) continue;
        const spanY = [Math.min(y, o.y), Math.max(y + h, o.y + o.h)];
        const spanX = [Math.min(x, o.x), Math.max(x + w, o.x + o.w)];
        // level with its edges, and a gap clear of them
        xs.push([o.x, spanY], [o.x + o.w, spanY],
                [o.x + o.w + board.snapGap, spanY, o.x + o.w],
                [o.x - board.snapGap, spanY, o.x]);
        ys.push([o.y, spanX], [o.y + o.h, spanX],
                [o.y + o.h + board.snapGap, spanX, o.y + o.h],
                [o.y - board.snapGap, spanX, o.y]);
      }
      const ss = Quickshell.screens;
      for (let i = 0; i < ss.length; i++) {
        const s = ss[i], g = board.snapGutter;
        xs.push([s.x + g, [s.y, s.y + s.height]], [s.x + s.width - g, [s.y, s.y + s.height]]);
        ys.push([s.y + g, [s.x, s.x + s.width]], [s.y + s.height - g, [s.x, s.x + s.width]]);
      }

      // The nearest target for either of this note's edges along one axis.
      // A gap target lines up with an edge from the far side, so it is
      // matched only against the opposite edge of this note.
      function best(lo, size, targets, onlyFar) {
        let hit = null;
        for (let i = 0; i < targets.length; i++) {
          const t = targets[i], gap = t.length > 2;
          const edges = onlyFar ? [[lo + size, 1]] : [[lo, 0], [lo + size, 1]];
          for (let e = 0; e < edges.length; e++) {
            // a gap past the right of another note meets this note's LEFT
            if (gap && ((t[0] > t[2]) !== (edges[e][1] === 0))) continue;
            const d = t[0] - edges[e][0];
            if (Math.abs(d) <= board.snapReach && (!hit || Math.abs(d) < Math.abs(hit.d)))
              hit = { d: d, at: gap ? t[2] : t[0], span: t[1] };
          }
        }
        return hit;
      }

      const hx = best(x, w, xs, resizing), hy = best(y, h, ys, resizing);
      const out = { x: x, y: y, w: w, h: h };
      if (hx) { if (resizing) out.w += hx.d; else out.x += hx.d; }
      if (hy) { if (resizing) out.h += hy.d; else out.y += hy.d; }

      // Drawn where the edges met, across both notes. A gap snap draws the
      // other note's edge — that is the line this note is keeping clear of.
      const lines = [];
      if (hx) lines.push({ x: hx.at, y: Math.min(hx.span[0], out.y),
                           w: 1, h: Math.max(hx.span[1], out.y + out.h) - Math.min(hx.span[0], out.y) });
      if (hy) lines.push({ x: Math.min(hy.span[0], out.x), y: hy.at,
                           w: Math.max(hy.span[1], out.x + out.w) - Math.min(hy.span[0], out.x), h: 1 });
      board.guides = lines;
      return out;
    }

    Item {
      id: wall
      anchors.fill: parent

      // PUT AWAY NOTE BY NOTE: each pops out (see the slot's popOut) and
      // the board follows once they have (board.drawn). The wall itself used
      // to fade as one sheet, front-loaded, and was gone before any note
      // could be seen to shrink.

      // above every note, whatever its z has climbed to
      InputShield {
        z: 1e9
        visible: board.menuSlot !== null
        onClicked: board.closeMenu()
      }

      // The guides, over every note and under the shield.
      Repeater {
        model: board.guides
        delegate: Rectangle {
          required property var modelData
          z: 1e8
          x: Math.round(modelData.x - board.originX)
          y: Math.round(modelData.y - board.originY)
          width: Math.max(1, modelData.w)
          height: Math.max(1, modelData.h)
          color: Qt.rgba(Zenon.white.r, Zenon.white.g, Zenon.white.b, 0.55)
        }
      }


      // ADDRESSED BY KEY, never by position — see Clio.rows. A delegate
      // that finds its note by index is a delegate that becomes a different
      // note the moment one earlier in the list goes; addressed by key it
      // stays the note it was, and the one that went is the one destroyed.
      Repeater {
        model: Clio.rows

        delegate: Item {
          id: slot
          required property string key

          readonly property var note: Clio.noteFor(slot.key)
          readonly property string noteId: slot.key
          // Not readonly, so it can be animated: a note changing colour
          // passes through the colours between rather than jumping, and the
          // ground, the edge and the head all follow it, being made of it.
          property color hue:
            slot.note ? Clio.ink(slot.note.hue) : Zenon.sand
          Behavior on hue { ColorAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
          // The body, or the typeface picker standing in for it: choosing a
          // face is still being on the note, so the head stays out.
          readonly property bool active: body.activeFocus || slot.pickFocus
          readonly property bool leaving: Clio.isLeaving(slot.key)
          // Being carried, as distinct from being pressed: set by the drags
          // once the pointer has really moved, so a click does not bob.
          property bool lifted: false
          // In the air, one way or the other: what the deep shadow means.
          readonly property bool raised: slot.active || slot.lifted

          // A deleted note's keyboard is given up before it fades, not left
          // to be lost when its row goes — a focus that dies with its item
          // never says so, and the board's grab would stay up holding it.
          onLeavingChanged: if (slot.leaving && (body.activeFocus || slot.pickFocus)) {
            body.focus = false;
            slot.picking = false;
            board.editing = "";
            wall.forceActiveFocus();
          }

          // BOUND, not owned. A gesture writes the note on every frame and
          // this follows — which is how the copy of this note on the next
          // screen keeps up with a drag happening on this one.
          x: slot.note ? slot.note.x - board.originX : 0
          y: slot.note ? slot.note.y - board.originY : 0
          width: slot.note ? slot.note.w : 350
          height: slot.note ? slot.note.h : 220

          // The one you touched is the one in front. Stacking is an item's
          // `z` again, which is the whole reason these share a surface.
          z: slot.note ? slot.note.z : 0

          visible: slot.note !== null
          property bool busy: false

          // ── CHOOSING A TYPEFACE ──────────────────────────────────────
          // The list stands where the text was until a face is picked or
          // escape is pressed; either way the text comes back with the caret.
          // First in the list, unfiltered, is the shell's own face: "".
          property bool picking: false
          // the list's filter line has the keyboard (set by it, below)
          property bool pickFocus: false
          property int faceSel: 0
          readonly property var shownFaces: {
            const q = faceQuery.text.toLowerCase();
            if (q === "") return [""].concat(Clio.families);
            return Clio.families.filter((f) => f.toLowerCase().indexOf(q) >= 0);
          }
          onShownFacesChanged: if (slot.faceSel >= slot.shownFaces.length) slot.faceSel = 0

          function openFaces() {
            Clio.loadFaces();
            faceQuery.text = "";
            slot.faceSel = Math.max(0, slot.shownFaces.indexOf(slot.note ? slot.note.face : ""));
            slot.picking = true;
            faceQuery.forceActiveFocus();
          }
          // NO LONGER BEING EDITED — decided once the focus has landed,
          // never in the middle of its move. Between the text and the
          // typeface list there is an instant when neither has it; clearing
          // `editing` then dropped the board's focus grab for that instant,
          // and a grab let go hands the keyboard to whatever is under the
          // pointer. From the head that is the note itself, so nothing was
          // seen; from the right-click menu it is the menu's card, which
          // takes no keyboard — so the board lost it, and the list closed
          // the moment it opened.
          function settle() {
            if (!body.activeFocus && !slot.pickFocus && board.editing === slot.noteId)
              board.editing = "";
          }
          // Put down: the end of every gesture, released or taken away.
          function drop() {
            slot.busy = false;
            slot.lifted = false;
            board.guides = [];
          }
          function closeFaces(face) {
            if (face !== undefined && slot.note) Clio.set(slot.noteId, "face", face);
            slot.picking = false;
            body.forceActiveFocus();
          }
          // ── WHAT ITS MENU OFFERS ─────────────────────────────────────
          // The edits a text field answers to, the head's own controls said
          // in words, and the note itself. Hints only for keys that do work
          // here: TextEdit's own, and the size steps (body.Keys).
          function menuItems() {
            const sel = body.selectionStart !== body.selectionEnd;
            const size = slot.note ? slot.note.size : Scribe.DEFAULT_SIZE;
            return [
              { text: "Cut", icon: "\u{F0190}", hint: "ctrl x", enabled: sel, run: () => body.cut() },
              { text: "Copy", icon: "\u{F018F}", hint: "ctrl c", enabled: sel, run: () => body.copy() },
              { text: "Paste", icon: "\u{F0192}", hint: "ctrl v", enabled: body.canPaste, run: () => body.paste() },
              { text: "Select all", icon: "\u{F0486}", hint: "ctrl a", run: () => body.selectAll() },
              { isSeparator: true },
              { text: "Bold", icon: "\uF032", run: () => card.mark("b") },
              { text: "Italic", icon: "\uF033", run: () => card.mark("i") },
              { text: "Underline", icon: "\uF0CD", run: () => card.mark("u") },
              { isSeparator: true },
              { text: "Larger text", icon: "\uF067", hint: "ctrl +",
                enabled: Scribe.stepSize(size, 1) !== size,
                run: () => Clio.set(slot.noteId, "size", Scribe.stepSize(size, 1)) },
              { text: "Smaller text", icon: "\uF068", hint: "ctrl -",
                enabled: Scribe.stepSize(size, -1) !== size,
                run: () => Clio.set(slot.noteId, "size", Scribe.stepSize(size, -1)) },
              { text: "Typeface", icon: "\uE659", run: () => slot.openFaces() },
              { isSeparator: true },
              { text: "New note", icon: "\uF067", run: () => Clio.addHere() },
              { text: "Hide notes", icon: "\uF070", run: () => Clio.toggle() },
              { text: "Delete note", icon: "\uF1F8", run: () => Clio.remove(slot.noteId) }
            ];
          }

          // a list that arrives after the picker opened finds the face the
          // note is set in, rather than leaving the bar on the default
          Connections {
            target: Clio
            function onFamiliesChanged() {
              if (slot.picking && faceQuery.text === "")
                slot.faceSel = Math.max(0, slot.shownFaces.indexOf(slot.note ? slot.note.face : ""));
            }
          }


          // ARRIVING. Once, when the note is made — which now happens only
          // when a note is genuinely made. And LEAVING, the same played
          // backwards: Clio holds the row until it has (see Clio.leaving).
          //
          // Lifted a touch while carried, with the deeper shadow below: the
          // note is off the wall and in your hand.
          //
          // A POP, both ways: in from 0.8 past full size and back (OutBack),
          // out as a quick shrink. Shown and hidden from icarus too — the
          // wall used to only fade as one sheet — with the notes popping in
          // turn (Zenon.stagger, capped at eight steps like every stagger).
          required property int index
          property bool arrived: false
          readonly property bool here: slot.arrived && !slot.leaving && Clio.shown
          enabled: !slot.leaving
          property real popK: 0
          // counted on the board while drawn at all (see board.drawn)
          readonly property bool onScreen: slot.popK > 0.001
          onOnScreenChanged: board.drawn += slot.onScreen ? 1 : -1
          Component.onDestruction: if (slot.onScreen) board.drawn -= 1
          property real liftK: slot.lifted ? 1.015 : 1
          Behavior on liftK {
            NumberAnimation { duration: Zenon.normal; easing.type: Zenon.travelEase }
          }
          opacity: Math.min(1, slot.popK)
          scale: (0.8 + 0.2 * slot.popK) * slot.liftK
          // set only while the delegate is being made: a new note pops at
          // once, the stagger is for a wall coming back
          property bool fresh: false
          Component.onCompleted: { slot.fresh = true; slot.arrived = true; slot.fresh = false; }
          onHereChanged: {
            popIn.stop();
            popOut.stop();
            if (slot.here) {
              popDelay.duration = slot.fresh || slot.popK > 0
                ? 0 : Math.min(slot.index, 8) * Zenon.stagger * 2;
              popIn.start();
            } else popOut.start();
          }
          SequentialAnimation {
            id: popIn
            PauseAnimation { id: popDelay; duration: 0 }
            NumberAnimation {
              target: slot; property: "popK"; to: 1
              duration: Zenon.normal * 2
              easing.type: Easing.OutBack
              easing.overshoot: 2.2
            }
          }
          NumberAnimation {
            id: popOut
            target: slot; property: "popK"; to: 0
            duration: Math.round(Zenon.normal * 1.4)
            // straight in, gathering pace: an outward breath first (InBack)
            // read as the notes flashing before they went
            easing.type: Easing.InQuad
          }

          // The shadow every card on this desktop casts. A sibling of the
          // card and never a child: the card clips, and a card that clips
          // clips its own shadow away.
          // ── THE SHAPE THE SHADOW FALLS FROM ──────────────────────────
          // The card, and the head with it while the head is up: one shape,
          // so one shadow — the head's own fell across the note beneath it.
          // Grown at the head's pace, so the shadow opens with it.
          Item {
            id: hull
            // not readonly: a readonly property cannot carry a Behavior
            property real reach: slot.active ? board.headH + board.headGap : 0
            x: 0
            width: slot.width
            y: head.below ? 0 : -hull.reach
            height: slot.height + hull.reach
            Behavior on reach {
              NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
            }
          }

          MenuShadow {
            panel: hull
            cornerRadius: card.radius
            ink: slot.raised ? Zenon.menuShadowInk
              : Qt.rgba(Zenon.menuShadowInk.r, Zenon.menuShadowInk.g,
                        Zenon.menuShadowInk.b, Zenon.menuShadowInk.a * 0.45)
            softness: slot.raised
              ? Zenon.menuShadowBlur : Zenon.menuShadowBlur * 0.45
            grow: slot.raised ? Zenon.menuShadowGrow : 0
            drop: slot.raised
              ? Zenon.menuShadowDrop : Zenon.menuShadowDrop * 0.4
            Behavior on softness {
              NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
            }
            Behavior on drop {
              NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
            }
            Behavior on ink { ColorAnimation { duration: Zenon.fast } }
          }

          // The note a menu is open about (terminus/HeldRing.qml), as
          // everywhere a right click asks something. A step out from the
          // card and hollow: the note's own wash is its colour.
          HeldRing {
            anchors.fill: parent
            anchors.margins: -4
            radius: card.radius + 4
            on: board.menuSlot === slot
          }

          ClippingRectangle {
            id: card
            anchors.fill: parent
            radius: 8
            // squared on the side the head joins, while it is there
            readonly property real joined: slot.active ? 0 : card.radius
            topLeftRadius: head.below ? card.radius : card.joined
            topRightRadius: head.below ? card.radius : card.joined
            bottomLeftRadius: head.below ? card.joined : card.radius
            bottomRightRadius: head.below ? card.joined : card.radius
            color: slot.note ? Clio.washOf(slot.hue) : "transparent"
            border.width: 1
            // The note's own colour, not the shared rule: the edge is part of
            // which note this is. Brighter under the pointer, which is the
            // only thing an idle note says about being something you can
            // pick up — the edge is already its colour, so it is the edge
            // that answers.
            border.color: Qt.rgba(slot.hue.r, slot.hue.g, slot.hue.b,
              noteHov.hovered && !slot.active ? 0.85 : 0.55)
            Behavior on border.color { ColorAnimation { duration: Zenon.fast } }

            HoverHandler { id: noteHov }

            // ── AND THE NOTE ITSELF ──────────────────────────────────
            Flickable {
              id: bodyScroll
              visible: !slot.picking
              // Finder's rubber band and the smooth wheel notch, one rule for
              // the whole shell — see morpheus/Elastic.qml. Inside the view
              // rather than over it: it pins itself to the viewport.
              ElasticScroll { view: bodyScroll }
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: 10
              clip: true
              contentWidth: width
              contentHeight: body.implicitHeight
              boundsBehavior: Flickable.StopAtBounds

              TextEdit {
                id: body
                width: parent.width
                // RICH TEXT, because the formatting buttons are edits rather
                // than properties — see card.mark. Plain text would render
                // the tags they insert as the characters they are made of.
                textFormat: TextEdit.RichText
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                persistentSelection: true
                // SET ONCE, NEVER BOUND. Assigning text to a TextEdit puts
                // the caret at the start, so a binding would have moved it
                // there on every keystroke. The model is written TO from here
                // and read back only when this slot takes on another note.
                Component.onCompleted: body.text = slot.note ? slot.note.text : ""

                // ...EXCEPT ON THE OTHER SCREENS. Every screen draws its own
                // copy of every note, and only the copy being typed in wrote
                // anything; the rest kept the text they were made with. Drag a
                // note across and it showed stale text, and typing into that
                // copy saved stale text plus the edit over the real note.
                // So a copy that does NOT have the keyboard follows the model
                // — the one that does is the model's source, and resetting it
                // is exactly the caret jump the note above avoids.
                readonly property string modelText: slot.note ? slot.note.text : ""
                property bool syncing: false
                onModelTextChanged: {
                  if (body.activeFocus) return;
                  const mine = body.length === 0 ? "" : Scribe.fragment(body.text);
                  if (mine === body.modelText) return;
                  body.syncing = true;
                  body.text = body.modelText;
                  body.syncing = false;
                }
                color: Zenon.white
                selectionColor: Zenon.wash(0.25)
                selectedTextColor: Zenon.white
                font.family: Clio.faceOf(slot.note)
                font.weight: Clio.weightOf(slot.note)
                font.pixelSize: slot.note ? slot.note.size : Scribe.DEFAULT_SIZE

                cursorDelegate: Caret { field: body }

                // Stored as the body's contents rather than as Qt's whole
                // HTML document — see Scribe.fragment — and as nothing at
                // all when the note is empty, which is otherwise six hundred
                // bytes of boilerplate saying so.
                onTextChanged: {
                  if (!slot.note || body.syncing) return;
                  const t = body.length === 0 ? "" : Scribe.fragment(body.text);
                  if (t !== slot.note.text)
                    Clio.set(slot.noteId, "text", t);
                }
                onActiveFocusChanged: {
                  if (activeFocus) {
                    board.editing = slot.noteId;
                    Clio.raise(slot.noteId);
                  } else {
                    Qt.callLater(slot.settle);
                  }
                }

                // BACK TO NORMAL. Giving the focus up is the whole of it:
                // the head, the buttons and the card's own handle all read
                // `slot.active`, which is this having the keyboard.
                // ctrl+= and ctrl+-, the zoom every editor has, onto the same
                // steps as the head's minus and plus — see Scribe.stepSize.
                // Plus as well as equals: with shift held, the key says Plus.
                Keys.onPressed: (e) => {
                  if (board.menuSlot !== null) {
                    board.closeMenu();
                    e.accepted = true;
                    return;
                  }
                  if (!(e.modifiers & Qt.ControlModifier) || !slot.note) return;
                  const by = e.key === Qt.Key_Equal || e.key === Qt.Key_Plus ? 1
                    : e.key === Qt.Key_Minus ? -1 : 0;
                  if (by === 0) return;
                  e.accepted = true;
                  const next = Scribe.stepSize(slot.note.size, by);
                  if (next !== slot.note.size) Clio.set(slot.noteId, "size", next);
                }

                Keys.onEscapePressed: (e) => {
                  e.accepted = true;
                  body.deselect();
                  body.focus = false;
                  wall.forceActiveFocus();
                }
              }
            }

            // ── WHERE THE TEXT RUNS ON ──────────────────────────────
            // A long note was cut off by a hard edge mid-line. Now the last
            // few pixels melt into the note's ground, and only while there
            // is more past them — at the end of the text the edge is clean.
            // The first edge does the same once the text has been scrolled.
            Rectangle {
              visible: bodyScroll.visible && bodyScroll.contentY > 1
              anchors.top: bodyScroll.top
              anchors.left: bodyScroll.left
              anchors.right: bodyScroll.right
              height: 14
              gradient: Gradient {
                GradientStop { position: 0; color: card.color }
                GradientStop { position: 1; color: Qt.rgba(card.color.r, card.color.g, card.color.b, 0) }
              }
            }
            Rectangle {
              visible: bodyScroll.visible
                && bodyScroll.contentY + bodyScroll.height < bodyScroll.contentHeight - 1
              anchors.bottom: bodyScroll.bottom
              anchors.left: bodyScroll.left
              anchors.right: bodyScroll.right
              height: 22
              gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(card.color.r, card.color.g, card.color.b, 0) }
                GradientStop { position: 1; color: card.color }
              }
            }

            // A SIBLING OF THE FLICKABLE, NEVER A CHILD OF IT. Inside, it
            // becomes part of the scrolling content: it travels up with the
            // text and its anchors resolve against the content item, whose
            // height is the whole document — so the "thumb" was as long as
            // the note and the whole thing read as one grey bar.
            // The track stops short of the corner grip (26px, below): run
            // to the bottom it lay over the grip, and the thumb at the end
            // of a long note sat on top of what you pull.
            Scrollbar {
              flick: bodyScroll
              anchors.right: bodyScroll.right
              anchors.top: bodyScroll.top
              anchors.bottom: bodyScroll.bottom
              anchors.bottomMargin: 26
            }

            // ── THE TYPEFACE LIST ────────────────────────────────────
            // Plato's font list, at a note's scale: a line to type a filter
            // into, then every family set in itself. Up and down (or ctrl+n
            // and ctrl+p) move, return takes it, escape leaves the face as
            // it was.
            Item {
              id: faces
              visible: slot.picking
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: 10

              TextInput {
                id: faceQuery
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 24
                verticalAlignment: TextInput.AlignVCenter
                color: Zenon.white
                selectionColor: Zenon.wash(0.25)
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(14)
                cursorDelegate: Caret { field: faceQuery }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: faceQuery.text === ""
                  text: "typeface…"
                  color: Zenon.wash(0.35)
                  font: faceQuery.font
                }

                // the board's keyboard is held while this is, exactly as
                // while the body is — see onActiveFocusChanged on the body
                onActiveFocusChanged: {
                  slot.pickFocus = activeFocus;
                  if (activeFocus) {
                    board.editing = slot.noteId;
                  } else {
                    slot.picking = false;
                    Qt.callLater(slot.settle);
                  }
                }

                Keys.onPressed: (e) => {
                  const n = slot.shownFaces.length;
                  const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
                  if (e.key === Qt.Key_Escape) {
                    slot.closeFaces();
                  } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                    if (n) slot.closeFaces(slot.shownFaces[slot.faceSel]);
                  } else if (e.key === Qt.Key_Down || (ctrl && e.key === Qt.Key_N)) {
                    if (n) slot.faceSel = (slot.faceSel + 1) % n;
                  } else if (e.key === Qt.Key_Up || (ctrl && e.key === Qt.Key_P)) {
                    if (n) slot.faceSel = (slot.faceSel - 1 + n) % n;
                  } else return;
                  e.accepted = true;
                }
              }

              Rectangle {
                id: faceRule
                anchors.top: faceQuery.bottom
                anchors.topMargin: 4
                width: parent.width
                height: 1
                color: Qt.rgba(slot.hue.r, slot.hue.g, slot.hue.b, 0.35)
              }

              ListView {
                id: faceList
                anchors.top: faceRule.bottom
                anchors.topMargin: 4
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                clip: true
                model: slot.picking ? slot.shownFaces : []
                currentIndex: slot.faceSel
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                boundsBehavior: Flickable.StopAtBounds
                ElasticScroll { view: faceList }
                SelectBar {
                  view: faceList
                  index: slot.faceSel
                  rowH: 26
                  color: Zenon.wash(0.14)
                }

                delegate: Item {
                  id: fam
                  required property string modelData
                  required property int index
                  width: faceList.width
                  height: 26

                  Text {
                    x: 6
                    width: parent.width - 12
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: fam.modelData === "" ? "Default · " + Clio.defaultFace : fam.modelData
                    font.family: fam.modelData === "" ? Zenon.face : fam.modelData
                    font.pixelSize: Zenon.px(16)
                    color: slot.note && fam.modelData === slot.note.face ? slot.hue : Zenon.white
                  }

                  MouseArea {
                    anchors.fill: parent
                    onClicked: slot.closeFaces(fam.modelData)
                  }
                }
              }
            }

            // The placeholder, which is not the TextEdit's own: a rich-text
            // edit has no ghost, and an empty note that says nothing at all
            // looks broken rather than blank.
            Text {
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.topMargin: 10
              anchors.leftMargin: 10
              visible: body.length === 0 && !body.activeFocus && !slot.picking
              text: "note\u2026"
              color: Zenon.wash(0.35)
              font.family: Clio.faceOf(slot.note)
              font.weight: Clio.weightOf(slot.note)
              font.pixelSize: slot.note ? slot.note.size : Scribe.DEFAULT_SIZE
            }

            // ── NORMAL MODE ──────────────────────────────────────────
            // A note you have not clicked into is an editor in normal mode:
            // no edits, only motion. So the whole card is the handle and the
            // text under it is inert — which is why this sits ABOVE the body
            // and is disabled the moment the body has the keyboard.
            //
            // A CLICK AND A DRAG ARE THE SAME GESTURE until the pointer
            // moves. Under the threshold it was a click and the note goes
            // into insert; over it, it was a drag and the note was moved,
            // which is not a request to start typing in it. Five pixels, the
            // same figure terminus tells a tab click from a tab drag by.
            MouseArea {
              anchors.fill: parent
              enabled: !slot.active
              property real grabX: 0
              property real grabY: 0
              property bool moved: false

              onPressed: (m) => {
                grabX = m.x;
                grabY = m.y;
                moved = false;
                slot.busy = true;
                Clio.raise(slot.noteId);
              }
              onPositionChanged: (m) => {
                if (!pressed) return;
                if (!moved
                    && Math.abs(m.x - grabX) < 5 && Math.abs(m.y - grabY) < 5)
                  return;
                moved = true;
                slot.lifted = true;
                const s = board.snap(slot.noteId,
                  slot.note.x + (m.x - grabX),
                  slot.note.y + (m.y - grabY),
                  slot.note.w, slot.note.h, false);
                Clio.place(slot.noteId, s.x, s.y, s.w, s.h);
              }
              onReleased: {
                slot.drop();
                if (!moved) body.forceActiveFocus();
              }
              onCanceled: slot.drop()
            }

            // ── THE CORNER YOU PULL ──────────────────────────────────
            MouseArea {
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              width: 26
              height: 26
              cursorShape: Qt.SizeFDiagCursor
              // Grown with the glyph: the mark and the thing you grab are the
              // same corner, and a 22px glyph inside a 20px box would have
              // been drawn past the edge of what answers the pointer.
              property real grabW: 0
              property real grabH: 0
              property real grabX: 0
              property real grabY: 0

              // MEASURED IN THE WALL, never in this box. `m.x` is relative
              // to this MouseArea, and this MouseArea is anchored to the
              // card's right and bottom edges — the very edges the drag is
              // moving. So the origin the pointer was measured from slid out
              // from under it on every frame, and the note grew in fits.
              // Reading the pointer off a thing the pointer is moving is a
              // feedback loop; the wall holds still.
              onPressed: (m) => {
                const p = mapToItem(wall, m.x, m.y);
                grabW = slot.note.w;
                grabH = slot.note.h;
                grabX = p.x;
                grabY = p.y;
                slot.busy = true;
                Clio.raise(slot.noteId);
              }
              onPositionChanged: (m) => {
                if (!pressed) return;
                const p = mapToItem(wall, m.x, m.y);
                const s = board.snap(slot.noteId, slot.note.x, slot.note.y,
                  Scribe.clamp(grabW + (p.x - grabX),
                               Scribe.MIN_W, Scribe.MAX_W),
                  Scribe.clamp(grabH + (p.y - grabY),
                               Scribe.MIN_H, Scribe.MAX_H), true);
                // clamped again: a snap can carry an edge past the limits
                Clio.place(slot.noteId, slot.note.x, slot.note.y,
                  Scribe.clamp(s.w, Scribe.MIN_W, Scribe.MAX_W),
                  Scribe.clamp(s.h, Scribe.MIN_H, Scribe.MAX_H));
              }
              onReleased: slot.drop()
              onCanceled: slot.drop()

              Text {
                anchors.centerIn: parent
                text: "\uDB81\uDC5D"
                color: Zenon.wash(noteHov.hovered ? 0.45 : 0)
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(22)
                Behavior on color { ColorAnimation { duration: Zenon.fast } }
              }
            }

            // ── THE RIGHT BUTTON ─────────────────────────────────────
            // Over everything in the card and answering only the right
            // button, so a left click still reaches whatever is under it.
            // A note right-clicked in normal mode goes into insert first:
            // what the menu does, it does to the text.
            MouseArea {
              anchors.fill: parent
              acceptedButtons: Qt.RightButton
              onPressed: (m) => {
                Clio.raise(slot.noteId);
                if (slot.picking) slot.closeFaces();
                else if (!body.activeFocus) body.forceActiveFocus();
                board.openMenu(slot, mapToItem(wall, m.x, m.y));
              }
            }

            // ── BOLD, ITALIC, UNDERLINE ──────────────────────────────
            // An EDIT, not a property. TextEdit's font is document-wide, so
            // there is no per-selection bold to set — the selection is
            // replaced with itself inside the tag, which is what a rich-text
            // editor does underneath. With nothing selected the whole note is
            // wrapped, because that is what pressing bold on an empty
            // selection means.
            // THROUGH Scribe.inline, and that is the whole of why this
            // works now. getFormattedText hands back a whole HTML document —
            // doctype, head, stylesheet and a paragraph — so wrapping its
            // result in <b> put the tag around the DOCTYPE and left the words
            // exactly as they were. Reduced to the run of inline markup
            // inside it, the tag lands on the text.
            function mark(tag) {
              const from = body.selectionStart;
              const to = body.selectionEnd;
              const had = from !== to;
              const a = had ? from : 0;
              const b = had ? to : body.length;
              if (b <= a) return;
              const run = Scribe.inline(body.getFormattedText(a, b));
              if (run === "") return;
              // A TOGGLE, NOT A STAMP. Pressing bold on bold text is how you
              // ask for it not to be bold — a one-shot left the only way back
              // being undo, and pressing it twice nested one <b> inside
              // another and grew the document for nothing.
              const next = Scribe.marked(run, tag)
                ? Scribe.unmark(run, tag)
                : "<" + tag + ">" + run + "</" + tag + ">";
              body.remove(a, b);
              body.insert(a, next);
              // The selection is put back so the next button acts on the same
              // words — bold then italic is one thought, not two selections.
              if (had) body.select(a, body.selectionEnd);
              body.forceActiveFocus();
            }
          }

          // ── THE HEAD IS THE HANDLE ───────────────────────────────
          // The whole note is not draggable, because the whole note but
          // this strip is a text field — a drag starting in the body is a
          // selection, and guessing which was meant is how an editor loses
          // a sentence.
          //
          // GROWN ONTO THE NOTE, NOT INSIDE IT. It used to grow inside the
          // card from nothing, and the text, anchored under it, dropped its
          // whole height every time a note was clicked into; keeping its room
          // instead left every idle note with an empty band across its top.
          // So it is outside the card, joined to it: on its top edge — or its
          // bottom one when there is no room above on this screen — with the
          // card's corners on that side squared while it is there, so the
          // two read as one shape with a rule across it. One shadow under
          // both (see `hull`). The board's input region grows to take it in
          // while the note is being edited (see the Instantiator up top).
          //
          // A sibling of the card for the same reason the shadow is: the
          // card clips.
          Rectangle {
            id: head
            readonly property bool below: !!slot.note
              && slot.note.y - board.originY < head.height + board.headGap
            x: 0
            width: slot.width
            height: board.headH
            y: head.below ? slot.height + board.headGap : -head.height - board.headGap
            radius: card.radius
            // square where it meets the note
            topLeftRadius: head.below ? 0 : card.radius
            topRightRadius: head.below ? 0 : card.radius
            bottomLeftRadius: head.below ? card.radius : 0
            bottomRightRadius: head.below ? card.radius : 0
            clip: true
            color: Clio.washOf(slot.hue)
            border.width: 1
            border.color: Qt.rgba(slot.hue.r, slot.hue.g, slot.hue.b, 0.55)
            opacity: slot.active ? 1 : 0
            visible: head.opacity > 0.01
            Behavior on opacity {
              NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
            }

            // the tint the head always wore, over the note's own ground
            Rectangle {
              anchors.fill: parent
              anchors.margins: 1
              topLeftRadius: Math.max(0, head.topLeftRadius - 1)
              topRightRadius: Math.max(0, head.topRightRadius - 1)
              bottomLeftRadius: Math.max(0, head.bottomLeftRadius - 1)
              bottomRightRadius: Math.max(0, head.bottomRightRadius - 1)
              color: Qt.rgba(slot.hue.r, slot.hue.g, slot.hue.b, 0.22)
            }

            MouseArea {
              id: drag
              anchors.fill: parent
              // idle, the whole card is the handle (normal mode, in the card)
              enabled: slot.active
              property real grabX: 0
              property real grabY: 0

              onPressed: (m) => {
                drag.grabX = m.x;
                drag.grabY = m.y;
                // Keeps the note active while it is being dragged: the head
                // is shown by the body having focus, and a press on the
                // head is not a press on the body.
                slot.busy = true;
                body.forceActiveFocus();
                Clio.raise(slot.noteId);
              }
              onPositionChanged: (m) => {
                if (!drag.pressed) return;
                slot.lifted = true;
                const s = board.snap(slot.noteId,
                  slot.note.x + (m.x - drag.grabX),
                  slot.note.y + (m.y - drag.grabY),
                  slot.note.w, slot.note.h, false);
                Clio.place(slot.noteId, s.x, s.y, s.w, s.h);
              }
              // Recorded on release rather than per frame: the position is
              // not news until the gesture is over, and a file rewritten
              // sixty times a second to record one drag is sixty writes
              // for one fact.
              onReleased: slot.drop()
              onCanceled: slot.drop()
            }

            // ── WHAT THE HEAD HOLDS ──────────────────────────────
            // Only while you are on the note. A wall of stickies covered
            // in buttons is a control panel; the buttons are for when you
            // have reached for one.
            readonly property bool armed: slot.active

            // ── WHAT FITS, IN THE ORDER IT IS MISSED LEAST ───────
            // A note can be dragged down to 180px and the bar cannot: at
            // full strength it needs about three hundred. So it gives way
            // instead of piling up — the swatches go first, then the size
            // stepper, and the close never does. Measured against what the
            // rows actually want rather than against thresholds written
            // out here, so changing a glyph cannot put the numbers wrong.
            readonly property real freeForSwatches:
              head.width - fmtRow.width - close.width - 34
            readonly property bool roomForSwatches:
              head.freeForSwatches >= swatchRow.implicitWidth
            readonly property bool roomForSize:
              head.width - close.width - 34 >= fmtRow.implicitWidth

            Row {
              id: fmtRow
              anchors.left: parent.left
              anchors.leftMargin: 6
              anchors.verticalCenter: parent.verticalCenter
              spacing: 2
              opacity: head.armed ? 1 : 0
              visible: opacity > 0.01
              Behavior on opacity {
                NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
              }

              // Bold, italic and underline, applied to the SELECTION when
              // there is one and to the whole note when there is not —
              // which is what pressing bold with nothing selected means.
              Repeater {
                model: [["\uF032", "b"], ["\uF033", "i"], ["\uF0CD", "u"]]

                delegate: Rectangle {
                  id: fmt
                  required property var modelData
                  width: 26
                  height: 22
                  radius: 4
                  color: fmtHov.hovered
                    ? Zenon.wash(0.16) : "transparent"

                  HoverHandler { id: fmtHov }

                  Text {
                    anchors.centerIn: parent
                    text: fmt.modelData[0]
                    color: Zenon.white
                    font.family: Zenon.face
                    font.weight: Zenon.weight
                    font.pixelSize: Zenon.px(14)
                  }

                  MouseArea {
                    anchors.fill: parent
                    onClicked: card.mark(fmt.modelData[1])
                  }
                }
              }

              // ── AND HOW BIG IT IS, AND IN WHAT ─────────────────
              // The face's mark, then down and up either side of it. The
              // mark is the one control here that is about the TYPE rather
              // than the size, and pressing it says so: it opens the
              // typeface list in the note's place. Tinted in the note's hue
              // while the note is set in something other than the shell's
              // own face.
              //
              // Each end dims when there is nowhere further to go, so the
              // control says it has run out rather than silently ignoring
              // you — see Scribe.stepSize, which clamps rather than wraps.
              Item { width: 5; height: 1; visible: head.roomForSize }

              // MINUS, THE MARK, PLUS — read as a sentence, with the thing
              // being changed in the middle and the two directions either
              // side of it. One Repeater rather than a button, a label and
              // another button: the middle entry is the one with nowhere to
              // step, which is what makes it the label.
              Repeater {
                model: [["\uF068", -1], ["\uE659", 0], ["\uF067", 1]]

                delegate: Rectangle {
                  id: step
                  required property var modelData
                  readonly property bool isMark: step.modelData[1] === 0
                  visible: head.roomForSize
                  readonly property bool canGo: !step.isMark && slot.note
                    && Scribe.stepSize(slot.note.size, step.modelData[1])
                       !== slot.note.size
                  width: 26
                  height: 22
                  radius: 4
                  color: stepHov.hovered && (step.isMark || step.canGo)
                    ? Zenon.wash(0.16) : "transparent"

                  HoverHandler { id: stepHov }

                  // ── A NUDGE WHEN IT TOOK ───────────────────────────
                  // The text resizing is the answer, but on a long note
                  // it can be off the part you are looking at. So the
                  // button that matches the step pops — ctrl+= and
                  // ctrl+- included, which reach it from the keyboard.
                  readonly property int size: slot.note ? slot.note.size : 0
                  // a value, not a binding: a binding could catch up
                  // before the handler below had compared against it
                  property int was: 0
                  Component.onCompleted: step.was = step.size
                  onSizeChanged: {
                    if (!step.isMark && step.was > 0 && step.size > 0
                        && (step.size > step.was) === (step.modelData[1] > 0))
                      pop.restart();
                    step.was = step.size;
                  }

                  Text {
                    id: stepGlyph
                    anchors.centerIn: parent
                    text: step.modelData[0]
                    color: step.isMark && slot.note && slot.note.face
                      ? slot.hue : Zenon.white
                    opacity: step.isMark ? 1 : (step.canGo ? 1 : 0.3)
                    font.family: Zenon.face
                    font.weight: Zenon.weight
                    font.pixelSize: Zenon.px(step.isMark ? 14 : 12)

                    SequentialAnimation on scale {
                      id: pop
                      running: false
                      NumberAnimation { to: 1.35; duration: Zenon.fast * 0.6; easing.type: Easing.OutCubic }
                      NumberAnimation { to: 1; duration: Zenon.normal; easing.type: Zenon.ease }
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    enabled: step.isMark || step.canGo
                    onClicked: {
                      if (step.isMark) slot.openFaces();
                      else Clio.set(slot.noteId, "size",
                        Scribe.stepSize(slot.note.size, step.modelData[1]));
                    }
                  }
                }
              }
            }

            // The colours, as the note's own hue repeated in every other.
            Row {
              id: swatchRow
              anchors.right: close.left
              anchors.rightMargin: 14
              anchors.verticalCenter: parent.verticalCenter
              spacing: 7
              opacity: head.armed ? 1 : 0
              visible: opacity > 0.01 && head.roomForSwatches
              Behavior on opacity {
                NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
              }

              Repeater {
                model: Scribe.HUES

                delegate: Rectangle {
                  id: swatch
                  required property var modelData
                  width: 13
                  height: 13
                  radius: 6.5
                  color: Clio.ink(swatch.modelData)
                  readonly property bool worn: !!slot.note
                    && slot.note.hue === swatch.modelData
                  opacity: swatchHov.hovered || swatch.worn ? 1 : 0.55
                  scale: swatchHov.hovered ? 1.15 : 1
                  Behavior on scale {
                    NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
                  }

                  HoverHandler { id: swatchHov }

                  // The one it wears is ringed rather than missing from the
                  // row: a gap would move every other swatch each time you
                  // changed colour. A ring around the dot, not a border
                  // eating into it — at 13px a border left a speck of the
                  // colour it was meant to be pointing out.
                  Rectangle {
                    anchors.centerIn: parent
                    width: 19
                    height: 19
                    radius: 9.5
                    color: "transparent"
                    border.width: 1.5
                    border.color: Zenon.white
                    opacity: swatch.worn ? 0.9 : 0
                    Behavior on opacity {
                      NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    onClicked: Clio.set(slot.noteId, "hue", swatch.modelData)
                  }
                }
              }
            }

            Text {
              id: close
              anchors.right: parent.right
              anchors.rightMargin: 8
              anchors.verticalCenter: parent.verticalCenter
              text: "\uF00D"
              // Red for the press, not the hover: passing over it on the way
              // to a swatch is not a threat to the note.
              color: closeMa.pressed ? Zenon.red : Zenon.white
              opacity: head.armed ? 1 : 0
              visible: opacity > 0.01
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(15)
              Behavior on opacity {
                NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
              }

              MouseArea {
                id: closeMa
                anchors.fill: parent
                anchors.margins: -4
                onClicked: Clio.remove(slot.noteId)
              }
            }
          }
        }
      }
    }
  }
}

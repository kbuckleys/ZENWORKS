// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Its own file since 2026-10-08, out of TerminusWindow.qml, where it was an
// inline component. `term` is the terminus window; every place that makes
// one passes it (`term: root`).

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
  // the terminus window — passed in by whoever makes one. NOT `root`:
  // inside a delegate a property of that name shadowed the window's id
  // and bound to itself (2026-10-08)
  property var term: null
  id: tile
  property var entry: null
  // the filter being typed, lit in the name (TileName.mark)
  property string mark: ""
  // The grid is holding its pictures back to fade them in together — see
  // PaneGrid.held. `waited` marks a tile whose picture was still decoding
  // while it did, which is what keeps it hidden until the release.
  property bool held: false
  property bool waited: false
  readonly property bool thumbLoading: thumb.source != "" && thumb.status === Image.Loading
  onThumbLoadingChanged: if (tile.thumbLoading && tile.held) tile.waited = true
  // ── AND THE SCREENFUL GOES IN TURN ─────────────────────────────────
  // Held, the whole tile waits out of sight; let go, the tiles come up
  // one after another from the top (TileRise, picasso's gallery's too)
  // rather than all on one frame.
  property var riseView: null
  property int riseIndex: -1
  TileRise { id: rise }
  Component.onCompleted: if (tile.held) rise.hide()
  // a tile taken from the pool after the release must not stay hidden
  function riseReset() { if (!tile.held) rise.show(); }
  onHeldChanged: {
    if (tile.held) { if (tile.thumbLoading) tile.waited = true; rise.hide(); }
    else {
      tile.waited = false;
      if (tile.riseView) rise.start(tile.riseView, tile.riseIndex); else rise.show();
    }
  }
  // Resolved once per tile rather than three times inside the label's own
  // binding — see the note there. "" whenever the mode is off, so a grid
  // outside a repository builds the same string it always did.
  readonly property string gitState: (term.git && tile.entry)
    ? (term.gitMarks[tile.entry.path] || "") : ""
  property bool current: false
  property bool ticked: false
  property bool passive: false
  // A pending CUT, faded to say so — the same signal EntryRow gives a row.
  property bool dim: false
  // Whether this tile is in the grid the cursor moves through — the second
  // pane's grid draws tiles the rename verb was never about. Same property,
  // same meaning, as EntryRow.live.
  property bool live: false
  readonly property bool editing:
    term.renaming && tile.live && !!tile.entry
    && tile.entry.path === term.renamePath
  // the zoom this tile's pane is at, so two grids can be at two zooms
  property real tileZoom: term.thumbZoom

  // The POSITION rides along with the click, because the actions menu opens
  // where the pointer is and a signal that dropped it left right-click in
  // the grid doing nothing at all.
  signal chosen(bool right, bool shift, bool ctrl, real mx, real my)
  // middle click: this entry, in a tab of its own
  signal tabbed()
  signal opened()

  // true while a drag hovers THIS directory — see root.dropDirAt
  readonly property bool dropTarget: term.dropDir !== "" && !!tile.entry
    && tile.entry.isDir && term.dropDir === tile.entry.path

  // ── dragging this tile out ──────────────────────────────────────
  // The same shape as EntryRow's: a DragHandler with no target decides
  // WHEN, and root.beginDrag hands the drag itself to dragProxy, which
  // outlives the tile — see there.
  DragHandler {
    id: tileDrag
    target: null
    enabled: !!tile.entry && !tile.editing && !term.modal
             && !term.railHover && !term.railDragging
    onActiveChanged: {
      if (!tileDrag.active) return;
      term.beginDrag(tile.entry, tile.width / 2, tile.height / 2);
    }
  }

  // The same pair as a row, and the same fix — see EntryRow.cursorOnly.
  readonly property bool cursorOnly:
    tile.current && (tile.passive || term.markedCount > 0)

  // As the list's rows do — see EntryRow.tagList.
  readonly property var tagList: {
    if (!tile.entry) return [];
    const all = term.tagMarks[tile.entry.path];
    if (!all || all.length === 0) return [];
    return all.length > 4 ? all.slice(0, 4) : all;
  }


  // A cyan flare on the tile that was just opened.
  //
  // Opening from a grid gives no feedback of its own — the window that comes
  // up is somewhere else, and if it takes a moment there is nothing to say
  // the keypress landed. This says it, on the tile it landed on, and is gone
  // before it can become clutter.
  property real glow: 0
  Connections {
    target: term
    // Files only, the same rule the list rows follow. Opening a DIRECTORY
    // replaces the whole grid — the tile that flared is gone on the next
    // frame, so the flare fires into a view that no longer exists and reads
    // as the new directory flashing at you. A file leaves the grid standing,
    // which is the case the flare was for.
    function onOpenPulseChanged() {
      if (tile.current && !tile.passive
          && tile.entry && !tile.entry.isDir) flare.restart();
    }
  }
  // The flare in and out on smooth curves. It used to drive the border's
  // WIDTH (1 → 3 → 1), which can only move in whole pixels, so it went
  // up and down in visible steps. The ring below keeps one width and
  // the flare fades it instead.
  SequentialAnimation {
    id: flare
    NumberAnimation { target: tile; property: "glow"; to: 1; duration: 140;
                      easing.type: Easing.OutCubic }
    NumberAnimation { target: tile; property: "glow"; to: 0; duration: 620;
                      easing.type: Easing.InOutSine }
  }

  Rectangle {
    anchors.fill: parent
    anchors.margins: 4
    radius: 6
    // NO CURSOR FILL: that is SelectCell, one rectangle the view slides
    // between tiles. The tick stays, because a tick is a property of the
    // FILE rather than of where the cursor happens to be — and the border
    // below stays too, because a tile has always carried one.
    // A tick is marked on the picture itself now (MarkRing, in thumbBox),
    // not washed over the whole cell.
    color: "transparent"
    // ── THE OUTLINE MOVED TO THE CURSOR ITSELF ────────────────
    // The sliding bar is BEHIND the tiles, which is right for a
    // glyph — it shows around it — and useless under a photograph,
    // which covers the cell. So on a thumbnail the only mark left
    // was this border, and a border drawn per tile cannot travel:
    // the cursor slid invisibly and the outline teleported.
    //
    // SelectCell carries the cyan outline now, so the thing you can
    // actually see on a grid of pictures is the thing that moves.
    // What stays here is the outline for the case the bar stands
    // down for — passive pane, or anything ticked — and the flare,
    // which is about the tile that was OPENED rather than the one
    // under the cursor.
    // A SPECIAL CASE of the one-border rule, on purpose: the open flare
    // swells the ring and lights it, and a flat 1px of the shared border
    // was the flare gone. At rest it is Zenon.border like everything else.
    border.width: (tile.current && tile.cursorOnly) ? 1 : 0
    // As a row's — see EntryRow's border.
    border.color: !tile.passive ? Zenon.cyan : Zenon.border

    // the flare itself, over the tile's own fill
    // the flare: a wash and a 3px ring, faded by `glow`
    Rectangle {
      anchors.fill: parent
      radius: parent.radius
      visible: tile.glow > 0.003
      opacity: tile.glow
      color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.18)
      border.width: 3
      border.color: Zenon.cyan
    }
  }
  HoverHandler {
    id: tileHov
    onHoveredChanged: {
      if (hovered) term.hoverRow = true;
      else if (term.hoverRow) term.hoverRow = false;
    }
  }

  Item {
    id: thumbBox
    anchors.top: parent.top
    anchors.topMargin: 12
    anchors.horizontalCenter: parent.horizontalCenter
    width: parent.width - 24
    // ticked, the picture steps back a little inside its ring (MarkRing)
    scale: tile.ticked ? 0.9 : 1
    Behavior on scale { NumberAnimation { duration: Zenon.slow; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
    // 68, not 62. The reserve has to hold the 8px gap, two lines of
    // label and the 4px the highlight is inset by — and the label
    // went from 15px to 16px, which is exactly enough for a name
    // long enough to wrap to overrun the bottom of its own tile.
    height: parent.height - 68

    // Rounded corners, and they belong to the PICTURE rather than
    // to the box holding it. The image is letterboxed inside
    // thumbBox — a portrait photo leaves a bar down each side — so
    // rounding the box would have curved empty space and left the
    // picture's own corners square.
    //
    // ClippingRectangle rather than `clip: true`: an item's clip is
    // a rectangle, always, and never follows a radius.
    //
    // The aspect ratio comes from a sizer image that is never drawn —
    // see thumbNat just below, and the note on it for why neither the
    // painted size NOR the drawn image's implicit size can be read here.
    // ── HOW BIG IT NATURALLY IS, ASKED OF SOMETHING NEVER DRAWN ──────
    // The comment below used to say the implicit size was safe because it
    // is not the painted size. It is not safe: `thumb` fills thumbClip, and
    // under PreserveAspectFit an Image's IMPLICIT size is kept in step with
    // its explicit one — so thumbClip sized itself from a number that was
    // derived from thumbClip. Qt said so on every load:
    //
    //     Binding loop detected for property "width"
    //
    // This one is never sized, never drawn and never anchored to anything,
    // so its implicit size is the decoded size and nothing else. Same source
    // and same sourceSize as the real one, which means Qt serves both out of
    // a single decode — it costs a QML item, not a second copy of the
    // picture. The same trick quick look uses; see lookLayer.lookNat.
    Image {
      id: thumbNat
      visible: false
      asynchronous: true
      source: thumb.source
      sourceSize.width: thumb.sourceSize.width
      sourceSize.height: thumb.sourceSize.height
    }

    ClippingRectangle {
      id: thumbClip
      anchors.centerIn: parent
      // ── IT FADES IN, SO THE GLYPH DOES NOT FLASH ─────────────────
      // An uncached picture shows its glyph for the moment it takes to
      // decode, and then the photograph cut in over it: a scroll through
      // a directory of pictures blinked a row of icons at you. Now the tile
      // stays empty while it decodes — the glyph is not drawn for a tile
      // with a picture coming — and the picture arrives over a short
      // fade, so it reads as developing rather than popping in.
      //
      // IN ONLY. Going out is immediate — a source change or a recycled
      // tile must not show the last picture dissolving over the next —
      // and a thumbnail already in the cache is Ready on the frame the
      // tile is made, which a Behavior does not animate, so a warmed
      // directory still appears at once.
      opacity: thumb.status === Image.Ready && !(tile.waited && tile.held) ? 1 : 0
      Behavior on opacity {
        enabled: thumbClip.opacity < 1
        NumberAnimation { duration: Zenon.normal; easing.type: Easing.OutCubic }
      }
      visible: thumbClip.opacity > 0
      color: "transparent"
      radius: Zenon.windowRadius

      readonly property real ar:
        thumbNat.implicitWidth > 0 && thumbNat.implicitHeight > 0
          ? thumbNat.implicitWidth / thumbNat.implicitHeight : 1
      width: Math.max(1, Math.min(thumbBox.width,
        thumbBox.height * thumbClip.ar))
      height: Math.max(1, Math.min(thumbBox.height,
        thumbBox.width / thumbClip.ar))

      Image {
        id: thumb
        anchors.fill: parent
        opacity: tile.dim ? 0.45 : 1
        // the cached 256px PNG if the batch has made it, the original
        // otherwise — so a directory is never blank while it renders, it
        // just gets cheaper a moment later
        // A video has no thumbnail until ffmpeg has pulled a frame
        // out of it, so unlike a picture there is nothing to fall back
        // to — it shows its glyph until the batch lands.
        // Zoomed past the cache, a PICTURE goes back to the original.
        //
        // The cached thumbnails are 480px, which is generous at the
        // default tile size and not enough at the top of the zoom
        // range — a 600px tile showing a 480px PNG is visibly soft,
        // and zooming in is precisely when you are looking closely. So
        // above the cache's own resolution the original file is decoded
        // instead, at the size actually needed. A VIDEO has no such
        // fallback: its thumbnail is a frame ffmpeg had to pull out of
        // it, so it keeps the cached one at any zoom.
        readonly property bool big: thumbBox.width > 480
        // Whether what is on screen is a POOL THUMBNAIL rather than the
        // original file. It decides the decode size below, and it is the
        // same test the source binding makes.
        readonly property bool pooled: !!tile.entry
          && (!!term.thumbFile[tile.entry.path] || thumb.onDisk !== "")
          && !(thumb.big && thumb.original)
        // ── THE INDEX ANSWERS FOR THE TILE TOO ─────────────────
        // thumbFile is filled by makeThumbs, which runs a beat after a
        // listing — and for the passive half of a split it did not run at
        // all. A tile made in that beat found nothing mapped, decoded the
        // ORIGINAL (a 24–48 MP photograph, one at a time on Qt's single
        // reader thread), and once that landed held it for the visit: a
        // directory whose thumbnails were all on disk filled in as slowly
        // as if none were, and again after every tab into it (user,
        // 2026-10-09). The index on disk is right there and costs a lookup.
        readonly property string onDisk: {
          if (!tile.entry || term.thumbFile[tile.entry.path]) return "";
          const s = term.indexHit(tile.entry);
          return s !== "" && !Thumbs.isNone(s) ? s : "";
        }
        // A picture Qt can open itself, and so can be decoded from the
        // original when zoomed past the cache. One it cannot is as
        // cache-only as a film: its original at that zoom was an Image
        // that failed and took the thumbnail with it.
        readonly property bool original: !!tile.entry
          && Terminus.isImage(tile.entry.name) && !term.needsRender(tile.entry)
        source: {
          // `entry` is declared null and, until the listing became a model
          // the views are told about rather than handed, could never be one.
          // A delegate now outlives a single listing, so it can be asked to
          // draw in the instant between a row leaving and the view being
          // told — guarded here rather than left to throw.
          if (!tile.entry) return "";
          // Switched off, a tile shows the glyph it shows before anything
          // has decoded — see root.thumbsOn.
          if (!term.thumbsOn) return "";
          const pic = thumb.original;
          // a video's frame, an audio file's cover, a document's page and
          // a picture Qt cannot read are all CACHE-ONLY: there is no
          // original to fall back to
          const cached = !pic && term.thumbKind(tile.entry) !== "";
          if (!pic && !cached) return "";
          // ── ONE PICTURE PER VISIT ──────────────────────────────
          // On a first visit the tile shows the original (Qt decodes it
          // at tile size) while the pool's thumbnail is being made — and
          // the moment that landed the source swapped: back to Loading,
          // the clip's opacity to nothing, the same picture decoded again
          // and faded back in. A screenful blinking in turn was what a big
          // directory looked like loading. A tile that has SHOWN the original
          // keeps it; the pooled one is for the next visit.
          if (pic && thumb.heldOriginal === tile.entry.path)
            return Strings.fileUrl(tile.entry.path);
          const ready = term.thumbFile[tile.entry.path] || thumb.onDisk;
          if (ready && !(thumb.big && pic))
            return "file://" + ready;
          return pic ? Strings.fileUrl(tile.entry.path) : "";
        }
        property string heldOriginal: ""
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        // Decode at the size drawn, not at a fixed 320: below that it
        // was decoding more than it showed, above it, less.
        //
        // ROUNDED UP TO A STEP, because the decode size is half of the
        // cache key and the two panes are NEVER the same width. The split
        // gives the left half floor(body * frac) and the right half what is
        // left after the divider — one pixel apart — so above the 320 floor
        // the same file was asked for at 376 and at 375. Qt treats those as
        // two different images: it decoded both, held both, and every step
        // across the divider was a guaranteed miss on the one it needed.
        //
        // A step of 64 puts both panes, and every zoom inside the step, on
        // ONE key. It only ever rounds UP, so nothing is decoded smaller
        // than it is drawn and no tile loses resolution — it just stops
        // asking for a resolution nobody can tell apart from its neighbour.
        // ── A POOL THUMBNAIL DECODES AT ITS OWN SIZE ─────────────
        // Not at the tile's. Qt caches a decoded image under (url,
        // sourceSize), so tying the size to the tile meant three things,
        // all bad: every zoom step crossed a 64px bucket and re-decoded
        // the whole screen; two panes of different widths could not
        // share a decode of the same file; and nothing could warm the
        // cache ahead of time, because the size a tile WILL ask for
        // depends on a zoom that is remembered per directory.
        //
        // Pinned to the pool's own size, every one of those goes away.
        // It is not more work either: the thumbnails are at most 480 in
        // either axis, so PreserveAspectFit at 480 decodes them at
        // exactly their natural size — no scaling at all, where before
        // Qt scaled every one of them on the way in.
        //
        // The ORIGINAL keeps the old rule: you are zoomed past what the
        // cache holds, which is the one time the tile's own size is the
        // right question.
        sourceSize.width: thumb.pooled ? Thumbs.size()
          : Math.max(320, Math.ceil(thumbBox.width / 64) * 64)
        sourceSize.height: thumb.pooled ? Thumbs.size()
          : Math.max(320, Math.ceil(thumbBox.height / 64) * 64)
        // A remembered name the pool no longer honours — see thumbMiss.
        // Only when the source WAS the thumbnail: an error on the
        // original is a format Qt cannot read, which is a different
        // story and noteBlind's.
        onStatusChanged: {
          if (thumb.status === Image.Error && tile.entry)
            term.thumbMiss(tile.entry);
          // a pool thumbnail on screen: kept decoded for the next time
          // this tile is made (Thumbnails.keepThumb)
          if (thumb.status === Image.Ready && thumb.pooled && term.keepThumb)
            term.keepThumb(thumb.source);
          // the original, on screen: hold it (see the source above)
          if (thumb.status === Image.Ready && tile.entry && thumb.original
              && String(thumb.source).indexOf("file://" + Thumbs.dir()) !== 0)
            thumb.heldOriginal = tile.entry.path;
        }
      }
    }

    // ── THE GLYPH IS THE FALLBACK, NOT THE PLACEHOLDER ─────────────
    // It used to stand in for a picture until the picture decoded, and
    // that stand-in is the flash: a row of icons, then photographs. A
    // tile with a picture on the way now shows nothing until it fades
    // in — see thumbClip. The glyph is for a tile with no picture to
    // show: not an image, thumbnails off, a video the batch has not
    // reached yet, or a file Qt could not read.
    //
    // A DIRECTORY WITH PICTURES IN IT IS DRAWN AS THEM — see FolderCover. One
    // with none, or with thumbnails off, keeps the glyph.
    FolderCover {
      id: tileCover
      anchors.fill: parent
      live: term.thumbsOn && !!tile.entry && tile.entry.isDir
      path: tile.entry && tile.entry.isDir ? tile.entry.path : ""
      stamp: tile.entry ? (tile.entry.mtime || 0) : 0
      glyph: tile.entry ? tile.entry.glyph : ""
      ink: term.inkFor(tile.entry)
      dim: tile.dim ? 0.45 : 1
    }

    Text {
      anchors.centerIn: parent
      visible: (thumb.source == "" || thumb.status === Image.Error)
        && !tileCover.shown
      opacity: tile.dim ? 0.45 : 1
      text: tile.entry ? tile.entry.glyph : ""
      color: term.inkFor(tile.entry)
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Math.round(64 * tile.tileZoom)
    }

    // Ticked: round the picture when there is one, the directory's cover
    // when it has one (3:2, not square — a square cut through the mosaic's
    // sides), else a square about the glyph.
    MarkRing {
      readonly property bool pic: thumbClip.visible
      readonly property bool dir: !pic && tileCover.shown
      readonly property real sq: Math.min(thumbBox.width, thumbBox.height)
      width: pic ? thumbClip.width : dir ? Math.round(tileCover.coverW) : sq
      height: pic ? thumbClip.height : dir ? Math.round(tileCover.coverH) : sq
      x: pic ? thumbClip.x : Math.round((thumbBox.width - width) / 2)
      y: pic ? thumbClip.y : Math.round((thumbBox.height - height) / 2)
      on: tile.ticked
    }

    // THE TAGS ARE NOT HERE ANY MORE — they ride in the name's lead, beside
    // the bookmark. Anchored to this box's corner they hung off the TILE's
    // corner, which a glyph or a portrait picture is nowhere near, and a
    // tag sat out in the air fifty pixels from the thing it marked.
  }

  // TileName, not Text: see TileName.qml for why a long name needs
  // shortening done by hand to keep its extension and its ellipsis.
  TileName {
    anchors.top: thumbBox.bottom
    anchors.topMargin: 8
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: 8
    horizontalAlignment: Text.AlignHCenter
    id: tileName
    visible: !tile.editing
    // THE BADGE READS WITH THE NAME. It used to sit in the corner of the
    // thumbnail, which put it over the picture and a long way from the thing
    // it qualifies. Inline it has to survive centring, wrapping to two lines
    // and eliding — which a Row beside the label would not — so it is part
    // of the same string, coloured with StyledText. The name is escaped
    // because it is now markup: an ampersand in a filename would otherwise
    // eat the rest of the label.
    // The git mark leads, because it is about the file rather than about
    // your relationship to it, and because a row of tiles reads left to
    // right. Same inline treatment as the bookmark below and for the same
    // reason: a badge in the corner of the thumbnail sits over the picture
    // and a long way from the thing it qualifies.
    // in the glyph face, marks AND the spaces after them: in a proportional
    // shell face those spaces all but vanished (Zenon.glyphFace)
    lead: "<font face=\"" + Zenon.glyphFace + "\">" + (tile.gitState !== ""
            ? "<font color=\"" + Zenon.hex(term.gitInk(tile.gitState)) + "\">"
              + Terminus.gitMark(tile.gitState) + "</font>&#160;&#160;" : "")
          + (tile.entry && term.isBookmarked(tile.entry.path)
            // NON-BREAKING spaces: this is markup now, and StyledText
            // collapses a run of ordinary ones to a single space, so the gap
            // asked for was never the gap drawn.
            ? "<font color=\"" + Zenon.hex(Zenon.sand) + "\">\uF02E</font>&#160;&#160;" : "")
          // Tags last, nearest the name, one coloured mark each — the
          // list's tag column, said inline for the same reason as above.
          + tile.tagList.map((t) => "<font color=\"" + Zenon.hex(term.tagInk(t))
              + "\">\uF02B</font>&#160;").join("")
          + (tile.tagList.length > 0 ? "&#160;" : "") + "</font>"
    name: tile.entry ? tile.entry.name : ""
    mark: tile.mark
    // the same mark a list row carries — a link was the one thing the
    // grid could not tell apart from the file it points at
    trail: tile.entry && tile.entry.isLink
      ? "<font face=\"" + Zenon.glyphFace + "\">&#160;\u2192</font>" : ""
    opacity: tile.dim ? 0.5 : 1
    color: term.nameInkFor(tile.entry)
    font.family: Zenon.face
    // the same weight as every other name: the cursor's ground already
    // says which one it is, and bold only made the name jump wider
    font.weight: Font.Medium
    // NOT scaled by zoom, unlike the tile and the glyph above it.
    // Zoom in a thumbnail view is about how big the PICTURES are;
    // scaling the filenames with them meant zooming out to fit more
    // on screen also shrank the labels towards unreadable, and
    // zooming in to inspect an image blew its name up to a headline.
    // The 62px the tile reserves for this text is a constant too, so
    // two lines always fit at every zoom.
    font.pixelSize: Zenon.px(14)
  }

  // ── renaming, on the tile ───────────────────────────────────────
  // The grid needs its own field: EntryRow's lives in a row and this is not
  // one. Without it `a` in a thumbnail view made the file and left you with
  // no way to name it, and `r` did nothing at all — the two views disagreed
  // about whether renaming existed.
  // Behind a Loader, for the reason EntryRow's is — a grid of thumbnails
  // keeps a lot of tiles alive and only one of them is ever being renamed.
  EditRing {
    target: tileEditBox
    on: tile.editing
    fontPx: 14
    padX: 2
    // the tile's name has room around it, unlike a row
    maxH: 28
    centered: true
  }
  Loader {
    id: tileEditBox
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: 6
    anchors.rightMargin: 6
    anchors.top: tileName.top
    height: tileName.height
    active: tile.editing
    sourceComponent: tileEditField
  }

  Component {
    id: tileEditField

    TextInput {
    id: tileEdit
    anchors.fill: parent
    horizontalAlignment: Text.AlignHCenter
    color: Zenon.white
    selectionColor: Zenon.selBg
    selectedTextColor: Zenon.white
    font.family: Zenon.face
    font.weight: Font.Bold
    // Whatever tileName is: a name that changed size the moment you
    // started renaming it would be jumping under the cursor.
    font.pixelSize: Zenon.px(14)
    clip: true

    cursorDelegate: Caret { field: tileEdit }

    property bool hadFocus: false

    Component.onCompleted: {
      tileEdit.hadFocus = false;
      // A CREATION STARTS BLANK. A rename starts with the name it is
      // about — you are editing something that exists, and the old name is
      // the thing you are editing. A creation is not editing anything: the
      // generic name is a placeholder the window picked, and presenting it
      // selected means the first thing you do is throw it away. Blank is the
      // same gesture with nothing to delete first.
      //
      // Return on a blank field keeps the generic name — commitRename
      // already reads an empty answer as "the one it arrived with", which is
      // the whole point of it arriving with one.
      const madeNow = term.freshPath !== "" && tile.entry
        && tile.entry.path === term.freshPath;
      tileEdit.text = madeNow ? "" : (tile.entry ? tile.entry.name : "");
      if (!madeNow) {
        const stem = Terminus.stem(tileEdit.text);
        tileEdit.select(0, stem.length > 0 ? stem.length : tileEdit.text.length);
      }
      tileEdit.forceActiveFocus();
      tileClaim.tries = 0;
      tileClaim.restart();
    }

    // asks until it has the keyboard — see EntryRow's editClaim
    Timer {
      id: tileClaim
      interval: 40
      repeat: true
      property int tries: 0
      onTriggered: {
        if (!tile.editing || tileEdit.activeFocus || tileClaim.tries++ > 12) {
          tileClaim.stop();
          return;
        }
        tileEdit.forceActiveFocus();
      }
    }

    Keys.onReturnPressed: (e) => {
      e.accepted = true; term.commitRename(tile.entry, tileEdit.text);
    }
    Keys.onEnterPressed: (e) => {
      e.accepted = true; term.commitRename(tile.entry, tileEdit.text);
    }
    Keys.onEscapePressed: (e) => { e.accepted = true; term.endRename(true); }
    onActiveFocusChanged: {
      if (activeFocus) { tileEdit.hadFocus = true; return; }
      // see EntryRow's note: still claiming is not yet finished
      if (tile.editing && tileEdit.hadFocus && !tileClaim.running)
        term.endRename(false);
    }
    }
  }

  // The tile a menu is open about (HeldRing.qml), as a disk row is.
  HeldRing {
    anchors.fill: parent
    anchors.margins: 4
    z: 5
    radius: 6
    on: !!tile.term && tile.term.sideMenuAt === tile
  }

  // Lit while a drag is over this directory — the grid's answer to the same
  // question the list row answers with its own outline.
  Rectangle {
    anchors.fill: parent
    anchors.margins: 4
    z: 6
    visible: tile.dropTarget
    color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.12)
    border.width: 1
    border.color: Zenon.border
    radius: 6
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    enabled: !tile.editing
    // ALL FIVE arguments, always. The signal is typed, and emitting it with
    // three left QML raising "Insufficient arguments" before the handler
    // ran — so every click in the grid did nothing at all while hovering
    // still worked, which is a very quiet way to break a view.
    //
    // Middle click is its own signal rather than a sixth argument: adding
    // one to a typed signal means every emit has to grow with it, and that
    // is exactly the mistake the note above is about.
    onClicked: (m) => {
      if (m.button === Qt.MiddleButton) { tile.tabbed(); return; }
      tile.chosen(m.button === Qt.RightButton,
                  (m.modifiers & Qt.ShiftModifier) !== 0,
                  (m.modifiers & Qt.ControlModifier) !== 0,
                  m.x, m.y);
    }
    onDoubleClicked: tile.opened()
  }
}

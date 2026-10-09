// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// TERMINUS' QUICK LOOK — its own layer window over the screen. Lived inside
// TerminusWindow.qml until 2026-10-08, when it was the first piece taken
// out of that 29,000-line file (see the note there). `root` is the terminus
// window, so everything in here that says root.x reads what it always did;
// `card`, `facts` and `previewBody` are the three items of the window's own
// it measures itself against. What the window reaches back in for — the
// card itself, its scroll, the player, the picture's natural size — is
// offered as aliases.

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick.Effects
import QtMultimedia
import "../morpheus"
import "../picasso"
import "../oracle"
import "terminus.js" as Terminus
import "../morpheus/icons.js" as Icons
import "../morpheus/thumbs.js" as Thumbs
import "tags.js" as Tags
import "collections.js" as Coll

PanelWindow {
  id: lookLayer
  required property var root
  property Item card: null
  property Item facts: null
  property Item previewBody: null
  readonly property alias look: look
  readonly property alias lookScroll: lookScroll
  // the player, once made — see playerSlot; a stand-in with its shape until
  // then, so everything that reads one reads it unchanged
  readonly property var lookPlayer: playerSlot.item ? playerSlot.item : playerSlot.idle
  readonly property alias lookNat: lookNat
  visible: root.looking || look.opacity > 0.01
  screen: root.screen
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  WlrLayershell.namespace: "terminus-quicklook"
  anchors { top: true; bottom: true; left: true; right: true }

  Rectangle {
    id: look
    anchors.fill: parent
    z: 15
    visible: look.opacity > 0.01
    opacity: root.looking ? 1 : 0
    // NO SCRIM AT ALL, and that is also what stops the blur.
    //
    // This surface is a layer now, and rules.lua blurs every layer namespace
    // with `ignore_alpha = 0.5` — so a 0.82 black wash was above the
    // threshold and hyprland blurred the desktop through it. Transparent is
    // below it, so the dim and the blur leave together and the picture sits
    // on the desktop rather than on a darkened copy of it.
    color: "transparent"
    // Asymmetric, the rule every card in this window follows: arriving takes
    // the full normal, leaving takes the fast. One duration for both made
    // opening and dismissing the same event played twice.
    Behavior on opacity {
      NumberAnimation {
        duration: root.looking ? Zenon.normal : Zenon.fast
        easing.type: Zenon.ease
      }
    }

    readonly property var row: root.currentRow()

    // THE STEP IS A NEW FILE, AND IT MAY NEED SOMETHING MADE. h and l move
    // the cursor in the listing underneath, so this is where a step lands —
    // there is no other signal for it. lookFetch is idempotent, and this
    // binding re-evaluates for reasons that are not steps, so a row that
    // already has everything falls straight through.
    // ── THE PATH, NOT THE OBJECT ──────────────────────────────────
    // `row` is root.currentRow(), which hands back a NEW object every
    // time the listing is rebuilt — a directory watcher firing is
    // enough. Clearing the latched tree on every one of those emptied
    // the archive viewer while you were reading it, which is the other
    // half of the scrolling complaint: not a slow scroll, a scroll
    // that kept losing its place because the model kept vanishing.
    //
    // Only a change of PATH means a different file.
    property string lastPath: ""
    onRowChanged: {
      // the directory card's walked facts — see askFacts
      Qt.callLater(look.docOpen);
      Qt.callLater(look.askFacts);
      const p = look.row ? look.row.path : "";
      if (p !== look.lastPath) {
        look.lastPath = p;
        look.treeRows = [];
        look.dirRows = [];
        lookTree.contentY = 0;
        lookDir.contentY = 0;
      }
      if (root.looking) root.lookFetch();
    }

    // Take the pane's rows when they are about THIS file. Called both
    // when they arrive and when quick look finds them already in hand —
    // see lookFetch, which skips the read in that case and used to
    // leave the viewer with nothing to show.
    function syncTree() {
      if (look.arc && root.previewKind === "archive"
          && root.previewTree.length > 0)
        look.treeRows = root.previewTree;
    }

    // A READ IS IN FLIGHT FOR THIS ROW. The apology below is an answer
    // about the file, and while bat is still running there is no answer
    // yet — without this, every text file opened from a list said there
    // was nothing to show for the fifty milliseconds before its text
    // arrived. The picture side has said the same thing all along; this is
    // look.pending for the other half.
    readonly property bool reading:
      !!look.row && root.previewFor === look.row.path

    // ── HOW WIDE THE CONTENTS WANT TO BE ───────────────────
    // Measured, not guessed, and measured once per directory rather than
    // once per row: the longest name by CHARACTER COUNT, then that one
    // string laid out for its real width. The rows themselves cannot
    // be asked — the list virtualises them, so the long one is very
    // often not built.
    readonly property string dirWidest: {
      let best = "";
      for (let i = 0; i < look.dirRows.length; ++i) {
        const nm = look.dirRows[i].name || "";
        if (nm.length > best.length) best = nm;
      }
      return best;
    }
    TextMetrics {
      id: lookDirName
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Math.round(16 * root.zoom)
      text: look.dirWidest
    }
    // One cell of the contents: the glyph column, its gap, the name.
    readonly property real dirCellW:
      Math.round(22 * root.zoom) + 6 + Math.ceil(lookDirName.width)

    // The caption bar's height, named on the OVERLAY rather than on the bar:
    // the picture's height subtracts it and the panel's height adds it, and
    // the bar is anchored inside the panel, so asking the bar itself puts
    // the panel's own geometry in the middle of both sums.
    readonly property real capH: 34

    // ── HOW BIG THE PICTURE IS, ASKED OF SOMETHING THAT IS NOT DRAWN ──
    // PreserveAspectFit keeps an Image's IMPLICIT size in step with its
    // explicit one — set a width and the implicit height follows it. So
    // asking the picture that is being drawn how big it naturally is, in
    // order to decide how big to draw it, is a circle, and Qt says so.
    //
    // This one is never sized, so its implicit size is the decoded size and
    // nothing else. Same source and same sourceSize as the real one, which
    // means Qt serves both out of one decode — it costs a QML item, not a
    // second copy of the picture.
    Image {
      id: lookNat
      visible: false
      asynchronous: true
      sourceSize.width: Math.round(look.width * 0.8)
      sourceSize.height: Math.round(look.height * 0.86)
      source: look.src
      // The same lesson the preview pane learns — see root.noteBlind.
      // Taken here as well because quick look can be the first thing to
      // meet a format, opened straight onto a file from a search.
      onStatusChanged: {
        if (status !== Image.Error) return;
        const rr = look.row;
        if (rr && !rr.isDir && Terminus.isImage(rr.name)) {
          root.noteBlind(rr.name);
          root.wantBig(rr);
        }
      }
    }

    // Capped at 1, because a small picture blown up to fill the window is
    // not a preview of it.
    readonly property real fitScale: {
      const iw = lookNat.implicitWidth;
      const ih = lookNat.implicitHeight;
      if (iw <= 0 || ih <= 0) return 0;
      // ── A FILM MAY BE SCALED UP; A PICTURE MAY NOT ────────────────
      // The cap exists because a small picture blown up to fill the panel
      // is not a preview of it — you would be looking at its pixels.
      //
      // For a film the number being measured is not the film, it is the
      // CACHED FRAME pulled out of it, which is a few hundred pixels wide
      // whatever the source is. Capping against that sized the panel to the
      // thumbnail and played a 4K video inside a 480px box. The thumbnail
      // is only being asked for the aspect ratio here; VideoOutput draws
      // the real frames at whatever size it is given.
      // A PDF's page is the same kind of case: the image measured here is
      // the pane's small 72dpi render, asked only for its shape — the page
      // you read is rendered sharp at the size it is drawn (see lookPage),
      // so it fills the same 80% as everything else instead of sitting at
      // the size of a thumbnail.
      const cap = (look.vid || look.doc) ? Infinity : 1;
      return Math.min(cap, (look.width * 0.8 - look.sideW) / iw,
                      (look.height * 0.86 - look.capH) / ih);
    }
    readonly property real shotW:
      Math.round(lookNat.implicitWidth * look.fitScale)
    readonly property real shotH:
      Math.round(lookNat.implicitHeight * look.fitScale)

    // ── THE SHAPE IT HAD WHILE THE NEXT ONE IS DECODING ───────────────
    // Stepping to the next picture clears the old one instantly and the new
    // one arrives a frame or two later. In between, shotW is 0, the panel
    // has nothing to be the size of, and it fell back to the size of a card
    // with no picture in it — so every step went small, then big. With the
    // resize eased that was a shrink and a grow; without it, a flash. Either
    // way it reads as the panel closing and reopening, which is the one
    // thing it is not doing.
    //
    // So the last good size is kept and worn through the gap. The panel
    // changes size once, when there is something to change it for.
    property real heldW: 0
    property real heldH: 0
    function holdSize() {
      if (look.shotW > 0 && look.shotH > 0) {
        look.heldW = look.shotW;
        look.heldH = look.shotH;
      }
    }
    onShotWChanged: look.holdSize()
    onShotHChanged: look.holdSize()

    // ── READING THE THING, RATHER THAN LEAVING IT ─────────────────────
    // Three lines a press, which is what a wheel notch moves and what the
    // hand expects from an arrow key in a document. Clamped at both ends so
    // holding a key at the bottom of a file does not wind contentY off into
    // space and leave the view blank on the way back.
    //
    // Silently nothing when there is no text pane: over a picture there is
    // nothing to scroll, and a key that quietly does nothing is better than
    // one that does something else instead.
    readonly property int scrollStep: 3 * 14 + 12

    // Whether there is anything to scroll — a short file fits and its keys
    // would do nothing, so the bar does not offer them.
    // Either reading surface: a document, or an archive's tree.
    readonly property bool scrollable:
      (lookScroll.visible && lookScroll.contentHeight > lookScroll.height)
      || (lookTree.visible && lookTree.contentHeight > lookTree.height)
      || (lookDir.visible && lookDir.contentHeight > lookDir.height)

    function scrollBy(n) {
      const v = lookScroll.visible ? lookScroll
        : (lookTree.visible ? lookTree
           : (lookDir.visible ? lookDir : null));
      if (!v) return;
      const max = Math.max(0, v.contentHeight - v.height);
      v.contentY = Math.max(0, Math.min(max, v.contentY + n * look.scrollStep));
    }

    // The row WANTS a picture and has not got one yet — as against a text
    // file, which never will and should collapse to its own size at once.
    readonly property bool pending: look.src !== ""
      && lookShot.status !== Image.Ready && lookShot.status !== Image.Error

    // ── ASKED OF THE FILE, NOT OF THE PREVIEW PANE ───────────────────
    // This read root.previewKind, which is the miller column's state — and
    // the miller column only exists in the columns view. In a list or a
    // grid nothing had computed it, so previewKind was "none" and every
    // picture opened as "nothing to show for this one".
    //
    // The row itself always knows, in every view, by the same functions the
    // grid's tiles use.
    // ── ASKED OF A FILE, AND ONLY A FILE ────────────────────────────
    // A directory can be quick-looked now, and a directory may be
    // called anything — "shots.png" is a perfectly ordinary directory
    // name. Without this the viewer would hand one to an Image and
    // draw a broken picture instead of what is inside it.
    readonly property bool isFile: !!look.row && !look.row.isDir
    readonly property bool pic:
      look.isFile && Terminus.isImage(look.row.name)
    readonly property bool framed: look.isFile
      && (Terminus.isVideo(look.row.name) || Terminus.isAudio(look.row.name))
    // A rendered page rather than a cached frame, so it is its own case.
    readonly property bool doc:
      look.isFile && Terminus.isPdf(look.row.name)
    // ── THE TWO THE PANE COULD SHOW AND THIS COULD NOT ──────────────
    // An archive has a tree and a typeface has a specimen, and quick
    // look drew "no preview available" over both — the one place you
    // would actually ask what is in a zip before opening it.
    //
    // Asked of the ROW, like the three above, so they are true in a
    // list and a grid where previewKind has never been computed. The
    // tree additionally needs rows to have arrived, which is the one
    // thing the name cannot say.
    readonly property bool arc:
      look.isFile && Terminus.isArchive(look.row.name)
    readonly property bool face:
      look.isFile && Terminus.isFont(look.row.name)
    readonly property bool folder: !!look.row && look.row.isDir
    // ── WHOSE TEXT ─────────────────────────────────────────────────
    // previewText is the PANE's, and it holds whatever the pane last read
    // until something replaces it. Quick look drew it whenever no picture
    // was ready — so opening on a PNG showed the text file you had been
    // on (your todo, in the capture) for the nine frames the picture took
    // to decode, under a caption already naming the picture.
    //
    // Text counts only when it is about THIS row, and never for the kinds
    // that are pictures of something rather than words.
    readonly property bool hasText: root.previewText !== ""
      && !!look.row && root.previewShown === look.row.path
      && !look.pic && !look.framed && !look.doc
      // nor a directory or a typeface, which have views of their own that
      // the text was drawn straight over — Documents with a package list
      // printed across its facts, in Buck's screenshot
      && !look.folder && !look.face
    // Its rows, latched for the same reason the archive's are — see
    // treeRows. previewRows belongs to the pane and the pane keeps
    // recomputing it.
    property var dirRows: []
    // ANY directory, including one holding nothing. It used to mean "has
    // rows to show", because an empty directory's card was the word
    // Empty and 120px was plenty for it. Now the card is the FACTS,
    // which an empty directory has as many of as a full one — gated on
    // the row count it fell through to emptyH and cut them in half.
    readonly property bool listing: look.folder

    // ── A DIRECTORY IS TWO THINGS AT ONCE ────────────────────────────
    // What it CONTAINS and what it IS. The preview used to answer only
    // the first, as one long column — which is the same answer the
    // listing behind it already gives, and says nothing about the
    // directory itself. Split: the left half is the directory, the right
    // half is its contents.
    //
    // The facts are the ones that cost nothing. A directory's own
    // `size` is its inode's, not its contents', and the real number is
    // a du away — that is what the properties sheet's Calculate size
    // is for, and it is not worth a process behind a keypress that is
    // meant to be instant.
    // ── SEVEN ROWS, ACROSS EXACTLY THE FACTS ────────────────
    // The pitch is not a number, it is a division: the height the
    // facts take, in seven. At a fixed 22px the contents overran the
    // facts beside them — nine rows against four pairs, the first
    // starting above "items" and the ninth clipped by the caption —
    // so the two halves read as two unrelated lists that happened to
    // share a card. Divided, they start and finish together.
    readonly property real dirRowH: look.dirBodyH / look.dirFit

    // Two columns once one would not fit, never more: past two, the
    // names are too narrow to read and the thing stops being a preview
    // and becomes a listing with a scrollbar.
    // ── THE FACTS SET THE HEIGHT; THE CONTENTS FIT INTO IT ────────
    // Not the other way round. Sized to its contents the card was a
    // listing with a scrollbar — forty rows tall for a directory of forty
    // things, and a different height for every directory you stepped
    // through. The left half is the same size whatever the directory is,
    // so it is what the card should measure, and the contents get two
    // columns and a scroll to live inside it.
    //
    // The facts' INK, which is what the contents line up against —
    // not the column's height, which carries 10px of padding below
    // the last fact that no fact is drawn in.
    //
    // No floor any more. The floor existed to keep the card as tall
    // as it was when the glyph sat in this column, and a card that
    // measures its own contents has no business being kept at the
    // size of something it no longer holds.
    readonly property real dirBodyH:
      Math.min(lookDirSide.implicitHeight - Math.round(10 * root.zoom),
               look.height * 0.8 - 32)

    // Not "as many as fit" — that is what made the count vary with the
    // length of a path, and made the last one a sliver.
    //
    // TWO ROWS PER FACT, LESS ONE. It was a flat seven, which was that
    // rule for the four facts the card used to carry. With the sheet's
    // full list the column doubled and seven rows stretched to fill it,
    // 50px apiece — a listing that read as double-spaced. Derived, the
    // pitch stays where it was and still divides the facts exactly.
    readonly property int dirFit: Math.max(7, look.dirFacts.length * 2 - 1)

    // A second column only when one will not hold everything. Never a
    // third: past two the names are too narrow to read.
    readonly property int dirCols:
      look.dirRows.length > look.dirFit ? 2 : 1

    // Down the first column, then the second — the order `ls` uses and
    // the order a person scanning for a name expects. Row-major would
    // put neighbours side by side and break the alphabet.
    readonly property var dirPairs: {
      const n = look.dirRows.length;
      if (n === 0) return [];
      const per = Math.ceil(n / look.dirCols);
      const out = [];
      for (let i = 0; i < per; ++i)
        out.push({ a: look.dirRows[i],
                   b: look.dirCols > 1 ? (look.dirRows[i + per] || null) : null });
      return out;
    }

    // ── EVERYTHING THE PROPERTIES SHEET SAYS ABOUT A DIRECTORY ────────
    // The card used to show the four facts that cost nothing and leave
    // the rest to the sheet. It now shows the sheet's whole list, and
    // the three that cost a walk — owner, total size, what is inside
    // all the way down — arrive from one process a moment after the
    // card does, "…" until then, the same way the sheet fills in.
    // ── A PDF'S PAGES ──────────────────────────────────────────────
    // Quick look showed page one and nothing else — the one render the
    // pane makes. It now knows how many pages there are, keeps a strip of
    // them down its side, and renders whichever one you are on at the
    // size it is drawn. See Terminus.pdfPagesCommand for the cache.
    property string docDir: ""        // this version of this file's pages
    property string docPath: ""
    property int docPages: 0          // 0 until pdfinfo has answered
    property int docPage: 1
    property var docThumbs: ({})      // page -> true once its thumbnail exists
    property var docSharp: ({})       // page -> true once rendered sharp
    property int docSeq: 0
    property int docSeen: -1          // the run the last "doc N" line came from
    property int docWant: 0           // a sharp page asked for while one renders
    property int docShown: 0          // the sharp page on screen — see lookPage

    readonly property int sideW: (look.doc && look.docPages > 1)
      ? Math.round(118 * root.zoom) : 0

    function docOpen() {
      const r = look.row;
      if (!root.looking || !look.doc || !r) return;
      const dir = Terminus.terminusCacheDir() + "/pdf/"
        + Qt.md5(r.path + "|" + r.size + "|" + Math.floor(r.mtime));
      if (dir === look.docDir) return;
      look.docDir = dir;
      look.docPath = r.path;
      look.docPages = 0;
      look.docPage = 1;
      look.docThumbs = ({});
      look.docSharp = ({});
      look.docWant = 0;
      look.docShown = 0;
      look.docSeq++;
      lookPagesProc.running = false;
      lookPagesProc.command = ["sh", "-c", "echo \"doc " + look.docSeq + "\"; "
        + Terminus.pdfPagesCommand(r.path, dir, 160)];
      lookPagesProc.running = true;
      look.docSharpen(1);
    }

    // One page, sharp. One render at a time; a page asked for while one
    // is running is remembered and done next — the last one asked for
    // wins, so holding PageDown does not queue every page on the way.
    function docSharpen(p) {
      if (look.docDir === "" || look.docSharp[p]) return;
      if (lookPageProc.running) { look.docWant = p; return; }
      look.docWant = 0;
      lookPageProc.forDir = look.docDir;
      // pdftoppm's -scale-to is the LONG side, and a page may be either
      // way up — so the larger of the two room the card has, which is
      // never smaller than it will be drawn.
      lookPageProc.command = ["sh", "-c", Terminus.pdfPageCommand(look.docPath,
        look.docDir, p, Math.round(Math.max(look.width * 0.8, look.height * 0.86)))];
      lookPageProc.running = true;
    }

    function docGo(p) {
      if (look.docPages < 1) return;
      look.docPage = Math.max(1, Math.min(look.docPages, p));
      if (look.docSharp[look.docPage]) look.docShown = look.docPage;
      else look.docSharpen(look.docPage);
    }

    Process {
      id: lookPagesProc
      stdout: SplitParser {
        splitMarker: "\n"
        onRead: (line) => {
          const t = String(line).trim();
          if (t.indexOf("doc ") === 0) { look.docSeen = parseInt(t.slice(4), 10); return; }
          // a run killed by stepping on can still flush a line or two
          if (look.docSeen !== look.docSeq) return;
          const m = Terminus.parsePdfLine(t);
          if (!m) return;
          if (m.kind === "pages") look.docPages = m.n;
          else if (m.kind === "thumb") {
            const next = Object.assign({}, look.docThumbs);
            next[m.n] = true;
            look.docThumbs = next;
          }
        }
      }
    }

    Process {
      id: lookPageProc
      property string forDir: ""
      stdout: SplitParser {
        splitMarker: "\n"
        onRead: (line) => {
          const m = Terminus.parsePdfLine(line);
          if (!m || m.kind !== "page" || lookPageProc.forDir !== look.docDir) return;
          const next = Object.assign({}, look.docSharp);
          next[m.n] = true;
          look.docSharp = next;
          // shown the moment it exists, if it is still the page wanted
          if (m.n === look.docPage) look.docShown = m.n;
        }
      }
      onExited: if (look.docWant > 0) look.docSharpen(look.docWant)
    }

    property var folderFacts: null     // parseFolderFacts, for factsFor
    property string factsFor: ""
    property int factsSeq: 0

    function askFacts() {
      const r = look.row;
      if (!root.looking || !look.folder || !r) return;
      if (r.path === look.factsFor) return;
      look.factsFor = r.path;
      look.folderFacts = null;
      look.factsSeq++;
      lookFactsProc.running = false;
      lookFactsProc.command = ["sh", "-c",
        Terminus.folderFactsCommand(r.path, look.factsSeq)];
      lookFactsProc.running = true;
    }
    Connections {
      target: root
      function onLookingChanged() {
        if (root.looking) { Qt.callLater(look.askFacts); Qt.callLater(look.docOpen); }
        // Closed, a walk has nobody to tell — and the next open of this
        // same directory must ask again rather than trust a stale "…".
        else {
          lookFactsProc.running = false; look.factsFor = "";
          lookPagesProc.running = false; look.docDir = "";
        }
      }
    }
    Process {
      id: lookFactsProc
      stdout: StdioCollector {
        id: lookFactsOut
        waitForEnd: true
        onStreamFinished: {
          const f = Terminus.parseFolderFacts(lookFactsOut.text);
          if (f && f.tag === String(look.factsSeq)) look.folderFacts = f;
        }
      }
    }

    readonly property var dirFacts: {
      const r = look.row;
      if (!r || !look.folder) return [];
      const n = look.dirRows.length;
      const f = look.factsFor === r.path ? look.folderFacts : null;
      const wait = "\u2026";
      const names = root.tagMarks[r.path] || [];
      return [
        // ANSWERED, not merely absent. dirRows still holds the LAST
        // directory's listing while this one is being read, so "empty" is
        // only true once the reply on screen is about this path — the
        // guard the old centred "Empty" label carried before the facts
        // took the sentence over.
        ["items", (look.reading || root.previewShown !== r.path) ? "\u2026"
          : (n === 0 ? "empty" : n + (n === 1 ? " item" : " items"))],
        ["location", Terminus.dirname(r.path)],
        ["type", r.isLink ? "symbolic link to a directory" : "directory"],
        // The sheet's spellings, so the two read as one answer.
        ["size", (f && f.size >= 0)
          ? Terminus.formatSize(f.size) + "  \u00b7  " + f.size + " bytes" : wait],
        ["contains", (f && f.files >= 0 && f.dirs >= 0)
          ? f.files + (f.files === 1 ? " file" : " files") + "  \u00b7  "
            + f.dirs + (f.dirs === 1 ? " directory" : " directories")
          : wait],
        ["modified", Terminus.formatTime(r.mtime)],
        ["owner", (f && f.owner !== "") ? f.owner : wait],
        ["permissions",
          ("000" + (r.mode & 511).toString(8)).slice(-3)
          + "  \u00b7  " + Terminus.modeString(r.mode)]
      ].concat(names.length > 0 ? [["tags", names.slice().sort().join(", ")]] : []);
    }
    function syncDir() {
      if (look.folder && root.previewKind === "dir"
          && root.previewRows.length > 0)
        look.dirRows = root.previewRows;
    }
    // ── THE TREE'S ROWS ARE LATCHED ────────────────────────────────
    // The model used to be `previewTree` gated on previewKind, and both
    // of those belong to the PREVIEW PANE, which goes on recomputing
    // while quick look is open. Any momentary dip emptied the model —
    // and an empty ListView has a contentHeight of 0, so the scroll
    // position is clamped to the top and gone. That is the momentum
    // loss, and it is why only the archive viewer has it: it is the one
    // surface here whose model is gated on somebody else's state.
    //
    // Copied once, when rows for THIS row arrive, and dropped only when
    // the row itself changes. Nothing the pane does afterwards can take
    // them away.
    property var treeRows: []
    readonly property bool tree: look.arc && look.treeRows.length > 0
    // Whether the file actually loaded AS a font, which is the one thing
    // the name cannot answer — see lookFaceBox.
    // The one place treeRows is filled. Guarded on the kind AND on the
    // row still being an archive, so a stray settle for something else
    // cannot write into it.
    Connections {
      target: root
      function onPreviewTreeChanged() { look.syncTree(); }
      function onPreviewRowsChanged() { look.syncDir(); }
    }

    readonly property bool faceReady: lookSpec.ready
    readonly property string faceName: lookSpec.face
    // The one path a FontLoader is ever allowed — see lookSpec below.
    readonly property string facePath:
      (look.face && look.row) ? look.row.path : ""

    // ── WHAT PLAYS, AND ONLY HERE ───────────────────────────────────
    // The preview PANE keeps its still frame on purpose: it follows the
    // cursor, and starting a decoder on every row you arrow past is a lot
    // of work for a directory you are walking through. Quick look is asked
    // for, one file at a time, which is exactly when playing is wanted.
    readonly property bool vid:
      look.isFile && Terminus.isVideo(look.row.name)
    readonly property bool playable: look.isFile
      && (look.vid || Terminus.isAudio(look.row.name))

    // The file itself for a picture; the cached frame for a film or a cover,
    // which is the only image either of those has.
    readonly property string src: {
      const r = look.row;
      if (!r) return "";
      // The stamp only changes when a rotation has happened — see
      // root.imgStamp — so an ordinary step between pictures still hits
      // Qt's cache as before.
      if (look.pic) {
        // Rendered, for the formats Qt has no decoder for. The big copy
        // when it has landed and the pane's small one until then, so
        // opening quick look shows something immediately and sharpens.
        if (root.needsRender(r)) {
          const big = root.bigFile[r.path];
          if (big) return "file://" + big;
          return root.thumbFile[r.path]
            ? "file://" + root.thumbFile[r.path] : "";
        }
        return Strings.fileUrl(r.path)
          + (root.imgStamp > 0 ? "?v=" + root.imgStamp : "");
      }
      if (look.framed)
        return root.thumbFile[r.path] ? "file://" + root.thumbFile[r.path] : "";
      // Only once the page at pdfStem is known to be THIS document's — see
      // root.pdfFor. The stamp is what makes Qt re-read a name it has
      // already cached.
      // Page one, always — even while another page is on screen. This is
      // what SIZES the card, and every page of one file is the same size,
      // so it never needs to change; the page being read is drawn over it
      // by lookPage. Swapping this instead made every page turn a reload:
      // the card treated each page as a new file and redrew for it.
      if (look.doc)
        return (root.pdfFor === r.path && root.previewStamp > 0)
          ? "file://" + root.pdfStem + ".png?v=" + root.previewStamp : "";
      return "";
    }

    // Source and lifetime are one expression: it empties when the overlay
    // closes or the cursor steps to something that does not play, and an
    // empty source is a stopped player. Nothing has to remember to stop it.
    // ── MADE THE FIRST TIME SOMETHING PLAYS ──────────────────────────
    // Creating a MediaPlayer starts Qt's whole FFmpeg backend: 598 ms in one
    // piece, the largest single block of a shell start, and paid again for
    // every terminus window built — with or without a film ever looked at
    // (qmlprofiler, 2026-10-09). It is made the first time quick look shows
    // something it can play, and kept from then on.
    property bool playerWanted: false
    readonly property bool wantsPlayer: root.looking && look.playable
    onWantsPlayerChanged: if (look.wantsPlayer) look.playerWanted = true
    Loader {
      id: playerSlot
      active: look.playerWanted
      readonly property var idle: ({ duration: 0, position: 0, hasVideo: false,
        playbackState: 0, source: "", play: () => {}, pause: () => {}, stop: () => {} })
      sourceComponent: Component {
        MediaPlayer {
          id: lookPlayerItem
          audioOutput: AudioOutput { }
          videoOutput: lookVideo
          source: (root.looking && look.playable && look.row)
            ? "file://" + look.row.path : ""
          // Autoplay, the way every other quick look does: you opened it to see
          // the thing, not to be asked whether you meant it.
          onSourceChanged: if (lookPlayerItem.source != "") lookPlayerItem.play()
          Component.onCompleted: if (lookPlayerItem.source != "") lookPlayerItem.play()
        }
      }
    }

    InputShield { keep: lookFrame; onClicked: root.looking = false }

    // ── THE PREVIEW AND ITS NAME, AS ONE PANEL ───────────────────────
    // The name used to float against the scrim along the bottom of the
    // WINDOW, which on a picture half the window tall left it stranded an
    // inch under the thing it was naming. A caption belongs to what it
    // captions, so it is a bar across the bottom of the panel now and the
    // panel is whatever there is to show — a picture, or the text preview.
    //
    // THE FRAME IS SIZED TO THE CONTENT, not the content to the frame.
    // lookShot takes its bounds from the window and the panel then takes the
    // picture's PAINTED size, which is the only number that knows where the
    // picture actually ends after PreserveAspectFit has had it. The other
    // way round is a binding loop: the painted size is what the frame would
    // be asking for.
    // ── THE SAME SHADOW THE MENU CASTS ──────────────────────────────
    // Full strength here, unlike the menu's. That one lives on a popup
    // sized to its card, so every pixel of shadow has to be paid for in
    // padding the compositor then counts when placing it — which is why its
    // reach is a third of the usual. This card sits in the middle of a
    // surface the size of the monitor, so the room is already there and the
    // defaults apply.
    //
    // It reads as a shadow rather than a haze because this is a LAYER, and
    // rules.lua ignores alpha below 0.5 on layers — the same reason icarus'
    // menus have always looked right. See the note on popups_ignorealpha.
    MenuShadow {
      panel: lookFrame
      cornerRadius: Zenon.dialogRadius
      opacity: look.opacity
    }

    ClippingRectangle {
      id: lookFrame
      anchors.centerIn: parent
      // ── A GROUND, NOT A BACKING BOARD ────────────────────────────
      // Solid black, a PNG with an alpha channel was shown mounted on it:
      // the transparent parts of the picture were not transparent, they
      // were black, and there is no way to tell that apart from a picture
      // that really is black. A viewer has to be able to answer "does this
      // image have a background" and this one could not.
      //
      // Quick look is a LAYER — see the namespace above — and rules.lua
      // blurs every layer namespace whose alpha clears ignore_alpha 0.5.
      // So a ground above that floor costs nothing to blur: the compositor
      // is already doing it for the bar and every popup.
      //
      // LIGHTER THAN A LAYER'S OWN GROUND, and that is the point rather
      // than an oversight. layerBg is 0.80, which over this desktop lets
      // through about seven values out of 255 — a distinction no eye is
      // going to make against black. The popups are at 0.80 because they
      // are things you READ; this is a thing you LOOK THROUGH, and it has
      // to be see-through enough to be worth the name.
      //
      // Against blurFloor rather than as a bare 0.60, so it can never
      // silently fall under hyprland's threshold — the one failure that
      // would turn the soft ground into a hard rectangle of sharp desktop.
      color: Zenon.frostBg
      border.color: Zenon.border
      border.width: 1
      radius: Zenon.dialogRadius

      readonly property real textW: Math.min(900, look.width * 0.8)

      // ── A DIRECTORY'S CARD IS THE SIZE OF WHAT IS ON IT ──────────
      // A picture's card is the picture. A directory's was the full
      // reading width whether it held forty things or nothing at all,
      // which left an empty directory's four facts adrift in the middle
      // of a 900px slab. Split, the contents want that width and earn
      // it. Unsplit, the card is the facts plus their margins.
      readonly property real dirW: {
        // No contents half: the card is the facts and their margins.
        if (!lookDirPane.split)
          return Math.max(lookDirSide.implicitWidth + 32, lookFrame.barW);
        // With one: the facts' half, the rule, and as many name
        // columns as there are — a directory holding one thing is not
        // 900px of anything. The reading width is the ceiling, for
        // the directory whose names run off the end of it.
        const cols = look.dirCols;
        const half = cols * look.dirCellW + (cols > 1 ? 12 : 0) + 10;
        return Math.max(
          Math.min(lookDirPane.leftW + 1 + 32 + half, lookFrame.textW),
          lookFrame.barW);
      }

      // The floor under that: what the CAPTION needs to say the name
      // and show its keys. The facts can be narrower than the bar
      // below them; the bar cannot be narrower than itself.
      //
      // Every term is an implicitWidth — a natural, unwrapped, unelided
      // text width — so none of them is read back off the card's own
      // width, which is what this is computing.
      readonly property real barW:
        Math.ceil(
          14 + lookGlyph.implicitWidth + 8
          + Math.min(lookName.implicitWidth, Math.round(220 * root.zoom))
          + 14 + lookKeys.implicitWidth + 14)
        // Slack. Summed exactly, the name gets exactly its own width
        // and Qt elides on the fractional pixel — a card sized to fit
        // "Documents" showed "Doc…nts".
        + 4

      // NOTHING TO READ IS NOT A SHORT DOCUMENT. With no preview text the
      // column is empty and the card collapsed onto its own caption bar —
      // a sentence saying there is nothing to show needs somewhere to be
      // shown, so the card keeps a fixed, modest height for that case.
      // Taller for a track, which puts a player in this space rather than
      // one line of type — see the column below the "no preview" text.
      readonly property real emptyH:
        (look.playable && !look.vid) ? 186 : 120

      // Held through the decode — see look.heldW — so a step between two
      // pictures is one change of size rather than a collapse and a recovery.
      readonly property bool holding: look.pending && look.heldW > 0

      // ── STEPPING BETWEEN PICTURES IS A MOVE, NOT A CUT ─────────────
      // The panel shrink-wraps whatever it is showing, so every picture of
      // a different size snapped it to a new shape. Held through the decode
      // (see heldW) that is one snap per image rather than two — but
      // arrowing through a directory is still a run of hard jumps at irregular
      // intervals, which is what reads as chop.
      //
      // Eased, the panel travels between the two shapes instead. The decode
      // has already finished by the time this runs — shotW only changes
      // once the image has been read — so the ease is not competing with it
      // for the GUI thread, which is the usual reason an eased resize
      // stutters.
      //
      // Not on the FIRST one: heldW is 0 until a picture has landed, so
      // opening quick look sizes the panel outright and only the steps
      // after it travel. Without that, every open would grow from nothing.
      Behavior on width {
        enabled: look.heldW > 0
        NumberAnimation { duration: Zenon.fast; easing.type: Zenon.travelEase }
      }
      Behavior on height {
        enabled: look.heldH > 0
        NumberAnimation { duration: Zenon.fast; easing.type: Zenon.travelEase }
      }
      // A tree is as tall as it needs, capped like a document; a
      // specimen is a fixed block of type. Both take the text width —
      // they are reading surfaces, not pictures.
      readonly property real treeH:
        Math.min(root.previewTree.length * Math.round(21 * root.zoom) + 32,
                 look.height * 0.8)
      // as tall as the specimen it holds (FontSpecimen), and never less
      readonly property real faceH: Math.max(Math.round(300 * root.zoom), Math.ceil(lookSpec.implicitHeight) + 40)
      // The facts column decides it — see look.dirBodyH. One height
      // for every directory, so stepping through them does not make the
      // card breathe.
      readonly property real dirH: look.dirBodyH + 32

      // ── NEVER NARROWER THAN ITS OWN CAPTION ───────────────────────
      // The card is sized to what it shows, and a 100px icon made a
      // 100px card: the name and the key hints were crushed into the
      // picture's width and cut off. The caption's natural width is now
      // the floor, and a picture smaller than that sits centred in the
      // room — see shotX. Nothing in the caption reads the card's width,
      // so this cannot loop; capped at the window like everything else.
      readonly property real capMinW: Math.min(look.width * 0.9,
        14 + lookGlyph.implicitWidth + 8 + lookName.implicitWidth
        + 14 + lookKeys.implicitWidth + 14)
      readonly property real shotX: Math.max(0,
        Math.round((lookFrame.width - look.sideW - look.shotW) / 2))
      width: Math.max(lookFrame.capMinW, lookShot.visible ? look.shotW + look.sideW
        : (lookFrame.holding ? look.heldW + look.sideW
           : (look.listing ? lookFrame.dirW : lookFrame.textW)))
      height: look.capH + (lookShot.visible ? look.shotH
        : (lookFrame.holding ? look.heldH
           : (look.listing ? lookFrame.dirH
              : (look.tree ? lookFrame.treeH
              : (look.face ? lookFrame.faceH
                 : (look.hasText
                    ? Math.min(lookCol.implicitHeight + 32, look.height * 0.8)
                    : lookFrame.emptyH))))))

      // ── NO EASING ON THE SIZE ─────────────────────────────────────
      // The panel used to ease between sizes, on the reasoning that stepping
      // files should be one panel changing shape rather than two panels.
      // With the size now HELD across the decode there is nothing to ease:
      // the change happens once, when the new picture is already in hand,
      // and easing it only delays the picture you asked for.
      //
      // Which leaves this overlay animating on exactly two events — opening
      // and closing. Everything in between is instant, which is what a
      // viewer you flick through should be.

      // THE ARRIVAL EVERY OTHER CARD HAS AND THIS ONE DID NOT. It appeared
      // at full size the instant the scrim began to fade, which reads as a
      // cut rather than as something being opened. CardRise and CardGrow are
      // the shared pair — rise and grow on travelEase, asymmetric in and
      // out — so quick look opens the way the menus and the cards do.
      transform: [
        CardGrow { shown: root.looking; card: lookFrame },
        CardRise { shown: root.looking }
      ]

      Image {
        id: lookShot
        // PLACED, NOT ANCHORED. The panel is sized to this picture, so a
        // horizontalCenter anchor is a loop: the picture's x would come from
        // the panel's width and the panel's width comes from the picture.
        // The panel IS the picture's size, so the corner is 0, 0 — and the
        // border draws over the edge, which is what a frame is. A PDF's
        // page strip, when it has one, is to its right. Centred when the
        // caption is wider than the picture — see capMinW.
        x: lookFrame.shotX
        y: 0
        // Ninety per cent of the window, less the caption bar, which is
        // part of the panel now and has to fit in the same room. The
        // arithmetic is look.fitScale; this is the result of it, which is
        // already aspect-correct and therefore exactly what is drawn.
        width: look.shotW
        height: look.shotH
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        visible: look.src !== "" && look.shotW > 0
          && lookShot.status === Image.Ready
        // Decoded at the size it is drawn, which for this is most of a
        // monitor — the grid's 480px cache would be a blur at that size.
        sourceSize.width: Math.round(look.width * 0.8)
        sourceSize.height: Math.round(look.height * 0.86)
        source: look.src
      }

      // ── THE PAGE BEING READ, OVER PAGE ONE ───────────────────────────
      // Exactly lookShot's box. retainWhileLoading keeps the page you were
      // on up until the next one has decoded, so turning a page is one
      // picture replaced by another — no blank frame, no soft thumbnail
      // first, and nothing about the card moves, because nothing about its
      // size depends on this.
      Image {
        id: lookPage
        x: lookFrame.shotX
        y: 0
        width: look.shotW
        height: look.shotH
        visible: lookShot.visible && look.docShown > 0
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        retainWhileLoading: true
        sourceSize.width: lookShot.sourceSize.width
        sourceSize.height: lookShot.sourceSize.height
        source: (look.docDir !== "" && look.docShown > 0)
          ? "file://" + look.docDir + "/p" + look.docShown + ".png" : ""
      }

      // ── THE PAGES, DOWN THE SIDE ─────────────────────────────────────
      // A thumbnail per page, the one you are on outlined, each filled in
      // as it is made. Click one to go there; PageUp and PageDown step.
      ListView {
        id: lookPages
        // pinned to the card's right edge, whatever the page is centred in
        x: lookFrame.width - look.sideW
        y: 0
        width: look.sideW
        height: lookFrame.height - look.capH
        visible: look.sideW > 0
        clip: true
        model: look.docPages
        spacing: Math.round(10 * root.zoom)
        topMargin: Math.round(10 * root.zoom)
        bottomMargin: Math.round(10 * root.zoom)
        boundsBehavior: Flickable.StopAtBounds
        ElasticScroll { view: lookPages; step: root.wheelStep }

        // the page you are on stays in view as you step
        Connections {
          target: look
          function onDocPageChanged() {
            lookPages.positionViewAtIndex(look.docPage - 1, ListView.Contain);
          }
        }

        delegate: Item {
          id: pageCell
          required property int index
          readonly property int page: index + 1
          readonly property bool here: look.docPage === pageCell.page
          width: lookPages.width
          height: pageBox.height + pageNum.height + 4

          Rectangle {
            id: pageBox
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - Math.round(28 * root.zoom)
            height: Math.round(pageBox.width * 1.3)
            // The tint alone was no cursor: a rendered page is opaque and
            // covers all but 4px of it. So the page you are on takes the
            // cyan ring a tile's cursor wears over a photograph — see
            // SelectCell — one pixel, the same width as everyone else's.
            color: pageCell.here
              ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.22)
              : Zenon.wash(0.04)
            border.width: 1
            border.color: pageCell.here ? Zenon.cyan : Zenon.border
            radius: 2

            Image {
              anchors.fill: parent
              anchors.margins: pageCell.here ? 4 : 1
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              // docDir as well: on the way out it empties before the strip
              // has faded, and "file:///t3.png" is a path Qt then complains
              // about for every page
              source: (look.docDir !== "" && look.docThumbs[pageCell.page])
                ? "file://" + look.docDir + "/t" + pageCell.page + ".png" : ""
            }
          }

          Text {
            id: pageNum
            anchors.top: pageBox.bottom
            anchors.topMargin: 3
            anchors.horizontalCenter: parent.horizontalCenter
            text: String(pageCell.page)
            color: pageCell.here ? Zenon.cyan : Zenon.muted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Math.round(11 * root.zoom)
          }

          MouseArea {
            anchors.fill: parent
            onClicked: look.docGo(pageCell.page)
          }
        }
      }

      Rectangle {
        x: lookFrame.width - look.sideW
        width: 1
        y: 0
        height: lookFrame.height - look.capH
        visible: look.sideW > 0
        color: Zenon.border
      }

      // ── THE FILM ITSELF, OVER THE FRAME PULLED OUT OF IT ─────────────
      // Exactly the still's box, so the panel's size is still worked out
      // from the thumbnail and nothing here feeds back into it — see the
      // note on lookShot about why that box is placed rather than anchored.
      // The still stays underneath and shows through until the first frame
      // is decoded, so opening a film does not flash an empty rectangle.
      VideoOutput {
        id: lookVideo
        x: lookFrame.shotX
        y: 0
        width: look.shotW
        height: look.shotH
        fillMode: VideoOutput.PreserveAspectFit
        visible: look.vid && lookPlayer.hasVideo
      }

      // ── HOW FAR THROUGH, FOR THE ONE THAT SHOWS NOTHING MOVING ──────
      // A film says where it is by playing; a track shows a cover that does
      // not change, so without this there is no way to tell a paused one
      // from a playing one, or to see that it is nearly over.
      //
      // Across the foot of the picture rather than under it: the panel is
      // sized to the cover, and a bar below would either stretch the panel
      // or hang outside it.
      Rectangle {
        // ACROSS THE CARD, not across the artwork. Sized to the picture
        // it was invisible for every track that has no cover — which is
        // most of them — because there was no picture to be the width of.
        // The card is always there, and the bar belongs to the file rather
        // than to its art anyway.
        // Over the artwork, where there IS artwork. A track with no cover
        // gets the player below instead, which has room for a bigger one.
        visible: look.playable && !look.vid && lookPlayer.duration > 0
                 && lookShot.visible
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: look.capH
        height: 10
        color: "transparent"

        Meter {
          anchors.centerIn: parent
          vertical: false
          value: lookPlayer.duration > 0
            ? lookPlayer.position / lookPlayer.duration : 0
          accent: Zenon.cyan
          thickness: 4
          segLength: 5
          segGap: 3
          deadZone: 0
          segCount: Math.max(8, Math.floor((parent.width - 24) / 8))
        }
      }

      // Everything that is not a picture: the text preview the pane already
      // read, or the name and the reason there is nothing to show.
      Flickable {
        id: lookScroll
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: lookCap.top
        anchors.margins: 16
        visible: !lookShot.visible && look.hasText
        clip: true
        contentWidth: width
        contentHeight: lookCol.implicitHeight
        boundsBehavior: Flickable.DragAndOvershootBounds
        boundsMovement: Flickable.FollowBoundsBehavior

        // The document half of quick look was the one scroll surface in
        // the shell still on Qt's own wheel handling — see
        // morpheus/Elastic.qml for the rule everything else follows.
        ElasticScroll { view: lookScroll; step: root.wheelStep }

        Column {
          id: lookCol
          width: parent.width
          spacing: 10

          Text {
            width: parent.width
            text: root.previewText
            textFormat: Text.RichText
            // The same two as the preview column — see previewBody. This is
            // the same text, bigger; it should not also be set differently.
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            color: Zenon.white
            // plato's face, as the column preview's (root.codeFamily)
            font.family: root.codeFamily
            font.weight: root.codeWeight
            font.pixelSize: Math.round(17 * root.zoom)
          }
        }
      }

      // A TEXT FILE IS THE ONE THING HERE YOU SCROLL. Pictures fit the panel
      // by construction, so this is the only view in the overlay with more
      // in it than is on screen — and it had no way of saying so, or of
      // saying how far down you were.
      //
      // Against the CARD rather than the flickable, the way the preview
      // pane's rail is: lookScroll is inset 16px so its text clears the
      // edges, and a rail hung off that would sit 18px in from the card.
      ScrollRail {
        owner: root
        target: lookScroll
        on: lookScroll.visible
        // Against the CARD only. Neither the flickable nor the caption
        // bar is a sibling of this — both sit a level deeper — and Qt
        // refuses an anchor that crosses that. The caption's height is
        // named on the overlay (look.capH) precisely so sums like this one
        // do not have to reach into the bar to ask it.
        anchors.top: parent.top
        anchors.topMargin: 2
        anchors.bottom: parent.bottom
        anchors.bottomMargin: look.capH + 2
        anchors.right: parent.right
        anchors.rightMargin: 2
      }

      // ── WHAT IS INSIDE AN ARCHIVE ───────────────────────────────
      // The same tree the columns pane draws, at the size of the window.
      // Its rows come from root.previewTree, which archiveTree already
      // gave a glyph, an ink and a guide prefix — so this is the same
      // three Texts, and a zip reads the same in both places.
      ListView {
        id: lookTree
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: lookCap.top
        anchors.margins: 16
        // ── VISIBLE FOR THE WHOLE LIFE OF THE ROW ─────────────
        // This was `look.tree`, which is `arc && kind === "archive" &&
        // rows.length > 0` — three conditions, two of them the preview
        // pane's state, which the pane goes on recomputing while quick
        // look is open. Any momentary dip in it hid the view, and the
        // reset below then threw the scroll position away. Scrolling a
        // long archive lost ground over and over, which is what "the
        // momentum degrades the further down I go" is.
        //
        // The ROW is what decides whether a tree belongs here, and the
        // row does not flicker. The model is still gated, so an archive
        // being read shows an empty view rather than a stale one.
        visible: look.arc
        model: look.treeRows
        clip: true
        boundsBehavior: Flickable.DragAndOvershootBounds
        boundsMovement: Flickable.FollowBoundsBehavior
        reuseItems: look.arc
        // Back to the top for a NEW archive, and only then — treeRows
        // is emptied on the same signal, so the two stay in step.
        Connections {
          target: look
          function onRowChanged() { lookTree.contentY = 0; }
        }

        // The same notch the listing uses, not a fraction of this card:
        // quick look's frame is a few hundred pixels tall, so the
        // default would have been about half the distance per notch
        // that every other surface in this window moves.
        ElasticScroll { view: lookTree; step: root.wheelStep }

        delegate: Item {
          required property var modelData
          width: lookTree.width
          height: Math.round(21 * root.zoom)

          // Box-drawing guides have to stack exactly under the ones
          // above, which only a fixed-pitch face guarantees — the names
          // beside them keep the proportional one. `|| ""` throughout
          // for the recycling reason above.
          Text {
            id: lookGuide
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.prefix || ""
            color: Zenon.muted
            font.family: Zenon.faceMono
            font.weight: Zenon.weight
            font.pixelSize: Math.round(15 * root.zoom)
          }

          Text {
            id: lookTreeGlyph
            anchors.left: lookGuide.right
            anchors.verticalCenter: parent.verticalCenter
            visible: !!modelData.glyph
            width: visible ? Math.round(20 * root.zoom) : 0
            text: modelData.glyph || ""
            color: modelData.inkKey ? Zenon[modelData.inkKey] : (modelData.ink || Zenon.white)
            font.family: Zenon.faceMono
            font.weight: Zenon.weight
            font.pixelSize: Math.round(15 * root.zoom)
          }

          Text {
            anchors.left: lookTreeGlyph.right
            anchors.leftMargin: 4
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.name || ""
            elide: Text.ElideRight
            color: modelData.nameKey ? Zenon[modelData.nameKey] : (modelData.nameInk || Zenon.white)
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Math.round(15 * root.zoom)
          }
        }
      }

      ScrollRail {
        owner: root
        target: lookTree
        on: lookTree.visible
        anchors.top: parent.top
        anchors.topMargin: 2
        anchors.bottom: parent.bottom
        anchors.bottomMargin: look.capH + 2
        anchors.right: parent.right
        anchors.rightMargin: 2
      }

      // ── WHAT IS IN A DIRECTORY ─────────────────────────────────────
      // The same glyph-and-name rows the listing behind it draws, so a
      // directory previews as a small copy of itself rather than as a
      // summary of facts about it. Sorted and enriched already — this
      // is the pane's own `previewRows`, latched.
      // ── WHAT A DIRECTORY IS, BESIDE WHAT IT HOLDS ──────────────────
      // Left: the directory itself — its glyph at size, and the facts that
      // cost nothing to know. Right: what is in it, in one column or
      // two. A rule between them, because two panels sharing an edge
      // with no line read as one panel with a gap in it.
      Item {
        id: lookDirPane
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: lookCap.top
        visible: look.folder

        // NO MARGINS ON THE PANE — they are on the two halves. A
        // separator that stops 16px short of the card's edges reads as
        // a line drawn on the panel; one that runs the full height
        // reads as the edge between two halves, which is what it is.
        // THE FACTS DECIDE IT, up to the fraction of the reading width
        // that used to decide it outright. Taken from the pane's own
        // width instead, the facts' cap would come from the card and
        // the card's width would come from the facts.
        readonly property real leftW:
          Math.min(lookDirSide.implicitWidth + 32,
                   Math.round(lookFrame.textW * 0.38))
        // An empty directory is its facts and nothing else: no contents
        // half, so no rule, and the facts get the whole width.
        readonly property bool split: look.dirRows.length > 0

        // ── the directory ────────────────────────────────────────────
        Column {
          id: lookDirSide
          // ── THE BOX IS CENTRED; THE LINES ARE NOT ─────────────
          // Pinned to the top-left of a half taller and wider than it
          // is, the facts read as having fallen into a corner of the
          // card rather than as being placed in it. So the column is
          // sized to the facts and centred on both axes — and every
          // line inside it still starts at its left edge, because a
          // centred RAG-BOTH label column is not a properties list,
          // it is a poem.
          anchors.verticalCenter: parent.verticalCenter
          // The INK centred, not the box. Every fact carries 10px of
          // padding BELOW it, including the last one, so a box centred
          // by its own height hangs half that gap high.
          anchors.verticalCenterOffset: Math.round(5 * root.zoom)
          x: Math.round((lookDirSide.room - lookDirSide.width) / 2)
          spacing: 0

          // The half it is centred in — which is the whole pane when
          // an empty directory leaves no contents half to sit beside.
          // Read off the PANE, because centring cannot feed a width.
          readonly property real room:
            lookDirPane.split ? lookDirPane.leftW : lookDirPane.width
          // What it may not grow past. Read off the READING WIDTH,
          // because this one does feed a width — see lookFrame.dirW.
          readonly property real capW:
            (lookDirPane.split ? Math.round(lookFrame.textW * 0.38)
                               : lookFrame.textW) - 32

          // No glyph here. It is the same glyph the caption bar shows
          // beside the name, and drawn twice on one small card it read
          // as two different things being named.
          Repeater {
            model: look.dirFacts
            delegate: Column {
              required property var modelData
              spacing: 1
              bottomPadding: Math.round(10 * root.zoom)

              Text {
                text: modelData[0]
                color: Zenon.keyInk
                font.family: Zenon.face
                font.pixelSize: Math.round(16 * root.zoom)
                font.weight: Font.Bold
                font.letterSpacing: 1.2
              }
              Text {
                // As wide as it wants, up to the half. A Text's
                // implicitWidth is its UNWRAPPED width, so capping the
                // width with it is safe — the wrap and the cap cannot
                // chase each other round a loop.
                width: Math.min(implicitWidth, lookDirSide.capW)
                text: modelData[1]
                color: Zenon.white
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Math.round(16 * root.zoom)
                // ElideRight, and not the middle elide the name bars
                // use: a middle elide has no meaning once the text
                // WRAPS, and Qt answers it by cutting the last line
                // off with no ellipsis at all. A deep path came out
                // ending in "scrat" as though that were the directory.
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.WrapAnywhere
              }
            }
          }
        }

        Rectangle {
          id: lookDirRule
          x: lookDirPane.leftW
          width: 1
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          visible: lookDirPane.split
          color: Zenon.border
        }

        // ── and what is in it ─────────────────────────────────────
        ListView {
          id: lookDir
          anchors.top: parent.top
          anchors.topMargin: 16
          anchors.left: lookDirRule.right
          anchors.leftMargin: 16
          anchors.right: parent.right
          anchors.rightMargin: 16
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 16
          visible: lookDirPane.split
          model: look.dirPairs
          clip: true

          // ── A NEW DIRECTORY STARTS AT THE TOP ────────────────────
          // The model is replaced wholesale whenever the preview
          // changes subject, and a ListView keeps whatever scroll it
          // had. Step from a long directory to a short one and the short
          // one opened two rows down: its first two entries above the
          // fold, and a sliver of an eighth row at the bottom where
          // seven should end cleanly.
          //
          // Deferred a turn, because the view has not taken the new
          // model at the moment the binding changes — positioning it
          // now would position the old rows. The same ordering trap
          // the panes' snapInBounds hit.
          //
          // ── AND NOT ONLY WHEN THE MODEL CHANGES ───────────────
          // The row pitch is the facts column's height in seven, and
          // that height moves per directory — a location long enough to
          // wrap adds a line. Rows that change height under a
          // ListView move its origin rather than its rows, and the
          // wheel's clamp to 0 then left the first rows above the
          // fold. So a change of pitch rewinds too, and so does
          // opening the viewer, and anything the wheel still had in
          // flight for the last directory is cancelled first.
          function rewind() {
            lookDirWheel.elastic.halt(lookDir);
            lookDir.positionViewAtBeginning();
          }
          onModelChanged: Qt.callLater(lookDir.rewind)
          Connections {
            target: look
            function onDirRowHChanged() { Qt.callLater(lookDir.rewind); }
          }
          Connections {
            target: root
            function onLookingChanged() {
              if (root.looking) Qt.callLater(lookDir.rewind);
            }
          }
          boundsBehavior: Flickable.DragAndOvershootBounds
          boundsMovement: Flickable.FollowBoundsBehavior
          reuseItems: look.folder

          ElasticScroll { id: lookDirWheel; view: lookDir; step: root.wheelStep }

          delegate: Item {
            id: dirPairRow
            required property var modelData
            width: lookDir.width
            height: look.dirRowH

            readonly property real colW:
              look.dirCols > 1 ? (dirPairRow.width - 12) / 2 : dirPairRow.width

            // One cell, twice. The b half is empty on the last row of an
            // odd listing, which is why it is drawn from a null-guarded
            // entry rather than from a second Repeater over a shorter
            // model.
            Item {
              x: 0
              width: dirPairRow.colW
              height: parent.height
              visible: !!dirPairRow.modelData.a

              Text {
                id: dirCellGlyphA
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(22 * root.zoom)
                horizontalAlignment: Text.AlignHCenter
                text: dirPairRow.modelData.a ? (dirPairRow.modelData.a.glyph || "") : ""
                color: dirPairRow.modelData.a
                  ? (dirPairRow.modelData.a.ink || Zenon.white) : Zenon.white
                font.family: Zenon.faceMono
                font.weight: Zenon.weight
                font.pixelSize: Math.round(16 * root.zoom)
              }
              Text {
                anchors.left: dirCellGlyphA.right
                anchors.leftMargin: 6
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: dirPairRow.modelData.a ? (dirPairRow.modelData.a.name || "") : ""
                elide: Text.ElideRight
                color: dirPairRow.modelData.a
                  ? (dirPairRow.modelData.a.nameInk || Zenon.white) : Zenon.white
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Math.round(16 * root.zoom)
              }
            }

            Item {
              x: dirPairRow.colW + 12
              width: dirPairRow.colW
              height: parent.height
              visible: !!dirPairRow.modelData.b

              Text {
                id: dirCellGlyphB
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(22 * root.zoom)
                horizontalAlignment: Text.AlignHCenter
                text: dirPairRow.modelData.b ? (dirPairRow.modelData.b.glyph || "") : ""
                color: dirPairRow.modelData.b
                  ? (dirPairRow.modelData.b.ink || Zenon.white) : Zenon.white
                font.family: Zenon.faceMono
                font.weight: Zenon.weight
                font.pixelSize: Math.round(16 * root.zoom)
              }
              Text {
                anchors.left: dirCellGlyphB.right
                anchors.leftMargin: 6
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: dirPairRow.modelData.b ? (dirPairRow.modelData.b.name || "") : ""
                elide: Text.ElideRight
                color: dirPairRow.modelData.b
                  ? (dirPairRow.modelData.b.nameInk || Zenon.white) : Zenon.white
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Math.round(16 * root.zoom)
              }
            }
          }
        }

        // ON the contents half. A ScrollRail anchors to its target, and
        // an anchor may only name a parent or a sibling — this one sat
        // outside the pane naming a grandchild of it, which Qt drops,
        // leaving the bar sized 0 and invisible however far the list
        // overflowed.
        ScrollRail {
          owner: root
          target: lookDir
          on: lookDirPane.visible && lookDirPane.split
          anchors.top: lookDir.top
          anchors.bottom: lookDir.bottom
          anchors.right: lookDir.right
        }
      }

      // ── AND WHAT A TYPEFACE LOOKS LIKE ──────────────────────────
      // A font previews by BEING the preview: Qt loads the file and the
      // lines below are set in it. Nothing to run and nothing to parse,
      // which is why this is the one kind quick look could have shown
      // all along and did not.
      //
      // Its own FontLoader rather than the pane's: that one is bound to
      // previewKind, which is the miller column's state and is never
      // computed in a list or a grid — the two views you are most
      // likely to be standing in when you press space on a font.
      // ── BUILT ONLY WHEN THERE IS A FONT ─────────────────────────
      // A FontLoader handed an empty source does not sit quietly: it
      // logs `Cannot load font: ""` every time the row under the cursor
      // is not a typeface, which is nearly always. A Loader that is
      // simply inactive has nothing to complain about.
      // ── IT MUST NEVER SEE A PATH THAT IS NOT A FONT ───────────
      // One guarded property (facePath) feeds it: `active` and the source
      // were once two separate readings of look.row, and stepping from a
      // typeface onto an archive asked Qt to load the archive as a font —
      // which half-registered a family and drew every later glyph one
      // codepoint off ("DpmmbqtjcmF/rnm" for Collapsible.qml). When it is
      // not a font the path is "", and FontSpecimen builds no loader.
      //
      // The shared specimen (FontSpecimen), as the preview pane and
      // oracle's Font button show a face.
      FontSpecimen {
        id: lookSpec
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 20
        visible: look.face
        zoom: root.zoom
        path: look.facePath
      }

      // ── AND WHEN THERE IS NOTHING ───────────────────────────────
      // Its own item rather than a third state of the text above: that one
      // is a document — left-aligned, monospaced, scrollable, starting at
      // the top because that is where a file starts. This is a SENTENCE
      // ABOUT the file, and it belongs in the middle of the space it is
      // explaining rather than in the corner of it.
      //
      // Yellow, the ink this window gives a thing that can be acted on and
      // an answer that is not a failure: the file is fine, terminus simply
      // has no way to show it. Muted read as though something had gone
      // wrong and been swallowed.
      Text {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: lookCap.top
        // NOT WHILE ONE IS ON ITS WAY. "no preview available" is an answer
        // about the file, and during a decode there is no answer yet.
        // And not for something that PLAYS. A track with no cover art is
        // not a file terminus cannot show you — it is one there is nothing
        // to look AT in, which is a different sentence. The player below
        // says that better by simply being the thing.
        // ── AND NOT OVER THE TWO THAT NOW HAVE SOMETHING ────────
        // An archive whose listing is still being read says nothing
        // rather than apologising and then filling in — `arc` rather
        // than `tree`, so the gap before the rows arrive is silent too.
        visible: !lookShot.visible && !look.pending && !look.reading
                 && !look.hasText && !look.playable
                 && !look.arc && !look.face && !look.folder
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: "no preview available"
        color: Zenon.yellow
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(15)
      }

      // ── AND AN EMPTY DIRECTORY SAYS SO ─────────────────────────────
      // A directory with nothing in it drew nothing at all: its listing
      // has no rows, and "no preview available" is suppressed for
      // directories because the listing IS the preview. The card came up
      // blank, which reads as still loading rather than as an answer.
      //
      // ANSWERED, not merely absent, and that is the whole of the
      // condition. previewShown is the path the preview currently on
      // screen is ABOUT, so this waits until the reply is about THIS
      // directory — dirRows is empty during the fetch too, and saying
      // "empty" then would be the same wrong sentence one beat early.
      //
      // Muted rather than the yellow above: that one is an answer about
      // what terminus cannot do, and this is a fact about the directory.

      // ── A TRACK WITH NO COVER IS STILL SOMETHING TO LOOK AT ─────────
      // It was a mostly empty card with "no preview available" in small red
      // type across the middle of it. There is nothing to preview, true —
      // but there is plenty to SHOW: what is playing, how far through it is
      // and how much is left. That fills the space the apology sat in.
      Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -look.capH / 2
        width: parent.width - 48
        spacing: 14
        visible: look.playable && !look.vid && !lookShot.visible
                 && !look.pending

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          // THE ROW'S OWN GLYPH, not a codepoint written out here. The
          // listing already worked out what this file looks like — and a
          // hand-written escape is exactly how the first attempt at this
          // ended up drawing a lorry.
          text: look.row ? look.row.glyph : ""
          color: look.row ? root.inkFor(look.row) : Zenon.cyan
          font.family: Zenon.faceMono
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(44)
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: lookPlayer.duration > 0
            ? Terminus.formatClock(lookPlayer.position)
              + "   /   " + Terminus.formatClock(lookPlayer.duration)
            : "\u2026"
          color: Zenon.white
          font.family: Zenon.faceMono
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(20)
        }

        Meter {
          anchors.horizontalCenter: parent.horizontalCenter
          vertical: false
          value: lookPlayer.duration > 0
            ? lookPlayer.position / lookPlayer.duration : 0
          accent: Zenon.cyan
          thickness: 6
          segLength: 6
          segGap: 3
          deadZone: 0
          segCount: Math.max(10, Math.floor(parent.width / 9))
        }
      }

      // ── THE NAME, AS A BAR RATHER THAN A CAPTION ─────────────────
      // headBg over the panel's black, which is the same pairing the path
      // bar has with the window: a strip that is part of the surface and a
      // shade off it, rather than a separate thing laid on top.
      Rectangle {
        id: lookCap
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: look.capH
        color: Zenon.headBg

        // The seam every strip in this window uses. Without it the bar and
        // a dark picture above it ran together into one shape.
        Rectangle {
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: 1
          color: Zenon.border
        }

        // ── THE NAME LEFT, THE KEYS RIGHT ─────────────────────────
        // Centred, the name moved every time you stepped to a file with a
        // longer one — a title that shifts under the eye on every keypress,
        // in the one place you are pressing a key repeatedly. Pinned left it
        // starts in the same spot whatever it says, and the room it is not
        // using is where the keys go.
        // The row's own glyph, in the row's own ink. Shown for every
        // kind and not only for directories: conditioned on the kind it
        // would shift the name sideways as you step through a listing,
        // which is the one thing the bar is pinned left to avoid.
        Text {
          id: lookGlyph
          anchors.left: parent.left
          anchors.leftMargin: 14
          anchors.verticalCenter: parent.verticalCenter
          text: look.row ? (look.row.glyph || "") : ""
          color: look.row ? (look.row.ink || Zenon.white) : Zenon.white
          font.family: Zenon.faceMono
          font.weight: Zenon.weight
          // Larger than the name beside it. A nerd glyph set at the
          // text size reads smaller than the text does — it is drawn
          // inside the cell rather than filling it.
          font.pixelSize: Zenon.px(19)
        }

        Text {
          id: lookName
          anchors.left: lookGlyph.right
          anchors.leftMargin: 8
          anchors.right: lookKeys.left
          anchors.rightMargin: 14
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideMiddle
          text: look.row ? look.row.name : ""
          color: Zenon.white
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: Zenon.px(15)
        }

        // WHAT MOVES YOU, said on the bar rather than left to be discovered.
        // Quick look has no footer of its own — the caption bar IS the
        // chrome — so the hint lives beside the name it is about.
        Row {
          id: lookKeys
          anchors.right: parent.right
          anchors.rightMargin: 14
          anchors.verticalCenter: parent.verticalCenter
          spacing: 5

          // How far in, for the things that have a "far in". Only while
          // something is actually loaded — a duration of 0 is a file that
          // has not been opened yet, not a zero-length one.
          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: look.playable && lookPlayer.duration > 0
            text: Terminus.formatClock(lookPlayer.position)
              + " / " + Terminus.formatClock(lookPlayer.duration)
            color: Zenon.muted
            font.family: Zenon.faceMono
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(11)
          }
          KeyCap {
            anchors.verticalCenter: parent.verticalCenter
            visible: look.playable
            label: lookPlayer.playbackState === MediaPlayer.PlayingState
              ? "p pause" : "p play"
            fontSize: 11
          }
          // ── THE QUICK ACTIONS THIS FILE HAS ────────────────────
          // Shown only for the kind of file they work on, the same rule
          // the play chip above follows: a hint for a key that does
          // nothing is worse than no hint.
          KeyCap {
            anchors.verticalCenter: parent.verticalCenter
            visible: look.pic
            label: "[ / ]"
            fontSize: 11
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: look.pic
            leftPadding: 3
            rightPadding: 8
            text: "rotate"
            color: Zenon.muted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(12)
          }
          KeyCap {
            anchors.verticalCenter: parent.verticalCenter
            visible: look.vid
            label: "e"
            fontSize: 11
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: look.vid
            leftPadding: 3
            rightPadding: 8
            text: "audio"
            color: Zenon.muted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(12)
          }
          KeyCap {
            anchors.verticalCenter: parent.verticalCenter
            label: "h / l"
            fontSize: 11
          }
          KeyCap {
            anchors.verticalCenter: parent.verticalCenter
            label: "\u2190 / \u2192"
            fontSize: 11
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: 3
            rightPadding: 8
            text: "prev / next"
            color: Zenon.muted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(12)
          }

          // ── A DOCUMENT'S PAGES, ONLY FOR ONE THAT HAS SEVERAL ───────
          KeyCap {
            anchors.verticalCenter: parent.verticalCenter
            visible: look.docPages > 1
            label: "PgUp / PgDn"
            fontSize: 11
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: look.docPages > 1
            leftPadding: 3
            rightPadding: 8
            text: "page"
            color: Zenon.muted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(12)
          }
          KeyCap {
            anchors.verticalCenter: parent.verticalCenter
            visible: look.docPages > 1
            label: "Home / End"
            fontSize: 11
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: look.docPages > 1
            leftPadding: 3
            rightPadding: 8
            text: "first / last"
            color: Zenon.muted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(12)
          }

          // ── AND THE OTHER AXIS, ONLY WHEN IT HAS ONE ────────────────
          // Shown for a document that is taller than its pane and nowhere
          // else: over a picture there is nothing to scroll, and a hint for
          // a key that does nothing is worse than no hint.
          KeyCap {
            anchors.verticalCenter: parent.verticalCenter
            visible: look.scrollable
            label: "j / k"
            fontSize: 11
          }
          KeyCap {
            anchors.verticalCenter: parent.verticalCenter
            visible: look.scrollable
            label: "\u2191 / \u2193"
            fontSize: 11
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: look.scrollable
            leftPadding: 3
            text: "scroll"
            color: Zenon.muted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(12)
          }
        }
      }
    }
  }
}

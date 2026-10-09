// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE PROPERTIES CARD — terminus' card body, shared with picasso (2026-10-07).
// What the listing cannot fit: the whole path, the owner, the exact byte
// count, and for a selection the total; the picture beside the facts; and the
// permissions page behind its row. `stat` is asked once for the set.
//
// The holder puts it inside a Sheet of its own (terminus hangs it from its
// bar, picasso floats it), sizes the card by `wantW` and `implicitHeight`,
// and answers its signals:
//
//   opened()                 show() has something to say — put the sheet up
//   closed()                 Close was pressed
//   menuWanted(item, rows)   the "open with" row's menu, as CardPopup rows
//
// `host` is what the card asks of the window, all optional apart from the
// first group:
//   enrich(rows) warn(t) run(cmd) status (written)  inkFor(r)
//   tagMarks {path: [name]}  tagInk(name)
//   thumbKind(r) thumbHas(r) thumbJob(r, kind) thumbNow(job) thumbFile {path: file}
//   openWithApps openWithDefault appsScanned appsPath (written)
//   findApps(path) setDefaultApp(id) removeApp(id) beginOpenWith(path, launch)

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../morpheus"
import "terminus.js" as Terminus

Item {
  id: props

  property var host: null
  signal opened()
  signal closed()
  signal menuWanted(Item item, var rows)

  implicitHeight: propsCol.implicitHeight

  // ── AS WIDE AS WHAT IT IS SAYING ──────────────────────────────────────
  // The widest fact measured (FontMetrics.advanceWidth, which a binding can
  // call), plus the row's own layout: 18 of padding, the 118 label column,
  // 12 of spacing, the value, 18 again — and the picture's own 18px inset
  // and width beside it. Between a floor that stops a one-line panel from
  // being a slot and a ceiling where elide takes over.
  readonly property real factsW: {
    let w = 0;
    const rows = props.facts;
    for (let i = 0; i < rows.length; i++) {
      const t = propFm.advanceWidth(String(rows[i][1]));
      if (t > w) w = t;
    }
    return 18 + 118 + 12 + w + 18;
  }
  readonly property real wantW: Math.max(420, Math.min(760,
    (props.many ? 0 : 18 + propShotBox.width + 10) + props.factsW))

  // Each show() is a generation, which the probes below answer only for —
  // see PropProc.qml.
  property int gen: 0

  property var rows: []
  property string owner: ""
  // -1 while du is still walking, so the row can say so rather than
  // showing a zero that looks like an answer
  property real walked: -1
  // -1 until the walk answers, the same sentinel `walked` uses
  property int files: -1
  property int dirs: -1
  // "" = never asked, "…" = running, otherwise the digest or an error
  property string checksum: ""
  // dimensions and format, for an image; null for anything else
  property var imageInfo: null

  readonly property bool many: props.rows.length > 1
  readonly property int total: {
    let n = 0;
    for (const r of props.rows) if (!r.isDir) n += r.size;
    return n;
  }

  function ask() {
    const sel = props.host.acting ? props.host.acting() : [];
    if (sel.length === 0) return;
    props.show(sel);
  }

  // Properties of THE DIRECTORY YOU ARE IN, which is what a right click on
  // empty space is asking about — there is no row selected and the one the
  // cursor happens to be on is not the answer.
  //
  // It needs a row object and the listing has none: the listing is of this
  // directory's CHILDREN. So one is made the same way a search result's
  // is, out of `stat` — the same command, parser and enrich the results
  // path already uses, so the card gets a row indistinguishable from one
  // that came out of a listing.
  function askPath(path) {
    if (path === "" || hereProc.running) return;
    props.wantPath = path;
    hereProc.command = Terminus.statArgv([path]);
    hereProc.running = true;
  }

  property string wantPath: ""

  // One string, because "0 files · 0 directories" and "counting…" are
  // the same row in two states, and deciding which at each call site is how
  // the two shapes of this card drift apart.
  function countText() {
    if (props.files < 0 || props.dirs < 0) return "counting\u2026";
    const f = props.files + (props.files === 1 ? " file" : " files");
    const d = props.dirs + (props.dirs === 1 ? " directory" : " directories");
    return f + "  ·  " + d;
  }

  function show(sel) {
    props.gen++;
    props.rows = sel;
    // The card carries an "open with" row for a single file, and the scan
    // that fills it used to be started only by the menu — so reaching
    // properties by its key showed an empty one.
    props.host.appsPath = (sel.length === 1 && !sel[0].isDir) ? sel[0].path : "";
    props.host.findApps(props.host.appsPath);
    props.owner = "";
    props.walked = -1;
    props.files = -1;
    props.dirs = -1;
    // The cursor row's mode, as the permissions card used: a mixed set
    // has no single answer and picking one is more honest than zero.
    props.permMode = (sel[0] && sel[0].mode) || 0;
    props.permWas = props.permMode;
    props.permCursor = 0;
    // Always opens on properties, whichever page you left it on.
    props.tab = 0;
    props.opened();
    // only when there is a directory in the set: for plain files the size
    // is already known and du would be a process for nothing
    if (sel.some((r) => r.isDir)) {
      sizeProc.ask(Terminus.shArgv(Terminus.sizeCommand(sel.map((r) => r.path))));
      countProc.ask(Terminus.shArgv(Terminus.countCommand(sel.map((r) => r.path))));
    }
    ownerProc.ask(["sh", "-c",
      "stat -c '%U:%G' -- " + Strings.shellQuote(sel[0].path) + " 2>/dev/null"]);

    // Dimensions come for free — identify reads a header, not a file — so
    // an image simply has them. A CHECKSUM does not: sha256 over a few
    // gigabytes takes real time, so it is a button, and only the digest you
    // asked for is ever computed.
    props.checksum = "";
    props.imageInfo = null;
    // The thumbnail panel above shows anything the cache can make — a
    // video's frame, a track's cover, a document's page, a picture Qt
    // cannot open — from the same pool the grid uses, which may not have
    // been asked yet if you have only ever seen this directory as a list.
    // A picture Qt CAN open is shown as itself and needs nothing.
    const one = props.many ? null : sel[0];
    const oneKind = one ? props.host.thumbKind(one) : "";
    if (oneKind !== "" && oneKind !== "i" && !props.host.thumbHas(one))
      props.host.thumbNow(props.host.thumbJob(one, oneKind));
    if (!props.many && !sel[0].isDir && Terminus.isImage(sel[0].name)) {
      imageProc.ask(["sh", "-c", Terminus.imageInfoCommand(sel[0].path)]);
    }
  }

  Process {
    id: hereProc
    stdout: StdioCollector {
      id: hereOut
      waitForEnd: true
      onStreamFinished: {
        const rows = props.host.enrich(Terminus.parseStat(hereOut.text));
        if (rows.length === 0) {
          props.host.warn("could not read " + Terminus.basename(props.wantPath));
          return;
        }
        props.show(rows);
      }
    }
  }

  function computeChecksum() {
    const r = props.rows[0];
    if (!r || r.isDir || sumProc.running) return;
    props.checksum = "\u2026";
    sumProc.command = ["sh", "-c", Terminus.checksumCommand(r.path)];
    sumProc.running = true;
  }


  // ── WHAT THE PANEL SAYS, AS A LIST ────────────────────────────────
  // Hoisted off the Repeater so the CARD can measure it. A panel that is
  // as wide as its longest value has to know what its values are before it
  // has drawn any of them, and a model written inline in the view is not
  // available to anything else.
  // 16, which is what a value is drawn at — a measurement taken at the
  // wrong size is a card that fits nothing.
  FontMetrics {
    id: propFm
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(16)
  }

  // The NAME of whatever currently opens this type, not its desktop id: the
  // id is what the association database deals in, the name is what you
  // recognise. Falls back to the id when the scan found no entry for it,
  // which is what a stale association looks like.
  readonly property string openWithLabel: {
    if (!props.host.appsScanned) return "\u2026";
    const id = props.host.openWithDefault;
    if (id === "") return "nothing";
    for (const a of props.host.openWithApps) if (a.id === id) return a.name;
    return id;
  }

  // ONE LIST. Choosing a row makes that handler the default; the cross at
  // the end of a row takes the handler away. Both verbs live on the row
  // they are about, which is why there is no longer a "Remove" submenu —
  // that was the same names listed twice, doing different things depending
  // on which copy you had walked into.
  function openWithMenu(item) {
    const apps = props.host.openWithApps;
    const out = [];
    for (let i = 0; i < apps.length; ++i) {
      const id = apps[i].id;
      out.push({ label: apps[i].name,
                 key: id === props.host.openWithDefault ? "default" : "",
                 act: () => props.host.setDefaultApp(id),
                 strike: () => props.host.removeApp(id) });
    }
    // a holder without terminus' open-with card offers only what is listed
    if (props.host.beginOpenWith) {
      if (out.length > 0) out.push({ sep: true });
      out.push({ label: "Add another\u2026",
                 act: () => props.host.beginOpenWith(props.host.appsPath, false) });
    }
    props.menuWanted(item, out);
  }

  // ── THE MODE, WHICH THIS CARD NOW OWNS ────────────────────────
  // permMode is what the grid is showing and permWas is what the file
  // actually has; the Apply button is the difference between them.
  // Nothing is written until it is pressed — properties is a card you
  // open to LOOK at something, and a chmod that happened because you
  // clicked a box while reading would be the one surprise it must not
  // spring.
  // ── TWO PAGES, ONE CARD ───────────────────────────────────────
  // Permissions used to be a sheet of its own, which meant two cards
  // about one file and no way between them without closing one and
  // reaching for a different key. They are one card now, and
  // properties is still what opens: reading is the common act and
  // changing the mode is the rare one, so the rare one is a tab away
  // rather than in the way.
  // 0 is properties, 1 is permissions. Not a tab index any more — the
  // strip is gone — but still the page the card is showing.
  property int tab: 0
  // Whether there is a second page at all. A mixed selection has no
  // single mode to edit, so it has no permissions row to open and no
  // page to open onto.
  readonly property bool hasPerms: !props.many

  property int permMode: 0
  property int permWas: 0
  property int permCursor: 0
  readonly property int permCursorBit:
    [4, 2, 1][props.permCursor % 3] << (6 - Math.floor(props.permCursor / 3) * 3)
  readonly property bool permDirty:
    (props.permMode & 511) !== (props.permWas & 511)
  readonly property var permPaths: props.rows.map((r) => r.path)

  function togglePermBit() {
    props.permMode = props.permMode ^ props.permCursorBit;
  }

  function applyPerms() {
    if (!props.permDirty) return;
    props.host.run(Terminus.chmodCommand(props.permPaths, props.permMode));
    props.permWas = props.permMode;
    props.host.status = "permissions set";
  }

  // Every tag on the selection, once each. One file's own list, or the
  // union across several — sorted, so the order does not jump about as
  // the selection changes.
  readonly property var tagNames: {
    const seen = ({});
    const out = [];
    for (let i = 0; i < props.rows.length; ++i) {
      const names = props.host.tagMarks[props.rows[i].path] || [];
      for (let j = 0; j < names.length; ++j)
        if (!seen[names[j]]) { seen[names[j]] = true; out.push(names[j]); }
    }
    return out.sort();
  }

  readonly property var facts: {
              const r = props.rows[0];
              if (!r) return [];
              if (props.many) {
                let dirs = 0;
                for (const x of props.rows) if (x.isDir) dirs++;
                return [
                  ["items", props.rows.length + " (" + dirs + " directories)"],
                  ["total size", props.walked < 0
                    ? (dirs > 0 ? "measuring\u2026"
                        : Terminus.formatSize(props.total) + "  ·  " + props.total + " bytes")
                    : Terminus.formatSize(props.walked) + "  ·  " + props.walked + " bytes"],
                  ["location", Terminus.dirname(r.path)]
                ].concat(dirs > 0 ? [["contains", props.countText()]] : []);
              }
              // no "name" row: it is the card's own title now
              return [
                ["location", Terminus.dirname(r.path)],
                ["type", r.isDir ? "directory"
                  : (r.isLink ? "symbolic link"
                    : (Terminus.categoryOf(r.name) || (r.isExec ? "executable" : "file")))],
                ["size", r.isDir
                  ? (props.walked < 0 ? "measuring\u2026"
                      : Terminus.formatSize(props.walked) + "  ·  " + props.walked + " bytes")
                  : Terminus.formatSize(r.size) + "  ·  " + r.size + " bytes"],
                ["modified", Terminus.formatTime(r.mtime)],
                ["owner", props.owner === "" ? "…" : props.owner],
                // ── AND THE WAY TO THE GRID ──────────────────────
                // It reads as a fact and acts as a door. Both
                // spellings, the same pair the grid itself shows, so
                // the page you arrive at is recognisably the row you
                // clicked rather than a different subject.
                ["permissions",
                  ("000" + (props.permMode & 511).toString(8)).slice(-3)
                  + "  \u00b7  " + Terminus.modeString(props.permMode)]
              ].concat(
                // What is inside it, for a directory — the natural companion
                // to the size two rows up, and the one thing this card could
                // not tell you about a directory.
                r.isDir ? [["contains", props.countText()]] : [],
                props.imageInfo
                  ? [["image", props.imageInfo.dims + "  \u00b7  "
                      + props.imageInfo.format + "  \u00b7  "
                      + props.imageInfo.depth + "  \u00b7  "
                      + props.imageInfo.colorspace]]
                  : [],
                r.isDir ? [] : [["open with", props.openWithLabel]],
                r.isDir ? []
                  : [["sha256", props.checksum === "" ? "click to compute"
                      : props.checksum]]);
  }


  Column {
    id: propsCol
    width: parent.width

    // The caption band stood here. It is the floating card's own
    // header now — see Sheet.floating, which draws the title and glyph.
    // Its own air stays: the sheet adds none, so a card whose first row
    // does not carry any has to say so.
    Item { width: 1; height: 10 }

    // ── NO TAB STRIP ───────────────────────────────────────
    // There were two pills here, Properties and Permissions, which
    // is a lot of chrome for a card with one subject and a second
    // page that most openings never want. The permissions row in
    // the facts below is the way through now: it reads as a fact
    // and acts as a door, so the card opens on what you came for
    // and the rare thing is one click away rather than always in
    // view. Escape on that page comes back here; see the key
    // handler.

    // picture on the left, facts on the right
    Item {
      id: propBody
      visible: props.tab === 0
      width: parent.width
      height: Math.max(props.many ? 0 : propShotBox.height + 4,
                       propFacts.implicitHeight)

      // What it LOOKS like, beside what it is.
      //
      // A picture or a video shows itself; a font shows its own A; anything
      // else shows the glyph the listing gives it, which is at least the
      // mark you picked the row out by. A multi-selection shows nothing at
      // all — there is no single thing to be a picture of, and the first
      // item's thumbnail standing in for eleven files would be a small lie
      // at the top of a panel of facts.
      //
      // Down the LEFT rather than across the top: the rows beside it are a
      // label column and a value column, and a picture over them pushed
      // every fact half a panel further down for no reason. On the left it
      // sits in the margin the labels already leave.
        Item {
          id: propShotBox
          anchors.left: parent.left
          anchors.leftMargin: 18
          anchors.verticalCenter: parent.verticalCenter

          // ── A PICTURE IS NOT A GLYPH, AND NEED NOT BE ITS SIZE ──
          // Both stand here, so both were 96 — the size a 56px glyph
          // wants to sit in with air around it, and a photograph shown at
          // 88 on its long edge is a stamp. They answer different
          // questions: the glyph is a MARK, the one you picked the row
          // out by, and only has to be recognisable; the thumbnail is the
          // thing itself, and this is the one panel where you look AT it.
          //
          // AS TALL AS THE FACTS BESIDE IT, which is the one measurement
          // in this panel that means anything — the picture and the
          // column of figures are the two halves of the answer, so they
          // are the same height and the panel is a rectangle rather than
          // a picture with a column hanging off it.
          //
          // Safe to measure against: propFacts' rows are a fixed 28 each,
          // so its implicitHeight is a row count and does not depend on
          // the width this box leaves it. Bound the other way round it
          // would be a loop.
          readonly property int glyphBox: 96
          readonly property real shotH: Math.max(88,
            propFacts.implicitHeight)
          // A ceiling for panoramas: 2560x1080 as tall as the facts
          // would still be half the card wide and crowd the figures.
          readonly property real maxW: 320

          // The box IS the picture, so the facts start right beside it
          // whatever shape it turned out to be.
          width: props.many ? 0
            : (propShotClip.visible ? propShotClip.width
                                    : propShotBox.glyphBox)
          height: propShotClip.visible ? propShotClip.height
                                       : propShotBox.glyphBox
          visible: !props.many

        ClippingRectangle {
          id: propShotClip
          anchors.centerIn: parent
          visible: propShot.status === Image.Ready
          color: "transparent"
          radius: Zenon.windowRadius

          // sized from the decoded source, never from paintedWidth — the
          // note over the preview pane's thumbClip has the reason
          readonly property real ar:
            propShot.implicitWidth > 0 && propShot.implicitHeight > 0
              ? propShot.implicitWidth / propShot.implicitHeight : 1
          // The facts' height, unless that would make it wider than
          // the ceiling — then the width decides and the height follows.
          readonly property real fitH: Math.min(propShotBox.shotH,
            propShotBox.maxW / Math.max(0.01, propShotClip.ar))
          width: Math.max(1, propShotClip.fitH * propShotClip.ar)
          height: Math.max(1, propShotClip.fitH)

          Image {
            id: propShot
            anchors.fill: parent
            // NOT CLEARED ON CLOSE. It used to empty the moment the
            // card was told to go, so the picture became the glyph on
            // the first frame of the fade and the card re-laid itself
            // out — narrower, recentred — while it was leaving.
            //
            // THE POOL'S COPY FIRST, even for a picture Qt can open:
            // a 480px JPEG decodes in a few milliseconds, so it is
            // decoded on the spot and the card ARRIVES with its
            // picture. An original is a decode of unknown size, so it
            // stays asynchronous — and the card opens on the glyph and
            // swaps — only when the pool has nothing yet.
            readonly property string pooledFile: {
              if (props.many) return "";
              const r = props.rows[0];
              if (!r || r.isDir || props.host.thumbKind(r) === "") return "";
              return props.host.thumbFile[r.path] || "";
            }
            source: {
              if (props.many) return "";
              const r = props.rows[0];
              if (!r || r.isDir) return "";
              if (propShot.pooledFile !== "") return "file://" + propShot.pooledFile;
              return props.host.thumbKind(r) === "i" ? Strings.fileUrl(r.path) : "";
            }
            fillMode: Image.PreserveAspectFit
            asynchronous: propShot.pooledFile === ""
            // Decoded at twice the drawn size, so the panel is sharp on
            // a scaled display and has something to work with if the box
            // grows again.
            sourceSize.width: 384
            sourceSize.height: 384
          }
        }

        FontLoader {
          id: propFace
          source: {
            if (props.many) return "";
            const r = props.rows[0];
            return r && !r.isDir && Terminus.isFont(r.name) ? Strings.fileUrl(r.path) : "";
          }
        }

        Text {
          anchors.centerIn: parent
          visible: !propShotClip.visible
          readonly property bool specimen: propFace.status === FontLoader.Ready
          text: {
            const r = props.rows[0];
            if (!r) return "";
            return specimen ? "Ag" : r.glyph;
          }
          color: {
            const r = props.rows[0];
            return r ? props.host.inkFor(r) : Zenon.muted;
          }
          font.family: specimen ? propFace.font.family
            : Zenon.face
          font.pixelSize: Zenon.px(56)
        }
    }


      Column {
        id: propFacts
        anchors.left: props.many ? parent.left : propShotBox.right
        anchors.leftMargin: props.many ? 0 : 10
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

      // ── TAGS, WHICH ARE NOT A STRING ─────────────────────────
      // A row of its own rather than an entry in `facts`, because
      // every fact there is a label and a piece of text and a tag is
      // a label and a COLOUR. Flattening them to "red · work" would
      // hand back exactly what the colour was carrying.
      //
      // Absent, not empty, for an untagged file: a card that says
      // "tags —" about most files is a row of nothing on most cards.
      // For several files at once it is the union, with a count, since
      // "which tags are in this selection" is the answerable question.
      Row {
        width: propFacts.width
        height: 28
        leftPadding: 18
        rightPadding: 18
        spacing: 12
        visible: props.tagNames.length > 0

        Text {
          width: 118
          height: parent.height
          horizontalAlignment: Text.AlignRight
          verticalAlignment: Text.AlignVCenter
          text: "tags"
          color: Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(16)
        }

        Row {
          height: parent.height
          spacing: 12

          Repeater {
            model: props.tagNames
            delegate: Row {
              required property var modelData
              height: 28
              spacing: 5

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "\uF02B"
                color: props.host.tagInk(modelData)
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(15)
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: modelData
                color: Zenon.white
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(16)
              }
            }
          }
        }
      }

      Repeater {
        model: props.facts

        delegate: Row {
          required property var modelData
          width: propFacts.width
          height: 28
          leftPadding: 18
          rightPadding: 18
          spacing: 12

          Text {
            width: 118
            height: parent.height
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            text: modelData[0]
            color: Zenon.muted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(16)
          }

          Text {
            id: propValue
            width: propFacts.width - 118 - 48
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            text: modelData[1]
            elide: Text.ElideMiddle
            // The one row you can act on says so by looking like a link
            // until it has an answer.
            readonly property bool askable:
              modelData[0] === "sha256" && props.checksum === ""
            // The other row you can act on. Same treatment, so "this one
            // does something" is one idea in this card rather than two.
            readonly property bool pickable:
              modelData[0] === "open with" && props.host.appsScanned
            // The third. A mixed selection has no single mode, so it
            // has no row to open and nothing to open it onto.
            readonly property bool opensPerms:
              modelData[0] === "permissions" && !props.many
            readonly property bool acts: propValue.askable
              || propValue.pickable || propValue.opensPerms
            color: propValue.acts
              ? (sumHov.hovered ? Zenon.cyan : Zenon.keyInk) : Zenon.white
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(16)

            HoverHandler {
              id: sumHov
              enabled: propValue.acts
            }

            MouseArea {
              anchors.fill: parent
              enabled: propValue.acts
              onClicked: {
                if (propValue.opensPerms) props.tab = 1;
                else if (propValue.pickable) props.openWithMenu(propValue);
                else props.computeChecksum();
              }
            }
          }
        }
      }

      // ── PERMISSIONS, WHICH USED TO BE A CARD OF ITS OWN ───────
      // Properties already listed the mode as a line of text you
      // could read and not change, and a second sheet existed to
      // change it. Two cards about one file, and the one you opened
      // first was always the wrong one.
      //
      // The grid is the same grid, moved: same nine boxes, same
      // presets, same keyboard. What it lost is a card, a scrim, a
      // shadow and five registrations — and what it gained is being
      // in the place you were already looking when you wondered.


      }
    }

    Item { width: 1; height: 6 }

    Column {
      id: permGrid
      width: parent.width
      readonly property int gap: 12
      readonly property int labelW: 78
      readonly property int cellW: 62
      readonly property int octW: 40
      // The tab AND something to show one for: a mixed selection has
      // no tab to reach this page with, so it can never be on it.
      visible: props.tab === 1 && props.rows.length > 0 && !props.many


    // ONE RHYTHM. Everything below the title is 12px apart and the grid
    // is centred rather than left-padded — it used to start 40px in and
    // end 146px short of the right edge, which is what made the card
    // look like it was leaning.

    // The caption band stood here. It is the floating card's own
    // header now — see Sheet.floating, which draws the title and glyph.
    // The rhythm's own gap stays: the sheet adds no air, so the first
    // row has to bring it like every other row does.
    Item { width: 1; height: permGrid.gap }

    // The answer in both spellings on one line — the octal you would
    // type at chmod and the rwx string ls prints. They are the same
    // number said twice, so they belong side by side rather than stacked.
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 16

      // ── AND YOU CAN TYPE IT ─────────────────────────────────
      // Clicking nine boxes to say "750" is the long way round when
      // the number is already in your head. The octal is a field:
      // three digits (or the nine rwx letters) and the grid below
      // follows as you type; Return or a click away hands the keys
      // back to the sheet, Escape puts the number back as it was.
      Item {
        anchors.verticalCenter: parent.verticalCenter
        width: permOctal.contentWidth + 4
        height: permOctal.contentHeight
        readonly property string shown: ("000" + (props.permMode & 511).toString(8)).slice(-3)

        TextInput {
          id: permOctal
          anchors.centerIn: parent
          width: Math.max(contentWidth, 10)
          text: parent.shown
          maximumLength: 9
          color: Zenon.cyan
          selectionColor: Zenon.selBg
          selectedTextColor: Zenon.white
          font.family: Zenon.faceMono
          font.weight: Font.Bold
          font.pixelSize: Zenon.px(30)
          cursorDelegate: Caret { field: permOctal }
          selectByMouse: true
          // valid as you go: octal digits, or the rwx spelling
          readonly property int parsed: Terminus.parseModeText(permOctal.text)
          onTextEdited: if (permOctal.parsed >= 0)
            props.permMode = (props.permMode & ~511) | permOctal.parsed
          onActiveFocusChanged: {
            if (permOctal.activeFocus) { permOctal.selectAll(); return; }
            permOctal.text = Qt.binding(() => permOctal.parent.shown);
          }
          onAccepted: dialogKeys.forceActiveFocus()
          Keys.onEscapePressed: {
            props.permMode = props.permWas;
            dialogKeys.forceActiveFocus();
          }
        }
        // the field's own line, so it reads as something to click
        Rectangle {
          anchors.top: permOctal.bottom
          anchors.horizontalCenter: permOctal.horizontalCenter
          width: permOctal.width + 6
          height: 1
          color: permOctal.activeFocus
            ? (permOctal.parsed >= 0 ? Zenon.cyan : Zenon.red)
            : (permOctalMa.containsMouse ? Zenon.border : "transparent")
        }
        MouseArea {
          id: permOctalMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.IBeamCursor
          acceptedButtons: Qt.NoButton
        }
      }

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 1
        height: 24
        color: Zenon.border
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: Terminus.modeString(props.permMode)
        color: Zenon.sand
        font.family: Zenon.faceMono
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(21)
      }
    }

    Item { width: 1; height: permGrid.gap }

    // The four modes anyone actually types. A permissions dialog whose
    // quickest route to 755 is nine clicks is a dialog that has not
    // finished the job.
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 8

      Repeater {
        model: [
          ["644", 420], ["755", 493], ["600", 384], ["700", 448]
        ]

        delegate: Rectangle {
          required property var modelData
          readonly property bool on: (props.permMode & 511) === modelData[1]
          width: 62
          height: 24
          radius: 4
          color: on ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.20)
            : (presetHov.hovered ? Zenon.border : "transparent")
          border.width: 1
          border.color: Zenon.border
          Behavior on color {
            ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
          }

          Text {
            anchors.centerIn: parent
            text: modelData[0]
            color: parent.on ? Zenon.cyan : Zenon.muted
            font.family: Zenon.faceMono
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(14)
          }

          HoverHandler { id: presetHov }
          MouseArea {
            anchors.fill: parent
            // the high bits — setuid and friends — are left alone: this
            // is a shortcut for the nine, not a reset of the whole mode
            onClicked: props.permMode = (props.permMode & ~511) | modelData[1]
          }
        }
      }
    }

    Item { width: 1; height: permGrid.gap + 2 }

    Rectangle {
      height: 1
      color: Zenon.border
    }

    Item { width: 1; height: permGrid.gap }

    // A GRID with its columns named, rather than three unlabelled rows
    // of three: r, w and x are not obvious from the boxes alone, and the
    // heading costs one row of small type.
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      height: 18

      Item { width: permGrid.labelW; height: 1 }
      Repeater {
        model: ["read", "write", "exec"]
        delegate: Text {
          required property var modelData
          width: permGrid.cellW
          height: 18
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          text: modelData
          color: Zenon.border
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(12)
        }
      }
      Item { width: permGrid.octW; height: 1 }
    }

    // three rows of three, in the order chmod writes them
    Repeater {
      model: [["owner", 6], ["group", 3], ["other", 0]]

      delegate: Row {
        id: permRow
        required property var modelData
        required property int index
        readonly property int shift: modelData[1]
        anchors.horizontalCenter: parent.horizontalCenter
        height: 34

        Text {
          width: permGrid.labelW
          height: parent.height
          verticalAlignment: Text.AlignVCenter
          text: modelData[0]
          color: Zenon.white
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(16)
        }

        Repeater {
          model: [["r", 4], ["w", 2], ["x", 1]]

          delegate: Item {
            required property var modelData
            required property int index
            width: permGrid.cellW
            height: parent.height

            readonly property int bit: modelData[1] << permRow.shift
            readonly property bool on: (props.permMode & bit) !== 0
            readonly property bool here:
              props.permCursor === permRow.index * 3 + index

            Rectangle {
              anchors.centerIn: parent
              width: 50
              height: 26
              radius: 4
              color: parent.on
                ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.20)
                : (bitHov.hovered ? Zenon.border : "transparent")
              border.width: 1
              border.color: Zenon.border
              Behavior on color {
                ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
              }

              Text {
                anchors.centerIn: parent
                text: modelData[0]
                color: parent.parent.on ? Zenon.cyan : Zenon.muted
                font.family: Zenon.faceMono
                font.weight: Font.Bold
                font.pixelSize: Zenon.px(16)
              }
            }

            HoverHandler { id: bitHov }
            MouseArea {
              anchors.fill: parent
              onClicked: {
                props.permCursor = permRow.index * 3 + parent.index;
                props.permMode = props.permMode ^ parent.bit;
              }
            }
          }
        }

        // This row's own octal digit, so the three boxes and the number
        // at the top are visibly the same statement.
        Text {
          width: permGrid.octW
          height: parent.height
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          text: String((props.permMode >> permRow.shift) & 7)
          color: Zenon.muted
          font.family: Zenon.faceMono
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(15)
        }
      }
    }

    Item { width: 1; height: permGrid.gap + 2 }

    Rectangle {
      height: 1
      color: Zenon.border
    }

    // ── ONLY WHEN THERE IS SOMETHING TO COMMIT ──────────────
    // The permissions CARD had Cancel and Apply because it was a
    // dialog: it existed to ask a question and had to be answered.
    // Properties is not — you open it to read, and most of the time
    // you will never touch a box. So the row is absent until the
    // grid differs from the file, and "Cancel" became "Revert",
    // which is what it now means: put the boxes back, stay here.
    Item {
      width: parent.width
      height: props.permDirty ? 54 : 8
      visible: true

      Row {
        anchors.centerIn: parent
        spacing: 12
        visible: props.permDirty

        DialogButton {
          label: "Revert"
          ink: Zenon.muted
          onClicked: props.permMode = props.permWas
        }

        DialogButton {
          label: "Apply"
          ink: Zenon.cyan
          primary: true
          onClicked: props.applyPerms()
        }
      }
    }
    }
    Item { width: 1; height: 10 }

    Rectangle {
      width: parent.width
      height: 1
      color: Zenon.border
    }

    Item {
      width: parent.width
      height: 46

      Row {
        anchors.centerIn: parent
        spacing: 8

        // ── OUT OF THE PAGE, NOT OUT OF THE CARD ─────────────
        // The permissions page is reached by clicking a row in
        // properties, and once the tab strip went it had no visible
        // way back — Escape and Tab both do it and neither is
        // written anywhere. Beside Close because the two are the
        // same kind of answer at different depths: one leaves the
        // page, the other leaves the card.
        //
        // A positioner skips an invisible child, so on the
        // properties page Close is centred exactly as it was.
        DialogButton {
          visible: props.tab === 1
          label: "Back"
          ink: Zenon.muted
          onClicked: props.tab = 0
        }

        DialogButton {
          label: "Close"
          ink: Zenon.cyan
          primary: true
          onClicked: props.closed()
        }
      }
    }
  }

  // ── THE CARD'S KEYS ───────────────────────────────────────────────────
  // For the holder to hand on while the card is up; true when it was one of
  // the card's. Escape is the holder's (terminus closes the card with it).
  function handleKey(k) {
    // ── THE PERMISSIONS PAGE HAS ITS OWN KEYS ──────────────────
    // The same nine-box keyboard the permissions sheet had, now
    // reached through the card's second tab. Left/right/up/down walk
    // the grid, space flips a bit, Return writes it.
    if (props.tab === 1) {
      if (k === Qt.Key_Return || k === Qt.Key_Enter) {
        props.applyPerms();
      } else if (k === Qt.Key_Left) {
        props.permCursor = (props.permCursor + 8) % 9;
      } else if (k === Qt.Key_Right) {
        props.permCursor = (props.permCursor + 1) % 9;
      } else if (k === Qt.Key_Up) {
        props.permCursor = (props.permCursor + 6) % 9;
      } else if (k === Qt.Key_Down) {
        props.permCursor = (props.permCursor + 3) % 9;
      } else if (k === Qt.Key_Space) {
        props.togglePermBit();
      } else if (k === Qt.Key_Tab
                 || k === Qt.Key_Escape) {
        // BACK, NOT SHUT. With the tab strip gone this is the way
        // out of the second page, and it is the one Escape already
        // means everywhere else in this window: unwind what you are
        // in the middle of and stop there. A second Escape, now on
        // the properties page, closes the card as it always did.
        props.tab = 0;
      }
      return true;
    }

    // properties: Tab changes page, Return closes it, and the one
    // thing in it you can ask for is the checksum
    if (k === Qt.Key_Tab) {
      if (props.hasPerms) props.tab = 1;
    } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
      props.closed();
    } else if (k === Qt.Key_S) {
      props.computeChecksum();
    }
    return k === Qt.Key_Tab || k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_S;
  }

  // ── the probes, each answering only its own generation (PropProc.qml) ─

  PropProc {
    id: sizeProc
    liveGen: props.gen
    stdout: StdioCollector {
      id: sizeOut
      waitForEnd: true
      onStreamFinished: if (sizeProc.current) props.walked = parseFloat(String(sizeOut.text).trim()) || 0
    }
  }

  // HOW MANY, beside how big. A size answers "will this fit"; a count answers
  // "what am I about to move", and for a directory those are different
  // questions — 30GB in four files and 30GB in ninety thousand are the same
  // row on this card and nothing alike to copy.
  PropProc {
    id: countProc
    liveGen: props.gen
    stdout: StdioCollector {
      id: countOut
      waitForEnd: true
      onStreamFinished: {
        if (!countProc.current) return;
        const n = String(countOut.text || "").trim().split("\n");
        const f = parseInt(n[0], 10);
        const d = parseInt(n[1], 10);
        props.files = isNaN(f) ? -1 : f;
        props.dirs = isNaN(d) ? -1 : d;
      }
    }
  }

  PropProc {
    id: ownerProc
    liveGen: props.gen
    stdout: StdioCollector {
      id: ownerOut
      waitForEnd: true
      onStreamFinished: if (ownerProc.current) props.owner = String(ownerOut.text || "").trim()
    }
  }

  PropProc {
    id: imageProc
    liveGen: props.gen
    stdout: StdioCollector {
      id: imageOut
      waitForEnd: true
      onStreamFinished: if (imageProc.current) props.imageInfo = Terminus.parseImageInfo(imageOut.text)
    }
  }

  Process {
    id: sumProc
    stdout: StdioCollector {
      id: sumOut
      waitForEnd: true
      onStreamFinished: {
        const t = String(sumOut.text || "").trim();
        props.checksum = t === "" ? "unreadable" : t;
      }
    }
  }
}

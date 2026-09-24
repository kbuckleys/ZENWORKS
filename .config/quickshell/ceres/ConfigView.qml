// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// SETTINGS — pacman.conf, every setting pacman 7.1 has, in one place.
//
// Maintenance's shape: the groups on the left, the chosen one's settings on
// the right, each with pacman.conf(5)'s own explanation and what pacman does
// when the line is absent. Edits collect here, against a copy of the file,
// until "Review & save": then the window's sheet shows diff's own account of
// them and pacman-conf's verdict on the result, and only then is anything
// written — as root, the old file kept as pacman.conf.ceres-bak.
//
// The editing itself is pacconf.js, which changes the lines that hold a
// setting and nothing else. See it for why the file stays yours.

import QtQuick
import Quickshell
import Quickshell.Io
import "../morpheus"
import "."
import "pacconf.js" as Pac
import "ceres.js" as Cer

Item {
  id: view

  // Handed the keys back when a field lets go of them.
  signal released()
  // "Review & save" was asked for: the window opens its sheet over this.
  signal reviewAsked()

  property var orig: []
  property var cur: []
  property bool loaded: false
  property int gsel: 0
  readonly property var group: Pac.GROUPS[view.gsel]
  readonly property int changes: view.loaded ? Pac.changedCount(view.orig, view.cur) : 0

  // ── the file ────────────────────────────────────────────────────────────
  function load() {
    readProc.running = false;
    readProc.running = true;
  }
  Process {
    id: readProc
    command: ["cat", "/etc/pacman.conf"]
    stdout: StdioCollector {
      id: readOut
      onStreamFinished: {
        const ls = Pac.lines(readOut.text);
        view.orig = ls;
        view.cur = ls;
        view.loaded = ls.length > 0;
      }
    }
  }
  function discard() { view.cur = view.orig; }

  // ── the review ──────────────────────────────────────────────────────────
  // The draft is written as you, then diffed and parsed — see the window's
  // sheet for what is shown of it.
  readonly property string draft: Paths.cacheDir() + "/ceres/pacman.conf.new"
  property var review: null
  property bool reviewing: false
  function askReview() {
    if (view.changes === 0 || view.reviewing) return;
    view.review = null;
    view.reviewing = true;
    draftProc.command = ["sh", "-c", "mkdir -p " + Cer.q(Paths.cacheDir() + "/ceres")
      + " && printf '%s' " + Cer.q(Pac.text(view.cur)) + " > " + Cer.q(view.draft)
      + " && " + Pac.reviewCommand(view.draft)];
    draftProc.running = true;
    view.reviewAsked();
  }
  Process {
    id: draftProc
    stdout: StdioCollector {
      id: draftOut
      onStreamFinished: { view.review = Pac.readReviewOut(draftOut.text); view.reviewing = false; }
    }
  }
  // Put in place as root, through the one password path. Not while pacman
  // is running: a transaction mid-way reads this file.
  property bool saving: false
  function save() {
    if (!view.review || !view.review.ok) return;
    view.saving = true;
    Ceres.request([["@sudo", "sh", "-c",
      "if [ -e /var/lib/pacman/db.lck ]; then echo 'error: pacman is running — try again when it has finished'; exit 1; fi; "
      + "cp -p /etc/pacman.conf /etc/pacman.conf.ceres-bak && install -m 644 " + Cer.q(view.draft) + " /etc/pacman.conf"]],
      "save pacman.conf · " + view.changes + (view.changes === 1 ? " line" : " lines"), 0);
  }
  // The window calls this when a job ends: a save that went through is the
  // file now, and one that did not leaves the edits where they were.
  function jobDone(ok) {
    if (!view.saving) return;
    view.saving = false;
    if (ok) view.load();
  }

  // ── edits ───────────────────────────────────────────────────────────────
  function opt(key) { return Pac.getOption(view.cur, key); }
  function optWas(key) { return Pac.getOption(view.orig, key); }
  function setOpt(key, value) { view.cur = Pac.setOption(view.cur, key, value); }
  function changedOpt(key) {
    const a = view.opt(key), b = view.optWas(key);
    return a.set !== b.set || String(a.value) !== String(b.value);
  }
  readonly property var reposNow: view.loaded ? Pac.repos(view.cur) : []
  function repoWas(name) { return Pac.repoNamed(view.orig, name); }
  // `at` is the card's own position: a Repeater hands each card a COPY of
  // its repository, so indexOf on the list never finds it — and every card
  // read as moved.
  function repoDirty(r, at) {
    const w = view.repoWas(r.name);
    if (!w) return true;
    const keyOf = x => [x.enabled, x.Include.join(" "), x.Server.join(" "), x.CacheServer.join(" "), x.SigLevel, x.Usage].join("|");
    return keyOf(w) !== keyOf(r) || Pac.repos(view.orig).findIndex(x => x.name === r.name) !== at;
  }
  function groupDirty(id) {
    if (!view.loaded) return false;
    if (id === "repos") return JSON.stringify(Pac.repos(view.orig).map(r => [r.name, r.enabled, r.Include, r.Server, r.CacheServer, r.SigLevel, r.Usage]))
      !== JSON.stringify(view.reposNow.map(r => [r.name, r.enabled, r.Include, r.Server, r.CacheServer, r.SigLevel, r.Usage]));
    return Pac.SCHEMA.some(s => s.group === id && view.changedOpt(s.key));
  }
  function groupSummary(id) {
    if (!view.loaded) return "…";
    if (id === "repos") {
      const on = view.reposNow.filter(r => r.enabled).length;
      return on + " on" + (view.reposNow.length > on ? " · " + (view.reposNow.length - on) + " off" : "");
    }
    const all = Pac.SCHEMA.filter(s => s.group === id);
    const set = all.filter(s => view.opt(s.key).set).length;
    return set === 0 ? "all at defaults" : set + " of " + all.length + " set";
  }

  // Narrow: labels go on their own line above what they label, which then has
  // the whole width — a fixed label column left the controls too little and
  // they wrapped mid-choice.
  readonly property bool narrow: rows.width < 560

  // Which repository cards are open, BY NAME: every edit rebuilds the list of
  // cards, and a card holding this itself was closed again by the very edit
  // it was opened for.
  property var openRepos: ({})
  function toggleRepo(name) {
    const o = Object.assign({}, view.openRepos);
    if (o[name]) delete o[name]; else o[name] = true;
    view.openRepos = o;
  }

  // The SigLevel everything starts from: [options]' own, or pacman's.
  readonly property var sigBase: Pac.parseSig(view.opt("SigLevel").value)

  // ── keys ────────────────────────────────────────────────────────────────
  function key(event) {
    const k = event.key, ctrl = event.modifiers & Qt.ControlModifier;
    if (ctrl && k === Qt.Key_S) { view.askReview(); return true; }
    if (k === Qt.Key_J || k === Qt.Key_Down) { view.gsel = Math.min(Pac.GROUPS.length - 1, view.gsel + 1); return true; }
    if (k === Qt.Key_K || k === Qt.Key_Up) { view.gsel = Math.max(0, view.gsel - 1); return true; }
    if (k === Qt.Key_R && view.changes === 0) { view.load(); return true; }
    return false;
  }
  readonly property var hints: [["j k", "choose"]]
    .concat(view.changes > 0 ? [["ctrl s", "review & save"]] : [["r", "reload"]])

  // ── the left: groups ────────────────────────────────────────────────────
  // AS WIDE AS IT NEEDS: the widest title or summary, the dot's gutter and
  // the row's padding — not a share of the window, which left most of the
  // column empty and squeezed the settings it sits beside.
  FontMetrics { id: fmTitle; font.family: Zenon.face; font.weight: Font.Bold; font.pixelSize: 17 }
  FontMetrics { id: fmSum; font.family: Zenon.face; font.pixelSize: 15 }
  readonly property real sideW: {
    let w = 0;
    for (const g of Pac.GROUPS)
      w = Math.max(w, fmTitle.advanceWidth(g.title), fmSum.advanceWidth(view.groupSummary(g.id)));
    return Math.max(180, Math.ceil(w) + 26 + 16);
  }
  Column {
    id: groupList
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.margins: 8
    width: view.sideW
    spacing: 4
    Repeater {
      model: Pac.GROUPS
      delegate: Rectangle {
        id: grow
        required property var modelData
        required property int index
        width: groupList.width
        height: 56
        radius: Zenon.windowRadius
        color: grow.index === view.gsel ? Zenon.headBg : "transparent"
        border.width: grow.index === view.gsel ? 1 : 0
        border.color: Zenon.border
        Rectangle {
          visible: view.groupDirty(grow.modelData.id)
          anchors.left: parent.left
          anchors.leftMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          width: 6; height: 6; radius: 3
          color: Zenon.yellow
        }
        Column {
          anchors.left: parent.left
          anchors.leftMargin: 26
          anchors.right: parent.right
          anchors.rightMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          spacing: 2
          Text {
            text: grow.modelData.title
            color: Zenon.white
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: 17
          }
          Text {
            width: parent.width
            elide: Text.ElideRight
            text: view.groupSummary(grow.modelData.id)
            color: Zenon.muted
            font.family: Zenon.face
            font.pixelSize: 15
          }
        }
        TapHandler { onTapped: { view.gsel = grow.index; view.released(); } }
      }
    }
  }

  Rectangle {
    id: div
    x: view.sideW + 16
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: 1
    color: Zenon.border
  }

  // ── the right: the chosen group's settings ──────────────────────────────
  Item {
    id: detail
    anchors.left: div.right
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.margins: 16

    // Pending edits, level with the title: how many, and the two ways out.
    Row {
      id: pending
      visible: view.changes > 0
      anchors.right: parent.right
      anchors.verticalCenter: gTitle.verticalCenter
      spacing: 8
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: view.changes + (view.changes === 1 ? " line changed" : " lines changed")
        color: Zenon.yellow
        font.family: Zenon.face
        font.pixelSize: 15
      }
      DialogButton {
        label: "Discard"
        ink: Zenon.muted
        onClicked: { view.discard(); view.released(); }
      }
      DialogButton {
        label: "Review & save"
        ink: Zenon.cyan
        primary: true
        onClicked: view.askReview()
      }
    }
    Text {
      id: gTitle
      text: view.group.title
      color: Zenon.white
      font.family: Zenon.face
      font.weight: Font.Bold
      font.pixelSize: 22
    }
    Text {
      id: gBlurb
      anchors.top: gTitle.bottom
      anchors.topMargin: 6
      width: parent.width
      wrapMode: Text.Wrap
      text: view.group.blurb
      color: Zenon.keyInk
      font.family: Zenon.face
      font.pixelSize: 16
    }

    Flickable {
      id: flick
      anchors.top: gBlurb.bottom
      anchors.topMargin: 14
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      contentHeight: rows.implicitHeight + 16
      // the shell's one scroll: the smooth notch and the rubber band
      ElasticScroll { view: flick }
      ScrollRail {
        target: flick
        parent: flick
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
      }
      // the list scrolls back to the top when the group changes
      Connections { target: view; function onGselChanged() { flick.contentY = 0; } }

      Column {
        id: rows
        width: flick.width - 14
        spacing: 6

        Repeater {
          model: view.group.id === "repos" ? [] : Pac.SCHEMA.filter(s => s.group === view.group.id)
          delegate: OptionRow { required property var modelData; spec: modelData; width: rows.width }
        }
        Repeater {
          model: view.group.id === "repos" ? view.reposNow : []
          delegate: RepoCard { required property var modelData; required property int index; repo: modelData; at: index; width: rows.width }
        }
        AddRepo { visible: view.group.id === "repos"; width: rows.width }
      }
    }
  }

  // ── controls ────────────────────────────────────────────────────────────
  // The Installed checkbox's look: a box with a tick, cyan when on.
  component Check: Row {
    id: ck
    property bool lit: false
    property string label: ""
    property bool enabled2: true
    signal toggled()
    spacing: 8
    opacity: ck.enabled2 ? 1 : 0.4
    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: 18
      height: 18
      radius: Zenon.windowRadius - 1
      color: ck.lit ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.2) : "transparent"
      border.width: 1
      border.color: ck.lit ? Zenon.cyan : Zenon.keyInk
      Text {
        anchors.centerIn: parent
        visible: ck.lit
        text: ""
        color: Zenon.cyan
        font.family: Zenon.face
        font.pixelSize: 11
      }
    }
    Text {
      visible: ck.label !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: ck.label
      color: ck.lit ? Zenon.white : Zenon.keyInk
      font.family: Zenon.face
      font.pixelSize: 15
    }
    TapHandler { enabled: ck.enabled2; onTapped: ck.toggled() }
  }

  // One of a few, the tab pill's lit look for the chosen one.
  component Chip: Rectangle {
    id: chip
    property string label: ""
    property bool lit: false
    property bool dim: false
    signal picked()
    width: chipText.implicitWidth + 20
    height: 28
    radius: Zenon.windowRadius
    color: chip.lit ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.2) : "transparent"
    border.width: 1
    border.color: chip.lit ? (chip.dim ? Zenon.border : Zenon.cyan) : Zenon.border
    Text {
      id: chipText
      anchors.centerIn: parent
      text: chip.label
      color: chip.lit ? (chip.dim ? Zenon.keyInk : Zenon.cyan) : Zenon.muted
      font.family: Zenon.face
      font.pixelSize: 15
    }
    TapHandler { onTapped: chip.picked() }
  }

  // ONE CHOICE, drawn as one bar: the options joined, the chosen one filled.
  // Separate chips for two different choices read as one list of five, and
  // wrapping could split a choice across two lines; a bar wraps whole.
  // `options` is [[value, label], …]; `dim` is the inherited look.
  component Segmented: Rectangle {
    id: seg
    property var options: []
    property string value: ""
    property bool dim: false
    signal picked(string value)
    width: segRow.implicitWidth + 4
    height: 32
    radius: Zenon.windowRadius
    color: "transparent"
    border.width: 1
    border.color: Zenon.border
    Row {
      id: segRow
      anchors.centerIn: parent
      Repeater {
        model: seg.options
        delegate: Item {
          id: part
          required property var modelData
          required property int index
          readonly property bool lit: seg.value === part.modelData[0]
          width: partText.implicitWidth + 18
          height: 28
          // between two unchosen options only: the fill is its own edge
          Rectangle {
            visible: part.index > 0 && !part.lit
              && seg.value !== seg.options[part.index - 1][0]
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: 16
            color: Zenon.border
          }
          Rectangle {
            anchors.fill: parent
            visible: part.lit
            radius: Zenon.windowRadius - 1
            color: seg.dim ? Zenon.headBg
              : Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.2)
            border.width: seg.dim ? 0 : 1
            border.color: Zenon.cyan
          }
          Text {
            id: partText
            anchors.centerIn: parent
            text: part.modelData[1]
            color: part.lit ? (seg.dim ? Zenon.keyInk : Zenon.cyan) : Zenon.muted
            font.family: Zenon.face
            font.pixelSize: 15
          }
          TapHandler { onTapped: seg.picked(part.modelData[0]) }
        }
      }
    }
  }

  // A line of text, committed on return or when it lets go; Esc puts it back.
  // Empty means unset — the placeholder says what that is.
  component Field: Rectangle {
    id: fld
    property string value: ""
    property string placeholder: ""
    signal committed(string text)
    width: 380
    height: 32
    radius: Zenon.windowRadius
    color: input.activeFocus ? Zenon.headBg : "transparent"
    border.width: 1
    border.color: input.activeFocus ? Zenon.cyan : Zenon.border
    TextInput {
      id: input
      anchors.fill: parent
      anchors.leftMargin: 10
      anchors.rightMargin: 10
      verticalAlignment: TextInput.AlignVCenter
      clip: true
      text: fld.value
      color: Zenon.white
      selectionColor: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.35)
      font.family: Zenon.face
      font.pixelSize: 15
      property bool reverting: false
      onAccepted: focus = false
      onActiveFocusChanged: {
        if (activeFocus) return;
        if (reverting) { reverting = false; text = fld.value; view.released(); return; }
        if (text.trim() !== fld.value) fld.committed(text.trim().replace(/\s+/g, " "));
        view.released();
      }
      Keys.onEscapePressed: { reverting = true; focus = false; }
    }
    // held in step with the file when it is not being typed in
    onValueChanged: if (!input.activeFocus) input.text = fld.value
    Text {
      anchors.fill: input
      anchors.leftMargin: 10
      anchors.rightMargin: 10
      verticalAlignment: Text.AlignVCenter
      visible: input.text === "" && !input.activeFocus
      elide: Text.ElideRight
      text: fld.placeholder
      color: Zenon.muted
      font.family: Zenon.face
      font.pixelSize: 15
      font.italic: true
    }
  }

  // Packages and databases, each: when to check, and whom to trust. Unset,
  // the inherited level is shown dimmed; choosing anything sets it.
  component SigEditor: Column {
    id: se
    // how wide it may be; past that, the trust chips wrap under
    property real avail: 600
    property string value: ""       // the line's own words, "" when unset
    property var base: null         // what an unset one inherits
    signal edited(string value)
    readonly property var sig: Pac.parseSig(se.value, se.base)
    readonly property bool inherited: se.value === ""
    spacing: 10
    Repeater {
      model: [["pkg", "Packages"], ["db", "Databases"]]
      // The label beside its bars while they fit, above them when not; and
      // the bars in a Flow of their own, so the second one wraps under the
      // first rather than back under the label.
      delegate: Flow {
        id: sr
        required property var modelData
        readonly property bool inline: se.avail >= 350
        width: se.avail
        spacing: 8
        Text {
          width: sr.inline ? 88 : se.avail
          height: sr.inline ? 32 : 22
          verticalAlignment: Text.AlignVCenter
          text: sr.modelData[1]
          color: Zenon.keyInk
          font.family: Zenon.face
          font.pixelSize: 15
        }
        Flow {
          width: sr.inline ? se.avail - 96 : se.avail
          spacing: 8
          Segmented {
            options: [["Never", "Never"], ["Optional", "Optional"], ["Required", "Required"]]
            value: se.sig[sr.modelData[0]].check
            dim: se.inherited
            onPicked: (v) => {
              const s = JSON.parse(JSON.stringify(se.sig));
              s[sr.modelData[0]].check = v;
              se.edited(Pac.formatSig(s));
            }
          }
          Segmented {
            options: [["TrustedOnly", "Trusted only"], ["TrustAll", "Trust all"]]
            value: se.sig[sr.modelData[0]].trust
            dim: se.inherited
            onPicked: (v) => {
              const s = JSON.parse(JSON.stringify(se.sig));
              s[sr.modelData[0]].trust = v;
              se.edited(Pac.formatSig(s));
            }
          }
        }
      }
    }
  }

  // ── one setting ─────────────────────────────────────────────────────────
  component OptionRow: Rectangle {
    id: orow
    property var spec: null
    readonly property var now: view.opt(orow.spec.key)
    readonly property bool changed: view.changedOpt(orow.spec.key)
    height: ocol.implicitHeight + 20
    radius: Zenon.windowRadius
    color: "transparent"
    border.width: 1
    border.color: orow.changed ? Qt.rgba(Zenon.yellow.r, Zenon.yellow.g, Zenon.yellow.b, 0.5) : Zenon.border

    Column {
      id: ocol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 10
      anchors.leftMargin: 14
      anchors.rightMargin: 14
      spacing: 6

      Item {
        width: parent.width
        height: Math.max(olabel.implicitHeight, octl.height)
        Text {
          id: olabel
          anchors.left: parent.left
          anchors.right: octl.left
          anchors.rightMargin: 12
          elide: Text.ElideRight
          anchors.verticalCenter: parent.verticalCenter
          text: orow.spec.label + "  <font color='" + Zenon.muted + "'>" + orow.spec.key + "</font>"
          textFormat: Text.StyledText
          color: Zenon.white
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: 17
        }
        // A Row, so only the visible control counts toward its width: an
        // Item sized by childrenRect took the widest hidden one's, and put
        // a small control over the label.
        Row {
          id: octl
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter

          Check {
            visible: orow.spec.type === "flag"
            lit: orow.now.set
            onToggled: view.setOpt(orow.spec.key, !orow.now.set)
          }
          // − n +; below the minimum is unset
          Row {
            visible: orow.spec.type === "int"
            spacing: 6
            readonly property int n: orow.now.set ? parseInt(orow.now.value, 10) || 0 : 0
            Chip {
              label: "−"
              // 1 is pacman's own default, so below 2 is unset
              onPicked: view.setOpt(orow.spec.key, parent.n - 1 < 2 ? "" : String(parent.n - 1))
            }
            Text {
              width: 44
              anchors.verticalCenter: parent.verticalCenter
              horizontalAlignment: Text.AlignHCenter
              text: orow.now.set ? orow.now.value : "—"
              color: orow.now.set ? Zenon.white : Zenon.muted
              font.family: Zenon.face
              font.weight: Font.Bold
              font.pixelSize: 17
            }
            Chip {
              label: "+"
              onPicked: view.setOpt(orow.spec.key, String(Math.min(orow.spec.max || 99, Math.max(parent.n + 1, 2))))
            }
          }
          Row {
            visible: orow.spec.type === "clean"
            spacing: 14
            Repeater {
              model: ["KeepInstalled", "KeepCurrent"]
              delegate: Check {
                required property string modelData
                label: modelData
                // every row builds these, hidden; only CleanMethod's value is words
                readonly property var words: orow.spec.type === "clean" && orow.now.set ? String(orow.now.value).split(/\s+/) : []
                lit: words.indexOf(modelData) >= 0
                onToggled: {
                  const w = words.filter(x => x !== modelData).concat(lit ? [] : [modelData]);
                  view.setOpt(orow.spec.key, ["KeepInstalled", "KeepCurrent"].filter(x => w.indexOf(x) >= 0).join(" "));
                }
              }
            }
          }
        }
      }

      Field {
        visible: orow.spec.type === "text" || orow.spec.type === "list"
        width: parent.width
        value: orow.now.set ? String(orow.now.value) : ""
        placeholder: "unset — " + orow.spec.def
        onCommitted: (t) => view.setOpt(orow.spec.key, t)
      }

      Row {
        visible: orow.spec.type === "sig"
        spacing: 10
        SigEditor {
          avail: ocol.width
          value: orow.now.set ? orow.now.value : ""
          // LocalFileSigLevel and RemoteFileSigLevel start from SigLevel
          base: orow.spec.key === "SigLevel" ? null : view.sigBase
          onEdited: (v) => view.setOpt(orow.spec.key, v)
        }
      }

      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: orow.spec.help
        color: Zenon.keyInk
        font.family: Zenon.face
        font.pixelSize: 15
      }
      Row {
        spacing: 12
        Text {
          text: orow.now.set ? "set in the file" : "unset · pacman uses: " + orow.spec.def
          color: Zenon.muted
          font.family: Zenon.face
          font.pixelSize: 14
        }
        Text {
          visible: orow.now.set && orow.spec.type !== "flag"
          text: "unset"
          color: Zenon.cyan
          font.family: Zenon.face
          font.pixelSize: 14
          font.underline: true
          TapHandler { onTapped: view.setOpt(orow.spec.key, "") }
        }
      }
    }
  }

  // ── one repository ──────────────────────────────────────────────────────
  // Closed, a card is its header and one line of what it is set to, so the
  // order of the list — which is what this page is about — fits on screen.
  // The name opens it.
  function repoSummary(r) {
    const from = r.Include.length > 0
      ? r.Include.map((f) => f.replace(/^.*\//, "")).join(", ")
      : r.Server.length > 0
        ? r.Server.length + (r.Server.length === 1 ? " server" : " servers")
        : "no servers";
    const sig = r.SigLevel === "" ? "signatures as [options]" : "signatures " + r.SigLevel;
    const use = r.Usage === "" || /\bAll\b/.test(r.Usage) ? "all uses" : r.Usage;
    return from + "  ·  " + sig + "  ·  " + use;
  }

  // A label and what it labels: side by side, or stacked when narrow.
  component Labeled: Flow {
    id: lab
    property string label: ""
    default property alias content: slot.data
    spacing: 10
    Text {
      width: view.narrow ? lab.width : 130
      height: view.narrow ? 22 : 32
      verticalAlignment: Text.AlignVCenter
      text: lab.label
      color: Zenon.keyInk
      font.family: Zenon.face
      font.pixelSize: 15
    }
    Item {
      id: slot
      width: view.narrow ? lab.width : lab.width - 140
      height: childrenRect.height
    }
  }

  component RepoCard: Rectangle {
    id: card
    property var repo: null
    property int at: 0
    readonly property bool changed: view.repoDirty(card.repo, card.at)
    readonly property bool open: card.repo.enabled && !!view.openRepos[card.repo.name]
    height: rcol.implicitHeight + 20
    radius: Zenon.windowRadius
    color: "transparent"
    border.width: 1
    border.color: card.changed ? Qt.rgba(Zenon.yellow.r, Zenon.yellow.g, Zenon.yellow.b, 0.5) : Zenon.border

    function set(key, value) { view.cur = Pac.setRepoKey(view.cur, card.repo.name, key, value); }

    Column {
      id: rcol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 10
      anchors.leftMargin: 14
      anchors.rightMargin: 14
      spacing: 8

      Item {
        width: parent.width
        height: 32
        Check {
          id: onBox
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          lit: card.repo.enabled
          onToggled: view.cur = Pac.setRepoEnabled(view.cur, card.repo.name, !card.repo.enabled)
        }
        // the chevron, the name and its badge: the part that opens the card
        Item {
          anchors.left: onBox.right
          anchors.leftMargin: 10
          anchors.right: moves.left
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          height: parent.height
          Row {
            id: titleRow
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            spacing: 10
            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: card.repo.enabled
              text: card.open ? "" : ""
              color: Zenon.muted
              font.family: Zenon.face
              font.pixelSize: 12
            }
            Text {
              id: repoName
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, titleRow.width - 22)
              elide: Text.ElideRight
              text: (card.at + 1) + ".  [" + card.repo.name + "]"
              color: card.repo.enabled ? Zenon.white : Zenon.muted
              font.family: Zenon.face
              font.weight: Font.Bold
              font.pixelSize: 17
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              // what is left after the name: it gives way before the name does
              width: Math.max(0, Math.min(implicitWidth, titleRow.width - repoName.width - 44))
              visible: width > 30
              elide: Text.ElideRight
              text: !card.repo.official ? "third party"
                : /testing|unstable/.test(card.repo.name) ? "pre-release" : "Arch"
              color: !card.repo.official ? Zenon.magenta : /testing|unstable/.test(card.repo.name) ? Zenon.yellow : Zenon.muted
              font.family: Zenon.face
              font.pixelSize: 14
            }
          }
          TapHandler {
            enabled: card.repo.enabled
            onTapped: { view.toggleRepo(card.repo.name); view.released(); }
          }
        }
        Row {
          id: moves
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: 6
          Chip {
            label: ""
            opacity: card.at > 0 ? 1 : 0.3
            onPicked: if (card.at > 0) view.cur = Pac.moveRepo(view.cur, card.repo.name, -1)
          }
          Chip {
            label: ""
            opacity: card.at < view.reposNow.length - 1 ? 1 : 0.3
            onPicked: if (card.at < view.reposNow.length - 1) view.cur = Pac.moveRepo(view.cur, card.repo.name, 1)
          }
          Chip {
            visible: !card.repo.official
            label: "Remove"
            onPicked: view.cur = Pac.removeRepo(view.cur, card.repo.name)
          }
        }
      }

      // closed: what it is set to, in one line
      Text {
        visible: card.repo.enabled && !card.open
        width: parent.width
        leftPadding: 28
        elide: Text.ElideRight
        text: view.repoSummary(card.repo)
        color: Zenon.muted
        font.family: Zenon.face
        font.pixelSize: 14
        TapHandler { onTapped: { view.toggleRepo(card.repo.name); view.released(); } }
      }

      // A switched-off repository is only its header: its settings are
      // commented out, and switching it on brings them back as they were.
      Column {
        visible: card.open
        width: parent.width
        topPadding: 4
        spacing: 12
        Repeater {
          model: [["Include", "Servers from", "a mirrorlist file, e.g. /etc/pacman.d/mirrorlist"],
                  ["Server", "Servers", "URLs, space-separated — $repo and $arch are filled in"],
                  ["CacheServer", "Cache servers", "tried first for packages, never for databases"]]
          delegate: Labeled {
            id: kr
            required property var modelData
            width: rcol.width
            label: kr.modelData[1]
            Field {
              width: parent.width
              value: card.repo[kr.modelData[0]].join(" ")
              placeholder: kr.modelData[2]
              onCommitted: (t) => card.set(kr.modelData[0], t)
            }
          }
        }
        Labeled {
          width: rcol.width
          label: "Signatures"
          Column {
            width: parent.width
            spacing: 8
            SigEditor {
              avail: parent.width
              value: card.repo.SigLevel
              base: view.sigBase
              onEdited: (v) => card.set("SigLevel", v)
            }
            // where these come from, and the way back to it
            Row {
              spacing: 8
              Text {
                text: card.repo.SigLevel === "" ? "inherited from [options]" : "this repository's own"
                color: Zenon.muted
                font.family: Zenon.face
                font.pixelSize: 14
              }
              Text {
                visible: card.repo.SigLevel !== ""
                text: "use [options]"
                color: Zenon.cyan
                font.family: Zenon.face
                font.pixelSize: 14
                font.underline: true
                TapHandler { onTapped: card.set("SigLevel", "") }
              }
            }
          }
        }
        Labeled {
          width: rcol.width
          label: "Used for"
          Flow {
            width: parent.width
            spacing: 16
            Repeater {
              // All, or unset, is every one; switching one off writes the rest
              model: Pac.USAGE
              delegate: Check {
                required property string modelData
                readonly property var words: card.repo.Usage === "" || /\bAll\b/.test(card.repo.Usage)
                  ? Pac.USAGE : card.repo.Usage.split(/\s+/)
                height: 32
                label: modelData
                lit: words.indexOf(modelData) >= 0
                onToggled: {
                  const w = Pac.USAGE.filter(u => u === modelData ? !lit : words.indexOf(u) >= 0);
                  card.set("Usage", w.length === Pac.USAGE.length ? "" : w.length === 0 ? "Sync" : w.join(" "));
                }
              }
            }
          }
        }
      }
    }
  }

  // ── a new repository ────────────────────────────────────────────────────
  component AddRepo: Rectangle {
    id: add
    property bool open: false
    property string name: ""
    property string servers: ""
    readonly property string problem: add.name === "" ? "" : Pac.validRepoName(add.name, view.cur)
    height: acol.implicitHeight + 20
    radius: Zenon.windowRadius
    color: "transparent"
    border.width: add.open ? 1 : 0
    border.color: Zenon.border
    Column {
      id: acol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 10
      anchors.leftMargin: 14
      anchors.rightMargin: 14
      spacing: 10
      DialogButton {
        visible: !add.open
        label: "Add a repository"
        ink: Zenon.cyan
        onClicked: add.open = true
      }
      Text {
        visible: add.open
        text: "New repository"
        color: Zenon.white
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: 17
      }
      Text {
        visible: add.open
        width: parent.width
        wrapMode: Text.Wrap
        text: "Added last, so Arch's own repositories win where both have a package of the same name. "
          + "Most third-party repositories also need their signing key imported with pacman-key first."
        color: Zenon.keyInk
        font.family: Zenon.face
        font.pixelSize: 15
      }
      Labeled {
        visible: add.open
        width: acol.width
        label: "Name"
        Field { width: parent.width; value: add.name; placeholder: "as the repository calls itself"; onCommitted: (t) => add.name = t }
      }
      Labeled {
        visible: add.open
        width: acol.width
        label: "Servers"
        Field { width: parent.width; value: add.servers; placeholder: "https://…/$repo/os/$arch"; onCommitted: (t) => add.servers = t }
      }
      Text {
        visible: add.open && add.problem !== ""
        text: add.problem
        color: Zenon.red
        font.family: Zenon.face
        font.pixelSize: 15
      }
      Row {
        visible: add.open
        spacing: 8
        DialogButton {
          label: "Cancel"
          ink: Zenon.muted
          onClicked: { add.open = false; add.name = ""; add.servers = ""; }
        }
        DialogButton {
          label: "Add"
          ink: Zenon.cyan
          primary: true
          ready: add.name !== "" && add.problem === "" && add.servers.trim() !== ""
          onClicked: {
            view.cur = Pac.addRepo(view.cur, add.name, add.servers, "");
            add.open = false; add.name = ""; add.servers = "";
          }
        }
      }
    }
  }
}

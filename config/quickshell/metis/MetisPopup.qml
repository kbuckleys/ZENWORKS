// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import "../morpheus"
import "metis.js" as Metis
import "../morpheus/helpers.js" as Helpers

LayerPopup {
  id: popup

  readonly property color bgColor: Zenon.layerBg
  readonly property color headColor: Zenon.blue
  readonly property color dimColor: Zenon.muted

  property string query: ""
  property int seq: 0

  // what's currently displayed
  property string shownExpr: ""
  property string shownResult: ""
  // and the same answer as qalc wrote it — what `ans` stands for later
  property string shownRaw: ""
  // qalc's own reading of the question ("5 kilometers → miles"), so a
  // misread is visible instead of trusted
  property string shownParse: ""
  property bool fromHistory: false
  // a question that could not be read, and the word it stopped at ("" when
  // there is no one word to blame)
  property bool shownBad: false
  property string badWord: ""
  // what the answer is a measure of ("length", "tz", "date" …) — the glyph
  // in the field — and the drawing under it, if it has one
  property string shownKind: "calc"
  property var shownStrip: []        // a time zone's day: [{label, min}]
  property var shownProgress: null   // a wait's share gone: {from, to, frac}
  // the answer on screen belongs to an older question and a newer one is
  // being worked out — it is dimmed rather than trusted or blanked
  property bool stale: false
  // ctrl+return landed; said for a moment before the panel goes
  property bool copied: false
  // what the answer on screen was asked as, for deciding whether its
  // reading is worth a line (Metis.parseWorth)
  property var shownPrep: null
  // the wash behind the answer — a Zenon colour name, or ""
  property string shownTint: ""
  readonly property color tintColor: popup.shownTint !== "" && popup.resultShown && !popup.shownBad
    ? Zenon[popup.shownTint] : "transparent"
  readonly property bool parseShown: popup.shownBad ? false
    : popup.fromHistory ? popup.shownParse !== ""
    : Metis.parseWorth(popup.shownPrep, popup.shownParse, popup.shownExpr)
  readonly property int resultH: popup.parseShown || popup.shownBad ? 66 : 50

  // the answer "* 2" goes on from, as it was shown
  readonly property string ansShown: {
    for (const h of popup.history) if (h.raw) return h.result;
    return "";
  }
  readonly property bool continuing: popup.histIdx < 0 && Metis.continues(popup.query, popup.ans)
  // the rest of the word being typed, offered faintly; → takes it
  readonly property string completion:
    filterInput.activeFocus && filterInput.cursorPosition === filterInput.text.length
      && popup.histIdx < 0 ? Metis.complete(filterInput.text, popup.qalcNames) : ""

  readonly property var parseInk: ({
    muted: String(Zenon.muted), arrow: String(Zenon.blue), target: String(Zenon.white),
    warn: String(Zenon.yellow)
  })

  // the colours the field's text is tinted in — see Metis.highlight, which
  // also says what counts as a number, a word and an operator
  readonly property var inkSet: ({
    num: String(Zenon.blue), word: String(Zenon.white), joiner: String(Zenon.muted),
    op: String(Zenon.keyInk), bad: String(Zenon.red)
  })

  // the same answer in the other units it is usually wanted in; Tab walks
  // them and Return takes the one selected. Under a question that could not
  // be read they are the names it might have meant ("fix"), and Return puts
  // the one selected in the field instead.
  property var chips: []
  property int chipIdx: -1
  property string chipMode: "units"   // "units" | "fix"
  // With the field empty the chip row holds the last few kept answers, so
  // an open panel is a reminder rather than a blank.
  readonly property bool recentMode: !popup.resultShown && popup.history.length > 0
  // as many as are worth scrolling through, now that the row scrolls
  readonly property var recents: popup.recentMode ? popup.history.slice(0, 12) : []
  // nothing kept yet at all: a few questions to try, which also teach what
  // it understands
  readonly property bool exampleMode: !popup.resultShown && popup.histLoaded
    && popup.history.length === 0
  readonly property var examples: popup.exampleMode ? Metis.EXAMPLES : []
  readonly property int chipCount: popup.recentMode ? popup.recents.length
    : popup.exampleMode ? popup.examples.length : popup.chips.length
  // What Return takes, and what the big answer shows: a selected chip is
  // previewed there, so what is large is exactly what you get.
  readonly property string pickText: {
    if (popup.recentMode)
      return popup.chipIdx >= 0 && popup.chipIdx < popup.recents.length
        ? popup.recents[popup.chipIdx].result : "";
    if (popup.exampleMode) return "";
    return popup.chipMode === "units" && popup.chipIdx >= 0 && popup.chipIdx < popup.chips.length
      ? popup.chips[popup.chipIdx] : popup.shownResult;
  }

  // kept answers {expr, result, raw, parse}, newest first — read from disk on
  // the first open, written back when one is added. An answer is kept when it
  // is taken (Return), or left on screen when the field is cleared or the
  // panel closed: not every half-typed step on the way to it.
  property var history: []
  property bool histLoaded: false
  property int histIdx: -1            // -1 = live input
  readonly property string ans: Metis.lastAnswer(popup.history)

  // every name qalc answers to, for "did you mean"; read once from its data
  // files (a few hundred ms, in the background, on the first open)
  property var qalcNames: []
  property var qalcPrefixes: []
  // the place index's names are in (Metis.setIndex) — read once a session,
  // about a quarter of a second for its hundred thousand lines
  property bool placesLoaded: false
  // how old the exchange rates on disk are, in seconds (NaN: not known yet)
  property real ratesAge: NaN

  // ── AS WIDE AS WHAT IT IS SHOWING ─────────────────────────────────
  // It was a fixed 600 while every other layer fits itself. Now: the
  // widest of what you typed, the result under it and the hint strip, and
  // never past the 1000 every layer shares. Measured with FontMetrics
  // calls, so nothing here reads the panel it is sizing — no loop.
  FontMetrics { id: inFm; font.family: Zenon.face; font.weight: Font.Bold; font.pixelSize: 20 }
  FontMetrics { id: exprFm; font.family: Zenon.face; font.weight: Font.Bold; font.pixelSize: 14 }
  readonly property var hintRows: {
    if (popup.histIdx >= 0)
      return [["return", "paste"], ["ctrl return", "copy"], ["tab", "edit"], ["↑↓", "history"]];
    if (popup.recentMode)
      return popup.chipIdx >= 0
        ? [["return", "open"], ["ctrl return", "copy"], ["tab", "recent"], ["esc", "close"]]
        : [["tab", "recent"], ["↑↓", "history"], ["esc", "close"]];
    if (popup.exampleMode)
      return [["tab", "examples"], ["return", "try it"], ["esc", "close"]];
    if (popup.completion !== "")
      return (popup.chips.length > 0 ? [["→", "finish word"], ["return", "paste"], ["tab", "units"]]
        : [["→", "finish word"], ["return", "paste"]]).concat([["esc", "clear · close"]]);
    if (popup.shownBad)
      return popup.chips.length > 0
        ? [["tab", "did you mean"], ["return", "use it"], ["esc", "clear · close"]]
        : [["esc", "clear · close"], ["↑↓", "history"]];
    return (popup.chips.length > 0
        ? [["return", "paste"], ["ctrl return", "copy"], ["tab", "units"]]
        : [["return", "paste"], ["ctrl return", "copy"]])
      .concat([["esc", "clear · close"], ["↑↓", "history"]]);
  }
  // measured off the row as drawn — see calypso's minW for why
  HintRow { id: hintMeasure; opacity: 0; rows: popup.hintRows }
  AnswerText { id: answerMeasure; opacity: 0; value: Metis.group(popup.pickText) }
  readonly property int minW: Math.max(360, Math.ceil(hintMeasure.implicitWidth + 48))
  readonly property int panelWidth: {
    const want = Math.max(
      inFm.advanceWidth(popup.query) + 120,
      popup.parseShown ? exprFm.advanceWidth(popup.parseLine) + 60 : 0,
      answerMeasure.implicitWidth + 60,
      // The chips as drawn (ChipStrip.contentW is its row's own width, which
      // never reads the panel). They widen it only so far; past that the row
      // scrolls.
      popup.chipRowH > 0 ? Math.min(680, chipStrip.contentW + 48) : 0,
      // a day strip needs room for two labels at its ends
      popup.shownStrip.length > 0 || popup.shownProgress ? 440 : 0);
    return Math.max(popup.minW, Math.min(1000, Math.ceil(want)));
  }
  readonly property int panelTarget: Zenon.layerWidth(popup.panelWidth)
  // Following the pill while morphed and easing on its own otherwise — the
  // same two-line rule artemis, folio and cynosure keep.
  property real liveWidth: (popup.morphMode && popup.statusbar
      && popup.statusbar.pillWidth > 0)
    ? popup.statusbar.pillWidth : popup.panelTarget
  Behavior on liveWidth {
    enabled: !popup.morphMode
    NumberAnimation { duration: Zenon.slow; easing.type: Zenon.ease }
  }

  component HintBar: Item {
    id: hintBarRoot
    height: 20
    property var rows: popup.hintRows
    // Keys as caps, like every other panel's — it was the one strip that
    // wrote them as bold text. See morpheus/HintRow.
    HintRow {
      anchors.centerIn: parent
      rows: hintBarRoot.rows
    }
  }

  focusable: true

  HyprlandFocusGrab {
    id: grab
    windows: [ popup ]
    active: popup.shown
    onCleared: popup.closePopup()
  }

  IpcHandler {
    target: "Metis"

    function toggle() { popup.toggle(); }
  }

  // ------------------------------------------------------------- procs --

  Process {
    id: calcProc
    property int runSeq: 0
    // the expression this run was started with — the result is shown under
    // THAT, never under whatever the field says by the time it lands
    property string runExpr: ""
    // and what metis.js made of it
    property var runPrep: ({})
    // A question asked while this was out is asked when it ends — and only
    // then: re-asking on every exit redid an answer already on screen (a
    // date, worked out with no process at all), and that rebuilt its chips
    // under a Tab selection.
    property bool pending: false
    onExited: if (calcProc.pending) {
      calcProc.pending = false;
      Qt.callLater(popup.evaluate);
    }

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (calcProc.runSeq !== popup.seq) return;
        const prep = calcProc.runPrep;
        const r = prep.kind === "tz" ? Metis.readTz(text, prep)
          : prep.kind === "geo" ? Metis.readGeo(text, prep)
          : Metis.readCalc(text, prep);
        if (r.bad) {
          popup.showBad(calcProc.runExpr,
            Metis.badWord(r, prep, popup.qalcNames, popup.qalcPrefixes));
          return;
        }
        if (!r.result) return;
        // A word qalc took without complaint but has no name for: "5 mtrs"
        // is five milliturn·seconds to it. Said so, with what it might be.
        if (prep.kind === "qalc" && popup.qalcNames.length > 0) {
          const w = Metis.culprit(prep.expr, popup.qalcNames, popup.qalcPrefixes);
          if (w !== "") {
            popup.showBad(calcProc.runExpr, w);
            return;
          }
        }
        let parse = r.parse || "";
        if (r.category === "currency") {
          const note = Metis.ratesNote(popup.ratesAge);
          if (note !== "") parse = (parse !== "" ? parse : calcProc.runExpr) + "  · " + note;
        }
        popup.showAnswer(calcProc.runExpr, r.result, prep.kind === "tz" ? "" : r.raw, parse);
        popup.shownPrep = prep;
        popup.shownKind = Metis.kindOf(prep, r);
        popup.shownTint = Metis.tintFor(popup.shownKind, r.base || "");
        popup.shownStrip = r.strip || [];
        if (prep.kind === "tz" || prep.kind === "geo") {
          // the 12-hour time, the day it lands on, the offset — read off the
          // same run, no second one
          popup.chipMode = "units";
          popup.chips = r.chips || [];
          popup.chipIdx = -1;
        } else {
          popup.askChips(r);
        }
      }
    }
  }

  // ── the chips ── a second, short qalc run, once the answer is known: what
  // it is a measure of is read off the answer, not guessed from the question
  Process {
    id: chipProc
    property int runSeq: 0
    property var plan: ({})
    property var calc: ({})
    // the chips of an answer that came while a run for an older one was out
    property var next: null
    onExited: if (chipProc.next) {
      const n = chipProc.next;
      chipProc.next = null;
      popup.startChips(n.plan, n.calc);
    }

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (chipProc.runSeq !== popup.seq) return;
        popup.chips = Metis.readChips(text, chipProc.plan, chipProc.calc);
      }
    }
  }

  function askChips(calc) {
    popup.chipIdx = -1;
    popup.chipMode = "units";
    const plan = calc.base !== undefined && calc.base !== ""
      ? Metis.chipPlan(calc) : { lines: [], specs: [], local: [] };
    if (plan.lines.length === 0) {
      popup.chips = plan.local.filter((x) => x !== "").slice(0, 6);
      return;
    }
    // A run still out belongs to an older answer: its seq no longer matches
    // and what it says is dropped. It is let finish and this one queued —
    // stopping it and starting again at once was a no-op on a process still
    // on its way out, and the newer answer got no chips at all.
    if (chipProc.running) {
      chipProc.next = { plan: plan, calc: calc };
      return;
    }
    popup.startChips(plan, calc);
  }

  function startChips(plan, calc) {
    chipProc.runSeq = popup.seq;
    chipProc.plan = plan;
    chipProc.calc = calc;
    chipProc.command = ["bash", "-c", Metis.chipScript(), "metis"].concat(plan.lines);
    chipProc.running = true;
  }

  function showAnswer(expr, result, raw, parse) {
    chipProc.next = null;
    popup.stale = false;
    staleTimer.stop();
    popup.shownKind = "calc";
    popup.shownTint = "";
    popup.shownPrep = null;
    popup.shownStrip = [];
    popup.shownProgress = null;
    popup.shownExpr = expr;
    popup.shownResult = result;
    popup.shownRaw = raw;
    popup.shownParse = parse;
    popup.shownBad = false;
    popup.badWord = "";
    popup.fromHistory = false;
  }

  function showBad(expr, word) {
    chipProc.next = null;
    popup.stale = false;
    staleTimer.stop();
    popup.shownKind = "calc";
    popup.shownTint = "";
    popup.shownPrep = null;
    popup.shownStrip = [];
    popup.shownProgress = null;
    popup.shownExpr = expr;
    popup.shownResult = "";
    popup.shownRaw = "";
    popup.shownParse = "";
    popup.shownBad = true;
    popup.badWord = word;
    popup.fromHistory = false;
    popup.chipMode = "fix";
    popup.chips = Metis.suggest(word, popup.qalcNames);
    popup.chipIdx = -1;
  }

  // the reading line as plain text, for measuring the panel by
  readonly property string parseLine: (popup.fromHistory ? "↺ " : "")
    + (popup.shownParse !== "" ? popup.shownParse : popup.shownExpr) + "  ="

  // the answer on screen, kept — once it is one you took or left there
  function keepShown() {
    if (popup.fromHistory || popup.shownBad || !popup.shownExpr || !popup.shownResult) return;
    popup.history = Metis.addHistory(popup.history, {
      expr: popup.shownExpr, result: popup.shownResult,
      raw: popup.shownRaw, parse: popup.shownParse, kind: popup.shownKind
    });
    popup.writeFile(Metis.historyPath(), Metis.serializeHistory(popup.history));
  }

  // ── on disk ── ~/.cache/metis-history, through stdin, beside the file and
  // renamed over it: lexi's way, for lexi's reasons (argv limits; a crash
  // mid-write)
  property var writeQueue: []
  Process {
    id: writeProc
    onExited: popup.drainWrite()
  }
  function writeFile(path, content) {
    popup.writeQueue.push({ path: path, content: content });
    popup.drainWrite();
  }
  function drainWrite() {
    if (popup.writeQueue.length === 0 || writeProc.running) return;
    const job = popup.writeQueue.shift();
    writeProc.command = ["sh", "-c",
      "cat > \"$1.tmp.$$\" && mv -f \"$1.tmp.$$\" \"$1\" || rm -f \"$1.tmp.$$\"",
      "metis-write", job.path];
    writeProc.stdinEnabled = true;
    writeProc.running = true;
    writeProc.write(job.content);
    writeProc.stdinEnabled = false;
  }

  Process {
    id: histReadProc
    command: ["sh", "-c", "cat \"$1\" 2>/dev/null", "metis-read", Metis.historyPath()]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // anything kept before the file came back goes on top of it
        let h = Metis.parseHistory(text);
        for (let i = popup.history.length - 1; i >= 0; --i)
          h = Metis.addHistory(h, popup.history[i]);
        popup.history = h;
        popup.histLoaded = true;
      }
    }
  }

  // Every city of 15,000 people or more, every province, state and country:
  // the first open with no index builds it (scripts/metis-places.py — one
  // download, a few seconds, in the background), and after that it is only
  // read. Until it is in, the places metis.js carries itself still work.
  Process {
    id: placesProc
    command: ["bash", "-c", Metis.placesScript(), "metis-places",
      Metis.placesPath(), Helpers.script("metis-places.py")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: popup.placesLoaded = Metis.setIndex(text) > 0
    }
  }

  Process {
    id: namesProc
    command: ["bash", "-c", Metis.namesScript()]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const n = Metis.readNames(text);
        popup.qalcNames = n.names;
        popup.qalcPrefixes = n.prefixes;
      }
    }
  }

  // At most twice a day: the ECB publishes once, and fetching on every open
  // was a network round trip each time the calculator appeared. Then how old
  // what is on disk is, for the note under a currency answer.
  Process {
    id: ratesProc
    command: ["bash", "-c", Metis.ratesScript()]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const a = parseInt(text.trim(), 10);
        popup.ratesAge = isNaN(a) ? NaN : a;
      }
    }
  }

  function detach(script) {
    if (script) Quickshell.execDetached(["bash", "-c", script]);
  }

  // ------------------------------------------------------------- open --

  function openPopup() {
    popup.shown = true;
    popup.collapsing = false;
    popup.query = "";
    filterInput.text = "";
    popup.seq++;
    popup.clearShown();
    popup.histIdx = -1;
    popup.copied = false;

    focusRetry.counter = 0;
    focusRetry.restart();
    popup.playOpen();
    popup.syncFocus();

    if (!popup.histLoaded && !histReadProc.running) histReadProc.running = true;
    if (popup.qalcNames.length === 0 && !namesProc.running) namesProc.running = true;
    if (!popup.placesLoaded && !placesProc.running) placesProc.running = true;
    if (!ratesProc.running) ratesProc.running = true;
  }

  function clearShown() {
    chipProc.next = null;
    popup.stale = false;
    staleTimer.stop();
    popup.shownTint = "";
    popup.shownPrep = null;
    popup.shownKind = "calc";
    popup.shownStrip = [];
    popup.shownProgress = null;
    popup.shownExpr = "";
    popup.shownResult = "";
    popup.shownRaw = "";
    popup.shownParse = "";
    popup.shownBad = false;
    popup.fromHistory = false;
    popup.chips = [];
    popup.chipIdx = -1;
  }

  function closePopup() {
    if (!popup.collapsing) popup.keepShown();
    popup.collapsing = true;
    popup.playClose();
  }

  function toggle() {
    if (popup.shown) popup.closePopup();
    else popup.openPopup();
  }

  function syncFocus() {
    Qt.callLater(() => {
      if (!popup.shown) return;
      filterInput.forceActiveFocus();
    });
  }

  // -------------------------------------------------------- evaluate --

  Timer {
    id: debounce
    interval: 150
    onTriggered: popup.evaluate()
  }

  function evaluate() {
    const q = popup.query.trim();
    if (!q) {
      popup.seq++;
      popup.clearShown();
      return;
    }
    const s = ++popup.seq;
    // answered here and now, or not at all: nothing to ask once a run ends
    calcProc.pending = false;
    const prep = Metis.prepare(q, { ans: popup.ans });
    // an English word left over is said so at once — qalc would only have
    // read it as a unit
    if (prep.bad) {
      popup.showBad(q, prep.bad);
      return;
    }
    // dates are worked out on the spot — no process, no wait
    if (prep.kind === "local") {
      popup.showAnswer(q, prep.result, prep.raw, prep.parse);
      popup.shownPrep = prep;
      popup.shownKind = Metis.kindOf(prep, null);
      popup.shownTint = Metis.tintFor(popup.shownKind, "");
      popup.shownProgress = prep.progress || null;
      popup.chipMode = "units";
      popup.chips = prep.chips;
      popup.chipIdx = -1;
      return;
    }
    // only a qalc question can be empty; a time zone or a distance has no
    // expression at all, and this dropped distances on the floor, leaving
    // whatever the half-typed question had said on screen
    if (prep.kind === "qalc" && !prep.expr) return;
    // A slow expression (a currency, say) still out when the next keystroke
    // lands: re-arming a running Process is a no-op, but runSeq moved on, so
    // the OLD answer passed the check and was shown beside the NEW
    // expression. The run keeps its own number and text; the newest is asked
    // when it ends.
    staleTimer.restart();
    if (calcProc.running) {
      calcProc.pending = true;
      return;
    }
    calcProc.runSeq = s;
    calcProc.runExpr = q;
    calcProc.runPrep = prep;
    calcProc.command = prep.kind === "tz"
      ? ["bash", "-c", Metis.tzScript(), "metis", prep.mode, prep.time, prep.date, prep.from, prep.to]
      : prep.kind === "geo"
      ? ["bash", "-c", Metis.geoScript(), "metis",
          prep.a.coord, prep.a.place, prep.a.zone, prep.b.coord, prep.b.place, prep.b.zone]
      : ["bash", "-c", Metis.calcScript(), "metis", prep.expr, prep.alt || "", prep.target || ""];
    calcProc.running = true;
  }

  // Not at once: most answers are back in well under a tenth of a second,
  // and dimming for each of those would be a flicker on every keystroke.
  Timer {
    id: staleTimer
    interval: 90
    onTriggered: if (popup.shownResult !== "" || popup.shownBad) popup.stale = true
  }

  // ---------------------------------------------------------- history --

  function histStep(delta) {
    if (popup.history.length === 0) return;
    let idx = popup.histIdx + delta;
    if (idx < -1) idx = popup.history.length - 1;
    if (idx >= popup.history.length) idx = -1;
    popup.histIdx = idx;
    if (idx === -1) {
      // back to what is typed, worked out again
      popup.clearShown();
      popup.evaluate();
      filterInput.forceActiveFocus();
    } else {
      const h = popup.history[idx];
      popup.showAnswer(h.expr, h.result, h.raw || "", h.parse || "");
      popup.shownKind = h.kind || "calc";
      popup.shownTint = Metis.tintFor(popup.shownKind, "");
      popup.fromHistory = true;
      popup.chips = [];
      popup.chipIdx = -1;
    }
  }

  // the question of the history row on screen, back in the field to change
  function editFromHistory() {
    if (popup.histIdx < 0) return;
    popup.recall(popup.history[popup.histIdx].expr);
  }

  // a kept question back in the field, worked out again, ready to change
  function recall(expr) {
    if (!expr) return;
    popup.histIdx = -1;
    filterInput.text = expr;
    filterInput.cursorPosition = expr.length;
    filterInput.forceActiveFocus();
    debounce.stop();
    popup.evaluate();
  }

  // ---------------------------------------------------------- actions --

  // Return: the selected chip or the answer, pasted where you were — or,
  // under a question it could not read, the name it might have meant, put
  // in the field in place of the word that failed
  function takeShown(copyOnly) {
    if (popup.exampleMode) {
      if (popup.chipIdx >= 0) popup.recall(popup.examples[popup.chipIdx]);
      return;
    }
    // a kept answer: Return brings its question back, as a click does;
    // ctrl+return copies the answer
    if (popup.recentMode) {
      if (popup.chipIdx < 0) return;
      if (copyOnly) popup.copyOnly(popup.pickText);
      else popup.recall(popup.recents[popup.chipIdx].expr);
      return;
    }
    if (popup.shownBad) {
      if (popup.chipIdx >= 0) popup.applyFix(popup.chips[popup.chipIdx]);
      return;
    }
    if (copyOnly) popup.copyOnly(popup.pickText);
    else popup.copyPaste(popup.pickText);
  }

  function applyFix(name) {
    if (!name || !popup.badWord) return;
    const re = new RegExp("\\b" + popup.badWord.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "\\b");
    const t = filterInput.text;
    if (!re.test(t)) return;
    filterInput.text = t.replace(re, name);
    filterInput.forceActiveFocus();
  }

  // ctrl+return: on the clipboard and nothing typed — for when the answer is
  // going somewhere other than the window underneath
  function copyOnly(text) {
    if (!text || popup.copied) return;
    // kept by closePopup, when copiedTimer closes the panel
    popup.detach("printf '%s' " + Strings.shellQuote(text) + " | wl-copy >/dev/null 2>&1");
    // nothing is typed anywhere, so without a word it looks like nothing
    // happened: "copied" in the strip, then the panel goes
    popup.copied = true;
    copiedTimer.restart();
  }

  Timer {
    id: copiedTimer
    interval: 520
    onTriggered: popup.closePopup()
  }

  // a click on the answer: copied, said so, and the panel stays — you were
  // looking at it, not done with it
  function copyStay(text) {
    if (!text) return;
    popup.keepShown();
    popup.detach("printf '%s' " + Strings.shellQuote(text) + " | wl-copy >/dev/null 2>&1");
    popup.copied = true;
    copiedFlash.restart();
  }

  Timer {
    id: copiedFlash
    interval: 900
    onTriggered: popup.copied = false
  }

  function copyPaste(text) {
    if (!text) return;
    popup.closePopup();   // which keeps the answer
    popup.detach("sleep 0.25 && printf '%s' " + Strings.shellQuote(text) +
      " | wl-copy >/dev/null 2>&1 && sleep 0.15 && wtype " +
      Strings.shellQuote(text));
  }

  function chipStep(delta) {
    const n = popup.chipCount;
    if (n === 0) return;
    // -1 is the answer itself, so a lap ends where it started
    let i = popup.chipIdx + delta;
    if (i >= n) i = -1;
    if (i < -1) i = n - 1;
    popup.chipIdx = i;
    // Tab can pick one past the panel's edge: the strip slides it into view
    const rep = popup.recentMode ? recentRep : popup.exampleMode ? exampleRep : unitRep;
    if (i >= 0) chipStrip.reveal(rep.itemAt(i));
  }

  // ---------------------------------------------------------- panel --

  MouseArea {
    anchors.fill: parent
    z: 0
    onClicked: popup.closePopup()
  }

  Item {
    id: panel
    width: Math.round(popup.liveWidth)
    height: popup.calcHeight()
    // Zenon.slow is the pill's own height easing in shell.qml
    Behavior on height { NumberAnimation { duration: Zenon.slow; easing.type: Zenon.ease } }
    // Either edge. A layer opens out of the pill, so it has to be on the
    // same one, off whichever it is by the same lift. Placed by y, NOT by a
    // top/bottom anchor pair: flipping two anchors at runtime updates one
    // before the other, for that instant both apply and stretch the panel to
    // the screen, and that stretch overwrites — and so unbinds — `height`.
    // The panel then stayed screen-tall until the shell was restarted.
    anchors.horizontalCenter: parent.horizontalCenter
    y: Zenon.barTop ? Zenon.edgeLift(popup.morphMode, popup.screen, popup.statusbar)
      : parent.height - height - Zenon.edgeLift(popup.morphMode, popup.screen, popup.statusbar)
    z: 1
    opacity: popup.contentFade
    transform: Scale {
      origin.x: panel.width / 2
      // grows out of the edge the bar is on, which is the edge it came from
      origin.y: Zenon.barTop ? 0 : panel.height
      xScale: popup.panelX
      yScale: popup.panelY
    }

    MouseArea { anchors.fill: parent }

    LayerShadow {
      panel: bgRoot
      cornerRadius: Zenon.pillRadius
      morphed: popup.morphMode
    }

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

      Keys.onEscapePressed: (event) => {
        event.accepted = true;
        if (popup.histIdx >= 0) {
          popup.histStep(-popup.histIdx - 1);   // back to what is typed
        } else if (filterInput.text !== "") {
          popup.keepShown();
          filterInput.clear();
          popup.query = "";
        } else {
          popup.closePopup();
        }
      }

      Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          event.accepted = true;
          popup.takeShown((event.modifiers & Qt.ControlModifier) !== 0);
          return;
        }
        if ((event.key === Qt.Key_Right || event.key === Qt.Key_End) && popup.completion !== "") {
          event.accepted = true;
          filterInput.insert(filterInput.text.length, popup.completion);
          filterInput.cursorPosition = filterInput.text.length;
          return;
        }
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
          event.accepted = true;
          if (popup.histIdx >= 0) popup.editFromHistory();
          else popup.chipStep(event.key === Qt.Key_Backtab ? -1 : 1);
          return;
        }
        if (event.key === Qt.Key_Up) {
          event.accepted = true;
          popup.histStep(1);
          return;
        }
        if (event.key === Qt.Key_Down) {
          event.accepted = true;
          popup.histStep(-1);
          return;
        }
      }

      Column {
        anchors.fill: parent

        // -------------------------------------------------- input --
        Item {
          width: parent.width
          height: 46

          Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Zenon.border
          }

          Row {
            anchors.fill: parent
            leftPadding: 16
            spacing: 12

            // what the answer is a measure of — a ruler, a clock, a globe —
            // so how the question was taken shows before a word is read
            Text {
              id: kindGlyph
              width: 22
              horizontalAlignment: Text.AlignHCenter
              text: Metis.glyphFor(popup.resultShown && !popup.shownBad ? popup.shownKind : "calc")
              color: popup.shownBad ? Zenon.red : popup.headColor
              Behavior on color { ColorAnimation { duration: Zenon.normal } }
              anchors.verticalCenter: parent.verticalCenter
              font.family: Zenon.face
              font.weight: 500
              font.pixelSize: 19
              onTextChanged: glyphPop.restart()
              NumberAnimation {
                id: glyphPop
                target: kindGlyph
                property: "scale"
                from: 0.55
                to: 1
                duration: Zenon.slow
                easing.type: Easing.OutBack
              }
            }

            Item {
              width: parent.width - 66
              height: parent.height
              clip: true

              // what "* 2" goes on from, faint, in front of what is typed —
              // the field makes room for it with its left padding
              Text {
                id: ansGhost
                visible: popup.continuing
                anchors.verticalCenter: parent.verticalCenter
                text: Metis.group(popup.ansShown)
                color: Zenon.muted
                opacity: 0.8
                font: filterInput.font
              }

              // The field's own text, tinted: numbers, units, joining words
              // and operators each their own ink (Metis.highlight). Drawn
              // UNDER the field, whose glyphs are transparent, so a selection
              // it paints still covers this; moved with the field's scroll.
              Text {
                id: inkLayer
                // cursorRectangle, not cursorPosition: the field scrolls AFTER
                // the cursor moves, and only the rectangle changes with it
                x: {
                  filterInput.text; filterInput.cursorRectangle; filterInput.width;
                  return filterInput.positionToRectangle(0).x;
                }
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.StyledText
                text: Metis.highlight(filterInput.text, popup.inkSet,
                  popup.shownBad ? popup.badWord : "")
                font: filterInput.font
              }

              // and the word it could not read, underlined where it stands
              Rectangle {
                id: badLine
                readonly property var span: popup.shownBad
                  ? Metis.wordSpan(filterInput.text, popup.badWord) : null
                visible: span !== null
                x: {
                  filterInput.cursorRectangle; filterInput.width;
                  return badLine.span ? filterInput.positionToRectangle(badLine.span.start).x : 0;
                }
                width: {
                  filterInput.cursorRectangle; filterInput.width;
                  return badLine.span
                    ? filterInput.positionToRectangle(badLine.span.end).x - badLine.x : 0;
                }
                y: parent.height / 2 + 12
                height: 2
                radius: 1
                color: Zenon.red
              }

              // the rest of the word being typed, faint after the cursor
              Text {
                visible: popup.completion !== ""
                x: {
                  filterInput.text; filterInput.cursorRectangle; filterInput.width;
                  return filterInput.positionToRectangle(filterInput.text.length).x;
                }
                anchors.verticalCenter: parent.verticalCenter
                text: popup.completion
                color: Zenon.muted
                opacity: 0.7
                font: filterInput.font
              }

              TextInput {
                id: filterInput
                anchors.fill: parent
                leftPadding: popup.continuing ? ansGhost.implicitWidth + 8 : 0
                verticalAlignment: TextInput.AlignVCenter
                // transparent: inkLayer under it is the text you see
                color: "transparent"
                selectionColor: popup.headColor
                selectedTextColor: "#000000"
                font.family: Zenon.face
                font.weight: Font.Bold
                font.pixelSize: 20
                cursorVisible: activeFocus
                cursorDelegate: Item {}
                clip: true
                Keys.forwardTo: bgRoot

                Rectangle {
                  id: pulseCursor
                  // where the cursor is, not the end of the text: it was drawn
                  // at the end wherever the cursor had been moved to
                  anchors.left: parent.left
                  anchors.leftMargin: Math.min(filterInput.cursorRectangle.x + 1,
                                               filterInput.width - 5)
                  anchors.verticalCenter: parent.verticalCenter
                  width: 3
                  height: 24
                  radius: 1
                  color: popup.headColor
                  opacity: 0.25
                  visible: filterInput.activeFocus
                  SequentialAnimation on opacity {
                    running: filterInput.activeFocus
                    loops: Animation.Infinite
                    NumberAnimation { to: 1; duration: 550; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0.25; duration: 550; easing.type: Easing.InOutSine }
                  }
                }

                onTextChanged: {
                  popup.query = filterInput.text;
                  popup.histIdx = -1;
                  popup.chipIdx = -1;
                  debounce.restart();
                }
              }

            }
          }
        }

        // ------------------------------------------------- result --
        Item {
          width: parent.width
          height: popup.resultShown ? popup.resultH : 0
          Behavior on height { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
          clip: true

          // A wash of colour behind the answer, felt more than seen: warm or
          // cool for a temperature by its value, green for money, violet for
          // time, blue for distance (Metis.tintFor).
          Rectangle {
            anchors.fill: parent
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0.0; color: "transparent" }
              GradientStop { position: 0.5; color: Qt.rgba(popup.tintColor.r, popup.tintColor.g, popup.tintColor.b, popup.tintColor.a * 0.11) }
              GradientStop { position: 1.0; color: "transparent" }
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: 3

            // How qalc read it, not the text echoed back — "5 kilometers →
            // miles" says the in was understood; the typed line would not.
            // Only when it says something: "5 km" read back as "5 kilometers"
            // is noise (Metis.parseWorth). The arrow in blue, where it went
            // in white, a stale-rates warning in yellow.
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              visible: popup.shownExpr.length > 0 && popup.parseShown
              textFormat: Text.StyledText
              text: (popup.fromHistory ? '<font color="' + popup.parseInk.muted + '">↺ </font>' : "")
                + Metis.parseHtml(popup.shownParse !== "" ? popup.shownParse : popup.shownExpr, popup.parseInk)
                + '<font color="' + popup.parseInk.muted + '">  =</font>'
              color: popup.dimColor
              elide: Text.ElideMiddle
              width: Math.min(implicitWidth + 8, popup.width - 40)
              horizontalAlignment: Text.AlignHCenter
              font.family: Zenon.face
              font.weight: Font.Bold
              font.pixelSize: 14
            }

            // Not understood, said so — a confident wrong number (5 km in
            // miles as 204386 m³) is worse than none. The word it stopped at
            // is a chip, the way lexi shows a word it could not find.
            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              visible: popup.shownBad
              spacing: 8
              // a newer question is being worked out: this verdict is old
              opacity: popup.stale ? 0.45 : 1
              Behavior on opacity { NumberAnimation { duration: Zenon.normal } }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: popup.badWord !== "" ? "can't read" : "can't make sense of that"
                color: Zenon.red
                font.family: Zenon.face
                font.weight: Font.Bold
                font.pixelSize: 19
              }

              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: popup.badWord !== ""
                width: badWordText.implicitWidth + 16
                height: badWordText.implicitHeight + 6
                radius: 5
                color: Qt.rgba(Zenon.red.r, Zenon.red.g, Zenon.red.b, 0.10)
                border.width: 1
                border.color: Qt.rgba(Zenon.red.r, Zenon.red.g, Zenon.red.b, 0.32)

                Text {
                  id: badWordText
                  anchors.centerIn: parent
                  text: popup.badWord
                  color: Zenon.red
                  font.family: Zenon.face
                  font.weight: 600
                  font.pixelSize: 19
                }
              }
            }

            // Numbers large, units quiet (AnswerText), grouped for reading —
            // what is copied is the answer as it is. A selected chip is shown
            // here in its place: the large thing is what Return takes.
            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              visible: popup.shownResult.length > 0
              spacing: 10
              opacity: popup.stale ? 0.45 : 1
              Behavior on opacity { NumberAnimation { duration: Zenon.normal } }

              // the sky where a time-zone answer lands: sun, low sun, moon
              Text {
                id: sky
                readonly property int at: popup.shownStrip.length > 0
                  ? popup.shownStrip[popup.shownStrip.length - 1].min : -1
                visible: (popup.shownKind === "tz") && sky.at >= 0
                anchors.verticalCenter: parent.verticalCenter
                text: Metis.skyGlyph(sky.at)
                color: Zenon[Metis.skyInk(sky.at)]
                font.family: Zenon.face
                font.pixelSize: 22
              }

              AnswerText {
                id: answer
                value: Metis.group(popup.pickText)

                // a click copies it — and the panel stays
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: popup.copyStay(popup.pickText)
                }
              }
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              visible: popup.shownResult.length === 0 && !popup.shownBad
                && popup.query.trim().length > 0
              text: "…"
              color: popup.dimColor
              font.family: Zenon.face
              font.pixelSize: 16
            }
          }
        }

        // ------------------------------------------------- visuals --
        // a time zone's day, or how much of a wait is gone
        Item {
          width: parent.width
          height: popup.visualH
          Behavior on height { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
          clip: true

          DayStrip {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: Math.min(parent.width - 64, 460)
            visible: popup.shownStrip.length > 0
            marks: popup.shownStrip
            opacity: popup.stale ? 0.45 : 1
          }

          ProgressStrip {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: Math.min(parent.width - 64, 460)
            visible: popup.shownProgress !== null
            progress: popup.shownProgress
            opacity: popup.stale ? 0.45 : 1
          }
        }

        // -------------------------------------------------- chips --
        Item {
          width: parent.width
          height: popup.chipRowH
          Behavior on height { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
          clip: true

          // scrolls sideways once they outgrow the panel, faded at whichever
          // end has more (ChipStrip)
          ChipStrip {
            id: chipStrip
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 12
            anchors.rightMargin: 12

            Repeater {
              id: unitRep
              model: popup.recentMode ? [] : popup.chips

              delegate: MetisChip {
                required property var modelData
                required property int index
                order: index
                sel: index === popup.chipIdx
                label: popup.chipMode === "fix" ? modelData : Metis.group(modelData)
                onClicked: popup.chipMode === "fix"
                  ? popup.applyFix(modelData) : popup.copyPaste(modelData)
              }
            }

            // the field empty: the last few kept answers, question muted
            Repeater {
              id: recentRep
              model: popup.recents

              delegate: MetisChip {
                required property var modelData
                required property int index
                order: index
                sel: index === popup.chipIdx
                label: Metis.group(modelData.result)
                sub: modelData.expr
                // Brought back, not pasted: a kept answer is picked to look
                // at again or build on, and pasting closed the panel out from
                // under it. Return does the same; ctrl+return copies it.
                onClicked: popup.recall(modelData.expr)
              }
            }

            // nothing kept yet: questions to try
            Repeater {
              id: exampleRep
              model: popup.examples

              delegate: MetisChip {
                required property var modelData
                required property int index
                order: index
                sel: index === popup.chipIdx
                label: modelData
                onClicked: popup.recall(modelData)
              }
            }
          }
        }

        // --------------------------------------------- hint strip --
        Rectangle {
          width: parent.width
          height: 34
          // black, like every other layer's hint strip — see Zenon.hintBg
          color: Zenon.hintBg

          Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Zenon.border
          }

          HintBar {
            width: parent.width
            anchors.centerIn: parent
            opacity: popup.copied ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: Zenon.fast } }
          }

          Text {
            anchors.centerIn: parent
            text: "\uF00C  copied"
            color: Zenon.green
            opacity: popup.copied ? 1 : 0
            scale: popup.copied ? 1 : 0.85
            Behavior on opacity { NumberAnimation { duration: Zenon.fast } }
            Behavior on scale { NumberAnimation { duration: Zenon.normal; easing.type: Easing.OutBack } }
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: 13
          }
        }
      }
    }
    }

  // -------------------------------------------------------- helpers --

  // a history row shows with the field empty too
  readonly property bool resultShown: popup.query.trim().length > 0 || popup.histIdx >= 0
  readonly property int chipRowH: (popup.recentMode ? popup.recents.length > 0
    : popup.exampleMode ? true
    : popup.chips.length > 0 && popup.resultShown) ? 38 : 0
  readonly property int visualH: !popup.resultShown || popup.shownBad ? 0
    : popup.shownStrip.length > 0 ? 50
    : popup.shownProgress !== null ? 38 : 0

  function calcHeight() {
    return 46 + (popup.resultShown ? popup.resultH : 0) + popup.visualH + popup.chipRowH + 34;
  }

  Timer {
    id: focusRetry
    interval: 60
    repeat: true
    onTriggered: {
      if (!popup.shown) {
        stop();
        return;
      }
      popup.syncFocus();
      if (filterInput.activeFocus) stop();
      if (focusRetry.counter++ > 12) stop();
    }
    property int counter: 0
  }
}

// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// IRIS' WINDOW — the tab strip, the address bar, the pages. Built of the
// suite's own parts, not copies of them:
//
//   the strip      plato/editor/TabBar (terminus' strip), fed by Tabs.qml;
//                  hidden while there is one tab, as plato's is
//   the bar        terminus' glass: the window's own ground (Zenon.layerBg)
//                  with the desktop frosted through it, the active tab the
//                  same surface; back / forward / reload are
//                  morpheus/TransportKey, the address line terminus/BulkField
//   the pages      Page.qml, one per tab, made and destroyed with it
//
//   the line's     what History remembers that fits what is typed, on
//   suggestions    morpheus/CardBody (every menu's card); Up / Down and
//                  Return, or a click
//
//   Ctrl+F find in page (FindBar) · Ctrl + / − / 0 zoom, kept per site ·
//   Ctrl+P the page as a PDF, opened to print ·
//   Ctrl+T new tab · Ctrl+Shift+N new cloak tab · Ctrl+W close ·
//   Ctrl+L / F6 the address line ·
//   Ctrl+Tab / Ctrl+Shift+Tab next / previous · Ctrl+R / F5 reload ·
//   Alt+Left / Alt+Right back / forward · Escape in the line puts it back
//
// IRIS_SELFTEST="<url> <url> …" loads each page in turn in one tab, reports
// the shield's numbers for each, works the tabs (open, switch, move, close),
// reports which renderer WebGL got and that the profiles are still there,
// and quits.

import QtQuick
import QtQuick.Window
import QtWebEngine
import "../morpheus"
import "../plato/editor" as Plato
import "../terminus" as Term
import "../morpheus/surface"
import IrisHost
import "iris.js" as I

Window {
  id: win
  width: 1280; height: 860
  visible: true
  title: deck.here && deck.here.title ? deck.here.title + " — Iris" : "Iris"
  color: "transparent"

  // ── A PAGE FULLSCREEN (a video, a game, slides) ─────────────────────
  // The window goes fullscreen and the chrome steps aside; Escape — the
  // page's own exit or not — and looking at another tab bring both back.
  property bool fullPage: false
  property int wasVisibility: Window.Windowed
  onFullPageChanged: {
    if (win.fullPage) { win.wasVisibility = win.visibility; win.visibility = Window.FullScreen; }
    else win.visibility = win.wasVisibility === Window.FullScreen ? Window.Windowed : win.wasVisibility;
  }
  function leaveFullPage() {
    if (!win.fullPage) return;
    if (deck.here) deck.here.triggerWebAction(WebEngineView.ExitFullScreen);
    win.fullPage = false;
  }

  readonly property font face: Qt.font({ family: Zenon.face, weight: Zenon.weight, pixelSize: Zenon.px(14) })

  Tabs {
    id: deck
    host: pages
    page: Component { Page { } }
    normal: Iris.profile
    cloak: Iris.cloak
    sendWheel: win.scrollMode === "js" ? null : win.scrollMode === "raf" ? win.aimPage : win.sendWheel
    stretchBy: wheel.elastic.stretch
    // the last tab closed: nothing to come back to
    onEmptied: { win.keep(); Qt.quit(); }
    onChanged: if (!Iris.selftest) keeper.restart()
    onMenuAsked: (page, request) => pageMenu.show(page, request,
      page.mapToItem(win.contentItem, request.position.x, request.position.y))
    // a page asking something is brought forward to ask it
    onAnswerAsked: (page, kind, request) => { deck.show(page.tabId); pageDialog[kind](request, page); }
    onFullScreenAsked: (page, on) => win.fullPage = on
    onPrintAsked: (page) => { deck.show(page.tabId); win.printPage(); }
    onTipAsked: (page, request) => {
      if (request.type === TooltipRequest.Hide || page !== deck.here) { pageTip.wanted = false; return; }
      // by the pointer (the request's own x/y are not in the view's space:
      // mapped, a tip landed 346 px above the window)
      const p = pages.mapToItem(win.contentItem, pointer.point.position.x, pointer.point.position.y);
      pageTip.text = request.text;
      pageTip.at = Qt.point(p.x, p.y);
      pageTip.wanted = true;
    }
    onCrashed: (page, status) => {
      if (status === WebEngineView.NormalTerminationStatus) return;
      pageDialog.ask({
        question: "This page stopped",
        glyph: "\u{F0026}", glyphInk: Zenon.yellow,
        detail: (page.title || I.shown(String(page.url))) + (status === WebEngineView.KilledTerminationStatus
          ? " — its process was ended" : " — its process crashed"),
        choices: [{ label: "Reload", ink: Zenon.cyan }, { label: "Close tab", ink: Zenon.muted }],
        cancel: 0,
        done: (i) => { if (i === 0) page.reload(); else deck.close(page.tabId); }
      });
    }
  }

  // into the download directory, and the shell's Jobs drawer (Downloads.qml)
  Downloads { id: downloads; normal: Iris.profile; cloak: Iris.cloak }

  // ── THE SESSION, kept as it changes (and as the window closes) ─────
  // OFF (user, 2026-10-12: "disable the open last page thing"): iris opens
  // fresh, and keeps no session to open. The machinery stays (Tabs'
  // restore/sessionText, core/keep.py's Session) for when iris has settings
  // and this is a switch there.
  readonly property bool restoreSession: false
  Timer { id: keeper; interval: 1000; onTriggered: win.keep() }
  function keep() { if (!Iris.selftest && win.restoreSession) { keeper.stop(); Session.save(deck.sessionText()); } }
  onClosing: win.keep()

  // another `iris <url>` handed its request here (core/door.py)
  Connections {
    target: Iris
    function onAsked(url, cloak) {
      if (url) deck.open(url, false, undefined, cloak);
      else { deck.open("about:blank", false, undefined, cloak); address.claim(); }
      Iris.raiseWindow();
    }
  }

  // ── THE CHROME: strip and bar, one piece of glass ───────────────────
  Item {
    id: chrome
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: strip.height + bar.height
    visible: !win.fullPage
    z: 1

    // ── PLATO'S CHROME, LAYER FOR LAYER (user, 2026-10-13: "look at plato")
    // As PlatoWindow lays it: the strip's own glass first (TabGlass — the
    // active tab in the window's ground, an inactive one a thinner tinted
    // glass), the bar in the window's ground; then the frost of what runs on
    // beneath, over both; then the ground again, over that; then the strip
    // and the bar's keys. Plato's text runs on under its bars; a page cannot
    // (its fixed headers and full-height apps would go behind the bar), so
    // what is frosted is the band of page just below (morpheus/Frost's
    // sampleShift) — the page drifts up through the glass as it scrolls.
    // At terminus' sheet's settings, as every strip now is: the full kernel
    // at full strength, the 0.6 veil over it.
    TabGlass {
      width: strip.width
      height: strip.height
      visible: strip.visible
      cell: strip.hereCell
    }
    Rectangle {
      y: strip.height
      width: parent.width
      height: bar.height
      color: Zenon.layerBg
    }
    Frost {
      anchors.fill: parent
      source: pages
      sampleShift: chrome.height
      track: [strip.height, pages.y]
      blurMax: 64
      scrim: 0
      brightness: 0
      saturation: -0.2
      active: !win.fullPage && !!deck.here
    }
    // terminus' sheet's veil (user, 2026-10-13: its frost on every strip,
    // terminus' bar and iris' navbar alike)
    Rectangle {
      anchors.fill: parent
      color: Zenon.ground
      opacity: 0.6
    }

    // ── THE STRIP ──────────────────────────────────────────────────────
    Plato.TabBar {
      id: strip
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      groundBelow: true
      ed: deck
      client: deck
      // the strips' size (plato's chromeSize, terminus' 16), in iris' face
      face: Qt.font({ family: Zenon.face, weight: Zenon.weight, pixelSize: Zenon.px(16) })
    }

    // ── THE BAR ────────────────────────────────────────────────────────
    // Safari's line (user, 2026-10-13): the address field CENTRED in the bar,
    // taller than the bar's own keys and in larger type; at rest it shows
    // the site alone, centred, and the whole address once typed in. Inside
    // it, the page's own state as chips: at its left the site's settings
    // (how it is connected, and what it may do — a bubble), at its right
    // calypso's two keys and the zoom. How far the page has loaded fills the
    // field from behind, as ceres' band fills (terminus/ProgressFill), and
    // fades once it has.
    Rectangle {
      id: bar
      anchors.top: strip.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      height: 42
      // its ground is laid under the frost (above); the bar itself is clear
      color: "transparent"

      // a cloak tab's bar wears its hue, as plato's statusline wears visual
      // mode's — and its tab in the strip the same (Tabs' `tint`)
      Rectangle {
        anchors.fill: parent
        color: Zenon.alpha(deck.cloakInk, !!deck.here && deck.here.cloaked ? 0.17 : 0)
        Behavior on color { ColorAnimation { duration: Zenon.normal } }
      }

      Row {
        id: keys
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 16
        TransportKey {
          glyph: "\u{F004D}"
          size: Zenon.px(18)
          enabled: !!deck.here && deck.here.canGoBack
          ink: enabled ? Zenon.white : Zenon.muted
          onActivated: deck.here.goBack()
        }
        TransportKey {
          glyph: "\u{F0054}"
          size: Zenon.px(18)
          enabled: !!deck.here && deck.here.canGoForward
          ink: enabled ? Zenon.white : Zenon.muted
          onActivated: deck.here.goForward()
        }
        TransportKey {
          // stop while loading, reload otherwise
          glyph: deck.here && deck.here.loading ? "\u{F0156}" : "\u{F0450}"
          size: Zenon.px(18)
          enabled: !!deck.here
          onActivated: deck.here.loading ? deck.here.stop() : deck.here.reload()
        }
      }

      // the bar's right end: what happens beside the page (downloads)
      Row {
        id: tail
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 16
        // ── DOWNLOADS: terminus' drawer, in iris' bar ─────────────────
        // The shell's own glyph (terminus/JobsGlyph: there only while there
        // is something, glowing, breathing, bursting as terminus' does) over
        // iris' own downloads; on hover — or Ctrl+J, which holds it open —
        // their drawer, the shell's card in a bubble hung from it.
        Term.JobsGlyph {
          id: dlGlyph
          anchors.verticalCenter: parent.verticalCenter
          jobs: downloads.jobs
          size: Zenon.px(16)
          onEmptied: win.dlPinned = false
        }
      }

      // centred whatever the two ends hold: the field keeps clear of the
      // wider of them on both sides
      readonly property real sideRoom: Math.max(keys.width, tail.width) + 28
      Term.BulkField {
        id: address
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(240, Math.min(760, parent.width - 2 * bar.sideRoom))
        height: 34
        // the suite's card rounding, so the line and the suggestions hanging
        // from it round alike at all four outer corners
        radius: Zenon.menuRadius
        textSize: Zenon.px(16)
        leadIn: siteChip.width + 6
        tailIn: chips.width + (chips.width > 0 ? 8 : 0)
        ghostCentred: true
        spliced: hintSurface.open
        restText: deck.here ? I.restOf(deck.here.pendingUrl || String(deck.here.url)) : ""
        ghost: deck.here && deck.here.cloaked ? "Cloaked · search or type an address"
                                              : "Search or type an address"

        // how far the page has loaded, filling the field from behind
        Term.ProgressFill {
          anchors.fill: parent
          anchors.margins: 1
          z: -1
          radius: address.radius - 1
          frac: deck.here ? deck.here.loadProgress / 100 : 0
          done: !deck.here || !deck.here.loading
          fades: true
        }

        // the site: how it is connected, and a click for what it may do
        TransportKey {
          id: siteChip
          anchors.left: parent.left
          anchors.leftMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          z: 2
          readonly property string url: deck.here ? String(deck.here.url) : ""
          readonly property bool web: /^https?:/i.test(siteChip.url)
          readonly property bool secure: /^https:/i.test(siteChip.url)
          visible: siteChip.web
          glyph: siteChip.secure ? "\u{F033E}" : "\u{F033F}"
          ink: siteChip.secure ? Zenon.white : Zenon.yellow
          size: Zenon.px(15)
          onActivated: win.openSite(siteChip)
        }

        Row {
          id: chips
          anchors.right: parent.right
          anchors.rightMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          spacing: 12
          z: 2
          // a login form on the page: calypso, for it (Ctrl+Shift+L)
          TransportKey {
            anchors.verticalCenter: parent.verticalCenter
            visible: !!deck.here && deck.here.hasLogin
            glyph: "\u{F0306}"
            size: Zenon.px(15)
            ink: Zenon.sand
            onActivated: win.fill()
          }
          // a sign-up: calypso makes a password, keeps it, types it (Alt+G)
          TransportKey {
            anchors.verticalCenter: parent.verticalCenter
            visible: !!deck.here && deck.here.hasSignup
            glyph: "\u{F0068}"
            size: Zenon.px(15)
            ink: Zenon.sand
            onActivated: win.suggestPassword()
          }
          // a pop-up held back: a click opens it, beside its page
          TransportKey {
            anchors.verticalCenter: parent.verticalCenter
            visible: !!deck.here && deck.here.blockedPopup !== ""
            glyph: "\u{F03CC}"
            size: Zenon.px(15)
            ink: Zenon.yellow
            onActivated: {
              const p = deck.here;
              deck.open(p.blockedPopup, false, deck.views.indexOf(p) + 1, p.cloaked);
              p.blockedPopup = "";
            }
          }
          // zoomed: how far, at the field's right edge; a click puts it back
          TransportKey {
            anchors.verticalCenter: parent.verticalCenter
            visible: !!deck.here && Math.abs(deck.here.zoomFactor - 1) > 0.001
            glyph: deck.here ? Math.round(deck.here.zoomFactor * 100) + "%" : ""
            size: Zenon.px(13)
            onActivated: win.zoom(0)
          }
        }

        // Return goes; Ctrl+Return makes a bare name www.<name>.com; Alt+Return
        // opens it in a new tab
        onAccepted: {
          const lit = win.hint >= 0 && win.hint < win.hints.length ? win.hints[win.hint].url : "";
          const t = address.text.trim();
          if (address.acceptModifiers & Qt.AltModifier) {
            const url = lit || I.toUrl(t);
            if (url !== "") { win.hints = []; deck.open(url); }
          } else if (lit) win.goTo(lit);
          else win.go((address.acceptModifiers & Qt.ControlModifier) && /^[a-z0-9-]+$/i.test(t) ? "www." + t + ".com" : t);
        }
        // typed, not set: what History has that fits it
        onTextChanged: if (address.focused && !win.setting) win.suggest()
        // left (a pick from the suggestions, a click on the page): the
        // line shows the page's address again, not what was typed — "re"
        // stayed in it after a suggestion took the tab to reddit (the url
        // changed while the line still had the keys, so it was not shown)
        onFocusedChanged: if (!address.focused) { win.hints = []; win.showAddress(true); }
        Keys.onDownPressed: if (win.hints.length) win.hint = Math.min(win.hints.length - 1, win.hint + 1)
        Keys.onUpPressed: if (win.hints.length) win.hint = Math.max(-1, win.hint - 1)
        // Escape: the suggestions go first; then what was typed, and the
        // page's address comes back
        Keys.onEscapePressed: {
          if (win.hints.length) { win.hints = []; return; }
          win.showAddress(true);
          win.toPage();
        }
      }

      Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Zenon.border
      }
    }
  }

  // ── THE PAGES ──────────────────────────────────────────────────────
  Item {
    id: pages
    anchors.top: win.fullPage ? parent.top : chrome.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: findBar.top
    // the page's band draws it off its place: never over the chrome
    clip: true

    // where the pointer is, asked of the page now and then: over something
    // that scrolls on its own, the wheel stays Chromium's (Page.probe)
    HoverHandler {
      id: pointer
      onPointChanged: probeSoon.restart()
    }
    Timer {
      id: probeSoon
      interval: 60
      onTriggered: if (deck.here) deck.here.probe(pointer.point.position.x, pointer.point.position.y)
    }
  }

  // ── THE RIGHT-CLICK MENU: the suite's card, not Chromium's ──────────
  PageMenu { id: pageMenu; host: win; deck: deck }
  // ── A PAGE'S QUESTIONS: the suite's confirmation card ───────────────
  PageDialog { id: pageDialog; backdrop: pages; barBottom: chrome.height }

  // ── THE SUITE'S SCROLLING, OVER THE PAGE ───────────────────────────
  // morpheus' ElasticScroll and Scrollbar on the page's document
  // (PageScroll.qml): the wheel accelerates, glides and stretches as every
  // list in the shell does, and the scrollbar is the shell's, hiding when
  // still. Declined — so the event goes to Chromium as it came — over a
  // panel or a frame that scrolls itself, a page that does not scroll,
  // sideways, and with Ctrl (Chromium's zoom).
  //
  // EVEN AT EVERY FRAME (measured 2026-10-13, the flick: self-test: where
  // the document stands at each frame Chromium draws). The glide is
  // sampled at Qt's frames and Chromium draws on a clock of its own; with
  // Chromium's smooth scrolling off (Qt WebEngine's default) it gathered
  // the samples onto its frames unevenly — steps of 19 11 31 26 21 80 52 44
  // 118 px frame to frame, judder on 15–17 of 55 frames: the "choppy". With
  // it on (core/host.py) Chromium eases each sample onto its own frames:
  // 2 3 5 8 12 17 23 32 42 53 61 71 77 82 80 74 66 57 …, judder 0–2.
  // (Handing Chromium accelerated notches to animate instead measured
  // worse — 6 — and is Chromium's curve, not the suite's.)
  property bool passWheel: false
  // IRIS_SCROLL, for measuring: "js" the glide through scrollTo, "native"
  // Chromium's own wheel with nothing of the suite's
  readonly property string scrollMode: Iris.scrollMode()
  // how a page is moved (PageScroll.send): a precise wheel into Chromium at
  // the pointer, with this overlay stood aside for the moment it takes.
  // DOUBLED: Qt WebEngine hands Chromium half a synthetic wheel's pixels —
  // measured, one 300 px wheel scrolled 150, thirty of 10 px scrolled 150.
  function sendWheel(dy) {
    const p = pointer.point.position;
    const at = pages.mapToItem(win.contentItem, p.x > 0 ? p.x : pages.width / 2, p.y > 0 ? p.y : pages.height / 2);
    wheel.enabled = false;
    Iris.wheelAt(win, at.x, at.y, dy * 2);
    wheel.enabled = true;
  }
  // PROTOTYPE (IRIS_SCROLL=raf): the glide's goal handed to the page, which
  // follows it with scrollfeel's own follow at every frame Chromium draws
  property real aimed: -1
  property string feelSrc: ""
  function aimPage(dy) {
    const p = deck.here;
    if (!p) return;
    const g = wheel.elastic._glide, s = p.scroller;
    const goal = Math.round(Math.max(0, Math.min(s.most, g.running && g.target === s ? g.goal : s.contentY)));
    if (goal === win.aimed) return;
    win.aimed = goal;
    if (!win.feelSrc) win.feelSrc = Iris.feelSource();
    p.runJavaScript("(window.__irisAim || (window.__irisAim = (function () {" + win.feelSrc +
      "; let goal = 0, y = 0, last = 0, run = false;" +
      " function tick(t) { y = follow(y, goal, t - last); last = t; window.scrollTo(0, y);" +
      "   if (y !== goal) requestAnimationFrame(tick); else run = false; }" +
      " return function (g) { goal = g; if (!run) { run = true; y = window.scrollY; last = performance.now(); requestAnimationFrame(tick); } };" +
      "})()))(" + goal + ")", WebEngineScript.ApplicationWorld);
  }
  ElasticScroll {
    id: wheel
    anchors.fill: pages
    enabled: win.scrollMode !== "native"
    // a notch is Chromium's own measure (about 53 CSS px), not a tenth of the
    // view as for a list: a page is read, and a tenth of a tall window per
    // click ran away from the eye (user, 2026-10-12). The shell's
    // acceleration and glide still apply on top.
    step: 56
    intercept: (w) => {
      win.passWheel = (w.modifiers & Qt.ControlModifier)
        || Math.abs(w.angleDelta.x) > Math.abs(w.angleDelta.y)
        || Math.abs(w.pixelDelta.x) > Math.abs(w.pixelDelta.y);
      return false;
    }
    pick: (x, y) => !deck.here || win.passWheel || deck.here.overInner || !deck.here.scroller.scrolls
      ? null : deck.here.scroller
    // the wheel only: the pointer's shape stays the page's (a link's hand…),
    // as ElasticScroll carries no shape of its own
  }
  // ── A MIDDLE CLICK SCROLLS: iris' puck (AutoScroll.qml) ─────────────
  AutoScroll {
    id: autoScroll
    area: pages
    // a middle click on a link is Chromium's (a tab behind)
    leave: (x, y) => !deck.here || deck.here.hovered !== ""
    wheel: (x, y, dy) => {
      const at = pages.mapToItem(win.contentItem, x, y);
      wheel.enabled = false;
      Iris.wheelAt(win, at.x, at.y, dy * 2);
      wheel.enabled = true;
    }
  }
  Scrollbar {
    flick: deck.here ? deck.here.scroller : null
    visible: !!deck.here && deck.here.scroller.scrolls
    anchors.right: pages.right
    anchors.top: pages.top
    anchors.bottom: pages.bottom
  }

  // ── THE LINE'S SUGGESTIONS ─────────────────────────────────────────
  property var hints: []          // [{ url, title }], best first
  property int hint: -1           // the one Up / Down has lit
  property bool setting: false    // the line being set, not typed in
  function suggest() {
    win.hints = address.text.trim() === "" ? [] : History.suggest(address.text, 6);
    win.hint = -1;
  }
  // On a popup surface of its own, as every menu (morpheus/surface): frosted
  // by the compositor, its shadow and fade. It never takes the keyboard —
  // the line keeps it, and Up / Down walk the list from there.
  PopupSurface {
    id: hintSurface
    host: win
    grab: false
    readonly property int pad: 36
    // the field's foot, re-read whenever anything above it moves (the strip
    // coming in pushed the field down and the list stayed — over the line)
    readonly property point under: { address.x; address.y; address.width; bar.y; bar.width; strip.height; chrome.height;
                                      return address.mapToItem(win.contentItem, 0, address.height); }
    open: win.hints.length > 0 && address.focused
    // SPLICED FROM THE LINE (user, 2026-10-13): flush with its foot, the
    // two borders one line, the field squared off and in the card's ground
    // while the list hangs (BulkField's `spliced`, CardBody's squareEdge)
    at: Qt.point(hintSurface.under.x - hintSurface.pad, hintSurface.under.y - 1 - hintSurface.pad)
    width: address.width + 2 * hintSurface.pad
    height: Math.max(1, win.shownHints.length) * Zenon.menuRowHeight + 2 * Zenon.menuCardPad + 2 + 2 * hintSurface.pad
    CardBody {
      id: hintCard
      anchors.fill: parent
      pad: hintSurface.pad
      shade: hintSurface.shade
      squareEdge: "top"
      // each with its site's favicon (History keeps it), a globe where none
      model: win.shownHints.map(h => ({ text: h.title || h.url, hint: I.tabName("", h.url).split("/")[0],
                                         image: h.icon || "", icon: h.icon ? "" : "\u{F059F}" }))
      activeIndex: win.hint
      onChosen: (i) => win.goTo(win.shownHints[i].url)
    }
  }
  // the list as it was last shown, kept while it fades out
  property var shownHints: []
  onHintsChanged: if (win.hints.length) win.shownHints = win.hints

  // go where the line says: an address, or a search (iris.js)
  function go(typed) {
    const url = I.toUrl(typed);
    if (url !== "") win.goTo(url);
  }
  function goTo(url) {
    if (!deck.here) return;
    win.hints = [];
    deck.here.url = url;
    win.toPage();
  }
  // the line shows the page's address — unless it is being typed in, or
  // `force` (Escape)
  function showAddress(force) {
    if (!force && address.focused) return;
    win.setting = true;
    address.text = I.shown(deck.here ? (deck.here.pendingUrl || deck.here.url) : "");
    win.setting = false;
  }
  function toPage() { if (deck.here) deck.here.forceActiveFocus(); }

  // ── A NEW PASSWORD, FROM CALYPSO ───────────────────────────────────
  // The page's new-password field under the cursor, then the shell's
  // calypso (via IrisManager): it makes a password, saves the login — this
  // site, this page, the username typed in the form — and types it in, and
  // into the confirmation after a Tab. The password never passes iris.
  function suggestPassword() {
    const p = deck.here;
    if (!p) return;
    const site = I.siteOf(String(p.url)), url = String(p.url);
    p.focusNewPassword((r) => {
      if (r.found) Shell.send({ suggest: { site: site, url: url, username: r.username, twice: r.twice } });
      if (Iris.selftest) Iris.report("suggest: found " + r.found + ", confirmation " + r.twice + ", username \"" + r.username + "\" for " + site);
    });
  }

  // ── THE DOWNLOADS' DRAWER, hung from their glyph ───────────────────
  property bool dlPinned: false
  Term.BubbleSurface {
    id: dlDrawer
    host: win
    target: dlGlyph
    grab: false
    sticky: true
    fit: false
    cardWidth: 400
    shown: (dlGlyph.hovered || win.dlPinned) && downloads.jobs.model.count > 0
    // read once the pointer has left it, as terminus' drawer does
    onOpenChanged: if (!open) downloads.jobs.clearEnded()
    JobsCard {
      width: 372
      bare: true
      jobs: downloads.jobs
      nouns: ["download", "downloads"]
    }
  }

  // ── THE SITE'S SETTINGS, from the line's site chip ─────────────────
  SiteSettings { id: siteCard; host: win; onShownChanged: if (!shown) win.putAwayAt = Date.now() }
  property real putAwayAt: 0
  function openSite(chip) {
    // the press that put it away was on the chip itself: that is the toggle
    if (siteCard.shown || Date.now() - win.putAwayAt < 400) { siteCard.shown = false; return; }
    if (deck.here) siteCard.openFor(deck.here, chip);
  }

  // ── A PRESS ANYWHERE IN THE WINDOW PUTS A POPUP AWAY ───────────────
  // The compositor dismisses a grabbing popup on a click outside it — when
  // it grants the grab, which hyprland does only for a popup opened on a
  // fresh press, and the chips open theirs on release (user, 2026-10-13:
  // "let me click out of that bubble"). So the window watches its own
  // presses too: a passive point handler over everything, which takes
  // nothing — the press goes on to the page, the line, the strip.
  Item {
    anchors.fill: parent
    z: 100
    PointHandler {
      acceptedButtons: Qt.AllButtons
      grabPermissions: PointerHandler.TakeOverForbidden
      onActiveChanged: if (active) {
        if (siteCard.shown) siteCard.shown = false;
        win.dlPinned = false;
        if (pageMenu.open) pageMenu.close();
      }
    }
  }

  // ── FIND, ALONG THE FOOT ───────────────────────────────────────────
  FindBar {
    id: findBar
    deck: deck
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
  }

  // ── ZOOM, KEPT PER SITE ────────────────────────────────────────────
  // Chrome's own steps. A site's zoom is kept (History, beside the visits)
  // and put back each time it is opened; Ctrl+wheel is Chromium's, and is
  // kept the same way. A cloak tab's is never kept.
  readonly property var zoomSteps: [0.25, 0.33, 0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4, 5]
  function zoom(dir) {
    const p = deck.here;
    if (!p) return;
    const z = p.zoomFactor, s = win.zoomSteps;
    let to = 1;
    if (dir > 0) to = s.find(v => v > z + 0.001) || s[s.length - 1];
    else if (dir < 0) to = s.slice().reverse().find(v => v < z - 0.001) || s[0];
    p.zoomFactor = to;
  }

  // ── PRINT: the page as a PDF, opened in what prints it ───────────────
  function printPage() {
    const p = deck.here;
    if (!p) return;
    p.printToPdf(Iris.pdfPath(p.title || I.siteOf(String(p.url))));
  }

  // ── A PAGE'S TOOLTIP: the suite's card, under the pointer ───────────
  Term.TipCard {
    id: pageTip
    property bool wanted: false
    property point at: Qt.point(0, 0)
    property real shade: wanted ? 1 : 0
    Behavior on shade { NumberAnimation { duration: Zenon.menuFade; easing.type: Easing.OutCubic } }
    plain: true
    z: 25
    visible: shade > 0.01
    opacity: shade
    // below and right of the pointer, turned back inside the window
    x: Math.max(4, Math.min(win.width - width - 4, at.x + 12))
    y: at.y + 22 + height > win.height - 4 ? at.y - height - 8 : at.y + 22
  }

  // ── THE ADDRESS UNDER THE POINTER, at the foot of the page ──────────
  Rectangle {
    readonly property string url: deck.here ? deck.here.hovered : ""
    visible: url !== "" && !win.fullPage
    z: 4
    anchors.left: pages.left
    anchors.bottom: pages.bottom
    anchors.margins: 6
    width: Math.min(hoverText.implicitWidth + 20, pages.width * 0.6)
    height: hoverText.implicitHeight + 10
    radius: Zenon.menuRadius
    color: Zenon.tipBg
    border.width: 1
    border.color: Zenon.border
    Text {
      id: hoverText
      anchors.fill: parent
      anchors.leftMargin: 10
      anchors.rightMargin: 10
      verticalAlignment: Text.AlignVCenter
      text: parent.url
      elide: Text.ElideMiddle
      color: Zenon.soft
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(12)
    }
  }
  // ── A LOGIN, FROM CALYPSO ──────────────────────────────────────────
  // The page's username field under the cursor, then calypso's Quick
  // Access open on this site's logins (the shell's, via IrisManager): you
  // choose, calypso types it there. No secret passes through iris.
  function fill() {
    const p = deck.here;
    if (!p) return;
    const site = I.siteOf(String(p.url));      // the page asked about, not where it goes next
    p.focusLogin((found) => {
      if (found) Shell.send({ fill: site });
      if (Iris.selftest)
        p.runJavaScript("document.activeElement ? document.activeElement.id : ''", (id) =>
          Iris.report("fill: found " + found + ", focused #" + id + ", calypso asked for \"" + site + "\""));
    });
  }
  // a new tab: blank, and the line ready for it
  function newTab() { deck.open("about:blank"); address.claim(); }

  Connections {
    target: deck
    function onHereChanged() { win.leaveFullPage(); win.showAddress(true); if (!address.focused) win.toPage(); }
  }
  Shortcut { sequence: "Escape"; enabled: win.fullPage; onActivated: win.leaveFullPage() }
  Connections {
    target: deck.here
    ignoreUnknownSignals: true
    function onUrlChanged() { win.showAddress(false); }
    function onLoadingChanged() { win.showAddress(false); }
  }

  // ── THE KEYS, AS OTHER BROWSERS HAVE THEM ──────────────────────────
  Shortcut { sequence: "Ctrl+T"; onActivated: win.newTab() }
  Shortcut { sequence: "Ctrl+Shift+T"; onActivated: deck.reopen() }
  Shortcut { sequence: "Ctrl+J"; onActivated: win.dlPinned = !win.dlPinned && downloads.jobs.model.count > 0 }
  Shortcut { sequences: ["Alt+D", "Ctrl+K", "Ctrl+E"]; onActivated: address.claim() }
  Shortcut { sequences: ["Ctrl+PgDown"]; onActivated: deck.step(1) }
  Shortcut { sequences: ["Ctrl+PgUp"]; onActivated: deck.step(-1) }
  Shortcut { sequence: "Ctrl+Shift+PgDown"; onActivated: deck.moveTab(deck.current, Math.min(deck.views.length - 1, deck.current + 1)) }
  Shortcut { sequence: "Ctrl+Shift+PgUp"; onActivated: deck.moveTab(deck.current, Math.max(0, deck.current - 1)) }
  // Ctrl+1 … Ctrl+8 that tab, Ctrl+9 the last (and Alt+, as on Linux Chrome)
  Instantiator {
    model: 9
    delegate: Shortcut {
      required property int index
      sequences: ["Ctrl+" + (index + 1), "Alt+" + (index + 1)]
      onActivated: if (deck.views.length) deck.current = index === 8 ? deck.views.length - 1 : Math.min(index, deck.views.length - 1)
    }
  }
  Shortcut { sequences: ["Ctrl+Shift+R", "Shift+F5", "Ctrl+F5"]; onActivated: if (deck.here) deck.here.reloadAndBypassCache() }
  Shortcut { sequence: "Ctrl+U"; onActivated: if (deck.here) deck.here.triggerWebAction(WebEngineView.ViewSource) }
  Shortcut { sequence: "Ctrl+S"; onActivated: if (deck.here) deck.here.triggerWebAction(WebEngineView.SavePage) }
  Shortcut { sequence: "F11"; onActivated: win.visibility = win.visibility === Window.FullScreen ? Window.Windowed : Window.FullScreen }
  Shortcut { sequence: "Alt+Home"; onActivated: if (deck.here) { deck.here.url = "about:blank"; address.claim(); } }
  Shortcut { sequence: "Ctrl+Shift+N"; onActivated: { deck.open("about:blank", false, undefined, true); address.claim(); } }
  Shortcut { sequence: "Ctrl+W"; onActivated: if (deck.here) deck.close(deck.here.tabId) }
  Shortcut { sequences: ["Ctrl+L", "F6"]; onActivated: address.claim() }
  Shortcut { sequences: ["Ctrl+Shift+P"]; onActivated: win.printPage() }
  Shortcut { sequence: "Ctrl+Shift+L"; onActivated: win.fill() }
  Shortcut { sequence: "Alt+G"; onActivated: win.suggestPassword() }
  Shortcut { sequences: ["Ctrl+F", "F3"]; onActivated: findBar.show() }
  Shortcut { sequences: ["Ctrl+=", "Ctrl++"]; onActivated: win.zoom(1) }
  Shortcut { sequence: "Ctrl+-"; onActivated: win.zoom(-1) }
  Shortcut { sequence: "Ctrl+0"; onActivated: win.zoom(0) }
  Shortcut { sequence: "Ctrl+P"; onActivated: win.printPage() }
  Shortcut { sequence: "Ctrl+Tab"; onActivated: deck.step(1) }
  Shortcut { sequence: "Ctrl+Shift+Tab"; onActivated: deck.step(-1) }
  Shortcut { sequences: ["Ctrl+R", "F5"]; onActivated: if (deck.here) deck.here.reload() }
  Shortcut { sequence: "Alt+Left"; onActivated: if (deck.here) deck.here.goBack() }
  Shortcut { sequence: "Alt+Right"; onActivated: if (deck.here) deck.here.goForward() }

  // the last session's tabs come back (each loaded when first looked at),
  // then what this launch asked for in front of them
  Component.onCompleted: {
    if (Iris.selftest && Iris.startUrl.startsWith("churn:")) { churn.start(); return; }
    if (Iris.selftest && Iris.startUrl.startsWith("drive:")) { driver.begin(); return; }
    if (Iris.selftest && Iris.startUrl.startsWith("flick:")) { flick.begin(); return; }
    if (Iris.selftest && Iris.startUrl.startsWith("gaps:")) { gaps.begin(Iris.startUrl.slice(5)); return; }
    // IRIS_SELFTEST="signup:<url> <url> …" — each page: does it read as a
    // sign-up, and what suggest would ask calypso for
    if (Iris.selftest && Iris.startUrl.startsWith("signup:")) {
      const urls = Iris.startUrl.slice(7).split(" ");
      const page = deck.open(urls[0]);
      let at = 0;
      page.loadingChanged.connect((req) => {
        if (req.status !== WebEngineView.LoadSucceededStatus) return;
        signupCheck.restart();
      });
      signupCheck.next = () => {
        Iris.report("signup " + urls[at] + ": login " + page.hasLogin + ", sign-up " + page.hasSignup);
        if (page.hasSignup) win.suggestPassword();
        if (++at < urls.length) page.url = urls[at]; else lookEnd.restart();
      };
      return;
    }
    // IRIS_SELFTEST="look:<url> <url> …" — the pages in tabs, held a while to be
    // looked at (a screenshot), the first in front
    if (Iris.selftest && Iris.startUrl.startsWith("look:")) {
      const urls = Iris.startUrl.slice(5).split(" ");
      for (const u of urls) deck.open(u, u !== urls[0]);
      lookEnd.start();
      return;
    }
    if (Iris.selftest && Iris.startUrl.startsWith("cosmetic:")) {
      const urls = Iris.startUrl.slice(9).split(" ");
      cosmeticCheck.urls = urls;
      cosmeticCheck.page = deck.open(urls[0]);
      cosmeticCheck.restart();
      return;
    }
    // IRIS_SELFTEST="lazy:<url>" — a page that grows as its foot is reached:
    // wheeled to the foot, the stretch let play, then wheeled on — the
    // document must keep going into what loaded meanwhile
    if (Iris.selftest && Iris.startUrl.startsWith("lazy:")) {
      const page = deck.open(Iris.startUrl.slice(5));
      page.loadingChanged.connect((req) => { if (req.status === WebEngineView.LoadSucceededStatus) lazyCheck.start(); });
      return;
    }
    // IRIS_SELFTEST="cursor:<url>" — the pointer over each element with an
    // id, and the shape the window shows for it
    if (Iris.selftest && Iris.startUrl.startsWith("cursor:")) {
      const page = deck.open(Iris.startUrl.slice(7));
      page.loadingChanged.connect((req) => { if (req.status === WebEngineView.LoadSucceededStatus) cursorCheck.start(); });
      return;
    }
    // IRIS_SELFTEST="site:<url>" — the site chip clicked: what the bubble
    // shows, a setting changed and kept, and a picture of it
    if (Iris.selftest && Iris.startUrl.startsWith("site:")) {
      const page = deck.open(Iris.startUrl.slice(5));
      page.loadingChanged.connect((req) => { if (req.status === WebEngineView.LoadSucceededStatus) siteCheck.start(); });
      return;
    }
    // IRIS_SELFTEST="hints:<url> <typed>" — the page visited and its tab
    // closed, then typed in the line: what is suggested, and whether its
    // favicon still loads
    if (Iris.selftest && Iris.startUrl.startsWith("hints:")) {
      const parts = Iris.startUrl.slice(6).split(" ");
      const page = deck.open(parts[0]);
      deck.open("about:blank", true);
      hintsCheck.typed = parts[1];
      page.loadingChanged.connect((req) => { if (req.status === WebEngineView.LoadSucceededStatus) hintsCheck.start(); });
      return;
    }
    // IRIS_SELFTEST="dl:<file url>" — a download: the bar's glyph, its
    // drawer pinned open (Ctrl+J's), the row as it runs and lands
    if (Iris.selftest && Iris.startUrl.startsWith("dl:")) {
      deck.open("about:blank");
      deck.here.url = Iris.startUrl.slice(3);
      dlCheck.start();
      return;
    }
    // IRIS_SELFTEST="auto:<url>" — a middle click (a click: it stays on),
    // the pointer moved below it, the page scrolling; a click ends it
    if (Iris.selftest && Iris.startUrl.startsWith("auto:")) {
      const page = deck.open(Iris.startUrl.slice(5));
      page.loadingChanged.connect((req) => { if (req.status === WebEngineView.LoadSucceededStatus) autoCheck.start(); });
      return;
    }
    // IRIS_SELFTEST="bars:<url>" — whether the page's own scrollbar is gone
    if (Iris.selftest && Iris.startUrl.startsWith("bars:")) {
      const page = deck.open(Iris.startUrl.slice(5));
      page.loadingChanged.connect((req) => {
        if (req.status !== WebEngineView.LoadSucceededStatus) return;
        page.runJavaScript("JSON.stringify({ adopted: (document.adoptedStyleSheets || []).length,"
          + " sw: getComputedStyle(document.documentElement).scrollbarWidth, bodySw: getComputedStyle(document.body).scrollbarWidth,"
          + " gutter: innerWidth - document.documentElement.clientWidth, scroller: document.scrollingElement && document.scrollingElement.nodeName,"
          + " htmlOverflow: getComputedStyle(document.documentElement).overflowY, bodyOverflow: getComputedStyle(document.body).overflowY })",
          (j) => { Iris.report("bars " + j); Qt.quit(); });
      });
      return;
    }
    if (Iris.selftest && Iris.startUrl.startsWith("onewheel:")) {
      const page = deck.open(Iris.startUrl.slice(9));
      page.loadingChanged.connect((req) => { if (req.status === WebEngineView.LoadSucceededStatus) oneWheel.start(); });
      return;
    }
    if (Iris.selftest) { test.begin(); return; }
    const restored = win.restoreSession && deck.restore(Session.load());
    const start = Iris.startUrl, blank = !start || start === "about:blank";
    if (Iris.startCloak) {
      deck.open(blank ? "about:blank" : start, false, undefined, true);
      if (blank) address.claim();
    } else if (!blank) deck.open(start);
    else if (!restored) { deck.open("about:blank"); address.claim(); }
  }

  // ── self-test ──────────────────────────────────────────────────────────
  QtObject {
    id: test
    readonly property var pages: Iris.startUrl.split(/\s+/).filter(s => s)
    property int at: 0
    property var before: ({ seen: 0, blocked: 0, spent: 0 })
    property var page: null
    function begin() {
      test.page = deck.open(test.pages[0]);
      test.page.loadingChanged.connect((req) => {
        if (req.status === WebEngineView.LoadSucceededStatus) settle.restart();
        else if (req.status === WebEngineView.LoadFailedStatus)
          Iris.report("load failed: " + req.url + " " + req.errorString);
      });
    }
    // the shell's Zenon as iris wears it, and the toolkit pieces iris builds on
    function toolkit() {
      Iris.report("zenon theme " + Zenon.themeName + "  cyan " + Zenon.hex(Zenon.cyan)
                  + "  ground " + Zenon.hex(Zenon.ground) + "  face " + Zenon.face + "  fast " + Zenon.fast + "  light " + Zenon.light);
      for (const f of ["morpheus/Elastic", "morpheus/ElasticScroll", "morpheus/TabGlass", "morpheus/Frost",
                       "morpheus/ScrollEdge", "morpheus/DialogButton", "morpheus/Sheet", "terminus/BubbleCard"]) {
        const c = Qt.createComponent("../" + f + ".qml");
        Iris.report("toolkit " + f + ": " + (c.status === Component.Ready ? "ok" : c.errorString().trim()));
      }
    }
    // the tabs, worked as a hand would: two more, switch, carry one, close
    function workTabs() {
      const names = () => deck.tabs.map(t => (t.current ? "*" : "") + t.name).join(" | ");
      Iris.report("tabs start: " + names() + "  strip " + strip.height + "px  line \"" + address.text + "\"");
      deck.open("about:blank");
      deck.open("data:text/html,<title>Third</title>", true);
      Iris.report("tabs opened: " + names());
      deck.step(1);
      Iris.report("tabs stepped: " + names());
      deck.moveTab(2, 0);
      Iris.report("tabs moved: " + names());
      deck.close(deck.here.tabId);
      Iris.report("tabs closed one: " + names() + "  line \"" + address.text + "\"");
      win.go("arch linux wiki");
      Iris.report("typed words go to: " + (deck.here.url + "").slice(0, 40));
      test.workKeep();
    }
    // the suite's scrolling on the page: down by the wheel's own path, then
    // past the top — a band, settling back — then on with the test
    function workScroll() {
      const s = test.page.scroller, el = wheel.elastic;
      Iris.report("scroll: document " + Math.round(s.contentHeight) + " px tall, view " + Math.round(s.height)
                  + " px, pointer over inner scroller " + test.page.overInner);
      el.scroll(s, 900);
      scrollCheck.step = 1;
      scrollCheck.restart();
    }
    // the suite's menu, right-clicked as a hand would (inside this window)
    property var menuSpots: []
    function workMenu() {
      test.page.runJavaScript(
        "JSON.stringify(['a', 'img', 'input', 'p'].map(s => { const r = document.querySelector(s).getBoundingClientRect();" +
        " return [s, r.left + 5, r.top + r.height / 2]; }))",
        (j) => { test.menuSpots = JSON.parse(j); menuCheck.restart(); });
    }
    // cloak, the session and the history, as the window uses them
    function workKeep() {
      const c = deck.open("data:text/html,<title>Secret</title>", false, undefined, true);
      Iris.report("cloak tab: profile off the record " + c.profile.offTheRecord + "  named \""
                  + deck.tabs[deck.indexOf(c.tabId)].name + "\"  marked " + deck.tabs[deck.indexOf(c.tabId)].name.startsWith(deck.cloakMark));
      const s = deck.sessionText();
      Iris.report("session: " + s.slice(0, 160) + (s.indexOf("Secret") < 0 ? "  (cloak tab left out)" : "  CLOAK TAB LEAKED"));
      const before = deck.views.length;
      deck.restore(s);
      const restored = deck.views.slice(before);
      Iris.report("restored " + restored.length + " tabs, lazily: " + restored.every(v => v.pendingUrl !== "" || v === deck.here)
                  + "  names: " + restored.map(v => deck.tabs[deck.indexOf(v.tabId)].name).join(" | "));
      Iris.report("history for \"exam\": " + JSON.stringify(History.suggest("exam", 3)));
      Iris.report("history for \"secret\": " + JSON.stringify(History.suggest("secret", 3)) + " (cloak: must be empty)");
      // asleep: a background tab aged by hand, then the same pass the timer runs
      const L = WebEngineView.LifecycleState, name = (s) => ["Active", "Frozen", "Discarded"][s];
      const bg = deck.open("https://example.com/", true);
      lifeCheck.page = bg;
      lifeCheck.restart();
    }
    function finish() {
      // the asleep check (lifeCheck) runs on its own clock: wait it out
      if (lifeCheck.running) { finishLater.restart(); return; }
      test.page.runJavaScript(
        "(() => { const g = document.createElement('canvas').getContext('webgl2');" +
        " if (!g) return 'no webgl2';" +
        " const d = g.getExtension('WEBGL_debug_renderer_info');" +
        " return d ? g.getParameter(d.UNMASKED_RENDERER_WEBGL) : g.getParameter(g.RENDERER); })()",
        r => {
          Iris.report("webgl renderer: " + r);
          // the profiles still there at the end (they once were collected)
          Iris.report("profiles alive: " + (Iris.profile !== null && Iris.profile.storageName === "iris")
                      + " / cloak off the record: " + (Iris.cloak !== null && Iris.cloak.offTheRecord));
          Qt.quit();
        });
    }
  }

  Timer {
    id: settle
    interval: 6000
    onTriggered: {
      if (test.at === 0) test.toolkit();
      if (test.page.hasLogin) { Iris.report("login form seen: true"); win.fill(); }
      if (test.page.scroller.scrolls && test.at === 0) { test.workScroll(); return; }
      if (String(test.page.title) === "menus") { test.workMenu(); return; }
      if (String(test.page.title) === "dialogs" && pageDialog.open) {
        Iris.report("dialog shown: '" + pageDialog.spec.detail + "'  card drawn " + pageDialog.visible);
        const out = Iris.shotPath();
        const go = () => { pageDialog.answer(0); settle.interval = 1500; settle.restart(); };
        if (out !== "") win.contentItem.grabToImage((r) => { r.saveToFile(out); go(); }); else go();
        return;
      }
      settle.interval = 6000;
      // chrome://gpu in the list: what Chromium says it accelerates
      if (String(test.page.url).startsWith("chrome://gpu")) {
        test.page.runJavaScript(
          "(() => { const walk = (n) => { let s = ''; if (n.shadowRoot) s += walk(n.shadowRoot);" +
          " for (const c of n.childNodes) s += c.nodeType === 3 ? c.textContent : (c.nodeType === 1 ? walk(c) + (getComputedStyle(c).display === 'block' || c.tagName === 'TR' ? '\\n' : ' ') : '');" +
          " return s; }; const t = walk(document.body).replace(/[ \\t]+/g, ' ');" +
          " const a = t.indexOf('Graphics Feature Status'), b = t.indexOf('Problems Detected');" +
          " return a < 0 ? t.slice(0, 800) : t.slice(a, b > a ? b : a + 1500); })()",
          r => Iris.report("gpu status\n" + r));
      }
      // a probe page writes its answer into its title (DONE …)
      if (String(test.page.title).startsWith("DONE")) Iris.report("probe " + test.page.title);
      const s = Iris.shieldStats();
      const n = s.seen - test.before.seen, us = s.meanUs * s.seen - test.before.spent;
      Iris.report(test.pages[test.at] + "  requests " + n + "  blocked " + (s.blocked - test.before.blocked)
                  + "  mean " + (n ? (us / n).toFixed(1) : 0) + "us  worst-so-far " + s.worstUs + "us");
      test.before = { seen: s.seen, blocked: s.blocked, spent: s.meanUs * s.seen };
      if (++test.at < test.pages.length) { test.page.url = test.pages[test.at]; return; }
      test.workTabs();
      test.finish();
    }
  }

  Timer { id: finishLater; interval: 1000; onTriggered: test.finish() }
  Timer {
    id: lookEnd
    interval: 9000
    onTriggered: {
      Iris.report("LOOK DONE");
      const out = Iris.shotPath();
      if (out) win.contentItem.grabToImage((r) => { r.saveToFile(out + "-look.png"); Qt.quit(); }); else Qt.quit();
    }
  }
  Timer { id: signupCheck; property var next: null; interval: 1500; onTriggered: if (next) next() }

  // IRIS_SELFTEST="cosmetic:<url> <url> …" — each page loaded, then what the
  // shield laid into it, and whether the boxes it should hide are hidden
  Timer {
    id: cosmeticCheck
    property var urls: []
    property int at: 0
    property var page: null
    interval: 7000
    onTriggered: {
      const p = page;
      const names = p.userScripts.collection.map(s => s.name + " (" + s.sourceCode.length + " bytes)").join(", ");
      p.runJavaScript(
        "JSON.stringify({ sheet: (document.adoptedStyleSheets || []).reduce((n, sh) => n + sh.cssRules.length, 0),"
        + " boxes: [...document.querySelectorAll('[data-probe]')].map(e => e.dataset.probe + ':' + getComputedStyle(e).display) })",
        (j) => {
          Iris.report("cosmetic " + urls[at] + "\n  laid in: " + names + "\n  in the page: " + j);
          if (++at < urls.length) { p.url = urls[at]; restart(); } else Qt.quit();
        });
    }
  }

  // IRIS_SELFTEST="gaps:<page>" — find, zoom, notifications, location,
  // fullscreen, print, a bad certificate and a site's sign-in, one after
  // another, each answered on the card as a hand would
  Timer {
    id: gaps
    property int step: 0
    property var page: null
    property var steps: []
    interval: 1200
    function begin(url) {
      gaps.page = deck.open(url);
      gaps.page.loadingChanged.connect((req) => { if (req.status === WebEngineView.LoadSucceededStatus && gaps.step === 0) gaps.restart(); });
      const p = () => gaps.page, js = (s, then) => p().runJavaScript(s, then || (() => {}));
      const card = () => pageDialog.open ? "card: \"" + pageDialog.spec.question + "\" [" + pageDialog.choices.map(c => c.label).join(" / ") + "]" : "no card";
      gaps.steps = [
        () => { findBar.show(); findBar.text = "needle"; },
        () => { Iris.report("find: " + findBar.matches + " matches, at " + findBar.at);
                const out = Iris.shotPath();
                const go = () => { findBar.close(); win.zoom(1); win.zoom(1); };
                if (out) win.contentItem.grabToImage((r) => { r.saveToFile(out + "-find.png"); go(); }); else go(); },
        () => { Iris.report("zoom: " + p().zoomFactor + ", kept for " + p().zoomSite + ": " + History.zoomFor(p().zoomSite));
                win.zoom(0); js("Notification.requestPermission().then(r => document.title = 'perm ' + r)"); },
        () => { Iris.report("notifications: " + card());
                const out = Iris.shotPath();
                if (out) win.contentItem.grabToImage((r) => { r.saveToFile(out + "-card.png"); pageDialog.answer(0); }); else pageDialog.answer(0); },
        () => { Iris.report("notifications answered, page says: " + p().title);
                js("new Notification('Hello from the page', { body: 'a notification body' })"); },
        () => { js("navigator.geolocation.getCurrentPosition(() => document.title = 'geo yes', (e) => document.title = 'geo no ' + e.code)"); },
        () => { Iris.report("location: " + card()); pageDialog.answer(1); },
        () => { Iris.report("location answered, page says: " + p().title);
                js("JSON.stringify((r => [r.left + 10, r.top + 10])(document.getElementById('fs').getBoundingClientRect()))",
                   (j) => { const s = JSON.parse(j), q = p().mapToItem(win.contentItem, s[0], s[1]); Iris.click(win, q.x, q.y, false); }); },
        () => { Iris.report("fullscreen: page asked, window full " + win.fullPage + ", chrome shown " + chrome.visible); win.leaveFullPage(); },
        () => { Iris.report("fullscreen: after Escape, window full " + win.fullPage + ", chrome shown " + chrome.visible); js("window.print()"); },
        () => {},
        () => { p().url = "https://expired.badssl.com/"; },
        () => {}, () => {}, () => {},
        () => { Iris.report("certificate: " + card()); pageDialog.answer(0); },
        () => { Iris.report("certificate answered, page at " + p().url); p().url = "https://httpbin.org/basic-auth/iris/secret"; },
        () => {},
        () => { Iris.report("sign-in: " + card()); pageDialog.firstText = "iris"; pageDialog.secondText = "secret"; pageDialog.answer(0); },
        () => {},
        () => { js("document.body.innerText.slice(0, 80)", (t) => Iris.report("sign-in answered, page shows: " + String(t).replace(/\s+/g, " "))); },
        () => { p().url = "data:text/html,<body style='margin:60px'><span id=t title='A tooltip from the page'>hover me</span></body>"; },
        () => { js("JSON.stringify((r => [r.left + 5, r.top + 5])(document.getElementById('t').getBoundingClientRect()))",
                   (j) => { const s = JSON.parse(j), q = p().mapToItem(win.contentItem, s[0], s[1]);
                            Iris.hover(win, q.x - 3, q.y - 3); Iris.hover(win, q.x, q.y); }); },
        () => {},
        () => { Iris.report("tooltip: shown " + pageTip.wanted + ", text \"" + pageTip.text + "\", drawn " + pageTip.visible); },
        () => { Iris.report("tooltip at grab: wanted " + pageTip.wanted + " shade " + pageTip.shade.toFixed(2) + " at " + pageTip.x + "," + pageTip.y + " size " + pageTip.width + "x" + pageTip.height);
                const out = Iris.shotPath();
                if (out) win.contentItem.grabToImage((r) => r.saveToFile(out + "-tip.png")); },
        () => { Qt.quit(); }
      ];
    }
    onTriggered: {
      if (gaps.step >= gaps.steps.length) return;
      gaps.steps[gaps.step++]();
      gaps.restart();
    }
  }

  // IRIS_SELFTEST="drive:<px a frame>:<url>" — the page loaded, then scrolled
  // at that constant speed for a few seconds through PageScroll (iris'
  // delivery, not the wheel's acceleration), for a recording to judge
  FrameAnimation {
    id: driver
    property real speed: 8
    property int frames: 0
    property real t0: 0
    function begin() {
      const parts = Iris.startUrl.split(":");
      driver.speed = parseFloat(parts[1]) || 8;
      const page = deck.open(parts.slice(2).join(":"));
      page.loadingChanged.connect((req) => {
        if (req.status === WebEngineView.LoadSucceededStatus) driveSoon.start();
      });
    }
    onTriggered: {
      const s = deck.here.scroller;
      s.contentY = Math.min(s.most, s.contentY + driver.speed);
      if (driver.frames === 0) driver.t0 = Date.now();
      if (++driver.frames >= 360 || s.contentY >= s.most) {
        driver.stop();
        const ms = Date.now() - driver.t0;
        Iris.report("DRIVE END " + driver.frames + " frames in " + ms + " ms = " + (driver.frames * 1000 / ms).toFixed(1) + " Qt frames/s");
        driveEnd.start();
      }
    }
  }
  Timer {
    id: autoCheck
    property int step: 0
    interval: 800
    repeat: true
    onTriggered: {
      const p = deck.here, c = pages.mapToItem(win.contentItem, 300, 300);
      if (step === 0) { Iris.middle(win, c.x, c.y); }
      else if (step === 1) {
        Iris.report("auto: on " + autoScroll.active + ", held " + autoScroll.held + ", puck at " + autoScroll.home.x + "," + autoScroll.home.y + ", page at " + Math.round(p.scrollPosition.y));
        Iris.hover(win, c.x, c.y + 120);
      } else if (step === 3) {
        Iris.report("auto: pointer 120 px below — speed " + Math.round(autoScroll.speed) + " px/s, page now at " + Math.round(p.scrollPosition.y));
        const out = Iris.shotPath(); if (out) win.contentItem.grabToImage((r) => r.saveToFile(out + "-auto.png"));
        Iris.click(win, c.x, c.y + 120, false);
      } else if (step === 4) {
        Iris.report("auto: after a click — on " + autoScroll.active + ", page stopped at " + Math.round(p.scrollPosition.y));
        stop(); quitSoon.start();
      }
      ++step;
    }
  }
  Timer {
    id: dlCheck
    property int step: 0
    interval: 700
    repeat: true
    onTriggered: {
      const j = downloads.jobs, row = j.model.count ? j.model.get(0) : null;
      Iris.report("dl " + step + ": glyph " + dlGlyph.visible + " (" + dlGlyph.width + "px), rows " + j.model.count
                  + (row ? " — " + row.what + " " + row.state + " " + row.pct + "%" : "") + ", drawer " + dlDrawer.visible);
      if (step === 1) win.dlPinned = true;
      if (step === 3) { const out = Iris.shotPath(); if (out) dlDrawer.contentItem.grabToImage((r) => r.saveToFile(out + "-dl.png")); }
      if (++step > 4) { stop(); quitSoon.start(); }
    }
  }
  Timer {
    id: hintsCheck
    property string typed: ""
    property int step: 0
    property var probe: null
    interval: 2500
    repeat: true
    onTriggered: {
      if (step === 0) { deck.close(deck.views[0].tabId); address.claim(); address.text = typed; }
      else if (step === 1) {
        Iris.report("hints for \"" + typed + "\": " + JSON.stringify(win.hints).slice(0, 220) + "  surface up " + hintSurface.visible);
        const icon = win.hints.length ? win.hints[0].icon : "";
        if (icon) hintsCheck.probe = Qt.createQmlObject("import QtQuick; Image { source: '" + icon + "' }", win.contentItem);
      } else {
        const out = Iris.shotPath();
        if (out) hintSurface.contentItem.grabToImage((r) => r.saveToFile(out + "-hints.png"));
        Iris.report("favicon after its tab closed: " + (hintsCheck.probe ? ["Null", "Ready", "Loading", "Error"][hintsCheck.probe.status] + " " + hintsCheck.probe.implicitWidth + "px" : "none kept"));
        stop(); quitSoon.start();
      }
      ++step;
    }
  }
  Timer { id: quitSoon; interval: 500; onTriggered: Qt.quit() }
  Timer {
    id: siteCheck
    property int step: 0
    interval: 900
    repeat: true
    onTriggered: {
      const p = deck.here;
      if (step === 0) {
        Iris.report("site: line at rest \"" + address.restText + "\", chip shown " + siteChip.visible + " secure " + siteChip.secure);
        win.openSite(siteChip);
      } else if (step === 1) {
        Iris.report("site: bubble open " + siteCard.visible + " at " + siteCard.x + "," + siteCard.y + " " + siteCard.width + "x" + siteCard.height
                    + "  key " + siteCard.key + "  set " + JSON.stringify(siteCard.set));
        Iris.report("site: notifications " + siteCard.stateOf(siteCard.permission(WebEnginePermission.PermissionType.Notifications)));
        siteCard.choose("autoplay", 0);
        const out = Iris.shotPath();
        if (out) siteCard.contentItem.grabToImage((r) => r.saveToFile(out + "-site.png"));
      } else if (step === 2) {
        Iris.report("site: after Autoplay Block — kept " + JSON.stringify(Iris.site(siteCard.key)) + ", page waits for a click " + p.settings.playbackRequiresUserGesture);
        siteCard.choose("shield", 0);
      } else if (step === 3) {
        Iris.report("site: blocking off — cosmetic now " + JSON.stringify(Iris.cosmeticFor(String(p.url))).slice(0, 80));
        siteCard.choose("shield", -1); siteCard.choose("autoplay", -1);
      } else if (step === 4) {
        p.runJavaScript("document.addEventListener('mousedown', () => document.title = 'pressed', true)");
        if (!siteCard.shown) win.openSite(siteChip);
      } else if (step === 5) {
        const q = pages.mapToItem(win.contentItem, pages.width / 2, pages.height / 2);
        Iris.report("site: bubble up again " + siteCard.shown + "; a click on the page");
        Iris.click(win, q.x, q.y, false);
      } else { Iris.report("site: after a click on the page — shown " + siteCard.shown + ", the page had the press: " + (p.title === "pressed")); stop(); Qt.quit(); }
      ++step;
    }
  }
  Timer {
    id: cursorCheck
    property var spots: []
    property int i: -1
    interval: 700
    repeat: true
    onTriggered: {
      const p = deck.here;
      if (i < 0) {
        p.runJavaScript("JSON.stringify([...document.querySelectorAll('[id]')].map(e => { const r = e.getBoundingClientRect(); return [e.id, r.left + 6, r.top + r.height / 2]; }))",
          (j) => { cursorCheck.spots = JSON.parse(j); cursorCheck.i = 0; });
        i = 0; return;
      }
      // Qt applies an item's new cursor where the system pointer is
      // (QCursor::pos), which offscreen never moves: hover again once
      // Chromium has answered, so the window takes it up
      if (i > 0 && i <= spots.length) { const s0 = spots[i - 1], q0 = p.mapToItem(win.contentItem, s0[1], s0[2]); Iris.hover(win, q0.x + 1, q0.y); }
      if (i > 0 && i <= spots.length) Iris.report("cursor over #" + spots[i - 1][0] + ": " + Iris.cursorOf(win) + "  (link hovered: \"" + p.hovered + "\")  over: " + Iris.itemsAt(win, p.mapToItem(win.contentItem, spots[i - 1][1], spots[i - 1][2]).x, p.mapToItem(win.contentItem, spots[i - 1][1], spots[i - 1][2]).y));
      if (i >= spots.length) { stop(); Qt.quit(); return; }
      const s = spots[i++], q = p.mapToItem(win.contentItem, s[1], s[2]);
      Iris.hover(win, q.x - 2, q.y); Iris.hover(win, q.x, q.y);
    }
  }
  Timer {
    id: lazyCheck
    property int step: 0
    interval: 1500
    repeat: true
    function say(what) {
      const p = deck.here, s = p.scroller;
      Iris.report("lazy " + what + ": document " + Math.round(s.contentHeight) + " most " + Math.round(s.most)
                  + " contentY " + Math.round(s.contentY) + " page at " + Math.round(p.scrollPosition.y)
                  + " band " + s.band.toFixed(1));
      p.runJavaScript("JSON.stringify([document.documentElement.scrollHeight, scrollY, innerHeight])", (j) => Iris.report("lazy   page says [height, scrollY, innerHeight] " + j));
    }
    onTriggered: {
      const at = () => Iris.notch(win, pages.width / 2, chrome.height + pages.height / 2, 1);
      if (step === 0) { say("start"); for (let i = 0; i < 40; ++i) at(); }
      else if (step === 1) { say("after 40 notches"); at(); at(); }
      else if (step === 2) { say("after 2 more (should have gone on)"); for (let i = 0; i < 6; ++i) at(); }
      else if (step === 3) { say("after 6 more"); }
      else { stop(); Qt.quit(); }
      ++step;
    }
  }
  Timer {
    id: oneWheel
    property int step: 0
    interval: 1500
    onTriggered: {
      const p = deck.here;
      if (step === 0) { Iris.report("onewheel: at " + p.scrollPosition.y + ", sending 300 px"); win.sendWheel(300); step = 1; restart(); return; }
      if (step === 1) { Iris.report("onewheel: now at " + p.scrollPosition.y + "; sending 30 × 10 px"); for (let i = 0; i < 30; ++i) win.sendWheel(10); step = 2; restart(); return; }
      Iris.report("onewheel: now at " + p.scrollPosition.y);
      Qt.quit();
    }
  }
  // IRIS_SELFTEST="flick:<url>" — the page loaded, then wheel clicks as a
  // mouse sends them (a burst of five, a pause, three more), with where the
  // document stands at every frame Chromium draws (its own rAF clock):
  // reported as the steps frame to frame, and how unevenly they come —
  // judder, in numbers. IRIS_SCROLL picks the delivery being judged.
  Timer {
    id: flick
    property int step: 0
    property var plan: [1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1]
    interval: 45
    repeat: true
    function begin() {
      const page = deck.open(Iris.startUrl.slice(6));
      page.loadingChanged.connect((req) => {
        if (req.status !== WebEngineView.LoadSucceededStatus || flick.step) return;
        flick.step = -1;
        flickSoon.start();
      });
    }
    onTriggered: {
      if (flick.step >= flick.plan.length) { flick.stop(); flickEnd.start(); return; }
      if (flick.plan[flick.step++]) Iris.notch(win, pages.width / 2, chrome.height + pages.height / 2, 1);
    }
  }
  Timer {
    id: flickSoon
    interval: 2500
    onTriggered: {
      deck.here.runJavaScript("window.__f=[];(function f(t){__f.push([t,scrollY]);if(__f.length<400)requestAnimationFrame(f)})(performance.now())");
      Iris.report("FLICK START " + Iris.scrollMode());
      flick.step = 0;
      flick.start();
    }
  }
  Timer {
    id: flickEnd
    interval: 1600
    onTriggered: deck.here.runJavaScript("JSON.stringify(__f)", (j) => {
      const f = JSON.parse(j), d = [], dt = [];
      for (let i = 1; i < f.length; ++i) { d.push(f[i][1] - f[i - 1][1]); dt.push(f[i][0] - f[i - 1][0]); }
      // moving frames only; judder = a step that differs from the mean of
      // its two neighbours by more than a third of it (and 1.5 px)
      let moving = 0, judder = 0, stalls = 0, worst = 0;
      for (let i = 1; i + 1 < d.length; ++i) {
        const around = (d[i - 1] + d[i + 1]) / 2;
        if (Math.abs(around) < 0.5 && Math.abs(d[i]) < 0.5) continue;
        ++moving;
        const off = Math.abs(d[i] - around);
        worst = Math.max(worst, off);
        if (off > Math.max(1.5, Math.abs(around) / 3)) ++judder;
        if (Math.abs(d[i]) < 0.5 && Math.abs(around) > 2) ++stalls;
      }
      const start = d.findIndex(x => x !== 0), end = d.length - [...d].reverse().findIndex(x => x !== 0);
      Iris.report("FLICK steps " + d.slice(Math.max(0, start), end).map(x => Math.round(x)).join(" "));
      Iris.report("FLICK " + moving + " moving frames, judder " + judder + ", stalls " + stalls + ", worst " + worst.toFixed(1)
        + " px, frame " + (dt.reduce((a, b) => a + b, 0) / dt.length).toFixed(2) + " ms, travelled " + Math.round(f[f.length - 1][1]) + " px");
      Qt.quit();
    })
  }
  Timer { id: driveSoon; interval: 3500; onTriggered: { Iris.report("DRIVE START " + Iris.scrollMode()); driver.start(); } }
  Timer { id: driveEnd; interval: 800; onTriggered: Qt.quit() }

  // IRIS_SELFTEST=churn:<n> — n tabs opened and closed, one after another,
  // with iris' memory (and its Chromium processes') along the way: a leak
  // shows as a climb that does not come back down
  Timer {
    id: churn
    property int n: parseInt(Iris.startUrl.slice(6)) || 100
    property int done: 0
    property var page: null
    interval: 400
    repeat: true
    onTriggered: {
      if (done === 0 && !page) {
        deck.open("about:blank");
        Iris.report("churn: start " + Iris.memoryMb() + " MiB");
      }
      if (page) { deck.close(page.tabId); page = null; ++done;
        if (done % 25 === 0) Iris.report("churn: " + done + " tabs opened and closed, " + Iris.memoryMb() + " MiB, " + deck.views.length + " tab(s) left"); }
      if (done >= n) { stop(); churnEnd.start(); return; }
      page = deck.open("data:text/html,<title>t" + done + "</title><h1>tab " + done + "</h1><img src='data:image/svg+xml,%3Csvg xmlns=%22http://www.w3.org/2000/svg%22 width=%22800%22 height=%22600%22/%3E'>");
    }
  }
  Timer { id: churnEnd; interval: 4000; onTriggered: { Iris.report("churn: settled " + Iris.memoryMb() + " MiB"); Qt.quit(); } }
  Timer {
    id: lifeCheck
    property var page: null
    property int step: 0
    interval: 3000
    onTriggered: {
      const L = WebEngineView.LifecycleState, name = (s) => ["Active", "Frozen", "Discarded"][s] || s;
      const v = page;
      if (step === 0) {
        v.hiddenSince = Date.now() - 3 * 60 * 1000;
        Iris.report("asleep: hidden 3 min — recommended " + name(v.recommendedState) + ", state " + name(v.lifecycleState));
        deck.rest(Date.now());
        Iris.report("asleep: after rest — " + name(v.lifecycleState));
        v.hiddenSince = Date.now() - 3 * 60 * 60 * 1000;
        step = 1; restart(); return;
      }
      if (step === 1) {
        Iris.report("asleep: hidden 3 h — recommended " + name(v.recommendedState));
        deck.rest(Date.now());
        Iris.report("asleep: after rest — " + name(v.lifecycleState));
        deck.show(v.tabId);
        step = 2; restart(); return;
      }
      Iris.report("asleep: looked at again — " + name(v.lifecycleState) + ", " + (v.loading ? "reloading" : "loaded") + " " + v.url);
      step = 0;
    }
  }

  Timer {
    id: menuCheck
    property int i: 0
    interval: 900
    onTriggered: {
      if (pageMenu.open) {
        Iris.report("menu on " + test.menuSpots[i - 1][0] + ": " + pageMenu.rows.map(r => r.isSeparator ? "—" : r.text + (r.enabled === false ? " (off)" : "")).join(" · "));
        if (i === 1 && Iris.shotPath() !== "") {
          // the window itself, from inside: what the menu looks like
          const out = Iris.shotPath();
          pageMenu.surface.contentItem.grabToImage((r) => { r.saveToFile(out); Iris.report("menu shot saved"); pageMenu.close(); menuCheck.restart(); });
          return;
        }
        pageMenu.close();
      }
      interval = 900;
      if (i >= test.menuSpots.length) { test.workTabs(); test.finish(); return; }
      const s = test.menuSpots[i++];
      const p = test.page.mapToItem(win.contentItem, s[1], s[2]);
      Iris.poke(win, p.x, p.y);
      restart();
    }
  }

  Timer {
    id: scrollCheck
    property int step: 0
    interval: 700
    onTriggered: {
      const s = test.page.scroller, el = wheel.elastic;
      if (step === 1) {
        Iris.report("scroll: after a 900 px scroll, document at " + Math.round(test.page.scrollPosition.y) + " (asked " + Math.round(s.contentY) + ")");
        el.scroll(s, -5000);
        step = 2; interval = 120; restart();
      } else if (step === 2) {
        Iris.report("scroll: pushed past the top — band " + s.band.toFixed(1) + " px, document at " + Math.round(test.page.scrollPosition.y));
        step = 3; interval = 900; restart();
      } else {
        Iris.report("scroll: settled — band " + s.band.toFixed(1) + " px, contentY " + s.contentY.toFixed(1));
        step = 0; interval = 700;
        test.at = test.pages.length;
        test.workTabs();
        test.finish();
      }
    }
  }

  Timer {
    interval: 90000; running: Iris.selftest
    onTriggered: { Iris.report("self-test timed out"); Qt.quit(); }
  }
}

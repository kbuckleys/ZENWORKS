// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ONE TAB'S PAGE — a WebEngineView. Tabs.qml makes and destroys these; only
// the tab being looked at is visible.
//
//   cloaked      on the cloak profile: off the record, and nothing of it is
//                kept here either (no history, no session) — set when made
//   pendingUrl   a tab restored from the last session, not loaded until it
//                is first looked at (pendingTitle names it meanwhile): a
//                session of forty tabs starts as one page, not forty
//
// A page that asks for a new tab or window (a middle click, target=_blank,
// window.open) hands the request to Tabs, which opens it beside this one.

import QtQuick
import QtWebEngine
import IrisHost
import "iris.js" as I

WebEngineView {
  id: page
  // the strip's id for it (TabBar keys its cells on this)
  property int tabId: 0
  property bool cloaked: false
  property string pendingUrl: ""
  property string pendingTitle: ""
  // when it was last hidden (0 while looked at): Tabs puts it to sleep
  property real hiddenSince: 0
  // a password field is on the page: the bar offers calypso (see fill);
  // a NEW password field (a sign-up, a change of password): calypso offers
  // to make one too (see suggest)
  property bool hasLogin: false
  property bool hasSignup: false

  // ── THE SUITE'S SCROLLING ──────────────────────────────────────────
  // The document as a view, for morpheus' Elastic and Scrollbar
  // (PageScroll.qml). `overInner`: the pointer is over something that
  // scrolls on its own (a panel, a frame) or the document does not scroll
  // at all — the wheel is then Chromium's, untouched.
  //
  // ── PAST AN END, IT STRETCHES (Android's overscroll, not a slide) ─────
  // As every list in the suite does (morpheus/Elastic's `stretch`): what the
  // wheel asks past an edge stretches the page from that edge. A web page
  // has no contentItem for Elastic to stretch, so the page is scaled here,
  // by Elastic's own factor (`stretchBy`, handed in) — one scale of the
  // page's texture on the GPU; the page never relays out.
  property real stretchBy: 0.6
  readonly property PageScroll scroller: PageScroll { page: page }
  transform: Scale {
    origin.x: page.width / 2
    origin.y: page.scroller.band < 0 ? 0 : page.height
    yScale: 1 + page.stretchBy * Math.abs(page.scroller.band) / Math.max(1, page.height)
  }
  property bool overInner: false
  function probe(x, y) {
    if (!page.scroller.scrolls) { page.overInner = true; return; }
    const z = page.scroller.zoom;
    page.runJavaScript(
      "((x, y) => { let e = document.elementFromPoint(x, y);" +
      " while (e && e !== document.body && e !== document.documentElement) {" +
      "   if (e.tagName === 'IFRAME' || e.tagName === 'EMBED' || e.tagName === 'OBJECT') return true;" +
      "   const s = getComputedStyle(e);" +
      "   if (/(auto|scroll|overlay)/.test(s.overflowY) && e.scrollHeight > e.clientHeight + 1) return true;" +
      "   e = e.parentElement; } return false; })(" + Math.round(x / z) + ", " + Math.round(y / z) + ")",
      WebEngineScript.ApplicationWorld, (inner) => page.overInner = !!inner);
  }
  signal wantsTab(var request)
  // a right click: the suite's menu answers it, not Chromium's (PageMenu)
  signal wantsMenu(var request)
  onContextMenuRequested: (request) => page.wantsMenu(request)
  // every question a page puts to the user, for the suite's card
  // (PageDialog): `kind` is the PageDialog function that answers it
  signal wantsAnswer(string kind, var request)
  onJavaScriptDialogRequested: (request) => page.wantsAnswer("jsDialog", request)
  onPermissionRequested: (permission) => page.wantsAnswer("permission", permission)
  onCertificateError: (error) => page.wantsAnswer("certificate", error)
  onAuthenticationDialogRequested: (request) => page.wantsAnswer("signIn", request)
  onRegisterProtocolHandlerRequested: (request) => page.wantsAnswer("protocol", request)
  onWebAuthUxRequested: (request) => page.wantsAnswer("webAuth", request)

  // a video (or a game, a slide deck) wanting the whole screen: the window
  // goes fullscreen with it and the chrome steps aside (Main)
  signal wantsFullScreen(bool on)
  onFullScreenRequested: (request) => { request.accept(); page.wantsFullScreen(request.toggleOn); }
  // the page's own window.close(): its tab closes
  signal wantsClose()
  onWindowCloseRequested: page.wantsClose()
  // the renderer gone (a crash, killed for memory): offered a reload
  signal crashed(int status)
  onRenderProcessTerminated: (terminationStatus, exitCode) => page.crashed(terminationStatus)
  // ── ITS ZOOM, KEPT PER SITE (History) ──────────────────────────────
  // Put back as each site opens; changed (the window's keys, or Ctrl+wheel,
  // which is Chromium's) it is kept — never for a cloak tab.
  property string zoomSite: ""
  property bool zoomSetting: false
  // ── ITS SITE'S OWN SETTINGS (the line's site bubble) ────────────────
  // autoplay: blocked = media waits for a click; popups: whether a page may
  // open a tab nobody clicked for (Tabs.adopt). Read as each site opens.
  property string siteKey: ""
  property var siteSet: ({})
  function applySite() {
    page.siteSet = page.siteKey ? Iris.site(page.siteKey) : {};
    page.settings.playbackRequiresUserGesture = page.siteSet.autoplay === 0;
  }
  // a tab the page tried to open on its own, held back: the line offers it
  property string blockedPopup: ""
  onUrlChanged: {
    const key = I.siteKey(String(page.url));
    if (key !== page.siteKey) { page.siteKey = key; page.blockedPopup = ""; page.applySite(); }
    const site = I.siteOf(String(page.url));
    if (site === page.zoomSite) return;
    page.zoomSite = site;
    page.zoomSetting = true;
    page.zoomFactor = site && !page.cloaked ? History.zoomFor(site) : 1;
    page.zoomSetting = false;
  }
  onZoomFactorChanged: if (!page.zoomSetting && !page.cloaked && page.zoomSite) History.keepZoom(page.zoomSite, page.zoomFactor)

  // a page's own print button (window.print()): the window's Print
  signal wantsPrint()
  onPrintRequested: page.wantsPrint()
  onPdfPrintingFinished: (filePath, success) => { if (success) Iris.openFile(filePath); }

  // a page's own tooltip (an element's title): the suite's card
  // (terminus/TipCard, as WindowTip wears it), not Qt's default
  signal wantsTip(var request)
  onTooltipRequested: (request) => { request.accepted = true; page.wantsTip(request); }

  // the address under the pointer, for the window's status line
  property string hovered: ""
  onLinkHovered: (hoveredUrl) => page.hovered = String(hoveredUrl || "")

  anchors.fill: parent
  visible: false
  // a PDF opens in the page (Chromium's own viewer), not as a download;
  // plugins are what carry the viewer
  settings.pluginsEnabled: true
  settings.pdfViewerEnabled: true
  onNewWindowRequested: (request) => {
    if (Iris.selftest) Iris.report("page " + page.tabId + " asked for a new tab: " + request.requestedUrl
                                   + " (" + request.destination + ", user " + request.isUserInitiated + ")");
    page.wantsTab(request);
  }

  // ── WHAT IT SHOWS: the lists' hiding rules and scriptlets ────────────
  // Armed as each page is about to open (core/shield.py's cosmetic): its
  // own hide rules as a style sheet, laid in iris' world before the page has
  // drawn anything; its scriptlets in the page's own world, before the
  // page's first script, which is the only place they can do their work.
  // Where the lists' generic rules apply, a watcher (iris' world) notes the
  // classes and ids the page grows, and `generic` asks the shield for the
  // rules they call for, every couple of seconds while the page is looked at.
  property string armedFor: ""
  property bool genericOn: false
  onNavigationRequested: (request) => { if (request.isMainFrame) page.arm(String(request.url)); }
  function arm(url) {
    if (url === page.armedFor) return;
    page.armedFor = url;
    const c = Iris.cosmeticFor(url);
    page.genericOn = c.generic;
    const scripts = [];
    const one = (name, world, source) => {
      const s = WebEngine.script();
      s.name = name;
      s.injectionPoint = WebEngineScript.DocumentCreation;
      s.worldId = world;
      s.runsOnSubFrames = false;
      s.sourceCode = source;
      scripts.push(s);
    };
    one("iris-hide", WebEngineScript.ApplicationWorld,
        I.sheetJs() + "(() => { window.__irisHide = (css) => { if (css) __irisSheet('iris-hide', css, true); };"
      + " const seen = new Set(), fresh = { c: new Set(), i: new Set() };"
      + " const note = (el) => { if (!el || el.nodeType !== 1) return;"
      + "   if (el.id && !seen.has('#' + el.id)) { seen.add('#' + el.id); fresh.i.add(el.id); }"
      + "   for (const c of el.classList || []) if (!seen.has('.' + c)) { seen.add('.' + c); fresh.c.add(c); } };"
      + " window.__irisTake = () => { const r = { c: [...fresh.c], i: [...fresh.i] }; fresh.c.clear(); fresh.i.clear(); return r; };"
      + " const css = " + JSON.stringify(c.css) + ";"
      + " const start = () => { __irisHide(css);"
      + (c.generic ? " document.querySelectorAll('[class],[id]').forEach(note);"
                   + " new MutationObserver((ms) => { for (const m of ms) for (const n of m.addedNodes) {"
                   + "   note(n); if (n.querySelectorAll) n.querySelectorAll('[class],[id]').forEach(note); } })"
                   + "   .observe(document.documentElement, { childList: true, subtree: true });" : "")
      + " };"
      + " if (document.documentElement) start();"
      + " else new MutationObserver((m, o) => { if (document.documentElement) { o.disconnect(); start(); } })"
      + "   .observe(document, { childList: true }); })();");
    if (c.script) one("iris-scriptlets", WebEngineScript.MainWorld, c.script);
    page.userScripts.collection = scripts;
  }
  function generic() {
    if (!page.genericOn) return;
    const url = page.armedFor;
    page.runJavaScript("window.__irisTake ? __irisTake() : null", WebEngineScript.ApplicationWorld, (r) => {
      if (!r || (!r.c.length && !r.i.length)) return;
      const css = Iris.genericFor(url, r.c, r.i);
      if (css) page.runJavaScript("__irisHide(" + JSON.stringify(css) + ")", WebEngineScript.ApplicationWorld);
    });
  }
  readonly property Timer genericTick: Timer {
    interval: 2000
    repeat: true
    running: page.genericOn && page.visible && page.lifecycleState === WebEngineView.LifecycleState.Active
    triggeredOnStart: true
    onTriggered: page.generic()
  }

  // the first look at a restored tab loads it
  onVisibleChanged: if (page.visible && page.pendingUrl !== "") {
    page.url = page.pendingUrl;
    page.pendingUrl = "";
  }

  // ── WHAT IS KEPT (never for a cloak tab) ────────────────────────────
  onLoadingChanged: (req) => {
    // an address asked for over http and upgraded (HTTPS first,
    // core/shield.py) that has no secure version: the window offers plain http
    if (req.status === WebEngineView.LoadFailedStatus && req.errorDomain === WebEngineLoadingInfo.ConnectionErrorDomain
        && Iris.wasUpgraded(String(req.url)))
      page.wantsAnswer("plain", req);
    if (req.status !== WebEngineView.LoadSucceededStatus) { page.hasLogin = false; page.hasSignup = false; return; }
    if (!page.cloaked) History.visit(String(req.url), page.title);
    page.lookForLogin();
  }

  // ── A LOGIN FORM ───────────────────────────────────────────────────
  // Asked in iris' own world (ApplicationWorld): the page's scripts never
  // see these, nor can they fake an answer. A form drawn after the page
  // loaded (a sign-in dialog) is found when fill is asked for anyway.
  function lookForLogin() {
    page.runJavaScript(
      "(() => { const pw = [...document.querySelectorAll('input[type=password]')];"
      + " const shown = pw.filter(i => i.offsetParent !== null);"
      + " return { login: pw.length > 0,"
      + "   signup: !!document.querySelector('input[autocomplete~=new-password]') || shown.length >= 2 }; })()",
      WebEngineScript.ApplicationWorld, (r) => { page.hasLogin = !!r && r.login; page.hasSignup = !!r && r.signup; });
  }
  // The NEW password field put under the cursor — the one a form marks as
  // new-password, else the first of two shown — for calypso to type a made
  // password into. `then({ found, twice, username })`: whether a second (a
  // confirmation) follows it, and what is in the form's username field.
  function focusNewPassword(then) {
    page.forceActiveFocus();
    page.runJavaScript(
      "(() => { const shown = [...document.querySelectorAll('input[type=password]')].filter(i => i.offsetParent !== null);"
      + " const marked = shown.filter(i => /\\bnew-password\\b/.test(i.autocomplete || ''));"
      + " const set = marked.length ? marked : shown; if (!set.length) return { found: false };"
      + " const first = set[0], after = shown[shown.indexOf(first) + 1];"
      + " const named = document.querySelector('input[autocomplete~=username],input[autocomplete~=email],input[type=email]');"
      + " const text = [...document.querySelectorAll('input')].filter(i => /^(text|email|tel|)$/.test(i.type)"
      + "   && i.offsetParent !== null && (i.compareDocumentPosition(first) & Node.DOCUMENT_POSITION_FOLLOWING));"
      + " const user = (named && named.offsetParent !== null) ? named : text[text.length - 1];"
      + " first.focus();"
      + " return { found: true, twice: !!after && (!marked.length || marked.indexOf(after) >= 0), username: user ? user.value : '' }; })()",
      WebEngineScript.ApplicationWorld, (r) => { if (then) then(r || { found: false }); });
  }
  // The username field put under the cursor — the one a form marks as
  // such, else the visible text field before the password, else the password
  // itself — for calypso to type into. `then(found)`.
  function focusLogin(then) {
    page.forceActiveFocus();
    page.runJavaScript(
      "(() => { const pw = [...document.querySelectorAll('input[type=password]')].find(i => i.offsetParent !== null);" +
      " if (!pw) return false;" +
      " const named = document.querySelector('input[autocomplete~=username],input[autocomplete~=email]');" +
      " const text = [...document.querySelectorAll('input')].filter(i => /^(text|email|tel|)$/.test(i.type)" +
      "   && i.offsetParent !== null && (i.compareDocumentPosition(pw) & Node.DOCUMENT_POSITION_FOLLOWING));" +
      " const u = (named && named.offsetParent !== null) ? named : text[text.length - 1];" +
      " (u || pw).focus(); return true; })()",
      WebEngineScript.ApplicationWorld, (found) => { page.hasLogin = !!found; if (then) then(!!found); });
  }
  onTitleChanged: if (!page.cloaked && !page.loading) History.retitle(String(page.url), page.title)
  // its favicon, for the line's suggestions
  onIconChanged: if (!page.cloaked && String(page.icon) !== "") History.setIcon(String(page.url), String(page.icon))
}

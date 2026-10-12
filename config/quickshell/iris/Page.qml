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
  // a password field is on the page: the bar offers calypso (see fill)
  property bool hasLogin: false

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
  onUrlChanged: {
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
  onNewWindowRequested: (request) => {
    if (Iris.selftest) Iris.report("page " + page.tabId + " asked for a new tab: " + request.requestedUrl
                                   + " (" + request.destination + ", user " + request.isUserInitiated + ")");
    page.wantsTab(request);
  }

  // the first look at a restored tab loads it
  onVisibleChanged: if (page.visible && page.pendingUrl !== "") {
    page.url = page.pendingUrl;
    page.pendingUrl = "";
  }

  // ── WHAT IS KEPT (never for a cloak tab) ────────────────────────────
  onLoadingChanged: (req) => {
    if (req.status !== WebEngineView.LoadSucceededStatus) { page.hasLogin = false; return; }
    if (!page.cloaked) History.visit(String(req.url), page.title);
    page.lookForLogin();
  }

  // ── A LOGIN FORM ───────────────────────────────────────────────────
  // Asked in iris' own world (ApplicationWorld): the page's scripts never
  // see these, nor can they fake an answer. A form drawn after the page
  // loaded (a sign-in dialog) is found when fill is asked for anyway.
  function lookForLogin() {
    page.runJavaScript("!!document.querySelector('input[type=password]')",
                       WebEngineScript.ApplicationWorld, (has) => page.hasLogin = !!has);
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
}

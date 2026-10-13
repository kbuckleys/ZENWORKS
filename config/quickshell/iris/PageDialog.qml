// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// WHEN A PAGE ASKS — every question a page puts to the user, on the suite's
// confirmation card (terminus/ConfirmBody in a morpheus Sheet, as picasso and
// terminus ask theirs), never the plain dialogs Qt WebEngine draws itself.
// Hung from the bar, frosted over the page. One at a time: a second waits
// its turn.
//
//   ask(spec)      the card itself: { question, glyph, glyphInk, detail,
//                  choices: [{ label, ink }] (first is the default, Escape
//                  and a click outside take `cancel` — the last unless
//                  said), fields: [{ ghost, text, masked }],
//                  done(index, values) }
//
// and what fills it, from what Chromium asks:
//
//   jsDialog       alert · confirm · prompt · "leave this page?"
//   permission     camera · microphone · screen · location · notifications ·
//                  clipboard · local fonts · pointer lock — Allow / Block
//                  (Chromium keeps the answer, per site; cloak's is
//                  forgotten with it)
//   certificate    a connection that is not private: Go back, or — where
//                  Chromium allows it — Continue anyway, in red
//   signIn         a site's own sign-in (HTTP auth): a name and a password
//   protocol       "open mailto: links with this site?"
//
// Named for the site asking, as browsers do ("github.com says"). Left / Right
// / Tab move between the answers, Return gives the lit one.

import QtQuick
import QtWebEngine
import "../morpheus"
import "../terminus" as Term
import IrisHost
import "iris.js" as I

Item {
  id: dlg
  anchors.fill: parent
  z: 30
  visible: sheet.shown || sheet.cardInk > 0.01

  // what the card frosts over, and where the bar ends
  required property Item backdrop
  required property real barBottom

  property var spec: null
  // what is typed in the card's fields
  property alias firstText: first.text
  property alias secondText: second.text
  property var waiting: []
  readonly property bool open: dlg.spec !== null
  property int pick: 0
  readonly property var choices: dlg.spec ? dlg.spec.choices : []
  readonly property var fields: dlg.spec && dlg.spec.fields ? dlg.spec.fields : []
  readonly property int cancel: !dlg.spec ? 0
    : dlg.spec.cancel !== undefined ? dlg.spec.cancel : dlg.choices.length - 1

  // ── THE CARD ───────────────────────────────────────────────────────
  function ask(s) {
    if (dlg.spec) { dlg.waiting = dlg.waiting.concat([s]); return; }
    dlg.pick = 0;
    dlg.spec = s;
    const f = s.fields || [];
    first.text = f.length > 0 ? String(f[0].text || "") : "";
    second.text = f.length > 1 ? String(f[1].text || "") : "";
    if (f.length) first.claim(); else keys.forceActiveFocus();
  }
  function answer(i) {
    const s = dlg.spec;
    if (!s) return;
    const values = [first.text, second.text];
    dlg.spec = null;
    try { s.done(i, values); } catch (e) { console.warn("iris: a page's question: " + e); }
    if (dlg.waiting.length) {
      const next = dlg.waiting[0];
      dlg.waiting = dlg.waiting.slice(1);
      Qt.callLater(() => dlg.ask(next));
    }
  }

  readonly property var allowBlock: [{ label: "Allow", ink: Zenon.cyan }, { label: "Block", ink: Zenon.muted }]
  function says(origin) { return (I.siteOf(String(origin)) || "This page"); }

  // ── WHAT CHROMIUM ASKS ─────────────────────────────────────────────
  function jsDialog(request) {
    request.accepted = true;
    const J = JavaScriptDialogRequest, k = request.type;
    const leaving = k === J.DialogTypeBeforeUnload, bare = k === J.DialogTypeAlert, prompt = k === J.DialogTypePrompt;
    dlg.ask({
      question: leaving ? "Leave this page?" : dlg.says(request.securityOrigin) + " says",
      glyph: leaving ? "\u{F0026}" : "\u{F02FD}",
      glyphInk: leaving ? Zenon.yellow : Zenon.cyan,
      detail: leaving ? "Changes you made may not be saved." : String(request.message),
      choices: bare ? [{ label: "OK", ink: Zenon.cyan }]
        : leaving ? [{ label: "Leave", ink: Zenon.red }, { label: "Stay", ink: Zenon.muted }]
        : [{ label: "OK", ink: Zenon.cyan }, { label: "Cancel", ink: Zenon.muted }],
      cancel: bare ? 0 : 1,
      fields: prompt ? [{ ghost: "", text: request.defaultText }] : [],
      done: (i, v) => { if (i === 0) request.dialogAccept(prompt ? v[0] : ""); else request.dialogReject(); }
    });
  }

  function permission(p) {
    const T = WebEnginePermission.PermissionType;
    const what = ({
      [T.MediaAudioCapture]: ["use your microphone", "\u{F036C}"],
      [T.MediaVideoCapture]: ["use your camera", "\u{F0100}"],
      [T.MediaAudioVideoCapture]: ["use your camera and microphone", "\u{F0100}"],
      [T.DesktopVideoCapture]: ["see your screen", "\u{F0379}"],
      [T.DesktopAudioVideoCapture]: ["see your screen and hear its sound", "\u{F0379}"],
      [T.MouseLock]: ["take over your pointer", "\u{F01BE}"],
      [T.Notifications]: ["show notifications", "\u{F009A}"],
      [T.Geolocation]: ["know your location", "\u{F034E}"],
      [T.ClipboardReadWrite]: ["read your clipboard", "\u{F0147}"],
      [T.LocalFontsAccess]: ["use your installed fonts", "\u{F0279}"]
    })[p.permissionType];
    if (!what) { p.deny(); return; }
    dlg.ask({
      question: dlg.says(p.origin) + " wants to " + what[0],
      glyph: what[1], glyphInk: Zenon.cyan,
      detail: String(p.origin),
      choices: dlg.allowBlock,
      done: (i) => { if (i === 0) p.grant(); else p.deny(); }
    });
  }

  // `page`: the tab it is for — Go back takes it back where it was
  function certificate(error, page) {
    error.defer();
    // upgraded by HTTPS first: the http site it really is, offered as such
    if (Iris.wasUpgraded(String(error.url))) {
      error.rejectCertificate();
      dlg.plain({ url: error.url }, page);
      return;
    }
    const can = error.overridable;
    dlg.ask({
      question: "This connection isn't private",
      glyph: "\u{F0026}", glyphInk: Zenon.red,
      detail: String(error.description) + "  (" + (I.siteOf(String(error.url)) || String(error.url)) + ")",
      choices: can ? [{ label: "Go back", ink: Zenon.cyan }, { label: "Continue anyway", ink: Zenon.red }]
                   : [{ label: "Go back", ink: Zenon.cyan }],
      cancel: 0,
      done: (i) => {
        if (can && i === 1) { error.acceptCertificate(); return; }
        error.rejectCertificate();
        // once the refusal has landed (Chromium commits its error page
        // first): back to where the tab was
        if (page) backSoon.go(page);
      }
    });
  }

  // HTTPS FIRST (core/shield.py): a site asked for over http was asked for
  // over https, and has no secure version — or one whose certificate is not
  // its own (`certificate` hands those here). Go back, or load it over plain
  // http for the rest of this run, with what that costs said plainly.
  function plain(req, page) {
    const url = String(req.url), host = I.hostOf(url);
    dlg.ask({
      question: host + " has no secure connection",
      glyph: "\u{F033F}", glyphInk: Zenon.yellow,
      detail: "Iris asked for it over HTTPS and it did not answer. Over plain HTTP, anyone on the network can read and change what you send and see.",
      choices: [{ label: "Go back", ink: Zenon.cyan }, { label: "Continue over HTTP", ink: Zenon.red }],
      cancel: 0,
      done: (i) => {
        if (i === 1) { Iris.allowPlain(host); if (page) page.url = url.replace(/^https:/, "http:"); return; }
        if (page) backSoon.go(page);
      }
    });
  }

  // ── A SECURITY KEY OR PASSKEY (WebAuthn) ───────────────────────────
  // Chromium hands each step to the browser to show, and waits on it: a
  // sign-in that asks for a key (Apple's, Google's) hung with nothing on
  // screen. Each step is a card — whose key, its PIN, "touch your key", what
  // went wrong — and the card goes when the key answers.
  function webAuth(request) {
    const W = WebEngineWebAuthUxRequest;
    const site = String(request.relyingPartyId || "This site");
    const step = () => {
      const st = request.state;
      dlg.drop(request);
      if (st === W.WebAuthUxState.SelectAccount) {
        const names = request.userNames || [];
        dlg.ask({
          owner: request,
          question: "Sign in to " + site + " as",
          glyph: "\u{F0306}", glyphInk: Zenon.sand,
          detail: "Your security key holds more than one account for this site.",
          choices: names.map(n => ({ label: String(n), ink: Zenon.cyan })).concat([{ label: "Cancel", ink: Zenon.muted }]),
          done: (i) => { if (i < names.length) request.setSelectedAccount(names[i]); else request.cancel(); }
        });
      } else if (st === W.WebAuthUxState.CollectPin) {
        const r = request.pinRequest;
        const left = r && r.remainingAttempts >= 0 ? "  ·  " + r.remainingAttempts + " tries left" : "";
        dlg.ask({
          owner: request,
          question: "Your security key's PIN",
          glyph: "\u{F0306}", glyphInk: Zenon.sand,
          detail: site + " asks for it" + left,
          choices: [{ label: "Continue", ink: Zenon.cyan }, { label: "Cancel", ink: Zenon.muted }],
          fields: [{ ghost: "PIN", masked: true }],
          done: (i, v) => { if (i === 0) request.setPin(v[0]); else request.cancel(); }
        });
      } else if (st === W.WebAuthUxState.FinishTokenCollection) {
        dlg.ask({
          owner: request,
          question: "Touch your security key",
          glyph: "\u{F0306}", glyphInk: Zenon.cyan,
          detail: "to sign in to " + site,
          choices: [{ label: "Cancel", ink: Zenon.muted }],
          cancel: 0,
          done: () => request.cancel()
        });
      } else if (st === W.WebAuthUxState.RequestFailed) {
        dlg.ask({
          owner: request,
          question: "The security key did not sign you in",
          glyph: "\u{F0026}", glyphInk: Zenon.yellow,
          detail: site,
          choices: [{ label: "Try again", ink: Zenon.cyan }, { label: "Cancel", ink: Zenon.muted }],
          done: (i) => { if (i === 0) request.retry(); else request.cancel(); }
        });
      }
    };
    request.stateChanged.connect(step);
    step();
  }
  // a card no longer wanted: the request it was for has moved on
  function drop(owner) {
    dlg.waiting = dlg.waiting.filter(w => w.owner !== owner);
    if (dlg.spec && dlg.spec.owner === owner) {
      dlg.spec = null;
      if (dlg.waiting.length) {
        const next = dlg.waiting[0];
        dlg.waiting = dlg.waiting.slice(1);
        Qt.callLater(() => dlg.ask(next));
      }
    }
  }

  function signIn(request) {
    request.accepted = true;
    dlg.ask({
      question: dlg.says(request.url) + " asks you to sign in",
      glyph: "\u{F0306}", glyphInk: Zenon.sand,
      detail: request.realm ? String(request.realm) : String(request.url),
      choices: [{ label: "Sign in", ink: Zenon.cyan }, { label: "Cancel", ink: Zenon.muted }],
      fields: [{ ghost: "Name" }, { ghost: "Password", masked: true }],
      done: (i, v) => { if (i === 0) request.dialogAccept(v[0], v[1]); else request.dialogReject(); }
    });
  }

  // asked once per site and kind of link: the answer is kept (History) and
  // given silently each time the site offers again — a mail site offers on
  // every load. A cloak tab uses what was answered, and keeps nothing.
  function protocol(request, page) {
    const scheme = String(request.scheme), origin = String(request.origin);
    const known = History.handlerAnswer(scheme, origin);
    if (known >= 0) { if (known) request.accept(); else request.reject(); return; }
    const cloaked = !!page && page.cloaked;
    dlg.ask({
      question: "Open " + String(request.scheme) + ": links with " + dlg.says(request.origin) + "?",
      glyph: "\u{F0337}", glyphInk: Zenon.cyan,
      detail: String(request.origin),
      choices: dlg.allowBlock,
      done: (i) => {
        if (!cloaked) History.keepHandler(scheme, origin, i === 0);
        if (i === 0) request.accept(); else request.reject();
      }
    });
  }

  Timer {
    id: backSoon
    property var page: null
    interval: 300
    function go(p) { backSoon.page = p; backSoon.restart(); }
    onTriggered: if (backSoon.page && backSoon.page.canGoBack) backSoon.page.goBack()
  }

  // ── DRAWN ──────────────────────────────────────────────────────────
  InputShield { visible: dlg.open; onClicked: dlg.answer(dlg.cancel) }
  Sheet {
    id: sheet
    backdrop: dlg.backdrop
    shown: dlg.open
    fromTop: dlg.barBottom
    cardW: 480
    cardH: body.implicitHeight
    Term.ConfirmBody {
      id: body
      width: parent.width
      question: dlg.spec ? dlg.spec.question : ""
      glyph: dlg.spec ? dlg.spec.glyph || "" : ""
      glyphInk: dlg.spec && dlg.spec.glyphInk ? dlg.spec.glyphInk : Zenon.cyan
      detail: dlg.spec ? dlg.spec.detail || "" : ""
      choices: dlg.choices
      pick: dlg.pick
      onPicked: (i) => dlg.pick = i
      onChose: (i) => dlg.answer(i)
      Term.BulkField {
        id: first
        visible: dlg.fields.length > 0
        width: parent.width
        textSize: Zenon.px(15)
        ghost: dlg.fields.length > 0 ? dlg.fields[0].ghost || "" : ""
        masked: dlg.fields.length > 0 && !!dlg.fields[0].masked
        onAccepted: dlg.fields.length > 1 ? second.claim() : dlg.answer(0)
        onTabbed: if (dlg.fields.length > 1) second.claim()
        Keys.onEscapePressed: dlg.answer(dlg.cancel)
      }
      Term.BulkField {
        id: second
        visible: dlg.fields.length > 1
        width: parent.width
        textSize: Zenon.px(15)
        ghost: dlg.fields.length > 1 ? dlg.fields[1].ghost || "" : ""
        masked: dlg.fields.length > 1 && !!dlg.fields[1].masked
        onAccepted: dlg.answer(0)
        onBackTabbed: first.claim()
        Keys.onEscapePressed: dlg.answer(dlg.cancel)
      }
    }
  }
  Item {
    id: keys
    Keys.onPressed: (e) => {
      if (!dlg.open) return;
      const n = Math.max(1, dlg.choices.length);
      if (e.key === Qt.Key_Escape) { e.accepted = true; dlg.answer(dlg.cancel); }
      else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { e.accepted = true; dlg.answer(dlg.pick); }
      else if (e.key === Qt.Key_Left || e.key === Qt.Key_Right || e.key === Qt.Key_Tab) { e.accepted = true; dlg.pick = (dlg.pick + 1) % n; }
    }
  }
}

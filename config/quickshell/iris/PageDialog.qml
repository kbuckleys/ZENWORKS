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

  function protocol(request) {
    dlg.ask({
      question: "Open " + String(request.scheme) + ": links with " + dlg.says(request.origin) + "?",
      glyph: "\u{F0337}", glyphInk: Zenon.cyan,
      detail: String(request.origin),
      choices: dlg.allowBlock,
      done: (i) => { if (i === 0) request.accept(); else request.reject(); }
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

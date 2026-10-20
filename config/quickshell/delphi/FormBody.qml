// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A QUESTION THAT WANTS SOMETHING TYPED — delphi's, inside its Sheet. Not a
// card of its own: it is the suite's confirmation card (terminus/ConfirmBody)
// with the fields in its slot — terminus' BulkField for a line of text,
// ceres' PasswordField for a secret, morpheus' Check for a yes/no — so a
// branch name is asked for the way a deletion is confirmed.
//
//     form = { title, glyph, ink, detail,
//              fields:  [{ key, label, value, hint, optional }],
//                       a field with `options` ([value] or [[value, label]])
//                       is terminus' BulkDrop instead; with `other` too
//                       ("New branch…") its last choice opens a line to type
//                       a value of your own, `otherHint` in it; with
//                       `lines` it is a well of several lines (a pull
//                       request's description) — ctrl+return answers there;
//                       with `file` a file, typed or chosen (`chooseFile`);
//                       with `path` a directory, typed or chosen (a
//                       Choose… button: `chooseDir`, terminus' picker), a
//                       chosen one followed by `pathTail` when the field
//                       names a directory still to be made in it;
//                       `why`: said beside its label if it is left empty
//              secret:  { key, prompt, purpose }   (instead of fields)
//              toggles: [{ key, label, value }],
//              verb, verbInk, then: (values) => …, cancel: () => … }
//
// Return answers with the verb from any field; Tab walks the fields; Esc is
// Cancel. A field not marked `optional` keeps the verb from answering while
// it is empty.

import QtQuick
import "../morpheus"
import "../morpheus/controls" as Controls
import "../terminus"
import "../picasso"
import "../ceres"

Item {
  id: fb
  property var form: null
  signal done(bool ok, var values)
  // (start, reply(path)) → a directory picker; the window's is terminus'
  property var chooseDir: null
  // (start, reply(path)) → a file picker, for a field with `file`
  property var chooseFile: null

  readonly property var fields: fb.form && fb.form.fields ? fb.form.fields : []
  readonly property var toggles: fb.form && fb.form.toggles ? fb.form.toggles : []
  readonly property var secret: fb.form && fb.form.secret ? fb.form.secret : null
  property var values: ({})
  property var flags: ({})
  property int pick: 0
  // ── HELD WHILE IT WORKS (`hold` on the form, CardSheet) ──────────────
  // The verb turns into the suite's working pill (BusyButton) and the card
  // stays up until the work is done; a refusal (refuse(text)) puts the verb
  // back with the reason under the fields — a wrong password shakes the
  // field — so it can be tried again where it was asked (user, 2026-10-12:
  // "change the login button to the progress animation instead").
  property bool busy: false
  property string busyText: ""
  property string fault: ""
  function refuse(text) {
    fb.busy = false;
    fb.fault = String(text || "");
    if (fb.secret) { pw.failed = true; Qt.callLater(fb.focusFirst); }
  }
  // a dropdown's "something else" choice — what its typed value is kept under
  readonly property string other: "\u0001other"
  // BulkDrop's host contract: the one open list, and the wheel's step
  property var bulkOpenDrop: null
  property real wheelStep: 120

  implicitHeight: body.implicitHeight

  onFormChanged: {
    const v = {}, t = {};
    for (const f of fb.fields) {
      v[f.key] = f.value || (f.options && f.options.length > 0 ? fb.optionsOf(f)[0][0] : "");
      if (f.other) v[f.key + fb.other] = "";
    }
    for (const g of fb.toggles) t[g.key] = !!g.value;
    fb.values = v;
    fb.flags = t;
    fb.missing = [];
    fb.busy = false;
    fb.fault = "";
    fb.pick = 0;
    pw.pw = "";
    pw.failed = false;
    Qt.callLater(fb.focusFirst);
  }
  function focusFirst() {
    if (fb.secret) { pw.asked(); catcher.forceActiveFocus(); return; }
    const first = fieldRep.itemAt(0);
    if (first) first.claim();
    else catcher.forceActiveFocus();
  }
  // a pair is any list, not only a JS Array: a form handed through a var
  // property gets its inner [value, label] pairs back as sequences, which
  // Array.isArray refuses — and the whole pair became the value ("green,Green":
  // clio's journal Color did nothing, 2026-10-17)
  function optionsOf(f) {
    return Array.from(f.options || []).map((o) => o !== null && typeof o === "object" && o.length !== undefined
      ? [String(o[0]), String(o.length > 1 ? o[1] : o[0])] : [o, o])
      .concat(f.other ? [[fb.other, f.other]] : []);
  }
  // what a field answers: the dropdown's choice, or what was typed for "other"
  function valueOf(f) {
    const v = fb.values[f.key];
    return v === fb.other ? String(fb.values[f.key + fb.other] || "") : String(v || "");
  }
  readonly property bool ready: fb.secret ? pw.pw !== ""
    : fb.fields.every((f) => f.optional || fb.valueOf(f).trim() !== "")
  // the fields still wanted, said once the verb was asked for without them
  // — a Save that only stayed gray said nothing (user, 2026-10-11)
  property var missing: []
  onValuesChanged: if (fb.missing.length > 0)
    fb.missing = fb.missing.filter((k) => fb.valueOf(fb.fields.find((f) => f.key === k) || {}).trim() === "")
  function answer(ok) {
    if (fb.busy && ok) return;
    if (ok) fb.fault = "";
    if (ok && !fb.ready) {
      // the secret not given yet (a paste that brought nothing): the field
      // says so, red, rather than the verb doing nothing
      if (fb.secret) { pw.failed = true; return; }
      fb.missing = fb.fields.filter((f) => !f.optional && fb.valueOf(f).trim() === "").map((f) => f.key);
      const i = fb.fields.findIndex((f) => f.key === fb.missing[0]);
      if (i >= 0 && fieldRep.itemAt(i)) fieldRep.itemAt(i).claim();
      return;
    }
    // what the fields SAY, read now — not only the copy kept as they were
    // typed in, which a card handed a new form a moment earlier could
    // leave without a key (an optional field left empty came back missing)
    const out = Object.assign({}, fb.flags);
    fb.fields.forEach((f, i) => {
      const it = fieldRep.itemAt(i);
      out[f.key] = it ? it.answer() : fb.valueOf(f);
    });
    if (fb.secret) { out[fb.secret.key] = pw.pw; pw.pw = ""; }
    fb.done(ok, out);
  }
  function walk(i, d) {
    const n = fieldRep.count;
    if (n > 0) fieldRep.itemAt((i + d + n) % n).claim();
  }

  // Keys that reach here: Esc from a field (BulkField takes Tab and Return
  // itself), and everything while the secret is asked — PasswordField draws,
  // it does not listen; whoever has the keyboard hands it keys.
  Item {
    id: catcher
    Keys.onPressed: (e) => {
      if (fb.secret && pw.key(e)) { e.accepted = true; return; }
      if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { fb.answer(fb.pick === 0); e.accepted = true; }
      else if (e.key === Qt.Key_Escape) { fb.answer(false); e.accepted = true; }
      else if (e.key === Qt.Key_Left || e.key === Qt.Key_Right || e.key === Qt.Key_Tab) { fb.pick = 1 - fb.pick; e.accepted = true; }
    }
  }
  Keys.onEscapePressed: (e) => { e.accepted = true; fb.answer(false); }

  // where a dropdown's list goes: over the whole card, so it can open up or
  // down wherever there is room; a click off an open list puts it away
  Item {
    id: dropLayer
    anchors.fill: parent
    z: 30
    MouseArea {
      anchors.fill: parent
      enabled: fb.bulkOpenDrop !== null
      onClicked: fb.bulkOpenDrop = null
    }
  }

  ConfirmBody {
    id: body
    width: parent.width
    question: fb.form ? fb.form.title || "" : ""
    glyph: fb.form && fb.form.glyph ? fb.form.glyph : ""
    glyphInk: fb.form && fb.form.ink ? fb.form.ink : Zenon.cyan
    detail: fb.form && fb.form.detail ? fb.form.detail : ""
    items: fb.form && fb.form.items ? fb.form.items : []
    choices: [{ label: fb.form && fb.form.verb ? fb.form.verb : "OK",
                ink: fb.ready ? (fb.form && fb.form.verbInk ? fb.form.verbInk : Zenon.cyan) : Zenon.accentMuted,
                busy: fb.busy, busyText: fb.busyText },
              { label: fb.form && fb.form.cancelLabel ? fb.form.cancelLabel : "Cancel", ink: Zenon.accentMuted }]
    pick: fb.pick
    onPicked: (i) => fb.pick = i
    onChose: (i) => fb.answer(i === 0)

    Repeater {
      id: fieldRep
      model: fb.secret ? [] : fb.fields
      delegate: Column {
        id: fcol
        required property var modelData
        required property int index
        readonly property alias box: fbox
        readonly property bool choice: !!fcol.modelData.options
        readonly property bool typed: fcol.choice && fb.values[fcol.modelData.key] === fb.other
        readonly property bool multi: !fcol.choice && !!fcol.modelData.lines
        function claim() {
          if (fcol.multi) well.claim();
          else if (!fcol.choice) fbox.claim();
          else if (fcol.typed) newBox.claim();
          else fdrop.claim();
        }
        function answer() {
          if (fcol.multi) return well.text;
          if (!fcol.choice) return fbox.text;
          return fcol.typed ? newBox.text : String(fb.values[fcol.modelData.key] || "");
        }
        function put(key, v) {
          const o = Object.assign({}, fb.values);
          o[key] = v;
          fb.values = o;
        }
        width: body.width - 36
        spacing: 6
        Text {
          visible: !!fcol.modelData.label
          readonly property bool wanted: fb.missing.indexOf(fcol.modelData.key) >= 0
          text: (fcol.modelData.label || "") + (wanted ? "  —  needed" + (fcol.modelData.why ? ": " + fcol.modelData.why : "") : "")
          color: wanted ? Zenon.red : Zenon.accentSoft
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(14)
        }
        BulkDrop {
          id: fdrop
          visible: fcol.choice
          width: Math.max(implicitWidth, Math.min(parent.width, 260))
          host: fb
          overlay: dropLayer
          textSize: Zenon.px(15)
          options: fcol.choice ? fb.optionsOf(fcol.modelData) : []
          value: String(fb.values[fcol.modelData.key] || "")
          onPicked: (v) => {
            fcol.put(fcol.modelData.key, v);
            if (v === fb.other) Qt.callLater(() => newBox.claim());
          }
          onTabbed: fb.walk(fcol.index, 1)
          onBackTabbed: fb.walk(fcol.index, -1)
        }
        // "something else": a value of your own
        BulkField {
          id: newBox
          visible: fcol.typed
          width: parent.width
          textSize: Zenon.px(16)
          ghost: fcol.modelData.otherHint || ""
          onTextChanged: fcol.put(fcol.modelData.key + fb.other, newBox.text)
          onAccepted: fb.answer(true)
          onTabbed: fb.walk(fcol.index, 1)
          onBackTabbed: fb.walk(fcol.index, -1)
        }
        MessageWell {
          id: well
          visible: fcol.multi
          width: parent.width
          height: fcol.multi ? 120 : 0     // not `visible`: see the secret field below
          ghost: fcol.modelData.hint || ""
          Component.onCompleted: if (fcol.multi) well.text = fcol.modelData.value || ""
          onTextChanged: if (fcol.multi) fcol.put(fcol.modelData.key, well.text)
          onSubmitted: fb.answer(true)
          onEscaped: fb.answer(false)
          onTabbed: fb.walk(fcol.index, 1)
          onBackTabbed: fb.walk(fcol.index, -1)
        }
        Row {
          visible: !fcol.choice && !fcol.multi
          width: parent.width
          spacing: 8
        BulkField {
          id: fbox
          width: parent.width - (pick.visible ? pick.width + parent.spacing : 0)
          textSize: Zenon.px(16)
          ghost: fcol.modelData.hint || ""
          elide: fcol.modelData.path || fcol.modelData.file ? Text.ElideLeft : Text.ElideRight
          text: fcol.modelData.value || ""
          onTextChanged: {
            const v = Object.assign({}, fb.values);
            v[fcol.modelData.key] = fbox.text;
            fb.values = v;
          }
          onAccepted: fb.answer(true)
          onTabbed: fb.walk(fcol.index, 1)
          onBackTabbed: fb.walk(fcol.index, -1)
        }
        // a directory field (or a file one): chosen in terminus' picker, or typed
        DialogButton {
          id: pick
          visible: (!!fcol.modelData.path && !!fb.chooseDir) || (!!fcol.modelData.file && !!fb.chooseFile)
          implicitWidth: 96
          height: fbox.height
          label: "Choose"
          onClicked: {
            const typed = fbox.text.trim();
            const start = typed.indexOf("/") === 0 ? typed.replace(/\/[^/]*$/, "") || "/" : "";
            if (fcol.modelData.file) {
              fb.chooseFile(start, (file) => { if (file) { fbox.text = file; fbox.claim(); } });
              return;
            }
            fb.chooseDir(start, (dir) => {
              if (!dir) return;
              fbox.text = dir.replace(/\/+$/, "") + "/" + (fcol.modelData.pathTail || "");
              fbox.claim();
            });
          }
        }
        }
      }
    }
    PasswordField {
      id: pw
      visible: !!fb.secret
      width: body.width - 36
      // sized by whether a secret is asked, never by `visible`: the card's
      // slot shows only once it has height, and the field is visible only
      // once the slot shows — each waited on the other, and the field
      // stayed at nothing (a pasted token went in unseen, 2026-10-11)
      height: fb.secret ? implicitHeight + (pw.purpose !== "" ? 22 : 0) : 0
      prompt: fb.secret && fb.secret.prompt ? fb.secret.prompt : "input your password"
      busy: fb.busy
      purpose: fb.fault !== "" ? fb.fault : fb.secret && fb.secret.purpose ? fb.secret.purpose : ""
      onSubmitted: (p) => { pw.pw = p; fb.answer(true); }
      onCancelled: fb.answer(false)
    }
    // why a held answer was refused (a secret's reason is under its field)
    Text {
      visible: fb.fault !== "" && !fb.secret
      width: body.width - 36
      wrapMode: Text.Wrap
      text: fb.fault
      color: Zenon.red
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
    }
    Repeater {
      model: fb.toggles
      delegate: Controls.Check {
        id: sw
        required property var modelData
        width: body.width - 36
        height: 26
        label: sw.modelData.label
        lit: !!fb.flags[sw.modelData.key]
        onToggled: {
          const t = Object.assign({}, fb.flags);
          t[sw.modelData.key] = !sw.lit;
          fb.flags = t;
        }
      }
    }
  }
}

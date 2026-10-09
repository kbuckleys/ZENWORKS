// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A Qt key event, in nvim's key notation.
//
// Two kinds of key and they are named differently. A key that TYPES something
// arrives with its text already shifted by the layout — "A", "!", "ä" — and
// that text is what nvim wants, so shift is not named again. A key that does
// not type anything (Escape, the arrows, F5) has no text and is named by what
// it is, with every modifier spelled out: <S-Tab>, <C-Left>.
//
// CTRL CHANGES THE TEXT. Ctrl+A arrives as "\x01", not "a", so with ctrl held
// a letter is read off the key code instead of the text.
//
// ALTGR IS CTRL+ALT. A layout that reaches "@" or "€" through AltGr reports
// both modifiers, and the text is the character it produced. Printable text
// under ctrl+alt is therefore typed as it is, not turned into <C-A-…>.

.pragma library

const named = {};
function _n(k, v) { named[k] = v; }
_n(Qt.Key_Escape, "Esc");
_n(Qt.Key_Return, "CR");
_n(Qt.Key_Enter, "CR");
_n(Qt.Key_Backspace, "BS");
_n(Qt.Key_Tab, "Tab");
_n(Qt.Key_Backtab, "Tab");      // Qt folds shift into the key; S- is added below
_n(Qt.Key_Delete, "Del");
_n(Qt.Key_Insert, "Insert");
_n(Qt.Key_Home, "Home");
_n(Qt.Key_End, "End");
_n(Qt.Key_PageUp, "PageUp");
_n(Qt.Key_PageDown, "PageDown");
_n(Qt.Key_Up, "Up");
_n(Qt.Key_Down, "Down");
_n(Qt.Key_Left, "Left");
_n(Qt.Key_Right, "Right");
_n(Qt.Key_Space, "Space");
for (let i = 1; i <= 12; ++i) _n(Qt.Key_F1 + i - 1, "F" + i);

// keys that are only ever modifiers: nothing to send until something is
// pressed with them
const bare = [Qt.Key_Shift, Qt.Key_Control, Qt.Key_Alt, Qt.Key_Meta,
              Qt.Key_AltGr, Qt.Key_CapsLock, Qt.Key_NumLock, Qt.Key_Super_L,
              Qt.Key_Super_R, Qt.Key_Hyper_L, Qt.Key_Hyper_R];

function prefix(ctrl, alt, shift, meta) {
  return (ctrl ? "C-" : "") + (alt ? "A-" : "") + (shift ? "S-" : "")
    + (meta ? "D-" : "");
}

// "<" is the one printable character nvim's notation claims for itself
function literal(ch) { return ch === "<" ? "<lt>" : ch; }

// the event, as keys for nvim_input; "" when there is nothing to send
function translate(event) {
  const key = event.key;
  if (bare.indexOf(key) >= 0) return "";
  const m = event.modifiers;
  const ctrl = (m & Qt.ControlModifier) !== 0;
  const alt = (m & Qt.AltModifier) !== 0;
  const shift = (m & Qt.ShiftModifier) !== 0;
  const meta = (m & Qt.MetaModifier) !== 0;
  const text = event.text || "";

  // a key with a name of its own
  if (named[key] !== undefined) {
    const name = named[key];
    const sh = shift || key === Qt.Key_Backtab;
    // a plain space types a space
    if (name === "Space" && !ctrl && !alt && !meta) return " ";
    const p = prefix(ctrl, alt, sh, meta);
    return "<" + p + name + ">";
  }

  // ctrl + a letter or digit: read the key code, the text is a control char
  if (ctrl && !(alt && isPrintable(text))) {
    let base = "";
    if (key >= Qt.Key_A && key <= Qt.Key_Z)
      base = String.fromCharCode(key - Qt.Key_A + 97);
    else if (key >= 0x20 && key < 0x7f)
      base = String.fromCharCode(key).toLowerCase();
    if (base === "") return "";
    return "<" + prefix(true, alt, shift, meta) + (base === "<" ? "lt" : base) + ">";
  }

  if (!isPrintable(text)) return "";

  // AltGr: ctrl+alt with a real character — type the character
  if (ctrl && alt) return literal(text);
  // alt or super with a character: nvim names the character, shift is in it
  if (alt || meta) return "<" + prefix(false, alt, false, meta) + (text === "<" ? "lt" : text) + ">";
  return literal(text);
}

function isPrintable(t) {
  if (t.length === 0) return false;
  const c = t.charCodeAt(0);
  return c >= 0x20 && c !== 0x7f;
}

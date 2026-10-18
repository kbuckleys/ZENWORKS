// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// What can come next, after a command half typed: the leader menu's idea
// for nvim's own keys. Type g and wait, and a card (KeyHints.qml) lists what
// g can be followed by; type d and wait, and it lists the motions and text
// objects d can take. Typing on answers it as usual — the card never takes
// a key.
//
// Curated, not complete: the keys worth knowing, by what they do, including
// what plato's plugins add (mini.ai's text objects, mini.surround's s, …).
//
//   forKeys(pending, opPending) → { title, keys: [[key, what], …] } | null
//   sheet() → [{ keys, what, section, feed }]   every one of them at once,
//             and the everyday commands besides, for the cheat sheet
//             (Picker's "motions" mode, Space ?)

.pragma library

const motions = [
  ["w", "To the next word"], ["b", "Back a word"], ["e", "To the end of the word"],
  ["$", "To the end of the line"], ["0", "To the start of the line"], ["^", "To its first character"],
  ["j", "This line and the next"], ["k", "This line and the one above"],
  ["G", "To the end of the file"], ["gg", "To the start of the file"],
  ["}", "To the end of the paragraph"], ["f…", "Up to and onto a character"],
  ["t…", "Up to a character"], ["/…", "Up to a search"], ["%", "To the matching bracket"],
  ["i…", "Inside a text object"], ["a…", "Around a text object"],
];

const objects = [
  ["w", "A word"], ["W", "A WORD (to spaces)"], ["s", "A sentence"], ["p", "A paragraph"],
  ["( b", "Brackets ( )"], ["{ B", "Braces { }"], ["[", "Brackets [ ]"], ["<", "Angle brackets"],
  ["\"", "double quotes"], ["'", "Single quotes"], ["`", "Backticks"],
  ["q", "Any quotes"], ["a", "An argument"], ["f", "A function call"],
  ["t", "A tag"], ["?", "Between two characters you type"],
  ["n…", "The NEXT one of these"], ["l…", "The LAST one of these"],
];

const tables = {
  "g": { title: "g", keys: [
    ["g", "Start of the file"], ["e", "Back to the end of a word"], ["_", "Last character of the line"],
    ["d", "Go to definition"], ["f", "Open the file under the cursor"], ["x", "Open with the system"],
    ["i", "Back to where you last typed"], ["v", "The last selection again"], [";", "Back through changes"],
    ["J", "Join lines, no spaces"], ["u", "Lower case…"], ["U", "Upper case…"], ["~", "Swap case…"],
    ["q", "Rewrap text…"], ["c", "Comment…"], ["cc", "Comment the line"], ["S", "Split / join arguments"],
    ["a", "Align…"], ["rn", "Rename symbol"], ["ra", "Code action"], ["rr", "References"],
    ["ri", "Implementation"], ["O", "Document symbols"], ["*", "Search the word, part of words too"],
  ] },
  "z": { title: "z (view and folds)", keys: [
    ["z", "This line to the middle"], ["t", "This line to the top"], ["b", "This line to the bottom"],
    ["a", "Open / close a fold"], ["o", "Open a fold"], ["c", "Close a fold"],
    ["R", "Open every fold"], ["M", "Close every fold"], ["f", "Make a fold…"],
    ["=", "Spelling suggestions"], ["g", "Add the word to the dictionary"],
  ] },
  "[": { title: "[ (back to the previous…)", keys: [
    ["d", "Diagnostic"], ["q", "Quickfix entry"], ["b", "Buffer"], ["h", "Git change"],
    ["(", "Unclosed ("], ["{", "Unclosed {"], ["s", "Misspelled word"], ["<Space>", "Blank line above"],
  ] },
  "]": { title: "] (on to the next…)", keys: [
    ["d", "Diagnostic"], ["q", "Quickfix entry"], ["b", "Buffer"], ["h", "Git change"],
    [")", "Unclosed )"], ["}", "Unclosed }"], ["s", "Misspelled word"], ["<Space>", "Blank line below"],
  ] },
  "<C-w>": { title: "ctrl w (windows)", keys: [
    ["v", "Split beside"], ["s", "Split below"], ["h j k l", "Go left, down, up, right"],
    ["w", "The next window"], ["q", "Close this one"], ["o", "Close the others"],
    ["=", "Make them all equal"], ["< >", "Narrower, wider"], ["+ -", "Taller, shorter"],
    ["x", "Swap with the next"], ["T", "Into a tab of its own"],
  ] },
  "\"": { title: "\" (which register)", keys: [
    ["a … z", "A named one (A … Z adds to it)"], ["+", "The clipboard"], ["0", "The last yank"],
    ["1 … 9", "The last deletions"], ["_", "Nowhere: delete without saving it"],
    ["%", "The file's name"], [".", "The last text typed"], [":", "The last command"],
    ["/", "The last search"],
  ] },
  "s": { title: "s (surround)", keys: [
    ["a…", "Add: saiw) brackets a word"], ["d…", "Delete: sd\" takes quotes off"],
    ["r……", "Replace: sr)] makes ( ) into [ ]"], ["f…", "Find the next surrounding"],
    ["h…", "Highlight it"], ["n", "Update how many lines it looks in"],
  ] },
  "m": { title: "m (set a mark)", keys: [
    ["a … z", "A mark in this file"], ["A … Z", "A mark in any file"],
  ] },
  "'": { title: "' (to a mark's line)", keys: [
    ["a … z A … Z", "That mark"], ["'", "Where you jumped from"], ["\"", "where you last were in the file"],
    [".", "The last change"], ["^", "The last insert"], ["[ ]", "the last yank or change"],
  ] },
  "`": { title: "` (to a mark, exactly)", keys: [
    ["a … z A … Z", "That mark"], ["`", "Where you jumped from"], [".", "The last change"],
  ] },
  "q": { title: "q (record a macro into…)", keys: [
    ["a … z", "That register — q again to stop"], [":", "The command-line history"],
  ] },
  "@": { title: "@ (play a macro from…)", keys: [
    ["a … z", "That register"], ["@", "The one played last"], [":", "The last command"],
  ] },
  "f": { title: "f (onto the next…)", keys: [["…", "Type the character"], [";", "Then: the next one"], [",", "The one before"]] },
  "t": { title: "t (up to the next…)", keys: [["…", "Type the character"], [";", "Then: the next one"], [",", "The one before"]] },
  "F": { title: "F (back onto…)", keys: [["…", "Type the character"]] },
  "T": { title: "T (back up to…)", keys: [["…", "Type the character"]] },
  "r": { title: "r (replace the character with…)", keys: [["…", "Type the character"]] },
  "Z": { title: "Z", keys: [["Z", "Save and close"], ["Q", "Close without saving"]] },
};

// operators: what waits for a motion or a text object
const operators = {
  "d": "delete", "c": "change", "y": "copy", "<": "indent less", ">": "indent more",
  "=": "re-indent", "gu": "lower case", "gU": "upper case", "g~": "swap case",
  "gq": "rewrap", "gw": "rewrap", "gc": "comment", "!": "filter through a program",
  "zf": "fold", "g?": "rot13", "ga": "align",
};

// "2d" → "d", "\"ay" → "y", "^W" → "<C-w>"
function tidy(keys) {
  let k = String(keys).replace(/\^W/g, "<C-w>").replace(/<C-W>/g, "<C-w>");
  // counts and a register, in either order, come before the command
  for (let again = true; again;) {
    again = false;
    const m = k.match(/^([1-9][0-9]*|"[a-zA-Z0-9"+*_%.:\/-])/);
    if (m && m[0].length < k.length) { k = k.slice(m[0].length); again = true; }
  }
  return k;
}

function forKeys(pending, opPending) {
  const raw = String(pending || "");
  if (raw === "") return null;
  let k = tidy(raw);
  // a count alone, or a register chosen: what can come next is a command
  if (/^[1-9][0-9]*$/.test(k)) return null;
  // "\"a" on its own: the register is chosen and a command comes next
  if (/^"[a-zA-Z0-9"+*_%.:\/-]$/.test(k)) return null;
  // the operator, then a count of its own (d2w)
  k = k.replace(/^(.+?)[1-9][0-9]*$/, "$1");
  for (const op in operators) {
    if (k === op + "i" || k === op + "a")
      return { title: (k.endsWith("i") ? "inside" : "around") + " — " + operators[op], keys: objects };
    if (k === op) return { title: operators[op] + " — then a motion, or i / a and an object",
      keys: [[op.slice(-1) === op ? op : op.slice(-1), "the whole line"]].concat(motions) };
  }
  if (opPending && (k.endsWith("i") || k.endsWith("a")))
    return { title: k.endsWith("i") ? "inside" : "around", keys: objects };
  return tables[k] || null;
}

// ── THE CHEAT SHEET ────────────────────────────────────────────────────
// The tables above are what comes AFTER a key; these are the commands that
// start with one, the everyday ones a hint card never shows because there
// is nothing half typed yet. Together they are the sheet.
const everyday = [
  ["Moving", [
    ["h j k l", "Left, down, up, right"], ["w b e", "Next word, back a word, end of word"],
    ["W B E", "The same, by WORDs (to spaces)"], ["0 ^ $", "Line start, first character, line end"],
    ["gg G", "First line, last line"], ["5G", "Line 5 (any number)"], ["{ }", "Back, on a paragraph"],
    ["%", "The matching bracket"], ["H M L", "Top, middle, bottom of the screen"],
    ["<C-d> <C-u>", "Half a screen down, up"], ["<C-f> <C-b>", "A screen down, up"],
    ["f… t…", "Onto, up to a character (; next, , back)"], ["F… T…", "The same, backwards"],
    ["<C-o> <C-i>", "Back, forward through jumps"], ["''", "Back where you jumped from"],
  ]],
  ["Inserting", [
    ["i a", "Insert before, after the cursor"], ["I A", "Insert at the line's start, end"],
    ["o O", "A new line below, above"], ["gi", "Where you last typed"],
    ["<C-w>", "(typing) delete the word before"], ["<C-r>…", "(typing) paste a register"],
    ["<C-Space>", "(typing) the completion menu"],
  ]],
  ["Changing", [
    ["x X", "Delete the character, the one before"], ["r…", "Replace the character"],
    ["R", "Overwrite as you type"], ["dd D", "Delete the line, to its end"],
    ["cc C", "Change the line, to its end"], ["yy Y", "Copy the line"],
    ["p P", "Paste after, before"], ["u <C-r>", "Undo, redo"], [".", "Do the last change again"],
    ["J", "Join the line below onto this"], ["~", "Swap the case of a character"],
    [">> <<", "Indent, outdent the line"], ["==", "Re-indent the line"],
    ["<C-a> <C-x>", "Add, subtract 1 from the number"], ["ddp", "Swap this line with the next"],
  ]],
  ["Operators (then a motion, or i / a and an object)", Object.keys(operators).map((op) => [op + "…", operators[op]])],
  ["Text objects (after an operator: diw, ci\", ya()…)", objects.map(([k, w]) => ["i" + k.split(" ")[0] + " a" + k.split(" ")[0], w])],
  ["Selecting", [
    ["v V <C-v>", "Select characters, lines, a block"], ["o", "(selecting) to the other end"],
    ["gv", "The last selection again"], ["viw vip", "Select a word, a paragraph"],
    ["I A", "(block) type on every line"],
  ]],
  ["Searching", [
    ["/… ?…", "Search forward, back"], ["n N", "Next, previous match"],
    ["* #", "The word under the cursor, forward, back"],
    [":%s/a/b/g", "Replace every a with b"], [":s/a/b/", "Replace on this line"],
    ["cgn", "Change the next match (. repeats)"],
  ]],
  ["Files and windows", [
    [":w", "Save"], [":q", "Close"], [":wq ZZ", "Save and close"], [":e …", "Open a file"],
    [":bn :bp", "Next, previous buffer"], ["<C-^>", "The file before this one"],
  ]],
];

function _row(section, prefix, k, what) {
  // What Enter types: the command, or as much of it as is certain — up to
  // the character still to be typed (…), and only the prefix where the key
  // lists several choices. Nothing for what is typed in another mode
  // ("(typing) …"): in normal mode those keys mean something else.
  const several = String(k).indexOf(" ") >= 0;
  let feed = several ? prefix : (prefix + k).split("…")[0];
  if (/^\(/.test(what)) feed = "";
  return { keys: prefix + k, what: what, section: section, feed: feed };
}
function sheet() {
  const out = [];
  for (const [section, rows] of everyday) for (const [k, w] of rows) out.push(_row(section, "", k, w));
  for (const pre in tables) {
    const t = tables[pre];
    for (const [k, w] of t.keys) out.push(_row(t.title, pre, k, w));
  }
  return out;
}

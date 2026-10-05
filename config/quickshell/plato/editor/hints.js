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

.pragma library

const motions = [
  ["w", "to the next word"], ["b", "back a word"], ["e", "to the end of the word"],
  ["$", "to the end of the line"], ["0", "to the start of the line"], ["^", "to its first character"],
  ["j", "this line and the next"], ["k", "this line and the one above"],
  ["G", "to the end of the file"], ["gg", "to the start of the file"],
  ["}", "to the end of the paragraph"], ["f…", "up to and onto a character"],
  ["t…", "up to a character"], ["/…", "up to a search"], ["%", "to the matching bracket"],
  ["i…", "inside a text object"], ["a…", "around a text object"],
];

const objects = [
  ["w", "a word"], ["W", "a WORD (to spaces)"], ["s", "a sentence"], ["p", "a paragraph"],
  ["( b", "brackets ( )"], ["{ B", "braces { }"], ["[", "brackets [ ]"], ["<", "angle brackets"],
  ["\"", "double quotes"], ["'", "single quotes"], ["`", "backticks"],
  ["q", "any quotes"], ["a", "an argument"], ["f", "a function call"],
  ["t", "a tag"], ["?", "between two characters you type"],
  ["n…", "the NEXT one of these"], ["l…", "the LAST one of these"],
];

const tables = {
  "g": { title: "g", keys: [
    ["g", "start of the file"], ["e", "back to the end of a word"], ["_", "last character of the line"],
    ["d", "go to definition"], ["f", "open the file under the cursor"], ["x", "open with the system"],
    ["i", "back to where you last typed"], ["v", "the last selection again"], [";", "back through changes"],
    ["J", "join lines, no spaces"], ["u", "lower case…"], ["U", "upper case…"], ["~", "swap case…"],
    ["q", "rewrap text…"], ["c", "comment…"], ["cc", "comment the line"], ["S", "split / join arguments"],
    ["a", "align…"], ["rn", "rename symbol"], ["ra", "code action"], ["rr", "references"],
    ["ri", "implementation"], ["O", "document symbols"], ["*", "search the word, part of words too"],
  ] },
  "z": { title: "z (view and folds)", keys: [
    ["z", "this line to the middle"], ["t", "this line to the top"], ["b", "this line to the bottom"],
    ["a", "open / close a fold"], ["o", "open a fold"], ["c", "close a fold"],
    ["R", "open every fold"], ["M", "close every fold"], ["f", "make a fold…"],
    ["=", "spelling suggestions"], ["g", "add the word to the dictionary"],
  ] },
  "[": { title: "[ (back to the previous…)", keys: [
    ["d", "diagnostic"], ["q", "quickfix entry"], ["b", "buffer"], ["h", "git change"],
    ["(", "unclosed ("], ["{", "unclosed {"], ["s", "misspelt word"], ["<Space>", "blank line above"],
  ] },
  "]": { title: "] (on to the next…)", keys: [
    ["d", "diagnostic"], ["q", "quickfix entry"], ["b", "buffer"], ["h", "git change"],
    [")", "unclosed )"], ["}", "unclosed }"], ["s", "misspelt word"], ["<Space>", "blank line below"],
  ] },
  "<C-w>": { title: "ctrl w (windows)", keys: [
    ["v", "split beside"], ["s", "split below"], ["h j k l", "go left, down, up, right"],
    ["w", "the next window"], ["q", "close this one"], ["o", "close the others"],
    ["=", "make them all equal"], ["< >", "narrower, wider"], ["+ -", "taller, shorter"],
    ["x", "swap with the next"], ["T", "into a tab of its own"],
  ] },
  "\"": { title: "\" (which register)", keys: [
    ["a … z", "a named one (A … Z adds to it)"], ["+", "the clipboard"], ["0", "the last yank"],
    ["1 … 9", "the last deletions"], ["_", "nowhere: delete without saving it"],
    ["%", "the file's name"], [".", "the last text typed"], [":", "the last command"],
    ["/", "the last search"],
  ] },
  "s": { title: "s (surround)", keys: [
    ["a…", "add: saiw) brackets a word"], ["d…", "delete: sd\" takes quotes off"],
    ["r……", "replace: sr)] makes ( ) into [ ]"], ["f…", "find the next surrounding"],
    ["h…", "highlight it"], ["n", "update how many lines it looks in"],
  ] },
  "m": { title: "m (set a mark)", keys: [
    ["a … z", "a mark in this file"], ["A … Z", "a mark in any file"],
  ] },
  "'": { title: "' (to a mark's line)", keys: [
    ["a … z A … Z", "that mark"], ["'", "where you jumped from"], ["\"", "where you last were in the file"],
    [".", "the last change"], ["^", "the last insert"], ["[ ]", "the last yank or change"],
  ] },
  "`": { title: "` (to a mark, exactly)", keys: [
    ["a … z A … Z", "that mark"], ["`", "where you jumped from"], [".", "the last change"],
  ] },
  "q": { title: "q (record a macro into…)", keys: [
    ["a … z", "that register — q again to stop"], [":", "the command-line history"],
  ] },
  "@": { title: "@ (play a macro from…)", keys: [
    ["a … z", "that register"], ["@", "the one played last"], [":", "the last command"],
  ] },
  "f": { title: "f (onto the next…)", keys: [["…", "type the character"], [";", "then: the next one"], [",", "the one before"]] },
  "t": { title: "t (up to the next…)", keys: [["…", "type the character"], [";", "then: the next one"], [",", "the one before"]] },
  "F": { title: "F (back onto…)", keys: [["…", "type the character"]] },
  "T": { title: "T (back up to…)", keys: [["…", "type the character"]] },
  "r": { title: "r (replace the character with…)", keys: [["…", "type the character"]] },
  "Z": { title: "Z", keys: [["Z", "save and close"], ["Q", "close without saving"]] },
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

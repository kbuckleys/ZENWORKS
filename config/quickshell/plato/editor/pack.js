// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

.pragma library
// ONE COPY FOR THE WHOLE SHELL. Without the pragma every component instance
// that imports this file evaluated all of it again (see morpheus/icons.js).

// vim.pack's confirmation buffer, read into something a panel can draw.
//
// nvim/pack.lua prints the buffer vim.pack.update() writes for a person to
// read before confirming. Its shape:
//
//   # Update ─────────             a section: Update, Same, Error, …
//   ## mini.nvim                    a plugin in it
//   Revision before: 6791615e…
//   Revision after:  561751e8… (main)
//   Pending updates:
//   > 561751e │ fix(icons): …        a commit the update brings in
//   < 1a2b3c4 │ …                    one it takes away
//
// Kept to what the panel needs, and forgiving about the rest: a line this
// does not know is skipped, so a newer nvim adding fields breaks nothing.

// what vim.pack's own failures say, in words: its wait gives up after two
// minutes with only "…/_async.lua:53: timeout"
function errorText(t) {
  const s = String(t).replace(/^.*?\/[\w.\/-]+\.lua:\d+: /, "").trim();
  if (s === "timeout") return "GitHub took too long to answer. Try again in a while.";
  return s;
}

function parse(text) {
  const out = { updates: [], errors: [], same: [], error: "" };
  const lines = String(text || "").split("\n");
  let section = "";
  let cur = null;
  for (const raw of lines) {
    const line = raw.replace(/\s+$/, "");
    // anywhere on the line: like the sections below, an ERROR can land on
    // the end of nvim's unterminated "Downloading updates" progress
    // ("…mini.nvimERROR …: timeout"), and read as nothing it left the
    // panel with no updates and no reason
    const e = section === "" ? line.indexOf("ERROR ") : -1;
    if (e >= 0) { out.error = errorText(line.slice(e + 6)); continue; }
    // A section starts a line — or ends one: nvim's own "Downloading
    // updates" progress has no newline after it, and anything that reads both
    // of nvim's outputs together gets "…nvim-autopairs# Update ───".
    let m = line.match(/(?:^|[^#])# (\w+) ─/) || line.match(/^# (\w+)$/);
    if (m) { section = m[1].toLowerCase(); cur = null; continue; }
    m = line.match(/^## (.+)$/);
    if (m) {
      // vim.pack notes a plugin's standing after its name — "(not active)"
      // — which is not part of the name
      const name = m[1].replace(/\s*\(.*\)\s*$/, "").trim();
      if (section === "update") {
        cur = { name: name, before: "", after: "", branch: "", commits: [] };
        out.updates.push(cur);
      } else if (section === "error") {
        cur = { name: name, text: "" };
        out.errors.push(cur);
      } else {
        out.same.push(name);
        cur = null;
      }
      continue;
    }
    if (!cur) continue;
    if (section === "error") {
      if (line !== "") cur.text += (cur.text ? "\n" : "") + line;
      continue;
    }
    m = line.match(/^Revision before:\s*([0-9a-f]+)/);
    if (m) { cur.before = m[1]; continue; }
    m = line.match(/^Revision after:\s*([0-9a-f]+)(?:\s*\((.*)\))?/);
    if (m) { cur.after = m[1]; cur.branch = m[2] || ""; continue; }
    m = line.match(/^([<>]) ([0-9a-f]+) │ (.*)$/);
    if (m) cur.commits.push({ dir: m[1] === ">" ? "in" : "out", sha: m[2], msg: m[3] });
  }
  return out;
}

// how an update is summed up on its row
function summary(u) {
  const n = u.commits.filter((c) => c.dir === "in").length;
  const back = u.commits.length - n;
  if (n === 0 && back > 0) return back + " commit" + (back === 1 ? "" : "s") + " back";
  return n + " new commit" + (n === 1 ? "" : "s");
}

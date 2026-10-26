// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// INPUT METHODS (2026-10-26): Input's fcitx5 rows read and write fcitx5's
// own profile and config, so a file its configtool wrote must come back
// with nothing lost. And the guard: GTK_IM_MODULE and QT_IM_MODULE never
// appear in the shipped config — on Wayland both push apps off the
// text-input protocol, the one path that reaches layer surfaces.

"use strict";

const fs = require("fs");
const path = require("path");

function walk(root, d, out) {
  for (const e of fs.readdirSync(path.join(root, d), { withFileTypes: true })) {
    const rel = d ? d + "/" + e.name : e.name;
    if (e.name.startsWith(".") || e.isSymbolicLink() || /^quickshell\/(oracle\/tests|plato\/nvim)(\/|$)/.test(rel)) continue;
    if (e.isDirectory()) walk(root, rel, out);
    else if (/\.(qml|js|lua|sh|py|conf)$/.test(e.name) || !/\./.test(e.name)) out.push(rel);
  }
  return out;
}

// what fcitx5-configtool writes, with one language added by hand
const PROFILE = [
  "[Groups/0]",
  "# Group Name",
  "Name=Default",
  "# Layout",
  "Default Layout=us",
  "# Default Input Method",
  "DefaultIM=pinyin",
  "",
  "[Groups/0/Items/0]",
  "# Name",
  "Name=keyboard-us",
  "# Layout",
  "Layout=",
  "",
  "[Groups/0/Items/1]",
  "Name=pinyin",
  "Layout=",
  "",
  "[Groups/0/Items/2]",
  "Name=m17n_hi_inscript",
  "Layout=",
  "",
  "[GroupOrder]",
  "0=Default",
  "",
].join("\n");

const CONFIG = [
  "[Hotkey]",
  "EnumerateWithTriggerKeys=True",
  "",
  "[Hotkey/TriggerKeys]",
  "0=Control+space",
  "1=Zenkaku_Hankaku",
  "",
  "[Behavior]",
  "ShareInputState=No",
  "",
].join("\n");

module.exports = {
  module: "oracle/oracle.js",
  cases: (O, t) => {
    t.eq("off with no file", O.parseImLua(""), false);
    t.eq("on round trip", O.parseImLua(O.renderImLua(true)), true);
    t.eq("off round trip", O.parseImLua(O.renderImLua(false)), false);
    t.eq("a commented line is not on", O.parseImLua("-- on = true\nreturn { on = false }"), false);
    t.eq("the shipped file is the renderer's off",
      fs.readFileSync(path.resolve(__dirname, "../../../hypr/lua/inputmethod.lua"), "utf8"), O.renderImLua(false));
    t.eq("an import is written fresh", O.sanitizeBundleFile("hypr/inputmethod.lua", "os.execute('x') return { on = true }"),
      O.renderImLua(true));

    // "Add a language" (2026-10-27): the ones not added, by name, after Choose…
    const all = O.imAddable([]);
    t.eq("the dropdown starts with Choose", all[0].value, "");
    t.eq("every language offered once", all.length - 1, O.IM_ENGINES.length);
    t.eq("an added one is not offered", O.imAddable(["pinyin"]).some((o) => o.value === "pinyin"), false);
    t.eq("offered by name", all.slice(1).map((o) => o.label).join("|"),
      all.slice(1).map((o) => o.label).sort((a, b) => a.localeCompare(b)).join("|"));
    t.eq("no fcitx5 name twice", new Set(O.IM_ENGINES.map((e) => e.im)).size, O.IM_ENGINES.length);
    t.eq("every engine from an fcitx5 package",
      O.IM_ENGINES.filter((e) => !/^fcitx5-/.test(e.pkg)).map((e) => e.im).join(","), "");
    t.eq("layout alone", O.imLayout("us", ""), "us");
    t.eq("first of several, with its variant", O.imLayout("de,us", "nodeadkeys,"), "de-nodeadkeys");
    t.eq("no layout is us", O.imLayout("", ""), "us");

    const p = O.parseImProfile(PROFILE);
    t.eq("profile layout", p.layout, "us");
    t.eq("profile items in order", p.items.join(" "), "keyboard-us pinyin m17n_hi_inscript");
    t.eq("nothing read from nothing", O.parseImProfile("").items.length, 0);

    t.eq("adding keeps the configtool's own", O.imItems(p.items, "us", "mozc", true).join(" "),
      "keyboard-us pinyin m17n_hi_inscript mozc");
    t.eq("removing", O.imItems(p.items, "us", "pinyin", false).join(" "), "keyboard-us m17n_hi_inscript");
    t.eq("adding twice is once", O.imItems(["keyboard-us", "mozc"], "us", "mozc", true).join(" "), "keyboard-us mozc");
    t.eq("the keyboard follows the layout", O.imItems(p.items, "de", "", false)[0], "keyboard-de");
    t.eq("from nothing, the keyboard", O.imItems([], "us", "", false).join(" "), "keyboard-us");

    const back = O.parseImProfile(O.renderImProfile("us", ["keyboard-us", "pinyin", "mozc"]));
    t.eq("render round trip", back.items.join(" "), "keyboard-us pinyin mozc");
    t.eq("render layout", back.layout, "us");
    t.eq("newest language is the default", /DefaultIM=mozc/.test(O.renderImProfile("us", ["keyboard-us", "mozc"])), true);

    t.eq("switch key read", O.parseImKey(CONFIG), "Control+space");
    t.eq("switch key default", O.parseImKey(""), O.IM_KEY_DEFAULT);
    const set = O.setImKey(CONFIG, "Control+Shift+space");
    t.eq("switch key set", O.parseImKey(set), "Control+Shift+space");
    t.eq("the rest of config kept", /ShareInputState=No/.test(set) && /EnumerateWithTriggerKeys=True/.test(set), true);
    t.eq("section added when missing", O.parseImKey(O.setImKey("[Behavior]\nA=1\n", "Super+Shift+space")), "Super+Shift+space");
    t.eq("text tray icon from nothing", O.imClassicUi(""), "PreferTextIcon=True\n");
    const cu = O.imClassicUi("Vertical Candidate List=False\nPreferTextIcon=False\nFont=\"Sans 10\"\n");
    t.eq("text tray icon replaces, keeps the rest", cu,
      "Vertical Candidate List=False\nPreferTextIcon=True\nFont=\"Sans 10\"\n");
    t.eq("a key added to a section", O.setIniKey("[A]\nx=1\n\n[B]\ny=2\n", "A", "z", "3"), "[A]\nx=1\nz=3\n\n[B]\ny=2\n");
    t.eq("every key offered is not Super+Space", O.IM_KEYS.every((k) => k.value !== "Super+space"), true);

    const root = path.resolve(__dirname, "../../..");
    const bad = [];
    for (const f of walk(root, "", [])) {
      fs.readFileSync(path.join(root, f), "utf8").split("\n").forEach((l, i) => {
        const code = l.replace(/(\/\/|--|#).*$/, "");
        if (/\b(GTK_IM_MODULE|QT_IM_MODULE)\b/.test(code)) bad.push(f + ":" + (i + 1));
      });
    }
    t.eq("no GTK_IM_MODULE or QT_IM_MODULE in the shipped config", bad.join("\n    "), "");
  },
};

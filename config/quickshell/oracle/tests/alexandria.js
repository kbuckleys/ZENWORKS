// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ALEXANDRIA'S LIBRARY: families out of fontconfig, a charset as an index,
// the names and the search, and the install/remove shell text.

"use strict";

const fs = require("fs");
const path = require("path");
const vm = require("vm");

// oracle's familyOf, the real one — Alexandria folds families by it
function oracleFamilyOf() {
  const src = fs.readFileSync(path.resolve(__dirname, "../oracle.js"), "utf8");
  const ctx = vm.createContext({ console });
  vm.runInContext(src.replace(/^\.pragma library$/m, ""), ctx);
  return ctx.familyOf;
}

const HOME = "/home/test";
const LIST = [
  "JetBrainsMono Nerd Font\tRegular\t/usr/share/fonts/TTF/JBM-Regular.ttf\t80\t0\t100\tTrueType\t0",
  "JetBrainsMono Nerd Font\tSemiBold\t/usr/share/fonts/TTF/JBM-SemiBold.ttf\t180\t0\t100\tTrueType\t0",
  "JetBrainsMono Nerd Font Propo\tRegular\t/usr/share/fonts/TTF/JBMP-Regular.ttf\t80\t0\t\tTrueType\t0",
  "JetBrainsMono Nerd Font\tItalic\t/usr/share/fonts/TTF/JBM-Italic.ttf\t80\t100\t100\tTrueType\t0",
  "SF Pro Display\tLight\t/usr/share/fonts/apple/SF-Pro-Display-Light.otf\t50\t0\t\tCFF\t0",
  "SF Pro Display\tLight\t/usr/share/fonts/apple/SF-Pro-Display-Light.otf\t50\t0\t\tCFF\t0",
  "Mine Sans,Mine Sans Alt\tBold,Fett\t/home/test/.local/share/fonts/Mine-Bold.ttf\t200\t0\t\tTrueType\t0",
  "",
  "broken line",
].join("\n");

module.exports = {
  module: "alexandria/alexandria.js",
  cases: (A, t) => {
    const fams = A.parseList(LIST, HOME, oracleFamilyOf());
    t.eq("families, folded and sorted", fams.map((f) => f.name),
      ["JetBrainsMono Nerd Font", "Mine Sans", "SF Pro Display"]);
    const jbm = fams[0];
    t.eq("the Propo cut joins its family", jbm.variants, ["JetBrainsMono Nerd Font", "JetBrainsMono Nerd Font Propo"]);
    t.eq("styles lightest first, upright before italic, plain cut first",
      jbm.styles.map((s) => s.family + "/" + s.style),
      ["JetBrainsMono Nerd Font/Regular", "JetBrainsMono Nerd Font Propo/Regular",
       "JetBrainsMono Nerd Font/Italic", "JetBrainsMono Nerd Font/SemiBold"]);
    t.ok("monospaced and nerd", jbm.mono && jbm.nerd && jbm.system && !jbm.user);
    t.eq("a face listed twice is one style", fams[2].styles.length, 1);
    t.ok("SF is proportional", !fams[2].mono);
    t.ok("a file under ~/.local/share/fonts is the user's", fams[1].user && !fams[1].system);
    t.eq("first names only", fams[1].styles[0].style, "Bold");
    t.eq("weights as CSS", [0, 40, 50, 80, 100, 180, 200, 205, 210].map(A.cssWeight),
      [100, 200, 300, 400, 500, 600, 700, 800, 900]);
    t.eq("the style nearest SemiBold", jbm.styles[A.styleNear(jbm, 600, false)].style, "SemiBold");
    t.eq("the cut is named", A.styleLabel(jbm, jbm.styles[1]), "Regular  ·  Propo");

    t.eq("shelves: mono", A.shelve(fams, "mono", "", {}).map((f) => f.name), ["JetBrainsMono Nerd Font"]);
    t.eq("shelves: bookmarks", A.shelve(fams, "fav", "", { "SF Pro Display": true }).length, 1);
    t.eq("words in any order", A.shelve(fams, "all", "display sf", {}).map((f) => f.name), ["SF Pro Display"]);
    t.eq("san francisco finds SF", A.shelve(fams, "all", "san francisco", {}).map((f) => f.name), ["SF Pro Display"]);
    t.eq("so does the directory it lives in", A.shelve(fams, "all", "apple", {}).map((f) => f.name), ["SF Pro Display"]);
    t.eq("a variant's name finds it", A.shelve(fams, "all", "propo", {}).length, 1);
    t.eq("counts", A.shelfCount(fams, "user", {}), 1);

    const ix = A.parseCharset("20-7e a0 f031 f0001-f0003 junk");
    t.eq("charset count", ix.count, 95 + 1 + 1 + 3);
    t.eq("cell 0 is space", A.codeAt(ix, 0), 0x20);
    t.eq("cell 95 is nbsp", A.codeAt(ix, 95), 0xa0);
    t.eq("the last cell", A.codeAt(ix, ix.count - 1), 0xf0003);
    t.eq("out of range", A.codeAt(ix, ix.count), -1);
    t.eq("position of a codepoint", A.posOf(ix, 0xf031), 96);
    t.ok("covers", A.covers(ix, 0x41) && !A.covers(ix, 0x7f));
    t.eq("an index of a list joins runs", A.indexOfList([1, 2, 3, 7]).ranges, [[1, 3], [7, 7]]);

    t.eq("hex is padded", A.uplus(0x41), "U+0041");
    t.eq("astral escapes use braces", A.spellings(0xF0001, "md-x")[2].text, "\\u{F0001}");
    t.eq("bmp escapes don't", A.spellings(0xF031, "")[2].text, "\\uF031");
    t.eq("nerd name spelled", A.spellings(0xF031, "fa-font")[4].text, "nf-fa-font");

    const uni = A.parseUnicodeData([
      "0009;<control>;Cc;0;S;;;;;N;CHARACTER TABULATION;;;;",
      "0041;LATIN CAPITAL LETTER A;Lu;0;L;;;;;N;;;;0061;",
      "4E00;<CJK Ideograph, First>;Lo;0;L;;;;;N;;;;;",
      "9FFF;<CJK Ideograph, Last>;Lo;0;L;;;;;N;;;;;",
    ].join("\n"));
    t.eq("a plain name", A.unicodeName(0x41, uni), "LATIN CAPITAL LETTER A");
    t.eq("a control's old name", A.unicodeName(9, uni), "CHARACTER TABULATION");
    t.eq("a CJK ideograph by number", A.unicodeName(0x4E01, uni), "CJK IDEOGRAPH-4E01");
    const nerd = A.parseNerdNames(JSON.stringify({ METADATA: {}, "fa-font": { char: "", code: "f031" },
                                                   "md-folder_open": { char: "", code: "f0002" } }));
    t.eq("nerd names by codepoint", nerd[0xf031], ["fa-font"]);
    t.eq("nerd first, unicode lowercased", [A.glyphName(0xf031, uni, nerd), A.glyphName(0x41, uni, nerd)],
      ["fa-font", "latin capital letter a"]);
    t.eq("bad json is no names", Object.keys(A.parseNerdNames("{")).length, 0);

    t.eq("search by codepoint", A.searchGlyphs(ix, "U+F031", uni, nerd), [0xf031]);
    t.eq("search by bare hex", A.searchGlyphs(ix, "f031", uni, nerd), [0xf031]);
    t.eq("search by the character", A.searchGlyphs(ix, "\u{F0001}", uni, nerd), [0xf0001]);
    t.eq("search by words", A.searchGlyphs(ix, "folder open", uni, nerd), [0xf0002]);
    t.eq("nf- prefix is ignored", A.searchGlyphs(ix, "nf-fa-font", uni, nerd), [0xf031]);
    t.eq("words reach unicode names", A.searchGlyphs(ix, "capital a", uni, nerd), [0x41]);
    t.eq("only what the face has", A.searchGlyphs(ix, "U+4E01", uni, nerd), []);

    const blocks = A.parseBlocks("0000..007F; Basic Latin\n0080..00FF; Latin-1 Supplement\nE000..F8FF; Private Use Area\nF0000..FFFFF; Supplementary Private Use Area-A\n# x");
    t.eq("blocks", blocks.length, 4);
    const groups = A.groupsOf(ix, blocks);
    t.eq("groups: blocks, and nerd sets inside the private use area", groups.map((g) => g.name + ":" + g.count),
      ["Basic Latin:95", "Latin-1 Supplement:1", "Font Awesome:1", "Material Design:3"]);
    t.eq("a group's own index", A.groupIndex(ix, groups[3]).count, 3);
    t.eq("block of a nerd icon", A.blockName(0xf031, blocks), "Font Awesome");

    t.match("install copies into the user's directory", A.installCommand(["/x/a.ttf"], HOME), /d='\/home\/test\/\.local\/share\/fonts'/);
    t.match("and tells fontconfig", A.installCommand(["/x/a.ttf"], HOME), /fc-cache -f/);
    t.eq("system fonts are never removed", A.removeCommand(["/usr/share/fonts/a.ttf"], HOME), "exit 1\n");
    t.match("the user's go to the trash", A.removeCommand(["/home/test/.local/share/fonts/a.ttf"], HOME), /gio trash/);
    const latinIx = A.indexOf([[0x20, 0x7e]]);
    t.eq("a Latin face is shown in Latin only", A.scriptsOf(latinIx).map((s) => s.id), ["latin"]);
    const greekIx = A.indexOf([[0x20, 0x7e], [0x370, 0x3ff]]);
    t.eq("Greek offered once it has every letter", A.scriptsOf(greekIx).map((s) => s.id), ["latin", "greek"]);
    t.eq("half an alphabet is no script", A.hasScript(A.indexOf([[0x391, 0x3a9]]), A.scriptOf("greek")), false);
    t.eq("an unknown script is Latin", A.scriptOf("klingon").id, "latin");
    t.eq("no charset, no scripts", A.scriptsOf(A.indexOf([])).length, 0);
    t.ok("font files", A.isFontFile("a.TTF") && A.isFontFile("b.woff2") && !A.isFontFile("c.txt"));
  }
};

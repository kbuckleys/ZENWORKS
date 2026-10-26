// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// hypr/lua/windows.lua and startup.lua: Oracle's Windows section, written
// and read back — a hand edit must survive the round trip.

"use strict";

module.exports = {
  module: "oracle/oracle.js",
  cases: (O, t) => {
    const r = Object.assign(O.blankWindowRule("steam", "Steam"),
      { float: true, size: "1200 800", center: true, workspace: "3", silent: true, opacity: 90 });
    const back = O.parseWindowsLua(O.renderWindowsLua([r]));
    t.eq("rule round trip", back, [r]);
    const picked = O.windowPickRows([
      { class: "org.quickshell", title: "terminus", initialTitle: "terminus" },
      { class: "org.quickshell", title: "plato", initialTitle: "plato" },
      { class: "org.quickshell", title: "terminus", initialTitle: "terminus" },
      { class: "firefox", title: "One tab" }, { class: "firefox", title: "Another" }],
      [{ class: "org.quickshell", title: "terminus", name: "Terminus" }], (c) => c);
    t.eq("suite windows a row each, others one per app", picked.map((p) => [p.name, p.pin]),
      [["firefox", ""], ["Plato", "plato"], ["Terminus", "terminus"]]);
    t.eq("a picked suite window keeps its title", O.blankWindowRule("org.quickshell", "Plato", "plato").title, "plato");
    t.eq("quotes survive", O.parseWindowsLua(O.renderWindowsLua([O.blankWindowRule("a\"b", "x\\y")]))[0].class, "a\"b");
    t.eq("a comment is not a rule", O.parseWindowsLua("-- { class = \"x\" }\nreturn {\n}"), []);
    t.eq("no class, no rule", O.parseWindowsLua("return { { name = \"x\" } }"), []);
    t.eq("hand edit, missing fields filled", O.parseWindowsLua("return {\n{ class = \"mpv\", float = true, opacity = 300 },\n}")[0].opacity, 100);
    t.eq("a bad size is dropped", O.parseWindowsLua("return { { class = \"a\", size = \"big\" } }")[0].size, "");
    t.eq("a bad workspace is dropped", O.parseWindowsLua("return { { class = \"a\", workspace = \"3; rm\" } }")[0].workspace, "");
    t.eq("words", O.windowRuleWords(r), "Floats 1200×800, centered · workspace 3, quietly · 90% opaque");
    t.eq("words, nothing", O.windowRuleWords(O.blankWindowRule("a")), "does nothing yet");
    t.eq("summary", [O.windowRulesSummary([]), O.windowRulesSummary([r, Object.assign({}, r, { on: false })])],
      ["none", "2 rules · 1 off"]);
    t.eq("summary with shipped", O.windowRulesSummary([], [O.blankWindowRule("a")].map((d) => Object.assign(d, { shipped: "a" }))), "1 shipped");

    const s = [{ name: "Discord", command: "discord --start-minimized", on: true, delay: 5 },
               { name: "Syncthing", command: "syncthing serve --no-browser", on: false, delay: 0 }];
    t.eq("startup round trip", O.parseStartupLua(O.renderStartupLua(s)), s);
    t.eq("startup delay clamped", O.parseStartupLua("return { { command = \"x\", delay = 9999 } }")[0].delay, 600);
    t.eq("startup empty command dropped", O.parseStartupLua("return { { command = \"  \" } }"), []);
    t.eq("startup look", [O.startupLook("env GDK_SCALE=2 /usr/bin/discord --x"), O.startupLook("flatpak run com.spotify.Client"),
                          O.startupLook("sh -c 'sleep 2; foo'")], ["discord", "com.spotify.Client", "sleep"]);
    t.eq("startup running", [O.startupRunning("/usr/bin/discord --x\nps -eo args=", "discord"),
                             O.startupRunning("grep discord", "discord"), O.startupRunning("", "")], [true, false, false]);
    t.eq("exec field codes", ["/usr/bin/discord --url -- %U", "spotify --uri=%U", "mpv --player-operation-mode=pseudo-gui -- %U", "kitty", "steam %U --silent"].map(O.execForStartup),
      ["/usr/bin/discord", "spotify", "mpv", "kitty", "steam --silent"]);
    t.eq("braces in a string are text", O.parseStartupLua(O.renderStartupLua([{ name: "Loop", command: "sh -c 'for i in {1..3}; do x; done'", on: true, delay: 0 }]))[0].command,
      "sh -c 'for i in {1..3}; do x; done'");
    t.eq("a title with braces survives", O.parseWindowsLua(O.renderWindowsLua([Object.assign(O.blankWindowRule("a"), { title: "{draft} }{" })]))[0].title, "{draft} }{");
    t.eq("a field inside a string is not the field", O.parseStartupLua("return { { command = \"x on = false\" } }")[0].on, true);
    t.eq("per-launch class tail dropped", [O.stableClass("com.transmissionbt.transmission_66307_44306163"), O.stableClass("steam"), O.stableClass("app_2")],
      ["com.transmissionbt.transmission", "steam", "app_2"]);
    t.eq("a read rule loses the tail, its name too", (() => { const x = O.parseWindowsLua("return { { name = \"t_1_2\", class = \"t_1_2\" } }")[0]; return [x.name, x.class]; })(), ["t", "t"]);
    t.eq("pinned only when floating", O.windowRuleWords(Object.assign(O.blankWindowRule("a"), { pin: true })), "does nothing yet");
    t.eq("remembered size only when floating", O.windowRuleWords(Object.assign(O.blankWindowRule("a"), { persistent_size: true })), "does nothing yet");
    t.eq("remembered size floating", O.windowRuleWords(Object.assign(O.blankWindowRule("a"), { float: true, persistent_size: true })), "Floats · remembers its size");
    t.eq("persistent_size round-trips", O.parseWindowsLua(O.renderWindowsLua([Object.assign(O.blankWindowRule("a"), { float: true, persistent_size: true })]))[0].persistent_size, true);
    t.eq("an old rule without it reads false", O.normWindowRule({ class: "a" }).persistent_size, false);
    t.eq("a shell keyword is not looked for", O.startupLook("sh -c 'for i in 1 2; do foo; done'"), "");
    t.eq("startup name", O.startupName("discord --start-minimized"), "Discord");

    // the suite's own rules, listed beside yours (2026-10-24)
    const ship = O.parseWindowDefaults("-- x\nreturn {\n\t{ shipped = \"mpv\", name = \"mpv\", class = \"mpv\", float = true },\n\t{ name = \"no id\", class = \"x\" },\n}");
    t.eq("a default needs its shipped name", ship.map((d) => d.shipped), ["mpv"]);
    const mine = [O.blankWindowRule("steam", "Steam")];
    t.eq("yours first, then shipped", O.windowRuleRows(ship, mine).map((w) => [w.rule.class, w.shipped, w.changed]),
      [["steam", "", false], ["mpv", "mpv", false]]);
    const changed = O.windowRulesPatched(ship, mine, 1, { on: false });
    t.eq("changing a shipped rule adds a stand-in", changed.map((r) => [r.class, r.shipped, r.on]),
      [["steam", "", true], ["mpv", "mpv", false]]);
    t.eq("the stand-in shows in its place", O.windowRuleRows(ship, changed).map((w) => [w.shipped, w.changed, w.rule.on]),
      [["", false, true], ["mpv", true, false]]);
    t.eq("changed back, the stand-in goes", O.windowRulesPatched(ship, changed, 1, { on: true }).length, 1);
    t.eq("removing a shipped rule resets it", O.windowRulesRemoved(ship, changed, 1).map((r) => r.class), ["steam"]);
    t.eq("removing yours deletes it", O.windowRulesRemoved(ship, changed, 0).map((r) => r.shipped), ["mpv"]);
    t.eq("a stand-in round-trips", O.parseWindowsLua(O.renderWindowsLua(changed)).map((r) => r.shipped), ["", "mpv"]);
    t.eq("yours write no empty shipped", O.renderWindowsLua(mine).indexOf("shipped"), -1);
    t.eq("an orphan stand-in is yours", O.windowRuleRows([], changed).map((w) => w.shipped), ["", ""]);
  }
};

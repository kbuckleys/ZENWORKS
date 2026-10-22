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
    t.eq("startup name", O.startupName("discord --start-minimized"), "Discord");
  }
};

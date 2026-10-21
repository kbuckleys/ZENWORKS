// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// hermes' pretend machine (HERMES_FAKE): every scenario is a whole state,
// and every action leaves a state the panel can still read.

"use strict";

module.exports = {
  module: "hermes/fake.js",
  cases: (F, t) => {
    for (const name of F.SCENARIOS) {
      const s = F.scenario(name);
      t.eq(name + " is itself", s.name, name);
      t.ok(name + " has a probe with links", Array.isArray(s.probe.links) && s.probe.links.length > 0);
    }
    t.eq("an unknown scenario is the full one", F.scenario("nope").name, "full");

    const full = F.scenario("full");
    t.eq("full is a mixed machine", full.probe.stacks, ["networkd", "nm"]);
    t.eq("full: the wired link is networkd's", full.probe.links[0].managedBy, "networkd");
    t.eq("full: wi-fi is NetworkManager's", full.probe.links[1].managedBy, "nm");
    t.eq("full: a device with a battery", full.devices[0].battery, 0.8);
    t.eq("wired has no wi-fi", F.scenario("wired").probe.wifiHw, false);
    t.eq("stuck: BlueZ has no controller", F.scenario("stuck").probe.bt.controllers, 0);
    t.eq("stopped: installed, not running", [F.scenario("stopped").probe.bt.installed, F.scenario("stopped").probe.bt.running], [true, false]);

    // wi-fi
    let r = F.act(full, "join", "ZenOpen");
    t.eq("joining moves the connection", r.state.networks.filter((n) => n.connected).map((n) => n.name), ["ZenOpen"]);
    t.eq("…and remembers it", r.state.networks.find((n) => n.name === "ZenOpen").known, true);
    t.eq("the state handed in is untouched", full.networks[1].connected, false);
    r = F.act(full, "join", "Neighbours 5G", "wrong");
    t.eq("a wrong password asks again", r.ask, true);
    t.eq("…and leaves the old connection", r.state.networks[0].connected, true);
    r = F.act(full, "wifiPower", "", false);
    t.eq("wi-fi off drops the connection", r.state.networks.some((n) => n.connected), false);
    t.eq("…and the link", r.state.probe.links[1].up, false);
    r = F.act(full, "forget", "ZenTest");
    t.eq("forgetting", [r.state.networks[0].known, r.state.networks[0].connected], [false, false]);

    // bluetooth
    r = F.act(full, "scan", "", true);
    t.eq("a search finds the keyboard", r.state.devices.some((d) => d.name === "Keychron K3"), true);
    t.eq("…once", F.act(r.state, "scan", "", true).state.devices.filter((d) => d.name === "Keychron K3").length, 1);
    r = F.act(full, "devPair", "Pixel 8");
    t.eq("pairing connects", [r.state.devices[2].paired, r.state.devices[2].connected], [true, true]);
    r = F.act(full, "devConnect", "5A:21:00:00:00:04");
    t.eq("an unpaired device does not connect", r.state.devices[3].connected, false);
    r = F.act(full, "btPower", "", false);
    t.eq("bluetooth off drops every device", r.state.devices.some((d) => d.connected), false);

    // vpn
    r = F.act(full, "vpn", "Work");
    t.eq("up", r.state.probe.vpn[0].active, true);
    r = F.act(r.state, "vpn", "Home");
    t.eq("one at a time", r.state.probe.vpn.map((v) => v.active), [false, true]);
    t.has("said", r.said, "Connected to Home");

    // brightness
    r = F.act(full, "brightness", "bl:intel_backlight", 30);
    t.eq("the backlight", r.state.probe.display.backlight[0].cur, 30);
    r = F.act(full, "brightness", "ddc:4", 80);
    t.eq("a monitor", r.state.ddc[0].cur, 80);

    // setup
    r = F.act(F.scenario("bare"), "setup", "bluetooth");
    t.eq("bluetooth set up", [r.state.probe.bt.running, r.state.bt.present], [true, true]);
    r = F.act(F.scenario("bare"), "setup", "networkmanager");
    t.eq("networkmanager set up", r.state.probe.nm.running, true);
    r = F.act(F.scenario("wired"), "setup", "hyprsunset");
    t.eq("hyprsunset set up", r.state.probe.display.hyprsunset, true);
  }
};

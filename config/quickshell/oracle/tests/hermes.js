// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The pure half of hermes: the probe read, the words and glyphs for links,
// networks and devices, ddcutil's output, the night light's range, and the
// Ceres jobs that set a missing piece up.

"use strict";

module.exports = {
  module: "hermes/hermes.js",
  cases: (H, t) => {
    // ── the probe ─────────────────────────────────────────────────────────
    const blank = H.parseProbe("not json");
    t.eq("a broken probe is the empty one", blank.known, false);
    t.eq("…with every field there", Array.isArray(blank.links) && !!blank.display && !!blank.bt, true);

    const p = H.parseProbe(JSON.stringify({
      stack: "networkd", nm: { installed: false, running: false },
      links: [
        { name: "enp7s0", kind: "wired", up: true, carrier: true, speed: 1000, mac: "aa", ipv4: ["192.168.1.172/24"], ipv6: [], gateway: "192.168.1.1" },
        { name: "wlan0", kind: "wifi", up: false, carrier: false, speed: 0 },
        { kind: "wired" }
      ],
      dns: ["1.1.1.1"], wifiHw: true, bt: { hw: false },
      vpn: [{ name: "wg0", type: "wireguard", active: true, managed: false }, { type: "vpn" }],
      display: { backlight: [{ name: "intel", cur: 50, max: 100 }, { name: "bad", max: 0 }], hyprsunset: true }
    }));
    t.eq("the probe is known", p.known, true);
    t.eq("a link without a name is dropped", p.links.length, 2);
    t.eq("the wired link is the one with a carrier", H.wiredLink(p).name, "enp7s0");
    t.eq("a nameless vpn is dropped", p.vpn.length, 1);
    t.eq("a backlight with no range is dropped", p.display.backlight.length, 1);
    t.eq("ddcutil defaults to missing", p.display.ddcutil, false);
    t.eq("the stack in words", H.stackWords(p.stack), "systemd-networkd");
    t.eq("an unknown stack in words", H.stackWords(""), "nothing Hermes knows");

    // ── a mixed machine ──
    const mixed = H.parseProbe(JSON.stringify({ stack: "networkd", stacks: ["networkd", "nm"],
      links: [{ name: "enp7s0", kind: "wired", managedBy: "networkd" }, { name: "wlan1", kind: "wifi", managedBy: "nm" }] }));
    t.eq("both stacks named", H.stacksWords(mixed), "systemd-networkd and NetworkManager");
    t.eq("the wired link's own", H.linkStack(mixed, mixed.links[0]), "systemd-networkd");
    t.eq("the wi-fi link's own", H.linkStack(mixed, mixed.links[1]), "NetworkManager");
    t.eq("short, for the sidebar", H.stacksShort(mixed), "networkd + NetworkManager");
    t.eq("an older probe without stacks", H.stacksWords(H.parseProbe('{"stack":"nm"}')), "NetworkManager");

    // ── a bluetooth adapter that never reached BlueZ ──
    const stuck = H.parseProbe(JSON.stringify({ bt: { hw: true, installed: true, running: true, controllers: 0 } }));
    t.eq("an adapter BlueZ never got is stuck", H.btStuck(stuck), true);
    t.eq("unknown controller count is not stuck", H.btStuck(H.parseProbe(JSON.stringify({ bt: { hw: true, running: true } }))), false);
    t.eq("one controller is not stuck", H.btStuck(H.parseProbe(JSON.stringify({ bt: { hw: true, running: true, controllers: 1 } }))), false);

    // ── speed ─────────────────────────────────────────────────────────────
    t.eq("gigabit", H.speedWords(1000), "1 Gb/s");
    t.eq("2.5 gigabit", H.speedWords(2500), "2.5 Gb/s");
    t.eq("fast ethernet", H.speedWords(100), "100 Mb/s");
    t.eq("no speed", H.speedWords(-1), "");

    // ── wi-fi ─────────────────────────────────────────────────────────────
    t.eq("no signal is no bars", H.wifiBars(0), 0);
    t.eq("a weak signal is one bar", H.wifiBars(0.1), 1);
    t.eq("full signal is four", H.wifiBars(1), 4);
    t.eq("a percentage is read as one", H.wifiBars(80), 4);
    t.eq("WPA3 by its name", H.securityWords("Sae"), "WPA3");
    t.eq("an open network", H.securityWords("Open"), "Open");
    t.eq("enterprise", H.securityWords("Wpa2Eap"), "Enterprise");
    t.eq("WPA2 asks for a passphrase", H.needsPassphrase("Wpa2Psk"), true);
    t.eq("enterprise does not (its own dialog)", H.needsPassphrase("Wpa2Eap"), false);
    t.eq("open does not", H.needsPassphrase("Open"), false);

    const nets = H.sortNetworks([
      { name: "Far", strength: 0.2 },
      { name: "Home", strength: 0.5, known: true },
      { name: "Cafe", strength: 0.9 },
      { name: "Home", strength: 0.8, known: true },
      { name: "Here", strength: 0.3, connected: true },
      { name: "" }
    ]);
    t.eq("connected, then saved, then by signal", nets.map((n) => n.name), ["Here", "Home", "Cafe", "Far"]);
    t.eq("one row per name, the strongest kept", nets[1].strength, 0.8);

    // ── bluetooth ─────────────────────────────────────────────────────────
    t.eq("headset glyph", H.btGlyph("audio-headset"), "\u{F02CB}");
    t.eq("keyboard glyph", H.btGlyph("input-keyboard"), "\u{F030C}");
    t.eq("unknown is the rune", H.btGlyph(""), H.G.bt);
    t.eq("battery as a fraction", H.batteryWords(0.8), "80%");
    t.eq("battery as a percentage", H.batteryWords(55), "55%");
    t.eq("no battery", H.batteryWords(-1), "");
    const devs = H.sortDevices([
      { name: "B", named: true },
      { name: "00:11", named: false },
      { name: "A", paired: true, named: true },
      { name: "Z", connected: true, paired: true, named: true }
    ]);
    t.eq("connected, paired, named, unnamed", devs.map((d) => d.name), ["Z", "A", "B", "00:11"]);

    // ── ddcutil ───────────────────────────────────────────────────────────
    const det = H.parseDdcDetect([
      "Display 1",
      "   I2C bus:  /dev/i2c-4",
      "   DRM connector:           card1-DP-1",
      "   Monitor:                 DEL:DELL U2720Q:ABC123",
      "",
      "Invalid display",
      "   I2C bus:  /dev/i2c-6",
      "   DRM connector:           card1-HDMI-A-1",
      "",
      "Display 2",
      "   I2C bus:  /dev/i2c-7",
      "   DRM_connector:           card0-DP-2",
      "   Monitor:                 GSM:LG ULTRAGEAR:",
    ].join("\n"));
    t.eq("two displays answer DDC", det.length, 2);
    t.eq("the bus", det[0].bus, 4);
    t.eq("the connector, without the card", det[0].connector, "DP-1");
    t.eq("the model", det[0].model, "DELL U2720Q");
    t.eq("an older ddcutil's DRM_connector", det[1].connector, "DP-2");
    t.eq("vcp read", H.parseVcp("VCP 10 C 50 100"), { cur: 50, max: 100 });
    t.eq("vcp failed", H.parseVcp("Display not found"), null);
    t.eq("percent", H.percent(30, 120), 25);

    // ── night light ───────────────────────────────────────────────────────
    t.eq("clamped low", H.clampKelvin(1000), 2500);
    t.eq("clamped high", H.clampKelvin(9000), 6500);
    t.eq("rounded to 50", H.clampKelvin(4021), 4000);
    t.eq("words", H.kelvinWords(3500), "3500 K");
    t.eq("by hand", H.nightWanted(true, false, true), true);
    t.eq("by the sun, by day", H.nightWanted(true, true, true), false);
    t.eq("by the sun, by night", H.nightWanted(false, true, false), true);

    // ── setup jobs ────────────────────────────────────────────────────────
    t.eq("bluetooth installs bluez", H.setupOf("bluetooth").pkgs, ["bluez", "bluez-utils"]);
    t.eq("…and starts its service as root", H.setupOf("bluetooth").after[0].slice(0, 2), ["@sudo", "systemctl"]);
    t.has("ddcutil loads i2c-dev at boot", H.setupOf("ddcutil").after[0][3], "/etc/modules-load.d/i2c-dev.conf");
    t.has("networkmanager turns networkd off", H.setupOf("networkmanager").after[0][3], "disable --now systemd-networkd");
    t.has("…and NetworkManager on", H.setupOf("networkmanager").after[0][3], "enable --now NetworkManager");
    t.eq("an unknown setup", H.setupOf("nope"), null);
    t.eq("printing installs cups and finds printers", H.setupOf("printing").pkgs.slice(0, 2), ["cups", "cups-filters"]);
    t.has("…and starts the socket as root", H.setupOf("printing").after[0].join(" "), "enable --now cups.socket");
    t.eq("scanning installs sane-airscan", H.setupOf("scanning").pkgs.indexOf("sane-airscan") >= 0, true);

    // ── printers ──────────────────────────────────────────────────────────
    t.eq("a broken print answer is the empty one", H.parsePrint("x").known, false);
    const pr = H.parsePrint(JSON.stringify({
      cups: { installed: true, running: true }, sane: { installed: false },
      printers: [
        { name: "Zed", info: "Zed office", state: "idle", reasons: [], default: false, jobs: 0, uri: "ipp://z" },
        { name: "Brother", info: "Brother HL", state: "printing", reasons: ["toner-low-report"], default: true, jobs: 2 },
        { info: "nameless" }
      ],
      jobs: [{ id: "Brother-12", printer: "Brother", size: 1024 }, { printer: "x" }]
    }));
    t.eq("a nameless printer is dropped", pr.printers.length, 2);
    t.eq("the default printer first", pr.printers[0].name, "Brother");
    t.eq("a nameless job is dropped", pr.jobs.length, 1);
    t.eq("a printer in words", H.printerWords(pr.printers[0]), "Printing · Toner low · 2 jobs");
    t.eq("an idle printer in words", H.printerWords(pr.printers[1]), "Ready");
    t.eq("a paused one says so once", H.printerWords({ state: "stopped", reasons: ["paused"], jobs: 0 }), "Paused");
    t.eq("a printer wanting something wears the alert", H.printerGlyph(pr.printers[0]), H.G.printerAlert);
    t.eq("an unknown reason is not said", H.reasonWords(["other", "none"]), "");
    t.eq("a scan's name sorts by when", H.scanFileName(new Date(2026, 9, 2, 9, 5, 7), "png"), "Scan 2026-10-02 09.05.07.png");
    t.eq("…as a PDF", H.scanFileName(new Date(2026, 9, 2, 9, 5, 7), "pdf").slice(-4), ".pdf");
    t.eq("an action that worked", H.parseAct('{"ok":true,"error":"","admin":false}').ok, true);
    t.eq("an action CUPS refused for want of root", H.parseAct('{"ok":false,"error":"Forbidden","admin":true}').admin, true);
    t.eq("no answer is a failure", H.parseAct("").ok, false);
    t.eq("found devices keep only those with an address", H.parseDevices('{"ok":true,"devices":[{"uri":"a"},{}]}').devices.length, 1);
    t.eq("a nearby printer already added", H.alreadyAdded({ uri: "ipp://z" }, pr.printers), true);

    // ── the bar ───────────────────────────────────────────────────────────
    t.eq("the bar wears hermes' own glyph", H.barGlyphs(p, {})[0].glyph, "\u{F1542}");
    t.eq("one glyph, whatever else is connected", H.barGlyphs(p, { btConnected: 1, vpnActive: "wg0" }).length, 1);
    t.eq("wired up is ok", H.barGlyphs(p, {})[0].role, "ok");
    const wifiOnly = H.parseProbe(JSON.stringify({ links: [{ name: "wlan0", kind: "wifi" }], wifiHw: true }));
    t.eq("wi-fi off is off", H.barGlyphs(wifiOnly, { wifiOn: false })[0].role, "off");
    t.eq("wi-fi joined is ok", H.barGlyphs(wifiOnly, { wifiNet: { name: "x", strength: 0.6 } })[0].role, "ok");
    t.eq("no link at all is down", H.barGlyphs(H.parseProbe('{"links":[]}'), {})[0].role, "down");
    t.has("the tooltip names the link", H.barWords(p, {}), "enp7s0 · 1 Gb/s");
    t.has("…and the address, without its prefix", H.barWords(p, {}).split("\n")[1], "192.168.1.172");
    t.eq("…exactly", H.barWords(p, {}).split("\n")[1], "192.168.1.172");
    t.has("…night light", H.barWords(p, { night: true, kelvin: 3400 }), "Night light · 3400 K");
    t.has("a network name is escaped", H.barWords(wifiOnly, { wifiNet: { name: "<b>", strength: 1 } }), "&lt;b&gt;");

    // ── settings ──────────────────────────────────────────────────────────
    t.eq("no file is the defaults", H.parseSettings(""), H.defaults());
    const s = H.parseSettings(JSON.stringify({ nightOn: true, kelvin: 99999, section: "vpn" }));
    t.eq("kelvin clamped on read", s.kelvin, 6500);
    t.eq("section kept", s.section, "vpn");
    t.eq("an unknown section is the default", H.parseSettings('{"section":"x"}').section, "network");
    t.eq("round trip", H.parseSettings(H.serializeSettings(s)), s);
  }
};

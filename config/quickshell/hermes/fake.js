// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

.pragma library
// ONE COPY FOR THE WHOLE SHELL (see morpheus/icons.js).
//
// HERMES, PRETENDING. With HERMES_FAKE=<scenario> in the environment the
// Hermes singleton reads everything from here instead of the probe,
// NetworkManager and BlueZ — for the offscreen harness and for looking at
// states this machine cannot reach (no Wi-Fi, no adapter, a service off).
// Nothing in the shipped shell sets it.
//
//   scenario(name)              a whole machine: { probe, wifiOn, networks,
//                               bt, devices, ddc }
//   act(state, what, name, arg) the state after doing `what`, plus what to
//                               say: { state, said, bad, ask }
//
// Pure, so oracle/tests/hermes-fake.js runs every action.

var SCENARIOS = ["full", "wired", "bare", "stopped", "stuck", "off"];

function clone(x) { return JSON.parse(JSON.stringify(x)); }

function wiredLink(managedBy) {
  return { name: "enp7s0", kind: "wired", up: true, carrier: true, speed: 1000, mac: "b4:2e:99:00:00:01",
           ipv4: ["192.168.1.172/24"], ipv6: ["fd00::172/64"], gateway: "192.168.1.1", managedBy: managedBy };
}
function wifiLink(up) {
  return { name: "wlan1", kind: "wifi", up: up, carrier: up, speed: 0, mac: "02:00:00:00:01:00",
           ipv4: up ? ["10.42.0.57/24"] : [], ipv6: [], gateway: up ? "10.42.0.1" : "", managedBy: "nm" };
}

function scenario(name) {
  var n = SCENARIOS.indexOf(name) >= 0 ? name : "full";
  var s = {
    name: n,
    probe: {
      known: true, stack: "networkd", stacks: ["networkd"],
      nm: { installed: false, running: false },
      links: [wiredLink("networkd")], dns: ["1.1.1.1", "192.168.1.1"], wifiHw: false,
      bt: { hw: false, installed: false, running: false, controllers: -1 },
      rfkill: { wifi: null, bt: null }, vpn: [],
      display: { backlight: [], ddcutil: false, i2c: false, hyprsunset: false, sunsetRunning: false }
    },
    wifiOn: false, networks: [],
    bt: { present: false, name: "", enabled: false, discovering: false, discoverable: false },
    devices: [], ddc: []
  };
  if (n === "wired") return s;
  if (n === "bare") {
    s.probe.wifiHw = true;
    s.probe.links.push(wifiLink(false));
    s.probe.links[1].managedBy = "";
    s.probe.bt.hw = true;
    return s;
  }
  if (n === "stopped") {
    s.probe.wifiHw = true;
    s.probe.links.push(wifiLink(false));
    s.probe.links[1].managedBy = "";
    s.probe.bt = { hw: true, installed: true, running: false, controllers: -1 };
    s.probe.display.ddcutil = true;
    return s;
  }
  if (n === "stuck") {
    s.probe.bt = { hw: true, installed: true, running: true, controllers: 0 };
    return s;
  }
  // full, and off: a laptop-ish mixed machine with everything there
  s.probe.stack = "networkd";
  s.probe.stacks = ["networkd", "nm"];
  s.probe.nm = { installed: true, running: true };
  s.probe.wifiHw = true;
  s.probe.links.push(wifiLink(n === "full"));
  s.probe.bt = { hw: true, installed: true, running: true, controllers: 1 };
  s.probe.vpn = [
    { name: "Work", uuid: "u-work", type: "wireguard", active: false, managed: true },
    { name: "Home", uuid: "u-home", type: "vpn", active: false, managed: true }
  ];
  s.probe.display = { backlight: [{ name: "intel_backlight", cur: 60, max: 100 }],
                      ddcutil: true, i2c: true, hyprsunset: true, sunsetRunning: false };
  s.ddc = [{ display: 1, bus: 4, connector: "DP-1", model: "DELL U2720Q", cur: 50, max: 100 }];
  s.bt = { present: true, name: "KRIG", enabled: n === "full", discovering: false, discoverable: false };
  s.wifiOn = n === "full";
  if (n === "off") return s;
  s.networks = [
    { name: "ZenTest", strength: 0.82, known: true, connected: true, busy: false, security: "Wpa2Psk" },
    { name: "ZenOpen", strength: 0.55, known: false, connected: false, busy: false, security: "Open" },
    { name: "Neighbours 5G", strength: 0.35, known: false, connected: false, busy: false, security: "Sae" },
    { name: "Office", strength: 0.6, known: false, connected: false, busy: false, security: "Wpa2Eap" },
    { name: "Café", strength: 0.18, known: false, connected: false, busy: false, security: "WpaPsk" }
  ];
  s.devices = [
    { name: "WH-1000XM5", address: "AC:80:0A:00:00:01", icon: "audio-headset", connected: true, paired: true, busy: false, battery: 0.8 },
    { name: "MX Master 3S", address: "D4:11:00:00:00:02", icon: "input-mouse", connected: false, paired: true, busy: false, battery: 0.45 },
    { name: "Pixel 8", address: "F0:5C:00:00:00:03", icon: "phone", connected: false, paired: false, busy: false, battery: -1 },
    { name: "5A:21:00:00:00:04", address: "5A:21:00:00:00:04", icon: "", connected: false, paired: false, busy: false, battery: -1 }
  ];
  return s;
}

function findBy(list, name) {
  for (var i = 0; i < list.length; ++i) if (list[i].name === name) return list[i];
  return null;
}
function wifiLinkOf(s) { return findBy(s.probe.links, "wlan1"); }

function act(state, what, name, arg) {
  var s = clone(state);
  var r = { state: s, said: "", bad: false, ask: false };
  var n, d, v, l;
  switch (what) {
  case "wifiPower":
    s.wifiOn = !!arg;
    if (!arg) s.networks.forEach(function (x) { x.connected = false; });
    l = wifiLinkOf(s);
    if (l && !arg) { l.up = false; l.carrier = false; l.ipv4 = []; l.gateway = ""; }
    break;
  case "join":
    n = findBy(s.networks, name);
    if (!n) break;
    if (arg === "wrong") { r.ask = true; r.said = "Wrong password for " + name; r.bad = true; break; }
    s.networks.forEach(function (x) { x.connected = false; });
    n.connected = true;
    n.known = true;
    l = wifiLinkOf(s);
    if (l) { l.up = true; l.carrier = true; l.ipv4 = ["10.42.0.57/24"]; l.gateway = "10.42.0.1"; }
    break;
  case "leave":
    n = findBy(s.networks, name);
    if (n) n.connected = false;
    l = wifiLinkOf(s);
    if (l) { l.up = false; l.carrier = false; l.ipv4 = []; l.gateway = ""; }
    break;
  case "forget":
    n = findBy(s.networks, name);
    if (n) { n.known = false; n.connected = false; }
    break;
  case "btPower":
    s.bt.enabled = !!arg;
    if (!arg) { s.bt.discovering = false; s.devices.forEach(function (x) { x.connected = false; }); }
    break;
  case "scan":
    s.bt.discovering = !!arg;
    if (arg && !findBy(s.devices, "Keychron K3"))
      s.devices.push({ name: "Keychron K3", address: "DC:2C:00:00:00:05", icon: "input-keyboard",
                       connected: false, paired: false, busy: false, battery: -1 });
    break;
  case "discoverable":
    s.bt.discoverable = !!arg;
    break;
  case "devConnect":
    d = findBy(s.devices, name);
    if (d && d.paired) d.connected = true;
    break;
  case "devDisconnect":
    d = findBy(s.devices, name);
    if (d) d.connected = false;
    break;
  case "devPair":
    d = findBy(s.devices, name);
    if (d) { d.paired = true; d.connected = true; r.said = "Paired with " + name; }
    break;
  case "devForget":
    d = findBy(s.devices, name);
    if (d) { d.paired = false; d.connected = false; }
    break;
  case "vpn":
    s.probe.vpn.forEach(function (x) { x.active = x.name === name ? !x.active : false; });
    v = findBy(s.probe.vpn, name);
    r.said = v ? (v.active ? "Connected to " : "Disconnected from ") + name : "";
    break;
  case "brightness":
    if (String(name).indexOf("bl:") === 0) {
      s.probe.display.backlight.forEach(function (b) { if ("bl:" + b.name === name) b.cur = Math.round(arg * b.max / 100); });
    } else {
      s.ddc.forEach(function (x) { if ("ddc:" + x.bus === name) x.cur = Math.round(arg * x.max / 100); });
    }
    break;
  case "setup":
    // what Ceres would have left behind, had it run
    if (name === "bluetoothStop") {
      s.probe.bt.running = false;
      s.probe.bt.controllers = 0;
      s.bt = { present: false, name: "", enabled: false, discovering: false, discoverable: false };
    } else if (name === "bluetooth" || name === "bluetoothStart") {
      s.probe.bt.installed = true;
      s.probe.bt.running = true;
      s.probe.bt.controllers = s.probe.bt.hw ? 1 : 0;
      s.bt = { present: s.probe.bt.hw, name: "KRIG", enabled: true, discovering: false, discoverable: false };
    } else if (name === "ddcutil") {
      s.probe.display.ddcutil = true;
      s.probe.display.i2c = true;
      s.ddc = [{ display: 1, bus: 4, connector: "DP-1", model: "DELL U2720Q", cur: 50, max: 100 }];
    } else if (name === "hyprsunset") {
      s.probe.display.hyprsunset = true;
    } else if (name === "networkmanager") {
      s.probe.nm = { installed: true, running: true };
      s.probe.stack = "nm";
      s.probe.stacks = ["nm"];
      s.probe.links.forEach(function (x) { x.managedBy = "nm"; });
      s.wifiOn = true;
    }
    r.said = "Done";
    break;
  }
  return r;
}

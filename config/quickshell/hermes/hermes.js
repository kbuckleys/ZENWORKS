// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

.pragma library
// ONE COPY FOR THE WHOLE SHELL. Without the pragma every component instance
// that imports this file evaluated all of it again (see morpheus/icons.js).
//
// HERMES' PURE HALF: what the probe said, put in order; the glyphs and the
// words for a link, a network, a device; ddcutil's output read; and the
// Ceres jobs that set a missing piece up. Nothing here touches the machine,
// so oracle/tests/hermes.js checks all of it.

// ── THE GLYPHS ───────────────────────────────────────────────────────────
// Material Design, by name from alexandria's glyphnames.json
var G = {
  app: "\u{F1542}",           // md-tune_variant: hermes itself (user's pick)
  wifi: ["\u{F092F}", "\u{F091F}", "\u{F0922}", "\u{F0925}", "\u{F0928}"],  // outline, 1…4
  wifiOff: "\u{F05AA}",
  wifiLock: "\u{F16BF}",
  wired: "\u{F0200}",          // md-ethernet
  wiredOff: "\u{F0319}",       // md-lan_disconnect
  bt: "\u{F00AF}",
  btOff: "\u{F00B2}",
  btOn: "\u{F00B1}",           // md-bluetooth_connect
  vpn: "\u{F0582}",
  vpnOn: "\u{F099D}",          // md-shield_lock
  sun: "\u{F00DF}",            // md-brightness_6
  night: "\u{F0594}",          // md-weather_night
  monitor: "\u{F0379}",
  lock: "\u{F033E}",
  check: "\u{F012C}",
  scan: "\u{F0437}",           // md-radar
  battery: "\u{F0079}",
  info: "\u{F02FD}",
  forget: "\u{F0A7A}",
  dns: "\u{F01D6}",
  network: "\u{F0317}",        // md-lan
  printer: "\u{F042A}",        // md-printer
  printerOff: "\u{F0E5D}",     // md-printer_off
  printerAlert: "\u{F042C}",   // md-printer_alert
  printerSearch: "\u{F1457}",  // md-printer_search
  scanner: "\u{F06AB}"         // md-scanner
};

// The sections, in the order the window's sidebar and the quick panel's
// tiles both keep
var SECTIONS = [
  { id: "network", label: "Network", glyph: "\u{F0317}" },
  { id: "bluetooth", label: "Bluetooth", glyph: "\u{F00AF}" },
  { id: "vpn", label: "VPN", glyph: "\u{F0582}" },
  { id: "display", label: "Display", glyph: "\u{F0379}" },
  { id: "printers", label: "Printers", glyph: "\u{F042A}" }
];

// ── THE PROBE ────────────────────────────────────────────────────────────
// bin/hermes-probe's JSON, with every field there whatever the probe said
// (or failed to say): the panel binds straight to these.
function emptyProbe() {
  return {
    known: false,
    stack: "",
    stacks: [],
    nm: { installed: false, running: false },
    links: [],
    dns: [],
    wifiHw: false,
    bt: { hw: false, installed: false, running: false, controllers: -1 },
    rfkill: { wifi: null, bt: null },
    vpn: [],
    display: { backlight: [], ddcutil: false, i2c: false, hyprsunset: false, sunsetRunning: false }
  };
}

function parseProbe(text) {
  var p = emptyProbe();
  var j;
  try { j = JSON.parse(String(text || "")); } catch (e) { return p; }
  if (!j || typeof j !== "object") return p;
  p.known = true;
  p.stack = typeof j.stack === "string" ? j.stack : "";
  p.stacks = Array.isArray(j.stacks) ? j.stacks.map(String) : (p.stack ? [p.stack] : []);
  if (j.nm) p.nm = { installed: !!j.nm.installed, running: !!j.nm.running };
  if (Array.isArray(j.links)) p.links = j.links.filter(function (l) { return l && l.name; }).map(function (l) {
    return {
      name: String(l.name), kind: l.kind === "wifi" ? "wifi" : "wired",
      up: !!l.up, carrier: !!l.carrier, speed: Number(l.speed) || 0, mac: String(l.mac || ""),
      ipv4: Array.isArray(l.ipv4) ? l.ipv4.map(String) : [],
      ipv6: Array.isArray(l.ipv6) ? l.ipv6.map(String) : [],
      gateway: String(l.gateway || ""),
      managedBy: String(l.managedBy || "")
    };
  });
  if (Array.isArray(j.dns)) p.dns = j.dns.map(String);
  p.wifiHw = !!j.wifiHw;
  if (j.bt) p.bt = { hw: !!j.bt.hw, installed: !!j.bt.installed, running: !!j.bt.running,
                     controllers: typeof j.bt.controllers === "number" ? j.bt.controllers : -1 };
  if (j.rfkill) p.rfkill = { wifi: j.rfkill.wifi || null, bt: j.rfkill.bt || null };
  if (Array.isArray(j.vpn)) p.vpn = j.vpn.filter(function (v) { return v && v.name; }).map(function (v) {
    return { name: String(v.name), uuid: String(v.uuid || ""), type: String(v.type || "vpn"),
             active: !!v.active, managed: !!v.managed };
  });
  if (j.display) {
    var d = j.display;
    p.display = {
      backlight: Array.isArray(d.backlight) ? d.backlight.filter(function (b) { return b && b.name && b.max > 0; }) : [],
      ddcutil: !!d.ddcutil, i2c: !!d.i2c, hyprsunset: !!d.hyprsunset, sunsetRunning: !!d.sunsetRunning
    };
  }
  return p;
}

// The wired link to talk about: one with a carrier first, then any.
function wiredLink(p) {
  var ls = (p && p.links || []).filter(function (l) { return l.kind === "wired"; });
  for (var i = 0; i < ls.length; ++i) if (ls[i].carrier && ls[i].up) return ls[i];
  return ls.length > 0 ? ls[0] : null;
}

// The kernel has an adapter, BlueZ runs, and BlueZ has none: the adapter
// failed to start (its reset timed out) rather than anything being missing
function btStuck(p) {
  return !!p && p.bt.hw && p.bt.running && p.bt.controllers === 0;
}

// Who runs the network, in words
function stackWords(stack) {
  return { nm: "NetworkManager", networkd: "systemd-networkd", iwd: "iwd" }[stack] || "nothing Hermes knows";
}

// Every stack running a link, in words: a mixed machine (wired on
// networkd, Wi-Fi on NetworkManager) names both
function stacksWords(p) {
  var ss = p && p.stacks && p.stacks.length ? p.stacks : (p && p.stack ? [p.stack] : []);
  if (ss.length === 0) return stackWords("");
  return ss.map(stackWords).join(" and ");
}
// The same, short enough for the window's sidebar
function stacksShort(p) {
  var ss = p && p.stacks && p.stacks.length ? p.stacks : (p && p.stack ? [p.stack] : []);
  if (ss.length === 0) return "nothing yet";
  return ss.map(function (x) { return { nm: "NetworkManager", networkd: "networkd", iwd: "iwd" }[x] || x; }).join(" + ");
}
// Who runs this link: its own, else the machine's
function linkStack(p, l) { return stackWords(l && l.managedBy ? l.managedBy : (p ? p.stack : "")); }

// 1000 → "1 Gb/s", 2500 → "2.5 Gb/s", 100 → "100 Mb/s"
function speedWords(mbps) {
  var m = Number(mbps) || 0;
  if (m <= 0) return "";
  if (m >= 1000) return (Math.round(m / 100) / 10).toString() + " Gb/s";
  return m + " Mb/s";
}

// ── WI-FI ────────────────────────────────────────────────────────────────
// quickshell's signalStrength is 0…1; a percentage is taken as one too
function strength01(s) {
  var v = Number(s) || 0;
  if (v > 1) v = v / 100;
  return Math.max(0, Math.min(1, v));
}
function wifiBars(s) {
  var v = strength01(s);
  return v <= 0 ? 0 : Math.min(4, Math.max(1, Math.ceil(v * 4)));
}
function wifiGlyph(s) { return G.wifi[wifiBars(s)]; }

// WifiSecurityType.toString() → the word on the row, and whether joining
// asks for a password Hermes can take (a passphrase; enterprise sign-ins
// are NetworkManager's own dialog, not a field here)
function securityWords(t) {
  var s = String(t || "");
  if (s === "Open" || s === "Owe" || s === "") return s === "Owe" ? "Open, encrypted" : "Open";
  if (s === "Sae" || s === "Wpa3SuiteB192") return "WPA3";
  if (s === "Wpa2Psk") return "WPA2";
  if (s === "WpaPsk") return "WPA";
  if (s === "Wpa2Eap" || s === "WpaEap" || s === "Leap") return "Enterprise";
  if (s === "StaticWep" || s === "DynamicWep") return "WEP";
  return "Secured";
}
function securityOpen(t) { var s = String(t || ""); return s === "Open" || s === "Owe"; }
function needsPassphrase(t) {
  return ["Sae", "Wpa2Psk", "WpaPsk", "StaticWep", "Wpa3SuiteB192"].indexOf(String(t || "")) >= 0;
}
function enterprise(t) { return ["Wpa2Eap", "WpaEap", "Leap", "DynamicWep"].indexOf(String(t || "")) >= 0; }

// The networks as listed: connected first, then saved ones, then by signal;
// one row per name (an access point per band shows up as two)
function sortNetworks(nets) {
  var best = {};
  (nets || []).forEach(function (n) {
    if (!n || !n.name) return;
    var cur = best[n.name];
    if (!cur || rankOf(n) < rankOf(cur) || (rankOf(n) === rankOf(cur) && strength01(n.strength) > strength01(cur.strength)))
      best[n.name] = n;
  });
  return Object.keys(best).map(function (k) { return best[k]; }).sort(function (a, b) {
    var r = rankOf(a) - rankOf(b);
    if (r !== 0) return r;
    var s = strength01(b.strength) - strength01(a.strength);
    if (s !== 0) return s;
    return a.name.localeCompare(b.name);
  });
}
function rankOf(n) { return n.connected ? 0 : n.known ? 1 : 2; }

// ── BLUETOOTH ────────────────────────────────────────────────────────────
// BlueZ's freedesktop icon name → the glyph for the row
function btGlyph(icon) {
  var i = String(icon || "");
  if (/headset|headphone|earbud/.test(i)) return "\u{F02CB}";
  if (/audio|speaker|card/.test(i)) return "\u{F04C3}";
  if (/keyboard/.test(i)) return "\u{F030C}";
  if (/mouse|tablet/.test(i)) return "\u{F037D}";
  if (/gaming|joystick/.test(i)) return "\u{F0297}";
  if (/phone/.test(i)) return "\u{F011C}";
  if (/computer|laptop/.test(i)) return "\u{F0322}";
  if (/printer/.test(i)) return "\u{F042A}";
  if (/watch/.test(i)) return "\u{F0589}";
  return G.bt;
}
// 0…1 (or a percentage) → "80%"
function batteryWords(b) {
  var v = Number(b);
  if (!isFinite(v) || v < 0) return "";
  if (v <= 1) v = v * 100;
  return Math.round(v) + "%";
}
// paired and connected first, then paired, then the rest by name; unnamed
// devices (a bare address) last, as every pairing dialog does
function sortDevices(devs) {
  return (devs || []).slice().sort(function (a, b) {
    var ra = a.connected ? 0 : a.paired ? 1 : 2, rb = b.connected ? 0 : b.paired ? 1 : 2;
    if (ra !== rb) return ra - rb;
    var na = !!a.named, nb = !!b.named;
    if (na !== nb) return na ? -1 : 1;
    return String(a.name || "").localeCompare(String(b.name || ""));
  });
}

// ── THE DISPLAY ──────────────────────────────────────────────────────────
// `ddcutil detect --brief`: a "Display N" block per monitor that answers
// DDC, with its bus and connector. "Invalid display" blocks (a monitor that
// does not) are left out.
function parseDdcDetect(text) {
  var out = [], cur = null;
  String(text || "").split("\n").forEach(function (line) {
    var m = /^Display\s+(\d+)/.exec(line);
    if (m) { cur = { display: Number(m[1]), bus: -1, connector: "", model: "" }; out.push(cur); return; }
    if (/^\S/.test(line)) { cur = null; return; }
    if (!cur) return;
    var b = /I2C bus:\s*\/dev\/i2c-(\d+)/.exec(line);
    if (b) { cur.bus = Number(b[1]); return; }
    var c = /DRM[_ ]connector:\s*(\S+)/.exec(line);
    if (c) { cur.connector = c[1].replace(/^card\d+-/, ""); return; }
    var mo = /Monitor:\s*(.*)$/.exec(line);
    if (mo) { var parts = mo[1].split(":"); cur.model = (parts.length >= 2 ? parts[1] : parts[0]).trim(); }
  });
  return out.filter(function (d) { return d.bus >= 0; });
}
// `ddcutil getvcp 10 --brief` → "VCP 10 C 50 100"
function parseVcp(text) {
  var m = /VCP\s+[0-9A-Fa-f]+\s+C\s+(\d+)\s+(\d+)/.exec(String(text || ""));
  return m ? { cur: Number(m[1]), max: Number(m[2]) } : null;
}
function percent(cur, max) { return max > 0 ? Math.round(100 * cur / max) : 0; }

// Night light: hyprsunset's range is 1000–20000 K; this keeps to the part a
// screen is ever wanted at
var KELVIN_MIN = 2500;
var KELVIN_MAX = 6500;
var KELVIN_DEFAULT = 4000;
function clampKelvin(k) {
  var v = Math.round((Number(k) || KELVIN_DEFAULT) / 50) * 50;
  return Math.max(KELVIN_MIN, Math.min(KELVIN_MAX, v));
}
function kelvinWords(k) { return clampKelvin(k) + " K"; }
// on by hand, or by the sun when that is asked for
function nightWanted(on, followSun, daylight) { return followSun ? !daylight : !!on; }

// ── SETTING A PIECE UP: Ceres' steps ─────────────────────────────────────
// Each is one Ceres job (Ceres.install's `after` steps run as root once the
// packages are in), so the password is asked for once.
//   bluetooth       bluez + its service
//   ddcutil         the tool, i2c-dev at boot and now, the udev rule applied
//   hyprsunset      nothing to start: Hermes runs it
//   networkmanager  SWAPS THE STACK: networkd off, NetworkManager on.
//                   Only ever behind a confirmation that says so.
var SETUP = {
  bluetooth: {
    pkgs: ["bluez", "bluez-utils"],
    after: [["@sudo", "systemctl", "enable", "--now", "bluetooth.service"]],
    why: "for Bluetooth in Hermes"
  },
  bluetoothStart: {
    pkgs: [],
    after: [["@sudo", "systemctl", "enable", "--now", "bluetooth.service"]],
    why: "start Bluetooth"
  },
  // BlueZ off and kept off at boot: the way out when there is no adapter
  // power switch to flip — one that never answered (user, 2026-10-21)
  bluetoothStop: {
    pkgs: [],
    after: [["@sudo", "systemctl", "disable", "--now", "bluetooth.service"]],
    why: "turn Bluetooth off"
  },
  ddcutil: {
    pkgs: ["ddcutil"],
    after: [["@sudo", "sh", "-c",
      "echo i2c-dev > /etc/modules-load.d/i2c-dev.conf && modprobe i2c-dev && udevadm trigger --subsystem-match=i2c-dev"]],
    why: "for monitor brightness in Hermes"
  },
  hyprsunset: {
    pkgs: ["hyprsunset"],
    after: [],
    why: "for night light in Hermes"
  },
  networkmanager: {
    pkgs: ["networkmanager"],
    after: [["@sudo", "sh", "-c",
      "systemctl disable --now systemd-networkd.service systemd-networkd.socket systemd-networkd-wait-online.service 2>/dev/null; systemctl enable --now NetworkManager.service"]],
    why: "to manage Wi-Fi and VPNs in Hermes (replaces systemd-networkd)"
  }
};
// Printing: CUPS with its filters, ipp-usb (a USB printer or scanner as a
// driverless network one) and avahi to find network printers; the socket
// and avahi started now and at boot. Scanning: SANE and its driverless
// eSCL/WSD backend.
SETUP.printing = {
  pkgs: ["cups", "cups-filters", "ipp-usb", "avahi"],
  after: [["@sudo", "systemctl", "enable", "--now", "cups.socket", "avahi-daemon.service"]],
  why: "for printers in Control Hub"
};
SETUP.printingStart = {
  pkgs: [],
  after: [["@sudo", "systemctl", "enable", "--now", "cups.socket", "avahi-daemon.service"]],
  why: "start printing"
};
SETUP.scanning = {
  pkgs: ["sane", "sane-airscan", "ipp-usb"],
  after: [],
  why: "for scanners in Control Hub"
};
function setupOf(kind) { return SETUP[kind] || null; }

// ── PRINTERS AND SCANNERS ────────────────────────────────────────────────
// bin/hermes-print's answers, with every field there whatever it said
function emptyPrint() {
  return { known: false, cups: { installed: false, running: false }, sane: { installed: false, airscan: false },
           printers: [], jobs: [] };
}
function parsePrint(text) {
  var d = emptyPrint();
  var j;
  try { j = JSON.parse(String(text || "")); } catch (e) { return d; }
  if (!j || typeof j !== "object") return d;
  d.known = true;
  if (j.cups) d.cups = { installed: !!j.cups.installed, running: !!j.cups.running };
  if (j.sane) d.sane = { installed: !!j.sane.installed, airscan: !!j.sane.airscan };
  d.printers = (Array.isArray(j.printers) ? j.printers : []).filter(function (p) { return p && p.name; }).map(function (p) {
    return { name: String(p.name), info: String(p.info || p.name), model: String(p.model || ""), uri: String(p.uri || ""),
             state: p.state === "printing" || p.state === "stopped" ? p.state : "idle",
             reasons: Array.isArray(p.reasons) ? p.reasons.map(String) : [],
             default: !!p.default, jobs: Number(p.jobs) || 0 };
  });
  // the default first, then by name
  d.printers.sort(function (a, b) { return (b.default - a.default) || a.info.localeCompare(b.info); });
  d.jobs = (Array.isArray(j.jobs) ? j.jobs : []).filter(function (x) { return x && x.id; }).map(function (x) {
    return { id: String(x.id), printer: String(x.printer || ""), size: Number(x.size) || 0, user: String(x.user || "") };
  });
  return d;
}
// an action's answer: { ok, error, admin }
function parseAct(text) {
  var j;
  try { j = JSON.parse(String(text || "")); } catch (e) { return { ok: false, error: "no answer", admin: false }; }
  return { ok: !!(j && j.ok), error: j && j.error ? String(j.error) : "", admin: !!(j && j.admin) };
}
function parseDevices(text) {
  var j;
  try { j = JSON.parse(String(text || "")); } catch (e) { return { ok: false, error: "no answer", devices: [] }; }
  return { ok: !!(j && j.ok), error: j && j.error ? String(j.error) : "",
           devices: (j && Array.isArray(j.devices) ? j.devices : []).filter(function (x) { return x && (x.uri || x.id); }) };
}
// CUPS' state reasons that are worth saying, in words
var REASONS = {
  "media-empty": "Out of paper", "media-needed": "Out of paper", "media-jam": "Paper jam",
  "toner-low": "Toner low", "toner-empty": "Out of toner", "marker-supply-low": "Ink low",
  "marker-supply-empty": "Out of ink", "door-open": "A door is open", "cover-open": "The cover is open",
  "offline": "Offline", "paused": "Paused", "connecting-to-device": "Connecting…"
};
function reasonWords(reasons) {
  var out = [];
  (reasons || []).forEach(function (r) {
    var k = String(r).replace(/-(report|warning|error)$/, "");
    if (REASONS[k] && out.indexOf(REASONS[k]) < 0) out.push(REASONS[k]);
  });
  return out.join(" · ");
}
function printerWords(p) {
  if (!p) return "";
  var why = reasonWords(p.reasons);
  var st = p.state === "stopped" ? "Paused" : p.state === "printing" ? "Printing" : "Ready";
  if (why === "Paused") why = "";
  var jobs = p.jobs > 0 ? p.jobs + (p.jobs === 1 ? " job" : " jobs") : "";
  return [st, why, jobs].filter(function (x) { return x; }).join(" · ");
}
function printerGlyph(p) {
  if (!p) return G.printer;
  if (p.state === "stopped") return G.printerOff;
  return reasonWords(p.reasons) !== "" ? G.printerAlert : G.printer;
}
// a scan's file: "Scan 2026-10-22 14.03.05.png" — sorts by when, and says it
function scanFileName(date, fmt) {
  function two(n) { return (n < 10 ? "0" : "") + n; }
  var d = date;
  return "Scan " + d.getFullYear() + "-" + two(d.getMonth() + 1) + "-" + two(d.getDate()) + " "
    + two(d.getHours()) + "." + two(d.getMinutes()) + "." + two(d.getSeconds()) + "." + (fmt === "pdf" ? "pdf" : "png");
}
// a printer found nearby that is already set up (same address)
function alreadyAdded(dev, printers) {
  return (printers || []).some(function (p) { return p.uri === dev.uri; });
}

// ── THE BAR ──────────────────────────────────────────────────────────────
// Hermes' own glyph, the one cynosure and icarus show (user, 2026-10-20:
// "the same icon in morpheus"), in the colour of the connection: connected,
// off (Wi-Fi switched off, nothing joined), or down (no link at all). What
// it is connected to, and Bluetooth and the VPN, are the tooltip's.
//   live: { wifiOn, wifiNet: { name, strength } | null, btConnected, vpnActive }
function barGlyphs(p, live) {
  var l = live || {};
  var w = wiredLink(p);
  var role = (w && w.carrier && w.up) || l.wifiNet ? "ok"
    : p && p.wifiHw ? "off"
    : p && p.known ? "down" : "off";
  return [{ glyph: G.app, role: role }];
}

// The tooltip's lines
function barWords(p, live) {
  var l = live || {};
  var lines = [];
  var w = wiredLink(p);
  if (w && w.carrier && w.up) {
    lines.push("<b>Wired</b> · " + w.name + (w.speed ? " · " + speedWords(w.speed) : ""));
    if (w.ipv4.length) lines.push(w.ipv4[0].split("/")[0]);
  } else if (l.wifiNet) {
    lines.push("<b>" + escapeHtml(l.wifiNet.name) + "</b> · " + Math.round(strength01(l.wifiNet.strength) * 100) + "%");
  } else if (p && p.wifiHw) {
    lines.push(l.wifiOn === false ? "<b>Wi-Fi off</b>" : "<b>Not connected</b>");
  } else {
    lines.push("<b>Not connected</b>");
  }
  if (l.btConnected > 0) lines.push("Bluetooth · " + l.btConnected + (l.btConnected === 1 ? " device" : " devices"));
  if (l.vpnActive) lines.push("VPN · " + escapeHtml(l.vpnActive));
  if (l.night) lines.push("Night light · " + kelvinWords(l.kelvin));
  return lines.join("\n");
}

function escapeHtml(s) {
  return String(s || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

// ── PERSISTED SETTINGS ───────────────────────────────────────────────────
function defaults() {
  return { nightOn: false, nightSun: false, kelvin: KELVIN_DEFAULT, section: "network" };
}
function parseSettings(text) {
  var d = defaults();
  var j;
  try { j = JSON.parse(String(text || "")); } catch (e) { return d; }
  if (!j || typeof j !== "object") return d;
  if (typeof j.nightOn === "boolean") d.nightOn = j.nightOn;
  if (typeof j.nightSun === "boolean") d.nightSun = j.nightSun;
  if (j.kelvin !== undefined) d.kelvin = clampKelvin(j.kelvin);
  if (SECTIONS.some(function (s) { return s.id === j.section; })) d.section = j.section;
  return d;
}
function serializeSettings(s) {
  var d = defaults();
  return JSON.stringify({
    nightOn: s && typeof s.nightOn === "boolean" ? s.nightOn : d.nightOn,
    nightSun: s && typeof s.nightSun === "boolean" ? s.nightSun : d.nightSun,
    kelvin: clampKelvin(s ? s.kelvin : d.kelvin),
    section: s && s.section ? s.section : d.section
  }, null, 2) + "\n";
}

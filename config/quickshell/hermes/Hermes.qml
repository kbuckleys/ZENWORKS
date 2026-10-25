// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// HERMES — the messenger: what this machine is connected to and how its
// screens look. Wi-Fi, the wired link, Bluetooth, VPNs, and the display's
// brightness and night light. The quick panel (HermesPopup) and the window
// (HermesWindow) are two views of THIS, and the bar's icon reads it too, so
// it is a singleton: one state, whoever is looking.
//
// WHERE EACH ANSWER COMES FROM
//   Wi-Fi           Quickshell.Networking, which is NetworkManager's
//   Bluetooth       Quickshell.Bluetooth, which is BlueZ's
//   everything else bin/hermes-probe: which stack runs the network (a wired
//                   desktop on systemd-networkd has no NetworkManager to
//                   ask), the wired link's facts, the hardware there is,
//                   what is installed, the VPNs (nmcli, or the WireGuard
//                   links up), the backlights
//   monitors        ddcutil, asked only while Hermes is open
//   night light     hyprsunset, which Hermes runs and stops
//
// A piece that is missing is set up from where it is missing (setup()),
// through Ceres: its password card, its log. Nothing is installed or
// switched on unasked.
//
// The probe runs once at start, on every change `ip monitor` reports, and
// every few seconds while a view is open (hold/release) — the bar's icon
// has to be right without anything open, and nothing should poll for it.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Bluetooth
import "../morpheus"
import "../oracle"
import "../morpheus/hypr.js" as Hypr
import "../morpheus/lagnotes.js" as LagNotes
import "../ceres"
import "hermes.js" as H
import "fake.js" as F

Singleton {
  id: root

  // ── PRETENDING ─────────────────────────────────────────────────────────
  // HERMES_FAKE=<scenario> (fake.js: full, wired, bare, stopped, stuck, off)
  // swaps every live source below for a made-up machine — for the offscreen
  // harness and for states this one cannot reach. Nothing ships with it set.
  readonly property string fake: Quickshell.env("HERMES_FAKE") || ""
  property var sim: root.fake !== "" ? F.scenario(root.fake) : null
  onSimChanged: if (root.sim) root.probe = root.sim.probe
  function fakeDo(what, name, arg) {
    const r = F.act(root.sim, what, name, arg);
    root.sim = r.state;
    if (r.ask) root.askAgain(name);
    if (r.said) root.tell(r.said, r.bad);
  }
  function fakeNet(name) {
    return { connect: () => root.fakeDo("join", name), connectWithPsk: (p) => root.fakeDo("join", name, p),
             disconnect: () => root.fakeDo("leave", name), forget: () => root.fakeDo("forget", name) };
  }
  function fakeDev(name) {
    return { connect: () => root.fakeDo("devConnect", name), disconnect: () => root.fakeDo("devDisconnect", name),
             pair: () => root.fakeDo("devPair", name), forget: () => root.fakeDo("devForget", name), trusted: false };
  }

  // ── WHAT THE PROBE SAID ────────────────────────────────────────────────
  property var probe: H.emptyProbe()
  readonly property var wired: H.wiredLink(root.probe)
  // Quickshell.Networking and .Bluetooth are only TOUCHED once the probe
  // says their service runs: touched without one, each logs an error at
  // every shell load ("Network will not work…", org.bluez's object manager)
  // on a machine that simply has no NetworkManager or BlueZ.
  readonly property bool nmRunning: root.probe.nm.running

  // ── WI-FI, LIVE ────────────────────────────────────────────────────────
  readonly property var wifiDevice: {
    if (root.sim) return root.sim.probe.wifiHw && root.nmRunning ? { name: "wlan1", fake: true } : null;
    if (!root.nmRunning) return null;
    const ds = Networking.devices ? Networking.devices.values : [];
    for (let i = 0; i < ds.length; ++i)
      if (ds[i] && ds[i].type === DeviceType.Wifi) return ds[i];
    return null;
  }
  readonly property bool wifiReady: root.nmRunning && root.wifiDevice !== null
  readonly property bool wifiOn: root.sim ? root.sim.wifiOn : root.nmRunning && Networking.wifiEnabled
  // [{ ref, name, strength, known, connected, busy, security }] in the
  // order they are listed (H.sortNetworks)
  readonly property var networks: {
    if (root.sim) return root.wifiOn ? H.sortNetworks(root.sim.networks.map((n) => Object.assign({}, n, { ref: root.fakeNet(n.name) }))) : [];
    const d = root.wifiDevice;
    if (!d || !d.networks) return [];
    return H.sortNetworks(d.networks.values.map((n) => ({
      ref: n, name: n.name, strength: n.signalStrength, known: n.known,
      connected: n.connected, busy: n.stateChanging,
      security: WifiSecurityType.toString(n.security)
    })));
  }
  readonly property var wifiNet: root.networks.length > 0 && root.networks[0].connected ? root.networks[0] : null

  // ── BLUETOOTH, LIVE ────────────────────────────────────────────────────
  readonly property var adapter: root.sim ? (root.sim.bt.present && root.sim.probe.bt.running ? root.sim.bt : null)
    : root.probe.bt.running ? Bluetooth.defaultAdapter : null
  readonly property bool btReady: root.adapter !== null
  readonly property bool btOn: !!root.adapter && root.adapter.enabled
  readonly property bool btScanning: !!root.adapter && root.adapter.discovering
  // [{ ref, name, named, icon, connected, paired, busy, battery }]
  readonly property var devices: {
    if (root.sim) return root.btOn ? H.sortDevices(root.sim.devices.map((d) => ({
      ref: root.fakeDev(d.name), name: d.name, named: d.name !== d.address, icon: d.icon,
      connected: d.connected, paired: d.paired, busy: d.busy, battery: d.battery }))) : [];
    const a = root.adapter;
    if (!a || !a.devices) return [];
    return H.sortDevices(a.devices.values.map((d) => ({
      ref: d, name: d.name || d.deviceName || d.address,
      named: !!(d.name || d.deviceName) && (d.name || d.deviceName) !== d.address,
      icon: d.icon, connected: d.connected, paired: d.paired || d.bonded,
      busy: d.pairing || d.state === BluetoothDeviceState.Connecting || d.state === BluetoothDeviceState.Disconnecting,
      battery: d.batteryAvailable ? d.battery : -1
    })));
  }
  readonly property int btConnected: root.devices.filter((d) => d.connected).length

  // ── VPN ────────────────────────────────────────────────────────────────
  readonly property var vpns: root.probe.vpn
  readonly property string vpnActive: {
    const v = root.vpns.find((x) => x.active);
    return v ? v.name : "";
  }

  // ── THE BAR'S VIEW OF ALL THAT ─────────────────────────────────────────
  readonly property var live: ({
    wifiOn: root.wifiReady ? root.wifiOn : undefined,
    wifiNet: root.wifiNet,
    btConnected: root.btConnected,
    vpnActive: root.vpnActive,
    night: root.nightActive,
    kelvin: root.kelvin
  })
  readonly property var barGlyphs: H.barGlyphs(root.probe, root.live)
  readonly property string barTip: H.barWords(root.probe, root.live)

  // ── THE PROBE ──────────────────────────────────────────────────────────
  // How many views are open (the panel, the window): while any is, the
  // probe runs every few seconds, Wi-Fi scans and the monitors are asked.
  property int holds: 0
  // The monitors are asked ONCE A SESSION, not on every open: ddcutil
  // talks to them over the GPU driver's i2c, and on NVIDIA that holds the
  // driver for the whole run — `detect` plus a read per monitor is ~0.7 s,
  // and the shell's own drawing waited on it (every open stalled ~0.9 s,
  // 2026-10-20). Again when a monitor comes or goes, or when asked.
  function hold() {
    root.holds++;
    root.reprobe();
    if (root.holds === 1 && !root.ddcRead) ddcSoon.restart();
  }
  function release() { root.holds = Math.max(0, root.holds - 1); }

  function reprobe() { if (root.sim) { root.probe = root.sim.probe; return; } if (!probeProc.running) probeProc.running = true; else probeAgain.restart(); }
  Process {
    id: probeProc
    command: [Quickshell.shellDir + "/hermes/bin/hermes-probe"]
    stdout: StdioCollector {
      id: probeOut
      waitForEnd: true
      onStreamFinished: {
        const p = H.parseProbe(probeOut.text);
        // an empty answer (the probe killed by a reload) keeps the last one
        if (p.known) root.probe = p;
      }
    }
  }
  Timer { id: probeAgain; interval: 300; onTriggered: root.reprobe() }
  Timer {
    interval: 4000
    repeat: true
    running: root.holds > 0
    onTriggered: root.reprobe()
  }
  // Links, addresses and routes coming and going: re-asked at once rather
  // than waited for. Tethered, so it dies with the shell.
  Process {
    id: linkWatch
    running: root.fake === ""
    command: Paths.tether(["ip", "monitor", "link", "address", "route"])
    stdout: SplitParser { splitMarker: "\n"; onRead: (line) => probeSettle.restart() }
    onExited: linkRetry.restart()
  }
  Timer { id: probeSettle; interval: 400; onTriggered: root.reprobe() }
  Timer { id: linkRetry; interval: 5000; onTriggered: if (root.fake === "") linkWatch.running = true }

  // Wi-Fi only scans while someone is looking at the list
  Binding {
    target: root.sim ? null : root.wifiDevice
    property: "scannerEnabled"
    value: root.holds > 0
    when: root.wifiDevice !== null && !root.sim
  }

  // ── WHAT WAS JUST DONE, SAID ONCE ─────────────────────────────────────
  // The window's toast and the panel's note both read it.
  property string said: ""
  property bool saidBad: false
  function tell(text, bad) {
    root.said = text;
    root.saidBad = !!bad;
    sayTimer.restart();
  }
  Timer { id: sayTimer; interval: 3200; onTriggered: root.said = "" }

  // ── WI-FI, DONE ────────────────────────────────────────────────────────
  function setWifi(on) {
    if (!root.wifiReady) return;
    if (root.sim) { root.fakeDo("wifiPower", "", on); return; }
    Networking.wifiEnabled = on;
  }
  // A network that needs a passphrase Hermes has not got returns "ask":
  // the view asks for it and calls again with it.
  function join(n, psk) {
    if (!n || !n.ref) return "";
    if (n.connected) { n.ref.disconnect(); return "left"; }
    if (!n.known && H.enterprise(n.security)) {
      root.tell("Enterprise networks sign in with NetworkManager's own tools (nmtui)", true);
      return "";
    }
    if (!n.known && H.needsPassphrase(n.security)) {
      if (!psk) return "ask";
      n.ref.connectWithPsk(psk);
      return "joining";
    }
    n.ref.connect();
    return "joining";
  }
  function forget(n) {
    if (!n || !n.ref || !n.known) return;
    n.ref.forget();
    root.tell("Forgot " + n.name);
  }
  // A join that failed, from any network: said, and a wrong passphrase
  // asked for again (the view listens for askAgain)
  signal askAgain(string name)
  Instantiator {
    model: root.wifiDevice && root.wifiDevice.networks ? root.wifiDevice.networks : null
    delegate: Connections {
      required property var modelData
      target: modelData
      function onConnectionFailed(reason) {
        const why = ConnectionFailReason.toString(reason);
        if (why === "NoSecrets") { root.askAgain(modelData.name); root.tell("Wrong password for " + modelData.name, true); }
        else root.tell("Could not join " + modelData.name + (why && why !== "Unknown" ? " (" + why + ")" : ""), true);
      }
    }
  }

  // ── BLUETOOTH, DONE ────────────────────────────────────────────────────
  function setBluetooth(on) {
    if (root.sim) { if (root.adapter) root.fakeDo("btPower", "", on); return; }
    if (root.adapter) root.adapter.enabled = on;
  }
  function setDiscoverable(on) {
    if (!root.adapter || !root.btOn) return;
    if (root.sim) { root.fakeDo("discoverable", "", on); return; }
    root.adapter.discoverable = on;
  }
  // Discovery runs half a minute at a time: a radio left searching drains
  // batteries for nothing
  function scan(on) {
    if (!root.adapter) return;
    if (root.sim) {
      if (on && !root.btOn) root.fakeDo("btPower", "", true);
      root.fakeDo("scan", "", on);
    } else {
      if (on && !root.adapter.enabled) root.adapter.enabled = true;
      root.adapter.discovering = on;
    }
    if (on) scanStop.restart(); else scanStop.stop();
  }
  Timer { id: scanStop; interval: 30000; onTriggered: if (root.adapter) root.scan(false) }
  function toggleDevice(d) {
    if (!d || !d.ref) return;
    if (d.connected) { d.ref.disconnect(); return; }
    if (!d.paired) {
      // trusted too, so it may reconnect by itself next time, as every
      // pairing dialog leaves it
      d.ref.trusted = true;
      d.ref.pair();
      root.tell("Pairing with " + d.name + "…");
      return;
    }
    d.ref.connect();
  }
  function forgetDevice(d) {
    if (!d || !d.ref) return;
    const name = d.name;
    d.ref.forget();
    root.tell("Forgot " + name);
  }

  // ── VPN, DONE ──────────────────────────────────────────────────────────
  // terminus, handed in by shell.qml, for Import… (its picker)
  property var fileManager: null
  function chooseVpnFile() {
    if (!root.fileManager) return;
    root.fileManager.choose(false, Quickshell.env("HOME"), (paths) => {
      if (paths && paths.length > 0) root.importVpn(paths[0]);
    });
  }
  function toggleVpn(v) {
    if (!v || !v.managed || vpnProc.running) return;
    if (root.sim) { root.fakeDo("vpn", v.name); return; }
    vpnProc.target = v.name;
    vpnProc.up = !v.active;
    vpnProc.command = ["nmcli", "connection", v.active ? "down" : "up", "uuid", v.uuid];
    vpnProc.running = true;
  }
  Process {
    id: vpnProc
    property string target: ""
    property bool up: true
    stderr: StdioCollector { id: vpnErr; waitForEnd: true }
    onExited: (code) => {
      if (code === 0) root.tell((vpnProc.up ? "Connected to " : "Disconnected from ") + vpnProc.target);
      else root.tell("Could not " + (vpnProc.up ? "connect to " : "disconnect from ") + vpnProc.target
        + (vpnErr.text.trim() !== "" ? ": " + vpnErr.text.trim().split("\n").pop() : ""), true);
      root.reprobe();
    }
  }
  // A WireGuard .conf or an OpenVPN .ovpn, into NetworkManager
  function importVpn(path) {
    if (!path || importProc.running) return;
    if (root.sim) { root.tell("Imported " + path.replace(/.*\//, "") + " (pretend)"); return; }
    const type = /\.ovpn$/i.test(path) ? "openvpn" : "wireguard";
    importProc.command = ["nmcli", "connection", "import", "type", type, "file", path];
    importProc.running = true;
  }
  Process {
    id: importProc
    stderr: StdioCollector { id: importErr; waitForEnd: true }
    onExited: (code) => {
      if (code === 0) root.tell("Imported");
      else root.tell("Could not import: " + (importErr.text.trim().split("\n").pop() || "nmcli failed"), true);
      root.reprobe();
    }
  }

  // ── BRIGHTNESS ─────────────────────────────────────────────────────────
  // [{ id, kind: "backlight"|"ddc", name, label, pct }] — every screen
  // Hermes can dim
  property var ddcDisplays: []
  readonly property var ddcList: root.sim ? root.sim.ddc : root.ddcDisplays
  property bool ddcReading: false
  readonly property var screens: {
    const out = [];
    for (const b of root.probe.display.backlight)
      out.push({ id: "bl:" + b.name, kind: "backlight", name: b.name, label: "Built-in screen",
                 pct: root.pending["bl:" + b.name] !== undefined ? root.pending["bl:" + b.name] : H.percent(b.cur, b.max) });
    for (const d of root.ddcList)
      out.push({ id: "ddc:" + d.bus, kind: "ddc", bus: d.bus, name: d.connector,
                 label: d.model !== "" ? d.model : d.connector !== "" ? d.connector : "Display " + d.display,
                 pct: root.pending["ddc:" + d.bus] !== undefined ? root.pending["ddc:" + d.bus] : H.percent(d.cur, d.max) });
    return out;
  }
  // set but not yet written: what the slider shows meanwhile
  property var pending: ({})
  // Every change Hermes makes is announced, and howler's OSD shows it beside
  // the volume's (user, 2026-10-20): the screen and where it now is.
  property var osdBright: ({ label: "", pct: 0 })
  signal brightnessBumped()
  // the brightness keys: every screen that can be dimmed, by `delta` percent
  function stepBrightness(delta) {
    for (const s of root.screens) root.setBrightness(s, s.pct + delta);
  }
  function setBrightness(s, pct) {
    const v = Math.max(1, Math.min(100, Math.round(pct)));
    root.osdBright = { label: root.screens.length > 1 ? s.label : "", pct: v };
    root.brightnessBumped();
    if (root.sim) { root.fakeDo("brightness", s.id, v); return; }
    const p = Object.assign({}, root.pending);
    p[s.id] = v;
    root.pending = p;
    brightWrite.restart();
  }
  // Written at most every 300 ms: a DDC write is 60–250 ms of the GPU
  // driver's time (measured, 2026-10-20), and a slider dragged across fires
  // dozens; the last value always lands, being the one still pending
  Timer {
    id: brightWrite
    interval: 300
    onTriggered: {
      if (brightProc.running) { brightWrite.restart(); return; }
      const ids = Object.keys(root.pending);
      if (ids.length === 0) return;
      const cmds = [];
      for (const id of ids) {
        const v = root.pending[id];
        if (id.startsWith("bl:")) cmds.push("brightnessctl -q -d " + Strings.shellQuote(id.slice(3)) + " set " + v + "%");
        else {
          const d = root.ddcDisplays.find((x) => "ddc:" + x.bus === id);
          if (d) cmds.push("ddcutil --bus " + d.bus + " setvcp 10 " + Math.round(v * d.max / 100) + " --noverify");
        }
      }
      brightProc.written = root.pending;
      brightProc.command = ["sh", "-c", cmds.join("; ")];
      brightProc.running = true;
    }
  }
  Process {
    id: brightProc
    property var written: ({})
    onExited: {
      // what was written lands in the state the sliders read; anything
      // moved since stays pending for the next write
      const left = {};
      for (const id of Object.keys(root.pending))
        if (root.pending[id] !== brightProc.written[id]) left[id] = root.pending[id];
      root.ddcDisplays = root.ddcDisplays.map((d) => {
        const v = brightProc.written["ddc:" + d.bus];
        return v === undefined ? d : Object.assign({}, d, { cur: Math.round(v * d.max / 100) });
      });
      root.pending = left;
      if (Object.keys(left).length > 0) brightWrite.restart();
      else root.reprobe();
    }
  }
  // asked once the panel has finished opening, so its arrival is not the
  // frame that waits
  property bool ddcRead: false
  Timer { id: ddcSoon; interval: Zenon.slow + 250; onTriggered: root.readDdc() }
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "monitoradded" || event.name === "monitorremoved"
          || event.name === "monitoraddedv2" || event.name === "monitorremovedv2") root.ddcRead = false;
    }
  }
  // the monitors that answer DDC, and where each one's brightness is
  function readDdc() {
    if (root.sim) return;
    if (!root.probe.display.ddcutil || ddcProc.running) return;
    root.ddcReading = true;
    ddcProc.running = true;
  }
  Process {
    id: ddcProc
    command: ["sh", "-c", "ddcutil detect --brief 2>/dev/null; echo '@@'; "
      + "for b in $(ddcutil detect --brief 2>/dev/null | sed -n 's#.*/dev/i2c-\\([0-9]*\\).*#\\1#p'); do "
      + "printf 'BUS %s ' \"$b\"; ddcutil --bus \"$b\" getvcp 10 --brief 2>/dev/null || echo; done"]
    stdout: StdioCollector {
      id: ddcOut
      waitForEnd: true
      onStreamFinished: {
        const parts = ddcOut.text.split("@@");
        const found = H.parseDdcDetect(parts[0] || "");
        const vals = {};
        for (const line of (parts[1] || "").split("\n")) {
          const m = /^BUS\s+(\d+)\s+(.*)$/.exec(line.trim());
          if (m) vals[m[1]] = H.parseVcp(m[2]);
        }
        root.ddcDisplays = found.filter((d) => !!vals[d.bus])
          .map((d) => Object.assign({}, d, vals[d.bus]));
        root.ddcReading = false;
        root.ddcRead = true;
      }
    }
  }
  // ddcutil arriving (set up from here) is a reason to look again
  Connections {
    target: root
    function onProbeChanged() {
      if (root.probe.display.ddcutil && root.probe.display.i2c && !root.ddcRead && root.holds > 0
          && !ddcProc.running && !ddcSoon.running && !root._ddcAsked) {
        root._ddcAsked = true;
        ddcSoon.restart();
      }
    }
  }
  property bool _ddcAsked: false

  // ── NIGHT LIGHT ────────────────────────────────────────────────────────
  property bool nightOn: false
  property bool nightSun: false
  property int kelvin: H.KELVIN_DEFAULT
  readonly property bool nightWanted: H.nightWanted(root.nightOn, root.nightSun, Zenon.daylight)
  readonly property bool nightActive: root.nightWanted && root.probe.display.hyprsunset
  function setNight(on) { root.nightOn = on; if (on) root.nightSun = false; root.save(); }
  function toggleNight() { root.setNight(!root.nightWanted); }
  function setNightSun(on) { root.nightSun = on; root.save(); }
  function setKelvin(k) {
    root.kelvin = H.clampKelvin(k);
    root.save();
    if (sunset.running) kelvinWrite.restart();
  }
  // hyprsunset itself, run while the night light is wanted; tethered so a
  // shell that dies takes the tint with it rather than leaving it stuck
  Process {
    id: sunset
    running: root.nightActive && !root.sim
    command: Paths.tether(["hyprsunset", "-t", String(root.kelvin)])
  }
  // a new warmth while it runs: through its own socket, not a restart
  // (a restart is a flash of full white between the two)
  Timer {
    id: kelvinWrite
    interval: 120
    onTriggered: Quickshell.execDetached(["hyprctl", "hyprsunset", "temperature", String(root.kelvin)])
  }

  // ── COLOR FILTER ───────────────────────────────────────────────────────
  // See H's COLOR FILTERS. `filter` is the one chosen, `filterFocus` asks for
  // grayscale while the bell is quiet (focusQuiet, Howler.quiet, handed in by
  // shell.qml); `filterWorn` is what the screen wears. Each change writes the
  // shader made from zoom.frag, then filter.lua, then tells zoom.lua.
  property string filter: ""
  property bool filterFocus: false
  property bool focusQuiet: false
  readonly property string filterWorn: H.filterWorn(root.filter, root.filterFocus, root.focusQuiet)
  // the filter's shader and filter.lua are yours (~/.config/zenworks/hypr);
  // zoom.frag, the shape every filter is made from, ships with the config
  readonly property string hyprDir: Oracle.zenworksDir + "/hypr"
  readonly property string hyprShippedDir: Oracle.hyprShippedDir
  function setFilter(id) { root.filter = id; root.save(); }
  function setFilterFocus(on) { root.filterFocus = on; root.save(); }
  property string _filterApplied: "?"
  onFilterWornChanged: filterApply.restart()
  // a beat, so a quiet that flickers with a timer is one change
  Timer {
    id: filterApply
    interval: 250
    onTriggered: root.applyFilter()
  }
  FileView {
    id: zoomFrag
    path: root.hyprShippedDir + "/shaders/zoom.frag"
    blockLoading: true
    printErrors: false
  }
  AtomicWriter { id: filterWriter; tag: "hermes-filter" }
  function applyFilter() {
    const id = root.filterWorn;
    if (id === root._filterApplied || root.sim) return;
    root._filterApplied = id;
    const lua = root.hyprDir + "/lua/filter.lua";
    const tell = (path) => filterWriter.write(lua, H.filterLua(path), () =>
      Quickshell.execDetached(["hyprctl", "-q", "eval", H.filterEval(path)]));
    if (id === "") { tell(""); return; }
    zoomFrag.reload();
    const src = H.filterShader(zoomFrag.text(), id);
    // zoom.frag missing or reshaped: no filter rather than a broken screen
    if (src === "") { console.warn("hermes: zoom.frag has no shape to filter; color filter not applied"); tell(""); return; }
    const path = H.filterShaderPath(root.hyprDir, id);
    filterWriter.write(path, src, (ok) => { if (ok) tell(path); });
  }

  // ── SETTINGS ───────────────────────────────────────────────────────────
  property string section: "network"
  function setSection(s) { root.section = s; root.save(); }
  FileView {
    id: settingsFile
    path: Quickshell.statePath("hermes.json")
    blockLoading: true
    printErrors: false
  }
  property string _saved: ""
  function save() { saveTimer.restart(); }
  Timer {
    id: saveTimer
    interval: 400
    onTriggered: {
      const text = H.serializeSettings({ nightOn: root.nightOn, nightSun: root.nightSun, kelvin: root.kelvin, section: root.section,
                                         filter: root.filter, filterFocus: root.filterFocus });
      if (text === root._saved) return;
      root._saved = text;
      settingsFile.setText(text);
    }
  }

  // ── SETTING A PIECE UP ─────────────────────────────────────────────────
  readonly property bool settingUp: Ceres.installing !== null || Ceres.txBusy
  property string setupKind: ""
  function setup(kind) {
    const s = H.setupOf(kind);
    if (!s) return false;
    if (root.sim) { root.fakeDo("setup", kind); return true; }
    if (root.settingUp) { root.tell("Ceres is busy with another job — try again once it is done", true); return false; }
    root.setupKind = kind;
    const asked = Ceres.install(s.pkgs, s.why, (ok, how) => {
      root.setupKind = "";
      if (ok) root.tell("Done — " + s.why.replace(/^for /, "").replace(/^to /, ""));
      else if (how !== "cancelled") root.tell("Setting up did not finish" + (Ceres.txError ? ": " + Ceres.txError : ""), true);
      root._ddcAsked = false;
      root.reprobe();
    }, s.after);
    if (!asked) { root.setupKind = ""; root.tell("Ceres could not take the job — open Ceres to see why", true); }
    return asked;
  }

  // ── THE WINDOW ─────────────────────────────────────────────────────────
  // One, built on first open and let go of when it closes (plato's rule).
  // Floating by its title (hypr/lua/rules.lua: "hermes").
  property var win: null
  LazyComponent {
    id: lazy
    source: Qt.resolvedUrl("HermesWindow.qml")
    tag: "hermes"
  }
  function open(sectionId) {
    if (sectionId && H.SECTIONS.some((s) => s.id === sectionId)) root.setSection(sectionId);
    lazy.withReady(() => {
      let fresh = false;
      if (!root.win) {
        const t0 = Date.now();
        root.win = lazy.comp.createObject(root, {});
        LagNotes.mark("hermes window", t0);
        if (!root.win) return;
        fresh = true;
      }
      const was = !fresh && root.win.visible;
      root.win.visible = true;
      if (was) Hyprland.dispatch(Hypr.focusTitle("hermes"));
    });
  }
  function retire(w) {
    if (root.win === w) root.win = null;
    if (!root.win && lazy.waiting.length === 0) lazy.comp = null;
  }

  // ── ITS .desktop ENTRY ─────────────────────────────────────────────────
  // So cynosure and artemis find it. Shipped as a file (scripts/launchers.js makes it from this).
  readonly property var launcher: Desktop.launcher("hermes", {
    Type: "Application",
    // what the launcher calls it (user, 2026-10-20); "hermes" stays a
    // keyword, so either name finds it
    Name: "Control Hub",
    GenericName: "Network and Display",
    Comment: "Wi-Fi, Bluetooth, VPN, brightness, night light, printers and scanners, in Zenworks",
    Icon: "preferences-system-network",
    Categories: ["Settings", "Network", "HardwareSettings"],
    Keywords: ["hermes", "control", "hub", "wifi", "wi-fi", "wireless", "network", "ethernet", "bluetooth", "vpn", "wireguard",
               "brightness", "night light", "display", "monitor", "printer", "printing", "scanner", "scan", "cups"],
    Exec: Desktop.execLine(Quickshell.shellDir + "/hermes/bin/hermes", ""),
    Terminal: "false",
    StartupNotify: "false",
  })

  Component.onCompleted: {
    const s = H.parseSettings(settingsFile.text());
    root.nightOn = s.nightOn;
    root.nightSun = s.nightSun;
    root.kelvin = s.kelvin;
    root.section = s.section;
    root.filter = s.filter;
    root.filterFocus = s.filterFocus;
    // seeded from what was read, so the first change is the first write
    // (FileView never re-reads its own setText — see fileview-own-write)
    root._saved = H.serializeSettings(s);
    if (root.sim) root.probe = root.sim.probe;
    root.reprobe();
    // filter.lua may still name what the last session wore
    filterApply.restart();
  }
}

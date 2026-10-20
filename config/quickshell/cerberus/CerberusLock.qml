// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// CERBERUS — the session lock, in place of hyprlock. Every value below came
// from ~/.config/hypr/hyprlock.conf, quoted beside the property it became.
//
// The lock lives inside the running shell rather than in a process of its
// own, so `locked` is just a property. That also means the escape hatch is
// `qs ipc call Cerberus unlock` from a VT — which already costs an
// authenticated login, so it gives a physical attacker nothing they did not
// already have, and it is the difference between a bad night and a lost
// session if PAM ever breaks under you.
//
// It is not only reachable from a VT: ANY process running as you in this
// session can make the same call and unlock without a password. That is a
// deliberate trust, not an oversight — code running as you already owns the
// session in every way that matters — but it means this lock guards against
// the person at the keyboard, not against your own processes.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pam
import Quickshell.Widgets
import "../morpheus"
import "../oracle"

Scope {
  id: root

  // ── hyprlock.conf, ported ────────────────────────────────────────────
  //   $font = JetBrainsMono Nerd Font Mono Medium
  readonly property string fontFamily: Zenon.faceMono
  readonly property int fontWeight: Font.Medium
  //   $monitor = DP-1 — the input field and both labels named this monitor;
  //   every other output gets background only. Named rather than fixed: which
  //   output you actually look at first is a fact about the desk, not about
  //   this shell, and effectiveWidgetMonitor below still catches a name that
  //   is not plugged in.
  readonly property string widgetMonitor: Oracle.lockWidgetMonitor
  //   general { hide_cursor = true }
  readonly property bool hideCursor: Oracle.lockHideCursor

  //   background { color = rgba(0,0,0,0.6), blur_size = 12, blur_passes = 5 }
  readonly property real shadeAlpha: Oracle.lockShade
  // THE FROST IS LIVE, AND IT IS HYPRLAND'S. misc:session_lock_xray keeps the
  // desktop rendering under the lock and misc:session_lock_blur blurs it
  // behind the lock surface (both in hypr/lua/base.lua), with the same
  // decoration.blur every window gets. It used to be a grim screenshot blurred
  // by ImageMagick at lock time: a frozen picture, and about a second of black
  // while the blur ran. The strength is now the compositor's, not this file's.
  //
  // XRAY MEANS THE SURFACE MUST COVER. Under it the desktop is really there,
  // so anything on the lock left transparent shows it — blurred, but there.
  // Only the shade below is see-through, and the curtain is opaque whenever
  // the lock is coming or going. A dead shell is still covered: Hyprland's
  // lockdead screen is drawn opaque, xray or not.
  readonly property color dark: "black"

  // ── HEAVIER WHILE LOCKED ─────────────────────────────────────────────
  // The everyday window blur (2 passes) left the desktop half-legible behind
  // the lock. Hyprland has one blur for everything, so the lock raises it
  // for its own length and puts it back — both while the screen is black,
  // so no window is ever seen changing. The size is hyprlock's blur_size 12
  // (the same dual-kawase size); Oracle's Lock frost is the passes, the
  // coarse knob — each one roughly doubles the spread.
  readonly property int frostSize: 12
  //
  // What was there is saved to a file before the first raise, and the file is
  // what gets put back: a shell that died mid-lock restores it on its next
  // start (below). flock keeps a raise and a restore fired a moment apart
  // from interleaving.
  readonly property string blurSave: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/cerberus-blur"

  function hyprBlur(size, passes) {
    return "hyprctl -q eval \"hl.config({ decoration = { blur = { size = " + size
      + ", passes = " + passes + " } } })\"";
  }

  // whether the raise is owed: a `hyprctl reload` (ThemeSync's phase change,
  // Oracle) puts base.lua's everyday blur back under a standing lock
  property bool frosted: false

  function frost(on) {
    root.frosted = on;
    const f = Strings.shellQuote(root.blurSave);
    const opt = (o) => "$(hyprctl getoption decoration:blur:" + o + " | awk 'NR==1{print $2}')";
    const script = on
      ? "[ -f " + f + " ] || echo \"" + opt("size") + " " + opt("passes") + "\" > " + f + "; "
        + root.hyprBlur(root.frostSize, Math.max(1, Oracle.lockFrost))
      : "[ -f " + f + " ] || exit 0; read s p < " + f + "; "
        + "[ -n \"$p\" ] && " + root.hyprBlur("$s", "$p") + "; rm -f " + f;
    Quickshell.execDetached(["flock", root.blurSave + ".lock", "sh", "-c", script]);
  }

  // the restore a lock that never finished still owes
  // (and the zoom it parked)
  Component.onCompleted: {
    root.frost(false);
    root.zoom(false);
  }

  Connections {
    target: Hyprland
    function onRawEvent(ev) {
      if (ev.name === "configreloaded" && root.frosted) root.frost(true);
    }
  }

  // ── HYPR ZOOM PARKED WHILE LOCKED ─────────────────────────────────────
  // cursor:zoom_factor magnifies the whole output, the lock with it. The
  // lock parks it (zoom.lua remembers the level) as the veil comes in and
  // hands it back as the veil goes out. Guarded: zoom.lua may not be loaded.
  function zoom(park) {
    const fn = park ? "zoom_park" : "zoom_unpark";
    Quickshell.execDetached(["hyprctl", "-q", "eval", "if " + fn + " then " + fn + "() end"]);
  }

  //   input-field { font_color / check_color / fail_color = rgba(223,223,221,1) }
  // ...in the CLOCK's color (user, 2026-10-20, after a turn in the accent):
  // the lock glyph, the dots, the check and the wait ripple are the clock's
  // own voice, so they wear clockFg, whatever the theme.
  readonly property color fg: clockFg
  //   the date label's own color = rgba(160,160,155,1)
  // THE LOCK SCREEN'S SECOND VOICE. The clock, the title and the play glyph
  // are the first — clockFg, white at 0.85. This is everything standing one
  // step behind them: the date, in both places it is drawn, and the artist
  // under the track. One value, because they are one role; it was a slightly
  // different gray from the artist's until the two were asked to match, which
  // is the kind of difference nobody chooses on purpose.
  // in a light theme the muted gray was too faint on the paper tint (user,
  // 2026-10-08): most of the way to the ink, still a step behind the clock
  // in a dark theme it was a fixed "#969daf" — Zenon's soft a fifth of the way
  // to muted, written out, so every other theme got Zenon's gray. Now the same
  // mix of the worn theme's slots (2026-10-20, user: the lock follows the palette)
  // The grays are the ACCENT grays (2026-10-20, user): under Follow
  // Background the plain ones are nearly colorless, so the lock read the
  // same in every theme. The windows' chrome already wears these.
  readonly property color dateFg: Zenon.light ? Zenon.mix(Zenon.ink, Zenon.accentMuted, 0.3)
    : Zenon.mix(Zenon.accentSoft, Zenon.accentMuted, 0.2)
  //   input-field { size = 20%, 10%; outline_thickness = 0; inner_color = transparent }
  readonly property real fieldWidthFrac: Oracle.lockFieldWidth
  readonly property real fieldHeightFrac: 0.10
  //   dots_size = 0.2, dots_spacing = 0.4 — both relative to the field height
  readonly property real dotsSize: 0.2
  readonly property real dotsSpacing: 0.4
  //   placeholder_text — the lock, shown while the field is empty. Read as a
  //   blank value the first time round because the terminal could not draw it;
  //   it is the same U+F456 cynosure's Lock screen row wears.
  readonly property string placeholderGlyph: "\uF456"
  //   fade_on_empty = false: an empty field keeps the placeholder rather than
  //   fading itself out, so there is always something on screen to aim at.
  readonly property bool fadeOnEmpty: false
  //   dots_text_format / fail_text / the unlocked glyph.
  //   The dot is above the BMP (U+F09DE) and is written as a literal
  //   character. It was a "\u{...}" escape, which is valid ES6 but NOT what
  //   QML's own string lexer accepts — it only takes the four-digit form — so
  //   it was silently becoming something else. A four-digit escape cannot
  //   express it either: "\uF09DE" reads as U+F09D followed by "E". A literal
  //   character is the one form with no trap in it.
  readonly property string dotGlyph: "󰧞"
  readonly property string failGlyph: "\uF00D"
  readonly property string unlockedGlyph: "\uF52A"

  //   label { text = $TIME, font_size = 16, position = 0,47, valign = bottom }
  //   ...and two pixels larger than hyprlock had it, now that it is drawn
  //   as segments rather than as type.
  readonly property int clockSize: Oracle.lockClockSize
  readonly property color clockFg: Qt.rgba(Zenon.white.r, Zenon.white.g, Zenon.white.b, 0.85)
  // The bar's clock face, worn here too. Named from Zenon rather than restated,
  // so there is one answer to "what does a clock look like in this shell".
  // Only the time takes it — DSEG has no month names in it.
  // The unlit segments are the accent's (2026-10-20): the lit ones stay ink.
  readonly property color ghostFg: Zenon.alpha(Zenon.cyan, 0.13)
  //   ...lifted from hyprlock's 47 to open the gap between the segments and
  //   the date under them, which the larger clock had closed up.
  readonly property int clockBottom: 64
  //   label { date, font_size = 12, position = 0,25, valign = bottom }
  //   ...also two larger than hyprlock had it, to keep its weight against the
  //   segments above it.
  readonly property int dateSize: Oracle.lockDateSize
  readonly property int dateBottom: 25

  // hyprlock drew the placeholder, check and fail glyphs at half the field
  // height. The field is 10% of the output, so on a 1440p screen that is a
  // 72px lock standing in the middle of the desktop. The same three symbols
  // still read from across the room at this size without dominating it.
  readonly property real glyphScale: 0.24

  // ── motion ───────────────────────────────────────────────────────────
  // TWO FADES, NEVER A CROSSFADE (the user asked, 2026-10-14). Locking, the
  // desktop goes to black under a veil, the lock goes up behind the black,
  // and only then does the lock come out of it. Unlocking is the same run
  // backwards. Every fade is a fade from or to solid black, so the session
  // is never seen through a half-faded lock, which is why this used to be a
  // hard cut.
  //
  //   veil      a black layer over every output, outside the lock — what
  //             the DESKTOP fades into and back out of
  //   curtain   black inside each lock surface, over the frost and the
  //             widgets — what the LOCK fades out of and back into
  //
  // stage:  ""  →  dimming  →  up  →  lifting  →  clearing  →  ""
  //   dimming   veil coming in; the session is still unlocked
  //   up        locked; the curtain opens once the compositor says secure
  //   lifting   curtain closing; then the veil goes black, unseen, and the
  //             lock is let go once the veil has really been drawn
  //   clearing  unlocked; the veil going out over the desktop
  //
  // The steps are Timers, not animation ends. Animations run on frames, and a
  // lock surface on an output that is asleep draws none; the escape hatch
  // must still get you out.
  // the veil is mapped for the whole run, so it never maps or unmaps visibly
  property bool covering: false
  property string stage: ""
  property real veil: 0
  property real curtain: 1
  // true for the instant a value must jump instead of fade
  property bool snap: false
  // THE LOCK ARRIVES THE WAY THE DESKTOP DOES (user, 2026-10-14): as the
  // curtain opens, the shade and the widgets settle from the background
  // arrival's zoom down to 1 — the same knob, duration and ease, so locking
  // and unlocking are one language. Only the lock's own drawing can move;
  // the frost behind it is the compositor's and stays put. Zoomed from
  // LARGER, so the shade always covers the screen on the way in. Lifting
  // is not zoomed: the unlock has the background's own arrival.
  property real rise: 1
  readonly property real riseBy: Math.max(0, Oracle.backgroundZoom - 1)
  readonly property int riseTime: Arrival.duration
  readonly property int fadeOut: 220
  readonly property int fadeIn: 320

  function jump(what, to) {
    root.snap = true;
    root[what] = to;
    root.snap = false;
  }

  Timer {
    id: dimDone
    interval: root.fadeOut
    onTriggered: {
      root.frost(true);
      root.engage();
    }
  }

  Timer {
    id: secureWait
    // The curtain opens on `secure`: by then the compositor has drawn the
    // lock on every output. Not forever, though — a lock that never says so
    // is still a lock, and a black one you cannot see the field on is worse.
    interval: 800
    onTriggered: root.openCurtain()
  }

  Timer {
    id: liftDone
    interval: root.fadeOut
    onTriggered: {
      // The veil goes black under the closed curtain. The lock is let go
      // only once every veil has drawn that frame (veilPainted): released a
      // frame early, the desktop shows for it.
      root.veilPainted = ({});
      root.jump("veil", 1);
      root.frost(false);
      root.zoom(false);
      handOff.restart();
    }
  }

  // which outputs' veils have drawn their black since the hand-off began
  property var veilPainted: ({})
  function veilFrame(name) {
    if (root.stage !== "lifting" || !handOff.running || root.veil < 1) return;
    root.veilPainted[name] = true;
    if (Object.keys(root.veilPainted).length >= Quickshell.screens.length)
      root.unlockNow();
  }

  Timer {
    id: handOff
    // the cap, should a veil never get a frame: let go anyway
    interval: 250
    onTriggered: root.unlockNow()
  }

  Timer {
    id: clearDone
    interval: root.fadeIn
    onTriggered: {
      if (root.stage !== "clearing") return;
      root.stage = "";
      root.covering = false;
    }
  }

  function openCurtain() {
    secureWait.stop();
    if (root.stage !== "up") return;
    // gone while the curtain still hides it: with xray on, the veil is drawn
    // under the lock too, and a black veil there is a black frost
    root.jump("veil", 0);
    root.curtain = 0;
    root.rise = 1;
  }


  // ── now playing awareness ────────────────────────────────────────
  // When a track is active (playing or paused) the lock's footer splits:
  // time/date slide to the bottom-right (rtl) and the track's art +
  // metadata stay on the bottom-left (ltr). Otherwise the clock stays
  // centered as before.
  readonly property bool hasTrack: NowPlaying.active && NowPlaying.title !== ""

  // ── state ────────────────────────────────────────────────────────────
  // One password buffer for the whole lock, not one per surface: every
  // output carries a key handler so typing works wherever the compositor
  // happens to have put focus, and they must all be filling the same field.
  property string pw: ""
  // "input" | "checking" | "fail" | "success"
  property string phase: "input"

  // ── the lock's ears ──────────────────────────────────────────────────
  // How many lock surfaces currently hold the keyboard. Counted rather than
  // held as a flag because the surfaces come and go with the outputs, and
  // because nothing on the way in says "your surface stopped being the
  // keyboard's" — it simply stops getting keys. Zero while locked is the one
  // state a lock screen must never be able to sit in: it renders perfectly
  // and answers nothing, which is what resuming from suspend leaves behind.
  property int keyboardHere: 0
  // Written to the trail on the EDGE, not from the guard: earGuard runs four
  // times a second while the lock is deaf, and a line each would bury the one
  // line that says when it went deaf.
  onKeyboardHereChanged: root.note("keyboard=" + root.keyboardHere)
  // every surface takes its focus back
  signal reclaim()

  // ── the way out ──────────────────────────────────────────────────────
  // pam_faillock is in this machine's system-auth stack, so a run of wrong
  // passwords stops the lock accepting the RIGHT one for unlock_time — which
  // on a lock screen means being shut out of your own session with no way to
  // say so. `faillock --reset` clears that, and needs no root here: the tally
  // is /var/run/faillock/$USER, owned by you and mode 0660.
  //
  // Offered only once the counter is actually spent. A permanently visible
  // "press this to clear your failures" is an instruction to a stranger.
  //   faillock.conf: deny= is unset, so 3 is pam_faillock's own default — and
  //   this number has to AGREE with pam's, not replace it. Setting it higher
  //   than pam's deny does not buy more attempts; it only stops the reset
  //   button appearing while the stack is already refusing you. Lower is safe
  //   and simply offers the reset early.
  //
  // SO PAM'S NUMBER IS READ, not assumed. faillock.conf's `deny =`, or 3,
  // pam_faillock's own default, when it is unset or the file is absent. 0
  // means pam never locks, and then the setting alone decides. The setting
  // can bring the button forward; it can no longer push it past pam.
  property int pamDeny: 3
  FileView {
    path: "/etc/security/faillock.conf"
    printErrors: false
    onLoaded: {
      const m = /^[ \t]*deny[ \t]*=[ \t]*(\d+)/m.exec(String(text()));
      root.pamDeny = m ? parseInt(m[1], 10) : 3;
    }
  }
  readonly property int failDeny: root.pamDeny > 0
    ? Math.min(Oracle.lockFailLimit, root.pamDeny) : Oracle.lockFailLimit
  property int failTally: 0
  readonly property bool lockedOut: root.failTally >= root.failDeny

  // The table's last column is V while a failure still counts against you,
  // and I on one that has aged out past fail_interval.
  function countValid(out) {
    let n = 0;
    for (const line of String(out || "").split("\n")) {
      if (/\sV\s*$/.test(line)) ++n;
    }
    return n;
  }

  Process {
    id: tallyProc
    command: ["faillock"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.failTally = root.countValid(text)
    }
  }

  Process {
    id: resetProc
    command: ["faillock", "--reset"]
    // re-read rather than assuming: if it failed, the hint must stay up
    onExited: tallyProc.running = true
  }

  // socordia watches this to know when it can let a suspend proceed
  // OWNED HERE, NOT AN ALIAS OF sessionLock.locked. Read directly, the
  // surface's flag is right; bound to, it never reports going up — probed
  // 2026-09-24: no change on engage, two changes (both false) on release. So
  // everything outside that asked "are we locked?" by binding was wrong:
  // earGuard never ran and ceres never forgot its password on lock. The same
  // failure pollUptime met, and the same answer: a bool this file writes.
  property bool locked: false

  // ── the trail ────────────────────────────────────────────────────────
  // Everything that goes wrong with this lock goes wrong at the one moment
  // nobody can read a log. The screen is black or it is deaf, the only way
  // out is the power button, and a reboot takes XDG_RUNTIME_DIR — and the
  // shell's own log inside it — along with the evidence of what happened.
  // Three years of "it did the thing again" and nothing to look at.
  //
  // So the dozen lines that matter go somewhere that survives the reboot you
  // had to perform to get out of it. Only the sleep edges and the lock's own
  // lifecycle, never anything typed.
  readonly property string trail: Paths.cacheDir() + "/cerberus.log"

  // How many keys the lock has been handed since it went up. The one number
  // that separates "the lock is deaf" from "the password is wrong", and it
  // cannot be read off anything else: a lock that receives nothing looks
  // exactly like a lock nobody has typed into.
  property int keysSeen: 0

  // Numbered, because each line is written by a shell of its own and two of
  // them racing to the same file land in whatever order they finish in. Four
  // events inside one second is normal here — that is the entire resume — and
  // a trail whose order cannot be trusted answers none of the questions it
  // was written to answer. The clock says when; the counter says after what.
  property int seq: 0

  function note(what) {
    root.seq++;
    Quickshell.execDetached(["sh", "-c",
      "printf '%s %04d %s\n' \"$(date -Is)\" " + root.seq + " "
        + Strings.shellQuote(String(what))
        + " >> " + Strings.shellQuote(root.trail)]);
  }

  // The monitor hyprlock named may not be plugged in. Falling back to the
  // first screen rather than rendering no input field anywhere, which would
  // be a locked session with nothing to type into.
  readonly property string effectiveWidgetMonitor: {
    // the leftmost when it is not here — see Oracle.pickScreen
    void Quickshell.screens;
    const s = Oracle.pickScreen(root.widgetMonitor);
    return s ? s.name : root.widgetMonitor;
  }

  function submit() {
    // only while the lock is up and open: an Enter during the lift would
    // start a check on a lock that is already going away
    if (root.phase !== "input" || root.stage !== "up") return;
    root.phase = "checking";
    if (!pam.start()) {
      // the stack would not even load; do not sit on a spinner forever
      root.phase = "fail";
      failReset.restart();
    }
  }

  function clearPassword() {
    root.pw = "";
  }

  function resetFaillock() {
    resetProc.running = true;
  }

  // ── caps lock ────────────────────────────────────────────────────────
  // The commonest reason a correct password is refused, and until now the lock
  // answered it with a shake and nothing else: the same cross you get for a
  // genuinely wrong password, with no way to tell the two apart.
  //
  // Asked of morpheus' CapsLock, which every password field in the shell
  // shares — how it asks, and why on the release as well as the press, is
  // written there.
  //
  // Read at four moments and not otherwise: once when the lock appears,
  // because caps may already be on; on Caps Lock's press and again on its
  // release (turning it off lands on the release); and once on a refusal,
  // which is the moment the answer is worth having.
  readonly property bool capsOn: CapsLock.on

  function engage() {
    // Once per lock, when the veil is black. The surface's own flag, read
    // directly, as lock() does — so a lock the compositor dropped can still
    // be engaged again. Already up, it must still leave `dimming`: returning
    // early there left the veil black over a lock nobody could get out of.
    if (!sessionLock.locked) {
      // closed before the surfaces exist, so they map black, and zoomed out
      // ready to arrive
      root.jump("curtain", 1);
      root.jump("rise", 0);
      sessionLock.locked = true;
    }
    root.stage = "up";
    root.locked = true;
    root.keysSeen = 0;
    CapsLock.read();
    root.note("lock:engage screens=" + Quickshell.screens.length);
    secureWait.restart();
  }

  function release() {
    // already on the way out
    if (root.stage === "lifting" || root.stage === "clearing") return;
    // nothing to let go of: lifting from here put the veil black over a live
    // desktop and faded it out again (`qs ipc call Cerberus unlock` unlocked)
    if (root.stage === "" && !sessionLock.locked) return;
    // asked before the lock was even up: just bring the desktop back
    if (root.stage === "dimming") {
      dimDone.stop();
      root.zoom(false);
      root.pollUptime = false;
      root.stage = "clearing";
      root.veil = 0;
      clearDone.restart();
      return;
    }
    // Whether keys arrived, not how many: the count is roughly the length of
    // the password, and this file outlives the lock.
    root.note("lock:release keys=" + (root.keysSeen > 0 ? "yes" : "none")
      + " keyboard=" + root.keyboardHere);
    root.pollUptime = false;
    secureWait.stop();
    root.covering = true;
    root.stage = "lifting";
    root.curtain = 1;
    liftDone.restart();
  }

  function unlockNow() {
    if (root.stage !== "lifting") return;
    handOff.stop();
    sessionLock.locked = false;
    root.locked = false;
    root.stage = "clearing";
    root.veil = 0;
    clearDone.restart();
  }

  PamContext {
    id: pam
    // hyprlock's own /etc/pam.d/hyprlock was a one-liner including this same
    // stack, and it went away with the package
    config: "system-auth"

    onPamMessage: {
      if (pam.responseRequired) pam.respond(root.pw);
    }

    onCompleted: (result) => {
      if (result === PamResult.Success) {
        root.clearPassword();
        root.phase = "success";
        successReset.restart();
        return;
      }
      root.clearPassword();
      root.phase = "fail";
      failReset.restart();
      // the one moment the answer is worth having: if this is why, say so
      CapsLock.read();
      tallyProc.running = true;
    }

    onError: (err) => {
      root.clearPassword();
      root.phase = "fail";
      failReset.restart();
    }
  }

  Timer {
    id: failReset
    // long enough to read the cross, short enough not to feel punitive
    interval: 1400
    onTriggered: if (root.phase === "fail") root.phase = "input";
  }

  Timer {
    id: successReset
    interval: 400
    // The phase STAYS "success" through the lift. Put back to "input" here,
    // the empty field's lock glyph faded in over the unlocked glyph while
    // the curtain closed (user, 2026-10-14); lock() starts the next one at
    // "input" instead.
    onTriggered: if (root.phase === "success") root.release()
  }

  // Runs the whole time the lock is up, fast while it is provably deaf and
  // slow otherwise. The slow half is the fix for the bug that survived the
  // first version of this guard.
  //
  // Resuming from suspend is where the lock goes deaf. The outputs come back
  // through a modeset and the USB keyboards through a re-enumeration, both
  // underneath a lock that never went away, and the surface Qt had made active
  // can return with no focus item in it. Everything still paints; nothing you
  // type lands.
  //
  // The first version only ran `while (locked && keyboardHere === 0)`, and that
  // predicate cannot see the failure it was written for. `keyboardHere` counts
  // Qt's own `activeFocus`, which is a CLIENT-side belief: it says which item
  // this process would route a key to, not whether the compositor is still
  // sending any. After a modeset the two disagree — Qt goes on reporting a
  // focused catcher on a surface the seat has moved on from — so the count
  // stays at one, the guard never runs, and the lock sits there deaf with its
  // recovery timer switched off. Which is exactly what was reported.
  //
  // So it runs regardless of what keyboardHere says, and asking is free:
  // forceActiveFocus() on an item that already has it does nothing at all.
  // Two speeds only so that the provably-broken case recovers in a quarter
  // second while the healthy case costs one no-op every two seconds.
  //
  // REGARDLESS OF THE COUNT, NOT REGARDLESS OF THE LOCK. Dropping the
  // `keyboardHere === 0` half of the old predicate was the fix; dropping the
  // `locked` half with it was not. Unlocked there is no lock surface to hold
  // focus, so the count is legitimately zero — which put the timer on its
  // 250ms footing forever, reclaiming four times a second and logging every
  // one of them, for the whole life of the session rather than the life of a
  // lock. The log this was written to stay legible in was the one it buried.
  Timer {
    id: earGuard
    interval: root.keyboardHere === 0 ? 250 : 2000
    repeat: true
    running: root.locked
    onTriggered: {
      // Only says so when it can actually tell something is wrong. The
      // two-second heartbeat is the case where nothing here CAN tell, and a
      // line every two seconds for the length of every lock would bury the
      // log it is meant to be legible in.
      if (root.keyboardHere === 0)
        console.log("cerberus: lock has no keyboard, reclaiming");
      root.reclaim();
    }
  }

  // The resume edge itself, handed over by socordia the moment logind says
  // PrepareForSleep(false). The heartbeat above would get there on its own
  // within two seconds, but two seconds of a lock screen ignoring your
  // password is the whole complaint — and the outputs are still coming back
  // during it, so one nudge at the instant of resume would land before the
  // surfaces it needs to nudge exist. Hence a burst across the modeset.
  function wake() {
    if (!sessionLock.locked) return;
    root.note("wake:begin keyboard=" + root.keyboardHere
      + " secure=" + sessionLock.secure
      + " screens=" + Quickshell.screens.length);
    wakeBurst.left = 20;
    wakeBurst.restart();
    root.reclaim();
  }

  Timer {
    id: wakeBurst
    interval: 150
    repeat: true
    property int left: 0
    onTriggered: {
      if (!sessionLock.locked || wakeBurst.left <= 0) {
        wakeBurst.stop();
        if (sessionLock.locked)
          root.note("wake:end keyboard=" + root.keyboardHere
            + " secure=" + sessionLock.secure
            + " screens=" + Quickshell.screens.length);
        return;
      }
      wakeBurst.left--;
      root.reclaim();
    }
  }

  // The other way the lock goes deaf. `checking` swallows keystrokes on
  // purpose — a password half-typed into a check in flight would be a mess —
  // so a PAM stack that never answers leaves a lock that cannot be typed into
  // at all. PAM has no timeout of its own; this is it. Long enough that a
  // slow stack finishes on its own, short enough that you are not locked out
  // of your own session waiting for it.
  Timer {
    id: checkGuard
    interval: 30000
    running: root.phase === "checking"
    onTriggered: {
      console.log("cerberus: pam did not answer in 30s, releasing the field");
      // End the stuck conversation too, or the next start() is refused
      // while it is still out and every later attempt fails with it.
      if (pam.active) pam.abort();
      root.clearPassword();
      root.phase = "fail";
      failReset.restart();
    }
  }

  // ── the veil ─────────────────────────────────────────────────────────
  // What the desktop fades into before the lock and back out of after it.
  // A layer of the shell's own, so it is only ever in front of the session
  // while the session is unlocked: dimming and clearing. While locked it is
  // kept at nothing, because with xray it is drawn under the lock as well.
  // Mapped for the whole run (see `covering`), never mapped black; hypr's
  // rules give it no map animation and no blur.
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: veilWin
      required property var modelData
      screen: veilWin.modelData
      visible: root.covering
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      anchors { top: true; bottom: true; left: true; right: true }
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "cerberus-veil"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      Rectangle {
        id: veilInk
        anchors.fill: parent
        color: root.dark
        opacity: root.veil
        Behavior on opacity {
          enabled: !root.snap
          NumberAnimation {
            duration: root.stage === "dimming" ? root.fadeOut : root.fadeIn
            easing.type: Easing.InOutCubic
          }
        }
      }

      // the unlock waits on this: a veil that has drawn its black
      Connections {
        target: veilInk.Window.window
        enabled: root.stage === "lifting"
        function onFrameSwapped() { root.veilFrame(veilWin.modelData.name); }
      }
    }
  }

  function lock() {
    root.pollUptime = true;
    // a lock the compositor dropped: start again from the desktop
    if (root.stage === "up" && !sessionLock.locked) root.stage = "";
    if (root.stage === "dimming" || root.stage === "up") return;
    if (root.stage === "lifting") {
      // still locked; the curtain only has to open again
      liftDone.stop();
      handOff.stop();
      root.jump("veil", 0);
      root.frost(true);
      root.zoom(true);
      root.phase = "input";
      root.stage = "up";
      root.curtain = 0;
      return;
    }
    // clearing: the session is already back, so the veil comes in again
    // from wherever it had got to
    clearDone.stop();
    root.pw = "";
    root.phase = "input";
    tallyProc.running = true;
    root.covering = true;
    root.stage = "dimming";
    root.veil = 1;
    root.zoom(true);
    dimDone.restart();
  }

  IpcHandler {
    target: "Cerberus"

    function lock(): string { root.lock(); return "locking"; }
    // the escape hatch described at the top of this file
    function unlock(): string {
      root.clearPassword();
      root.release();
      return "unlocked";
    }
    function status(): string {
      return "locked=" + sessionLock.locked + " secure=" + sessionLock.secure
        + " phase=" + root.phase
        + " keyboard=" + root.keyboardHere
        + " keys=" + (root.keysSeen > 0 ? "yes" : "none")
        + " screens=" + Quickshell.screens.length;
    }
  }

  // ── the lock itself ──────────────────────────────────────────────────

  WlSessionLock {
    id: sessionLock

    onSecureChanged: {
      root.note("lock:secure=" + sessionLock.secure);
      // drawn on every output: the lock may come out of the black now
      if (sessionLock.secure) root.openCurtain();
    }

    surface: WlSessionLockSurface {
      id: surf

      // A surface torn down and not replaced is a black output with no
      // keyboard on it, which is one of the two things this lock is reported
      // to do after a resume. If that is what happens, it says so here.
      //
      // Reported when the SCREEN arrives rather than when the surface
      // completes: quickshell assigns it a moment later, so onCompleted only
      // ever wrote "surface:+?" — a line that says one appeared without
      // saying where, which on a two-output resume is the whole question.
      // Said once per output, not once per notification: the screen property
      // settles over two changes and a trail that reports every surface twice
      // is a trail you have to count before you can read.
      property string noted: ""
      onScreenChanged: {
        if (!surf.screen || surf.screen.name === surf.noted) return;
        surf.noted = surf.screen.name;
        root.note("surface:+" + surf.noted);
      }
      Component.onDestruction: root.note("surface:-"
        + (surf.screen ? surf.screen.name : "?"))
      // Transparent, so Hyprland's frost shows behind the shade. The black
      // when there is no frost to show is the curtain's.
      color: "transparent"

      readonly property bool showsWidgets:
        surf.screen && surf.screen.name === root.effectiveWidgetMonitor


      //   general { hide_cursor = true }
      // Outside the fade: the pointer must be gone the instant the lock is
      // up, not eased away over a quarter of a second.
      MouseArea {
        anchors.fill: parent
        cursorShape: root.hideCursor ? Qt.BlankCursor : Qt.ArrowCursor
        acceptedButtons: Qt.NoButton
      }

      // Every surface takes keys, not just the one with the widgets: the
      // compositor decides which output has focus, and typing into a blank
      // one must still reach the field. Outside the fade for the same reason
      // as the cursor — the keyboard is live from frame one.
      Item {
        id: catcher
        anchors.fill: parent
        focus: true

        // Reported to the root, which is the only place that can tell whether
        // ANY surface still has the keyboard. Idempotent through `counted`:
        // a surface torn down with the focus still on it must decrement once
        // and not twice, and onActiveFocusChanged may or may not have fired
        // by the time it goes.
        property bool counted: false
        function sync() {
          if (catcher.activeFocus === catcher.counted) return;
          catcher.counted = catcher.activeFocus;
          root.keyboardHere += catcher.counted ? 1 : -1;
        }
        onActiveFocusChanged: catcher.sync()
        Component.onCompleted: catcher.sync()
        Component.onDestruction: if (catcher.counted) {
          catcher.counted = false;
          root.keyboardHere--;
        }

        Connections {
          target: root
          // Unconditional, deliberately. The guarded version — only asking
          // when activeFocus was already false — could not repair the one
          // state that matters, because in that state Qt believes the focus
          // is here and the seat disagrees. Every surface claiming a focus
          // ITEM does not fight over the keyboard either: forceActiveFocus is
          // per-window, so all this does is guarantee that whichever window
          // the compositor hands the seat to has somewhere to put the keys.
          function onReclaim() { catcher.forceActiveFocus(); }
        }

        // CAPS LOCK SETTLES ON RELEASE, NOT PRESS. xkb locks a locking
        // modifier on the press but unlocks it on the release of the next
        // press, so a read on the press that turns caps OFF still sees it on
        // — measured, 2026-09-24: four presses, four reads of "on". Reading
        // again on the release sees the state both ways round.
        Keys.onReleased: (event) => {
          if (event.key === Qt.Key_CapsLock) {
            CapsLock.read();
          }
        }
        Keys.onPressed: (event) => {
          event.accepted = true;
          root.keysSeen++;
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.submit();
          } else if (event.key === Qt.Key_Backspace) {
            if (root.pw.length > 0) {
              const chars = Array.from(root.pw);
              chars.pop();
              root.pw = chars.join("");
            }
          } else if (event.key === Qt.Key_CapsLock) {
            // the compositor has already applied it by the time this arrives
            CapsLock.read();
          } else if (event.key === Qt.Key_Escape) {
            root.clearPassword();
          } else if (root.lockedOut && event.key === Qt.Key_R
                     && (event.modifiers & Qt.MetaModifier)) {
            // only once the counter is spent, so this cannot be leaned on as
            // a way to make failures free
            root.resetFaillock();
          } else if (event.text && event.text.length > 0 &&
                     !(event.modifiers & Qt.ControlModifier) &&
                     !(event.modifiers & Qt.MetaModifier)) {
            if (root.phase !== "checking" && root.stage === "up") root.pw += event.text;
          }
        }
      }

      // The curtain: over everything with a picture on it, the frost behind
      // included. Opaque whenever the lock is coming or going — see `stage`.
      Rectangle {
        anchors.fill: parent
        z: 1
        color: root.dark
        opacity: root.curtain
        // opening, it keeps time with the rise below
        Behavior on opacity {
          enabled: !root.snap
          NumberAnimation {
            duration: root.stage === "lifting" ? root.fadeOut : root.riseTime
            easing.type: root.stage === "lifting" ? Easing.InOutCubic : Zenon.ease
          }
        }
      }

      // everything with a picture on it, over the compositor's live frost
      Item {
        id: content
        anchors.fill: parent
        // eased here, on the item, from the jump/settle the root decides
        property real k: root.rise
        Behavior on k {
          enabled: !root.snap
          NumberAnimation { duration: root.riseTime; easing.type: Zenon.ease }
        }
        transform: Scale {
          origin.x: content.width / 2
          origin.y: content.height / 2
          xScale: 1 + root.riseBy * (1 - content.k)
          yScale: 1 + root.riseBy * (1 - content.k)
        }

        //   background { color = rgba(0,0,0,0.6) } — over the blur, not instead
        // In a light theme the tint is the theme's paper, not black: the
        // clock and the field are drawn in its dark ink and stand on it (the
        // user asked, 2026-10-08). The same strength either way. Dark themes
        // wear their own ground too (2026-10-20) — black only in Zenon, whose
        // ground it is; Nord's lock is Nord's night, not a black film over it.
        Rectangle {
          anchors.fill: parent
          color: Zenon.alpha(Zenon.ground, root.shadeAlpha)
        }


        // ── the widgets, on $monitor only ──────────────────────────────
        Item {
          id: field
          visible: surf.showsWidgets
          anchors.centerIn: parent
          //   input-field { size = 20%, 10% }
          // Floored, because every glyph in here is sized as a fraction of
          // this box: on the frame before the surface is configured its width
          // and height are still 0, and a font.pixelSize of 0 does not come
          // back when the real size arrives — it stays at Qt's minimum.
          width: Math.max(240, surf.width * root.fieldWidthFrac)
          height: Math.max(88, surf.height * root.fieldHeightFrac)

          //   outline_thickness = 0, inner_color = rgba(0,0,0,0): the field
          //   itself paints nothing at all — only what is in it.

          // a rejected password shoves the field aside rather than just
          // swapping a glyph; it is the one interaction that has to be felt
          // without being read
          transform: Translate { id: shake }

          SequentialAnimation {
            id: shakeAnim
            NumberAnimation { target: shake; property: "x"; to:  11; duration: Zenon.ms(55); easing.type: Easing.OutSine }
            NumberAnimation { target: shake; property: "x"; to: -11; duration: Zenon.ms(90); easing.type: Easing.InOutSine }
            NumberAnimation { target: shake; property: "x"; to:   7; duration: Zenon.ms(80); easing.type: Easing.InOutSine }
            NumberAnimation { target: shake; property: "x"; to:  -4; duration: Zenon.ms(70); easing.type: Easing.InOutSine }
            NumberAnimation { target: shake; property: "x"; to:   0; duration: Zenon.ms(60); easing.type: Easing.OutSine }
          }

          Connections {
            target: root
            function onPhaseChanged() {
              if (root.phase === "fail") shakeAnim.restart();
            }
          }

          Text {
            // NOT `state`. Every Item already has a `state` property, so that
            // id resolved to the enclosing item's state string instead of to
            // this Text — `state.pulse` came back undefined, opacity went NaN,
            // and the cross was never drawn.
            id: verdict
            anchors.centerIn: parent
            //   fail_text / unlocked. The WAIT is not a glyph any more — see
            //   the dots below.
            text: root.phase === "fail" ? root.failGlyph : root.unlockedGlyph
            color: root.fg
            font.family: root.fontFamily
            font.weight: root.fontWeight
            font.pixelSize: field.height * root.glyphScale

            opacity: (root.phase === "input" || root.phase === "checking") ? 0 : 1
            visible: opacity > 0.01
            scale: (root.phase === "input" || root.phase === "checking") ? 0.7 : 1

            Behavior on opacity { NumberAnimation { duration: Zenon.ms(150); easing.type: Easing.OutQuint } }
            Behavior on scale { NumberAnimation { duration: Zenon.ms(220); easing.type: Easing.OutBack } }
          }

          // ── the wait, as THREE DOTS ─────────────────────────────────
          // The same mark lexi waits on a look-up with — see
          // morpheus/Working.qml. It was a ripple of rings, which said the
          // same thing in a dialect nothing else in the shell speaks; "out,
          // and not back yet" should look the same wherever it is said.
          //
          // Sized off the field rather than lexi's fixed 5/7, because the
          // field scales with the monitor and a 5px dot is lost in it. The
          // gap keeps lexi's proportion to the dot, and the breathing — the
          // period, the stagger, the floor — is Working's own, untouched.
          Working {
            id: ripple
            anchors.centerIn: parent
            // NOT THE INSTANT CHECKING BEGINS.
            //
            // A correct password comes back in well under a tenth of a second,
            // so showing the wait the moment pam is asked meant a successful
            // unlock flashed it for a frame or two on its way to the open
            // lock — a burst of movement that says "working" about something
            // that has already finished, and reads as a stutter rather than as
            // feedback. A refusal is the slow case, because pam makes it slow
            // on purpose.
            //
            // So the dots are what appears when the answer does NOT come
            // straight back. A quarter of a second is past the point where a
            // success could still be pending and well short of where a wait
            // starts to feel unanswered.
            running: root.rippleDue
            ink: root.fg
            dot: Math.max(5, Math.round(field.height * 0.06))
            gap: Math.round(ripple.dot * 7 / 5)
          }

          // ── caps lock, under the lock ───────────────────────────────
          // The GLYPH ALONE, and in red. It said "caps lock is on" in the
          // warning orange below the field, which put a sentence where the
          // rest of this surface says everything in one symbol — and put it
          // far enough from the thing you are looking at to be missed.
          //
          // Under the lock rather than beside it, and measured off the field's
          // center rather than off any one of the three glyphs that live
          // there: the placeholder, the verdict and the dots all occupy that
          // center in turn, and anchoring to whichever happens to be showing
          // would move the warning as the phase changed.
          //
          // Red, which this shell reserves for what cannot be undone or what
          // is actively wrong. A password refused because of this IS wrong,
          // and the orange below is already spoken for by the lockout.
          //
          // It arrives and leaves rather than blinking — pressing the key
          // again re-reads the state and the fade runs the other way.
          // AND IT GLOWS (user, 2026-10-15): morpheus' Glow, the meter's
          // bloom, red behind the glyph — a solid source the glyph's size,
          // blurred into room twice that, breathing slowly while caps is on.
          Glow {
            id: capsGlow
            anchors.centerIn: caps
            width: caps.font.pixelSize * 2.6
            height: caps.font.pixelSize * 2.6
            sourceW: caps.font.pixelSize * 0.8
            sourceH: caps.font.pixelSize * 0.8
            soft: 40
            ink: Zenon.red
            scale: caps.scale
            property real breath: 0.75
            opacity: caps.opacity * capsGlow.breath
            visible: opacity > 0.01
            SequentialAnimation on breath {
              running: capsGlow.visible
              loops: Animation.Infinite
              NumberAnimation { to: 0.45; duration: Zenon.glowSlow; easing.type: Easing.InOutSine }
              NumberAnimation { to: 0.85; duration: Zenon.glowSlow; easing.type: Easing.InOutSine }
            }
          }
          Text {
            id: caps
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: field.height * root.glyphScale * 1.15
            text: "󰌎"
            color: Zenon.red
            // on the lock glyph's beat, with its zoom (see the placeholder)
            opacity: root.capsOn && content.k > 0.6 ? 1 : 0
            visible: opacity > 0.01
            scale: opacity > 0.5 ? 1 : 0.7
            Behavior on opacity {
              NumberAnimation { duration: Zenon.ms(180); easing.type: Easing.OutQuint }
            }
            Behavior on scale { NumberAnimation { duration: Zenon.ms(220); easing.type: Easing.OutBack } }
            font.family: root.fontFamily
            font.weight: root.fontWeight
            // Under two thirds of the lock above it: large enough to read at a
            // glance, small enough that the lock stays the thing in the middle.
            // Up from half, and set further down, at the user's ask
            // (2026-10-14).
            font.pixelSize: field.height * root.glyphScale * 0.6
          }

          //   placeholder_text — only while there is nothing typed yet
          Text {
            id: placeholder
            anchors.centerIn: parent
            text: root.placeholderGlyph
            color: root.fg
            //   fade_on_empty = false: an empty field keeps this rather than
            //   fading itself out
            // ...and it arrives on its own beat (user, 2026-10-14): held back
            // until the lock's rise is most of the way in, then its own fade
            // and OutBack zoom below, so the lock lands and THEN the glyph
            opacity: (root.phase === "input" && root.pw.length === 0
              && !root.fadeOnEmpty && content.k > 0.6) ? 1 : 0
            visible: opacity > 0.01
            scale: opacity > 0.5 ? 1 : 0.7
            Behavior on opacity { NumberAnimation { duration: Zenon.ms(150); easing.type: Easing.OutQuint } }
            Behavior on scale { NumberAnimation { duration: Zenon.ms(220); easing.type: Easing.OutBack } }
            font.family: root.fontFamily
            font.weight: root.fontWeight
            // the same size the check and fail glyphs use; all three are the
            // one symbol standing in the middle of the field
            font.pixelSize: field.height * root.glyphScale
          }

          Row {
            id: dots
            anchors.centerIn: parent
            opacity: (root.phase === "input" && root.pw.length > 0) ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: Zenon.ms(140); easing.type: Easing.OutQuint } }

            // The whole row breathes on each keystroke — a quick swell and
            // settle so feedback carries even when the row is long and one
            // more dot at the end is easy to miss. Backspace triggers it too.
            property real kick: 1
            scale: dots.kick
            // keep the row crisp while it scales
            transformOrigin: Item.Center

            SequentialAnimation {
              id: kickAnim
              NumberAnimation { target: dots; property: "kick"; to: 1.10; duration: Zenon.ms(85); easing.type: Easing.OutQuad }
              NumberAnimation { target: dots; property: "kick"; to: 1.0;  duration: Zenon.ms(260); easing.type: Easing.OutCubic }
            }

            Connections {
              target: root
              function onPwChanged() {
                if (root.pw.length > 0) kickAnim.restart();
              }
            }
            //   dots_spacing = 0.4, relative to the dot size
            spacing: field.height * root.dotsSize * root.dotsSpacing

            Repeater {
              model: root.pw.length

              delegate: Text {
                id: dot
                required property int index
                //   dots_text_format
                text: root.dotGlyph
                color: root.fg
                font.family: root.fontFamily
                font.weight: root.fontWeight
                //   dots_size = 0.2 of the field height
                font.pixelSize: field.height * root.dotsSize

                // Horizontal fade-slide-bounce: each dot slides in from the
                // left with a single OutBack overshoot (one bounce, no
                // rebound/oscillation) while fading in — crisp horizontal
                // motion instead of the previous vertical drop. Uses a
                // Translate so Row's own x layout is not fought.
                property real tx: -field.height * root.dotsSize * 0.85
                transform: Translate { x: dot.tx }
                scale: 0.7
                opacity: 0
                Component.onCompleted: {
                  Qt.callLater(() => {
                    dot.scale = 1;
                    dot.opacity = 1;
                    dot.tx = 0;
                  });
                }
                Behavior on scale {
                  NumberAnimation { duration: Zenon.ms(300); easing.type: Easing.OutBack; easing.overshoot: 1.4 }
                }
                Behavior on opacity { NumberAnimation { duration: Zenon.ms(150); easing.type: Easing.OutQuad } }
                Behavior on tx {
                  NumberAnimation { duration: Zenon.ms(320); easing.type: Easing.OutBack; easing.overshoot: 1.3 }
                }
              }
            }
          }
        }

        // Only on screen once the counter is spent. Zenon's orange, the same
        // ink the bar's bell and updates count wear — the color this shell
        // uses for "something needs you". A permanently visible "press this to
        // clear your failures" is an instruction to a stranger.
        Text {
          visible: surf.showsWidgets && root.lockedOut
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: field.bottom
          anchors.topMargin: 8
          text: "Too many attempts  \u00b7  super + r  clears the counter"
          color: Zenon.yellow
          font.family: root.fontFamily
          font.weight: root.fontWeight
          font.pointSize: root.dateSize
        }

        //   label { text = $TIME, position = 0,47, valign = bottom }
        //   Seven-segment, with every unlit segment showing behind the live
        //   ones — which is what the panel of a real clock is doing.
        //   Centered when no track; pushed to the bottom-right (rtl) when a
        //   track is active so the bottom-left can host the now-playing.
        // The clock and the uptime are centered AS A PAIR rather than the clock
        // being centered with something hung off it — otherwise adding the
        // second reading pushes the first off the middle of the screen, which
        // is the one thing its placement was about.
        Row {
          visible: surf.showsWidgets && !root.hasTrack
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: root.clockBottom
          spacing: 16

          // UPTIME FIRST, THEN THE CLOCK — the order the other lock layout
          // has always used, over on the right when a track is playing. The
          // two were mirror images of each other for no reason anyone chose.
          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.uptimeText !== ""
            text: root.uptimeText
            color: root.clockFg
            font.family: Zenon.clockFamily
            font.weight: Font.Bold
            font.pointSize: root.clockSize
          }

          // THE CLOCK'S OWN FACE, not a footnote beside it. Two readings of
          // the same kind — how long, and when — so they are set the same way
          // and the glyph between them is what says they are different
          // questions. Nothing at all until it has been read, so the pair does
          // not jump sideways a moment after the lock appears.
          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.uptimeText !== ""
            text: root.uptimeSep
            // THE SAME INK AS THE DIGITS EITHER SIDE OF IT. It was drawn in
            // ghostFg — the unlit-segment color — which made the separator
            // read as part of the clock's backing rather than as a mark
            // between two readings.
            color: root.clockFg
            font.family: root.fontFamily
            font.pixelSize: root.sepSize
          }

          Item {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(lockGhost.implicitWidth, lockTime.implicitWidth)
            height: lockTime.implicitHeight

            Text {
              id: lockGhost
              anchors.centerIn: parent
              text: "88:88"
              color: root.ghostFg
              font.family: Zenon.clockFamily
              font.weight: Font.Bold
              font.pointSize: root.clockSize
            }

            Text {
              id: lockTime
              anchors.centerIn: parent
              text: Qt.formatDateTime(clock.date, "HH:mm")
              color: root.clockFg
              font.family: Zenon.clockFamily
              font.weight: Font.Bold
              font.pointSize: root.clockSize
            }
          }
        }

        //   label { cmd[update:60000] date +"%A, %d %B %Y", position = 0,25 }
        Text {
          visible: surf.showsWidgets && !root.hasTrack
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: root.dateBottom
          text: Qt.formatDateTime(clock.date, "dddd, dd MMMM yyyy")
          color: root.dateFg
          font.family: root.fontFamily
          font.weight: root.fontWeight
          font.pointSize: root.dateSize
        }

        // ── now-playing footer ─────────────────────────────────────
        // Active track: art + metadata on the bottom-left (ltr), clock/date
        // on the bottom-right (rtl). Mirrors the mpris tooltip palette:
        // track green, artist white, album muted.
        Item {
          id: npLeft
          visible: surf.showsWidgets && root.hasTrack
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          anchors.leftMargin: 40
          anchors.bottomMargin: 30
          width: Math.min(520, surf.width * 0.46)
          height: 92

          Row {
            id: npRow
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            // The sleeve is a solid block of artwork and the text beside it is
            // now nearly as tall, so they need real air between them or they
            // read as one object. 14 was set against much smaller type.
            spacing: 22

            ClippingRectangle {
              id: npArtBox
              width: 84
              height: 84
              radius: Zenon.windowRadius
              color: Zenon.surface
              border.color: Zenon.border
              border.width: 1
              anchors.verticalCenter: parent.verticalCenter

              Image {
                id: npArt
                anchors.fill: parent
                source: NowPlaying.artUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                // same bound as the bar's copy in morpheus/NowPlayingPanel.qml:
                // the player decides how big the art is, this box decides how
                // much of it is worth decoding
                sourceSize.width: Math.ceil(npArt.width * npArt.Screen.devicePixelRatio)
                sourceSize.height: Math.ceil(npArt.height * npArt.Screen.devicePixelRatio)
                cache: false
                visible: status === Image.Ready
              }
              Text {
                anchors.centerIn: parent
                visible: npArt.status !== Image.Ready
                text: ""
                color: Zenon.muted
                font.family: root.fontFamily
                font.pixelSize: Zenon.px(28)
              }
            }

            // ── AS TALL AS THE COVER BESIDE IT ───────────────────────
            // Three rows at 15/13/12 with 2px between them came to about 58
            // against an 84px sleeve, so the text sat as a small block halfway
            // up a large square. Sized up until the column fills the art it is
            // standing next to — the sleeve is the thing setting the scale
            // here, and the type should answer to it rather than the other way
            // round.
            Column {
              anchors.verticalCenter: parent.verticalCenter
              // What is left after the sleeve and the gap, rather than a
              // number that happened to equal them — those two have moved
              // twice now and this did not follow either time.
              width: npLeft.width - npArtBox.width - npRow.spacing
              spacing: 6

              Row {
                width: parent.width
                spacing: 6

                Text {
                  id: playIcon
                  anchors.verticalCenter: parent.verticalCenter
                  // The clock's white, not a flat one: the lock screen's text
                  // all sits at the same weight against the background, and a
                  // fully opaque title beside a 0.85 clock reads as the louder
                  // of the two for no reason.
                  text: NowPlaying.playing ? "" : ""
                  color: root.clockFg
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  // with the title, not with what it used to sit beside
                  font.pixelSize: Zenon.px(17)
                }

                Text {
                  id: titleText
                  width: Math.min(implicitWidth, parent.width - playIcon.implicitWidth - parent.spacing)
                  text: NowPlaying.title
                  color: root.clockFg
                  font.family: root.fontFamily
                  font.weight: Font.Bold
                  font.pixelSize: Zenon.px(19)
                  elide: Text.ElideRight
                  horizontalAlignment: Text.AlignLeft
                  verticalAlignment: Text.AlignVCenter
                }
              }

              Text {
                width: parent.width
                visible: NowPlaying.artist !== ""
                text: NowPlaying.artist
                // Between the title's white and the album's muted, so the
                // three rows read as a hierarchy rather than as two whites and
                // a gray. The same ink the date is set in — see dateFg.
                color: root.dateFg
                font.family: root.fontFamily
                font.pixelSize: Zenon.px(16)
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignLeft
              }
              Text {
                width: parent.width
                visible: NowPlaying.album !== ""
                text: NowPlaying.album
                // Muted read too faint over a light lock (user, 2026-10-09):
                // there it is a step past the artist's ink, not the full gray.
                color: Zenon.light ? Zenon.mix(Zenon.ink, Zenon.accentMuted, 0.6) : Zenon.accentMuted
                font.family: root.fontFamily
                font.pixelSize: Zenon.px(14)
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignLeft
              }
            }
          }
        }

        Item {
          id: clockRight
          visible: surf.showsWidgets && root.hasTrack
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.rightMargin: 40
          anchors.bottomMargin: root.dateBottom
          width: rightCol.implicitWidth
          height: rightCol.implicitHeight

          Column {
            id: rightCol
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            spacing: 12

            // The clock and the uptime as one right-aligned pair, the same way
            // the centered layout treats them — this corner is the other place
            // the time lives, and a reading that only appears in one of them
            // is a reading you cannot rely on being there.
            Row {
              anchors.right: parent.right
              spacing: 12

              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.uptimeText !== ""
                text: root.uptimeText
                color: root.clockFg
                font.family: Zenon.clockFamily
                font.weight: Font.Bold
                font.pointSize: root.clockSize
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.uptimeText !== ""
                text: root.uptimeSep
                color: root.clockFg
                font.family: root.fontFamily
                font.pixelSize: root.sepSize
              }

            Item {
              anchors.verticalCenter: parent.verticalCenter
              width: Math.max(ghostR.implicitWidth, timeR.implicitWidth)
              height: timeR.implicitHeight
              Text {
                id: ghostR
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "88:88"
                color: root.ghostFg
                font.family: Zenon.clockFamily
                font.weight: Font.Bold
                font.pointSize: root.clockSize
                horizontalAlignment: Text.AlignRight
              }
              Text {
                id: timeR
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(clock.date, "HH:mm")
                color: root.clockFg
                font.family: Zenon.clockFamily
                font.weight: Font.Bold
                font.pointSize: root.clockSize
                horizontalAlignment: Text.AlignRight
              }
            }
            }

            Text {
              anchors.right: parent.right
              text: Qt.formatDateTime(clock.date, "dddd, dd MMMM yyyy")
              color: root.dateFg
              font.family: root.fontFamily
              font.weight: root.fontWeight
              font.pointSize: root.dateSize
              horizontalAlignment: Text.AlignRight
            }
          }
        }
      }
    }
  }

  // ── HOW LONG THIS MACHINE HAS BEEN UP ─────────────────────────────────
  // Beside the time, because the two answer the same shape of question and
  // the lock screen is where you most often want the second one: you came
  // back to a machine and the first thing worth knowing is whether it is the
  // one you left.
  //
  // From /proc/uptime rather than `uptime -p`, which says "up 3 days, 4 hours,
  // 12 minutes" — a sentence, next to a seven-segment clock. Two units is as
  // much as anyone reads off a glance.
  property string uptimeText: ""
  // The mark between the two readings, in the digits' own ink (see the Text
  // that draws it).
  readonly property string uptimeSep: "󱑼"
  readonly property int sepSize: 20

  // WRITTEN FOR A SEVEN-SEGMENT FACE, because that is the face it wears.
  //
  // DSEG7 has no "m" — seven segments cannot make one, and it comes out as an
  // "n". So the unit is carried by a single letter the display CAN form, used
  // as the separator between the two numbers rather than as a suffix after
  // each: "3h41" and "2d07" instead of "3h 41m". It reads as a duration
  // precisely because a clock never has a letter in the middle of it.
  function formatUptime(secs) {
    const s = Math.max(0, Math.floor(secs));
    if (!isFinite(s)) return "";
    const pad = (n) => (n < 10 ? "0" + n : String(n));
    const d = Math.floor(s / 86400);
    const h = Math.floor((s % 86400) / 3600);
    const m = Math.floor((s % 3600) / 60);
    if (d > 0) return d + "d" + pad(h);
    return h + "h" + pad(m);
  }

  Process {
    id: uptimeProc
    command: ["sh", "-c", "cut -d. -f1 /proc/uptime"]
    stdout: StdioCollector {
      id: uptimeOut
      waitForEnd: true
      onStreamFinished:
        root.uptimeText = root.formatUptime(parseInt(String(uptimeOut.text).trim(), 10))
    }
  }

  // True once `checking` has lasted long enough to be worth drawing — see the
  // dots. Cleared the moment the phase moves on, so a refusal followed by a
  // second attempt starts the wait over rather than showing the dots at once.
  property bool rippleDue: false

  Timer {
    id: rippleDelay
    interval: 250
    onTriggered: root.rippleDue = (root.phase === "checking")
  }

  Connections {
    target: root
    function onPhaseChanged() {
      if (root.phase === "checking") {
        root.rippleDue = false;
        rippleDelay.restart();
      } else {
        rippleDelay.stop();
        root.rippleDue = false;
      }
    }
  }

  // Only while the lock is up, and only once a minute — it is measured in
  // hours and nothing on this surface is watching the seconds.
  // Driven by a plain property that lock() and release() set, NOT by a
  // binding on sessionLock.locked. That binding evaluated false and never
  // moved — the surface's own lock flag does not notify this far out — so the
  // timer never started and the reading was never taken. A bool this file
  // owns and writes is the one thing certain to report a change.
  property bool pollUptime: false

  Timer {
    interval: 60000
    repeat: true
    triggeredOnStart: true
    running: root.pollUptime
    onTriggered: uptimeProc.running = true
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    enabled: true
  }
}

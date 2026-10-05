// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ── THE SCROLL RULE ─────────────────────────────────────────────────────
// Finder's rubber band, and the smooth wheel step that goes with it, in one
// place. Every scrollable surface in this shell should reach it through
// here or through ElasticScroll, which wraps it; a second copy of these
// numbers anywhere is the bug this file exists to prevent.
//
// WHY IT IS NOT JUST A boundsBehavior. Flickable overshoots for DRAG and
// FLICK gestures. A wheel event is neither — QQuickFlickable moves contentY
// and clamps it — so on a mouse there is no rubber band at any setting.
// The clamp is where the band lives instead: whatever it throws away is
// exactly how far past the edge the wheel asked to go.
//
// WHY IT IS NOT A WheelHandler. One declared inside a Flickable never fires
// at all: Flickable's default property parents non-Item children to
// contentItem as a plain QObject, so the handler is registered on nothing.
// Verified with a logging handler inside the very view whose wheel events
// were visibly scrolling it. The wheel has to be caught by a MouseArea laid
// over the view — see ElasticScroll.

import QtQuick
import "."
import "scrollfeel.js" as Feel

QtObject {
  id: elastic

  // ── ONE AXIS PER INSTANCE ─────────────────────────────────────────────
  // Down a list, or ACROSS a strip (a filmstrip, a tab row, a path trail):
  // the same feel either way, so a sideways view is an Elastic with this
  // on (ElasticScroll's `horizontal`), not a second implementation. Every
  // position below goes through these, so nothing else knows which.
  property bool horizontal: false
  readonly property string prop: elastic.horizontal ? "contentX" : "contentY"
  function at(v) { return elastic.horizontal ? v.contentX : v.contentY; }
  function put(v, p) { if (elastic.horizontal) v.contentX = p; else v.contentY = p; }
  function span(v) { return elastic.horizontal ? v.width : v.height; }

  // How far one notch travels when the caller does not say. A tenth of the
  // view, floored so a short list still moves usefully.
  function notchFor(v) {
    return Math.max(48, Math.round(elastic.span(v) * 0.10));
  }

  // ── APPLE'S RUBBER BAND, EXACTLY ──────────────────────────────────────
  //     f(x, d, c) = (x * d * c) / (d + c * x)        c = 0.55
  // x is how far past the edge the wheel has asked to go and d is the
  // height of what is being scrolled, so the first pixels come easily and
  // the hundredth costs almost nothing.
  readonly property real c: 0.55

  function pull(x, d) {
    return (x * d * elastic.c) / (d + elastic.c * x);
  }

  // ── HOW FAR IT MAY GO ─────────────────────────────────────────────────
  // The curve self-limits at d/c, which is nearly twice the viewport. That
  // is right for a finger, which runs out of screen, and wrong for a wheel,
  // which does not: spinning at the edge would wind the content most of the
  // way off and then take the whole settle to bring it back, so the reply
  // to "there is no more" got slower the harder you asked.
  //
  // A tenth of the view says the same thing and lets go at once. Inverting
  // f gives the raw distance that lands exactly on it, so the clamp applies
  // to what the wheel ASKED for — clamp the drawn value instead and `raw`
  // climbs invisibly, and the band then ignores the first several notches
  // of the way back.
  function maxRaw(d) {
    const b = d * 0.10;
    return (b * d) / (elastic.c * (d - b));
  }

  // ── STATE ─────────────────────────────────────────────────────────────
  // One set, not one per view: a wheel belongs to one surface at a time and
  // there is no gesture that can band two at once.
  property var band: null            // the view currently stretched
  property real raw: 0               // what the wheel has asked for, past the edge
  property bool atTop: true

  // ── AN EDGE ANSWERS ONCE ──────────────────────────────────────────────
  // Capping the stretch stopped it growing without bound, and left a worse
  // thing behind: at the end of a list every further notch still began a
  // fresh stretch-and-settle. Measured off a capture of the archive
  // viewer, the settle reads as -16, -12, -10, -6, -3, -1 — 48px back, the
  // cap exactly — and then again, and again, for as long as the wheel
  // turns. Scrolling forward was perfectly steady right up to that point,
  // so what felt like momentum draining away was the band pushing back.
  //
  // A rubber band is a reply to "there is no more", and a reply is worth
  // giving once. Spent after it settles, and only a notch travelling back
  // INTO the content clears it — so the next time you arrive at that edge
  // you get the bounce again, and leaning on the wheel there is quiet.
  property bool spent: false

  // ── THE TOP IS originY, NOT 0 ─────────────────────────────────────────
  // For a Flickable they are the same number. For a ListView they are not
  // once rows above the viewport change height: the view keeps the rows
  // where they are and moves its ORIGIN instead, and "clamp to 0" then
  // parks the list some distance below its own first row — which is quick
  // look's folder listing opening with its top rows cut off, because its
  // row pitch is re-derived for every folder. Every bound below is
  // measured from here.
  // AND THE MARGINS ARE PART OF THE ROOM: a list with a leftMargin (the
  // filmstrip) starts that far before its origin and ends that far past.
  function lo(v) {
    return elastic.horizontal ? (v.originX || 0) - (v.leftMargin || 0)
                              : (v.originY || 0) - (v.topMargin || 0);
  }
  function hi(v) {
    const room = elastic.horizontal
      ? v.contentWidth + (v.leftMargin || 0) + (v.rightMargin || 0) - v.width
      : v.contentHeight + (v.topMargin || 0) + (v.bottomMargin || 0) - v.height;
    return elastic.lo(v) + Math.max(0, room);
  }

  // Forget anything in flight for this view — a notch still travelling, a
  // band, a settle — so a caller that is about to reposition it outright is
  // not overruled a frame later by an ease aimed at the old content.
  function halt(v) {
    if (!v) return;
    if (glide.target === v) glide.stop();
    if (coast.target === v) coast.stop();
    if (bounce.target === v) bounce.stop();
    if (settle.target === v) settle.stop();
    elastic.fingerRaw = 0;
    if (elastic.band === v) { elastic.raw = 0; elastic.band = null; idle.stop(); }
  }

  // ── THE ONE ENTRY POINT ───────────────────────────────────────────────
  // Every notch, banded or not, goes through here.
  function scroll(v, delta) {
    if (!v) return;
    const top = elastic.lo(v);
    const most = elastic.hi(v);
    const from = (glide.running && glide.target === v) ? glide.goal : elastic.at(v);

    // Any movement back into the content means the edge is behind us: the
    // next arrival at one is a new question and deserves an answer.
    if ((elastic.atTop && delta > 0) || (!elastic.atTop && delta < 0))
      elastic.spent = false;

    // ALREADY BANDED means the whole notch belongs to the band. Working it
    // out from `from` would measure it against a contentY the band has
    // already pushed out of bounds and count the stretch twice.
    const banded = elastic.band === v && elastic.raw > 0;
    let to, lost;
    if (banded) {
      to = elastic.atTop ? top : most;
      lost = delta;
    } else {
      const asked = from + delta;
      to = Math.max(top, Math.min(most, asked));
      lost = asked - to;
    }

    // ── IT TRAVELS THERE, IT DOES NOT ARRIVE ────────────────────────────
    // The banded position is just another target for the same animation.
    // Writing contentY outright instead — while ordinary scrolling went
    // through the animation — made the notch that reached the edge stop
    // mid-flight and teleport to the stretch: a scroll, a hitch, then a
    // band. That gap is what reads as snappy, and it is not the settle's
    // fault.
    let want = to;
    if (most > top && (lost !== 0 || banded)) {
      const b = elastic.take(v, lost, to);
      if (b === b) want = b;          // NaN when the band declined it
    }

    if (want === elastic.at(v) && !glide.running) return;
    coast.stop();
    glide.aim(v, want);
  }

  // ── A WHEEL EVENT, WHATEVER SENT IT ───────────────────────────────────
  // What ElasticScroll (and terminus' own listing) hand over. A mouse
  // wheel's notch is `step` px, worth more the faster the notches come
  // (scrollfeel's wheelGain); a touchpad's fingers are followed exactly
  // and, let go, the content coasts (see `finger` below). Returns false for
  // an event with nothing in it, which the caller declines.
  readonly property var _rate: Feel.makeRate()
  function wheel(v, w, step) {
    if (!v) return false;
    // across a strip, either way the wheel or the fingers go means along
    // it (there is only the one axis); down a list, only up and down do
    const pick = (a) => elastic.horizontal ? (a.y !== 0 ? a.y : a.x) : a.y;
    const pd = pick(w.pixelDelta);
    // a touchpad says which part of the gesture this is; a wheel does not
    if (w.phase !== Qt.NoScrollPhase && (pd !== 0 || w.phase === Qt.ScrollEnd))
      return elastic.finger(v, w.phase, -pd);
    const notches = pick(w.angleDelta) / 120;
    if (notches === 0) return false;
    const rate = Feel.rateAdd(elastic._rate, Date.now(), notches);
    elastic.scroll(v, -notches * step * Feel.wheelGain(rate));
    return true;
  }

  // ── THE FINGERS ───────────────────────────────────────────────────────
  // Down: the content goes exactly where they take it, and past an edge it
  // stretches by the band's curve (the same pull, the same cap). Up: from a
  // stretch it settles back; otherwise it keeps the fingers' speed and
  // slows as UIScrollView does, and a coast that reaches an edge bounces.
  // A compositor that sends its own momentum (ScrollMomentum) is followed
  // like the fingers, and no second coast is added to it.
  readonly property var _track: Feel.makeTrack()
  property real fingerRaw: 0
  function finger(v, phase, d) {
    const now = Date.now();
    const top = elastic.lo(v), most = elastic.hi(v);
    const h = Math.max(1, elastic.span(v));
    if (phase === Qt.ScrollBegin) {
      glide.stop(); coast.stop(); settle.stop(); bounce.stop();
      elastic._track.at = []; elastic._track.d = [];
      elastic.fingerRaw = 0;
    }
    if (phase === Qt.ScrollEnd) {
      if (elastic.fingerRaw > 0) { elastic.settleBack(v); return true; }
      const vel = Feel.clampVelocity(Feel.trackVelocity(elastic._track, now));
      if (Math.abs(vel) > Feel.REST && most > top) coast.launch(v, vel);
      return true;
    }
    if (d === 0) return true;
    glide.stop(); coast.stop(); settle.stop();
    if (phase !== Qt.ScrollMomentum) Feel.trackAdd(elastic._track, now, d);
    if (most <= top) return true;
    // stretched: the move is the band's, in or out
    if (elastic.fingerRaw > 0) {
      const out = elastic.atTop ? -d : d;
      elastic.fingerRaw = Math.max(0, Math.min(elastic.maxRaw(h), elastic.fingerRaw + out));
      const b = elastic.pull(elastic.fingerRaw, h);
      elastic.put(v, elastic.atTop ? top - b : most + b);
      return true;
    }
    const asked = elastic.at(v) + d;
    const to = Math.max(top, Math.min(most, asked));
    elastic.put(v, to);
    if (asked !== to && phase !== Qt.ScrollMomentum) {
      elastic.atTop = asked < top;
      elastic.fingerRaw = Math.min(elastic.maxRaw(h), Math.abs(asked - to));
      const b = elastic.pull(elastic.fingerRaw, h);
      elastic.put(v, elastic.atTop ? top - b : most + b);
    }
    return true;
  }
  // back from past an edge, on the settle the wheel's band uses
  function settleBack(v) {
    elastic.fingerRaw = 0;
    glide.stop(); coast.stop();
    settle.target = v;
    settle.to = elastic.atTop ? elastic.lo(v) : elastic.hi(v);
    settle.restart();
  }

  // `lost` is the distance the clamp discarded — negative past the top,
  // positive past the bottom. Returns the contentY the band wants, or NaN
  // when it has nothing to say and the plain clamped target should stand.
  function take(v, lost, clamped) {
    const banded = elastic.band === v && elastic.raw > 0;
    if (lost === 0 && !banded) return NaN;
    // Already answered at this edge — see `spent`.
    if (elastic.spent && !banded) return NaN;
    // A different surface under the wheel: let the old one go rather than
    // dragging its band along.
    if (elastic.band && elastic.band !== v) elastic.letGo();

    settle.stop();
    if (elastic.band !== v) {
      elastic.band = v;
      elastic.raw = 0;
      // Which edge, recorded once: contentY is about to be driven past it
      // and can no longer be asked.
      elastic.atTop = clamped <= elastic.lo(v) + 0.5;
    }

    // Past the top the clamp loses a NEGATIVE amount, and the band there
    // pulls the content down — so the sign is folded into "how far out",
    // which is always positive.
    const next = elastic.raw + (elastic.atTop ? -lost : lost);
    if (next <= 0) { elastic.letGo(); return NaN; }

    const d = Math.max(1, elastic.span(v));
    elastic.raw = Math.min(next, elastic.maxRaw(d));
    idle.restart();
    const b = elastic.pull(elastic.raw, d);
    const bound = elastic.atTop ? elastic.lo(v) : elastic.hi(v);
    return bound + (elastic.atTop ? -b : b);
  }

  function letGo() {
    const v = elastic.band;
    elastic.raw = 0;
    elastic.band = null;
    idle.stop();
    // Exactly on the bound, and only when nothing is still animating it:
    // settle calls this on the frame it finishes, and writing contentY out
    // from under an animation that is winding down ends the scroll with a
    // twitch.
    if (v && !settle.running && !glide.running) {
      elastic.put(v, Math.max(elastic.lo(v), Math.min(elastic.hi(v), elastic.at(v))));
    }
  }

  // ── THE WHEEL MOVES RATHER THAN JUMPS ─────────────────────────────────
  // Setting contentY outright covers the distance instantly, and at a tenth
  // of a view per notch that reads as a teleport: nothing travels, so there
  // is nothing for the eye to follow and you arrive having lost your place.
  //
  // ONE animation, retargeted, rather than one per view — two racing on the
  // same property is how a list ends up stuttering. Consecutive notches
  // accumulate from where it is GOING, not from where it is, or spinning
  // the wheel restarts the journey every notch and covers a fraction of
  // what was asked for.
  readonly property Timer _idle: Timer {
    id: idle
    // Just longer than the stretch itself, so the band reaches full
    // stretch before it starts coming back rather than being cut off
    // halfway and reversed. A wheel has no "finger lifted"; a short
    // silence is the end of the gesture.
    interval: 150
    onTriggered: {
      const v = elastic.band;
      if (!v) return;
      glide.stop();
      settle.target = v;
      settle.to = elastic.atTop ? elastic.lo(v) : elastic.hi(v);
      settle.restart();
    }
  }

  //
  // NOT A FIXED EASE, A FOLLOW. A 130 ms OutCubic restarted on every notch
  // starts fast every notch: spinning the wheel was a lurch per click. The
  // view now closes on the target exponentially (scrollfeel's follow), so
  // a notch added mid-flight only moves where it is heading.
  readonly property FrameAnimation _glide: FrameAnimation {
    id: glide
    property var target: null
    property real goal: 0
    function aim(v, to) {
      glide.target = v;
      glide.goal = to;
      if (!glide.running) glide.start();
    }
    onTriggered: {
      const v = glide.target;
      if (!v) { glide.stop(); return; }
      const next = Feel.follow(elastic.at(v), glide.goal, glide.frameTime * 1000);
      elastic.put(v, next);
      if (next === glide.goal) glide.stop();
    }
  }

  // ── THE COAST ─────────────────────────────────────────────────────────
  // After the fingers lift: the speed they had, decaying (scrollfeel's
  // coastStep). An edge it reaches stops it there and throws the content
  // out by what that speed was worth (bounceFor), then the settle.
  readonly property FrameAnimation _coast: FrameAnimation {
    id: coast
    property var target: null
    property real vel: 0
    function launch(v, vel) {
      coast.target = v;
      coast.vel = vel;
      coast.start();
    }
    onTriggered: {
      const v = coast.target;
      if (!v) { coast.stop(); return; }
      const s = Feel.coastStep(coast.vel, Math.min(64, coast.frameTime * 1000));
      const top = elastic.lo(v), most = elastic.hi(v);
      const asked = elastic.at(v) + s.d;
      if (asked < top || asked > most) {
        coast.stop();
        elastic.atTop = asked < top;
        const edge = elastic.atTop ? top : most;
        const b = Feel.bounceFor(coast.vel, elastic.pull(elastic.maxRaw(elastic.span(v)), elastic.span(v)));
        elastic.put(v, edge);
        bounce.target = v;
        bounce.to = elastic.atTop ? edge - b : edge + b;
        bounce.restart();
        return;
      }
      elastic.put(v, asked);
      coast.vel = s.v;
      if (s.v === 0) coast.stop();
    }
  }
  readonly property NumberAnimation _bounce: NumberAnimation {
    id: bounce
    property: elastic.prop
    duration: 110
    easing.type: Easing.OutQuad
    onFinished: if (bounce.target) elastic.settleBack(bounce.target)
  }

  // The settle, on contentY directly — the same property the stretch was
  // animated on, so letting go continues that motion rather than starting a
  // second one against it. See Zenon.elastic for the duration, and why the
  // curve has to spend it rather than front-load it.
  readonly property NumberAnimation _settle: NumberAnimation {
    id: settle
    property: elastic.prop
    duration: Zenon.elastic
    easing.type: Easing.OutCubic
    onFinished: {
      // The edge has now given its answer. Leaning on the wheel from here
      // does nothing until the content has been scrolled back into.
      elastic.spent = true;
      elastic.letGo();
    }
  }
}

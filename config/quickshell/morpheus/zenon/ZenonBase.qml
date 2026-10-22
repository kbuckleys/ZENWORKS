// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ZENON'S BASE — every token, color and helper the suite draws with,
// needing nothing but QtQuick. morpheus/Zenon.qml is the shell's
// singleton: this, fed Oracle's settings and the worn theme file.
//
// `cfg` is where every setting comes from — Oracle. Nothing in
// here reads Oracle, quickshell or a file itself.

import QtQuick

QtObject {
  id: root
  // the settings Zenon is made from: Oracle. Empty until handed one —
  // every read falls back.
  property var cfg: ({})
  // ── THEMES, AND WHY ZENON IS STILL THE ANSWER ────────────────────────
  // Every color below is read through pick(): the theme Oracle names, if it
  // has that slot as a valid hex, and ZENON's own value otherwise. So Zenon
  // is not a file that can go missing — it is the table right here, and a
  // theme is only ever a set of overrides on top of it. A theme that names
  // three colors gets those three; a file that is gone, half-written or not
  // JSON at all gets Zenon, whole. "zenon" never reads a file at all.
  //
  // A theme is themes/<name>.json in this config:
  //
  //   { "name": "Shown in oracle", "mode": "dark" | "light",
  //     "colors": { "ground": "#…", "ink": "#…", "cyan": "#…", … } }
  //
  // The slots are the keys of `zenon` below. Two of them are named for what
  // they DO, not what they are, because in a light theme they swap places:
  // `ground` is what every surface is painted on (Zenon.black) and `ink` is
  // the type set on it (Zenon.white). The old names stay — 4,500 references
  // read them — the way a terminal's "white" slot holds dark ink in a light
  // scheme. New code says Zenon.ground / Zenon.ink.
  //
  // `wash` is what a hover or a pressed row is lightened WITH (white over
  // dark glass; a light theme darkens instead), and `shadow` is what a
  // shadow is made of. Neither is ink: Zenon's ink is #dfdfdd, and every
  // wash in the shell was tuned against pure white.
  readonly property var zenon: ({
    ground:    "#000000",
    surface:   "#20242a",
    ink:       "#dfdfdd",
    muted:     "#6a707f",
    soft:      "#a2a8b5",
    red:       "#e78284",
    green:     "#b6e0a4",
    yellow:    "#fab387",
    blue:      "#9fcbfc",
    magenta:   "#c8a4e0",
    cyan:      "#9bbfbf",
    pink:      "#eebebe",
    sand:      "#e0d8a4",
    dim:       "#506060",
    sparkFill: "#339bbfbf",
    border:    "#4d45505c",
    headBg:    "#66282f36",
    selBg:     "#4d45505c",
    keyInk:    "#a2a8bc",
    card:      "#0d0e11",
    onAccent:  "#000000",
    wash:      "#ffffff",
    shadow:    "#000000"
  })

  // The theme worn: a file's (fileTheme), or under Follow Background the
  // one picasso/FollowBackground makes from the background (followTheme). {}
  // for Zenon, and for anything that did not parse. kitty and hyprland hear
  // about it through ThemeSync.
  property var fileTheme: ({})
  property var followTheme: null
  readonly property var theme: themeName === "follow" ? (followTheme || ({})) : fileTheme
  // The theme worn NOW. Oracle's choice, except under Follow Daytime, which
  // wears Oracle's Day theme between sunrise and sunset and its Night theme
  // otherwise — `daylight` is kept by chronos/SunClock. Everything reads this
  // name, so a day or night theme may be Follow Background too.
  property bool daylight: true
  readonly property string themeName: {
    const t = cfg.theme || "zenon";
    if (t !== "sun") return t;
    const pickT = daylight ? cfg.themeDay : cfg.themeNight;
    return pickT && pickT !== "sun" ? pickT : "zenon";
  }

  // ── SETTLED ──────────────────────────────────────────────────────────
  // Bumped once the theme has stopped changing. Follow Background fades from
  // one palette to the next in a handful of steps, and what is cheap to
  // repaint (every binding) takes each; what is not — plato's nvim
  // rebuilding its highlights, a preview rendered again by a process —
  // waits for this.
  property int themeEpoch: 0
  onThemeChanged: themeSettle.restart()
  onAccentOwnChanged: themeSettle.restart()
  readonly property Timer themeSettle: Timer { interval: 300; onTriggered: root.themeEpoch++ }
  readonly property bool light: theme.mode === "light"

  function pick(slot) {
    const c = theme.colors;
    const v = c ? c[slot] : undefined;
    return typeof v === "string" && /^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(v)
      ? v : zenon[slot];
  }


  // what a surface is painted on, and the type set on it — see above
  readonly property color ground: pick("ground")

  // ── THE BACKGROUND'S TINT, IF ASKED FOR ───────────────────────────────
  // The current background's accent (Picasso.accentFor), pushed here by
  // PicassoDaemon — Zenon cannot import picasso, which imports morpheus.
  // Oracle's "Background tint" mixes that much of it into the ground every
  // glass surface is laid in (floor), so the glass reads as lit by what is
  // behind it. 0, the default, is the plain ground; opaque surfaces
  // (ground itself, hintBg, menuBgSolid) are never tinted.
  property color wallAccent: "transparent"
  // Not under Follow Background: the glass is already the background's.
  readonly property color glassBase: themeName !== "follow" && cfg.wallpaperTint > 0 && wallAccent.a > 0
    ? mix(ground, Qt.rgba(wallAccent.r, wallAccent.g, wallAccent.b, 1), cfg.wallpaperTint)
    : ground
  readonly property color ink:    pick("ink")

  // The three ways the shell lays a color over something, as functions so
  // a call site states its alpha and nothing else. floor: the ground itself,
  // part see-through (a panel, a scrim). wash: a hover, a press, a rule.
  // shade: a shadow. Written out as Qt.rgba(0,0,0,a) and Qt.rgba(1,1,1,a)
  // across the shell, they were right for one theme only.
  // the type set ON an accent fill — a selected row's cyan, a kill
  // button's red, the selection in a field. Black on Zenon's pastels; a
  // theme with deep accents wants it light.
  // Under an accent of your own (below) the theme's onAccent was chosen for
  // ITS accent, not yours: the type goes to the theme's darker or lighter
  // end, whichever stands out on the color picked.
  readonly property color onAccent: {
    if (accentOwn === "") return pick("onAccent");
    const g = pick("ground"), k = pick("ink");
    const dk = lum(g) <= lum(k) ? g : k, lt = dk === g ? k : g;
    return (lum(cyan) + 0.05) / (lum(dk) + 0.05) >= (lum(lt) + 0.05) / (lum(cyan) + 0.05) ? dk : lt;
  }
  // relative luminance (WCAG), for the choice above
  function lum(c) {
    const f = (v) => v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
    return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
  }
  // ── THE THEME AS PLATO'S NVIM TAKES IT ───────────────────────────────
  // The resolved colors under Zenon's slot names, as #rrggbb (nvim's have
  // no alpha), or null for Zenon itself, which nvim already is. One answer
  // for the live editor (PlatoWindow) and for every preview rendered by
  // plato/nvim/render.lua — terminus' pane, quick look, plato's file cards.
  function nvimTheme() {
    if (accentOwn === "" && (themeName === "zenon" || !theme.colors)) return null;
    const slots = ["ground", "surface", "ink", "muted", "soft", "red", "green", "yellow",
                   "blue", "magenta", "cyan", "pink", "sand", "border"];
    const colors = {};
    for (const s of slots) colors[s] = hex(root[s]);
    return { mode: light ? "light" : "dark", colors: colors };
  }

  // ── THE GLASS RIM ────────────────────────────────────────────────────
  // A hairline of light along the top edge of a glass surface — the pill
  // and every panel morphed into it, menus, tooltips, the now-playing card
  // — the way the edge of a pane catches the light above it. Faint on dark
  // glass, bright on light glass, where a white edge is what separates the
  // pane from a pale background. A theme may set its own `rim`.
  readonly property color rim: {
    const c = theme.colors ? theme.colors.rim : undefined;
    if (typeof c === "string" && /^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(c)) return c;
    return light ? Qt.rgba(1, 1, 1, 0.7) : Qt.rgba(1, 1, 1, 0.09);
  }

  // the near-black of a card floating inside a window rather than on the
  // desktop — plato's completion menu, its floats, its toasts, the file
  // tree's menu. A shade above ground so it reads as lifted off it.
  readonly property color card:      pick("card")
  readonly property color washInk:   pick("wash")
  readonly property color shadowRgb: pick("shadow")
  function floor(a) { return Qt.rgba(glassBase.r, glassBase.g, glassBase.b, a); }
  function wash(a)  { return Qt.rgba(washInk.r, washInk.g, washInk.b, a); }
  function shade(a) { return Qt.rgba(shadowRgb.r, shadowRgb.g, shadowRgb.b, a); }
  // darken: a region that is not a shadow — a modal's scrim, a
  // recessed well, the shade under a bar a list scrolls beneath. Every theme
  // darkens for these, a light one included, but black at Zenon's strengths
  // over white paper is a gray slab, so a light theme gets half.
  // ── LIGHT GLASS IS DENSER GLASS ────────────────────────────────────
  // Every opacity in this shell was tuned as black over a blurred desktop,
  // where the blur goes DARK and type in a pastel ink stands out of it. Light
  // glass over a bright background is the opposite: the blur stays bright, so
  // at the same alpha the ink sinks into it (Buck's Latte capture of the
  // pill). A light theme closes `glassLift` of the remaining transparency:
  // 0.5 takes the pill from 0.52 to 0.76 and a panel from 0.80 to 0.90, the
  // way a light material is always the more opaque of the pair. The sliders
  // still move it; a theme can set its own lift.
  readonly property real glassLift: {
    const v = theme.glassLift;
    return typeof v === "number" && v >= 0 && v <= 1 ? v : (light ? 0.5 : 0);
  }
  function glass(a) { return a + (1 - a) * glassLift; }
  // hud: a chip that floats over a PICTURE — picasso's zoom readout, the
  // crop size, a video's controls, a monitor's name on its preview. Over an
  // image there is no blur to lean on, so it is nearly solid; light glass
  // gets its lift like every other surface. Exactly #cc000000 in Zenon.
  function hud(a) { return floor(glass(a)); }
  function darken(a) { return shade(light ? a * 0.5 : a); }
  // ── THE SUITE'S PRESS ──────────────────────────────────────────────
  // A button, a segment, a tab's ×, held down: its fill darkens and its
  // type dims, as if pushed in (user, 2026-10-15). On dark glass that is
  // shadow at 0.35 and type at 0.55. On paper the same black came out at
  // half strength (darken) — a faint gray smudge — and type at 0.55 went
  // muddy (user, 2026-10-17). A light theme presses with its own ink drawn
  // a little toward the accent, deep enough to read as pressed, and keeps
  // its type nearly whole.
  // 0.3 on paper (user, 2026-10-17): at 0.2 a plain button, resting on a
  // 0.12–0.16 wash of its own, hardly changed under the finger
  // and more accent than ink, and TRULY dark (user, 2026-10-17: a pressed
  // Cancel was a neutral gray barely deeper than its rest) — the button's
  // own accent gray (buttonRest), pushed well down toward the ink
  readonly property color pressFill: light ? alpha(mix(ink, cyan, 0.35), 0.46) : shade(0.35)
  readonly property real pressDim: light ? 0.9 : 0.55
  // a LIT button (vibrant, tinted) pressed: shadowRgb over it at this
  // opacity — its own color darkened, never a gray slab (DialogButton
  // primary, Delphi's network pill)
  readonly property real pressShade: light ? 0.25 : 0.45
  // A control that cannot act right now — off, not ready, nothing to work
  // on — fades to this, and only this. Seventeen had settled on five
  // values from 0.3 to 0.6 one by one (2026-10-22); 0.4 is Controls.Check's,
  // the one on/off. oracle/tests/disabled.js keeps new ones from drifting.
  readonly property real disabledDim: 0.4
  // A PRESSED TILE — a tab, a card, a row: a large surface, where the
  // button's press (pressFill, pressShade) reads as a hole. A lighter shadow,
  // set for each mode (user, 2026-10-19: "too dark in dark mode — we must
  // always account for both theme modes"); `lit` for one already showing
  // its highlight, which needs a touch more to show the press over it.
  // dark glass needs more shadow than paper for a press to read at all (0.16
  // vanished on oracle's dark toolbar)
  function pressTile(lit) { return shade(light ? (lit ? 0.12 : 0.08) : (lit ? 0.34 : 0.30)); }
  // a plain button at rest: a wash of the ink on dark glass; on paper the
  // window's accent gray (accentMuted), as every other gray in a window
  // leans to the accent — a black wash read as a neutral gray slab beside
  // them (user, 2026-10-17)
  function buttonRest(primary) {
    return light ? alpha(accentMuted, primary ? 0.3 : 0.24) : wash(primary ? 0.16 : 0.12);
  }
  // the lighter presses (a wash over a chip or a row) on dark glass; paper
  // shares the suite's press, as a black wash there is gray
  function pressWash(a) { return light ? pressFill : wash(a); }
  // any color at another alpha: `Qt.rgba(c.r, c.g, c.b, a)`, said once
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }
  // a color t of the way to another, alpha included. What "goes solid
  // behind a sheet" means: towards ground, which was only ever black by
  // coincidence — scaling a color's rgb down reached black in Zenon and a
  // black bar in a light theme.
  function mix(a, b, t) {
    return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
                   a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t);
  }

  // base
  readonly property color black:   ground
  readonly property color surface: pick("surface")   // lblack

  // The chrome border every morpheus surface draws around itself: the pill,
  // its tooltips, its menus, the now-playing card. Solid, it was the one part
  // of those surfaces that admitted nothing — a hard dark line around a ground
  // that is mostly the blurred desktop showing through.
  //
  // ── THE ONE BORDER ──────────────────────────────────────────────────
  // Every border in the shell, and every hairline rule, is this and only
  // this: #45505c — spoot's highlight slate — at 30%, 1px. It replaced three that had
  // drifted apart (border, border, border) and a local
  // borderColor copy in nine popups. One value, read from here, so the
  // shell cannot come apart again without someone editing this line.
  //
  // THE SPECIAL CASES, and only these, change color or width with STATE —
  // at rest each is still this border: the save field (red for a bad name,
  // yellow for Replace), focus and "on" rings in terminus and oracle, the
  // open dropdown chip, a tag swatch's own-color ring, the grid tile's open
  // flare, a critical toast's accent, chronos' running pomodoro, zeus'
  // hovered profile, the corner picker's chosen cell. A cue is not a border.
  //
  // Below hyprland's ignore_alpha on purpose — Buck's call. The note above
  // is why the old one sat over it: an edge that faint is not blurred
  // behind, so it reads as a hairline of the desktop itself.
  // The color is spoot's highlight bar (its Theme.selectedBg, #45505c) —
  // Buck's call, replacing the cyan it started as — at 30%.
  // Hyprland's window borders (hypr/lua/base.lua) are this same value, copied
  // by hand: change one, change the other.
  readonly property color border: pick("border")

  readonly property color white:   ink
  readonly property color muted:   pick("muted")   // bright_black
  // muted, lifted: labels that must read on a frosted panel (picasso's look
  // controls) — muted itself sank into the frost
  readonly property color soft:    pick("soft")

  // accents
  readonly property color red:     pick("red")
  readonly property color green:   pick("green")
  readonly property color yellow:  pick("yellow")
  readonly property color blue:    pick("blue")
  // A WEB LINK's ink: the theme's ACCENT (user, 2026-10-19 — its blue was
  // not it), everywhere one is shown — Text's linkColor, a TextEdit's
  // palette.link (else the system's #0000ff)
  readonly property color link: cyan
  readonly property color magenta: pick("magenta")
  // ACCENT COLOR (Oracle, user 2026-10-20): a color of your own over any
  // theme's accent — Follow Background's too. "" is the theme's own.
  readonly property string accentOwn: {
    const v = cfg.accentColor;
    return typeof v === "string" && /^#[0-9a-fA-F]{6}$/.test(v) ? v : "";
  }
  readonly property color cyan:    accentOwn !== "" ? accentOwn : themeAccent
  // the worn theme's accent, whatever Accent color says
  readonly property color themeAccent: pick("cyan")
  readonly property color pink:    pick("pink")   // bright_red
  readonly property color sand:    pick("sand")   // bright_yellow

  // derived surfaces — alpha over black so the compositor blur reads through
  //
  // hyprland refuses to blur under a pixel below its ignore_alpha, which is
  // 0.5 in rules.lua. That floor is the reason every ground in this file sits
  // where it does — layerBg at 0.80, menuBg at quick look's 0.60, even hoverTint chosen so
  // the row it tints composites to ~0.56 rather than falling under.
  //
  // The pill is the one surface a person can drive UNDER the floor by hand:
  // Bar opacity starts opaque (1.0, since 2026-10-15) and its slider goes down to 0.10. Every
  // step towards transparent used to hand back the blur and show the desktop
  // through sharp, which is the opposite of what asking for a see-through bar
  // is asking for. barBlur decides which side of the floor it may land on —
  // and, off, shell.qml names the surface "morpheus-bar-clear", which
  // rules.lua does not blur at all, so off means sharp at any opacity.
  // ignore_alpha in rules.lua: the alpha hyprland will not blur under.
  readonly property real blurFloor: 0.52

  readonly property color panelBg: floor(glass(
    cfg.barBlur ? Math.max(cfg.barOpacity, blurFloor) : cfg.barOpacity))

  readonly property color panelBgDeep: floor(0.7)
  readonly property color dim:        pick("dim")   // muted cyan, inactive workspace
  // dim AS TEXT (inactive workspaces, other months' days, quiet states). A
  // light theme's dim is a pale surface tone, and as ink on pale glass it was
  // all but unreadable (user, colors.png, 2026-10-08): there it is muted.
  readonly property color dimInk: light ? muted : dim

  readonly property color sparkFill: accentOwn !== "" ? alpha(cyan, 0.2) : pick("sparkFill")

  // ── a layer's own furniture ──────────────────────────────────────────
  // Every popup layer was carrying its own copy of these four hexes. They are
  // one palette, not twelve, so they live here: layerBg is a layer's ground,
  // headBg the strip its title sits on, border the hairline under it, and
  // selBg the fill of a selected or pressed row. keyInk is the ink a hint's
  // KEY is set in, against Zenon.muted for the word beside it.
  readonly property color layerBg:   floor(glass(cfg.panelOpacity))
  // A MENU's ground, which is a different question from a layer's. A layer
  // is a panel belonging to the bar and the blur behind it is most of how it
  // looks; a menu is a small card floating over whatever you were reading,
  // and at the layers' alpha the text underneath reads straight through its
  // rows. Opaque by default for that reason, and its own setting because
  // "how solid is a panel" and "how solid is a menu" are two answers.
  //
  // FROSTED, AS A BLANKET RULE. Every menu here is its own layer or popup
  // surface, so what shows through is frosted rather than sharp — and the
  // alpha is held above blurFloor, under which hyprland stops frosting and
  // the card would become a clear window onto the desktop.
  readonly property color menuBg:
    floor(glass(Math.max(blurFloor, cfg.menuOpacity)))

  // ── WHAT A MENU CARD IS ───────────────────────────────────────────────
  // There are four menus on this desktop — icarus' desktop menu, the tray's,
  // terminus' right-click menu, and CardMenu, which picasso and the settings
  // dropdowns wear — and they are meant to be one object, not four takes on
  // one idea. They had drifted: three different row heights, two separator
  // heights, two grounds, radii hardcoded in some and read from the setting
  // in others. Every one of them now reads these, so the four cannot come
  // apart again without someone editing this block.
  //
  // Routed through Zenon rather than read from Oracle directly, because
  // terminus does not import oracle and should not have to: a token is what
  // Zenon is for.
  readonly property int menuRadius:    Math.round(corner * 1.2)
  readonly property int menuWidth:     cfg.menuWidth
  readonly property int menuRowHeight: cfg.menuRowHeight
  // A WINDOW'S TOOLBAR — terminus' bar (its headH). 42 since the user's
  // 2026-10-17 call, room for back/forward and a rename ring.
  readonly property int toolbarH: 42
  // and the tab strip above it, every morpheus/TabStrip's (terminus' and
  // plato's): a little lower than the bar (user, 2026-10-18); 34 since
  // the user's 2026-10-21 call
  readonly property int tabH: 34
  // the hint strip at a window's or a panel's foot (morpheus/HintBar):
  // ceres' 40, every strip's since 2026-10-19 (user: "bar height included")
  readonly property int hintBarH: 40
  readonly property int menuSepHeight: 7
  // the labels' inset from the card's sides. Sideways only: the rows run
  // flush to the border top and bottom, the card's round clip cutting the
  // first and last bands (folio's cursor, every menu — user 2026-10-17)
  readonly property int menuCardPad:   4
  // THE TALLEST A CARD GETS: twenty-two rows, and past that it scrolls (CardBody).
  // A menu as tall as the screen — xkb's ninety-nine keyboard layouts — is
  // not a menu but a wall, and its far end was out of reach. Eighteen was
  // too few: picasso's picture menu is eighteen rows and five separators,
  // and scrolled for its last row.
  readonly property int menuMaxHeight: menuRowHeight * 22 + 2
  // The air between a row's icon and its label. The icon sits in a 16px box
  // and most Font Awesome glyphs do not fill it, so the gap reads narrower
  // than the number suggests — 8 had the two touching on the wider marks.
  readonly property int menuIconGap:   12
  // A FITTED MENU (fit: true) is as wide as its longest row and no wider
  // (user, 2026-10-18: a card held at its old fixed width showed a gutter
  // of nothing); this is only the least it may be, so a one-word menu is
  // still a card. menuFitSlack is the rounding a label must not lose to:
  // measured to the pixel, the longest one elided.
  readonly property int menuMinWidth:  120
  readonly property int menuFitSlack:  6

  // A MENU INSIDE A WINDOW, which cannot be frosted and so is not translucent.
  //
  // The layer menus — icarus', the tray's, picasso's — sit on the desktop, and
  // hyprland blurs what is behind a surface, so lowering menuOpacity there
  // frosts the background. Terminus' right-click menu is an item INSIDE the
  // terminus window: what is behind it is terminus' own rows, which no
  // compositor rule can reach. Translucent, it is a card with sharp text
  // showing through it rather than a frosted one.
  //
  // So it is solid, which is what a menu over your own work wants anyway.
  readonly property color menuBgSolid: ground

  // ── FROSTED, THE WAY QUICK LOOK IS ────────────────────────────────────
  // The ground of a surface you look THROUGH rather than read off: quick
  // look's card, and now the menus that float on their own surfaces —
  // icarus' two and terminus' right-click menu and its submenu. Hyprland
  // blurs layers and popups alike above ignore_alpha 0.5, so at this alpha
  // what shows through is frosted, never sharp.
  //
  // Only for menus that ARE their own surface. A card drawn inside another
  // window (menuBgSolid above) has that window's own text behind it, which
  // no compositor rule can blur.
  //
  // Held above blurFloor so it can never slip under the threshold and turn
  // into a hard window onto the sharp desktop.
  // The same ground as a menu, by definition — one setting, Menu opacity,
  // answers for all of them.
  readonly property color frostBg: menuBg

  // ── EVERY TOOLTIP'S GROUND ────────────────────────────────────────────
  // One answer for the two kinds there are: Tooltip (a layer, the bar's) and
  // WindowTip (a popup hung in a window — plato, the file tree, picasso,
  // oracle). Both are surfaces of their own, so hyprland frosts what is behind
  // them, as it does the menus — and both wear this, with the glass rim. The
  // user asked for frosted tooltips "across the board" (2026-10-08); a tip
  // drawn as an item INSIDE a window is out of hyprland's reach: the one
  // there is (oracle's font specimen card) frosts itself with morpheus Frost.
  readonly property color tipBg: frostBg

  // A DIALOG's corner, which is not a menu's. Terminus' cards — properties,
  // permissions, confirmations, the path bar, the app picker — are larger
  // surfaces that sit in the middle of your work, and they have always used
  // 10 where a menu uses 6. Written out seven times, and their shadows were
  // told 6 regardless: with a hollow shadow that cuts the hole SMALLER than
  // the card at each corner, leaving four dark slivers inside them.
  readonly property int dialogRadius: corner * 2
  // Hyprland's own window corner (decoration.rounding in hypr/lua/base.lua,
  // which ThemeSync writes from this). The controls inside a real window
  // round to the window they sit in, so a button never looks softer than the
  // frame around it.
  readonly property int windowRadius: corner
  // ── THE RADIUS SCALE (user, 2026-10-19; one setting 2026-10-21) ──────
  // Every corner in the suite is one of these, or `height / 2` for a capsule
  // or a circle (chips, badges, knobs, switches, thin meter bars), or 0 where
  // the square is meant. All of them are Oracle's Corner rounding times the
  // proportion they had when it was 5, so moving it moves everything and 0
  // squares everything. windowRadius above is the ROW: list bands, cells,
  // fields, inner panels; menuRadius and pillRadius are with the menus and
  // the bar. Toasts are rows (windowRadius), the OSD a dialog.
  readonly property int corner: Math.max(0, cfg.cornerRadius === undefined ? 5 : Number(cfg.cornerRadius) || 0)
  readonly property int radiusControl: Math.round(corner * 0.8)   // buttons, key-like boxes, small swatches
  readonly property int radiusCard: Math.round(corner * 1.6)      // a card inside a window: a sticky, a timer, a preview
  // ANY OTHER CORNER, written as it looks at the default (5): rad(7) is 7
  // there and follows the setting like every token above. For the odd sizes
  // the scale has no name for — a toolbar chip, a cell, a wash — so no corner
  // is a bare number that stays put when everything else moves.
  function rad(n) { return n * corner / 5; }

  // WHERE A CARD THAT HANGS OFF ANOTHER ONE GOES: its parent's right side if
  // there is room, its left if not, and clamped only when neither side fits.
  //
  // One definition. There were four — CardMenu's, and a copy in each of the
  // three icarus submenus that predate it — and the copies are where two of
  // this shell's placement bugs lived: one clamped against the SHADOW's
  // padding instead of a screen margin and held every menu 80px off the
  // edges, and one used NaN as a sentinel that a QML real does not carry.
  //
  // `gap` is how close a card may come to a screen edge. Not the shadow's
  // padding — that is decoration and may clip against the edge.
  function hingeX(parentLeft, parentW, w, screenW, gap) {
    const right = parentLeft + parentW;
    if (right + w <= screenW - gap) return right;
    const left = parentLeft - w;
    if (left >= gap) return left;
    return Math.max(gap, Math.min(right, screenW - w - gap));
  }

  // HOW A MENU ARRIVES. Every menu on this desktop grows out of its own
  // top-left corner rather than appearing at full size, so a card unfolds FROM
  // the thing that opened it instead of expanding around its own middle. The
  // numbers were written out identically in five places and the tray had none
  // of them at all — it simply blinked into existence.
  readonly property int  menuFade: fast
  readonly property real menuScaleFrom: 0.94
  function menuScale(shade) {
    return menuScaleFrom + (1 - menuScaleFrom) * shade;
  }
  readonly property color headBg:    pick("headBg")
  // THE ACTIVE TAB'S FILL (plato's and terminus' strips). headBg in a dark
  // theme; in a light one headBg is a pale tint at 40% over pale glass and
  // the active tab vanished into its neighbors (user, tab-visibility.png,
  // 2026-10-08) — there it is the ink, washed thin, which reads as a tab.
  readonly property color tabHere: light ? Qt.rgba(ink.r, ink.g, ink.b, 0.11) : headBg
  // AN INACTIVE TAB'S GLASS, given the window's alpha (plato's and terminus'
  // strips, which lay no window ground under their tabs): thinner than the
  // window's, so the desktop shows through. In a dark theme thin black glass
  // let a bright desktop light the tab up past the active one, so there it
  // is tinted deep navy as well (user's values, 2026-10-09: 60% glass against
  // the window's 80%, tint full toward rgb 10,18,40) — see-through, and
  // still the darker of the two.
  function tabAway(a) { return light ? a * 0.7 : a * 0.75; }
  // What the ACTIVE tab lays over a strip already painted with the inactive
  // glass, so the two compose to the window's own alpha `a`:
  // 1 − (1 − away)(1 − over) = a. The strip keeps a ground of its own that
  // way, and a tab cell rebuilt or still fading in never leaves a hole.
  function tabOver(a) {
    const away = tabAway(a);
    return away >= 1 ? 0 : Math.max(0, 1 - (1 - a) / (1 - away));
  }
  // The navy lift is Zenon's (user's pick, 2026-10-09). Under Follow
  // Background it lifts by about as much in the PICTURE's tint — ground
  // towards surface, which carry its hue — so a black and white background
  // gets gray glass, not blue (user, 2026-10-20).
  readonly property color tabAwayInk: light ? layerBg
    : themeName === "follow" ? mix(ground, surface, 0.55)
    : Qt.rgba(Math.min(1, ground.r + 10 / 255), Math.min(1, ground.g + 18 / 255),
              Math.min(1, ground.b + 40 / 255), 1)

  // ── THE STRIP A HINT BAR STANDS ON ────────────────────────────────────
  // Named here rather than written out in each popup — seven of them wear
  // this and they were seven copies of one answer.
  //
  // OPAQUE. It was 35% black, and it sits over the busiest part of a popup —
  // a page of translation, a grid of glyphs, a wall of graphs — so the content
  // behind it stayed legible straight through the hints. Terminus' prefix bar,
  // the row of continuations a half-typed `g` or `c` puts along the bottom,
  // had already learned this and put an opaque floor under itself.
  //
  // BLACK, and nothing over it. Tinting it with headBg first kept the strip
  // in the chrome's blue-gray family and left it reading as a panel rather
  // than as a floor — which is the one thing a hint bar must not do: it is the
  // quietest row on a popup and it stands over the busiest part of one.
  readonly property color hintBg: ground
  // ── EXCEPT OVER A FROST ───────────────────────────────────────────────
  // A hint strip with a ScrollEdge under it (rows rising out of it from
  // below) lets some of them through, the way macOS' bars do. That is not
  // the legibility problem above coming back: what shows is blurred, then
  // darkened by the edge's own scrim, then by this — no sharp glyph reaches
  // the hints. Only for strips that have one; anywhere else this is just a
  // see-through floor, which is what hintBg exists to prevent.
  readonly property color hintFrostBg: floor(glass(0.6))
  readonly property color selBg:     pick("selBg")
  readonly property color keyInk:    pick("keyInk")
  // ── THE GRAYS, IN THE ACCENT (user, 2026-10-15) ─────────────────────
  // A window's chrome — section heads, the steps behind the current crumb,
  // a count, a glyph at rest — in its theme's accent rather than a neutral
  // gray, as the cursor is: the same three grays, each drawn part of the
  // way to cyan (the accent; Follow Background's seed). Same lightness
  // order, so a muted word stays quieter than a soft one.
  readonly property real accentGreyMix: 0.4
  readonly property color accentMuted: mix(muted, cyan, accentGreyMix)
  readonly property color accentSoft:  mix(soft, cyan, accentGreyMix)
  readonly property color accentKey:   mix(keyInk, cyan, accentGreyMix)
  // and the ink itself, for the one fact a strip of accent grays leads with
  // (plato's cursor line): louder than them, still in the accent
  readonly property color accentInk:   mix(white, cyan, accentGreyMix)
  // THE MENU CURSOR: the lit row of every menu — CardBody, icarus, folio,
  // terminus' right-click and drop menus — in the theme's accent, as the
  // windows' rows already are (their hiFill, the same cyan at 0.12), not
  // the border gray it was (user, 2026-10-17). A shade stronger than the
  // windows': a menu's ground is opaque and its band runs the whole card.
  readonly property color menuHi:      alpha(cyan, 0.16)
  // ── spacing ──────────────────────────────────────────────────────────
  // Four values, and only four. padModule is a module's own breathing room,
  // gap is the space between two neighbors, padBar is the pill's end caps,
  // padScreen is the pill's clearance from the screen edge.
  // A Divider carries a gap on each side itself, so it never needs spacers.
  readonly property int padModule: cfg.barPadModule
  readonly property int gap:       cfg.barGap
  readonly property int padBar:    cfg.barPadBar
  // the clearance the pill keeps from the screen edge. Every layer reuses it,
  // so a layer spawned on a monitor that has no pill still sits exactly where
  // it would have sat morphed into one.
  readonly property int padScreen:  cfg.barScreenPad
  // Every module occupies a slot of this height, and BarText fills it, so a
  // short label beside a taller sibling still sits on the bar's center line.
  readonly property int slot:      cfg.barSlot
  // the bar's type size; every module reads it through BarText
  readonly property int textSize:  cfg.barTextSize
  // the pill and every layer's corner radius — uniform on all four corners, no
  // morph. A single token so the bar, cynosure, and all other layers stay even
  // without duped literals, and one setting moves all of them together.
  readonly property int pillRadius: Math.round(corner * 1.6)

  // ── how wide a layer may be ──────────────────────────────────────────
  // Every layer used to write 1000 into its own panel, and shell.qml wrote it
  // a second time into the width it gives the morphed pill. Those two numbers
  // MUST agree: morphed, a layer scales itself by pill width over panel width,
  // so a pill that was told 900 while the panel still believed 1000 does not
  // narrow the layer, it squashes it by a tenth.
  //
  // So there is one number, and one function that applies it. A layer asks for
  // the width it wants; both sides call this with the same argument and cannot
  // come out different.
  readonly property int layerMax: cfg.barMaxWidth
  function layerWidth(want) {
    // EVEN, ALWAYS. Every layer is centered — the pill by its own margins,
    // the rest by anchors.horizontalCenter — and centering an ODD width
    // inside an even-width monitor puts the whole panel on a half pixel.
    //
    // That is not a cosmetic half pixel. Each of these panels clips through
    // a ClippingRectangle to keep square children inside its rounded
    // corners, and a clipped subtree is drawn through a texture: sampled
    // half a pixel off, the texture is resampled and every glyph in it goes
    // soft at once. Measured side by side — the same string in the same
    // clipped box at x and at x + 0.5 — and the second is visibly smeared.
    //
    // Most widths here are literals and already even. The ones that are not
    // are the shrink-wrapped ones: cynosure's content width, chronos'
    // calendar grid, artemis' panel. Rounding down to even here fixes all of
    // them in one place. Panels that position themselves explicitly round
    // their own x instead — see ZeusPopup.
    const w = Math.min(layerMax, want);
    return 2 * Math.floor(w / 2);
  }

  // ── THE SHELL'S TYPE ─────────────────────────────────────────────────
  // One family, three cuts, and every one of them derived from a single
  // setting. Nerd Fonts ship a proportional cut, a strictly monospaced one,
  // and the plain one in between; this shell uses all three — labels are
  // proportional, the lock's clock and the mark are monospaced, and the
  // column-aligned tables in zeus and terminus need the plain fixed cut —
  // and they must be the SAME family or a panel looks like two fonts.
  //
  // The family name was written out 279 times before this. That is 279
  // places to edit to change the shell's type, and 279 chances for one of
  // them to be missed, which is exactly the kind of thing that leaves one
  // label in a corner still set in the old face.
  // A face that is not a Nerd Font has no cuts: it is all three, and its
  // icons come from JetBrainsMono Nerd Font (morpheus/GlyphFallback).
  readonly property bool nerdFace: /Nerd Font$/.test(cfg.fontFamily)
  readonly property string face:      cfg.fontFamily + (nerdFace ? " Propo" : "")
  // The weight of the shell's text wherever it does not ask for one — a
  // label set Bold or Medium keeps that. Medium by default; oracle's
  // Font weight, which picking a font file sets to that file's own cut.
  readonly property int weight: Number(cfg.fontWeight) || 500
  // A TITLE'S WEIGHT: a sidebar's place, a category, a disk's name and the
  // glyph before it, terminus' breadcrumbs — the name only, never its
  // reading (a count, a size). Bold, whatever the family (user, 2026-10-17).
  readonly property int titleWeight: Font.Bold
  // A SECTION'S LABEL: the small spaced capitals over what it heads
  // (morpheus/SectionLabel) and a list's group heads. They had drifted over
  // six spacings, three weights and three greys (2026-10-20). Size is px()'d
  // by the caller — `labelPx` for a section, a list's heads one up. Weight is
  // titleWeight: a section's name is a title.
  readonly property int  labelPx: 11
  readonly property real labelSpacing: 1.2
  // ── THE SHELL'S TEXT SIZE ──────────────────────────────────────────────
  // Oracle's Font size (the Font row's stepper), as a factor over the 16 px
  // every label was sized against. A label's size goes through px(): its own
  // number at 16, grown or shrunk with the setting — so `px(13)` stays the
  // smaller line beside `px(16)` at any size. Not the bar's (textSize), and
  // not where a window has a size of its own (plato's editor, terminus' zoom
  // multiplies on top).
  readonly property real textScale: Math.max(12, Math.min(24, Number(cfg.fontSize) || 16)) / 16
  function px(n) { return Math.max(1, Math.round(n * textScale)); }
  readonly property string faceMono:  cfg.fontFamily + (nerdFace ? " Mono" : "")
  readonly property string faceFixed: cfg.fontFamily
  // THE CODE FACE: oracle's Monospace font, not the shell's — plato, code
  // and file previews, logs, kitty (ThemeSync). A Nerd Font's Mono cut, so
  // its icons are one cell. faceFixed above is the shell's face without a
  // cut, for chrome; this one is fixed-width whatever the shell wears.
  readonly property string faceCode: (cfg.monoFamily || "SF Mono")
    + (/Nerd Font$/.test(cfg.monoFamily || "") ? " Mono" : "")
  readonly property int codeWeight: Number(cfg.monoWeight) || 600
  // THE BOX-DRAWING ART (oracle's mark, plato's start card) is set in one
  // face whatever the shell's is, as the icons are (GlyphFallback): its
  // strokes meet only in a strictly monospaced cut that has them, and in
  // a proportional face (Adwaita Sans, user 2026-10-08) they fell apart.
  readonly property string artFace: glyphMono
  // A GLYPH SET ON ITS OWN, beside a label in the shell's face: always
  // JetBrainsMono's cuts, so its size and the gap after it are what they
  // were under JetBrainsMono whatever the label is set in. A proportional
  // face's spaces are a third as wide, and its fallback glyphs a different
  // cut — tree expanders and the grid's marks crowded their labels (user,
  // 2026-10-08). glyphFace for a mark among proportional text, glyphMono
  // for one in a fixed column.
  readonly property string glyphFace: "JetBrainsMono Nerd Font Propo"
  readonly property string glyphMono: "JetBrainsMono Nerd Font Mono"

  // ── the clock's face ─────────────────────────────────────────────────
  // A seven-segment LCD, the way an old bedside clock renders. DSEG covers
  // digits, the colon and a rough alphabet, but none of the nerd glyphs the
  // rest of the bar uses — so it is named here rather than set on BarText,
  // and only the clock ever asks for it.
  readonly property string clockFamily: "DSEG7 Classic"
  // DSEG's digits stand taller than JetBrains' at the same nominal size, so
  // the clock is set two pixels smaller and still reads level with the rest
  // of the bar. Expressed against textSize rather than written out, so the
  // two cannot drift if the bar's type changes again.
  readonly property int clockSize: textSize - 2

  // ── elevation ────────────────────────────────────────────────────────
  // What a layer's drop shadow is made of. Tuned in one place so the whole
  // set stays consistent — morpheus itself casts none: the pill is the ground
  // floor, and a shadow under it would make the layers it morphs into look
  // like they were peeling off it.
  //
  // ── ONE POOL, AND THESE ARE NOW THE MENU'S ──────────────────────────
  // They used to be a second, tighter set — grow 4, blur 24, drop 6 —
  // for a reason that has since expired. A panel was a SMALL surface
  // sitting a few pixels off a screen edge, so the menu's wider reach
  // would have been clipped by the window it was drawn in; the note
  // above this one is about exactly that.
  //
  // Every surface that casts is full-output now, and the two that are
  // not reserve the pad explicitly, so there is nothing left for the two
  // sets to disagree about. Disagreeing is what made chronos and howler
  // read as a different kind of shadow from the menu beside them: a
  // tighter falloff AND, because only the menu ink was capped, a hazier
  // edge — one lamp lighting the desk two different ways.
  //
  // Kept as names rather than deleted: they say "a panel's shadow",
  // which is still a thing worth being able to say.
  readonly property color shadowInk:  menuShadowInk
  readonly property int   shadowGrow: menuShadowGrow
  readonly property int   shadowBlur: menuShadowBlur
  readonly property int   shadowDrop: menuShadowDrop
  readonly property int   shadowPad:  menuShadowPad

  // ── the shadow a MENU's BORDER casts ──
  //
  // It hangs off the EDGE, not off the body: MenuShadow is hollow, so what
  // these describe is a ring. As dark and as wide as it can be without
  // crossing the one line that matters.
  //
  // THE LIMIT IS THE INK, NOT THE SIZE. hyprland blurs any pixel above
  // ignore_alpha (0.5 in rules.lua) and cannot tell a shadow from a ground —
  // one alpha channel, one surface — so a shadow over that line gets the
  // desktop blurred behind it, and against a card too transparent to be
  // blurred itself that reads as a frosted ring. UNDER the line none of that
  // happens at any size, which is why Shadow is capped at 0.48
  // and the geometry below is not.
  //
  // SAME INK AS A PANEL'S, one setting for both, because one desktop should
  // be lit by one lamp. The GEOMETRY differs and has to: a panel is a layer
  // surface sitting a few pixels off a screen edge, so a shadow this wide
  // would be clipped by its own window and never drawn. A menu floats in the
  // middle of the screen with room around it, so it gets the full spread.
  //
  // GROW IS MOST OF WHAT MAKES IT DARK. A blurred rounded rect is only about
  // half covered at the edge of its own shape, so with a small grow the ring
  // never reaches the ink it was given — it peaked near half of it. Twenty
  // pixels of full strength before the falloff starts is the part you
  // actually see against a bright background.
  // ── AND THE CAP THE NOTE ABOVE DESCRIBES, ACTUALLY APPLIED ──────────
  // It said the ring is capped at 0.48 and then handed `shadowInk`
  // through untouched — which is Oracle's shadowStrength, 0.60 by default.
  // Over hyprland's ignore_alpha of 0.5, so every ring above that line
  // had the desktop blurred behind it: quick look's card sat in a band
  // of frosted glass instead of a shadow.
  //
  // A PANEL gets away with 0.60 because LayerShadow is FILLED — its dense
  // middle is hidden under an opaque panel and only the falloff shows. A
  // ring has no middle to hide in: what you see IS the dense part, which
  // is why this one, and only this one, has to stay under the line.
  // oracle's "Menu and sheet shadows": off, every menu's and sheet's
  // MenuShadow hides (they wear `visible: Zenon.menuShadows`)
  readonly property bool  menuShadows: cfg.menuShadows !== false
  readonly property real  menuShadowMax:  0.48
  readonly property color menuShadowInk:
    shade(Math.min(root.menuShadowMax, cfg.shadowStrength))
  readonly property int   menuShadowGrow: 20   // full strength this far out
  readonly property int   menuShadowBlur: 50   // then a long, smooth falloff
  readonly property int   menuShadowDrop: 10   // and a direction for the light
  readonly property int   menuShadowPad: menuShadowGrow + menuShadowBlur + menuShadowDrop

  // ── motion ──
  // Shared timings and curve, so every module and every layer eases
  // identically. OutQuint rather than OutCubic: it puts more
  // of the travel in the first third and lands softer, so the same move reads
  // as both quicker off the mark and gentler on arrival.
  //
  // Each is its own number times Oracle's one multiplier, so the whole shell
  // slows down or speeds up together — a layer easing at a different rate from
  // the pill it is morphing out of is the one way this shell can look broken
  // rather than merely different. At a scale of 0 they are all zero, which Qt
  // reads as "no animation": every Behavior in here then lands on frame one.
  // BELOW `fast`, for the one thing you WAIT ON. Everything on this scale
  // decorates something already on screen, so `fast` is as quick as decoration
  // needs to be. The morph is the exception: it stands between asking for a
  // panel and being able to use it, and the right length for that is the
  // shortest one that still reads as a move rather than a cut.
  // ── A PHYSICAL SETTLE, NOT A UI ANIMATION ────────────────────────────
  // How long an elastic scroll edge takes to let go. Still far longer
  // than anything else on this scale on purpose — the rest of these are
  // things being shown to you, and this is a thing with weight coming to
  // rest.
  //
  // 480, not the ~630ms Apple's own settle measures at. That figure is a
  // touchscreen's, where the band was stretched by a finger that has just
  // let go and the eye is already following it. A wheel gives the band a
  // shove and lets go in the same notch, so the same duration reads as
  // the list being slow to answer rather than as weight. Tuned by eye
  // against the real thing, which is the only way this one can be judged.
  //
  // With OutCubic that is halfway back in 99ms and still visibly moving
  // at 300 — the spread is what stops it feeling snapped, and the spread
  // is preserved by shortening the whole curve rather than steepening it.
  //
  // Here rather than in terminus for the reason menuRadius is: terminus
  // does not import oracle and should not have to, and a number times
  // Oracle's multiplier is exactly what this file is for.
  readonly property int elastic: Math.round(480 * cfg.motionScale)

  readonly property int brisk:  Math.round(75 * cfg.motionScale)
  // the step between one row's arrival and the next when a panel opens —
  // see LayerPopup.opened. Capped at eight rows by whoever staggers, so the
  // last of them is in before a hand reaches for the keys.
  readonly property int stagger: Math.round(14 * cfg.motionScale)
  readonly property int fast:   Math.round(110 * cfg.motionScale)
  readonly property int normal: Math.round(140 * cfg.motionScale)
  readonly property int slow:   Math.round(170 * cfg.motionScale)
  readonly property int ease:   Easing.OutQuint
  // any other one-off duration, times the same multiplier — so Animation
  // speed reaches a shake or a flash too, and 0 means none. Not for loops
  // (a breath or a spinner at 0 ms would spin) nor a PauseAnimation's hold.
  function ms(n) { return Math.round(n * cfg.motionScale); }

  // ── HOVER INTENT (2026-10-20) ───────────────────────────────────────
  // How long the pointer rests on a thing before its tip or peek opens, and
  // how long it may be off one before the peek goes (so crossing a gap to
  // the next row does not shut it). One pair for WindowTip and every Bubble
  // peek, which had drifted to 300, 450, 500 and 550 and to 120 and 220.
  // Not times the multiplier: a wait for intent, not motion.
  readonly property int hoverWait: 450
  readonly property int hoverLeave: 220
  // ── A BREATH: half of one cycle of the caret's breath, dim to bright or
  // back. They had drifted to 520, 550 and 620 on two curves, so a
  // launcher's caret breathed out of step with a window's (2026-10-20);
  // Caret's own 620 on InOutQuad is the one kept. Since 2026-10-22 every
  // caret IS morpheus/Caret (stepped at 30 Hz, resting when idle); besides
  // it only a drop on offer (terminus' sidebar, clio's shelf) and metis'
  // refreshing rates dot read this, briefly. oracle/tests/caret.js fails
  // any other reader as a caret drawn by hand. How dim it goes stays each
  // caller's. A loop, so off the multiplier for the reason ms() is.
  readonly property int breath: 620
  readonly property int breathEase: Easing.InOutQuad
  // a recording light: slower than a breath, so "live" never reads as
  // "waiting for you to type" (plato's macro REC, the bar's screen record)
  readonly property int beacon: 700
  // one turn of something spinning while it works — morpheus/Working's
  // period, a refresh glyph, a ring (they were 900 and 1100)
  readonly property int spin: 900
  // one pass of an indeterminate sweep along a bar: a job without a
  // percent, plato's language servers busy (1150 and 1400)
  readonly property int sweep: 1150
  // an ambient glow, half a cycle — the default button, the jobs glyph —
  // and the slower one a password field idles on (lock screen, Ceres)
  readonly property int glow: 900
  readonly property int glowSlow: 1400

  // whether morpheus/Scrollbar fades out between scrolls — read here so the
  // scrollbar's own test stub can stand in for it without importing oracle
  readonly property bool scrollAutohide: cfg.scrollbarAutohide
  // whether morpheus/ScrollEdge frosts rows past a list's edge at all
  readonly property bool scrollFrost: cfg.scrollFrost
  // oracle's "Elastic scrolling": the rubber band past a list's ends
  // (morpheus/Elastic). Off, a list stops at its edge.
  readonly property bool elasticScroll: cfg.elasticScroll !== false
  // Oracle's "Sliding cursor": CursorBand and terminus' SelectBar glide, or jump
  readonly property bool cursorSlide: cfg.cursorSlide !== false

  // THE CURVE FOR SOMETHING THAT TRAVELS, as opposed to something that
  // appears. `ease` above is quintic, which is right for a panel arriving:
  // it is over almost at once and the tail is not really seen.
  //
  // A thing moving ACROSS a surface is seen the whole way, and quintic puts
  // seven tenths of the distance in the first fifth of the time — a handful
  // of frames carrying nearly all the movement, then a long crawl. It reads
  // as a lurch followed by drift, which is exactly what it is. Cubic spends
  // the time far more evenly, so each frame carries a similar distance and
  // the move lands instead of settling.
  readonly property int travelEase: Easing.OutCubic

  // ── A SHEET'S ARRIVAL AND ITS DEPARTURE ─────────────────────────────
  // One pair for every sheet, where each used to carry its own copy.
  // LEAVING TAKES AS LONG AS ARRIVING — the same value, not a second number
  // that happens to match. It was 0.75 of slow on an InCubic, which barely
  // moves for the first half of its time, so a dismissed sheet sat there
  // before going; both halves now run on a curve that moves at once.
  // `slow`, which is twice the speed it was (slow × 2.0, 340ms) — Buck's
  // call, 2026-09-23.
  readonly property int sheetIn: slow
  readonly property int sheetOut: sheetIn
  readonly property int sheetInEase: Easing.OutCubic
  readonly property int sheetOutEase: Easing.OutCubic
  // HOW FAR THE WINDOW BEHIND A SHEET IS SET BACK (morpheus/SheetDim): one
  // number for every sheet in the suite — plato's, which was the only one
  // that dimmed at all (user, 2026-10-20: all sheets dim their window).
  readonly property real sheetDim: 0.32

  // ── THE CURVE FOR A THING THAT GROWS INTO PLACE ──────────────────────
  // Material's STANDARD easing, cubic-bezier(0.4, 0, 0.2, 1): a real
  // accelerate-then-decelerate, which is the shape for something moving
  // within the screen.
  //
  // NOT emphasized-decelerate, which is what this was and which is what
  // Material names for an expanding container — because that curve is
  // specified against a 300ms duration and this runs in a quarter of that.
  // Measured over its own numbers: it reaches 62% of the travel in the
  // first 10% of the time. At 75ms on a 100Hz panel that is ONE frame
  // carrying nearly two thirds of the distance, and 3 of 8 frames carrying
  // anything at all — a snap with a long invisible tail, which is exactly
  // what the file already records quintic being rejected for.
  //
  // This one spends the time: 0.03 / 0.13 / 0.37 / 0.78 at a tenth, a
  // fifth, a third and a half. 5 of 8 frames carry motion at 75ms, and the
  // eye has something to follow the whole way.
  //
  // Qt takes a bezier as its control points with the endpoint (1,1) written
  // out — which is why this is a list and cannot live beside the enums
  // above. `morphCurve` is the type; `morphBezier` is the shape.
  readonly property int morphCurve: Easing.Bezier
  readonly property var morphBezier: [0.4, 0.0, 0.2, 1.0, 1.0, 1.0]

  // ── AND A DIFFERENT ONE ON THE WAY OUT ───────────────────────────────
  // Material's `emphasized-accelerate`, cubic-bezier(0.3, 0, 0.8, 0.15),
  // which is the curve their spec names for an element LEAVING. One curve
  // for both directions was the last thing wrong with the morph: an exit is
  // not an entrance played backwards.
  //
  // It holds, then goes. Measured against the crossfade it has to share the
  // transition with: the pill stays at 70% of its width or more for the
  // first 50ms of a 75ms collapse — five frames at 100Hz — which is exactly
  // the window the outgoing layer has to fade out in. So the content is
  // gone BEFORE the shape moves out from under it, and the shape then
  // closes quickly because there is nothing left to wait for.
  //
  // With the entrance curve on both ends the pill was down to 70% in 20ms,
  // two frames, while the layer's text was still half lit — which is the
  // text left hanging past the rounded ends in Buck's capture.
  readonly property var morphExitBezier: [0.3, 0.0, 0.8, 0.15, 1.0, 1.0]


  // ── the arrival ──────────────────────────────────────────────────────
  // Moved to Arrival.qml. When the session's first animation plays is a
  // question about the boot, not a design token, and it had grown a frame
  // clock and a trace file that had no business living in the palette.

  // An item inside a layer-shell surface has window-local coordinates. This
  // is that window's own top-left in screen space, so the two can be added.
  // Written once: every popout that anchors to a bar module needs it, and the
  // one that skipped it landed a side-margin off.
  //
  // ONLY A LAYER SURFACE HAS ONE. An ordinary window — oracle's, ceres',
  // terminus' — is placed by the compositor and never told where, and has no
  // `anchors` to read; asked about one, this answers 0,0 rather than throwing.
  // Whatever wants to hang off a WINDOW needs a popup instead (CardPopup).
  function winOrigin(w, screen) {
    if (!w || !screen || w.anchors === undefined) return Qt.point(0, 0);
    return Qt.point(
      w.anchors.left ? w.margins.left : screen.width - w.margins.right - w.width,
      w.anchors.top ? w.margins.top : screen.height - w.margins.bottom - w.height);
  }

  // ── WHICH EDGE THE BAR LIVES ON ──────────────────────────────────────
  // One boolean, read by the pill, by every layer that opens out of it, by
  // the toast stack and by the tooltips. They must all agree: a layer that
  // stayed at the bottom while the pill moved to the top would be opening out
  // of nothing, and a tooltip that still pointed upwards would be pointing at
  // the bar it was trying to get out from under.
  readonly property bool barTop: cfg.barPosition === "top"

  // How far a layer's near edge sits from the screen edge the bar is on. One
  // definition for every layer, so a layer opened on a monitor that has no
  // pill lands at exactly the offset it would have had morphed into one. On
  // the pill's own screen, and not morphed into it, it additionally clears
  // the pill.
  //
  // Named for the EDGE rather than for the bottom: it was bottomLift while
  // the bottom was the only place the bar could be, and a function called
  // bottomLift feeding a topMargin is a lie that someone will eventually
  // believe.
  function edgeLift(morphed, screen, statusbar) {
    if (morphed) return padScreen;
    const onPill = screen && statusbar && statusbar.screen
      && screen.name === statusbar.screen.name;
    // The PILL's height, which is what "clears the pill" means. The bar's
    // surface is bigger than the pill for the length of a morph, and a
    // layer that is not itself morphing must not be pushed off by it.
    return padScreen + (onPill ? statusbar.pillHeight : 0);
  }

  // Unlit meter notch: the accent dimmed, so a meter reads as one color
  // whether its segments are lit or not. Kept well clear of the lit segment
  // in both brightness and alpha — but not so faint that the meter's own
  // shape disappears, which is what the first pass at these numbers did.
  function trough(c) {
    // Light: the accent, faint. Darkening a deep accent on paper only made
    // a gray notch, which read as a different meter.
    if (light) return Qt.rgba(c.r, c.g, c.b, 0.22);
    return Qt.rgba(c.r * 0.62, c.g * 0.62, c.b * 0.62, 0.42);
  }

  // 6-digit hex for markup that needs a string (StyledText <font color=...>);
  // QML's color->string gives #AARRGGBB, which Qt's rich text won't parse
  function hex(c) {
    const b = (v) => Math.round(v * 255).toString(16).padStart(2, "0");
    return "#" + b(c.r) + b(c.g) + b(c.b);
  }
}

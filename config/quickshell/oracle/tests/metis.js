// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The pure half of metis: English → qalc, and qalc → what is shown.
//
// Every rewrite here was a wrong answer first. "5 km in miles" came back as
// 204386.688 m³ and "30C to F" as 30 F·V, with nothing on screen to say the
// question had been misread — so each is pinned by the sentence that broke it.

"use strict";

module.exports = {
  module: "metis/metis.js",
  cases: (M, t) => {
    const ex = (q) => M.prepare(q).expr;

    // ── conversions ───────────────────────────────────────────────────────
    t.eq("in is a conversion before a unit", ex("5 km in miles"), "5 km to miles");
    t.eq("as and into too", ex("5 km as mi"), "5 km to mi");
    t.eq("an arrow too", ex("5 km -> mi"), "5 km to mi");
    t.eq("but an inch at the end is an inch", ex("6 ft 2 in"), "6 ft 2 in");
    t.eq("an inch before to stays an inch", ex("2 in to cm"), "2 in to cm");
    t.eq("five inches in centimetres", ex("5 in in cm"), "5 in to cm");
    t.eq("how many A in a B", ex("how many feet in a mile"), "1 mile to feet");
    t.eq("X is how many Y", ex("5 km is how many miles"), "5 km to miles");
    t.eq("leading filler goes", ex("what is 5 km in miles?"), "5 km to miles");

    // ── temperatures ──────────────────────────────────────────────────────
    t.eq("30C to F is celsius, not coulombs", ex("30C to F"), "30 °C to °F");
    t.eq("lowercase too", ex("30 c in f"), "30 °C to °F");
    t.eq("degrees spelled out", ex("30 degrees C"), "30 °C to °C");
    t.eq("centimetres are not celsius", ex("5 cm"), "5 cm to cm");
    t.eq("a hex number is not a temperature", ex("0x1F"), "0x1F");

    // ── rates ─────────────────────────────────────────────────────────────
    const at = M.prepare("100 km at 60 km/h");
    t.eq("at divides", at.expr, "(100 km) / (60 km/h)");
    t.eq("or multiplies, whichever is a time", at.alt, "(100 km) * (60 km/h)");
    t.eq("how long to … is the same question",
      ex("how long to drive 100 km at 60 km/h"), "(100 km) / (60 km/h)");
    t.eq("in a number is a rate", ex("100 km in 2 h"), "(100 km) / (2 h)");
    t.eq("for a number multiplies", ex("60 mph for 2 h"), "(60 mph) * (2 h)");
    t.eq("an hour is a per", ex("60 miles an hour to km/h"), "60 miles/hour to km/h");
    t.eq("Mbps is bits", ex("500 MB at 10 Mbps"), "(500 MB) / (10 Mbit/s)");

    // ── percentages ───────────────────────────────────────────────────────
    t.eq("% of is a product", ex("20% of 150"), "20% × 150");
    t.eq("percent spelled out", ex("what is 15 percent of 80"), "15% × 80");
    t.eq("off is unambiguous", ex("20% off 150"), "(150) × (1 − 20/100)");
    t.eq("more than", ex("15% more than 200"), "(200) × (1 + 15/100)");
    t.eq("is what percent of", ex("40 is what percent of 160"), "(40) / (160) to %");
    t.eq("percent change", ex("percent change from 50 to 75"), "((75) - (50)) / (50) to %");

    // ── units qalc misreads ───────────────────────────────────────────────
    t.eq("lbs is pounds, not pound-seconds", ex("3 lbs to kg"), "3 lb to kg");
    t.eq("quarts", ex("2 quarts to L"), "2 liq_qt to L");
    t.eq("fl oz", ex("8 fl oz to mL"), "8 floz to mL");
    t.eq("knots", ex("10 knots to km/h"), "10 knot to km/h");
    t.eq("but kN is a kilonewton", ex("5 kN to lbf"), "5 kN to lbf");
    t.eq("speed of light", ex("speed of light"), "c");
    t.eq("light years", ex("1 light year in km"), "1 ly to km");
    t.eq("L/100km", ex("8 L/100km"), "8 L/(100 km) to L/(100 km)");

    // ── a bare quantity keeps its unit ────────────────────────────────────
    const kwh = M.prepare("3 kWh");
    t.eq("3 kWh stays in kWh", kwh.expr, "3 kWh to kWh");
    t.ok("and says so quietly", kwh.auto === true);
    t.eq("an explicit target is not automatic", M.prepare("3 kWh to J").auto, undefined);

    // ── words that are not units ──────────────────────────────────────────
    t.eq("a stray of is refused", M.prepare("foo of bar").bad, "of");
    t.eq("a stray at with nothing either side is refused", M.prepare("at").bad, "at");

    // ── time zones ────────────────────────────────────────────────────────
    const tz = M.prepare("3pm EST to CET");
    t.eq("a time between zones", tz.kind, "tz");
    t.eq("EST is New York", tz.from, "America/New_York");
    t.eq("CET is Paris", tz.to, "Europe/Paris");
    const now = M.prepare("what time is it in tokyo");
    t.eq("now in a city", now.time, "now");
    t.eq("a known city is its zone", now.to, "Asia/Tokyo");
    t.eq("an unknown one is looked up by name", M.prepare("time in reykjavik").to, "reykjavik");
    t.eq("two words are one name", M.prepare("time in port moresby").to, "port_moresby");
    t.eq("a city that is not a zone file", M.prepare("time in san francisco").to, "America/Los_Angeles");
    t.eq("a US state", M.prepare("time in california").to, "America/Los_Angeles");
    t.eq("a country with many zones means its main one", M.prepare("time in australia").to, "Australia/Sydney");
    t.eq("tokyo time is now there", M.prepare("tokyo time").time, "now");
    const tt = M.prepare("3pm tokyo time");
    t.eq("3pm tokyo time is theirs", tt.from, "Asia/Tokyo");
    t.eq("brought here", tt.to, "");
    t.eq("noon is a time", M.prepare("noon PST to london").time, "12:00");
    const wd = M.prepare("9am monday new york to sydney", { now: new Date(2026, 9, 5, 12) });
    t.eq("a day with the time", wd.date, "2026-10-05");
    t.eq("and the place after it", wd.from, "America/New_York");
    t.eq("tomorrow is a day and not a place", M.prepare("9am tomorrow in tokyo", { now: new Date(2026, 9, 5, 12) }).date, "2026-10-06");
    t.eq("the label keeps the day as typed", wd.label, "9am monday New York → Sydney");
    t.eq("difference between", M.prepare("time difference between tokyo and london").mode, "diff");
    t.eq("two places and no time is their difference", M.prepare("tokyo to london").mode, "diff");
    t.eq("but two units are not places", M.prepare("meters to feet").kind, "qalc");
    t.eq("ahead", M.readTz("+0900|+0100|10:00 JST|02:00 BST", M.prepare("tokyo to london")).result,
      "London is 8 h behind Tokyo");
    t.eq("half hours", M.readTz("+0100|+0530|x|y", M.prepare("london to mumbai")).result,
      "Mumbai is 4 h 30 min ahead of London");
    const conv = M.readTz("21:00 JST · Mon 5 Oct|9:00 PM|+0900|2026-10-06",
      M.prepare("3pm to tokyo"), new Date(2026, 9, 5, 12));
    t.eq("the 12-hour time, the day it lands on, the offset", conv.chips.join(" | "),
      "9:00 pm | tomorrow | UTC+9");
    t.eq("an offset is POSIX, counted backwards", M.prepare("15:30 to utc+5:30").to, "<+0530>-5:30");
    t.eq("10:30 to min is arithmetic, not a zone", M.prepare("10:30 to min").kind, "qalc");

    // ── reading qalc ──────────────────────────────────────────────────────
    const S = "\u001e\n";
    const ok = M.readCalc("3.106855961 mi\n" + S + "5 kilometers ≈ 3.106855961 mi\n" + S
      + "5000 m\n" + S + "5 km to miles\n", M.prepare("5 km in miles"));
    t.eq("the answer", ok.result, "3.106855961 mi");
    t.eq("the reading, with where it went", ok.parse, "5 kilometers → miles");
    t.eq("the base it is classified by", ok.base, "5000 m");

    const salad = M.readCalc("204386.688 m³\n" + S + "5 kilometer·inch·miles = 204386.688 m³\n"
      + S + "204386.688 m³\n" + S + "5 km in miles\n", {});
    t.ok("three units multiplied is words read as units", salad.bad);
    const err = M.readCalc("1 B\n" + S + "error: \"w\" is not a valid variable/function/unit.\nx = 1 B\n"
      + S + S, {});
    t.eq("an unknown name is named", err.word, "w");
    t.ok("a fourth power is not real", M.looksLikeSalad("", "12 m⁷"));
    t.ok("nor a squared byte", M.looksLikeSalad("", "1 bits²"));
    t.ok("but an energy is", !M.looksLikeSalad("3 kilowatt·hours", "10800000 kg·m²/s²"));

    t.eq("trailing zeros go", M.trimZeros("$56.12500000"), "$56.125");
    t.eq("all of them", M.trimZeros("€50.0000"), "€50");
    t.eq("integers are untouched", M.trimZeros("120"), "120");
    t.eq("an exponent is part of a unit", M.unitOf("2400000000 s^−1"), "s^−1");

    // ── chips ─────────────────────────────────────────────────────────────
    t.eq("a duration", M.duration(6000), "1 h 40 min");
    t.eq("a long one", M.duration(90061), "1 d 1 h 1 min");
    t.eq("under a minute is not one", M.duration(30), "");
    t.eq("a height", M.feetInches(1.8796), "6 ft 2 in");
    t.eq("a length is a length", M.categoryOf("5000 m", "5 km").name, "length");
    t.eq("a speed", M.categoryOf("27.7 m/s", "100 km/h").name, "speed");
    t.eq("an energy", M.categoryOf("3600000 kg·m²/s²", "1 kWh").name, "energy");
    t.eq("a frequency", M.categoryOf("50 s^−1", "50 Hz").name, "freq");
    t.eq("money", M.categoryOf("€50", "$56.125").name, "currency");
    t.eq("L/100km is fuel, not an area", M.categoryOf("8E−8 m²", "8 L/100km").name, "fuel");

    const plain = M.chipPlan({ result: "30", raw: "30", base: "30", expr: "20% × 150", input: "20% × 150" });
    t.eq("a sum's answer gets no hex", plain.lines.length, 0);
    const hex = M.chipPlan({ result: "255", raw: "255", base: "255", expr: "255", input: "255" });
    t.has("a bare number does", hex.lines.join("|"), "to hex");
    const kn = M.chipPlan({ result: "53.99 kn", raw: "53.99 knots", base: "27.7 m/s", expr: "", input: "" });
    t.has("chips are asked in qalc's words, not the display's", kn.lines[0], "53.99 knots");

    const chips = M.readChips("5000 m\n5 km\n3.10686 mi\n16404.2 ft\n196850 in\n",
      { specs: [{ to: "m" }, { to: "km" }, { to: "mi" }, { to: "ft" }, { to: "in" }], local: [] },
      { result: "3.106855961 mi", input: "5 km to miles" });
    t.eq("the typed quantity, the shown unit and the absurd are dropped",
      chips.join(" | "), "5000 m | 16404.2 ft");

    // ── going on from the last answer ─────────────────────────────────────
    const A = { ans: "3.106855961 mi" };
    t.eq("ans is the last answer, whole", M.prepare("ans * 2", A).expr, "(3.106855961 mi) * 2");
    t.eq("an operator on its own carries on", M.prepare("* 2", A).expr, "(3.106855961 mi) * 2");
    t.eq("so does a bare conversion", M.prepare("to km", A).expr, "(3.106855961 mi) to km");
    t.eq("- 5 carries on", M.prepare("- 5", A).expr, "(3.106855961 mi) - 5");
    t.eq("but -5 is a number", M.prepare("-5", A).expr, "-5");
    t.eq("ans with nothing before it is refused", M.prepare("ans * 2").bad, "ans");
    t.eq("the newest answer qalc can read back",
      M.lastAnswer([{ raw: "" }, { raw: "5 km" }, { raw: "2 mi" }]), "5 km");

    // ── history on disk ───────────────────────────────────────────────────
    t.eq("history lives under the cache dir", M.historyPath(), "/home/test/.cache/metis-history");
    t.eq("a broken file is no history", M.parseHistory("{nope").length, 0);
    t.eq("rows without an answer are dropped",
      M.parseHistory('[{"expr":"1+1","result":"2"},{"expr":"x"}]').length, 1);
    const H2 = M.addHistory([{ expr: "1+1", result: "2" }], { expr: "1+1", result: "2" });
    t.eq("the same answer is kept once", H2.length, 1);

    // ── rounding ──────────────────────────────────────────────────────────
    t.eq("to 2 decimals", M.prepare("5 km in miles to 2 decimals").round.dp, 2);
    t.eq("and the conversion survives it", M.prepare("5 km in miles to 2 decimals").expr, "5 km to miles");
    t.eq("sig figs", M.prepare("pi to 3 sig figs").round.sig, 3);
    t.eq("round X", M.prepare("round 3.14159").round.dp, 0);
    t.eq("X rounded", M.prepare("22/7 rounded").expr, "22/7");
    t.eq("dp keeps the unit", M.roundText("3.106855961 mi", { dp: 2 }), "3.11 mi");
    t.eq("sig too", M.roundText("0.5283441047 gal", { sig: 3 }), "0.528 gal");
    t.eq("a long answer gets a short chip", M.roundedChip("3.106855961 mi"), "3.11 mi");
    t.eq("a short one does not", M.roundedChip("3.5 mi"), "");

    // ── reading long numbers ──────────────────────────────────────────────
    t.eq("thousands", M.group("9460730472581 km"), "9,460,730,472,581 km");
    t.eq("four digits stay", M.group("5280 ft"), "5280 ft");
    t.eq("decimals stay", M.group("0.123456789"), "0.123456789");
    t.eq("dates stay", M.group("2026-12-25"), "2026-12-25");
    t.eq("hex stays", M.group("0xFFFFFF"), "0xFFFFFF");

    // ── dates ─────────────────────────────────────────────────────────────
    const N = { now: new Date(2026, 9, 5, 12, 0) };   // Mon 5 Oct 2026
    t.eq("days until christmas", M.prepare("days until christmas", N).result, "81 days");
    t.eq("weeks till it", M.prepare("weeks till christmas", N).result, "11 weeks 4 days");
    t.eq("christmas already past this year is next year's",
      M.prepare("days until christmas", { now: new Date(2026, 11, 26) }).result, "364 days");
    t.eq("days since", M.prepare("days since 1994-03-12", N).result, "11895 days");
    t.eq("age", M.prepare("how old is someone born 12 march 1994", N).result, "32 years 6 months 23 days");
    t.eq("weekday", M.prepare("what day is christmas", N).result, "Friday");
    t.eq("next friday", M.prepare("next friday", N).result, "Fri 9 Oct 2026");
    t.eq("next monday on a monday is a week on", M.prepare("next monday", N).result, "Mon 12 Oct 2026");
    t.eq("an offset", M.prepare("90 days from now", N).result, "Sun 3 Jan 2027");
    t.eq("ago", M.prepare("3 weeks ago", N).result, "Mon 14 Sep 2026");
    t.eq("months clamp to the month's end",
      M.prepare("2026-01-31 + 1 month", N).result, "Sat 28 Feb 2026");
    t.eq("clock span", M.prepare("9:15 to 17:40", N).result, "8 h 25 min");
    t.eq("across midnight", M.prepare("from 10pm to 6am", N).result, "8 h");
    t.eq("days between", M.prepare("days between 2026-01-01 and 2026-12-25", N).result, "358 days");
    t.eq("but 5 km to mi is not a date", M.prepare("5 km to mi", N).kind, "qalc");

    // ── running ───────────────────────────────────────────────────────────
    const P = M.prepare("10k in 50 min");
    t.eq("10k in a race is km, and the answer a pace", P.expr, "(50 min) / (10 km) to s/km");
    t.ok("shown as one", P.pace);
    t.eq("10k elsewhere is ten thousand", M.prepare("10k usd to eur").expr, "(10 × 1000) usd to eur");
    t.eq("a typed pace is seconds per km", M.prepare("marathon at 5:30/km").alt,
      "((42.195 km)) * ((330 s/km))");
    t.eq("to min/mi is a pace", M.prepare("5:30/km to min/mi").target, "s/mi");
    t.eq("pace text", M.paceText(330, "/km"), "5:30 /km");
    t.eq("no 5:60", M.paceText(359.7, "/km"), "6:00 /km");

    // ── cooking ───────────────────────────────────────────────────────────
    const C = M.prepare("2 cups flour to grams");
    t.eq("a cup of flour weighs", C.expr, "(2 cup) × (125 g/cup) to grams");
    t.has("and says what it assumed", C.label, "125 g a cup");
    t.eq("grams to cups divides", M.prepare("200 g sugar in cups").expr, "(200 g) / (200 g/cup) to cup");
    t.eq("a stick of butter is half a cup", M.prepare("1 stick of butter in grams").expr,
      "((1 × 0.5 cup)) × (227 g/cup) to grams");
    t.eq("no target: grams for a volume", M.prepare("2 cups flour").target, "g");

    // ── did you mean ──────────────────────────────────────────────────────
    const NAMES = M.parseNames("<names>ar:m,meter,p:meters</names><names>a-cr:EUR,au:€,euro,p:euros</names>"
      + "<names>r:mile,p:miles,a:mi</names><names>a:mil,p:mils</names>");
    t.ok("names come out of qalc's files", NAMES.indexOf("euros") !== -1 && NAMES.indexOf("€") === -1);
    t.eq("mtrs is not a name", M.culprit("5 mtrs", NAMES, ["k", "m"]), "mtrs");
    t.eq("km is a prefixed one", M.culprit("5 km to mi", NAMES, ["k"]), "");
    t.eq("plurals count", M.culprit("5 meters", NAMES, []), "");
    t.eq("swapped letters are one slip", M.suggest("miels", NAMES)[0], "miles");
    t.eq("shortened words are found", M.suggest("mtrs", NAMES)[0], "meters");
    t.eq("English is not suggested for", M.suggest("of", NAMES).length, 0);
    t.eq("a hex number is not a misspelling", M.culprit("0x1F + 1E5", NAMES, []), "");
    t.eq("a bare pace is shown as one", M.prepare("5:30 min/km").target, "s/km");
    t.eq("qalc's one-letter fragment defers to the whole word",
      M.badWord({ word: "r" }, { expr: "2 cps to g" }, NAMES, []), "cps");

    // ── exchange rates ────────────────────────────────────────────────────
    t.eq("fresh rates say nothing", M.ratesNote(3600), "");
    t.eq("old ones do", M.ratesNote(3 * 86400 + 5), "rates 3 days old");
    t.eq("none at all", M.ratesNote(-1), "no exchange rates");

    // ── how an answer looks ───────────────────────────────────────────────
    const kinds = (v) => M.answerChars(v).map((x) => x.quiet ? "q" : x.big ? "B" : "s").join("");
    t.eq("a time zone's date quieter still", kinds("21:00 JST · Mon 5 Oct"), "BBBBBssssqqqqqqqqqqqq");
    t.eq("hex is one number", kinds("0xFF"), "BBBB");
    t.eq("an answer with no number is whole", kinds("Friday"), "BBBBBB");
    t.eq("grouped thousands stay one number", kinds("9,460 km"), "BBBBBsss");
    t.eq("the sky's colour follows its glyph", [M.skyInk(12 * 60), M.skyInk(6 * 60), M.skyInk(23 * 60)].join(" "),
      "sand yellow keyInk");
    const ink = { num: "N", word: "W", joiner: "J", op: "O", bad: "B" };
    const hl = M.highlight("5 mtrs in miles * 2", ink, "mtrs");
    t.has("numbers tinted", hl, '<font color="N">5</font>');
    t.has("the bad word red", hl, '<font color="B">mtrs</font>');
    t.has("joining words quiet", hl, '<font color="J">in</font>');
    t.has("operators", hl, '<font color="O">*</font>');
    t.has("markup in the field is text", M.highlight("<b>", ink, ""), "&lt;");
    t.has("feet and inches are numbers", M.highlight("5'11\"", ink, ""), '<font color="N">11</font>');
    t.eq("where the bad word is", JSON.stringify(M.wordSpan("5 mtrs in m", "mtrs")), '{"start":2,"end":6}');
    t.eq("whole words only", M.wordSpan("5 mtrsx", "mtrs"), null);
    t.eq("a length shows a ruler", M.kindOf({ kind: "qalc" }, { category: "length", result: "5 km" }), "length");
    t.eq("a time zone a globe", M.kindOf({ kind: "tz", mode: "conv" }, null), "tz");
    t.eq("cooking", M.kindOf({ kind: "qalc", label: "x" }, {}), "cooking");
    t.eq("a clock span", M.kindOf(M.prepare("9:15 to 17:40"), null), "clock");
    t.ok("every kind has a glyph", ["length", "tz", "date", "calc", "cooking"].every((k) => M.glyphFor(k).length > 0));
    const xmas = M.prepare("days until christmas", { now: new Date(2026, 9, 5, 12) });
    t.ok("a wait has its progress", xmas.progress && xmas.progress.frac > 0.7 && xmas.progress.frac < 0.8);
    t.eq("from last time", xmas.progress.from, "Thu 25 Dec 2025");
    const st = M.readTz("21:00 JST · Mon 5 Oct|9:00 PM|+0900|2026-10-05|15:00", M.prepare("3pm to tokyo"),
      new Date(2026, 9, 5, 12));
    t.eq("both places on one day", JSON.stringify(st.strip),
      '[{"label":"here","min":900},{"label":"Tokyo","min":1260}]');
    t.eq("history keeps the kind", M.parseHistory('[{"expr":"a","result":"b","kind":"tz"}]')[0].kind, "tz");
    t.eq("but not one it does not know", M.parseHistory('[{"expr":"a","result":"b","kind":"zz"}]')[0].kind, "calc");

    // ── distances ─────────────────────────────────────────────────────────
    const G = M.prepare("distance from cairo to london");
    t.eq("a distance between two cities", G.kind, "geo");
    t.eq("known cities carry their coordinates", G.a.coord, "30.044,31.236");
    t.eq("how far is X from Y", M.prepare("how far is tokyo from paris").kind, "geo");
    t.eq("X to Y distance", M.prepare("cairo to dubai distance").kind, "geo");
    t.eq("but how far … at a speed is still arithmetic", M.prepare("how far is 2 h at 60 km/h").kind, "qalc");
    t.eq("ISO 6709 coordinates", JSON.stringify(M.parseCoord("+3003+03115")), "[30.05,31.25]");
    t.eq("with seconds", M.parseCoord("+404251-0740023")[1].toFixed(4), "-74.0064");
    t.eq("cairo to london", Math.round(M.haversineKm([30.044, 31.236], [51.507, -0.128])), 3511);
    t.eq("which way", M.bearingWord([30.044, 31.236], [51.507, -0.128]), "northwest");
    const gr = M.readGeo("30.044,31.236|51.507,-0.128|+0300|+0100|Africa/Cairo|Europe/London", G);
    t.eq("the answer", gr.result, "3511 km");
    t.has("a flight time", gr.chips.join("|"), "flight");
    t.has("and the clocks", gr.chips.join("|"), "London 2 h behind");
    const gs = M.readGeo("34.05,-118.24|29.76,-95.36|-0700|-0500|Los Angeles|Houston",
      M.prepare("distance from california to texas"));
    t.has("a stand-in city is named", gs.parse, "Texas at Houston");
    t.eq("a city is not its own stand-in",
      M.readGeo("30.04,31.24|51.51,-0.13|+0300|+0100||", G).parse, "Cairo → London  · straight line");

    // ── the place index ───────────────────────────────────────────────────
    t.eq("names in", M.setIndex("0\tontario\tr\n0\tlondon\tc\n1\tbombay\tc\n0\tcanada\tn\n"), 3);
    t.ok("a province is a place", M.isKnownZone("ontario"));
    t.ok("so is a city by another name", M.isKnownZone("bombay"));
    t.eq("a place there", JSON.stringify(M.qualified("london ontario")), '{"name":"london","qual":"ontario"}');
    t.eq("with a comma", JSON.stringify(M.qualified("london, ontario")), '{"name":"london","qual":"ontario"}');
    t.eq("a country by its code", M.qualified("london ca").qual, "ca");
    t.eq("the UK is GB to ISO", M.qualified("london uk").qual, "gb");
    t.eq("as the scripts read it", M.placeQuery("London, Ontario"), "london,ontario");
    t.eq("time in ontario", M.prepare("time in ontario").to, "ontario");
    t.eq("a distance to a place only the index has", M.prepare("distance from london ontario to toronto").a.place,
      "london,ontario");
    t.eq("another name is found but never offered", M.complete("3pm bomb"), "");
    t.eq("its own is", M.complete("time in onta"), "rio");
    t.eq("a misspelt place is suggested", M.suggest("ontaria", [])[0], "ontario");
    M.setIndex("");

    // ── visual refinements ────────────────────────────────────────────────
    const ch = M.answerChars("3.11 mi");
    t.eq("digits large, units small", ch.map((x) => x.big ? "B" : "s").join(""), "BBBBsss");
    t.ok("a reading of a bare quantity is noise", !M.parseWorth({ kind: "qalc", auto: true }, "5 kilometers", "5 km"));
    t.ok("a conversion's is the point", M.parseWorth({ kind: "qalc" }, "5 kilometers → miles", "5 km in miles"));
    t.ok("spacing alone is no news", !M.parseWorth({ kind: "qalc" }, "1 / 3", "1/3"));
    const ph = M.parseHtml("50 EUR → USD  · rates 3 days old", { muted: "M", arrow: "A", target: "T", warn: "W" });
    t.has("the arrow in its own ink", ph, '<font color="A">&nbsp;→&nbsp;</font>');
    t.has("old rates warned", ph, '<font color="W">rates');
    t.ok("* 2 goes on", M.continues("* 2", "3 mi"));
    t.ok("-5 does not", !M.continues("-5", "3 mi"));
    t.eq("trillions", M.wordScale("9460730472581 km"), "≈ 9.46 trillion km");
    t.eq("millionths", M.wordScale("0.0000032 m"), "≈ 3.2 millionths m");
    t.eq("ordinary numbers stay", M.wordScale("5280 ft"), "");
    t.eq("hot is red", M.tintFor("temp", "313.15 K"), "red");
    t.eq("freezing is cyan", M.tintFor("temp", "263.15 K"), "cyan");
    t.eq("money is green", M.tintFor("currency", ""), "green");
    t.ok("sun by day", M.skyGlyph(12 * 60) !== M.skyGlyph(23 * 60));
    t.eq("finish the word", M.complete("5 kilom"), "eters");
    t.eq("the short one first", M.complete("5 km to mil"), "es");
    t.eq("a place, two words", M.complete("3pm new yo"), "rk");
    t.eq("a whole word is left alone", M.complete("5 km to miles"), "");
    t.ok("examples to start from", M.EXAMPLES.length >= 3);
    t.ok("a division by zero inside an answer is not one",
      M.readCalc("€(20.48997773 / 0)(1 EGP < 0)\n\u001e\n23 USD = x\n\u001e\n\u001e\n", {}).bad);
  }
};

// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE PURE HALF OF METIS: what you typed → what qalc is asked, and what qalc
// said → what is shown.
//
// qalc already knows every unit there is. What it does not know is English:
// "5 km in miles" is five kilometre-inch-miles to it, "30C to F" is coulombs
// and farads, "20% of 150" is a modulo and a byte. So the sentence is turned
// into qalc's grammar here first, and what comes back is checked before it is
// shown — a confident wrong number is worse than no number.

// ── qalc as metis runs it ─────────────────────────────────────────────────
// `autoconversion none` is what makes an answer come back in the unit it was
// asked in: no "3 mi + 188 yd + 2.39 in" for "to mi", no 2 L shown as
// 2000000 mm³, no °C turned to °F because the locale is en_US. It is passed
// per call and never saved — the user's own qalc.cfg is left alone.
const QALC = "qalc -s 'autoconversion none'";
// The same, for the base-unit signature a result is classified by. Without
// prefixes "to base" is m³ and bits/s rather than mm³ and kilobits/ms.
const QALC_BASE = "qalc -t -s 'autoconversion none' -s 'prefixes off'";
// Six figures is plenty on a chip; the headline keeps qalc's ten.
const QALC_CHIP = "qalc -t -s 'autoconversion none' -s 'precision 6'";

// Sections of one calc run's output are split by an ASCII record separator,
// which no answer qalc gives can contain.
const SEP = "\u001e";
// where "ans" stood, until the stray-word check has run
const ANS = "\u2045ANS\u2046";

// ── words that are never units ────────────────────────────────────────────
// Every one of these is SOMETHING to qalc (at = atto-, as = attosecond, of …)
// so an English word left in the expression is not an error to it, it is a
// factor. Any of them still standing after the rewrites means the sentence
// was not understood, and it is said so instead of guessed.
const STOPWORDS = [
  "of", "at", "how", "many", "much", "what", "whats", "is", "are", "the",
  "an", "for", "from", "with", "by", "and", "or", "does", "do", "it", "take",
  "there", "would", "will", "can", "you", "me", "my", "give", "show", "tell",
  "about", "approximately", "roughly", "around", "if", "when", "where",
  "which", "who", "why", "than", "more", "less", "into", "as", "on", "then",
  "also", "please", "long", "far", "big", "fast", "heavy", "hot", "cold"
];

// ── spellings qalc reads as something else ────────────────────────────────
// Each was checked against qalc 5.12: the left side gave a wrong unit or a
// unit salad, the right side the thing meant.
const ALIASES = [
  [/\b(?:kmh|kph|kmph)\b/gi, "km/h"],
  [/\bkm\s*\/\s*hr\b/gi, "km/h"],
  [/\b([kKmMgG])bps\b/g, (m, p) => ({ k: "k", K: "k", m: "M", M: "M", g: "G", G: "G" })[p] + "bit/s"],
  [/\bbps\b/g, "bit/s"],
  [/\bfl\.?\s*oz\b/gi, "floz"],
  [/\bfluid\s+ounces?\b/gi, "floz"],
  [/\btablespoons?\b/gi, "tbsp"],
  [/\bteaspoons?\b/gi, "tsp"],
  [/\bcups\b/gi, "cup"],
  [/\bimperial\s+gallons?\b/gi, "gal_UK"],
  [/\bimperial\s+pints?\b/gi, "pt_UK"],
  [/\b(?:quarts?|qts?)\b/gi, "liq_qt"],
  [/\b(?:pints?|pts?)\b/gi, "liq_pt"],
  [/\b(?:stones?|st)\b/gi, "stone"],
  [/\b(?:knots?|kts?)\b/gi, "knot"],
  [/\bkn\b/g, "knot"],   // lowercase only: kN is a kilonewton
  [/\bbtus?\b/gi, "Btu"],
  [/\blbs\b/gi, "lb"],
  [/\bozs\b/gi, "oz"],
  [/\b(?:hrs?)\b/gi, "h"],
  [/\bmins\b/gi, "min"],
  [/\bsecs?\b(?!\s*\()/gi, "s"],   // not sec(x)
  [/\b(?:yrs?)\b/gi, "year"],
  [/\bweeks?\b/gi, "week"],
  [/\bdecades?\b/gi, "(10 year)"],
  [/\b(?:g-?force|gees|gravity)\b/gi, "g0"],
  [/\bsq(?:uare)?\.?\s+(km|m|cm|mm|mi|ft|in|yd)\b/gi, "$1^2"],
  [/\bcu(?:bic)?\.?\s+(km|m|cm|mm|ft|in|yd)\b/gi, "$1^3"],
  [/\b(percent|pct)\b/gi, "%"],
  [/\bspeed\s+of\s+light\b/gi, "c"],
  [/\bspeed\s+of\s+sound\b/gi, "(343 m/s)"],
  [/\blight[\s-]?years?\b/gi, "ly"],
  [/\bastronomical\s+units?\b/gi, "au"],
  [/\bnautical\s+miles?\b/gi, "nmi"],
  [/\bl\s*\/\s*100\s*km\b/gi, "L/(100 km)"]
];

// "60 miles an hour", "5 km a day": the article is a "per".
const PER_WORDS = "hour|hr|h|minute|min|second|sec|s|day|week|month|year";

// ── time zones ────────────────────────────────────────────────────────────
// The abbreviations people actually type, to the zone they mean by them —
// which in summer is the DST one: "EST" in July means New York, not UTC−5.
// Anything not here is looked up by name in /usr/share/zoneinfo by the
// script (tokyo, new york, cairo …).
const ZONES = {
  utc: "UTC", gmt: "UTC", z: "UTC", zulu: "UTC",
  est: "America/New_York", edt: "America/New_York", et: "America/New_York",
  eastern: "America/New_York",
  cst: "America/Chicago", cdt: "America/Chicago", ct: "America/Chicago",
  central: "America/Chicago",
  mst: "America/Denver", mdt: "America/Denver", mt: "America/Denver",
  mountain: "America/Denver",
  pst: "America/Los_Angeles", pdt: "America/Los_Angeles",
  pt: "America/Los_Angeles", pacific: "America/Los_Angeles",
  akst: "America/Anchorage", hst: "Pacific/Honolulu",
  bst: "Europe/London", wet: "Europe/Lisbon", west: "Europe/Lisbon",
  cet: "Europe/Paris", cest: "Europe/Paris",
  eet: "Europe/Athens", eest: "Europe/Athens", msk: "Europe/Moscow",
  gst: "Asia/Dubai", pkt: "Asia/Karachi", ist: "Asia/Kolkata",
  ict: "Asia/Bangkok", wib: "Asia/Jakarta", sgt: "Asia/Singapore",
  hkt: "Asia/Hong_Kong", jst: "Asia/Tokyo", kst: "Asia/Seoul",
  awst: "Australia/Perth", acst: "Australia/Adelaide",
  aest: "Australia/Sydney", aedt: "Australia/Sydney",
  nzst: "Pacific/Auckland", nzdt: "Pacific/Auckland",
  brt: "America/Sao_Paulo", art: "America/Argentina/Buenos_Aires",
  sast: "Africa/Johannesburg", wat: "Africa/Lagos", eat: "Africa/Nairobi",
  local: "", here: ""
};

// Places people say that are not zone file names: cities, US states, and
// the countries with more than one zone (whose first zone.tab row is not
// the one meant — Australia's is Lord Howe). Single-zone countries come from
// the system's own iso3166.tab/zone.tab, in the script.
const PLACES = {
  // North America
  "san francisco": "America/Los_Angeles", sf: "America/Los_Angeles",
  la: "America/Los_Angeles", "los angeles": "America/Los_Angeles",
  seattle: "America/Los_Angeles", portland: "America/Los_Angeles",
  "las vegas": "America/Los_Angeles", "san diego": "America/Los_Angeles",
  phoenix: "America/Phoenix", denver: "America/Denver", "salt lake city": "America/Denver",
  dallas: "America/Chicago", houston: "America/Chicago", austin: "America/Chicago",
  chicago: "America/Chicago", "new orleans": "America/Chicago",
  "new york": "America/New_York", nyc: "America/New_York", "new york city": "America/New_York",
  boston: "America/New_York", miami: "America/New_York", atlanta: "America/New_York",
  washington: "America/New_York", dc: "America/New_York", "washington dc": "America/New_York",
  philadelphia: "America/New_York", detroit: "America/Detroit",
  toronto: "America/Toronto", montreal: "America/Toronto", ottawa: "America/Toronto",
  vancouver: "America/Vancouver", calgary: "America/Edmonton",
  "mexico city": "America/Mexico_City", honolulu: "Pacific/Honolulu", anchorage: "America/Anchorage",
  // US states
  california: "America/Los_Angeles", oregon: "America/Los_Angeles",
  "washington state": "America/Los_Angeles", nevada: "America/Los_Angeles",
  arizona: "America/Phoenix", colorado: "America/Denver", utah: "America/Denver",
  "new mexico": "America/Denver", montana: "America/Denver", idaho: "America/Boise",
  wyoming: "America/Denver", texas: "America/Chicago", illinois: "America/Chicago",
  minnesota: "America/Chicago", wisconsin: "America/Chicago", louisiana: "America/Chicago",
  missouri: "America/Chicago", iowa: "America/Chicago", oklahoma: "America/Chicago",
  kansas: "America/Chicago", nebraska: "America/Chicago", alabama: "America/Chicago",
  mississippi: "America/Chicago", arkansas: "America/Chicago", tennessee: "America/Chicago",
  florida: "America/New_York", massachusetts: "America/New_York",
  pennsylvania: "America/New_York", "new jersey": "America/New_York",
  virginia: "America/New_York", "north carolina": "America/New_York",
  "south carolina": "America/New_York", ohio: "America/New_York",
  michigan: "America/Detroit", maryland: "America/New_York", connecticut: "America/New_York",
  maine: "America/New_York", vermont: "America/New_York", "new hampshire": "America/New_York",
  "rhode island": "America/New_York", delaware: "America/New_York",
  kentucky: "America/New_York", indiana: "America/Indiana/Indianapolis",
  "west virginia": "America/New_York", alaska: "America/Anchorage", hawaii: "Pacific/Honolulu",
  // Europe
  london: "Europe/London", edinburgh: "Europe/London", manchester: "Europe/London",
  dublin: "Europe/Dublin", lisbon: "Europe/Lisbon", madrid: "Europe/Madrid",
  barcelona: "Europe/Madrid", paris: "Europe/Paris", brussels: "Europe/Brussels",
  amsterdam: "Europe/Amsterdam", berlin: "Europe/Berlin", munich: "Europe/Berlin",
  frankfurt: "Europe/Berlin", hamburg: "Europe/Berlin", zurich: "Europe/Zurich",
  geneva: "Europe/Zurich", rome: "Europe/Rome", milan: "Europe/Rome",
  vienna: "Europe/Vienna", prague: "Europe/Prague", warsaw: "Europe/Warsaw",
  budapest: "Europe/Budapest", copenhagen: "Europe/Copenhagen", oslo: "Europe/Oslo",
  stockholm: "Europe/Stockholm", helsinki: "Europe/Helsinki", athens: "Europe/Athens",
  istanbul: "Europe/Istanbul", kyiv: "Europe/Kyiv", kiev: "Europe/Kyiv",
  moscow: "Europe/Moscow",
  // Africa and the Middle East
  cairo: "Africa/Cairo", alexandria: "Africa/Cairo", lagos: "Africa/Lagos",
  nairobi: "Africa/Nairobi", johannesburg: "Africa/Johannesburg",
  "cape town": "Africa/Johannesburg", casablanca: "Africa/Casablanca",
  accra: "Africa/Accra", "addis ababa": "Africa/Addis_Ababa",
  dubai: "Asia/Dubai", "abu dhabi": "Asia/Dubai", doha: "Asia/Qatar",
  riyadh: "Asia/Riyadh", "tel aviv": "Asia/Jerusalem", jerusalem: "Asia/Jerusalem",
  tehran: "Asia/Tehran", amman: "Asia/Amman", beirut: "Asia/Beirut",
  // Asia and Oceania
  karachi: "Asia/Karachi", mumbai: "Asia/Kolkata", delhi: "Asia/Kolkata",
  "new delhi": "Asia/Kolkata", bangalore: "Asia/Kolkata", bengaluru: "Asia/Kolkata",
  chennai: "Asia/Kolkata", hyderabad: "Asia/Kolkata", kolkata: "Asia/Kolkata",
  dhaka: "Asia/Dhaka", bangkok: "Asia/Bangkok", hanoi: "Asia/Bangkok",
  "ho chi minh": "Asia/Ho_Chi_Minh", jakarta: "Asia/Jakarta", singapore: "Asia/Singapore",
  "kuala lumpur": "Asia/Kuala_Lumpur", manila: "Asia/Manila", beijing: "Asia/Shanghai",
  shanghai: "Asia/Shanghai", shenzhen: "Asia/Shanghai", "hong kong": "Asia/Hong_Kong",
  taipei: "Asia/Taipei", seoul: "Asia/Seoul", tokyo: "Asia/Tokyo", osaka: "Asia/Tokyo",
  kyoto: "Asia/Tokyo", sydney: "Australia/Sydney", melbourne: "Australia/Melbourne",
  brisbane: "Australia/Brisbane", perth: "Australia/Perth", adelaide: "Australia/Adelaide",
  auckland: "Pacific/Auckland", wellington: "Pacific/Auckland",
  // South America
  "sao paulo": "America/Sao_Paulo", "são paulo": "America/Sao_Paulo",
  rio: "America/Sao_Paulo", "rio de janeiro": "America/Sao_Paulo",
  "buenos aires": "America/Argentina/Buenos_Aires", santiago: "America/Santiago",
  lima: "America/Lima", bogota: "America/Bogota", "bogotá": "America/Bogota",
  caracas: "America/Caracas",
  // countries by their usual name, and the many-zoned ones
  usa: "America/New_York", us: "America/New_York", america: "America/New_York",
  "united states": "America/New_York", uk: "Europe/London", england: "Europe/London",
  britain: "Europe/London", "great britain": "Europe/London", scotland: "Europe/London",
  wales: "Europe/London", uae: "Asia/Dubai", emirates: "Asia/Dubai",
  china: "Asia/Shanghai", india: "Asia/Kolkata", russia: "Europe/Moscow",
  australia: "Australia/Sydney", canada: "America/Toronto", brazil: "America/Sao_Paulo",
  mexico: "America/Mexico_City", indonesia: "Asia/Jakarta", korea: "Asia/Seoul",
  "south korea": "Asia/Seoul", holland: "Europe/Amsterdam", japan: "Asia/Tokyo",
  germany: "Europe/Berlin", france: "Europe/Paris", spain: "Europe/Madrid",
  italy: "Europe/Rome", egypt: "Africa/Cairo"
};

// noon and midnight as clock times date(1) reads
const TIME_RE = "(now|\\d{1,2}(?::\\d{2})?\\s*(?:am|pm)|\\d{1,2}:\\d{2})";
// "10:30 to min" is a qalc question, not a time zone one
const TIME_UNITS = /^(?:ms|s|sec|secs|seconds?|min|mins|minutes?|h|hrs?|hours?|d|days?|weeks?|base|mixed|hex|bin|oct|sci|fraction)$/i;

function placeKey(word) {
  return String(word || "").trim().toLowerCase().replace(/\s+/g, " ").replace(/\s+time$/, "");
}

// A zone as the user wrote it → what the script gets: an IANA name, a POSIX
// offset for UTC±h[:mm], "" for local, or the words (underscored) to look up.
function zoneArg(word) {
  const w = String(word || "").trim().replace(/\s+time$/i, "");
  const k = w.toLowerCase();
  if (Object.prototype.hasOwnProperty.call(ZONES, k)) return ZONES[k];
  if (Object.prototype.hasOwnProperty.call(PLACES, placeKey(k))) return PLACES[placeKey(k)];
  const off = /^(?:utc|gmt)\s*([+\-−])\s*(\d{1,2})(?::?(\d{2}))?$/i.exec(w);
  if (off) {
    const east = off[1] === "+";
    const hh = off[2].padStart(2, "0"), mm = off[3] || "00";
    // POSIX TZ counts the other way round: "<+0530>-5:30" is UTC+5:30
    return "<" + (east ? "+" : "-") + hh + mm + ">" + (east ? "-" : "+")
      + Number(off[2]) + ":" + mm;
  }
  return placeQuery(w);
}

// a zone this file knows by name — its own tables, or the place index
function isKnownZone(word) {
  const k = placeKey(word);
  return Object.prototype.hasOwnProperty.call(ZONES, k)
    || Object.prototype.hasOwnProperty.call(PLACES, k)
    || /^(?:utc|gmt)\s*[+\-−]\s*\d/i.test(k)
    || inIndex(word);
}

// ── the place index ───────────────────────────────────────────────────────
// Every city of 15,000 people or more, every province, state and country,
// from GeoNames: built once into the cache by scripts/metis-places.py and
// read here as names only (is this a place? what might this word finish
// as?). Where a place is — its zone, its coordinates — is looked up in the
// file itself, by the scripts (ZONE_SH's place()).
// main: its own names, biggest first, filed by their first three letters —
// completion runs on every keystroke, and scanning forty thousand names to
// finish one word was 50 ms of typing lag
let INDEX = { keys: {}, main: {} };

function placesPath() {
  return Paths.cacheDir() + "/metis-places.tsv";
}

// $1 the index, $2 the script that builds it: built if missing (one
// download, a few seconds), then its names — "alt <tab> key <tab> kind"
function placesScript() {
  return "[ -s \"$1\" ] || timeout 180 python3 \"$2\" \"$1\" >/dev/null 2>&1\n"
    + "[ -s \"$1\" ] && awk -F'\\t' '!/^#/ {print $12 \"\\t\" $1 \"\\t\" $2}' \"$1\"\n";
}

// what placesScript printed → the names; how many there are
function setIndex(text) {
  const keys = {}, main = {};
  let n = 0;
  for (const line of String(text || "").split("\n")) {
    const f = line.split("\t");
    if (f.length < 3 || !f[1]) continue;
    if (!keys[f[1]]) {
      keys[f[1]] = f[2];
      // its own name, not one it is also called: those are for finding a
      // place, never for offering one
      if (f[0] === "0" && f[1].length >= 3) {
        const b = f[1].slice(0, 3);
        (main[b] || (main[b] = [])).push(f[1]);
        n += 1;
      }
    }
  }
  INDEX = { keys: keys, main: main };
  return n;
}

// the countries people name by another code than ISO's
const QUALIFIERS = { uk: "gb", england: "gb", britain: "gb", usa: "us", america: "us" };

// "london ontario", "london, ontario", "london ca" → {name, qual}: a place
// the index has, and where — a province, a state, a country or its code
function qualified(word) {
  const w = placeKey(word).replace(/\s*,\s*/g, ", ");
  const isQual = (q) => INDEX.keys[q] === "r" || INDEX.keys[q] === "n"
    || /^[a-z]{2}$/.test(q) || Object.prototype.hasOwnProperty.call(QUALIFIERS, q);
  const comma = /^(.+?), (.+)$/.exec(w);
  if (comma && INDEX.keys[comma[1]] && isQual(comma[2]))
    return { name: comma[1], qual: QUALIFIERS[comma[2]] || comma[2] };
  const t = w.split(" ");
  for (let i = t.length - 1; i >= 1; --i) {
    const name = t.slice(0, i).join(" "), q = t.slice(i).join(" ");
    if (INDEX.keys[name] && isQual(q)) return { name: name, qual: QUALIFIERS[q] || q };
  }
  return null;
}

function inIndex(word) {
  return !!INDEX.keys[placeKey(word)] || !!qualified(word);
}

// the words as the scripts' place() reads them: "london,ontario", "new_york"
function placeQuery(word) {
  const q = qualified(word);
  const w = q ? q.name + "," + q.qual : placeKey(word);
  return w.replace(/\s+/g, "_");
}

// something that may be a zone, for the script to look up
function isZoneish(word) {
  const w = String(word || "").trim();
  if (isKnownZone(w)) return true;
  return /^[a-z][a-z .'_-]{3,}$/i.test(w) && !TIME_UNITS.test(w);
}

// "Tokyo", "New York", "here"
function placeLabel(word) {
  const w = String(word || "").trim().replace(/\s+time$/i, "");
  if (!w || /^(?:local|here)$/i.test(w)) return "here";
  if (/^[a-z]{2,5}$/i.test(w) && Object.prototype.hasOwnProperty.call(ZONES, w.toLowerCase()))
    return w.toUpperCase();
  if (/^(?:utc|gmt)\b/i.test(w)) return w.toUpperCase().replace(/\s+/g, "");
  // "london ontario" → "London, Ontario"; "london ca" → "London, CA"
  const q = w.indexOf(",") < 0 ? qualified(w) : null;
  if (q) return placeLabel(q.name) + ", " + (q.qual.length === 2 ? q.qual.toUpperCase() : placeLabel(q.qual));
  // nyc, la, sf, dc, uk, uae: initials, not words
  if (/^(?:nyc|la|sf|dc|uk|us|usa|uae|washington dc)$/i.test(w))
    return w.toUpperCase().replace(/^WASHINGTON DC$/, "Washington DC");
  return w.replace(/\b[a-z]/g, (c) => c.toUpperCase());
}

// "9am monday new york" → the time, a date (or ""), and the place — the
// date is however many words after the time parseDate takes, the rest the
// place
function splitWhenWhere(words, now) {
  const toks = String(words || "").trim().replace(/\s+time$/i, "").split(/\s+/);
  // places this file knows first, so "monday new york" is a day and a city
  // and not one place called that
  for (const test of [isKnownZone, isZoneish])
    for (let k = 0; k < toks.length; ++k) {
      const datePart = toks.slice(0, k).join(" ");
      const place = toks.slice(k).join(" ");
      // "tomorrow" is a day, never a place
      if (!test(place) || parseDate(place, now, 1)) continue;
      if (k === 0) return { date: "", dateWords: "", place: place };
      const d = parseDate(datePart, now, 1);
      if (d) return { date: isoDate(d), dateWords: datePart, place: place };
    }
  return null;
}

function tzPrepare(s, now) {
  now = now || new Date();
  const t = s.replace(/\bnoon\b/gi, "12:00").replace(/\bmidnight\b/gi, "00:00");
  let m;
  // time difference between tokyo and london · tokyo vs london
  if ((m = /^(?:(?:the\s+)?time\s+difference|difference|offset)\s+(?:between\s+)?(.+?)\s+(?:and|to|vs\.?|from)\s+(.+)$/i.exec(t))
      && isZoneish(m[1]) && isZoneish(m[2]))
    return tzDiff(m[1], m[2]);
  // time in tokyo · what time is it in new york · now in london
  if ((m = /^(?:what\s+)?(?:the\s+)?(?:time|now)\s+(?:is\s+it\s+)?(?:in|at)\s+(.+)$/i.exec(t)) && isZoneish(m[1]))
    return tz("now", "", "", m[1], "");
  // tokyo time · what's the time in tokyo was above
  if ((m = /^(.+?)\s+time$/i.exec(t)) && isKnownZone(m[1]))
    return tz("now", "", "", m[1], "");
  // 3pm [monday] new york [time] to tokyo
  if ((m = new RegExp("^" + TIME_RE + "\\s+(.+?)\\s+(?:to|in|as|into)\\s+(.+)$", "i").exec(t))
      && isZoneish(m[3])) {
    const ww = splitWhenWhere(m[2], now);
    if (ww) return tz(m[1], ww.date, ww.place, m[3], ww.dateWords);
  }
  // 3pm [tomorrow] in tokyo — yours, there
  if ((m = new RegExp("^" + TIME_RE + "(?:\\s+(.+?))?\\s+(?:to|in|as|into)\\s+(.+)$", "i").exec(t))
      && isZoneish(m[3])) {
    const d = m[2] ? parseDate(m[2], now, 1) : null;
    if (!m[2] || d) return tz(m[1], d ? isoDate(d) : "", "", m[3], m[2] || "");
  }
  // 3pm tokyo time · 9am monday new york — theirs, here
  if ((m = new RegExp("^" + TIME_RE + "\\s+(.+?)(?:\\s+time)?$", "i").exec(t))) {
    const ww = splitWhenWhere(m[2], now);
    if (ww && isKnownZone(ww.place)) return tz(m[1], ww.date, ww.place, "", ww.dateWords);
  }
  // tokyo to london, with no time: how far apart they are
  if ((m = /^(.+?)\s+(?:to|vs\.?|and)\s+(.+)$/i.exec(t)) && isKnownZone(m[1]) && isKnownZone(m[2]))
    return tzDiff(m[1], m[2]);
  return null;
}

// dateWords: the day as it was typed ("monday"), for the label
function tz(time, date, from, to, dateWords) {
  const when = time === "now" ? "now" : time + (dateWords ? " " + dateWords : "");
  const label = when + (from ? " " + placeLabel(from) : "") + " → " + placeLabel(to);
  return { kind: "tz", mode: "conv", time: time, date: date || "",
    from: zoneArg(from), to: zoneArg(to), fromWord: from, toWord: to, label: label };
}

function tzDiff(a, b) {
  return { kind: "tz", mode: "diff", time: "now", date: "",
    from: zoneArg(a), to: zoneArg(b), fromWord: a, toWord: b,
    label: placeLabel(a) + " → " + placeLabel(b) };
}

// ── what you typed → what qalc is asked ───────────────────────────────────
// Returns {kind:"qalc", expr, alt, target, …}, {kind:"tz", …}, {kind:"local",
// result, …} for what is worked out here (dates), or {bad:word}.
// `alt` is for "X at Y", which is X/Y for a distance at a speed but X·Y for a
// time at a speed or a weight at a price; the script asks qalc which one is a
// time and runs that one.
//
// ctx: {ans: the last kept answer, as qalc wrote it; now: a Date, for tests}
function prepare(input, ctx) {
  ctx = ctx || {};
  const now = ctx.now || new Date();
  const ans = String(ctx.ans || "");
  let s = String(input || "").trim().replace(/\s+/g, " ");
  s = s.replace(/[?!=]+$/, "").replace(/\s*\bplease\b\s*/gi, " ").trim();
  for (let i = 0; i < 3; ++i)
    s = s.replace(/^(?:what\s*(?:'s|’s|\s+is|\s+are)|whats|how\s+much\s+is|calculate|calc|compute|convert|evaluate|solve|work\s+out)\s+/i, "");
  s = s.replace(/\s*(?:->|→|=>)\s*/g, " to ");
  if (!s) return { kind: "qalc", expr: "" };

  // ── going on from the last answer ──
  // "* 2", "+ 15%", "to EUR" on their own carry on from it; "-5" is a number
  // and "- 5" is a continuation.
  if (continues(s, ans)) s = "ans " + s;
  if (/\bans\b/i.test(s)) {
    if (!ans) return { bad: "ans" };
    s = s.replace(/\bans\b/gi, ANS);
  }

  // ── rounding, asked for in words ──
  let round = null, m;
  if ((m = /\s*,?\s*(?:rounded\s+)?(?:to|in)\s+(\d+)\s*(?:decimals?|decimal\s+places?|dp|d\.p\.|places?)$/i.exec(s))) {
    round = { dp: Math.min(15, Number(m[1])) };
    s = s.slice(0, m.index);
  } else if ((m = /\s*,?\s*(?:rounded\s+)?(?:to|in)\s+(\d+)\s*(?:sig(?:nificant)?\.?\s*(?:figs?|figures|digits)|sf|s\.f\.)$/i.exec(s))) {
    round = { sig: Math.max(1, Math.min(15, Number(m[1]))) };
    s = s.slice(0, m.index);
  }
  if ((m = /^round(?:ed)?\s+(.+)$/i.exec(s))) { s = m[1]; if (!round) round = { dp: 0 }; }
  if ((m = /^(.+?),?\s+rounded$/i.exec(s))) { s = m[1]; if (!round) round = { dp: 0 }; }
  s = s.trim();

  const d = datePrepare(s, now);
  if (d) return d;

  const g = geoPrepare(s);
  if (g) return g;

  const z = tzPrepare(s, now);
  if (z) return z;

  // "how many feet in a mile" → "1 mile to feet"
  m = /^how\s+many\s+(.+?)\s+(?:are\s+(?:there\s+)?)?(?:in|per|make(?:\s+up)?)\s+(.+)$/i.exec(s);
  if (m) s = m[2] + " to " + m[1];
  // "5 km is how many miles"
  m = /^(.+?)\s+(?:is|are|equals?|makes?)\s+how\s+(?:many|much)\s+(.+)$/i.exec(s);
  if (m) s = m[1] + " to " + m[2];

  // ── running ──
  // "10k in 50 min" is a race, "10k usd" ten thousand dollars; a pace typed
  // as 5:30/km is 330 s/km to qalc.
  const race = /\b(?:pace|run|ran|race|marathon|jog|jogging|running)\b|\d+(?:\.\d+)?k\s+(?:in|at)\b/i.test(s);
  let pace = false;
  if (/\bpace\b/i.test(s)) {
    pace = true;
    s = s.replace(/\b(?:what(?:'s|\s+is)?\s+)?(?:the\s+|my\s+)?pace\s*(?:for|of|to\s+run|to\s+do|needed\s+for|if\s+i\s+run)?\s*/i, " ")
      .replace(/\s+pace\b/i, "").trim();
  }
  s = s.replace(/\b(?:an?\s+)?half[\s-]?marathons?\b/gi, "(21.0975 km)")
    .replace(/\b(?:an?\s+)?marathons?\b/gi, "(42.195 km)")
    .replace(/(\d+(?:\.\d+)?)k\b(?![\w/])/g, (all, n) => (race ? n + " km" : "(" + n + " × 1000)"))
    .replace(/(\d{1,2}):(\d{2})\s*(?:min(?:utes?)?\s*)?(?:\/|per\s+)\s*(km|kilomet(?:er|re)s?|mi|miles?)\b/gi,
      (all, mm, ss, u) => "(" + (Number(mm) * 60 + Number(ss)) + " s/" + (/^mi/i.test(u) ? "mi" : "km") + ")");
  if (race && /^(.+?)\s+in\s+(\d.*)$/i.test(s) && !/\s(?:to|as|into)\s/i.test(s)) pace = true;
  // a pace on its own is shown as one, not as 330 ms/m
  if ((m = /^\((\d+) s\/(km|mi)\)$/.exec(s))) return finish(s, "", "s/" + m[2], { pace: true });

  // "how long to drive 100 km at 60 km/h", "how far is 2 h at 60 mph"
  s = s.replace(/^how\s+(?:long|far)\s+(?:(?:does|will|would)\s+it\s+take\s+)?(?:is\s+|can\s+(?:i|you)\s+|do\s+(?:i|you)\s+|will\s+(?:i|you)\s+)?/i, "");
  s = s.replace(/^(?:to\s+)?(?:travel|drive|go|walk|run|cycle|bike|ride|fly|swim|download|upload|transfer|cover|copy)\s+/i, "");

  for (const [re, to] of ALIASES) s = s.replace(re, to);
  // "60 miles an hour" → "60 miles/hour"
  s = s.replace(new RegExp("([a-z°$€£¥])\\s+(?:an?|per|every|each)\\s+(" + PER_WORDS + ")\\b", "gi"), "$1/$2");
  // degrees: "30 degrees C", "30 deg f", "30C", "86 °f" → °C/°F
  s = s.replace(/(\d)\s*(?:degrees?|deg|°)\s*(c|f|celsius|fahrenheit)\b/gi,
    (all, dd, u) => dd + " °" + u[0].toUpperCase());
  // (not inside a hex number, where 0x1F is a number and not a temperature)
  if (!/0x/i.test(s))
    s = s.replace(/(\d)\s*([CcFf])(?![\w²³^/·*])/g, (all, dd, u) => dd + " °" + u.toUpperCase());
  s = s.replace(/\b(to|in|as|into)\s+(?:degrees?\s+|deg\s+|°)?([CcFf]|celsius|fahrenheit)$/i,
    (all, k, u) => k + " °" + u[0].toUpperCase());

  const extra = { round: round, pace: pace, ans: ans };

  const cook = cooking(s);
  if (cook) return finish(cook.expr, "", cook.target, Object.assign({ label: cook.label }, extra));

  const pct = percent(s);
  if (pct) return finish(pct.expr, "", pct.target, extra);

  // ── the conversion ──
  // The LAST keyword with a unit after it: "2 in to cm" is two inches to
  // centimetres, "5 in in cm" five inches in centimetres. A number after
  // "in" is not a target — "100 km in 2 h" is a speed.
  let left = s, target = "";
  const kw = /\s+(to|in|as|into)(?=\s+)/gi;
  const hits = [];
  let k;
  while ((k = kw.exec(s)) !== null) hits.push({ at: k.index, end: k.index + k[0].length });
  for (let i = hits.length - 1; i >= 0; --i) {
    const rhs = s.slice(hits[i].end).trim();
    if (!rhs || /^\d/.test(rhs)) continue;
    if (/^(?:to|in|as|into)\b/i.test(rhs)) continue;
    left = s.slice(0, hits[i].at).trim();
    target = rhs;
    break;
  }

  // A bare quantity keeps the unit it was typed in: "3 kWh" is otherwise
  // shown as 10.8 kg·m²/ms², and 8 L/100km as 80000 μm².
  let auto = false;
  if (!target && !/^\s*0[xbo]/i.test(left)) {
    if (/L\/\(100 km\)/.test(left)) target = "L/(100 km)";
    else if ((m = /^[−-]?\d[\d.,]*(?:E[−+-]?\d+)?\s*([A-Za-z°µμ$€£¥][A-Za-z°µμ_/²³^\d]*)$/.exec(left))
             && !/^(?:to|in|as|into)$/i.test(m[1]) && !/^e\d/i.test(m[1]))
      target = m[1];
    auto = target !== "";
  }

  // ── rates ──
  let expr = left, alt = "";
  if ((m = /^(.+?)\s+at\s+(.+)$/i.exec(left))) {
    expr = "(" + article(m[1]) + ") / (" + article(m[2]) + ")";
    alt = "(" + article(m[1]) + ") * (" + article(m[2]) + ")";
  } else if ((m = /^(.+?)\s+(?:in|over)\s+(\d.*)$/i.exec(left))) {
    if (pace) {
      // a pace is the time over the distance, per kilometre unless it was miles
      expr = "(" + m[2] + ") / (" + article(m[1]) + ")";
      if (!target) target = /\bmi(?:les?)?\b/i.test(m[1]) ? "s/mi" : "s/km";
    } else {
      expr = "(" + article(m[1]) + ") / (" + m[2] + ")";
    }
  } else if ((m = /^(.+?)\s+for\s+([\d(].*)$/i.exec(left))) {
    expr = "(" + article(m[1]) + ") * (" + m[2] + ")";
  } else {
    expr = article(left);
  }
  // "to min/mi", "to /km": a pace, shown as one
  if ((m = /^(?:min(?:utes?)?|s)?\s*(?:\/|per\s+)\s*(km|kilomet(?:er|re)|mi|mile)s?$/i.exec(target))) {
    target = /^mi/i.test(m[1]) ? "s/mi" : "s/km";
    extra.pace = true;
  }
  if (extra.pace && !/^s\/(?:km|mi)$/.test(target)) extra.pace = false;
  const out = finish(expr, alt, article(target), extra);
  if (auto && !out.bad) out.auto = true;
  return out;
}

// "a mile" → "1 mile"; "an hour" → "1 hour"; not "5 a" (five years)
function article(s) {
  return String(s || "").replace(/(^|[(+*/×-]\s*)(?:a|an|one)\s+(?=[a-z°$€£¥])/gi,
    (all, lead) => lead + "1 ");
}

function percent(s) {
  let m;
  const P = "(?:%|percent(?:age)?)";
  if ((m = new RegExp("^" + P + "\\s+change\\s+(?:from\\s+)?(.+?)\\s+to\\s+(.+)$", "i").exec(s)))
    return { expr: "((" + m[2] + ") - (" + m[1] + ")) / (" + m[1] + ")", target: "%" };
  if ((m = new RegExp("^(.+?)\\s+is\\s+what\\s+" + P + "\\s+of\\s+(.+)$", "i").exec(s)))
    return { expr: "(" + m[1] + ") / (" + m[2] + ")", target: "%" };
  if ((m = new RegExp("^what\\s+" + P + "\\s+of\\s+(.+?)\\s+is\\s+(.+)$", "i").exec(s)))
    return { expr: "(" + m[2] + ") / (" + m[1] + ")", target: "%" };
  if ((m = new RegExp("^(.+?)\\s+(?:as\\s+an?\\s+" + P + "\\s+of|out\\s+of)\\s+(.+)$", "i").exec(s)))
    return { expr: "(" + m[1] + ") / (" + m[2] + ")", target: "%" };
  if ((m = /^([\d.]+)\s*%\s+off\s+(.+)$/i.exec(s)))
    // m[1]/100 and not m[1]%: qalc asks which kind of percentage addition is
    // meant, on the very stream the reading is taken from
    return { expr: "(" + m[2] + ") × (1 − " + m[1] + "/100)", target: "" };
  if ((m = /^([\d.]+)\s*%\s+(more|higher|bigger|larger|greater|increase|up|less|lower|smaller|fewer|decrease|down|discount)(?:\s+(?:than|on|of|from))?\s+(.+)$/i.exec(s))) {
    const up = /^(more|higher|bigger|larger|greater|increase|up)$/i.test(m[2]);
    return { expr: "(" + m[3] + ") × (1 " + (up ? "+ " : "− ") + m[1] + "/100)", target: "" };
  }
  if (/%\s+of\s+/i.test(s))
    return { expr: s.replace(/([\d.]+)\s*%\s+of\s+/gi, "$1% × "), target: "" };
  return null;
}

function finish(expr, alt, target, extra) {
  const all = (expr + " " + (target || "")).replace(/"[^"]*"/g, " ").split(ANS).join(" ");
  const words = all.match(/[A-Za-z']+/g) || [];
  for (const w of words)
    if (STOPWORDS.indexOf(w.toLowerCase()) !== -1) return { bad: w };
  const t = target ? " to " + target : "";
  const a = "(" + ((extra && extra.ans) || "") + ")";
  const out = { kind: "qalc", expr: (expr + t).split(ANS).join(a),
    alt: alt ? (alt + t).split(ANS).join(a) : "", target: target || "" };
  if (extra) {
    if (extra.round) out.round = extra.round;
    if (extra.pace) out.pace = true;
    if (extra.label) out.label = extra.label;
  }
  return out;
}

// ── the run ───────────────────────────────────────────────────────────────
// $1 the expression, $2 its alternative (or ""), $3 its target (or "").
// Four sections:
//   the answer · qalc's own reading of the question (with its warnings and
//   errors) · the answer in base units, unprefixed · the expression used.
function calcScript() {
  return "e=$1\n"
    + "if [ -n \"$2\" ]; then\n"
    + "  b=$(" + QALC_BASE + " -- \"($1) to base\" 2>/dev/null)\n"
    + "  case \"$b\" in *[0-9]\" s\") ;; *) e=$2 ;; esac\n"
    + "fi\n"
    + "r=$(" + QALC + " -t -- \"$e\" 2>/dev/null)\n"
    // Nothing asked for and still raw SI (c is 299.79 km/ms to qalc): put it
    // in a unit a person would use.
    + "if [ -z \"$3\" ]; then\n"
    + "  case $r in\n"
    + "    *km/ms) e=\"($e) to m/s\" ;;\n"
    + "    *kg·*|*kg/*|*μm*|*nm²*) e=\"($e) to optimal\" ;;\n"
    + "    *) e=${e} ;;\n"
    + "  esac\n"
    + "  r=$(" + QALC + " -t -- \"$e\" 2>/dev/null)\n"
    + "fi\n"
    + "printf '%s\\n\\036\\n' \"$r\"\n"
    + QALC + " -- \"$e\" 2>&1\n"
    + "printf '\\036\\n'\n"
    + "[ -n \"$r\" ] && " + QALC_BASE + " -- \"($r) to base\" 2>/dev/null\n"
    + "printf '\\036\\n%s\\n' \"$e\"\n";
}

function stripAnsi(s) {
  return String(s || "").replace(/\u001b\[[0-9;]*m/g, "");
}

// "$56.12500000" → "$56.125", "€50.0000" → "€50", "1.00040 hp" → "1.0004 hp"
function trimZeros(s) {
  return String(s || "")
    .replace(/(\d\.\d*?[1-9])0+(?![\d])/g, "$1")
    .replace(/(\d)\.0+(?![\d])/g, "$1");
}

// qalc's own long names for a few units, in the short form the chip has room for
const DISPLAY = [
  [/\bkcal_th\b/g, "kcal"], [/\bcal_th\b/g, "cal"], [/\ba_j\b/g, "yr"],
  [/\bmegabits\b/g, "Mbit"], [/\bgigabits\b/g, "Gbit"], [/\bkilobits\b/g, "kbit"],
  [/\bknots?\b/g, "kn"], [/\bkW·h\b/g, "kWh"], [/\bliq_qt\b/g, "qt"],
  [/\bliq_pt\b/g, "pt"], [/\bstones\b/g, "st"], [/\bfl_oz\b/g, "fl oz"],
  [/\bbars\b/g, "bar"], [/\bgees\b/g, "g"], [/\btr\b/g, "turn"],
  [/ L \/ \(100 km\)/g, " L/100km"]
];

function tidy(s) {
  let t = trimZeros(stripAnsi(s).trim());
  for (const [re, to] of DISPLAY) t = t.replace(re, to);
  return t;
}

// The unit part of an answer: what is left with the numbers taken out
// (an exponent is part of the unit: s^−1 stays s^−1)
function unitOf(s) {
  return String(s || "")
    .replace(/(\^?)([−-]?[\d.,]+(?:E[−+-]?\d+)?)/g, (all, hat) => (hat ? all : ""))
    .replace(/\s+/g, " ").trim();
}

function numOf(s) {
  const m = /[−-]?\d[\d,]*(?:\.\d+)?(?:E[−+-]?\d+)?/.exec(String(s || ""));
  return m ? parseFloat(m[0].replace(/−/g, "-").replace(/,/g, "")) : NaN;
}

// A reading that multiplies three units straight into each other —
// "kilometer·inch·miles", "femtobyte·byte·bar" — is words read as units.
function looksLikeSalad(parse, base) {
  if (/[^\s()·×/]+(?:·[^\s()·×/]+){2,}/.test(parse)) return true;
  if (/\s×\s[a-z]\s×\s/.test(parse)) return true;
  const b = String(base || "");
  // m⁷, s^−5 … nothing real has a fourth power of a base unit
  if (/[⁴⁵⁶⁷⁸⁹]|\^[−-]?[4-9]/.test(b)) return true;
  // and nothing real squares a mass, a byte or a currency
  if (/(?:kg|bits?|B|€|\$|£|¥|cd|mol)(?:²|³|\^)/.test(b)) return true;
  return false;
}

// One calc run's output → what is shown.
//   {result, parse, base, expr} on an answer
//   {bad, word}                 on a question it could not read
//   {}                          on nothing (half-typed)
function readCalc(text, prep) {
  const parts = stripAnsi(text).split(SEP + "\n");
  // raw is what qalc said, for handing back to qalc (it reads "kn" as kilo-n
  // and "st" as a short ton); result is what is shown
  const raw = (parts[0] || "").trim();
  const result = tidy(raw);
  const verbose = (parts[1] || "").split("\n").map((l) => l.trim()).filter((l) => l !== "");
  const base = (parts[2] || "").trim();
  const expr = (parts[3] || "").trim();

  for (const l of verbose) {
    const e = /^error:\s*"([^"]+)" is not a valid/i.exec(l);
    if (e) return { bad: true, word: e[1] };
    if (/^error:/i.test(l)) return { bad: true, word: "" };
  }
  // only lines that are a reading and an answer — qalc also prints its own
  // questions ("Please select interpretation of …") on this stream
  const lines = verbose.filter((l) => !/^(?:warning|error):/i.test(l)
    && (l.indexOf(" = ") > 0 || l.indexOf(" ≈ ") > 0));
  if (!result) return {};

  let parse = "";
  if (lines.length > 1) {
    parse = lines[0];
  } else if (lines.length === 1) {
    const l = lines[0];
    const at = Math.max(l.lastIndexOf(" = "), l.lastIndexOf(" ≈ "));
    parse = at > 0 ? l.slice(0, at) : "";
  }
  if (looksLikeSalad(parse, base)) return { bad: true, word: "" };
  // a division by zero or a comparison left inside an answer is qalc
  // working around a question it misread ("23 usd to > egp" came back as
  // €(20.49 / 0)(1 EGP < 0)), not an answer
  if (/\/\s*0(?:\.0+)?\)|[<>≤≥]/.test(raw)) return { bad: true, word: "" };
  if (prep && prep.target && !prep.auto && !prep.pace && parse) parse += " → " + prep.target;
  if (prep && prep.label) parse = prep.label;

  let shown = result;
  const cat = categoryOf(base, result);
  if (prep && prep.pace) {
    // 300 s/km → 5:00 /km
    const sec = numOf(raw);
    if (isFinite(sec) && sec > 0)
      shown = paceText(sec, /mi/.test(prep.target) ? "/mi" : "/km");
  } else if (prep && prep.round) {
    shown = roundText(result, prep.round);
  } else if (cat && cat.name === "time" && (!prep || !prep.target || prep.auto)
             && numOf(base) >= 60) {
    // a time nobody asked to see in a unit reads as one: 1 h 40 min, not 1.666666667 h
    shown = duration(numOf(base));
  }
  return { result: shown, raw: raw, parse: parse, base: base, expr: expr,
    input: prep ? prep.expr : "", category: cat ? cat.name : "" };
}

// 330 → "5:30 /km"
function paceText(sec, per) {
  let m = Math.floor(sec / 60), ss = Math.round(sec - m * 60);
  if (ss === 60) { m += 1; ss = 0; }
  return m + ":" + String(ss).padStart(2, "0") + " " + per;
}

// ── time zones ────────────────────────────────────────────────────────────
// $1 conv|diff · $2 the time ("now", "3pm", "15:30") · $3 a date or "" ·
// $4 the zone it is in · $5 the zone it is wanted in. "" is local.
// conv prints  time zone · day | 12-hour | offset | yyyy-mm-dd | HH:MM where it was
// diff prints  offset-a | offset-b | now there in a | now there in b
// A place not found prints "?place".
// The zone lookup both scripts start with: $Z, and zone() — a place as the
// user wrote it (see zoneArg) to an IANA name, or a failure.
const ZONE_SH = "Z=/usr/share/zoneinfo\n"
    + "P=\"${XDG_CACHE_HOME:-$HOME/.cache}/metis-places.tsv\"\n"
    // the index's line for a place: "london", "new_york", "london,ontario"
    // (after the comma: a province, a state, a country or its code)
    + "place() {\n"
    + "  [ -f \"$P\" ] || return 1\n"
    + "  awk -F'\\t' -v q=\"$1\" 'BEGIN { q = tolower(q); gsub(/_/, \" \", q); n = q; c = \"\"\n"
    + "      i = index(q, \",\"); if (i) { n = substr(q, 1, i - 1); c = substr(q, i + 1) } }\n"
    + "    /^#/ { next }\n"
    + "    $1 == n && (c == \"\" || tolower($4) == c || tolower($5) == c || tolower($6) == c) { print; f = 1; exit }\n"
    + "    END { exit !f }' \"$P\"\n"
    + "}\n"
    + "zone() {\n"
    + "  case $1 in\n"
    + "    '') readlink /etc/localtime | sed 's|.*/zoneinfo/||' ;;\n"
    + "    */*|UTC|'<'*) printf '%s\\n' \"$1\" ;;\n"
    + "    *) r=$(place \"$1\") && { printf '%s\\n' \"$r\" | cut -f9; return 0; }\n"
    + "       f=$(find -L \"$Z\" \\( -path '*/posix' -o -path '*/right' \\) -prune"
    + " -o -type f -iname \"$1\" -print 2>/dev/null | head -n1)\n"
    + "       if [ -n \"$f\" ]; then printf '%s\\n' \"${f#$Z/}\"; return 0; fi\n"
    // a country by name: iso3166.tab has the code, zone.tab its main zone
    + "       n=$(printf '%s' \"$1\" | tr '_' ' ')\n"
    + "       c=$(awk -F'\\t' -v n=\"$n\" 'BEGIN{n=tolower(n)} !/^#/{l=tolower($2); sub(/ \\(.*/, \"\", l); if (l==n) {print $1; exit}}' \"$Z/iso3166.tab\")\n"
    + "       [ -n \"$c\" ] || return 1\n"
    + "       awk -F'\\t' -v c=\"$c\" '$1==c {print $3; exit}' \"$Z/zone.tab\" ;;\n"
    + "  esac\n"
    + "}\n";

function tzScript() {
  return ZONE_SH
    + "src=$(zone \"$4\") && [ -n \"$src\" ] || { printf '?%s\\n' \"$4\"; exit 0; }\n"
    + "dst=$(zone \"$5\") && [ -n \"$dst\" ] || { printf '?%s\\n' \"$5\"; exit 0; }\n"
    + "if [ \"$1\" = diff ]; then\n"
    + "  printf '%s|%s|%s|%s\\n' \"$(TZ=$src date +%z)\" \"$(TZ=$dst date +%z)\""
    + " \"$(TZ=$src date '+%H:%M %Z')\" \"$(TZ=$dst date '+%H:%M %Z')\"\n"
    + "  exit 0\n"
    + "fi\n"
    + "if [ \"$2\" = now ]; then at=now; else at=\"TZ=\\\"$src\\\" $3 $2\"; fi\n"
    + "out=$(TZ=$dst date -d \"$at\" '+%H:%M %Z · %a %-d %b|%-I:%M %p|%z|%F' 2>/dev/null)"
    + " || { printf '?%s\\n' \"$2\"; exit 0; }\n"
    + "printf '%s|%s\\n' \"$out\" \"$(TZ=$src date -d \"$at\" +%H:%M 2>/dev/null)\"\n";
}

// "+0530" → minutes east of UTC
function offMin(z) {
  const m = /^([+-])(\d{2})(\d{2})$/.exec(String(z || "").trim());
  return m ? (m[1] === "-" ? -1 : 1) * (Number(m[2]) * 60 + Number(m[3])) : NaN;
}
function offText(mins) {
  const a = Math.abs(mins), h = Math.floor(a / 60), mi = a % 60;
  return (h ? h + " h" : "") + (h && mi ? " " : "") + (mi ? mi + " min" : "");
}

function readTz(text, prep, now) {
  now = now || new Date();
  const out = stripAnsi(text).trim().split("\n")[0] || "";
  if (!out) return {};
  if (out[0] === "?") {
    const w = out.slice(1).replace(/_/g, " ");
    return { bad: true, word: w === "" ? "" : w };
  }
  const f = out.split("|");
  if (prep.mode === "diff") {
    const a = offMin(f[0]), b = offMin(f[1]);
    if (!isFinite(a) || !isFinite(b)) return {};
    const A = placeLabel(prep.fromWord), B = placeLabel(prep.toWord);
    const d = b - a;
    const result = d === 0 ? B + " is on " + A + "'s time"
      : B + " is " + offText(d) + (d > 0 ? " ahead of " : " behind ") + A;
    return { result: result, raw: "", parse: prep.label, base: "", expr: "", input: "",
      chips: [A + " " + (f[2] || ""), B + " " + (f[3] || "")],
      strip: [{ label: A, min: hmMin(f[2]) }, { label: B, min: hmMin(f[3]) }] };
  }
  // the day it lands on, when it is not today's
  const chips = [];
  if (f[1]) chips.push(f[1].replace(/^0/, "").replace(/ ([AP]M)$/, (all, x) => " " + x.toLowerCase()));
  if (f[3]) {
    const n = dayNum(new Date(Number(f[3].slice(0, 4)), Number(f[3].slice(5, 7)) - 1, Number(f[3].slice(8, 10))))
      - dayNum(dayOf(now));
    if (n !== 0) chips.push(n === 1 ? "tomorrow" : n === -1 ? "yesterday" : relText(n));
  }
  const o = offMin(f[2]);
  if (isFinite(o)) {
    const ao = Math.abs(o);
    chips.push(o === 0 ? "UTC" : "UTC" + (o < 0 ? "−" : "+") + Math.floor(ao / 60)
      + (ao % 60 ? ":" + String(ao % 60).padStart(2, "0") : ""));
  }
  // both places on one day: where the time was given, and where it lands
  const strip = [{ label: placeLabel(prep.fromWord), min: hmMin(f[4]) },
    { label: placeLabel(prep.toWord), min: hmMin(f[0]) }].filter((x) => isFinite(x.min));
  return { result: f[0], raw: "", parse: prep.label, base: "", expr: "", input: "",
    chips: chips, strip: strip };
}

// ── the chips ─────────────────────────────────────────────────────────────
// What an answer is a measure OF, read off its unprefixed base units, and the
// other units it is usually wanted in. Each list is in order of preference;
// whichever come out between 0.01 and 99999 are kept, so a short distance
// gets cm and inches and a long one km and miles without a table of ranges.
const CATEGORIES = [
  { sig: "m", name: "length", to: ["m", "km", "cm", "mm", "mi", "ft", "in", "yd", "nmi", "au", "ly"] },
  { sig: "m²", name: "area", to: ["m^2", "km^2", "ha", "acre", "ft^2", "mi^2", "cm^2", "in^2"] },
  { sig: "m³", name: "volume", to: ["L", "mL", "gal", "liq_qt", "cup", "floz", "tbsp", "tsp", "m^3", "ft^3", "gal_UK"] },
  { sig: "m/s", name: "speed", to: ["km/h", "mph", "m/s", "knot", "ft/s", "km/s"] },
  { sig: "m/s²", name: "accel", to: ["m/s^2", "ft/s^2", "g0"] },
  { sig: "K", name: "temp", to: ["°C", "°F", "K"], all: true },
  { sig: "kg", name: "mass", to: ["kg", "g", "lb", "oz", "stone", "t", "mg"] },
  { sig: "s", name: "time", to: ["s", "min", "h", "d", "week", "ms"] },
  { sig: "bits", name: "data", to: ["kB", "MB", "GB", "TB", "KiB", "MiB", "GiB", "TiB", "B", "Mbit", "Gbit"] },
  { sig: "bits/s", name: "rate", to: ["Mbit/s", "MB/s", "kbit/s", "kB/s", "Gbit/s", "GB/s"] },
  { sig: "kg·m²/s²", name: "energy", to: ["J", "kJ", "MJ", "kWh", "Wh", "kcal", "cal", "Btu", "eV"] },
  { sig: "kg·m²/s³", name: "power", to: ["W", "kW", "MW", "hp", "PS", "Btu/h"] },
  { sig: "kg·m/s²", name: "force", to: ["N", "kN", "lbf", "kgf"] },
  { sig: "kg/(m·s²)", name: "pressure", to: ["kPa", "bar", "psi", "atm", "mmHg", "Pa", "MPa", "hPa"] },
  { sig: "s^−1", name: "freq", to: ["Hz", "kHz", "MHz", "GHz"] },
  { sig: "s/m", name: "pace", to: [{ to: "s/km", pace: "/km" }, { to: "s/mi", pace: "/mi" },
    { to: "km/h", inv: true }, { to: "mph", inv: true }] },
  { sig: "m^−2", name: "fuel", to: ["mpg", "km/L", { to: "L/(100 km)", inv: true }] }
];

const CURRENCIES = ["USD", "EUR", "GBP", "JPY", "CNY", "CHF"];

function categoryOf(base, result) {
  const b = String(base || "").trim();
  if (/^[−-]?[$€£¥]/.test(b) || /^[$€£¥]/.test(result) || /\b[A-Z]{3}$/.test(result))
    return { name: "currency" };
  if (/°$|\brad$/.test(result)) return { name: "angle" };
  const sig = unitOf(b);
  if (sig === "") return /^[−-]?[\d.]+(?:E[−+-]?\d+)?$/.test(b) ? { name: "number" } : null;
  // volume per distance (L/100km) is an area to physics and a fuel figure to people
  if (sig === "m²" && Math.abs(numOf(b)) < 1e-6)
    return { name: "fuel", to: [{ to: "L/(100 km)" }, { to: "mpg", inv: true }, { to: "km/L", inv: true }] };
  for (const c of CATEGORIES) if (c.sig === sig) return c;
  return null;
}

// The chip list for an answer: [{line, pace?, label?}] for the chip run, plus
// any chip that needs no qalc at all (a duration, a height).
function chipPlan(calc) {
  const c = categoryOf(calc.base, calc.result);
  if (!c) {
    const only = [roundedChip(calc.result), wordScale(calc.result)].filter((x) => x !== "");
    return { lines: [], specs: [], local: only };
  }
  const v = numOf(calc.base);
  const r = calc.raw || calc.result;
  if (/%/.test(calc.result)) return { lines: [], specs: [], local: [] };
  // ten digits where three would do: the short form, first
  const short = roundedChip(calc.result);
  const specs = [], local = [];

  if (c.name === "number") {
    const n = numOf(r);
    if (!isFinite(n)) return { lines: [], specs: [], local: [] };
    // Bases only for a question that is about bases — "255", "0x1F", a shift
    // or a mask — and not for every whole number a sum comes to.
    const prog = /^\s*(?:0x[\da-f]+|0b[01]+|0o[0-7]+|\d+)\s*$|0x|0b|0o|<<|>>|&|\||\bxor\b/i
      .test(calc.input || "");
    if (Number.isInteger(n) && Math.abs(n) < 1e15) {
      if (!prog) return { lines: [], specs: [], local: [] };
      specs.push({ to: "hex" });
      if (Math.abs(n) < 65536) specs.push({ to: "bin" });
      specs.push({ to: "oct" });
    } else if (!Number.isInteger(n)) {
      specs.push({ to: "fraction", fraction: true, from: calc.expr });
      if (n > 0 && n < 1) specs.push({ to: "%" });
    }
    if (!/E/.test(r) && (Math.abs(n) >= 1e6 || (n !== 0 && Math.abs(n) < 1e-3)))
      specs.push({ to: "sci" });
  } else if (c.name === "currency") {
    for (const k of CURRENCIES) specs.push({ to: k });
  } else if (c.name === "angle") {
    specs.push({ to: "deg" }, { to: "rad" }, { to: "turn" });
  } else {
    for (const t of c.to) specs.push(typeof t === "string" ? { to: t } : t);
    if (c.name === "time" && v >= 60) local.push(duration(v));
    if (c.name === "length" && v > 0.3 && v < 3) local.push(feetInches(v));
    if (c.name === "speed" && v >= 1 && v <= 8)
      specs.push({ to: "s/km", inv: true, pace: "/km" }, { to: "s/mi", inv: true, pace: "/mi" });
    if (c.all) specs.forEach((s) => { s.all = true; });
  }
  // a fraction from the question rather than its rounded answer: 1/3 and not
  // 3333333333/1E10
  // 9,460,730,472,581 km is ≈ 9.46 trillion km to a person
  const words = wordScale(calc.result);
  if (words) local.unshift(words);
  if (short) local.unshift(short);
  const lines = specs.map((s) => (s.inv ? "1/(" + r + ")" : "(" + (s.from || r) + ")") + " to " + s.to);
  return { lines: lines, specs: specs, local: local };
}

function chipScript() {
  return "printf '%s\\n' \"$@\" | " + QALC_CHIP + " -f - 2>/dev/null\n";
}

// The chip run's lines, one per spec, → the chips, best first, at most six.
function readChips(text, plan, calc) {
  const out = stripAnsi(text).split("\n");
  const shown = unitOf(calc.result);
  const seen = {};
  seen[calc.result] = true;
  const chips = plan.local.filter((x) => x !== "" && !seen[x]);
  for (const x of chips) seen[x] = true;
  for (let i = 0; i < plan.specs.length && i < out.length; ++i) {
    const s = plan.specs[i];
    let t = tidy(out[i]);
    if (!t || /[·×]|\(/.test(t) && !s.to.includes("(")) continue;
    if (s.pace) {
      const sec = numOf(t);
      if (!isFinite(sec) || sec <= 0) continue;
      t = paceText(sec, s.pace);
    } else if (s.fraction) {
      if (/[E+]/.test(t) || !/\//.test(t) || t.length > 9) continue;
    } else if (!s.all && !/^(?:hex|bin|oct|sci|%)$/.test(s.to)) {
      // a tenth of a stone or a hundredth of a week says nothing
      const n = Math.abs(numOf(t));
      if (!(n >= 0.1 && n < 99999.5)) continue;
    }
    if (unitOf(t) === shown && !/^(?:hex|bin|oct|sci|fraction|%)$/.test(s.to)) continue;
    if (seen[t]) continue;
    // what was typed is not news: "5 km" under "5 km to mi"
    if ((" " + (calc.input || "") + " ").indexOf(" " + t + " ") !== -1) continue;
    seen[t] = true;
    chips.push(t);
  }
  return chips.slice(0, 6);
}

// 6000 → "1 h 40 min"; 90061 → "1 d 1 h 1 min"; 330 → "5 min 30 s"
function duration(sec) {
  let s = Math.round(Number(sec));
  if (!isFinite(s) || s < 60) return "";
  const parts = [];
  const units = [["yr", 31557600], ["d", 86400], ["h", 3600], ["min", 60], ["s", 1]];
  for (const [name, n] of units) {
    const q = Math.floor(s / n);
    if (q > 0) parts.push(q + " " + name);
    s -= q * n;
  }
  return parts.slice(0, 3).join(" ");
}

// 1.8796 → "6 ft 2 in"
function feetInches(m) {
  const inches = Number(m) / 0.0254;
  let ft = Math.floor(inches / 12);
  let inch = Math.round((inches - ft * 12) * 10) / 10;
  if (inch >= 12) { ft += 1; inch -= 12; }
  return ft + " ft " + (Math.round(inch * 10) / 10) + " in";
}

// ── rounding ──────────────────────────────────────────────────────────────
const NUM_RE = /[−-]?\d[\d,]*(?:\.\d+)?(?:E[−+-]?\d+)?/;

// The first number in an answer, rounded; the unit after it is left alone.
// {dp: 2} is decimal places, {sig: 3} significant figures.
function roundText(text, r) {
  const t = String(text || "");
  if (/^0x|^0b|^"/.test(t)) return t;
  const m = NUM_RE.exec(t);
  if (!m) return t;
  const n = parseFloat(m[0].replace(/−/g, "-").replace(/,/g, ""));
  if (!isFinite(n)) return t;
  let out;
  if (r.sig !== undefined) {
    out = String(Number(n.toPrecision(r.sig)));
  } else {
    out = n.toFixed(r.dp);
  }
  return t.slice(0, m.index) + out.replace(/^-/, "−") + t.slice(m.index + m[0].length);
}

// "3.106855961 mi" → "3.11 mi"; nothing for an answer that is already short
function roundedChip(result) {
  const t = String(result || "");
  const m = /^[^\d−-]*([−-]?\d+)\.(\d+)(?!\d|E)/.exec(t);
  if (!m || m[2].length < 5 || /^0x|^"/.test(t)) return "";
  const n = Math.abs(parseFloat(m[1] + "." + m[2]));
  const r = n >= 1 ? roundText(t, { dp: 2 }) : roundText(t, { sig: 3 });
  return r === t ? "" : r;
}

// ── reading long numbers ──────────────────────────────────────────────────
// 9460730472581 → 9,460,730,472,581. For the eye only: what is copied is the
// answer as qalc gave it. Four digits stay as they are (a year, 5280 ft), and
// nothing after a decimal point, inside a hex number or in a date is touched.
function group(text) {
  return String(text || "").replace(/(^|[^\d.,\w])(\d{5,})(?![\d])/g,
    (all, lead, digits) => lead + digits.replace(/\B(?=(\d{3})+$)/g, ","));
}

// ── dates ─────────────────────────────────────────────────────────────────
// Worked out here rather than by qalc: "days until christmas" needs to know
// which christmas, and "how old" wants years and months, not 32.5667 a_j.
const MONTHS = ["january", "february", "march", "april", "may", "june", "july",
  "august", "september", "october", "november", "december"];
const WDAYS = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];
const HOLIDAYS = [
  [/^(?:christmas|xmas)(?:\s+day)?$/, 12, 25],
  [/^(?:christmas|xmas)\s+eve$/, 12, 24],
  [/^new\s*years?'?s?\s+eve$|^nye$/, 12, 31],
  [/^new\s*years?'?s?(?:\s+day)?$/, 1, 1],
  [/^halloween$/, 10, 31],
  [/^valentine'?s?(?:\s+day)?$/, 2, 14]
];

function dayOf(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()); }
function dayNum(d) { return Math.round(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()) / 86400000); }
function daysIn(y, m0) { return new Date(y, m0 + 1, 0).getDate(); }
function mkDate(y, m0, dd) {
  const d = new Date(y, m0, dd);
  return d.getFullYear() === y && d.getMonth() === m0 && d.getDate() === dd ? d : null;
}

function monthIndex(w) {
  const t = String(w || "").toLowerCase().replace(/\.$/, "");
  if (t.length < 3) return -1;
  for (let i = 0; i < 12; ++i)
    if (MONTHS[i].indexOf(t) === 0 || (t === "sept" && i === 8)) return i;
  return -1;
}

// A month and day with no year: the next one (dir > 0), the last one (dir < 0)
// or this year's (0).
function pickYear(m0, dd, today, dir) {
  const y = today.getFullYear();
  let d = mkDate(y, m0, dd);
  if (!d) return null;
  if (dir > 0 && dayNum(d) < dayNum(today)) d = mkDate(y + 1, m0, dd);
  if (dir < 0 && dayNum(d) > dayNum(today)) d = mkDate(y - 1, m0, dd);
  return d;
}

function parseDate(str, now, dir) {
  const today = dayOf(now);
  let t = String(str || "").trim().toLowerCase()
    .replace(/^the\s+/, "").replace(/[,.]+$/, "").replace(/(\d)(?:st|nd|rd|th)\b/g, "$1")
    .replace(/\s+/g, " ");
  let m;
  if (t === "today" || t === "now") return today;
  if (t === "tomorrow") return new Date(today.getFullYear(), today.getMonth(), today.getDate() + 1);
  if (t === "yesterday") return new Date(today.getFullYear(), today.getMonth(), today.getDate() - 1);

  let lean = dir, strict = false;
  if ((m = /^(next|this|coming|last)\s+(.+)$/.exec(t))) {
    lean = m[1] === "last" ? -1 : 1;
    strict = m[1] === "next";   // next friday, on a friday, is a week away
    t = m[2];
  }
  for (const [re, mo, dd] of HOLIDAYS)
    if (re.test(t)) return pickYear(mo - 1, dd, today, lean === 0 ? 1 : lean);

  if ((m = /^(sun|mon|tues?|wed(?:nes)?|thu(?:rs?)?|fri|sat(?:ur)?)(?:day)?$/.exec(t))) {
    const want = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"].indexOf(m[1].slice(0, 3));
    const cur = today.getDay();
    let off;
    if (lean < 0) off = -(((cur - want) + 7) % 7 || 7);
    else if (strict) off = ((want - cur) + 7) % 7 || 7;
    else off = ((want - cur) + 7) % 7;
    return new Date(today.getFullYear(), today.getMonth(), today.getDate() + off);
  }
  if ((m = /^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$/.exec(t)))
    return mkDate(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  // 12 march 1994 · 12 mar
  if ((m = /^(\d{1,2}) ([a-z]{3,})\.?(?: (\d{4}))?$/.exec(t))) {
    const mo = monthIndex(m[2]);
    if (mo < 0) return null;
    return m[3] ? mkDate(Number(m[3]), mo, Number(m[1])) : pickYear(mo, Number(m[1]), today, lean);
  }
  // march 12 1994 · march 12, 1994 · mar 12
  if ((m = /^([a-z]{3,})\.? (\d{1,2})(?:,? (\d{4}))?$/.exec(t))) {
    const mo = monthIndex(m[1]);
    if (mo < 0) return null;
    return m[3] ? mkDate(Number(m[3]), mo, Number(m[2])) : pickYear(mo, Number(m[2]), today, lean);
  }
  // 25/12/2026, the unambiguous way round only
  if ((m = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(t))) {
    const a = Number(m[1]), b = Number(m[2]);
    if (a > 12) return mkDate(Number(m[3]), b - 1, a);
    if (b > 12) return mkDate(Number(m[3]), a - 1, b);
  }
  return null;
}

function fmtDate(d) {
  return WDAYS[d.getDay()].slice(0, 3).replace(/^./, (c) => c.toUpperCase()) + " "
    + d.getDate() + " " + MONTHS[d.getMonth()].slice(0, 3).replace(/^./, (c) => c.toUpperCase())
    + " " + d.getFullYear();
}
function isoDate(d) {
  return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-"
    + String(d.getDate()).padStart(2, "0");
}
function plural(n, w) { return n + " " + w + (n === 1 ? "" : "s"); }

// calendar years, months and days from a to b (a ≤ b)
function diffParts(a, b) {
  let y = b.getFullYear() - a.getFullYear();
  let mo = b.getMonth() - a.getMonth();
  let dd = b.getDate() - a.getDate();
  if (dd < 0) { mo -= 1; dd += daysIn(b.getFullYear(), (b.getMonth() + 11) % 12); }
  if (mo < 0) { y -= 1; mo += 12; }
  return { y: y, m: mo, d: dd };
}
function partsText(p) {
  const out = [];
  if (p.y) out.push(plural(p.y, "year"));
  if (p.m) out.push(plural(p.m, "month"));
  if (p.d || out.length === 0) out.push(plural(p.d, "day"));
  return out.join(" ");
}
function relText(n) {
  return n === 0 ? "today" : n === 1 ? "tomorrow" : n === -1 ? "yesterday"
    : n > 0 ? "in " + plural(n, "day") : plural(-n, "day") + " ago";
}

function addTo(d, n, unit) {
  const u = unit.toLowerCase()[0];
  if (u === "d") return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n);
  if (u === "w") return new Date(d.getFullYear(), d.getMonth(), d.getDate() + 7 * n);
  const months = u === "y" ? 12 * n : n;
  const y = d.getFullYear() + Math.floor((d.getMonth() + months) / 12);
  const m0 = ((d.getMonth() + months) % 12 + 12) % 12;
  return new Date(y, m0, Math.min(d.getDate(), daysIn(y, m0)));
}

// A span of days, said the way it was asked for, with the other ways as chips
function span(from, to, unit, label, now, shown) {
  const n = dayNum(to) - dayNum(from);
  const a = n >= 0 ? from : to, b = n >= 0 ? to : from;
  const abs = Math.abs(n);
  const p = diffParts(a, b);
  const weeks = Math.floor(abs / 7) ? plural(Math.floor(abs / 7), "week")
    + (abs % 7 ? " " + plural(abs % 7, "day") : "") : "";
  let main;
  const u = (unit || "days").toLowerCase();
  if (u[0] === "w" && weeks) main = weeks;
  else if ((u[0] === "m" || u[0] === "y") && abs >= 28) main = partsText(p);
  else if (u[0] === "h") main = Math.round(Math.abs(to - now) / 3600000) + " hours";
  else main = plural(abs, "day");
  const chips = [plural(abs, "day"), weeks, abs >= 28 ? partsText(p) : "", fmtDate(shown || to)]
    .filter((c) => c !== "" && c !== main);
  // a wait of up to a year, drawn as how much of it is behind you
  const today = dayOf(now);
  const progress = n > 0 && dayNum(from) === dayNum(today) ? yearProgress(to, today) : null;
  return local(main + (n < 0 ? " ago" : ""), abs + " d", label, chips,
    progress ? { progress: progress } : null);
}

function local(result, raw, parse, chips, extra) {
  return Object.assign({ kind: "local", category: "date", result: result, raw: raw, parse: parse,
    chips: (chips || []).filter((c) => c && c !== result).slice(0, 6) }, extra || {});
}

// How far through a year-long wait today is: from the same date a year
// before to the one awaited. {from, to, frac} with the ends as dates.
function yearProgress(target, today) {
  const start = addTo(target, -1, "year");
  const total = dayNum(target) - dayNum(start);
  const done = dayNum(today) - dayNum(start);
  if (total <= 0 || done < 0 || done > total) return null;
  return { from: fmtDate(start), to: fmtDate(target), frac: done / total };
}

// clock time → minutes after midnight ("9:15", "5:40 pm", "noon")
function clockMin(str) {
  const t = String(str || "").trim().toLowerCase();
  if (t === "noon") return 720;
  if (t === "midnight") return 0;
  const m = /^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$/.exec(t);
  if (!m || (!m[2] && !m[3])) return -1;
  let h = Number(m[1]);
  const mi = Number(m[2] || 0);
  if (m[3]) { if (h === 12) h = 0; if (m[3] === "pm") h += 12; }
  return h < 24 && mi < 60 ? h * 60 + mi : -1;
}

function datePrepare(s, now) {
  const today = dayOf(now);
  let m;

  // days until christmas · how long until friday · weeks till 2027-01-01
  if ((m = /^(?:how\s+(?:many\s+)?(days|weeks|months|hours|sleeps)|(days|weeks|months|hours|sleeps)|how\s+long|time|countdown)\s+(?:is\s+it\s+|are\s+there\s+|left\s+|remain(?:ing)?\s+)?(?:until|till|til|before|to)\s+(.+?)(?:\s+left)?$/i.exec(s))) {
    const d = parseDate(m[3], now, 1);
    if (d) return span(today, d, m[1] || m[2] || "days", "today → " + fmtDate(d), now);
  }
  // days since 1994-03-12 · how long ago was new year
  if ((m = /^(?:how\s+(?:many\s+)?(days|weeks|months|years)|(days|weeks|months|years)|how\s+long|time)\s+(?:has\s+it\s+been\s+|have\s+passed\s+|passed\s+|elapsed\s+)?(?:since|ago\s+was|ago\s+is)\s+(.+)$/i.exec(s))) {
    const d = parseDate(m[3], now, -1);
    if (d) return span(d, today, m[1] || m[2] || "days", fmtDate(d) + " → today", now, d);
  }
  // time between 9:15 and 17:40 · days between two dates · from X to Y
  if ((m = /^(?:(days|weeks|months|years|time|hours)\s+)?(?:between|from)\s+(.+?)\s+(?:and|to|until|till)\s+(.+)$/i.exec(s))) {
    const c1 = clockMin(m[2]), c2 = clockMin(m[3]);
    if (c1 >= 0 && c2 >= 0) return clockSpan(c1, c2, m[2], m[3]);
    const a = parseDate(m[2], now, 0), b = parseDate(m[3], now, 0);
    if (a && b) return span(a, b, m[1] || "days", fmtDate(a) + " → " + fmtDate(b), now);
  }
  // 9:15 to 17:40
  if ((m = /^(\S+(?:\s*[ap]m)?)\s+(?:to|until|till|–|-)\s+(\S+(?:\s*[ap]m)?)$/i.exec(s))) {
    const c1 = clockMin(m[1]), c2 = clockMin(m[2]);
    if (c1 >= 0 && c2 >= 0) return clockSpan(c1, c2, m[1], m[2]);
  }
  // age 1994-03-12 · how old is someone born 12 march 1994
  if ((m = /^(?:age(?:\s+of)?(?:\s+someone)?(?:\s+born)?|how\s+old\s+(?:is|am|are|was|will|would)\s+(?:\S+\s+){0,3}?(?:if\s+)?(?:born|b\.)|born)\s+(?:on\s+|in\s+)?(.+)$/i.exec(s))) {
    const b = parseDate(m[1], now, -1);
    if (b && dayNum(b) <= dayNum(today)) {
      const p = diffParts(b, today);
      let next = mkDate(today.getFullYear(), b.getMonth(), Math.min(b.getDate(), daysIn(today.getFullYear(), b.getMonth())));
      if (dayNum(next) < dayNum(today)) next = mkDate(today.getFullYear() + 1, b.getMonth(), Math.min(b.getDate(), daysIn(today.getFullYear() + 1, b.getMonth())));
      const toNext = dayNum(next) - dayNum(today);
      const days = dayNum(today) - dayNum(b);
      const pr = toNext > 0 ? yearProgress(next, today) : null;
      return local(partsText(p), days + " d", "born " + fmtDate(b), [
        plural(p.y, "year"), plural(days, "day"),
        toNext === 0 ? "birthday today" : "birthday " + relText(toNext),
        "born on a " + WDAYS[b.getDay()].replace(/^./, (c) => c.toUpperCase())
      ], pr ? { progress: pr } : null);
    }
  }
  // what day is christmas · weekday of 2027-01-01 · what day was 12 march 1994
  if ((m = /^(?:what\s+)?(?:day(?:\s+of\s+the\s+week)?|weekday)\s+(?:is|was|will\s+be|falls\s+on|of|for|does)?\s*(.+?)(?:\s+(?:on|fall\s+on|be\s+on))?$/i.exec(s))) {
    const d = parseDate(m[1], now, 1);
    if (d) {
      const n = dayNum(d) - dayNum(today);
      return local(WDAYS[d.getDay()].replace(/^./, (c) => c.toUpperCase()), JSON.stringify(isoDate(d)),
        fmtDate(d), [relText(n), isoDate(d)]);
    }
  }
  // 90 days from now · 3 weeks ago · in 10 days · 2 months after christmas
  if ((m = /^(?:in\s+)?(\d+)\s*(days?|weeks?|wks?|months?|mos?|years?|yrs?)\s+(from\s+(?:now|today)|later|ago|(?:after|from|before)\s+(.+))$/i.exec(s))
      || (m = /^in\s+(\d+)\s*(days?|weeks?|months?|years?)()$/i.exec(s))) {
    const n = Number(m[1]);
    let base = today, sign = 1;
    if (m[3] && /^ago$/i.test(m[3])) sign = -1;
    if (m[4]) {
      base = parseDate(m[4], now, 1);
      if (!base) return null;
      if (/^before/i.test(m[3])) sign = -1;
    }
    return dateAnswer(addTo(base, sign * n, m[2]), today, s);
  }
  // today + 90 days · christmas - 2 weeks · 2026-01-01 + 1 month
  if ((m = /^(.+?)\s*([+-])\s*(\d+)\s*(days?|weeks?|months?|years?)$/i.exec(s))) {
    const base = parseDate(m[1], now, 1);
    if (base) return dateAnswer(addTo(base, (m[2] === "-" ? -1 : 1) * Number(m[3]), m[4]), today, s);
  }
  // a date on its own: christmas · next friday · 2027-01-01
  if (/^(?:(?:next|this|last|coming)\s+)?[a-z' ]+$|^\d{4}-\d{1,2}-\d{1,2}$/i.test(s)) {
    const d = parseDate(s, now, 1);
    if (d) return dateAnswer(d, today, "");
  }
  return null;
}

function dateAnswer(d, today, label) {
  const n = dayNum(d) - dayNum(today);
  return local(fmtDate(d), JSON.stringify(isoDate(d)), label, [relText(n), isoDate(d)]);
}

function clockSpan(c1, c2, a, b) {
  let mins = c2 - c1;
  if (mins < 0) mins += 1440;   // across midnight
  const h = Math.floor(mins / 60), mi = mins % 60;
  const main = h && mi ? h + " h " + mi + " min" : h ? h + " h" : mi + " min";
  return local(main, mins + " min", a + " → " + b,
    [plural(mins, "minute"), Math.round(mins / 60 * 100) / 100 + " h"], { category: "clock" });
}

// ── cooking ───────────────────────────────────────────────────────────────
// A cup is a volume and a gram a mass, so "2 cups flour to grams" needs what
// a cup of flour weighs. Grams per US cup, from the usual baking tables.
const INGREDIENTS = [
  ["(?:all[\\s-]purpose\\s+|plain\\s+)?flour", 125, "flour"],
  ["bread\\s+flour", 130, "bread flour"],
  ["(?:whole\\s*wheat|wholemeal)\\s+flour", 120, "whole wheat flour"],
  ["almond\\s+(?:flour|meal)", 96, "almond flour"],
  ["(?:powdered|icing|confectioners'?)\\s+sugar", 120, "powdered sugar"],
  ["brown\\s+sugar", 220, "brown sugar"],
  ["(?:granulated\\s+|white\\s+|caster\\s+)?sugar", 200, "sugar"],
  ["butter", 227, "butter"],
  ["(?:olive\\s+|vegetable\\s+|canola\\s+|sunflower\\s+)?oil", 218, "oil"],
  ["water", 237, "water"],
  ["(?:whole\\s+|skim\\s+)?milk", 244, "milk"],
  ["(?:heavy\\s+|whipping\\s+|double\\s+|single\\s+)?cream", 238, "cream"],
  ["honey", 340, "honey"],
  ["maple\\s+syrup", 312, "maple syrup"],
  ["(?:uncooked\\s+|white\\s+)?rice", 185, "rice"],
  ["(?:rolled\\s+)?oats", 90, "oats"],
  ["cocoa(?:\\s+powder)?", 84, "cocoa"],
  ["(?:table\\s+)?salt", 273, "salt"],
  ["baking\\s+soda", 288, "baking soda"],
  ["baking\\s+powder", 192, "baking powder"],
  ["(?:corn\\s*starch|cornflour)", 120, "cornstarch"],
  ["(?:greek\\s+)?yogh?urt", 245, "yogurt"],
  ["peanut\\s+butter", 256, "peanut butter"],
  ["chocolate\\s+chips", 170, "chocolate chips"]
];
const VOL_RE = /\b(?:cup|tbsp|tsp|mL|ml|L|l|floz|liq_qt|liq_pt|gal|gal_UK|pt_UK|liters?|litres?|milliliters?|millilitres?)\b/;
const MASS_RE = /\b(?:g|kg|mg|oz|lb|grams?|kilograms?|ounces?|pounds?)\b/i;

function cooking(s) {
  const t = s.replace(/\b(\d+(?:\.\d+)?|an?|one)\s+sticks?\b(?:\s+of)?/gi,
    (all, n) => "(" + (isNaN(Number(n)) ? 1 : n) + " × 0.5 cup)");
  for (const [src, perCup, name] of INGREDIENTS) {
    const m = new RegExp("^(.*\\d.*?)\\s+(?:of\\s+)?(" + src + ")(?:\\s+(?:to|in|as|into)\\s+(.+))?$", "i").exec(t);
    if (!m) continue;
    const qty = m[1].trim();
    const vol = VOL_RE.test(qty), mass = MASS_RE.test(qty);
    if (!vol && !mass) return null;
    let target = (m[3] || "").trim();
    if (!target) target = vol ? "g" : "cup";
    const tVol = VOL_RE.test(target), tMass = MASS_RE.test(target);
    // per cup, as the table has it: 2 cups of flour is 250 g and not 249.98
    const rho = "(" + perCup + " g/cup)";
    let expr = "(" + qty + ")";
    if (vol && tMass) expr += " × " + rho;
    else if (mass && tVol) expr += " / " + rho;
    else if (!tVol && !tMass) return null;
    return { expr: expr, target: target,
      label: qty + " " + name + " → " + target + "   (" + perCup + " g a cup)" };
  }
  return null;
}

// ── did you mean ──────────────────────────────────────────────────────────
// qalc's data files, as `grep -o '<names>…</names>'` gives them, → every
// name it answers to. `qalc --list-units` will not do: without a search term
// it leaves out the currencies. "a-cr:EUR,au:€,euro,p:euros" → EUR € euro euros
function parseNames(text) {
  const out = [];
  const re = /<names>([^<]*)<\/names>/g;
  let m;
  while ((m = re.exec(String(text || ""))) !== null)
    for (const n of m[1].split(",")) {
      const w = n.replace(/^[a-z-]*:/, "").trim();
      if (/^[A-Za-z_][\w]*$/.test(w)) out.push(w);
    }
  return out;
}

// what the name check reads: the four data files, then the prefixes
function namesScript() {
  return "d=/usr/share/qalculate\n"
    + "cat \"$d/units.xml\" \"$d/currencies.xml\" \"$d/variables.xml\" \"$d/functions.xml\" 2>/dev/null"
    + " | grep -o '<names>[^<]*</names>'\n"
    + "printf '\\036\\n'\n"
    + "grep -o '<names>[^<]*</names>' \"$d/prefixes.xml\" 2>/dev/null\n";
}

function readNames(text) {
  const parts = String(text || "").split(SEP + "\n");
  return { names: parseNames(parts[0] || ""), prefixes: parseNames(parts[1] || "") };
}

// words qalc takes that are in none of its files
const KNOWN = ["today", "now", "yesterday", "tomorrow", "hex", "bin", "oct", "sci",
  "fraction", "base", "optimal", "mixed", "decimals", "x", "y", "z", "i", "e",
  "pi", "ans", "to"];

// The everyday names, looked at first and preferred on a tie: qalc knows
// "pouce" and "pond", and nobody who typed "pund" meant either.
const COMMON = [
  "m", "km", "cm", "mm", "mi", "ft", "in", "yd", "nmi", "kg", "g", "mg", "lb", "oz",
  "L", "mL", "gal", "cup", "tbsp", "tsp", "floz", "s", "min", "h", "d", "week",
  "year", "mph", "knot", "J", "kJ", "kWh", "W", "kW", "hp", "N", "Pa", "kPa", "bar",
  "psi", "atm", "Hz", "B", "kB", "MB", "GB", "TB", "bit", "acre", "ha",
  "meters", "metres", "kilometers", "kilometres", "centimeters", "millimeters",
  "miles", "feet", "foot", "inches", "inch", "yards", "grams", "kilograms",
  "pounds", "ounces", "liters", "litres", "milliliters", "gallons", "cups",
  "seconds", "minutes", "hours", "days", "weeks", "years", "celsius",
  "fahrenheit", "kelvin", "joules", "calories", "watts", "newtons", "pascals",
  "bytes", "kilobytes", "megabytes", "gigabytes", "acres", "hectares",
  "sqrt", "sin", "cos", "tan", "log", "ln", "abs", "round", "floor", "ceil", "pi"
];

// edit distance, with two swapped letters as one edit ("miels" is one from "miles")
function lev(a, b) {
  const m = a.length, n = b.length;
  const d = [];
  for (let i = 0; i <= m; ++i) { d.push([i]); for (let j = 1; j <= n; ++j) d[i].push(i ? 0 : j); }
  for (let i = 1; i <= m; ++i)
    for (let j = 1; j <= n; ++j) {
      d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1,
        d[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
      if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1])
        d[i][j] = Math.min(d[i][j], d[i - 2][j - 2] + 1);
    }
  return d[m][n];
}

// "mtrs" is in "meters" in order: the way people shorten a word
function subseq(w, c) {
  let i = 0;
  for (const ch of c) if (ch === w[i]) i += 1;
  return i === w.length;
}

function suggest(word, names) {
  const w = String(word || "");
  const lw = w.toLowerCase();
  if (lw.length < 2 || STOPWORDS.indexOf(lw) !== -1) return [];
  const seen = {}, scored = [];
  // and places, from the index's bucket for the word's first letters:
  // "torontoo" is Toronto
  const pool = COMMON.concat(names || [], INDEX.main[lw.slice(0, 3)] || []);
  for (let i = 0; i < pool.length; ++i) {
    const c = pool[i], lc = c.toLowerCase();
    if (seen[lc] || lc === lw) continue;
    seen[lc] = true;
    let d = lev(lw, lc);
    const sub = lc[0] === lw[0] && lw.length >= 2 && subseq(lw, lc) && lc.length <= lw.length * 3;
    if (sub) d = Math.min(d, 1.5);
    const ok = d <= Math.max(1, Math.floor(lw.length / 3)) || sub;
    if (ok) scored.push({ c: c, d: d + (i < COMMON.length ? 0 : 0.5), i: i });
  }
  scored.sort((a, b) => a.d - b.d || a.i - b.i);
  return scored.slice(0, 3).map((x) => x.c);
}

// The word in a question qalc misread without complaint ("mtrs" as
// milli-tonne·r·s): the first one it has no name for. Prefixed units
// (km, MiB) and plurals (meters) count as known.
function culprit(expr, names, prefixes) {
  const known = {};
  for (const n of (names || []).concat(COMMON, KNOWN)) { known[n] = true; known[n.toLowerCase()] = true; }
  const pre = (prefixes || []).slice().sort((a, b) => b.length - a.length);
  const isKnown = (w) => {
    if (known[w] || known[w.toLowerCase()]) return true;
    if (/s$/.test(w) && (known[w.slice(0, -1)] || known[w.slice(0, -1).toLowerCase()])) return true;
    for (const p of pre)
      if (w.length > p.length && w.indexOf(p) === 0 && known[w.slice(p.length)]) return true;
    return false;
  };
  // numbers out first: 0x1F and 1E5 are not words
  const bare = String(expr || "").replace(/"[^"]*"/g, " ")
    .replace(/\b0x[\da-f]+\b|\b0b[01]+\b|\b0o[0-7]+\b/gi, " ")
    .replace(/\d+(?:\.\d+)?(?:e[−+-]?\d+)?/gi, " ");
  const words = bare.match(/[A-Za-z_][A-Za-z_\d]*/g) || [];
  for (const w of words)
    if (w.length > 1 && !/^(?:to|in|as|into)$/i.test(w) && !isKnown(w)) return w;
  return "";
}

// ── exchange rates ────────────────────────────────────────────────────────
// How old the rates on disk are, said only once it matters. They are fetched
// at most twice a day while metis is used, so a day old means fetching failed.
function ratesNote(ageSec) {
  const a = Number(ageSec);
  if (!isFinite(a)) return "";
  if (a < 0) return "no exchange rates";
  if (a < 86400) return "";
  const d = Math.floor(a / 86400);
  return "rates " + plural(d, "day") + " old";
}

// The word to blame for a question that failed, and what to offer instead.
// qalc's own error names a fragment at times ("r" out of "cps"), so a single
// letter defers to the name check, which reads whole words.
function badWord(calc, prep, names, prefixes) {
  const w = calc && calc.word ? String(calc.word) : "";
  if (w.length > 1) return w;
  const c = culprit(prep ? prep.expr : "", names, prefixes);
  return c || w;
}

// ── history ───────────────────────────────────────────────────────────────
// Kept answers, newest first: what you asked, what was shown, and what qalc
// said (so `ans` is the full answer and not the rounded one on screen).
function historyPath() {
  return Paths.cacheDir() + "/metis-history";
}

const HISTORY_MAX = 50;

function parseHistory(text) {
  let rows;
  try { rows = JSON.parse(String(text || "")); } catch (e) { return []; }
  if (!Array.isArray(rows)) return [];
  return rows.filter((r) => r && typeof r.expr === "string" && typeof r.result === "string"
    && r.expr !== "" && r.result !== "")
    .map((r) => ({ expr: r.expr, result: r.result, raw: typeof r.raw === "string" ? r.raw : "",
      parse: typeof r.parse === "string" ? r.parse : "",
      kind: typeof r.kind === "string" && knownKind(r.kind) ? r.kind : "calc" }))
    .slice(0, HISTORY_MAX);
}

function addHistory(rows, row) {
  const h = (rows || []).filter((x) => x.expr !== row.expr || x.result !== row.result);
  h.unshift(row);
  return h.slice(0, HISTORY_MAX);
}

function serializeHistory(rows) {
  return JSON.stringify((rows || []).slice(0, HISTORY_MAX));
}

// the last answer `ans` stands for: the newest one qalc can read back
function lastAnswer(rows) {
  for (const r of rows || []) if (r.raw) return r.raw;
  return "";
}

// what the exchange-rate fetch runs: fetch if older than 12 h, then say how
// old the rates are in seconds (-1 for none at all)
function ratesScript() {
  return "d=\"${QALCULATE_USER_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/qalculate}\"\n"
    + "f=\"$d/eurofxref-daily.xml\"\n"
    + "[ -n \"$(find \"$f\" -mmin -720 2>/dev/null)\" ] || timeout 20 qalc --exrates >/dev/null 2>&1\n"
    + "if [ -f \"$f\" ]; then echo $(( $(date +%s) - $(stat -c %Y \"$f\") )); else echo -1; fi\n";
}

// ── how an answer looks ───────────────────────────────────────────────────
// The glyph in the field, for what the answer is a measure of: you see how
// the question was taken before you read a word of it.
const GLYPHS = {
  length: 0xF046D, area: 0xF0FE6, volume: 0xF01AB, speed: 0xF04C5, accel: 0xF04C5,
  temp: 0xF050F, mass: 0xF05A2, time: 0xF051B, data: 0xF01BC, rate: 0xF06F4,
  energy: 0xF140B, power: 0xF0241, force: 0xF089B, pressure: 0xF029A, freq: 0xF095B,
  pace: 0xF070E, fuel: 0xF0298, currency: 0xF0114, angle: 0xF0937, percent: 0xF03F0,
  date: 0xF0E17, clock: 0xF0150, tz: 0xF01E7, tzdiff: 0xF0D1E, cooking: 0xF0B7C,
  geo: 0xF08F0,
  calc: 0xF00EC
};

function knownKind(kind) {
  return Object.prototype.hasOwnProperty.call(GLYPHS, kind);
}

function glyphFor(kind) {
  return String.fromCodePoint(GLYPHS[kind] || GLYPHS.calc);
}

// what kind an answer is, from the question and what came back
function kindOf(prep, calc) {
  if (!prep) return "calc";
  if (prep.kind === "tz") return prep.mode === "diff" ? "tzdiff" : "tz";
  if (prep.kind === "geo") return "geo";
  if (prep.kind === "local") return prep.category || "date";
  if (prep.label) return "cooking";
  if (prep.pace) return "pace";
  if (calc && /%$/.test(calc.result || "")) return "percent";
  return (calc && calc.category && GLYPHS[calc.category]) ? calc.category : "calc";
}

function esc(s) {
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/ /g, "&nbsp;");
}

// The question as typed, tinted: numbers, units, the joining words and the
// operators each their own ink, and the word that could not be read in red.
// StyledText, not rich: it lays out exactly as the field under it does.
const JOINERS = /^(?:to|in|as|into|at|for|of|per|from|until|till|since|between|and|ago|by|after|before|vs)$/i;
function highlight(text, ink, bad) {
  const t = String(text || "");
  const font = (c, s) => '<font color="' + c + '">' + esc(s) + "</font>";
  // a word starts with a letter or a unit sign — not an apostrophe, or the
  // 11 of 5'11" was tinted as a unit
  const re = /([−-]?\d[\d,]*(?:[.:]\d+)*(?:e[−+-]?\d+)?)|([A-Za-z_°$€£¥µμ][\w°'²³]*)|([+\-*/×÷^%=()])|(\s+)|(.)/g;
  let out = "", m;
  while ((m = re.exec(t)) !== null) {
    if (m[1]) out += font(ink.num, m[1]);
    else if (m[2]) {
      const w = m[2];
      if (ink.bad && bad && w.toLowerCase() === String(bad).toLowerCase()) out += font(ink.bad, w);
      else out += font(JOINERS.test(w) ? ink.joiner : ink.word, w);
    } else if (m[3]) out += font(ink.op, m[3]);
    else if (m[4]) out += esc(m[4]);
    else out += font(ink.word, m[5]);
  }
  return out;
}

// where a word sits in the field: [start, end) of its first whole-word match
function wordSpan(text, word) {
  const w = String(word || "");
  if (!w) return null;
  const esc2 = w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const m = new RegExp("(^|[^\\w])(" + esc2 + ")(?![\\w])", "i").exec(String(text || ""));
  return m ? { start: m.index + m[1].length, end: m.index + m[1].length + w.length } : null;
}

// "21:00" → minutes after midnight
function hmMin(s) {
  const m = /(\d{1,2}):(\d{2})/.exec(String(s || ""));
  return m ? Number(m[1]) * 60 + Number(m[2]) : NaN;
}

// ── distances between places ──────────────────────────────────────────────
// Great-circle ("as the crow flies") from coordinates. The cities people
// usually mean are here; anything else is looked up by its time zone, whose
// main city zone1970.tab gives coordinates for (so "egypt" is Cairo).
const CITIES = {
  london: [51.507, -0.128], paris: [48.857, 2.352], berlin: [52.52, 13.405],
  madrid: [40.417, -3.704], rome: [41.903, 12.496], amsterdam: [52.368, 4.904],
  brussels: [50.85, 4.352], vienna: [48.208, 16.374], zurich: [47.377, 8.542],
  geneva: [46.204, 6.143], munich: [48.137, 11.576], frankfurt: [50.11, 8.682],
  hamburg: [53.551, 9.994], barcelona: [41.385, 2.173], milan: [45.464, 9.19],
  lisbon: [38.722, -9.139], dublin: [53.35, -6.26], edinburgh: [55.953, -3.189],
  manchester: [53.48, -2.242], prague: [50.075, 14.438], warsaw: [52.23, 21.012],
  budapest: [47.498, 19.04], copenhagen: [55.676, 12.568], oslo: [59.914, 10.752],
  stockholm: [59.329, 18.069], helsinki: [60.17, 24.938], athens: [37.984, 23.728],
  istanbul: [41.008, 28.978], ankara: [39.934, 32.86], moscow: [55.756, 37.617],
  "saint petersburg": [59.939, 30.316], "st petersburg": [59.939, 30.316],
  kyiv: [50.45, 30.524], kiev: [50.45, 30.524], bucharest: [44.426, 26.102],
  sofia: [42.698, 23.322], belgrade: [44.787, 20.457], zagreb: [45.815, 15.982],
  reykjavik: [64.147, -21.942], venice: [45.441, 12.316], florence: [43.77, 11.256],
  naples: [40.852, 14.268], nice: [43.71, 7.262], marseille: [43.296, 5.37], lyon: [45.764, 4.836],
  cairo: [30.044, 31.236], alexandria: [31.2, 29.918], giza: [30.013, 31.209],
  luxor: [25.687, 32.639], aswan: [24.089, 32.899], "sharm el sheikh": [27.916, 34.33],
  hurghada: [27.258, 33.812], casablanca: [33.573, -7.59], marrakesh: [31.63, -7.99],
  marrakech: [31.63, -7.99], tunis: [36.806, 10.181], algiers: [36.754, 3.059],
  tripoli: [32.887, 13.191], khartoum: [15.501, 32.56], "addis ababa": [9.03, 38.74],
  nairobi: [-1.286, 36.817], lagos: [6.524, 3.379], accra: [5.604, -0.187],
  dakar: [14.716, -17.467], kinshasa: [-4.441, 15.266], johannesburg: [-26.204, 28.047],
  "cape town": [-33.925, 18.424], durban: [-29.858, 31.022], "dar es salaam": [-6.792, 39.208],
  kampala: [0.347, 32.582],
  dubai: [25.205, 55.271], "abu dhabi": [24.454, 54.377], doha: [25.285, 51.531],
  riyadh: [24.713, 46.675], jeddah: [21.485, 39.193], mecca: [21.389, 39.858],
  medina: [24.524, 39.569], "kuwait city": [29.376, 47.977], manama: [26.228, 50.586],
  muscat: [23.588, 58.383], amman: [31.945, 35.928], beirut: [33.894, 35.502],
  damascus: [33.513, 36.276], baghdad: [33.315, 44.366], tehran: [35.689, 51.389],
  jerusalem: [31.768, 35.214], "tel aviv": [32.085, 34.781],
  karachi: [24.861, 67.01], lahore: [31.52, 74.359], islamabad: [33.684, 73.048],
  delhi: [28.704, 77.102], "new delhi": [28.614, 77.209], mumbai: [19.076, 72.878],
  bangalore: [12.972, 77.595], bengaluru: [12.972, 77.595], chennai: [13.083, 80.271],
  hyderabad: [17.385, 78.487], kolkata: [22.573, 88.364], dhaka: [23.81, 90.413],
  kathmandu: [27.717, 85.324], colombo: [6.927, 79.861], bangkok: [13.756, 100.502],
  hanoi: [21.028, 105.834], "ho chi minh": [10.823, 106.63], singapore: [1.352, 103.82],
  "kuala lumpur": [3.139, 101.687], jakarta: [-6.208, 106.846], bali: [-8.34, 115.092],
  manila: [14.6, 120.984], beijing: [39.904, 116.407], shanghai: [31.23, 121.474],
  shenzhen: [22.543, 114.058], guangzhou: [23.129, 113.264], "hong kong": [22.32, 114.169],
  taipei: [25.033, 121.565], seoul: [37.567, 126.978], busan: [35.18, 129.075],
  tokyo: [35.676, 139.65], osaka: [34.694, 135.502], kyoto: [35.012, 135.768],
  ulaanbaatar: [47.886, 106.906], almaty: [43.222, 76.851], tashkent: [41.299, 69.24],
  sydney: [-33.869, 151.209], melbourne: [-37.814, 144.963], brisbane: [-27.47, 153.026],
  perth: [-31.951, 115.861], adelaide: [-34.929, 138.601], auckland: [-36.848, 174.763],
  wellington: [-41.286, 174.776], honolulu: [21.307, -157.858],
  "new york": [40.713, -74.006], nyc: [40.713, -74.006], "new york city": [40.713, -74.006],
  boston: [42.36, -71.059], washington: [38.907, -77.037], dc: [38.907, -77.037],
  "washington dc": [38.907, -77.037], philadelphia: [39.953, -75.165], miami: [25.762, -80.192],
  atlanta: [33.749, -84.388], chicago: [41.878, -87.63], detroit: [42.331, -83.046],
  dallas: [32.777, -96.797], houston: [29.76, -95.37], austin: [30.267, -97.743],
  denver: [39.739, -104.99], phoenix: [33.448, -112.074], "las vegas": [36.17, -115.14],
  "los angeles": [34.052, -118.244], la: [34.052, -118.244], "san francisco": [37.775, -122.419],
  sf: [37.775, -122.419], "san diego": [32.716, -117.161], seattle: [47.606, -122.332],
  portland: [45.515, -122.679], "salt lake city": [40.761, -111.891], minneapolis: [44.978, -93.265],
  "new orleans": [29.951, -90.072], orlando: [28.538, -81.379], anchorage: [61.218, -149.9],
  toronto: [43.653, -79.383], montreal: [45.502, -73.567], vancouver: [49.283, -123.121],
  ottawa: [45.421, -75.697], calgary: [51.045, -114.072], "mexico city": [19.433, -99.133],
  cancun: [21.162, -86.851], havana: [23.114, -82.367],
  "sao paulo": [-23.551, -46.633], "são paulo": [-23.551, -46.633],
  "rio de janeiro": [-22.907, -43.173], rio: [-22.907, -43.173],
  "buenos aires": [-34.604, -58.382], santiago: [-33.449, -70.669], lima: [-12.046, -77.043],
  bogota: [4.711, -74.072], "bogotá": [4.711, -74.072], caracas: [10.481, -66.904],
  quito: [-0.181, -78.468], montevideo: [-34.901, -56.164]
};

function geoPrepare(s) {
  let m = /^(?:the\s+)?distance\s+(?:from\s+|between\s+)?(.+?)\s+(?:to|and|from)\s+(.+)$/i.exec(s)
    || /^how\s+far\s+(?:away\s+)?(?:is\s+(?:it\s+)?)?(?:from\s+)?(.+?)\s+(?:from|to)\s+(.+?)(?:\s+away)?$/i.exec(s)
    || /^(.+?)\s+(?:to|-|–)\s+(.+?)\s+distance$/i.exec(s);
  if (!m) return null;
  const a = m[1].trim(), b = m[2].trim();
  // places, not "5 km to miles": each must be a known city or zone-ish words
  const ok = (w) => Object.prototype.hasOwnProperty.call(CITIES, placeKey(w)) || isZoneish(w);
  if (!ok(a) || !ok(b) || /\d/.test(a + b)) return null;
  const end = (w) => {
    const c = CITIES[placeKey(w)];
    return { word: w, label: placeLabel(w), coord: c ? c[0] + "," + c[1] : "",
      place: placeQuery(w), zone: zoneArg(w) };
  };
  return { kind: "geo", a: end(a), b: end(b), label: placeLabel(a) + " → " + placeLabel(b) + "  · straight line" };
}

// For each end: its "lat,lon" from CITIES or "", its words for the index,
// and its zone. Prints  coordA | coordB | offsetA | offsetB | viaA | viaB —
// `via` is the city a province, a state or a country was measured at ("" for
// a city) — or "?place" for one not found.
function geoScript() {
  return ZONE_SH
    // where a place is: "lat,lon|via|zone"
    + "where() {\n"
    + "  if [ -n \"$1\" ]; then printf '%s||%s\\n' \"$1\" \"$(zone \"$3\" 2>/dev/null)\"; return 0; fi\n"
    + "  if r=$(place \"$2\"); then\n"
    + "    printf '%s\\n' \"$r\" | awk -F'\\t' '{ print $7 \",\" $8 \"|\" ($2 == \"c\" ? \"\" : $11) \"|\" $9 }'\n"
    + "    return 0\n"
    + "  fi\n"
    // no index, or not in it: its zone's main city, from zone1970.tab
    + "  z=$(zone \"$3\") && [ -n \"$z\" ] || return 1\n"
    + "  c=$(awk -F'\\t' -v z=\"$z\" '!/^#/ && $3==z {print $2; exit}' \"$Z/zone1970.tab\" \"$Z/zone.tab\")\n"
    + "  [ -n \"$c\" ] || return 1\n"
    + "  v=${z##*/}; printf '%s|%s|%s\\n' \"$c\" \"$(printf '%s' \"$v\" | tr '_' ' ')\" \"$z\"\n"
    + "}\n"
    + "a=$(where \"$1\" \"$2\" \"$3\") || { printf '?%s\\n' \"$2\"; exit 0; }\n"
    + "b=$(where \"$4\" \"$5\" \"$6\") || { printf '?%s\\n' \"$5\"; exit 0; }\n"
    + "off() { [ -n \"$1\" ] && TZ=$1 date +%z; }\n"
    + "printf '%s|%s|%s|%s|%s|%s\\n' \"${a%%|*}\" \"${b%%|*}\" \"$(off \"${a##*|}\")\" \"$(off \"${b##*|}\")\""
    + " \"$(printf '%s' \"$a\" | cut -d'|' -f2)\" \"$(printf '%s' \"$b\" | cut -d'|' -f2)\"\n";
}

// "51.507,-0.128" or ISO 6709 "+3003+03115" / "+404251-0740023" → [lat, lon]
function parseCoord(s) {
  const t = String(s || "").trim();
  let m = /^(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)$/.exec(t);
  if (m) return [Number(m[1]), Number(m[2])];
  m = /^([+-])(\d{2})(\d{2})(\d{2})?([+-])(\d{3})(\d{2})(\d{2})?$/.exec(t);
  if (!m) return null;
  const dms = (sg, d, mi, se) => (sg === "-" ? -1 : 1) * (Number(d) + Number(mi) / 60 + Number(se || 0) / 3600);
  return [dms(m[1], m[2], m[3], m[4]), dms(m[5], m[6], m[7], m[8])];
}

function haversineKm(a, b) {
  const R = 6371.0088, rad = Math.PI / 180;
  const dLat = (b[0] - a[0]) * rad, dLon = (b[1] - a[1]) * rad;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a[0] * rad) * Math.cos(b[0] * rad) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
}

// the way you would set off from a, as a compass word
function bearingWord(a, b) {
  const rad = Math.PI / 180;
  const y = Math.sin((b[1] - a[1]) * rad) * Math.cos(b[0] * rad);
  const x = Math.cos(a[0] * rad) * Math.sin(b[0] * rad)
    - Math.sin(a[0] * rad) * Math.cos(b[0] * rad) * Math.cos((b[1] - a[1]) * rad);
  const deg = (Math.atan2(y, x) / rad + 360) % 360;
  return ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"][Math.round(deg / 45) % 8];
}

function readGeo(text, prep) {
  const out = stripAnsi(text).trim().split("\n")[0] || "";
  if (!out) return {};
  if (out[0] === "?") return { bad: true, word: out.slice(1).replace(/_/g, " ") };
  const f = out.split("|");
  const a = parseCoord(f[0]), b = parseCoord(f[1]);
  if (!a || !b) return { bad: true, word: "" };
  const km = haversineKm(a, b);
  const shown = km >= 100 ? Math.round(km) : Math.round(km * 10) / 10;
  const mi = km / 1.609344;
  const chips = [(mi >= 100 ? Math.round(mi) : Math.round(mi * 10) / 10) + " mi"];
  // a jet's ~800 km/h, and half an hour for climbing and landing
  if (km > 300) chips.push("≈ " + duration(Math.round((km / 800 + 0.5) * 3600 / 300) * 300) + " flight");
  chips.push("heading " + bearingWord(a, b));
  const oa = offMin(f[2]), ob = offMin(f[3]);
  if (isFinite(oa) && isFinite(ob) && oa !== ob)
    chips.push(prep.b.label + " " + offText(Math.abs(ob - oa)) + (ob > oa ? " ahead" : " behind"));
  // A province, a state or a country is measured at a city — its biggest,
  // its capital, or its time zone's — and says which, so "Texas" is not
  // quietly Houston.
  const at = [];
  for (const [end, via] of [[prep.a, f[4]], [prep.b, f[5]]])
    if (via && via.toLowerCase() !== placeKey(end.word)) at.push(end.label + " at " + via);
  const parse = at.length ? placeLabel(prep.a.word) + " → " + placeLabel(prep.b.word)
    + "  · measured " + at.join(", ") : prep.label;
  return { result: shown + " km", raw: shown + " km", parse: parse, base: "", expr: "", input: "",
    chips: chips, category: "geo" };
}

// ── the answer, a character at a time ─────────────────────────────────────
// For the rolling digits: each character, and whether it is part of a
// number (large), a unit (small) or a time zone's date after " · " (quiet).
// Not split: a hex or binary number, or an answer with no number in it.
function answerChars(text) {
  const t = String(text || "");
  const cut = t.indexOf(" · ");
  const head = cut >= 0 ? t.slice(0, cut) : t;
  const tail = cut >= 0 ? t.slice(cut) : "";
  const out = [];
  const push = (s, big, quiet) => { for (const c of s) out.push({ c: c, big: big, quiet: !!quiet }); };
  if (/^0[xbo]|^[01]{4}(?: [01]{4})+$/i.test(head) || !/\d/.test(head)) {
    push(head, true);
  } else {
    const re = /[−-]?\d[\d,]*(?:[.:]\d+)*(?:E[−+-]?\d+)?/g;
    let at = 0, m;
    while ((m = re.exec(head)) !== null) {
      if (m.index > at) push(head.slice(at, m.index), false);
      push(m[0], true);
      at = m.index + m[0].length;
    }
    if (at < head.length) push(head.slice(at), false);
  }
  push(tail, false, true);
  return out;
}

// ── the reading line ──────────────────────────────────────────────────────
// Shown only when it says something: "5 km" read back as "5 kilometers" is
// noise, "5 km in miles" as "5 kilometers → miles" is the point.
function parseWorth(prep, parse, input) {
  if (!parse) return false;
  if (!prep || prep.kind !== "qalc") return true;
  if (prep.label || prep.pace || prep.round) return true;
  if (prep.auto) return false;
  const flat = (x) => String(x || "").toLowerCase().replace(/[\s()]/g, "").replace(/[×*]/g, "*");
  return flat(parse) !== flat(input);
}

// "5 kilometers → miles  · rates 3 days old": the source muted, the arrow
// in blue, where it went in white, a warning after "·" in yellow
function parseHtml(parse, ink) {
  const t = String(parse || "");
  const dot = t.indexOf("  · ");
  const main = dot >= 0 ? t.slice(0, dot) : t;
  const note = dot >= 0 ? t.slice(dot + 4) : "";
  const font = (c, s) => '<font color="' + c + '">' + esc(s) + "</font>";
  const arrow = main.lastIndexOf(" → ");
  let out = arrow >= 0
    ? font(ink.muted, main.slice(0, arrow)) + font(ink.arrow, " → ") + font(ink.target, main.slice(arrow + 3))
    : font(ink.muted, main);
  if (note) out += font(ink.muted, "  · ") + font(/old|no exchange/.test(note) ? ink.warn : ink.muted, note);
  return out;
}

// ── what "* 2" goes on from ───────────────────────────────────────────────
function continues(input, ans) {
  return !!ans && /^\s*(?:[+*/×÷^]|-\s|(?:to|in|as|into)\s)/i.test(String(input || ""));
}

// ── very large and very small numbers, in words ───────────────────────────
const SCALES = [[1e18, "quintillion"], [1e15, "quadrillion"], [1e12, "trillion"],
  [1e9, "billion"], [1e6, "million"]];
const SMALL_SCALES = [[1e-6, "millionths"], [1e-9, "billionths"]];
function wordScale(result) {
  const t = String(result || "");
  if (/^0x|^"/.test(t)) return "";
  const m = NUM_RE.exec(t);
  if (!m) return "";
  const n = parseFloat(m[0].replace(/−/g, "-").replace(/,/g, ""));
  const a = Math.abs(n);
  const unit = t.slice(m.index + m[0].length).trim();
  const say = (v, w) => "≈ " + (n < 0 ? "−" : "") + String(Number(v.toPrecision(3))) + " " + w
    + (unit ? " " + unit : "");
  for (const [v, w] of SCALES) if (a >= v) return a < v * 1000 || v === 1e18 ? say(a / v, w) : "";
  if (a > 0 && a < 1e-4)
    for (const [v, w] of SMALL_SCALES) if (a >= v) return say(a / v, w);
  return "";
}

// ── a wash behind the answer ──────────────────────────────────────────────
// Felt more than seen. A temperature is warm or cool by its value; the rest
// by what they measure. "" for none.
function tintFor(kind, base) {
  if (kind === "temp") {
    const c = numOf(base) - 273.15;
    if (!isFinite(c)) return "";
    return c < 0 ? "cyan" : c < 15 ? "blue" : c < 26 ? "green" : c < 35 ? "yellow" : "red";
  }
  return ({ currency: "green", time: "magenta", date: "magenta", clock: "magenta",
    tz: "magenta", tzdiff: "magenta", pace: "magenta", length: "blue", area: "blue",
    volume: "blue", geo: "blue", speed: "cyan", data: "cyan", rate: "cyan",
    mass: "sand", force: "sand", cooking: "sand", energy: "yellow", power: "yellow",
    percent: "green" })[kind] || "";
}

// ── the sky at a place ────────────────────────────────────────────────────
// day 07–18, a low sun either side of it (05–07, 18–20), night the rest
function skyAt(min) {
  if (!isFinite(min) || min < 0) return "";
  if (min >= 7 * 60 && min < 18 * 60) return "day";
  if (min >= 5 * 60 && min < 20 * 60) return "low";
  return "night";
}
function skyGlyph(min) {
  const k = skyAt(min);
  return k === "" ? "" : String.fromCodePoint(({ day: 0xF0599, low: 0xF059A, night: 0xF0594 })[k]);
}
// its colour, a Zenon name
function skyInk(min) {
  return ({ day: "sand", low: "yellow", night: "keyInk" })[skyAt(min)] || "keyInk";
}

// ── finishing the word being typed ────────────────────────────────────────
// The rest of the last word, when it is the start of one name and not a
// whole one already: "kilom" → "eters". Everyday names first, then places,
// then everything qalc knows.
function complete(text, names) {
  const m = /([A-Za-z][A-Za-z ]*)$/.exec(String(text || ""));
  if (!m) return "";
  // a place may be two words ("new yo"); a unit is one
  const tries = [m[1].replace(/^.*\s/, "")];
  if (/\s/.test(m[1])) tries.push(m[1].split(" ").slice(-2).join(" "));
  const places = Object.keys(PLACES).concat(Object.keys(CITIES));
  for (const w of tries.reverse()) {
    if (w.length < 3) continue;
    const lw = w.toLowerCase();
    // the index last: thirty thousand towns would finish "eur" before euro
    const tiers = [COMMON, places, names || [], INDEX.main[lw.slice(0, 3)] || []];
    if (tiers.some((t) => t.some((c) => c.toLowerCase() === lw))) continue;
    // the shortest match in the first list that has one: "mil" is miles,
    // not millimeters
    for (const tier of tiers) {
      let best = "";
      for (const c of tier)
        if (c.length > w.length && c.toLowerCase().indexOf(lw) === 0 && !/_/.test(c)
            && (best === "" || c.length < best.length)) best = c;
      if (best) return best.slice(w.length);
    }
  }
  return "";
}

// ── for a first open, with nothing kept yet ───────────────────────────────
const EXAMPLES = ["5 km in miles", "days until christmas", "3pm tokyo to london",
  "distance from cairo to london"];

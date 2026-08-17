.pragma library

// One place that decides what a chain number means.
//
// UNITS — the chain's raw u64 IS LGO. There is no sub-unit.
//   core/src/mantle/transactions/gas.rs cites the spec
//   (lip.logos.co/blockchain/raw/storage-markets.html) as "P_STR(0) = 1 LGO/gas"
//   and implements it as GasPrice::new(1) — a 1:1 mapping.
// This module used to divide by an invented `baseUnitsPerLgo = 10000`, so every
// balance read 10,000x too small. Nothing upstream does that: the official
// logos-blockchain-ui renders the raw string and hackyguru/persona formats the
// raw value with no division; `baseUnitsPerLgo` had zero hits across GitHub.
//
// A shared library rather than a QML component because callers need the string
// inside a sentence, not a visual item. Five views each doing their own unit
// maths is how the wrong one survived.

var TICKER = "LGO";

function _valid(raw) {
    return raw !== undefined && raw !== null && String(raw).length > 0
           && !isNaN(Number(raw));
}
function _trim(x) { return String(Math.round(x * 100) / 100); }
function _grouped(n) { return Number(n).toLocaleString(Qt.locale(), 'f', 0); }

// Exact, with thousands separators. No ticker.
function plain(raw) { return _valid(raw) ? _grouped(Number(raw)) : "—"; }

// Exact, with ticker — for tooltips and anywhere space allows.
function exact(raw) { return _valid(raw) ? _grouped(Number(raw)) + " " + TICKER : "—"; }

// Abbreviated with ticker, for narrow fields. Below 1e6 the value is shown in
// full so rewards and fees (~9,517 / ~4,173) stay readable rather than becoming
// "9.52K"; only a node balance is ever large enough to need shortening.
function short(raw) {
    if (!_valid(raw)) return "— " + TICKER;
    var n = Number(raw), a = Math.abs(n);
    if (a < 1e6)   return _grouped(n) + " " + TICKER;
    if (a >= 1e12) return _trim(n / 1e12) + "T " + TICKER;
    if (a >= 1e9)  return _trim(n / 1e9)  + "B " + TICKER;
    return _trim(n / 1e6) + "M " + TICKER;
}

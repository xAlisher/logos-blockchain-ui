.pragma library

// One place that decides what a chain number means.
//
// UNITS — the chain's raw u64 is LEPTA (base units). 1 LGO = 10^9 lepta,
// decimals = 9. Settled by the "Logos Token: Units and Precision" spec (§0.1);
// master genesis confirms it in code — a stakeholder stake of 100000000000000
// lepta = 100,000 LGO against the 10^10 supply, which only makes sense in lepta.
// The node/module report values as raw u64 lepta (logos_blockchain_module.h:109
// "value": "<u64>"), so convert to LGO for display by dividing by LEPTA_PER_LGO.
//
// NOTE: this SUPERSEDES the earlier "raw u64 IS LGO" reading (pre-lepton, cited
// gas.rs P_STR(0)=1 LGO/gas). The denomination moved to decimals=9 afterwards.
// Reference implementation for the real UI — keep the division in ONE place.

var TICKER = "LGO";
var LEPTA_PER_LGO = 1e9;          // decimals = 9

function _valid(raw) {
    return raw !== undefined && raw !== null && String(raw).length > 0
           && !isNaN(Number(raw));
}
function _lgo(rawLepta) { return Number(rawLepta) / LEPTA_PER_LGO; }
function _trim(x) { return String(Math.round(x * 100) / 100); }
function _grouped(n) { return Number(n).toLocaleString(Qt.locale(), 'f', 0); }

// Exact LGO, thousands-separated, no ticker.
function plain(rawLepta) { return _valid(rawLepta) ? _grouped(_lgo(rawLepta)) : "—"; }

// Exact LGO with ticker — tooltips / wide fields.
function exact(rawLepta) { return _valid(rawLepta) ? _grouped(_lgo(rawLepta)) + " " + TICKER : "—"; }

// FULL lepta precision (up to 9 decimals, trailing zeros trimmed), string math on
// the raw u64 → no float loss: 5000000234000 lepta → "5,000.000234". preciseNum has
// no ticker (for "+a − b = c LGO" rows); precise appends the ticker.
function _preciseStr(rawLepta) {
    var raw = String(rawLepta).trim();
    var neg = raw.charAt(0) === '-';
    var digits = (raw.replace(/[^0-9]/g, "").replace(/^0+/, "")) || "0";
    while (digits.length < 10) digits = "0" + digits;         // >= 1 integer digit + 9 fractional
    var intPart = digits.slice(0, digits.length - 9);
    var frac = digits.slice(digits.length - 9).replace(/0+$/, "");   // trim trailing zeros
    var intGrouped = Number(intPart).toLocaleString(Qt.locale(), 'f', 0);
    return (neg ? "-" : "") + intGrouped + (frac.length ? "." + frac : "");
}
function preciseNum(rawLepta) { return _valid(rawLepta) ? _preciseStr(rawLepta) : "—"; }
function precise(rawLepta) { return _valid(rawLepta) ? _preciseStr(rawLepta) + " " + TICKER : "—"; }

// Abbreviated LGO with ticker, for narrow tiles. Below 1e6 LGO shown in full so
// rewards/fees stay readable; only a large stake needs K/M/B/T shortening.
function short(rawLepta) {
    if (!_valid(rawLepta)) return "— " + TICKER;
    var n = _lgo(rawLepta), a = Math.abs(n);
    if (a < 1e6)   return _grouped(n) + " " + TICKER;
    if (a >= 1e12) return _trim(n / 1e12) + "T " + TICKER;
    if (a >= 1e9)  return _trim(n / 1e9)  + "B " + TICKER;
    return _trim(n / 1e6) + "M " + TICKER;
}

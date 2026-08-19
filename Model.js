// Pure presentation helpers for Stock Ticker.
//
// Loaded by Panel.qml (import "Model.js" as Model) AND by node --test, and the
// two engines do not accept the same syntax. So: no I/O, no QML imports, no
// timers, no state between calls, and everything at top level is `var` or
// `function` declarations. Do NOT use: arrow functions, template literals,
// spread, let/const, Object.assign, .includes(), .endsWith().

var TIMEFRAMES = ["1D", "1W", "1M", "6M", "1Y", "5Y"]

function timeframeParams(tf) {
  switch (tf) {
  case "1D": return { interval: "5m", range: "1d" }
  case "1W": return { interval: "30m", range: "5d" }
  case "1M": return { interval: "1h", range: "1mo" }
  case "6M": return { interval: "1d", range: "6mo" }
  case "1Y": return { interval: "1d", range: "1y" }
  case "5Y": return { interval: "1wk", range: "5y" }
  default:   return { interval: "1d", range: "1y" }
  }
}

function chartUrl(ticker, tf) {
  var p = timeframeParams(tf)
  var sym = String(ticker || "").toUpperCase()
  return ["curl", "-fsS", "--max-time", "8",
          "-H", "User-Agent: Mozilla/5.0",
          "https://query1.finance.yahoo.com/v8/finance/chart/" +
          encodeURIComponent(sym) +
          "?interval=" + p.interval + "&range=" + p.range]
}

function quoteUrl(ticker) {
  var sym = String(ticker || "").toUpperCase()
  return ["curl", "-fsS", "--max-time", "8",
          "-H", "User-Agent: Mozilla/5.0",
          "https://query1.finance.yahoo.com/v8/finance/chart/" +
          encodeURIComponent(sym) +
          "?interval=5m&range=1d&includePrePost=true"]
}

function parseChart(raw) {
  try {
    var obj = JSON.parse(raw)
    var result = obj.chart && obj.chart.result && obj.chart.result[0]
    if (!result) return []
    var ts = result.timestamp
    var closes = result.indicators && result.indicators.quote &&
                 result.indicators.quote[0] && result.indicators.quote[0].close
    if (!ts || !closes) return []
    var out = []
    for (var i = 0; i < ts.length; i++) {
      if (closes[i] !== null && closes[i] !== undefined)
        out.push({ t: ts[i], p: closes[i] })
    }
    return out
  } catch (e) {
    return []
  }
}

function parseQuote(raw) {
  try {
    var obj = JSON.parse(raw)
    var result = obj.chart && obj.chart.result && obj.chart.result[0]
    var meta = result && result.meta
    if (!meta) return null
    var pre = null, post = null
    var ts = result.timestamp
    var closes = result.indicators && result.indicators.quote &&
                 result.indicators.quote[0] && result.indicators.quote[0].close
    var reg = meta.currentTradingPeriod && meta.currentTradingPeriod.regular
    if (ts && closes && reg) {
      var preV = null, postV = null
      for (var i = 0; i < ts.length; i++) {
        if (closes[i] === null || closes[i] === undefined) continue
        if (ts[i] < reg.start) preV = closes[i]
        else if (ts[i] >= reg.end) postV = closes[i]
      }
      pre = preV
      post = postV
    }
    return {
      price: meta.regularMarketPrice,
      previousClose: meta.chartPreviousClose || meta.previousClose,
      currency: meta.currency || "USD",
      companyName: meta.longName || meta.shortName || null,
      dayHigh: meta.regularMarketDayHigh,
      dayLow: meta.regularMarketDayLow,
      weekHigh52: meta.fiftyTwoWeekHigh,
      weekLow52: meta.fiftyTwoWeekLow,
      volume: meta.regularMarketVolume,
      preMarketPrice: pre,
      postMarketPrice: post
    }
  } catch (e) {
    return null
  }
}

function fmtPrice(v) {
  if (v === null || v === undefined) return "N/A"
  if (v > 0 && v < 1) return v.toFixed(4)
  return v.toFixed(2)
}

function fmtChange(v) {
  if (v === null || v === undefined) return "N/A"
  var s = v >= 0 ? "+" : ""
  return s + v.toFixed(2)
}

function fmtPct(v) {
  if (v === null || v === undefined) return "N/A"
  var s = v >= 0 ? "+" : ""
  return s + v.toFixed(2) + "%"
}

var CURRENCY_SYMBOLS = { USD: "$", GBP: "\u00a3", EUR: "\u20ac", JPY: "\u00a5" }

function fmtPriceWithCurrency(v, currency) {
  var sym = CURRENCY_SYMBOLS[currency] || (currency ? currency + " " : "")
  return sym + fmtPrice(v)
}

function fmtVolume(v) {
  if (v === null || v === undefined) return "N/A"
  var abs = Math.abs(v)
  var base, suffix
  if (abs >= 1000000000) { base = v / 1000000000; suffix = "B" }
  else if (abs >= 1000000) { base = v / 1000000; suffix = "M" }
  else if (abs >= 1000) { base = v / 1000; suffix = "K" }
  else return String(Math.round(v))
  var s = base.toFixed(1)
  if (s.slice(-2) === ".0") s = s.slice(0, -2)
  return s + suffix
}

// NYSE trading window, 9:30–16:00 ET, Mon–Fri. ET is derived from UTC plus a
// fixed offset in minutes; a constant offset is an accepted simplification
// (the answer is off by an hour around DST transitions). Holidays ignored.
function isMarketOpen(nowMs, tzOffsetMinutes) {
  var d = new Date(nowMs)
  var etMinutes = d.getUTCHours() * 60 + d.getUTCMinutes() + (tzOffsetMinutes || 0)
  var day = d.getUTCDay()
  if (etMinutes < 0) { etMinutes += 1440; day = (day + 6) % 7 }
  else if (etMinutes >= 1440) { etMinutes -= 1440; day = (day + 1) % 7 }
  if (day === 0 || day === 6) return false
  return etMinutes >= 570 && etMinutes < 960
}

function changeColor(change, dim) {
  if (change === null || change === undefined) return dim
  if (change > 0) return "#22c55e"
  if (change < 0) return "#ef4444"
  return dim
}

var MONTHS = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]

function padZero(n) {
  return n < 10 ? "0" + n : "" + n
}

function fmtJsDate(d, fmt) {
  if (fmt === "HH:mm") return padZero(d.getHours()) + ":" + padZero(d.getMinutes())
  if (fmt === "MMM d") return MONTHS[d.getMonth()] + " " + d.getDate()
  if (fmt === "MMM yy") return MONTHS[d.getMonth()] + " " + String(d.getFullYear()).slice(2)
  return String(d)
}

function timeLabel(t, tf, fmtDt) {
  var d = new Date(t * 1000)
  if (tf === "1D")
    return fmtDt ? fmtDt(d, "HH:mm") : fmtJsDate(d, "HH:mm")
  if (tf === "1W" || tf === "1M" || tf === "6M")
    return fmtDt ? fmtDt(d, "MMM d") : fmtJsDate(d, "MMM d")
  return fmtDt ? fmtDt(d, "MMM yy") : fmtJsDate(d, "MMM yy")
}

function barLabel(ticker, price) {
  var sym = String(ticker || "").toUpperCase()
  if (price === null || price === undefined)
    return sym + ": ..."
  return sym + ": " + fmtPrice(price)
}

// Node.js exports for testing.
if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    TIMEFRAMES: TIMEFRAMES,
    timeframeParams: timeframeParams,
    chartUrl: chartUrl,
    quoteUrl: quoteUrl,
    parseChart: parseChart,
    parseQuote: parseQuote,
    fmtPrice: fmtPrice,
    fmtChange: fmtChange,
    fmtPct: fmtPct,
    changeColor: changeColor,
    fmtPriceWithCurrency: fmtPriceWithCurrency,
    fmtVolume: fmtVolume,
    isMarketOpen: isMarketOpen,
    CURRENCY_SYMBOLS: CURRENCY_SYMBOLS,
    timeLabel: timeLabel,
    barLabel: barLabel,
    fmtJsDate: fmtJsDate,
    padZero: padZero
  }
}

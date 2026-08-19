const test = require("node:test")
const assert = require("node:assert/strict")

const M = require("../Model.js")

// ── fmtPrice ──

test("fmtPrice formats normal stock price", function() {
  assert.equal(M.fmtPrice(305.54), "305.54")
})

test("fmtPrice formats price under $1 with 4 decimals", function() {
  assert.equal(M.fmtPrice(0.0053), "0.0053")
})

test("fmtPrice formats price exactly 1", function() {
  assert.equal(M.fmtPrice(1.0), "1.00")
})

test("fmtPrice formats large price", function() {
  assert.equal(M.fmtPrice(1823.45), "1823.45")
})

test("fmtPrice returns N/A for null", function() {
  assert.equal(M.fmtPrice(null), "N/A")
})

test("fmtPrice returns N/A for undefined", function() {
  assert.equal(M.fmtPrice(undefined), "N/A")
})

test("fmtPrice handles zero", function() {
  assert.equal(M.fmtPrice(0), "0.00")
})

test("fmtPrice handles negative", function() {
  assert.equal(M.fmtPrice(-5.32), "-5.32")
})

// ── fmtChange ──

test("fmtChange formats positive with plus sign", function() {
  assert.equal(M.fmtChange(2.34), "+2.34")
})

test("fmtChange formats negative", function() {
  assert.equal(M.fmtChange(-1.23), "-1.23")
})

test("fmtChange formats zero with plus sign", function() {
  assert.equal(M.fmtChange(0), "+0.00")
})

test("fmtChange returns N/A for null", function() {
  assert.equal(M.fmtChange(null), "N/A")
})

// ── fmtPct ──

test("fmtPct formats positive with plus sign and percent", function() {
  assert.equal(M.fmtPct(5.23), "+5.23%")
})

test("fmtPct formats negative", function() {
  assert.equal(M.fmtPct(-0.45), "-0.45%")
})

test("fmtPct formats zero with plus sign", function() {
  assert.equal(M.fmtPct(0), "+0.00%")
})

test("fmtPct returns N/A for null", function() {
  assert.equal(M.fmtPct(null), "N/A")
})

// ── fmtPriceWithCurrency ──

test("fmtPriceWithCurrency prefixes dollar sign for USD", function() {
  assert.equal(M.fmtPriceWithCurrency(305.54, "USD"), "$305.54")
})

test("fmtPriceWithCurrency uses pound for GBP", function() {
  assert.equal(M.fmtPriceWithCurrency(305.54, "GBP"), "\u00a3305.54")
})

test("fmtPriceWithCurrency uses euro for EUR", function() {
  assert.equal(M.fmtPriceWithCurrency(305.54, "EUR"), "\u20ac305.54")
})

test("fmtPriceWithCurrency uses yen for JPY", function() {
  assert.equal(M.fmtPriceWithCurrency(305.54, "JPY"), "\u00a5305.54")
})

test("fmtPriceWithCurrency falls back to code prefix for unknown currency", function() {
  assert.equal(M.fmtPriceWithCurrency(305.54, "CHF"), "CHF 305.54")
})

test("fmtPriceWithCurrency omits prefix when currency is null", function() {
  assert.equal(M.fmtPriceWithCurrency(305.54, null), "305.54")
})

// ── fmtVolume ──

test("fmtVolume returns plain number under 1000", function() {
  assert.equal(M.fmtVolume(500), "500")
})

test("fmtVolume abbreviates thousands", function() {
  assert.equal(M.fmtVolume(340000), "340K")
})

test("fmtVolume abbreviates millions", function() {
  assert.equal(M.fmtVolume(1200000), "1.2M")
})

test("fmtVolume abbreviates billions", function() {
  assert.equal(M.fmtVolume(2500000000), "2.5B")
})

test("fmtVolume strips trailing .0", function() {
  assert.equal(M.fmtVolume(2000000000), "2B")
})

test("fmtVolume returns N/A for null", function() {
  assert.equal(M.fmtVolume(null), "N/A")
})

// ── changeColor ──

test("changeColor returns green for positive", function() {
  assert.equal(M.changeColor(1.5, "#888"), "#22c55e")
})

test("changeColor returns red for negative", function() {
  assert.equal(M.changeColor(-0.3, "#888"), "#ef4444")
})

test("changeColor returns dim for zero", function() {
  assert.equal(M.changeColor(0, "#888"), "#888")
})

test("changeColor returns dim for null", function() {
  assert.equal(M.changeColor(null, "#888"), "#888")
})

// ── isMarketOpen ──
// All fixtures use a fixed -300 (EST) offset. 2026-08-17 is a Monday,
// 2026-08-18 a Tuesday, 2026-08-16 a Sunday.

test("isMarketOpen true at 09:30 ET open", function() {
  var ms = Date.UTC(2026, 7, 18, 14, 30) // 09:30 ET Tuesday
  assert.equal(M.isMarketOpen(ms, -300), true)
})

test("isMarketOpen true mid-session", function() {
  var ms = Date.UTC(2026, 7, 18, 17, 0) // 12:00 ET Tuesday
  assert.equal(M.isMarketOpen(ms, -300), true)
})

test("isMarketOpen false before open", function() {
  var ms = Date.UTC(2026, 7, 18, 14, 0) // 09:00 ET Tuesday
  assert.equal(M.isMarketOpen(ms, -300), false)
})

test("isMarketOpen false at 16:00 ET close", function() {
  var ms = Date.UTC(2026, 7, 18, 21, 0) // 16:00 ET Tuesday
  assert.equal(M.isMarketOpen(ms, -300), false)
})

test("isMarketOpen false on weekend", function() {
  var ms = Date.UTC(2026, 7, 16, 17, 0) // 12:00 ET Sunday
  assert.equal(M.isMarketOpen(ms, -300), false)
})

test("isMarketOpen true on Monday inside window", function() {
  var ms = Date.UTC(2026, 7, 17, 15, 0) // 10:00 ET Monday
  assert.equal(M.isMarketOpen(ms, -300), true)
})

test("isMarketOpen handles backward wrap past midnight", function() {
  var ms = Date.UTC(2026, 7, 18, 4, 0) // 23:00 ET Monday
  assert.equal(M.isMarketOpen(ms, -300), false)
})

// ── timeframeParams ──

test("timeframeParams returns correct interval/range for 1D", function() {
  var p = M.timeframeParams("1D")
  assert.equal(p.interval, "5m")
  assert.equal(p.range, "1d")
})

test("timeframeParams returns correct for 1W", function() {
  var p = M.timeframeParams("1W")
  assert.equal(p.interval, "30m")
  assert.equal(p.range, "5d")
})

test("timeframeParams returns correct for 1M", function() {
  var p = M.timeframeParams("1M")
  assert.equal(p.interval, "1h")
  assert.equal(p.range, "1mo")
})

test("timeframeParams returns correct for 6M", function() {
  var p = M.timeframeParams("6M")
  assert.equal(p.interval, "1d")
  assert.equal(p.range, "6mo")
})

test("timeframeParams returns correct for 1Y", function() {
  var p = M.timeframeParams("1Y")
  assert.equal(p.interval, "1d")
  assert.equal(p.range, "1y")
})

test("timeframeParams returns correct for 5Y", function() {
  var p = M.timeframeParams("5Y")
  assert.equal(p.interval, "1wk")
  assert.equal(p.range, "5y")
})

test("timeframeParams defaults to 1Y for unknown", function() {
  var p = M.timeframeParams("XYZ")
  assert.equal(p.interval, "1d")
  assert.equal(p.range, "1y")
})

// ── chartUrl ──

test("chartUrl returns array starting with curl", function() {
  var url = M.chartUrl("AAPL", "1D")
  assert.ok(Array.isArray(url))
  assert.equal(url[0], "curl")
})

test("chartUrl includes ticker in URL", function() {
  var url = M.chartUrl("MSFT", "1D")
  var fullUrl = url[url.length - 1]
  assert.ok(fullUrl.indexOf("MSFT") !== -1)
})

test("chartUrl includes User-Agent header", function() {
  var url = M.chartUrl("AAPL", "1D")
  assert.ok(url.indexOf("-H") !== -1)
  assert.ok(url.indexOf("User-Agent: Mozilla/5.0") !== -1)
})

test("chartUrl includes interval and range params", function() {
  var url = M.chartUrl("AAPL", "1W")
  var fullUrl = url[url.length - 1]
  assert.ok(fullUrl.indexOf("interval=30m") !== -1)
  assert.ok(fullUrl.indexOf("range=5d") !== -1)
})

// ── quoteUrl ──

test("quoteUrl returns array starting with curl", function() {
  var url = M.quoteUrl("AAPL")
  assert.ok(Array.isArray(url))
  assert.equal(url[0], "curl")
})

test("quoteUrl includes ticker", function() {
  var url = M.quoteUrl("GOOGL")
  var fullUrl = url[url.length - 1]
  assert.ok(fullUrl.indexOf("GOOGL") !== -1)
})

test("quoteUrl includes User-Agent header", function() {
  var url = M.quoteUrl("AAPL")
  assert.ok(url.indexOf("User-Agent: Mozilla/5.0") !== -1)
})

// ── parseQuote ──

test("parseQuote extracts price and previousClose", function() {
  var raw = JSON.stringify({
    chart: { result: [{ meta: {
      regularMarketPrice: 305.54,
      chartPreviousClose: 303.21,
      currency: "USD"
    }}] }
  })
  var q = M.parseQuote(raw)
  assert.equal(q.price, 305.54)
  assert.equal(q.previousClose, 303.21)
  assert.equal(q.currency, "USD")
})

test("parseQuote falls back to previousClose", function() {
  var raw = JSON.stringify({
    chart: { result: [{ meta: {
      regularMarketPrice: 100,
      previousClose: 99,
      currency: "USD"
    }}] }
  })
  var q = M.parseQuote(raw)
  assert.equal(q.previousClose, 99)
})

test("parseQuote defaults currency to USD", function() {
  var raw = JSON.stringify({
    chart: { result: [{ meta: {
      regularMarketPrice: 50,
      chartPreviousClose: 49
    }}] }
  })
  var q = M.parseQuote(raw)
  assert.equal(q.currency, "USD")
})

test("parseQuote returns null for empty string", function() {
  assert.equal(M.parseQuote(""), null)
})

test("parseQuote returns null for invalid JSON", function() {
  assert.equal(M.parseQuote("not json"), null)
})

test("parseQuote returns null for missing meta", function() {
  assert.equal(M.parseQuote(JSON.stringify({ chart: { result: [] } })), null)
})

test("parseQuote returns null for null price", function() {
  var raw = JSON.stringify({
    chart: { result: [{ meta: { regularMarketPrice: null } }] }
  })
  var q = M.parseQuote(raw)
  assert.equal(q.price, null)
})

test("parseQuote extracts day/52-week range and volume", function() {
  var raw = JSON.stringify({
    chart: { result: [{ meta: {
      regularMarketPrice: 100,
      chartPreviousClose: 99,
      currency: "USD",
      longName: "Acme Corp",
      regularMarketDayHigh: 103.5,
      regularMarketDayLow: 98.2,
      fiftyTwoWeekHigh: 140.0,
      fiftyTwoWeekLow: 80.1,
      regularMarketVolume: 34000000
    }}] }
  })
  var q = M.parseQuote(raw)
  assert.equal(q.dayHigh, 103.5)
  assert.equal(q.dayLow, 98.2)
  assert.equal(q.weekHigh52, 140.0)
  assert.equal(q.weekLow52, 80.1)
  assert.equal(q.volume, 34000000)
})

test("parseQuote extracts post-market price after the regular session", function() {
  var raw = JSON.stringify({
    chart: { result: [{ meta: {
      regularMarketPrice: 100,
      currentTradingPeriod: { regular: { start: 900, end: 1200 } }
    }, timestamp: [800, 850, 900, 1100, 1300, 1310],
      indicators: { quote: [{ close: [99, 99.2, 100, 100.5, 100.8, 101.0] }] } }] }
  })
  var q = M.parseQuote(raw)
  assert.equal(q.price, 100)
  assert.equal(q.preMarketPrice, 99.2)
  assert.equal(q.postMarketPrice, 101.0)
})

test("parseQuote leaves pre/post null without extended-hours data", function() {
  var raw = JSON.stringify({
    chart: { result: [{ meta: {
      regularMarketPrice: 100,
      currentTradingPeriod: { regular: { start: 900, end: 1200 } }
    }, timestamp: [900, 1000, 1100],
      indicators: { quote: [{ close: [100, 100.5, 100.3] }] } }] }
  })
  var q = M.parseQuote(raw)
  assert.equal(q.preMarketPrice, null)
  assert.equal(q.postMarketPrice, null)
})

// ── parseChart ──

test("parseChart extracts timestamps and closing prices", function() {
  var raw = JSON.stringify({
    chart: { result: [{
      timestamp: [1000, 2000, 3000],
      indicators: { quote: [{ close: [100.0, 101.5, 99.8] }] }
    }] }
  })
  var data = M.parseChart(raw)
  assert.equal(data.length, 3)
  assert.deepEqual(data[0], { t: 1000, p: 100.0 })
  assert.deepEqual(data[1], { t: 2000, p: 101.5 })
  assert.deepEqual(data[2], { t: 3000, p: 99.8 })
})

test("parseChart filters out null prices", function() {
  var raw = JSON.stringify({
    chart: { result: [{
      timestamp: [1000, 2000, 3000],
      indicators: { quote: [{ close: [100.0, null, 99.8] }] }
    }] }
  })
  var data = M.parseChart(raw)
  assert.equal(data.length, 2)
  assert.equal(data[0].p, 100.0)
  assert.equal(data[1].p, 99.8)
})

test("parseChart returns empty array for invalid JSON", function() {
  assert.deepEqual(M.parseChart("not json"), [])
})

test("parseChart returns empty array for empty string", function() {
  assert.deepEqual(M.parseChart(""), [])
})

test("parseChart returns empty array for missing result", function() {
  assert.deepEqual(M.parseChart(JSON.stringify({ chart: { result: [] } })), [])
})

test("parseChart returns empty array for missing timestamps", function() {
  var raw = JSON.stringify({
    chart: { result: [{
      indicators: { quote: [{ close: [100] }] }
    }] }
  })
  assert.deepEqual(M.parseChart(raw), [])
})

test("parseChart returns empty array for missing closes", function() {
  var raw = JSON.stringify({
    chart: { result: [{
      timestamp: [1000]
    }] }
  })
  assert.deepEqual(M.parseChart(raw), [])
})

// ── barLabel ──

test("barLabel formats ticker and price", function() {
  assert.equal(M.barLabel("AAPL", 305.54), "AAPL: 305.54")
})

test("barLabel shows ellipsis when price is null", function() {
  assert.equal(M.barLabel("MSFT", null), "MSFT: ...")
})

test("barLabel shows ellipsis when price is undefined", function() {
  assert.equal(M.barLabel("GOOGL", undefined), "GOOGL: ...")
})

test("barLabel uppercases ticker", function() {
  assert.equal(M.barLabel("tsla", 250.0), "TSLA: 250.00")
})

// ── fmtJsDate ──

test("fmtJsDate formats HH:mm", function() {
  var d = new Date(2026, 0, 15, 14, 5)
  assert.equal(M.fmtJsDate(d, "HH:mm"), "14:05")
})

test("fmtJsDate formats MMM d", function() {
  var d = new Date(2026, 0, 15)
  assert.equal(M.fmtJsDate(d, "MMM d"), "Jan 15")
})

test("fmtJsDate formats MMM yy", function() {
  var d = new Date(2026, 5, 1)
  assert.equal(M.fmtJsDate(d, "MMM yy"), "Jun 26")
})

// ── timeLabel ──

test("timeLabel uses HH:mm for 1D without fmtDt", function() {
  var d = new Date(2026, 0, 15, 14, 30)
  var ts = Math.floor(d.getTime() / 1000)
  assert.equal(M.timeLabel(ts, "1D", null), "14:30")
})

test("timeLabel uses MMM d for 1M without fmtDt", function() {
  var d = new Date(2026, 0, 15)
  var ts = Math.floor(d.getTime() / 1000)
  assert.equal(M.timeLabel(ts, "1M", null), "Jan 15")
})

test("timeLabel uses MMM yy for 1Y without fmtDt", function() {
  var d = new Date(2026, 5, 1)
  var ts = Math.floor(d.getTime() / 1000)
  assert.equal(M.timeLabel(ts, "1Y", null), "Jun 26")
})

test("timeLabel uses MMM d for 1W without fmtDt", function() {
  var d = new Date(2026, 0, 15)
  var ts = Math.floor(d.getTime() / 1000)
  assert.equal(M.timeLabel(ts, "1W", null), "Jan 15")
})

test("timeLabel calls fmtDt when provided", function() {
  var calls = []
  function fakeFmtDt(date, fmt) { calls.push([date.getTime(), fmt]); return "MOCK" }
  var ts = Math.floor(new Date(2026, 0, 15).getTime() / 1000)
  assert.equal(M.timeLabel(ts, "1W", fakeFmtDt), "MOCK")
  assert.equal(calls.length, 1)
  assert.equal(calls[0][1], "MMM d")
})

// ── TIMEFRAMES ──

test("TIMEFRAMES has 6 entries", function() {
  assert.equal(M.TIMEFRAMES.length, 6)
})

test("TIMEFRAMES contains expected values", function() {
  assert.deepEqual(M.TIMEFRAMES, ["1D", "1W", "1M", "6M", "1Y", "5Y"])
})

// ── padZero ──

test("padZero pads single digit", function() {
  assert.equal(M.padZero(5), "05")
})

test("padZero does not pad double digit", function() {
  assert.equal(M.padZero(12), "12")
})

test("padZero pads zero", function() {
  assert.equal(M.padZero(0), "00")
})

#!/usr/bin/env python3
"""Integration tests for the stock ticker plugin.

Tests the full data pipeline: API fetch -> parse -> format -> bar label.
All Model.js calls go through node subprocess to test the actual JS code.
Run with: python3 tests/test_integration.py
"""
import json
import subprocess
import sys
import os
import unittest

PLUGIN_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run_node(expr):
    """Evaluate a JS expression via node, requiring Model.js, return parsed result."""
    cmd = [
        "node", "-e",
        "const M = require('" + PLUGIN_DIR + "/Model.js'); " +
        "console.log(JSON.stringify(" + expr + "))"
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
    if result.returncode != 0:
        raise RuntimeError(f"node failed: {result.stderr[:500]}")
    return json.loads(result.stdout.strip())


def run_node_raw(expr):
    """Evaluate a JS expression via node, return raw stdout."""
    cmd = [
        "node", "-e",
        "const M = require('" + PLUGIN_DIR + "/Model.js'); " +
        "console.log(" + expr + ")"
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
    return result.stdout.strip(), result.returncode


def curl_yahoo(url_parts):
    """Run curl like the QML Process does."""
    result = subprocess.run(url_parts, capture_output=True, text=True, timeout=15)
    return result.stdout, result.returncode


def node_parse_quote(raw_json):
    """Parse a quote via Model.parseQuote in Node."""
    safe = json.dumps(raw_json)
    return run_node("M.parseQuote(" + safe + ")")


def node_parse_chart(raw_json):
    """Parse chart data via Model.parseChart in Node."""
    safe = json.dumps(raw_json)
    return run_node("M.parseChart(" + safe + ")")


def node_bar_label(ticker, price):
    """Generate bar label via Model.barLabel in Node."""
    return run_node_raw("M.barLabel(" + json.dumps(ticker) + ", " + str(price) + ")")[0]


class TestYahooApiFetch(unittest.TestCase):
    """Verify Yahoo Finance API is reachable and returns valid data."""

    def test_quote_api_returns_valid_json(self):
        cmd = run_node("M.quoteUrl('AAPL')")
        stdout, rc = curl_yahoo(cmd)
        self.assertEqual(rc, 0, f"curl failed: {stdout[:200]}")
        data = json.loads(stdout)
        self.assertIn("chart", data)
        results = data["chart"]["result"]
        self.assertTrue(len(results) > 0, "No chart results returned")
        meta = results[0]["meta"]
        self.assertIn("regularMarketPrice", meta)

    def test_quote_price_is_positive(self):
        cmd = run_node("M.quoteUrl('AAPL')")
        stdout, _ = curl_yahoo(cmd)
        data = json.loads(stdout)
        price = data["chart"]["result"][0]["meta"]["regularMarketPrice"]
        self.assertIsInstance(price, (int, float))
        self.assertGreater(price, 0)

    def test_quote_has_previous_close(self):
        cmd = run_node("M.quoteUrl('AAPL')")
        stdout, _ = curl_yahoo(cmd)
        data = json.loads(stdout)
        meta = data["chart"]["result"][0]["meta"]
        prev = meta.get("chartPreviousClose") or meta.get("previousClose")
        self.assertIsNotNone(prev, "No previous close in API response")
        self.assertGreater(prev, 0)

    def test_chart_1d_has_many_points(self):
        cmd = run_node("M.chartUrl('AAPL', '1D')")
        stdout, rc = curl_yahoo(cmd)
        self.assertEqual(rc, 0)
        data = json.loads(stdout)
        ts = data["chart"]["result"][0].get("timestamp", [])
        self.assertGreaterEqual(len(ts), 5, "1D chart should have data points")

    def test_chart_1y_has_many_points(self):
        cmd = run_node("M.chartUrl('AAPL', '1Y')")
        stdout, rc = curl_yahoo(cmd)
        self.assertEqual(rc, 0)
        data = json.loads(stdout)
        ts = data["chart"]["result"][0].get("timestamp", [])
        self.assertGreater(len(ts), 50, "1Y chart should have many data points")


class TestDataParsing(unittest.TestCase):
    """Verify Model.js parsing with real API responses."""

    def _fetch_quote_raw(self):
        cmd = run_node("M.quoteUrl('AAPL')")
        stdout, rc = curl_yahoo(cmd)
        self.assertEqual(rc, 0)
        return stdout

    def _fetch_chart_raw(self, tf):
        cmd = run_node("M.chartUrl('AAPL', '" + tf + "')")
        stdout, rc = curl_yahoo(cmd)
        self.assertEqual(rc, 0)
        return stdout

    def test_parseQuote_extracts_price(self):
        raw = self._fetch_quote_raw()
        q = node_parse_quote(raw)
        self.assertIsNotNone(q, "parseQuote returned None")
        self.assertIsInstance(q["price"], (int, float))
        self.assertGreater(q["price"], 0)

    def test_parseQuote_extracts_previous_close(self):
        raw = self._fetch_quote_raw()
        q = node_parse_quote(raw)
        self.assertIsNotNone(q["previousClose"])
        self.assertGreater(q["previousClose"], 0)

    def test_parseQuote_currency_is_usd(self):
        raw = self._fetch_quote_raw()
        q = node_parse_quote(raw)
        self.assertEqual(q["currency"], "USD")

    def test_parseChart_1d_has_valid_points(self):
        raw = self._fetch_chart_raw("1D")
        data = node_parse_chart(raw)
        self.assertGreaterEqual(len(data), 5)
        for point in data:
            self.assertIn("t", point)
            self.assertIn("p", point)
            self.assertIsInstance(point["t"], (int, float))
            self.assertIsInstance(point["p"], (int, float))
            self.assertGreater(point["p"], 0)

    def test_parseChart_1y_has_valid_range(self):
        raw = self._fetch_chart_raw("1Y")
        data = node_parse_chart(raw)
        self.assertGreater(len(data), 50)
        prices = [p["p"] for p in data]
        self.assertGreater(min(prices), 100, "AAPL should be > $100")
        self.assertLess(max(prices), 500, "AAPL should be < $500")


class TestBarLabel(unittest.TestCase):
    """Verify bar label generation with real data."""

    def test_bar_label_shows_price(self):
        cmd = run_node("M.quoteUrl('AAPL')")
        stdout, _ = curl_yahoo(cmd)
        q = node_parse_quote(stdout)
        label = node_bar_label("AAPL", q["price"])
        self.assertTrue(label.startswith("aapl: "))
        self.assertNotEqual(label, "aapl: ...")

    def test_bar_label_price_is_number(self):
        cmd = run_node("M.quoteUrl('AAPL')")
        stdout, _ = curl_yahoo(cmd)
        q = node_parse_quote(stdout)
        label = node_bar_label("AAPL", q["price"])
        price_str = label.split(": ")[1]
        price = float(price_str)
        self.assertGreater(price, 0)


class TestTimeframeSwitching(unittest.TestCase):
    """Verify chart data changes when switching timeframes."""

    def test_different_timeframes_different_points(self):
        raw_1d = self._fetch_chart_raw("1D")
        raw_1y = self._fetch_chart_raw("1Y")
        data_1d = node_parse_chart(raw_1d)
        data_1y = node_parse_chart(raw_1y)
        self.assertNotEqual(len(data_1d), len(data_1y),
                            "1D and 1Y should have different data point counts")

    def _fetch_chart_raw(self, tf):
        cmd = run_node("M.chartUrl('AAPL', '" + tf + "')")
        stdout, rc = curl_yahoo(cmd)
        self.assertEqual(rc, 0)
        return stdout


class TestEdgeCases(unittest.TestCase):
    """Verify error handling for edge cases."""

    def test_invalid_ticker_returns_empty(self):
        cmd = run_node("M.chartUrl('INVALID_TICKER_XYZ123', '1D')")
        stdout, _ = curl_yahoo(cmd)
        data = node_parse_chart(stdout)
        self.assertIsInstance(data, list)

    def test_empty_string_parse_quote(self):
        result = node_parse_quote("")
        self.assertIsNone(result)

    def test_empty_string_parse_chart(self):
        result = node_parse_chart("")
        self.assertEqual(result, [])

    def test_malformed_json_parse_quote(self):
        result = node_parse_quote("not json at all")
        self.assertIsNone(result)

    def test_malformed_json_parse_chart(self):
        result = node_parse_chart("not json at all")
        self.assertEqual(result, [])


class TestFormattingConsistency(unittest.TestCase):
    """Verify formatting functions produce consistent output."""

    def test_fmtPrice_two_decimals(self):
        out, _ = run_node_raw("M.fmtPrice(100.0)")
        self.assertEqual(out, "100.00")
        out, _ = run_node_raw("M.fmtPrice(100.5)")
        self.assertEqual(out, "100.50")

    def test_fmtPrice_penny_stock_four_decimals(self):
        out, _ = run_node_raw("M.fmtPrice(0.0053)")
        self.assertEqual(out, "0.0053")

    def test_fmtChange_sign(self):
        out, _ = run_node_raw("M.fmtChange(1.0)")
        self.assertTrue(out.startswith("+"))
        out, _ = run_node_raw("M.fmtChange(-1.0)")
        self.assertTrue(out.startswith("-"))

    def test_fmtPct_ends_with_percent(self):
        out, _ = run_node_raw("M.fmtPct(5.0)")
        self.assertTrue(out.endswith("%"))
        out, _ = run_node_raw("M.fmtPct(-3.0)")
        self.assertTrue(out.endswith("%"))


if __name__ == "__main__":
    unittest.main(verbosity=2)

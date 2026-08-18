# Stock Ticker

Real-time stock price ticker with an interactive line chart for the Omarchy Quattro bar.

## Install

```sh
omarchy plugin add https://github.com/christensen/omarchy-stock-ticker.git --enable
```

## Usage

### Bar label

Shows the ticker (uppercase), the latest price, and the day's percent change, e.g. `MU: 937.85 -7.3%`. The label color follows the day's move: green when up, red when down, dimmed when the data is stale (no successful fetch within three refresh cycles).

Click the label to open the details panel; middle-click refreshes immediately.

### Details panel

- Company name, ticker (editable — see below), price with currency
- Day's change ($ and %), previous close, currency
- Day range bar with a marker at the current price, plus day low → high
- 52-week low → high range
- Volume (abbreviated: `12.4M`, `340K`)
- "Updated Xs ago" freshness line (amber when stale)
- Interactive line chart with a hover crosshair showing `price · time`
- Timeframe selector: 1D, 1W, 1M, 6M, 1Y, 5Y
- "Ticker not found" feedback when a symbol does not exist

### Keyboard

| Key | Action |
| --- | --- |
| `Enter` | Edit ticker symbol |
| `←` / `→` (or `h` / `l`) | Step through timeframes |
| `r` | Refresh now |
| `Esc` | Close the panel |
| `Tab` / `Shift+Tab` | Switch to the neighboring panel |

### Refresh behavior

- Base interval comes from `refreshSec` (default 5 seconds).
- While the NYSE is open (9:30–16:00 ET, Mon–Fri) the plugin refreshes at the base interval; when the market is closed it slows to 12× that.
- On consecutive fetch failures the interval backs off exponentially (up to 8×), and resets after a successful fetch.
- An invalid ticker stops automatic retries until you edit the symbol.

## Multiple tickers

The plugin supports multiple instances (`allowMultiple: true`). Add more than one entry to the bar layout, each with its own `ticker`:

```json
{
  "id": "christensen.stock-ticker",
  "ticker": "MSFT",
  "refreshSec": 10
},
{
  "id": "christensen.stock-ticker",
  "ticker": "AAPL"
}
```

## Configure

Change the tracked stock in `~/.config/omarchy/shell.json`:

```json
{"id": "christensen.stock-ticker", "ticker": "MSFT", "refreshSec": 10}
```

Or click the ticker name in the panel and press `Enter` to edit it interactively.

### Settings

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `ticker` | string | `AAPL` | Stock symbol, e.g. `AAPL`, `MSFT`, `GOOGL` |
| `refreshSec` | integer | `5` | Base price refresh interval in seconds (3–60) |

## Tests

Pure helpers in `Model.js` are covered by Node's test runner:

```sh
node --test tests/model.test.js
```

## Remove

```sh
omarchy plugin remove christensen.stock-ticker
```

## Dependencies

- `curl` (for Yahoo Finance API requests)
- Internet connection (for live price data)

## License

MIT
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "christensen.stock-ticker"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.45)
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : "JetBrainsMono Nerd Font"

  readonly property string currentTicker: setting("ticker", "AAPL")
  readonly property int refreshInterval: Math.max(3, parseInt(setting("refreshSec", "5"), 10) || 5)
  readonly property int etOffsetMinutes: -300

  // True when no successful quote fetch happened within 3 refresh cycles.
  readonly property bool stale: lastUpdated > 0 && (root._now - root.lastUpdated) > root.refreshInterval * 1000 * 3

  readonly property string barChangeLabel: {
    if (!quote || quote.price === null || !quote.previousClose) return ""
    var ch = quote.price - quote.previousClose
    return Model.fmtPct((ch / quote.previousClose) * 100)
  }

  property string timeFrame: "1D"
  property var quote: null
  property var chartData: []
  property bool editingTicker: false
  property bool loading: false
  property bool quoteQueued: false
  property bool chartQueued: false
  property double lastUpdated: 0
  property double _now: Date.now()
  property int failCount: 0
  property bool tickerInvalid: false
  property string _quoteStdout: ""
  property string _quoteStderr: ""
  property string _chartStdout: ""
  property string _chartStderr: ""
  property string _watchStdout: ""
  property string _watchStderr: ""

  // ── Watchlist state ──────────────────────────────────────────────────────
  // Persisted as a shared JSON file (symbols + last-known mini-quote cache) so
  // multiple instances of the widget see the same list. Reassigned (never
  // mutated in place) so QML bindings / ListView pick up changes.
  property string watchlistPath: Quickshell.env("HOME") + "/.local/share/stock-ticker/watchlist.json"
  property var watchlist: []
  property var watchlistQuotes: ({})
  property bool watchlistLoaded: false
  property bool watchlistMode: false
  property bool addingTicker: false
  property string addError: ""
  property string pendingAdd: ""
  property int watchCursor: -1
  property string watchFetching: ""

  readonly property string barLabel: {
    if (!quote || quote.price === null || quote.price === undefined)
      return currentTicker.toUpperCase() + ": ..."
    return currentTicker.toUpperCase() + ": " + Model.fmtPrice(quote.price) +
           (barChangeLabel ? " " + barChangeLabel : "")
  }

  readonly property string tooltipText: {
    if (!quote || quote.price === null) return currentTicker
    var change = quote.price - quote.previousClose
    var pct = quote.previousClose ? (change / quote.previousClose) * 100 : 0
    var name = quote.companyName ? quote.companyName + " \u00b7 " : ""
    return name + currentTicker.toUpperCase() + " " + Model.fmtPrice(quote.price) +
           " (" + Model.fmtChange(change) + " / " + Model.fmtPct(pct) + ")"
  }

  readonly property color barLabelColor: {
    if (root.stale) return root.dim
    if (!quote || quote.price === null ||
        quote.previousClose === null || quote.previousClose === undefined)
      return fg
    return Model.changeColor(quote.price - quote.previousClose, fg)
  }

  function open() {
    root.controller.show()
    refresh()
  }

  function close() {
    if (root.editingTicker) cancelEditTicker()
    if (root.addingTicker) cancelAddTicker()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) close()
    else {
      watchlistMode = false
      open()
    }
  }

  function showWatchlist() {
    watchlistMode = true
    open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function refresh() {
    if (!currentTicker || currentTicker.trim() === "") return
    if (quoteProc.running) { quoteQueued = true; return }
    if (chartProc.running) { chartQueued = true; return }
    _quoteStdout = ""
    _quoteStderr = ""
    _chartStdout = ""
    _chartStderr = ""
    loading = quote === null
    quoteProc.command = Model.quoteUrl(currentTicker)
    quoteProc.running = true
    chartProc.command = Model.chartUrl(currentTicker, timeFrame)
    chartProc.running = true
  }

  function changeTimeframe(tf) {
    if (tf === timeFrame) return
    timeFrame = tf
    chartData = []
    if (!chartProc.running) {
      _chartStdout = ""
      _chartStderr = ""
      chartProc.command = Model.chartUrl(currentTicker, timeFrame)
      chartProc.running = true
    } else {
      chartQueued = true
    }
  }

  function stepTimeframe(dir) {
    var i = Model.TIMEFRAMES.indexOf(timeFrame)
    var next = Math.max(0, Math.min(Model.TIMEFRAMES.length - 1, i + dir))
    changeTimeframe(Model.TIMEFRAMES[next])
  }

  function startEditTicker() {
    editingTicker = true
    Qt.callLater(function() {
      tickerField.text = currentTicker
      tickerField.selectAll()
      tickerField.forceActiveFocus()
    })
  }

  function cancelEditTicker() {
    editingTicker = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function commitEditTicker() {
    var newTicker = tickerField.text.trim().toUpperCase()
    if (newTicker === "" || newTicker === currentTicker) {
      cancelEditTicker()
      return
    }
    applyTicker(newTicker)
    editingTicker = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  // Shared tail of commitEditTicker() and selectTicker(): persist the ticker
  // choice through the inline settings entry, drop stale data, refetch.
  function applyTicker(symbol) {
    var entry = { id: root.moduleName }
    for (var key in root.settings) {
      if (key !== "id") entry[key] = root.settings[key]
    }
    entry.ticker = symbol
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
    quote = null
    chartData = []
    tickerInvalid = false
    failCount = 0
    Qt.callLater(refresh)
  }

  function selectTicker(symbol) {
    if (!symbol) return
    applyTicker(symbol)
    watchlistMode = false
  }

  // ── Watchlist persistence ────────────────────────────────────────────────

  function cacheFromQuote(q) {
    return { price: q.price, previousClose: q.previousClose, currency: q.currency }
  }

  function loadWatchlistFile() {
    var txt = watchlistFile.text() || ""
    var parsed = null
    try { parsed = JSON.parse(txt) } catch (e) { parsed = null }
    var syms = (parsed && parsed.symbols && Array.isArray(parsed.symbols)) ? parsed.symbols : []
    var clean = []
    for (var i = 0; i < syms.length; i++) {
      var s = String(syms[i]).trim().toUpperCase()
      if (s && clean.indexOf(s) < 0) clean.push(s)
    }
    root.watchlist = clean
    root.watchlistQuotes = (parsed && parsed.quotes && typeof parsed.quotes === "object")
      ? parsed.quotes : {}
    root.watchlistLoaded = true
    if (root.watchlistMode) startWatchQueue()
  }

  function saveWatchlist() {
    if (!root.watchlistLoaded) return
    watchlistFile.setText(JSON.stringify({
      symbols: root.watchlist,
      quotes: root.watchlistQuotes
    }))
  }

  // ── Watchlist mini-quote queue ───────────────────────────────────────────
  // One shared Process walks the list sequentially, refreshing each entry's
  // cached mini-quote. Runs only while the watchlist pane is visible.

  function startWatchQueue() {
    if (!root.watchlistLoaded) return
    if (watchQueueTimer.running) return
    root.watchCursor = 0
    fetchNextWatch()
    watchQueueTimer.start()
  }

  function stopWatchQueue() {
    watchQueueTimer.stop()
  }

  function fetchNextWatch() {
    if (watchProc.running) return
    if (root.pendingAdd !== "") {
      root.watchFetching = root.pendingAdd
      watchProc.command = Model.quoteUrl(root.pendingAdd)
      watchProc.running = true
      return
    }
    if (!root.watchlist || root.watchlist.length === 0) return
    if (root.watchCursor < 0 || root.watchCursor >= root.watchlist.length) return
    root.watchFetching = root.watchlist[root.watchCursor]
    watchProc.command = Model.quoteUrl(root.watchFetching)
    watchProc.running = true
  }

  function moveWatchCursor(dir) {
    if (!root.watchlist || root.watchlist.length === 0) return
    var next = watchlistView.currentIndex + dir
    if (next < 0) next = 0
    if (next >= root.watchlist.length) next = root.watchlist.length - 1
    watchlistView.currentIndex = next
  }

  // ── Watchlist mutation ───────────────────────────────────────────────────

  function addToList(symbol, q) {
    var arr = root.watchlist.slice()
    arr.push(symbol)
    root.watchlist = arr
    var qs = {}
    for (var k in root.watchlistQuotes) qs[k] = root.watchlistQuotes[k]
    qs[symbol] = cacheFromQuote(q)
    root.watchlistQuotes = qs
    root.saveWatchlist()
  }

  function removeTicker(symbol) {
    var idx = root.watchlist.indexOf(symbol)
    if (idx < 0) return
    var arr = root.watchlist.slice()
    arr.splice(idx, 1)
    root.watchlist = arr
    var qs = {}
    for (var k in root.watchlistQuotes) {
      if (k !== symbol) qs[k] = root.watchlistQuotes[k]
    }
    root.watchlistQuotes = qs
    if (watchlistView.currentIndex > arr.length - 1)
      watchlistView.currentIndex = Math.max(0, arr.length - 1)
    root.saveWatchlist()
  }

  function startAddTicker() {
    root.addError = ""
    root.addingTicker = true
    Qt.callLater(function() {
      addField.text = ""
      addField.forceActiveFocus()
    })
  }

  function cancelAddTicker() {
    root.addingTicker = false
    root.addError = ""
    root.pendingAdd = ""
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function commitAddTicker() {
    var sym = addField.text.trim().toUpperCase()
    if (!sym) return
    if (root.watchlist.indexOf(sym) >= 0) {
      root.addError = "Already on watchlist"
      Qt.callLater(function() { if (addField) addField.forceActiveFocus() })
      return
    }
    if (root.pendingAdd !== "") return
    root.addError = ""
    root.pendingAdd = sym
    fetchNextWatch()
  }

  // Called by the queue when the pending-add fetch validated successfully.
  function commitAdd(symbol, q) {
    addToList(symbol, q)
    root.addingTicker = false
    root.addError = ""
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  Component.onCompleted: Qt.callLater(refresh)

  onOpenedChanged: {
    if (opened) {
      refresh()
      paintTimer.start()
    } else {
      paintTimer.stop()
      stopWatchQueue()
    }
  }

  onWatchlistModeChanged: {
    if (watchlistMode) {
      startWatchQueue()
      Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
    } else {
      stopWatchQueue()
      root.addError = ""
      if (root.addingTicker) cancelAddTicker()
    }
  }

  Timer {
    id: paintTimer
    interval: 200
    repeat: true
    onTriggered: if (chartCanvas) chartCanvas.requestPaint()
  }

  Process {
    id: quoteProc
    running: false
    command: []

    onExited: function(exitCode) {
      root.loading = false
      var stdout = String(quoteOutput.text || root._quoteStdout || "")
      var q = Model.parseQuote(stdout.trim())
      if (q) {
        root.quote = q
        root.lastUpdated = Date.now()
        root.failCount = 0
        root.tickerInvalid = false
      } else {
        root.failCount++
        if (exitCode !== 0) root.tickerInvalid = true
      }
      if (root.quoteQueued) {
        root.quoteQueued = false
        Qt.callLater(root.refresh)
      }
    }

    stdout: StdioCollector {
      id: quoteOutput
      waitForEnd: true
      onStreamFinished: root._quoteStdout = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._quoteStderr = text
    }
  }

  Process {
    id: chartProc
    running: false
    command: []

    onExited: function(exitCode) {
      var stdout = String(chartOutput.text || root._chartStdout || "")
      root.chartData = Model.parseChart(stdout)
      if (root.chartQueued) {
        root.chartQueued = false
        if (root.currentTicker && root.currentTicker.trim() !== "") {
          chartProc.command = Model.chartUrl(root.currentTicker, root.timeFrame)
          chartProc.running = true
        }
      }
    }

    stdout: StdioCollector {
      id: chartOutput
      waitForEnd: true
      onStreamFinished: root._chartStdout = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._chartStderr = text
    }
  }

  Process {
    id: watchProc
    running: false
    command: []

    onExited: function(exitCode) {
      var stdout = String(watchOutput.text || root._watchStdout || "")
      var fetchSym = root.watchFetching
      root.watchFetching = ""
      var q = Model.parseQuote(stdout.trim())

      // A pending add is validated before any queue refresh step. The fetch
      // only counts as validation when it was launched for that symbol.
      if (root.pendingAdd !== "" && fetchSym === root.pendingAdd) {
        root.pendingAdd = ""
        root.addingTicker = false
        if (q) {
          root.commitAdd(fetchSym, q)
        } else {
          root.addError = "Ticker not found"
          Qt.callLater(function() { if (addField) addField.forceActiveFocus() })
        }
        if (root.watchlistMode) Qt.callLater(root.fetchNextWatch)
        return
      }

      if (q && fetchSym && root.watchCursor >= 0 &&
          root.watchCursor < root.watchlist.length &&
          fetchSym === root.watchlist[root.watchCursor]) {
        var qs = {}
        for (var k in root.watchlistQuotes) qs[k] = root.watchlistQuotes[k]
        qs[fetchSym] = root.cacheFromQuote(q)
        root.watchlistQuotes = qs
        if (root.watchCursor === root.watchlist.length - 1) root.saveWatchlist()
        root.watchCursor++
        if (root.watchCursor < root.watchlist.length) fetchNextWatch()
      }
    }

    stdout: StdioCollector {
      id: watchOutput
      waitForEnd: true
      onStreamFinished: root._watchStdout = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._watchStderr = text
    }
  }

  // Runs one full sequential pass over the watchlist every 45s while the
  // watchlist pane is open; each pass refreshes every entry's cached quote.
  Timer {
    id: watchQueueTimer
    interval: 45000
    repeat: true
    running: false
    triggeredOnStart: false
    onTriggered: {
      if (!root.watchlistMode) { stop(); return }
      if (watchProc.running) return
      if (!root.watchlist || root.watchlist.length === 0) return
      root.watchCursor = 0
      fetchNextWatch()
    }
  }

  // Shared watchlist file. Reads are async; onLoaded syncs our in-memory
  // copy (and catches writes from other widget instances via watchChanges).
  FileView {
    id: watchlistFile
    path: root.watchlistPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadWatchlistFile()
    onLoadFailed: function(error) {
      // Missing file on first run: start with an empty list.
      root.watchlistLoaded = true
    }
  }

  Timer {
    id: refreshTimer
    // Refresh faster while the market is open and back off exponentially on
    // consecutive failures (capped at 8x the base interval).
    interval: root.refreshInterval * 1000 *
              (Model.isMarketOpen(root._now, root.etOffsetMinutes) ? 1 : 12) *
              Math.min(8, Math.pow(2, root.failCount))
    running: true
    repeat: true
    triggeredOnStart: false
    onTriggered: if (!root.tickerInvalid) root.refresh()
  }

  // Drives `_now`, which makes the stale/interval bindings re-evaluate even
  // though Date.now() alone is not reactive in QML.
  Timer {
    id: tickTimer
    interval: 1000
    repeat: true
    running: true
    onTriggered: root._now = Date.now()
  }

  Connections {
    target: root
    function onFailCountChanged() { refreshTimer.restart() }
  }

  IpcHandler {
    target: "christensen.stock-ticker"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(480))
    contentHeight: panel.fittedContentHeight(Math.max(contentCol.implicitHeight, watchCol.implicitHeight))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editingTicker || root.addingTicker
      onCloseRequested: root.close()
      onReturnRequested: root.watchlistMode
        ? root.selectTicker(root.watchlist[watchlistView.currentIndex])
        : root.startEditTicker()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (root.watchlistMode) {
          if (dy !== 0) root.moveWatchCursor(dy)
        } else if (dx !== 0) {
          root.stepTimeframe(dx)
        }
      }
      onDeleteRequested: function() {
        if (root.watchlistMode && root.watchlist.length > 0)
          root.removeTicker(root.watchlist[watchlistView.currentIndex])
      }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
        else if (root.watchlistMode && (t === "a" || t === "A")) root.startAddTicker()
      }

      Flickable {
        id: mainScroll
        anchors.fill: parent
        visible: !root.watchlistMode
        contentWidth: width
        contentHeight: contentCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: contentCol
          width: mainScroll.width
          spacing: Style.space(14)

          // ── Header ──
          Row {
            width: parent.width
            spacing: Style.space(10)

            Column {
              width: parent.width - changeCol.width - Style.space(10)
              spacing: Style.space(2)

              // Company name
              Text {
                visible: root.quote && root.quote.companyName
                width: parent.width
                elide: Text.ElideRight
                text: root.quote ? root.quote.companyName : ""
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              // Ticker
              Item {
                visible: !root.editingTicker
                width: tickerRow.width
                height: tickerRow.height

                Row {
                  id: tickerRow
                  spacing: Style.space(6)

                  Text {
                    text: root.currentTicker.toUpperCase()
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.display
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    text: "\uf040"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.startEditTicker()
                }
              }

              Row {
                visible: root.editingTicker
                spacing: Style.space(4)

                TextField {
                  id: tickerField
                  width: Style.space(120)
                  foreground: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                  font.bold: true
                  placeholderText: "AAPL"

                  Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Escape) {
                      root.cancelEditTicker()
                      event.accepted = true
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                      root.commitEditTicker()
                      event.accepted = true
                    }
                  }
                }

                Text {
                  text: "\uf00c"
                  color: "#22c55e"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  anchors.verticalCenter: parent.verticalCenter

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.commitEditTicker()
                  }
                }

                Text {
                  text: "\uf00d"
                  color: "#ef4444"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  anchors.verticalCenter: parent.verticalCenter

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.cancelEditTicker()
                  }
                }
              }

              // Price
              Text {
                visible: root.quote !== null
                text: root.quote ? Model.fmtPriceWithCurrency(root.quote.price, root.quote.currency) : ""
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: 56
                font.bold: true
              }

              // Day range bar with marker at current price
              Rectangle {
                visible: root.quote !== null && root.quote.dayLow !== null &&
                         root.quote.dayHigh !== null && root.quote.dayHigh > root.quote.dayLow
                width: parent.width
                height: 3
                radius: 1.5
                color: Qt.rgba(1, 1, 1, 0.16)

                Rectangle {
                  id: dayMarker
                  width: 3
                  height: 9
                  radius: 1.5
                  color: root.fg
                  y: (parent.height - height) / 2
                  x: {
                    if (!root.quote || root.quote.price === null ||
                        root.quote.dayLow === null || root.quote.dayHigh === null ||
                        root.quote.dayHigh <= root.quote.dayLow) return 0
                    var f = (root.quote.price - root.quote.dayLow) /
                           (root.quote.dayHigh - root.quote.dayLow)
                    if (f < 0) f = 0
                    if (f > 1) f = 1
                    return f * parent.width - width / 2
                  }
                }
              }

              // Day range
              Row {
                visible: root.quote !== null && root.quote.dayLow !== null &&
                         root.quote.dayHigh !== null
                spacing: Style.space(6)

                Text {
                  text: "Day"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Text {
                  text: root.quote ? Model.fmtPriceWithCurrency(root.quote.dayLow, root.quote.currency) : ""
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Text {
                  text: "\u2192"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Text {
                  text: root.quote ? Model.fmtPriceWithCurrency(root.quote.dayHigh, root.quote.currency) : ""
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              // 52-week range
              Row {
                visible: root.quote !== null && root.quote.weekLow52 !== null &&
                         root.quote.weekHigh52 !== null
                spacing: Style.space(6)

                Text {
                  text: "52W"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Text {
                  text: root.quote ? Model.fmtPriceWithCurrency(root.quote.weekLow52, root.quote.currency) : ""
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Text {
                  text: "\u2192"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Text {
                  text: root.quote ? Model.fmtPriceWithCurrency(root.quote.weekHigh52, root.quote.currency) : ""
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              // Volume
              Row {
                visible: root.quote !== null && root.quote.volume !== null
                spacing: Style.space(6)

                Text {
                  text: "Vol"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Text {
                  text: root.quote ? Model.fmtVolume(root.quote.volume) : ""
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              // Last-update freshness
              Text {
                visible: root.quote !== null && root.lastUpdated > 0
                text: {
                  var secs = Math.max(0, Math.round((root._now - root.lastUpdated) / 1000))
                  return "updated " + secs + "s ago"
                }
                color: root.stale ? "#eab308" : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Column {
              id: changeCol
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)
              visible: root.quote !== null && root.quote.previousClose !== null

              Text {
                visible: root.quote !== null
                text: {
                  if (!root.quote) return ""
                  var ch = root.quote.price - root.quote.previousClose
                  return Model.fmtChange(ch) + " (" + Model.fmtPct(
                    root.quote.previousClose ? (ch / root.quote.previousClose) * 100 : 0
                  ) + ")"
                }
                color: root.quote
                  ? Model.changeColor(root.quote.price - root.quote.previousClose, root.dim)
                  : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                horizontalAlignment: Text.AlignRight
              }

              Text {
                visible: root.quote !== null
                text: root.quote ? Model.fmtPrice(root.quote.previousClose) + " prev close" : ""
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                horizontalAlignment: Text.AlignRight
              }

              Text {
                visible: root.quote !== null
                text: root.quote ? (root.quote.currency || "USD") : ""
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                horizontalAlignment: Text.AlignRight
              }
            }
          }

          // ── Loading ──
          Text {
            visible: root.loading && root.quote === null && !root.tickerInvalid
            text: "Fetching price..."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.italic: true
          }

          Text {
            visible: root.tickerInvalid
            text: "Ticker not found"
            color: "#ef4444"
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.italic: true
          }

          // ── Divider ──
          PanelSeparator { width: parent.width; foreground: root.fg }

          // ── Chart ──
          Item {
            width: parent.width
            height: 180
            visible: root.chartData.length > 0

            Canvas {
              id: chartCanvas
              anchors.fill: parent

              property var dataPoints: root.chartData
              property string tf: root.timeFrame
              property var lastPx: []
              property var lastPy: []
              property int hoverIndex: -1

              onDataPointsChanged: requestPaint()
              onTfChanged: requestPaint()

              onPaint: {
                var ctx = getContext("2d")
                if (!ctx || !dataPoints || dataPoints.length < 2) return

                ctx.clearRect(0, 0, width, height)

                var padL = 55
                var padR = 12
                var padT = 10
                var padB = 22
                var cw = width - padL - padR
                var ch = height - padT - padB

                var minP = dataPoints[0].p
                var maxP = dataPoints[0].p
                for (var i = 1; i < dataPoints.length; i++) {
                  if (dataPoints[i].p < minP) minP = dataPoints[i].p
                  if (dataPoints[i].p > maxP) maxP = dataPoints[i].p
                }
                var range = maxP - minP
                if (range < 0.01) { range = 1; minP -= 0.5 }

                var px = [], py = []
                for (var j = 0; j < dataPoints.length; j++) {
                  px.push(padL + (j / (dataPoints.length - 1)) * cw)
                  py.push(padT + (1 - (dataPoints[j].p - minP) / range) * ch)
                }

                var up = dataPoints[dataPoints.length - 1].p >= dataPoints[0].p
                var lineColor = up ? "#22c55e" : "#ef4444"

                // Area fill
                ctx.beginPath()
                ctx.moveTo(px[0], padT + ch)
                for (var k = 0; k < px.length; k++) ctx.lineTo(px[k], py[k])
                ctx.lineTo(px[px.length - 1], padT + ch)
                ctx.closePath()
                ctx.fillStyle = up ? "rgba(34,197,94,0.08)" : "rgba(239,68,68,0.08)"
                ctx.fill()

                // Line
                ctx.beginPath()
                ctx.moveTo(px[0], py[0])
                for (var m = 1; m < px.length; m++) ctx.lineTo(px[m], py[m])
                ctx.strokeStyle = lineColor
                ctx.lineWidth = 1.8
                ctx.stroke()

                // Current price dot
                var lastX = px[px.length - 1]
                var lastY = py[py.length - 1]
                ctx.beginPath()
                ctx.arc(lastX, lastY, 3, 0, Math.PI * 2)
                ctx.fillStyle = lineColor
                ctx.fill()

                // Text setup
                ctx.font = "10px " + root.fontFamily
                ctx.fillStyle = root.dim

                // High / low labels
                ctx.textAlign = "right"
                ctx.fillText(Model.fmtPrice(maxP), padL - 6, padT + 8)
                ctx.fillStyle = up ? "rgba(34,197,94,0.7)" : "rgba(239,68,68,0.7)"
                ctx.fillText(Model.fmtPrice(minP), padL - 6, padT + ch)
                ctx.fillStyle = root.dim

                // Y-axis ticks
                ctx.textAlign = "right"
                for (var n = 1; n <= 3; n++) {
                  var tv = minP + range * n / 4
                  var ty = padT + (1 - n / 4) * ch
                  ctx.fillText(Model.fmtPrice(tv), padL - 6, ty + 4)
                  ctx.strokeStyle = "rgba(255,255,255,0.04)"
                  ctx.lineWidth = 0.5
                  ctx.beginPath()
                  ctx.moveTo(padL, ty)
                  ctx.lineTo(padL + cw, ty)
                  ctx.stroke()
                }

                // X-axis labels
                ctx.textAlign = "center"
                var labelCount = Math.min(6, dataPoints.length)
                var step = Math.max(1, Math.floor((dataPoints.length - 1) / (labelCount - 1)))
                for (var q = 0; q < dataPoints.length; q += step) {
                  if (q >= dataPoints.length) break
                  var label = Model.timeLabel(dataPoints[q].t, tf, Qt.formatDateTime)
                  ctx.fillText(label, px[q], padT + ch + 16)
                }

                // Cache hit-test coordinates for the hover overlay
                lastPx = px
                lastPy = py

                // ── Hover crosshair ──
                if (hoverIndex >= 0 && hoverIndex < dataPoints.length) {
                  var hx = px[hoverIndex]
                  var hy = py[hoverIndex]

                  // Vertical guide
                  ctx.strokeStyle = "rgba(255,255,255,0.25)"
                  ctx.lineWidth = 1
                  ctx.beginPath()
                  ctx.moveTo(hx, padT)
                  ctx.lineTo(hx, padT + ch)
                  ctx.stroke()

                  // Point marker
                  ctx.beginPath()
                  ctx.arc(hx, hy, 4, 0, Math.PI * 2)
                  ctx.fillStyle = root.fg
                  ctx.fill()
                  ctx.beginPath()
                  ctx.arc(hx, hy, 2, 0, Math.PI * 2)
                  ctx.fillStyle = lineColor
                  ctx.fill()

                  // Price / time label, clamped to stay inside the canvas
                  ctx.font = "10px " + root.fontFamily
                  var priceStr = Model.fmtPrice(dataPoints[hoverIndex].p)
                  var timeStr = Model.timeLabel(dataPoints[hoverIndex].t, tf, Qt.formatDateTime)
                  var hoverText = priceStr + " \u00b7 " + timeStr
                  var textW = ctx.measureText(hoverText).width
                  var boxW = textW + 10
                  var boxH = 16
                  var boxX = hx - boxW / 2
                  boxX = Math.max(padL, Math.min(boxX, width - padR - boxW))
                  var boxY = hy - boxH - 6 < padT ? hy + 6 : hy - boxH - 6
                  ctx.fillStyle = "rgba(0,0,0,0.72)"
                  ctx.beginPath()
                  ctx.rect(boxX, boxY, boxW, boxH)
                  ctx.fill()
                  ctx.fillStyle = root.fg
                  ctx.textAlign = "center"
                  ctx.fillText(hoverText, boxX + boxW / 2, boxY + 11)
                }
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.CrossCursor
              onPositionChanged: {
                var ps = chartCanvas.lastPx
                if (!ps || ps.length === 0) return
                var best = -1
                var bestD = 1e9
                for (var i = 0; i < ps.length; i++) {
                  var d = Math.abs(ps[i] - mouseX)
                  if (d < bestD) { bestD = d; best = i }
                }
                if (best !== chartCanvas.hoverIndex) {
                  chartCanvas.hoverIndex = best
                  chartCanvas.requestPaint()
                }
              }
              onExited: {
                if (chartCanvas.hoverIndex !== -1) {
                  chartCanvas.hoverIndex = -1
                  chartCanvas.requestPaint()
                }
              }
            }
          }

          // ── Timeframe selector ──
          Row {
            width: parent.width
            spacing: Style.space(8)

            Repeater {
              model: Model.TIMEFRAMES

              Rectangle {
                required property string modelData
                required property int index
                width: label.implicitWidth + Style.space(16)
                height: label.implicitHeight + Style.space(8)
                radius: Style.cornerRadius
                color: modelData === root.timeFrame
                  ? Style.hoverFillFor(root.fg, Color.accent)
                  : "transparent"

                Text {
                  id: label
                  anchors.centerIn: parent
                  text: modelData
                  color: modelData === root.timeFrame
                    ? root.fg
                    : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: modelData === root.timeFrame
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.changeTimeframe(modelData)
                }
              }
            }
          }

          // ── Footer ──
          PanelSeparator { width: parent.width; foreground: root.fg }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "enter edit ticker \u00b7 r refresh \u00b7 esc closes"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      // ── Watchlist pane ──
      Flickable {
        id: watchScroll
        anchors.fill: parent
        visible: root.watchlistMode
        contentWidth: width
        contentHeight: watchCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: watchCol
          width: watchScroll.width
          spacing: Style.space(10)

          // Header
          Row {
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: "Watchlist"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              font.bold: true
            }

            Text {
              text: root.watchlist.length + " symbols"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          // Symbols with cached mini-quotes
          ListView {
            id: watchlistView
            width: parent.width
            height: Math.min(root.watchlist.length, 6) * Style.space(34)
            clip: true
            currentIndex: 0
            interactive: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.watchlist

            delegate: Item {
              required property string modelData
              required property int index
              width: watchlistView.width
              height: Style.space(34)

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: index === watchlistView.currentIndex
                  ? Style.hoverFillFor(root.fg, Color.accent)
                  : "transparent"
              }

              Text {
                id: symText
                text: modelData
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                text: {
                  var c = root.watchlistQuotes[modelData]
                  if (!c) return ""
                  var ch = c.price - c.previousClose
                  var pct = c.previousClose ? (ch / c.previousClose) * 100 : 0
                  return Model.fmtPrice(c.price) + " (" + Model.fmtPct(pct) + ")"
                }
                color: {
                  var c = root.watchlistQuotes[modelData]
                  return c ? Model.changeColor(c.price - c.previousClose, root.dim) : root.dim
                }
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                anchors.left: symText.right
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
              }

              // Full-row hover highlight + click to select (sits below the ×)
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: watchlistView.currentIndex = index
                onClicked: root.selectTicker(modelData)
              }

              Text {
                text: "\uf00d"
                color: "#ef4444"
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.removeTicker(modelData)
                }
              }
            }
          }

          // Add-symbol affordance (idle state)
          Row {
            visible: !root.addingTicker
            spacing: Style.space(6)

            Text {
              text: "\uf067"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              anchors.verticalCenter: parent.verticalCenter

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.startAddTicker()
              }
            }

            Text {
              text: "add symbol"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              anchors.verticalCenter: parent.verticalCenter

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.startAddTicker()
              }
            }
          }

          // Add-symbol inline input
          Row {
            visible: root.addingTicker
            spacing: Style.space(4)

            TextField {
              id: addField
              width: Style.space(120)
              foreground: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              placeholderText: "SYMBOL"

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.cancelAddTicker()
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.commitAddTicker()
                  event.accepted = true
                }
              }
            }

            Text {
              text: "\uf00c"
              color: "#22c55e"
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              anchors.verticalCenter: parent.verticalCenter

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.commitAddTicker()
              }
            }

            Text {
              text: "\uf00d"
              color: "#ef4444"
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              anchors.verticalCenter: parent.verticalCenter

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.cancelAddTicker()
              }
            }
          }

          Text {
            visible: root.addError !== ""
            text: root.addError
            color: "#ef4444"
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.italic: true
          }

          // Footer
          PanelSeparator { width: parent.width; foreground: root.fg }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "click select \u00b7 x remove \u00b7 a add \u00b7 enter select \u00b7 r refresh"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}

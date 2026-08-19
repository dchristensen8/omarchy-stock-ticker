import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "christensen.stock-ticker"
  clip: true

  readonly property string ticker: setting("ticker", "AAPL")

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  function openWatchlist() {
    if (panelLoader.item && panelLoader.item.showWatchlist) panelLoader.item.showWatchlist()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  visible: panelLoader.item && panelLoader.item.barLabel !== ""
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Component.onCompleted: Qt.callLater(function() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  })

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
      Qt.callLater(function() {
        if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
      })
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: panelLoader.item ? panelLoader.item.barLabel : root.ticker.toUpperCase() + ": ..."
    tooltipText: panelLoader.item ? panelLoader.item.tooltipText : root.ticker
    foreground: panelLoader.item
      ? panelLoader.item.barLabelColor
      : (root.bar ? root.bar.barForeground : Color.foreground)

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else if (b === Qt.RightButton) root.openWatchlist()
      else root.togglePanel()
    }
  }
}

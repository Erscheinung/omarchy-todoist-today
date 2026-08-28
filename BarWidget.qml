import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.erscheinung.todoist-today"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false
  readonly property int taskCount: panelLoader.item ? panelLoader.item.taskCount : 0
  readonly property var barTask: panelLoader.item ? panelLoader.item.barTask : null
  readonly property bool hasError: panelLoader.item ? panelLoader.item.hasError : false

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function refresh() {
    if (panelLoader.item) panelLoader.item.refresh()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: root.moduleName
    function refresh(): void { root.refresh() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  function truncatedTask(text) {
    var value = String(text || "")
    return value.length > 24 ? value.slice(0, 23) + "…" : value
  }

  WidgetButton {
    id: button
    bar: root.bar
    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
    text: "󰄬 " + root.taskCount + (root.barTask ? " · " + root.truncatedTask(root.barTask.content) : "")
    active: root.hasError
    tooltipText: root.hasError
      ? "Todoist could not refresh · middle-click to retry"
      : (root.barTask ? root.barTask.content : root.taskCount + (root.taskCount === 1 ? " task today" : " tasks today"))

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else if (b === Qt.RightButton && root.bar) root.bar.run("xdg-open https://todoist.com/app/today")
      else root.toggle()
    }
  }
}

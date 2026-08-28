import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Todoist.js" as Todoist

Panel {
  id: root
  moduleName: "io.github.erscheinung.todoist-today"
  ipcTarget: "io.github.erscheinung.todoist-today"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property string helperPath: Quickshell.env("HOME")
    + "/.config/omarchy/plugins/" + root.moduleName + "/scripts/todoist"

  property var tasks: []
  property bool loading: false
  property string errorMessage: ""
  property bool savingToken: false
  property date fetchedAt: new Date(0)
  property int selectedIndex: 0
  property int scrollAttempts: 0
  property date now: new Date()

  readonly property int taskCount: tasks.length
  readonly property bool hasError: errorMessage !== ""
  readonly property bool needsToken: errorMessage === "Todoist token is not configured"
  readonly property var allDay: Todoist.allDayTasks(tasks)
  readonly property var bounds: Todoist.calendarBounds(tasks, now.getHours())
  readonly property var timed: Todoist.layout(tasks, bounds.startHour)
  readonly property int hourHeight: Style.space(68)
  readonly property int timelineHeight: (bounds.endHour - bounds.startHour) * hourHeight
  readonly property int hourCount: bounds.endHour - bounds.startHour + 1
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property color accent: bar ? bar.accent : Color.accent
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function open() {
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) root.setCenterHoverRevealSuppressed(true)
      root.scheduleScrollToNow()
    })
    if (tasks.length === 0 || Date.now() - fetchedAt.getTime() > 120000) refresh()
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function closeForPopoutSwitch() {
    root.close()
  }

  onOpenedChanged: {
    if (root.opened) root.scheduleScrollToNow()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function refresh() {
    if (fetchProcess.running || completeProcess.running) return
    root.loading = true
    root.errorMessage = ""
    fetchProcess.command = [root.helperPath, "list"]
    fetchProcess.running = true
  }

  function acceptPayload(raw) {
    try {
      var payload = JSON.parse(String(raw || ""))
      if (payload.error) {
        root.errorMessage = String(payload.error)
        return
      }
      root.tasks = payload.tasks || []
      root.fetchedAt = new Date()
      root.errorMessage = ""
      root.selectedIndex = Math.min(root.selectedIndex, Math.max(0, root.timed.length - 1))
      root.scheduleScrollToNow()
    } catch (e) {
      root.errorMessage = "Todoist returned an unreadable response"
    }
  }

  function completeTask(taskId) {
    if (completeProcess.running || fetchProcess.running) return
    root.loading = true
    root.errorMessage = ""
    completeProcess.command = [root.helperPath, "complete", String(taskId)]
    completeProcess.running = true
  }

  function saveToken() {
    var token = String(tokenField.text || "").trim()
    if (token.length < 20 || setupProcess.running) return
    root.savingToken = true
    root.errorMessage = ""
    setupProcess.command = [Qt.resolvedUrl("scripts/configure-token").toString().replace("file://", "")]
    setupProcess.running = true
  }

  function openTask(url) {
    if (!url) return
    openProcess.command = ["xdg-open", String(url)]
    openProcess.running = true
  }

  function openToday() {
    openTask("https://todoist.com/app/today")
  }

  function scrollToNow() {
    var currentHour = root.now.getHours()
    var target = (currentHour - root.bounds.startHour) * root.hourHeight
    timelineScroll.contentY = Math.max(0, Math.min(target,
                                                   timelineScroll.contentHeight - timelineScroll.height))
  }

  function scheduleScrollToNow() {
    root.scrollAttempts = 0
    scrollTimer.restart()
  }

  function moveSelection(delta) {
    if (root.timed.length === 0) return
    root.selectedIndex = Math.max(0, Math.min(root.timed.length - 1, root.selectedIndex + delta))
    var task = root.timed[root.selectedIndex]
    var target = task.offsetMinutes / 60 * root.hourHeight
    timelineScroll.contentY = Math.max(0, Math.min(target - timelineScroll.height * 0.35,
                                                   timelineScroll.contentHeight - timelineScroll.height))
  }

  function activateSelected() {
    if (root.timed.length > 0) root.openTask(root.timed[root.selectedIndex].url)
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      root.now = date
      root.scheduleScrollToNow()
    }
  }

  Timer {
    id: scrollTimer
    interval: 100
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.scrollToNow()
      root.scrollAttempts++
      if (root.scrollAttempts >= 10) scrollTimer.stop()
    }
  }

  Process {
    id: fetchProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.acceptPayload(text)
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      root.loading = false
      if (code !== 0 && root.errorMessage === "") root.errorMessage = "Could not reach Todoist"
    }
  }

  Process {
    id: completeProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.acceptPayload(text)
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      root.loading = false
      if (code !== 0 && root.errorMessage === "") root.errorMessage = "Could not update Todoist"
    }
  }

  Process { id: openProcess }

  Process {
    id: setupProcess
    stdinEnabled: true
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onStarted: {
      setupProcess.write(tokenField.text + "\n")
      tokenField.text = ""
    }
    onExited: function(code) {
      root.savingToken = false
      if (code === 0) root.refresh()
      else root.errorMessage = "Could not save the Todoist token"
    }
  }

  Timer {
    interval: 5 * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(Style.space(740))
    onOpenChanged: if (open) root.scheduleScrollToNow()

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: tokenField.activeFocus
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveSelection(dy)
      }
      onActivateRequested: root.activateSelected()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "r" || text === "R") root.refresh()
        else if (text === "n" || text === "N") root.scrollToNow()
        else if (text === "o" || text === "O") root.openToday()
      }

      Column {
        anchors.fill: parent
        spacing: Style.space(12)

        Item {
          width: parent.width
          height: Style.space(74)

          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(14)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "󰄬"
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: 42
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(3)

              Text {
                text: "TODAY"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                font.bold: true
                font.letterSpacing: 1.6
              }

              Text {
                text: Qt.formatDate(root.now, "dddd, MMMM d")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }
          }

          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Rectangle {
              width: countText.implicitWidth + Style.space(18)
              height: Style.space(28)
              radius: height / 2
              color: Style.normalFillFor(root.foreground, root.accent, root.urgent)
              border.width: Style.normalBorderWidth
              border.color: Style.normalBorderFor(root.foreground, root.accent, root.urgent)

              Text {
                id: countText
                anchors.centerIn: parent
                text: root.taskCount + (root.taskCount === 1 ? " TASK" : " TASKS")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 0.8
              }
            }

            Rectangle {
              width: Style.space(32)
              height: width
              radius: width / 2
              color: refreshMouse.containsMouse
                ? Style.hoverFillFor(root.foreground, root.accent, root.urgent)
                : "transparent"

              Text {
                anchors.centerIn: parent
                text: root.loading ? "󰔟" : "󰑐"
                color: root.loading ? root.dim : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              MouseArea {
                id: refreshMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.refresh()
              }
            }
          }
        }

        Rectangle {
          visible: root.hasError
          width: parent.width
          height: errorContent.implicitHeight + Style.space(18)
          radius: Style.cornerRadius
          color: Style.normalFillFor(root.urgent, root.urgent, root.urgent)
          border.width: Style.normalBorderWidth
          border.color: root.urgent

          Column {
            id: errorContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.space(10)
            spacing: Style.space(8)

            Row {
              width: parent.width
              spacing: Style.space(8)

              Text {
                text: root.needsToken ? "󰌆" : "󰅚"
                color: root.needsToken ? root.accent : root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Text {
                width: parent.width - Style.space(28)
                text: root.needsToken ? "CONNECT TODOIST" : root.errorMessage
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: root.needsToken
                font.letterSpacing: root.needsToken ? 0.8 : 0
                wrapMode: Text.Wrap
              }
            }

            Text {
              visible: root.needsToken
              width: parent.width
              text: "Paste your personal API token. It stays on this computer."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
            }

            Row {
              visible: root.needsToken
              width: parent.width
              spacing: Style.space(8)

              TextField {
                id: tokenField
                width: parent.width - connectButton.width - parent.spacing
                enabled: !root.savingToken
                password: true
                placeholderText: "Todoist API token"
                foreground: root.foreground
                accent: root.accent
                font.family: root.fontFamily
                onAccepted: root.saveToken()
              }

              Button {
                id: connectButton
                text: root.savingToken ? "CONNECTING…" : "CONNECT"
                enabled: !root.savingToken && tokenField.text.trim().length >= 20
                bordered: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: root.saveToken()
              }
            }
          }
        }

        Column {
          visible: root.allDay.length > 0
          width: parent.width
          spacing: Style.space(6)

          Text {
            text: "NO TIME"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
          }

          Repeater {
            model: root.allDay

            Rectangle {
              required property var modelData
              width: parent.width
              height: Style.space(38)
              radius: Style.cornerRadius
              color: allDayMouse.containsMouse
                ? Style.hoverFillFor(root.foreground, root.accent, root.urgent)
                : Style.normalFillFor(root.foreground, root.accent, root.urgent)

              Rectangle {
                width: Style.space(3)
                height: parent.height
                color: Todoist.priorityColor(modelData.priority,
                                               Todoist.projectColor(modelData.project_color, root.accent),
                                               root.urgent)
              }

              Rectangle {
                id: allDayCheck
                anchors.left: parent.left
                anchors.leftMargin: Style.space(13)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(16)
                height: width
                radius: width / 2
                color: "transparent"
                border.width: Style.space(1)
                border.color: root.dim

                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -Style.space(6)
                  cursorShape: Qt.PointingHandCursor
                  onClicked: function(mouse) {
                    mouse.accepted = true
                    root.completeTask(modelData.id)
                  }
                }
              }

              Text {
                anchors.left: allDayCheck.right
                anchors.leftMargin: Style.space(10)
                anchors.right: projectLabel.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.content
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              Text {
                id: projectLabel
                anchors.right: parent.right
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.project || "Inbox"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                id: allDayMouse
                anchors.fill: parent
                z: -1
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openTask(modelData.url)
              }
            }
          }
        }

        Rectangle {
          visible: root.allDay.length > 0
          width: parent.width
          height: Style.space(1)
          color: Style.normalBorderFor(root.foreground, root.accent, root.urgent)
        }

        Item {
          width: parent.width
          height: Math.max(Style.space(260), parent.height - y)

          Text {
            visible: !root.loading && !root.hasError && root.taskCount === 0
            anchors.centerIn: parent
            text: "A clear day\nNothing due today"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            horizontalAlignment: Text.AlignHCenter
            lineHeight: 1.35
          }

          Flickable {
            id: timelineScroll
            visible: root.timed.length > 0
            anchors.fill: parent
            contentWidth: width
            // Leave enough trailing room for the final displayed hour to sit at
            // the top. Without it, Flickable clamps late-day scroll requests.
            contentHeight: root.timelineHeight + Math.max(Style.space(20), height - root.hourHeight)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            onContentHeightChanged: root.scheduleScrollToNow()
            onHeightChanged: root.scheduleScrollToNow()

            Item {
              id: timeline
              width: timelineScroll.width
              height: root.timelineHeight

              Repeater {
                model: root.hourCount

                Item {
                  required property int index
                  readonly property int hour: root.bounds.startHour + index
                  y: index * root.hourHeight
                  width: timeline.width
                  height: Style.space(20)

                  Text {
                    width: Style.space(52)
                    text: String(parent.hour % 24).padStart(2, "0") + ":00"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(58)
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: Style.space(7)
                    height: Style.space(1)
                    color: Style.normalBorderFor(root.foreground, root.accent, root.urgent)
                  }
                }
              }

              Repeater {
                model: root.timed

                Rectangle {
                  required property var modelData
                  required property int index
                  readonly property real laneWidth: (timeline.width - Style.space(68)) / modelData.laneCount
                  x: Style.space(62) + modelData.lane * laneWidth
                  y: modelData.offsetMinutes / 60 * root.hourHeight + Style.space(2)
                  width: laneWidth - Style.space(4)
                  height: Math.max(Style.space(34), modelData.durationMinutes / 60 * root.hourHeight - Style.space(3))
                  radius: Style.cornerRadius
                  color: index === root.selectedIndex || cardMouse.containsMouse
                    ? Style.hoverFillFor(root.foreground, root.accent, root.urgent)
                    : Style.normalFillFor(root.foreground, root.accent, root.urgent)
                  border.width: index === root.selectedIndex ? Style.focusBorderWidth : Style.normalBorderWidth
                  border.color: index === root.selectedIndex
                    ? Style.focusBorderFor(root.foreground, root.accent, root.urgent)
                    : Style.normalBorderFor(root.foreground, root.accent, root.urgent)

                  Rectangle {
                    width: Style.space(4)
                    height: parent.height
                    radius: parent.radius
                    color: Todoist.priorityColor(modelData.priority,
                                                 Todoist.projectColor(modelData.project_color, root.accent),
                                                 root.urgent)
                  }

                  Rectangle {
                    id: timedCheck
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(12)
                    anchors.top: parent.top
                    anchors.topMargin: Style.space(11)
                    width: Style.space(16)
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: Style.space(1)
                    border.color: root.dim

                    MouseArea {
                      anchors.fill: parent
                      anchors.margins: -Style.space(6)
                      cursorShape: Qt.PointingHandCursor
                      onClicked: function(mouse) {
                        mouse.accepted = true
                        root.completeTask(modelData.id)
                      }
                    }
                  }

                  Column {
                    anchors.left: timedCheck.right
                    anchors.leftMargin: Style.space(9)
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(9)
                    anchors.top: parent.top
                    anchors.topMargin: Style.space(7)
                    spacing: Style.space(2)

                    Text {
                      width: parent.width
                      text: modelData.content
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                      elide: Text.ElideRight
                    }

                    Text {
                      width: parent.width
                      text: modelData.timeText + "–" + modelData.endTimeText + "  ·  " + (modelData.project || "Inbox")
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  MouseArea {
                    id: cardMouse
                    anchors.fill: parent
                    z: -1
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      root.selectedIndex = index
                      root.openTask(modelData.url)
                    }
                  }
                }
              }

              Item {
                visible: {
                  var minute = root.now.getHours() * 60 + root.now.getMinutes()
                  return minute >= root.bounds.startHour * 60 && minute <= root.bounds.endHour * 60
                }
                y: (root.now.getHours() * 60 + root.now.getMinutes() - root.bounds.startHour * 60)
                   / 60 * root.hourHeight
                x: Style.space(50)
                width: timeline.width - x
                height: Style.space(8)

                Rectangle {
                  x: 0
                  y: -height / 2
                  width: Style.space(8)
                  height: width
                  radius: width / 2
                  color: root.urgent
                }
                Rectangle {
                  x: Style.space(7)
                  width: parent.width - x
                  height: Style.space(1)
                  color: root.urgent
                }
              }
            }
          }
        }

        Item {
          width: parent.width
          height: Style.space(22)

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.loading ? "SYNCING…" : (root.fetchedAt.getTime() > 0 ? "UPDATED " + Qt.formatTime(root.fetchedAt, "HH:mm") : "")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 0.7
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "R REFRESH  ·  N NOW  ·  O OPEN"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 0.7
          }
        }
      }
    }
  }
}

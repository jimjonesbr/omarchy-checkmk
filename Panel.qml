import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "jimjonesbr.checkmk"
  manageIpc: false

  property var anchorItem: null
  // The BarWidget that owns the data. The bar identifies popouts by that widget.
  property var hostWidget: null

  // "hosts", "problems", "host" (the services of currentHost) or "setup"
  property string view: "hosts"
  property string viewBeforeSetup: "hosts"
  property string currentHost: ""
  property bool showAll: false
  property int cursor: 0
  // Expanded service row, shows full output and metrics
  property string expanded: ""

  readonly property var status: hostWidget ? hostWidget.status : null
  readonly property var services: status ? status.services : []
  readonly property var hosts: status && status.hosts ? status.hosts : []
  readonly property var hostInfo: Model.findHost(hosts, currentHost)
  readonly property bool hostRows: view === "hosts"
  readonly property bool unconfigured: !!status && status.unconfigured === true
  readonly property var rows: view === "setup" ? []
    : view === "hosts" ? hosts
    : view === "host" ? Model.hostServices(services, currentHost)
    : (showAll ? services : Model.problems(services, true))
  readonly property int now: hostWidget ? hostWidget.now : 0
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function colorFor(state) { return Model.stateColor(state, fg, urgent) }
  // In the host list OK is green, like in Checkmk
  function hostColorFor(state) { return Model.stateColor(state, fg, urgent, Model.OK_COLOR) }

  function open() {
    cursor = 0
    root.controller.show()
    if (unconfigured) showSetup()
    else if (hostWidget) hostWidget.refresh()
  }

  // ---- Connection setup. The helper keeps the secret in the desktop keyring.
  property var config: ({})
  property bool setupBusy: false
  property bool setupOk: false
  property string setupMessage: ""

  function showSetup() {
    if (view !== "setup") viewBeforeSetup = view
    setupMessage = ""
    setupOk = false
    secretField.text = ""
    setView("setup")
    configGetProc.running = true
    Qt.callLater(function() { urlField.forceActiveFocus() })
  }

  function leaveSetup() {
    setView(viewBeforeSetup === "setup" ? "hosts" : viewBeforeSetup)
    keyCatcher.forceActiveFocus()
  }

  function setupInput() {
    return JSON.stringify({
      url: urlField.text.trim(),
      user: userField.text.trim(),
      secret: secretField.text,
      serviceFilter: serviceFilterField.text.trim(),
      hostFilter: hostFilterField.text.trim(),
      insecure: insecureToggle.checked
    })
  }

  function runSetup(action) {
    if (setupBusy || !hostWidget) return
    setupBusy = true
    setupMessage = action === "save" ? "Saving…" : "Connecting…"
    setupProc.action = action
    setupProc.input = setupInput()
    setupProc.command = [hostWidget.configTool, action]
    setupProc.running = true
  }

  Process {
    id: configGetProc
    command: root.hostWidget ? [root.hostWidget.configTool, "get"] : []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.config = JSON.parse(text) } catch (e) { root.config = {} }
        urlField.text = root.config.url || ""
        userField.text = root.config.user || ""
        serviceFilterField.text = root.config.serviceFilter || ""
        hostFilterField.text = root.config.hostFilter || ""
        insecureToggle.checked = root.config.insecure === true
      }
    }
  }

  // Test or save. The settings, secret included, go over stdin, never argv.
  Process {
    id: setupProc
    property string action: ""
    property string input: ""
    stdinEnabled: true
    onStarted: {
      write(input + "\n")
      input = ""
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var result = null
        try { result = JSON.parse(text) } catch (e) {}
        root.setupBusy = false
        root.setupOk = !!result && result.ok === true
        root.setupMessage = result ? result.message : "The helper script failed"
        if (root.setupOk && setupProc.action === "save") {
          secretField.text = ""
          configGetProc.running = true
          if (root.hostWidget) root.hostWidget.refresh()
          root.leaveSetup()
        }
      }
    }
  }

  // "hosts", "problems" or "host:NAME"
  function show(name) {
    name = String(name || "")
    if (name.indexOf("host:") === 0) openHost(name.slice(5))
    else if (name === "hosts" || name === "problems") setView(name)
    if (!opened) open()
  }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function") return bar.switchPanelFrom(hostWidget || root, direction)
    return false
  }

  function setView(name) {
    if (view === name) return
    view = name
    cursor = 0
    expanded = ""
    scroll.contentY = 0
  }

  function openHost(name) {
    currentHost = name
    setView("host")
  }

  // Back from a host to the host list, keeping that host selected
  function back() {
    if (view !== "host") return
    var name = currentHost
    setView("hosts")
    for (var i = 0; i < hosts.length; i++) if (hosts[i].host === name) cursor = i
    Qt.callLater(ensureVisible)
  }

  function rowKey(row) { return row.host + "\u0000" + row.service }

  function moveCursor(dy) {
    if (rows.length === 0) return
    cursor = Math.max(0, Math.min(rows.length - 1, cursor + dy))
    // Moving the cursor collapses the expanded service, unless it is the one selected
    if (!hostRows && expanded !== rowKey(rows[cursor])) expanded = ""
    ensureVisible()
  }

  function ensureVisible() {
    var item = (hostRows ? hostRepeater : serviceRepeater).itemAt(cursor)
    if (!item) return
    var y = item.mapToItem(column, 0, 0).y
    if (y < scroll.contentY) scroll.contentY = y
    else if (y + item.height > scroll.contentY + scroll.height) scroll.contentY = y + item.height - scroll.height
  }

  function moveSideways(dx) {
    if (dx < 0) {
      if (view === "host") back()
      else setView("hosts")
    } else if (view === "hosts") {
      var row = rows[cursor]
      if (row) openHost(row.host)
    } else if (view === "host") {
      setView("problems")
    }
  }

  // Enter: open a host, expand a service, or open an expanded service in Checkmk
  function activate(index) {
    var row = rows[index]
    if (!row) return
    if (hostRows) {
      openHost(row.host)
    } else if (expanded === rowKey(row)) {
      openInCheckmk(row.link)
    } else {
      expanded = rowKey(row)
      Qt.callLater(ensureVisible)
    }
  }

  function openInCheckmk(url) {
    if (!hostWidget) return
    hostWidget.openWebUi(url)
    close()
  }

  onRowsChanged: {
    cursor = Math.min(cursor, Math.max(0, rows.length - 1))
    // The host disappeared, e.g. after removing it from Checkmk
    if (view === "host" && status && !hostInfo) setView("hosts")
  }

  component FieldLabel: Row {
    property string label: ""
    property string hint: ""
    spacing: Style.space(8)
    topPadding: Style.space(4)
    Text {
      id: labelText
      text: parent.label
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }
    Text {
      anchors.baseline: labelText.baseline
      text: parent.hint
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(680))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCursor(dy)
        else root.moveSideways(dx)
      }
      onActivateRequested: root.activate(root.cursor)
      // The form fields need the keys themselves
      blocked: root.view === "setup"
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "s") root.showSetup()
        else if (t === "1") root.setView("hosts")
        else if (t === "2") root.setView("problems")
        else if (t === "\b") root.back()
        else if (t === "a" && root.view === "problems") { root.showAll = !root.showAll; root.cursor = 0 }
        else if (t === "r" && root.hostWidget) root.hostWidget.refresh()
        else if (t === "o") {
          var row = root.rows[root.cursor]
          root.openInCheckmk(row && row.link ? row.link : "")
        }
      }

      Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: column
          width: scroll.width
          spacing: Style.space(10)

          // ---- Header: title, last update or error
          Item {
            width: parent.width
            height: title.implicitHeight

            Text {
              id: title
              text: "Checkmk"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              id: gear
              anchors.right: parent.right
              anchors.verticalCenter: title.verticalCenter
              text: "\u{f0493}"
              color: root.view === "setup" ? Color.accent : (gearMouse.containsMouse ? root.fg : root.dim)
              font.family: root.fontFamily
              font.pixelSize: Style.font.title

              MouseArea {
                id: gearMouse
                anchors.fill: parent
                anchors.margins: -Style.space(4)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.view === "setup" ? root.leaveSetup() : root.showSetup()
              }
            }

            Text {
              visible: !root.unconfigured
              anchors.right: gear.left
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: title.verticalCenter
              textFormat: Text.PlainText
              text: !root.status ? "waiting for first poll"
                : (root.status.ok ? "" : "unreachable · ") + "updated " + Model.age(root.now - root.status.checked) + " ago"
              color: root.status && !root.status.ok ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Text {
            visible: !!root.status && !root.status.ok && !root.unconfigured && root.view !== "setup"
            width: parent.width
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: root.status ? root.status.error : ""
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          // ---- Counts per state
          Row {
            visible: root.view !== "setup"
            spacing: Style.space(18)
            Repeater {
              model: [
                { state: 2, count: root.status ? root.status.counts.crit : 0 },
                { state: 3, count: root.status ? root.status.counts.unknown : 0 },
                { state: 1, count: root.status ? root.status.counts.warn : 0 },
                { state: 0, count: root.status ? root.status.counts.ok : 0 }
              ]
              Row {
                spacing: Style.space(5)
                opacity: modelData.count > 0 ? 1 : 0.45
                Text {
                  id: countText
                  text: modelData.count
                  color: modelData.count > 0 ? root.colorFor(modelData.state) : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                }
                Text {
                  anchors.baseline: countText.baseline
                  text: Model.stateName(modelData.state)
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          PanelSeparator { foreground: root.fg }

          // ---- Tabs, or the way back from a host
          Row {
            visible: root.view !== "setup"
            spacing: Style.space(16)

            Repeater {
              model: root.view === "host"
                ? [{ id: "back", label: "‹ HOSTS" }, { id: "host", label: root.currentHost.toUpperCase() }]
                : [{ id: "hosts", label: "HOSTS " + root.hosts.length },
                   { id: "problems", label: (root.showAll ? "ALL SERVICES " + root.services.length
                     : "PROBLEMS " + Model.problems(root.services, true).length) }]

              PanelSectionHeader {
                readonly property bool current: modelData.id === root.view
                text: modelData.label
                foreground: root.fg
                fontFamily: root.fontFamily
                color: current ? root.fg : Qt.darker(root.fg, 1.9)

                Rectangle {
                  visible: parent.current && modelData.id !== "host"
                  anchors.top: parent.bottom
                  anchors.topMargin: Style.space(3)
                  width: parent.width
                  height: 2
                  color: Color.accent
                }

                MouseArea {
                  anchors.fill: parent
                  enabled: modelData.id !== "host"
                  cursorShape: Qt.PointingHandCursor
                  onClicked: modelData.id === "back" ? root.back() : root.setView(modelData.id)
                }
              }
            }
          }

          Text {
            visible: root.rows.length === 0 && root.view !== "setup"
            textFormat: Text.PlainText
            text: !root.status ? "No data yet" : root.view === "hosts" ? "No hosts" : "All " + root.services.length + " services OK"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          // ---- Host list: one row per host, coloured by its worst service
          Column {
            visible: root.hostRows
            width: parent.width
            spacing: Style.space(2)

            Repeater {
              id: hostRepeater
              model: root.hostRows ? root.rows : []

              Rectangle {
                id: hostRow
                required property var modelData
                required property int index
                readonly property bool selected: index === root.cursor

                width: parent.width
                height: hostName.implicitHeight + Style.space(14)
                radius: Math.min(6, Style.cornerRadius)
                color: selected || hostMouse.containsMouse ? Style.hoverFillFor(root.fg, Color.accent) : "transparent"

                Rectangle {
                  id: hostDot
                  x: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(10)
                  height: width
                  radius: width / 2
                  color: root.hostColorFor(hostRow.modelData.state)
                }

                Text {
                  id: hostName
                  anchors.left: hostDot.right
                  anchors.leftMargin: Style.space(10)
                  anchors.right: hostCounts.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  elide: Text.ElideRight
                  textFormat: Text.PlainText
                  text: hostRow.modelData.host + (hostRow.modelData.down ? "  DOWN" : "")
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                Row {
                  id: hostCounts
                  anchors.right: chevron.left
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(10)

                  Repeater {
                    model: Model.hostCounts(hostRow.modelData)
                    Text {
                      textFormat: Text.PlainText
                      text: modelData.count + " " + Model.stateName(modelData.state)
                      color: modelData.state === 0 ? root.dim : root.colorFor(modelData.state)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: modelData.state !== 0
                    }
                  }
                }

                Text {
                  id: chevron
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  text: "›"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                }

                MouseArea {
                  id: hostMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openHost(hostRow.modelData.host)
                }
              }
            }
          }

          // ---- Service list: problems, all services, or the services of one host
          Column {
            visible: !root.hostRows
            width: parent.width
            spacing: Style.space(2)

            Repeater {
              id: serviceRepeater
              model: root.hostRows ? [] : root.rows

              Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool selected: index === root.cursor
                readonly property bool isExpanded: root.expanded === root.rowKey(modelData)

                width: parent.width
                height: rowContent.implicitHeight + Style.space(12)
                radius: Math.min(6, Style.cornerRadius)
                color: selected || rowMouse.containsMouse ? Style.hoverFillFor(root.fg, Color.accent) : "transparent"
                opacity: modelData.handled ? 0.55 : 1

                Text {
                  id: stateTag
                  x: Style.space(8)
                  y: Style.space(6)
                  width: Style.space(44)
                  text: Model.stateName(row.modelData.state)
                  color: root.colorFor(row.modelData.state)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }

                MouseArea {
                  id: rowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.cursor = row.index
                    root.expanded = row.isExpanded ? "" : root.rowKey(row.modelData)
                  }
                  onDoubleClicked: root.openInCheckmk(row.modelData.link)
                }

                Column {
                  id: rowContent
                  anchors.left: stateTag.right
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(8)
                  y: Style.space(6)
                  spacing: Style.space(2)

                  Item {
                    width: parent.width
                    height: serviceText.implicitHeight

                    Text {
                      id: serviceText
                      anchors.left: parent.left
                      anchors.right: ageText.left
                      anchors.rightMargin: Style.space(8)
                      elide: Text.ElideRight
                      textFormat: Text.PlainText
                      text: row.modelData.service
                      color: root.fg
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }
                    Text {
                      id: ageText
                      anchors.right: parent.right
                      textFormat: Text.PlainText
                      text: Model.age(root.now - row.modelData.since)
                        + (row.modelData.handled ? " · handled" : "")
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  // The host is obvious inside the host view
                  Text {
                    visible: root.view !== "host"
                    textFormat: Text.PlainText
                    text: row.modelData.host
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    maximumLineCount: row.isExpanded ? 20 : (row.modelData.state === 0 ? 1 : 2)
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: row.isExpanded && row.modelData.details ? row.modelData.details : row.modelData.output
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  // ---- Metrics of the expanded service
                  Column {
                    visible: row.isExpanded && row.modelData.metrics.length > 0
                    width: parent.width
                    topPadding: Style.space(6)
                    spacing: Style.space(3)

                    Repeater {
                      model: row.isExpanded ? row.modelData.metrics : []

                      Item {
                        width: parent.width
                        height: metricName.implicitHeight

                        Text {
                          id: metricName
                          width: parent.width * 0.42
                          elide: Text.ElideRight
                          textFormat: Text.PlainText
                          text: modelData.name
                          color: root.dim
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.bodySmall
                        }
                        Text {
                          x: parent.width * 0.42
                          width: parent.width * 0.22
                          horizontalAlignment: Text.AlignRight
                          textFormat: Text.PlainText
                          text: Model.metricValue(modelData)
                          color: root.fg
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.bodySmall
                          font.bold: true
                        }
                        Text {
                          x: parent.width * 0.68
                          width: parent.width * 0.32
                          elide: Text.ElideRight
                          textFormat: Text.PlainText
                          text: Model.metricLevels(modelData)
                          color: root.dim
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }
                      }
                    }
                  }

                  Text {
                    visible: row.isExpanded
                    topPadding: Style.space(4)
                    text: "open in Checkmk ↗"
                    color: Color.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.openInCheckmk(row.modelData.link)
                    }
                  }
                }
              }
            }
          }

          // ---- Connection setup
          Column {
            visible: root.view === "setup"
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "CHECKMK SERVER"
              foreground: root.fg
              fontFamily: root.fontFamily
            }

            FieldLabel { label: "Site URL"; hint: "everything before /check_mk/" }
            TextField {
              id: urlField
              width: parent.width
              placeholderText: "https://monitoring.example.com/mysite"
              foreground: root.fg
              font.family: root.fontFamily
              KeyNavigation.tab: userField
              Keys.onEscapePressed: root.leaveSetup()
              onAccepted: root.runSetup("test")
            }

            FieldLabel { label: "User"; hint: "an automation user with read-only rights" }
            TextField {
              id: userField
              width: parent.width
              placeholderText: "omarchy"
              foreground: root.fg
              font.family: root.fontFamily
              KeyNavigation.tab: secretField
              Keys.onEscapePressed: root.leaveSetup()
              onAccepted: root.runSetup("test")
            }

            FieldLabel { label: "Password or automation secret"; hint: "" }
            TextField {
              id: secretField
              width: parent.width
              password: true
              placeholderText: root.config.secretStore === "keyring" ? "stored in the keyring, leave empty to keep"
                : root.config.secretStore === "file" || root.config.secretStore === "config" ? "stored in a file, leave empty to keep"
                : ""
              foreground: root.fg
              font.family: root.fontFamily
              KeyNavigation.tab: serviceFilterField
              Keys.onEscapePressed: root.leaveSetup()
              onAccepted: root.runSetup("test")
            }

            FieldLabel { label: "Services"; hint: "regular expression, empty for all" }
            TextField {
              id: serviceFilterField
              width: parent.width
              placeholderText: "e.g. ^PostgreSQL|Memory|CPU"
              foreground: root.fg
              font.family: root.fontFamily
              KeyNavigation.tab: hostFilterField
              Keys.onEscapePressed: root.leaveSetup()
              onAccepted: root.runSetup("test")
            }

            FieldLabel { label: "Hosts"; hint: "regular expression, empty for all" }
            TextField {
              id: hostFilterField
              width: parent.width
              placeholderText: "e.g. ^vm-db"
              foreground: root.fg
              font.family: root.fontFamily
              KeyNavigation.tab: urlField
              Keys.onEscapePressed: root.leaveSetup()
              onAccepted: root.runSetup("test")
            }

            Toggle {
              id: insecureToggle
              width: parent.width
              label: "Accept self-signed certificates"
              description: "Only for servers without a trusted TLS certificate"
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: checked = !checked
            }

            Row {
              spacing: Style.space(8)

              Button {
                text: "Test connection"
                bordered: true
                foreground: root.fg
                fontFamily: root.fontFamily
                onClicked: root.runSetup("test")
              }
              Button {
                text: "Save"
                bordered: true
                foreground: root.fg
                fontFamily: root.fontFamily
                onClicked: root.runSetup("save")
              }
              Button {
                visible: !root.unconfigured
                text: "Cancel"
                foreground: root.fg
                fontFamily: root.fontFamily
                onClicked: root.leaveSetup()
              }
            }

            Text {
              visible: root.setupMessage !== ""
              width: parent.width
              wrapMode: Text.Wrap
              textFormat: Text.PlainText
              text: root.setupMessage
              color: root.setupBusy ? root.dim : (root.setupOk ? Model.OK_COLOR : root.urgent)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              width: parent.width
              wrapMode: Text.Wrap
              textFormat: Text.PlainText
              text: "Tip: in Checkmk create a user under Setup › Users with the role Guest user and the "
                + "authentication option Automation secret. The secret is kept in your desktop keyring."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          PanelSeparator { foreground: root.fg }

          Text {
            width: parent.width
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: root.view === "setup" ? "tab next field · enter test · esc back"
              : root.view === "hosts" ? "enter/l open host · 2 problems · o host in Checkmk · r refresh · s setup"
              : root.view === "host" ? "enter details, again opens Checkmk · h/backspace back · o open in Checkmk"
              : "enter details, again opens Checkmk · a " + (root.showAll ? "problems only" : "all services")
                + " · 1 hosts · r refresh"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}

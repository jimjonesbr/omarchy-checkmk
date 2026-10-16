import QtQuick
import QtQuick.Layouts
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

  // "hosts", "problems", "host" (the services of currentHost), "servers" or "edit"
  property string view: "hosts"
  property string mainView: "hosts"
  property string currentServer: ""
  property string currentHost: ""
  property bool showAll: false
  property int cursor: 0
  // Expanded service row, shows full output and metrics
  property string expanded: ""

  readonly property var status: hostWidget ? hostWidget.status : null
  readonly property var services: status ? status.services : []
  readonly property var hosts: status ? status.hosts : []
  readonly property var polledServers: status ? status.servers : []
  readonly property bool multiServer: polledServers.length > 1
  readonly property var hostInfo: Model.findHost(hosts, currentServer, currentHost)
  readonly property bool unconfigured: !!status && status.unconfigured === true
  readonly property bool settingsView: view === "servers" || view === "edit"
  readonly property var rows: view === "edit" ? []
    : view === "servers" ? Model.serverRows(configured, polledServers)
    : view === "hosts" ? hosts
    : view === "host" ? Model.hostServices(services, currentServer, currentHost)
    : (showAll ? services : Model.problems(services, true))
  readonly property int now: hostWidget ? hostWidget.now : 0
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function colorFor(state) { return Model.stateColor(state, fg, urgent) }
  // In the host and server lists OK is green, like in Checkmk
  function hostColorFor(state) { return Model.stateColor(state, fg, urgent, Model.OK_COLOR) }

  function open() {
    cursor = 0
    root.controller.show()
    if (unconfigured) showEdit("")
    else if (hostWidget) hostWidget.refresh()
  }

  // "hosts", "problems", "servers", "host:NAME", "host:SERVER/NAME" or
  // "service:SERVER/HOST/SERVICE[@RANGE]", which opens the host with that service
  // expanded and, with a range like 4h, its graph
  function show(name) {
    name = String(name || "")
    if (name.indexOf("service:") === 0) {
      // An optional "@4h" etc. also loads the graph of that range
      var range = name.indexOf("@") > 0 ? name.slice(name.lastIndexOf("@") + 1) : ""
      if (range) name = name.slice(0, name.lastIndexOf("@"))
      var parts = name.slice(8).split("/")
      var svc = { server: parts[0], host: parts[1], service: parts.slice(2).join("/") }
      openHost(svc.server, svc.host)
      expanded = rowKey(svc)
      // After the rows of the host view are in place
      Qt.callLater(function() {
        selectWhere(function(r) { return rowKey(r) === rowKey(svc) })
        var row = rows[cursor]
        if (range && row && rowKey(row) === rowKey(svc)) showGraph(row, range)
      })
    } else if (name.indexOf("host:") === 0) {
      var target = name.slice(5)
      var slash = target.indexOf("/")
      var info = slash > 0 ? Model.findHost(hosts, target.slice(0, slash), target.slice(slash + 1))
        : Model.findHost(hosts, "", target)
      if (info) openHost(info.server, info.host)
    } else if (name === "hosts" || name === "problems") {
      setView(name)
    } else if (name === "servers") {
      showServers()
    }
    if (!opened) open()
  }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function") return bar.switchPanelFrom(hostWidget || root, direction)
    return false
  }

  function setView(name) {
    if (view === name) return
    if (name === "hosts" || name === "problems") mainView = name
    view = name
    cursor = 0
    expanded = ""
    confirmDelete = ""
    scroll.contentY = 0
    if (name !== "edit") keyCatcher.forceActiveFocus()
  }

  function openHost(server, host) {
    currentServer = server
    currentHost = host
    setView("host")
  }

  function selectWhere(test) {
    for (var i = 0; i < rows.length; i++) if (test(rows[i])) { cursor = i; break }
    Qt.callLater(ensureVisible)
  }

  // One level up: host -> hosts, servers -> hosts or problems, edit -> servers
  function back() {
    if (view === "host") {
      var server = currentServer, host = currentHost
      setView("hosts")
      selectWhere(function(r) { return r.server === server && r.host === host })
    } else if (view === "servers") {
      setView(mainView)
    } else if (view === "edit") {
      if (unconfigured) return
      var id = editId
      showServers()
      selectWhere(function(r) { return r.id === id })
    }
  }

  function rowKey(row) { return row.server + "\u0000" + row.host + "\u0000" + row.service }

  function repeaterForView() {
    if (view === "hosts") return hostRepeater
    if (view === "servers") return serverRepeater
    return serviceRepeater
  }

  function moveCursor(dy) {
    if (rows.length === 0) return
    cursor = Math.max(0, Math.min(rows.length - 1, cursor + dy))
    confirmDelete = ""
    // Moving the cursor collapses the expanded service, unless it is the one selected
    if (expanded !== "" && expanded !== rowKey(rows[cursor])) expanded = ""
    ensureVisible()
  }

  function ensureVisible() {
    var item = repeaterForView().itemAt(cursor)
    if (!item) return
    var y = item.mapToItem(column, 0, 0).y
    if (y < scroll.contentY) scroll.contentY = y
    else if (y + item.height > scroll.contentY + scroll.height) scroll.contentY = y + item.height - scroll.height
  }

  function moveSideways(dx) {
    if (dx < 0) {
      if (view === "hosts" || view === "problems") setView("hosts")
      else back()
    } else if (view === "hosts" || view === "servers") {
      activate(cursor)
    }
  }

  // Enter: open a host or server, expand a service, or open an expanded service in Checkmk
  function activate(index) {
    var row = rows[index]
    if (!row) return
    if (view === "hosts") {
      openHost(row.server, row.host)
    } else if (view === "servers") {
      showEdit(row.id)
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
    // The host disappeared, e.g. after removing it or its server
    if (view === "host" && status && !hostInfo) setView("hosts")
  }

  // ---- History graphs, fetched only when a range is picked
  readonly property var graphRanges: [
    { id: "4h", seconds: 4 * 3600 },
    { id: "25h", seconds: 25 * 3600 },
    { id: "1w", seconds: 7 * 86400 },
    { id: "1m", seconds: 31 * 86400 }
  ]
  // The graph of the expanded service: {key, range, loading, error, data}
  property var graph: ({ key: "", range: "" })
  // key + range -> {data, at}, so collapsing and reopening a row fetches nothing
  property var graphCache: ({})
  readonly property int graphCacheSeconds: 300

  function showGraph(row, range) {
    var key = rowKey(row)
    // Picking the shown range again hides the graph
    if (graph.key === key && graph.range === range && !graph.loading) {
      graph = { key: "", range: "" }
      return
    }
    var cached = graphCache[key + "\u0000" + range]
    if (cached && Date.now() / 1000 - cached.at < graphCacheSeconds) {
      graph = { key: key, range: range, loading: false, error: "", data: cached.data }
      return
    }
    if (!hostWidget || row.metrics.length === 0) return
    var seconds = 0
    for (var i = 0; i < graphRanges.length; i++) if (graphRanges[i].id === range) seconds = graphRanges[i].seconds
    graph = { key: key, range: range, loading: true, error: "", data: null }
    graphProc.running = false
    graphProc.command = [hostWidget.graphTool, row.server, row.host, row.service, String(seconds)]
      .concat(row.metrics.map(function(m) { return m.name }))
    graphProc.running = true
  }

  // g: no graph -> 4h -> 25h -> 1w -> 1m -> no graph
  function cycleGraph() {
    var row = rows[cursor]
    if (!row || view === "hosts" || settingsView || !row.metrics || row.metrics.length === 0) return
    var key = rowKey(row)
    expanded = key
    var index = graph.key === key ? graphRanges.map(function(r) { return r.id }).indexOf(graph.range) : -1
    if (index === graphRanges.length - 1) graph = { key: "", range: "" }
    else showGraph(row, graphRanges[index + 1].id)
    Qt.callLater(ensureVisible)
  }

  Process {
    id: graphProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var result = null
        try { result = JSON.parse(text) } catch (e) {}
        var current = root.graph
        if (!current.loading) return
        if (!result || !result.ok) {
          root.graph = { key: current.key, range: current.range, loading: false,
            error: result ? result.error : "Could not load the history", data: null }
          return
        }
        var cache = Object.assign({}, root.graphCache)
        cache[current.key + "\u0000" + current.range] = { data: result, at: Date.now() / 1000 }
        root.graphCache = cache
        root.graph = { key: current.key, range: current.range, loading: false, error: "", data: result }
      }
    }
  }

  // ---- Servers. The helper keeps the secrets in the desktop keyring.
  property var configured: []
  property string editId: ""
  property string confirmDelete: ""
  property bool setupBusy: false
  property bool setupOk: false
  property string setupMessage: ""
  readonly property var editServer: {
    for (var i = 0; i < configured.length; i++) if (configured[i].id === editId) return configured[i]
    return null
  }

  function showServers() {
    setView("servers")
    listProc.running = true
  }

  // An empty id adds a server
  function showEdit(id) {
    editId = id
    setupMessage = ""
    setupOk = false
    confirmDelete = ""
    var s = null
    for (var i = 0; i < configured.length; i++) if (configured[i].id === id) s = configured[i]
    nameField.text = s ? s.name : ""
    urlField.text = s ? s.url : ""
    userField.text = s ? s.user : ""
    secretField.text = ""
    serviceFilterField.text = s ? (s.serviceFilter || "") : ""
    hostFilterField.text = s ? (s.hostFilter || "") : ""
    insecureToggle.checked = !!s && s.insecure === true
    setView("edit")
    Qt.callLater(function() { (id ? nameField : urlField).forceActiveFocus() })
  }

  function setupInput() {
    return JSON.stringify({
      id: editId,
      name: nameField.text.trim(),
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

  // A first request arms the deletion, the second one carries it out
  function requestDelete(id) {
    if (!id || deleteProc.running || !hostWidget) return
    if (confirmDelete !== id) {
      confirmDelete = id
      return
    }
    confirmDelete = ""
    deleteProc.command = [hostWidget.configTool, "delete", id]
    deleteProc.running = true
  }

  function configChanged() {
    listProc.running = true
    if (hostWidget) hostWidget.refresh()
  }

  Process {
    id: listProc
    command: root.hostWidget ? [root.hostWidget.configTool, "list"] : []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.configured = JSON.parse(text) } catch (e) { root.configured = [] }
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
          root.editId = result.id
          secretField.text = ""
          root.configChanged()
          root.showServers()
          Qt.callLater(function() { root.selectWhere(function(r) { return r.id === result.id }) })
        }
      }
    }
  }

  Process {
    id: deleteProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.configChanged()
        if (root.view === "edit") root.showServers()
      }
    }
  }

  Component.onCompleted: listProc.running = true

  // History of one metric: legend, area chart with warn/crit lines, time axis.
  // Hovering shows the value at that time.
  component MetricGraph: Column {
    id: metricGraph
    property var curve: null
    property var metric: null
    property int hoverIndex: -1

    readonly property var points: curve && curve.points ? curve.points : []
    readonly property var values: points.filter(function(v) { return v !== null })
    readonly property string unit: metric ? Model.metricUnit(metric) : ""
    readonly property real dataMax: values.length ? Math.max.apply(null, values) : 0
    readonly property real dataMin: values.length ? Math.min.apply(null, values) : 0
    readonly property real warn: metric ? parseFloat(metric.warn) : NaN
    readonly property real crit: metric ? parseFloat(metric.crit) : NaN
    readonly property real yMin: Math.min(0, dataMin)
    // Percentages up to 100, else a little headroom; levels count when they are near the data
    readonly property real yMax: {
      var top = dataMax
      if (unit === "%" && dataMax <= 100) top = 100
      ;[warn, crit].forEach(function(level) { if (!isNaN(level) && level <= dataMax * 1.5) top = Math.max(top, level) })
      top = top * (unit === "%" && top === 100 ? 1 : 1.1)
      return top > yMin ? top : yMin + 1
    }

    function format(value) { return value === null || value === undefined ? "–" : Model.formatValue(value, unit) }
    function timeAt(index) {
      var t = new Date((curve.start + index * curve.step) * 1000)
      return Qt.formatDateTime(t, curve.end - curve.start > 26 * 3600 ? "ddd d MMM HH:mm" : "HH:mm")
    }

    spacing: Style.space(4)

    Item {
      width: parent.width
      height: graphTitle.implicitHeight

      Text {
        id: graphTitle
        anchors.left: parent.left
        anchors.right: graphLegend.left
        anchors.rightMargin: Style.space(8)
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: metricGraph.metric ? Model.metricLabel(metricGraph.metric) : (metricGraph.curve ? metricGraph.curve.metric : "")
        color: root.fg
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
      Text {
        id: graphLegend
        anchors.right: parent.right
        textFormat: Text.PlainText
        text: metricGraph.curve && metricGraph.curve.error ? "no history"
          : metricGraph.hoverIndex >= 0
            ? metricGraph.timeAt(metricGraph.hoverIndex) + "  " + metricGraph.format(metricGraph.points[metricGraph.hoverIndex])
            : "min " + metricGraph.format(metricGraph.dataMin) + " · max " + metricGraph.format(metricGraph.dataMax)
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Canvas {
      id: canvas
      width: parent.width
      height: Style.space(64)
      visible: metricGraph.values.length > 0

      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var pts = metricGraph.points, n = pts.length
        if (n < 2) return
        var w = width, h = height, lo = metricGraph.yMin, hi = metricGraph.yMax
        function x(i) { return i / (n - 1) * w }
        function y(v) { return h - (v - lo) / (hi - lo) * (h - 2) - 1 }

        // Area and line, broken where Checkmk has no data
        var line = Color.accent
        ctx.lineWidth = 1.5
        ctx.strokeStyle = line
        ctx.fillStyle = Qt.rgba(line.r, line.g, line.b, 0.18)
        var i = 0
        while (i < n) {
          while (i < n && pts[i] === null) i++
          if (i >= n) break
          var first = i
          ctx.beginPath()
          ctx.moveTo(x(i), y(pts[i]))
          while (i < n && pts[i] !== null) { ctx.lineTo(x(i), y(pts[i])); i++ }
          var last = i - 1
          ctx.stroke()
          ctx.lineTo(x(last), h)
          ctx.lineTo(x(first), h)
          ctx.closePath()
          ctx.fill()
        }

        // Levels as dashed lines
        function level(value, color) {
          if (isNaN(value) || value < lo || value > hi) return
          ctx.save()
          ctx.setLineDash([4, 3])
          ctx.lineWidth = 1
          ctx.strokeStyle = color
          ctx.beginPath()
          ctx.moveTo(0, y(value))
          ctx.lineTo(w, y(value))
          ctx.stroke()
          ctx.restore()
        }
        level(metricGraph.warn, root.colorFor(1))
        level(metricGraph.crit, root.colorFor(2))

        // Hover marker
        if (metricGraph.hoverIndex >= 0) {
          ctx.strokeStyle = Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.5)
          ctx.lineWidth = 1
          ctx.beginPath()
          ctx.moveTo(x(metricGraph.hoverIndex), 0)
          ctx.lineTo(x(metricGraph.hoverIndex), h)
          ctx.stroke()
        }
      }

      // The baseline, also when everything is zero
      Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: root.fg
        opacity: 0.15
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: function(mouse) {
          var n = metricGraph.points.length
          metricGraph.hoverIndex = n > 1 ? Math.max(0, Math.min(n - 1, Math.round(mouse.x / width * (n - 1)))) : -1
        }
        onExited: metricGraph.hoverIndex = -1
      }

      Connections {
        target: metricGraph
        function onHoverIndexChanged() { canvas.requestPaint() }
        function onCurveChanged() { canvas.requestPaint() }
      }
      onWidthChanged: requestPaint()
    }

    Item {
      visible: canvas.visible
      width: parent.width
      height: startLabel.implicitHeight

      Text {
        id: startLabel
        text: metricGraph.curve ? metricGraph.timeAt(0) : ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
      Text {
        anchors.right: parent.right
        text: "now"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
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
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(700))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // The form fields need the keys themselves
      blocked: root.view === "edit"
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCursor(dy)
        else root.moveSideways(dx)
      }
      onActivateRequested: root.activate(root.cursor)
      onCloseRequested: root.close()
      onDeleteRequested: if (root.view === "servers" && root.rows[root.cursor]) root.requestDelete(root.rows[root.cursor].id)
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "s") root.view === "servers" ? root.back() : root.showServers()
        else if (t === "n" && root.view === "servers") root.showEdit("")
        else if (t === "g") root.cycleGraph()
        else if (t === "1") root.setView("hosts")
        else if (t === "2") root.setView("problems")
        else if (t === "\b") root.back()
        else if (t === "a" && root.view === "problems") { root.showAll = !root.showAll; root.cursor = 0 }
        else if (t === "r" && root.hostWidget) root.hostWidget.refresh()
        else if (t === "o" && !root.settingsView) {
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

          // ---- Header: title, last update, settings
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
              color: root.settingsView ? Color.accent : (gearMouse.containsMouse ? root.fg : root.dim)
              font.family: root.fontFamily
              font.pixelSize: Style.font.title

              MouseArea {
                id: gearMouse
                anchors.fill: parent
                anchors.margins: -Style.space(4)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.settingsView ? root.setView(root.mainView) : root.showServers()
              }
            }

            Text {
              visible: !root.unconfigured
              anchors.right: gear.left
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: title.verticalCenter
              textFormat: Text.PlainText
              text: !root.status ? "waiting for first poll" : "updated " + Model.age(root.now - root.status.checked) + " ago"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          // ---- Servers that did not answer, their data is the last known
          Repeater {
            model: root.settingsView ? [] : root.polledServers.filter(function(s) { return !s.ok })
            Text {
              width: column.width
              wrapMode: Text.Wrap
              textFormat: Text.PlainText
              text: (root.multiServer ? modelData.name + " unreachable: " : "Unreachable: ") + modelData.error
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          // ---- Counts per state
          Row {
            visible: !root.settingsView
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

          // ---- Tabs, or the way back
          Row {
            spacing: Style.space(16)

            Repeater {
              model: root.view === "host"
                ? [{ id: "back", label: "‹ HOSTS" },
                   { id: "title", label: root.currentHost.toUpperCase()
                     + (root.multiServer && root.hostInfo ? " · " + root.hostInfo.serverName.toUpperCase() : "") }]
                : root.view === "servers"
                ? [{ id: "back", label: "‹ BACK" }, { id: "title", label: "SERVERS " + root.configured.length }]
                : root.view === "edit"
                ? (root.unconfigured ? [{ id: "title", label: "ADD A CHECKMK SERVER" }]
                   : [{ id: "back", label: "‹ SERVERS" },
                      { id: "title", label: root.editServer ? root.editServer.name.toUpperCase() : "NEW SERVER" }])
                : [{ id: "hosts", label: "HOSTS " + root.hosts.length },
                   { id: "problems", label: (root.showAll ? "ALL SERVICES " + root.services.length
                     : "PROBLEMS " + Model.problems(root.services, true).length) }]

              PanelSectionHeader {
                readonly property bool current: modelData.id === root.view || modelData.id === "title"
                text: modelData.label
                foreground: root.fg
                fontFamily: root.fontFamily
                color: current ? root.fg : Qt.darker(root.fg, 1.9)

                Rectangle {
                  visible: modelData.id === root.view
                  anchors.top: parent.bottom
                  anchors.topMargin: Style.space(3)
                  width: parent.width
                  height: 2
                  color: Color.accent
                }

                MouseArea {
                  anchors.fill: parent
                  enabled: modelData.id !== "title"
                  cursorShape: Qt.PointingHandCursor
                  onClicked: modelData.id === "back" ? root.back() : root.setView(modelData.id)
                }
              }
            }
          }

          Text {
            visible: root.rows.length === 0 && !root.settingsView
            textFormat: Text.PlainText
            text: !root.status ? "No data yet" : root.view === "hosts" ? "No hosts" : "All " + root.services.length + " services OK"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          // ---- Host list: one row per host, coloured by its worst service, grouped by server
          Column {
            visible: root.view === "hosts"
            width: parent.width
            spacing: Style.space(2)

            Repeater {
              id: hostRepeater
              model: root.view === "hosts" ? root.rows : []

              Column {
                id: hostEntry
                required property var modelData
                required property int index
                readonly property bool firstOfServer: index === 0 || root.rows[index - 1].server !== modelData.server
                readonly property var serverInfo: {
                  for (var i = 0; i < root.polledServers.length; i++)
                    if (root.polledServers[i].id === modelData.server) return root.polledServers[i]
                  return null
                }
                width: parent.width

                // Server heading, only with more than one server
                Row {
                  visible: root.multiServer && hostEntry.firstOfServer
                  spacing: Style.space(8)
                  topPadding: hostEntry.index === 0 ? 0 : Style.space(10)
                  bottomPadding: Style.space(4)

                  Text {
                    id: serverHeading
                    textFormat: Text.PlainText
                    text: hostEntry.modelData.serverName.toUpperCase()
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1
                  }
                  Text {
                    anchors.baseline: serverHeading.baseline
                    visible: !!hostEntry.serverInfo && !hostEntry.serverInfo.ok
                    textFormat: Text.PlainText
                    text: "unreachable, last known state"
                    color: root.urgent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Rectangle {
                  id: hostRow
                  readonly property bool selected: hostEntry.index === root.cursor
                  width: parent.width
                  height: hostName.implicitHeight + Style.space(14)
                  radius: Math.min(6, Style.cornerRadius)
                  color: selected || hostMouse.containsMouse ? Style.hoverFillFor(root.fg, Color.accent) : "transparent"
                  opacity: hostEntry.modelData.stale ? 0.6 : 1

                  Rectangle {
                    id: hostDot
                    x: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(10)
                    height: width
                    radius: width / 2
                    color: root.hostColorFor(hostEntry.modelData.state)
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
                    text: hostEntry.modelData.host + (hostEntry.modelData.down ? "  DOWN" : "")
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
                      model: Model.hostCounts(hostEntry.modelData)
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
                    onClicked: root.openHost(hostEntry.modelData.server, hostEntry.modelData.host)
                  }
                }
              }
            }
          }

          // ---- Service list: problems, all services, or the services of one host
          Column {
            visible: root.view === "problems" || root.view === "host"
            width: parent.width
            spacing: Style.space(2)

            Repeater {
              id: serviceRepeater
              model: root.view === "problems" || root.view === "host" ? root.rows : []

              Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool selected: index === root.cursor
                readonly property string rowKey: root.rowKey(modelData)
                readonly property bool isExpanded: root.expanded === rowKey
                readonly property bool hasGraph: isExpanded && root.graph.key === rowKey

                width: parent.width
                height: rowContent.implicitHeight + Style.space(12)
                radius: Math.min(6, Style.cornerRadius)
                // An expanded row keeps the plain background, so its metrics read like
                // the network panel's details; an accent bar marks it instead
                color: !isExpanded && (selected || rowMouse.containsMouse) ? Style.hoverFillFor(root.fg, Color.accent) : "transparent"
                opacity: modelData.handled || modelData.stale ? 0.55 : 1

                Rectangle {
                  visible: row.isExpanded
                  width: 2
                  height: parent.height
                  radius: 1
                  color: Color.accent
                }

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
                        + (row.modelData.stale ? " · stale" : "")
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  // The host is obvious inside the host view
                  Text {
                    visible: root.view !== "host"
                    textFormat: Text.PlainText
                    text: row.modelData.host + (root.multiServer ? " · " + row.modelData.serverName : "")
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
                    text: row.isExpanded ? Model.detailsText(row.modelData) : row.modelData.output
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  // ---- Metrics of the expanded service, laid out like the network panel's details
                  Item {
                    visible: metricsGrid.visible
                    width: 1
                    height: Style.space(4)
                  }

                  GridLayout {
                    id: metricsGrid
                    visible: row.isExpanded && row.modelData.metrics.length > 0
                    width: parent.width
                    columns: row.modelData.metrics.length > 1 ? 4 : 2
                    columnSpacing: Style.space(16)
                    rowSpacing: Style.spacing.labelGap

                    // Two cells per metric: label, value
                    Repeater {
                      model: row.isExpanded
                        ? [].concat.apply([], row.modelData.metrics.map(function(m) {
                            return [{ value: false, metric: m }, { value: true, metric: m }]
                          }))
                        : []

                      Text {
                        id: metricCell
                        readonly property int level: Model.metricState(modelData.metric)
                        readonly property string levels: Model.metricLevels(modelData.metric)

                        Layout.fillWidth: modelData.value
                        horizontalAlignment: modelData.value ? Text.AlignRight : Text.AlignLeft
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        text: modelData.value ? Model.metricValue(modelData.metric) : Model.metricLabel(modelData.metric)
                        color: modelData.value && level > 0 ? root.colorFor(level) : root.fg
                        opacity: modelData.value ? 1 : 0.6
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.bold: modelData.value && level > 0

                        HoverHandler {
                          id: metricHover
                          enabled: modelData.value && metricCell.levels !== ""
                        }

                        PanelToolTip {
                          visible: metricHover.hovered
                          text: metricCell.levels
                          fontFamily: root.fontFamily
                        }
                      }
                    }
                  }

                  // ---- History: range pills, then one graph per metric
                  Row {
                    visible: row.isExpanded && row.modelData.metrics.length > 0 && !row.modelData.stale
                    topPadding: Style.space(8)
                    spacing: Style.space(6)

                    Text {
                      anchors.verticalCenter: rangePills.verticalCenter
                      anchors.verticalCenterOffset: Style.space(4)
                      text: "History"
                      color: root.fg
                      opacity: 0.6
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      rightPadding: Style.space(4)
                    }

                    Row {
                      id: rangePills
                      spacing: Style.space(6)

                      Repeater {
                        model: root.graphRanges
                        Button {
                          text: modelData.id
                          selected: root.graph.key === row.rowKey && root.graph.range === modelData.id
                          bordered: true
                          foreground: root.fg
                          fontFamily: root.fontFamily
                          fontSize: Style.font.caption
                          verticalPadding: Style.space(2)
                          horizontalPadding: Style.space(8)
                          onClicked: root.showGraph(row.modelData, modelData.id)
                        }
                      }
                    }
                  }

                  Text {
                    visible: row.hasGraph && (root.graph.loading || root.graph.error !== "")
                    width: parent.width
                    topPadding: Style.space(6)
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    text: root.graph.loading ? "Loading…" : root.graph.error
                    color: root.graph.loading ? root.dim : root.urgent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Column {
                    visible: row.hasGraph && !!root.graph.data
                    width: parent.width
                    topPadding: Style.space(8)
                    spacing: Style.space(12)

                    Repeater {
                      model: row.hasGraph && root.graph.data ? root.graph.data.curves : []

                      MetricGraph {
                        width: parent.width
                        curve: modelData
                        metric: row.modelData.metrics.filter(function(m) { return m.name === modelData.metric })[0] || null
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

          // ---- Server list
          Column {
            visible: root.view === "servers"
            width: parent.width
            spacing: Style.space(2)

            Repeater {
              id: serverRepeater
              model: root.view === "servers" ? root.rows : []

              Rectangle {
                id: serverRow
                required property var modelData
                required property int index
                readonly property bool selected: index === root.cursor
                readonly property bool confirming: root.confirmDelete === modelData.id

                width: parent.width
                height: serverContent.implicitHeight + Style.space(14)
                radius: Math.min(6, Style.cornerRadius)
                color: selected || serverMouse.containsMouse ? Style.hoverFillFor(root.fg, Color.accent) : "transparent"

                MouseArea {
                  id: serverMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.showEdit(serverRow.modelData.id)
                }

                Rectangle {
                  id: serverDot
                  x: Style.space(10)
                  y: Style.space(7) + (serverName.implicitHeight - height) / 2
                  width: Style.space(10)
                  height: width
                  radius: width / 2
                  color: !serverRow.modelData.polled ? root.dim
                    : serverRow.modelData.ok ? Model.OK_COLOR : root.urgent
                }

                Column {
                  id: serverContent
                  anchors.left: serverDot.right
                  anchors.leftMargin: Style.space(10)
                  anchors.right: serverActions.left
                  anchors.rightMargin: Style.space(10)
                  y: Style.space(7)
                  spacing: Style.space(2)

                  Text {
                    id: serverName
                    width: parent.width
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: serverRow.modelData.name
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
                  Text {
                    width: parent.width
                    elide: Text.ElideMiddle
                    textFormat: Text.PlainText
                    text: serverRow.modelData.user + " @ " + serverRow.modelData.url
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                  Text {
                    visible: serverRow.modelData.polled && !serverRow.modelData.ok
                    width: parent.width
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    text: serverRow.modelData.error
                    color: root.urgent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }

                Row {
                  id: serverActions
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(10)
                  y: Style.space(7)
                  spacing: Style.space(12)

                  Text {
                    textFormat: Text.PlainText
                    text: !serverRow.modelData.polled ? "not polled yet"
                      : serverRow.modelData.hosts + (serverRow.modelData.hosts === 1 ? " host" : " hosts")
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                  Text {
                    visible: serverRow.selected || serverRow.confirming
                    text: serverRow.confirming ? "remove? x again" : "remove"
                    color: serverRow.confirming ? root.urgent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall

                    MouseArea {
                      anchors.fill: parent
                      anchors.margins: -Style.space(4)
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.requestDelete(serverRow.modelData.id)
                    }
                  }
                }
              }
            }

            Button {
              text: "+ Add server"
              bordered: true
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: root.showEdit("")
            }
          }

          // ---- Add or edit a server
          Column {
            visible: root.view === "edit"
            width: parent.width
            spacing: Style.space(8)

            FieldLabel { label: "Name"; hint: "shown in the panel, e.g. Production" }
            TextField {
              id: nameField
              width: parent.width
              placeholderText: "defaults to the host name of the URL"
              foreground: root.fg
              font.family: root.fontFamily
              KeyNavigation.tab: urlField
              Keys.onEscapePressed: root.back()
              onAccepted: root.runSetup("test")
            }

            FieldLabel { label: "Site URL"; hint: "everything before /check_mk/" }
            TextField {
              id: urlField
              width: parent.width
              placeholderText: "https://monitoring.example.com/mysite"
              foreground: root.fg
              font.family: root.fontFamily
              KeyNavigation.tab: userField
              Keys.onEscapePressed: root.back()
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
              Keys.onEscapePressed: root.back()
              onAccepted: root.runSetup("test")
            }

            FieldLabel { label: "Password or automation secret"; hint: "" }
            TextField {
              id: secretField
              width: parent.width
              password: true
              placeholderText: !root.editServer ? ""
                : root.editServer.secretStore === "keyring" ? "stored in the keyring, leave empty to keep"
                : root.editServer.secretStore === "file" ? "stored in a file, leave empty to keep"
                : ""
              foreground: root.fg
              font.family: root.fontFamily
              KeyNavigation.tab: serviceFilterField
              Keys.onEscapePressed: root.back()
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
              Keys.onEscapePressed: root.back()
              onAccepted: root.runSetup("test")
            }

            FieldLabel { label: "Hosts"; hint: "regular expression, empty for all" }
            TextField {
              id: hostFilterField
              width: parent.width
              placeholderText: "e.g. ^vm-db"
              foreground: root.fg
              font.family: root.fontFamily
              KeyNavigation.tab: nameField
              Keys.onEscapePressed: root.back()
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

            Item {
              width: parent.width
              height: formButtons.implicitHeight

              Row {
                id: formButtons
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
                  onClicked: root.back()
                }
              }

              Button {
                visible: !!root.editServer
                anchors.right: parent.right
                text: root.confirmDelete === root.editId ? "Really remove?" : "Remove"
                foreground: root.confirmDelete === root.editId ? root.urgent : root.dim
                fontFamily: root.fontFamily
                onClicked: root.requestDelete(root.editId)
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
            text: root.view === "edit" ? "tab next field · enter test · esc back"
              : root.view === "servers" ? "enter edit · n add · x remove · h back"
              : root.view === "hosts" ? "enter/l open host · 2 problems · o host in Checkmk · r refresh · s servers"
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

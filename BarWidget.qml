import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root

  readonly property string poller: String(Qt.resolvedUrl("bin/checkmk-poll")).replace(/^file:\/\//, "")
  readonly property string configTool: String(Qt.resolvedUrl("bin/checkmk-config")).replace(/^file:\/\//, "")
  readonly property string statusPath: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache")
    + "/omarchy-checkmk/status.json"

  readonly property int refreshIntervalSec: Math.max(10, parseInt(setting("refreshIntervalSec", 60), 10) || 60)
  readonly property bool notifications: setting("notifications", true) !== false
  // Any Nerd Font glyph, the default is nf-md-heart_pulse
  readonly property string icon: setting("icon", "\u{f05f6}") || "\u{f05f6}"

  // Last status written by bin/checkmk-poll, shared by every bar instance through the file
  property var status: null
  property int now: Math.floor(Date.now() / 1000)

  // At least one server answered; the others show up as unreachable in the panel
  readonly property bool reachable: !!status && status.reachable === true
  readonly property bool unconfigured: !!status && status.unconfigured === true
  readonly property int worst: status && !status.unconfigured ? (status.worst || 0) : 0
  readonly property color stateColor: Model.stateColor(worst, bar ? bar.barForeground : Color.foreground,
    bar ? bar.urgent : Color.urgent)

  // There is one bar per monitor, but only the first instance polls, so every
  // state change is notified once
  readonly property bool primary: {
    var items = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : []
    return items.length === 0 || items[0] === root
  }

  function refresh() {
    if (!pollProc.running) pollProc.running = true
  }

  function openWebUi(url) {
    var target = url || (status && status.url ? status.url + "/check_mk/" : "")
    if (target) Quickshell.execDetached(["xdg-open", target])
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.anchorItem = button
    target.hostWidget = root
  }

  // Shape contract for shell summon/hide/toggle routing, as in the built-in widgets
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()

  // omarchy-shell checkmk show <hosts|problems|host:NAME>, e.g. for a Hyprland keybinding
  IpcHandler {
    target: "checkmk"
    enabled: root.primary

    function show(view: string): void { if (panelLoader.item) panelLoader.item.show(view) }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
  }

  FileView {
    id: statusFile
    path: root.statusPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.status = Model.parseStatus(text())
  }

  Process {
    id: pollProc
    command: root.notifications ? [root.poller] : [root.poller, "--quiet"]
    // The poller replaces the file atomically, which the watch can miss
    onExited: statusFile.reload()
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: root.primary
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // Ticks the "updated 20s ago" texts
  Timer {
    interval: 10000
    running: true
    repeat: true
    onTriggered: root.now = Math.floor(Date.now() / 1000)
  }

  Loader {
    id: panelLoader
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    foreground: root.stateColor
    useActiveColor: false
    dimmed: !root.reachable
    slotSize: Style.bar.statusSlot
    tooltipText: root.opened ? "" : root.unconfigured ? "Checkmk: click to set up the connection" : Model.summary(root.status)

    onPressed: function(b) {
      if (b === Qt.RightButton) root.openWebUi()
      else if (b === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }
}

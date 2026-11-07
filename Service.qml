import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Item {
  id: root

  property var shell: null
  readonly property string home: Quickshell.env("HOME")
  readonly property string configPath: home + "/.config/omarchy/dim-it.json"
  readonly property string stayAwakePath: home + "/.local/state/omarchy/indicators/stay-awake"

  property int displayDimSeconds: 60
  property int dimPercentage: 25
  property bool enabled: true
  property bool stayAwake: false
  property int savedBrightness: 0
  property bool isDimmed: false
  property bool manualTest: false

  readonly property bool monitorShouldBeActive: enabled && !stayAwake

  function applyConfig(raw) {
    var parsed = null
    try { parsed = JSON.parse(String(raw || "")) } catch (e) { parsed = null }
    if (!parsed || typeof parsed !== "object") return
    displayDimSeconds = typeof parsed.displayDimSeconds === "number" && parsed.displayDimSeconds >= 5 && parsed.displayDimSeconds <= 3600
      ? Math.round(parsed.displayDimSeconds)
      : typeof parsed.dimSeconds === "number" && parsed.dimSeconds >= 5 && parsed.dimSeconds <= 3600
        ? Math.round(parsed.dimSeconds) : 60
    if (typeof parsed.dimPercentage === "number" && parsed.dimPercentage >= 1 && parsed.dimPercentage <= 100)
      dimPercentage = Math.round(parsed.dimPercentage)
    if (typeof parsed.enabled === "boolean") enabled = parsed.enabled
  }

  property FileView configFile: FileView {
    path: root.configPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyConfig(text())
  }

  FileView {
    id: stayAwakeFile
    path: root.stayAwakePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.stayAwake = true
    onLoadFailed: root.stayAwake = false
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    onTriggered: stayAwakeFile.reload()
  }

  function handleDimIdle(isManual) {
    if (!root.enabled || (root.stayAwake && !isManual) || root.isDimmed) return
    root.manualTest = !!isManual
    readBrightness.running = true
  }

  function handleActive() {
    root.manualTest = false
    if (!root.isDimmed || root.savedBrightness <= 0) return
    var restoreValue = root.savedBrightness
    root.isDimmed = false
    root.savedBrightness = 0
    Quickshell.execDetached(["omarchy-brightness-display", "--no-osd", restoreValue + "%"])
  }

  Process {
    id: readBrightness
    command: ["omarchy-brightness-display"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var current = parseInt(String(text || "").trim(), 10)
        if (isNaN(current) || current <= 1) {
          root.manualTest = false
          return
        }
        if (!root.isIdle && !root.manualTest) {
          root.manualTest = false
          return
        }
        root.savedBrightness = current
        root.isDimmed = true
        var target = Math.max(1, Math.round(current * root.dimPercentage / 100))
        Quickshell.execDetached(["omarchy-brightness-display", "--no-osd", target + "%"])
      }
    }
  }

  readonly property bool isIdle: idleMonitorLoader.item ? idleMonitorLoader.item.isIdle : false

  Loader {
    id: idleMonitorLoader
    active: root.monitorShouldBeActive
    sourceComponent: Component {
      IdleMonitor {
        timeout: root.displayDimSeconds
        respectInhibitors: true
        onIsIdleChanged: isIdle ? root.handleDimIdle(false) : root.handleActive()
      }
    }
  }

  onMonitorShouldBeActiveChanged: {
    if (!monitorShouldBeActive) root.handleActive()
    idleMonitorLoader.active = false
    if (monitorShouldBeActive) Qt.callLater(() => idleMonitorLoader.active = true)
  }

  IpcHandler {
    target: "dim-it.service"
    function status(): string {
      return JSON.stringify({ enabled: root.enabled, stayAwake: root.stayAwake,
        displayDimSeconds: root.displayDimSeconds, dimPercentage: root.dimPercentage,
        isDimmed: root.isDimmed, isIdle: root.isIdle,
        monitorLoaded: idleMonitorLoader.item !== null,
        monitorTimeout: idleMonitorLoader.item ? idleMonitorLoader.item.timeout : 0 })
    }
    function triggerDim(): void { root.handleDimIdle(true) }
    function triggerActive(): void { root.handleActive() }
  }

  Component.onDestruction: root.handleActive()
}

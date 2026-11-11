import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "dim-it"

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/dim-it.json"
  readonly property string stayAwakePath: Quickshell.env("HOME") + "/.local/state/omarchy/indicators/stay-awake"
  property int displayDimSeconds: 60
  property int barDimSeconds: 60
  property int dimPercentage: 25
  property string foregroundMode: "dark"
  property bool enabled: true
  property bool stayAwake: false
  property bool popupOpen: false
  property bool testDimActive: false
  property bool settingsLoaded: false
  property bool settingsDirty: false
  property bool foregroundSyncPending: false
  property bool monitorIdle: false
  property int idleTransitionCount: 0
  property double lastActivityAt: Date.now()
  property int countdownTick: 0
  readonly property int idleElapsedSeconds: {
    countdownTick
    return Math.max(0, Math.floor((Date.now() - lastActivityAt) / 1000))
  }
  readonly property bool opened: popupOpen
  readonly property bool isIdle: monitorIdle && idleElapsedSeconds >= barDimSeconds
  readonly property bool indicatorDimmed: root.isIdle || root.testDimActive
  readonly property color themeForeground: root.bar ? root.bar.barForeground : Commons.Color.bar.text
  readonly property string foregroundScript: Quickshell.env("HOME") + "/.config/omarchy/plugins/dim-it/bar-foreground.py"

  function open() { popupOpen = true }
  function close() { popupOpen = false }
  function toggle() { popupOpen = !popupOpen }
  function testDim() {
    testDimActive = true
    Quickshell.execDetached(["omarchy-shell", "dim-it.service", "triggerDim"])
  }
  function restore() {
    testDimActive = false
    Quickshell.execDetached(["omarchy-shell", "dim-it.service", "triggerActive"])
  }
  function syncBarForeground() {
    if (!root.settingsLoaded) return
    if (foregroundSync.running) {
      foregroundSyncPending = true
      return
    }
    if (root.indicatorDimmed && root.bar) {
      foregroundSync.command = ["python3", root.foregroundScript, "apply", root.foregroundMode,
        String(root.bar.barForeground), String(root.bar.urgent)]
    } else {
      foregroundSync.command = ["python3", root.foregroundScript, "restore"]
    }
    foregroundSync.running = true
  }
  onIndicatorDimmedChanged: syncBarForeground()
  onForegroundModeChanged: if (indicatorDimmed) syncBarForeground()
  onEnabledChanged: {
    lastActivityAt = Date.now()
    if (!enabled) {
      monitorIdle = false
      testDimActive = false
      popupOpen = false
      Quickshell.execDetached(["omarchy-shell", "dim-it.service", "triggerActive"])
      syncBarForeground()
    }
  }
  function secondsUntilDim(timeoutSeconds) {
    return Math.max(0, timeoutSeconds - idleElapsedSeconds)
  }
  function formatSeconds(seconds) {
    if (seconds < 60) return strings.t("time.seconds").arg(seconds)
    var minutes = Math.floor(seconds / 60)
    var remainder = seconds % 60
    return remainder ? strings.t("time.minute_seconds").arg(minutes).arg(remainder) : strings.t(minutes === 1 ? "time.minute" : "time.minutes").arg(minutes)
  }
  function applyConfig(raw) {
    if (settingsDirty) return
    var parsed = null
    try { parsed = JSON.parse(String(raw || "")) } catch (e) { parsed = null }
    if (!parsed || typeof parsed !== "object") return
    var legacySeconds = typeof parsed.dimSeconds === "number" && parsed.dimSeconds >= 5 && parsed.dimSeconds <= 3600
      ? Math.round(parsed.dimSeconds) : 60
    displayDimSeconds = typeof parsed.displayDimSeconds === "number" && parsed.displayDimSeconds >= 5 && parsed.displayDimSeconds <= 18000
      ? Math.round(parsed.displayDimSeconds) : legacySeconds
    barDimSeconds = typeof parsed.barDimSeconds === "number" && parsed.barDimSeconds >= 5 && parsed.barDimSeconds <= 18000
      ? Math.round(parsed.barDimSeconds) : legacySeconds
    if (typeof parsed.dimPercentage === "number" && parsed.dimPercentage >= 1 && parsed.dimPercentage <= 100) dimPercentage = Math.round(parsed.dimPercentage)
    foregroundMode = parsed.foregroundMode === "dark" || parsed.foregroundMode === "very-dark" || parsed.foregroundMode === "black"
      ? parsed.foregroundMode : "dark"
    if (typeof parsed.enabled === "boolean") enabled = parsed.enabled
    settingsDirty = false
  }
  function saveConfig() {
    var data = { displayDimSeconds: displayDimSeconds, barDimSeconds: barDimSeconds,
      dimPercentage: dimPercentage, foregroundMode: foregroundMode, enabled: enabled }
    var output = JSON.stringify(data, null, 2) + "\n"
    if (configFile && typeof configFile.setText === "function") configFile.setText(output)
    settingsDirty = false
  }
  function selectDisplayTimeout(seconds) { displayDimSeconds = seconds; settingsDirty = true }
  function selectBarTimeout(seconds) { barDimSeconds = seconds; settingsDirty = true }
  function selectLevel(percent) { dimPercentage = percent; settingsDirty = true }
  function saveSettings() { saveConfig() }
  function restartShell() { Quickshell.execDetached(["omarchy", "restart", "shell"]) }

  property FileView configFile: FileView {
    path: root.configPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onSaved: root.settingsDirty = false
    onLoaded: {
      root.applyConfig(text())
      if (!root.settingsLoaded) {
        root.settingsLoaded = true
        root.syncBarForeground()
      }
    }
    onLoadFailed: {
      if (!root.settingsLoaded) {
        root.settingsLoaded = true
        root.syncBarForeground()
      }
    }
  }
  Process {
    id: foregroundSync
    command: []
    onExited: {
      if (root.foregroundSyncPending) {
        root.foregroundSyncPending = false
        root.syncBarForeground()
      }
    }
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
    interval: 1500
    running: true
    repeat: true
    onTriggered: { root.configFile.reload(); stayAwakeFile.reload() }
  }
  IdleMonitor {
    id: idleMonitor
    enabled: root.enabled && !root.stayAwake
    timeout: 1
    respectInhibitors: true
    Component.onCompleted: {
      root.monitorIdle = isIdle
      if (isIdle) root.lastActivityAt = Date.now() - 1000
    }
    onIsIdleChanged: {
      root.monitorIdle = isIdle
      root.idleTransitionCount++
      root.lastActivityAt = isIdle ? Date.now() - 1000 : Date.now()
    }
  }
  Timer {
    interval: 1000
    running: root.enabled && !root.stayAwake
    repeat: true
    onTriggered: root.countdownTick++
  }
  onStayAwakeChanged: {
    lastActivityAt = Date.now()
    if (stayAwake) monitorIdle = false
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰃞"
    slotSize: Style.bar.iconSlot
    active: root.indicatorDimmed
    useActiveColor: false
    foreground: root.themeForeground
    tooltipText: !root.enabled ? strings.t("tooltip.disabled")
      : root.stayAwake ? strings.t("tooltip.stay_awake")
      : root.testDimActive ? strings.t("tooltip.test_dim")
      : root.isIdle ? strings.t("tooltip.idle")
      : strings.t("tooltip.after").arg(root.formatSeconds(root.barDimSeconds))
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) { root.enabled = !root.enabled; root.saveConfig() }
      else root.toggle()
    }
  }

  IpcHandler {
    target: root.moduleName
    function open(): void { root.broadcast("open") }
    function close(): void { root.broadcast("close") }
    function toggle(): void { root.broadcast("toggle") }
    function testDim(): void { root.broadcast("testDim") }
    function restore(): void { root.broadcast("restore") }
    function status(): string {
      return JSON.stringify({ isIdle: root.isIdle, testDimActive: root.testDimActive,
        foregroundMode: root.foregroundMode, displayDimSeconds: root.displayDimSeconds,
        barDimSeconds: root.barDimSeconds, themeForeground: String(root.themeForeground),
        barActive: root.bar ? String(root.bar.urgent) : "",
        idleTransitionCount: root.idleTransitionCount,
        monitorLoaded: true,
        monitorEnabled: idleMonitor.enabled,
        monitorTimeout: idleMonitor.timeout })
    }
  }

  PopupCard {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.popupOpen
    onOpenChanged: {
      if (root.popupOpen !== open) root.popupOpen = open
      if (!open && root.testDimActive) root.restore()
    }
    contentWidth: popup.fittedContentWidth(Style.space(360))
    contentHeight: popup.fittedContentHeight(contentColumn.implicitHeight)

    Column {
      id: contentColumn
      width: parent.width
      spacing: Style.space(14)

      Row {
        width: parent.width
        spacing: Style.space(10)
        Text {
          text: "󰃞"
          color: Commons.Color.accent
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.title
          anchors.verticalCenter: parent.verticalCenter
        }
        Column {
          width: parent.width - enabledSwitch.width - Style.space(40)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)
          Text {
            textFormat: Text.PlainText
            text: strings.t("panel.title")
            color: Commons.Color.popups.text
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }
          Text {
            textFormat: Text.PlainText
            text: !root.enabled ? strings.t("panel.paused")
              : root.stayAwake ? strings.t("panel.stay_awake")
              : strings.t("panel.after_enabled")
                .arg(root.formatSeconds(root.secondsUntilDim(root.displayDimSeconds)))
                .arg(root.formatSeconds(root.secondsUntilDim(root.barDimSeconds)))
            color: Commons.Color.popups.text
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
        ToggleSwitch {
          id: enabledSwitch
          anchors.verticalCenter: parent.verticalCenter
          checked: root.enabled
          onToggled: { root.enabled = !root.enabled; root.saveConfig() }
        }
      }

      PanelSeparator { width: parent.width; foreground: Commons.Color.popups.text }

      Column {
        width: parent.width
        spacing: Style.space(7)
        Text {
          textFormat: Text.PlainText
          text: strings.t("panel.display_timer")
          color: Commons.Color.popups.text
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }
        Flow {
          width: parent.width
          spacing: Style.space(6)
          Repeater {
            model: [10, 30, 45, 60, 120, 300]
            Button {
              required property int modelData
              text: strings.t("time.seconds").arg(modelData)
              selected: root.displayDimSeconds === modelData
              active: selected
              bordered: true
              horizontalPadding: Style.space(9)
              verticalPadding: Style.space(5)
              foreground: Commons.Color.popups.text
              onClicked: root.selectDisplayTimeout(modelData)
            }
          }
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(7)
        Text {
          textFormat: Text.PlainText
          text: strings.t("panel.bar_timer")
          color: Commons.Color.popups.text
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }
        Flow {
          width: parent.width
          spacing: Style.space(6)
          Repeater {
            model: [5, 10, 15, 30, 45]
            Button {
              required property int modelData
              text: strings.t("time.seconds").arg(modelData)
              selected: root.barDimSeconds === modelData
              active: selected
              bordered: true
              horizontalPadding: Style.space(9)
              verticalPadding: Style.space(5)
              foreground: Commons.Color.popups.text
              onClicked: root.selectBarTimeout(modelData)
            }
          }
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(7)
        Text {
          textFormat: Text.PlainText
          text: strings.t("panel.brightness")
          color: Commons.Color.popups.text
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }
        Row {
          spacing: Style.space(7)
          Repeater {
            model: [25, 50, 75]
            Button {
              required property int modelData
              text: modelData + "%"
              selected: root.dimPercentage === modelData
              active: selected
              bordered: true
              horizontalPadding: Style.space(12)
              verticalPadding: Style.space(5)
              foreground: Commons.Color.popups.text
              onClicked: root.selectLevel(modelData)
            }
          }
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(7)
        Text {
          textFormat: Text.PlainText
          text: strings.t("panel.foreground")
          color: Commons.Color.popups.text
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }
        Row {
          spacing: Style.space(7)
          Button {
            text: strings.t("panel.gray")
            selected: root.foregroundMode === "dark"
            active: selected
            bordered: true
            foreground: Commons.Color.popups.text
            onClicked: { root.foregroundMode = "dark"; root.settingsDirty = true }
          }
          Button {
            text: strings.t("panel.dark_gray")
            selected: root.foregroundMode === "very-dark"
            active: selected
            bordered: true
            foreground: Commons.Color.popups.text
            onClicked: { root.foregroundMode = "very-dark"; root.settingsDirty = true }
          }
          Button {
            text: strings.t("panel.black")
            selected: root.foregroundMode === "black"
            active: selected
            bordered: true
            foreground: Commons.Color.popups.text
            onClicked: { root.foregroundMode = "black"; root.settingsDirty = true }
          }
        }
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.stayAwake
          ? strings.t("panel.stay_awake")
          : strings.t("panel.theme_color")
        color: Commons.Color.popups.text
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Row {
        width: parent.width
        spacing: Style.space(8)
        Button {
          text: strings.t("panel.save")
          bordered: true
          foreground: Commons.Color.popups.text
          onClicked: root.saveSettings()
        }
        Button {
          text: strings.t("panel.restart_shell")
          bordered: true
          foreground: Commons.Color.popups.text
          onClicked: root.restartShell()
        }
        Button {
          text: strings.t("panel.test")
          bordered: true
          foreground: Commons.Color.popups.text
          onClicked: root.testDim()
        }
        Button {
          text: strings.t("panel.restore")
          bordered: true
          foreground: Commons.Color.popups.text
          onClicked: root.restore()
        }
      }
    }
  }
}

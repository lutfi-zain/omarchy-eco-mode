import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "lutfi.eco"
  ipcTarget: "lutfi.eco"
  manageIpc: true

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string helperPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/lutfi.eco/bin/eco-ctl"

  // State exposed to the UI
  property bool ecoActive: false
  property bool autoSwitch: false
  property bool adjustBlur: true
  property bool adjustOpacity: true
  property bool adjustAnimations: true
  property bool adjustBrightness: true
  property int  targetBrightness: 35
  property bool adjustPowerProfile: true

  // Telemetry
  property string batteryPct: ""
  property string batteryTime: ""
  property real   batteryWatts: 0.0
  property bool   acOnline: false
  property string batteryState: ""

  property bool loaded: false
  property bool actionRunning: false

  // Bar icon color — green tint when eco is active, normal foreground otherwise
  readonly property color iconColor: {
    if (!root.bar) return ecoActive ? "#4ade80" : "#ffffff"
    return ecoActive
      ? Qt.lighter(root.bar.foreground, 1.0)   // will be tinted via opacity trick below
      : root.bar.foreground
  }

  // Tooltip text
  readonly property string tooltipLabel: {
    if (ecoActive) {
      var parts = []
      if (batteryWatts > 0) parts.push(batteryWatts.toFixed(1) + "W")
      if (batteryTime)       parts.push(batteryTime + " left")
      return "Eco ON" + (parts.length > 0 ? " · " + parts.join(" · ") : "")
    }
    if (!acOnline && batteryWatts > 0) {
      return batteryPct + " · " + batteryWatts.toFixed(1) + "W"
    }
    return "Eco Mode"
  }

  function loadState() {
    getProc.running = true
  }

  function parseState(text) {
    try {
      var d = JSON.parse(text)
      root.ecoActive           = d.active            === true
      root.autoSwitch          = d.auto_switch        === true
      root.adjustBlur          = d.adjust_blur        !== false
      root.adjustOpacity       = d.adjust_opacity     !== false
      root.adjustAnimations    = d.adjust_animations  !== false
      root.adjustBrightness    = d.adjust_brightness  !== false
      root.targetBrightness    = d.target_brightness  || 35
      root.adjustPowerProfile  = d.adjust_powerprofile !== false

      var t = d.telemetry || {}
      root.batteryPct   = t.percentage  || ""
      root.batteryTime  = t.time        || ""
      root.batteryWatts = t.rate_watts  || 0.0
      root.acOnline     = t.ac_online   === true
      root.batteryState = t.state       || ""

      root.loaded = true
    } catch (e) {}
  }

  function runToggle(force) {
    if (actionRunning) return
    var cmd = [root.helperPath, "toggle"]
    if (force === "on" || force === "off") cmd.push(force)
    toggleProc.command = cmd
    toggleProc.running = true
    root.actionRunning = true
  }

  function setConfigKey(key, value) {
    configProc.command = [root.helperPath, "set-config", key, String(value)]
    configProc.running = true
  }

  // ─── Processes ───────────────────────────────────────────────────────────

  Process {
    id: getProc
    command: [root.helperPath, "get"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseState(text)
    }
  }

  Process {
    id: toggleProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.parseState(text)
        root.actionRunning = false
      }
    }
    onExited: root.actionRunning = false
  }

  Process {
    id: configProc
    onExited: root.loadState()
  }

  // Refresh telemetry every 8s while panel is closed; 4s while open
  Timer {
    interval: root.opened ? 4000 : 8000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.loadState()
  }

  Component.onCompleted: loadState()
  onOpenedChanged: if (opened) loadState()

  // ─── Bar Button ──────────────────────────────────────────────────────────

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰌪"
    tooltipText: root.tooltipLabel
    foreground: root.ecoActive
      ? "#4ade80"
      : (root.bar ? root.bar.foreground : Color.foreground)

    Behavior on foreground { ColorAnimation { duration: 200 } }

    onPressed: function(b) {
      if (b === Qt.LeftButton || b === Qt.MiddleButton) root.toggle()
    }
  }

  // ─── Panel ───────────────────────────────────────────────────────────────

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(mainColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Column {
        id: mainColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ── Header: icon + title + master toggle ─────────────────────────
        RowLayout {
          width: parent.width
          spacing: Style.space(10)

          // Eco leaf icon — green when active
          Text {
            text: "󰌪"
            color: root.ecoActive ? "#4ade80" : (root.bar ? root.bar.foreground : Color.foreground)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.title

            Behavior on color { ColorAnimation { duration: 200 } }
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Text {
              text: "Eco Mode"
              color: root.bar ? root.bar.foreground : Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }

            Text {
              text: {
                if (root.ecoActive) {
                  var parts = []
                  if (root.batteryWatts > 0) parts.push(root.batteryWatts.toFixed(1) + "W")
                  if (root.batteryTime)       parts.push(root.batteryTime + " left")
                  return parts.length > 0 ? parts.join(" · ") : "Active"
                }
                if (!root.acOnline && root.batteryWatts > 0) {
                  return root.batteryPct + " · " + root.batteryWatts.toFixed(1) + "W drawing"
                }
                return root.acOnline ? "On AC power" : "On battery"
              }
              color: root.ecoActive
                ? "#4ade80"
                : Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption

              Behavior on color { ColorAnimation { duration: 200 } }
            }
          }

          ToggleSwitch {
            checked: root.ecoActive
            onToggled: root.runToggle(root.ecoActive ? "off" : "on")
          }
        }

        // ── Battery progress bar ─────────────────────────────────────────
        Item {
          width: parent.width
          implicitHeight: Style.space(5)
          visible: root.batteryPct !== ""

          readonly property real fraction: {
            var s = root.batteryPct.replace("%", "").trim()
            var n = parseInt(s, 10)
            return isNaN(n) ? 0 : Math.max(0, Math.min(1, n / 100))
          }

          Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(
              root.bar ? root.bar.foreground.r : 1,
              root.bar ? root.bar.foreground.g : 1,
              root.bar ? root.bar.foreground.b : 1,
              0.12
            )
          }

          Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            radius: parent.height / 2
            width: Math.max(parent.height, parent.width * parent.fraction)
            color: {
              var f = parent.fraction
              if (f <= 0.20) return "#f87171"   // red
              if (f <= 0.40) return "#fb923c"   // orange
              if (root.ecoActive) return "#4ade80" // eco green
              return root.bar ? root.bar.foreground : "#ffffff"
            }

            Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 200 } }
          }
        }

        PanelSeparator { foreground: root.bar ? root.bar.foreground : Color.foreground }

        // ── Auto-switch section ──────────────────────────────────────────
        Toggle {
          width: parent.width
          label: "Auto-enable on battery unplug"
          description: root.autoSwitch
            ? "Eco activates when charger is removed"
            : "Manual control only"
          checked: root.autoSwitch
          foreground: root.bar ? root.bar.foreground : Color.foreground
          accent: root.bar ? root.bar.urgent : Color.accent
          onClicked: {
            root.autoSwitch = !root.autoSwitch
            root.setConfigKey("auto_switch_battery", root.autoSwitch)
          }
        }

        PanelSeparator { foreground: root.bar ? root.bar.foreground : Color.foreground }

        // ── Granular adjustments section ─────────────────────────────────
        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "ECO ADJUSTMENTS"
            foreground: root.bar ? root.bar.foreground : Color.foreground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          }

          // Blur
          Toggle {
            width: parent.width
            label: "Disable window blur"
            description: "Saves ~3-5W on Radeon Vega iGPU"
            checked: root.adjustBlur
            foreground: root.bar ? root.bar.foreground : Color.foreground
            accent: root.bar ? root.bar.urgent : Color.accent
            onClicked: {
              root.adjustBlur = !root.adjustBlur
              root.setConfigKey("adjust_blur", root.adjustBlur)
            }
          }

          // Opacity
          Toggle {
            width: parent.width
            label: "Enforce solid windows"
            description: "100% opacity, no compositor layer blending"
            checked: root.adjustOpacity
            foreground: root.bar ? root.bar.foreground : Color.foreground
            accent: root.bar ? root.bar.urgent : Color.accent
            onClicked: {
              root.adjustOpacity = !root.adjustOpacity
              root.setConfigKey("adjust_opacity", root.adjustOpacity)
            }
          }

          // Animations
          Toggle {
            width: parent.width
            label: "Disable animations"
            description: "Stops GPU spikes during workspace switching"
            checked: root.adjustAnimations
            foreground: root.bar ? root.bar.foreground : Color.foreground
            accent: root.bar ? root.bar.urgent : Color.accent
            onClicked: {
              root.adjustAnimations = !root.adjustAnimations
              root.setConfigKey("adjust_animations", root.adjustAnimations)
            }
          }

          // Power profile
          Toggle {
            width: parent.width
            label: "Switch to power-saver profile"
            description: "Sets powerprofilesctl to power-saver"
            checked: root.adjustPowerProfile
            foreground: root.bar ? root.bar.foreground : Color.foreground
            accent: root.bar ? root.bar.urgent : Color.accent
            onClicked: {
              root.adjustPowerProfile = !root.adjustPowerProfile
              root.setConfigKey("adjust_powerprofile", root.adjustPowerProfile)
            }
          }

          // Brightness toggle + slider
          Column {
            width: parent.width
            spacing: Style.space(6)

            Toggle {
              width: parent.width
              label: "Cap display brightness"
              description: "Reduces backlight to target level"
              checked: root.adjustBrightness
              foreground: root.bar ? root.bar.foreground : Color.foreground
              accent: root.bar ? root.bar.urgent : Color.accent
              onClicked: {
                root.adjustBrightness = !root.adjustBrightness
                root.setConfigKey("adjust_brightness", root.adjustBrightness)
              }
            }

            // Slider only visible when brightness adjustment is enabled
            Column {
              width: parent.width
              spacing: Style.space(4)
              opacity: root.adjustBrightness ? 1.0 : 0.35

              RowLayout {
                width: parent.width

                PanelSectionHeader {
                  text: "TARGET BRIGHTNESS"
                  foreground: root.bar ? root.bar.foreground : Color.foreground
                  fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                }

                Item { Layout.fillWidth: true }

                Text {
                  text: (brightnessSlider.dragging
                    ? Math.round(brightnessSlider.liveValue)
                    : root.targetBrightness) + "%"
                  color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }

              PanelSlider {
                id: brightnessSlider
                bar: root.bar
                width: parent.width
                minimum: 20
                maximum: 70
                step: 5
                integer: true
                value: root.targetBrightness
                enabled: root.adjustBrightness

                onMoved: function(v) {
                  root.targetBrightness = Math.round(v)
                }
                onReleased: function(v) {
                  root.targetBrightness = Math.round(v)
                  root.setConfigKey("target_brightness", root.targetBrightness)
                }
              }
            }
          }
        }

        PanelSeparator { foreground: root.bar ? root.bar.foreground : Color.foreground }

        // ── Quick action row ─────────────────────────────────────────────
        Row {
          width: parent.width
          spacing: Style.space(8)

          Button {
            width: (parent.width - parent.spacing) / 2
            text: "Apply Eco Now"
            bordered: true
            active: root.ecoActive
            onClicked: root.runToggle("on")
          }

          Button {
            width: (parent.width - parent.spacing) / 2
            text: "Restore Normal"
            bordered: true
            onClicked: root.runToggle("off")
          }
        }
      }
    }
  }
}

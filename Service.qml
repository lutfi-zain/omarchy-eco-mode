import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

/*
  lutfi.eco — Service.qml
  Background AC/battery detection service.
  Polls eco-ctl every 6 seconds while on battery;
  reacts immediately to UPower's onBatteryChanged signal.
*/

Item {
  id: root

  property var shell: null

  // Debounce rapid AC plug/unplug events (e.g. connector bounce)
  property bool pendingPoll: false

  function runPoll() {
    if (!pollProc.running) {
      pollProc.running = true
    } else {
      root.pendingPoll = true
    }
  }

  Process {
    id: pollProc
    command: [Quickshell.env("HOME") + "/.config/omarchy/plugins/lutfi.eco/bin/eco-ctl", "poll"]
    onExited: {
      if (root.pendingPoll) {
        root.pendingPoll = false
        root.runPoll()
      }
    }
  }

  // Periodic refresh every 6 seconds — keeps telemetry fresh without UPower lag
  Timer {
    interval: 6000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.runPoll()
  }

  // Immediate reaction to AC plug/unplug via UPower signal — no polling delay
  Connections {
    target: UPower
    function onOnBatteryChanged() {
      // Small delay to let the kernel settle /sys/class/power_supply values
      acDebounce.restart()
    }
  }

  Timer {
    id: acDebounce
    interval: 1200
    repeat: false
    onTriggered: root.runPoll()
  }
}

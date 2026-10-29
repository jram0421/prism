import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "jram0421.prism"
  ipcTarget: "jram0421.prism"
  // manageIpc: false so this panel owns the one IpcHandler the target permits,
  // which adds `settings` (open straight to the settings view) to the usual set.
  manageIpc: false

  readonly property string script: String(Qt.resolvedUrl("bin/omarchy-prism")).replace("file://", "")

  // Mirrored from `omarchy-prism status --json`.
  property var cfg: ({
    power: true, mode: "Static", color: "ffffff", brightness: 100, speed: 50,
    follow_theme: false, auto_off: { lock: false, screensaver: false }, zones: {}
  })
  property var runtime: ({})
  property bool installed: true
  property string serverState: "active"
  property string engineState: "active"
  property string accent: ""
  property var checks: []
  property string error: ""
  property string view: "main"   // "main" or "settings"

  readonly property bool powered: cfg.power === true
  readonly property bool needsSetup: !installed || engineState !== "active" || serverState !== "active"
  readonly property string suppressed: runtime && runtime.suppressed ? runtime.suppressed : ""
  readonly property var swatches: [
    { name: "Theme", hex: "theme" },
    { name: "White", hex: "ffffff" },
    { name: "Red", hex: "ff0000" },
    { name: "Orange", hex: "ff6a00" },
    { name: "Yellow", hex: "ffd000" },
    { name: "Green", hex: "00ff40" },
    { name: "Cyan", hex: "00e5ff" },
    { name: "Blue", hex: "0040ff" },
    { name: "Purple", hex: "9d00ff" },
    { name: "Pink", hex: "ff2a9d" }
  ]
  readonly property var modes: ["Static", "Breathing", "Flashing", "Spectrum Cycle", "Rainbow", "Wave"]

  // Every zone OpenRGB reports as resizable (addressable headers), across all devices.
  readonly property var zoneList: {
    var out = []
    var devices = runtime && runtime.devices ? runtime.devices : []
    for (var i = 0; i < devices.length; i++) {
      for (var j = 0; j < devices[i].zones.length; j++) {
        var z = devices[i].zones[j]
        if (z.resizable) out.push({ key: z.key, label: z.name, device: devices[i].name, leds: z.leds, min: z.min, max: z.max })
      }
    }
    return out
  }

  // Playful status line, rotated like the Bluetooth and Network panels. The
  // first entry is the real state (effect and color) so it is what you see on
  // open; the rest are flavor.
  property int phraseIndex: 0
  readonly property var phrases: [
    "Untangling photons",
    "Herding rainbows",
    "Polishing pixels",
    "Wrangling lumens",
    "Taming the glow",
    "Summoning sparkle",
    "Feeding the LEDs",
    "Bottling sunsets"
  ]
  readonly property bool rotatingPhrases: installed && !needsSetup && powered && suppressed === ""
  readonly property var activePhrases: [cfg.mode + " · #" + cfg.color].concat(phrases)
  readonly property string heroStatusText: {
    if (!installed) return "OpenRGB missing"
    if (needsSetup) return "Setup needed"
    if (suppressed === "locked") return "Paused · locked"
    if (suppressed === "screensaver") return "Paused · screensaver"
    if (!powered) return "Off"
    return activePhrases[phraseIndex % activePhrases.length]
  }

  function swatchColor(hex) {
    if (hex === "theme") return root.accent !== "" ? "#" + root.accent : Commons.Color.accent
    return "#" + hex
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function refreshChecks() {
    if (!doctorProc.running) doctorProc.running = true
  }

  // Commands run one at a time. Queued commands replace an earlier one for the
  // same setting (and the same zone), so dragging a slider or stepping a number
  // cannot pile up work.
  property var queue: []

  function run(args) {
    var key = args.slice(0, args[0] === "zone" ? 2 : 1).join(" ")
    queue = queue.filter(function(q) { return q.key !== key }).concat([{ key: key, args: args }])
    pump()
  }

  function pump() {
    if (actionProc.running || queue.length === 0) return
    var next = queue[0]
    queue = queue.slice(1)
    root.error = ""
    actionProc.command = [root.script].concat(next.args)
    actionProc.running = true
  }

  // Optimistic update so the panel responds before the next status poll.
  function patch(values) {
    cfg = Object.assign({}, cfg, values)
  }

  function setColor(hex) {
    var theme = hex === "theme"
    var value = theme ? root.accent : hex
    var next = { color: value, power: true }
    if (cfg.mode === "Rainbow" || cfg.mode === "Spectrum Cycle") next.mode = "Static"
    patch(next)
    run(["color", hex])
  }

  function setMode(mode) {
    patch({ mode: mode, power: true })
    run(["mode", mode])
  }

  function setPower(on) {
    patch({ power: on })
    run([on ? "on" : "off"])
  }

  function setAutoOff(trigger, on) {
    var next = Object.assign({}, cfg.auto_off)
    next[trigger] = on
    patch({ auto_off: next })
    run(["auto-off", trigger, on ? "on" : "off"])
  }

  function launchSetup() {
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", Util.shellQuote(root.script) + " setup"])
  }

  function parseStatus(raw) {
    var st
    try { st = JSON.parse(raw) } catch (e) { return }
    if (!st || !st.config) return
    // Don't let a poll overwrite a value the user is still dragging.
    if (actionProc.running || root.queue.length > 0) return
    cfg = st.config
    runtime = st.runtime || ({})
    installed = st.installed === true
    serverState = st.server
    engineState = st.engine
    accent = st.accent || ""
  }

  function parseChecks(raw) {
    try { checks = JSON.parse(raw) } catch (e) { checks = [] }
  }

  property bool openToSettings: false

  function openSettings() {
    openToSettings = true
    open()
  }

  IpcHandler {
    target: "jram0421.prism"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function settings() { root.openSettings() }
  }

  onOpenedChanged: {
    if (opened) {
      phraseIndex = 0
      view = openToSettings ? "settings" : "main"
      openToSettings = false
      refresh()
    }
  }
  onViewChanged: if (view === "settings") refreshChecks()

  Timer { interval: 3000; running: root.opened; repeat: true; onTriggered: root.refresh() }

  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && root.view === "main" && root.rotatingPhrases
    repeat: true
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: heroStatus; property: "opacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length
    }
    PropertyAnimation {
      target: heroStatus; property: "opacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  // Leaving a rotating state mid-swap: stop and snap back to full opacity so
  // "Off" / "Paused" is legible immediately.
  Connections {
    target: root
    function onRotatingPhrasesChanged() {
      if (!root.rotatingPhrases) {
        phraseSwap.stop()
        heroStatus.opacity = 1.0
      }
    }
  }


  Process {
    id: statusProc
    command: [root.script, "status", "--json"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.parseStatus(text) }
  }

  Process {
    id: doctorProc
    command: [root.script, "doctor", "--json"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.parseChecks(text) }
  }

  Process {
    id: actionProc
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.error = String(actionErr.text).trim().split("\n")[0]
      if (root.queue.length > 0) root.pump()
      else root.refresh()
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.powered ? "󰛨" : "󰌶"
    dimmed: !root.powered || root.needsSetup
    tooltipText: ""
    onPressed: function(b) {
      if (b === Qt.RightButton) root.setPower(!root.powered)
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(root.view === "main" ? mainColumn.implicitHeight : settingsColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: hexField.activeFocus
      onCloseRequested: {
        if (root.view === "settings") root.view = "main"
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      // =====================================================================
      // Main view
      // =====================================================================
      Column {
        id: mainColumn
        visible: root.view === "main"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, powerSwitch.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.powered ? "󰛨" : "󰌶"
            color: root.powered && !root.needsSetup ? root.swatchColor(root.cfg.color) : root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            Behavior on color { ColorAnimation { duration: 200 } }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroControls.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Prism"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              width: parent.width
            }

            Text {
              id: heroStatus
              textFormat: Text.PlainText
              text: root.heroStatusText.toUpperCase()
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Row {
            id: heroControls
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(10)

            PanelActionButton {
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰒓"
              tooltipText: "Settings"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onClicked: root.view = "settings"
            }

            ToggleSwitch {
              id: powerSwitch
              anchors.verticalCenter: parent.verticalCenter
              foreground: root.bar.foreground
              checked: root.powered
              interactive: !root.needsSetup
              onToggled: root.setPower(!root.powered)
            }
          }
        }

        Column {
          visible: root.needsSetup
          width: parent.width
          spacing: Style.space(8)

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: root.installed
              ? "The lighting service isn't running. Run setup to install and start it."
              : "OpenRGB isn't installed. Run setup to install it and start the lighting service."
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Button {
            width: parent.width
            text: "Run setup"
            iconText: "󰐊"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            onClicked: root.launchSetup()
          }
        }

        Text {
          visible: root.error !== ""
          width: parent.width
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: root.error
          color: root.bar.urgent
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        PanelSeparator { foreground: root.bar.foreground }

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "COLOR"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Flow {
            width: parent.width
            spacing: Style.space(8)

            Repeater {
              model: root.swatches
              Rectangle {
                required property var modelData
                readonly property bool current: modelData.hex === "theme"
                  ? root.cfg.color === root.accent
                  : root.cfg.color === modelData.hex
                width: Style.space(28)
                height: width
                radius: width / 2
                color: root.swatchColor(modelData.hex)
                border.width: current ? 2 : 1
                border.color: current ? root.bar.foreground : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.25)
                scale: swatchMouse.containsMouse ? 1.12 : 1.0
                Behavior on scale { NumberAnimation { duration: 100 } }

                Text {
                  visible: modelData.hex === "theme"
                  anchors.centerIn: parent
                  text: "󰏘"
                  color: root.bar.background
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                MouseArea {
                  id: swatchMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.setColor(modelData.hex)
                }

                PanelToolTip {
                  visible: swatchMouse.containsMouse
                  text: modelData.name
                  fontFamily: root.bar.fontFamily
                }
              }
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "EFFECT"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Flow {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.modes
              Button {
                required property string modelData
                text: modelData
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                bordered: true
                active: root.powered && root.cfg.mode === modelData
                onClicked: root.setMode(modelData)
              }
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "BRIGHTNESS  " + Math.round(brightnessSlider.liveValue) + "%"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          PanelSlider {
            id: brightnessSlider
            width: parent.width
            bar: root.bar
            minimum: 0
            maximum: 100
            step: 5
            integer: true
            value: root.cfg.brightness
            onReleased: function(v) {
              root.patch({ brightness: Math.round(v), power: true })
              root.run(["brightness", String(Math.round(v))])
            }
          }
        }

        Toggle {
          width: parent.width
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          label: "Match theme"
          description: "Recolor to the theme accent when the theme changes"
          checked: root.cfg.follow_theme === true
          onClicked: {
            root.patch({ follow_theme: !root.cfg.follow_theme })
            root.run(["follow", root.cfg.follow_theme ? "on" : "off"])
          }
        }
      }

      // =====================================================================
      // Settings view
      // =====================================================================
      Column {
        id: settingsColumn
        visible: root.view === "settings"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        Row {
          spacing: Style.space(10)

          PanelActionButton {
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰁍"
            tooltipText: "Back"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: root.view = "main"
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Settings"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }
        }

        // ---------- Custom color ----------
        Column {
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "CUSTOM COLOR"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Rectangle {
              id: customPreview
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(28)
              height: width
              radius: width / 2
              color: /^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(hexField.text)
                ? (hexField.text.charAt(0) === "#" ? hexField.text : "#" + hexField.text)
                : root.swatchColor(root.cfg.color)
              border.width: 1
              border.color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.25)
            }

            TextField {
              id: hexField
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - customPreview.width - applyButton.width - parent.spacing * 2
              placeholderText: "#" + root.cfg.color
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              foreground: root.bar.foreground
              onAccepted: {
                root.setColor(text.replace("#", ""))
                text = ""
                keyCatcher.forceActiveFocus()
              }
              Keys.onEscapePressed: { text = ""; keyCatcher.forceActiveFocus() }
            }

            Button {
              id: applyButton
              anchors.verticalCenter: parent.verticalCenter
              text: "Apply"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              bordered: true
              onClicked: {
                if (hexField.text !== "") root.setColor(hexField.text.replace("#", ""))
                hexField.text = ""
              }
            }
          }
        }

        // ---------- Speed ----------
        Column {
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "EFFECT SPEED  " + Math.round(speedSlider.liveValue) + "%"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          PanelSlider {
            id: speedSlider
            width: parent.width
            bar: root.bar
            minimum: 0
            maximum: 100
            step: 5
            integer: true
            value: root.cfg.speed
            onReleased: function(v) {
              root.patch({ speed: Math.round(v) })
              root.run(["speed", String(Math.round(v))])
            }
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        // ---------- Automation ----------
        Column {
          width: parent.width
          spacing: Style.space(4)

          PanelSectionHeader {
            text: "AUTOMATION"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Toggle {
            width: parent.width
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            label: "Off while locked"
            description: "Fade out when the screen locks, back on unlock"
            checked: root.cfg.auto_off.lock === true
            onClicked: root.setAutoOff("lock", !root.cfg.auto_off.lock)
          }

          Toggle {
            width: parent.width
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            label: "Off during screensaver"
            description: "Fade out when the idle screensaver starts"
            checked: root.cfg.auto_off.screensaver === true
            onClicked: root.setAutoOff("screensaver", !root.cfg.auto_off.screensaver)
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        // ---------- LED zones ----------
        Column {
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "ADDRESSABLE HEADERS"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: root.zoneList.length > 0
              ? "Set the number of LEDs on whatever is plugged into each header. A header set to 0 stays dark."
              : "No adjustable headers detected."
            color: root.bar.foreground
            opacity: 0.6
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Repeater {
            model: root.zoneList

            Item {
              required property var modelData
              width: settingsColumn.width
              height: Math.max(zoneLabel.implicitHeight, zoneField.implicitHeight)

              Column {
                id: zoneLabel
                anchors.left: parent.left
                anchors.right: zoneField.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: modelData.label
                  elide: Text.ElideRight
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: modelData.device
                  elide: Text.ElideRight
                  color: root.bar.foreground
                  opacity: 0.5
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              NumberField {
                id: zoneField
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                from: modelData.min
                to: modelData.max
                value: modelData.leds
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                onModified: function(v) { root.run(["zone", modelData.key, String(v)]) }
              }
            }
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        // ---------- Diagnostics ----------
        Column {
          width: parent.width
          spacing: Style.space(8)

          readonly property var problems: root.checks.filter(function(c) { return c.status !== "ok" })

          PanelSectionHeader {
            text: "DIAGNOSTICS"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Text {
            visible: parent.problems.length === 0
            width: parent.width
            textFormat: Text.PlainText
            text: root.checks.length === 0 ? "Checking…" : "󰄬  All " + root.checks.length + " checks passed"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Repeater {
            model: parent.problems

            Column {
              required property var modelData
              width: settingsColumn.width
              spacing: Style.space(2)

              Text {
                width: parent.width
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: (modelData.status === "fail" ? "✗  " : "!  ") + modelData.name + (modelData.detail ? " — " + modelData.detail : "")
                color: modelData.status === "fail" ? root.bar.urgent : root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Text {
                visible: modelData.fix !== ""
                width: parent.width
                wrapMode: Text.WrapAnywhere
                textFormat: Text.PlainText
                text: modelData.fix
                color: root.bar.foreground
                opacity: 0.6
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          Row {
            spacing: Style.space(8)

            Button {
              text: "Re-run setup"
              iconText: "󰐊"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              onClicked: root.launchSetup()
            }

            Button {
              text: "Recheck"
              iconText: "󰑐"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              onClicked: root.refreshChecks()
            }
          }
        }
      }
    }
  }
}

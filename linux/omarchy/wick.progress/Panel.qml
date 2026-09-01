import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Omarchy bar widget: candle in the bar, progress paper as a system
// dropdown (qs.Ui.KeyboardPanel: wlr-layer-shell overlay), not a Hyprland window.
Panel {
  id: root
  moduleName: "wick.progress"
  ipcTarget: "wick.progress"

  property date now: new Date()
  property string language: "zh-Hans"
  readonly property bool isChinese: language !== "en" && !language.startsWith("en")

  function t(zh, en) {
    return isChinese ? zh : en
  }

  readonly property color foreground: Color.popups.text || Color.foreground
  readonly property color dim: Color.muted || Qt.rgba(foreground.r, foreground.g, foreground.b, 0.65)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color stain: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.25)
  readonly property color stainHot: Color.accent
  readonly property color cardBg: Color.popups.background
  readonly property color cardBorder: Color.popups.border

  property FileView langFile: FileView {
    id: langFile
    path: Quickshell.env("HOME") + "/.config/wick/language"
    watchChanges: true
    printErrors: false
    onLoaded: {
      var str = String(text() || "").trim()
      if (str.length > 0) root.language = str
    }
    onLoadFailed: {}
  }

  onOpenedChanged: {
    if (opened) langFile.reload()
  }

  Component.onCompleted: {
    langFile.reload()
  }

  function clamp01(x) {
    return Math.max(0, Math.min(1, x))
  }

  function remainingFrac(startMs, endMs, atMs) {
    var dur = endMs - startMs
    if (dur <= 0)
      return 0
    return clamp01((endMs - atMs) / dur)
  }

  function startOfDay(d) {
    return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
  }

  function addDays(d, n) {
    return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n)
  }

  readonly property real atMs: now.getTime()
  readonly property real dayStartMs: startOfDay(now)
  readonly property real dayEndMs: startOfDay(addDays(now, 1))
  readonly property var monday: addDays(now, -((now.getDay() + 6) % 7))
  readonly property real weekStartMs: startOfDay(monday)
  readonly property real weekEndMs: startOfDay(addDays(monday, 7))
  readonly property real monthStartMs: new Date(now.getFullYear(), now.getMonth(), 1).getTime()
  readonly property real monthEndMs: new Date(now.getFullYear(), now.getMonth() + 1, 1).getTime()
  readonly property real yearStartMs: new Date(now.getFullYear(), 0, 1).getTime()
  readonly property real yearEndMs: new Date(now.getFullYear() + 1, 0, 1).getTime()

  readonly property real dayRemaining: remainingFrac(dayStartMs, dayEndMs, atMs)
  readonly property real weekRemaining: remainingFrac(weekStartMs, weekEndMs, atMs)
  readonly property real monthRemaining: remainingFrac(monthStartMs, monthEndMs, atMs)
  readonly property real yearRemaining: remainingFrac(yearStartMs, yearEndMs, atMs)

  readonly property real dayElapsed: 1 - dayRemaining
  readonly property real weekElapsed: 1 - weekRemaining
  readonly property real monthElapsed: 1 - monthRemaining
  readonly property real yearElapsed: 1 - yearRemaining

  readonly property string dayPercentNumber: (dayRemaining * 100).toFixed(1)
  readonly property string weekPercentText: (weekRemaining * 100).toFixed(1) + "%"
  readonly property string monthPercentText: (monthRemaining * 100).toFixed(1) + "%"
  readonly property string yearPercentText: (yearRemaining * 100).toFixed(1) + "%"
  readonly property int monthTicks: new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      root.now = date
    }
  }

  Component {
    id: candleIcon
    Item {
      anchors.fill: parent
      Shape {
        anchors.centerIn: parent
        width: 18
        height: 18
        scale: Math.min(parent.width, parent.height) / 18
        transformOrigin: Item.Center
        antialiasing: true
        layer.enabled: true
        layer.samples: 4

        ShapePath {
          fillColor: root.barForeground
          strokeWidth: 0
          PathSvg {
            path: "M9 1.4 C7.6 3.1 6.6 4.6 6.6 6.1 C6.6 7.8 7.7 9 9 9 C10.3 9 11.4 7.8 11.4 6.1 C11.4 4.6 10.4 3.1 9 1.4 Z M8.5 9.2 H9.5 V11.2 H8.5 Z M5.6 11.2 L12.4 11.2 L12.8 15.6 Q12.85 16.6 11.6 16.6 L6.4 16.6 Q5.15 16.6 5.2 15.6 Z"
          }
        }
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.t("今日剩余 ", "Left today ") + root.dayPercentNumber + "%"
    iconComponent: candleIcon
    onPressed: function (buttonCode) {
      root.toggle()
    }
  }

  component BurnStrip: Item {
    id: strip
    property real elapsed: 0
    property int ticks: 24
    property bool showsFlame: false
    property int stripHeight: Style.space(12)

    implicitHeight: stripHeight
    height: stripHeight

    readonly property real fraction: Math.max(0, Math.min(1, strip.elapsed))
    readonly property real frontier: width * fraction
    readonly property bool isFrontierActive: fraction > 0.002

    Rectangle {
      id: baseTrack
      anchors.fill: parent
      radius: Style.space(3)
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
      clip: true

      Repeater {
        model: Math.max(strip.ticks, 1)
        Rectangle {
          required property int index
          width: 1
          height: parent.height
          x: (index / strip.ticks) * parent.width
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
          visible: index > 0
        }
      }

      Canvas {
        id: omStainCanvas
        anchors.fill: parent
        antialiasing: true
        visible: strip.isFrontierActive
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          ctx.clearRect(0, 0, width, height)
          var fx = width * strip.fraction
          if (fx <= 0.5) return
          var seed = 7
          function wobble(t) {
            return Math.sin(t * 9 + seed) * 1.05 + Math.sin(t * 23 + seed * 3.1) * 0.65 + Math.sin(t * 41 + seed * 1.7) * 0.35
          }
          ctx.beginPath()
          ctx.moveTo(0, 0)
          ctx.lineTo(fx + wobble(0), 0)
          var steps = 24
          for (var s = 1; s <= steps; s++) {
            var t = s / steps
            ctx.lineTo(fx + wobble(t), height * t)
          }
          ctx.lineTo(0, height)
          ctx.closePath()
          var grad = ctx.createLinearGradient(0, 0, fx, 0)
          grad.addColorStop(0.0, Qt.rgba(root.stainHot.r, root.stainHot.g, root.stainHot.b, 0.20))
          grad.addColorStop(1.0, Qt.rgba(root.stainHot.r, root.stainHot.g, root.stainHot.b, 0.55))
          ctx.fillStyle = grad
          ctx.fill()
        }
        Connections {
          target: strip
          function onFractionChanged() { omStainCanvas.requestPaint() }
          function onWidthChanged() { omStainCanvas.requestPaint() }
          function onHeightChanged() { omStainCanvas.requestPaint() }
        }
      }
    }

    // Outer enclosing frame
    Rectangle {
      anchors.fill: parent
      radius: Style.space(3)
      color: "transparent"
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
      border.width: 1
    }

    // Warm halo
    Canvas {
      id: omHaloCanvas
      property real haloSize: Math.max(strip.height * 2.8, 16)
      width: haloSize
      height: haloSize
      x: strip.frontier - width / 2
      y: (strip.height - height) / 2
      visible: strip.isFrontierActive
      antialiasing: true
      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        ctx.clearRect(0, 0, width, height)
        var cx = width / 2
        var cy = height / 2
        var r = width / 2
        var g = ctx.createRadialGradient(cx, cy, 0, cx, cy, r)
        g.addColorStop(0.0, Qt.rgba(root.stainHot.r, root.stainHot.g, root.stainHot.b, 0.4))
        g.addColorStop(1.0, "transparent")
        ctx.fillStyle = g
        ctx.beginPath()
        ctx.arc(cx, cy, r, 0, 2 * Math.PI)
        ctx.fill()
      }
      onWidthChanged: omHaloCanvas.requestPaint()
      onHeightChanged: omHaloCanvas.requestPaint()
    }

    // Ember line
    Item {
      visible: strip.isFrontierActive
      width: 2.5
      height: strip.height + 2
      x: strip.frontier - width / 2
      y: -1

      Rectangle {
        anchors.fill: parent
        radius: 1
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: Qt.rgba(root.stainHot.r, root.stainHot.g, root.stainHot.b, 0.25) }
          GradientStop { position: 0.5; color: root.stainHot }
          GradientStop { position: 1.0; color: root.foreground }
        }
      }
    }

    // Flame dot
    Item {
      id: omFlameContainer
      visible: strip.showsFlame && strip.isFrontierActive
      property real flameW: Math.max(8, Math.min(12, strip.height * 0.9))
      property real flameH: flameW * 1.15
      width: flameW
      height: flameH
      x: strip.frontier - width / 2
      y: (strip.height - height) / 2

      Canvas {
        id: omFlameCanvas
        anchors.fill: parent
        anchors.margins: -4
        antialiasing: true
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          ctx.clearRect(0, 0, width, height)
          var pad = 4
          var w = width - 2 * pad
          var h = height - 2 * pad
          ctx.save()
          ctx.translate(pad, pad)

          ctx.beginPath()
          ctx.moveTo(w * 0.5, 0)
          ctx.bezierCurveTo(w * -0.05, h * 0.42, w * 0.12, h * 0.8, w * 0.5, h)
          ctx.bezierCurveTo(w * 0.88, h * 0.8, w * 1.05, h * 0.42, w * 0.5, 0)
          ctx.closePath()

          var grad = ctx.createRadialGradient(w * 0.5, h * 0.35, 0, w * 0.5, h * 0.5, Math.max(w, h) * 0.65)
          grad.addColorStop(0.0, "#FFF0C7")
          grad.addColorStop(0.45, root.stainHot)
          grad.addColorStop(1.0, root.stainHot)

          ctx.shadowColor = root.stainHot
          ctx.shadowBlur = 5
          ctx.fillStyle = grad
          ctx.fill()
          ctx.restore()
        }
        onWidthChanged: omFlameCanvas.requestPaint()
        onHeightChanged: omFlameCanvas.requestPaint()
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(352))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) {
        root.switchPanel(direction)
      }

      Rectangle {
        anchors.fill: parent
        anchors.margins: -Style.spacing.popupPadding
        color: Color.background
        radius: Style.cornerRadius
        z: -2
      }

      Rectangle {
        anchors.fill: parent
        anchors.margins: -Style.spacing.popupPadding
        color: root.cardBg
        border.color: root.cardBorder
        border.width: 1
        radius: Style.cornerRadius
        z: -1
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            text: root.t("今日剩余", "Left today")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
            anchors.verticalCenter: parent.verticalCenter
          }

          Item {
            width: Math.max(0, parent.width - parent.children[0].width - parent.children[2].width - parent.spacing * 2)
            height: 1
          }

          Row {
            spacing: 2
            anchors.verticalCenter: parent.verticalCenter
            Text {
              text: root.dayPercentNumber
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              font.bold: true
            }
            Text {
              text: "%"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              anchors.baseline: parent.children[0].baseline
            }
          }
        }

        BurnStrip {
          width: parent.width
          stripHeight: Style.space(34)
          elapsed: root.dayElapsed
          ticks: 24
          showsFlame: true
        }

        Row {
          width: parent.width
          Text {
            text: "00:00"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Item {
            width: Math.max(0, parent.width - parent.children[0].width - parent.children[2].width)
            height: 1
          }
          Text {
            text: root.t("24:00 终", "24:00 End")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(11)

          Row {
            width: parent.width
            spacing: Style.space(12)
            Text {
              text: root.t("本周", "Week")
              width: root.isChinese ? Style.space(30) : Style.space(42)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }
            BurnStrip {
              width: parent.width - (root.isChinese ? Style.space(30) : Style.space(42)) - Style.space(44) - parent.spacing * 2
              elapsed: root.weekElapsed
              ticks: 7
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              text: root.weekPercentText
              width: Style.space(44)
              horizontalAlignment: Text.AlignRight
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(12)
            Text {
              text: root.t("本月", "Month")
              width: root.isChinese ? Style.space(30) : Style.space(42)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }
            BurnStrip {
              width: parent.width - (root.isChinese ? Style.space(30) : Style.space(42)) - Style.space(44) - parent.spacing * 2
              elapsed: root.monthElapsed
              ticks: root.monthTicks
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              text: root.monthPercentText
              width: Style.space(44)
              horizontalAlignment: Text.AlignRight
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(12)
            Text {
              text: root.t("今年", "Year")
              width: root.isChinese ? Style.space(30) : Style.space(42)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }
            BurnStrip {
              width: parent.width - (root.isChinese ? Style.space(30) : Style.space(42)) - Style.space(44) - parent.spacing * 2
              elapsed: root.yearElapsed
              ticks: 12
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              text: root.yearPercentText
              width: Style.space(44)
              horizontalAlignment: Text.AlignRight
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }

        Row {
          width: parent.width
          Text {
            text: root.t("一寸光阴一寸金。", "Time is precious.")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
        }

        // Design contract: linux.html `.pp-actions` — 打开日记 / 设置 / 退出.
        Row {
          id: actionRow
          width: parent.width
          spacing: Style.space(8)
          readonly property real cellWidth: (width - spacing * 2) / 3

          Button {
            width: actionRow.cellWidth
            text: root.t("打开日记", "Open Journal")
            bordered: true
            active: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            onClicked: root.launchWick("journal")
          }
          Button {
            width: actionRow.cellWidth
            text: root.t("设置", "Settings")
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            onClicked: root.launchWick("settings")
          }
          Button {
            width: actionRow.cellWidth
            text: root.t("退出", "Quit")
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            onClicked: root.launchWick("quit")
          }
        }
      }
    }
  }

  function launchWick(mode) {
    root.close()
    Quickshell.execDetached([
      "bash",
      "-lc",
      'bin=$(cat "$HOME/.local/share/wick/current-executable" 2>/dev/null); ' +
      'if [ ! -x "$bin" ]; then bin=$(command -v wick); fi; ' +
      'if [ ! -x "$bin" ]; then exit 1; fi; ' +
      'exec "$bin" --' + mode
    ])
  }
}

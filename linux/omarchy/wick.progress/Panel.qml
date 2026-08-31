import QtQuick
import QtQuick.Effects
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

  readonly property color barIconColor: (bar && bar.barForeground !== undefined) ? bar.barForeground : ((bar && bar.foreground !== undefined) ? bar.foreground : Color.foreground)
  readonly property color foreground: Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color stain: Qt.darker(foreground, 2.4)
  readonly property color stainHot: Color.accent

  property FileView langFile: FileView {
    id: langFile
    path: Quickshell.env("HOME") + "/.config/wick/language"
    watchChanges: true
    printErrors: false
    onLoaded: {
      var str = String(text() || "").trim()
      if (str.length > 0) root.language = str
    }
    onFileChanged: reload()
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
      langProcess.running = true
    }
  }

  Component {
    id: candleIcon
    Item {
      Image {
        id: candleImage
        anchors.fill: parent
        source: Qt.resolvedUrl("candle.svg")
        fillMode: Image.PreserveAspectFit
        sourceSize.width: Math.round(width * Screen.devicePixelRatio)
        sourceSize.height: Math.round(height * Screen.devicePixelRatio)
        visible: false
        layer.enabled: true
      }
      MultiEffect {
        anchors.fill: candleImage
        source: candleImage
        colorization: 1.0
        colorizationColor: root.barIconColor
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
    property int stripHeight: Style.space(12)

    implicitHeight: stripHeight
    height: stripHeight

    Rectangle {
      anchors.fill: parent
      radius: Style.space(3)
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
      border.width: 1
      clip: true

      Repeater {
        model: Math.max(strip.ticks, 1)
        Rectangle {
          required property int index
          width: 1
          height: parent.height
          x: (index / strip.ticks) * parent.width
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
          visible: index > 0
        }
      }

      Rectangle {
        id: charFill
        width: Math.max(0, Math.min(1, strip.elapsed)) * parent.width
        height: parent.height
        color: Qt.rgba(root.stainHot.r, root.stainHot.g, root.stainHot.b, 0.45)
      }

      Rectangle {
        visible: strip.elapsed > 0.002 && strip.elapsed < 0.998
        width: 3
        height: parent.height
        x: charFill.width - 1
        color: root.stainHot
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

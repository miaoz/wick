import QtQuick
import QtQuick.Layouts
import "journal"

// Paper slip — layout contract from designs/wick-design-language/linux.html
// `.wick-pop` (width 352). Stage 0: no Dropbox row, no journal/settings
// buttons (those live on the tray context menu). Keep the motto.

Rectangle {
    id: paper
    width: 352
    implicitWidth: 352
    implicitHeight: Math.max(content.implicitHeight, 200)
    height: implicitHeight

    Theme { id: theme }

    color: theme.paper
    border.color: theme.rule
    border.width: 1

    readonly property color ink1: theme.ink1
    readonly property color ink2: theme.ink2
    readonly property color ink3: theme.ink3
    readonly property color paperHi: theme.paperHi
    readonly property color stain1: theme.stain1
    readonly property color stain2: theme.stain2
    readonly property color ember: theme.ember
    readonly property color emberHi: theme.emberHi
    readonly property color glow: theme.glow

    readonly property string fontUi: theme.fontUi
    readonly property string fontPrint: theme.fontPrint
    readonly property string fontMono: theme.fontMono

    component BurnStrip: Item {
        id: strip
        property real elapsed: 0
        property int ticks: 24
        property bool showEmber: true

        Rectangle {
            anchors.fill: parent
            radius: 3
            color: paper.paperHi
            border.color: Qt.rgba(240 / 255, 227 / 255, 198 / 255, 0.14)
            border.width: 1
            clip: true

            // Remaining paper ticks (刻度).
            Repeater {
                model: Math.max(strip.ticks, 1)
                Rectangle {
                    required property int index
                    width: 1
                    height: parent.height
                    x: (index / strip.ticks) * parent.width
                    color: Qt.rgba(240 / 255, 227 / 255, 198 / 255, 0.14)
                    visible: index > 0
                }
            }

            // Elapsed = 烛光烘过的渍. No flame animation in stage 0.
            Rectangle {
                id: charFill
                width: Math.max(0, Math.min(1, strip.elapsed)) * parent.width
                height: parent.height
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: paper.stain1 }
                    GradientStop { position: 0.55; color: paper.stain1 }
                    GradientStop { position: 1.0; color: paper.stain2 }
                }
            }

            Rectangle {
                visible: strip.showEmber && strip.elapsed > 0.002 && strip.elapsed < 0.998
                width: 3
                height: parent.height + 2
                y: -1
                x: charFill.width - 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.45; color: "#FFB25E" }
                    GradientStop { position: 1.0; color: "#FFE0A8" }
                }
            }
        }
    }

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 18
            Layout.rightMargin: 18
            Layout.topMargin: 16
            Layout.bottomMargin: 6
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "今日剩余"
                    color: paper.ink2
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.3
                    font.family: paper.fontUi
                }

                Item { Layout.fillWidth: true }

                Row {
                    spacing: 2
                    Text {
                        text: timeProgress.dayPercentNumber
                        color: paper.ink1
                        font.pixelSize: 32
                        font.weight: Font.Black
                        font.family: paper.fontUi
                    }
                    Text {
                        text: "%"
                        color: paper.ink2
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        font.family: paper.fontUi
                        anchors.baseline: parent.children[0].baseline
                    }
                }
            }

            BurnStrip {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                elapsed: timeProgress.dayElapsed
                ticks: 24
                showEmber: true
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "00:00"
                    color: paper.ink3
                    font.pixelSize: 10
                    font.family: paper.fontMono
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: "24:00 终"
                    color: paper.ink3
                    font.pixelSize: 10
                    font.family: paper.fontMono
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 18
            Layout.rightMargin: 18
            Layout.topMargin: 12
            Layout.bottomMargin: 4
            spacing: 11

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Text {
                    text: "本周"
                    color: paper.ink2
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.family: paper.fontUi
                    Layout.preferredWidth: 30
                }
                BurnStrip {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 12
                    elapsed: timeProgress.weekElapsed
                    ticks: 7
                    showEmber: true
                }
                Text {
                    text: timeProgress.weekPercentText
                    color: paper.ink2
                    font.pixelSize: 11
                    font.family: paper.fontMono
                    horizontalAlignment: Text.AlignRight
                    Layout.preferredWidth: 44
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Text {
                    text: "本月"
                    color: paper.ink2
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.family: paper.fontUi
                    Layout.preferredWidth: 30
                }
                BurnStrip {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 12
                    elapsed: timeProgress.monthElapsed
                    ticks: timeProgress.monthTicks
                    showEmber: true
                }
                Text {
                    text: timeProgress.monthPercentText
                    color: paper.ink2
                    font.pixelSize: 11
                    font.family: paper.fontMono
                    horizontalAlignment: Text.AlignRight
                    Layout.preferredWidth: 44
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Text {
                    text: "今年"
                    color: paper.ink2
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.family: paper.fontUi
                    Layout.preferredWidth: 30
                }
                BurnStrip {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 12
                    elapsed: timeProgress.yearElapsed
                    ticks: 12
                    showEmber: true
                }
                Text {
                    text: timeProgress.yearPercentText
                    color: paper.ink2
                    font.pixelSize: 11
                    font.family: paper.fontMono
                    horizontalAlignment: Text.AlignRight
                    Layout.preferredWidth: 44
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 18
            Layout.rightMargin: 18
            Layout.topMargin: 2
            Layout.bottomMargin: 14

            Text {
                text: "一寸光阴一寸金"
                color: paper.ink3
                font.pixelSize: 11
                font.family: paper.fontPrint
            }
        }
        }
    }
}

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
                    text: (appSettings && appSettings.isChinese) ? "今日剩余" : "Left today"
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
                showsFlame: true
                theme: theme
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
                    text: (appSettings && appSettings.isChinese) ? "24:00 终" : "24:00 End"
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
                    text: (appSettings && appSettings.isChinese) ? "本周" : "Week"
                    color: paper.ink2
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.family: paper.fontUi
                    Layout.preferredWidth: (appSettings && appSettings.isChinese) ? 30 : 40
                }
                BurnStrip {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 12
                    elapsed: timeProgress.weekElapsed
                    ticks: 7
                    theme: theme
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
                    text: (appSettings && appSettings.isChinese) ? "本月" : "Month"
                    color: paper.ink2
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.family: paper.fontUi
                    Layout.preferredWidth: (appSettings && appSettings.isChinese) ? 30 : 40
                }
                BurnStrip {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 12
                    elapsed: timeProgress.monthElapsed
                    ticks: timeProgress.monthTicks
                    theme: theme
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
                    text: (appSettings && appSettings.isChinese) ? "今年" : "Year"
                    color: paper.ink2
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.family: paper.fontUi
                    Layout.preferredWidth: (appSettings && appSettings.isChinese) ? 30 : 40
                }
                BurnStrip {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 12
                    elapsed: timeProgress.yearElapsed
                    ticks: 12
                    theme: theme
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
                text: (appSettings && appSettings.isChinese) ? "一寸光阴一寸金。" : "Time is precious."
                color: paper.ink3
                font.pixelSize: 11
                font.family: paper.fontPrint
            }
        }
    }
}

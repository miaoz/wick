import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: list
    required property var theme
    required property var library
    color: theme.paper

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Text {
            visible: library.days.length === 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: library.searchText.length > 0 ? "无匹配条目" : "还没有日记\n点 ＋ 写下今天"
            color: theme.ink3
            font.family: theme.fontPrint
            font.pixelSize: 13
            wrapMode: Text.Wrap
        }

        ListView {
            visible: library.days.length > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: library.days
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Item {
                required property var modelData
                width: ListView.view.width
                height: (modelData.showMonthHeader ? 28 : 0) + 52

                Column {
                    anchors.fill: parent

                    Item {
                        width: parent.width
                        height: modelData.showMonthHeader ? 28 : 0
                        visible: modelData.showMonthHeader
                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 4
                            spacing: 6
                            Text {
                                text: modelData.monthLabel
                                color: theme.ink1
                                font.family: theme.fontPrint
                                font.pixelSize: 12
                                font.weight: Font.Bold
                            }
                            Text {
                                text: "" + modelData.year
                                color: theme.ink3
                                font.family: theme.fontMono
                                font.pixelSize: 10
                                anchors.baseline: parent.children[0].baseline
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 52
                        color: modelData.isSelected ? theme.paperHi : "transparent"

                        Rectangle {
                            visible: modelData.isSelected
                            width: 3
                            height: parent.height
                            color: theme.cinnabar
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 12
                            spacing: 8

                            Column {
                                Layout.fillWidth: true
                                spacing: 2
                                Row {
                                    spacing: 6
                                    Text {
                                        text: modelData.dateLabel
                                        color: theme.ink1
                                        font.family: theme.fontUi
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                    }
                                    Text {
                                        text: modelData.weekday
                                        color: theme.ink3
                                        font.family: theme.fontUi
                                        font.pixelSize: 11
                                        anchors.baseline: parent.children[0].baseline
                                    }
                                }
                                Text {
                                    text: modelData.itemCount + " 条"
                                    color: theme.ink3
                                    font.family: theme.fontMono
                                    font.pixelSize: 10
                                }
                            }

                            Row {
                                spacing: 3
                                Text {
                                    visible: modelData.hasCorrect
                                    text: "✓"
                                    color: theme.gain
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                }
                                Text {
                                    visible: modelData.hasWrong
                                    text: "✗"
                                    color: theme.loss
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                }
                            }
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 1
                            color: Qt.rgba(240 / 255, 227 / 255, 198 / 255, 0.08)
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: library.selectDay(modelData.entryId)
                        }
                    }
                }
            }
        }
    }
}

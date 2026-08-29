import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: insp
    required property var theme
    required property var library
    color: theme.paper

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
            id: col
            width: parent.width
            spacing: 0

            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                Layout.topMargin: 10
                Layout.bottomMargin: 12
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "今日事件"
                        color: theme.ink1
                        font.family: "Noto Serif SC"
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }
                    Text {
                        text: library.todayWeekday
                        color: theme.ink3
                        font.family: "JetBrains Mono"
                        font.pixelSize: 9
                    }
                    Item { Layout.fillWidth: true }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        text: library.todayDateLabel
                        color: theme.ink1
                        font.family: "Inter, Noto Serif SC"
                        font.pixelSize: 21
                        font.weight: Font.Black
                    }
                    Text {
                        text: library.todayLunar
                        color: theme.ink2
                        font.family: "Noto Serif SC"
                        font.pixelSize: 10
                        visible: library.todayLunar.length > 0
                    }
                    Item { Layout.fillWidth: true }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    Layout.topMargin: 8
                    Rectangle {
                        anchors.centerIn: parent
                        width: idleLabel.implicitWidth + 24
                        height: idleLabel.implicitHeight + 12
                        radius: 3
                        color: "transparent"
                        border.color: Qt.rgba(224 / 255, 106 / 255, 76 / 255, 0.75)
                        border.width: 1
                        rotation: -3
                        Text {
                            id: idleLabel
                            anchors.centerIn: parent
                            text: library.todayIsWeekend ? "休市" : "本日无事"
                            color: Qt.rgba(224 / 255, 106 / 255, 76 / 255, 0.85)
                            font.family: "Noto Serif SC"
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            font.letterSpacing: 2
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: "宏观 / 财报未接入（WickCalendarKit 未移植）"
                    color: theme.ink3
                    font.family: "Noto Sans SC"
                    font.pixelSize: 10
                    wrapMode: Text.Wrap
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: theme.rule
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                Layout.topMargin: 10
                Layout.bottomMargin: 12
                spacing: 8

                Text {
                    text: "盈亏月历"
                    color: theme.ink1
                    font.family: "Noto Serif SC"
                    font.pixelSize: 12
                    font.weight: Font.Bold
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "‹"
                        color: theme.ink2
                        font.pixelSize: 16
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -8
                            cursorShape: Qt.PointingHandCursor
                            onClicked: library.shiftCalendarMonth(-1)
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: library.calendarMonthLabel
                        color: theme.ink1
                        font.family: "Noto Serif SC"
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "›"
                        color: theme.ink2
                        font.pixelSize: 16
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -8
                            cursorShape: Qt.PointingHandCursor
                            onClicked: library.shiftCalendarMonth(1)
                        }
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 7
                    columnSpacing: 3
                    rowSpacing: 3

                    Repeater {
                        model: ["一", "二", "三", "四", "五", "六", "日"]
                        Text {
                            required property string modelData
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData
                            color: theme.ink3
                            font.family: "Noto Sans SC"
                            font.pixelSize: 9
                        }
                    }

                    Repeater {
                        model: library.calendarDays
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 24
                            radius: 4
                            color: {
                                if (modelData.state === "up")
                                    return theme.gainSoft
                                if (modelData.state === "down")
                                    return theme.lossSoft
                                if (modelData.state === "journaled")
                                    return theme.stain1
                                return "transparent"
                            }
                            border.color: modelData.isToday ? theme.ember : "transparent"
                            border.width: modelData.isToday ? 1.5 : 0
                            opacity: modelData.isFuture ? 0.4 : 1

                            Text {
                                anchors.centerIn: parent
                                text: modelData.dayNumber
                                font.family: "JetBrains Mono"
                                font.pixelSize: 10
                                font.weight: modelData.isToday ? Font.Black : Font.Medium
                                color: {
                                    if (!modelData.inMonth)
                                        return "transparent"
                                    if (modelData.isToday)
                                        return theme.ink1
                                    if (modelData.state === "up")
                                        return theme.gain
                                    if (modelData.state === "down")
                                        return theme.loss
                                    if (modelData.state === "journaled")
                                        return theme.ink2
                                    return theme.ink3
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: modelData.hasEntry === true
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: library.selectCalendarDay(modelData.dayKey)
                            }
                        }
                    }
                }
            }
        }
    }
}

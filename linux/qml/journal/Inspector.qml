import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: insp
    required property var theme
    required property var library
    color: theme.paper
    property string eventTab: "macro"
    property bool sortImportance: false

    Component.onCompleted: if (typeof calendarStore !== "undefined" && calendarStore)
                               calendarStore.loadIfNeeded()

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
                        font.family: theme.fontPrint
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }
                    Text {
                        text: library.todayWeekday
                        color: theme.ink3
                        font.family: theme.fontMono
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
                        font.family: theme.fontPrint
                        font.pixelSize: 21
                        font.weight: Font.Black
                    }
                    Text {
                        text: library.todayLunar
                        color: theme.ink2
                        font.family: theme.fontPrint
                        font.pixelSize: 10
                        visible: library.todayLunar.length > 0
                    }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        visible: calendarStore && calendarStore.seal.length > 0
                        width: sealLab.implicitWidth + 10
                        height: 22
                        radius: 2
                        rotation: -3
                        color: theme.pnlUp
                        Text {
                            id: sealLab
                            anchors.centerIn: parent
                            text: calendarStore ? calendarStore.seal : ""
                            color: "#FAEBD7"
                            font.family: theme.fontPrint
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            font.letterSpacing: 1
                        }
                    }
                }

                Row {
                    spacing: 4
                    Rectangle {
                        width: yiMark.implicitWidth + 10
                        height: 16
                        radius: 2
                        color: theme.pnlUp
                        Text {
                            id: yiMark
                            anchors.centerIn: parent
                            text: "宜"
                            color: "#FAEBD7"
                            font.family: theme.fontPrint
                            font.pixelSize: 9
                            font.weight: Font.Bold
                        }
                    }
                    Text {
                        text: calendarStore ? calendarStore.yi : ""
                        color: theme.ink2
                        font.family: theme.fontPrint
                        font.pixelSize: 10
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Row {
                    spacing: 4
                    Rectangle {
                        width: jiMark.implicitWidth + 10
                        height: 16
                        radius: 2
                        color: theme.ink1
                        Text {
                            id: jiMark
                            anchors.centerIn: parent
                            text: "忌"
                            color: theme.paper
                            font.family: theme.fontPrint
                            font.pixelSize: 9
                            font.weight: Font.Bold
                        }
                    }
                    Text {
                        text: calendarStore ? calendarStore.ji : ""
                        color: theme.ink2
                        font.family: theme.fontPrint
                        font.pixelSize: 10
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Text {
                    visible: calendarStore && (calendarStore.lucky.length > 0 || calendarStore.sha.length > 0)
                    Layout.fillWidth: true
                    text: {
                        if (!calendarStore)
                            return ""
                        var bits = []
                        if (calendarStore.lucky.length > 0)
                            bits.push("吉神 " + calendarStore.lucky)
                        if (calendarStore.sha.length > 0)
                            bits.push("煞方 " + calendarStore.sha)
                        return bits.join("  ·  ")
                    }
                    color: theme.ink3
                    font.family: theme.fontPrint
                    font.pixelSize: 9
                    elide: Text.ElideRight
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [
                            { id: "macro", label: "宏观" },
                            { id: "earnings", label: "财报" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            height: 20
                            width: tabLab.implicitWidth + 18
                            radius: 2
                            color: insp.eventTab === modelData.id ? theme.pnlUp : "transparent"
                            border.color: theme.pnlUp
                            border.width: 1
                            Text {
                                id: tabLab
                                anchors.centerIn: parent
                                text: modelData.label
                                color: insp.eventTab === modelData.id ? "#FAEBD7" : theme.pnlUp
                                font.family: theme.fontPrint
                                font.pixelSize: 10
                                font.weight: insp.eventTab === modelData.id ? Font.Bold : Font.Medium
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: insp.eventTab = modelData.id
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        visible: insp.eventTab === "macro"
                        text: insp.sortImportance ? "按重要" : "按时间"
                        color: theme.ink3
                        font.family: theme.fontPrint
                        font.pixelSize: 9
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                insp.sortImportance = !insp.sortImportance
                                if (calendarStore)
                                    calendarStore.setSortByImportance(insp.sortImportance)
                            }
                        }
                    }
                }

                Text {
                    visible: calendarStore && calendarStore.loading
                    text: "加载中…"
                    color: theme.ink3
                    font.family: theme.fontUi
                    font.pixelSize: 11
                }
                Text {
                    visible: calendarStore && calendarStore.error.length > 0 && !calendarStore.loading
                    text: calendarStore ? calendarStore.error : ""
                    color: theme.cinnabar
                    font.family: theme.fontUi
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                ColumnLayout {
                    visible: insp.eventTab === "macro" && calendarStore && !calendarStore.loading
                    Layout.fillWidth: true
                    spacing: 0
                    Repeater {
                        model: calendarStore ? calendarStore.events : []
                        delegate: Item {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: evCol.implicitHeight + 8
                            Column {
                                id: evCol
                                width: parent.width
                                spacing: 2
                                Row {
                                    spacing: 7
                                    Text {
                                        width: 34
                                        text: modelData.time
                                        color: theme.pnlUp
                                        font.family: theme.fontMono
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                    }
                                    Text {
                                        width: 32
                                        text: modelData.country
                                        color: theme.ink2
                                        font.family: theme.fontPrint
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        width: Math.max(40, evCol.width - 34 - 32 - 7 * 2)
                                        text: modelData.title
                                        color: theme.ink1
                                        font.family: theme.fontPrint
                                        font.pixelSize: 11
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                    }
                                }
                                Text {
                                    visible: modelData.values.length > 0
                                    text: modelData.values
                                    color: theme.ink3
                                    font.family: theme.fontMono
                                    font.pixelSize: 9
                                    leftPadding: 41
                                }
                            }
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 1
                                color: theme.rule
                                opacity: 0.7
                            }
                        }
                    }
                    Item {
                        visible: calendarStore && calendarStore.events.length === 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        Layout.topMargin: 8
                        Rectangle {
                            anchors.centerIn: parent
                            width: idleMacro.implicitWidth + 24
                            height: 28
                            radius: 3
                            rotation: -3
                            color: "transparent"
                            border.color: theme.pnlUp
                            border.width: 1
                            Text {
                                id: idleMacro
                                anchors.centerIn: parent
                                text: calendarStore && calendarStore.isWeekend ? "休市" : "本日无事"
                                color: theme.pnlUp
                                font.family: theme.fontPrint
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                font.letterSpacing: 2
                            }
                        }
                    }
                }

                ColumnLayout {
                    visible: insp.eventTab === "earnings" && calendarStore && !calendarStore.loading
                    Layout.fillWidth: true
                    spacing: 0
                    Repeater {
                        model: calendarStore ? calendarStore.earnings : []
                        delegate: Item {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 28
                            Row {
                                anchors.fill: parent
                                spacing: 7
                                Text {
                                    width: 30
                                    text: modelData.mark
                                    color: theme.pnlUp
                                    font.family: theme.fontPrint
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: modelData.code
                                    color: theme.ink1
                                    font.family: theme.fontMono
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    width: Math.max(40, parent.width - 160)
                                    text: modelData.company
                                    color: theme.ink1
                                    font.family: theme.fontPrint
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: modelData.eps
                                    color: theme.ink3
                                    font.family: theme.fontMono
                                    font.pixelSize: 9
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 1
                                color: theme.rule
                                opacity: 0.7
                            }
                        }
                    }
                    Item {
                        visible: calendarStore && calendarStore.earnings.length === 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        Rectangle {
                            anchors.centerIn: parent
                            width: idleEarn.implicitWidth + 24
                            height: 28
                            radius: 3
                            rotation: -3
                            color: "transparent"
                            border.color: theme.pnlUp
                            border.width: 1
                            Text {
                                id: idleEarn
                                anchors.centerIn: parent
                                text: "本日无事"
                                color: theme.pnlUp
                                font.family: theme.fontPrint
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                font.letterSpacing: 2
                            }
                        }
                    }
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
                    font.family: theme.fontPrint
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
                        font.family: theme.fontPrint
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
                            font.family: theme.fontUi
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
                                font.family: theme.fontMono
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

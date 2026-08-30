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
    property bool eventsCollapsed: false
    property bool pnlCollapsed: false
    property var expandedEventIds: ({})
    property var expandedEarningIds: ({})

    Component.onCompleted: if (typeof calendarStore !== "undefined" && calendarStore)
                               calendarStore.loadIfNeeded()

    // Reusable Events & Almanac Content component
    component EventsContent: ColumnLayout {
        id: evContent
        property bool isFullHeight: false
        Layout.fillWidth: true
        Layout.leftMargin: 14
        Layout.rightMargin: 14
        Layout.bottomMargin: 12
        spacing: 8

        // 报头：大日期 + 农历 + 右上角朱砂方印
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
                width: sealLab.implicitWidth + 8
                height: 18
                radius: 3
                rotation: -3
                color: "transparent"
                border.color: theme.pnlUp
                border.width: 1.2
                opacity: 0.9

                Text {
                    id: sealLab
                    anchors.centerIn: parent
                    text: calendarStore ? calendarStore.seal : ""
                    color: theme.pnlUp
                    font.family: theme.fontPrint
                    font.pixelSize: 9
                    font.weight: Font.Black
                    font.letterSpacing: 1
                }
            }
        }

        // 宜忌双行
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

        // 吉神 / 煞方行
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

        // 栏目签条：宏观 / 财报 + 排序按钮
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
            Rectangle {
                visible: insp.eventTab === "macro"
                height: 20
                radius: 2
                color: sortMouse.containsMouse ? Qt.rgba(100 / 255, 100 / 255, 100 / 255, 0.08) : "transparent"
                border.color: theme.rule
                border.width: 1
                implicitWidth: sortRow.implicitWidth + 12

                RowLayout {
                    id: sortRow
                    anchors.centerIn: parent
                    spacing: 3
                    Text {
                        text: insp.sortImportance ? "★" : "🕒"
                        font.pixelSize: 8
                        color: theme.ink3
                    }
                    Text {
                        text: insp.sortImportance ? "按重要" : "按时间"
                        color: theme.ink2
                        font.family: theme.fontPrint
                        font.pixelSize: 10
                        font.weight: Font.Medium
                    }
                }

                MouseArea {
                    id: sortMouse
                    anchors.fill: parent
                    hoverEnabled: true
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

        // 宏观列表
        ColumnLayout {
            visible: insp.eventTab === "macro" && calendarStore && !calendarStore.loading
            Layout.fillWidth: true
            spacing: 0

            readonly property int totalCount: calendarStore ? calendarStore.events.length : 0
            readonly property int rowLimit: evContent.isFullHeight ? totalCount : 8
            readonly property var visibleItems: {
                if (!calendarStore || !calendarStore.events) return []
                return calendarStore.events.slice(0, rowLimit)
            }

            Repeater {
                model: parent.visibleItems
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
                                maximumLineCount: insp.expandedEventIds[modelData.id] ? 99 : 2
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

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var map = Object.assign({}, insp.expandedEventIds)
                            map[modelData.id] = !map[modelData.id]
                            insp.expandedEventIds = map
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

            // 展开更多 / 更多项标签（点击可折叠月历展开全部事件）
            Text {
                visible: parent.totalCount > parent.rowLimit
                Layout.fillWidth: true
                Layout.topMargin: 4
                horizontalAlignment: Text.AlignRight
                text: "还有 " + (parent.totalCount - parent.rowLimit) + " 项 ›"
                color: theme.pnlUp
                font.family: theme.fontPrint
                font.pixelSize: 10
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: insp.pnlCollapsed = true
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
                    border.width: 1.2
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

        // 财报列表
        ColumnLayout {
            visible: insp.eventTab === "earnings" && calendarStore && !calendarStore.loading
            Layout.fillWidth: true
            spacing: 0

            readonly property int totalCount: calendarStore ? calendarStore.earnings.length : 0
            readonly property int rowLimit: evContent.isFullHeight ? totalCount : 8
            readonly property var visibleItems: {
                if (!calendarStore || !calendarStore.earnings) return []
                return calendarStore.earnings.slice(0, rowLimit)
            }

            Repeater {
                model: parent.visibleItems
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
                            maximumLineCount: insp.expandedEarningIds[modelData.id] ? 99 : 1
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

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var map = Object.assign({}, insp.expandedEarningIds)
                            map[modelData.id] = !map[modelData.id]
                            insp.expandedEarningIds = map
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

            Text {
                visible: parent.totalCount > parent.rowLimit
                Layout.fillWidth: true
                Layout.topMargin: 4
                horizontalAlignment: Text.AlignRight
                text: "还有 " + (parent.totalCount - parent.rowLimit) + " 项 ›"
                color: theme.pnlUp
                font.family: theme.fontPrint
                font.pixelSize: 10
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: insp.pnlCollapsed = true
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
                    border.width: 1.2
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

    // Reusable Month PnL Calendar Content component
    component PnlCalendarContent: ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 14
        Layout.rightMargin: 14
        Layout.bottomMargin: 12
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Rectangle {
                width: 22
                height: 22
                radius: 3
                color: prevMonthHover.containsMouse ? Qt.rgba(100 / 255, 100 / 255, 100 / 255, 0.1) : "transparent"
                WickIcon {
                    anchors.centerIn: parent
                    name: "chevron.left"
                    size: 11
                    color: theme.ink2
                }
                MouseArea {
                    id: prevMonthHover
                    anchors.fill: parent
                    hoverEnabled: true
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
            Rectangle {
                width: 22
                height: 22
                radius: 3
                color: nextMonthHover.containsMouse ? Qt.rgba(100 / 255, 100 / 255, 100 / 255, 0.1) : "transparent"
                WickIcon {
                    anchors.centerIn: parent
                    name: "chevron.right"
                    size: 11
                    color: theme.ink2
                }
                MouseArea {
                    id: nextMonthHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: library.shiftCalendarMonth(1)
                }
            }
        }

        // Month Total Realized PnL Row
        RowLayout {
            Layout.fillWidth: true
            visible: library.hasCalendarMonthPnl
            Text {
                text: "已实现合计"
                color: theme.ink3
                font.family: theme.fontMono
                font.pixelSize: 10
            }
            Item { Layout.fillWidth: true }
            Text {
                text: library.calendarMonthPnlText
                color: library.calendarMonthPnl >= 0 ? theme.gain : theme.loss
                font.family: theme.fontMono
                font.pixelSize: 13
                font.weight: Font.Bold
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

    // =========================================================================
    // Root Layout: Top Header + Dynamic Middle Body + Bottom PnL Header
    // =========================================================================
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // 1. 交易日历 Header (Always pinned at top)
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            color: "transparent"
            z: 2

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 8

                Text {
                    text: "交易日历"
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
                WickIcon {
                    name: insp.eventsCollapsed ? "chevron.right" : "chevron.down"
                    size: 9
                    color: theme.ink3
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: insp.eventsCollapsed = !insp.eventsCollapsed
            }
        }

        // 2. Middle Body:
        // A) When pnlCollapsed is TRUE: events takes 100% of remaining height, scrolling all items!
        Flickable {
            visible: insp.pnlCollapsed && !insp.eventsCollapsed
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: fullEventsCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: fullEventsCol
                width: parent.width
                spacing: 0
                EventsContent {
                    isFullHeight: true
                }
            }
        }

        // B) When both collapsed: fill empty space
        Item {
            visible: insp.eventsCollapsed && insp.pnlCollapsed
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        // C) When pnlCollapsed is FALSE: scroll view containing events + divider + pnl
        Flickable {
            visible: !insp.pnlCollapsed
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: normalContentCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: normalContentCol
                width: parent.width
                spacing: 0

                // Events section (when !eventsCollapsed)
                EventsContent {
                    visible: !insp.eventsCollapsed
                    isFullHeight: false
                }

                Rectangle {
                    visible: !insp.eventsCollapsed
                    Layout.fillWidth: true
                    height: 1
                    color: theme.rule
                }

                // 月度总览 Header inside normal flow
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    color: "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 8

                        Text {
                            text: "月度总览"
                            color: theme.ink1
                            font.family: theme.fontPrint
                            font.pixelSize: 12
                            font.weight: Font.Bold
                        }
                        Item { Layout.fillWidth: true }
                        WickIcon {
                            name: "chevron.down"
                            size: 9
                            color: theme.ink3
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: insp.pnlCollapsed = true
                    }
                }

                // 月度总览 Content
                PnlCalendarContent {}
            }
        }

        // 3. PnL Header pinned at bottom when pnlCollapsed is TRUE
        Rectangle {
            visible: insp.pnlCollapsed
            Layout.fillWidth: true
            height: 1
            color: theme.rule
        }

        Rectangle {
            visible: insp.pnlCollapsed
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            color: "transparent"
            z: 2

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 8

                Text {
                    text: "月度总览"
                    color: theme.ink1
                    font.family: theme.fontPrint
                    font.pixelSize: 12
                    font.weight: Font.Bold
                }
                Item { Layout.fillWidth: true }
                WickIcon {
                    name: "chevron.right"
                    size: 9
                    color: theme.ink3
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: insp.pnlCollapsed = false
            }
        }
    }
}

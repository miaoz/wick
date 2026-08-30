import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: nav
    required property var theme
    required property var library
    color: theme.sidebar

    property int draggingIndex: -1
    property int dropTargetIndex: -1
    property bool dropAbove: true

    signal newJournalRequested()
    signal renameJournalRequested(string id, string name)
    signal deleteJournalRequested(string id, string name)

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 14
        anchors.bottomMargin: 12
        spacing: 16

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.rightMargin: 10
                Text {
                    text: (appSettings && appSettings.isChinese) ? "日记本" : "JOURNALS"
                    color: theme.ink3
                    font.family: theme.fontUi
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    font.letterSpacing: 1.2
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: "+"
                    color: theme.ink3
                    font.pixelSize: 14
                    visible: !library.isCatalogReadOnly
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: nav.newJournalRequested()
                    }
                }
            }

            Repeater {
                model: library.journals
                delegate: Item {
                    id: rowItem
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    Layout.rightMargin: 4
                    height: 32
                    z: rowItem.isDraggingThis ? 999 : 0

                    readonly property bool isDraggingThis: nav.draggingIndex === index
                    readonly property bool showDropAbove: nav.dropTargetIndex === index && nav.dropAbove && nav.draggingIndex !== index && nav.draggingIndex !== index - 1
                    readonly property bool showDropBelow: nav.dropTargetIndex === index && !nav.dropAbove && nav.draggingIndex !== index && nav.draggingIndex !== index + 1

                    Rectangle {
                        anchors.top: parent.top
                        anchors.topMargin: -2
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 2
                        radius: 1
                        color: theme.ember
                        visible: rowItem.showDropAbove
                        z: 10
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: -2
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 2
                        radius: 1
                        color: theme.ember
                        visible: rowItem.showDropBelow
                        z: 10
                    }

                    DropArea {
                        id: dropArea
                        anchors.fill: parent
                        enabled: !library.isCatalogReadOnly && nav.draggingIndex >= 0
                        onEntered: function (drag) {
                            nav.dropTargetIndex = rowItem.index
                            nav.dropAbove = (drag.y < rowItem.height / 2)
                        }
                        onPositionChanged: function (drag) {
                            nav.dropAbove = (drag.y < rowItem.height / 2)
                        }
                        onExited: {
                            if (nav.dropTargetIndex === rowItem.index)
                                nav.dropTargetIndex = -1
                        }
                    }

                    Rectangle {
                        id: rowContent
                        anchors.fill: parent
                        radius: 6
                        color: modelData.isActive ? theme.ember : (rowMouseArea.containsMouse ? Qt.rgba(240 / 255, 227 / 255, 198 / 255, 0.05) : "transparent")
                        opacity: rowItem.isDraggingThis ? 0.35 : 1.0

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 6
                            Text {
                                text: modelData.name
                                color: modelData.isActive ? "#FFF3E0" : theme.ink1
                                font.family: theme.fontUi
                                font.pixelSize: 13
                                font.weight: modelData.isActive ? Font.DemiBold : Font.Normal
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                text: modelData.statsText || (modelData.entryCount + ((appSettings && appSettings.isChinese) ? " 篇" : (modelData.entryCount === 1 ? " entry" : " entries")))
                                color: modelData.isActive ? Qt.rgba(1, 0.95, 0.88, 0.65) : theme.ink3
                                font.family: theme.fontMono
                                font.pixelSize: 10
                            }
                            Text {
                                visible: modelData.isActive
                                text: modelData.todayMark || ((appSettings && appSettings.isChinese) ? "今" : "NOW")
                                color: Qt.rgba(1, 0.95, 0.88, 0.85)
                                font.family: theme.fontMono
                                font.pixelSize: 11
                                font.weight: Font.Medium
                            }
                        }
                    }

                    Rectangle {
                        id: dragGhost
                        visible: rowItem.isDraggingThis
                        width: rowItem.width
                        height: rowItem.height
                        radius: 6
                        color: modelData.isActive ? theme.ember : theme.paperHi
                        border.color: theme.ember
                        border.width: 1
                        opacity: 0.92
                        z: 999

                        Drag.active: rowMouseArea.drag.active
                        Drag.source: rowItem
                        Drag.hotSpot.x: width / 2
                        Drag.hotSpot.y: height / 2

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 6
                            Text {
                                text: modelData.name
                                color: modelData.isActive ? "#FFF3E0" : theme.ink1
                                font.family: theme.fontUi
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                text: modelData.statsText || (modelData.entryCount + ((appSettings && appSettings.isChinese) ? " 篇" : (modelData.entryCount === 1 ? " entry" : " entries")))
                                color: modelData.isActive ? Qt.rgba(1, 0.95, 0.88, 0.65) : theme.ink3
                                font.family: theme.fontMono
                                font.pixelSize: 10
                            }
                            Text {
                                visible: modelData.isActive
                                text: modelData.todayMark || ((appSettings && appSettings.isChinese) ? "今" : "NOW")
                                color: Qt.rgba(1, 0.95, 0.88, 0.85)
                                font.family: theme.fontMono
                                font.pixelSize: 11
                                font.weight: Font.Medium
                            }
                        }
                    }

                    MouseArea {
                        id: rowMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: pressed && drag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                        drag.target: !library.isCatalogReadOnly && library.journals.length > 1 ? dragGhost : null
                        drag.axis: Drag.YAxis

                        onReleased: function (mouse) {
                            if (drag.active) {
                                if (nav.dropTargetIndex >= 0 && nav.draggingIndex >= 0) {
                                    var target = nav.dropTargetIndex
                                    if (!nav.dropAbove)
                                        target += 1
                                    if (nav.draggingIndex < target)
                                        target -= 1
                                    if (target !== nav.draggingIndex && target >= 0 && target < library.journals.length) {
                                        library.moveJournal(nav.draggingIndex, target)
                                    }
                                }
                            }
                            nav.draggingIndex = -1
                            nav.dropTargetIndex = -1
                            dragGhost.x = 0
                            dragGhost.y = 0
                        }

                        onCanceled: {
                            nav.draggingIndex = -1
                            nav.dropTargetIndex = -1
                            dragGhost.x = 0
                            dragGhost.y = 0
                        }

                        onClicked: function (mouse) {
                            if (mouse.button === Qt.RightButton)
                                rowMenu.popup()
                            else if (!drag.active)
                                library.selectJournal(modelData.id)
                        }

                        Connections {
                            target: rowMouseArea.drag
                            function onActiveChanged() {
                                if (rowMouseArea.drag.active) {
                                    nav.draggingIndex = rowItem.index
                                    nav.dropTargetIndex = rowItem.index
                                    nav.dropAbove = false
                                }
                            }
                        }

                        Menu {
                            id: rowMenu
                            MenuItem {
                                text: (appSettings && appSettings.isChinese) ? "重命名" : "Rename"
                                enabled: !library.isCatalogReadOnly
                                onTriggered: nav.renameJournalRequested(modelData.id, modelData.name)
                            }
                            MenuItem {
                                text: (appSettings && appSettings.isChinese) ? "删除" : "Delete"
                                enabled: !library.isCatalogReadOnly && library.journals.length > 1
                                onTriggered: nav.deleteJournalRequested(modelData.id, modelData.name)
                            }
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: library.tags.length > 0

            Text {
                Layout.leftMargin: 10
                text: (appSettings && appSettings.isChinese) ? "标签" : "TAGS"
                color: theme.ink3
                font.family: theme.fontUi
                font.pixelSize: 11
                font.weight: Font.Bold
                font.letterSpacing: 1.2
            }

            Flow {
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.rightMargin: 10
                spacing: 6
                Repeater {
                    model: library.tags
                    delegate: Rectangle {
                        required property var modelData
                        height: 22
                        width: tagLabel.implicitWidth + 16
                        radius: 2
                        color: "transparent"
                        border.color: theme.cinnabar
                        border.width: 1
                        Text {
                            id: tagLabel
                            anchors.centerIn: parent
                            text: modelData.tag
                            color: theme.cinnabar
                            font.family: theme.fontPrint
                            font.pixelSize: 11
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: library.searchText = modelData.tag
                        }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}

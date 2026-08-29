import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: nav
    required property var theme
    required property var library
    color: theme.sidebar

    signal newJournalRequested()

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
                    text: "日记本"
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
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    Layout.rightMargin: 4
                    height: 32
                    radius: 6
                    color: modelData.isActive ? theme.ember : "transparent"

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
                            text: modelData.entryCount + " 篇"
                            color: modelData.isActive ? Qt.rgba(1, 0.95, 0.88, 0.65) : theme.ink3
                            font.family: theme.fontMono
                            font.pixelSize: 10
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: library.selectJournal(modelData.id)
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
                text: "标签"
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

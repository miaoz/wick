import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    color: theme.paper

    Theme { id: theme }

    readonly property int navWidth: 200
    readonly property int listWidth: 240
    readonly property int inspectorWidth: 268
    readonly property int foldInspectorBelow: 1180
    readonly property int foldNavBelow: 900

    readonly property bool autoHideInspector: width < foldInspectorBelow
    readonly property bool autoHideNav: width < foldNavBelow
    readonly property bool showNav: journalLibrary.columnMode === 0 && !autoHideNav
    readonly property bool showList: journalLibrary.columnMode <= 1
    readonly property bool showInspector: journalLibrary.inspectorVisible
                                          && journalLibrary.columnMode === 0
                                          && !autoHideInspector

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            visible: journalLibrary.errorBanner.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: errorLabel.implicitHeight + 16
            color: Qt.rgba(224 / 255, 106 / 255, 76 / 255, 0.18)
            Text {
                id: errorLabel
                anchors.fill: parent
                anchors.margins: 8
                text: journalLibrary.errorBanner
                color: theme.cinnabar
                font.family: "Noto Sans SC"
                font.pixelSize: 12
                wrapMode: Text.Wrap
            }
        }

        Rectangle {
            visible: journalLibrary.restoreBanner.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: restoreLabel.implicitHeight + 16
            color: Qt.rgba(245 / 255, 168 / 255, 60 / 255, 0.16)
            Text {
                id: restoreLabel
                anchors.fill: parent
                anchors.margins: 8
                text: journalLibrary.restoreBanner
                color: theme.ember
                font.family: "Noto Sans SC"
                font.pixelSize: 12
                wrapMode: Text.Wrap
            }
        }

        Rectangle {
            id: toolbar
            Layout.fillWidth: true
            Layout.preferredHeight: 46
            color: theme.paperHi

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: theme.rule
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 10

                ToolButton {
                    text: journalLibrary.columnMode === 0 ? "▣" : (journalLibrary.columnMode === 1 ? "▤" : "□")
                    font.pixelSize: 14
                    implicitWidth: 28
                    implicitHeight: 28
                    onClicked: journalLibrary.cycleColumns()
                    ToolTip.visible: hovered
                    ToolTip.text: "栏位：全导航 → 仅列表 → 专注"
                    background: Rectangle {
                        radius: 4
                        color: parent.hovered ? Qt.rgba(245 / 255, 168 / 255, 60 / 255, 0.12) : "transparent"
                        border.color: parent.hovered ? theme.ember : theme.ink3
                        border.width: 1
                    }
                    contentItem: Text {
                        text: parent.text
                        color: parent.hovered ? theme.ember : theme.ink2
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                Rectangle {
                    width: 24
                    height: 24
                    radius: 5
                    color: theme.char1
                    Text {
                        anchors.centerIn: parent
                        text: "烛"
                        color: theme.emberHi
                        font.family: "Noto Serif SC"
                        font.pixelSize: 11
                        font.weight: Font.Bold
                    }
                }

                Text {
                    text: "秉烛日记"
                    color: theme.ink1
                    font.family: "Noto Serif SC"
                    font.pixelSize: 15
                    font.weight: Font.Black
                }

                Text {
                    text: journalLibrary.activeJournalName
                    color: theme.ink2
                    font.family: "Inter, Noto Sans SC"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    visible: journalLibrary.activeJournalName.length > 0
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.preferredWidth: 190
                    Layout.preferredHeight: 28
                    radius: 4
                    color: "transparent"
                    border.color: theme.rule
                    border.width: 1

                    TextField {
                        id: searchField
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        placeholderText: "搜索条目…"
                        color: theme.ink1
                        placeholderTextColor: theme.ink3
                        font.family: "Inter, Noto Sans SC"
                        font.pixelSize: 12
                        background: Item {}
                        readOnly: journalLibrary.isCatalogReadOnly
                        onTextChanged: journalLibrary.searchText = text
                    }
                    Connections {
                        target: journalLibrary
                        function onSearchTextChanged() {
                            if (searchField.text !== journalLibrary.searchText)
                                searchField.text = journalLibrary.searchText
                        }
                    }
                }

                ToolButton {
                    text: "＋"
                    implicitWidth: 28
                    implicitHeight: 28
                    onClicked: journalLibrary.openOrCreateToday()
                    enabled: !journalLibrary.isReadOnly
                    ToolTip.visible: hovered
                    ToolTip.text: "今日日记"
                    background: Rectangle {
                        radius: 4
                        color: "transparent"
                        border.color: parent.hovered ? theme.ember : theme.ink3
                        border.width: 1
                    }
                    contentItem: Text {
                        text: parent.text
                        color: parent.hovered ? theme.ember : theme.ink2
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                ToolButton {
                    text: "☰"
                    implicitWidth: 28
                    implicitHeight: 28
                    onClicked: journalLibrary.toggleInspector()
                    ToolTip.visible: hovered
                    ToolTip.text: "检查器"
                    background: Rectangle {
                        radius: 4
                        color: journalLibrary.inspectorVisible ? Qt.rgba(245 / 255, 168 / 255, 60 / 255, 0.12) : "transparent"
                        border.color: parent.hovered || journalLibrary.inspectorVisible ? theme.ember : theme.ink3
                        border.width: 1
                    }
                    contentItem: Text {
                        text: parent.text
                        color: parent.hovered || journalLibrary.inspectorVisible ? theme.ember : theme.ink2
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            NavColumn {
                visible: root.showNav
                Layout.preferredWidth: root.navWidth
                Layout.fillHeight: true
                theme: theme
                library: journalLibrary
                onNewJournalRequested: root.requestNewJournal()
            }

            Rectangle {
                visible: root.showNav
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                color: theme.rule
            }

            DayList {
                visible: root.showList
                Layout.preferredWidth: root.listWidth
                Layout.fillHeight: true
                theme: theme
                library: journalLibrary
            }

            Rectangle {
                visible: root.showList
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                color: theme.rule
            }

            DayPage {
                Layout.fillWidth: true
                Layout.fillHeight: true
                theme: theme
                library: journalLibrary
            }

            Rectangle {
                visible: root.showInspector
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                color: theme.rule
            }

            Inspector {
                visible: root.showInspector
                Layout.preferredWidth: root.inspectorWidth
                Layout.fillHeight: true
                theme: theme
                library: journalLibrary
            }
        }
    }

    Rectangle {
        id: newJournalDialog
        visible: false
        anchors.fill: parent
        color: Qt.rgba(18 / 255, 13 / 255, 7 / 255, 0.55)

        Rectangle {
            width: 320
            height: 140
            radius: 6
            color: theme.paperHi
            border.color: theme.rule
            anchors.centerIn: parent

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 10
                Text {
                    text: "新建日记本"
                    color: theme.ink1
                    font.family: "Noto Serif SC"
                    font.pixelSize: 16
                    font.weight: Font.Bold
                }
                TextField {
                    id: newJournalName
                    Layout.fillWidth: true
                    placeholderText: "日记"
                    color: theme.ink1
                    placeholderTextColor: theme.ink3
                    font.family: "Noto Sans SC"
                    font.pixelSize: 13
                    background: Rectangle {
                        color: "transparent"
                        border.color: theme.rule
                        border.width: 1
                        radius: 3
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    Button {
                        text: "取消"
                        onClicked: newJournalDialog.visible = false
                    }
                    Button {
                        text: "创建"
                        onClicked: {
                            journalLibrary.addJournal(newJournalName.text)
                            newJournalDialog.visible = false
                        }
                    }
                }
            }
        }
    }

    function requestNewJournal() {
        newJournalName.text = ""
        newJournalDialog.visible = true
        newJournalName.forceActiveFocus()
    }
}

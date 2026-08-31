import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

Rectangle {
    id: root
    color: theme.paper

    Theme { id: theme }

    function t(zh, en) {
        return (appSettings && appSettings.isChinese) ? zh : en
    }

    readonly property int navWidth: 220
    readonly property int listWidth: 240
    readonly property int inspectorWidth: 268

    // Four columns follow width only: a full-width tile (including two
    // stacked Hyprland windows) keeps nav / list / editor / inspector.
    // A side-by-side split is narrower and drops to the editor pane.
    readonly property var hostWindow: Window.window
    readonly property real screenWidth: (hostWindow && hostWindow.screen) ? hostWindow.screen.width : Screen.width
    readonly property bool isFullLayout: width >= screenWidth * 0.9

    readonly property bool showNav: isFullLayout && journalLibrary.columnMode === 0
    readonly property bool showList: isFullLayout && journalLibrary.columnMode <= 1
    readonly property bool showInspector: isFullLayout
                                          && journalLibrary.inspectorVisible
                                          && journalLibrary.columnMode === 0

    signal requestSettings()

    Shortcut {
        sequence: "Ctrl+N"
        onActivated: journalLibrary.openOrCreateToday()
    }

    Shortcut {
        sequence: "Ctrl+F"
        onActivated: searchField.forceActiveFocus()
    }

    Shortcut {
        sequence: "Escape"
        onActivated: {
            if (dayPage.lightboxVisible)
                dayPage.closeLightbox()
            else if (searchField.activeFocus) {
                searchField.text = ""
                searchField.focus = false
            }
        }
    }

    Shortcut {
        sequence: "Ctrl+0"
        onActivated: journalLibrary.toggleInspector()
    }

    Shortcut {
        sequence: "Ctrl+Alt+0"
        onActivated: journalLibrary.toggleInspector()
    }

    Shortcut {
        sequence: "Ctrl+Shift+S"
        onActivated: journalLibrary.cycleColumns()
    }

    Shortcut {
        sequence: "Ctrl+,"
        onActivated: root.requestSettings()
    }

    Shortcut { sequence: "Ctrl+1"; onActivated: journalLibrary.selectJournalByIndex(0) }
    Shortcut { sequence: "Ctrl+2"; onActivated: journalLibrary.selectJournalByIndex(1) }
    Shortcut { sequence: "Ctrl+3"; onActivated: journalLibrary.selectJournalByIndex(2) }
    Shortcut { sequence: "Ctrl+4"; onActivated: journalLibrary.selectJournalByIndex(3) }
    Shortcut { sequence: "Ctrl+5"; onActivated: journalLibrary.selectJournalByIndex(4) }
    Shortcut { sequence: "Ctrl+6"; onActivated: journalLibrary.selectJournalByIndex(5) }
    Shortcut { sequence: "Ctrl+7"; onActivated: journalLibrary.selectJournalByIndex(6) }
    Shortcut { sequence: "Ctrl+8"; onActivated: journalLibrary.selectJournalByIndex(7) }
    Shortcut { sequence: "Ctrl+9"; onActivated: journalLibrary.selectJournalByIndex(8) }

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
                font.family: theme.fontUi
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
                font.family: theme.fontUi
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

                Rectangle {
                    visible: root.isFullLayout
                    implicitWidth: 28
                    implicitHeight: 28
                    radius: 4
                    color: colBtnHover.containsMouse ? Qt.rgba(theme.ink1.r, theme.ink1.g, theme.ink1.b, 0.06) : "transparent"
                    border.color: colBtnHover.containsMouse ? theme.rule : "transparent"
                    border.width: 1

                    readonly property string iconName: {
                        if (journalLibrary.columnMode === 1) return "rectangle.split.2x1"
                        if (journalLibrary.columnMode === 2) return "rectangle"
                        return "sidebar.left"
                    }

                    WickIcon {
                        anchors.centerIn: parent
                        name: parent.iconName
                        size: 15
                        color: colBtnHover.containsMouse ? theme.ember : theme.ink2
                    }

                    MouseArea {
                        id: colBtnHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: journalLibrary.cycleColumns()
                    }

                    ToolTip.visible: colBtnHover.containsMouse
                    ToolTip.text: root.t("切换栏位模式 (Ctrl+Shift+S)", "Toggle column mode (Ctrl+Shift+S)")
                    ToolTip.delay: 400
                }

                Text {
                    text: journalLibrary.activeJournalName.length > 0 ? journalLibrary.activeJournalName : root.t("主日记本", "Main Journal")
                    color: theme.ink1
                    font.family: theme.fontUi
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }

                Text {
                    text: journalLibrary.selectedDayStamp
                    color: theme.ink3
                    font.family: theme.fontUi
                    font.pixelSize: 11
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.preferredWidth: 190
                    Layout.preferredHeight: 28
                    radius: 4
                    color: "transparent"
                    border.color: theme.rule
                    border.width: 1

                    Timer {
                        id: searchDebounce
                        interval: 150
                        repeat: false
                        onTriggered: journalLibrary.searchText = searchField.text
                    }

                    TextField {
                        id: searchField
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        placeholderText: root.t("搜索条目…", "Search entries…")
                        color: theme.ink1
                        placeholderTextColor: theme.ink3
                        font.family: theme.fontUi
                        font.pixelSize: 12
                        background: Item {}
                        readOnly: journalLibrary.isCatalogReadOnly
                        onTextChanged: searchDebounce.restart()
                    }
                    Connections {
                        target: journalLibrary
                        function onSearchTextChanged() {
                            if (searchField.text !== journalLibrary.searchText)
                                searchField.text = journalLibrary.searchText
                        }
                    }
                }

                Rectangle {
                    implicitWidth: 28
                    implicitHeight: 28
                    radius: 4
                    color: todayBtnHover.containsMouse ? Qt.rgba(theme.ink1.r, theme.ink1.g, theme.ink1.b, 0.06) : "transparent"
                    border.color: todayBtnHover.containsMouse ? theme.rule : "transparent"
                    border.width: 1
                    opacity: journalLibrary.isReadOnly ? 0.4 : 1.0

                    WickIcon {
                        anchors.centerIn: parent
                        name: "square.and.pencil"
                        size: 15
                        color: todayBtnHover.containsMouse ? theme.ember : theme.ink2
                    }

                    MouseArea {
                        id: todayBtnHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: journalLibrary.isReadOnly ? Qt.ArrowCursor : Qt.PointingHandCursor
                        enabled: !journalLibrary.isReadOnly
                        onClicked: journalLibrary.openOrCreateToday()
                    }

                    ToolTip.visible: todayBtnHover.containsMouse
                    ToolTip.text: root.t("今日日记 (Ctrl+N)", "Today's Journal (Ctrl+N)")
                    ToolTip.delay: 400
                }

                Rectangle {
                    visible: root.isFullLayout
                    implicitWidth: 28
                    implicitHeight: 28
                    radius: 4
                    color: (inspBtnHover.containsMouse || journalLibrary.inspectorVisible) ? Qt.rgba(theme.ember.r, theme.ember.g, theme.ember.b, 0.12) : "transparent"
                    border.color: (inspBtnHover.containsMouse || journalLibrary.inspectorVisible) ? theme.ember : "transparent"
                    border.width: 1

                    WickIcon {
                        anchors.centerIn: parent
                        name: "sidebar.right"
                        size: 15
                        color: (inspBtnHover.containsMouse || journalLibrary.inspectorVisible) ? theme.ember : theme.ink2
                    }

                    MouseArea {
                        id: inspBtnHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: journalLibrary.toggleInspector()
                    }

                    ToolTip.visible: inspBtnHover.containsMouse
                    ToolTip.text: root.t("检查器 (Ctrl+I)", "Inspector (Ctrl+I)")
                    ToolTip.delay: 400
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
                onRenameJournalRequested: function (id, name) { root.requestRenameJournal(id, name) }
                onDeleteJournalRequested: function (id, name) { root.requestDeleteJournal(id, name) }
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
                id: dayPage
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
        id: journalDialog
        visible: false
        anchors.fill: parent
        color: Qt.rgba(18 / 255, 13 / 255, 7 / 255, 0.55)
        property string mode: "new" // new | rename | delete
        property string targetId: ""
        property string targetName: ""

        MouseArea {
            anchors.fill: parent
            onClicked: journalDialog.visible = false
        }

        Shortcut {
            enabled: journalDialog.visible
            sequence: "Escape"
            onActivated: journalDialog.visible = false
        }

        Rectangle {
            width: 320
            height: journalDialog.mode === "delete" ? 150 : 140
            radius: 6
            color: theme.paperHi
            border.color: theme.rule
            anchors.centerIn: parent

            MouseArea {
                anchors.fill: parent
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 10
                Text {
                    text: journalDialog.mode === "rename" ? root.t("重命名日记本", "Rename Journal")
                          : journalDialog.mode === "delete" ? root.t("删除日记本", "Delete Journal")
                          : root.t("新建日记本", "New Journal")
                    color: theme.ink1
                    font.family: theme.fontPrint
                    font.pixelSize: 16
                    font.weight: Font.Bold
                }
                Text {
                    visible: journalDialog.mode === "delete"
                    Layout.fillWidth: true
                    text: root.t("删除「" + journalDialog.targetName + "」？此操作不可撤销，且会从所有已同步设备移除。",
                                 "Delete \"" + journalDialog.targetName + "\"? This cannot be undone and will remove it from all synced devices.")
                    color: theme.ink2
                    font.family: theme.fontUi
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }
                TextField {
                    id: journalNameField
                    visible: journalDialog.mode !== "delete"
                    Layout.fillWidth: true
                    placeholderText: root.t("日记", "Journal")
                    color: theme.ink1
                    placeholderTextColor: theme.ink3
                    font.family: theme.fontUi
                    font.pixelSize: 13
                    background: Rectangle {
                        color: "transparent"
                        border.color: theme.rule
                        border.width: 1
                        radius: 3
                    }
                    Keys.onReturnPressed: root.commitJournalDialog()
                }
                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    Button {
                        text: root.t("取消", "Cancel")
                        font.family: theme.fontUi
                        font.pixelSize: 12
                        onClicked: journalDialog.visible = false
                    }
                    Button {
                        text: journalDialog.mode === "rename" ? root.t("保存", "Save")
                              : journalDialog.mode === "delete" ? root.t("删除", "Delete")
                              : root.t("创建", "Create")
                        font.family: theme.fontUi
                        font.pixelSize: 12
                        onClicked: root.commitJournalDialog()
                    }
                }
            }
        }
    }

    function requestNewJournal() {
        journalDialog.mode = "new"
        journalDialog.targetId = ""
        journalDialog.targetName = ""
        journalNameField.text = ""
        journalDialog.visible = true
        journalNameField.forceActiveFocus()
    }

    function requestRenameJournal(id, name) {
        journalDialog.mode = "rename"
        journalDialog.targetId = id
        journalDialog.targetName = name
        journalNameField.text = name
        journalDialog.visible = true
        journalNameField.forceActiveFocus()
        journalNameField.selectAll()
    }

    function requestDeleteJournal(id, name) {
        journalDialog.mode = "delete"
        journalDialog.targetId = id
        journalDialog.targetName = name
        journalDialog.visible = true
    }

    function commitJournalDialog() {
        if (journalDialog.mode === "new")
            journalLibrary.addJournal(journalNameField.text)
        else if (journalDialog.mode === "rename")
            journalLibrary.renameJournal(journalDialog.targetId, journalNameField.text)
        else if (journalDialog.mode === "delete")
            journalLibrary.deleteJournal(journalDialog.targetId)
        journalDialog.visible = false
    }
}

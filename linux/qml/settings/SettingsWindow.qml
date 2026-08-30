import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

Rectangle {
    id: root
    color: theme.paper

    Theme { id: theme }

    property int currentGroup: 0
    readonly property var groups: [
        appSettings.t("外观与语言", "Appearance & language"),
        appSettings.t("通用", "General"),
        appSettings.t("日记与提醒", "Journal & reminder"),
        appSettings.t("同步", "Sync"),
        appSettings.t("交易所", "Exchanges"),
        appSettings.t("数据", "Data"),
        appSettings.t("关于", "About")
    ]

    function t(zh, en) { return appSettings.t(zh, en) }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            id: nav
            Layout.preferredWidth: 132
            Layout.fillHeight: true
            color: Qt.tint(theme.paper, Qt.rgba(0, 0, 0, 0.12))

            Column {
                anchors.fill: parent
                anchors.topMargin: 12
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 2

                Repeater {
                    model: root.groups
                    delegate: Item {
                        required property int index
                        required property string modelData
                        width: parent.width
                        height: 32

                        Rectangle {
                            anchors.fill: parent
                            radius: 4
                            color: root.currentGroup === index ? theme.paperHi : "transparent"
                        }
                        Rectangle {
                            visible: root.currentGroup === index
                            width: 2
                            height: parent.height - 8
                            anchors.verticalCenter: parent.verticalCenter
                            color: theme.ember
                        }
                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            text: modelData
                            color: root.currentGroup === index ? theme.ink1 : theme.ink2
                            font.family: theme.fontUi
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.currentGroup = index
                        }
                    }
                }
            }

            Rectangle {
                anchors.right: parent.right
                width: 1
                height: parent.height
                color: theme.rule
            }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: pageCol.implicitHeight + 24
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: pageCol
                width: parent.width
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 24
                anchors.rightMargin: 24
                anchors.topMargin: 18
                spacing: 0

                Loader {
                    Layout.fillWidth: true
                    sourceComponent: [
                        appearancePage, generalPage, reminderPage,
                        syncPage, exchangePage, dataPage, aboutPage
                    ][root.currentGroup]
                }
            }
        }
    }

    component Hairline: Rectangle {
        Layout.fillWidth: true
        height: 1
        color: theme.rule
    }

    component SectionLabel: Text {
        Layout.fillWidth: true
        Layout.topMargin: 4
        Layout.bottomMargin: 8
        color: theme.ink3
        font.family: theme.fontUi
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 1.4
    }

    component SettingRow: RowLayout {
        id: srow
        Layout.fillWidth: true
        Layout.preferredHeight: 36
        spacing: 10
        property alias label: lab.text
        property alias hint: hintLab.text
        property bool showHint: false
        Column {
            Layout.fillWidth: true
            spacing: 2
            Text {
                id: lab
                color: theme.ink1
                font.family: theme.fontUi
                font.pixelSize: 13
            }
            Text {
                id: hintLab
                visible: srow.showHint && text.length > 0
                color: theme.ink3
                font.family: theme.fontUi
                font.pixelSize: 11
                wrapMode: Text.Wrap
                width: parent.width
            }
        }
    }

    component EmberToggle: Item {
        id: tog
        property bool on: false
        signal toggled(bool value)
        width: 34
        height: 20
        Rectangle {
            anchors.fill: parent
            radius: 10
            color: tog.on ? theme.ember : theme.rule
        }
        Rectangle {
            width: 16
            height: 16
            radius: 8
            y: 2
            x: tog.on ? 16 : 2
            color: theme.paperHi
            Behavior on x { NumberAnimation { duration: 120 } }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: tog.toggled(!tog.on)
        }
    }

    component Seg: Row {
        id: seg
        property var options: []
        property string current: ""
        signal picked(string value)
        spacing: 0
        Rectangle {
            width: row.implicitWidth
            height: 26
            radius: 4
            color: "transparent"
            border.color: theme.ink3
            border.width: 1
            Row {
                id: row
                height: parent.height
                Repeater {
                    model: seg.options
                    delegate: Rectangle {
                        required property var modelData
                        width: Math.max(44, lab.implicitWidth + 22)
                        height: parent.height
                        color: seg.current === modelData.value ? theme.ember : "transparent"
                        Text {
                            id: lab
                            anchors.centerIn: parent
                            text: modelData.label
                            color: seg.current === modelData.value ? theme.accentTextOnEmber : theme.ink2
                            font.family: theme.fontUi
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: seg.picked(modelData.value)
                        }
                    }
                }
            }
        }
    }

    component ActionRow: Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 34
        Layout.topMargin: 4
        radius: 4
        color: Qt.rgba(theme.ink1.r, theme.ink1.g, theme.ink1.b, 0.04)
        border.color: theme.rule
        border.width: 1
        property alias text: lab.text
        property bool enabled: true
        property bool destructive: false
        property bool coming: false
        signal clicked()
        opacity: enabled ? 1 : 0.55
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            Text {
                id: lab
                color: destructive ? theme.cinnabar : theme.ink1
                font.family: theme.fontUi
                font.pixelSize: 13
                Layout.fillWidth: true
            }
            Text {
                visible: coming
                text: root.t("即将支持", "Coming soon")
                color: theme.ink3
                font.family: theme.fontUi
                font.pixelSize: 11
            }
            Text {
                visible: !coming
                text: "›"
                color: theme.ink3
                font.pixelSize: 14
            }
        }
        MouseArea {
            anchors.fill: parent
            enabled: parent.enabled
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: parent.clicked()
        }
    }

    component EmberButton: Button {
        id: ebtn
        font.family: theme.fontUi
        font.pixelSize: 12
        font.weight: Font.Medium
        implicitHeight: 28
        leftPadding: 14
        rightPadding: 14
        topPadding: 4
        bottomPadding: 4
        contentItem: Text {
            text: ebtn.text
            font: ebtn.font
            color: ebtn.enabled ? theme.ink1 : theme.ink3
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: Rectangle {
            implicitWidth: 72
            implicitHeight: 28
            radius: 4
            color: !ebtn.enabled ? Qt.rgba(0, 0, 0, 0.02)
                 : ebtn.down ? Qt.rgba(0, 0, 0, 0.12)
                 : ebtn.hovered ? Qt.rgba(0, 0, 0, 0.06)
                 : Qt.rgba(0, 0, 0, 0.03)
            border.color: ebtn.visualFocus ? theme.ember : theme.rule
            border.width: 1
        }
    }

    Component {
        id: appearancePage
        ColumnLayout {
            spacing: 0
            SectionLabel { text: t("外观与语言", "APPEARANCE & LANGUAGE") }
            SettingRow {
                label: t("语言", "Language")
                Seg {
                    options: [
                        { value: "zh-Hans", label: "中文" },
                        { value: "en", label: "English" }
                    ]
                    current: appSettings.language
                    onPicked: (v) => appSettings.language = v
                }
            }
            Hairline {}
            SettingRow {
                label: t("外观", "Appearance")
                Seg {
                    options: [
                        { value: "light", label: t("亮色", "Light") },
                        { value: "dark", label: t("暗色", "Dark") },
                        { value: "system", label: t("跟随系统", "System") }
                    ]
                    current: appSettings.appearance
                    onPicked: (v) => appSettings.appearance = v
                }
            }
            RowLayout {
                visible: appSettings.appearance === "system" && appSettings.omarchyAvailable
                Layout.fillWidth: true
                Layout.topMargin: 2
                Layout.bottomMargin: 2
                spacing: 6
                WickIcon {
                    name: "sparkles"
                    size: 11
                    color: theme.ember
                }
                Text {
                    text: t("已连接 Omarchy 主题：" + (appSettings.omarchyThemeName || "当前主题"),
                            "Connected to Omarchy theme: " + (appSettings.omarchyThemeName || "Current theme"))
                    color: theme.ink3
                    font.family: theme.fontUi
                    font.pixelSize: 11
                }
            }
            Item {
                visible: appSettings.appearance !== "system"
                Layout.preferredHeight: 8
            }
            RowLayout {
                visible: appSettings.appearance !== "system"
                Layout.fillWidth: true
                Text {
                    text: t("相位", "Phase")
                    color: theme.ink2
                    font.family: theme.fontUi
                    font.pixelSize: 12
                    Layout.fillWidth: true
                }
                Row {
                    spacing: 6
                    Repeater {
                        model: [
                            { value: "dawn", label: "拂晓" },
                            { value: "day", label: "正午" },
                            { value: "dusk", label: "黄昏" },
                            { value: "night", label: "子夜" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            width: chipLab.implicitWidth + 14
                            height: 24
                            radius: 4
                            color: appSettings.phase === modelData.value ? theme.ember : "transparent"
                            border.color: appSettings.phase === modelData.value ? theme.ember : theme.rule
                            border.width: 1
                            Text {
                                id: chipLab
                                anchors.centerIn: parent
                                text: modelData.label
                                color: appSettings.phase === modelData.value ? theme.accentTextOnEmber : theme.ink2
                                font.family: theme.fontUi
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: appSettings.phase = modelData.value
                            }
                        }
                    }
                }
            }
            Hairline {}
            SettingRow {
                label: t("涨跌配色", "PnL color")
                Seg {
                    options: [
                        { value: "greenUp", label: t("绿涨红跌", "Green up") },
                        { value: "redUp", label: t("红涨绿跌", "Red up") }
                    ]
                    current: appSettings.pnlColorConvention
                    onPicked: (v) => appSettings.pnlColorConvention = v
                }
            }
            Hairline {}
            SettingRow {
                label: t("字体风格", "Typeface")
                Item {
                    id: fontPicker
                    Layout.preferredWidth: 220
                    Layout.preferredHeight: 30
                    property bool popupOpen: false
                    property string searchQuery: ""

                    readonly property var allFonts: [t("默认（系统字体）", "Default (system)")].concat(appSettings.fontFamilies)

                    readonly property var filteredFonts: {
                        const q = searchQuery.trim().toLowerCase()
                        if (q.length === 0)
                            return allFonts
                        return allFonts.filter(f => f.toLowerCase().indexOf(q) !== -1)
                    }

                    readonly property string currentDisplayText: {
                        if (appSettings.journalFontName.length === 0)
                            return t("默认（系统字体）", "Default (system)")
                        return appSettings.journalFontName
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: fontPickerHover.containsMouse ? Qt.rgba(0, 0, 0, 0.04) : "transparent"
                        border.color: fontPicker.popupOpen ? theme.ember : theme.rule
                        border.width: 1
                        radius: 4

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 6

                            Text {
                                Layout.fillWidth: true
                                text: fontPicker.currentDisplayText
                                color: appSettings.journalFontName.length > 0 ? theme.cinnabar : theme.ink1
                                font.family: appSettings.journalFontName.length > 0 ? appSettings.journalFontName : theme.fontUi
                                font.pixelSize: 12
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }

                            WickIcon {
                                name: fontPicker.popupOpen ? "chevron.up" : "chevron.down"
                                size: 12
                                color: theme.ink3
                            }
                        }

                        MouseArea {
                            id: fontPickerHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                fontPicker.popupOpen = !fontPicker.popupOpen
                                if (fontPicker.popupOpen) {
                                    fontPicker.searchQuery = ""
                                    fontSearchField.forceActiveFocus()
                                }
                            }
                        }
                    }

                    Popup {
                        id: fontPopup
                        visible: fontPicker.popupOpen
                        onClosed: fontPicker.popupOpen = false
                        x: fontPicker.width - width
                        y: fontPicker.height + 4
                        width: 260
                        height: 300
                        padding: 0
                        modal: true
                        focus: true
                        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

                        background: Rectangle {
                            color: theme.paperHi
                            border.color: theme.rule
                            border.width: 1
                            radius: 6

                            Rectangle {
                                anchors.fill: parent
                                anchors.topMargin: 2
                                anchors.bottomMargin: -2
                                radius: 6
                                color: Qt.rgba(0, 0, 0, 0.08)
                                z: -1
                            }
                        }

                        contentItem: ColumnLayout {
                            anchors.fill: parent
                            spacing: 0

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 38
                                color: "transparent"

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    color: theme.paper
                                    border.color: fontSearchField.activeFocus ? theme.ember : theme.rule
                                    border.width: 1
                                    radius: 4

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 6
                                        anchors.rightMargin: 6
                                        spacing: 4

                                        WickIcon {
                                            name: "magnifyingglass"
                                            size: 13
                                            color: theme.ink3
                                        }

                                        TextField {
                                            id: fontSearchField
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            placeholderText: t("搜索字体...", "Search fonts...")
                                            placeholderTextColor: theme.ink3
                                            text: fontPicker.searchQuery
                                            color: theme.ink1
                                            font.family: theme.fontUi
                                            font.pixelSize: 12
                                            background: null
                                            padding: 0
                                            onTextChanged: fontPicker.searchQuery = text
                                            Keys.onEscapePressed: fontPopup.close()
                                        }

                                        Item {
                                            visible: fontSearchField.text.length > 0
                                            width: 16
                                            height: 16
                                            WickIcon {
                                                anchors.centerIn: parent
                                                name: "xmark.circle.fill"
                                                size: 13
                                                color: theme.ink3
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    fontSearchField.text = ""
                                                    fontSearchField.forceActiveFocus()
                                                }
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

                            ListView {
                                id: fontListView
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds
                                model: fontPicker.filteredFonts
                                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                                delegate: Item {
                                    required property string modelData
                                    required property int index
                                    width: fontListView.width
                                    height: 30

                                    readonly property bool isDefault: modelData === t("默认（系统字体）", "Default (system)")
                                    readonly property bool isSelected: {
                                        if (isDefault)
                                            return appSettings.journalFontName.length === 0
                                        return modelData === appSettings.journalFontName
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.leftMargin: 4
                                        anchors.rightMargin: 4
                                        radius: 4
                                        color: rowMouse.containsMouse ? Qt.rgba(0, 0, 0, 0.06) : (isSelected ? Qt.rgba(0, 0, 0, 0.03) : "transparent")
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 6

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData
                                            color: isSelected ? theme.ember : theme.ink1
                                            font.family: isDefault ? theme.fontUi : modelData
                                            font.pixelSize: 12
                                            font.weight: isSelected ? Font.DemiBold : Font.Normal
                                            elide: Text.ElideRight
                                        }

                                        WickIcon {
                                            visible: isSelected
                                            name: "checkmark"
                                            size: 12
                                            color: theme.ember
                                        }
                                    }

                                    MouseArea {
                                        id: rowMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (isDefault)
                                                appSettings.journalFontName = ""
                                            else
                                                appSettings.journalFontName = modelData
                                            fontPopup.close()
                                        }
                                    }
                                }

                                Text {
                                    visible: fontPicker.filteredFonts.length === 0
                                    anchors.centerIn: parent
                                    text: t("无匹配字体", "No matching fonts")
                                    color: theme.ink3
                                    font.family: theme.fontUi
                                    font.pixelSize: 12
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: theme.rule
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 32
                                color: importFontHover.containsMouse ? Qt.rgba(0, 0, 0, 0.04) : "transparent"

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 6
                                    WickIcon {
                                        name: "plus"
                                        size: 11
                                        color: theme.ember
                                    }
                                    Text {
                                        text: t("导入字体文件 (.otf / .ttf)...", "Import font file (.otf / .ttf)...")
                                        color: theme.ember
                                        font.family: theme.fontUi
                                        font.pixelSize: 11
                                        font.weight: Font.Medium
                                    }
                                }

                                MouseArea {
                                    id: importFontHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        fontPopup.close()
                                        fontImportDialog.open()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    FileDialog {
        id: fontImportDialog
        fileMode: FileDialog.OpenFile
        nameFilters: [t("字体文件 (*.otf *.ttf *.woff2 *.ttc)", "Font files (*.otf *.ttf *.woff2 *.ttc)")]
        onAccepted: {
            appSettings.importFontFile(selectedFile)
        }
    }

    Component {
        id: generalPage
        ColumnLayout {
            spacing: 0
            SectionLabel { text: t("通用", "GENERAL") }
            SettingRow { label: "每周从周一开始"
                EmberToggle {
                    on: appSettings.weekStartsOnMonday
                    onToggled: (v) => appSettings.weekStartsOnMonday = v
                }
            }
            Hairline {}
            SettingRow { label: t("登录时启动", "Launch at login")
                EmberToggle {
                    on: appSettings.launchAtLogin
                    onToggled: (v) => appSettings.launchAtLogin = v
                }
            }
            Text {
                visible: appSettings.launchAtLoginNote.length > 0
                Layout.fillWidth: true
                Layout.bottomMargin: 8
                text: appSettings.launchAtLoginNote
                color: theme.ink3
                font.family: theme.fontUi
                font.pixelSize: 11
                wrapMode: Text.Wrap
            }
            Hairline {}
            SettingRow { label: t("托盘剩余百分比", "Tray remaining %")
                EmberToggle {
                    on: appSettings.showMenuBarPercentage
                    onToggled: (v) => appSettings.showMenuBarPercentage = v
                }
            }
        }
    }

    Component {
        id: reminderPage
        ColumnLayout {
            spacing: 0
            SectionLabel { text: t("日记与提醒", "JOURNAL & REMINDER") }
            SettingRow { label: t("每日提醒写日记", "Daily journal reminder")
                EmberToggle {
                    on: appSettings.reminderEnabled
                    onToggled: (v) => appSettings.reminderEnabled = v
                }
            }
            Hairline {}
            SettingRow {
                visible: appSettings.reminderEnabled
                label: t("提醒时间", "Reminder time")
                Row {
                    spacing: 6
                    ComboBox {
                        id: hourBox
                        width: 72
                        model: 24
                        font.family: theme.fontMono
                        font.pixelSize: 12
                        delegate: ItemDelegate {
                            required property int index
                            text: index.toString().padStart(2, "0")
                            width: hourBox.width
                            font.family: theme.fontMono
                            font.pixelSize: 12
                            contentItem: Text {
                                text: parent.text
                                font: parent.font
                                color: theme.ink1
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignHCenter
                            }
                            background: Rectangle {
                                color: parent.highlighted || parent.hovered ? Qt.rgba(0, 0, 0, 0.06) : "transparent"
                            }
                            onClicked: {
                                appSettings.reminderHour = index
                                hourBox.currentIndex = index
                            }
                        }
                        displayText: appSettings.reminderHour.toString().padStart(2, "0")
                        currentIndex: appSettings.reminderHour
                        onActivated: appSettings.reminderHour = currentIndex
                        contentItem: Text {
                            text: hourBox.displayText
                            font: hourBox.font
                            color: theme.ink1
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: Text.AlignHCenter
                        }
                        background: Rectangle {
                            color: "transparent"
                            border.color: theme.rule
                            border.width: 1
                            radius: 4
                        }
                        popup: Popup {
                            y: hourBox.height + 2
                            width: hourBox.width
                            height: Math.min(200, contentItem.implicitHeight)
                            padding: 1
                            contentItem: ListView {
                                clip: true
                                implicitHeight: contentHeight
                                model: hourBox.popup.visible ? hourBox.delegateModel : null
                                currentIndex: hourBox.highlightedIndex
                                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                            }
                            background: Rectangle {
                                color: theme.paperHi
                                border.color: theme.rule
                                border.width: 1
                                radius: 4
                            }
                        }
                    }
                    Text {
                        text: ":"
                        color: theme.ink1
                        font.family: theme.fontMono
                        font.pixelSize: 16
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    ComboBox {
                        id: minBox
                        width: 72
                        model: 60
                        font.family: theme.fontMono
                        font.pixelSize: 12
                        delegate: ItemDelegate {
                            required property int index
                            text: index.toString().padStart(2, "0")
                            width: minBox.width
                            font.family: theme.fontMono
                            font.pixelSize: 12
                            contentItem: Text {
                                text: parent.text
                                font: parent.font
                                color: theme.ink1
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignHCenter
                            }
                            background: Rectangle {
                                color: parent.highlighted || parent.hovered ? Qt.rgba(0, 0, 0, 0.06) : "transparent"
                            }
                            onClicked: {
                                appSettings.reminderMinute = index
                                minBox.currentIndex = index
                            }
                        }
                        displayText: appSettings.reminderMinute.toString().padStart(2, "0")
                        currentIndex: appSettings.reminderMinute
                        onActivated: appSettings.reminderMinute = currentIndex
                        contentItem: Text {
                            text: minBox.displayText
                            font: minBox.font
                            color: theme.ink1
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: Text.AlignHCenter
                        }
                        background: Rectangle {
                            color: "transparent"
                            border.color: theme.rule
                            border.width: 1
                            radius: 4
                        }
                        popup: Popup {
                            y: minBox.height + 2
                            width: minBox.width
                            height: Math.min(200, contentItem.implicitHeight)
                            padding: 1
                            contentItem: ListView {
                                clip: true
                                implicitHeight: contentHeight
                                model: minBox.popup.visible ? minBox.delegateModel : null
                                currentIndex: minBox.highlightedIndex
                                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                            }
                            background: Rectangle {
                                color: theme.paperHi
                                border.color: theme.rule
                                border.width: 1
                                radius: 4
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: syncPage
        ColumnLayout {
            spacing: 0
            SectionLabel { text: t("同步", "SYNC") }
            Text {
                Layout.fillWidth: true
                Layout.bottomMargin: 10
                text: t("通过 Dropbox 在多台设备间同步日记。本地始终是主副本，同步中断不影响使用。",
                        "Sync journals across devices via Dropbox. Local data is always the primary copy.")
                color: theme.ink2
                font.family: theme.fontUi
                font.pixelSize: 12
                wrapMode: Text.Wrap
            }
            ActionRow {
                text: (syncCoordinator && syncCoordinator.connected)
                      ? t("断开 Dropbox", "Disconnect Dropbox")
                      : t("连接 Dropbox", "Connect Dropbox")
                coming: false
                enabled: !!syncCoordinator
                onClicked: {
                    if (!syncCoordinator)
                        return
                    if (syncCoordinator.connected)
                        syncCoordinator.signOut()
                    else
                        syncCoordinator.connectDropbox()
                }
            }
            Text {
                visible: !!(syncCoordinator && (syncCoordinator.connected
                           || syncCoordinator.statusText.length > 0
                           || syncCoordinator.fakeSyncAvailable))
                Layout.fillWidth: true
                Layout.topMargin: 6
                text: {
                    if (!syncCoordinator)
                        return ""
                    if (syncCoordinator.connected) {
                        const prefix = syncCoordinator.fakeSyncAvailable
                            ? t("已连接（调试假后端）", "Connected (debug fake backend)")
                            : t("已连接", "Connected")
                        return prefix
                            + (syncCoordinator.accountEmail ? " · " + syncCoordinator.accountEmail : "")
                            + (syncCoordinator.statusText ? " · " + syncCoordinator.statusText : "")
                    }
                    if (syncCoordinator.statusText.length > 0)
                        return syncCoordinator.statusText
                    if (syncCoordinator.fakeSyncAvailable)
                        return t("WICK_FAKE_SYNC=1：用内存假后端跑同步循环，不访问真实 Dropbox。",
                                 "WICK_FAKE_SYNC=1: run the engine against an in-memory fake, no real Dropbox.")
                    return ""
                }
                color: theme.ink3
                font.family: theme.fontUi
                font.pixelSize: 11
                wrapMode: Text.Wrap
            }
        }
    }

    Component {
        id: exchangePage
        ColumnLayout {
            spacing: 0
            SectionLabel { text: t("交易所", "EXCHANGES") }
            Text {
                Layout.fillWidth: true
                Layout.bottomMargin: 10
                text: t("每本日记绑定一个交易所账号。凭证只读，保存在系统密钥环（或 WICK_DEV_SECRETS=1 的本地文件），不会上传。",
                        "One exchange account per journal. Credentials stay in the system keyring (or WICK_DEV_SECRETS=1 file) and never upload.")
                color: theme.ink2
                font.family: theme.fontUi
                font.pixelSize: 12
                wrapMode: Text.Wrap
            }
            SettingRow {
                label: t("日记本", "Journal")
                ComboBox {
                    id: journalBox
                    Layout.preferredWidth: 200
                    model: journalLibrary.journals
                    textRole: "name"
                    font.family: theme.fontUi
                    font.pixelSize: 12
                    onActivated: {
                        const row = journalLibrary.journals[currentIndex]
                        if (row) {
                            appSettings.exchangeJournalId = row.id
                            exchangeCoordinator.targetJournalId = row.id
                        }
                    }
                    Component.onCompleted: selectCurrent()
                    function selectCurrent() {
                        let id = exchangeCoordinator.targetJournalId
                        if (id.length === 0)
                            id = appSettings.exchangeJournalId
                        const list = journalLibrary.journals
                        for (let i = 0; i < list.length; ++i) {
                            if (list[i].id === id) {
                                currentIndex = i
                                exchangeCoordinator.targetJournalId = list[i].id
                                return
                            }
                        }
                        if (list.length > 0) {
                            currentIndex = 0
                            exchangeCoordinator.targetJournalId = list[0].id
                            if (appSettings.exchangeJournalId.length === 0)
                                appSettings.exchangeJournalId = list[0].id
                        }
                    }
                    Connections {
                        target: journalLibrary
                        function onJournalsChanged() { journalBox.selectCurrent() }
                    }
                    background: Rectangle {
                        color: "transparent"
                        border.color: theme.rule
                        border.width: 1
                        radius: 4
                    }
                    contentItem: Text {
                        text: journalBox.displayText
                        color: theme.ink1
                        font: journalBox.font
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: 8
                        elide: Text.ElideRight
                    }
                    delegate: ItemDelegate {
                        required property var modelData
                        required property int index
                        width: journalBox.width
                        font.family: theme.fontUi
                        font.pixelSize: 12
                        contentItem: Text {
                            text: modelData.name || ""
                            font: parent.font
                            color: theme.ink1
                            verticalAlignment: Text.AlignVCenter
                            leftPadding: 8
                            elide: Text.ElideRight
                        }
                        background: Rectangle {
                            color: parent.highlighted || parent.hovered ? Qt.rgba(0, 0, 0, 0.06) : "transparent"
                        }
                    }
                }
            }
            Hairline {}

            ColumnLayout {
                visible: exchangeCoordinator.configured
                Layout.fillWidth: true
                spacing: 8
                SettingRow {
                    label: t("已连接", "Connected")
                    Text {
                        text: (exchangeCoordinator.venue === "okx" ? "OKX"
                              : exchangeCoordinator.venue === "hyperliquid" ? "Hyperliquid"
                              : "Binance") + " · " + exchangeCoordinator.accountLabel
                        color: theme.ink1
                        font.family: theme.fontMono
                        font.pixelSize: 12
                        elide: Text.ElideMiddle
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: exchangeCoordinator.statusText
                    color: exchangeCoordinator.lastError.length > 0 ? theme.cinnabar : theme.ink2
                    font.family: theme.fontUi
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }
                RowLayout {
                    Layout.fillWidth: true
                    EmberButton {
                        text: exchangeCoordinator.syncing ? t("同步中…", "Syncing…") : t("立即同步", "Sync now")
                        enabled: !exchangeCoordinator.syncing
                        onClicked: exchangeCoordinator.syncNow(exchangeCoordinator.targetJournalId)
                    }
                    EmberButton {
                        text: t("断开", "Disconnect")
                        enabled: !exchangeCoordinator.syncing
                        onClicked: exchangeCoordinator.disconnectJournal(exchangeCoordinator.targetJournalId)
                    }
                }
            }

            ColumnLayout {
                visible: !exchangeCoordinator.configured
                Layout.fillWidth: true
                spacing: 8
                SettingRow {
                    label: t("交易所", "Venue")
                    Seg {
                        options: [
                            { value: "binance", label: "Binance" },
                            { value: "okx", label: "OKX" },
                            { value: "hyperliquid", label: "Hyperliquid" }
                        ]
                        current: appSettings.exchangeVenue
                        onPicked: (v) => appSettings.exchangeVenue = v
                    }
                }
                Hairline {}
                SettingRow {
                    visible: appSettings.exchangeVenue !== "hyperliquid"
                    label: t("API Key", "API Key")
                    TextField {
                        id: apiKeyField
                        Layout.preferredWidth: 240
                        echoMode: TextInput.Normal
                        font.family: theme.fontMono
                        font.pixelSize: 12
                        color: theme.ink1
                        background: Rectangle {
                            color: "transparent"
                            border.color: theme.rule
                            border.width: 1
                            radius: 3
                        }
                    }
                }
                SettingRow {
                    visible: appSettings.exchangeVenue !== "hyperliquid"
                    label: t("Secret", "Secret")
                    TextField {
                        id: secretField
                        Layout.preferredWidth: 240
                        echoMode: TextInput.Password
                        font.family: theme.fontMono
                        font.pixelSize: 12
                        color: theme.ink1
                        background: Rectangle {
                            color: "transparent"
                            border.color: theme.rule
                            border.width: 1
                            radius: 3
                        }
                    }
                }
                SettingRow {
                    visible: appSettings.exchangeVenue === "okx"
                    label: t("Passphrase", "Passphrase")
                    TextField {
                        id: passphraseField
                        Layout.preferredWidth: 240
                        echoMode: TextInput.Password
                        font.family: theme.fontMono
                        font.pixelSize: 12
                        color: theme.ink1
                        background: Rectangle {
                            color: "transparent"
                            border.color: theme.rule
                            border.width: 1
                            radius: 3
                        }
                    }
                }
                SettingRow {
                    visible: appSettings.exchangeVenue === "hyperliquid"
                    label: t("钱包地址", "Wallet")
                    TextField {
                        id: addressField
                        Layout.preferredWidth: 240
                        placeholderText: "0x…"
                        font.family: theme.fontMono
                        font.pixelSize: 12
                        color: theme.ink1
                        placeholderTextColor: theme.ink3
                        background: Rectangle {
                            color: "transparent"
                            border.color: theme.rule
                            border.width: 1
                            radius: 3
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: appSettings.exchangeVenue === "okx"
                          ? t("OKX 永续。fillSz 单位是张，未换算 ctVal。", "OKX SWAP. fillSz is contracts, not coin.")
                          : appSettings.exchangeVenue === "hyperliquid"
                            ? t("只需只读地址，无需 API Key。公开 info 接口。", "Read-only address; public info endpoint.")
                            : t("Binance USDⓈ-M。请用只读 API Key。", "Binance USDⓈ-M. Use a read-only API key.")
                    color: theme.ink3
                    font.family: theme.fontUi
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                }
                EmberButton {
                    text: exchangeCoordinator.syncing ? t("连接中…", "Connecting…") : t("连接并同步", "Save and sync")
                    enabled: !exchangeCoordinator.syncing && (
                        appSettings.exchangeVenue === "hyperliquid"
                            ? addressField.text.length > 0
                            : apiKeyField.text.length > 0 && secretField.text.length > 0
                              && (appSettings.exchangeVenue !== "okx" || passphraseField.text.length > 0)
                    )
                    onClicked: {
                        const id = exchangeCoordinator.targetJournalId
                        if (appSettings.exchangeVenue === "okx")
                            exchangeCoordinator.saveOKX(id, apiKeyField.text, secretField.text, passphraseField.text)
                        else if (appSettings.exchangeVenue === "hyperliquid")
                            exchangeCoordinator.saveHyperliquid(id, addressField.text)
                        else
                            exchangeCoordinator.saveBinance(id, apiKeyField.text, secretField.text)
                        apiKeyField.text = ""
                        secretField.text = ""
                        passphraseField.text = ""
                    }
                }
                Text {
                    visible: exchangeCoordinator.lastError.length > 0
                    Layout.fillWidth: true
                    text: exchangeCoordinator.lastError
                    color: theme.cinnabar
                    font.family: theme.fontUi
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }
            }

            Hairline { Layout.topMargin: 12 }
            SettingRow {
                label: t("同步仓位快照", "Sync trading snapshots")
                showHint: true
                hint: t("可选。上传成交、资金费与仓位供其他设备只读展示；API Key、Secret 与 Passphrase 永不上传。",
                        "Optional. Upload fills and positions for read-only display on other devices. Credentials never upload.")
                EmberToggle {
                    on: appSettings.syncTradingSnapshots
                    onToggled: (v) => appSettings.syncTradingSnapshots = v
                }
            }
        }
    }

    Component {
        id: dataPage
        ColumnLayout {
            spacing: 0
            SectionLabel { text: t("数据", "DATA") }
            Rectangle {
                visible: journalLibrary.isReadOnly || journalLibrary.isCatalogReadOnly
                Layout.fillWidth: true
                Layout.preferredHeight: roCol.implicitHeight + 16
                Layout.bottomMargin: 10
                radius: 4
                color: theme.cinnabarSoft
                border.color: theme.cinnabar
                border.width: 1
                Column {
                    id: roCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 8
                    spacing: 4
                    Text {
                        text: t("只读（加载失败）", "Read-only (load failure)")
                        color: theme.cinnabar
                        font.family: theme.fontUi
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width
                        text: journalLibrary.errorBanner
                        color: theme.ink2
                        font.family: theme.fontUi
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                        visible: journalLibrary.errorBanner.length > 0
                    }
                }
            }
            ActionRow {
                text: t("导出日记…", "Export journal…")
                enabled: !journalLibrary.isReadOnly
                onClicked: exportDialog.open()
            }
            ActionRow {
                text: t("导入日记…", "Import journal…")
                onClicked: importDialog.open()
            }
            ActionRow {
                text: t("在文件管理器中显示数据", "Reveal data in file manager")
                onClicked: appSettings.revealDataDirectory()
            }
            Text {
                visible: appSettings.dataStatusText.length > 0
                Layout.fillWidth: true
                Layout.topMargin: 8
                text: appSettings.dataStatusText
                color: theme.ink2
                font.family: theme.fontUi
                font.pixelSize: 11
            }
        }
    }

    Component {
        id: aboutPage
        ColumnLayout {
            spacing: 0
            SectionLabel { text: t("关于", "ABOUT") }
            SettingRow { label: t("自动检查更新", "Check for updates automatically")
                EmberToggle {
                    on: appSettings.checkForUpdatesAutomatically
                    onToggled: (v) => appSettings.checkForUpdatesAutomatically = v
                }
            }
            Hairline {}
            ActionRow {
                text: appSettings.isCheckingUpdates
                      ? t("正在检查…", "Checking…")
                      : t("检查更新", "Check for updates")
                enabled: !appSettings.isCheckingUpdates
                onClicked: appSettings.checkForUpdates()
            }
            Text {
                visible: appSettings.updateStatusText.length > 0
                Layout.fillWidth: true
                Layout.topMargin: 6
                text: appSettings.updateStatusText
                color: theme.ink2
                font.family: theme.fontUi
                font.pixelSize: 11
            }
            ActionRow {
                text: t("打开发布页", "Open release page")
                onClicked: appSettings.openReleasesPage()
            }
            Item { Layout.preferredHeight: 28 }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: "Wick for Linux · 秉烛日记"
                color: theme.ink2
                font.family: theme.fontPrint
                font.pixelSize: 12
                font.weight: Font.Bold
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: "v" + appSettings.appVersion
                color: theme.ink3
                font.family: theme.fontPrint
                font.pixelSize: 10
            }
        }
    }

    FileDialog {
        id: exportDialog
        fileMode: FileDialog.SaveFile
        nameFilters: [root.t("Zip 归档 (*.zip)", "Zip archive (*.zip)")]
        defaultSuffix: "zip"
        onAccepted: {
            const err = journalLibrary.exportArchiveTo(selectedFile)
            if (err.length === 0)
                appSettings.setDataStatus(root.t("已导出", "Exported"))
            else
                appSettings.setDataStatus(err)
        }
    }

    FileDialog {
        id: importDialog
        fileMode: FileDialog.OpenFile
        nameFilters: [
            root.t("秉烛归档 (*.zip *.json)", "Wick archive (*.zip *.json)"),
            root.t("Zip (*.zip)", "Zip (*.zip)"),
            root.t("JSON (*.json)", "JSON (*.json)")
        ]
        onAccepted: {
            const err = journalLibrary.importArchiveFrom(selectedFile)
            if (err.length === 0)
                appSettings.setDataStatus(root.t("已导入", "Imported"))
            else
                appSettings.setDataStatus(err)
        }
    }
}

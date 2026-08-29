import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

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

    // ----- shared bits -----
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

    // 1. 外观与语言
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
                        { value: "light", label: t("亮", "Light") },
                        { value: "dark", label: t("暗", "Dark") },
                        { value: "system", label: t("跟随", "System") }
                    ]
                    current: appSettings.appearance
                    onPicked: (v) => appSettings.appearance = v
                }
            }
            Item { Layout.preferredHeight: 8 }
            RowLayout {
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
                ComboBox {
                    id: fontBox
                    Layout.preferredWidth: 220
                    model: [t("默认（系统字体）", "Default (system)")].concat(appSettings.fontFamilies)
                    font.family: theme.fontUi
                    font.pixelSize: 12
                    onActivated: {
                        if (currentIndex === 0)
                            appSettings.journalFontName = ""
                        else
                            appSettings.journalFontName = appSettings.fontFamilies[currentIndex - 1]
                    }
                    Component.onCompleted: {
                        if (appSettings.journalFontName.length === 0)
                            currentIndex = 0
                        else {
                            const i = appSettings.fontFamilies.indexOf(appSettings.journalFontName)
                            currentIndex = i >= 0 ? i + 1 : 0
                        }
                    }
                    background: Rectangle {
                        color: "transparent"
                        border.color: theme.rule
                        border.width: 1
                        radius: 4
                    }
                    contentItem: Text {
                        text: fontBox.displayText
                        color: theme.cinnabar
                        font: fontBox.font
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: 8
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // 2. 通用
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

    // 3. 日记与提醒 — no 打开日记
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
                        delegate: ItemDelegate {
                            required property int index
                            text: index.toString().padStart(2, "0")
                            width: hourBox.width
                            onClicked: {
                                appSettings.reminderHour = index
                                hourBox.currentIndex = index
                            }
                        }
                        displayText: appSettings.reminderHour.toString().padStart(2, "0")
                        currentIndex: appSettings.reminderHour
                        onActivated: appSettings.reminderHour = currentIndex
                    }
                    Text {
                        text: ":"
                        color: theme.ink1
                        font.pixelSize: 16
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    ComboBox {
                        id: minBox
                        width: 72
                        model: 60
                        delegate: ItemDelegate {
                            required property int index
                            text: index.toString().padStart(2, "0")
                            width: minBox.width
                            onClicked: {
                                appSettings.reminderMinute = index
                                minBox.currentIndex = index
                            }
                        }
                        displayText: appSettings.reminderMinute.toString().padStart(2, "0")
                        currentIndex: appSettings.reminderMinute
                        onActivated: appSettings.reminderMinute = currentIndex
                    }
                }
            }
        }
    }

    // 4. 同步 — Dropbox stub, no snapshot toggle
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
                text: t("连接 Dropbox", "Connect Dropbox")
                coming: true
                enabled: false
            }
        }
    }

    // 5. 交易所 — prefs only, snapshot moved here
    Component {
        id: exchangePage
        ColumnLayout {
            spacing: 0
            SectionLabel { text: t("交易所", "EXCHANGES") }
            Text {
                Layout.fillWidth: true
                Layout.bottomMargin: 10
                text: t("先选择日记本与交易所。仓位同步将在后续版本接入，此处只保存偏好。",
                        "Pick a journal and venue. Live exchange sync arrives later — this stores preferences only.")
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
                        if (row)
                            appSettings.exchangeJournalId = row.id
                    }
                    Component.onCompleted: selectCurrent()
                    function selectCurrent() {
                        const id = appSettings.exchangeJournalId
                        const list = journalLibrary.journals
                        for (let i = 0; i < list.length; ++i) {
                            if (list[i].id === id) {
                                currentIndex = i
                                return
                            }
                        }
                        if (list.length > 0) {
                            currentIndex = 0
                            if (id.length === 0)
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
                }
            }
            Hairline {}
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

    // 6. 数据
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
                coming: true
                onClicked: appSettings.stubExport()
            }
            ActionRow {
                text: t("导入日记…", "Import journal…")
                coming: true
                onClicked: appSettings.stubImport()
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

    // 7. 关于 — no Quit
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
}

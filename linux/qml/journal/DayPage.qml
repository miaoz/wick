import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

Rectangle {
    id: page
    required property var theme
    required property var library
    color: theme.paper
    property string pendingImageItemId: ""
    property string pendingDeleteItemId: ""
    property string pendingDeleteEntryId: ""
    property bool lightboxVisible: false
    property var lightboxImages: []
    property int lightboxIndex: 0
    property string lastScrolledEntryId: ""

    function t(zh, en) {
        return (appSettings && appSettings.isChinese) ? zh : en
    }

    function openLightbox(images, index) {
        lightboxImages = images
        lightboxIndex = index
        lightboxVisible = true
    }

    function closeLightbox() {
        lightboxVisible = false
    }

    function nextLightbox() {
        if (lightboxImages.length > 0)
            lightboxIndex = (lightboxIndex + 1) % lightboxImages.length
    }

    function prevLightbox() {
        if (lightboxImages.length > 0)
            lightboxIndex = (lightboxIndex - 1 + lightboxImages.length) % lightboxImages.length
    }

    function scrollToSelectedDay(force) {
        const targetId = library.selectedEntryId
        if (!targetId)
            return
        if (!force && targetId === lastScrolledEntryId)
            return
        lastScrolledEntryId = targetId
        for (let i = 0; i < timelineRepeater.count; ++i) {
            const item = timelineRepeater.itemAt(i)
            if (item && item.entryId === targetId) {
                const targetY = Math.max(0, item.y - 20)
                scrollAnim.stop()
                scrollAnim.from = timelineFlickable.contentY
                scrollAnim.to = targetY
                scrollAnim.start()
                return
            }
        }
    }

    Connections {
        target: library
        function onSelectedEntryIdChanged() {
            page.scrollToSelectedDay(false)
        }
        function onSelectionChanged() {
            page.scrollToSelectedDay(false)
        }
        function onDaysChanged() {
            Qt.callLater(() => { page.scrollToSelectedDay(false) })
        }
    }

    NumberAnimation {
        id: scrollAnim
        target: timelineFlickable
        property: "contentY"
        duration: 250
        easing.type: Easing.OutCubic
    }

    Flickable {
        id: timelineFlickable
        anchors.fill: parent
        contentWidth: width
        contentHeight: timelineCol.implicitHeight + 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
            id: timelineCol
            width: Math.min(page.width - 48, 760)
            anchors.horizontalCenter: parent.horizontalCenter
            topPadding: 20
            bottomPadding: 20
            spacing: 30

            Text {
                visible: library.days.length === 0
                width: parent.width
                height: 120
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: library.isCatalogReadOnly ? page.t("目录不可用", "Catalog Unavailable") : page.t("选择一日，或点 ＋ 写下今天", "Select a day, or click + to write today")
                color: theme.ink3
                font.family: theme.fontPrint
                font.pixelSize: 14
            }

            Repeater {
                id: timelineRepeater
                model: library.days
                delegate: Item {
                    id: daySection
                    required property var modelData
                    required property int index
                    readonly property string entryId: modelData.entryId
                    width: timelineCol.width
                    implicitHeight: sheet.implicitHeight + 6
                    height: implicitHeight

                    // Dual contact shadow (design: 0 1px 2px / 0 5px 14px at 8%).
                    Rectangle {
                        anchors.fill: sheet
                        anchors.topMargin: 5
                        radius: 4
                        color: Qt.rgba(0, 0, 0, 0.08)
                    }
                    Rectangle {
                        anchors.fill: sheet
                        anchors.topMargin: 1
                        radius: 4
                        color: Qt.rgba(0, 0, 0, 0.08)
                    }

                    Rectangle {
                        id: sheet
                        anchors.left: parent.left
                        anchors.right: parent.right
                        implicitHeight: sheetCol.implicitHeight + 34
                        height: implicitHeight
                        color: theme.paperHi
                        border.color: theme.rule
                        border.width: 1
                        radius: 4

                        ColumnLayout {
                            id: sheetCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.leftMargin: 26
                            anchors.rightMargin: 26
                            anchors.topMargin: 20
                            spacing: 0

                            // Top Header
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12

                                Text {
                                    text: daySection.modelData.dateLabel
                                    color: theme.ink1
                                    font.family: theme.fontPrint
                                    font.pixelSize: 28
                                    font.weight: Font.Black
                                }

                                Column {
                                    spacing: 2
                                    Layout.bottomMargin: 3
                                    Text {
                                        text: daySection.modelData.weekday
                                        color: theme.ink2
                                        font.family: theme.fontPrint
                                        font.pixelSize: 11
                                    }
                                    Text {
                                        text: daySection.modelData.lunar || ""
                                        color: theme.ink2
                                        font.family: theme.fontPrint
                                        font.pixelSize: 11
                                        visible: text.length > 0
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                // 当日净盈亏 (对齐 macOS JournalDaySection.swift)
                                Column {
                                    visible: daySection.modelData.hasPnl
                                    spacing: 2
                                    Layout.bottomMargin: 2
                                    Text {
                                        anchors.right: parent.right
                                        text: page.t("净盈亏", "Net PnL")
                                        color: theme.ink3
                                        font.family: theme.fontMono
                                        font.pixelSize: 9
                                        font.weight: Font.Medium
                                    }
                                    Text {
                                        anchors.right: parent.right
                                        text: daySection.modelData.pnlText || ""
                                        color: (daySection.modelData.dayPnl >= 0) ? theme.gain : theme.loss
                                        font.family: theme.fontMono
                                        font.pixelSize: 14
                                        font.weight: Font.Bold
                                    }
                                }

                                Text {
                                    text: daySection.modelData.savedState || ""
                                    color: library.isReadOnly ? theme.cinnabar : theme.ink3
                                    font.family: theme.fontMono
                                    font.pixelSize: 9
                                    Layout.bottomMargin: 5
                                    visible: text.length > 0 && daySection.modelData.isSelected
                                }

                                // Day delete button on top-right of sheet
                                Rectangle {
                                    visible: !library.isReadOnly
                                    width: 24
                                    height: 24
                                    radius: 3
                                    color: trashBtnHover.containsMouse ? Qt.rgba(224 / 255, 76 / 255, 76 / 255, 0.15) : "transparent"
                                    ToolTip.visible: trashBtnHover.containsMouse
                                    ToolTip.text: page.t("删除本日日记", "Delete Today's Journal")
                                    WickIcon {
                                        anchors.centerIn: parent
                                        name: "trash"
                                        size: 14
                                        color: trashBtnHover.containsMouse ? theme.cinnabar : theme.ink3
                                    }
                                    MouseArea {
                                        id: trashBtnHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            page.pendingDeleteEntryId = daySection.modelData.entryId
                                            deleteDayConfirmDialog.open()
                                        }
                                    }
                                }
                            }

                            // Burn progress track
                            Item {
                                Layout.fillWidth: true
                                Layout.topMargin: 12
                                Layout.preferredHeight: daySection.modelData.isToday ? 28 : 8

                                Rectangle {
                                    id: burnTrack
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    height: 8
                                    radius: 3
                                    color: theme.paperHi
                                    border.color: theme.rule
                                    clip: true

                                    Repeater {
                                        model: 24
                                        Rectangle {
                                            required property int index
                                            width: 1
                                            height: burnTrack.height
                                            x: (index / 24) * burnTrack.width
                                            color: theme.rule
                                            visible: index > 0
                                        }
                                    }

                                    Rectangle {
                                        id: burnFill
                                        width: Math.max(0, Math.min(1, daySection.modelData.burnElapsed)) * burnTrack.width
                                        height: burnTrack.height
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0.0; color: theme.stain1 }
                                            GradientStop { position: 1.0; color: theme.stain2 }
                                        }
                                    }
                                    Rectangle {
                                        visible: daySection.modelData.isToday && daySection.modelData.burnElapsed > 0.002
                                                 && daySection.modelData.burnElapsed < 0.998
                                        width: 3
                                        height: burnTrack.height
                                        x: burnFill.width - 1
                                        color: theme.ember
                                    }
                                }

                                RowLayout {
                                    visible: daySection.modelData.isToday
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    Text {
                                        text: Math.round(daySection.modelData.burnElapsed * 100) + "% 已过"
                                        color: theme.ink3
                                        font.family: theme.fontMono
                                        font.pixelSize: 9
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: "00:00 — 24:00"
                                        color: theme.ink3
                                        font.family: theme.fontMono
                                        font.pixelSize: 9
                                    }
                                }
                            }

                            // Items List
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                spacing: 0

                                Repeater {
                                    model: daySection.modelData.items
                                    delegate: Item {
                                        id: itemBlock
                                        required property var modelData
                                        required property int index
                                        Layout.fillWidth: true
                                        implicitHeight: itemCol.implicitHeight + 20

                                        property bool reviewOpen: false

                                        Rectangle {
                                            visible: index > 0
                                            anchors.top: parent.top
                                            width: parent.width
                                            height: 1
                                            color: theme.rule
                                        }

                                        DropArea {
                                            anchors.fill: parent
                                            onDropped: (drop) => {
                                                if (drop.hasUrls) {
                                                    for (var i = 0; i < drop.urls.length; ++i) {
                                                        library.addImageFromUrl(itemBlock.modelData.itemId, drop.urls[i])
                                                    }
                                                }
                                            }
                                        }

                                        ColumnLayout {
                                            id: itemCol
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.topMargin: 12
                                            spacing: 8

                                            // Item header: [ #1 ] ... [ +图片 ] [ –删除 ]
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 8

                                                Text {
                                                    text: modelData.indexLabel || (page.t("条目 ", "Entry ") + (index + 1))
                                                    color: theme.ink3
                                                    font.family: theme.fontPrint
                                                    font.pixelSize: 11
                                                }

                                                Item { Layout.fillWidth: true }

                                                // [+] Add image button
                                                Rectangle {
                                                    visible: !library.isReadOnly
                                                    width: 22
                                                    height: 22
                                                    radius: 3
                                                    color: imgBtnHover.containsMouse ? Qt.rgba(245 / 255, 168 / 255, 60 / 255, 0.15) : "transparent"
                                                    ToolTip.visible: imgBtnHover.containsMouse
                                                    ToolTip.text: page.t("添加图片", "Add image")
                                                    WickIcon {
                                                        anchors.centerIn: parent
                                                        name: "photo.badge.plus"
                                                        size: 14
                                                        color: imgBtnHover.containsMouse ? theme.ember : theme.ink3
                                                    }
                                                    MouseArea {
                                                        id: imgBtnHover
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                             page.pendingImageItemId = modelData.itemId
                                                             attachDialog.open()
                                                        }
                                                    }
                                                }

                                                // [–] Delete item button
                                                Rectangle {
                                                    visible: !library.isReadOnly
                                                    width: 22
                                                    height: 22
                                                    radius: 3
                                                    color: delItemHover.containsMouse ? Qt.rgba(224 / 255, 76 / 255, 76 / 255, 0.15) : "transparent"
                                                    ToolTip.visible: delItemHover.containsMouse
                                                    ToolTip.text: page.t("删除条目", "Delete entry")
                                                    WickIcon {
                                                        anchors.centerIn: parent
                                                        name: "minus.circle"
                                                        size: 14
                                                        color: delItemHover.containsMouse ? theme.cinnabar : theme.ink3
                                                    }
                                                    MouseArea {
                                                        id: delItemHover
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (modelData.isEmpty) {
                                                                library.deleteItem(modelData.itemId)
                                                            } else {
                                                                page.pendingDeleteItemId = modelData.itemId
                                                                deleteItemConfirmDialog.open()
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            TextField {
                                                id: tagField
                                                Layout.fillWidth: true
                                                leftPadding: 0
                                                rightPadding: 0
                                                topPadding: 0
                                                bottomPadding: 0
                                                text: modelData.tag
                                                placeholderText: page.t("标签", "Tag")
                                                color: theme.pnlUp
                                                placeholderTextColor: theme.ink3
                                                font.family: theme.fontPrint
                                                font.pixelSize: 13
                                                font.weight: Font.Bold
                                                readOnly: library.isReadOnly
                                                background: Item {}
                                                onEditingFinished: library.setItemTag(modelData.itemId, text)
                                            }

                                            TextArea {
                                                id: bodyArea
                                                Layout.fillWidth: true
                                                leftPadding: 0
                                                rightPadding: 0
                                                topPadding: 0
                                                bottomPadding: 0
                                                Layout.preferredHeight: Math.max(68, implicitHeight)
                                                text: modelData.body
                                                placeholderText: page.t("记下此刻…", "Write something…")
                                                color: theme.ink1
                                                placeholderTextColor: theme.ink3
                                                font.family: theme.fontPrint
                                                font.pixelSize: 14
                                                wrapMode: TextEdit.Wrap
                                                readOnly: library.isReadOnly
                                                background: Item {}
                                                onTextChanged: {
                                                    if (activeFocus)
                                                        library.setItemBody(modelData.itemId, text)
                                                }
                                                Keys.onPressed: (event) => {
                                                    if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
                                                        if (library.pasteClipboardImage(modelData.itemId))
                                                            event.accepted = true
                                                    }
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 10
                                                visible: itemBlock.modelData.positions && itemBlock.modelData.positions.length > 0
                                                Repeater {
                                                    model: itemBlock.modelData.positions || []
                                                    delegate: PositionReceipt {
                                                        id: posReceipt
                                                        required property var modelData
                                                        required property int index
                                                        theme: page.theme
                                                        position: posReceipt.modelData
                                                        tilt: (posReceipt.index % 2 === 0) ? -0.4 : 0.5
                                                    }
                                                }
                                            }

                                            Flow {
                                                Layout.fillWidth: true
                                                spacing: 8
                                                visible: library.itemImageFilenames(itemBlock.modelData.itemId).length > 0
                                                Repeater {
                                                    model: library.itemImageFilenames(itemBlock.modelData.itemId)
                                                    delegate: Item {
                                                        id: thumb
                                                        required property string modelData
                                                        required property int index
                                                        width: 72
                                                        height: 72
                                                        Image {
                                                            anchors.fill: parent
                                                            source: library.imageFileUrl(thumb.modelData)
                                                            fillMode: Image.PreserveAspectCrop
                                                            asynchronous: true
                                                        }
                                                        Rectangle {
                                                            anchors.fill: parent
                                                            color: "transparent"
                                                            border.color: theme.rule
                                                            border.width: 1
                                                        }
                                                        MouseArea {
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                const imgs = library.itemImageFilenames(itemBlock.modelData.itemId)
                                                                page.openLightbox(imgs, thumb.index)
                                                            }
                                                        }
                                                        Rectangle {
                                                            visible: !library.isReadOnly
                                                            width: 16
                                                            height: 16
                                                            radius: 8
                                                            anchors.top: parent.top
                                                            anchors.right: parent.right
                                                            anchors.margins: 2
                                                            color: "transparent"
                                                            WickIcon {
                                                                anchors.fill: parent
                                                                name: "xmark.circle.fill"
                                                                size: 15
                                                                color: thumbDelHover.containsMouse ? theme.cinnabar : Qt.rgba(40 / 255, 30 / 255, 20 / 255, 0.65)
                                                            }
                                                            MouseArea {
                                                                id: thumbDelHover
                                                                anchors.fill: parent
                                                                hoverEnabled: true
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: library.removeImage(itemBlock.modelData.itemId, thumb.modelData)
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            // Note row if note exists
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 8
                                                visible: itemBlock.modelData.reviewNote && itemBlock.modelData.reviewNote.length > 0
                                                Rectangle {
                                                    Layout.preferredWidth: 2
                                                    Layout.preferredHeight: noteTextLab.implicitHeight
                                                    color: itemBlock.modelData.review === "wrong" ? theme.cinnabar : theme.dai
                                                }
                                                Text {
                                                    id: noteTextLab
                                                    Layout.fillWidth: true
                                                    text: itemBlock.modelData.reviewNote || ""
                                                    color: theme.ink2
                                                    font.family: theme.fontPrint
                                                    font.pixelSize: 12
                                                    wrapMode: Text.Wrap
                                                }
                                            }

                                            // In-row "复盘" call to action when unreviewed (styled with checkmark.seal icon as in iOS)
                                            RowLayout {
                                                Layout.fillWidth: true
                                                visible: daySection.modelData.reviewEligible && itemBlock.modelData.review.length === 0
                                                Item { Layout.fillWidth: true }

                                                Rectangle {
                                                    radius: 3
                                                    color: revBtnHover.containsMouse ? Qt.rgba(theme.cinnabar.r, theme.cinnabar.g, theme.cinnabar.b, 0.16)
                                                                                    : Qt.rgba(theme.cinnabar.r, theme.cinnabar.g, theme.cinnabar.b, 0.08)
                                                    implicitWidth: revBtnRow.implicitWidth + 12
                                                    implicitHeight: revBtnRow.implicitHeight + 6

                                                    RowLayout {
                                                        id: revBtnRow
                                                        anchors.centerIn: parent
                                                        spacing: 3

                                                        WickIcon {
                                                            name: "checkmark.seal"
                                                            size: 12
                                                            Layout.preferredWidth: 12
                                                            Layout.preferredHeight: 12
                                                            color: theme.cinnabar
                                                        }

                                                        Text {
                                                            text: page.t("复盘", "Review")
                                                            color: theme.cinnabar
                                                            font.family: theme.fontPrint
                                                            font.pixelSize: 11
                                                            font.weight: Font.Bold
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: revBtnHover
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: itemBlock.reviewOpen = !itemBlock.reviewOpen
                                                    }
                                                }
                                            }

                                            // Review Popover / Box
                                            Rectangle {
                                                visible: itemBlock.reviewOpen
                                                Layout.fillWidth: true
                                                implicitHeight: reviewCardCol.implicitHeight + 16
                                                radius: 4
                                                color: Qt.rgba(theme.ink1.r, theme.ink1.g, theme.ink1.b, 0.04)
                                                border.color: theme.rule
                                                border.width: 1

                                                ColumnLayout {
                                                    id: reviewCardCol
                                                    anchors.fill: parent
                                                    anchors.margins: 10
                                                    spacing: 8

                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 10

                                                        Text {
                                                            text: page.t("复盘定论", "Review Verdict")
                                                            color: theme.ink2
                                                            font.family: theme.fontPrint
                                                            font.pixelSize: 11
                                                            font.weight: Font.Bold
                                                        }

                                                        Item { Layout.fillWidth: true }

                                                        Row {
                                                            spacing: 8
                                                            Repeater {
                                                                model: ["correct", "wrong"]
                                                                delegate: Rectangle {
                                                                    required property string modelData
                                                                    width: 48
                                                                    height: 24
                                                                    radius: 3
                                                                    color: itemBlock.modelData.review === modelData
                                                                           ? (modelData === "correct" ? theme.dai : theme.cinnabar)
                                                                           : "transparent"
                                                                    border.color: modelData === "correct" ? theme.dai : theme.cinnabar
                                                                    border.width: 1
                                                                    Text {
                                                                        anchors.centerIn: parent
                                                                        text: modelData === "correct" ? page.t("✓ 正确", "✓ Good") : page.t("✗ 失误", "✗ Bad")
                                                                        color: itemBlock.modelData.review === modelData
                                                                               ? "#FFF"
                                                                               : (modelData === "correct" ? theme.dai : theme.cinnabar)
                                                                        font.family: theme.fontPrint
                                                                        font.pixelSize: 10
                                                                        font.weight: Font.Bold
                                                                    }
                                                                    MouseArea {
                                                                        anchors.fill: parent
                                                                        cursorShape: Qt.PointingHandCursor
                                                                        onClicked: {
                                                                            library.setItemReview(itemBlock.modelData.itemId, modelData, reviewNoteField.text)
                                                                        }
                                                                    }
                                                                }
                                                            }

                                                            Rectangle {
                                                                visible: itemBlock.modelData.review.length > 0
                                                                width: 38
                                                                height: 24
                                                                radius: 3
                                                                color: "transparent"
                                                                border.color: theme.rule
                                                                border.width: 1
                                                                Text {
                                                                    anchors.centerIn: parent
                                                                    text: page.t("清除", "Clear")
                                                                    color: theme.ink3
                                                                    font.family: theme.fontUi
                                                                    font.pixelSize: 10
                                                                }
                                                                MouseArea {
                                                                    anchors.fill: parent
                                                                    cursorShape: Qt.PointingHandCursor
                                                                    onClicked: {
                                                                        library.setItemReview(itemBlock.modelData.itemId, "", "")
                                                                        reviewNoteField.text = ""
                                                                    }
                                                                }
                                                            }

                                                            Text {
                                                                text: page.t("完成", "Done")
                                                                color: theme.ember
                                                                font.family: theme.fontUi
                                                                font.pixelSize: 11
                                                                font.weight: Font.DemiBold
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                MouseArea {
                                                                    anchors.fill: parent
                                                                    cursorShape: Qt.PointingHandCursor
                                                                    onClicked: itemBlock.reviewOpen = false
                                                                }
                                                            }
                                                        }
                                                    }

                                                    TextArea {
                                                        id: reviewNoteField
                                                        Layout.fillWidth: true
                                                        Layout.preferredHeight: Math.max(48, implicitHeight)
                                                        text: itemBlock.modelData.reviewNote || ""
                                                        placeholderText: page.t("写下这笔交易/决策的复盘体会、教训或规则…", "Write review notes, lessons, or rules for this trade/decision…")
                                                        color: theme.ink1
                                                        placeholderTextColor: theme.ink3
                                                        font.family: theme.fontPrint
                                                        font.pixelSize: 12
                                                        wrapMode: TextEdit.Wrap
                                                        background: Rectangle {
                                                            color: theme.paperHi
                                                            border.color: theme.rule
                                                            border.width: 1
                                                            radius: 3
                                                        }
                                                        onTextChanged: {
                                                            if (activeFocus && itemBlock.modelData.review.length > 0)
                                                                library.setItemReviewNote(itemBlock.modelData.itemId, text)
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // Floating review seal over the bottom-right corner of the whole card (including position receipt)
                                        ReviewSeal {
                                            visible: modelData.review.length > 0
                                            theme: page.theme
                                            verdict: modelData.review
                                            size: 56
                                            floating: true
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            anchors.rightMargin: 4
                                            anchors.bottomMargin: 4
                                            z: 10
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                enabled: daySection.modelData.reviewEligible && !library.isReadOnly
                                                onClicked: itemBlock.reviewOpen = !itemBlock.reviewOpen
                                            }
                                        }
                                    }
                                }
                            }

                            // Add item action at the bottom of each day section
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.topMargin: 10
                                Layout.preferredHeight: 32
                                radius: 4
                                color: addBtnHover.containsMouse ? Qt.rgba(0, 0, 0, 0.04) : "transparent"
                                border.color: theme.rule
                                border.width: 1
                                opacity: 0.9
                                visible: !library.isReadOnly

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 6
                                    WickIcon {
                                        name: "plus"
                                        size: 10
                                        color: addBtnHover.containsMouse ? theme.ember : theme.ink3
                                    }
                                    Text {
                                        text: page.t("添加条目", "Add entry")
                                        color: addBtnHover.containsMouse ? theme.ember : theme.ink3
                                        font.family: theme.fontPrint
                                        font.pixelSize: 11
                                    }
                                }

                                MouseArea {
                                    id: addBtnHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: library.addItemTo(daySection.modelData.entryId)
                                }
                            }

                            Item { Layout.preferredHeight: 14 }
                        }
                    }
                }
            }
        }
    }

    FileDialog {
        id: attachDialog
        fileMode: FileDialog.OpenFile
        nameFilters: ["Images (*.png *.jpg *.jpeg *.gif *.webp *.bmp *.tif *.tiff *.heic)"]
        onAccepted: {
            if (page.pendingImageItemId.length > 0)
                library.addImageFromUrl(page.pendingImageItemId, selectedFile)
            page.pendingImageItemId = ""
        }
    }

    Rectangle {
        id: deleteDayConfirmDialog
        visible: false
        anchors.fill: parent
        z: 90
        color: Qt.rgba(18 / 255, 13 / 255, 7 / 255, 0.6)

        function open() { visible = true }
        function close() { visible = false }

        MouseArea { anchors.fill: parent }

        Rectangle {
            width: 320
            height: 140
            anchors.centerIn: parent
            color: theme.paperHi
            border.color: theme.rule
            border.width: 1
            radius: 6

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 12

                Text {
                    text: page.t("删除日记", "Delete Journal")
                    color: theme.ink1
                    font.family: theme.fontPrint
                    font.pixelSize: 14
                    font.weight: Font.Bold
                }

                Text {
                    text: page.t("确定要删除该日期的所有日记与条目吗？此操作无法撤销。",
                                 "Are you sure you want to delete this full day journal and all its entries? This cannot be undone.")
                    color: theme.ink2
                    font.family: theme.fontUi
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: 10

                    Button {
                        text: page.t("取消", "Cancel")
                        font.family: theme.fontUi
                        font.pixelSize: 12
                        onClicked: deleteDayConfirmDialog.close()
                    }

                    Button {
                        text: page.t("删除", "Delete")
                        font.family: theme.fontUi
                        font.pixelSize: 12
                        contentItem: Text {
                            text: page.t("删除", "Delete")
                            color: theme.cinnabar
                            font.family: theme.fontUi
                            font.pixelSize: 12
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: {
                            deleteDayConfirmDialog.close()
                            if (page.pendingDeleteEntryId.length > 0)
                                library.deleteDay(page.pendingDeleteEntryId)
                            else
                                library.deleteSelectedDay()
                            page.pendingDeleteEntryId = ""
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: deleteItemConfirmDialog
        visible: false
        anchors.fill: parent
        z: 90
        color: Qt.rgba(18 / 255, 13 / 255, 7 / 255, 0.6)

        function open() { visible = true }
        function close() { visible = false }

        MouseArea { anchors.fill: parent }

        Rectangle {
            width: 320
            height: 130
            anchors.centerIn: parent
            color: theme.paperHi
            border.color: theme.rule
            border.width: 1
            radius: 6

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 12

                Text {
                    text: page.t("删除条目", "Delete Entry")
                    color: theme.ink1
                    font.family: theme.fontPrint
                    font.pixelSize: 14
                    font.weight: Font.Bold
                }

                Text {
                    text: page.t("确定要删除该条目吗？", "Are you sure you want to delete this entry?")
                    color: theme.ink2
                    font.family: theme.fontUi
                    font.pixelSize: 12
                    Layout.fillWidth: true
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: 10

                    Button {
                        text: page.t("取消", "Cancel")
                        font.family: theme.fontUi
                        font.pixelSize: 12
                        onClicked: deleteItemConfirmDialog.close()
                    }

                    Button {
                        text: page.t("删除", "Delete")
                        font.family: theme.fontUi
                        font.pixelSize: 12
                        contentItem: Text {
                            text: page.t("删除", "Delete")
                            color: theme.cinnabar
                            font.family: theme.fontUi
                            font.pixelSize: 12
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: {
                            deleteItemConfirmDialog.close()
                            if (page.pendingDeleteItemId.length > 0) {
                                library.deleteItem(page.pendingDeleteItemId)
                                page.pendingDeleteItemId = ""
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: lightboxOverlay
        anchors.fill: parent
        z: 100
        visible: page.lightboxVisible
        color: Qt.rgba(16 / 255, 14 / 255, 13 / 255, 0.94)

        FocusScope {
            anchors.fill: parent
            focus: lightboxOverlay.visible
            Keys.onEscapePressed: page.closeLightbox()
            Keys.onLeftPressed: page.prevLightbox()
            Keys.onRightPressed: page.nextLightbox()

            MouseArea {
                anchors.fill: parent
                onClicked: page.closeLightbox()
            }

            Image {
                id: lightboxImg
                anchors.fill: parent
                anchors.margins: 56
                source: (page.lightboxImages.length > page.lightboxIndex && page.lightboxIndex >= 0)
                        ? library.imageFileUrl(page.lightboxImages[page.lightboxIndex])
                        : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }

            Rectangle {
                width: 32
                height: 32
                radius: 16
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 16
                color: Qt.rgba(255, 255, 255, 0.15)
                Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: "#FFF"
                    font.pixelSize: 18
                    font.bold: true
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.closeLightbox()
                }
            }

            Rectangle {
                visible: page.lightboxImages.length > 1
                width: 36
                height: 36
                radius: 18
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                color: Qt.rgba(255, 255, 255, 0.15)
                Text {
                    anchors.centerIn: parent
                    text: "‹"
                    color: "#FFF"
                    font.pixelSize: 24
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.prevLightbox()
                }
            }

            Rectangle {
                visible: page.lightboxImages.length > 1
                width: 36
                height: 36
                radius: 18
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                color: Qt.rgba(255, 255, 255, 0.15)
                Text {
                    anchors.centerIn: parent
                    text: "›"
                    color: "#FFF"
                    font.pixelSize: 24
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.nextLightbox()
                }
            }

            Text {
                visible: page.lightboxImages.length > 1
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 20
                anchors.horizontalCenter: parent.horizontalCenter
                text: (page.lightboxIndex + 1) + " / " + page.lightboxImages.length
                color: Qt.rgba(255, 255, 255, 0.75)
                font.family: theme.fontMono
                font.pixelSize: 12
            }
        }
    }
}

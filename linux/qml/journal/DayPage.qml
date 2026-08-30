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
    property bool lightboxVisible: false
    property var lightboxImages: []
    property int lightboxIndex: 0

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

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.topMargin: 20
        anchors.bottomMargin: 20
        anchors.leftMargin: 28
        anchors.rightMargin: 28
        contentWidth: width
        contentHeight: sheetWrap.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Item {
            id: sheetWrap
            width: Math.min(parent.width, 880)
            anchors.horizontalCenter: parent.horizontalCenter
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

                Text {
                    visible: !library.hasSelectedDay
                    Layout.fillWidth: true
                    Layout.preferredHeight: 120
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: library.isCatalogReadOnly ? "目录不可用" : "选择一日，或点 ＋ 写下今天"
                    color: theme.ink3
                    font.family: theme.fontPrint
                    font.pixelSize: 14
                }

                ColumnLayout {
                    visible: library.hasSelectedDay
                    Layout.fillWidth: true
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14

                        Text {
                            text: library.pageDateLabel
                            color: theme.ink1
                            font.family: theme.fontPrint
                            font.pixelSize: 28
                            font.weight: Font.Black
                        }

                        Column {
                            spacing: 2
                            Layout.bottomMargin: 3
                            Text {
                                text: library.pageWeekday
                                color: theme.ink2
                                font.family: theme.fontPrint
                                font.pixelSize: 11
                            }
                            Text {
                                text: library.pageLunar
                                color: theme.ink2
                                font.family: theme.fontPrint
                                font.pixelSize: 11
                                visible: library.pageLunar.length > 0
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: library.pageSavedState
                            color: library.isReadOnly ? theme.cinnabar : theme.ink3
                            font.family: theme.fontMono
                            font.pixelSize: 9
                            Layout.bottomMargin: 5
                            visible: library.pageSavedState.length > 0
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.topMargin: 12
                        Layout.preferredHeight: library.pageIsToday ? 28 : 8

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
                                width: Math.max(0, Math.min(1, library.pageBurnElapsed)) * burnTrack.width
                                height: burnTrack.height
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: theme.stain1 }
                                    GradientStop { position: 1.0; color: theme.stain2 }
                                }
                            }
                            Rectangle {
                                visible: library.pageIsToday && library.pageBurnElapsed > 0.002
                                         && library.pageBurnElapsed < 0.998
                                width: 3
                                height: burnTrack.height
                                x: burnFill.width - 1
                                color: theme.ember
                            }
                        }

                        RowLayout {
                            visible: library.pageIsToday
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            Text {
                                text: Math.round(library.pageBurnElapsed * 100) + "% 已过"
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

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 0

                        Repeater {
                            model: library.items
                            delegate: Item {
                                id: itemBlock
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                implicitHeight: itemCol.implicitHeight + 24

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

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            text: modelData.index
                                            color: theme.ink3
                                            font.family: theme.fontMono
                                            font.pixelSize: 10
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            visible: modelData.isEmpty && !library.isReadOnly
                                            text: "–"
                                            color: theme.ink3
                                            font.pixelSize: 16
                                            MouseArea {
                                                anchors.fill: parent
                                                anchors.margins: -6
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: library.deleteEmptyItem(modelData.itemId)
                                            }
                                        }
                                    }

                                    TextField {
                                        id: tagField
                                        Layout.fillWidth: true
                                        text: modelData.tag
                                        placeholderText: "标签"
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
                                        Layout.preferredHeight: Math.max(72, implicitHeight)
                                        text: modelData.body
                                        placeholderText: "记下此刻…"
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
                                                theme: page.theme
                                                position: posReceipt.modelData
                                            }
                                        }
                                    }

                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: 8
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
                                                    color: theme.paperHi
                                                    border.color: theme.ink3
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "×"
                                                        color: theme.ink2
                                                        font.pixelSize: 10
                                                    }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: library.removeImage(itemBlock.modelData.itemId, thumb.modelData)
                                                    }
                                                }
                                            }
                                        }
                                        Rectangle {
                                            visible: !library.isReadOnly
                                            width: 72
                                            height: 72
                                            radius: 4
                                            color: "transparent"
                                            border.color: theme.rule
                                            border.width: 1
                                            Text {
                                                anchors.centerIn: parent
                                                text: "+"
                                                color: theme.ink3
                                                font.pixelSize: 20
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    page.pendingImageItemId = itemBlock.modelData.itemId
                                                    attachDialog.open()
                                                }
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        visible: library.pageReviewEligible && modelData.review.length === 0
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: "复盘"
                                            color: Qt.rgba(224 / 255, 106 / 255, 76 / 255, 0.8)
                                            font.family: theme.fontPrint
                                            font.pixelSize: 12
                                            font.weight: Font.Bold
                                            rotation: -3
                                            MouseArea {
                                                anchors.fill: parent
                                                anchors.margins: -10
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: itemBlock.reviewOpen = !itemBlock.reviewOpen
                                            }
                                        }
                                    }

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
                                                    text: "复盘定论"
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
                                                            width: 46
                                                            height: 24
                                                            radius: 3
                                                            color: itemBlock.modelData.review === modelData
                                                                   ? (modelData === "correct" ? theme.dai : theme.cinnabar)
                                                                   : "transparent"
                                                            border.color: modelData === "correct" ? theme.dai : theme.cinnabar
                                                            border.width: 1
                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: modelData === "correct" ? "✓ 正确" : "✗ 失误"
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
                                                            text: "清除"
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
                                                        text: "完成"
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
                                                placeholderText: "写下这笔交易/决策的复盘体会、教训或规则…"
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

                                ReviewSeal {
                                    visible: modelData.review.length > 0
                                    theme: page.theme
                                    verdict: modelData.review
                                    size: 56
                                    floating: true
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.rightMargin: 2
                                    anchors.bottomMargin: 6
                                    z: 2
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        enabled: library.pageReviewEligible && !library.isReadOnly
                                        onClicked: itemBlock.reviewOpen = !itemBlock.reviewOpen
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 10
                        Layout.preferredHeight: 32
                        radius: 4
                        color: "transparent"
                        border.color: theme.rule
                        border.width: 1
                        opacity: 0.9
                        visible: !library.isReadOnly

                        Text {
                            anchors.centerIn: parent
                            text: "+  添加条目"
                            color: theme.ink3
                            font.family: theme.fontPrint
                            font.pixelSize: 11
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: library.addItem()
                        }
                    }

                    Item { Layout.preferredHeight: 14 }
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

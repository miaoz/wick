import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: page
    required property var theme
    required property var library
    color: theme.paper

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.topMargin: 20
        anchors.bottomMargin: 20
        anchors.leftMargin: 28
        anchors.rightMargin: 28
        contentWidth: width
        contentHeight: sheet.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Rectangle {
            id: sheet
            width: Math.min(parent.width, 880)
            anchors.horizontalCenter: parent.horizontalCenter
            implicitHeight: sheetCol.implicitHeight + 34
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
                                width: Math.max(0, Math.min(1, library.pageBurnElapsed)) * burnTrack.width
                                height: burnTrack.height
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: theme.stain1 }
                                    GradientStop { position: 1.0; color: theme.stain2 }
                                }
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

                                    Row {
                                        visible: itemBlock.reviewOpen || (library.pageReviewEligible && modelData.review.length > 0 && itemBlock.reviewOpen)
                                        Layout.alignment: Qt.AlignRight
                                        spacing: 12
                                        Repeater {
                                            model: ["correct", "wrong"]
                                            delegate: Rectangle {
                                                required property string modelData
                                                width: 40
                                                height: 40
                                                radius: 3
                                                rotation: -6
                                                color: modelData === "correct" ? theme.gain : theme.loss
                                                opacity: (itemBlock.modelData.review === modelData || itemBlock.modelData.review.length === 0) ? 1 : 0.3
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: modelData === "correct" ? "✓" : "✗"
                                                    color: theme.sealInk
                                                    font.family: theme.fontPrint
                                                    font.pixelSize: 20
                                                    font.weight: Font.Bold
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        library.setItemReview(itemBlock.modelData.itemId, modelData)
                                                        itemBlock.reviewOpen = false
                                                    }
                                                }
                                            }
                                        }
                                        Text {
                                            visible: itemBlock.modelData.review.length > 0
                                            text: "清除"
                                            color: theme.ink3
                                            font.family: theme.fontUi
                                            font.pixelSize: 12
                                            anchors.verticalCenter: parent.verticalCenter
                                            MouseArea {
                                                anchors.fill: parent
                                                anchors.margins: -4
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    library.setItemReview(itemBlock.modelData.itemId, "")
                                                    itemBlock.reviewOpen = false
                                                }
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    visible: modelData.review.length > 0
                                    width: 56
                                    height: 56
                                    radius: 4
                                    rotation: -6
                                    opacity: 0.82
                                    color: modelData.review === "correct" ? theme.gain : theme.loss
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.rightMargin: 2
                                    anchors.bottomMargin: 6
                                    z: 2
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.review === "correct" ? "✓" : "✗"
                                        color: theme.sealInk
                                        font.family: theme.fontPrint
                                        font.pixelSize: 28
                                        font.weight: Font.Bold
                                    }
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

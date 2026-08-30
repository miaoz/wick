import QtQuick
import QtQuick.Layouts

Item {
    id: receiptItem
    property var position: null
    property var theme

    readonly property var d: position || {}

    Layout.fillWidth: true
    implicitHeight: card.implicitHeight + 14

    Rectangle {
        id: card
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 8
        anchors.bottomMargin: 6
        implicitHeight: contentCol.implicitHeight + 20
        rotation: (typeof d.tilt === "number") ? d.tilt : 0
        transformOrigin: Item.Center

        color: (theme && theme.scheme === "dark") ? "#F5EEDC" : "#FFFDF4"
        radius: 3
        border.color: Qt.rgba(51 / 255, 41 / 255, 26 / 255, 0.18)
        border.width: 1

        // Drop shadow feel
        Rectangle {
            z: -1
            anchors.fill: parent
            anchors.topMargin: 2
            anchors.leftMargin: 1
            anchors.rightMargin: -1
            anchors.bottomMargin: -2
            radius: 3
            color: Qt.rgba(0, 0, 0, 0.06)
        }

        // Tape strips
        Rectangle {
            width: 44
            height: 12
            color: Qt.rgba(235 / 255, 225 / 255, 205 / 255, 0.75)
            border.color: Qt.rgba(210 / 255, 200 / 255, 180 / 255, 0.5)
            border.width: 0.5
            radius: 1
            rotation: -4
            anchors.top: parent.top
            anchors.topMargin: -6
            anchors.left: parent.left
            anchors.leftMargin: 14
            z: 2
        }

        Rectangle {
            width: 44
            height: 12
            color: Qt.rgba(235 / 255, 225 / 255, 205 / 255, 0.75)
            border.color: Qt.rgba(210 / 255, 200 / 255, 180 / 255, 0.5)
            border.width: 0.5
            radius: 1
            rotation: 3
            anchors.top: parent.top
            anchors.topMargin: -6
            anchors.right: parent.right
            anchors.rightMargin: 14
            z: 2
        }

        ColumnLayout {
            id: contentCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 4

            // Header: Symbol + Lane Badge + Date range
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: d.headerTitle || d.symbol || ""
                    color: "#33291A"
                    font.family: theme ? theme.fontMono : "JetBrains Mono"
                    font.pixelSize: 11
                    font.weight: Font.Bold
                }

                Rectangle {
                    radius: 2
                    color: d.isLong ? Qt.rgba(176 / 255, 52 / 255, 30 / 255, 0.12)
                                    : Qt.rgba(62 / 255, 92 / 255, 80 / 255, 0.12)
                    implicitWidth: laneText.implicitWidth + 8
                    implicitHeight: laneText.implicitHeight + 2

                    Text {
                        id: laneText
                        anchors.centerIn: parent
                        text: d.laneLabel || (d.isLong ? "多" : "空")
                        color: d.isLong ? "#B0341E" : "#3E5C50"
                        font.family: theme ? theme.fontUi : "Inter"
                        font.pixelSize: 9
                        font.weight: Font.Bold
                    }
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: d.dateRange || ""
                    color: Qt.rgba(51 / 255, 41 / 255, 26 / 255, 0.65)
                    font.family: theme ? theme.fontMono : "JetBrains Mono"
                    font.pixelSize: 9
                }
            }

            // Dashed header rule
            Canvas {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                Layout.topMargin: 2
                Layout.bottomMargin: 2
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    ctx.strokeStyle = Qt.rgba(51 / 255, 41 / 255, 26 / 255, 0.3)
                    ctx.lineWidth = 1
                    ctx.setLineDash([3, 2.5])
                    ctx.beginPath()
                    ctx.moveTo(0, 0.5)
                    ctx.lineTo(width, 0.5)
                    ctx.stroke()
                }
            }

            // Row 1: VWAP
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "开仓 → 平仓 VWAP"
                    color: Qt.rgba(51 / 255, 41 / 255, 26 / 255, 0.66)
                    font.family: theme ? theme.fontMono : "JetBrains Mono"
                    font.pixelSize: 10
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: d.priceText || ""
                    color: "#33291A"
                    font.family: theme ? theme.fontMono : "JetBrains Mono"
                    font.pixelSize: 10
                }
            }

            // Row 2: Size & duration
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "数量 · 持有"
                    color: Qt.rgba(51 / 255, 41 / 255, 26 / 255, 0.66)
                    font.family: theme ? theme.fontMono : "JetBrains Mono"
                    font.pixelSize: 10
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: d.sizeText || ""
                    color: "#33291A"
                    font.family: theme ? theme.fontMono : "JetBrains Mono"
                    font.pixelSize: 10
                }
            }

            // Row 3: Fees & Funding
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "手续费 · 资金费"
                    color: Qt.rgba(51 / 255, 41 / 255, 26 / 255, 0.66)
                    font.family: theme ? theme.fontMono : "JetBrains Mono"
                    font.pixelSize: 10
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: d.feesText || ""
                    color: "#33291A"
                    font.family: theme ? theme.fontMono : "JetBrains Mono"
                    font.pixelSize: 10
                }
            }

            // Dashed total rule
            Canvas {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                Layout.topMargin: 3
                Layout.bottomMargin: 2
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    ctx.strokeStyle = Qt.rgba(51 / 255, 41 / 255, 26 / 255, 0.35)
                    ctx.lineWidth = 1
                    ctx.setLineDash([3, 2.5])
                    ctx.beginPath()
                    ctx.moveTo(0, 0.5)
                    ctx.lineTo(width, 0.5)
                    ctx.stroke()
                }
            }

            // Row 4: Total Realized PnL
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: d.isClosed ? "已实现盈亏" : "持仓状态"
                    color: "#33291A"
                    font.family: theme ? theme.fontMono : "JetBrains Mono"
                    font.pixelSize: 11
                    font.weight: Font.Bold
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: d.isClosed ? (d.netPnlText || "") : "持仓中"
                    color: {
                        if (!d.isClosed)
                            return Qt.rgba(51 / 255, 41 / 255, 26 / 255, 0.75)
                        if (theme)
                            return (d.netPnl || 0) >= 0 ? theme.gain : theme.loss
                        return (d.netPnl || 0) >= 0 ? "#3E5C50" : "#B0341E"
                    }
                    font.family: theme ? theme.fontMono : "JetBrains Mono"
                    font.pixelSize: 12
                    font.weight: Font.Bold
                }
            }
        }
    }
}

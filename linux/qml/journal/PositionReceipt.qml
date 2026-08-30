import QtQuick
import QtQuick.Layouts

Item {
    id: receiptItem
    property var position: null
    property var theme
    property real tilt: 0

    readonly property var d: position || {}
    property bool showsBreakdown: false

    Layout.fillWidth: true
    implicitHeight: card.implicitHeight + 16

    Item {
        id: card
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 10
        anchors.bottomMargin: 6
        implicitHeight: contentCol.implicitHeight + 24
        rotation: (typeof d.tilt === "number" && d.tilt !== 0) ? d.tilt : receiptItem.tilt
        transformOrigin: Item.Center

        Connections {
            target: theme || null
            function onPalChanged() {
                paperBg.requestPaint()
                dashedRule1.requestPaint()
                dashedRule2.requestPaint()
                if (dashedRule3.visible)
                    dashedRule3.requestPaint()
            }
        }

        // Torn Paper Canvas
        Canvas {
            id: paperBg
            anchors.fill: parent
            anchors.margins: -4
            antialiasing: true
            z: 0

            onPaint: {
                var ctx = getContext("2d")
                var w = width
                var h = height
                ctx.reset()
                ctx.clearRect(0, 0, w, h)

                var tearAmplitude = 1.4
                var seed = 11

                function tear(t, phase) {
                    return Math.sin(t * 24 + phase) * tearAmplitude * 0.5
                         + Math.sin(t * 57 + phase * 2.1) * tearAmplitude * 0.32
                         + Math.sin(t * 8 + phase * 0.8) * tearAmplitude * 0.42
                }

                var inset = tearAmplitude + 4
                var top = inset
                var bottom = h - inset
                var left = 4
                var right = w - 4
                var steps = 32

                // Shadow
                ctx.save()
                ctx.shadowColor = Qt.rgba(0, 0, 0, 0.12)
                ctx.shadowBlur = 4
                ctx.shadowOffsetY = 1.5

                ctx.beginPath()
                ctx.moveTo(left, top + tear(0, seed))
                for (var s = 1; s <= steps; ++s) {
                    var t = s / steps
                    ctx.lineTo(left + (right - left) * t, top + tear(t, seed))
                }
                ctx.lineTo(right, bottom + tear(1, seed + 5))
                for (var s = 1; s <= steps; ++s) {
                    var t = s / steps
                    ctx.lineTo(right - (right - left) * t, bottom + tear(1 - t, seed + 5))
                }
                ctx.closePath()

                // Receipt paper background from theme
                ctx.fillStyle = theme ? theme.receipt : "#F5EEDC"
                ctx.fill()
                ctx.restore()

                // Paper border stroke
                ctx.strokeStyle = theme ? theme.rule : Qt.rgba(51 / 255, 41 / 255, 26 / 255, 0.18)
                ctx.lineWidth = 0.8
                ctx.stroke()
            }
        }

        // Left Washi Tape
        Rectangle {
            width: 46
            height: 13
            radius: 1.5
            color: theme ? theme.tape : Qt.rgba(238 / 255, 212 / 255, 153 / 255, 0.58)
            border.color: theme ? theme.tapeBorder : Qt.rgba(217 / 255, 184 / 255, 115 / 255, 0.45)
            border.width: 0.5
            rotation: -4
            anchors.top: parent.top
            anchors.topMargin: -6
            anchors.left: parent.left
            anchors.leftMargin: 16
            z: 10
        }

        // Right Washi Tape
        Rectangle {
            width: 46
            height: 13
            radius: 1.5
            color: theme ? theme.tape : Qt.rgba(238 / 255, 212 / 255, 153 / 255, 0.58)
            border.color: theme ? theme.tapeBorder : Qt.rgba(217 / 255, 184 / 255, 115 / 255, 0.45)
            border.width: 0.5
            rotation: 3
            anchors.top: parent.top
            anchors.topMargin: -6
            anchors.right: parent.right
            anchors.rightMargin: 16
            z: 10
        }

        ColumnLayout {
            id: contentCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.topMargin: 10
            anchors.bottomMargin: 8
            spacing: 3
            z: 1

            // Header: Symbol + Lane Badge + Date range
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: d.headerTitle || d.symbol || ""
                    color: theme ? theme.receiptInk : "#33291A"
                    font.family: theme ? theme.fontMono : "JetBrains Mono"
                    font.pixelSize: 11
                    font.weight: Font.Bold
                }

                Rectangle {
                    radius: 2.5
                    color: d.isLong ? (theme ? Qt.rgba(theme.cinnabar.r, theme.cinnabar.g, theme.cinnabar.b, 0.16) : Qt.rgba(176 / 255, 52 / 255, 30 / 255, 0.12))
                                    : (theme ? Qt.rgba(theme.dai.r, theme.dai.g, theme.dai.b, 0.16) : Qt.rgba(62 / 255, 92 / 255, 80 / 255, 0.12))
                    implicitWidth: laneText.implicitWidth + 8
                    implicitHeight: laneText.implicitHeight + 2

                    Text {
                        id: laneText
                        anchors.centerIn: parent
                        text: d.laneLabel || (d.isLong ? "多" : "空")
                        color: d.isLong ? (theme ? theme.cinnabar : "#B0341E") : (theme ? theme.dai : "#3E5C50")
                        font.family: theme ? theme.fontUi : "Inter"
                        font.pixelSize: 9
                        font.weight: Font.Bold
                    }
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: d.dateRange || ""
                    color: theme ? theme.ink3 : Qt.rgba(51 / 255, 41 / 255, 26 / 255, 0.6)
                    font.family: theme ? theme.fontMono : "JetBrains Mono"
                    font.pixelSize: 9
                }
            }

            // Dashed header rule
            Canvas {
                id: dashedRule1
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                Layout.topMargin: 2
                Layout.bottomMargin: 2
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    ctx.strokeStyle = theme ? theme.receiptRule : Qt.rgba(51 / 255, 41 / 255, 26 / 255, 0.35)
                    ctx.lineWidth = 0.8
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
                    color: theme ? theme.ink2 : Qt.rgba(51 / 255, 41 / 255, 26 / 255, 0.72)
                    font.family: theme ? theme.fontUi : "Inter"
                    font.pixelSize: 10
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: d.priceText || ""
                    color: theme ? theme.receiptInk : "#33291A"
                    font.family: theme ? theme.fontMono : "JetBrains Mono"
                    font.pixelSize: 10
                }
            }

            // Row 2: Size & duration
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "数量 · 持有"
                    color: theme ? theme.ink2 : Qt.rgba(51 / 255, 41 / 255, 26 / 255, 0.72)
                    font.family: theme ? theme.fontUi : "Inter"
                    font.pixelSize: 10
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: d.sizeText || ""
                    color: theme ? theme.receiptInk : "#33291A"
                    font.family: theme ? theme.fontMono : "JetBrains Mono"
                    font.pixelSize: 10
                }
            }

            // Row 3: Fees & Funding summary or expandable
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "手续费 · 资金费"
                    color: theme ? theme.ink2 : Qt.rgba(51 / 255, 41 / 255, 26 / 255, 0.72)
                    font.family: theme ? theme.fontUi : "Inter"
                    font.pixelSize: 10
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: d.feesText || ""
                    color: theme ? theme.receiptInk : "#33291A"
                    font.family: theme ? theme.fontMono : "JetBrains Mono"
                    font.pixelSize: 10
                }
            }

            // Dashed total rule
            Canvas {
                id: dashedRule2
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                Layout.topMargin: 2
                Layout.bottomMargin: 2
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    ctx.strokeStyle = theme ? theme.receiptRule : Qt.rgba(51 / 255, 41 / 255, 26 / 255, 0.35)
                    ctx.lineWidth = 0.8
                    ctx.setLineDash([3, 2.5])
                    ctx.beginPath()
                    ctx.moveTo(0, 0.5)
                    ctx.lineTo(width, 0.5)
                    ctx.stroke()
                }
            }

            // Row 4: Total Realized PnL (Clickable to toggle breakdown)
            RowLayout {
                Layout.fillWidth: true

                Item {
                    implicitWidth: toggleRow.implicitWidth
                    implicitHeight: toggleRow.implicitHeight

                    RowLayout {
                        id: toggleRow
                        anchors.fill: parent
                        spacing: 4
                        Text {
                            visible: d.isClosed
                            text: receiptItem.showsBreakdown ? "▾" : "▸"
                            color: theme ? theme.ink3 : Qt.rgba(51 / 255, 41 / 255, 26 / 255, 0.6)
                            font.family: theme ? theme.fontMono : "JetBrains Mono"
                            font.pixelSize: 8
                            font.bold: true
                        }
                        Text {
                            text: d.isClosed ? "净已实现盈亏" : "持仓状态"
                            color: theme ? theme.receiptInk : "#33291A"
                            font.family: theme ? theme.fontUi : "Inter"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: d.isClosed ? Qt.PointingHandCursor : Qt.ArrowCursor
                        enabled: d.isClosed
                        onClicked: receiptItem.showsBreakdown = !receiptItem.showsBreakdown
                    }
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: d.isClosed ? (d.netPnlText || "") : "持仓中"
                    color: {
                        if (!d.isClosed)
                            return theme ? theme.ink3 : Qt.rgba(51 / 255, 41 / 255, 26 / 255, 0.75)
                        return (d.netPnl || 0) >= 0 ? (theme ? theme.gain : "#3E5C50") : (theme ? theme.loss : "#B0341E")
                    }
                    font.family: theme ? theme.fontMono : "JetBrains Mono"
                    font.pixelSize: 12
                    font.weight: Font.Bold
                }
            }

            // Expanded Breakdown Rows
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                visible: receiptItem.showsBreakdown && d.isClosed

                Canvas {
                    id: dashedRule3
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        ctx.strokeStyle = theme ? theme.receiptRule : Qt.rgba(51 / 255, 41 / 255, 26 / 255, 0.25)
                        ctx.lineWidth = 0.8
                        ctx.setLineDash([2, 2])
                        ctx.beginPath()
                        ctx.moveTo(0, 0.5)
                        ctx.lineTo(width, 0.5)
                        ctx.stroke()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "  已实现盈亏"
                        color: theme ? theme.ink2 : Qt.rgba(51 / 255, 41 / 255, 26 / 255, 0.65)
                        font.family: theme ? theme.fontUi : "Inter"
                        font.pixelSize: 10
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: (d.realizedPnl >= 0 ? "+" : "") + (d.realizedPnl || 0).toFixed(2) + " USDT"
                        color: (d.realizedPnl || 0) >= 0 ? (theme ? theme.gain : "#3E5C50") : (theme ? theme.loss : "#B0341E")
                        font.family: theme ? theme.fontMono : "JetBrains Mono"
                        font.pixelSize: 10
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "  手续费"
                        color: theme ? theme.ink2 : Qt.rgba(51 / 255, 41 / 255, 26 / 255, 0.65)
                        font.family: theme ? theme.fontUi : "Inter"
                        font.pixelSize: 10
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: ((d.commissionTotal || 0) >= 0 ? "+" : "") + (d.commissionTotal || 0).toFixed(2) + " USDT"
                        color: (d.commissionTotal || 0) <= 0 ? (theme ? theme.loss : "#B0341E") : (theme ? theme.gain : "#3E5C50")
                        font.family: theme ? theme.fontMono : "JetBrains Mono"
                        font.pixelSize: 10
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "  资金费"
                        color: theme ? theme.ink2 : Qt.rgba(51 / 255, 41 / 255, 26 / 255, 0.65)
                        font.family: theme ? theme.fontUi : "Inter"
                        font.pixelSize: 10
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: ((d.fundingPnl || 0) >= 0 ? "+" : "") + (d.fundingPnl || 0).toFixed(2) + " USDT"
                        color: (d.fundingPnl || 0) >= 0 ? (theme ? theme.gain : "#3E5C50") : (theme ? theme.loss : "#B0341E")
                        font.family: theme ? theme.fontMono : "JetBrains Mono"
                        font.pixelSize: 10
                    }
                }
            }
        }
    }
}

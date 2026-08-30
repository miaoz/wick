import QtQuick

// White-character square seal (白文方章). Ports WickCalendarKit/JournalReviewBadge:
// chipped silhouette, pooled ink, crisp ✓/✗. Ink follows the PnL convention.
Item {
    id: seal
    property var theme
    property string verdict: "correct" // correct | wrong
    property real size: 56
    property bool mini: false
    property bool floating: false
    property bool dimmed: false

    width: size
    height: size
    rotation: mini ? 0 : -6
    opacity: {
        if (dimmed)
            return 0.3
        if (floating)
            return 0.82 * stamp
        return stamp
    }
    scale: mini ? 1 : (0.4 + 0.6 * stamp)
    transformOrigin: Item.Center

    property real stamp: mini ? 1 : 0
    property color ink: verdict === "correct" ? theme.gain : theme.loss
    property color glyphColor: theme.sealInk

    NumberAnimation on stamp {
        id: slam
        from: 0
        to: 1
        duration: 300
        easing.type: Easing.OutBack
        easing.overshoot: 1.15
        running: false
    }

    Component.onCompleted: {
        if (mini)
            stamp = 1
        else
            slam.start()
    }

    onVerdictChanged: canvas.requestPaint()
    onInkChanged: canvas.requestPaint()
    onSizeChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true
        onPaint: {
            var ctx = getContext("2d")
            var w = width
            var h = height
            ctx.reset()
            ctx.clearRect(0, 0, w, h)

            function chip(t, phase) {
                return Math.sin(t * 21 + phase) * 0.9
                    + Math.sin(t * 47 + phase * 2.2) * 0.55
                    + Math.sin(t * 8 + phase * 0.7) * 0.8
            }

            var steps = 14
            var corner = w * 0.08
            var seed = 9

            function bodyPath() {
                ctx.beginPath()
                ctx.moveTo(corner, chip(0, seed))
                var s, t
                for (s = 1; s <= steps; s++) {
                    t = s / steps
                    ctx.lineTo(corner + (w - 2 * corner) * t, chip(t, seed))
                }
                for (s = 1; s <= steps; s++) {
                    t = s / steps
                    ctx.lineTo(w + chip(t, seed + 3), corner + (h - 2 * corner) * t)
                }
                for (s = 1; s <= steps; s++) {
                    t = s / steps
                    ctx.lineTo(w - corner - (w - 2 * corner) * t, h + chip(t, seed + 6))
                }
                for (s = 1; s <= steps; s++) {
                    t = s / steps
                    ctx.lineTo(chip(t, seed + 9), h - corner - (h - 2 * corner) * t)
                }
                ctx.closePath()
            }

            var g = ctx.createRadialGradient(w * 0.3, h * 0.22, 0, w * 0.5, h * 0.55, w * 1.15)
            g.addColorStop(0, Qt.lighter(seal.ink, 1.12))
            g.addColorStop(0.45, seal.ink)
            g.addColorStop(1, Qt.darker(seal.ink, 1.35))

            bodyPath()
            ctx.shadowColor = Qt.rgba(seal.ink.r, seal.ink.g, seal.ink.b, 0.3)
            ctx.shadowBlur = 1.5
            ctx.shadowOffsetY = 1
            ctx.fillStyle = g
            ctx.fill()
            ctx.shadowColor = "transparent"

            ctx.save()
            var pad = w * 0.09
            ctx.translate(pad, pad)
            ctx.scale((w - 2 * pad) / w, (h - 2 * pad) / h)
            bodyPath()
            ctx.strokeStyle = Qt.rgba(seal.glyphColor.r, seal.glyphColor.g, seal.glyphColor.b, 0.38)
            ctx.lineWidth = Math.max(1, w * 0.03)
            ctx.stroke()
            ctx.restore()
        }
    }

    Text {
        anchors.centerIn: parent
        text: seal.verdict === "correct" ? "✓" : "✗"
        color: seal.glyphColor
        font.family: theme.fontPrint
        font.pixelSize: Math.round(seal.size * 0.44)
        font.weight: Font.Black
        z: 1
    }
}

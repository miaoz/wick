import QtQuick
import QtQuick.Shapes

// White-character square seal (白文方章). Ports WickCalendarKit/JournalReviewBadge:
// chipped silhouette, pooled ink, calligraphic brush ✓/✗. Ink follows the PnL convention.
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

    Item {
        anchors.centerIn: parent
        width: 32
        height: 32
        scale: (seal.size * 0.54) / 32.0
        z: 1

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeColor: "transparent"
                    strokeWidth: 0
                    fillColor: seal.glyphColor
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    PathSvg {
                        path: seal.verdict === "correct"
                            ? "M 7.5,14.5 C 8.2,13.5 9.6,13.0 10.8,14.2 L 12.8,18.2 C 15.5,13.5 19.2,8.6 24.5,5.0 C 25.8,4.1 26.8,4.8 26.6,5.8 C 26.2,7.0 25.0,8.8 23.4,11.0 C 19.0,16.5 15.2,23.0 13.6,26.2 C 12.8,27.5 11.4,27.5 10.4,25.6 C 8.8,22.4 7.4,18.6 5.6,16.2 C 5.0,15.4 6.2,14.2 7.5,14.5 Z"
                            : "M 7.2,8.4 C 7.8,7.0 9.2,6.5 10.6,7.6 L 16.0,13.6 L 21.4,7.6 C 22.8,6.5 24.2,7.0 24.8,8.4 C 25.4,9.8 24.6,11.2 23.2,12.6 L 18.2,16.0 L 23.6,21.4 C 25.0,22.8 25.4,24.2 24.6,25.4 C 23.8,26.4 22.2,26.2 20.8,24.8 L 16.0,18.4 L 11.2,24.8 C 9.8,26.2 8.2,26.4 7.4,25.4 C 6.6,24.2 7.0,22.8 8.4,21.4 L 13.8,16.0 L 8.6,12.6 C 7.2,11.2 6.6,9.8 7.2,8.4 Z"
                    }
            }
        }
    }
}

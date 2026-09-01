import QtQuick
import QtQuick.Shapes

// Port of WickCalendarKit/BurnStripView.swift for Linux.
// The signature component of the「秉烛」system: elapsed time is a warm stain
// left by candlelight, the frontier is a thin ember line with a small flame,
// and the future is clean ruled paper.
Item {
    id: strip
    property var theme: null
    property real elapsed: 0.0
    property int ticks: 24
    property bool showsFlame: false

    Theme { id: defaultTheme }
    readonly property var actualTheme: theme ? theme : defaultTheme

    readonly property real fraction: Math.max(0.0, Math.min(1.0, elapsed))
    readonly property real frontier: width * fraction
    readonly property bool isFrontierActive: fraction > 0.002

    function repaintAll() {
        if (stainCanvas.available)
            stainCanvas.requestPaint()
        if (haloCanvas.available)
            haloCanvas.requestPaint()
        if (flameCanvas.available)
            flameCanvas.requestPaint()
    }

    Component.onCompleted: repaintAll()

    Connections {
        target: strip.actualTheme
        function onStain1Changed() { strip.repaintAll() }
        function onStain2Changed() { strip.repaintAll() }
        function onEmberChanged() { strip.repaintAll() }
        function onEmberHiChanged() { strip.repaintAll() }
        function onGlowChanged() { strip.repaintAll() }
        function onRuleChanged() { strip.repaintAll() }
        function onPaperHiChanged() { strip.repaintAll() }
    }

    // 1. Base track (Unburnt ruled paper + Stain, clipped to radius 3)
    Rectangle {
        id: baseTrack
        anchors.fill: parent
        radius: 3
        color: strip.actualTheme.paperHi
        clip: true

        // Vertical tick divisions
        Repeater {
            model: Math.max(strip.ticks, 1)
            Rectangle {
                required property int index
                visible: index > 0
                x: (index / strip.ticks) * baseTrack.width
                width: 1
                height: baseTrack.height
                color: strip.actualTheme.rule
                opacity: 0.75
            }
        }

        // Candle stain with deterministic wobbled edge (StainShape)
        Canvas {
            id: stainCanvas
            anchors.fill: parent
            antialiasing: true
            visible: strip.isFrontierActive
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.clearRect(0, 0, width, height)
                var fx = width * strip.fraction
                if (fx <= 0.5)
                    return
                var seed = 7
                function wobble(t) {
                    return Math.sin(t * 9 + seed) * 1.05
                         + Math.sin(t * 23 + seed * 3.1) * 0.65
                         + Math.sin(t * 41 + seed * 1.7) * 0.35
                }
                ctx.beginPath()
                ctx.moveTo(0, 0)
                ctx.lineTo(fx + wobble(0), 0)
                var steps = 24
                for (var s = 1; s <= steps; s++) {
                    var t = s / steps
                    ctx.lineTo(fx + wobble(t), height * t)
                }
                ctx.lineTo(0, height)
                ctx.closePath()

                var grad = ctx.createLinearGradient(0, 0, fx, 0)
                grad.addColorStop(0.0, strip.actualTheme.stain1)
                grad.addColorStop(1.0, strip.actualTheme.stain2)
                ctx.fillStyle = grad
                ctx.fill()
            }
            Connections {
                target: strip
                function onFractionChanged() { stainCanvas.requestPaint() }
                function onWidthChanged() { stainCanvas.requestPaint() }
                function onHeightChanged() { stainCanvas.requestPaint() }
            }
        }
    }

    // 2. Outer enclosing rule frame (1px border wrapping both elapsed and remaining slots, Layer 3 in macOS)
    Rectangle {
        id: outerFrame
        anchors.fill: parent
        radius: 3
        color: "transparent"
        border.color: strip.actualTheme.rule
        border.width: 1
    }

    // 2. Warm halo hugging the frontier (unclipped)
    Canvas {
        id: haloCanvas
        property real haloSize: Math.max(strip.height * 2.8, 16)
        width: haloSize
        height: haloSize
        x: strip.frontier - width / 2
        y: (strip.height - height) / 2
        visible: strip.isFrontierActive
        antialiasing: true
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.clearRect(0, 0, width, height)
            var cx = width / 2
            var cy = height / 2
            var r = width / 2
            var g = ctx.createRadialGradient(cx, cy, 0, cx, cy, r)
            var ember = strip.actualTheme.ember
            g.addColorStop(0.0, Qt.rgba(ember.r, ember.g, ember.b, 0.4))
            g.addColorStop(1.0, "transparent")
            ctx.fillStyle = g
            ctx.beginPath()
            ctx.arc(cx, cy, r, 0, 2 * Math.PI)
            ctx.fill()
        }
        Connections {
            target: strip
            function onHeightChanged() { haloCanvas.requestPaint() }
        }
        onWidthChanged: haloCanvas.requestPaint()
        onHeightChanged: haloCanvas.requestPaint()
    }

    // 3. Ember line at the frontier (unclipped)
    Item {
        id: emberItem
        visible: strip.isFrontierActive
        width: 2.5
        height: strip.height + 2
        x: strip.frontier - width / 2
        y: -1

        // Outer soft glow
        Rectangle {
            anchors.centerIn: parent
            width: parent.width + 6
            height: parent.height + 4
            radius: 3
            color: "transparent"
            border.color: strip.actualTheme.glow
            border.width: 2
            opacity: 0.55
        }

        // Ember gradient line
        Rectangle {
            anchors.fill: parent
            radius: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.rgba(strip.actualTheme.ember.r, strip.actualTheme.ember.g, strip.actualTheme.ember.b, 0.25) }
                GradientStop { position: 0.5; color: strip.actualTheme.ember }
                GradientStop { position: 1.0; color: strip.actualTheme.emberHi }
            }
        }
    }

    // 4. Flame dot (hero tier or today)
    Item {
        id: flameContainer
        visible: strip.showsFlame && strip.isFrontierActive
        property real flameW: Math.max(8, Math.min(12, strip.height * 0.9))
        property real flameH: flameW * 1.15
        width: flameW
        height: flameH
        x: strip.frontier - width / 2
        y: (strip.height - height) / 2

        Canvas {
            id: flameCanvas
            anchors.fill: parent
            anchors.margins: -4
            antialiasing: true
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.clearRect(0, 0, width, height)

                var pad = 4
                var w = width - 2 * pad
                var h = height - 2 * pad
                ctx.save()
                ctx.translate(pad, pad)

                // Teardrop path matching macOS TeardropShape
                ctx.beginPath()
                ctx.moveTo(w * 0.5, 0)
                ctx.bezierCurveTo(w * -0.05, h * 0.42, w * 0.12, h * 0.8, w * 0.5, h)
                ctx.bezierCurveTo(w * 0.88, h * 0.8, w * 1.05, h * 0.42, w * 0.5, 0)
                ctx.closePath()

                // Radial gradient (#FFF0C7 -> emberHi -> ember)
                var grad = ctx.createRadialGradient(w * 0.5, h * 0.35, 0, w * 0.5, h * 0.5, Math.max(w, h) * 0.65)
                grad.addColorStop(0.0, "#FFF0C7")
                grad.addColorStop(0.45, strip.actualTheme.emberHi)
                grad.addColorStop(1.0, strip.actualTheme.ember)

                // Glow shadow
                ctx.shadowColor = strip.actualTheme.glow
                ctx.shadowBlur = 5
                ctx.shadowOffsetX = 0
                ctx.shadowOffsetY = 0

                ctx.fillStyle = grad
                ctx.fill()

                ctx.restore()
            }
            Connections {
                target: strip
                function onHeightChanged() { flameCanvas.requestPaint() }
            }
            onWidthChanged: flameCanvas.requestPaint()
            onHeightChanged: flameCanvas.requestPaint()
        }
    }
}

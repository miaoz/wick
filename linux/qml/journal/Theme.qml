import QtQuick

// Palettes from WickCalendarKit/WickTheme.swift DayArcEngine anchors.
// gain/loss follow AppSettings.pnlColorConvention (greenUp default: gain=dai, loss=cinnabar).
QtObject {
    id: theme

    readonly property var settings: typeof appSettings !== "undefined" ? appSettings : null
    readonly property string scheme: settings ? settings.resolvedScheme : "dark"
    readonly property string phase: settings ? settings.phase : "night"
    readonly property string convention: settings ? settings.pnlColorConvention : "greenUp"
    readonly property string fontOverride: settings ? settings.journalFontName : ""

    readonly property var pal: {
        // Force re-evaluation when scheme/phase/appearance/omarchy changes.
        var s = scheme
        var p = phase
        var app = settings ? settings.appearance : "system"
        if (app === "system" && settings && settings.omarchyAvailable && Object.keys(settings.omarchyColors).length > 0) {
            return theme._omarchyPalette(settings.omarchyColors)
        }
        return theme._palette(s, p)
    }

    readonly property color desk: pal.desk
    readonly property color paper: pal.paper
    readonly property color paperHi: pal.paperHi
    readonly property color paperEdge: pal.paperEdge
    readonly property color sidebar: pal.sidebar
    readonly property color ink1: pal.ink1
    readonly property color ink2: pal.ink2
    readonly property color ink3: pal.ink3
    readonly property color rule: pal.rule
    readonly property color ember: pal.ember
    readonly property color emberHi: pal.emberHi
    readonly property color glow: pal.glow
    readonly property color cinnabar: pal.cinnabar
    readonly property color cinnabarSoft: pal.cinnabarSoft
    readonly property color dai: pal.dai
    readonly property color daiSoft: pal.daiSoft
    readonly property color stain1: pal.stain1
    readonly property color stain2: pal.stain2
    readonly property color char1: pal.char1
    readonly property color sealInk: pal.sealInk
    readonly property color receipt: pal.receipt !== undefined ? pal.receipt : _hex(0xF5EEDC)
    readonly property color receiptInk: pal.receiptInk !== undefined ? pal.receiptInk : _hex(0x33291A)
    readonly property color receiptRule: pal.receiptRule !== undefined ? pal.receiptRule : _rgba(rule, 0.35)
    readonly property color tape: pal.tape !== undefined ? pal.tape : _rgba(0xEED499, 0.58)
    readonly property color tapeBorder: pal.tapeBorder !== undefined ? pal.tapeBorder : _rgba(0xD9B873, 0.45)
    readonly property color accentTextOnEmber: _contrastTextColor(ember)

    // Token names (A-share pigments). Default 绿涨红跌 swaps the *binding*.
    readonly property color pnlUp: cinnabar
    readonly property color pnlDown: dai

    readonly property color gain: convention === "redUp" ? cinnabar : dai
    readonly property color loss: convention === "redUp" ? dai : cinnabar
    readonly property color gainSoft: convention === "redUp" ? cinnabarSoft : daiSoft
    readonly property color lossSoft: convention === "redUp" ? daiSoft : cinnabarSoft

    readonly property string fontUi: fontOverride.length > 0 ? fontOverride : "Inter, Noto Sans SC"
    readonly property string fontPrint: fontOverride.length > 0 ? fontOverride : "Noto Serif SC"
    readonly property string fontMono: fontOverride.length > 0 ? fontOverride : "JetBrains Mono"

    function _hex(n) { return "#" + n.toString(16).padStart(6, "0") }

    function _contrastTextColor(cVal) {
        var c = Qt.color(cVal)
        var lum = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
        return lum > 0.58 ? "#120D07" : "#FFF3E0"
    }

    function _rgba(val, a) {
        if (typeof val === "number") {
            var r = (val >> 16) & 0xff
            var g = (val >> 8) & 0xff
            var b = val & 0xff
            return Qt.rgba(r / 255, g / 255, b / 255, a)
        }
        var c = Qt.color(val)
        return Qt.rgba(c.r, c.g, c.b, a)
    }

    function _omarchyPalette(oc) {
        var mode = oc.mode || "dark"
        var isDark = mode !== "light"

        var bg = oc.background || (isDark ? "#1a1b26" : "#FFFCF0")
        var darkBg = oc.dark_background || (isDark ? "#13141c" : "#f2efe4")
        var darkerBg = oc.darker_background || (isDark ? "#0e0e14" : "#e5e2d8")
        var lighterBg = oc.lighter_background || (isDark ? "#24283b" : "#E6E4D9")

        var fg = oc.foreground || (isDark ? "#a9b1d6" : "#100F0F")
        var darkFg = oc.dark_foreground || (isDark ? "#565f89" : "#878580")
        var lightFg = oc.light_foreground || (isDark ? "#b4bee6" : "#403E3C")
        var brightFg = oc.bright_foreground || (isDark ? "#c0caf5" : "#100F0F")

        var accent = oc.accent || (isDark ? "#F5A83C" : "#D96E14")
        var muted = oc.muted || (isDark ? "#414868" : "#B7B5AC")
        var red = oc.red || "#f7768e"
        var green = oc.green || "#9ece6a"
        var emberHiColor = oc.bright_yellow || oc.bright_cyan || oc.bright_blue || accent

        if (isDark) {
            return {
                desk: darkerBg,
                paper: bg,
                paperHi: lighterBg,
                paperEdge: _rgba(muted, 0.4),
                sidebar: darkBg,
                ink1: brightFg,
                ink2: lightFg,
                ink3: darkFg,
                rule: muted,
                ember: accent,
                emberHi: emberHiColor,
                glow: _rgba(accent, 0.42),
                cinnabar: red,
                cinnabarSoft: _rgba(red, 0.14),
                dai: green,
                daiSoft: _rgba(green, 0.14),
                stain1: darkBg,
                stain2: darkerBg,
                char1: "#0C0703",
                sealInk: "#F7E7D2",
                receipt: lighterBg,
                receiptInk: brightFg,
                receiptRule: _rgba(muted, 0.6),
                tape: _rgba(accent, 0.32),
                tapeBorder: _rgba(accent, 0.55)
            }
        } else {
            return {
                desk: darkerBg,
                paper: bg,
                paperHi: lighterBg,
                paperEdge: _rgba(muted, 0.4),
                sidebar: darkBg,
                ink1: fg,
                ink2: lightFg,
                ink3: darkFg,
                rule: muted,
                ember: accent,
                emberHi: emberHiColor,
                glow: _rgba(accent, 0.35),
                cinnabar: red,
                cinnabarSoft: _rgba(red, 0.14),
                dai: green,
                daiSoft: _rgba(green, 0.14),
                stain1: darkBg,
                stain2: darkerBg,
                char1: "#191008",
                sealInk: "#F7E7D2",
                receipt: lighterBg,
                receiptInk: fg,
                receiptRule: _rgba(muted, 0.5),
                tape: _rgba(accent, 0.25),
                tapeBorder: _rgba(accent, 0.45)
            }
        }
    }

    function _palette(scheme, phase) {
        var dark = scheme !== "light"
        var key = (dark ? "d" : "l") + "-" + phase
        switch (key) {
        case "l-dawn":
            return {
                desk: _hex(0xE7D5C3), paper: _hex(0xFBF0E4), paperHi: _hex(0xFFFAF1),
                paperEdge: _rgba(0x33231C, 0.16), sidebar: _hex(0xF0E3D6),
                ink1: _hex(0x33231C), ink2: _hex(0x715850), ink3: _hex(0x8D6F5F),
                rule: _rgba(0x33231C, 0.16), ember: _hex(0xD26438), emberHi: _hex(0xA8492C),
                glow: _rgba(0xE06A38, 0.30), cinnabar: _hex(0xC03A22),
                cinnabarSoft: _rgba(0xC03A22, 0.14), dai: _hex(0x3E5C50),
                daiSoft: _rgba(0x3E5C50, 0.14), stain1: _hex(0xF2DCC2), stain2: _hex(0xE6C49A),
                char1: _hex(0x191008), sealInk: _hex(0xF7E7D2)
            }
        case "l-day":
            return {
                desk: _hex(0xE3D7BE), paper: _hex(0xFBF4E6), paperHi: _hex(0xFFFCF2),
                paperEdge: _rgba(0x2B2014, 0.16), sidebar: _hex(0xEDE3CF),
                ink1: _hex(0x2B2014), ink2: _hex(0x6B5942), ink3: _hex(0x82705A),
                rule: _rgba(0x2B2014, 0.16), ember: _hex(0xD96E14), emberHi: _hex(0xA85A0E),
                glow: _rgba(0xE8791C, 0.32), cinnabar: _hex(0xC03A22),
                cinnabarSoft: _rgba(0xC03A22, 0.14), dai: _hex(0x3E5C50),
                daiSoft: _rgba(0x3E5C50, 0.14), stain1: _hex(0xF0DFB6), stain2: _hex(0xE2C282),
                char1: _hex(0x191008), sealInk: _hex(0xF7E7D2)
            }
        case "l-dusk":
            return {
                desk: _hex(0xE2CFA6), paper: _hex(0xFAEEDA), paperHi: _hex(0xFFF9EA),
                paperEdge: _rgba(0x2E2112, 0.16), sidebar: _hex(0xF0E0C0),
                ink1: _hex(0x2E2112), ink2: _hex(0x6B5136), ink3: _hex(0x816440),
                rule: _rgba(0x2E2112, 0.16), ember: _hex(0xCC6A10), emberHi: _hex(0x9F5208),
                glow: _rgba(0xE07412, 0.34), cinnabar: _hex(0xC03A22),
                cinnabarSoft: _rgba(0xC03A22, 0.14), dai: _hex(0x3E5C50),
                daiSoft: _rgba(0x3E5C50, 0.14), stain1: _hex(0xF2DCAC), stain2: _hex(0xE6C688),
                char1: _hex(0x191008), sealInk: _hex(0xF7E7D2)
            }
        case "l-night":
            return {
                desk: _hex(0xD6D0C2), paper: _hex(0xEDE8DB), paperHi: _hex(0xF5F1E6),
                paperEdge: _rgba(0x29241B, 0.16), sidebar: _hex(0xE1DCD0),
                ink1: _hex(0x29241B), ink2: _hex(0x5E5747), ink3: _hex(0x7D7465),
                rule: _rgba(0x29241B, 0.16), ember: _hex(0xC96F1C), emberHi: _hex(0x96550F),
                glow: _rgba(0xE8862B, 0.30), cinnabar: _hex(0xC03A22),
                cinnabarSoft: _rgba(0xC03A22, 0.14), dai: _hex(0x3E5C50),
                daiSoft: _rgba(0x3E5C50, 0.14), stain1: _hex(0xEBDCB8), stain2: _hex(0xDCC896),
                char1: _hex(0x191008), sealInk: _hex(0xF7E7D2)
            }
        case "d-dawn":
            return {
                desk: _hex(0x16100C), paper: _hex(0x2B2118), paperHi: _hex(0x35291C),
                paperEdge: _rgba(0xF0E3C6, 0.12), sidebar: _hex(0x211812),
                ink1: _hex(0xF0E3C6), ink2: _rgba(0xF0E3C6, 0.64), ink3: _rgba(0xF0E3C6, 0.42),
                rule: _rgba(0xF0E3C6, 0.14), ember: _hex(0xF0A368), emberHi: _hex(0xF5BE8A),
                glow: _rgba(0xF0A368, 0.42), cinnabar: _hex(0xE06A4C),
                cinnabarSoft: _rgba(0xE06A4C, 0.14), dai: _hex(0x8FAE9E),
                daiSoft: _rgba(0x8FAE9E, 0.14), stain1: _hex(0x4E3C24), stain2: _hex(0x6E562C),
                char1: _hex(0x0C0703), sealInk: _hex(0xF7E7D2)
            }
        case "d-day":
            return {
                desk: _hex(0x15100A), paper: _hex(0x2C2214), paperHi: _hex(0x362A18),
                paperEdge: _rgba(0xF0E3C6, 0.12), sidebar: _hex(0x221A0F),
                ink1: _hex(0xF0E3C6), ink2: _rgba(0xF0E3C6, 0.64), ink3: _rgba(0xF0E3C6, 0.42),
                rule: _rgba(0xF0E3C6, 0.14), ember: _hex(0xF5A83C), emberHi: _hex(0xFFC882),
                glow: _rgba(0xF59A3C, 0.42), cinnabar: _hex(0xE06A4C),
                cinnabarSoft: _rgba(0xE06A4C, 0.14), dai: _hex(0x8FAE9E),
                daiSoft: _rgba(0x8FAE9E, 0.14), stain1: _hex(0x4A3820), stain2: _hex(0x6B5226),
                char1: _hex(0x0C0703), sealInk: _hex(0xF7E7D2)
            }
        case "d-dusk":
            return {
                desk: _hex(0x181006), paper: _hex(0x2E2010), paperHi: _hex(0x382712),
                paperEdge: _rgba(0xF0E3C6, 0.12), sidebar: _hex(0x241A0E),
                ink1: _hex(0xF0E3C6), ink2: _rgba(0xF0E3C6, 0.64), ink3: _rgba(0xF0E3C6, 0.42),
                rule: _rgba(0xF0E3C6, 0.14), ember: _hex(0xF08A2B), emberHi: _hex(0xF7AB5E),
                glow: _rgba(0xF08A2B, 0.44), cinnabar: _hex(0xE06A4C),
                cinnabarSoft: _rgba(0xE06A4C, 0.14), dai: _hex(0x8FAE9E),
                daiSoft: _rgba(0x8FAE9E, 0.14), stain1: _hex(0x523F22), stain2: _hex(0x74592C),
                char1: _hex(0x0C0703), sealInk: _hex(0xF7E7D2)
            }
        default: // d-night 暗·子夜
            return {
                desk: _hex(0x120D07), paper: _hex(0x241C10), paperHi: _hex(0x2C2214),
                paperEdge: _rgba(0xF0E3C6, 0.12), sidebar: _hex(0x1C160C),
                ink1: _hex(0xF0E3C6), ink2: _rgba(0xF0E3C6, 0.64), ink3: _rgba(0xF0E3C6, 0.42),
                rule: _rgba(0xF0E3C6, 0.14), ember: _hex(0xF5A83C), emberHi: _hex(0xFFC882),
                glow: _rgba(0xF5A83C, 0.50), cinnabar: _hex(0xE06A4C),
                cinnabarSoft: _rgba(0xE06A4C, 0.14), dai: _hex(0x8FAE9E),
                daiSoft: _rgba(0x8FAE9E, 0.14), stain1: _hex(0x4A3820), stain2: _hex(0x6B5226),
                char1: _hex(0x0C0703), sealInk: _hex(0xF7E7D2)
            }
        }
    }
}

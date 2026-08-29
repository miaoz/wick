import QtQuick

// 暗 · 子夜 tokens from designs/wick-design-language/tokens-v2.css
QtObject {
    readonly property color desk: "#120D07"
    readonly property color paper: "#241C10"
    readonly property color paperHi: "#2C2214"
    readonly property color paperEdge: "#4A3A22"
    readonly property color sidebar: "#1C160C"
    readonly property color ink1: "#F0E3C6"
    readonly property color ink2: Qt.rgba(240 / 255, 227 / 255, 198 / 255, 0.64)
    readonly property color ink3: Qt.rgba(240 / 255, 227 / 255, 198 / 255, 0.42)
    readonly property color rule: Qt.rgba(240 / 255, 227 / 255, 198 / 255, 0.14)
    readonly property color ember: "#F5A83C"
    readonly property color emberHi: "#FFC882"
    readonly property color glow: Qt.rgba(245 / 255, 168 / 255, 60 / 255, 0.5)
    readonly property color cinnabar: "#E06A4C"
    readonly property color cinnabarSoft: Qt.rgba(224 / 255, 106 / 255, 76 / 255, 0.14)
    readonly property color dai: "#8FAE9E"
    readonly property color daiSoft: Qt.rgba(143 / 255, 174 / 255, 158 / 255, 0.14)
    readonly property color stain1: "#4A3820"
    readonly property color stain2: "#6B5226"
    readonly property color char1: "#0C0703"
    readonly property color sealInk: "#F7E7D2"

    // Token names (A-share pigments). Default 绿涨红跌 swaps the *binding*.
    readonly property color pnlUp: cinnabar
    readonly property color pnlDown: dai
    readonly property color gain: dai
    readonly property color loss: cinnabar
    readonly property color gainSoft: daiSoft
    readonly property color lossSoft: cinnabarSoft

    readonly property string fontUi: "Inter, Noto Sans SC"
    readonly property string fontPrint: "Noto Serif SC"
    readonly property string fontMono: "JetBrains Mono"
}

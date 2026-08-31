import QtQuick
import QtQuick.Shapes

Item {
    id: root
    property string name: ""
    property color color: "#33291A"
    property real size: 16

    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    readonly property real s: size / 16.0

    Item {
        id: container
        width: 16
        height: 16
        scale: root.s
        transformOrigin: Item.TopLeft

        // 1. TRASH
        Shape {
            visible: root.name === "trash"
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: root.color
                strokeWidth: 1.25
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg {
                    path: "M 6,3 L 6,1.6 C 6,1.4 6.2,1.2 6.5,1.2 L 9.5,1.2 C 9.8,1.2 10,1.4 10,1.6 L 10,3 M 2.4,3.2 L 13.6,3.2 M 3.8,3.5 L 4.4,13.2 C 4.5,14.3 5.3,14.8 6.2,14.8 L 9.8,14.8 C 10.7,14.8 11.5,14.3 11.6,13.2 L 12.2,3.5 M 6.8,6.2 L 6.8,12.0 M 9.2,6.2 L 9.2,12.0"
                }
            }
        }

        // 2. PHOTO.BADGE.PLUS
        Shape {
            visible: root.name === "photo.badge.plus"
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            // Main frame & landscape
            ShapePath {
                strokeColor: root.color
                strokeWidth: 1.2
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg {
                    path: "M 3,2.2 L 12,2.2 C 13,2.2 13.5,2.7 13.5,3.7 L 13.5,10.3 C 13.5,11.3 13,11.8 12,11.8 L 3,11.8 C 2,11.8 1.5,11.3 1.5,10.3 L 1.5,3.7 C 1.5,2.7 2,2.2 3,2.2 Z M 2.2,9.6 L 4.8,6.8 L 7.0,8.6 L 8.8,6.8 L 11.8,9.8"
                }
            }

            // Sun
            ShapePath {
                strokeColor: root.color
                strokeWidth: 1.0
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathSvg {
                    path: "M 5.8,5.0 A 1.0,1.0 0 1,1 3.8,5.0 A 1.0,1.0 0 1,1 5.8,5.0"
                }
            }

            // Plus badge knockout circle
            ShapePath {
                strokeColor: root.color
                strokeWidth: 1.1
                fillColor: "#FFFFFF"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg {
                    path: "M 15.6,12.0 A 3.6,3.6 0 1,1 8.4,12.0 A 3.6,3.6 0 1,1 15.6,12.0 Z M 10.0,12.0 L 14.0,12.0 M 12.0,10.0 L 12.0,14.0"
                }
            }
        }

        // 3. PHOTO (no badge)
        Shape {
            visible: root.name === "photo"
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: root.color
                strokeWidth: 1.2
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg {
                    path: "M 3,2.2 L 13,2.2 C 14,2.2 14.5,2.7 14.5,3.7 L 14.5,12.3 C 14.5,13.3 14,13.8 13,13.8 L 3,13.8 C 2,13.8 1.5,13.3 1.5,12.3 L 1.5,3.7 C 1.5,2.7 2,2.2 3,2.2 Z M 2.2,11.2 L 5.2,7.8 L 7.6,10.0 L 9.6,7.8 L 13.8,11.8"
                }
            }

            ShapePath {
                strokeColor: root.color
                strokeWidth: 1.0
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathSvg {
                    path: "M 6.0,5.2 A 1.1,1.1 0 1,1 3.8,5.2 A 1.1,1.1 0 1,1 6.0,5.2"
                }
            }
        }

        // 4. MINUS.CIRCLE
        Shape {
            visible: root.name === "minus.circle"
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: root.color
                strokeWidth: 1.25
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg {
                    path: "M 14.6,8.0 A 6.6,6.6 0 1,1 1.4,8.0 A 6.6,6.6 0 1,1 14.6,8.0 Z M 4.6,8.0 L 11.4,8.0"
                }
            }
        }

        // 5. PLUS.CIRCLE
        Shape {
            visible: root.name === "plus.circle"
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: root.color
                strokeWidth: 1.25
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg {
                    path: "M 14.6,8.0 A 6.6,6.6 0 1,1 1.4,8.0 A 6.6,6.6 0 1,1 14.6,8.0 Z M 4.6,8.0 L 11.4,8.0 M 8.0,4.6 L 8.0,11.4"
                }
            }
        }

        // 6. PLUS
        Shape {
            visible: root.name === "plus"
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: root.color
                strokeWidth: 1.3
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathSvg {
                    path: "M 3.2,8.0 L 12.8,8.0 M 8.0,3.2 L 8.0,12.8"
                }
            }
        }

        // 7. XMARK.CIRCLE.FILL
        Shape {
            visible: root.name === "xmark.circle.fill"
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: "transparent"
                strokeWidth: 0
                fillColor: root.color
                PathSvg {
                    path: "M 15.0,8.0 A 7.0,7.0 0 1,1 1.0,8.0 A 7.0,7.0 0 1,1 15.0,8.0 Z"
                }
            }

            ShapePath {
                strokeColor: "#FFFFFF"
                strokeWidth: 1.2
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathSvg {
                    path: "M 5.2,5.2 L 10.8,10.8 M 10.8,5.2 L 5.2,10.8"
                }
            }
        }

        // 8. CHECKMARK.SEAL
        Shape {
            visible: root.name === "checkmark.seal"
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: root.color
                strokeWidth: 1.15
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg {
                    path: "M 8,1.2 L 9.8,2.8 L 12.2,2.2 L 12.8,4.6 L 14.8,6.2 L 13.8,8.4 L 14.8,10.6 L 12.8,12.2 L 12.2,14.6 L 9.8,14.0 L 8,15.6 L 6.2,14.0 L 3.8,14.6 L 3.2,12.2 L 1.2,10.6 L 2.2,8.4 L 1.2,6.2 L 3.2,4.6 L 3.8,2.2 L 6.2,2.8 Z M 4.8,8.2 L 7.0,10.4 L 11.4,5.8"
                }
            }
        }

        // 9. CHEVRON.RIGHT
        Shape {
            visible: root.name === "chevron.right"
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: root.color
                strokeWidth: 1.4
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg {
                    path: "M 5.5,3.2 L 10.5,8.0 L 5.5,12.8"
                }
            }
        }

        // 10. CHEVRON.LEFT
        Shape {
            visible: root.name === "chevron.left"
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: root.color
                strokeWidth: 1.4
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg {
                    path: "M 10.5,3.2 L 5.5,8.0 L 10.5,12.8"
                }
            }
        }

        // 11. CHEVRON.DOWN
        Shape {
            visible: root.name === "chevron.down"
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: root.color
                strokeWidth: 1.4
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg {
                    path: "M 3.2,5.5 L 8.0,10.5 L 12.8,5.5"
                }
            }
        }

        // 12. CHEVRON.UP
        Shape {
            visible: root.name === "chevron.up"
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: root.color
                strokeWidth: 1.4
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg {
                    path: "M 3.2,10.5 L 8.0,5.5 L 12.8,10.5"
                }
            }
        }

        // 13. MAGNIFYINGGLASS
        Shape {
            visible: root.name === "magnifyingglass"
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: root.color
                strokeWidth: 1.3
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg {
                    path: "M 10.5,6.5 A 4.0,4.0 0 1,1 2.5,6.5 A 4.0,4.0 0 1,1 10.5,6.5 Z M 9.5,9.5 L 13.8,13.8"
                }
            }
        }

        // 14. CHECKMARK
        Shape {
            visible: root.name === "checkmark"
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: root.color
                strokeWidth: 1.4
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg {
                    path: "M 3.2,8.0 L 6.5,11.3 L 12.8,4.7"
                }
            }
        }

        // 15. SIDEBAR.LEFT
        Shape {
            visible: root.name === "sidebar.left"
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: root.color
                strokeWidth: 1.2
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg {
                    path: "M 3.8,2.6 L 12.2,2.6 C 13.2,2.6 14.0,3.4 14.0,4.4 L 14.0,11.6 C 14.0,12.6 13.2,13.4 12.2,13.4 L 3.8,13.4 C 2.8,13.4 2.0,12.6 2.0,11.6 L 2.0,4.4 C 2.0,3.4 2.8,2.6 3.8,2.6 Z M 5.8,2.6 L 5.8,13.4"
                }
            }
        }

        // 16. RECTANGLE.SPLIT.2X1
        Shape {
            visible: root.name === "rectangle.split.2x1"
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: root.color
                strokeWidth: 1.2
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg {
                    path: "M 3.8,2.6 L 12.2,2.6 C 13.2,2.6 14.0,3.4 14.0,4.4 L 14.0,11.6 C 14.0,12.6 13.2,13.4 12.2,13.4 L 3.8,13.4 C 2.8,13.4 2.0,12.6 2.0,11.6 L 2.0,4.4 C 2.0,3.4 2.8,2.6 3.8,2.6 Z M 8.0,2.6 L 8.0,13.4"
                }
            }
        }

        // 17. RECTANGLE
        Shape {
            visible: root.name === "rectangle"
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: root.color
                strokeWidth: 1.2
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg {
                    path: "M 3.8,2.6 L 12.2,2.6 C 13.2,2.6 14.0,3.4 14.0,4.4 L 14.0,11.6 C 14.0,12.6 13.2,13.4 12.2,13.4 L 3.8,13.4 C 2.8,13.4 2.0,12.6 2.0,11.6 L 2.0,4.4 C 2.0,3.4 2.8,2.6 3.8,2.6 Z"
                }
            }
        }

        // 18. SIDEBAR.RIGHT
        Shape {
            visible: root.name === "sidebar.right"
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: root.color
                strokeWidth: 1.2
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg {
                    path: "M 3.8,2.6 L 12.2,2.6 C 13.2,2.6 14.0,3.4 14.0,4.4 L 14.0,11.6 C 14.0,12.6 13.2,13.4 12.2,13.4 L 3.8,13.4 C 2.8,13.4 2.0,12.6 2.0,11.6 L 2.0,4.4 C 2.0,3.4 2.8,2.6 3.8,2.6 Z M 10.2,2.6 L 10.2,13.4"
                }
            }
        }

        // 19. SQUARE.AND.PENCIL
        Shape {
            visible: root.name === "square.and.pencil"
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: root.color
                strokeWidth: 1.2
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg {
                    path: "M 7.2,2.6 L 3.8,2.6 C 2.8,2.6 2.0,3.4 2.0,4.4 L 2.0,12.2 C 2.0,13.2 2.8,14.0 3.8,14.0 L 11.6,14.0 C 12.6,14.0 13.4,13.2 13.4,12.2 L 13.4,8.8 M 13.8,2.2 L 12.8,1.2 C 12.4,0.8 11.8,0.8 11.4,1.2 L 5.8,6.8 L 5.2,9.2 L 7.6,8.6 L 13.2,3.0 C 13.6,2.6 13.6,2.0 13.8,2.2 Z"
                }
            }
        }

        // 20. STAR.FILL
        Shape {
            visible: root.name === "star.fill" || root.name === "star"
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: "transparent"
                strokeWidth: 0
                fillColor: root.color
                PathSvg {
                    path: "M 8.0,1.2 L 10.2,5.8 L 15.2,6.5 L 11.5,9.8 L 12.5,14.8 L 8.0,12.2 L 3.5,14.8 L 4.5,9.8 L 0.8,6.5 L 5.8,5.8 Z"
                }
            }
        }

        // 21. SEAL.CHECKMARK
        Shape {
            visible: root.name === "seal.checkmark" || root.name === "checkmark.brush"
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: "transparent"
                strokeWidth: 0
                fillColor: root.color
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg {
                    path: "M 3.8,7.2 C 4.1,6.8 4.8,6.5 5.4,7.1 L 6.4,9.1 C 7.8,6.8 9.6,4.3 12.2,2.5 C 12.9,2.0 13.4,2.4 13.3,2.9 C 13.1,3.5 12.5,4.4 11.7,5.5 C 9.5,8.2 7.6,11.5 6.8,13.1 C 6.4,13.8 5.7,13.8 5.2,12.8 C 4.4,11.2 3.7,9.3 2.8,8.1 C 2.5,7.7 3.1,7.1 3.8,7.2 Z"
                }
            }
        }

        // 22. SEAL.XMARK
        Shape {
            visible: root.name === "seal.xmark" || root.name === "xmark.brush"
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: "transparent"
                strokeWidth: 0
                fillColor: root.color
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg {
                    path: "M 3.6,4.2 C 3.9,3.5 4.6,3.2 5.3,3.8 L 8.0,6.8 L 10.7,3.8 C 11.4,3.2 12.1,3.5 12.4,4.2 C 12.7,4.9 12.3,5.6 11.6,6.3 L 9.1,8.0 L 11.8,10.7 C 12.5,11.4 12.7,12.1 12.3,12.7 C 11.9,13.2 11.1,13.1 10.4,12.4 L 8.0,9.2 L 5.6,12.4 C 4.9,13.1 4.1,13.2 3.7,12.7 C 3.3,12.1 3.5,11.4 4.2,10.7 L 6.9,8.0 L 4.3,6.3 C 3.6,5.6 3.3,4.9 3.6,4.2 Z"
                }
            }
        }

        // 23. SPARKLES
        Shape {
            visible: root.name === "sparkles" || root.name === "sparkle"
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: "transparent"
                strokeWidth: 0
                fillColor: root.color
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg {
                    path: "M 8.0,1.5 C 8.0,5.0 9.0,6.0 12.5,8.0 C 9.0,10.0 8.0,11.0 8.0,14.5 C 8.0,11.0 7.0,10.0 3.5,8.0 C 7.0,6.0 8.0,5.0 8.0,1.5 Z M 13.0,1.5 C 13.0,3.0 13.5,3.5 15.0,4.5 C 13.5,5.5 13.0,6.0 13.0,7.5 C 13.0,6.0 12.5,5.5 11.0,4.5 C 12.5,3.5 13.0,3.0 13.0,1.5 Z"
                }
            }
        }
    }
}

import QtQuick
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * The frame the three charts sit in.
 *
 *   ┌──────────────────────────────────────────────┐
 *   │ SALES BY DAY                     [trailing]  │  <- 13px caps, in `ink`
 *   │ last 30 days                                 │  <- optional, 15px muted
 *   │                                              │
 *   │            (the chart, anchors.fill)          │
 *   └──────────────────────────────────────────────┘
 *
 * It exists for the same reason CardRow/KpiCard do: the surface recipe is one
 * decision, made once. Copied verbatim from KpiCard.qml:116-119 —
 *
 *     Fluent.cardBackground + Tokens.radius.lg + 1px Fluent.dividerBorder
 *
 * and NO shadow. FluentPySide ships no shadow of any kind (Tokens.qml:231-234),
 * so adding a layer.effect here would make the chart cards the only raised
 * surfaces in the product. Fluent's own charting agrees from the other side: it
 * puts no shadow, no border and no plot-area fill on data ink at all.
 *
 * The title is set exactly like KpiCard's label — overline caps, letterSpaced,
 * coloured in the module's ink — so a chart card and a KPI card stacked in the
 * same column read as the same object at two sizes. Fluent uses 10px semibold
 * caps for chart titles; overline (13) is that size at this app's 1.5x scale.
 */
Rectangle {
    id: card

    // =====================================================================
    // API
    // =====================================================================
    property string title: ""
    property string subtitle: ""

    /* Analytics is violet in Tokens.moduleHue, so that is the default. A card
       reporting one module's numbers should be passed that module's hue:
           ChartCard { ink: Tokens.hueFor("purchases") } */
    property color ink: Tokens.hue.violet

    /* The plot area the caller wants, excluding padding and the header. The
       card's implicit height is built from it rather than measured out of the
       content, because a chart anchored to fill its parent has no implicit
       height of its own and reading childrenRect here would close a loop. */
    property int contentHeight: 240

    /* Right-hand end of the header: a period chip, a total, a GlyphButton. In a
       RowLayout, so it is the LEADING end in Arabic without being asked. */
    property alias trailing: trailingRow.data

    default property alias content: body.data

    // =====================================================================
    // SURFACE
    // =====================================================================
    Layout.fillWidth: true

    implicitWidth: 360
    implicitHeight: 2 * Tokens.size.cardPadding
                    + header.implicitHeight
                    + Tokens.spacing.md
                    + card.contentHeight

    color: Fluent.cardBackground
    radius: Tokens.radius.lg
    border.width: 1
    border.color: Fluent.dividerBorder

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.size.cardPadding
        spacing: Tokens.spacing.md

        RowLayout {
            id: header
            Layout.fillWidth: true
            spacing: Tokens.spacing.sm
            visible: card.title !== "" || card.subtitle !== ""
                     || trailingRow.children.length > 0

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    visible: card.title !== ""
                    horizontalAlignment: Text.AlignLeft
                    text: card.title
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.overline
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 0.8
                    color: card.ink
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                Text {
                    Layout.fillWidth: true
                    visible: card.subtitle !== ""
                    horizontalAlignment: Text.AlignLeft
                    text: card.subtitle
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.caption
                    color: Fluent.textSecondary
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }

            Row {
                id: trailingRow
                Layout.alignment: Qt.AlignVCenter
                spacing: Tokens.spacing.sm
            }
        }

        Item {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: card.contentHeight
            clip: true
        }
    }
}

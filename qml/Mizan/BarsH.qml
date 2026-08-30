import QtQuick
import QtQuick.Layouts
import FluentControls
import Mizan
import "charts.js" as Charts

/*
 * أعمدة بيانية أفقية — horizontal bars, and only horizontal.
 *
 *   01  COCA-COLA 1.5L                            412,300
 *       ████████████████████████████████████
 *   02  LAIT CANDIA 1L                            287,100
 *       █████████████████████████
 *   03  PAIN                                      190,050
 *       ████████████████
 *
 * Ported from pos/app/widgets/charts.py::HBarChart / HorizontalRankingChart,
 * which was already hand-painted there rather than handed to QtCharts, and
 * follows the layout of Fluent's own HorizontalBarChart:
 *
 *   label ABOVE the bar, value right-aligned on the same line   chartTitle
 *   bar height 12px                                            _barHeight
 *   row gap 10px                                               items10pMargin
 *   label -> bar gap 5px                                       chartTitleLeft5p
 *   corner radius 3 (opt-in)                                   rx
 *   unselected rows drop to 0.1 opacity                        opacity
 *   no animation                                               (grep)
 *
 * WHY THIS ONE DRAWS NOTHING
 *
 * A horizontal bar is a rectangle inside a rectangle. Shapes and Canvas both
 * exist to draw what Rectangle cannot, and here there is nothing: two nested
 * Rectangles are native scene-graph geometry, so they get perfect antialiasing
 * and DPI handling for free, cost no triangulation and no texture upload, and
 * each one animates and hit-tests on its own. The donut and the curve earn a
 * Shape; this does not.
 *
 * It also means RTL costs nothing. The fill anchors to the track's LEADING edge
 * and LayoutMirroring swaps left for right, so the bars grow right-to-left in
 * Arabic the way a progress bar does, while the label/value row mirrors itself
 * because it is a RowLayout. No branch on Strings.rtl anywhere in this file.
 */
Item {
    id: root

    // =====================================================================
    // API
    // =====================================================================
    /* [{ label, value, valueText?, color?, tone? }] in the order to display —
       this component does not sort. A "top 5" list arrives already ranked from
       SQL, and re-sorting here would silently disagree with the table beside it. */
    property var rows: []

    /* 0 = scale to the largest row, which is what a ranking wants: the leader
       fills the track and everything else is read against it. For share-of-total
       bars, pass the total explicitly. */
    property real maxValue: 0

    property color ink: Tokens.hue.violet

    /* Per-row colours. Empty means every bar takes `ink` — Fluent's own
       HorizontalBarChart is single-colour, because the rows are one measure at
       different magnitudes and eight hues would imply eight meanings. */
    property var palette: []

    /* Ranking mode: the leader at full strength, the rest stepped back. pos did
       this by giving index 0 the accent and the others a muted pen. */
    property bool emphasiseFirst: false

    property int barHeight: 14
    property int barRadius: Tokens.radius.sm
    property int rowSpacing: Tokens.spacing.xs

    /* 01 / 02 / 03 down the leading edge, as pos's HorizontalRankingChart had. */
    property bool showRank: false

    /* Set it to override the tinted track. Transparent (the default) means
       "derive it from the bar's own colour" — see trackFor(). */
    property color trackColor: "transparent"

    property var formatValue: function (v) { return Charts.magnitude(v) }

    property string emptyText: ""

    property int activeIndex: -1

    signal rowClicked(int index)

    readonly property int count: (root.rows || []).length
    readonly property real scaleMax: root.maxValue > 0
                                     ? root.maxValue
                                     : Charts.extent(root.rows, "value").max

    /* The floor a row may be squeezed to: one line of label, the gap, the bar.
       Below this the label starts clipping, so the layout stops sharing height
       and overflows instead — a visibly cramped chart is easier to diagnose than
       a silently truncated one. */
    readonly property int minRowHeight: Math.round(Tokens.font.overline * 1.6)
                                        + Tokens.spacing.xs + root.barHeight

    /* And the ceiling.
     *
     * Rows share the card's height, which is right for four or five of them and
     * absurd for two: a supplier ranking with two suppliers in a 230px card would
     * put 115px of air around each bar and read as a rendering fault rather than as
     * two suppliers. Capped at roughly one and a half rows, the surplus goes to the
     * spacers above and below instead and a short ranking sits as a compact block
     * in the middle of its card.
     *
     * pos solved the same problem from the other end, by padding a ranking to a
     * minimum of three rows (charts.py:615, `max(len(items), 3)`) — which pretends
     * there are three. This leaves the count honest and moves the space. */
    readonly property int maxRowHeight: Math.round(root.minRowHeight * 1.55)

    implicitHeight: root.count > 0
                    ? root.count * root.minRowHeight + (root.count - 1) * root.rowSpacing
                    : 120
    implicitWidth: 360

    function colorFor(i, row) {
        if (row.color !== undefined && row.color !== "")
            return row.color
        if (row.tone !== undefined && row.tone !== "")
            return Tokens.toneInk(row.tone)
        var p = root.palette || []
        return p.length > 0 ? p[i % p.length] : root.ink
    }

    /*
     * The empty part of the bar.
     *
     * Fluent uses a neutral grey here. This derives a low-alpha wash of the
     * bar's own colour instead, because Tokens designs colour as ink/tint PAIRS
     * (Tokens.qml:45-49) and every other filled thing in this product — KpiCard's
     * chip, a badge, a tinted row — already puts that ink on its own tint. A
     * neutral track would make these the only bars in the app that don't.
     *
     * Alpha, not a lookup: Tokens.tint is keyed by hue NAME and a caller may
     * pass a raw colour, so there is nothing to look up. Higher in dark mode,
     * where a 13% wash over #202020 is not visible.
     */
    function trackFor(barColor) {
        if (root.trackColor.a > 0)
            return root.trackColor
        return Qt.rgba(barColor.r, barColor.g, barColor.b, Tokens.isDark ? 0.22 : 0.13)
    }

    function valueOf(row) {
        var v = Number(row.value)
        return isFinite(v) && v > 0 ? v : 0
    }

    // =====================================================================
    // ROWS
    // =====================================================================
    ColumnLayout {
        anchors.fill: parent
        spacing: root.rowSpacing
        visible: root.count > 0

        /* Takes whatever the rows refuse once they hit maxRowHeight, which centres
           a short ranking instead of stretching it. Zero-height when the rows can
           use the space, so a full card is unaffected. */
        Item { Layout.fillHeight: true }

        Repeater {
            model: root.rows

            delegate: Item {
                id: row

                required property var modelData
                required property int index

                readonly property int rowIndex: row.index
                readonly property real amount: root.valueOf(row.modelData)
                readonly property real share: root.scaleMax > 0 ? row.amount / root.scaleMax : 0
                readonly property color barColor: root.colorFor(row.index, row.modelData)

                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: root.minRowHeight
                Layout.maximumHeight: root.maxRowHeight

                /* Two stacked reasons to fade a row, resolved in one place:
                   the leader/follower step of a ranking, and the hover dim.
                   Fluent dims to 0.1; 0.35 here for the same reason the donut
                   stops at 0.28 — the card behind this is translucent. */
                opacity: {
                    if (root.activeIndex >= 0 && root.activeIndex !== row.index)
                        return 0.35
                    if (root.emphasiseFirst && row.index > 0)
                        return 0.72
                    return 1.0
                }

                Behavior on opacity {
                    NumberAnimation { duration: Fluent.anim.fast }
                }

                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Tokens.spacing.xs

                    RowLayout {
                        width: parent.width
                        spacing: Tokens.spacing.sm

                        /* Fixed width so the labels line up down the column even
                           when the count crosses from 9 to 10. Zero-padded and
                           LTR-marked: "01" inside an Arabic paragraph is a digit
                           run like any other. */
                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: 26
                            visible: root.showRank
                            horizontalAlignment: Text.AlignLeft
                            text: Charts.ltr((row.rowIndex + 1) < 10
                                             ? "0" + (row.rowIndex + 1)
                                             : String(row.rowIndex + 1))
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.overline
                            font.weight: Font.DemiBold
                            color: row.barColor
                        }

                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignLeft
                            text: row.modelData.label !== undefined
                                  ? String(row.modelData.label) : ""
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.caption
                            color: Fluent.textPrimary
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        /* The figure, at body weight — Fluent sets this line in
                           body1Strong while the label stays caption, so the
                           number wins the row. Pre-formatted by Python when the
                           caller supplied valueText; formatValue is the fallback
                           for a count or a quantity that is not money. */
                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            horizontalAlignment: Text.AlignRight
                            text: Charts.ltr(row.modelData.valueText !== undefined
                                             && row.modelData.valueText !== ""
                                             ? String(row.modelData.valueText)
                                             : root.formatValue(row.amount))
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.body
                            font.weight: Font.DemiBold
                            color: Fluent.textPrimary
                        }
                    }

                    Rectangle {
                        id: track
                        width: parent.width
                        height: root.barHeight
                        radius: Math.min(root.barRadius, height / 2)
                        color: root.trackFor(row.barColor)

                        Rectangle {
                            /* Leading edge, not the left one. Under
                               LayoutMirroring an anchor to `left` resolves to the
                               right edge, so the bar grows from wherever the
                               reader starts. */
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            /* A row with a real but tiny value must still draw
                               something — 4px, which at this radius is a dot.
                               Rounding it away would report a sale as no sale. */
                            width: row.amount > 0
                                   ? Math.max(4, Math.round(track.width * row.share))
                                   : 0
                            radius: Math.min(track.radius, width / 2)
                            color: row.barColor
                        }
                    }
                }

                HoverHandler {
                    onHoveredChanged: root.activeIndex = hovered ? row.rowIndex : -1
                }

                TapHandler {
                    onTapped: root.rowClicked(row.rowIndex)
                }
            }
        }

        Item { Layout.fillHeight: true }
    }

    Text {
        anchors.centerIn: parent
        visible: root.count === 0 && root.emptyText !== ""
        text: root.emptyText
        font.family: Tokens.font.family
        font.pixelSize: Tokens.font.caption
        color: Fluent.textSecondary
    }
}

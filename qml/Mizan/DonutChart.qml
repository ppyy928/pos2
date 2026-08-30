import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import FluentControls
import Mizan
import "charts.js" as Charts

/*
 * دائرة نسبية — the share-of-total ring.
 *
 *              ╭───────╮
 *           ╭──╯       ╰──╮        ■ Cash          62%
 *          │    1,204,500  │       ■ Card          28%
 *          │    TOTAL      │       ■ Credit        10%
 *           ╰──╮       ╭──╯
 *              ╰───────╯
 *
 * Ported in spirit from pos/app/widgets/charts.py::DonutChart (QPieSeries with
 * setHoleSize(0.58), total in the hole, legend off, hover tip). Nothing of
 * QtCharts survives — see the note at the bottom on why.
 *
 * HOW IT IS DRAWN
 *
 * One QtQuick.Shapes ShapePath per slice, each a single PathAngleArc STROKED at
 * the ring thickness on the ring's mid-radius — not a filled annular sector.
 * A stroke needs one arc where a filled sector needs two plus two straight
 * joins, and the geometry cannot come apart at the seam. The gap between slices
 * is bitten out of each sweep (gapDegrees) rather than painted over in the card
 * colour, which is what Fluent's SVG does; on a translucent Fluent.cardBackground
 * over Mica there is no opaque colour to paint with.
 *
 * preferredRendererType: Shape.CurveRenderer is not optional. Shapes' default
 * GeometryRenderer triangulates on the CPU and has NO antialiasing, so a 0.5px
 * error walks visibly around a 240px ring. CurveRenderer (Qt 6.6+, this app
 * runs 6.9.3) resolves curves on the GPU with native AA and does not retriangulate
 * when the card is resized. The alternative — layer.enabled + layer.samples: 4 —
 * costs an offscreen buffer per chart and blurs the centre text.
 *
 * DIRECTION
 *
 * Clockwise from 12 o'clock in both languages. A pie is not a layout: mirroring
 * it in Arabic would put the largest share where an operator does not expect it,
 * and every printed report the merchant has ever seen goes clockwise. Only the
 * legend mirrors, and it does so by itself because it is a RowLayout.
 */
Item {
    id: root

    // =====================================================================
    // API
    // =====================================================================
    /* [{ label, value, valueText?, color?, tone? }]
       `value` is the raw number — this component needs the arithmetic. `valueText`
       is that number already formatted by Python and is what gets DISPLAYED;
       omit it and the legend shows the share only. `color` wins over `tone`,
       and with neither the slice takes its position in `palette`. */
    property var slices: []

    /* Fluent's donut stories run innerRadius 55 on a 220 box — a 0.5 hole. 0.52
       here: the centre carries a 34px figure at this app's type scale, and 0.5
       of a 200px ring is 100px of room for it. */
    property real holeRatio: 0.52

    /* Fluent uses d3's padAngle(0.02 rad) = 1.15°. 1.4 because the ring is
       thicker here, and a gap has to stay visible at the inner edge where the
       arc is narrowest. Suppressed automatically for a single slice, which would
       otherwise show a notch in an unbroken circle. */
    property real gapDegrees: 1.4

    /* PathAngleArc measures 0 at 3 o'clock, positive clockwise. -90 is noon. */
    property real startAngle: -90

    /* The figure in the hole, pre-formatted. Left empty and the centre shows
       nothing — a donut of percentages does not need a total. */
    property string centerValue: ""
    property string centerLabel: ""

    property bool showLegend: true

    /* Legend beside the ring when there is width for both, under it when there
       is not. Fluent always puts it below and centred; beside wins here because
       a reports page is landscape and a POS legend carries a money column that
       wants to align vertically. */
    property bool legendBeside: root.width >= 460

    /* The channel palette, in Tokens' own declaration order. Tokens.qml:48-49
       states that this palette IS the chart series palette, so a slice and the
       nav item for the same module cannot disagree about its colour. */
    property var palette: [Tokens.hue.emerald, Tokens.hue.indigo, Tokens.hue.teal,
                           Tokens.hue.amber, Tokens.hue.crimson, Tokens.hue.violet,
                           Tokens.hue.rose, Tokens.hue.slate]

    /* Hover/selection state. Written by this component and by the legend; also
       writable from outside so a page can highlight a slice from elsewhere.
       -1 is "nothing active", which is not the same as "everything dimmed". */
    property int activeIndex: -1

    property string emptyText: ""

    signal sliceClicked(int index)

    implicitHeight: 240
    implicitWidth: 320

    // =====================================================================
    // ARITHMETIC
    // =====================================================================
    /*
     * One binding computes the whole plan, so the sum is walked once instead of
     * once per slice per repaint. Negative and zero values are dropped rather
     * than clamped: a share of a total is undefined for a negative part, and
     * Fluent's Pie.tsx filters `d.data !== 0` for the same reason — a zero slice
     * with a colour and a gap is a rendering artefact, not data.
     */
    readonly property var plan: {
        var list = root.slices || []
        var i
        var v
        var total = 0
        var visible = 0
        for (i = 0; i < list.length; i++) {
            v = Number(list[i].value)
            if (isFinite(v) && v > 0) {
                total += v
                visible++
            }
        }
        if (total <= 0)
            return { total: 0, arcs: [] }

        var gap = visible > 1 ? root.gapDegrees : 0
        var free = 360 - gap * visible
        var arcs = []
        var at = root.startAngle
        for (i = 0; i < list.length; i++) {
            v = Number(list[i].value)
            if (!isFinite(v) || v <= 0)
                continue
            var sweep = v * free / total
            arcs.push({
                index: i,
                label: list[i].label !== undefined ? String(list[i].label) : "",
                valueText: list[i].valueText !== undefined ? String(list[i].valueText) : "",
                value: v,
                share: v / total,
                start: at,
                sweep: sweep,
                color: root.colorFor(i, list[i])
            })
            at += sweep + gap
        }
        return { total: total, arcs: arcs }
    }

    readonly property real total: plan.total
    readonly property var arcs: plan.arcs

    function colorFor(i, slice) {
        if (slice.color !== undefined && slice.color !== "")
            return slice.color
        if (slice.tone !== undefined && slice.tone !== "")
            return Tokens.toneInk(slice.tone)
        var p = root.palette
        return p.length > 0 ? p[i % p.length] : Tokens.hue.slate
    }

    /* Which slice is under a point in ring coordinates. Trigonometry rather than
       Shape.containsMode, because containsMode tests the FILL and these arcs are
       stroked — every one of them contains nothing. Returns -1 outside the ring,
       inside the hole, and in the gaps between slices. */
    function sliceAt(px, py) {
        var dx = px - ringBox.width / 2
        var dy = py - ringBox.height / 2
        var r = Math.sqrt(dx * dx + dy * dy)
        if (r < ringBox.innerR || r > ringBox.outerR)
            return -1
        /* atan2's y grows downward here, exactly as PathAngleArc's sweep does,
           so both agree that positive is clockwise on screen. */
        var deg = Math.atan2(dy, dx) * 180 / Math.PI
        var list = root.arcs
        for (var i = 0; i < list.length; i++) {
            var t = deg - list[i].start
            while (t < 0) t += 360
            while (t >= 360) t -= 360
            if (t <= list[i].sweep)
                return list[i].index
        }
        return -1
    }

    function arcOf(sliceIndex) {
        for (var i = 0; i < root.arcs.length; i++)
            if (root.arcs[i].index === sliceIndex)
                return root.arcs[i]
        return null
    }

    // =====================================================================
    // LAYOUT
    // =====================================================================
    GridLayout {
        anchors.fill: parent
        columns: root.legendBeside ? 2 : 1
        rowSpacing: Tokens.spacing.md
        columnSpacing: Tokens.spacing.lg

        Item {
            id: ringBox

            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 120
            Layout.minimumHeight: 120

            readonly property real side: Math.min(width, height)
            readonly property real outerR: side / 2
            readonly property real innerR: outerR * root.holeRatio
            readonly property real midR: (outerR + innerR) / 2
            readonly property real thickness: outerR - innerR

            /* The unbroken ring behind the slices. Without it a donut whose data
               is one 4% slice reads as a stray comma floating in a card; with it
               the shape is always a ring and the data is the coloured part of
               it. It is also the entire empty state. */
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                visible: ringBox.thickness > 0

                ShapePath {
                    fillColor: "transparent"
                    strokeColor: Fluent.subtleSecondary
                    strokeWidth: ringBox.thickness
                    capStyle: ShapePath.FlatCap

                    PathAngleArc {
                        centerX: ringBox.width / 2
                        centerY: ringBox.height / 2
                        radiusX: ringBox.midR
                        radiusY: ringBox.midR
                        startAngle: 0
                        sweepAngle: 360
                    }
                }
            }

            /* One Shape per slice rather than one Shape holding every ShapePath.
               Qt's guidance is the other way round — but a Repeater delegate has
               to be an Item and a ShapePath is not one, so a data-driven set of
               paths inside a single Shape means driving Shape.data from an
               Instantiator by hand. Eight arcs is not a number where the
               difference is measurable, and one Shape per slice buys per-slice
               opacity for free. */
            Repeater {
                model: root.arcs

                delegate: Shape {
                    /* Declared rather than relying on the injected context
                       property: this delegate reads modelData from inside a
                       ShapePath and a PathAngleArc, and a required property is
                       resolved on the delegate object itself instead of walking
                       out of the nested scope. ReportsPage.qml:178 sets the same
                       precedent. */
                    required property var modelData

                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    /* Fluent drops everything unselected to opacity 0.1. That is
                       tuned for white behind the chart; on a translucent card
                       over Mica 0.1 of a mid-tone hue disappears entirely, so
                       the dim stops at 0.28 — still unmistakably not the active
                       slice, still visible as a share. */
                    opacity: root.activeIndex < 0
                             || root.activeIndex === modelData.index ? 1.0 : 0.28

                    Behavior on opacity {
                        NumberAnimation { duration: Fluent.anim.fast }
                    }

                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: modelData.color
                        strokeWidth: ringBox.thickness
                        capStyle: ShapePath.FlatCap

                        PathAngleArc {
                            centerX: ringBox.width / 2
                            centerY: ringBox.height / 2
                            radiusX: ringBox.midR
                            radiusY: ringBox.midR
                            startAngle: modelData.start
                            sweepAngle: modelData.sweep
                        }
                    }
                }
            }

            // -------------------------------------------------------------
            // THE HOLE
            // -------------------------------------------------------------
            /* Hovering a slice replaces the total with that slice's own figure.
               Fluent does not do this — its donut only dims and shows a popover.
               It is kept because the hole is the one place on the chart where a
               number is already legible from across a counter, and the question
               an operator asks a payment-mix donut is "how much was card", not
               "what fraction was card". The total returns on exit. */
            /* Not named `focus`: Item already has a property by that name and
               redeclaring it is a load error, not a shadow. */
            readonly property var focusArc: root.activeIndex >= 0 ? root.arcOf(root.activeIndex) : null

            Column {
                anchors.centerIn: parent
                width: ringBox.innerR * 1.74
                spacing: 2
                visible: ringBox.innerR > 24

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: text !== ""
                    text: {
                        if (ringBox.focusArc)
                            return ringBox.focusArc.valueText !== ""
                                 ? Charts.ltr(ringBox.focusArc.valueText)
                                 : Charts.percent(ringBox.focusArc.value, root.total)
                        if (root.total <= 0)
                            return root.emptyText
                        return root.centerValue !== "" ? Charts.ltr(root.centerValue) : ""
                    }
                    font.family: Tokens.font.family
                    /* Fluent sets the centre in title2 (28/600). font.amount (34)
                       is this app's equivalent — the same token KpiCard puts its
                       value in — but it is a CEILING, not a size. The hole is a
                       circle whose width shrinks with the card, and a POS total
                       is "1,204,000.00", not "62%": at 34px that is ~200px of
                       text inside a 110px hole.

                       HorizontalFit shrinks the figure to the hole instead of
                       eliding it, which is the only acceptable behaviour — an
                       elided total ("1,204...") is worse than no total at all,
                       because it looks like a number and isn't one. The floor is
                       caption; below that the figure has stopped being the point
                       of the chart and the legend is, so ElideRight takes over as
                       the last resort. */
                    font.pixelSize: Math.min(Tokens.font.amount,
                                             Math.max(Tokens.font.caption,
                                                      ringBox.innerR * 0.66))
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: Tokens.font.caption
                    font.weight: Font.DemiBold
                    color: root.total <= 0 ? Fluent.textSecondary : Fluent.textPrimary
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: text !== "" && ringBox.innerR > 40
                    text: ringBox.focusArc ? ringBox.focusArc.label : root.centerLabel
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.overline
                    font.weight: Font.DemiBold
                    font.capitalization: ringBox.focusArc ? Font.MixedCase : Font.AllUppercase
                    font.letterSpacing: ringBox.focusArc ? 0 : 0.8
                    color: Fluent.textSecondary
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }

            /* MouseArea, not HoverHandler: this needs the cursor POSITION on
               every move to run sliceAt(), and a MouseArea's positionChanged
               hands it over directly. The rest of the app uses HoverHandler
               because it only ever asks the boolean question. */
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton

                onPositionChanged: function (mouse) {
                    root.activeIndex = root.sliceAt(mouse.x, mouse.y)
                }
                onExited: root.activeIndex = -1
                onClicked: function (mouse) {
                    var i = root.sliceAt(mouse.x, mouse.y)
                    if (i >= 0)
                        root.sliceClicked(i)
                }
            }
        }

        // -----------------------------------------------------------------
        // LEGEND
        // -----------------------------------------------------------------
        ColumnLayout {
            id: legend

            visible: root.showLegend && root.arcs.length > 0
            Layout.fillWidth: !root.legendBeside
            Layout.fillHeight: root.legendBeside
            Layout.alignment: root.legendBeside ? Qt.AlignVCenter : Qt.AlignHCenter
            Layout.maximumWidth: root.legendBeside ? root.width * 0.52 : root.width
            spacing: Tokens.spacing.xs

            Item { Layout.fillHeight: root.legendBeside }

            Repeater {
                model: root.arcs

                delegate: RowLayout {
                    required property var modelData

                    Layout.fillWidth: true
                    spacing: Tokens.spacing.sm

                    /* Fluent's legend swatch is a 12x12 square with a 1px border
                       in the series colour — not a dot. 14 at this scale, and
                       radius 4 because 3 is the one and only corner radius
                       Fluent's charting uses and 3 x 1.5 rounds to 4.

                       implicitWidth/Height rather than width/height: inside a
                       RowLayout the layout owns the geometry, and assigning
                       width directly is undefined behaviour. */
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 14
                        implicitHeight: 14
                        radius: 4
                        color: modelData.color
                        opacity: root.activeIndex < 0
                                 || root.activeIndex === modelData.index ? 1.0 : 0.35

                        Behavior on opacity {
                            NumberAnimation { duration: Fluent.anim.fast }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignLeft
                        text: modelData.label
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.caption
                        color: Fluent.textPrimary
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    /* The money column, when the caller supplied one. Right in
                       Latin, left in Arabic — AlignRight mirrors, and the LTR
                       mark inside keeps the digits themselves in order. */
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        visible: modelData.valueText !== ""
                        horizontalAlignment: Text.AlignRight
                        text: Charts.ltr(modelData.valueText)
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.caption
                        font.weight: Font.DemiBold
                        color: Fluent.textPrimary
                    }

                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.minimumWidth: 56
                        horizontalAlignment: Text.AlignRight
                        text: Charts.percent(modelData.value, root.total)
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.caption
                        color: Fluent.textSecondary
                    }

                    /* The legend is the easier hover target of the two — a 14px
                       swatch and a word beat a 3-degree wedge — so it drives the
                       same activeIndex the ring does. */
                    HoverHandler {
                        onHoveredChanged: root.activeIndex = hovered ? modelData.index : -1
                    }

                    TapHandler {
                        onTapped: root.sliceClicked(modelData.index)
                    }
                }
            }

            Item { Layout.fillHeight: root.legendBeside }
        }
    }

    /*
     * WHY NOT QtCharts / QtGraphs
     *
     * pos's DonutChart is a QPieSeries in a QChartView and that was the right
     * call for a QtWidgets app. Here it is not:
     *
     *   LICENCE   Both QtCharts and QtGraphs are commercial-or-GPLv3. Every
     *             other Qt module this product uses is available under the LGPL.
     *   PACKAGING They live in PySide6-Addons, not PySide6-Essentials, which is
     *             what FluentPySide is built against.
     *   THEME     Neither picks up the FluentWinUI3 style. QtCharts has its own
     *             theme enum and QtGraphs has GraphsTheme; both would have to be
     *             fed Tokens by hand, and neither knows Segoe UI Variable, the
     *             1.5x geometry scale, or Fluent.cardBackground.
     *   LIFE      QtCharts is deprecated as of Qt 6.10 and QtGraphs 2D ships no
     *             legend and no title, so the legend above would exist either way.
     *
     * Three arcs and a Column are a smaller thing to own than that.
     */
}

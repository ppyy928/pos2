import QtQuick
import QtQuick.Controls as QC
import QtQuick.Shapes
import FluentControls
import Mizan
import "charts.js" as Charts

/*
 * منحنى بياني — the value-over-time curve.
 *
 *   1.2M ┤                            ╭──╮
 *        │              ╭────╮   ╭────╯   ╰─
 *   600K ┤     ╭───╮ ╭──╯    ╰───╯
 *        │  ╭──╯   ╰─╯
 *      0 ┤──╯
 *        └────┬─────┬─────┬─────┬─────┬─────
 *           01-04  06-04  11-04  16-04  21-04
 *
 * Ported from pos/app/widgets/charts.py::LineChart / AreaChart. The Fluent
 * numbers it follows, read out of @fluentui/react-charts:
 *
 *   line          4px, round cap, no dash                LineChart.tsx
 *   gridlines     HORIZONTAL ONLY, 1px, solid, faint     createNumericYAxis
 *   domain line   removed entirely ('& path': none)      useCartesianChartStyles
 *   ticks         4 on the value axis, 6 on the category  CartesianChart.types
 *   tick labels   10px semibold                          useCartesianChartStyles
 *   area fill     0.7 opacity of the series colour       AreaChart.tsx
 *   crosshair     dashed 5,5 on hover only               LineChart _verticalLine
 *   hovered point white fill, series-colour stroke        LineChart _getPointFill
 *   animation     none, anywhere in the library          (grep)
 *
 * strokeWidth is 3 rather than Fluent's 4: 4 is measured against a 12px web
 * axis label and this app's is 13px on a 1.5x geometry scale, so a proportional
 * 6 would turn a 30-day series into a ribbon. 3 is what pos's QPen used after
 * the same adjustment. The area fill is 0.18 rather than 0.7 for the same reason
 * Fluent can afford 0.7 and this cannot — Fluent fills against opaque white,
 * this fills against a translucent card over Mica, so the wallpaper is behind it.
 *
 * DIRECTION — the one place in this app that does NOT mirror
 *
 * `frame` sets LayoutMirroring.enabled: false. Time flows left to right in
 * Arabic too; pos recorded the same rule at charts.py:13. Mirroring the plot
 * would put last week on the right of this week and read as a decline. So the
 * value axis stays on the left and the category axis stays chronological in both
 * languages, and only the label TEXT lays itself out RTL. Every number drawn
 * carries a U+200E so its digits do not reverse inside an Arabic paragraph.
 */
Item {
    id: root

    // =====================================================================
    // API
    // =====================================================================
    /* [{ label, value, valueText? }] in chronological order. `label` is the
       category as it should be printed (a day, an hour, a week) — this component
       does no date arithmetic, because the query layer already decided the
       buckets and named them.

       This is the ONE-SERIES door, and it is still the common case. For two or
       three lines use `series` below; the two are mutually exclusive and `series`
       wins. */
    property var points: []

    /* Analytics violet by default, as Tokens.moduleHue has it. */
    property color ink: Tokens.hue.violet

    /*
     * SEVERAL LINES ON ONE AXIS
     *
     *   [{ label, color, points: [{label, value, valueText?}], muted? }]
     *
     * Two questions need this and neither can be answered with one line: "how does
     * this period compare with the one before it", and "revenue against cost
     * against what is left". Both are comparisons, and a comparison drawn as two
     * charts side by side is not one — the reader has to hold one axis in their
     * head while looking at the other.
     *
     * `muted` marks a line as the reference rather than the subject: the prior
     * period, drawn thinner and at lower opacity so the current one reads first.
     * It is not dashed, because a dash pattern is a stroker feature and this chart
     * renders with Shape.CurveRenderer for antialiasing — the two do not combine.
     *
     * The x axis comes from the FIRST series. Lines are index-aligned, not
     * date-aligned: point 3 of the prior period is drawn under point 3 of this one,
     * which is what "the same day last month" means on a comparison chart. A
     * shorter series simply stops early.
     */
    property var series: []

    property int strokeWidth: 3
    property bool showArea: true

    /* The legend. Off for one line — a legend with one entry is a caption in a box
       — and on by default the moment there are two, because then the colours are
       the only thing telling them apart. */
    property bool showLegend: root.lanes.length > 1

    /* Catmull-Rom through every point, resampled (see charts.js smooth()).
       Off gives the raw polyline, which is the honest choice for a series with
       few points — a smooth curve through 5 weekly totals invents four days of
       shape that was never measured. */
    property bool curved: true

    /* Start the value axis at zero unless the data goes negative. A revenue
       chart cropped to 900k..1.1M turns a 20% week into a cliff; Fluent's own
       charts do the same by defaulting the y domain to include 0. */
    property bool baselineZero: true

    property int valueTicks: 4
    property int categoryTicks: 6

    /* The axis-tick formatter. Default is the magnitude fallback in charts.js;
       pass app.fmt through it to get the product's real number rules:
           formatValue: function (v) { return app.fmt.compact(v) } */
    property var formatValue: function (v) { return Charts.magnitude(v) }

    property string emptyText: ""

    /* -1 when nothing is hovered. Writable, so a page can drive the readout
       from a table row selection instead of the mouse. */
    property int activeIndex: -1

    signal pointClicked(int index)

    implicitHeight: 240
    implicitWidth: 420

    // =====================================================================
    // LANES
    // =====================================================================
    /*
     * The series, normalised, so everything below has exactly one shape to read.
     *
     * `points` + `ink` become a single unnamed lane. That is what keeps every
     * existing caller — the dashboard's sales trend, the reports' single curves —
     * working unchanged after this component learned to draw more than one line.
     */
    readonly property var lanes: {
        var src = root.series || []
        if (src.length > 0) {
            var out = []
            for (var i = 0; i < src.length; i++) {
                out.push({
                    label: src[i].label !== undefined ? String(src[i].label) : "",
                    color: (src[i].color !== undefined && src[i].color !== "")
                           ? src[i].color : root.ink,
                    points: src[i].points || [],
                    muted: src[i].muted === true
                })
            }
            return out
        }
        return [{ label: "", color: root.ink, points: root.points || [], muted: false }]
    }

    // =====================================================================
    // SCALE
    // =====================================================================
    /* Named yAxis, not `scale`: Item.scale is the transform and redeclaring it
       is a load error.

       Spans EVERY lane. One axis per chart is the whole point of putting the lines
       on one chart; a second scale would let cost look bigger than revenue. */
    readonly property var yAxis: {
        var lo = 0
        var hi = 0
        var seen = false
        var lanes_ = root.lanes
        for (var L = 0; L < lanes_.length; L++) {
            var list = lanes_[L].points || []
            for (var i = 0; i < list.length; i++) {
                var v = Number(list[i].value)
                if (!isFinite(v))
                    continue
                if (!seen) { lo = v; hi = v; seen = true }
                else { if (v < lo) lo = v; if (v > hi) hi = v }
            }
        }
        if (!seen)
            return Charts.axis(0, 1, root.valueTicks)
        if (root.baselineZero) {
            if (lo > 0) lo = 0
            if (hi < 0) hi = 0
        }
        return Charts.axis(lo, hi, root.valueTicks)
    }

    /* The category axis belongs to the first lane — see the note on `series`. */
    readonly property var categories: root.lanes.length > 0
                                      ? (root.lanes[0].points || []) : []
    readonly property int count: root.categories.length
    readonly property var categoryIndexes: Charts.spread(root.count, root.categoryTicks)

    /* Left gutter — the widest value label plus a gap.

       Measured imperatively rather than bound, because measuring means writing
       metrics.text once per tick and reading advanceWidth back, and doing that
       inside a binding on a property the same binding depends on is a loop
       waiting to happen. Nothing here changes at a rate where a binding would
       earn its keep: the axis is recomputed when the data changes, and that is
       the only moment the gutter can move. */
    property int gutter: 48

    /* Room for the stroke's own half-width and the topmost marker. */
    readonly property int topPad: Math.ceil(root.strokeWidth / 2) + 8

    /* The legend sits in a band the plot gives up at the bottom, under the
       category labels — Fluent's placement, and the only one that does not put a
       row of words over the data. */
    readonly property int legendHeight: (root.showLegend && root.lanes.length > 0)
                                        ? Math.round(Tokens.font.caption * 1.8) : 0

    readonly property int bottomPad: Tokens.font.overline + 16 + root.legendHeight
    /* Fluent reserves 20 on the right so the last tick label is not clipped by
       the plot edge; half a label is enough here because the last label is
       right-aligned against it rather than centred. */
    readonly property int rightPad: 14

    function xAt(i) {
        if (root.count <= 1)
            return plot.width / 2
        return i * plot.width / (root.count - 1)
    }

    function yAt(v) {
        var span = root.yAxis.max - root.yAxis.min
        if (!(span > 0))
            return plot.height
        return plot.height - (v - root.yAxis.min) * plot.height / span
    }

    /* Nearest category to an x in plot coordinates. Nearest, not "the bucket it
       fell in": the readout should latch to the point the operator is pointing
       at even when the cursor is a few pixels past it. */
    function indexAt(px) {
        if (root.count === 0)
            return -1
        if (root.count === 1)
            return 0
        var t = px * (root.count - 1) / plot.width
        var i = Math.round(t)
        return i < 0 ? 0 : (i > root.count - 1 ? root.count - 1 : i)
    }

    function valueAt(i) {
        return root.laneValue(0, i)
    }

    function laneValue(lane, i) {
        var lanes_ = root.lanes
        if (lane < 0 || lane >= lanes_.length)
            return 0
        var list = lanes_[lane].points || []
        if (i < 0 || i >= list.length)
            return 0
        var v = Number(list[i].value)
        return isFinite(v) ? v : 0
    }

    function laneText(lane, i) {
        var lanes_ = root.lanes
        if (lane < 0 || lane >= lanes_.length)
            return ""
        var list = lanes_[lane].points || []
        if (i < 0 || i >= list.length)
            return ""
        if (list[i].valueText !== undefined && list[i].valueText !== "")
            return String(list[i].valueText)
        return root.formatValue(root.laneValue(lane, i))
    }

    function textAt(i) {
        return root.laneText(0, i)
    }

    /* Has this lane got a point at all at this index? A prior period with fewer
       days must not report a zero it never measured. */
    function laneHas(lane, i) {
        var lanes_ = root.lanes
        if (lane < 0 || lane >= lanes_.length)
            return false
        var list = lanes_[lane].points || []
        return i >= 0 && i < list.length
    }

    // =====================================================================
    // CURVE
    // =====================================================================
    /*
     * Functions rather than bound properties, because there is one curve per lane
     * now and a property cannot be indexed. Each lane's Shape delegate binds its
     * own `curve` to a call, which tracks the same dependencies a property would —
     * plot geometry, the shared axis, the smoothing flag.
     */
    function curveOf(points) {
        var out = []
        var n = points ? points.length : 0
        if (n === 0 || plot.width <= 0 || plot.height <= 0)
            return out
        var raw = []
        for (var i = 0; i < n; i++) {
            var v = Number(points[i].value)
            raw.push([root.xAt(i), root.yAt(isFinite(v) ? v : 0)])
        }
        var sampled = (root.curved && raw.length > 2) ? Charts.smooth(raw, 10) : raw
        for (i = 0; i < sampled.length; i++)
            out.push(Qt.point(sampled[i][0], sampled[i][1]))
        return out
    }

    /* The same curve, closed down to the baseline. The baseline is zero when
       zero is on the axis and the axis floor otherwise, so a series that never
       goes negative fills to the bottom rule and one that does fills to the
       zero line from both sides. */
    function areaOf(curve) {
        if (!curve || curve.length < 2)
            return []
        var zero = Math.min(Math.max(0, root.yAxis.min), root.yAxis.max)
        var base = root.yAt(zero)
        var out = curve.slice()
        out.push(Qt.point(curve[curve.length - 1].x, base))
        out.push(Qt.point(curve[0].x, base))
        out.push(Qt.point(curve[0].x, curve[0].y))
        return out
    }

    // =====================================================================
    // FRAME
    // =====================================================================
    Item {
        id: frame
        anchors.fill: parent

        /* See the header. The plot is the one subtree in the app that stays LTR. */
        LayoutMirroring.enabled: false
        LayoutMirroring.childrenInherit: true

        visible: root.count > 0

        // -----------------------------------------------------------------
        // GRIDLINES + VALUE LABELS
        // -----------------------------------------------------------------
        Repeater {
            model: root.yAxis.values

            delegate: Item {
                id: tick

                required property var modelData

                readonly property real value: tick.modelData
                readonly property real lineY: plot.y + root.yAt(tick.value)

                Rectangle {
                    x: plot.x
                    y: tick.lineY
                    width: plot.width
                    height: 1
                    /* Fluent draws these at 1px and 0.2 alpha of the foreground.
                       Fluent.divider is this design system's value for the same
                       decision (8% black / 8% white) and Tokens.qml:9-11 says
                       lines belong to Fluent, not to Mizan — so the token wins
                       over the imported number.

                       The zero rule is the exception: when the series crosses
                       zero, that line is not decoration, it is the boundary
                       between profit and loss. */
                    color: (tick.value === 0 && root.yAxis.min < 0)
                           ? Fluent.dividerStrong : Fluent.divider
                    opacity: (tick.value === 0 && root.yAxis.min < 0) ? 0.5 : 1.0
                }

                Text {
                    x: 0
                    y: tick.lineY - height / 2
                    width: root.gutter - Tokens.spacing.xs
                    horizontalAlignment: Text.AlignRight
                    text: Charts.ltr(root.formatValue(tick.value))
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.overline
                    font.weight: Font.DemiBold
                    color: Fluent.textSecondary
                }
            }
        }

        // -----------------------------------------------------------------
        // CATEGORY LABELS
        // -----------------------------------------------------------------
        Repeater {
            model: root.categoryIndexes

            delegate: Text {
                id: catLabel

                required property var modelData

                readonly property int pointIndex: catLabel.modelData
                readonly property real centre: plot.x + root.xAt(catLabel.pointIndex)

                /* Clamped into the frame so the first and last labels sit inside
                   the card instead of half under its border. */
                x: Math.max(plot.x - Tokens.spacing.xs,
                            Math.min(frame.width - width, catLabel.centre - width / 2))
                y: plot.y + plot.height + Tokens.spacing.xs
                text: {
                    var list = root.categories
                    var l = list[catLabel.pointIndex] !== undefined
                          ? list[catLabel.pointIndex].label : ""
                    return l === undefined ? "" : String(l)
                }
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.overline
                font.weight: Font.DemiBold
                color: Fluent.textSecondary
                opacity: root.activeIndex === catLabel.pointIndex ? 1.0 : 0.85
            }
        }

        // -----------------------------------------------------------------
        // THE PLOT
        // -----------------------------------------------------------------
        Item {
            id: plot
            x: root.gutter
            y: root.topPad
            width: Math.max(1, frame.width - root.gutter - root.rightPad)
            height: Math.max(1, frame.height - root.topPad - root.bottomPad)

            /*
             * ONE Shape PER LANE.
             *
             * Qt's guidance is one Shape holding many ShapePaths, and that is what
             * a single lane does — its area and its line share a node. But a
             * ShapePath is not an Item, so a Repeater cannot make one, and a
             * data-driven set of lanes has to be a Repeater of Shapes. Three lanes
             * is not a number where the difference is measurable, and it buys
             * per-lane opacity for the muted reference line for free. The donut
             * makes the same trade for the same reason.
             *
             * Reversed order: the LAST lane is drawn first, so lane 0 — the subject
             * — ends up on top of its own reference line.
             */
            Repeater {
                model: root.lanes.length

                delegate: Shape {
                    id: laneShape

                    required property int index

                    /* Draw order, not data order. */
                    readonly property int lane: root.lanes.length - 1 - laneShape.index
                    readonly property var spec: root.lanes[laneShape.lane]
                    readonly property var curve: root.curveOf(laneShape.spec.points)
                    readonly property var area: laneShape.spec.muted
                                                ? [] : root.areaOf(laneShape.curve)

                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    visible: laneShape.curve.length >= 2
                    /* The reference line steps back rather than being dashed — see
                       the note on `series`. */
                    opacity: laneShape.spec.muted ? 0.55 : 1.0

                    ShapePath {
                        strokeColor: "transparent"
                        strokeWidth: -1
                        fillColor: "transparent"
                        startX: laneShape.area.length > 0 ? laneShape.area[0].x : 0
                        startY: laneShape.area.length > 0 ? laneShape.area[0].y : 0

                        fillGradient: LinearGradient {
                            id: wash
                            x1: 0
                            y1: 0
                            x2: 0
                            y2: plot.height
                            /* Fluent fills an area at 0.7 against opaque white. On
                               a translucent card that reads as a solid block, so
                               the fill fades instead: enough at the curve to attach
                               the line to the axis, almost gone by the baseline so
                               the gridlines stay readable through it.

                               Three stops, not two: a straight linear ramp from
                               0.28 to 0 spends most of its length in the visible
                               half and the fill reads as a wedge. Dropping to 0.09
                               by a third of the way down puts the visible part of
                               the gradient where the curve is.

                               Only the FIRST lane fills. Two overlapping washes
                               make a third colour that means nothing.

                               Addressed through `wash`, never through `parent`: a
                               GradientStop is not an Item, so `parent` inside one
                               does not resolve to the gradient and every colour
                               came out undefined. */
                            readonly property bool on: root.showArea
                                                       && laneShape.lane === 0
                            readonly property color hue: laneShape.spec.color

                            GradientStop {
                                position: 0.0
                                color: Qt.rgba(wash.hue.r, wash.hue.g, wash.hue.b,
                                               wash.on ? 0.28 : 0)
                            }
                            GradientStop {
                                position: 0.35
                                color: Qt.rgba(wash.hue.r, wash.hue.g, wash.hue.b,
                                               wash.on ? 0.09 : 0)
                            }
                            GradientStop {
                                position: 1.0
                                color: Qt.rgba(wash.hue.r, wash.hue.g, wash.hue.b, 0)
                            }
                        }

                        PathPolyline { path: laneShape.area }
                    }

                    ShapePath {
                        strokeColor: laneShape.spec.color
                        strokeWidth: laneShape.spec.muted
                                     ? Math.max(1, root.strokeWidth - 1)
                                     : root.strokeWidth
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin
                        fillColor: "transparent"
                        startX: laneShape.curve.length > 0 ? laneShape.curve[0].x : 0
                        startY: laneShape.curve.length > 0 ? laneShape.curve[0].y : 0

                        PathPolyline { path: laneShape.curve }
                    }
                }
            }

            /* A one-point series has no curve to draw, and a lone dot is the
               truthful picture of it. */
            Repeater {
                model: root.count === 1 ? root.lanes.length : 0

                delegate: Rectangle {
                    id: soloDot

                    required property int index

                    width: root.strokeWidth * 4
                    height: width
                    radius: width / 2
                    visible: root.laneHas(soloDot.index, 0)
                    x: root.xAt(0) - width / 2
                    y: root.yAt(root.laneValue(soloDot.index, 0)) - height / 2
                    color: Fluent.cardBackgroundTertiary
                    border.width: root.strokeWidth
                    border.color: root.lanes[soloDot.index].color
                }
            }

            // -------------------------------------------------------------
            // HOVER
            // -------------------------------------------------------------
            /* Deliberately NOT CurveRenderer: dash patterns are a stroker
               feature and a vertical 1px line has nothing to antialias. */
            Shape {
                anchors.fill: parent
                visible: root.activeIndex >= 0 && root.count > 1

                ShapePath {
                    strokeColor: Fluent.dividerStrong
                    strokeWidth: 1
                    strokeStyle: ShapePath.DashLine
                    dashPattern: [4, 4]
                    fillColor: "transparent"
                    startX: root.activeIndex >= 0 ? root.xAt(root.activeIndex) : 0
                    startY: 0

                    PathLine {
                        x: root.activeIndex >= 0 ? root.xAt(root.activeIndex) : 0
                        y: plot.height
                    }
                }
            }

            /* Fluent's hovered point: white fill, series colour at the line's own
               stroke width. The fill is cardBackgroundTertiary rather than plain
               white because Fluent.cardBackground is translucent and the curve
               would show through the marker. One per lane, so a comparison chart
               marks both values at the crosshair rather than only the subject. */
            Repeater {
                model: root.lanes.length

                delegate: Rectangle {
                    id: dot

                    required property int index

                    readonly property bool live: root.activeIndex >= 0
                                                 && root.count > 1
                                                 && root.laneHas(dot.index, root.activeIndex)

                    width: root.strokeWidth * 4
                    height: width
                    radius: width / 2
                    visible: dot.live
                    x: (root.activeIndex >= 0 ? root.xAt(root.activeIndex) : 0) - width / 2
                    y: (dot.live ? root.yAt(root.laneValue(dot.index, root.activeIndex)) : 0)
                       - height / 2
                    color: Fluent.cardBackgroundTertiary
                    border.width: root.lanes[dot.index].muted
                                  ? Math.max(1, root.strokeWidth - 1) : root.strokeWidth
                    border.color: root.lanes[dot.index].color
                    opacity: root.lanes[dot.index].muted ? 0.75 : 1.0
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton

                onPositionChanged: function (mouse) {
                    root.activeIndex = root.indexAt(mouse.x)
                }
                onExited: root.activeIndex = -1
                onClicked: function (mouse) {
                    var i = root.indexAt(mouse.x)
                    if (i >= 0)
                        root.pointClicked(i)
                }
            }
        }
    }

    // =====================================================================
    // LEGEND
    // =====================================================================
    /*
     * Outside `frame` on purpose. The plot forces LayoutMirroring off because time
     * runs left to right in every language; a legend is a row of WORDS and must
     * mirror like any other. It sits in the band `bottomPad` reserved for it, so it
     * overlays nothing.
     */
    Flow {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.legendHeight
        visible: root.legendHeight > 0
        spacing: Tokens.spacing.md

        Repeater {
            model: root.lanes

            delegate: Row {
                id: swatchRow

                required property var modelData

                spacing: Tokens.spacing.xs
                visible: swatchRow.modelData.label !== ""

                /* A dash, not a dot: it is a line chart, and the swatch should say
                   which line. 3px tall matches the stroke it stands for. */
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    height: 3
                    radius: 1.5
                    color: swatchRow.modelData.color
                    opacity: swatchRow.modelData.muted ? 0.55 : 1.0
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: swatchRow.modelData.label
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.caption
                    color: swatchRow.modelData.muted ? Fluent.textTertiary
                                                     : Fluent.textSecondary
                }
            }
        }
    }

    // =====================================================================
    // EMPTY
    // =====================================================================
    Text {
        anchors.centerIn: parent
        visible: root.count === 0 && root.emptyText !== ""
        text: root.emptyText
        font.family: Tokens.font.family
        font.pixelSize: Tokens.font.caption
        color: Fluent.textSecondary
    }

    // =====================================================================
    // READOUT
    // =====================================================================
    /* Every lane's value at the crosshair, one line each. A comparison chart whose
       tooltip reported only the subject would leave the reader doing the
       subtraction they came here to avoid. */
    QC.ToolTip {
        parent: root
        visible: root.activeIndex >= 0
        text: {
            if (root.activeIndex < 0)
                return ""
            var list = root.categories
            var head = list[root.activeIndex] !== undefined
                     ? String(list[root.activeIndex].label) : ""
            var out = head
            var lanes_ = root.lanes
            for (var L = 0; L < lanes_.length; L++) {
                if (!root.laneHas(L, root.activeIndex))
                    continue
                var value = Charts.ltr(root.laneText(L, root.activeIndex))
                out += "\n" + (lanes_[L].label !== ""
                               ? lanes_[L].label + "   " + value : value)
            }
            return out
        }
        delay: 0
        /* Anchored to the crosshair rather than to a marker item: there is one
           marker per lane now, and the readout belongs to the column. */
        x: {
            var cx = plot.x + (root.activeIndex >= 0 ? root.xAt(root.activeIndex) : 0)
            return Math.max(0, Math.min(root.width - width,
                                        cx + root.strokeWidth * 3))
        }
        y: Math.max(0, plot.y
                       + (root.activeIndex >= 0
                          ? root.yAt(root.laneValue(0, root.activeIndex)) : 0)
                       - height - Tokens.spacing.xs)
    }

    // =====================================================================
    // MEASUREMENT
    // =====================================================================
    TextMetrics {
        id: tickMetrics
        font.family: Tokens.font.family
        font.pixelSize: Tokens.font.overline
        font.weight: Font.DemiBold
    }

    function remeasureGutter() {
        var values = root.yAxis.values
        var widest = 0
        for (var i = 0; i < values.length; i++) {
            tickMetrics.text = Charts.ltr(root.formatValue(values[i]))
            if (tickMetrics.advanceWidth > widest)
                widest = tickMetrics.advanceWidth
        }
        /* A floor, so an axis of single digits does not leave the curve hard
           against the card's padding. */
        root.gutter = Math.max(32, Math.ceil(widest) + Tokens.spacing.sm)
    }

    onYAxisChanged: root.remeasureGutter()
    onFormatValueChanged: root.remeasureGutter()
    Component.onCompleted: root.remeasureGutter()
}

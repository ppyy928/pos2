.pragma library

/*
 * Chart arithmetic — axis ticks, label thinning, curve sampling.
 *
 * Same reasoning as columns.js: numbers in, numbers out, no QML context. A
 * `.pragma library` cannot read Tokens or Fluent, so nothing here knows a
 * colour or a pixel size; the three chart components do the mapping.
 *
 * WHY THERE IS NO MONEY FORMATTER HERE
 *
 * pos formats every currency figure in Python (fmt.money / fmt.compact) and
 * legacy.py:129-138 states the rule: a second implementation in JavaScript
 * would be a second set of rules for the same money. That still holds for the
 * value a chart *reports* — the caller passes `valueText` already formatted.
 *
 * An axis TICK is different: it is not a figure from the database, it is a
 * magnitude this file invented while choosing the scale, so nothing upstream
 * could have formatted it. `magnitude()` below abbreviates that magnitude and
 * deliberately emits no currency, no separator convention and no locale — it is
 * the fallback. Every chart exposes `formatValue` so a page that wants the real
 * thing can route ticks through app.fmt instead:
 *
 *     LineChart { formatValue: function (v) { return app.fmt.compact(v) } }
 */

/* =====================================================================
 * AXIS
 * ===================================================================== */

/* The classic "nice number" rounding: snap a raw range or step to 1, 2, 5 or
   10 times a power of ten, so ticks land on numbers an operator recognises
   (0 / 25k / 50k) instead of wherever the data happened to stop (0 / 23,140 /
   46,280). `round` picks the nearest such number rather than the next one up,
   which is what a step wants; a range wants the ceiling. */
function niceNum(range, round) {
    if (!(range > 0))
        return 1
    var exp = Math.floor(Math.log(range) / Math.LN10)
    var pow = Math.pow(10, exp)
    var f = range / pow
    var nf
    if (round)
        nf = f < 1.5 ? 1 : (f < 3 ? 2 : (f < 7 ? 5 : 10))
    else
        nf = f <= 1 ? 1 : (f <= 2 ? 2 : (f <= 5 ? 5 : 10))
    return nf * pow
}

/*
 * Returns { min, max, step, values } for a value axis.
 *
 * `wanted` is a hint, not a promise — nice steps do not divide an arbitrary
 * range into exactly N parts, so the caller gets between wanted-1 and wanted+1
 * ticks. Fluent's own charts ask for 4 on the value axis.
 *
 * Ticks are generated as min + i*step rather than by accumulating step, because
 * accumulating 0.1 twenty times does not give 2 in binary floating point and
 * the axis would end on 1.9999999999999998.
 */
function axis(lo, hi, wanted) {
    var min = Number(lo)
    var max = Number(hi)
    if (!isFinite(min) || !isFinite(max))
        return { min: 0, max: 1, step: 1, values: [0, 1] }
    if (max < min) { var t = min; min = max; max = t }

    /* A flat series — every day the same figure, or a single point. There is no
       range to divide, so invent one around the value instead of dividing by
       zero. A flat zero series gets 0..1 so the baseline still has a scale. */
    if (max === min) {
        if (max === 0) { min = 0; max = 1 }
        else if (max > 0) { min = 0; max = max * 1.25 }
        else { max = 0; min = min * 1.25 }
    }

    var ticks = Math.max(2, Math.round(wanted) || 4)

    /* The step comes from the RAW range, not from a nicened one.
       Heckbert's "loose labeling" rounds the range up first, and doing that here
       cost a fifth of the plot: a series topping out at 241,300 has a raw range
       of 241,300, but nicening that to 500,000 before dividing by 3 produces a
       step of 200,000 and an axis of 0..400,000 — the curve then lives in the
       bottom 60% of the card and the top two fifths are white space. Dividing
       the raw range gives a step of 100,000 and an axis of 0..300,000. */
    var step = niceNum((max - min) / (ticks - 1), true)
    var start = Math.floor(min / step) * step
    var end = Math.ceil(max / step) * step

    var values = []
    var n = Math.round((end - start) / step)
    for (var i = 0; i <= n; i++)
        values.push(start + i * step)

    return { min: start, max: end, step: step, values: values }
}

/*
 * Which of `n` categories get an x-axis label when only `wanted` fit.
 *
 * Always includes the first and the last: a time axis whose ends are unlabelled
 * does not say what period it covers. Duplicates are dropped, so a 3-point
 * series asked for 6 labels gets 3 rather than 6 pointing at the same tick.
 */
function spread(n, wanted) {
    var out = []
    var i
    if (n <= 0)
        return out
    if (n <= wanted || wanted < 2) {
        for (i = 0; i < n; i++)
            out.push(i)
        return out
    }
    var last = n - 1
    var steps = Math.round(wanted) - 1
    for (i = 0; i <= steps; i++) {
        var idx = Math.round(i * last / steps)
        if (out.length === 0 || out[out.length - 1] !== idx)
            out.push(idx)
    }
    return out
}

/* =====================================================================
 * CURVE
 * ===================================================================== */

/*
 * Catmull-Rom through every point, resampled as a dense polyline.
 *
 * `pts` and the return value are both arrays of [x, y] in PIXELS — the caller
 * has already mapped data to the plot rectangle.
 *
 * WHY A POLYLINE AND NOT PathCubic
 *
 * A smooth ShapePath needs one PathCubic element per segment, and QML cannot
 * instantiate path elements from a model: Repeater's delegate has to be an
 * Item, and a PathCubic is not one. The alternatives are Instantiator pushing
 * into Shape.data by hand, or PathSvg with a hand-built `d` string. Sampling
 * the curve here and handing a single PathPolyline the result needs neither:
 * one element, fully data-driven, and the series length is bounded — pos's
 * _bucket_series already collapses any range to 45 points, so 45 x 12 = 540
 * polyline points at worst.
 *
 * WHY THE OVERSHOOT IS CLAMPED
 *
 * Catmull-Rom is interpolating but not monotone: three points at 100, 0, 100
 * make the curve dip BELOW zero between them. On a sales chart that draws
 * negative revenue that never happened, and under the axis line. Clamping each
 * sample into its own segment's [min, max] costs a slightly flatter shoulder at
 * a local extreme and buys a curve that cannot lie.
 */
function smooth(pts, sub) {
    var n = pts ? pts.length : 0
    var steps = Math.max(1, Math.round(sub) || 1)
    if (n < 3 || steps < 2)
        return pts ? pts.slice() : []

    var out = [[pts[0][0], pts[0][1]]]
    for (var i = 0; i < n - 1; i++) {
        var p0 = pts[i > 0 ? i - 1 : 0]
        var p1 = pts[i]
        var p2 = pts[i + 1]
        var p3 = pts[i + 2 < n ? i + 2 : n - 1]

        var loY = Math.min(p1[1], p2[1])
        var hiY = Math.max(p1[1], p2[1])

        for (var s = 1; s <= steps; s++) {
            var t = s / steps
            var t2 = t * t
            var t3 = t2 * t
            var x = 0.5 * (2 * p1[0]
                           + (-p0[0] + p2[0]) * t
                           + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2
                           + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3)
            var y = 0.5 * (2 * p1[1]
                           + (-p0[1] + p2[1]) * t
                           + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2
                           + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
            out.push([x, y < loY ? loY : (y > hiY ? hiY : y)])
        }
    }
    return out
}

/* =====================================================================
 * TEXT
 * ===================================================================== */

/* U+200E LEFT-TO-RIGHT MARK.

   Applied to every number a chart draws, unconditionally. Inside an Arabic
   paragraph the bidi algorithm resolves a digit run against the paragraph
   direction and reverses the pieces, so "1,204.50" renders as "50.204,1" and a
   date axis label as "01-2026". The mark pins the run to LTR. It is invisible
   and harmless in a Latin paragraph, which is why it is not conditional — the
   same rule DataTable, TotalsDock and KeypadDisplay already follow. */
function ltr(s) {
    return "\u200e" + s
}

/* Axis-tick fallback. Magnitude only — see the header note. */
function magnitude(v) {
    var n = Number(v)
    if (!isFinite(n))
        return ""
    var a = Math.abs(n)
    if (a >= 1e9) return trim(n / 1e9) + "B"
    if (a >= 1e6) return trim(n / 1e6) + "M"
    if (a >= 1e4) return trim(n / 1e3) + "K"
    return trim(n)
}

/* One decimal, dropped when it is a zero: 1.5K, but 2K rather than 2.0K. */
function trim(x) {
    var r = Math.round(x * 10) / 10
    return Math.abs(r - Math.round(r)) < 0.05 ? String(Math.round(r)) : r.toFixed(1)
}

/* Share of a total, as a percentage string. Not currency — see the header. */
function percent(value, total) {
    if (!(total > 0))
        return ltr("0%")
    var p = value * 100 / total
    /* A slice that exists must not read as 0%: below a tenth of a percent it is
       reported as "<0.1%" rather than rounded away, because a legend row with a
       colour and a name next to "0%" looks like a bug. */
    if (p > 0 && p < 0.1)
        return ltr("<0.1%")
    return ltr(trim(p) + "%")
}

/* Largest value in a [{value}] list, and the sum. One pass, used by every
   component to scale itself; `Math.max.apply` on a long list can blow the
   argument limit, so it is a loop. */
function extent(rows, key) {
    var k = key || "value"
    var max = 0
    var sum = 0
    var list = rows || []
    for (var i = 0; i < list.length; i++) {
        var v = Number(list[i][k])
        if (!isFinite(v))
            continue
        sum += v
        if (v > max)
            max = v
    }
    return { max: max, sum: sum }
}

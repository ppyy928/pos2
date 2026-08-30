.pragma library

/*
 * Column width distribution for DataTable.
 *
 * Ported from pos/app/widgets/table.py::distribute_widths. Pure arithmetic —
 * columns in, pixel widths out — so it lives in a `.pragma library` with no QML
 * context of its own and can be reasoned about (and tested) on its own.
 *
 * The rule, unchanged from pos: every column keeps at least its declared width.
 * Surplus goes to the stretch columns first, each capped at ~45% of the
 * viewport so one wide free-text column cannot eat the table. What is left
 * grows the fixed columns proportionally, up to 1.75x their declared width, so
 * they gain room without drifting away from the sizes the page chose. Anything
 * still unspent goes back to the stretch columns — or, when there are none,
 * spreads across everything — so the last column always meets the right edge
 * and there is never a dead strip.
 *
 * `null` means the declared widths already overflow: the caller keeps its own
 * behaviour (elide, or scroll) rather than being handed widths that don't fit.
 *
 * The two constants are pos's 160 and 120 at the 1.5x geometry scale this app
 * runs at. They are floors for columns that declare nothing, and 120px of 12px
 * text is not the same amount of text as 120px of 17px text — leaving them
 * unscaled would silently elide every default column.
 */

var STRETCH_BASE = 240   // pos: 160
var DEFAULT_WIDTH = 180  // pos: 120

var STRETCH_MAX_SHARE = 0.45
var FIXED_MAX_FACTOR = 1.75

/* One action slot, and the padding around the whole strip. pos: 48 and 24, and
   the slot needs no scaling — 48 is Tokens.size.control, the touch minimum this
   app is built to, and RowActions puts one 48px IconButton in each slot. The
   padding is 2 * Tokens.spacing.md so it matches DataTable's own cellPadding.
   Spelled as numbers because a .pragma library has no QML context and cannot
   read Tokens. */
var ACTION_SLOT = 48
var ACTION_PADDING = 32

/* Fixed width for a column of `actions` — pos's column_width(). */
function actionsWidth(actions) {
    return (actions ? actions.length : 0) * ACTION_SLOT + ACTION_PADDING
}

function nominalWidth(column) {
    if (column.stretch)
        return Math.max(column.width || 0, STRETCH_BASE)
    /* An action column measures itself. pos makes every page pass
       `width=column_width(actions)` by hand, which is a number that has to be
       kept in step with the action list right next to it; deriving it here means
       adding a fifth action cannot silently crop the fourth. An explicit width
       still wins, for a page that wants a wider strip. */
    if (column.actions !== undefined)
        return column.width || actionsWidth(column.actions)
    return column.width || DEFAULT_WIDTH
}

/* Returns an array of widths summing to `available`, or null if the declared
   widths already exceed it. */
function distribute(columns, available) {
    var i
    var nominal = []
    var total = 0
    for (i = 0; i < columns.length; i++) {
        nominal.push(nominalWidth(columns[i]))
        total += nominal[i]
    }

    var surplus = available - total
    if (surplus <= 0)
        return null

    var widths = nominal.slice()
    var stretch = []
    var fixed = []
    for (i = 0; i < columns.length; i++)
        (columns[i].stretch ? stretch : fixed).push(i)

    /* Hand `surplus` to `indices`, in proportion to their nominal widths, with
       nobody crossing its cap. Repeats because capping one column frees its
       share for the others. `caps` is indexed by column, not by position in
       `indices`. */
    function grow(indices, caps) {
        while (surplus > 0) {
            var open = []
            var weight = 0
            for (var k = 0; k < indices.length; k++) {
                var idx = indices[k]
                if (widths[idx] < caps[idx]) {
                    open.push(idx)
                    weight += nominal[idx]
                }
            }
            if (open.length === 0 || weight === 0)
                return

            var given = 0
            for (var j = 0; j < open.length; j++) {
                var o = open[j]
                var share = Math.min(Math.floor(surplus * nominal[o] / weight),
                                     caps[o] - widths[o])
                widths[o] += share
                given += share
            }
            surplus -= given

            /* Every share floored to zero — a few pixels left over and more
               open columns than pixels. Without this the loop would spin
               forever handing out nothing. */
            if (given === 0) {
                for (var m = 0; m < open.length && surplus > 0; m++) {
                    var add = Math.min(surplus, caps[open[m]] - widths[open[m]])
                    widths[open[m]] += add
                    surplus -= add
                }
                return
            }
        }
    }

    function filled(value) {
        var out = []
        for (var n = 0; n < columns.length; n++)
            out.push(value)
        return out
    }

    if (stretch.length)
        grow(stretch, filled(Math.floor(available * STRETCH_MAX_SHARE)))

    if (surplus > 0 && fixed.length) {
        var factored = []
        for (i = 0; i < columns.length; i++)
            factored.push(Math.floor(nominal[i] * FIXED_MAX_FACTOR))
        grow(fixed, factored)
    }

    if (surplus > 0)
        grow(stretch.length ? stretch : fixed, filled(available))

    return widths
}

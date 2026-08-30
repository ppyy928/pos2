import QtQuick
import QtQuick.Layouts
import Mizan

/*
 * The KPI row that sits under a page header. Ported from
 * pos/app/widgets/cards.py::CardGrid.
 *
 * Equal-width cards that WRAP under width pressure instead of stretching thin:
 * all of them share one row while each still gets `minCardWidth`, otherwise they
 * fold onto more rows. That is pos's rule verbatim, and it is why Customers' two
 * cards stop leaving half the screen dead and Cash's five stop cramming.
 *
 *     CardRow {
 *         Layout.fillWidth: true
 *         KpiCard { label: ...; value: ... }
 *         KpiCard { label: ...; value: ... }
 *     }
 *
 * Cards are ordinary children — this file's root IS the layout, so there is no
 * default-property alias to get wrong and a Repeater works here too.
 *
 * WHAT DOES NOT NEED PORTING
 *
 * pos carries a `_dirty_place` flag and an "if cols == self._cols: return" guard
 * with a comment about the hide/show cycle stack-overflowing the GUI thread —
 * relayout ran from resizeEvent, hid and reshowed every card, and that resized
 * the container again. None of it applies to a binding: `columns` is recomputed
 * from the width, nothing is hidden or reparented to apply it, and a binding
 * cannot re-enter itself. pos also had to keep one permanent QGridLayout because
 * replacing an installed layout left every card parentless and floating as its
 * own window; there is no equivalent hazard to guard against here.
 */
GridLayout {
    id: cardRow

    /* The width below which cards wrap to another row rather than shrink. Same
       number as KpiCard.implicitWidth — that is the floor being enforced. */
    property int minCardWidth: 320

    columnSpacing: Tokens.spacing.md
    rowSpacing: Tokens.spacing.md

    /*
     * How many CARDS, which is not how many children.
     *
     * The file header promises a Repeater works here, and it does — but a Repeater
     * is itself an Item and therefore itself a visible child, so counting
     * `visibleChildren.length` counts one too many and every wrap decision below
     * is made on the wrong number. It never showed while every page declared its
     * cards one by one; the Reports screen builds them from a model, and four cards
     * counted as five stopped the orphan rule from ever firing.
     *
     * A Repeater has no size of its own, and a card is 320 wide before it is laid
     * out, so implicitWidth separates them without either one having to know about
     * the other.
     */
    readonly property int cardCount: {
        var n = 0
        var kids = visibleChildren
        for (var i = 0; i < kids.length; i++) {
            if (kids[i].implicitWidth > 0)
                n += 1
        }
        return n
    }

    /*
     * pos: max(1, min(len(cards), (width + spacing) // step)).
     *
     * Before the first layout pass the width is 0, and assuming ONE row then
     * (rather than one column) keeps the row from being born as a tall stack
     * that snaps flat a frame later.
     *
     * ONE ADDITION TO pos'S RULE: NEVER LEAVE A CARD ALONE ON A ROW
     *
     * The greedy count is right whenever the remainder is a row rather than an
     * orphan. It is wrong when exactly one card is left over: four cards in a
     * width that fits three come out 3 + 1, and the single card on the second row
     * reads as something that failed to fit rather than as part of a grid. When
     * that happens the cards are split as evenly as they go instead — 4 becomes
     * 2 + 2, and 5 becomes 3 + 2.
     *
     * The dashboard's six-card band is deliberately untouched by this: 6 in a
     * width that fits 4 leaves a remainder of 2, so it keeps the 4 + 2 its own
     * comment asks for (pos/app/pages/dashboard.py:148-151).
     */
    columns: {
        if (cardCount <= 0)
            return 1
        if (width <= 0)
            return cardCount
        var step = minCardWidth + columnSpacing
        var fit = Math.max(1, Math.min(cardCount, Math.floor((width + columnSpacing) / step)))
        if (fit < cardCount && cardCount % fit === 1)
            return Math.ceil(cardCount / 2)
        return fit
    }
}

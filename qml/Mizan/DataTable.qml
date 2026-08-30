import QtQuick
import QtQuick.Controls as QC
import FluentControls
import Mizan
import "columns.js" as Columns

/*
 * The data grid. Ported from pos/app/widgets/table.py.
 *
 * FluentPySide has no table type at all — 47 controls and not one of them shows
 * rows and columns — so this is the one substantial widget the port has to build
 * rather than reuse. Everything inside it is still Fluent: the scrollbar, the
 * colours, the type ramp.
 *
 * WHAT CARRIED OVER, AND WHAT DID NOT
 *
 * The column model and the width algorithm are pos's, faithfully (see
 * columns.js). So are the row behaviours: whole-row single selection, no
 * in-place editing, double-click to open, elide instead of wrap, right-aligned
 * numbers, soft chips for status columns, and tone driven by the value rather
 * than the position.
 *
 * What deliberately did NOT carry over is the machinery around QHeaderView: the
 * 60ms debounce on resize, the pinned scrollbar policies, the StyleChange
 * re-apply, the delegate diffing and the no-op guard in apply_columns. None of
 * that was product behaviour. It existed because resizing a QHeaderView from
 * inside a resize event re-enters the layout, and with both scrollbar policies
 * free the layout oscillates until Qt recurses into a native stack overflow.
 * Here the widths are a *binding* on the viewport width — a pure function
 * evaluated by the declarative engine, which cannot re-enter itself — so all of
 * it is not just unnecessary but actively harmful: a debounce would show the
 * operator a stale layout for 60ms on every resize.
 *
 * One consequence of dropping the pinned policies: when the declared widths do
 * not fit, this table scrolls sideways instead of silently clipping the last
 * column, which is what pos did to stay out of the recursion.
 *
 * ARABIC
 *
 * Nothing here reverses anything by hand. LayoutMirroring is enabled on the
 * window and inherited, and it mirrors the three things this table is built from:
 * Row positioners (so the first column lands on the right), anchors (so the
 * selection bar and the chips move to the right edge), and Text alignment (so
 * `Text.AlignLeft` below means "leading", not "left"). Alignments are therefore
 * written logically and left alone. The one thing mirroring cannot do is reorder
 * the characters inside a barcode — that is what `ltr` is for.
 *
 * The model may be anything a ListView accepts, as long as each row exposes the
 * column keys by name — a QAbstractListModel with those role names, a ListModel,
 * or a plain JS array of objects. Column keys are chosen by the page at runtime,
 * so cells read the delegate's implicit `model` object rather than declaring
 * required properties, which would have to be known at compile time.
 */
Item {
    id: table

    // =====================================================================
    // API
    // =====================================================================
    property alias model: rows.model

    /*
     * Column specs, in display order. Plain JS objects:
     *
     *   key      string   property/role name on the row
     *   header   string   heading text, already translated by the page
     *   numeric  bool     align to the trailing edge (money, quantities, counts)
     *   stretch  bool     absorb surplus width (names, descriptions)
     *   width    int      declared width; a floor, never a ceiling
     *   ltr      bool     keep the characters in LTR order under Arabic
     *   badge    bool     draw the value as a soft chip
     *   tone     string   | function(row) -> "success"|"info"|"warning"|"danger"|"primary"
     *   actions  array    draw icon actions instead of a value — see RowActions
     *
     * Everything but `key` is optional. `tone` as a function is how a value earns
     * its colour — a negative balance is red because it is negative, not because
     * it is in the balance column.
     *
     * `badge` and `actions` are the two cells that draw something other than
     * text, and a column picks at most one of them.
     */
    property var columns: []

    /*
     * The selected row, or -1. An alias rather than a property with a binding:
     * the view writes to it on click and on arrow keys, and a plain property
     * would have its binding destroyed the first time that happened. Pages can
     * read it, write it, and watch onCurrentRowChanged.
     */
    property alias currentRow: rows.currentIndex

    readonly property int count: rows.count

    /* Double-click, or Enter on the focused row. The page decides what "open"
       means — a detail page, an editor, adding to the cart. */
    signal rowActivated(int row)

    /* An icon in an `actions` column was pressed. Row index and action id, which
       is pos's `on_action(index.row(), action_id)` exactly — one handler per page
       switching on the id, rather than a signal per action. */
    signal actionTriggered(int row, string action)

    /* Right-click on a row. The row is selected first, so the menu the page pops
       visibly belongs to something — pos does the same (`indexAt(pos)` then the
       menu). No position travels with the signal: Menu.popup() with no arguments
       opens at the cursor, which is where pos puts it too
       (`menu.exec(viewport().mapToGlobal(pos))`).

       Every list page in pos has one of these — details / edit / a toggle or two /
       delete — so it belongs here rather than being rebuilt per page. */
    signal rowContextRequested(int row)

    // Empty state. `emptyIcon` is a Fluent icon name; Icon draws nothing at all
    // for a name that is not in the font index, so it is a property rather than
    // a literal buried in the tree.
    property string emptyText: Strings.t("table.empty", "Nothing to show")
    property string emptyDetail: ""
    property string emptyIcon: "ic_fluent_table_search_20_regular"

    property bool showHeader: true

    // =====================================================================
    // SIZING TO CONTENT
    // =====================================================================
    /*
     * TWO WAYS TO USE THIS TABLE, AND ONLY ONE OF THEM SCROLLS.
     *
     * The default is a viewport: the caller gives it a height, it shows what fits and
     * flicks for the rest, and ListView instantiates only the visible delegates.
     * That is right for a page whose table IS the page.
     *
     * `scrollable: false` is for a table inside a page that already scrolls. It turns
     * off the vertical bar and the flick, and `naturalHeight` is what the caller
     * should then set its height to — the table becomes one tall block and the
     * page's own scrollbar moves it. Two scrollbars on one screen, one nested inside
     * the other, is the thing this exists to avoid: the reader has to work out which
     * one they are pointing at, and the wheel answers whichever the cursor happens to
     * be over.
     *
     * THE CALLER MUST BOUND THE ROWS
     *
     * A non-scrolling table renders every row it is given, because its viewport is
     * its full height. That is fine for the fifty rows a page shows at a time and
     * ruinous for two thousand. Pair `scrollable: false` with paging — the Reports
     * screen does exactly that.
     */
    property bool scrollable: true

    readonly property int naturalHeight: (showHeader ? Tokens.size.tableHeader : 0)
                                         + count * Tokens.size.tableRow

    // =====================================================================
    // SORTING
    // =====================================================================
    /*
     * THIS TABLE DOES NOT SORT. IT ASKS.
     *
     * `sortRequested` goes out, `sortColumn` and `sortDescending` come back in, and
     * the arrow in the header is drawn from whatever they say. The rows arrive
     * already in order, exactly as they always have.
     *
     * That split is not ceremony. Every money value that reaches this component has
     * been through fmt.money and is a STRING with a thousands separator in it — and
     * `"1,234.50" < "9.00"` is true. Half the columns also carry a U+200E so their
     * digits survive an Arabic paragraph. Sorting here would mean parsing the
     * formatting back off values that were formatted precisely so nobody downstream
     * would have to, and getting it wrong on the first column whose format changes.
     * Whoever produced the numbers still has them.
     *
     * A column opts out with `sortable: false`. Columns of `actions` never sort —
     * there is nothing to compare.
     */
    property int sortColumn: -1
    property bool sortDescending: false

    signal sortRequested(int column)

    function sortableAt(index) {
        if (index < 0 || index >= columns.length)
            return false
        var spec = columns[index]
        if (spec.actions !== undefined)
            return false
        return spec.sortable !== false && spec.key !== undefined
    }

    // =====================================================================
    // LAYOUT
    // =====================================================================
    /*
     * Fluent's scrollbar is an overlay: transparent until it is touched, 12px
     * wide when expanded, and it does not narrow the flickable. No strip is
     * reserved for it, because `cellPadding` is already wider than the bar — a
     * value in the trailing column stops 16px short of the edge and the bar lives
     * in that gap. Reserving width instead would mean deciding whether the table
     * currently overflows, which changes the widths, which changes nothing about
     * the row heights but does change the content height — a layout that can
     * flip back and forth across the boundary. A constant that is simply large
     * enough cannot.
     *
     * It also means the bar is free to mirror itself to the left edge in Arabic,
     * which it does, on its own.
     */
    readonly property int cellPadding: Tokens.spacing.md

    /* null when the declared widths already overflow. */
    readonly property var fittedWidths: Columns.distribute(columns, width)
    readonly property bool fits: fittedWidths !== null

    readonly property var colWidths: fits ? fittedWidths : nominalWidths()

    function nominalWidths() {
        var out = []
        for (var i = 0; i < columns.length; i++)
            out.push(Columns.nominalWidth(columns[i]))
        return out
    }

    readonly property int rowWidth: {
        var total = 0
        for (var i = 0; i < colWidths.length; i++)
            total += colWidths[i]
        return total
    }

    // =====================================================================
    // HELPERS
    // =====================================================================
    /* U+200E LEFT-TO-RIGHT MARK. Prefixed to a `ltr` column's text so a barcode,
       a phone number or an invoice reference keeps its characters in the order
       they were entered when the surrounding paragraph is Arabic. Without it the
       bidi algorithm resolves a run of digits and dashes against the paragraph
       direction and "0612-345" comes out reversed. On an ASCII value in an LTR
       paragraph it changes nothing, so it is applied unconditionally.

       Worth noting that pos declares this flag on ~20 columns and never reads it
       anywhere — it is dead there, so Arabic barcodes are reversed today. It is
       implemented here because the flag was clearly meant to do something. */
    readonly property string lrm: "‎"

    function displayOf(column, rowObj) {
        var value = rowObj ? rowObj[column.key] : undefined
        if (value === undefined || value === null)
            return ""
        return column.ltr ? lrm + value : "" + value
    }

    /* "" for a row with nothing remarkable about it, which is the common case. */
    function toneOf(column, rowObj) {
        if (!column.tone)
            return ""
        if (typeof column.tone === "function")
            return column.tone(rowObj)
        return column.tone
    }

    /* Logical, not visual: LayoutMirroring turns AlignLeft into AlignRight in
       Arabic on its own. Numbers align to the trailing edge so a column of them
       lines up on its last digit, whichever way the script runs. */
    function alignmentOf(column) {
        return column.numeric ? Text.AlignRight : Text.AlignLeft
    }

    // =====================================================================
    // HEADER
    // =====================================================================
    Item {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: table.showHeader ? Tokens.size.tableHeader : 0
        visible: table.showHeader
        clip: true

        Rectangle {
            anchors.fill: parent
            color: Fluent.subtleSecondary
        }

        Row {
            /* Slides with the rows when the table is wide enough to scroll
               sideways. Explicit x is not mirrored by LayoutMirroring — only
               anchors, positioners and text alignment are — so this stays
               measured from the left in Arabic, which is also what Flickable's
               contentX means there. */
            x: -rows.contentX
            width: table.rowWidth
            height: parent.height

            Repeater {
                model: table.columns

                Item {
                    id: headerCell
                    required property var modelData
                    required property int index

                    width: index < table.colWidths.length ? table.colWidths[index] : 0
                    height: header.height

                    readonly property bool sortable: table.sortableAt(headerCell.index)
                    readonly property bool sorted: table.sortColumn === headerCell.index

                    /* The label and the arrow travel together, packed against the
                       edge the column's values sit on — a right-aligned money
                       column gets a right-aligned heading with the arrow beside
                       the digits it orders.

                       `layoutDirection` does the packing, so the Text must size to
                       its OWN content: given a fill width it would push the arrow to
                       the far side of the cell, which put the Total column's arrow
                       against the Qty column's numbers. */
                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: table.cellPadding
                        anchors.rightMargin: table.cellPadding
                        spacing: Tokens.spacing.xs
                        layoutDirection: table.alignmentOf(headerCell.modelData) === Text.AlignRight
                                         ? Qt.RightToLeft : Qt.LeftToRight

                        readonly property real room: Math.max(0, width
                                                    - (arrow.visible
                                                       ? arrow.width + spacing : 0))

                        Text {
                            id: label
                            width: Math.min(implicitWidth, parent.room)
                            height: parent.height
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: table.alignmentOf(headerCell.modelData)
                            text: headerCell.modelData.header !== undefined
                                  ? headerCell.modelData.header : ""
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.overline
                            font.weight: Font.DemiBold
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: 0.8
                            /* The sorted column's heading steps forward. It is the
                               one piece of state a header row has, and an arrow
                               alone is small at 13px. */
                            color: headerCell.sorted ? Tokens.brand
                                 : headerCell.sortable && headerHover.hovered
                                   ? Fluent.textPrimary : Fluent.textSecondary
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        Icon {
                            id: arrow
                            anchors.verticalCenter: parent.verticalCenter
                            visible: headerCell.sorted
                            icon: table.sortDescending
                                  ? "ic_fluent_arrow_down_20_filled"
                                  : "ic_fluent_arrow_up_20_filled"
                            size: Tokens.icon.xs
                            color: Tokens.brand
                        }
                    }

                    HoverHandler {
                        id: headerHover
                        enabled: headerCell.sortable
                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        enabled: headerCell.sortable
                        onTapped: table.sortRequested(headerCell.index)
                    }
                }
            }
        }

        // On top of the header fill, so the line reads as the boundary between
        // heading and data rather than as the bottom edge of a bar.
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Fluent.divider
        }
    }

    // =====================================================================
    // ROWS
    // =====================================================================
    ListView {
        id: rows
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        clip: true

        /* Wider than the viewport only when the declared widths did not fit, and
           then the whole table flicks sideways rather than losing its last
           column. In Arabic that fallback still opens at contentX 0, which is the
           far end of the content — a page whose columns fit, which is the normal
           case, never reaches it. */
        contentWidth: table.rowWidth

        // Fluent's own scrollbar, and the same one ScrollView installs. It
        // anchors itself to the flickable's trailing edge, so it moves to the
        // left in Arabic without being told. Absent entirely when the table is
        // sized to its content — see `scrollable`.
        QC.ScrollBar.vertical: FluentScrollBar {
            policy: table.scrollable ? QC.ScrollBar.AsNeeded : QC.ScrollBar.AlwaysOff
        }

        /* A content-sized table must not swallow the wheel: the gesture belongs to
           the page it is sitting in. Horizontal flicking survives, because a table
           wider than its column still has to reach its last column. */
        interactive: table.scrollable

        // Keyboard: arrows move the row, Enter opens it. Reachable by Tab so the
        // table is usable without a mouse, which is how a till gets used when
        // the scanner is doing the pointing.
        activeFocusOnTab: true
        keyNavigationEnabled: true
        Keys.onReturnPressed: if (currentIndex >= 0) table.rowActivated(currentIndex)
        Keys.onEnterPressed: if (currentIndex >= 0) table.rowActivated(currentIndex)

        // Nothing selected until something is chosen. A table that arrives with
        // row 0 highlighted invites an operator to act on a row they never picked.
        currentIndex: -1
        highlight: null

        delegate: Rectangle {
            id: row

            /* The delegate's implicit context object: the row. Column keys are
               only known at runtime, so this cannot be a set of declared role
               properties. `modelData` is what a plain JS array or a role-less
               model provides; `model` is what a role-based one provides. */
            readonly property var rowData: (typeof modelData !== "undefined"
                                            && modelData !== null
                                            && typeof modelData === "object")
                                           ? modelData : model

            readonly property bool selected: ListView.isCurrentItem

            /* The row's index, under a name of its own. The cell Repeater below
               redeclares `index` as the *column* index, which shadows this one
               everywhere inside a cell — so an action cell has no other way to
               say which row it was pressed on. */
            readonly property int rowIndex: index

            width: table.rowWidth
            height: Tokens.size.tableRow

            /* Three steps, faintest first, so the states can never be confused
               with each other: the zebra stripe is the quietest thing on the
               table, hover is one step up from it, and selection is brand. */
            color: selected ? Tokens.brandTint
                 : pointer.containsMouse ? Fluent.subtleSecondary
                 : (index % 2 === 1 ? Fluent.subtleTertiary : "transparent")

            Behavior on color {
                ColorAnimation { duration: 100; easing.type: Easing.OutCubic }
            }

            // Selection marker, on the leading edge — anchors mirror, so it moves
            // to the right-hand side in Arabic on its own.
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 4
                color: Tokens.brand
                visible: row.selected
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: Fluent.divider
            }

            MouseArea {
                id: pointer
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (mouse) => {
                    rows.currentIndex = index
                    rows.forceActiveFocus()
                    if (mouse.button === Qt.RightButton)
                        table.rowContextRequested(index)
                }
                onDoubleClicked: {
                    rows.currentIndex = index
                    table.rowActivated(index)
                }
            }

            Row {
                anchors.fill: parent

                Repeater {
                    model: table.columns

                    Item {
                        id: cell
                        required property var modelData
                        required property int index

                        /* Which of the three cell bodies below draws. Resolved
                           once, so they are mutually exclusive by construction
                           instead of by three separate conditions that could all
                           come out true on a column declaring both `badge` and
                           `actions`. */
                        readonly property string kind: modelData.actions !== undefined ? "actions"
                                                     : modelData.badge === true ? "badge"
                                                     : "text"

                        readonly property string tone: table.toneOf(modelData, row.rowData)
                        readonly property string display: table.displayOf(modelData, row.rowData)

                        width: index < table.colWidths.length ? table.colWidths[index] : 0
                        height: row.height

                        // Plain cell.
                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: table.cellPadding
                            anchors.rightMargin: table.cellPadding
                            visible: cell.kind === "text"
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: table.alignmentOf(cell.modelData)
                            text: cell.display
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.body
                            /*
                             * TABULAR FIGURES ON THE COLUMNS THAT HOLD NUMBERS.
                             *
                             * This used to say it could not be done — that
                             * `font.features` needs a newer Qt and assigning a
                             * property the runtime does not have fails the whole page
                             * at load. The property arrived in Qt 6.7 and this app
                             * runs 6.9.3, so it can be, and it matters more than the
                             * note assumed: measured at 34px in Segoe UI Variable,
                             * ten 1s are 130px wide and ten 0s are 190px. A money
                             * column of proportional digits does not line up under
                             * its own heading no matter how it is aligned.
                             *
                             * Numeric and ltr columns only. Prose wants proportional
                             * digits; a product called "Atlas Beans 1L" is not a
                             * quantity.
                             */
                            font.features: (cell.modelData.numeric === true
                                            || cell.modelData.ltr === true)
                                           ? Tokens.figures : ({})
                            /* A toned value is bold as well as coloured, so the
                               row still reads as exceptional in a screenshot, on
                               a projector, or to an operator who cannot separate
                               red from green. */
                            font.weight: cell.tone !== "" ? Font.DemiBold : Font.Normal
                            color: cell.tone !== "" ? Tokens.toneInk(cell.tone)
                                                    : Fluent.textPrimary
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        /* Badge cell: a soft chip, sized to its text and clamped
                           to the column so a long status cannot push into its
                           neighbour. Always on the leading edge — a status is
                           never a number — and anchors mirror, so Arabic puts it
                           on the right. */
                        Rectangle {
                            visible: cell.kind === "badge" && cell.display !== ""
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: table.cellPadding

                            height: 32
                            width: Math.min(chipLabel.implicitWidth + 2 * Tokens.spacing.sm,
                                            Math.max(cell.width - 2 * table.cellPadding, 40))
                            radius: Tokens.radius.sm
                            color: Tokens.toneFill(cell.tone)

                            Text {
                                id: chipLabel
                                anchors.fill: parent
                                anchors.leftMargin: Tokens.spacing.sm
                                anchors.rightMargin: Tokens.spacing.sm
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignHCenter
                                text: cell.display
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.caption
                                font.weight: Font.DemiBold
                                color: Tokens.toneInk(cell.tone)
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                        }

                        /* Action cell. Free in an ordinary column: the list is
                           empty there, so the Repeater inside creates no buttons
                           at all and there is nothing to hide. */
                        RowActions {
                            anchors.fill: parent
                            actions: cell.kind === "actions" ? cell.modelData.actions : []
                            rowData: row.rowData
                            onTriggered: (action) => table.actionTriggered(row.rowIndex, action)
                        }
                    }
                }
            }
        }
    }

    // =====================================================================
    // EMPTY STATE
    // =====================================================================
    Column {
        anchors.centerIn: rows
        width: Math.max(200, Math.min(rows.width - 2 * Tokens.spacing.xxl, 420))
        spacing: Tokens.spacing.sm
        visible: rows.count === 0

        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            icon: table.emptyIcon
            size: Tokens.icon.xl
            color: Fluent.textTertiary
            visible: table.emptyIcon !== ""
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: table.emptyText
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.bodyLarge
            color: Fluent.textSecondary
            wrapMode: Text.WordWrap
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: table.emptyDetail
            visible: table.emptyDetail !== ""
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.body
            color: Fluent.textTertiary
            wrapMode: Text.WordWrap
        }
    }
}

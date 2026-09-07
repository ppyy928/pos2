import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * The select-product table — the one list a product is chosen from.
 *
 *   ┌ [ search by name or barcode ...................... ] ┐
 *   │ NAME         BARCODE        CATEGORY   STOCK  PRICE │
 *   │ Yoghurt 1L  5449000996     Dairy       24    89.00 │
 *   │ Yoghurt fraise  5449000521 Dairy       12    89.00 │
 *   │ 2 / 2,999                                            │
 *   └───────────────────────────────────────────────────────┘
 *
 * WHY THIS EXISTS, AND WHY IT IS A TABLE
 *
 * A picker row carries five facts — the name, the barcode that matched, the
 * category two products share, what is on the shelf and what it costs — and
 * each picker used to arrange them its own way: the till's dialog as two
 * stacked lines with tags, the finder's browse list as a third shape, the
 * multi-unit form as names alone. None of them said which figure was which.
 * One table with a heading over each column says so, and this is it: the same
 * body inside the till's `product_select` dialog, inside ProductFinder's
 * browse popup, and inside the multi-unit form's product question.
 *
 * WHY EVERYTHING AT ONCE
 *
 * The catalogue is handed over whole, when the shell opens, and filtered here
 * in JavaScript. No paging, no query per keystroke: a JavaScript pass over a
 * few thousand rows is faster than a round trip, and ListView instantiates
 * only the delegates it can show. A hard ceiling is the other thing this
 * avoids — a row the operator wanted that never appears no matter how the
 * query is refined. The callers' `catalogue()` slots carry the fuse on that
 * reasoning, not this file.
 *
 * THE PICK CONTRACT
 *
 * A single click chooses, the same as every picker this app has had — a list
 * whose whole purpose is to choose one row does not make the operator confirm
 * the click. Double-click and Enter arrive through the table's own activation,
 * and the arrows move the selection while the search field keeps focus, so the
 * whole thing is one text field as far as the hands are concerned.
 *
 * OUT OF STOCK IS THE TILL'S QUESTION, NOT THE LIST'S
 *
 * `requireStock` is off everywhere but the till: a delivery of a product at
 * zero is the normal reason a delivery happens, a stocktake exists to find
 * zeros, and a movement ledger reads them. Only the till reports the empty
 * shelf instead of handing the row over — and even there a product with no
 * shelf (`track_stock` off) never runs out, which is the tile wall's rule too.
 */
Item {
    id: picker

    // =====================================================================
    // API
    // =====================================================================
    /* The catalogue, as handed over once by the shell. Never re-fetched while
       the picker is open: a price or a stock figure changing under the operator
       mid-search would reorder the list they are reading. */
    property var catalogue: []

    /* The till's rule: an out-of-stock row is reported, not picked. */
    property bool requireStock: false

    property string query: ""

    /* One product was chosen. The shell decides what that means — a cart line,
       a sheet line, a filter — and closes itself. */
    signal picked(var product)

    function focusSearch() { field.forceActiveFocus() }

    /* Back to a blank list. Shells call it as they open, so a picker that was
       opened before starts clean rather than still holding the last query. */
    function reset() {
        error.text = ""
        field.clear()
        /* Directly as well: `query` is the public property, and clearing the
           field only clears it through the field's own change signal. */
        picker.query = ""
        table.currentRow = -1
    }

    /*
     * The filter.
     *
     * Name OR barcode, which is what `fetch_products` matches in SQL — so
     * typing part of a code finds the product the same way typing part of a
     * name does, and this list agrees with the dropdown behind it.
     *
     * `toLowerCase` rather than a locale-aware fold: SQLite's ILIKE is itself
     * only ASCII-case-insensitive, so matching JavaScript's default here keeps
     * the two paths returning the same set rather than making this one subtly
     * cleverer.
     */
    readonly property var rows: {
        var src = picker.decorated
        var q = picker.query.trim().toLowerCase()
        if (q === "")
            return src

        var out = []
        for (var i = 0; i < src.length; i++) {
            var row = src[i]
            var code = String(row.barcode || "").toLowerCase()
            if (String(row.name).toLowerCase().indexOf(q) >= 0
                    || code.indexOf(q) >= 0)
                out.push(row)
        }
        return out
    }

    /* The catalogue with the status column filled in. Done once per catalogue
       rather than once per keystroke: the filter above reads this, and the
       facts it decorates do not change with the query.

       Out of stock wins the one chip over hidden, when a product is both: it is
       the fact the operator can still act on, and the more urgent of the two. */
    readonly property var decorated: {
        var src = picker.catalogue || []
        var out = []
        for (var i = 0; i < src.length; i++) {
            var row = src[i]
            var status = ""
            var tone = ""
            if (row.track_stock !== false && Number(row.stock) <= 0) {
                status = Strings.t("pos.tile.out_of_stock", "Out of stock")
                tone = "danger"
            } else if (row.hidden === true) {
                status = Strings.t("products.hidden_on_pos", "Hidden on the till")
                tone = "warning"
            }
            out.push(Object.assign({}, row, { status: status, status_tone: tone }))
        }
        return out
    }

    onQueryChanged: table.currentRow = -1

    // =====================================================================
    // CHOOSING
    // =====================================================================
    function take(index) {
        var list_ = picker.rows
        if (index < 0 || index >= list_.length)
            return
        var row = list_[index]
        if (picker.requireStock && row.track_stock !== false
                && Number(row.stock) <= 0) {
            error.text = row.name + " — "
                       + Strings.t("pos.tile.out_of_stock", "Out of stock")
            return
        }
        error.text = ""
        picker.picked(row)
    }

    /* Enter. Narrowed to one row, that row is obviously what was meant — pos
       does the same, and it is what makes the picker usable without the mouse.
       With several rows nothing is taken until one is chosen: a table that
       arrives with a row already acted on invites an operator to add a product
       they never picked. */
    function submit() {
        if (picker.rows.length === 1)
            picker.take(0)
        else
            picker.take(table.currentRow)
    }

    function step(delta) {
        var n = picker.rows.length
        if (n === 0)
            return
        var next = table.currentRow + delta
        table.currentRow = next < 0 ? 0 : (next > n - 1 ? n - 1 : next)
        table.revealRow(table.currentRow)
    }

    // =====================================================================
    // LAYOUT
    // =====================================================================
    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacing.sm

        QC.TextField {
            id: field
            Layout.fillWidth: true
            Layout.preferredHeight: Tokens.size.control
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.bodyLarge
            placeholderText: Strings.t("products.search.ph",
                                       "Search by name or barcode")
            onTextChanged: picker.query = text
            onAccepted: picker.submit()

            /* The arrows move the selection while the field keeps focus, so the
               whole picker is one text field as far as the hands are
               concerned. */
            Keys.onDownPressed: picker.step(1)
            Keys.onUpPressed: picker.step(-1)
            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_PageDown) {
                    picker.step(10)
                    event.accepted = true
                } else if (event.key === Qt.Key_PageUp) {
                    picker.step(-10)
                    event.accepted = true
                }
            }
        }

        /* The table itself, bare: every page in this app seats its DataTable
           straight on the surface, and a card around it would only put square
           header corners over a rounded frame. */
        DataTable {
            id: table
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 280
            columns: picker.columns
            model: picker.rows
            emptyIcon: "ic_fluent_search_20_regular"
            emptyText: picker.query !== ""
                       ? Strings.t("state.no_results.title", "No matches")
                       : Strings.t("state.empty.title", "Nothing here yet")
            onRowClicked: (row) => picker.take(row)
            onRowActivated: (row) => picker.take(row)
        }

        Text {
            id: error
            Layout.fillWidth: true
            visible: text !== ""
            wrapMode: Text.WordWrap
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.caption
            color: Tokens.danger
        }

        /* The count, because "everything" is a claim worth backing with a
           number — and because "12 of 2,999" tells the operator whether to
           refine the query or start scrolling. */
        Text {
            Layout.fillWidth: true
            text: picker.query === ""
                  ? "\u200e" + picker.rows.length
                  : "\u200e" + picker.rows.length + " / "
                    + (picker.catalogue || []).length
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.caption
            color: Fluent.textSecondary
        }
    }

    // =====================================================================
    // THE COLUMNS
    // =====================================================================
    /* Not sortable, any of them: the rows arrive in the catalogue's own order
       and a search box answers "which row" better than a sort on a name the
       operator already half knows. */
    readonly property var columns: [
        {
            key: "name",
            header: Strings.t("products.col.name", "Name"),
            stretch: true,
            sortable: false
        },
        {
            key: "barcode",
            header: Strings.t("products.col.barcode", "Barcode"),
            width: 190,
            ltr: true,
            sortable: false
        },
        {
            key: "category",
            header: Strings.t("products.col.category", "Category"),
            width: 170,
            sortable: false
        },
        {
            key: "stock_text",
            header: Strings.t("products.col.stock", "Stock"),
            numeric: true,
            width: 120,
            ltr: true,
            sortable: false
        },
        {
            key: "price_text",
            header: Strings.t("products.col.sale_price", "Sale Price"),
            numeric: true,
            width: 140,
            ltr: true,
            sortable: false
        },
        {
            key: "status",
            header: Strings.t("employees.col.status", "Status"),
            badge: true,
            width: 170,
            sortable: false,
            tone: function (r) { return r.status_tone }
        }
    ]
}

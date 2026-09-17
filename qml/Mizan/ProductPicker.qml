import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * The select-product table — the one list a product is chosen from.
 *
 *   ┌ [ search by name or barcode ................ ] [ All categories ▾ ] ┐
 *   │ NAME            BARCODE        STOCK      SALE PRICE                │
 *   │ Yoghurt 1L      5449000996     24         89.00                     │
 *   │ Yoghurt fraise  5449000521     12         89.00                     │
 *   │ 1–100 of 2,999          ‹‹ ‹ Page 1 of 30 › ››        100 / page    │
 *   └──────────────────────────────────────────────────────────────────────┘
 *
 * WHY THIS EXISTS, AND WHY IT IS A TABLE
 *
 * A picker row carries four facts — the name, the barcode that matched, what
 * is on the shelf and what it costs — and each picker used to arrange them its
 * own way: the till's dialog as two stacked lines with tags, the finder's
 * browse list as a third shape, the multi-unit form as names alone. None of
 * them said which figure was which. One table with a heading over each column
 * says so, and this is it: the same body inside the till's `product_select`
 * dialog, inside ProductFinder's browse popup, and inside the multi-unit
 * form's product question. The category is a filter above the table rather
 * than a column in it — it narrows the list far better than a repeated word
 * down a column spends width saying.
 *
 * WHY EVERYTHING AT ONCE — AND WHY THE PAGER DOES NOT CONTRADICT IT
 *
 * The catalogue is handed over whole, when the shell opens, and filtered here
 * in JavaScript. No query per keystroke: a JavaScript pass over a few thousand
 * rows is faster than a round trip, and ListView instantiates only the
 * delegates it can show. A hard ceiling is the other thing this avoids — a row
 * the operator wanted that never appears no matter how the query is refined.
 * The callers' `catalogue()` slots carry the fuse on that reasoning, not this
 * file.
 *
 * The pager is presentation, not transport. The whole catalogue is still
 * searched at once; what is paged is the ANSWER — one slice of the filtered
 * rows at a time, with the pages' own PaginationBar, so "100 / page" and
 * "Page 1 of 30" mean here exactly what they mean on Products. Paging in the
 * database would be the thing to avoid: a query per keystroke, and "the row I
 * wanted was on page 4".
 *
 * WHY THE CATEGORY SITS BESIDE THE FIELD
 *
 * The field answers "which row"; the category answers "which shelf", and those
 * are the same two questions the Products page puts side by side. The options
 * are built from the catalogue in hand — a picker is handed a fixed list, not
 * a controller — and only from names it actually carries: a category no row
 * has is a filter that can only ever answer nothing.
 *
 * THE PICK CONTRACT
 *
 * A single click chooses, the same as every picker this app has had — a list
 * whose whole purpose is to choose one row does not make the operator confirm
 * the click. Double-click and Enter arrive through the table's own activation,
 * and the arrows move the selection while the search field keeps focus, so the
 * whole thing is one text field as far as the hands are concerned. The arrows
 * carry the selection across a page boundary too: walking down the list is
 * walking down the list, not walking into the end of page one.
 *
 * OUT OF STOCK IS THE TILL'S QUESTION, NOT THE LIST'S
 *
 * `requireStock` is off everywhere but the till: a delivery of a product at
 * zero is the normal reason a delivery happens, a stocktake exists to find
 * zeros, and a movement ledger reads them. Only the till reports the empty
 * shelf instead of handing the row over — and even there a product with no
 * shelf (`track_stock` off) never runs out, which is the tile wall's rule too.
 * The refusal is said where it applies, when the row is picked; the list keeps
 * no column of verdicts over rows that are all perfectly choosable somewhere
 * else.
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

    /* The shelf the list is narrowed to: a category NAME from the catalogue,
       "" for all of them. A name rather than an id because this component is
       handed rows, not a controller — the rows carry the category as the words
       the shop typed, and two rows of the same words are the same shelf. */
    property string category: ""

    property int currentPage: 1
    property int pageSize: 100

    /* One product was chosen. The shell decides what that means — a cart line,
       a sheet line, a filter — and closes itself. */
    signal picked(var product)

    function focusSearch() { field.forceActiveFocus() }

    /* Back to a blank list. Shells call it as they open, so a picker that was
       opened before starts clean rather than still holding the last query —
       and a filter still narrowing the row the operator came back for. */
    function reset() {
        error.text = ""
        field.clear()
        /* Directly as well: `query` is the public property, and clearing the
           field only clears it through the field's own change signal. */
        picker.query = ""
        picker.category = ""
        categoryBox.currentIndex = 0
        picker.currentPage = 1
        picker.current = -1
        table.currentRow = -1
    }

    /*
     * The filter.
     *
     * Name OR barcode, which is what `fetch_products` matches in SQL — so
     * typing part of a code finds the product the same way typing part of a
     * name does, and this list agrees with the dropdown behind it. The
     * category is answered first and exactly, because a shelf is a fact about
     * the row rather than something a name search is trying to recognise.
     *
     * `toLowerCase` rather than a locale-aware fold: SQLite's ILIKE is itself
     * only ASCII-case-insensitive, so matching JavaScript's default here keeps
     * the two paths returning the same set rather than making this one subtly
     * cleverer.
     */
    readonly property var rows: {
        var src = picker.catalogue || []
        var q = picker.query.trim().toLowerCase()
        var shelf = picker.category
        if (q === "" && shelf === "")
            return src

        var out = []
        for (var i = 0; i < src.length; i++) {
            var row = src[i]
            if (shelf !== "" && String(row.category || "") !== shelf)
                continue
            if (q === "") {
                out.push(row)
                continue
            }
            var code = String(row.barcode || "").toLowerCase()
            if (String(row.name).toLowerCase().indexOf(q) >= 0
                    || code.indexOf(q) >= 0)
                out.push(row)
        }
        return out
    }

    /*
     * The shelf options beside the field: "All categories", then every
     * category the catalogue in hand actually carries, once, in the order the
     * catalogue lists them.
     */
    readonly property var categories: {
        var seen = {}
        var out = [{ key: "",
                     name: Strings.t("products.filter.all_categories",
                                     "All categories") }]
        var src = picker.catalogue || []
        for (var i = 0; i < src.length; i++) {
            var name = String(src[i].category || "")
            if (name === "" || seen[name] === true)
                continue
            seen[name] = true
            out.push({ key: name, name: name })
        }
        return out
    }

    /* The pages of the filtered list, and the slice the table is showing. The
       arithmetic is PaginationBar's own: a page is `pageSize` rows of the
       ANSWER, so narrowing the filter narrows the pages with it. */
    readonly property int maxPage: Math.max(1, Math.ceil(
        rows.length / Math.max(1, picker.pageSize)))
    readonly property int pageStart: (picker.currentPage - 1)
                                     * Math.max(1, picker.pageSize)
    readonly property var pageRows: rows.slice(
        pageStart, pageStart + Math.max(1, picker.pageSize))

    /* The selection in the filtered list's terms. `table.currentRow` is an
       index into the page on screen; this is an index into the rows behind it,
       which is what the arrows walk and what crosses a page boundary. */
    property int current: -1

    function indexOfCategory(key) {
        var list_ = picker.categories
        for (var i = 0; i < list_.length; i++)
            if (list_[i].key === key)
                return i
        return 0
    }

    function setCategory(key) {
        if (picker.category === key)
            return
        picker.category = key
        picker.currentPage = 1
        picker.current = -1
        table.currentRow = -1
    }

    /* A narrowed filter can leave the page on screen past the end — the table
       would sit on an empty slice with the rows it wants one page back. */
    function clampPage() {
        if (picker.currentPage > picker.maxPage)
            picker.currentPage = picker.maxPage
    }

    onRowsChanged: picker.clampPage()

    onQueryChanged: {
        picker.currentPage = 1
        picker.current = -1
        table.currentRow = -1
    }

    // =====================================================================
    // CHOOSING
    // =====================================================================
    /* `index` is the row's index on the PAGE — that is the list the table is
       showing and the list its signals count in — mapped here onto the
       filtered rows behind it. */
    function take(index) {
        var list_ = picker.pageRows
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
        /* Where the hand is, so the arrows continue from the row that was
           clicked as well as from the row an arrow landed on. */
        picker.current = picker.pageStart + index
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
        var next = picker.current < 0 ? 0 : picker.current + delta
        picker.select(Math.min(Math.max(0, next), n - 1))
    }

    /*
     * Move the selection to a filtered-list index, carrying it across a page
     * boundary when it walks off the page on screen.
     *
     * The table's row index is written AFTER the slice has changed under it:
     * the table's model IS the page, so the same write made before the swap
     * would select the row at that index in the OLD page. `Qt.callLater` is
     * that "after" — one turn of the event loop, when the model has settled.
     */
    function select(index) {
        picker.current = index
        var page = Math.floor(index / Math.max(1, picker.pageSize)) + 1
        if (page !== picker.currentPage) {
            picker.currentPage = page
            Qt.callLater(picker.revealCurrent)
        } else {
            picker.revealCurrent()
        }
    }

    /* Put the table's cursor where `current` says, on the page now showing. */
    function revealCurrent() {
        var local = picker.current - picker.pageStart
        if (local < 0 || local >= picker.pageRows.length)
            return
        table.currentRow = local
        table.revealRow(local)
    }

    // =====================================================================
    // LAYOUT
    // =====================================================================
    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacing.sm

        /* The two questions of a pick, side by side: which row, and which
           shelf. The same pairing the Products page seats above its table. */
        RowLayout {
            Layout.fillWidth: true
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

            /* The category, from the catalogue itself. currentIndex is
               deliberately unbound — the same rule ProductsPage's filter
               states: ComboBox writes it internally on every pick, which would
               destroy a binding — so it is set explicitly in the three places
               it can change: the operator chose, the list was rebuilt (a
               language change retranslating "All categories"), and reset()
               above. */
            QC.ComboBox {
                id: categoryBox
                Layout.preferredWidth: 260
                Layout.preferredHeight: Tokens.size.control
                textRole: "name"
                model: picker.categories
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body

                onActivated: (index) => picker.setCategory(model[index].key)
                onModelChanged: currentIndex = picker.indexOfCategory(picker.category)
                Component.onCompleted: currentIndex = picker.indexOfCategory(picker.category)
            }
        }

        /* The table itself, bare: every page in this app seats its DataTable
           straight on the surface, and a card around it would only put square
           header corners over a rounded frame. Its model is the page on
           screen, not the whole filtered list — the pager below owns which
           page that is. */
        DataTable {
            id: table
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 280
            columns: picker.columns
            model: picker.pageRows
            emptyIcon: "ic_fluent_search_20_regular"
            emptyText: picker.query !== "" || picker.category !== ""
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

        /* The pager, the pages' own: the range, the page and the page size,
           meaning here exactly what they mean under Products or Sales. Hidden
           while there is nothing to page — the table's empty state above
           already says so, and a bar reading "0–0 of 0" over an empty list is
           a control offering a tour of nothing. */
        PaginationBar {
            Layout.fillWidth: true
            visible: picker.rows.length > 0
            page: picker.currentPage
            total: picker.rows.length
            pageSize: picker.pageSize

            /* `requested`, not `page`: a handler parameter named after the
               property it sets would shadow PaginationBar's own `page` inside
               this scope, which reads as a self-assignment. Pages' rule. */
            onPageRequested: (requested) => {
                picker.currentPage = requested
                picker.current = -1
                table.currentRow = -1
            }
            onPageSizeRequested: (requested) => {
                picker.pageSize = requested
                picker.currentPage = 1
                picker.current = -1
                table.currentRow = -1
            }
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
        }
    ]
}

import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * Products — the first rebuilt list page, and the blueprint for the other
 * eleven. Ported from pos/app/pages/products.py.
 *
 *   PageHeader        title, description, and the page's own actions
 *   CardRow           four KpiCards: count, stock value, low stock, categories
 *   FilterBar         category combo + debounced search + refresh
 *   DataTable         seven columns, three row actions, right-click menu
 *   PaginationBar     page + rows-per-page
 *   StateView         empty / no-results / error, instead of the table
 *   LoadingOverlay    first load only
 *
 * WHAT THE PORT CHANGES ON PURPOSE
 *
 * 1. The stock cell's low-stock colour actually works. pos computes it with
 *    `float(row["stock"])` on the *formatted* row, where stock is already
 *    "12 pcs" — that raises ValueError into a bare `except: pass`, so the tone
 *    is silently dead for every product that has a unit, which is all of them.
 *    Here the controller sends a `low_stock` boolean computed from the raw
 *    numbers and the column only reads it. No parsing of display text.
 *
 * 2. An empty *category* is a no-results state, not a first-run one. pos tests
 *    `total == 0 and not self._search` and forgets the category filter, so
 *    filtering to a category with nothing in it offers "Add your first product"
 *    to a shop with a thousand of them.
 *
 * 3. The low-stock card is red only when the count is above zero. pos tones it
 *    danger unconditionally, and a red "0" is a false alarm on the one screen
 *    that should be calm.
 *
 * 4. Refreshing over existing rows shows a small ring in the filter bar instead
 *    of the blocking overlay. pos decides this from a `reason` string passed
 *    into refresh(); here it is `busy && table.count === 0`, which is the same
 *    intent read off the actual state rather than off the call site.
 *
 * THE BRIDGE IS OPTIONAL
 *
 * Every `app.*` read is guarded, so this page loads and lays out with no Python
 * behind it — empty table, em-dash KPIs, first-run state. That is what makes it
 * reviewable now, and it is the same guard LoginPage and Strings already use.
 */
Item {
    id: root

    // =====================================================================
    // BRIDGE
    // =====================================================================
    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.products : null
    readonly property var session: (typeof app !== "undefined" && app) ? app.session : null
    readonly property var workflows: (typeof app !== "undefined" && app) ? app.workflows : null

    // =====================================================================
    // QUERY STATE
    // =====================================================================
    /* The page owns the query and the controller answers it — pos's split
       exactly (_search / _page / _category_id live on the page there too). It
       matters for a reason beyond symmetry: a reload after an edit has to repeat
       the *same* query, and that is only possible if something remembers it. */
    property string search: ""

    /* 0 is "all categories". An int property cannot hold pos's None, and a
       sentinel that is also a falsy number reads naturally in every test below. */
    property int categoryId: 0

    property int currentPage: 1
    property int pageSize: 100

    // =====================================================================
    // DERIVED
    // =====================================================================
    readonly property bool busy: ctrl ? ctrl.busy : false
    readonly property string errorText: ctrl ? ctrl.error : ""
    readonly property int total: ctrl ? ctrl.total : 0
    readonly property var stats: ctrl ? ctrl.stats : null

    readonly property bool hasFilter: search !== "" || categoryId > 0
    readonly property bool canManage: session ? session.can("products.manage") : false

    /* The state matrix, as one expression instead of pos's if/elif chain over
       three setCurrentWidget calls. An error outranks emptiness: "could not
       load" and "nothing here" are different sentences and the operator needs
       the true one. */
    readonly property bool showState: !busy && (errorText !== "" || total === 0)
    readonly property string stateVariant: errorText !== "" ? "error"
                                         : hasFilter ? "no_results" : "empty"

    // =====================================================================
    // COLUMNS
    // =====================================================================
    /*
     * Widths are pos's at this app's 1.5x geometry scale (170/120/150/120/100 ->
     * 255/180/225/180/150). They are floors, not ceilings — Columns.distribute
     * hands out the surplus — so the only thing they fix is the ratio between
     * columns and the point at which the table starts to scroll.
     *
     * These are bindings, not constants: every header calls Strings.t(), which
     * reads Strings.map, so switching language re-evaluates the array and the
     * headers retranslate on their own. pos has to mutate its frozen Column
     * dataclasses through object.__setattr__ and emit headerDataChanged by hand
     * to achieve the same thing; there is nothing to port because the binding
     * already is the mechanism.
     */
    readonly property var tableColumns: [
        {
            key: "name",
            header: Strings.t("products.col.name", "Product"),
            stretch: true
        },
        {
            /* 13 digits that must never elide, and must never reverse: `ltr`
               makes DataTable prefix U+200E so the barcode reads in entry order
               inside an Arabic row. */
            key: "barcode",
            header: Strings.t("products.col.barcode", "Barcode"),
            width: 255,
            ltr: true
        },
        {
            key: "category",
            header: Strings.t("products.col.category", "Category"),
            width: 180
        },
        {
            key: "purchase_price",
            header: Strings.t("products.col.purchase_price", "Cost"),
            numeric: true,
            width: 225
        },
        {
            key: "sale_price",
            header: Strings.t("products.col.sale_price", "Price"),
            numeric: true,
            width: 180
        },
        {
            key: "stock",
            header: Strings.t("products.col.stock", "Stock"),
            numeric: true,
            width: 150,
            /* The fix described at the top of the file: a flag from the
               controller, compared against nothing. */
            tone: function (row) {
                return row && row.low_stock ? "warning" : ""
            }
        },
        {
            key: "actions",
            actions: root.rowActions
        }
    ]

    /* pos's _ACTIONS, minus the eye.
     *
     * There used to be four icons and the first two opened the same product — an
     * eye for the read-only panel, a pencil for the editor the panel's own primary
     * button led to. The record is one screen now, so `edit` is how it is opened and
     * it is not gated on the manage right: `products.view` is what opened the page
     * and it is enough to look, while the dialog gates its own Save. The two that
     * write from the row still dim for an operator who may not.
     *
     * A binding, so signing in as someone else re-gates the icons without the page
     * being reloaded. Gated actions dim rather than disappear, which is pos's
     * behaviour and the right one: the row keeps its shape for every operator. */
    readonly property var rowActions: [
        { id: "edit" },
        { id: "adjust", enabled: root.canManage },
        { id: "delete", enabled: root.canManage }
    ]

    // =====================================================================
    // CATEGORY FILTER MODEL
    // =====================================================================
    /* "All categories" first, then whatever the controller loaded. Rebuilt on a
       language change too, because the first entry is a translated string —
       which is exactly why the combo restores its index in onModelChanged
       below. */
    readonly property var categoryModel: {
        var out = [{
            id: 0,
            name: Strings.t("products.filter.all_categories", "All categories")
        }]
        var src = ctrl ? ctrl.categories : null
        if (src)
            for (var i = 0; i < src.length; i++)
                out.push({ id: src[i].id, name: src[i].name })
        return out
    }

    function indexOfCategory(id) {
        var m = categoryModel
        for (var i = 0; i < m.length; i++)
            if (m[i].id === id)
                return i
        return 0
    }

    // =====================================================================
    // DATA
    // =====================================================================
    function reload() {
        if (ctrl)
            ctrl.load(root.search, root.currentPage, root.pageSize, root.categoryId)
    }

    /* Any change to *what* is being filtered goes back to page 1. Staying on
       page 7 of a filter that now matches four rows shows an empty page and no
       explanation. */
    function refilter() {
        currentPage = 1
        reload()
    }

    function rowAt(index) {
        return (ctrl && index >= 0 && index < total) ? ctrl.rowAt(index) : null
    }

    /* Take the field's current text as the query. Called by the debounce, and
       directly on Enter — a barcode scanner types its burst and sends Enter
       faster than 300ms, so without the flush the table would lag behind the
       scan by the full interval on every single item. */
    function flushSearch() {
        debounce.stop()
        search = filters.searchText
        refilter()
    }

    function statText(key) {
        var value = stats ? stats[key] : undefined
        return (value === undefined || value === null || value === "") ? "—" : "" + value
    }

    function statNumber(key) {
        var value = stats ? stats[key] : undefined
        return typeof value === "number" ? value : 0
    }

    // =====================================================================
    // ACTIONS
    // =====================================================================
    /*
     * Every "open something else" goes through one funnel.
     *
     * The forms and dialogs this page opens — the product record, the stock
     * adjustment, import/export, the category and unit managers — are not all
     * pages: pos has some as dialogs and some as routed screens. Routing them is
     * the bridge's job (app.workflows), so the page states the intent and nothing
     * more.
     *
     * When the target does not exist the operator is told. A button that does
     * nothing at all is indistinguishable from a broken one.
     */
    function requestOpen(key, context) {
        if (workflows && workflows.open) {
            workflows.open(key, context || ({}))
            return
        }
        notify(Strings.t("workflow.not_ready",
                         "That screen is not part of this build yet."),
               Severity.info)
    }

    function handleAction(row, action) {
        var data = rowAt(row)
        if (!data)
            return

        switch (action) {
        case "edit":
            requestOpen("product_form", { product_id: data.id })
            break
        case "adjust":
            requestOpen("stock_adjust", { product_id: data.id })
            break
        case "delete":
            confirmDelete.productId = data.id
            confirmDelete.productName = data.name || ""
            confirmDelete.open()
            break
        }
    }

    /*
     * Is this string nothing but digits, and long enough to be a barcode?
     *
     * Written as a code-point test rather than a regex on purpose. The three
     * digit sets a keypad in this market can produce are ASCII, Arabic-Indic and
     * Eastern Arabic-Indic, and a character class spelling those out puts
     * ٠-٩ and ۰-۹ into the source — two ranges that are invisible in a diff and
     * indistinguishable from each other in most editors. Naming the code points
     * says which is which, and needs nothing from the regex engine.
     */
    function isDigitsOnly(code) {
        if (code.length < 4)
            return false
        for (var i = 0; i < code.length; i++) {
            var c = code.charCodeAt(i)
            var ascii = c >= 0x30 && c <= 0x39     // 0-9
            var arabic = c >= 0x0660 && c <= 0x0669 // Arabic-Indic
            var eastern = c >= 0x06F0 && c <= 0x06F9 // Eastern Arabic-Indic
            if (!ascii && !arabic && !eastern)
                return false
        }
        return true
    }

    /*
     * Enter on a digit-only code that matches nothing: offer to create it.
     *
     * pos's _on_search_return, with the two blocking DB calls moved off the GUI
     * thread — the controller answers on barcodeProbed below. The digit test
     * stays here because it decides whether to ask at all, and it accepts
     * Arabic-Indic digits: an operator typing on an Arabic keypad produces ٠-٩,
     * and pos normalises those in Python *after* an ASCII-only `isdigit()` test
     * that has already rejected them.
     */
    function probeBarcode() {
        var code = filters.searchText.trim()
        if (!isDigitsOnly(code))
            return
        if (ctrl && ctrl.probeBarcode)
            ctrl.probeBarcode(code)
    }

    function notify(message, severity) {
        toast.show(message, severity)
    }

    // =====================================================================
    // LIFECYCLE
    // =====================================================================
    /* PageHost builds a page fresh on every navigation and throws it away on
       leaving, so creation *is* pos's activate() and there is no deactivate to
       write. The categories load once because that is once per visit here. */
    Component.onCompleted: {
        if (ctrl && ctrl.loadCategories)
            ctrl.loadCategories()
        reload()
    }

    Connections {
        target: root.ctrl

        /* exists -> the filter already shows it. matchTotal -> the filter still
           matches something. Neither is a reason to interrupt. */
        function onBarcodeProbed(code, exists, matchTotal) {
            if (!exists && matchTotal === 0)
                root.requestOpen("product_form", { barcode: code })
        }

        /* A write landed — a delete, a favourite, a visibility toggle, or an edit
           in a form that has since closed. Repeat the same query rather than
           resetting it: an operator who deleted row 40 of page 3 stays on page 3.

           Named `invalidated` rather than `changed` because the controller also
           carries properties, and every property already generates its own
           `<name>Changed`; a bare `changed()` alongside them reads like one of
           those and is the kind of name that gets connected to by accident. */
        function onInvalidated() {
            root.reload()
        }
    }

    /*
     * Search debounce.
     *
     * 300ms is pos's interval. It reads the field at fire time rather than
     * carrying the text through the timer, so a burst of keystrokes collapses to
     * one query for the final text and never for an intermediate one.
     */
    Timer {
        id: debounce
        interval: 300
        onTriggered: root.flushSearch()
    }

    // =====================================================================
    // LAYOUT
    // =====================================================================
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.size.pagePadding
        spacing: Tokens.spacing.lg

        PageHeader {
            Layout.fillWidth: true
            title: Strings.t("products.title", "Products")
            description: Strings.t("products.description",
                                   "Your catalogue, stock levels and prices.")

            /*
             * FLAT, NOT AN OVERFLOW MENU.
             *
             * Six of these used to live behind a "More" button — categories, units,
             * multi-units, barcode labels, import, export — and one thing that did
             * not belong on this page at all had a top-level button of its own
             * ("Arrange", which orders the *till's* tiles; it is on the till now).
             * So the page hid the six things that are about the catalogue and
             * promoted the one thing that is not.
             *
             * They are all here now, and the row still fits a 1366px screen because
             * the labels are spent where the word is doing work: on the three that
             * open a manager an owner goes looking for by name. Import and export
             * are a pair of conventional arrows with tooltips — occasional, and
             * unmistakable as a pair.
             *
             * `products.multi_units` is not here: the product record owns its own
             * packs now, so a second global editor for them would be two doors to
             * one field.
             */
            actionItems: [
                GlyphButton {
                    glyph: "ic_fluent_add_20_regular"
                    text: Strings.t("products.add", "Add product")
                    /* The one accent button on the page. `highlighted` is the
                       style's own primary treatment, so it tracks the brand
                       accent run.py installs. */
                    highlighted: true
                    enabled: root.canManage
                    onClicked: root.requestOpen("product_form", {})
                },
                GlyphButton {
                    glyph: "ic_fluent_folder_20_regular"
                    text: Strings.t("products.manage_categories", "Categories")
                    onClicked: root.requestOpen("categories", {})
                },
                GlyphButton {
                    glyph: "ic_fluent_ruler_20_regular"
                    text: Strings.t("units.title", "Units")
                    onClicked: root.requestOpen("units", {})
                },
                GlyphButton {
                    glyph: "ic_fluent_barcode_scanner_20_regular"
                    text: Strings.t("products.hdr.barcode", "Barcode labels")
                    /* Opened on what the page is currently showing — the category
                       filter and the search text — so "label this shelf" is the
                       filter the operator already set plus one click. The sheet
                       builds its own queue from there; DataTable has no row
                       selection, and inventing one for this would be a second
                       selection model on a page that does not otherwise have one. */
                    onClicked: root.requestOpen("barcode_labels",
                                                { category_id: root.categoryId,
                                                  search: root.search })
                },
                GlyphButton {
                    glyph: "ic_fluent_clipboard_task_20_regular"
                    text: Strings.t("count.title", "Stocktake")
                    /* Its own button rather than a row action: a stocktake is a
                       document over many products, so it belongs to the page, not
                       to a line on it. */
                    enabled: root.canManage
                    onClicked: root.requestOpen("stock_count", {})
                },
                IconButton {
                    glyph: "ic_fluent_history_20_regular"
                    glyphSize: Tokens.icon.md
                    tooltip: Strings.t("stock.ledger", "Stock ledger")
                    onClicked: root.requestOpen("stock_ledger", {})
                },
                IconButton {
                    glyph: "ic_fluent_arrow_import_20_regular"
                    glyphSize: Tokens.icon.md
                    tooltip: Strings.t("import.title", "Import")
                    enabled: root.canManage
                    onClicked: root.requestOpen("products_import", {})
                },
                IconButton {
                    glyph: "ic_fluent_arrow_export_20_regular"
                    glyphSize: Tokens.icon.md
                    tooltip: Strings.t("reports.export", "Export")
                    onClicked: root.requestOpen("products_export", {})
                }
            ]
        }

        CardRow {
            Layout.fillWidth: true

            KpiCard {
                label: Strings.t("products.card.count", "Products")
                value: root.statText("product_count")
                glyph: "ic_fluent_box_multiple_20_regular"
                tone: "info"
            }

            KpiCard {
                label: Strings.t("products.card.value", "Stock value")
                value: root.statText("inventory_value")
                /* pos pairs the abbreviated figure with the exact one in a
                   tooltip; the controller sends both because only Python has
                   the locale and the currency. */
                valueTooltip: root.statText("inventory_value_full")
                glyph: "ic_fluent_money_20_regular"
                tone: "primary"
            }

            KpiCard {
                label: Strings.t("products.card.low_stock", "Low stock")
                value: root.statText("low_stock")
                glyph: "ic_fluent_warning_20_regular"
                /* Red only when there is something to be red about — see the
                   header. */
                tone: root.statNumber("low_stock_raw") > 0 ? "danger" : "success"
            }

            KpiCard {
                label: Strings.t("products.card.categories", "Categories")
                value: root.statText("categories")
                glyph: "ic_fluent_tag_multiple_20_regular"
                tone: "info"
            }
        }

        FilterBar {
            id: filters
            Layout.fillWidth: true
            placeholder: Strings.t("products.search.ph",
                                   "Search by name, barcode or reference")

            onSearchTextChanged: debounce.restart()
            onAccepted: {
                /* Enter means "now". Flush first so the table matches the field,
                   then ask whether this looks like an unknown barcode. */
                root.flushSearch()
                root.probeBarcode()
            }

            filterItems: [
                QC.ComboBox {
                    id: categoryBox
                    /* pos's 180px minimum at this scale. Wide enough for a real
                       category name rather than an ellipsis. */
                    width: 270
                    textRole: "name"
                    valueRole: "id"
                    model: root.categoryModel

                    /* currentIndex is deliberately unbound.
                     *
                     * ComboBox assigns to it internally when the operator picks
                     * an entry, and that assignment destroys a QML binding —
                     * after the first selection a bound index would be frozen at
                     * whatever it was. So the index is set explicitly, in the
                     * two places it can change:
                     *
                     *   onActivated     the operator chose (user gesture only,
                     *                   which is pos's blockSignals in one word)
                     *   onModelChanged  the list was rebuilt — by categories
                     *                   arriving, or by a language change
                     *                   retranslating "All categories". Without
                     *                   this the combo would snap back to "All"
                     *                   while categoryId still held the filter,
                     *                   and the table would disagree with the
                     *                   control that set it.
                     */
                    /* currentValue, not model[index].id: that is what valueRole
                       is for, and `activated` fires after currentIndex has moved
                       so it already reports the new entry. */
                    onActivated: {
                        root.categoryId = currentValue
                        root.refilter()
                    }
                    onModelChanged: currentIndex = root.indexOfCategory(root.categoryId)
                    Component.onCompleted: currentIndex = root.indexOfCategory(root.categoryId)
                }
            ]

            actionItems: [
                /* A refresh over rows that are already on screen. The blocking
                   overlay is for the first load only; this is the same
                   information without taking the table away.
                   No `running` property is set: ProgressRing derives from
                   ProgressBar, which has none, and assigning a property a type
                   does not have is a load-time error that takes the page with
                   it. `indeterminate` is what gates its animations. */
                ProgressRing {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.busy && table.count > 0
                    indeterminate: true
                    ringSize: 28
                    strokeWidth: 3
                }
            ]
        }

        // -----------------------------------------------------------------
        // BODY: the table, or the reason there isn't one
        // -----------------------------------------------------------------
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            /* The table's surface. DataTable draws rows, a header and dividers
               but no frame of its own, which is right — a table inside a card on
               one page and flush to the edge on another is the same table.
               No `clip`: a rounded Rectangle clips to its bounding box, not its
               corners, so clipping here would buy nothing and cost a layer. The
               ListView inside already clips its own content. */
            Rectangle {
                anchors.fill: parent
                visible: !root.showState
                color: Fluent.cardBackground
                radius: Tokens.radius.lg
                border.width: 1
                border.color: Fluent.dividerBorder

                ColumnLayout {
                    anchors.fill: parent
                    /*
                     * Inset, not the 1px that would merely clear the border.
                     *
                     * DataTable's header is a full-width Rectangle with square
                     * corners, and a rounded Rectangle clips to its bounding box
                     * rather than its corner arcs — so a header flush to the edge
                     * would show two small square nubs poking out of the card's
                     * top corners, faint in light and obvious in dark. There is
                     * no cheap rounded clip to reach for and per-corner radii are
                     * Qt 6.7+, so the fix is geometric: at a 16px radius the arc
                     * is only half a pixel outside a 12px inset, which is nothing.
                     *
                     * It also happens to be what a card should look like. The
                     * rows stopping short of the edge is padding, not a
                     * workaround — but the reason it cannot be reduced is.
                     */
                    anchors.margins: Tokens.spacing.sm
                    spacing: 0

                    DataTable {
                        id: table
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        model: root.ctrl ? root.ctrl.rows : null
                        columns: root.tableColumns

                        onRowActivated: (row) => root.handleAction(row, "edit")
                        onActionTriggered: (row, action) => root.handleAction(row, action)
                        onRowContextRequested: (row) => {
                            rowMenu.rowData = root.rowAt(row)
                            if (rowMenu.rowData)
                                rowMenu.popup()
                        }
                    }

                    PaginationBar {
                        Layout.fillWidth: true
                        page: root.currentPage
                        total: root.total
                        pageSize: root.pageSize

                        /* `requested`, not `page`: a handler parameter named
                           after the property it sets would shadow PaginationBar's
                           own `page` inside this scope, which reads as a
                           self-assignment and is one rename away from being
                           one. */
                        onPageRequested: (requested) => {
                            root.currentPage = requested
                            root.reload()
                        }
                        onPageSizeRequested: (requested) => {
                            root.pageSize = requested
                            root.refilter()
                        }
                    }
                }
            }

            StateView {
                anchors.fill: parent
                visible: root.showState
                variant: root.stateVariant

                /* pos passes a body only for the first-run case and lets the
                   variant speak for itself otherwise. The error state shows what
                   actually went wrong rather than a generic apology. */
                body: root.stateVariant === "error"
                      ? root.errorText
                      : root.stateVariant === "empty"
                        ? Strings.t("products.empty.body",
                                    "Add your first product to start selling.")
                        : ""

                actionText: root.stateVariant === "empty" && root.canManage
                            ? Strings.t("products.add", "Add product")
                            : ""

                onActionRequested: root.requestOpen("product_form", {})
                onRetryRequested: root.reload()
            }
        }
    }

    // =====================================================================
    // OVERLAY
    // =====================================================================
    /* First load only — there are no rows to protect otherwise, and blanking a
       table the operator is reading in order to tell them it is being reread is
       the wrong trade. Declared after the layout so it stacks above it. */
    LoadingOverlay {
        visible: root.busy && table.count === 0
    }

    // =====================================================================
    // MENUS
    // =====================================================================
    /*
     * The row menu — pos's _row_menu. It carries the two toggles the action
     * icons have no room for, which is the whole reason a right-click menu earns
     * its place next to a three-icon action column.
     *
     * `rowData` is captured when the menu opens rather than read from the
     * current row while it is open: a reload can arrive in between, and an
     * operator who right-clicked one product must not have their click land on
     * whatever moved into that position.
     */
    QC.Menu {
        id: rowMenu
        property var rowData: null

        readonly property int rowId: rowData ? rowData.id : 0
        readonly property string rowName: rowData && rowData.name ? rowData.name : ""
        readonly property bool isFavorite: rowData ? rowData.is_favorite === true : false
        readonly property bool onPos: rowData ? rowData.show_on_pos !== false : true

        QC.MenuItem {
            text: Strings.t("action.open", "Open")
            onTriggered: root.requestOpen("product_form", { product_id: rowMenu.rowId })
        }
        QC.MenuItem {
            /* This product's own ledger — why its stock is what it is. The one
               question a stock figure provokes, and until now unanswerable. */
            text: Strings.t("stock.ledger", "Stock ledger")
            onTriggered: root.requestOpen("stock_ledger",
                                          { product_id: rowMenu.rowId,
                                            product_name: rowMenu.rowName })
        }
        QC.MenuItem {
            text: Strings.t("products.actions.adjust", "Adjust stock")
            enabled: root.canManage
            onTriggered: root.requestOpen("stock_adjust", { product_id: rowMenu.rowId })
        }

        QC.MenuSeparator {}

        QC.MenuItem {
            text: rowMenu.isFavorite
                  ? Strings.t("products.remove_favorite", "Remove from favourites")
                  : Strings.t("products.add_favorite", "Add to favourites")
            enabled: root.canManage
            onTriggered: {
                if (root.ctrl)
                    root.ctrl.setFavorite(rowMenu.rowId, !rowMenu.isFavorite)
            }
        }
        QC.MenuItem {
            text: rowMenu.onPos
                  ? Strings.t("products.hide_pos", "Hide from the till")
                  : Strings.t("products.show_pos", "Show on the till")
            enabled: root.canManage
            onTriggered: {
                if (root.ctrl)
                    root.ctrl.setVisibility(rowMenu.rowId, !rowMenu.onPos)
            }
        }

        QC.MenuSeparator {}

        QC.MenuItem {
            text: Strings.t("action.delete", "Delete")
            enabled: root.canManage
            onTriggered: {
                confirmDelete.productId = rowMenu.rowId
                confirmDelete.productName = rowMenu.rowData
                                            ? (rowMenu.rowData.name || "") : ""
                confirmDelete.open()
            }
        }
    }

    // =====================================================================
    // CONFIRM
    // =====================================================================
    FluentDialog {
        id: confirmDelete

        property int productId: 0
        property string productName: ""

        /*
         * The text measure, as a constant.
         *
         * FluentDialog sizes itself from its content —
         * `implicitWidth: max(480, min(implicitContentWidth + padding, 900))` —
         * so a wrapping Text inside it must not take its width from the dialog.
         * `width: parent.width` would run implicitContentWidth -> dialog width ->
         * content width -> implicitContentWidth and close a binding loop, which
         * QML reports once and then leaves the layout wrong.
         *
         * Stating the measure instead breaks the cycle in the one direction that
         * matters, and 420 is a deliberate number rather than a fallout: it is a
         * comfortable line length for two short sentences, and it lands the
         * dialog at 492 — just past the 480 floor, so the frame is sized by this
         * text rather than by the minimum.
         */
        readonly property int measure: 420

        modal: true
        title: Strings.t("confirm.delete_product.title", "Delete this product?")
        standardButtons: QC.Dialog.Yes | QC.Dialog.No

        onAccepted: if (root.ctrl) root.ctrl.remove(productId)

        /* The name on its own line rather than interpolated into the question:
           a product called "500 g" inside a sentence is ambiguous, and on its
           own line it is not. It also means the catalogue string needs no
           placeholder and cannot be mis-formatted by a translation. */
        contentItem: Column {
            spacing: Tokens.spacing.sm

            Text {
                width: confirmDelete.measure
                text: Strings.t("confirm.delete_product.body",
                                "This cannot be undone.")
                wrapMode: Text.WordWrap
                color: Fluent.textPrimary
                font.pixelSize: Tokens.font.body
            }

            Text {
                width: confirmDelete.measure
                text: confirmDelete.productName
                visible: text !== ""
                wrapMode: Text.WordWrap
                color: Fluent.textPrimary
                font.pixelSize: Tokens.font.body
                font.weight: Font.DemiBold
            }
        }
    }

    // =====================================================================
    // FEEDBACK
    // =====================================================================
    /* A host, not a Toast: FluentControls' Toast destroys itself at the end of
       its exit animation — it is built to be created per message — so a Toast
       declared here once would work exactly until the first dismissal and then
       every later message would be written to a destroyed object. ToastHost
       creates one per message and positions it. */
    ToastHost {
        id: toast
        bottomMargin: Tokens.size.pagePadding
    }
}

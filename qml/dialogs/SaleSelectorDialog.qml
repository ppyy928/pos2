import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * Find a sale. Ported from pos/app/dialogs/selectors.py::SaleSelectorDialog,
 * which the till opens on F1 to start a return.
 *
 *   ┌──────────────────────────────────────────────────────────────────────────────┐
 *   │ Select a sale to return                                                      │
 *   │ [ number, customer, or a product on it ] [👤 Any customer] [From] [To] [⟲]   │
 *   │ ┌───────────────────────────────────┬──────────────────────────────────────┐ │
 *   │ │ TRX-0183  30/08 01:49  Azizi  ... │ TRX-0183 · 30/08/2026 01:49          │ │
 *   │ │ TRX-0182  29/08 16:45  Walk-in    │ Atlas Beans   2   250.00   500.00    │ │
 *   │ │ TRX-0181  28/08 11:42  Walk-in    │ Atlas Rice    1    80.00    80.00 ¹  │ │
 *   │ └───────────────────────────────────┴──────────────────────────────────────┘ │
 *   │                                                    [ Cancel ] [ Select ]     │
 *   └──────────────────────────────────────────────────────────────────────────────┘
 *
 * WHY TWO TABLES
 *
 * A sale is identified by what was in it. The number is a reference nobody memorises,
 * the timestamp narrows to a day at best, and "Walk-in" identifies nothing at all —
 * so with one list the operator picks a row, loses the dialog to the return screen,
 * finds it is the wrong ticket, and starts again. The right-hand table answers "is
 * this the one?" before the pick is committed: the lines, their quantities, and how
 * much of each has already been returned.
 *
 * It also makes the product search legible. Searching "cola" narrows the left list to
 * every ticket with a cola on it; the pane on the right is where you see WHICH cola
 * and how many, which is the actual question behind the search.
 *
 * WHY IT IS THIS WIDE
 *
 * Five columns of sale plus five of line do not fit in a dialog sized for a
 * confirmation. `preferredWidth` asks for a desktop's worth and `AppDialog` caps it
 * at the window, so on a 1366 till it is the window minus its breathing margin and on
 * a wide screen it stops growing at 1760 — past that the two tables are just further
 * apart.
 *
 * THE FILTERS
 *
 * Search is words, and every word must match something (see `db.fetch_sales`). The
 * customer filter is the party, not a name that resembles it, because two customers
 * called Ahmed are two accounts. The dates are a closed range on the sale's own
 * timestamp, either end optional. Nothing here is applied on a timer: the search box
 * debounces (a scanner's burst is not four queries), and every other control queries
 * on the change, because a filter that waits is a filter the operator presses twice.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.sales : null
    readonly property var workflows: (typeof app !== "undefined" && app)
                                     ? app.workflows : null
    readonly property string purpose: context && context.purpose ? context.purpose : ""

    /* Wide, and as wide as the window when the window is narrower than this. */
    preferredWidth: 1760
    preferredHeight: 880

    modal: true
    closePolicy: QC.Popup.CloseOnEscape

    title: purpose === "return"
           ? Strings.t("return.select_sale", "Select a sale to return")
           : Strings.t("sales.title", "Sales")

    // =====================================================================
    // STATE
    // =====================================================================
    /* The filters, held here so `reload()` is the one place that sends them. */
    property string query: ""
    property int customerId: 0
    property string customerName: ""
    property string dateFrom: ""
    property string dateTo: ""

    readonly property bool filtered: query !== "" || customerId !== 0
                                     || dateFrom !== "" || dateTo !== ""

    /* The sale under the cursor on the left, and its lines. `lines` is loaded per
       selection rather than with the list: a page of 100 sales is 100 line queries
       nobody asked for, and the operator reads one at a time. */
    property var lines: []
    property var picked: null

    readonly property int pageSize: 100

    // =====================================================================
    // BEHAVIOUR
    // =====================================================================
    function reload() {
        if (!ctrl)
            return
        ctrl.load(query, "", 1, pageSize, dateFrom, dateTo, customerId)
        /* The list is about to be replaced, so nothing is selected: keeping the row
           index would point at a different sale. */
        salesTable.currentRow = -1
        picked = null
        lines = []
    }

    function showLines(row) {
        var summary = ctrl ? ctrl.rowAt(row) : null
        picked = summary
        if (!summary || !ctrl) {
            lines = []
            return
        }
        var sale = ctrl.sale(summary.id)
        lines = sale && sale.items ? sale.items : []
    }

    function choose(index) {
        var row = ctrl ? ctrl.rowAt(index) : null
        if (!row)
            return
        if (workflows)
            workflows.open(purpose === "return" ? "return_create" : "sale_transaction",
                           { sale_id: row.id })
        dialog.close()
    }

    function submit() {
        /* Enter on a search that narrowed to one is the whole point of typing. */
        if (ctrl && ctrl.rows.length === 1)
            choose(0)
        else if (salesTable.currentRow >= 0)
            choose(salesTable.currentRow)
    }

    function clearFilters() {
        query = ""
        customerId = 0
        customerName = ""
        dateFrom = ""
        dateTo = ""
        searchField.text = ""
        fromField.value = ""
        toField.value = ""
        reload()
    }

    Component.onCompleted: {
        reload()
        searchField.forceActiveFocus()
    }

    /* A scanner types a barcode in one burst and a person types a name in several
       keystrokes; both arrive here as onTextChanged. 250ms turns either into one
       query. */
    Timer {
        id: debounce
        interval: 250
        onTriggered: {
            dialog.query = searchField.text.trim()
            dialog.reload()
        }
    }

    // =====================================================================
    // COLUMNS
    // =====================================================================
    readonly property var saleColumns: [
        {
            key: "number",
            header: Strings.t("sales.col.number", "Number"),
            width: 150,
            ltr: true
        },
        {
            key: "when",
            header: Strings.t("sales.col.time", "Date"),
            width: 190,
            ltr: true
        },
        {
            key: "customer",
            header: Strings.t("sales.col.customer", "Customer"),
            stretch: true
        },
        {
            key: "payment",
            header: Strings.t("sales.col.payment", "Payment"),
            width: 130,
            badge: true,
            tone: function (r) {
                return r.payment_type === "cash" ? "success"
                     : r.payment_type === "debt" ? "danger"
                     : r.payment_type === "partial" ? "warning" : ""
            }
        },
        {
            key: "total",
            header: Strings.t("sales.col.total", "Total"),
            numeric: true,
            width: 160,
            ltr: true
        }
    ]

    readonly property var lineColumns: [
        {
            key: "name",
            header: Strings.t("sales.col.product", "Product"),
            stretch: true
        },
        {
            key: "qty_text",
            header: Strings.t("purchases.col.qty", "Qty"),
            numeric: true,
            width: 110,
            ltr: true
        },
        {
            key: "price_text",
            header: Strings.t("sales.col.price", "Unit price"),
            numeric: true,
            width: 150,
            ltr: true
        },
        {
            key: "total_text",
            header: Strings.t("sales.col.total", "Total"),
            numeric: true,
            width: 150,
            ltr: true
        },
        {
            /* What has already gone back. A line that is fully returned is why an
               operator opens the wrong ticket twice, so it is on the row and toned:
               anything above zero is the reason to look twice. */
            key: "returned_text",
            header: Strings.t("sales.col.returned", "Returned"),
            numeric: true,
            width: 130,
            ltr: true,
            tone: function (r) { return r.returned > 0 ? "warning" : "" }
        }
    ]

    /* The lines come from the bridge with everything formatted except this one: the
       return figure is a quantity the bridge reports as a number. */
    readonly property var lineRows: {
        var out = []
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i]
            out.push({
                name: line.name,
                qty_text: line.qty_text,
                price_text: line.price_text,
                total_text: line.total_text,
                returned: line.returned,
                returned_text: line.returned > 0 ? "\u200e" + line.returned : "—"
            })
        }
        return out
    }

    // =====================================================================
    // LAYOUT
    // =====================================================================
    contentItem: ColumnLayout {
        spacing: Tokens.spacing.md

        // -----------------------------------------------------------------
        // THE FILTERS
        // -----------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.sm

            QC.TextField {
                id: searchField
                Layout.fillWidth: true
                Layout.minimumWidth: 320
                Layout.preferredHeight: Tokens.size.control
                placeholderText: Strings.t("sales.search.smart.ph",
                                           "Number, customer, or a product on the sale")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body

                onTextChanged: debounce.restart()
                /* Enter is "I mean it now", so it does not wait for the timer. */
                onAccepted: {
                    debounce.stop()
                    dialog.query = text.trim()
                    dialog.reload()
                    dialog.submit()
                }

                QC.ToolTip.text: Strings.t("sales.search.smart.hint",
                                           "Every word has to match something.")
                QC.ToolTip.visible: hovered
                QC.ToolTip.delay: 700
            }

            /* The customer, as a record. A combo box of 121 names is a scroll, so this
               is the same searchable picker the counter uses — told not to touch the
               cart, because narrowing a list is not attaching a customer to a sale. */
            GlyphButton {
                glyph: "ic_fluent_person_20_regular"
                outlined: dialog.customerId === 0
                text: dialog.customerId === 0
                      ? Strings.t("sales.filter.customer", "Any customer")
                      : dialog.customerName
                onClicked: customerPicker.open()
            }

            IconButton {
                visible: dialog.customerId !== 0
                glyph: "ic_fluent_dismiss_20_regular"
                glyphSize: Tokens.icon.sm
                tooltip: Strings.t("sales.filter.customer", "Any customer")
                onClicked: {
                    dialog.customerId = 0
                    dialog.customerName = ""
                    dialog.reload()
                }
            }

            Text {
                text: Strings.t("date.from", "From")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.caption
                color: Fluent.textSecondary
            }

            DateField {
                id: fromField
                implicitWidth: 180
                value: dialog.dateFrom
                onEdited: (value) => {
                    dialog.dateFrom = value
                    dialog.reload()
                }
            }

            Text {
                text: Strings.t("date.to", "To")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.caption
                color: Fluent.textSecondary
            }

            DateField {
                id: toField
                implicitWidth: 180
                value: dialog.dateTo
                onEdited: (value) => {
                    dialog.dateTo = value
                    dialog.reload()
                }
            }

            IconButton {
                visible: dialog.filtered
                glyph: "ic_fluent_arrow_counterclockwise_20_regular"
                tooltip: Strings.t("filters.clear", "Clear filters")
                onClicked: dialog.clearFilters()
            }
        }

        // -----------------------------------------------------------------
        // THE TWO TABLES
        // -----------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacing.md

            /* 5:4. The sales list is the one being scanned, so it leads; the lines
               pane needs enough for a product name beside four figures. Both are
               `fillWidth`, so a narrow window shrinks them together instead of
               dropping one off the edge. */
            DataTable {
                id: salesTable
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 5
                columns: dialog.saleColumns
                model: dialog.ctrl ? dialog.ctrl.rows : null
                emptyIcon: "ic_fluent_receipt_20_regular"
                emptyText: dialog.filtered
                           ? Strings.t("state.no_results.title", "No matches")
                           : Strings.t("table.empty", "Nothing to show")

                onCurrentRowChanged: dialog.showLines(currentRow)
                onRowActivated: (row) => dialog.choose(row)
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 4
                spacing: Tokens.spacing.xs

                /* Which sale the pane is showing. Without it the two tables are two
                   lists side by side and nothing says they are related. */
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.sm

                    Text {
                        text: Strings.t("sales.lines.title", "What is on it")
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.overline
                        font.weight: Font.DemiBold
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 0.8
                        color: Fluent.textSecondary
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: dialog.picked !== null
                        text: dialog.picked
                              ? "\u200e" + dialog.picked.number + "  ·  "
                                + dialog.picked.when + "  ·  " + dialog.picked.total
                              : ""
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.caption
                        font.features: Tokens.figures
                        color: Fluent.textPrimary
                        elide: Text.ElideRight
                    }
                }

                DataTable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columns: dialog.lineColumns
                    model: dialog.lineRows
                    emptyIcon: "ic_fluent_list_20_regular"
                    emptyText: Strings.t("sales.lines.hint",
                                         "Pick a sale on the left to see its lines.")
                    /* Double-clicking a line is agreeing to the sale it belongs to:
                       the operator is looking at the goods in front of them. */
                    onRowActivated: (row) => dialog.submit()
                }
            }
        }

        // -----------------------------------------------------------------
        // COMMIT
        // -----------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.sm

            Text {
                visible: dialog.ctrl !== null
                text: dialog.ctrl
                      ? Strings.tf("sales.found", "{count} sales",
                                   { count: dialog.ctrl.total })
                      : ""
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.caption
                color: Fluent.textSecondary
            }

            Item { Layout.fillWidth: true }

            GlyphButton {
                glyph: "ic_fluent_dismiss_20_regular"
                outlined: true
                text: Strings.t("action.cancel", "Cancel")
                onClicked: dialog.close()
            }

            GlyphButton {
                glyph: "ic_fluent_checkmark_20_regular"
                text: Strings.t("select_customer.select", "Select")
                highlighted: true
                enabled: salesTable.currentRow >= 0
                         || (dialog.ctrl && dialog.ctrl.rows.length === 1)
                onClicked: dialog.submit()
            }
        }
    }

    // =====================================================================
    // THE CUSTOMER FILTER'S PICKER
    // =====================================================================
    CustomerPickerDialog {
        id: customerPicker
        attach: false
        onPicked: (customer) => {
            dialog.customerId = customer.id
            dialog.customerName = customer.name
            dialog.reload()
        }
    }
}

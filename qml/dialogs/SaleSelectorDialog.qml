import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * Find a sale. Ported from pos/app/dialogs/selectors.py::SaleSelectorDialog,
 * which the till opens on F1 to start a return.
 *
 *   ┌──────────────────────────────────────────────────────────────────────┐
 *   │ Select a sale to return                                              │
 *   │ [ number, customer, or a product on it                        ✕ ]    │
 *   │ [👤 Any customer      ] [From 📅]      [To 📅]                 ⟲     │
 *   │ NUMBER        DATE            CUSTOMER       PAYMENT  TOTAL   ⟲ret   │
 *   │ TRX-0183  30/08 01:49  Azizi Bouzid       [Partial] 12 480   ↩      │
 *   │ TRX-0182  29/08 16:45  Walk-in            [Cash]    1 980    ↩      │
 *   │                                              2 sales  [Cancel][Select]│
 *   └──────────────────────────────────────────────────────────────────────┘
 *
 * ONE TABLE, AND THE RETURN DIALOG ON TOP OF IT
 *
 * There were two tables: the list, and a preview of the picked row's lines. The
 * preview answered "is this the one?" — but every line it showed reappeared one
 * tap later in the return dialog, beside the stepper that actually takes the
 * goods back, where the question is not "what is on it" but "how much of it is
 * coming back". A pane that can only be looked at is a detour on the way to the
 * screen that can act.
 *
 * So the row carries the act instead: the return icon opens the return dialog
 * ON TOP of this one (DialogHost stacks, it does not swap), the lines arrive in
 * the dialog that can do something with them, and cancelling it drops the
 * operator back on the list — still open, still filtered, still where they left
 * it. That is the wrong-ticket answer the preview used to give, and a better
 * one: the old flow closed this dialog to open the next, so a wrong pick meant
 * starting the search over from a blank screen.
 *
 * When the return lands (`sales.returned`), this dialog closes itself: the
 * Returns page opened it to make one return, and the return is made. Everything
 * in between — Escape, Cancel, a refusal — leaves the list standing.
 *
 * THE RETURN ACTION
 *
 * The icon is RowActions' `return`: arrow-undo, warning tone, the same glyph the
 * sales page's row uses for the same act. Gated on `sales.edit` exactly as the
 * New return button that opened this dialog is. Enter, double-click and the
 * Select button all do what the icon does, because they always did — the icon
 * is the affordance the row was missing, not a second behaviour.
 *
 * THE FILTERS
 *
 * Search is words, and every word must match something (see `db.fetch_sales`). The
 * customer filter is the party, not a name that resembles it, because two customers
 * called Ahmed are two accounts. The dates are a closed range on the sale's own
 * timestamp, either end optional. Nothing here is applied on a timer: the search box
 * debounces (a scanner's burst is not four queries), and every other control queries
 * on the change, because a filter that waits is a filter the operator presses twice.
 *
 * The filters sit directly above the table they narrow, and the three fields of
 * the second row share its whole width in proportion (5:2:2) with minimums, so
 * none of them is ever squeezed to unreadability by the others or stranded
 * beside a dead gap.
 *
 * WHY THE CUSTOMER FIELD IS THE TILL'S OWN CONTROL
 *
 * It was a button that opened a second modal over this one — the third window an
 * operator sat behind while answering one question. `PartySelect` is the same field
 * the counter attaches customers with and the delivery form attaches suppliers
 * with: tap, type, pick, done, without this dialog ever going away. The pick is
 * a local answer here — a filter, not an attachment — so nothing is sent to the cart;
 * the field's contract is the same, only the consequence differs.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.sales : null
    readonly property var customers: (typeof app !== "undefined" && app)
                                     ? app.customers : null
    readonly property var workflows: (typeof app !== "undefined" && app)
                                     ? app.workflows : null
    readonly property var session: (typeof app !== "undefined" && app)
                                   ? app.session : null
    readonly property string purpose: context && context.purpose ? context.purpose : ""

    /* One table's worth. `AppDialog` caps it at the window, so a narrower screen
       takes the window minus its breathing margin. */
    preferredWidth: 1280
    preferredHeight: 820

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
    property string customerPhone: ""
    property string dateFrom: ""
    property string dateTo: ""

    readonly property bool filtered: query !== "" || customerId !== 0
                                     || dateFrom !== "" || dateTo !== ""

    /* The act this dialog exists for, gated exactly as the New return button
       that opened it is gated. `revision` first: `can()` is a slot with no
       notifier, so a binding that only calls it never re-evaluates when
       somebody signs in — SalesPage's own note. */
    readonly property bool canReturn: session && session.revision >= 0
                                      && session.can("sales.edit")

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
    }

    /* Open the return dialog for a row — stacked above this one, which stays
       open. See the header: the list is the place the operator comes back to
       when the ticket is the wrong one, so it must not be destroyed to make
       room for the answer. */
    function choose(index) {
        var row = ctrl ? ctrl.rowAt(index) : null
        if (!row)
            return
        if (workflows)
            workflows.open(purpose === "return" ? "return_create" : "sale_transaction",
                           { sale_id: row.id })
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
        customerPhone = ""
        dateFrom = ""
        dateTo = ""
        filters.clear()
        fromField.value = ""
        toField.value = ""
        reload()
    }

    Component.onCompleted: {
        reload()
        filters.focusSearch()
    }

    /* A scanner types a barcode in one burst and a person types a name in several
       keystrokes; both arrive here as onSearchTextChanged. 250ms turns either into
       one query. */
    Timer {
        id: debounce
        interval: 250
        onTriggered: {
            dialog.query = filters.searchText.trim()
            dialog.reload()
        }
    }

    /* The return being made is this dialog's job done: the Returns page opened
       it for one return, the return exists, and leaving the list standing under
       a finished task is a screen that has to be dismissed for no reason. The
       return dialog closes itself on the same signal, from its own layer on top;
       the two closes pop the stack in whichever order they arrive. */
    Connections {
        target: dialog.ctrl
        ignoreUnknownSignals: true

        function onReturned(result) { dialog.close() }
    }

    // =====================================================================
    // COLUMNS
    // =====================================================================
    readonly property var rowActions: [
        { id: "return", enabled: dialog.canReturn }
    ]

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
        },
        {
            key: "actions",
            actions: dialog.rowActions
        }
    ]

    // =====================================================================
    // LAYOUT
    // =====================================================================
    contentItem: ColumnLayout {
        spacing: Tokens.spacing.md

        FilterBar {
            id: filters

            Layout.fillWidth: true
            placeholder: Strings.t("sales.search.smart.ph",
                                   "Number, customer, or a product on the sale")
            searchTooltip: Strings.t("sales.search.smart.hint",
                                     "Every word has to match something.")

            onSearchTextChanged: debounce.restart()

            /* Enter is "I mean it now", so it does not wait for the timer —
               and a search that narrowed to one sale takes it. */
            onAccepted: {
                debounce.stop()
                dialog.query = filters.searchText.trim()
                dialog.reload()
                dialog.submit()
            }
        }

        /* The rest of the filters: the customer, the range, and the reset.
           Every one of them takes a share of the width rather than a fixed
           slice with a dead spacer after it — a row that ends in a gap is a
           row of squeezed fields on one window and a row of lost space on
           another, and neither says "these all filter the table below". */
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.sm

            /* The customer, as a record — chosen with the till's own control,
               not a button that opens a second window over this one. The
               customer is a filter here, not an attachment, so the pick is
               answered locally and nothing touches the cart. */
            PartySelect {
                id: customerFilter

                Layout.fillWidth: true
                Layout.preferredWidth: 5
                /* A floor, not a preference: the dates below have their own
                   minimum, and whichever of the three is squeezed to nothing
                   by the other two is the one the operator needed. */
                Layout.minimumWidth: 220

                active: dialog.customerId !== 0
                title: dialog.customerId !== 0
                       ? dialog.customerName
                       : Strings.t("sales.filter.customer", "Any customer")
                subtitle: dialog.customerId !== 0
                          ? dialog.customerPhone
                          : Strings.t("sales.filter.customer.hint",
                                      "Tap to filter by customer")
                removeTip: Strings.t("sales.filter.customer", "Any customer")

                rows: dialog.customers ? dialog.customers.rows : []
                placeholder: Strings.t("select_customer.search.ph",
                                       "Search name or phone")
                emptyText: Strings.t("select_customer.no_match",
                                     "No customer matches that.")

                /* Whole list, once, per open: `search("")` is unpaged and the
                   sheet filters it in QML — the same contract the till's field
                   uses. */
                onListRequested: {
                    if (dialog.customers)
                        dialog.customers.search("")
                }
                onPicked: (party) => {
                    dialog.customerId = party.id
                    dialog.customerName = party.name
                    dialog.customerPhone = party.phone !== undefined
                                           ? party.phone : ""
                    dialog.reload()
                }
                onRemoveRequested: {
                    dialog.customerId = 0
                    dialog.customerName = ""
                    dialog.customerPhone = ""
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

                Layout.fillWidth: true
                Layout.preferredWidth: 2
                Layout.minimumWidth: 150
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

                Layout.fillWidth: true
                Layout.preferredWidth: 2
                Layout.minimumWidth: 150
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
        // THE LIST
        // -----------------------------------------------------------------
        DataTable {
            id: salesTable
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: dialog.saleColumns
            model: dialog.ctrl ? dialog.ctrl.rows : null
            emptyIcon: "ic_fluent_receipt_20_regular"
            emptyText: dialog.filtered
                       ? Strings.t("state.no_results.title", "No matches")
                       : Strings.t("table.empty", "Nothing to show")

            /* The icon on the row and the activation of the row are the same
               act — see THE RETURN ACTION above. */
            onActionTriggered: (row, action) => {
                if (action === "return")
                    dialog.choose(row)
            }
            onRowActivated: (row) => dialog.choose(row)
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
}

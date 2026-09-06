import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * Purchases — what came in, from whom, and what is still owed for it. Ported from
 * pos's purchases page over db.fetch_purchase_invoices.
 *
 * The mirror image of Sales: the same three figures (how many, how much, how much
 * outstanding) pointing the other way. Outstanding here is money the shop owes,
 * which is why it is the toned column and the toned card.
 *
 * An invoice can be deleted, unlike a sale, because a mistyped delivery note has
 * to be correctable — but it takes the stock back out and undoes the debt, so it
 * asks first and names the invoice.
 */
Item {
    id: root

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.purchases : null
    readonly property var session: (typeof app !== "undefined" && app) ? app.session : null
    readonly property var printer: (typeof app !== "undefined" && app) ? app.printing : null
    readonly property var workflows: (typeof app !== "undefined" && app)
                                     ? app.workflows : null

    property string search: ""
    property int currentPage: 1
    property int pageSize: 100

    readonly property bool busy: ctrl ? ctrl.busy : false
    readonly property string errorText: ctrl ? ctrl.error : ""
    readonly property int total: ctrl ? ctrl.total : 0
    readonly property var stats: ctrl ? ctrl.stats : null
    readonly property bool canManage: session ? session.can("purchases.manage") : true

    readonly property bool showState: !busy && (errorText !== "" || total === 0)
    readonly property string stateVariant: errorText !== "" ? "error"
                                         : search !== "" ? "no_results" : "empty"

    readonly property var tableColumns: [
        {
            key: "number",
            header: Strings.t("purchases.col.number", "Number"),
            width: 190,
            ltr: true
        },
        {
            key: "when",
            header: Strings.t("purchases.col.time", "Date"),
            width: 240,
            ltr: true
        },
        {
            key: "supplier",
            header: Strings.t("purchases.col.supplier", "Supplier"),
            stretch: true
        },
        {
            key: "total",
            header: Strings.t("purchases.col.total", "Total"),
            numeric: true,
            width: 200
        },
        {
            key: "due",
            header: Strings.t("purchases.col.due", "Outstanding"),
            numeric: true,
            width: 200,
            tone: function (row) { return row.owes ? "danger" : "" }
        },
        {
            key: "actions",
            actions: root.rowActions
        }
    ]

    /* Three icons. The eye used to open the same purchase form with a `readonly`
       flag, which meant the operator who spotted a wrong quantity had to close it
       and press the pencil on the same row to fix it — a mode switch on a screen
       that had nothing to protect. `edit` is not gated either: `purchases.view`
       opened the page and it is enough to read an invoice, while the form gates its
       own Save. Deleting one is still a manage-level act.

       `print` is here because a delivery note is the piece of paper a supplier's
       rep asks for at the counter, and the renderer for it
       (`print_purchase_by_id`) already existed with nothing calling it. */
    readonly property var rowActions: [
        { id: "edit" },
        { id: "print" },
        { id: "delete", enabled: root.canManage }
    ]

    function reload() {
        if (ctrl)
            ctrl.load(search, currentPage, pageSize)
    }

    function applySearch() {
        debounce.stop()
        search = filters.searchText
        currentPage = 1
        reload()
    }

    function handleAction(row, action) {
        var data = ctrl ? ctrl.rowAt(row) : null
        if (!data)
            return
        if (action === "edit")
            requestOpen("purchase_form", { invoice_id: data.id })
        else if (action === "print") {
            if (printer)
                printer.printPurchase(data.id)
        }
        else if (action === "delete")
            askDelete(data.id)
    }

    /* The question, with what it would cost read out of the database first — see the
       confirmation at the bottom of this file for what those two conditions are. */
    function askDelete(invoiceId) {
        if (!ctrl)
            return
        var impact = ctrl.deleteImpact(invoiceId)
        if (!impact)
            return
        confirmDelete.invoiceId = invoiceId
        confirmDelete.impact = impact
        confirmDelete.open()
    }

    function requestOpen(key, context) {
        if (workflows && workflows.open) {
            workflows.open(key, context || ({}))
            return
        }
        notify(Strings.t("workflow.not_ready",
                         "That screen is not part of this build yet."),
               Severity.info)
    }

    function notify(message, severity) {
        toast.show(message, severity)
    }

    function statText(key) {
        if (!stats)
            return "—"
        var value = stats[key]
        return (value === undefined || value === null || value === "") ? "—" : value
    }

    function statNumber(key) {
        if (!stats)
            return 0
        var value = stats[key]
        return typeof value === "number" ? value : 0
    }

    Component.onCompleted: reload()

    Connections {
        target: root.ctrl
        ignoreUnknownSignals: true
        function onInvalidated() { root.reload() }
        function onSaved(invoice) {
            root.notify(Strings.tf("purchases.saved", "Invoice {number} saved",
                                   { number: invoice.number }),
                        Severity.success)
        }
        function onRejected(message) { root.notify(message, Severity.caution) }
    }

    /* The printer answers on its own schedule — it is a device on a pool thread —
       so the toast is wired to it rather than to the click. */
    Connections {
        target: root.printer
        ignoreUnknownSignals: true
        function onPrinted(result) {
            if (result.what === "purchase")
                root.notify(Strings.t("sales.printed", "Sent to the printer"),
                            Severity.success)
        }
        function onPrintFailed(message) { root.notify(message, Severity.caution) }
    }

    Timer {
        id: debounce
        interval: 300
        onTriggered: root.applySearch()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.size.pagePadding
        spacing: Tokens.spacing.lg

        PageHeader {
            Layout.fillWidth: true
            title: Strings.t("nav.purchases", "Purchases")
            description: Strings.t("purchases.description",
                                   "Deliveries received, and what is still owed for them.")

            actionItems: [
                GlyphButton {
                    glyph: "ic_fluent_add_20_regular"
                    text: Strings.t("purchases.new", "New invoice")
                    highlighted: true
                    enabled: root.canManage
                    onClicked: root.requestOpen("purchase_form", {})
                },
                GlyphButton {
                    glyph: "ic_fluent_vehicle_truck_profile_20_regular"
                    text: Strings.t("suppliers.title", "Suppliers")
                    /* The suppliers screen, not a dialog with a second suppliers
                       list inside it: there is a page for this now, and a supplier
                       account is edited on its own record there. */
                    onClicked: Destinations.request("suppliers")
                }
            ]
        }

        CardRow {
            Layout.fillWidth: true

            KpiCard {
                label: Strings.t("purchases.card.count", "Invoices")
                value: root.statText("count")
                glyph: "ic_fluent_receipt_20_regular"
                tone: "primary"
            }

            KpiCard {
                label: Strings.t("purchases.card.total", "Purchased")
                value: root.statText("total")
                valueTooltip: root.statText("total_full")
                glyph: "ic_fluent_box_multiple_20_regular"
                tone: "info"
            }

            KpiCard {
                label: Strings.t("purchases.card.debt", "Owed to suppliers")
                value: root.statText("debt")
                valueTooltip: root.statText("debt_full")
                glyph: "ic_fluent_wallet_20_regular"
                tone: "danger"
                valueTone: root.statNumber("debt_raw") > 0 ? "danger" : ""
            }
        }

        FilterBar {
            id: filters
            Layout.fillWidth: true
            placeholder: Strings.t("purchases.search.ph", "Search number or supplier")

            onSearchTextChanged: debounce.restart()
            onAccepted: root.applySearch()

            actionItems: [
                ProgressRing {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.busy && root.total > 0
                    indeterminate: true
                    ringSize: 28
                    strokeWidth: 3
                }
            ]
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            DataTable {
                id: table
                anchors.fill: parent
                visible: !root.showState
                columns: root.tableColumns
                model: root.ctrl ? root.ctrl.rows : null

                onRowActivated: (row) => root.handleAction(row, "edit")
                onActionTriggered: (row, action) => root.handleAction(row, action)
            }

            StateView {
                anchors.fill: parent
                visible: root.showState
                variant: root.stateVariant
                body: root.stateVariant === "error" ? root.errorText : ""
                onRetryRequested: root.reload()
            }

            LoadingOverlay {
                visible: root.busy && root.total === 0
            }
        }

        PaginationBar {
            Layout.fillWidth: true
            page: root.currentPage
            pageSize: root.pageSize
            total: root.total

            onPageRequested: (page) => {
                root.currentPage = Math.max(1, page)
                root.reload()
            }
            onPageSizeRequested: (size) => {
                root.pageSize = size
                root.currentPage = 1
                root.reload()
            }
        }
    }

    /*
     * Deleting a delivery is the one destructive act on this app that routinely cannot
     * be undone cleanly, and the confirmation is where that is said.
     *
     * `delete_purchase_invoice` takes the delivered quantities back off the shelf and
     * reduces the supplier's account by what is still owed on the invoice — both
     * clamped at zero, because a negative shelf and a negative account are worse than
     * a wrong one. By the time somebody deletes a delivery, though, the goods may have
     * been sold and the invoice may have been paid down, and then each clamp swallows a
     * difference the books will never show again.
     *
     * So `deleteImpact` reads both before anything is written, and the two conditions
     * appear as warnings with the actual numbers in them: which product is short and by
     * how much, and how much of the debt reversal the account cannot absorb. Neither
     * blocks the delete — only the operator can judge whether the correction is worth
     * it — but neither happens silently.
     */
    ConfirmDialog {
        id: confirmDelete

        property int invoiceId: -1
        property var impact: null

        title: Strings.t("purchases.delete.title", "Delete this delivery?")

        body: impact
              ? Strings.tf("purchases.delete.body2",
                           "{number} is removed: the delivered stock comes back off the shelf and the supplier's account is reduced by what is still owed on it.",
                           { number: impact.number })
              : ""

        facts: impact ? [
            {
                label: Strings.t("pos.summary.items", "Items"),
                value: impact.lines + " \u00b7 " + impact.units,
                tone: ""
            },
            {
                label: Strings.t("purchases.col.total", "Total"),
                value: impact.total,
                tone: ""
            },
            {
                label: Strings.t("purchases.delete.owed", "Still owed on it"),
                value: impact.owed_value > 0 ? impact.owed : "",
                tone: "danger"
            },
            {
                label: impact.supplier !== ""
                       ? Strings.tf("purchases.delete.supplier_holds",
                                    "{name} is owed", { name: impact.supplier })
                       : "",
                value: impact.supplier !== "" ? impact.supplier_debt : "",
                tone: ""
            },
            {
                label: Strings.t("purchases.delete.batches", "Dated stock it created"),
                value: impact.batches > 0 ? String(impact.batches) : "",
                tone: "warning"
            }
        ] : []

        /* The two conditions, with the figures in them. Built as a list rather than one
           paragraph because they are independent: either, both or neither can apply. */
        warnings: {
            if (!impact)
                return []
            var out = []
            if (impact.short.length > 0) {
                var parts = []
                for (var i = 0; i < impact.short.length; i++) {
                    var line = impact.short[i]
                    parts.push(Strings.tf("purchases.delete.short_line",
                                          "{name} (delivered {delivered}, {stock} in stock)",
                                          { name: line.name,
                                            delivered: line.delivered,
                                            stock: line.stock }))
                }
                out.push(Strings.tf("purchases.delete.short",
                                    "Some of what this delivery brought in has been sold since: {lines}. Their stock stops at zero rather than going negative, so the shelf figures will be short by that much.",
                                    { lines: parts.join("; ") }))
            }
            if (impact.debt_short_value > 0)
                out.push(Strings.tf("purchases.delete.debt_short",
                                    "The supplier's account cannot give back the whole {owed} — it holds {held}. The difference of {diff} is dropped.",
                                    { owed: impact.owed, held: impact.supplier_debt,
                                      diff: impact.debt_short }))
            return out
        }

        confirmText: Strings.t("purchases.delete.action", "Delete the delivery")

        onConfirmed: if (root.ctrl) root.ctrl.remove(confirmDelete.invoiceId)
    }

    ToastHost {
        id: toast
        bottomMargin: Tokens.size.pagePadding
    }
}

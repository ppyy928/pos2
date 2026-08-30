import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * Sales — what has been sold, and what is still owed on it. Ported from pos's
 * sales page over db.fetch_sales.
 *
 *  ┌──────────────────────────────────────────────────────────────────────┐
 *  │ Sales                                                                │
 *  │ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐                          │
 *  │ │ 174    │ │ 4.2M   │ │ 3.1M   │ │ 1.1M   │  count / total / cash /  │
 *  │ └────────┘ └────────┘ └────────┘ └────────┘  outstanding             │
 *  │ [ 🔍 Search number or customer ] [All ▾]                             │
 *  │ TRX-0174  27/08 14:05  Amine Bekkar  [Partial]  12 480,00   2 480,00 │
 *  └──────────────────────────────────────────────────────────────────────┘
 *
 * THE PAYMENT TYPE IS A CHIP, AND ITS COLOUR IS THE POINT
 *
 * Cash, partial and debt are the three states of a sale that matter after the
 * fact, and the difference between them is money the shop is still waiting for.
 * The chip is toned from the raw key rather than from the translated word, so it
 * is the same colour in all three languages.
 *
 * WHY THE DEBT KPI IS TONED AND THE OTHERS ARE NOT
 *
 * A count and a turnover are facts. Outstanding debt is a number somebody has to
 * act on, and it is the only one on this row that can be a problem — so it is the
 * only one that gets a colour. Same rule as ProductsPage's low-stock card.
 */
Item {
    id: root

    // =====================================================================
    // BRIDGE
    // =====================================================================
    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.sales : null
    readonly property var session: (typeof app !== "undefined" && app) ? app.session : null
    readonly property var pos: (typeof app !== "undefined" && app) ? app.pos : null

    /* `revision` first: `can()` is a slot with no notifier, so a binding that only
       calls it never re-evaluates when somebody logs in. */
    readonly property bool canEdit: session && session.revision >= 0
                                    && session.can("sales.edit")
    readonly property var workflows: (typeof app !== "undefined" && app)
                                     ? app.workflows : null

    // =====================================================================
    // QUERY STATE
    // =====================================================================
    property string search: ""
    property string paymentType: ""
    property int currentPage: 1
    property int pageSize: 100

    readonly property bool busy: ctrl ? ctrl.busy : false
    readonly property string errorText: ctrl ? ctrl.error : ""
    readonly property int total: ctrl ? ctrl.total : 0
    readonly property var stats: ctrl ? ctrl.stats : null

    readonly property bool hasFilter: search !== "" || paymentType !== ""
    readonly property bool canReturn: session ? session.can("sales.edit") : true

    readonly property bool showState: !busy && (errorText !== "" || total === 0)
    readonly property string stateVariant: errorText !== "" ? "error"
                                         : hasFilter ? "no_results" : "empty"

    /* The three payment types, plus "everything". The empty key is the absence of
       a filter, which is what the controller expects. */
    readonly property var paymentFilters: [
        { key: "", label: Strings.t("sales.filter.all", "All payments") },
        { key: "cash", label: Strings.t("pay.type.cash", "Cash") },
        { key: "partial", label: Strings.t("pay.type.partial", "Partial") },
        { key: "debt", label: Strings.t("pay.type.debt", "Debt") }
    ]

    readonly property var tableColumns: [
        {
            key: "number",
            header: Strings.t("sales.col.number", "Number"),
            width: 190,
            ltr: true
        },
        {
            key: "when",
            header: Strings.t("sales.col.time", "Date"),
            width: 240,
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
            width: 165,
            badge: true,
            /* Toned from the raw key: cash is done, partial is part-done, debt is
               entirely outstanding. */
            tone: function (row) {
                if (row.payment_type === "cash")
                    return "success"
                if (row.payment_type === "partial")
                    return "warning"
                if (row.payment_type === "debt")
                    return "danger"
                return ""
            }
        },
        {
            key: "total",
            header: Strings.t("sales.col.total", "Total"),
            numeric: true,
            width: 200
        },
        {
            key: "due",
            header: Strings.t("sales.col.due", "Outstanding"),
            numeric: true,
            width: 200,
            tone: function (row) { return row.due !== "0.00" ? "danger" : "" }
        },
        {
            key: "actions",
            actions: root.rowActions
        }
    ]

    /*
     * `edit` opens the invoice in the TILL, not in an editor of its own.
     *
     * An invoice is corrected the way it was rung up — find the product, set the
     * quantity, choose how it is paid — and that screen already exists, with the
     * tiles, the keypad, the customer card and the two pay buttons an operator uses a
     * hundred times a day. A second screen shaped like it would be a copy to keep in
     * step, learned twice, and different somewhere in a way that costs a mistake.
     *
     * Gated on `sales.edit`, because rewriting a completed sale moves stock and a
     * customer's debt. `Sales.save` refuses one that has already been returned
     * against, so the pen may be pressed on any row and the refusal explains itself.
     */
    readonly property var rowActions: [
        { id: "view" },
        { id: "edit", enabled: root.canEdit },
        { id: "print" },
        { id: "return", enabled: root.canReturn }
    ]

    // =====================================================================
    // BEHAVIOUR
    // =====================================================================
    function reload() {
        if (ctrl)
            ctrl.load(search, paymentType, currentPage, pageSize, "", "")
    }

    function applySearch() {
        debounce.stop()
        search = filters.searchText
        currentPage = 1
        reload()
    }

    function selectPayment(key) {
        if (paymentType === key)
            return
        paymentType = key
        currentPage = 1
        reload()
    }

    function goToPage(page) {
        currentPage = Math.max(1, page)
        reload()
    }

    function handleAction(row, action) {
        var data = ctrl ? ctrl.rowAt(row) : null
        if (!data)
            return
        if (action === "view")
            requestOpen("sale_transaction", { sale_id: data.id })
        else if (action === "edit" && pos) {
            /* Load first, THEN navigate: loadSale refuses a cart that is not empty,
               and being thrown onto the till with the previous cart still on it and a
               refusal toast behind the page is the one outcome to avoid. */
            if (pos.loadSale(data.id))
                Destinations.request("pos")
        }
        else if (action === "return")
            requestOpen("return_create", { sale_id: data.id })
        else if (action === "print" && ctrl)
            /* A reprint is the commonest request at a counter: the customer wants
               the slip, or the first one came out blank. */
            ctrl.printReceipt(data.id)
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

    Component.onCompleted: reload()

    Connections {
        target: root.ctrl
        ignoreUnknownSignals: true

        /* A return changes a sale's outstanding figure, and a sale made at the
           till adds a row — both land here. */
        function onInvalidated() {
            root.reload()
        }

        function onReturned(result) {
            root.notify(Strings.tf("return.done", "Return {number} recorded",
                                   { number: result.number }),
                        Severity.success)
        }

        function onPrinted(number) {
            root.notify(Strings.t("sales.printed", "Sent to the printer"),
                        Severity.success)
        }

        function onRejected(message) {
            root.notify(message, Severity.caution)
        }
    }

    Timer {
        id: debounce
        interval: 300
        onTriggered: root.applySearch()
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
            title: Strings.t("nav.sales", "Sales")
            description: Strings.t("sales.description",
                                   "Every completed sale, and what is still owed on it.")
        }

        CardRow {
            Layout.fillWidth: true

            KpiCard {
                label: Strings.t("sales.card.count", "Sales")
                value: root.statText("count")
                glyph: "ic_fluent_receipt_money_20_regular"
                tone: "primary"
            }

            KpiCard {
                label: Strings.t("sales.card.total", "Turnover")
                value: root.statText("total")
                valueTooltip: root.statText("total_full")
                glyph: "ic_fluent_data_trending_20_regular"
                tone: "info"
            }

            KpiCard {
                label: Strings.t("sales.card.cash", "Taken in cash")
                value: root.statText("cash")
                valueTooltip: root.statText("cash_full")
                glyph: "ic_fluent_money_20_regular"
                tone: "success"
            }

            KpiCard {
                label: Strings.t("sales.card.debt", "Outstanding")
                value: root.statText("debt")
                valueTooltip: root.statText("debt_full")
                glyph: "ic_fluent_wallet_20_regular"
                tone: "warning"
                /* Only when there is something to chase. */
                valueTone: root.statNumber("debt_raw") > 0 ? "danger" : ""
            }
        }

        FilterBar {
            id: filters
            Layout.fillWidth: true
            placeholder: Strings.t("sales.search.ph", "Search number or customer")

            onSearchTextChanged: debounce.restart()
            onAccepted: root.applySearch()

            filterItems: [
                QC.ComboBox {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 260
                    textRole: "label"
                    model: root.paymentFilters
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                    /* Assigned, not bound: a ComboBox writes its own
                       currentIndex, which would destroy a binding on the first
                       click. Same note ProductsPage's category filter carries. */
                    onActivated: (index) => root.selectPayment(
                        root.paymentFilters[index].key)
                }
            ]

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

                onRowActivated: (row) => root.handleAction(row, "view")
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

            onPageRequested: (page) => root.goToPage(page)
            onPageSizeRequested: (size) => {
                root.pageSize = size
                root.goToPage(1)
            }
        }
    }

    // =====================================================================
    // STATS
    // =====================================================================
    /* Em dash for a figure that has not arrived: a KPI reading 0 is a claim, and
       "no data yet" is not the same claim. ProductsPage's own rule. */
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

    ToastHost {
        id: toast
        bottomMargin: Tokens.size.pagePadding
    }
}

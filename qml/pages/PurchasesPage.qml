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
        else if (action === "delete") {
            confirmDelete.invoiceId = data.id
            confirmDelete.number = data.number
            confirmDelete.open()
        }
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

    FluentDialog {
        id: confirmDelete

        property int invoiceId: -1
        property string number: ""
        readonly property int measure: 460

        modal: true
        title: Strings.t("purchases.delete.title", "Delete this invoice?")
        standardButtons: QC.Dialog.Yes | QC.Dialog.No

        onAccepted: if (root.ctrl) root.ctrl.remove(confirmDelete.invoiceId)

        contentItem: Column {
            spacing: Tokens.spacing.sm

            Text {
                width: confirmDelete.measure
                text: Strings.t("purchases.delete.body",
                                "The stock it added is removed and the supplier debt it created is undone.")
                wrapMode: Text.WordWrap
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                color: Fluent.textPrimary
            }

            Text {
                width: confirmDelete.measure
                text: "\u200e" + confirmDelete.number
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                font.weight: Font.DemiBold
                color: Fluent.textPrimary
            }
        }
    }

    ToastHost {
        id: toast
        bottomMargin: Tokens.size.pagePadding
    }
}

import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * The payments register: every settlement against a debt, customers and suppliers
 * in one list. Ported from pos's payments page over db.fetch_payments.
 *
 * One list rather than two, because the question is almost always "was this paid",
 * not "was this paid by a customer" — the kind is a column and a filter, not a
 * separate screen.
 *
 * Read-only, deliberately. A payment is money that has already changed hands, and
 * deleting one from a register is an account correction pretending to be a tidy-up:
 * the debt comes back, the drawer total no longer matches what was counted, and
 * neither of those reversals is visible from this screen. The record on the party
 * is where a wrong payment belongs, and it is where the correction is made.
 */
Item {
    id: root

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.payments : null

    property string kind: "all"
    property string search: ""
    property int currentPage: 1
    property int pageSize: 100

    readonly property bool busy: ctrl ? ctrl.busy : false
    readonly property string errorText: ctrl ? ctrl.error : ""
    readonly property int total: ctrl ? ctrl.total : 0
    readonly property var stats: ctrl ? ctrl.stats : null

    readonly property bool hasFilter: search !== "" || kind !== "all"

    readonly property bool showState: !busy && (errorText !== "" || total === 0)
    readonly property string stateVariant: errorText !== "" ? "error"
                                         : hasFilter ? "no_results" : "empty"

    readonly property var kinds: [
        { key: "all", label: Strings.t("payments.kind.all", "Everything") },
        { key: "customer", label: Strings.t("payments.kind.customer", "Customers") },
        { key: "supplier", label: Strings.t("payments.kind.supplier", "Suppliers") }
    ]

    readonly property var tableColumns: [
        {
            key: "when",
            header: Strings.t("payments.col.time", "Date"),
            width: 240,
            ltr: true
        },
        {
            key: "kind_label",
            header: Strings.t("payments.col.kind", "Kind"),
            width: 170,
            badge: true,
            tone: function (row) { return row.kind === "supplier" ? "info" : "success" }
        },
        {
            key: "party",
            header: Strings.t("payments.col.party", "Paid by"),
            stretch: true
        },
        {
            key: "amount_text",
            header: Strings.t("payments.col.amount", "Amount"),
            numeric: true,
            width: 240
        }
    ]

    function reload() {
        if (ctrl)
            ctrl.load(kind, search, currentPage, pageSize)
    }

    function applySearch() {
        debounce.stop()
        search = filters.searchText
        currentPage = 1
        reload()
    }

    function statText(key) {
        if (!stats)
            return "—"
        var value = stats[key]
        return (value === undefined || value === null || value === "") ? "—" : value
    }

    function notify(message, severity) {
        toast.show(message, severity)
    }

    Component.onCompleted: reload()

    /*
     * Re-read on arrival, because nothing else here does.
     *
     * The Refresh button that used to sit in the filter bar was this page's only
     * path back to the database — payments are recorded from Customers and from
     * Suppliers, never from here, so no write on this screen invalidates its own
     * list. `Payments` (bridge/cash.py:268) does emit `invalidated`, and the
     * Connections below now listens for it; this covers the other half, a payment
     * taken on another screen while this one sat cached in PageHost.
     */
    onVisibleChanged: if (visible) reload()

    Connections {
        target: root.ctrl
        ignoreUnknownSignals: true
        function onInvalidated() { root.reload() }
        function onRejected(message) { root.notify(message, Severity.caution) }
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
            title: Strings.t("nav.payments", "Payments")
            description: Strings.t("payments.description",
                                   "Every payment recorded against a debt.")
        }

        CardRow {
            Layout.fillWidth: true

            KpiCard {
                label: Strings.t("payments.card.count", "Payments")
                value: root.statText("count")
                glyph: "ic_fluent_wallet_20_regular"
                tone: "primary"
            }

            KpiCard {
                label: Strings.t("payments.card.customer", "From customers")
                value: root.statText("customer")
                valueTooltip: root.statText("customer_full")
                glyph: "ic_fluent_people_team_20_regular"
                tone: "success"
            }

            KpiCard {
                label: Strings.t("payments.card.supplier", "To suppliers")
                value: root.statText("supplier")
                valueTooltip: root.statText("supplier_full")
                glyph: "ic_fluent_vehicle_truck_profile_20_regular"
                tone: "info"
            }
        }

        FilterBar {
            id: filters
            Layout.fillWidth: true
            placeholder: Strings.t("payments.search.ph", "Search a name")

            onSearchTextChanged: debounce.restart()
            onAccepted: root.applySearch()

            filterItems: [
                QC.ComboBox {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 240
                    textRole: "label"
                    model: root.kinds
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                    onActivated: (index) => {
                        root.kind = root.kinds[index].key
                        root.currentPage = 1
                        root.reload()
                    }
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

    ToastHost {
        id: toast
        bottomMargin: Tokens.size.pagePadding
    }
}

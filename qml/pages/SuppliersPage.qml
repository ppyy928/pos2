import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * Suppliers — who the shop buys from, and what it owes them. The mirror of the
 * customers screen, with the sign reversed.
 *
 * A screen of its own rather than a dialog off the purchases page, because a
 * supplier account outlives any one invoice: what is owed, what has been paid, and
 * which deliveries it came from are the questions asked when the rep is standing at
 * the counter.
 */
Item {
    id: root

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.suppliers : null
    readonly property var session: (typeof app !== "undefined" && app) ? app.session : null
    readonly property var workflows: (typeof app !== "undefined" && app)
                                     ? app.workflows : null

    property string search: ""

    readonly property bool busy: ctrl ? ctrl.busy : false
    readonly property int total: ctrl ? ctrl.total : 0
    readonly property bool canManage: session ? session.can("purchases.manage") : true

    readonly property var rows: ctrl ? ctrl.rows : []

    readonly property bool showState: !busy && total === 0
    readonly property string stateVariant: search !== "" ? "no_results" : "empty"

    /* Computed here rather than in Python: the controller returns every supplier in
       one call, so the totals are a sum over rows already in hand. */
    readonly property var summary: {
        var owing = 0
        var count = 0
        var largest = 0
        for (var i = 0; i < rows.length; i++) {
            var debt = rows[i].debt
            if (debt > 0) {
                owing += debt
                count += 1
                if (debt > largest)
                    largest = debt
            }
        }
        return { owing: owing, count: count, largest: largest }
    }

    function money(value) {
        return ctrl ? ctrl.moneyText(value) : "—"
    }

    readonly property var tableColumns: [
        {
            key: "name",
            header: Strings.t("supplier.name", "Supplier"),
            stretch: true
        },
        {
            key: "phone",
            header: Strings.t("supplier.phone", "Phone"),
            width: 260,
            ltr: true
        },
        {
            key: "debt_text",
            header: Strings.t("suppliers.col.debt", "Owed"),
            numeric: true,
            width: 220,
            tone: function (row) { return row.owes ? "danger" : "" }
        },
        {
            key: "actions",
            actions: root.rowActions
        }
    ]

    /*
     * Two icons, not an eye and a coin.
     *
     * The eye used to open a read-only supplier panel that could not correct the
     * supplier's name — that lived in a separate manager dialog reached from the
     * purchases screen. The record is now one screen, `edit` opens it, and `pay`
     * opens it on its payments section with the amount focused.
     */
    readonly property var rowActions: [
        { id: "edit" },
        { id: "pay", enabled: function (row) { return root.canManage && row.owes } }
    ]

    function reload() {
        if (ctrl)
            ctrl.load(search)
    }

    function applySearch() {
        debounce.stop()
        search = filters.searchText
        reload()
    }

    function handleAction(row, action) {
        var data = ctrl ? ctrl.rowAt(row) : null
        if (!data)
            return
        if (action === "edit")
            requestOpen("supplier_form", { supplier_id: data.id })
        else if (action === "pay")
            requestOpen("supplier_form", { supplier_id: data.id,
                                           section: "payments" })
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

    /*
     * Re-read on arrival. Supplier debt moves from two screens this one cannot see —
     * a purchase invoice saved on Purchases raises it, and a payment recorded there
     * lowers it — and the Refresh button in the filter bar used to be the only way
     * back to the truth. `invalidated` below covers a change made while this page is
     * live; this covers one made while it sat cached in PageHost.
     */
    onVisibleChanged: if (visible) reload()

    Connections {
        target: root.ctrl
        ignoreUnknownSignals: true

        function onInvalidated() { root.reload() }

        function onPaid(result) {
            root.notify(Strings.tf("suppliers.paid", "Paid — {debt} still owed",
                                   { debt: result.debt_text }),
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

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.size.pagePadding
        spacing: Tokens.spacing.lg

        PageHeader {
            Layout.fillWidth: true
            title: Strings.t("nav.suppliers", "Suppliers")
            description: Strings.t("suppliers.description",
                                   "Who the shop buys from, and what is still owed to them.")

            actionItems: [
                /* The same record screen with nothing in it, rather than the list-
                   plus-form manager this button used to open: adding a supplier from
                   the suppliers page should not put a second copy of the suppliers
                   list on top of it. */
                GlyphButton {
                    glyph: "ic_fluent_add_20_regular"
                    text: Strings.t("suppliers.add", "New supplier")
                    highlighted: true
                    enabled: root.canManage
                    onClicked: root.requestOpen("supplier_form", {})
                }
            ]
        }

        CardRow {
            Layout.fillWidth: true

            KpiCard {
                label: Strings.t("suppliers.card.count", "Suppliers")
                value: String(root.total)
                glyph: "ic_fluent_vehicle_truck_profile_20_regular"
                tone: "primary"
            }

            KpiCard {
                label: Strings.t("suppliers.card.debtors", "With a balance")
                value: String(root.summary.count)
                glyph: "ic_fluent_receipt_20_regular"
                tone: "warning"
                valueTone: root.summary.count > 0 ? "warning" : ""
            }

            KpiCard {
                label: Strings.t("suppliers.card.debt", "Total owed")
                value: root.money(root.summary.owing)
                glyph: "ic_fluent_wallet_20_regular"
                tone: "danger"
                valueTone: root.summary.owing > 0 ? "danger" : ""
            }

            KpiCard {
                label: Strings.t("suppliers.card.largest", "Largest balance")
                value: root.money(root.summary.largest)
                glyph: "ic_fluent_arrow_trending_20_regular"
                tone: "info"
            }
        }

        FilterBar {
            id: filters
            Layout.fillWidth: true
            placeholder: Strings.t("suppliers.search.ph", "Search name or phone")

            onSearchTextChanged: debounce.restart()
            onAccepted: root.applySearch()
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            DataTable {
                id: table
                anchors.fill: parent
                visible: !root.showState
                columns: root.tableColumns
                model: root.rows

                onRowActivated: (row) => root.handleAction(row, "edit")
                onActionTriggered: (row, action) => root.handleAction(row, action)
            }

            StateView {
                anchors.fill: parent
                visible: root.showState
                variant: root.stateVariant
                onRetryRequested: root.reload()
            }

            LoadingOverlay {
                visible: root.busy && root.total === 0
            }
        }
    }

    ToastHost {
        id: toast
        bottomMargin: Tokens.size.pagePadding
    }
}

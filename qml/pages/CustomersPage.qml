import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * Customers, and what they owe. Ported from pos's customers page over
 * db.fetch_customers.
 *
 * The only reason a shop keeps this list is the debt column: who may buy on
 * account, who has to settle first, and how much is out there in total. So the
 * page leads with those figures, the "owes something" filter is one tap, and the
 * row action that matters is taking a payment.
 */
Item {
    id: root

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.customers : null
    readonly property var session: (typeof app !== "undefined" && app) ? app.session : null
    readonly property var workflows: (typeof app !== "undefined" && app)
                                     ? app.workflows : null

    property string search: ""
    property bool onlyDebtors: false
    property int currentPage: 1
    property int pageSize: 100

    readonly property bool busy: ctrl ? ctrl.busy : false
    readonly property string errorText: ctrl ? ctrl.error : ""
    readonly property int total: ctrl ? ctrl.total : 0
    readonly property var stats: ctrl ? ctrl.stats : null

    readonly property bool hasFilter: search !== "" || onlyDebtors
    readonly property bool canManage: session ? session.can("customers.manage") : true

    readonly property bool showState: !busy && (errorText !== "" || total === 0)
    readonly property string stateVariant: errorText !== "" ? "error"
                                         : hasFilter ? "no_results" : "empty"

    readonly property var tableColumns: [
        {
            key: "name",
            header: Strings.t("qcustomer.name", "Customer"),
            stretch: true
        },
        {
            key: "phone",
            header: Strings.t("qcustomer.phone", "Phone"),
            width: 260,
            ltr: true
        },
        {
            key: "debt_text",
            header: Strings.t("select_customer.col.debt", "Debt"),
            numeric: true,
            width: 220,
            /* Red because it is money owed, not because of which column it is
               in — a settled account shows the same figure in ordinary ink. */
            tone: function (row) { return row.owes ? "danger" : "" }
        },
        {
            key: "actions",
            actions: root.rowActions
        }
    ]

    /*
     * Two icons, not three.
     *
     * There used to be an eye as well, opening a read-only customer panel that the
     * pencil then had to be used to correct. Both opened the same record, so the
     * record is now one screen and `edit` is how it is reached — which also means
     * `edit` is not gated on the manage right any more: looking is what
     * `customers.view` allows, and the dialog gates its own Save.
     *
     * `pay` is still its own icon because it is the errand, not a way of looking at
     * the account: it lands on the payments section with the amount focused.
     */
    readonly property var rowActions: [
        { id: "edit" },
        { id: "pay", enabled: function (row) { return root.canManage && row.owes } }
    ]

    function reload() {
        if (ctrl)
            ctrl.load(search, onlyDebtors, currentPage, pageSize)
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
            requestOpen("customer_form", { customer_id: data.id })
        else if (action === "pay")
            requestOpen("customer_form", { customer_id: data.id,
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

        function onInvalidated() {
            root.reload()
        }

        function onPaid(result) {
            root.notify(Strings.tf("payments.recorded", "Payment recorded — debt now {debt}",
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
            title: Strings.t("nav.customers", "Customers")
            description: Strings.t("customers.description",
                                   "Accounts, phone numbers and outstanding debt.")

            actionItems: [
                GlyphButton {
                    glyph: "ic_fluent_person_add_20_regular"
                    text: Strings.t("customers.add", "New customer")
                    highlighted: true
                    enabled: root.canManage
                    onClicked: root.requestOpen("customer_form", {})
                }
            ]
        }

        CardRow {
            Layout.fillWidth: true

            KpiCard {
                label: Strings.t("customers.card.count", "Customers")
                value: root.statText("count")
                glyph: "ic_fluent_people_team_20_regular"
                tone: "primary"
            }

            KpiCard {
                label: Strings.t("customers.card.debtors", "With debt")
                value: root.statText("debtors")
                glyph: "ic_fluent_person_warning_20_regular"
                tone: "warning"
                valueTone: root.statNumber("debtors_raw") > 0 ? "warning" : ""
            }

            KpiCard {
                label: Strings.t("customers.card.debt", "Total owed")
                value: root.statText("debt")
                valueTooltip: root.statText("debt_full")
                glyph: "ic_fluent_wallet_20_regular"
                tone: "danger"
                valueTone: root.statNumber("debt_raw") > 0 ? "danger" : ""
            }

            KpiCard {
                label: Strings.t("customers.card.largest", "Largest account")
                value: root.statText("largest")
                glyph: "ic_fluent_arrow_trending_20_regular"
                tone: "info"
            }
        }

        FilterBar {
            id: filters
            Layout.fillWidth: true
            placeholder: Strings.t("customers.search.ph", "Search name or phone")

            onSearchTextChanged: debounce.restart()
            onAccepted: root.applySearch()

            filterItems: [
                /* A toggle, not a dropdown with two entries: "who owes me money"
                   is the question this page exists to answer, and it should be one
                   tap away rather than two. */
                GlyphButton {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "ic_fluent_filter_20_regular"
                    text: Strings.t("customers.filter.debtors", "Owes money")
                    highlighted: root.onlyDebtors
                    onClicked: {
                        root.onlyDebtors = !root.onlyDebtors
                        root.currentPage = 1
                        root.reload()
                    }
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

    ToastHost {
        id: toast
        bottomMargin: Tokens.size.pagePadding
    }
}

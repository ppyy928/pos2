import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * Returns — what came back, and what it cost. Ported from pos's returns list over
 * db.fetch_returns.
 *
 * Its own screen rather than a filter on Sales, because a return is a document with
 * its own number (RET-0001) and "what came back this week" is a question a shop asks
 * on its own — usually about one supplier's product or one bad batch.
 *
 * Deleting one is an undo, not a tidy-up: the restored stock goes back out and a
 * credit sale's refund goes back onto the customer's debt, so the confirmation says
 * so and names the return.
 */
Item {
    id: root

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.returns : null
    readonly property var session: (typeof app !== "undefined" && app) ? app.session : null
    readonly property var workflows: (typeof app !== "undefined" && app)
                                     ? app.workflows : null

    property string search: ""
    property int currentPage: 1
    property int pageSize: 100

    readonly property bool busy: ctrl ? ctrl.busy : false
    readonly property string errorText: ctrl ? ctrl.error : ""
    readonly property int total: ctrl ? ctrl.total : 0
    readonly property var stats: ctrl ? ctrl.stats : null
    readonly property bool canEdit: session ? session.can("sales.edit") : true

    readonly property bool showState: !busy && (errorText !== "" || total === 0)
    readonly property string stateVariant: errorText !== "" ? "error"
                                         : search !== "" ? "no_results" : "empty"

    readonly property var tableColumns: [
        {
            key: "number",
            header: Strings.t("returns.col.number", "Number"),
            width: 190,
            ltr: true
        },
        {
            key: "sale",
            header: Strings.t("returns.col.sale", "Sale"),
            width: 190,
            ltr: true
        },
        {
            key: "when",
            header: Strings.t("returns.col.time", "Date"),
            width: 240,
            ltr: true
        },
        {
            key: "reason",
            header: Strings.t("returns.col.reason", "Reason"),
            stretch: true
        },
        {
            key: "total",
            header: Strings.t("returns.col.total", "Refunded"),
            numeric: true,
            width: 200,
            /* Always toned: every figure in this column is money that went back
               out of the till. */
            tone: "warning"
        },
        {
            key: "actions",
            actions: root.rowActions
        }
    ]

    readonly property var rowActions: [
        { id: "view" },
        { id: "delete", enabled: root.canEdit }
    ]

    function reload() {
        if (ctrl)
            ctrl.load(search, currentPage, pageSize, "", "")
    }

    function applySearch() {
        debounce.stop()
        search = filters.searchText
        currentPage = 1
        reload()
    }

    function handleAction(row, action) {
        var data = ctrl ? ctrl.returnAt(row) : null
        if (!data)
            return
        if (action === "view")
            requestOpen("return_details", { return_id: data.id })
        else if (action === "delete") {
            confirmDelete.returnId = data.id
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

    Component.onCompleted: reload()

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
            title: Strings.t("nav.returns", "Returns")
            description: Strings.t("returns.description",
                                   "Goods brought back, priced at what they were sold for.")

            actionItems: [
                GlyphButton {
                    glyph: "ic_fluent_arrow_undo_20_regular"
                    text: Strings.t("return.create_title", "New return")
                    highlighted: true
                    enabled: root.canEdit
                    onClicked: root.requestOpen("sale_select", { purpose: "return" })
                }
            ]
        }

        CardRow {
            Layout.fillWidth: true

            KpiCard {
                label: Strings.t("returns.card.count", "Returns")
                value: root.statText("count")
                glyph: "ic_fluent_arrow_undo_20_regular"
                tone: "primary"
            }

            KpiCard {
                label: Strings.t("returns.card.total", "Refunded")
                value: root.statText("total")
                valueTooltip: root.statText("total_full")
                glyph: "ic_fluent_money_hand_20_regular"
                tone: "warning"
            }
        }

        FilterBar {
            id: filters
            Layout.fillWidth: true
            placeholder: Strings.t("returns.search.ph", "Search a return or sale number")

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

                onRowActivated: (row) => root.handleAction(row, "view")
                onActionTriggered: (row, action) => root.handleAction(row, action)
            }

            StateView {
                anchors.fill: parent
                visible: root.showState
                variant: root.stateVariant
                title: root.stateVariant === "empty"
                       ? Strings.t("returns.empty.title", "Nothing has come back")
                       : ""
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

        property int returnId: -1
        property string number: ""
        readonly property int measure: 470

        modal: true
        title: Strings.t("returns.delete.title", "Undo this return?")
        standardButtons: QC.Dialog.Yes | QC.Dialog.No

        onAccepted: if (root.ctrl) root.ctrl.remove(confirmDelete.returnId)

        contentItem: Column {
            spacing: Tokens.spacing.sm

            Text {
                width: confirmDelete.measure
                text: Strings.t("returns.delete.body",
                                "The stock it put back is removed again, and a credit sale's refund goes back onto the customer's debt.")
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

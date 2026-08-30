import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * Employees — who may sign in, and what they may do once they have. Ported from
 * pos's employees page over db.fetch_employees.
 *
 * The status column is a chip rather than a tick, because "inactive" is the only
 * thing on this screen that changes what happens at the login window, and it has
 * to be readable at a glance down the column.
 *
 * There is no delete. Sales carry the name of whoever made them, so removing an
 * employee would orphan an audit trail; deactivating is the operation, and it is
 * what closes the door.
 */
Item {
    id: root

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.employees : null
    readonly property var session: (typeof app !== "undefined" && app) ? app.session : null
    readonly property var workflows: (typeof app !== "undefined" && app)
                                     ? app.workflows : null

    property string search: ""

    readonly property bool busy: ctrl ? ctrl.busy : false
    readonly property string errorText: ctrl ? ctrl.error : ""
    readonly property int total: ctrl ? ctrl.total : 0
    readonly property bool canManage: session ? session.can("employees.manage") : true

    readonly property bool showState: !busy && (errorText !== "" || total === 0)
    readonly property string stateVariant: errorText !== "" ? "error"
                                         : search !== "" ? "no_results" : "empty"

    readonly property var tableColumns: [
        {
            key: "name",
            header: Strings.t("employees.col.name", "Name"),
            stretch: true
        },
        {
            key: "username",
            header: Strings.t("employees.col.username", "Username"),
            width: 240,
            ltr: true
        },
        {
            key: "role_label",
            header: Strings.t("employees.col.role", "Role"),
            width: 180,
            badge: true,
            tone: function (row) { return row.role === "admin" ? "primary" : "info" }
        },
        {
            key: "permission_count",
            header: Strings.t("employees.col.permissions", "Permissions"),
            numeric: true,
            width: 190
        },
        {
            key: "status",
            header: Strings.t("employees.col.status", "Status"),
            width: 180,
            badge: true,
            tone: function (row) { return row.active ? "success" : "danger" }
        },
        {
            key: "actions",
            actions: root.rowActions
        }
    ]

    readonly property var rowActions: [
        { id: "edit", enabled: root.canManage }
    ]

    /* The controller reports `active` as a bool; the table draws strings, and the
       chip needs a word rather than "true". */
    readonly property var rows: {
        var source = ctrl ? ctrl.rows : []
        var out = []
        for (var i = 0; i < source.length; i++) {
            var row = source[i]
            out.push({
                id: row.id,
                name: row.name,
                username: row.username,
                role: row.role,
                role_label: row.role_label,
                permission_count: row.permission_count,
                active: row.active,
                status: row.active ? Strings.t("employees.active", "Active")
                                   : Strings.t("employees.inactive", "Inactive")
            })
        }
        return out
    }

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
            requestOpen("employee_form", { employee_id: data.id })
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
            title: Strings.t("employees.title", "Employees")
            description: Strings.t("employees.info",
                                   "Accounts, roles and what each person may do.")

            actionItems: [
                GlyphButton {
                    glyph: "ic_fluent_person_add_20_regular"
                    text: Strings.t("employees.add", "New employee")
                    highlighted: true
                    enabled: root.canManage
                    onClicked: root.requestOpen("employee_form", {})
                }
            ]
        }

        FilterBar {
            id: filters
            Layout.fillWidth: true
            placeholder: Strings.t("employees.search.ph", "Search name or username")

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
                body: root.stateVariant === "error" ? root.errorText : ""
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

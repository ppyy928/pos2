import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * An employee account, in two columns: who they are on the left, what they may do
 * on the right.
 *
 *   ┌──────────────────────────┬────────────────────────────────────┐
 *   │ ACCOUNT                  │ PERMISSIONS                        │
 *   │ Name .................   │ Sales & POS   [x] Sell  [x] View   │
 *   │ Username .............   │ Catalog       [ ] View  [ ] Manage │
 *   │ Role [ Cashier      ▾ ]  │ Purchases     [ ] View  [ ] Manage │
 *   │ Password .............   │ Customers     [x] View  [ ] Manage │
 *   │ [x] Active               │ Cash          [x] View  [ ] Manage │
 *   │                          │ Administration…                    │
 *   └──────────────────────────┴────────────────────────────────────┘
 *
 * The permissions are the larger half and they get the larger column: eleven
 * checkboxes in six groups is the part of this form somebody actually thinks about,
 * and folding them under four text fields is what made the single-column version
 * unusable.
 *
 * PICKING A ROLE FILLS THE PERMISSIONS IN, IT DOES NOT LOCK THEM
 *
 * A role is a starting point — pos's ROLE_DEFAULTS — and the boxes stay editable
 * underneath it, because a real shop always has the cashier who is also allowed to
 * receive deliveries. Choosing a role replaces the selection, so the order is:
 * role first, then adjust. A NEW account opens already filled from the default
 * role ("seller"), because a form whose role and whose checkboxes disagree about
 * the same state is a form that has not finished opening.
 *
 * THE PASSWORD FIELD IS EMPTY ON AN EDIT AND MEANS "LEAVE IT ALONE"
 *
 * save_employee only rewrites the hash when a password is supplied. On a new
 * account it is required, because an account whose hash is empty can be signed
 * into by anyone who knows the username.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.employees : null
    readonly property int employeeId: context && context.employee_id
                                      ? context.employee_id : 0
    readonly property bool creating: employeeId === 0

    preferredWidth: 1280
    preferredHeight: 820

    title: creating ? Strings.t("employees.add", "New employee")
                    : Strings.t("employees.edit_title", "Edit employee")

    property var row: ({})
    /* The permission keys currently ticked. Replaced wholesale on every change so
       the bindings that read it fire. */
    property var granted: []

    Component.onCompleted: {
        if (!creating && ctrl)
            row = ctrl.employee(employeeId) || ({})
        name.text = row.name !== undefined ? row.name : ""
        username.text = row.username !== undefined ? row.username : ""
        active.checked = row.active !== false
        role.currentIndex = indexOfRole(row.role !== undefined ? row.role : "seller")
        if (creating) {
            /* A new account starts from its role, not from nothing. The combo
               already says "Seller" — set above — but `applyRole` only runs
               `onActivated`, on a human change. Without this, the form opened
               showing the seller role with every permission unticked, and the
               defaults only appeared once the operator cycled the combo away
               and back: the role and the boxes disagreed about the same state.
               An edit keeps the employee's own grants, which may have been
               adjusted away from the role's defaults and are the truth. */
            applyRole(role.currentIndex)
        } else {
            granted = row.permissions !== undefined ? row.permissions.slice() : []
        }
        name.forceActiveFocus()
    }

    readonly property var roles: ctrl ? ctrl.roles : []
    readonly property var groups: ctrl ? ctrl.permissionGroups : []

    function indexOfRole(key) {
        for (var i = 0; i < roles.length; i++)
            if (roles[i].key === key)
                return i
        return 0
    }

    function has(permission) {
        return granted.indexOf(permission) >= 0
    }

    function toggle(permission, on) {
        var next = granted.slice()
        var at = next.indexOf(permission)
        if (on && at < 0)
            next.push(permission)
        else if (!on && at >= 0)
            next.splice(at, 1)
        granted = next
    }

    function applyRole(index) {
        if (index >= 0 && index < roles.length)
            granted = (roles[index].permissions || []).slice()
    }

    function save() {
        error.text = ""
        if (!ctrl)
            return
        ctrl.save({
            name: name.text,
            username: username.text,
            role: roles.length > 0 ? roles[role.currentIndex].key : "seller",
            active: active.checked,
            permissions: granted,
            password: password.text
        }, employeeId)
    }

    Connections {
        target: dialog.ctrl
        ignoreUnknownSignals: true
        function onSaved(employee) { dialog.close() }
        function onRejected(message) { error.text = message }
    }

    component Field: ColumnLayout {
        id: field
        property string label: ""
        property bool required: false

        Layout.fillWidth: true
        spacing: 2

        Text {
            text: field.required ? field.label + " *" : field.label
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.caption
            font.weight: Font.DemiBold
            color: Fluent.textSecondary
        }
    }

    component Group: ColumnLayout {
        id: group
        property string label: ""

        Layout.fillWidth: true
        spacing: Tokens.spacing.sm

        Text {
            text: group.label
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.overline
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.1
            color: Fluent.textTertiary
        }
    }

    contentItem: ColumnLayout {
        spacing: Tokens.spacing.md

        Flickable {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: columns.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            QC.ScrollBar.vertical: FluentScrollBar { policy: QC.ScrollBar.AsNeeded }

            RowLayout {
                id: columns
                width: body.width
                spacing: Tokens.spacing.xxl

                // =========================================================
                // left: the account
                // =========================================================
                ColumnLayout {
                    Layout.preferredWidth: 1
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: Tokens.spacing.lg

                    Group {
                        label: Strings.t("employees.info", "Account")

                        Field {
                            label: Strings.t("employees.col.name", "Name")
                            required: true

                            QC.TextField {
                                id: name
                                Layout.fillWidth: true
                                Layout.preferredHeight: Tokens.size.control
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.body
                            }
                        }

                        Field {
                            label: Strings.t("employees.col.username", "Username")
                            required: true

                            QC.TextField {
                                id: username
                                Layout.fillWidth: true
                                Layout.preferredHeight: Tokens.size.control
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.body
                                /* A login name reads left to right whatever the UI
                                   does. */
                                horizontalAlignment: TextInput.AlignLeft
                            }
                        }

                        Field {
                            label: Strings.t("employees.col.role", "Role")

                            QC.ComboBox {
                                id: role
                                Layout.fillWidth: true
                                textRole: "label"
                                model: dialog.roles
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.body
                                onActivated: (index) => dialog.applyRole(index)
                            }
                        }

                        Field {
                            label: dialog.creating
                                   ? Strings.t("employees.password", "Password")
                                   : Strings.t("employees.change_password", "New password")
                            required: dialog.creating

                            QC.TextField {
                                id: password
                                Layout.fillWidth: true
                                Layout.preferredHeight: Tokens.size.control
                                echoMode: TextInput.Password
                                placeholderText: dialog.creating
                                                 ? ""
                                                 : Strings.t("employees.password.keep",
                                                             "Leave empty to keep the current one")
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.body
                            }
                        }

                        QC.Switch {
                            id: active
                            text: Strings.t("employees.active", "Active")
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.body
                        }

                        Text {
                            Layout.fillWidth: true
                            text: Strings.t("employees.inactive.hint",
                                            "An inactive account cannot sign in. Accounts are never deleted, because sales carry the name of whoever made them.")
                            wrapMode: Text.WordWrap
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.caption
                            color: Fluent.textTertiary
                        }
                    }
                }

                // =========================================================
                // right: what they may do
                // =========================================================
                ColumnLayout {
                    /* Twice the width of the account column: this is the half of
                       the form with eleven decisions in it. */
                    Layout.preferredWidth: 2
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: Tokens.spacing.md

                    Group {
                        label: Strings.t("employees.permissions", "Permissions")

                        /* Grouped exactly as Python groups them, so this screen and
                           session.can() describe the same six areas. */
                        Repeater {
                            model: dialog.groups

                            delegate: Rectangle {
                                id: group
                                required property var modelData

                                Layout.fillWidth: true
                                implicitHeight: block.implicitHeight + 2 * Tokens.spacing.sm
                                radius: Tokens.radius.md
                                color: Fluent.subtleSecondary

                                ColumnLayout {
                                    id: block
                                    anchors.fill: parent
                                    anchors.margins: Tokens.spacing.sm
                                    spacing: 2

                                    Text {
                                        text: group.modelData.label
                                        font.family: Tokens.font.family
                                        font.pixelSize: Tokens.font.caption
                                        font.weight: Font.DemiBold
                                        color: Fluent.textSecondary
                                    }

                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: Tokens.spacing.md

                                        Repeater {
                                            model: group.modelData.permissions

                                            delegate: QC.CheckBox {
                                                required property var modelData

                                                text: modelData.label
                                                checked: dialog.has(modelData.key)
                                                font.family: Tokens.font.family
                                                font.pixelSize: Tokens.font.body
                                                onToggled: dialog.toggle(modelData.key,
                                                                         checked)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Text {
            id: error
            Layout.fillWidth: true
            visible: text !== ""
            wrapMode: Text.WordWrap
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.caption
            color: Tokens.danger
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.sm

            Item { Layout.fillWidth: true }

            GlyphButton {
                glyph: "ic_fluent_dismiss_20_regular"
                outlined: true
                text: Strings.t("action.cancel", "Cancel")
                onClicked: dialog.close()
            }

            GlyphButton {
                glyph: "ic_fluent_save_20_regular"
                text: Strings.t("action.save", "Save")
                highlighted: true
                onClicked: dialog.save()
            }
        }
    }
}

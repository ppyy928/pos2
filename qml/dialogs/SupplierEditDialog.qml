import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * A supplier's details, added or corrected. The customer editor with the sign
 * reversed — and, like it, only the details: what the shop owes and which
 * deliveries are behind it belong to the record screen.
 *
 *   ┌ Edit supplier ────────────────────────────────────────────────┐
 *   │ Supplier name *                        Phone                  │
 *   │ [ Sarl Boissons Atlas           ]      [ 0770 11 22 33     ]  │
 *   │ Rep                     Wilaya          Address               │
 *   │ [ Karim              ]  [ Blida  ]     [                   ]  │
 *   │ Email               NIF              RC                       │
 *   │ [               ]   [           ]    [                    ]   │
 *   │                                        Cancel      Save       │
 *   └───────────────────────────────────────────────────────────────┘
 *
 * WHY IT LEFT THE RECORD
 *
 * The record held these fields and swapped between reading and writing with a flag,
 * so pressing Edit hid the balance the operator was looking at — and "new supplier"
 * was the same 1240px record screen with the invoices, the cards and the sections
 * switched off.
 *
 * A supplier is reached through a person: the rep's name is what gets a delivery
 * moved, and it is the thing a shop writes on the wall next to the phone. The wilaya
 * decides how long a replacement takes. Those two sit with the phone; the postal and
 * tax detail is only ever read while writing paperwork.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.suppliers : null
    readonly property var session: (typeof app !== "undefined" && app) ? app.session : null

    /* Writable: the record screen reuses one instance of this dialog. */
    property int supplierId: 0

    readonly property bool creating: supplierId === 0
    readonly property bool canManage: session ? session.can("purchases.manage") : true
    readonly property int measure: 700

    preferredWidth: 940

    title: creating ? Strings.t("suppliers.add", "New supplier")
                    : Strings.t("supplier.edit_title", "Edit supplier")

    signal committed(var supplier)

    function edit(row) {
        var r = row || ({})
        supplierId = r.id ? r.id : 0
        name.text = r.name !== undefined ? r.name : ""
        phone.text = r.phone !== undefined ? r.phone : ""
        contact.text = r.contact !== undefined ? r.contact : ""
        wilaya.text = r.wilaya !== undefined ? r.wilaya : ""
        address.text = r.address !== undefined ? r.address : ""
        email.text = r.email !== undefined ? r.email : ""
        taxId.text = r.tax_id !== undefined ? r.tax_id : ""
        tradeId.text = r.trade_id !== undefined ? r.trade_id : ""
        error.text = ""
        open()
        name.forceActiveFocus()
        name.selectAll()
    }

    Component.onCompleted: {
        if (context && context.supplier_id) {
            supplierId = context.supplier_id
            if (ctrl)
                edit(ctrl.supplier(supplierId) || ({}))
            return
        }
        if (context && context.name)
            name.text = context.name
        name.forceActiveFocus()
    }

    function save() {
        error.text = ""
        if (!ctrl)
            return
        if (name.text.trim() === "") {
            error.text = Strings.t("suppliers.name.required",
                                   "A supplier needs a name.")
            name.forceActiveFocus()
            return
        }
        ctrl.save(name.text, phone.text, supplierId, {
            contact: contact.text,
            wilaya: wilaya.text,
            address: address.text,
            email: email.text,
            tax_id: taxId.text,
            trade_id: tradeId.text
        })
    }

    Connections {
        target: dialog.ctrl
        ignoreUnknownSignals: true

        function onSaved(supplier) {
            if (!dialog.visible)
                return
            dialog.committed(supplier)
            dialog.close()
        }

        function onRejected(message) {
            if (dialog.visible)
                error.text = message
        }
    }

    // =====================================================================
    // PIECES
    // =====================================================================
    component Field: ColumnLayout {
        id: field
        property string label: ""
        property bool required: false

        Layout.fillWidth: true
        spacing: 2

        Text {
            Layout.fillWidth: true
            text: field.required ? field.label + " *" : field.label
            elide: Text.ElideRight
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.caption
            font.weight: Font.DemiBold
            color: Fluent.textSecondary
        }
    }

    // =====================================================================
    // LAYOUT
    // =====================================================================
    contentItem: ColumnLayout {
        spacing: Tokens.spacing.md

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: dialog.measure
            spacing: Tokens.spacing.md

            Field {
                label: Strings.t("supplier.name", "Supplier name")
                required: true

                QC.TextField {
                    id: name
                    Layout.fillWidth: true
                    Layout.preferredHeight: Tokens.size.control
                    enabled: dialog.canManage
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.bodyLarge
                    onAccepted: dialog.save()
                }
            }

            Field {
                Layout.maximumWidth: 300
                label: Strings.t("supplier.phone", "Phone")

                QC.TextField {
                    id: phone
                    Layout.fillWidth: true
                    Layout.preferredHeight: Tokens.size.control
                    enabled: dialog.canManage
                    inputMethodHints: Qt.ImhDialableCharactersOnly
                    horizontalAlignment: TextInput.AlignLeft
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                    onAccepted: dialog.save()
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.md

            Field {
                label: Strings.t("party.contact", "Rep")

                QC.TextField {
                    id: contact
                    Layout.fillWidth: true
                    Layout.preferredHeight: Tokens.size.control
                    enabled: dialog.canManage
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                }
            }

            Field {
                Layout.maximumWidth: 220
                label: Strings.t("party.wilaya", "Wilaya")

                QC.TextField {
                    id: wilaya
                    Layout.fillWidth: true
                    Layout.preferredHeight: Tokens.size.control
                    enabled: dialog.canManage
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                }
            }

            Field {
                label: Strings.t("party.address", "Address")

                QC.TextField {
                    id: address
                    Layout.fillWidth: true
                    Layout.preferredHeight: Tokens.size.control
                    enabled: dialog.canManage
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.md

            Field {
                Layout.maximumWidth: 300
                label: Strings.t("party.email", "Email")

                QC.TextField {
                    id: email
                    Layout.fillWidth: true
                    Layout.preferredHeight: Tokens.size.control
                    enabled: dialog.canManage
                    inputMethodHints: Qt.ImhEmailCharactersOnly
                    horizontalAlignment: TextInput.AlignLeft
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                }
            }

            Field {
                Layout.maximumWidth: 220
                label: Strings.t("party.tax_id", "NIF")

                QC.TextField {
                    id: taxId
                    Layout.fillWidth: true
                    Layout.preferredHeight: Tokens.size.control
                    enabled: dialog.canManage
                    horizontalAlignment: TextInput.AlignLeft
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                }
            }

            Field {
                Layout.maximumWidth: 220
                label: Strings.t("party.trade_id", "RC")

                QC.TextField {
                    id: tradeId
                    Layout.fillWidth: true
                    Layout.preferredHeight: Tokens.size.control
                    enabled: dialog.canManage
                    horizontalAlignment: TextInput.AlignLeft
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                }
            }

            Item { Layout.fillWidth: true }
        }

        Text {
            id: error
            Layout.fillWidth: true
            Layout.preferredWidth: dialog.measure
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
                enabled: dialog.canManage && name.text.trim() !== ""
                onClicked: dialog.save()
            }
        }
    }
}

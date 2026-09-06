import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * A customer's details, added or corrected. Only the details — what they owe and
 * what they bought are the record screen's business, not this one's.
 *
 *   ┌ Edit customer ────────────────────────────────────────────────┐
 *   │ Customer name *                        Phone                  │
 *   │ [ Ahmed Belkacem                ]      [ 0661 20 41 88     ]  │
 *   │ Address                    Wilaya          Price level        │
 *   │ [                     ]    [        ]     [ Retail       ▾ ]  │
 *   │ Email          NIF           RC            Credit limit       │
 *   │ [           ]  [         ]   [        ]    [ no ceiling    ]  │
 *   │ 0 means no ceiling. Above it, a sale on account is refused.    │
 *   │                                        Cancel      Save       │
 *   └───────────────────────────────────────────────────────────────┘
 *
 * WHY IT IS NOT INSIDE THE RECORD ANY MORE
 *
 * The record screen used to hold these fields itself and swap between reading and
 * writing with a flag. Two consequences, both bad: the figures an operator opened
 * the record to read disappeared the moment they pressed Edit, and the footer's
 * Save meant something different depending on a state nothing on screen named.
 * Adding a customer reused the same file with everything else switched off, which
 * is how a 1240px record screen ended up as the "new customer" form.
 *
 * So: the record is a record, and this is the form. It opens over the record when
 * something needs correcting, and on its own from the customers page when there is
 * no record yet.
 *
 * WHAT THE TILL READS
 *
 * Wilaya, price level and credit limit are not paperwork: the level picks which of
 * the three prices a sale uses, and the limit is what refuses a sale on account.
 * The postal fields are only ever read off a printed invoice.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.customers : null
    readonly property var session: (typeof app !== "undefined" && app) ? app.session : null

    /* Writable: the record screen reuses one instance of this dialog. */
    property int customerId: 0

    readonly property bool creating: customerId === 0
    readonly property bool canManage: session ? session.can("customers.manage") : true
    readonly property int measure: 700

    preferredWidth: 940

    title: creating ? Strings.t("customers.add", "New customer")
                    : Strings.t("customers.edit_title", "Edit customer")

    /* The saved record, for a host that wants to react to its own save. */
    signal committed(var customer)

    /* Which of the three counters this customer buys over. Held here rather than
       read off the combo, because the combo is rebuilt when the language changes
       and its index would not survive that. */
    property string levelKey: "retail"

    readonly property var levels: [
        { key: "retail", label: Strings.t("price.retail", "Retail") },
        { key: "half", label: Strings.t("price.half", "Half-wholesale") },
        { key: "wholesale", label: Strings.t("price.wholesale", "Wholesale") }
    ]

    function levelIndex(key) {
        for (var i = 0; i < levels.length; i++)
            if (levels[i].key === key)
                return i
        return 0
    }

    // =====================================================================
    // FILLING IT
    // =====================================================================
    /* The record screen's entry point: it already has the row, so this does not go
       back to the database for it. Imperative rather than bound, because the first
       keystroke breaks a binding and the next customer opened would show the last
       one's name. */
    function edit(row) {
        var r = row || ({})
        customerId = r.id ? r.id : 0
        name.text = r.name !== undefined ? r.name : ""
        phone.text = r.phone !== undefined ? r.phone : ""
        address.text = r.address !== undefined ? r.address : ""
        wilaya.text = r.wilaya !== undefined ? r.wilaya : ""
        email.text = r.email !== undefined ? r.email : ""
        taxId.text = r.tax_id !== undefined ? r.tax_id : ""
        tradeId.text = r.trade_id !== undefined ? r.trade_id : ""
        /* 0 is "no ceiling", and an empty box says that better than a 0 the
           operator has to know to read as unlimited. */
        limit.text = r.credit_limit ? String(r.credit_limit) : ""
        levelKey = r.price_level ? r.price_level : "retail"
        error.text = ""
        open()
        name.forceActiveFocus()
        name.selectAll()
    }

    /* Opened by the router instead: from the customers page for a new one, or from
       the till's picker with the name already typed into the search box. */
    Component.onCompleted: {
        if (context && context.customer_id) {
            customerId = context.customer_id
            if (ctrl)
                edit(ctrl.customer(customerId) || ({}))
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
            error.text = Strings.t("customers.name.required",
                                   "A customer needs a name.")
            name.forceActiveFocus()
            return
        }
        ctrl.save(name.text, phone.text, customerId, {
            address: address.text,
            wilaya: wilaya.text,
            email: email.text,
            tax_id: taxId.text,
            trade_id: tradeId.text,
            price_level: dialog.levelKey,
            credit_limit: limit.text
        })
    }

    Connections {
        target: dialog.ctrl
        ignoreUnknownSignals: true

        function onSaved(customer) {
            if (!dialog.visible)
                return
            dialog.committed(customer)
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
                label: Strings.t("qcustomer.name", "Customer name")
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
                label: Strings.t("qcustomer.phone", "Phone")

                QC.TextField {
                    id: phone
                    Layout.fillWidth: true
                    Layout.preferredHeight: Tokens.size.control
                    enabled: dialog.canManage
                    inputMethodHints: Qt.ImhDialableCharactersOnly
                    /* A phone number reads left to right in every language. */
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
                Layout.maximumWidth: 240
                label: Strings.t("customer.price_level", "Price level")

                QC.ComboBox {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Tokens.size.control
                    enabled: dialog.canManage
                    textRole: "label"
                    model: dialog.levels
                    currentIndex: dialog.levelIndex(dialog.levelKey)
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                    onActivated: (index) => {
                        dialog.levelKey = dialog.levels[index].key
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.md

            Field {
                Layout.maximumWidth: 280
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
                Layout.maximumWidth: 200
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
                Layout.maximumWidth: 200
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

            Field {
                Layout.maximumWidth: 200
                label: Strings.t("customer.credit_limit", "Credit limit")

                NumberField {
                    id: limit
                    Layout.fillWidth: true
                    Layout.preferredHeight: Tokens.size.control
                    enabled: dialog.canManage
                    placeholderText: Strings.t("customer.limit.none", "no ceiling")
                    font.pixelSize: Tokens.font.body
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.preferredWidth: dialog.measure
            text: Strings.t("customer.credit_limit.hint",
                            "0 means no ceiling. Above it, a sale on account is refused.")
            wrapMode: Text.WordWrap
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.caption
            color: Fluent.textTertiary
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

import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * One supplier: what the shop owes them, the deliveries behind it, what has been
 * paid — and the two fields that can be changed, in the same screen.
 *
 * The customer screen with the sign reversed, deliberately down to the layout: a
 * supplier account behaves the way a customer account does, and an operator who
 * has learned one should not have to learn the other. What differs is what the
 * first section lists (invoices in, not sales out) and where its action goes (the
 * purchase form, not the till).
 *
 * WHY THIS REPLACED `supplier_details`
 *
 * There used to be a read-only supplier panel behind an eye icon, and no way to
 * correct a supplier's name from it at all — that lived in the separate suppliers
 * manager, a list-plus-form dialog reached from another screen entirely. So a
 * misspelled supplier meant closing the record, opening a manager, finding the row
 * again and retyping it. The record is now the one place, and the eye column is
 * gone from the suppliers table.
 *
 * WHY PAYING IS IN THE PAYMENTS SECTION
 *
 * It is the reason this screen gets opened: the rep is at the counter with an
 * invoice, and the two things needed are the balance and a box to type into. Both
 * are here, and the payment lands in the list directly beneath it.
 */
AppDialog {
    id: dialog

    property var context: ({})

    // =====================================================================
    // BRIDGE
    // =====================================================================
    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.suppliers : null
    readonly property var session: (typeof app !== "undefined" && app) ? app.session : null
    readonly property var workflows: (typeof app !== "undefined" && app)
                                     ? app.workflows : null

    readonly property int supplierId: context && context.supplier_id
                                      ? context.supplier_id : 0
    readonly property bool creating: supplierId === 0

    readonly property bool canManage: session ? session.can("purchases.manage") : true

    preferredWidth: creating ? 700 : 1240
    preferredHeight: creating ? 0 : 900

    title: creating ? Strings.t("suppliers.add", "New supplier")
                    : (row.name !== undefined && row.name
                       ? row.name
                       : Strings.t("supplier.edit_title", "Edit supplier"))

    // =====================================================================
    // STATE
    // =====================================================================
    property var row: ({})

    readonly property var cards: row.cards !== undefined ? row.cards : ({})
    readonly property var invoices: row.invoices !== undefined ? row.invoices : []
    readonly property var payments: row.payments !== undefined ? row.payments : []

    readonly property real debt: row.debt !== undefined ? row.debt : 0
    readonly property bool owes: debt > 0

    property bool editingInfo: creating
    property bool paying: false

    property string invoicesQuery: ""
    property string paymentsQuery: ""

    /* Modal: the page's ToastHost is behind the scrim, so what happened is said
       here or not at all. */
    property string notice: ""

    readonly property int measure: 560

    // =====================================================================
    // DATA
    // =====================================================================
    Component.onCompleted: {
        reload()
        fill()
        if (creating) {
            name.forceActiveFocus()
        } else if (context && context.section) {
            sectionBar.select(context.section)
            if (context.section === "payments" && canManage && owes)
                openPayment()
        }
    }

    function reload() {
        if (ctrl && supplierId)
            row = ctrl.supplier(supplierId) || ({})
    }

    function fill() {
        name.text = row.name !== undefined ? row.name : ""
        phone.text = row.phone !== undefined ? row.phone : ""
        contact.text = row.contact !== undefined ? row.contact : ""
        wilaya.text = row.wilaya !== undefined ? row.wilaya : ""
        address.text = row.address !== undefined ? row.address : ""
        email.text = row.email !== undefined ? row.email : ""
        taxId.text = row.tax_id !== undefined ? row.tax_id : ""
        tradeId.text = row.trade_id !== undefined ? row.trade_id : ""
        error.text = ""
    }

    function saveInfo() {
        error.text = ""
        if (ctrl)
            ctrl.save(name.text, phone.text, supplierId, {
                contact: contact.text,
                wilaya: wilaya.text,
                address: address.text,
                email: email.text,
                tax_id: taxId.text,
                trade_id: tradeId.text
            })
    }

    function cancelInfo() {
        fill()
        editingInfo = false
    }

    function openPayment() {
        paying = true
        amount.forceActiveFocus()
    }

    // -- money ------------------------------------------------------------
    function money(value) {
        return ctrl ? ctrl.moneyText(value) : "—"
    }

    function number(text) {
        var value = parseFloat(String(text).replace(",", "."))
        return isNaN(value) ? 0 : value
    }

    readonly property real entered: number(amount.text)
    readonly property real remaining: Math.max(0, debt - entered)
    readonly property bool validPayment: entered > 0 && entered <= debt

    function pay() {
        error.text = ""
        notice = ""
        if (!validPayment) {
            error.text = entered > debt
                         ? Strings.t("payments.over_debt",
                                     "That is more than this account owes.")
                         : Strings.t("amount.error", "Enter a valid amount.")
            amount.forceActiveFocus()
            return
        }
        if (ctrl)
            ctrl.recordPayment(supplierId, amount.text)
    }

    // -- the two histories, filtered --------------------------------------
    /* Filtered here rather than in Python: both lists arrived whole with the
       record, so the search box over them is instant and needs no debounce. */
    function matches(haystack, needle) {
        return String(haystack).toLowerCase().indexOf(needle) >= 0
    }

    readonly property var invoiceRows: {
        var query = invoicesQuery.trim().toLowerCase()
        if (query === "")
            return invoices
        var out = []
        for (var i = 0; i < invoices.length; i++) {
            var invoice = invoices[i]
            if (matches(invoice.number, query) || matches(invoice.when, query)
                    || matches(invoice.total_text, query))
                out.push(invoice)
        }
        return out
    }

    readonly property var paymentRows: {
        var query = paymentsQuery.trim().toLowerCase()
        if (query === "")
            return payments
        var out = []
        for (var i = 0; i < payments.length; i++) {
            var payment = payments[i]
            if (matches(payment.when, query) || matches(payment.amount_text, query))
                out.push(payment)
        }
        return out
    }

    function cardText(key) {
        var value = cards[key]
        return (value === undefined || value === null || value === "") ? "—" : "" + value
    }

    function cardNumber(key) {
        var value = cards[key]
        return typeof value === "number" ? value : 0
    }

    // =====================================================================
    // COLUMNS
    // =====================================================================
    readonly property var invoiceColumns: [
        {
            key: "number",
            header: Strings.t("purchases.col.number", "Number"),
            width: 200,
            ltr: true
        },
        {
            key: "when",
            header: Strings.t("purchases.col.time", "Date"),
            stretch: true,
            ltr: true
        },
        {
            key: "total_text",
            header: Strings.t("purchases.col.total", "Total"),
            numeric: true,
            width: 200,
            ltr: true
        },
        {
            key: "due_text",
            header: Strings.t("purchases.col.due", "Outstanding"),
            numeric: true,
            width: 200,
            ltr: true,
            tone: function (r) { return r.owes ? "danger" : "" }
        }
    ]

    readonly property var paymentColumns: [
        {
            key: "when",
            header: Strings.t("purchases.col.time", "Date"),
            stretch: true,
            ltr: true
        },
        {
            key: "amount_text",
            header: Strings.t("cash.col.amount", "Amount"),
            numeric: true,
            width: 260,
            ltr: true,
            tone: "success"
        }
    ]

    // =====================================================================
    // BRIDGE SIGNALS
    // =====================================================================
    Connections {
        target: dialog.ctrl
        ignoreUnknownSignals: true

        function onSaved(supplier) {
            if (dialog.creating) {
                dialog.close()
                return
            }
            dialog.editingInfo = false
            dialog.notice = Strings.t("customers.info_saved", "Details saved.")
            dialog.reload()
            dialog.fill()
        }

        function onPaid(result) {
            /* Stays open with the new balance: a rep often settles two invoices in
               one visit, and reopening the record to do the second is a step for
               nothing. */
            amount.text = ""
            dialog.paying = false
            dialog.reload()
            dialog.notice = Strings.tf("suppliers.paid", "Paid — {debt} still owed",
                                       { debt: result.debt_text })
        }

        function onRejected(message) {
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
            text: field.required ? field.label + " *" : field.label
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

        // -----------------------------------------------------------------
        // WHO
        // -----------------------------------------------------------------
        RowLayout {
            Layout.preferredWidth: dialog.measure
            Layout.fillWidth: true
            spacing: Tokens.spacing.md

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.xs

                Text {
                    Layout.fillWidth: true
                    visible: !dialog.editingInfo
                    text: dialog.row.name !== undefined && dialog.row.name
                          ? dialog.row.name : "—"
                    wrapMode: Text.WordWrap
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.title
                    font.weight: Font.DemiBold
                    color: Fluent.textPrimary
                }

                Text {
                    visible: !dialog.editingInfo && text !== ""
                    text: dialog.row.phone !== undefined && dialog.row.phone
                          ? "\u200e" + dialog.row.phone : ""
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.bodyLarge
                    color: Fluent.textSecondary
                }

                /* The rep and the wilaya, read-only: the two that decide who to
                   call and how long a delivery takes. The postal and tax detail is
                   only read while writing paperwork, so it stays in the editor. */
                RowLayout {
                    Layout.fillWidth: true
                    visible: !dialog.editingInfo
                    spacing: Tokens.spacing.md

                    Text {
                        visible: text !== ""
                        text: dialog.row.contact ? dialog.row.contact : ""
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.body
                        color: Fluent.textTertiary
                    }

                    Text {
                        visible: text !== ""
                        text: dialog.row.wilaya ? dialog.row.wilaya : ""
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.body
                        color: Fluent.textTertiary
                    }

                    Item { Layout.fillWidth: true }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: dialog.editingInfo
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
                            onAccepted: dialog.saveInfo()
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
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.body
                            horizontalAlignment: TextInput.AlignLeft
                            onAccepted: dialog.saveInfo()
                        }
                    }
                }

                /*
                 * Who to actually call, and where they are.
                 *
                 * A supplier is reached through a person: the rep's name is what
                 * gets a delivery moved, and it is the thing a shop writes on the
                 * wall next to the phone. The wilaya decides who delivers when and
                 * how long a replacement takes, which is why it sits with the
                 * contact rather than with the postal detail below.
                 */
                RowLayout {
                    Layout.fillWidth: true
                    visible: dialog.editingInfo
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
                    visible: dialog.editingInfo
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
            }

            GlyphButton {
                Layout.alignment: Qt.AlignBottom
                visible: !dialog.creating && !dialog.editingInfo
                glyph: "ic_fluent_edit_20_regular"
                text: Strings.t("action.edit_info", "Edit info")
                enabled: dialog.canManage
                onClicked: {
                    dialog.editingInfo = true
                    dialog.notice = ""
                    name.forceActiveFocus()
                }
            }
        }

        // -----------------------------------------------------------------
        // THE FOUR FIGURES
        // -----------------------------------------------------------------
        CardRow {
            Layout.fillWidth: true
            visible: !dialog.creating
            minCardWidth: 230

            KpiCard {
                chipSize: 44
                minHeight: 104
                floorWidth: 230
                label: Strings.t("suppliers.col.debt", "Owed")
                value: dialog.cardText("debt")
                glyph: "ic_fluent_wallet_20_regular"
                tone: "danger"
                valueTone: dialog.cardNumber("debt_raw") > 0 ? "danger" : ""
            }

            KpiCard {
                chipSize: 44
                minHeight: 104
                floorWidth: 230
                label: Strings.t("supplier.card.paid", "Paid so far")
                value: dialog.cardText("paid_total")
                valueTooltip: dialog.cardText("paid_total_full")
                glyph: "ic_fluent_money_20_regular"
                tone: "success"
            }

            KpiCard {
                chipSize: 44
                minHeight: 104
                floorWidth: 230
                label: Strings.t("purchases.card.count", "Invoices")
                value: dialog.cardText("invoice_count")
                subtext: dialog.cardText("last_invoice") !== "—"
                         ? Strings.tf("supplier.card.last_invoice", "Last: {when}",
                                      { when: dialog.cardText("last_invoice") })
                         : ""
                glyph: "ic_fluent_receipt_20_regular"
                tone: "info"
            }

            KpiCard {
                chipSize: 44
                minHeight: 104
                floorWidth: 230
                label: Strings.t("purchases.card.total", "Purchased")
                value: dialog.cardText("purchased")
                valueTooltip: dialog.cardText("purchased_full")
                glyph: "ic_fluent_box_multiple_20_regular"
                tone: "primary"
            }
        }

        // -----------------------------------------------------------------
        // WHICH HISTORY
        // -----------------------------------------------------------------
        SectionBar {
            id: sectionBar
            Layout.fillWidth: true
            visible: !dialog.creating

            sections: [
                {
                    key: "invoices",
                    label: Strings.t("supplier.invoices", "Invoices"),
                    glyph: "ic_fluent_receipt_20_regular",
                    count: dialog.invoices.length
                },
                {
                    key: "payments",
                    label: Strings.t("supplier.payments", "Payments"),
                    glyph: "ic_fluent_money_20_regular",
                    count: dialog.payments.length
                }
            ]

            onActivated: (key) => {
                if (key !== "payments")
                    dialog.paying = false
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !dialog.creating
            currentIndex: sectionBar.currentIndex

            // -- invoices -------------------------------------------------
            ColumnLayout {
                spacing: Tokens.spacing.sm

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.sm

                    QC.TextField {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Tokens.size.controlSmall
                        placeholderText: Strings.t("supplier.invoices.search.ph",
                                                   "Search number, date or amount")
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.body
                        onTextChanged: dialog.invoicesQuery = text
                    }

                    /* A delivery is a screen of its own — lines, quantities, what
                       was paid on the spot — so this hands over to it with the
                       supplier already chosen. One dialog at a time, so this one
                       goes; the record it was showing is one row away. */
                    GlyphButton {
                        glyph: "ic_fluent_add_20_regular"
                        text: Strings.t("purchases.new", "New invoice")
                        highlighted: true
                        enabled: dialog.canManage
                        onClicked: {
                            if (dialog.workflows)
                                dialog.workflows.open("purchase_form",
                                                      { supplier_id: dialog.supplierId })
                            dialog.close()
                        }
                    }
                }

                DataTable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columns: dialog.invoiceColumns
                    model: dialog.invoiceRows
                    emptyIcon: "ic_fluent_receipt_20_regular"
                    emptyText: dialog.invoicesQuery !== ""
                               ? Strings.t("state.no_results.title", "No matches")
                               : Strings.t("supplier.no_invoices",
                                           "Nothing has been bought from this supplier yet.")
                }
            }

            // -- payments -------------------------------------------------
            ColumnLayout {
                spacing: Tokens.spacing.sm

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.sm

                    QC.TextField {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Tokens.size.controlSmall
                        placeholderText: Strings.t("customer.payments.search.ph",
                                                   "Search date or amount")
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.body
                        onTextChanged: dialog.paymentsQuery = text
                    }

                    GlyphButton {
                        glyph: "ic_fluent_money_20_regular"
                        text: Strings.t("payments.record", "Record payment")
                        highlighted: true
                        enabled: dialog.canManage && dialog.owes && !dialog.paying
                        onClicked: dialog.openPayment()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    visible: dialog.paying
                    implicitHeight: entry.implicitHeight + 2 * Tokens.spacing.md
                    radius: Tokens.radius.md
                    color: Fluent.subtleSecondary
                    border.width: 1
                    border.color: Fluent.dividerBorder

                    RowLayout {
                        id: entry
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Tokens.spacing.md
                        anchors.rightMargin: Tokens.spacing.md
                        spacing: Tokens.spacing.sm

                        Field {
                            Layout.maximumWidth: 320
                            label: Strings.t("amount.entered", "Amount")
                            required: true

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacing.xs

                                QC.TextField {
                                    id: amount
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Tokens.size.control
                                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                                    font.family: Tokens.font.family
                                    font.pixelSize: Tokens.font.bodyLarge
                                    onAccepted: dialog.pay()
                                }

                                GlyphButton {
                                    text: Strings.t("amount.all", "All")
                                    onClicked: amount.text = String(dialog.debt)
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        ColumnLayout {
                            Layout.maximumWidth: 220
                            spacing: 2

                            Text {
                                text: Strings.t("amount.remaining_after",
                                                "Left after this")
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.caption
                                font.weight: Font.DemiBold
                                color: Fluent.textSecondary
                            }

                            Text {
                                Layout.preferredHeight: Tokens.size.control
                                verticalAlignment: Text.AlignVCenter
                                text: "\u200e" + dialog.money(dialog.remaining)
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.bodyLarge
                                font.weight: Font.DemiBold
                                color: dialog.remaining > 0 ? Tokens.danger
                                                            : Tokens.success
                            }
                        }

                        GlyphButton {
                            Layout.alignment: Qt.AlignBottom
                            glyph: "ic_fluent_checkmark_20_regular"
                            text: Strings.t("action.confirm", "Confirm")
                            highlighted: true
                            enabled: dialog.canManage && dialog.validPayment
                            onClicked: dialog.pay()
                        }

                        GlyphButton {
                            Layout.alignment: Qt.AlignBottom
                            glyph: "ic_fluent_dismiss_20_regular"
                            outlined: true
                            text: Strings.t("action.cancel", "Cancel")
                            onClicked: {
                                amount.text = ""
                                error.text = ""
                                dialog.paying = false
                            }
                        }
                    }
                }

                DataTable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columns: dialog.paymentColumns
                    model: dialog.paymentRows
                    emptyIcon: "ic_fluent_money_20_regular"
                    emptyText: dialog.paymentsQuery !== ""
                               ? Strings.t("state.no_results.title", "No matches")
                               : Strings.t("supplier.no_payments",
                                           "Nothing has been paid to this supplier.")
                }
            }
        }

        // -----------------------------------------------------------------
        // FEEDBACK AND COMMIT
        // -----------------------------------------------------------------
        Text {
            id: error
            Layout.fillWidth: true
            visible: text !== ""
            wrapMode: Text.WordWrap
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.caption
            color: Tokens.danger
        }

        Text {
            Layout.fillWidth: true
            visible: dialog.notice !== "" && error.text === ""
            text: dialog.notice
            wrapMode: Text.WordWrap
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.caption
            font.weight: Font.DemiBold
            color: Tokens.success
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.sm

            Item { Layout.fillWidth: true }

            GlyphButton {
                glyph: "ic_fluent_dismiss_20_regular"
                outlined: true
                text: dialog.editingInfo ? Strings.t("action.cancel", "Cancel")
                                         : Strings.t("action.close", "Close")
                onClicked: {
                    if (dialog.creating || !dialog.editingInfo)
                        dialog.close()
                    else
                        dialog.cancelInfo()
                }
            }

            GlyphButton {
                visible: dialog.editingInfo
                glyph: "ic_fluent_save_20_regular"
                text: Strings.t("action.save", "Save")
                highlighted: true
                enabled: dialog.canManage && name.text.trim() !== ""
                onClicked: dialog.saveInfo()
            }
        }
    }
}

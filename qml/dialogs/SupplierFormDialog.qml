import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * One supplier: what the shop owes them, the deliveries behind it, what has been
 * paid.
 *
 * The customer screen with the sign reversed, deliberately down to the layout: a
 * supplier account behaves the way a customer account does, and an operator who
 * has learned one should not have to learn the other. What differs is what the
 * first section lists (invoices in, not sales out) and where its action goes (the
 * purchase form, not the till).
 *
 * A RECORD, NOT A FORM
 *
 * The details used to be editable in place here, shown or hidden by a flag — so
 * pressing Edit hid the balance that was the reason for pressing it, and the footer's
 * Save meant nothing the rest of the time. They live in `SupplierEditDialog` now,
 * which opens over this record; the suppliers page opens it directly when there is
 * no record yet.
 *
 * WHY PAYING IS STILL IN THE PAYMENTS SECTION
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
    /* The lists on this record hold documents other screens own: a delivery note is
       opened by the purchase workflow and printed by the printer, a payment is deleted
       by the payments register. This record asks them; it owns neither. */
    readonly property var printer: (typeof app !== "undefined" && app)
                                   ? app.printing : null
    readonly property var paymentsCtrl: (typeof app !== "undefined" && app)
                                        ? app.payments : null
    /* Deliveries are written by the purchase form, which this record opens over
       itself: the invoice list and the four figures at the top are what change when
       it saves. */
    readonly property var purchasesCtrl: (typeof app !== "undefined" && app)
                                         ? app.purchases : null

    readonly property int supplierId: context && context.supplier_id
                                      ? context.supplier_id : 0

    readonly property bool canManage: session ? session.can("purchases.manage") : true

    preferredWidth: 1240
    preferredHeight: 900

    /* The generic word, not the name — the name is the record's own first line, at
       title size. Same reasoning as the customer record. */
    title: Strings.t("suppliers.record_title", "Supplier")

    // =====================================================================
    // STATE
    // =====================================================================
    property var row: ({})

    readonly property var cards: row.cards !== undefined ? row.cards : ({})
    readonly property var invoices: row.invoices !== undefined ? row.invoices : []
    readonly property var payments: row.payments !== undefined ? row.payments : []

    readonly property real debt: row.debt !== undefined ? row.debt : 0
    readonly property bool owes: debt > 0

    property bool paying: false

    property string invoicesQuery: ""
    property string paymentsQuery: ""

    /* Modal: the page's ToastHost is behind the scrim, so what happened is said
       here or not at all. */
    property string notice: ""

    readonly property int measure: 560

    /* Whether this record can go: the same three conditions `delete_supplier`
       enforces — no delivery, no payment, nothing owed — read off the payload already
       on screen. Same reasoning as the customer record. */
    readonly property bool deletable: supplierId > 0 && invoices.length === 0
                                      && payments.length === 0 && !(debt > 0.005)

    // =====================================================================
    // DATA
    // =====================================================================
    Component.onCompleted: {
        reload()
        if (context && context.section) {
            sectionBar.select(context.section)
            if (context.section === "payments" && canManage && owes)
                openPayment()
        }
    }

    function reload() {
        if (ctrl && supplierId)
            row = ctrl.supplier(supplierId) || ({})
    }

    function openPayment() {
        paying = true
        amount.forceActiveFocus()
    }

    // -- the two lists' row actions ---------------------------------------
    /*
     * A row here is a document, handed to whoever owns it. Each of these says
     * something when it cannot act: an icon that answers a press with silence cannot
     * be told apart from a broken one.
     */
    function invoiceAt(row) {
        return (row >= 0 && row < invoiceRows.length) ? invoiceRows[row] : null
    }

    function paymentAt(row) {
        return (row >= 0 && row < paymentRows.length) ? paymentRows[row] : null
    }

    function openInvoice(row) {
        var invoice = invoiceAt(row)
        if (!invoice)
            return
        if (!workflows || !workflows.open) {
            error.text = Strings.t("workflow.not_ready",
                                   "That screen is not part of this build yet.")
            return
        }
        workflows.open("purchase_form", { invoice_id: invoice.id })
    }

    function printInvoice(row) {
        var invoice = invoiceAt(row)
        if (!invoice)
            return
        if (!printer) {
            error.text = Strings.t("workflow.not_ready",
                                   "That screen is not part of this build yet.")
            return
        }
        printer.printPurchase(invoice.id)
        notice = Strings.t("sales.printed", "Sent to the printer")
    }

    function askDeletePayment(row) {
        var payment = paymentAt(row)
        if (!payment || !canManage)
            return
        confirmDeletePayment.paymentId = payment.id
        confirmDeletePayment.amount = payment.amount_text
        confirmDeletePayment.when = payment.when
        confirmDeletePayment.open()
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
        },
        /* A delivery note is a record with an editor, so the pen opens it — there is
           no separate read-only view of the same thing. Print is what the rep asks
           for at the counter. */
        {
            key: "actions",
            actions: [
                { id: "edit", enabled: dialog.canManage },
                { id: "print" }
            ]
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
        },
        /* No pen: a payment is not edited, because a corrected receipt is a different
           receipt. It is deleted — which puts the balance back — and taken again. */
        {
            key: "actions",
            actions: [
                { id: "delete", enabled: dialog.canManage }
            ]
        }
    ]

    // =====================================================================
    // BRIDGE SIGNALS
    // =====================================================================
    Connections {
        target: dialog.ctrl
        ignoreUnknownSignals: true

        /* The editor closes itself on a save; this is the record catching up. */
        function onSaved(supplier) {
            dialog.notice = Strings.t("customers.info_saved", "Details saved.")
            dialog.reload()
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

    /* The payments register refuses out loud, on whichever screen asked it to: this
       record can now delete a payment, so it has to be able to hear "no". */
    Connections {
        target: dialog.paymentsCtrl
        ignoreUnknownSignals: true

        function onRejected(message) {
            error.text = message
        }

        /* A deleted payment moves this supplier's balance, and the figures at the top
           of this record are the reason it is open. */
        function onInvalidated() {
            dialog.reload()
        }
    }

    /* A delivery saved in the form above this one. */
    Connections {
        target: dialog.purchasesCtrl
        ignoreUnknownSignals: true

        function onInvalidated() {
            dialog.reload()
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
                    text: dialog.row.name !== undefined && dialog.row.name
                          ? dialog.row.name : "—"
                    wrapMode: Text.WordWrap
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.title
                    font.weight: Font.DemiBold
                    color: Fluent.textPrimary
                }

                Text {
                    visible: text !== ""
                    text: dialog.row.phone !== undefined && dialog.row.phone
                          ? "\u200e" + dialog.row.phone : ""
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.bodyLarge
                    color: Fluent.textSecondary
                }

                /* The rep and the wilaya: the two that decide who to call and how
                   long a delivery takes. The postal and tax detail is only read
                   while writing paperwork, so it stays in the editor. */
                RowLayout {
                    Layout.fillWidth: true
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
            }

            /* What can be done to the record itself. The sections below own the
               errands — enter a delivery, pay the rep — because each acts on a row in
               the list under it; these two act on the supplier. */
            ColumnLayout {
                Layout.alignment: Qt.AlignBottom
                spacing: Tokens.spacing.xs

                GlyphButton {
                    Layout.fillWidth: true
                    glyph: "ic_fluent_edit_20_regular"
                    text: Strings.t("action.edit_details", "Edit details")
                    enabled: dialog.canManage
                    onClicked: {
                        dialog.notice = ""
                        editor.edit(dialog.row)
                    }
                }

                /* Dark until the record is empty: `delete_supplier` allows only a
                   supplier with no delivery, no payment and nothing owed, and the
                   tooltip says so rather than a refusal after the press. */
                GlyphButton {
                    Layout.fillWidth: true
                    glyph: "ic_fluent_delete_20_regular"
                    text: Strings.t("action.delete", "Delete")
                    enabled: dialog.canManage && dialog.deletable
                    icon.color: enabled ? Tokens.danger : Fluent.textDisabled
                    tooltip: dialog.deletable
                             ? ""
                             : Strings.t("suppliers.delete.refused",
                                         "This supplier has deliveries, payments or a balance — the record stays so those documents keep the name on them.")
                    onClicked: {
                        dialog.notice = ""
                        confirmDelete.open()
                    }
                }
            }
        }

        // -----------------------------------------------------------------
        // THE FOUR FIGURES
        // -----------------------------------------------------------------
        CardRow {
            Layout.fillWidth: true
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
                            /* The delivery form opens OVER this record and the record
                               stays: a new invoice for this supplier is read against
                               what they have already delivered, which is the list
                               underneath. The Connections on `purchasesCtrl` bring the
                               figures up to date when it is saved. */
                            if (dialog.workflows)
                                dialog.workflows.open("purchase_form",
                                                      { supplier_id: dialog.supplierId })
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
                    /* Double-click opens the note, the same gesture every other table
                       in this app answers to. */
                    onRowActivated: (row) => dialog.openInvoice(row)
                    onActionTriggered: (row, action) => {
                        if (action === "edit")
                            dialog.openInvoice(row)
                        else if (action === "print")
                            dialog.printInvoice(row)
                    }
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

                                NumberField {
                                    id: amount
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Tokens.size.control
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
                    onActionTriggered: (row, action) => {
                        if (action === "delete")
                            dialog.askDeletePayment(row)
                    }
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
                text: Strings.t("action.close", "Close")
                onClicked: dialog.close()
            }
        }
    }

    // =====================================================================
    // THE DETAILS, IN A FORM OF THEIR OWN
    // =====================================================================
    SupplierEditDialog {
        id: editor
        onCommitted: error.text = ""
    }

    /* Deleting the record itself. Only reachable while `deletable`, so this states
       what goes rather than arguing about whether it may. */
    ConfirmDialog {
        id: confirmDelete

        title: Strings.t("suppliers.delete.title", "Delete this supplier?")
        body: Strings.t("suppliers.delete.body",
                        "Nothing is recorded against this supplier, so nothing is lost with it.")

        facts: [
            {
                label: Strings.t("supplier.name", "Supplier name"),
                value: dialog.row.name !== undefined ? dialog.row.name : "",
                tone: ""
            },
            {
                label: Strings.t("supplier.phone", "Phone"),
                value: dialog.row.phone !== undefined ? dialog.row.phone : "",
                tone: ""
            }
        ]

        confirmText: Strings.t("suppliers.delete.action", "Delete the supplier")

        onConfirmed: {
            if (dialog.ctrl)
                dialog.ctrl.remove(dialog.supplierId)
            dialog.close()
        }
    }

    /* Deleting a payment is not a tidy-up: what it settled goes back on the balance.
       So the confirmation names the amount and the date — the same sentence the
       payments register uses, because it is the same act on the same record. */
    FluentDialog {
        id: confirmDeletePayment

        property int paymentId: -1
        property string amount: ""
        property string when: ""
        readonly property int measure: 460

        modal: true
        title: Strings.t("payments.delete.title", "Delete this payment?")
        standardButtons: QC.Dialog.Yes | QC.Dialog.No

        onAccepted: {
            if (!dialog.paymentsCtrl) {
                error.text = Strings.t("workflow.not_ready",
                                       "That screen is not part of this build yet.")
                return
            }
            /* `kind` tells the register which table the id belongs to: supplier and
               customer payments number themselves independently. */
            dialog.paymentsCtrl.remove(confirmDeletePayment.paymentId, "supplier")
            dialog.reload()
        }

        contentItem: Column {
            spacing: Tokens.spacing.sm

            Text {
                width: confirmDeletePayment.measure
                text: Strings.t("payments.delete.body",
                                "The amount is added back to the debt it settled.")
                wrapMode: Text.WordWrap
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                color: Fluent.textPrimary
            }

            Text {
                width: confirmDeletePayment.measure
                text: confirmDeletePayment.when + "  ·  \u200e" + confirmDeletePayment.amount
                wrapMode: Text.WordWrap
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                font.weight: Font.DemiBold
                color: Fluent.textPrimary
            }
        }
    }
}

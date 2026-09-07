import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * One customer: who they are, what they owe, what they bought, what they paid.
 *
 *   ┌────────────────────────────────────────────────────────────────┐
 *   │ Ahmed Belkacem                              [ Edit details ]   │
 *   │ 0661 20 41 88                                                  │
 *   │ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐                    │
 *   │ │ DEBT   │ │ PAID   │ │ SALES  │ │ BOUGHT │                    │
 *   │ │ 12 400 │ │ 38 000 │ │   17   │ │ 50 400 │                    │
 *   │ └────────┘ └────────┘ └────────┘ └────────┘                    │
 *   │ ( Sales 17 )( Payments 4 )                                     │
 *   │ [ search ......................... ]        [ Start a sale ]    │
 *   │ PIN-0166  27/08 14:02  Debt      12 480,00        2 480,00     │
 *   │ ...                                                            │
 *   └────────────────────────────────────────────────────────────────┘
 *
 * A RECORD, NOT A FORM
 *
 * The details used to be editable in place here: the same fields, shown or hidden by
 * a flag, with a Save in the footer that meant nothing the rest of the time. Two
 * things were wrong with it. The figures an operator opened the record to read
 * vanished the moment they pressed Edit — and they pressed Edit *because* of those
 * figures. And "new customer" was this same 1240px screen with the history, the
 * cards and the sections all switched off, which is not a form, it is a record with
 * the record missing.
 *
 * So the details live in `CustomerEditDialog`, which opens over this one when
 * something needs correcting and on its own from the customers page when there is
 * nothing to correct yet.
 *
 * WHY THE EDITOR IS DECLARED HERE AND NOT ROUTED
 *
 * DialogHost shows one dialog at a time, so opening the editor through `workflows`
 * would close this record and leave the operator nowhere to come back to. It is a
 * child of this dialog instead, which is what the delete confirmations on the pages
 * already do.
 *
 * WHY THE PAYMENT IS TAKEN HERE AND NOT IN A DIALOG OF ITS OWN
 *
 * Same reason, one step further: a payment is taken *against* a balance that is on
 * this screen. The panel below is three fields inside the section that already lists
 * what they produce, and it keeps the balance in view while the money is counted.
 */
AppDialog {
    id: dialog

    property var context: ({})

    // =====================================================================
    // BRIDGE
    // =====================================================================
    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.customers : null
    readonly property var session: (typeof app !== "undefined" && app) ? app.session : null
    readonly property var till: (typeof app !== "undefined" && app) ? app.pos : null
    /* The two lists on this record are documents belonging to other screens: a sale
       is opened by the sales workflow and printed by the printer, and a payment is
       deleted by the payments register. This record asks them; it owns neither. */
    readonly property var workflows: (typeof app !== "undefined" && app)
                                     ? app.workflows : null
    readonly property var printer: (typeof app !== "undefined" && app)
                                   ? app.printing : null
    readonly property var paymentsCtrl: (typeof app !== "undefined" && app)
                                        ? app.payments : null
    /* Sales are written elsewhere — the till, and the ticket this record opens over
       itself. Either changes the history listed here and the four figures above it. */
    readonly property var salesCtrl: (typeof app !== "undefined" && app)
                                     ? app.sales : null

    readonly property int customerId: context && context.customer_id
                                      ? context.customer_id : 0

    /* Reading a customer needs `customers.view`, which is what opened this. Writing
       needs the manage right, and that is gated on the button that opens the editor
       rather than by refusing to open the record: an operator who may look at an
       account should see it, not a refusal where the record was. */
    readonly property bool canManage: session ? session.can("customers.manage") : true
    readonly property bool canSell: session ? session.can("pos.sell") : true
    /* The same right the sales page's pen asks for: rewriting a completed sale
       moves stock and this customer's debt, so `sales.edit` is the gate. */
    readonly property bool canEditSales: session ? session.can("sales.edit") : true

    preferredWidth: 1240
    preferredHeight: 900

    /* The generic word, not the name.
     *
     * The name is the first line of the record itself, at title size, with the phone
     * and the chips attached to it — so putting it here as well printed it twice,
     * forty pixels apart, in two different sizes. The dialog's own title says which
     * KIND of thing is open; the record says which one. */
    title: Strings.t("customers.record_title", "Customer")

    // =====================================================================
    // STATE
    // =====================================================================
    property var row: ({})

    readonly property var cards: row.cards !== undefined ? row.cards : ({})
    readonly property var sales: row.sales !== undefined ? row.sales : []
    readonly property var payments: row.payments !== undefined ? row.payments : []

    readonly property real debt: row.debt !== undefined ? row.debt : 0
    readonly property bool owes: debt > 0

    /* The payment panel, folded away until there is a payment to take. Opened by
        its own button, and opened for the operator when the row action that brought
        them here was "take a payment". While a payment is being CORRECTED it holds
        that payment instead: `editingPayment` is the row from the list above, and
        the panel answers through the payments register rather than by recording. */
    property bool paying: false
    property var editingPayment: null

    /* What a correction is measured against. The payment being corrected was
       already taken, so the account can absorb a figure up to the debt PLUS
       that payment: correcting 500 to 700 on a 300 debt is "they actually paid
       700 of the 800 they owed", which leaves 100 — not an overpayment. */
    readonly property real correctedBase: editingPayment
                                         ? Number(editingPayment.amount) : 0

    property string salesQuery: ""
    property string paymentsQuery: ""

    /* What just happened, in the dialog rather than in a toast: this is modal, so
       the page's ToastHost is behind the scrim and unreadable. */
    property string notice: ""

    readonly property int measure: 560

    /*
     * Whether this record can be deleted at all.
     *
     * The same three conditions `delete_customer` enforces — no sale, no payment, no
     * debt — read off the payload that is already on screen rather than asked for
     * again. A bin that is dark until the account is empty is the rule stated in
     * advance; a bin that always looks pressable and answers with a refusal is the
     * rule stated too late.
     */
    readonly property bool deletable: {
        var sales = row.sales !== undefined ? row.sales : []
        var payments = row.payments !== undefined ? row.payments : []
        return customerId > 0 && sales.length === 0 && payments.length === 0
               && !(row.debt > 0.005)
    }

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
        if (ctrl && customerId)
            row = ctrl.customer(customerId) || ({})
    }

    /* Which of the three counters this customer buys over — read off the record,
       for the chip beside the name. Changing it is the editor's business. */
    readonly property string levelKey: row.price_level !== undefined && row.price_level
                                       ? row.price_level : "retail"

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

    function openPayment() {
        /* A new payment, never a leftover correction: the button and the pen
           are two different questions, and the panel has to know which one it
           is answering. */
        editingPayment = null
        amount.text = ""
        paying = true
        amount.forceActiveFocus()
    }

    // -- the two lists' row actions ---------------------------------------
    /*
     * A row here is a document, and each of these hands it to whoever owns it.
     *
     * They are wired to say something when they cannot act, rather than nothing: an
     * icon that answers a press with silence is indistinguishable from a broken one,
     * and that is exactly how the pen on the sales page came to be reported as dead.
     */
    function saleAt(row) {
        return (row >= 0 && row < salesRows.length) ? salesRows[row] : null
    }

    function paymentAt(row) {
        return (row >= 0 && row < paymentRows.length) ? paymentRows[row] : null
    }

    function openSale(row) {
        var sale = saleAt(row)
        if (!sale)
            return
        if (!workflows || !workflows.open) {
            error.text = Strings.t("workflow.not_ready",
                                   "That screen is not part of this build yet.")
            return
        }
        workflows.open("sale_transaction", { sale_id: sale.id })
    }

    /*
     * The invoice is corrected on the TILL, exactly as the sales page's pen
     * does it — the same screen it was rung up on, the same gestures, and the
     * same refusal when the till is holding a cart that has not been dealt
     * with.
     *
     * Load first, THEN navigate: loadSale refuses a busy cart, and being
     * thrown onto the till with the old cart still on it and a refusal behind
     * the page is the one outcome to avoid. The refusal arrives on
     * `pos.rejected`, which the Connections below put into this dialog's own
     * error line — modal, so the page's toast is behind the scrim.
     */
    function editSale(row) {
        var sale = saleAt(row)
        if (!sale)
            return
        if (!till) {
            error.text = Strings.t("workflow.not_ready",
                                   "That screen is not part of this build yet.")
            return
        }
        if (till.loadSale(sale.id)) {
            Destinations.request("pos")
            dialog.close()
        }
    }

    function printSale(row) {
        var sale = saleAt(row)
        if (!sale)
            return
        if (!printer) {
            error.text = Strings.t("workflow.not_ready",
                                   "That screen is not part of this build yet.")
            return
        }
        /* Returns immediately: a thermal printer can be missing or out of paper, and
           the answer arrives on the printer's own signals. */
        printer.printSale(sale.id)
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

    /* The pen on a payment row: the same panel that takes one, holding the row
       it is going to correct. The amount field opens on the recorded figure,
       selected, so the first keystroke replaces it — the panel's own rule for a
       figure being corrected. */
    function askEditPayment(row) {
        var payment = paymentAt(row)
        if (!payment || !canManage)
            return
        editingPayment = payment
        paying = true
        amount.text = String(payment.amount)
        amount.forceActiveFocus()
        amount.selectAll()
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
    /* While correcting, the old figure is returned to the account first —
       that is what "the balance moves by the difference" means here, and it is
       why the ceiling and the remainder both add `correctedBase`. */
    readonly property real remaining: Math.max(0, debt + correctedBase - entered)
    readonly property bool validPayment: entered > 0
                                         && entered <= debt + correctedBase

    function pay() {
        error.text = ""
        notice = ""
        if (!validPayment) {
            error.text = entered > debt + correctedBase
                         ? Strings.t("payments.over_debt",
                                     "That is more than this customer owes.")
                         : Strings.t("amount.error", "Enter a valid amount.")
            amount.forceActiveFocus()
            return
        }
        /* A correction is the register's business, not this controller's: the
           register owns the payment tables for both kinds of party, and it is
           what answers with the new balance. */
        if (editingPayment) {
            if (paymentsCtrl)
                paymentsCtrl.update(editingPayment.id, "customer", amount.text)
            return
        }
        if (ctrl)
            ctrl.recordPayment(customerId, amount.text)
    }

    // -- the two histories, filtered --------------------------------------
    /*
     * Filtering in QML, not in Python.
     *
     * Both lists arrived whole with the record — a customer has tens of sales, not
     * the thousands the catalogue has products — so a round trip per keystroke
     * would buy nothing and cost the debounce that would then be needed. `search`
     * is therefore instant here, which is the behaviour a search box over a list
     * already on screen should have.
     */
    function matches(haystack, needle) {
        return String(haystack).toLowerCase().indexOf(needle) >= 0
    }

    readonly property var salesRows: {
        var query = salesQuery.trim().toLowerCase()
        if (query === "")
            return sales
        var out = []
        for (var i = 0; i < sales.length; i++) {
            var sale = sales[i]
            if (matches(sale.number, query) || matches(sale.when, query)
                    || matches(sale.payment, query)
                    || matches(sale.total_text, query))
                out.push(sale)
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
    readonly property var salesColumns: [
        {
            key: "number",
            header: Strings.t("sales.col.number", "Number"),
            width: 190,
            ltr: true
        },
        {
            key: "when",
            header: Strings.t("sales.col.time", "Date"),
            width: 240,
            ltr: true
        },
        {
            key: "payment",
            header: Strings.t("sales.col.payment", "Payment"),
            width: 160,
            badge: true,
            /* Coloured by how it was paid, not by where the column is: a debt sale
               is the one that put the figure on this account. */
            tone: function (r) {
                return r.payment_type === "cash" ? "success"
                     : r.payment_type === "debt" ? "danger"
                     : r.payment_type === "partial" ? "warning" : ""
            }
        },
        {
            key: "total_text",
            header: Strings.t("sales.col.total", "Total"),
            numeric: true,
            width: 190,
            ltr: true
        },
        {
            key: "due_text",
            header: Strings.t("purchases.col.due", "Outstanding"),
            numeric: true,
            width: 190,
            ltr: true,
            tone: function (r) { return r.owes ? "danger" : "" }
        },
        /* A row on this list is a ticket: look at it, correct it on the till it
           was rung up on, or hand the customer a copy of it. All three were the
           things an operator asked this record for and could not do without
           leaving it — the pen is the sales page's own act, same right, same
           screen, arrived at from the history that names it. */
        {
            key: "actions",
            actions: [
                { id: "view" },
                { id: "edit", enabled: dialog.canEditSales },
                { id: "print" }
            ]
        }
    ]

    readonly property var paymentColumns: [
        {
            key: "when",
            header: Strings.t("sales.col.time", "Date"),
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
        /* The pen corrects the amount in place — the debt moves by the
           difference, and the row keeps its date and its place in the history.
           The bin stays for the payment that should not exist at all, which is
           a different question from "the figure was typed wrong". */
        {
            key: "actions",
            actions: [
                { id: "edit", enabled: dialog.canManage },
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

        /* The editor closes itself on a save; this is the record catching up with
           what it just wrote. */
        function onSaved(customer) {
            dialog.notice = Strings.t("customers.info_saved", "Details saved.")
            dialog.reload()
        }

        function onPaid(result) {
            /* Stays open with the new balance — a customer settling an account
                often pays against two tickets in one visit, and reopening the
                record to do the second is a step for nothing. */
            amount.text = ""
            dialog.paying = false
            dialog.editingPayment = null
            dialog.reload()
            dialog.notice = Strings.tf("payments.recorded",
                                       "Payment recorded — debt now {debt}",
                                       { debt: result.debt_text })
        }

        function onRejected(message) {
            error.text = message
        }

        /* Another screen moved this account — a sale on the till, a payment on the
           payments page. The figures here are the reason the dialog is open. */
        function onInvalidated() {
            dialog.reload()
        }
    }

    /* The payments register refuses out loud, on whichever screen asked it to: this
        record can now correct and delete a payment, so it has to be able to hear
        "no" — and it hears "done" the same way, because a correction is the
        register's write, not this controller's. */
    Connections {
        target: dialog.paymentsCtrl
        ignoreUnknownSignals: true

        function onRejected(message) {
            error.text = message
        }

        function onUpdated(result) {
            /* Gated on the panel being open in correct mode: the register
               reports every payment corrected anywhere, and this dialog is
               modal — but a plain guard is cheaper than an argument about
               what can happen behind a scrim. */
            if (!dialog.visible || dialog.editingPayment === null)
                return
            amount.text = ""
            dialog.editingPayment = null
            dialog.paying = false
            dialog.reload()
            dialog.notice = Strings.tf("payments.corrected",
                                       "Payment corrected — debt now {debt}",
                                       { debt: result.debt_text })
        }

        /* A payment moved this account — the register deletes and corrects as
           well as records — and the figures at the top are the reason this
           record is open. */
        function onInvalidated() {
            dialog.reload()
        }
    }

    /* The till's refusals while this record asked it to hold a sale for
       rewriting: `loadSale` says "finish or void the current cart first", and
       that sentence has to land somewhere the operator can read it — modal, so
       the page's toast is behind the scrim. */
    Connections {
        target: dialog.till
        ignoreUnknownSignals: true

        function onRejected(message) {
            if (dialog.visible)
                error.text = message
        }
    }

    /* A ticket opened from the list above stays open OVER this record, and a return
       taken on it changes what this history says. Catch up rather than show what was
       true when the record opened. */
    Connections {
        target: dialog.salesCtrl
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

                // -- who they are, as the record has it
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

                    /*
                     * The rest of the record on one line.
                     *
                     * Wilaya, price level and credit ceiling — the three that change
                     * what happens at the till, so they belong beside the name rather
                     * than behind the edit button. The postal detail (address, email,
                     * NIF, RC) is only ever read while writing an invoice, and lives
                     * in the editor.
                     */
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.md

                        Text {
                            visible: text !== ""
                            text: dialog.row.wilaya ? dialog.row.wilaya : ""
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.body
                            color: Fluent.textTertiary
                        }

                        Rectangle {
                            visible: dialog.levelKey !== "retail"
                            implicitWidth: levelChip.implicitWidth + Tokens.spacing.md
                            implicitHeight: levelChip.implicitHeight + Tokens.spacing.xs
                            radius: Tokens.radius.pill
                            color: Tokens.infoTint

                            Text {
                                id: levelChip
                                anchors.centerIn: parent
                                text: dialog.levels[dialog.levelIndex(dialog.levelKey)].label
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.caption
                                font.weight: Font.DemiBold
                                color: Tokens.info
                            }
                        }

                        Text {
                            visible: dialog.row.credit_limit > 0
                            text: Strings.tf("customer.limit_is", "Limit {amount}",
                                             { amount: dialog.money(dialog.row.credit_limit) })
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.caption
                            color: Fluent.textTertiary
                        }

                        Item { Layout.fillWidth: true }
                    }


            }

            /*
             * What can be done to the record itself, beside the record.
             *
             * The two sections below own the errands — start a sale, take a payment,
             * open an invoice — because each of those acts on a row in the list under
             * it. These two act on the customer, so they belong to the header: the
             * details are corrected in a form over this dialog, and the record itself
             * can go when there is nothing recorded against it.
             *
             * Both gated on the manage right: an operator who may read an account can
             * open it and cannot change it.
             */
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

                /*
                 * Deleting is offered, and refused, on the spot.
                 *
                 * `delete_customer` allows it only for a record with no sale, no payment
                 * and no debt — a duplicate or a typo. Those three facts are already on
                 * this screen, so the button knows the answer before it is pressed and
                 * says it in the tooltip rather than letting the operator press a bin
                 * and read a refusal. Nothing is ever detached: a sale that lost its
                 * customer is a debt nobody owes.
                 */
                GlyphButton {
                    Layout.fillWidth: true
                    glyph: "ic_fluent_delete_20_regular"
                    text: Strings.t("action.delete", "Delete")
                    enabled: dialog.canManage && dialog.deletable
                    icon.color: enabled ? Tokens.danger : Fluent.textDisabled
                    tooltip: dialog.deletable
                             ? ""
                             : Strings.t("customers.delete.refused",
                                         "This customer has sales, payments or a debt — the record stays so those documents keep the name on them.")
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
        /* Compact cards: the same KpiCard the customers page opens with, sized for
           the room left above a table. The value keeps its 34px, because being
           readable across a counter is the whole reason these are cards and not a
           row of labels. */
        CardRow {
            Layout.fillWidth: true
            minCardWidth: 230

            KpiCard {
                chipSize: 44
                minHeight: 104
                floorWidth: 230
                label: Strings.t("select_customer.col.debt", "Debt")
                value: dialog.cardText("debt")
                glyph: "ic_fluent_wallet_20_regular"
                tone: "danger"
                valueTone: dialog.cardNumber("debt_raw") > 0 ? "danger" : ""
            }

            KpiCard {
                chipSize: 44
                minHeight: 104
                floorWidth: 230
                label: Strings.t("customer.card.paid", "Paid so far")
                value: dialog.cardText("paid_total")
                valueTooltip: dialog.cardText("paid_total_full")
                glyph: "ic_fluent_money_20_regular"
                tone: "success"
            }

            KpiCard {
                chipSize: 44
                minHeight: 104
                floorWidth: 230
                label: Strings.t("sales.card.count", "Sales")
                value: dialog.cardText("sales_count")
                subtext: dialog.cardText("last_sale") !== "—"
                         ? Strings.tf("customer.card.last_sale", "Last: {when}",
                                      { when: dialog.cardText("last_sale") })
                         : ""
                glyph: "ic_fluent_receipt_money_20_regular"
                tone: "info"
            }

            KpiCard {
                chipSize: 44
                minHeight: 104
                floorWidth: 230
                label: Strings.t("sales.card.total", "Total bought")
                value: dialog.cardText("sales_total")
                valueTooltip: dialog.cardText("sales_total_full")
                glyph: "ic_fluent_cart_20_regular"
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
                    key: "sales",
                    label: Strings.t("customers.sales_history", "Sales"),
                    glyph: "ic_fluent_receipt_money_20_regular",
                    count: dialog.sales.length
                },
                {
                    key: "payments",
                    label: Strings.t("customers.payments_history", "Payments"),
                    glyph: "ic_fluent_money_20_regular",
                    count: dialog.payments.length
                }
            ]

            /* Leaving the payments section folds its payment panel away again, so
                coming back to it is a decision rather than a leftover — and a
                correction is folded away with it: the row it was aimed at is on
                the section being left. */
            onActivated: (key) => {
                if (key !== "payments") {
                    dialog.paying = false
                    dialog.editingPayment = null
                    amount.text = ""
                }
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: sectionBar.currentIndex

            // -- sales ----------------------------------------------------
            ColumnLayout {
                spacing: Tokens.spacing.sm

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.sm

                    QC.TextField {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Tokens.size.controlSmall
                        placeholderText: Strings.t("customer.sales.search.ph",
                                                   "Search number, date or amount")
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.body
                        onTextChanged: dialog.salesQuery = text
                    }

                    /* The next sale is made at the till, not here — so this puts
                       the customer on the cart and goes there, which is the whole
                       of "add a sale for this customer". */
                    GlyphButton {
                        glyph: "ic_fluent_cart_20_regular"
                        text: Strings.t("customers.start_sale", "Start a sale")
                        highlighted: true
                        enabled: dialog.canSell
                        onClicked: {
                            if (dialog.till)
                                dialog.till.setCustomer(dialog.customerId)
                            Destinations.request("pos")
                            dialog.close()
                        }
                    }
                }

                DataTable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columns: dialog.salesColumns
                    model: dialog.salesRows
                    emptyIcon: "ic_fluent_receipt_20_regular"
                    emptyText: dialog.salesQuery !== ""
                               ? Strings.t("state.no_results.title", "No matches")
                               : Strings.t("customer.no_sales",
                                           "This customer has not bought anything yet.")
                    /* Double-click opens the ticket, the same gesture every other
                       table in this app answers to. */
                    onRowActivated: (row) => dialog.openSale(row)
                    onActionTriggered: (row, action) => {
                        if (action === "view")
                            dialog.openSale(row)
                        else if (action === "edit")
                            dialog.editSale(row)
                        else if (action === "print")
                            dialog.printSale(row)
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
                        /* Nothing owed is nothing to pay: the database clamps a
                           debt at zero rather than turning an overpayment into
                           credit, so a payment against a settled account has no
                           meaning to record. */
                        enabled: dialog.canManage && dialog.owes && !dialog.paying
                        onClicked: dialog.openPayment()
                    }
                }

                // The panel, in the section that lists what it produces.
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
                            /* The word says which question the panel is
                               answering: taking money, or correcting the figure
                               that was taken. */
                            label: dialog.editingPayment
                                   ? Strings.t("payments.edit.amount",
                                               "Corrected amount")
                                   : Strings.t("amount.entered", "Amount")
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

                                /* Settling in full is the common case, and
                                   retyping six figures at a counter is where
                                   mistakes come from. While correcting, "all"
                                   is the debt plus the payment being corrected:
                                   the figure that leaves the account at
                                   zero. */
                                GlyphButton {
                                    text: Strings.t("amount.all", "All")
                                    onClicked: amount.text = String(
                                        dialog.debt + dialog.correctedBase)
                                }
                            }
                        }

                        /* What is being corrected, named: the panel sits below
                           the list, and "which payment am I rewriting" is a
                           question a number field cannot answer. The sentence
                           also states the rule — replaces, not adds — which is
                           the one mistake a correction panel exists to
                           prevent. Sized to its content rather than filled:
                           the filler below keeps the column and the buttons
                           where they are in either mode. */
                        Text {
                            visible: dialog.editingPayment !== null
                            text: Strings.tf("payments.edit.hint",
                                             "Replaces {amount} — the balance moves by the difference.",
                                             { amount: dialog.editingPayment
                                               ? dialog.editingPayment.amount_text
                                               : "" })
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.caption
                            color: Fluent.textTertiary
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
                                dialog.editingPayment = null
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
                               : Strings.t("customer.no_payments",
                                           "Nothing has been paid against this account.")
                    onActionTriggered: (row, action) => {
                        if (action === "edit")
                            dialog.askEditPayment(row)
                        else if (action === "delete")
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
    CustomerEditDialog {
        id: editor

        /* The record catches up through the controller's `saved` signal, which this
           dialog is already listening to — so there is nothing to do here but keep
           the last refusal from lingering over a successful save. */
        onCommitted: error.text = ""
    }

    /* Deleting a payment is not a tidy-up: the debt it settled comes back. So the
       confirmation names the amount and the date, which is what the operator needs to
       be sure it is the right row — the same sentence the payments register uses,
       because it is the same act on the same record. */
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
            /* `kind` tells the register which table the id belongs to; the customer
               and supplier payment tables number themselves independently. */
            dialog.paymentsCtrl.remove(confirmDeletePayment.paymentId, "customer")
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

    /* Deleting the record itself. Only reachable while `deletable` — so the dialog
       states what goes rather than arguing about whether it may. */
    ConfirmDialog {
        id: confirmDelete

        title: Strings.t("customers.delete.title", "Delete this customer?")
        body: Strings.t("customers.delete.body",
                        "Nothing is recorded against this account, so nothing is lost with it.")

        facts: [
            {
                label: Strings.t("qcustomer.name", "Customer name"),
                value: dialog.row.name !== undefined ? dialog.row.name : "",
                tone: ""
            },
            {
                label: Strings.t("qcustomer.phone", "Phone"),
                value: dialog.row.phone !== undefined ? dialog.row.phone : "",
                tone: ""
            }
        ]

        confirmText: Strings.t("customers.delete.action", "Delete the customer")

        onConfirmed: {
            if (dialog.ctrl)
                dialog.ctrl.remove(dialog.customerId)
            /* The list behind reloads on `invalidated`; this record is about a row
               that no longer exists, so it goes too. */
            dialog.close()
        }
    }
}

import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * One customer: who they are, what they owe, what they bought, what they paid —
 * and the two fields that can be changed, in the same screen.
 *
 *   ┌────────────────────────────────────────────────────────────────┐
 *   │ Ahmed Belkacem                              [ Edit info ]      │
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
 * WHY THERE IS NO SEPARATE DETAILS SCREEN ANY MORE
 *
 * There used to be two: a read-only `customer_details` behind an eye icon, and a
 * two-field `customer_form` behind a pencil. Every visit to the first one that
 * found something wrong ended in the second, and the first could not show the name
 * being corrected. They were one screen split by an implementation detail — the
 * editor was small — so this is that screen: the record is what you look at, and
 * the two editable facts about it are edited in place.
 *
 * That also removes the eye column from the customers table, which is what the
 * table wanted: three icons on a row where two of them opened the same record.
 *
 * WHY THE PAYMENT IS TAKEN HERE AND NOT IN A DIALOG OF ITS OWN
 *
 * DialogHost shows one dialog at a time, so a payment dialog opened from here
 * would replace this one — the operator loses the balance they were reading in
 * order to act on it, and gets a screen that has to repeat it. The payment panel
 * below is the same three fields inside the section that already lists them, which
 * is what the supplier screen has always done.
 *
 * CREATING
 *
 * A new customer has no debt, no history and nothing to select between, so none of
 * that is drawn: the dialog is the two fields and Save. Same file, because "new
 * customer" and "this customer" differ by what the record contains, not by which
 * widgets exist.
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

    readonly property int customerId: context && context.customer_id
                                      ? context.customer_id : 0
    readonly property bool creating: customerId === 0

    /* Reading a customer needs `customers.view`, which is what opened this. Writing
       needs the manage right, and that is gated per control rather than by refusing
       to open: an operator who may look at an account should see it, not a refusal
       where the record was. */
    readonly property bool canManage: session ? session.can("customers.manage") : true
    readonly property bool canSell: session ? session.can("pos.sell") : true

    /* Wide when there is history to show, narrow when there are two fields. */
    preferredWidth: creating ? 700 : 1240
    preferredHeight: creating ? 0 : 900

    /* The record's own name is the title once there is one: a dialog headed "Edit
       customer" makes the operator look down to find out which. */
    title: creating ? Strings.t("customers.add", "New customer")
                    : (row.name !== undefined && row.name
                       ? row.name
                       : Strings.t("customers.edit_title", "Edit customer"))

    // =====================================================================
    // STATE
    // =====================================================================
    property var row: ({})

    readonly property var cards: row.cards !== undefined ? row.cards : ({})
    readonly property var sales: row.sales !== undefined ? row.sales : []
    readonly property var payments: row.payments !== undefined ? row.payments : []

    readonly property real debt: row.debt !== undefined ? row.debt : 0
    readonly property bool owes: debt > 0

    /* The identity fields are read-only until asked for. A screen whose name is
       already in an editable box invites a stray keystroke into the ledger, and it
       reads as a form rather than as a record. */
    property bool editingInfo: creating

    /* The payment panel, folded away until there is a payment to take. Opened by
       its own button, and opened for the operator when the row action that brought
       them here was "take a payment". */
    property bool paying: false

    property string salesQuery: ""
    property string paymentsQuery: ""

    /* What just happened, in the dialog rather than in a toast: this is modal, so
       the page's ToastHost is behind the scrim and unreadable. */
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
        if (ctrl && customerId)
            row = ctrl.customer(customerId) || ({})
    }

    /* The record into the fields. Called on open and on cancel, so "cancel" means
       "put it back" rather than "leave whatever I typed lying there". */
    function fill() {
        name.text = row.name !== undefined ? row.name : ""
        phone.text = row.phone !== undefined ? row.phone : ""
        address.text = row.address !== undefined ? row.address : ""
        wilaya.text = row.wilaya !== undefined ? row.wilaya : ""
        email.text = row.email !== undefined ? row.email : ""
        taxId.text = row.tax_id !== undefined ? row.tax_id : ""
        tradeId.text = row.trade_id !== undefined ? row.trade_id : ""
        /* 0 is "no ceiling", and an empty box says that better than a 0 the
           operator has to know to read as unlimited. */
        limit.text = row.credit_limit ? String(row.credit_limit) : ""
        levelKey = row.price_level !== undefined && row.price_level
                   ? row.price_level : "retail"
        error.text = ""
    }

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

    function saveInfo() {
        error.text = ""
        if (ctrl)
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
                                     "That is more than this customer owes.")
                         : Strings.t("amount.error", "Enter a valid amount.")
            amount.forceActiveFocus()
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
        }
    ]

    // =====================================================================
    // BRIDGE SIGNALS
    // =====================================================================
    Connections {
        target: dialog.ctrl
        ignoreUnknownSignals: true

        /* Saved while creating means the record now exists and there is nothing
           more to do here. Saved while editing means the two fields landed: stay
           open on the record, because the operator came to look at it. */
        function onSaved(customer) {
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
            /* Stays open with the new balance — a customer settling an account
               often pays against two tickets in one visit, and reopening the
               record to do the second is a step for nothing. */
            amount.text = ""
            dialog.paying = false
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

                // -- read state
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

                    /*
                     * The rest of the record, read-only, on one line.
                     *
                     * Wilaya, price level and credit ceiling — the three that change
                     * what happens at the till, so they belong beside the name rather
                     * than behind the edit button. The postal detail (address, email,
                     * NIF, RC) is only ever read while writing an invoice, and lives
                     * in the editor.
                     */
                    RowLayout {
                        Layout.fillWidth: true
                        visible: !dialog.editingInfo
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


                // -- edit state
                    RowLayout {
                        Layout.fillWidth: true
                        visible: dialog.editingInfo
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
                                onAccepted: dialog.saveInfo()
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
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.body
                                /* A phone number reads left to right in every
                                   language. */
                                horizontalAlignment: TextInput.AlignLeft
                                onAccepted: dialog.saveInfo()
                            }
                        }
                    }

                    /*
                     * Where they are, and how they buy.
                     *
                     * A small shop delivers, so the address is not optional in
                     * practice; the wilaya is how an Algerian address is filed. The
                     * price level and the ceiling are on this row because they are
                     * the two fields that change what the till does — everything
                     * else here is only ever read off a printed invoice.
                     */
                    RowLayout {
                        Layout.fillWidth: true
                        visible: dialog.editingInfo
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
                        visible: dialog.editingInfo
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

                            QC.TextField {
                                id: limit
                                Layout.fillWidth: true
                                Layout.preferredHeight: Tokens.size.control
                                enabled: dialog.canManage
                                placeholderText: Strings.t("customer.limit.none",
                                                           "no ceiling")
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.body
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: dialog.editingInfo
                        text: Strings.t("customer.credit_limit.hint",
                                        "0 means no ceiling. Above it, a sale on account is refused.")
                        wrapMode: Text.WordWrap
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.caption
                        color: Fluent.textTertiary
                    }

            }

            /* One button, and only while there is a record to edit. The Save that
               ends the edit is in the footer with every other commit on this
               dialog, so there is one place to look for it. */
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
        /* Compact cards: the same KpiCard the customers page opens with, sized for
           the room left above a table. The value keeps its 34px, because being
           readable across a counter is the whole reason these are cards and not a
           row of labels. */
        CardRow {
            Layout.fillWidth: true
            visible: !dialog.creating
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
            visible: !dialog.creating

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
               coming back to it is a decision rather than a leftover. */
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

                                /* Settling in full is the common case, and
                                   retyping six figures at a counter is where
                                   mistakes come from. */
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
                               : Strings.t("customer.no_payments",
                                           "Nothing has been paid against this account.")
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

            /* One button, three meanings, in the order they are reached: abandon a
               new record, put an edit back, or leave. Naming them apart matters —
               "Cancel" on a record nobody edited would suggest something is being
               undone. */
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

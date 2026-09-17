import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * A delivery: find the product, answer three figures, say what was paid.
 *
 *   ┌────────────────────────────────────────────────────────────────────────┐
 *   │ New delivery                                                          │
 *   │ [ Select supplier (F3) ▾ ] [＋]   [ scan or search a product (F2) ] [▤]│
 *   │ ┌ LINES 2 ──┐ ┌ TOTAL QTY 32 ┐ ┌ TOTAL COST 14 600.00 ─┐              │
 *   │ Product              Qty         Cost      Sells       Total           │
 *   │ Atlas Beans       [− 12 +]     [ 250 ]   [ 320 ]    3 000.00   ✎  🗑   │
 *   │ Atlas Rice        [− 20 +]     [  80 ]   [ 110 ]    1 600.00   ✎  🗑   │
 *   │ ┌──────────────────────────────────────────────────────────────────┐  │
 *   │ │ 2 lines   TOTAL 4 600.00   Paid [ 1000 ] All   Outstanding 3 600 │  │
 *   │ │                                          [ Save ]  [  Cash  ]    │  │
 *   │ └──────────────────────────────────────────────────────────────────┘  │
 *   └────────────────────────────────────────────────────────────────────────┘
 *
 * WHY A TABLE AND NOT CART ROWS
 *
 * A sale line has one figure a cashier may change, so the till's cart row — name, one
 * price, a stepper, a total — is exactly right there. A delivery line has three, and
 * the cart row could only ever show one of them: it displayed a "price" that was
 * really the cost, with nothing to say so and nowhere to put the selling price at all.
 * Three numbers per row is a table, with a heading over each column saying which is
 * which — and the three figures are edited IN the table (DataTable's stepper and
 * edit cells, the cart's own − n + among them), because a delivery is mostly
 * corrections: the cost the rep says out loud, the quantity that came in short.
 * The pen is still there for the full question — margin, last cost, the shelf —
 * but the common fix no longer opens a sheet over the row to make it.
 *
 * WHY THE EMPTY NOTE OFFERS THE SUPPLIER'S LAST DELIVERY
 *
 * A standing order is the same goods every week, and "Nothing on this delivery
 * yet" made the operator rebuild it from the search box every time. With a
 * supplier attached the empty state shows their last few items as the till's
 * own product cards, one tap each. Without one it says so: a cash purchase
 * from the market has no history to offer, and inventing one would be worse
 * than the sentence.
 *
 * WHY THERE IS NO FULL KEYPAD ON THIS SCREEN
 *
 * There was, for editing a line in place — select the row, switch the pad's
 * mode, type, Apply. The entry sheet replaced all of that: it asks the three
 * figures together with its own pad, and the inline cells above handle the
 * nudge. The one number this screen still takes as a whole amount is what was
 * paid, and that is a field with an "All" beside it — the same shape the
 * customer and supplier payment panels already use.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.purchases : null
    readonly property var suppliers: (typeof app !== "undefined" && app)
                                     ? app.suppliers : null
    readonly property var stock: (typeof app !== "undefined" && app) ? app.stock : null
    readonly property var session: (typeof app !== "undefined" && app) ? app.session : null
    readonly property var workflows: (typeof app !== "undefined" && app)
                                     ? app.workflows : null

    readonly property int invoiceId: context && context.invoice_id ? context.invoice_id : 0
    readonly property bool creating: invoiceId === 0

    /* `revision` first: `can()` is a slot with no notifier, so a binding that only
       calls it never re-evaluates when somebody logs in. */
    readonly property bool canManage: session && session.revision >= 0
                                      && session.can("purchases.manage")

    /* A supplier chosen elsewhere — the supplier record's "new invoice" button — so
       the delivery starts on the account it belongs to. */
    readonly property int presetSupplier: context && context.supplier_id
                                         ? context.supplier_id : 0

    preferredWidth: 1320
    preferredHeight: 820

    title: creating ? Strings.t("purchases.new", "New delivery")
                    : Strings.tf("purchases.edit_number", "Delivery {number}",
                                 { number: row.number !== undefined ? row.number : "" })

    /*
     * The header is the style's own Label again.
     *
     * The finder used to live up here, level with the document's name, to save the
     * 60px a line of its own would cost. It has moved down to share the supplier's
     * row instead — that row already ran half empty — so the saving stands and the
     * two things a delivery opens with, who it came from and what was on it, now sit
     * side by side where the eye finds them together.
     */

    // =====================================================================
    // STATE
    // =====================================================================
    /* [{ product_id, name, qty, price, sale_price }] — the document, in the order it
       was rung. A delivery note is read top to bottom, so the order is the operator's
       own. `price` is the COST, which is what `save_purchase_invoice` calls it. */
    property var lines: []
    property var row: ({})

    /* The supplier, as a record rather than a combo index: the card shows a name and
       a rep, and an id alone cannot draw that. */
    property var supplier: null

    property string paidText: ""

    /* The finder's data. The caller owns it; the component owns the interaction. */
    property var matches: []
    property var catalogue: []

    /* What this supplier sent last time — the empty note's quick-add strip,
       newest first, in the till's tile row shape. Reloaded on every attach:
       a supplier chosen two minutes ago may have a delivery on file from this
       morning, and the strip is exactly the "the usual order again" list. */
    property var recent: []

    /* True from the press on the add-supplier button until the supplier that
       press is making comes back — the till's own gate around the customer
       form, for the same reason: `saved` fires for every supplier written
       anywhere in the app, and only this one belongs on this delivery. */
    property bool awaitingNewSupplier: false

    Component.onCompleted: {
        if (suppliers)
            suppliers.load("")
        if (!creating && ctrl) {
            row = ctrl.invoice(invoiceId) || ({})
            var loaded = []
            var source = row.items !== undefined ? row.items : []
            for (var i = 0; i < source.length; i++)
                loaded.push({ product_id: source[i].product_id,
                              name: source[i].name,
                              qty: Number(source[i].qty),
                              price: Number(source[i].price) })
            lines = loaded
            paidText = row.paid ? String(row.paid) : ""
            attach(row.supplier_id)
        } else if (presetSupplier) {
            attach(presetSupplier)
        }
        finder.focusSearch()
    }

    function attach(supplierId) {
        if (!supplierId || !suppliers) {
            supplier = null
            recent = []
            return
        }
        supplier = suppliers.supplier(Number(supplierId)) || null
        recent = (ctrl && supplier) ? ctrl.recentItems(Number(supplierId)) : []
    }

    /* The form, not the picker: an operator who has decided the supplier is
       not on file is never handed the list of the ones that are to click
       through. `supplier_edit` with no id is the empty form; the save lands in
       the Connections below. */
    function newSupplier() {
        if (!workflows || !workflows.open)
            return
        awaitingNewSupplier = true
        workflows.open("supplier_edit", {})
    }

    // -- money -------------------------------------------------------------
    readonly property real total: {
        var sum = 0
        for (var i = 0; i < lines.length; i++)
            sum += Number(lines[i].qty) * Number(lines[i].price)
        return sum
    }

    readonly property real paidValue: number(paidText)
    readonly property real due: Math.max(0, total - paidValue)
    readonly property bool sendable: canManage && lines.length > 0 && total > 0

    /* The sum of the quantities, in the shop's own format — the Total Qty
       card's figure. Strings, not a number, because the shop's unit text
       ("12 kg") is the honest way to say it. */
    readonly property string qtyTotalText: {
        var sum = 0
        for (var i = 0; i < lines.length; i++)
            sum += Number(lines[i].qty)
        return stock ? stock.qtyText(sum) : String(sum)
    }

    function money(value) {
        return ctrl ? ctrl.moneyText(value) : "—"
    }

    function number(text) {
        var value = parseFloat(String(text).replace(",", "."))
        return isNaN(value) ? 0 : value
    }

    // -- the note, formatted for the table ---------------------------------
    /* DataTable renders `row[key]` verbatim, so the formatted strings are
       built here. The RAW figures ride beside them under their own keys —
       `qty`, `cost`, `sale_price` — because the editable and stepper cells
       bind to numbers, not to money text: a field holding "1 658,74" is a
       field its own parser cannot read back. */
    readonly property var noteRows: {
        var out = []
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i]
            var cost = Number(line.price)
            var sale = line.sale_price !== undefined ? Number(line.sale_price) : 0
            out.push({
                index: i,
                name: line.name,
                qty: Number(line.qty),
                cost: cost,
                sale_price: sale,
                total_text: money(Number(line.qty) * cost),
                /* A selling price at or under cost is worth pointing at: sometimes
                   deliberate, never accidental on purpose. */
                thin: sale > 0 && sale <= cost
            })
        }
        return out
    }

    readonly property var columns: [
        {
            key: "name",
            header: Strings.t("products.col.name", "Product"),
            stretch: true
        },
        {
            key: "qty",
            header: Strings.t("purchases.col.qty", "Qty"),
            numeric: true,
            /* Wide enough for the cart's own stepper: two 48px keys around a
               72px field, plus the cell's padding. */
            width: 220,
            stepper: true
        },
        {
            key: "cost",
            header: Strings.t("product.purchase_price", "Cost"),
            numeric: true,
            width: 150,
            edit: true
        },
        {
            key: "sale_price",
            header: Strings.t("product.sale_price", "Sells for"),
            numeric: true,
            width: 150,
            edit: true,
            tone: function (r) { return r.thin ? "danger" : "" }
        },
        {
            key: "total_text",
            header: Strings.t("purchases.col.total", "Total"),
            numeric: true,
            width: 170,
            ltr: true
        },
        {
            key: "actions",
            actions: [{ id: "edit" }, { id: "delete" }]
        }
    ]

    // -- the document ------------------------------------------------------
    function indexOf(productId) {
        for (var i = 0; i < lines.length; i++)
            if (lines[i].product_id === productId)
                return i
        return -1
    }

    /*
     * A product chosen is a question, not a line yet.
     *
     * A delivery line is three numbers decided together, so the entry sheet asks for
     * all three with the margin between them in view, and the line is written when
     * they are answered.
     *
     * A product already on the note reopens ITS line instead of adding a second one —
     * the till's rule, for the till's reason: two rows for one product is a quantity
     * the operator has to add up by eye.
     */
    function add(product) {
        if (!product)
            return
        var at = indexOf(product.id)
        if (at >= 0) {
            editLine(at)
            return
        }
        var seed = ctrl ? ctrl.lineDefaults(product.id) : ({})
        entry.editingIndex = -1
        entry.product = { id: product.id,
                          name: product.name,
                          barcode: product.barcode !== undefined ? product.barcode : "" }
        entry.qty = 1
        entry.cost = seed.cost !== undefined ? seed.cost : 0
        entry.price = seed.price !== undefined ? seed.price : 0
        entry.lastText = seed.last_text !== undefined ? seed.last_text : ""
        entry.stockText = seed.stock_text !== undefined ? seed.stock_text : ""
        entry.editing = false
        entry.open()
    }

    /* The pen on a row: the same sheet, holding what that line already says. */
    function editLine(index) {
        if (index < 0 || index >= lines.length)
            return
        var line = lines[index]
        var seed = ctrl ? ctrl.lineDefaults(line.product_id) : ({})
        entry.editingIndex = index
        entry.product = { id: line.product_id,
                          name: line.name,
                          barcode: seed.barcode !== undefined ? seed.barcode : "" }
        entry.qty = Number(line.qty)
        entry.cost = Number(line.price)
        entry.price = line.sale_price !== undefined
                      ? Number(line.sale_price)
                      : (seed.price !== undefined ? seed.price : 0)
        entry.lastText = seed.last_text !== undefined ? seed.last_text : ""
        entry.stockText = seed.stock_text !== undefined ? seed.stock_text : ""
        entry.editing = true
        entry.open()
    }

    /* A code first, then the one visible match — the same rule the till and the
       stocktake use, so one box serves a scanner and two typed letters. */
    function submit(text) {
        if (text.trim() === "" || !stock)
            return
        var hits = stock.find(text, 3)
        if (hits.length === 1) {
            finder.take(hits[0])
            return
        }
        if (matches.length === 1)
            finder.take(matches[0])
    }

    function patch(index, changes) {
        if (index < 0 || index >= lines.length)
            return
        var next = []
        for (var i = 0; i < lines.length; i++)
            next.push(i === index ? Object.assign({}, lines[i], changes) : lines[i])
        lines = next
    }

    /* An inline cell edit, in the line's own vocabulary. The table names the
       columns the way the screen reads them — `cost`, `sale_price`, `qty` —
       while the document stores the cost as `price`, which is the name
       `save_purchase_invoice` takes. Whatever comes back is a figure: any
       edit is clamped at zero, because a negative cost, price or quantity is
       a typo, not a correction. */
    function cellEdited(index, key, value) {
        var figure = Number(value)
        if (isNaN(figure))
            return
        figure = Math.max(0, figure)
        if (key === "qty")
            patch(index, { qty: figure })
        else if (key === "cost")
            patch(index, { price: figure })
        else if (key === "sale_price")
            patch(index, { sale_price: figure })
    }

    function removeLine(index) {
        var next = lines.slice()
        next.splice(index, 1)
        lines = next
    }

    // -- commit ------------------------------------------------------------
    function payCash() {
        paidText = String(total)
        commit()
    }

    function commit() {
        error.text = ""
        if (!ctrl || !sendable)
            return
        ctrl.save({
            supplier_id: supplier ? supplier.id : null,
            paid: paidText === "" ? 0 : paidValue,
            items: lines
        }, invoiceId)
    }

    Connections {
        target: dialog.ctrl
        ignoreUnknownSignals: true
        function onSaved(invoice) { dialog.close() }
        function onRejected(message) { error.text = message }
    }

    /* The supplier form saved. Attached by id, the way the customer form's
       result is on the till: the operator pressed that button to put a name
       on this delivery, not to file a record. Gated by awaitingNewSupplier,
       because `saved` fires for every supplier written anywhere. */
    Connections {
        target: dialog.suppliers
        ignoreUnknownSignals: true
        function onSaved(supplier) {
            if (!dialog.awaitingNewSupplier || !supplier)
                return
            dialog.awaitingNewSupplier = false
            dialog.attach(supplier.id)
        }
    }

    // =====================================================================
    // LAYOUT
    // =====================================================================
    // =====================================================================
    // LAYOUT
    // =====================================================================
    /*
     * Top to bottom, full width: who it is from, what is on it, what it comes to.
     *
     * There was a 360px column down the right holding the supplier card, the totals
     * and the buttons. It wasted the width the table needed — five columns squeezed
     * into two thirds of the dialog — and it left a tall empty gap between the card at
     * its top and the totals at its bottom, because nothing else belonged there.
     *
     * The supplier belongs above the note, where an invoice puts it. The total and the
     * two buttons belong at the bottom in the till's own dock, which is what that
     * component is built for and the reason it did not fit a narrow column.
     */
    contentItem: ColumnLayout {
        spacing: Tokens.spacing.sm

        /* F2 and F3, the till's own keys for the same two things: the finder
           is where a scanner's Return lands, and the supplier list drops open
           without a trip to the field. Declared as a Keys handler rather than
           a Shortcut because a Popup is not an Item — the bubbles from
           whichever child holds focus are what reach this. */
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_F2) {
                finder.focusSearch()
                event.accepted = true
            } else if (event.key === Qt.Key_F3) {
                supplierSelect.open()
                event.accepted = true
            }
        }

        // -----------------------------------------------------------------
        // WHO IT IS FROM, AND WHAT GOES ON IT
        // -----------------------------------------------------------------
        /* The till's customer control, holding a supplier: same card, same gesture —
           tap to drop the list, type to narrow it, the ✕ to detach. It shares this
           row with the finder: who the delivery came from and what is being put on
           it are the two answers this screen opens with, and they belong on one
           line, not stacked into two.

           A delivery with no supplier is legitimate — a cash purchase from a market —
           so the empty state is an invitation, not an error. */
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.md

            PartySelect {
                id: supplierSelect
                Layout.fillWidth: true
                Layout.maximumWidth: 480
                glyph: "ic_fluent_vehicle_truck_profile_20_regular"
                active: dialog.supplier !== null
                title: dialog.supplier
                       ? dialog.supplier.name
                       : Strings.t("purchases.supplier.hint",
                                   "Select supplier (F3)")
                subtitle: dialog.supplier
                          ? [dialog.supplier.contact, dialog.supplier.wilaya]
                            .filter(function (p) { return p }).join("  ·  ")
                          : ""
                removeTip: Strings.t("purchases.supplier.remove", "Remove supplier")

                /* Already in memory: the list is loaded with the dialog, so the
                   dropdown filters it in QML and needs no round trip. Reloaded on
                   each open anyway, because a supplier added from elsewhere while
                   this dialog was up would otherwise be missing from it. */
                rows: dialog.suppliers ? dialog.suppliers.rows : []
                placeholder: Strings.t("suppliers.search.ph",
                                       "Search name or phone")

                onListRequested: {
                    if (dialog.suppliers)
                        dialog.suppliers.load("")
                }
                /* Attached by id, not by the row: the list carries a name, a phone
                   and a debt, and the card shows a rep and a wilaya that only the
                   full record has. */
                onPicked: (party) => dialog.attach(party.id)
                onRemoveRequested: dialog.supplier = null
            }

            /* ADD A SUPPLIER FROM HERE. The one gesture a delivery needs that
               the select cannot do — a rep nobody has bought from before
               walks in — and one that should not cost a trip to the suppliers
               page and back with the delivery half-entered. Beside the field
               it serves, where the till also keeps its customer's. */
            IconButton {
                Layout.alignment: Qt.AlignTop
                glyph: "ic_fluent_person_add_20_regular"
                glyphSize: Tokens.icon.md
                tooltip: Strings.t("suppliers.add", "New supplier")
                enabled: dialog.canManage
                onClicked: dialog.newSupplier()
            }

            /* Vertically centred against the card, which is the taller of the two:
               a search field stretched to a card's height is a field that looks
               broken. */
            ProductFinder {
                id: finder
                Layout.fillWidth: true
                Layout.maximumWidth: 620
                Layout.alignment: Qt.AlignTop
                enabled: dialog.canManage
                placeholder: Strings.t("purchases.finder.ph2",
                                       "Scan or search a product (F2)")
                results: dialog.matches
                all: dialog.catalogue

                onQueried: (text) => {
                    dialog.matches = (text.trim() === "" || !dialog.stock)
                                     ? [] : dialog.stock.find(text, 12)
                }
                onBrowsed: {
                    /* The whole catalogue, not a capped find: the browse list is
                       the shared select-product table, and a ceiling on it is
                       the row the operator wanted made invisible. */
                    if (dialog.stock)
                        dialog.catalogue = dialog.stock.catalogue()
                }
                onAccepted: (text) => dialog.submit(text)
                onPicked: (product) => dialog.add(product)
            }

            /* The slack lands here, so neither the card nor the finder is stretched
               across a wide dialog. */
            Item { Layout.fillWidth: true }
        }

        // -----------------------------------------------------------------
        // THE RUNNING SUMMARY
        // -----------------------------------------------------------------
        /* The same cards the stocktake wears over its sheet, for the same
           reason: the figures a delivery is steered by should not require
           scrolling to the dock and reading past the buttons to find. Cost,
           not value: what this delivery owes, which is the number the
           operator reconciles with the rep. */
        CardRow {
            Layout.fillWidth: true
            minCardWidth: 220

            KpiCard {
                glyph: "ic_fluent_receipt_20_regular"
                value: String(dialog.lines.length)
                label: Strings.t("purchases.card.lines", "Lines")
                tone: "info"
            }

            KpiCard {
                glyph: "ic_fluent_box_multiple_20_regular"
                value: dialog.qtyTotalText
                label: Strings.t("purchases.card.qty", "Total qty")
                tone: "primary"
            }

            KpiCard {
                glyph: "ic_fluent_money_20_regular"
                value: dialog.money(dialog.total)
                label: Strings.t("purchases.card.cost", "Total cost")
                tone: "success"
            }
        }

        // -----------------------------------------------------------------
        // THE NOTE
        // -----------------------------------------------------------------
        DataTable {
            id: noteTable
            Layout.fillWidth: true
            Layout.fillHeight: true
            /* An empty table is a heading over nothing; the block below is
               what the note shows until it has a line. */
            visible: dialog.lines.length > 0
            columns: dialog.columns
            model: dialog.noteRows
            emptyIcon: "ic_fluent_receipt_20_regular"
            emptyText: Strings.t("purchases.empty.hint",
                                 "Nothing on this delivery yet. Scan a product or search for one.")
            /* Double-clicking a row is the same as its pen: a row that opens on
               activation is what every other table in this app does. */
            onRowActivated: (row) => dialog.editLine(row)
            /* The inline cells — qty's stepper, cost and sells' fields. The
               page owns `lines`; the table only reports what changed. */
            onCellEdited: (row, key, value) => dialog.cellEdited(row, key, value)
            onActionTriggered: (row, action) => {
                if (action === "edit")
                    dialog.editLine(row)
                else if (action === "delete")
                    dialog.removeLine(row)
            }
        }

        /* THE EMPTY NOTE — a hint, and a way in.
           "Nothing on this delivery yet" was the whole story; the operator's
           next move was always the search box. With a supplier attached this
           shows their last few items as the till's own product cards, one tap
           each — the standing order is mostly the last order repeated. With no
           supplier there is no history to offer, and the second line says so
           rather than showing an empty strip. */
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: dialog.lines.length === 0
            spacing: Tokens.spacing.sm

            Text {
                Layout.fillWidth: true
                text: Strings.t("purchases.empty.hint2",
                                "Nothing on this delivery yet. Scan a product, search for one, or start from what this supplier sent last time.")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                color: Fluent.textSecondary
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                visible: recentStrip.count === 0
                text: Strings.t("purchases.empty.no_supplier",
                                "Attach a supplier and their last items will appear here.")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.caption
                color: Fluent.textTertiary
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                visible: recentStrip.count > 0
                text: Strings.tf("purchases.recent.title", "Last from {name}",
                                 { name: dialog.supplier ? dialog.supplier.name : "" })
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.caption
                font.weight: Font.DemiBold
                color: Fluent.textSecondary
                elide: Text.ElideRight
            }

            /* The strip: horizontal, the till's card, one tap to the entry
               sheet. Left-aligned and scrolling rather than wrapping — it is
               a rail of options, not a wall. */
            ListView {
                id: recentStrip
                Layout.fillWidth: true
                Layout.preferredHeight: Tokens.size.tile + Tokens.spacing.sm
                visible: count > 0
                orientation: ListView.Horizontal
                clip: true
                spacing: Tokens.spacing.sm
                model: dialog.recent

                QC.ScrollBar.horizontal: FluentScrollBar {
                    policy: QC.ScrollBar.AsNeeded
                }

                delegate: Item {
                    required property var modelData
                    width: 210
                    height: recentStrip.height

                    PosTile {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - recentStrip.spacing,
                                        Tokens.size.tileMax)
                        height: Tokens.size.tile

                        name: modelData.name
                        priceText: modelData.price_text
                        barcode: modelData.barcode !== undefined
                                 ? modelData.barcode : ""
                        stock: modelData.stock !== undefined ? modelData.stock : 0
                        stockText: modelData.stock_text !== undefined
                                   ? modelData.stock_text : ""
                        onClicked: dialog.add(modelData)
                    }
                }
            }

            /* Keeps the rail against the hint instead of centred in the
               table's old space. */
            Item { Layout.fillHeight: true }
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

        // -----------------------------------------------------------------
        // WHAT IT COMES TO
        // -----------------------------------------------------------------
        /* The till's own dock, at the bottom and full width — which is the shape it
           was built for. Its third metadata slot carries what is still owed rather
           than a discount, which is why that caption is a property now. */
        TotalsDock {
            Layout.fillWidth: true

            cartNumber: dialog.creating
                        ? Strings.t("purchases.new", "New delivery")
                        : (dialog.row.number !== undefined ? dialog.row.number : "")
            itemsText: Strings.tf("purchases.lines_n", "{count} lines",
                                  { count: dialog.lines.length })
            totalText: dialog.money(dialog.total)

            /*
             * TOTAL / PAID / REMAINING, but only on a document that exists.
             *
             * `pos`'s purchase footer draws the same three columns and hides the last
             * two while creating (purchase_form.py: `show_financial = self._invoice_id
             * is not None`) — there is nothing paid on an invoice that has not been
             * saved, and a "Paid 0.00" column on a blank form is a fake reading.
             *
             * They were caption lines in the metadata block before, which was the wrong
             * weight: an operator settling up with a rep is reading "how much is left",
             * and that is not something to put in 12px grey under "1 lines".
             */
            paidText: dialog.creating ? "" : dialog.money(dialog.paidValue)
            remainingText: dialog.creating ? "" : dialog.money(dialog.due)
            owing: dialog.due > 0.005

            actionItems: [
                /* Two buttons and no field. A partial payment is a moment, not a
                   setting: somebody is standing there handing over less than the whole
                   amount, and the question that has to be answered out loud — how much
                   is still owed after this — needs the screen and a figure read across
                   a counter. A box tucked into this panel could ask neither, so Partial
                   opens a dialog and Cash needs no input at all.

                   Cash is the hero and sits on the far edge where a thumb lands: paying
                   a delivery in full is the common answer. Same order as the till. */
                PayButton {
                    compact: true
                    text: Strings.t("pos.pay.partial", "Partial")
                    shortcut: "F8"
                    glyph: "ic_fluent_money_hand_20_regular"
                    hue: Tokens.chromeHue.amber
                    enabled: dialog.sendable
                    onClicked: payment.open()
                },
                PayButton {
                    text: Strings.t("pos.pay.cash", "Cash")
                    shortcut: "F9"
                    glyph: "ic_fluent_money_20_regular"
                    hue: Tokens.chromeHue.emerald
                    primary: true
                    enabled: dialog.sendable
                    onClicked: dialog.payCash()
                }
            ]
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
    // THE LINE ENTRY SHEET
    // =====================================================================
    /*
     * Quantity, cost and selling price for one product, with a keypad typing straight
     * into whichever figure has focus. A popup inside this dialog rather than a
     * workflow: it is a field of this form, not a destination with a key and a
     * permission, and it answers by handing a line back to the sheet.
     */
    LineEntry {
        id: entry

        /* Which line is being corrected, or -1 for a product being added. Held here
           rather than on the sheet, because it is this screen's bookkeeping. */
        property int editingIndex: -1

        onAccepted: (qty, cost, price) => {
            if (entry.editingIndex >= 0) {
                dialog.patch(entry.editingIndex,
                             { qty: qty, price: cost, sale_price: price })
            } else {
                dialog.lines = dialog.lines.concat([{
                    product_id: entry.product.id,
                    name: entry.product.name,
                    qty: qty,
                    price: cost,
                    /* Carried on the line and applied to the product when the delivery
                       is saved: a delivery that arrived dearer re-prices the shelf,
                       which is what the field is for. */
                    sale_price: price
                }])
            }
            /* Back to the finder: the next thing after a line is the next line, and
               the scanner is already in the operator's hand. */
            finder.focusSearch()
        }
    }

    // =====================================================================
    // THE PARTIAL PAYMENT
    // =====================================================================
    /*
     * The shared payment sheet, told what this delivery is worth and what the supplier
     * is already owed. It owns the keypad and the "left after this" figure; this screen
     * owns only where the answer goes.
     */
    PaymentEntry {
        id: payment

        heading: Strings.t("purchases.partial.title", "Part-pay this delivery")
        due: dialog.total
        /* A delivery may be taken entirely on account, so nothing is a real answer
           here — unlike a customer payment, where zero would be a no-op. */
        allowZero: true
        confirmText: Strings.t("purchases.save", "Save invoice")

        /* Correcting a delivery that was already part-paid: `save_purchase_invoice`
           reverses the old supplier debt and writes what arrives here as the invoice's
           paid figure, so this amount replaces the stored one instead of adding to it.
           `row` is the invoice as it was loaded and never re-read, which is exactly the
           "before" figure the sheet needs. */
        replaces: !dialog.creating
        alreadyPaid: dialog.row.paid !== undefined ? dialog.row.paid : 0

        facts: {
            var out = []
            if (dialog.supplier && dialog.supplier.debt > 0)
                out.push({
                    label: Strings.tf("purchases.supplier_owes", "{name} is already owed",
                                      { name: dialog.supplier.name }),
                    value: dialog.money(dialog.supplier.debt),
                    tone: "danger"
                })
            out.push({
                label: Strings.t("purchases.partial.this", "This delivery"),
                value: dialog.money(dialog.total),
                tone: ""
            })
            return out
        }

        onAccepted: (amount) => {
            dialog.paidText = String(amount)
            dialog.commit()
        }
    }
}

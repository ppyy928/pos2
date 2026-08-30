import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * A delivery: find the product, answer three figures, say what was paid.
 *
 *   ┌──────────────────────────────────────────────┬───────────────────────┐
 *   │ [ scan or search a product ......... ] [▤]   │ ┌─ SUPPLIER ────────┐ │
 *   │                                              │ │ Atlas Distribution│ │
 *   │ Product        Qty    Cost    Sells   Total  │ │ Karim · Blida     │ │
 *   │ Atlas Beans     12  250.00  320.00  3 000.00 │ └───────────────────┘ │
 *   │ Atlas Rice      20   80.00  110.00  1 600.00 │ ┌───────────────────┐ │
 *   │                                        ✎  ✕  │ │ 2 lines     TOTAL │ │
 *   │                                              │ │        4 600.00   │ │
 *   │                                              │ │ Paid [ 1000 ] All │ │
 *   │                                              │ │ Outstanding 3 600 │ │
 *   │                                              │ └───────────────────┘ │
 *   │                                              │ [ Save ] [  Cash  ]   │
 *   └──────────────────────────────────────────────┴───────────────────────┘
 *
 * WHY A TABLE AND NOT CART ROWS
 *
 * A sale line has one figure a cashier may change, so the till's cart row — name, one
 * price, a stepper, a total — is exactly right there. A delivery line has three, and
 * the cart row could only ever show one of them: it displayed a "price" that was
 * really the cost, with nothing to say so and nowhere to put the selling price at all.
 * Three numbers per row is a table, with a heading over each column saying which is
 * which.
 *
 * WHY THERE IS NO KEYPAD ON THIS SCREEN
 *
 * There was, for editing a line in place — select the row, switch the pad's mode,
 * type, Apply. The entry sheet replaced all of that: it asks the three figures
 * together with its own pad, so a second pad out here would be a second way to do one
 * job, and the row's pen is a shorter path to it than selecting a row and hunting a
 * mode. The one number this screen still takes is what was paid, and that is a field
 * with an "All" beside it — the same shape the customer and supplier payment panels
 * already use.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.purchases : null
    readonly property var suppliers: (typeof app !== "undefined" && app)
                                     ? app.suppliers : null
    readonly property var stock: (typeof app !== "undefined" && app) ? app.stock : null
    readonly property var session: (typeof app !== "undefined" && app) ? app.session : null

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
            return
        }
        supplier = suppliers.supplier(Number(supplierId)) || null
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

    function money(value) {
        return ctrl ? ctrl.moneyText(value) : "—"
    }

    function number(text) {
        var value = parseFloat(String(text).replace(",", "."))
        return isNaN(value) ? 0 : value
    }

    // -- the note, formatted for the table ---------------------------------
    /* DataTable renders `row[key]` verbatim, so the strings are built here. The raw
       numbers stay on `lines`, which is what travels to the bridge. */
    readonly property var noteRows: {
        var out = []
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i]
            var cost = Number(line.price)
            var sale = line.sale_price !== undefined ? Number(line.sale_price) : 0
            out.push({
                index: i,
                name: line.name,
                qty_text: stock ? stock.qtyText(Number(line.qty)) : String(line.qty),
                cost_text: money(cost),
                sale_text: sale > 0 ? money(sale) : "—",
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
            key: "qty_text",
            header: Strings.t("purchases.col.qty", "Qty"),
            numeric: true,
            width: 110,
            ltr: true
        },
        {
            key: "cost_text",
            header: Strings.t("product.purchase_price", "Cost"),
            numeric: true,
            width: 150,
            ltr: true
        },
        {
            key: "sale_text",
            header: Strings.t("product.sale_price", "Sells for"),
            numeric: true,
            width: 150,
            ltr: true,
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

        // -----------------------------------------------------------------
        // WHO IT IS FROM, AND WHAT GOES ON IT
        // -----------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.md

            ProductFinder {
                id: finder
                Layout.fillWidth: true
                enabled: dialog.canManage
                placeholder: Strings.t("purchases.finder.ph",
                                       "Scan or search a product to add it")
                results: dialog.matches
                all: dialog.catalogue

                onQueried: (text) => {
                    dialog.matches = (text.trim() === "" || !dialog.stock)
                                     ? [] : dialog.stock.find(text, 12)
                }
                onBrowsed: {
                    if (dialog.stock)
                        dialog.catalogue = dialog.stock.find("", 500)
                }
                onAccepted: (text) => dialog.submit(text)
                onPicked: (product) => dialog.add(product)
            }

            /* The till's customer card, holding a supplier: same widget, same gesture —
               tap to attach, the x to detach. Above the note because that is where an
               invoice names who it is from, and beside the finder because both are
               things you set before the lines rather than after them.

               A delivery with no supplier is legitimate — a cash purchase from a
               market — so the empty state is an invitation, not an error. */
            PartyCard {
                Layout.preferredWidth: 360
                Layout.minimumWidth: 280
                glyph: "ic_fluent_vehicle_truck_profile_20_regular"
                active: dialog.supplier !== null
                title: dialog.supplier ? dialog.supplier.name
                                       : Strings.t("purchases.no_supplier",
                                                   "No supplier")
                subtitle: dialog.supplier
                          ? [dialog.supplier.contact, dialog.supplier.wilaya]
                            .filter(function (p) { return p }).join("  ·  ")
                          : Strings.t("purchases.supplier.hint",
                                      "Tap to attach a supplier")
                removeTip: Strings.t("purchases.supplier.remove", "Remove supplier")
                onClicked: picker.open()
                onRemoveRequested: dialog.supplier = null
            }
        }

        // -----------------------------------------------------------------
        // THE NOTE
        // -----------------------------------------------------------------
        DataTable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: dialog.columns
            model: dialog.noteRows
            emptyIcon: "ic_fluent_receipt_20_regular"
            emptyText: Strings.t("purchases.empty.hint",
                                 "Nothing on this delivery yet. Scan a product or search for one.")
            /* Double-clicking a row is the same as its pen: a row that opens on
               activation is what every other table in this app does. */
            onRowActivated: (row) => dialog.editLine(row)
            onActionTriggered: (row, action) => {
                if (action === "edit")
                    dialog.editLine(row)
                else if (action === "delete")
                    dialog.removeLine(row)
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
            /* Only once something has been paid: an unpaid delivery has nothing to
               say here, and a "Paid now 0.00" line is noise. */
            qtyText: dialog.paidValue > 0.005 ? dialog.money(dialog.paidValue) : ""
            qtyCaption: Strings.t("purchases.paid", "Paid now")
            discountText: dialog.due > 0.005 ? dialog.money(dialog.due) : ""
            discountCaption: Strings.t("purchases.col.due", "Outstanding")
            totalText: dialog.money(dialog.total)

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
     * workflow, for the usual reason: DialogHost shows one dialog at a time and a
     * workflow would destroy the delivery being written.
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

    // =====================================================================
    // THE SUPPLIER PICKER
    // =====================================================================
    /*
     * An inline popup, not a workflow: DialogHost shows one dialog at a time, so a
     * supplier picker opened as a workflow would destroy the delivery being written.
     * Same reason ProductFinder owns its own browse list.
     */
    QC.Popup {
        id: picker

        parent: QC.Overlay.overlay
        anchors.centerIn: QC.Overlay.overlay
        /* Measured against the overlay it is parented to, not against `Window`: the
           attached `Window` property only works on Items, and this dialog derives from
           Popup — reading it warns and answers undefined. */
        width: Math.min(620, (parent ? parent.width : 900) - 2 * Tokens.spacing.xxl)
        height: Math.min(560, (parent ? parent.height : 700) - 2 * Tokens.spacing.xxl)
        padding: Tokens.spacing.md
        modal: true
        focus: true

        background: Rectangle {
            color: Fluent.popupBackground
            radius: Tokens.radius.lg
            border.width: 1
            border.color: Fluent.dividerBorder
        }

        onOpened: sieve.forceActiveFocus()

        contentItem: ColumnLayout {
            spacing: Tokens.spacing.sm

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.sm

                Text {
                    Layout.fillWidth: true
                    text: Strings.t("suppliers.title", "Suppliers")
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.subtitle
                    font.weight: Font.DemiBold
                    color: Fluent.textPrimary
                }

                IconButton {
                    glyph: "ic_fluent_dismiss_20_regular"
                    glyphSize: Tokens.icon.sm
                    onClicked: picker.close()
                }
            }

            QC.TextField {
                id: sieve
                Layout.fillWidth: true
                Layout.preferredHeight: Tokens.size.control
                placeholderText: Strings.t("suppliers.search.ph",
                                           "Search name or phone")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
            }

            ListView {
                id: shelf
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                QC.ScrollBar.vertical: FluentScrollBar { }

                /* Filtered here: the suppliers list arrived whole with the screen, so
                   narrowing it is instant and needs no round trip. */
                model: {
                    var needle = sieve.text.trim().toLowerCase()
                    var source = dialog.suppliers ? dialog.suppliers.rows : []
                    if (needle === "")
                        return source
                    var out = []
                    for (var i = 0; i < source.length; i++) {
                        var s = source[i]
                        if (String(s.name).toLowerCase().indexOf(needle) >= 0
                                || String(s.phone || "").indexOf(needle) >= 0
                                || String(s.contact || "").toLowerCase()
                                   .indexOf(needle) >= 0)
                            out.push(s)
                    }
                    return out
                }

                delegate: Rectangle {
                    id: hit
                    required property var modelData

                    width: shelf.width
                    height: Tokens.size.tableRow
                    radius: Tokens.radius.sm
                    color: hover.hovered ? Fluent.subtleSecondary : "transparent"

                    HoverHandler { id: hover }
                    TapHandler {
                        onTapped: {
                            dialog.attach(hit.modelData.id)
                            picker.close()
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.spacing.sm
                        anchors.rightMargin: Tokens.spacing.sm
                        spacing: Tokens.spacing.sm

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            Text {
                                Layout.fillWidth: true
                                text: hit.modelData.name
                                elide: Text.ElideRight
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.body
                                color: Fluent.textPrimary
                            }

                            Text {
                                visible: text !== ""
                                text: [hit.modelData.contact, hit.modelData.wilaya,
                                       hit.modelData.phone]
                                      .filter(function (p) { return p }).join("  ·  ")
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.overline
                                color: Fluent.textTertiary
                            }
                        }

                        /* What is already owed. The one figure that changes which
                           supplier a shopkeeper buys from next. */
                        Text {
                            visible: hit.modelData.debt > 0
                            text: "\u200e" + dialog.money(hit.modelData.debt)
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.body
                            font.weight: Font.DemiBold
                            color: Tokens.danger
                        }
                    }
                }
            }
        }
    }
}

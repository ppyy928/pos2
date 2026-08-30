import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * One product, on one page, in four groups you can see.
 *
 *   Atlas Beans                                    ← the dialog title, once
 *   ┌─ 📦 IDENTITY ─────────────────────────────────────────────────────┐
 *   │  Name    [ Atlas Beans                                        ]   │
 *   │  Barcode [ 5449000996 ]  Category [ Drinks ▾ ]  Unit [ pcs ▾ ]    │
 *   └───────────────────────────────────────────────────────────────────┘
 *   ┌─ 💰 PRICING ───────────────────── margin 135.15 (20.1%) ──────────┐
 *   │  Cost [ 536.76 ]  Retail [ 671.91 ]  Half [    ]  Whole [    ]    │
 *   │  VAT % [ shop default ]                                           │
 *   └───────────────────────────────────────────────────────────────────┘
 *   ┌─ 📊 STOCK ────────────────────────────────────────────────────────┐
 *   │  In stock  295  [ Adjust ]   Low-stock [ 5 ]                      │
 *   │  ⦿ On the till    ○ Favourite                                     │
 *   └───────────────────────────────────────────────────────────────────┘
 *   ┌─ 🗃 MULTI-UNITS ─────────────────────────── [ + Add a unit ] ─────┐
 *   │  Pack of 6   × 6   700.00   2885822280736              🗑          │
 *   └───────────────────────────────────────────────────────────────────┘
 *                                              [ ✕ Cancel ]  [ 💾 Save ]
 *
 * WHAT THE SCREENSHOTS SHOWED, AND WHAT CHANGED
 *
 * Rendering this dialog and looking at it found four faults a compile check cannot:
 *
 *  1. THE NAME APPEARED TWICE. The dialog's title is the product's name, and a live
 *     heading under it echoed the same name — and on a NEW product that heading showed
 *     the placeholder "Product Name", directly above a field labelled "Product Name".
 *     The heading is gone; the title already does that job, and the field's own text is
 *     the confirmation that it took what was typed.
 *
 *  2. THE GROUPS WERE NOT GROUPS. "PRICING", "INVENTORY" and "MULTI-UNITS" were 10px
 *     grey captions with a gap under them, which on screen is one undifferentiated wall
 *     of labels. They are FormGroups now: an edge, a tint from the app's hue family and
 *     an icon, so the eye finds "what it costs" by shape before reading a word.
 *
 *  3. THE FIELDS WERE BADLY DISTRIBUTED. Four price boxes on one row and three
 *     inventory boxes on another, with the two switches stranded at the far right of
 *     the inventory row behind a wide gap. Rows are grouped by what they answer now,
 *     and the switches have a row of their own.
 *
 *  4. IT COULD NOT SCROLL. Five multi-unit rows pushed the footer off the bottom of the
 *     frame and the last row was clipped. The body is a Flickable, so a product with
 *     twelve packs scrolls instead of losing its Save button.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.products : null
    readonly property var session: (typeof app !== "undefined" && app) ? app.session : null
    readonly property var workflows: (typeof app !== "undefined" && app)
                                     ? app.workflows : null

    readonly property int productId: context && context.product_id ? context.product_id : 0
    readonly property bool creating: productId === 0

    /* `products.view` opened this — the row action is not gated, because the record is
       also how a product is looked at. Writing is gated per control, so a view-only
       operator reads the whole product and cannot change it. `revision` first: `can()`
       is a slot with no notifier of its own. */
    readonly property bool canManage: session && session.revision >= 0
                                      && session.can("products.manage")

    preferredWidth: 1120
    preferredHeight: 860

    title: creating ? Strings.t("product.add_title", "New product")
                    : (row.name !== undefined && row.name
                       ? row.name
                       : Strings.t("product.edit_title", "Edit product"))

    // =====================================================================
    // STATE
    // =====================================================================
    property var row: ({})

    /* The packs, as rows being edited: [{ name, base_qty, price, barcode }]. Saved with
       the product, replaced whole — which is what replace_multi_units does. */
    property var packs: []

    readonly property var text_: row.text !== undefined ? row.text : ({})

    Component.onCompleted: {
        if (ctrl && ctrl.loadCategories)
            ctrl.loadCategories()
        if (!creating && ctrl)
            row = ctrl.product(productId) || ({})
        fill()
        /* A barcode handed in by the till's "this scan matched nothing" path is the one
           thing the record did not come with, so it is applied after fill(). */
        if (context && context.barcode)
            barcode.text = context.barcode
        name.forceActiveFocus()
    }

    /* One place that copies the row into the fields, so "new" and "edit" differ by what
       the row contains rather than by which widgets exist. */
    function fill() {
        name.text = row.name !== undefined ? row.name : ""
        barcode.text = row.barcode !== undefined ? row.barcode : ""
        purchase.text = row.purchase_price !== undefined
                        ? String(row.purchase_price) : ""
        sale.text = row.sale_price !== undefined ? String(row.sale_price) : ""
        /* Zero means "not set" for the two extra counters, and an empty box says that
           better than a 0 the operator has to read as absent. */
        half.text = row.price_half ? String(row.price_half) : ""
        wholesale.text = row.price_wholesale ? String(row.price_wholesale) : ""
        /* null is "use the shop's rate", 0 is "exempt", and they are different answers —
           so an empty box is null and a typed 0 stays 0. */
        tax.text = (row.tax_rate === undefined || row.tax_rate === null)
                   ? "" : String(row.tax_rate)
        threshold.text = row.low_stock_threshold !== undefined
                         ? String(row.low_stock_threshold) : ""
        stock.text = ""
        onPos.checked = row.show_on_pos !== false
        favorite.checked = row.is_favorite === true
        category.currentIndex = indexOf(category.model, row.category_id)
        unit.currentIndex = indexOf(unit.model, row.unit_id)

        var loaded = []
        var source = row.multi_units !== undefined ? row.multi_units : []
        for (var i = 0; i < source.length; i++)
            loaded.push({ name: source[i].name,
                          base_qty: source[i].base_qty,
                          price: source[i].price,
                          barcode: source[i].barcode })
        packs = loaded
    }

    function indexOf(model, id) {
        if (id === undefined || id === null)
            return 0
        for (var i = 0; i < model.length; i++)
            if (model[i].id === id)
                return 0 + i
        return 0
    }

    function number(text) {
        var value = parseFloat(String(text).replace(",", "."))
        return isNaN(value) ? 0 : value
    }

    /* The one derived figure worth showing, and it lives in the pricing group's heading
       rather than in a card or a stray line: it is a fact about that group and nothing
       else, and a heading is where a group states its summary. */
    readonly property real margin: number(sale.text) - number(purchase.text)
    readonly property string marginText: {
        if (number(sale.text) <= 0)
            return ""
        var pct = margin / number(sale.text) * 100
        return "\u200e" + (ctrl ? ctrl.moneyText(margin) : margin.toFixed(2))
               + "  (" + pct.toFixed(1) + "%)"
    }

    // -- packs -------------------------------------------------------------
    function addPack() {
        packs = packs.concat([{ name: "", base_qty: 1, price: 0, barcode: "" }])
    }

    function patchPack(index, changes) {
        if (index < 0 || index >= packs.length)
            return
        var next = []
        for (var i = 0; i < packs.length; i++)
            next.push(i === index ? Object.assign({}, packs[i], changes) : packs[i])
        packs = next
    }

    function removePack(index) {
        var next = packs.slice()
        next.splice(index, 1)
        packs = next
    }

    function save() {
        error.text = ""
        if (!ctrl)
            return
        /* Only complete rows travel: a half-typed pack is not a refusal, it is a row the
           operator started and abandoned. */
        var units = []
        for (var i = 0; i < packs.length; i++)
            if (String(packs[i].name).trim() !== "" && number(packs[i].base_qty) > 0)
                units.push({ name: packs[i].name,
                             base_qty: number(packs[i].base_qty),
                             price: number(packs[i].price),
                             barcode: packs[i].barcode })

        ctrl.save({
            name: name.text,
            barcode: barcode.text,
            category_id: category.model[category.currentIndex].id,
            unit_id: unit.model[unit.currentIndex].id,
            purchase_price: purchase.text,
            sale_price: sale.text,
            price_half: half.text === "" ? 0 : number(half.text),
            price_wholesale: wholesale.text === "" ? 0 : number(wholesale.text),
            /* null, not 0: an empty box means "whatever the shop charges", and a typed 0
               means exempt. Sending 0 for both would silently zero-rate every product
               the first time somebody saved it. */
            tax_rate: tax.text.trim() === "" ? null : number(tax.text),
            low_stock_threshold: threshold.text === "" ? 5 : threshold.text,
            stock: stock.text,
            show_on_pos: onPos.checked,
            is_favorite: favorite.checked,
            multi_units: units
        }, productId)
    }

    function adjustStock() {
        if (workflows)
            workflows.open("stock_adjust", { product_id: productId })
        close()
    }

    Connections {
        target: dialog.ctrl
        ignoreUnknownSignals: true
        function onSaved(product) { dialog.close() }
        function onRejected(message) { error.text = message }
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

    component Money: QC.TextField {
        Layout.fillWidth: true
        Layout.preferredHeight: Tokens.size.control
        enabled: dialog.canManage
        inputMethodHints: Qt.ImhFormattedNumbersOnly
        horizontalAlignment: TextInput.AlignRight
        font.family: Tokens.font.family
        font.pixelSize: Tokens.font.bodyLarge
    }

    // =====================================================================
    // LAYOUT
    // =====================================================================
    contentItem: ColumnLayout {
        spacing: Tokens.spacing.sm

        /*
         * The body scrolls.
         *
         * Five multi-unit rows used to push the footer off the bottom of the frame and
         * clip the last one — the fault the screenshots made obvious. A product with a
         * dozen packs is legitimate; losing the Save button is not.
         */
        Flickable {
            id: scroller
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: sheet.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            QC.ScrollBar.vertical: FluentScrollBar { policy: QC.ScrollBar.AsNeeded }

            ColumnLayout {
                id: sheet
                /* Room for the scrollbar. Without it the group panels run under the
                   bar and their right border disappears behind it — visible the
                   moment the dialog was rendered and looked at. */
                width: scroller.width - Tokens.spacing.md
                spacing: Tokens.spacing.sm

                // ---------------------------------------------------------
                // WHAT IT IS
                // ---------------------------------------------------------
                FormGroup {
                    title: Strings.t("product.identity", "Identity")
                    glyph: "ic_fluent_box_20_regular"
                    tone: "info"

                    Field {
                        label: Strings.t("product.name", "Name")
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

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.md

                        Field {
                            label: Strings.t("product.barcode", "Barcode")

                            QC.TextField {
                                id: barcode
                                Layout.fillWidth: true
                                Layout.preferredHeight: Tokens.size.control
                                enabled: dialog.canManage
                                horizontalAlignment: TextInput.AlignLeft
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.body
                            }
                        }

                        Field {
                            label: Strings.t("product.category", "Category")

                            QC.ComboBox {
                                id: category
                                Layout.fillWidth: true
                                Layout.preferredHeight: Tokens.size.control
                                enabled: dialog.canManage
                                textRole: "name"
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.body
                                model: {
                                    var out = [{ id: 0,
                                                 name: Strings.t("product.no_category",
                                                                 "No category") }]
                                    var src = dialog.ctrl ? dialog.ctrl.categories : null
                                    if (src)
                                        for (var i = 0; i < src.length; i++)
                                            out.push(src[i])
                                    return out
                                }
                            }
                        }

                        Field {
                            label: Strings.t("product.unit", "Unit")

                            QC.ComboBox {
                                id: unit
                                Layout.fillWidth: true
                                Layout.preferredHeight: Tokens.size.control
                                enabled: dialog.canManage
                                textRole: "name"
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.body
                                model: {
                                    var out = [{ id: 0,
                                                 name: Strings.t("product.no_unit",
                                                                 "No unit") }]
                                    var src = dialog.ctrl ? dialog.ctrl.units() : null
                                    if (src)
                                        for (var i = 0; i < src.length; i++)
                                            out.push(src[i])
                                    return out
                                }
                            }
                        }
                    }
                }

                // ---------------------------------------------------------
                // WHAT IT COSTS
                // ---------------------------------------------------------
                FormGroup {
                    title: Strings.t("product.pricing", "Pricing")
                    glyph: "ic_fluent_tag_20_regular"
                    tone: "success"

                    /* The margin, in the group's own heading. It is a fact about these
                       four boxes and nothing else, and a heading is where a group states
                       its summary — a stray line under the fields belonged to neither
                       the group above it nor the one below. */
                    actionItems: [
                        Text {
                            visible: dialog.marginText !== ""
                            text: Strings.t("product.profit_unit", "Margin") + "  "
                                  + dialog.marginText
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.caption
                            font.weight: Font.DemiBold
                            color: dialog.margin < 0 ? Tokens.danger : Tokens.success
                        }
                    ]

                    /* Cost and retail together — the pair every product needs and the two
                       the margin is between. */
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.md

                        Field {
                            label: Strings.t("product.purchase_price", "Cost")
                            Money { id: purchase }
                        }

                        Field {
                            label: Strings.t("product.sale_price", "Retail price")
                            required: true
                            Money { id: sale }
                        }

                        Field {
                            Layout.maximumWidth: 200
                            label: Strings.t("product.tax_rate", "VAT rate (%)")

                            QC.TextField {
                                id: tax
                                Layout.fillWidth: true
                                Layout.preferredHeight: Tokens.size.control
                                enabled: dialog.canManage
                                placeholderText: Strings.t("product.tax_rate.default",
                                                           "shop default")
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                                horizontalAlignment: TextInput.AlignRight
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.body
                            }
                        }
                    }

                    /* The two optional counters on a row of their own, so they read as
                       what they are: extras, not two more required prices. */
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.md

                        Field {
                            label: Strings.t("product.price_half", "Half-wholesale price")
                            Money {
                                id: half
                                placeholderText: Strings.t("price.unset", "same as retail")
                                font.pixelSize: Tokens.font.body
                            }
                        }

                        Field {
                            label: Strings.t("product.price_wholesale", "Wholesale price")
                            Money {
                                id: wholesale
                                placeholderText: Strings.t("price.unset", "same as retail")
                                font.pixelSize: Tokens.font.body
                            }
                        }

                        /* Half the row, deliberately: two optional prices beside two
                           empty columns says "there is no third price" better than
                           stretching them to fill the width would. */
                        Item { Layout.fillWidth: true }
                    }
                }

                // ---------------------------------------------------------
                // WHAT THERE IS
                // ---------------------------------------------------------
                FormGroup {
                    title: Strings.t("product.inventory", "Stock")
                    glyph: "ic_fluent_box_multiple_20_regular"
                    tone: "warning"

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.md

                        /* Only while creating. `save_product` never writes stock on an
                           update, and this follows it: a shelf count changes because
                           something arrived, sold, spoiled or was miscounted, and each of
                           those is a reason worth recording — the adjustment's job. */
                        Field {
                            visible: dialog.creating
                            Layout.maximumWidth: 240
                            label: Strings.t("product.opening_qty", "Opening quantity")

                            QC.TextField {
                                id: stock
                                Layout.fillWidth: true
                                Layout.preferredHeight: Tokens.size.control
                                enabled: dialog.canManage
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                                horizontalAlignment: TextInput.AlignRight
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.body
                            }
                        }

                        Field {
                            visible: !dialog.creating
                            Layout.maximumWidth: 340
                            label: Strings.t("product.current_stock", "In stock")

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Tokens.size.control
                                spacing: Tokens.spacing.sm

                                Text {
                                    text: "\u200e" + (dialog.text_.stock !== undefined
                                                      ? dialog.text_.stock : "—")
                                    font.family: Tokens.font.family
                                    font.pixelSize: Tokens.font.title
                                    font.weight: Font.DemiBold
                                    color: dialog.row.stock <= 0 ? Tokens.danger
                                         : dialog.row.stock <= dialog.row.low_stock_threshold
                                           ? Tokens.warning : Fluent.textPrimary
                                }

                                GlyphButton {
                                    glyph: "ic_fluent_arrow_swap_20_regular"
                                    text: Strings.t("stock.adjust", "Adjust")
                                    outlined: true
                                    enabled: dialog.canManage
                                    onClicked: dialog.adjustStock()
                                }

                                Item { Layout.fillWidth: true }
                            }
                        }

                        Field {
                            Layout.maximumWidth: 240
                            label: Strings.t("product.low_stock", "Low-stock threshold")

                            QC.TextField {
                                id: threshold
                                Layout.fillWidth: true
                                Layout.preferredHeight: Tokens.size.control
                                enabled: dialog.canManage
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                                horizontalAlignment: TextInput.AlignRight
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.body
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }

                    /* The two switches on a row of their own. They were stranded at the
                       far right of the field row behind a wide gap, which read as a
                       layout accident rather than as two answers. */
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.xl

                        QC.Switch {
                            id: onPos
                            enabled: dialog.canManage
                            text: Strings.t("product.show_on_pos", "Show on the till")
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.body
                        }

                        QC.Switch {
                            id: favorite
                            enabled: dialog.canManage
                            text: Strings.t("product.favorite", "Favourite")
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.body
                        }

                        Item { Layout.fillWidth: true }
                    }
                }

                // ---------------------------------------------------------
                // HOW IT IS SOLD
                // ---------------------------------------------------------
                /*
                 * A pack of six is part of deciding how this product is sold, not a
                 * separate record to go and manage: pos saves it with the product, and
                 * `replace_multi_units` exists for exactly this form. The barcode column
                 * is what earns the row — it is what makes one scan add six units at the
                 * pack's own price.
                 */
                FormGroup {
                    title: Strings.t("product.multi_units", "Multi-units")
                    glyph: "ic_fluent_box_multiple_20_regular"
                    tone: "primary"
                    gap: Tokens.spacing.xs

                    actionItems: [
                        GlyphButton {
                            glyph: "ic_fluent_add_20_regular"
                            text: Strings.t("product.add_multi_unit", "Add a unit")
                            outlined: true
                            enabled: dialog.canManage
                            onClicked: dialog.addPack()
                        }
                    ]

                    Text {
                        Layout.fillWidth: true
                        visible: dialog.packs.length === 0
                        text: Strings.t("mu.hint",
                                        "A pack or a case with its own barcode and price. Scanning it adds the whole pack.")
                        wrapMode: Text.WordWrap
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.caption
                        color: Fluent.textTertiary
                    }

                    /* Column captions once, and only when there is a row to caption. */
                    RowLayout {
                        Layout.fillWidth: true
                        visible: dialog.packs.length > 0
                        spacing: Tokens.spacing.xs

                        Text {
                            Layout.fillWidth: true
                            text: Strings.t("mu.name", "Unit")
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.overline
                            color: Fluent.textTertiary
                        }

                        Text {
                            Layout.preferredWidth: 100
                            horizontalAlignment: Text.AlignHCenter
                            text: Strings.t("mu.qty", "× qty")
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.overline
                            color: Fluent.textTertiary
                        }

                        Text {
                            Layout.preferredWidth: 150
                            horizontalAlignment: Text.AlignRight
                            text: Strings.t("mu.price", "Price")
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.overline
                            color: Fluent.textTertiary
                        }

                        Text {
                            Layout.preferredWidth: 230
                            text: Strings.t("mu.barcode", "Barcode")
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.overline
                            color: Fluent.textTertiary
                        }

                        Item { Layout.preferredWidth: Tokens.size.controlSmall }
                    }

                    Repeater {
                        model: dialog.packs

                        delegate: RowLayout {
                            id: pack
                            required property var modelData
                            required property int index

                            Layout.fillWidth: true
                            spacing: Tokens.spacing.xs

                            QC.TextField {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Tokens.size.controlSmall
                                enabled: dialog.canManage
                                text: pack.modelData.name
                                placeholderText: Strings.t("mu.name.ph", "Pack of 6")
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.body
                                onEditingFinished: dialog.patchPack(pack.index,
                                                                   { name: text })
                            }

                            QC.TextField {
                                Layout.preferredWidth: 100
                                Layout.preferredHeight: Tokens.size.controlSmall
                                enabled: dialog.canManage
                                text: String(pack.modelData.base_qty)
                                horizontalAlignment: TextInput.AlignHCenter
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.body
                                onEditingFinished: dialog.patchPack(pack.index,
                                                                   { base_qty: text })
                            }

                            QC.TextField {
                                Layout.preferredWidth: 150
                                Layout.preferredHeight: Tokens.size.controlSmall
                                enabled: dialog.canManage
                                text: String(pack.modelData.price)
                                horizontalAlignment: TextInput.AlignRight
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.body
                                onEditingFinished: dialog.patchPack(pack.index,
                                                                   { price: text })
                            }

                            QC.TextField {
                                Layout.preferredWidth: 230
                                Layout.preferredHeight: Tokens.size.controlSmall
                                enabled: dialog.canManage
                                text: pack.modelData.barcode
                                placeholderText: Strings.t("mu.barcode", "Barcode")
                                horizontalAlignment: TextInput.AlignLeft
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.body
                                onEditingFinished: dialog.patchPack(pack.index,
                                                                   { barcode: text })
                            }

                            IconButton {
                                glyph: "ic_fluent_delete_20_regular"
                                glyphSize: Tokens.icon.sm
                                glyphColor: Tokens.danger
                                enabled: dialog.canManage
                                tooltip: Strings.t("action.delete", "Delete")
                                onClicked: dialog.removePack(pack.index)
                            }
                        }
                    }
                }
            }
        }

        // -----------------------------------------------------------------
        // COMMIT
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

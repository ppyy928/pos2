import QtQuick
import QtQuick.Controls as QC
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQuick.Window
import FluentControls
import Mizan

/*
 * One product, on one page, in four groups you can see.
 *
 *   Atlas Beans                                    ← the dialog title, once
 *   ┌─ 📦 IDENTITY ───────────── [ 🖼 Change ] [ 🗑 ] ──────────────────┐
 *   │  ┌────────┐  Name    [ Atlas Beans                            ]  │
 *   │  │ photo  │  Barcode [ 5449000996 ] Category [ Drinks ▾ ] Unit ▾  │
 *   │  └────────┘                                                       │
 *   └───────────────────────────────────────────────────────────────────┘
 *   ┌─ 💰 PRICING ───────────────────── margin 135.15 (20.1%) ──────────┐
 *   │  Cost [ 536.76 ]  Retail [ 671.91 ]  VAT [ shop default ▾ ]       │
 *   │  ⌄ Wholesale prices                                               │
 *   └───────────────────────────────────────────────────────────────────┘
 *   ┌─ 📊 STOCK ────────────────────────────────────────────────────────┐
 *   │  In stock  295  [ Adjust ]   Low-stock [ 5 ]                      │
 *   └───────────────────────────────────────────────────────────────────┘
 *   ┌─ 🗃 MULTI-UNITS ─────────────────────────── [ + Add a unit ] ─────┐
 *   │  Pack of 6   × 6   700.00   2885822280736              🗑          │
 *   └───────────────────────────────────────────────────────────────────┘
 *   ──────────────────────────────────────────────────────────────────────
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
 *
 * AND THEN THE SCROLLING ITSELF WAS THE COMPLAINT
 *
 * A Flickable answered "the footer disappears" and created a worse problem: the dialog
 * asked for a FIXED 860px whatever the screen was, so on a 1080p till it left 200px of
 * desk empty and scrolled anyway — the Multi-units group was permanently below the fold
 * and the last visible group was sliced mid-control by the footer. Three changes, and
 * between them the common case does not scroll at all:
 *
 *  * THE FORM ASKS FOR WHAT IT NEEDS, UP TO THE WHOLE WINDOW. `preferredHeight` is the
 *    measured height of the sheet plus the chrome around it, capped by AppDialog at the
 *    window: a product with no packs opens exactly as tall as it is, and one with twelve
 *    opens full-screen. Nothing is a fixed number any more, so no screen size is the
 *    one this form was designed for at the expense of the rest.
 *
 *  * `breathing` IS 20px, NOT 32. On a full-height form that margin is the difference
 *    between showing the last group and scrolling for it, and a dialog 20px from the
 *    edge still reads as a dialog — the smoke behind it is what says so.
 *
 *  * WHAT HAS THE KEYBOARD STAYS IN THE FRAME. Tabbing into a pack's barcode used to
 *    move focus to a control below the fold and leave the view where it was: the
 *    operator typed into a field they could not see. `ensureVisible` follows the focus,
 *    and adding a pack scrolls to the row it just created.
 *
 * THE PHOTO
 *
 * Optional, and in the Identity group rather than a group of its own: a picture of the
 * product is part of what the product IS, and a fifth panel for one thumbnail would say
 * it is a separate subject. It is a 160px square beside the name and the barcode — the
 * same square, cropped the same way, that the till's product card draws, so what the
 * form shows is what the shop will see. Clicking it chooses a file; the two buttons in
 * the group's heading are the explicit path to the same two acts.
 *
 * Nothing is copied while the form is open: the picked file is previewed straight from
 * where it sits and only imported when Save is pressed, so cancelling a form leaves no
 * file behind. Removing a photo is likewise a decision the row records — the file is
 * forgotten by the data layer after the save, and only if no other product was given
 * the same picture.
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

    preferredWidth: 1280

    /*
     * As tall as the form is, and never taller than the window.
     *
     * `preferredHeight` is left at 0 — "as tall as the content" — and the content
     * is measurable because the Flickable below states an implicitHeight of its
     * own (a Flickable's is 0 by default, which is what used to make this dialog
     * unmeasurable and is why it carried a hardcoded 860). AppDialog caps the
     * result at the window, so a normal product opens at exactly its own height
     * and one with a dozen packs opens full-screen and scrolls the remainder.
     *
     * The arithmetic that briefly stood here — content plus a measured "chrome" —
     * was five pixels wrong, and five pixels wrong is a scrollbar on a form that
     * fits. Letting the dialog measure itself cannot be wrong by any pixels.
     */

    /* 20px of air rather than 32. See the header: on a form that would otherwise
       scroll, that margin is a field. */
    breathing: 2 * Tokens.spacing.lg

    title: creating ? Strings.t("product.add_title", "New product")
                    : (row.name !== undefined && row.name
                       ? row.name
                       : Strings.t("product.edit_title", "Edit product"))

    /*
     * The title row carries the two till switches.
     *
     * Neither is a stock fact, and the Stock group was the wrong home for them:
     * "show this on the till" and "pin it to Favourites" decide where the product
     * appears in the shop, and that belongs where the record announces itself
     * rather than four groups down, wedged between a low-stock threshold and a
     * list of packs. The header is also the one row that does not scroll, so both
     * answers stay readable while the rest of the form is filled in.
     *
     * Replacing the style's header means restating what it does: the title at
     * `subtitle` size and DemiBold, `padding` in from three edges, and the same
     * "not until the popup is really on the overlay" guard FluentWinUI3's own
     * Dialog.qml uses — a header that measures itself before that makes the dialog
     * jump as it opens. In Arabic the RowLayout mirrors itself, so the title goes
     * right and the switches left, with no second rule to write.
     */
    header: Item {
        visible: dialog.title !== "" && parent?.parent === QC.Overlay.overlay
        implicitHeight: visible ? titleRow.implicitHeight + dialog.padding : 0

        RowLayout {
            id: titleRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: dialog.padding
            anchors.rightMargin: dialog.padding
            anchors.topMargin: dialog.padding
            spacing: Tokens.spacing.lg

            Text {
                /* Centred against the switches, which are taller than a line of
                   24px type: top-aligned it would sit a few pixels above them and
                   read as two rows that happen to overlap. */
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: dialog.title
                elide: Text.ElideRight
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.subtitle
                font.weight: Font.DemiBold
                color: Fluent.textPrimary
            }

            QC.Switch {
                id: onPos
                Layout.alignment: Qt.AlignVCenter
                enabled: dialog.canManage
                text: Strings.t("product.show_on_pos", "Show on the till")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
            }

            QC.Switch {
                id: favorite
                Layout.alignment: Qt.AlignVCenter
                enabled: dialog.canManage
                text: Strings.t("product.favorite", "Favourite")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
            }
        }
    }

    // =====================================================================
    // STATE
    // =====================================================================
    property var row: ({})

    /* The packs, as rows being edited: [{ name, base_qty, price, barcode }]. Saved with
       the product, replaced whole — which is what replace_multi_units does. */
    property var packs: []

    /*
     * Whether the wholesale counters are on screen.
     *
     * Four price boxes on one form is what this dialog was criticised for, and the
     * criticism was right: a shop adding a tin of beans answers cost and price, and the
     * other two are a decision it makes for a handful of products at most. So they are
     * behind a disclosure that opens itself for a product that already uses them —
     * which means the form is two prices for almost everything and four for the few
     * that need four, instead of four for everything.
     */
    property bool tiersOpen: false

    /* The VAT rate this product is charged at: 0 is "the shop's default", anything else
       is a row on the taxes screen. Held here rather than read off the combo, because the
       combo is rebuilt when the language changes and its index would not survive that. */
    property int taxId: 0

    /*
     * The photo, as three separate facts.
     *
     * "This product has one", "the operator just chose one" and "the operator took
     * it off" are three different answers and only the first one survives a
     * Cancel, so they are three properties rather than one string that would have
     * to mean all three. `imagePreview` is what the thumbnail draws and
     * `save()` sends the other two: a picked file to import, or a clearance.
     *
     * A picked file is previewed from where the operator picked it. Copying it
     * into the shop's folder when it is chosen would leave a file behind for every
     * form that was opened and closed again.
     */
    property string imagePicked: ""
    property bool imageCleared: false

    readonly property string imageStored: row.image_url !== undefined
                                          ? row.image_url : ""
    readonly property string imagePreview: imagePicked !== "" ? imagePicked
                                         : imageCleared ? "" : imageStored
    readonly property bool hasImage: imagePreview !== ""

    readonly property var taxCtrl: (typeof app !== "undefined" && app) ? app.taxes : null

    /* The picker's entries, default first. Built from the taxes controller so the list a
       product chooses from is the list the taxes screen manages — one definition. */
    readonly property var taxOptions: {
        var out = [{ id: 0, label: Strings.t("product.tax.default", "Shop default") }]
        var rows = taxCtrl ? taxCtrl.rows : []
        for (var i = 0; i < rows.length; i++)
            out.push({ id: rows[i].id,
                       label: rows[i].name + "  \u200e" + rows[i].rate_text })
        return out
    }

    function taxIndex(id) {
        for (var i = 0; i < taxOptions.length; i++)
            if (taxOptions[i].id === id)
                return i
        return 0
    }

    readonly property var text_: row.text !== undefined ? row.text : ({})

    Component.onCompleted: {
        if (ctrl && ctrl.loadCategories)
            ctrl.loadCategories()
        /* The rate list, if nothing has loaded it yet: this dialog opens from the till's
           unknown-barcode path as well as from the products page, and the taxes screen
           may never have been visited. */
        if (taxCtrl && taxCtrl.total === 0)
            taxCtrl.load()
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
        /* A rate is named, not typed: 0 means "the shop's default", which is what the
           first entry in the picker stands for. */
        taxId = row.tax_id ? row.tax_id : 0
        threshold.text = row.low_stock_threshold !== undefined
                         ? String(row.low_stock_threshold) : ""
        stock.text = ""
        /* A new product has a shelf until told otherwise — a shop is mostly shelves,
           so the exception is the thing that gets declared. */
        tracked.checked = creating ? true : row.track_stock !== false
        /* Collapsed unless this product actually uses the other counters, so the form
           opens at the length of the question it is usually asking. */
        tiersOpen = (row.price_half > 0) || (row.price_wholesale > 0)
        onPos.checked = row.show_on_pos !== false
        favorite.checked = row.is_favorite === true
        category.currentIndex = indexOf(category.model, row.category_id)
        unit.currentIndex = indexOf(unit.model, row.unit_id)
        /* The photo the row carries is read straight off it by `imageStored`;
           what is reset here is the two decisions the operator can make about it,
           so re-filling the form is the record again and not the last edit of it. */
        imagePicked = ""
        imageCleared = false

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
        /* Scrolled to after the Repeater has built the row and the sheet has
           remeasured — contentHeight is still the old one during this call. A row
           added below the fold and left there is a button that appears to have
           done nothing. */
        Qt.callLater(scrollToEnd)
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

    // -- the photo ---------------------------------------------------------
    /* Chosen, not imported: `save()` hands the path to Python, which copies and
       downscales it. Choosing again replaces the choice, and it cancels a pending
       removal — the last thing the operator did is the answer. */
    function pickImage(fileUrl) {
        var picked = String(fileUrl || "")
        if (picked === "")
            return
        imagePicked = picked
        imageCleared = false
    }

    function clearImage() {
        imagePicked = ""
        imageCleared = true
    }

    // -- scrolling ---------------------------------------------------------
    /*
     * Keep one item inside the frame.
     *
     * Called on every focus change, so the first thing it does is establish that
     * the item is one of ours: the window's focus can be in the page behind this
     * dialog, or inside a ComboBox's popup, and neither is a coordinate in this
     * sheet. `mapToItem` would answer for those too, with a number that scrolls
     * the form somewhere absurd.
     */
    function ensureVisible(item) {
        if (!item || scroller.height <= 0)
            return
        var node = item
        while (node && node !== sheet)
            node = node.parent
        if (node !== sheet)
            return

        var margin = Tokens.spacing.md
        var top = item.mapToItem(sheet, 0, 0).y
        var bottom = top + item.height
        var limit = Math.max(0, scroller.contentHeight - scroller.height)
        if (top - margin < scroller.contentY)
            scroller.contentY = Math.max(0, top - margin)
        else if (bottom + margin > scroller.contentY + scroller.height)
            scroller.contentY = Math.min(limit,
                                         bottom + margin - scroller.height)
    }

    function scrollToEnd() {
        scroller.contentY = Math.max(0, scroller.contentHeight - scroller.height)
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
            /* 0 is not a rate, it is "the shop's default" — Python turns it into the
               NULL that `_product_rate` reads as "fall back". A named rate travels as
               its id, so moving that rate later moves this product with it. */
            tax_id: dialog.taxId,
            low_stock_threshold: threshold.text === "" ? 5 : threshold.text,
            stock: stock.text,
            track_stock: tracked.checked,
            show_on_pos: onPos.checked,
            is_favorite: favorite.checked,
            /* The photo, in the two keys Python distinguishes: a file to import,
               or a clearance. Sending neither — which is what an untouched form
               does — leaves the product's own picture alone. */
            image: dialog.imagePicked,
            image_clear: dialog.imageCleared && dialog.imagePicked === "",
            multi_units: units
        }, productId)
    }

    /*
     * The stock sheet opens OVER this form, and this form stays.
     *
     * It used to close itself first, which threw away every edit the operator had
     * typed and left them nowhere to come back to — the worst version of the
     * behaviour, because a stock correction is exactly the errand somebody runs in
     * the middle of editing a product. DialogHost stacks, so the sheet simply draws
     * on top; what this has to do instead is notice the adjustment when it lands.
     */
    function adjustStock() {
        if (workflows)
            workflows.open("stock_adjust", { product_id: productId })
    }

    /* Re-read the record without touching the form.
     *
     * `fill()` is deliberately NOT called: it copies the row into the fields, and an
     * adjustment made from a form with unsaved edits must not overwrite them. Only
     * `row` moves, and the stock figure is bound to it. */
    function refreshStock() {
        if (!creating && ctrl)
            row = ctrl.product(productId) || row
    }

    Connections {
        target: dialog.ctrl
        ignoreUnknownSignals: true
        function onSaved(product) { dialog.close() }
        function onRejected(message) { error.text = message }
        /* The sheet above just moved this product's stock. */
        function onAdjusted(result) { dialog.refreshStock() }
    }

    /*
     * The file picker — the platform's own.
     *
     * QtQuick.Dialogs' FileDialog is the native Windows dialog here, which matters
     * for a shop: the operator's photos are in the folder Windows already
     * remembers, on the phone Windows already mounted, and a hand-rolled QML
     * browser would know about neither.
     *
     * The filter is the same list of suffixes the data layer accepts
     * (`db.IMAGE_SUFFIXES`). Both sides state it, because a filter is a
     * convenience and a refusal is a rule: a file dragged past the filter, or
     * picked with "All files" on a platform that offers it, still meets the rule.
     */
    FileDialog {
        id: picker
        title: Strings.t("product.image.pick", "Choose a product photo")
        nameFilters: [Strings.t("product.image.filter",
                                "Images (*.png *.jpg *.jpeg *.webp *.bmp)")]
        onAccepted: dialog.pickImage(picker.selectedFile)
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

    component Money: NumberField {
        Layout.fillWidth: true
        Layout.preferredHeight: Tokens.size.control
        enabled: dialog.canManage
    }

    /*
     * The photo, or the offer to add one.
     *
     * A square, and the same square the till's product card draws: cropped to fill
     * rather than letterboxed, so what the operator approves here is what the shop
     * will see there. Its corners are square for the reason PosTile's own header
     * gives — a rounded Rectangle in Qt Quick does not clip its children to its
     * arcs, so a rounded frame around a photo is a rounding that only pretends.
     *
     * The tile IS the button. An empty one says what it is for and a full one says
     * so on hover, which is one gesture for the whole feature; the pair of buttons
     * in the group's heading is the same two acts written out for anyone who does
     * not try clicking a picture. For an operator without `products.manage` it is
     * neither — no hover, no click, no hint — because the photo is then a fact
     * about the product and not a control.
     */
    component PhotoTile: Rectangle {
        id: photo

        Layout.preferredWidth: Tokens.size.thumb
        Layout.preferredHeight: Tokens.size.thumb
        Layout.alignment: Qt.AlignTop

        readonly property bool live: dialog.canManage
        readonly property bool hovered: hover.containsMouse

        color: dialog.hasImage ? Fluent.subtleTertiary
             : photo.hovered ? Tokens.infoTint : Fluent.subtleSecondary
        border.width: 1
        border.color: photo.hovered ? Tokens.info : Fluent.dividerBorder
        clip: true

        QC.ToolTip.text: Strings.t("product.image.hint",
                                   "Optional. Shown on the till's product cards.")
        QC.ToolTip.visible: photo.hovered
        QC.ToolTip.delay: 700

        Image {
            anchors.fill: parent
            visible: dialog.hasImage
            source: dialog.imagePreview
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            /* The picked file is the operator's original — 4000px off a phone —
               and this draws it at 168. Decoding it whole would cost 50 MB for a
               thumbnail; the stored copy is capped at 640px by the data layer, and
               this caps the preview of the one that has not been stored yet. */
            sourceSize.width: 2 * Tokens.size.thumb
            mipmap: true
        }

        /* Nothing there yet: the invitation, which is also the whole explanation
           of what this square is. */
        Column {
            anchors.centerIn: parent
            visible: !dialog.hasImage
            spacing: Tokens.spacing.xs

            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                icon: "ic_fluent_image_add_20_regular"
                size: Tokens.icon.lg
                color: photo.hovered ? Tokens.info : Fluent.textTertiary
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: photo.live ? Strings.t("product.image.add", "Add a photo")
                                 : Strings.t("product.image", "Photo")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.caption
                color: photo.hovered ? Tokens.info : Fluent.textTertiary
            }
        }

        /* On hover over a photo that is there: what a click would do. White on a
           dark scrim rather than a themed pair, because what is under it is a
           photograph and neither theme's ink can be trusted against one. */
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Tokens.size.controlSmall
            visible: dialog.hasImage && photo.hovered
            color: Qt.rgba(0, 0, 0, 0.55)

            Text {
                anchors.centerIn: parent
                text: Strings.t("product.image.change", "Change")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.caption
                font.weight: Font.DemiBold
                color: "#FFFFFF"
            }
        }

        MouseArea {
            id: hover
            anchors.fill: parent
            enabled: photo.live
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: picker.open()
        }
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
            /* What it would like to be: the whole sheet, so the dialog above can
               measure itself from its content instead of being told a number. A
               Flickable's own implicitHeight is 0, which makes any dialog that
               contains one unmeasurable — the fault behind the fixed 860 this form
               used to carry. `fillHeight` still shrinks it when the window is the
               smaller of the two, which is the case where scrolling is the answer. */
            implicitHeight: sheet.implicitHeight
            clip: true
            contentWidth: width
            contentHeight: sheet.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            /*
             * What has the keyboard, watched rather than polled — so that tabbing
             * into a control below the fold brings it into view instead of typing
             * into a field the operator cannot see.
             *
             * Read HERE and not on the dialog. `Window` is an attached property of
             * an ITEM, and a Popup is not one: on the dialog itself it resolves to
             * null every time, which is precisely how the first version of this
             * read as correct and did nothing at all. Probing it is the only way
             * that shows up — `dlg.focused` was None while the window's own
             * `activeFocusItem` was a real item.
             */
            readonly property var focusedItem: Window.activeFocusItem
            onFocusedItemChanged: dialog.ensureVisible(focusedItem)

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

                    /* The photo's two acts, named. The tile below does both on its
                       own, but a picture that has to be clicked to be discovered is
                       a feature half the shops will never find. */
                    actionItems: [
                        GlyphButton {
                            glyph: "ic_fluent_image_add_20_regular"
                            text: dialog.hasImage
                                  ? Strings.t("product.image.change", "Change")
                                  : Strings.t("product.image.add", "Add a photo")
                            outlined: true
                            enabled: dialog.canManage
                            onClicked: picker.open()
                        },
                        IconButton {
                            glyph: "ic_fluent_delete_20_regular"
                            glyphSize: Tokens.icon.sm
                            glyphColor: Tokens.danger
                            visible: dialog.hasImage
                            enabled: dialog.canManage
                            tooltip: Strings.t("product.image.remove",
                                               "Remove the photo")
                            onClicked: dialog.clearImage()
                        }
                    ]

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.lg

                        PhotoTile {}

                        /* The three questions that name a product, in their own
                           column so the photo sits beside all of them rather than
                           above them: the two columns are within a few pixels of
                           the same height, which is why this reads as one block
                           and not as a picture with a form stuck under it. */
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacing.md

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
                    }
                }

                /*
                 * WHAT IT COSTS, AND WHAT THERE IS — side by side.
                 *
                 * Two groups of three fields each, stacked, is 400px of a form that
                 * had 200px to spare and a Multi-units group permanently below the
                 * fold. They are the two halves of the same question about the same
                 * product and neither is wide: at 1280 the dialog has 620px per
                 * column, which is more than three money boxes need.
                 *
                 * A GridLayout and not a RowLayout, for the one thing a Row cannot
                 * do: below 1000px of sheet there is not room for two columns of
                 * fields, and `columns: 1` re-flows the same two groups into the
                 * stack they used to be — no second layout, no duplicated content.
                 */
                GridLayout {
                    Layout.fillWidth: true
                    columns: sheet.width >= 1000 ? 2 : 1
                    columnSpacing: Tokens.spacing.sm
                    rowSpacing: Tokens.spacing.sm

                    FormGroup {
                        Layout.alignment: Qt.AlignTop
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
                    }

                    /*
                     * Which VAT rate this product is charged at — a name from the
                     * taxes screen, not a percentage typed here.
                     *
                     * It used to be a free box for "VAT rate (%)" that did nothing
                     * at all: `fetch_product` returns `tax_id` and no `tax_rate`, so
                     * the box always opened empty, and `save_product` has no
                     * `tax_rate` to write, so whatever was typed went nowhere. A
                     * product carries a pointer into the rate list, which is what
                     * lets a rate move without editing eight hundred products.
                     *
                     * "Shop default" is the first entry and means NULL: the rate the
                     * taxes screen marks as the default. That is what nearly every
                     * product wants, and naming "Exempt" instead is a decision the
                     * shop made rather than one it never got round to.
                     *
                     * On a row of its own, because this group shares its width with
                     * the stock group now: a third box beside the two prices left the
                     * rate 150px wide, which elides "The shop's default rate" to "The
                     * shop's …" — a picker whose whole job is to name the rate.
                     */
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.md

                        Field {
                            Layout.maximumWidth: 320
                            label: Strings.t("product.tax", "VAT rate")

                            QC.ComboBox {
                                id: tax
                                Layout.fillWidth: true
                                Layout.preferredHeight: Tokens.size.control
                                enabled: dialog.canManage
                                textRole: "label"
                                model: dialog.taxOptions
                                currentIndex: dialog.taxIndex(dialog.taxId)
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.body
                                onActivated: (index) => {
                                    dialog.taxId = dialog.taxOptions[index].id
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }


                        /*
                         * The wholesale counters, folded away.
                         *
                         * One price is the answer for almost every product, and four boxes
                         * on the form made the two that matter harder to find. The link
                         * below opens the other two, and `fill()` opens it by itself for a
                         * product that already has them — so nobody who uses them has to
                         * know the link exists.
                         */
                        RowLayout {
                            Layout.fillWidth: true
                            visible: !dialog.tiersOpen
                            spacing: Tokens.spacing.sm

                            GlyphButton {
                                glyph: "ic_fluent_chevron_down_20_regular"
                                text: Strings.t("product.more_prices",
                                                "Wholesale prices")
                                flat: true
                                enabled: dialog.canManage
                                onClicked: dialog.tiersOpen = true
                            }

                            Item { Layout.fillWidth: true }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            visible: dialog.tiersOpen
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
                        Layout.alignment: Qt.AlignTop
                        title: Strings.t("product.inventory", "Stock")
                        glyph: "ic_fluent_box_multiple_20_regular"
                        tone: "warning"

                        /*
                         * Does this product have a shelf at all?
                         *
                         * A restaurant's couscous, a barber's haircut, a phone top-up: there
                         * is nothing to count, nothing runs out, and a stock figure for it is
                         * a lie that grows more negative with every sale. Switched off, every
                         * stock path in the data layer skips it — sale, return, delivery,
                         * adjustment and stocktake — and the till and the table show an
                         * infinity sign instead of a number.
                         *
                         * First in the group, because it decides whether the rest of the
                         * group means anything. The fields below hide when it is off rather
                         * than dimming: a threshold on something that never runs out is not
                         * a disabled setting, it is a question that does not apply.
                         */
                        QC.Switch {
                            id: tracked
                            /* Named so a harness can reach it: this switch decides whether
                               six code paths in the data layer touch a number, and that is
                               worth being able to assert from outside. */
                            objectName: "trackStock"
                            checked: true
                            enabled: dialog.canManage
                            text: Strings.t("product.track_stock", "Track stock")
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.body
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: !tracked.checked
                            text: Strings.t("product.track_stock.off",
                                            "Always available. Selling it never changes a count — for services and made-to-order items.")
                            wrapMode: Text.WordWrap
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.caption
                            color: Tokens.warning
                        }

                        RowLayout {
                            visible: tracked.checked
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

                                NumberField {
                                    id: stock
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Tokens.size.control
                                    enabled: dialog.canManage
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

                                NumberField {
                                    id: threshold
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Tokens.size.control
                                    enabled: dialog.canManage
                                    font.pixelSize: Tokens.font.body
                                }
                            }

                            Item { Layout.fillWidth: true }
                        }
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

                            NumberField {
                                Layout.preferredWidth: 100
                                Layout.preferredHeight: Tokens.size.controlSmall
                                enabled: dialog.canManage
                                text: String(pack.modelData.base_qty)
                                horizontalAlignment: TextInput.AlignHCenter
                                font.pixelSize: Tokens.font.body
                                onEditingFinished: dialog.patchPack(pack.index,
                                                                   { base_qty: text })
                            }

                            NumberField {
                                Layout.preferredWidth: 150
                                Layout.preferredHeight: Tokens.size.controlSmall
                                enabled: dialog.canManage
                                text: String(pack.modelData.price)
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
        /* A rule between the sheet and the buttons.
         *
         * On a form that scrolls, the last group used to be sliced by the footer
         * with nothing to say whether the cut was the end of the form or the edge
         * of the frame. A line answers that: what is above it is the record, what
         * is below it is what to do with the record, and content meeting a line is
         * content that continues. */
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.xs
            implicitHeight: 1
            color: Fluent.dividerBorder
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
            id: commit
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

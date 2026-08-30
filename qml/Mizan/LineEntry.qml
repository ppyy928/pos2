import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * One delivery line, entered whole: how many, what it cost, what it sells for.
 *
 *   ┌─────────────────────────────────────────────────────────────┐
 *   │  Atlas Beans                                                │
 *   │  5449000996 · 275 in stock · last 90.00 on PIN-0166         │
 *   ├─────────────────────────────────────────────────────────────┤
 *   │  QUANTITY                                                   │
 *   │  ┌───────────────────────────────────────────────────────┐  │
 *   │  │                                                   12  │  │
 *   │  └───────────────────────────────────────────────────────┘  │
 *   │  COST                        SELLING PRICE                  │
 *   │  ┌─────────────────────┐     ┌─────────────────────────┐    │
 *   │  │             250.00  │     │               320.00    │    │
 *   │  └─────────────────────┘     └─────────────────────────┘    │
 *   │  margin 70.00 (21.9%)              line total 3 000.00      │
 *   ├─────────────────────────────────────────────────────────────┤
 *   │  [ QTY  ] [7][8][9]                                         │
 *   │  [ COST ] [4][5][6]                                         │
 *   │  [ SELL ] [1][2][3]                                         │
 *   │           [0][.][⌫]                                         │
 *   │                           [ Cancel ]      [ Add a line ]    │
 *   └─────────────────────────────────────────────────────────────┘
 *
 * WHY A LINE GETS ITS OWN SHEET
 *
 * A delivery line is three numbers decided together — what arrived, what it cost,
 * and what it will be sold for, the third following from the second — so they belong
 * on one surface with the margin between them in view. Before this they were three
 * separate hunts across a row.
 *
 * This is also the ONLY keypad on the delivery screen now. The screen behind it used
 * to carry one too, for editing lines in place, and two keypads for one job is one
 * too many: the pen on a row opens this, and this is where numbers are typed.
 *
 * THE KEYPAD AND THE FIELDS ARE ONE CONTROL
 *
 * There is no Apply. The pad types INTO whichever field has focus, and the mode
 * column and the focus are two views of the same state:
 *
 *   - tapping a field selects all of it and lights that mode on the pad
 *   - tapping a mode focuses that field and selects all of it
 *
 * Selecting all is what makes the first keystroke replace rather than append, which
 * is what an operator expects of a figure they are correcting, and it is why Apply is
 * not needed: the value is already where it belongs as it is typed. The live field
 * also carries a brand-coloured border, so which figure the pad is aimed at is
 * legible without reading the mode column.
 *
 * Focus starts on the quantity, because that is the one figure every line needs and
 * the other two are usually already right.
 */
QC.Popup {
    id: sheet

    // =====================================================================
    // API
    // =====================================================================
    /* The product being added or corrected: { id, name, barcode }. */
    property var product: null

    /* Seeded values. The caller fetches them — from the last delivery of this
       product, or from the line being edited. */
    property real qty: 1
    property real cost: 0
    property real price: 0

    /* Context under the name: what is on the shelf, and what the last delivery of
       this product cost. Shown rather than silently used, because "the same as last
       time" is the answer nine lines in ten and the tenth is the one worth noticing. */
    property string lastText: ""
    property string stockText: ""

    /* An existing line is being corrected rather than a new one added. Changes one
       word on the confirm button and nothing else. */
    property bool editing: false

    signal accepted(real qty, real cost, real price)

    function money(value) {
        return (typeof app !== "undefined" && app && app.purchases)
               ? app.purchases.moneyText(value) : String(value)
    }

    // =====================================================================
    // FRAME
    // =====================================================================
    parent: QC.Overlay.overlay
    anchors.centerIn: QC.Overlay.overlay
    /* Measured against the overlay it is parented to: the attached `Window` property
       only works on Items, and a Popup is not one. */
    width: Math.min(620, (parent ? parent.width : 800) - 2 * Tokens.spacing.xxl)
    padding: 0
    modal: true
    focus: true

    background: Rectangle {
        color: Fluent.popupBackground
        radius: Tokens.radius.lg
        border.width: 1
        border.color: Fluent.dividerBorder
    }

    /* Opening always starts on the quantity, in both modes: it is the figure every
       line needs, and the other two are usually already right. */
    onOpened: {
        qtyField.text = sheet.qty > 0 ? String(sheet.qty) : "1"
        costField.text = sheet.cost > 0 ? String(sheet.cost) : ""
        priceField.text = sheet.price > 0 ? String(sheet.price) : ""
        focusField("qty")
    }

    // =====================================================================
    // ONE STATE, TWO VIEWS
    // =====================================================================
    /* Which field the pad is typing into. Named with the pad's own vocabulary so the
       mode column and the focus can never disagree about what is in force. */
    property string mode: "qty"

    function fieldFor(name) {
        if (name === "cost")
            return costField
        if (name === "price")
            return priceField
        return qtyField
    }

    /* The one function both directions go through. A field tapped by hand calls it
       from its own focus handler; a mode tapped on the pad calls it directly — so
       there is exactly one place that decides what "the live field" means. */
    function focusField(name) {
        mode = name
        var field = fieldFor(name)
        field.forceActiveFocus()
        /* Selected, not just focused. The first keystroke on a figure being corrected
           should replace it: an operator retyping a cost of 250 as 320 means 320, not
           250320. This is also what makes an Apply button unnecessary. */
        field.selectAll()
    }

    // -- the pad types into the live field ---------------------------------
    function key(value) {
        var field = fieldFor(mode)
        if (value === "clear") {
            field.text = ""
            return
        }
        if (value === "back") {
            if (field.selectedText.length > 0)
                field.remove(field.selectionStart, field.selectionEnd)
            else if (field.cursorPosition > 0)
                field.remove(field.cursorPosition - 1, field.cursorPosition)
            return
        }
        /* One decimal point per figure, and never as the first character: ".5" parses,
           but it reads as a mistake on an invoice. */
        if (value === ".") {
            if (field.text.indexOf(".") >= 0 && field.selectedText.length === 0)
                return
            if (field.text === "" || field.selectedText === field.text) {
                field.text = "0."
                field.cursorPosition = field.text.length
                return
            }
        }
        if (field.selectedText.length > 0)
            field.remove(field.selectionStart, field.selectionEnd)
        field.insert(field.cursorPosition, value)
    }

    // -- what has been entered ---------------------------------------------
    function number(text) {
        var value = parseFloat(String(text).replace(",", "."))
        return isNaN(value) ? 0 : value
    }

    readonly property real enteredQty: number(qtyField.text)
    readonly property real enteredCost: number(costField.text)
    readonly property real enteredPrice: number(priceField.text)
    readonly property real margin: enteredPrice - enteredCost
    readonly property real lineTotal: enteredQty * enteredCost
    readonly property bool valid: enteredQty > 0

    function commit() {
        if (!valid)
            return
        sheet.accepted(enteredQty, enteredCost, enteredPrice)
        sheet.close()
    }

    // =====================================================================
    // PIECES
    // =====================================================================
    /*
     * A labelled figure that reports its own focus and shows when the pad is aimed at
     * it. `name` is the pad's mode, which is what ties the two together without either
     * knowing about the other.
     *
     * The frame is drawn here rather than left to the style: FluentWinUI3's focused
     * TextField underlines its bottom edge in the accent colour, which is a fine
     * signal for a form and too quiet for one of three boxes a keypad is pointing at.
     */
    component Figure: ColumnLayout {
        id: figure
        required property string name
        required property string label
        property alias field: box
        property int size: Tokens.font.bodyLarge

        readonly property bool live: sheet.mode === figure.name

        Layout.fillWidth: true
        spacing: 2

        Text {
            Layout.fillWidth: true
            text: figure.label
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.overline
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.1
            color: figure.live ? Tokens.brand : Fluent.textTertiary
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: box.implicitHeight
            radius: Tokens.radius.md
            color: figure.live ? Tokens.brandTint : Fluent.subtleSecondary
            border.width: figure.live ? 2 : 1
            border.color: figure.live ? Tokens.brand : Fluent.dividerBorder

            Behavior on border.color {
                ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
            }

            QC.TextField {
                id: box
                /* Named so a test harness can reach it: PySide cannot convert an
                   aliased QML TextField across the boundary, and a UI whose focus
                   rules are its whole point has to be provable from outside. */
                objectName: "figure_" + figure.name
                anchors.fill: parent
                anchors.leftMargin: Tokens.spacing.sm
                anchors.rightMargin: Tokens.spacing.sm
                /* The style's own frame would be a second border inside this one. */
                background: null
                horizontalAlignment: TextInput.AlignRight
                verticalAlignment: TextInput.AlignVCenter
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                font.family: Tokens.font.family
                font.pixelSize: figure.size
                font.weight: Font.DemiBold

                /* The other direction: a field tapped or tabbed into lights its own
                   mode on the pad and selects itself. One handler, so a keyboard user
                   and a touch user get the same behaviour. */
                onActiveFocusChanged: {
                    if (activeFocus && sheet.mode !== figure.name)
                        sheet.focusField(figure.name)
                    else if (activeFocus)
                        selectAll()
                }

                /* Return moves on rather than committing: quantity to cost to price is
                   the order they are decided in, and the last one commits. */
                onAccepted: {
                    if (figure.name === "qty")
                        sheet.focusField("cost")
                    else if (figure.name === "cost")
                        sheet.focusField("price")
                    else
                        sheet.commit()
                }
            }
        }
    }

    // =====================================================================
    // LAYOUT
    // =====================================================================
    contentItem: ColumnLayout {
        spacing: 0

        // -----------------------------------------------------------------
        // WHICH PRODUCT
        // -----------------------------------------------------------------
        /* A tinted header rather than a line of text: it is the one thing on this
           sheet that is not editable, and separating it stops the eye from reading the
           name as another field. */
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: head.implicitHeight + 2 * Tokens.spacing.md
            color: Fluent.subtleSecondary
            /* Only the top corners: this sits inside a rounded frame. */
            radius: Tokens.radius.lg

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: Tokens.radius.lg
                color: parent.color
            }

            ColumnLayout {
                id: head
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.spacing.lg
                anchors.rightMargin: Tokens.spacing.lg
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    text: sheet.product ? sheet.product.name : ""
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.subtitle
                    font.weight: Font.DemiBold
                    color: Fluent.textPrimary
                }

                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    /* Barcode, what is on the shelf, and what it cost last time —
                       the three facts that decide whether the seeded figures are
                       right, on one line under the name. */
                    text: {
                        var parts = []
                        if (sheet.product && sheet.product.barcode)
                            parts.push("\u200e" + sheet.product.barcode)
                        if (sheet.stockText !== "")
                            parts.push(sheet.stockText)
                        if (sheet.lastText !== "")
                            parts.push(sheet.lastText)
                        return parts.join("  ·  ")
                    }
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.caption
                    color: Fluent.textTertiary
                }
            }
        }

        // -----------------------------------------------------------------
        // THE THREE FIGURES
        // -----------------------------------------------------------------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.margins: Tokens.spacing.lg
            spacing: Tokens.spacing.md

            /* The quantity is the hero and takes the full width at title size: it is
               the figure every line needs and the one most often wrong. */
            Figure {
                id: qtyRow
                name: "qty"
                label: Strings.t("pos.numpad.qty", "Quantity")
                size: Tokens.font.title
            }

            /* Cost and price side by side, because the decision is the difference
               between them and two boxes on one line is where an eye compares. */
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.md

                Figure {
                    id: costRow
                    name: "cost"
                    label: Strings.t("product.purchase_price", "Cost")
                }

                Figure {
                    id: priceRow
                    name: "price"
                    label: Strings.t("product.sale_price", "Selling price")
                }
            }

            /* The two consequences, under the two boxes that produce them: the margin
               under the prices, and what this line adds to the invoice. */
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.md

                Text {
                    Layout.fillWidth: true
                    text: Strings.t("product.profit_unit", "Margin") + "  "
                          + (sheet.enteredPrice > 0
                             ? "\u200e" + sheet.money(sheet.margin) + "  ("
                               + (sheet.margin / sheet.enteredPrice * 100).toFixed(1)
                               + "%)"
                             : "—")
                    elide: Text.ElideRight
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.caption
                    font.weight: Font.DemiBold
                    color: sheet.enteredPrice <= 0 ? Fluent.textTertiary
                         : sheet.margin < 0 ? Tokens.danger : Tokens.success
                }

                Text {
                    text: Strings.t("purchases.line_total", "Line total") + "  \u200e"
                          + sheet.money(sheet.lineTotal)
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.caption
                    font.weight: Font.DemiBold
                    color: Fluent.textSecondary
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Fluent.dividerBorder
            }

            // -------------------------------------------------------------
            // THE PAD
            // -------------------------------------------------------------
            Numpad {
                Layout.alignment: Qt.AlignHCenter
                modes: ["qty", "cost", "price"]
                activeMode: sheet.mode
                /* Both directions land in focusField: tapping a mode moves the caret
                   and selects the text, exactly as tapping the field itself does. */
                onModeRequested: (value) => sheet.focusField(value)
                onKeyPressed: (value) => sheet.key(value)
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.sm

                Item { Layout.fillWidth: true }

                GlyphButton {
                    glyph: "ic_fluent_dismiss_20_regular"
                    outlined: true
                    text: Strings.t("action.cancel", "Cancel")
                    onClicked: sheet.close()
                }

                GlyphButton {
                    glyph: sheet.editing ? "ic_fluent_checkmark_20_regular"
                                         : "ic_fluent_add_20_regular"
                    text: sheet.editing ? Strings.t("action.save", "Save")
                                        : Strings.t("purchases.add_line", "Add a line")
                    highlighted: true
                    enabled: sheet.valid
                    onClicked: sheet.commit()
                }
            }
        }
    }

    /* The three figures' fields, reachable by the functions above. Declared as
       aliases rather than looked up, so a rename is a compile error instead of a
       silent no-op. */
    readonly property alias qtyField: qtyRow.field
    readonly property alias costField: costRow.field
    readonly property alias priceField: priceRow.field
}

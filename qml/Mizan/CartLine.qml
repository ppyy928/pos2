import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * One line in the till's cart. Ported from
 * pos/app/widgets/cart_list.py::CartLineItem.
 *
 *     ┌────────────────────────────────────────────────────────┐
 *     │ Coca-Cola 1.5L                                         │
 *     │ 120,00   [ −  2  + ]           240,00            🗑     │
 *     └────────────────────────────────────────────────────────┘
 *
 * WHY THE STEPPER SITS ON THE ROW
 *
 * pos changes a quantity by selecting the line and retyping it on the numpad, or
 * by opening a small editor over the row. A −/+ pair on the line itself is the
 * biggest touch win available on this screen, and it is what sets
 * Tokens.size.cartRow: a 48px control cannot live in a 56px table row, so the
 * cart is a list of cards rather than a table.
 *
 * WHY THIS ROW MIRRORS AND pos's DOES NOT
 *
 * cart_list.py pins the row to LeftToRight so its four pieces never move. Here
 * the row is a Layout and mirrors with the language, because every other surface
 * in this app does — a cart that reads left-to-right inside an Arabic screen is
 * the one row that looks broken. Nothing is lost by mirroring: the amounts
 * arrive already formatted from Python, which owns the digit shapes for the
 * active language.
 *
 * THE ARITHMETIC IS NOT HERE
 *
 * The stepper reports the quantity it *wants*; it never sets one. The cart is
 * owned by the controller, the totals are computed and formatted there, and a
 * row that changed its own number before the total under it agreed would be
 * worse than a tap that is refused. Same one-way rule as NavRail and Numpad.
 */
Rectangle {
    id: line

    // =====================================================================
    // API
    // =====================================================================
    property string name: ""

    /* Unit price and line total, both formatted by pos's fmt_money. The row
       shows no currency symbol — pos drops it here too, so a column of six
       amounts stays quiet and the currency appears once, on the dock. */
    property string priceText: ""
    property string totalText: ""

    /* The quantity as text, because that is what is displayed, and as a number,
       because the stepper has to add to it. Both come from the controller: one
       is fmt_qty's output, the other the raw value behind it. */
    property string qtyText: ""
    property real qty: 0

    /* The step is the product's own unit quantity — a 6-pack steps by 6 if the
       catalogue says so. pos passes the same value into the card. */
    property real step: 1

    property bool selected: false

    signal clicked()
    signal qtyRequested(real value)
    signal removeRequested()

    /* Show a pen and emit `editRequested`. See the button near the bottom of this
       file for why it is opt-in. */
    property bool editable: false
    signal editRequested()

    // =====================================================================
    // SURFACE
    // =====================================================================
    implicitHeight: Tokens.size.cartRow
    radius: Tokens.radius.md

    /* Selected is a fill, not a border: a 1px outline appearing and disappearing
       shifts nothing but is easy to miss across a counter, and the brand tint is
       legible at arm's length. Hover is the ordinary subtle fill so a mouse user
       still gets the row they are about to hit. */
    color: selected ? Tokens.brandTint
         : hover.hovered ? Fluent.subtleSecondary
                         : "transparent"
    Behavior on color { ColorAnimation { duration: Fluent.anim.appearance } }

    /* Leading marker for the selected line. The numpad's QTY mode acts on this
       row and nothing else, so which row it is has to be unmistakable. Inset by
       the radius for the same reason PosTile's stripe is: a rounded Rectangle
       clips to its bounding box, not to its arcs. */
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: Tokens.radius.md
        anchors.bottomMargin: Tokens.radius.md
        width: 3
        radius: 2
        visible: line.selected
        color: Tokens.brand
    }

    HoverHandler { id: hover }

    /* Tapping the row selects it. The buttons inside accept their own presses,
       so the stepper and the bin do not also move the selection — which is what
       pos gets from putting this on mousePressEvent. */
    TapHandler {
        onTapped: line.clicked()
    }

    // =====================================================================
    // CONTENT
    // =====================================================================
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Tokens.spacing.sm
        anchors.rightMargin: Tokens.spacing.xs
        anchors.topMargin: Tokens.spacing.xs
        anchors.bottomMargin: Tokens.spacing.xs
        spacing: Tokens.spacing.sm

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                Layout.fillWidth: true
                text: line.name
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                font.weight: Font.DemiBold
                color: Fluent.textPrimary
                elide: Text.ElideRight
                /* One line, elided. pos word-wraps the name across the card and
                   never truncates it, which is the right call in a 470px column
                   with nothing under it — here the row also carries a stepper,
                   and a two-line name pushes it out of the card. The untruncated
                   name is in the tooltip. */
                maximumLineCount: 1
                horizontalAlignment: Text.AlignLeft
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.sm

                Text {
                    text: line.priceText
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.caption
                    color: Fluent.textSecondary
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignLeft
                }

                Item { Layout.fillWidth: true }

                // -------------------------------------------------------------
                // stepper
                // -------------------------------------------------------------
                /* − field + reads in that order in both directions: a Row
                   positions by x and reverses under the LayoutMirroring the
                   window installs, so "less" stays on the leading edge in
                   Arabic without being told. */
                Row {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2

                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: "ic_fluent_subtract_20_regular"
                        glyphSize: Tokens.icon.sm
                        /* Refusing the tap that would take the line to zero,
                           rather than sending a value the page has to reject.
                           Removing a line is the bin's job, and it is one tap
                           away. */
                        enabled: line.qty - line.step > 0
                        tooltip: Strings.t("cart.qty.decrease", "Less")
                        onClicked: line.qtyRequested(line.qty - line.step)
                    }

                    /* Editable, because a cashier with a keyboard changes "1" to
                       "12" faster than they tap + eleven times. The numpad's QTY
                       mode is the touch path to the same value.

                       No binding on `text`: a TextField assigns its own text as
                       the operator types, which would destroy one — so the value
                       is pushed in from onQtyTextChanged below, which is the only
                       other place it can change. Same reason ProductsPage sets
                       ComboBox.currentIndex by hand. */
                    QC.TextField {
                        id: qtyField
                        anchors.verticalCenter: parent.verticalCenter
                        width: 72
                        height: Tokens.size.control
                        horizontalAlignment: TextInput.AlignHCenter
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.body
                        font.weight: Font.DemiBold
                        inputMethodHints: Qt.ImhFormattedNumbersOnly
                        selectByMouse: true

                        Component.onCompleted: text = line.qtyText

                        onAccepted: line.commitTyped(text)
                        /* Also on focus loss: a cashier who types 3 and then taps
                           a product instead of pressing Enter meant 3. */
                        onEditingFinished: line.commitTyped(text)
                    }

                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: "ic_fluent_add_20_regular"
                        glyphSize: Tokens.icon.sm
                        tooltip: Strings.t("cart.qty.increase", "More")
                        onClicked: line.qtyRequested(line.qty + line.step)
                    }
                }
            }
        }

        /* The dominant figure in the row, at the same size as a KPI value —
           this is the number a customer leans over the counter to read. */
        Text {
            Layout.alignment: Qt.AlignVCenter
            Layout.minimumWidth: 110
            text: line.totalText
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.amount
            font.weight: Font.DemiBold
            color: Fluent.textPrimary
            elide: Text.ElideRight
            /* Trailing edge, logically: mirrors to the left in Arabic, where the
               row's trailing edge is. */
            horizontalAlignment: Text.AlignRight
        }

        /*
         * Open this line's full editor.
         *
         * Off by default, because the till does not need it: a sale line has a
         * quantity and nothing else the cashier may change, and the stepper beside it
         * is that. A delivery line has three values — how many, what it cost, what it
         * will sell for — and three values do not fit on a row, so the delivery screen
         * turns this on and reopens the entry dialog with the line in it.
         */
        IconButton {
            Layout.alignment: Qt.AlignVCenter
            visible: line.editable
            glyph: "ic_fluent_edit_20_regular"
            glyphSize: Tokens.icon.sm
            tooltip: Strings.t("action.edit", "Edit")
            onClicked: line.editRequested()
        }

        IconButton {
            Layout.alignment: Qt.AlignVCenter
            glyph: "ic_fluent_delete_20_regular"
            glyphSize: Tokens.icon.sm
            glyphColor: Tokens.danger
            tooltip: Strings.t("action.delete", "Delete")
            onClicked: line.removeRequested()
        }
    }

    // =====================================================================
    // BEHAVIOUR
    // =====================================================================
    /* Push a new quantity into the field. The delegate is recycled as the list
       scrolls and rebuilt when the cart changes, so this is also what keeps a
       field the operator typed into in step with the cart behind it. */
    onQtyTextChanged: qtyField.text = qtyText

    QC.ToolTip.text: line.name
    QC.ToolTip.visible: hover.hovered && line.name !== ""
    QC.ToolTip.delay: 700

    /* Parse what was typed and ask for it, or put the stored value back.
       "1,5" is what a French or Arabic keyboard produces for one and a half, and
       parseFloat stops at the comma — so the separator is normalised here. The
       digit *shapes* are Python's job: normalize_digits already handles
       Arabic-Indic input on the way in, and this field is the keyboard shortcut
       to a value the numpad can also set. */
    function commitTyped(text) {
        var value = parseFloat(String(text).replace(",", "."))
        if (isNaN(value) || value <= 0) {
            qtyField.text = line.qtyText
            return
        }
        if (value !== line.qty)
            line.qtyRequested(value)
    }
}

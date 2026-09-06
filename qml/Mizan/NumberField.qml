import QtQuick
import QtQuick.Controls as QC
import Mizan

/*
 * A field that holds a NUMBER — a price, a cost, a quantity, a threshold, a rate.
 *
 *     NumberField {
 *         id: sale
 *         Layout.fillWidth: true
 *         onAccepted: dialog.save()
 *     }
 *
 * SELECTING THE WHOLE VALUE ON FOCUS IS THE POINT
 *
 * On a till, a number in a field is nearly always a number to REPLACE. The cost
 * says 536.76 and the new delivery came in at 540; the quantity says 1 and the
 * customer wants 12. With a caret, that is: tap, then select the old value by
 * dragging across it — on a touchscreen, over four characters, next to a decimal
 * point — or tap and press Backspace six times. Twenty-two fields in this app
 * behaved that way, and two did not: the delivery line's keypad and the payment
 * sheet both selected the value as they opened, which is why those two are the
 * ones nobody complained about. This makes the other twenty behave like them.
 *
 * WHY Qt.callLater AND NOT selectAll() DIRECTLY
 *
 * A mouse press does two things in order: it moves focus, then it positions the
 * caret. `onActiveFocusChanged: selectAll()` runs between those two, so the
 * press that arrives a moment later collapses the selection it just made — the
 * plain version works for Tab and for forceActiveFocus() and silently does
 * nothing for a click, which is the gesture an operator actually uses. Deferring
 * to the end of the event puts the selection after the caret placement.
 *
 * `pending` guards the deferred call: focus can be lost again before it runs (a
 * click that lands on a field and immediately opens a dialog), and selecting text
 * in a field nobody is looking at leaves it highlighted for the next visit.
 *
 * WHY selectByMouse IS ON
 *
 * Select-all is what a tap gives; a drag has to still be able to take part of the
 * value, or correcting one digit of a barcode-length number becomes retyping it.
 *
 * WHAT THIS DELIBERATELY DOES NOT DO
 *
 * No validator. Qt's DoubleValidator refuses the intermediate states of typing —
 * "1." and "-" among them — and its notion of a decimal separator comes from the
 * C locale, so on a French or Arabic keyboard it rejects the comma the operator's
 * numpad produces. Every caller already parses with `interop.as_float` or QML's
 * own `number()`, both of which take a comma; `inputMethodHints` asks a
 * touch keyboard for digits, and that is the honest limit of what a hint can do.
 *
 * No layout, no height, no width: this is a field, not a row. `Layout.fillWidth`,
 * `Layout.preferredHeight` and alignment belong to the caller, which is the only
 * thing that knows whether it is one of three in a row or the whole of one.
 *
 * WHY LineEntry AND PaymentEntry STILL DO NOT USE IT
 *
 * Both drive an on-screen numpad that inserts INTO the current selection
 * (`if (field.selectedText.length > 0) field.remove(...)`), and both keep the
 * pad's mode column and the caret in step through one shared function. Their
 * fields are already selection-correct; replacing them with this would mean
 * re-testing that coupling for no behavioural gain.
 */
QC.TextField {
    id: field

    /* The value, as a number, with a decimal comma understood.
       Read-only and derived — a caller that wants the number does not want to
       write the same three-line parse a fourth time. NaN never escapes: an empty
       or half-typed field is 0. */
    readonly property real value: {
        var parsed = parseFloat(String(text).replace(",", "."))
        return isNaN(parsed) ? 0 : parsed
    }

    /* True when nothing has been typed. Distinct from `value === 0`, because "no
       threshold given" and "a threshold of zero" are different answers and some
       callers send a default for the first. */
    readonly property bool blank: String(text).trim() === ""

    /* Digits by default; a caller that wants a bare integer count sets
       `Qt.ImhDigitsOnly`. */
    inputMethodHints: Qt.ImhFormattedNumbersOnly

    /* Numbers line up on the right, which is what makes a column of them
       comparable. Overridable, because a quantity in a narrow centred cell reads
       better centred. Not mirrored under RTL on purpose: this is a figure, and a
       figure is left-to-right in every one of the three languages. */
    horizontalAlignment: TextInput.AlignRight

    selectByMouse: true

    font.family: Tokens.font.family
    font.pixelSize: Tokens.font.bodyLarge

    property bool pending: false

    onActiveFocusChanged: {
        if (activeFocus) {
            pending = true
            Qt.callLater(function () {
                if (field.pending && field.activeFocus)
                    field.selectAll()
                field.pending = false
            })
        } else {
            pending = false
            /* Drop the selection on the way out. A field left highlighted looks
               focused when it is not — two of them on screen at once is a form
               that cannot say where the keyboard is. */
            deselect()
        }
    }
}

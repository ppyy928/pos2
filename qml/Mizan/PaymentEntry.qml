import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * Take an amount, against something that is owed.
 *
 *   ┌── Partial payment ─────────────────────────────┐
 *   │  Customer owes            12 400.00            │
 *   │  This sale                 3 160.00            │
 *   ├────────────────────────────────────────────────┤
 *   │  RECEIVED                                      │
 *   │  ┌──────────────────────────────────────────┐  │
 *   │  │                                 1 000.00 │  │
 *   │  └──────────────────────────────────────────┘  │
 *   │  Left after this            2 160.00           │
 *   ├────────────────────────────────────────────────┤
 *   │  [7][8][9]  [ ALL ]                            │
 *   │  [4][5][6]                                     │
 *   │  [1][2][3]                                     │
 *   │  [0][.][⌫]                                     │
 *   │                    [ Cancel ]  [ Confirm ]     │
 *   └────────────────────────────────────────────────┘
 *
 * WHY A DIALOG AND NOT A FIELD ON THE SCREEN
 *
 * A partial payment is a moment, not a setting. Somebody is standing there handing
 * over less than the whole amount, and the question that has to be answered out loud
 * is "how much is still owed after this" — which a box tucked into a totals panel
 * cannot ask, because it has no room for the arithmetic and no weight to make anybody
 * read it. Taking the screen for the duration is what makes the figure impossible to
 * miss and the act deliberate.
 *
 * WHY IT IS ONE COMPONENT
 *
 * Every place this happens is the same shape with a different sentence and a different
 * place to store the answer: a sale part-paid at the till, a delivery part-paid to a
 * rep, a customer settling some of an account, a supplier being paid down. So the
 * caller supplies the facts to show, what the payment is measured against, and where
 * the answer goes — and this owns the keypad, the arithmetic and the wording of "left
 * after this".
 *
 * THE FACTS ARE THE CALLER'S
 *
 * `facts` is a list of `{ label, value, tone }` drawn above the field. The customer's
 * existing debt belongs there on a till sale and does not exist on a delivery; the
 * component has no business knowing which, so it draws what it is given.
 */
QC.Popup {
    id: sheet

    // =====================================================================
    // API
    // =====================================================================
    property string heading: ""
    property string glyph: "ic_fluent_money_hand_20_regular"

    /* Context, in the caller's words: [{ label, value, tone }]. `tone` is optional and
       takes the app's usual names — "danger" for money owed, "" for a plain figure. */
    property var facts: []

    /* What this payment is measured against: the sale's total, the invoice's total, the
       balance on an account. Drives "left after this" and the ALL key. */
    property real due: 0

    /* Nothing may be paid at all — a debt sale is a payment of zero — but a caller that
       needs a positive figure says so. */
    property bool allowZero: false

    property string confirmText: ""

    signal accepted(real amount)

    function money(value) {
        return (typeof app !== "undefined" && app && app.pos)
               ? app.pos.moneyText(value) : String(value)
    }

    // =====================================================================
    // FRAME
    // =====================================================================
    parent: QC.Overlay.overlay
    anchors.centerIn: QC.Overlay.overlay
    /* Measured against the overlay it is parented to: the attached `Window` property
       only works on Items, and a Popup is not one. */
    width: Math.min(520, (parent ? parent.width : 700) - 2 * Tokens.spacing.xxl)
    padding: 0
    modal: true
    focus: true

    background: Rectangle {
        color: Fluent.popupBackground
        radius: Tokens.radius.lg
        border.width: 1
        border.color: Fluent.dividerBorder
    }

    /* Opens empty, not pre-filled with the total. A partial payment is by definition
       not the whole amount, so seeding it with the whole amount would be seeding the
       one answer this dialog is not for — and ALL is one key away for the operator who
       changes their mind. */
    onOpened: {
        amount.text = ""
        amount.forceActiveFocus()
    }

    // =====================================================================
    // THE ARITHMETIC
    // =====================================================================
    function number(text) {
        var value = parseFloat(String(text).replace(",", "."))
        return isNaN(value) ? 0 : value
    }

    readonly property real entered: number(amount.text)
    readonly property real remaining: Math.max(0, due - entered)
    readonly property bool over: entered > due + 0.005
    readonly property bool valid: (allowZero || entered > 0) && !over

    function key(value) {
        if (value === "clear") {
            amount.text = ""
            return
        }
        if (value === "back") {
            if (amount.selectedText.length > 0)
                amount.remove(amount.selectionStart, amount.selectionEnd)
            else if (amount.cursorPosition > 0)
                amount.remove(amount.cursorPosition - 1, amount.cursorPosition)
            return
        }
        if (value === ".") {
            if (amount.text.indexOf(".") >= 0 && amount.selectedText.length === 0)
                return
            if (amount.text === "" || amount.selectedText === amount.text) {
                amount.text = "0."
                amount.cursorPosition = amount.text.length
                return
            }
        }
        if (amount.selectedText.length > 0)
            amount.remove(amount.selectionStart, amount.selectionEnd)
        amount.insert(amount.cursorPosition, value)
    }

    function commit() {
        if (!valid)
            return
        sheet.accepted(entered)
        sheet.close()
    }

    // =====================================================================
    // LAYOUT
    // =====================================================================
    contentItem: ColumnLayout {
        spacing: 0

        // -----------------------------------------------------------------
        // WHAT IS OWED, AND FOR WHAT
        // -----------------------------------------------------------------
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: head.implicitHeight + 2 * Tokens.spacing.md
            color: Fluent.subtleSecondary
            radius: Tokens.radius.lg

            /* Square off the bottom two corners: this sits at the top of a rounded
               frame and a rounded bottom edge would cut the divider under it. */
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
                spacing: Tokens.spacing.xs

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.sm

                    Icon {
                        icon: sheet.glyph
                        size: Tokens.icon.md
                        color: Tokens.warning
                    }

                    Text {
                        Layout.fillWidth: true
                        text: sheet.heading
                        elide: Text.ElideRight
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.subtitle
                        font.weight: Font.DemiBold
                        color: Fluent.textPrimary
                    }
                }

                /* The caller's facts, one line each. Caption quiet, figure loud — the
                   same two-Text arrangement the totals dock uses, for the same reason:
                   a translator cannot break a layout that has no placeholder in it. */
                Repeater {
                    model: sheet.facts

                    delegate: RowLayout {
                        required property var modelData

                        Layout.fillWidth: true
                        spacing: Tokens.spacing.sm

                        Text {
                            Layout.fillWidth: true
                            text: modelData.label
                            elide: Text.ElideRight
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.body
                            color: Fluent.textSecondary
                        }

                        Text {
                            text: "\u200e" + modelData.value
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.bodyLarge
                            font.weight: Font.DemiBold
                            color: modelData.tone !== undefined && modelData.tone !== ""
                                   ? Tokens.toneInk(modelData.tone)
                                   : Fluent.textPrimary
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.margins: Tokens.spacing.lg
            spacing: Tokens.spacing.md

            // -------------------------------------------------------------
            // WHAT IS BEING HANDED OVER
            // -------------------------------------------------------------
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: Strings.t("pay.received", "Received")
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.overline
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.1
                    color: sheet.over ? Tokens.danger : Tokens.brand
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: amount.implicitHeight
                    radius: Tokens.radius.md
                    color: sheet.over ? Tokens.dangerTint : Tokens.brandTint
                    border.width: 2
                    border.color: sheet.over ? Tokens.danger : Tokens.brand

                    Behavior on border.color {
                        ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
                    }

                    QC.TextField {
                        id: amount
                        objectName: "paymentAmount"
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.spacing.sm
                        anchors.rightMargin: Tokens.spacing.sm
                        /* The style's own frame would be a second border inside this
                           one. */
                        background: null
                        placeholderText: "0"
                        horizontalAlignment: TextInput.AlignRight
                        verticalAlignment: TextInput.AlignVCenter
                        inputMethodHints: Qt.ImhFormattedNumbersOnly
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.title
                        font.weight: Font.DemiBold
                        onAccepted: sheet.commit()
                        onActiveFocusChanged: if (activeFocus) selectAll()
                    }
                }
            }

            /*
             * The answer to the question the operator is being asked out loud.
             *
             * This is the whole reason the payment moved out of a totals panel and into
             * a dialog: "so how much do I still owe?" needs a figure at a size that is
             * read across a counter, and it has to change as the number is typed.
             */
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.sm

                Text {
                    Layout.fillWidth: true
                    text: sheet.over
                          ? Strings.t("pay.over", "That is more than is owed.")
                          : Strings.t("amount.remaining_after", "Left after this")
                    wrapMode: Text.WordWrap
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                    color: sheet.over ? Tokens.danger : Fluent.textSecondary
                }

                Text {
                    visible: !sheet.over
                    text: "\u200e" + sheet.money(sheet.remaining)
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.amount
                    font.weight: Font.DemiBold
                    color: sheet.remaining > 0.005 ? Tokens.danger : Tokens.success
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
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Tokens.spacing.sm

                /* No mode column: there is one field, so a mode would be a control with
                   one setting. `modes: []` is what Numpad's mode list is for. */
                Numpad {
                    modes: []
                    onKeyPressed: (value) => sheet.key(value)
                }

                /* Settling in full is one key away for the operator who changes their
                   mind at the counter — which happens, and retyping six figures is
                   where mistakes come from. */
                PayButton {
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: 120
                    compact: true
                    text: Strings.t("amount.all", "All")
                    glyph: "ic_fluent_checkmark_circle_20_regular"
                    hue: Tokens.chromeHue.indigo
                    onClicked: {
                        amount.text = String(sheet.due)
                        amount.forceActiveFocus()
                    }
                }
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
                    glyph: "ic_fluent_checkmark_20_regular"
                    text: sheet.confirmText !== ""
                          ? sheet.confirmText
                          : Strings.t("action.confirm", "Confirm")
                    highlighted: true
                    enabled: sheet.valid
                    onClicked: sheet.commit()
                }
            }
        }
    }
}

import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * Taking goods back. Ported from pos's `return_create` workflow over
 * db.create_return(sale_id, items, reason).
 *
 *   ┌──────────────────────────────────────────────────────────┐
 *   │ Return items — TRX-0174                                  │
 *   │ Coca-Cola 1.5L    sold 2   [ − 1 + ]  of 2               │
 *   │ Pain complet    sold 1,5   [ − 0 + ]  of 1,5 (0,5 back)  │
 *   │ Reason [                                             ▾]  │
 *   │ Refund (estimate)                          120,00        │
 *   │                              [Cancel] [Confirm return]   │
 *   └──────────────────────────────────────────────────────────┘
 *
 * THE CEILING IS PER LINE, AND IT IS NOT A SUGGESTION
 *
 * A line can only give back what is left of it: sold minus already returned. The
 * steppers stop there, and `create_return` applies the same rule again when it
 * writes — the screen is the convenience, the database is the guarantee.
 *
 * THE REASON IS CHOSEN, NOT TYPED
 *
 * `app.sales.returnReasons` is a fixed list — the shop's twelve reasons, in the
 * operator's language — and its first entry is empty, which is what the dialog
 * opens on. Typing it was the earlier version and it produced five spellings of
 * "damaged" across three languages, which made the reason column on the returns
 * page and in the returns report worth nothing. Empty stays available and stays
 * first: a return with no stated reason is a normal return, and a required reason
 * only teaches the operator to pick whichever sentence is at the top.
 *
 * THE REFUND IS AN ESTIMATE ON THIS SIDE
 *
 * It is shown so the operator knows roughly what is going back across the counter,
 * and it is computed from the sale's stored unit prices. The figure that is
 * recorded is priced by the database from those same stored items, never from
 * anything sent from here — which is why this is labelled an estimate and why
 * nothing depends on it being right.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.sales : null
    readonly property int saleId: context && context.sale_id ? context.sale_id : 0
    readonly property int measure: 720

    preferredWidth: 1000
    title: Strings.t("return.create_title", "Return items")

    property var row: ({})
    /* Quantity chosen per line, by index. A plain array so the whole thing can be
       rebuilt in one assignment when the sale loads. */
    property var picked: []

    Component.onCompleted: {
        if (ctrl && saleId)
            row = ctrl.sale(saleId) || ({})
        var items = row.items !== undefined ? row.items : []
        var zeros = []
        for (var i = 0; i < items.length; i++)
            zeros.push(0)
        picked = zeros
    }

    readonly property var items: row.items !== undefined ? row.items : []

    readonly property real refund: {
        var sum = 0
        for (var i = 0; i < items.length && i < picked.length; i++)
            sum += picked[i] * items[i].price
        return sum
    }

    readonly property bool anything: {
        for (var i = 0; i < picked.length; i++)
            if (picked[i] > 0)
                return true
        return false
    }

    function set(index, value) {
        var items_ = items
        if (index < 0 || index >= items_.length)
            return
        var capped = Math.max(0, Math.min(items_[index].returnable, value))
        /* Replaced wholesale rather than mutated in place: a `var` property does
           not notify on element assignment, and every figure on this dialog is
           bound to it. */
        var next = picked.slice()
        next[index] = capped
        picked = next
    }

    function confirm() {
        error.text = ""
        if (!ctrl || !anything)
            return
        var lines = []
        for (var i = 0; i < items.length && i < picked.length; i++)
            if (picked[i] > 0)
                lines.push({ product_id: items[i].product_id, qty: picked[i] })
        ctrl.createReturn(saleId, lines, reason.currentText)
    }

    Connections {
        target: dialog.ctrl
        ignoreUnknownSignals: true

        function onReturned(result) {
            dialog.close()
        }

        function onRejected(message) {
            error.text = message
        }
    }

    contentItem: ColumnLayout {
        spacing: Tokens.spacing.md

        Text {
            Layout.preferredWidth: dialog.measure
            Layout.fillWidth: true
            text: dialog.row.number !== undefined
                  ? "\u200e" + dialog.row.number : ""
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.bodyLarge
            font.weight: Font.DemiBold
            color: Fluent.textPrimary
        }

        Repeater {
            model: dialog.items

            delegate: RowLayout {
                id: line
                required property var modelData
                required property int index

                readonly property real chosen: index < dialog.picked.length
                                               ? dialog.picked[index] : 0
                readonly property bool spent: modelData.returnable <= 0

                Layout.fillWidth: true
                spacing: Tokens.spacing.md

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        Layout.fillWidth: true
                        text: line.modelData.name
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.body
                        font.weight: Font.DemiBold
                        color: line.spent ? Fluent.textTertiary : Fluent.textPrimary
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: {
                            var sold = Strings.tf("return.sold", "sold {qty}",
                                                  { qty: line.modelData.qty_text })
                            if (line.modelData.returned > 0)
                                return sold + " · " + Strings.tf(
                                    "return.returned_qty", "{qty} returned",
                                    { qty: line.modelData.returned })
                            return sold
                        }
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.caption
                        color: Fluent.textSecondary
                    }
                }

                /* − qty + , capped at what is left. Nothing to take back leaves
                   the row visible and inert: the line was part of this sale, and
                   hiding it would make the receipt and this dialog disagree. */
                Row {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2

                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: "ic_fluent_subtract_20_regular"
                        glyphSize: Tokens.icon.sm
                        enabled: line.chosen > 0
                        onClicked: dialog.set(line.index, line.chosen - 1)
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 64
                        horizontalAlignment: Text.AlignHCenter
                        text: "\u200e" + line.chosen
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.body
                        font.weight: Font.DemiBold
                        color: Fluent.textPrimary
                    }

                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: "ic_fluent_add_20_regular"
                        glyphSize: Tokens.icon.sm
                        enabled: line.chosen < line.modelData.returnable
                        onClicked: dialog.set(line.index, line.chosen + 1)
                    }
                }

                Text {
                    Layout.preferredWidth: 120
                    text: "\u200e" + Strings.tf("return.of", "of {qty}",
                                                { qty: line.modelData.returnable })
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.caption
                    color: Fluent.textTertiary
                    horizontalAlignment: Text.AlignRight
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Fluent.dividerBorder
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                text: Strings.t("stock.reason", "Reason")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.caption
                font.weight: Font.DemiBold
                color: Fluent.textSecondary
            }

            /* The fixed list, empty entry first. `currentIndex` is left at 0 and
               never assigned from a binding: a ComboBox writes its own index the
               moment it is used, which would destroy one — the trap SettingsPage
               and PaginationBar both document. There is nothing to restore here
               anyway, since a new return starts with no reason. */
            QC.ComboBox {
                id: reason
                Layout.fillWidth: true
                Layout.preferredHeight: Tokens.size.control
                model: dialog.ctrl ? dialog.ctrl.returnReasons : [""]
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.md

            Text {
                text: Strings.t("return.refund", "Refund (estimate)")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                color: Fluent.textSecondary
            }

            Item { Layout.fillWidth: true }

            Text {
                text: "\u200e" + (dialog.ctrl ? dialog.ctrl.moneyText(dialog.refund) : "—")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.amount
                font.weight: Font.DemiBold
                color: dialog.anything ? Tokens.warning : Fluent.textTertiary
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
                glyph: "ic_fluent_arrow_undo_20_regular"
                text: Strings.t("return.confirm", "Confirm return")
                highlighted: true
                enabled: dialog.anything
                onClicked: dialog.confirm()
            }
        }
    }
}

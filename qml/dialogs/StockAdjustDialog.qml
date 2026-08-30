import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * Moving a stock figure, on purpose and on the record. Ported from pos's
 * `stock_adjust` workflow over db.adjust_stock(product_id, mode, qty, reason).
 *
 *   ┌──────────────────────────────────────────┐
 *   │ Adjust stock — Coca-Cola 1.5L            │
 *   │ In stock                            24   │
 *   │ [ Add ][ Reduce ][ Set ]                 │
 *   │ Quantity  [ 6            ]               │
 *   │ Reason    [ Delivery 27/08 ]             │
 *   │ Resulting stock                     30   │
 *   │                     [Cancel][Adjust]     │
 *   └──────────────────────────────────────────┘
 *
 * THE RESULT IS SHOWN BEFORE IT HAPPENS
 *
 * Three modes over one number is the classic place to make an expensive mistake —
 * "set 6" and "reduce 6" differ by 24 units of stock. The resulting figure is
 * computed live from the same rules the database applies (reduce and set both
 * clamp at zero), so the operator confirms an outcome rather than an instruction.
 *
 * WHY A REASON
 *
 * adjust_stock writes it to the log. A count that disagrees with the shelf next
 * month is answerable only if each change says why it happened, and the cashier
 * doing it is the only person who knows.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.products : null
    readonly property int productId: context && context.product_id ? context.product_id : 0
    readonly property int measure: 560

    preferredWidth: 720
    title: Strings.t("stock.adjust_title", "Adjust stock")

    property var row: ({})
    property string mode: "add"

    Component.onCompleted: {
        if (ctrl && productId)
            row = ctrl.product(productId) || ({})
        qty.forceActiveFocus()
    }

    readonly property real current: row.stock !== undefined ? row.stock : 0
    readonly property real amount: {
        var value = parseFloat(String(qty.text).replace(",", "."))
        return isNaN(value) ? 0 : value
    }

    /* db.adjust_stock's own arithmetic, including both clamps. */
    readonly property real resulting: {
        if (mode === "add")
            return current + amount
        if (mode === "reduce")
            return Math.max(0, current - amount)
        return Math.max(0, amount)
    }

    function apply() {
        error.text = ""
        if (amount <= 0) {
            error.text = Strings.t("amount.error", "Enter a valid amount.")
            qty.forceActiveFocus()
            return
        }
        if (ctrl)
            ctrl.adjustStock(productId, mode, amount, reason.text)
    }

    Connections {
        target: dialog.ctrl
        ignoreUnknownSignals: true

        function onAdjusted(result) {
            dialog.close()
        }

        function onRejected(message) {
            error.text = message
        }
    }

    component Line: RowLayout {
        id: line
        property string caption: ""
        property string value: ""
        property color ink: Fluent.textPrimary

        Layout.fillWidth: true
        spacing: Tokens.spacing.md

        Text {
            text: line.caption
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.body
            color: Fluent.textSecondary
        }

        Item { Layout.fillWidth: true }

        Text {
            text: "\u200e" + line.value
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.bodyLarge
            font.weight: Font.DemiBold
            color: line.ink
        }
    }

    contentItem: ColumnLayout {
        spacing: Tokens.spacing.md

        Text {
            Layout.preferredWidth: dialog.measure
            Layout.fillWidth: true
            visible: dialog.row.name !== undefined
            text: dialog.row.name !== undefined ? dialog.row.name : ""
            wrapMode: Text.WordWrap
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.bodyLarge
            font.weight: Font.DemiBold
            color: Fluent.textPrimary
        }

        Line {
            caption: Strings.t("stock.current", "In stock")
            value: dialog.row.text !== undefined ? dialog.row.text.stock : "—"
        }

        Text {
            text: Strings.t("stock.mode", "Mode")
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.caption
            font.weight: Font.DemiBold
            color: Fluent.textSecondary
        }

        /* Three buttons rather than a dropdown: the choice changes the meaning of
           the number below it, so it has to be visible without being opened. */
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.xs

            Repeater {
                model: [
                    { key: "add", label: Strings.t("stock.mode.add", "Add"),
                      glyph: "ic_fluent_add_20_regular" },
                    { key: "reduce", label: Strings.t("stock.mode.reduce", "Reduce"),
                      glyph: "ic_fluent_subtract_20_regular" },
                    { key: "set", label: Strings.t("stock.mode.set", "Set"),
                      glyph: "ic_fluent_checkmark_20_regular" }
                ]

                delegate: GlyphButton {
                    required property var modelData

                    Layout.fillWidth: true
                    Layout.preferredHeight: Tokens.size.control
                    glyph: modelData.glyph
                    text: modelData.label
                    highlighted: dialog.mode === modelData.key
                    onClicked: dialog.mode = modelData.key
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.md

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: Strings.t("stock.qty", "Quantity")
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.caption
                    font.weight: Font.DemiBold
                    color: Fluent.textSecondary
                }

                QC.TextField {
                    id: qty
                    Layout.fillWidth: true
                    Layout.preferredHeight: Tokens.size.control
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                    onAccepted: dialog.apply()
                }
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

                QC.TextField {
                    id: reason
                    Layout.fillWidth: true
                    Layout.preferredHeight: Tokens.size.control
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                    onAccepted: dialog.apply()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: preview.implicitHeight + 2 * Tokens.spacing.sm
            radius: Tokens.radius.md
            color: Tokens.brandTint

            Line {
                id: preview
                anchors.fill: parent
                anchors.leftMargin: Tokens.spacing.md
                anchors.rightMargin: Tokens.spacing.md
                caption: Strings.t("stock.resulting", "Resulting stock")
                value: dialog.resulting.toString()
                ink: Tokens.brand
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
                glyph: "ic_fluent_checkmark_20_regular"
                text: Strings.t("stock.adjust", "Adjust")
                highlighted: true
                onClicked: dialog.apply()
            }
        }
    }
}

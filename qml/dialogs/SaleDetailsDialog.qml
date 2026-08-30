import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * One sale, after the fact. Ported from pos's `sale_transaction` workflow.
 *
 *   ┌────────────────────────────────────────────────────────┐
 *   │ TRX-0174                                    [Partial]  │
 *   │ 27/08/2026 14:05 · Amine Bekkar                        │
 *   │ Coca-Cola 1.5L      2 × 120,00              240,00     │
 *   │ Pain complet      1,5 × 35,00                52,50     │
 *   │ ──────────────────────────────────────────────────────  │
 *   │ Total 12 480,00 · Paid 10 000,00 · Outstanding 2 480,00 │
 *   │                              [Close] [Return items]    │
 *   └────────────────────────────────────────────────────────┘
 *
 * A returned line says so on its own row rather than being hidden: what was sold
 * is a fact about the sale, and what came back is a second fact about it. The
 * Return button leads to the dialog that can only take back what is left.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.sales : null
    readonly property var printer: (typeof app !== "undefined" && app) ? app.printing : null

    /* The receipt picture, off until asked for — see the panel below. */
    property bool previewing: false
    readonly property var session: (typeof app !== "undefined" && app) ? app.session : null
    readonly property var workflows: (typeof app !== "undefined" && app)
                                     ? app.workflows : null

    readonly property int saleId: context && context.sale_id ? context.sale_id : 0
    readonly property int measure: 700
    readonly property bool canReturn: session ? session.can("sales.edit") : true

    preferredWidth: 960
    title: Strings.t("sale.transaction_title", "Sale")

    property var row: ({})
    readonly property var text_: row.text !== undefined ? row.text : ({})

    Component.onCompleted: {
        if (ctrl && saleId)
            row = ctrl.sale(saleId) || ({})
    }

    readonly property string tone: {
        if (row.payment_type === "cash")
            return "success"
        if (row.payment_type === "partial")
            return "warning"
        if (row.payment_type === "debt")
            return "danger"
        return ""
    }

    contentItem: ColumnLayout {
        spacing: Tokens.spacing.md

        // -----------------------------------------------------------------
        RowLayout {
            Layout.preferredWidth: dialog.measure
            Layout.fillWidth: true
            spacing: Tokens.spacing.md

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: dialog.row.number !== undefined
                          ? "\u200e" + dialog.row.number : "—"
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.title
                    font.weight: Font.DemiBold
                    color: Fluent.textPrimary
                }

                Text {
                    Layout.fillWidth: true
                    text: {
                        var when = dialog.text_.when !== undefined ? dialog.text_.when : ""
                        var who = dialog.row.customer
                                  ? dialog.row.customer
                                  : Strings.t("pos.walk_in", "Walk-in")
                        return "\u200e" + when + " · " + who
                    }
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                    color: Fluent.textSecondary
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignTop
                visible: dialog.tone !== ""
                implicitWidth: chip.implicitWidth + 2 * Tokens.spacing.md
                implicitHeight: chip.implicitHeight + Tokens.spacing.sm
                radius: Tokens.radius.pill
                color: Tokens.toneFill(dialog.tone)

                Text {
                    id: chip
                    anchors.centerIn: parent
                    text: dialog.text_.payment !== undefined ? dialog.text_.payment : ""
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.caption
                    font.weight: Font.DemiBold
                    color: Tokens.toneInk(dialog.tone)
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Fluent.dividerBorder
        }

        // -----------------------------------------------------------------
        // the lines
        // -----------------------------------------------------------------
        Repeater {
            model: dialog.row.items !== undefined ? dialog.row.items : []

            delegate: RowLayout {
                required property var modelData

                Layout.fillWidth: true
                spacing: Tokens.spacing.md

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        Layout.fillWidth: true
                        text: modelData.name
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.body
                        font.weight: Font.DemiBold
                        color: Fluent.textPrimary
                        elide: Text.ElideRight
                    }

                    Text {
                        visible: modelData.returned > 0
                        text: Strings.tf("return.returned_qty", "{qty} returned",
                                         { qty: modelData.returned })
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.caption
                        color: Tokens.warning
                    }
                }

                Text {
                    Layout.preferredWidth: 200
                    text: "\u200e" + modelData.qty_text + " × " + modelData.price_text
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                    color: Fluent.textSecondary
                    horizontalAlignment: Text.AlignRight
                }

                Text {
                    Layout.preferredWidth: 160
                    text: "\u200e" + modelData.total_text
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                    font.weight: Font.DemiBold
                    color: Fluent.textPrimary
                    horizontalAlignment: Text.AlignRight
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Fluent.dividerBorder
        }

        // -----------------------------------------------------------------
        // the money
        // -----------------------------------------------------------------
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: Tokens.spacing.xl
            rowSpacing: Tokens.spacing.xs

            Text {
                text: Strings.t("pos.summary.total", "Total")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                color: Fluent.textSecondary
            }

            Text {
                Layout.fillWidth: true
                text: "\u200e" + (dialog.text_.total !== undefined ? dialog.text_.total : "—")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.amount
                font.weight: Font.DemiBold
                color: Fluent.textPrimary
                horizontalAlignment: Text.AlignRight
            }

            Text {
                text: Strings.t("pay.paid", "Paid")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                color: Fluent.textSecondary
            }

            Text {
                Layout.fillWidth: true
                text: "\u200e" + (dialog.text_.paid !== undefined ? dialog.text_.paid : "—")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.bodyLarge
                font.weight: Font.DemiBold
                color: Fluent.textPrimary
                horizontalAlignment: Text.AlignRight
            }

            Text {
                visible: dialog.row.payment_type !== "cash"
                text: Strings.t("sales.col.due", "Outstanding")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                color: Fluent.textSecondary
            }

            Text {
                Layout.fillWidth: true
                visible: dialog.row.payment_type !== "cash"
                text: "\u200e" + (dialog.text_.due !== undefined ? dialog.text_.due : "—")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.bodyLarge
                font.weight: Font.DemiBold
                color: Tokens.danger
                horizontalAlignment: Text.AlignRight
            }
        }

        /*
         * The receipt, as it will come out of the printer.
         *
         * Folded away until asked for: this dialog exists to answer "what was on
         * this ticket", and the answer is the table above — the picture is for the
         * second question, "is the reprint going to look right", which is asked
         * when a customer disputes a line or the roll has been changed. Rendering
         * it is the same call the print path makes, so what is on screen is what
         * the device receives.
         */
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 300
            visible: dialog.previewing
            radius: Tokens.radius.md
            color: Fluent.subtleSecondary
            border.width: 1
            border.color: Fluent.dividerBorder
            clip: true

            /* A Flickable with a FluentScrollBar, not QC.ScrollView: the vendored
               FluentWinUI3 ScrollView's background references `vertical` and
               `horizontal` scrollbars that only exist once it has made them, so a
               bare one floods the log with ReferenceErrors and undefined
               assignments. NavRail and SettingsPage avoid it for the same reason. */
            Flickable {
                id: shot
                anchors.fill: parent
                anchors.margins: Tokens.spacing.sm
                clip: true
                contentWidth: width
                contentHeight: paper.height
                boundsBehavior: Flickable.StopAtBounds

                QC.ScrollBar.vertical: FluentScrollBar {
                    policy: QC.ScrollBar.AsNeeded
                }

                Image {
                    id: paper
                    width: Math.min(shot.width,
                                    sourceSize.width > 0 ? sourceSize.width : 1)
                    height: sourceSize.width > 0
                            ? width * sourceSize.height / sourceSize.width : 0
                    source: dialog.printer ? dialog.printer.preview : ""
                    smooth: false
                    fillMode: Image.PreserveAspectFit
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.sm

            Text {
                Layout.fillWidth: true
                text: {
                    if (!dialog.printer)
                        return ""
                    if (dialog.printer.error !== "")
                        return dialog.printer.error
                    var name = dialog.printer.receiptPrinter
                    return name !== ""
                           ? Strings.tf("receipt.printer_is", "Printer: {printer}",
                                        { printer: name })
                           : Strings.t("receipt.no_printer",
                                       "No receipt printer is set in Settings.")
                }
                elide: Text.ElideRight
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.caption
                color: dialog.printer && dialog.printer.error !== "" ? Tokens.danger
                                                                     : Fluent.textTertiary
            }

            GlyphButton {
                glyph: dialog.previewing ? "ic_fluent_eye_off_20_regular"
                                         : "ic_fluent_eye_20_regular"
                text: Strings.t("action.preview", "Preview")
                onClicked: {
                    dialog.previewing = !dialog.previewing
                    if (dialog.previewing && dialog.printer)
                        dialog.printer.previewSale(dialog.saleId)
                }
            }

            GlyphButton {
                glyph: "ic_fluent_print_20_regular"
                text: Strings.t("action.print", "Print")
                enabled: !dialog.printer || !dialog.printer.busy
                onClicked: if (dialog.ctrl) dialog.ctrl.printReceipt(dialog.saleId)
            }

            GlyphButton {
                glyph: "ic_fluent_dismiss_20_regular"
                outlined: true
                text: Strings.t("action.close", "Close")
                onClicked: dialog.close()
            }

            GlyphButton {
                glyph: "ic_fluent_arrow_undo_20_regular"
                text: Strings.t("return.create_title", "Return items")
                highlighted: true
                enabled: dialog.canReturn
                onClicked: {
                    if (dialog.workflows)
                        dialog.workflows.open("return_create",
                                              { sale_id: dialog.saleId })
                    dialog.close()
                }
            }
        }
    }
}

import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * One return: which sale it came from, what came back, and why.
 *
 * Read-only. A return is a record of something that happened at the counter; the
 * only thing that can be done to it afterwards is undoing it, which belongs on the
 * list where the confirmation can say what the undo costs.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.returns : null
    readonly property int returnId: context && context.return_id ? context.return_id : 0

    preferredWidth: 860

    title: Strings.t("return.details_title", "Return")

    property var row: null
    property var lines: []

    Component.onCompleted: {
        if (!ctrl || !returnId)
            return
        /* The list already holds the header; only the lines need fetching. */
        for (var i = 0; i < ctrl.rows.length; i++)
            if (ctrl.rows[i].id === returnId)
                row = ctrl.rows[i]
        lines = ctrl.items(returnId)
    }

    contentItem: ColumnLayout {
        spacing: Tokens.spacing.md

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.md

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: dialog.row ? "\u200e" + dialog.row.number : "—"
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.title
                    font.weight: Font.DemiBold
                    color: Fluent.textPrimary
                }

                Text {
                    Layout.fillWidth: true
                    text: dialog.row
                          ? "\u200e" + dialog.row.when + "  ·  "
                            + Strings.t("returns.col.sale", "Sale") + " "
                            + dialog.row.sale
                          : ""
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                    color: Fluent.textSecondary
                    elide: Text.ElideRight
                }
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignTop
                spacing: 0

                Text {
                    Layout.alignment: Qt.AlignRight
                    text: Strings.t("returns.col.total", "Refunded")
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.overline
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.1
                    color: Fluent.textTertiary
                }

                Text {
                    Layout.alignment: Qt.AlignRight
                    text: dialog.row ? "\u200e" + dialog.row.total : "—"
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.amount
                    font.weight: Font.DemiBold
                    color: Tokens.warning
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Fluent.dividerBorder
        }

        Repeater {
            model: dialog.lines

            delegate: RowLayout {
                required property var modelData

                Layout.fillWidth: true
                spacing: Tokens.spacing.md

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
                    Layout.preferredWidth: 200
                    text: "\u200e" + modelData.qty_text + " × " + modelData.price_text
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                    color: Fluent.textSecondary
                    horizontalAlignment: Text.AlignRight
                }

                Text {
                    Layout.preferredWidth: 170
                    text: "\u200e" + modelData.total_text
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                    font.weight: Font.DemiBold
                    color: Fluent.textPrimary
                    horizontalAlignment: Text.AlignRight
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: dialog.row && dialog.row.reason !== ""
            spacing: 2

            Text {
                text: Strings.t("stock.reason", "Reason")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.overline
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.1
                color: Fluent.textTertiary
            }

            Text {
                Layout.fillWidth: true
                text: dialog.row ? dialog.row.reason : ""
                wrapMode: Text.WordWrap
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                color: Fluent.textPrimary
            }
        }

        RowLayout {
            Layout.fillWidth: true

            Item { Layout.fillWidth: true }

            GlyphButton {
                glyph: "ic_fluent_dismiss_20_regular"
                outlined: true
                text: Strings.t("action.close", "Close")
                onClicked: dialog.close()
            }
        }
    }
}

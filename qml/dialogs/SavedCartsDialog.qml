import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * Carts parked mid-sale. Ported from
 * pos/app/dialogs/pos_dialogs.py::SavedCartsDialog.
 *
 *   ┌──────────────────────────────────────────────────────────┐
 *   │ Saved carts                                              │
 *   │ 003  Amine Bekkar     4 lines   7   12 480,00   14:05    │
 *   │ 002  Walk-in          2 lines   2    1 240,00   13:52    │
 *   │ ⚠ Opening a saved cart replaces the one on the counter.   │
 *   │                              [Close] [Delete] [Open]     │
 *   └──────────────────────────────────────────────────────────┘
 *
 * THE WARNING IS THE CONFIRMATION
 *
 * pos asks a second time in a nested dialog when the current cart is not empty.
 * Here the warning is a line in this dialog, shown only in that case, and Open is
 * the answer to it — one surface instead of a dialog on top of a dialog. Nothing
 * is lost: the operator cannot press Open without the sentence being on screen.
 *
 * Restoring deletes the held row, as it does in pos: a cart that existed in two
 * places at once would be sold twice.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var till: (typeof app !== "undefined" && app) ? app.pos : null

    readonly property int measure: 820
    readonly property int listHeight: 340

    preferredWidth: 1060
    title: Strings.t("carts.title", "Saved carts")

    property var rows: []
    property int selected: -1

    readonly property bool cartBusy: till && till.lines.length > 0

    Component.onCompleted: reload()

    function reload() {
        rows = till ? till.heldCarts() : []
        selected = -1
    }

    function open_() {
        if (selected < 0 || selected >= rows.length)
            return
        if (till)
            till.restore(rows[selected].id)
        dialog.close()
    }

    function discard() {
        if (selected < 0 || selected >= rows.length)
            return
        if (till)
            till.discard(rows[selected].id)
        reload()
    }

    component Cell: Text {
        font.family: Tokens.font.family
        font.pixelSize: Tokens.font.body
        color: Fluent.textPrimary
        elide: Text.ElideRight
    }

    contentItem: ColumnLayout {
        spacing: Tokens.spacing.md

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredWidth: dialog.measure
            Layout.preferredHeight: dialog.listHeight
            color: Fluent.cardBackground
            radius: Tokens.radius.md
            border.width: 1
            border.color: Fluent.dividerBorder

            ListView {
                id: list
                anchors.fill: parent
                anchors.margins: 1
                clip: true
                model: dialog.rows

                QC.ScrollBar.vertical: FluentScrollBar {
                    policy: QC.ScrollBar.AsNeeded
                }

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index

                    width: list.width
                    height: Tokens.size.tableRow
                    color: index === dialog.selected ? Tokens.brandTint
                         : hover.hovered ? Fluent.subtleSecondary : "transparent"

                    HoverHandler { id: hover }
                    TapHandler {
                        onTapped: dialog.selected = row.index
                        onDoubleTapped: {
                            dialog.selected = row.index
                            dialog.open_()
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.spacing.md
                        anchors.rightMargin: Tokens.spacing.md
                        spacing: Tokens.spacing.md

                        Cell {
                            Layout.preferredWidth: 90
                            text: "\u200e" + row.modelData.number
                            font.weight: Font.DemiBold
                        }

                        Cell {
                            Layout.fillWidth: true
                            text: row.modelData.customer
                        }

                        Cell {
                            Layout.preferredWidth: 90
                            text: row.modelData.lines
                            color: Fluent.textSecondary
                            horizontalAlignment: Text.AlignRight
                        }

                        Cell {
                            Layout.preferredWidth: 90
                            text: "\u200e" + row.modelData.qty
                            color: Fluent.textSecondary
                            horizontalAlignment: Text.AlignRight
                        }

                        Cell {
                            Layout.preferredWidth: 150
                            text: "\u200e" + row.modelData.total
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignRight
                        }

                        Cell {
                            Layout.preferredWidth: 170
                            text: "\u200e" + row.modelData.when
                            color: Fluent.textSecondary
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }
            }

            StateView {
                anchors.fill: parent
                visible: list.count === 0
                variant: "empty"
                title: Strings.t("state.empty.title", "Nothing here yet")
                body: Strings.t("carts.empty", "No saved carts.")
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: dialog.cartBusy
            spacing: Tokens.spacing.sm

            Icon {
                Layout.alignment: Qt.AlignVCenter
                icon: "ic_fluent_warning_20_regular"
                size: Tokens.icon.sm
                color: Tokens.warning
            }

            Text {
                Layout.fillWidth: true
                text: Strings.t("confirm.cart_not_empty.body",
                                "Opening a saved cart replaces the cart on the counter.")
                wrapMode: Text.WordWrap
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.caption
                color: Fluent.textSecondary
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.sm

            GlyphButton {
                glyph: "ic_fluent_dismiss_20_regular"
                outlined: true
                text: Strings.t("action.close", "Close")
                onClicked: dialog.close()
            }

            Item { Layout.fillWidth: true }

            GlyphButton {
                glyph: "ic_fluent_delete_20_regular"
                text: Strings.t("action.delete", "Delete")
                enabled: dialog.selected >= 0
                onClicked: dialog.discard()
            }

            GlyphButton {
                glyph: "ic_fluent_arrow_hook_up_left_20_regular"
                text: Strings.t("carts.open", "Open")
                highlighted: true
                enabled: dialog.selected >= 0
                onClicked: dialog.open_()
            }
        }
    }
}

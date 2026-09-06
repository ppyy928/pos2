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
 *   │ NUMBER  CUSTOMER      LINES  QTY     AMOUNT   SAVED AT   │
 *   │ 003     Amine Bekkar      4    7  12 480,00      14:05 ↩🗑│
 *   │ 002     Walk-in           2    2   1 240,00      13:52 ↩🗑│
 *   │ ⚠ Opening a saved cart replaces the one on the counter.   │
 *   │                              [Close] [Delete] [Open]     │
 *   └──────────────────────────────────────────────────────────┘
 *
 * TWO WAYS TO THE SAME TWO ACTS, ON PURPOSE
 *
 * The footer buttons act on the selected row; the icons act on the row they sit in.
 * That is not a duplicate — it is the difference between "I have been reading this
 * list and I mean that one" and "that one", and a list of parked sales is read both
 * ways: an operator scanning five held carts for the right customer wants to select
 * and confirm, one coming back for the cart they parked a minute ago wants to press
 * the row and be done. Every other list in this app carries row actions, so a
 * selection-only list here was the odd one out.
 *
 * Double-tapping a row still opens it, which is the third way and the one nobody has
 * to be taught.
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

    /* Column widths, in one place. They lived in the delegate while the rows had
       nothing to line up against; now the heading band measures the same columns,
       and a heading four pixels out of step with the figures under it is worse
       than no heading at all. Widths are pos's (pos_dialogs.py:263-270), the
       action strip aside. */
    readonly property int colNumber:  90
    readonly property int colLines:   90
    readonly property int colQty:     90
    readonly property int colTotal:  150
    readonly property int colWhen:   170
    readonly property int colActions: 96

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
        openRow(selected)
    }

    function discard() {
        if (selected < 0 || selected >= rows.length)
            return
        discardRow(selected)
    }

    /* By index, so a row action does not have to select first. Selecting on the way
       through keeps the footer buttons and the icons talking about the same cart —
       and the row stays highlighted while the confirmation is up. */
    function openRow(index) {
        if (index < 0 || index >= rows.length)
            return
        selected = index
        if (till)
            till.restore(rows[index].id)
        dialog.close()
    }

    function discardRow(index) {
        if (index < 0 || index >= rows.length)
            return
        selected = index
        confirmDiscard.row = rows[index]
        confirmDiscard.open()
    }

    /*
     * Discarding a parked cart asks first — and it did not, which was the real gap
     * here: the footer's Delete threw a sale away on one press with nothing on screen
     * about what was in it. A held cart is somebody's shopping, and the number is not
     * enough to recognise it by, so the confirmation names the customer, the lines and
     * what it came to.
     */
    ConfirmDialog {
        id: confirmDiscard

        property var row: null

        title: Strings.t("carts.discard.title", "Discard this parked cart?")
        body: Strings.t("carts.discard.body",
                        "Nothing was sold, so nothing is reversed — the lines are simply gone.")

        facts: row ? [
            {
                label: Strings.t("carts.col.number", "Number"),
                value: row.number,
                tone: ""
            },
            {
                label: Strings.t("pos.customer", "Customer"),
                value: row.customer,
                tone: ""
            },
            {
                label: Strings.t("pos.summary.items", "Items"),
                value: row.lines + " \u00b7 " + row.qty,
                tone: ""
            },
            {
                label: Strings.t("pos.summary.total", "Total"),
                value: row.total,
                tone: ""
            }
        ] : []

        confirmText: Strings.t("carts.discard.action", "Discard the cart")

        onConfirmed: {
            if (dialog.till && confirmDiscard.row)
                dialog.till.discard(confirmDiscard.row.id)
            dialog.reload()
        }
    }

    component Cell: Text {
        font.family: Tokens.font.family
        font.pixelSize: Tokens.font.body
        color: Fluent.textPrimary
        elide: Text.ElideRight
    }

    /* The heading band's type, which is DataTable's: 13px caps, letter-spaced,
       secondary ink. Not a Cell in a different colour — a heading is a different
       thing from a value, and every other table in this app draws it as one. */
    component Heading: Text {
        font.family: Tokens.font.family
        font.pixelSize: Tokens.font.overline
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.8
        color: Fluent.textSecondary
        elide: Text.ElideRight
        maximumLineCount: 1
        verticalAlignment: Text.AlignVCenter
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

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 1
                spacing: 0

                /*
                 * THE HEADING ROW, WHICH WAS NOT HERE.
                 *
                 * Six columns, four of them bare figures — "2  4  12,167.78
                 * 03/09/2026 16:25" reads as four unrelated numbers until somebody
                 * tells you the first is lines and the second is items, and the two
                 * counts are the pair nobody guesses. pos labelled all six
                 * (pos_dialogs.py:277-284) and the port dropped the labels while
                 * keeping the columns; the keys were translated then and are still
                 * in the catalogue (i18n.py:606-611), so this is the port catching
                 * up rather than new copy.
                 *
                 * DataTable's metrics rather than invented ones — 48px, the subtle
                 * fill, 13px caps, the divider underneath — because this table is
                 * the same furniture as the ones on the pages. It cannot BE a
                 * DataTable: the rows select on a single tap and carry a two-icon
                 * action strip that is not one of DataTable's cell kinds.
                 *
                 * Nothing here sorts. `heldCarts()` hands over newest-first and
                 * that is the only order a list of five parked sales wants, so the
                 * headings are labels, not buttons — no hover, no arrow, nothing
                 * that suggests a press would do something.
                 */
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Tokens.size.tableHeader
                    color: Fluent.subtleSecondary

                    /* Square corners inside a 10px-radius card show as two nubs at
                       the top edge, because a rounded Rectangle clips to its
                       bounding box and not to its corner arcs. Per-corner radii are
                       the exact fix and Qt has had them since 6.7 (this runs
                       6.9.3), so no inset is needed to hide the problem. Both top
                       corners take the same value, which is also why mirroring has
                       nothing to do here. */
                    topLeftRadius: Tokens.radius.md - 1
                    topRightRadius: Tokens.radius.md - 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.spacing.md
                        anchors.rightMargin: Tokens.spacing.md
                        spacing: Tokens.spacing.md

                        Heading {
                            Layout.preferredWidth: dialog.colNumber
                            text: Strings.t("carts.col.number", "Number")
                        }

                        Heading {
                            Layout.fillWidth: true
                            text: Strings.t("carts.col.customer", "Customer")
                        }

                        /* Right-aligned over right-aligned values: a heading
                           belongs on the edge its column's digits sit on. */
                        Heading {
                            Layout.preferredWidth: dialog.colLines
                            horizontalAlignment: Text.AlignRight
                            text: Strings.t("carts.col.lines", "Lines")
                        }

                        Heading {
                            Layout.preferredWidth: dialog.colQty
                            horizontalAlignment: Text.AlignRight
                            text: Strings.t("carts.col.qty", "Total qty")
                        }

                        Heading {
                            Layout.preferredWidth: dialog.colTotal
                            horizontalAlignment: Text.AlignRight
                            text: Strings.t("carts.col.amount", "Amount")
                        }

                        Heading {
                            Layout.preferredWidth: dialog.colWhen
                            horizontalAlignment: Text.AlignRight
                            text: Strings.t("carts.col.time", "Saved at")
                        }

                        /* The action strip has no heading, as it has none in
                           DataTable — there is nothing to name. */
                        Item { Layout.preferredWidth: dialog.colActions }
                    }

                    // On top of the fill, so the line reads as the boundary
                    // between heading and data rather than the bar's own edge.
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: Fluent.divider
                    }
                }

                /*
                 * The rows and the "nothing saved" message share one box under the
                 * heading, which is why there is an Item around them at all: an
                 * anchor reaches a parent or a sibling and nothing else, so a
                 * StateView left outside this wrapper could not be pinned to the
                 * list, and a second fillHeight child of the ColumnLayout would be
                 * handed half the height instead of lying over the rows.
                 */
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ListView {
                        id: list
                        anchors.fill: parent
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
                                    Layout.preferredWidth: dialog.colNumber
                                    text: "\u200e" + row.modelData.number
                                    font.weight: Font.DemiBold
                                }

                                Cell {
                                    Layout.fillWidth: true
                                    text: row.modelData.customer
                                }

                                Cell {
                                    Layout.preferredWidth: dialog.colLines
                                    text: row.modelData.lines
                                    color: Fluent.textSecondary
                                    horizontalAlignment: Text.AlignRight
                                }

                                Cell {
                                    Layout.preferredWidth: dialog.colQty
                                    text: "\u200e" + row.modelData.qty
                                    color: Fluent.textSecondary
                                    horizontalAlignment: Text.AlignRight
                                }

                                Cell {
                                    Layout.preferredWidth: dialog.colTotal
                                    text: "\u200e" + row.modelData.total
                                    font.weight: Font.DemiBold
                                    horizontalAlignment: Text.AlignRight
                                }

                                Cell {
                                    Layout.preferredWidth: dialog.colWhen
                                    text: "\u200e" + row.modelData.when
                                    color: Fluent.textSecondary
                                    horizontalAlignment: Text.AlignRight
                                }

                                /* The same strip every table in this app puts at
                                   the end of a row, with the two acts a parked
                                   cart has. `open` is not one of RowActions'
                                   seven ids, so it brings its own glyph and tone;
                                   `delete` is. */
                                RowActions {
                                    Layout.preferredWidth: dialog.colActions
                                    Layout.fillHeight: true
                                    rowData: row.modelData
                                    actions: [
                                        {
                                            id: "open",
                                            glyph: "ic_fluent_arrow_hook_up_left_20_regular",
                                            tone: "primary",
                                            label: Strings.t("carts.open", "Open")
                                        },
                                        { id: "delete" }
                                    ]
                                    onTriggered: (action) => {
                                        if (action === "open")
                                            dialog.openRow(row.index)
                                        else if (action === "delete")
                                            dialog.discardRow(row.index)
                                    }
                                }
                            }
                        }
                    }

                    /* Over the rows only. The headings stay up with nothing under
                       them — they say what the list would hold, and DataTable
                       leaves its own header standing on an empty table for the
                       same reason. */
                    StateView {
                        anchors.fill: parent
                        visible: list.count === 0
                        variant: "empty"
                        title: Strings.t("state.empty.title", "Nothing here yet")
                        body: Strings.t("carts.empty", "No saved carts.")
                    }
                }
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

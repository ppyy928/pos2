import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * Categories — the tabs on the till and the colour of every tile under them.
 * Ported from pos's category management.
 *
 *   ┌ Categories ──────────────────────────────────────┐
 *   │ ■ Beverages          228 products   ↑ ↓  ✏  🗑  │
 *   │ ■ Dairy              233 products   ↑ ↓  ✏  🗑  │
 *   ├──────────────────────────────────────────────────┤
 *   │ + Add category                            Close  │
 *   └──────────────────────────────────────────────────┘
 *
 * A LIST, AND NOTHING ELSE
 *
 * Names and colours are edited in `CategoryFormDialog`, which opens over this one.
 * What used to be here was an entry row welded to the bottom that was both the add
 * form and the editor of the selected row, with nothing but a button's word to say
 * which — so adding a category while a row was selected renamed that category.
 *
 * Deleting one never orphans its products: pos reassigns them first, to the category
 * chosen in the confirmation or to "Uncategorized". That is why the product count
 * sits on every row and why the confirmation has a destination picker.
 *
 * Order matters as much as the names: it is the order of the tabs above the tile
 * grid, and a cashier's hand learns it. So rows move with two buttons and the new
 * order is written as soon as it changes.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.catalogue : null
    readonly property int measure: 760
    readonly property int listHeight: 380

    preferredWidth: 1000
    title: Strings.t("categories.title", "Categories")

    property var rows: []

    Component.onCompleted: reload()

    function reload() {
        rows = ctrl ? ctrl.categories() : []
    }

    function move(from, to) {
        if (from < 0 || to < 0 || from >= rows.length || to >= rows.length)
            return
        var order = []
        for (var i = 0; i < rows.length; i++)
            order.push(rows[i].id)
        var moved = order.splice(from, 1)[0]
        order.splice(to, 0, moved)
        if (ctrl)
            ctrl.reorderCategories(order)
    }

    Connections {
        target: dialog.ctrl
        ignoreUnknownSignals: true
        function onChanged() { dialog.reload() }
        /* The form reports its own refusals while it is open; this is left with
           the ones that belong to a reorder or a delete. */
        function onRejected(message) {
            if (!form.visible)
                error.text = message
        }
    }

    // =====================================================================
    // THE FORM, AND THE ONE DESTRUCTIVE QUESTION
    // =====================================================================
    /* Declared here rather than routed through `workflows`: the form belongs to this
       list's task, has no permission of its own to check, and takes the row it is
       editing straight from `edit(row)` instead of a context. DialogHost stacks, so
       either way it would draw over this list — this is about ownership, not
       layering. */
    CategoryFormDialog {
        id: form
        onCommitted: error.text = ""
    }

    /* Where do its products go? That question is the confirmation. */
    FluentDialog {
        id: confirmDelete

        property var target: null
        readonly property int measure: 480

        modal: true
        title: Strings.t("categories.delete.title", "Delete this category?")
        standardButtons: QC.Dialog.Yes | QC.Dialog.No

        onAccepted: if (dialog.ctrl && confirmDelete.target)
                        dialog.ctrl.deleteCategory(
                            confirmDelete.target.id,
                            reassign.currentIndex > 0
                            ? reassign.model[reassign.currentIndex].id : 0)

        contentItem: ColumnLayout {
            spacing: Tokens.spacing.sm

            Text {
                Layout.preferredWidth: confirmDelete.measure
                text: Strings.t("categories.delete.body",
                                "Its products are moved rather than deleted. Choose where they go.")
                wrapMode: Text.WordWrap
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                color: Fluent.textPrimary
            }

            Text {
                Layout.preferredWidth: confirmDelete.measure
                visible: confirmDelete.target !== null
                text: confirmDelete.target ? confirmDelete.target.name : ""
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                font.weight: Font.DemiBold
                color: Fluent.textPrimary
            }

            QC.ComboBox {
                id: reassign
                Layout.fillWidth: true
                textRole: "name"
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                model: {
                    var out = [{ id: 0,
                                 name: Strings.t("categories.uncategorized",
                                                 "Uncategorized") }]
                    var skip = confirmDelete.target ? confirmDelete.target.id : 0
                    for (var i = 0; i < dialog.rows.length; i++)
                        if (dialog.rows[i].id !== skip)
                            out.push(dialog.rows[i])
                    return out
                }
            }
        }
    }

    // =====================================================================
    // LAYOUT
    // =====================================================================
    contentItem: ColumnLayout {
        spacing: Tokens.spacing.md

        Rectangle {
            Layout.preferredWidth: dialog.measure
            Layout.fillWidth: true
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
                    color: hover.hovered ? Fluent.subtleSecondary : "transparent"

                    HoverHandler { id: hover }
                    /* The row opens its own editor — the same gesture as every
                       table in this app. */
                    TapHandler { onTapped: form.edit(row.modelData) }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.spacing.md
                        anchors.rightMargin: Tokens.spacing.xs + Tokens.size.scrollSeat
                        spacing: Tokens.spacing.md

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            width: 20
                            height: 20
                            radius: Tokens.radius.sm
                            color: row.modelData.color !== ""
                                   ? row.modelData.color : Fluent.subtleTertiary
                            border.width: 1
                            border.color: Fluent.dividerBorder
                        }

                        Text {
                            Layout.fillWidth: true
                            text: row.modelData.name
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.body
                            font.weight: Font.DemiBold
                            color: Fluent.textPrimary
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.preferredWidth: 140
                            text: Strings.tf("categories.products", "{count} products",
                                             { count: row.modelData.products_text })
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.caption
                            color: Fluent.textSecondary
                            horizontalAlignment: Text.AlignRight
                        }

                        IconButton {
                            glyph: "ic_fluent_arrow_up_20_regular"
                            glyphSize: Tokens.icon.sm
                            enabled: row.index > 0
                            tooltip: Strings.t("action.move_up", "Move up")
                            onClicked: dialog.move(row.index, row.index - 1)
                        }

                        IconButton {
                            glyph: "ic_fluent_arrow_down_20_regular"
                            glyphSize: Tokens.icon.sm
                            enabled: row.index < dialog.rows.length - 1
                            tooltip: Strings.t("action.move_down", "Move down")
                            onClicked: dialog.move(row.index, row.index + 1)
                        }

                        IconButton {
                            glyph: "ic_fluent_edit_20_regular"
                            glyphSize: Tokens.icon.sm
                            tooltip: Strings.t("action.edit", "Edit")
                            onClicked: form.edit(row.modelData)
                        }

                        IconButton {
                            glyph: "ic_fluent_delete_20_regular"
                            glyphSize: Tokens.icon.sm
                            glyphColor: Tokens.danger
                            tooltip: Strings.t("action.delete", "Delete")
                            onClicked: {
                                confirmDelete.target = row.modelData
                                confirmDelete.open()
                            }
                        }
                    }
                }
            }

            StateView {
                anchors.fill: parent
                visible: list.count === 0
                variant: "empty"
                title: Strings.t("categories.empty.title", "No categories yet")
                actionText: Strings.t("categories.add_title", "Add category")
                onActionRequested: form.edit(null)
            }
        }

        Text {
            id: error
            Layout.fillWidth: true
            Layout.preferredWidth: dialog.measure
            visible: text !== ""
            wrapMode: Text.WordWrap
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.caption
            color: Tokens.danger
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.sm

            GlyphButton {
                glyph: "ic_fluent_add_20_regular"
                text: Strings.t("categories.add_title", "Add category")
                highlighted: true
                onClicked: form.edit(null)
            }

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

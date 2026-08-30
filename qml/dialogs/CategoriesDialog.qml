import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * Categories — the tabs on the till and the colour of every tile under them.
 * Ported from pos's category management.
 *
 * Deleting one never orphans its products: pos reassigns them first, to the
 * category chosen here or to "Uncategorized" if none is. That is why the product
 * count sits on every row and why the delete confirmation has a destination
 * picker rather than a plain yes.
 *
 * Order matters as much as the names: it is the order the tabs appear in above the
 * tile grid, and a cashier's hand learns it. So the rows move with two buttons and
 * the new order is written as soon as it changes.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.catalogue : null
    readonly property int measure: 760
    readonly property int listHeight: 340

    preferredWidth: 1000
    title: Strings.t("categories.title", "Categories")

    property var rows: []
    property int selected: -1
    readonly property var current: selected >= 0 && selected < rows.length
                                  ? rows[selected] : null

    /* The token hues, which is where every other colour on this screen comes
       from — so a category can only be given a colour the rest of the app already
       knows how to draw on a tile. */
    readonly property var palette: [
        Tokens.hue.emerald, Tokens.hue.indigo, Tokens.hue.teal, Tokens.hue.amber,
        Tokens.hue.crimson, Tokens.hue.violet, Tokens.hue.rose, Tokens.hue.slate
    ]
    property string colour: ""

    Component.onCompleted: reload()

    function reload() {
        rows = ctrl ? ctrl.categories() : []
        if (selected >= rows.length)
            selected = -1
        fill()
    }

    function fill() {
        name.text = current ? current.name : ""
        colour = current ? current.color : ""
    }

    onSelectedChanged: fill()

    function save() {
        error.text = ""
        if (ctrl)
            ctrl.saveCategory(name.text, colour, current ? current.id : 0)
    }

    function move(from, to) {
        if (from < 0 || to < 0 || from >= rows.length || to >= rows.length)
            return
        var order = []
        for (var i = 0; i < rows.length; i++)
            order.push(rows[i].id)
        var moved = order.splice(from, 1)[0]
        order.splice(to, 0, moved)
        selected = to
        if (ctrl)
            ctrl.reorderCategories(order)
    }

    Connections {
        target: dialog.ctrl
        ignoreUnknownSignals: true
        function onChanged() { dialog.reload() }
        function onRejected(message) { error.text = message }
    }

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
                    color: index === dialog.selected ? Tokens.brandTint
                         : hover.hovered ? Fluent.subtleSecondary : "transparent"

                    HoverHandler { id: hover }
                    TapHandler { onTapped: dialog.selected = row.index }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.spacing.md
                        anchors.rightMargin: Tokens.spacing.xs
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
                            glyph: "ic_fluent_delete_20_regular"
                            glyphSize: Tokens.icon.sm
                            glyphColor: Tokens.danger
                            tooltip: Strings.t("action.delete", "Delete")
                            onClicked: {
                                dialog.selected = row.index
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
            }
        }

        // -----------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.sm

            QC.TextField {
                id: name
                Layout.fillWidth: true
                Layout.preferredHeight: Tokens.size.control
                placeholderText: Strings.t("categories.name", "Category name")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                onAccepted: dialog.save()
            }

            /* Swatches, not a colour picker: eight hues that the tile grid can
               tell apart, and "none" for letting pos choose. */
            Row {
                Layout.alignment: Qt.AlignVCenter
                spacing: 4

                Repeater {
                    model: dialog.palette

                    delegate: Rectangle {
                        required property var modelData
                        width: 28
                        height: 28
                        radius: Tokens.radius.sm
                        color: modelData
                        border.width: dialog.colour === String(modelData) ? 3 : 1
                        border.color: dialog.colour === String(modelData)
                                      ? Fluent.textPrimary : Fluent.dividerBorder

                        TapHandler { onTapped: dialog.colour = String(modelData) }
                    }
                }

                Rectangle {
                    width: 28
                    height: 28
                    radius: Tokens.radius.sm
                    color: "transparent"
                    border.width: dialog.colour === "" ? 3 : 1
                    border.color: dialog.colour === "" ? Fluent.textPrimary
                                                       : Fluent.dividerBorder

                    Text {
                        anchors.centerIn: parent
                        text: "—"
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.body
                        color: Fluent.textSecondary
                    }

                    TapHandler { onTapped: dialog.colour = "" }
                }
            }

            GlyphButton {
                glyph: "ic_fluent_save_20_regular"
                text: dialog.current ? Strings.t("action.save", "Save")
                                     : Strings.t("categories.add", "Add")
                enabled: name.text.trim() !== ""
                onClicked: dialog.save()
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

            GlyphButton {
                visible: dialog.selected >= 0
                text: Strings.t("categories.new", "New category")
                onClicked: dialog.selected = -1
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

    /* Where do its products go? That question is the confirmation. */
    FluentDialog {
        id: confirmDelete
        readonly property int measure: 480

        modal: true
        title: Strings.t("categories.delete.title", "Delete this category?")
        standardButtons: QC.Dialog.Yes | QC.Dialog.No

        onAccepted: if (dialog.ctrl && dialog.current)
                        dialog.ctrl.deleteCategory(
                            dialog.current.id,
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
                    for (var i = 0; i < dialog.rows.length; i++)
                        if (!dialog.current || dialog.rows[i].id !== dialog.current.id)
                            out.push(dialog.rows[i])
                    return out
                }
            }
        }
    }
}

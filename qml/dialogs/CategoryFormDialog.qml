import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * One category: its name, and the colour every tile under it is painted.
 *
 *     ┌ Add category ───────────────────────┐
 *     │ Name *                              │
 *     │ [ Beverages                      ]  │
 *     │ Tile colour                         │
 *     │ ■ ■ ■ ■ ■ ■ ■ ■ —                  │
 *     │                     Cancel   Save   │
 *     └─────────────────────────────────────┘
 *
 * WHY A DIALOG AND NOT THE ROW UNDER THE LIST
 *
 * The list used to carry an entry row that was both the add form and the editor of
 * whatever row happened to be selected. The only thing distinguishing the two was a
 * button changing its word, so adding a category with a row selected renamed that
 * category instead — and the till's tabs are the first thing a cashier looks at.
 *
 * WHY EIGHT COLOURS AND NOT A PICKER
 *
 * These are the token hues, which is where every other colour in the app comes
 * from. A free picker lets a shop choose something the tile grid cannot draw
 * legibly; "—" means "let pos pick from the palette", which is what most do.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.catalogue : null

    /* The category being edited. 0 adds one. Writable: the list reuses one
       instance for every row. */
    property int categoryId: 0
    property string colour: ""

    readonly property bool creating: categoryId === 0
    readonly property int measure: 460

    preferredWidth: 600

    title: creating ? Strings.t("categories.add_title", "Add category")
                    : Strings.t("categories.edit_title", "Edit category")

    signal committed()

    readonly property var palette: [
        Tokens.hue.emerald, Tokens.hue.indigo, Tokens.hue.teal, Tokens.hue.amber,
        Tokens.hue.crimson, Tokens.hue.violet, Tokens.hue.rose, Tokens.hue.slate
    ]

    /* The list's entry point. Imperative, because a binding on `text` dies at the
       first keystroke and the next row would open showing the previous name. */
    function edit(row) {
        categoryId = row && row.id ? row.id : 0
        name.text = row && row.name ? row.name : ""
        colour = row && row.color ? row.color : ""
        error.text = ""
        open()
        name.forceActiveFocus()
        name.selectAll()
    }

    Component.onCompleted: {
        if (context && context.category_id)
            categoryId = context.category_id
        if (context && context.name)
            name.text = context.name
        if (context && context.color)
            colour = context.color
        name.forceActiveFocus()
    }

    function save() {
        error.text = ""
        if (!ctrl)
            return
        if (name.text.trim() === "") {
            error.text = Strings.t("categories.name.required",
                                   "A category needs a name.")
            name.forceActiveFocus()
            return
        }
        ctrl.saveCategory(name.text, colour, categoryId)
    }

    Connections {
        target: dialog.ctrl
        ignoreUnknownSignals: true

        /* The catalogue's success signal says only "something changed", so the
           guard is this dialog's own visibility: it outlives its open, and a
           delete in the list behind it emits the same thing. */
        function onChanged() {
            if (!dialog.visible)
                return
            dialog.committed()
            dialog.close()
        }

        function onRejected(message) {
            if (dialog.visible)
                error.text = message
        }
    }

    contentItem: ColumnLayout {
        spacing: Tokens.spacing.md

        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: dialog.measure
            spacing: 2

            Text {
                text: Strings.t("categories.name", "Category name") + " *"
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.caption
                font.weight: Font.DemiBold
                color: Fluent.textSecondary
            }

            QC.TextField {
                id: name
                Layout.fillWidth: true
                Layout.preferredHeight: Tokens.size.control
                placeholderText: Strings.t("categories.name.ph",
                                           "Beverages, Dairy, Cleaning…")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.bodyLarge
                onAccepted: dialog.save()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.xs

            Text {
                text: Strings.t("categories.colour", "Tile colour")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.caption
                font.weight: Font.DemiBold
                color: Fluent.textSecondary
            }

            Row {
                spacing: Tokens.spacing.xs

                Repeater {
                    model: dialog.palette

                    delegate: Rectangle {
                        required property var modelData
                        width: 36
                        height: 36
                        radius: Tokens.radius.sm
                        color: modelData
                        border.width: dialog.colour === String(modelData) ? 3 : 1
                        border.color: dialog.colour === String(modelData)
                                      ? Fluent.textPrimary : Fluent.dividerBorder

                        TapHandler { onTapped: dialog.colour = String(modelData) }
                    }
                }

                /* "Let pos choose" — the palette assigns one on save. */
                Rectangle {
                    width: 36
                    height: 36
                    radius: Tokens.radius.sm
                    color: "transparent"
                    border.width: dialog.colour === "" ? 3 : 1
                    border.color: dialog.colour === "" ? Fluent.textPrimary
                                                       : Fluent.dividerBorder

                    Text {
                        anchors.centerIn: parent
                        text: "\u2014"
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.body
                        color: Fluent.textSecondary
                    }

                    TapHandler { onTapped: dialog.colour = "" }
                }
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

            Item { Layout.fillWidth: true }

            GlyphButton {
                glyph: "ic_fluent_dismiss_20_regular"
                outlined: true
                text: Strings.t("action.cancel", "Cancel")
                onClicked: dialog.close()
            }

            GlyphButton {
                glyph: "ic_fluent_save_20_regular"
                text: Strings.t("action.save", "Save")
                highlighted: true
                enabled: name.text.trim() !== ""
                onClicked: dialog.save()
            }
        }
    }
}

import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * Units of measure — piece, kilogram, litre. Ported from pos's unit management.
 *
 *   ┌ Units ─────────────────────────────┐
 *   │ Box                         ✏  🗑  │
 *   │ Kilogram                    ✏  🗑  │
 *   │ Litre                       ✏  🗑  │
 *   ├────────────────────────────────────┤
 *   │ + Add unit                  Close  │
 *   └────────────────────────────────────┘
 *
 * A LIST, AND NOTHING ELSE
 *
 * Adding and renaming both happen in `UnitFormDialog`, which opens over this one.
 * What used to be here instead was an entry row welded to the bottom that doubled
 * as the editor of whichever row was selected — two jobs, one set of fields, and
 * no way to tell from the screen which of them was about to happen.
 *
 * A unit is one word. There is no short code to type any more: the only place it
 * was read is the suffix on a product's stock cell, and that now falls back to the
 * unit's name.
 *
 * DELETING ONE DOES NOT REFUSE
 *
 * pos reassigns rather than refuses: every product on the unit is left with none,
 * and the products stay. Silent, if nobody says so — so the confirmation names the
 * unit and says how many products it is about to detach.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.catalogue : null
    readonly property int measure: 560
    readonly property int listHeight: 320

    preferredWidth: 700
    title: Strings.t("units.title", "Units")

    property var rows: []

    Component.onCompleted: reload()

    function reload() {
        rows = ctrl ? ctrl.units() : []
    }

    Connections {
        target: dialog.ctrl
        ignoreUnknownSignals: true
        function onChanged() { dialog.reload() }
        /* The form shows its own refusals while it is open; this catches the ones
           that belong to a delete. */
        function onRejected(message) {
            if (!form.visible)
                error.text = message
        }
    }

    // =====================================================================
    // THE ADD/EDIT FORM, AND THE ONE DESTRUCTIVE QUESTION
    // =====================================================================
    /* Declared here rather than routed through `workflows`: the form belongs to this
       list's task, has no permission of its own, and is handed the row by `edit(row)`
       rather than a context. DialogHost stacks either way. */
    UnitFormDialog {
        id: form
        onCommitted: error.text = ""
    }

    FluentDialog {
        id: confirmDelete

        property int unitId: -1
        property string unitName: ""
        readonly property int measure: 440

        modal: true
        title: Strings.t("units.delete.title", "Delete this unit?")
        standardButtons: QC.Dialog.Yes | QC.Dialog.No

        onAccepted: if (dialog.ctrl) dialog.ctrl.deleteUnit(confirmDelete.unitId)

        contentItem: Column {
            spacing: Tokens.spacing.sm

            Text {
                width: confirmDelete.measure
                text: Strings.t("units.delete.body",
                                "Products measured in it keep their stock and are left without a unit.")
                wrapMode: Text.WordWrap
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                color: Fluent.textPrimary
            }

            Text {
                width: confirmDelete.measure
                text: confirmDelete.unitName
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                font.weight: Font.DemiBold
                color: Fluent.textPrimary
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
                        anchors.rightMargin: Tokens.spacing.xs
                        spacing: Tokens.spacing.md

                        Text {
                            Layout.fillWidth: true
                            text: row.modelData.name
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.body
                            font.weight: Font.DemiBold
                            color: Fluent.textPrimary
                            elide: Text.ElideRight
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
                                confirmDelete.unitId = row.modelData.id
                                confirmDelete.unitName = row.modelData.name
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
                title: Strings.t("units.empty.title", "No units yet")
                actionText: Strings.t("units.add_title", "Add unit")
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
                text: Strings.t("units.add_title", "Add unit")
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

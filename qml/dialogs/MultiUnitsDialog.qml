import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * Multi-units — the second way a product is sold. Ported from pos's multi-unit
 * management.
 *
 *   Coca-Cola 1.5L
 *     Pack of 6      × 6    550,00    6133273409991   ✏ 🗑
 *     Case of 24     × 24  2 100,00   6133273409992   ✏ 🗑
 *
 * This is not labelling. The till's barcode lookup returns a multi-unit hit with
 * its base quantity, so scanning the case's barcode adds twenty-four units at the
 * case's own price — one scan, one line, the right stock movement. That is why a
 * multi-unit needs a barcode of its own to be worth having, and why the ones
 * without are marked.
 *
 * Opened from a product it lists that product's units; opened from the catalogue it
 * lists all of them and the form asks which product a new one belongs to.
 *
 * A LIST, AND NOTHING ELSE
 *
 * Adding and editing happen in `MultiUnitFormDialog`, over this one. The four
 * fields used to sit in a row under the list and doubled as the editor of whichever
 * line was selected — so a pack added while a case was selected overwrote the case,
 * barcode included.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.catalogue : null

    readonly property int productId: context && context.product_id
                                     ? context.product_id : 0
    readonly property int measure: 820
    readonly property int listHeight: 380

    preferredWidth: 1120
    title: Strings.t("product.multi_units", "Multi-units")

    property var rows: []

    Component.onCompleted: reload()

    function reload() {
        rows = ctrl ? ctrl.multiUnits(productId) : []
    }

    Connections {
        target: dialog.ctrl
        ignoreUnknownSignals: true
        function onChanged() { dialog.reload() }
        function onRejected(message) {
            if (!form.visible)
                error.text = message
        }
    }

    // =====================================================================
    // THE FORM, AND THE ONE DESTRUCTIVE QUESTION
    // =====================================================================
    /* Declared here rather than routed through `workflows`: the form belongs to this
       list's task, has no permission of its own, and is handed the row by `edit(row)`
       rather than a context. DialogHost stacks either way. */
    MultiUnitFormDialog {
        id: form
        lockedProduct: dialog.productId
        onCommitted: error.text = ""
    }

    FluentDialog {
        id: confirmDelete

        property var target: null
        readonly property int measure: 440

        modal: true
        title: Strings.t("mu.delete.title", "Delete this multi-unit?")
        standardButtons: QC.Dialog.Yes | QC.Dialog.No

        onAccepted: if (dialog.ctrl && confirmDelete.target)
                        dialog.ctrl.deleteMultiUnit(confirmDelete.target.id)

        contentItem: Column {
            spacing: Tokens.spacing.sm

            Text {
                width: confirmDelete.measure
                text: Strings.t("mu.delete.body",
                                "Its barcode stops resolving at the till. The product itself is untouched.")
                wrapMode: Text.WordWrap
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                color: Fluent.textPrimary
            }

            Text {
                width: confirmDelete.measure
                text: confirmDelete.target ? confirmDelete.target.name : ""
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
                    TapHandler { onTapped: form.edit(row.modelData) }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.spacing.md
                        anchors.rightMargin: Tokens.spacing.xs
                        spacing: Tokens.spacing.md

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

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
                                Layout.fillWidth: true
                                visible: dialog.productId === 0
                                text: row.modelData.product
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.caption
                                color: Fluent.textSecondary
                                elide: Text.ElideRight
                            }
                        }

                        Text {
                            Layout.preferredWidth: 110
                            text: "\u200e× " + row.modelData.qty_text
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.body
                            color: Fluent.textSecondary
                            horizontalAlignment: Text.AlignRight
                        }

                        Text {
                            Layout.preferredWidth: 160
                            text: "\u200e" + row.modelData.price_text
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.body
                            font.weight: Font.DemiBold
                            color: Fluent.textPrimary
                            horizontalAlignment: Text.AlignRight
                        }

                        Text {
                            Layout.preferredWidth: 220
                            text: row.modelData.barcode === ""
                                  ? Strings.t("barcode.none", "no barcode")
                                  : "\u200e" + row.modelData.barcode
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.caption
                            color: row.modelData.barcode === "" ? Tokens.warning
                                                                : Fluent.textSecondary
                            horizontalAlignment: Text.AlignLeft
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
                title: Strings.t("mu.empty.title", "No multi-units")
                body: Strings.t("mu.empty.body",
                                "Add one for a pack or a case that has its own barcode.")
                actionText: Strings.t("mu.add_title", "Add multi-unit")
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
                text: Strings.t("mu.add_title", "Add multi-unit")
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

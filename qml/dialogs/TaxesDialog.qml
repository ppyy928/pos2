import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * VAT rates — the named percentages the shop charges, and which one a product falls
 * back to. Ported from pos's TaxesPage (app/pages/catalog_pages.py:334).
 *
 *   ┌ VAT rates ───────────────────────────────────────────────┐
 *   │ ⓘ VAT is switched off, so nothing here is charged.        │
 *   │ Normal 19%     19%   default    812 products     ✏  🗑   │
 *   │ Reduced 9%      9%                34 products    ✏  🗑   │
 *   │ Exempt          0%                 6 products    ✏  🗑   │
 *   ├──────────────────────────────────────────────────────────┤
 *   │ + Add rate                                       Close   │
 *   └──────────────────────────────────────────────────────────┘
 *
 * WHY A DIALOG OFF THE PRODUCTS PAGE AND NOT A PAGE OF ITS OWN
 *
 * It was a destination in the rail for a day, and that was wrong twice over: the rail
 * is for places work happens — the till, the sales, the stock — and a list of three
 * percentages that changes once a year is not one of them. And a rate belongs to the
 * catalogue: it is `products.tax_id`, chosen in the product form, so it sits behind the
 * products page with the other things a product points at (categories, units, barcode
 * labels). Same button row, same kind of dialog.
 *
 * WHAT A CHANGE DOES AND DOES NOT DO
 *
 * Every sale and purchase line stores the rate it was charged at, so editing a rate
 * changes what is sold from now on and leaves the history alone. That is also why the
 * VAT report adds up: it reads the stored line rates, not this list.
 *
 * WHAT CANNOT BE DELETED
 *
 * The default. `delete_tax` refuses it, because a product that names no rate is charged
 * it and there would be nothing to fall back to. Marking another rate as the default is
 * what frees this one.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.taxes : null
    readonly property var session: (typeof app !== "undefined" && app) ? app.session : null

    /* One right for the whole screen: pos has no `settings.manage`, and the rates a shop
       charges are a fiscal decision rather than a catalogue detail — which is also why
       `workflows` gates the key on `settings.view`. */
    readonly property bool canManage: session ? session.can("settings.view") : true

    readonly property int measure: 820
    readonly property int listHeight: 300

    preferredWidth: 1080
    title: Strings.t("taxes.title", "VAT rates")

    property var rows: []

    Component.onCompleted: reload()

    function reload() {
        if (ctrl)
            ctrl.load()
        rows = ctrl ? ctrl.rows : []
    }

    Connections {
        target: dialog.ctrl
        ignoreUnknownSignals: true
        function onRowsChanged() { dialog.rows = dialog.ctrl.rows }
        /* The form shows its own refusals while it is open; this is left with the ones
           that belong to a delete. */
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
    TaxFormDialog {
        id: form
        onCommitted: error.text = ""
    }

    /* Where do its products go? That question is the confirmation. */
    FluentDialog {
        id: confirmDelete

        property var target: null
        readonly property int measure: 480

        modal: true
        title: Strings.t("taxes.delete.title", "Delete this rate?")
        standardButtons: QC.Dialog.Yes | QC.Dialog.No

        onAccepted: if (dialog.ctrl && confirmDelete.target)
                        dialog.ctrl.remove(confirmDelete.target.id,
                                           reassign.currentIndex > 0
                                           ? reassign.model[reassign.currentIndex].id
                                           : 0)

        contentItem: ColumnLayout {
            spacing: Tokens.spacing.sm

            Text {
                Layout.preferredWidth: confirmDelete.measure
                /* The catalogue names the rate and counts its products, so this has to
                   be `tf` — read through `t` the operator saw a literal "{name}". */
                text: confirmDelete.target
                      ? Strings.tf("taxes.delete.body",
                                   "\u201c{name}\u201d is carried by {count} product(s). Choose the rate they move to before deleting it.",
                                   { name: confirmDelete.target.name,
                                     count: confirmDelete.target.products_text })
                      : ""
                wrapMode: Text.WordWrap
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                color: Fluent.textPrimary
            }

            Text {
                Layout.preferredWidth: confirmDelete.measure
                visible: confirmDelete.target !== null
                text: confirmDelete.target
                      ? confirmDelete.target.name + " \u200e("
                        + confirmDelete.target.rate_text + ")"
                      : ""
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
                                 name: Strings.t("taxes.delete.shop_default",
                                                 "The shop's default") }]
                    var skip = confirmDelete.target ? confirmDelete.target.id : 0
                    for (var i = 0; i < dialog.rows.length; i++)
                        if (dialog.rows[i].id !== skip)
                            out.push({ id: dialog.rows[i].id,
                                       name: dialog.rows[i].name + " \u200e("
                                             + dialog.rows[i].rate_text + ")" })
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

        /* VAT off is the default in this app and the common case for a corner shop.
           Every rate below is then stored and charged on nothing, which is worth saying
           once rather than leaving somebody to wonder why a receipt did not change. */
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredWidth: dialog.measure
            visible: dialog.ctrl ? !dialog.ctrl.enabled : false
            implicitHeight: offNote.implicitHeight + 2 * Tokens.spacing.sm
            radius: Tokens.radius.md
            color: Tokens.warningTint
            border.width: 1
            border.color: Qt.rgba(Tokens.warning.r, Tokens.warning.g,
                                  Tokens.warning.b, 0.28)

            RowLayout {
                id: offNote
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.spacing.md
                anchors.rightMargin: Tokens.spacing.md
                spacing: Tokens.spacing.sm

                Icon {
                    Layout.alignment: Qt.AlignTop
                    icon: "ic_fluent_info_20_regular"
                    size: Tokens.icon.sm
                    color: Tokens.warning
                }

                Text {
                    Layout.fillWidth: true
                    text: Strings.t("taxes.disabled",
                                    "VAT is switched off, so nothing here is charged. Turn it on under Settings → VAT.")
                    wrapMode: Text.WordWrap
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                    color: Fluent.textPrimary
                }
            }
        }

        /* What the shop charges when a product names nothing — the fact that makes the
           rest of the list make sense, so it is read before the list. */
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.md

            Text {
                text: Strings.t("taxes.card.mode", "Shelf prices")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.caption
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.1
                color: Fluent.textTertiary
            }

            Text {
                text: dialog.ctrl && dialog.ctrl.inclusive
                      ? Strings.t("taxes.mode.inclusive", "include VAT")
                      : Strings.t("taxes.mode.exclusive", "exclude VAT")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                font.weight: Font.DemiBold
                color: Fluent.textPrimary
            }

            Item { Layout.fillWidth: true }

            Text {
                visible: dialog.ctrl !== null
                text: dialog.ctrl
                      ? Strings.tf("taxes.fallback", "Fallback {rate}",
                                   { rate: dialog.ctrl.fallbackRate })
                      : ""
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                color: Fluent.textSecondary
            }
        }

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
                    TapHandler {
                        onTapped: if (dialog.canManage) form.edit(row.modelData)
                    }

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

                        Text {
                            Layout.preferredWidth: 120
                            text: "\u200e" + row.modelData.rate_text
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.bodyLarge
                            font.weight: Font.DemiBold
                            color: Fluent.textPrimary
                            horizontalAlignment: Text.AlignRight
                        }

                        /* The default is a badge and not a tick: it is the rate every
                           product that names nothing is charged, which is a statement
                           about the shop rather than a property of the row. */
                        Rectangle {
                            Layout.preferredWidth: 110
                            Layout.preferredHeight: 28
                            radius: Tokens.radius.sm
                            visible: row.modelData.is_default
                            color: Tokens.successTint

                            Text {
                                anchors.centerIn: parent
                                text: Strings.t("taxes.default_badge", "Default")
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.caption
                                font.weight: Font.DemiBold
                                color: Tokens.success
                            }
                        }

                        Item {
                            Layout.preferredWidth: 110
                            visible: !row.modelData.is_default
                        }

                        Text {
                            Layout.preferredWidth: 160
                            text: Strings.tf("taxes.products", "{count} products",
                                             { count: row.modelData.products_text })
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.caption
                            color: Fluent.textSecondary
                            horizontalAlignment: Text.AlignRight
                        }

                        IconButton {
                            glyph: "ic_fluent_edit_20_regular"
                            glyphSize: Tokens.icon.sm
                            enabled: dialog.canManage
                            tooltip: Strings.t("action.edit", "Edit")
                            onClicked: form.edit(row.modelData)
                        }

                        IconButton {
                            glyph: "ic_fluent_delete_20_regular"
                            glyphSize: Tokens.icon.sm
                            glyphColor: Tokens.danger
                            /* The default cannot go — disabled rather than refused,
                               with the reason in the tooltip. */
                            enabled: dialog.canManage && !row.modelData.is_default
                            tooltip: row.modelData.is_default
                                     ? Strings.t("taxes.delete.default_refused",
                                                 "The default rate cannot be deleted. Make another rate the default first.")
                                     : Strings.t("action.delete", "Delete")
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
                title: Strings.t("taxes.empty.title", "No rates yet")
                actionText: dialog.canManage
                            ? Strings.t("taxes.add_title", "Add rate") : ""
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
                text: Strings.t("taxes.add_title", "Add rate")
                highlighted: true
                enabled: dialog.canManage
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

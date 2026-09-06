import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * One VAT rate: a name, a percentage, and whether it is the one a product falls
 * back to.
 *
 *     ┌ Add rate ───────────────────────────┐
 *     │ Name *              Rate (%)        │
 *     │ [ Reduced        ]  [ 9         ]   │
 *     │ [x] The shop's default rate         │
 *     │ A product that names no rate is     │
 *     │ charged the default.                │
 *     │                    Cancel   Save    │
 *     └─────────────────────────────────────┘
 *
 * WHY A RATE IS NAMED
 *
 * A product carries the rate's id, not its percentage — so when a rate moves, the
 * whole catalogue moves with it instead of eight hundred products needing an edit.
 * The name is what the product form offers and what the VAT report groups by.
 *
 * WHY THE DEFAULT TICK CANNOT BE UNTICKED
 *
 * `save_tax` moves the default from one rate to another; it has no way to leave the
 * shop with none, because every product that names no rate is charged it. So on the
 * rate that already holds it the box is ticked and disabled, and the way to free it
 * is to tick it on another rate.
 *
 * It opens over `TaxesDialog` as a child of it rather than through `workflows`: it
 * belongs to that list's task and is handed the row by `edit(row)`. DialogHost stacks,
 * so the layering is the same either way.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.taxes : null
    readonly property var session: (typeof app !== "undefined" && app) ? app.session : null

    /* Which rate is being edited. 0 adds one. Writable, because the rates list reuses
       one instance of this dialog for every row it opens. */
    property int taxId: 0

    readonly property bool creating: taxId === 0
    readonly property bool canManage: session ? session.can("settings.view") : true
    readonly property int measure: 460

    preferredWidth: 620

    title: creating ? Strings.t("taxes.add_title", "Add rate")
                    : Strings.t("taxes.edit_title", "Edit rate")

    signal committed()

    /* Ticked here; already the shop's default over there. The second one is what
       disables the box. */
    property bool isDefault: false
    property bool wasDefault: false

    /* The list's entry point: `form.edit(row)` then it opens itself. Imperative rather
       than bound, because the first keystroke breaks a binding on `text` and the next
       row opened would show the previous rate. */
    function edit(row) {
        taxId = row && row.id ? row.id : 0
        name.text = row && row.name !== undefined ? row.name : ""
        rate.text = row ? String(row.rate) : ""
        isDefault = row ? row.is_default === true : false
        wasDefault = isDefault
        error.text = ""
        open()
        name.forceActiveFocus()
        name.selectAll()
    }

    Component.onCompleted: {
        /* Opened by the router or the shots harness instead, which carry a context and
           not a row. */
        if (context && context.tax_id) {
            if (ctrl && ctrl.total === 0)
                ctrl.load()
            taxId = context.tax_id
            fill()
        }
        name.forceActiveFocus()
    }

    function fill() {
        var row = (ctrl && taxId) ? ctrl.tax(taxId) : null
        name.text = row ? row.name : ""
        rate.text = row ? String(row.rate) : ""
        isDefault = row ? row.is_default === true : false
        wasDefault = isDefault
        error.text = ""
    }

    function save() {
        error.text = ""
        if (!ctrl)
            return
        if (name.text.trim() === "") {
            error.text = Strings.t("taxes.name.required", "A tax needs a name.")
            name.forceActiveFocus()
            return
        }
        ctrl.save({ name: name.text, rate: rate.text,
                    is_default: dialog.isDefault }, taxId)
    }

    Connections {
        target: dialog.ctrl
        ignoreUnknownSignals: true

        /* The guard matters: this instance outlives its own open, and a delete in the
           list behind it goes through the same controller. */
        function onSaved(tax) {
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

    component Field: ColumnLayout {
        id: field
        property string label: ""
        property bool required: false

        Layout.fillWidth: true
        spacing: 2

        Text {
            Layout.fillWidth: true
            text: field.required ? field.label + " *" : field.label
            elide: Text.ElideRight
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.caption
            font.weight: Font.DemiBold
            color: Fluent.textSecondary
        }
    }

    contentItem: ColumnLayout {
        spacing: Tokens.spacing.md

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: dialog.measure
            spacing: Tokens.spacing.md

            Field {
                label: Strings.t("taxes.name", "Name")
                required: true

                QC.TextField {
                    id: name
                    Layout.fillWidth: true
                    Layout.preferredHeight: Tokens.size.control
                    enabled: dialog.canManage
                    placeholderText: Strings.t("taxes.name.ph",
                                               "Normal, Reduced, Exempt…")
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.bodyLarge
                    onAccepted: dialog.save()
                }
            }

            Field {
                Layout.maximumWidth: 180
                label: Strings.t("taxes.rate", "Rate (%)")

                NumberField {
                    id: rate
                    Layout.fillWidth: true
                    Layout.preferredHeight: Tokens.size.control
                    enabled: dialog.canManage
                    placeholderText: "0"
                    onAccepted: dialog.save()
                }
            }
        }

        QC.CheckBox {
            id: defaultBox
            Layout.fillWidth: true
            /* Already the default: it can be moved to another rate, never removed
               from every rate. */
            enabled: dialog.canManage && !dialog.wasDefault
            checked: dialog.isDefault
            text: Strings.t("taxes.is_default", "The shop's default rate")
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.body
            onToggled: dialog.isDefault = checked
        }

        Text {
            Layout.fillWidth: true
            Layout.preferredWidth: dialog.measure
            text: Strings.t("taxes.hint",
                            "A product that names no rate is charged the default. Changing a rate only affects what is sold from now on — every past line keeps the rate it was sold at.")
            wrapMode: Text.WordWrap
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.caption
            color: Fluent.textTertiary
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
                enabled: dialog.canManage && name.text.trim() !== ""
                onClicked: dialog.save()
            }
        }
    }
}

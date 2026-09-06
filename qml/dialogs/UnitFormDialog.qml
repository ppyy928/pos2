import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * One unit of measure, added or renamed. Nothing else — a unit IS its name.
 *
 *     ┌ Add unit ──────────────────┐
 *     │ Unit name *                │
 *     │ [ Kilogram              ]  │
 *     │              Cancel  Save  │
 *     └────────────────────────────┘
 *
 * WHY IT IS ITS OWN DIALOG
 *
 * The units screen used to be a list with an entry row welded under it, and that
 * row was two things at once: the "add" form and the editor for whichever row was
 * selected. Nothing on screen said which — the button changed its word from Add to
 * Save and that was the whole signal. Adding a unit while a row happened to be
 * selected renamed that row instead, which is the kind of mistake a shop finds two
 * weeks later on a shelf label.
 *
 * A form that opens, says what it is doing in its title, and closes when it is done
 * cannot make that mistake.
 *
 * WHY THE SHORT CODE IS GONE
 *
 * pos stores a code beside the name (KG, PCS). It was asked for here and read in
 * exactly one place — the suffix on a product's stock cell — which now falls back
 * to the unit's name, so nothing is lost by not asking. Codes already typed are
 * kept: the bridge writes back the one it found rather than blanking it.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.catalogue : null

    /* Which unit is being renamed. 0 adds one. Writable, because the units list
       reuses one instance of this dialog for every row it opens. */
    property int unitId: 0

    readonly property bool creating: unitId === 0
    readonly property int measure: 420

    preferredWidth: 560

    title: creating ? Strings.t("units.add_title", "Add unit")
                    : Strings.t("units.edit_title", "Rename unit")

    /* Saved and closed. The list reloads on the controller's own `changed`, so this
       is only for a host that wants to react to *its* save (a fresh selection, a
       toast) rather than to any change. */
    signal committed()

    /* The host's entry point: `form.edit(row)` then it opens itself.
       Imperative rather than a binding on `text`, because the first keystroke
       breaks a binding and the next row opened would show the previous name. */
    function edit(row) {
        unitId = row && row.id ? row.id : 0
        name.text = row && row.name ? row.name : ""
        error.text = ""
        open()
        name.forceActiveFocus()
        name.selectAll()
    }

    /* Opened by the workflow router instead, with a context. */
    Component.onCompleted: {
        if (context && context.unit_id)
            unitId = context.unit_id
        if (context && context.name)
            name.text = context.name
        name.forceActiveFocus()
    }

    function save() {
        error.text = ""
        if (!ctrl)
            return
        if (name.text.trim() === "") {
            error.text = Strings.t("units.name.required", "A unit needs a name.")
            name.forceActiveFocus()
            return
        }
        ctrl.saveUnit(name.text, unitId)
    }

    Connections {
        target: dialog.ctrl
        ignoreUnknownSignals: true

        /* `changed` is the catalogue's only success signal — it does not say what
           changed, so this closes on it and lets the list underneath reload. The
           visibility guard matters: this instance outlives its own open, and the
           list deleting a row emits the same signal. */
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
                text: Strings.t("units.name", "Unit name") + " *"
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.caption
                font.weight: Font.DemiBold
                color: Fluent.textSecondary
            }

            QC.TextField {
                id: name
                Layout.fillWidth: true
                Layout.preferredHeight: Tokens.size.control
                placeholderText: Strings.t("units.name.ph",
                                           "Piece, Kilogram, Litre, Box…")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.bodyLarge
                onAccepted: dialog.save()
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

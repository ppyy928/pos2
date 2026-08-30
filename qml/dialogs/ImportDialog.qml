import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import QtQuick.Dialogs as QD
import FluentControls
import Mizan

/*
 * Import products from a CSV. Ported from pos's import page (app/pages/
 * import_products.py), which is a page there and a dialog here for one reason:
 * it is done once in a shop's life and then never again.
 *
 *   ┌──────────────────────────────────────────────────────────────┐
 *   │ [ Choose a file… ]  products.csv                             │
 *   │ Name *          [ column 1: name        ▾ ]                  │
 *   │ Barcode         [ column 2: barcode     ▾ ]                  │
 *   │ Cost            [ column 3: purchase    ▾ ]                  │
 *   │ …                                                            │
 *   │ Existing barcode:  ( ) Skip the row   (•) Update the product │
 *   │ name        barcode        purchase  sale   stock            │
 *   │ Coca-Cola   6133273401234  96,00     120,00 24               │
 *   │                                    [Cancel] [Import]         │
 *   └──────────────────────────────────────────────────────────────┘
 *
 * WHY A MAPPING STEP AT ALL
 *
 * Because the file comes from somebody else's spreadsheet. The columns are guessed
 * when their headings match the field names — a file exported from here maps
 * itself — and every one of them stays choosable, which is the difference between
 * an import that works on the shop's own file and one that only works on ours.
 *
 * The preview under the mapping is the check: five rows of what will actually be
 * read, in the columns as mapped, before anything is written.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.catalogue : null
    readonly property int measure: 820

    /*
     * Wide only once there is a mapping table to show.
     *
     * Rendering this dialog and looking at it found it opening at 1120px around two
     * controls — a "Choose CSV file..." button and the words "No file selected" — with
     * the footer button stranded in the middle of an acre of white. A dialog should be
     * the size of what it is asking, and at the start it is asking one question.
     */
    preferredWidth: dialog.preview !== null || dialog.report !== null ? 1120 : 620
    title: Strings.t("import.title", "Import products")

    property var preview: null
    property var mapping: ({})
    property string policy: "skip"
    /* Not `result`: Dialog owns a FINAL property of that name (its accept
       code) and overriding one is a load error, not a warning. */
    property var report: null

    readonly property var fields: ctrl ? ctrl.importFields : []
    readonly property bool ready: preview !== null && mapping["name"] !== undefined

    function choose(url) {
        report = null
        preview = ctrl ? ctrl.csvPreview(String(url)) : null
        if (preview) {
            /* The guess is a starting point, not a decision — it fills the
               dropdowns and the operator overrides what is wrong. */
            var next = ({})
            for (var key in preview.guess)
                next[key] = preview.guess[key]
            mapping = next
        }
    }

    function map(key, column) {
        var next = ({})
        for (var existing in mapping)
            next[existing] = mapping[existing]
        if (column < 0)
            delete next[key]
        else
            next[key] = column
        mapping = next
    }

    function columnLabel(index) {
        if (!preview || index < 0 || index >= preview.columns.length)
            return Strings.t("import.column.none", "Not in the file")
        var heading = preview.columns[index]
        return (index + 1) + ": " + (heading !== "" ? heading
                                                    : Strings.t("import.column.blank",
                                                                "unnamed"))
    }

    function run() {
        error.text = ""
        if (ctrl && preview)
            ctrl.importProducts(preview.path, mapping, policy)
    }

    Connections {
        target: dialog.ctrl
        ignoreUnknownSignals: true
        function onImported(outcome) { dialog.report = outcome }
        function onRejected(message) { error.text = message }
    }

    QD.FileDialog {
        id: chooser
        title: Strings.t("import.choose", "Choose a CSV file")
        nameFilters: [Strings.t("import.filter", "CSV files") + " (*.csv)"]
        onAccepted: dialog.choose(selectedFile)
    }

    contentItem: ColumnLayout {
        spacing: Tokens.spacing.md

        RowLayout {
            Layout.preferredWidth: dialog.measure
            Layout.fillWidth: true
            spacing: Tokens.spacing.sm

            GlyphButton {
                glyph: "ic_fluent_folder_open_20_regular"
                text: Strings.t("import.choose", "Choose a file")
                highlighted: dialog.preview === null
                onClicked: chooser.open()
            }

            Text {
                Layout.fillWidth: true
                text: dialog.preview !== null
                      ? "\u200e" + dialog.preview.path
                      : Strings.t("import.no_file", "No file chosen yet")
                elide: Text.ElideMiddle
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.caption
                color: dialog.preview !== null ? Fluent.textSecondary
                                               : Fluent.textTertiary
            }
        }

        // -----------------------------------------------------------------
        // which column is which
        // -----------------------------------------------------------------
        GridLayout {
            Layout.fillWidth: true
            visible: dialog.preview !== null
            columns: 4
            columnSpacing: Tokens.spacing.md
            rowSpacing: Tokens.spacing.xs

            Repeater {
                model: dialog.fields

                delegate: RowLayout {
                    id: field
                    required property var modelData

                    Layout.fillWidth: true
                    spacing: Tokens.spacing.xs

                    Text {
                        Layout.preferredWidth: 110
                        text: field.modelData.required
                              ? field.modelData.label + " *" : field.modelData.label
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.caption
                        font.weight: Font.DemiBold
                        color: Fluent.textSecondary
                        elide: Text.ElideRight
                    }

                    QC.ComboBox {
                        Layout.fillWidth: true
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.caption

                        /* Index 0 is "not in the file", so a column number is the
                           index minus one — which is also why a field the guess
                           did not find shows the right thing without extra
                           bookkeeping. */
                        model: {
                            var out = [Strings.t("import.column.none",
                                                 "Not in the file")]
                            if (dialog.preview)
                                for (var i = 0; i < dialog.preview.columns.length; i++)
                                    out.push(dialog.columnLabel(i))
                            return out
                        }

                        currentIndex: dialog.mapping[field.modelData.key] !== undefined
                                      ? dialog.mapping[field.modelData.key] + 1 : 0

                        onActivated: (index) => dialog.map(field.modelData.key,
                                                           index - 1)
                    }
                }
            }
        }

        // -----------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            visible: dialog.preview !== null
            spacing: Tokens.spacing.md

            Text {
                text: Strings.t("import.conflict", "A barcode already in the catalogue")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                color: Fluent.textSecondary
            }

            QC.RadioButton {
                text: Strings.t("import.conflict.skip", "Skip the row")
                checked: dialog.policy === "skip"
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                onToggled: if (checked) dialog.policy = "skip"
            }

            QC.RadioButton {
                text: Strings.t("import.conflict.update", "Update the product")
                checked: dialog.policy === "update"
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                onToggled: if (checked) dialog.policy = "update"
            }

            Item { Layout.fillWidth: true }
        }

        // -----------------------------------------------------------------
        // what will be read
        // -----------------------------------------------------------------
        Rectangle {
            Layout.fillWidth: true
            visible: dialog.preview !== null && dialog.report === null
            implicitHeight: 190
            color: Fluent.cardBackground
            radius: Tokens.radius.md
            border.width: 1
            border.color: Fluent.dividerBorder

            ListView {
                id: rows
                anchors.fill: parent
                anchors.margins: Tokens.spacing.xs
                clip: true
                model: dialog.preview ? dialog.preview.rows : null

                QC.ScrollBar.vertical: FluentScrollBar {
                    policy: QC.ScrollBar.AsNeeded
                }

                delegate: Row {
                    required property var modelData
                    spacing: Tokens.spacing.md
                    height: Tokens.size.controlSmall

                    Repeater {
                        model: dialog.fields

                        delegate: Text {
                            required property var modelData
                            width: 130
                            height: Tokens.size.controlSmall
                            verticalAlignment: Text.AlignVCenter
                            /* The cell this field is mapped to, so the preview
                               shows the mapping rather than the file. */
                            text: {
                                var column = dialog.mapping[modelData.key]
                                if (column === undefined)
                                    return "—"
                                var line = parent.parent.modelData
                                return column < line.length ? line[column] : ""
                            }
                            elide: Text.ElideRight
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.caption
                            color: Fluent.textPrimary
                        }
                    }
                }
            }
        }

        // -----------------------------------------------------------------
        // what happened
        // -----------------------------------------------------------------
        Rectangle {
            Layout.fillWidth: true
            visible: dialog.report !== null
            implicitHeight: outcome.implicitHeight + 2 * Tokens.spacing.sm
            radius: Tokens.radius.md
            color: dialog.report && dialog.report.error_count > 0
                   ? Tokens.warningTint : Tokens.successTint

            ColumnLayout {
                id: outcome
                anchors.fill: parent
                anchors.margins: Tokens.spacing.sm
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: dialog.report
                          ? Strings.tf("import.result",
                                       "{imported} added, {updated} updated, {skipped} skipped",
                                       { imported: dialog.report.imported,
                                         updated: dialog.report.updated,
                                         skipped: dialog.report.skipped })
                          : ""
                    wrapMode: Text.WordWrap
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                    font.weight: Font.DemiBold
                    color: Fluent.textPrimary
                }

                /* Rows that could not be read, with the reason as the database
                   gave it: an import that says "12 errors" and nothing else is an
                   import nobody can fix. */
                Repeater {
                    model: dialog.report ? dialog.report.errors : []

                    delegate: Text {
                        required property var modelData
                        Layout.fillWidth: true
                        text: "\u200e" + modelData.row + " — " + modelData.reason
                        wrapMode: Text.WordWrap
                        font.family: Tokens.font.family
                        font.pixelSize: Tokens.font.caption
                        color: Tokens.danger
                    }
                }
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

            Item { Layout.fillWidth: true }

            GlyphButton {
                glyph: "ic_fluent_dismiss_20_regular"
                outlined: true
                text: dialog.report !== null ? Strings.t("action.close", "Close")
                                             : Strings.t("action.cancel", "Cancel")
                onClicked: dialog.close()
            }

            GlyphButton {
                glyph: "ic_fluent_arrow_upload_20_regular"
                text: Strings.t("import.run", "Import")
                highlighted: true
                enabled: dialog.ready && dialog.report === null
                onClicked: dialog.run()
            }
        }
    }
}

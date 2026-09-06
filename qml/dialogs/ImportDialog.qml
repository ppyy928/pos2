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
 *   ┌────────────────────────────────────────────────────────────────────────┐
 *   │ [ Choose CSV file… ]  C:/Users/islem/Downloads/dz-fr.csv               │
 *   │ Match the file's columns                                               │
 *   │  FIELD             CSV COLUMN                   FIRST VALUE            │
 *   │  Name *            [ 1: list_product_name  ▾ ]  Atlas Beans Premium    │
 *   │  Barcode           [ 2: list_barcode       ▾ ]  2293118704442          │
 *   │  Purchase price    [ Not in the file       ▾ ]  —                      │
 *   │  …                                                                     │
 *   │ A barcode already in the catalogue  (•) Skip   ( ) Update              │
 *   │ ⌄ What will be read    first 6 rows                                    │
 *   │ 5 of 7 fields matched                    [Cancel] [Start Import]       │
 *   └────────────────────────────────────────────────────────────────────────┘
 *
 * WHY A MAPPING STEP AT ALL
 *
 * Because the file comes from somebody else's spreadsheet. The columns are guessed
 * when their headings match the field names — a file exported from here maps
 * itself — and every one of them stays choosable, which is the difference between
 * an import that works on the shop's own file and one that only works on ours.
 *
 * WHY THE MAPPING IS A TABLE AND NOT A GRID OF DROPDOWNS
 *
 * It was four columns of [label][dropdown] pairs, two rows deep, and the dropdowns
 * came out about 130px wide. A real file's headings are things like
 * `list_product_name`, `list_product_barcode`, `list_product_price` — so every
 * option in every list rendered as "1: list_prod…", "2: list_prod…",
 * "3: list_prod…", and the operator was asked to choose between three identical
 * strings. A popup is as wide as the control that opens it, so opening the list
 * did not help either. That is the defect this layout exists to fix:
 *
 *  - one row per field, seven rows, so the dropdown gets a real 400px and the
 *    heading is read whole — in the closed control and in the open list;
 *  - the FIRST VALUE from the chosen column, on the same row. This is the part
 *    that actually confirms a choice: `list_product_price` and
 *    `list_product_price_ttc` are one letter apart as headings and obviously
 *    different as "3390.78" and "4996.04";
 *  - a count of what is matched, and the one sentence that says what is missing,
 *    instead of a disabled Import button with no explanation.
 *
 * Field-first, not column-first (a row per column in the file, choosing what it
 * is): the operator is nearly always *verifying* a guess rather than building a
 * mapping from nothing, verification is per field, and seven rows is a dialog of
 * knowable size — a column-first table is as tall as somebody else's spreadsheet
 * is wide. It also keeps a file's one price column usable as both cost and sale
 * price, which one row per column cannot express.
 *
 * The preview of what will be read is still here, folded away behind a link. The
 * mapping table's FIRST VALUE column is the check for row one; the preview is the
 * check for the rest of the file — a second row that is a subtotal, a column that
 * stops halfway down — and it is worth a click rather than worth making the table
 * with the controls in it scroll.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.catalogue : null
    readonly property int measure: 820

    /*
     * Three states, three sizes.
     *
     * Rendering this dialog and looking at it found it opening at 1120px around two
     * controls — a "Choose CSV file..." button and the words "No file selected" — with
     * the footer button stranded in the middle of an acre of white. A dialog should be
     * the size of what it is asking. At the start it is asking one question; while
     * mapping it is showing a seven-row table over a wide dropdown, which is the
     * widest thing it ever shows; afterwards it is three lines of outcome.
     *
     * With the preview folded away the height is the content's own: the seven rows,
     * this dialog's fixed furniture, and nothing else — asking for a round number
     * instead left a strip of white above the footer on a tall screen. Opening the
     * preview asks for the rest of the screen. AppDialog clamps to the window either
     * way, and on a 1366x768 till both tables shrink toward their minimums and
     * scroll rather than pushing the Import button off the bottom edge.
     */
    preferredWidth: report !== null ? 860 : (preview !== null ? 1320 : 620)
    preferredHeight: report === null && preview !== null && previewOpen ? 1200 : 0
    title: Strings.t("import.title", "Import products")

    property var preview: null
    property var mapping: ({})
    property string policy: "skip"
    /* The preview is a second opinion, not the decision, so it is folded away.
       Both tables competing for the same height was what made the mapping table —
       the one with the controls in it — scroll four rows at a time. */
    property bool previewOpen: false
    /* Not `result`: Dialog owns a FINAL property of that name (its accept
       code) and overriding one is a load error, not a warning. */
    property var report: null

    readonly property var fields: ctrl ? ctrl.importFields : []
    readonly property bool ready: preview !== null && mapping["name"] !== undefined

    /* How many of the seven the operator has answered. Shown rather than implied:
       a file that maps six of seven is normal and fine, and the operator is the
       one who decides whether the seventh matters. */
    readonly property int matched: {
        var count = 0
        for (var key in mapping)
            if (mapping[key] !== undefined)
                count++
        return count
    }

    /* Column widths for the preview, by field. Numbers sit in narrow columns and
       a product name needs the rest, so an equal share would starve the only cell
       anybody reads. A field with no entry here gets the default — which is what a
       field added to Python's FIELDS tuple tomorrow will use until it is given a
       width of its own. */
    readonly property var previewWidths: ({
        "barcode": 180,
        "purchase_price": 120,
        "sale_price": 120,
        "stock": 90,
        "low_stock_threshold": 170,
        "category": 170
    })

    function previewWidth(key) {
        return previewWidths[key] !== undefined ? previewWidths[key] : 140
    }

    /* The mapping table's own arithmetic, in one place. A table row rather than a
       control's own height, so the dropdown inside it has a few pixels of air on
       each side instead of touching the band above and below. */
    readonly property int mapRow: Tokens.size.tableRow
    readonly property int mapNatural: Tokens.size.tableHeader
                                      + fields.length * mapRow + 2

    /* Six rows is all `csvPreview` ever returns, so the preview card has exactly
       one useful size and never grows past it. Both cards can shrink below their
       natural height, and on a short screen both do — the alternative was one of
       them taking what it wanted and the footer leaving the window. */
    readonly property int previewNatural: Tokens.size.tableHeader
                                          + 6 * Tokens.size.controlSmall + 2

    /* Figures right, words left — the rule every other table in this app follows. */
    function previewRight(key) {
        return key === "purchase_price" || key === "sale_price"
                || key === "stock" || key === "low_stock_threshold"
    }

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

    /* The first data row's value for a field, or "" when the field is unmapped.
       The one piece of evidence that a mapping is right. */
    function sample(key) {
        if (!preview || !preview.rows || preview.rows.length === 0)
            return ""
        var column = mapping[key]
        if (column === undefined)
            return ""
        var line = preview.rows[0]
        return column < line.length ? String(line[column]) : ""
    }

    /* One cell of the preview: field `key` out of data row `line`. */
    function cell(line, key) {
        var column = mapping[key]
        if (column === undefined)
            return "—"
        return column < line.length ? String(line[column]) : ""
    }

    function run() {
        error.text = ""
        if (ctrl && preview)
            ctrl.importProducts(preview.path, mapping, policy)
    }

    /* A heading, in this app's table language: small caps in secondary ink. */
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
        Text {
            Layout.fillWidth: true
            visible: dialog.preview !== null && dialog.report === null
            text: Strings.t("import.match", "Match the file's columns")
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.body
            font.weight: Font.DemiBold
            color: Fluent.textPrimary
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            /* Seven rows and a header is the whole table; it never needs to be
               taller than that, and the surplus is better spent on the preview.
               The minimum is two rows: below that the dialog is being opened on a
               screen this form does not fit on, and scrolling two rows at a time is
               still an import — a clipped footer is not. */
            Layout.preferredHeight: dialog.mapNatural
            Layout.maximumHeight: dialog.mapNatural
            Layout.minimumHeight: Tokens.size.tableHeader + 2 * dialog.mapRow
            visible: dialog.preview !== null && dialog.report === null
            color: Fluent.cardBackground
            radius: Tokens.radius.md
            border.width: 1
            border.color: Fluent.dividerBorder

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 1
                spacing: 0

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Tokens.size.tableHeader
                    color: Fluent.subtleSecondary
                    topLeftRadius: Tokens.radius.md - 1
                    topRightRadius: Tokens.radius.md - 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.spacing.md
                        anchors.rightMargin: Tokens.spacing.md
                        spacing: Tokens.spacing.md

                        Heading {
                            Layout.preferredWidth: 220
                            text: Strings.t("import.field", "Field")
                        }

                        Heading {
                            Layout.preferredWidth: 400
                            text: Strings.t("import.column", "CSV column")
                        }

                        Heading {
                            Layout.fillWidth: true
                            text: Strings.t("import.col.sample", "First value")
                        }
                    }
                }

                /* Seven rows, and a Flickable around them for the screen that
                   cannot show seven. contentHeight from the column's own implicit
                   height, so nothing here has to know the row count. */
                Flickable {
                    id: mapScroller
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: width
                    contentHeight: mapRows.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    QC.ScrollBar.vertical: FluentScrollBar {
                        policy: QC.ScrollBar.AsNeeded
                    }

                    ColumnLayout {
                        id: mapRows
                        width: mapScroller.width
                        spacing: 0

                        Repeater {
                            model: dialog.fields

                            delegate: Rectangle {
                                id: field
                                required property var modelData
                                required property int index

                                readonly property bool mapped:
                                    dialog.mapping[field.modelData.key] !== undefined

                                Layout.fillWidth: true
                                Layout.preferredHeight: dialog.mapRow
                                /* Banded, like every other table here: seven rows
                                   of three columns need a horizontal guide more
                                   than they need a border. */
                                color: field.index % 2 === 0 ? "transparent"
                                                             : Fluent.subtleSecondary

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Tokens.spacing.md
                                    anchors.rightMargin: Tokens.spacing.md
                                    spacing: Tokens.spacing.md

                                    Text {
                                        Layout.preferredWidth: 220
                                        text: field.modelData.required
                                              ? field.modelData.label + " *"
                                              : field.modelData.label
                                        elide: Text.ElideRight
                                        font.family: Tokens.font.family
                                        font.pixelSize: Tokens.font.body
                                        font.weight: field.modelData.required
                                                     ? Font.DemiBold : Font.Normal
                                        color: Fluent.textPrimary
                                    }

                                    QC.ComboBox {
                                        id: picker
                                        Layout.preferredWidth: 400
                                        Layout.preferredHeight: Tokens.size.control
                                        font.family: Tokens.font.family
                                        font.pixelSize: Tokens.font.body

                                        /* Index 0 is "not in the file", so a column
                                           number is the index minus one — which is
                                           also why a field the guess did not find
                                           shows the right thing without extra
                                           bookkeeping. */
                                        model: {
                                            var out = [Strings.t("import.column.none",
                                                                 "Not in the file")]
                                            if (dialog.preview)
                                                for (var i = 0;
                                                     i < dialog.preview.columns.length;
                                                     i++)
                                                    out.push(dialog.columnLabel(i))
                                            return out
                                        }

                                        currentIndex:
                                            dialog.mapping[field.modelData.key] !== undefined
                                            ? dialog.mapping[field.modelData.key] + 1 : 0

                                        onActivated: (index) => dialog.map(
                                            field.modelData.key, index - 1)

                                        /* And pushed again from here, because a
                                           ComboBox writes its own currentIndex the
                                           moment it is used and that drops the
                                           inline binding above for the rest of the
                                           session. This one has to keep working:
                                           choosing a second file rebuilds `mapping`
                                           under all seven rows at once, and the row
                                           the operator had already touched would
                                           otherwise keep pointing at a column from
                                           the file before it. */
                                        Binding {
                                            target: picker
                                            property: "currentIndex"
                                            value: dialog.mapping[field.modelData.key] !== undefined
                                                   ? dialog.mapping[field.modelData.key] + 1 : 0
                                            restoreMode: Binding.RestoreNone
                                        }
                                    }

                                    /* The value that proves the choice. Dimmed and
                                       an em dash when the field is not mapped, so
                                       an empty cell is never mistaken for a column
                                       that holds nothing. */
                                    Text {
                                        Layout.fillWidth: true
                                        text: field.mapped
                                              ? (dialog.sample(field.modelData.key) || "—")
                                              : "—"
                                        elide: Text.ElideRight
                                        font.family: Tokens.font.family
                                        font.pixelSize: Tokens.font.body
                                        color: field.mapped ? Fluent.textPrimary
                                                            : Fluent.textTertiary
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // -----------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            visible: dialog.preview !== null && dialog.report === null
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
        /* A disclosure, not a permanent panel. The mapping table above already
           shows the first value of every field, which is what confirms a choice;
           this shows six rows of it, which is what catches a file whose second row
           is a subtotal or whose columns stop halfway down. Worth having, not worth
           making the table with the controls in it scroll. */
        RowLayout {
            Layout.fillWidth: true
            visible: dialog.preview !== null && dialog.report === null
            spacing: Tokens.spacing.sm

            GlyphButton {
                glyph: dialog.previewOpen ? "ic_fluent_chevron_up_20_regular"
                                          : "ic_fluent_chevron_down_20_regular"
                flat: true
                text: Strings.t("import.preview", "What will be read")
                onClicked: dialog.previewOpen = !dialog.previewOpen
            }

            Text {
                text: dialog.preview
                      ? Strings.tf("import.preview.rows", "first {count} rows",
                                   { count: dialog.preview.rows.length })
                      : ""
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.caption
                color: Fluent.textTertiary
            }

            Item { Layout.fillWidth: true }
        }

        Rectangle {
            Layout.fillWidth: true
            /* Its natural size when there is room, and able to shrink when there
               is not. Both are needed: without the maximum a tall screen gives it
               a half-empty card, and without the ability to shrink a 1366x768 till
               pushed the whole footer — the Import button — off the bottom of the
               window, which is exactly the failure a Popup does not clip and so
               does not even look like an overflow. */
            Layout.fillHeight: true
            Layout.preferredHeight: dialog.previewNatural
            Layout.maximumHeight: dialog.previewNatural
            Layout.minimumHeight: Tokens.size.tableHeader + Tokens.size.controlSmall
            visible: dialog.preview !== null && dialog.report === null
                     && dialog.previewOpen
            color: Fluent.cardBackground
            radius: Tokens.radius.md
            border.width: 1
            border.color: Fluent.dividerBorder

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 1
                spacing: 0

                /* The field names as column headings. Seven columns of dashes with
                   nothing above them was the old preview, and it could not be read
                   at all — which is half of why nobody could tell it was showing
                   an unmapped file rather than an empty one. */
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Tokens.size.tableHeader
                    color: Fluent.subtleSecondary
                    topLeftRadius: Tokens.radius.md - 1
                    topRightRadius: Tokens.radius.md - 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.spacing.md
                        anchors.rightMargin: Tokens.spacing.md
                        spacing: Tokens.spacing.md

                        Repeater {
                            model: dialog.fields

                            delegate: Heading {
                                required property var modelData

                                Layout.fillWidth: modelData.key === "name"
                                Layout.preferredWidth:
                                    modelData.key === "name"
                                    ? 1 : dialog.previewWidth(modelData.key)
                                horizontalAlignment:
                                    dialog.previewRight(modelData.key)
                                    ? Text.AlignRight : Text.AlignLeft
                                text: modelData.label
                                opacity: dialog.mapping[modelData.key] !== undefined
                                         ? 1 : 0.45
                            }
                        }
                    }
                }

                ListView {
                    id: rows
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: dialog.preview ? dialog.preview.rows : null

                    QC.ScrollBar.vertical: FluentScrollBar {
                        policy: QC.ScrollBar.AsNeeded
                    }

                    delegate: Rectangle {
                        id: line
                        required property var modelData
                        required property int index

                        width: rows.width
                        height: Tokens.size.controlSmall
                        color: line.index % 2 === 0 ? "transparent"
                                                    : Fluent.subtleSecondary

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.spacing.md
                            anchors.rightMargin: Tokens.spacing.md
                            spacing: Tokens.spacing.md

                            Repeater {
                                model: dialog.fields

                                delegate: Text {
                                    required property var modelData

                                    Layout.fillWidth: modelData.key === "name"
                                    Layout.preferredWidth:
                                        modelData.key === "name"
                                        ? 1 : dialog.previewWidth(modelData.key)
                                    horizontalAlignment:
                                        dialog.previewRight(modelData.key)
                                        ? Text.AlignRight : Text.AlignLeft
                                    verticalAlignment: Text.AlignVCenter
                                    /* The cell this field is mapped to, so the
                                       preview shows the mapping rather than the
                                       file. */
                                    text: dialog.cell(line.modelData, modelData.key)
                                    elide: Text.ElideRight
                                    font.family: Tokens.font.family
                                    font.pixelSize: Tokens.font.caption
                                    color: dialog.mapping[modelData.key] !== undefined
                                           ? Fluent.textPrimary : Fluent.textTertiary
                                }
                            }
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

            /* What is left to do, beside the button it is about. A grey Import
               button is not an explanation, and "name" is the only answer this
               cannot proceed without — the same sentence Python refuses with, read
               from the same key, so the dialog and the bridge cannot disagree. */
            Text {
                Layout.fillWidth: true
                visible: dialog.preview !== null && dialog.report === null
                text: dialog.ready
                      ? Strings.tf("import.mapped", "{count} of {total} fields matched",
                                   { count: dialog.matched,
                                     total: dialog.fields.length })
                      : Strings.t("import.name.required",
                                  "Choose which column holds the product name.")
                elide: Text.ElideRight
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.caption
                font.weight: dialog.ready ? Font.Normal : Font.DemiBold
                color: dialog.ready ? Fluent.textSecondary : Tokens.warning
            }

            Item {
                Layout.fillWidth: dialog.preview === null || dialog.report !== null
            }

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

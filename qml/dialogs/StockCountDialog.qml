import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * Stocktake — walk the shelf, scan or find what is in front of you, type the number.
 *
 *   ┌─────────────────────────────────────────────────────────────────┐
 *   │ CNT-0004 · Dairy & Eggs           [ Discard ]   [ Post 12 ]     │
 *   │ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐                             │
 *   │ │ ON   │ │ LEFT │ │SHORT │ │VALUE │                             │
 *   │ │SHEET │ │  3   │ │  2   │ │-4 200│                             │
 *   │ │  12  │ │      │ │      │ │      │                             │
 *   │ └──────┘ └──────┘ └──────┘ └──────┘                             │
 *   │ [ scan or search a product ................ ] [▤]  [ Add all ]  │
 *   │   ┌───────────────────────────────────────┐                     │
 *   │   │ Yoghurt 1L    5449000996 · Dairy   24 │  <- dropdown        │
 *   │   └───────────────────────────────────────┘                     │
 *   │ Product        Book   Counted   Variance                        │
 *   │ Milk 1L         60    [ 57 ]      -3      [×]                   │
 *   │ Butter 250g     18    [ 18 ]       0      [×]                   │
 *   └─────────────────────────────────────────────────────────────────┘
 *
 * WHY THE SHEET STARTS EMPTY
 *
 * The first version of this screen listed every product in scope — three thousand
 * rows for a whole shop — and left the operator to search, type, clear the search
 * and search again for each one. That is not how a count happens. A count is walked:
 * you stand at a shelf, you find or scan what is in front of you, you type the
 * number, you move on. So the sheet is BUILT, exactly like a cart, and each line
 * freezes its book figure at the moment it is added.
 *
 * Freezing per line rather than per sheet is also the more accurate reading: the
 * figure the operator is disagreeing with is the one that was true when they looked
 * at the shelf, not the one that was true when they opened the sheet an hour ago.
 *
 * "Add all" is still here for the annual inventory of one aisle, where every product
 * listed and nothing missed is the whole point and "left to count" is the number
 * that matters. It is a deliberate press, not the default.
 *
 * WHY THERE IS NO "START A STOCKTAKE" SCREEN
 *
 * There was one, and it was a gate: the first thing an operator saw was a state
 * ("no stocktake is open") and a button, with the actual work one click behind it.
 * The sheet, the cards and the table are always on screen now, and the document
 * appears when the first line does — the first scan IS the start of a count, so
 * asking for it separately was asking twice.
 *
 * Lazily, though: creating the sheet on merely opening the screen would burn a CNT
 * number every time somebody looked, and a numbered document nobody used is a hole
 * in an audit trail.
 *
 * WHY UNCOUNTED IS NOT ZERO
 *
 * An empty box means "on the sheet, not yet counted". A typed 0 means "the shelf is
 * empty", which is the single most valuable finding a stocktake produces. Posting
 * touches only the lines with a figure in them.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.stock : null
    readonly property var products: (typeof app !== "undefined" && app) ? app.products : null
    readonly property var session: (typeof app !== "undefined" && app) ? app.session : null

    /* `revision` is read first so the binding re-evaluates when somebody logs in:
       `can()` is a slot and has no notifier of its own. */
    readonly property bool canManage: session && session.revision >= 0
                                      && session.can("products.manage")

    preferredWidth: 1240
    preferredHeight: 900

    /* The number appears when the sheet does. Before that this is the screen for
       counting, not a document with a name. */
    title: open_ ? Strings.tf("count.sheet", "Stocktake {number}",
                              { number: sheet.number })
                 : Strings.t("count.title", "Stocktake")

    readonly property var sheet: ctrl && ctrl.hasSheet ? ctrl.sheet : ({})
    readonly property bool open_: ctrl ? ctrl.hasSheet : false
    readonly property var summary: sheet.summary !== undefined ? sheet.summary : ({})

    /*
     * The sheet, newest line first.
     *
     * pos hands the lines over in the order they were added, and the row an operator
     * wants is the one they just scanned — so the list is reversed here. It used to
     * be done with the ListView's `verticalLayoutDirection: BottomToTop`, which put
     * the newest line at the *bottom* of the frame: with one product on the sheet,
     * the header sat at the top and the only row on screen sat 300px below it, with
     * nothing in between. Reversing the model instead keeps the first line directly
     * under the header, where a list starts.
     */
    readonly property var lines: {
        var src = sheet.items !== undefined ? sheet.items : []
        var out = []
        for (var i = src.length - 1; i >= 0; i--)
            out.push(src[i])
        return out
    }

    property string notice: ""

    /* What the finder is showing. Held here because the caller owns the data: the
       component owns only the interaction. */
    property var matches: []
    property var catalogue: []

    Component.onCompleted: {
        if (products && products.loadCategories)
            products.loadCategories()
        if (ctrl)
            ctrl.loadSheet()
    }

    function count(key) {
        var value = summary[key]
        return value === undefined ? "0" : String(value)
    }

    /* A code first, then the visible matches. A scanner sends a full barcode and a
       Return; a person types three letters and expects the one row under the field.
       Trying the code first is what makes both work through one box. */
    function submit(text) {
        if (!ctrl || text.trim() === "")
            return
        var hit = ctrl.addByCode(text)
        if (hit) {
            notice = Strings.tf("count.added", "{name} added",
                                { name: hit.name })
            finder.clear()
            return
        }
        if (matches.length === 1) {
            finder.take(matches[0])
            return
        }
        if (matches.length === 0)
            notice = Strings.t("count.no_match", "Nothing matched that.")
    }

    Connections {
        target: dialog.ctrl
        ignoreUnknownSignals: true
        function onPosted(result) {
            dialog.notice = Strings.tf("count.posted",
                                       "Posted — {count} lines adjusted",
                                       { count: result.changed })
        }
        function onRejected(message) { error.text = message }
    }

    contentItem: ColumnLayout {
        spacing: Tokens.spacing.md

        // -----------------------------------------------------------------
        // THE FOUR FIGURES — always, at zero before the first line
        // -----------------------------------------------------------------
        CardRow {
            Layout.fillWidth: true
            minCardWidth: 220

            KpiCard {
                chipSize: 44
                minHeight: 100
                floorWidth: 220
                label: Strings.t("count.card.on_sheet", "On the sheet")
                value: dialog.count("lines")
                glyph: "ic_fluent_list_20_regular"
                tone: "info"
            }

            KpiCard {
                chipSize: 44
                minHeight: 100
                floorWidth: 220
                label: Strings.t("count.card.remaining", "Left to count")
                value: dialog.count("remaining")
                glyph: "ic_fluent_clipboard_task_20_regular"
                tone: "warning"
                valueTone: dialog.summary.remaining > 0 ? "warning" : "success"
            }

            KpiCard {
                chipSize: 44
                minHeight: 100
                floorWidth: 220
                label: Strings.t("count.card.shortage", "Short")
                value: dialog.count("shortage")
                glyph: "ic_fluent_arrow_trending_down_20_regular"
                tone: "danger"
                valueTone: dialog.summary.shortage > 0 ? "danger" : ""
            }

            KpiCard {
                chipSize: 44
                minHeight: 100
                floorWidth: 220
                label: Strings.t("count.card.value", "Variance value")
                value: dialog.summary.variance_value_text !== undefined
                       ? "\u200e" + dialog.summary.variance_value_text : "—"
                glyph: "ic_fluent_money_20_regular"
                tone: "primary"
                valueTone: dialog.summary.variance_value < 0 ? "danger"
                         : dialog.summary.variance_value > 0 ? "success" : ""
            }
        }

        // -- how a line gets onto the sheet
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.sm

            ProductFinder {
                id: finder
                Layout.fillWidth: true
                enabled: dialog.canManage
                placeholder: Strings.t("count.finder.ph",
                                       "Scan or search a product to add it")
                results: dialog.matches
                all: dialog.catalogue

                /* No debounce: a scanner's burst must not wait 300ms, and this
                   query is a single indexed LIKE on a local file. */
                onQueried: (text) => {
                    dialog.matches = (text.trim() === "" || !dialog.ctrl)
                                     ? [] : dialog.ctrl.find(text, 12)
                }
                onBrowsed: {
                    /* The whole catalogue, not a capped find: the browse list is
                       the shared select-product table, and a ceiling on it is
                       the row the operator wanted made invisible. */
                    if (dialog.ctrl)
                        dialog.catalogue = dialog.ctrl.catalogue()
                }
                onAccepted: (text) => dialog.submit(text)
                onPicked: (product) => {
                    if (dialog.ctrl) {
                        dialog.ctrl.addLine(product.id)
                        dialog.notice = Strings.tf("count.added", "{name} added",
                                                   { name: product.name })
                    }
                }
            }

            /* The scope. Only decides what "Add all" covers and what the browse list
               is filtered to, so it stays live until the sheet exists and then locks
               — a sheet's scope is part of what it recorded. */
            QC.ComboBox {
                Layout.preferredWidth: 240
                Layout.preferredHeight: Tokens.size.control
                enabled: dialog.canManage && !dialog.open_
                textRole: "name"
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                model: {
                    var out = [{ id: 0,
                                 name: Strings.t("products.filter.all_categories",
                                                 "All categories") }]
                    var src = dialog.products ? dialog.products.categories : null
                    if (src)
                        for (var i = 0; i < src.length; i++)
                            out.push(src[i])
                    return out
                }
                onActivated: (index) => {
                    if (dialog.ctrl)
                        dialog.ctrl.scope = model[index].id
                }
            }

            /* The exhaustive case, one press away and never the default. */
            GlyphButton {
                glyph: "ic_fluent_add_square_multiple_20_regular"
                text: Strings.t("count.add_all", "Add all")
                enabled: dialog.canManage
                onClicked: if (dialog.ctrl) dialog.ctrl.fillSheet()
            }
        }

        /*
         * The sheet, as a list rather than a DataTable: every row carries an editable
         * box and a remove button, and DataTable renders text cells. The header below
         * repeats DataTable's metrics so the two read as the same furniture.
         */
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Tokens.radius.md
            color: Fluent.subtleSecondary
            border.width: 1
            border.color: Fluent.dividerBorder
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 1
                spacing: 0

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Tokens.size.control
                    color: Fluent.subtleTertiary

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.spacing.md
                        anchors.rightMargin: Tokens.spacing.md
                        spacing: Tokens.spacing.sm

                        Text {
                            Layout.fillWidth: true
                            text: Strings.t("products.col.name", "Product")
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.caption
                            font.weight: Font.DemiBold
                            color: Fluent.textSecondary
                        }

                        Text {
                            Layout.preferredWidth: 110
                            horizontalAlignment: Text.AlignRight
                            text: Strings.t("count.col.expected", "Book")
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.caption
                            font.weight: Font.DemiBold
                            color: Fluent.textSecondary
                        }

                        Text {
                            Layout.preferredWidth: 140
                            horizontalAlignment: Text.AlignHCenter
                            text: Strings.t("count.col.counted", "Counted")
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.caption
                            font.weight: Font.DemiBold
                            color: Fluent.textSecondary
                        }

                        Text {
                            Layout.preferredWidth: 140
                            horizontalAlignment: Text.AlignRight
                            text: Strings.t("count.col.variance", "Variance")
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.caption
                            font.weight: Font.DemiBold
                            color: Fluent.textSecondary
                        }

                        Item { Layout.preferredWidth: Tokens.size.controlSmall }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: dialog.lines.length === 0
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.WordWrap
                    text: Strings.t("count.sheet.empty",
                                    "Nothing on the sheet yet. Scan a product, search for one, or use Add all.")
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                    color: Fluent.textTertiary
                }

                ListView {
                    id: sheetList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: dialog.lines.length > 0
                    clip: true
                    /* Newest first — see `lines` above, which is where the order is
                       decided. The list itself fills from the header down. */
                    model: dialog.lines
                    cacheBuffer: 400

                    QC.ScrollBar.vertical: FluentScrollBar {
                        policy: QC.ScrollBar.AsNeeded
                    }

                    delegate: Rectangle {
                        id: line
                        required property var modelData
                        required property int index

                        width: sheetList.width
                        height: Tokens.size.control + Tokens.spacing.sm
                        color: index % 2 === 0 ? "transparent" : Fluent.subtleTertiary

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.spacing.md
                            anchors.rightMargin: Tokens.spacing.md
                            spacing: Tokens.spacing.sm

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                Text {
                                    Layout.fillWidth: true
                                    text: line.modelData.product
                                    elide: Text.ElideRight
                                    font.family: Tokens.font.family
                                    font.pixelSize: Tokens.font.body
                                    color: Fluent.textPrimary
                                }

                                Text {
                                    visible: text !== ""
                                    text: line.modelData.barcode
                                          ? "\u200e" + line.modelData.barcode : ""
                                    font.family: Tokens.font.family
                                    font.pixelSize: Tokens.font.caption
                                    color: Fluent.textTertiary
                                }
                            }

                            Text {
                                Layout.preferredWidth: 110
                                horizontalAlignment: Text.AlignRight
                                text: "\u200e" + line.modelData.expected_text
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.body
                                color: Fluent.textSecondary
                            }

                            NumberField {
                                Layout.preferredWidth: 140
                                Layout.preferredHeight: Tokens.size.controlSmall
                                enabled: dialog.canManage
                                text: line.modelData.counted_text
                                horizontalAlignment: TextInput.AlignHCenter
                                placeholderText: "—"
                                /* On editing finished, not per keystroke: a
                                   half-typed "1" of "12" would post a variance of
                                   -11 and turn the row red under the operator's
                                   fingers. */
                                onEditingFinished: {
                                    if (text !== line.modelData.counted_text
                                            && dialog.ctrl)
                                        dialog.ctrl.setCounted(
                                            line.modelData.product_id, text)
                                }
                                /* Return goes back to the finder: the loop is
                                   scan, type, Return, scan — never the mouse. */
                                onAccepted: finder.focusSearch()
                            }

                            Text {
                                Layout.preferredWidth: 140
                                horizontalAlignment: Text.AlignRight
                                text: line.modelData.counted_yet
                                      ? "\u200e" + line.modelData.variance_text
                                      : line.modelData.variance_text
                                font.family: Tokens.font.family
                                font.pixelSize: Tokens.font.body
                                font.weight: line.modelData.tone !== ""
                                             ? Font.DemiBold : Font.Normal
                                color: line.modelData.tone !== ""
                                       ? Tokens.toneInk(line.modelData.tone)
                                       : Fluent.textTertiary
                            }

                            IconButton {
                                glyph: "ic_fluent_dismiss_20_regular"
                                glyphSize: Tokens.icon.sm
                                glyphColor: Tokens.danger
                                enabled: dialog.canManage
                                tooltip: Strings.t("count.remove", "Take off the sheet")
                                onClicked: if (dialog.ctrl)
                                               dialog.ctrl.removeLine(
                                                   line.modelData.product_id)
                            }
                        }
                    }
                }
            }
        }

        // -----------------------------------------------------------------
        // FEEDBACK AND COMMIT
        // -----------------------------------------------------------------
        Text {
            id: error
            Layout.fillWidth: true
            visible: text !== ""
            wrapMode: Text.WordWrap
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.caption
            color: Tokens.danger
        }

        Text {
            Layout.fillWidth: true
            visible: dialog.notice !== "" && error.text === ""
            text: dialog.notice
            wrapMode: Text.WordWrap
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.caption
            font.weight: Font.DemiBold
            color: Tokens.success
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.sm

            Item { Layout.fillWidth: true }

            GlyphButton {
                /* Nothing to discard until a sheet exists. */
                visible: dialog.open_
                glyph: "ic_fluent_delete_20_regular"
                text: Strings.t("count.cancel", "Discard")
                enabled: dialog.canManage
                onClicked: confirmDiscard.open()
            }

            GlyphButton {
                glyph: "ic_fluent_dismiss_20_regular"
                outlined: true
                text: Strings.t("action.close", "Close")
                onClicked: dialog.close()
            }

            GlyphButton {
                /* Always present, and disabled until something has been counted:
                   a button that appears and disappears is a button an operator
                   has to look for. */
                glyph: "ic_fluent_checkmark_20_regular"
                text: Strings.tf("count.post_n", "Post {count}",
                                 { count: dialog.count("counted") })
                highlighted: true
                enabled: dialog.canManage && dialog.summary.counted > 0
                onClicked: confirmPost.open()
            }
        }
    }

    /* `measure` is a stated constant, not `parent.width`: FluentDialog sizes itself
       from its content, so a wrapping Text that takes its width from the dialog
       closes a binding loop. */
    FluentDialog {
        id: confirmPost
        readonly property int measure: 440
        modal: true
        title: Strings.t("count.post.title", "Post this stocktake?")
        standardButtons: QC.Dialog.Yes | QC.Dialog.No
        onAccepted: if (dialog.ctrl) dialog.ctrl.postCount()

        contentItem: Text {
            width: confirmPost.measure
            wrapMode: Text.WordWrap
            text: Strings.t("count.post.body",
                            "Counted lines become the new stock. Uncounted lines are left alone.")
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.body
            color: Fluent.textSecondary
        }
    }

    FluentDialog {
        id: confirmDiscard
        readonly property int measure: 440
        modal: true
        title: Strings.t("count.cancel.title", "Discard this stocktake?")
        standardButtons: QC.Dialog.Yes | QC.Dialog.No
        onAccepted: if (dialog.ctrl) dialog.ctrl.cancelCount()

        contentItem: Text {
            width: confirmDiscard.measure
            wrapMode: Text.WordWrap
            text: Strings.t("count.cancel.body",
                            "Nothing was applied, so nothing is reversed — but the counts already typed are lost.")
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.body
            color: Fluent.textSecondary
        }
    }
}

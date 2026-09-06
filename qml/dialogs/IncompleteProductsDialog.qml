import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * The waiting room: imported rows that are not products yet.
 *
 *   Incomplete products                              98,431 waiting
 *   ┌───────────────────────────────────────────────────────────────────────┐
 *   │ 🔍 Search these by name or barcode        [ All imports ▾ ]           │
 *   ├──────────────────────┬───────────────┬────────┬────────┬─────────────┤
 *   │ NAME                 │ BARCODE       │ COST   │ SELL   │ MISSING     │
 *   │ Coca-Cola 1.5L       │ 5449000996    │   —    │   —    │ ⟨2 prices⟩ ✏️│
 *   │ Fanta Orange 1L      │ 6130003015160 │ 120.00 │   —    │ ⟨price⟩    ✏️│
 *   └──────────────────────┴───────────────┴────────┴────────┴─────────────┘
 *   ⓘ You do not have to finish these now. Scan one and the form opens filled in.
 *   [ Discard all ]                    1–100 of 98,431   ‹ › ››   [ Close ]
 *
 * WHY THIS IS A SEPARATE SCREEN AND NOT A FILTER ON THE PRODUCTS TABLE
 *
 * The obvious design was a dropdown on the products page — "All / Complete /
 * Incomplete" — and it is wrong for this shop at this scale. A national barcode
 * catalogue is a hundred thousand rows against a catalogue of two thousand, so:
 *
 *   * every page of the products table would be somebody else's catalogue, and
 *     the shop's own products would be findable only by search;
 *   * "Products 102,431" is a lie about a shop that stocks two thousand;
 *   * the till's tile query, the barcode-label sheet, the CSV export and the
 *     stock valuation would each need a predicate adding, and the one that was
 *     forgotten would be the one that sold a 0.00 product.
 *
 * They are in a table of their own (`product_drafts`), so none of those queries
 * can see them and there is no predicate to forget. What the products page shows
 * is the NUMBER — one card, only when it is non-zero — and this is what the number
 * opens.
 *
 * WHY IT IS PAGED AND SEARCHED AND NOTHING ELSE
 *
 * Nobody reads a hundred thousand rows. There are exactly two useful questions
 * here — "is this barcode in there?" and "what did that import bring?" — and the
 * search box and the source picker are those two. There is no sorting, because
 * every column is either the same for the whole page (the gaps) or meaningless to
 * order by (a code); ordering is by name, so the page is stable between visits.
 *
 * WHY THE REAL ENTRY POINT IS NOT THIS SCREEN
 *
 * It is the scanner. A shop does not work through a queue of ninety-eight thousand
 * rows; it picks up a bottle, scans it, and the product form opens with the name,
 * the barcode, the category and the unit already in it — two prices to type. That
 * path is in ProductsPage and PosPage, and it is the reason the rows are kept at
 * all. This screen exists for the two things that path cannot do: look one up
 * without having it in your hand, and throw away a file that was the wrong file.
 *
 * WHY "COMPLETE IT" OPENS THE PRODUCT FORM RATHER THAN EDITING IN PLACE
 *
 * Two prices typed into the row would have been fewer clicks, and it would have
 * been a second way to create a product — one that silently could not carry a VAT
 * rate, a photo, wholesale prices or a pack. There is one way a product is written
 * in this app and it is the form. See `db.promote_draft` for the same decision on
 * the other side of the boundary.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.drafts : null
    readonly property var session: (typeof app !== "undefined" && app) ? app.session : null
    readonly property var workflows: (typeof app !== "undefined" && app)
                                     ? app.workflows : null

    /* Discarding a hundred thousand rows, and completing one into a product, are
       both catalogue writes. Looking is `products.view`, which the workflow key
       already required to open this at all. */
    readonly property bool canManage: session && session.revision >= 0
                                      && session.can("products.manage")

    preferredWidth: 1280
    preferredHeight: 900
    breathing: 2 * Tokens.spacing.lg

    title: Strings.t("drafts.title", "Incomplete products")

    // =====================================================================
    // QUERY
    // =====================================================================
    property string search: ""
    property string source: ""
    property int page: 1
    readonly property int pageSize: 100

    readonly property var rows: ctrl ? ctrl.rows : []
    readonly property int total: ctrl ? ctrl.total : 0
    readonly property int waiting: ctrl ? ctrl.waiting : 0
    readonly property bool busy: ctrl ? ctrl.busy : false
    readonly property string errorText: ctrl ? ctrl.error : ""

    /* Which import to look at. Built from the controller's own grouping, so a
       source that no longer has rows in it disappears from the list by itself. */
    readonly property var sourceModel: {
        var out = [{ source: "", label: Strings.t("drafts.card", "Incomplete")
                                 + "  (" + dialog.waiting + ")" }]
        var src = ctrl ? ctrl.sources : []
        for (var i = 0; i < src.length; i++)
            out.push({ source: src[i].source, label: src[i].label })
        return out
    }

    Component.onCompleted: {
        if (context && context.search)
            search = String(context.search)
        reload()
    }

    function reload() {
        if (ctrl)
            ctrl.load(search, page, pageSize, source)
    }

    function refilter() {
        page = 1
        reload()
    }

    function rowAt(index) {
        return (index >= 0 && index < rows.length) ? rows[index] : null
    }

    /* Finish one row. The product form does the writing and clears the row after
       it — this only routes, which is why it closes nothing: DialogHost stacks, so
       the form opens over this list and the list is still here underneath when it
       is done. */
    function complete(row) {
        if (!row)
            return
        if (workflows)
            workflows.open("product_form", { draft_id: row.id })
    }

    Connections {
        target: dialog.ctrl
        ignoreUnknownSignals: true
        /* A row that became a product, or one that was discarded. The count in the
           header and the page both come off the controller, so re-reading is all
           this has to do. */
        function onInvalidated() { dialog.reload() }
    }

    /* The form that just promoted a row is a sibling dialog, not a child of this
       one, so its outcome arrives through the products controller. Watched here so
       the list loses the row the moment it stops being a draft, rather than the
       next time somebody reopens this. */
    Connections {
        target: (typeof app !== "undefined" && app) ? app.products : null
        ignoreUnknownSignals: true
        function onSaved(_product) { dialog.reload() }
    }

    // =====================================================================
    // TABLE
    // =====================================================================
    readonly property var columns: [
        {
            key: "name",
            header: Strings.t("products.col.name", "Name"),
            stretch: true
        },
        {
            key: "barcode",
            header: Strings.t("products.col.barcode", "Barcode"),
            width: 240,
            ltr: true
        },
        {
            key: "category",
            header: Strings.t("products.col.category", "Category"),
            width: 170
        },
        {
            key: "purchase_price_text",
            header: Strings.t("products.col.purchase_price", "Cost"),
            numeric: true,
            width: 150,
            /* An em dash in this column IS the gap, so it carries the tone rather
               than the badge repeating it. A figure that is there reads neutral. */
            tone: function (r) {
                return r && r.gaps && r.gaps.indexOf("purchase_price") >= 0
                       ? "warning" : ""
            }
        },
        {
            key: "sale_price_text",
            header: Strings.t("products.col.sale_price", "Sale price"),
            numeric: true,
            width: 150,
            tone: function (r) {
                return r && r.gaps && r.gaps.indexOf("sale_price") >= 0
                       ? "warning" : ""
            }
        },
        {
            key: "gaps_text",
            header: Strings.t("drafts.missing", "Missing"),
            width: 260,
            badge: true,
            tone: function (_r) { return "warning" }
        },
        {
            key: "source",
            header: Strings.t("drafts.col.source", "From"),
            width: 200
        },
        {
            key: "actions",
            actions: dialog.rowActions
        }
    ]

    readonly property var rowActions: [
        /* Not `edit`: RowActions draws a pencil for that id and the act is not
           editing a product, it is finishing one. A check reads as "this is done". */
        { id: "complete", enabled: dialog.canManage },
        { id: "delete", enabled: dialog.canManage }
    ]

    contentItem: ColumnLayout {
        spacing: Tokens.spacing.md

        // -----------------------------------------------------------------
        // WHAT THIS IS
        // -----------------------------------------------------------------
        /* A sentence, once, at the top. The rows themselves cannot explain why
           they are not products, and an operator who has just clicked a card
           marked "98,431" is owed the explanation before the table. */
        Text {
            Layout.fillWidth: true
            text: Strings.t("drafts.subtitle",
                            "Imported rows that cannot be sold yet. Fill in what is missing and each one becomes a product.")
            wrapMode: Text.WordWrap
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.body
            color: Fluent.textSecondary
        }

        // -----------------------------------------------------------------
        // FINDING ONE
        // -----------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.sm

            QC.TextField {
                id: searchField
                Layout.fillWidth: true
                Layout.preferredHeight: Tokens.size.control
                placeholderText: Strings.t("drafts.search.ph",
                                           "Search these by name or barcode")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                /* Enter, not per keystroke, and no debounce timer: a search here
                   is a COUNT plus a LIMIT over a hundred thousand rows, and firing
                   it on the fourth character of a thirteen-digit barcode is four
                   scans of the table for an answer nobody wanted yet. The till's
                   own search debounces because its catalogue is small. */
                onAccepted: {
                    dialog.search = text.trim()
                    dialog.refilter()
                }
            }

            IconButton {
                glyph: "ic_fluent_dismiss_20_regular"
                glyphSize: Tokens.icon.sm
                visible: dialog.search !== ""
                tooltip: Strings.t("action.clear", "Clear")
                onClicked: {
                    searchField.text = ""
                    dialog.search = ""
                    dialog.refilter()
                }
            }

            /* Which file these came from. Only offered when there is more than
               one, because a picker with a single choice is a control that cannot
               do anything. */
            QC.ComboBox {
                Layout.preferredWidth: 300
                Layout.preferredHeight: Tokens.size.control
                visible: dialog.sourceModel.length > 2
                textRole: "label"
                model: dialog.sourceModel
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                onActivated: (index) => {
                    dialog.source = dialog.sourceModel[index].source
                    dialog.refilter()
                }
            }

            Text {
                text: Strings.tf("drafts.count_n", "{count} waiting",
                                 { count: dialog.waiting })
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.caption
                font.features: Tokens.figures
                color: Fluent.textTertiary
            }
        }

        // -----------------------------------------------------------------
        // THE ROWS
        // -----------------------------------------------------------------
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            DataTable {
                id: table
                anchors.fill: parent
                columns: dialog.columns
                model: dialog.rows
                visible: !dialog.showState

                onRowActivated: (row) => dialog.complete(dialog.rowAt(row))

                onActionTriggered: (row, action) => {
                    var data = dialog.rowAt(row)
                    if (!data)
                        return
                    if (action === "complete") {
                        dialog.complete(data)
                    } else if (action === "delete") {
                        confirmDiscard.target = data
                        confirmDiscard.open()
                    }
                }
            }

            /* Three states, one surface: an error, an empty table, and an empty
               SEARCH — which is a different sentence, because the rows are there
               and the query is what found nothing. */
            StateView {
                anchors.fill: parent
                visible: dialog.showState
                variant: dialog.stateVariant
                title: dialog.stateVariant === "error"
                       ? Strings.t("state.error", "Something went wrong")
                       : dialog.stateVariant === "no_results"
                         ? Strings.t("drafts.no_results", "No match here")
                         : Strings.t("drafts.empty", "Nothing is waiting")
                body: dialog.stateVariant === "error"
                      ? dialog.errorText
                      : dialog.stateVariant === "no_results"
                        ? Strings.t("state.no_results.body",
                                    "Try a different search.")
                        : Strings.t("drafts.empty.body",
                                    "Every imported product has what it needs. Incomplete rows appear here after an import.")
            }

            LoadingOverlay {
                anchors.fill: parent
                visible: dialog.busy && dialog.rows.length === 0
            }
        }

        readonly property bool showState: !dialog.busy
                                          && (dialog.errorText !== ""
                                              || dialog.total === 0)
        readonly property string stateVariant: dialog.errorText !== "" ? "error"
                                             : dialog.search !== "" ? "no_results"
                                             : "empty"

        // -----------------------------------------------------------------
        // WHAT TO DO ABOUT THEM
        // -----------------------------------------------------------------
        /* The thing an operator most needs told, and the reason none of this is
           urgent: the queue empties itself as the shop sells. */
        Text {
            Layout.fillWidth: true
            visible: dialog.total > 0
            text: "\u24d8  " + Strings.t("drafts.hint",
                                         "You do not have to finish these now. Scan one of their barcodes and the form opens already filled in.")
            wrapMode: Text.WordWrap
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.caption
            color: Tokens.info
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Fluent.dividerBorder
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.sm

            /* Undoing an import. Dangerous-looking and genuinely not: these are
               not products, so nothing sold, counted, printed or reported refers
               to them, and the file can be loaded again. The confirmation says
               exactly that, because a shop that cannot tell will not press it. */
            GlyphButton {
                glyph: "ic_fluent_delete_20_regular"
                text: dialog.source !== ""
                      ? Strings.t("drafts.clear", "Discard all") + " \u2014 "
                        + dialog.source
                      : Strings.t("drafts.clear", "Discard all")
                outlined: true
                visible: dialog.canManage && dialog.waiting > 0
                onClicked: confirmClear.open()
            }

            PaginationBar {
                Layout.fillWidth: true
                page: dialog.page
                pageSize: dialog.pageSize
                total: dialog.total
                onPageRequested: (value) => {
                    dialog.page = value
                    dialog.reload()
                }
            }

            GlyphButton {
                glyph: "ic_fluent_dismiss_20_regular"
                outlined: true
                text: Strings.t("action.close", "Close")
                onClicked: dialog.close()
            }
        }
    }

    // =====================================================================
    // THE TWO REFUSALS
    // =====================================================================
    ConfirmDialog {
        id: confirmDiscard
        property var target: null

        title: Strings.t("drafts.discard.confirm", "Discard this row?")
        body: Strings.t("drafts.clear.body",
                        "They are not products, so nothing you have sold is affected. The import file can be loaded again.")
        confirmText: Strings.t("action.delete", "Delete")
        facts: confirmDiscard.target
               ? [{ label: Strings.t("products.col.name", "Name"),
                    value: confirmDiscard.target.name || "—" },
                  { label: Strings.t("products.col.barcode", "Barcode"),
                    value: "\u200e" + (confirmDiscard.target.barcode || "—") }]
               : []

        onConfirmed: {
            if (dialog.ctrl && confirmDiscard.target)
                dialog.ctrl.discard(confirmDiscard.target.id)
        }
    }

    ConfirmDialog {
        id: confirmClear

        title: Strings.tf("drafts.clear.confirm",
                          "Discard {count} incomplete rows?",
                          { count: dialog.source !== "" ? dialog.total
                                                        : dialog.waiting })
        body: Strings.t("drafts.clear.body",
                        "They are not products, so nothing you have sold is affected. The import file can be loaded again.")
        confirmText: Strings.t("drafts.clear", "Discard all")
        facts: dialog.source !== ""
               ? [{ label: Strings.t("drafts.col.source", "From"),
                    value: dialog.source }]
               : []

        onConfirmed: {
            if (dialog.ctrl)
                dialog.ctrl.clearAll(dialog.source)
        }
    }
}

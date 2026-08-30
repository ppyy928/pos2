import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * The stock ledger — every movement, and the document behind it.
 *
 *   Product          Movement    Change   Balance   Document   When
 *   Yoghurt 1L       Sale          -4       304     TRX-0183   14:02
 *   Yoghurt 1L       Delivery     +20       308     PIN-0167   11:30
 *   Yoghurt 1L       Stocktake     -3        56     CNT-0001   09:14
 *
 * WHY THIS SCREEN EXISTS
 *
 * Stock used to be a single number that six functions wrote to and nothing
 * recorded — `adjust_stock` even took a reason and threw it into a log line. So the
 * one question a stock figure ever provokes, "why is it this and not that", had no
 * answer anywhere in the product.
 *
 * `Balance` is the level the movement produced, stored at the time rather than
 * recomputed now. Read down the column and the exact point where the book and the
 * shelf parted company is visible; recomputing it from today's stock would only
 * ever show that they agree.
 *
 * Opened for one product from its record, or for the whole shop from the products
 * page — same screen, one filter apart.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.stock : null

    readonly property int productId: context && context.product_id
                                     ? context.product_id : 0
    readonly property string productName: context && context.product_name
                                          ? context.product_name : ""

    preferredWidth: 1280
    preferredHeight: 860

    title: shownName !== ""
           ? Strings.tf("stock.ledger.of", "Stock ledger — {product}",
                        { product: shownName })
           : Strings.t("stock.ledger", "Stock ledger")

    property string kind: ""
    property int page: 1
    readonly property int pageSize: 60

    /* Which product the ledger is filtered to, and its name for the title. Starts at
       whatever the caller opened it on — a row menu passes a product — and is changed
       by the finder without reopening the dialog. */
    property int shownId: productId
    property string shownName: productName

    /* The finder's data. The caller owns it; the component owns the interaction. */
    property var matches: []
    property var catalogue: []

    readonly property var rows: ctrl ? ctrl.movements : []
    readonly property int total: ctrl ? ctrl.movementsTotal : 0

    Component.onCompleted: reload()

    function reload() {
        if (ctrl)
            ctrl.load(shownId, kind, page, pageSize)
    }

    function show(id, name) {
        shownId = id
        shownName = name
        page = 1
        reload()
    }

    /* A code first, then the one visible match — the same rule the stocktake uses,
       so one box serves a scanner and a pair of typed letters. */
    function submit(text) {
        if (!ctrl || text.trim() === "")
            return
        var hits = ctrl.find(text, 2)
        if (hits.length === 1)
            finder.take(hits[0])
    }

    /* The kinds, as a filter. Built from the same list the bridge translates, so a
       kind added in the data layer appears here without a second table. */
    readonly property var kinds: [
        { key: "", label: Strings.t("stock.kind.all", "All movements") },
        { key: "sale", label: Strings.t("stock.kind.sale", "Sale") },
        { key: "purchase", label: Strings.t("stock.kind.purchase", "Delivery") },
        { key: "return", label: Strings.t("stock.kind.return", "Return") },
        { key: "adjust", label: Strings.t("stock.kind.adjust", "Adjustment") },
        { key: "count", label: Strings.t("stock.kind.count", "Stocktake") },
        { key: "expiry", label: Strings.t("stock.kind.expiry", "Expired") }
    ]

    readonly property var columns: [
        {
            key: "when",
            header: Strings.t("sales.col.time", "Date"),
            width: 190,
            ltr: true
        },
        {
            key: "product",
            header: Strings.t("products.col.name", "Product"),
            stretch: true,
            /* Hidden when the ledger is filtered to one product: repeating the
               name on sixty rows is sixty times the same fact. */
            hidden: dialog.shownId > 0
        },
        {
            key: "kind_text",
            header: Strings.t("stock.col.kind", "Movement"),
            width: 170,
            badge: true,
            tone: function (r) { return r.kind_tone }
        },
        {
            key: "qty_text",
            header: Strings.t("stock.col.qty", "Change"),
            numeric: true,
            width: 130,
            ltr: true,
            tone: function (r) { return r.in ? "success" : "danger" }
        },
        {
            key: "after_text",
            header: Strings.t("stock.col.after", "Balance"),
            numeric: true,
            width: 130,
            ltr: true
        },
        {
            key: "ref",
            header: Strings.t("stock.col.ref", "Document"),
            width: 160,
            ltr: true
        },
        {
            key: "reason",
            header: Strings.t("cash.reason", "Reason"),
            width: 260
        },
        {
            key: "by",
            header: Strings.t("receipt.cashier", "By"),
            width: 150
        }
    ]

    /* `hidden` is not a DataTable feature — the column list is filtered here
       instead, which is the same result with nothing added to the shared
       component for one caller's benefit. */
    readonly property var visibleColumns: {
        var out = []
        for (var i = 0; i < columns.length; i++)
            if (!columns[i].hidden)
                out.push(columns[i])
        return out
    }

    contentItem: ColumnLayout {
        spacing: Tokens.spacing.md

        /*
         * Which product, and which kind of movement.
         *
         * The first version of this screen loaded the whole shop and offered no way
         * to narrow it, which is the wrong default for the question it answers: a
         * ledger is read because ONE figure looks wrong. So the finder comes first,
         * a scan or two letters lands on a product, and the whole shop is what you
         * get when you have not chosen one — the fallback rather than the start.
         */
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.sm

            ProductFinder {
                id: finder
                Layout.fillWidth: true
                placeholder: Strings.t("stock.finder.ph",
                                       "Scan or search a product")
                results: dialog.matches
                all: dialog.catalogue

                onQueried: (text) => {
                    dialog.matches = (text.trim() === "" || !dialog.ctrl)
                                     ? [] : dialog.ctrl.find(text, 12)
                }
                onBrowsed: {
                    if (dialog.ctrl)
                        dialog.catalogue = dialog.ctrl.find("", 500)
                }
                onAccepted: (text) => dialog.submit(text)
                onPicked: (product) => dialog.show(product.id, product.name)
            }

            /* Back to the whole shop. Only offered while something is filtered, so
               it never reads as a control with no effect. */
            GlyphButton {
                visible: dialog.shownId > 0
                glyph: "ic_fluent_dismiss_20_regular"
                text: Strings.t("stock.all_products", "Whole shop")
                onClicked: dialog.show(0, "")
            }

            QC.ComboBox {
                Layout.preferredWidth: 240
                Layout.preferredHeight: Tokens.size.control
                textRole: "label"
                model: dialog.kinds
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                onActivated: (index) => {
                    dialog.kind = dialog.kinds[index].key
                    dialog.page = 1
                    dialog.reload()
                }
            }

            Text {
                text: Strings.tf("table.count", "{count} movements",
                                 { count: dialog.total })
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.caption
                color: Fluent.textTertiary
            }
        }

        DataTable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: dialog.visibleColumns
            model: dialog.rows
            emptyIcon: "ic_fluent_history_20_regular"
            emptyText: Strings.t("stock.ledger.empty",
                                 "Nothing has moved yet.")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.sm

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
}

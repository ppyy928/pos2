import QtQuick
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * Find a product, to sell it — the till's `product_select` workflow.
 *
 *   ┌ Find a product ─────────────────────────────────────────┐
 *   │ [ search by name or barcode ......................... ] │
 *   │ NAME         BARCODE        CATEGORY   STOCK  PRICE     │
 *   │ Yoghurt 1L  5449000996     Dairy       24    89.00     │
 *   │ 2,999                                                    │
 *   │                                              [ Close ]   │
 *   └──────────────────────────────────────────────────────────┘
 *
 * A thin shell: the table, the filter, the keyboard and the pick contract all
 * live in `Mizan/ProductPicker.qml`, which is the same surface inside
 * ProductFinder's browse popup and the multi-unit form's product question. This
 * file owns only what is particular to the till — the catalogue it reads, the
 * rule that an empty shelf is reported rather than rung up, and where the
 * answer goes: a cart line.
 *
 * WHY IT IS STILL A WORKFLOW DIALOG
 *
 * The browse popups inside other screens are popups because they belong to
 * those screens. This one is routed — `pos.sell`, not `products.view`, because
 * its only outcome is a cart line and a view-only stock clerk who may read the
 * catalogue must not reach it — and a routed dialog is what DialogHost stacks.
 *
 * WHAT IT SHOWS THAT THE TILE WALL CANNOT
 *
 * Every product, including the ones kept off the till (`show_on_pos = 0`) and
 * the ones out of stock. A hidden product is perfectly sellable — the barcode
 * scanner has always found them — so refusing to list them here would leave
 * the operator no way to sell something that is sitting on the shelf. The
 * empty shelf is the one thing the till says out loud, and it says it at the
 * moment the row is picked (`requireStock`), not as a verdict printed over a
 * list whose other callers would sell that very row without a question.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var till: (typeof app !== "undefined" && app) ? app.pos : null

    preferredWidth: 1040
    preferredHeight: 860

    title: Strings.t("product_select.title", "Find a product")

    Component.onCompleted: body.focusSearch()

    contentItem: ColumnLayout {
        spacing: Tokens.spacing.md

        ProductPicker {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: true

            catalogue: dialog.till ? dialog.till.catalogue() : []
            requireStock: true

            /* Add and close. One tap, one product, one outcome — the dropdown
               under the till's own search field is the tool for adding three
               things in a row. */
            onPicked: (product) => {
                if (dialog.till)
                    dialog.till.add(product.id)
                dialog.close()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.sm

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

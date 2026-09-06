import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * A product the shop is selling before anyone filed it. Ported from
 * pos/app/dialogs/pos_dialogs.py::QuickAddProductDialog.
 *
 * A name is the only requirement, and that is deliberate: the cashier is holding
 * up a queue. Everything else — cost, category, opening quantity — can be filled
 * in later from the Products screen, and pos's quick_add_product is built for
 * exactly that.
 *
 * On success it goes into the cart if there is stock to sell, which is what pos
 * does: the reason this dialog is open is that somebody is standing there holding
 * the thing.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.products : null
    readonly property var till: (typeof app !== "undefined" && app) ? app.pos : null
    readonly property int measure: 620

    preferredWidth: 900
    title: Strings.t("qproduct.title", "Quick add product")

    Component.onCompleted: {
        if (ctrl && ctrl.loadCategories)
            ctrl.loadCategories()
        if (context && context.code)
            barcode.text = context.code
        name.forceActiveFocus()
    }

    function save() {
        error.text = ""
        if (name.text.trim() === "") {
            error.text = Strings.t("qproduct.name.required",
                                   "Product name is required.")
            name.forceActiveFocus()
            return
        }
        if (!ctrl)
            return
        ctrl.quickAdd(name.text, barcode.text,
                      dialog.number(sale.text), dialog.number(purchase.text),
                      dialog.number(stock.text),
                      category.currentIndex > 0
                      ? category.model[category.currentIndex].id : 0)
    }

    /* "1,5" is what a French or Arabic keyboard produces for one and a half, and
       parseFloat stops at the comma. Same normalisation as the cart's stepper. */
    function number(text) {
        var value = parseFloat(String(text).replace(",", "."))
        return isNaN(value) ? 0 : value
    }

    Connections {
        target: dialog.ctrl
        ignoreUnknownSignals: true

        function onCreated(product) {
            /* Straight into the cart when there is something to sell. A product
               created at zero stock was filed, not sold — pos draws the same
               line, and adding it would put a line on the sale that the shelf
               cannot support. */
            if (dialog.till && product.stock > 0)
                dialog.till.add(product.id)
            dialog.close()
        }

        function onRejected(message) {
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
            text: field.required ? field.label + " *" : field.label
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.caption
            font.weight: Font.DemiBold
            color: Fluent.textSecondary
        }
    }

    contentItem: ColumnLayout {
        spacing: Tokens.spacing.md

        Field {
            Layout.preferredWidth: dialog.measure
            label: Strings.t("qproduct.name", "Product name")
            required: true

            QC.TextField {
                id: name
                Layout.fillWidth: true
                Layout.preferredHeight: Tokens.size.control
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                onAccepted: dialog.save()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.md

            Field {
                label: Strings.t("qproduct.barcode", "Barcode")

                QC.TextField {
                    id: barcode
                    Layout.fillWidth: true
                    Layout.preferredHeight: Tokens.size.control
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                    /* A code reads left to right whatever the language. */
                    horizontalAlignment: TextInput.AlignLeft
                    onAccepted: dialog.save()
                }
            }

            Field {
                label: Strings.t("qproduct.category", "Category")

                QC.ComboBox {
                    id: category
                    Layout.fillWidth: true
                    textRole: "name"
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                    /* Index 0 is "none": a quick add without a category is
                       normal, and pos allows it. */
                    model: {
                        var out = [{ id: 0,
                                     name: Strings.t("products.filter.all_categories",
                                                     "No category") }]
                        var source = dialog.ctrl ? dialog.ctrl.categories : null
                        if (source)
                            for (var i = 0; i < source.length; i++)
                                out.push(source[i])
                        return out
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.md

            Field {
                label: Strings.t("qproduct.sale", "Sale price")

                NumberField {
                    id: sale
                    Layout.fillWidth: true
                    Layout.preferredHeight: Tokens.size.control
                    font.pixelSize: Tokens.font.body
                    onAccepted: dialog.save()
                }
            }

            Field {
                label: Strings.t("qproduct.purchase", "Purchase price")

                NumberField {
                    id: purchase
                    Layout.fillWidth: true
                    Layout.preferredHeight: Tokens.size.control
                    font.pixelSize: Tokens.font.body
                    onAccepted: dialog.save()
                }
            }

            Field {
                label: Strings.t("qproduct.stock", "Opening quantity")

                NumberField {
                    id: stock
                    Layout.fillWidth: true
                    Layout.preferredHeight: Tokens.size.control
                    font.pixelSize: Tokens.font.body
                    onAccepted: dialog.save()
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
                text: Strings.t("action.cancel", "Cancel")
                onClicked: dialog.close()
            }

            GlyphButton {
                glyph: "ic_fluent_save_20_regular"
                text: Strings.t("action.save", "Save")
                highlighted: true
                onClicked: dialog.save()
            }
        }
    }
}

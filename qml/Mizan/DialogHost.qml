import QtQuick
import QtQuick.Controls as QC
import FluentControls
import Mizan

/*
 * The window's dialogs. One host, one dialog at a time, keyed by workflow.
 *
 *     DialogHost { id: dialogs }
 *     Connections {
 *         target: app.workflows
 *         function onRequested(key, context) { dialogs.show(key, context) }
 *     }
 *
 * WHY THE MAP LIVES HERE AND THE PERMISSION DOES NOT
 *
 * `app.workflows` decides whether the operator may open a thing — that is a
 * business rule and it belongs in Python. Which QML file draws it is a fact about
 * this front end, so it is here. A key with no file yet is not an error: it is a
 * screen that has not been built, and it says so rather than doing nothing.
 *
 * WHY IT IS AT WINDOW LEVEL
 *
 * A dialog parented to a page dies with the page — and PageHost replaces the page
 * on every navigation. It also outranks `enabled: signedIn` on the shell layout,
 * so a dialog is never left half-usable behind a login screen.
 *
 * WHY createObject AND NOT A LOADER
 *
 * FluentDialog is a Popup, not an Item: it positions itself over
 * `Overlay.overlay` and draws its own scrim, so it does not need — and cannot
 * use — a Loader's geometry. Building it explicitly also makes the failure cases
 * reportable, which is the same reasoning PageHost gives for its own
 * Qt.createComponent.
 */
Item {
    id: host

    /* A key that has no file yet. The shell says so out loud. */
    signal unavailable(string key)
    /* A file that exists and would not load: a defect, with the reason. */
    signal failed(string key, string message)

    readonly property var files: ({
        "customer_select": "../dialogs/CustomerPickerDialog.qml",
        "product_select": "../dialogs/ProductPickerDialog.qml",
        "saved_carts": "../dialogs/SavedCartsDialog.qml",
        "payment_calculator": "../dialogs/PaymentCalculatorDialog.qml",
        "unknown_barcode": "../dialogs/UnknownBarcodeDialog.qml",
        "quick_add_product": "../dialogs/QuickAddProductDialog.qml",
        "product_form": "../dialogs/ProductFormDialog.qml",
        "stock_adjust": "../dialogs/StockAdjustDialog.qml",
        "stock_count": "../dialogs/StockCountDialog.qml",
        "stock_ledger": "../dialogs/StockLedgerDialog.qml",
        "sale_select": "../dialogs/SaleSelectorDialog.qml",
        "sale_transaction": "../dialogs/SaleDetailsDialog.qml",
        "return_create": "../dialogs/ReturnDialog.qml",
        "return_details": "../dialogs/ReturnDetailsDialog.qml",
        /* One record screen per party, doing what a `*_details` panel and a form
           used to do between them — see workflows.py for why the split went. */
        "customer_form": "../dialogs/CustomerFormDialog.qml",
        "supplier_form": "../dialogs/SupplierFormDialog.qml",
        "cash_entry": "../dialogs/CashEntryDialog.qml",
        "employee_form": "../dialogs/EmployeeFormDialog.qml",
        "purchase_form": "../dialogs/PurchaseFormDialog.qml",
        "categories": "../dialogs/CategoriesDialog.qml",
        "units": "../dialogs/UnitsDialog.qml",
        "multi_units": "../dialogs/MultiUnitsDialog.qml",
        "products_arrange": "../dialogs/ArrangeDialog.qml",
        "barcode_labels": "../dialogs/BarcodeLabelsDialog.qml",
        "products_export": "../dialogs/ExportDialog.qml",
        "products_import": "../dialogs/ImportDialog.qml"
    })

    property var current: null

    function show(key, context) {
        var file = files[key]
        if (file === undefined) {
            host.unavailable(key)
            return
        }

        close()

        var component = Qt.createComponent(Qt.resolvedUrl(file))
        if (component.status === Component.Error) {
            host.failed(key, component.errorString())
            return
        }

        var dialog = component.createObject(host, { context: context || ({}) })
        if (dialog === null) {
            host.failed(key, component.errorString())
            return
        }

        /* Closed for any reason — a button, Escape, the operator finishing —
           takes the object with it. Deferred, because destroying an object while
           it is emitting the signal that brought us here is how a crash starts. */
        dialog.closed.connect(function () {
            Qt.callLater(function () {
                if (dialog !== null)
                    dialog.destroy()
            })
        })

        current = dialog
        dialog.open()
    }

    function close() {
        if (current) {
            current.close()
            current = null
        }
    }
}

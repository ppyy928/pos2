import QtQuick
import QtQuick.Controls as QC
import FluentControls
import Mizan

/*
 * The window's dialogs, keyed by workflow — and stacked, not swapped.
 *
 *     DialogHost { id: dialogs }
 *     Connections {
 *         target: app.workflows
 *         function onRequested(key, context) { dialogs.show(key, context) }
 *     }
 *
 * WHY A STACK
 *
 * This used to close the open dialog before building the next one, on the theory
 * that one dialog at a time is simpler. It is not what the screens do. A customer's
 * record lists their sales and opens one; a supplier's record opens a delivery; the
 * product form opens a stock adjustment. Every one of those is "look at this thing
 * from inside that thing", and closing the opener meant the record an operator was
 * reading vanished under them — and in the product form's case took unsaved edits
 * with it. There was nowhere to come back to.
 *
 * So `show` pushes and a close pops. A Popup opened later is placed later in the
 * window's overlay, so it draws over the one beneath it and dims it with its own
 * modal scrim; Escape reaches the topmost popup only. Nothing about the layering
 * needed building — only this file needed to stop destroying the layer below.
 *
 * A dialog that genuinely REPLACES its opener still can: it closes itself after
 * routing, which is what UnknownBarcodeDialog does when the operator chooses to add
 * the product instead ("that question is answered, this one is not a layer to come
 * back to").
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
        /* One record screen per party, with the details it holds edited in a form of
           their own — which the record opens as a child. The `*_edit` keys are how a
           page reaches that form when there is no record yet. */
        "customer_form": "../dialogs/CustomerFormDialog.qml",
        "customer_edit": "../dialogs/CustomerEditDialog.qml",
        "supplier_form": "../dialogs/SupplierFormDialog.qml",
        "supplier_edit": "../dialogs/SupplierEditDialog.qml",
        "cash_entry": "../dialogs/CashEntryDialog.qml",
        "employee_form": "../dialogs/EmployeeFormDialog.qml",
        "taxes": "../dialogs/TaxesDialog.qml",
        "purchase_form": "../dialogs/PurchaseFormDialog.qml",
        "categories": "../dialogs/CategoriesDialog.qml",
        "units": "../dialogs/UnitsDialog.qml",
        "multi_units": "../dialogs/MultiUnitsDialog.qml",
        "products_arrange": "../dialogs/ArrangeDialog.qml",
        "barcode_labels": "../dialogs/BarcodeLabelsDialog.qml",
        "products_export": "../dialogs/ExportDialog.qml",
        "products_import": "../dialogs/ImportDialog.qml",
        "products_incomplete": "../dialogs/IncompleteProductsDialog.qml"
    })

    /* Open dialogs, oldest first. A page reads `current` for the top one; nothing
       reads the rest, but the depth is what tells this file when to stop. */
    property var stack: []

    readonly property var current: stack.length > 0 ? stack[stack.length - 1] : null

    /* A dialog that opens a dialog that opens the first one is a cycle, and a cycle
       here fills the overlay with modal layers nobody can dismiss. Four is one more
       than anything this app legitimately nests (record → form → confirmation), so
       the fifth is a defect and says so instead of piling up. */
    readonly property int maxDepth: 4

    function show(key, context) {
        var file = files[key]
        if (file === undefined) {
            Diag.warn("DialogHost", "no file for workflow key " + key)
            host.unavailable(key)
            return
        }

        if (stack.length >= maxDepth) {
            Diag.fail("DialogHost",
                      key + ": refused at depth " + stack.length
                      + " — a dialog chain this deep is a cycle")
            host.failed(key, "dialog stack too deep")
            return
        }

        Diag.action("DialogHost", "open " + key, context)

        var component = Qt.createComponent(Qt.resolvedUrl(file))
        if (component.status === Component.Error) {
            /* A defect rather than a refusal: the file is named in the map above,
               so it exists and does not compile. errors.log is where that
               belongs, with the reason QML gave. */
            Diag.fail("DialogHost", key + ": " + component.errorString())
            host.failed(key, component.errorString())
            return
        }

        var dialog = component.createObject(host, { context: context || ({}) })
        if (dialog === null) {
            Diag.fail("DialogHost", key + ": " + component.errorString())
            host.failed(key, component.errorString())
            return
        }

        /* Closed for any reason — a button, Escape, the operator finishing — takes
           the object with it and leaves the layer beneath it open. Deferred, because
           destroying an object while it is emitting the signal that brought us here
           is how a crash starts. */
        dialog.closed.connect(function () {
            Diag.action("DialogHost", "closed " + key)
            host.forget(dialog)
            Qt.callLater(function () {
                if (dialog !== null)
                    dialog.destroy()
            })
        })

        var next = stack.slice()
        next.push(dialog)
        stack = next
        dialog.open()
    }

    /* Drop one dialog from the stack, wherever it is: they usually close top-down,
       but a dialog closed by its own logic while another sits over it must not leave
       a hole that `current` then points at. */
    function forget(dialog) {
        var next = []
        for (var i = 0; i < stack.length; i++)
            if (stack[i] !== dialog)
                next.push(stack[i])
        stack = next
    }

    /* Close the topmost. Each close pops itself through the handler above, so
       closing repeatedly walks the stack down. */
    function close() {
        if (current)
            current.close()
    }

    function closeAll() {
        var open_ = stack.slice()
        for (var i = open_.length - 1; i >= 0; i--)
            open_[i].close()
    }
}

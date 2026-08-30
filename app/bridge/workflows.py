"""The workflow router, behind `app.workflows`.

A page never opens a dialog itself. It says what it wants —
`workflows.open("customer_select", {})` — and this decides whether the operator
may, then asks the shell to show it. Ported from pos/app/core/workflows.py,
which does the same three things: look the key up, check the permission, open it.

WHY THE ROUTER DOES NOT KNOW WHAT A DIALOG LOOKS LIKE

The QML file for each key is in DialogHost.qml, not here. Python owns the rule
(who may open this) and QML owns the surface (what it looks like), which is the
same split as everywhere else in this app: a permission is a business fact, a
dialog is a screen. It also means an unbuilt key is a QML-side question, and
DialogHost answers it with a message instead of silence.

WHY A SIGNAL AND NOT A RETURN VALUE

pos constructs and shows a QWidget dialog from inside this function. Here the
dialogs are QML, so the router cannot build one — it emits `requested` and the
window's DialogHost, which lives as long as the window, does. That also keeps a
dialog alive across a page change, which a page-owned dialog would not be.
"""

from __future__ import annotations

from PySide6.QtCore import QObject, Signal, Slot

from . import interop


class Spec:
    """One workflow: the permission it needs and the name to put in a refusal."""

    __slots__ = ("permission", "title_key")

    def __init__(self, permission: str | None, title_key: str) -> None:
        self.permission = permission
        self.title_key = title_key


# Permissions follow pos's own table (app/core/workflows.py:205-224): the *view*
# permission opens an editor, and the page decides separately whether its
# manage-level actions are enabled. Keys that pos has no workflow for take the
# permission of the page they belong to.
#
# WHY THERE ARE NO `*_details` KEYS
#
# There used to be three — `product_details`, `customer_details`,
# `supplier_details` — each a read-only screen behind an eye icon whose own primary
# button opened the matching editor. They were one screen split by an
# implementation detail, so each pair is now a single record screen and the eye
# column is gone from those tables. That is also why `customer_form` takes the
# *view* permission: it is how a customer is looked at now, and its Save is gated
# on the manage right inside the dialog rather than by refusing to open it.
SPECS: dict[str, Spec] = {
    # products
    "product_form": Spec("products.view", "product.edit_title"),
    "stock_adjust": Spec("products.manage", "stock.adjust_title"),
    "stock_count": Spec("products.manage", "count.title"),
    "stock_ledger": Spec("products.view", "stock.ledger"),
    "products_arrange": Spec("products.manage", "products.arrange.action"),
    "products_import": Spec("products.view", "import.title"),
    "products_export": Spec("products.view", "reports.export"),
    "barcode_labels": Spec("products.view", "products.hdr.barcode"),
    "categories": Spec("products.view", "categories.title"),
    "units": Spec("products.view", "units.title"),
    "multi_units": Spec("products.view", "product.multi_units"),
    "quick_add_product": Spec("products.view", "qproduct.title"),
    "unknown_barcode": Spec("products.view", "unknown.title"),
    # till
    "customer_select": Spec("customers.view", "select_customer.title"),
    # pos.sell, not products.view: this dialog's only outcome is a cart line, so a
    # view-only stock clerk who may read the catalogue must not reach it.
    "product_select": Spec("pos.sell", "product_select.title"),
    "saved_carts": Spec("pos.sell", "carts.title"),
    "payment_calculator": Spec("pos.sell", "pos.calculator.title"),
    # sales
    "sale_select": Spec("sales.view", "return.select_sale"),
    "sale_transaction": Spec("sales.view", "sale.transaction_title"),
    "return_create": Spec("sales.edit", "return.create_title"),
    "return_details": Spec("sales.view", "return.details_title"),
    # customers
    "customer_form": Spec("customers.view", "customers.edit_title"),
    # cash
    "cash_entry": Spec("cash.manage", "nav.cash"),
    # people
    "employee_form": Spec("employees.view", "employees.add"),
    # purchases
    "purchase_form": Spec("purchases.view", "purchases.edit_title"),
    "supplier_form": Spec("purchases.view", "supplier.edit_title"),
}


class Workflows(QObject):
    #: The shell should show this. `context` is the page's own payload.
    requested = Signal(str, "QVariant")

    #: Refused, with a sentence to show. Never silent: a button that does
    #: nothing is indistinguishable from a broken one.
    refused = Signal(str)

    def __init__(self, i18n: QObject, session: QObject,
                 parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._i18n = i18n
        self._session = session

    @Slot(str, "QVariant")
    def open(self, key: str, context: object) -> None:
        spec = SPECS.get(key)
        if spec is None:
            # Not translated, deliberately: a build-state message that goes away
            # when the key lands, not a product string. Same wording the pages
            # use when the router itself is missing.
            self.refused.emit("That screen is not part of this build yet.")
            return
        if spec.permission and not self._session.can(spec.permission):
            self.refused.emit(
                self._i18n.text("permission.denied.body",
                                target=self._i18n.text(spec.title_key))
            )
            return
        self.requested.emit(key, interop.as_dict(context))

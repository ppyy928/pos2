"""Purchases and suppliers, behind `app.purchases` and `app.suppliers`.

    app.purchases   load(search, page, pageSize), rows, stats, invoice(id),
                    save(data, id), remove(id)
    app.suppliers   load(search), rows, supplier(id), save(name, phone, id),
                    recordPayment(id, amount)

A PURCHASE INVOICE IS A STOCK MOVEMENT AND A DEBT AT THE SAME TIME
------------------------------------------------------------------
`save_purchase_invoice` raises stock for every line and adds what is unpaid to the
supplier's debt, in one transaction — and on an edit it undoes the old effects
first. That is why the form sends whole invoices rather than patches: a line
changed in isolation would leave the stock it moved behind.

The same reason nothing here computes a total. The invoice's own figure is the sum
the database wrote, and a screen that added the lines up itself would be a second
opinion about money.
"""

from __future__ import annotations

from PySide6.QtCore import Property, QObject, Signal, Slot

from . import fmt, interop, legacy


class Purchases(QObject):
    rowsChanged = Signal()
    statsChanged = Signal()
    busyChanged = Signal()
    errorChanged = Signal()

    invalidated = Signal()
    saved = Signal("QVariant")
    rejected = Signal(str)

    def __init__(self, i18n: QObject, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._i18n = i18n
        self._rows: list[dict] = []
        self._stats: dict = {}
        self._total = 0
        self._busy = False
        self._error = ""
        self._query = ("", 1, 100)

    @Property(bool, notify=busyChanged)
    def busy(self) -> bool:
        return self._busy

    @Property(str, notify=errorChanged)
    def error(self) -> str:
        return self._error

    @Property(int, notify=rowsChanged)
    def total(self) -> int:
        return self._total

    @Property("QVariantList", notify=rowsChanged)
    def rows(self) -> list:
        return self._rows

    @Property("QVariantMap", notify=statsChanged)
    def stats(self) -> dict:
        return self._stats

    @Slot(str, int, int)
    def load(self, search: str, page: int, page_size: int) -> None:
        database = self._database()
        if database is None:
            return
        self._query = (search or "", max(1, int(page)), int(page_size))
        self._set_busy(True)
        try:
            result = database.fetch_purchase_invoices(*self._query)
            self._rows = [self._row(row) for row in result["rows"]]
            self._total = int(result["total"])
            stats = dict(result.get("stats") or {})
            debt = float(stats.get("debt") or 0.0)
            self._stats = {
                "count": str(int(stats.get("count") or 0)),
                "total": fmt.compact(stats.get("total") or 0.0),
                "total_full": fmt.money(stats.get("total") or 0.0),
                "debt": fmt.compact(debt),
                "debt_full": fmt.money(debt),
                "debt_raw": debt,
            }
            self._set_error("")
        except Exception as exc:  # noqa: BLE001
            self._set_error(str(exc))
            self._rows = []
            self._total = 0
        finally:
            self._set_busy(False)
        self.rowsChanged.emit()
        self.statsChanged.emit()

    @Slot()
    def reload(self) -> None:
        self.load(*self._query)

    @Slot(int, result="QVariant")
    def rowAt(self, index: int) -> object:
        if 0 <= index < len(self._rows):
            return self._rows[index]
        return None

    @Slot(int, result="QVariant")
    def invoice(self, invoice_id: int) -> object:
        database = self._database()
        if database is None:
            return None
        try:
            row = database.fetch_purchase_invoice(int(invoice_id))
        except Exception as exc:  # noqa: BLE001
            self._set_error(str(exc))
            return None
        if row is None:
            return None
        invoice = dict(row)
        total = float(invoice.get("total") or 0.0)
        paid = float(invoice.get("paid") or 0.0)
        invoice["text"] = {
            "total": fmt.money(total),
            "paid": fmt.money(paid),
            "due": fmt.money(max(0.0, total - paid)),
            "when": fmt.when(invoice.get("created_at")),
        }
        invoice["items"] = [
            {
                "id": item.get("id"),
                "product_id": item.get("product_id"),
                "name": item["name"],
                "qty": float(item.get("qty") or 0.0),
                "qty_text": fmt.qty(item.get("qty")),
                "price": float(item.get("price") or 0.0),
                "price_text": fmt.money(item.get("price")),
                "total_text": fmt.money(item.get("total")),
            }
            for item in (invoice.get("items") or [])
        ]
        return invoice

    @Slot("QVariant", int)
    def save(self, data: object, invoice_id: int) -> None:
        """`data` is {supplier_id, paid, items: [{product_id, name, qty, price}]}.

        Whole invoices only — see the module note. An empty item list is refused by
        the database, which is the right place for that rule.
        """
        values = interop.as_dict(data)
        raw_items = values.get("items") or []
        items = []
        for entry in raw_items:
            item = interop.as_dict(entry) if not isinstance(entry, dict) else entry
            qty = interop.as_float(item.get("qty"))
            price = interop.as_float(item.get("price"))
            name = str(item.get("name") or "").strip()
            if qty <= 0 or not name:
                continue
            items.append({
                "product_id": item.get("product_id") or None,
                "name": name,
                "qty": qty,
                "price": price,
                # Optional, and only present when the entry sheet was used: a delivery
                # that arrived dearer re-prices the shelf, and 0 means "leave the
                # product's own price alone" rather than "sell it for nothing".
                "sale_price": interop.as_float(item.get("sale_price")),
                "expiry": str(item.get("expiry") or "").strip(),
                "batch_code": str(item.get("batch_code") or "").strip(),
            })
        if not items:
            self.rejected.emit(self._i18n.text("purchases.no_items",
                                               "An invoice needs at least one line."))
            return

        database = self._database()
        if database is None:
            return
        payload = {
            "supplier_id": int(values.get("supplier_id") or 0) or None,
            "paid": interop.as_float(values.get("paid")),
            "items": items,
        }
        try:
            invoice = database.save_purchase_invoice(payload,
                                                    int(invoice_id) or None)
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.saved.emit(dict(invoice))
        self.invalidated.emit()
        self.reload()

    @Slot(int)
    def remove(self, invoice_id: int) -> None:
        """Deleting an invoice takes its stock back out and undoes the debt it
        created — pos's delete does both, which is why this is a confirmed action
        on the page rather than a row button."""
        database = self._database()
        if database is None:
            return
        try:
            database.delete_purchase_invoice(int(invoice_id))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.invalidated.emit()
        self.reload()

    @Slot(int, result="QVariantMap")
    def lineDefaults(self, product_id: int) -> dict:
        """What a new delivery line for this product should start with.

        The cost comes from the last delivery of it rather than from
        `products.purchase_price` — the stored figure is whatever somebody typed into
        the product form, which may be a year old, while this is what was actually
        paid. `last_text` names the invoice and the date, so the operator can see that
        it is last time's number and notice when it should not be.

        The selling price is the product's current one: that IS the last price it was
        sold at, and the delivery screen offers it for re-pricing rather than for
        confirmation.
        """
        database = self._database()
        if database is None:
            return {}
        try:
            product = database.fetch_product(int(product_id))
            last = database.last_purchase_line(int(product_id))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return {}
        if product is None:
            return {}

        cost = float(product.get("purchase_price") or 0.0)
        text = ""
        if last:
            cost = float(last.get("price") or cost)
            text = (self._i18n.text("purchases.last_cost",
                                    "Last: {amount} · {number} · {when}")
                    .replace("{amount}", fmt.money(cost))
                    .replace("{number}", str(last.get("number") or ""))
                    .replace("{when}", fmt.when(last.get("created_at"))))
        return {
            "id": product["id"],
            "name": product.get("name") or "",
            "barcode": product.get("barcode") or "",
            "cost": cost,
            "price": float(product.get("sale_price") or 0.0),
            "last_text": text,
            # What is on the shelf. The entry sheet shows it under the name because it
            # is the third fact that decides whether the seeded figures are right.
            "stock_text": self._i18n.text("purchases.in_stock", "{qty} in stock")
                              .replace("{qty}", fmt.qty(product.get("stock"))),
        }

    @Slot(float, result=str)
    def moneyText(self, value: float) -> str:
        return fmt.money(value)

    def _row(self, row: dict) -> dict:
        total = float(row.get("total") or 0.0)
        paid = float(row.get("paid") or 0.0)
        due = max(0.0, total - paid)
        return {
            "id": row["id"],
            "number": row["number"],
            "when": fmt.when(row.get("created_at")),
            "supplier": row.get("supplier") or self._i18n.text("purchases.no_supplier"),
            "total": fmt.money(total),
            "paid": fmt.money(paid),
            "due": fmt.money(due),
            "owes": due > 0,
        }

    def _database(self):
        try:
            return legacy.database()
        except Exception as exc:  # noqa: BLE001
            self._set_error(str(exc))
            return None

    def _set_busy(self, value: bool) -> None:
        if self._busy == value:
            return
        self._busy = value
        self.busyChanged.emit()

    def _set_error(self, message: str) -> None:
        if self._error == message:
            return
        self._error = message
        self.errorChanged.emit()


class Suppliers(QObject):
    """The other side of PartyCard: who the shop buys from, and what it owes them.

    Deliberately the same shape as Customers — search, rows with a formatted debt,
    a detail payload and a payment — because a supplier account behaves the same
    way a customer account does, with the sign reversed.
    """

    rowsChanged = Signal()
    busyChanged = Signal()

    invalidated = Signal()
    saved = Signal("QVariant")
    paid = Signal("QVariant")
    rejected = Signal(str)

    def __init__(self, i18n: QObject, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._i18n = i18n
        self._rows: list[dict] = []
        self._busy = False
        self._search = ""

    @Property(bool, notify=busyChanged)
    def busy(self) -> bool:
        return self._busy

    @Property(int, notify=rowsChanged)
    def total(self) -> int:
        return len(self._rows)

    @Property("QVariantList", notify=rowsChanged)
    def rows(self) -> list:
        return self._rows

    @Slot(str)
    def load(self, search: str) -> None:
        database = self._database()
        if database is None:
            return
        self._search = search or ""
        self._set_busy(True)
        try:
            self._rows = [
                {
                    "id": row["id"],
                    "name": row["name"],
                    "phone": row.get("phone") or "",
                    "debt": float(row.get("debt") or 0.0),
                    "debt_text": fmt.money(row.get("debt") or 0.0),
                    "owes": float(row.get("debt") or 0.0) > 0,
                }
                for row in database.fetch_suppliers(self._search)
            ]
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            self._rows = []
        finally:
            self._set_busy(False)
        self.rowsChanged.emit()

    @Slot()
    def reload(self) -> None:
        self.load(self._search)

    @Slot(int, result="QVariant")
    def rowAt(self, index: int) -> object:
        if 0 <= index < len(self._rows):
            return self._rows[index]
        return None

    @Slot(int, result="QVariant")
    def supplier(self, supplier_id: int) -> object:
        """One supplier: the balance, the deliveries behind it, what has been paid,
        and the four figures the dialog leads with.

        Same shape as Customers.customer, deliberately — the two dialogs are the
        same screen with the sign reversed, so a difference in the payload would be
        a difference in the QML for no reason.
        """
        database = self._database()
        if database is None:
            return None
        try:
            row = database.fetch_supplier(int(supplier_id))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return None
        if row is None:
            return None
        supplier = dict(row)
        debt = float(supplier.get("debt") or 0.0)
        supplier["debt"] = debt
        supplier["debt_text"] = fmt.money(debt)
        supplier["owes"] = debt > 0

        invoices = []
        purchased = 0.0
        for invoice in supplier.get("invoices") or []:
            total = float(invoice.get("total") or 0.0)
            due = max(0.0, total - float(invoice.get("paid") or 0.0))
            purchased += total
            invoices.append({
                "id": invoice.get("id"),
                "number": invoice.get("number"),
                "when": fmt.when(invoice.get("created_at")),
                "total_text": fmt.money(total),
                "due_text": fmt.money(due),
                "owes": due > 0,
            })
        supplier["invoices"] = invoices

        payments = []
        paid_total = 0.0
        for payment in supplier.get("payments") or []:
            amount = float(payment.get("amount") or 0.0)
            paid_total += amount
            payments.append({
                "id": payment.get("id"),
                "amount_text": fmt.money(amount),
                "when": fmt.when(payment.get("created_at")),
            })
        supplier["payments"] = payments

        supplier["cards"] = {
            "debt": fmt.money(debt),
            "debt_raw": debt,
            "invoice_count": str(len(invoices)),
            "purchased": fmt.compact(purchased),
            "purchased_full": fmt.money(purchased),
            "paid_total": fmt.compact(paid_total),
            "paid_total_full": fmt.money(paid_total),
            "paid_count": str(len(payments)),
            "last_invoice": invoices[0]["when"] if invoices else "",
        }
        return supplier

    @Slot(str, str, int)
    @Slot(str, str, int, "QVariant")
    def save(self, name: str, phone: str, supplier_id: int,
             extra: object = None) -> None:
        """Name, phone, and whatever else the record offered — the rep's name, the
        wilaya, the postal and tax detail. Optional, so the purchases screen can
        still create a supplier from two fields mid-delivery."""
        clean = (name or "").strip()
        if not clean:
            self.rejected.emit(self._i18n.text("supplier.name.required"))
            return
        database = self._database()
        if database is None:
            return
        fields = interop.as_dict(extra) if extra is not None else {}
        try:
            supplier = database.save_supplier(clean, (phone or "").strip(),
                                              int(supplier_id) or None,
                                              fields or None)
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.saved.emit(dict(supplier))
        self.invalidated.emit()
        self.reload()

    @Slot(int, "QVariant")
    def recordPayment(self, supplier_id: int, amount: object) -> None:
        value = interop.as_float(amount)
        if value <= 0:
            self.rejected.emit(self._i18n.text("amount.error"))
            return
        database = self._database()
        if database is None:
            return
        try:
            result = database.record_supplier_payment(int(supplier_id), value)
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        payload = dict(result)
        payload["debt_text"] = fmt.money(payload.get("debt") or 0.0)
        self.paid.emit(payload)
        self.invalidated.emit()
        self.reload()

    @Slot(float, result=str)
    def moneyText(self, value: float) -> str:
        return fmt.money(value)

    def _database(self):
        try:
            return legacy.database()
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return None

    def _set_busy(self, value: bool) -> None:
        if self._busy == value:
            return
        self._busy = value
        self.busyChanged.emit()

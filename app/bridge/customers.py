"""Customers and their debt, behind `app.customers`.

    read      busy, error, total, stats, rows
    call      search(text)              the till's picker
              load(search, onlyDebtors, page, pageSize)
              customer(id)              one customer: cards, sales, payments
              save(name, phone, id), quickAdd(name, phone)
              recordPayment(id, amount)
    emits     invalidated(), created(customer), saved(customer), paid(result),
              rejected(message)

WHY THE PAGE PAGES IN PYTHON

`fetch_customers` has no page argument — a shop has hundreds of customers, not the
thousands it has products, so pos loads them all and filters in the widget. The
page still wants a page size and a total to show, so the slicing happens here
rather than in QML: the count is the truth about the query, and the rows are the
slice being looked at.

DEBT IS THE ONLY NUMBER THAT MATTERS HERE
-----------------------------------------
Everything else on a customer is a label. The debt figure decides whether the till
may sell to them on account, and it is the reason this screen has a "who owes"
filter at all.
"""

from __future__ import annotations

from PySide6.QtCore import Property, QObject, Signal, Slot

from . import fmt, interop, legacy


class Customers(QObject):
    rowsChanged = Signal()
    statsChanged = Signal()
    busyChanged = Signal()
    errorChanged = Signal()

    invalidated = Signal()
    created = Signal("QVariant")
    saved = Signal("QVariant")
    paid = Signal("QVariant")
    rejected = Signal(str)

    def __init__(self, i18n: QObject, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._i18n = i18n
        self._rows: list[dict] = []
        self._stats: dict = {}
        self._total = 0
        self._busy = False
        self._error = ""
        self._query = ("", False, 1, 100)

    # =====================================================================
    # STATE
    # =====================================================================
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

    # =====================================================================
    # QUERIES
    # =====================================================================
    @Slot(str)
    def search(self, text: str) -> None:
        """The till's picker: everything matching, unpaged."""
        self.load(text, False, 1, 0)

    @Slot(str, bool, int, int)
    def load(self, search: str, only_debtors: bool, page: int,
             page_size: int) -> None:
        database = self._database()
        if database is None:
            return
        self._query = (search or "", bool(only_debtors), max(1, int(page)),
                       int(page_size))
        self._set_busy(True)
        try:
            found = database.fetch_customers(self._query[0], self._query[1])
            self._total = len(found)
            self._stats = self._stat_block(found)
            size = self._query[3]
            if size > 0:
                start = (self._query[2] - 1) * size
                found = found[start:start + size]
            self._rows = [self._row(row) for row in found]
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
    def customer(self, customer_id: int) -> object:
        """One customer with their sales, their payments and the four figures the
        dialog leads with, newest first — which is the order the question is
        usually asked in ("what did they just buy").

        `cards` is a summary of the two histories below it rather than a second
        query: the rows are already here, so counting and totalling them costs
        nothing, and doing it here keeps every amount on the screen formatted by
        the one formatter. QML gets strings for the cards and a `_raw` beside each
        one, because a card that is red only when the number is above zero needs
        the number, not its rendering.
        """
        database = self._database()
        if database is None:
            return None
        try:
            row = database.fetch_customer(int(customer_id))
        except Exception as exc:  # noqa: BLE001
            self._set_error(str(exc))
            return None
        if row is None:
            return None

        customer = dict(row)
        debt = float(customer.get("debt") or 0.0)
        customer["debt"] = debt
        customer["debt_text"] = fmt.money(debt)
        customer["owes"] = debt > 0

        sales = []
        sales_total = 0.0
        for sale in customer.get("sales") or []:
            total = float(sale.get("total") or 0.0)
            due = max(0.0, total - float(sale.get("paid") or 0.0))
            sales_total += total
            sales.append({
                "id": sale["id"],
                "number": sale["number"],
                "when": fmt.when(sale.get("created_at")),
                # The raw type as well as its label: the label is what the cell
                # shows, the type is what decides the chip's colour, and deriving
                # one from the other in QML would mean matching translated text.
                "payment_type": sale.get("payment_type") or "",
                "payment": self._i18n.text(f"pay.type.{sale.get('payment_type')}")
                if sale.get("payment_type") else "",
                "total_text": fmt.money(total),
                "due_text": fmt.money(due),
                # The tone the table paints the row with, decided here because
                # "still owed on this ticket" is a fact about the numbers and not
                # about which column they land in.
                "owes": due > 0,
            })
        customer["sales"] = sales

        payments = []
        paid_total = 0.0
        for payment in customer.get("payments") or []:
            amount = float(payment.get("amount") or 0.0)
            paid_total += amount
            payments.append({
                "id": payment["id"],
                "amount_text": fmt.money(amount),
                "when": fmt.when(payment.get("created_at")),
            })
        customer["payments"] = payments

        customer["cards"] = {
            "debt": fmt.money(debt),
            "debt_raw": debt,
            "sales_count": str(len(sales)),
            "sales_total": fmt.compact(sales_total),
            "sales_total_full": fmt.money(sales_total),
            "paid_total": fmt.compact(paid_total),
            "paid_total_full": fmt.money(paid_total),
            "paid_count": str(len(payments)),
            "last_sale": sales[0]["when"] if sales else "",
        }
        return customer

    # =====================================================================
    # MUTATIONS
    # =====================================================================
    @Slot(str, str, int)
    @Slot(str, str, int, "QVariant")
    def save(self, name: str, phone: str, customer_id: int,
             extra: object = None) -> None:
        """Name, phone, and whatever else the form offered.

        `extra` is optional so the quick-add path and every existing caller stay
        two arguments and a flag: a cashier holding up a queue types a name, and
        the address, the price level and the credit ceiling are filled in later on
        the record itself.
        """
        clean = (name or "").strip()
        if not clean:
            self.rejected.emit(self._i18n.text("qcustomer.name.required"))
            return
        database = self._database()
        if database is None:
            return
        fields = interop.as_dict(extra) if extra is not None else {}
        try:
            customer = database.save_customer(clean, (phone or "").strip(),
                                              int(customer_id) or None,
                                              fields or None)
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.saved.emit(dict(customer))
        self.invalidated.emit()

    @Slot(str, str)
    def quickAdd(self, name: str, phone: str) -> None:
        """pos's quick_add_customer: a name is the only requirement, because the
        cashier is holding up a queue and the rest can be filled in later."""
        clean = (name or "").strip()
        if not clean:
            self.rejected.emit(self._i18n.text("qcustomer.name.required"))
            return
        database = self._database()
        if database is None:
            return
        try:
            customer = database.quick_add_customer(clean, (phone or "").strip())
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.created.emit(dict(customer))
        self.invalidated.emit()

    @Slot(int, "QVariant")
    def recordPayment(self, customer_id: int, amount: object) -> None:
        """Money against a debt. The database refuses zero and negatives and
        clamps the debt at zero, so an overpayment settles the account rather than
        turning it into credit — pos's rule, and the one a shop actually keeps."""
        value = interop.as_float(amount)
        if value <= 0:
            self.rejected.emit(self._i18n.text("amount.error"))
            return
        database = self._database()
        if database is None:
            return
        try:
            result = database.record_customer_payment(int(customer_id), value)
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        payload = dict(result)
        payload["debt_text"] = fmt.money(payload.get("debt") or 0.0)
        self.paid.emit(payload)
        self.invalidated.emit()

    @Slot(float, result=str)
    def moneyText(self, value: float) -> str:
        return fmt.money(value)

    # =====================================================================
    # INTERNALS
    # =====================================================================
    def _row(self, row: dict) -> dict:
        debt = float(row.get("debt") or 0.0)
        return {
            "id": row["id"],
            "name": row["name"],
            "phone": row.get("phone") or "",
            "debt": debt,
            "debt_text": fmt.money(debt),
            "owes": debt > 0,
        }

    def _stat_block(self, rows: list) -> dict:
        debts = [float(row.get("debt") or 0.0) for row in rows]
        owing = [value for value in debts if value > 0]
        total = sum(owing)
        return {
            "count": str(len(rows)),
            "debtors": str(len(owing)),
            "debtors_raw": len(owing),
            "debt": fmt.compact(total),
            "debt_full": fmt.money(total),
            "debt_raw": total,
            "largest": fmt.money(max(owing) if owing else 0.0),
        }

    def _database(self):
        try:
            return legacy.database()
        except Exception as exc:  # noqa: BLE001
            self._set_error(str(exc))
            self.rejected.emit(str(exc))
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

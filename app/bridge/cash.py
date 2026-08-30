"""The cash drawer and the payments register, behind `app.cash` and `app.payments`.

Two small controllers in one file because they are two views of the same money:
what is in the drawer right now, and every payment that has been recorded against
a debt.

    app.cash        session, movements, open(), close(), add(kind, amount, reason)
    app.payments    load(kind, search, page, pageSize), rows, stats

A CASH SESSION IS A SHIFT, NOT A SETTING
----------------------------------------
pos allows exactly one open session at a time and refuses a second — the drawer is
a physical object. Movements can only be recorded while one is open, which is why
`add()` reports rather than silently queues: a cashier who has not opened the
drawer has to be told, not corrected later.

A REASON IS NOT A NOTE
----------------------
`add()` takes a reason because for an expense or a cash_out it is the only record
of where the money went, and the expense report groups by it — the data model has
no expense categories, so identical reason text *is* the category. Opening and
closing a session used to take a note as well; nothing ever displayed it, so it is
gone along with every other note in this app.
"""

from __future__ import annotations

from PySide6.QtCore import Property, QObject, Signal, Slot

from . import fmt, interop, legacy


class Cash(QObject):
    changed = Signal()
    busyChanged = Signal()
    errorChanged = Signal()

    opened = Signal("QVariant")
    closed = Signal("QVariant")
    recorded = Signal("QVariant")
    rejected = Signal(str)

    #: The three kinds pos accepts, and the only ones add() will pass through.
    KINDS = ("cash_in", "expense", "cash_out")

    def __init__(self, i18n: QObject, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._i18n = i18n
        self._session: dict | None = None
        self._movements: list[dict] = []
        self._totals: dict = {}
        self._sessions: list[dict] = []
        self._busy = False
        self._error = ""

    # =====================================================================
    # STATE
    # =====================================================================
    @Property(bool, notify=busyChanged)
    def busy(self) -> bool:
        return self._busy

    @Property(str, notify=errorChanged)
    def error(self) -> str:
        return self._error

    @Property(bool, notify=changed)
    def isOpen(self) -> bool:
        return self._session is not None

    @Property("QVariant", notify=changed)
    def session(self) -> object:
        return self._session

    @Property("QVariantList", notify=changed)
    def movements(self) -> list:
        return self._movements

    @Property("QVariantMap", notify=changed)
    def totals(self) -> dict:
        return self._totals

    @Property("QVariantList", notify=changed)
    def sessions(self) -> list:
        return self._sessions

    # =====================================================================
    # QUERIES
    # =====================================================================
    @Slot()
    def load(self) -> None:
        database = self._database()
        if database is None:
            return
        self._set_busy(True)
        try:
            current = database.current_cash_session()
            self._session = self._session_view(current) if current else None
            movements = database.fetch_cash_movements(
                current["id"] if current else None)
            self._movements = [self._movement(row)
                               for row in (movements.get("rows") or [])]
            self._totals = self._total_block(movements, current)
            self._sessions = [self._session_view(row)
                              for row in database.fetch_cash_sessions()]
            self._set_error("")
        except Exception as exc:  # noqa: BLE001
            self._set_error(str(exc))
            self._session = None
            self._movements = []
        finally:
            self._set_busy(False)
        self.changed.emit()

    # =====================================================================
    # MUTATIONS
    # =====================================================================
    @Slot("QVariant")
    def openSession(self, opening_balance: object) -> None:
        database = self._database()
        if database is None:
            return
        try:
            result = database.open_cash_session(interop.as_float(opening_balance))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.opened.emit(dict(result))
        self.load()

    @Slot("QVariant")
    def closeSession(self, actual_cash: object) -> None:
        """The count in the drawer, against what the till thinks should be there.
        pos records both and the difference between them — that difference is the
        whole point of closing a session."""
        database = self._database()
        if database is None:
            return
        try:
            result = database.close_cash_session(interop.as_float(actual_cash))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        payload = dict(result)
        payload["difference_text"] = fmt.money(payload.get("difference") or 0.0)
        payload["expected_text"] = fmt.money(payload.get("expected") or 0.0)
        self.closed.emit(payload)
        self.load()

    @Slot(str, "QVariant", str)
    def add(self, kind: str, amount: object, reason: str) -> None:
        if kind not in self.KINDS:
            return
        value = interop.as_float(amount)
        if value <= 0:
            self.rejected.emit(self._i18n.text("amount.error"))
            return
        database = self._database()
        if database is None:
            return
        try:
            result = database.add_cash_movement(kind, value, str(reason or ""))
        except Exception as exc:  # noqa: BLE001
            # "no open cash session" arrives here, and it is the sentence the
            # cashier needs.
            self.rejected.emit(str(exc))
            return
        self.recorded.emit(dict(result))
        self.load()

    @Slot(float, result=str)
    def moneyText(self, value: float) -> str:
        return fmt.money(value)

    # =====================================================================
    # INTERNALS
    # =====================================================================
    def _session_view(self, row: dict) -> dict:
        data = dict(row)
        for key in ("opening_balance", "expected", "actual_cash", "difference",
                    "in_total", "out_total"):
            if key in data:
                data[f"{key}_text"] = fmt.money(data.get(key))
        data["opened_text"] = fmt.when(data.get("opened_at"))
        if data.get("closed_at"):
            data["closed_text"] = fmt.when(data.get("closed_at"))
        return data

    def _movement(self, row: dict) -> dict:
        kind = row.get("type") or ""
        return {
            "id": row["id"],
            "kind": kind,
            "label": self._i18n.text(f"cash.type.{kind}", self._kind_label(kind)),
            "amount": float(row.get("amount") or 0.0),
            "amount_text": fmt.money(row.get("amount")),
            # Why the money moved. A sale movement has no reason of its own, so
            # the data layer substitutes the invoice number and the column is
            # never blank.
            "reason": row.get("reason") or "",
            "when": fmt.when(row.get("created_at")),
            # Money in is money in whatever it is called; everything else leaves
            # the drawer. The page tones the row from this.
            "incoming": kind in ("cash_in", "sale"),
        }

    def _kind_label(self, kind: str) -> str:
        """English for the four movement kinds pos's catalogue does not name."""
        return {
            "sale": "Sale",
            "cash_in": "Cash in",
            "expense": "Expense",
            "cash_out": "Cash out",
        }.get(kind, kind)

    def _total_block(self, movements: dict, current: dict | None) -> dict:
        """fetch_cash_movements carries the open session's own totals under
        `current` — the same numbers _session_totals computed, so this does not
        add them up a second time from the rows."""
        stats = dict(movements.get("current") or {})
        into = float(stats.get("in_total") or 0.0)
        out = float(stats.get("out_total") or 0.0)
        opening = float(stats.get("opening")
                        or (current or {}).get("opening_balance") or 0.0)
        expected = float(stats.get("expected") or (opening + into - out))
        return {
            "in": fmt.money(into),
            "out": fmt.money(out),
            "sales": fmt.money(stats.get("sales") or 0.0),
            "expenses": fmt.money(stats.get("expenses") or 0.0),
            "opening": fmt.money(opening),
            "expected": fmt.money(expected),
            "expected_raw": expected,
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


class Payments(QObject):
    """Every payment recorded against a debt, customer and supplier together.

    pos calls it the unified register, and the reason it is one list is that the
    question is usually "was this paid" rather than "was this paid by a customer".
    """

    rowsChanged = Signal()
    statsChanged = Signal()
    busyChanged = Signal()
    errorChanged = Signal()

    invalidated = Signal()
    rejected = Signal(str)

    def __init__(self, i18n: QObject, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._i18n = i18n
        self._rows: list[dict] = []
        self._stats: dict = {}
        self._total = 0
        self._busy = False
        self._error = ""
        self._query = ("all", "", 1, 100)

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

    @Slot(str, str, int, int)
    def load(self, kind: str, search: str, page: int, page_size: int) -> None:
        database = self._database()
        if database is None:
            return
        self._query = (kind or "all", search or "", max(1, int(page)),
                       int(page_size))
        self._set_busy(True)
        try:
            result = database.fetch_payments(*self._query)
            self._rows = [self._row(row) for row in result["rows"]]
            self._total = int(result["total"])
            stats = dict(result.get("stats") or {})
            customer = float(stats.get("customer_total") or 0.0)
            supplier = float(stats.get("supplier_total") or 0.0)
            self._stats = {
                "count": str(int(stats.get("count") or 0)),
                "customer": fmt.compact(customer),
                "customer_full": fmt.money(customer),
                "supplier": fmt.compact(supplier),
                "supplier_full": fmt.money(supplier),
                "amount": fmt.compact(customer + supplier),
                "amount_full": fmt.money(customer + supplier),
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

    @Slot(int, str)
    def remove(self, payment_id: int, kind: str) -> None:
        """Deleting a payment gives the debt back — pos's delete_*_payment
        restores exactly what the payment reduced, which is why the kind has to
        travel with the id."""
        database = self._database()
        if database is None:
            return
        try:
            if kind == "supplier":
                database.delete_supplier_payment(int(payment_id))
            else:
                database.delete_customer_payment(int(payment_id))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.invalidated.emit()
        self.reload()

    def _row(self, row: dict) -> dict:
        kind = row.get("kind") or "customer"
        return {
            "id": row["id"],
            "kind": kind,
            "kind_label": self._i18n.text(
                f"payments.kind.{kind}",
                "Supplier" if kind == "supplier" else "Customer"),
            "party": row.get("party") or "",
            "amount_text": fmt.money(row.get("amount")),
            "when": fmt.when(row.get("created_at")),
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

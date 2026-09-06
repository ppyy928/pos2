"""Sales, behind `app.sales`.

    read      busy, error, total, stats, rows, returnReasons
    call      load(search, paymentType, page, pageSize, dateFrom, dateTo),
              sale(id), createReturn(saleId, items, reason),
              deleteImpact(id), remove(id)
    emits     invalidated(), returned(result), deleted(number), rejected(message)

The list is pos's `fetch_sales` with every figure formatted and the payment type
left as its raw key — the table draws it as a toned chip, and the tone is decided
from that key rather than from a translated word.

A RETURN IS PRICED BY THE SALE, NOT BY THE SCREEN
--------------------------------------------------
`create_return` reads the price from the stored sale item and ignores anything the
caller sends, which is why this passes only product ids and quantities. It also
knows what has already been returned, so a second return of the same line cannot
exceed what was sold — the dialog shows those ceilings, the database enforces
them.
"""

from __future__ import annotations

from PySide6.QtCore import (
    Property,
    QObject,
    QRunnable,
    QThreadPool,
    Signal,
    Slot,
)

from .. import diagnostics
from . import fmt, interop, legacy


class Sales(QObject):
    rowsChanged = Signal()
    statsChanged = Signal()
    busyChanged = Signal()
    errorChanged = Signal()

    invalidated = Signal()
    returned = Signal("QVariant")
    saved = Signal("QVariant")
    #: The sale is gone, and its number so the page can say which. Separate from
    #: `saved`: a page that reloads on both still wants to word them differently.
    deleted = Signal(str)
    rejected = Signal(str)
    #: A receipt reached the printer, or did not and says why. Separate from
    #: rejected(), because a failed print does not undo a completed sale and
    #: must not read like it did.
    printed = Signal(str)
    printFailed = Signal(str)
    #: Private: the worker thread's way home.
    _finished = Signal(int, bool, str)

    #: The return reasons are translated sentences, so the list is not constant:
    #: a language change has to rebuild it like every other visible string.
    reasonsChanged = Signal()

    def __init__(self, i18n: QObject, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._i18n = i18n
        i18n.languageChanged.connect(self.reasonsChanged)
        self._rows: list[dict] = []
        self._stats: dict = {}
        self._total = 0
        self._busy = False
        self._error = ""
        self._query = ("", "", 1, 100, "", "", 0)
        self._task = None
        self._finished.connect(self._settle)

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
    @Slot(str, str, int, int, str, str)
    @Slot(str, str, int, int, str, str, int)
    def load(self, search: str, payment_type: str, page: int, page_size: int,
             date_from: str, date_to: str, customer_id: int = 0) -> None:
        """One page of sales.

        `customer_id` is the exact party rather than a name that resembles one, and it
        is last with a default so the six-argument callers written before it keep
        working — `reload()` replays whatever `_query` holds.
        """
        database = self._database()
        if database is None:
            return
        self._query = (search or "", payment_type or "", max(1, int(page)),
                       int(page_size), date_from or "", date_to or "",
                       int(customer_id or 0))
        self._set_busy(True)
        try:
            result = database.fetch_sales(
                self._query[0], self._query[1] or None, self._query[2],
                self._query[3], self._query[4] or None, self._query[5] or None,
                self._query[6] or None,
            )
            self._rows = [self._row(row) for row in result["rows"]]
            self._total = int(result["total"])
            self._stats = self._stat_block(result.get("stats") or {})
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
    def sale(self, sale_id: int) -> object:
        """One sale, with its lines and what is still returnable on each.

        `returnable` is the quantity sold minus everything already returned: the
        dialog needs it as a number to cap a spin box, and the database applies
        the same rule again when the return is written.
        """
        database = self._database()
        if database is None:
            return None
        try:
            row = database.fetch_sale(int(sale_id))
        except Exception as exc:  # noqa: BLE001
            self._set_error(str(exc))
            return None
        if row is None:
            return None

        sale = dict(row)
        returned = dict(sale.get("returned") or {})
        total = float(sale.get("total") or 0.0)
        paid = float(sale.get("paid") or 0.0)

        sale["items"] = [
            {
                "product_id": item.get("product_id"),
                "name": item["name"],
                "qty": float(item["qty"]),
                "qty_text": fmt.qty(item["qty"]),
                # The raw unit price as well as the formatted one: the return
                # dialog multiplies it to show what a refund would come to before
                # the database prices the return itself.
                "price": float(item.get("price") or 0.0),
                "price_text": fmt.money(item["price"]),
                "total_text": fmt.money(item.get("total")),
                "returned": float(returned.get(item.get("product_id"), 0.0)),
                "returnable": max(
                    0.0,
                    float(item["qty"]) - float(returned.get(item.get("product_id"), 0.0)),
                ),
            }
            for item in (sale.get("items") or [])
        ]
        sale["text"] = {
            "total": fmt.money(total),
            "paid": fmt.money(paid),
            "due": fmt.money(max(0.0, total - paid)),
            "when": fmt.when(sale.get("created_at")),
            "payment": self._payment_label(sale.get("payment_type")),
        }
        return sale

    # =====================================================================
    # PRINTING
    # =====================================================================
    @Property(bool, constant=True)
    def autoPrint(self) -> bool:
        """Whether a sale prints itself. pos's `receipt.auto_print`, read when
        asked rather than cached: it is a setting somebody changes on the settings
        screen while the till is open."""
        database = self._database()
        if database is None:
            return False
        try:
            return database.get_setting("receipt.auto_print", "1") == "1"
        except Exception:  # noqa: BLE001
            diagnostics.log.debug("receipt.auto_print unreadable", exc_info=True)
            return False

    @Slot(int)
    @Slot(int, str)
    def printReceipt(self, sale_id: int, cashier: str = "") -> None:
        """Render and print one sale, off the GUI thread.

        A thermal printer is a device: it can be missing, out of paper, or simply
        slow, and none of that should freeze a till that has already taken the
        money. So this returns immediately and the answer arrives as printed() or
        printFailed().
        """
        if not sale_id:
            return
        self._task = _PrintTask(self, int(sale_id), str(cashier or ""))
        self._task.setAutoDelete(False)
        QThreadPool.globalInstance().start(self._task)

    def _settle(self, sale_id: int, ok: bool, error: str) -> None:
        if error:
            self.printFailed.emit(error)
        elif not ok:
            # print_sale_by_id answers False when the sale is not there, which is
            # a different problem from a printer that refused — and one that
            # raised nothing on the pool thread, so this is its only record.
            diagnostics.log.warning(
                "receipt print returned no confirmation: sale_id=%s", sale_id
            )
            self.printFailed.emit(self._i18n.text("toast.print_failed"))
        else:
            self.printed.emit(str(sale_id))

    @Slot(float, result=str)
    def moneyText(self, value: float) -> str:
        """For a figure the return dialog worked out while the operator types.
        The refund that is actually written comes from the sale's own prices."""
        return fmt.money(value)

    # =====================================================================
    # RETURNS
    # =====================================================================
    #: The reasons a return may carry, in the order the dialog offers them.
    #: Codes here, sentences in the string catalogue (`return.reason.<code>`).
    #:
    #: A fixed list rather than a text field, because the field was answering the
    #: wrong question: "damaged", "Damaged", "damage", "abîmé" and "تالف" are one
    #: reason typed five ways, which makes the reason column on the returns page
    #: and in the returns report unreadable within a week. Twelve choices cover
    #: what a shop actually sees; the thirteenth reason is the empty one.
    RETURN_REASONS = (
        "damaged",
        "expired",
        "wrong_item",
        "wrong_qty",
        "faulty",
        "quality",
        "opened",
        "changed_mind",
        "not_needed",
        "wrong_price",
        "double_rung",
        "exchange",
    )

    @Property("QVariantList", notify=reasonsChanged)
    def returnReasons(self) -> list:
        """The dropdown's model. First entry empty, always.

        The empty one is first and is what the dialog opens on: a return with no
        stated reason is a normal return — the goods and the money are the record
        — and a required reason only teaches the operator to pick whatever is at
        the top. It is also what every existing return has, so the list does not
        rewrite history.

        Sentences, not codes, because a sentence is what gets stored: the returns
        page, the return's own details dialog and the returns report all print
        `Return.reason` exactly as it was written, the same way a cash movement's
        reason and a stock adjustment's reason are printed. Storing codes would
        mean translating in three more places and would leave every return
        recorded before today as unreadable text beside a set of tidy codes.

        The cost is stated plainly: a shop that switches language keeps the
        reasons it already recorded in the language they were recorded in. That is
        true of every other reason field in this application.
        """
        return ["", *(self._i18n.text(f"return.reason.{code}")
                      for code in self.RETURN_REASONS)]

    @Slot(int, "QVariant", str)
    def createReturn(self, sale_id: int, items: object, reason: str) -> None:
        """`items` is [{product_id, qty}] — quantities only, prices are the
        sale's own."""
        lines = []
        raw = items
        to_variant = getattr(raw, "toVariant", None)
        if callable(to_variant):
            raw = to_variant()
        for entry in (raw or []):
            row = interop.as_dict(entry) if not isinstance(entry, dict) else entry
            qty = interop.as_float(row.get("qty"))
            if qty > 0 and row.get("product_id") is not None:
                lines.append({"product_id": int(row["product_id"]), "qty": qty})

        if not lines:
            self.rejected.emit(self._i18n.text("return.nothing",
                                               "Nothing is being returned."))
            return

        database = self._database()
        if database is None:
            return
        try:
            result = database.create_return(int(sale_id), lines, str(reason or ""))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.returned.emit(dict(result))
        self.invalidated.emit()

    # =====================================================================
    # EDITING A SALE
    # =====================================================================
    @Slot("QVariant", int)
    def save(self, data: object, sale_id: int) -> None:
        """Rewrite a completed sale: its lines, what was paid, and whose it is.

        `data` is `{items: [{product_id, name, qty, price, discount}], paid, customer_id}`
        — the whole document, the way `Purchases.save` takes one. `db.update_sale`
        reverses the old lines' stock, applies the new ones, reconciles the customer's
        debt by the DELTA between the old and new obligation, replaces the linked cash
        movement rather than adding a second one, and stamps `updated_by`.

        THE PAID FIGURE REPLACES, IT DOES NOT ADD

        `paid` is the invoice's new total paid, not an extra payment. That is
        `update_sale`'s stated contract (db.py:1954-1957) and it is what stops repeated
        edits from double-counting. The payment TYPE is then derived, not chosen:
        settled is cash, nothing paid is debt, anything between is partial.

        WHY A RETURNED SALE IS REFUSED

        `update_sale` recomputes the total from the submitted lines and reverses the
        old lines' stock unconditionally — and it knows nothing about `ReturnItem`.
        Editing a sale that has already been returned against would put the returned
        quantity back into stock a second time and leave `create_return`'s remaining
        ceilings pointing at quantities that no longer exist. Nothing in the database
        blocks that, so it is blocked here, before anything is written.
        """
        values = interop.as_dict(data)

        raw_items = values.get("items") or []
        to_variant = getattr(raw_items, "toVariant", None)
        if callable(to_variant):
            raw_items = to_variant()

        items = []
        for entry in raw_items:
            row = interop.as_dict(entry) if not isinstance(entry, dict) else entry
            qty = interop.as_float(row.get("qty"))
            name = str(row.get("name") or "").strip()
            if qty <= 0 or not name:
                continue
            items.append({
                "product_id": row.get("product_id") or None,
                "name": name,
                "qty": qty,
                "price": interop.as_float(row.get("price")),
                "discount": interop.as_float(row.get("discount")),
            })

        if not items:
            self.rejected.emit(self._i18n.text("sales.no_items",
                                               "A sale needs at least one line."))
            return

        database = self._database()
        if database is None:
            return

        try:
            existing = database.fetch_sale(int(sale_id))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        if existing is None:
            self.rejected.emit(self._i18n.text("sales.missing",
                                               "That sale no longer exists."))
            return

        # Counted straight off the `returns` table, not read from the payload above.
        # `db.fetch_sale` carries no returned quantity — the per-line `returned` and
        # `returnable` fields belong to `Sales.sale()`, which adds them for the details
        # dialog. Trusting the raw row here meant `float(None or 0.0)`, so the guard
        # read zero for every sale and let a returned one through.
        try:
            with database.SessionFactory() as session:
                returns = session.execute(
                    database.select(database.func.count(database.Return.id))
                    .where(database.Return.sale_id == int(sale_id))
                ).scalar() or 0
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return

        if returns > 0:
            self.rejected.emit(self._i18n.text(
                "sales.edit_returned",
                "This sale has a return against it and can no longer be edited. "
                "Delete the return first."))
            return

        customer_id = values.get("customer_id")
        customer_id = int(customer_id) if customer_id else None

        try:
            result = database.update_sale(
                int(sale_id), items,
                interop.as_float(values.get("paid")),
                customer_id,
            )
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return

        self.saved.emit(dict(result))
        self.invalidated.emit()
        self.reload()

    # =====================================================================
    # DELETING ONE
    # =====================================================================
    @Slot(int, result="QVariant")
    def deleteImpact(self, sale_id: int) -> object:
        """What deleting this sale would do — read before the operator is asked.

        A confirmation that says "are you sure" asks the operator to remember what
        the invoice contained. This hands the figures back so the dialog can state
        them: the lines, the total, what comes out of the drawer and what comes off
        the customer's account. `returns` is the blocker rather than a warning — the
        data layer refuses while it is set.
        """
        database = self._database()
        if database is None:
            return None
        try:
            impact = database.sale_delete_impact(int(sale_id))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return None
        if not impact:
            self.rejected.emit(self._i18n.text("sales.missing",
                                               "That sale no longer exists."))
            return None
        return {
            "number": impact["number"],
            "lines": int(impact["lines"]),
            "units": fmt.qty(impact["units"]),
            "total": fmt.money(impact["total"]),
            "paid": fmt.money(impact["paid"]),
            "debt": fmt.money(impact["debt"]),
            "customer": impact["customer"],
            # Raw as well as formatted: the dialog hides a row that is zero, and
            # "0,00 DA" is not falsy.
            "paid_value": float(impact["paid"]),
            "debt_value": float(impact["debt"]),
            "returns": int(impact["returns"]),
        }

    @Slot(int)
    def remove(self, sale_id: int) -> None:
        """Delete a sale and everything it did: stock back on, debt off, drawer
        movement removed.

        The return guard is the data layer's — `delete_sale` raises rather than
        trusting a caller to have checked — and its refusal is turned into the same
        sentence the edit path uses, because it is the same situation and the same
        remedy: delete the return first.
        """
        database = self._database()
        if database is None:
            return
        try:
            result = database.delete_sale(int(sale_id))
        except Exception as exc:  # noqa: BLE001
            message = str(exc)
            if "has returns" in message:
                message = self._i18n.text(
                    "sales.delete_returned",
                    "This sale has a return against it. Delete the return first.")
            elif "not found" in message:
                message = self._i18n.text("sales.missing",
                                          "That sale no longer exists.")
            self.rejected.emit(message)
            return
        self.deleted.emit(str(result.get("number") or ""))
        self.invalidated.emit()
        self.reload()

    # =====================================================================
    # INTERNALS
    # =====================================================================
    def _row(self, row: dict) -> dict:
        walk_in = self._i18n.text("pos.walk_in")
        return {
            "id": row["id"],
            "number": row["number"],
            "when": fmt.when(row.get("created_at")),
            "customer": row.get("customer") or walk_in,
            # The raw key, so the table can tone it; the label comes with it.
            "payment_type": row.get("payment_type") or "",
            "payment": self._payment_label(row.get("payment_type")),
            "total": fmt.money(row.get("total")),
            "paid": fmt.money(row.get("paid")),
            "due": fmt.money(max(0.0, float(row.get("total") or 0.0)
                                 - float(row.get("paid") or 0.0))),
        }

    def _stat_block(self, stats: dict) -> dict:
        return {
            "count": str(int(stats.get("count") or 0)),
            "total": fmt.compact(stats.get("total") or 0.0),
            "total_full": fmt.money(stats.get("total") or 0.0),
            "cash": fmt.compact(stats.get("cash") or 0.0),
            "cash_full": fmt.money(stats.get("cash") or 0.0),
            "debt": fmt.compact(stats.get("debt") or 0.0),
            "debt_full": fmt.money(stats.get("debt") or 0.0),
            "debt_raw": float(stats.get("debt") or 0.0),
        }

    def _payment_label(self, key: object) -> str:
        return self._i18n.text(f"pay.type.{key}") if key else ""

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
        # Logged before the dedup: the same sentence twice is two failures, and
        # the traceback — still live inside the emitting except block — is what
        # str(exc) threw away. Two severities, same test as the rejected tap:
        # a live exception is an ERROR, a bare sentence ("Nothing to print.")
        # is a refusal the operator can act on and stays DEBUG. An empty
        # message clears the banner and is not a failure at all.
        if message:
            if diagnostics.active_exc():
                diagnostics.log.error(
                    "screen error: %s", message, exc_info=True
                )
            else:
                diagnostics.log.debug("screen error: %s", message)
        if self._error == message:
            return
        self._error = message
        self.errorChanged.emit()


class Returns(QObject):
    """Goods that came back, behind `app.returns`.

        read      busy, error, total, stats, rows
        call      load(search, page, pageSize, dateFrom, dateTo), returnAt(index),
                  items(returnId), remove(returnId)
        emits     invalidated(), rejected(message)

    A separate screen from Sales, because a return is a document of its own with its
    own number — pos numbers them RET-0001 — and because "what came back this week"
    is a question a shop asks on its own.

    DELETING ONE IS AN UNDO, NOT A TIDY-UP
    --------------------------------------
    `delete_return` reverses exactly what the return did: the restored stock goes
    back out and, on a credit sale, the refunded amount goes back onto the
    customer's debt. So the page confirms it by name and says what will happen.
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
        self._query = ("", 1, 100, "", "")

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

    @Slot(str, int, int, str, str)
    def load(self, search: str, page: int, page_size: int, date_from: str,
             date_to: str) -> None:
        database = self._database()
        if database is None:
            return
        self._query = (search or "", max(1, int(page)), int(page_size),
                       date_from or "", date_to or "")
        self._set_busy(True)
        try:
            result = database.fetch_returns(
                self._query[0], self._query[1], self._query[2],
                self._query[3] or None, self._query[4] or None,
            )
            self._rows = [self._row(row) for row in result["rows"]]
            self._total = int(result["total"])
            stats = dict(result.get("stats") or {})
            self._stats = {
                "count": str(int(stats.get("count") or 0)),
                "total": fmt.compact(stats.get("total") or 0.0),
                "total_full": fmt.money(stats.get("total") or 0.0),
                "total_raw": float(stats.get("total") or 0.0),
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
    def returnAt(self, index: int) -> object:
        if 0 <= index < len(self._rows):
            return self._rows[index]
        return None

    @Slot(int, result="QVariantList")
    def items(self, return_id: int) -> list:
        """The lines of one return. A slot rather than a property: nothing on the
        list shows them, so they are fetched when a detail is opened."""
        database = self._database()
        if database is None:
            return []
        try:
            rows = database.fetch_return_items(int(return_id))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return []
        return [
            {
                "name": row["name"],
                "qty_text": fmt.qty(row.get("qty")),
                "price_text": fmt.money(row.get("price")),
                "total_text": fmt.money(row.get("total")),
            }
            for row in rows
        ]

    @Slot(int)
    def remove(self, return_id: int) -> None:
        database = self._database()
        if database is None:
            return
        try:
            database.delete_return(int(return_id))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.invalidated.emit()
        self.reload()

    def _row(self, row: dict) -> dict:
        return {
            "id": row["id"],
            "number": row["number"],
            "sale": row.get("sale_number") or "",
            "when": fmt.when(row.get("created_at")),
            "reason": row.get("reason") or "",
            "total": fmt.money(row.get("total")),
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
        # Logged before the dedup: the same sentence twice is two failures, and
        # the traceback — still live inside the emitting except block — is what
        # str(exc) threw away. Two severities, same test as the rejected tap:
        # a live exception is an ERROR, a bare sentence ("Nothing to print.")
        # is a refusal the operator can act on and stays DEBUG. An empty
        # message clears the banner and is not a failure at all.
        if message:
            if diagnostics.active_exc():
                diagnostics.log.error(
                    "screen error: %s", message, exc_info=True
                )
            else:
                diagnostics.log.debug("screen error: %s", message)
        if self._error == message:
            return
        self._error = message
        self.errorChanged.emit()


class _PrintTask(QRunnable):
    """One receipt, on a pool thread."""

    def __init__(self, sales: Sales, sale_id: int, cashier: str) -> None:
        super().__init__()
        self._sales = sales
        self._sale_id = sale_id
        self._cashier = cashier

    def run(self) -> None:
        try:
            printing = legacy.printing()
            ok = printing.print_sale_by_id(self._sale_id, cashier=self._cashier)
        except Exception as exc:  # noqa: BLE001
            # A missing printer, a missing font, a missing Pillow: all of them are
            # a sentence for the operator rather than a crashed thread. The
            # traceback belongs in errors.log — a pool thread has no stderr the
            # operator will ever see.
            diagnostics.log.exception(
                "receipt print failed: sale_id=%s", self._sale_id
            )
            self._sales._finished.emit(self._sale_id, False, str(exc))
            return
        self._sales._finished.emit(self._sale_id, bool(ok), "")

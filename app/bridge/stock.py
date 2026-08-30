"""app.stock — the ledger, the stocktake and the expiry register.

    app.stock   movements, movementsTotal, load(productId, kind, page)
                sheet, hasSheet, openCount(categoryId, reason),
                setCounted(productId, counted), postCount(), cancelCount()
                batches(productId), saveBatch(...), deleteBatch(id),
                writeOff(batchId, reason)
                expiry, loadExpiry(days)

WHY THESE THREE LIVE TOGETHER

They are one subject seen three ways. A movement is what happened to the stock, a
stocktake is a batch of movements the shelf dictated, and an expiry write-off is a
movement with a date behind it. All three read and write the same two tables, and
splitting them across three controllers would mean three copies of "reload after a
write" and three chances for one of them to show a stale figure after another one
moved the stock.

WHY THE SHEET IS A WHOLE PAYLOAD AND NOT A ROW MODEL

A stocktake is answered as a unit: the summary at the top — lines, left to count,
short, variance value — is arithmetic over every line, not over the page on screen.
`sheet` therefore carries its items and its summary together, and one `setCounted`
brings both back in step. A count of 229 lines is one round trip per keystroke on a
local SQLite file, which is cheaper than the bookkeeping a partial model would
need to keep the totals honest.
"""

from __future__ import annotations

from typing import Any

from PySide6.QtCore import Property, QObject, Signal, Slot

from . import fmt, interop, legacy

#: What a movement row's `kind` is rendered as. The keys are the ledger's own, so a
#: kind added in the data layer shows up here as its raw name rather than blank —
#: visible, and obviously unfinished, which is the failure mode to prefer.
_KIND_KEYS = {
    "initial": "stock.kind.initial",
    "sale": "stock.kind.sale",
    "sale_edit": "stock.kind.sale_edit",
    "return": "stock.kind.return",
    "purchase": "stock.kind.purchase",
    "purchase_delete": "stock.kind.purchase_delete",
    "return_delete": "stock.kind.return_delete",
    "adjust": "stock.kind.adjust",
    "count": "stock.kind.count",
    "expiry": "stock.kind.expiry",
}

#: A movement's tone in a table: stock arriving is good news, stock leaving for a
#: reason nobody chose (expiry, a shortage found by a count) is not.
_KIND_TONES = {
    "initial": "info",
    "sale": "",
    "sale_edit": "info",
    "return": "success",
    "purchase": "success",
    "purchase_delete": "warning",
    "return_delete": "warning",
    "adjust": "warning",
    "count": "info",
    "expiry": "danger",
}


class Stock(QObject):
    """One controller for everything that moves a quantity."""

    movementsChanged = Signal()
    sheetChanged = Signal()
    scopeChanged = Signal()
    expiryChanged = Signal()
    posted = Signal("QVariant")
    rejected = Signal(str)
    #: Stock moved: the catalogue, the till and the dashboard are all stale.
    invalidated = Signal()

    def __init__(self, i18n, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._i18n = i18n
        self._movements: list[dict] = []
        self._movements_total = 0
        self._sheet: dict[str, Any] = {}
        self._scope = 0
        self._expiry: dict[str, Any] = {}

    # =====================================================================
    # THE LEDGER
    # =====================================================================
    @Property("QVariantList", notify=movementsChanged)
    def movements(self) -> list:
        return self._movements

    @Property(int, notify=movementsChanged)
    def movementsTotal(self) -> int:
        return self._movements_total

    @Slot()
    @Slot(int)
    @Slot(int, str)
    @Slot(int, str, int)
    @Slot(int, str, int, int)
    def load(self, product_id: int = 0, kind: str = "",
             page: int = 1, page_size: int = 50) -> None:
        database = self._database()
        if database is None:
            return
        try:
            payload = database.fetch_stock_movements(
                int(product_id) or None, str(kind or ""), int(page), int(page_size)
            )
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self._movements = [self._movement(r) for r in payload.get("rows", [])]
        self._movements_total = int(payload.get("total") or 0)
        self.movementsChanged.emit()

    def _movement(self, row: dict) -> dict:
        qty = float(row.get("qty") or 0.0)
        kind = str(row.get("kind") or "")
        ref_table = str(row.get("ref_table") or "")
        return {
            "id": row.get("id"),
            "product_id": row.get("product_id"),
            "product": row.get("product") or "",
            "kind": kind,
            "kind_text": self._i18n.text(_KIND_KEYS.get(kind, ""), kind),
            "kind_tone": _KIND_TONES.get(kind, ""),
            # Signed, and shown signed. "-4" is the whole content of the cell: a
            # ledger read for a discrepancy is scanned down the sign column.
            "qty": qty,
            "qty_text": ("+" if qty > 0 else "") + fmt.qty(qty),
            "in": qty > 0,
            "after_text": fmt.qty(float(row.get("stock_after") or 0.0)),
            "reason": row.get("reason") or "",
            # The document, named rather than numbered: "sales #182" is a row id an
            # operator cannot use, so the table shows the kind of paper it was.
            "ref": self._ref_text(ref_table, row.get("ref_id")),
            "when": fmt.when(row.get("created_at")),
            "by": row.get("created_by") or "",
        }

    def _ref_text(self, table: str, ref_id: object) -> str:
        if not table or ref_id is None:
            return ""
        database = self._database()
        if database is None:
            return ""
        try:
            if table == "sales":
                sale = database.fetch_sale(int(ref_id))
                return str(sale.get("number") or "") if sale else ""
            if table == "purchase_invoices":
                invoice = database.fetch_purchase_invoice(int(ref_id))
                return str(invoice.get("number") or "") if invoice else ""
            if table == "stock_counts":
                sheet = database.fetch_stock_count(int(ref_id))
                return str(sheet.get("number") or "") if sheet else ""
        except Exception:  # noqa: BLE001
            return ""
        return ""

    # =====================================================================
    # THE STOCKTAKE
    # =====================================================================
    @Property("QVariantMap", notify=sheetChanged)
    def sheet(self) -> dict:
        return self._sheet

    @Property(bool, notify=sheetChanged)
    def hasSheet(self) -> bool:
        return bool(self._sheet.get("id"))

    def _get_scope(self) -> int:
        return self._scope

    def _set_scope(self, value: int) -> None:
        value = int(value or 0)
        if self._scope == value:
            return
        self._scope = value
        self.scopeChanged.emit()

    #: Which category the NEXT sheet covers. Only decides what "Add all" means and
    #: what the browse list is filtered to — lines are added one at a time either
    #: way, so choosing wrong costs nothing.
    scope = Property(int, _get_scope, _set_scope, notify=scopeChanged)

    @Slot()
    def loadSheet(self) -> None:
        database = self._database()
        if database is None:
            return
        try:
            payload = database.current_stock_count()
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self._sheet = self._decorate(payload or {})
        self.sheetChanged.emit()

    @Slot(result=bool)
    def ensureSheet(self) -> bool:
        """The open sheet, creating one if there is none.

        WHY THE SHEET IS CREATED LAZILY

        The screen used to open on a gate — "no stocktake is open" with a Start
        button — which made the first thing an operator saw a state rather than the
        work. Now the sheet, the cards and the table are always on screen and the
        document appears when the first line does.

        Not on opening the dialog, though: that would burn a CNT number every time
        somebody looked at the screen, and a numbered document nobody used is a hole
        in an audit trail. The first scan is the moment a count actually begins.
        """
        if self._sheet.get("id"):
            return True
        database = self._database()
        if database is None:
            return False
        try:
            database.open_stock_count(self._scope or None, "")
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return False
        self.loadSheet()
        return bool(self._sheet.get("id"))

    @Slot()
    @Slot(int)
    @Slot(int, str)
    def openCount(self, category_id: int = 0, reason: str = "") -> None:
        """Start a sheet explicitly. `ensureSheet` is what the screen uses; this
        stays for a caller that wants a scope and a reason recorded up front."""
        database = self._database()
        if database is None:
            return
        try:
            database.open_stock_count(int(category_id) or None, str(reason or ""))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.loadSheet()

    @Slot(int)
    @Slot(int, "QVariant")
    def addLine(self, product_id: int, counted: object = None) -> None:
        """Put a product on the sheet, with or without a figure.

        The whole interaction model: the operator is at a shelf, finds or scans what
        is in front of them, and the line appears with its book figure frozen at that
        moment. Scanning the same product twice does not open a second line. Creates
        the sheet if this is the first line.
        """
        database = self._database()
        if database is None or not self.ensureSheet():
            return
        text = "" if counted is None else str(counted).strip()
        value = None if text == "" else interop.as_float(text)
        try:
            database.add_count_line(int(self._sheet["id"]), int(product_id), value)
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.loadSheet()

    @Slot(str, result="QVariant")
    def addByCode(self, code: str) -> object:
        """Resolve a scanned or typed code and put it on the sheet.

        Returns the product it landed on, or null when the code matched nothing — a
        scanner burst that hits nothing has to say so, because the operator is looking
        at the shelf and not at the screen.
        """
        database = self._database()
        if database is None:
            return None
        digits = str(code or "").strip()
        if not digits:
            return None
        try:
            hit = database.lookup_barcode(digits)
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return None
        if hit is None:
            return None
        self.addLine(int(hit["id"]))
        return {"id": hit["id"], "name": hit["name"]}

    @Slot(int)
    def removeLine(self, product_id: int) -> None:
        database = self._database()
        if database is None or not self._sheet.get("id"):
            return
        try:
            database.remove_count_line(int(self._sheet["id"]), int(product_id))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.loadSheet()

    @Slot()
    def fillSheet(self) -> None:
        """Add every product in scope that is not on the sheet yet — the annual
        inventory case, where nothing missed is the point."""
        database = self._database()
        if database is None or not self.ensureSheet():
            return
        try:
            database.fill_count_sheet(int(self._sheet["id"]))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.loadSheet()

    @Slot(str, result="QVariantList")
    @Slot(str, int, result="QVariantList")
    def find(self, search: str, limit: int = 25) -> list:
        """Products matching a name or a barcode, for a ProductFinder.

        `stock_text` travels with each row because the finder draws it: what is on
        the shelf is the one figure that matters when the picker sits over a
        stocktake or a movement ledger.
        """
        database = self._database()
        if database is None:
            return []
        try:
            rows = database.find_products(str(search or ""), int(limit))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return []
        out = []
        for row in rows:
            unit = row.get("unit") or ""
            out.append({
                "id": row["id"],
                "name": row.get("name") or "",
                "barcode": row.get("barcode") or "",
                "category": row.get("category") or "",
                "stock": float(row.get("stock") or 0.0),
                "stock_text": f"{fmt.qty(row.get('stock'))} {unit}".strip(),
                # What the shop last paid for it. The delivery screen seeds a new
                # line with this rather than with zero: a delivery is mostly the same
                # goods at the same cost, and a figure the operator overwrites when it
                # changed is fewer keystrokes than one they must type every time.
                "cost": float(row.get("purchase_price") or 0.0),
                "price": float(row.get("sale_price") or 0.0),
            })
        return out

    @Slot(int, "QVariant")
    def setCounted(self, product_id: int, counted: object) -> None:
        """Record one shelf figure. An empty string un-counts the line.

        Un-counting matters: an operator who typed into the wrong row needs a way
        back to "not counted yet", which is not the same as zero — and zero is the
        finding a stocktake exists to catch.
        """
        database = self._database()
        if database is None or not self._sheet.get("id"):
            return
        text = "" if counted is None else str(counted).strip()
        value = None if text == "" else interop.as_float(text)
        try:
            database.set_counted(int(self._sheet["id"]), int(product_id), value)
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.loadSheet()

    @Slot()
    def postCount(self) -> None:
        database = self._database()
        if database is None or not self._sheet.get("id"):
            return
        try:
            result = database.post_stock_count(int(self._sheet["id"]))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        payload = dict(result)
        payload["value_text"] = fmt.money(payload.get("value") or 0.0)
        self._sheet = {}
        self.sheetChanged.emit()
        self.posted.emit(payload)
        self.invalidated.emit()

    @Slot()
    def cancelCount(self) -> None:
        database = self._database()
        if database is None or not self._sheet.get("id"):
            return
        try:
            database.cancel_stock_count(int(self._sheet["id"]))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self._sheet = {}
        self.sheetChanged.emit()

    def _decorate(self, sheet: dict) -> dict:
        if not sheet:
            return {}
        out = dict(sheet)
        items = []
        for row in sheet.get("items") or []:
            item = dict(row)
            counted = item.get("counted")
            variance = item.get("variance")
            item["expected_text"] = fmt.qty(float(item.get("expected") or 0.0))
            item["counted_text"] = "" if counted is None else fmt.qty(float(counted))
            item["variance_text"] = (
                self._i18n.text("count.uncounted", "not counted")
                if variance is None
                else ("+" if variance > 0 else "") + fmt.qty(variance)
            )
            # Three states, three tones: not counted yet is muted, a match is
            # quiet, and only a real discrepancy is coloured.
            item["tone"] = ("" if variance is None
                            else "danger" if variance < 0
                            else "success" if variance > 0 else "")
            item["counted_yet"] = counted is not None
            items.append(item)
        out["items"] = items
        summary = dict(sheet.get("summary") or {})
        summary["variance_value_text"] = fmt.money(summary.get("variance_value") or 0.0)
        out["summary"] = summary
        return out

    # =====================================================================
    # EXPIRY AND BATCHES
    # =====================================================================
    @Property("QVariantMap", notify=expiryChanged)
    def expiry(self) -> dict:
        return self._expiry

    @Slot()
    @Slot(int)
    def loadExpiry(self, days: int = 30) -> None:
        database = self._database()
        if database is None:
            return
        try:
            payload = database.report_expiry(int(days) or 30)
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        out = dict(payload)
        for key in ("expired", "soon"):
            out[key] = [self._batch_row(r) for r in payload.get(key) or []]
        summary = dict(payload.get("summary") or {})
        summary["expired_value_text"] = fmt.money(summary.get("expired_value") or 0.0)
        summary["soon_value_text"] = fmt.money(summary.get("soon_value") or 0.0)
        out["summary"] = summary
        self._expiry = out
        self.expiryChanged.emit()

    def _batch_row(self, row: dict) -> dict:
        item = dict(row)
        item["qty_text"] = fmt.qty(float(item.get("qty") or 0.0))
        item["value_text"] = fmt.money(item.get("value") or 0.0)
        days = item.get("days_left")
        item["days_text"] = "" if days is None else str(int(days))
        item["batch_code"] = item.get("batch_code") or ""
        return item

    @Slot(int, result="QVariantList")
    def batches(self, product_id: int) -> list:
        database = self._database()
        if database is None:
            return []
        try:
            rows = database.fetch_batches(int(product_id))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return []
        out = []
        for row in rows:
            item = dict(row)
            item["qty_text"] = fmt.qty(float(item.get("qty") or 0.0))
            item["cost_text"] = fmt.money(item.get("unit_cost") or 0.0)
            out.append(item)
        return out

    @Slot("QVariant")
    def saveBatch(self, values: object) -> None:
        """Add or correct one dated lot: {product_id, expiry, qty, batch_code,
        unit_cost, id?}.

        Deliberately does not move stock. A shop typing in the dates it already has
        on the shelf must not double its inventory by doing so; moving a quantity is
        what the stock adjustment is for, and keeping the two apart is what makes
        both safe to use.
        """
        row = interop.as_dict(values) or {}
        database = self._database()
        if database is None:
            return
        try:
            database.save_batch(
                int(row.get("product_id") or 0),
                str(row.get("expiry") or ""),
                interop.as_float(row.get("qty")),
                str(row.get("batch_code") or ""),
                interop.as_float(row.get("unit_cost")),
                int(row["id"]) if row.get("id") else None,
            )
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.invalidated.emit()

    @Slot(int)
    def deleteBatch(self, batch_id: int) -> None:
        database = self._database()
        if database is None:
            return
        try:
            database.delete_batch(int(batch_id))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.invalidated.emit()

    @Slot(int)
    @Slot(int, str)
    def writeOff(self, batch_id: int, reason: str = "") -> None:
        """Bin an expired lot: stock down by what is left, ledger says why."""
        database = self._database()
        if database is None:
            return
        try:
            database.write_off_batch(int(batch_id), str(reason or ""))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.loadExpiry(int(self._expiry.get("days") or 30))
        self.invalidated.emit()

    # =====================================================================
    # INTERNALS
    # =====================================================================
    @Slot(float, result=str)
    def qtyText(self, value: float) -> str:
        return fmt.qty(value)

    @Slot(float, result=str)
    def moneyText(self, value: float) -> str:
        return fmt.money(value)

    def _database(self):
        try:
            return legacy.database()
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return None

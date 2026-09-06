"""Incomplete products, behind `app.drafts`.

The contract IncompleteProductsDialog.qml states, over pos's `product_drafts`:

    read      busy, error, total, rows, waiting, sources
    call      load(search, page, pageSize, source), refresh(), reload(),
              draft(id), seedFor(code), discard(id), clearAll(source)
    emits     invalidated(), countChanged(), rejected(message)

WHAT THIS IS FOR, IN ONE SENTENCE
---------------------------------
A shop imports a hundred thousand rows of "barcode, name" from a national
catalogue; the two thousand it actually stocks are discovered one scan at a time,
and this is where the other ninety-eight thousand wait without pretending to be
products.

IT DOES NOT WRITE PRODUCTS
--------------------------
There is one way a product is created in this app and it is `Products.save`,
through the form the operator can see every field in. Completing a draft opens
that form with the draft's values in it; the row is cleared afterwards by
`db.consume_draft`, which the products controller calls. A second, quieter create
path here would have accepted a VAT rate and a photo from the form and dropped
both — see `db.promote_draft`.

So the only writes on this controller are the two ways a draft LEAVES without
becoming anything: `discard` and `clearAll`.

`waiting` IS A COUNT AND NOT A LIST
-----------------------------------
The products page shows the number, not the rows: a page of somebody else's
catalogue is not a page anybody reads, and `count_drafts()` is one indexed COUNT
against a table nothing else queries. The rows are loaded only when the dialog
that lists them is open.

WHY `seedFor` LIVES HERE AND NOT IN Products
--------------------------------------------
It is asked at the moment a barcode misses — by the products page and by the till
— and what it answers with is a draft. Putting it on the products controller would
have meant that controller knowing about a table it never writes to, and both
callers already reach for `app.drafts` to know whether the number is non-zero.

EVERY ROW SAYS WHAT IT IS MISSING
---------------------------------
`gaps` comes back from the data layer as the field names `product_gaps` produced,
and is translated here into the shop's own words. The dialog never decides what
"incomplete" means — there is one definition, in `db.product_gaps`, and it is the
same one the importer routed the row with.
"""

from __future__ import annotations

from PySide6.QtCore import Property, QObject, Signal, Slot

from .. import diagnostics
from . import fmt, legacy

#: The order gaps are named in a sentence. `product_gaps` already returns them in
#: this order; the tuple is here so the labels can be looked up without trusting
#: that, and so a field added there without a string here is visible as its key
#: rather than as nothing at all.
GAP_KEYS = ("name", "barcode", "purchase_price", "sale_price")


class Drafts(QObject):
    rowsChanged = Signal()
    busyChanged = Signal()
    errorChanged = Signal()
    #: How many are waiting. Watched by the products page, which shows the number.
    countChanged = Signal()
    #: The list changed underneath the current query.
    invalidated = Signal()
    rejected = Signal(str)

    def __init__(self, i18n: QObject, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._i18n = i18n
        self._rows: list[dict] = []
        self._total = 0
        self._waiting = 0
        self._sources: list[dict] = []
        self._busy = False
        self._error = ""
        self._query = ("", 1, 100, "")

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
        """Rows matching the current search — what the pager counts."""
        return self._total

    @Property("QVariantList", notify=rowsChanged)
    def rows(self) -> list:
        return self._rows

    @Property(int, notify=countChanged)
    def waiting(self) -> int:
        """Every row in the table, whatever is being searched.

        The products page reads this and nothing else. Refreshed by `refresh()`,
        which the bridge root calls after an import and after a promotion — so it
        cannot be stale against the thing that changed it.
        """
        return self._waiting

    @Property("QVariantList", notify=rowsChanged)
    def sources(self) -> list:
        """The imports these came from: [{source, count, label}].

        What makes "discard all" survivable — a shop that imported the wrong file
        can drop that file's rows and keep the ones before it.
        """
        return self._sources

    # =====================================================================
    # READS
    # =====================================================================
    @Slot(str, int, int, str)
    def load(self, search: str, page: int, page_size: int, source: str) -> None:
        database = self._database()
        if database is None:
            return
        self._query = (search, page, page_size, source)
        self._set_busy(True)
        try:
            payload = database.fetch_drafts(search, max(1, page), page_size, source)
            self._rows = [self._row(row) for row in payload["rows"]]
            self._total = int(payload.get("total") or 0)
            self._waiting = int(database.count_drafts())
            self._sources = [
                {**entry, "label": self._source_label(entry)}
                for entry in database.draft_sources()
            ]
            self._set_error("")
        except Exception as exc:  # noqa: BLE001
            self._set_error(str(exc))
            self._rows = []
            self._total = 0
        finally:
            self._set_busy(False)
        self.rowsChanged.emit()
        self.countChanged.emit()

    @Slot()
    def refresh(self) -> None:
        """Re-read the count without loading a page.

        What the products page needs after an import: the number on the card, and
        not the hundred thousand rows behind it.
        """
        database = self._database(quiet=True)
        if database is None:
            return
        try:
            value = int(database.count_drafts())
        except Exception:  # noqa: BLE001
            diagnostics.log.debug("draft count unreadable", exc_info=True)
            return
        if value != self._waiting:
            self._waiting = value
            self.countChanged.emit()

    @Slot(int, result="QVariant")
    def draft(self, draft_id: int) -> object:
        """One waiting row, in the shape the product form fills itself from."""
        database = self._database()
        if database is None:
            return None
        try:
            row = database.fetch_draft(int(draft_id))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return None
        return self._row(row) if row else None

    @Slot(str, result="QVariant")
    def seedFor(self, code: str) -> object:
        """A scanned code that is not a product — is it waiting here?

        Answers None for the ordinary case, which is why it is cheap enough to ask
        on every missed scan: one indexed lookup on a table the rest of the app
        never touches.
        """
        database = self._database(quiet=True)
        if database is None:
            return None
        try:
            row = database.lookup_draft(str(code or ""))
        except Exception:  # noqa: BLE001
            # A miss and an unreadable table are the same answer to a scan: there
            # is nothing to pre-fill, so the form opens empty as it always did.
            diagnostics.log.debug("draft lookup failed for %r", code, exc_info=True)
            return None
        return self._row(row) if row else None

    # =====================================================================
    # WRITES — the two ways a draft leaves without becoming a product
    # =====================================================================
    @Slot(int)
    def discard(self, draft_id: int) -> None:
        database = self._database()
        if database is None:
            return
        try:
            database.discard_draft(int(draft_id))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.reload()

    @Slot(str)
    def clearAll(self, source: str) -> None:
        """Undo an import. Empty `source` means every waiting row.

        Safe in the way that matters: these are not products, so nothing sold,
        counted or printed refers to them, and the file can be imported again.
        """
        database = self._database()
        if database is None:
            return
        try:
            database.clear_drafts(str(source or ""))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.reload()

    @Slot()
    def reload(self) -> None:
        """Repeat the last query — after a write, or when something else changed
        the table underneath it."""
        search, page, page_size, source = self._query
        self.load(search, page, page_size, source)
        self.invalidated.emit()

    # =====================================================================
    # INTERNALS
    # =====================================================================
    def _row(self, row: dict) -> dict:
        """One waiting row, for a table and for a form at the same time.

        Both, because a draft is read by two surfaces with opposite needs: the list
        wants strings it can print, the form wants numbers it can edit. Sending
        only formatted text is what made a pack lose its price elsewhere in this
        bridge — so every figure travels twice, once of each.
        """
        gaps = list(row.get("gaps") or [])
        return {
            "id": row["id"],
            "name": row.get("name") or "",
            "barcode": row.get("barcode") or "",
            "category": row.get("category") or "",
            "unit": row.get("unit") or "",
            "source": row.get("source") or "",
            "created_at": row.get("created_at") or "",
            # Raw, for the form.
            "purchase_price": float(row.get("purchase_price") or 0.0),
            "sale_price": float(row.get("sale_price") or 0.0),
            "stock": float(row.get("stock") or 0.0),
            "low_stock_threshold": float(row.get("low_stock_threshold") or 5.0),
            # Formatted, for the table. A zero price is a GAP, not a figure, so it
            # prints as an em dash: "0.00" in a price column reads as a decision
            # somebody made, and this is the absence of one.
            "purchase_price_text": ("—" if "purchase_price" in gaps
                                    else fmt.money(row.get("purchase_price"))),
            "sale_price_text": ("—" if "sale_price" in gaps
                                else fmt.money(row.get("sale_price"))),
            "stock_text": fmt.qty(row.get("stock")),
            # What it still needs, as keys and as a sentence.
            "gaps": gaps,
            "gaps_text": self._gap_text(gaps),
            "complete": not gaps,
        }

    def _gap_text(self, gaps: list) -> str:
        if not gaps:
            return ""
        names = [self._i18n.text(f"drafts.gap.{key}") for key in GAP_KEYS
                 if key in gaps]
        # Comma-joined and not a list: it is read inside a sentence ("still needs
        # its cost price, selling price"), and two words do not earn bullets.
        return "، ".join(names) if self._is_arabic() else ", ".join(names)

    def _is_arabic(self) -> bool:
        try:
            return bool(self._i18n.isRtl)
        except Exception:  # noqa: BLE001
            return False

    def _source_label(self, entry: dict) -> str:
        source = entry.get("source") or ""
        count = int(entry.get("count") or 0)
        name = source or self._i18n.text("drafts.title")
        return f"{name}  ({count})"

    def _database(self, quiet: bool = False):
        try:
            return legacy.database()
        except Exception as exc:  # noqa: BLE001
            if not quiet:
                self._set_error(str(exc))
            diagnostics.log.debug("drafts: no database", exc_info=True)
            return None

    def _set_busy(self, value: bool) -> None:
        if self._busy == value:
            return
        self._busy = value
        self.busyChanged.emit()

    def _set_error(self, value: str) -> None:
        if self._error == value:
            return
        self._error = value
        self.errorChanged.emit()

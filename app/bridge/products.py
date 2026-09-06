"""Products, behind `app.products`.

The contract ProductsPage.qml states, over pos's `fetch_products`:

    read      busy, error, total, stats, categories, rows
    call      load(search, page, pageSize, categoryId), loadCategories(),
              rowAt(index), probeBarcode(code), setFavorite(id, on),
              setVisibility(id, on), remove(id), quickAdd(...),
              product(id), save(values, id), units(), moneyText(value),
              adjustStock(...)
    emits     barcodeProbed(code, exists, matchTotal), invalidated(),
              created(product), saved(product), adjusted(result), rejected(message)

EVERY CELL IS A STRING

The table's price, cost and stock columns are `numeric: true`, which right-aligns
them — it does not format them. Formatting is pos's `fmt_money`/`fmt_qty`, and
`low_stock` is the comparison already made, so the page can tone a row without
knowing what a threshold is. That is ProductsPage's own stated requirement.

`product()` IS THE EXCEPTION, AND IT CARRIES BOTH

The form does not display a record, it EDITS one, so every value it is given has
to be the value it can hand back: the raw number beside the formatted string. A
pack's `price` and `price_text`, the photo's stored name and its URL. The one
place this was forgotten cost a pack its price on every save — see
`product()`.

`rowAt` IS PAGE-RELATIVE

The page guards it with `total`, which is the query-wide count, so an index from
a later page can arrive here. Out of range answers None rather than raising.
"""

from __future__ import annotations

from PySide6.QtCore import Property, QObject, Signal, Slot

from .. import diagnostics
from . import fmt, images, interop, legacy


class Products(QObject):
    rowsChanged = Signal()
    statsChanged = Signal()
    categoriesChanged = Signal()
    busyChanged = Signal()
    errorChanged = Signal()

    #: A row changed underneath the current query: reload it, same page.
    invalidated = Signal()
    #: Answer to probeBarcode: does this code exist, and does the catalogue hold
    #: anything matching it at all.
    barcodeProbed = Signal(str, bool, int)
    #: quickAdd's outcomes.
    created = Signal("QVariant")
    #: save() and adjustStock() outcomes.
    saved = Signal("QVariant")
    adjusted = Signal("QVariant")
    rejected = Signal(str)
    #: A save that finished an imported row: the waiting-room count moved. Carries
    #: nothing, because the only listener is a counter.
    draftConsumed = Signal()

    def __init__(self, i18n: QObject, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._i18n = i18n
        self._rows: list[dict] = []
        self._stats: dict = {}
        self._categories: list[dict] = []
        self._total = 0
        self._busy = False
        self._error = ""
        # The last query, so an invalidation can repeat it without the page
        # having to hand it back.
        self._query = ("", 1, 100, 0)

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

    @Property("QVariantList", notify=categoriesChanged)
    def categories(self) -> list:
        return self._categories

    # =====================================================================
    # QUERIES
    # =====================================================================
    @Slot(str, int, int, int)
    def load(self, search: str, page: int, page_size: int, category_id: int) -> None:
        database = self._database()
        if database is None:
            return
        self._query = (search or "", max(1, int(page)), int(page_size),
                       int(category_id or 0))
        self._set_busy(True)
        try:
            result = database.fetch_products(
                self._query[0], self._query[1], self._query[2],
                self._query[3] or None,
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
    def loadCategories(self) -> None:
        database = self._database()
        if database is None:
            return
        try:
            self._categories = [
                {"id": row["id"], "name": row["name"]}
                for row in database.fetch_categories()
            ]
        except Exception as exc:  # noqa: BLE001
            self._set_error(str(exc))
            self._categories = []
        self.categoriesChanged.emit()

    @Slot(int, result="QVariant")
    def rowAt(self, index: int) -> object:
        if 0 <= index < len(self._rows):
            return self._rows[index]
        return None

    @Slot(str)
    def probeBarcode(self, code: str) -> None:
        """Enter in the search box: is this an exact code, and if not, does the
        catalogue match it at all? The page offers to create a product only when
        both answers are no."""
        database = self._database()
        if database is None:
            return
        text = (code or "").strip()
        if not text:
            return
        try:
            hit = database.lookup_barcode(text)
            matches = int(database.fetch_products(text, 1, 1, None)["total"])
        except Exception as exc:  # noqa: BLE001
            self._set_error(str(exc))
            return
        self.barcodeProbed.emit(text, hit is not None, matches)

    # =====================================================================
    # ONE PRODUCT
    # =====================================================================
    @Slot(int, result="QVariant")
    def product(self, product_id: int) -> object:
        """Everything the form and the details dialog need, in one payload.

        Raw numbers, because the form edits them, and a `text` block of the same
        figures formatted, because the details dialog displays them. Two slots
        returning two shapes of the same row would be two things to keep in step.
        """
        database = self._database()
        if database is None:
            return None
        try:
            row = database.fetch_product(int(product_id))
        except Exception as exc:  # noqa: BLE001
            self._set_error(str(exc))
            return None
        if row is None:
            return None

        product = dict(row)
        cost = float(product.get("purchase_price") or 0.0)
        price = float(product.get("sale_price") or 0.0)
        margin = price - cost
        # The photo, as the form needs it: the stored name so a save can hand the
        # same value straight back ("unchanged"), and a URL because that is what
        # an `Image` loads. Empty for the common case — a product without one.
        product["image_path"] = product.get("image_path") or ""
        product["image_url"] = images.url_for(product["image_path"])
        product["text"] = {
            "purchase_price": fmt.money(cost),
            "sale_price": fmt.money(price),
            "stock": fmt.qty(product.get("stock")),
            "low_stock_threshold": fmt.qty(product.get("low_stock_threshold")),
            "margin": fmt.money(margin),
            # Margin over the selling price, which is how a shopkeeper reads it:
            # "a fifth of what I charge is mine". Blank rather than a division by
            # zero when nothing is priced yet.
            "margin_pct": f"{(margin / price * 100):.1f}%" if price else "",
        }
        product["multi_units"] = [
            {
                "id": unit["id"],
                "name": unit["name"],
                "base_qty": unit["base_qty"],
                "qty_text": fmt.qty(unit["base_qty"]),
                # The raw price as well as the formatted one, and this is not
                # decoration: the form's pack rows are EDITABLE, so they need the
                # number back. Without it `row.price` was undefined, the box read
                # "undefined", and saving the product parsed that to 0 — opening a
                # product with a pack and pressing Save wiped the pack's price.
                "price": unit["price"],
                "price_text": fmt.money(unit["price"]),
                "barcode": unit.get("barcode") or "",
            }
            for unit in (product.get("multi_units") or [])
        ]
        return product

    @Slot(float, result=str)
    def moneyText(self, value: float) -> str:
        """For a figure QML worked out and has to show — the form's live margin.
        Through the same formatter as every stored amount, so a margin and a price
        are never written two different ways."""
        return fmt.money(value)

    @Slot(result="QVariantList")
    def units(self) -> list:
        """Units of measure, for the form's picker."""
        database = self._database()
        if database is None:
            return []
        try:
            return [
                {"id": row["id"],
                 "name": row["name"],
                 "abbreviation": row.get("abbreviation") or ""}
                for row in database.fetch_units()
            ]
        except Exception as exc:  # noqa: BLE001
            self._set_error(str(exc))
            return []

    @Slot("QVariant", int)
    def save(self, data: object, product_id: int) -> None:
        """Create or update. `product_id` 0 means create.

        save_product only writes the keys it is handed and never touches stock on
        an edit — stock moves through adjustStock, which records why. A duplicate
        barcode comes back as pos's own sentence naming the code.
        """
        values = interop.as_dict(data)
        name = str(values.get("name") or "").strip()
        if not name:
            self.rejected.emit(self._i18n.text("product.name.required"))
            return

        database = self._database()
        if database is None:
            return

        # Is this save finishing an imported row?
        #
        # `draft_id` travels only from a form that was opened on one. The four
        # required fields are checked HERE and not by the form, because the rule is
        # `db.product_gaps` and there must be one of it: a form that decided for
        # itself would be a second definition, and the importer already routed the
        # row by the first.
        #
        # A manually added product is deliberately NOT held to this. Somebody typing
        # a product in is present and deciding — a service with no barcode and no
        # cost is a real thing to sell. A file is not present and decided nothing,
        # which is the whole reason the waiting room exists.
        draft_id = int(values.get("draft_id") or 0)
        if draft_id:
            try:
                database.promote_draft(draft_id, {
                    "name": name,
                    "barcode": str(values.get("barcode") or "").strip(),
                    "purchase_price": interop.as_float(values.get("purchase_price")),
                    "sale_price": interop.as_float(values.get("sale_price")),
                })
            except ValueError as exc:
                self.rejected.emit(self._gap_reason(str(exc)))
                return
            except Exception as exc:  # noqa: BLE001
                self.rejected.emit(str(exc))
                return

        payload = {
            "name": name,
            "barcode": str(values.get("barcode") or "").strip(),
            "category_id": int(values.get("category_id") or 0) or None,
            "unit_id": int(values.get("unit_id") or 0) or None,
            "purchase_price": interop.as_float(values.get("purchase_price")),
            "sale_price": interop.as_float(values.get("sale_price")),
            "price_half": interop.as_float(values.get("price_half")),
            "price_wholesale": interop.as_float(values.get("price_wholesale")),
            "low_stock_threshold": interop.as_float(
                values.get("low_stock_threshold"), 5.0),
            "show_on_pos": 1 if values.get("show_on_pos", True) else 0,
            "is_favorite": 1 if values.get("is_favorite") else 0,
            # Default ON: a shop is mostly shelves, so it is the exception that gets
            # declared. A form that does not send the key leaves the product alone.
            "track_stock": 1 if values.get("track_stock", True) else 0,
        }
        # A draft carried its category and its unit as WORDS, because a file's
        # spelling is not a foreign key. If the form left both pickers on their
        # default, those words are resolved now — creating the category or the unit
        # if the shop has not got one — so a completed draft lands in the category
        # the file said it was in instead of in none.
        if draft_id and not payload["category_id"] and not payload["unit_id"]:
            try:
                resolved = database.resolve_draft_labels(
                    str(values.get("category_text") or ""),
                    str(values.get("unit_text") or ""),
                )
            except Exception:  # noqa: BLE001
                # Not worth refusing a save over: the product is right, it is just
                # uncategorised, and the operator can put it in a category in the
                # form they are already looking at.
                diagnostics.log.debug("could not resolve a draft's labels",
                                      exc_info=True)
            else:
                payload["category_id"] = resolved.get("category_id") or None
                payload["unit_id"] = resolved.get("unit_id") or None
        # Which NAMED rate this product is charged at — the rates dialog owns the list,
        # a product owns a pointer into it. 0 is not a rate: it means "whatever the
        # shop's default is", and it travels as NULL so a rate that later moves takes
        # the whole catalogue with it. The key travels only when the form sent it, so a
        # form that does not ask (quick-add) leaves the product alone.
        if "tax_id" in values:
            tax_id = values.get("tax_id")
            payload["tax_id"] = int(tax_id) if tax_id else None
        if not product_id:
            # Opening quantity, on a create only.
            payload["stock"] = interop.as_float(values.get("stock"))

        # The photo. Three different answers, and the difference matters:
        #
        #   a picked file   import it, and point the product at what was stored
        #   image_clear     this product has no photo any more
        #   neither         the key never travels, so the product keeps the photo
        #                   it has — which is what every caller that is not the
        #                   form (quick-add, a favourite toggle) means.
        staged = ""
        picked = images.local_path(values.get("image"))
        if picked:
            try:
                staged = database.store_product_image(picked)
            except Exception as exc:  # noqa: BLE001
                # "unsupported image format: .heic", "image file is too large" —
                # pos's own sentence, which names what to do about it. Refused
                # before the product is written: a photo the operator chose and
                # did not get is worth saying out loud rather than saving around.
                self.rejected.emit(str(exc))
                return
            payload["image_path"] = staged
        elif values.get("image_clear"):
            payload["image_path"] = ""

        try:
            saved = database.save_product(payload, int(product_id) or None)
        except Exception as exc:  # noqa: BLE001
            if staged:
                # A file copied a moment ago for a product that was never
                # written. Nothing points at it, so it goes — and if another
                # product already had the same picture, the data layer keeps it.
                database.discard_product_image(staged)
            self.rejected.emit(str(exc))
            return

        # The packs travel with the product, because that is how the form edits
        # them: replace_multi_units exists for this save and does it in one
        # transaction. Absent means "the form did not offer them" — quick-add does
        # not — and is left alone; an empty list means "there are none", which is
        # a real edit and clears them.
        if "multi_units" in values:
            units = []
            for entry in (values.get("multi_units") or []):
                unit = interop.as_dict(entry) if not isinstance(entry, dict) else entry
                name = str(unit.get("name") or "").strip()
                qty = interop.as_float(unit.get("base_qty"), 1.0)
                if not name or qty <= 0:
                    continue
                units.append({
                    "name": name,
                    "base_qty": qty,
                    "price": interop.as_float(unit.get("price")),
                    "barcode": str(unit.get("barcode") or "").strip(),
                })
            try:
                database.replace_multi_units(int(saved["id"]), units)
            except Exception as exc:  # noqa: BLE001
                # The product is saved; only the packs failed, and saying which is
                # the difference between a fixable message and a mystery.
                self.rejected.emit(str(exc))

        # The waiting row goes now that its product exists. Idempotent by design —
        # `consume_draft` looks for the barcode before it deletes anything — so a
        # failure here leaves the row in place to be finished again rather than
        # losing it. See its own comment.
        if draft_id:
            try:
                if database.consume_draft(draft_id, payload["barcode"]):
                    self.draftConsumed.emit()
            except Exception:  # noqa: BLE001
                diagnostics.log.exception("could not clear draft %s", draft_id)

        self.saved.emit(dict(saved))
        self.invalidated.emit()

    def _gap_reason(self, message: str) -> str:
        """`db.promote_draft`'s structured refusal, as the shop's own sentence.

        Duplicated from Drafts._reason on purpose: the alternative is one controller
        importing the other for a four-line string builder, and the two of them
        needing each other to exist. The shared thing is the KEY NAMES, and those
        come from `db.product_gaps`.
        """
        if not message.startswith("incomplete:"):
            return message
        gaps = [part for part in message.split(":", 1)[1].split(",") if part]
        names = [self._i18n.text(f"drafts.gap.{key}") for key in gaps]
        joiner = "، " if getattr(self._i18n, "isRtl", False) else ", "
        return self._i18n.text("drafts.incomplete_n", fields=joiner.join(names))

    @Slot(int, str, float, str)
    def adjustStock(self, product_id: int, mode: str, qty: float,
                    reason: str) -> None:
        """pos's three modes: add, reduce, set. A reason is asked for and stored
        in the log — a stock figure that changed for no recorded reason is the
        thing an inventory count cannot explain later."""
        database = self._database()
        if database is None:
            return
        try:
            result = database.adjust_stock(int(product_id), str(mode),
                                           float(qty), str(reason or ""))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.adjusted.emit(dict(result))
        self.invalidated.emit()

    # =====================================================================
    # MUTATIONS
    # =====================================================================
    #
    # THESE TWO DO NOT GO THROUGH save_product, AND THAT IS THE POINT
    #
    # They used to: `_patch` built `{"name": row["name"], "is_favorite": 1}` and
    # handed it to `save_product` on the stated understanding that "save_product
    # only touches the keys it is given". It does not. Only five keys are guarded
    # by `in data` — tax_id, track_stock, show_on_pos, is_favorite and the photo —
    # and every other column is assigned unconditionally from a `.get` with a
    # default. So starring a product from the row menu wrote `barcode = ""`,
    # `category_id = None`, `purchase_price = 0.0`, `sale_price = 0.0` and
    # `low_stock_threshold = 5.0` over the real ones: one click, and a priced,
    # categorised, barcoded product became a free uncategorised one.
    #
    # `set_product_favorite` and `set_product_visibility` are the data layer's own
    # single-column updates — one UPDATE naming one column, and the favourite one
    # also places the product at the end of the Favourites strip, which the flag
    # alone would not have done.
    @Slot(int, bool)
    def setFavorite(self, product_id: int, value: bool) -> None:
        database = self._database()
        if database is None:
            return
        try:
            database.set_product_favorite(int(product_id), bool(value))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.invalidated.emit()

    @Slot(int, bool)
    def setVisibility(self, product_id: int, value: bool) -> None:
        database = self._database()
        if database is None:
            return
        try:
            database.set_product_visibility(int(product_id), bool(value))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.invalidated.emit()

    @Slot(int)
    def remove(self, product_id: int) -> None:
        database = self._database()
        if database is None:
            return
        try:
            database.delete_product(int(product_id))
        except Exception as exc:  # noqa: BLE001
            # delete_product turns a foreign-key refusal into a sentence about
            # sales and purchases, which is the reason the operator needs.
            self.rejected.emit(str(exc))
            return
        self.invalidated.emit()

    @Slot(str, str, float, float, float, int)
    def quickAdd(self, name: str, barcode: str, sale_price: float,
                 purchase_price: float, stock: float, category_id: int) -> None:
        """pos's quick add, in its argument order: a name, and everything else
        optional. Used by the till when a scan finds nothing."""
        clean = (name or "").strip()
        if not clean:
            self.rejected.emit(self._i18n.text("qproduct.name.required"))
            return
        database = self._database()
        if database is None:
            return
        code = (barcode or "").strip()
        try:
            product = database.quick_add_product(
                clean, code, float(sale_price), float(purchase_price),
                int(category_id) or None, float(stock),
            )
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.created.emit(dict(product))
        self.invalidated.emit()

    # =====================================================================
    # INTERNALS
    # =====================================================================
    def _row(self, row: dict) -> dict:
        stock = float(row.get("stock") or 0.0)
        threshold = float(row.get("low_stock_threshold") or 0.0)
        unit = row.get("unit") or ""
        tracked = bool(row.get("track_stock", 1))
        return {
            "id": row["id"],
            "name": row["name"],
            "barcode": row.get("barcode") or "",
            "category": row.get("category") or "",
            "purchase_price": fmt.money(row.get("purchase_price")),
            "sale_price": fmt.money(row.get("sale_price")),
            # The unit belongs with the number it counts: "12" alone is not an
            # answer to how much is on the shelf.
            #
            # A product with no shelf shows an infinity sign instead of a figure. Not
            # "0" and not blank: zero reads as "sold out" — the opposite of the truth —
            # and an empty cell reads as missing data. The sign says "this one does not
            # run out", which is exactly what the flag means.
            "stock": ("\u221e" if not tracked
                      else f"{fmt.qty(stock)} {unit}".strip()),
            # Never flagged low, because it never is.
            "low_stock": tracked and stock <= threshold,
            "track_stock": tracked,
            "is_favorite": bool(row.get("is_favorite")),
            "show_on_pos": bool(row.get("show_on_pos", True)),
        }

    def _stat_block(self, stats: dict) -> dict:
        value = stats.get("inventory_value") or 0.0
        low = int(stats.get("low_stock") or 0)
        return {
            "product_count": str(int(stats.get("product_count") or 0)),
            # Compact on the card, exact in the tooltip — pos's own pairing, and
            # the reason a seven-figure inventory does not clip.
            "inventory_value": fmt.compact(value),
            "inventory_value_full": fmt.money(value),
            "low_stock": str(low),
            "low_stock_raw": low,
            "categories": str(int(stats.get("categories") or 0)),
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

"""The till, behind `app.pos`.

Implements the contract PosPage.qml's header states, over pos's data layer:

    read      busy, error, tiles, categories, lines,
              cartNumber, totalText, currencyText, itemsText, qtyText,
              discountText, customerName, customerPhone, hasCustomer,
              remainingText, paid, paidText, paidValid, allowPartial,
              imageCards, warnStock
    call      loadCategories(), loadTiles(tab, search), add(productId),
              addAnyway(productId), setQty(row, qty), setQtyAnyway(row, qty),
              remove(row), clear(), hold(), resolve(text),
              scan(code), addFreeAmount(sign, amount), setCustomer(customerId),
              setPaid(amount), payCash(), payPartial(), reloadPreferences(),
              setWarnStock(on)
    emits     invalidated(), lineTouched(row), resolved(text, added),
              scanMissed(code, barcode), saleFinished(number),
              stockBlocked(info), stockWarning(rows), rejected(message)

WHERE THE CART LIVES, AND WHY IT IS HERE

pos keeps the cart on its page and computes the totals there. It can, because
fmt_money is one import away. QML is not: every amount on that screen is a
string that has to be built by the one formatter that knows the currency, the
decimal count and the rounding rule, so the cart lives on this side of the
bridge and QML renders what it is given. The line shapes are pos's own dicts —
{product_id, name, qty, price, discount} — which is what lets finalize_sale take
them unchanged.

WHY THESE CALLS ARE SYNCHRONOUS WHEN LOGIN IS NOT

Auth runs off the GUI thread because PBKDF2 at 600 000 iterations is *designed*
to take a third of a second. These are SQLite reads and one small write against
a local file: sub-millisecond, and each of them is a step in a conversation with
an operator standing at a counter, where a queued answer arriving after the next
tap would be worse than a frame's delay. Two threads sharing one cart list would
also need a lock, and a till that can silently reorder "add" and "set quantity"
is not a till.

ONE `changed` SIGNAL FOR THE CART

The cart, the totals, the customer and the payment draft change together as far
as the screen is concerned: adding a line moves the total, the item count, the
quantity and the remaining figure. Twelve notify signals would be twelve chances
to forget one and leave a stale number on a dock that is 64px tall.

WHAT IS NOT CARRIED OVER YET

Receipt printing (pos auto-prints through `receipt_printing` after a sale).

SELLING WHAT IS NOT ON THE SHELF

pos never asks: it rings the sale and reports the negative stock afterwards, which
is `stockWarning` here. That is the right shape for the case where the shelf count
was wrong, and the wrong shape for the case that is far more common — a product at
zero that the operator did not notice, on a screen where the figure is 13px in the
corner of a tile. By then the sale is recorded, the stock is negative and correcting
it is three screens away.

So `_add` and `setQty` now ASK FIRST, through `stockBlocked`, and the line is not
added until the answer comes back through `addAnyway` / `setQtyAnyway`. Three things
this is careful about:

  IT IS A QUESTION, NOT A REFUSAL. A shop sells goods that are physically present
  and miscounted all the time. Blocking the sale would make the till wrong about
  the real world; asking makes the operator right about it.

  IT IS ABOUT THE LINE, NOT THE TAP. The figure compared against the shelf is what
  the cart line would HOLD — so the fifth tap on a product with four in stock is
  the one that asks, not the first.

  A PRODUCT WITH NO SHELF NEVER ASKS. `track_stock` off means the quantity is not
  a fact about anything (a service, a bag, anything weighed at the counter), which
  is the same rule the tiles already draw with an infinity sign.

`warnStock` is the shop's own switch, persisted as `pos.warn_stock`, so a shop that
sells from a shelf it does not count can turn the whole thing off — from the dialog
itself, which is where somebody who has just been asked twice is standing.
"""

from __future__ import annotations

from typing import Any

from PySide6.QtCore import Property, QObject, Signal, Slot

from .. import diagnostics
from . import fmt, images, legacy

#: Rows in the search dropdown under the till's search field.
#:
#: Twelve. A dropdown is read at a glance or it is not read; past about a dozen
#: entries the operator is scanning a list, and a list is what the picker dialog is
#: for.
SEARCH_LIMIT = 12

#: The fuse on `catalogue()`.
#:
#: Not a page size — the picker dialog deliberately has no paging. This is the point
#: past which handing the whole catalogue to QML stops being the right idea, and a
#: shop that reaches it needs a paged picker rather than a bigger number here.
CATALOGUE_MAX = 20000


class Till(QObject):
    # -- notifications ----------------------------------------------------
    changed = Signal()          # cart, totals, customer, payment draft
    tilesChanged = Signal()
    resultsChanged = Signal()
    categoriesChanged = Signal()
    busyChanged = Signal()
    errorChanged = Signal()
    #: The till's own settings changed — today, whether cards carry a photo.
    preferencesChanged = Signal()

    # -- events the page reacts to ---------------------------------------
    invalidated = Signal()
    lineTouched = Signal(int)
    resolved = Signal(str, bool)
    scanMissed = Signal(str, bool)
    saleFinished = Signal(str)
    #: The same sale, by id, for the bridge rather than the screen: printing
    #: and any other post-sale work needs the row, not its number.
    saleRecorded = Signal(int)

    #: An invoice in the cart is being rewritten: (document, sale_id). Routed to
    #: Sales.save by the bridge root, so the till never learns how a sale is saved.
    saleEditRequested = Signal("QVariant", int)
    #: Products whose stock went below zero on that sale.
    stockWarning = Signal("QVariantList")
    #: An add or a quantity change that would sell more than the shelf holds,
    #: asked rather than done: {product_id, name, stock, stock_text, wanted,
    #: wanted_text, kind, row}. `kind` is "out" for a shelf at or below zero and
    #: "short" for one that cannot cover the line; `row` is the cart row for a
    #: quantity change and -1 for an add. Answered by addAnyway / setQtyAnyway.
    stockBlocked = Signal("QVariant")
    held = Signal(str)
    rejected = Signal(str)

    #: The setting behind `warnStock`. pos has never heard of it — it is this front
    #: end's own, and `get_setting` falls back to the default passed here for any key
    #: that has never been written.
    WARN_STOCK_KEY = "pos.warn_stock"

    #: pos's own ceiling on a free amount.
    AMOUNT_MAX = 1e12

    def __init__(self, i18n: QObject, session: QObject,
                 parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._i18n = i18n
        self._session = session

        self._items: list[dict[str, Any]] = []
        self._customer: dict[str, Any] | None = None
        self._paid = 0.0
        self._tiles: list[dict[str, Any]] = []
        self._results: list[dict[str, Any]] = []
        self._categories: list[dict[str, Any]] = []
        self._number = ""
        self._busy = False
        self._error = ""
        self._selling = False
        #: True for exactly the length of one addAnyway / setQtyAnyway call: the
        #: shelf question has been asked and answered, so the guard stands down for
        #: that one call. Cleared in a `finally`, so a raise inside the add cannot
        #: leave the till permanently unguarded.
        self._forced = False
        #: Do the tiles carry a photo? Both halves have to be true — the shop's
        #: switch and at least one photo in the catalogue — so a shop that has
        #: never added a picture keeps the compact cards it has always had.
        self._image_cards = False
        #: The sale being rewritten, and its number for the chrome. 0 = a fresh cart.
        self._editing = 0
        self._editing_number = ""
        #: What that sale had already been paid when it was loaded. The payment sheet
        #: shows it and warns that a new figure replaces it.
        self._editing_paid = 0.0

        # Every formatted string on this screen is built for one language, so a
        # language change has to rebuild all of them: the amounts carry a
        # currency, the free lines carry a translated label, and the cart number
        # is "Invoice #3" in three languages.
        self._i18n.languageChanged.connect(self._retranslate)

    # =====================================================================
    # STATE QML READS
    # =====================================================================
    @Property(bool, notify=busyChanged)
    def busy(self) -> bool:
        return self._busy

    @Property(str, notify=errorChanged)
    def error(self) -> str:
        return self._error

    @Property("QVariantList", notify=tilesChanged)
    def tiles(self) -> list:
        return self._tiles

    @Property(bool, notify=preferencesChanged)
    def imageCards(self) -> bool:
        """Should the grid draw the photo card instead of the compact one?

        One question with two halves, because either alone gives the wrong
        answer. `ui.product_images` is the shop's decision, and a shop that
        photographs nothing would still get tall cards with a placeholder in
        every one of them; `any_product_image()` is the catalogue's state, and
        acting on it alone would take the density away from a shop that added
        one picture and then thought better of it.

        Read per grid load rather than watched: it is two indexed reads next to
        the query that builds the tiles, and it cannot then be stale against the
        rows it describes.
        """
        return self._image_cards

    @Property("QVariantList", notify=resultsChanged)
    def results(self) -> list:
        """Matches for the search dropdown: {id, name, barcode, price_text, stock,
        stock_text, category, hidden}. Empty whenever the field is empty."""
        return self._results

    @Property("QVariantList", notify=categoriesChanged)
    def categories(self) -> list:
        return self._categories

    @Property("QVariantList", notify=changed)
    def lines(self) -> list:
        money = self._money
        qty = self._qty
        return [
            {
                "name": item["name"],
                # The raw quantity as well as the formatted one: the row's
                # stepper has to add to it, and parsing a display string back
                # into a number is how a comma becomes a bug.
                "qty": item["qty"],
                "qty_text": qty(item["qty"]),
                "price_text": money(item["price"]),
                "total_text": money(self._line_total(item)),
                "step": item.get("unit") or 1.0,
            }
            for item in self._items
        ]

    @Property(str, notify=changed)
    def cartNumber(self) -> str:
        if not self._number:
            return ""
        return self._i18n.text("pos.bar.summary_title", number=self._number)

    @Property(str, notify=changed)
    def totalText(self) -> str:
        return self._money(self._total())

    @Property(str, notify=changed)
    def currencyText(self) -> str:
        return self._i18n.text("pos.currency")

    @Property(str, notify=changed)
    def itemsText(self) -> str:
        """Lines, not units — pos counts `len(self._items)` here, and the count
        beside it is the quantity."""
        return str(len(self._items)) if self._items else ""

    @Property(str, notify=changed)
    def qtyText(self) -> str:
        if not self._items:
            return ""
        return self._qty(sum(item["qty"] for item in self._items))

    @Property(str, notify=changed)
    def discountText(self) -> str:
        """Empty when there is none: the dock hides a line with no text, which is
        how a sale with no discount shows no discount row."""
        discount = sum(item["discount"] for item in self._items)
        return self._money(discount) if discount else ""

    @Property(str, notify=changed)
    def customerName(self) -> str:
        return (self._customer or {}).get("name", "")

    @Property(str, notify=changed)
    def customerPhone(self) -> str:
        return (self._customer or {}).get("phone") or ""

    @Property(bool, notify=changed)
    def hasCustomer(self) -> bool:
        return self._customer is not None

    @Property(float, notify=changed)
    def customerDebt(self) -> float:
        """What the attached customer already owed before this cart.

        Raw, because the payment sheet shows it as one of the facts an operator weighs
        while deciding what to accept — "they already owe 12 400" changes the answer to
        "how much of this are you paying" — and it formats it with the same formatter as
        everything else on that sheet.
        """
        return float((self._customer or {}).get("debt") or 0.0)

    @Property(str, notify=changed)
    def remainingText(self) -> str:
        return self._money(max(0.0, self._total() - self._paid))

    @Property(float, notify=changed)
    def paid(self) -> float:
        """What has been taken against this cart, raw.

        `remainingText` is the figure the dock draws; this is the number a page
        needs to decide whether anything is still owed — the dock's `owing` is
        the caller's call, because "0.00" is good news rather than a warning. It
        is the LIVE draft: zero on a new sale until a partial payment is typed,
        and the invoice's recorded figure while one is being rewritten — the
        payment sheet replaces it, never adds to it.
        """
        return float(self._paid)

    @Property(str, notify=changed)
    def paidText(self) -> str:
        """The same figure formatted, for the dock's settled column.

        Always formats: whether it is shown is a rule about documents, not about
        numbers, and it belongs to the page — an invoice being rewritten shows
        its settled figures, a new sale has none, and a guest invoice cannot owe
        anything so its "paid" is only ever the total said twice.
        """
        return self._money(self._paid)

    @Property(float, notify=changed)
    def editingPaid(self) -> float:
        """What the invoice being rewritten was already recorded as paid.

        Kept apart from `_paid`, which the payment sheet overwrites as soon as the
        operator types: this is the figure that was on the invoice when it was loaded,
        and the sheet needs both to say "500 → 100" and to warn that the second number
        replaces the first rather than adding to it — which is what `update_sale`
        does (db.py:2706). Zero outside an edit, where there is nothing to replace.
        """
        return float(self._editing_paid)

    @Property(bool, notify=changed)
    def paidValid(self) -> bool:
        """pos's range: nothing paid (a full debt) up to the whole total. Above
        the total is not an overpayment, it is a typo — change is worked out on
        the calculator, not by recording money the shop did not take."""
        return bool(self._items) and 0.0 <= self._paid <= self._total()

    @Property(bool, notify=changed)
    def allowPartial(self) -> bool:
        database = self._database(quiet=True)
        if database is None:
            return False
        try:
            return database.get_setting("sale.allow_partial", "1") == "1"
        except Exception:  # noqa: BLE001
            diagnostics.log.debug("sale.allow_partial unreadable", exc_info=True)
            return False

    @Property(bool, notify=changed)
    def allowDebt(self) -> bool:
        """Whether money may be left owing: `sale.allow_debt`.

        The switch was in Settings and enforced by nothing — here or in pos,
        which never reads it either. Now it owns the whole underpayment family,
        because they are all the same act: a full debt sale (nothing paid), a
        partial (some left over) — both leave a balance on an account, and a
        shop that switched accounts off meant both. Read live, like
        `allowPartial` above: the Settings screen that writes it does not tell
        this controller it did.
        """
        database = self._database(quiet=True)
        if database is None:
            return False
        try:
            return database.get_setting("sale.allow_debt", "1") == "1"
        except Exception:  # noqa: BLE001
            diagnostics.log.debug("sale.allow_debt unreadable", exc_info=True)
            return False

    @Property(bool, notify=preferencesChanged)
    def warnStock(self) -> bool:
        """Ask before selling past the shelf. On unless the shop turned it off.

        Read from the database rather than cached, like `allowPartial` above: it is
        one indexed read on a key that is asked about once per add, and a cache would
        have to be invalidated by a Settings screen this object does not watch.
        """
        database = self._database(quiet=True)
        if database is None:
            # No shelf figures either, so there is nothing to warn about and a
            # False here is the honest answer rather than a fallback.
            return False
        try:
            return database.get_setting(self.WARN_STOCK_KEY, "1") == "1"
        except Exception:  # noqa: BLE001
            diagnostics.log.debug("pos.warn_stock unreadable", exc_info=True)
            return False

    @Slot(bool)
    def setWarnStock(self, on: bool) -> None:
        """The dialog's own "don't warn me again", and the Settings switch.

        Written where the operator is standing when they decide, which is in front of
        the question. It is a shop-wide setting and not a per-session mute on purpose:
        somebody who has just been asked about the same untracked shelf three times is
        answering for the shop, and a mute that forgets itself overnight would ask
        them again tomorrow. The Settings screen carries the same switch, which is the
        way back.
        """
        database = self._database()
        if database is None:
            return
        try:
            database.set_setting(self.WARN_STOCK_KEY, "1" if on else "0")
        except Exception as exc:  # noqa: BLE001
            self._set_error(str(exc))
            return
        diagnostics.business().info("stock warning %s", "on" if on else "off")
        self.preferencesChanged.emit()

    # =====================================================================
    # LOADING
    # =====================================================================
    @Slot()
    def loadCategories(self) -> None:
        database = self._database()
        if database is None:
            return
        try:
            self._categories = [
                {"id": row["id"], "name": row["name"], "color": row["color"]}
                for row in database.fetch_categories()
            ]
            self._set_error("")
        except Exception as exc:  # noqa: BLE001
            self._set_error(str(exc))
            self._categories = []
        self.categoriesChanged.emit()

        # The cart number counts sales and held carts, so it is only known once
        # the database is reachable.
        if not self._number:
            self._renumber(database)

    @Slot("QVariant")
    def loadTiles(self, tab: object) -> None:
        """The active tab's products. Nothing else.

        This used to take a search string as well, and a non-empty one replaced the
        grid with catalogue-wide results — so typing three letters emptied the
        category the operator had open, left its chip still highlighted in the strip,
        and turned the tile wall into a result list. Search is now its own thing
        (`search()` below, feeding a dropdown), and the grid only ever shows the tab.
        """
        database = self._database()
        if database is None:
            return

        self._set_busy(True)
        try:
            if tab == "favorites":
                rows = database.fetch_favorites()
            else:
                rows = database.fetch_pos_products(self._category_id(tab), "")
            thresholds = self._thresholds(database)
            self._tiles = [self._tile(row, thresholds) for row in rows]
            # Which card the grid draws, decided beside the rows it describes.
            self._set_image_cards(self._wants_image_cards(database))
            self._set_error("")
        except Exception as exc:  # noqa: BLE001
            self._set_error(str(exc))
            self._tiles = []
        finally:
            self._set_busy(False)
        self.tilesChanged.emit()

    @Slot()
    def reloadPreferences(self) -> None:
        """The shop changed a setting this screen renders.

        Wired from the bridge root when Settings writes `ui.product_images`. The
        grid is invalidated rather than repainted: the flag changes the shape of
        every card in it, and a taller card holding a row that was measured for a
        shorter one is exactly the sort of thing that looks like a bug.
        """
        database = self._database(quiet=True)
        if database is None:
            return
        self._set_image_cards(self._wants_image_cards(database))
        self.invalidated.emit()

    # =====================================================================
    # SEARCH
    # =====================================================================
    @Slot(str)
    def search(self, text: str) -> None:
        """Matches for the dropdown under the search field.

        THE WHOLE CATALOGUE, NOT THE TILL'S VIEW OF IT

        `fetch_pos_products` — what this used to go through — filters
        `show_on_pos != 0`, so a product deliberately kept off the tile wall could
        not be found by name at all, even though it is perfectly sellable and
        `lookup_barcode` will happily scan it. `fetch_products` applies no such
        filter and matches name OR barcode, which is what an operator means when
        they type into a search box: find the thing, wherever it is filed.

        Capped, because this is a dropdown. A list longer than the eye can take in
        is a list nobody reads; the picker dialog is the answer for a query that
        matches half the shop.
        """
        database = self._database()
        if database is None:
            return

        query = (text or "").strip()
        if not query:
            if self._results:
                self._results = []
                self.resultsChanged.emit()
            return

        try:
            page = database.fetch_products(query, 1, SEARCH_LIMIT, None)
            self._results = [self._listing(row) for row in page.get("rows") or []]
            self._set_error("")
        except Exception as exc:  # noqa: BLE001
            self._set_error(str(exc))
            self._results = []
        self.resultsChanged.emit()

    @Slot(result="QVariantList")
    def catalogue(self) -> list:
        """Every product, in one call, for the picker dialog.

        No paging and no lazy loading: the dialog filters what it is given in
        JavaScript, which for a few thousand rows is faster than a round trip per
        keystroke and removes the whole class of "the row I wanted was on page 4".
        A QVariantList of this shape is about 200 bytes a row, so a 3000-product
        shop hands over well under a megabyte, once, when the dialog opens.

        CATALOGUE_MAX is a fuse, not a page size. A shop past it has outgrown the
        premise of this dialog and wants a paged one; silently showing the first
        20000 of 50000 would be worse than the cap being visible in the code.
        """
        database = self._database()
        if database is None:
            return []
        try:
            page = database.fetch_products("", 1, CATALOGUE_MAX, None)
            return [self._listing(row) for row in page.get("rows") or []]
        except Exception as exc:  # noqa: BLE001
            self._set_error(str(exc))
            return []

    def _listing(self, row: dict) -> dict:
        """One row for the dropdown and for the picker.

        Deliberately NOT the tile shape. A tile carries `price` and `unit` because
        `add()` used to need them; a listing row carries only what is displayed plus
        the id, because `add()` now looks the product up itself. Keeping money out of
        a payload QML could otherwise send back is the same rule the rest of this
        file follows: the price on a cart line comes from the database, never from
        the screen.
        """
        stock = float(row.get("stock") or 0.0)
        return {
            "id": row["id"],
            "name": row["name"],
            "barcode": row.get("barcode") or "",
            "price_text": fmt.money(row.get("sale_price")),
            "stock": stock,
            "stock_text": fmt.qty(stock),
            "category": row.get("category") or "",
            # True for a product the tile wall never shows. Worth saying here,
            # because this is the one place in the app that finds those on purpose.
            "hidden": not bool(row.get("show_on_pos", True)),
            # False when the quantity is not a fact about anything — a service, a
            # bag, anything weighed at the counter. The picker draws no "out of
            # stock" for those and the till does not ask about their shelf.
            "track_stock": bool(row.get("track_stock", True)),
        }

    # =====================================================================
    # CART
    # =====================================================================
    @Slot(int)
    def add(self, product_id: int) -> None:
        """Add a product to the cart by id.

        The tile path costs no query: a tile row carries its own price and unit, and
        the grid was loaded moments ago and is reloaded after every sale, which is
        the same freshness pos works from.

        THE FALLBACK IS NOT DEFENSIVE PADDING

        Anything that is not a tile — the search dropdown, the picker dialog, a
        product created by QuickAddProductDialog — has an id that is by definition
        not in `_tiles`. Without this branch such a call did nothing at all, silently:
        QuickAddProductDialog.qml:73 has been calling `add()` on a brand-new product
        since it was written, and `products.created` fires before the reload that
        would have put it on the grid, so the first add after creating a product has
        always been dropped.
        """
        for tile in self._tiles:
            if tile["id"] == product_id:
                self._add(tile["id"], tile["name"], tile["price"], tile["unit"])
                return

        database = self._database()
        if database is None:
            return
        try:
            product = database.fetch_product(int(product_id))
        except Exception as exc:  # noqa: BLE001
            self._set_error(str(exc))
            return
        if product is None:
            # A row that was deleted between listing it and tapping it. The screen
            # will reload and stop offering it; there is nothing to tell the
            # operator that the disappearing row does not already say.
            return
        self._add(product["id"], product["name"],
                  float(product["sale_price"] or 0.0), 1.0)

    @Slot(int)
    def addAnyway(self, product_id: int) -> None:
        """`add`, with the shelf question already answered.

        A separate slot rather than a flag on `add`, so nothing can pass "skip the
        check" by accident: every ordinary caller — a tile, the scanner, the picker —
        gets the guarded path, and this one exists only to be called by the dialog
        that asked.
        """
        self._forced = True
        try:
            self.add(product_id)
        finally:
            self._forced = False

    @Slot(int, float)
    def setQty(self, row: int, qty: float) -> None:
        if not self._valid(row) or qty <= 0:
            return
        item = self._items[row]
        blocked = self._shelf_block(item.get("product_id"), float(qty), row)
        if blocked is not None:
            self.stockBlocked.emit(blocked)
            return
        item["qty"] = float(qty)
        self.changed.emit()

    @Slot(int, float)
    def setQtyAnyway(self, row: int, qty: float) -> None:
        """`setQty`, with the shelf question already answered."""
        self._forced = True
        try:
            self.setQty(row, qty)
        finally:
            self._forced = False

    @Slot(int)
    def remove(self, row: int) -> None:
        if not self._valid(row):
            return
        del self._items[row]
        self._paid = 0.0
        self.changed.emit()

    @Slot()
    def clear(self) -> None:
        """Void: the lines and the customer both go. A cart cleared with somebody
        still attached is how the next sale ends up on the wrong account."""
        self._items = []
        self._customer = None
        self._paid = 0.0
        self._editing = 0
        self._editing_number = ""
        self._editing_paid = 0.0
        self._renumber()
        self.changed.emit()

    # =====================================================================
    # EDITING A COMPLETED SALE
    # =====================================================================
    #
    # WHY THE TILL AND NOT AN EDITOR OF ITS OWN
    #
    # An invoice is edited the way it was rung up: find the product, set the
    # quantity, choose how it is paid. That is this screen — the tiles, the keypad,
    # the customer card, Cash and Partial — and a second screen shaped like it would
    # be a copy to keep in step, learned twice, and different in some small way that
    # costs an operator a mistake. So the sale is loaded INTO the till, and the two
    # pay buttons commit an update instead of a new sale.
    #
    # What changes is the chrome, not the layout: `editing` is on, the screen says
    # which invoice it is holding, and the pay buttons read "Save". Nothing about the
    # gestures changes, which is the entire point.

    #: The sale being rewritten, or 0 for a normal cart.
    @Property(int, notify=changed)
    def editing(self) -> int:
        return self._editing

    @Property(str, notify=changed)
    def editingNumber(self) -> str:
        return self._editing_number

    @Slot(int, result=bool)
    def loadSale(self, sale_id: int) -> bool:
        """Put a completed sale in the cart, to be rewritten.

        Refuses when the cart is not empty rather than merging: a half-rung sale and
        an invoice being corrected are two documents, and silently mixing them is
        the one outcome nothing can undo afterwards.
        """
        if self._items:
            self.rejected.emit(self._i18n.text(
                "pos.edit.cart_busy",
                "Finish or void the current cart first."))
            return False
        database = self._database()
        if database is None:
            return False
        try:
            sale = database.fetch_sale(int(sale_id))
        except Exception as exc:  # noqa: BLE001
            self._set_error(str(exc))
            return False
        if sale is None:
            self.rejected.emit(self._i18n.text("sales.missing",
                                               "That sale no longer exists."))
            return False

        items = []
        for line in sale.get("items") or []:
            items.append({
                "product_id": line.get("product_id"),
                "name": line.get("name") or "",
                "qty": float(line.get("qty") or 0.0),
                "price": float(line.get("price") or 0.0),
                "discount": float(line.get("discount") or 0.0),
                "unit": 1.0,
                # Every price on a finished invoice is a decision that was already
                # made: attaching a customer must not re-price the document being
                # corrected.
                "manual_price": True,
            })
        self._items = items
        self._customer = (database.fetch_customer(sale["customer_id"])
                          if sale.get("customer_id") else None)
        self._paid = float(sale.get("paid") or 0.0)
        self._editing_paid = self._paid
        self._editing = int(sale_id)
        self._editing_number = str(sale.get("number") or "")
        self.changed.emit()
        return True

    @Slot()
    def cancelEdit(self) -> None:
        """Leave the invoice alone and empty the cart. Nothing was written."""
        self.clear()

    @Slot(int, float)
    def addFreeAmount(self, sign: int, amount: float) -> None:
        """pos's ± AMT line: a charge at +amount, a cart-level discount at
        −amount, both qty 1. The name is numbered and unique because the cart
        shows the label and two identical rows cannot be told apart."""
        if amount <= 0:
            return
        if amount > self.AMOUNT_MAX:
            self.rejected.emit(self._i18n.text("amount.too_large"))
            return

        key = "pos.free_plus" if sign > 0 else "pos.free_minus"
        taken = {item["name"] for item in self._items if item["product_id"] is None}
        number = len(taken) + 1
        name = self._i18n.text(key, number=number)
        while name in taken:
            number += 1
            name = self._i18n.text(key, number=number)

        self._items.append({
            "product_id": None,
            "name": name,
            "qty": 1.0,
            "price": amount if sign > 0 else 0.0,
            "discount": 0.0 if sign > 0 else amount,
            "unit": 1.0,
            # The label's two ingredients, kept so a language change can rebuild
            # the same name instead of guessing at it.
            "free": (1 if sign > 0 else -1, number),
        })
        row = len(self._items) - 1
        self.changed.emit()
        self.lineTouched.emit(row)

    # =====================================================================
    # WHAT WAS TYPED
    # =====================================================================
    @Slot(str)
    def resolve(self, text: str) -> None:
        """The keypad's Apply: a barcode, or a number for the active mode.

        The text travels back with the answer so a page that has since been typed
        into cannot apply a quantity to the wrong value.
        """
        added = self._try_code(text)
        self.resolved.emit(text, added)

    @Slot(str)
    def scan(self, code: str) -> None:
        """A scanner burst, or Enter in the search box. A miss is never a number
        here — it is an unknown code, and the page offers to create it."""
        if self._try_code(code):
            return
        digits = self._digits(code)
        self.scanMissed.emit(code, bool(digits) and digits.isdigit())

    # =====================================================================
    # CUSTOMER
    # =====================================================================
    @Slot(int)
    def setCustomer(self, customer_id: int) -> None:
        """Attach (or clear) the customer the sale is for.

        A customer used to change the PRICES on the lines already in the cart —
        `_reprice()` re-read `product_price(id, level)` for every line the moment
        a wholesaler's account was attached. The shop prices in one band now (see
        the note where `_level` used to be), so a customer changes who pays and
        what they owe, and not what anything costs.
        """
        if not customer_id:
            self._customer = None
            self.changed.emit()
            return
        database = self._database()
        if database is None:
            return
        try:
            self._customer = database.fetch_customer(int(customer_id))
        except Exception as exc:  # noqa: BLE001
            self._set_error(str(exc))
            return
        self.changed.emit()

    # =====================================================================
    # WHAT ONE COSTS — ONE BAND, ON PURPOSE
    # =====================================================================
    #
    # This class used to hold `_level` (the customer's price level: retail, half
    # or wholesale) and `_reprice()` (which re-read `db.product_price(id, level)`
    # for every line whenever a customer was attached), and `_add` looked the
    # tier price up on every add. All three are gone: the shop sells at one band,
    # the product form no longer offers the other two counters, and a customer's
    # account carries no level.
    #
    # `price_half` and `price_wholesale` remain as COLUMNS and their stored values
    # ride through every save untouched (see ProductFormDialog's `priceHalf` /
    # `priceWholesale`) — nothing was migrated and nothing was lost. What left is
    # the behaviour: a line's price is the product's sale price at the moment it
    # is added, and a manual override still wins over that, which is the whole of
    # the pricing rule now.
    #
    # `db.product_price()` itself is untouched: it lives in the other project. It
    # is simply not called with a tier again.

    # =====================================================================
    # PAYMENT
    # =====================================================================
    @Slot(float)
    def setPaid(self, amount: float) -> None:
        self._paid = max(0.0, float(amount))
        self.changed.emit()

    @Slot()
    def payCash(self) -> None:
        if not self._sellable():
            return
        self._finalize("cash", self._total())

    @Slot()
    def payPartial(self) -> None:
        """pos's three outcomes for one panel: the whole total is a cash sale,
        nothing is a debt sale, anything between is a partial — and the last two
        need somebody to owe the money."""
        if not self._sellable():
            return
        total = self._total()
        paid = self._paid
        if not 0.0 <= paid <= total:
            return
        if paid < total and not self.allowDebt and not self._editing:
            self.rejected.emit(self._i18n.text(
                "pay.debt_off",
                "Sales on account are switched off in Settings.",
            ))
            return
        if paid < total and self._customer is None:
            self.rejected.emit(self._i18n.text("pay.need_customer"))
            return
        if paid == total:
            self._finalize("cash", total)
        elif paid == 0.0:
            self._finalize("debt", 0.0)
        else:
            self._finalize("partial", paid)

    @Slot()
    def hold(self) -> None:
        """Park the cart under its number and start a fresh one."""
        if not self._items:
            self.rejected.emit(self._i18n.text("pos.cart_empty"))
            return
        database = self._database()
        if database is None:
            return
        try:
            database.hold_cart(
                self._number,
                (self._customer or {}).get("name", ""),
                {"items": [dict(item) for item in self._items],
                 "customer": self._customer},
            )
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        held = self._number
        self.clear()
        self.held.emit(held)
        # Held carts count towards the next number, and a held cart is one fewer
        # sale on the shelf — the page reloads its grid on this.
        self.invalidated.emit()

    # =====================================================================
    # HELD CARTS
    # =====================================================================
    @Slot(result="QVariantList")
    def heldCarts(self) -> list:
        """Display-ready rows for the saved-carts dialog. A slot rather than a
        property: nothing on the till screen shows them, so they are fetched when
        the dialog opens and not kept in step for the rest of the day."""
        database = self._database()
        if database is None:
            return []
        try:
            carts = database.fetch_held_carts()
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return []
        walk_in = self._i18n.text("pos.walk_in")
        return [
            {
                "id": cart["id"],
                "number": cart["number"],
                "customer": cart.get("customer_name") or walk_in,
                "lines": str(int(cart.get("line_count") or 0)),
                "qty": self._qty(cart.get("total_qty") or 0.0),
                "total": self._money(cart.get("total") or 0.0),
                "when": self._when(cart.get("created_at")),
            }
            for cart in carts
        ]

    @Slot(int)
    def restore(self, cart_id: int) -> None:
        """Open a held cart, replacing whatever is on the counter.

        pos deletes the held row as it restores, and that is right: a cart that
        existed in two places at once would be sold twice. The dialog is what
        warns about replacing a non-empty cart — by then the operator has said
        yes.
        """
        database = self._database()
        if database is None:
            return
        try:
            carts = database.fetch_held_carts()
            cart = next((c for c in carts if c["id"] == int(cart_id)), None)
            if cart is None:
                return
            database.delete_held_cart(int(cart_id))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return

        self._items = [
            {
                "product_id": item.get("product_id"),
                "name": item["name"],
                "qty": float(item["qty"]),
                "price": float(item["price"]),
                "discount": float(item["discount"]),
                "unit": 1.0,
            }
            for item in (cart.get("items") or [])
        ]
        self._customer = cart.get("customer")
        self._paid = 0.0
        self._number = cart["number"]
        self.changed.emit()
        self.invalidated.emit()

    @Slot(int)
    def discard(self, cart_id: int) -> None:
        database = self._database()
        if database is None:
            return
        try:
            database.delete_held_cart(int(cart_id))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.invalidated.emit()

    # =====================================================================
    # FOR THE CALCULATOR
    # =====================================================================
    @Property(float, notify=changed)
    def total(self) -> float:
        """The raw total. The only number on this controller QML may do
        arithmetic with, and it exists for one reason: the change calculator
        subtracts what the customer handed over from it."""
        return self._total()

    @Slot(float, result=str)
    def moneyText(self, value: float) -> str:
        """Format an amount the calculator worked out, through the same formatter
        as the dock — so change and total cannot be written two ways."""
        return self._money(value)

    # =====================================================================
    # INTERNALS
    # =====================================================================
    def _finalize(self, payment_type: str, paid: float) -> None:
        if self._selling:
            return
        # An invoice being corrected takes a different road out: the same cart, the
        # same two buttons, but `Sales.save` rather than a new sale. Emitted rather
        # than called, because the till's job ends at "this is the document" and
        # rewriting one belongs to the controller that owns sales.
        if self._editing:
            self.saleEditRequested.emit(
                {
                    "items": [
                        {key: value for key, value in item.items()
                         if key not in ("unit", "manual_price")}
                        for item in self._items
                    ],
                    "paid": float(paid),
                    "customer_id": (self._customer or {}).get("id"),
                },
                int(self._editing),
            )
            return
        database = self._database()
        if database is None:
            return

        # `unit` is the row's stepper size and `manual_price` is the "leave this
        # line's price alone" flag — both belong to this side only; the rest of the
        # dict is pos's own sale-item shape.
        items = [
            {key: value for key, value in item.items()
             if key not in ("unit", "manual_price")}
            for item in self._items
        ]
        customer_id = (self._customer or {}).get("id")

        self._selling = True
        try:
            sale = database.finalize_sale(items, customer_id, payment_type, paid)
        except Exception as exc:  # noqa: BLE001
            # Its own words: finalize_sale refuses an empty cart, a debt with no
            # customer and a partial outside 0..total, and each of those
            # sentences says more than "could not save".
            self.rejected.emit(str(exc))
            return
        finally:
            self._selling = False

        self._items = []
        self._customer = None

        self._paid = 0.0
        self._renumber(database)

        self.changed.emit()
        self.saleFinished.emit(str(sale.get("number", "")))
        self.saleRecorded.emit(int(sale.get("id") or 0))

        # Stock is never allowed to block a sale — finalize_sale says so — so the
        # only honest thing left is to report what went below zero, after the
        # money is in. pos shows the same list in a dialog.
        below = [
            {
                "product_id": row.get("product_id"),
                "name": row.get("name") or "",
                "after": float(row.get("after") or 0.0),
                "after_text": self._qty(row.get("after")),
            }
            for row in (sale.get("stocks") or [])
            if float(row.get("after") or 0.0) < 0
        ]
        if below:
            self.stockWarning.emit(below)

        self.invalidated.emit()

    def _add(self, product_id: int, name: str, price: float, unit: float) -> None:
        """pos's add_product: a product already in the cart gains one unit rather
        than opening a second line.

        `price` is what the caller found — a tile, a search hit, a scanned
        multi-unit. It is overridden by the customer's own counter for a plain
        product, and left exactly as passed for a multi-unit, whose price belongs
        to the pack rather than to the product.

        The shelf is checked HERE rather than in `add`, because this is the one place
        every route into the cart passes through — a tile, the scanner, the picker,
        a product just created in the quick-add form — and a guard on one of the four
        is a guard on none of them. It is also the only place that knows what the line
        would come to, which is the figure the shelf has to cover.
        """
        unit = float(unit or 1.0)
        existing = 0.0
        for item in self._items:
            if item["product_id"] == product_id:
                existing = float(item["qty"])
                break
        blocked = self._shelf_block(product_id, existing + unit, -1)
        if blocked is not None:
            self.stockBlocked.emit(blocked)
            return

        for row, item in enumerate(self._items):
            if item["product_id"] == product_id:
                item["qty"] += unit
                break
        else:
            self._items.append({
                "product_id": product_id,
                "name": name,
                "qty": unit,
                "price": float(price),
                "discount": 0.0,
                "unit": unit,
                # A pack's price is the pack's, not the product's, so a customer
                # change must not re-price it off the single-unit counter.
                "manual_price": unit != 1.0,
            })
            row = len(self._items) - 1
        self.changed.emit()
        self.lineTouched.emit(row)

    # =====================================================================
    # THE SHELF
    # =====================================================================
    def _shelf_block(self, product_id: object, wanted: float,
                     row: int) -> dict[str, Any] | None:
        """The shelf's objection to holding `wanted` of `product_id`, or None.

        None — the common answer — for all of: the guard standing down because the
        question was already answered, the shop having switched the warning off, a
        free-amount line with no product behind it, a product that does not count its
        stock, and a shelf that covers the line.
        """
        if self._forced or product_id is None:
            return None
        if not self.warnStock:
            return None
        shelf = self._shelf(int(product_id))
        if shelf is None:
            return None
        name, stock = shelf
        if wanted <= stock:
            return None
        return {
            "product_id": int(product_id),
            "name": name,
            "stock": stock,
            "stock_text": self._qty(stock),
            "wanted": float(wanted),
            "wanted_text": self._qty(wanted),
            # Two different sentences, and the dialog needs to know which: "there
            # are none of these" and "there are three and the line wants five" are
            # not the same news, and only the first one is a surprise.
            "kind": "out" if stock <= 0 else "short",
            # -1 for an add, so the answer knows whether to re-add a unit or to set
            # a quantity — the two are not interchangeable on a line that already
            # holds four.
            "row": int(row),
        }

    def _shelf(self, product_id: int) -> tuple[str, float] | None:
        """(name, stock) for a product that counts its stock, else None.

        The wall is the first place asked and answers for nearly every tap: a tile
        carries both figures and is reloaded after every sale, so the guard usually
        costs no query at all. Anything not on the wall — a search hit, a scan, a
        product created a second ago — is read once, which is the same read `add`
        makes for it anyway.
        """
        for tile in self._tiles:
            if tile["id"] == product_id:
                # `tracked` and not `stock`: `_tile` reports an untracked product as
                # 1.0 with an infinity sign, and comparing a second unit against that
                # 1.0 would refuse to sell two of a service.
                if not tile.get("tracked", True):
                    return None
                return (str(tile["name"]), float(tile["stock"]))

        database = self._database(quiet=True)
        if database is None:
            return None
        try:
            product = database.fetch_product(int(product_id))
        except Exception:  # noqa: BLE001
            diagnostics.log.debug("shelf unreadable: product_id=%s", product_id,
                                  exc_info=True)
            return None
        if product is None:
            return None
        if not bool(product.get("track_stock", 1)):
            return None
        return (str(product.get("name") or ""),
                float(product.get("stock") or 0.0))

    def _try_code(self, text: str) -> bool:
        """Look `text` up as a barcode and add what it finds. True when it hit."""
        database = self._database()
        if database is None:
            return False
        code = self._digits(text)
        if not code:
            return False
        try:
            hit = database.lookup_barcode(code)
        except Exception as exc:  # noqa: BLE001
            self._set_error(str(exc))
            return False
        if hit is None:
            return False
        self._add(hit["id"], hit["name"], hit["sale_price"],
                  hit.get("unit_qty") or 1.0)
        return True

    def _digits(self, text: str) -> str:
        """Arabic-Indic digits to ASCII, whitespace off. pos's normalise, because
        whether a string is a barcode is decided in exactly one place."""
        value = (text or "").strip()
        if not value:
            return ""
        try:
            return legacy.scanner().normalize_digits(value)
        except Exception:  # noqa: BLE001
            diagnostics.log.debug("scanner normalise unavailable", exc_info=True)
            return value

    def _tile(self, row: dict[str, Any], thresholds: dict[int, float]) -> dict[str, Any]:
        stock = float(row.get("stock") or 0.0)
        threshold = float(thresholds.get(row["id"], 0.0) or 0.0)
        tracked = bool(row.get("track_stock", 1))
        return {
            "id": row["id"],
            "name": row["name"],
            "price_text": self._money(row["sale_price"]),
            # A product with no shelf reads as plentiful, so the tile never dims it and
            # never warns about it. The figure is an infinity sign rather than a 0,
            # because 0 on a till tile means "sold out" — the opposite of the truth.
            "stock": stock if tracked else 1.0,
            "stock_text": self._qty(stock) if tracked else "\u221e",
            # Whether that figure means anything. Not read by QML — the tile draws
            # the infinity sign above and needs nothing more — but `_shelf` cannot
            # tell an untracked product from one with exactly one left without it,
            # and the two answer the shelf question very differently.
            "tracked": tracked,
            # Low is "still sellable but worth knowing": at or under the
            # product's own threshold and not yet zero, which the tile shows
            # differently again. Never true without a shelf.
            "low_stock": tracked and 0.0 < stock <= threshold,
            "color": row.get("color") or "",
            "barcode": row.get("barcode") or "",
            # The photo, as a URL, or "" for a product without one — which is the
            # same thing to the card as a photo whose file has gone missing.
            "image": images.url_for(row.get("image_path") or ""),
            # Not read by QML: what add() needs to build a cart line without
            # going back to the database.
            "price": float(row["sale_price"]),
            "unit": float(row.get("unit_qty") or 1.0),
        }

    def _thresholds(self, database) -> dict[int, float]:
        """{product_id: low_stock_threshold} for the whole catalogue.

        fetch_pos_products does not select the threshold and this side does not
        edit pos/, so it is one extra indexed read per grid load rather than a
        changed query — and it is per product, which is where the threshold
        lives: 5 litres of milk is low, 5 fridges is not.
        """
        with database.SessionFactory() as session:
            rows = session.execute(
                database.select(database.Product.id,
                                database.Product.low_stock_threshold)
            ).all()
        return {row[0]: row[1] for row in rows}

    def _category_id(self, tab: object) -> int | None:
        try:
            return int(tab)  # type: ignore[arg-type]
        except (TypeError, ValueError):
            return None

    def _wants_image_cards(self, database) -> bool:
        """The two halves of `imageCards`, read together.

        Unreadable is False rather than an error: which card is drawn is not
        worth taking a till screen down for, and the compact one is what the app
        has always drawn.
        """
        try:
            if database.get_setting("ui.product_images", "1") != "1":
                return False
            return bool(database.any_product_image())
        except Exception:  # noqa: BLE001
            diagnostics.log.debug("photo preference unreadable", exc_info=True)
            return False

    def _set_image_cards(self, value: bool) -> None:
        if self._image_cards == value:
            return
        self._image_cards = value
        self.preferencesChanged.emit()

    def _line_total(self, item: dict[str, Any]) -> float:
        return item["qty"] * item["price"] - item["discount"]

    def _total(self) -> float:
        return sum(self._line_total(item) for item in self._items)

    def _money(self, value: object) -> str:
        """Formatted without a currency: the dock prints it once, beside the
        total, instead of on every line of a cart."""
        try:
            return legacy.formatters().fmt_money(value, currency=False)
        except Exception:  # noqa: BLE001
            diagnostics.log.debug("money fallback for %r", value, exc_info=True)
            return "—"

    def _qty(self, value: object) -> str:
        try:
            return legacy.formatters().fmt_qty(value)
        except Exception:  # noqa: BLE001
            diagnostics.log.debug("qty fallback for %r", value, exc_info=True)
            return ""

    def _when(self, value: object) -> str:
        try:
            return legacy.formatters().fmt_dt(value)
        except Exception:  # noqa: BLE001
            diagnostics.log.debug("date fallback for %r", value, exc_info=True)
            return str(value or "")

    def _valid(self, row: int) -> bool:
        return 0 <= row < len(self._items)

    def _sellable(self) -> bool:
        if not self._items:
            self.rejected.emit(self._i18n.text("pos.cart_empty"))
            return False
        # An invoice being rewritten is not a sale being rung: it moves stock that
        # was already counted and a debt that was already owed, so it takes the
        # sales-edit right rather than the right to serve a customer. The pen on the
        # sales table is gated the same way; this is the door it cannot be walked
        # around by loading an invoice and then pressing Save.
        permission = "sales.edit" if self._editing else "pos.sell"
        if not self._session.can(permission):
            self.rejected.emit(self._i18n.text("permission.denied.title"))
            return False
        return True

    def _renumber(self, database=None) -> None:
        database = database or self._database(quiet=True)
        if database is None:
            return
        try:
            self._number = database.next_cart_number()
        except Exception:  # noqa: BLE001
            diagnostics.log.debug("cart number unavailable", exc_info=True)
            self._number = ""

    def _retranslate(self) -> None:
        """Rebuild everything that was formatted in the old language."""
        for item in self._items:
            # A free line's name is a translated label, stored on the line
            # because that is what the cart shows and what a held cart carries.
            # Its sign and number were kept for exactly this.
            free = item.get("free")
            if free is None:
                continue
            sign, number = free
            key = "pos.free_plus" if sign > 0 else "pos.free_minus"
            item["name"] = self._i18n.text(key, number=number)
        # `tracked` is honoured here as well as in `_tile`: reformatting from
        # `tile["stock"]` alone turned an untracked product's infinity sign into the
        # 1.0 that stands in for it, so switching language used to tell the operator
        # a service had exactly one left.
        self._tiles = [dict(tile,
                            price_text=self._money(tile["price"]),
                            stock_text=(self._qty(tile["stock"])
                                        if tile.get("tracked", True)
                                        else "\u221e"))
                       for tile in self._tiles]
        self.tilesChanged.emit()
        self.changed.emit()

    def _database(self, quiet: bool = False):
        try:
            return legacy.database()
        except Exception as exc:  # noqa: BLE001
            if not quiet:
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

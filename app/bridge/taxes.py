"""The rates the shop charges, behind `app.taxes`.

    read      rows, total, enabled, inclusive, fallbackRate
    call      load(), tax(id), save(data, id), remove(id, reassignTo)
    emits     invalidated(), saved(tax), rejected(message)

WHY A DIALOG OFF THE PRODUCTS PAGE AND NOT A SCREEN OF ITS OWN

Settings already holds the three scalars: whether VAT is charged at all, the rate to
fall back on, and whether shelf prices already include it. What it cannot hold is a
*list* — "Normal 19%", "Reduced 9%", "Exempt 0%" — and that list is what a product
points at through `products.tax_id`. So the list lives with the other things a product
points at, behind the products page beside categories and units, and this controller is
read by `TaxesDialog` and by the product form's rate picker.

WHY A RATE IS NAMED AND NOT TYPED ON THE PRODUCT

A product carries `tax_id`, not a percentage, so the day a rate moves the whole
catalogue moves with it instead of 800 rows needing an edit. NULL is not 0: it means
"whatever the shop's default is", which is what nearly every product wants, while
naming "Exempt" is a decision the shop made rather than one it never got round to.

WHAT CANNOT BE DELETED

The default. `delete_tax` refuses it, because every product that names nothing falls
back to it and there would be nothing to fall back to. Mark another rate as the default
first — that is what frees this one.

NO `busy`, NO `error`

Three rows out of SQLite is not a wait, and there is no page here to put a spinner or an
error strip on: a failure is a sentence in the dialog, which is what `rejected` is for.
"""

from __future__ import annotations

from PySide6.QtCore import Property, QObject, Signal, Slot

from .. import diagnostics
from . import interop, legacy


class Taxes(QObject):
    rowsChanged = Signal()
    #: The three `tax.*` settings changed under us — the settings page writes the
    #: same keys this reports on.
    settingsChanged = Signal()

    invalidated = Signal()
    saved = Signal("QVariant")
    rejected = Signal(str)

    def __init__(self, i18n: QObject, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._i18n = i18n
        self._rows: list[dict] = []

    # =====================================================================
    # STATE
    # =====================================================================
    @Property(int, notify=rowsChanged)
    def total(self) -> int:
        return len(self._rows)

    @Property("QVariantList", notify=rowsChanged)
    def rows(self) -> list:
        return self._rows

    @Property(bool, notify=settingsChanged)
    def enabled(self) -> bool:
        """Whether VAT is charged at all.

        Off is the default and the common case for a corner shop, and it makes every
        rate inert — so the dialog says so rather than letting an operator wonder why
        nothing on a receipt changed.
        """
        return self._setting("tax.enabled", "0") == "1"

    @Property(bool, notify=settingsChanged)
    def inclusive(self) -> bool:
        """Whether a shelf price already contains the tax. The Algerian retail
        default, and the difference between extracting the tax and adding it on."""
        return self._setting("tax.prices_include_tax", "1") == "1"

    @Property(str, notify=settingsChanged)
    def fallbackRate(self) -> str:
        """The percentage used when no rate carries the default flag."""
        raw = self._setting("tax.default_rate", "19")
        try:
            return f"{float(raw):g}%"
        except (TypeError, ValueError):
            return str(raw)

    # =====================================================================
    # QUERIES
    # =====================================================================
    @Slot()
    def load(self) -> None:
        database = self._database()
        if database is None:
            return
        try:
            rows = database.fetch_taxes()
        except Exception as exc:  # noqa: BLE001
            diagnostics.log.error("taxes unreadable", exc_info=True)
            self.rejected.emit(str(exc))
            return
        self._rows = [self._row(row) for row in rows]
        self.rowsChanged.emit()
        self.settingsChanged.emit()

    @Slot(int, result="QVariant")
    def tax(self, tax_id: int) -> object:
        for row in self._rows:
            if row["id"] == int(tax_id):
                return row
        return None

    # =====================================================================
    # MUTATIONS
    # =====================================================================
    @Slot("QVariant", int)
    def save(self, data: object, tax_id: int) -> None:
        """Add or change one rate: `{name, rate, is_default}`.

        The duplicate name is caught here rather than left to the database, whose
        unique index raises an IntegrityError with a sentence about SQL in it — a
        clash with a rate the shop already has is an ordinary answer, not a fault.
        """
        values = interop.as_dict(data)
        name = str(values.get("name") or "").strip()
        if not name:
            self.rejected.emit(self._i18n.text("taxes.name.required",
                                               "A tax needs a name."))
            return
        rate = max(0.0, interop.as_float(values.get("rate")))
        is_default = bool(values.get("is_default"))
        tax_id = int(tax_id or 0)

        lowered = name.lower()
        for row in self._rows:
            if row["id"] != tax_id and row["name"].strip().lower() == lowered:
                self.rejected.emit(self._i18n.text(
                    "taxes.name.duplicate",
                    "There is already a rate with that name."))
                return

        database = self._database()
        if database is None:
            return
        try:
            tax = database.save_tax(name, rate, is_default, tax_id or None)
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.saved.emit(dict(tax))
        self.invalidated.emit()
        self.load()

    @Slot(int, int)
    def remove(self, tax_id: int, reassign_to: int) -> None:
        """Delete a rate; every product on it moves to `reassignTo`, or to the
        shop's default when that is 0."""
        database = self._database()
        if database is None:
            return
        try:
            database.delete_tax(int(tax_id), int(reassign_to) or None)
        except Exception as exc:  # noqa: BLE001
            # "cannot delete the default tax" is the sentence that says what to do.
            self.rejected.emit(str(exc))
            return
        self.invalidated.emit()
        self.load()

    # =====================================================================
    # INTERNALS
    # =====================================================================
    def _row(self, row: dict) -> dict:
        rate = float(row.get("rate") or 0.0)
        count = int(row.get("products") or 0)
        return {
            "id": row["id"],
            "name": row.get("name") or "",
            "rate": rate,
            "rate_text": f"{rate:g}%",
            "is_default": bool(row.get("is_default")),
            "products_text": str(count),
        }

    def _setting(self, key: str, default: str) -> str:
        database = self._database(quiet=True)
        if database is None:
            return default
        try:
            return str(database.get_setting(key, default) or default)
        except Exception:  # noqa: BLE001
            diagnostics.log.debug("setting unreadable: %s", key, exc_info=True)
            return default

    def _database(self, quiet: bool = False):
        try:
            return legacy.database()
        except Exception as exc:  # noqa: BLE001
            if not quiet:
                self.rejected.emit(str(exc))
            return None


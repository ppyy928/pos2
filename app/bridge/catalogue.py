"""The catalogue's furniture, behind `app.catalogue`.

Categories, units, multi-units, tile order and a CSV export — the five things the
Products screen links to that are not a product.

    categories()            list with product counts
    saveCategory(name, colour, id) / deleteCategory(id, reassignTo)
    reorderCategories(ids) / setCategoryVisibility(id, show)
    units() / saveUnit(name, abbreviation, id) / deleteUnit(id)
    multiUnits(productId) / saveMultiUnit(data, id) / deleteMultiUnit(id)
    productsInCategory(id) / reorderProducts(id, ids)
    favorites() / setFavorite(id, on) / reorderFavorites(ids) / clearFavorites()
    exportProducts(path)

DELETING A CATEGORY NEVER ORPHANS A PRODUCT
-------------------------------------------
`delete_category` reassigns first — to a category the caller names, or to the
"Uncategorized" one it creates if none is given. The dialog therefore has to say
where the products are going, which is why the count travels with every category.

MULTI-UNITS ARE THE OTHER PRICE A PRODUCT HAS
---------------------------------------------
A box of six sells at its own barcode and its own price, and the till's barcode
lookup already knows it: `lookup_barcode` returns a multi-unit hit with
`unit_qty` set to the box size, which is what makes one scan add six units. So
this is not a labelling feature — it is the second way a product can be sold.
"""

from __future__ import annotations

import csv
from pathlib import Path

from PySide6.QtCore import Property, QObject, Signal, Slot

from . import fmt, interop, legacy


class Catalogue(QObject):
    changed = Signal()
    rejected = Signal(str)
    exported = Signal(str, int)
    imported = Signal("QVariant")

    def __init__(self, i18n: QObject, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._i18n = i18n

    # =====================================================================
    # CATEGORIES
    # =====================================================================
    @Slot(result="QVariantList")
    def categories(self) -> list:
        database = self._database()
        if database is None:
            return []
        try:
            return [
                {
                    "id": row["id"],
                    "name": row["name"],
                    "color": row.get("color") or "",
                    "order": int(row.get("display_order") or 0),
                    "products": int(row.get("products") or 0),
                    "products_text": str(int(row.get("products") or 0)),
                }
                for row in database.fetch_categories_with_counts()
            ]
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return []

    @Slot(str, str, int)
    def saveCategory(self, name: str, colour: str, category_id: int) -> None:
        clean = (name or "").strip()
        if not clean:
            self.rejected.emit(self._i18n.text("categories.name.required",
                                               "A category needs a name."))
            return
        database = self._database()
        if database is None:
            return
        try:
            # An empty colour is not a missing value: save_category assigns a
            # distinct one from its palette, which is how a fresh shop ends up
            # with a legible tile grid without anybody choosing colours.
            database.save_category(clean, int(category_id) or None,
                                   color=(colour or None))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.changed.emit()

    @Slot(int, int)
    def deleteCategory(self, category_id: int, reassign_to: int) -> None:
        database = self._database()
        if database is None:
            return
        try:
            database.delete_category(int(category_id),
                                     int(reassign_to) or None)
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.changed.emit()

    @Slot("QVariant")
    def reorderCategories(self, ids: object) -> None:
        database = self._database()
        if database is None:
            return
        try:
            database.reorder_categories(self._ints(ids))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.changed.emit()

    @Slot(int, bool, result=int)
    def setCategoryVisibility(self, category_id: int, show: bool) -> int:
        """Hide or show a whole category on the till at once — pos returns how
        many products it touched, and the screen says so."""
        database = self._database()
        if database is None:
            return 0
        try:
            count = database.set_category_visibility(int(category_id), bool(show))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return 0
        self.changed.emit()
        return int(count or 0)

    # =====================================================================
    # UNITS
    # =====================================================================
    @Slot(result="QVariantList")
    def units(self) -> list:
        database = self._database()
        if database is None:
            return []
        try:
            return [
                {"id": row["id"], "name": row["name"],
                 "abbreviation": row.get("abbreviation") or ""}
                for row in database.fetch_units()
            ]
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return []

    @Slot(str, str, int)
    def saveUnit(self, name: str, abbreviation: str, unit_id: int) -> None:
        clean = (name or "").strip()
        if not clean:
            self.rejected.emit(self._i18n.text("units.name.required"))
            return
        database = self._database()
        if database is None:
            return
        try:
            database.save_unit(clean, (abbreviation or "").strip(),
                               int(unit_id) or None)
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.changed.emit()

    @Slot(int)
    def deleteUnit(self, unit_id: int) -> None:
        database = self._database()
        if database is None:
            return
        try:
            database.delete_unit(int(unit_id))
        except Exception as exc:  # noqa: BLE001
            # A unit still used by a product cannot go; the sentence says so.
            self.rejected.emit(str(exc))
            return
        self.changed.emit()

    # =====================================================================
    # MULTI-UNITS
    # =====================================================================
    @Slot(int, result="QVariantList")
    def multiUnits(self, product_id: int) -> list:
        database = self._database()
        if database is None:
            return []
        try:
            rows = database.fetch_multi_units(int(product_id) or None)
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return []
        return [
            {
                "id": row["id"],
                "product_id": row["product_id"],
                "product": row.get("product_name") or "",
                "name": row["name"],
                "base_qty": float(row.get("base_qty") or 1.0),
                "qty_text": fmt.qty(row.get("base_qty") or 1.0),
                "price": float(row.get("price") or 0.0),
                "price_text": fmt.money(row.get("price")),
                "barcode": row.get("barcode") or "",
            }
            for row in rows
        ]

    @Slot("QVariant", int)
    def saveMultiUnit(self, data: object, multi_unit_id: int) -> None:
        values = interop.as_dict(data)
        name = str(values.get("name") or "").strip()
        product_id = int(values.get("product_id") or 0)
        if not name or not product_id:
            self.rejected.emit(self._i18n.text("mu.name.required"))
            return
        qty = interop.as_float(values.get("base_qty"), 1.0)
        if qty <= 0:
            self.rejected.emit(self._i18n.text(
                "mu.qty.required", "How many units does this pack hold?"))
            return
        database = self._database()
        if database is None:
            return
        try:
            database.save_multi_unit({
                "product_id": product_id,
                "name": name,
                "base_qty": qty,
                "price": interop.as_float(values.get("price")),
                "barcode": str(values.get("barcode") or "").strip(),
            }, int(multi_unit_id) or None)
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.changed.emit()

    @Slot(int)
    def deleteMultiUnit(self, multi_unit_id: int) -> None:
        database = self._database()
        if database is None:
            return
        try:
            database.delete_multi_unit(int(multi_unit_id))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.changed.emit()

    # =====================================================================
    # TILE ORDER
    # =====================================================================
    @Slot(int, result="QVariantList")
    def productsInCategory(self, category_id: int) -> list:
        database = self._database()
        if database is None:
            return []
        try:
            rows = database.fetch_catalog_cards(int(category_id) or None)
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return []
        return [self._card(row) for row in rows]

    @Slot(int, "QVariant")
    def reorderProducts(self, category_id: int, ids: object) -> None:
        """The order the tiles appear in, which is the whole point of arranging:
        a cashier's hand goes to the same place every time."""
        database = self._database()
        if database is None:
            return
        try:
            database.reorder_products(int(category_id) or None, self._ints(ids))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.changed.emit()

    @Slot(result="QVariantList")
    def favorites(self) -> list:
        database = self._database()
        if database is None:
            return []
        try:
            rows = database.fetch_catalog_cards(favorite_only=True)
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return []
        return [self._card(row) for row in rows]

    @staticmethod
    def _card(row: dict) -> dict:
        """One tile for the arrange screen.

        WHY THERE IS NO PRICE ON IT

        There used to be, and it was always "0.00". These two slots read
        `fetch_products_in_category`, whose SELECT is `id, name, position,
        show_on_pos` — so `sale_price`, `stock` and `is_favorite` were all absent,
        `fmt_money(None)` rendered "0.00", `fmt_qty(None)` rendered "0", and
        `bool(None)` left every star hollow on every category tab. The Favourites
        tab looked right only because `fetch_favorites` goes through a different row
        builder that happens to carry those columns. That is most of "it works on
        some tiles and not others".

        `fetch_catalog_cards` is the function pos wrote for exactly this screen —
        its docstring says "product cards for the arrange / favorites managers" —
        and it returns the favourite flag and the visibility flag but no price. Which
        is the right trade: a price is not a lever on a screen about order, and a
        wrong price is worse than none. Both tabs now read the same function, so
        they cannot disagree again.

        `hidden` is passed through because `fetch_catalog_cards` includes products
        with `show_on_pos = 0` while the till's own query excludes them. Without the
        flag, arranging one of those is a swap that visibly does nothing.
        """
        return {
            "id": row["id"],
            "name": row["name"],
            "favorite": bool(row.get("is_favorite")),
            "hidden": not bool(row.get("show_on_pos", True)),
        }

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
        self.changed.emit()

    @Slot("QVariant")
    def reorderFavorites(self, ids: object) -> None:
        database = self._database()
        if database is None:
            return
        try:
            database.reorder_favorites(self._ints(ids))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.changed.emit()

    @Slot(result=int)
    def clearFavorites(self) -> int:
        database = self._database()
        if database is None:
            return 0
        try:
            count = database.clear_favorites()
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return 0
        self.changed.emit()
        return int(count or 0)

    # =====================================================================
    # IMPORT
    # =====================================================================
    #: The fields import_products can be handed, in the order the dialog shows
    #: them. `name` is the only one it cannot do without.
    FIELDS = ("name", "barcode", "purchase_price", "sale_price", "stock",
              "low_stock_threshold", "category")

    @Property("QVariantList", constant=True)
    def importFields(self) -> list:
        return [
            {"key": key,
             "label": self._i18n.text(f"import.field.{key}"),
             "required": key == "name"}
            for key in self.FIELDS
        ]

    @Slot(str, result="QVariant")
    def csvPreview(self, path: str) -> object:
        """The header row and the first few lines, so the mapping can be made
        against what is actually in the file.

        A guess is offered per column by matching its heading against the field
        names — an exported file maps itself, which is the common case — but every
        column stays choosable, because somebody else's spreadsheet will not use
        our words.
        """
        target = self._localPath(path)
        if not target:
            return None
        try:
            with open(target, newline="", encoding="utf-8-sig") as handle:
                reader = csv.reader(handle)
                rows = []
                for index, row in enumerate(reader):
                    if index > 6:
                        break
                    if any(cell.strip() for cell in row):
                        rows.append(row)
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return None
        if not rows:
            self.rejected.emit(self._i18n.text("import.empty",
                                               "That file has no rows in it."))
            return None

        header = [cell.strip() for cell in rows[0]]
        guess = {}
        for key in self.FIELDS:
            for index, heading in enumerate(header):
                if heading.lower().replace(" ", "_") == key:
                    guess[key] = index
                    break
        return {
            "path": str(target),
            "columns": header,
            "rows": rows[1:],
            "guess": guess,
        }

    @Slot(str, "QVariant", str)
    def importProducts(self, path: str, mapping: object, policy: str) -> None:
        """Run the import. `mapping` is {field: column index}.

        The policy is pos's: an existing barcode is either skipped or updated.
        There is no third option on purpose — a file that half-matches the
        catalogue is the normal case, and silently creating duplicates of the
        matches is the one outcome nobody wants.
        """
        target = self._localPath(path)
        if not target:
            return
        columns = {}
        for key, index in interop.as_dict(mapping).items():
            try:
                position = int(index)
            except (TypeError, ValueError):
                continue
            if position >= 0:
                columns[str(key)] = position
        if "name" not in columns:
            self.rejected.emit(self._i18n.text(
                "import.name.required",
                "Choose which column holds the product name."))
            return

        database = self._database()
        if database is None:
            return
        try:
            result = database.import_products(
                str(target), columns,
                "update" if policy == "update" else "skip")
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return

        payload = dict(result)
        payload["errors"] = [
            {"row": str(entry.get("row") or ""),
             "reason": str(entry.get("reason") or "")}
            for entry in (payload.get("errors") or [])
        ]
        payload["error_count"] = len(payload["errors"])
        self.imported.emit(payload)
        self.changed.emit()

    def _localPath(self, path: str) -> str:
        """A QML FileDialog hands back a file: URL; everything below wants a path."""
        text = (path or "").strip()
        if not text:
            return ""
        if text.startswith("file:///"):
            return text[8:] if len(text) > 9 and text[9] == ":" else text[7:]
        if text.startswith("file://"):
            return text[7:]
        return text

    # =====================================================================
    # EXPORT
    # =====================================================================
    @Slot(str)
    def exportProducts(self, folder: str) -> None:
        """The catalogue as a CSV, in the same column order pos imports.

        Written here rather than in the database module because it is a display
        concern: the numbers are raw so the file can be edited and imported back,
        and the header is the one `import_products` expects to be mapped.
        """
        database = self._database()
        if database is None:
            return
        try:
            result = database.fetch_products("", 1, 1_000_000, None)
            target = Path(self._folder(folder)) / "products.csv"
            with open(target, "w", newline="", encoding="utf-8-sig") as handle:
                writer = csv.writer(handle)
                writer.writerow(["name", "barcode", "purchase_price",
                                 "sale_price", "stock", "category", "unit"])
                for row in result["rows"]:
                    writer.writerow([
                        row.get("name") or "",
                        row.get("barcode") or "",
                        row.get("purchase_price") or 0,
                        row.get("sale_price") or 0,
                        row.get("stock") or 0,
                        row.get("category") or "",
                        row.get("unit") or "",
                    ])
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.exported.emit(str(target), len(result["rows"]))

    def _folder(self, folder: str) -> str:
        """Where a file goes when the screen did not say. pos keeps exports beside
        the database, which is also where its backups live — one place to look."""
        text = (folder or "").strip()
        if text:
            return text
        database = legacy.database()
        return str(getattr(database, "DATA_DIR", Path.home()))

    # =====================================================================
    # INTERNALS
    # =====================================================================
    def _ints(self, value: object) -> list[int]:
        to_variant = getattr(value, "toVariant", None)
        if callable(to_variant):
            value = to_variant()
        out = []
        for entry in (value or []):
            try:
                out.append(int(entry))
            except (TypeError, ValueError):
                continue
        return out

    def _database(self):
        try:
            return legacy.database()
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return None

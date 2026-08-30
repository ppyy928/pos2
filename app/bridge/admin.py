"""Settings, backups and the dashboard, behind `app.settings`, `app.backups`
and `app.dashboard`.

Three small controllers over pos's own key/value store, backup helpers and report
functions. They share a file because none of them owns enough behaviour to justify
one, and they are the three screens that read the whole application rather than one
part of it.

WHY SETTINGS ARE TYPED HERE AND NOT IN QML
------------------------------------------
`DEFAULT_SETTINGS` stores everything as a string — "1" and "0" for flags, "80" for
a paper width. The kind of each key is a fact about the setting, so it is declared
here once, and QML gets `{key, kind, value, label}` and hands back a value of the
same kind. Otherwise every screen that touches a setting would have to remember
that a switch is the string "1".
"""

from __future__ import annotations

import csv
from pathlib import Path

from PySide6.QtCore import Property, QObject, Signal, Slot

from . import fmt, interop, legacy, reportsql
from . import reportview as rv

#: Every key in pos's DEFAULT_SETTINGS, with the group it belongs to, the kind of
#: control that edits it, the catalogue key for its label and an English fallback
#: for the ones pos never had to name (it hardcoded those labels in widgets).
#:
#: The kinds matter because everything in that store is a string: "1" and "0" are
#: flags, "80" is a paper width, "ar" is a language. QML cannot guess which is
#: which, and a screen that shows a switch as a text box saying "1" — which is
#: exactly what this used to do — is asking the operator to know the storage
#: format.
SPEC: dict[str, dict] = {
    # -- the shop ---------------------------------------------------------
    "store.name": {"group": "store", "kind": "text",
                   "key": "settings.store.name", "text": "Shop name"},
    "store.phone": {"group": "store", "kind": "text",
                    "key": "settings.store.phone", "text": "Phone"},
    "store.address": {"group": "store", "kind": "text",
                      "key": "settings.store.address", "text": "Address"},
    "store.email": {"group": "store", "kind": "text",
                    "key": "settings.store.email", "text": "Email"},
    # -- what the registrar calls this shop -------------------------------
    #
    # A till receipt does not need them and a proper invoice cannot be issued
    # without them. They are their own group rather than four more lines under
    # "the shop", because they are typed once when the business is registered and
    # then never touched, while the shop's name and phone change with a move.
    "store.rc": {"group": "legal", "kind": "text",
                 "key": "settings.store.rc", "text": "Trade register (RC)"},
    "store.nif": {"group": "legal", "kind": "text",
                  "key": "settings.store.nif", "text": "Tax ID (NIF)"},
    "store.nis": {"group": "legal", "kind": "text",
                  "key": "settings.store.nis", "text": "Statistical ID (NIS)"},
    "store.ai": {"group": "legal", "kind": "text",
                 "key": "settings.store.ai", "text": "Article number (AI)"},
    "store.receipt_footer": {"group": "store", "kind": "text",
                             "key": "settings.store.footer",
                             "text": "Receipt footer"},
    # -- TVA ---------------------------------------------------------------
    #
    # Off by default: a shop that is not registered for it must never see the word,
    # and switching it on has to be a decision rather than a default that quietly
    # reinterprets every price on the shelf.
    "tax.enabled": {"group": "tax", "kind": "flag",
                    "key": "settings.tax.enabled", "text": "Charge VAT (TVA)"},
    "tax.default_rate": {"group": "tax", "kind": "number",
                         "key": "settings.tax.rate",
                         "text": "Default rate (%)"},
    "tax.prices_include_tax": {
        "group": "tax", "kind": "flag",
        "key": "settings.tax.inclusive",
        # The Algerian retail default, and the reason the arithmetic is a division
        # rather than a multiplication: a shelf price of 130 DA IS what the
        # customer pays, so the tax inside it is extracted, not added on top.
        "text": "Shelf prices already include VAT",
    },
    # -- how it looks -----------------------------------------------------
    "ui.language": {
        "group": "appearance", "kind": "choice", "key": "settings.language",
        "text": "Language",
        # Language names are written in the language itself, everywhere. There is
        # nothing to translate.
        "options": [("en", "English"), ("fr", "Français"), ("ar", "العربية")],
    },
    "ui.font_scale": {
        "group": "appearance", "kind": "choice", "key": "settings.font_scale",
        "text": "Text size",
        "options": [("normal", "settings.font.normal"),
                    ("large", "settings.font.large"),
                    ("extra_large", "settings.font.extra_large")],
    },
    "ui.theme": {
        "group": "appearance", "kind": "choice", "key": "settings.theme",
        "text": "Theme",
        "options": [("light", "settings.theme.light"),
                    ("dark", "settings.theme.dark")],
    },
    # -- selling ----------------------------------------------------------
    "sale.allow_debt": {"group": "sale", "kind": "flag",
                        "key": "settings.sale.allow_debt",
                        "text": "Allow sales on account"},
    "sale.allow_partial": {"group": "sale", "kind": "flag",
                           "key": "settings.sale.allow_partial",
                           "text": "Allow partial payment"},
    # -- receipts ---------------------------------------------------------
    "receipt.printer": {"group": "receipt", "kind": "text",
                        "key": "settings.receipt.printer", "text": "Printer"},
    "receipt.copies": {"group": "receipt", "kind": "number",
                       "key": "settings.receipt.copies", "text": "Copies"},
    "receipt.paper_width": {
        "group": "receipt", "kind": "choice",
        "key": "settings.receipt.paper_width", "text": "Paper width",
        # The two widths thermal paper comes in. A free number here is a receipt
        # printed off the edge of the roll.
        "options": [("58", "58 mm"), ("80", "80 mm")],
    },
    "receipt.auto_print": {"group": "receipt", "kind": "flag",
                           "key": "settings.receipt.auto_print",
                           "text": "Print automatically after a sale"},
    "receipt.show_store_info": {"group": "receipt", "kind": "flag",
                                "key": "settings.receipt.show_store_info",
                                "text": "Show the shop's details"},
    "receipt.show_store": {"group": "receipt", "kind": "flag",
                           "key": "settings.receipt.show_store",
                           "text": "Show the shop name"},
    "receipt.show_phone": {"group": "receipt", "kind": "flag",
                           "key": "settings.receipt.show_phone",
                           "text": "Show the phone number"},
    "receipt.show_address": {"group": "receipt", "kind": "flag",
                             "key": "settings.receipt.show_address",
                             "text": "Show the address"},
    "receipt.show_number": {"group": "receipt", "kind": "flag",
                            "key": "settings.receipt.show_number",
                            "text": "Show the invoice number"},
    "receipt.show_customer": {"group": "receipt", "kind": "flag",
                              "key": "settings.receipt.show_customer",
                              "text": "Show the customer"},
    "receipt.show_payment": {"group": "receipt", "kind": "flag",
                             "key": "settings.receipt.show_payment",
                             "text": "Show how it was paid"},
    "receipt.show_footer": {"group": "receipt", "kind": "flag",
                            "key": "settings.receipt.show_footer",
                            "text": "Show the footer"},
    "receipt.show_legal": {"group": "receipt", "kind": "flag",
                           "key": "settings.receipt.show_legal",
                           "text": "Show the registration numbers"},
    # -- labels -----------------------------------------------------------
    "barcode.printer": {"group": "barcode", "kind": "text",
                        "key": "settings.barcode.printer", "text": "Printer"},
    "barcode.label_width": {"group": "barcode", "kind": "number",
                            "key": "settings.barcode.width",
                            "text": "Label width (mm)"},
    "barcode.label_height": {"group": "barcode", "kind": "number",
                             "key": "settings.barcode.height",
                             "text": "Label height (mm)"},
    "barcode.show_store": {"group": "barcode", "kind": "flag",
                           "key": "settings.barcode.show_store",
                           "text": "Print the shop name"},
    "barcode.show_name": {"group": "barcode", "kind": "flag",
                          "key": "settings.barcode.show_name",
                          "text": "Print the product name"},
    "barcode.show_price": {"group": "barcode", "kind": "flag",
                           "key": "settings.barcode.show_price",
                           "text": "Print the price"},
    "barcode.show_bars": {"group": "barcode", "kind": "flag",
                          "key": "settings.barcode.show_bars",
                          "text": "Print the bars"},
    "barcode.show_number": {"group": "barcode", "kind": "flag",
                            "key": "settings.barcode.show_number",
                            "text": "Print the code as digits"},
    # -- the till itself --------------------------------------------------
    "security.auto_lock_minutes": {"group": "security", "kind": "number",
                                   "key": "settings.security.auto_lock",
                                   "text": "Lock after (minutes, 0 = never)"},
}

#: Group order and their labels — pos names five of the six.
GROUPS: tuple[tuple[str, str, str], ...] = (
    ("store", "settings.store", "Shop"),
    # Registration and tax sit next to the shop's own details and before anything
    # about how the app looks: they are what a business is, not how it behaves.
    ("legal", "settings.legal", "Registration"),
    ("tax", "settings.tax", "VAT"),
    ("appearance", "settings.appearance", "Appearance"),
    ("sale", "settings.sale", "Selling"),
    ("receipt", "settings.receipt", "Receipts"),
    ("barcode", "settings.barcode", "Labels"),
    ("security", "settings.security", "Security"),
)



class Settings(QObject):
    groupsChanged = Signal()
    saved = Signal(str)
    rejected = Signal(str)

    def __init__(self, i18n: QObject, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._i18n = i18n
        self._groups: list[dict] = []
        i18n.languageChanged.connect(self.load)

    @Property("QVariantList", notify=groupsChanged)
    def groups(self) -> list:
        return self._groups

    @Slot()
    def load(self) -> None:
        database = self._database()
        if database is None:
            return
        defaults = dict(getattr(database, "DEFAULT_SETTINGS", {}))
        buckets: dict[str, list] = {name: [] for name, _key, _text in GROUPS}

        for key in defaults:
            spec = SPEC.get(key)
            if spec is None:
                # A key pos added that this table has not been taught. Shown as
                # text in the last group rather than hidden, so it is visible that
                # something new arrived.
                spec = {"group": GROUPS[-1][0], "kind": "text",
                        "key": "", "text": key}
            try:
                raw = database.get_setting(key, defaults[key])
            except Exception as exc:  # noqa: BLE001
                self.rejected.emit(str(exc))
                return
            buckets.setdefault(spec["group"], []).append({
                "key": key,
                "kind": spec["kind"],
                "label": self._i18n.text(spec.get("key") or key, spec["text"]),
                "value": raw == "1" if spec["kind"] == "flag" else raw,
                "options": self._options(spec),
            })

        self._groups = [
            {
                "key": name,
                "label": self._i18n.text(label_key, label_text),
                "items": buckets.get(name) or [],
            }
            for name, label_key, label_text in GROUPS
            if buckets.get(name)
        ]
        self.groupsChanged.emit()

    def _options(self, spec: dict) -> list:
        """A choice's values, with their labels resolved.

        An option's label is either a catalogue key — pos names the font sizes and
        the themes — or literal text, for the things that are the same in every
        language: "58 mm", "Français".
        """
        out = []
        for value, label in (spec.get("options") or []):
            out.append({
                "value": value,
                "label": self._i18n.text(label, label) if "." in label else label,
            })
        return out

    @Slot(str, "QVariant")
    def put(self, key: str, value: object) -> None:
        """Write one setting. Flags are stored as pos stores them — "1" / "0" —
        so anything that reads them without going through this controller still
        sees what it expects."""
        database = self._database()
        if database is None:
            return
        spec = SPEC.get(key) or {"kind": "text"}
        kind = spec["kind"]
        if kind == "flag":
            text = "1" if value in (True, 1, "1", "true") else "0"
        elif kind == "number":
            number = interop.as_float(value)
            text = str(int(number)) if number == int(number) else str(number)
        else:
            text = str(value if value is not None else "")
        try:
            database.set_setting(key, text)
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self._apply(key, text)
        self.saved.emit(key)

    def _apply(self, key: str, value: str) -> None:
        """Two settings are also the running application.

        Language and theme are stored *and* switched: a screen that saves "dark"
        and stays light is asking to be pressed twice. Text size is stored only —
        it is applied to the QApplication font at startup, and re-applying it to a
        live window is a change for run.py to make, not for a controller.
        """
        if key == "ui.language":
            self._i18n.setLanguage(value)
            return
        if key == "ui.theme":
            try:
                import fluentpyside

                manager = fluentpyside.theme_manager()
                if manager is not None:
                    manager.setTheme(value)
            except Exception as exc:  # noqa: BLE001
                print(f"bridge: could not switch the theme ({exc})")

    def _database(self):
        try:
            return legacy.database()
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return None


class Backups(QObject):
    """Copies of the database file, and the way back from one.

    Restoring is the most destructive thing this application can do — it replaces
    the live database — so the controller does exactly what it is told and says
    what happened, and the screen is where the confirmation lives.
    """

    rowsChanged = Signal()
    created = Signal("QVariant")
    restored = Signal(str)
    rejected = Signal(str)

    def __init__(self, i18n: QObject, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._i18n = i18n
        self._rows: list[dict] = []

    @Property("QVariantList", notify=rowsChanged)
    def rows(self) -> list:
        return self._rows

    @Property(int, notify=rowsChanged)
    def total(self) -> int:
        return len(self._rows)

    @Slot()
    def load(self) -> None:
        database = self._database()
        if database is None:
            return
        try:
            self._rows = [
                {
                    "name": row["name"],
                    "size": int(row.get("size") or 0),
                    "size_text": self._size(row.get("size") or 0),
                    "when": fmt.when(row.get("created")),
                }
                for row in database.list_backups()
            ]
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            self._rows = []
        self.rowsChanged.emit()

    @Slot()
    def create(self) -> None:
        database = self._database()
        if database is None:
            return
        try:
            result = database.create_backup()
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        payload = dict(result)
        payload["size_text"] = self._size(payload.get("size") or 0)
        self.created.emit(payload)
        self.load()

    @Slot(str)
    def restore(self, name: str) -> None:
        database = self._database()
        if database is None:
            return
        try:
            database.restore_backup(str(name))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.restored.emit(str(name))

    def _size(self, size: object) -> str:
        value = float(size or 0)
        for unit in ("B", "KB", "MB", "GB"):
            if value < 1024 or unit == "GB":
                return f"{value:.0f} {unit}" if unit == "B" else f"{value:.1f} {unit}"
            value /= 1024
        return f"{value:.1f} GB"

    def _database(self):
        try:
            return legacy.database()
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return None


#: How many days back the dashboard looks, counting today as one, when the screen
#: does not say.
#:
#: The screen now carries a period selector — today / last 7 / last 30 — and passes
#: its choice to load(). This is the fallback for a caller that passes nothing, and
#: the week is the right default for a morning screen: one day of a curve is a dot,
#: and a payment donut at nine in the morning is two sales.
TREND_DAYS = 7

#: Rows in a ranking. Eight, not pos's Top-10 default: a horizontal bar chart is
#: one row of label + value + bar per item, and eight of them at this app's 1.5x
#: type scale is already 380px of card. pos could afford ten because its rankings
#: grew the page and the page scrolled; here they sit above a table that needs its
#: own height.
TOP_N = 8

#: Payment type -> tone name.
#:
#: pos's own mapping (pos/app/pages/dashboard.py:59): cash is money in the drawer,
#: partial is information, debt is a promise. Tokens.toneInk turns those three names
#: into emerald / teal / amber, which is the same colour the nav rail and the KPI
#: cards give the same ideas.
#:
#: Carried ON THE SLICE rather than left to the donut's palette, because the slices
#: are sorted by size: a positional palette would recolour cash the first day debt
#: overtook it, and on this screen the colour is the thing an operator reads before
#: the label.
PAY_TONES = {"cash": "success", "partial": "info", "debt": "warning"}


class Dashboard(QObject):
    """The morning question: what happened, what is owed, what is running out.

    Every figure is one of pos's report functions. Nothing here is computed from
    another screen's numbers — a dashboard that disagreed with the page it
    summarises would be worse than no dashboard.

    TWO KINDS OF FIGURE, AND ONLY ONE OF THEM HAS A PERIOD

    Sales, profit and expenses are quantities over the range the screen asked for.
    Stock value, what customers owe and what the shop owes suppliers are balances:
    they are true right now and pos's own functions for them take no dates at all.
    So the period selector governs three of the six cards and all three charts, and
    the other three answer "now" whatever it is set to — which is what a debt is.

    The charts are a second query, kept separate from the cards so that
    `dashboard_stats` failing costs three charts rather than six figures.
    """

    changed = Signal()
    busyChanged = Signal()
    rejected = Signal(str)

    def __init__(self, i18n: QObject, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._i18n = i18n
        self._cards: dict = {}
        self._series: dict = {}
        self._busy = False

    @Property("QVariantMap", notify=changed)
    def cards(self) -> dict:
        return self._cards

    @Property("QVariantMap", notify=changed)
    def series(self) -> dict:
        """`{ trend, mix, ranking, range, total }` for the three chart cards.

        Each of the first three is a list of `{label, value, valueText}` — the raw
        number for the arithmetic a chart has to do, and the formatted string for
        the one it displays. Empty lists rather than a missing key, so QML can bind
        `series.trend` without guarding every read.
        """
        return self._series

    @Property(bool, notify=busyChanged)
    def busy(self) -> bool:
        return self._busy

    @Slot(int)
    def load(self, days: int = TREND_DAYS) -> None:
        """Everything, over the last `days` days counting today as one.

        `days` is a count rather than a pair of dates because that is what the
        selector on the screen offers — today, the week, the month — and turning
        three integers into two ISO strings in QML would be date arithmetic in the
        one language of the three that has no date type worth the name. 1 means
        today alone.
        """
        database = self._database()
        if database is None:
            return
        span = max(1, int(days or TREND_DAYS))
        self._set_busy(True)
        try:
            from datetime import date, timedelta

            end = date.today()
            start = end - timedelta(days=span - 1)
            since, until = start.isoformat(), end.isoformat()

            sales = database.report_sales(since, until)["summary"]
            profit = database.report_profit(since, until)["summary"]
            expenses = database.report_expenses(since, until)["summary"]
            # No dates: these three are balances, not quantities over a period.
            inventory = database.report_inventory()["summary"]
            owed_to_us = database.report_customer_debts()["summary"]
            we_owe = database.report_supplier_debts()["summary"]

            self._cards = {
                "sales_count": str(int(sales.get("count") or 0)),
                "sales_total": fmt.compact(sales.get("total") or 0.0),
                "sales_total_full": fmt.money(sales.get("total") or 0.0),
                "profit": fmt.compact(profit.get("profit") or 0.0),
                "profit_full": fmt.money(profit.get("profit") or 0.0),
                "profit_raw": float(profit.get("profit") or 0.0),
                "expenses": fmt.compact(expenses.get("total") or 0.0),
                "expenses_full": fmt.money(expenses.get("total") or 0.0),
                "inventory_value": fmt.compact(inventory.get("value") or 0.0),
                "inventory_value_full": fmt.money(inventory.get("value") or 0.0),
                "low_stock": str(int(inventory.get("low_stock") or 0)),
                "low_stock_raw": int(inventory.get("low_stock") or 0),
                "customer_debt": fmt.compact(owed_to_us.get("total") or 0.0),
                "customer_debt_full": fmt.money(owed_to_us.get("total") or 0.0),
                "customer_debt_raw": float(owed_to_us.get("total") or 0.0),
                "supplier_debt": fmt.compact(we_owe.get("total") or 0.0),
                "supplier_debt_full": fmt.money(we_owe.get("total") or 0.0),
                "supplier_debt_raw": float(we_owe.get("total") or 0.0),
            }
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            self._cards = {}
        finally:
            self._set_busy(False)
        self._load_series(database, since, until)
        self.changed.emit()

    def _load_series(self, database, since: str, until: str) -> None:
        """The three chart series, over the range the cards above used.

        One `dashboard_stats` call rather than three: it already returns the
        gap-filled daily totals, the payment split and the top products in one
        short-lived session, and it is the same function pos's own dashboard drew
        from — so the two products cannot disagree about what "top product" means.

        Its own try/except, and it does NOT emit `rejected`. The six cards above
        these charts come from six separate report functions that have already
        succeeded by the time this runs; a failure here is three missing cards, and
        a toast about it would be a complaint the operator can do nothing with on a
        screen that is otherwise working. It goes to stderr, where the rest of this
        application's non-fatal notes go.
        """
        try:
            stats = database.dashboard_stats(since, until)

            trend = [
                self._point(str(point.get("day") or ""), point.get("total"))
                for point in (stats.get("profit_days") or [])
            ]

            # The payment types are stored as the raw enum ("cash" / "debt" /
            # "partial") because that is what the column holds. pos names them in
            # all three languages already. Sorted descending for the same reason
            # Reports._points sorts its mix: a ring is read clockwise from noon.
            mix = [
                self._point(
                    self._i18n.text(f"pay.type.{row.get('label')}",
                                    str(row.get("label") or "")),
                    row.get("value"),
                    PAY_TONES.get(str(row.get("label") or ""), ""),
                )
                for row in (stats.get("payment_mix") or [])
                if float(row.get("value") or 0.0) > 0
            ]
            mix.sort(key=lambda point: point["value"], reverse=True)

            ranking = [
                self._point(str(row.get("label") or ""), row.get("value"))
                for row in (stats.get("top_products") or [])
                if float(row.get("value") or 0.0) > 0
            ][:TOP_N]

            self._series = {
                "trend": trend,
                "mix": mix,
                "ranking": ranking,
                # Printed under every chart title. Three of the six cards above are
                # balances that ignore the period entirely, and a curve is the one
                # thing on the screen whose meaning is unreadable without knowing
                # which days it covers.
                "range": f"{since} \u2192 {until}",
                "total": fmt.money(sum(row["value"] for row in mix)),
            }
        except Exception as exc:  # noqa: BLE001
            import sys

            print(f"bridge: dashboard charts unavailable ({exc})", file=sys.stderr)
            self._series = {"trend": [], "mix": [], "ranking": [],
                            "range": "", "total": ""}

    @staticmethod
    def _point(label: str, value: object, tone: str = "") -> dict:
        """One chart point: the number to draw with, and the string to print.

        Both, always. A chart needs the float to scale an arc or a bar, and the
        screen needs pos's own fmt_money for the figure beside it — deriving the
        second from the first in JavaScript would be a second currency rule.

        `tone` is a NAME, not a colour, because that is what crosses this boundary
        everywhere else in the bridge: KpiCard, DataTable and the badges all take
        "success" | "info" | "warning" | "danger" | "primary" and resolve it through
        Tokens. An empty tone leaves the colour to the chart's palette.
        """
        amount = float(value or 0.0)
        return {"label": label, "value": amount,
                "valueText": fmt.money(amount), "tone": tone}

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


# =====================================================================
# REPORTS
# =====================================================================
#: The six tabs, in order, with the catalogue key and the glyph the strip shows.
#:
#: This screen used to be eight flat "kinds" — sales, profit, purchases, expenses,
#: cash, inventory, customer debt, supplier debt — each one a table with a summary
#: over it. Six subjects replace them, and each subject now owns its own figures, its
#: own charts and as many tables as the question needs. Expenses folded into Cash
#: (they are `CashMovement` rows of `type == "expense"`, not a separate ledger),
#: profit became a P&L that also carries what expenses leave of it, and the two debt
#: reports became the customer and supplier sides of the tabs they belong to.
REPORT_TABS: tuple[dict, ...] = (
    {"key": "sales", "title": "reports.tab.sales", "text": "Sales",
     "glyph": "ic_fluent_receipt_money_20_regular"},
    {"key": "inventory", "title": "reports.tab.inventory", "text": "Inventory",
     "glyph": "ic_fluent_box_multiple_20_regular"},
    {"key": "purchases", "title": "reports.tab.purchases", "text": "Purchases",
     "glyph": "ic_fluent_vehicle_truck_profile_20_regular"},
    {"key": "customers", "title": "reports.tab.customers", "text": "Customers",
     "glyph": "ic_fluent_people_team_20_regular"},
    {"key": "cash", "title": "reports.tab.cash", "text": "Cash",
     "glyph": "ic_fluent_coin_multiple_20_regular"},
    {"key": "pnl", "title": "reports.tab.pnl", "text": "Profit & loss",
     "glyph": "ic_fluent_data_trending_20_regular"},
)

#: Day-of-week labels, indexed the way SQLite's `strftime('%w')` numbers them —
#: 0 is Sunday. pos has no catalogue keys for weekday names, so these carry their
#: own; three letters, because the chart has seven bars and one line for them.
DOW_KEYS = (
    ("reports.dow.sun", "Sun"), ("reports.dow.mon", "Mon"),
    ("reports.dow.tue", "Tue"), ("reports.dow.wed", "Wed"),
    ("reports.dow.thu", "Thu"), ("reports.dow.fri", "Fri"),
    ("reports.dow.sat", "Sat"),
)


class Reports(QObject):
    """Six tabs of detailed reporting over one date range.

    WHAT CROSSES TO QML, AND IN WHAT SHAPE

    Four properties, and every tab fills the same four, so the screen has one layout
    to draw rather than six:

        cards   [{label, value, tooltip, subtext, tone, glyph, raw}]
        charts  [{id, kind: line|bars|donut, title, subtitle, ...payload}]
        tables  [{id, title, columns, rows, sortColumn, sortDescending}]
        note    a sentence the tab has to say out loud, or ""

    Colours are HUE NAMES ("indigo", "amber"), not colours. Tokens owns the palette
    and resolves them at the far end — the same rule `tone` follows everywhere else
    in this bridge.

    RAW NUMBERS ARE KEPT ON THIS SIDE

    `tables[].rows` are formatted strings, because that is what a table draws. The
    raw rows stay in `self._raw`, and sorting and CSV export both read those. Sorting
    formatted money is how `"1,234.50" < "9.00"` becomes true; DataTable therefore
    asks for a sort instead of doing one, and this is where the request lands.

    THE SQL IS NOT pos'S

    `reportsql` owns every query on this screen. Its module docstring lists the three
    defects in `db_analytics.report_*_detail` that made reaching for them untenable —
    including the one that raises outright for any range over 45 selling days, which
    is the range a P&L tab is most often asked for.
    """

    rowsChanged = Signal()
    busyChanged = Signal()
    rejected = Signal(str)
    exported = Signal(str, int)

    def __init__(self, i18n: QObject, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._i18n = i18n
        self._tab = "sales"
        self._cards: list[dict] = []
        self._charts: list[dict] = []
        self._tables: list[dict] = []
        self._raw: dict[str, list[dict]] = {}
        self._sort: dict[str, tuple[int, bool]] = {}
        self._note = ""
        self._compare = True
        self._busy = False

    # -----------------------------------------------------------------
    # STATE QML READS
    # -----------------------------------------------------------------
    @Property("QVariantList", constant=True)
    def tabs(self) -> list:
        return [
            {"key": spec["key"],
             "label": self._i18n.text(spec["title"], spec["text"]),
             "glyph": spec["glyph"]}
            for spec in REPORT_TABS
        ]

    @Property(str, notify=rowsChanged)
    def tab(self) -> str:
        return self._tab

    @Property("QVariantList", notify=rowsChanged)
    def cards(self) -> list:
        return self._cards

    @Property("QVariantList", notify=rowsChanged)
    def charts(self) -> list:
        return self._charts

    @Property("QVariantList", notify=rowsChanged)
    def tables(self) -> list:
        return self._tables

    @Property(str, notify=rowsChanged)
    def note(self) -> str:
        return self._note

    @Property(bool, notify=busyChanged)
    def busy(self) -> bool:
        return self._busy

    # -----------------------------------------------------------------
    # LOAD
    # -----------------------------------------------------------------
    @Slot(str, str, str, bool)
    def load(self, tab: str, since: str, until: str, compare: bool) -> None:
        if tab not in reportsql.QUERIES:
            return
        database = self._database()
        if database is None:
            return

        self._tab = tab
        self._compare = bool(compare)
        self._set_busy(True)
        try:
            data = reportsql.QUERIES[tab](database, since, until)
            builder = getattr(self, f"_build_{tab}")
            cards, charts, tables = builder(data, since, until)
            self._cards = cards
            self._charts = charts
            self._tables = tables
            self._raw = {table["id"]: table.pop("_raw") for table in tables}
            self._note = self._note_for(tab)
            self._apply_sorts()
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            self._cards = []
            self._charts = []
            self._tables = []
            self._raw = {}
            self._note = ""
        finally:
            self._set_busy(False)
        self.rowsChanged.emit()

    def _note_for(self, tab: str) -> str:
        """The one thing a tab has to admit before its numbers are trusted.

        Profit here is `qty * Product.purchase_price` — the price a product costs
        TODAY, because `SaleItem` stores no cost. Change a purchase price and every
        past sale of that product changes with it. Two tabs report profit, and both
        say so rather than leaving a reader to discover it from a discrepancy.
        """
        if tab in ("pnl", "inventory") and reportsql.COST_IS_CURRENT:
            return self._i18n.text(
                "reports.note.current_cost",
                "Cost and profit use each product's current purchase price — "
                "the sale line does not store what it cost at the time.")
        return ""

    # -----------------------------------------------------------------
    # SORTING
    # -----------------------------------------------------------------
    @Slot(str, int)
    def sortTable(self, table_id: str, column: int) -> None:
        """Same column again reverses it; a new column starts ascending.

        Sorted on the RAW rows. `_format_rows` runs again afterwards, so the strings
        the table draws are rebuilt from numbers that were compared as numbers.
        """
        table = self._table(table_id)
        if table is None or column < 0 or column >= len(table["columns"]):
            return
        current, descending = self._sort.get(table_id, (-1, False))
        self._sort[table_id] = (column, not descending if current == column else False)
        self._apply_sorts()
        self.rowsChanged.emit()

    def _apply_sorts(self) -> None:
        for table in self._tables:
            column, descending = self._sort.get(table["id"], (-1, False))
            rows = self._raw.get(table["id"], [])
            if 0 <= column < len(table["columns"]):
                key = table["columns"][column]["key"]
                rows = sorted(rows, key=lambda row: rv.sort_key(row.get(key)),
                              reverse=descending)
            table["sortColumn"] = column
            table["sortDescending"] = descending
            table["rows"] = [self._format_row(row, table["columns"]) for row in rows]

    # -----------------------------------------------------------------
    # EXPORT
    # -----------------------------------------------------------------
    @Slot(str, str)
    def exportCsv(self, table_id: str, folder: str) -> None:
        """One table, as it is currently sorted and filtered, to a CSV.

        TRANSLATED HEADERS, RAW NUMBERS

        The header row is what the screen shows, so the file can be read by whoever
        asked for it. The values are the raw floats, not `fmt.money` output — a
        spreadsheet needs to add them up, and "1,234.50" is text to every one of
        them. That is the opposite trade from pos, whose exporter wrote the formatted
        display strings under raw SQL column names.

        `utf-8-sig` because Excel reads a BOM-less UTF-8 file as the local codepage
        and turns every Arabic product name into mojibake. It is the house rule
        already — every reader and writer in both trees uses it.
        """
        table = self._table(table_id)
        if table is None:
            return
        rows = self._raw.get(table_id, [])
        if not rows:
            self.rejected.emit(self._i18n.text("reports.export.empty",
                                              "Nothing to export."))
            return

        column, descending = self._sort.get(table_id, (-1, False))
        if 0 <= column < len(table["columns"]):
            key = table["columns"][column]["key"]
            rows = sorted(rows, key=lambda row: rv.sort_key(row.get(key)),
                          reverse=descending)

        try:
            target = Path(self._folder(folder)) / f"{self._tab}-{table_id}.csv"
            with open(target, "w", newline="", encoding="utf-8-sig") as handle:
                writer = csv.writer(handle)
                writer.writerow([col["header"] for col in table["columns"]])
                for row in rows:
                    writer.writerow([
                        rv.csv_value(row.get(col["key"]), col.get("kind", "text"))
                        for col in table["columns"]
                    ])
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.exported.emit(str(target), len(rows))

    @staticmethod
    def _folder(folder: str) -> Path:
        """Where a typed folder resolves to, and where an empty one goes.

        Same rule as `Catalogue.exportProducts`: the application's own data folder,
        which is the one place the process is certain it may write.
        """
        text = (folder or "").strip()
        if text:
            candidate = Path(text)
            if candidate.is_dir():
                return candidate
        try:
            return Path(legacy.database().DATA_DIR)
        except Exception:  # noqa: BLE001
            return Path.home()

    def _table(self, table_id: str) -> dict | None:
        for table in self._tables:
            if table["id"] == table_id:
                return table
        return None

    def _format_row(self, row: dict, columns: list[dict]) -> dict:
        return {
            column["key"]: rv.display(row.get(column["key"]),
                                      column.get("kind", "text"))
            for column in columns
        }

    def _range_label(self, since: str, until: str) -> str:
        return f"{since} \u2192 {until}"

    # -----------------------------------------------------------------
    # 1. SALES
    # -----------------------------------------------------------------
    def _build_sales(self, data: dict, since: str, until: str):
        i18n = self._i18n
        kpi, prev = data["kpi"], data["prev"]
        compare = self._compare

        cards = [
            rv.card(i18n, "reports.sales.net_sales", "Sales", kpi["total"],
                    tone="primary", glyph="ic_fluent_receipt_money_20_regular",
                    previous=prev["total"], compare=compare),
            rv.card(i18n, "reports.sales.invoices", "Invoices", kpi["count"],
                    kind="count", tone="info",
                    glyph="ic_fluent_receipt_20_regular",
                    previous=prev["count"], compare=compare),
            rv.card(i18n, "reports.sales.avg_basket", "Avg. basket",
                    kpi["avg_basket"], tone="info",
                    glyph="ic_fluent_cart_20_regular",
                    previous=prev["avg_basket"], compare=compare),
            rv.card(i18n, "sales.col.paid", "Paid", kpi["paid"], tone="success",
                    glyph="ic_fluent_money_20_regular",
                    previous=prev["paid"], compare=compare),
            rv.card(i18n, "reports.sales.outstanding", "Outstanding",
                    kpi["outstanding"], tone="warning",
                    glyph="ic_fluent_wallet_20_regular",
                    previous=prev["outstanding"], higher_is_better=False,
                    compare=compare),
            rv.card(i18n, "reports.sales.discount", "Discount given",
                    kpi["discount"], tone="warning",
                    glyph="ic_fluent_tag_20_regular", higher_is_better=False),
            rv.card(i18n, "reports.sales.items_sold", "Items sold", kpi["items"],
                    kind="qty", tone="info",
                    glyph="ic_fluent_box_multiple_20_regular"),
            rv.card(i18n, "reports.sales.returns", "Returns", kpi["returns"],
                    tone="danger", glyph="ic_fluent_arrow_undo_20_regular",
                    higher_is_better=False),
        ]

        lanes = [rv.lane(i18n, "reports.period.current", "This period",
                         data["trend"], "indigo")]
        if compare:
            lanes.append(rv.lane(i18n, "reports.period.previous", "Previous",
                                 data["prev_trend"], "slate", muted=True))

        charts = [
            rv.line_chart(i18n, "trend", "reports.sales.trend", "Sales trend",
                          lanes, self._range_label(since, until)),
            rv.donut_chart(
                i18n, "mix", "reports.sales.payment_mix", "Payment methods",
                [{"label": i18n.text(f"pay.type.{s['key']}", s["key"]),
                  "value": s["value"], "tone": PAY_TONES.get(s["key"], "")}
                 for s in data["payment_mix"]]),
            rv.bars_chart(i18n, "top", "reports.sales.top_revenue",
                          "Top products by revenue", data["top_value"], "indigo"),
            rv.bars_chart(i18n, "cats", "reports.inv.category_sales",
                          "Sales by category", data["by_category"], "teal"),
            # The two "when" charts. Peak hours are the finding a shop acts on —
            # staffing, deliveries — and neither exists in pos's data layer.
            rv.line_chart(i18n, "hours", "reports.sales.by_hour",
                          "Sales by hour of day",
                          [rv.lane(i18n, "", i18n.text("reports.sales.net_sales",
                                                       "Sales"),
                                   data["by_hour"], "violet")],
                          area=True),
            rv.bars_chart(
                i18n, "dow", "reports.sales.by_dow", "Sales by day of week",
                [{"label": i18n.text(DOW_KEYS[int(p["key"])][0],
                                     DOW_KEYS[int(p["key"])][1]),
                  "value": p["value"]} for p in data["by_dow"]],
                "amber", limit=7),
        ]

        tables = [
            rv.table(i18n, "invoices", "reports.tab.sales", "Invoices", [
                rv.col(i18n, "number", "reports.col.number", "Number", ltr=True,
                       width=150),
                rv.col(i18n, "created_at", "reports.col.created_at", "Date",
                       kind="datetime", ltr=True, width=190),
                rv.col(i18n, "customer", "reports.col.customer", "Customer",
                       stretch=True),
                rv.col(i18n, "payment_type", "reports.col.payment_type", "Payment",
                       width=140),
                rv.col(i18n, "total", "reports.summary.total", "Total",
                       kind="money"),
                rv.col(i18n, "paid", "sales.col.paid", "Paid", kind="money"),
                rv.col(i18n, "remaining", "reports.col.remaining", "Remaining",
                       kind="money"),
            ], data["invoices"]),
            rv.table(i18n, "returns", "reports.returns", "Returns", [
                rv.col(i18n, "number", "reports.col.number", "Number", ltr=True,
                       width=150),
                rv.col(i18n, "created_at", "reports.col.created_at", "Date",
                       kind="datetime", ltr=True, width=190),
                rv.col(i18n, "sale_number", "reports.col.sale", "Sale", ltr=True,
                       width=150),
                rv.col(i18n, "reason", "reports.col.reason", "Reason",
                       stretch=True),
                rv.col(i18n, "total", "reports.summary.total", "Total",
                       kind="money"),
            ], data["returns"]),
            # created_by is a name string, not a foreign key — see reportsql.
            rv.table(i18n, "staff", "reports.by_staff", "By employee", [
                rv.col(i18n, "label", "employees.title", "Employee", stretch=True),
                rv.col(i18n, "count", "reports.sales.invoices", "Invoices",
                       kind="count"),
                rv.col(i18n, "value", "reports.summary.total", "Total",
                       kind="money"),
            ], data["by_staff"]),
        ]
        return cards, charts, tables

    # -----------------------------------------------------------------
    # 2. INVENTORY
    # -----------------------------------------------------------------
    def _build_inventory(self, data: dict, since: str, until: str):
        i18n = self._i18n
        kpi = data["kpi"]

        cards = [
            rv.card(i18n, "reports.inv.value", "Stock value at cost",
                    kpi["value_cost"], tone="primary",
                    glyph="ic_fluent_box_multiple_20_regular"),
            rv.card(i18n, "reports.inv.value_retail", "Stock value at retail",
                    kpi["value_retail"], tone="info",
                    glyph="ic_fluent_tag_20_regular"),
            rv.card(i18n, "reports.inv.active", "Products", kpi["count"],
                    kind="count", tone="info",
                    glyph="ic_fluent_receipt_20_regular"),
            rv.card(i18n, "reports.inv.low_stock", "Low on stock",
                    kpi["low_stock"], kind="count", tone="warning",
                    glyph="ic_fluent_alert_20_regular"),
            rv.card(i18n, "reports.inv.stagnant", "Not sold in this period",
                    kpi["stagnant"], kind="count", tone="danger",
                    glyph="ic_fluent_warning_20_regular"),
        ]

        charts = [
            # Stock VALUE by category — a closed set of categories, so a ring is
            # honest here where a top-N ranking of products would not be.
            rv.donut_chart(i18n, "stockcat", "reports.inv.stock_by_category",
                           "Stock value by category", data["stock_by_category"]),
            rv.bars_chart(i18n, "lowest", "reports.inv.low_stock", "Low on stock",
                          data["low_rows"], "amber", field="stock", label="name"),
            rv.bars_chart(i18n, "thinnest", "reports.inv.thin_margin",
                          "Thinnest margins", data["margin_rows"], "crimson",
                          field="margin_pct", label="name"),
        ]

        stock_cols = [
            rv.col(i18n, "name", "product.name", "Product", stretch=True),
            rv.col(i18n, "barcode", "product.barcode", "Barcode", ltr=True,
                   width=170),
            rv.col(i18n, "category", "product.category", "Category", width=170),
            rv.col(i18n, "stock", "product.stock", "Stock", kind="qty"),
            rv.col(i18n, "purchase_price", "product.purchase_price", "Cost",
                   kind="money"),
            rv.col(i18n, "value", "reports.inv.value", "Value", kind="money"),
        ]
        tables = [
            rv.table(i18n, "stock", "reports.tab.inventory", "Stock",
                     stock_cols, data["stock_rows"]),
            rv.table(i18n, "low", "reports.inv.low_stock", "Low on stock", [
                rv.col(i18n, "name", "product.name", "Product", stretch=True),
                rv.col(i18n, "category", "product.category", "Category",
                       width=170),
                rv.col(i18n, "stock", "product.stock", "Stock", kind="qty"),
                rv.col(i18n, "threshold", "product.low_stock_threshold",
                       "Threshold", kind="qty"),
                rv.col(i18n, "value", "reports.inv.value", "Value", kind="money"),
            ], data["low_rows"]),
            rv.table(i18n, "stagnant", "reports.inv.stagnant",
                     "Not sold in this period", [
                rv.col(i18n, "name", "product.name", "Product", stretch=True),
                rv.col(i18n, "category", "product.category", "Category",
                       width=170),
                rv.col(i18n, "stock", "product.stock", "Stock", kind="qty"),
                rv.col(i18n, "value", "reports.inv.value", "Value", kind="money"),
            ], data["stagnant_rows"]),
            rv.table(i18n, "margin", "reports.inv.margin", "Margin per product", [
                rv.col(i18n, "name", "product.name", "Product", stretch=True),
                rv.col(i18n, "purchase_price", "product.purchase_price", "Cost",
                       kind="money"),
                rv.col(i18n, "sale_price", "product.sale_price", "Price",
                       kind="money"),
                rv.col(i18n, "margin", "reports.inv.margin", "Margin",
                       kind="money"),
                rv.col(i18n, "margin_pct", "reports.profit.avg_margin", "Margin %",
                       kind="percent"),
            ], data["margin_rows"]),
        ]
        return cards, charts, tables

    # -----------------------------------------------------------------
    # 3. PURCHASES AND SUPPLIERS
    # -----------------------------------------------------------------
    def _build_purchases(self, data: dict, since: str, until: str):
        i18n = self._i18n
        kpi, prev = data["kpi"], data["prev"]
        compare = self._compare

        cards = [
            rv.card(i18n, "reports.summary.total", "Purchases", kpi["total"],
                    tone="primary",
                    glyph="ic_fluent_vehicle_truck_profile_20_regular",
                    previous=prev["total"], higher_is_better=False,
                    compare=compare),
            rv.card(i18n, "purchases.card.count", "Invoices", kpi["count"],
                    kind="count", tone="info",
                    glyph="ic_fluent_receipt_20_regular",
                    previous=prev["count"], compare=compare),
            rv.card(i18n, "purchases.col.paid", "Paid", kpi["paid"],
                    tone="success", glyph="ic_fluent_money_20_regular",
                    previous=prev["paid"], compare=compare),
            rv.card(i18n, "reports.purchases.outstanding", "Unpaid",
                    kpi["outstanding"], tone="warning",
                    glyph="ic_fluent_wallet_20_regular",
                    previous=prev["outstanding"], higher_is_better=False,
                    compare=compare),
            rv.card(i18n, "reports.debt.supplier_payments", "Paid to suppliers",
                    kpi["settled"], tone="info",
                    glyph="ic_fluent_arrow_upload_20_regular"),
        ]

        lanes = [rv.lane(i18n, "reports.period.current", "This period",
                         data["trend"], "amber")]
        if compare:
            lanes.append(rv.lane(i18n, "reports.period.previous", "Previous",
                                 data["prev_trend"], "slate", muted=True))

        charts = [
            rv.line_chart(i18n, "trend", "reports.purchases.by_day",
                          "Purchases over time", lanes,
                          self._range_label(since, until)),
            rv.bars_chart(i18n, "suppliers", "reports.purchases.by_supplier",
                          "Top suppliers", data["by_supplier"], "amber"),
            rv.bars_chart(i18n, "owed", "reports.debt.supplier_balances",
                          "Largest supplier balances", data["debts"], "crimson",
                          field="debt", label="name"),
        ]

        tables = [
            rv.table(i18n, "invoices", "reports.tab.purchases", "Invoices", [
                rv.col(i18n, "number", "reports.col.number", "Number", ltr=True,
                       width=150),
                rv.col(i18n, "created_at", "reports.col.created_at", "Date",
                       kind="datetime", ltr=True, width=190),
                rv.col(i18n, "supplier", "reports.purch.suppliers", "Supplier",
                       stretch=True),
                rv.col(i18n, "total", "reports.summary.total", "Total",
                       kind="money"),
                rv.col(i18n, "paid", "purchases.col.paid", "Paid", kind="money"),
                rv.col(i18n, "remaining", "reports.col.remaining", "Remaining",
                       kind="money"),
            ], data["invoices"]),
            rv.table(i18n, "debts", "reports.debt.supplier_payables",
                     "Supplier balances", [
                rv.col(i18n, "name", "reports.purch.suppliers", "Supplier",
                       stretch=True),
                rv.col(i18n, "phone", "party.phone", "Phone", ltr=True,
                       width=170),
                rv.col(i18n, "debt", "reports.debt.supplier_payables", "Owed",
                       kind="money"),
            ], data["debts"]),
            rv.table(i18n, "payments", "reports.debt.supplier_payments",
                     "Payments to suppliers", [
                rv.col(i18n, "created_at", "reports.col.created_at", "Date",
                       kind="datetime", ltr=True, width=190),
                rv.col(i18n, "supplier", "reports.purch.suppliers", "Supplier",
                       stretch=True),
                rv.col(i18n, "amount", "reports.col.amount", "Amount",
                       kind="money"),
            ], data["payments"]),
        ]
        return cards, charts, tables

    # -----------------------------------------------------------------
    # 4. CUSTOMERS
    # -----------------------------------------------------------------
    def _build_customers(self, data: dict, since: str, until: str):
        i18n = self._i18n
        kpi, prev = data["kpi"], data["prev"]
        compare = self._compare

        cards = [
            rv.card(i18n, "reports.debt.customer", "Customer debt", kpi["debt"],
                    tone="danger", glyph="ic_fluent_people_team_20_regular",
                    higher_is_better=False),
            rv.card(i18n, "customers.card.count", "Debtors", kpi["debtors"],
                    kind="count", tone="info",
                    glyph="ic_fluent_people_20_regular"),
            rv.card(i18n, "reports.debt.new_debt", "New debt", kpi["issued"],
                    tone="warning", glyph="ic_fluent_arrow_upload_20_regular",
                    previous=prev["issued"], higher_is_better=False,
                    compare=compare),
            rv.card(i18n, "reports.debt.collected", "Collected", kpi["collected"],
                    tone="success", glyph="ic_fluent_arrow_download_20_regular",
                    previous=prev["collected"], compare=compare),
        ]

        charts = [
            # Two lanes, both current: what the shop lent against what it got back.
            # A comparison with the previous period would be a third line on a chart
            # whose point is the gap between these two.
            rv.line_chart(i18n, "flow", "reports.debt.trend",
                          "Debt issued vs collected", [
                rv.lane(i18n, "reports.debt.new_debt", "New debt", data["trend"],
                        "crimson", field="issued"),
                rv.lane(i18n, "reports.debt.collected", "Collected",
                        data["trend"], "emerald", field="collected"),
            ], self._range_label(since, until), area=False),
            rv.bars_chart(i18n, "top", "reports.customers.top",
                          "Top customers by purchases", data["top_customers"],
                          "rose"),
            rv.bars_chart(i18n, "owed", "reports.debt.largest_debtors",
                          "Largest debts", data["debtors"], "crimson",
                          field="debt", label="name"),
        ]

        tables = [
            rv.table(i18n, "debtors", "reports.debt.largest_debtors",
                     "Customer debts", [
                rv.col(i18n, "name", "customers.title", "Customer", stretch=True),
                rv.col(i18n, "phone", "party.phone", "Phone", ltr=True,
                       width=170),
                rv.col(i18n, "last_payment", "reports.col.last_payment",
                       "Last payment", ltr=True, width=170),
                rv.col(i18n, "debt", "reports.debt.customer", "Debt",
                       kind="money"),
            ], data["debtors"]),
            rv.table(i18n, "top", "reports.customers.top", "Top customers", [
                rv.col(i18n, "label", "customers.title", "Customer",
                       stretch=True),
                rv.col(i18n, "count", "reports.sales.invoices", "Invoices",
                       kind="count"),
                rv.col(i18n, "value", "reports.summary.total", "Total",
                       kind="money"),
            ], data["top_customers"]),
            rv.table(i18n, "payments", "reports.debt.collected", "Collections", [
                rv.col(i18n, "created_at", "reports.col.created_at", "Date",
                       kind="datetime", ltr=True, width=190),
                rv.col(i18n, "customer", "customers.title", "Customer",
                       stretch=True),
                rv.col(i18n, "amount", "reports.col.amount", "Amount",
                       kind="money"),
            ], data["payments"]),
        ]
        return cards, charts, tables

    # -----------------------------------------------------------------
    # 5. CASH AND TREASURY
    # -----------------------------------------------------------------
    def _build_cash(self, data: dict, since: str, until: str):
        i18n = self._i18n
        kpi = data["kpi"]

        cards = [
            rv.card(i18n, "reports.cash.net", "Net cash", kpi["net"],
                    kind="signed", tone="primary",
                    glyph="ic_fluent_coin_multiple_20_regular"),
            rv.card(i18n, "reports.cash.in", "Cash in", kpi["cash_in"],
                    tone="success", glyph="ic_fluent_arrow_download_20_regular"),
            rv.card(i18n, "reports.cash.out", "Cash out", kpi["cash_out"],
                    tone="danger", glyph="ic_fluent_arrow_upload_20_regular",
                    higher_is_better=False),
            rv.card(i18n, "reports.cash.expenses", "Expenses", kpi["expenses"],
                    tone="warning", glyph="ic_fluent_money_hand_20_regular",
                    higher_is_better=False),
            rv.card(i18n, "reports.cash.movements", "Movements",
                    kpi["movements"], kind="count", tone="info",
                    glyph="ic_fluent_arrow_swap_20_regular"),
        ]

        charts = [
            rv.line_chart(i18n, "flow", "reports.cash.net", "Daily cash flow", [
                rv.lane(i18n, "reports.cash.in", "In", data["trend"], "emerald",
                        field="in"),
                rv.lane(i18n, "reports.cash.out", "Out", data["trend"], "crimson",
                        field="out"),
                rv.lane(i18n, "reports.cash.net", "Net", data["trend"], "indigo",
                        field="net"),
            ], self._range_label(since, until), area=False),
            # The four movement types are a closed set — `add_cash_movement`
            # validates against exactly cash_in / expense / cash_out, and
            # finalize_sale writes the fourth — so a ring is the truth here.
            rv.donut_chart(
                i18n, "types", "reports.cash.by_type", "Movements by type",
                [{"label": i18n.text(f"cash.type.{s['key']}", s["key"]),
                  "value": s["value"],
                  "tone": ("success" if s["key"] in ("sale", "cash_in")
                           else "warning" if s["key"] == "expense" else "danger")}
                 for s in data["by_type"]]),
            rv.bars_chart(i18n, "reasons", "reports.cash.expense_descriptions",
                          "Expenses by reason", data["by_reason"], "crimson"),
        ]

        tables = [
            rv.table(i18n, "sessions", "reports.cash.sessions", "Drawer sessions", [
                rv.col(i18n, "opened_at", "reports.cash.opened", "Opened",
                       kind="datetime", ltr=True, width=190),
                rv.col(i18n, "closed_at", "reports.cash.closed", "Closed",
                       kind="datetime", ltr=True, width=190),
                rv.col(i18n, "opening", "reports.cash.opening", "Opening",
                       kind="money"),
                rv.col(i18n, "cash_in", "reports.cash.in", "In", kind="money"),
                rv.col(i18n, "cash_out", "reports.cash.out", "Out", kind="money"),
                rv.col(i18n, "expected", "reports.cash.expected", "Expected",
                       kind="money"),
                rv.col(i18n, "actual", "reports.cash.actual", "Counted",
                       kind="money"),
                # Neither stored nor derivable from one row: `expected` is computed
                # from the session's movements, and the variance from that.
                rv.col(i18n, "difference", "reports.cash.difference", "Difference",
                       kind="signed"),
            ], data["sessions"]),
            rv.table(i18n, "movements", "reports.cash.movements", "Movements", [
                rv.col(i18n, "created_at", "reports.col.created_at", "Date",
                       kind="datetime", ltr=True, width=190),
                rv.col(i18n, "type", "reports.col.type", "Type", width=150),
                rv.col(i18n, "reason", "reports.col.reason", "Reason",
                       stretch=True),
                rv.col(i18n, "amount", "reports.col.amount", "Amount",
                       kind="money"),
            ], data["movements"]),
        ]
        return cards, charts, tables

    # -----------------------------------------------------------------
    # 6. PROFIT AND LOSS
    # -----------------------------------------------------------------
    def _build_pnl(self, data: dict, since: str, until: str):
        i18n = self._i18n
        kpi, prev = data["kpi"], data["prev"]
        compare = self._compare

        cards = [
            rv.card(i18n, "reports.profit.revenue", "Revenue", kpi["revenue"],
                    tone="info", glyph="ic_fluent_arrow_trending_lines_20_regular",
                    previous=prev["revenue"], compare=compare),
            rv.card(i18n, "reports.profit.cogs", "Cost of goods", kpi["cost"],
                    tone="warning", glyph="ic_fluent_box_multiple_20_regular",
                    previous=prev["cost"], higher_is_better=False,
                    compare=compare),
            rv.card(i18n, "reports.profit.gross", "Gross profit", kpi["gross"],
                    kind="signed", tone="success",
                    glyph="ic_fluent_money_20_regular",
                    previous=prev["gross"], compare=compare),
            rv.card(i18n, "reports.cash.expenses", "Expenses", kpi["expenses"],
                    tone="danger", glyph="ic_fluent_money_hand_20_regular",
                    previous=prev["expenses"], higher_is_better=False,
                    compare=compare),
            # Gross profit less expenses. pos never subtracted them anywhere, so its
            # "profit" is margin; this is what is actually left.
            rv.card(i18n, "reports.profit.net", "Net profit", kpi["net"],
                    kind="signed", tone="primary",
                    glyph="ic_fluent_coin_multiple_20_regular",
                    previous=prev["net"], compare=compare),
            rv.card(i18n, "reports.profit.avg_margin", "Margin", kpi["margin"],
                    kind="percent", tone="info",
                    glyph="ic_fluent_data_pie_20_regular",
                    previous=prev["margin"], compare=compare),
        ]

        charts = [
            rv.line_chart(i18n, "pnl", "reports.profit.over_time",
                          "Revenue, cost and profit", [
                rv.lane(i18n, "reports.profit.revenue", "Revenue", data["trend"],
                        "indigo", field="revenue"),
                rv.lane(i18n, "reports.profit.cogs", "Cost", data["trend"],
                        "amber", field="cost"),
                rv.lane(i18n, "reports.profit.net", "Net profit", data["trend"],
                        "emerald", field="net"),
            ], self._range_label(since, until), area=False),
            rv.bars_chart(i18n, "cats", "reports.profit.by_category",
                          "Profit by category", data["by_category"], "violet",
                          field="profit", label="name"),
            rv.bars_chart(i18n, "prods", "reports.profit.by_product",
                          "Profit by product", data["top_profit"], "emerald",
                          field="profit", label="name"),
        ]

        pnl_cols = [
            rv.col(i18n, "name", "product.category", "Category", stretch=True),
            rv.col(i18n, "qty", "reports.sales.items_sold", "Qty", kind="qty"),
            rv.col(i18n, "revenue", "reports.profit.revenue", "Revenue",
                   kind="money"),
            rv.col(i18n, "cost", "reports.profit.cogs", "Cost", kind="money"),
            rv.col(i18n, "profit", "reports.profit.net_profit", "Profit",
                   kind="signed"),
            rv.col(i18n, "margin", "reports.profit.avg_margin", "Margin",
                   kind="percent"),
        ]
        product_cols = list(pnl_cols)
        product_cols[0] = rv.col(i18n, "name", "product.name", "Product",
                                 stretch=True)

        tables = [
            rv.table(i18n, "cats", "reports.profit.by_category",
                     "Profit by category", pnl_cols, data["by_category"]),
            rv.table(i18n, "prods", "reports.profit.by_product",
                     "Profit by product", product_cols, data["by_product"]),
        ]
        return cards, charts, tables

    # -----------------------------------------------------------------
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




"""Language and strings, as QML's Strings singleton expects them.

Strings.qml reads three things — `strings`, `language`, `isRtl` — and calls
`setLanguage`. That is the whole contract; everything else about translation
lives on the QML side, where `t()` reads the map inside a binding and so
re-evaluates every label on a language change without a single signal handler.

WHY THE WHOLE MAP AND NOT A tr() SLOT

A slot would mean one Python round trip per visible string, on every language
change, for a UI with a few hundred labels on screen. Handing over a flat
{key: text} map for the active language is one conversion, after which QML
indexes a JavaScript object. The map is rebuilt only when the language changes.

WHAT THIS DOES NOT DO

It does not touch QGuiApplication.setLayoutDirection, which is what pos's
LanguageManager does for its widgets. Qt Quick mirrors through LayoutMirroring
instead, and Main.qml already drives that from `Strings.rtl` — the QML-native
mechanism, applied at one place in the tree, rather than a global that would
then have to agree with it.
"""

from __future__ import annotations

from PySide6.QtCore import Property, QObject, Signal, Slot

from . import legacy

#: Strings this front end needs and pos's catalogue has never heard of.
#:
#: `text()` and QML's `Strings.t()` both take an English fallback, so a missing key
#: is legible rather than broken — but only in English. That is fine for a label
#: nobody reads twice and wrong for one in a dropdown whose other five entries are
#: in Arabic. Anything that has to be translated and is not in pos's table goes
#: here, in the same {key: {en, fr, ar}} shape, and is merged OVER the borrowed
#: catalogue so pos stays the authority for every key it does define.
#:
#: Deliberately short. This is not a second catalogue; it is the overflow for
#: strings pos never had a screen for.
EXTRA: dict[str, dict[str, str]] = {
    # The period presets. pos has today / yesterday / last7 / last30 / month /
    # prev_month / custom (i18n.py:1534-1540) and "All time" (:238); a year is the
    # one span its own screens never offered.
    "reports.preset.last365": {
        "en": "Last year",
        "fr": "Derniers 12 mois",
        "ar": "آخر سنة",
    },
    "dashboard.description": {
        "en": "The shop, at a glance.",
        "fr": "Le magasin, en un coup d'œil.",
        "ar": "المتجر في لمحة.",
    },
    # Two counted lines the dashboard prints under a figure. Both take {count},
    # which is why neither can borrow a pos key: `dashboard.low_stock` exists over
    # there as the plain label "Low Stock Items", so the page was printing that
    # instead of "61 low on stock" — a template with no placeholder in it formats
    # to itself.
    "dashboard.sales_count": {
        "en": "{count} sales",
        "fr": "{count} ventes",
        "ar": "{count} عملية بيع",
    },
    "dashboard.low_stock_count": {
        "en": "{count} low on stock",
        "fr": "{count} en stock bas",
        "ar": "{count} بمخزون منخفض",
    },
    # The arrange screen lists products the till does not show, because that is the
    # screen where you would want to notice.
    "products.hidden_on_pos": {
        "en": "Hidden on the till",
        "fr": "Masqué sur la caisse",
        "ar": "مخفي في نقطة البيع",
    },
    # The till's product picker. pos has "selector.open_picker" — "Open product
    # picker" — which reads as an instruction and belongs on the button that opens
    # it, not across the top of the thing it opened.
    "product_select.title": {
        "en": "Find a product",
        "fr": "Trouver un produit",
        "ar": "ابحث عن منتج",
    },
    # Both ways of reordering, in one line.
    "products.arrange.hint2": {
        "en": "Tap a tile, then tap another to swap them — or drag one onto another. The till shows them exactly like this.",
        "fr": "Touchez une tuile, puis une autre pour les échanger — ou faites glisser l'une sur l'autre. La caisse les affiche exactement ainsi.",
        "ar": "اضغط على مربّع ثم على آخر لتبديلهما — أو اسحب أحدهما فوق الآخر. نقطة البيع تعرضهما بهذا الترتيب نفسه.",
    },
    # The pager, rebuilt as one contained strip. Three keys pos cannot supply as
    # written: its `pagination.showing` opens with the word "Showing", which the new
    # bar drops because the numbers are on their own line and the word was carrying
    # nothing; and its `pagination.per_page` is the label "Items per page", which the
    # new combo no longer needs because the unit is inside the value.
    "pagination.showing": {
        "en": "{from}–{to} of {total}",
        "fr": "{from}–{to} sur {total}",
        "ar": "{from}–{to} من {total}",
    },
    "pagination.page_of": {
        "en": "Page {page} of {pages}",
        "fr": "Page {page} sur {pages}",
        "ar": "صفحة {page} من {pages}",
    },
    "pagination.per_page": {
        "en": "{n} / page",
        "fr": "{n} / page",
        "ar": "{n} / صفحة",
    },
    # Selling below stock is allowed — `finalize_sale` lets the count go negative on
    # purpose — so the till reports it instead of refusing it.
    "pos.tile.oversold": {
        "en": "sold below stock — the count is now negative",
        "fr": "vendu sous le stock — le compte est maintenant négatif",
        "ar": "بيع تحت المخزون — العدد صار سالباً",
    },
    # The one caveat the two profit tabs have to say out loud. `SaleItem` stores no
    # cost, so every past sale is costed at the product's price today.
    "reports.note.current_cost": {
        "en": "Cost and profit use each product's current purchase price — "
              "the sale line does not store what it cost at the time.",
        "fr": "Le coût et le bénéfice utilisent le prix d'achat actuel de chaque "
              "produit — la ligne de vente n'enregistre pas son coût d'alors.",
        "ar": "التكلفة والربح يستخدمان سعر الشراء الحالي لكل منتج — "
              "سطر البيع لا يحفظ تكلفته وقت البيع.",
    },
}


class I18n(QObject):
    languageChanged = Signal()

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)

        try:
            self._table = legacy.catalogue()
            self._languages, self._rtl = legacy.languages()
        except ImportError as exc:
            # Reported, not swallowed: QML falls back to the English text passed
            # to every t() call, so the UI stays legible and this says why.
            print(f"bridge: no string catalogue ({exc})")
            self._table = {}
            self._languages, self._rtl = ("en",), ()

        self._language = "en"
        self._flat = self._build(self._language)

    # -- what QML reads ---------------------------------------------------
    @Property("QVariantMap", notify=languageChanged)
    def strings(self) -> dict:
        return self._flat

    @Property(str, notify=languageChanged)
    def language(self) -> str:
        return self._language

    @Property(bool, notify=languageChanged)
    def isRtl(self) -> bool:
        return self._language in self._rtl

    @Property("QVariantList", constant=True)
    def availableLanguages(self) -> list:
        """For a selector that should not hardcode the list. LoginPage still
        hardcodes ["en", "fr", "ar"] to match its own Segmented labels; this is
        here so the next one does not have to."""
        return list(self._languages)

    # -- what QML calls ---------------------------------------------------
    @Slot(str)
    def setLanguage(self, code: str) -> None:
        if code not in self._languages or code == self._language:
            return
        self._language = code
        self._flat = self._build(code)

        # Keep pos's own manager in step. Nothing in QML reads it, but every
        # borrowed function that calls tr() does — fmt_money's currency suffix
        # most visibly — and a French screen with an English currency is exactly
        # the kind of split a single catalogue was supposed to prevent.
        try:
            legacy.language_manager().set_language(code)
        except Exception as exc:  # noqa: BLE001
            print(f"bridge: could not set the legacy language ({exc})")

        self.languageChanged.emit()

    # -- what the rest of the bridge calls --------------------------------
    def text(self, key: str, fallback: str = "", **values: object) -> str:
        """The same lookup QML's Strings.t() performs, for strings Python builds.

        The controllers need a handful of translated fragments — a currency
        suffix, a free-line label, "Invoice #3" — and they read them from this
        map rather than through pos's tr(), so that the language QML is showing
        and the language Python is formatting in cannot drift apart.

        `fallback` is what QML's t() has always taken as its second argument and
        this did not: a key pos's catalogue has never heard of used to render as
        itself, which is how "settings.barcode.label_height" ended up on screen as
        a label. English text is a poor translation; a key is not a label at all.
        """
        text = self._flat.get(key) or fallback or key
        return text.format(**values) if values else text

    # -- internals --------------------------------------------------------
    def _build(self, code: str) -> dict:
        """Flatten the catalogue for one language.

        English is the fallback per key, not per catalogue: a key that only pos's
        newest screens have translated should still read in English rather than
        showing its own name on a button.

        EXTRA is applied last, so this front end's own strings win for the keys it
        declares and pos keeps every key it defines.
        """
        out = {}
        for table in (self._table, EXTRA):
            for key, entry in table.items():
                text = entry.get(code) or entry.get("en")
                if text:
                    out[key] = text
        return out

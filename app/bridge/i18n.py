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

from .. import diagnostics
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
    # ASKING BEFORE THE SHELF GOES NEGATIVE
    #
    # pos only ever reported this afterwards, so its catalogue has the wording for the
    # report (`negstock.*`) and none for the question. Two titles rather than one: a
    # shelf at zero and a shelf that is merely short are different news, and only the
    # first one is usually a surprise. `negstock.mute` is pos's own "Do not show
    # again" and is reused as it is — the checkbox means the same thing here.
    "stock.short.out.title": {
        "en": "Out of stock",
        "fr": "Rupture de stock",
        "ar": "نفد المخزون",
    },
    "stock.short.title": {
        "en": "Not enough stock",
        "fr": "Stock insuffisant",
        "ar": "المخزون لا يكفي",
    },
    "stock.short.out.body": {
        "en": "{name} has nothing left on the shelf. It can still be sold — the "
              "count simply goes below zero.",
        "fr": "{name} n'a plus rien en rayon. La vente reste possible — le compte "
              "passe simplement sous zéro.",
        "ar": "{name} لم يبق منه شيء في الرفّ. البيع ما زال ممكناً — لكن العدد "
              "سينزل تحت الصفر.",
    },
    "stock.short.body": {
        "en": "{name} does not have enough on the shelf for this line. It can "
              "still be sold — the count simply goes below zero.",
        "fr": "{name} n'a pas assez de stock pour cette ligne. La vente reste "
              "possible — le compte passe simplement sous zéro.",
        "ar": "{name} لا يوجد منه ما يكفي هذا السطر. البيع ما زال ممكناً — لكن "
              "العدد سينزل تحت الصفر.",
    },
    "stock.short.wanted": {
        "en": "This line wants",
        "fr": "Cette ligne demande",
        "ar": "هذا السطر يطلب",
    },
    "stock.short.sell": {
        "en": "Sell it anyway",
        "fr": "Vendre quand même",
        "ar": "بِعْه على أي حال",
    },
    "stock.short.add": {
        "en": "Add stock",
        "fr": "Ajouter du stock",
        "ar": "إضافة كمية",
    },
    # The same switch, on the Settings screen — the way back for a shop that muted
    # the question from the dialog and then wanted it again.
    "settings.pos.warn_stock": {
        "en": "Ask before selling more than the shelf holds",
        "fr": "Demander avant de vendre plus que le stock",
        "ar": "السؤال قبل بيع أكثر من الموجود في المخزون",
    },
    # WHAT A LABEL CARRIES. pos's settings screen hardcodes these three labels in
    # its own widgets and its catalogue never named them, so both surfaces here —
    # the Settings group and the label sheet's contents row — were falling back to
    # English. One set of keys, two doors, one store.
    "settings.barcode.show_store": {
        "en": "Print the shop name",
        "fr": "Imprimer le nom du magasin",
        "ar": "طباعة اسم المتجر",
    },
    "settings.barcode.show_name": {
        "en": "Print the product name",
        "fr": "Imprimer le nom du produit",
        "ar": "طباعة اسم المنتج",
    },
    "settings.barcode.show_price": {
        "en": "Print the price",
        "fr": "Imprimer le prix",
        "ar": "طباعة السعر",
    },
    # The heading over those three switches on the label sheet, where the picture
    # re-renders on every flip.
    "barcode.contents": {
        "en": "On the label",
        "fr": "Sur l'étiquette",
        "ar": "على الملصق",
    },
    # The label sheet's settings popup: the gear beside the picture, the heading
    # inside it, and the size group it carries.
    "barcode.settings": {
        "en": "Label settings",
        "fr": "Paramètres de l'étiquette",
        "ar": "إعدادات الملصق",
    },
    "barcode.size": {
        "en": "Label size",
        "fr": "Dimensions",
        "ar": "مقاس الملصق",
    },
    "barcode.width": {
        "en": "Width",
        "fr": "Largeur",
        "ar": "العرض",
    },
    "barcode.height": {
        "en": "Height",
        "fr": "Hauteur",
        "ar": "الارتفاع",
    },
    # The picture's heading on the label sheet — and, one row up, the tooltip on
    # the + that puts a product on the sheet.
    "barcode.preview": {
        "en": "Preview",
        "fr": "Aperçu",
        "ar": "معاينة",
    },
    "barcode.enqueue": {
        "en": "Queue one label",
        "fr": "Mettre en file",
        "ar": "أضف ملصقًا",
    },
    # An override, not a new key: the label sheet's catalogue gained an explicit
    # + on each row, and "tap a product" now undersells the thing to tap. pos's
    # own text serves its own screen, which has no +; EXTRA is merged over the
    # borrowed table only in THIS front end, so its wording stays its own.
    "barcode.pick": {
        "en": "Tap + on a product to queue one label",
        "fr": "Touchez + sur un produit pour ajouter une étiquette",
        "ar": "انقر + على منتج لإضافة ملصق واحد",
    },
    # Same reason: the empty sheet used to point at a "Queue all" button this
    # dialog no longer has — one press queuing an unbounded number of labels was
    # a misfire with a printer attached.
    "barcode.queue.empty": {
        "en": "Nothing queued yet. Tap + on a product on the left.",
        "fr": "Rien en file. Touchez + sur un produit à gauche.",
        "ar": "لا شيء في القائمة بعد. انقر + على منتج في اليسار.",
    },
    # The refusal a till gives when the shop has switched accounts off — the same
    # sentence from the button and from Python, because the button may be bypassed
    # by F8.
    "pay.debt_off": {
        "en": "Sales on account are switched off in Settings.",
        "fr": "Les ventes à crédit sont désactivées dans les paramètres.",
        "ar": "البيع بالدين معطّل في الإعدادات.",
    },

    # THE PAYMENT ROW'S SECONDARY BUTTON, IN ONE WORD.
    #
    # An override, not a new key: pos's catalogue says "Partial / Debt", which fits
    # neither the secondary button's width nor the merchant's word for it. The
    # command underneath is unchanged — the same payment sheet, the same F8, the
    # same Python that splits cash from debt — only the label is shorter. "Dette"
    # at body size clears the 38% share of the row in French; "دين" has no width
    # problem at all.
    "pos.pay.partial": {
        "en": "Debt",
        "fr": "Dette",
        "ar": "دين",
    },
    # The keypad's one mode, without the "#": the readout and the pad draw the
    # number-sign glyph beside the word, and printing "#" as well is the same
    # symbol twice.
    "pos.numpad.qty": {
        "en": "Qty",
        "fr": "Qté",
        "ar": "الكمية",
    },
    # The keypad's commit control and its spoken name — the accessible name and
    # the tooltip are the same sentence, so a screen reader and a hover say the
    # same thing.
    "pos.numpad.submit": {
        "en": "Submit",
        "fr": "Valider",
        "ar": "إدخال",
    },
    "pos.numpad.submit.qty": {
        "en": "Submit quantity",
        "fr": "Valider la quantité",
        "ar": "إدخال الكمية",
    },
    # The same key in the money modes: + AMT / − DISC commit an amount, and
    # the readout's tooltip says the act it will perform.
    "pos.numpad.submit.amt": {
        "en": "Submit amount",
        "fr": "Valider le montant",
        "ar": "إدخال المبلغ",
    },
    # The decimal key's tooltip, on the pads whose page has not said more.
    "pos.numpad.decimal": {
        "en": "Decimal point",
        "fr": "Virgule décimale",
        "ar": "الفاصلة العشرية",
    },
    # The cart row's remove button — its tooltip and accessible name. "Delete" was
    # the generic action's word; a cart line is removed, not deleted from records.
    "cart.remove_item": {
        "en": "Remove item",
        "fr": "Retirer l'article",
        "ar": "إزالة الصنف",
    },

    # THE SCREENS pos NEVER HAD
    #
    # The rest of this table is one batch: every key this front end passes to
    # Strings.t that exists in no catalogue anywhere (tools/i18n_check.py lists
    # them — a key with no entry shows its English fallback in every language,
    # which is how a "translated" screen stays half English). Grouped by screen,
    # same {en, fr, ar} shape, merged over pos's table like everything above.

    # The rail itself: the Returns destination, the section captions, and the
    # collapse toggle (which was qsTr — dead here, nothing installs a QTranslator).
    #
    # Two overrides, not new keys: pos's catalogue calls these screens
    # "Customers & Debts" and "Cash & Expenses", and both wrapped mid-word in
    # the rail's 224px slot — an ellipsis where a name should be. One word
    # each, and the pages the keys title follow them: the rail and a page
    # heading are the same label, and two names for one screen is how a menu
    # stops being a map of the app.
    "nav.customers": {
        "en": "Customers",
        "fr": "Clients",
        "ar": "العملاء",
    },
    "nav.cash": {
        "en": "Finances",
        "fr": "Finances",
        "ar": "المالية",
    },
    "nav.returns": {
        "en": "Returns",
        "fr": "Retours",
        "ar": "المرتجعات",
    },
    "nav.section.sell": {
        "en": "Sell",
        "fr": "Vendre",
        "ar": "البيع",
    },
    "nav.section.stock": {
        "en": "Stock",
        "fr": "Stock",
        "ar": "المخزون",
    },
    "nav.section.money": {
        "en": "Money",
        "fr": "Argent",
        "ar": "المال",
    },
    "nav.section.manage": {
        "en": "Manage",
        "fr": "Gérer",
        "ar": "الإدارة",
    },
    "nav.expand": {
        "en": "Expand menu",
        "fr": "Déplier le menu",
        "ar": "توسيع القائمة",
    },
    "nav.collapse": {
        "en": "Collapse menu",
        "fr": "Replier le menu",
        "ar": "تصغير القائمة",
    },
    # The category strip's edge buttons, which appear while it scrolls.
    "action.scroll_back": {
        "en": "Back",
        "fr": "Précédent",
        "ar": "السابق",
    },
    "action.scroll_forward": {
        "en": "Forward",
        "fr": "Suivant",
        "ar": "التالي",
    },
    # The cart line's quantity steppers.
    "cart.qty.decrease": {
        "en": "Less",
        "fr": "Moins",
        "ar": "أنقص",
    },
    "cart.qty.increase": {
        "en": "More",
        "fr": "Plus",
        "ar": "زد",
    },
    # The numpad's backspace key and its long-press hint.
    "pos.numpad.back": {
        "en": "Backspace",
        "fr": "Effacer",
        "ar": "مسح",
    },
    "pos.numpad.back.hint": {
        "en": "Backspace — hold to clear",
        "fr": "Effacer — maintenez pour tout effacer",
        "ar": "مسح — استمر بالضغط للمسح الكامل",
    },
    # The login button while the password is being checked.
    "login.busy": {
        "en": "Signing in…",
        "fr": "Connexion…",
        "ar": "جارٍ تسجيل الدخول…",
    },
    # One dashboard card the old screen never named this way.
    "dashboard.debts": {
        "en": "Who owes money",
        "fr": "Qui doit de l'argent",
        "ar": "من عليه دين",
    },
    # The sales page.
    "sales.description": {
        "en": "Every completed sale, and what is still owed on it.",
        "fr": "Chaque vente terminée, et ce qui reste dû.",
        "ar": "كل عملية بيع مكتملة وما ما زال مستحقًا عليها.",
    },
    "sales.filter.all": {
        "en": "All payments",
        "fr": "Tous les paiements",
        "ar": "كل طرق الدفع",
    },
    # The returns page and its two dialogs, whole: pos kept returns inside the
    # sales screen, so none of this vocabulary existed.
    "returns.description": {
        "en": "Goods brought back, priced at what they were sold for.",
        "fr": "Les marchandises ramenées, au prix de vente.",
        "ar": "البضائع المرتجعة، بسعر بيعها.",
    },
    "returns.search.ph": {
        "en": "Search a return or sale number",
        "fr": "Rechercher un numéro de retour ou de vente",
        "ar": "ابحث برقم المرتجع أو الفاتورة",
    },
    "returns.empty.title": {
        "en": "Nothing has come back",
        "fr": "Rien n'est revenu",
        "ar": "لم يُرجَع شيء بعد",
    },
    "returns.col.time": {
        "en": "Date",
        "fr": "Date",
        "ar": "التاريخ",
    },
    "returns.col.total": {
        "en": "Refunded",
        "fr": "Remboursé",
        "ar": "المبلغ المسترد",
    },
    "return.details_title": {
        "en": "Return",
        "fr": "Retour",
        "ar": "مرتجع",
    },
    "return.confirm": {
        "en": "Confirm return",
        "fr": "Confirmer le retour",
        "ar": "تأكيد الإرجاع",
    },
    "return.done": {
        "en": "Return {number} recorded",
        "fr": "Retour {number} enregistré",
        "ar": "تم تسجيل المرتجع {number}",
    },
    "return.sold": {
        "en": "sold {qty}",
        "fr": "vendu {qty}",
        "ar": "بيعت {qty}",
    },
    "return.of": {
        "en": "of {qty}",
        "fr": "sur {qty}",
        "ar": "من {qty}",
    },
    "return.refund": {
        "en": "Refund (estimate)",
        "fr": "Remboursement (estimation)",
        "ar": "المبلغ المسترد (تقديري)",
    },
    # The reports page.
    "reports.description": {
        "en": "What was sold, earned, spent and is still owed.",
        "fr": "Ce qui a été vendu, gagné, dépensé et reste dû.",
        "ar": "ما تم بيعه وكسبه وإنفاقه وما ما زال مستحقًا.",
    },
    "reports.section.charts": {
        "en": "Charts",
        "fr": "Graphiques",
        "ar": "الرسوم البيانية",
    },
    "reports.empty.title": {
        "en": "Nothing in this range",
        "fr": "Rien dans cette plage",
        "ar": "لا شيء في هذا النطاق",
    },
    "reports.empty.body": {
        "en": "Try a wider range of dates.",
        "fr": "Essayez une plage de dates plus large.",
        "ar": "جرّب نطاق تواريخ أوسع.",
    },
    "reports.compare": {
        "en": "Compare with previous",
        "fr": "Comparer avec la période précédente",
        "ar": "مقارنة بالفترة السابقة",
    },
    # The payments page borrows most of its words; the employees page's search
    # and the account hints are new.
    "employees.search.ph": {
        "en": "Search name or username",
        "fr": "Rechercher un nom ou un identifiant",
        "ar": "ابحث عن اسم أو اسم مستخدم",
    },
    "employees.password.keep": {
        "en": "Leave empty to keep the current one",
        "fr": "Laissez vide pour conserver l'actuel",
        "ar": "اتركه فارغًا للإبقاء على كلمة المرور الحالية",
    },
    "employees.inactive.hint": {
        "en": "An inactive account cannot sign in. Accounts are never deleted, "
              "because sales carry the name of whoever made them.",
        "fr": "Un compte inactif ne peut pas se connecter. Les comptes ne sont "
              "jamais supprimés, car les ventes portent le nom de celui qui les "
              "a faites.",
        "ar": "الحساب غير النشط لا يمكنه تسجيل الدخول. لا تُحذف الحسابات أبدًا، "
              "لأن المبيعات تحمل اسم من أجراها.",
    },
    # The backup page.
    "backup.description": {
        "en": "Copies of the whole database, newest first.",
        "fr": "Copies de la base de données complète, plus récentes d'abord.",
        "ar": "نسخ كاملة من قاعدة البيانات، الأحدث أولًا.",
    },
    "backup.empty.title": {
        "en": "No backups yet",
        "fr": "Aucune sauvegarde",
        "ar": "لا توجد نسخ احتياطية بعد",
    },
    "backup.empty.body": {
        "en": "Take one before the first busy day.",
        "fr": "Prenez-en une avant le premier jour chargé.",
        "ar": "خُذ نسخة قبل أول يوم مزدحم.",
    },
    "backup.created": {
        "en": "Saved {name}",
        "fr": "{name} enregistrée",
        "ar": "تم حفظ {name}",
    },
    "backup.restored": {
        "en": "Restored. Close and reopen the application.",
        "fr": "Restaurée. Fermez puis rouvrez l'application.",
        "ar": "تمت الاستعادة. أغلق التطبيق وافتحه من جديد.",
    },
    # The settings page's own description, its save toast, and the diagnostics
    # card.
    "settings.description": {
        "en": "The shop's details, and how the till and its printers behave.",
        "fr": "Les détails de la boutique, et le comportement de la caisse et "
              "de ses imprimantes.",
        "ar": "تفاصيل المتجر وسلوك نقطة البيع وطابعاتها.",
    },
    "settings.saved": {
        "en": "Saved",
        "fr": "Enregistré",
        "ar": "تم الحفظ",
    },
    "settings.logs": {
        "en": "Diagnostics",
        "fr": "Diagnostics",
        "ar": "التشخيصات",
    },
    "settings.logs.open": {
        "en": "Open log folder",
        "fr": "Ouvrir le dossier des journaux",
        "ar": "افتح مجلد السجلات",
    },
    # The export dialog.
    "export.body": {
        "en": "Every product, with its cost, price, stock, category and unit — "
              "the same columns the importer reads.",
        "fr": "Chaque produit, avec son coût, son prix, son stock, sa catégorie "
              "et son unité — les mêmes colonnes que l'importateur lit.",
        "ar": "كل منتج مع تكلفته وسعره ومخزونه وفئته ووحدته — نفس الأعمدة التي "
              "يقرأها المستورد.",
    },
    "export.folder": {
        "en": "Folder",
        "fr": "Dossier",
        "ar": "المجلد",
    },
    "export.folder.ph": {
        "en": "Leave empty for the application's data folder",
        "fr": "Laissez vide pour le dossier de données de l'application",
        "ar": "اتركه فارغًا لمجلد بيانات التطبيق",
    },
    "export.done": {
        "en": "{count} products written",
        "fr": "{count} produits écrits",
        "ar": "تمت كتابة {count} منتجًا",
    },
    # The import dialog's file filter name.
    "import.filter": {
        "en": "CSV files",
        "fr": "Fichiers CSV",
        "ar": "ملفات CSV",
    },
    # The arrange screen's favourites.
    "favorites.clear": {
        "en": "Clear favourites",
        "fr": "Vider les favoris",
        "ar": "مسح المفضلة",
    },
    "favorites.empty.title": {
        "en": "No favourites yet",
        "fr": "Aucun favori",
        "ar": "لا مفضلات بعد",
    },
    "favorites.empty.body": {
        "en": "Star the products that sell all day; they become the first tab "
              "on the till.",
        "fr": "Étoilez les produits qui se vendent toute la journée ; ils "
              "deviennent le premier onglet de la caisse.",
        "ar": "ضع نجمة على المنتجات التي تُباع طوال اليوم؛ تصبح أول تبويب في "
              "نقطة البيع.",
    },
    # The generic error state's title, used by the drafts dialog.
    "state.error": {
        "en": "Something went wrong",
        "fr": "Une erreur s'est produite",
        "ar": "حدث خطأ ما",
    },
    # -- The title bar's own action, and the delivery form's new words.
    #
    # One key, because the other four chips reuse keys that already exist:
    # "Add Customer" is `customers.add`, "Add product" is `products.add`,
    # "Arrange products" is `products.arrange.action`, "Barcodes" is
    # `products.hdr.barcode`.
    #
    # `purchases.supplier.hint` is an OVERRIDE: pos's catalogue says "Tap to
    # attach a supplier", which is a two-line story under a field that has
    # room for one line — the till's customer field asks its question in the
    # title alone, and a delivery opens the same way.
    "pos.action.refresh": {
        "en": "Refresh products",
        "fr": "Actualiser les produits",
        "ar": "تحديث المنتجات",
    },
    "purchases.supplier.hint": {
        "en": "Select supplier (F3)",
        "fr": "Sélectionner un fournisseur (F3)",
        "ar": "اختر المورّد (F3)",
    },
    "purchases.finder.ph2": {
        "en": "Scan or search a product (F2)",
        "fr": "Scannez ou cherchez un produit (F2)",
        "ar": "امسح أو ابحث عن منتج (F2)",
    },
    "purchases.empty.hint2": {
        "en": "Nothing on this delivery yet. Scan a product, search for one, "
              "or start from what this supplier sent last time.",
        "fr": "Rien sur ce bon de livraison pour l'instant. Scannez un "
              "produit, cherchez-le, ou partez de ce que ce fournisseur a "
              "livré la dernière fois.",
        "ar": "لا شيء في هذا التوريد بعد. امسح منتجًا أو ابحث عنه، أو ابدأ "
              "ممّا أرسله هذا المورّد آخر مرة.",
    },
    "purchases.empty.no_supplier": {
        "en": "Attach a supplier and their last items will appear here.",
        "fr": "Associez un fournisseur : ses derniers articles apparaîtront ici.",
        "ar": "أرفق مورّدًا وستظهر آخر أصنافه هنا.",
    },
    "purchases.recent.title": {
        "en": "Last from {name}",
        "fr": "Derniers de {name}",
        "ar": "آخر ما ورد من {name}",
    },
    "purchases.card.lines": {
        "en": "Lines",
        "fr": "Lignes",
        "ar": "الأسطر",
    },
    "purchases.card.qty": {
        "en": "Total qty",
        "fr": "Qté totale",
        "ar": "إجمالي الكمية",
    },
    "purchases.card.cost": {
        "en": "Total cost",
        "fr": "Coût total",
        "ar": "إجمالي التكلفة",
    },
    # The shell's own four: the title-bar theme toggle (qsTr before — dead, the
    # same as the rail's collapse toggle was) and the page host's two states.
    "shell.theme.light": {
        "en": "Light theme",
        "fr": "Thème clair",
        "ar": "المظهر الفاتح",
    },
    "shell.theme.dark": {
        "en": "Dark theme",
        "fr": "Thème sombre",
        "ar": "المظهر الداكن",
    },
    "pagehost.unbuilt": {
        "en": "This screen has not been rebuilt yet.",
        "fr": "Cet écran n'a pas encore été reconstruit.",
        "ar": "لم تُعَدْ بناء هذه الشاشة بعد.",
    },
    "pagehost.failed": {
        "en": "{title} failed to load",
        "fr": "{title} n'a pas pu être chargé",
        "ar": "تعذّر تحميل {title}",
    },
    # The cart's two ready states. The charge and discount vocabulary that
    # used to sit here went with the keypad modes that showed it: those
    # lines' names come from pos's own catalogue ("pos.free_plus" /
    # "pos.free_minus", reached through Till.addFreeAmount), which is where
    # the capability still lives.
    "pos.cart.ready.title": {
        "en": "Ready for the next sale",
        "fr": "Prêt pour la vente suivante",
        "ar": "جاهز للبيع التالي",
    },
    "pos.cart.ready.body": {
        "en": "Scan a barcode or choose a product to begin.",
        "fr": "Scannez un code-barres ou choisissez un produit pour commencer.",
        "ar": "امسح باركودًا أو اختر منتجًا للبدء.",
    },
    "pos.grid.empty": {
        "en": "No products in this category",
        "fr": "Aucun produit dans cette catégorie",
        "ar": "لا منتجات في هذه الفئة",
    },
    "pos.hold.hint": {
        "en": "Hold the sale (F5)",
        "fr": "Mettre la vente en attente (F5)",
        "ar": "تعليق البيع (F5)",
    },
    # -- The login's brand field and the till's new labelled controls. pos's own
    # keys carry the long forms ("Hold sale", "Payment calculator", "Cancel
    # sale"); the buttons below print the short ones, because a 3-column action
    # grid cell is ~120px wide and "Payment calculator" at that width is a
    # truncated word.
    "login.tagline": {
        "en": "Sales and inventory, in balance.",
        "fr": "Ventes et stock, en équilibre.",
        "ar": "المبيعات والمخزون، في توازن.",
    },
    "pos.action.hold": {
        "en": "Hold",
        "fr": "Suspendre",
        "ar": "تعليق",
    },
    "pos.action.suspended": {
        "en": "Suspended",
        "fr": "Suspendues",
        "ar": "المعلّقة",
    },
    "pos.action.calculator": {
        "en": "Calculator",
        "fr": "Calculatrice",
        "ar": "الآلة الحاسبة",
    },
    "pos.action.clear": {
        "en": "Clear cart",
        "fr": "Vider le panier",
        "ar": "تفريغ السلة",
    },
    # The labelled stock value on a product tile: "Stock 24", not an
    # unexplained 24.
    "pos.tile.stock": {
        "en": "Stock",
        "fr": "Stock",
        "ar": "المخزون",
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
            diagnostics.log.warning("no string catalogue (%s)", exc)
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
            diagnostics.log.warning("could not set the legacy language (%s)", exc)

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

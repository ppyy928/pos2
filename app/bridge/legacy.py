"""The one seam between this app and pos/.

pos/ holds a working data layer: a 3769-line SQLAlchemy module over
`pos/appdata/mizan.db`, PBKDF2 password hashing, a permission rule and a
three-language string catalogue. None of that is UI, and none of it is worth
rewriting to move a QML front end onto it, so the bridge imports it.

WHY IT IS MOUNTED UNDER A DIFFERENT NAME

Both trees call their package `app`. Putting `pos/` on sys.path would make that
name ambiguous: the first `import app` wins, and every module in the other tree
becomes unreachable — including this one, which run.py loads as `app.bridge`.
So pos/app is mounted explicitly, under a name of its own, and every borrowed
module is visible in a traceback as `mizan_pos1.<something>`. Nothing on
sys.path changes.

WHAT IS BORROWED, AND WHAT IS NOT

Borrowed: `data.db` (schema, authenticate, hash_password), `core.session` (the
permission rule) and `core.i18n` (the catalogue). Not borrowed: anything that
imports QtWidgets to build a widget — those are the files being replaced.
"""

from __future__ import annotations

import importlib
import importlib.util
import sys
from pathlib import Path
from types import ModuleType

#: Import name for pos/app. Deliberately not "app".
MOUNT = "mizan_pos1"

#: POS/pos2/app/bridge/legacy.py -> POS/pos/app
PACKAGE = Path(__file__).resolve().parents[3] / "pos" / "app"

_initialised = False


def mount() -> ModuleType:
    """Make pos/app importable as `mizan_pos1`, once."""
    existing = sys.modules.get(MOUNT)
    if existing is not None:
        return existing

    init = PACKAGE / "__init__.py"
    if not init.is_file():
        raise ImportError(f"pos/ is not beside pos2/ — expected {PACKAGE}")

    spec = importlib.util.spec_from_file_location(
        MOUNT, init, submodule_search_locations=[str(PACKAGE)]
    )
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load {init}")

    module = importlib.util.module_from_spec(spec)
    # Registered before exec_module, so a submodule that imports its own package
    # during that call finds it instead of loading a second copy.
    sys.modules[MOUNT] = module
    spec.loader.exec_module(module)
    return module


def database() -> ModuleType:
    """`mizan_pos1.data.db`, with the schema ensured on first use.

    init_db() is what pos runs at every startup: it creates the tables, applies
    its own migrations and seeds a first admin (`admin` / `admin`) when the
    employees table is empty. Called here rather than at import so that opening
    a broken or locked database is a failed *login* with a message, not a window
    that never appears.
    """
    global _initialised
    module = importlib.import_module(f"{MOUNT}.data.db", package=mount().__name__)
    if not _initialised:
        module.init_db()
        _initialised = True
    return module


def analytics() -> ModuleType:
    """`mizan_pos1.data.db_analytics` — the per-day, per-category and top-N series.

    A separate accessor because `db.py` does not re-export it: pos reaches these
    functions through its own ReportsService, and `report_*_detail` is the only
    place a report's *series* exist. `report_sales` gives rows and a summary;
    `report_sales_detail` gives those plus `by_day`, `payment_mix`, `by_category`
    and the rankings — which is everything a chart needs and nothing a table does.

    database() is called first on purpose. db_analytics imports the ORM models and
    SessionFactory from `.db`, so the schema has to be ensured before a query runs,
    and that is what database() does exactly once.
    """
    database()
    return importlib.import_module(f"{MOUNT}.data.db_analytics")


def session_user():
    """pos's own session singleton, so the permission rule has one implementation.

    Anything borrowed from pos/ later — a service, a report, a workflow guard —
    consults this object. Handing QML a second, parallel notion of who is signed
    in is how the two halves end up disagreeing about what an operator may do.
    """
    mount()
    return importlib.import_module(f"{MOUNT}.core.session").session_user


def catalogue() -> dict[str, dict[str, str]]:
    """The EN/FR/AR string table, and the languages that exist.

    `_STRINGS` is private and pos has no accessor for the whole table — only
    `tr(key)` — but the whole table is exactly what QML needs: Strings.qml hands
    the map to JavaScript and indexes it there, so it can translate without a
    round trip per label. Reading the private name keeps one catalogue; copying
    it would make two.
    """
    mount()
    module = importlib.import_module(f"{MOUNT}.core.i18n")
    table = getattr(module, "_STRINGS", None)
    if not isinstance(table, dict):
        raise ImportError(f"{MOUNT}.core.i18n has no _STRINGS table")
    return table


def languages() -> tuple[tuple[str, ...], tuple[str, ...]]:
    """(all languages, the right-to-left ones), from pos's own constants."""
    mount()
    module = importlib.import_module(f"{MOUNT}.core.i18n")
    return tuple(module.LANGUAGES), tuple(module.RTL_LANGUAGES)


def language_manager():
    """pos's own LanguageManager, so borrowed code speaks the chosen language.

    Nothing in QML reads it — the bridge keeps its own copy of the active
    language — but `fmt_money(currency=True)` and every db error message go
    through `tr()`, which reads this. Left out of step, the UI would be French
    and its amounts would carry an English currency.
    """
    mount()
    return importlib.import_module(f"{MOUNT}.core.i18n").i18n


def formatters():
    """`mizan_pos1.core.format` — fmt_money and fmt_qty.

    Every amount QML displays is a string built here. The contract in
    PosPage.qml's header is deliberate: the currency, the decimal count and the
    rounding rule are pos's, and a second implementation in JavaScript would be a
    second set of rules for the same money.
    """
    mount()
    return importlib.import_module(f"{MOUNT}.core.format")


def printing():
    """`mizan_pos1.core.receipt_printing` — the receipt renderer and its printers.

    Imported lazily by the caller because it pulls in Pillow and a font search: a
    machine with no printer configured should still open the till, and a missing
    dependency should surface as a failed print with a message rather than a
    window that never appears.
    """
    mount()
    return importlib.import_module(f"{MOUNT}.core.receipt_printing")


def labels():
    """`mizan_pos1.core.label_printing` — the shelf-label renderer and its printer.

    A separate module and a separate device from the receipt: a label printer speaks
    TSPL or ZPL onto 40x25mm stock, a receipt printer speaks ESC/POS onto an 80mm
    roll, and a shop that owns one very often does not own the other. Lazy for the
    same reason `printing()` is — Pillow, a font search and a barcode rasteriser
    behind a feature most tills never open.
    """
    mount()
    return importlib.import_module(f"{MOUNT}.core.label_printing")


def scanner():
    """`mizan_pos1.core.scanner` — normalize_digits.

    Arabic-Indic digits are what an Arabic keyboard produces and what a scanner
    never produces; one function decides whether a typed string is a barcode, and
    it is the one pos already trusts.
    """
    mount()
    return importlib.import_module(f"{MOUNT}.core.scanner")

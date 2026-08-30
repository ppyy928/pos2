"""MIZAN POS 2 — application entry point.

    python run.py              # launch
    python run.py --diag       # launch and print the resolved QML environment
    python run.py --check      # verify the vendored style, then exit
    python run.py --mica       # launch with the Windows 11 Mica backdrop

Bootstrap order is not arbitrary; each step depends on the one before it:

1. ``pos2/vendor`` goes on ``sys.path`` *first*, so ``import fluentpyside``
   resolves to the scaled copy rather than any pip-installed one.
2. ``fluentpyside.apply()`` sets ``QML2_IMPORT_PATH`` and the QQuickStyle. It
   must run before ``QQmlApplicationEngine()`` is constructed, because the
   engine snapshots the import path at construction.
3. Fonts are registered before ``engine.load()``, and the real icon family name
   is published as a context property — the style's typography block reads
   ``iconFontFamilyResizable`` and falls back to a hardcoded guess without it.
   The base UI font is set in the same window, before any control exists: a
   control reads the application font when it is constructed, and it is what
   makes the type match the scaled geometry (see ``apply_base_font``).
4. ``register_context()`` before ``load()``; ``setup_windows()`` after.

Why ``QApplication`` and not ``QGuiApplication``: the UI is pure QML and would
run on either, but the business layer carried over from ``pos`` uses
QtPrintSupport for receipts and labels, and native file dialogs for backup.
Those need the QtWidgets application object. It costs nothing else.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
VENDOR = HERE / "vendor"
VENDOR_PKG = VENDOR / "fluentpyside"
QML_DIR = HERE / "qml"
MAIN_QML = QML_DIR / "Main.qml"

APP_NAME = "MIZAN POS"
APP_ORG = "MIZAN"

# MIZAN's audited accent. Drives Fluent's whole derived accent family
# (hover/pressed/selected), so setting it here recolours every styled control.
BRAND_ACCENT = "#127A4B"

# Light is the implemented baseline, same as pos. Overridden later by the
# ui.theme setting once the settings bridge lands.
DEFAULT_THEME = "light"

ICON_FONT = "FluentSystemIcons-Resizable.ttf"

# The base UI size every control inherits, in device-independent pixels. Must
# stay equal to Fluent.typography.body (and so Tokens.font.body) — see
# apply_base_font() for why this exists at all.
BASE_FONT_PX = 17

# Witnesses that the scaler actually ran: the values these files must hold
# after tools/scale_fluent.py. Checked at every launch — a stale or pristine
# vendor tree is the one failure mode that looks like "nothing happened".
WITNESSES: tuple[tuple[str, str, str], ...] = (
    ("FluentControls/Fluent.qml", "readonly property int body: 17", "type ramp"),
    (
        "QtQuick/Controls/FluentWinUI3/Fluent.qml",
        "readonly property int body: 17",
        "type ramp (style)",
    ),
    # A layer-5 patch, the class of change most likely to regress silently: the
    # patches match exact source text, so any upstream reformat stops them.
    (
        "FluentControls/CtrlBtn.qml",
        "implicitHeight: isMacStyle ? 12 : 56",
        "caption buttons filling the title bar",
    ),
)

# `prefer` redirects every QML load into the DLL's compiled-in resources, which
# makes the scaled files on disk dead code. It must not survive vendoring.
NO_PREFER = (
    "QtQuick/Controls/FluentWinUI3/qmldir",
    "QtQuick/Controls/FluentWinUI3/impl/qmldir",
)


def _die(message: str, *hint: str) -> "NoReturn":  # noqa: F821
    print(f"error: {message}", file=sys.stderr)
    for line in hint:
        print(f"  {line}", file=sys.stderr)
    raise SystemExit(1)


def verify_vendor() -> None:
    """Fail loudly if the vendored style is missing, pristine or resource-shadowed."""
    if not VENDOR_PKG.is_dir():
        _die(
            f"no vendored FluentPySide at {VENDOR_PKG}",
            "build it:  python tools/scale_fluent.py",
        )

    style = VENDOR_PKG / "QtQuick" / "Controls" / "FluentWinUI3"
    if not (style / "Config.qml").is_file():
        _die(
            f"vendored style is incomplete: {style}",
            "rebuild it:  python tools/scale_fluent.py",
        )

    for rel, needle, label in WITNESSES:
        path = VENDOR_PKG / rel
        if not path.is_file():
            _die(f"missing vendored file: {path}")
        if needle not in path.read_text(encoding="utf-8"):
            _die(
                f"{rel} is not scaled ({label}): expected `{needle}`",
                "the vendor tree looks pristine — re-run:",
                "  python tools/scale_fluent.py",
            )

    for rel in NO_PREFER:
        path = VENDOR_PKG / rel
        if not path.is_file():
            _die(f"missing vendored file: {path}")
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.strip().startswith("prefer "):
                _die(
                    f"{rel} still carries a `prefer` redirect",
                    "every scaled QML file would be ignored in favour of the",
                    "resources compiled into the style DLL. Re-run:",
                    "  python tools/scale_fluent.py",
                )


def bootstrap_style():
    """Put the scaled FluentPySide in charge and prove it took effect."""
    sys.path.insert(0, str(VENDOR))

    import fluentpyside

    pkg = Path(fluentpyside.__file__).resolve().parent
    if pkg != VENDOR_PKG:
        _die(
            f"another fluentpyside shadowed the vendored copy: {pkg}",
            f"expected: {VENDOR_PKG}",
            "uninstall the pip package, or run from the pos2 directory",
        )

    # apply() swallows every exception from set_style(), so its return value is
    # the only evidence of which style tree actually won. Check it.
    used = Path(fluentpyside.apply(accent_color=BRAND_ACCENT, theme=DEFAULT_THEME))
    used = used.resolve()
    if VENDOR not in used.parents:
        _die(
            f"FluentPySide fell back to an unscaled style: {used}",
            "expected a path under:  " + str(VENDOR),
            "this is the silent-fallback path in fluentpyside.apply()",
        )
    return fluentpyside, used


def load_icon_font() -> str | None:
    """Register the Fluent icon font and return its real family name."""
    from PySide6.QtGui import QFontDatabase

    path = VENDOR_PKG / "FluentControls" / ICON_FONT
    if not path.is_file():
        print(f"warning: icon font not found: {path}", file=sys.stderr)
        return None

    font_id = QFontDatabase.addApplicationFont(str(path))
    if font_id < 0:
        print(f"warning: failed to load {ICON_FONT}", file=sys.stderr)
        return None

    families = QFontDatabase.applicationFontFamilies(font_id)
    return families[0] if families else None


def apply_base_font() -> None:
    """Set the UI font every control inherits.

    This is the single most consequential line in the file, and the one thing
    the vendoring scaler cannot do.

    The scaler rewrites the style's *geometry* tables, so a FluentWinUI3 button
    is 48px tall here instead of 32px. It does not touch the application font,
    because there isn't one in the QML — a Qt Quick Control's ``font`` is
    inherited from ``QGuiApplication.font()``, which on Windows is 9pt Segoe UI,
    about 12px. Left alone, the whole app is 12px labels floating inside 48px
    controls: exactly the "everything is too small" complaint, and *worse* than
    the unscaled library, where at least the proportions agreed.

    Setting it once here reaches every control in the process — menus, combo box
    popups, text fields, dialog buttons, tooltips, the lot — including the ones
    no page ever names. The alternative is ``font.pixelSize`` on every control in
    every page, which is a line that only has to be forgotten once.

    17px is ``Fluent.typography.body``, which is what ``Tokens.font.body``
    resolves to, so Python and QML agree on one number rather than drifting.

    pixelSize, not pointSize: QML's ``font.pixelSize`` is in the same
    device-independent pixels as every other size in this UI, and the rounding
    policy above already passes fractional DPI straight through. Going via points
    would scale the type by DPI a second time and detune it from the geometry.

    The family list is a fallback chain, not a choice: "Segoe UI Variable" is the
    Windows 11 UI face the style is designed against but carries no Arabic, and
    this app ships Arabic. Qt substitutes per missing glyph, so naming Tahoma —
    Windows' long-standing Arabic-capable UI face — makes that substitution
    predictable instead of leaving it to the system default.
    """
    from PySide6.QtGui import QFont, QGuiApplication

    font = QFont()
    font.setFamilies(["Segoe UI Variable", "Segoe UI", "Tahoma"])
    font.setPixelSize(BASE_FONT_PX)
    QGuiApplication.setFont(font)


def register_bridges(engine) -> None:
    """Expose the Python business layer to QML.

    The bridge package is built incrementally, so its absence is a normal state
    early on — but it is reported, never swallowed: without it the UI has no
    data at all, and that must not look like a styling problem.
    """
    try:
        from app.bridge import register_all
    except ImportError as exc:
        print(
            f"note: no bridge layer yet ({exc}) — UI runs without data",
            file=sys.stderr,
        )
        return
    register_all(engine)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=APP_NAME)
    parser.add_argument(
        "--check", action="store_true", help="verify the vendored style and exit"
    )
    parser.add_argument(
        "--diag", action="store_true", help="print the resolved QML environment"
    )
    parser.add_argument(
        "--mica",
        action="store_true",
        help="enable the Windows 11 Mica backdrop (cosmetic, off by default)",
    )
    args = parser.parse_args(argv)

    verify_vendor()
    if args.check:
        print(f"vendored style OK: {VENDOR_PKG}")
        return 0

    if not MAIN_QML.is_file():
        _die(f"missing {MAIN_QML}")

    from PySide6.QtCore import Qt, QTimer
    from PySide6.QtGui import QGuiApplication
    from PySide6.QtQml import QQmlApplicationEngine
    from PySide6.QtQuickControls2 import QQuickStyle
    from PySide6.QtWidgets import QApplication

    # Non-integer DPI passes through instead of snapping to 100/200%. We size
    # everything ourselves, so double-rounding is the only thing to avoid.
    QGuiApplication.setHighDpiScaleFactorRoundingPolicy(
        Qt.HighDpiScaleFactorRoundingPolicy.PassThrough
    )

    fluentpyside, style_path = bootstrap_style()

    app = QApplication(sys.argv)
    app.setApplicationName(APP_NAME)
    app.setOrganizationName(APP_ORG)

    # Before the engine exists: a control snapshots the application font when it
    # is created, so this has to be in place before any QML is instantiated.
    apply_base_font()

    icon_family = load_icon_font()
    QQuickStyle.setStyle("FluentWinUI3")

    engine = QQmlApplicationEngine()
    # The package dir holds both QtQuick/Controls/FluentWinUI3 and
    # FluentControls, so one path resolves both module trees.
    engine.addImportPath(str(VENDOR_PKG))
    engine.addImportPath(str(QML_DIR))  # import Mizan

    engine.warnings.connect(
        lambda errors: [
            print(f"qml: {e.toString()}", file=sys.stderr) for e in errors
        ]
    )

    fluentpyside.register_context(engine)

    ctx = engine.rootContext()
    if icon_family:
        # The style's typography block reads this name; without it, it guesses.
        ctx.setContextProperty("iconFontFamilyResizable", icon_family)
        ctx.setContextProperty("iconFontFamily", icon_family)
    register_bridges(engine)

    if args.diag:
        print(f"style path   : {style_path}")
        print(f"icon family  : {icon_family}")
        print(f"ui font      : {app.font().families()} @ {app.font().pixelSize()}px")
        print(f"import paths : {engine.importPathList()}")
        print(f"qml entry    : {MAIN_QML}")

    engine.load(str(MAIN_QML))
    if not engine.rootObjects():
        _die(f"failed to load {MAIN_QML}", "see the qml: lines above")

    fluentpyside.setup_windows(engine)
    _ensure_visible(engine)
    if args.mica:
        _enable_mica(engine, QTimer)

    return app.exec()


def _ensure_visible(engine) -> None:
    """Show the window if the native frameless setup failed to.

    ``FluentWindowBase`` starts at ``visible: !isWindows`` — on Windows nothing
    but ``setup_windows()`` reveals it — and ``setup_windows()`` wraps its whole
    body in a bare ``except Exception: pass``. A failure there therefore leaves
    a running process with no window and no message, which from the outside is
    indistinguishable from a hang. A window with the wrong frame beats no
    window, so show it and say why.
    """
    root = engine.rootObjects()[0]
    if root.property("isFluentWindow") is not True:
        return  # not one of ours — leave its visibility alone
    if root.isVisible():
        return

    print(
        "warning: the frameless window setup did not complete; showing the "
        "window with whatever frame the platform gives it",
        file=sys.stderr,
    )
    root.setVisible(True)


def _enable_mica(engine, QTimer) -> None:
    """Turn on the Mica backdrop. Windows 11 only, and entirely cosmetic.

    Two things must both happen, and neither works alone:

    * DWM has to accept the backdrop attribute, which it only does once the
      native window exists — hence the retry.
    * QML has to set ``Fluent.backdropEnabled``, which is what makes the window
      and its background rectangle transparent so the backdrop shows through.

    The order is the whole reason this is opt-in rather than the default. Doing
    it the other way round — transparent first, Mica after — leaves a
    see-through window on every machine that refuses the backdrop (Windows 10,
    most VMs, remote desktop), and the failure is silent. So transparency is
    only switched on once ``apply_mica`` has reported success.
    """
    if sys.platform != "win32":
        print("note: --mica is Windows-only; ignored", file=sys.stderr)
        return

    import fluentpyside
    from fluentpyside._mica import apply_mica

    manager = fluentpyside.theme_manager()
    if manager is None:
        print("note: no theme manager; --mica ignored", file=sys.stderr)
        return
    # Lets the library reapply the backdrop itself on every theme change.
    manager.setBackdrop(True)

    root = engine.rootObjects()[0]
    max_attempts = 5
    retry_ms = 200
    attempts = {"n": 0}

    def attempt() -> None:
        attempts["n"] += 1
        try:
            applied = apply_mica(root, dark=manager._resolve_dark())
        except Exception as exc:  # cosmetic only — never fatal
            print(f"note: Mica unavailable ({exc}); solid background", file=sys.stderr)
            return

        if applied:
            # Safe now, and only now: this is what goes transparent.
            root.setBackdropEnabled(True)
            return

        if attempts["n"] < max_attempts:
            QTimer.singleShot(retry_ms, attempt)
        else:
            print(
                "note: this system did not accept a Mica backdrop; "
                "keeping the solid window background",
                file=sys.stderr,
            )

    QTimer.singleShot(0, attempt)


if __name__ == "__main__":
    raise SystemExit(main())

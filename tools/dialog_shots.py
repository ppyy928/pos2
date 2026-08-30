"""Render every dialog offscreen and save a PNG of each.

Not a test: a way to LOOK at them. Layout faults in a dialog — a heading that repeats
the label under it, a list that runs past the frame, groups with no visual separation —
are invisible to a compile check and obvious in a picture.

    python tools/dialog_shots.py [outdir]

Each dialog is created inside a real window with the bridge attached, given a moment to
lay out and load its data, then grabbed. Dialogs are sized by their own
`preferredWidth`/`preferredHeight`, so the window is deliberately large.
"""

from __future__ import annotations

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
QML_DIR = os.path.join(ROOT, "qml")

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
sys.path.insert(0, ROOT)
sys.path.insert(0, os.path.join(ROOT, "vendor"))
os.chdir(ROOT)

import fluentpyside  # noqa: E402

from PySide6.QtGui import QGuiApplication  # noqa: E402
from PySide6.QtQml import QQmlApplicationEngine  # noqa: E402
from PySide6.QtQuickControls2 import QQuickStyle  # noqa: E402
from PySide6.QtTest import QTest  # noqa: E402

#: A context per dialog that puts it in its most crowded state — an existing record
#: rather than an empty one, because that is where layout faults show.
CONTEXTS: dict[str, dict] = {
    "ArrangeDialog.qml": {},
    "BarcodeLabelsDialog.qml": {},
    "CashEntryDialog.qml": {"purpose": "expense"},
    "CategoriesDialog.qml": {},
    "CustomerFormDialog.qml": {"customer_id": 7, "section": "payments"},
    "CustomerPickerDialog.qml": {},
    "EmployeeFormDialog.qml": {},
    "ExportDialog.qml": {},
    "ImportDialog.qml": {},
    "MultiUnitsDialog.qml": {},
    "ProductFormDialog.qml": {"product_id": 552},
    "ProductPickerDialog.qml": {},
    "PurchaseFormDialog.qml": {},
    "QuickAddProductDialog.qml": {"code": "5449000996"},
    "ReturnDetailsDialog.qml": {"return_id": 1},
    "ReturnDialog.qml": {"sale_id": 1},
    "SaleDetailsDialog.qml": {"sale_id": 1},
    "SaleSelectorDialog.qml": {"purpose": "return"},
    "SavedCartsDialog.qml": {},
    "StockAdjustDialog.qml": {"product_id": 552},
    "StockCountDialog.qml": {},
    "StockLedgerDialog.qml": {},
    "SupplierFormDialog.qml": {"supplier_id": 3},
    "UnitsDialog.qml": {},
    "UnknownBarcodeDialog.qml": {"code": "9999999999999"},
}

HOST = """
import QtQuick
import QtQuick.Controls as QC
QC.ApplicationWindow {
    id: win
    width: 1700
    height: 1060
    visible: true
    color: "#8A8A8A"
    property var dlg: null
    function present(file, ctx) {
        if (dlg) { dlg.close(); dlg.destroy() }
        var c = Qt.createComponent(file)
        if (c.status === Component.Error) { console.log("ERROR " + c.errorString()); return null }
        dlg = c.createObject(win.contentItem, { context: ctx })
        dlg.open()
        return dlg
    }
}
"""


def main() -> int:
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "shots")
    os.makedirs(out, exist_ok=True)

    # run.py's own startup, in run.py's order: the base UI font must be set BEFORE any
    # control exists (a control snapshots QGuiApplication.font() when it is built), and
    # the icon family has to be registered and handed to QML by its real name. Without
    # both, the pictures come out with the geometry right and every word missing —
    # which is exactly how the first pass of this tool failed.
    from PySide6.QtGui import QFont, QFontDatabase

    # run.py's accent and theme, not the style's defaults: a picture in the wrong
    # accent is a picture of an app nobody runs.
    fluentpyside.apply(accent_color="#127A4B", theme="light")
    QQuickStyle.setStyle("FluentWinUI3")
    app = QGuiApplication(sys.argv)  # noqa: F841 - an engine needs one alive

    # The offscreen QPA plugin has no system font database, so naming "Segoe UI" gets
    # nothing and every label draws blank — which is how the first two passes of this
    # tool produced pictures of empty boxes. Loading the file as an APPLICATION font
    # makes it available whatever the platform knows about.
    ui_family = "Tahoma"
    for candidate in (r"C:\Windows\Fonts\segoeui.ttf",
                      r"C:\Windows\Fonts\tahoma.ttf",
                      r"C:\Windows\Fonts\arial.ttf"):
        if os.path.exists(candidate):
            loaded = QFontDatabase.addApplicationFont(candidate)
            families = QFontDatabase.applicationFontFamilies(loaded)
            if families:
                ui_family = families[0]
                break

    base = QFont()
    base.setFamilies([ui_family, "Segoe UI Variable", "Segoe UI", "Tahoma"])
    base.setPixelSize(17)
    QGuiApplication.setFont(base)
    print(f"ui font: {ui_family}")

    icon_path = os.path.join(ROOT, "vendor", "fluentpyside", "FluentControls",
                             "FluentSystemIcons-Resizable.ttf")
    icon_id = QFontDatabase.addApplicationFont(icon_path)
    icon_family = (QFontDatabase.applicationFontFamilies(icon_id) or
                   ["Fluent System Icons Resizable"])[0]

    from app.bridge.root import App

    engine = QQmlApplicationEngine()
    engine.addImportPath(os.path.join(ROOT, "vendor", "fluentpyside"))
    engine.addImportPath(QML_DIR)
    bridge = App()
    ctx = engine.rootContext()
    ctx.setContextProperty("app", bridge)
    ctx.setContextProperty("iconFontFamilyResizable", icon_family)
    ctx.setContextProperty("iconFontFamily", icon_family)
    engine.loadData(HOST.encode())
    win = engine.rootObjects()[0]
    QTest.qWait(500)

    # Somebody has to be logged in or every permission-gated control is hidden and the
    # pictures show a dialog nobody will ever see.
    from mizan_pos1.data import db as ldb

    admin = next(e for e in ldb.fetch_employees() if e["role"] == "admin")
    bridge.session.adopt(admin)
    QTest.qWait(200)

    made = 0
    for name in sorted(CONTEXTS):
        path = os.path.join(QML_DIR, "dialogs", name)
        if not os.path.exists(path):
            print(f"  skip {name} (missing)")
            continue
        url = "file:///" + path.replace("\\", "/")
        dlg = win.present(url, CONTEXTS[name])
        if dlg is None:
            print(f"  FAIL {name}")
            continue
        QTest.qWait(700)
        image = win.grabWindow()
        target = os.path.join(out, name.replace(".qml", "") + ".png")
        image.save(target)
        h = dlg.property("height") or 0
        w = dlg.property("width") or 0
        print(f"  {name:28s} {w:>5.0f}x{h:<5.0f} -> {os.path.basename(target)}")
        made += 1

    print(f"\n{made} dialogs rendered into {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

"""Compile every QML file in this app and report the ones that will not load.

Not a unit test: a syntax error, an unknown type, a misspelled property or a signal
handler with the wrong arity is invisible until the file is first *compiled*, and a
dialog is only compiled when an operator opens it. This walks the tree once so that
never has to be the discovery path.

    python tools/qml_check.py

It compiles rather than instantiates, on purpose. Instantiating would also catch
binding loops, but half the tree is Windows and Popups that cannot be created
without a real scene graph, and a harness that crashes on those reports nothing
about the files it had not reached yet.

The bridge is deliberately absent. Every `app.*` read in this app is guarded with
`typeof app !== "undefined"`, so nothing here depends on Python being wired up.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
VENDOR_PKG = ROOT / "vendor" / "fluentpyside"
QML_DIR = ROOT / "qml"

# Before any Qt import: no display is needed to build a component.
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

sys.path.insert(0, str(ROOT / "vendor"))

import fluentpyside
from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine
from PySide6.QtQuickControls2 import QQuickStyle


def main() -> int:
    fluentpyside.apply()
    QQuickStyle.setStyle("FluentWinUI3")

    app = QGuiApplication(sys.argv)  # noqa: F841 — an engine needs one

    engine = QQmlEngine()
    engine.addImportPath(str(VENDOR_PKG))
    engine.addImportPath(str(QML_DIR))

    # Singletons and the icon family the style asks for, so a component that reads
    # them is not reported for the harness's own omission.
    ctx = engine.rootContext()
    ctx.setContextProperty("iconFontFamilyResizable", "Fluent System Icons Resizable")
    ctx.setContextProperty("iconFontFamily", "Fluent System Icons Resizable")

    failures = 0
    files = sorted(QML_DIR.rglob("*.qml"))
    for path in files:
        component = QQmlComponent(engine, QUrl.fromLocalFile(str(path)))
        if component.isError():
            failures += 1
            print(f"FAIL {path.relative_to(ROOT)}", flush=True)
            for error in component.errors():
                print(f"     {error.toString()}", flush=True)

    print(f"\n{len(files) - failures}/{len(files)} QML files compiled")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())

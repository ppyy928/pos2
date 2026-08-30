"""Everything QML can reach, in one context property.

run.py calls `register_all(engine)` before it loads Main.qml, so `app` exists
before the first binding is evaluated — which matters, because the Strings
singleton reads `app.i18n` the moment any label asks for text.

    engine.rootContext().setContextProperty("app", App(parent=engine))

The bridge is parented to the engine rather than held in a module global: that is
what keeps it alive for exactly as long as the QML that reads it, and it means a
second engine (a test harness) gets its own bridge instead of sharing one.
"""

from __future__ import annotations

from .root import App

__all__ = ["App", "register_all"]


def register_all(engine) -> None:
    engine.rootContext().setContextProperty("app", App(parent=engine))

"""What QML reports about itself, behind `app.diag`.

    Diag.action("PosPage", "pay pressed", { total: 1245.41 })
    Diag.warn("ImportDialog", "no column chosen for name")

Every *Python* action is traced automatically by `app/instrument.py`, and the
things QML does on its own — a page opening, a dialog closing, a toast the
operator read, a navigation, a shortcut — are the half that no wrapper can see.
They arrive here and go into the same `mizan.trace` channel, in the same file,
at the same indentation, so one `debug.log` reads as one story:

    * shell: navigate products
    * PageHost: page loaded products
      > products.search(text='cola', page=1)
      < products.search = [12 x {id=552, …} …] 6.1ms
    * ToastHost: 12 products found

WHY QML DOES NOT CALL THIS OBJECT DIRECTLY

`qml/Mizan/Diag.qml` is a singleton facade over it. Two reasons, both load-time:
`app` is a context property that `tools/qml_check.py` deliberately does not set,
so every read of it in this app is guarded — and a guard repeated in twenty
components is a guard that will be forgotten in the twenty-first. The facade also
lets QML omit the payload (`Diag.action(source, what)`), since a Qt slot cannot
have optional arguments.

NOTHING HERE CAN BREAK A SCREEN

A logging call that raises inside a QML signal handler aborts the rest of that
handler — the button would half-work because of its own log line. So every slot
is total: bad arguments are coerced, never rejected.
"""

from __future__ import annotations

from pathlib import Path

from PySide6.QtCore import Property, QObject, Slot

from .. import diagnostics, instrument


class Diag(QObject):
    #: Not instrumented, deliberately: `install()` skips any class already
    #: marked, and wrapping these slots would print `> diag.action(...)` and
    #: `< diag.action 0.0ms` around every single line QML writes.
    __mizan_traced__ = True

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)

    # -- the trace --------------------------------------------------------
    @Slot(str, str, "QVariant")
    def action(self, source: str, what: str, detail: object) -> None:
        """Something the operator did. `detail` may be null."""
        instrument.action(str(source), str(what), detail)

    @Slot(str, str)
    def note(self, source: str, message: str) -> None:
        """A fact worth keeping that is not an action and not a fault."""
        instrument.note(str(source), str(message))

    @Slot(str, str)
    def warn(self, source: str, message: str) -> None:
        """Something is wrong but the screen carried on. WARNING, so it reaches
        app.log as well as the trace — a soft failure nobody reads is the one
        that turns into a support call."""
        diagnostics.log.warning("qml %s: %s", source, message)

    @Slot(str, str)
    def fail(self, source: str, message: str) -> None:
        """A defect: a page that would not load, a component that would not
        build. ERROR, so it lands in errors.log with everything else that broke."""
        diagnostics.log.error("qml %s: %s", source, message)

    # -- where the files are ----------------------------------------------
    @Property(str, constant=True)
    def logDir(self) -> str:
        """The directory the four log files are in, for a screen to show.

        Empty when nothing called `init()` — a harness that builds the bridge
        without diagnostics, where `LOG_DIR` is still the empty path and would
        otherwise render as ".". A screen offering the folder tests this string,
        so the answer has to be honestly empty rather than technically a path.

        Constant on purpose: `init()` resolves it once per process, before any
        QML exists, and it cannot change afterwards.
        """
        return "" if diagnostics.LOG_DIR == Path() else str(diagnostics.LOG_DIR)

    @Property(bool, constant=True)
    def tracing(self) -> bool:
        return bool(diagnostics.TRACE)

    @Slot(result=bool)
    def openLogFolder(self) -> bool:
        """Show the log directory in the file manager.

        This is what makes the whole mechanism usable by the person who has the
        problem: "send me your logs" becomes one button instead of a path to
        read down a phone line. Imported here rather than at module scope so the
        bridge keeps its no-QtGui-at-import property.
        """
        try:
            from PySide6.QtCore import QUrl
            from PySide6.QtGui import QDesktopServices

            return bool(
                QDesktopServices.openUrl(
                    QUrl.fromLocalFile(str(diagnostics.LOG_DIR))
                )
            )
        except Exception:  # noqa: BLE001 - a button that cannot open a folder
            diagnostics.log.warning("could not open the log folder", exc_info=True)
            return False

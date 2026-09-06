"""Headless smoke test for app/diagnostics.py and app/instrument.py.

Verifies, without a window:
1. init() creates the log directory and the four files' handlers.
2. Records land at the right severities in the right files.
3. sys.excepthook writes CRITICAL + traceback into errors.log.
4. The direct-connection trick: a slot connected to a Qt Signal and called
   from inside an except block still sees sys.exc_info(), so the central
   `rejected` tap in root.py recovers full tracebacks.
5. An exception in a Qt-invoked slot lands in errors.log and the loop survives.
6. An exception on a thread-pool runnable lands in errors.log.
7. brief() is bounded, total and redacting — it runs inside every traced call.
8. The action trace: a wrapped slot logs its call, its result and its duration;
   a password argument is never written down; a slot that raises is recorded
   with its arguments and still raises; a call that blocks the GUI thread is
   promoted to a WARNING; nesting is indented.
9. Signals are traced, and property-notification signals are not.
10. The real bridge gets wrapped end to end, and `app.diag` — the object QML
    logs through — does not wrap itself.
Run from pos2/:  python -m tools.log_check
"""

from __future__ import annotations

import logging
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))

from app import diagnostics

failures: list[str] = []


def check(label: str, ok: bool) -> None:
    print(f"{'PASS' if ok else 'FAIL'}: {label}")
    if not ok:
        failures.append(label)


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8") if path.is_file() else ""


# -- 1. init ----------------------------------------------------------------
log_dir = diagnostics.init()
check("log dir created", (log_dir / "app.log").exists())
check("banner recorded", "logging initialized" in read(log_dir / "app.log"))
check("environment banner", "environment: python=" in read(log_dir / "app.log"))

# -- 2. levels land where expected ------------------------------------------
diagnostics.log.debug("SMOKE debug line")
diagnostics.business().info("SMOKE business line")
diagnostics.log.error("SMOKE error line")
for handler in logging.getLogger().handlers:
    handler.flush()
check("debug.log has the DEBUG line", "SMOKE debug line" in read(log_dir / "debug.log"))
check("app.log has the INFO line", "SMOKE business line" in read(log_dir / "app.log"))
check("debug.log has the INFO line too", "SMOKE business line" in read(log_dir / "debug.log"))
check("errors.log has the ERROR line", "SMOKE error line" in read(log_dir / "errors.log"))
check("app.log keeps ERROR out of DEBUG-only debug.log",
      "SMOKE error line" in read(log_dir / "app.log"))
check("business logger name", "mizan.business" in read(log_dir / "app.log"))

# -- 3. excepthook ------------------------------------------------------------
try:
    raise ValueError("SMOKE boom")
except ValueError:
    diagnostics._excepthook(*sys.exc_info())
for handler in logging.getLogger().handlers:
    handler.flush()
errors_text = read(log_dir / "errors.log")
check("excepthook logged CRITICAL", "uncaught exception" in errors_text)
check("excepthook kept the traceback", "ValueError: SMOKE boom" in errors_text)
check("traceback has this file's frames", "log_check.py" in errors_text)

# -- 4. the direct-connection trick ------------------------------------------
from PySide6.QtCore import QObject, Signal


class Dummy(QObject):
    rejected = Signal(str)

    def __init__(self) -> None:
        super().__init__()
        self.messages: list[str] = []
        self.rejected.connect(self._on_rejected)

    def _on_rejected(self, message: str) -> None:
        # Same shape as root.py's tap: the traceback comes from the still
        # active except block of the emitter.
        diagnostics.log.error(
            "SMOKE rejected: %s", message, exc_info=diagnostics.active_exc()
        )
        self.messages.append(message)


dummy = Dummy()
try:
    raise KeyError("SMOKE missing key")
except KeyError:
    dummy.rejected.emit("it refused")
for handler in logging.getLogger().handlers:
    handler.flush()
tap_text = read(log_dir / "errors.log")
check("tap slot ran synchronously", dummy.messages == ["it refused"])
check("tap recovered the traceback", "KeyError: 'SMOKE missing key'" in tap_text)

# and outside an except block there is no traceback noise
dummy.rejected.emit("clean refusal")
for handler in logging.getLogger().handlers:
    handler.flush()
clean_text = read(log_dir / "errors.log")
check("no exc_info outside except", "NoneType" not in clean_text)

# -- 5. the safety net: an exception in a Qt-invoked slot --------------------
# A slot called from C++ (a QTimer here, QML everywhere else) that raises is
# the one path no bridge try/except can cover. If PySide6 routes it through
# sys.excepthook — which our init() replaced — it lands in errors.log and the
# app keeps running. That is the claim behind "every operation is logged".
from PySide6.QtCore import QCoreApplication, QTimer

app = QCoreApplication([])
slot_calls: list[str] = []


def boom_slot() -> None:
    slot_calls.append("before")
    raise RuntimeError("SMOKE slot boom")


def after_boom() -> None:
    # Still runs: the crash in the earlier timer must not take the loop down.
    slot_calls.append("after")
    app.quit()


QTimer.singleShot(50, boom_slot)
QTimer.singleShot(150, after_boom)
app.exec()
for handler in logging.getLogger().handlers:
    handler.flush()
net_text = read(log_dir / "errors.log")
check("event loop survived the slot crash", slot_calls == ["before", "after"])
check("slot exception reached errors.log", "SMOKE slot boom" in net_text)

# -- 6. the safety net: an exception in a pool-thread runnable ----------------
import time

from PySide6.QtCore import QRunnable, QThreadPool


class BoomTask(QRunnable):
    def run(self) -> None:
        raise RuntimeError("SMOKE pool boom")


QThreadPool.globalInstance().start(BoomTask())
time.sleep(1.0)  # the pool thread needs a moment
for handler in logging.getLogger().handlers:
    handler.flush()
pool_text = read(log_dir / "errors.log")
check("pool exception reached errors.log", "SMOKE pool boom" in pool_text)

# -- 7. brief(): bounded, total, redacting -----------------------------------
from app.diagnostics import brief

check("brief keeps a short string whole", brief("cola") == "'cola'")
check("brief bounds a long string", len(brief("x" * 5000)) < 200)
check("brief summarises a big list", brief([{"id": 1}] * 5000).startswith("[5000 x"))
check("brief names a dict's keys", "name='Cola'" in brief({"name": "Cola"}))
check("brief redacts by key name", "***" in brief({"password": "hunter2"}))
check("brief never leaks a redacted value", "hunter2" not in brief({"pin": "hunter2"}))


class Unprintable:
    def __repr__(self) -> str:
        raise RuntimeError("SMOKE repr boom")


check("brief survives a repr that raises", "Unprintable" in brief(Unprintable()))

# -- 8. the action trace ------------------------------------------------------
import time

from PySide6.QtCore import Property, Slot

from app import instrument


class Probe(QObject):
    """One of everything a bridge controller has."""

    saved = Signal(int)
    busyChanged = Signal()

    def __init__(self) -> None:
        super().__init__()
        self._busy = False

    @Property(bool, notify=busyChanged)
    def busy(self) -> bool:
        return self._busy

    @Slot(str, str, result=bool)
    def signIn(self, username: str, password: str) -> bool:
        return bool(username and password)

    @Slot(int, result="QVariantList")
    def rows(self, count: int) -> list:
        self.saved.emit(count)
        return [{"id": index} for index in range(count)]

    @Slot()
    def outer(self) -> None:
        self.rows(2)

    @Slot()
    def slow(self) -> None:
        time.sleep(0.02)

    @Slot(int)
    def boom(self, product_id: int) -> None:
        raise RuntimeError("SMOKE traced boom")

    @Slot()
    def touch(self) -> None:
        self._busy = not self._busy
        self.busyChanged.emit()


wrapped = instrument.trace_slots(Probe)
check("every slot wrapped", wrapped == 6)
check("wrapping is idempotent", instrument.trace_slots(Probe) == 0)

probe = Probe()
probe._mizan_label = "probe"
signals = instrument.watch_signals(probe, "probe")
check("event signals watched, notifiers skipped", signals == 1)

probe.signIn("admin", "hunter2")
probe.outer()
probe.touch()
for handler in logging.getLogger().handlers:
    handler.flush()
traced = read(log_dir / "debug.log")

check("a call is traced", "> probe.signIn(" in traced)
check("its return is traced", "< probe.signIn = True" in traced)
check("the duration is traced", "< probe.signIn = True 0." in traced)
check("argument names are used", "username='admin'" in traced)
check("the password is redacted", "password=***" in traced)
check("no password reaches any file", "hunter2" not in traced)
check("a result is summarised, not dumped", "< probe.rows = [2 x {id=0} …]" in traced)
check("nesting is indented", "  > probe.rows(count=2)" in traced)
check("a signal is traced", "~ probe.saved(2)" in traced)
check("a signal inside a call is indented", "  ~ probe.saved(2)" in traced)
check("a notify signal is not traced", "probe.busyChanged" not in traced)
check("the trace channel is named", "mizan.trace" in traced)
check("the trace stays out of app.log", "> probe.signIn(" not in read(log_dir / "app.log"))

# A slot that blocks the GUI thread is a defect the trace alone would bury.
from app import diagnostics as diag_module

previous_slow = diag_module.SLOW_MS
diag_module.SLOW_MS = 5.0
probe.slow()
diag_module.SLOW_MS = previous_slow
for handler in logging.getLogger().handlers:
    handler.flush()
check("a slow call is promoted to WARNING",
      "slow: probe.slow blocked the GUI thread" in read(log_dir / "app.log"))

# A slot that raises: recorded with its arguments, and still raises. Both halves
# matter — the bridge's own error handling has to keep working unchanged.
raised = False
try:
    probe.boom(552)
except RuntimeError:
    raised = True
for handler in logging.getLogger().handlers:
    handler.flush()
boom_text = read(log_dir / "errors.log")
check("a raising slot still raises", raised)
check("the raise is in errors.log", "! probe.boom(product_id=552) raised" in boom_text)
check("with the traceback", "SMOKE traced boom" in boom_text)

# Off means off: no wrappers at all, so a tuned deployment pays nothing.
diag_module.set_trace(False)


class Quiet(QObject):
    @Slot()
    def ping(self) -> None:
        pass


check("MIZAN_TRACE off installs nothing", instrument.install(Quiet())[0] == 0)
diag_module.set_trace(True)

# -- 9. what QML logs through app.diag ---------------------------------------
from app.bridge.diag import Diag

surface = Diag()
surface.action("PosPage", "pay pressed", {"total": 1245.41})
surface.note("StockCountDialog", "sheet has 240 lines")
surface.warn("ImportDialog", "no column chosen for the name")
surface.fail("PageHost", "products: would not load")
for handler in logging.getLogger().handlers:
    handler.flush()
qml_text = read(log_dir / "debug.log")
check("a QML action is traced", "* PosPage: pay pressed {total=1245.41}" in qml_text)
check("a QML note is traced", ". StockCountDialog: sheet has 240 lines" in qml_text)
check("a QML warning reaches app.log",
      "qml ImportDialog: no column chosen" in read(log_dir / "app.log"))
check("a QML failure reaches errors.log",
      "qml PageHost: products: would not load" in read(log_dir / "errors.log"))
check("diag names the log directory", surface.logDir == str(log_dir))
check("diag does not trace itself", not getattr(Diag.action, "__mizan_traced__", False))

# -- 10. the real bridge ------------------------------------------------------
# The claim this whole file exists to support: not "the mechanism works" but
# "it is installed on everything QML can reach". Skipped rather than failed when
# pos/ is not beside pos2/ — that is a checkout problem, not a defect here.
try:
    from app.bridge.root import App
except ImportError as exc:  # pragma: no cover - depends on the checkout
    print(f"SKIP: bridge unavailable ({exc})")
else:
    bridge = App()
    found = instrument.controllers(bridge)
    traced_slots = 0
    for label, controller in found:
        traced_slots += sum(
            1
            for value in vars(type(controller)).values()
            if getattr(value, "__mizan_traced__", False)
        )
    check("every controller is reachable", len(found) >= 24)
    check("the whole bridge is traced", traced_slots > 150)
    check("app.diag is exposed to QML", bridge.diag is not None)
    check("the trace is announced in app.log",
          "action trace installed:" in read(log_dir / "app.log"))

# -- verdict ------------------------------------------------------------------
print(f"\nlog dir: {log_dir}")
if failures:
    print(f"{len(failures)} FAILURES: {failures}")
    raise SystemExit(1)
print("ALL CHECKS PASSED")

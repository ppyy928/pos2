"""One wire that makes every action in this app leave a record.

THE PROBLEM THIS SOLVES

`app/diagnostics.py` gives the process four log files and catches everything
that *breaks*: uncaught exceptions, thread crashes, Qt's own warnings, native
faults. What it could not give is the other half of a bug report — what the
operator did. The bridge is 175 slots across 20 controllers, and a slot that
worked wrote nothing at all, so `errors.log` said "cannot save: UNIQUE
constraint failed" with no way to know which screen, which record, or what was
typed into it. Worse, a slot that raised *outside* its own `try` never even got
that far: PySide prints the traceback to stderr, and on a windowed exe stderr
does not exist.

Editing 175 slots to log their own arguments would have been 175 chances to
forget one, plus a permanent tax on every new slot. So the trace is installed
rather than written: `install()` walks the bridge, replaces every `@Slot` with a
wrapper around the original function, and connects a logger to every signal.
Nothing in `app/bridge/` knows this file exists.

WHY REPLACING THE CLASS ATTRIBUTE IS ENOUGH

A `@Slot` is registered in the class's QMetaObject when the class is created, and
the entry holds the method *name*. When QML calls `app.products.save(...)`, Qt
resolves that name against the instance at call time — so an attribute swapped in
after the class was built is what actually runs, for QML calls, for
`QMetaObject.invokeMethod`, and for plain Python calls alike. Verified for
value-returning slots (`result="QVariantList"`), `QVariant` slots and raising
slots; `functools.wraps` carries the `_slots` metadata across so the function
stays indistinguishable from the one Qt registered.

WHAT ONE LINE LOOKS LIKE

    > products.save(data={name='Cola', price=120}, id=0)
      > taxes.rate(id=2)
      < taxes.rate = 19 0.3ms
    ~ products.saved(552)
    < products.save 7.4ms

`>` a call, `<` its return, `!` a call that raised, `~` a signal, `*` something
QML reported through `app.diag`. Indentation is call depth, which is what turns
a flat file into the causal chain: the till asked the catalogue, which asked the
tax table. Everything is DEBUG, so the whole trace lands in `debug.log` and
`app.log` stays the audit trail it was — except for two things that are
promoted, because they are defects rather than history: a slot that raised
(ERROR, with the traceback and the arguments) and a call that blocked the GUI
thread for longer than `SLOW_MS` (WARNING).

WHAT IS DELIBERATELY NOT TRACED

* `@Property` getters. QML re-reads a bound property whenever anything it
  depends on changes; tracing those would produce a file measured in megabytes
  per minute and hide every line that matters.
* Property *notification* signals (`busyChanged`, `rowsChanged`, …), for the
  same reason — one per keystroke in a search field. `MIZAN_TRACE_NOTIFY=1`
  turns them on for the rare session that needs them. Signals that report an
  event (`saleFinished`, `rejected`, `held`, `scanMissed`) are always traced;
  the two are told apart by asking the QMetaObject which signals are a
  property's notifier, so a signal that is both is treated as the notifier it is.
* Passwords and PINs. The parameter *names* of every wrapped slot are read once,
  at wrap time, and any name containing `password`, `pin`, `secret`, `token` or
  `hash` logs `***` forever after — `auth.login(username, password)` is the slot
  this exists for.
"""

from __future__ import annotations

import functools
import inspect
import logging
import threading
import time

from PySide6.QtCore import QCoreApplication, QMetaMethod, QObject, QThread

from . import diagnostics
from .diagnostics import brief, trace

#: Set on a class once its slots are wrapped, and on each wrapper. Checked
#: against `cls.__dict__` rather than with getattr, so a subclass of an already
#: instrumented controller is still instrumented itself.
MARK = "__mizan_traced__"

#: QObject's own signals. Neither is an action, and `destroyed` fires while the
#: object is being torn down, which is the worst possible moment to call back
#: into Python.
_SKIP_SIGNALS = frozenset({"destroyed", "objectNameChanged"})

#: Call depth, per thread: the bridge runs slots on the GUI thread and finishes
#: workers on pool threads, and interleaving their indentation would describe a
#: nesting that never happened.
_local = threading.local()

#: Connections are kept alive by Qt, but a receiver that is only referenced by
#: the connection has been collected out from under a signal often enough in
#: PySide's history to be worth one list.
_receivers: list[object] = []


def install(root: QObject) -> tuple[int, int]:
    """Trace every slot and every signal reachable from the bridge root.

    Called from `App.__init__`, which is the one place every entry point goes
    through — `run.py`, `tools/dialog_shots.py`, a test harness — so no launcher
    can forget it. Returns (slots wrapped, signals watched) for the log line and
    for `tools/log_check.py`.

    Controllers are discovered from the QMetaObject rather than listed: they are
    exactly the `Property(QObject, constant=True)` entries on `App`, so a
    controller added to `root.py` tomorrow is traced without touching this file.
    """
    if not diagnostics.TRACE:
        diagnostics.log.info("action trace off (MIZAN_TRACE)")
        return (0, 0)

    slots = 0
    signals = 0
    for label, controller in controllers(root):
        # The label is the name QML uses (`app.products` -> "products"), stored
        # on the instance because the wrapper lives on the class: `Sales` and
        # `Returns` are separate classes, but one class serving two instances
        # would otherwise report both under one name.
        try:
            controller._mizan_label = label
        except AttributeError:  # __slots__ somewhere in the hierarchy
            pass
        slots += trace_slots(type(controller))
        signals += watch_signals(controller, label)

    diagnostics.log.info(
        "action trace installed: %s slots, %s signals, %s controllers",
        slots, signals, len(controllers(root)),
    )
    return (slots, signals)


def controllers(root: QObject) -> list[tuple[str, QObject]]:
    """`[("app", root), ("products", <Products>), …]` — the bridge, flattened."""
    found: list[tuple[str, QObject]] = [("app", root)]
    meta = root.metaObject()
    for index in range(meta.propertyCount()):
        prop = meta.property(index)
        name = prop.name()
        if name == "objectName":
            continue
        try:
            value = prop.read(root)
        except Exception:  # noqa: BLE001 - a getter that throws is its own bug
            diagnostics.log.debug(
                "cannot read app.%s while installing the trace", name, exc_info=True
            )
            continue
        if isinstance(value, QObject):
            found.append((name, value))
    return found


def trace_slots(cls: type) -> int:
    """Wrap every `@Slot` this class declares. Idempotent, once per class."""
    if cls.__dict__.get(MARK):
        return 0

    declared = _slot_names(cls)
    wrapped = 0
    for name, attribute in list(vars(cls).items()):
        if name not in declared or not inspect.isfunction(attribute):
            continue
        if attribute.__dict__.get(MARK):
            continue
        setattr(cls, name, _traced(cls, name, attribute))
        wrapped += 1

    setattr(cls, MARK, True)
    return wrapped


def watch_signals(obj: QObject, label: str) -> int:
    """Log every event signal this object emits, without touching an `emit`."""
    meta = obj.metaObject()
    notifiers = _notifier_names(meta)
    seen: set[str] = set()
    watched = 0

    for index in range(meta.methodCount()):
        method = meta.method(index)
        if method.methodType() != QMetaMethod.MethodType.Signal:
            continue
        name = bytes(method.name()).decode()
        if name in seen or name in _SKIP_SIGNALS:
            continue
        seen.add(name)
        if name in notifiers and not diagnostics.TRACE_NOTIFY:
            continue

        signal = getattr(obj, name, None)
        if signal is None or not hasattr(signal, "connect"):
            continue
        receiver = _emission(f"{label}.{name}")
        try:
            signal.connect(receiver)
        except (RuntimeError, TypeError):
            # An overload this build cannot bind to. One untraced signal is not
            # worth a failed launch.
            continue
        _receivers.append(receiver)
        watched += 1

    return watched


def action(source: str, what: str, detail: object = None) -> None:
    """Record something that happened outside Python: a QML action.

    `app.diag` and `Mizan/Diag.qml` are the callers. Same channel, same
    indentation and the same file as the slot trace, so a dialog opening and the
    query it fires appear in the order they happened rather than in two logs
    that have to be zipped together by timestamp.
    """
    if not trace.isEnabledFor(logging.DEBUG):
        return
    if detail is None or detail == "":
        trace.debug("%s* %s: %s", _pad(), source, what)
    else:
        trace.debug("%s* %s: %s %s", _pad(), source, what, brief(detail))


def note(source: str, message: str) -> None:
    """A fact from QML that is not an action: a state, a count, a decision."""
    if trace.isEnabledFor(logging.DEBUG):
        trace.debug("%s. %s: %s", _pad(), source, message)


# ---------------------------------------------------------------------------
# INTERNALS
# ---------------------------------------------------------------------------
def _traced(cls: type, name: str, func):
    """The wrapper. Everything here runs on the GUI thread, per call."""
    fallback = cls.__name__.lower()
    params = _parameters(func)

    @functools.wraps(func)
    def traced(self, *args, **kwargs):
        # The one cheap test that turns the whole mechanism off: with the trace
        # disabled by configuration this is a plain call through.
        if not trace.isEnabledFor(logging.DEBUG):
            return func(self, *args, **kwargs)

        who = f"{getattr(self, '_mizan_label', fallback)}.{name}"
        depth = getattr(_local, "depth", 0)
        pad = "  " * depth
        trace.debug("%s> %s(%s)", pad, who, _arguments(params, args, kwargs))

        _local.depth = depth + 1
        started = time.perf_counter()
        try:
            result = func(self, *args, **kwargs)
        except Exception:
            elapsed = (time.perf_counter() - started) * 1000.0
            # The arguments are repeated here on purpose: this record is the one
            # that gets read in errors.log, where the `>` line above it is not.
            trace.error(
                "%s! %s(%s) raised after %.1fms",
                pad, who, _arguments(params, args, kwargs), elapsed,
                exc_info=True,
            )
            raise
        finally:
            _local.depth = depth

        elapsed = (time.perf_counter() - started) * 1000.0
        if result is None:
            trace.debug("%s< %s %.1fms", pad, who, elapsed)
        else:
            trace.debug("%s< %s = %s %.1fms", pad, who, brief(result), elapsed)

        if elapsed >= diagnostics.SLOW_MS and _on_gui_thread():
            # Promoted out of the trace and into app.log: this is the project's
            # "no long work on the GUI thread" rule failing, and the window was
            # frozen for that long.
            diagnostics.log.warning(
                "slow: %s blocked the GUI thread for %.0fms", who, elapsed
            )
        return result

    traced.__dict__[MARK] = True
    return traced


def _emission(who: str):
    def emitted(*args) -> None:
        if not trace.isEnabledFor(logging.DEBUG):
            return
        thread = threading.current_thread().name
        where = "" if thread == "MainThread" else f" [{thread}]"
        trace.debug(
            "%s~ %s(%s)%s",
            _pad(), who, ", ".join(brief(value) for value in args), where,
        )

    return emitted


def _pad() -> str:
    return "  " * getattr(_local, "depth", 0)


def _parameters(func) -> tuple[tuple[str, bool], ...]:
    """`(("username", False), ("password", True))` — computed once, per slot.

    Names come from the Python signature rather than from the QMetaObject, which
    only knows types. `self` is dropped, so positions line up with the `*args`
    the wrapper receives.
    """
    try:
        parameters = list(inspect.signature(func).parameters.values())[1:]
    except (TypeError, ValueError):
        return ()
    return tuple((p.name, diagnostics.is_secret(p.name)) for p in parameters)


def _arguments(params, args, kwargs) -> str:
    parts = []
    for index, value in enumerate(args):
        if index < len(params):
            name, hidden = params[index]
        else:
            name, hidden = f"#{index}", False
        parts.append(f"{name}={'***' if hidden else brief(value)}")
    for key, value in kwargs.items():
        hidden = diagnostics.is_secret(str(key))
        parts.append(f"{key}={'***' if hidden else brief(value)}")
    return ", ".join(parts)


def _slot_names(cls: type) -> set[str]:
    """The names Qt registered as slots for this class.

    Read from the QMetaObject rather than from a private attribute on the
    function, so this keeps working if PySide renames `_slots`. Inherited
    QObject slots (`deleteLater`) appear here too and are harmless: they are not
    in `vars(cls)`, so nothing wraps them.
    """
    meta = getattr(cls, "staticMetaObject", None)
    if meta is None:
        return set()
    names = set()
    for index in range(meta.methodCount()):
        method = meta.method(index)
        if method.methodType() == QMetaMethod.MethodType.Slot:
            names.add(bytes(method.name()).decode())
    return names


def _notifier_names(meta) -> set[str]:
    """Signals that exist to notify a property, asked of Qt rather than guessed.

    Guessing by an "…Changed" suffix would be wrong in both directions: `Till`
    notifies half its properties through a signal called `changed`, and a real
    event could be called `languageChanged`.
    """
    names = set()
    for index in range(meta.propertyCount()):
        prop = meta.property(index)
        if not prop.hasNotifySignal():
            continue
        names.add(bytes(prop.notifySignal().name()).decode())
    return names


def _on_gui_thread() -> bool:
    app = QCoreApplication.instance()
    return app is not None and QThread.currentThread() == app.thread()

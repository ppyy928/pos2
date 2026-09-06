"""Diagnostics: logging, crash capture, and where they live on disk.

pos2 used to run blind. Every bridge slot already reported failures to the
operator through ``rejected`` / ``_set_error`` — but the string was the whole
story: the traceback was dropped at the ``except`` line, and nothing anywhere
remembered the sentence five minutes later. On a windowed exe, where stderr
does not exist, a crash left no trace at all. This module is the fix.

Layout under the log directory (``pos2/logs/`` in development, ``<exe>/logs``
when frozen):

- ``app.log``     — INFO+ (2 MB, 3 backups): the run's story and the business
                    audit trail (logins, sales, cash sessions, backups).
- ``debug.log``   — full DEBUG firehose (4 MB, 2 backups), including Qt
                    warnings, every soft fallback and the whole action trace.
                    The first place to look when reproducing a bug.
- ``errors.log``  — ERROR/CRITICAL only (1 MB, 3 backups), with tracebacks.
                    What the support question is usually about.
- ``crash.log``   — ``faulthandler`` dumps of native crashes (segfaults inside
                    Qt's C++). ``sys.excepthook`` cannot see those; Python is
                    already gone when they happen.

Logger taxonomy, matching pos/ so both apps read the same way: ``mizan``
(infrastructure, this module's ``log``), ``mizan.business`` (audit events),
``mizan.trace`` (the action trace — see ``app/instrument.py``) and ``mizan.qt``
(qInstallMessageHandler output). The borrowed pos/ modules log to
``mizan.business`` already, so their records land here without any change.

Crash coverage: ``sys.excepthook`` (main thread), ``threading.excepthook``
(background threads), the Qt message handler (C++ warnings) and faulthandler
(native faults) all land in these files with full context.

Frozen-build readiness (``sys.frozen``, e.g. PyInstaller): the log directory
resolves next to the executable first — a portable POS keeps its logs with its
database — and falls back to ``%LOCALAPPDATA%/MIZAN/logs`` when that spot is
not writable (Program Files), then to the temp directory. ``MIZAN_LOG_DIR``
overrides all of it, for support scenarios ("run with logs over there").

Switches, all environment variables so they work on a frozen build with no
command line to speak of (``run.py`` also exposes ``--debug`` / ``--no-trace``):

- ``MIZAN_LOG_DIR``      — put the four files somewhere else.
- ``MIZAN_TRACE=0``      — turn the action trace off entirely.
- ``MIZAN_TRACE_NOTIFY`` — also trace property-notification signals. Off by
                           default: ``busyChanged`` fires on every load and
                           would bury the events that mean something.
- ``MIZAN_SLOW_MS``      — the "this blocked the GUI thread" threshold, in ms.
- ``MIZAN_TRACE_WIDTH``  — how much of a value a trace line may show.
"""

from __future__ import annotations

import logging
import os
import platform
import sys
import tempfile
import threading
from logging.handlers import RotatingFileHandler
from pathlib import Path

#: Set by init(); the directory every diagnostics file lives in.
LOG_DIR = Path()

#: Infrastructure logger. Business events go through business() instead.
log = logging.getLogger("mizan")

#: The action trace: one line per QML→Python call, per signal a controller
#: emits, and per screen the operator opens. DEBUG throughout, so the whole
#: story lands in debug.log and app.log stays the audit trail it was.
#: Written by app/instrument.py and by app.diag (from QML).
trace = logging.getLogger("mizan.trace")

_FORMAT = "%(asctime)s | %(levelname)-8s | %(process)d | %(name)s | %(message)s"
_DATEFMT = "%Y-%m-%d %H:%M:%S"

_initialized = False


def _flag(name: str, default: bool) -> bool:
    """An environment switch, read the way an operator would write it."""
    raw = os.environ.get(name)
    if raw is None:
        return default
    return raw.strip().lower() not in ("", "0", "no", "off", "false")


def _number(name: str, default: float) -> float:
    try:
        return float(os.environ.get(name) or default)
    except ValueError:
        return default


#: Is the action trace installed at all. Off costs nothing: instrument.install()
#: wraps nothing, so the slots QML calls are the original functions.
TRACE = _flag("MIZAN_TRACE", True)

#: Trace property-notification signals too (busyChanged, rowsChanged, …).
TRACE_NOTIFY = _flag("MIZAN_TRACE_NOTIFY", False)

#: A call that took longer than this and ran on the GUI thread gets a WARNING of
#: its own — in app.log, not just the trace. 50ms rather than the project's
#: ~1ms budget for a DB call: this is the threshold where a human sees the
#: window stop repainting, and a warning nobody can act on is noise.
SLOW_MS = _number("MIZAN_SLOW_MS", 50.0)

#: How much of one value a trace line may show. A cart with 40 lines and a
#: report with 5000 rows both pass through here on their way to QML, and a log
#: file that holds them entire is a log file nobody opens twice.
TRACE_WIDTH = int(_number("MIZAN_TRACE_WIDTH", 120))

#: Argument names whose value never reaches a log line, at any level. Matched as
#: substrings of the parameter name, so `password`, `new_password` and
#: `passwordConfirm` are all covered by one entry.
SECRET_NAMES = ("password", "passwd", "pwd", "pin", "secret", "token", "hash")

# faulthandler keeps the file object alive by reference; this module has to
# hold it for the process lifetime or the dump file gets closed mid-crash.
_crash_file = None


def init(debug: bool = False) -> Path:
    """Install every handler once; returns the log directory.

    Safe to call again: the second call is a no-op that returns the same
    directory (``--check`` and tests both run paths that already passed here).
    ``debug`` raises the *console* verbosity to DEBUG; the files always keep
    their fixed split, so debug.log is complete whatever the launch mode.
    """
    global _initialized, LOG_DIR
    if _initialized:
        return LOG_DIR
    _initialized = True

    LOG_DIR = _resolve_log_dir()

    root = logging.getLogger()
    root.setLevel(logging.DEBUG)
    # Quiet noisy third parties; their warnings still pass (WARNING >=).
    logging.getLogger("sqlalchemy.engine").setLevel(logging.WARNING)

    formatter = logging.Formatter(_FORMAT, datefmt=_DATEFMT)

    app_handler = WindowsSafeRotatingFileHandler(
        LOG_DIR / "app.log", maxBytes=2 * 1024 * 1024, backupCount=3, encoding="utf-8"
    )
    app_handler.setLevel(logging.INFO)
    app_handler.setFormatter(formatter)

    debug_handler = WindowsSafeRotatingFileHandler(
        LOG_DIR / "debug.log", maxBytes=4 * 1024 * 1024, backupCount=2, encoding="utf-8"
    )
    debug_handler.setLevel(logging.DEBUG)
    debug_handler.setFormatter(formatter)

    error_handler = WindowsSafeRotatingFileHandler(
        LOG_DIR / "errors.log", maxBytes=1024 * 1024, backupCount=3, encoding="utf-8"
    )
    error_handler.setLevel(logging.ERROR)
    error_handler.setFormatter(formatter)

    # Windows consoles default to a legacy codepage (cp1252/cp1256) that cannot
    # encode arrows or mixed-script names — reconfigure to UTF-8 with
    # replacement so a log line can never crash the logging machinery itself.
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):  # non-reconfigurable stream (frozen/piped)
        pass
    console = logging.StreamHandler(sys.stderr)
    console.setLevel(logging.DEBUG if debug else logging.INFO)
    console.setFormatter(formatter)

    root.addHandler(app_handler)
    root.addHandler(debug_handler)
    root.addHandler(error_handler)
    root.addHandler(console)

    sys.excepthook = _excepthook
    threading.excepthook = _thread_excepthook
    _install_qt_message_handler()
    _enable_faulthandler()

    # The environment banner: the first thing support reads off a machine.
    log.info("logging initialized → %s", LOG_DIR)
    log.info(
        "environment: python=%s | platform=%s | qt=%s | frozen=%s",
        platform.python_version(),
        platform.platform(),
        _qt_version(),
        bool(getattr(sys, "frozen", False)),
    )
    log.info("invoked as: %s", " ".join(sys.argv))
    log.info(
        "diagnostics: trace=%s notify=%s slow=%.0fms width=%s",
        TRACE, TRACE_NOTIFY, SLOW_MS, TRACE_WIDTH,
    )
    return LOG_DIR


def business() -> logging.Logger:
    """Logger for business events (logins, sales, cash, backups, …)."""
    return logging.getLogger("mizan.business")


def active_exc() -> bool | tuple:
    """The exception being handled, or False when none is.

    The bridge's error path emits a signal or sets a property from inside an
    ``except`` block; slots wired with a direct connection therefore still run
    inside that block's dynamic extent, where ``sys.exc_info()`` is live. That
    is what lets one central tap log full tracebacks for hundreds of ``except``
    sites without touching them. Outside an except block the answer is False,
    which logging renders as no traceback.
    """
    info = sys.exc_info()
    return info if info[0] is not None else False


def set_trace(enabled: bool) -> None:
    """Turn the action trace on or off before the bridge is built.

    run.py's ``--no-trace`` lands here. After ``instrument.install()`` has run
    this has no effect — the wrappers are already in place — which is deliberate:
    a switch that can be flipped mid-shift is a switch that makes two halves of
    one log file mean different things.
    """
    global TRACE
    TRACE = bool(enabled)


def is_secret(name: str) -> bool:
    """Is this parameter name one whose value must never be written down."""
    lowered = (name or "").lower()
    return any(needle in lowered for needle in SECRET_NAMES)


def brief(value: object, width: int | None = None) -> str:
    """One short, safe, bounded line for any value crossing the QML boundary.

    Three properties matter more than fidelity, because this runs inside every
    traced call:

    * **Bounded.** A 5000-row report and a 40-line cart both pass through here.
      Collections are summarised by length and by their first entry rather than
      walked, so the cost of a trace line does not grow with the payload.
    * **Total.** ``repr`` on a half-built ORM object or a QJSValue holding a
      JS exception can itself raise, and a logger that crashes the till is worse
      than no logger. Every path is caught.
    * **Readable.** ``{name='Cola', price=120.0}`` beats
      ``<PySide6.QtQml.QJSValue object at 0x…>`` by the entire point of the
      exercise: a QJSValue is what a QML form payload actually arrives as, so it
      is converted rather than named.
    """
    limit = TRACE_WIDTH if width is None else width
    try:
        return _brief(value, limit, depth=0)
    except Exception:  # noqa: BLE001 - a log line must never raise
        return f"<unprintable {type(value).__name__}>"


def _brief(value: object, limit: int, depth: int) -> str:
    if value is None or isinstance(value, (bool, int)):
        return repr(value)
    if isinstance(value, float):
        return f"{value:g}"
    if isinstance(value, (bytes, bytearray)):
        return f"<{len(value)} bytes>"
    if isinstance(value, str):
        if len(value) <= limit:
            return repr(value)
        return f"{value[:limit]!r}…+{len(value) - limit}"

    # A JS object/array handed to a QVariant slot. as_dict() does this same
    # conversion downstream, so showing the converted value is showing what the
    # slot is about to work with.
    to_variant = getattr(value, "toVariant", None)
    if callable(to_variant):
        try:
            return _brief(to_variant(), limit, depth)
        except Exception:  # noqa: BLE001
            return "<QJSValue>"

    if isinstance(value, dict):
        if depth >= 2:
            return f"{{{len(value)} keys}}"
        shown = list(value.items())[:4]
        body = ", ".join(
            f"{key}=" + ("***" if is_secret(str(key))
                         else _brief(item, limit // 2, depth + 1))
            for key, item in shown
        )
        rest = len(value) - len(shown)
        return "{" + body + (f", +{rest}" if rest > 0 else "") + "}"

    if isinstance(value, (list, tuple, set)):
        count = len(value)
        if count == 0:
            return "[]"
        if depth >= 2:
            return f"[{count}]"
        first = next(iter(value))
        head = _brief(first, limit // 2, depth + 1)
        return f"[{head}]" if count == 1 else f"[{count} x {head} …]"

    # A QObject prints as its class, which is the only useful part of it here.
    name = type(value).__name__
    text = repr(value)
    if text.startswith("<") and " object at " in text:
        return f"<{name}>"
    return text if len(text) <= limit else f"{text[:limit]}…"


class WindowsSafeRotatingFileHandler(RotatingFileHandler):
    """Rotate normally, but fall back to a per-process file on Windows locks.

    Windows cannot rename ``app.log`` while another running POS/test process
    still has it open, and a standard RotatingFileHandler answers that with a
    traceback for every subsequent log record. On the first sharing violation
    this process switches to ``app.<pid>.log`` (same directory, same rotation
    policy), so logging stays silent and lossless with no extra dependencies.
    """

    def doRollover(self) -> None:
        try:
            super().doRollover()
        except PermissionError:
            if self.stream:
                self.stream.close()
                self.stream = None
            path = Path(self.baseFilename)
            self.baseFilename = str(
                path.with_name(f"{path.stem}.{os.getpid()}{path.suffix}")
            )


def _resolve_log_dir() -> Path:
    """First writable candidate wins; see the module docstring for the order.

    A POS that cannot write a log line anywhere must still start — the till
    outranks the telemetry — so the chain ends at the temp directory, which is
    writable on every Windows profile.
    """
    candidates: list[Path] = []
    override = os.environ.get("MIZAN_LOG_DIR")
    if override:
        candidates.append(Path(override))
    if getattr(sys, "frozen", False):  # PyInstaller & friends
        candidates.append(Path(sys.executable).resolve().parent / "logs")
    else:
        # app/diagnostics.py -> pos2/logs. Kept beside the project in dev so
        # a bug report is one directory to zip.
        candidates.append(Path(__file__).resolve().parents[1] / "logs")
        candidates.append(Path(tempfile.gettempdir()) / "mizan-logs")
        return _first_writable(candidates)
    # Frozen and the exe dir refused (Program Files): per-user app data, then
    # the shared temp dir.
    local = os.environ.get("LOCALAPPDATA")
    if local:
        candidates.append(Path(local) / "MIZAN" / "logs")
    candidates.append(Path(tempfile.gettempdir()) / "mizan-logs")
    return _first_writable(candidates)


def _first_writable(candidates: list[Path]) -> Path:
    for candidate in candidates:
        try:
            candidate.mkdir(parents=True, exist_ok=True)
            probe = candidate / ".write-test"
            probe.touch()
            probe.unlink()
            return candidate
        except OSError:
            continue
    # Unreachable in practice: the temp candidate always succeeds. If it ever
    # does not, send records nowhere rather than crash the till on every line.
    return Path(tempfile.gettempdir())


def _qt_version() -> str:
    try:
        from PySide6 import __version__ as pyside_version
        from PySide6.QtCore import qVersion

        return f"{qVersion()} (PySide6 {pyside_version})"
    except Exception:  # noqa: BLE001 - PySide6 may not be imported yet
        return "unavailable"


def _excepthook(exc_type, exc_value, exc_tb) -> None:
    log.critical("uncaught exception", exc_info=(exc_type, exc_value, exc_tb))


def _thread_excepthook(args: threading.ExceptHookArgs) -> None:
    log.critical(
        "uncaught exception in thread %r",
        getattr(args.thread, "name", "?"),
        exc_info=(args.exc_type, args.exc_value, args.exc_traceback),
    )


def _install_qt_message_handler() -> None:
    """Route Qt's own qDebug/qWarning/qCritical output into the log files.

    Catches layout/QML/painter warnings that otherwise vanish on frozen builds
    where stderr is invisible — and everything QML's ``console.*`` prints,
    which arrives here too.
    """
    try:
        from PySide6.QtCore import QtMsgType, qInstallMessageHandler
    except Exception:  # noqa: BLE001 - PySide6 may not be imported yet
        return

    level_map = {
        QtMsgType.QtDebugMsg: logging.DEBUG,
        QtMsgType.QtInfoMsg: logging.INFO,
        QtMsgType.QtWarningMsg: logging.WARNING,
        QtMsgType.QtCriticalMsg: logging.ERROR,
        QtMsgType.QtFatalMsg: logging.CRITICAL,
    }
    qt_log = logging.getLogger("mizan.qt")

    def handler(msg_type, context, message) -> None:
        qt_log.log(level_map.get(msg_type, logging.WARNING), "%s", message)

    qInstallMessageHandler(handler)


def _enable_faulthandler() -> None:
    """Dump native crashes (segfaults in Qt's C++) to logs/crash.log.

    Python-level hooks cannot report a fault that kills the interpreter, so the
    interpreter itself writes the dump: enabled once, here, before any Qt
    window exists. A missing/unwritable file only means no dump — never a
    failed launch.
    """
    global _crash_file
    try:
        import faulthandler

        # Opened without a context manager on purpose: the handle has to stay
        # open for the process lifetime — closing it would close the very file
        # a crash is about to be dumped into.
        _crash_file = open(LOG_DIR / "crash.log", "a", encoding="utf-8")  # noqa: SIM115
        faulthandler.enable(file=_crash_file, all_threads=True)
    except Exception:  # noqa: BLE001 - diagnostics must never block startup
        _crash_file = None

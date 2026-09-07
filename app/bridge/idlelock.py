"""The idle lock, behind `security.auto_lock_minutes`.

A till is a cash drawer with a screen on it, and the moment its operator walks
away it is everybody's till. The setting was in pos's DEFAULT_SETTINGS and in
its Settings screen, and nothing in either front end ever read it: a shop that
asked for a lock after five minutes got a shop that never locked.

WHY THE WATCHER IS AN EVENT FILTER AND NOT A QML TIMER
------------------------------------------------------

QML cannot see the whole application's input. A Timer in the window would have
to be reset by handlers on every control, and the one that is forgotten — a
dialog's keypad, a context menu — is the one that locks a till mid-sale. The
application object sees every key, click and wheel before any of them is
delivered, so one read-only filter over it is the whole attendance record. The
scanner works this way for the same reason (see its own header).

WHY THE LOCK IS `session.end()` AND NOT A SIGNAL OF ITS OWN
----------------------------------------------------------

The session is the one object whose `changed` the shell already treats as "who
is at the till moved": signing in adopts a user, and `end()` adopts nobody. The
shell watches it (Main.qml), shows the login layer, and the next operator signs
in exactly the way the first one did — no second lock screen to build, and no
way for this module to get the locked state out of step with the session's.

WHY THE MINUTES ARE READ EVERY TICK
-----------------------------------

The Settings screen that changes them does not tell this module, and the same
key was unread for two front ends by being cached once at startup. A tick is
ten seconds and the read is one indexed row; a lock that ignores the knob it
was given is worse than no lock, because it teaches the shop the knob does
nothing — which is exactly what this file exists to stop being true.
"""

from __future__ import annotations

import time

from PySide6.QtCore import Property, QEvent, QObject, QTimer, Signal

from .. import diagnostics
from . import legacy

#: How often to look, in milliseconds. Ten seconds: fine enough that "five
#: minutes" means five minutes, coarse enough that one indexed read per tick is
#: nothing.
_TICK_MS = 10_000

#: What counts as being at the till. Presses and wheels — not moves: a pointer
#: drifting across an unattended screen is not attendance, and a mouse jitter
#: keeping a till unlocked all night is this feature's most embarrassing
#: failure mode.
_ACTIVITY = {
    QEvent.Type.KeyPress,
    QEvent.Type.KeyRelease,
    QEvent.Type.MouseButtonPress,
    QEvent.Type.MouseButtonRelease,
    QEvent.Type.Wheel,
    QEvent.Type.TabletPress,
    QEvent.Type.TouchBegin,
}


class IdleLock(QObject):
    """Watches for absence, and ends the session when it has gone on long
    enough. Installed by the bridge, like the scanner."""

    #: The lock fired — for the log's audit trail, which is the record of who
    #: had the till and when that stopped being true.
    locked = Signal()

    def __init__(self, session: QObject, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._session = session
        self._last = time.monotonic()
        self._installed = False

        self._timer = QTimer(self)
        self._timer.setInterval(_TICK_MS)
        self._timer.timeout.connect(self._tick)

    @Property(bool, constant=True)
    def installed(self) -> bool:
        return self._installed

    def install(self, target: QObject) -> None:
        """Watch every input the application sees. Called once, by the bridge."""
        if target is None or self._installed:
            return
        target.installEventFilter(self)
        self._installed = True
        self._timer.start()

    # -- the filter -------------------------------------------------------
    def eventFilter(self, watched: QObject, event: QEvent) -> bool:
        # Never consumed: this filter is attendance, not policy, and the one
        # thing it must never do is eat the click it is recording.
        if event.type() in _ACTIVITY:
            self._last = time.monotonic()
        return False

    # -- the clock --------------------------------------------------------
    def _minutes(self) -> float:
        """The knob, read live. 0 — the default — means "never lock"."""
        try:
            database = legacy.database()
            return float(database.get_setting(
                "security.auto_lock_minutes", "0") or 0)
        except Exception:  # noqa: BLE001
            # No store, no lock: a database-less build (dialog_shots, a
            # preview harness) must not lock anything, and DEBUG is where a
            # fallthrough belongs.
            diagnostics.log.debug("auto_lock_minutes unreadable", exc_info=True)
            return 0.0

    def _tick(self) -> None:
        minutes = self._minutes()
        if minutes <= 0:
            return
        if not self._session.signedIn:
            return
        idle = (time.monotonic() - self._last) / 60.0
        if idle < minutes:
            return
        # The moment of the lock is the moment of the last input, not the
        # moment of this tick: the difference is up to ten seconds, and the
        # audit trail should not round an operator's absence up.
        diagnostics.business().info(
            "auto-locked after %d minute(s) idle", round(idle)
        )
        self._last = time.monotonic()
        self._session.end()
        self.locked.emit()

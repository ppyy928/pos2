"""Sign-in, and what the signed-in operator may do.

    LoginPage.qml           app.auth.login(username, password)
                            -> succeeded(user) | failed(message)
    RowActions, pages       app.session.can("products.manage")

WHY THE CHECK RUNS OFF THE GUI THREAD

pos hashes passwords with PBKDF2-HMAC-SHA256 at 600 000 iterations, which is the
point of PBKDF2 and costs 0.2-0.3 s per attempt on desktop hardware. On the GUI
thread that is a visibly frozen window on every login, including every mistyped
one, so the check goes to the global thread pool and the answer comes back as a
signal. LoginPage already renders `busy` while it waits.

WHY A WRONG PASSWORD SENDS AN EMPTY MESSAGE

`failed("")` means "these credentials are not valid" and LoginPage supplies its
own translated sentence for it. A non-empty message is an infrastructure failure
— a missing or locked database — and is shown verbatim, because "invalid
username or password" would be a lie in that case and would send the operator
looking for the wrong problem.
"""

from __future__ import annotations

from PySide6.QtCore import Property, QObject, QRunnable, QThreadPool, Signal, Slot

from .. import diagnostics
from . import legacy


class Session(QObject):
    """A QObject face on pos's own session singleton.

    The permission rule lives in `mizan_pos1.core.session` — admin passes
    everything, an unguarded action passes, anything else has to be in the
    employee's list — and it stays there. This adds property notification, which
    is what QML needs and a plain Python object cannot provide.
    """

    changed = Signal()

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        #: Bumped by adopt(). See the `revision` property for why it exists.
        self._revision = 0
        try:
            self._store = legacy.session_user()
        except ImportError as exc:
            # No pos/ means no authentication at all, so refusing every
            # permission is the accurate answer rather than a defensive one.
            diagnostics.log.warning("no session layer (%s)", exc)
            self._store = None

    # -- what QML reads ---------------------------------------------------
    @Property("QVariant", notify=changed)
    def user(self) -> object:
        return None if self._store is None else self._store.user

    @Property(bool, notify=changed)
    def signedIn(self) -> bool:
        return self._store is not None and self._store.user is not None

    @Property(str, notify=changed)
    def name(self) -> str:
        return "" if self._store is None else self._store.name

    @Property(str, notify=changed)
    def role(self) -> str:
        return "" if self._store is None else self._store.role

    # -- what QML calls ---------------------------------------------------
    @Property(int, notify=changed)
    def revision(self) -> int:
        """A number that changes whenever the session does.

        `can()` below is a slot, and a QML binding that only calls a slot has
        nothing to re-evaluate on: it runs once, when the item is built, and never
        again. That is invisible on a page created after login and fatal on the one
        created before it — the till is the default screen, so its permission-gated
        controls evaluated against an empty session and stayed hidden for the whole
        shift, reappearing only if the operator navigated away and back and the page
        was rebuilt.

        Reading this first anchors such a binding to `changed`:

            readonly property bool mayEdit:
                session && session.revision >= 0 && session.can("products.manage")
        """
        return self._revision

    @Slot(str, result=bool)
    def can(self, permission: str) -> bool:
        if self._store is None:
            return False
        # "" is how QML spells "this action carries no permission"; pos's rule
        # reads that as None and passes it.
        return self._store.has_permission(permission or None)

    @Slot()
    def end(self) -> None:
        self.adopt(None)

    # -- wiring -----------------------------------------------------------
    def adopt(self, user: object) -> None:
        """Record the operator Auth just verified. Called by the bridge, not QML:
        a session that QML could write to would be a permission system QML could
        grant itself."""
        if self._store is not None:
            self._store.set_user(user)
        self._revision += 1
        self.changed.emit()


class Auth(QObject):
    succeeded = Signal("QVariant")
    failed = Signal(str)
    busyChanged = Signal()

    #: Private, and the only thing the worker thread touches. Emitting a signal
    #: across threads is queued by Qt, which is what moves the answer back onto
    #: the GUI thread.
    _finished = Signal("QVariant", str)

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._busy = False
        self._task: _LoginTask | None = None
        self._finished.connect(self._settle)

    @Property(bool, notify=busyChanged)
    def busy(self) -> bool:
        return self._busy

    @Slot(str, str)
    def login(self, username: str, password: str) -> None:
        if self._busy:
            # One attempt at a time. Enter held down on a slow hash would
            # otherwise queue a dozen of them.
            return
        self._set_busy(True)
        # Held, and not auto-deleted: a QRunnable handed to the pool as a
        # temporary is owned by C++ from that moment, and the Python wrapper it
        # came from is not. Keeping the reference and letting Python free it is
        # the version of this that cannot become a dangling pointer. `_busy`
        # guarantees the previous one has finished before it is replaced.
        self._task = _LoginTask(self, username, password)
        self._task.setAutoDelete(False)
        QThreadPool.globalInstance().start(self._task)

    def _settle(self, user: object, error: str) -> None:
        self._set_busy(False)
        if error:
            self.failed.emit(error)
        elif user is None:
            self.failed.emit("")
        else:
            self.succeeded.emit(user)

    def _set_busy(self, value: bool) -> None:
        if self._busy == value:
            return
        self._busy = value
        self.busyChanged.emit()


class _LoginTask(QRunnable):
    """One verification attempt, on a pool thread."""

    def __init__(self, auth: Auth, username: str, password: str) -> None:
        super().__init__()
        self._auth = auth
        self._username = username
        self._password = password

    def run(self) -> None:
        try:
            database = legacy.database()
            user = database.authenticate(self._username, self._password)
        except Exception as exc:  # noqa: BLE001
            # Anything from a missing file to a locked database. It has to reach
            # the operator: a silent exception on a pool thread would leave the
            # login screen spinning forever. The traceback belongs in errors.log
            # — the username, never the password, travels with it.
            diagnostics.log.exception(
                "login attempt failed on the pool: user=%r", self._username
            )
            self._auth._finished.emit(None, str(exc))
            return
        self._auth._finished.emit(user, "")

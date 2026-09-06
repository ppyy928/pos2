"""The barcode scanner, behind `app.scanner`.

A USB scanner is a keyboard that types faster than a person and ends with Return.
pos decodes that burst with an application-wide event filter over layout-
independent virtual key codes, because a scan must not land in whichever field
happens to have focus — and because a French keyboard layout turns the digit row
into symbols, which is what `decode_vk` exists to undo.

    installed()             the filter is on and the till is listening
    scanned(code)           a burst ending in Return
    enabled                 off while a screen wants the keyboard verbatim

WHY IT NEVER SWALLOWS A KEY
---------------------------
pos's decoder consumes the keys of a burst and re-inserts them into the one
QLineEdit it was built for, undoing them if the burst turns out to be typing. That
works because it is attached to a single field. Attached to the whole application
it cannot work: `SCAN_MAX_GAP_MS` is 100ms and `decode_vk` covers letters, so brisk
human typing *is* a burst by those rules — and consuming it means a login form you
cannot type into. That is exactly what happened.

So this filter is read-only over the keyboard: every character passes through to
whatever has focus, the buffer only watches. The single event it consumes is the
Return that completes a real scan, because that Return belongs to the scan rather
than to the focused field. What the burst typed into that field is then removed —
and only ever the code itself, checked against the end of the field's own text.

WHY IT IS OFF ON THE LOGIN SCREEN
---------------------------------
Nothing is scannable before somebody signs in, and a password is the one string that
must never be read as a code. The shell binds `enabled` to being signed in, and
password fields are skipped outright.
"""

from __future__ import annotations

from PySide6.QtCore import Property, QEvent, QObject, Signal, Slot
from PySide6.QtGui import QGuiApplication

from .. import diagnostics
from . import legacy


class Scanner(QObject):
    scanned = Signal(str)
    installedChanged = Signal()
    enabledChanged = Signal()

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._buffer = None
        self._decode = None
        self._enabled = True
        self._installed = False

        try:
            module = legacy.scanner()
            self._buffer = module.ScanBuffer()
            self._decode = module.decode_key
        except Exception as exc:  # noqa: BLE001
            # No decoder means no scanner support, and the till still works: its
            # search box takes a burst the ordinary way, because a scanner ends
            # with Return and that field acts on Return.
            diagnostics.log.warning("no scanner decoder (%s)", exc)

    @Property(bool, notify=installedChanged)
    def installed(self) -> bool:
        return self._installed

    def _get_enabled(self) -> bool:
        return self._enabled

    def _set_enabled(self, value: bool) -> None:
        if self._enabled == bool(value):
            return
        self._enabled = bool(value)
        if self._buffer is not None:
            self._buffer.reset()
        self.enabledChanged.emit()

    enabled = Property(bool, _get_enabled, _set_enabled, notify=enabledChanged)

    @Slot(QObject)
    def install(self, target: QObject) -> None:
        """Watch every key the application sees. Called once, by the bridge."""
        if self._buffer is None or target is None or self._installed:
            return
        target.installEventFilter(self)
        self._installed = True
        self.installedChanged.emit()

    # -- the filter -------------------------------------------------------
    def eventFilter(self, watched: QObject, event: QEvent) -> bool:
        if not self._enabled or self._buffer is None:
            return False
        if event.type() != QEvent.Type.KeyPress:
            return False

        from PySide6.QtCore import Qt

        if event.isAutoRepeat():
            # A held key repeats inside the burst gap and is not a scanner.
            return False

        if self._password_focused():
            self._buffer.reset()
            return False

        if event.key() in (Qt.Key.Key_Return, Qt.Key.Key_Enter):
            code = self._buffer.complete()
            if not code:
                return False
            # The burst typed itself into whatever had focus, because nothing was
            # consumed on the way in. Take exactly the code back off the end — and
            # only if it is there, so a field that never received it is untouched.
            self._unwind(code)
            self.scanned.emit(code)
            # The Return belongs to the scan.
            return True

        char = self._decode(event) if self._decode else None
        if char is None:
            # `decode_key` reads nativeVirtualKey, which is a Windows concept: it
            # is 0 on other platforms and for synthetic events. A digit in the
            # event's own text is still a digit, so that is the fallback — and it
            # is restricted to digits on purpose, because the whole reason the VK
            # path exists is that a French layout's digit row produces symbols in
            # text(). Those are ignored rather than mistaken for a code.
            text = event.text()
            if len(text) == 1 and text.isdigit():
                char = text

        if char is None:
            # Anything that is not a scannable character ends a burst: a scanner
            # does not press Shift or Tab in the middle of a code.
            self._buffer.reset()
            return False

        self._buffer.feed(char)
        # Never consumed. Typing must keep working everywhere, and a scan is only
        # recognised at its Return.
        return False

    # -- internals --------------------------------------------------------
    def _focus(self) -> QObject | None:
        application = QGuiApplication.instance()
        return application.focusObject() if application is not None else None

    def _password_focused(self) -> bool:
        """A password field is never a scanner's target, and its text is the one
        string that must not be edited from out here.

        Detected by comparing `text` with `displayText`: a masked field shows dots
        for its characters, so the two differ the moment anything is in it. The
        obvious test — reading `echoMode` — cannot be used, because it is a QML enum
        that PySide has no converter for and reading it *raises* inside the event
        filter, which would take the keystroke with it.

        Before the first character both are empty and this answers False. Nothing is
        lost by that: no key is ever consumed, and the second character is enough to
        stop a burst from forming.
        """
        focus = self._focus()
        if focus is None:
            return False
        try:
            text = focus.property("text")
            shown = focus.property("displayText")
        except RuntimeError:
            # The focus object died between the focus query and the read. DEBUG:
            # a Qt lifecycle moment that arrives with a deleted C++ pointer, not
            # a defect — but it belongs in debug.log like every other fallback.
            diagnostics.log.debug("password probe on a deleted focus object")
            return False
        if not isinstance(text, str) or not isinstance(shown, str):
            return False
        return text != shown

    def _unwind(self, code: str) -> None:
        focus = self._focus()
        if focus is None:
            return
        text = focus.property("text")
        if not isinstance(text, str) or not text.endswith(code):
            return
        focus.setProperty("text", text[: -len(code)])

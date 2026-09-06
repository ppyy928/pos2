import QtQuick
import FluentControls
import Mizan

/*
 * A place for toasts, because a Toast cannot be declared once and reused.
 *
 *     ToastHost { id: toasts }
 *     ...
 *     toasts.show(Strings.t("toast.saved", "Saved"), Severity.success)
 *
 * FluentControls' Toast ends its exit animation with `root.destroy()` — it is
 * built to be created per message and to clean itself up. Declared as a child of
 * a page, that means the first dismissal leaves the id pointing at a destroyed
 * object and every message after it goes nowhere. This creates one per message
 * instead, which is the shape the control was written for.
 *
 * One at a time: a new message closes the one on screen rather than stacking.
 * A queue of four pills over a till's dock is noise, and the last message is the
 * one that matters.
 */
Item {
    id: host

    /* Where the pill sits. A page with a dock underneath raises it. */
    property int bottomMargin: Tokens.spacing.xl

    /* Above the page content; the shell's own dialogs sit higher still. */
    z: 50

    anchors.fill: parent

    /* Nothing here takes input: the host is a positioning frame, and the only
       interactive thing in a toast is its own dismiss button. */
    property Item current: null

    Component {
        id: pill
        Toast {}
    }

    function show(message, severity) {
        if (message === undefined || message === "")
            return

        /* Every toast is recorded, whatever it says. This is the single most
           useful line in a support log: it is what the operator actually read,
           in the operator's own language, at the moment they read it — which is
           the sentence a bug report is written from. Severity travels with it so
           a refusal ("the cart is empty") is not filed as a failure. */
        Diag.action("ToastHost", "toast " + _severityName(severity), message)

        if (current)
            current.close()          // fades, then destroys itself

        var toast = pill.createObject(host, {
            message: message,
            severity: severity === undefined ? Severity.info : severity
        })
        if (!toast) {
            Diag.fail("ToastHost", "could not build a toast for: " + message)
            return
        }

        /* Bindings rather than values, so the pill stays centred and clear of
           the bottom edge when the window is resized under it. */
        toast.x = Qt.binding(function () { return (host.width - toast.width) / 2 })
        toast.y = Qt.binding(function () {
            return host.height - toast.height - host.bottomMargin
        })

        current = toast
        toast.show()
    }

    /* Severity is an enum, and an enum in a log line is a number nobody can
       read six months later. */
    function _severityName(severity) {
        switch (severity) {
        case Severity.success: return "success"
        case Severity.caution: return "caution"
        case Severity.error:   return "error"
        default:               return "info"
        }
    }
}

import QtQuick
import QtQuick.Controls as QC
import FluentControls
import Mizan

/*
 * The base every one of this app's dialogs stands on.
 *
 * WHY IT EXISTS: WIDTH
 *
 * FluentDialog sizes itself from its content and caps that at 900px — sensible for
 * a confirmation, wrong for anything with a table or two columns in it. On a
 * 1920px till that left every form squeezed into the middle third of the screen
 * with its own scrollbars. A dialog here asks for the width it needs and gets it,
 * bounded only by the window it is in.
 *
 *     AppDialog {
 *         preferredWidth: 1320       // what the layout wants
 *         preferredHeight: 900       // optional; content decides when 0
 *     }
 *
 * Both are *preferences*: the window is the ceiling, so a form designed for a wide
 * screen still opens on a small one — narrower, scrolling, but whole.
 *
 * WHY IT EXISTS: ESCAPE
 *
 * FluentDialog defaults to `Popup.NoAutoClose`, which is right for "are you sure"
 * and wrong for everything else: a picker, a form or a report has to close on
 * Escape. Setting it once here means no dialog forgets, and the two confirmations
 * that genuinely should not close by accident say so themselves.
 */
FluentDialog {
    id: dialog

    /* What the content wants. The window is the ceiling. */
    property int preferredWidth: 720
    /* 0 means "as tall as the content", which is what a short form wants. A number
       caps it, for a dialog whose body scrolls. */
    property int preferredHeight: 0

    /* How much room there is to fill. The dialog's parent is the window-level host
       it was created in (or the overlay, once Qt has centred it there), and either
       one is the content area. Both are checked because which of them answers
       depends on how far through opening the dialog is — and a zero from either is
       not an answer, so the last resort is a sane desktop width rather than a
       dialog collapsed to its minimum. */
    readonly property real roomWidth: {
        if (parent && parent.width > 0)
            return parent.width
        if (QC.Overlay.overlay && QC.Overlay.overlay.width > 0)
            return QC.Overlay.overlay.width
        return 1600
    }

    readonly property real roomHeight: {
        if (parent && parent.height > 0)
            return parent.height
        if (QC.Overlay.overlay && QC.Overlay.overlay.height > 0)
            return QC.Overlay.overlay.height
        return 900
    }

    /* A margin so a full-width dialog still reads as a dialog rather than as the
       screen. */
    readonly property int breathing: 2 * Tokens.spacing.xxl

    width: Math.max(480, Math.min(preferredWidth, roomWidth - breathing))
    height: Math.min(preferredHeight > 0 ? preferredHeight : implicitHeight,
                     roomHeight - breathing)

    modal: true
    closePolicy: QC.Popup.CloseOnEscape
}

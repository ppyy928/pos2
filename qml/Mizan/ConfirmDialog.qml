import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * The question asked before something irreversible happens.
 *
 *   ┌──────────────────────────────────────────────────────┐
 *   │ 🗑  Delete this sale?                                │
 *   │                                                      │
 *   │ TRX-0174 is removed and everything it did is undone.  │
 *   │ ┌──────────────────────────────────────────────────┐ │
 *   │ │ Lines                                    4 · 7   │ │
 *   │ │ Total                                12 480,00   │ │
 *   │ │ Out of the drawer                    10 000,00   │ │
 *   │ │ Off Amine Bekkar's account            2 480,00   │ │
 *   │ └──────────────────────────────────────────────────┘ │
 *   │ ⚠ 3 of the delivered units have been sold since.      │
 *   │                                                      │
 *   │                    [ Keep it ]  [ Delete the sale ]  │
 *   └──────────────────────────────────────────────────────┘
 *
 * WHY THIS EXISTS
 *
 * Every destructive action in this app used to ask with a FluentDialog, one sentence
 * and a pair of Yes/No buttons. Three things were wrong with that, and the empty-cart
 * confirmation had all three: the sentence came from a catalogue key whose text names
 * a slot ("Remove all {count} line(s)…") while the caller used `Strings.t`, which does
 * no substitution — so the operator read a literal `{count}`; the dialog said what
 * would be removed but never what it was worth or who it belonged to; and "Yes" is
 * not the name of an act, so the button carried no warning at all.
 *
 * So a confirmation here is four things, in the order they are read: what is about to
 * happen (title), what that means (body), the figures it will change (`facts`), and
 * what cannot be undone cleanly (`warnings`). The button says the verb.
 *
 * FACTS, NOT A PARAGRAPH
 *
 * `facts` is the same `[{ label, value, tone }]` shape PaymentEntry already uses, for
 * the same reason: a figure in a label/value row is read across a counter, and a
 * translator cannot break a layout that has no placeholder in it. A fact whose value
 * is empty is dropped, so a caller can pass a row for a customer that may not exist
 * without branching.
 *
 * WARNINGS ARE NOT REFUSALS, AND `blocker` IS
 *
 * A warning is amber: the act is allowed, and the operator is the only one who can
 * judge whether the correction is worth it — a delivery whose goods have since been
 * sold is the case this was built for. `blocker` is different: it names a rule the
 * data layer will refuse on, so the confirm button is not drawn at all. Letting
 * somebody press Delete and answering with a toast is a worse way to say the same
 * thing.
 *
 * TWO OPT-INS FOR THE QUESTIONS THAT ARE NOT DESTRUCTIVE
 *
 * `extraText` adds a third button — a way to fix the cause instead of overriding it —
 * and `suppressText` adds a "do not show again" box. Both are off unless a caller
 * asks, and both exist for the same kind of question: one that guards a judgement
 * rather than an irreversible act. See their own notes below.
 */
AppDialog {
    id: confirm

    // =====================================================================
    // API
    // =====================================================================
    /* "danger" (default) or "caution". Drives the icon tint and the confirm
       button's ink — not a red fill: the style resolves hover, pressed and
       disabled through one colour property, and replacing its background would
       opt this button out of all of it. See GlyphButton's note. */
    property string tone: "danger"

    property string glyph: "ic_fluent_delete_20_regular"
    property string body: ""

    /* [{ label, value, tone }] — the figures this act changes. */
    property var facts: []

    /* Sentences that qualify the act. Amber, bulleted, never a refusal. */
    property var warnings: []

    /* Set to a sentence when the act cannot proceed at all. The confirm button
       disappears and only the way out is left. */
    property string blocker: ""

    property string confirmText: ""
    property string cancelText: ""

    /*
     * A SECOND WAY OUT, FOR A QUESTION THAT HAS ONE.
     *
     * Most confirmations are a fork: do it, or do not. A few are a fork with a third
     * road that fixes the cause instead of overriding it — "there is none of this on
     * the shelf" is answered better by putting some on the shelf than by either
     * button. Set `extraText` and it appears between Cancel and the verb, outlined,
     * so it reads as an alternative rather than as the answer. Left empty — the
     * normal case — nothing is drawn and no caller notices this exists.
     */
    property string extraText: ""
    property string extraGlyph: ""
    signal extraRequested()

    /*
     * "DO NOT SHOW AGAIN", FOR A QUESTION THAT IS ALLOWED TO STOP ASKING.
     *
     * Only for confirmations that guard a judgement the shop can settle once — never
     * for a destructive act, where every instance is its own decision. Set
     * `suppressText` to offer it; the caller reads `suppressed` in its `confirmed`
     * handler and persists the answer itself, because where that preference lives is
     * a fact about the caller's own controller and not about this dialog.
     *
     * Pressing Cancel deliberately does NOT apply it: an operator backing out of a
     * question has not answered it, and silently muting it on the way out would be
     * the one outcome they cannot see or undo.
     */
    property string suppressText: ""
    readonly property bool suppressed: suppressBox.checked

    /* The operator said yes. The caller acts; this only asks. */
    signal confirmed()

    // =====================================================================
    // FRAME
    // =====================================================================
    preferredWidth: 620

    /* The measure every wrapping Text inside is given. A Text that reads the
       dialog's own width closes a binding loop, because FluentDialog sizes itself
       from its content — the same reason every other dialog here states a
       measure. */
    readonly property int measure: 500

    readonly property color ink: Tokens.toneInk(tone)
    readonly property color tint: Tokens.toneFill(tone)

    readonly property var shownFacts: {
        var out = []
        for (var i = 0; i < facts.length; i++) {
            var fact = facts[i]
            if (fact && fact.value !== undefined && fact.value !== "")
                out.push(fact)
        }
        return out
    }

    function accept_() {
        confirm.confirmed()
        confirm.close()
    }

    /* Unticked on every open. The dialog is usually one long-lived instance that a
       page fills and reopens, and a box still carrying a tick the operator backed
       out of last time would apply an answer they had abandoned. */
    onOpened: suppressBox.checked = false

    contentItem: ColumnLayout {
        spacing: Tokens.spacing.md

        // -----------------------------------------------------------------
        // WHAT IS ABOUT TO HAPPEN
        // -----------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: confirm.measure
            spacing: Tokens.spacing.md

            Rectangle {
                Layout.alignment: Qt.AlignTop
                width: 48
                height: 48
                radius: 24
                color: confirm.tint

                Icon {
                    anchors.centerIn: parent
                    icon: confirm.glyph
                    size: Tokens.icon.md
                    color: confirm.ink
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                /* The dialog's own title, in the body: AppDialog draws `title`
                   above this, and repeating it would be the same words twice. The
                   title stays the question; this is the consequence. */
                Text {
                    Layout.fillWidth: true
                    visible: confirm.body !== ""
                    text: confirm.body
                    wrapMode: Text.WordWrap
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.bodyLarge
                    color: Fluent.textPrimary
                }
            }
        }

        // -----------------------------------------------------------------
        // WHAT IT CHANGES
        // -----------------------------------------------------------------
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredWidth: confirm.measure
            visible: confirm.shownFacts.length > 0
            implicitHeight: factRows.implicitHeight + 2 * Tokens.spacing.md
            radius: Tokens.radius.md
            color: Fluent.subtleSecondary
            border.width: 1
            border.color: Fluent.dividerBorder

            ColumnLayout {
                id: factRows
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.spacing.md
                anchors.rightMargin: Tokens.spacing.md
                spacing: Tokens.spacing.xs

                Repeater {
                    model: confirm.shownFacts

                    delegate: RowLayout {
                        required property var modelData

                        Layout.fillWidth: true
                        spacing: Tokens.spacing.md

                        Text {
                            Layout.fillWidth: true
                            text: modelData.label
                            wrapMode: Text.WordWrap
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.body
                            color: Fluent.textSecondary
                        }

                        Text {
                            /* LTR-marked: a figure reads left to right in Arabic
                               too, and a mixed string would otherwise reorder. */
                            text: "\u200e" + modelData.value
                            font.family: Tokens.font.family
                            font.pixelSize: Tokens.font.bodyLarge
                            font.weight: Font.DemiBold
                            color: modelData.tone !== undefined
                                   && modelData.tone !== ""
                                   ? Tokens.toneInk(modelData.tone)
                                   : Fluent.textPrimary
                        }
                    }
                }
            }
        }

        // -----------------------------------------------------------------
        // WHAT CANNOT BE UNDONE CLEANLY
        // -----------------------------------------------------------------
        Repeater {
            model: confirm.warnings

            delegate: RowLayout {
                required property var modelData

                Layout.fillWidth: true
                Layout.preferredWidth: confirm.measure
                spacing: Tokens.spacing.sm

                Icon {
                    Layout.alignment: Qt.AlignTop
                    icon: "ic_fluent_warning_20_regular"
                    size: Tokens.icon.sm
                    color: Tokens.warning
                }

                Text {
                    Layout.fillWidth: true
                    text: modelData
                    wrapMode: Text.WordWrap
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                    color: Fluent.textPrimary
                }
            }
        }

        // -----------------------------------------------------------------
        // WHY IT CANNOT HAPPEN AT ALL
        // -----------------------------------------------------------------
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredWidth: confirm.measure
            visible: confirm.blocker !== ""
            implicitHeight: blockerRow.implicitHeight + 2 * Tokens.spacing.sm
            radius: Tokens.radius.md
            color: Tokens.dangerTint
            border.width: 1
            border.color: Qt.rgba(Tokens.danger.r, Tokens.danger.g,
                                  Tokens.danger.b, 0.28)

            RowLayout {
                id: blockerRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.spacing.md
                anchors.rightMargin: Tokens.spacing.md
                spacing: Tokens.spacing.sm

                Icon {
                    Layout.alignment: Qt.AlignTop
                    icon: "ic_fluent_dismiss_circle_20_regular"
                    size: Tokens.icon.sm
                    color: Tokens.danger
                }

                Text {
                    Layout.fillWidth: true
                    text: confirm.blocker
                    wrapMode: Text.WordWrap
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                    font.weight: Font.DemiBold
                    color: Fluent.textPrimary
                }
            }
        }

        // -----------------------------------------------------------------
        // THE ANSWER
        // -----------------------------------------------------------------
        /* Above the buttons and outside the row, so it is read before the verb is
           pressed rather than beside it — and so a long label wraps into the
           dialog's measure instead of squeezing the buttons. */
        QC.CheckBox {
            id: suppressBox
            Layout.fillWidth: true
            Layout.preferredWidth: confirm.measure
            visible: confirm.suppressText !== "" && confirm.blocker === ""
            text: confirm.suppressText
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.caption
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.sm

            Item { Layout.fillWidth: true }

            GlyphButton {
                glyph: "ic_fluent_dismiss_20_regular"
                outlined: true
                text: confirm.cancelText !== ""
                      ? confirm.cancelText
                      : (confirm.blocker !== ""
                         ? Strings.t("action.close", "Close")
                         : Strings.t("action.cancel", "Cancel"))
                onClicked: confirm.close()
            }

            /* The third road. Outlined like Cancel because it is not the answer to
               the question asked — it is a way to make the question go away. */
            GlyphButton {
                visible: confirm.extraText !== ""
                outlined: true
                glyph: confirm.extraGlyph
                text: confirm.extraText
                onClicked: {
                    confirm.extraRequested()
                    confirm.close()
                }
            }

            GlyphButton {
                visible: confirm.blocker === ""
                glyph: confirm.glyph
                text: confirm.confirmText !== ""
                      ? confirm.confirmText
                      : Strings.t("action.delete", "Delete")
                /* The verb in the tone's own ink rather than an accent fill. The
                   style drives its whole label — glyph and text — through
                   `icon.color`, so assigning that one property colours both and
                   leaves hover, pressed and disabled where the style resolves
                   them. */
                icon.color: confirm.ink
                onClicked: confirm.accept_()
            }
        }
    }
}

import QtQuick
import QtQuick.Controls as QC
import FluentControls
import Mizan

/*
 * The four "there is nothing to show" states, ported from
 * pos/app/widgets/states.py::EmptyState.
 *
 *   empty        the table is legitimately empty — no products yet
 *   no_results   a filter or search matched nothing
 *   error        the load failed; offers Retry
 *   permission   the operator may not see this
 *
 * Each variant owns a glyph, an ink and a default title/body, and a page can
 * override any of the text. `empty` usually also passes `actionText` so the
 * state doubles as the first call to action ("Add your first product").
 *
 * WHERE THIS IS USED — AND WHERE IT IS NOT
 *
 * pos puts the table and this view in a QStackedWidget and swaps between them.
 * DataTable here already draws its own empty message for the ordinary case, so a
 * page reaches for this view for the three states a table cannot express on its
 * own: a failed load, a permission refusal, and the first-run invitation.
 *
 * GLYPH NAMES
 *
 * Every name in Fluent's icon font is spelled _20_ no matter what size it is
 * drawn at — the font is variable and Icon.size does the scaling. There is no
 * `inbox` in this set, so `empty` uses `box`. An unknown name renders as
 * nothing at all rather than failing, which is exactly why these four are
 * checked against FluentSystemIcons-Index.js and not guessed.
 */
Item {
    id: view

    // =====================================================================
    // API
    // =====================================================================
    property string variant: "empty"

    /* Empty string means "use the variant's default", which is how pos spells
       it (`title if title is not None else default_title`). */
    property string title: ""
    property string body: ""

    /* A primary action. Shown only when set — pos gates it the same way. */
    property string actionText: ""

    signal retryRequested()
    signal actionRequested()

    // =====================================================================
    // VARIANTS
    // =====================================================================
    readonly property string glyph: {
        switch (variant) {
        case "no_results": return "ic_fluent_search_20_regular"
        case "error":      return "ic_fluent_warning_20_regular"
        case "permission": return "ic_fluent_shield_lock_20_regular"
        }
        return "ic_fluent_box_20_regular"
    }

    readonly property color ink: {
        switch (variant) {
        case "no_results": return Fluent.textSecondary
        case "error":      return Tokens.danger
        case "permission": return Tokens.danger
        }
        return Fluent.textTertiary
    }

    readonly property string defaultTitle: {
        switch (variant) {
        case "no_results": return Strings.t("state.no_results.title", "No matches")
        case "error":      return Strings.t("state.error.title", "Could not load")
        case "permission": return Strings.t("state.permission.title", "Not allowed")
        }
        return Strings.t("state.empty.title", "Nothing here yet")
    }

    readonly property string defaultBody: {
        switch (variant) {
        case "no_results":
            return Strings.t("state.no_results.body", "Try a different search or clear the filters.")
        case "error":
            return Strings.t("state.error.body", "Something went wrong. Try again.")
        }
        return ""
    }

    readonly property string shownTitle: title !== "" ? title : defaultTitle
    readonly property string shownBody: body !== "" ? body : defaultBody

    // =====================================================================
    // LAYOUT
    // =====================================================================
    Column {
        anchors.centerIn: parent
        /* Room to breathe, and a ceiling on the body's line length — centred
           text is hard to read across a full-width table. */
        width: Math.min(parent.width - 2 * Tokens.size.pagePadding, 520)
        spacing: Tokens.spacing.md

        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            icon: view.glyph
            size: Tokens.icon.xl
            color: view.ink
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: view.shownTitle
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.subtitle
            font.weight: Font.DemiBold
            color: Fluent.textPrimary
            wrapMode: Text.WordWrap
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: view.shownBody !== ""
            text: view.shownBody
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.body
            color: Fluent.textSecondary
            wrapMode: Text.WordWrap
        }

        /* Both buttons in one row, so a first-run state can offer the action and
           an error can offer Retry without either shifting the block's centre. */
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Tokens.spacing.sm
            visible: actionButton.visible || retryButton.visible

            QC.Button {
                id: actionButton
                visible: view.actionText !== ""
                highlighted: true      // accent fill — this is the page's primary
                height: Tokens.size.control
                text: view.actionText
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                onClicked: view.actionRequested()
            }

            QC.Button {
                id: retryButton
                /* Only an error is retryable. "No matches" is not a failure and
                   retrying it would run the same query to the same end. */
                visible: view.variant === "error"
                height: Tokens.size.control
                text: Strings.t("action.retry", "Retry")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                onClicked: view.retryRequested()
            }
        }
    }
}

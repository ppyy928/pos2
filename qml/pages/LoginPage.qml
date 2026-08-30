import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * The front door.
 *
 *   ┌────────────────────────────────────────────────┐
 *   │ ▣ MIZAN POS                                    │  wordmark, over the photo
 *   │                                                │
 *   │                ┌──────────────┐                │
 *   │   a market     │  Store Login │                │
 *   │   street at    │  [username]  │                │  one card, one column
 *   │   dusk, out    │  [password]  │                │
 *   │   of focus     │  [ Login   ] │                │
 *   │                │  En Fr ع     │                │
 *   │                └──────────────┘                │
 *   │ Version 2.4                                    │
 *   └────────────────────────────────────────────────┘
 *
 * WHAT CHANGED, AND WHY
 *
 * This was a 1040x640 card split into a white form panel and a dark brand panel
 * carrying a hand-drawn shopping bag (Mizan's BrandArt, a Canvas composition).
 * That layout existed to work around a real constraint — a flush two-pane split
 * cannot be done here, because `clip: true` on a rounded Rectangle clips
 * rectangularly and a square-cornered pane pokes out through the rounded corner —
 * and the workaround was a panel floating inside a card, which is two nested
 * surfaces to say one thing.
 *
 * A photograph removes the problem instead of routing around it. The image is the
 * whole window, so there are no panes to align and no corners to reconcile; the
 * form is one card in the middle of it; and the brand mark moves out onto the
 * photograph where it has room. One surface, one column, no illustration to keep
 * in step with the product.
 *
 * BrandArt is now unreferenced. It is left in Mizan rather than deleted — it is a
 * registered component and removing it is a separate decision from this one.
 *
 * THE PHOTOGRAPH
 *
 * `assets/login-bg.jpg` — a market street at dusk, CC0, blurred and compressed at
 * build time. Provenance, licence and the exact processing are in
 * assets/CREDITS.md. Two things about it matter here:
 *
 *   THE BLUR IS IN THE FILE.  There is no run-time blur in this build:
 *   QtQuick.Effects / MultiEffect is not verified present, which is why nothing in
 *   FluentPySide has a shadow either. So the softening is baked in.
 *
 *   THE DARKENING IS NOT.  The scrim below is QML, so it can be retuned without
 *   re-encoding a photograph — and it is what guarantees the wordmark and the
 *   version stamp stay legible over whichever image is dropped in.
 *
 * A missing or unreadable file falls back to the gradient this screen used before,
 * because a login screen that cannot be logged into is the one failure it may not
 * have.
 *
 * DEPTH WITHOUT SHADOWS
 *
 * Unchanged from the port: FluentPySide has no shadow idiom anywhere, so the card
 * separates from the photograph with surface contrast, a 1px border and a rim
 * highlight along its top edge. Over a photograph that is now doing more work than
 * it was over a flat gradient, which is why the scrim under the card is opaque
 * enough to give it a consistent ground.
 *
 * Card surfaces come from Tokens.login* rather than Fluent.cardBackground: those
 * are translucent by design — they are meant to sit over Mica — and over a
 * photograph a translucent card is an unreadable card.
 */
Item {
    id: page

    // ------------------------------------------------------------------ API
    /* Carries the employee dict from db.authenticate():
       { id, name, username, role, permissions }. */
    signal authenticated(var user)
    signal closeRequested()

    // --------------------------------------------------------------- metrics
    readonly property int cardWidth: 460
    readonly property int gutter: Tokens.size.pagePadding

    // Room for the leading icon inside a field, and for the trailing reveal
    // button. Named because both fields and both mirror cases refer to them.
    readonly property int fieldIconGutter: Tokens.spacing.md + Tokens.icon.sm + Tokens.spacing.sm
    readonly property int fieldActionGutter: Tokens.size.controlSmall + Tokens.spacing.sm

    // ----------------------------------------------------------------- state
    readonly property var auth: (typeof app !== "undefined" && app && app.auth)
                                ? app.auth : null
    readonly property bool busy: auth ? auth.busy : false
    property string errorText: ""

    /* Index order must match the Segmented labels below. */
    readonly property var languages: ["en", "fr", "ar"]

    function languageIndex() {
        var i = languages.indexOf(Strings.language)
        return i < 0 ? 0 : i
    }

    function submit() {
        if (busy)
            return

        var username = usernameField.text.trim()
        /* An empty field moves focus and says nothing else. The placeholder
           already states what goes there, and the alternative — inventing
           "Enter your username." — would mean three new catalogue entries in
           three languages to say what a blinking cursor already says. */
        if (username === "") {
            usernameField.forceActiveFocus()
            return
        }
        if (passwordField.text === "") {
            passwordField.forceActiveFocus()
            return
        }
        if (!auth) {
            /* Deliberately not translated: a build-state message that disappears
               the moment the bridge lands, not a product string. It says what is
               actually wrong — a spinner that never resolves, or a generic
               "invalid password", would both be lies. */
            errorText = "The data layer is not connected yet."
            return
        }

        errorText = ""
        /* Async on purpose: verification is PBKDF2 with a deliberately high
           iteration count, which would freeze the UI on the GUI thread. The
           result arrives on the signals below. */
        auth.login(username, passwordField.text)
    }

    Connections {
        target: page.auth
        // The bridge is built alongside these pages; tolerate it not having
        // grown both signals yet rather than filling the log with warnings.
        ignoreUnknownSignals: true

        function onSucceeded(user) {
            page.errorText = ""
            passwordField.text = ""
            page.authenticated(user)
        }

        function onFailed(message) {
            page.errorText = (message && message !== "")
                ? message
                : Strings.t("login.error", "Invalid username or password.")
            passwordField.selectAll()
            passwordField.forceActiveFocus()
        }
    }

    /* Explicit, because a default button does not fire while a text field holds
       focus — the same reason pos installs QShortcuts on this screen. */
    Shortcut {
        sequences: ["Return", "Enter"]
        enabled: page.visible
        onActivated: page.submit()
    }
    Shortcut {
        sequence: "Escape"
        enabled: page.visible
        onActivated: page.closeRequested()
    }

    Component.onCompleted: usernameField.forceActiveFocus()

    /* Small caps field label. Both fields use it, so the type treatment cannot
       drift between them. Declared before its first use: an inline component
       referenced above its own declaration is not reliably resolved. */
    component FieldLabel: QC.Label {
        Layout.fillWidth: true
        font.family: Tokens.font.family
        font.pixelSize: Tokens.font.overline
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.8
        color: Fluent.textSecondary
    }

    // ------------------------------------------------------------------------
    // Backdrop
    // ------------------------------------------------------------------------
    /* Under the photograph, not instead of it: this is what shows through while a
       178KB JPEG decodes on the loader thread, and what remains if the file is
       gone. It is the gradient this screen used before. */
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0;  color: Qt.lighter(Tokens.loginFrom, 1.25) }
            GradientStop { position: 0.42; color: Tokens.loginFrom }
            GradientStop { position: 1.0;  color: Tokens.loginTo }
        }
    }

    Image {
        id: backdrop
        anchors.fill: parent
        source: "../assets/login-bg.jpg"
        /* Crop, never letterbox: a band of gradient down one side of a photograph
           reads as a broken image. The photograph's subject is its centre, which is
           what survives a crop at any window shape. */
        fillMode: Image.PreserveAspectCrop
        /* Decoded off the GUI thread — this is the first screen the process shows,
           and a synchronous 1920px decode is a visible stall at startup. */
        asynchronous: true
        cache: true
        /* No `smooth: false`, no sourceSize: the file is 1920 wide and the window
           is smaller than that, so Qt is downscaling, which is the case its default
           filtering is good at. */
        opacity: status === Image.Ready ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Fluent.anim.speed }
        }
    }

    /*
     * The scrim, in two layers.
     *
     * A flat tint sets the floor — how dark the lightest part of any photograph is
     * allowed to be — and a gradient darkens the top and bottom bands, which is
     * where the wordmark and the version stamp sit. Doing it in one gradient would
     * mean the middle of a bright photograph stays bright, and the middle is where
     * the card goes.
     */
    Rectangle {
        anchors.fill: parent
        color: Tokens.loginTo
        opacity: 0.34
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0;  color: Qt.rgba(0, 0, 0, 0.50) }
            GradientStop { position: 0.32; color: Qt.rgba(0, 0, 0, 0.10) }
            GradientStop { position: 0.74; color: Qt.rgba(0, 0, 0, 0.18) }
            GradientStop { position: 1.0;  color: Qt.rgba(0, 0, 0, 0.60) }
        }
    }

    // ------------------------------------------------------------------------
    // Wordmark, over the photograph
    // ------------------------------------------------------------------------
    RowLayout {
        id: wordmark
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: page.gutter
        spacing: Tokens.spacing.md

        Rectangle {
            implicitWidth: 48
            implicitHeight: 48
            radius: Tokens.radius.md
            color: Tokens.brand

            Icon {
                anchors.centerIn: parent
                icon: "ic_fluent_cart_20_regular"
                size: Tokens.icon.lg
                color: Tokens.onBrand
            }
        }

        ColumnLayout {
            spacing: 0

            /* The product name comes from the catalogue, not a literal, so there is
               one place to change it. Note that the catalogue says "DZ-Retail POS"
               while the window title, the app id and this folder all say MIZAN —
               that disagreement predates this port and is settled in i18n.py. */
            QC.Label {
                text: Strings.t("app.name", "DZ-Retail POS")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.subtitle
                font.weight: Font.Bold
                font.letterSpacing: 1.2
                color: Tokens.onChrome
            }

            QC.Label {
                text: Strings.t("app.tagline", "Enterprise Smart Management System")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.caption
                color: Tokens.onChromeMuted
            }
        }

        Item { Layout.fillWidth: true }
    }

    // ------------------------------------------------------------------------
    // The card
    // ------------------------------------------------------------------------
    Rectangle {
        id: card

        anchors.centerIn: parent
        width: Math.min(parent.width - page.gutter * 2, page.cardWidth)
        /* Sized by its contents, floored so a short form does not look like a
           fragment, and capped so it never collides with the wordmark or the
           version line on a short window. */
        height: Math.min(parent.height - page.gutter * 2 - 2 * Tokens.size.command,
                         Math.max(420, form.implicitHeight + 2 * Tokens.spacing.xxl))

        radius: Tokens.radius.lg
        color: Tokens.loginSurface
        border.width: 1
        border.color: Tokens.loginBorder

        /* Rim light along the top edge — the library's own way of suggesting depth
           where it has no shadow. Inset by the corner radius so it stops before the
           rounding rather than crossing it. */
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: parent.radius
            height: 1
            color: Tokens.loginRim
            opacity: Tokens.isDark ? 1.0 : 0.7
        }

        ColumnLayout {
            id: form
            anchors.fill: parent
            anchors.margins: Tokens.spacing.xxl
            spacing: Tokens.spacing.md

            Item { Layout.fillHeight: true }

            QC.Label {
                Layout.fillWidth: true
                text: Strings.t("login.title", "Store Login")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.title
                font.weight: Font.DemiBold
                color: Fluent.textPrimary
            }

            QC.Label {
                Layout.fillWidth: true
                Layout.bottomMargin: Tokens.spacing.sm
                text: Strings.t("login.subtitle", "Access your store account")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                color: Fluent.textSecondary
                wrapMode: Text.WordWrap
            }

            FieldLabel {
                text: Strings.t("login.username", "Username")
            }

            QC.TextField {
                id: usernameField
                Layout.fillWidth: true
                Layout.preferredHeight: Tokens.size.control
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                placeholderText: Strings.t("login.username.ph",
                                           "Enter operator username")
                /* Padding does not mirror by itself the way anchors do, so the
                   gutter has to change sides explicitly for Arabic. It asks
                   Strings.rtl rather than `mirrored`: that flag belongs to Control,
                   and TextField descends from TextInput instead — reading it here is
                   a ReferenceError at run time, not a compile error. FilterBar's
                   fields ask the same question. */
                leftPadding: Strings.rtl ? Tokens.spacing.md : page.fieldIconGutter
                rightPadding: Strings.rtl ? page.fieldIconGutter : Tokens.spacing.md
                onAccepted: page.submit()

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: Tokens.spacing.md
                    icon: "ic_fluent_person_20_regular"
                    size: Tokens.icon.sm
                    color: parent.activeFocus ? Fluent.accent : Fluent.textSecondary
                }
            }

            FieldLabel {
                Layout.topMargin: Tokens.spacing.xs
                text: Strings.t("login.password", "Password")
            }

            QC.TextField {
                id: passwordField
                property bool revealed: false

                Layout.fillWidth: true
                Layout.preferredHeight: Tokens.size.control
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                echoMode: revealed ? TextInput.Normal : TextInput.Password
                placeholderText: Strings.t("login.password.ph", "Enter password")
                leftPadding: Strings.rtl ? page.fieldActionGutter : page.fieldIconGutter
                rightPadding: Strings.rtl ? page.fieldIconGutter : page.fieldActionGutter
                onAccepted: page.submit()

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: Tokens.spacing.md
                    icon: "ic_fluent_lock_closed_20_regular"
                    size: Tokens.icon.sm
                    color: parent.activeFocus ? Fluent.accent : Fluent.textSecondary
                }

                /* A MouseArea rather than a ToolButton: it is how the library
                   builds its own controls, and it keeps the hit target at exactly
                   40 inside a 48 field instead of inheriting a styled button's
                   implicit size. */
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: Tokens.spacing.xs
                    width: Tokens.size.controlSmall
                    height: Tokens.size.controlSmall
                    radius: Tokens.radius.sm
                    color: revealArea.containsMouse ? Fluent.subtleSecondary : "transparent"
                    opacity: revealArea.pressed ? 0.6 : 1.0

                    Icon {
                        anchors.centerIn: parent
                        icon: passwordField.revealed
                            ? "ic_fluent_eye_off_20_regular"
                            : "ic_fluent_eye_20_regular"
                        size: Tokens.icon.sm
                        color: Fluent.textSecondary
                    }

                    MouseArea {
                        id: revealArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: passwordField.revealed = !passwordField.revealed
                    }
                }
            }

            /* InfoBar hard-binds `width: parent.width`, which fights
               Layout.fillWidth if it goes into a layout directly. This wrapper is
               what the layout manages; the bar fills it. */
            Item {
                Layout.fillWidth: true
                Layout.topMargin: visible ? Tokens.spacing.xs : 0
                Layout.preferredHeight: visible ? errorBar.height : 0
                visible: page.errorText !== ""

                /* No title. InfoBar hides its title Label when the string is empty,
                   and the body already says the whole thing — a heading above it
                   would only be a second invented string saying "that failed"
                   twice. */
                InfoBar {
                    id: errorBar
                    severity: Severity.error
                    text: page.errorText
                    closable: false
                    timeout: -1
                }
            }

            QC.Button {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.sm
                Layout.preferredHeight: Tokens.size.command
                highlighted: true      // accent fill — brand emerald
                enabled: !page.busy
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.bodyLarge
                font.weight: Font.DemiBold
                /* Busy shows as text, not a ProgressRing: the ring's colour is
                   hardcoded to Fluent.accent, which is this button's own fill — an
                   invisible spinner. */
                text: page.busy
                    ? Strings.t("login.busy", "Signing in…")
                    : Strings.t("login.submit", "Login")
                onClicked: page.submit()
            }

            Item { Layout.fillHeight: true }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.xs
                implicitHeight: 1
                color: Fluent.divider
            }

            Segmented {
                id: langPicker
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Tokens.spacing.xs
                items: ["English", "Français", "العربية"]

                /* Segmented assigns its own currentIndex from a MouseArea, which
                   would destroy a binding placed on it — the same trap as
                   Fluent.setTheme() breaking isDark. So the link to Strings runs
                   imperatively both ways. It converges: assigning an unchanged
                   value emits nothing. */
                onCurrentIndexChanged: Strings.setLanguage(page.languages[currentIndex])
                Component.onCompleted: currentIndex = page.languageIndex()
            }

            Connections {
                target: Strings
                function onLanguageChanged() {
                    langPicker.currentIndex = page.languageIndex()
                }
            }

            QC.Button {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredHeight: Tokens.size.controlSmall
                flat: true             // subtle config, not accent
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.caption
                text: Strings.t("login.close", "Close")
                onClicked: page.closeRequested()
            }
        }
    }

    // ------------------------------------------------------------------------
    // Build stamp, over the photograph
    // ------------------------------------------------------------------------
    /* What pos puts here. It replaced a shield-and-reassurance row: that would
       have been a claim about where the data lives, and this screen is not the
       place to make one the app cannot verify. */
    QC.Label {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: page.gutter
        text: Strings.t("login.version", "Version 2.4 — Desktop edition")
        font.family: Tokens.font.family
        font.pixelSize: Tokens.font.caption
        color: Tokens.onChromeMuted
        horizontalAlignment: Text.AlignLeft
        elide: Text.ElideRight
    }
}

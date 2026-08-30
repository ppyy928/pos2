import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls

/*
 * Hosts the module pages.
 *
 * Ported from FluentPySide's NavigationView.safePush — the asynchronous
 * Qt.createComponent, the component cache and the error page are its ideas and
 * they are good ones. Two things are changed deliberately:
 *
 *  - show() REPLACES rather than pushes. The rail is a set of destinations, not
 *    a history stack; pushing them made "back" walk sideways through unrelated
 *    modules. Drill-downs inside a module still use push()/pop().
 *  - a failed component reports its errorString instead of a bare error page.
 *    Unbuilt pages are declared in Destinations.built, so anything that fails
 *    here is a genuine defect and says so.
 */
Item {
    id: host

    property string currentKey: ""
    readonly property int depth: stack.depth
    readonly property bool busy: _pending > 0

    signal pageLoaded(string key)
    signal pageFailed(string key, string message)

    property var _cache: ({})
    property int _pending: 0

    /* Switch destinations. `key` is a Destinations key. */
    function show(key) {
        var d = Destinations.byKey(key)
        if (!d) {
            console.warn("PageHost: unknown destination", key)
            return
        }
        host.currentKey = key

        if (!Destinations.isBuilt(key)) {
            stack.replace(null, placeholderPage, { destination: d })
            return
        }

        _load(Qt.resolvedUrl("../" + d.page), function (component, error) {
            if (host.currentKey !== key)
                return          // operator moved on while we were loading
            if (error) {
                stack.replace(null, failurePage,
                              { destination: d, message: error })
                host.pageFailed(key, error)
                return
            }
            stack.replace(null, component)
            host.pageLoaded(key)
        })
    }

    /* Drill down inside the current module (order detail, product editor). */
    function push(url, props) {
        _load(url, function (component, error) {
            if (error) {
                console.warn("PageHost: cannot push", url, "-", error)
                return
            }
            stack.push(component, props || {})
        })
    }

    function pop() {
        if (stack.depth > 1)
            stack.pop()
    }

    function _load(url, done) {
        var cached = _cache[url]
        if (cached && cached.status === Component.Ready) {
            done(cached, null)
            return
        }

        var component = Qt.createComponent(url, Component.Asynchronous)

        function finish() {
            if (component.status === Component.Ready) {
                _cache[url] = component
                done(component, null)
            } else {
                // Never cache a failure, or a fixed file would keep failing
                // until restart.
                delete _cache[url]
                done(null, component.errorString())
            }
        }

        if (component.status === Component.Ready
                || component.status === Component.Error) {
            finish()
            return
        }

        host._pending++
        function onStatus() {
            if (component.status === Component.Loading)
                return
            component.statusChanged.disconnect(onStatus)
            host._pending--
            finish()
        }
        component.statusChanged.connect(onStatus)
    }

    QC.StackView {
        id: stack
        anchors.fill: parent
        clip: true

        // Motion borrowed from NavigationView so page changes feel like the
        // rest of the library rather than a different app.
        replaceEnter: Transition {
            ParallelAnimation {
                NumberAnimation {
                    property: "opacity"; from: 0; to: 1
                    duration: Fluent.anim.appearance
                }
                NumberAnimation {
                    property: "y"; from: 12; to: 0
                    duration: Fluent.anim.speed
                    easing.type: Easing.OutQuint
                }
            }
        }

        replaceExit: Transition {
            NumberAnimation {
                property: "opacity"; from: 1; to: 0
                duration: Fluent.anim.appearance
            }
        }

        pushEnter: Transition {
            NumberAnimation {
                property: "opacity"; from: 0; to: 1
                duration: Fluent.anim.appearance
            }
        }

        popExit: Transition {
            NumberAnimation {
                property: "opacity"; from: 1; to: 0
                duration: Fluent.anim.appearance
            }
        }
    }

    QC.BusyIndicator {
        anchors.centerIn: parent
        running: host.busy
        visible: running
    }

    /* Shown for modules that have not been built yet. Keeps the whole shell
       navigable while pages land one at a time. */
    Component {
        id: placeholderPage

        Item {
            property var destination
            // Comfortable reading measure for a short centred message.
            readonly property int maxMeasure: 520

            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - Tokens.size.pagePadding * 2, maxMeasure)
                spacing: Tokens.spacing.lg

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: Tokens.size.posHero
                    height: Tokens.size.posHero
                    radius: Tokens.radius.lg
                    color: Tokens.tintFor(destination.key)

                    Icon {
                        anchors.centerIn: parent
                        icon: destination.icon
                        size: Tokens.icon.xl
                        color: Tokens.hueFor(destination.key)
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: destination.title
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.title
                    font.weight: Font.DemiBold
                    color: Fluent.textPrimary
                }

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: qsTr("This screen has not been rebuilt yet.")
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                    color: Fluent.textSecondary
                }
            }
        }
    }

    /* A page that exists but would not load. Shows the real reason. */
    Component {
        id: failurePage

        Item {
            property var destination
            property string message: ""
            // Wider than the placeholder: QML error strings carry long paths.
            readonly property int maxMeasure: 720

            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - Tokens.size.pagePadding * 2, maxMeasure)
                spacing: Tokens.spacing.md

                Icon {
                    Layout.alignment: Qt.AlignHCenter
                    icon: "ic_fluent_warning_20_regular"
                    size: Tokens.icon.xl
                    color: Tokens.danger
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("%1 failed to load").arg(destination.title)
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.subtitle
                    font.weight: Font.DemiBold
                    color: Fluent.textPrimary
                }

                QC.TextArea {
                    Layout.fillWidth: true
                    readOnly: true
                    wrapMode: TextEdit.Wrap
                    text: message
                    /* One name, not a list. QML's `font` value type has no
                       `families` member — that is QFont's C++ API — and
                       assigning a property the type does not have is a
                       load-time error, which on this page would mean the screen
                       that reports a broken page is itself a broken page.
                       A single family is enough: Qt substitutes per missing
                       glyph, and Consolas ships with Windows. */
                    font.family: "Consolas"
                    font.pixelSize: Tokens.font.caption
                }
            }
        }
    }
}

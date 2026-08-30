import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

FluentWindowBase {
    id: window
    width: 1350
    height: 900
    minimumWidth: 600
    minimumHeight: 450
    titleEnabled: false
    titleBarHeight: useNativeMacFrame ? 36 : Fluent.appearance.windowTitleBarHeight

    property alias navigationView: navigationView
    property alias navigationItems: navigationView.navigationItems
    property alias currentPage: navigationView.currentPage
    property alias defaultPage: navigationView.defaultPage
    property alias appLayerEnabled: navigationView.appLayerEnabled
    default property alias freeContent: freeContainer.data

    NavigationView {
        id: navigationView
        window: window
    }

    Item {
        id: freeContainer
        anchors.fill: parent
    }
}
